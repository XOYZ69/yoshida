// Edits of an expression through its syntax tree, for the formula panel.
// Each edit rewrites the source text and returns its canonical layout, or
// null when the result does not parse; the text is then left as it was.
// Pure functions: the formatter is passed in (formatExpr from core.ts), so
// the tests can run them against expr.wasm without a browser.
//
// Spans are UTF-16 offsets into the text the node was parsed from.

import type { Node, NodeKind, Span } from "./core";

/** The formatter: canonical text at a width, or null when the source has problems. */
export type Format = (src: string, width: number) => string | null;

/** The width the edits format to: the same as a field of the panel. */
const WIDTH = 72;

/** A piece of the expression: a node with its source text. */
export type Slot = {
	/** The node id, for the live values of its trace. */
	id: number;
	kind: NodeKind;
	span: Span;
	text: string;
};

export type MatchRow = { key: Slot; result: Slot };

export type MatchView = {
	subject: Slot;
	rows: MatchRow[];
	/** The default: the last argument. */
	fallback: Slot;
};

export type CondRow = { when: Slot; result: Slot };

export type CondChain = {
	/** One row per `cond` of the chain; a single cond has one row. */
	rows: CondRow[];
	/** The final else branch: not a cond. */
	fallback: Slot;
};

export type ListView = { value: Slot; items: Slot[] };

export type OutlineItem = {
	/** Child indexes from the root (see `children`). */
	path: number[];
	depth: number;
	label: string;
	kind: NodeKind;
	text: string;
};

export function slot(n: Node, text: string): Slot {
	return {
		id: n.id,
		kind: n.k,
		span: n.span,
		text: text.slice(n.span[0], n.span[1]),
	};
}

/** The parts of a node in source order. */
export function children(n: Node): Node[] {
	const out: Node[] = [];
	for (const c of [
		n.obj,
		n.idx,
		n.x,
		n.l,
		n.r,
		n.c,
		n.a,
		n.b,
		n.value,
		...(n.args ?? []),
		...(n.items ?? []),
	])
		if (c) out.push(c);
	return out.sort((p, q) => p.span[0] - q.span[0]);
}

/** The node at a path of child indexes, or null when the path does not exist. */
export function nodeAt(root: Node, path: number[]): Node | null {
	let n: Node | null = root;
	for (const i of path) {
		n = n ? (children(n)[i] ?? null) : null;
	}
	return n;
}

/** The node without the parentheses around it. */
function unwrap(n: Node): Node {
	let cur = n;
	while (cur.k === "paren" && cur.x) cur = cur.x;
	return cur;
}

/** Replaces the source at `span` with `cell`, in parentheses, and formats the result. */
export function replaceSlot(
	text: string,
	span: Span,
	cell: string,
	format: Format,
): string | null {
	const next = `${text.slice(0, span[0])}(${cell})${text.slice(span[1])}`;
	return format(next, WIDTH);
}

/** The argument sources of a call. */
function argTexts(n: Node, text: string): string[] {
	return (n.args ?? []).map((a) => text.slice(a.span[0], a.span[1]));
}

/** Rewrites a call with new argument sources. */
function rewriteCall(
	text: string,
	n: Node,
	args: string[],
	format: Format,
): string | null {
	const call = `${n.fn}(${args.join(", ")})`;
	return format(text.slice(0, n.span[0]) + call + text.slice(n.span[1]), WIDTH);
}

/** The keys and results of a `match(value, key, result, ..., default)` call; null for other nodes. */
export function matchView(n: Node, text: string): MatchView | null {
	const args = n.args ?? [];
	if (
		n.k !== "call" ||
		n.fn !== "match" ||
		args.length < 4 ||
		args.length % 2 !== 0
	)
		return null;
	const rows: MatchRow[] = [];
	for (let i = 1; i + 1 < args.length; i += 2)
		rows.push({ key: slot(args[i], text), result: slot(args[i + 1], text) });
	return {
		subject: slot(args[0], text),
		rows,
		fallback: slot(args[args.length - 1], text),
	};
}

/** Adds a row before the default, with the placeholder key `'key'` and the default as its result. */
export function addMatchRow(
	text: string,
	n: Node,
	format: Format,
): string | null {
	const args = argTexts(n, text);
	const fallback = args.pop();
	if (fallback === undefined) return null;
	args.push("'key'", fallback, fallback);
	return rewriteCall(text, n, args, format);
}

