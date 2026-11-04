// The export dialog's settings and what an export writes: which cards, which
// files, their names and the archive around them. No rendering here.

export type ExportScope = "card" | "design" | "all";
export type ExportFormat = "png" | "jpeg" | "webp" | "svg" | "pdf";
export type PngCompression = "fast" | "default" | "smallest";
export type CropMarks = "auto" | "on" | "off";

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
};

export const EXPORT_FORMATS: ExportFormat[] = [
	"png",
	"jpeg",
	"webp",
	"svg",
	"pdf",
];

/** The scales an export renders at (what the server and the CLI accept). */
export const MIN_SCALE = 1;
export const MAX_SCALE = 4;
/** The slider's steps; the dpi field reaches any scale in between. */
export const SCALE_STEP = 0.25;

/** The highest target dpi kept in the settings (four times the core's highest canvas.dpi). */
const MAX_DPI = 40000;

/** The core's limit for each side of a rendered bitmap. */
export const MAX_SIDE = 10000;

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
};

const extensions: Record<ExportFormat, string> = {
	png: "png",
	jpeg: "jpg",
	webp: "webp",
	svg: "svg",
	pdf: "pdf",
};

export const formatLabels: Record<ExportFormat, string> = {
	png: "PNG",
	jpeg: "JPEG",
	webp: "WebP",
	svg: "SVG",
	pdf: "PDF",
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
	};
}

/**
 * A design's canvas: its size and its bleed (on every side, inside the edge)
 * in canvas pixels, and its canvas.dpi (0 without one).
 */
export type CanvasInfo = { w: number; h: number; dpi: number; bleed?: number };

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

/**
 * What an export of `scope` writes. `current` is the set shown, `card` the
 * index of the card shown.
 */
export function planExport(
	s: Pick<ExportSettings, "scope" | "formats">,
	project: string,
	sets: PlanSet[],
	current: string,
	card: number,
): ExportPlan {
	// In the order of EXPORT_FORMATS, whatever order they were chosen in.
	const imageFormats = EXPORT_FORMATS.filter(
		(f) => f !== "pdf" && s.formats.includes(f),
	);
	const pdf = s.formats.includes("pdf");
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
	const cards = targets.reduce((a, t) => a + t.cards.length, 0);
	const files = cards * imageFormats.length + (pdf ? targets.length : 0);
	let fileName =
		s.scope === "all" ? `${project}.zip` : `${project}-${current}.zip`;
	const zip = files !== 1;
	if (!zip) {
		const t = targets[0];
		const id = sets.find((x) => x.name === t.set)?.cards[t.cards[0]] ?? "";
		if (imageFormats.length) fileName = `${id}.${extensions[imageFormats[0]]}`;
		else if (s.scope === "card") fileName = `${id}.pdf`;
		else fileName = `${project}-${t.set}.pdf`;
	}
	return { targets, skipped, imageFormats, pdf, cards, files, fileName, zip };
}

/** One line before the Export button: what will be written. */
export function planSummary(p: ExportPlan): string {
	if (!p.files) return "Nothing to export.";
	if (!p.zip) return `1 file: ${p.fileName}`;
	// The files of each format: "40 PNG", "1 PDF".
	const counts = p.imageFormats.map((f) => `${p.cards} ${formatLabels[f]}`);
	if (p.pdf) counts.push(`${p.targets.length} PDF`);
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
