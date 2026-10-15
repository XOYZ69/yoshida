<script lang="ts">
// The formula editor: a floating window that shows an expression by its
// parts. A match is a table of key and result rows, a ?: chain a list of
// when and then rows, an `in` test a list of chips; anything else is one
// field with its source. A breadcrumb shows the path to the selected part,
// and the open buttons of the cells drill into the calls, chains and tests
// inside it. The text below the parts is the whole expression. Both stay in
// step: a cell edit rewrites the text through edit.ts, and it is kept only
// when the result parses. Apply (or closing the window) hands the text to
// the field; Escape closes it while the focus is in the window. With the
// editor's live context the values of each part show next to it, for the
// card on the stage. "Extract to" moves a part into a new design constant or
// function, after a name is asked for.

import { getContext, onMount, untrack } from "svelte";
import type { ScopeResult } from "../engine";
import Icon from "../ui/Icon.svelte";
import { askText, overlay } from "../ui/overlay.svelte";
import Window from "../ui/Window.svelte";
import { exprCoreReady, formatExpr, type Node, parseExpr } from "./core";
import {
	addChip,
	addMatchRow,
	children,
	condChain,
	listView,
	matchView,
	nodeAt,
	openPath,
	partTrail,
	removeChip,
	removeMatchRow,
	replaceSlot,
	type Slot,
	slot,
} from "./edit";
import {
	type EvalResult,
	LIVE_CONTEXT,
	type LiveContext,
	type LiveValue,
} from "./live";
import {
	type Arg,
	BUILTIN_NAMES,
	type Core,
	canExtract,
	condChainToMatch,
	extractConst,
	extractFunction,
	freeNames,
	hasLayerRef,
	matchToCondChain,
	RESERVED,
} from "./rewrite";

let {
	text,
	label = "",
	path,
	onapply,
	onclose,
}: {
	/** The field's text when the editor opened. */
	text: string;
	/** The field's label, for the window title. */
	label?: string;
	/** JSON pointer of the field in the design: enables live values. */
	path?: string;
	onapply: (v: string) => void;
	onclose: () => void;
} = $props();

const live = getContext<LiveContext | undefined>(LIVE_CONTEXT);

/** The text the field has now: what Apply compares with. */
let base = $state(untrack(() => text));
/** The full expression, as edited in the text area and the cells. */
let draft = $state(untrack(() => text));
/** Child indexes from the root to the selected node (see edit.ts `children`). */
let selPath = $state<number[]>([]);
/** Cells whose typed text does not parse, by span: they keep the typed text. */
let bad = $state<Record<string, string>>({});
let note = $state("");
let result = $state<{ src: string; r: EvalResult } | null>(null);
/** The window's body: its focus is what Escape acts on. */
let body: HTMLElement | undefined = $state();

const parsed = $derived(exprCoreReady() ? parseExpr(draft, false) : null);
const root = $derived(parsed?.root ?? null);
/** The selected path, or the root when the text changed under it. */
const activePath = $derived(root && nodeAt(root, selPath) ? selPath : []);
const sel = $derived(root ? (nodeAt(root, activePath) ?? root) : null);
const selSlot = $derived(sel ? slot(sel, draft) : null);
const mv = $derived(sel ? matchView(sel, draft) : null);
const cc = $derived(sel ? condChain(sel, draft) : null);
const lv = $derived(sel ? listView(sel, draft) : null);
/** The selected part has no parts of its own: a literal or a name. */
const leaf = $derived(!!sel && children(sel).length === 0);
const trail = $derived(root ? partTrail(root, activePath) : []);
const dirty = $derived(draft !== base);
/** Rows of the text area: one per line, at least 2, then it scrolls. */
const textRows = $derived(Math.min(8, Math.max(2, draft.split("\n").length)));

// Live values: only those of the current draft, since node ids change with it.
const liveTrace = $derived(
	result && result.src === draft ? result.r.trace : null,
);
const hits = $derived(result && result.src === draft ? result.r.hits : null);

