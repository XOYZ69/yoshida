<script lang="ts">
// Layer list, topmost first (the design's arrays are bottom first). Groups
// are folders: click the arrow to fold them, drop a layer onto a group to
// move it inside. Ctrl/Cmd+click adds to the selection, Shift+click
// selects a range; right-click opens the layer menu. The eye sets the
// layer's `visible`; the lock only stops canvas selection in the editor.
// Dividers are titled rules that only organise the list. Right-click on
// empty space opens the menu for adding layers.
import { childrenOf, isDivider, isGroup, type Obj } from "../design";

let {
	layers,
	selected,
	locked,
	problems,
	onselect,
	onvisible,
	onlock,
	onmove,
	oncontext,
}: {
	layers: Obj[];
	selected: string[];
	locked: Set<string>;
	problems: Map<string, "error" | "warning">;
	onselect: (ids: string[]) => void;
	onvisible: (id: string) => void;
	onlock: (id: string) => void;
	/** Drag and drop: above/below a layer, into a group, or to the very bottom (target null). */
	onmove: (
		ids: string[],
		target: string | null,
		where: "above" | "below" | "into",
	) => void;
	/** Right-click on a layer, or on empty space (id null). */
	oncontext: (e: MouseEvent, id: string | null) => void;
} = $props();

const icons: Record<string, string> = {
	rect: "▭",
	ellipse: "◯",
	polygon: "△",
	text: "T",
	image: "🖼",
	group: "▤",
};

let folded = $state(new Set<string>());

type Row = {
	l: Obj;
	id: string;
	depth: number;
	group: boolean;
	divider: boolean;
	count: number;
	hiddenBy: boolean;
};
const rows = $derived.by(() => {
	const out: Row[] = [];
	const walk = (list: Obj[], depth: number, hiddenBy: boolean) => {
		for (let i = list.length - 1; i >= 0; i--) {
			const l = list[i];
			const id = String(l.id ?? `#${i}`);
			const group = isGroup(l);
			const kids = group ? childrenOf(l) : [];
			out.push({
				l,
				id,
				depth,
				group,
				divider: isDivider(l),
				count: kids.filter((k) => !isDivider(k)).length,
				hiddenBy,
			});
			if (group && !folded.has(id))
				walk(kids, depth + 1, hiddenBy || l.visible === false);
		}
	};
	walk(layers, 0, false);
	return out;
});

let anchor: string | null = null;

function pick(id: string, e: MouseEvent) {
	if (e.shiftKey && anchor && selected.includes(anchor)) {
		const order = rows.map((r) => r.id);
		const [a, b] = [order.indexOf(anchor), order.indexOf(id)].sort(
			(x, y) => x - y,
		);
		onselect(order.slice(a, b + 1));
		return;
	}
	anchor = id;
	if (e.ctrlKey || e.metaKey)
		onselect(
			selected.includes(id)
				? selected.filter((x) => x !== id)
				: [...selected, id],
		);
	else onselect([id]);
}

function fold(id: string) {
	const next = new Set(folded);
	if (!next.delete(id)) next.add(id);
	folded = next;
}

// ---------------------------------------------------------------- drag and drop

let dragIds: string[] = [];
let drop: { id: string | null; where: "above" | "below" | "into" } | null =
	$state(null);

function zone(e: DragEvent, r: Row): "above" | "below" | "into" {
	const b = (e.currentTarget as HTMLElement).getBoundingClientRect();
	const f = (e.clientY - b.top) / b.height;
	if (r.group)
		return f < 0.25
			? "above"
			: f > 0.75 && (folded.has(r.id) || !r.count)
				? "below"
				: "into";
	return f < 0.5 ? "above" : "below";
}

function dragstart(e: DragEvent, id: string) {
	dragIds = selected.includes(id)
		? rows.map((r) => r.id).filter((x) => selected.includes(x))
		: [id];
	e.dataTransfer?.setData("text/x-yoshida-layer", dragIds.join(","));
	if (e.dataTransfer) e.dataTransfer.effectAllowed = "move";
}

