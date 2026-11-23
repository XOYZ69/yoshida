// Main-thread client for the render worker, plus the shapes the core returns.

import type { Placed } from "./design";
import type { EvalResult } from "./expr/live";
import type { PrintRequest } from "./exportPlan";

export type Severity = "error" | "warning" | "hint";

export type Diagnostic = {
	severity: Severity;
	code: number;
	file: string;
	path: string;
	line: number;
	col: number;
	span: [number, number];
	message: string;
	hint: string | null;
	card: string | null;
};

export type ParamType =
	| "number"
	| "integer"
	| "text"
	| "bool"
	| "color"
	| "enum"
	| "image"
	| "list";

export type Param = {
	name: string;
	type: ParamType;
	required: boolean;
	default?: unknown;
	min?: number;
	max?: number;
	max_length?: number;
	label?: string;
	note?: string;
	/** Editor section (docs: site/content/docs/params.md). */
	group?: string;
	options?: string[];
	/** List item fields: name → type (`enum` for enum fields). */
	item?: Record<string, string>;
	/** List item fields with their options and defaults. */
	item_defs?: Record<string, ItemField>;
};

export type ItemField = { type: string; options?: string[]; default?: unknown };

/** A card's own canvas values (`_width`, `_height`, `_dpi`, `_bleed` in card data). */
export type CardCanvas = {
	width?: number;
	height?: number;
	dpi?: number;
	bleed?: number;
};

export type CardInfo = {
	id: string;
	values: Record<string, unknown>;
	/** Only a card that sets its own canvas has this; the rest inherit the design's. */
	canvas?: CardCanvas;
};

export type SetInfo = {
	name: string;
	design: string;
	design_name: string;
	/** The set's group in pickers: its manifest `group`, else the design name. */
	group: string;
	cards_file: string | null;
	ok: boolean;
	params: Param[];
	cards: CardInfo[];
};

export type ProjectInfo = { name: string; sets: SetInfo[] };

export type CheckResult = { diagnostics: Diagnostic[]; project: ProjectInfo };

export type RenderResult = {
	/** Size of the bitmap in `bin`; smaller than the canvas for a proxy render. */
	width: number;
	height: number;
	/** Size of the canvas the design describes. */
	canvas_width?: number;
	canvas_height?: number;
	/** canvas.dpi times the scale; 0 when the design has no dpi. */
	dpi?: number;
	/** canvas.bleed times the scale, in bitmap pixels. */
	bleed?: number;
	diagnostics: Diagnostic[];
	missing_urls: string[];
	/** Layer bounds, when the request asked for `layout`. */
	layout?: Placed[];
	bin: Uint8Array;
};

/**
 * The render time: `now` is the UTC instant (`YYYY-MM-DDTHH:MM:SSZ`) and the
 * core derives render.date and render.time from it, with the project's
 * utc_offset. `date` is the local date of the same instant, for older cores.
 */
export type Clock = { date: string; now: string };

/** The clock at `at` (default: now). Compute once per export, per preview render. */
export function renderClock(at: Date = new Date()): Clock {
	const p2 = (n: number) => String(n).padStart(2, "0");
	const date = `${String(at.getFullYear()).padStart(4, "0")}-${p2(at.getMonth() + 1)}-${p2(at.getDate())}`;
	// Seconds precision, no milliseconds.
	const now = `${at.toISOString().slice(0, 19)}Z`;
	return { date, now };
}

export type RenderArgs = {
	set: string;
	card: number;
	date: string;
	now: string;
	preview: boolean;
	format: "rgba" | "png" | "png16";
	layout?: boolean;
	/**
	 * Bitmap pixels per canvas pixel: below 1 a proxy render for the
	 * preview, above 1 a larger export (each side at most 10000 pixels).
	 */
	scale?: number;
	/** PNG deflate level. */
	compression?: "fast" | "default" | "smallest";
	/** Draw only these layer ids (and what is inside them), without the background. */
	only?: string[];
	/** Draw everything but these layer ids. */
	except?: string[];
};

export type SvgArgs = {
	set: string;
	card: number;
	date: string;
	now: string;
	/** Pixels per canvas pixel for the parts that stay pixels (1 to 4, default 2). */
	scale?: number;
};

export type SvgResult = {
	/** The card's size in canvas pixels. */
	width: number;
	height: number;
	diagnostics: Diagnostic[];
	missing_urls: string[];
	/** The SVG file; empty when nothing could be drawn. */
	bin: Uint8Array;
};

/** A name an expression can use, with its type (`number`, `list`, ...). */
export type ScopeSymbol = {
	name: string;
	type: string;
	/** Params: the param type (`enum`, `integer`, ...) and enum options. */
	kind?: string;
	options?: string[];
	/** Lists and list items: their fields. */
	fields?: { name: string; type: string; options?: string[] }[];
};

