<script lang="ts">
// Every card of a set, as a table (one column per param, sortable) or as
// a grid of small renders. Only the rows or tiles in view are drawn, and
// thumbnails are rendered on demand for the tiles in view.

import { cardLabel, nameParam } from "../cards";
import type { CardInfo, Param } from "../engine";
import { loadPref, savePref } from "./drag";
import { type MenuItem, openMenu } from "./overlay.svelte";

let {
	cards,
	params,
	index,
	canRender,
	thumb,
	onpick,
}: {
	cards: CardInfo[];
	params: Param[];
	index: number;
	/** False while the design has errors: the grid shows names only. */
	canRender: boolean;
	/** A rendered card as an image URL (cached by the caller). */
	thumb: (i: number) => Promise<string | null>;
	onpick: (i: number) => void;
} = $props();

const prefKey = "yoshida.cardBrowser";
const pref = loadPref(prefKey, {
	view: "table" as "table" | "grid",
	hidden: [] as string[],
	tile: 150,
});
let view = $state(pref.view);
let hidden = $state(new Set(pref.hidden));
let tile = $state(pref.tile);
let query = $state("");
let sortBy: string | null = $state(null);
let sortDir = $state(1);

function remember() {
	savePref(prefKey, { view, hidden: [...hidden], tile });
}

const named = $derived(nameParam(params));
const columns = $derived(params.filter((p) => !hidden.has(p.name)));

function cell(c: CardInfo, p: Param): string {
	const v = c.values[p.name];
	if (v === undefined) return "";
	if (Array.isArray(v)) return `${v.length} item${v.length === 1 ? "" : "s"}`;
	if (typeof v === "object" && v) return JSON.stringify(v);
	return String(v);
}

const rows = $derived.by(() => {
	const q = query.trim().toLowerCase();
	let out = cards.map((c, i) => ({ c, i, label: cardLabel(c, params, named) }));
	if (q)
		out = out.filter((r) =>
			`${r.c.id} ${Object.values(r.c.values)
				.map((v) => (typeof v === "object" ? JSON.stringify(v) : String(v)))
				.join(" ")}`
				.toLowerCase()
				.includes(q),
		);
	if (sortBy) {
		const key = sortBy;
		const val = (r: (typeof out)[number]) =>
			key === "#" ? r.i : key === "id" ? r.c.id : r.c.values[key];
		out = [...out].sort((a, b) => {
			const x = val(a);
			const y = val(b);
			if (x === undefined) return 1;
			if (y === undefined) return -1;
			const n =
				typeof x === "number" && typeof y === "number"
					? x - y
					: String(x).localeCompare(String(y), undefined, { numeric: true });
			return n * sortDir;
		});
	}
	return out;
});

function sort(key: string) {
	if (sortBy === key) {
		if (sortDir === 1) sortDir = -1;
		else sortBy = null;
	} else {
		sortBy = key;
		sortDir = 1;
	}
}

function columnMenu(e: MouseEvent) {
	const items: MenuItem[] = [{ heading: "Columns" }];
	for (const p of params)
		items.push({
			label: p.label ?? p.name,
			icon: hidden.has(p.name) ? "" : "✓",
			detail: p.type,
			action: () => {
				const next = new Set(hidden);
				if (!next.delete(p.name)) next.add(p.name);
				hidden = next;
				remember();
			},
		});
	const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
	openMenu(r.left, r.bottom + 4, items);
}

// ---------------------------------------------------------------- virtual scrolling

let scroller: HTMLDivElement | undefined = $state();
let scrollTop = $state(0);
let viewW = $state(600);
let viewH = $state(400);

$effect(() => {
	if (!scroller) return;
	const ro = new ResizeObserver(() => {
		viewW = scroller!.clientWidth;
		viewH = scroller!.clientHeight;
	});
	ro.observe(scroller);
	return () => ro.disconnect();
});

const rowH = 30;
/** The table scrolls sideways when the columns do not fit. */
const tableW = $derived(20 + 48 + 120 + columns.length * 88 + 8);
const tableFirst = $derived(Math.max(0, Math.floor(scrollTop / rowH) - 5));
const tableLast = $derived(
	Math.min(rows.length, Math.ceil((scrollTop + viewH) / rowH) + 5),
);

