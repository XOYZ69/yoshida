<script lang="ts">
  // The options of an enum param, one row each: Enter adds a row, pasting
  // several lines adds several options, rows can be dragged to reorder.
  // Renaming an option also renames it in the default and in card data (the
  // parent does that through `onrename`).
  import { confirmAction } from '../ui/overlay.svelte';

  let {
    options,
    usage,
    templates,
    onchange,
    onrename,
  }: {
    options: string[];
    /** How many cards use each option. */
    usage: Map<string, number>;
    /** Path templates that use this param; renaming an option affects their files. */
    templates: string[];
    onchange: (options: string[]) => void;
    onrename: (from: string, to: string) => void;
  } = $props();

  let error = $state('');
  let adding = $state('');
  let dragFrom: number | null = $state(null);
  let dropAt: number | null = $state(null);

  function split(text: string) {
    return text
      .split(/[\r\n]+/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function add(raw: string) {
    const fresh = split(raw).filter((s, i, a) => a.indexOf(s) === i);
    const dup = fresh.filter((s) => options.includes(s));
    const next = fresh.filter((s) => !options.includes(s));
    error = dup.length ? `Already an option: ${dup.join(', ')}` : '';
    if (next.length) onchange([...options, ...next]);
    adding = '';
  }

  async function rename(i: number, raw: string, input: HTMLInputElement) {
    const to = raw.trim();
    const from = options[i];
    if (to === from) return (error = '');
    if (!to) {
      input.value = from;
      return (error = 'An option cannot be empty; use × to remove it.');
    }
    if (options.includes(to)) {
      input.value = from;
      return (error = `'${to}' is already an option.`);
    }
    error = '';
    if (templates.length) {
      const ok = await confirmAction({
        title: `Rename '${from}' to '${to}'?`,
        message: `This param is used in ${templates.map((t) => `"${t}"`).join(', ')}. Files named after '${from}' must be renamed too, or those cards will show a missing image.`,
        confirm: 'Rename',
      });
      if (!ok) {
        input.value = from;
        return;
      }
    }
    onrename(from, to);
  }

  async function remove(i: number) {
    const o = options[i];
    const n = usage.get(o) ?? 0;
    if (n) {
      const ok = await confirmAction({
        title: `Remove option '${o}'?`,
        message: `${n} card${n === 1 ? ' uses' : 's use'} it and will show an error until you pick another option.`,
        confirm: 'Remove',
        danger: true,
      });
      if (!ok) return;
    }
    onchange(options.filter((_, j) => j !== i));
  }

  function move(from: number, to: number) {
    if (from === to || from + 1 === to) return;
    const next = [...options];
    const [o] = next.splice(from, 1);
    next.splice(to > from ? to - 1 : to, 0, o);
    onchange(next);
  }

  function sortAz() {
    onchange([...options].sort((a, b) => a.localeCompare(b, undefined, { numeric: true })));
  }
</script>

<div class="opts">
  <div class="head">
    <span class="lbl">options ({options.length})</span>
    {#if options.length > 2}<button class="mini" title="Sort the options A to Z" onclick={sortAz}>A→Z</button>{/if}
  </div>
  <ol>
    {#each options as o, i (o)}
      <li
        class:drop={dropAt === i}
        ondragover={(e) => {
          if (dragFrom === null) return;
          e.preventDefault();
          const b = (e.currentTarget as HTMLElement).getBoundingClientRect();
          dropAt = e.clientY < b.top + b.height / 2 ? i : i + 1;
        }}
        ondrop={(e) => {
          e.preventDefault();
          if (dragFrom !== null && dropAt !== null) move(dragFrom, dropAt);
          dragFrom = dropAt = null;
        }}>
        <span
          class="grip"
          draggable="true"
          role="button"
          tabindex="-1"
          aria-label="Drag to reorder"
          title="Drag to reorder"
          ondragstart={(e) => {
            dragFrom = i;
            e.dataTransfer?.setData('text/x-yoshida-option', o);
          }}
          ondragend={() => (dragFrom = dropAt = null)}>⋮⋮</span>
        <input
          class="mono"
          value={o}
          aria-label="Option {i + 1}"
          onchange={(e) => rename(i, e.currentTarget.value, e.currentTarget)}
          onkeydown={(e) => {
            if (e.key === 'Enter') e.currentTarget.blur();
            if (e.key === 'Escape') {
              e.currentTarget.value = o;
              e.currentTarget.blur();
            }
          }} />
        {#if usage.get(o)}<span class="use" title="{usage.get(o)} card(s) use this option">{usage.get(o)}</span>{/if}
        <button class="mini" title="Remove '{o}'" disabled={options.length <= 1} onclick={() => remove(i)}>×</button>
      </li>
    {/each}
    <li class="end" class:drop={dropAt === options.length}></li>
  </ol>
  <input
    class="mono"
    placeholder="+ option, Enter (paste several lines)"
    bind:value={adding}
    onkeydown={(e) => {
      if (e.key === 'Enter' && adding.trim()) {
        e.preventDefault();
        add(adding);
      }
    }}
    onpaste={(e) => {
      const t = e.clipboardData?.getData('text') ?? '';
      if (/[\r\n]/.test(t.trim())) {
        e.preventDefault();
        add(t);
      }
    }} />
  {#if error}<p class="err">{error}</p>{/if}
</div>

<style>
  .opts {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .head {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .lbl {
    font-size: 12px;
    color: var(--muted);
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
    max-height: 260px;
    overflow: auto;
  }
  li {
    display: flex;
    align-items: center;
    gap: 4px;
    border-top: 2px solid transparent;
  }
  li.drop {
    border-top-color: var(--accent);
  }
  li.end {
    min-height: 2px;
  }
  li input {
    flex: 1;
    min-width: 0;
    padding: 2px 6px;
  }
  .grip {
    cursor: grab;
    color: var(--muted);
    font-size: 11px;
    letter-spacing: -2px;
    padding: 0 2px;
    user-select: none;
  }
  .use {
    font-size: 11px;
    color: var(--muted);
    min-width: 14px;
    text-align: right;
  }
  .mini {
    padding: 1px 6px;
    font-size: 11px;
  }
  .mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .err {
    color: var(--err);
    font-size: 12px;
    margin: 0;
  }
</style>
