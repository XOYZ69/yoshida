<script lang="ts">
// Code editor for the Advanced view (CodeMirror 6): JSON highlighting,
// folding, search, bracket matching, problem markers from the core, and
// `jump` to move the cursor to a line and column.

import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import {
	defaultKeymap,
	history,
	historyKeymap,
	indentWithTab,
} from "@codemirror/commands";
import { json } from "@codemirror/lang-json";
import {
	bracketMatching,
	foldGutter,
	foldKeymap,
	HighlightStyle,
	indentOnInput,
	syntaxHighlighting,
} from "@codemirror/language";
import {
	type Diagnostic as CmDiagnostic,
	lintGutter,
	setDiagnostics,
} from "@codemirror/lint";
import { highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import { EditorState, type Extension } from "@codemirror/state";
import {
	drawSelection,
	EditorView,
	highlightActiveLine,
	highlightActiveLineGutter,
	keymap,
	lineNumbers,
} from "@codemirror/view";
import { tags } from "@lezer/highlight";
import { onMount } from "svelte";
import type { Diagnostic } from "./engine";

let {
	text,
	path,
	diagnostics = [],
	jump = null,
	readonly = false,
	onchange,
}: {
	text: string;
	path: string;
	diagnostics?: Diagnostic[];
	jump?: { line: number; col: number; nonce: number } | null;
	readonly?: boolean;
	onchange: (text: string) => void;
} = $props();

let host: HTMLDivElement | undefined = $state();
let view: EditorView | null = null;
/** The text last given to or reported by the editor, to tell outside changes apart. */
let known = "";

const highlight = HighlightStyle.define([
	{ tag: tags.propertyName, color: "var(--syn-key)" },
	{ tag: tags.string, color: "var(--syn-string)" },
	{ tag: tags.number, color: "var(--syn-number)" },
	{ tag: [tags.bool, tags.null], color: "var(--syn-keyword)" },
	{ tag: tags.punctuation, color: "var(--muted)" },
]);

const theme = EditorView.theme({
	"&": {
		height: "100%",
		fontSize: "13px",
		backgroundColor: "var(--bg-code)",
		color: "var(--fg)",
	},
	".cm-scroller": { fontFamily: "var(--mono)", lineHeight: "1.5" },
	".cm-gutters": {
		backgroundColor: "var(--bg-bar)",
		color: "var(--muted)",
		borderRight: "1px solid var(--line)",
	},
	".cm-activeLine": { backgroundColor: "var(--hover)" },
	".cm-activeLineGutter": { backgroundColor: "var(--hover)" },
	"&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
		backgroundColor: "var(--sel) !important",
	},
	".cm-cursor": { borderLeftColor: "var(--fg)" },
	".cm-tooltip": {
		backgroundColor: "var(--bg)",
		color: "var(--fg)",
		border: "1px solid var(--line)",
	},
	".cm-panels": { backgroundColor: "var(--bg-bar)", color: "var(--fg)" },
	// The search panel (Ctrl+F): app-styled fields, buttons and option chips.
	".cm-panel.cm-search": { padding: "6px 8px", fontSize: "12px" },
	".cm-panel.cm-search .cm-textfield": {
		backgroundColor: "var(--bg)",
		color: "var(--fg)",
		border: "1px solid var(--line)",
		borderRadius: "6px",
		padding: "3px 8px",
		fontSize: "12px",
		verticalAlign: "middle",
	},
	".cm-panel.cm-search .cm-textfield:focus": {
		outline: "none",
		borderColor: "var(--accent)",
	},
	".cm-panel.cm-search .cm-button": {
		font: "inherit",
		fontSize: "12px",
		backgroundImage: "none",
		backgroundColor: "var(--bg)",
		color: "var(--fg)",
		border: "1px solid var(--line)",
		borderRadius: "6px",
		padding: "3px 10px",
		verticalAlign: "middle",
		cursor: "pointer",
	},
	".cm-panel.cm-search .cm-button:hover": { backgroundColor: "var(--hover)" },
	".cm-panel.cm-search .cm-button:active": { backgroundImage: "none" },
	// Option checkboxes: the native box stays focusable and labelled but is hidden; the label is the chip.
	".cm-panel.cm-search label:has(input)": {
		position: "relative",
		display: "inline-block",
		boxSizing: "border-box",
		margin: "2px 6px 2px 0",
		padding: "3px 10px",
		border: "1px solid var(--line)",
		borderRadius: "6px",
		backgroundColor: "var(--bg)",
		color: "var(--fg)",
		fontSize: "12px",
		lineHeight: "1.4",
		cursor: "pointer",
	},
	".cm-panel.cm-search label input[type=checkbox]": {
		appearance: "none",
		position: "absolute",
		inset: "0",
		width: "100%",
		height: "100%",
		margin: "0",
		opacity: "0",
		cursor: "pointer",
	},
	".cm-panel.cm-search label:has(input):hover": { backgroundColor: "var(--hover)" },
	".cm-panel.cm-search label:has(input:focus-visible)": {
		outline: "2px solid var(--accent)",
		outlineOffset: "1px",
	},
	".cm-panel.cm-search label:has(input:checked)": {
		backgroundColor: "var(--accent-strong)",
		borderColor: "var(--accent-strong)",
		color: "var(--on-accent)",
	},
	".cm-panel.cm-search button[name=close]": {
		position: "absolute",
		top: "4px",
		right: "6px",
		margin: "0",
		padding: "0 4px",
		border: "0",
		backgroundColor: "transparent",
		boxShadow: "none",
		color: "var(--muted)",
		font: "inherit",
		fontSize: "16px",
		lineHeight: "1",
	},
	".cm-panel.cm-search button[name=close]:hover": { color: "var(--fg)" },
});

