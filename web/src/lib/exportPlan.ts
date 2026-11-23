// The export dialog's settings and what an export writes: which cards, which
// files, their names and the archive around them. No rendering here.

export type ExportScope = "card" | "design" | "all";
/**
 * "sheet": the cards of a design tiled into PNG sheets (a deck image for a
 * tabletop simulator), like `yoshida render --sheet`.
 */
export type ExportFormat = "png" | "jpeg" | "webp" | "svg" | "pdf" | "sheet";
export type PngCompression = "fast" | "default" | "smallest";
export type CropMarks = "auto" | "on" | "off";
/**
 * A PDF's pages: one card a page, or the cards side by side on paper pages
 * ("print"), like `yoshida render --pdf --page`.
 */
export type PdfLayout = "card" | "print";
export type Paper =
	| "a3"
	| "a4"
	| "a5"
	| "a6"
	| "letter"
	| "legal"
	| "tabloid"
	| "custom";
export type Duplex = "long" | "short";

export type ExportSettings = {
	scope: ExportScope;
	formats: ExportFormat[];
	/**
	 * Bitmap pixels per canvas pixel, 1 to 4 (the slider). With a target dpi,
	 * the designs without a canvas.dpi use it.
	 */
	scale: number;
	/** The print resolution to reach when `resolution` is "dpi". */
	dpi: number;
	/**
	 * What the resolution follows: the same scale for every design, or the
	 * same dpi (each design at dpi / canvas.dpi).
	 */
	resolution: "scale" | "dpi";
	pngDepth: 8 | 16;
	pngCompression: PngCompression;
	jpegQuality: number;
	/** JPEG has no transparency: transparent pixels are shown on this color. */
	jpegBackground: string;
	webpQuality: number;
	webpLossless: boolean;
	cropMarks: CropMarks;
	/** PDF pages as vector drawing or as one image per page. */
	pdfVector: boolean;
	/** Cards per row and rows per sheet. */
	sheetCols: number;
	sheetRows: number;
	pdfLayout: PdfLayout;
	/** Print layout: the paper, turned to landscape, and a custom size in mm. */
	paper: Paper;
	landscape: boolean;
	paperW: number;
	paperH: number;
	/** Print layout: millimetres between cards and at least at the page edges. */
	printGap: number;
	printMargin: number;
	/** Print layout: the set whose first card is shown behind every card; "" for none. */
	printBack: string;
	/** The edge the duplex printer turns the sheet over on. */
	duplex: Duplex;
};

export const EXPORT_FORMATS: ExportFormat[] = [
	"png",
	"jpeg",
	"webp",
	"svg",
	"pdf",
	"sheet",
];

/** Columns and rows of a sheet: 1 to this (what the core accepts). */
export const MAX_SHEET_GRID = 100;
/** The core's limit for each side of a sheet, in pixels. */
export const SHEET_MAX_SIDE = 20000;

/** The scales an export renders at (what the server and the CLI accept). */
export const MIN_SCALE = 1;
export const MAX_SCALE = 4;
/** The slider's steps; the dpi field reaches any scale in between. */
export const SCALE_STEP = 0.25;

/** The highest target dpi kept in the settings (four times the core's highest canvas.dpi). */
const MAX_DPI = 40000;

/**
 * The core's limit for each side of a rendered bitmap. 10000 unless the
 * server that hosts the editor raised it (YOSHIDA_MAX_CANVAS).
 */
export let MAX_SIDE = 10000;

/** What "unlimited" means for a side of the canvas (core/limits.zig). */
export const MAX_SIDE_CEILING = 65535;

/** Follows the canvas limit of the core: a number of pixels, or null for unlimited. */
export function setMaxSide(side: number | null | undefined) {
	if (side === null) MAX_SIDE = MAX_SIDE_CEILING;
	else if (typeof side === "number" && Number.isFinite(side) && side >= 1)
		MAX_SIDE = Math.min(Math.floor(side), MAX_SIDE_CEILING);
}

export const defaultExportSettings: ExportSettings = {
	scope: "design",
	formats: ["png"],
	scale: 1,
	dpi: 300,
	resolution: "scale",
	pngDepth: 8,
	pngCompression: "default",
	jpegQuality: 90,
	jpegBackground: "#ffffff",
	webpQuality: 90,
	webpLossless: false,
	cropMarks: "auto",
	pdfVector: true,
	// Ten by seven: the largest deck image the common tabletop simulators take.
	sheetCols: 10,
	sheetRows: 7,
	pdfLayout: "card",
	paper: "a4",
	landscape: false,
	paperW: 210,
	paperH: 297,
	printGap: 0,
	printMargin: 5,
	printBack: "",
	duplex: "long",
};

/** Print layout limits in millimetres (what the core accepts). */
export const MIN_PAPER = 20;
export const MAX_PAPER = 2000;
export const MAX_GAP = 50;
export const MAX_MARGIN = 50;

