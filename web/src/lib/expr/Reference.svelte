<script lang="ts">
  // Reference popover of an expression input: everything that can be used
  // in this field, grouped, with types and docs. Clicking an entry inserts it
  // at the caret. Lives in document.body with fixed position so the
  // inspector's scroll container does not clip it. Closes on Escape and on
  // a click outside.
  import { onMount } from 'svelte';
  import type { CompletionContext } from '../builder/complete';
  import { BUILTINS, CHEATSHEET, FUNCTIONS, TEMPLATE_HELP, fit, fnSignature, typeLabel, valueType, type Expect } from './catalog';

  let {
    ctx,
    expect = 'any',
    template = false,
    anchor,
    ignore,
    oninsert,
    onclose,
  }: {
    ctx: CompletionContext;
    expect?: Expect;
    template?: boolean;
    /** The rect to place the popover next to (re-read on scroll and resize). */
    anchor: () => DOMRect | null;
    /** Clicks on this element do not count as outside (the toggle button). */
    ignore?: HTMLElement;
    oninsert: (text: string, reopen: boolean) => void;
    onclose: () => void;
  } = $props();

  let pop: HTMLDivElement | undefined = $state();
  let pos = $state({ left: 0, top: 0, maxHeight: 400, above: false });
  const width = 360;

  function place() {
    const r = anchor();
    if (!r) return onclose();
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const left = Math.max(8, Math.min(r.right - width, vw - width - 8));
    const below = vh - r.bottom - 12;
    const aboveSpace = r.top - 12;
    const above = below < 260 && aboveSpace > below;
    const maxHeight = Math.max(160, Math.min(460, above ? aboveSpace : below));
    pos = { left, top: above ? r.top - 4 : r.bottom + 4, maxHeight, above };
  }

  function portal(node: HTMLElement) {
    document.body.appendChild(node);
    return { destroy: () => node.remove() };
  }

  onMount(() => {
    place();
    const down = (e: PointerEvent) => {
      const t = e.target as Node;
      if (pop?.contains(t) || ignore?.contains(t)) return;
      onclose();
    };
    const key = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.preventDefault();
      e.stopPropagation();
      onclose();
    };
    const move = () => place();
    window.addEventListener('pointerdown', down, true);
    window.addEventListener('keydown', key, true);
    window.addEventListener('resize', move);
    window.addEventListener('scroll', move, true);
    return () => {
      window.removeEventListener('pointerdown', down, true);
      window.removeEventListener('keydown', key, true);
      window.removeEventListener('resize', move);
      window.removeEventListener('scroll', move, true);
    };
  });

  const dim = (type: string) => fit(type, expect) === 0;
  const needs = $derived(expect && expect !== 'any' ? expect : '');
  const params = $derived([...ctx.params].sort((a, b) => fit(b.type, expect) - fit(a.type, expect)));
  const fns = $derived([...FUNCTIONS].sort((a, b) => fit(b.ret, expect) - fit(a.ret, expect)));

  /** Keeps the focus (and caret) in the editor when an entry is clicked. */
  function keep(e: MouseEvent) {
    e.preventDefault();
  }
</script>

