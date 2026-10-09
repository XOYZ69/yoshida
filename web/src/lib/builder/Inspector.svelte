<script lang="ts">
// Properties of the selected layer, or of the design itself when nothing
// is selected. Every field accepts a literal or an expression; fields a
// layer inherits through `extends` are marked and editing them adds an
// override to this layer.
import { setContext } from "svelte";
import {
	type AlignMode,
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
import ImagePicker from "../ui/ImagePicker.svelte";
import Select from "../ui/Select.svelte";
import type { CompletionContext } from "./complete";
import Field from "./Field.svelte";

let {
	doc,
	ids,
	imageFiles,
	upload,
	fontFiles,
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
	listKeys = {},
}: {
	doc: Obj;
	ids: string[];
	imageFiles: string[];
	/** Adds an image from the user's computer; returns its project path. */
	upload: () => Promise<string | null>;
	fontFiles: string[];
	diagnostics: Diagnostic[];
	designFile: string;
	editLayer: (fn: (own: Obj) => void, key?: string) => void;
	editDoc: (fn: (doc: Obj) => void, key?: string) => void;
	rename: (from: string, to: string) => string;
	/** Key values of each list param, from the cards, for `list.Key` suggestions. */
	listKeys?: Record<string, string[]>;
	onalign: (mode: AlignMode) => void;
	ondistribute: (axis: "x" | "y") => void;
	onduplicate: () => void;
	ondelete: () => void;
	ongroup: () => void;
	onungroup: () => void;
	/** Shows the problems of a layer (or of the design, for null) in the problems panel. */
	onproblems: (id: string | null) => void;
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

// Suggestions for expression fields (see ExprInput).
const completion = $derived.by((): CompletionContext => {
	const locals: CompletionContext["locals"] = [];
	const rep = isObj(eff?.repeat) ? (eff!.repeat as Obj) : null;
	if (rep) {
		locals.push({ name: String(rep.index ?? "i"), detail: "repeat index" });
		if (typeof rep.item === "string") {
			const each = String(rep.each ?? "");
			const p = params.find(([n]) => n === each.trim())?.[1];
			locals.push({
				name: rep.item,
				detail: `item of ${each}`,
				fields: isObj(p?.item) ? (p!.item as Record<string, string>) : {},
			});
		}
	}
	return {
		params: params.map(([name, p]) => ({
			name,
			type: String(p.type),
			item:
				p.item && typeof p.item === "object" && !Array.isArray(p.item)
					? (Object.fromEntries(
							Object.entries(p.item).map(([k, v]) => [k, String(v)]),
						) as Record<string, string>)
					: undefined,
			keys: listKeys[name],
			label: typeof p.label === "string" ? p.label : undefined,
			note: typeof p.note === "string" ? p.note : undefined,
		})),
		layers: layersOf(doc)
			.filter((l) => l.id !== id && !l.repeat)
			.map((l) => ({ id: String(l.id), type: String(l.type) })),
		locals,
	};
});
setContext("yoshida-complete", () => completion);

// Problems are listed once, in the problems panel; fields only show a
// short note for their own errors.
const myDiags = $derived(
	diagnostics.filter(
		(d) =>
			d.file === designFile &&
			(ptr
				? (d.path === ptr || d.path.startsWith(ptr + "/")) &&
					!d.path.startsWith(ptr + "/layers/")
				: !d.path.startsWith("/layers/")),
	),
);
const errorCount = $derived(
	myDiags.filter((d) => d.severity === "error").length,
);
const warnCount = $derived(
	myDiags.filter((d) => d.severity === "warning").length,
);

function errorAt(path: string[]) {
	const p = ptr ? `${ptr}/${path.join("/")}` : `/${path.join("/")}`;
	const d = myDiags.find(
		(x) =>
			x.severity === "error" && (x.path === p || x.path.startsWith(p + "/")),
	);
	return d ? d.message.replace(/^layer '[^']*': /, "") : "";
}

const ownVal = (path: string[]) => getPath(own ?? undefined, path);
const effVal = (path: string[]) => getPath(eff ?? undefined, path);

function set(path: string[], v: Json | undefined) {
	editLayer((l) => setPath(l, path, v), path.join("."));
}

function setDoc(path: string[], v: Json | undefined) {
	editDoc((d) => setPath(d, path, v), "doc." + path.join("."));
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

function parseCoord(raw: string): Json {
	const s = raw.trim();
	return /^-?\d+(\.\d+)?$/.test(s) ? Number(s) : s;
}

// ------------------------------------------------------------ fonts

const fontEntries = $derived(
	isObj(doc.fonts) ? Object.entries(doc.fonts as Obj) : [],
);
let newFont = $state("");
</script>

{#snippet effectsSection()}
  <section>
    <h3>Effects</h3>
    {#each effects as fx, i}
      <div class="effect">
        <div class="effect-head">
          <strong>{fx.type}</strong>
          <span class="spacer"></span>
          <button class="mini" disabled={i === 0} onclick={() => editEffects((l) => l.splice(i - 1, 0, ...l.splice(i, 1)))}>↑</button>
          <button class="mini" disabled={i === effects.length - 1} onclick={() => editEffects((l) => l.splice(i + 1, 0, ...l.splice(i, 1)))}>↓</button>
          <button class="mini" onclick={() => editEffects((l) => l.splice(i, 1))}>×</button>
        </div>
        {#if fx.type === 'fade' || fx.type === 'crop'}
          <Field label="side" kind="enum" value={fx.side} options={['top', 'bottom', 'left', 'right']} onchange={(v) => editEffects((l) => (l[i].side = v ?? 'bottom'))} />
          <Field label="length" kind="number" value={fx.length} bindings={numberParams} error={errorAt(['effects', String(i)])} onchange={(v) => editEffects((l) => (l[i].length = v ?? 0), `fx${i}.length`)} />
        {:else}
          <Field label="strength" kind="number" optional value={fx.strength} fallback={1} bindings={numberParams} error={errorAt(['effects', String(i)])} onchange={(v) => editEffects((l) => (v === undefined ? delete l[i].strength : (l[i].strength = v)), `fx${i}.strength`)} />
        {/if}
      </div>
    {/each}
    <Select value="" placeholder="+ Add effect…" label="Add effect" options={effectTypes.map((t) => ({ value: t, label: t, detail: effectHelp[t] }))} onchange={(t) => editEffects((l) => l.push(newEffect(t)))} />
  </section>
{/snippet}

{#snippet problemChip()}
  {#if errorCount || warnCount}
    <button class="probs" class:has-err={errorCount > 0} onclick={() => onproblems(id)} title="Show in the problems panel">
      {#if errorCount}<span class="e">● {errorCount} error{errorCount > 1 ? 's' : ''}</span>{/if}
      {#if warnCount}<span class="w">▲ {warnCount} warning{warnCount > 1 ? 's' : ''}</span>{/if}
      <span class="go">show ›</span>
    </button>
  {/if}
{/snippet}

{#snippet alignBar(toCanvas: boolean)}
  <div class="align" role="group" aria-label="Align">
    <button title="Align left{toCanvas ? ' to the canvas' : ''}" onclick={() => onalign('left')}>⇤</button>
    <button title="Center horizontally{toCanvas ? ' on the canvas' : ''}" onclick={() => onalign('hcenter')}>↔</button>
    <button title="Align right{toCanvas ? ' to the canvas' : ''}" onclick={() => onalign('right')}>⇥</button>
    <button title="Align top{toCanvas ? ' to the canvas' : ''}" onclick={() => onalign('top')}>⤒</button>
    <button title="Center vertically{toCanvas ? ' on the canvas' : ''}" onclick={() => onalign('vcenter')}>↕</button>
    <button title="Align bottom{toCanvas ? ' to the canvas' : ''}" onclick={() => onalign('bottom')}>⤓</button>
    {#if !toCanvas}
      <button title="Distribute horizontally (equal gaps)" disabled={ids.length < 3} onclick={() => ondistribute('x')}>⋯</button>
      <button title="Distribute vertically (equal gaps)" disabled={ids.length < 3} onclick={() => ondistribute('y')}>⋮</button>
    {/if}
  </div>
{/snippet}

<div class="inspector">
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
      <Field label="rotate" kind="number" optional value={ownVal(['rotate'])} fallback={0} title="Degrees clockwise around the group's centre" bindings={numberParams} error={errorAt(['rotate'])} onchange={(v) => set(['rotate'], v)} />
      <Field label="visible" kind="bool" optional value={ownVal(['visible'])} fallback={true} bindings={boolParams} error={errorAt(['visible'])} onchange={(v) => set(['visible'], v === true ? undefined : v)} />
      <Field label="opacity" kind="number" optional value={ownVal(['opacity'])} fallback={1} bindings={numberParams} error={errorAt(['opacity'])} onchange={(v) => set(['opacity'], v)} />
      <div class="row">
        <button onclick={onungroup} title="Ctrl+Shift+G">Ungroup</button>
      </div>
    </section>
    {@render effectsSection()}
  {:else if ids.length === 1 && id && own && eff}

    <section>
      <h3>Position and size</h3>
      {@render alignBar(true)}
      {#if type === 'polygon'}
        <div class="points">
          {#each points as p, i}
            <div class="pt">
              <span class="lbl">{i + 1}</span>
              <input class="mono" value={String(p[0])} onchange={(e) => editPoints((pts) => (pts[i][0] = parseCoord(e.currentTarget.value)))} />
              <input class="mono" value={String(p[1])} onchange={(e) => editPoints((pts) => (pts[i][1] = parseCoord(e.currentTarget.value)))} />
              <button class="mini" title="Remove point" disabled={points.length <= 3} onclick={() => editPoints((pts) => pts.splice(i, 1))}>×</button>
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
        {#each type === 'text' ? [['at', 'x'], ['at', 'y']] : [['box', 'x'], ['box', 'y'], ['box', 'w'], ['box', 'h']] as path}
          <Field
            label={path.join('.')}
            kind="number"
            value={ownVal(path) ?? effVal(path)}
            inherited={ownVal(path) === undefined && effVal(path) !== undefined}
            bindings={numberParams}
            allowAuto={type === 'image' && path[1] !== 'x' && path[1] !== 'y'}
            error={errorAt(path)}
            onchange={(v) => set(path, v)} />
        {/each}
        {#if type === 'text'}
          <Field label="wrap" kind="number" optional value={ownVal(['wrap'])} fallback={effVal(['wrap'])} placeholder="no wrapping" bindings={numberParams} error={errorAt(['wrap'])} onchange={(v) => set(['wrap'], v)} />
        {/if}
      {/if}
      <Field label="rotate" kind="number" optional value={ownVal(['rotate'])} fallback={effVal(['rotate']) ?? 0} title="Degrees clockwise around the anchor point (polygons: their centre)" bindings={numberParams} error={errorAt(['rotate'])} onchange={(v) => set(['rotate'], v)} />
    </section>

    <section>
      <h3>Appearance</h3>
      {#if type === 'text'}
        <Field label="text" kind="template" value={ownVal(['text']) ?? effVal(['text'])} bindings={textParams} error={errorAt(['text'])} onchange={(v) => set(['text'], v)} />
        <Field label="font" kind="enum" optional value={ownVal(['font'])} fallback={String(effVal(['font']) ?? 'default')} options={['default', ...fonts.filter((f) => f !== 'default')]} onchange={(v) => set(['font'], v)} />
        <Field label="size" kind="number" optional value={ownVal(['size'])} fallback={effVal(['size']) ?? 16} bindings={numberParams} error={errorAt(['size'])} onchange={(v) => set(['size'], v)} />
        <Field label="color" kind="color" optional value={ownVal(['color'])} fallback={effVal(['color']) ?? '#000000FF'} bindings={colorParams} error={errorAt(['color'])} onchange={(v) => set(['color'], v)} />
        <Field label="align" kind="enum" optional value={ownVal(['align'])} fallback={String(effVal(['align']) ?? 'left')} options={['left', 'center', 'right', 'justify']} onchange={(v) => set(['align'], v)} />
        <Field label="line_spacing" kind="number" optional value={ownVal(['line_spacing'])} fallback={effVal(['line_spacing']) ?? 4} bindings={numberParams} error={errorAt(['line_spacing'])} onchange={(v) => set(['line_spacing'], v)} />
        <p class="sub">Auto-shrink: the size goes down until the text fits.</p>
        <Field label="max_width" kind="number" optional value={ownVal(['max_width'])} fallback={effVal(['max_width'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_width'])} onchange={(v) => set(['max_width'], v)} />
        <Field label="max_height" kind="number" optional value={ownVal(['max_height'])} fallback={effVal(['max_height'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_height'])} onchange={(v) => set(['max_height'], v)} />
        <Field label="min_size" kind="number" optional value={ownVal(['min_size'])} fallback={effVal(['min_size']) ?? 8} bindings={numberParams} error={errorAt(['min_size'])} onchange={(v) => set(['min_size'], v)} />
        <Field label="max_lines" kind="number" optional value={ownVal(['max_lines'])} fallback={effVal(['max_lines'])} placeholder="no limit" bindings={numberParams} error={errorAt(['max_lines'])} onchange={(v) => set(['max_lines'], v)} />
      {:else if type === 'image'}
        <Field label="src" kind="template" value={ownVal(['src']) ?? effVal(['src'])} bindings={imageParams} error={errorAt(['src'])} onchange={(v) => set(['src'], v)} />
        <div class="field-like">
          <span class="lbl"></span>
          <ImagePicker {imageFiles} {upload} onpick={(v) => set(['src'], v)} />
        </div>
        <Field label="fit" kind="enum" optional value={ownVal(['fit'])} fallback={String(effVal(['fit']) ?? 'fill')} options={['fill', 'contain', 'cover']} onchange={(v) => set(['fit'], v)} />
        <Field label="smoothing" kind="enum" optional value={ownVal(['smoothing'])} fallback={String(effVal(['smoothing']) ?? 'bilinear')} options={['bilinear', 'nearest']} onchange={(v) => set(['smoothing'], v)} />
      {:else}
        <Field label="fill" kind="color" optional value={ownVal(['fill'])} fallback={effVal(['fill']) ?? '#FFFFFFFF'} bindings={colorParams} error={errorAt(['fill'])} onchange={(v) => set(['fill'], v)} />
        {#if type === 'rect'}
          <Field label="radius" kind="number" optional value={ownVal(['radius'])} fallback={effVal(['radius']) ?? 0} bindings={numberParams} error={errorAt(['radius'])} onchange={(v) => set(['radius'], v)} />
        {/if}
      {/if}
      {#if type !== 'text' && type !== 'image'}
        <div class="field-like">
          <span class="lbl">stroke</span>
          <input type="checkbox" checked={isObj(eff.stroke)} onchange={(e) => set(['stroke'], e.currentTarget.checked ? { color: '#000000', width: 4 } : undefined)} />
        </div>
        {#if isObj(eff.stroke)}
          <Field label="stroke.color" kind="color" value={ownVal(['stroke', 'color']) ?? effVal(['stroke', 'color'])} bindings={colorParams} error={errorAt(['stroke', 'color'])} onchange={(v) => set(['stroke', 'color'], v)} />
          <Field label="stroke.width" kind="number" value={ownVal(['stroke', 'width']) ?? effVal(['stroke', 'width'])} bindings={numberParams} error={errorAt(['stroke', 'width'])} onchange={(v) => set(['stroke', 'width'], v)} />
        {/if}
      {/if}
      <Field label="visible" kind="bool" optional value={ownVal(['visible'])} fallback={effVal(['visible']) ?? true} bindings={boolParams} error={errorAt(['visible'])} onchange={(v) => set(['visible'], v === true ? undefined : v)} />
      <Field label="opacity" kind="number" optional value={ownVal(['opacity'])} fallback={effVal(['opacity']) ?? 1} bindings={numberParams} error={errorAt(['opacity'])} onchange={(v) => set(['opacity'], v)} />
    </section>

    <section>
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
        <Field label="count" kind="number" value={effVal(['repeat', 'count'])} bindings={numberParams} error={errorAt(['repeat', 'count'])} onchange={(v) => set(['repeat', 'count'], v)} />
      {:else if repeatMode === 'each'}
        <Field label="each" kind="expr" expect="list" value={effVal(['repeat', 'each'])} bindings={listParams} error={errorAt(['repeat', 'each'])} onchange={(v) => set(['repeat', 'each'], v)} />
        <Field label="item" kind="text" value={effVal(['repeat', 'item'])} placeholder="item" error={errorAt(['repeat', 'item'])} onchange={(v) => set(['repeat', 'item'], v)} />
      {/if}
      {#if repeatMode !== 'none'}
        <Field label="index" kind="text" optional value={effVal(['repeat', 'index'])} fallback="i" error={errorAt(['repeat', 'index'])} onchange={(v) => set(['repeat', 'index'], v)} />
        <p class="hint">Use the index (and item) names in this layer's fields, for example <code>x: 100 + i * 60</code>.</p>
      {/if}
    </section>

    {@render effectsSection()}
  {:else if !ids.length}
    <section>
      <h3>Design</h3>
      <Field label="name" kind="text" value={doc.name} error={errorAt(['name'])} onchange={(v) => setDoc(['name'], v ?? '')} />
      <Field label="width" kind="number" value={getPath(doc, ['canvas', 'width'])} bindings={numberParams} error={errorAt(['canvas', 'width'])} onchange={(v) => setDoc(['canvas', 'width'], v)} />
      <Field label="height" kind="number" value={getPath(doc, ['canvas', 'height'])} bindings={numberParams} error={errorAt(['canvas', 'height'])} onchange={(v) => setDoc(['canvas', 'height'], v)} />
      <Field label="background" kind="color" optional value={getPath(doc, ['canvas', 'background'])} fallback="#00000000" bindings={colorParams} error={errorAt(['canvas', 'background'])} onchange={(v) => setDoc(['canvas', 'background'], v)} />
      <Field label="note" kind="text" optional value={doc.note} onchange={(v) => setDoc(['note'], v)} />
      {@render problemChip()}
    </section>
    <section>
      <h3>Fonts</h3>
      {#each fontEntries as [name, path]}
        <div class="field-like">
          <span class="lbl mono">{name}</span>
          <div class="row">
            <Select
              value={String(path)}
              mono
              label="Font file for {name}"
              options={[...(fontFiles.includes(String(path)) ? [] : [{ value: String(path), label: String(path).split('/').pop(), detail: 'missing' }]), ...fontFiles.map((f) => ({ value: f, label: f.split('/').pop() }))]}
              onchange={(v) => setDoc(['fonts', name], v)} />
            {#if !fontFiles.includes(String(path))}<span class="missing" title="This font file is not in the project; the default font is used">!</span>{/if}
            <button class="mini" title="Remove" onclick={() => setDoc(['fonts', name], undefined)}>×</button>
          </div>
        </div>
      {/each}
      <div class="row">
        <input class="mono" placeholder="font name" bind:value={newFont} />
        <button
          disabled={!identRe.test(newFont) || fontEntries.some(([n]) => n === newFont)}
          onclick={() => {
            setDoc(['fonts', newFont], fontFiles[0] ?? `assets/fonts/${newFont}.ttf`);
            newFont = '';
          }}>Add</button>
      </div>
      {#if !fontFiles.length}<p class="hint">Use <b>Add files</b> in the top bar to add .ttf or .otf fonts, then choose them here.</p>{/if}
    </section>
    <p class="hint pad">Select a layer on the canvas or in the layer list to edit it. Drag to move, use the handles to resize, Alt+click to pick the layer underneath, hold Ctrl to move without snapping.</p>
  {/if}
</div>

<style>
  .inspector {
    display: flex;
    flex-direction: column;
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
  .probs .e {
    color: var(--err);
    font-weight: 600;
  }
  .probs .w {
    color: var(--warn-text);
    font-weight: 600;
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
    gap: 2px;
    flex-wrap: wrap;
  }
  .align button {
    padding: 2px 7px;
    min-width: 28px;
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
