<script lang="ts">
// Input for expressions and templates (CodeMirror 6): syntax highlighting,
// suggestions with types and docs (params, repeat names, @layer fields,
// built-ins, functions), signature help inside a function call, and a ƒ
// button that opens a reference of everything usable in this field.
// Single line: Enter or leaving the field commits, newlines are dropped.
// Multiline (templates): newlines allowed, leaving the field (or Ctrl+Enter)
// commits. Escape reverts the draft. One EditorView per instance.

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
	EditorSelection,
	EditorState,
	type Extension,
	Prec,
	Transaction,
	type TransactionSpec,
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
import { exprHighlight, refreshNames } from "../expr/highlight";
import Reference from "../expr/Reference.svelte";
import type { Names } from "../expr/scan";
import { exprAt } from "../expr/scan";
import { signatureHelp } from "../expr/signature";
import { exprTheme } from "../expr/theme";
import type { CompletionContext } from "./complete";

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
	oncommit: (v: string) => void;
} = $props();

const ctxFn = getContext<(() => CompletionContext) | undefined>(
	"yoshida-complete",
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

// Read through getters so the long-lived editor sees current props.
const getCtx = () => ctxFn?.() ?? null;
const getExpect = () => expect;
const highlighted = $derived(suggest || template);

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

/** Single line: newlines typed or pasted become spaces. */
const oneLine = EditorState.transactionFilter.of(
	(
		tr: Transaction,
	): Transaction | TransactionSpec | readonly TransactionSpec[] => {
		if (!tr.docChanged || tr.newDoc.lines === 1) return tr;
		const changes: { from: number; to: number; insert: string }[] = [];
		let end = 0;
		tr.changes.iterChanges((fromA, toA, _fromB, toB, ins) => {
			const insert = ins.toString().replace(/\r?\n/g, " ");
			changes.push({ from: fromA, to: toA, insert });
			end = toB;
		});
		return {
			changes,
			selection: EditorSelection.cursor(end),
			userEvent: tr.annotation(Transaction.userEvent),
			scrollIntoView: true,
		};
	},
);

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
		{
			key: "Mod-Enter",
			run: () => {
				commit();
				return true;
			},
		},
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
	if (multiline) ext.push(EditorView.lineWrapping);
	else ext.push(oneLine);
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
		);
	}
	return ext;
}

onMount(() => {
	view = new EditorView({
		state: EditorState.create({ doc: value, extensions: extensions() }),
		parent: host!,
	});
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
</div>
{#if refOpen && ctxFn}
  <Reference ctx={ctxFn()} {expect} {template} anchor={() => fbtn?.getBoundingClientRect() ?? null} ignore={fbtn} oninsert={insertRef} onclose={() => (refOpen = false)} />
{/if}

<style>
  /* Extra syntax colors (app.css has the base --syn-* ones). */
  :global(:root) {
    --yx-ref: var(--syn-ref, #b0347f);
    --yx-param: var(--syn-param, #0b7a87);
    --yx-hole: var(--syn-hole, rgba(59, 108, 246, 0.09));
  }
  @media (prefers-color-scheme: dark) {
    :global(:root) {
      --yx-ref: var(--syn-ref, #f08cc8);
      --yx-param: var(--syn-param, #5fd0dc);
      --yx-hole: var(--syn-hole, rgba(110, 147, 255, 0.14));
    }
  }

  .expr {
    flex: 1;
    min-width: 0;
    display: flex;
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
  .host :global(.cm-editor) {
    width: 100%;
  }
  .multiline .host :global(.cm-content) {
    min-height: calc(var(--rows, 1) * 18px + 6px);
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
