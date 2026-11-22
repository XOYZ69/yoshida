<script lang="ts">
// Picks the format of a barcode layer: the current one as a button, and a
// grid of every format with a small preview made by the real encoder, so the
// difference between the codes can be seen before choosing.
import { BARCODE_FORMATS, formatInfo } from "../barcode";
import type { BarcodeInfo, BarcodeRequest } from "../engine";

let {
	value,
	lookup,
	onpick,
}: {
	/** The current format (a literal; "" when it is an expression). */
	value: string;
	lookup: (req: BarcodeRequest) => Promise<BarcodeInfo>;
	onpick: (format: string) => void;
} = $props();

let open = $state(false);
let previews = $state<Record<string, { w: number; h: number; bits: string } | null>>({});

const current = $derived(formatInfo(value));

$effect(() => {
	if (!open) return;
	for (const f of BARCODE_FORMATS) {
		if (f.soon || f.id in previews) continue;
		previews[f.id] = null;
		lookup({ format: f.id, text: f.sample, modules: true })
			.then((r) => {
				if (r.ok && r.modules) previews[f.id] = { w: r.w, h: r.h, bits: r.modules };
			})
			.catch(() => {});
	}
});

/** One path of squares for the dark modules; a 1D code is drawn as tall bars. */
function pathOf(p: { w: number; h: number; bits: string }, linear: boolean): string {
	let d = "";
	const rows = linear ? 1 : p.h;
	for (let y = 0; y < rows; y++) {
		let x = 0;
		while (x < p.w) {
			if (p.bits[y * p.w + x] !== "1") {
				x++;
				continue;
			}
			let e = x;
			while (e < p.w && p.bits[y * p.w + e] === "1") e++;
			d += `M${x} ${y}h${e - x}v1h${x - e}z`;
			x = e;
		}
	}
	return d;
}

function viewBox(p: { w: number; h: number }, linear: boolean): string {
	// Bars are drawn as high as a quarter of their width, but at most square.
	return linear ? `0 0 ${p.w} 1` : `0 0 ${p.w} ${p.h}`;
}
</script>

<div class="picker">
  <button class="current" type="button" aria-expanded={open} onclick={() => (open = !open)} title="Choose the kind of code">
    <span class="name">{current?.name ?? (value || 'expression')}</span>
    <span class="chev" aria-hidden="true">{open ? '▴' : '▾'}</span>
  </button>
  {#if open}
    <div class="grid" role="listbox" aria-label="Barcode formats">
      {#each BARCODE_FORMATS as f (f.id)}
        {@const p = previews[f.id]}
        <button
          type="button"
          role="option"
          aria-selected={f.id === value}
          class="tile"
          class:on={f.id === value}
          disabled={f.soon}
          title={f.hint}
          onclick={() => {
            onpick(f.id);
            open = false;
          }}
        >
          <span class="art" class:bars={f.kind === 'linear'}>
            {#if p}
              <svg viewBox={viewBox(p, f.kind === 'linear')} preserveAspectRatio="none" shape-rendering="crispEdges" aria-hidden="true"><path d={pathOf(p, f.kind === 'linear')} fill="currentColor" /></svg>
            {/if}
          </span>
          <span class="lbl">{f.name}</span>
          {#if f.soon}<span class="soon">soon</span>{/if}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .picker {
    flex: 1;
    min-width: 0;
  }
  .current {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 4px 8px;
    border: 1px solid var(--border, #8884);
    border-radius: 6px;
    background: var(--surface, transparent);
    color: inherit;
    font: inherit;
    cursor: pointer;
  }
  .grid {
    margin-top: 6px;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 6px;
  }
  .tile {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 6px 4px;
    border: 1px solid var(--border, #8884);
    border-radius: 6px;
    background: transparent;
    color: inherit;
    font: inherit;
    font-size: 11px;
    cursor: pointer;
    position: relative;
  }
  .tile:hover:not(:disabled) {
    border-color: var(--accent, #3b6cf6);
  }
  .tile.on {
    border-color: var(--accent, #3b6cf6);
    box-shadow: 0 0 0 1px var(--accent, #3b6cf6) inset;
  }
  .tile:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .art {
    width: 44px;
    height: 44px;
    display: block;
  }
  .art svg {
    width: 100%;
    height: 100%;
    display: block;
  }
  .art.bars {
    height: 28px;
    margin: 8px 0;
  }
  .lbl {
    text-align: center;
    line-height: 1.2;
  }
  .soon {
    position: absolute;
    top: 3px;
    right: 4px;
    font-size: 9px;
    opacity: 0.8;
  }
</style>
