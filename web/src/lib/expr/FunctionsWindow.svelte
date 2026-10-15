<script lang="ts">
// The Functions window: a searchable reference of every function of the
// expression language, with signature, a one-line doc and an example that
// can be copied. Functions are grouped by what they work on (GROUPS below).
// The second tab lists the built-in names, keywords and operators; the
// functions this design defines are listed last, under "This design".
import { onDestroy, onMount } from "svelte";
import Window from "../ui/Window.svelte";
import {
	BUILTINS,
	CHEATSHEET,
	CONSTANTS,
	FUNCTIONS,
	type FnDoc,
	fnSignature,
	KEYWORDS,
} from "./catalog";

let {
	onclose,
	query = "",
	userFunctions = [],
}: {
	onclose: () => void;
	/** Filter text to start with. */
	query?: string;
	/** The functions this design defines: name, argument names and body. */
	userFunctions?: { name: string; args: string; expr: string }[];
} = $props();

/** Function groups in list order. Every function of FUNCTIONS is in one of them, or in OTHER. */
const GROUPS: [title: string, names: string[]][] = [
	[
		"Numbers",
		[
			"min",
			"max",
			"clamp",
			"abs",
			"floor",
			"ceil",
			"round",
			"sign",
			"sqrt",
			"pow",
			"lerp",
			"remap",
			"wrap",
		],
	],
	["Trigonometry", ["sin", "cos", "tan", "asin", "acos", "atan2", "deg", "rad"]],
	[
		"Text",
		[
			"upper",
			"lower",
			"trim",
			"fmt",
			"contains",
			"starts_with",
			"ends_with",
			"replace",
			"slice",
			"pad_start",
			"repeat",
			"title_case",
			"roman",
			"part",
		],
	],
	[
		"Lists",
		[
			"len",
			"has",
			"get",
			"index_of",
			"sum",
			"avg",
			"count",
			"join",
			"last",
		],
	],
	[
		"Dates and times",
		[
			"year",
			"month",
			"day",
			"weekday",
			"hour",
			"minute",
			"date_fmt",
			"add_days",
			"add_hours",
			"days_between",
		],
	],
	[
		"Colours",
		[
			"avg_color",
			"mix",
			"with_alpha",
			"rgb",
			"rgba",
			"hsl",
			"hsla",
			"lighten",
			"darken",
			"luminance",
			"readable",
		],
	],
	["Random", ["rand", "rand_int", "pick"]],
	["Logic", ["match"]],
];
const OTHER = "Other";
const groupOf = new Map(
	GROUPS.flatMap(([title, names]) =>
		names.map((n): [string, string] => [n, title]),
	),
);
const slug = (title: string) => title.toLowerCase().replace(/\W+/g, "-");

type Group = { id: string; title: string; fns: FnDoc[] };
type Row = { code: string; meta?: string; doc: string };

let tab = $state<"functions" | "names">("functions");
let q = $state("");
let searchEl: HTMLInputElement | undefined = $state();
let listEl: HTMLDivElement | undefined = $state();

$effect(() => {
	q = query;
});
onMount(() => searchEl?.focus());

const terms = $derived(q.trim().toLowerCase().split(/\s+/).filter(Boolean));
function matches(text: string): boolean {
	const t = text.toLowerCase();
	return terms.every((w) => t.includes(w));
}

const design = $derived(
	userFunctions.filter((u) => matches(`${u.name} ${u.args} ${u.expr}`)),
);

const groups = $derived.by((): Group[] => {
	const buckets = new Map<string, FnDoc[]>(GROUPS.map(([t]) => [t, []]));
	buckets.set(OTHER, []);
	for (const f of FUNCTIONS) {
		if (!matches(`${f.name} ${f.doc} ${f.example}`)) continue;
		buckets.get(groupOf.get(f.name) ?? OTHER)?.push(f);
	}
	return [...buckets]
		.filter(([, fns]) => fns.length)
		.map(([title, fns]) => ({ id: slug(title), title, fns }));
});

const refs = $derived.by((): { title: string; rows: Row[] }[] => {
	const out: { title: string; rows: Row[] }[] = [];
	const add = (title: string, rows: Row[]) => {
		const hit = rows.filter((r) => matches(`${r.code} ${r.doc}`));
		if (hit.length) out.push({ title, rows: hit });
	};
	add(
		"Built-in names",
		Object.entries(BUILTINS).flatMap(([ns, b]) => [
			{ code: ns, doc: b.doc },
			...b.fields.map((f) => ({
				code: `${ns}.${f.name}`,
				meta: f.type,
				doc: f.doc,
			})),
		]),
	);
	add(
		"Constants",
		CONSTANTS.map((k) => ({ code: k.name, meta: k.type, doc: k.doc })),
	);
	add(
		"Keywords",
		KEYWORDS.map((k) => ({ code: k.name, meta: k.type, doc: k.doc })),
	);
	for (const g of CHEATSHEET)
		add(
			g.title,
			g.rows.map(([code, doc]) => ({ code, doc })),
		);
	return out;
});

