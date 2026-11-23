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
	withCardSizes,
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

// Sheets: the cards of a design tiled into PNG files.
{
	const mod = await import("../src/lib/exportPlan.ts");
	const sets = [
		{ name: "a", label: "A", ok: true, cards: Array.from({ length: 40 }, (_, i) => `c${i}`) },
		{ name: "b", label: "B", ok: true, cards: ["x", "y", "z"] },
	];
	const plan = (over) =>
		mod.planExport({ scope: "design", formats: ["sheet"], sheetCols: 10, sheetRows: 7, ...over }, "game", sets, "a", 0);
	let pl = plan();
	ok("sheet: one file for a design that fits", pl.sheet && pl.sheets === 1 && pl.files === 1 && !pl.zip && pl.fileName === "game-a.png" && pl.imageFormats.length === 0);
	pl = plan({ sheetCols: 5, sheetRows: 3 });
	ok("sheet: 40 cards on 5 x 3 take three sheets in a zip", pl.sheets === 3 && pl.zip && pl.fileName === "game-a.zip" && mod.planSummary(pl) === "3 Sheet files in game-a.zip", mod.planSummary(pl));
	pl = plan({ scope: "all", formats: ["png", "sheet"] });
	ok("sheet: with PNG and every design", pl.files === 43 + 2 && mod.planSummary(pl) === "45 files in game.zip: 43 PNG, 2 Sheet", mod.planSummary(pl));
	pl = mod.planExport({ scope: "design", formats: ["sheet"] }, "game", sets, "a", 0);
	ok("sheet: 10 x 7 without a grid", pl.sheets === 1);
	ok("sheet: count and names", mod.sheetCount(0, 10, 7) === 0 && mod.sheetCount(70, 10, 7) === 1 && mod.sheetCount(71, 10, 7) === 2 && mod.sheetPath("a", 1, false) === "a.png" && mod.sheetPath("a", 2, true) === "a-2.png");
	ok(
		"sheet: the size limits",
		mod.sheetProblem({ w: 750, h: 1050 }, 10, 7) === "" &&
			mod.sheetProblem(null, 100, 100) === "" &&
			mod.sheetProblem({ w: 2000, h: 2500 }, 10, 8) === "" &&
			/22500 x 1050 px; the limit is 20000/.test(mod.sheetProblem({ w: 750, h: 1050 }, 30, 1)),
	);
	const c = mod.cleanSettings({ sheetCols: 0, sheetRows: 250, formats: ["sheet", "nope"] });
	ok("sheet: stored grid is kept within 1 to 100", c.sheetCols === 1 && c.sheetRows === 100 && c.formats.join() === "sheet" && mod.cleanSettings({}).sheetCols === 10 && mod.cleanSettings({}).sheetRows === 7 && mod.cleanGrid("x", 4) === 4 && mod.cleanGrid(2.6, 4) === 3);
}

// The side limit follows the server's canvas limit (YOSHIDA_MAX_CANVAS).
{
	const mod = await import("../src/lib/exportPlan.ts");
	ok("side limit: 10000 by default", mod.MAX_SIDE === 10000 && !mod.scaleFits({ w: 6000, h: 100 }, 2));
	mod.setMaxSide(undefined);
	mod.setMaxSide("big");
	mod.setMaxSide(0);
	ok("side limit: nonsense keeps it", mod.MAX_SIDE === 10000);
	mod.setMaxSide(20000);
	ok("side limit: raised", mod.MAX_SIDE === 20000 && mod.scaleFits({ w: 6000, h: 100 }, 2) && !mod.scaleFits({ w: 6000, h: 100 }, 4));
	mod.setMaxSide(null);
	ok("side limit: unlimited is the core's ceiling", mod.MAX_SIDE === 65535);
	mod.setMaxSide(10000);
}

