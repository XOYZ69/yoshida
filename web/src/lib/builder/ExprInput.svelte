<script lang="ts">
// Input for expressions and templates (CodeMirror 6): syntax highlighting,
// suggestions with types and docs (params, repeat names, @layer fields,
// built-ins, functions), signature help inside a function call, and a ƒ
// button that opens a reference of everything usable in this field, and a ⤢
// button (or Ctrl+Shift+E) that opens the formula panel: the expression as
// its parts, for editing.
// Hovering a name shows what it is; Ctrl/Cmd+click (or F12) shows where it
// is defined, through the `yoshida-goto` context.
// Enter (or leaving the field, or Ctrl+Enter) commits; Shift+Enter starts a
// new line. A single-line field does not wrap: a long expression scrolls
// sideways, and wraps only once its text has a newline. Templates always
// wrap. Templates: Enter starts a new line and Ctrl+Enter
// commits. Shift+Alt+F (or Ctrl+Shift+F) reformats an expression. Escape
// reverts the draft. Under the text, a breadcrumb shows where the caret is in
// the syntax tree. One EditorView per instance.

import {
	acceptCompletion,
	autocompletion,
	closeCompletion,
	completionStatus,
	startCompletion,
} from "@codemirror/autocomplete";
import {
	defaultKeymap,
	history,
	historyKeymap,
	insertNewline,
} from "@codemirror/commands";
import {
	Compartment,
	EditorSelection,
	EditorState,
	type Extension,
	Prec,
} from "@codemirror/state";
import {
	placeholder as cmPlaceholder,
	drawSelection,
	EditorView,
	keymap,
	tooltips,
} from "@codemirror/view";
import { getContext, onMount } from "svelte";
import type { Expect } from "../expr/catalog";
import { exprCompletion, kindBadge, optionClass } from "../expr/completion";
import { exprCoreReady, formatExpr, parseExpr } from "../expr/core";
import { crumbPath } from "../expr/crumbs";
import FormulaPanel from "../expr/FormulaPanel.svelte";
import { exprHighlight, refreshNames } from "../expr/highlight";
import { exprHover } from "../expr/hover";
import Reference from "../expr/Reference.svelte";
import type { Names } from "../expr/scan";
import { exprAt } from "../expr/scan";
import { signatureHelp } from "../expr/signature";
import { exprTheme } from "../expr/theme";
import type { CompletionContext, GotoTarget } from "./complete";

let {
	value,
	multiline = false,
	template = false,
	suggest = true,
	mono = false,
	placeholder = "",
	rows = 1,
	expect = "any",
	label = "",
	path,
	oncommit,
}: {
	value: string;
	multiline?: boolean;
	template?: boolean;
	suggest?: boolean;
	mono?: boolean;
	placeholder?: string;
	rows?: number;
	/** The type the field needs; ranks suggestions and dims ones of another type. */
	expect?: Expect;
	/** Accessible name of the input. */
	label?: string;
	/** JSON pointer of the field in the design (e.g. `/layers/3/fill`): live values in the formula panel. */
	path?: string;
	oncommit: (v: string) => void;
} = $props();

const ctxFn = getContext<(() => CompletionContext) | undefined>(
	"yoshida-complete",
);

const gotoFn = getContext<((t: GotoTarget) => void) | undefined>(
	"yoshida-goto",
);

let host: HTMLDivElement | undefined = $state();
let fbtn: HTMLButtonElement | undefined = $state();
let view: EditorView | null = null;
let ready = $state(false);
/** The user changed the text since the last commit or outside update. */
let editing = false;
/** True while we replace the text ourselves (outside value). */
let syncing = false;
let refOpen = $state(false);
/** The formula panel, and the text it opened with. */
let formulaOpen = $state(false);
let formulaText = $state("");
/** The breadcrumb under the text: the path to the caret in the syntax tree. */
let crumbs: string[] = $state([]);
/** The text as the editor has it now (for the ⤢ button). */
let draft = $state("");
/** Line wrapping: on for templates and multiline fields, else only with a newline. */
const wrap = new Compartment();

