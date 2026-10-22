<script lang="ts">
// The project's files as a folder tree. Click a folder to make it the
// target for uploads, right-click for actions, drag files onto a folder
// to move them, drop files from the computer onto a folder to add them
// there. Renames and moves rewrite the references to the file (the parent
// does that through `onrename`).

import { type FileType, fileType } from "../filetypes";
import { buildTree, dirOf, join, nameError, type TreeNode } from "../paths";
import { type Files, isImage } from "../project";
import { formatSize } from "../store";
import Icon, { type IconName } from "./Icon.svelte";
import { askText, type MenuItem, openMenu } from "./overlay.svelte";

let {
	files,
	selected = $bindable(null),
	folder = $bindable(""),
	highlight = null,
	dirty,
	saveTarget = null,
	uses,
	usedBy,
	problems,
	onopen,
	onrename,
	ondelete,
	onmove,
	onnewfolder,
	onnewdesign,
	onnewcards,
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
	/** Name of the connected folder that Save writes to; the unsaved marker only shows with one. */
	saveTarget?: string | null;
	/** How many files refer to each path. */
	uses: Map<string, number>;
	/** The files that refer to each path, sorted. */
	usedBy: Map<string, string[]>;
	/** Errors and warnings per file path; hints are not counted. */
	problems: Map<string, { errors: number; warnings: number }>;
	onopen: (path: string) => void;
	onrename: (from: string, to: string) => void;
	ondelete: (path: string) => void;
	onmove: (paths: string[], folder: string) => void;
	onnewfolder: (parent: string, name: string) => void;
	/** Adds a design with its own card file. Left out: no design items. */
	onnewdesign?: () => void;
	/** Adds a card file for the design at this path, or asks which design (in a menu at `at`) when none is given. */
	onnewcards?: (design?: string, at?: { x: number; y: number }) => void;
	onupload: (folder: string) => void;
	onduplicate: (path: string) => void;
	ondropfiles: (list: File[], folder: string) => void;
} = $props();

const tree = $derived(buildTree(files));
/** Files under a folder, counted recursively. */
function fileCount(n: TreeNode): number {
	return n.children.reduce((t, c) => t + (c.dir ? fileCount(c) : 1), 0);
}
const totalFiles = $derived(fileCount(tree));

type Problems = { errors: number; warnings: number };
const noProblems: Problems = { errors: 0, warnings: 0 };
/** Problems of every node: a folder adds up the files under it. */
const nodeProblems = $derived.by(() => {
	const m = new Map<string, Problems>();
	const sum = (n: TreeNode): Problems => {
		if (!n.dir) {
			const p = problems.get(n.path) ?? noProblems;
			m.set(n.path, p);
			return p;
		}
		const t = { errors: 0, warnings: 0 };
		for (const c of n.children) {
			const p = sum(c);
			t.errors += p.errors;
			t.warnings += p.warnings;
		}
		m.set(n.path, t);
		return t;
	};
	sum(tree);
	return m;
});
/** Tooltip of the problem icon, e.g. "2 errors, 1 warning in this folder". */
function problemText(p: Problems, dir: boolean): string {
	const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
	const parts: string[] = [];
	if (p.errors) parts.push(plural(p.errors, "error"));
	if (p.warnings) parts.push(plural(p.warnings, "warning"));
	return parts.join(", ") + (dir ? " in this folder" : "");
}
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
/** Thumbnail URLs the browser could not decode; those files show the image icon. */
let broken = $state(new Set<string>());

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

const typeIcons: Record<FileType, IconName> = {
	design: "design",
	cards: "table",
	json: "braces",
	font: "font",
	markdown: "markdown",
	pdf: "pdf",
	text: "file-text",
	image: "image",
	file: "file",
};

function iconOf(n: TreeNode): IconName {
	if (n.dir) return folded.has(n.path) && !query ? "folder" : "folder-open";
	return typeIcons[fileType(n.path)];
}

