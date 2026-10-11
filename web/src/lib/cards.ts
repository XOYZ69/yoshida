// How cards are labelled in lists: a name taken from the card's values,
// so rows read as "Blue-Eyes White Dragon" rather than "002".

import type { CardInfo, Param } from "./engine";

const nameParams = [
	"title",
	"name",
	"card_name",
	"cardname",
	"label",
	"heading",
];
const looksLikeFile = (s: string) =>
	/\.(png|jpe?g|webp|gif|bmp)$/i.test(s) || /^https?:\/\//i.test(s);
const looksLikeColor = (s: string) => /^#[0-9a-f]{6}/i.test(s);

/** The param whose value names a card: title or name if there is one, else the first text param. */
export function nameParam(params: Param[]): string | null {
	for (const n of nameParams)
		if (
			params.some(
				(p) => p.name === n && (p.type === "text" || p.type === "enum"),
			)
		)
			return n;
	return params.find((p) => p.type === "text")?.name ?? null;
}

function text(v: unknown): string {
	if (typeof v === "string")
		return looksLikeFile(v) || looksLikeColor(v)
			? ""
			: v.replace(/\s+/g, " ").trim();
	if (typeof v === "number" || typeof v === "boolean") return String(v);
	return "";
}

/** A card's name (empty when it has none) and a short detail line from its other values. */
export function cardLabel(
	c: CardInfo,
	params: Param[],
	name = nameParam(params),
): { name: string; detail: string } {
	const own = name ? text(c.values[name]) : "";
	const def = name ? text(params.find((p) => p.name === name)?.default) : "";
	const parts: string[] = [];
	for (const p of params) {
		if (
			p.name === name ||
			p.type === "image" ||
			p.type === "list" ||
			p.type === "color"
		)
			continue;
		const t = text(c.values[p.name]);
		if (t) parts.push(t.length > 40 ? `${t.slice(0, 40)}…` : t);
		if (parts.length >= 3) break;
	}
	return { name: own || def, detail: parts.join(" · ") };
}
