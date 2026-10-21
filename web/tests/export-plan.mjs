// Checks what the export dialog plans to write: file names, ZIP or single
// file, the summary line, stored settings and the JPEG dpi patch.
//
//   node --experimental-strip-types tests/export-plan.mjs
import {
	cleanSettings,
	defaultExportSettings,
	designHasBleed,
	planExport,
	planSummary,
	scaleFits,
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
	"summary counts cards and formats",
	planSummary(p) === "2 cards × 2 formats, 4 files in poker-number.zip",
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
	planSummary(p) === "3 cards + 2 PDFs, 5 files in poker.zip",
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
	"bleed is found",
	designHasBleed('{"canvas":{"bleed":12}}') &&
		!designHasBleed('{"canvas":{}}') &&
		!designHasBleed("{"),
);

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
