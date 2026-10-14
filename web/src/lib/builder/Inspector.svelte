<script module lang="ts">
/** The last go to definition request handled (see `focus`). */
let handled = 0;
</script>

<script lang="ts">
// Properties of the selected layer, or of the design itself when nothing
// is selected. Every field accepts a literal or an expression; fields a
// layer inherits through `extends` are marked and editing them adds an
// override to this layer.
import { setContext, tick } from "svelte";
import {
	type AlignMode,
	ancestorsOf,
	anchors,
	childrenOf,
	effectiveLayer,
	findLayer as findIn,
	getPath,
	identRe,
	isObj,
	type Json,
	layerPointer,
	layersOf,
	newParam,
	type Obj,
	setPath,
	textAnchors,
} from "../design";
import type { Diagnostic } from "../engine";
import { layersUsing, removeFont, renameFont } from "../fonts/project";
import Icon from "../ui/Icon.svelte";
import ImagePicker from "../ui/ImagePicker.svelte";
import Select from "../ui/Select.svelte";
import { confirmAction } from "../ui/overlay.svelte";
import type { CompletionContext } from "./complete";
import Field from "./Field.svelte";
import Scope from "./Scope.svelte";

let {
	doc,
	ids,
	imageFiles,
	upload,
	fontFiles,
	fontFaces = {},
	fontLicenses = {},
	fontText = "",
	onfonts = () => {},
	diagnostics,
	designFile,
	editLayer,
	editDoc,
	rename,
	onalign,
	ondistribute,
	onduplicate,
	ondelete,
	ongroup,
	onungroup,
	onproblems,
	onback,
	listKeys = {},
	cardValues = {},
	focus = null,
}: {
	doc: Obj;
	ids: string[];
	imageFiles: string[];
	/** Adds an image from the user's computer; returns its project path. */
	upload: () => Promise<string | null>;
	fontFiles: string[];
	/** CSS font-family of each project font file, for previews (null: could not load). */
	fontFaces?: Record<string, string | null>;
	/** License tag of each project font file ("OFL", "Apache"...), "" when it has no license file. */
	fontLicenses?: Record<string, string>;
	/** The selected text layer's text as the current card shows it, for font previews. */
	fontText?: string;
	/** Opens the Fonts window (on a font file, or to upload one). */
	onfonts?: (target?: { path?: string; upload?: boolean }) => void;
	diagnostics: Diagnostic[];
	designFile: string;
	editLayer: (fn: (own: Obj) => void, key?: string) => void;
	editDoc: (fn: (doc: Obj) => void, key?: string) => void;
	rename: (from: string, to: string) => string;
	/** Key values of each list param, from the cards, for `list.Key` suggestions. */
	listKeys?: Record<string, string[]>;
	/** The current card's values, shown when hovering a param. */
	cardValues?: Record<string, unknown>;
	/** Scrolls to and highlights a part of the inspector (go to definition). */
	focus?: { key: string; n: number } | null;
	onalign: (mode: AlignMode) => void;
	ondistribute: (axis: "x" | "y") => void;
	onduplicate: () => void;
	ondelete: () => void;
	ongroup: () => void;
	onungroup: () => void;
	/** Shows the problems of a layer (or of the design, for null) in the problems panel. */
	onproblems: (id: string | null) => void;
	/** Clears the selection so the design settings show again. */
	onback: () => void;
} = $props();

const id = $derived(ids.length === 1 ? ids[0] : null);

const own = $derived(
	id ? (layersOf(doc).find((l) => l.id === id) ?? null) : null,
);
const eff = $derived(id ? (effectiveLayer(doc, id) ?? null) : null);
const ptr = $derived(id ? layerPointer(doc, id) : null);
const type = $derived(String(eff?.type ?? ""));
const params = $derived(
	isObj(doc.params)
		? (Object.entries(doc.params).filter(([, v]) => isObj(v)) as [
				string,
				Obj,
			][])
		: [],
);
const fonts = $derived(isObj(doc.fonts) ? Object.keys(doc.fonts) : []);

function paramsOfType(...types: string[]) {
	return params
		.filter(([, p]) => types.includes(String(p.type)))
		.map(([n]) => n);
}
const numberParams = $derived(paramsOfType("number", "integer"));
const colorParams = $derived(paramsOfType("color"));
const boolParams = $derived(paramsOfType("bool"));
const textParams = $derived(
	paramsOfType("text", "enum", "number", "integer", "color", "bool", "image"),
);
const imageParams = $derived(paramsOfType("image"));
const listParams = $derived(paramsOfType("list"));

/** Item field name → type name (enum fields are objects in the file). */
function itemTypes(item: Json | undefined): Record<string, string> {
	if (!isObj(item)) return {};
	return Object.fromEntries(
		Object.entries(item).map(([k, v]) => [
			k,
			isObj(v) ? String(v.type ?? "text") : String(v),
		]),
	);
}

const consts = $derived(
	isObj(doc.consts) ? Object.entries(doc.consts as Obj) : [],
);
const functions = $derived(
	isObj(doc.functions)
		? (Object.entries(doc.functions as Obj).filter(([, v]) => isObj(v)) as [
				string,
				Obj,
			][])
		: [],
);

function argsText(args: Json | undefined): string {
	if (Array.isArray(args)) return args.map(String).join(", ");
	if (isObj(args))
		return Object.entries(args)
			.map(([k, t]) => `${k}: ${t}`)
			.join(", ");
	return "";
}

function parseArgs(text: string): Obj {
	const out: Obj = {};
	for (const part of text.split(",")) {
		const [n, t] = part.split(":").map((x) => x.trim());
		if (n) out[n] = t || "number";
	}
	return out;
}

// Suggestions for expression fields (see ExprInput).
const completion = $derived.by((): CompletionContext => {
	const locals: CompletionContext["locals"] = [];
	// Loop names of the repeated groups around the layer, then its own.
	const owners = id
		? [
				...ancestorsOf(doc, id)
					.reverse()
					.map((a) => effectiveLayer(doc, a)),
				eff,
			]
		: [];
	for (const o of owners) {
		const rep = isObj(o?.repeat) ? (o!.repeat as Obj) : null;
		if (!rep) continue;
		const whose = o === eff ? "repeat" : `group ${o?.id}`;
		const source = { kind: "repeat" as const, layer: String(o?.id) };
		locals.push({
			name: String(rep.index ?? "i"),
			detail: `${whose} index`,
			source,
		});
		if (typeof rep.item === "string") {
			const each = String(rep.each ?? "");
			const p = params.find(([n]) => n === each.trim())?.[1];
			locals.push({
				name: rep.item,
				detail: `item of ${each}`,
				fields: itemTypes(p?.item),
				source,
			});
		}
	}
	return {
		consts: consts.map(([name, v]) => ({ name, expr: String(v) })),
		functions: functions.map(([name, f]) => ({
			name,
			args: argsText(f.args),
			expr: typeof f.expr === "string" ? f.expr : String(f.expr ?? ""),
			note: typeof f.note === "string" ? f.note : undefined,
		})),
		params: params.map(([name, p]) => ({
			name,
			type: String(p.type),
			item: isObj(p.item) ? itemTypes(p.item) : undefined,
			keys: listKeys[name],
			label: typeof p.label === "string" ? p.label : undefined,
			note: typeof p.note === "string" ? p.note : undefined,
			value: cardValues[name],
		})),
		layers: layersOf(doc)
			.filter((l) => l.id !== id && !l.repeat)
			.map((l) => ({ id: String(l.id), type: String(l.type) })),
		locals,
	};
});
setContext("yoshida-complete", () => completion);