const papers: Record<Exclude<Paper, "custom">, { w: number; h: number }> = {
	a3: { w: 297, h: 420 },
	a4: { w: 210, h: 297 },
	a5: { w: 148, h: 210 },
	a6: { w: 105, h: 148 },
	letter: { w: 215.9, h: 279.4 },
	legal: { w: 215.9, h: 355.6 },
	tabloid: { w: 279.4, h: 431.8 },
};

/** The papers of the dropdown, as the core's `--page` names them. */
export const PAPER_OPTIONS: { value: Paper; label: string; detail: string }[] =
	[
		{ value: "a3", label: "A3", detail: "297 × 420 mm" },
		{ value: "a4", label: "A4", detail: "210 × 297 mm" },
		{ value: "a5", label: "A5", detail: "148 × 210 mm" },
		{ value: "a6", label: "A6", detail: "105 × 148 mm" },
		{ value: "letter", label: "Letter", detail: "8.5 × 11 in" },
		{ value: "legal", label: "Legal", detail: "8.5 × 14 in" },
		{ value: "tabloid", label: "Tabloid", detail: "11 × 17 in" },
		{ value: "custom", label: "Custom", detail: "" },
	];

const extensions: Record<ExportFormat, string> = {
	png: "png",
	jpeg: "jpg",
	webp: "webp",
	svg: "svg",
	pdf: "pdf",
	sheet: "png",
};

export const formatLabels: Record<ExportFormat, string> = {
	png: "PNG",
	jpeg: "JPEG",
	webp: "WebP",
	svg: "SVG",
	pdf: "PDF",
	sheet: "Sheet",
};

const clampInt = (v: unknown, lo: number, hi: number, fallback: number) =>
	typeof v === "number" && Number.isFinite(v)
		? Math.max(lo, Math.min(hi, Math.round(v)))
		: fallback;

const within = (v: unknown, lo: number, hi: number, fallback: number) =>
	typeof v === "number" && v >= lo && v <= hi ? v : fallback;

/** A typed quality, 1 to 100: out of range is clamped, anything else gives `fallback`. */
export const cleanQuality = (v: unknown, fallback: number) =>
	clampInt(v, 1, 100, fallback);

/** A typed number of columns or rows: 1 to 100, anything else gives `fallback`. */
export const cleanGrid = (v: unknown, fallback: number) =>
	clampInt(v, 1, MAX_SHEET_GRID, fallback);

/** A typed length in mm within `lo` to `hi`: out of range is clamped, anything else gives `fallback`. */
export const cleanMm = (v: unknown, lo: number, hi: number, fallback: number) =>
	typeof v === "number" && Number.isFinite(v)
		? Math.max(lo, Math.min(hi, Math.round(v * 10) / 10))
		: fallback;

/** Settings read back from storage: anything unknown becomes the default. */
export function cleanSettings(raw: unknown): ExportSettings {
	const d = defaultExportSettings;
	const r = (raw && typeof raw === "object" ? raw : {}) as Record<
		string,
		unknown
	>;
	const pick = <T>(v: unknown, options: readonly T[], fallback: T): T =>
		options.includes(v as T) ? (v as T) : fallback;
	const formats = Array.isArray(r.formats)
		? EXPORT_FORMATS.filter((f) => (r.formats as unknown[]).includes(f))
		: d.formats;
	return {
		scope: pick(r.scope, ["card", "design", "all"] as const, d.scope),
		formats: formats.length ? formats : d.formats,
		scale: within(r.scale, MIN_SCALE, MAX_SCALE, d.scale),
		dpi: within(r.dpi, 1, MAX_DPI, d.dpi),
		resolution: pick(r.resolution, ["scale", "dpi"] as const, d.resolution),
		pngDepth: pick(r.pngDepth, [8, 16] as const, d.pngDepth),
		pngCompression: pick(
			r.pngCompression,
			["fast", "default", "smallest"] as const,
			d.pngCompression,
		),
		jpegQuality: clampInt(r.jpegQuality, 1, 100, d.jpegQuality),
		jpegBackground:
			typeof r.jpegBackground === "string" &&
			/^#[0-9a-f]{6}$/i.test(r.jpegBackground)
				? r.jpegBackground
				: d.jpegBackground,
		webpQuality: clampInt(r.webpQuality, 1, 100, d.webpQuality),
		webpLossless:
			typeof r.webpLossless === "boolean" ? r.webpLossless : d.webpLossless,
		cropMarks: pick(r.cropMarks, ["auto", "on", "off"] as const, d.cropMarks),
		pdfVector: typeof r.pdfVector === "boolean" ? r.pdfVector : d.pdfVector,
		sheetCols: cleanGrid(r.sheetCols, d.sheetCols),
		sheetRows: cleanGrid(r.sheetRows, d.sheetRows),
		pdfLayout: pick(r.pdfLayout, ["card", "print"] as const, d.pdfLayout),
		paper: pick(
			r.paper,
			["a3", "a4", "a5", "a6", "letter", "legal", "tabloid", "custom"] as const,
			d.paper,
		),
		landscape: typeof r.landscape === "boolean" ? r.landscape : d.landscape,
		paperW: cleanMm(r.paperW, MIN_PAPER, MAX_PAPER, d.paperW),
		paperH: cleanMm(r.paperH, MIN_PAPER, MAX_PAPER, d.paperH),
		printGap: cleanMm(r.printGap, 0, MAX_GAP, d.printGap),
		printMargin: cleanMm(r.printMargin, 0, MAX_MARGIN, d.printMargin),
		printBack: typeof r.printBack === "string" ? r.printBack : d.printBack,
		duplex: pick(r.duplex, ["long", "short"] as const, d.duplex),
	};
}