/** Index of the Functions tab: the groups, then the design's own functions. */
const index = $derived([
	...groups.map((g) => ({ id: g.id, title: g.title, count: g.fns.length })),
	...(design.length
		? [{ id: "this-design", title: "This design", count: design.length }]
		: []),
]);

function jump(id: string) {
	const el = listEl?.querySelector<HTMLElement>(`#grp-${id}`);
	if (listEl && el) listEl.scrollTo({ top: el.offsetTop, behavior: "smooth" });
}

function searchKey(e: KeyboardEvent) {
	if (e.key !== "Escape") return;
	e.preventDefault();
	e.stopPropagation();
	if (q) q = "";
	else onclose();
}

// Examples are coloured with the expression colours, without the core: a
// name before "(" is a function, then literals, references and keywords.
const TOKEN =
	/('[^']*'|#[\dA-Fa-f]{6,8}|@\w+|\b\d+(?:\.\d+)?|\b[A-Za-z_]\w*(?=\()|\b(?:and|or|not|in|true|false)\b)/;
const SPLIT = new RegExp(TOKEN.source, "g");
const KEYWORD = /^(and|or|not|in|true|false)$/;

function kindOf(t: string): string {
	if (t[0] === "'") return "str";
	if (t[0] === "#") return "color";
	if (t[0] === "@") return "ref";
	if (/^\d/.test(t)) return "num";
	return KEYWORD.test(t) ? "kw" : "call";
}

function highlight(code: string): { t: string; k: string }[] {
	return code
		.split(SPLIT)
		.map((t, i) => ({ t, k: i % 2 ? kindOf(t) : "" }))
		.filter((s) => s.t);
}

let copied = $state("");
let timer: ReturnType<typeof setTimeout> | undefined;
async function copy(text: string) {
	try {
		await navigator.clipboard.writeText(text);
	} catch {
		return;
	}
	copied = text;
	clearTimeout(timer);
	timer = setTimeout(() => (copied = ""), 1400);
}
onDestroy(() => clearTimeout(timer));
</script>

