// Checks the font readers and the Google Fonts catalog (src/lib/fonts/sfnt.ts
// and catalog.ts) without a browser:
//
//   node --experimental-strip-types tests/fonts.mjs
//
// Optional inputs:
//   FONT_CATALOG=/path/to/google-fonts.json  real catalog (the real-catalog checks are skipped without it)
//   FONT_SAMPLES=/path/to/static/ttfs        Google static TTFs, e.g. Inter-700.ttf
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import * as C from "../src/lib/fonts/catalog.ts";
import * as P from "../src/lib/fonts/project.ts";
import * as S from "../src/lib/fonts/sfnt.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const skip = (name, why) => console.log(`SKIP ${name} (${why})`);

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const repoFont = (p) => new Uint8Array(readFileSync(here(`../../${p}`)));

// ------------------------------------------------------------ synthetic fonts

const utf16 = (s) => {
	const b = new Uint8Array(s.length * 2);
	for (let i = 0; i < s.length; i++) {
		const c = s.charCodeAt(i);
		b[2 * i] = c >> 8;
		b[2 * i + 1] = c & 0xff;
	}
	return b;
};
const latin1 = (s) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);

/** A `name` table from [platform, language, nameID, text] records. */
function nameTable(recs) {
	const strs = recs.map(([p, , , s]) => (p === 1 ? latin1(s) : utf16(s)));
	const head = 6 + 12 * recs.length;
	const total = head + strs.reduce((n, b) => n + b.length, 0);
	const out = new Uint8Array(total);
	const v = new DataView(out.buffer);
	v.setUint16(2, recs.length);
	v.setUint16(4, head);
	let at = head;
	recs.forEach(([p, lang, id], i) => {
		const r = 6 + i * 12;
		v.setUint16(r, p);
		v.setUint16(r + 2, p === 1 ? 0 : 1);
		v.setUint16(r + 4, lang);
		v.setUint16(r + 6, id);
		v.setUint16(r + 8, strs[i].length);
		v.setUint16(r + 10, at - head);
		out.set(strs[i], at);
		at += strs[i].length;
	});
	return out;
}

/** An OS/2 table (78 bytes) with the fields the reader uses. */
function os2Table({ weight = 400, fsType = 0, italic = false } = {}) {
	const out = new Uint8Array(78);
	const v = new DataView(out.buffer);
	v.setUint16(4, weight);
	v.setUint16(8, fsType);
	v.setUint16(62, italic ? 1 : 0);
	return out;
}

/**
 * A sfnt font face whose table offsets start at `base` in the file, so it
 * can sit inside a collection. Returns a buffer of base + face length bytes.
 */
function face(tables, base = 0) {
	let pos = 12 + 16 * tables.length;
	const offs = tables.map(([, d]) => {
		const at = pos;
		pos += (d.length + 3) & ~3;
		return at;
	});
	const out = new Uint8Array(base + pos);
	const v = new DataView(out.buffer);
	v.setUint32(base, 0x00010000);
	v.setUint16(base + 4, tables.length);
	tables.forEach(([tag, d], i) => {
		const r = base + 12 + i * 16;
		for (let k = 0; k < 4; k++) out[r + k] = tag.charCodeAt(k);
		v.setUint32(r + 8, base + offs[i]);
		v.setUint32(r + 12, d.length);
		out.set(d, base + offs[i]);
	});
	return out;
}

/** A TrueType file with a name table and OS/2 table (plus fvar when asked). */
function ttf({ names = [], os2 = {}, variable = false } = {}) {
	const tables = [
		["OS/2", os2Table(os2)],
		["name", nameTable(names)],
	];
	if (variable) tables.push(["fvar", new Uint8Array(16)]);
	return face(tables);
}

const DEMO = [
	[3, 0x409, 1, "Demo Sans"],
	[3, 0x409, 2, "Bold"],
	[3, 0x409, 4, "Demo Sans Bold"],
	[3, 0x409, 0, "© 2026 Demo Co."],
	[3, 0x409, 9, "Jane Doe"],
	[3, 0x409, 13, "Licensed under the OFL"],
	[3, 0x409, 14, "https://example.test/ofl"],
];

// ------------------------------------------------------------ fontFormat / drawable

{
	ok(
		"Lato is a TrueType file",
		S.fontFormat(repoFont("src/core/assets/Lato-Regular.ttf")) === "ttf",
	);
	ok(
		"Bebas Neue is a TrueType file",
		S.fontFormat(
			repoFont("examples/board-game/assets/fonts/BebasNeue-Regular.ttf"),
		) === "ttf",
	);
	ok("sfnt version 1.0 is ttf", S.fontFormat(ttf()) === "ttf");
	ok(
		"'true' tag is ttf",
		S.fontFormat(
			Uint8Array.from("true\0\0\0\0".split(""), (c) => c.charCodeAt(0)),
		) === "ttf",
	);
	const tag = (t) =>
		Uint8Array.from(
			[...t, 0, 0, 0, 0, 0, 0, 0, 0].map((c) =>
				typeof c === "string" ? c.charCodeAt(0) : c,
			),
		);
	ok("OTTO is otf", S.fontFormat(tag("OTTO")) === "otf");
	ok("wOFF is woff", S.fontFormat(tag("wOFF")) === "woff");
	ok("wOF2 is woff2", S.fontFormat(tag("wOF2")) === "woff2");
	ok("ttcf is ttc", S.fontFormat(tag("ttcf")) === "ttc");
	ok("PK zip header is unknown", S.fontFormat(tag("PK\x03\x04")) === "unknown");
	ok(
		"fewer than four bytes is unknown",
		S.fontFormat(new Uint8Array([0, 1, 0])) === "unknown",
	);
	ok("empty input is unknown", S.fontFormat(new Uint8Array(0)) === "unknown");

	ok(
		"ttf, otf and ttc are drawable",
		["ttf", "otf", "ttc"].every((f) => S.drawable(f)),
	);
	ok(
		"woff, woff2 and unknown are not drawable",
		["woff", "woff2", "unknown"].every((f) => !S.drawable(f)),
	);
}

