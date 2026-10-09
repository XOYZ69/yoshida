// What the yoshida expression language offers (FORMAT.md section 6): the
// functions with signatures and docs, built-in names, the fields of each
// layer kind that `@id.<field>` can read, units and operators. Used by the
// expression input for completion, signature help, the reference popover
// and highlighting.

/** The type a field needs; used to rank suggestions. */
export type Expect =
	| "number"
	| "color"
	| "bool"
	| "text"
	| "list"
	| "image"
	| "any";

export type FnArg = {
	name: string;
	type: string;
	optional?: string;
	rest?: boolean;
};
export type FnDoc = {
	name: string;
	args: FnArg[];
	ret: string;
	doc: string;
	example: string;
};

const n = (name: string): FnArg => ({ name, type: "number" });

export const FUNCTIONS: FnDoc[] = [
	{
		name: "min",
		args: [n("a"), n("b"), { name: "…", type: "number", rest: true }],
		ret: "number",
		doc: "The smallest of the arguments.",
		example: "min(@title.bounds.w, 300)",
	},
	{
		name: "max",
		args: [n("a"), n("b"), { name: "…", type: "number", rest: true }],
		ret: "number",
		doc: "The largest of the arguments.",
		example: "max(@title.bounds.bottom, 40) + 8",
	},
	{
		name: "clamp",
		args: [n("value"), n("lo"), n("hi")],
		ret: "number",
		doc: "Limits value to the range lo to hi.",
		example: "clamp(level * 10, 0, 100)",
	},
	{
		name: "abs",
		args: [n("n")],
		ret: "number",
		doc: "Absolute value (drops the minus sign).",
		example: "abs(-3)",
	},
	{
		name: "floor",
		args: [n("n")],
		ret: "number",
		doc: "Rounds down to a whole number.",
		example: "floor(i / 3)",
	},
	{
		name: "ceil",
		args: [n("n")],
		ret: "number",
		doc: "Rounds up to a whole number.",
		example: "ceil(len(items) / 2)",
	},
	{
		name: "round",
		args: [n("n"), { name: "digits", type: "number", optional: "0" }],
		ret: "number",
		doc: "Rounds to the nearest number with `digits` decimals (default 0).",
		example: "round(scale * 1.5, 1)",
	},
	{
		name: "len",
		args: [{ name: "value", type: "list or text" }],
		ret: "number",
		doc: "Number of items in a list, or characters in a text.",
		example: "len(ingredients)",
	},
	{
		name: "upper",
		args: [{ name: "s", type: "text" }],
		ret: "text",
		doc: "The text in UPPER CASE.",
		example: "upper(title)",
	},
	{
		name: "lower",
		args: [{ name: "s", type: "text" }],
		ret: "text",
		doc: "The text in lower case.",
		example: "lower(card_type)",
	},
	{
		name: "trim",
		args: [{ name: "s", type: "text" }],
		ret: "text",
		doc: "The text without spaces at the start and end.",
		example: "trim(title)",
	},
	{
		name: "fmt",
		args: [n("n"), n("decimals")],
		ret: "text",
		doc: "Formats a number with a fixed number of decimals.",
		example: "fmt(0.5, 2)  → '0.50'",
	},
	{
		name: "avg_color",
		args: [{ name: "img", type: "image" }],
		ret: "color",
		doc: "Average color of the opaque pixels of an image.",
		example: "avg_color(art)",
	},
	{
		name: "mix",
		args: [{ name: "a", type: "color" }, { name: "b", type: "color" }, n("t")],
		ret: "color",
		doc: "Blends two colors: t = 0 gives a, t = 1 gives b.",
		example: "mix(accent, #FFFFFF, 0.3)",
	},
	{
		name: "with_alpha",
		args: [{ name: "c", type: "color" }, n("a")],
		ret: "color",
		doc: "The color with its alpha set to a (0 to 1).",
		example: "with_alpha(accent, 0.5)",
	},
	{
		name: "rgb",
		args: [n("r"), n("g"), n("b")],
		ret: "color",
		doc: "A color from red, green, blue channels, each 0 to 255.",
		example: "rgb(255, 128, 0)",
	},
	{
		name: "rgba",
		args: [n("r"), n("g"), n("b"), n("a")],
		ret: "color",
		doc: "A color from channels 0 to 255 and alpha 0 to 1.",
		example: "rgba(0, 0, 0, 0.4)",
	},
];

