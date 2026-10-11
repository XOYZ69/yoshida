// Project files in the browser: loading examples and folders, saving, card
// data edits written back into JSON or CSV, and the formatter.

import { unzipSync, type Zippable, zipSync } from "fflate";

export type Files = Map<string, Uint8Array>;

const enc = new TextEncoder();
const dec = new TextDecoder();

export const textOf = (b: Uint8Array) => dec.decode(b);
export const bytesOf = (s: string) => enc.encode(s);

export function isText(path: string) {
	return /\.(json|csv|md|txt)$/i.test(path);
}

export function isImage(path: string) {
	return /\.(png|jpe?g|gif|bmp|webp)$/i.test(path);
}

const skipDirs = new Set([".git", ".yoshida", "node_modules", "out"]);

export type Example = { name: string; title: string; files: string[] };

export async function listExamples(): Promise<Example[]> {
	try {
		const res = await fetch("examples/index.json");
		return res.ok ? await res.json() : [];
	} catch {
		return [];
	}
}

export async function loadExample(ex: Example): Promise<Files> {
	const files: Files = new Map();
	await Promise.all(
		ex.files.map(async (f) => {
			const res = await fetch(
				`examples/${ex.name}/${f.split("/").map(encodeURIComponent).join("/")}`,
			);
			if (res.ok) files.set(f, new Uint8Array(await res.arrayBuffer()));
		}),
	);
	return files;
}

/** From an <input type="file" webkitdirectory> selection. */
export async function filesFromInput(
	list: FileList | File[],
): Promise<{ name: string; files: Files }> {
	const files: Files = new Map();
	let name = "project";
	for (const f of Array.from(list)) {
		const parts = (f.webkitRelativePath || f.name).split("/");
		if (parts.length > 1) name = parts[0];
		const rel = parts.length > 1 ? parts.slice(1) : parts;
		if (rel.some((p) => skipDirs.has(p))) continue;
		files.set(rel.join("/"), new Uint8Array(await f.arrayBuffer()));
	}
	return { name, files };
}

// File System Access API (Chromium): open a folder read/write.
type DirHandle = FileSystemDirectoryHandle;

type PickerWindow = Window & {
	showDirectoryPicker?: (options: {
		mode: "readwrite";
	}) => Promise<FileSystemDirectoryHandle>;
};

export function canOpenWritable() {
	return typeof (window as PickerWindow).showDirectoryPicker === "function";
}

function showDirectoryPicker(): Promise<DirHandle> {
	const pick = (window as PickerWindow).showDirectoryPicker;
	if (!pick) throw new Error("This browser cannot open folders for writing.");
	return pick({ mode: "readwrite" });
}

export async function openWritable(): Promise<{
	name: string;
	files: Files;
	handle: DirHandle;
}> {
	const handle = await showDirectoryPicker();
	const files: Files = new Map();
	const walk = async (dir: DirHandle, prefix: string) => {
		for await (const [name, entry] of dir.entries()) {
			if (entry.kind === "directory") {
				if (!skipDirs.has(name))
					await walk(entry as DirHandle, `${prefix}${name}/`);
			} else {
				const file = await (entry as FileSystemFileHandle).getFile();
				files.set(prefix + name, new Uint8Array(await file.arrayBuffer()));
			}
		}
	};
	await walk(handle, "");
	return { name: handle.name, files, handle };
}

export async function writeFile(
	root: DirHandle,
	path: string,
	data: Uint8Array,
) {
	const parts = path.split("/");
	let dir = root;
	for (const p of parts.slice(0, -1))
		dir = await dir.getDirectoryHandle(p, { create: true });
	const fh = await dir.getFileHandle(parts[parts.length - 1], { create: true });
	const w = await fh.createWritable();
	await w.write(data as Uint8Array<ArrayBuffer>);
	await w.close();
}