// ------------------------------------------------------------ readFont on real files

{
	const cinzel = S.readFont(
		repoFont("examples/poker/assets/fonts/CinzelDecorative-Bold.ttf"),
	);
	console.log(
		"  Cinzel Decorative Bold:",
		JSON.stringify({
			family: cinzel.family,
			style: cinzel.style,
			weight: cinzel.weight,
			embedding: cinzel.embedding,
		}),
	);
	ok(
		"Cinzel Decorative family",
		cinzel.family === "Cinzel Decorative",
		cinzel.family,
	);
	ok(
		"Cinzel Decorative style Bold, weight 700",
		cinzel.style === "Bold" && cinzel.weight === 700,
		`${cinzel.style} ${cinzel.weight}`,
	);
	ok(
		"Cinzel Decorative is upright and static",
		!cinzel.italic && !cinzel.variable,
	);
	ok(
		"Cinzel Decorative is installable",
		cinzel.embedding === "installable",
		cinzel.embedding,
	);
	ok(
		"Cinzel Decorative names its OFL",
		cinzel.license.includes("SIL Open Font License"),
	);
	ok(
		"Cinzel Decorative copyright names the author",
		cinzel.copyright.includes("Natanael Gama"),
	);

	const dm = S.readFont(
		repoFont("examples/poker/assets/fonts/DMSerifDisplay-Regular.ttf"),
	);
	ok(
		"DM Serif Display family and Regular",
		dm.family === "DM Serif Display" &&
			dm.style === "Regular" &&
			dm.weight === 400,
		`${dm.family} ${dm.style}`,
	);

	const bebas = S.readFont(
		repoFont("examples/board-game/assets/fonts/BebasNeue-Regular.ttf"),
	);
	console.log(
		"  Bebas Neue:",
		JSON.stringify({
			family: bebas.family,
			fullName: bebas.fullName,
			licenseUrl: bebas.licenseUrl,
		}),
	);
	ok("Bebas Neue family", bebas.family === "Bebas Neue", bebas.family);
	ok(
		"Bebas Neue full name",
		bebas.fullName === "Bebas Neue Regular",
		bebas.fullName,
	);
	ok(
		"Bebas Neue names only a license URL in its name table",
		bebas.license === "" && bebas.licenseUrl.includes("OFL"),
		bebas.licenseUrl,
	);
	ok(
		"Bebas Neue copyright names the project",
		bebas.copyright.includes("Bebas Neue Project Authors"),
	);

	const lato = S.readFont(repoFont("src/core/assets/Lato-Regular.ttf"));
	ok(
		"Lato family and weight",
		lato.family === "Lato" && lato.weight === 400,
		`${lato.family} ${lato.weight}`,
	);
	ok(
		"Lato license URL",
		lato.licenseUrl === "http://scripts.sil.org/OFL",
		lato.licenseUrl,
	);

	if (process.env.FONT_SAMPLES && existsSync(process.env.FONT_SAMPLES)) {
		const dir = process.env.FONT_SAMPLES;
		const inter = S.readFont(
			new Uint8Array(readFileSync(`${dir}/Inter-700.ttf`)),
		);
		console.log(
			"  Inter-700:",
			JSON.stringify({
				family: inter.family,
				style: inter.style,
				weight: inter.weight,
			}),
		);
		ok(
			"Inter-700 reads weight 700",
			inter.weight === 700 && inter.style === "Bold",
			`${inter.style} ${inter.weight}`,
		);
		const pf = S.readFont(
			new Uint8Array(readFileSync(`${dir}/PlayfairDisplay-700.ttf`)),
		);
		ok(
			"Playfair Display 700 family",
			pf.family === "Playfair Display" && pf.weight === 700,
			`${pf.family} ${pf.weight}`,
		);
		const cav = S.readFont(
			new Uint8Array(readFileSync(`${dir}/Caveat-400.ttf`)),
		);
		ok("Caveat family", cav.family === "Caveat", cav.family);
	} else {
		skip("Google static TTF samples", "set FONT_SAMPLES to a folder with them");
	}
}

// ------------------------------------------------------------ readFont on synthetic fonts