/** The part of the projection taken on the live card: a row, the fallback, or neither. */
const taken = $derived.by(() => {
	const none = { row: -1, fallback: false };
	const trace = liveTrace;
	if (!trace) return none;
	if (mv) {
		const subject = trace[mv.subject.id] ?? null;
		if (subject === null) return none;
		const row = mv.rows.findIndex((r) => (trace[r.key.id] ?? null) === subject);
		return row >= 0 ? { row, fallback: false } : { row: -1, fallback: true };
	}
	if (cc) {
		const row = cc.rows.findIndex((r) => trace[r.when.id] === true);
		return row >= 0 ? { row, fallback: false } : { row: -1, fallback: true };
	}
	return none;
});

// Evaluate the field on the live card: at once when the editor opens, then
// 200 ms after the last change of the text.
let seq = 0;
let first = true;
$effect(() => {
	const src = draft;
	if (!live || !path) return;
	const mine = ++seq;
	const delay = first ? 0 : 200;
	first = false;
	const t = setTimeout(() => {
		live
			.eval(path, src)
			.catch(() => null)
			.then((r) => {
				if (mine === seq) result = r ? { src, r } : null;
			});
	}, delay);
	return () => clearTimeout(t);
});

// ------------------------------------------------------------ quick actions

const core: Core = {
	parse: (src) => parseExpr(src, false),
	format: formatExpr,
};
/** The field's scope, for the locals an extracted part uses. */
let scope = $state<ScopeResult | null>(null);
$effect(() => {
	if (!live || !path) return;
	live.scope(path).then((r) => (scope = r));
});

/** The design section and entry the field is in, when it is a constant or function body. */
const home = $derived.by(() => {
	const m = /^\/(consts|functions)\/([^/]+)/.exec(path ?? "");
	return m
		? { key: m[1], name: m[2].replace(/~1/g, "/").replace(/~0/g, "~") }
		: null;
});
const inConst = $derived(home?.key === "consts");
const toMatch = $derived(
	sel && cc && cc.rows.length > 1 ? condChainToMatch(core, draft, sel) : null,
);
const toChain = $derived(sel && mv ? matchToCondChain(core, draft, sel) : null);

const ARG_TYPES = ["number", "text", "bool", "color"];
const localNames = $derived(scope ? scope.locals.map((l) => l.name) : []);
/** The repeat names and function arguments the selected part uses, in order. */
const used = $derived(sel ? freeNames(sel, localNames) : []);
const usedArgs = $derived<Arg[]>(
	used.map((n) => ({
		name: n,
		type: scope?.locals.find((l) => l.name === n)?.type ?? "",
	})),
);
const usesLayer = $derived(!!sel && hasLayerRef(sel));

const NO_DESIGN =
	"Only a field of a design can extract parts into it. Open the field from the editor.";
const TOO_SMALL =
	"A single value or name is already as small as it gets: select a larger part.";

/** Why the selected part cannot become a constant; "" when it can. */
const constWhy = $derived.by(() => {
	if (!live || !path || !scope || !sel) return NO_DESIGN;
	if (!canExtract(sel)) return TOO_SMALL;
	if (usesLayer) return "It refers to a layer, which a constant cannot do.";
	if (used.length)
		return `It uses ${used.join(", ")}, which only a function can take. Extract a function instead.`;
	return "";
});

/** Why the selected part cannot become a function; "" when it can. */
const fnWhy = $derived.by(() => {
	if (!live || !path || !scope || !sel) return NO_DESIGN;
	if (!canExtract(sel)) return TOO_SMALL;
	if (usesLayer) return "It refers to a layer, which a function cannot do.";
	if (inConst)
		return "This field is the value of a constant, and a function cannot be added from here.";
	const bad = usedArgs.find((a) => !ARG_TYPES.includes(a.type));
	if (bad)
		return `'${bad.name}' is a ${bad.type || "value"}; function arguments can only be numbers, text, bools or colors.`;
	return "";
});

const CONST_HELP =
	"Move the selected part into a new design constant and use its name here. Constants are shared by every field of the design.";