type PrintSettings = Pick<
	ExportSettings,
	| "paper"
	| "landscape"
	| "paperW"
	| "paperH"
	| "printGap"
	| "printMargin"
	| "duplex"
>;

/** The page of a print layout in millimetres, turned for landscape. */
export function paperSize(s: PrintSettings): { w: number; h: number } {
	if (s.paper === "custom")
		return {
			w: cleanMm(s.paperW, MIN_PAPER, MAX_PAPER, 210),
			h: cleanMm(s.paperH, MIN_PAPER, MAX_PAPER, 297),
		};
	const p = papers[s.paper];
	return s.landscape ? { w: p.h, h: p.w } : p;
}

/** The print layout as the core takes it with pdf_begin. */
export type PrintRequest = {
	page: string;
	gap: number;
	margin: number;
	crop_marks: boolean;
	duplex: Duplex;
};

export function printRequest(
	s: PrintSettings,
	cropMarks: boolean,
): PrintRequest {
	const size = paperSize(s);
	return {
		page:
			s.paper === "custom"
				? `${size.w}x${size.h}`
				: `${s.paper}${s.landscape ? "-landscape" : ""}`,
		gap: cleanMm(s.printGap, 0, MAX_GAP, 0),
		margin: cleanMm(s.printMargin, 0, MAX_MARGIN, 5),
		crop_marks: cropMarks,
		duplex: s.duplex,
	};
}

/**
 * Cards of `trim` mm a page of `page` mm holds: as many as fit inside the
 * margin, `gap` apart (the core's print layout). 0 x 0 when one does not fit.
 */
export function printGrid(
	page: { w: number; h: number },
	trim: { w: number; h: number },
	gap: number,
	margin: number,
): { cols: number; rows: number } {
	const fit = (avail: number, size: number) =>
		avail < size || !(size > 0)
			? 0
			: Math.min(100, Math.floor((avail + gap) / (size + gap) + 1e-9));
	const cols = fit(page.w - 2 * margin, trim.w);
	const rows = fit(page.h - 2 * margin, trim.h);
	return cols && rows ? { cols, rows } : { cols: 0, rows: 0 };
}

/**
 * The print layout's summary for the designs a PDF writes: the printed card
 * size and the cards a page ("Cards print at 63.5 × 88.9 mm, 3 × 3 a page"),
 * one entry per distinct size when the designs differ, and the first design
 * whose card does not fit the page inside the margins.
 */
export function printSummary(
	s: PrintSettings,
	sets: PlanSet[],
	targets: PlanTarget[],
	noPdf: string[] = [],
): { text: string; note: string; problem: string } {
	const page = paperSize(s);
	const gap = cleanMm(s.printGap, 0, MAX_GAP, 0);
	const margin = cleanMm(s.printMargin, 0, MAX_MARGIN, 5);
	const parts = new Set<string>();
	for (const t of targets) {
		if (noPdf.includes(t.set)) continue;
		const set = sets.find((x) => x.name === t.set);
		const c = set?.canvas;
		if (!c) continue;
		// Without canvas.dpi, a canvas pixel is a point, as in the core.
		const mm = (px: number) => (px / (c.dpi > 0 ? c.dpi : 72)) * 25.4;
		const bleed = c.bleed ?? 0;
		const trim = { w: mm(c.w - 2 * bleed), h: mm(c.h - 2 * bleed) };
		const g = printGrid(page, trim, gap, margin);
		if (!g.cols)
			return {
				text: "",
				note: "",
				problem: `${set?.label ?? t.set} (${formatMm({ w: mm(c.w), h: mm(c.h) })}) does not fit on the page inside the margins`,
			};
		parts.add(`${formatMm(trim)}, ${g.cols} × ${g.rows} a page`);
	}
	if (!parts.size) return { text: "", note: "", problem: "" };
	return {
		text: `Cards print at ${[...parts].join("; ")}`,
		note: PRINT_SCALE_NOTE,
		problem: "",
	};
}

/** Said next to the summary: a scaled page prints the cards at the wrong size. */
export const PRINT_SCALE_NOTE =
	"Print at 100% (actual size), not “fit to page”.";