{
	const a = S.readFont(ttf({ names: DEMO, os2: { weight: 700 } }));
	ok(
		"name table: Windows English family, style and full name",
		a.family === "Demo Sans" &&
			a.style === "Bold" &&
			a.fullName === "Demo Sans Bold",
		JSON.stringify([a.family, a.style, a.fullName]),
	);
	ok(
		"name table: copyright, designer, license text and URL",
		a.copyright === "© 2026 Demo Co." &&
			a.designer === "Jane Doe" &&
			a.license === "Licensed under the OFL" &&
			a.licenseUrl === "https://example.test/ofl",
	);
	ok("OS/2 weight 700 is read", a.weight === 700);

	const typo = S.readFont(
		ttf({
			names: [
				[3, 0x409, 1, "Demo Serif Legacy"],
				[3, 0x409, 2, "Regular"],
				[3, 0x409, 16, "Demo Serif"],
				[3, 0x409, 17, "Black"],
			],
		}),
	);
	ok(
		"typographic family and style (IDs 16, 17) win over legacy ones",
		typo.family === "Demo Serif" && typo.style === "Black",
		`${typo.family} / ${typo.style}`,
	);

	const mac = S.readFont(
		ttf({
			names: [
				[1, 0, 1, "Mac Only"],
				[1, 0, 2, "Italic"],
			],
		}),
	);
	ok(
		"Mac Roman name used when there is no Windows name",
		mac.family === "Mac Only" && mac.style === "Italic",
		`${mac.family} / ${mac.style}`,
	);

	const win = S.readFont(
		ttf({
			names: [
				[1, 0, 1, "Mac Name"],
				[3, 0x407, 1, "German Name"],
				[3, 0x409, 1, "English Name"],
			],
		}),
	);
	ok(
		"Windows English beats Windows other language and Mac",
		win.family === "English Name",
		win.family,
	);

	const other = S.readFont(
		ttf({
			names: [
				[3, 0x407, 1, "German Name"],
				[1, 0, 1, "Mac Name"],
			],
		}),
	);
	ok(
		"Windows other language beats Mac Roman",
		other.family === "German Name",
		other.family,
	);

	const nul = S.readFont(
		ttf({
			names: [
				[3, 0x409, 1, "Nul Name\u0000\u0000"],
				[3, 0x409, 2, "Bold\u0000 "],
			],
		}),
	);
	ok(
		"a trailing NUL is stripped from name strings",
		nul.family === "Nul Name" && nul.style === "Bold",
		JSON.stringify([nul.family, nul.style]),
	);
	const padded = S.readFont(
		ttf({ names: [[3, 0x409, 1, "  Padded Name \t "]] }),
	);
	ok(
		"name strings are trimmed",
		padded.family === "Padded Name",
		JSON.stringify(padded.family),
	);

	const sel = (fsSelection) =>
		S.readFont(ttf({ os2: { italic: fsSelection } }));
	ok("fsSelection bit 0 sets italic", sel(true).italic === true);
	ok("upright fsSelection is not italic", sel(false).italic === false);

	const emb = (fsType) => S.readFont(ttf({ os2: { fsType } })).embedding;
	ok("fsType 0 is installable", emb(0) === "installable", emb(0));
	ok("fsType 0x0002 is restricted", emb(0x0002) === "restricted", emb(0x0002));
	ok("fsType 0x0004 is preview", emb(0x0004) === "preview", emb(0x0004));
	ok("fsType 0x0008 is editable", emb(0x0008) === "editable", emb(0x0008));
	ok(
		"fsType 0x0100 (no subsetting) stays installable",
		emb(0x0100) === "installable",
		emb(0x0100),
	);

	ok(
		"fvar table marks a variable font",
		S.readFont(ttf({ variable: true })).variable === true,
	);
	ok("no fvar table is static", S.readFont(ttf()).variable === false);

	const short = S.readFont(
		face([
			["OS/2", os2Table({ weight: 700 }).subarray(0, 40)],
			["name", nameTable(DEMO)],
		]),
	);
	ok(
		"short OS/2 table keeps the defaults",
		short.weight === 400 && short.embedding === "installable",
		`${short.weight} ${short.embedding}`,
	);
	ok(
		"name table is still read when OS/2 is short",
		short.family === "Demo Sans",
	);

	const padded2 = new Uint8Array(ttf({ names: DEMO, os2: { weight: 300 } }));
	const shifted = new Uint8Array(padded2.length + 7);
	shifted.set(padded2, 7);
	ok(
		"a view with a byte offset reads the same as the whole file",
		same(S.readFont(shifted.subarray(7)), S.readFont(padded2)),
	);

	const ttcFace = face(
		[
			["OS/2", os2Table({ weight: 500 })],
			[
				"name",
				nameTable([
					[3, 0x409, 1, "Collected Sans"],
					[3, 0x409, 2, "Medium"],
				]),
			],
		],
		16,
	);
	ttcFace.set([0x74, 0x74, 0x63, 0x66, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 16], 0); // "ttcf", v1.0, 1 face, offset 16
	const ttc = S.readFont(ttcFace);
	ok(
		"ttc reads its first face",
		ttc.format === "ttc" &&
			ttc.family === "Collected Sans" &&
			ttc.weight === 500,
		JSON.stringify([ttc.format, ttc.family, ttc.weight]),
	);

	const woff = S.readFont(
		Uint8Array.from("wOFF\x00\x01\x00\x00\0\0\0\0".split(""), (c) =>
			c.charCodeAt(0),
		),
	);
	ok(
		"woff is reported but not parsed",
		woff.format === "woff" && woff.family === "" && woff.weight === 400,
	);
	const woff2 = S.readFont(
		Uint8Array.from("wOF2\x00\x01\x00\x00\0\0\0\0".split(""), (c) =>
			c.charCodeAt(0),
		),
	);
	ok(
		"woff2 is reported but not parsed",
		woff2.format === "woff2" && woff2.family === "",
	);

	const garbage = S.readFont(
		new Uint8Array([0xde, 0xad, 0xbe, 0xef, 1, 2, 3, 4, 5, 6, 7, 8]),
	);
	ok(
		"garbage bytes give unknown with defaults",
		garbage.format === "unknown" &&
			garbage.family === "" &&
			garbage.embedding === "installable",
	);
	ok(
		"empty input does not throw",
		S.readFont(new Uint8Array(0)).format === "unknown",
	);

	const lato = repoFont("src/core/assets/Lato-Regular.ttf");
	const cut = S.readFont(lato.slice(0, 200));
	ok("a file cut short does not throw", cut.format === "ttf", cut.format);

	const bad = new Uint8Array(ttf({ names: DEMO }));
	new DataView(bad.buffer).setUint16(4, 0xffff); // claims 65535 tables
	ok(
		"a table count past the end does not throw",
		S.readFont(bad).format === "ttf",
	);
}

