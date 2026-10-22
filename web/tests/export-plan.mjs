// Checks what the export dialog plans to write: file names, ZIP or single
// file, the summary line, stored settings, the scale and size of each design
// (by scale or by target dpi, within the pixel limit, with the trim size),
// the JPEG dpi patch and the bleed test for crop marks.
//
//   node --experimental-strip-types tests/export-plan.mjs
import {
	cleanQuality,
	cleanSettings,
	defaultExportSettings,
	designHasBleed,
	designOutputs,
	dpiRange,
	fitScale,
	followsDpi,
	formatDpi,
	formatMm,
	formatScale,
	hasBleed,
	planExport,
	planSummary,
	scaleFits,
	scaleFor,
	setJpegDpi,
} from "../src/lib/exportPlan.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};

const sets = [
	{ name: "number", label: "Number cards", ok: true, cards: ["7C", "8C"] },
	{ name: "court", label: "Court cards", ok: true, cards: ["KS"] },
	{ name: "broken", label: "Broken", ok: false, cards: ["x"] },
];
const plan = (scope, formats, current = "number", card = 1) =>
	planExport({ scope, formats }, "poker", sets, current, card);

let p = plan("card", ["jpeg"]);
ok(
	"one card in one format is one file",
	!p.zip && p.fileName === "8C.jpg",
	p.fileName,
);
ok(
	"its summary names the file",
	planSummary(p) === "1 file: 8C.jpg",
	planSummary(p),
);
p = plan("card", ["pdf"]);
ok("one card as PDF", !p.zip && p.fileName === "8C.pdf", p.fileName);
p = plan("design", ["pdf"]);
ok(
	"a design as PDF keeps today's name",
	!p.zip && p.fileName === "poker-number.pdf",
	p.fileName,
);
p = plan("design", ["png", "jpeg"]);
ok(
	"a design in two formats is a ZIP",
	p.zip && p.fileName === "poker-number.zip" && p.files === 4,
);
ok(
	"summary counts the files of each format",
	planSummary(p) === "4 files in poker-number.zip: 2 PNG, 2 JPEG",
	planSummary(p),
);
p = plan("design", ["jpeg", "png"]);
ok(
	"formats are counted in a fixed order",
	planSummary(p) === "4 files in poker-number.zip: 2 PNG, 2 JPEG",
	planSummary(p),
);
p = plan("design", ["png"]);
ok(
	"summary of one format names it",
	planSummary(p) === "2 PNG files in poker-number.zip",
	planSummary(p),
);
p = plan("all", ["png", "pdf"]);
ok(
	"all designs skip sets with errors",
	p.targets.length === 2 && p.skipped.join() === "Broken",
);
ok(
	"all designs: one PDF per design",
	p.files === 3 + 2 && p.fileName === "poker.zip",
	`${p.files}`,
);
ok(
	"all designs summary",
	planSummary(p) === "5 files in poker.zip: 3 PNG, 2 PDF",
	planSummary(p),
);
p = plan("design", ["png"], "broken");
ok(
	"a design with errors exports nothing",
	p.files === 0 && planSummary(p) === "Nothing to export.",
);

const c = cleanSettings({
	scale: 9,
	formats: ["gif", "webp"],
	jpegQuality: 300,
	pngDepth: 10,
	jpegBackground: "red",
});
ok(
	"stored settings are cleaned",
	c.scale === 1 &&
		c.formats.join() === "webp" &&
		c.jpegQuality === 100 &&
		c.pngDepth === 8 &&
		c.jpegBackground === "#ffffff",
);
ok(
	"garbage gives the defaults",
	JSON.stringify(cleanSettings("x")) === JSON.stringify(defaultExportSettings),
);

ok(
	"scale within the side limit",
	scaleFits({ w: 2500, h: 3500 }, 2) && !scaleFits({ w: 2500, h: 3500 }, 3),
);

