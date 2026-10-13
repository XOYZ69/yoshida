// Quick actions: pure rewrites of an expression's syntax tree. Each returns
// the new expression text, formatted, or null when the rewrite does not
// apply. The extract actions also return the design with the new const or
// function. The expression core is passed in (parse and format), so this
// module runs under Node for the tests as well as in the editor.

import type { Node, Span } from "./core";

/** The parse and format functions of the expression core (core.ts). */
export type Core = {
	parse(src: string): { root?: Node | null; problems: unknown[] };
	format(src: string, width: number): string | null;
};

/** A design document as parsed JSON. */
export type Design = Record<string, unknown>;

/** An argument of an extracted function. */
export type Arg = { name: string; type: string };

export type Rewrite = { text: string; note?: string };
export type Extracted = { text: string; design: Design };

const WIDTH = 72;
/** Extracted bodies stay on one line: they are JSON strings in the design. */
const BODY_WIDTH = 1 << 16;
const NAME_RE = /^[a-z][a-z0-9_]*$/;

/** Words the expression language reserves. */
export const RESERVED = ["and", "or", "not", "in", "true", "false", "match"];

/** The functions of catalog.ts FUNCTIONS. tests/expr-rewrite.mjs checks the list. */
export const FUNCTION_NAMES = [
	"min",
	"max",
	"clamp",
	"abs",
	"floor",
	"ceil",
	"round",
	"len",
	"upper",
	"lower",
	"trim",
	"fmt",
	"avg_color",
	"mix",
	"with_alpha",
	"rgb",
	"rgba",
	"match",
];

/** The builtin objects of catalog.ts BUILTINS. */
export const BUILTIN_NAMES = ["canvas", "card", "render"];

const LITERALS = new Set(["number", "unit", "string", "boolean", "color"]);
const REPEATABLE = new Set([
	...LITERALS,
	"name",
	"field",
	"builtin",
	"layer_ref",
]);

/** Every direct child of a node, in source order. */
function children(n: Node): Node[] {
	const out: Node[] = [];
	for (const c of [n.obj, n.idx, n.x, n.l, n.r, n.c, n.a, n.b, n.value]) {
		if (c) out.push(c);
	}
	if (n.args) out.push(...n.args);
	if (n.items) out.push(...n.items);
	return out;
}

function walk(n: Node, f: (n: Node) => void): void {
	f(n);
	for (const c of children(n)) walk(c, f);
}

/** The source of a node, in parens so it stays one operand. The formatter drops the redundant ones. */
function wrap(text: string, n: Node): string {
	return `(${text.slice(n.span[0], n.span[1])})`;
}

/** Source without whitespace outside quoted strings, to compare subjects. */
function compact(src: string): string {
	return src.replace(/'[^']*'|\s+/g, (m) => (m.startsWith("'") ? m : ""));
}

/** A node without its parens. */
function unparen(n: Node): Node {
	let x = n;
	while (x.k === "paren" && x.x) x = x.x;
	return x;
}

