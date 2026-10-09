// A small scanner for yoshida expressions and templates (FORMAT.md 6.1 to
// 6.6). It never fails: anything it does not understand becomes an `error`
// token. Used for highlighting, and to find the expression (template hole)
// and the function call around the caret.

import { FN_BY_NAME } from "./catalog";

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
};

const identStart = /[A-Za-z_]/;
const identChar = /[A-Za-z0-9_]/;
const builtins = new Set(["canvas", "card", "render"]);

/** Tokens of the expression in text[from, to). */
export function scanExpr(
	text: string,
	from: number,
	to: number,
	names: Names | null,
	out: Tok[],
) {
	let i = from;
	const push = (a: number, b: number, kind: TokKind, note?: string) =>
		out.push({ from: a, to: b, kind, note });
	const ident = (p: number) => {
		let e = p;
		while (e < to && identChar.test(text[e])) e++;
		return e;
	};
	// `.name.name` chains after a name.
	const chain = (p: number, kind: TokKind) => {
		while (
			p < to &&
			text[p] === "." &&
			p + 1 < to &&
			identStart.test(text[p + 1])
		) {
			push(p, p + 1, "punct");
			const e = ident(p + 1);
			push(p + 1, e, kind);
			p = e;
		}
		// A trailing dot while typing is fine.
		if (p < to && text[p] === ".") {
			push(p, p + 1, "punct");
			p++;
		}
		return p;
	};
	while (i < to) {
		const c = text[i];
		if (c === " " || c === "\t" || c === "\n" || c === "\r") {
			i++;
			continue;
		}
		if (/[0-9]/.test(c)) {
			let e = i;
			while (e < to && /[0-9]/.test(text[e])) e++;
			if (text[e] === "." && /[0-9]/.test(text[e + 1] ?? "")) {
				e++;
				while (e < to && /[0-9]/.test(text[e])) e++;
			}
			push(i, e, "num");
			const u = /^(%|vw|vh)/.exec(text.slice(e, Math.min(to, e + 2)));
			if (u && !(u[1] !== "%" && identChar.test(text[e + 2] ?? ""))) {
				push(e, e + u[1].length, "unit");
				e += u[1].length;
			}
			i = e;
			continue;
		}
		if (c === "'" || c === '"') {
			let e = i + 1;
			while (e < to && text[e] !== c) e += text[e] === "\\" ? 2 : 1;
			if (e < to) push(i, e + 1, "str");
			else push(i, to, "error", "Text is missing its closing quote");
			i = Math.min(to, e + 1);
			continue;
		}
		if (c === "#") {
			let e = i + 1;
			while (e < to && /[0-9a-fA-F]/.test(text[e])) e++;
			const len = e - i - 1;
			if ([6, 8, 12, 16].includes(len)) push(i, e, "color");
			else push(i, e, "error", "A color is #RRGGBB or #RRGGBBAA");
			i = e;
			continue;
		}
		if (c === "@") {
			if (i + 1 < to && identStart.test(text[i + 1])) {
				const e = ident(i + 1);
				const id = text.slice(i + 1, e);
				const known = !names || names.layers.has(id);
				push(
					i,
					e,
					known ? "ref" : "unknown",
					known ? undefined : `No layer '${id}' can be referenced here`,
				);
				i = chain(e, "ref-field");
			} else {
				push(i, i + 1, "ref");
				i++;
			}
			continue;
		}
		if (identStart.test(c)) {
			const e = ident(i);
			const w = text.slice(i, e);
			let k = e;
			while (k < to && text[k] === " ") k++;
			const call = text[k] === "(";
			if (w === "and" || w === "or" || w === "not") push(i, e, "keyword");
			else if (w === "true" || w === "false") push(i, e, "bool");
			else if (call)
				push(
					i,
					e,
					FN_BY_NAME.has(w) ? "fn" : "unknown",
					FN_BY_NAME.has(w) ? undefined : `Unknown function '${w}'`,
				);
			else if (builtins.has(w)) {
				push(i, e, "builtin");
				i = chain(e, "prop");
				continue;
			} else if (!names || names.locals.has(w)) {
				push(i, e, "local");
				i = chain(e, "prop");
				continue;
			} else if (names.params.has(w)) push(i, e, "param");
			else if (FN_BY_NAME.has(w)) push(i, e, "fn");
			else push(i, e, "unknown", `Unknown name '${w}'`);
			i = chain(e, "prop");
			continue;
		}
		const two = text.slice(i, i + 2);
		if (["==", "!=", "<=", ">="].includes(two)) {
			push(i, i + 2, "op");
			i += 2;
			continue;
		}
		if ("+-*/%<>?:!".includes(c)) {
			push(i, i + 1, "op");
			i++;
			continue;
		}
		if (c === "." && identStart.test(text[i + 1] ?? "")) {
			i = chain(i, "prop");
			continue;
		}
		if ("()[],.".includes(c)) {
			push(i, i + 1, "punct");
			i++;
			continue;
		}
		push(i, i + 1, "error", `Unexpected '${c}'`);
		i++;
	}
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

export function scan(
	text: string,
	template: boolean,
	names: Names | null,
): Tok[] {
	const out: Tok[] = [];
	if (!template) {
		scanExpr(text, 0, text.length, names, out);
		return out;
	}
	let last = 0;
	const literal = (a: number, b: number) => {
		for (let i = a; i < b; i++) {
			const two = text.slice(i, i + 2);
			if (two === "{{" || two === "}}") {
				out.push({
					from: i,
					to: i + 2,
					kind: "escape",
					note: `Literal '${two[0]}'`,
				});
				i++;
			} else if (text[i] === "}")
				out.push({
					from: i,
					to: i + 1,
					kind: "error",
					note: "A lone '}' — write '}}' for a literal brace",
				});
		}
	};
	for (const h of holes(text)) {
		literal(last, h.from - 1);
		out.push({
			from: h.from - 1,
			to: h.from,
			kind: h.closed ? "brace" : "error",
			note: h.closed ? undefined : "This '{' has no closing '}'",
		});
		if (h.to > h.from) out.push({ from: h.from, to: h.to, kind: "hole" });
		scanExpr(text, h.from, h.to, names, out);
		if (h.closed) out.push({ from: h.to, to: h.to + 1, kind: "brace" });
		last = h.closed ? h.to + 1 : h.to;
	}
	literal(last, text.length);
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
