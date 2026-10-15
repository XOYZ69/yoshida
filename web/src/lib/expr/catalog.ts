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
	/** Another accepted form of the call with different arguments, shown as a second signature line. */
	alt?: FnArg[];
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
		doc: "The smallest of the arguments, or of a list's number field: min(list, 'field') (an empty list is an error).",
		example: "min(@title.bounds.w, 300)",
	},
	{
		name: "max",
		args: [n("a"), n("b"), { name: "…", type: "number", rest: true }],
		ret: "number",
		doc: "The largest of the arguments, or of a list's number field: max(list, 'field') (an empty list is an error).",
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
		name: "sign",
		args: [n("n")],
		ret: "number",
		doc: "-1, 0 or 1 for the sign of n.",
		example: "sign(offset_x) * 4",
	},
	{
		name: "sqrt",
		args: [n("n")],
		ret: "number",
		doc: "Square root of n; n must not be negative.",
		example: "sqrt(area)",
	},
	{
		name: "pow",
		args: [n("base"), n("exp")],
		ret: "number",
		doc: "base raised to the power exp.",
		example: "pow(1.2, i)",
	},
	{
		name: "lerp",
		args: [n("a"), n("b"), n("t")],
		ret: "number",
		doc: "Goes from a to b by t: t = 0 gives a, t = 1 gives b. t is not clamped.",
		example: "lerp(20, 180, i / 9)",
	},
	{
		name: "remap",
		args: [
			n("value"),
			n("from_lo"),
			n("from_hi"),
			n("to_lo"),
			n("to_hi"),
		],
		ret: "number",
		doc: "Maps value from the range from_lo to from_hi onto to_lo to to_hi. Not clamped.",
		example: "remap(level, 0, 100, 0, 360)",
	},
	{
		name: "wrap",
		args: [n("value"), n("n")],
		ret: "number",
		doc: "Wraps value into the range 0 up to n (n itself is not reached), for angles and cycles.",
		example: "wrap(i * 47, 360)",
	},
	{
		name: "sin",
		args: [n("deg")],
		ret: "number",
		doc: "Sine of an angle in degrees.",
		example: "sin(i * 30) * radius",
	},
	{
		name: "cos",
		args: [n("deg")],
		ret: "number",
		doc: "Cosine of an angle in degrees.",
		example: "cx + cos(angle) * radius",
	},
	{
		name: "tan",
		args: [n("deg")],
		ret: "number",
		doc: "Tangent of an angle in degrees. An error at 90, 270 and every 180 more.",
		example: "tan(slope) * run",
	},
	{
		name: "asin",
		args: [n("x")],
		ret: "number",
		doc: "The angle in degrees whose sine is x (x from -1 to 1).",
		example: "asin(ratio)",
	},
	{
		name: "acos",
		args: [n("x")],
		ret: "number",
		doc: "The angle in degrees whose cosine is x (x from -1 to 1).",
		example: "acos(dot)",
	},
	{
		name: "atan2",
		args: [n("y"), n("x")],
		ret: "number",
		doc: "The angle in degrees from the x axis to the point (x, y), from -180 to 180.",
		example: "atan2(dy, dx)",
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
		name: "contains",
		args: [
			{ name: "text", type: "text" },
			{ name: "part", type: "text" },
		],
		ret: "bool",
		doc: "True if text contains part. An empty part is always found.",
		example: "contains(title, 'Dragon')",
	},
	{
		name: "starts_with",
		args: [
			{ name: "text", type: "text" },
			{ name: "prefix", type: "text" },
		],
		ret: "bool",
		doc: "True if text starts with prefix.",
		example: "starts_with(card.id, 'A')",
	},
	{
		name: "ends_with",
		args: [
			{ name: "text", type: "text" },
			{ name: "suffix", type: "text" },
		],
		ret: "bool",
		doc: "True if text ends with suffix.",
		example: "ends_with(file, '.png')",
	},
	{
		name: "replace",
		args: [
			{ name: "text", type: "text" },
			{ name: "old", type: "text" },
			{ name: "new", type: "text" },
		],
		ret: "text",
		doc: "Replaces every old in text with new.",
		example: "replace(title, ' ', '-')",
	},
	{
		name: "slice",
		args: [
			{ name: "text", type: "text" },
			n("start"),
			{ name: "end", type: "number", optional: "the end" },
		],
		ret: "text",
		doc: "The characters from start up to end (counted from 0; a negative count is from the end).",
		example: "slice(title, 0, 3)",
	},
	{
		name: "pad_start",
		args: [
			{ name: "text", type: "text" },
			n("width"),
			{ name: "fill", type: "text", optional: "' '" },
		],
		ret: "text",
		doc: "Pads text on the left with fill up to width characters.",
		example: "pad_start(card.id, 3, '0')",
	},
	{
		name: "repeat",
		args: [
			{ name: "text", type: "text" },
			n("n"),
		],
		ret: "text",
		doc: "text written n times (none when n is 0 or less).",
		example: "repeat('★', rating)",
	},
	{
		name: "title_case",
		args: [{ name: "text", type: "text" }],
		ret: "text",
		doc: "Upper-cases the first letter of each word and leaves the rest as they are.",
		example: "title_case(name)",
	},
	{
		name: "roman",
		args: [n("n")],
		ret: "text",
		doc: "The number n in Roman numerals, from 1 to 3999.",
		example: "roman(render.index + 1)",
	},
	{
		name: "part",
		args: [
			{ name: "text", type: "text" },
			{ name: "sep", type: "text" },
			n("n"),
		],
		ret: "text",
		doc: "The n-th piece of text split on sep, counted from 0 (a negative n counts from the end); empty when there is none.",
		example: "part(card.id, '-', 0)",
	},
	{
		name: "len",
		args: [{ name: "value", type: "list or text" }],
		ret: "number",
		doc: "Number of items in a list, or characters in a text.",
		example: "len(ingredients)",
	},
	{
		name: "has",
		args: [
			{ name: "list", type: "list" },
			{ name: "key", type: "text" },
		],
		ret: "bool",
		doc: "True if the list has an item with this key.",
		example: "has(prices, tier)",
	},
	{
		name: "get",
		args: [
			{ name: "list", type: "list" },
			{ name: "key", type: "text" },
			{ name: "fallback", type: "any" },
		],
		alt: [
			{ name: "list", type: "list" },
			{ name: "key", type: "text" },
			{ name: "field", type: "text" },
			{ name: "fallback", type: "any" },
		],
		ret: "any",
		doc: "The value stored under key in a key and value list, else fallback. get(list, key, 'field', fallback) reads that field of the item with the key.",
		example: "get(prices, tier, 0)",
	},
	{
		name: "index_of",
		args: [
			{ name: "list", type: "list" },
			{ name: "key", type: "text" },
		],
		ret: "number",
		doc: "Position from 0 of the first item with this key, or -1 when there is none.",
		example: "index_of(levels, 'gold')",
	},
	{
		name: "sum",
		args: [
			{ name: "list", type: "list" },
			{ name: "field", type: "text", optional: "value field" },
		],
		ret: "number",
		doc: "The sum of a list of numbers, or of one number field of its items.",
		example: "sum(cards, 'cost')",
	},
	{
		name: "avg",
		args: [
			{ name: "list", type: "list" },
			{ name: "field", type: "text", optional: "value field" },
		],
		ret: "number",
		doc: "The average of a list of numbers, or of one number field of its items. An empty list is an error.",
		example: "avg(scores, 'points')",
	},
	{
		name: "count",
		args: [
			{ name: "list", type: "list" },
			{ name: "field", type: "text" },
			{ name: "value", type: "any" },
		],
		ret: "number",
		doc: "How many items have field equal to value.",
		example: "count(cards, 'type', 'monster')",
	},
	{
		name: "join",
		args: [
			{ name: "list", type: "list" },
			{ name: "sep", type: "text" },
		],
		alt: [
			{ name: "list", type: "list" },
			{ name: "field", type: "text" },
			{ name: "sep", type: "text" },
		],
		ret: "text",
		doc: "The items joined with sep. join(list, 'field', sep) joins one field of the items instead.",
		example: "join(tags, ', ')",
	},
	{
		name: "last",
		args: [{ name: "list", type: "list" }],
		ret: "any",
		doc: "The last item of a list. An empty list is an error.",
		example: "last(steps)",
	},
	{
		name: "year",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The year of a date or date-time.",
		example: "year(render.date)",
	},
	{
		name: "month",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The month, 1 to 12, of a date or date-time.",
		example: "month(release)",
	},
	{
		name: "day",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The day of the month of a date or date-time.",
		example: "day(render.date)",
	},
	{
		name: "weekday",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The day of the week of a date or date-time: 1 for Monday up to 7 for Sunday.",
		example: "weekday(render.date) >= 6",
	},
	{
		name: "hour",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The hour, 0 to 23, of a time or date-time.",
		example: "hour(start) < 12",
	},
	{
		name: "minute",
		args: [{ name: "t", type: "text" }],
		ret: "number",
		doc: "The minute, 0 to 59, of a time or date-time.",
		example: "minute(start)",
	},
	{
		name: "date_fmt",
		args: [
			{ name: "t", type: "text" },
			{ name: "pattern", type: "text" },
		],
		ret: "text",
		doc: "Formats a date, time or date-time with a pattern such as 'D MMM YYYY' or 'HH:mm'. Text in [brackets] is kept as it is.",
		example: "date_fmt(render.date, 'D MMM YYYY')",
	},
	{
		name: "add_days",
		args: [
			{ name: "t", type: "text" },
			n("n"),
		],
		ret: "text",
		doc: "The date or date-time n days later, in the same form.",
		example: "add_days(render.date, 7)",
	},
	{
		name: "add_hours",
		args: [
			{ name: "t", type: "text" },
			n("h"),
		],
		ret: "text",
		doc: "The date or date-time h hours later, as a date-time.",
		example: "add_hours(start, 1.5)",
	},
	{
		name: "days_between",
		args: [
			{ name: "a", type: "text" },
			{ name: "b", type: "text" },
		],
		ret: "number",
		doc: "Whole days from date a to date b; negative when b is earlier.",
		example: "days_between(render.date, due)",
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
	{
		name: "hsl",
		args: [n("h"), n("s"), n("l")],
		ret: "color",
		doc: "A color from hue in degrees, saturation and lightness, each 0 to 100 (hue wraps).",
		example: "hsl(i * 20, 70, 50)",
	},
	{
		name: "hsla",
		args: [n("h"), n("s"), n("l"), n("a")],
		ret: "color",
		doc: "A color from hue in degrees, saturation and lightness 0 to 100, and alpha 0 to 1.",
		example: "hsla(hue, 60, 40, 0.5)",
	},
	{
		name: "lighten",
		args: [{ name: "c", type: "color" }, n("n")],
		ret: "color",
		doc: "The color lighter by n lightness points (0 to 100).",
		example: "lighten(accent, 15)",
	},
	{
		name: "darken",
		args: [{ name: "c", type: "color" }, n("n")],
		ret: "color",
		doc: "The color darker by n lightness points (0 to 100).",
		example: "darken(accent, 20)",
	},
	{
		name: "luminance",
		args: [{ name: "c", type: "color" }],
		ret: "number",
		doc: "Relative brightness of a color, from 0 (black) to 1 (white). Alpha is ignored.",
		example: "luminance(c_panel) > 0.5",
	},
	{
		name: "readable",
		args: [
			{ name: "bg", type: "color" },
			{ name: "light", type: "color", optional: "#FFFFFF" },
			{ name: "dark", type: "color", optional: "#000000" },
		],
		ret: "color",
		doc: "Whichever of light and dark has the higher contrast against bg.",
		example: "readable(c_panel)",
	},
	{
		name: "rand",
		args: [
			{ name: "seed", type: "any" },
			{ name: "…", type: "any", rest: true },
		],
		ret: "number",
		doc: "A number from 0 up to 1 that is the same for the same seeds. Use card.id and i to vary it per card.",
		example: "rand(card.id, i)",
	},
	{
		name: "rand_int",
		args: [
			n("lo"),
			n("hi"),
			{ name: "seed", type: "any" },
			{ name: "…", type: "any", rest: true },
		],
		ret: "number",
		doc: "A whole number from lo to hi, both included; the same for the same seeds.",
		example: "rand_int(1, 6, card.id, i)",
	},
	{
		name: "pick",
		args: [
			{ name: "seed", type: "any" },
			{ name: "a", type: "any" },
			{ name: "b", type: "any" },
			{ name: "…", type: "any", rest: true },
		],
		ret: "any",
		doc: "One of the choices (two or more, all one type), picked by the seeds.",
		example: "pick(card.id, 'Fire', 'Water', 'Earth')",
	},
	{
		name: "match",
		args: [
			{ name: "value", type: "any" },
			{ name: "key", type: "any" },
			{ name: "result", type: "any" },
			{ name: "…", type: "any", rest: true },
		],
		ret: "any",
		doc: "The result of the first key equal to value, else the default (the last argument). Only the chosen result is evaluated.",
		example: "match(k, 'start', c_start, 'finish', c_finish, c_plain)",
	},
];

export const FN_BY_NAME = new Map(FUNCTIONS.map((f) => [f.name, f]));

export function fnSignature(
	f: FnDoc,
	active = -1,
	args: FnArg[] = f.args,
): { text: string; parts: { text: string; active: boolean }[] } {
	const parts: { text: string; active: boolean }[] = [
		{ text: `${f.name}(`, active: false },
	];
	const last = args.length - 1;
	const act = active < 0 ? -1 : Math.min(active, last);
	args.forEach((a, i) => {
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
			{ name: "time", type: "text", doc: "Render time, HH:MM:SS local time." },
			{
				name: "now",
				type: "text",
				doc: "Render date-time in UTC, YYYY-MM-DDTHH:MM:SSZ.",
			},
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
].map(([f, doc]) => ({ name: `bounds.${f}`, type: "number", doc }));

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
	{
		name: "in",
		type: "bool",
		doc: "True if the value equals one item of a bracket list, e.g. k in [0, 4].",
	},
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
			["v in [a, b]", "true if v equals one of the items"],
			["and or not", "logic on bools"],
			["c ? a : b", "a if c is true, else b (chains without brackets)"],
			["match(v, k, r, …, d)", "r for the first k equal to v, else d"],
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
