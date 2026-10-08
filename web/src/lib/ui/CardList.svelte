<script lang="ts">
  // Searchable card list that stays fast with thousands of cards: only the
  // rows in view are drawn.
  import type { CardInfo, Param } from '../engine';
  import { cardLabel, nameParam } from '../cards';

  let {
    cards,
    index,
    onpick,
    height = 320,
    autofocus = false,
    onclose = undefined,
    params = [],
  }: {
    cards: CardInfo[];
    /** The design's params, to show each card's name. */
    params?: Param[];
    index: number;
    onpick: (i: number) => void;
    /** Height of the scrolling area in px; 0 fills the parent. */
    height?: number;
    autofocus?: boolean;
    onclose?: () => void;
  } = $props();

  const row = 34;
  let query = $state('');
  let scroller: HTMLDivElement | undefined = $state();
  let search: HTMLInputElement | undefined = $state();
  let scrollTop = $state(0);
  let viewH = $state(320);
  let active = $state(0);

  const named = $derived(nameParam(params));
  const items = $derived(cards.map((c, i) => ({ i, id: c.id, ...cardLabel(c, params, named), hay: `${c.id} ${Object.values(c.values).map((v) => (typeof v === 'object' ? JSON.stringify(v) : String(v))).join(' ')}`.toLowerCase() })));
  const shown = $derived.by(() => {
    const q = query.trim().toLowerCase();
    return q ? items.filter((x) => x.hay.includes(q)) : items;
  });
  const first = $derived(Math.max(0, Math.floor(scrollTop / row) - 4));
  const last = $derived(Math.min(shown.length, Math.ceil((scrollTop + viewH) / row) + 4));

  $effect(() => {
    if (!scroller) return;
    const ro = new ResizeObserver(() => (viewH = scroller!.clientHeight));
    ro.observe(scroller);
    return () => ro.disconnect();
  });

  // Keep the current card in view when the list opens or the card changes.
  $effect(() => {
    const at = shown.findIndex((x) => x.i === index);
    active = Math.max(0, at);
    if (!scroller || at < 0) return;
    const top = at * row;
    if (top < scroller.scrollTop || top + row > scroller.scrollTop + scroller.clientHeight) scroller.scrollTop = Math.max(0, top - scroller.clientHeight / 2);
  });

  $effect(() => {
    if (autofocus) requestAnimationFrame(() => search?.focus());
  });

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (!shown.length) return;
      active = Math.max(0, Math.min(shown.length - 1, active + (e.key === 'ArrowDown' ? 1 : -1)));
      const top = active * row;
      if (scroller && (top < scroller.scrollTop || top + row > scroller.scrollTop + scroller.clientHeight)) scroller.scrollTop = top - scroller.clientHeight / 2;
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (shown[active]) onpick(shown[active].i);
    } else if (e.key === 'Escape' && onclose) {
      e.preventDefault();
      e.stopPropagation();
      onclose();
    }
  }
</script>

<div class="cards" style:height={height ? `${height + 40}px` : '100%'}>
  <div class="bar">
    <input bind:this={search} type="search" placeholder="Search {cards.length} card{cards.length === 1 ? '' : 's'}…" bind:value={query} {onkeydown} aria-label="Search cards" />
    {#if query}<span class="count">{shown.length}</span>{/if}
  </div>
  <div class="scroll" bind:this={scroller} onscroll={() => (scrollTop = scroller!.scrollTop)} role="listbox" aria-label="Cards" tabindex="-1" {onkeydown}>
    <div style:height="{shown.length * row}px" class="spacer">
      {#each shown.slice(first, last) as x, k (x.i)}
        <button
          class="row"
          role="option"
          aria-selected={x.i === index}
          class:current={x.i === index}
          class:active={first + k === active}
          style:top="{(first + k) * row}px"
          onclick={() => onpick(x.i)}>
          <span class="num">{x.i + 1}</span>
          <span class="main">
            <span class="name" class:mono={!x.name}>{x.name || x.id}</span>
            {#if x.name}<span class="id">{x.id}</span>{/if}
          </span>
          {#if x.detail}<span class="sum">{x.detail}</span>{/if}
        </button>
      {/each}
    </div>
    {#if !shown.length}<p class="empty">No card matches “{query}”.</p>{/if}
  </div>
</div>

<style>
  .cards {
    display: flex;
    flex-direction: column;
    min-height: 0;
    container-type: inline-size;
  }
  /* Narrow lists show the name and id only. */
  @container (max-width: 300px) {
    .sum {
      display: none;
    }
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px;
  }
  .bar input {
    flex: 1;
  }
  .count {
    font-size: 11px;
    color: var(--muted);
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow: auto;
    outline: none;
    position: relative;
  }
  .spacer {
    position: relative;
  }
  .row {
    all: unset;
    box-sizing: border-box;
    position: absolute;
    left: 4px;
    right: 4px;
    height: 32px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 8px;
    border-radius: 5px;
    cursor: pointer;
    font-size: 13px;
  }
  .row.active {
    background: var(--hover);
  }
  .row.current {
    background: var(--sel);
  }
  .num {
    width: 32px;
    flex: none;
    text-align: right;
    color: var(--muted);
    font-size: 11px;
    font-variant-numeric: tabular-nums;
  }
  .main {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1 1 50%;
    line-height: 1.15;
  }
  .name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .id {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .sum {
    flex: 1 1 50%;
    font-size: 12px;
    min-width: 0;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .empty {
    color: var(--muted);
    font-size: 12px;
    text-align: center;
  }
</style>