/** Gives the name the full path as a tooltip, only when it is cut off. */
function fitTitle(e: MouseEvent, path: string) {
	const name = (e.currentTarget as HTMLElement).querySelector<HTMLElement>(
		".name",
	);
	const label = name?.querySelector(".label");
	if (name && label)
		name.title = label.scrollWidth > label.clientWidth ? path : "";
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

/** The design and card file items of the New button. */
function newItems(at: { x: number; y: number }): MenuItem[] {
	const out: MenuItem[] = [];
	if (onnewdesign)
		out.push({
			label: "Design…",
			icon: "design",
			detail: "with its own card file",
			action: () => onnewdesign(),
		});
	if (onnewcards)
		out.push({
			label: "Card file…",
			icon: "table",
			detail: "for an existing design",
			action: () => onnewcards(undefined, at),
		});
	return out;
}

function newMenu(e: MouseEvent) {
	const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
	const items = newItems({ x: r.left, y: r.bottom + 4 });
	if (items.length) items.push({ separator: true });
	items.push({
		label: "Folder…",
		icon: "folder-plus",
		detail: folder ? `in ${folder}/` : "at the project root",
		action: () => newFolder(folder),
	});
	openMenu(r.left, r.bottom + 4, items);
}

function menu(e: MouseEvent, n: TreeNode | null) {
	e.preventDefault();
	e.stopPropagation();
	const target = n ? (n.dir ? n.path : dirOf(n.path)) : "";
	const items: MenuItem[] = [];
	if (n?.dir && n.path === "designs" && onnewdesign)
		items.push({
			label: "New design…",
			icon: "design",
			detail: "with its own card file",
			action: () => onnewdesign(),
		});
	if (n?.dir && n.path === "cards" && onnewcards)
		items.push({
			label: "New card file…",
			icon: "table",
			action: () => onnewcards(undefined, { x: e.clientX, y: e.clientY }),
		});
	if (n && !n.dir) {
		items.push({ label: "Open", action: () => click(n) });
		items.push(
			{ label: "Rename…", icon: "pencil", action: () => rename(n) },
			{ label: "Duplicate", icon: "copy", action: () => onduplicate(n.path) },
		);
		if (onnewcards && /\.design\.json$/i.test(n.name))
			items.push({
				label: "New card file for this design…",
				icon: "table",
				action: () => onnewcards(n.path),
			});
	}
	if (n?.dir)
		items.push({ label: "Rename folder…", icon: "pencil", action: () => rename(n) });
	if (n) items.push({ separator: true });
	items.push(
		{
			label: target ? `Upload to ${target}/…` : "Upload to the project root…",
			icon: "upload",
			action: () => onupload(target),
		},
		{
			label: "New folder…",
			icon: "folder-plus",
			detail: target ? `in ${target}/` : "",
			action: () => newFolder(target),
		},
	);
	if (!n && onnewdesign)
		items.push({
			label: "New design…",
			icon: "design",
			detail: "with its own card file",
			action: () => onnewdesign(),
		});
	if (n) {
		const uses_ = n.dir ? 0 : (uses.get(n.path) ?? 0);
		items.push(
			{ separator: true },
			{
				label: n.dir ? "Delete folder…" : "Delete…",
				icon: "trash",
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
    <button title="New design, card file or folder" aria-label="New" onclick={newMenu}><Icon name="plus" /></button>
    <button title="Upload files to {folder ? `${folder}/` : 'the project root'}" aria-label="Upload files" onclick={() => onupload(folder)}><Icon name="upload" /></button>
    <button title="New folder in {folder ? `${folder}/` : 'the project root'}" aria-label="New folder" onclick={() => newFolder(folder)}><Icon name="folder-plus" /></button>
  </div>
  <div
    class="target"
    title={folder
      ? 'Uploads and new folders go here. Click a folder to change it.'
      : 'Uploads and new folders go here. Click a folder to change it. Without one, Add files in the project menu sorts files by type.'}>
    <span class="target-icon"><Icon name="folder" /></span>
    {#if folder}
      <span class="where">Uploads go to <span class="mono">{folder}/</span></span>
      <button class="reset" title="Upload to the project root instead" aria-label="Use the project root" onclick={() => (folder = '')}><Icon name="close" /></button>
    {:else}
      <span class="where">Uploads go to the project root</span>
    {/if}
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
      {@const count = uses.get(n.path) ?? 0}
      {@const by = usedBy.get(n.path) ?? []}
      {@const pr = nodeProblems.get(n.path) ?? noProblems}
      {@const worst = pr.errors ? 'err' : pr.warnings ? 'warn' : ''}
      {@const type = n.dir ? 'folder' : fileType(n.path)}
      {@const thumb = n.dir ? undefined : thumbs.get(n.path)}
      <li
        role="treeitem"
        aria-selected={n.dir ? folder === n.path && !selected : selected === n.path}
        aria-expanded={n.dir ? !folded.has(n.path) : undefined}
        data-path={n.path}
        class:sel={n.dir ? folder === n.path && !selected : selected === n.path}
        class:flash={highlight === n.path}
        class:drop={n.dir && dropDir === n.path}
        class:upload-dir={n.dir && folder === n.path}
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
        <button class="row" onmouseenter={(e) => fitTitle(e, n.path)} onclick={() => click(n)} ondblclick={() => !n.dir && rename(n)}>
          {#if thumb && !broken.has(thumb)}
            <img
              class="thumb"
              src={thumb}
              alt=""
              loading="lazy"
              data-type={type}
              onerror={() => (broken = new Set(broken).add(thumb))} />
          {:else}
            <span class="icon" data-type={type}><Icon name={iconOf(n)} /></span>
          {/if}
          <span class="name" class:err={worst === 'err'} class:warn={worst === 'warn'}><span class="label">{n.name}{#if saveTarget && dirty.has(n.path)}<span class="unsaved" title="Not saved to {saveTarget} yet" role="img" aria-label="Not saved"></span>{/if}</span>{#if worst}<span class="problem" title={problemText(pr, n.dir)} role="img" aria-label={problemText(pr, n.dir)}><Icon name={pr.errors ? 'close' : 'alert'} /></span>{/if}{#if count}<span class="uses" title={`Used by:\n${by.join('\n')}`}>{count}↩</span>{/if}</span>
          <span class="size" title={n.dir ? `${fileCount(n)} file${fileCount(n) === 1 ? '' : 's'}` : undefined}>{formatSize(n.size)}</span>
        </button>
      </li>
    {/each}
    {#if !rows.length}<li class="empty">{query ? 'No file matches.' : 'No files yet.'}</li>{/if}
  </ul>
  {#if totalFiles}
    <div class="total">{totalFiles} file{totalFiles === 1 ? '' : 's'} · {formatSize(tree.size)}</div>
  {/if}
</div>

<style>
  /* Fills the panel; only the tree scrolls, between the bar and the total. */
  .browser {
    display: flex;
    flex-direction: column;
    flex: 1 0 auto;
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
    min-width: 30px;
    padding: 2px 8px;
  }
  .target {
    font-size: 11px;
    color: var(--muted);
    padding: 0 8px 4px 12px;
    display: flex;
    gap: 4px;
    align-items: center;
    min-height: 24px;
    white-space: nowrap;
    overflow: hidden;
  }
  .target-icon {
    flex: none;
    color: var(--accent);
  }
  .where {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .mono {
    font-family: var(--mono);
    color: var(--fg);
  }
  .reset {
    all: unset;
    flex: none;
    width: 24px;
    height: 24px;
    display: grid;
    place-items: center;
    border-radius: 4px;
    color: var(--muted);
    cursor: pointer;
  }
  .reset:hover {
    background: var(--hover);
    color: var(--fg);
  }
  .reset :global(svg) {
    width: 12px;
    height: 12px;
  }
  .ftree {
    list-style: none;
    margin: 0;
    padding: 2px 0 24px;
    flex: 1 1 0;
    min-height: 96px;
    overflow: auto;
  }
  .ftree.drop-root {
    outline: 2px dashed var(--accent);
    outline-offset: -2px;
  }
  /* One faint guide line per level, under the parent folders' icons. The
     colors below set only background-color so the lines stay. */
  li {
    background-image: repeating-linear-gradient(
      to right,
      transparent 0 7px,
      var(--line) 7px 8px,
      transparent 8px 10px
    );
    background-size: calc(var(--depth, 0) * 10px) 100%;
    background-position: 12px 0;
    background-repeat: no-repeat;
  }
  li.sel {
    background-color: var(--sel);
  }
  li.drop {
    background-color: color-mix(in srgb, var(--accent) 18%, transparent);
  }
  li.flash {
    animation: flash 1.6s ease-out;
  }
  @keyframes flash {
    from {
      background-color: color-mix(in srgb, var(--accent) 40%, transparent);
    }
  }
  /* The folder uploads go to, matching the line above the tree. */
  li.upload-dir .row {
    box-shadow: inset 2px 0 var(--accent);
  }
  li.upload-dir .icon {
    color: var(--accent);
  }
  .row {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: grid;
    /* The size column has one width at every depth, so the sizes line up. */
    grid-template-columns: 16px minmax(0, 1fr) 3.5em;
    align-items: center;
    column-gap: 6px;
    padding: 3px 12px 3px calc(12px + var(--depth, 0) * 10px);
    cursor: pointer;
    font-size: 13px;
  }
  .row:hover {
    background-color: var(--hover);
  }
  /* Rows sit flush in the scrolling tree: draw their focus ring inside. */
  .row:focus-visible {
    outline-offset: -2px;
  }
  .icon {
    width: 16px;
    color: var(--muted);
  }
  .icon[data-type='design'] {
    color: var(--file-design);
  }
  .icon[data-type='cards'] {
    color: var(--file-cards);
  }
  .icon[data-type='json'] {
    color: var(--file-json);
  }
  .icon[data-type='font'] {
    color: var(--file-font);
  }
  .icon[data-type='markdown'] {
    color: var(--file-markdown);
  }
  .icon[data-type='pdf'] {
    color: var(--file-pdf);
  }
  .icon[data-type='text'] {
    color: var(--file-text);
  }
  .icon[data-type='image'] {
    color: var(--file-image);
  }
  .thumb {
    box-sizing: border-box;
    width: 16px;
    height: 16px;
    object-fit: contain;
    border: 1px solid var(--line);
    border-radius: 3px;
    background: repeating-conic-gradient(var(--check-a) 0 25%, var(--check-b) 0 50%) 0 0 / 6px 6px;
  }
  .name {
    display: flex;
    align-items: center;
    min-width: 0;
  }
  .label {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .name.err {
    color: var(--err);
  }
  .name.warn {
    color: var(--warn-text);
  }
  /* On the selected row the fill is light; the icon carries the state there. */
  li.sel .name.err,
  li.sel .name.warn {
    color: inherit;
  }
  .problem {
    flex: none;
    display: inline-flex;
    margin-left: 4px;
  }
  .problem :global(svg) {
    width: 12px;
    height: 12px;
  }
  .unsaved {
    display: inline-block;
    width: 6px;
    height: 6px;
    margin-left: 6px;
    border-radius: 50%;
    background: var(--accent);
    vertical-align: middle;
  }
  /* Only shown when other files use this one, so it takes no room otherwise. */
  .uses {
    flex: none;
    margin-left: auto;
    padding-left: 6px;
    font-size: 10px;
    color: var(--accent);
    white-space: nowrap;
  }
  .size {
    font-size: 11px;
    color: var(--muted);
    text-align: right;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .total {
    flex: none;
    padding: 6px 12px;
    border-top: 1px solid var(--line);
    font-size: 11px;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .empty {
    padding: 8px 12px;
    font-size: 12px;
    color: var(--muted);
  }
</style>