/** Removes row `index` of a match. Null when it would leave no row. */
export function removeMatchRow(
	text: string,
	n: Node,
	index: number,
	format: Format,
): string | null {
	const args = argTexts(n, text);
	const rows = (args.length - 2) / 2;
	if (rows < 2 || index < 0 || index >= rows) return null;
	args.splice(1 + index * 2, 2);
	return rewriteCall(text, n, args, format);
}

/** The branches of a `?:` chain, from its first cond; null for other nodes. */
export function condChain(n: Node, text: string): CondChain | null {
	if (n.k !== "cond" || !n.c || !n.a || !n.b) return null;
	const rows: CondRow[] = [];
	let cur: Node = n;
	while (cur.k === "cond" && cur.c && cur.a && cur.b) {
		rows.push({ when: slot(cur.c, text), result: slot(cur.a, text) });
		cur = unwrap(cur.b);
	}
	return { rows, fallback: slot(cur, text) };
}

/** The value and the items of an `in [...]` test; null for other nodes. */
export function listView(n: Node, text: string): ListView | null {
	if (n.k !== "in_list" || !n.value) return null;
	return {
		value: slot(n.value, text),
		items: (n.items ?? []).map((i) => slot(i, text)),
	};
}

/** Rewrites an `in` test with new item sources. The value is parenthesised: `in` binds looser than `+`. */
function rewriteList(
	text: string,
	n: Node,
	value: string,
	items: string[],
	format: Format,
): string | null {
	const list = `(${value}) in [${items.join(", ")}]`;
	return format(text.slice(0, n.span[0]) + list + text.slice(n.span[1]), WIDTH);
}

/** Adds an item to an `in` test. Null for an empty item. */
export function addChip(
	text: string,
	n: Node,
	item: string,
	format: Format,
): string | null {
	const chip = item.trim();
	if (n.k !== "in_list" || !n.value || chip === "") return null;
	const items = (n.items ?? []).map((i) => text.slice(i.span[0], i.span[1]));
	items.push(chip);
	const value = text.slice(n.value.span[0], n.value.span[1]);
	return rewriteList(text, n, value, items, format);
}

/** Removes item `index` of an `in` test. */
export function removeChip(
	text: string,
	n: Node,
	index: number,
	format: Format,
): string | null {
	if (n.k !== "in_list" || !n.value) return null;
	const items = (n.items ?? []).map((i) => text.slice(i.span[0], i.span[1]));
	if (index < 0 || index >= items.length) return null;
	items.splice(index, 1);
	const value = text.slice(n.value.span[0], n.value.span[1]);
	return rewriteList(text, n, value, items, format);
}

/** Nodes worth a line in the outline: calls, `?:` chains, `and`/`or`, `in` tests. */
function interesting(n: Node, tail: boolean): boolean {
	switch (n.k) {
		case "call":
		case "ucall":
		case "in_list":
			return true;
		case "cond":
			// The else branch of a chain is part of the chain's first line.
			return !tail;
		case "binary":
			return n.op === "and" || n.op === "or";
		default:
			return false;
	}
}

function labelOf(n: Node): string {
	switch (n.k) {
		case "call":
		case "ucall":
			return n.fn ?? "call";
		case "cond":
			return "? :";
		case "in_list":
			return "in";
		default:
			return n.op ?? n.k;
	}
}

/** The outline of a tree: its interesting nodes in source order, indented by depth. */
export function outline(root: Node, text: string): OutlineItem[] {
	const out: OutlineItem[] = [];
	const visit = (n: Node, depth: number, path: number[], tail: boolean) => {
		let d = depth;
		if (interesting(n, tail)) {
			out.push({
				path,
				depth,
				label: labelOf(n),
				kind: n.k,
				text: text.slice(n.span[0], n.span[1]),
			});
			d = depth + 1;
		}
		children(n).forEach((c, i) => {
			// The else branch of a cond, also through parentheses.
			const next = (n.k === "cond" && c === n.b) || (n.k === "paren" && tail);
			visit(c, d, [...path, i], next);
		});
	};
	visit(root, 0, [], false);
	return out;
}
