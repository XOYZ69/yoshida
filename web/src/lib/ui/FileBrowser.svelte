<script lang="ts">
// The project's files as a folder tree. Click a folder to make it the
// target for uploads, right-click for actions, drag files onto a folder
// to move them, drop files from the computer onto a folder to add them
// there. Renames and moves rewrite the references to the file (the parent
// does that through `onrename`).

import { buildTree, dirOf, join, nameError, type TreeNode } from "../paths";
import { type Files, isImage } from "../project";
import { formatSize } from "../store";
import { askText, type MenuItem, openMenu } from "./overlay.svelte";

let {
	files,
	selected = $bindable(null),
	folder = $bindable(""),
	highlight = null,
	dirty,
	uses,
	onopen,
	onrename,
	ondelete,
	onmove,
	onnewfolder,
	onupload,
	onduplicate,
	ondropfiles,
}: {
	files: Files;
	/** The selected file. */
	selected?: string | null;
	/** The selected folder: where uploads go ('' is the project root). */
	folder?: string;
	/** A file to scroll to and flash, such as one just added. */
	highlight?: string | null;
	dirty: Set<string>;
	/** How many files refer to each path. */
	uses: Map<string, number>;
	onopen: (path: string) => void;
	onrename: (from: string, to: string) => void;
	ondelete: (path: string) => void;
	onmove: (paths: string[], folder: string) => void;
	onnewfolder: (parent: string, name: string) => void;
	onupload: (folder: string) => void;
	onduplicate: (path: string) => void;
	ondropfiles: (list: File[], folder: string) => void;
} = $props();

const tree = $derived(buildTree(files));
let folded = $state(new Set<string>());
let query = $state("");

type Row = { node: TreeNode; depth: number };
const rows = $derived.by(() => {
	const out: Row[] = [];
	const q = query.trim().toLowerCase();
	const matches = (n: TreeNode): boolean =>
		n.dir ? n.children.some(matches) : n.path.toLowerCase().includes(q);
	const walk = (n: TreeNode, depth: number) => {
		for (const c of n.children) {
			if (q && !matches(c)) continue;
			out.push({ node: c, depth });
			if (c.dir && (q || !folded.has(c.path))) walk(c, depth + 1);
		}
	};
	walk(tree, 0);
	return out;
});

// Small previews for images; URLs are made once per file content.
const urlCache = new Map<Uint8Array, string>();
const thumbs = $derived.by(() => {
	const m = new Map<string, string>();
	for (const [p, d] of files) {
		if (!isImage(p)) continue;
		let u = urlCache.get(d);
		if (!u) {
			u = URL.createObjectURL(new Blob([d as BlobPart]));
			urlCache.set(d, u);
		}
		m.set(p, u);
	}
	return m;
});
$effect(() => {
	const live = new Set(files.values());
	for (const [d, u] of urlCache)
		if (!live.has(d)) {
			URL.revokeObjectURL(u);
			urlCache.delete(d);
		}
});
$effect(() => () => {
	for (const u of urlCache.values()) URL.revokeObjectURL(u);
});

let list: HTMLUListElement | undefined = $state();
$effect(() => {
	const h = highlight;
	if (!h || !list) return;
	// Unfold the folders around it, then scroll it into view.
	let d = dirOf(h);
	const next = new Set(folded);
	while (d) {
		next.delete(d);
		d = dirOf(d);
	}
	if (next.size !== folded.size) folded = next;
	requestAnimationFrame(() =>
		list
			?.querySelector(`[data-path="${CSS.escape(h)}"]`)
			?.scrollIntoView({ block: "nearest" }),
	);
});

function icon(n: TreeNode) {
	if (n.dir) return folded.has(n.path) && !query ? "📁" : "📂";
	if (/\.design\.json$/i.test(n.name)) return "◧";
	if (/\.cards\.(json|csv)$/i.test(n.name)) return "▦";
	if (/\.(ttf|otf)$/i.test(n.name)) return "Aa";
	if (/\.json$/i.test(n.name)) return "{}";
	return "·";
}

function click(n: TreeNode) {
	if (n.dir) {
		folder = n.path;
		selected = null;
		const next = new Set(folded);
		if (!next.delete(n.path)) next.add(n.path);
		folded = next;
	} else {
		// The upload folder only changes when a folder is clicked.
		selected = n.path;
		onopen(n.path);
	}
}