function finish() {
	if (drop && dragIds.length && !(drop.id && dragIds.includes(drop.id)))
		onmove(dragIds, drop.id, drop.where);
	dragIds = [];
	drop = null;
}
</script>

<ul
  class="tree"
  role="tree"
  aria-label="Layers"
  aria-multiselectable="true"
  oncontextmenu={(e) => {
    // Rows handle their own menu first.
    if (e.defaultPrevented) return;
    e.preventDefault();
    oncontext(e, null);
  }}>
  {#each rows as r (r.id)}
    {@const vis = r.l.visible}
    <li
      role="treeitem"
      aria-selected={selected.includes(r.id)}
      aria-expanded={r.group ? !folded.has(r.id) : undefined}
      class:selected={selected.includes(r.id)}
      class:drop-above={drop?.id === r.id && drop.where === 'above'}
      class:drop-below={drop?.id === r.id && drop.where === 'below'}
      class:drop-into={drop?.id === r.id && drop.where === 'into'}
      class:dimmed={r.hiddenBy}
      style:--depth={r.depth}
      draggable="true"
      ondragstart={(e) => dragstart(e, r.id)}
      ondragover={(e) => {
        if (!dragIds.length) return;
        e.preventDefault();
        drop = { id: r.id, where: zone(e, r) };
      }}
      ondrop={(e) => {
        e.preventDefault();
        finish();
      }}
      ondragend={() => {
        dragIds = [];
        drop = null;
      }}
      oncontextmenu={(e) => {
        e.preventDefault();
        if (!selected.includes(r.id)) onselect([r.id]);
        oncontext(e, r.id);
      }}>
      {#if r.divider}
        <span class="fold-space"></span>
        <button class="row divider" onclick={(e) => pick(r.id, e)} title={r.l.note ? String(r.l.note) : `Divider '${r.id}'`}>
          <span class="rule"></span>
          <span class="dlabel">{typeof r.l.label === 'string' && r.l.label ? r.l.label : r.id}</span>
          <span class="rule"></span>
          {#if problems.get(r.id)}<span class="dot {problems.get(r.id)}" title="Has problems"></span>{/if}
        </button>
        <span class="tools">
          <button
            class="tool"
            title="More actions"
            onclick={(e) => {
              if (!selected.includes(r.id)) onselect([r.id]);
              oncontext(e, r.id);
            }}>⋯</button>
        </span>
      {:else}
        {#if r.group}
          <button class="fold" aria-label={folded.has(r.id) ? 'Expand group' : 'Collapse group'} onclick={() => fold(r.id)}>{folded.has(r.id) ? '▸' : '▾'}</button>
        {:else}
          <span class="fold-space"></span>
        {/if}
        <button class="row" onclick={(e) => pick(r.id, e)}>
          <span class="icon" class:grp={r.group}>{icons[String(r.l.type)] ?? '?'}</span>
          <span class="name" class:off={vis === false} title={r.id}>{r.id}</span>
          {#if r.group}<span class="badge" title="{r.count} layers">{r.count}</span>{/if}
          {#if r.l.repeat}<span class="badge" title="Repeated">⟳</span>{/if}
          {#if r.l.extends}<span class="badge" title="Extends {r.l.extends}">↳{r.l.extends}</span>{/if}
          {#if Array.isArray(r.l.effects) && r.l.effects.length}<span class="badge" title="Effects">✦</span>{/if}
          {#if problems.get(r.id)}<span class="dot {problems.get(r.id)}" title="Has problems"></span>{/if}
        </button>
        <span class="tools">
          <button
            class="tool"
            title={typeof vis === 'string' ? `visible: ${vis}` : vis === false ? 'Show' : 'Hide'}
            disabled={typeof vis === 'string'}
            onclick={() => onvisible(r.id)}>{typeof vis === 'string' ? 'fx' : vis === false ? '◌' : '👁'}</button>
          <button class="tool" class:on={locked.has(r.id)} title={locked.has(r.id) ? 'Unlock' : 'Lock (canvas clicks pass through)'} onclick={() => onlock(r.id)}
            >{locked.has(r.id) ? '🔒' : '🔓'}</button>
          <button
            class="tool"
            title="More actions"
            onclick={(e) => {
              if (!selected.includes(r.id)) onselect([r.id]);
              oncontext(e, r.id);
            }}>⋯</button>
        </span>
      {/if}
    </li>
  {/each}
  <!-- Dropping below the last row moves the layers to the bottom. -->
  <li
    class="end"
    class:drop-above={drop?.id === null}
    ondragover={(e) => {
      if (!dragIds.length) return;
      e.preventDefault();
      drop = { id: null, where: 'below' };
    }}
    ondrop={(e) => {
      e.preventDefault();
      finish();
    }}>
    {#if !layers.length}<span class="empty">No layers yet. Add one from the toolbar, or right-click here.</span>{/if}
  </li>
</ul>

<style>
  .tree {
    list-style: none;
    margin: 0;
    padding: 4px 0;
  }
  li {
    display: flex;
    align-items: center;
    border-top: 2px solid transparent;
    border-bottom: 2px solid transparent;
    padding-left: calc(4px + var(--depth, 0) * 14px);
    position: relative;
  }
  li.drop-above {
    border-top-color: var(--accent);
  }
  li.drop-below {
    border-bottom-color: var(--accent);
  }
  li.drop-into {
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    outline: 1px dashed var(--accent);
    outline-offset: -1px;
  }
  li:hover {
    background: var(--hover);
  }
  li.selected {
    background: var(--sel);
  }
  li.dimmed {
    opacity: 0.55;
  }
  .fold,
  .fold-space {
    width: 18px;
    flex: none;
  }
  .fold {
    all: unset;
    width: 18px;
    display: grid;
    place-items: center;
    height: 24px;
    cursor: pointer;
    color: var(--muted);
    font-size: 11px;
    border-radius: 4px;
  }
  .fold:hover {
    background: var(--line);
  }
  .row {
    all: unset;
    flex: 1;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 4px;
    cursor: pointer;
    min-width: 0;
  }
  .icon {
    width: 16px;
    text-align: center;
    color: var(--muted);
    font-size: 12px;
  }
  .icon.grp {
    color: var(--accent);
  }
  .name {
    font-family: var(--mono);
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .name.off {
    text-decoration: line-through;
    color: var(--muted);
  }
  .badge {
    font-size: 10px;
    color: var(--accent);
    white-space: nowrap;
  }
  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    flex: none;
  }
  .dot.error {
    background: var(--err);
  }
  .dot.warning {
    background: var(--warn);
  }
  /* The row tools float over the end of the name instead of reserving
     width, so names are only cut while the tools are showing. */
  .tools {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    display: flex;
    align-items: center;
    gap: 0;
    padding: 0 4px;
    visibility: hidden;
    background: var(--hover);
  }
  li:hover .tools,
  li:focus-within .tools,
  li.selected .tools {
    visibility: visible;
  }
  li.selected .tools {
    background: var(--sel);
  }
  .tool {
    all: unset;
    display: inline-grid;
    place-items: center;
    min-width: 24px;
    height: 24px;
    cursor: pointer;
    font-size: 12px;
    border-radius: 4px;
    color: var(--muted);
  }
  /* Rows sit flush in a scrolling list: draw their focus ring inside. */
  .row:focus-visible,
  .fold:focus-visible,
  .tool:focus-visible {
    outline-offset: -2px !important;
  }
  .tool:hover {
    background: var(--line);
  }
  .tool.on {
    opacity: 1;
  }
  .tool:disabled {
    cursor: default;
  }
  li.end {
    min-height: 24px;
  }
  .tree {
    min-height: 100%;
    box-sizing: border-box;
  }
  .row.divider {
    gap: 6px;
    padding: 6px 4px 4px;
  }
  .rule {
    flex: 1;
    height: 1px;
    min-width: 8px;
    background: var(--line);
  }
  .dlabel {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 70%;
  }
  li.selected .dlabel {
    color: var(--fg);
  }
  .empty {
    padding: 8px 12px;
    color: var(--muted);
    font-size: 12px;
  }
</style>
