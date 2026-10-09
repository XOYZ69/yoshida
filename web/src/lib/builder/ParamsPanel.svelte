<script lang="ts">
// The design's params: the inputs every card fills in. Each one becomes a
// field in the card form and a name that layer fields can use.
// Sections come from each param's optional `group`; the list can also be
// shown A to Z or by type. Dragging a param reorders the file (that order
// is the card form's order) and can move it to another group.

import {
	groupOf,
	identRe,
	isObj,
	type Json,
	moveParam,
	newParam,
	type Obj,
	type ParamTypeName,
	paramSections,
	paramTypes,
	renameParamGroup,
	retypeParam,
	setPath,
	templatesUsing,
} from "../design";
import type { CardInfo, Diagnostic } from "../engine";
import ImagePicker from "../ui/ImagePicker.svelte";
import { askText, confirmAction, openMenu } from "../ui/overlay.svelte";
import Select from "../ui/Select.svelte";
import EnumOptions from "./EnumOptions.svelte";
import Field from "./Field.svelte";

let {
	doc,
	imageFiles,
	upload,
	diagnostics,
	designFile,
	editDoc,
	onrename,
	cards,
	onrenameoption,
}: {
	doc: Obj;
	imageFiles: string[];
	upload: () => Promise<string | null>;
	diagnostics: Diagnostic[];
	designFile: string;
	editDoc: (fn: (doc: Obj) => void, key?: string) => void;
	/** Renames a param in the design and in the card data that uses it. */
	onrename: (from: string, to: string) => void;
	/** Every card of the sets that use this design. */
	cards: CardInfo[];
	/** Renames an enum option in the design and in card data. */
	onrenameoption: (param: string, from: string, to: string) => void;
} = $props();

const params = $derived(
	isObj(doc.params)
		? (Object.entries(doc.params).filter(([, v]) => isObj(v)) as [
				string,
				Obj,
			][])
		: [],
);
const reserved = new Set([
	"canvas",
	"render",
	"card",
	"true",
	"false",
	"and",
	"or",
	"not",
]);

let open: string | null = $state(null);

// ---------------------------------------------------------------- views

type View = "groups" | "az" | "type";
const viewKey = "yoshida.paramsView";
let view: View = $state(load());
let query = $state("");
let folded = $state(new Set<string>());

function load(): View {
	try {
		const v = localStorage.getItem(viewKey);
		return v === "az" || v === "type" ? v : "groups";
	} catch {
		return "groups";
	}
}

function setView(v: View) {
	view = v;
	try {
		localStorage.setItem(viewKey, v);
	} catch {
		/* private mode */
	}
}

const groups = $derived([
	...new Set(params.map(([, p]) => groupOf(p)).filter(Boolean)),
]);
const matches = $derived.by(() => {
	const q = query.trim().toLowerCase();
	if (!q) return params;
	return params.filter(([n, p]) =>
		`${n} ${p.label ?? ""} ${p.note ?? ""} ${p.type} ${groupOf(p)}`
			.toLowerCase()
			.includes(q),
	);
});
const sections = $derived.by(
	(): { key: string; title: string; params: [string, Obj][] }[] => {
		if (view === "az")
			return [
				{
					key: "",
					title: "",
					params: [...matches].sort(([a], [b]) => a.localeCompare(b)),
				},
			];
		if (view === "type") {
			const out = paramTypes.map((t) => ({
				key: `type:${t}`,
				title: t,
				params: matches.filter(([, p]) => p.type === t),
			}));
			return out.filter((x) => x.params.length);
		}
		const out = paramSections(matches, groupOf).map((x) => ({
			key: x.group,
			title: x.group,
			params: x.params,
		}));
		// Keep empty-by-search groups out; the ungrouped section only has a title when groups exist.
		return out.filter((x) => x.params.length);
	},
);
const canDrag = $derived(view === "groups" && !query.trim());

function fold(key: string) {
	const next = new Set(folded);
	if (!next.delete(key)) next.add(key);
	folded = next;
}

