// What kind of file a project path is: the colored icon in the Files tab and
// the short description in the selected file block.

import { fontFormat, readFont } from "./fonts/sfnt.ts";

export type FileType =
	| "design"
	| "cards"
	| "json"
	| "font"
	| "markdown"
	| "pdf"
	| "text"
	| "image"
	| "file";

const types: [RegExp, FileType][] = [
	[/\.design\.json$/i, "design"],
	[/\.cards\.(json|csv)$/i, "cards"],
	[/\.json$/i, "json"],
	[/\.(ttf|otf|ttc|woff2?)$/i, "font"],
	[/\.(md|markdown)$/i, "markdown"],
	[/\.pdf$/i, "pdf"],
	[/\.txt$/i, "text"],
	[/\.(png|jpe?g|gif|bmp|webp|svg)$/i, "image"],
];

export function fileType(path: string): FileType {
	return types.find(([re]) => re.test(path))?.[1] ?? "file";
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

const textOf = (data: Uint8Array) => new TextDecoder().decode(data);

function jsonOf(data: Uint8Array) {
	try {
		return JSON.parse(textOf(data));
	} catch {
		return undefined;
	}
}

/** Number of cards in a card file, or -1 when it cannot be read. */
function cardCount(path: string, data: Uint8Array): number {
	if (/\.csv$/i.test(path))
		// A header row, then one row per card; blank lines do not count.
		return Math.max(
			0,
			textOf(data)
				.split(/\r?\n/)
				.filter((l) => l.trim()).length - 1,
		);
	const v = jsonOf(data);
	const cards = Array.isArray(v) ? v : v?.cards;
	return Array.isArray(cards) ? cards.length : -1;
}

/**
 * A short description of what a file is, such as "Design: Number cards",
 * "Card data, 40 cards" or "Font: Cinzel Decorative Bold". Images are described by
 * their pixel size elsewhere, once decoded.
 */
export function describeFile(path: string, data: Uint8Array): string {
	const name = path.slice(path.lastIndexOf("/") + 1);
	switch (fileType(path)) {
		case "design": {
			const title = jsonOf(data)?.name;
			return typeof title === "string" && title ? `Design: ${title}` : "Design";
		}
		case "cards": {
			const n = cardCount(path, data);
			return n < 0 ? "Card data" : `Card data, ${plural(n, "card")}`;
		}
		case "json":
			return path === "yoshida.json" ? "Project manifest" : "JSON";
		case "font": {
			const f = readFont(data);
			const label = [f.family, f.style].filter(Boolean).join(" ");
			if (label) return `Font: ${label}`;
			const format = fontFormat(data);
			return format === "unknown" ? "Font" : `Font (${format.toUpperCase()})`;
		}
		case "markdown":
			return "Markdown";
		case "pdf":
			return "PDF";
		case "text":
			return /licen[cs]e|ofl/i.test(name) ? "License text" : "Text";
		case "image":
			return /\.svg$/i.test(path) ? "SVG image" : "Image";
		default: {
			const ext = /\.([a-z0-9]+)$/i.exec(name)?.[1];
			return ext ? `${ext.toUpperCase()} file` : "File";
		}
	}
}
