<script lang="ts">
  // Themed color picker (replaces <input type=color>): a swatch that opens
  // a saturation/value square, hue and alpha sliders and a hex field.
  // `value` is #RRGGBB or #RRGGBBAA; changes are reported when a drag ends.
  import { placeNear } from './overlay.svelte';

  let {
    value,
    onchange,
    disabled = false,
    title = 'Pick a color',
  }: {
    value: string;
    onchange: (hex: string) => void;
    disabled?: boolean;
    title?: string;
  } = $props();

  type Hsva = { h: number; s: number; v: number; a: number };

  function parse(hex: string): Hsva {
    const m = /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(hex.trim());
    const n = m ? parseInt(m[1], 16) : 0;
    const r = ((n >> 16) & 255) / 255;
    const g = ((n >> 8) & 255) / 255;
    const b = (n & 255) / 255;
    const a = m?.[2] ? parseInt(m[2], 16) / 255 : 1;
    const max = Math.max(r, g, b);
    const d = max - Math.min(r, g, b);
    let h = 0;
    if (d) {
      if (max === r) h = ((g - b) / d) % 6;
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h = (h * 60 + 360) % 360;
    }
    return { h, s: max ? d / max : 0, v: max, a };
  }

  function rgbOf({ h, s, v }: Hsva): [number, number, number] {
    const f = (k: number) => {
      const x = (k + h / 60) % 6;
      return v - v * s * Math.max(0, Math.min(x, 4 - x, 1));
    };
    return [f(5), f(3), f(1)].map((c) => Math.round(c * 255)) as [number, number, number];
  }

  const hx = (n: number) => n.toString(16).padStart(2, '0').toUpperCase();
  function format(c: Hsva) {
    const [r, g, b] = rgbOf(c);
    const a = Math.round(c.a * 255);
    return `#${hx(r)}${hx(g)}${hx(b)}${a === 255 ? '' : hx(a)}`;
  }

  let open = $state(false);
  let button: HTMLButtonElement | undefined = $state();
  let pop: HTMLDivElement | undefined = $state();
  let pos = $state({ left: 0, top: 0 });
  let c = $state<Hsva>({ h: 0, s: 0, v: 0, a: 1 });
  let hexText = $state('');

  const solid = $derived(format({ ...c, a: 1 }).slice(0, 7));
  const swatch = $derived(/^#[0-9a-f]{6}/i.test(value) ? value : '#000000');

  function show() {
    if (disabled || !button) return;
    c = parse(value);
    hexText = format(c);
    const p = placeNear(button.getBoundingClientRect(), 232, 280);
    pos = { left: p.left, top: p.top };
    open = true;
  }

  function commit() {
    const next = format(c);
    hexText = next;
    if (next.toUpperCase() !== value.toUpperCase()) onchange(next);
  }

  function track(e: PointerEvent, apply: (x: number, y: number) => void) {
    const el = e.currentTarget as HTMLElement;
    const r = el.getBoundingClientRect();
    const at = (ev: PointerEvent) => apply(Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)), Math.max(0, Math.min(1, (ev.clientY - r.top) / r.height)));
    el.setPointerCapture(e.pointerId);
    at(e);
    hexText = format(c);
    const move = (ev: PointerEvent) => {
      at(ev);
      hexText = format(c);
    };
    const up = () => {
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      commit();
    };
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', up);
  }

  function typedHex() {
    const t = hexText.trim();
    if (/^#?[0-9a-f]{6}([0-9a-f]{2})?$/i.test(t)) {
      c = parse(t.startsWith('#') ? t : `#${t}`);
      commit();
    } else hexText = format(c);
  }
</script>

<svelte:window
  onpointerdowncapture={(e) => {
    if (open && !pop?.contains(e.target as Node) && !button?.contains(e.target as Node)) open = false;
  }}
  onkeydown={(e) => {
    if (open && e.key === 'Escape') {
      e.stopPropagation();
      open = false;
      button?.focus();
    }
  }} />