function isObj(v: unknown): v is Record<string, unknown> {
	return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Replaces a span of the text and formats the result; null if it has problems. */
function splice(
	core: Core,
	text: string,
	span: Span,
	insert: string,
): string | null {
	return core.format(
		text.slice(0, span[0]) + insert + text.slice(span[1]),
		WIDTH,
	);
}

type Branch = { subject: Node; keys: Node[] };

/** Reads `s == k` or `s in [k1, k2]`. With no subject yet, the first condition sets it. */
function branchOf(
	text: string,
	c: Node,
	subject: string | null,
): Branch | null {
	if (c.k === "in_list") {
		if (!c.value || !c.items?.length) return null;
		if (subject !== null && compact(text.slice(...c.value.span)) !== subject)
			return null;
		return { subject: c.value, keys: c.items };
	}
	if (c.k !== "binary" || c.op !== "==" || !c.l || !c.r) return null;
	const { l, r } = c;
	if (subject === null) {
		// The subject is the side that is not a literal: `s == 'a'` and `'a' == s`
		// both work. Two literals: the left one, as written by `match` to `?:`.
		return LITERALS.has(l.k) && !LITERALS.has(r.k)
			? { subject: r, keys: [l] }
			: { subject: l, keys: [r] };
	}
	if (compact(text.slice(...l.span)) === subject)
		return { subject: l, keys: [r] };
	if (compact(text.slice(...r.span)) === subject)
		return { subject: r, keys: [l] };
	return null;
}

/**
 * `s == k1 ? r1 : s == k2 ? r2 : d` (or `s in [k1, k2]` conditions) to
 * `match(s, k1, r1, k2, r2, d)`. Every condition must test the same subject.
 */
export function condChainToMatch(
	core: Core,
	text: string,
	node: Node,
): Rewrite | null {
	if (node.k !== "cond") return null;
	const arms: { keys: Node[]; result: Node }[] = [];
	let subject: Node | null = null;
	let subjectSrc: string | null = null;
	let cur: Node | undefined = node;
	while (cur?.k === "cond") {
		if (!cur.c || !cur.a || !cur.b) return null;
		const b = branchOf(text, unparen(cur.c), subjectSrc);
		if (!b) return null;
		if (!subject) {
			subject = b.subject;
			subjectSrc = compact(text.slice(...b.subject.span));
		}
		arms.push({ keys: b.keys, result: cur.a });
		cur = unparen(cur.b);
	}
	if (!subject || arms.length < 2 || !cur) return null;

	const parts = [wrap(text, subject)];
	for (const arm of arms) {
		for (const k of arm.keys) parts.push(wrap(text, k), wrap(text, arm.result));
	}
	parts.push(wrap(text, cur));
	const out = splice(core, text, node.span, `(match(${parts.join(", ")}))`);
	return out === null ? null : { text: out };
}

/**
 * `match(s, k1, r1, ..., d)` to `s == k1 ? r1 : ... : d`. A subject that is
 * not a plain name, field, builtin or layer ref is repeated per condition,
 * so the result carries a note.
 */
export function matchToCondChain(
	core: Core,
	text: string,
	node: Node,
): Rewrite | null {
	if (node.k !== "call" || node.fn !== "match" || !node.args) return null;
	const args = node.args;
	if (args.length < 4 || args.length % 2 !== 0) return null;
	const [subject, ...rest] = args;
	if (!subject) return null;

	const subj = wrap(text, subject);
	let chain = "";
	for (let i = 0; i + 2 < rest.length; i += 2) {
		const key = rest[i];
		const result = rest[i + 1];
		if (!key || !result) return null;
		chain += `${subj} == ${wrap(text, key)} ? ${wrap(text, result)} : `;
	}
	const last = rest[rest.length - 1];
	if (!last) return null;
	chain += wrap(text, last);

	const out = splice(core, text, node.span, `(${chain})`);
	if (out === null) return null;
	return REPEATABLE.has(subject.k)
		? { text: out }
		: { text: out, note: "the subject is evaluated once per condition" };
}

/** True for nodes worth pulling into a const or a function (not literals, names or layer refs). */
export function canExtract(node: Node): boolean {
	return (
		!LITERALS.has(node.k) &&
		!["name", "paren", "err", "layer_ref"].includes(node.k)
	);
}

/** The names of `locals` used inside the node, in first-use order. */
export function freeNames(node: Node, locals: string[]): string[] {
	const found: Node[] = [];
	walk(node, (n) => {
		if (n.k === "name" && n.name && locals.includes(n.name)) found.push(n);
	});
	found.sort((a, b) => a.span[0] - b.span[0]);
	const out: string[] = [];
	for (const n of found) {
		const name = n.name ?? "";
		if (!out.includes(name)) out.push(name);
	}
	return out;
}

/** True when the node refers to a layer (`@layer`), which constants and functions cannot. */
export function hasLayerRef(node: Node): boolean {
	let found = false;
	walk(node, (n) => {
		if (n.k === "layer_ref") found = true;
	});
	return found;
}

/** A name a const or function may take: a plain identifier not used by the design or the language. */
function nameFree(name: string, locals: string[], design: Design): boolean {
	if (!NAME_RE.test(name)) return false;
	if (RESERVED.includes(name) || FUNCTION_NAMES.includes(name)) return false;
	if (BUILTIN_NAMES.includes(name) || locals.includes(name)) return false;
	for (const section of ["params", "consts", "functions"]) {
		const s = design[section];
		if (isObj(s) && Object.hasOwn(s, name)) return false;
	}
	return true;
}

function copyDesign(design: Design): Design {
	return JSON.parse(JSON.stringify(design)) as Design;
}

/**
 * Adds `name: entry` to the consts or functions object of a design (created
 * when missing), before the entry `before` when given: a constant or function
 * only sees the ones above it.
 */
function addEntry(
	design: Design,
	key: "consts" | "functions",
	name: string,
	entry: unknown,
	before?: string,
) {
	const cur = isObj(design[key])
		? (design[key] as Record<string, unknown>)
		: {};
	const next: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(cur)) {
		if (k === before) next[name] = entry;
		next[k] = v;
	}
	if (!(name in next)) next[name] = entry;
	design[key] = next;
}

