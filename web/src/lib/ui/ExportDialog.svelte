<script lang="ts">
// The export dialog: what to export, in which formats and at which
// resolution. A modal like the ask/confirm dialogs: it is a short decision
// that ends in one action, and the export's progress window follows it.
// A format's settings show only while the format is chosen, so the dialog
// stays short.
import ColorPicker from "./ColorPicker.svelte";
import Icon from "./Icon.svelte";
import Select from "./Select.svelte";
import {
	type DesignOutput,
	type ExportFormat,
	type ExportSettings,
	MAX_SCALE,
	MAX_SIDE,
	MIN_SCALE,
	type PlanSet,
	SCALE_STEP,
	clampScale,
	cleanQuality,
	defaultExportSettings,
	designOutputs,
	dpiRange,
	fitScale,
	followsDpi,
	formatDpi,
	formatLabels,
	formatMm,
	formatScale,
	planExport,
	planSummary,
} from "../exportPlan";

let {
	initial,
	project,
	sets,
	current,
	card,
	webp,
	webpLossless,
	canServer,
	measuring,
	useServer = $bindable(false),
	onexport,
	onclose,
}: {
	initial: ExportSettings;
	project: string;
	/** The project's sets, with their canvases once they are measured. */
	sets: PlanSet[];
	/** The set shown, and the index of the card shown. */
	current: string;
	card: number;
	/** Whether this browser can encode WebP; null while checking. */
	webp: boolean | null;
	/** Whether this browser writes lossless WebP; null while checking. */
	webpLossless: boolean | null;
	/** Whether the server this editor comes from can render (shows the switch). */
	canServer: boolean;
	/** Whether the canvases are being measured. */
	measuring: boolean;
	/** Render on server (whole designs as PNG, SVG and PDF), the same setting as the toolbar switch. */
	useServer?: boolean;
	onexport: (s: ExportSettings) => void;
	onclose: () => void;
} = $props();

// svelte-ignore state_referenced_locally
let s = $state<ExportSettings>({ ...initial, formats: [...initial.formats] });
// A design with errors cannot be exported on its own: start with all designs.
// svelte-ignore state_referenced_locally
if (s.scope !== "all" && !sets.find((x) => x.name === current)?.ok)
	s.scope = "all";
let box: HTMLDivElement | undefined = $state();
/** The dpi field's text while it is typed in; otherwise it shows the dpi the resolution gives. */
let dpiText = $state<string | null>(null);
/** With only vector formats the resolution is one line until it is opened. */
let vectorRes = $state(false);

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
/** "A", "A and B", "A, B and C". */
const listOf = (names: string[]) =>
	names.length > 1
		? `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`
		: (names[0] ?? "");

const set = $derived(sets.find((x) => x.name === current));
const cardId = $derived(set?.cards[card] ?? "");
const okSets = $derived(sets.filter((x) => x.ok));
const allCards = $derived(okSets.reduce((a, x) => a + x.cards.length, 0));
const scopes = $derived([
	{ value: "card", label: "This card", disabled: !set?.ok },
	{ value: "design", label: "This design", disabled: !set?.ok },
	{ value: "all", label: "All designs", disabled: false },
] as const);
const scopeDetail = $derived(
	s.scope === "card"
		? cardId
			? `${set?.label ?? current} · card ${cardId}, ${card + 1} of ${set?.cards.length ?? 0}`
			: ""
		: s.scope === "design"
			? `${set?.label ?? current} · ${plural(set?.cards.length ?? 0, "card")}`
			: `${plural(okSets.length, "design")} · ${plural(allCards, "card")}`,
);
const unavailable = $derived<Partial<Record<ExportFormat, string>>>(
	webp === false
		? { webp: "This browser cannot write WebP images." }
		: webp === null
			? { webp: "Checking whether this browser can write WebP…" }
			: {},
);
/** The formats that will be written: chosen and available. */
const formats = $derived(s.formats.filter((f) => !unavailable[f]));
const chosen = (f: ExportFormat) => formats.includes(f);
const plan = $derived(
	planExport({ scope: s.scope, formats }, project, sets, current, card),
);
/** Vector formats use the resolution only for the parts that stay pixels. */
const vectorChosen = $derived(
	formats.includes("svg") || (formats.includes("pdf") && s.pdfVector),
);
const rasterChosen = $derived(
	formats.some((f) => f === "png" || f === "jpeg" || f === "webp") ||
		(formats.includes("pdf") && !s.pdfVector),
);
const vectorOnly = $derived(vectorChosen && !rasterChosen);
const folded = $derived(vectorOnly && !vectorRes);
/** WebP files carry no dpi; the other formats keep the printed size. */
const printSize = $derived(formats.some((f) => f !== "webp"));
/** Lossless WebP is offered where the browser really writes it. */
const lossless = $derived(webpLossless !== false);

