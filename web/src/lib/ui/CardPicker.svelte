<script lang="ts">
// "Card 3 of 120" with previous/next buttons and a searchable list.
import type { CardInfo, Param } from "../engine";
import CardList from "./CardList.svelte";
import { placeNear } from "./overlay.svelte";

let {
	cards,
	index,
	onpick,
	disabled = false,
	params = [],
	onbrowse = undefined,
}: {
	cards: CardInfo[];
	index: number;
	onpick: (i: number) => void;
	disabled?: boolean;
	params?: Param[];
	onbrowse?: () => void;
} = $props();

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

<div class="picker" class:open role="group" aria-label="Card shown in the preview">
  <button class="step" title="Previous card" disabled={disabled || index <= 0} onclick={() => onpick(index - 1)}>‹</button>
  <button bind:this={button} class="current" {disabled} aria-haspopup="listbox" aria-expanded={open} title="Choose the card to preview" onclick={() => (open ? (open = false) : show())}>
    <span class="cap">Card</span>
    <span class="of">{cards.length ? `${index + 1} / ${cards.length}` : 'no cards'}</span>
    <span class="id">{current?.id ?? '—'}</span>
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
  /* One joined control: previous | card ▾ | next. */
  .picker {
    display: inline-flex;
    align-items: stretch;
    height: var(--ctl-h);
    box-sizing: border-box;
    border: 1px solid var(--line);
    border-radius: 6px;
    background: var(--bg);
    overflow: hidden;
    transition: border-color 0.12s;
  }
  .picker:hover {
    border-color: color-mix(in srgb, var(--fg) 28%, var(--line));
  }
  .picker.open {
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent);
  }
  .picker > button {
    border: 0;
    border-radius: 0;
    background: none;
    display: inline-flex;
    align-items: center;
  }
  .picker > button:hover:not(:disabled) {
    background: var(--hover);
  }
  .step {
    width: 26px;
    justify-content: center;
    padding: 0;
    font-size: 15px;
    color: var(--muted);
  }
  .picker > .current {
    gap: 8px;
    min-width: 150px;
    padding: 0 10px;
    border-left: 1px solid var(--line);
    border-right: 1px solid var(--line);
  }
  .cap {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    padding-right: 8px;
    border-right: 1px solid var(--line);
    align-self: stretch;
    display: flex;
    align-items: center;
    flex: none;
  }
  /* Position sits right after the caption and never shrinks out of view;
     the card name takes the remaining room and truncates. */
  .of {
    flex: none;
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }
  .id {
    flex: 1 1 auto;
    min-width: 0;
    max-width: 140px;
    font-family: var(--mono);
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  svg {
    flex: none;
    width: 10px;
    height: 6px;
    margin-left: auto;
    color: var(--muted);
    transition: transform 0.15s;
  }
  .open svg {
    transform: rotate(180deg);
    color: var(--accent);
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
    box-shadow: var(--shadow-pop);
    overflow: hidden;
  }
</style>