// Read through getters so the long-lived editor sees current props.
const getCtx = () => ctxFn?.() ?? null;
const getExpect = () => expect;
const highlighted = $derived(suggest || template);
/** ⤢ only for a real expression: not empty, a literal or a single name. */
const formulaable = $derived(canOpenFormula(draft));

const plainKinds = new Set([
	"number",
	"unit",
	"string",
	"boolean",
	"color",
	"name",
]);

function canOpenFormula(t: string): boolean {
	if (!t.trim()) return false;
	if (!exprCoreReady()) return true;
	let root = parseExpr(t, false).root;
	// `-5` and `-10%` are literals too.
	if (root?.k === "neg" && root.x) root = root.x;
	return !root || !plainKinds.has(root.k);
}

function names(): Names | null {
	const c = getCtx();
	if (!c) return null;
	return {
		params: new Map(c.params.map((p) => [p.name, p.type])),
		locals: new Set(c.locals.map((l) => l.name)),
		layers: new Map(c.layers.map((l) => [l.id, l.type])),
		consts: new Set((c.consts ?? []).map((k) => k.name)),
		functions: new Set((c.functions ?? []).map((f) => f.name)),
	};
}

function text() {
	return view ? view.state.doc.toString() : value;
}

function commit() {
	editing = false;
	const d = text();
	if (d !== value) oncommit(d);
}

/** Opens the formula panel on the field's current text (not for templates). */
function openFormula(): boolean {
	if (template || !suggest) return false;
	formulaText = text();
	formulaOpen = true;
	return true;
}

/** Hands the panel's text to the field and commits it, as Enter does. */
function applyFormula(v: string) {
	setText(v);
	commit();
}

function closeFormula() {
	formulaOpen = false;
	view?.focus();
}

function revert(v: EditorView) {
	if (refOpen) {
		refOpen = false;
		return true;
	}
	setText(value);
	editing = false;
	v.contentDOM.blur();
	return true;
}

function setText(t: string) {
	if (!view || view.state.doc.toString() === t) return;
	syncing = true;
	view.dispatch({
		changes: { from: 0, to: view.state.doc.length, insert: t },
		selection: EditorSelection.cursor(
			Math.min(t.length, view.state.selection.main.head),
		),
	});
	syncing = false;
}

function extensions(): Extension[] {
	const keys = keymap.of([
		{
			key: "Enter",
			run: (v) => {
				if (multiline) return insertNewline(v);
				commit();
				return true;
			},
		},
		{ key: "Shift-Enter", run: insertNewline },
		{
			key: "Mod-Enter",
			run: () => {
				commit();
				return true;
			},
		},
		{ key: "Shift-Alt-f", run: reformat },
		{ key: "Ctrl-Shift-f", run: reformat },
		{ key: "Mod-Shift-e", run: openFormula },
		{ key: "Escape", run: revert },
		...defaultKeymap.filter((k) => k.key !== "Enter" && k.key !== "Mod-Enter"),
		...historyKeymap,
	]);
	const ext: Extension[] = [
		history(),
		drawSelection(),
		keys,
		exprTheme,
		tooltips({ position: "fixed", parent: document.body }),
		EditorView.contentAttributes.of({
			"aria-label":
				label || placeholder || (template ? "Template" : "Expression"),
			"aria-multiline": String(multiline),
			spellcheck: "false",
			autocapitalize: "off",
			autocorrect: "off",
		}),
		EditorView.updateListener.of((u) => {
			if (u.docChanged && !syncing) editing = true;
			if (u.docChanged) draft = u.state.doc.toString();
			if (u.docChanged || u.selectionSet || u.focusChanged)
				refreshCrumbs(u.view);
		}),
		EditorView.domEventHandlers({
			blur: () => {
				// Clicks in our tooltips and popover keep the focus; anything else commits.
				setTimeout(() => {
					if (view && !view.hasFocus) commit();
				}, 0);
				return false;
			},
		}),
	];
	// Wrapping follows the text: see `wrap`. The same transaction switches it.
	let wrapOn = multiline || template || value.includes("\n");
	ext.push(
		wrap.of(wrapOn ? EditorView.lineWrapping : []),
		EditorState.transactionExtender.of((tr) => {
			if (!tr.docChanged) return null;
			const on = multiline || template || tr.newDoc.lines > 1;
			if (on === wrapOn) return null;
			wrapOn = on;
			return { effects: wrap.reconfigure(on ? EditorView.lineWrapping : []) };
		}),
	);
	if (placeholder) ext.push(cmPlaceholder(placeholder));
	if (highlighted) ext.push(exprHighlight(template, names));
	if (suggest && ctxFn) {
		ext.push(
			autocompletion({
				override: [exprCompletion(getCtx, template, getExpect)],
				icons: false,
				addToOptions: [kindBadge],
				optionClass,
				maxRenderedOptions: 100,
				aboveCursor: false,
			}),
			Prec.high(keymap.of([{ key: "Tab", run: acceptCompletion }])),
			signatureHelp(template),
			exprHover(
				getCtx,
				template,
				gotoFn &&
					((t) => {
						// Keep what was typed: going there can unmount this field.
						commit();
						gotoFn(t);
					}),
			),
		);
	}
	return ext;
}

