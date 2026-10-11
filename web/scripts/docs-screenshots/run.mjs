// Retakes the screenshots used by the documentation site.
//
//   npm run docs:screenshots                  (from web/, after `npm run build`)
//   npm run docs:screenshots -- --only editor-params,editor-files
//   npm run docs:screenshots -- --section card-data --theme dark
//   npm run docs:screenshots -- --build       (build the editor first)
//   npm run docs:screenshots -- --base http://localhost:4173/   (use a running editor)
//
// Every shot lives in shots/*.mjs and says which docs page uses it. Images go
// to ../site/static/docs/images/ as <name>-light.png and <name>-dark.png
// (<name>.png for shots that do not show the editor), and manifest.json lists them.
import { spawn, spawnSync } from "node:child_process";
import { mkdir, readdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { launch, open } from "./lib.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, "..", "..");
const args = process.argv.slice(2);
const opt = (name) => {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? args[i + 1] : undefined;
};
const only = opt("only")?.split(",");
const section = opt("section");
const themeOnly = opt("theme");
const out = opt("out") ?? join(web, "..", "site", "static", "docs", "images");
let base = opt("base");

if (args.includes("--build")) {
	const r = spawnSync("npm", ["run", "build"], { cwd: web, stdio: "inherit" });
	if (r.status !== 0) process.exit(r.status ?? 1);
}

let server;
if (!base) {
	const port = 4300 + Math.floor(Math.random() * 500);
	server = spawn("npx", ["vite", "preview", "--port", String(port), "--strictPort"], {
		cwd: web,
		stdio: "ignore",
	});
	base = `http://localhost:${port}/`;
	for (let i = 0; i < 50; i++) {
		try {
			if ((await fetch(base)).ok) break;
		} catch {}
		await new Promise((r) => setTimeout(r, 200));
	}
}

await mkdir(out, { recursive: true });
const files = (await readdir(join(here, "shots"))).filter((f) => f.endsWith(".mjs")).sort();
const shots = [];
for (const f of files) {
	const mod = await import(pathToFileURL(join(here, "shots", f)).href);
	shots.push(...mod.shots.map((s) => ({ ...s, section: s.section ?? f.replace(/\.mjs$/, "") })));
}

const browser = await launch();
const manifest = [];
let failed = 0;
for (const s of shots) {
	if (only && !only.includes(s.name)) continue;
	if (section && s.section !== section) continue;
	const themes = s.themes === false ? [null] : themeOnly ? [themeOnly] : ["light", "dark"];
	const images = [];
	for (const theme of themes) {
		const file = theme ? `${s.name}-${theme}.png` : `${s.name}.png`;
		try {
			const h = await open(browser, { base, theme: theme ?? "light", project: s.project, viewport: s.viewport });
			const clip = await s.run(h);
			await h.settle();
			await h.save(join(out, file), clip ?? undefined);
			if (h.logs.length) console.log(`  console problems in ${file}:\n    ${h.logs.join("\n    ")}`);
			await h.ctx.close();
			images.push(file);
			console.log(`ok   ${file}`);
		} catch (e) {
			failed++;
			console.log(`FAIL ${file}: ${e.message.split("\n")[0]}`);
		}
	}
	manifest.push({ name: s.name, section: s.section, page: s.page, alt: s.alt, images });
}
await browser.close();
server?.kill();
if (!only && !section && !themeOnly) {
	await writeFile(join(here, "manifest.json"), `${JSON.stringify(manifest, null, "\t")}\n`);
}
process.exit(failed ? 1 : 0);