<Window key="functions" title="Functions" width={720} height={560} minWidth={340} {onclose}>
  <div class="fw">
    <div class="bar">
      <div class="btn-group" role="tablist" aria-label="Reference">
        <button role="tab" aria-selected={tab === 'functions'} onclick={() => (tab = 'functions')}>Functions</button>
        <button role="tab" aria-selected={tab === 'names'} onclick={() => (tab = 'names')}>Names and operators</button>
      </div>
      <input
        class="search"
        type="search"
        placeholder="Search name, doc or example"
        aria-label="Search functions"
        bind:value={q}
        bind:this={searchEl}
        onkeydown={searchKey}
      />
    </div>

    {#if tab === 'functions'}
      <div class="main">
        {#if index.length}
          <nav class="index" aria-label="Groups">
            {#each index as g}
              <button onclick={() => jump(g.id)}>{g.title}<span class="count">{g.count}</span></button>
            {/each}
          </nav>
        {/if}

        <div class="list" bind:this={listEl}>
          {#each groups as g}
            <section class="group" id="grp-{g.id}">
              <h3>{g.title}</h3>
              {#each g.fns as f}
                <article class="entry">
                  <div class="sig"><code>{#each fnSignature(f).parts as p, i}<span class:fname={i === 0}>{p.text}</span>{/each}</code></div>
                  <p class="doc">{f.doc}</p>
                  <div class="ex">
                    <code>{#each highlight(f.example) as s}<span class={s.k}>{s.t}</span>{/each}</code>
                    <button class="copy" class:done={copied === f.example} title="Copy the example" onclick={() => copy(f.example)}>
                      {copied === f.example ? 'Copied' : 'Copy'}
                    </button>
                  </div>
                </article>
              {/each}
            </section>
          {/each}
          {#if design.length}
            <section class="group" id="grp-this-design">
              <h3>This design</h3>
              {#each design as u}
                <article class="entry">
                  <div class="sig"><code><span class="fname">{u.name}</span>({u.args})</code></div>
                  <div class="ex"><span class="eq">=</span><code>{#each highlight(u.expr) as s}<span class={s.k}>{s.t}</span>{/each}</code></div>
                </article>
              {/each}
            </section>
          {/if}
          {#if !groups.length && !design.length}<p class="none">No match</p>{/if}
        </div>
      </div>
    {:else}
      <div class="names">
        {#each refs as s}
          <section class="group">
            <h3>{s.title}</h3>
            {#each s.rows as r}
              <div class="crow">
                <code>{r.code}</code>
                <span>{#if r.meta}<span class="meta">{r.meta}</span>{/if}{r.doc}</span>
              </div>
            {/each}
          </section>
        {:else}
          <p class="none">No match</p>
        {/each}
      </div>
    {/if}
  </div>
</Window>

<style>
  .fw {
    position: relative;
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
    font-size: 12px;
    container-type: inline-size;
  }
  .bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 8px;
    flex: none;
    min-height: var(--bar-h);
    box-sizing: border-box;
    padding: 6px 10px;
    border-bottom: 1px solid var(--line);
  }
  .bar .btn-group {
    flex: none;
  }
  .bar .btn-group > button {
    height: calc(var(--ctl-h) - 2px);
    padding: 0 10px;
    font-family: inherit;
  }
  .search {
    flex: 1 1 180px;
    min-width: 0;
    height: var(--ctl-h);
    box-sizing: border-box;
  }
  .main {
    flex: 1;
    min-height: 0;
    display: flex;
  }
  .index {
    flex: none;
    width: 136px;
    display: flex;
    flex-direction: column;
    padding: 8px 6px;
    overflow-y: auto;
    border-right: 1px solid var(--line);
  }
  .index button {
    all: unset;
    box-sizing: border-box;
    display: flex;
    justify-content: space-between;
    gap: 6px;
    padding: 4px 8px;
    border-radius: 4px;
    cursor: pointer;
    font-family: inherit;
    color: var(--fg);
  }
  .index button:hover {
    background: var(--hover);
  }
  .count {
    color: var(--muted);
    font-size: 11px;
  }
  .list,
  .names {
    position: relative;
    flex: 1;
    min-width: 0;
    min-height: 0;
    overflow-y: auto;
  }
  .group {
    padding: 0 14px 6px;
  }
  .group + .group {
    border-top: 1px solid var(--line);
  }
  h3 {
    position: sticky;
    top: 0;
    z-index: 1;
    margin: 0;
    padding: 10px 0 6px;
    background: var(--bg);
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }
  .entry {
    padding: 7px 0;
    border-bottom: 1px solid color-mix(in srgb, var(--line) 60%, transparent);
  }
  .entry:last-child {
    border-bottom: 0;
  }
  .sig code {
    font-family: var(--mono);
    font-size: 13px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .fname {
    color: var(--syn-keyword);
    font-weight: 600;
  }
  .doc {
    margin: 3px 0 0;
    color: var(--fg);
  }
  .ex {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 5px;
    min-width: 0;
  }
  .ex code {
    flex: 1;
    min-width: 0;
    padding: 2px 8px;
    background: var(--bg-code);
    border: 1px solid var(--line);
    border-radius: 5px;
    font-family: var(--mono);
    font-size: 12px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .eq {
    color: var(--muted);
    font-family: var(--mono);
  }
  .copy {
    flex: none;
    padding: 2px 9px;
    font-family: inherit;
    font-size: 11px;
    color: var(--muted);
  }
  .copy:hover {
    color: var(--fg);
  }
  .copy.done {
    color: var(--accent);
  }
  .call {
    color: var(--syn-keyword);
  }
  .str {
    color: var(--syn-string);
  }
  .num,
  .color {
    color: var(--syn-number);
  }
  .ref {
    color: var(--syn-ref);
    font-weight: 600;
  }
  .kw {
    color: var(--syn-key);
    font-weight: 600;
  }
  .names .crow {
    display: grid;
    grid-template-columns: minmax(96px, 30%) 1fr;
    gap: 10px;
    padding: 3px 0;
    color: var(--muted);
    font-size: 12px;
  }
  .names code {
    color: var(--fg);
    font-family: var(--mono);
    font-size: 12px;
    overflow-wrap: anywhere;
  }
  .meta {
    margin-right: 6px;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--accent);
  }
  .none {
    margin: 24px 14px;
    color: var(--muted);
    text-align: center;
  }

  /* Narrow window: the index moves above the list, as a row of links. */
  @container (max-width: 520px) {
    .main {
      flex-direction: column;
    }
    .index {
      flex-direction: row;
      flex-wrap: wrap;
      gap: 2px;
      width: auto;
      padding: 6px;
      border-right: 0;
      border-bottom: 1px solid var(--line);
    }
    .index button {
      padding: 3px 8px;
      border: 1px solid var(--line);
      border-radius: 12px;
    }
  }
</style>
