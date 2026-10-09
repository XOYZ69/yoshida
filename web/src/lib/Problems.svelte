<script lang="ts">
// The one list of problems. Each entry is a block: severity, code, the
// message with names set as code, where it is (file:line and a readable
// path) and the hint. The same problem on several cards is shown once.
import type { Diagnostic, Severity } from "./engine";

let {
	diagnostics,
	onselect,
	crumbs = () => [],
	focus = null,
	onclearfocus = () => {},
}: {
	diagnostics: Diagnostic[];
	onselect: (d: Diagnostic) => void;
	/** Readable location steps, e.g. ['layer title', 'size']. */
	crumbs?: (d: Diagnostic) => string[];
	/** Only show the problems of one layer (or the design). */
	focus?: { label: string; match: (d: Diagnostic) => boolean } | null;
	onclearfocus?: () => void;
} = $props();

const order: Record<Severity, number> = { error: 0, warning: 1, hint: 2 };
let show = $state<Record<Severity, boolean>>({
	error: true,
	warning: true,
	hint: true,
});

type Entry = { d: Diagnostic; cards: string[] };
const entries = $derived.by(() => {
	const map = new Map<string, Entry>();
	for (const d of diagnostics) {
		const key = [
			d.severity,
			d.code,
			d.file,
			d.path,
			d.line,
			d.col,
			d.message,
		].join("\u0000");
		const e = map.get(key);
		if (e) {
			if (d.card && !e.cards.includes(d.card)) e.cards.push(d.card);
		} else map.set(key, { d, cards: d.card ? [d.card] : [] });
	}
	return [...map.values()].sort(
		(a, b) =>
			order[a.d.severity] - order[b.d.severity] ||
			a.d.file.localeCompare(b.d.file) ||
			a.d.line - b.d.line,
	);
});
const scoped = $derived(
	focus ? entries.filter((e) => focus!.match(e.d)) : entries,
);
const visible = $derived(scoped.filter((e) => show[e.d.severity]));
const counts = $derived({
	error: scoped.filter((e) => e.d.severity === "error").length,
	warning: scoped.filter((e) => e.d.severity === "warning").length,
	hint: scoped.filter((e) => e.d.severity === "hint").length,
});

/** Splits a message into text and 'quoted' names (shown as code). */
function parts(msg: string): { code: boolean; text: string }[] {
	const out: { code: boolean; text: string }[] = [];
	const re = /'([^']+)'|"([^"]+)"/g;
	let last = 0;
	for (let m = re.exec(msg); m; m = re.exec(msg)) {
		if (m.index > last)
			out.push({ code: false, text: msg.slice(last, m.index) });
		out.push({ code: true, text: m[1] ?? m[2] });
		last = m.index + m[0].length;
	}
	if (last < msg.length) out.push({ code: false, text: msg.slice(last) });
	return out;
}

const area: Record<string, string> = {
	1: "file structure",
	2: "card data",
	3: "expressions and layout",
	4: "images and fonts",
	5: "limits",
};

const short = (f: string) => f.split("/").pop() ?? f;
/** Messages start with "layer 'x': "; the location already says that. */
const body = (m: string) => m.replace(/^layer '[^']*': /, "");
const icon: Record<Severity, string> = { error: "✕", warning: "!", hint: "i" };
</script>