onMount(() => {
	view = new EditorView({
		state: EditorState.create({ doc: value, extensions: extensions() }),
		parent: host!,
	});
	draft = value;
	ready = true;
	return () => {
		view?.destroy();
		view = null;
	};
});

// Outside changes (other field, undo, card switch) while not editing.
$effect(() => {
	const v = value;
	if (!ready || editing) return;
	setText(v);
});

// New params or layers: re-highlight unknown names.
$effect(() => {
	if (!ctxFn || !ready || !highlighted) return;
	ctxFn();
	view?.dispatch({ effects: refreshNames.of(null) });
});

/** The breadcrumb for the caret, while this field has focus. */
function refreshCrumbs(v: EditorView) {
	const path =
		suggest && v.hasFocus
			? crumbPath(v.state.doc.toString(), v.state.selection.main.head, template)
			: [];
	crumbs = path.length >= 2 ? path : [];
}

/** The field's width in characters, for formatting: 24 to 100. */
function fieldWidth(v: EditorView): number {
	const cw = v.defaultCharacterWidth || 8;
	return Math.min(100, Math.max(24, Math.floor(v.contentDOM.clientWidth / cw)));
}

/** Replaces the expression with its canonical layout, and commits it. Templates are left alone. */
function reformat(v: EditorView): boolean {
	if (template || !exprCoreReady()) return true;
	const doc = v.state.doc.toString();
	const out = formatExpr(doc, fieldWidth(v));
	if (out === null || out === doc) return true;
	v.dispatch({
		changes: { from: 0, to: v.state.doc.length, insert: out },
		selection: { anchor: out.length },
		userEvent: "input",
		scrollIntoView: true,
	});
	commit();
	return true;
}

function toggleRef() {
	if (!view) return;
	if (!refOpen) {
		closeCompletion(view);
		view.focus();
	}
	refOpen = !refOpen;
}

/** Inserts reference text at the caret; in template literal text it goes into a new `{}` hole. */
function insertRef(t: string, reopen: boolean) {
	if (!view) return;
	const sel = view.state.selection.main;
	const doc = view.state.doc.toString();
	const inHole = !template || exprAt(doc, sel.from, true) !== null;
	// Outside a hole: wrap in `{}`; keep the caret inside when more typing follows.
	const insert = inHole ? t : `{${t}}`;
	const open = reopen || t.endsWith("(");
	const caret =
		sel.from + (inHole ? t.length : open ? 1 + t.length : insert.length);
	view.dispatch({
		changes: { from: sel.from, to: sel.to, insert },
		selection: { anchor: caret },
		userEvent: "input",
		scrollIntoView: true,
	});
	view.focus();
	refOpen = false;
	if (reopen)
		setTimeout(
			() =>
				view && completionStatus(view.state) === null && startCompletion(view),
			0,
		);
}
</script>

