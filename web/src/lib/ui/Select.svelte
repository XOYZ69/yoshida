<script lang="ts" module>
  export type Option = { value: string; label?: string; detail?: string; muted?: boolean };
</script>

<script lang="ts">
  // Themed dropdown (replaces <select>). Long lists get a filter box.
  import { placeNear } from './overlay.svelte';

  let {
    value,
    options,
    onchange,
    placeholder = 'Choose…',
    disabled = false,
    title = '',
    mono = false,
    label = '',
    searchable = undefined,
    compact = false,
  }: {
    value: string;
    options: (string | Option)[];
    onchange: (v: string) => void;
    placeholder?: string;
    disabled?: boolean;
    title?: string;
    mono?: boolean;
    /** Accessible name. */
    label?: string;
    searchable?: boolean;
    compact?: boolean;
  } = $props();

  const opts = $derived(options.map((o): Option => (typeof o === 'string' ? { value: o } : o)));
  const current = $derived(opts.find((o) => o.value === value));
  const canSearch = $derived(searchable ?? opts.length > 10);

  let open = $state(false);
  let button: HTMLButtonElement | undefined = $state();
  let list: HTMLUListElement | undefined = $state();
  let search: HTMLInputElement | undefined = $state();
  let query = $state('');
  let active = $state(0);
  let pos = $state({ left: 0, top: 0, maxHeight: 300, width: 160 });

  const shown = $derived.by(() => {
    const q = query.trim().toLowerCase();
    if (!q) return opts;
    return opts.filter((o) => `${o.label ?? o.value} ${o.value} ${o.detail ?? ''}`.toLowerCase().includes(q));
  });

  function show() {
    if (disabled || !button) return;
    const r = button.getBoundingClientRect();
    // Wide enough for the longest option (label and detail), within reason.
    const longest = Math.max(0, ...opts.map((o) => (o.label ?? o.value).length * 7.5 + (o.detail ? o.detail.length * 6.5 + 12 : 0)));
    const width = Math.min(Math.max(r.width, 180, longest + 48), 440, window.innerWidth - 16);
    const p = placeNear(r, width, Math.min(320, opts.length * 30 + (canSearch ? 40 : 8)));
    pos = { ...p, maxHeight: Math.min(p.maxHeight, 360), width };
    query = '';
    active = Math.max(0, opts.findIndex((o) => o.value === value));
    open = true;
    requestAnimationFrame(() => {
      if (canSearch) search?.focus();
      else list?.focus();
      list?.querySelector('.active')?.scrollIntoView({ block: 'nearest' });
    });
  }

  function hide(refocus = true) {
    open = false;
    if (refocus) button?.focus();
  }

  function pick(o: Option) {
    hide();
    if (o.value !== value) onchange(o.value);
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      hide();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      if (!shown.length) return;
      active = (active + (e.key === 'ArrowDown' ? 1 : shown.length - 1)) % shown.length;
      requestAnimationFrame(() => list?.querySelector('.active')?.scrollIntoView({ block: 'nearest' }));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (shown[active]) pick(shown[active]);
    } else if (e.key === 'Tab') hide(false);
  }

  function onbuttonkey(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      show();
    }
  }
</script>

<svelte:window
  onpointerdowncapture={(e) => {
    if (!open) return;
    const t = e.target as Node;
    if (!list?.parentElement?.contains(t) && !button?.contains(t)) hide(false);
  }}
  onresize={() => open && hide(false)} />

<button
  bind:this={button}
  type="button"
  class="select"
  class:compact
  class:placeholder={!current}
  class:mono
  {disabled}
  {title}
  aria-label={label || undefined}
  aria-haspopup="listbox"
  aria-expanded={open}
  onclick={() => (open ? hide() : show())}
  onkeydown={onbuttonkey}>
  <span class="text">{current ? (current.label ?? current.value) : value || placeholder}</span>
  <svg class="chev" viewBox="0 0 10 6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.5" /></svg>
</button>

{#if open}
  <div class="pop" style:left="{pos.left}px" style:top="{pos.top}px" style:width="{pos.width}px" style:max-height="{pos.maxHeight}px">
    {#if canSearch}
      <input bind:this={search} class="search" placeholder="Filter…" bind:value={query} oninput={() => (active = 0)} {onkeydown} />
    {/if}
    <ul bind:this={list} role="listbox" tabindex="-1" aria-label={label || undefined} {onkeydown}>
      {#each shown as o, i (o.value)}
        <li
          role="option"
          aria-selected={o.value === value}
          class:active={i === active}
          class:selected={o.value === value}
          class:muted={o.muted}
          class:mono
          onpointerenter={() => (active = i)}
          onpointerdown={(e) => e.preventDefault()}
          onclick={() => pick(o)}
          onkeydown={() => {}}>
          <span class="check">{o.value === value ? '✓' : ''}</span>
          <span class="lbl">{o.label ?? o.value}</span>
          {#if o.detail}<span class="detail">{o.detail}</span>{/if}
        </li>
      {:else}
        <li class="empty">No matches</li>
      {/each}
    </ul>
  </div>
{/if}

<style>
  .select {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    max-width: 100%;
    text-align: left;
    padding: 3px 8px;
    background: var(--bg-code);
  }
  .select:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: -1px;
  }
  .select.compact {
    padding: 1px 6px;
    font-size: 11px;
    color: var(--muted);
    background: var(--bg);
  }
  .text {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .placeholder .text {
    color: var(--muted);
  }
  .mono .text,
  li.mono .lbl {
    font-family: var(--mono);
    font-size: 12px;
  }
  .chev {
    width: 10px;
    height: 6px;
    flex: none;
    color: var(--muted);
  }
  .pop {
    position: fixed;
    z-index: 950;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 8px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25);
    overflow: hidden;
  }
  .search {
    margin: 6px 6px 2px;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 4px;
    overflow: auto;
    outline: none;
  }
  li {
    display: flex;
    align-items: baseline;
    gap: 6px;
    padding: 4px 8px 4px 4px;
    border-radius: 5px;
    cursor: pointer;
    font-size: 13px;
  }
  li.active {
    background: var(--sel);
  }
  li.muted .lbl {
    color: var(--muted);
  }
  .check {
    width: 14px;
    flex: none;
    color: var(--accent);
    font-size: 12px;
    text-align: center;
  }
  .lbl {
    flex: 1 1 auto;
    min-width: 40%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .detail {
    flex: 0 1 auto;
    min-width: 0;
    color: var(--muted);
    font-size: 11px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .empty {
    color: var(--muted);
    cursor: default;
    justify-content: center;
  }
</style>