<div class="problems">
  <header>
    <strong>Problems</strong>
    {#each ['error', 'warning', 'hint'] as const as s}
      <button class="toggle {s}" class:off={!show[s]} aria-pressed={show[s]} onclick={() => (show[s] = !show[s])} title={show[s] ? `Hide ${s}s` : `Show ${s}s`}>
        <span class="dot">{icon[s]}</span>{counts[s]} {s}{counts[s] === 1 ? '' : 's'}
      </button>
    {/each}
    {#if focus}
      <span class="focus">
        only <b>{focus.label}</b>
        <button class="clear" onclick={onclearfocus} title="Show all problems">×</button>
      </span>
    {/if}
  </header>
  {#if !scoped.length}
    <p class="empty"><span class="ok">✓</span> {focus ? `No problems in ${focus.label}.` : 'No problems.'}</p>
  {:else}
    <ul>
      {#each visible as { d, cards }, i (i)}
        <li>
          <button class="item {d.severity}" onclick={() => onselect(d)} title="Go to the problem">
            <span class="badge">{icon[d.severity]}</span>
            <span class="main">
              <span class="line1">
                <span class="msg">
                  {#each parts(body(d.message)) as p}{#if p.code}<code>{p.text}</code>{:else}{p.text}{/if}{/each}
                </span>
              </span>
              {#if d.hint}
                <span class="fix">{#each parts(d.hint) as p}{#if p.code}<code>{p.text}</code>{:else}{p.text}{/if}{/each}</span>
              {/if}
              <span class="meta">
                <span class="chip codechip" title="Code {d.code}: {area[String(d.code)[0]] ?? 'other'}">{d.code}</span>
                <span class="chip file" title={d.file}>{short(d.file)}{d.line ? `:${d.line}` : ''}</span>
                {#each crumbs(d) as c, k}
                  {#if k}<span class="sep">›</span>{/if}<span class="crumb">{c}</span>
                {/each}
                {#if cards.length}
                  <span class="cards" title={cards.join(', ')}>{cards.length === 1 ? `card ${cards[0]}` : `${cards.length} cards`}</span>
                {/if}
              </span>
            </span>
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .problems {
    height: 100%;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  header {
    padding: 5px 12px;
    border-bottom: 1px solid var(--line);
    display: flex;
    gap: 8px;
    align-items: center;
    flex-wrap: wrap;
  }
  .toggle {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    font-size: 12px;
    min-height: 24px;
    box-sizing: border-box;
    padding: 1px 8px 1px 3px;
    border-radius: 999px;
  }
  .toggle.off {
    opacity: 0.45;
  }
  .dot {
    display: inline-grid;
    place-items: center;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    font-size: 10px;
    font-weight: 700;
    color: var(--on-status);
  }
  .error .dot,
  .error .badge {
    background: var(--err);
  }
  .warning .dot,
  .warning .badge {
    background: var(--warn);
    color: #000;
  }
  .hint .dot,
  .hint .badge {
    background: var(--muted);
  }
  .focus {
    font-size: 12px;
    color: var(--muted);
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }
  .focus b {
    color: var(--fg);
    font-family: var(--mono);
    font-weight: 500;
  }
  .clear {
    padding: 0 6px;
    line-height: 1.2;
  }
  .empty {
    padding: 10px 12px;
    color: var(--muted);
    margin: 0;
  }
  .ok {
    color: #2e9e5b;
    font-weight: 700;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 6px 8px;
    overflow: auto;
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .item {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: flex;
    gap: 10px;
    padding: 7px 10px;
    border-radius: 8px;
    border: 1px solid var(--line);
    border-left-width: 4px;
    cursor: pointer;
    background: var(--bg);
  }
  .item:hover,
  .item:focus-visible {
    background: var(--hover);
  }
  .item.error {
    border-left-color: var(--err);
    background: color-mix(in srgb, var(--err) 5%, var(--bg));
  }
  .item.warning {
    border-left-color: var(--warn);
    background: color-mix(in srgb, var(--warn) 6%, var(--bg));
  }
  .item.hint {
    border-left-color: var(--muted);
  }
  .badge {
    flex: none;
    display: grid;
    place-items: center;
    width: 18px;
    height: 18px;
    margin-top: 1px;
    border-radius: 50%;
    font-size: 11px;
    font-weight: 700;
    color: var(--on-status);
  }
  .main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .msg {
    font-size: 13px;
    line-height: 1.45;
  }
  code {
    font-family: var(--mono);
    font-size: 12px;
    padding: 0 4px;
    border-radius: 4px;
    background: var(--hover);
    border: 1px solid var(--line);
    overflow-wrap: anywhere;
  }
  .fix {
    font-size: 12px;
    color: var(--muted);
  }
  .fix::before {
    content: 'Fix: ';
    font-weight: 600;
    color: var(--accent);
  }
  .meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px;
    font-size: 11px;
    color: var(--muted);
  }
  .chip {
    font-family: var(--mono);
    padding: 0 5px;
    border-radius: 4px;
    border: 1px solid var(--line);
    background: var(--bg-bar);
  }
  .crumb {
    font-family: var(--mono);
  }
  .sep {
    opacity: 0.6;
  }
  .cards {
    margin-left: auto;
    padding: 0 6px;
    border-radius: 999px;
    background: var(--sel);
    color: var(--fg);
  }
</style>
