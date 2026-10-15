// The Google Fonts catalog (public/fonts/google-fonts.json, made by
// scripts/font-catalog.mjs), previews through the Google Fonts CSS API and
// downloads of the static .ttf files and their license texts.

export type Category =
	| "sans-serif"
	| "serif"
	| "display"
	| "handwriting"
	| "monospace";
export type LicenseId = "OFL" | "APACHE2" | "UFL";

/** One style of a family: "400", "700i"... */
export type Style = { key: string; weight: number; italic: boolean };

export type Family = {
	name: string;
	category: Category;
	designer: string;
	license: LicenseId;
	/** Folder in the google/fonts repository, e.g. "ofl/bebasneue". */
	dir: string;
	subsets: string[];
	styles: Style[];
	files: Record<string, string>;
};

type Raw = {
	licenseBase: string;
	licenseFiles: Record<LicenseId, string>;
	fileBase: string;
	families: {
		n: string;
		c: Category;
		d: string;
		l: LicenseId;
		p: string;
		s: string[];
		u: string;
		f: Record<string, string>;
	}[];
};

export const LICENSES: Record<
	LicenseId,
	{ name: string; short: string; url: string; summary: string }
> = {
	OFL: {
		name: "SIL Open Font License 1.1",
		short: "OFL",
		url: "https://openfontlicense.org",
		summary:
			"Free to use, embed and share, also in commercial work. The license must stay with the font, and the font file may not be sold on its own.",
	},
	APACHE2: {
		name: "Apache License 2.0",
		short: "Apache",
		url: "https://www.apache.org/licenses/LICENSE-2.0",
		summary:
			"Free to use, embed, change and share, also in commercial work. Keep the license and copyright notice with the font.",
	},
	UFL: {
		name: "Ubuntu Font Licence 1.0",
		short: "UFL",
		url: "https://ubuntu.com/legal/font-licence",
		summary:
			"Free to use, embed and share, also in commercial work. Changed versions must be renamed. The license must stay with the font.",
	},
};

export const CATEGORIES: Category[] = [
	"sans-serif",
	"serif",
	"display",
	"handwriting",
	"monospace",
];

const WEIGHTS: Record<number, string> = {
	100: "Thin",
	200: "ExtraLight",
	300: "Light",
	400: "Regular",
	500: "Medium",
	600: "SemiBold",
	700: "Bold",
	800: "ExtraBold",
	900: "Black",
};

export function styleName(s: Style) {
	const w = WEIGHTS[s.weight] ?? String(s.weight);
	if (!s.italic) return w;
	return s.weight === 400 ? "Italic" : `${w}Italic`;
}

/** Readable label: "Bold 700", "Italic 400". */
export function styleLabel(s: Style) {
	const w = WEIGHTS[s.weight] ?? "";
	return `${s.italic ? (s.weight === 400 ? "Italic" : `${w} Italic`) : w} ${s.weight}`.trim();
}

let raw: Promise<Raw> | null = null;
let list: Family[] | null = null;

export async function loadCatalog(
	url = "fonts/google-fonts.json",
): Promise<Family[]> {
	if (list) return list;
	raw ??= fetch(url).then((r) => {
		if (!r.ok) throw new Error(`Font catalog not found (${r.status})`);
		return r.json();
	});
	const data = await raw.catch((e) => {
		raw = null;
		throw e;
	});
	base = data;
	list = data.families.map((f) => ({
		name: f.n,
		category: f.c,
		designer: f.d,
		license: f.l,
		dir: f.p,
		subsets: f.s,
		files: Object.fromEntries(
			Object.entries(f.f).map(([k, id]) => [
				k,
				id.includes("/") ? id : `${f.u}${id}`,
			]),
		),
		styles: Object.keys(f.f)
			.map((key) => ({
				key,
				weight: Number.parseInt(key, 10),
				italic: key.endsWith("i"),
			}))
			.sort(
				(a, b) => Number(a.italic) - Number(b.italic) || a.weight - b.weight,
			),
	}));
	return list;
}