// ------------------------------------------------------------ catalog helpers (no fetch)

const fam = (
	name,
	category,
	designer,
	styles = [{ key: "400", weight: 400, italic: false }],
	extra = {},
) => ({
	name,
	category,
	designer,
	license: "OFL",
	dir: `ofl/${name.toLowerCase().replace(/\s/g, "")}`,
	subsets: ["latin"],
	styles,
	files: {},
	...extra,
});
const R = { weight: 400, italic: false, key: "400" };
const st = (weight, italic = false) => ({
	key: `${weight}${italic ? "i" : ""}`,
	weight,
	italic,
});

{
	ok("styleName: Regular", C.styleName(st(400)) === "Regular");
	ok("styleName: Bold", C.styleName(st(700)) === "Bold");
	ok(
		"styleName: upright 400 italic is Italic",
		C.styleName(st(400, true)) === "Italic",
	);
	ok("styleName: Bold Italic", C.styleName(st(700, true)) === "BoldItalic");
	ok("styleName: Light Italic", C.styleName(st(300, true)) === "LightItalic");
	ok(
		"styleName: unnamed weight uses its number",
		C.styleName(st(550)) === "550" &&
			C.styleName(st(550, true)) === "550Italic",
	);

	ok(
		"styleLabel: Regular 400",
		C.styleLabel(st(400)) === "Regular 400",
		C.styleLabel(st(400)),
	);
	ok("styleLabel: Bold 700", C.styleLabel(st(700)) === "Bold 700");
	ok("styleLabel: Italic 400", C.styleLabel(st(400, true)) === "Italic 400");
	ok(
		"styleLabel: Bold Italic 700",
		C.styleLabel(st(700, true)) === "Bold Italic 700",
	);
	ok(
		"styleLabel: unnamed weight shows the number",
		C.styleLabel(st(550)) === "550",
		C.styleLabel(st(550)),
	);

	const list = [
		fam("Slab Robot", "serif", "Ann Other"),
		fam("Roboto Slab", "serif", "Christian Robertson"),
		fam("Roboto", "sans-serif", "Christian Robertson"),
		fam("Fira Mono", "monospace", "Mozilla"),
		fam("Playfair Display", "serif", "Claus Eggers Sørensen"),
		fam("Bebas Neue", "display", "Dharma Type"),
		fam("Noto Sans", "sans-serif", "Google"),
	];
	const names = (r) => r.map((f) => f.name);

	ok(
		"search: name prefix ranks before a name containing the query",
		same(names(C.search(list, "rob")), ["Roboto Slab", "Roboto", "Slab Robot"]),
		JSON.stringify(names(C.search(list, "rob"))),
	);
	ok(
		"search: matches by designer",
		same(names(C.search(list, "eggers")), ["Playfair Display"]),
	);
	ok(
		"search: designer-only match ranks after name matches",
		same(
			names(
				C.search(
					[
						fam("Mono Font", "monospace", "Robo Ted"),
						fam("Zeta Robo", "display", "X"),
						fam("Robo Sans", "sans-serif", "Y"),
					],
					"robo",
				),
			),
			["Robo Sans", "Zeta Robo", "Mono Font"],
		),
	);
	ok(
		"search: case and surrounding spaces are ignored",
		same(names(C.search(list, "  FIRA ")), ["Fira Mono"]),
	);
	ok(
		"search: empty query returns every family",
		C.search(list, "").length === list.length,
	);
	ok(
		"search: category filter with an empty query",
		same(names(C.search(list, "", "monospace")), ["Fira Mono"]),
	);
	ok(
		"search: category filter applies to matches",
		same(names(C.search(list, "o", "serif")), ["Slab Robot", "Roboto Slab"]),
		JSON.stringify(names(C.search(list, "o", "serif"))),
	);
	ok(
		"search: no match returns an empty list",
		C.search(list, "zzz").length === 0,
	);

	const pf = fam("Playfair Display", "serif", "x", [
		st(700, true),
		st(400),
		st(400, true),
		st(700),
	]);
	ok("mainStyle: Regular when there is one", C.mainStyle(pf).key === "400");
	ok(
		"mainStyle: first style when there is no Regular",
		C.mainStyle(fam("Bold Only", "display", "x", [st(700), st(900)])).key ===
			"700",
	);

	const P = fam("Playfair Display", "serif", "x");
	const PB = { key: "700", weight: 700, italic: false };
	const PBI = { key: "700i", weight: 700, italic: true };
	const PI = { key: "400i", weight: 400, italic: true };
	ok(
		"fileStem: PlayfairDisplay-BoldItalic",
		C.fileStem(P, PBI) === "PlayfairDisplay-BoldItalic",
		C.fileStem(P, PBI),
	);
	ok(
		"fileStem: Bebas-Regular",
		C.fileStem(fam("Bebas", "display", "x"), R) === "Bebas-Regular",
	);
	ok(
		"fileStem: removes spaces and symbols",
		C.fileStem(fam("Noto Sans 2.0!", "sans-serif", "x"), PB) ===
			"NotoSans20-Bold",
	);
	ok(
		"fileStem: unnamed weight uses its number",
		C.fileStem(P, st(550)) === "PlayfairDisplay-550",
	);

	ok(
		"fontName: Playfair Display 400 is playfair_display",
		C.fontName(P, R) === "playfair_display",
	);
	ok(
		"fontName: Playfair Display 700 is playfair_display_bold",
		C.fontName(P, PB) === "playfair_display_bold",
	);
	ok(
		"fontName: Playfair Display 400 italic is playfair_display_italic",
		C.fontName(P, PI) === "playfair_display_italic",
	);
	ok(
		"fontName: Playfair Display 700 italic is playfair_display_bold_italic",
		C.fontName(P, PBI) === "playfair_display_bold_italic",
	);
	ok(
		"fontName: punctuation becomes underscores",
		C.fontName(fam("Noto Sans-Mono", "monospace", "x"), R) === "noto_sans_mono",
	);
	ok(
		"fontName: a leading digit gets an f_ prefix",
		C.fontName(fam("3 Dots", "display", "x"), R) === "f_3_dots",
		C.fontName(fam("3 Dots", "display", "x"), R),
	);
	ok(
		"fontName: unnamed weight",
		C.fontName(P, st(550)) === "playfair_display_550",
		C.fontName(P, st(550)),
	);
	ok(
		"fontName: unnamed italic weight",
		C.fontName(P, st(550, true)) === "playfair_display_550_italic",
		C.fontName(P, st(550, true)),
	);
}

