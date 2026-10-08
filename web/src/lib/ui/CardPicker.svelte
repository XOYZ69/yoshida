<script lang="ts">
  // "Card 3 of 120" with previous/next buttons and a searchable list.
  import type { CardInfo, Param } from '../engine';
  import CardList from './CardList.svelte';
  import { placeNear } from './overlay.svelte';

  let {
    cards,
    index,
    onpick,
    disabled = false,
    params = [],
    onbrowse = undefined,
  }: { cards: CardInfo[]; index: number; onpick: (i: number) => void; disabled?: boolean; params?: Param[]; onbrowse?: () => void } = $props();

  let open = $state(false);
  let button: HTMLButtonElement | undefined = $state();
  let pop: HTMLDivElement | undefined = $state();
  let pos = $state({ left: 0, top: 0 });

  const current = $derived(cards[index]);

  function show() {
    if (!button) return;
    const p = placeNear(button.getBoundingClientRect(), 360, 380);
    pos = { left: p.left, top: p.top };
    open = true;
  }

  function pick(i: number) {
    open = false;
    if (i !== index) onpick(i);
    button?.focus();
  }
</script>

<svelte:window
  onpointerdowncapture={(e) => {
    if (open && !pop?.contains(e.target as Node) && !button?.contains(e.target as Node)) open = false;
  }} />

<div class="picker" role="group" aria-label="Card shown in the preview">
  <span class="cap">Card</span>
  <button class="step" title="Previous card" disabled={disabled || index <= 0} onclick={() => onpick(index - 1)}>‹</button>
  <button bind:this={button} class="current" {disabled} aria-haspopup="listbox" aria-expanded={open} title="Choose the card to preview" onclick={() => (open ? (open = false) : show())}>
    <span class="id">{current?.id ?? '—'}</span>
    <span class="of">{cards.length ? `${index + 1} / ${cards.length}` : 'no cards'}</span>
    <svg viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.5" /></svg>
  </button>
  <button class="step" title="Next card" disabled={disabled || index >= cards.length - 1} onclick={() => onpick(index + 1)}>›</button>
</div>

{#if open}
  <div bind:this={pop} class="pop" style:left="{pos.left}px" style:top="{pos.top}px">
    <div class="list" style:height="{Math.min(360, Math.max(80, cards.length * 34 + 48))}px">
      <CardList {cards} {params} {index} height={0} onpick={pick} autofocus onclose={() => (open = false)} />
    </div>
    {#if onbrowse}
      <button class="browse" onclick={() => ((open = false), onbrowse?.())}>⤢ Browse all cards…</button>
    {/if}
  </div>
{/if}

<style>
  .picker {
    display: inline-flex;
    align-items: center;
    gap: 2px;
  }
  .cap {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
    margin-right: 4px;
  }
  .step {
    padding: 3px 8px;
  }
  .current {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-width: 120px;
    background: var(--bg-code);
  }
  .id {
    font-family: var(--mono);
    font-size: 12px;
    max-width: 140px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .of {
    flex: 1;
    text-align: right;
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  svg {
    width: 10px;
    height: 6px;
    color: var(--muted);
  }
  .list {
    min-height: 80px;
    display: flex;
    flex-direction: column;
  }
  .browse {
    width: 100%;
    border: 0;
    border-top: 1px solid var(--line);
    border-radius: 0;
    background: var(--bg-bar);
    font-size: 12px;
    padding: 6px;
  }
  /* The corner grip resizes the list (CSS resize, themed by the browser). */
  .pop {
    resize: both;
    min-width: 260px;
    min-height: 140px;
    max-width: calc(100vw - 16px);
    max-height: calc(100vh - 16px);
    display: flex;
    flex-direction: column;
    position: fixed;
    z-index: 950;
    width: 360px;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25);
    overflow: hidden;
  }
</style>
