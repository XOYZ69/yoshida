<script lang="ts">
  // One property in the inspector. Shows a widget for literal values (number,
  // color picker, checkbox, dropdown) and a text box for expressions. The
  // link menu binds the field to a param of a matching type.
  import { hexOf, literalNumber, round, type Json } from '../design';
  import ExprInput from './ExprInput.svelte';
  import Select from '../ui/Select.svelte';
  import ColorPicker from '../ui/ColorPicker.svelte';

  type FieldKind = 'number' | 'color' | 'bool' | 'enum' | 'template' | 'text' | 'expr';

  let {
    label,
    kind,
    value,
    fallback = undefined,
    options = [],
    bindings = [],
    optional = false,
    inherited = false,
    error = '',
    placeholder = '',
    title = '',
    allowAuto = false,
    expect = undefined,
    onchange,
  }: {
    label: string;
    kind: FieldKind;
    value: Json | undefined;
    /** Shown (greyed) when the field is not set. */
    fallback?: Json | undefined;
    options?: string[];
    /** Param names this field can be bound to. */
    bindings?: string[];
    optional?: boolean;
    inherited?: boolean;
    error?: string;
    placeholder?: string;
    title?: string;
    allowAuto?: boolean;
    /** The value type an expression must give (for suggestions). */
    expect?: 'number' | 'color' | 'bool' | 'text' | 'list' | 'image' | 'any';
    onchange: (v: Json | undefined) => void;
  } = $props();

  const unset = $derived(value === undefined);
  const shown = $derived(value ?? fallback);
  const text = $derived(shown === undefined || shown === null ? '' : typeof shown === 'string' ? shown : JSON.stringify(shown));
  const hex = $derived(hexOf(shown));
  const isExpr = $derived.by(() => {
    if (shown === undefined) return false;
    switch (kind) {
      case 'number':
        return literalNumber(shown) === undefined && !/^-?\d+(\.\d+)?%$/.test(String(shown)) && shown !== 'auto';
      case 'color':
        return hex === null;
      case 'bool':
        return typeof shown !== 'boolean';
      default:
        return false;
    }
  });
  let forceExpr = $state(false);
  const exprMode = $derived(isExpr || forceExpr);

  function parseNumber(raw: string): Json | undefined {
    const s = raw.trim();
    if (s === '') return optional ? undefined : value;
    const n = literalNumber(s);
    return n !== undefined ? n : s;
  }

  function commitText(raw: string) {
    if (kind === 'number') return onchange(parseNumber(raw));
    if (kind === 'bool' && (raw.trim() === 'true' || raw.trim() === 'false')) {
      forceExpr = false;
      return onchange(raw.trim() === 'true');
    }
    if (raw === '' && optional) return onchange(undefined);
    onchange(raw);
  }

  const expects = $derived(expect ?? (kind === 'number' ? 'number' : kind === 'color' ? 'color' : kind === 'bool' ? 'bool' : kind === 'template' ? 'text' : 'any'));

  function bind(name: string) {
    if (!name) return;
    if (kind === 'template') onchange(`${value ?? ''}{${name}}`);
    else onchange(name);
  }

  // Drag the label sideways to change a literal number.
  let scrub: { x: number; start: number } | null = null;
  function scrubStart(e: PointerEvent) {
    if (kind !== 'number') return;
    const n = literalNumber(shown);
    if (n === undefined) return;
    scrub = { x: e.clientX, start: n };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }
  function scrubMove(e: PointerEvent) {
    if (!scrub) return;
    const step = e.shiftKey ? 10 : Math.abs(scrub.start) < 2 ? 0.01 : 1;
    const next = round(scrub.start + Math.round((e.clientX - scrub.x) / 2) * step, 2);
    if (next !== literalNumber(value)) onchange(next);
  }
  function scrubEnd() {
    scrub = null;
  }
</script>