// ------------------------------------------------------------ loadCatalog and fetch

const calls = [];
let route = () => {
	throw new Error("no route");
};
const reply = (body, status = 200) => ({
	ok: status >= 200 && status < 300,
	status,
	json: async () => body,
	text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
	arrayBuffer: async () => new Uint8Array(0).buffer,
});
globalThis.fetch = async (url) => {
	calls.push(String(url));
	return route(String(url));
};

const SYNTH = {
	source: "test",
	generated: "2026-01-01",
	licenseBase: "https://raw.example.test/fonts/main/",
	licenseFiles: { OFL: "OFL.txt", APACHE2: "LICENSE.txt", UFL: "UFL.txt" },
	fileBase: "https://files.example.test/s/",
	families: [
		{
			n: "Playfair Display",
			c: "serif",
			d: "Claus Eggers Sørensen",
			l: "OFL",
			p: "ofl/playfairdisplay",
			s: ["latin"],
			u: "pf/v40/",
			f: { "700i": "abc", 400: "def/ghi", "400i": "jkl", 700: "mno" },
		},
		{
			n: "Lato",
			c: "sans-serif",
			d: "Łukasz",
			l: "OFL",
			p: "ofl/lato",
			s: ["latin"],
			u: "lato/v1/",
			f: { 400: "xyz" },
		},
	],
};

