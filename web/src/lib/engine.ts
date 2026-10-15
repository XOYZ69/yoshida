// Main-thread client for the render worker, plus the shapes the core returns.

import type { Placed } from "./design";
import type { EvalResult } from "./expr/live";

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
	/** Editor section (FORMAT.md section 4). */
	group?: string;
	options?: string[];
	/** List item fields: name → type (`enum` for enum fields). */
	item?: Record<string, string>;
	/** List item fields with their options and defaults. */
	item_defs?: Record<string, ItemField>;
};

export type ItemField = { type: string; options?: string[]; default?: unknown };

export type CardInfo = { id: string; values: Record<string, unknown> };

export type SetInfo = {
	name: string;
	design: string;
	design_name: string;
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
	/** Proxy render: bitmap pixels per canvas pixel (0 < scale <= 1). */
	scale?: number;
	/** Draw only these layer ids (and what is inside them), without the background. */
	only?: string[];
	/** Draw everything but these layer ids. */
	except?: string[];
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
		const info = await this.call<{ version: string }>({
			op: "init",
			url: new URL("yoshida.wasm", document.baseURI).href,
		});
		this.version = info.version;
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
	 * number of cards rendered so far.
	 */
	pdf(
		set: string,
		clock: Clock,
		cropMarks: boolean,
		cards: number,
		progress?: (done: number) => void,
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
			},
			[],
			progress,
		);
	}

	render(args: RenderArgs) {
		return this.call<RenderResult>({ op: "render", args });
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