/**
 * A design's canvas: its size and its bleed (on every side, inside the edge)
 * in canvas pixels, and its canvas.dpi (0 without one).
 */
export type CanvasInfo = { w: number; h: number; dpi: number; bleed?: number };

/**
 * The canvas an export has to plan for when cards set their own size: the
 * design's canvas grown to the largest card in each direction, so the pixel
 * limit and the printed size shown cover every card. The dpi and the bleed
 * stay the measured card's.
 */
export function withCardSizes(
	base: CanvasInfo,
	cards: { canvas?: { width?: number; height?: number } }[],
): CanvasInfo {
	let w = base.w;
	let h = base.h;
	for (const c of cards) {
		if (c.canvas?.width !== undefined && c.canvas.width > w) w = c.canvas.width;
		if (c.canvas?.height !== undefined && c.canvas.height > h)
			h = c.canvas.height;
	}
	return { ...base, w, h };
}

/** A set as the plan needs it. */
export type PlanSet = {
	name: string;
	label: string;
	ok: boolean;
	cards: string[];
	/** Its design's canvas; null while it is not known. */
	canvas?: CanvasInfo | null;
};

/** The cards of one set that an export renders. */
export type PlanTarget = { set: string; cards: number[] };

export type ExportPlan = {
	targets: PlanTarget[];
	/** Labels of the sets left out because they have errors. */
	skipped: string[];
	/** Card images (PNG, JPEG, WebP, SVG) per card, and PDFs per set. */
	imageFormats: ExportFormat[];
	pdf: boolean;
	/**
	 * Sets that get no PDF: the backs of a print layout, shown behind the
	 * other sets' cards (unless they are the only set exported).
	 */
	noPdf: string[];
	/** Sheets are written, and how many files that makes over all sets. */
	sheet: boolean;
	sheets: number;
	cards: number;
	files: number;
	/** The one file to download: the file itself, or the ZIP around many. */
	fileName: string;
	zip: boolean;
};

export const fileExt = (f: ExportFormat) => extensions[f];

/** Path of a card image inside the ZIP. */
export const imagePath = (set: string, card: string, f: ExportFormat) =>
	`${set}/${card}.${extensions[f]}`;

/** Path of a set's PDF inside the ZIP. */
export const pdfPath = (set: string) => `${set}.pdf`;

/** How many sheets of `cols` x `rows` hold `cards` cards. */
export const sheetCount = (cards: number, cols: number, rows: number) =>
	cards > 0 ? Math.ceil(cards / Math.max(1, cols * rows)) : 0;

/**
 * Path of sheet `n` (from 1) of a set inside the ZIP: `<set>.png`, or
 * `<set>-<n>.png` when the set takes `many` sheets (the names the command
 * line writes).
 */
export const sheetPath = (set: string, n: number, many: boolean) =>
	many ? `${set}-${n}.png` : `${set}.png`;

/**
 * Why a sheet of `cols` x `rows` cards of `size` pixels cannot be made
 * (the core's limits for a sheet), or "" when it can.
 */
export function sheetProblem(
	size: { w: number; h: number } | null,
	cols: number,
	rows: number,
): string {
	if (!size) return "";
	const w = size.w * cols;
	const h = size.h * rows;
	if (w > SHEET_MAX_SIDE || h > SHEET_MAX_SIDE)
		return `a ${cols} x ${rows} sheet would be ${w} x ${h} px; the limit is ${SHEET_MAX_SIDE} px on each side`;
	return "";
}

/**
 * What an export of `scope` writes. `current` is the set shown, `card` the
 * index of the card shown.
 */