{
	let threw = false;
	try {
		C.fileUrl(fam("X", "serif", "x"), R);
	} catch {
		threw = true;
	}
	ok("fileUrl before the catalog is loaded throws", threw);

	// First load fails with a 404, then a retry succeeds.
	route = () => reply({}, 404);
	let msg = "";
	try {
		await C.loadCatalog();
	} catch (e) {
		msg = e.message;
	}
	ok(
		"loadCatalog reports a missing catalog",
		msg === "Font catalog not found (404)",
		msg,
	);

	route = () => reply(SYNTH);
	const list = await C.loadCatalog();
	ok(
		"loadCatalog retries after a failure",
		list.length === 2 && calls.length === 2,
		`${list.length} families, ${calls.length} fetches`,
	);
	ok(
		"loadCatalog fetches the default catalog URL",
		calls[0] === "fonts/google-fonts.json",
		calls[0],
	);

	const pf = list[0];
	ok(
		"loadCatalog keeps name, category, designer, license and dir",
		pf.name === "Playfair Display" &&
			pf.category === "serif" &&
			pf.designer === "Claus Eggers Sørensen" &&
			pf.license === "OFL" &&
			pf.dir === "ofl/playfairdisplay",
		JSON.stringify(pf),
	);
	ok(
		"styles: upright first by weight, then italic",
		same(
			pf.styles.map((s) => s.key),
			["400", "700", "400i", "700i"],
		),
		JSON.stringify(pf.styles.map((s) => s.key)),
	);
	ok(
		"style italic flag comes from the key suffix",
		same(
			pf.styles.map((s) => s.italic),
			[false, false, true, true],
		),
	);
	ok(
		"style weight comes from the key",
		same(
			pf.styles.map((s) => s.weight),
			[400, 700, 400, 700],
		),
	);
	ok(
		"file id with a slash is used as the full path",
		C.fileUrl(pf, pf.styles[0]) === "https://files.example.test/s/def/ghi.ttf",
		C.fileUrl(pf, pf.styles[0]),
	);
	ok(
		"file id without a slash is prefixed with the family folder",
		C.fileUrl(pf, pf.styles[3]) ===
			"https://files.example.test/s/pf/v40/abc.ttf",
		C.fileUrl(pf, pf.styles[3]),
	);

	const again = await C.loadCatalog();
	ok(
		"loadCatalog returns the cached list without fetching again",
		again === list && calls.length === 2,
		`fetches: ${calls.length}`,
	);

	route = () => reply("license text for the family");
	calls.length = 0;
	const lic = await C.downloadLicense(pf);
	ok(
		"downloadLicense uses the family folder and the OFL file",
		calls[0] ===
			"https://raw.example.test/fonts/main/ofl/playfairdisplay/OFL.txt" &&
			lic === "license text for the family",
		calls[0],
	);

	route = () => reply({}, 500);
	let dl = "";
	try {
		await C.downloadStyle(pf, pf.styles[0]);
	} catch (e) {
		dl = e.message;
	}
	ok(
		"downloadStyle reports a failed download",
		dl === "Playfair Display Regular 400: download failed (500)",
		dl,
	);

	// Real catalog, in a fresh module instance so the cache above does not apply.
	const real = process.env.FONT_CATALOG;
	if (real && existsSync(real)) {
		const fresh = await import(`../src/lib/fonts/catalog.ts?real=1`);
		const json = JSON.parse(readFileSync(real, "utf8"));
		route = (url) => {
			if (url !== "fonts/google-fonts.json")
				throw new Error(`unexpected ${url}`);
			return reply(json);
		};
		const all = await fresh.loadCatalog();
		ok(
			"real catalog loads every family",
			all.length === json.families.length,
			`${all.length}`,
		);
		const pfr = all.find((f) => f.name === "Playfair Display");
		ok(
			"real catalog: Playfair Display has 12 styles",
			pfr?.styles.length === 12,
			`${pfr?.styles.length}`,
		);
		ok(
			"real catalog: Playfair Display main style is 400",
			pfr && fresh.mainStyle(pfr).key === "400",
		);
		ok(
			"real catalog: fileStem for 700 italic",
			pfr &&
				fresh.fileStem(
					pfr,
					pfr.styles.find((s) => s.key === "700i"),
				) === "PlayfairDisplay-BoldItalic",
		);
		ok(
			"real catalog: fontName for 400 italic",
			pfr &&
				fresh.fontName(
					pfr,
					pfr.styles.find((s) => s.key === "400i"),
				) === "playfair_display_italic",
		);
		ok(
			"real catalog: fileUrl for 700",
			pfr &&
				fresh.fileUrl(
					pfr,
					pfr.styles.find((s) => s.key === "700"),
				) ===
					"https://fonts.gstatic.com/s/playfairdisplay/v40/nuFvD-vYSZviVYUb_rj3ij__anPXJzDwcbmjWBN2PKeiukDQ.ttf",
		);
		ok(
			"real catalog: search 'lato' finds Lato first",
			fresh.search(all, "lato")[0]?.name === "Lato",
			fresh.search(all, "lato")[0]?.name,
		);
		ok(
			"real catalog: search 'eggers' finds Playfair Display",
			fresh.search(all, "eggers").some((f) => f.name === "Playfair Display"),
		);
	} else {
		skip("real Google Fonts catalog", "set FONT_CATALOG to google-fonts.json");
	}
}

// ------------------------------------------------------------ project fonts (project.ts)

const enc = (s) => new TextEncoder().encode(s);
const repoText = (p) => readFileSync(here(`../../${p}`), "utf8");
const files = (entries) => new Map(entries);
const BEBAS = "examples/board-game/assets/fonts/BebasNeue-Regular.ttf";
const BEBAS_LIC =
	"examples/board-game/assets/fonts/BebasNeue-Regular-license.txt";
// The kind of free-font EULA that forbids sharing the font file.
const EULA =
	"FREE FONT END USER LICENSE AGREEMENT\n1. You may use this font for commercial and non-commercial works.\n4. You may not redistribute this font without permission.";
const DM = "examples/poker/assets/fonts/DMSerifDisplay-Regular.ttf";
const DM_LIC = "examples/poker/assets/fonts/DMSerifDisplay-Regular-license.txt";
const SHARED_OFL = "src/core/assets/OFL.txt";
const SHARED_NOTO = "src/core/assets/NotoSansSymbols2-OFL.txt";