const gap = 10;
const perRow = $derived(Math.max(1, Math.floor((viewW - gap) / (tile + gap))));
const tileH = $derived(Math.round(tile * 1.4) + 34);
const gridRows = $derived(Math.ceil(rows.length / perRow));
const gridFirst = $derived(
	Math.max(0, Math.floor(scrollTop / (tileH + gap)) - 1),
);
const gridLast = $derived(
	Math.min(gridRows, Math.ceil((scrollTop + viewH) / (tileH + gap)) + 1),
);
const tiles = $derived(
	rows
		.slice(gridFirst * perRow, gridLast * perRow)
		.map((r, k) => ({ ...r, at: gridFirst * perRow + k })),
);

// Thumbnails for the tiles in view.
let urls = $state(new Map<number, string | null>());
let asked = new Set<number>();
$effect(() => {
	// Card data or design changed: start over.
	void cards;
	void canRender;
	urls = new Map();
	asked = new Set();
});
$effect(() => {
	if (view !== "grid" || !canRender) return;
	for (const t of tiles) {
		if (asked.has(t.i)) continue;
		asked.add(t.i);
		const want = cards;
		thumb(t.i).then((u) => {
			if (want !== cards) return;
			urls = new Map(urls).set(t.i, u);
		});
	}
});

// Keep the current card in view when the window opens.
$effect(() => {
	if (!scroller) return;
	const at = rows.findIndex((r) => r.i === index);
	if (at < 0) return;
	requestAnimationFrame(() => {
		if (!scroller) return;
		const top =
			view === "table" ? at * rowH : Math.floor(at / perRow) * (tileH + gap);
		if (
			top < scroller.scrollTop ||
			top > scroller.scrollTop + scroller.clientHeight - rowH
		)
			scroller.scrollTop = Math.max(0, top - scroller.clientHeight / 3);
	});
});
</script>