/** Deletes a file in a folder opened with write access; a missing file is fine. */
export async function removeFile(root: DirHandle, path: string) {
	const parts = path.split("/");
	let dir = root;
	try {
		for (const p of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(p);
		await dir.removeEntry(parts[parts.length - 1]);
	} catch (e) {
		if ((e as Error).name !== "NotFoundError") throw e;
	}
}

export function download(
	name: string,
	data: Uint8Array | Blob,
	type = "application/octet-stream",
) {
	const blob =
		data instanceof Blob ? data : new Blob([data as BlobPart], { type });
	const a = document.createElement("a");
	a.href = URL.createObjectURL(blob);
	a.download = name;
	a.click();
	setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
}

// ---------------------------------------------------------------- formatter

/**
 * Canonical JSON layout (FORMAT.md, "Canonical formatting"): 2 spaces, LF,
 * trailing newline, and objects or arrays of scalars on one line when they
 * fit in 100 columns. Key order is kept as written.
 */
export function formatJson(value: unknown): string {
	return `${fmt(value, 0)}\n`;
}

function isScalar(v: unknown) {
	return v === null || typeof v !== "object";
}

function oneLine(v: unknown): string | null {
	if (isScalar(v)) return JSON.stringify(v);
	if (Array.isArray(v)) {
		if (!v.every((x) => isScalar(x) || (Array.isArray(x) && x.every(isScalar))))
			return null;
		return `[${v.map((x) => oneLine(x)).join(", ")}]`;
	}
	const entries = Object.entries(v as object);
	if (!entries.every(([, x]) => isScalar(x))) return null;
	if (entries.length === 0) return "{}";
	return `{ ${entries.map(([k, x]) => `${JSON.stringify(k)}: ${JSON.stringify(x)}`).join(", ")} }`;
}

function fmt(v: unknown, indent: number, keyLen = 0): string {
	if (isScalar(v)) return JSON.stringify(v);
	const line = oneLine(v);
	if (line !== null && indent * 2 + keyLen + line.length <= 100) return line;
	const pad = "  ".repeat(indent + 1);
	const end = "  ".repeat(indent);
	if (Array.isArray(v)) {
		if (v.length === 0) return "[]";
		return `[\n${v.map((x) => pad + fmt(x, indent + 1)).join(",\n")}\n${end}]`;
	}
	const entries = Object.entries(v as object);
	if (entries.length === 0) return "{}";
	return `{\n${entries
		.map(([k, x]) => {
			const key = `${JSON.stringify(k)}: `;
			return pad + key + fmt(x, indent + 1, key.length);
		})
		.join(",\n")}\n${end}}`;
}

// ---------------------------------------------------------------- CSV

export function parseCsv(text: string): string[][] {
	const rows: string[][] = [];
	let row: string[] = [];
	let cell = "";
	let i = 0;
	let quoted = false;
	if (text.startsWith("﻿")) i = 1;
	for (; i < text.length; i++) {
		const ch = text[i];
		if (quoted) {
			if (ch === '"') {
				if (text[i + 1] === '"') {
					cell += '"';
					i++;
				} else quoted = false;
			} else cell += ch;
		} else if (ch === '"') quoted = true;
		else if (ch === ",") {
			row.push(cell);
			cell = "";
		} else if (ch === "\n" || ch === "\r") {
			if (ch === "\r" && text[i + 1] === "\n") i++;
			row.push(cell);
			cell = "";
			if (!(row.length === 1 && row[0] === "")) rows.push(row);
			row = [];
		} else cell += ch;
	}
	if (cell !== "" || row.length) {
		row.push(cell);
		rows.push(row);
	}
	return rows;
}

export function writeCsv(rows: string[][]): string {
	const q = (s: string) =>
		/[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
	return `${rows.map((r) => r.map(q).join(",")).join("\n")}\n`;
}

// ---------------------------------------------------------------- card edits

/**
 * Sets (or with `undefined`, clears) a param of card `index` in a card data
 * file and returns the new file text.
 */
export function setCardValue(
	path: string,
	text: string,
	index: number,
	param: string,
	value: unknown,
): string {
	if (path.endsWith(".csv")) {
		const rows = parseCsv(text);
		let col = rows[0].indexOf(param);
		if (col < 0) {
			if (value === undefined) return text;
			rows[0].push(param);
			for (const r of rows.slice(1)) r.push("");
			col = rows[0].length - 1;
		}
		const row = rows[index + 1];
		row[col] =
			value === undefined
				? ""
				: typeof value === "object"
					? JSON.stringify(value)
					: String(value);
		return writeCsv(rows);
	}
	const doc = JSON.parse(text);
	const card = doc.cards[index];
	if (value === undefined) delete card[param];
	else card[param] = value;
	return formatJson(doc);
}

// ---------------------------------------------------------------- card list edits

export type CardListOp =
	| { op: "add"; after: number }
	| { op: "duplicate"; index: number }
	| { op: "delete"; index: number }
	| { op: "move"; index: number; to: number }
	| { op: "rename"; index: number; id: string };

export const cardIdRe = /^[A-Za-z0-9._-]+$/;

function freeId(taken: Set<string>, base: string) {
	if (!taken.has(base)) return base;
	const stem = base.replace(/_copy\d*$/, "");
	for (let n = 1; ; n++) {
		const id = `${stem}_copy${n === 1 ? "" : n}`;
		if (!taken.has(id)) return id;
	}
}

function newCardId(taken: Set<string>) {
	for (let n = taken.size + 1; ; n++) {
		const id = String(n).padStart(3, "0");
		if (!taken.has(id)) return id;
	}
}

/**
 * Adds, copies, removes, moves or renames a card in a card data file.
 * `ids` are the cards' current ids (explicit or default). Returns the new
 * text and the index of the card to show afterwards.
 */
export function editCardList(
	path: string,
	text: string,
	op: CardListOp,
	ids: string[],
): { text: string; index: number } {
	const taken = new Set(ids);
	const csv = path.endsWith(".csv");
	let rows: string[][] = [];
	let cards: unknown[] = [];
	let doc: Record<string, unknown> = {};
	if (csv) {
		rows = parseCsv(text);
		if (!rows.length) rows = [["id"]];
		if (!rows[0].includes("id")) {
			rows[0].unshift("id");
			for (const r of rows.slice(1)) r.unshift("");
		}
	} else {
		doc = JSON.parse(text);
		if (!Array.isArray(doc.cards)) doc.cards = [];
		cards = doc.cards as unknown[];
	}
	const idCol = csv ? rows[0].indexOf("id") : -1;
	const count = csv ? rows.length - 1 : cards.length;
	let index = 0;

	switch (op.op) {
		case "add": {
			const id = newCardId(taken);
			index = Math.min(op.after + 1, count);
			if (csv) {
				const row = rows[0].map(() => "");
				row[idCol] = id;
				rows.splice(index + 1, 0, row);
			} else cards.splice(index, 0, { id });
			break;
		}
		case "duplicate": {
			const id = freeId(taken, ids[op.index] ?? "card");
			index = op.index + 1;
			if (csv) {
				const row = [...rows[op.index + 1]];
				row[idCol] = id;
				rows.splice(index + 1, 0, row);
			} else {
				const src = cards[op.index];
				const copy =
					src && typeof src === "object" ? JSON.parse(JSON.stringify(src)) : {};
				cards.splice(index, 0, {
					id,
					...Object.fromEntries(
						Object.entries(copy).filter(([k]) => k !== "id"),
					),
				});
			}
			break;
		}
		case "delete": {
			if (csv) rows.splice(op.index + 1, 1);
			else cards.splice(op.index, 1);
			index = Math.max(0, Math.min(op.index, count - 2));
			break;
		}
		case "move": {
			const to = Math.max(0, Math.min(op.to, count - 1));
			if (csv) rows.splice(to + 1, 0, ...rows.splice(op.index + 1, 1));
			else cards.splice(to, 0, ...cards.splice(op.index, 1));
			index = to;
			break;
		}
		case "rename": {
			index = op.index;
			if (csv) rows[op.index + 1][idCol] = op.id;
			else {
				const c = cards[op.index];
				const rest =
					c && typeof c === "object"
						? Object.entries(c).filter(([k]) => k !== "id")
						: [];
				cards[op.index] = { id: op.id, ...Object.fromEntries(rest) };
			}
			break;
		}
	}
	return { text: csv ? writeCsv(rows) : formatJson(doc), index };
}

// ---------------------------------------------------------------- new projects

/** A small starting design: one background, a title and a param. */
export function blankDesign(name: string): string {
	return formatJson({
		format: 1,
		name,
		canvas: { width: 750, height: 1050, background: "#F4F1EA" },
		params: {
			title: { type: "text", default: "Card title", label: "Title" },
		},
		layers: [
			{
				id: "frame",
				type: "rect",
				box: { x: 24, y: 24, w: "100% - 48", h: "100% - 48" },
				radius: 24,
				stroke: { color: "#2B2B2B", width: 4 },
			},
			{
				id: "title",
				type: "text",
				at: { x: "50%", y: 120 },
				anchor: "center",
				text: "{title}",
				size: 56,
				color: "#2B2B2B",
				max_width: "100% - 120",
			},
		],
	});
}

export function blankCards(design: string, name: string): string {
	return formatJson({
		format: 1,
		design,
		name,
		cards: [{ id: "001", title: "First card" }],
	});
}

/** A file name stem from free text: lower case, a-z 0-9 and dashes. */
export function slug(s: string) {
	return (
		s
			.toLowerCase()
			.replace(/[^a-z0-9]+/g, "-")
			.replace(/^-+|-+$/g, "") || "untitled"
	);
}

/** Where an imported file goes in the project, by its type. */
export function importPath(name: string) {
	const base = name.split(/[\\/]/).pop() ?? name;
	if (isImage(base)) return `assets/images/${base}`;
	if (/\.(ttf|otf)$/i.test(base)) return `assets/fonts/${base}`;
	if (/\.design\.json$/i.test(base)) return `designs/${base}`;
	if (/\.cards\.(json|csv)$/i.test(base)) return `cards/${base}`;
	return base;
}

/** Asks for a folder to write to (File System Access API). */
export async function pickDirectory(): Promise<DirHandle> {
	return showDirectoryPicker();
}

// ---------------------------------------------------------------- project files

/** Extension of a project file: a zip container, like .docx. */
export const PROJECT_EXT = ".yoshida";
/** Media type of a project file. */
export const PROJECT_MIME = "application/vnd.yoshida+zip";
/** Matches the extension of a project file, or of a plain zip (older exports). */
export const projectFileRe = /\.(yoshida|zip)$/i;

/**
 * A whole project as a `.yoshida` file (a zip container): every file at its
 * project path inside one folder, images and fonts included, so renaming it
 * to .zip and unpacking gives a folder the CLI and the editor can open as is.
 */
export function projectZip(name: string, files: Files): Uint8Array {
	const out: Zippable = {};
	const root = slug(name);
	// Images are already compressed; storing them saves time.
	for (const [p, d] of files)
		out[`${root}/${p}`] = /\.(png|jpe?g|gif|webp)$/i.test(p)
			? [d, { level: 0 }]
			: d;
	return zipSync(out, { level: 6 });
}

/**
 * Files of a project file (`.yoshida`, or a plain zip from older exports).
 * A single top folder (as projectZip writes) is removed and becomes the name.
 */
export function filesFromZip(data: Uint8Array): {
	name: string | null;
	files: Files;
} {
	const all = unzipSync(data);
	const paths = Object.keys(all).filter(
		(p) =>
			!p.endsWith("/") &&
			!p.startsWith("__MACOSX/") &&
			!/(^|\/)\.DS_Store$/.test(p),
	);
	const first = paths[0]?.split("/")[0];
	const strip =
		first && paths.every((p) => p.startsWith(`${first}/`))
			? first.length + 1
			: 0;
	const files: Files = new Map();
	for (const p of paths) {
		const rel = p.slice(strip);
		if (rel.split("/").some((x) => skipDirs.has(x) || x === "..")) continue;
		files.set(rel, all[p]);
	}
	return { name: strip ? first : null, files };
}