/** The designs the export writes, and their canvases as far as they are known. */
const targets = $derived(
	plan.targets
		.map((t) => sets.find((x) => x.name === t.set))
		.filter((x): x is PlanSet => !!x),
);
const canvases = $derived(targets.flatMap((x) => (x.canvas ? [x.canvas] : [])));
/** The design the slider shows: the one in view when it is exported, else the first. */
const refSet = $derived(targets.find((x) => x.name === current) ?? targets[0]);
/** The design the dpi field starts from: the one above, or the first one with a dpi. */
const dpiRefSet = $derived(
	(refSet?.canvas?.dpi ?? 0) > 0
		? refSet
		: targets.find((x) => (x.canvas?.dpi ?? 0) > 0),
);
const dpiRef = $derived(dpiRefSet?.canvas ?? null);
/** Target dpis the designs reach between 1x and 4x. */
const range = $derived(dpiRange(canvases));
/** Each design at the scale that gives it the target dpi (else one scale for all). */
const byDpi = $derived(followsDpi(s, canvases) && !!dpiRef);
const clampDpi = (v: number) =>
	range ? Math.min(range.max, Math.max(range.min, v)) : v;
/** The designs have different dpis (or some have none): a target dpi gives them different scales. */
const mixed = $derived(
	!!dpiRef && new Set(canvases.map((c) => c.dpi)).size > 1,
);
/** The dpi every design has, so the slider's marks can show dpi; 0 when they differ. */
const sharedDpi = $derived(dpiRef && !mixed ? dpiRef.dpi : 0);
/** The slider: the scale, or with a target dpi the scale it gives the design above. */
const sliderScale = $derived(
	byDpi && dpiRef
		? clampScale(clampDpi(s.dpi) / dpiRef.dpi)
		: clampScale(s.scale),
);
/** The dpi field: the target, or what the slider gives the design above. */
const fieldDpi = $derived(
	dpiRef ? (byDpi ? clampDpi(s.dpi) : dpiRef.dpi * sliderScale) : 0,
);
const outputs = $derived(
	designOutputs(plan, sets, {
		resolution: s.resolution,
		dpi: s.dpi,
		scale: sliderScale,
	}),
);
/** The output the slider stands for. */
const refOut = $derived(
	outputs.find((o) => o.set === (byDpi ? dpiRefSet : refSet)?.name) ??
		outputs[0],
);
/** Images over the core's pixel limit; vector files have none. */
const over = $derived(rasterChosen ? outputs.filter((o) => !o.fits) : []);
/** The slider position from which some design is over the limit (unrounded). */
const limit = $derived(
	rasterChosen
		? fitScale(canvases, byDpi, dpiRef?.dpi ?? 1)
		: Number.POSITIVE_INFINITY,
);
/** The highest slider stop within the limit; null when even 1x is over. */
const fix = $derived.by(() => {
	const k = Math.min(
		MAX_SCALE,
		Math.floor(limit / SCALE_STEP + 1e-9) * SCALE_STEP,
	);
	if (!(k >= MIN_SCALE)) return null;
	const r =
		byDpi && dpiRef
			? { resolution: "dpi" as const, dpi: k * dpiRef.dpi, scale: k }
			: { resolution: "scale" as const, dpi: s.dpi, scale: k };
	return designOutputs(plan, sets, r).every((o) => o.fits) ? r : null;
});

const sameOutput = (a: DesignOutput, b: DesignOutput) =>
	a.size?.w === b.size?.w &&
	a.size?.h === b.size?.h &&
	a.dpi === b.dpi &&
	a.scale === b.scale;
/** The designs, those that come out the same in one row. */
const rows = $derived.by(() => {
	const groups: { labels: string[]; o: DesignOutput }[] = [];
	for (const o of outputs) {
		const g = groups.find((x) => sameOutput(x.o, o));
		if (g) g.labels.push(o.label);
		else groups.push({ labels: [o.label], o });
	}
	return groups;
});
const known = $derived(outputs.filter((o) => o.size));
/** The table shows the scale and the dpi only where the designs differ. */
const scalesDiffer = $derived(new Set(known.map((o) => o.scale)).size > 1);
const dpisDiffer = $derived(new Set(known.map((o) => o.dpi)).size > 1);
/** "2x", or "1–4x" when the designs get different scales. */
const readout = $derived.by(() => {
	if (!scalesDiffer) return formatScale(sliderScale);
	const ks = known.map((o) => o.scale);
	return `${formatScale(Math.min(...ks)).slice(0, -1)}–${formatScale(Math.max(...ks))}`;
});
const valueText = $derived(
	[
		readout,
		refOut?.size ? `${refOut.size.w} × ${refOut.size.h} px` : "",
		refOut?.dpi ? `${formatDpi(refOut.dpi)} dpi` : "",
	]
		.filter(Boolean)
		.join(", "),
);
const fraction = (k: number) => (k - MIN_SCALE) / (MAX_SCALE - MIN_SCALE);
const quality = (q: number) => Math.max(0, Math.min(1, (q - 5) / 95));