/** A function's arguments as `name -> type` (an array of names is all numbers). */
function argTypes(args: Json | undefined): [string, string][] {
	if (Array.isArray(args)) return args.map((n) => [String(n), "number"]);
	if (isObj(args)) return Object.entries(args).map(([n, t]) => [n, String(t)]);
	return [];
}

// A function body sees its arguments, params, constants and the functions
// before it; not layers or repeat names (FORMAT.md 6.8).
function functionScope(name: string, fn: Obj): CompletionContext {
	const at = functions.findIndex(([n]) => n === name);
	return {
		...completion,
		functions: completion.functions?.slice(0, Math.max(0, at)),
		layers: [],
		locals: argTypes(fn.args).map(([n, t]) => ({
			name: n,
			detail: `argument of ${name}`,
			type: t,
			source: { kind: "function" as const, name },
		})),
	};
}

// Go to definition: scroll to the marked part (`data-goto`) and flash it.
let root: HTMLDivElement | undefined = $state();
$effect(() => {
	const f = focus;
	// Once per request: not again when the inspector is shown later.
	if (!f || !root || f.n === handled) return;
	handled = f.n;
	tick().then(() => {
		const el = root?.querySelector<HTMLElement>(
			`[data-goto="${CSS.escape(f.key)}"]`,
		);
		if (!el) return;
		el.scrollIntoView({ block: "center" });
		el.classList.remove("goto-flash");
		void el.offsetWidth;
		el.classList.add("goto-flash");
	});
});

// Problems are listed once, in the problems panel; fields only show a
// short note for their own errors.
const myDiags = $derived(
	diagnostics.filter(
		(d) =>
			d.file === designFile &&
			(ptr
				? (d.path === ptr || d.path.startsWith(`${ptr}/`)) &&
					!d.path.startsWith(`${ptr}/layers/`)
				: !d.path.startsWith("/layers/")),
	),
);
const errorCount = $derived(
	myDiags.filter((d) => d.severity === "error").length,
);
const warnCount = $derived(
	myDiags.filter((d) => d.severity === "warning").length,
);