export const FN_BY_NAME = new Map(FUNCTIONS.map((f) => [f.name, f]));

export function fnSignature(
	f: FnDoc,
	active = -1,
): { text: string; parts: { text: string; active: boolean }[] } {
	const parts: { text: string; active: boolean }[] = [
		{ text: f.name + "(", active: false },
	];
	const last = f.args.length - 1;
	const act = active < 0 ? -1 : Math.min(active, last);
	f.args.forEach((a, i) => {
		if (i) parts.push({ text: ", ", active: false });
		const t = a.rest
			? "…"
			: `${a.name}: ${a.type}${a.optional !== undefined ? ` = ${a.optional}` : ""}`;
		parts.push({ text: t, active: i === act });
	});
	parts.push({ text: `) → ${f.ret}`, active: false });
	return { text: parts.map((p) => p.text).join(""), parts };
}

export type FieldDoc = { name: string; type: string; doc: string };

export const BUILTINS: Record<string, { doc: string; fields: FieldDoc[] }> = {
	canvas: {
		doc: "The canvas (card) size in pixels.",
		fields: [
			{ name: "w", type: "number", doc: "Canvas width in pixels." },
			{ name: "h", type: "number", doc: "Canvas height in pixels." },
		],
	},
	card: {
		doc: "The card being rendered.",
		fields: [{ name: "id", type: "text", doc: "The card's id." }],
	},
	render: {
		doc: "Facts about the current render.",
		fields: [
			{
				name: "index",
				type: "number",
				doc: "Position of the card in its set, from 0.",
			},
			{ name: "date", type: "text", doc: "Render date, YYYY-MM-DD." },
		],
	},
};

const bounds: FieldDoc[] = [
	["left", "Left edge in pixels, after anchor and layout."],
	["top", "Top edge in pixels."],
	["right", "Right edge in pixels."],
	["bottom", "Bottom edge in pixels."],
	["w", "Final width in pixels."],
	["h", "Final height in pixels."],
	["cx", "Horizontal centre in pixels."],
	["cy", "Vertical centre in pixels."],
].map(([f, doc]) => ({ name: "bounds." + f, type: "number", doc }));

const common: FieldDoc[] = [
	...bounds,
	{ name: "opacity", type: "number", doc: "Opacity, 0 to 1." },
	{ name: "visible", type: "bool", doc: "Whether the layer is drawn." },
	{ name: "rotate", type: "number", doc: "Rotation in degrees, clockwise." },
];
const box: FieldDoc[] = [
	{ name: "box.x", type: "number", doc: "Anchor x in pixels." },
	{ name: "box.y", type: "number", doc: "Anchor y in pixels." },
	{ name: "box.w", type: "number", doc: "Width in pixels." },
	{ name: "box.h", type: "number", doc: "Height in pixels." },
];
const paint: FieldDoc[] = [
	{ name: "fill", type: "color", doc: "Fill color." },
	{ name: "stroke.color", type: "color", doc: "Outline color." },
	{ name: "stroke.width", type: "number", doc: "Outline width in pixels." },
];

export const LAYER_FIELDS: Record<string, FieldDoc[]> = {
	rect: [
		...common,
		...box,
		...paint,
		{ name: "radius", type: "number", doc: "Corner radius in pixels." },
	],
	ellipse: [...common, ...box, ...paint],
	polygon: [...common, ...paint],
	text: [
		...common,
		{ name: "at.x", type: "number", doc: "Anchor x in pixels." },
		{ name: "at.y", type: "number", doc: "Anchor y in pixels." },
		{ name: "text", type: "text", doc: "The text content." },
		{
			name: "size",
			type: "number",
			doc: "Font size actually used (after auto-shrink).",
		},
		{ name: "color", type: "color", doc: "Text color." },
		{ name: "wrap", type: "number", doc: "Wrap width in pixels." },
		{
			name: "line_spacing",
			type: "number",
			doc: "Extra pixels between lines.",
		},
		{ name: "max_lines", type: "number", doc: "Most lines shown." },
	],
	image: [
		...common,
		...box,
		{ name: "src", type: "text", doc: "Image path or URL." },
	],
	group: common,
};

