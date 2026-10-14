// Fonts that are already in the project: previews from their bytes, the
// license file next to them and what that license says.

import type { Files } from "../project";
import { drawable, type FontInfo, fontFormat, readFont } from "./sfnt.ts";

const textOf = (b: Uint8Array) => new TextDecoder().decode(b);

export const fontFileRe = /\.(ttf|otf|ttc)$/i;
/** Font files the renderer cannot read; refused on upload with the reason. */
export const webFontRe = /\.(woff2?|eot)$/i;

const stemOf = (path: string) => path.replace(/\.[^./]+$/, "");
const dirOf = (path: string) =>
	path.includes("/") ? path.slice(0, path.lastIndexOf("/") + 1) : "";

/** Where an imported or uploaded font's license file goes: next to it. */
export const licensePathFor = (fontPath: string) =>
	`${stemOf(fontPath)}-license.txt`;

/**
 * The license file for a font: `<stem>-license.txt` next to it, or a shared
 * OFL.txt / LICENSE.txt / UFL.txt (any case) in the same folder.
 */
export function findLicense(files: Files, fontPath: string): string | null {
	const own = licensePathFor(fontPath);
	if (files.has(own)) return own;
	const dir = dirOf(fontPath);
	const shared = /^(ofl|license|licence|ufl|copying)(\.(txt|md))?$/i;
	for (const p of files.keys()) {
		if (
			p.startsWith(dir) &&
			!p.slice(dir.length).includes("/") &&
			shared.test(p.slice(dir.length))
		)
			return p;
	}
	return null;
}

export type LicenseKind = "OFL" | "APACHE2" | "UFL" | "restricted" | "other";

/** A rough reading of a license text, to pick the badge and warning. */
export function licenseKind(text: string): LicenseKind {
	const t = text.toLowerCase();
	if (
		/may not (re)?distribute|not (be )?(re)?distribut|no redistribution|personal use only|non-commercial use only|for personal use/.test(
			t,
		)
	)
		return "restricted";
	if (t.includes("open font license")) return "OFL";
	if (t.includes("apache license")) return "APACHE2";
	if (t.includes("ubuntu font licen")) return "UFL";
	return "other";
}

export type ProjectFont = {
	path: string;
	info: FontInfo;
	license: { path: string; kind: LicenseKind; text: string } | null;
};

const infoCache = new WeakMap<Uint8Array, FontInfo>();

export function projectFont(files: Files, path: string): ProjectFont | null {
	const data = files.get(path);
	if (!data) return null;
	let info = infoCache.get(data);
	if (!info) {
		info = readFont(data);
		infoCache.set(data, info);
	}
	const lp = findLicense(files, path);
	const lt = lp ? textOf(files.get(lp) as Uint8Array) : "";
	return {
		path,
		info,
		license: lp ? { path: lp, kind: licenseKind(lt), text: lt } : null,
	};
}

/** A warning to show for a project font, or "" when there is nothing to say. */
export function fontWarning(f: ProjectFont): string {
	if (!drawable(f.info.format))
		return "This file is not a TrueType or OpenType font, so the default font is used.";
	if (f.license?.kind === "restricted")
		return "Its license limits sharing: check it before you share or publish this project with the font inside.";
	if (f.info.embedding === "restricted")
		return "The font says it may not be embedded (OS/2 fsType). Check its license before you share this project.";
	if (!f.license && !f.info.license)
		return "No license file found next to this font, so its terms are unknown. Add one before you share the project.";
	if (f.info.variable)
		return "A variable font: only its default style is drawn. Import the static styles you need instead.";
	return "";
}

// ---------------------------------------------------------------- previews

const faces = new WeakMap<Uint8Array, Promise<string | null>>();
let counter = 0;

/** Loads a project font into the page for previews; returns its CSS family name. */
export function previewFace(data: Uint8Array): Promise<string | null> {
	let p = faces.get(data);
	if (!p) {
		const name = `yfont-${++counter}`;
		const format = fontFormat(data);
		p = drawable(format)
			? new FontFace(name, data.slice().buffer as ArrayBuffer)
					.load()
					.then((face) => {
						document.fonts.add(face);
						return name;
					})
					.catch(() => null)
			: Promise.resolve(null);
		faces.set(data, p);
	}
	return p;
}

