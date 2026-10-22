// Checks the file kinds of the Files tab (src/lib/filetypes.ts): the icon
// type per path and the description in the selected file block.
//
//   node --experimental-strip-types tests/filetypes.mjs
import { readFileSync } from "node:fs";
import { describeFile, fileType } from "../src/lib/filetypes.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const bytes = (s) => new TextEncoder().encode(s);
const poker = new URL("../../examples/poker/", import.meta.url);

const types = {
	"designs/a.design.json": "design",
	"cards/a.cards.json": "cards",
	"cards/a.cards.csv": "cards",
	"yoshida.json": "json",
	"data/extra.json": "json",
	"assets/fonts/A.ttf": "font",
	"assets/fonts/A.OTF": "font",
	"assets/fonts/A.woff2": "font",
	"README.md": "markdown",
	"rules.pdf": "pdf",
	"assets/fonts/A-license.txt": "text",
	"assets/images/a.png": "image",
	"assets/images/a.JPEG": "image",
	"assets/images/a.svg": "image",
	"notes.zip": "file",
	Makefile: "file",
};
const wrong = Object.entries(types).filter(([p, t]) => fileType(p) !== t);
ok("file type per path", !wrong.length, wrong.map(([p]) => p).join(", "));

const read = (rel) => new Uint8Array(readFileSync(new URL(rel, poker)));
const d = (rel) => describeFile(rel, read(rel));
ok(
	"design shows its name",
	d("designs/number.design.json") === "Design: Number cards (A to 10)",
	d("designs/number.design.json"),
);
ok(
	"card data shows the number of cards",
	d("cards/numbers.cards.json") === "Card data, 40 cards",
	d("cards/numbers.cards.json"),
);
ok(
	"one card is singular",
	d("cards/back.cards.json") === "Card data, 1 card",
	d("cards/back.cards.json"),
);
ok(
	"csv card data counts rows after the header",
	describeFile("cards/a.cards.csv", bytes("id,name\na,A\nb,B\n\n")) ===
		"Card data, 2 cards",
);
ok(
	"broken card data still says what it is",
	describeFile("cards/a.cards.json", bytes("{")) === "Card data",
);
ok("manifest", d("yoshida.json") === "Project manifest", d("yoshida.json"));
ok(
	"font shows family and style",
	d("assets/fonts/CinzelDecorative-Bold.ttf") ===
		"Font: Cinzel Decorative Bold",
	d("assets/fonts/CinzelDecorative-Bold.ttf"),
);
ok(
	"web font shows its format",
	describeFile("a.woff2", bytes("wOF2\0\0\0\0")) === "Font (WOFF2)",
);
ok(
	"license text",
	d("assets/fonts/CinzelDecorative-Bold-license.txt") === "License text",
);
ok("markdown", d("README.md") === "Markdown");
ok("pdf", describeFile("rules.pdf", bytes("%PDF")) === "PDF");
ok(
	"other files show the extension",
	describeFile("a.zip", bytes("")) === "ZIP file",
);

console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