async function rename(n: TreeNode) {
	const parent = dirOf(n.path);
	const name = await askText({
		title: `Rename ${n.dir ? "folder" : "file"} '${n.name}'`,
		message: "References in designs and card data are updated too.",
		value: n.name,
		confirm: "Rename",
		validate: (v) =>
			nameError(v.trim()) ||
			(v.trim() !== n.name && exists(join(parent, v.trim()))
				? `'${v.trim()}' already exists here.`
				: ""),
	});
	const to = name?.trim();
	if (to && to !== n.name) onrename(n.path, join(parent, to));
}

function exists(path: string) {
	return (
		files.has(path) || [...files.keys()].some((p) => p.startsWith(`${path}/`))
	);
}

async function newFolder(parent: string) {
	const name = (
		await askText({
			title: "New folder",
			message: parent ? `Inside ${parent}/` : "At the top of the project",
			placeholder: "images",
			confirm: "Create",
			validate: (v) =>
				nameError(v.trim()) ||
				(exists(join(parent, v.trim())) ? "That already exists." : ""),
		})
	)?.trim();
	if (name) {
		onnewfolder(parent, name);
		folder = join(parent, name);
	}
}

function menu(e: MouseEvent, n: TreeNode | null) {
	e.preventDefault();
	e.stopPropagation();
	const target = n ? (n.dir ? n.path : dirOf(n.path)) : "";
	const items: MenuItem[] = [];
	if (n && !n.dir) {
		items.push({ label: "Open", action: () => click(n) });
		items.push(
			{ label: "Rename…", icon: "✎", action: () => rename(n) },
			{ label: "Duplicate", icon: "⧉", action: () => onduplicate(n.path) },
		);
	}
	if (n?.dir)
		items.push({ label: "Rename folder…", icon: "✎", action: () => rename(n) });
	if (n) items.push({ separator: true });
	items.push(
		{
			label: target ? `Upload to ${target}/…` : "Upload to the project root…",
			icon: "⤒",
			action: () => onupload(target),
		},
		{
			label: "New folder…",
			icon: "📁",
			detail: target ? `in ${target}/` : "",
			action: () => newFolder(target),
		},
	);
	if (n) {
		const uses_ = n.dir ? 0 : (uses.get(n.path) ?? 0);
		items.push(
			{ separator: true },
			{
				label: n.dir ? "Delete folder…" : "Delete…",
				icon: "🗑",
				danger: true,
				detail: uses_ ? `used by ${uses_} file${uses_ > 1 ? "s" : ""}` : "",
				action: () => ondelete(n.path),
			},
		);
	}
	openMenu(e.clientX, e.clientY, items);
}

// ---------------------------------------------------------------- drag and drop

let dragPaths: string[] = [];
let dropDir: string | null = $state(null);

function dropTargetOf(n: TreeNode | null) {
	return n ? (n.dir ? n.path : dirOf(n.path)) : "";
}

function over(e: DragEvent, n: TreeNode | null) {
	const t = e.dataTransfer?.types ?? [];
	if (e.defaultPrevented || (!dragPaths.length && !t.includes("Files"))) return;
	e.preventDefault();
	dropDir = dropTargetOf(n);
}

function dropOn(e: DragEvent, n: TreeNode | null) {
	// The row handles a drop first; the list and the app then see it as handled.
	if (e.defaultPrevented) return;
	const dir = dropTargetOf(n);
	const osFiles = Array.from(e.dataTransfer?.files ?? []);
	e.preventDefault();
	if (dragPaths.length) {
		const moving = dragPaths.filter(
			(p) => dirOf(p) !== dir && dir !== p && !dir.startsWith(`${p}/`),
		);
		if (moving.length) onmove(moving, dir);
	} else if (osFiles.length) ondropfiles(osFiles, dir);
	dragPaths = [];
	dropDir = null;
}
</script>

