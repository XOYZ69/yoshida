// Hex colour literals as the Zig core reads them (value.zig Color.parseHex):
// #RGB and #RGBA expand each digit (#F80 is #FF8800), #RRGGBB and #RRGGBBAA
// are as written, and the 16-bit #RRRRGGGGBBBB forms are read too.

/** Any hex colour the core accepts, with or without the `#`-free forms out of scope. */
export const HEX_COLOR =
	/^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8}|[0-9a-f]{12}|[0-9a-f]{16})$/i;

/** A hex colour CSS can draw as it is: #RGB, #RGBA, #RRGGBB or #RRGGBBAA. */
export const CSS_HEX_COLOR = /^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i;

/** #RGB or #RGBA to #RRGGBB or #RRGGBBAA by repeating each digit; other text is returned unchanged. */
export function expandHex(s: string): string {
	const t = s.trim();
	const m = /^#([0-9a-f]{3,4})$/i.exec(t);
	if (!m) return t;
	return `#${[...m[1]].map((d) => d + d).join("")}`;
}
