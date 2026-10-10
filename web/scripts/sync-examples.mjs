// Copies example projects into public/examples and writes an index the
// editor uses to list and load them.
//
//   node scripts/sync-examples.mjs SRC DST [--public]
//
// --public leaves out the files listed in SRC/.public-exclude (one path
// per line, relative to SRC, `*` matches within a name, # starts a
// comment): fonts that may be used privately but not published.
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const pub = args.includes("--public");
const [src, dst] = args.filter((a) => !a.startsWith("--"));
const excludeFile = path.join(src, ".public-exclude");
const excluded = (
	pub && fs.existsSync(excludeFile)
		? fs.readFileSync(excludeFile, "utf8").split("\n")
		: []
)
	.map((l) => l.replace(/#.*/, "").trim())
	.filter(Boolean)
	.map(
		(l) =>
			new RegExp(
				"^" +
					l
						.split("*")
						.map((x) => x.replace(/[.+?^${}()|[\]\\]/g, "\\$&"))
						.join("[^/]*") +
					"$",
			),
	);
let skipped = 0;
fs.rmSync(dst, { recursive: true, force: true });
const index = [];
for (const name of fs.readdirSync(src).sort()) {
	const root = path.join(src, name);
	if (!fs.statSync(root).isDirectory()) continue;
	const files = [];
	const walk = (dir, rel) => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const r = rel ? `${rel}/${e.name}` : e.name;
			if (e.isDirectory()) walk(path.join(dir, e.name), r);
			else if (excluded.some((x) => x.test(`${name}/${r}`))) skipped++;
			else {
				files.push(r);
				const out = path.join(dst, name, r);
				fs.mkdirSync(path.dirname(out), { recursive: true });
				fs.copyFileSync(path.join(dir, e.name), out);
			}
		}
	};
	walk(root, "");
	let title = name;
	const manifest = path.join(root, "yoshida.json");
	if (fs.existsSync(manifest))
		title = JSON.parse(fs.readFileSync(manifest, "utf8")).name ?? name;
	index.push({ name, title, files: files.sort() });
}
fs.writeFileSync(
	path.join(dst, "index.json"),
	`${JSON.stringify(index, null, 2)}\n`,
);
console.log(
	`synced ${index.length} example(s) into ${dst}` +
		(pub ? `, left out ${skipped} non-public file(s)` : ""),
);