/** The dpi field's text as a number while it is typed in. */
const typed = $derived(
	dpiText === null
		? null
		: dpiText.trim() === ""
			? Number.NaN
			: Number(dpiText),
);
const dpiInvalid = $derived(typed !== null && !(typed > 0));
const dpiOutside = $derived(
	typed !== null &&
		typed > 0 &&
		!!range &&
		(typed < range.min || typed > range.max),
);
const rangeNote = $derived(
	range
		? `${formatDpi(range.min)} to ${formatDpi(range.max)} dpi${mixed ? " for these designs" : " (1x to 4x)"}`
		: "",
);

/** "1500 × 2100 px · prints at 63.5 × 88.9 mm"; the pixels only while measuring. */
function sizeLine(o: DesignOutput): string {
	if (!o.size) return measuring ? "Measuring…" : "Size not known yet";
	const parts = [`${o.size.w} × ${o.size.h} px`];
	if (printSize)
		parts.push(
			o.mm
				? `prints at ${formatMm(o.mm)}${o.trim ? `, trim ${formatMm(o.trim)}` : ""}`
				: "no dpi in the design",
		);
	return parts.join(" · ");
}
const rowLabel = (labels: string[]) =>
	labels.length > 1 ? `${labels[0]} and ${labels.length - 1} more` : labels[0];

const overText = $derived.by(() => {
	if (!over.length) return "";
	const who =
		outputs.length > 1
			? `${over[0].label}${over.length > 1 ? ` and ${plural(over.length - 1, "more design")} are` : " is"} over`
			: "Over";
	return fix
		? `${who} the limit of ${MAX_SIDE} px on each side.`
		: `${who} the limit of ${MAX_SIDE} px on each side even at 1x; SVG and vector PDF have no limit.`;
});

const server = $derived(canServer && useServer);
const where = $derived.by(() => {
	if (!server) return "Everything renders in this browser.";
	if (s.scope === "card")
		return "A single card always renders in this browser.";
	// JPEG and WebP are encoded by the browser, so they render here.
	const names = (fs: ExportFormat[]) => fs.map((f) => formatLabels[f]);
	const there = formats.filter((f) => f !== "jpeg" && f !== "webp");
	const here = formats.filter((f) => f === "jpeg" || f === "webp");
	const verb = here.length > 1 ? "render" : "renders";
	if (!here.length) return "The server renders everything.";
	if (!there.length)
		return `${listOf(names(here))} always ${verb} in this browser.`;
	return `The server renders ${listOf(names(there))}; ${listOf(names(here))} ${verb} in this browser.`;
});

/** Why Export is off, said in place of the summary; empty when it is on. */
const blocked = $derived.by(() => {
	if (!formats.length)
		return !s.formats.length
			? "Choose at least one format."
			: webp === null
				? "Checking whether this browser can write WebP…"
				: "This browser cannot write WebP: choose another format.";
	if (!plan.targets.length)
		return plan.skipped.length
			? `Nothing to export: ${listOf(plan.skipped)} ${plan.skipped.length > 1 ? "have" : "has"} errors.`
			: "Nothing to export: no cards.";
	if (dpiInvalid && range) return `Type a dpi from ${rangeNote}.`;
	if (rasterChosen && measuring && outputs.some((o) => !o.size))
		return "Measuring the designs…";
	if (over.length)
		return `Over the limit of ${MAX_SIDE} px on each side: lower the resolution.`;
	return "";
});
const canExport = $derived(!blocked && plan.files > 0);

function toggle(f: ExportFormat, on: boolean) {
	s.formats = on
		? [...new Set([...s.formats, f])]
		: s.formats.filter((x) => x !== f);
}

function setScale(k: number) {
	s.scale = clampScale(k);
	s.resolution = "scale";
	dpiText = null;
}

/** PageUp and PageDown jump to the next whole multiple. */
function wholeSteps(e: KeyboardEvent) {
	if (e.key !== "PageUp" && e.key !== "PageDown") return;
	e.preventDefault();
	const k = sliderScale;
	setScale(
		e.key === "PageUp" ? Math.floor(k + 1e-9) + 1 : Math.ceil(k - 1e-9) - 1,
	);
}

/** Same dpi (each design at its own scale) or same scale for every design. */
function setMode(mode: "dpi" | "scale") {
	if (mode === "dpi") s.dpi = clampDpi(fieldDpi);
	else s.scale = sliderScale;
	s.resolution = mode;
	dpiText = null;
}

function typeDpi(text: string) {
	dpiText = text;
	const v = Number(text);
	if (text.trim() !== "" && Number.isFinite(v) && v > 0) {
		s.dpi = v;
		s.resolution = "dpi";
		// The slider keeps its place for a design without a dpi.
		if (dpiRef) s.scale = clampScale(clampDpi(v) / dpiRef.dpi);
	}
}