<div class="browser">
  <div class="bar">
    <input type="search" placeholder="Search {cards.length} cards…" bind:value={query} aria-label="Search cards" />
    {#if query}<span class="muted">{rows.length} shown</span>{/if}
    <span class="spacer"></span>
    {#if view === 'table'}
      <button onclick={columnMenu} title="Choose the columns">Columns ▾</button>
    {:else}
      <label class="zoom" title="Tile size">
        <span class="muted">Size</span>
        <input type="range" min="90" max="320" step="10" bind:value={tile} onchange={remember} />
      </label>
    {/if}
    <div class="seg" role="tablist">
      <button role="tab" aria-selected={view === 'table'} class:active={view === 'table'} onclick={() => ((view = 'table'), remember())}>Table</button>
      <button role="tab" aria-selected={view === 'grid'} class:active={view === 'grid'} onclick={() => ((view = 'grid'), remember())}>Grid</button>
    </div>
  </div>

  <div class="scroll" bind:this={scroller} onscroll={() => (scrollTop = scroller!.scrollTop)}>
    {#if view === 'table'}
      <div class="thead" style:min-width="{tableW}px" style:grid-template-columns="48px minmax(120px, 1.2fr) {columns.map(() => 'minmax(80px, 1fr)').join(' ')}">
        <button onclick={() => sort('#')}>#{sortBy === '#' ? (sortDir > 0 ? ' ▲' : ' ▼') : ''}</button>
        <button onclick={() => sort('id')}>id{sortBy === 'id' ? (sortDir > 0 ? ' ▲' : ' ▼') : ''}</button>
        {#each columns as p (p.name)}
          <button onclick={() => sort(p.name)} title={p.note ?? p.name}>{p.label ?? p.name}{sortBy === p.name ? (sortDir > 0 ? ' ▲' : ' ▼') : ''}</button>
        {/each}
      </div>
    {/if}
    {#if view === 'table'}
      <div class="space" style:height="{rows.length * rowH}px" style:min-width="{tableW}px">
        {#each rows.slice(tableFirst, tableLast) as r, k (r.i)}
          <button
            class="tr"
            class:current={r.i === index}
            style:top="{(tableFirst + k) * rowH}px"
            style:grid-template-columns="48px minmax(120px, 1.2fr) {columns.map(() => 'minmax(80px, 1fr)').join(' ')}"
            ondblclick={() => onpick(r.i)}
            onclick={() => onpick(r.i)}>
            <span class="num">{r.i + 1}</span>
            <span class="mono">{r.c.id}</span>
            {#each columns as p (p.name)}
              <span class:muted={r.c.values[p.name] === undefined} class:name={p.name === named}>{cell(r.c, p) || (p.default !== undefined && typeof p.default !== 'object' ? String(p.default) : '')}</span>
            {/each}
          </button>
        {/each}
      </div>
    {:else}
      <div class="space" style:height="{gridRows * (tileH + gap) + gap}px">
        {#each tiles as t (t.i)}
          {@const col = t.at % perRow}
          {@const row = Math.floor(t.at / perRow)}
          <button
            class="tile"
            class:current={t.i === index}
            style:left="{gap + col * (tile + gap)}px"
            style:top="{gap + row * (tileH + gap)}px"
            style:width="{tile}px"
            style:height="{tileH}px"
            title="{t.label.name || t.c.id} ({t.c.id})"
            onclick={() => onpick(t.i)}>
            <span class="pic">
              {#if urls.get(t.i)}
                <img src={urls.get(t.i)} alt={t.label.name || t.c.id} />
              {:else if !canRender}
                <span class="muted small">Fix the errors to see previews</span>
              {:else if urls.has(t.i)}
                <span class="muted small">Could not render</span>
              {:else}
                <span class="spinner" aria-label="Rendering"></span>
              {/if}
            </span>
            <span class="cap"><b>{t.label.name || t.c.id}</b><span class="mono muted">{t.i + 1} · {t.c.id}</span></span>
          </button>
        {/each}
      </div>
    {/if}
    {#if !rows.length}<p class="empty">{query ? `No card matches “${query}”.` : 'This set has no cards yet.'}</p>{/if}
  </div>
</div>

<style>
  .browser {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 10px;
    border-bottom: 1px solid var(--line);
  }
  .bar input[type='search'] {
    width: 220px;
    max-width: 40%;
  }
  .spacer {
    flex: 1;
  }
  .seg {
    display: flex;
    border: 1px solid var(--line);
    border-radius: 7px;
    overflow: hidden;
  }
  .seg button {
    border: 0;
    border-radius: 0;
  }
  .seg button.active {
    background: var(--accent-strong);
    color: var(--on-accent);
  }
  .zoom {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
  }
  .thead {
    position: sticky;
    top: 0;
    z-index: 1;
    display: grid;
    gap: 0 8px;
    padding: 0 10px;
    border-bottom: 1px solid var(--line);
    background: var(--bg-bar);
  }
  .thead button {
    all: unset;
    padding: 6px 0;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--muted);
    cursor: pointer;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow: auto;
    position: relative;
  }
  .space {
    position: relative;
  }
  .tr {
    all: unset;
    box-sizing: border-box;
    position: absolute;
    left: 0;
    right: 0;
    height: 30px;
    display: grid;
    gap: 0 8px;
    align-items: center;
    padding: 0 10px;
    font-size: 13px;
    border-bottom: 1px solid var(--line);
    cursor: pointer;
  }
  .tr > span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .tr:hover {
    background: var(--hover);
  }
  .tr.current {
    background: var(--sel);
  }
  .num {
    color: var(--muted);
    font-size: 11px;
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .name {
    font-weight: 600;
  }
  .mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .muted {
    color: var(--muted);
  }
  .small {
    font-size: 11px;
    text-align: center;
    padding: 8px;
  }
  .tile {
    all: unset;
    box-sizing: border-box;
    position: absolute;
    display: flex;
    flex-direction: column;
    border: 1px solid var(--line);
    border-radius: 8px;
    overflow: hidden;
    cursor: pointer;
    background: var(--bg-code);
  }
  .tile:hover {
    border-color: var(--accent);
  }
  .tile.current {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }
  .pic {
    flex: 1;
    min-height: 0;
    display: grid;
    place-items: center;
    padding: 6px;
  }
  .pic img {
    max-width: 100%;
    max-height: 100%;
    object-fit: contain;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.25);
  }
  .cap {
    display: flex;
    flex-direction: column;
    padding: 4px 8px 6px;
    font-size: 12px;
    border-top: 1px solid var(--line);
    background: var(--bg);
    line-height: 1.25;
  }
  .cap b,
  .cap span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .cap .mono {
    font-size: 10px;
  }
  .spinner {
    width: 18px;
    height: 18px;
    border: 2px solid var(--line);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  .empty {
    text-align: center;
    color: var(--muted);
    font-size: 13px;
  }
</style>