<button bind:this={button} type="button" class="swatch" {disabled} {title} aria-label={title} onclick={() => (open ? (open = false) : show())}>
  <span class="chip" style:background={swatch}></span>
</button>

{#if open}
  <div bind:this={pop} class="pop" style:left="{pos.left}px" style:top="{pos.top}px" role="dialog" aria-label="Color picker">
    <div
      class="sv"
      style:background-color="hsl({c.h} 100% 50%)"
      role="slider"
      tabindex="0"
      aria-label="Saturation and brightness"
      aria-valuenow={Math.round(c.s * 100)}
      onpointerdown={(e) => track(e, (x, y) => (c = { ...c, s: x, v: 1 - y }))}>
      <span class="knob" style:left="{c.s * 100}%" style:top="{(1 - c.v) * 100}%" style:background={solid}></span>
    </div>
    <div
      class="bar hue"
      role="slider"
      tabindex="0"
      aria-label="Hue"
      aria-valuenow={Math.round(c.h)}
      onpointerdown={(e) => track(e, (x) => (c = { ...c, h: x * 359.9 }))}>
      <span class="thumb" style:left="{(c.h / 360) * 100}%"></span>
    </div>
    <div
      class="bar alpha"
      style:--solid={solid}
      role="slider"
      tabindex="0"
      aria-label="Opacity"
      aria-valuenow={Math.round(c.a * 100)}
      onpointerdown={(e) => track(e, (x) => (c = { ...c, a: x }))}>
      <span class="thumb" style:left="{c.a * 100}%"></span>
    </div>
    <div class="row">
      <span class="preview"><span style:background={format(c)}></span></span>
      <input class="hex" bind:value={hexText} onchange={typedHex} onkeydown={(e) => e.key === 'Enter' && typedHex()} aria-label="Hex color" />
      <span class="pct">{Math.round(c.a * 100)}%</span>
    </div>
  </div>
{/if}

<style>
  .swatch {
    padding: 2px;
    width: 30px;
    height: 26px;
    flex: none;
    display: grid;
    place-items: stretch;
    background: var(--bg-code);
  }
  .chip,
  .preview span {
    display: block;
    border-radius: 3px;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.15);
  }
  .pop {
    position: fixed;
    z-index: 950;
    width: 216px;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25);
  }
  .sv {
    position: relative;
    height: 140px;
    border-radius: 6px;
    background-image: linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, transparent);
    cursor: crosshair;
    touch-action: none;
  }
  .knob {
    position: absolute;
    width: 12px;
    height: 12px;
    margin: -6px 0 0 -6px;
    border-radius: 50%;
    border: 2px solid #fff;
    box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.4);
    pointer-events: none;
  }
  .bar {
    position: relative;
    height: 12px;
    border-radius: 6px;
    cursor: pointer;
    touch-action: none;
  }
  .hue {
    background: linear-gradient(to right, #f00, #ff0, #0f0, #0ff, #00f, #f0f, #f00);
  }
  .alpha {
    background:
      linear-gradient(to right, transparent, var(--solid)),
      repeating-conic-gradient(var(--check-a) 0 25%, var(--check-b) 0 50%) 0 0 / 8px 8px;
  }
  .thumb {
    position: absolute;
    top: 50%;
    width: 10px;
    height: 16px;
    margin: -8px 0 0 -5px;
    border-radius: 3px;
    background: #fff;
    box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.4);
    pointer-events: none;
  }
  .row {
    display: flex;
    gap: 6px;
    align-items: center;
  }
  .preview {
    width: 26px;
    height: 22px;
    border-radius: 4px;
    display: grid;
    background: repeating-conic-gradient(var(--check-a) 0 25%, var(--check-b) 0 50%) 0 0 / 8px 8px;
  }
  .hex {
    flex: 1;
    font-family: var(--mono);
    font-size: 12px !important;
  }
  .pct {
    font-size: 11px;
    color: var(--muted);
    width: 34px;
    text-align: right;
  }
</style>
