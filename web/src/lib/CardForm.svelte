<script lang="ts">
  // Form for the current card, built from the design's params. Changes are
  // written back into the card data file by the parent.
  import type { CardInfo, Param } from './engine';
  import Select from './ui/Select.svelte';
  import ColorPicker from './ui/ColorPicker.svelte';
  import ImagePicker from './ui/ImagePicker.svelte';
  import { paramSections } from './design';

  let {
    params,
    card,
    editable,
    imageFiles,
    upload,
    onchange,
  }: {
    params: Param[];
    card: CardInfo | undefined;
    editable: boolean;
    imageFiles: string[];
    upload: () => Promise<string | null>;
    onchange: (param: string, value: unknown) => void;
  } = $props();

  // Params with a `group` are shown in foldable sections, ungrouped first.
  const sections = $derived(paramSections(params.map((p) => [p.name, p] as [string, Param]), (p) => (p.group ?? '').trim()));
  let folded = $state(new Set<string>());
  /** The field being edited shows its note below it. */
  let focused: string | null = $state(null);

  function fold(g: string) {
    const next = new Set(folded);
    if (!next.delete(g)) next.add(g);
    folded = next;
  }

  function current(p: Param): unknown {
    return card?.values[p.name];
  }

  function shown(p: Param): string {
    const v = current(p) ?? p.default;
    if (v === undefined || v === null) return '';
    return typeof v === 'object' ? JSON.stringify(v, null, 1) : String(v);
  }

  function set(p: Param, raw: string | boolean) {
    if (raw === '' || raw === undefined) return onchange(p.name, undefined);
    switch (p.type) {
      case 'number':
      case 'integer': {
        const n = Number(raw);
        if (Number.isFinite(n)) onchange(p.name, n);
        return;
      }
      case 'bool':
        return onchange(p.name, raw === true);
      case 'list':
        try {
          onchange(p.name, JSON.parse(String(raw)));
        } catch {
          /* keep typing */
        }
        return;
      default:
        return onchange(p.name, raw);
    }
  }

  // List params with item fields are edited as a small table.
  type Item = Record<string, unknown>;

  function itemsOf(p: Param): Item[] {
    const v = current(p) ?? p.default;
    return Array.isArray(v) ? v.map((x) => (x && typeof x === 'object' ? (x as Item) : {})) : [];
  }

  function blankItem(p: Param): Item {
    const out: Item = {};
    for (const [k, t] of Object.entries(p.item ?? {})) out[k] = t === 'number' || t === 'integer' ? 0 : t === 'bool' ? false : t === 'color' ? '#000000' : '';
    return out;
  }

  function setItem(p: Param, index: number, field: string, raw: string | boolean) {
    const t = p.item?.[field];
    let v: unknown = raw;
    if (t === 'number' || t === 'integer') {
      v = Number(raw);
      if (raw === '' || !Number.isFinite(v)) return;
    }
    const items = itemsOf(p).map((x) => ({ ...x }));
    items[index][field] = v;
    onchange(p.name, items);
  }

  function addItem(p: Param) {
    onchange(p.name, [...itemsOf(p), blankItem(p)]);
  }

  function removeItem(p: Param, index: number) {
    onchange(
      p.name,
      itemsOf(p).filter((_, i) => i !== index),
    );
  }
</script>