/** The function's help, with the arguments the part uses. */
const fnHelp = $derived(
	`Move the selected part into a new design function. Repeat names and arguments it uses become the function's arguments (here: ${used.length ? used.join(", ") : "none"}), and the call takes its place.`,
);

function convert(r: { text: string; note?: string } | null) {
	if (take(r ? r.text : null)) {
		selPath = [];
		note = r?.note ? `Converted; ${r.note}.` : "";
	}
}

/** Why a name cannot be a new constant or function here; "" when it can. */
function nameProblem(name: string): string {
	if (!name) return "";
	if (!/^[a-z][a-z0-9_]*$/.test(name))
		return "Use lowercase letters, digits and _, starting with a letter.";
	if (
		RESERVED.includes(name) ||
		BUILTIN_NAMES.includes(name)
	)
		return `'${name}' is a word of the expression language.`;
	if (localNames.includes(name))
		return `'${name}' is a repeat name or argument of this field.`;
	const d = live?.design();
	for (const [section, what] of [
		["params", "parameter"],
		["consts", "constant"],
		["functions", "function"],
	] as const) {
		const s = d?.[section];
		if (s && typeof s === "object" && Object.hasOwn(s, name))
			return `'${name}' is already a ${what} of the design.`;
	}
	return "";
}

/** The name a new constant or function starts with: the field label, when that is a valid name. */
function defaultName(): string {
	const base = label
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "_")
		.replace(/^[^a-z]+/, "")
		.replace(/_+$/, "");
	return nameProblem(base) ? "" : base;
}

/** Asks for a name, then moves the selected part into a new constant or function. */
async function startExtract(kind: "const" | "function") {
	if (!sel) return;
	const part = draft
		.slice(sel.span[0], sel.span[1])
		.replace(/\s+/g, " ")
		.trim();
	const shown = part.length > 60 ? `${part.slice(0, 59)}…` : part;
	const message =
		kind === "const"
			? `"${shown}" moves into a new constant. This field will use the constant's name instead.`
			: `"${shown}" moves into a new function${used.length === 0 ? " with no arguments" : used.length === 1 ? `, which takes the argument ${used[0]}` : `, which takes the arguments ${used.join(", ")}`}. This field will call the function in its place.`;
	const name = await askText({
		title: kind === "const" ? "Extract to constant" : "Extract to function",
		message,
		value: defaultName(),
		placeholder: kind === "const" ? "constant name" : "function name",
		confirm: "Extract",
		validate: nameProblem,
	});
	if (name !== null) extract(kind, name.trim());
}

/** Moves the selected part into a new constant or function of the design. */
function extract(kind: "const" | "function", name: string) {
	const d = live?.design();
	if (!live || !path || !scope || !sel || !d) return;
	const why = kind === "const" ? constWhy : fnWhy;
	if (why) {
		note = why;
		return;
	}
	const before =
		home && home.key === (kind === "const" ? "consts" : "functions")
			? home.name
			: undefined;
	const r =
		kind === "const"
			? extractConst(core, draft, sel, name, localNames, d, before)
			: extractFunction(
					core,
					draft,
					sel,
					name,
					localNames,
					usedArgs,
					d,
					before,
				);
	if (!r) {
		note = `Cannot extract as '${name}': the name is taken or not valid.`;
		return;
	}
	live.extract(r.design, path, r.text);
	base = r.text;
	draft = r.text;
	bad = {};
	selPath = [];
	note = "";
}

function keyOf(s: Slot): string {
	return `${s.span[0]}:${s.span[1]}`;
}

function cellValue(s: Slot): string {
	return bad[keyOf(s)] ?? s.text;
}

function cellBad(s: Slot): boolean {
	return keyOf(s) in bad;
}

/** Takes a new full text from an edit; null keeps the text and says why. */
function take(next: string | null): boolean {
	if (next === null) {
		note = "That change does not parse, so the text is unchanged.";
		return false;
	}
	draft = next;
	bad = {};
	note = "";
	return true;
}

