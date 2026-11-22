// What the designer knows about the barcode formats: their names, which
// fields each one reads (mirrors `barcodeIgnores` in src/core/design.zig, so
// the inspector greys out what the renderer would warn about), and the
// readable size of a symbol.

export type BarcodeFormat = {
	id: string;
	name: string;
	/** Bars of one height, or a square (or rectangular) grid of modules. */
	kind: "linear" | "matrix";
	/** Text for the picker's preview. */
	sample: string;
	/** One line under the preview. */
	hint: string;
	/** Not available yet: shown, but cannot be picked. */
	soon?: boolean;
};

export const BARCODE_FORMATS: BarcodeFormat[] = [
	{
		id: "qr",
		name: "QR code",
		kind: "matrix",
		sample: "yoshida",
		hint: "Any text or link; the one phones read best",
	},
	{
		id: "code128",
		name: "Code 128",
		kind: "linear",
		sample: "YOSHIDA 42",
		hint: "Any ASCII text; the usual choice for ids",
	},
	{
		id: "ean13",
		name: "EAN-13",
		kind: "linear",
		sample: "400638133393",
		hint: "13 digits for retail; the check digit is added",
	},
	{
		id: "ean8",
		name: "EAN-8",
		kind: "linear",
		sample: "9638507",
		hint: "8 digits for small retail items",
	},
	{
		id: "upca",
		name: "UPC-A",
		kind: "linear",
		sample: "03600029145",
		hint: "12 digits, North American retail",
	},
	{
		id: "code39",
		name: "Code 39",
		kind: "linear",
		sample: "CARD-42",
		hint: "Digits, capitals and - . $ / + %",
	},
	{
		id: "itf",
		name: "ITF",
		kind: "linear",
		sample: "1234567890",
		hint: "Digits in pairs (Interleaved 2 of 5)",
	},
	{
		id: "itf14",
		name: "ITF-14",
		kind: "linear",
		sample: "1234567890123",
		hint: "14 digits for cartons, with bearer bars",
	},
	{
		id: "codabar",
		name: "Codabar",
		kind: "linear",
		sample: "A12345B",
		hint: "Digits and - $ : / . + for libraries and labs",
	},
	{
		id: "code93",
		name: "Code 93",
		kind: "linear",
		sample: "YOSHIDA",
		hint: "Denser than Code 39",
	},
	{
		id: "datamatrix",
		name: "Data Matrix",
		kind: "matrix",
		sample: "Yoshida",
		hint: "Tiny square code for small labels",
	},
	{
		id: "aztec",
		name: "Aztec",
		kind: "matrix",
		sample: "Yoshida",
		hint: "Square code that needs no quiet zone",
	},
	{
		id: "pdf417",
		name: "PDF417",
		kind: "matrix",
		sample: "Yoshida",
		hint: "Stacked rows; not available yet",
		soon: true,
	},
];

export const LINEAR_ONLY = [
	"label",
	"label_text",
	"label_color",
	"label_gap",
	"font",
	"size",
	"align",
];
export const QR_ONLY = ["level", "mode", "eye", "eye_color", "logo", "logo_src"];

export function formatInfo(id: string): BarcodeFormat | undefined {
	return BARCODE_FORMATS.find((f) => f.id === id);
}

/** True when the format does not read the field. */
export function ignores(format: string, key: string): boolean {
	const info = formatInfo(format);
	if (!info) return false;
	const linear = info.kind === "linear";
	if (format !== "qr" && QR_ONLY.includes(key)) return true;
	if (key === "ecc") return format !== "aztec" && format !== "pdf417";
	if (!linear) {
		if (LINEAR_ONLY.includes(key) || key === "check") return true;
		if (key === "style" && format === "pdf417") return true;
		return false;
	}
	if (key === "style") return true;
	if (key === "check") return ["code128", "codabar", "code93"].includes(format);
	return false;
}

/** The quiet zone a format asks for, in modules. */
export function quietZone(format: string): number {
	switch (format) {
		case "qr":
			return 4;
		case "ean13":
			return 11;
		case "ean8":
			return 7;
		case "upca":
			return 9;
		case "datamatrix":
		case "pdf417":
			return 2;
		case "aztec":
			return 1;
		default:
			return 10;
	}
}

/**
 * The smallest box width, in canvas pixels, that keeps a module at the
 * printable minimum for the canvas dpi (0.25 mm, QR 0.5 mm), or at 2 px
 * without a dpi.
 */
export function minWidth(
	format: string,
	modulesAcross: number,
	margin: number,
	dpi: number | null,
): { px: number; why: string } {
	const total = modulesAcross + 2 * margin;
	if (dpi && dpi > 0) {
		const mm = format === "qr" ? 0.5 : 0.25;
		const per = Math.ceil((mm / 25.4) * dpi);
		return { px: per * total, why: `${per} px a module for ${mm} mm at ${dpi} dpi` };
	}
	return { px: 2 * total, why: "2 px a module" };
}