export function planExport(
	s: Pick<ExportSettings, "scope" | "formats"> &
		Partial<
			Pick<
				ExportSettings,
				"sheetCols" | "sheetRows" | "pdfLayout" | "printBack"
			>
		>,
	project: string,
	sets: PlanSet[],
	current: string,
	card: number,
): ExportPlan {
	// In the order of EXPORT_FORMATS, whatever order they were chosen in.
	const imageFormats = EXPORT_FORMATS.filter(
		(f) => f !== "pdf" && f !== "sheet" && s.formats.includes(f),
	);
	const pdf = s.formats.includes("pdf");
	const sheet = s.formats.includes("sheet");
	const cols = s.sheetCols ?? defaultExportSettings.sheetCols;
	const rows = s.sheetRows ?? defaultExportSettings.sheetRows;
	const targets: PlanTarget[] = [];
	const skipped: string[] = [];
	const chosen =
		s.scope === "all" ? sets : sets.filter((x) => x.name === current);
	for (const set of chosen) {
		if (!set.ok) {
			skipped.push(set.label);
			continue;
		}
		const cards =
			s.scope === "card"
				? set.cards[card] === undefined
					? []
					: [card]
				: set.cards.map((_, i) => i);
		if (cards.length) targets.push({ set: set.name, cards });
	}
	const back =
		pdf && s.pdfLayout === "print" && s.printBack ? s.printBack : "";
	const noPdf =
		back && targets.some((t) => t.set !== back)
			? targets.filter((t) => t.set === back).map((t) => t.set)
			: [];
	const cards = targets.reduce((a, t) => a + t.cards.length, 0);
	const sheets = sheet
		? targets.reduce((a, t) => a + sheetCount(t.cards.length, cols, rows), 0)
		: 0;
	const files =
		cards * imageFormats.length +
		(pdf ? targets.length - noPdf.length : 0) +
		sheets;
	let fileName =
		s.scope === "all" ? `${project}.zip` : `${project}-${current}.zip`;
	const zip = files !== 1;
	if (!zip) {
		const t = targets.find((x) => !noPdf.includes(x.set)) ?? targets[0];
		const id = sets.find((x) => x.name === t.set)?.cards[t.cards[0]] ?? "";
		if (imageFormats.length) fileName = `${id}.${extensions[imageFormats[0]]}`;
		else if (sheet) fileName = `${project}-${t.set}.png`;
		else if (s.scope === "card") fileName = `${id}.pdf`;
		else fileName = `${project}-${t.set}.pdf`;
	}
	return {
		targets,
		skipped,
		imageFormats,
		pdf,
		noPdf,
		sheet,
		sheets,
		cards,
		files,
		fileName,
		zip,
	};
}

/** One line before the Export button: what will be written. */
export function planSummary(p: ExportPlan): string {
	if (!p.files) return "Nothing to export.";
	if (!p.zip) return `1 file: ${p.fileName}`;
	// The files of each format: "40 PNG", "1 PDF".
	const counts = p.imageFormats.map((f) => `${p.cards} ${formatLabels[f]}`);
	if (p.pdf) counts.push(`${p.targets.length - p.noPdf.length} PDF`);
	if (p.sheet) counts.push(`${p.sheets} ${formatLabels.sheet}`);
	return counts.length === 1
		? `${counts[0]} files in ${p.fileName}`
		: `${p.files} files in ${p.fileName}: ${counts.join(", ")}`;
}

/** Bitmap size at `scale`, or null when the canvas size is not known. */
export function scaledSize(
	canvas: { w: number; h: number },
	scale: number,
): { w: number; h: number } | null {
	if (!(canvas.w > 0 && canvas.h > 0)) return null;
	return {
		w: Math.max(1, Math.round(canvas.w * scale)),
		h: Math.max(1, Math.round(canvas.h * scale)),
	};
}

/** True when the bitmap at `scale` stays within the core's side limit. */
export const scaleFits = (canvas: { w: number; h: number }, scale: number) => {
	const s = scaledSize(canvas, scale);
	return !s || (s.w <= MAX_SIDE && s.h <= MAX_SIDE);
};

/** Within the scales an export renders at. */
export const clampScale = (k: number) =>
	Number.isFinite(k) ? Math.min(MAX_SCALE, Math.max(MIN_SCALE, k)) : MIN_SCALE;

/**
 * Whether an export follows a target dpi: chosen, and a design in it has a
 * canvas.dpi to reach it from.
 */
export const followsDpi = (
	r: Pick<ExportSettings, "resolution">,
	canvases: CanvasInfo[],
) => r.resolution === "dpi" && canvases.some((c) => c.dpi > 0);

/**
 * The target dpis the designs reach between 1x and 4x: the range every one
 * of them reaches or, when their dpis are more than 4 times apart, the range
 * any of them reaches. Null when no design has a dpi.
 */
export function dpiRange(
	canvases: CanvasInfo[],
): { min: number; max: number } | null {
	const dpis = canvases.map((c) => c.dpi).filter((d) => d > 0);
	if (!dpis.length) return null;
	const lo = Math.min(...dpis);
	const hi = Math.max(...dpis);
	return hi * MIN_SCALE <= lo * MAX_SCALE
		? { min: hi * MIN_SCALE, max: lo * MAX_SCALE }
		: { min: lo * MIN_SCALE, max: hi * MAX_SCALE };
}

/**
 * The scale a design renders at. Following a target dpi (`byDpi`): that dpi
 * over the design's canvas.dpi, and 1x for a design without one. Otherwise
 * the slider's scale.
 */
export function scaleFor(
	r: Pick<ExportSettings, "scale" | "dpi">,
	designDpi: number,
	byDpi: boolean,
): number {
	if (!byDpi) return clampScale(r.scale);
	return designDpi > 0 ? clampScale(r.dpi / designDpi) : MIN_SCALE;
}

/** What one design of an export comes out as. */
export type DesignOutput = {
	set: string;
	label: string;
	scale: number;
	/** The bitmap's size; null while the canvas is not known. */
	size: { w: number; h: number } | null;
	/** The dpi its files carry: canvas.dpi times the scale (0 without one). */
	dpi: number;
	/** The printed size in millimetres; null without a dpi. */
	mm: { w: number; h: number } | null;
	/** The printed size inside the bleed, where the card is cut; null without a bleed. */
	trim: { w: number; h: number } | null;
	/** Within the core's limit of MAX_SIDE pixels a side. */
	fits: boolean;
};