/**
 * The dpi field is done: the dpi stays within what the designs reach, and
 * text that is not a dpi gives way to the last one. True when the field
 * then shows something else than what was typed.
 */
function commitDpi(): boolean {
	if (dpiText === null) return false;
	const was = typed;
	if (s.resolution === "dpi") s.dpi = clampDpi(s.dpi);
	dpiText = null;
	return Number(formatDpi(fieldDpi)) !== was;
}

/** Typed qualities within 1 to 100; true when one changed. */
function cleanQualities(): boolean {
	const d = defaultExportSettings;
	const jpeg = cleanQuality(s.jpegQuality, d.jpegQuality);
	const webpQ = cleanQuality(s.webpQuality, d.webpQuality);
	const changed = jpeg !== s.jpegQuality || webpQ !== s.webpQuality;
	s.jpegQuality = jpeg;
	s.webpQuality = webpQ;
	return changed;
}

function fitLimit() {
	if (!fix) return;
	s.resolution = fix.resolution;
	s.scale = fix.scale;
	if (fix.resolution === "dpi") s.dpi = fix.dpi;
	dpiText = null;
	// The button goes away: the focus moves to the control that changed.
	requestAnimationFrame(() =>
		box
			?.querySelector<HTMLElement>(
				fix?.resolution === "dpi" ? ".dpi input" : "input.scale",
			)
			?.focus(),
	);
}

function openResolution() {
	vectorRes = true;
	requestAnimationFrame(() =>
		box?.querySelector<HTMLElement>("input.scale")?.focus(),
	);
}

function submit() {
	// A typed value that changes when it is committed is shown first.
	const changed = commitDpi();
	if (cleanQualities() || changed || !canExport) return;
	onexport({
		...s,
		formats,
		webpLossless: s.webpLossless && lossless,
		scale: sliderScale,
		dpi: byDpi ? clampDpi(s.dpi) : s.dpi,
	});
}

/** A dropdown list or color picker is open; it takes Enter and Escape. */
const popupOpen = () => !!box?.querySelector("[role=listbox], [role=dialog]");

/** What Tab reaches: enabled controls, and of radio buttons the checked one. */
const focusable = () =>
	[
		...(box?.querySelectorAll<HTMLElement>(
			"button, input, [tabindex]:not([tabindex='-1'])",
		) ?? []),
	].filter(
		(el) =>
			!(el as HTMLButtonElement).disabled &&
			!(el instanceof HTMLInputElement && el.type === "radio" && !el.checked),
	);