/**
 * Moves a node into `consts[name]` and puts the name in its place. Null when
 * the node uses a local (loop or function arg) or a layer ref, or the name is
 * taken. `before`: the constant to insert it above (when extracting from one).
 */
export function extractConst(
	core: Core,
	text: string,
	node: Node,
	name: string,
	locals: string[],
	designJson: Design,
	before?: string,
): Extracted | null {
	const design = copyDesign(designJson);
	if (!nameFree(name, locals, design)) return null;
	if (freeNames(node, locals).length > 0 || hasLayerRef(node)) return null;
	const expr = core.format(text.slice(node.span[0], node.span[1]), BODY_WIDTH);
	if (expr === null) return null;
	const out = splice(core, text, node.span, name);
	if (out === null) return null;
	addEntry(design, "consts", name, expr, before);
	return { text: out, design };
}

/**
 * Moves a node into `functions[name]` and replaces it with `name(args)`. The
 * args must be exactly the locals the node uses (see freeNames). Null when the
 * node uses a layer ref or the name is taken. `before`: the function to insert
 * it above (when extracting from one).
 */
export function extractFunction(
	core: Core,
	text: string,
	node: Node,
	name: string,
	locals: string[],
	args: Arg[],
	designJson: Design,
	before?: string,
): Extracted | null {
	const design = copyDesign(designJson);
	if (!nameFree(name, locals, design)) return null;
	if (hasLayerRef(node)) return null;

	const used = freeNames(node, locals);
	const names = args.map((a) => a.name);
	if (names.length !== used.length || !used.every((u) => names.includes(u)))
		return null;
	if (!args.every((a) => NAME_RE.test(a.name) && !RESERVED.includes(a.name)))
		return null;

	const expr = core.format(text.slice(node.span[0], node.span[1]), BODY_WIDTH);
	if (expr === null) return null;
	const out = splice(core, text, node.span, `${name}(${names.join(", ")})`);
	if (out === null) return null;
	addEntry(
		design,
		"functions",
		name,
		{ args: Object.fromEntries(args.map((a) => [a.name, a.type])), expr },
		before,
	);
	return { text: out, design };
}

/** The smallest node whose span covers [from, to], or null when the root does not. */
export function nodeAt(
	root: Node | null | undefined,
	from: number,
	to: number,
): Node | null {
	const covers = (s: Span) => s[0] <= from && to <= s[1];
	let cur = root && covers(root.span) ? root : null;
	while (cur) {
		const here: Node = cur;
		const next = children(here).find((c) => covers(c.span));
		if (!next) return here;
		cur = next;
	}
	return null;
}