{
	ok(
		"licensePathFor: sidecar next to the font",
		P.licensePathFor("fonts/Bebas-Regular.ttf") ===
			"fonts/Bebas-Regular-license.txt",
	);
	ok(
		"licensePathFor: dots in folders are kept",
		P.licensePathFor("a.b/c.otf") === "a.b/c-license.txt",
		P.licensePathFor("a.b/c.otf"),
	);
	ok(
		"licensePathFor: file without extension",
		P.licensePathFor("noext") === "noext-license.txt",
	);

	const own = files([
		["fonts/X.ttf", new Uint8Array(1)],
		["fonts/X-license.txt", enc("own")],
		["fonts/OFL.txt", enc("shared")],
	]);
	ok(
		"findLicense: own sidecar wins over a shared OFL.txt",
		P.findLicense(own, "fonts/X.ttf") === "fonts/X-license.txt",
	);

	const shared = files([
		["fonts/X.ttf", new Uint8Array(1)],
		["fonts/OFL.txt", enc("shared")],
		["fonts/Other-OFL.txt", enc("")],
	]);
	ok(
		"findLicense: shared OFL.txt in the same folder",
		P.findLicense(shared, "fonts/X.ttf") === "fonts/OFL.txt",
	);

	const cased = files([
		["fonts/X.ttf", new Uint8Array(1)],
		["fonts/license.MD", enc("")],
	]);
	ok(
		"findLicense: shared names match any case and .md",
		P.findLicense(cased, "fonts/X.ttf") === "fonts/license.MD",
	);

	const sub = files([
		["fonts/X.ttf", new Uint8Array(1)],
		["fonts/sub/OFL.txt", enc("")],
	]);
	ok(
		"findLicense: a license in a subfolder is not used",
		P.findLicense(sub, "fonts/X.ttf") === null,
	);

	const root = files([
		["X.ttf", new Uint8Array(1)],
		["OFL.txt", enc("")],
	]);
	ok(
		"findLicense: root folder shared file",
		P.findLicense(root, "X.ttf") === "OFL.txt",
	);

	const none = files([["fonts/X.ttf", new Uint8Array(1)]]);
	ok(
		"findLicense: no license gives null",
		P.findLicense(none, "fonts/X.ttf") === null,
	);

	ok(
		"licenseKind: a no-redistribution EULA is restricted",
		P.licenseKind(EULA) === "restricted",
		P.licenseKind(EULA),
	);
	ok(
		"licenseKind: Bebas Neue sidecar (OFL with header) is OFL",
		P.licenseKind(repoText(BEBAS_LIC)) === "OFL",
		P.licenseKind(repoText(BEBAS_LIC)),
	);
	ok(
		"licenseKind: DM Serif sidecar (OFL) is OFL",
		P.licenseKind(repoText(DM_LIC)) === "OFL",
	);
	ok(
		"licenseKind: shared OFL.txt is OFL",
		P.licenseKind(repoText(SHARED_OFL)) === "OFL",
	);
	ok(
		"licenseKind: Noto OFL text is OFL",
		P.licenseKind(repoText(SHARED_NOTO)) === "OFL",
	);
	ok(
		"licenseKind: Apache text is APACHE2",
		P.licenseKind("Apache License Version 2.0, January 2004") === "APACHE2",
	);
	ok(
		"licenseKind: Ubuntu text is UFL",
		P.licenseKind("Ubuntu Font Licence 1.0") === "UFL",
	);
	ok("licenseKind: empty text is other", P.licenseKind("") === "other");
	ok(
		"licenseKind: unrelated text is other",
		P.licenseKind("All rights reserved.") === "other",
	);

	const bebas = P.projectFont(
		files([
			[BEBAS, repoFont(BEBAS)],
			[BEBAS_LIC, enc(repoText(BEBAS_LIC))],
		]),
		BEBAS,
	);
	ok(
		"projectFont: reads the font and its sidecar",
		bebas?.info.family === "Bebas Neue" &&
			bebas.license?.path === BEBAS_LIC &&
			bebas.license.kind === "OFL",
		JSON.stringify({
			f: bebas?.info.family,
			l: bebas?.license?.path,
			k: bebas?.license?.kind,
		}),
	);
	ok(
		"projectFont: missing path gives null",
		P.projectFont(new Map(), BEBAS) === null,
	);
	const bare = P.projectFont(files([[BEBAS, repoFont(BEBAS)]]), BEBAS);
	ok("projectFont: no sidecar gives license null", bare?.license === null);

	ok(
		"fontWarning: Bebas Neue with its OFL sidecar has no warning",
		P.fontWarning(bebas) === "",
		P.fontWarning(bebas),
	);
	const eula = P.projectFont(
		files([
			[BEBAS, repoFont(BEBAS)],
			[BEBAS_LIC, enc(EULA)],
		]),
		BEBAS,
	);
	const eulaWarn = P.fontWarning(eula);
	ok(
		"fontWarning: a no-redistribution EULA warns about sharing",
		eulaWarn.includes("license limits sharing"),
		eulaWarn,
	);

	const dm = P.projectFont(
		files([
			[DM, repoFont(DM)],
			[DM_LIC, enc(repoText(DM_LIC))],
		]),
		DM,
	);
	ok(
		"fontWarning: OFL font with sidecar has no warning",
		dm && P.fontWarning(dm) === "",
		dm && P.fontWarning(dm),
	);

	const noLic = P.projectFont(
		files([["fonts/Plain.ttf", ttf({ names: [[3, 0x409, 1, "Plain"]] })]]),
		"fonts/Plain.ttf",
	);
	ok(
		"fontWarning: no license anywhere warns",
		noLic && P.fontWarning(noLic).startsWith("No license file found"),
		noLic && P.fontWarning(noLic),
	);

	const named = P.projectFont(
		files([
			[
				"fonts/Named.ttf",
				ttf({
					names: [
						[3, 0x409, 1, "Named"],
						[3, 0x409, 13, "Licensed under the OFL"],
					],
				}),
			],
		]),
		"fonts/Named.ttf",
	);
	ok(
		"fontWarning: a license named inside the font is enough",
		named && P.fontWarning(named) === "",
		named && P.fontWarning(named),
	);

	const emb = P.projectFont(
		files([
			[
				"fonts/Emb.ttf",
				ttf({ names: [[3, 0x409, 1, "Emb"]], os2: { fsType: 0x0002 } }),
			],
			["fonts/OFL.txt", enc(repoText(SHARED_OFL))],
		]),
		"fonts/Emb.ttf",
	);
	ok(
		"fontWarning: restricted embedding warns",
		emb && P.fontWarning(emb).includes("may not be embedded"),
		emb && P.fontWarning(emb),
	);

	const vari = P.projectFont(
		files([
			["fonts/V.ttf", ttf({ names: [[3, 0x409, 1, "V"]], variable: true })],
			["fonts/OFL.txt", enc(repoText(SHARED_OFL))],
		]),
		"fonts/V.ttf",
	);
	ok(
		"fontWarning: variable font warns",
		vari && P.fontWarning(vari).startsWith("A variable font"),
		vari && P.fontWarning(vari),
	);

	const woff = P.projectFont(
		files([["fonts/W.woff2", enc("wOF2\x00\x01\x00\x00")]]),
		"fonts/W.woff2",
	);
	ok(
		"fontWarning: woff2 is not drawable",
		woff && P.fontWarning(woff).startsWith("This file is not a TrueType"),
		woff && P.fontWarning(woff),
	);

	ok(
		"freeFontName: free name is kept",
		P.freeFontName("inter", []) === "inter",
	);
	ok(
		"freeFontName: taken name gets _2",
		P.freeFontName("inter", ["inter"]) === "inter_2",
	);
	ok(
		"freeFontName: next free suffix",
		P.freeFontName("inter", new Set(["inter", "inter_2"])) === "inter_3",
	);
	ok(
		"freeFontName: fills the first gap",
		P.freeFontName("inter", ["inter", "inter_3"]) === "inter_2",
	);
	ok(
		"freeFontName: lowercases and replaces symbols",
		P.freeFontName("My Font!", []) === "my_font",
		P.freeFontName("My Font!", []),
	);
	ok("freeFontName: digit start gets f_", P.freeFontName("3d", []) === "f_3d");
	ok(
		"freeFontName: empty name gets f_font",
		P.freeFontName("", []) === "f_font",
	);
	ok(
		"freeFontName: case of taken names counts",
		P.freeFontName("Inter", ["inter"]) === "inter_2",
	);

	ok(
		"nameForFile: family and style",
		P.nameForFile("fonts/x.ttf", { family: "Inter", style: "Bold" }) ===
			"Inter_Bold",
	);
	ok(
		"nameForFile: Regular style is left out",
		P.nameForFile("a/b.ttf", { family: "Inter", style: "Regular" }) === "Inter",
	);
	ok(
		"nameForFile: multi-word style",
		P.nameForFile("a/b.ttf", { family: "Noto Sans", style: "Semi Bold" }) ===
			"Noto_Sans_Semi_Bold",
	);
	ok(
		"nameForFile: no family uses the file name",
		P.nameForFile("a/b.otf", { family: "", style: "" }) === "b",
	);
	ok(
		"nameForFile: file name dashes become underscores",
		P.nameForFile("dir/Lato-Regular.ttf", { family: "", style: "" }) ===
			"Lato_Regular",
	);

	const doc = {
		layers: [
			{ id: "t1", type: "text", font: "inter" },
			{
				id: "g",
				type: "group",
				layers: [
					{ id: "t2", type: "text", font: "inter" },
					{
						id: "g2",
						type: "group",
						layers: [
							{ id: "t3", type: "text", font: "other" },
							{ id: "t5", type: "text", font: "inter" },
						],
					},
				],
			},
			{ id: "t4", type: "text" },
		],
	};
	ok(
		"layersUsing: finds layers in nested groups",
		same(P.layersUsing(doc, "inter"), ["t1", "t2", "t5"]),
		JSON.stringify(P.layersUsing(doc, "inter")),
	);
	ok(
		"layersUsing: other font in a deeper group",
		same(P.layersUsing(doc, "other"), ["t3"]),
	);
	ok(
		"layersUsing: text without a font is the default font",
		same(P.layersUsing(doc, "default"), ["t4"]),
	);
	ok(
		"layersUsing: no document or no layers gives []",
		same(P.layersUsing(null, "x"), []) && same(P.layersUsing({}, "x"), []),
	);
	ok(
		"layersUsing: a layer without an id is reported as ?",
		same(P.layersUsing({ layers: [{ type: "text", font: "a" }] }, "a"), ["?"]),
	);
}

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