<div
  bind:this={pop}
  use:portal
  class="ref"
  role="dialog"
  aria-label="Expression reference"
  style:left="{pos.left}px"
  style:top="{pos.top}px"
  style:max-height="{pos.maxHeight}px"
  style:width="{width}px"
  class:above={pos.above}>
  <header>
    <span class="title">Expression reference</span>
    {#if needs}<span class="needs">needs <b>{needs}</b></span>{/if}
    <button class="close" title="Close (Esc)" aria-label="Close" onmousedown={keep} onclick={onclose}>×</button>
  </header>
  <p class="hint">Click an entry to insert it at the caret. While typing, suggestions appear by themselves; Ctrl+Space shows them all.</p>

  {#if ctx.locals.length}
    <section>
      <h4>Repeat</h4>
      {#each ctx.locals as l}
        <button class="row" onmousedown={keep} onclick={() => oninsert(l.name, false)}>
          <code class="n local">{l.name}</code><span class="t">{l.fields ? 'item' : 'number'}</span>
          <span class="d">{l.detail}</span>
        </button>
        {#each Object.entries(l.fields ?? {}) as [f, t]}
          <button class="row sub" class:dim={dim(t)} onmousedown={keep} onclick={() => oninsert(`${l.name}.${f}`, false)}>
            <code class="n">{l.name}.<span class="local">{f}</span></code><span class="t">{t}</span>
          </button>
        {/each}
      {/each}
    </section>
  {/if}

  <section>
    <h4>Params</h4>
    {#each params as p}
      <button class="row" class:dim={dim(p.type)} onmousedown={keep} onclick={() => oninsert(p.name, false)} title={dim(p.type) ? `This field needs ${expect}; ${p.name} is ${valueType(p.type)}` : ''}>
        <code class="n param">{p.name}</code><span class="t">{typeLabel(p.type, p.item)}</span>
        {#if p.label || p.note}<span class="d">{[p.label, p.note].filter(Boolean).join(' — ')}</span>{/if}
      </button>
    {:else}
      <p class="empty">No params yet.</p>
    {/each}
  </section>

  {#if ctx.layers.length}
    <section>
      <h4>Layers <span class="aside">@id.field — e.g. @{ctx.layers[0].id}.bounds.bottom</span></h4>
      <div class="chips">
        {#each ctx.layers as l}
          <button class="chip" onmousedown={keep} onclick={() => oninsert('@' + l.id + '.', true)} title="{l.type} layer"><code class="ref-id">@{l.id}</code><span class="t">{l.type}</span></button>
        {/each}
      </div>
    </section>
  {/if}

  <section>
    <h4>Built-ins</h4>
    {#each Object.entries(BUILTINS) as [ns, b]}
      {#each b.fields as f}
        <button class="row" class:dim={dim(f.type)} onmousedown={keep} onclick={() => oninsert(`${ns}.${f.name}`, false)}>
          <code class="n"><span class="builtin">{ns}</span>.{f.name}</code><span class="t">{f.type}</span>
          <span class="d">{f.doc}</span>
        </button>
      {/each}
    {/each}
  </section>

  <section>
    <h4>Functions</h4>
    {#each fns as f}
      <button class="row fn" class:dim={dim(f.ret)} onmousedown={keep} onclick={() => oninsert(f.name + '(', false)}>
        <code class="sig"><span class="fname">{f.name}</span>{fnSignature(f).text.slice(f.name.length)}</code>
        <span class="d">{f.doc} <code class="ex">{f.example}</code></span>
      </button>
    {/each}
  </section>

  <section class="cheat">
    {#if template}
      <h4>Templates</h4>
      {#each TEMPLATE_HELP as [k, v]}
        <div class="crow"><code>{k}</code><span>{v}</span></div>
      {/each}
    {/if}
    {#each CHEATSHEET as g}
      <h4>{g.title}</h4>
      {#each g.rows as [k, v]}
        <div class="crow"><code>{k}</code><span>{v}</span></div>
      {/each}
    {/each}
  </section>
</div>

<style>
  .ref {
    position: fixed;
    z-index: 1000;
    box-sizing: border-box;
    overflow: auto;
    padding: 0 0 8px;
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 8px;
    box-shadow:
      0 10px 32px rgba(0, 0, 0, 0.2),
      0 1px 3px rgba(0, 0, 0, 0.12);
    font: 12px/1.4 system-ui, -apple-system, 'Segoe UI', sans-serif;
  }
  .ref.above {
    transform: translateY(-100%);
  }
  header {
    position: sticky;
    top: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 8px 7px 12px;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--line);
  }
  .title {
    font-weight: 600;
  }
  .needs {
    color: var(--muted);
    font-size: 11px;
  }
  .needs b {
    color: var(--accent);
    font-family: var(--mono);
    font-weight: 600;
  }
  .close {
    margin-left: auto;
    padding: 0 6px;
    border: none;
    background: none;
    color: var(--muted);
    font-size: 16px;
    line-height: 1;
  }
  .close:hover {
    color: var(--fg);
  }
  .hint {
    margin: 6px 12px 0;
    color: var(--muted);
    font-size: 11px;
  }
  section {
    padding: 2px 6px 0;
  }
  h4 {
    margin: 10px 6px 3px;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .aside {
    text-transform: none;
    letter-spacing: 0;
    font-weight: 400;
    font-family: var(--mono);
    margin-left: 4px;
  }
  .row {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    column-gap: 8px;
    padding: 3px 6px;
    border-radius: 4px;
    cursor: pointer;
  }
  .row:hover,
  .chip:hover {
    background: var(--hover);
  }
  .row.sub {
    padding-left: 18px;
  }
  .row.dim {
    opacity: 0.5;
  }
  .row.dim:hover {
    opacity: 0.85;
  }
  .n,
  .sig {
    font-family: var(--mono);
    font-size: 12px;
  }
  .t {
    margin-left: auto;
    color: var(--muted);
    font-family: var(--mono);
    font-size: 11px;
  }
  .d {
    flex-basis: 100%;
    color: var(--muted);
    font-size: 11px;
  }
  .fn .d {
    margin-top: 1px;
  }
  .ex {
    color: var(--fg);
    opacity: 0.75;
    font-size: 11px;
    white-space: nowrap;
  }
  .param {
    color: var(--yx-param);
  }
  .local {
    color: var(--yx-param);
    font-style: italic;
  }
  .builtin {
    color: var(--syn-key);
  }
  .fname {
    color: var(--syn-keyword);
    font-weight: 600;
  }
  .ref-id {
    color: var(--yx-ref);
    font-weight: 600;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    padding: 0 4px;
  }
  .chip {
    all: unset;
    display: inline-flex;
    gap: 6px;
    align-items: baseline;
    padding: 2px 7px;
    border: 1px solid var(--line);
    border-radius: 10px;
    cursor: pointer;
    font-family: var(--mono);
    font-size: 12px;
  }
  .empty {
    margin: 2px 6px;
    color: var(--muted);
  }
  .cheat {
    margin-top: 4px;
    border-top: 1px solid var(--line);
  }
  .crow {
    display: grid;
    grid-template-columns: 118px 1fr;
    gap: 8px;
    padding: 2px 6px;
    color: var(--muted);
    font-size: 11px;
  }
  .crow code {
    color: var(--fg);
    font-size: 11.5px;
  }
</style>