<!-- A long one-line value is cut at the edge: the tooltip shows all of it. -->
<div class="expr" class:mono class:multiline class:hasfx={suggest && !!ctxFn} style:--rows={rows} title={!multiline && value.length > 18 ? value : undefined}>
  <div class="host" bind:this={host}></div>
  {#if suggest && (ctxFn || !template)}
    <div class="fxs">
      {#if suggest && ctxFn}
        <button
          bind:this={fbtn}
          class="fx"
          class:on={refOpen}
          tabindex="-1"
          title="What can I use here? (functions, params, layers…)"
          aria-label="Expression reference"
          aria-expanded={refOpen}
          onmousedown={(e) => e.preventDefault()}
          onclick={toggleRef}>ƒ</button>
      {/if}
      {#if !template && formulaable}
        <button
          class="fx fe"
          tabindex="-1"
          title="Formula panel (Ctrl+Shift+E)"
          aria-label="Formula panel"
          aria-expanded={formulaOpen}
          onmousedown={(e) => e.preventDefault()}
          onclick={openFormula}>⤢</button>
      {/if}
    </div>
  {/if}
  {#if crumbs.length}
    <div class="yx-crumbs" title={crumbs.join(' › ')}>{crumbs.join(' › ')}</div>
  {/if}
</div>
{#if refOpen && ctxFn}
  <Reference ctx={ctxFn()} {expect} {template} anchor={() => fbtn?.getBoundingClientRect() ?? null} ignore={fbtn} oninsert={insertRef} onclose={() => (refOpen = false)} />
{/if}
{#if formulaOpen}
  <FormulaPanel text={formulaText} {label} {path} onapply={applyFormula} onclose={closeFormula} />
{/if}

<style>
  /* Extra syntax colors; app.css defines --syn-ref/param/hole for both
     themes, the fallbacks only apply if it does not. */
  :global(:root) {
    --yx-ref: var(--syn-ref, #b0347f);
    --yx-param: var(--syn-param, #0b7a87);
    --yx-hole: var(--syn-hole, rgba(59, 108, 246, 0.09));
  }

  .expr {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-wrap: wrap;
    align-items: stretch;
    box-sizing: border-box;
    background: var(--bg-code);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 4px;
    font-size: 13px;
    transition:
      border-color 0.1s,
      box-shadow 0.1s;
  }
  .expr:focus-within {
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent);
  }
  .expr.mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .host {
    flex: 1;
    min-width: 0;
    display: flex;
  }
  /* Under the text, inside the field: the path to the caret. */
  .yx-crumbs {
    flex: 1 1 100%;
    padding: 0 8px 3px;
    font-size: 11px;
    line-height: 16px;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    user-select: none;
  }
  .host :global(.cm-editor) {
    width: 100%;
  }
  .multiline .host :global(.cm-content) {
    min-height: calc(var(--rows, 1) * 18px + 6px);
  }
  .fxs {
    flex: none;
    align-self: flex-start;
    display: flex;
  }
  .fx {
    flex: none;
    align-self: flex-start;
    height: 24px;
    padding: 0 6px;
    border: none;
    border-left: 1px solid transparent;
    border-radius: 0 3px 3px 0;
    background: none;
    color: var(--muted);
    font: italic 600 13px/24px Georgia, 'Times New Roman', serif;
    opacity: 0.5;
    cursor: pointer;
  }
  .expr:hover .fx,
  .expr:focus-within .fx {
    opacity: 1;
  }
  .fe {
    font: 600 13px/24px system-ui, -apple-system, 'Segoe UI', sans-serif;
  }
  .fx:hover,
  .fx.on {
    color: var(--accent);
    background: var(--hover);
  }

  /* States set by Field.svelte on its wrapper. */
  :global(.bad) .expr {
    border-color: var(--err);
  }
  :global(.unset) .expr :global(.cm-content) {
    color: var(--muted);
  }
</style>