const stored = cleanSettings({ scale: 2.5, dpi: 450, resolution: "dpi" });
ok(
	"in-between scales and a target dpi are kept",
	stored.scale === 2.5 && stored.dpi === 450 && stored.resolution === "dpi",
);
const bad = cleanSettings({ scale: 0.5, dpi: -3, resolution: "px" });
ok(
	"out of range ones give the defaults",
	bad.scale === 1 && bad.dpi === 300 && bad.resolution === "scale",
);

const byScale = { resolution: "scale", scale: 2, dpi: 600 };
const byDpi = { resolution: "dpi", scale: 1.5, dpi: 600 };
ok(
	"by scale every design gets the slider's scale",
	scaleFor(byScale, 300, false) === 2 && scaleFor(byScale, 0, false) === 2,
);
ok(
	"by dpi each design gets the dpi over its own; without a dpi, 1x",
	scaleFor(byDpi, 300, true) === 2 &&
		scaleFor(byDpi, 400, true) === 1.5 &&
		scaleFor(byDpi, 0, true) === 1,
);
ok(
	"the scale stays within 1 to 4",
	scaleFor({ ...byDpi, dpi: 100 }, 300, true) === 1 &&
		scaleFor({ ...byDpi, dpi: 3000 }, 300, true) === 4,
);
ok(
	"a target dpi is followed only with a design that has a dpi",
	followsDpi(byDpi, [{ w: 1, h: 1, dpi: 300 }]) &&
		!followsDpi(byDpi, [{ w: 1, h: 1, dpi: 0 }]) &&
		!followsDpi(byScale, [{ w: 1, h: 1, dpi: 300 }]),
);
const rangeOf = (...dpis) =>
	JSON.stringify(dpiRange(dpis.map((dpi) => ({ w: 1, h: 1, dpi }))));
ok(
	"dpi range: 1x to 4x, what every design reaches, else what any reaches",
	rangeOf(300, 300) === '{"min":300,"max":1200}' &&
		rangeOf(300, 150, 0) === '{"min":300,"max":600}' &&
		rangeOf(72, 600) === '{"min":72,"max":2400}' &&
		rangeOf(0) === "null",
	`${rangeOf(300, 150, 0)} ${rangeOf(72, 600)}`,
);

const mixed = [
	{
		name: "a",
		label: "A",
		ok: true,
		cards: ["1"],
		canvas: { w: 750, h: 1050, dpi: 300 },
	},
	{
		name: "b",
		label: "B",
		ok: true,
		cards: ["1"],
		canvas: { w: 3000, h: 1000, dpi: 400 },
	},
	{
		name: "c",
		label: "C",
		ok: true,
		cards: ["1"],
		canvas: { w: 600, h: 600, dpi: 0 },
	},
	{ name: "d", label: "D", ok: true, cards: ["1"], canvas: null },
];
const all = planExport({ scope: "all", formats: ["png"] }, "p", mixed, "a", 0);
let outs = designOutputs(all, mixed, byDpi);
ok(
	"design outputs at 600 dpi: own scales, sizes, dpi and print size",
	JSON.stringify(outs.map((o) => [o.scale, o.size, o.dpi])) ===
		JSON.stringify([
			[2, { w: 1500, h: 2100 }, 600],
			[1.5, { w: 4500, h: 1500 }, 600],
			[1, { w: 600, h: 600 }, 0],
			[1, null, 0],
		]) &&
		formatMm(outs[0].mm) === "63.5 × 88.9 mm" &&
		outs[2].mm === null &&
		outs[0].trim === null,
	JSON.stringify(outs.map((o) => [o.scale, o.size, o.dpi])),
);
outs = designOutputs(all, mixed, { ...byDpi, dpi: 5000 });
ok(
	"a target dpi beyond what the designs reach is kept within it",
	outs[0].dpi === 1200 && outs[1].dpi === 1200,
	`${outs[0].dpi} ${outs[1].dpi}`,
);
outs = designOutputs(all, mixed, { ...byScale, scale: 4 });
ok(
	"at 4x B is over the limit, an unknown canvas is not",
	outs.map((o) => o.fits).join() === "true,false,true,true",
	outs.map((o) => o.fits).join(),
);
const canvases = mixed.filter((x) => x.canvas).map((x) => x.canvas);
const board = { w: 4961, h: 3508, dpi: 300, bleed: 35 };
const quarter = (k) => Math.floor(k / 0.25 + 1e-9) * 0.25;
ok(
	"the highest scale that fits all: 2x for 4961 px, 3.25x for 3000 px",
	quarter(fitScale([board], false, 300)) === 2 &&
		quarter(fitScale(canvases, false, 300)) === 3.25 &&
		fitScale([{ w: 750, h: 1050, dpi: 300 }], false, 300) > 4,
);
const one = [{ name: "x", label: "X", ok: true, cards: ["1"], canvas: board }];
const fitsAt = (dpi) =>
	designOutputs(
		planExport({ scope: "all", formats: ["png"] }, "p", one, "x", 0),
		one,
		{ resolution: "dpi", scale: 1, dpi },
	)[0].fits;