/** A cell changed: its text goes into the expression, or it stays red. */
function setCell(s: Slot, value: string) {
	const k = keyOf(s);
	if (value === s.text) {
		const rest = { ...bad };
		delete rest[k];
		bad = rest;
		return;
	}
	const next = replaceSlot(draft, s.span, value, formatExpr);
	if (next === null) {
		bad = { ...bad, [k]: value };
		note = "That cell does not parse, so the text is unchanged.";
		return;
	}
	take(next);
}

function setText(v: string) {
	draft = v;
	bad = {};
	note = "";
}

/** Selects a part of the expression: the breadcrumb and the open buttons. */
function select(p: number[]) {
	selPath = p;
	bad = {};
	note = "";
}

/** The path an open button of a cell selects: a structure, other than the selection. */
function openTo(s: Slot): number[] | null {
	if (!root) return null;
	const p = openPath(root, s.id);
	return p && !samePath(p, activePath) ? p : null;
}

function apply() {
	if (!dirty) return;
	onapply(draft);
	base = draft;
}

function close() {
	apply();
	onclose();
}

/** Formats a live value: numbers to 3 decimals, text quoted, lists in brackets. */
function fmt(v: LiveValue | null | undefined): string {
	if (v === undefined || v === null) return "";
	if (typeof v === "number") return String(Number(v.toFixed(3)));
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "string") return isHex(v) ? v : `'${v}'`;
	return `[${v.map((x) => fmt(x)).join(", ")}]`;
}

function isHex(v: string): boolean {
	return /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(v);
}

/** Ids of literal nodes: their value is their text, so no value is shown next to them. */
const literals = $derived.by(() => {
	const ids = new Set<number>();
	const walk = (n: Node) => {
		if (n.k === "paren" && n.x) walk(n.x);
		else if (["number", "unit", "string", "boolean", "color"].includes(n.k))
			ids.add(n.id);
		for (const c of [n.obj, n.idx, n.x, n.l, n.r, n.c, n.a, n.b, n.value])
			if (c && n.k !== "paren") walk(c);
		for (const c of [...(n.args ?? []), ...(n.items ?? [])]) walk(c);
	};
	if (root) walk(root);
	return ids;
});

function liveOf(id: number): LiveValue | null {
	if (literals.has(id)) return null;
	return liveTrace?.[id] ?? null;
}

function samePath(a: number[], b: number[]): boolean {
	return a.length === b.length && a.every((x, i) => x === b[i]);
}

/** Escape acts only when the focus is in this window (its title bar or body). */
function inWindow(e: KeyboardEvent): boolean {
	const win = body?.closest('[role="dialog"]');
	return !!win && e.target instanceof Node && win.contains(e.target);
}

function onKey(e: KeyboardEvent) {
	// A dialog (askText) is open, or it has just taken this Escape: it closes
	// first, and the window stays.
	if (e.defaultPrevented || overlay.dialog !== null || !inWindow(e)) return;
	if (e.key === "Escape") {
		e.preventDefault();
		e.stopPropagation();
		// Blurring a cell commits what was typed in it.
		if (document.activeElement instanceof HTMLInputElement)
			document.activeElement.blur();
		close();
	}
}

// When a dialog of this window closes, the focus goes back to the window, so
// that Escape keeps working.
let inDialog = false;
$effect(() => {
	const open = overlay.dialog !== null;
	if (inDialog && !open) body?.focus();
	inDialog = open;
});

onMount(() => {
	// Capture, so Escape closes the window and not the editor under it.
	window.addEventListener("keydown", onKey, true);
	body?.focus();
	return () => window.removeEventListener("keydown", onKey, true);
});
</script>