/**
 * Scale, size and dpi of every design the plan exports. A target dpi is
 * kept within what the designs reach (`dpiRange`).
 */
export function designOutputs(
	plan: ExportPlan,
	sets: PlanSet[],
	r: Pick<ExportSettings, "resolution" | "scale" | "dpi">,
): DesignOutput[] {
	const found = plan.targets.map((t) => ({
		t,
		set: sets.find((x) => x.name === t.set),
	}));
	const canvases = found
		.map((x) => x.set?.canvas)
		.filter((c): c is CanvasInfo => !!c);
	const byDpi = followsDpi(r, canvases);
	const range = dpiRange(canvases);
	const want = {
		scale: r.scale,
		dpi: range ? Math.min(range.max, Math.max(range.min, r.dpi)) : r.dpi,
	};
	return found.map(({ t, set }) => {
		const c = set?.canvas ?? null;
		const dpi = c && c.dpi > 0 ? c.dpi : 0;
		const scale = scaleFor(want, dpi, byDpi);
		const size = c ? scaledSize(c, scale) : null;
		const bleed = c?.bleed ?? 0;
		const mm = (px: number) => (px / dpi) * 25.4;
		return {
			set: t.set,
			label: set?.label ?? t.set,
			scale,
			size,
			dpi: dpi * scale,
			mm: c && dpi ? { w: mm(c.w), h: mm(c.h) } : null,
			trim:
				c && dpi && bleed > 0
					? { w: mm(c.w - 2 * bleed), h: mm(c.h - 2 * bleed) }
					: null,
			fits: !size || (size.w <= MAX_SIDE && size.h <= MAX_SIDE),
		};
	});
}

/**
 * The highest slider position at which every design stays within MAX_SIDE
 * pixels a side, unrounded (Infinity when no canvas is known). Following a
 * target dpi (`byDpi`), the slider shows the scale of a design at `refDpi`
 * and the designs without a dpi stay at 1x. Below 1 when a design is over
 * at 1x already.
 */
export function fitScale(
	canvases: CanvasInfo[],
	byDpi: boolean,
	refDpi: number,
): number {
	let k = Number.POSITIVE_INFINITY;
	for (const c of canvases) {
		const side = Math.max(c.w, c.h);
		if (!(side > 0)) continue;
		// The design's own highest scale.
		const own = MAX_SIDE / side;
		if (own < MIN_SCALE || !byDpi) k = Math.min(k, own);
		else if (c.dpi > 0) k = Math.min(k, (own * c.dpi) / refDpi);
	}
	return k;
}

const round = (v: number, digits: number) => Number(v.toFixed(digits));

/** "2x", "1.5x", "3.33x". */
export const formatScale = (k: number) => `${round(k, 2)}x`;

/** "600", "317.5". */
export const formatDpi = (dpi: number) => String(round(dpi, 1));

/** "63.5 × 88.9 mm", "420 × 297 mm". */
export const formatMm = (mm: { w: number; h: number }) =>
	`${round(mm.w, 1)} × ${round(mm.h, 1)} mm`;

/**
 * Writes `dpi` into a JPEG's JFIF header (the browser's encoder leaves it
 * at 1:1 without units), so the image prints at the design's size. Files
 * without a JFIF header are left as they are.
 */
export function setJpegDpi(jpeg: Uint8Array, dpi: number): Uint8Array {
	const d = Math.round(dpi);
	if (!(d > 0 && d <= 65535) || jpeg.length < 18) return jpeg;
	const jfif = [0xff, 0xd8, 0xff, 0xe0];
	if (jfif.some((b, i) => jpeg[i] !== b)) return jpeg;
	if (String.fromCharCode(...jpeg.subarray(6, 11)) !== "JFIF\0") return jpeg;
	jpeg[13] = 1; // dots per inch
	jpeg[14] = d >> 8;
	jpeg[15] = d & 0xff;
	jpeg[16] = d >> 8;
	jpeg[17] = d & 0xff;
	return jpeg;
}

/**
 * True when a design's canvas has a bleed (crop marks "auto"): a number
 * above 0, or an expression (worked out only when rendering).
 */
export function hasBleed(canvas: unknown): boolean {
	if (!canvas || typeof canvas !== "object") return false;
	const b = (canvas as { bleed?: unknown }).bleed;
	if (typeof b === "number") return b > 0;
	if (typeof b !== "string" || !b.trim()) return false;
	const n = Number(b);
	return Number.isNaN(n) || n > 0;
}

/** True when the design JSON has a bleed (see `hasBleed`). */
export function designHasBleed(json: string | undefined): boolean {
	if (!json) return false;
	try {
		return hasBleed(JSON.parse(json)?.canvas);
	} catch {
		return false;
	}
}