// Labels of the search panel, capitalised like the rest of the app's buttons.
// Keys are the ones @codemirror/search passes to state.phrase(). "Find" and
// "Replace" (placeholders) are already capitalised, so they are not listed.
const searchPhrases = EditorState.phrases.of({
	next: "Next",
	previous: "Previous",
	all: "All",
	"match case": "Match case",
	regexp: "Regexp",
	"by word": "By word",
	replace: "Replace",
	"replace all": "Replace all",
});

function language(p: string): Extension[] {
	return p.endsWith(".json") ? [json()] : [];
}

function makeState(doc: string) {
	return EditorState.create({
		doc,
		extensions: [
			lineNumbers(),
			foldGutter(),
			lintGutter(),
			highlightActiveLineGutter(),
			highlightActiveLine(),
			drawSelection(),
			history(),
			indentOnInput(),
			bracketMatching(),
			closeBrackets(),
			highlightSelectionMatches(),
			syntaxHighlighting(highlight),
			keymap.of([
				...closeBracketsKeymap,
				...defaultKeymap,
				...searchKeymap,
				...historyKeymap,
				...foldKeymap,
				indentWithTab,
			]),
			EditorState.tabSize.of(2),
			EditorState.readOnly.of(readonly),
			theme,
			searchPhrases,
			language(path),
			EditorView.updateListener.of((u) => {
				if (!u.docChanged) return;
				known = u.state.doc.toString();
				onchange(known);
			}),
		],
	});
}

onMount(() => {
	known = text;
	view = new EditorView({ state: makeState(text), parent: host! });
	return () => view?.destroy();
});

// A different file: fresh state (own undo history and language).
let shownPath = "";
$effect(() => {
	const p = path;
	if (!view || p === shownPath) return;
	if (shownPath) {
		known = text;
		view.setState(makeState(text));
	}
	shownPath = p;
});

// The same file changed from outside (builder, card form, undo): replace
// the text but keep the editor.
$effect(() => {
	const t = text;
	if (!view || t === known) return;
	known = t;
	view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: t } });
});

function offset(line: number, col: number) {
	const doc = view!.state.doc;
	const l = doc.line(Math.max(1, Math.min(line, doc.lines)));
	return Math.min(l.to, l.from + Math.max(0, col - 1));
}

$effect(() => {
	const ds = diagnostics;
	void text;
	if (!view) return;
	const out: CmDiagnostic[] = [];
	for (const d of ds) {
		if (!d.line) continue;
		const from = offset(d.line, d.col);
		const lineEnd = view.state.doc.lineAt(from).to;
		out.push({
			from,
			to: Math.max(from + 1, Math.min(lineEnd, from + 60)),
			severity: d.severity === "hint" ? "info" : d.severity,
			message: `${d.code}: ${d.message}${d.hint ? `\n${d.hint}` : ""}`,
		});
	}
	view.dispatch(setDiagnostics(view.state, out));
});

$effect(() => {
	if (!jump || !view) return;
	const pos = offset(jump.line, jump.col);
	view.dispatch({
		selection: { anchor: pos },
		effects: EditorView.scrollIntoView(pos, { y: "center" }),
	});
	view.focus();
});
</script>

<div class="editor" bind:this={host}></div>

<style>
  .editor {
    flex: 1;
    min-height: 0;
    overflow: hidden;
  }
  .editor :global(.cm-editor) {
    height: 100%;
  }
  .editor :global(.cm-editor.cm-focused) {
    outline: none;
  }
</style>
