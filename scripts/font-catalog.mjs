#!/usr/bin/env node
// Builds web/public/fonts/google-fonts.json, the catalog behind the editor's
// "Google Fonts" tab. No API key is needed:
//   - family names come from google/fonts tags/all/families.csv
//   - designer, license, category, subsets and styles from each METADATA.pb
//   - static TTF urls from the Google Fonts CSS API (css2). A non-browser
//     User-Agent makes it answer with full .ttf files instead of woff2 slices.
// Usage: node scripts/font-catalog.mjs [out.json] [--limit N]

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const limitAt = args.indexOf("--limit");
const limit = limitAt >= 0 ? Number(args.splice(limitAt, 2)[1]) : Infinity;
const out = resolve(args[0] ?? `${root}/web/public/fonts/google-fonts.json`);

const RAW = "https://raw.githubusercontent.com/google/fonts/main";
const CSS = "https://fonts.googleapis.com/css2";
const GSTATIC = "https://fonts.gstatic.com/s/";
const UA = "yoshida-font-catalog/1 (+https://github.com/XOYZ69)";
const LICENSE_DIRS = { OFL: "ofl", APACHE2: "apache", UFL: "ufl" };
const LICENSE_FILES = {
	OFL: "OFL.txt",
	APACHE2: "LICENSE.txt",
	UFL: "UFL.txt",
};
const CATEGORIES = {
	SANS_SERIF: "sans-serif",
	SERIF: "serif",
	DISPLAY: "display",
	HANDWRITING: "handwriting",
	MONOSPACE: "monospace",
};

async function get(url, tries = 4) {
	for (let i = 0; ; i++) {
		try {
			const r = await fetch(url, { headers: { "user-agent": UA } });
			if (r.status === 404) return null;
			if (!r.ok) throw new Error(`${r.status} ${url}`);
			return await r.text();
		} catch (e) {
			if (i + 1 >= tries) throw e;
			await new Promise((ok) => setTimeout(ok, 500 * 2 ** i));
		}
	}
}

function parseCsvNames(text) {
	const names = new Set();
	for (const line of text.split("\n")) {
		if (!line.trim()) continue;
		const m = line.match(/^"([^"]*)"|^([^,]*)/);
		const name = (m[1] ?? m[2]).trim();
		if (name && name !== "Family") names.add(name);
	}
	return [...names].sort((a, b) => a.localeCompare(b));
}

// METADATA.pb is protobuf text format; only the fields used here are read.
function parseMetadata(text) {
	const top = text.replace(
		/^\s*(fonts|axes|source|registry_default_overrides)\s*\{[\s\S]*?^\}/gm,
		"",
	);
	const all = (re, src) => [...src.matchAll(re)].map((m) => m[1]);
	const one = (key, src = top) =>
		src.match(new RegExp(`^\\s*${key}:\\s*"([^"]*)"`, "m"))?.[1];
	const fonts = [...text.matchAll(/^fonts\s*\{([\s\S]*?)^\}/gm)].map((m) => ({
		style: one("style", m[1]),
		weight: Number(m[1].match(/weight:\s*(\d+)/)?.[1] ?? 400),
	}));
	const wght = [...text.matchAll(/^axes\s*\{([\s\S]*?)^\}/gm)]
		.map((m) => m[1])
		.find((b) => /tag:\s*"wght"/.test(b));
	return {
		name: one("name"),
		designer: one("designer"),
		license: one("license"),
		category: all(/^category:\s*"([^"]*)"/gm, top),
		subsets: all(/^subsets:\s*"([^"]*)"/gm, top).filter((s) => s !== "menu"),
		fonts,
		wght: wght && [
			Number(wght.match(/min_value:\s*([\d.]+)/)[1]),
			Number(wght.match(/max_value:\s*([\d.]+)/)[1]),
		],
	};
}

function variantsOf(meta) {
	const styles = [...new Set(meta.fonts.map((f) => f.style))];
	const list = [];
	for (const style of styles) {
		if (meta.wght) {
			for (let w = 100; w <= 900; w += 100)
				if (w >= meta.wght[0] && w <= meta.wght[1])
					list.push([style === "italic" ? 1 : 0, w]);
		} else {
			for (const f of meta.fonts)
				if (f.style === style)
					list.push([style === "italic" ? 1 : 0, f.weight]);
		}
	}
	return list.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
}

async function family(name) {
	const dir = name.toLowerCase().replace(/[^a-z0-9]/g, "");
	let meta = null;
	let path = "";
	for (const lic of Object.values(LICENSE_DIRS)) {
		const text = await get(`${RAW}/${lic}/${dir}/METADATA.pb`);
		if (text) {
			meta = parseMetadata(text);
			path = `${lic}/${dir}`;
			break;
		}
	}
	if (!meta || !LICENSE_FILES[meta.license]) return null;
	const variants = variantsOf(meta);
	if (!variants.length) return null;
	const spec = `${meta.name ?? name}:ital,wght@${variants.map(([i, w]) => `${i},${w}`).join(";")}`;
	const css = await get(
		`${CSS}?family=${encodeURIComponent(spec).replace(/%20/g, "+")}`,
	);
	if (!css) return null;
	const files = {};
	let prefix = null;
	for (const block of css.split("@font-face").slice(1)) {
		const style = block.match(/font-style:\s*(\w+)/)?.[1];
		const weight = block.match(/font-weight:\s*(\d+)/)?.[1];
		const url = block.match(/url\((https:[^)]+\.ttf)\)/)?.[1];
		if (!style || !weight || !url?.startsWith(GSTATIC)) continue;
		const rest = url.slice(GSTATIC.length); // "<slug>/v20/<id>.ttf"
		const cut = rest.indexOf("/", rest.indexOf("/") + 1) + 1;
		prefix ??= rest.slice(0, cut);
		files[`${weight}${style === "italic" ? "i" : ""}`] = rest.startsWith(prefix)
			? rest.slice(cut, -4)
			: rest.slice(0, -4);
	}
	if (!Object.keys(files).length) return null;
	return {
		n: meta.name ?? name,
		c: CATEGORIES[meta.category[0]] ?? "display",
		d: meta.designer ?? "",
		l: meta.license,
		p: path,
		s: meta.subsets,
		u: prefix,
		f: files,
	};
}

async function pool(items, size, fn) {
	const results = new Array(items.length);
	let next = 0;
	let done = 0;
	await Promise.all(
		Array.from({ length: size }, async () => {
			while (next < items.length) {
				const i = next++;
				try {
					results[i] = await fn(items[i]);
				} catch (e) {
					console.error(`skip ${items[i]}: ${e.message}`);
				}
				if (++done % 100 === 0) console.error(`${done}/${items.length}`);
			}
		}),
	);
	return results;
}

const names = parseCsvNames(await get(`${RAW}/tags/all/families.csv`)).slice(
	0,
	limit,
);
const families = (await pool(names, 16, family)).filter(Boolean);
const catalog = {
	source: "Google Fonts",
	generated: new Date().toISOString().slice(0, 10),
	licenseBase: `${RAW}/`,
	licenseFiles: LICENSE_FILES,
	fileBase: GSTATIC,
	families,
};
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(catalog)}\n`);
console.error(`${families.length} of ${names.length} families -> ${out}`);