// ---------------------------------------------------------------- names

/**
 * Preview text for a text layer: its text with each `{...}` replaced by the
 * card value of the last name in it (`{upper(t.title)}` shows `title`).
 */
export function previewTextOf(
	text: string,
	values: Record<string, unknown> = {},
) {
	return text
		.replace(/\{([^{}]*)\}/g, (_, e: string) => {
			const names = e.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? [];
			for (let i = names.length - 1; i >= 0; i--) {
				const v = values[names[i]];
				if (typeof v === "string" || typeof v === "number") return String(v);
			}
			return "";
		})
		.replace(/\s+/g, " ")
		.trim()
		.slice(0, 40);
}

const identRe = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** A free ident for a font name, based on `want` ("inter", "inter_2"...). */
export function freeFontName(want: string, taken: Iterable<string>) {
	const used = new Set(taken);
	let base = want
		.toLowerCase()
		.replace(/[^a-z0-9_]+/g, "_")
		.replace(/^_+|_+$/g, "");
	if (!identRe.test(base)) base = `f_${base || "font"}`;
	if (!used.has(base)) return base;
	for (let i = 2; ; i++) if (!used.has(`${base}_${i}`)) return `${base}_${i}`;
}

/** Suggested font name for a file: from its family and style, else its file name. */
export function nameForFile(path: string, info: FontInfo) {
	const style =
		info.style && !/^regular$/i.test(info.style) ? `_${info.style}` : "";
	return (
		info.family
			? `${info.family}${style}`
			: (path.split("/").pop() ?? "font").replace(/\.[^.]+$/, "")
	).replace(/[-\s]+/g, "_");
}

/** Layers (by id) in a design that use font `name`, searched through groups. */
export function layersUsing(doc: unknown, name: string): string[] {
	const out: string[] = [];
	const walk = (layers: unknown) => {
		if (!Array.isArray(layers)) return;
		for (const l of layers) {
			if (!l || typeof l !== "object") continue;
			const o = l as Record<string, unknown>;
			if (
				o.font === name ||
				(name === "default" && o.type === "text" && o.font === undefined)
			)
				out.push(String(o.id ?? "?"));
			walk(o.layers);
		}
	};
	walk((doc as Record<string, unknown> | null)?.layers);
	return out;
}

/**
 * Renames font `from` to `to` in a design, in place (for use inside editDoc):
 * the entry keeps its place in `fonts`, and every layer (also in groups)
 * that uses it by name is updated.
 */
export function renameFont(
	doc: Record<string, unknown>,
	from: string,
	to: string,
) {
	const fonts = doc.fonts as Record<string, unknown> | undefined;
	if (fonts && typeof fonts === "object") {
		const entries = Object.entries(fonts).map(
			([n, p]) => [n === from ? to : n, p] as const,
		);
		for (const n of Object.keys(fonts)) delete fonts[n];
		for (const [n, p] of entries) fonts[n] = p;
	}
	const walk = (layers: unknown) => {
		if (!Array.isArray(layers)) return;
		for (const l of layers) {
			if (!l || typeof l !== "object") continue;
			const o = l as Record<string, unknown>;
			if (o.font === from) o.font = to;
			walk(o.layers);
		}
	};
	walk(doc.layers);
}

/**
 * Removes font `name` from a design, in place (for use inside editDoc):
 * layers that used it lose their `font`, so they draw with the default font.
 */
export function removeFont(doc: Record<string, unknown>, name: string) {
	const fonts = doc.fonts as Record<string, unknown> | undefined;
	if (fonts && typeof fonts === "object") delete fonts[name];
	const walk = (layers: unknown) => {
		if (!Array.isArray(layers)) return;
		for (const l of layers) {
			if (!l || typeof l !== "object") continue;
			const o = l as Record<string, unknown>;
			if (o.font === name) delete o.font;
			walk(o.layers);
		}
	};
	walk(doc.layers);
}
