// Shows an expression in its canonical multi-line layout while the text stays
// on one line. The gaps where the formatter would break a line are replaced by
// a widget that draws the line break and the indent; the document is not
// changed, so a design never saves the breaks (a JSON string can only hold
// them as `\n`). The caret moves over a break as over one character.

import { RangeSetBuilder } from "@codemirror/state";
import {
	Decoration,
	type DecorationSet,
	EditorView,
	ViewPlugin,
	type ViewUpdate,
	WidgetType,
} from "@codemirror/view";
import { exprCoreReady, formatExpr, parseExpr } from "./core";
import { layoutBreaks } from "./edit";

class BreakWidget extends WidgetType {
	constructor(readonly text: string) {
		super();
	}
	eq(other: BreakWidget): boolean {
		return other.text === this.text;
	}
	toDOM(): HTMLElement {
		const el = document.createElement("span");
		el.className = "yx-break";
		el.textContent = this.text;
		return el;
	}
}

/** The widest layout: the width the formula window formats to, so both show the same. */
const MAX_WIDTH = 72;

/** The field's width in characters, for formatting: 24 to 72. */
function widthOf(v: EditorView): number {
	const cw = v.defaultCharacterWidth || 8;
	return Math.min(
		MAX_WIDTH,
		Math.max(24, Math.floor(v.contentDOM.clientWidth / cw)),
	);
}

function build(v: EditorView): DecorationSet {
	const b = new RangeSetBuilder<Decoration>();
	if (!exprCoreReady()) return b.finish();
	const doc = v.state.doc.toString();
	const breaks = layoutBreaks(doc, widthOf(v), formatExpr, (s) =>
		parseExpr(s, false).tokens.map((t): [number, number] => [t[0], t[1]]),
	);
	for (const k of breaks) {
		const widget = new BreakWidget(k.text);
		if (k.from === k.to)
			b.add(k.from, k.to, Decoration.widget({ widget, side: 1 }));
		else b.add(k.from, k.to, Decoration.replace({ widget }));
	}
	return b.finish();
}

/** The layout view for a one-line expression field (not for templates). */
export const exprLayout = ViewPlugin.fromClass(
	class {
		decorations: DecorationSet;
		constructor(v: EditorView) {
			this.decorations = build(v);
		}
		update(u: ViewUpdate) {
			if (u.docChanged || u.geometryChanged)
				this.decorations = build(u.view);
		}
	},
	{
		decorations: (p) => p.decorations,
		provide: (plugin) =>
			EditorView.atomicRanges.of(
				(v) => v.plugin(plugin)?.decorations ?? Decoration.none,
			),
	},
);

export const layoutTheme = EditorView.baseTheme({
	".yx-break": { whiteSpace: "pre" },
});