<div class="field" class:unset class:inherited class:bad={!!error} {title}>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <span
    class="label"
    class:scrub={kind === 'number' && literalNumber(shown) !== undefined}
    onpointerdown={scrubStart}
    onpointermove={scrubMove}
    onpointerup={scrubEnd}
    onpointercancel={scrubEnd}>{label}</span>
  <div class="control">
    {#if kind === 'enum'}
      <Select
        value={unset ? '' : text}
        label={label}
        options={[...(optional ? [{ value: '', label: `default${fallback !== undefined ? `: ${fallback}` : ''}`, muted: true }] : []), ...options]}
        onchange={(v) => onchange(v === '' && optional ? undefined : v)} />
    {:else if kind === 'bool' && !exprMode}
      <input type="checkbox" checked={shown === true} onchange={(e) => onchange(e.currentTarget.checked)} />
    {:else if kind === 'color' && !exprMode}
      <ColorPicker value={hex ?? '#000000'} title="Pick {label}" onchange={(v) => onchange(v)} />
      <ExprInput value={text} mono {placeholder} {label} expect="color" oncommit={commitText} />
    {:else if kind === 'template'}
      <ExprInput value={text} template multiline rows={text.length > 30 || text.includes('\n') ? 3 : 1} {placeholder} {label} expect="text" oncommit={commitText} />
    {:else}
      <ExprInput value={text} suggest={kind !== 'text'} mono={exprMode || kind === 'expr'} {placeholder} {label} expect={expects} oncommit={commitText} />
    {/if}
    {#if kind === 'number' && allowAuto}
      <button class="mini" class:on={shown === 'auto'} title="Keep the image's aspect ratio" onclick={() => onchange(shown === 'auto' ? 100 : 'auto')}>auto</button>
    {/if}
    {#if kind === 'color' || kind === 'bool'}
      <button class="mini" class:on={exprMode} title="Switch between a plain value and an expression" onclick={() => (isExpr ? onchange(kind === 'bool' ? true : '#000000') : (forceExpr = !forceExpr))}>{exprMode ? 'expr' : 'value'}</button>
    {:else if kind === 'number' && isExpr}
      <span class="mini on" title="This value is an expression">expr</span>
    {/if}
    {#if bindings.length}
      <span class="link"><Select compact value="" placeholder="param" label="Bind {label} to a param" title="Bind to a param" options={bindings} onchange={bind} /></span>
    {/if}
    {#if optional && !unset && kind !== 'enum'}
      <button class="mini" title="Remove (use the default)" onclick={() => onchange(undefined)}>×</button>
    {/if}
  </div>
  {#if error}<div class="error">{error}</div>{/if}
</div>

<style>
  .field {
    display: grid;
    grid-template-columns: 84px 1fr;
    gap: 2px 8px;
    align-items: center;
  }
  .label {
    font-size: 12px;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    user-select: none;
  }
  .label.scrub {
    cursor: ew-resize;
  }
  .control > :global(.select) {
    flex: 1;
  }
  .control {
    display: flex;
    gap: 4px;
    align-items: center;
    min-width: 0;
  }
  .unset .control :global(input),
  .unset .control :global(textarea) {
    color: var(--muted);
  }
  .inherited .label::after {
    content: ' ↳';
    color: var(--accent);
  }
  .bad .control :global(input),
  .bad .control :global(textarea) {
    border-color: var(--err);
  }
  .mini {
    padding: 2px 5px;
    font-size: 11px;
    border-radius: 4px;
    color: var(--muted);
    border: 1px solid var(--line);
    background: var(--bg);
    font-family: var(--mono);
  }
  .mini.on {
    color: var(--accent);
    border-color: var(--accent);
  }
  .link {
    width: 64px;
    flex: none;
    display: flex;
  }
  .link :global(.select) {
    width: 100%;
  }
  input[type='checkbox'] {
    margin: 4px 0;
  }
  .error {
    grid-column: 2;
    color: var(--err);
    font-size: 11px;
  }
</style>
