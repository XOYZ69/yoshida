// Scanner for yoshida expressions and templates. The syntax is decided by
// the Zig core (core.ts, expr.wasm): this file maps its tokens and problems
// onto highlight kinds, and keeps the text-based helpers that find the
// expression and call around the caret. It never fails: with no core loaded
// it returns no tokens.

import { FN_BY_NAME } from "./catalog";
import { type ExprToken, exprCoreReady, type Problem, parseExpr } from "./core";

export type TokKind =
	| "num"
	| "unit"
	| "str"
	| "color"
	| "ref"
	| "ref-field"
	| "param"
	| "local"
	| "builtin"
	| "prop"
	| "fn"
	| "keyword"
	| "bool"
	| "op"
	| "punct"
	| "unknown"
	| "error"
	| "hole"
	| "brace"
	| "escape";

export type Tok = { from: number; to: number; kind: TokKind; note?: string };

export type Names = {
	params: Map<string, string>;
	locals: Set<string>;
	layers: Map<string, string>;
	/** Design constants and functions. */
	consts?: Set<string>;
	functions?: Set<string>;
};

const identChar = /[A-Za-z0-9_]/;
const builtins = new Set(["canvas", "card", "render"]);

/** The message of the first problem that overlaps [from, to), if any. */
function problemAt(problems: Problem[], from: number, to: number) {
	return problems.find((p) => p.span[0] < to && p.span[1] > from)?.message;
}

/** Highlight range of a problem. A zero-width one marks the character before it. */
function problemRange(p: Problem, len: number): [number, number] | null {
	const [s, e] = p.span;
	if (e > s) return [s, e];
	if (s > 0) return [s - 1, s];
	return len > 0 ? [0, 1] : null;
}

/** Name tokens: what the name is, given what it is followed by and what names exist. */
function nameKind(
	w: string,
	call: boolean,
	names: Names | null,
): { kind: TokKind; note?: string } {
	if (call) {
		const known = FN_BY_NAME.has(w) || !names || !!names.functions?.has(w);
		return known
			? { kind: "fn" }
			: { kind: "unknown", note: `Unknown function '${w}'` };
	}
	if (builtins.has(w)) return { kind: "builtin" };
	if (!names || names.locals.has(w)) return { kind: "local" };
	if (names.params.has(w)) return { kind: "param" };
	if (names.consts?.has(w)) return { kind: "param", note: "Constant" };
	if (FN_BY_NAME.has(w)) return { kind: "fn" };
	return { kind: "unknown", note: `Unknown name '${w}'` };
}

/** Highlight tokens of an expression or template, from the Zig core. */
export function scan(
	text: string,
	template: boolean,
	names: Names | null,
): Tok[] {
	if (!exprCoreReady() || text.length === 0) return [];
	const r = parseExpr(text, template);
	const out: Tok[] = [];
	const push = (from: number, to: number, kind: TokKind, note?: string) =>
		out.push({ from, to, kind, note });

	// A `{` whose hole never closes.
	const unclosed = new Set<number>();
	for (const p of r.problems)
		if (p.message.startsWith("unclosed '{'")) unclosed.add(p.span[0]);

	// `.name` chains: a name after a reference is a reference field.
	let afterDot = false;
	let chainRef = false;
	const toks: ExprToken[] = r.tokens;
	for (let i = 0; i < toks.length; i++) {
		const [from, to, kind] = toks[i];
		const w = text.slice(from, to);
		const dotted = afterDot;
		afterDot = false;
		const isDot = kind === "punct" && w === ".";
		afterDot = isDot;
		if (!isDot && !(kind === "name" && dotted)) chainRef = kind === "ref";

		switch (kind) {
			case "number":
				push(from, to, "num");
				break;
			case "unit":
				push(from, to, "unit");
				break;
			case "string":
				push(from, to, "str");
				break;
			case "color":
				push(from, to, "color");
				break;
			case "ref": {
				const id = w.slice(1);
				const known = !names || !id || names.layers.has(id);
				push(
					from,
					to,
					known ? "ref" : "unknown",
					known ? undefined : `No layer '${id}' can be referenced here`,
				);
				break;
			}
			case "name": {
				if (dotted) {
					push(from, to, chainRef ? "ref-field" : "prop");
					break;
				}
				const next = toks[i + 1];
				const call = !!next && next[2] === "punct" && text[next[0]] === "(";
				const k = nameKind(w, call, names);
				push(from, to, k.kind, k.note);
				break;
			}
			case "keyword":
				push(from, to, w === "true" || w === "false" ? "bool" : "keyword");
				break;
			case "op":
				push(from, to, "op");
				break;
			case "punct":
				push(from, to, "punct");
				break;
			case "bad":
				push(
					from,
					to,
					"error",
					problemAt(r.problems, from, to) ?? "Unexpected text",
				);
				break;
			case "escape":
				push(from, to, "escape", `Literal '${w[0]}'`);
				break;
			case "brace":
				if (unclosed.has(from))
					push(from, to, "error", "This '{' has no closing '}'");
				else push(from, to, "brace");
				break;
			case "text":
				break;
		}
	}

	for (const h of r.holes ?? []) {
		const closed = !unclosed.has(h.span[0]);
		const from = h.span[0] + 1;
		const to = closed ? h.span[1] - 1 : h.span[1];
		if (to > from) push(from, to, "hole");
	}

	// Every problem, so nothing invalid goes unmarked.
	for (const p of r.problems) {
		const range = problemRange(p, text.length);
		if (range) push(range[0], range[1], "error", p.message);
	}
	return out;
}