/** What one expression field can use, from the core (`scope` op). */
export type ScopeResult = {
	/** The type the field needs; null for any. */
	want: string | null;
	template: boolean;
	axis: "none" | "x" | "y";
	units: boolean;
	builtins: boolean;
	/** False where layer references are not allowed (constants, functions). */
	layers: boolean;
	params: ScopeSymbol[];
	consts: ScopeSymbol[];
	functions: { name: string; args: ScopeSymbol[]; ret: string | null }[];
	locals: ScopeSymbol[];
	/** ok: `@id` works; index: needs `@id[i]`; none: cannot be referenced here. */
	layer_refs: { id: string; kind: string; ref: "ok" | "index" | "none" }[];
};

/** The core's size limits; null is unlimited. Images are in megapixels. */
export type BarcodeRequest = {
	format: string;
	text: string;
	check?: string;
	level?: string;
	mode?: string;
	ecc?: number;
	modules?: boolean;
};

export type BarcodeInfo =
	| {
			ok: true;
			format: string;
			/** Modules across and down (1 down for bars). */
			w: number;
			h: number;
			normalized: string;
			check_digit: string | null;
			note: string;
			version: number;
			capacity: number;
			modules?: string;
	  }
	| { ok: false; code: number; message: string; hint: string | null };

export type CoreLimits = {
	layers?: number | null;
	repeat?: number | null;
	canvas?: number | null;
	image_mp?: number | null;
	set_cards?: number | null;
};

export class Engine {
	private worker: Worker;
	private nextId = 1;
	private pending = new Map<
		number,
		{
			resolve: (v: unknown) => void;
			reject: (e: Error) => void;
			progress?: (p: number) => void;
		}
	>();
	version = "";
	/** "dev" for a preview build from the dev branch, empty for a release build. */
	channel = "";

	constructor() {
		this.worker = new Worker(new URL("./worker.ts", import.meta.url), {
			type: "module",
		});
		this.worker.onmessage = (e) => {
			const { id, ok, result, error, progress } = e.data;
			const p = this.pending.get(id);
			if (!p) return;
			if (progress !== undefined) {
				p.progress?.(progress);
				return;
			}
			this.pending.delete(id);
			if (ok) p.resolve(result);
			else p.reject(new Error(error));
		};
	}

	private call<T>(
		msg: object,
		transfer: Transferable[] = [],
		progress?: (p: number) => void,
	): Promise<T> {
		const id = this.nextId++;
		return new Promise<T>((resolve, reject) => {
			this.pending.set(id, {
				resolve: resolve as (v: unknown) => void,
				reject,
				progress,
			});
			this.worker.postMessage({ id, ...msg }, transfer);
		});
	}

	async init(): Promise<void> {
		const info = await this.call<{ version: string; channel?: string }>({
			op: "init",
			url: new URL("yoshida.wasm", document.baseURI).href,
		});
		this.version = info.version;
		this.channel = info.channel ?? "";
	}

	/**
	 * Raises the core's limits to what the server that hosts the editor allows
	 * (the "limits" of its /api/capabilities; null means unlimited). Returns
	 * the limits now in force.
	 */
	async setLimits(limits: CoreLimits): Promise<CoreLimits> {
		const r = await this.call<{ limits: CoreLimits }>({ op: "limits", limits });
		return r.limits;
	}

	setFiles(files: Map<string, Uint8Array>) {
		// Copies, so the caller keeps its buffers.
		return this.call<null>({
			op: "files",
			files: [...files].map(([p, d]) => [p, d.slice()]),
		});
	}

	put(path: string, data: Uint8Array) {
		return this.call<null>({ op: "put", path, data: data.slice() });
	}

	remove(path: string) {
		return this.call<null>({ op: "remove", path });
	}

	async check() {
		const r = await this.call<CheckResult>({ op: "check" });
		// Item fields come as "text" or { type, options, default }.
		for (const s of r.project?.sets ?? [])
			for (const p of s.params) {
				if (!p.item) continue;
				const raw = p.item as Record<string, unknown>;
				const defs: Record<string, ItemField> = {};
				const types: Record<string, string> = {};
				for (const [k, v] of Object.entries(raw)) {
					defs[k] =
						v && typeof v === "object" ? (v as ItemField) : { type: String(v) };
					types[k] = defs[k].type;
				}
				p.item = types;
				p.item_defs = defs;
			}
		return r;
	}

	/** Every card of a set evaluated without drawing: errors that depend on card data. */
	checkCards(set: string, clock: Clock) {
		return this.call<{ diagnostics: Diagnostic[] }>({
			op: "checkCards",
			set,
			...clock,
		});
	}

	/**
	 * What a barcode of `format` makes of `text`: its size, the text as
	 * encoded (check digit added) or the problem with it. `modules` adds the
	 * grid as a string of 0 and 1, row by row, for previews.
	 */
	barcode(req: BarcodeRequest): Promise<BarcodeInfo> {
		return this.call<BarcodeInfo>({ op: "barcode", ...req });
	}

