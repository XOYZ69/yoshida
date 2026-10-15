// The breadcrumb under an expression field: the path from the root of the
// syntax tree to the innermost node around the caret, as short labels
// (`match › arg 3 › with_alpha › arg 1`). Leaf nodes add no label; paren
// nodes and fields and indexes are passed through.

import { exprCoreReady, type Node, parseExpr, type Span } from "./core";
import { exprAt } from "./scan";

function contains(span: Span, pos: number): boolean {
	return span[0] <= pos && pos <= span[1];
}

function within<T extends { span: Span }>(list: T[], pos: number): number {
	return list.findIndex((n) => contains(n.span, pos));
}

/** Labels of the path from `n` down to the caret at `pos`. */
function walk(n: Node, pos: number, out: string[]) {
	switch (n.k) {
		case "paren":
		case "err":
			if (n.x && contains(n.x.span, pos)) walk(n.x, pos, out);
			return;
		case "field":
			if (n.obj && contains(n.obj.span, pos)) walk(n.obj, pos, out);
			return;
		case "index":
			if (n.obj && contains(n.obj.span, pos)) walk(n.obj, pos, out);
			else if (n.idx && contains(n.idx.span, pos)) walk(n.idx, pos, out);
			return;
		case "call":
		case "ucall": {
			out.push(n.fn ?? "call");
			const args = n.args ?? [];
			const i = within(args, pos);
			if (i >= 0) {
				out.push(`arg ${i + 1}`);
				walk(args[i], pos, out);
			}
			return;
		}
		case "cond": {
			out.push("? :");
			const parts: [string, Node | undefined][] = [
				["if", n.c],
				["then", n.a],
				["else", n.b],
			];
			for (const [label, part] of parts)
				if (part && contains(part.span, pos)) {
					out.push(label);
					walk(part, pos, out);
					return;
				}
			return;
		}
		case "binary": {
			out.push(n.op ?? "");
			const side = [n.l, n.r].find((s) => s && contains(s.span, pos));
			if (side) walk(side, pos, out);
			return;
		}
		case "in_list": {
			out.push("in");
			if (n.value && contains(n.value.span, pos)) walk(n.value, pos, out);
			else {
				const items = n.items ?? [];
				const i = within(items, pos);
				if (i >= 0) walk(items[i], pos, out);
			}
			return;
		}
		case "neg":
		case "not":
			out.push(n.k === "neg" ? "-" : "not");
			if (n.x && contains(n.x.span, pos)) walk(n.x, pos, out);
			return;
		default:
			// Leaves: names, literals, layer references.
			return;
	}
}

/**
 * The breadcrumb labels for the caret at `pos`, or [] when there is no
 * expression there (a template's literal text, or no core loaded).
 */
export function crumbPath(
	text: string,
	pos: number,
	template: boolean,
): string[] {
	if (!exprCoreReady()) return [];
	const range = exprAt(text, pos, template);
	if (!range) return [];
	const r = parseExpr(text, template);
	let root: Node | null | undefined;
	if (template) {
		const hole = (r.holes ?? []).find((h) => contains(h.span, pos));
		root = hole?.root;
	} else root = r.root;
	if (!root) return [];
	const out: string[] = [];
	walk(root, pos, out);
	return out;
}