/** Tokens of the expression in text[from, to), appended to `out`. */
export function scanExpr(
	text: string,
	from: number,
	to: number,
	names: Names | null,
	out: Tok[],
) {
	for (const t of scan(text.slice(from, to), false, names))
		out.push({ ...t, from: t.from + from, to: t.to + from });
}

export type Hole = { from: number; to: number; closed: boolean };

/** The `{...}` holes of a template: from/to are the expression inside the braces. */
export function holes(text: string): Hole[] {
	const out: Hole[] = [];
	let i = 0;
	while (i < text.length) {
		const c = text[i];
		if (
			(c === "{" && text[i + 1] === "{") ||
			(c === "}" && text[i + 1] === "}")
		) {
			i += 2;
			continue;
		}
		if (c === "{") {
			let e = i + 1;
			let q = "";
			while (e < text.length) {
				const d = text[e];
				if (q) {
					if (d === "\\") e++;
					else if (d === q) q = "";
				} else if (d === "'" || d === '"') q = d;
				else if (d === "}" || d === "{") break;
				e++;
			}
			const closed = text[e] === "}";
			out.push({ from: i + 1, to: e, closed });
			i = closed ? e + 1 : e;
			continue;
		}
		i++;
	}
	return out;
}

/** The expression range the caret is in: the whole text, or a template hole; null in template literal text. */
export function exprAt(
	text: string,
	pos: number,
	template: boolean,
): { from: number; to: number } | null {
	if (!template) return { from: 0, to: text.length };
	for (const h of holes(text)) if (pos >= h.from && pos <= h.to) return h;
	return null;
}

/** True when `pos` is inside a string literal of the expression starting at `from`. */
export function inString(text: string, from: number, pos: number): boolean {
	let q = "";
	for (let i = from; i < pos; i++) {
		const c = text[i];
		if (q) {
			if (c === "\\") i++;
			else if (c === q) q = "";
		} else if (c === "'" || c === '"') q = c;
	}
	return q !== "";
}

/** The innermost function call whose parentheses contain `pos`, and which argument the caret is in. */
export function callAt(
	text: string,
	from: number,
	pos: number,
): { name: string; open: number; arg: number } | null {
	const stack: { name: string; open: number; arg: number }[] = [];
	let q = "";
	for (let i = from; i < pos; i++) {
		const c = text[i];
		if (q) {
			if (c === "\\") i++;
			else if (c === q) q = "";
			continue;
		}
		if (c === "'" || c === '"') q = c;
		else if (c === "(" || c === "[") {
			let k = i - 1;
			while (k >= from && text[k] === " ") k--;
			let s = k;
			while (s >= from && identChar.test(text[s])) s--;
			const name =
				c === "(" && s < k && text[s] !== "@" && text[s] !== "."
					? text.slice(s + 1, k + 1)
					: "";
			stack.push({ name, open: i, arg: 0 });
		} else if (c === ")" || c === "]") stack.pop();
		else if (c === "," && stack.length) stack[stack.length - 1].arg++;
	}
	for (let j = stack.length - 1; j >= 0; j--)
		if (stack[j].name) return stack[j];
	return null;
}
