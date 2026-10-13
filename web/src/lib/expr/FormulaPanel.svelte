<script lang="ts">
// The formula panel: a drawer at the right edge that shows an expression by
// its parts. A match is a table of key and result rows, a ?: chain a list of
// when and then rows, an `in` test a list of chips; anything else is one
// field with its source. The outline lists the calls and conditions of the
// tree, and the text at the bottom is the whole expression. Both stay in
// step: a cell edit rewrites the text through edit.ts, and it is kept only
// when the result parses. Apply (or closing the panel) hands the text to the
// field; Escape closes it. With the editor's live context the values of
// each part show next to it, for the card on the stage.

import { getContext, onMount, untrack } from "svelte";
import type { ScopeResult } from "../engine";
import { exprCoreReady, formatExpr, type Node, parseExpr } from "./core";
import {
	addChip,
	addMatchRow,
	condChain,
	listView,
	matchView,
	nodeAt,
	outline,
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
	type Core,
	canExtract,
	condChainToMatch,
	extractConst,
	extractFunction,
	freeNames,
	matchToCondChain,
} from "./rewrite";

let {
	text,
	label = "",
	path,
	onapply,
	onclose,
}: {
	/** The field's text when the panel opened. */
	text: string;
	/** The field's label, for the header. */
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
let panel: HTMLElement | undefined = $state();

const parsed = $derived(exprCoreReady() ? parseExpr(draft, false) : null);
const root = $derived(parsed?.root ?? null);
const items = $derived(root ? outline(root, draft) : []);
const sel = $derived(root ? (nodeAt(root, selPath) ?? root) : null);
const selSlot = $derived(sel ? slot(sel, draft) : null);
const mv = $derived(sel ? matchView(sel, draft) : null);
const cc = $derived(sel ? condChain(sel, draft) : null);
const lv = $derived(sel ? listView(sel, draft) : null);
const dirty = $derived(draft !== base);

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

// Evaluate the field on the live card: at once when the panel opens, then
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
/** The extract form: which kind is being named, and the name typed so far. */
let extracting = $state<"const" | "function" | null>(null);
let newName = $state("");

/** The design section and entry the field is in, when it is a constant or function body. */
const home = $derived.by(() => {
	const m = /^\/(consts|functions)\/([^/]+)/.exec(path ?? "");
	return m
		? { key: m[1], name: m[2].replace(/~1/g, "/").replace(/~0/g, "~") }
		: null;
});
const toMatch = $derived(
	sel && cc && cc.rows.length > 1 ? condChainToMatch(core, draft, sel) : null,
);
const toChain = $derived(sel && mv ? matchToCondChain(core, draft, sel) : null);
const canPull = $derived(
	!!live && !!path && !!scope && !!sel && canExtract(sel),
);

function convert(r: { text: string; note?: string } | null) {
	if (take(r ? r.text : null)) {
		selPath = [];
		note = r?.note ? `Converted; ${r.note}.` : "";
	}
}

/** Moves the selected part into a new constant or function of the design. */
function extract() {
	const d = live?.design();
	if (!live || !path || !scope || !sel || !d || !extracting) return;
	const name = newName.trim();
	const locals = scope.locals.map((l) => l.name);
	const before =
		home && home.key === (extracting === "const" ? "consts" : "functions")
			? home.name
			: undefined;
	let r: { text: string; design: Record<string, unknown> } | null;
	if (extracting === "const") {
		if (freeNames(sel, locals).length > 0) {
			note =
				"A constant cannot use repeat names or function arguments; extract a function instead.";
			return;
		}
		r = extractConst(core, draft, sel, name, locals, d, before);
	} else {
		const args = freeNames(sel, locals).map((n) => ({
			name: n,
			type: scope?.locals.find((l) => l.name === n)?.type ?? "",
		}));
		const bad = args.find(
			(a) => !["number", "text", "bool", "color"].includes(a.type),
		);
		if (bad) {
			note = `'${bad.name}' is a ${bad.type || "value"}; function arguments can only be numbers, text, bools or colors.`;
			return;
		}
		r = extractFunction(core, draft, sel, name, locals, args, d, before);
	}
	if (!r) {
		note = `Cannot extract as '${name}': the name is taken or not valid, or the part refers to a layer.`;
		return;
	}
	live.extract(r.design, path, r.text);
	base = r.text;
	draft = r.text;
	bad = {};
	selPath = [];
	extracting = null;
	newName = "";
	note = "";
}

/** Moves the drawer to document.body, so no ancestor's stacking or clipping covers it. */
function portal(node: HTMLElement) {
	document.body.appendChild(node);
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
	if (v === undefined || v === null) return "–";
	if (typeof v === "number") return String(Number(v.toFixed(3)));
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "string") return isHex(v) ? v : `'${v}'`;
	return `[${v.map((x) => fmt(x)).join(", ")}]`;
}

