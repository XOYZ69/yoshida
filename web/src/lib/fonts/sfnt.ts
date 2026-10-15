// Reads the parts of a font file the Fonts window shows: its format, the
// family and style names, the copyright and license strings from the `name`
// table, and the embedding permissions (OS/2 fsType).

export type FontFormat = "ttf" | "otf" | "ttc" | "woff" | "woff2" | "unknown";

export type FontInfo = {
	format: FontFormat;
	family: string;
	style: string;
	fullName: string;
	weight: number;
	italic: boolean;
	copyright: string;
	designer: string;
	license: string;
	licenseUrl: string;
	/** OS/2 fsType: what the font's maker allows when it is embedded. */
	embedding: "installable" | "editable" | "preview" | "restricted";
	/** Has an `fvar` table: only its default instance is drawn. */
	variable: boolean;
};

const tag = (v: DataView, at: number) =>
	String.fromCharCode(
		v.getUint8(at),
		v.getUint8(at + 1),
		v.getUint8(at + 2),
		v.getUint8(at + 3),
	);

export function fontFormat(data: Uint8Array): FontFormat {
	if (data.length < 4) return "unknown";
	const v = new DataView(data.buffer, data.byteOffset, data.byteLength);
	const t = tag(v, 0);
	if (t === "wOFF") return "woff";
	if (t === "wOF2") return "woff2";
	if (t === "ttcf") return "ttc";
	if (t === "OTTO") return "otf";
	if (v.getUint32(0) === 0x00010000 || t === "true") return "ttf";
	return "unknown";
}

/** True for files the renderer can draw (TrueType, CFF OpenType, first face of a collection). */
export const drawable = (f: FontFormat) =>
	f === "ttf" || f === "otf" || f === "ttc";

function tables(v: DataView, offset: number) {
	const out = new Map<string, { at: number; len: number }>();
	const count = v.getUint16(offset + 4);
	for (let i = 0; i < count; i++) {
		const rec = offset + 12 + i * 16;
		if (rec + 16 > v.byteLength) break;
		out.set(tag(v, rec), {
			at: v.getUint32(rec + 8),
			len: v.getUint32(rec + 12),
		});
	}
	return out;
}

function utf16be(v: DataView, at: number, len: number) {
	let s = "";
	for (let i = 0; i + 1 < len; i += 2)
		s += String.fromCharCode(v.getUint16(at + i));
	return s;
}

function latin1(v: DataView, at: number, len: number) {
	let s = "";
	for (let i = 0; i < len; i++) s += String.fromCharCode(v.getUint8(at + i));
	return s;
}

/** name table: nameID -> best string (Windows English first, then Mac Roman). */
function names(v: DataView, t: { at: number; len: number }) {
	const out = new Map<number, { s: string; rank: number }>();
	const count = v.getUint16(t.at + 2);
	const strings = t.at + v.getUint16(t.at + 4);
	for (let i = 0; i < count; i++) {
		const r = t.at + 6 + i * 12;
		if (r + 12 > v.byteLength) break;
		const platform = v.getUint16(r);
		const lang = v.getUint16(r + 4);
		const id = v.getUint16(r + 6);
		const len = v.getUint16(r + 8);
		const at = strings + v.getUint16(r + 10);
		if (at + len > v.byteLength) continue;
		let rank = -1;
		let s = "";
		if (platform === 3 || platform === 0) {
			rank = platform === 3 && lang === 0x409 ? 3 : 2;
			s = utf16be(v, at, len);
		} else if (platform === 1 && lang === 0) {
			rank = 1;
			s = latin1(v, at, len);
		}
		if (rank > (out.get(id)?.rank ?? -1))
			out.set(id, { s: s.replace(/\0/g, "").trim(), rank });
	}
	return (id: number) => out.get(id)?.s ?? "";
}

export function readFont(data: Uint8Array): FontInfo {
	const format = fontFormat(data);
	const info: FontInfo = {
		format,
		family: "",
		style: "",
		fullName: "",
		weight: 400,
		italic: false,
		copyright: "",
		designer: "",
		license: "",
		licenseUrl: "",
		embedding: "installable",
		variable: false,
	};
	if (!drawable(format)) return info;
	try {
		const v = new DataView(data.buffer, data.byteOffset, data.byteLength);
		const offset = format === "ttc" ? v.getUint32(12) : 0;
		const t = tables(v, offset);
		const nameT = t.get("name");
		if (nameT) {
			const n = names(v, nameT);
			info.family = n(16) || n(1);
			info.style = n(17) || n(2);
			info.fullName = n(4);
			info.copyright = n(0);
			info.designer = n(9);
			info.license = n(13);
			info.licenseUrl = n(14);
		}
		const os2 = t.get("OS/2");
		if (os2 && os2.len >= 64) {
			info.weight = v.getUint16(os2.at + 4);
			const fsType = v.getUint16(os2.at + 8);
			info.embedding =
				fsType & 0x0002 && !(fsType & 0x000c)
					? "restricted"
					: fsType & 0x0004
						? "preview"
						: fsType & 0x0008
							? "editable"
							: "installable";
			info.italic = (v.getUint16(os2.at + 62) & 0x0001) !== 0;
		}
		info.variable = t.has("fvar");
	} catch {
		// A broken table leaves the defaults; the renderer reports the file itself.
	}
	return info;
}