let base: Raw | null = null;

/** Search by name or designer, filtered by category; name-prefix matches first. */
export function search(
	families: Family[],
	query: string,
	category: Category | "" = "",
) {
	const q = query.trim().toLowerCase();
	const hits = families.filter(
		(f) =>
			(!category || f.category === category) &&
			(!q ||
				f.name.toLowerCase().includes(q) ||
				f.designer.toLowerCase().includes(q)),
	);
	if (!q) return hits;
	const rank = (f: Family) =>
		f.name.toLowerCase().startsWith(q)
			? 0
			: f.name.toLowerCase().includes(q)
				? 1
				: 2;
	return hits.sort((a, b) => rank(a) - rank(b));
}

/** The style shown in lists: Regular when there is one, else the first. */
export function mainStyle(f: Family) {
	return f.styles.find((s) => s.key === "400") ?? f.styles[0];
}

// ---------------------------------------------------------------- previews

const loaded = new Map<string, Promise<string | null>>();

/**
 * Loads a preview of `family` that covers only the characters of `text`
 * (the CSS API's `text=` option keeps it to a few kilobytes) and returns
 * the CSS font-family to use, or null when it could not be loaded.
 */
export function previewFamily(
	f: Family,
	style: Style,
	text: string,
): Promise<string | null> {
	const chars = [...new Set(text || f.name)].sort().join("");
	const id = `yfp-${f.name}-${style.key}-${chars}`;
	let p = loaded.get(id);
	if (!p) {
		const spec = `${f.name}:ital,wght@${style.italic ? 1 : 0},${style.weight}`;
		const url = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(spec).replace(/%20/g, "+")}&text=${encodeURIComponent(chars)}`;
		const name = `yfp-${loaded.size}`;
		p = fetch(url)
			.then((r) =>
				r.ok ? r.text() : Promise.reject(new Error(String(r.status))),
			)
			.then(async (css) => {
				const src = css.match(/src:\s*(url\([^)]+\)\s*format\('[^']+'\))/)?.[1];
				if (!src) return null;
				const face = new FontFace(name, src, {
					weight: String(style.weight),
					style: style.italic ? "italic" : "normal",
				});
				document.fonts.add(await face.load());
				return name;
			})
			.catch(() => {
				loaded.delete(id);
				return null;
			});
		loaded.set(id, p);
	}
	return p;
}

// ---------------------------------------------------------------- import

export function fileUrl(f: Family, s: Style) {
	if (!base) throw new Error("Font catalog is not loaded");
	return `${base.fileBase}${f.files[s.key]}.ttf`;
}

/** File stem used in the project: "PlayfairDisplay-BoldItalic". */
export function fileStem(f: Family, s: Style) {
	return `${f.name.replace(/[^A-Za-z0-9]/g, "")}-${styleName(s)}`;
}

/** Font name declared in the design: "playfair_display", "playfair_display_bold". */
export function fontName(f: Family, s: Style) {
	const fam = f.name
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "_")
		.replace(/^_+|_+$/g, "");
	const head = /^[a-z_]/.test(fam) ? fam : `f_${fam}`;
	if (s.key === "400") return head;
	return `${head}_${styleName(s).toLowerCase().replace("italic", "_italic").replace(/^_/, "")}`;
}

export async function downloadStyle(f: Family, s: Style): Promise<Uint8Array> {
	const r = await fetch(fileUrl(f, s));
	if (!r.ok)
		throw new Error(
			`${f.name} ${styleLabel(s)}: download failed (${r.status})`,
		);
	return new Uint8Array(await r.arrayBuffer());
}

/** The family's license text from the google/fonts repository. */
export async function downloadLicense(f: Family): Promise<string> {
	if (!base) throw new Error("Font catalog is not loaded");
	const r = await fetch(
		`${base.licenseBase}${f.dir}/${base.licenseFiles[f.license]}`,
	);
	if (!r.ok) throw new Error(`${f.name}: license text not found (${r.status})`);
	return await r.text();
}
