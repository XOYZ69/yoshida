// Syntax highlighting for the expression input: marks every token from the
// scanner with a `yx-<kind>` class, tints template holes, and puts a small
// color swatch after color literals. Names (params, locals, layers) come
// from a getter, so unknown names can be underlined; dispatch
// `refreshNames` when the names change.

import { type Extension, StateEffect } from "@codemirror/state";
import {
	Decoration,
	type DecorationSet,
	type EditorView,
	ViewPlugin,
	type ViewUpdate,
	WidgetType,
} from "@codemirror/view";
import { type Names, scan } from "./scan";

export const refreshNames = StateEffect.define<null>();

class Swatch extends WidgetType {
	constructor(readonly color: string) {
		super();
	}
	eq(other: Swatch) {
		return other.color === this.color;
	}
	toDOM() {
		const s = document.createElement("span");
		s.className = "yx-swatch";
		s.setAttribute("aria-hidden", "true");
		// 16-bit colors: keep the high byte of each channel.
		const hex = this.color.slice(1);
		const c = hex.length >= 12 ? hex.replace(/(..)../g, "$1") : hex;
		s.style.setProperty("--c", `#${c}`);
		return s;
	}
	ignoreEvent() {
		return true;
	}
}

const marks = new Map<string, Decoration>();
function mark(kind: string, note?: string) {
	const key = `${kind}\0${note ?? ""}`;
	let d = marks.get(key);
	if (!d) {
		d = Decoration.mark({
			class: `yx-${kind}`,
			attributes: note ? { title: note } : undefined,
		});
		marks.set(key, d);
	}
	return d;
}

function build(
	view: EditorView,
	template: boolean,
	names: () => Names | null,
): DecorationSet {
	const text = view.state.doc.toString();
	const toks = scan(text, template, names());
	const ranges = [];
	for (const t of toks) {
		if (t.to <= t.from) continue;
		ranges.push(mark(t.kind, t.note).range(t.from, t.to));
		if (t.kind === "color")
			ranges.push(
				Decoration.widget({
					widget: new Swatch(text.slice(t.from, t.to)),
					side: 1,
				}).range(t.to),
			);
	}
	return Decoration.set(ranges, true);
}

export function exprHighlight(
	template: boolean,
	names: () => Names | null,
): Extension {
	return ViewPlugin.fromClass(
		class {
			decorations: DecorationSet;
			constructor(view: EditorView) {
				this.decorations = build(view, template, names);
			}
			update(u: ViewUpdate) {
				if (
					u.docChanged ||
					u.transactions.some((t) => t.effects.some((e) => e.is(refreshNames)))
				)
					this.decorations = build(u.view, template, names);
			}
		},
		{ decorations: (v) => v.decorations },
	);
}