const top = fitScale([board], true, 300) * 300;
ok(
	"by dpi: up to 604.7 dpi fits for 4961 px at 300 dpi; the slider stop is 600",
	fitsAt(604) &&
		!fitsAt(605) &&
		Math.abs(top - 604.7) < 0.05 &&
		quarter(top / 300) * 300 === 600,
	String(top),
);
ok(
	"by dpi, a design without a dpi (at 1x) does not limit the slider",
	fitScale([{ w: 5000, h: 100, dpi: 0 }], true, 300) ===
		Number.POSITIVE_INFINITY,
);
ok(
	"a design over the limit at 1x already is below 1",
	fitScale([{ w: 12000, h: 100, dpi: 0 }], false, 300) < 1 &&
		fitScale([{ w: 12000, h: 100, dpi: 300 }], true, 300) < 1,
);
ok(
	"by dpi the slider shows the design at refDpi: a 150 dpi one may go further",
	Math.abs(
		fitScale([board, { w: 1000, h: 1000, dpi: 150 }], true, 150) - 4.031,
	) < 0.001,
);
outs = designOutputs(
	planExport({ scope: "all", formats: ["png"] }, "p", one, "x", 0),
	one,
	byScale,
);
ok(
	"with a bleed: the printed size and the trim size inside it",
	formatMm(outs[0].mm) === "420 × 297 mm" &&
		formatMm(outs[0].trim) === "414.1 × 291.1 mm",
	`${formatMm(outs[0].mm)} ${formatMm(outs[0].trim)}`,
);
ok(
	"labels: scale, dpi",
	formatScale(2) === "2x" &&
		formatScale(10 / 3) === "3.33x" &&
		formatScale(1.25) === "1.25x" &&
		formatDpi(600) === "600" &&
		formatDpi(317.5) === "317.5",
);

const jfif = Uint8Array.from([
	0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1,
	0, 0,
]);
setJpegDpi(jfif, 600);
ok(
	"JPEG dpi is written to the JFIF header",
	jfif[13] === 1 &&
		jfif[14] * 256 + jfif[15] === 600 &&
		jfif[16] * 256 + jfif[17] === 600,
);
const other = Uint8Array.from([
	0xff, 0xd8, 0xff, 0xe1, 0, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
ok(
	"other JPEGs are left alone",
	setJpegDpi(other.slice(), 300).every((b, i) => b === other[i]),
);

ok(
	"bleed is found: above 0, or an expression",
	designHasBleed('{"canvas":{"bleed":12}}') &&
		!designHasBleed('{"canvas":{}}') &&
		!designHasBleed('{"canvas":{"bleed":0}}') &&
		!designHasBleed('{"canvas":{"bleed":"0"}}') &&
		!designHasBleed('{"canvas":{"bleed":null}}') &&
		hasBleed({ bleed: "3 * param.mm" }) &&
		hasBleed({ bleed: "12" }) &&
		!designHasBleed("{"),
);
ok(
	"typed qualities: clamped, else the fallback",
	cleanQuality(150, 90) === 100 &&
		cleanQuality(0, 90) === 1 &&
		cleanQuality(null, 90) === 90 &&
		cleanQuality(72.4, 90) === 72,
);

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