/** JSON pointer of a field in the design file, escaped as in the core's diagnostics. */
function pathOf(path: string[]): string {
	const segs = path.map((s) => s.replace(/~/g, "~0").replace(/\//g, "~1"));
	return ptr ? `${ptr}/${segs.join("/")}` : `/${segs.join("/")}`;
}

function errorAt(path: string[]) {
	const p = pathOf(path);
	const d = myDiags.find(
		(x) =>
			x.severity === "error" && (x.path === p || x.path.startsWith(`${p}/`)),
	);
	return d ? d.message.replace(/^layer '[^']*': /, "") : "";
}

const ownVal = (path: string[]) => getPath(own ?? undefined, path);
const effVal = (path: string[]) => getPath(eff ?? undefined, path);

function set(path: string[], v: Json | undefined) {
	editLayer((l) => setPath(l, path, v), path.join("."));
}

function setDoc(path: string[], v: Json | undefined) {
	editDoc((d) => setPath(d, path, v), `doc.${path.join(".")}`);
}

let idError = $state("");
function renameTo(next: string) {
	if (!id || next === id) return;
	idError = rename(id, next);
}
$effect(() => {
	void id;
	idError = "";
});

const isGroupLayer = $derived(type === "group");
const childCount = $derived(own && isGroupLayer ? childrenOf(own).length : 0);
const sameTypeIds = $derived(
	layersOf(doc)
		.filter((l) => l.type === type && l.id !== id)
		.map((l) => String(l.id)),
);

// ------------------------------------------------------------ effects

const effectTypes = [
	"fade",
	"crop",
	"sharpen",
	"detail",
	"edge_enhance",
	"find_edges",
];
const effectHelp: Record<string, string> = {
	fade: "soft edge on one side",
	crop: "cut one side off",
	sharpen: "crisper details",
	detail: "boost fine detail",
	edge_enhance: "stronger edges",
	find_edges: "outline only",
};
const effects = $derived(
	Array.isArray(eff?.effects) ? (eff!.effects as Obj[]) : [],
);

function editEffects(fn: (list: Obj[]) => void, key?: string) {
	editLayer((l) => {
		const list = structuredClone(effects);
		fn(list);
		if (list.length) l.effects = list;
		else delete l.effects;
	}, key);
}

function newEffect(t: string): Obj {
	return t === "fade" || t === "crop"
		? { type: t, side: "bottom", length: 100 }
		: { type: t };
}

// ------------------------------------------------------------ repeat

const repeatMode = $derived(
	isObj(eff?.repeat)
		? (eff!.repeat as Obj).each !== undefined
			? "each"
			: "count"
		: "none",
);

function setRepeat(mode: string) {
	editLayer((l) => {
		if (mode === "none") delete l.repeat;
		else if (mode === "count")
			l.repeat = { count: numberParams[0] ?? 3, index: "i" };
		else
			l.repeat = { each: listParams[0] ?? "items", item: "item", index: "i" };
	});
}

/** `each` needs a list: without one, add an `items` list param in the same step. */
function setRepeatMode(mode: string) {
	if (mode !== "each" || listParams.length || !id) return setRepeat(mode);
	const target = id;
	editDoc((d) => {
		if (!isObj(d.params)) d.params = {};
		const ps = d.params as Obj;
		let name = "items";
		for (let n = 2; ps[name] !== undefined; n++) name = `items${n}`;
		ps[name] = newParam("list", imageFiles);
		const l = findIn(d, target);
		if (l) l.repeat = { each: name, item: "item", index: "i" };
	});
}

// ------------------------------------------------------------ polygon points

const points = $derived(
	Array.isArray(eff?.points) ? (eff!.points as Json[][]) : [],
);

function editPoints(fn: (pts: Json[][]) => void, key?: string) {
	editLayer((l) => {
		const pts = structuredClone(points);
		fn(pts);
		l.points = pts;
	}, key);
}

const isShape = $derived(type === "polygon" && isObj(eff?.shape));
const shapeTypes = [
	"star",
	"polygon",
	"triangle",
	"diamond",
	"arrow",
	"cross",
	"chevron",
];

/** Switches a polygon between its own points and a preset shape in a box. */
function setShapeMode(mode: string) {
	editLayer((l) => {
		if (mode === "shape") {
			const b = shapeBox();
			delete l.points;
			delete l.closed;
			l.shape = { type: "star" };
			l.box = b;
		} else {
			const box = isObj(l.box) ? (l.box as Obj) : {};
			const n = (v: Json | undefined, d: number) =>
				typeof v === "number" ? v : d;
			const x = n(box.x, 0);
			const y = n(box.y, 0);
			const w = n(box.w, 100);
			const h = n(box.h, 100);
			delete l.shape;
			delete l.box;
			l.points = [
				[x + w / 2, y],
				[x + w, y + h],
				[x, y + h],
			];
		}
	});
}

/** A box around a polygon's literal points (or a default). */
function shapeBox(): Obj {
	const xs: number[] = [];
	const ys: number[] = [];
	for (const p of points) {
		if (typeof p[0] === "number") xs.push(p[0]);
		if (typeof p[1] === "number") ys.push(p[1]);
	}
	if (!xs.length || !ys.length) return { x: 0, y: 0, w: 100, h: 100 };
	const x = Math.min(...xs);
	const y = Math.min(...ys);
	return {
		x,
		y,
		w: Math.max(1, Math.max(...xs) - x),
		h: Math.max(1, Math.max(...ys) - y),
	};
}

/** `[12, 6]` ⇄ "12, 6". */
function dashText(v: Json | undefined): string {
	return Array.isArray(v) ? v.map(String).join(", ") : "";
}

function parseDash(text: string): Json | undefined {
	const parts = text
		.split(",")
		.map((x) => x.trim())
		.filter(Boolean)
		.map((x) => (/^-?\d+(\.\d+)?$/.test(x) ? Number(x) : x));
	return parts.length ? parts : undefined;
}

function parseCoord(raw: string): Json {
	const s = raw.trim();
	return /^-?\d+(\.\d+)?$/.test(s) ? Number(s) : s;
}

// ------------------------------------------------------------ fonts

const fontEntries = $derived(
	isObj(doc.fonts) ? Object.entries(doc.fonts as Obj) : [],
);
const fontPathOf = (name: string) => {
	const p = isObj(doc.fonts) ? (doc.fonts as Obj)[name] : undefined;
	return typeof p === "string" ? p : "";
};
const faceOf = (name: string) => fontFaces[fontPathOf(name)] ?? null;
// Text for font previews: the selected text layer's text, shortened.
const fontSampleText = $derived(
	fontText && type === "text" ? fontText.slice(0, 18) : "Aa Bb Cc",
);
const sampleOf = (name: string) => {
	const family = faceOf(name);
	return family ? { family, text: fontSampleText } : undefined;
};
let fontError = $state({ name: "", msg: "" });
function renameFontTo(from: string, input: HTMLInputElement) {
	const to = input.value.trim();
	if (to === from) {
		fontError = { name: "", msg: "" };
		input.value = from;
		return;
	}
	const fail = (msg: string) => {
		fontError = { name: from, msg };
	};
	if (!identRe.test(to))
		return fail("Letters, digits and _ only, not starting with a digit");
	if (to === "default") return fail("'default' is the built-in font");
	if (fontEntries.some(([n]) => n === to))
		return fail(`There is already a font '${to}'`);
	fontError = { name: "", msg: "" };
	editDoc((d) => renameFont(d, from, to));
}
async function askRemoveFont(name: string) {
	const users = layersUsing(doc, name);
	const n = users.length;
	const more = n > 5 ? `, and ${n - 5} more` : "";
	const ok = await confirmAction({
		title: `Remove font '${name}'?`,
		message: n
			? `${n} ${n === 1 ? "layer uses" : "layers use"} it: ${users.slice(0, 5).join(", ")}${more}. ${n === 1 ? "It" : "They"} will use the default font. The font file stays in the project.`
			: "No layer uses it. The font file stays in the project.",
		confirm: "Remove",
		danger: true,
	});
	if (ok) editDoc((d) => removeFont(d, name));
}
const BROWSE = "\u0001browse";
const UPLOAD = "\u0001upload";
const fontOptions = $derived([
	{ value: "default", sample: sampleOf("default") },
	...fonts.filter((f) => f !== "default").map((f) => ({ value: f, sample: sampleOf(f) })),
	{ value: BROWSE, label: "Browse fonts…", divider: true, action: true },
	{ value: UPLOAD, label: "Upload font file…", action: true },
]);
function pickFont(v: unknown) {
	if (v === BROWSE) onfonts();
	else if (v === UPLOAD) onfonts({ upload: true });
	else set(["font"], v as string | undefined);
}
let newConst = $state("");
let newFunction = $state("");
</script>

{#snippet effectsSection()}
  <section>
    <h3>Effects</h3>
    {#each effects as fx, i}
      <div class="effect">
        <div class="effect-head">
          <strong>{fx.type}</strong>
          <span class="spacer"></span>
          <button class="mini" aria-label="Move effect up" title="Move up" disabled={i === 0} onclick={() => editEffects((l) => l.splice(i - 1, 0, ...l.splice(i, 1)))}><Icon name="up" /></button>
          <button class="mini" aria-label="Move effect down" title="Move down" disabled={i === effects.length - 1} onclick={() => editEffects((l) => l.splice(i + 1, 0, ...l.splice(i, 1)))}><Icon name="down" /></button>
          <button class="mini" aria-label="Remove effect" title="Remove" onclick={() => editEffects((l) => l.splice(i, 1))}><Icon name="close" /></button>
        </div>
        {#if fx.type === 'fade' || fx.type === 'crop'}
          <Field label="side" kind="enum" value={fx.side} options={['top', 'bottom', 'left', 'right']} onchange={(v) => editEffects((l) => (l[i].side = v ?? 'bottom'))} />
          <Field label="length" kind="number" value={fx.length} bindings={numberParams} error={errorAt(['effects', String(i)])} path={pathOf(['effects', String(i), 'length'])} onchange={(v) => editEffects((l) => (l[i].length = v ?? 0), `fx${i}.length`)} />
        {:else}
          <Field label="strength" kind="number" optional value={fx.strength} fallback={1} bindings={numberParams} error={errorAt(['effects', String(i)])} path={pathOf(['effects', String(i), 'strength'])} onchange={(v) => editEffects((l) => (v === undefined ? delete l[i].strength : (l[i].strength = v)), `fx${i}.strength`)} />
        {/if}
      </div>
    {/each}
    <Select value="" placeholder="+ Add effect…" label="Add effect" options={effectTypes.map((t) => ({ value: t, label: t, detail: effectHelp[t] }))} onchange={(t) => editEffects((l) => l.push(newEffect(t)))} />
  </section>
{/snippet}

{#snippet repeatSection()}
    <section data-goto="repeat">
      <h3>Repeat</h3>
      <div class="field-like">
        <span class="lbl">mode</span>
        <Select
          value={repeatMode}
          label="Repeat mode"
          options={[
            { value: 'none', label: 'none' },
            { value: 'count', label: 'count', detail: 'n times' },
            { value: 'each', label: 'each', detail: listParams.length ? 'once per list item' : 'adds a list param “items”' },
          ]}
          onchange={setRepeatMode} />
      </div>
      {#if repeatMode === 'count'}
        <Field label="count" kind="number" value={effVal(['repeat', 'count'])} bindings={numberParams} error={errorAt(['repeat', 'count'])} path={pathOf(['repeat', 'count'])} onchange={(v) => set(['repeat', 'count'], v)} />
      {:else if repeatMode === 'each'}
        <Field label="each" kind="expr" expect="list" value={effVal(['repeat', 'each'])} bindings={listParams} error={errorAt(['repeat', 'each'])} path={pathOf(['repeat', 'each'])} onchange={(v) => set(['repeat', 'each'], v)} />
        <Field label="item" kind="text" value={effVal(['repeat', 'item'])} placeholder="item" error={errorAt(['repeat', 'item'])} onchange={(v) => set(['repeat', 'item'], v)} />
      {/if}
      {#if repeatMode !== 'none'}
        <Field label="index" kind="text" optional value={effVal(['repeat', 'index'])} fallback="i" error={errorAt(['repeat', 'index'])} onchange={(v) => set(['repeat', 'index'], v)} />
        <p class="hint">{isGroupLayer ? 'The layers inside are drawn once per iteration and can use the index (and item) names, for example translate.x: 100 + i * 60. Read one iteration from elsewhere with @layer[i].' : "Use the index (and item) names in this layer's fields, for example x: 100 + i * 60. Read one iteration from elsewhere with @layer[i]."}</p>
      {/if}
    </section>

{/snippet}

{#snippet problemChip()}
  {#if errorCount || warnCount}
    <button class="probs" class:has-err={errorCount > 0} onclick={() => onproblems(id)} title="Show in the problems panel">
      {#if errorCount}<span class="e"><Icon name="close" />{errorCount} error{errorCount > 1 ? 's' : ''}</span>{/if}
      {#if warnCount}<span class="w"><Icon name="alert" />{warnCount} warning{warnCount > 1 ? 's' : ''}</span>{/if}
      <span class="go">show ›</span>
    </button>
  {/if}
{/snippet}

{#snippet alignBar(toCanvas: boolean)}
  {@const to = toCanvas ? ' to the canvas' : ''}
  {@const on = toCanvas ? ' on the canvas' : ''}
  <div class="align" role="group" aria-label="Align">
    <span class="btn-group">
      <button title="Align left{to}" aria-label="Align left{to}" onclick={() => onalign('left')}><Icon name="align-left" /></button>
      <button title="Center horizontally{on}" aria-label="Center horizontally{on}" onclick={() => onalign('hcenter')}><Icon name="align-hcenter" /></button>
      <button title="Align right{to}" aria-label="Align right{to}" onclick={() => onalign('right')}><Icon name="align-right" /></button>
    </span>
    <span class="btn-group">
      <button title="Align top{to}" aria-label="Align top{to}" onclick={() => onalign('top')}><Icon name="align-top" /></button>
      <button title="Center vertically{on}" aria-label="Center vertically{on}" onclick={() => onalign('vcenter')}><Icon name="align-vcenter" /></button>
      <button title="Align bottom{to}" aria-label="Align bottom{to}" onclick={() => onalign('bottom')}><Icon name="align-bottom" /></button>
    </span>
    {#if !toCanvas}
      <span class="btn-group">
        <button title="Distribute horizontally (equal gaps)" aria-label="Distribute horizontally" disabled={ids.length < 3} onclick={() => ondistribute('x')}><Icon name="distribute-x" /></button>
        <button title="Distribute vertically (equal gaps)" aria-label="Distribute vertically" disabled={ids.length < 3} onclick={() => ondistribute('y')}><Icon name="distribute-y" /></button>
      </span>
    {/if}
  </div>
{/snippet}

<div class="inspector" bind:this={root}>
  {#if ids.length}
    <nav class="crumb" aria-label="Inspector">
      <button class="back" onclick={onback} title="Back to the design settings (Esc)">‹ Design settings</button>
      <span class="sep" aria-hidden="true">/</span>
      <span class="here" title={ids.join(', ')}>{ids.length === 1 ? ids[0] : `${ids.length} layers`}</span>
    </nav>
  {/if}
  {#if ids.length > 1}
    <section>
      <h3>{ids.length} layers selected</h3>
      <p class="hint">{ids.join(', ')}</p>
      {@render alignBar(false)}
      <div class="row">
        <button onclick={ongroup} title="Ctrl+G">Group</button>
        <button onclick={onduplicate}>Duplicate</button>
        <button onclick={ondelete}>Delete</button>
      </div>
      <p class="hint">Drag any of them on the canvas to move them together. Arrow keys nudge, Ctrl+C / Ctrl+V copy and paste.</p>
    </section>
  {:else if id && own && eff}
    <section>
      <h3>{type === 'group' || type === 'divider' ? type : `${type} layer`}</h3>
      <div class="field-like">
        <span class="lbl">id</span>
        <input class="mono" value={id} onchange={(e) => renameTo(e.currentTarget.value.trim())} />
      </div>
      {#if idError}<div class="err">{idError}</div>{/if}
      {#if type === 'divider'}
        <Field label="title" kind="text" optional value={ownVal(['label'])} title="Shown in the layer list; the id is used when empty" onchange={(v) => set(['label'], v === '' ? undefined : v)} />
      {:else if !isGroupLayer}
        <Field label="extends" kind="enum" optional value={ownVal(['extends'])} options={sameTypeIds} onchange={(v) => set(['extends'], v)} />
      {/if}
      <Field label="note" kind="text" optional value={ownVal(['note'])} onchange={(v) => set(['note'], v)} />
      {@render problemChip()}
    </section>
  {/if}
  {#if ids.length === 1 && id && own && eff && type === 'divider'}
    <section>
      <p class="hint">A divider only organises the layer list: it is never drawn and cannot be referenced. Drag layers above or below it.</p>
    </section>
  {:else if ids.length === 1 && id && own && eff && isGroupLayer}
    <section>
      <h3>Group contents</h3>
      <p class="hint">Contains {childCount} layer{childCount === 1 ? '' : 's'}. Its opacity, rotation, visibility and effects apply to everything inside, drawn together as one picture.</p>
      {@render alignBar(true)}
      <Field label="rotate" kind="number" optional value={ownVal(['rotate'])} fallback={0} title="Degrees clockwise around the group's centre" bindings={numberParams} error={errorAt(['rotate'])} path={pathOf(['rotate'])} onchange={(v) => set(['rotate'], v)} />
      <Field label="visible" kind="bool" optional value={ownVal(['visible'])} fallback={true} bindings={boolParams} error={errorAt(['visible'])} path={pathOf(['visible'])} onchange={(v) => set(['visible'], v === true ? undefined : v)} />
      <Field label="opacity" kind="number" optional value={ownVal(['opacity'])} fallback={1} bindings={numberParams} error={errorAt(['opacity'])} path={pathOf(['opacity'])} onchange={(v) => set(['opacity'], v)} />
      <div class="row">
        <button onclick={onungroup} title="Ctrl+Shift+G">Ungroup</button>
      </div>
    </section>
    <section>
      <h3>Origin</h3>
      <Field label="translate.x" kind="number" optional value={ownVal(['translate', 'x'])} fallback={0} title="Moves everything inside; coordinates inside the group are relative to this point" bindings={numberParams} error={errorAt(['translate', 'x'])} path={pathOf(['translate', 'x'])} onchange={(v) => set(['translate', 'x'], v)} />
      <Field label="translate.y" kind="number" optional value={ownVal(['translate', 'y'])} fallback={0} bindings={numberParams} error={errorAt(['translate', 'y'])} path={pathOf(['translate', 'y'])} onchange={(v) => set(['translate', 'y'], v)} />
      <p class="hint">With a translate, the layers inside use coordinates relative to it, and moving the group on the canvas changes only the translate.</p>
    </section>
    {@render repeatSection()}
    {@render effectsSection()}
  {:else if ids.length === 1 && id && own && eff}

    <section>
      <h3>Position and size</h3>
      {@render alignBar(true)}
      {#if type === 'polygon'}
        <div class="field-like">
          <span class="lbl">drawn from</span>
          <Select
            value={isShape ? 'shape' : 'points'}
            label="Polygon drawn from"
            options={[
              { value: 'points', label: 'points', detail: 'your own corners' },
              { value: 'shape', label: 'shape', detail: 'a preset in a box' },
            ]}
            onchange={setShapeMode} />
        </div>
      {/if}
      {#if type === 'polygon' && !isShape}
        <div class="points">
          {#each points as p, i}
            <div class="pt">
              <span class="lbl">{i + 1}</span>
              <input class="mono" value={String(p[0])} onchange={(e) => editPoints((pts) => (pts[i][0] = parseCoord(e.currentTarget.value)))} />
              <input class="mono" value={String(p[1])} onchange={(e) => editPoints((pts) => (pts[i][1] = parseCoord(e.currentTarget.value)))} />
              <button class="mini" title="Remove point" disabled={points.length <= (effVal(['closed']) === false ? 2 : 3)} onclick={() => editPoints((pts) => pts.splice(i, 1))}>×</button>
            </div>
          {/each}
          <button
            class="add"
            onclick={() =>
              editPoints((pts) => {
                const a = pts[pts.length - 1];
                const b = pts[0];
                const n = (v: Json) => (typeof v === 'number' ? v : 0);
                pts.push([Math.round((n(a[0]) + n(b[0])) / 2), Math.round((n(a[1]) + n(b[1])) / 2)]);
              })}>+ point</button>
        </div>
        {#if errorAt(['points'])}<div class="err">{errorAt(['points'])}</div>{/if}
        <Field label="closed" kind="enum" optional value={ownVal(['closed']) === undefined ? undefined : String(ownVal(['closed']))} fallback="true" options={['true', 'false']} onchange={(v) => set(['closed'], v === undefined ? undefined : v === 'true')} />
      {:else}
        <Field label="anchor" kind="enum" optional value={ownVal(['anchor'])} fallback="top-left" options={type === 'text' ? textAnchors : anchors} inherited={ownVal(['anchor']) === undefined && effVal(['anchor']) !== undefined} onchange={(v) => set(['anchor'], v)} />
        {#if isShape}
          <Field label="shape" kind="enum" value={effVal(['shape', 'type'])} options={shapeTypes} error={errorAt(['shape', 'type'])} onchange={(v) => set(['shape', 'type'], v ?? 'star')} />
          {#if effVal(['shape', 'type']) === 'star' || effVal(['shape', 'type']) === 'polygon'}
            <Field label="count" kind="number" optional value={ownVal(['shape', 'count'])} fallback={effVal(['shape', 'type']) === 'star' ? 5 : 6} title="Points of a star, sides of a polygon" bindings={numberParams} error={errorAt(['shape', 'count'])} path={pathOf(['shape', 'count'])} onchange={(v) => set(['shape', 'count'], v)} />
          {/if}
          {#if ['star', 'arrow', 'cross', 'chevron'].includes(String(effVal(['shape', 'type'])))}
            <Field label="inner" kind="number" optional value={ownVal(['shape', 'inner'])} title="Star: inner radius; arrow: shaft; cross: arm; chevron: thickness (0 to 1)" bindings={numberParams} error={errorAt(['shape', 'inner'])} path={pathOf(['shape', 'inner'])} onchange={(v) => set(['shape', 'inner'], v)} />
          {/if}
        {/if}
        {#each type === 'text' ? [['at', 'x'], ['at', 'y']] : [['box', 'x'], ['box', 'y'], ['box', 'w'], ['box', 'h']] as path}
          <Field
            label={path.join('.')}
            kind="number"
            value={ownVal(path) ?? effVal(path)}
            inherited={ownVal(path) === undefined && effVal(path) !== undefined}
            bindings={numberParams}
            allowAuto={type === 'image' && path[1] !== 'x' && path[1] !== 'y'}
            error={errorAt(path)}
            path={pathOf(path)}
            onchange={(v) => set(path, v)} />
        {/each}
        {#if type === 'text'}
          <Field label="wrap" kind="number" optional value={ownVal(['wrap'])} fallback={effVal(['wrap'])} placeholder="no wrapping" bindings={numberParams} error={errorAt(['wrap'])} path={pathOf(['wrap'])} onchange={(v) => set(['wrap'], v)} />
        {/if}
      {/if}
      <Field label="rotate" kind="number" optional value={ownVal(['rotate'])} fallback={effVal(['rotate']) ?? 0} title="Degrees clockwise around the anchor point (polygons with a point list and groups: their centre)" bindings={numberParams} error={errorAt(['rotate'])} path={pathOf(['rotate'])} onchange={(v) => set(['rotate'], v)} />
    </section>

    <section>
      <h3>Appearance</h3>
      {#if type === 'text'}
        <Field label="text" kind="template" value={ownVal(['text']) ?? effVal(['text'])} bindings={textParams} error={errorAt(['text'])} path={pathOf(['text'])} onchange={(v) => set(['text'], v)} />
        {@const fontNow = String(effVal(['font']) ?? 'default')}
        <Field label="font" kind="enum" optional value={ownVal(['font'])} fallback={fontNow} options={fontOptions} sample={sampleOf(fontNow) ?? null} defaultSample={sampleOf(fontNow)} onchange={pickFont}>
          {#snippet extra()}
            <button class="mini aa" title="Browse fonts: preview, upload and import fonts" aria-label="Browse fonts" onclick={() => onfonts({ path: fontPathOf(fontNow) || undefined })}>Aa</button>
          {/snippet}
        </Field>
        <Field label="size" kind="number" optional value={ownVal(['size'])} fallback={effVal(['size']) ?? 16} bindings={numberParams} error={errorAt(['size'])} path={pathOf(['size'])} onchange={(v) => set(['size'], v)} />
        <Field label="color" kind="color" optional value={ownVal(['color'])} fallback={effVal(['color']) ?? '#000000FF'} bindings={colorParams} error={errorAt(['color'])} path={pathOf(['color'])} onchange={(v) => set(['color'], v)} />
        <Field label="align" kind="enum" optional value={ownVal(['align'])} fallback={String(effVal(['align']) ?? 'left')} options={['left', 'center', 'right', 'justify']} onchange={(v) => set(['align'], v)} />
        <Field label="line_spacing" kind="number" optional value={ownVal(['line_spacing'])} fallback={effVal(['line_spacing']) ?? 4} bindings={numberParams} error={errorAt(['line_spacing'])} path={pathOf(['line_spacing'])} onchange={(v) => set(['line_spacing'], v)} />
        <p class="sub">Auto-shrink: the size goes down until the text fits.</p>
        <Field label="max_width" kind="number" optional value={ownVal(['max_width'])} fallback={effVal(['max_width'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_width'])} path={pathOf(['max_width'])} onchange={(v) => set(['max_width'], v)} />
        <Field label="max_height" kind="number" optional value={ownVal(['max_height'])} fallback={effVal(['max_height'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_height'])} path={pathOf(['max_height'])} onchange={(v) => set(['max_height'], v)} />
        <Field label="min_size" kind="number" optional value={ownVal(['min_size'])} fallback={effVal(['min_size']) ?? 8} bindings={numberParams} error={errorAt(['min_size'])} path={pathOf(['min_size'])} onchange={(v) => set(['min_size'], v)} />
        <Field label="max_lines" kind="number" optional value={ownVal(['max_lines'])} fallback={effVal(['max_lines'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_lines'])} path={pathOf(['max_lines'])} onchange={(v) => set(['max_lines'], v)} />
        <Field label="shrink_group" kind="text" optional value={ownVal(['shrink_group'])} fallback={effVal(['shrink_group'])} placeholder="none" title="Texts with the same name (and all their iterations) use the smallest size any of them shrank to" onchange={(v) => set(['shrink_group'], v === '' ? undefined : v)} />
      {:else if type === 'image'}
        <Field label="src" kind="template" value={ownVal(['src']) ?? effVal(['src'])} bindings={imageParams} error={errorAt(['src'])} path={pathOf(['src'])} onchange={(v) => set(['src'], v)} />
        <div class="field-like">
          <span class="lbl"></span>
          <ImagePicker {imageFiles} {upload} onpick={(v) => set(['src'], v)} />
        </div>
        <Field label="fit" kind="enum" optional value={ownVal(['fit'])} fallback={String(effVal(['fit']) ?? 'fill')} options={['fill', 'contain', 'cover']} onchange={(v) => set(['fit'], v)} />
        <Field label="smoothing" kind="enum" optional value={ownVal(['smoothing'])} fallback={String(effVal(['smoothing']) ?? 'bilinear')} options={['bilinear', 'nearest']} onchange={(v) => set(['smoothing'], v)} />
      {:else}
        <Field label="fill" kind="color" optional value={ownVal(['fill'])} fallback={effVal(['fill']) ?? '#FFFFFFFF'} bindings={colorParams} error={errorAt(['fill'])} path={pathOf(['fill'])} onchange={(v) => set(['fill'], v)} />
        {#if type === 'rect'}
          <Field label="radius" kind="number" optional value={ownVal(['radius'])} fallback={effVal(['radius']) ?? 0} bindings={numberParams} error={errorAt(['radius'])} path={pathOf(['radius'])} onchange={(v) => set(['radius'], v)} />
        {/if}
        {#if type === 'ellipse'}
          <div class="field-like">
            <span class="lbl">arc</span>
            <input type="checkbox" checked={isObj(eff.arc)} title="Draw part of the ellipse" onchange={(e) => set(['arc'], e.currentTarget.checked ? { start: 0, end: 270 } : undefined)} />
          </div>
          {#if isObj(eff.arc)}
            <Field label="arc.start" kind="number" optional value={ownVal(['arc', 'start'])} fallback={effVal(['arc', 'start']) ?? 0} title="Degrees clockwise from the top" bindings={numberParams} error={errorAt(['arc', 'start'])} path={pathOf(['arc', 'start'])} onchange={(v) => set(['arc', 'start'], v)} />
            <Field label="arc.end" kind="number" optional value={ownVal(['arc', 'end'])} fallback={effVal(['arc', 'end']) ?? 360} bindings={numberParams} error={errorAt(['arc', 'end'])} path={pathOf(['arc', 'end'])} onchange={(v) => set(['arc', 'end'], v)} />
            <Field label="arc.pie" kind="enum" optional value={ownVal(['arc', 'pie']) === undefined ? undefined : String(ownVal(['arc', 'pie']))} fallback="true" options={['true', 'false']} title="true: a slice through the centre; false: only the curve (stroke)" onchange={(v) => set(['arc', 'pie'], v === undefined ? undefined : v === 'true')} />
          {/if}
        {/if}
      {/if}
      {#if type !== 'image'}
        <div class="field-like">
          <span class="lbl">{type === 'text' ? 'outline' : 'stroke'}</span>
          <input type="checkbox" checked={isObj(eff.stroke)} onchange={(e) => set(['stroke'], e.currentTarget.checked ? { color: '#000000', width: type === 'text' ? 2 : 4 } : undefined)} />
        </div>
        {#if isObj(eff.stroke)}
          <Field label="stroke.color" kind="color" value={ownVal(['stroke', 'color']) ?? effVal(['stroke', 'color'])} bindings={colorParams} error={errorAt(['stroke', 'color'])} path={pathOf(['stroke', 'color'])} onchange={(v) => set(['stroke', 'color'], v)} />
          <Field label="stroke.width" kind="number" value={ownVal(['stroke', 'width']) ?? effVal(['stroke', 'width'])} bindings={numberParams} error={errorAt(['stroke', 'width'])} path={pathOf(['stroke', 'width'])} onchange={(v) => set(['stroke', 'width'], v)} />
          {#if type !== 'text'}
            <div class="field-like">
              <span class="lbl">stroke.dash</span>
              <input class="mono" placeholder="solid, or e.g. 12, 6" title="Dash pattern in pixels: on, off, on, off…" value={dashText(effVal(['stroke', 'dash']))} onchange={(e) => set(['stroke', 'dash'], parseDash(e.currentTarget.value))} />
            </div>
            {#if errorAt(['stroke', 'dash'])}<div class="err">{errorAt(['stroke', 'dash'])}</div>{/if}
          {/if}
          {#if type === 'polygon' && !isShape && effVal(['closed']) === false}
            <Field label="stroke.arrow" kind="enum" optional value={ownVal(['stroke', 'arrow'])} fallback={String(effVal(['stroke', 'arrow']) ?? 'none')} options={['none', 'start', 'end', 'both']} title="Arrowheads at the ends of an open line" onchange={(v) => set(['stroke', 'arrow'], v === 'none' ? undefined : v)} />
          {/if}
        {/if}
      {/if}
      <Field label="visible" kind="bool" optional value={ownVal(['visible'])} fallback={effVal(['visible']) ?? true} bindings={boolParams} error={errorAt(['visible'])} path={pathOf(['visible'])} onchange={(v) => set(['visible'], v === true ? undefined : v)} />
      <Field label="opacity" kind="number" optional value={ownVal(['opacity'])} fallback={effVal(['opacity']) ?? 1} bindings={numberParams} error={errorAt(['opacity'])} path={pathOf(['opacity'])} onchange={(v) => set(['opacity'], v)} />
    </section>

    {@render repeatSection()}

    {@render effectsSection()}
  {:else if !ids.length}
    <section>
      <h3>Design</h3>
      <Field label="name" kind="text" value={doc.name} error={errorAt(['name'])} onchange={(v) => setDoc(['name'], v ?? '')} />
      <Field label="width" kind="number" value={getPath(doc, ['canvas', 'width'])} bindings={numberParams} error={errorAt(['canvas', 'width'])} path={pathOf(['canvas', 'width'])} onchange={(v) => setDoc(['canvas', 'width'], v)} />
      <Field label="height" kind="number" value={getPath(doc, ['canvas', 'height'])} bindings={numberParams} error={errorAt(['canvas', 'height'])} path={pathOf(['canvas', 'height'])} onchange={(v) => setDoc(['canvas', 'height'], v)} />
      <Field label="background" kind="color" optional value={getPath(doc, ['canvas', 'background'])} fallback="#00000000" bindings={colorParams} error={errorAt(['canvas', 'background'])} path={pathOf(['canvas', 'background'])} onchange={(v) => setDoc(['canvas', 'background'], v)} />
      <Field label="dpi" kind="number" optional value={getPath(doc, ['canvas', 'dpi'])} placeholder="not set" title="Print resolution, stored in PNG and PDF files" bindings={numberParams} error={errorAt(['canvas', 'dpi'])} path={pathOf(['canvas', 'dpi'])} onchange={(v) => setDoc(['canvas', 'dpi'], v)} />
      <Field label="bleed" kind="number" optional value={getPath(doc, ['canvas', 'bleed'])} placeholder="none" title="Pixels on every side that are cut off; the trim line (and crop marks) sit this far inside the edge" bindings={numberParams} error={errorAt(['canvas', 'bleed'])} path={pathOf(['canvas', 'bleed'])} onchange={(v) => setDoc(['canvas', 'bleed'], v)} />
      <Field label="note" kind="text" optional value={doc.note} onchange={(v) => setDoc(['note'], v)} />
      {@render problemChip()}
    </section>
    <section>
      <h3>Constants</h3>
      {#each consts as [name, v]}
        <div class="const" data-goto="const:{name}">
          <Field label={name} kind="expr" value={v} error={errorAt(['consts', name])} path={pathOf(['consts', name])} onchange={(x) => setDoc(['consts', name], x ?? 0)} />
          <button class="mini" title="Remove" onclick={() => editDoc((d) => {
            if (isObj(d.consts)) delete (d.consts as Obj)[name];
            if (isObj(d.consts) && !Object.keys(d.consts).length) delete d.consts;
          })}>×</button>
        </div>
      {/each}
      <div class="row">
        <input class="mono" placeholder="name" bind:value={newConst} />
        <button disabled={!identRe.test(newConst) || consts.some(([n]) => n === newConst)} onclick={() => { setDoc(['consts', newConst], 0); newConst = ''; }}>Add</button>
      </div>
      <p class="hint">A value every layer can use by name, such as a tile size. It can use params and the constants above it.</p>
    </section>
    <section>
      <h3>Functions</h3>
      {#each functions as [name, fn]}
        <div class="effect" data-goto="function:{name}">
          <div class="effect-head">
            <strong class="mono">{name}({argsText(fn.args)})</strong>
            <span class="spacer"></span>
            <button class="mini" title="Remove" onclick={() => editDoc((d) => {
              if (isObj(d.functions)) delete (d.functions as Obj)[name];
              if (isObj(d.functions) && !Object.keys(d.functions).length) delete d.functions;
            })}>×</button>
          </div>
          <div class="field-like">
            <span class="lbl">args</span>
            <input class="mono" value={argsText(fn.args)} placeholder="i: number, kind: text" onchange={(e) => setDoc(['functions', name, 'args'], parseArgs(e.currentTarget.value))} />
          </div>
          <Scope context={() => functionScope(name, fn)}>
            <Field label="expr" kind="expr" value={fn.expr} error={errorAt(['functions', name])} path={pathOf(['functions', name, 'expr'])} onchange={(x) => setDoc(['functions', name, 'expr'], x ?? '0')} />
          </Scope>
        </div>
      {/each}
      <div class="row">
        <input class="mono" placeholder="name" bind:value={newFunction} />
        <button disabled={!identRe.test(newFunction) || functions.some(([n]) => n === newFunction)} onclick={() => { setDoc(['functions', newFunction], { args: { i: 'number' }, expr: 'i * 10' }); newFunction = ''; }}>Add</button>
      </div>
      <p class="hint">A formula with arguments, such as <code>tile_x(i)</code>, that layers call instead of repeating it. Argument types: number, text, bool, color.</p>
    </section>
    <section>
      <h3>Fonts</h3>
      {#each fontEntries as [name, path]}
        {@const face = fontFaces[String(path)]}
        {@const lic = fontLicenses[String(path)]}
        <div class="font-entry">
          <div class="field-like font-row">
            <input class="mono font-name" value={name} aria-label="Font name" title="Renaming also updates the layers that use this font" onchange={(e) => renameFontTo(name, e.currentTarget)} onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()} />
            <button class="font-sample" title="Show {name} in the Fonts window" style:font-family={face ? `"${face}"` : undefined} onclick={() => onfonts({ path: String(path) })}>{fontSampleText}</button>
            <div class="row">
              <Select
                value={String(path)}
                mono
                label="Font file for {name}"
                options={[...(fontFiles.includes(String(path)) ? [] : [{ value: String(path), label: String(path).split('/').pop(), detail: 'missing' }]), ...fontFiles.map((f) => ({ value: f, label: f.split('/').pop(), sample: fontFaces[f] ? { family: fontFaces[f] as string, text: 'Aa' } : undefined }))]}
                onchange={(v) => setDoc(['fonts', name], v)} />
              {#if !fontFiles.includes(String(path))}<span class="missing" title="This font file is not in the project; the default font is used">!</span>
              {:else if lic}<span class="lic" title="License file next to the font">{lic}</span>
              {:else}<span class="missing" title="No license file next to this font: check its terms before you share the project. Open it in the Fonts window to add one.">?</span>{/if}
              <button class="mini" title="Remove" onclick={() => askRemoveFont(name)}>×</button>
            </div>
          </div>
          {#if fontError.name === name}<div class="err">{fontError.msg}</div>{/if}
        </div>
      {/each}
      <div class="row font-actions">
        <button onclick={() => onfonts()}>Browse fonts…</button>
        <button onclick={() => onfonts({ upload: true })}>Upload…</button>
      </div>
      {#if !fontEntries.length}<p class="hint">Text uses the bundled default font until you add one. <b>Browse fonts…</b> previews the fonts in the project and on Google Fonts and adds them here; <b>Upload…</b> adds a .ttf or .otf file from this computer.</p>{/if}
    </section>
    <p class="hint pad">Select a layer on the canvas or in the layer list to edit it, and press Esc or use <b>Design settings</b> at the top to come back here. Drag to move, use the handles to resize, Alt+click to pick the layer underneath, hold Ctrl to move without snapping.</p>
  {/if}
</div>

<style>
  .inspector {
    display: flex;
    flex-direction: column;
  }
  .crumb {
    position: sticky;
    top: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    padding: 6px 12px;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--line);
    font-size: 12px;
  }
  .crumb .back {
    flex: none;
    padding: 2px 6px;
    border-color: transparent;
    background: none;
    color: var(--accent);
    font-size: 12px;
  }
  .crumb .back:hover {
    background: var(--hover);
    text-decoration: underline;
  }
  .crumb .sep {
    color: var(--muted);
  }
  .crumb .here {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: var(--mono);
  }
  section {
    padding: 10px 12px;
    border-bottom: 1px solid var(--line);
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  h3 {
    margin: 0 0 2px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }
  .field-like {
    display: grid;
    grid-template-columns: 84px minmax(0, 1fr);
    gap: 8px;
    align-items: center;
  }
  .field-like > input[type='checkbox'] {
    justify-self: start;
  }
  .lbl {
    font-size: 12px;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .row {
    display: flex;
    gap: 4px;
  }
  .font-sample {
    grid-column: 2;
    justify-self: start;
    max-width: 100%;
    padding: 0;
    border: 0;
    background: none;
    font-size: 18px;
    line-height: 1.2;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: var(--fg);
    cursor: pointer;
  }
  .lic {
    align-self: center;
    padding: 0 5px;
    border: 1px solid var(--line);
    border-radius: 4px;
    font-size: 11px;
    color: var(--muted);
  }
  .font-row > .row {
    grid-column: 2;
  }
  .font-name {
    grid-row: span 2;
    min-width: 0;
  }
  .font-actions > button {
    flex: 1;
  }
  .aa {
    font-weight: 600;
  }
  .row > :global(:first-child) {
    flex: 1;
    min-width: 0;
  }
  .err {
    color: var(--err);
    font-size: 11px;
    padding-left: 92px;
  }
  .probs {
    align-self: flex-start;
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 12px;
    padding: 3px 8px;
    border-radius: 999px;
    border-color: color-mix(in srgb, var(--warn) 50%, var(--line));
    background: color-mix(in srgb, var(--warn) 10%, var(--bg));
  }
  .probs.has-err {
    border-color: color-mix(in srgb, var(--err) 50%, var(--line));
    background: color-mix(in srgb, var(--err) 9%, var(--bg));
  }
  .probs .e,
  .probs .w {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-weight: 600;
  }
  .probs .e {
    color: var(--err);
  }
  .probs .w {
    color: var(--warn-text);
  }
  .probs .go {
    color: var(--muted);
  }
  .missing {
    display: grid;
    place-items: center;
    width: 20px;
    flex: none;
    border-radius: 50%;
    background: var(--warn);
    color: #000;
    font-weight: 700;
    font-size: 12px;
  }
  .const {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 4px;
    align-items: center;
  }
  .points {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .pt {
    display: grid;
    grid-template-columns: 20px 1fr 1fr auto;
    gap: 4px;
    align-items: center;
  }
  .pt input {
    min-width: 0;
  }
  .add {
    align-self: flex-start;
    font-size: 12px;
    padding: 2px 8px;
  }
  .effect {
    border: 1px solid var(--line);
    border-radius: 6px;
    padding: 6px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .effect-head {
    display: flex;
    gap: 4px;
    align-items: center;
    font-size: 12px;
  }
  .spacer {
    flex: 1;
  }
  .mini {
    padding: 1px 6px;
    font-size: 11px;
  }
  .align {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
  }
  .align button {
    width: 30px;
    height: 26px;
    padding: 0;
  }
  .sub {
    font-size: 11px;
    color: var(--muted);
    margin: 4px 0 0;
  }
  .hint {
    font-size: 12px;
    color: var(--muted);
    margin: 0;
  }
  .pad {
    padding: 10px 12px;
  }
</style>