// The PDF print layout: paper, the request for the core, the grid and the backs.
{
	const mod = await import("../src/lib/exportPlan.ts");
	const d = mod.defaultExportSettings;
	ok("print: off by default", d.pdfLayout === "card" && d.paper === "a4" && d.printBack === "" && d.duplex === "long");
	const a4 = mod.paperSize(d);
	const land = mod.paperSize({ ...d, paper: "letter", landscape: true });
	const custom = mod.paperSize({ ...d, paper: "custom", paperW: 330, paperH: 482.6 });
	ok("print: paper sizes", a4.w === 210 && a4.h === 297 && land.w === 279.4 && land.h === 215.9 && custom.w === 330 && custom.h === 482.6);
	const req = mod.printRequest({ ...d, landscape: true, printGap: 3, duplex: "short" }, true);
	ok("print: request", req.page === "a4-landscape" && req.gap === 3 && req.margin === 5 && req.crop_marks && req.duplex === "short");
	ok("print: custom request", mod.printRequest({ ...d, paper: "custom", paperW: 100, paperH: 150.5 }, false).page === "100x150.5");
	const poker = { w: 63.5, h: 88.9 };
	const g = mod.printGrid(a4, poker, 0, 5);
	const gl = mod.printGrid(mod.paperSize({ ...d, paper: "letter", landscape: true }), poker, 0, 5);
	ok("print: grid as the core lays it out", g.cols === 3 && g.rows === 3 && gl.cols === 4 && gl.rows === 2);
	ok("print: a gap can cost a column", mod.printGrid(a4, poker, 5, 5).cols === 2 && mod.printGrid(a4, poker, 4, 5).cols === 3);
	ok("print: a card that does not fit", mod.printGrid({ w: 50, h: 50 }, poker, 0, 5).cols === 0 && mod.printGrid(a4, poker, 0, 75).rows === 0);
	// Every paper changes the page, the request and the grid (the summary follows).
	const sz = (paper, landscape = false) => mod.paperSize({ ...d, paper, landscape });
	ok("print: more papers", sz("a3").h === 420 && sz("a5").w === 148 && sz("a6").h === 148 && sz("legal").h === 355.6 && sz("tabloid").w === 279.4 && sz("tabloid", true).w === 431.8);
	ok("print: paper requests", ["a3", "a5", "a6", "legal", "tabloid"].every((p) => mod.printRequest({ ...d, paper: p, landscape: true }, false).page === `${p}-landscape`));
	ok("print: every option is a paper", mod.PAPER_OPTIONS.every((o) => o.value === "custom" || sz(o.value).w > 0));
	const grid = (paper, over = {}) => mod.printGrid(mod.paperSize({ ...d, paper, ...over }), poker, 0, 5);
	ok("print: the grid follows the paper", grid("a3").cols === 4 && grid("a3").rows === 4 && grid("a5").cols === 2 && grid("a6").cols === 1 && grid("tabloid", { landscape: true }).cols === 6);
	const pset = [{ name: "p", label: "P", ok: true, cards: ["a"], canvas: { w: 750, h: 1050, bleed: 0, dpi: 300 } }];
	const tg = [{ set: "p", cards: [0] }];
	const sum = (over) => mod.printSummary({ ...d, ...over }, pset, tg);
	ok("print: summary has the printed size and the count", sum({}).text === "Cards print at 63.5 × 88.9 mm, 3 × 3 a page" && sum({}).note.includes("100%"));
	ok("print: summary follows paper, orientation, size, margin and gap", sum({ paper: "a3" }).text.endsWith("4 × 4 a page") && sum({ landscape: true }).text.endsWith("4 × 2 a page") && sum({ paper: "custom", paperW: 100, paperH: 100 }).text.endsWith("1 × 1 a page") && sum({ printMargin: 40 }).text.endsWith("2 × 2 a page") && sum({ printGap: 5 }).text.endsWith("2 × 3 a page"));
	ok("print: summary says a card does not fit", sum({ paper: "custom", paperW: 60, paperH: 60 }).problem.includes("does not fit") && sum({ paper: "custom", paperW: 60, paperH: 60 }).text === "");
	const c = mod.cleanSettings({ pdfLayout: "print", paper: "foolscap", paperW: 5, paperH: 9999, printGap: -1, printMargin: 7.25, printBack: "back", duplex: "sideways" });
	ok("print: stored settings are cleaned", c.pdfLayout === "print" && c.paper === "a4" && c.paperW === 20 && c.paperH === 2000 && c.printGap === 0 && c.printMargin === 7.3 && c.printBack === "back" && c.duplex === "long");
	// The back set gets no PDF of its own, unless it is all that is exported.
	const deck = [
		{ name: "numbers", label: "Numbers", ok: true, cards: ["AS", "2S"] },
		{ name: "back", label: "Back", ok: true, cards: ["back"] },
	];
	const all = mod.planExport({ scope: "all", formats: ["pdf"], pdfLayout: "print", printBack: "back" }, "poker", deck, "numbers", 0);
	ok("print: no PDF of the backs", all.noPdf.join() === "back" && all.files === 1 && !all.zip && all.fileName === "poker-numbers.pdf", JSON.stringify(all));
	const withPng = mod.planExport({ scope: "all", formats: ["png", "pdf"], pdfLayout: "print", printBack: "back" }, "poker", deck, "numbers", 0);
	ok("print: the backs still get their PNG", withPng.files === 4 && mod.planSummary(withPng) === "4 files in poker.zip: 3 PNG, 1 PDF", mod.planSummary(withPng));
	const only = mod.planExport({ scope: "design", formats: ["pdf"], pdfLayout: "print", printBack: "back" }, "poker", deck, "back", 0);
	ok("print: the back design alone", only.noPdf.length === 0 && only.files === 1);
	const plain = mod.planExport({ scope: "all", formats: ["pdf"], pdfLayout: "card", printBack: "back" }, "poker", deck, "numbers", 0);
	ok("print: a card a page prints every design", plain.noPdf.length === 0 && plain.files === 2);
}

{
	const base = { w: 750, h: 1050, dpi: 300, bleed: 36 };
	const same = withCardSizes(base, [{}, { canvas: { dpi: 600 } }]);
	ok("card sizes: none set keeps the canvas", same.w === 750 && same.h === 1050 && same.dpi === 300 && same.bleed === 36);
	const grown = withCardSizes(base, [{ canvas: { width: 1000 } }, { canvas: { height: 400 } }, { canvas: { width: 100, height: 1200 } }]);
	ok("card sizes: the largest card in each direction", grown.w === 1000 && grown.h === 1200 && grown.dpi === 300);
	const small = withCardSizes(base, [{ canvas: { width: 100, height: 100 } }]);
	ok("card sizes: smaller cards do not shrink it", small.w === 750 && small.h === 1050);
}

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