<div class="form">
  {#if !editable}
    <p class="note">This design has no card data file, so values cannot be saved. Add a <code>*.cards.json</code> file that names this design.</p>
  {/if}
  {#each sections as sec (sec.group)}
    {#if sec.group}
      <button class="section" aria-expanded={!folded.has(sec.group)} onclick={() => fold(sec.group)}>
        <span>{folded.has(sec.group) ? '▸' : '▾'}</span>
        <span class="title">{sec.group}</span>
        <span class="count">{sec.params.length}</span>
      </button>
    {/if}
    {#if !folded.has(sec.group)}
  {#each sec.params as [, p] (p.name)}
    {@const isSet = current(p) !== undefined}
    <div class="fld" class:unset={!isSet} onfocusin={() => (focused = p.name)} onfocusout={() => (focused = focused === p.name ? null : focused)}>
      <span class="name">
        {p.label ?? p.name}
        {#if p.required}<b>*</b>{/if}
        {#if p.note}
          <button type="button" class="info" aria-label="About {p.label ?? p.name}: {p.note}">
            ⓘ<span class="tip" role="tooltip">{p.note}</span>
          </button>
        {/if}
        <small>{p.type}{isSet ? '' : ' (default)'}</small>
      </span>
      {#if p.type === 'bool'}
        <input type="checkbox" checked={shown(p) === 'true'} disabled={!editable} onchange={(e) => set(p, e.currentTarget.checked)} />
      {:else if p.type === 'enum'}
        <Select value={shown(p)} label={p.label ?? p.name} disabled={!editable} options={p.options ?? []} onchange={(v) => set(p, v)} />
      {:else if p.type === 'color'}
        <span class="row">
          <ColorPicker value={/^#[0-9a-f]{6}/i.test(shown(p)) ? shown(p) : '#000000'} disabled={!editable} title="Pick {p.label ?? p.name}" onchange={(v) => set(p, v)} />
          <input type="text" value={shown(p)} disabled={!editable} onchange={(e) => set(p, e.currentTarget.value)} />
        </span>
      {:else if p.type === 'number' || p.type === 'integer'}
        <input type="number" value={shown(p)} min={p.min} max={p.max} step={p.type === 'integer' ? 1 : 'any'} disabled={!editable} onchange={(e) => set(p, e.currentTarget.value)} />
      {:else if p.type === 'list' && p.item && Object.keys(p.item).length}
        {@const fields = Object.entries(p.item)}
        <div class="items">
          <table>
            <thead>
              <tr>
                {#each fields as [f]}<th>{f}</th>{/each}
                <th></th>
              </tr>
            </thead>
            <tbody>
              {#each itemsOf(p) as it, i}
                <tr>
                  {#each fields as [f, t]}
                    <td>
                      {#if t === 'bool'}
                        <input type="checkbox" checked={it[f] === true} disabled={!editable} onchange={(e) => setItem(p, i, f, e.currentTarget.checked)} />
                      {:else}
                        <input
                          type={t === 'number' || t === 'integer' ? 'number' : 'text'}
                          step={t === 'integer' ? 1 : 'any'}
                          value={it[f] ?? ''}
                          disabled={!editable}
                          onchange={(e) => setItem(p, i, f, e.currentTarget.value)} />
                      {/if}
                    </td>
                  {/each}
                  <td><button class="reset" title="Remove this row" disabled={!editable} onclick={(e) => { e.preventDefault(); removeItem(p, i); }}>×</button></td>
                </tr>
              {/each}
            </tbody>
          </table>
          <button class="add" disabled={!editable} onclick={(e) => { e.preventDefault(); addItem(p); }}>+ Row</button>
        </div>
      {:else if p.type === 'list'}
        <textarea rows="4" value={shown(p)} disabled={!editable} onchange={(e) => set(p, e.currentTarget.value)}></textarea>
      {:else if p.type === 'image'}
        <div class="img">
          <input type="text" value={shown(p)} disabled={!editable} onchange={(e) => set(p, e.currentTarget.value)} />
          <ImagePicker {imageFiles} {upload} disabled={!editable} onpick={(v) => set(p, v)} />
        </div>
      {:else}
        <textarea rows={shown(p).length > 40 ? 3 : 1} value={shown(p)} maxlength={p.max_length} disabled={!editable} onchange={(e) => set(p, e.currentTarget.value)}></textarea>
      {/if}
      {#if isSet && editable}
        <button class="reset" title="Use the default" onclick={() => onchange(p.name, undefined)}>×</button>
      {/if}
      {#if p.note && focused === p.name}<p class="note-line">{p.note}</p>{/if}
    </div>
  {/each}
    {/if}
  {/each}
</div>

<style>
  .img {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .form {
    padding: 8px 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .fld {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 2px 6px;
    align-items: start;
  }
  .name {
    grid-column: 1 / -1;
    font-size: 12px;
    font-weight: 600;
  }
  .name small {
    font-weight: 400;
    color: var(--muted);
    margin-left: 6px;
  }
  .name b {
    color: var(--err);
  }
  .section {
    all: unset;
    box-sizing: border-box;
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 4px -12px 0;
    padding: 5px 12px;
    background: var(--bg-bar);
    border-top: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
    cursor: pointer;
  }
  .section .title {
    flex: 1;
  }
  .section .count {
    font-weight: 400;
  }
  .info {
    all: unset;
    position: relative;
    display: inline-block;
    margin-left: 4px;
    color: var(--accent);
    font-weight: 400;
    cursor: help;
    outline: none;
  }
  .tip {
    display: none;
    position: absolute;
    left: -40px;
    top: calc(100% + 6px);
    z-index: 20;
    width: max-content;
    max-width: 240px;
    padding: 6px 8px;
    border-radius: 6px;
    border: 1px solid var(--line);
    background: var(--bg-bar);
    color: var(--fg);
    box-shadow: 0 6px 18px rgb(0 0 0 / 0.25);
    font-size: 12px;
    font-weight: 400;
    line-height: 1.4;
    white-space: normal;
  }
  .info:hover .tip,
  .info:focus .tip {
    display: block;
  }
  .note-line {
    grid-column: 1 / -1;
    margin: 0;
    font-size: 11px;
    color: var(--muted);
    line-height: 1.35;
  }
  .unset input:not([type='checkbox']),
  .unset textarea {
    color: var(--muted);
  }
  input,
  textarea {
    font: inherit;
    font-size: 13px;
    width: 100%;
    box-sizing: border-box;
    background: var(--bg-code);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 4px;
    padding: 4px 6px;
  }
  input[type='checkbox'] {
    width: auto;
  }
  .row {
    display: flex;
    gap: 6px;
  }
  .reset {
    border: 0;
    background: none;
    color: var(--muted);
    cursor: pointer;
    font-size: 16px;
    line-height: 1;
    padding: 4px;
  }
  .items {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  table {
    border-collapse: collapse;
    width: 100%;
    table-layout: fixed;
  }
  th {
    font-size: 11px;
    font-weight: 500;
    color: var(--muted);
    text-align: left;
    padding: 0 2px;
  }
  td {
    padding: 1px 2px;
  }
  td:last-child,
  th:last-child {
    width: 24px;
  }
  td input {
    padding: 2px 4px;
    font-size: 12px;
  }
  .add {
    align-self: flex-start;
    font-size: 12px;
  }
  .note {
    font-size: 12px;
    color: var(--muted);
    margin: 0;
  }
</style>
