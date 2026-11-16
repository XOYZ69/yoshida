// Runs the browser tests (tests/ui*.mjs), one file after another, and reports
// every file that failed instead of stopping at the first one.
//
//   node tests/run-ui.mjs [URL] [--shard 2/3] [--list]
//
// URL is passed to every file (default: BASE_URL, then http://localhost:4173/).
// --shard i/n runs only the files of group i out of n, so CI can run the
// groups in parallel jobs. The groups are balanced by file size, which tracks
// the running time well enough, and do not change between runs. --list prints
// the files the options select and runs nothing.
import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
let shard = null;
let list = false;
let url = process.env.BASE_URL ?? "http://localhost:4173/";
for (let i = 0; i < args.length; i++) {
	if (args[i] === "--shard") {
		const m = /^(\d+)\/(\d+)$/.exec(args[++i] ?? "");
		if (!m || +m[1] < 1 || +m[1] > +m[2]) {
			console.error("usage: --shard i/n with 1 <= i <= n");
			process.exit(2);
		}
		shard = { index: +m[1], count: +m[2] };
	} else if (args[i] === "--list") list = true;
	else url = args[i];
}

const files = readdirSync(dir)
	.filter((f) => /^ui(-.+)?\.mjs$/.test(f))
	.sort();

// Largest file first into the group with the least bytes so far.
function select(all, s) {
	if (!s) return all;
	const groups = Array.from({ length: s.count }, () => ({ size: 0, files: [] }));
	const bySize = all
		.map((f) => ({ f, size: statSync(join(dir, f)).size }))
		.sort((a, b) => b.size - a.size || a.f.localeCompare(b.f));
	for (const { f, size } of bySize) {
		const g = groups.reduce((a, b) => (b.size < a.size ? b : a));
		g.size += size;
		g.files.push(f);
	}
	return groups[s.index - 1].files.sort();
}

const chosen = select(files, shard);
if (list) {
	console.log(chosen.join("\n"));
	process.exit(0);
}
if (!chosen.length) {
	console.error("no test files selected");
	process.exit(2);
}

const failed = [];
for (const f of chosen) {
	console.log(`\n=== ${f} ===`);
	const t0 = Date.now();
	const r = spawnSync(process.execPath, [join("tests", f), url], { stdio: "inherit" });
	const secs = ((Date.now() - t0) / 1000).toFixed(1);
	console.log(`=== ${f}: ${r.status === 0 ? "ok" : "FAILED"} in ${secs} s ===`);
	if (r.status !== 0) failed.push(f);
}
console.log(
	failed.length
		? `\n${failed.length} of ${chosen.length} file(s) failed:\n${failed.map((f) => `  ${f}`).join("\n")}`
		: `\nall ${chosen.length} file(s) passed`,
);
process.exit(failed.length ? 1 : 0);