/**
 * Whether this browser can write WebP: some only write PNG and say so in
 * the blob's type.
 */
export async function canEncodeWebp(): Promise<boolean> {
	try {
		const canvas = new OffscreenCanvas(1, 1);
		// A canvas without a context cannot be encoded at all.
		canvas.getContext("2d");
		const blob = await canvas.convertToBlob({ type: "image/webp" });
		return blob.type === "image/webp";
	} catch {
		return false;
	}
}

/**
 * Whether this browser writes true lossless WebP at quality 1 (Chrome and
 * Edge do; others write their highest lossy quality): a few pixels of noise
 * are written and read back.
 */
export async function canEncodeLosslessWebp(): Promise<boolean> {
	try {
		const n = 8;
		const canvas = new OffscreenCanvas(n, n);
		const g = canvas.getContext("2d");
		if (!g) return false;
		const px = g.createImageData(n, n);
		for (let i = 0; i < px.data.length; i++)
			px.data[i] = i % 4 === 3 ? 255 : (i * 97 + 13) % 256;
		g.putImageData(px, 0, 0);
		const blob = await canvas.convertToBlob({
			type: "image/webp",
			quality: 1,
		});
		if (blob.type !== "image/webp") return false;
		const img = await createImageBitmap(blob, {
			colorSpaceConversion: "none",
			premultiplyAlpha: "none",
		});
		const back = new OffscreenCanvas(n, n).getContext("2d");
		if (!back) return false;
		back.drawImage(img, 0, 0);
		const got = back.getImageData(0, 0, n, n).data;
		return got.every((v, i) => v === px.data[i]);
	} catch {
		return false;
	}
}

// ----------------------------------------------------------- size estimate

/**
 * A card written in one format, measured by rendering a few cards of the
 * set and taking the mean. Raster formats scale with the pixels (`w` x `h`
 * is the size it was drawn at); SVG does not. A sheet is measured as one
 * sheet of a few cards (`w` x `h` is the sheet's size). A PDF is measured as
 * a one page file and as a file of `pages` pages (`more`), so the file's
 * fixed part (fonts, headers) is not counted for every page; `pixels` says
 * its pages are images, which scale with the pixels like the other rasters.
 */
export type FormatSample = {
	bytes: number;
	w: number;
	h: number;
	more?: number;
	pages?: number;
	pixels?: boolean;
};
export type SampleSet = Partial<Record<ExportFormat, FormatSample>>;

/** What the browser renders for an estimate: one card in these formats. */
export type SampleRequest = {
	set: string;
	/** The cards to render; the estimate takes their mean. */
	cards: number[];
	/** The scale to draw at (the export's own, or lower to keep the sample cheap). */
	scale: number;
	/** The card's bitmap size at that scale, for the samples that are not bitmaps. */
	size: { w: number; h: number };
	formats: ExportFormat[];
	settings: Pick<
		ExportSettings,
		| "pngDepth"
		| "pngCompression"
		| "jpegQuality"
		| "jpegBackground"
		| "webpQuality"
		| "webpLossless"
		| "pdfVector"
		| "cropMarks"
	>;
};

export type SizeEstimate = {
	/** Bytes per format (the PDFs and the sheets of all designs together). */
	perFormat: Partial<Record<ExportFormat, number>>;
	/** The file the export downloads: the formats together, plus the ZIP's own bytes. */
	total: number;
	/** Formats left out for want of a sample or a known size. */
	missing: ExportFormat[];
};

/** A ZIP entry: local and central headers around a name like `set/card.png`. */
const ZIP_ENTRY_BYTES = 120;
const ZIP_END_BYTES = 22;

/** Pixels the estimate renders at most, so a sample at 4x stays cheap. */
export const SAMPLE_MAX_PIXELS = 3_000_000;

/** How many cards the estimate renders per format. */
export const SAMPLE_CARDS = 3;

/** `k` cards spread evenly over `n` (the middle of each part), so the sample is not just the card in view. */
export const spreadCards = (n: number, k = SAMPLE_CARDS) =>
	Array.from({ length: Math.min(k, n) }, (_, i) =>
		Math.floor(((i + 0.5) * n) / Math.min(k, n)),
	);

/**
 * The scale to draw the sample at: the export's own, lowered so the sample
 * stays within SAMPLE_MAX_PIXELS (the estimate scales it back by the pixels).
 */
export function sampleScale(
	size: { w: number; h: number },
	scale: number,
): number {
	const px = size.w * size.h;
	if (!(px > SAMPLE_MAX_PIXELS)) return scale;
	return scale * Math.sqrt(SAMPLE_MAX_PIXELS / px);
}

/**
 * Typical bytes of a card without measuring it, from the pixels alone: for
 * a format whose sample could not be made. Rough, within a factor of two
 * for card art.
 */
