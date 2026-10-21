// The export dialog's settings and what an export writes: which cards, which
// files, their names and the archive around them. No rendering here.

export type ExportScope = "card" | "design" | "all";
export type ExportFormat = "png" | "jpeg" | "webp" | "svg" | "pdf";
export type PngCompression = "fast" | "default" | "smallest";
export type CropMarks = "auto" | "on" | "off";

export type ExportSettings = {
	scope: ExportScope;
	formats: ExportFormat[];
	/** Bitmap pixels per canvas pixel: 1 to 4. */
	scale: number;
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

export const SCALES = [1, 2, 3, 4];

/** The core's limit for each side of a rendered bitmap. */
export const MAX_SIDE = 10000;

export const defaultExportSettings: ExportSettings = {
	scope: "design",
	formats: ["png"],
	scale: 1,
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
		scale: pick(r.scale, SCALES, d.scale),
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

/** A set as the plan needs it. */
export type PlanSet = {
	name: string;
	label: string;
	ok: boolean;
	cards: string[];
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
	const imageFormats = s.formats.filter((f) => f !== "pdf");
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

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** One line before the Export button: what will be written. */
export function planSummary(p: ExportPlan): string {
	if (!p.files) return "Nothing to export.";
	if (!p.zip) return `1 file: ${p.fileName}`;
	const parts: string[] = [];
	if (p.imageFormats.length)
		parts.push(
			p.imageFormats.length === 1
				? plural(p.cards, "card")
				: `${plural(p.cards, "card")} × ${p.imageFormats.length} formats`,
		);
	if (p.pdf) parts.push(plural(p.targets.length, "PDF"));
	return `${parts.join(" + ")}, ${p.files} files in ${p.fileName}`;
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

/** True when the design JSON sets `canvas.bleed` (crop marks "auto"). */
export function designHasBleed(json: string | undefined): boolean {
	if (!json) return false;
	try {
		const d = JSON.parse(json);
		return (
			!!d?.canvas &&
			typeof d.canvas === "object" &&
			d.canvas.bleed !== undefined
		);
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
