// Signature help: while the caret is inside a function call's parentheses
// (and the editor has focus), a tooltip above the call shows the signature
// with the current argument highlighted, and the function's doc.

import {
	type EditorState,
	type Extension,
	StateEffect,
	StateField,
} from "@codemirror/state";
import { EditorView, showTooltip, type Tooltip } from "@codemirror/view";
import type { CompletionContext } from "../builder/complete";
import { FN_BY_NAME, type FnDoc } from "./catalog";
import { signatureNode } from "./completion";
import { callAt, exprAt } from "./scan";

const focusEffect = StateEffect.define<boolean>();

const focusField = StateField.define<boolean>({
	create: () => false,
	update(v, tr) {
		for (const e of tr.effects) if (e.is(focusEffect)) return e.value;
		return v;
	},
});

type Help = { key: string; tip: Tooltip | null };

/** A design function (`functions`) as a signature; a built-in of the same name is hidden. */
function designFnDoc(
	f: NonNullable<CompletionContext["functions"]>[number],
): FnDoc {
	const names = f.args
		.split(",")
		.map((a) => a.trim())
		.filter(Boolean);
	return {
		name: f.name,
		args: names.map((name) => ({ name, type: "any" })),
		ret: "any",
		doc: f.note || "A design function.",
		example: f.expr ?? "",
	};
}

function tooltip(f: FnDoc, pos: number, arg: number): Tooltip {
	return {
		pos,
		above: true,
		strictSide: false,
		arrow: false,
		create: () => {
			const dom = document.createElement("div");
			dom.className = "yx-sighelp";
			dom.appendChild(signatureNode(f, arg));
			const doc = document.createElement("div");
			doc.className = "yx-sighelp-doc";
			const a = f.args[Math.min(arg, f.args.length - 1)];
			doc.textContent =
				f.doc +
				(a && !a.rest && !f.alt && f.args.length > 1
					? `  ·  ${a.name}: ${a.type}`
					: "");
			dom.appendChild(doc);
			return { dom };
		},
	};
}

function compute(
	state: EditorState,
	template: boolean,
	prev: Help,
	getCtx: () => CompletionContext | null,
): Help {
	const none = { key: "", tip: null };
	if (!state.field(focusField)) return none;
	const sel = state.selection.main;
	if (!sel.empty) return none;
	const text = state.doc.toString();
	const range = exprAt(text, sel.head, template);
	const call = range && callAt(text, range.from, sel.head);
	if (!call) return none;
	const own = getCtx()?.functions?.find((x) => x.name === call.name);
	const f = own ? designFnDoc(own) : FN_BY_NAME.get(call.name);
	if (!f) return none;
	const pos = call.open - call.name.length;
	const key = `${pos}:${call.name}:${call.arg}`;
	// Same call and argument: keep the tooltip so it does not flicker.
	return key === prev.key ? prev : { key, tip: tooltip(f, pos, call.arg) };
}

export function signatureHelp(
	template: boolean,
	getCtx: () => CompletionContext | null,
): Extension {
	const field = StateField.define<Help>({
		create: () => ({ key: "", tip: null }),
		update(v, tr) {
			if (
				!tr.docChanged &&
				!tr.selection &&
				!tr.effects.some((e) => e.is(focusEffect))
			)
				return v;
			return compute(tr.state, template, v, getCtx);
		},
		provide: (f) => showTooltip.compute([f], (s) => s.field(f).tip),
	});
	return [
		focusField,
		field,
		EditorView.focusChangeEffect.of((_s, focusing) => focusEffect.of(focusing)),
	];
}
