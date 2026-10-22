<script lang="ts">
// The export dialog: what to export, in which formats and at which
// resolution. A modal like the ask/confirm dialogs: it is a short decision
// that ends in one action, and the export's progress window follows it.
import ColorPicker from "./ColorPicker.svelte";
import Icon from "./Icon.svelte";
import Select from "./Select.svelte";
import {
	type ExportFormat,
	type ExportSettings,
	MAX_SIDE,
	type PlanSet,
	SCALES,
	formatLabels,
	planExport,
	planSummary,
	scaleFits,
	scaledSize,
} from "../exportPlan";

let {
	initial,
	project,
	sets,
	current,
	card,
	canvas,
	webp,
	canServer,
	useServer = $bindable(false),
	onexport,
	onclose,
}: {
	initial: ExportSettings;
	project: string;
	sets: PlanSet[];
	/** The set shown, and the index of the card shown. */
	current: string;
	card: number;
	/** Canvas size of the design shown (0 x 0 when not known yet). */
	canvas: { w: number; h: number };
	/** Whether this browser can encode WebP; null while checking. */
	webp: boolean | null;
	/** Whether the server this editor comes from can render (shows the switch). */
	canServer: boolean;
	/** Render on server (whole designs as PNG, SVG and PDF), the same setting as the toolbar switch. */
	useServer?: boolean;
	onexport: (s: ExportSettings) => void;
	onclose: () => void;
} = $props();

// svelte-ignore state_referenced_locally
let s = $state<ExportSettings>({ ...initial, formats: [...initial.formats] });
let box: HTMLDivElement | undefined = $state();