{#snippet val(id: number)}
	{#if liveOf(id) !== null}
		{@const v = liveOf(id)}
		<span class="lv">{#if typeof v === "string" && isHex(v)}<span class="sw" style:background={v}></span>{/if}{fmt(v)}</span>
	{/if}
{/snippet}

{#snippet opener(s: Slot)}
	{@const p = openTo(s)}
	{#if p}
		<button class="open" title="Open this part" aria-label="Open this part" onclick={() => select(p)}><Icon name="chevron-right" /></button>
	{/if}
{/snippet}

{#snippet cell(s: Slot, name: string)}
	<span class="cell">
		{#if s.kind === "color"}<span class="sw" style:background={s.text}></span>{/if}
		<input
			class="in"
			class:invalid={cellBad(s)}
			aria-label={name}
			value={cellValue(s)}
			spellcheck="false"
			onchange={(e) => setCell(s, e.currentTarget.value)}
			onkeydown={(e) => {
				if (e.key === "Enter") {
					e.preventDefault();
					setCell(s, e.currentTarget.value);
				}
			}} />
		{@render val(s.id)}
		{@render opener(s)}
	</span>
{/snippet}

<Window
	key="formula"
	title={label ? `Formula: ${label}` : "Formula"}
	width={540}
	minWidth={380}
	fit
	onclose={close}>
	<div class="formula" bind:this={body} tabindex="-1">
		<nav class="trail" aria-label="Path">
			{#each trail as c, i}
				{#if i > 0}<span class="sep" aria-hidden="true">›</span>{/if}
				<button
					class="crumb"
					aria-current={i === trail.length - 1 ? "step" : undefined}
					onclick={() => select(c.path)}>{c.label}</button>
			{/each}
			{#if live && live.card()}
				<span class="card">values for: {live.card()}</span>
			{/if}
		</nav>

		{#if sel}
			<div class="toolbar">
				<div class="convert">
					{#if toMatch}<button title="Rewrite this ?: chain as one match(), with the same subject, keys and results." onclick={() => convert(toMatch)}>To match</button>{/if}
					{#if toChain}<button title="Rewrite this match as a ?: chain: one when per key. A subject that is not a plain name is repeated in each when." onclick={() => convert(toChain)}>To ?: chain</button>{/if}
				</div>
				<span class="btn-group extract" role="group" aria-label="Extract">
					<span class="group-cap" aria-hidden="true"><Icon name="ungroup" /> Extract to</span>
					<button disabled={!!constWhy} title={constWhy || CONST_HELP} onclick={() => startExtract("const")}>Constant</button>
					<button disabled={!!fnWhy} title={fnWhy || fnHelp} onclick={() => startExtract("function")}>Function</button>
				</span>
			</div>
		{/if}

		{#if hits === 0}
			<p class="hint">Not evaluated for this card.</p>
		{/if}

		{#if !root}
			<p class="hint">The expression does not parse yet. Fix the text below.</p>
		{:else if mv && sel}
			<h3>Match on <code>{mv.subject.text}</code> {@render val(mv.subject.id)} {@render opener(mv.subject)}</h3>
			<table>
				<thead>
					<tr><th>key</th><th>result</th><th></th></tr>
				</thead>
				<tbody>
					{#each mv.rows as r, i}
						<tr class:hit={taken.row === i}>
							<td>{@render cell(r.key, `key ${i + 1}`)}</td>
							<td>{@render cell(r.result, `result ${i + 1}`)}</td>
							<td>
								{#if mv.rows.length > 1}
									<button class="x" aria-label="Delete row {i + 1}" title="Delete row"
										onclick={() => take(removeMatchRow(draft, sel, i, formatExpr))}>×</button>
								{/if}
							</td>
						</tr>
					{/each}
					<tr class:hit={taken.fallback}>
						<td><span class="kw">default</span></td>
						<td>{@render cell(mv.fallback, "default")}</td>
						<td></td>
					</tr>
				</tbody>
			</table>
			<button class="add-row" title="Add a key and a result before the default" onclick={() => take(addMatchRow(draft, sel, formatExpr))}>+ row</button>
		{:else if cc && cc.rows[0]}
			<h3>Conditions</h3>
			<ol class="chain">
				{#each cc.rows as r, i}
					<li class:hit={taken.row === i}>
						<span class="kw">when</span>
						{@render cell(r.when, `when ${i + 1}`)}
						<span class="kw">then</span>
						{@render cell(r.result, `then ${i + 1}`)}
					</li>
				{/each}
				<li class="else" class:hit={taken.fallback}>
					<span class="kw">else</span>
					{@render cell(cc.fallback, "else")}
				</li>
			</ol>
		{:else if lv && sel}
			<div class="list">
				<div class="lrow">
					<span class="kw">value</span>
					{@render cell(lv.value, "value")}
				</div>
				<ul class="chips">
					{#each lv.items as it, i}
						<li class="chip">
							{#if it.kind === "color"}<span class="sw" style:background={it.text}></span>{/if}
							<code>{it.text}</code>
							{#if lv.items.length > 1}
								<button class="x" aria-label="Remove {it.text}" title="Remove"
									onclick={() => take(removeChip(draft, sel, i, formatExpr))}>×</button>
							{/if}
						</li>
					{/each}
					<li>
						<input
							class="in add"
							aria-label="New item"
							placeholder="add item"
							spellcheck="false"
							onkeydown={(e) => {
								if (e.key !== "Enter") return;
								e.preventDefault();
								const input = e.currentTarget;
								if (take(addChip(draft, sel, input.value, formatExpr)))
									input.value = "";
							}} />
					</li>
				</ul>
			</div>
		{:else if leaf}
			<p class="hint">A literal or a name has no parts. Edit it here or in the text below.</p>
			{#if selSlot}<div class="one">{@render cell(selSlot, "expression")}</div>{/if}
		{:else if selSlot}
			<div class="one">
				{@render cell(selSlot, "expression")}
			</div>
		{/if}

		<textarea
			class="text"
			aria-label="Expression text"
			rows={textRows}
			spellcheck="false"
			value={draft}
			oninput={(e) => setText(e.currentTarget.value)}
			onkeydown={(e) => {
				if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
					e.preventDefault();
					apply();
				}
			}}></textarea>

		<footer>
			<div class="status-line">
				{#if parsed && parsed.problems.length}
					<p class="prob">{parsed.problems[0].message}</p>
				{/if}
				{#if note}
					<p class="note">{note}</p>
				{/if}
			</div>
			<button class="primary" disabled={!dirty} onclick={apply} title="Hand the text to the field (Ctrl+Enter)">Apply</button>
		</footer>
	</div>
</Window>

<style>
  /* The body of the window: the parts, the text and the footer, one under the other. */
  .formula {
    flex: 1;
    min-height: 0;
    overflow: auto;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 10px 14px;
    background: var(--bg);
    color: var(--fg);
    font-size: 13px;
    outline: none;
  }
  /* The path to the selected part: one small button per step. */
  .trail {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 2px;
    min-height: 24px;
    font-size: 12px;
  }
  .crumb {
    height: 24px;
    padding: 0 6px;
    border: 0;
    border-radius: 4px;
    background: none;
    color: var(--muted);
    font: inherit;
    font-size: 12px;
    white-space: nowrap;
  }
  .crumb:hover {
    background: var(--hover);
    color: var(--fg);
  }
  .crumb[aria-current="step"] {
    color: var(--fg);
    font-weight: 600;
  }
  .sep {
    color: var(--muted);
  }
  .trail .card {
    max-width: 100%;
    min-width: 0;
    margin-left: auto;
    padding-left: 8px;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  /* The conversions on the left, the Extract group on the right: one row. */
  .toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: nowrap;
    gap: 8px;
  }
  .convert {
    flex: none;
    display: flex;
    gap: 6px;
  }
  .convert > button {
    height: var(--ctl-h);
    white-space: nowrap;
  }
  .extract {
    flex: none;
    height: var(--ctl-h);
    margin-left: auto;
  }
  .extract > button {
    padding: 0 8px;
    font-weight: 500;
  }
  /* The caption cell of a group (as in the top bar's Export group). */
  .group-cap {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 0 7px 0 6px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    background: var(--bg-bar);
  }
  /* Section captions, as the Inspector's. */
  h3 {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--muted);
  }
  h3 code {
    font: 12px var(--mono);
    letter-spacing: 0;
    text-transform: none;
    color: var(--fg);
  }
  code {
    font-family: var(--mono);
  }
  /* A line of muted text where the parts would be: its own padding. */
  .hint {
    margin: 0;
    padding: 8px 0;
    color: var(--muted);
    font-size: 12px;
  }
  table {
    width: 100%;
    table-layout: fixed;
    border-collapse: collapse;
  }
  th {
    padding: 0 4px 4px;
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--muted);
  }
  td {
    min-width: 0;
    padding: 3px 4px;
    vertical-align: middle;
  }
  th:first-child {
    width: 30%;
  }
  th:last-child,
  td:last-child {
    width: 28px;
  }
  tr.hit td {
    background: var(--sel);
  }
  tr.hit td:first-child {
    box-shadow: inset 3px 0 0 var(--accent);
  }
  .add-row {
    align-self: flex-start;
    height: 24px;
    padding: 0 8px;
    font-size: 12px;
  }
  .kw {
    font-size: 12px;
    color: var(--muted);
  }
  .cell {
    display: flex;
    align-items: center;
    gap: 5px;
    min-width: 0;
  }
  /* Expression cells: the look of an Inspector field (ExprInput). */
  .formula .in {
    flex: 1;
    width: 100%;
    min-width: 56px;
    height: 26px;
    box-sizing: border-box;
    padding: 3px 6px;
    background: var(--bg-code);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 4px;
    font: 12px var(--mono);
  }
  .formula .in:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent);
  }
  .formula .in.invalid {
    border-color: var(--err);
  }
  /* Delete buttons of the rows and chips. */
  .x {
    flex: none;
    display: grid;
    place-items: center;
    width: 26px;
    height: 24px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: none;
    color: var(--muted);
  }
  .x:hover {
    background: var(--hover);
    color: var(--fg);
  }
  /* The open button of a part: opens it as the selection, at the cell's right edge. */
  .open {
    flex: none;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    padding: 0;
    border: 0;
    border-radius: 4px;
    background: none;
    color: var(--muted);
  }
  .open:hover {
    background: var(--hover);
    color: var(--fg);
  }
  /* The live value of a part: a small muted pill after its cell. */
  .lv {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex: none;
    padding: 1px 5px;
    border-radius: 999px;
    background: var(--bg-bar);
    color: var(--muted);
    font: 11px var(--mono);
    letter-spacing: 0;
    text-transform: none;
    white-space: nowrap;
  }
  .sw {
    display: inline-block;
    flex: none;
    width: 12px;
    height: 12px;
    border: 1px solid var(--line);
    border-radius: 3px;
    vertical-align: middle;
  }
  .chain {
    display: grid;
    gap: 4px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .chain li {
    display: grid;
    grid-template-columns: 34px minmax(0, 1fr) 34px minmax(0, 1fr);
    align-items: center;
    gap: 6px;
    padding: 4px 8px 4px 5px;
    border-left: 3px solid transparent;
    border-radius: 4px;
  }
  .chain li.else {
    grid-template-columns: 34px minmax(0, 1fr);
  }
  .chain li.hit {
    background: var(--sel);
    border-left-color: var(--accent);
  }
  .list .lrow {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr);
    align-items: center;
    gap: 6px;
    margin-bottom: 8px;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 2px 4px 2px 8px;
    border: 1px solid var(--line);
    border-radius: 999px;
    background: var(--bg-code);
  }
  .chip code {
    font-size: 12px;
  }
  .chips .in.add {
    width: 120px;
    flex: none;
  }
  .one {
    max-width: 100%;
  }
  /* The whole expression: as many rows as its lines, at least 2, then it scrolls. */
  textarea {
    display: block;
    flex: none;
    width: 100%;
    box-sizing: border-box;
    resize: vertical;
    padding: 6px 8px;
    background: var(--bg-code);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 4px;
    font: 12px/1.5 var(--mono);
  }
  textarea:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent);
  }
  footer {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .status-line {
    flex: 1;
    min-width: 0;
  }
  .prob,
  .note {
    margin: 0;
    font-size: 12px;
  }
  .prob {
    color: var(--err);
  }
  .note {
    color: var(--muted);
  }
  /* The primary button of a dialog (DialogHost). */
  .primary {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
    color: var(--on-accent);
    font-weight: 600;
  }
</style>