<div class="browser">
  <div class="bar">
    <input type="search" placeholder="Find a file…" bind:value={query} aria-label="Find a file" />
    <button title="Upload files to {folder ? `${folder}/` : 'the project root'}" onclick={() => onupload(folder)}>⤒</button>
    <button title="New folder in {folder ? `${folder}/` : 'the project root'}" onclick={() => newFolder(folder)}>＋📁</button>
  </div>
  <div class="target" title="Uploads and new folders go here. Click a folder to change it.">
    Adding to <span class="mono">{folder ? `${folder}/` : 'project root'}</span>
    {#if folder}<button class="link" onclick={() => (folder = '')}>root</button>{/if}
  </div>
  <ul
    bind:this={list}
    class="ftree"
    class:drop-root={dropDir === ''}
    role="tree"
    aria-label="Project files"
    oncontextmenu={(e) => menu(e, null)}
    ondragover={(e) => over(e, null)}
    ondragleave={(e) => {
      if (!e.relatedTarget || !(e.currentTarget as Node).contains(e.relatedTarget as Node)) dropDir = null;
    }}
    ondrop={(e) => dropOn(e, null)}>
    {#each rows as r (r.node.path)}
      {@const n = r.node}
      <li
        role="treeitem"
        aria-selected={n.dir ? folder === n.path && !selected : selected === n.path}
        aria-expanded={n.dir ? !folded.has(n.path) : undefined}
        data-path={n.path}
        class:sel={n.dir ? folder === n.path && !selected : selected === n.path}
        class:flash={highlight === n.path}
        class:drop={n.dir && dropDir === n.path}
        style:--depth={r.depth}
        draggable="true"
        ondragstart={(e) => {
          dragPaths = [n.path];
          e.dataTransfer?.setData('text/x-yoshida-file', n.path);
          if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
        }}
        ondragend={() => {
          dragPaths = [];
          dropDir = null;
        }}
        ondragover={(e) => over(e, n)}
        ondrop={(e) => dropOn(e, n)}
        oncontextmenu={(e) => menu(e, n)}>
        <button class="row" onclick={() => click(n)} ondblclick={() => !n.dir && rename(n)} title={n.path}>
          {#if !n.dir && thumbs.has(n.path)}
            <img class="thumb" src={thumbs.get(n.path)} alt="" loading="lazy" />
          {:else}
            <span class="icon" class:dir={n.dir}>{icon(n)}</span>
          {/if}
          <span class="name">{n.name}{dirty.has(n.path) ? ' •' : ''}</span>
          {#if !n.dir && (uses.get(n.path) ?? 0) > 0}<span class="uses" title="Referred to by {uses.get(n.path)} file(s)">{uses.get(n.path)}↩</span>{/if}
          <span class="size">{n.dir ? `${n.children.length}` : formatSize(n.size)}</span>
        </button>
      </li>
    {/each}
    {#if !rows.length}<li class="empty">{query ? 'No file matches.' : 'No files yet.'}</li>{/if}
  </ul>
</div>

<style>
  .browser {
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .bar {
    display: flex;
    gap: 4px;
    padding: 8px 12px 4px;
  }
  .bar input {
    flex: 1;
    min-width: 0;
  }
  .bar button {
    padding: 2px 8px;
  }
  .target {
    font-size: 11px;
    color: var(--muted);
    padding: 0 12px 6px;
    display: flex;
    gap: 4px;
    align-items: baseline;
    white-space: nowrap;
    overflow: hidden;
  }
  .mono {
    font-family: var(--mono);
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .link {
    all: unset;
    color: var(--accent);
    cursor: pointer;
    text-decoration: underline;
  }
  .ftree {
    list-style: none;
    margin: 0;
    padding: 2px 0 24px;
    flex: 1;
    min-height: 80px;
  }
  .ftree.drop-root {
    outline: 2px dashed var(--accent);
    outline-offset: -2px;
  }
  li {
    padding-left: calc(var(--depth, 0) * 14px);
  }
  li.sel {
    background: var(--sel);
  }
  li.drop {
    background: color-mix(in srgb, var(--accent) 18%, transparent);
  }
  li.flash {
    animation: flash 1.6s ease-out;
  }
  @keyframes flash {
    from {
      background: color-mix(in srgb, var(--accent) 40%, transparent);
    }
  }
  .row {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 12px;
    cursor: pointer;
    font-size: 13px;
  }
  .row:hover {
    background: var(--hover);
  }
  .icon {
    width: 18px;
    text-align: center;
    font-size: 11px;
    color: var(--muted);
    flex: none;
  }
  .icon.dir {
    font-size: 13px;
  }
  .thumb {
    width: 18px;
    height: 18px;
    object-fit: contain;
    flex: none;
    background: repeating-conic-gradient(#ccc 0 25%, #eee 0 50%) 0 0 / 6px 6px;
    border-radius: 2px;
  }
  .name {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .uses {
    font-size: 10px;
    color: var(--accent);
  }
  .size {
    font-size: 11px;
    color: var(--muted);
    white-space: nowrap;
  }
  .empty {
    padding: 8px 12px;
    font-size: 12px;
    color: var(--muted);
  }
</style>