function onkeydown(e: KeyboardEvent) {
	// An open dropdown list or color picker takes Escape and Enter (the color
	// picker listens on the window).
	if ((e.key === "Escape" || e.key === "Enter") && popupOpen()) return;
	// The editor's shortcuts stay off behind the dialog.
	e.stopPropagation();
	if (e.defaultPrevented) return;
	if (e.key === "Escape") {
		e.preventDefault();
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

/** Keys while the focus is outside the dialog (a control it was on went away). */
function onWindowKey(e: KeyboardEvent) {
	if (!box || box.contains(document.activeElement)) return;
	e.stopPropagation();
	if (e.key === "Escape") {
		e.preventDefault();
		onclose();
	} else if (e.key === "Tab") {
		e.preventDefault();
		const list = focusable();
		(e.shiftKey ? list[list.length - 1] : list[0])?.focus();
	}
}

$effect(() => {
	const first = box?.querySelector<HTMLInputElement>(
		"input[name='export-scope']:checked:not(:disabled)",
	);
	(first ?? focusable()[0])?.focus();
});
</script>

<svelte:window onkeydowncapture={onWindowKey} />

<div class="backdrop" role="presentation" onpointerdown={(e) => e.target === e.currentTarget && onclose()}>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div bind:this={box} class="dialog" role="dialog" aria-modal="true" aria-labelledby="export-title" tabindex="-1" {onkeydown}>
    <h2 id="export-title">Export</h2>

    <div class="form">
      <span class="label" id="export-what">What</span>
      <div class="body what">
        <div class="seg" role="radiogroup" aria-labelledby="export-what">
          {#each scopes as o (o.value)}
            <label class:on={s.scope === o.value} class:off={o.disabled}>
              <input type="radio" name="export-scope" value={o.value} bind:group={s.scope} disabled={o.disabled} />
              {o.label}
            </label>
          {/each}
        </div>
        {#if scopeDetail}<p class="note">{scopeDetail}</p>{/if}
        {#if plan.skipped.length}
          <p class="note warn">Skipped because they have errors: {plan.skipped.join(", ")}.</p>
        {/if}
      </div>

      <span class="label" id="export-formats">Formats</span>
      <div class="body formats" role="group" aria-labelledby="export-formats">
        <div class="fmt">
          <label class="opt"><input type="checkbox" checked={s.formats.includes("png")} aria-describedby={chosen("png") ? undefined : "export-about-png"} onchange={(e) => toggle("png", e.currentTarget.checked)} /> PNG</label>
          {#if chosen("png")}
            <span class="more">
              <span class="ctl">Bit depth
                <Select label="Bit depth" title="Bits per color channel. 16 bit gives smoother gradients and files about twice the size; PNG has no 10 bit mode." value={String(s.pngDepth)} options={[{ value: "8", label: "8 bit" }, { value: "16", label: "16 bit", detail: "smoother gradients" }]} onchange={(v) => (s.pngDepth = v === "16" ? 16 : 8)} />
              </span>
              <span class="ctl">Compression
                <Select label="Compression" title="The pixels are the same at every level; only the file size and the time change" value={s.pngCompression} options={[{ value: "fast", label: "Fast", detail: "larger files" }, { value: "default", label: "Default" }, { value: "smallest", label: "Smallest", detail: "slower" }]} onchange={(v) => (s.pngCompression = v as ExportSettings["pngCompression"])} />
              </span>
            </span>
          {:else}
            <span class="more muted" id="export-about-png">Lossless, with transparency</span>
          {/if}
        </div>

        <div class="fmt">
          <label class="opt"><input type="checkbox" checked={s.formats.includes("jpeg")} aria-describedby={chosen("jpeg") ? undefined : "export-about-jpeg"} onchange={(e) => toggle("jpeg", e.currentTarget.checked)} /> JPEG</label>
          {#if chosen("jpeg")}
            <span class="more">
              <span class="ctl">Quality
                <input type="range" class="slider" min="5" max="100" step="5" aria-label="JPEG quality" title="Steps of 5; type an exact value in the field" style:--f={quality(s.jpegQuality)} bind:value={s.jpegQuality} />
                <input type="number" min="1" max="100" aria-label="JPEG quality, exact value" bind:value={s.jpegQuality} onchange={() => (s.jpegQuality = cleanQuality(s.jpegQuality, defaultExportSettings.jpegQuality))} />
              </span>
              <span class="ctl">Background
                <ColorPicker title="JPEG background: transparent parts are shown on this color" value={s.jpegBackground} onchange={(v) => (s.jpegBackground = v.slice(0, 7))} />
              </span>
            </span>
          {:else}
            <span class="more muted" id="export-about-jpeg">Small files, no transparency</span>
          {/if}
        </div>

        <div class="fmt">
          <label class="opt" title={unavailable.webp}><input type="checkbox" checked={s.formats.includes("webp") && !unavailable.webp} disabled={!!unavailable.webp} aria-describedby={chosen("webp") ? undefined : "export-about-webp"} onchange={(e) => toggle("webp", e.currentTarget.checked)} /> WebP</label>
          {#if chosen("webp")}
            <span class="more">
              <span class="ctl">Quality
                <input type="range" class="slider" min="5" max="100" step="5" aria-label="WebP quality" title="Steps of 5; type an exact value in the field" style:--f={quality(s.webpQuality)} bind:value={s.webpQuality} disabled={s.webpLossless && lossless} />
                <input type="number" min="1" max="100" aria-label="WebP quality, exact value" bind:value={s.webpQuality} disabled={s.webpLossless && lossless} onchange={() => (s.webpQuality = cleanQuality(s.webpQuality, defaultExportSettings.webpQuality))} />
              </span>
              {#if lossless}
                <label class="ctl" title="Exact pixels, larger files"><input type="checkbox" bind:checked={s.webpLossless} /> Lossless</label>
              {/if}
            </span>
          {:else}
            <span class="more muted" id="export-about-webp">{unavailable.webp ?? "Small files, with transparency"}</span>
          {/if}
        </div>

        <div class="fmt">
          <label class="opt"><input type="checkbox" checked={s.formats.includes("svg")} aria-describedby="export-about-svg" onchange={(e) => toggle("svg", e.currentTarget.checked)} /> SVG</label>
          <span class="more muted" id="export-about-svg">Vector, sharp at any size</span>
        </div>

        <div class="fmt">
          <label class="opt"><input type="checkbox" checked={s.formats.includes("pdf")} aria-describedby={chosen("pdf") ? undefined : "export-about-pdf"} onchange={(e) => toggle("pdf", e.currentTarget.checked)} /> PDF</label>
          {#if chosen("pdf")}
            <span class="more">
              <span class="ctl">Pages as
                <Select label="Pages as" value={s.pdfVector ? "vector" : "image"} options={[{ value: "vector", label: "Vector", detail: "sharp at any size" }, { value: "image", label: "Image", detail: "like the PNG" }]} onchange={(v) => (s.pdfVector = v === "vector")} />
              </span>
              <span class="ctl">Crop marks
                <Select label="Crop marks" title="Auto: crop marks when the design has a bleed, the edge that is cut off (canvas.bleed)" value={s.cropMarks} options={[{ value: "auto", label: "Auto", detail: "when the design has a bleed" }, { value: "on", label: "On" }, { value: "off", label: "Off" }]} onchange={(v) => (s.cropMarks = v as ExportSettings["cropMarks"])} />
              </span>
            </span>
          {:else}
            <span class="more muted" id="export-about-pdf">For print: one PDF per design, a page per card</span>
          {/if}
        </div>
      </div>

      <span class="label" id="export-resolution">Resolution</span>
      <div class="body resolution" role="group" aria-labelledby="export-resolution">
        {#if folded}
          <p class="note fold">
            SVG and vector PDF are sharp at any size; effects such as sharpen are drawn at {readout}.
            <button type="button" class="link" onclick={openResolution}>Change</button>
          </p>
        {:else}
          <div class="res">
            <span class="track">
              <input type="range" class="slider scale" class:derived={scalesDiffer} min={MIN_SCALE} max={MAX_SCALE} step={SCALE_STEP} value={sliderScale} aria-label="Resolution" aria-valuetext={valueText} aria-describedby="export-res-keys" title="1x is the design's own size; the printed size stays the same and the dpi grows with it. Quarter steps; Page Up and Page Down jump to whole multiples." style:--f={fraction(sliderScale)} style:--lim={limit < MAX_SCALE ? fraction(Math.max(MIN_SCALE, limit)) : 2} oninput={(e) => setScale(Number(e.currentTarget.value))} onkeydown={wholeSteps} />
              <span class="ticks" aria-hidden="true">
                {#each [1, 2, 3, 4] as k (k)}<span style:--t={fraction(k)}>{sharedDpi ? formatDpi(sharedDpi * k) : `${k}x`}</span>{/each}
              </span>
              <span id="export-res-keys" hidden>Arrow keys move a quarter step; Page Up and Page Down jump to whole multiples.</span>
            </span>
            {#if range && dpiRef}
              <span class="dpi">
                <input type="number" min={range.min} max={range.max} step={dpiRef.dpi * SCALE_STEP} aria-label="Target dpi" aria-invalid={dpiInvalid || dpiOutside} aria-describedby={dpiInvalid || dpiOutside ? "export-dpi-range" : undefined} title={`Type the dpi you need: ${rangeNote}. Each design renders at the scale that gives it this dpi.`} value={dpiText ?? formatDpi(fieldDpi)} oninput={(e) => typeDpi(e.currentTarget.value)} onchange={commitDpi} onblur={commitDpi} />
                dpi
              </span>
            {/if}
            <output class="k" class:range={scalesDiffer} aria-hidden="true">{readout}</output>
          </div>
          {#if (dpiInvalid || dpiOutside) && range}
            <p class="note" id="export-dpi-range">{rangeNote}{dpiOutside ? "; the nearest is used" : ""}.</p>
          {/if}
          {#if mixed}
            <div class="mode" role="radiogroup" aria-labelledby="export-mode">
              <span id="export-mode">Designs differ in dpi:</span>
              <label><input type="radio" name="export-mode" checked={byDpi} onchange={() => setMode("dpi")} /> same dpi</label>
              <label><input type="radio" name="export-mode" checked={!byDpi} onchange={() => setMode("scale")} /> same scale</label>
            </div>
          {/if}
          {#if vectorOnly}
            <p class="note">In SVG and vector PDF only effects drawn as pixels, such as sharpen, use the resolution.</p>
          {:else if rows.length === 1}
            <p class="note size" class:warn={over.length > 0}>{outputs.length > 1 ? "Each design: " : ""}{sizeLine(rows[0].o)}</p>
          {:else if rows.length}
            <table class="per-design">
              <thead>
                <tr>
                  <th scope="col" class="name">Design</th>
                  <th scope="col" class="px">Size</th>
                  {#if scalesDiffer}<th scope="col" class="num">Scale</th>{/if}
                  {#if dpisDiffer}<th scope="col" class="num">dpi</th>{/if}
                </tr>
              </thead>
              <tbody>
                {#each rows as r (r.o.set)}
                  <tr class:warn={rasterChosen && !r.o.fits}>
                    <th scope="row" class="name" title={r.labels.join(", ")}>{rowLabel(r.labels)}</th>
                    <td>{r.o.size ? `${r.o.size.w} × ${r.o.size.h} px` : measuring ? "…" : "not known"}</td>
                    {#if scalesDiffer}<td>{formatScale(r.o.scale)}</td>{/if}
                    {#if dpisDiffer}<td>{r.o.dpi ? formatDpi(r.o.dpi) : r.o.size ? "no dpi" : ""}</td>{/if}
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
          {#if over.length}
            <p class="note warn" role="alert">
              {overText}
              {#if fix}<button type="button" class="link" onclick={fitLimit}>Use {fix.resolution === "dpi" ? `${formatDpi(fix.dpi)} dpi` : formatScale(fix.scale)}, the largest that fits</button>{/if}
            </p>
          {/if}
        {/if}
      </div>

      {#if canServer}
        <span class="label" id="export-where">Rendering</span>
        <div class="body where">
          <label class="switch" title="Renders whole designs as PNG, SVG and PDF on the yoshida server this editor comes from, with all its CPU cores. The same setting as the switch next to the export buttons.">
            <input type="checkbox" role="switch" bind:checked={useServer} />
            <Icon name="cloud" />
            <span>Render on server</span>
          </label>
          <p class="note">{where}</p>
        </div>
      {/if}
    </div>

    <div class="foot">
      <p class="summary" class:warn={!!blocked} id="export-summary" aria-live="polite">{blocked || planSummary(plan)}</p>
      <button type="button" class="ghost" onclick={onclose}>Cancel</button>
      <button type="button" class="primary" onclick={submit} aria-disabled={!canExport} aria-describedby="export-summary">Export</button>
    </div>
  </div>
</div>

<style>
  /* Anchored near the top, so the dialog grows downwards and its controls
     stay in place when a note or the table comes and goes. */
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(10, 10, 15, 0.45);
    display: grid;
    justify-items: center;
    align-items: start;
    padding-top: min(10vh, 80px);
    box-sizing: border-box;
  }
  .dialog {
    width: min(580px, calc(100vw - 32px));
    max-height: calc(100vh - min(10vh, 80px) - 16px);
    overflow: auto;
    box-sizing: border-box;
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 12px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
    padding: 18px 20px 16px;
  }
  .dialog:focus {
    outline: none;
  }
  h2 {
    margin: 0 0 16px;
    font-size: 15px;
    font-weight: 600;
  }
  /* Section names in the left column, their controls on the right. */
  .form {
    display: grid;
    grid-template-columns: 84px minmax(0, 1fr);
    gap: 18px 12px;
    align-items: start;
  }
  .label {
    font-size: 11px;
    line-height: 26px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
  }
  .body {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }
  label {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
  }
  .where .switch {
    align-self: flex-start;
    min-height: 26px;
  }

  /* What: one control of three joined radio buttons. */
  .seg {
    display: inline-flex;
    align-self: flex-start;
    border: 1px solid var(--line-strong);
    border-radius: 6px;
    overflow: hidden;
  }
  /* The focus ring goes around the whole control, outside the filled
     segment (the focused radio is the checked one). */
  .seg:has(input:focus-visible) {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }
  .seg label {
    position: relative;
    min-height: 26px;
    padding: 0 12px;
    cursor: pointer;
    white-space: nowrap;
  }
  .seg label + label {
    border-left: 1px solid var(--line-strong);
  }
  /* The radio covers its segment: invisible, but it takes the clicks, the
     focus and the arrow keys. */
  .seg input {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    margin: 0;
    opacity: 0;
    cursor: inherit;
  }
  .seg label:hover:not(.on):not(.off) {
    background: var(--hover);
  }
  .seg label.on {
    background: var(--accent-strong);
    color: var(--on-accent);
  }
  .seg label.off {
    opacity: 0.5;
    cursor: default;
  }

  /* Formats: the checkbox, then the format's settings while it is chosen
     (a short description otherwise). */
  .fmt {
    display: grid;
    grid-template-columns: 68px minmax(0, 1fr);
    align-items: center;
    gap: 4px 12px;
    min-height: 28px;
  }
  .opt {
    min-height: 24px;
    font-weight: 500;
  }
  .opt input {
    width: 16px;
    height: 16px;
    margin: 0;
  }
  .more {
    display: inline-flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 14px;
  }
  .ctl {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    color: var(--muted);
  }
  /* Number fields with an edge of 3:1 and the editor's focus ring. */
  .dialog input[type="number"] {
    width: 4.5em;
    border-color: var(--line-strong);
  }
  .dialog input[type="number"]:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 1px;
  }
  .dialog input[type="number"][aria-invalid="true"] {
    border-color: var(--warn-text);
  }
  input:disabled {
    opacity: 0.5;
  }
  .muted {
    color: var(--muted);
    font-size: 13px;
  }

  /* Sliders: a thin track filled up to the thumb (--f, 0 to 1); the
     resolution marks the scales over the pixel limit (from --lim). The
     track is one background (--track) for both engines. ".dialog" makes
     these win over the global style for text fields. */
  .dialog input[type="range"].slider {
    --thumb: 14px;
    --fill: var(--accent-strong);
    --at: calc(var(--thumb) / 2 + (100% - var(--thumb)) * var(--f, 0));
    --track: linear-gradient(to right, var(--fill) var(--at), var(--line-strong) 0);
    appearance: none;
    width: 96px;
    height: 24px;
    margin: 0;
    padding: 0;
    border: 0;
    border-radius: 0;
    background: transparent;
    cursor: pointer;
  }
  .dialog input[type="range"].slider:disabled {
    cursor: default;
  }
  .dialog input[type="range"].slider:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
    border-radius: 4px;
  }
  .slider::-webkit-slider-runnable-track {
    height: 4px;
    border-radius: 2px;
    background: var(--track);
  }
  .slider::-moz-range-track {
    height: 4px;
    border-radius: 2px;
    background: var(--track);
  }
  .slider::-webkit-slider-thumb {
    appearance: none;
    width: var(--thumb);
    height: var(--thumb);
    margin-top: calc((4px - var(--thumb)) / 2);
    border-radius: 50%;
    background: var(--on-accent);
    border: 2px solid var(--accent-strong);
    box-sizing: border-box;
    box-shadow: 0 1px 2px rgb(0 0 0 / 0.3);
  }
  .slider::-moz-range-thumb {
    width: var(--thumb);
    height: var(--thumb);
    border-radius: 50%;
    background: var(--on-accent);
    border: 2px solid var(--accent-strong);
    box-sizing: border-box;
    box-shadow: 0 1px 2px rgb(0 0 0 / 0.3);
  }
  .dialog input[type="range"].slider.scale {
    --track:
      linear-gradient(
        to right,
        transparent calc(var(--thumb) / 2 + (100% - var(--thumb)) * var(--lim, 2)),
        var(--warn) 0
      ),
      linear-gradient(to right, var(--fill) var(--at), var(--line-strong) 0);
    width: 100%;
    height: 26px;
  }
  /* The designs get different scales: the thumb shows only the one in view. */
  .dialog input[type="range"].slider.derived {
    --fill: var(--muted);
  }

  /* Resolution: the slider with its marks, the dpi field and the scale. */
  .res {
    display: flex;
    align-items: flex-start;
    gap: 12px;
  }
  .track {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
    max-width: 240px;
  }
  .ticks {
    position: relative;
    height: 14px;
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .ticks span {
    position: absolute;
    top: 0;
    left: calc(7px + (100% - 14px) * var(--t));
    transform: translateX(-50%);
  }
  .dpi {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 26px;
    font-size: 13px;
    color: var(--muted);
  }
  .dialog .dpi input {
    width: 5.5em;
  }
  .k {
    min-width: 3.4em;
    line-height: 26px;
    font-size: 13px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .k.range {
    color: var(--muted);
    font-weight: 500;
  }
  .mode {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 2px 14px;
    font-size: 12px;
    color: var(--muted);
  }
  .mode label {
    font-size: 12px;
    color: var(--fg);
    gap: 5px;
  }
  .mode input {
    margin: 0;
  }
  .per-design {
    width: 100%;
    table-layout: fixed;
    border-collapse: collapse;
    font-size: 12px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .per-design th,
  .per-design td {
    padding: 1px 10px 1px 0;
    text-align: left;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .per-design thead th {
    font-size: 11px;
    font-weight: 500;
    color: var(--muted);
  }
  .per-design tbody th {
    font-weight: 500;
    color: var(--fg);
  }
  .per-design .px {
    width: 9.5em;
  }
  .per-design .num {
    width: 4.2em;
  }
  .per-design tr.warn,
  .per-design tr.warn th {
    color: var(--warn-text);
  }

  .note {
    margin: 0;
    font-size: 12px;
    color: var(--muted);
  }
  .note.warn {
    color: var(--warn-text);
  }
  /* A link-like button with a target of 24 px. */
  .link {
    display: inline-block;
    padding: 4px 2px;
    margin: -4px 0;
    border: 0;
    background: none;
    color: light-dark(var(--accent-strong), var(--accent));
    font-size: 12px;
    font-weight: 600;
    text-decoration: underline;
    white-space: nowrap;
  }

  .foot {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 18px;
    padding-top: 14px;
    border-top: 1px solid var(--line);
  }
  .summary {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    overflow-wrap: anywhere;
  }
  .summary.warn {
    color: var(--warn-text);
  }
  .ghost {
    margin-left: auto;
    background: transparent;
    border-color: var(--line-strong);
  }
  .primary {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
    color: var(--on-accent);
    font-weight: 600;
  }
  /* Off but still in the tab order, so the reason next to it can be found. */
  .primary[aria-disabled="true"] {
    opacity: 0.5;
    cursor: default;
  }

  /* Narrow windows: the section names go above their controls. */
  @media (max-width: 560px) {
    .form {
      grid-template-columns: minmax(0, 1fr);
      gap: 4px;
    }
    .label:not(:first-child) {
      margin-top: 12px;
    }
    .foot {
      flex-wrap: wrap;
    }
    .summary {
      flex-basis: 100%;
    }
  }
</style>