function groupMenu(e: MouseEvent, g: string) {
	e.preventDefault();
	openMenu(e.clientX, e.clientY, [
		{ label: "Rename group…", icon: "✎", action: () => renameGroup(g) },
		{
			label: "Ungroup",
			detail: "params stay, without a group",
			action: () => editDoc((d) => renameParamGroup(d, g, "")),
		},
		{ separator: true },
		{
			label: folded.size ? "Expand all" : "Collapse all",
			action: () =>
				(folded = folded.size
					? new Set()
					: new Set(sections.map((s) => s.key))),
		},
	]);
}

async function renameGroup(g: string) {
	const to = (
		await askText({
			title: `Rename group '${g}'`,
			value: g,
			confirm: "Rename",
			validate: (v) => (v.trim() ? "" : "Enter a name."),
		})
	)?.trim();
	if (to && to !== g) editDoc((d) => renameParamGroup(d, g, to));
}

async function setGroup(name: string, v: string) {
	let g = v;
	if (v === "\u0001new") {
		g =
			(
				await askText({
					title: "New group",
					message: `Puts '${name}' in a new section of the params list and the card form.`,
					placeholder: "Monster stats",
					confirm: "Create",
					validate: (x) => (x.trim() ? "" : "Enter a name."),
				})
			)?.trim() ?? "";
		if (!g) return;
	}
	editDoc((d) => moveParam(d, name, null, g));
}

// ---------------------------------------------------------------- drag to reorder

let dragName: string | null = $state(null);
let dropTarget: { before: string | null; group: string } | null = $state(null);

function finishDrop() {
	const name = dragName;
	const t = dropTarget;
	dragName = null;
	dropTarget = null;
	if (!name || !t || t.before === name) return;
	editDoc((d) => moveParam(d, name, t.before, t.group));
}

// ---------------------------------------------------------------- enum helpers

function usageOf(name: string): Map<string, number> {
	const m = new Map<string, number>();
	for (const c of cards) {
		const v = c.values[name];
		if (typeof v === "string") m.set(v, (m.get(v) ?? 0) + 1);
	}
	return m;
}
let newName = $state("");
let newType: ParamTypeName = $state("text");
const nameError = $derived(
	!newName
		? ""
		: !identRe.test(newName)
			? "Letters, digits and _ only, not starting with a digit"
			: reserved.has(newName)
				? "This name is reserved"
				: params.some(([n]) => n === newName)
					? "Already exists"
					: "",
);

function edit(name: string, path: string[], v: Json | undefined) {
	editDoc(
		(d) => {
			if (!isObj(d.params)) d.params = {};
			setPath(d.params[name] as Obj, path, v);
		},
		`param.${name}.${path.join(".")}`,
	);
}

function add() {
	if (!newName || nameError) return;
	const name = newName;
	editDoc((d) => {
		if (!isObj(d.params)) d.params = {};
		(d.params as Obj)[name] = newParam(newType, imageFiles);
	});
	open = name;
	newName = "";
}

let renameError = $state("");

function rename(from: string, to: string) {
	const fail = (msg: string) => {
		renameError = msg;
		return msg;
	};
	if (to === from) return fail("");
	if (!identRe.test(to))
		return fail("Letters, digits and _ only, not starting with a digit");
	if (reserved.has(to)) return fail("This name is reserved");
	if (params.some(([n]) => n === to))
		return fail(`There is already a param '${to}'`);
	renameError = "";
	onrename(from, to);
	open = to;
}

async function remove(name: string) {
	const ok = await confirmAction({
		title: `Delete param '${name}'?`,
		message:
			"Layers and cards that use it will show errors until you fix them.",
		confirm: "Delete",
		danger: true,
	});
	if (!ok) return;
	editDoc((d) => {
		if (isObj(d.params)) delete d.params[name];
	});
}

function retype(name: string, t: ParamTypeName) {
	editDoc((d) => {
		const ps = d.params as Obj;
		ps[name] = retypeParam(ps[name] as Obj, t, imageFiles);
	});
}

function problems(name: string) {
	return diagnostics.filter(
		(d) => d.file === designFile && d.path.startsWith(`/params/${name}`),
	);
}