const set = $derived(sets.find((x) => x.name === current));
const cardId = $derived(set?.cards[card] ?? "");
const okSets = $derived(sets.filter((x) => x.ok));
const allCards = $derived(okSets.reduce((a, x) => a + x.cards.length, 0));
const unavailable = $derived<Partial<Record<ExportFormat, string>>>(
	webp === false
		? { webp: "This browser cannot write WebP images." }
		: webp === null
			? { webp: "Checking whether this browser can write WebP…" }
			: {},
);
/** The formats that will be written: chosen and available. */
const formats = $derived(s.formats.filter((f) => !unavailable[f]));
const plan = $derived(
	planExport({ scope: s.scope, formats }, project, sets, current, card),
);
const size = $derived(scaledSize(canvas, s.scale));
/** Vector formats use the resolution only for the parts that stay pixels. */
const vectorChosen = $derived(
	formats.includes("svg") || (formats.includes("pdf") && s.pdfVector),
);
const rasterChosen = $derived(
	formats.some((f) => f === "png" || f === "jpeg" || f === "webp") ||
		(formats.includes("pdf") && !s.pdfVector),
);
/** The pixel limit applies to images; vector files keep their size. */
const allowed = (k: number) => !rasterChosen || scaleFits(canvas, k);
const fits = $derived(allowed(s.scale));
/** "PNG", "PNG and SVG", "PNG, SVG and PDF". */
const listOf = (fs: ExportFormat[]) => {
	const names = fs.map((f) => formatLabels[f]);
	return names.length > 1
		? `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
		: (names[0] ?? "");
};
const server = $derived(canServer && useServer);
const where = $derived.by(() => {
	if (!server) return "Everything is rendered in this browser.";
	if (s.scope === "card")
		return "One card always renders in this browser; the server renders whole designs.";
	// JPEG and WebP are encoded by the browser, so they render here.
	const there = formats.filter((f) => f !== "jpeg" && f !== "webp");
	const here = formats.filter((f) => f === "jpeg" || f === "webp");
	if (!here.length) return "Rendered on the server.";
	if (!there.length)
		return `${listOf(here)} ${here.length > 1 ? "are" : "is"} rendered in this browser.`;
	return `${listOf(there)} on the server; ${listOf(here)} in this browser.`;
});
const canExport = $derived(plan.files > 0 && fits);

function toggle(f: ExportFormat, on: boolean) {
	s.formats = on
		? [...new Set([...s.formats, f])]
		: s.formats.filter((x) => x !== f);
}

function submit() {
	if (!canExport) return;
	onexport({ ...s, formats });
}

/** A dropdown list or color picker is open; it takes Enter and Escape. */
const popupOpen = () => !!box?.querySelector("[role=listbox], [role=dialog]");

const focusable = () =>
	[
		...(box?.querySelectorAll<HTMLElement>(
			"button, input, [tabindex]:not([tabindex='-1'])",
		) ?? []),
	].filter((el) => !(el as HTMLButtonElement).disabled);

function onkeydown(e: KeyboardEvent) {
	if (e.defaultPrevented) return;
	if ((e.key === "Escape" || e.key === "Enter") && popupOpen()) return;
	if (e.key === "Escape") {
		e.preventDefault();
		e.stopPropagation();
		onclose();
	} else if (
		e.key === "Enter" &&
		(e.target as HTMLElement).tagName !== "BUTTON"
	) {
		e.preventDefault();
		submit();
	} else if (e.key === "Tab") {
		// Keep the focus inside the dialog.
		const list = focusable();
		if (!list.length) return;
		const i = list.indexOf(document.activeElement as HTMLElement);
		if (e.shiftKey && i <= 0) {
			e.preventDefault();
			list[list.length - 1].focus();
		} else if (!e.shiftKey && i === list.length - 1) {
			e.preventDefault();
			list[0].focus();
		}
	}
}

$effect(() => {
	const first = box?.querySelector<HTMLInputElement>(
		"input[name='export-scope']:checked",
	);
	(first ?? focusable()[0])?.focus();
});
</script>

<div class="backdrop" role="presentation" onpointerdown={(e) => e.target === e.currentTarget && onclose()}>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div bind:this={box} class="dialog" role="dialog" aria-modal="true" aria-labelledby="export-title" tabindex="-1" {onkeydown}>
    <h2 id="export-title">Export</h2>

    <fieldset>
      <legend>What</legend>
      <label class="opt">
        <input type="radio" name="export-scope" value="card" bind:group={s.scope} disabled={!set?.ok} />
        This card{cardId ? ` (${cardId})` : ""}
      </label>
      <label class="opt">
        <input type="radio" name="export-scope" value="design" bind:group={s.scope} disabled={!set?.ok} />
        This design ({set?.cards.length ?? 0} card{set?.cards.length === 1 ? "" : "s"})
      </label>
      <label class="opt">
        <input type="radio" name="export-scope" value="all" bind:group={s.scope} />
        All designs ({okSets.length} design{okSets.length === 1 ? "" : "s"}, {allCards} card{allCards === 1 ? "" : "s"})
      </label>
      {#if plan.skipped.length}
        <p class="note warn">Skipped because they have errors: {plan.skipped.join(", ")}.</p>
      {/if}
    </fieldset>

    <fieldset>
      <legend>Formats</legend>
      <div class="fmt">
        <label class="opt"><input type="checkbox" checked={s.formats.includes("png")} onchange={(e) => toggle("png", e.currentTarget.checked)} /> PNG</label>
        <span class="more">
          <span class="ctl">Bit depth
            <Select label="Bit depth" value={String(s.pngDepth)} options={[{ value: "8", label: "8 bit" }, { value: "16", label: "16 bit" }]} disabled={!s.formats.includes("png")} onchange={(v) => (s.pngDepth = v === "16" ? 16 : 8)} />
          </span>
          <span class="ctl">Compression
            <Select label="Compression" value={s.pngCompression} options={[{ value: "fast", label: "Fast" }, { value: "default", label: "Default" }, { value: "smallest", label: "Smallest" }]} disabled={!s.formats.includes("png")} onchange={(v) => (s.pngCompression = v as ExportSettings["pngCompression"])} />
          </span>
        </span>
      </div>
      {#if s.formats.includes("png") && s.pngDepth === 16}
        <p class="note">16 bit keeps smooth gradients for print and editing; the files are about twice as large. PNG has no 10 bit mode.</p>
      {/if}

      <div class="fmt">
        <label class="opt"><input type="checkbox" checked={s.formats.includes("jpeg")} onchange={(e) => toggle("jpeg", e.currentTarget.checked)} /> JPEG</label>
        <span class="more">
          <span class="ctl">Quality
            <input type="range" min="5" max="100" step="5" aria-label="JPEG quality" title="Steps of 5; type an exact value in the field" bind:value={s.jpegQuality} disabled={!s.formats.includes("jpeg")} />
            <input type="number" min="1" max="100" aria-label="JPEG quality, exact value" bind:value={s.jpegQuality} disabled={!s.formats.includes("jpeg")} onchange={() => (s.jpegQuality = Math.max(1, Math.min(100, Math.round(s.jpegQuality || 90))))} />
          </span>
          <span class="ctl">Background
            <ColorPicker title="JPEG background: transparent parts are shown on this color" value={s.jpegBackground} disabled={!s.formats.includes("jpeg")} onchange={(v) => (s.jpegBackground = v.slice(0, 7))} />
          </span>
        </span>
      </div>

      <div class="fmt">
        <label class="opt" title={unavailable.webp}><input type="checkbox" checked={s.formats.includes("webp") && !unavailable.webp} disabled={!!unavailable.webp} onchange={(e) => toggle("webp", e.currentTarget.checked)} /> WebP</label>
        <span class="more">
          <span class="ctl">Quality
            <input type="range" min="5" max="100" step="5" aria-label="WebP quality" title="Steps of 5; type an exact value in the field" bind:value={s.webpQuality} disabled={!formats.includes("webp") || s.webpLossless} />
            <input type="number" min="1" max="100" aria-label="WebP quality, exact value" bind:value={s.webpQuality} disabled={!formats.includes("webp") || s.webpLossless} onchange={() => (s.webpQuality = Math.max(1, Math.min(100, Math.round(s.webpQuality || 90))))} />
          </span>
          <label title="True lossless in Chrome and Edge; other browsers write their highest quality"><input type="checkbox" bind:checked={s.webpLossless} disabled={!formats.includes("webp")} /> Lossless</label>
        </span>
      </div>
      {#if unavailable.webp}<p class="note">{unavailable.webp}</p>{/if}

      <div class="fmt">
        <label class="opt"><input type="checkbox" checked={s.formats.includes("svg")} onchange={(e) => toggle("svg", e.currentTarget.checked)} /> SVG</label>
        <span class="more muted">Vector drawing, sharp at any zoom.</span>
      </div>

      <div class="fmt">
        <label class="opt"><input type="checkbox" checked={s.formats.includes("pdf")} onchange={(e) => toggle("pdf", e.currentTarget.checked)} /> PDF</label>
        <span class="more">
          <span class="ctl">Crop marks
            <Select label="Crop marks" title="Auto: crop marks when the design has a bleed (canvas.bleed)" value={s.cropMarks} options={[{ value: "auto", label: "Auto" }, { value: "on", label: "On" }, { value: "off", label: "Off" }]} disabled={!s.formats.includes("pdf")} onchange={(v) => (s.cropMarks = v as ExportSettings["cropMarks"])} />
          </span>
          <span class="ctl">Pages
            <Select label="Pages" value={s.pdfVector ? "vector" : "image"} options={[{ value: "vector", label: "Vector (sharp at any zoom)" }, { value: "image", label: "Image (like the PNG)" }]} disabled={!s.formats.includes("pdf")} onchange={(v) => (s.pdfVector = v === "vector")} />
          </span>
        </span>
      </div>
    </fieldset>

    <fieldset>
      <legend>Resolution</legend>
      <div class="row">
        <span class="btn-group" role="radiogroup" aria-label="Resolution">
          {#each SCALES as k (k)}
            {@const ok = allowed(k)}
            <button type="button" role="radio" aria-checked={s.scale === k} class:active={s.scale === k} disabled={!ok} title={ok ? `${k} times the design size` : `Over the limit of ${MAX_SIDE} pixels per side`} onclick={() => (s.scale = k)}>{k}x</button>
          {/each}
        </span>
        <span class="muted">
          {#if size}{size.w} × {size.h} px{:else}Size not known yet{/if}
        </span>
      </div>
      <p class="note">
        {#if rasterChosen || !vectorChosen}The printed size stays the same: the dpi grows with the resolution.{/if}
        {#if vectorChosen}Vector files use it only for the parts that stay pixels.{/if}
      </p>
      {#if !fits}<p class="note warn" role="alert">Over the limit of {MAX_SIDE} pixels per side; choose a lower resolution.</p>{/if}
    </fieldset>

    {#if canServer}
      <fieldset>
        <legend>Where</legend>
        <label class="switch" title="Whole designs as PNG, SVG and PDF are rendered by the yoshida server this editor comes from, with all its CPU cores. JPEG, WebP and a single card render in this browser. The same setting as the switch next to the export buttons.">
          <input type="checkbox" role="switch" bind:checked={useServer} />
          <Icon name="cloud" />
          <span>Render on server</span>
        </label>
        <p class="note">{where}</p>
      </fieldset>
    {:else}
      <p class="note">{where}</p>
    {/if}
    <p class="summary" aria-live="polite">{planSummary(plan)}</p>

    <div class="actions">
      <button type="button" class="ghost" onclick={onclose}>Cancel</button>
      <button type="button" class="primary" onclick={submit} disabled={!canExport}>Export</button>
    </div>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(10, 10, 15, 0.45);
    display: grid;
    place-items: center;
  }
  .dialog {
    width: min(520px, calc(100vw - 32px));
    max-height: calc(100vh - 16px);
    overflow: auto;
    box-sizing: border-box;
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 12px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
    padding: 18px 18px 14px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .dialog:focus {
    outline: none;
  }
  h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
  }
  fieldset {
    margin: 0;
    padding: 8px 10px 10px;
    border: 1px solid var(--line);
    border-radius: 8px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  legend {
    padding: 0 4px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
  }
  label {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
  }
  .opt {
    min-height: 24px;
  }
  .opt input {
    width: 16px;
    height: 16px;
    margin: 0;
  }
  /* The format's checkbox, then its settings; settings that wrap stay in
     their column. */
  .fmt {
    display: grid;
    grid-template-columns: 72px 1fr;
    align-items: center;
    gap: 4px 14px;
    min-height: 28px;
  }
  .fmt > .opt {
    font-weight: 500;
  }
  .more {
    display: inline-flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 14px;
  }
  .more label,
  .ctl {
    color: var(--muted);
  }
  .ctl {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
  }
  input[type="number"] {
    width: 4.5em;
  }
  input[type="range"] {
    width: 96px;
    margin: 0;
  }
  input:disabled {
    opacity: 0.5;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  .btn-group {
    height: var(--ctl-h, 28px);
  }
  .btn-group button {
    min-width: 40px;
  }
  .muted {
    color: var(--muted);
    font-size: 13px;
  }
  .note {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }
  .note.warn {
    color: var(--warn-text);
  }
  .summary {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 4px;
  }
  .ghost {
    background: transparent;
  }
  .primary {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
    color: var(--on-accent);
    font-weight: 600;
  }
</style>