export function layerFields(type: string): FieldDoc[] {
	return LAYER_FIELDS[type] ?? common;
}

export const KEYWORDS: FieldDoc[] = [
	{ name: "and", type: "bool", doc: "Both sides true (short-circuit)." },
	{ name: "or", type: "bool", doc: "Either side true (short-circuit)." },
	{ name: "not", type: "bool", doc: "Negates a bool." },
	{ name: "true", type: "bool", doc: "Boolean true." },
	{ name: "false", type: "bool", doc: "Boolean false." },
];

export const CHEATSHEET: { title: string; rows: [string, string][] }[] = [
	{
		title: "Units",
		rows: [
			[
				"50%",
				"percent of the canvas along the field’s axis (x/w or y/h fields)",
			],
			["10vw", "percent of the canvas width"],
			["10vh", "percent of the canvas height"],
		],
	},
	{
		title: "Literals",
		rows: [
			["'text'", "text in single (or double) quotes"],
			["#RRGGBB", "color, also #RRGGBBAA"],
			["true false", "bools"],
		],
	},
	{
		title: "Operators",
		rows: [
			["+ - * / %", "arithmetic on numbers (a % b needs spaces)"],
			["< <= > >= == !=", "comparisons, give a bool"],
			["and or not", "logic on bools"],
			["c ? a : b", "a if c is true, else b"],
			["list[n]  item.f", "index from 0, item field"],
		],
	},
];

export const TEMPLATE_HELP: [string, string][] = [
	["Hello {name}", "literal text with {expression} holes"],
	["{{ }}", "literal braces"],
];

/** Param types as the expression language sees them. */
export function valueType(paramType: string): string {
	if (paramType === "integer") return "number";
	if (paramType === "enum") return "text";
	return paramType;
}

/**
 * How well a value of `type` fits a field that needs `expect`: 2 exact, 1
 * usable (e.g. a number shown in a text template), 0 wrong type.
 */
export function fit(type: string, expect: Expect | undefined): number {
	if (!expect || expect === "any") return 1;
	const t = valueType(type);
	if (t === expect) return 2;
	if (t === "any") return 1;
	if (
		expect === "text" &&
		(t === "number" || t === "bool" || t === "color" || t === "image")
	)
		return 1;
	if (expect === "image" && t === "text") return 1;
	if (
		t === "list or text" &&
		(expect === "number" || expect === "list" || expect === "text")
	)
		return 1;
	return 0;
}

export function typeLabel(type: string, item?: Record<string, string>): string {
	if (type === "list" && item && Object.keys(item).length)
		return `list of {${Object.keys(item).join(", ")}}`;
	return type;
}

/** The field a list is looked up by (`list.Key`): its first text field (FORMAT.md 6.3.1). */
export function keyField(
	item: Record<string, string> | undefined,
): string | undefined {
	return Object.entries(item ?? {}).find(([, t]) => t === "text")?.[0];
}

/** What `list.Key` gives: the other field's type for a key and value item, else the item. */
export function lookupType(item: Record<string, string>): {
	type: string;
	field?: string;
} {
	const key = keyField(item);
	const rest = Object.entries(item).filter(([k]) => k !== key);
	return Object.keys(item).length === 2 && rest.length === 1
		? { type: rest[0][1], field: rest[0][0] }
		: { type: "item" };
}

/** Key values found in list values (card values, the default), in first-seen order. */
export function listKeys(
	item: Record<string, string> | undefined,
	values: unknown[],
): string[] {
	const key = keyField(item);
	const seen = new Set<string>();
	if (!key) return [];
	for (const v of values) {
		if (!Array.isArray(v)) continue;
		for (const it of v) {
			const k =
				it && typeof it === "object"
					? (it as Record<string, unknown>)[key]
					: undefined;
			if (typeof k === "string" && k) seen.add(k);
		}
	}
	return [...seen];
}