function defaultKind(t: string) {
	return t === "number" || t === "integer"
		? "number"
		: t === "bool"
			? "bool"
			: t === "color"
				? "color"
				: t === "enum"
					? "enum"
					: "text";
}

const typeHelp: Record<string, string> = {
	text: "words",
	number: "any number",
	integer: "whole number",
	bool: "yes / no",
	color: "#RRGGBB",
	enum: "one of a list",
	image: "file or URL",
	list: "rows with fields",
};

// List item fields: name -> scalar type.
const itemTypes = ["text", "number", "integer", "bool", "color"];
</script>

<div class="params">
  {#if params.length > 3}
    <div class="bar">
      <input class="search" type="search" placeholder="Filter params…" bind:value={query} aria-label="Filter params" />
      <Select
        value={view}
        label="Show params"
        options={[
          { value: 'groups', label: 'Groups', detail: 'file order' },
          { value: 'az', label: 'A to Z' },
          { value: 'type', label: 'By type' },
        ]}
        onchange={(v) => setView(v as View)} />
    </div>
  {/if}
  {#each sections as sec (sec.key)}
    {#if sec.title || (view === 'groups' && sections.length > 1)}
      <div
        class="section"
        class:drop={dragName && dropTarget?.before === null && dropTarget.group === sec.key}
        role="heading"
        aria-level="3"
        ondragover={(e) => {
          if (!dragName || view !== 'groups') return;
          e.preventDefault();
          dropTarget = { before: null, group: sec.key };
        }}
        ondrop={(e) => {
          e.preventDefault();
          finishDrop();
        }}
        oncontextmenu={(e) => view === 'groups' && sec.title && groupMenu(e, sec.title)}>
        <button class="fold" aria-expanded={!folded.has(sec.key)} onclick={() => fold(sec.key)}>
          <span class="arrow">{folded.has(sec.key) ? '▸' : '▾'}</span>
          <span class="title">{sec.title || 'No group'}</span>
          <span class="count">{sec.params.length}</span>
        </button>
        {#if view === 'groups' && sec.title}
          <button class="more" title="Group actions" onclick={(e) => groupMenu(e, sec.title)}>⋯</button>
        {/if}
      </div>
    {/if}
    {#if !folded.has(sec.key)}
      {#each sec.params as [name, p] (name)}
        {@const t = String(p.type)}
        {@const probs = problems(name)}
        <div
          class="param"
          role="group"
          aria-label={name}
          draggable={canDrag && open !== name}
          ondragstart={(e) => {
            dragName = name;
            e.dataTransfer?.setData('text/x-yoshida-param', name);
            if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
          }}
          ondragend={() => {
            dragName = null;
            dropTarget = null;
          }}
          class:open={open === name}
          class:drop={dropTarget?.before === name}
          class:dragging={dragName === name}
          ondragover={(e) => {
            if (!dragName) return;
            e.preventDefault();
            dropTarget = { before: name, group: groupOf(p) };
          }}
          ondrop={(e) => {
            e.preventDefault();
            finishDrop();
          }}>
          <button
            class="head"
            onclick={() => (open = open === name ? null : name)}>
            {#if canDrag}<span class="grip" aria-hidden="true">⋮⋮</span>{/if}
            <span class="mono">{name}</span>
            {#if p.label}<span class="label">{p.label}</span>{/if}
            <span class="type">{t}{p.required ? ', required' : ''}</span>
            {#if p.note}<span class="has-note" title={String(p.note)}>ⓘ</span>{/if}
            {#if probs.length}<span class="dot"></span>{/if}
          </button>
          {#if open === name}
            <div class="body">
              <div class="field-like">
                <span class="lbl">name</span>
                <input
                  class="mono"
                  value={name}
                  title="Renaming also updates layer fields and card data"
                  onchange={(e) => rename(name, e.currentTarget.value.trim())}
                  onkeydown={(e) => e.key === 'Enter' && e.currentTarget.blur()} />
              </div>
              {#if renameError}<p class="err">{renameError}</p>{/if}
              <div class="field-like">
                <span class="lbl">type</span>
                <Select value={t} label="Type of {name}" options={paramTypes.map((pt) => ({ value: pt, label: pt, detail: typeHelp[pt] }))} onchange={(v) => retype(name, v as ParamTypeName)} />
              </div>
              <Field label="label" kind="text" optional value={p.label} onchange={(v) => edit(name, ['label'], v)} />
              <Field label="note" kind="text" optional value={p.note} onchange={(v) => edit(name, ['note'], v)} />
              <div class="field-like">
                <span class="lbl">group</span>
                <Select
                  value={groupOf(p)}
                  label="Group of {name}"
                  options={[{ value: '', label: 'No group' }, ...groups.map((g) => ({ value: g, label: g })), { value: '\u0001new', label: 'New group…' }]}
                  onchange={(v) => setGroup(name, v)} />
              </div>
              <div class="field-like">
                <span class="lbl">required</span>
                <input
                  type="checkbox"
                  checked={p.required === true}
                  onchange={(e) =>
                    editDoc((d) => {
                      const q = (d.params as Obj)[name] as Obj;
                      if (e.currentTarget.checked) {
                        q.required = true;
                        delete q.default;
                      } else {
                        delete q.required;
                        q.default = (newParam(t as ParamTypeName, imageFiles).default ?? '') as Json;
                      }
                    })} />
              </div>
              {#if !p.required}
                {#if t === 'list'}
                  <div class="field-like">
                    <span class="lbl">default</span>
                    <textarea
                      class="mono"
                      rows="3"
                      value={JSON.stringify(p.default ?? [])}
                      onchange={(e) => {
                        try {
                          edit(name, ['default'], JSON.parse(e.currentTarget.value));
                        } catch {
                          /* keep the old value until it parses */
                        }
                      }}></textarea>
                  </div>
                {:else if t === 'image'}
                  <Field label="default" kind="text" value={p.default} onchange={(v) => edit(name, ['default'], v ?? '')} />
                  <div class="field-like">
                    <span class="lbl"></span>
                    <ImagePicker {imageFiles} {upload} onpick={(v) => edit(name, ['default'], v)} />
                  </div>
                {:else}
                  <Field
                    label="default"
                    kind={defaultKind(t)}
                    value={t === 'bool' ? p.default : p.default}
                    options={Array.isArray(p.options) ? (p.options as string[]) : []}
                    onchange={(v) => edit(name, ['default'], t === 'number' || t === 'integer' ? (typeof v === 'number' ? v : Number(v) || 0) : (v ?? ''))} />
                {/if}
              {/if}
              {#if t === 'number' || t === 'integer'}
                <Field label="min" kind="number" optional value={p.min} onchange={(v) => edit(name, ['min'], typeof v === 'string' ? Number(v) : v)} />
                <Field label="max" kind="number" optional value={p.max} onchange={(v) => edit(name, ['max'], typeof v === 'string' ? Number(v) : v)} />
              {:else if t === 'text'}
                <Field label="max_length" kind="number" optional value={p.max_length} onchange={(v) => edit(name, ['max_length'], typeof v === 'string' ? Number(v) : v)} />
              {:else if t === 'enum'}
                <EnumOptions
                  options={Array.isArray(p.options) ? p.options.map(String) : []}
                  usage={usageOf(name)}
                  templates={templatesUsing(doc, name)}
                  onchange={(v) => edit(name, ['options'], v)}
                  onrename={(from, to) => onrenameoption(name, from, to)} />
              {:else if t === 'list'}
                <div class="items">
                  <span class="lbl">item fields</span>
                  {#each Object.entries(isObj(p.item) ? p.item : {}) as [field, ft]}
                    <div class="row">
                      <span class="mono grow">{field}</span>
                      <Select value={String(ft)} label="Type of {field}" options={itemTypes} onchange={(v) => edit(name, ['item', field], v)} />
                      <button class="mini" disabled={Object.keys(p.item as Obj).length <= 1} onclick={() => edit(name, ['item', field], undefined)}>×</button>
                    </div>
                  {/each}
                  <input
                    class="mono"
                    placeholder="+ field name, Enter"
                    onkeydown={(e) => {
                      const v = e.currentTarget.value.trim();
                      if (e.key === 'Enter' && identRe.test(v)) {
                        edit(name, ['item', v], 'text');
                        e.currentTarget.value = '';
                      }
                    }} />
                </div>
              {/if}
              {#each probs as d}<div class="prob {d.severity}">{d.message}</div>{/each}
              <button class="danger" onclick={() => remove(name)}>Delete param</button>
            </div>
          {/if}
        </div>
      {/each}
    {/if}
  {/each}
  {#if query && !matches.length}<p class="hint">No param matches '{query}'.</p>{/if}

  <div class="new">
    <input class="mono" placeholder="new param name" bind:value={newName} onkeydown={(e) => e.key === 'Enter' && add()} />
    <Select value={newType} label="Type of the new param" options={paramTypes.map((pt) => ({ value: pt, label: pt, detail: typeHelp[pt] }))} onchange={(v) => (newType = v as ParamTypeName)} />
    <button onclick={add} disabled={!newName || !!nameError}>Add</button>
  </div>
  {#if nameError}<div class="prob error pad">{nameError}</div>{/if}
  <p class="hint">Params are the inputs each card fills in. Use their names in layer fields, like <code>accent</code> in a color or <code>{'{title}'}</code> in a text.</p>
</div>

<style>
  .params {
    display: flex;
    flex-direction: column;
  }
  .param {
    border-bottom: 1px solid var(--line);
    border-top: 2px solid transparent;
  }
  .param.drop {
    border-top-color: var(--accent);
  }
  .param.dragging {
    opacity: 0.5;
  }
  .bar {
    display: flex;
    gap: 4px;
    padding: 8px 12px;
    border-bottom: 1px solid var(--line);
  }
  .search {
    flex: 1;
    min-width: 0;
  }
  .section {
    display: flex;
    align-items: center;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--line);
    border-top: 2px solid transparent;
  }
  .section.drop {
    border-top-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 14%, var(--bg-bar));
  }
  .section .fold {
    all: unset;
    flex: 1;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    cursor: pointer;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }
  .section .count {
    font-weight: 400;
  }
  .section .more {
    border: 0;
    background: none;
    padding: 2px 8px;
    color: var(--muted);
  }
  .grip {
    color: var(--muted);
    font-size: 10px;
    letter-spacing: -2px;
    cursor: grab;
  }
  .label {
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }
  .has-note {
    color: var(--muted);
    font-size: 12px;
  }
  .head {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: flex;
    gap: 8px;
    align-items: center;
    padding: 6px 12px;
    cursor: pointer;
  }
  .head .type {
    margin-left: auto;
    white-space: nowrap;
  }
  .head:hover {
    background: var(--hover);
  }
  .open .head {
    background: var(--sel);
  }
  .type {
    color: var(--muted);
    font-size: 12px;
  }
  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--err);
  }
  .body {
    padding: 8px 12px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .field-like {
    display: grid;
    grid-template-columns: 84px 1fr;
    gap: 8px;
    align-items: center;
  }
  .field-like > input[type='checkbox'] {
    justify-self: start;
  }
  .lbl {
    font-size: 12px;
    color: var(--muted);
  }
  .err {
    color: var(--err);
    font-size: 12px;
    margin: 0;
  }
  .mono {
    font-family: var(--mono);
    font-size: 12px;
  }
  .items {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .row {
    display: flex;
    gap: 4px;
    align-items: center;
  }
  .grow {
    flex: 1;
  }
  .mini {
    padding: 1px 6px;
    font-size: 11px;
  }
  .danger {
    align-self: flex-start;
    color: var(--err);
    font-size: 12px;
  }
  .new {
    display: flex;
    gap: 4px;
    padding: 10px 12px 4px;
  }
  .new input {
    flex: 1;
    min-width: 0;
  }
  .prob {
    font-size: 12px;
  }
  .prob.error {
    color: var(--err);
  }
  .prob.warning {
    color: var(--warn-text);
  }
  .pad {
    padding: 0 12px;
  }
  .hint {
    font-size: 12px;
    color: var(--muted);
    padding: 4px 12px;
    margin: 0;
  }
</style>