	/**
	 * What the expression field at JSON pointer `path` of the set's design can
	 * use; null when there is no such field (or the design does not load).
	 */
	scope(set: string, path: string): Promise<ScopeResult | null> {
		return this.call<ScopeResult>({ op: "scope", set, path }).catch(
			() => null,
		);
	}

	/**
	 * Evaluates `src` in place of the field at `path` while rendering card
	 * `card` (without drawing); null when there is no such field.
	 */
	eval(
		set: string,
		path: string,
		src: string,
		card: number,
		clock: Clock,
	): Promise<EvalResult | null> {
		return this.call<EvalResult>({
			op: "eval",
			set,
			path,
			src,
			card,
			...clock,
		}).catch(() => null);
	}

	/**
	 * Every card of a set as one PDF, one page per card. `progress` gets the
	 * number of cards rendered so far. With `vector` the pages are drawn as
	 * vectors instead of images (`scale` as for `svg`).
	 */
	pdf(
		set: string,
		clock: Clock,
		cropMarks: boolean,
		cards: number,
		progress?: (done: number) => void,
		vector?: { scale?: number },
	) {
		return this.call<{
			pages: number;
			diagnostics: Diagnostic[];
			bin: Uint8Array;
		}>(
			{
				op: "pdf",
				set,
				...clock,
				crop_marks: cropMarks,
				cards,
				vector: vector !== undefined,
				scale: vector?.scale,
			},
			[],
			progress,
		);
	}

	render(args: RenderArgs) {
		return this.call<RenderResult>({ op: "render", args });
	}

	/**
	 * Renders one card once and encodes it with the browser's encoders (JPEG,
	 * WebP), one file per entry of `encodings`.
	 */
	encode(
		args: Omit<RenderArgs, "format">,
		encodings: {
			type: "image/jpeg" | "image/webp";
			quality: number;
			background?: string;
		}[],
	) {
		return this.call<RenderResult & { files: Uint8Array[] }>({
			op: "encode",
			args,
			encodings,
		});
	}

	/**
	 * A PDF built one page per call (pdfBegin, pdfPage per card, pdfFinish),
	 * so an export can stop between cards. With `print` the cards go side by
	 * side on pages of a paper size instead (`yoshida render --pdf --page`),
	 * and `pdfBack` before the cards adds a page of backs after each page.
	 */
	pdfBegin(print?: PrintRequest) {
		return this.call<{ pages: number }>({ op: "pdfBegin", print });
	}

	/** The card shown behind every card of a print layout. */
	pdfBack(args: {
		set: string;
		card: number;
		date: string;
		now: string;
		scale?: number;
		vector?: boolean;
	}) {
		return this.call<{ back: boolean; diagnostics: Diagnostic[] }>({
			op: "pdfBack",
			args,
		});
	}

	pdfPage(args: {
		set: string;
		card: number;
		date: string;
		now: string;
		crop_marks: boolean;
		/**
		 * Pixels per canvas pixel: of the page image (default 1), or with
		 * `vector` of the parts that stay pixels (default 2).
		 */
		scale?: number;
		/** Draw the page as vectors instead of as an image. */
		vector?: boolean;
	}) {
		return this.call<{
			pages: number;
			diagnostics: Diagnostic[];
			/** Print layout: cards placed so far, and false for a card of another size than the first. */
			cards?: number;
			fits?: boolean;
		}>({
			op: "pdfPage",
			args,
		});
	}

	pdfFinish() {
		return this.call<{
			pages: number;
			/** The print layout's grid (0 without one). */
			cols: number;
			rows: number;
			bin: Uint8Array;
		}>({ op: "pdfFinish" });
	}

	/**
	 * A sheet: the cards tiled left to right, top to bottom into one PNG
	 * (sheetBegin, sheetCard per card until `full`, sheetFinish). A set with
	 * more cards than one sheet holds begins again for the next sheet.
	 */
	sheetBegin(cols: number, rows: number) {
		return this.call<{ cards: number }>({ op: "sheetBegin", cols, rows });
	}

	sheetCard(args: {
		set: string;
		card: number;
		date: string;
		now: string;
		/** Pixels per canvas pixel (default 1). */
		scale?: number;
	}) {
		return this.call<{
			cards: number;
			/** Every cell is taken: finish this sheet. */
			full: boolean;
			diagnostics: Diagnostic[];
		}>({ op: "sheetCard", args });
	}

	sheetFinish() {
		return this.call<{
			cards: number;
			width: number;
			height: number;
			bin: Uint8Array;
		}>({ op: "sheetFinish" });
	}

	/** One card as a vector SVG file. */
	svg(args: SvgArgs) {
		return this.call<SvgResult>({ op: "svg", args });
	}

	renderAll(
		args: Omit<RenderArgs, "card">,
		ids: string[],
		progress?: (p: number) => void,
	) {
		return this.call<{
			files: { id: string; png: Uint8Array }[];
			diagnostics: Diagnostic[];
		}>({ op: "renderAll", args, ids }, [], progress);
	}
}