function isHex(v: string): boolean {
	return /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(v);
}

function liveOf(id: number): LiveValue | null {
	return liveTrace?.[id] ?? null;
}

function samePath(a: number[], b: number[]): boolean {
	return a.length === b.length && a.every((x, i) => x === b[i]);
}

function onKey(e: KeyboardEvent) {
	if (e.key === "Escape") {
		e.preventDefault();
		e.stopPropagation();
		// Blurring a cell commits what was typed in it.
		if (document.activeElement instanceof HTMLInputElement)
			document.activeElement.blur();
		close();
	}
}

onMount(() => {
	// Capture, so Escape closes the panel and not the editor under it.
	window.addEventListener("keydown", onKey, true);
	panel?.focus();
	return () => window.removeEventListener("keydown", onKey, true);
});
</script>

{#snippet val(id: number)}
	{#if liveTrace}
		{@const v = liveOf(id)}
		<span class="lv" class:none={v === null}>
			{#if typeof v === "string" && isHex(v)}<span class="sw" style:background={v}></span>{/if}{fmt(v)}
		</span>
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
	</span>
{/snippet}

<div
	class="formula"
	role="dialog"
	use:portal
	bind:this={panel}
	tabindex="-1"
	aria-label="Formula panel">
	<header>
		<h2 title={label}>{label || "Formula"}</h2>
		{#if live && live.card()}
			<span class="card">values for: {live.card()}</span>
		{/if}
		<button class="close" onclick={close} aria-label="Close formula panel" title="Close (Escape)">×</button>
	</header>

	<div class="split">
		<nav class="outline" aria-label="Outline">
			{#each items as it}
				<button
					class="ol"
					class:on={samePath(it.path, sel ? selPath : [])}
					style:padding-left="{8 + it.depth * 12}px"
					onclick={() => (selPath = it.path)}>
					<b>{it.label}</b> <span>{it.text}</span>
				</button>
			{:else}
				<p class="empty">Nothing to outline.</p>
			{/each}
		</nav>

		<div class="main">
			{#if hits === 0}
				<p class="nohit">not evaluated for this card</p>
			{/if}
			{#if toMatch || toChain || canPull}
				<div class="actions">
					{#if toMatch}<button class="btn" onclick={() => convert(toMatch)}>Convert to match</button>{/if}
					{#if toChain}<button class="btn" onclick={() => convert(toChain)}>Convert to ?: chain</button>{/if}
					{#if canPull}
						<button class="btn" class:on={extracting === "const"} onclick={() => (extracting = extracting === "const" ? null : "const")}>Extract constant</button>
						{#if home?.key !== "consts"}
							<button class="btn" class:on={extracting === "function"} onclick={() => (extracting = extracting === "function" ? null : "function")}>Extract function</button>
						{/if}
					{/if}
				</div>
				{#if extracting}
					<form class="actions" onsubmit={(e) => { e.preventDefault(); extract(); }}>
						<input class="in" aria-label="New {extracting} name" placeholder="{extracting} name" spellcheck="false" bind:value={newName} />
						<button class="btn primary" type="submit" disabled={!newName.trim()}>Extract</button>
					</form>
				{/if}
			{/if}

			{#if !root}
				<p class="empty">The expression does not parse yet.</p>
			{:else if mv && sel}
				<h3>match on <code>{mv.subject.text}</code> {#if liveTrace}{@render val(mv.subject.id)}{/if}</h3>
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
				<button class="btn" onclick={() => take(addMatchRow(draft, sel, formatExpr))}>+ row</button>
			{:else if cc && cc.rows.length > 1}
				<ol class="chain">
					{#each cc.rows as r, i}
						<li class:hit={taken.row === i}>
							<span class="kw">when</span>
							{@render cell(r.when, `when ${i + 1}`)}
							<span class="kw">→</span>
							{@render cell(r.result, `then ${i + 1}`)}
						</li>
					{/each}
					<li class:hit={taken.fallback}>
						<span class="kw">else</span>
						{@render cell(cc.fallback, "else")}
					</li>
				</ol>
			{:else if cc && cc.rows[0]}
				<div class="card-cond">
					<div class:hit={taken.row === 0}>
						<span class="kw">when</span>
						{@render cell(cc.rows[0].when, "when")}
					</div>
					<div class:hit={taken.row === 0}>
						<span class="kw">then</span>
						{@render cell(cc.rows[0].result, "then")}
					</div>
					<div class:hit={taken.fallback}>
						<span class="kw">else</span>
						{@render cell(cc.fallback, "else")}
					</div>
				</div>
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
			{:else if selSlot}
				<div class="one">
					{@render cell(selSlot, "expression")}
				</div>
			{/if}
		</div>
	</div>

	<section class="text">
		<textarea
			aria-label="Expression text"
			spellcheck="false"
			value={draft}
			oninput={(e) => setText(e.currentTarget.value)}
			onkeydown={(e) => {
				if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
					e.preventDefault();
					apply();
				}
			}}></textarea>
		{#if parsed && parsed.problems.length}
			<p class="prob">{parsed.problems[0].message}</p>
		{/if}
		<footer>
			<span class="note">{note}</span>
			<button class="btn primary" disabled={!dirty} onclick={apply}>Apply</button>
		</footer>
	</section>
</div>

<style>
  .formula {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    z-index: 800;
    width: min(560px, 90vw);
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    color: var(--fg);
    border-left: 1px solid var(--line);
    box-shadow: -8px 0 24px rgb(0 0 0 / 0.16);
    font: 13px/1.4 system-ui, -apple-system, 'Segoe UI', sans-serif;
    outline: none;
  }
  header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 8px 8px 14px;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--line);
  }
  h2 {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .card {
    flex: 1;
    min-width: 0;
    color: var(--muted);
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  header .card:only-of-type {
    margin-left: auto;
  }
  .close {
    margin-left: auto;
    width: 28px;
    height: 28px;
    border: none;
    border-radius: 4px;
    background: none;
    color: var(--muted);
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
  }
  .close:hover {
    background: var(--hover);
    color: var(--fg);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 10px;
  }
  .actions .in {
    flex: 1;
    min-width: 120px;
  }
  .btn.on {
    border-color: var(--accent);
  }
  .split {
    flex: 1;
    min-height: 0;
    display: flex;
  }
  .outline {
    flex: none;
    width: 180px;
    overflow: auto;
    border-right: 1px solid var(--line);
    background: var(--bg-code);
    padding: 6px 0;
  }
  .ol {
    display: block;
    width: 100%;
    box-sizing: border-box;
    padding: 3px 8px;
    border: none;
    background: none;
    color: var(--fg);
    text-align: left;
    font: 12px/1.4 var(--mono);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    cursor: pointer;
  }
  .ol span {
    color: var(--muted);
  }
  .ol:hover {
    background: var(--hover);
  }
  .ol.on {
    background: var(--sel);
  }
  .main {
    flex: 1;
    min-width: 0;
    overflow: auto;
    padding: 10px 14px;
  }
  .main h3 {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0 0 8px;
    font-size: 13px;
    font-weight: 600;
  }
  .main code {
    font-family: var(--mono);
    font-weight: 400;
  }
  .empty,
  .nohit {
    margin: 0 0 8px;
    color: var(--muted);
  }
  table {
    width: 100%;
    table-layout: fixed;
    border-collapse: collapse;
    margin-bottom: 8px;
  }
  th {
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    color: var(--muted);
    padding: 0 4px 4px;
  }
  td {
    min-width: 0;
    padding: 3px 4px;
    vertical-align: middle;
  }
  td:last-child {
    width: 28px;
  }
  td > .cell {
    width: 100%;
  }
  tr.hit {
    box-shadow: inset 3px 0 0 var(--accent);
  }
  .kw {
    font-size: 11px;
    color: var(--muted);
    font-family: var(--mono);
  }
  .cell {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .in {
    flex: 1;
    width: 100%;
    min-width: 0;
    box-sizing: border-box;
    padding: 4px 6px;
    background: var(--bg-code);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 3px;
    font: 12px var(--mono);
  }
  .in:focus {
    outline: none;
    border-color: var(--accent);
  }
  .in.invalid {
    border-color: var(--err);
  }
  .lv {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex: none;
    font: 11px var(--mono);
    color: var(--fg);
    white-space: nowrap;
  }
  .lv.none {
    color: var(--muted);
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
  .x {
    width: 24px;
    height: 24px;
    border: none;
    border-radius: 4px;
    background: none;
    color: var(--muted);
    font-size: 15px;
    cursor: pointer;
  }
  .x:hover {
    background: var(--hover);
    color: var(--err);
  }
  .btn {
    padding: 4px 10px;
    border: 1px solid var(--line);
    border-radius: 4px;
    background: var(--bg-bar);
    color: var(--fg);
    font: inherit;
    cursor: pointer;
  }
  .btn:hover:not(:disabled) {
    border-color: var(--accent);
  }
  .btn:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .btn.primary {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--on-accent);
  }
  .chain {
    margin: 0 0 8px;
    padding: 0;
    list-style: none;
  }
  .chain li {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 6px;
    padding: 4px 6px;
    border-radius: 4px;
  }
  .chain li.hit {
    box-shadow: inset 3px 0 0 var(--accent);
    background: var(--hover);
  }
  .chain li > .kw {
    flex: none;
    width: 40px;
  }
  .card-cond {
    display: grid;
    gap: 6px;
  }
  .card-cond > div {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    border: 1px solid var(--line);
    border-radius: 6px;
    background: var(--bg-code);
  }
  .card-cond > div.hit {
    box-shadow: inset 3px 0 0 var(--accent);
  }
  .card-cond > div > .kw {
    flex: none;
    width: 40px;
  }
  .list .lrow {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 8px;
  }
  .list .lrow > .kw {
    flex: none;
    width: 40px;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
    align-items: center;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 2px 4px 2px 8px;
    border: 1px solid var(--line);
    border-radius: 12px;
    background: var(--bg-code);
  }
  .chip code {
    font-family: var(--mono);
    font-size: 12px;
  }
  .chips .in.add {
    width: 120px;
    flex: none;
  }
  .one {
    max-width: 100%;
  }
  .text {
    flex: none;
    padding: 8px 14px 10px;
    border-top: 1px solid var(--line);
    background: var(--bg-bar);
  }
  textarea {
    display: block;
    width: 100%;
    height: 110px;
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
  }
  .prob {
    margin: 4px 0 0;
    font-size: 12px;
    color: var(--err);
  }
  footer {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 8px;
  }
  .note {
    flex: 1;
    min-width: 0;
    font-size: 12px;
    color: var(--muted);
  }
</style>