export function fallbackSample(
	format: ExportFormat,
	w: number,
	h: number,
	s: Pick<
		ExportSettings,
		| "pngDepth"
		| "pngCompression"
		| "jpegQuality"
		| "webpQuality"
		| "webpLossless"
		| "pdfVector"
	>,
): FormatSample {
	const px = Math.max(1, w * h);
	const png =
		1.2 *
		(s.pngDepth === 16 ? 1.9 : 1) *
		(s.pngCompression === "fast" ? 1.3 : s.pngCompression === "smallest" ? 0.9 : 1);
	const q = Math.max(0.01, Math.min(1, s.jpegQuality / 100));
	const jpeg = 0.05 + 0.55 * q * q;
	const wq = Math.max(0.01, Math.min(1, s.webpQuality / 100));
	const webp = s.webpLossless ? 0.8 * png : 0.7 * (0.05 + 0.55 * wq * wq);
	if (format === "svg") return { bytes: 30_000, w, h };
	if (format === "pdf")
		return s.pdfVector
			? { bytes: 60_000, w, h, more: 80_000 }
			: { bytes: Math.round(png * px), w, h, pixels: true };
	const bpp = format === "jpeg" ? jpeg : format === "webp" ? webp : png;
	return { bytes: Math.round(bpp * px), w, h };
}

/**
 * The size of an export from samples of one card per format: the samples
 * scaled to each design's pixels and multiplied by its cards (a PDF by its
 * pages, a sheet by the cards it holds), plus the ZIP's headers. An
 * estimate: the cards of a design differ, a sample drawn at a lower scale
 * than the export compresses a little differently.
 */
export function estimateSizes(
	plan: ExportPlan,
	outputs: Pick<DesignOutput, "set" | "size">[],
	samples: SampleSet,
): SizeEstimate {
	const perFormat: Partial<Record<ExportFormat, number>> = {};
	const missing: ExportFormat[] = [];
	const formats: ExportFormat[] = [
		...plan.imageFormats,
		...(plan.pdf ? (["pdf"] as const) : []),
		...(plan.sheet ? (["sheet"] as const) : []),
	];
	for (const f of formats) {
		const sample = samples[f];
		let sum = 0;
		let known = !!sample && sample.bytes >= 0;
		for (const t of plan.targets) {
			if (!sample || !known) break;
			if (f === "pdf" && plan.noPdf.includes(t.set)) continue;
			const size = outputs.find((o) => o.set === t.set)?.size;
			const n = t.cards.length;
			const px = sample.w * sample.h;
			const ratio = size && px > 0 ? (size.w * size.h) / px : null;
			if (f === "svg") sum += sample.bytes * n;
			else if (f === "pdf" && !sample.pixels) {
				// A first page with the file's fixed part, then what a page adds.
				const extra = Math.max(1, (sample.pages ?? 2) - 1);
				const add =
					sample.more === undefined
						? sample.bytes
						: Math.min(
								sample.bytes,
								Math.max(
									(sample.more - sample.bytes) / extra,
									sample.bytes * 0.05,
								),
							);
				sum += sample.bytes + (n - 1) * add;
			} else if (ratio === null) known = false;
			// Per pixel; a sheet's sample is a sheet of a few cards.
			else sum += sample.bytes * ratio * n;
		}
		if (known && sample) perFormat[f] = Math.round(sum);
		else missing.push(f);
	}
	const parts = Object.values(perFormat);
	const zip = plan.zip ? plan.files * ZIP_ENTRY_BYTES + ZIP_END_BYTES : 0;
	return {
		perFormat,
		total: Math.round(parts.reduce((a, b) => a + b, 0) + (parts.length ? zip : 0)),
		missing,
	};
}

/** "812 B", "4.2 KB", "48 KB", "1.2 MB", "3.45 GB". */
export function formatSize(bytes: number): string {
	const n = Math.max(0, bytes);
	if (n < 1000) return `${Math.round(n)} B`;
	const units = ["KB", "MB", "GB"];
	let v = n / 1024;
	let i = 0;
	while (v >= 1000 && i < units.length - 1) {
		v /= 1024;
		i++;
	}
	const digits = v < 10 ? (i === 2 ? 2 : 1) : i === 2 && v < 100 ? 1 : 0;
	return `${v.toFixed(digits)} ${units[i]}`;
}

/** "≈ 48 MB", with a no-break space after the sign. */
export const formatEstimate = (bytes: number) => `≈ ${formatSize(bytes)}`;

/** "PNG 30 MB · JPEG 8.2 MB": each format's share, in the order of the dialog. */
export function sizeBreakdown(
	perFormat: Partial<Record<ExportFormat, number>>,
): string {
	return EXPORT_FORMATS.filter((f) => perFormat[f] !== undefined)
		.map((f) => `${formatLabels[f]} ${formatSize(perFormat[f] ?? 0)}`)
		.join(" · ");
}
