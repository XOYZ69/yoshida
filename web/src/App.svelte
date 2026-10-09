<script lang="ts">
import { zipSync } from "fflate";
import { onMount } from "svelte";
import {
	type AlignMode,
	alignLayers,
	ancestorsOf,
	childrenOf,
	clone,
	deleteLayer,
	distributeLayers,
	duplicateLayer,
	effectiveLayer,
	findLayer,
	type Gesture,
	getPath,
	groupLayers,
	type HandleMode,
	identRe,
	insertLayer,
	isDivider,
	isGroup,
	isObj,
	type LayerType,
	layerAtPointer,
	layerPointer,
	layersOf,
	layerTypes,
	literalNumber,
	moveIntoGroup,
	moveLayers,
	movePoint,
	newContainer,
	newLayer,
	type Obj,
	type Placed,
	paramsOf,
	parentOf,
	pasteLayers,
	referencesTo,
	renameEnumOption,
	renameLayer,
	renameParam,
	renameParamInCards,
	renameValueInCards,
	reorderLayer,
	resizeLayer,
	rotateLayer,
	stepLayer,
	ungroupLayer,
} from "./lib/design";
import {
	type CheckResult,
	type Diagnostic,
	Engine,
	type RenderResult,
} from "./lib/engine";
import {
	blankCards,
	blankDesign,
	bytesOf,
	type CardListOp,
	canOpenWritable,
	cardIdRe,
	download,
	type Example,
	editCardList,
	type Files,
	filesFromInput,
	filesFromZip,
	formatJson,
	importPath,
	isImage,
	isText,
	listExamples,
	loadExample,
	openWritable,
	PROJECT_EXT,
	PROJECT_MIME,
	parseCsv,
	pickDirectory,
	projectFileRe,
	projectZip,
	removeFile,
	setCardValue,
	slug,
	textOf,
	writeCsv,
	writeFile,
} from "./lib/project";
import {
	deleteProject,
	formatAge,
	formatSize,
	lastProject,
	listProjects,
	loadProject,
	newProjectId,
	type ProjectMeta,
	persistStorage,
	saveProject,
	setLastProject,
} from "./lib/store";

// CodeMirror is only needed in the Advanced view; load it on demand.
const loadEditor = () => import("./lib/Editor.svelte");

import Inspector from "./lib/builder/Inspector.svelte";
import LayerTree from "./lib/builder/LayerTree.svelte";
import ParamsPanel from "./lib/builder/ParamsPanel.svelte";
import Stage from "./lib/builder/Stage.svelte";
import CardForm from "./lib/CardForm.svelte";
import { listKeys as listKeysOf } from "./lib/expr/catalog";
import Problems from "./lib/Problems.svelte";
import {
	baseOf,
	dirOf,
	findRefs,
	freePath,
	isKeep,
	join,
	keepName,
	pathsUnder,
	rewriteRefs,
	useCounts,
} from "./lib/paths";
import CardBrowser from "./lib/ui/CardBrowser.svelte";
import CardList from "./lib/ui/CardList.svelte";
import CardPicker from "./lib/ui/CardPicker.svelte";
import DialogHost from "./lib/ui/DialogHost.svelte";
import { loadPref, savePref } from "./lib/ui/drag";
import FileBrowser from "./lib/ui/FileBrowser.svelte";
import MenuHost from "./lib/ui/MenuHost.svelte";
import {
	askText,
	confirmAction,
	type MenuItem,
	openMenu,
} from "./lib/ui/overlay.svelte";
import Select from "./lib/ui/Select.svelte";
import Icon from "./lib/ui/Icon.svelte";
import Splitter from "./lib/ui/Splitter.svelte";
import Window from "./lib/ui/Window.svelte";

const engine = new Engine();

let status = $state("Starting…");
let fatal = $state("");
let examples: Example[] = $state([]);
let projectName = $state("");
/** Id of the project in this browser's storage; null for an unchanged example. */
let projectId: string | null = $state(null);
let myProjects = $state.raw<ProjectMeta[]>([]);
let files = $state.raw<Files>(new Map());
let dirty = $state.raw(new Set<string>());
let dirHandle: FileSystemDirectoryHandle | null = $state(null);
let selected: string | null = $state(null);
let check = $state.raw<CheckResult | null>(null);
let setName = $state("");
let cardIndex = $state(0);
let lastRender = $state.raw<RenderResult | null>(null);
let renderMs = $state(0);
let jump: { line: number; col: number; nonce: number } | null = $state(null);
let sidePanel: "card" | "files" = $state("card");
let server: { render: boolean; max_cards: number } | null = $state(null);
let useServer = $state(false);
let busy = $state("");

// Builder state
let mode: "build" | "code" = $state("build");
let leftTab: "layers" | "params" | "card" | "files" = $state("layers");
let selectedLayers: string[] = $state([]);
const selectedLayer = $derived(
	selectedLayers.length === 1 ? selectedLayers[0] : null,
);
let locked = $state.raw(new Set<string>());
let image = $state.raw<ImageData | null>(null);
let layout = $state.raw<Placed[]>([]);
let stale = $state(false);

const today = new Date().toISOString().slice(0, 10);

// Panel sizes, remembered in this browser. null: share the space evenly.
const layoutDefaults = {
	left: 250,
	right: 370,
	bottom: 160,
	cardList: 220,
	files: 280,
	preview: null as number | null,
	codeBottom: 200,
};
let sizes = $state(loadPref("yoshida.layout", layoutDefaults));
const saveSizes = () => savePref("yoshida.layout", sizes);
// Saved sizes are clamped to the window, so a panel dragged wide on a big
// screen (or before the window shrank) never pushes the layout off-screen.
let winW = $state(window.innerWidth);
let winH = $state(window.innerHeight);
const clamp = (v: number, lo: number, hi: number) =>
	Math.max(lo, Math.min(Math.max(lo, hi), v));
/** Space left for the side panels: the window minus the splitter tracks and the smallest middle column. */
const sideRoom = $derived(winW - 10 - (mode === "build" ? 360 : 300));
const rightW = $derived(clamp(sizes.right, 260, sideRoom - 200));
const leftW = $derived(clamp(sizes.left, 200, sideRoom - rightW));
const previewW = $derived(
	sizes.preview === null ? null : clamp(sizes.preview, 260, sideRoom - 200),
);
const filesW = $derived(clamp(sizes.files, 200, sideRoom - (previewW ?? 320)));
/** The problems panel leaves the stage (or editor) at least 240px plus the top bar. */
const bottomMax = $derived(Math.max(60, winH - 320));
const bottomH = $derived(
	clamp(mode === "build" ? sizes.bottom : sizes.codeBottom, 60, bottomMax),
);
let appEl: HTMLDivElement | undefined = $state();
/** Current size of a grid area, for a splitter that starts dragging. */
function areaSize(sel: string, axis: "x" | "y") {
	const el = appEl?.querySelector(sel) as HTMLElement | null;
	if (!el) return 0;
	const r = el.getBoundingClientRect();
	return axis === "x" ? r.width : r.height;
}

const fileList = $derived([...files.keys()].filter((p) => !isKeep(p)).sort());
const imageFiles = $derived(fileList.filter(isImage));
const fontFiles = $derived(fileList.filter((f) => /\.(ttf|otf)$/i.test(f)));
const sets = $derived(check?.project.sets ?? []);
const currentSet = $derived(sets.find((s) => s.name === setName));
const currentCard = $derived(currentSet?.cards[cardIndex]);
// Keys of each list param (for `list.Key` suggestions): the current card's
// first, then the other cards', then the default's.
const listKeys = $derived.by(() => {
	const out: Record<string, string[]> = {};
	for (const p of currentSet?.params ?? []) {
		if (p.type !== "list") continue;
		const values = [
			currentCard?.values[p.name],
			...(currentSet?.cards ?? []).map((c) => c.values[p.name]),
			p.default,
		];
		out[p.name] = listKeysOf(p.item, values);
	}
	return out;
});
const diagnostics: Diagnostic[] = $derived(
	lastRender?.diagnostics ?? check?.diagnostics ?? [],
);
const fileDiagnostics = $derived(
	diagnostics.filter((d) => d.file === selected),
);
const selectedText = $derived(
	selected && isText(selected)
		? textOf(files.get(selected) ?? new Uint8Array())
		: "",
);
const imageUrl = $derived.by(() => {
	if (!selected || !isImage(selected)) return "";
	const data = files.get(selected);
	return data ? URL.createObjectURL(new Blob([data as BlobPart])) : "";
});

// The design the builder edits: the current set's, else the first one.
const designPath = $derived(
	currentSet?.design ??
		fileList.find((p) => p.endsWith(".design.json")) ??
		null,
);
const designText = $derived(
	designPath && files.has(designPath) ? textOf(files.get(designPath)!) : "",
);
const parsed = $derived.by((): { doc: Obj | null; error: string } => {
	if (!designPath) return { doc: null, error: "" };
	try {
		const d = JSON.parse(designText);
		return isObj(d)
			? { doc: d, error: "" }
			: { doc: null, error: "the design file is not a JSON object" };
	} catch (e) {
		return { doc: null, error: (e as Error).message };
	}
});
const doc = $derived(parsed.doc);
const canvasSize = $derived.by(() => {
	if (image) return { w: image.width, h: image.height };
	const w =
		literalNumber(getPath(doc ?? undefined, ["canvas", "width"])) ?? 1000;
	const h =
		literalNumber(getPath(doc ?? undefined, ["canvas", "height"])) ?? 1400;
	return { w, h };
});
const layerProblems = $derived.by(() => {
	const m = new Map<string, "error" | "warning">();
	if (!doc || !Array.isArray(doc.layers)) return m;
	for (const d of diagnostics) {
		if (d.file !== designPath || d.severity === "hint") continue;
		const id = layerAtPointer(doc, d.path);
		if (!id) continue;
		// A group shows the worst problem of the layers inside it.
		for (const x of [id, ...ancestorsOf(doc, id)])
			if (m.get(x) !== "error") m.set(x, d.severity);
	}
	return m;
});

$effect(() => {
	if (!doc || !selectedLayers.length) return;
	const keep = selectedLayers.filter((id) => findLayer(doc, id));
	if (keep.length !== selectedLayers.length) selectedLayers = keep;
});

onMount(async () => {
	try {
		await engine.init();
	} catch (e) {
		fatal = `Could not load yoshida.wasm: ${(e as Error).message}`;
		return;
	}
	examples = await listExamples();
	try {
		const res = await fetch("api/capabilities");
		if (res.ok && (res.headers.get("content-type") ?? "").includes("json"))
			server = await res.json();
	} catch {
		server = null;
	}
	myProjects = await listProjects();
	const last = lastProject();
	if (last && (await openSaved(last))) return;
	const first = examples.find((e) => e.name === "feature-tour") ?? examples[0];
	if (first) await openExample(first.name);
	else status = "Open a project folder to start.";
});

/**
 * Shows a project. `id`: where it is saved in this browser; a new id saves
 * it right away, null (an example) saves it on the first change.
 */
async function openProject(
	name: string,
	f: Files,
	handle: FileSystemDirectoryHandle | null = null,
	id: string | null = null,
	saved = false,
) {
	projectName = name;
	projectId = id;
	savedFiles = saved ? f : null;
	saveState = saved ? "saved" : id ? "unsaved" : "idle";
	if (id) setLastProject(id);
	files = f;
	dirty = new Set();
	dirHandle = handle;
	lastRender = null;
	check = null;
	setName = "";
	cardIndex = 0;
	selectedLayers = [];
	locked = new Set();
	image = null;
	layout = [];
	undoStack = [];
	redoStack = [];
	uploadFolder = "";
	filesSelected = null;
	filesHighlight = null;
	browsing = false;
	await engine.setFiles(f);
	selected =
		fileList.find((p) => p.endsWith(".design.json")) ?? fileList[0] ?? null;
	await refresh();
}

async function openExample(name: string) {
	const ex = examples.find((e) => e.name === name);
	if (!ex) return;
	status = `Loading ${ex.title}…`;
	await openProject(ex.name, await loadExample(ex));
}

async function openSaved(id: string): Promise<boolean> {
	try {
		const p = await loadProject(id);
		if (!p) return false;
		await openProject(p.meta.name, p.files, null, id, true);
		return true;
	} catch (e) {
		status = `Could not open the saved project: ${(e as Error).message}`;
		return false;
	}
}

/** Lets the user pick files; resolves to [] when cancelled. */
function pickFiles(
	accept: string,
	opts: { multiple?: boolean; directory?: boolean } = {},
): Promise<File[]> {
	return new Promise((resolve) => {
		const input = document.createElement("input");
		input.type = "file";
		input.accept = accept;
		input.multiple = !!opts.multiple;
		if (opts.directory) input.webkitdirectory = true;
		input.onchange = () => resolve(Array.from(input.files ?? []));
		input.oncancel = () => resolve([]);
		input.click();
	});
}

async function openFolder() {
	if (canOpenWritable()) {
		try {
			const { name, files: f, handle } = await openWritable();
			await openProject(name, f, handle, newProjectId());
		} catch (e) {
			if ((e as Error).name !== "AbortError")
				status = `Could not open the folder: ${(e as Error).message}`;
		}
		return;
	}
	const list = await pickFiles("", { directory: true });
	if (!list.length) return;
	const { name, files: f } = await filesFromInput(list);
	await openProject(name, f, null, newProjectId());
}

/** Opens a .yoshida project file; plain .zip projects from older exports still work. */
async function openProjectFile() {
	const [file] = await pickFiles(
		`${PROJECT_EXT},.zip,${PROJECT_MIME},application/zip`,
	);
	if (file) await openProjectFileFrom(file);
}

async function openProjectFileFrom(file: File) {
	try {
		const { name, files: f } = filesFromZip(
			new Uint8Array(await file.arrayBuffer()),
		);
		if (!f.size) throw new Error("the project file is empty");
		await openProject(
			name ?? file.name.replace(projectFileRe, ""),
			f,
			null,
			newProjectId(),
		);
	} catch (e) {
		status = `Could not open ${file.name}: ${(e as Error).message}`;
	}
}

/** The whole project, images and fonts included, as one .yoshida file. */
function exportProject() {
	const fileName = `${slug(projectName)}${PROJECT_EXT}`;
	download(fileName, projectZip(projectName, files), PROJECT_MIME);
	status = `Exported ${files.size} file(s) as ${fileName}.`;
}

// ---------------------------------------------------------------- saving in the browser

/** The files object last written to this browser's storage. */
let savedFiles: Files | null = null;
let saveState: "idle" | "unsaved" | "saving" | "saved" | "error" =
	$state("idle");
let saveTimer: ReturnType<typeof setTimeout> | undefined;

// Every change is saved in this browser shortly after it happens. An
// example becomes a saved project on its first change.
$effect(() => {
	const f = files;
	if (!f.size || f === savedFiles || (!projectId && !dirty.size)) return;
	saveState = "unsaved";
	clearTimeout(saveTimer);
	saveTimer = setTimeout(saveInBrowser, 600);
});

async function saveInBrowser() {
	clearTimeout(saveTimer);
	if (!files.size || files === savedFiles) return;
	projectId ??= newProjectId();
	const f = files;
	const id = projectId;
	saveState = "saving";
	try {
		await saveProject(id, projectName, f);
		if (id !== projectId) return;
		savedFiles = f;
		setLastProject(id);
		saveState = files === f ? "saved" : "unsaved";
		myProjects = await listProjects();
		persistStorage();
	} catch (e) {
		saveState = "error";
		status = `Could not save in this browser: ${(e as Error).message}. Export the project as a .yoshida file to keep it.`;
	}
}

function onHide() {
	if (document.visibilityState === "hidden" && saveState === "unsaved")
		saveInBrowser();
}

async function renameProject() {
	const name = (
		await askText({
			title: "Rename project",
			value: projectName,
			confirm: "Rename",
			validate: needName,
		})
	)?.trim();
	if (!name || name === projectName) return;
	projectName = name;
	savedFiles = null;
	projectId ??= newProjectId();
	await saveInBrowser();
}

async function forgetProject(meta: ProjectMeta) {
	const ok = await confirmAction({
		title: `Delete '${meta.name}' from this browser?`,
		message:
			"Its files (images included) are removed from this browser. Export it as a .yoshida file first if you want to keep it.",
		confirm: "Delete",
		danger: true,
	});
	if (!ok) return;
	await deleteProject(meta.id);
	myProjects = await listProjects();
	if (meta.id === projectId) {
		projectId = null;
		savedFiles = null;
		dirty = new Set();
		saveState = "idle";
		status = `Deleted '${meta.name}' from this browser; it stays open until you open another project.`;
	}
}

function projectMenu(e: MouseEvent) {
	const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
	const current = myProjects.find((p) => p.id === projectId);
	const items: MenuItem[] = [
		{ label: "New project…", icon: "＋", action: newProject },
		{ label: "Open folder…", icon: "📁", action: openFolder },
		{
			label: "Open project file…",
			icon: "⤓",
			detail: ".yoshida",
			action: openProjectFile,
		},
		{
			label: "Export project file",
			icon: "⤒",
			detail: "with images and fonts",
			disabled: !files.size,
			action: exportProject,
		},
		{
			label: "Rename…",
			icon: "✎",
			disabled: !files.size,
			action: renameProject,
		},
	];
	if (current)
		items.push({
			label: "Delete from this browser…",
			icon: "🗑",
			danger: true,
			action: () => forgetProject(current),
		});
	items.push({ separator: true }, { heading: "Saved in this browser" });
	if (!myProjects.length)
		items.push({
			label: "Nothing yet: changes are saved here automatically",
			disabled: true,
			action: () => {},
		});
	for (const p of myProjects)
		items.push({
			label: p.name,
			icon: p.id === projectId ? "✓" : "",
			detail: `${formatAge(p.updated)} · ${formatSize(p.size)}`,
			action: () => (p.id === projectId ? undefined : openSaved(p.id)),
		});
	items.push({ separator: true }, { heading: "Examples" });
	for (const ex of examples)
		items.push({
			label: ex.title,
			icon: !projectId && ex.name === projectName ? "✓" : "",
			detail: "opens a fresh copy",
			action: () => openExample(ex.name),
		});
	openMenu(r.left, r.bottom + 4, items);
}

/**
 * Adds an image from the user's computer: to the folder chosen in the
 * Files tab, else to assets/images/.
 */
async function uploadImage(): Promise<string | null> {
	const [file] = await pickFiles(
		"image/png,image/jpeg,image/webp,image/gif,image/bmp,.png,.jpg,.jpeg,.webp,.gif,.bmp",
	);
	if (!file) return null;
	const added = await importFiles([file], uploadFolder || null);
	return added[0] ?? null;
}

const needName = (v: string) =>
	v.trim() && slug(v.trim())
		? ""
		: "Enter a name with at least one letter or digit.";

async function newProject() {
	const name = (
		await askText({
			title: "New project",
			message: "Starts an empty project with one design and one card file.",
			value: "My cards",
			confirm: "Create",
			validate: needName,
		})
	)?.trim();
	if (!name) return;
	const stem = slug(name);
	const design = `designs/${stem}.design.json`;
	const f: Files = new Map([
		[design, bytesOf(blankDesign(name))],
		[`cards/${stem}.cards.json`, bytesOf(blankCards(design, name))],
	]);
	openProject(stem, f, null, newProjectId()).then(() => {
		dirty = new Set(f.keys());
		mode = "build";
	});
}

/** Adds a blank design with its own card file to the open project. */
async function newDesign() {
	const name = (
		await askText({
			title: "New design",
			message: "Adds a blank design and its own card file to this project.",
			value: "New design",
			confirm: "Add design",
			validate: needName,
		})
	)?.trim();
	if (!name) return;
	let stem = slug(name);
	for (let n = 2; files.has(`designs/${stem}.design.json`); n++)
		stem = `${slug(name)}-${n}`;
	const design = `designs/${stem}.design.json`;
	await updateFile(design, blankDesign(name));
	await updateFile(`cards/${stem}.cards.json`, blankCards(design, name));
	await refresh();
	const s = sets.find((x) => x.design === design);
	if (s) {
		setName = s.name;
		cardIndex = 0;
		await renderPreview();
	}
	mode = "build";
	leftTab = "layers";
}

/**
 * Copies dropped or picked files into the project: into `folder` when
 * given, else by kind (images to assets/images, fonts to assets/fonts...).
 * A name that is taken gets a number instead of replacing the file.
 */
async function importFiles(
	list: FileList | File[],
	folder: string | null = null,
): Promise<string[]> {
	const changes: Snapshot = [];
	const taken = new Map(files);
	for (const f of Array.from(list)) {
		const data = new Uint8Array(await f.arrayBuffer());
		const want =
			folder !== null ? join(folder, baseOf(f.name)) : importPath(f.name);
		const same = taken.get(want);
		if (
			same &&
			same.length === data.length &&
			same.every((b, i) => b === data[i])
		)
			continue;
		const path = freePath(taken, want);
		taken.set(path, data);
		changes.push({ path, data });
	}
	if (!changes.length) {
		status = "Already in the project.";
		return [];
	}
	recordMany(changes.map((c) => snap(c.path)));
	await writeFiles(changes);
	const added = changes.map((c) => c.path);
	filesHighlight = added[0];
	status = `Added ${added.join(", ")}${leftTab !== "files" && mode === "build" ? " (see the Files tab)" : ""}`;
	return added;
}

// ---------------------------------------------------------------- file browser

/** Folder chosen in the Files tab; uploads go there ('' = by kind). */
let uploadFolder = $state("");
let filesSelected: string | null = $state(null);
let filesHighlight: string | null = $state(null);
const fileUses = $derived(useCounts(files));

async function uploadTo(folder: string) {
	const list = await pickFiles("", { multiple: true });
	if (list.length) await importFiles(list, folder);
}

/**
 * Renames or moves files and folders and rewrites every reference to
 * them in designs and card data, as one undo step. Path templates that
 * may point at a moved file are listed first.
 */
async function movePaths(moves: [string, string][]) {
	const renames = new Map<string, string>();
	for (const [from, to] of moves) {
		for (const p of pathsUnder(files, from))
			renames.set(p, to + p.slice(from.length));
	}
	if (!renames.size) return;
	for (const [from, to] of renames)
		if (files.has(to) && !renames.has(to)) {
			status = `Not moved: '${to}' already exists.`;
			return;
		}
	const refs = findRefs(files, [...renames.keys()]);
	const templates = [
		...new Set(
			[...refs.values()].flatMap((r) =>
				r.templates.map((t) => `"${t.template}" in ${t.file}`),
			),
		),
	];
	if (templates.length) {
		const ok = await confirmAction({
			title:
				renames.size === 1
					? `Move '${[...renames.keys()][0]}'?`
					: `Move ${renames.size} files?`,
			message: `These path templates may use ${renames.size === 1 ? "this file" : "these files"} and cannot be updated automatically:\n${templates.slice(0, 6).join("\n")}${templates.length > 6 ? `\n… and ${templates.length - 6} more` : ""}\nCards that build this path will show a missing file until you fix the template or the name.`,
			confirm: "Move anyway",
		});
		if (!ok) return;
	}
	const rewritten = rewriteRefs(files, renames);
	const changes: Snapshot = [];
	for (const [path, data] of rewritten)
		if (!renames.has(path)) changes.push({ path, data });
	for (const [from, to] of renames) {
		changes.push({ path: from, data: null });
		changes.push({
			path: to,
			data: rewritten.get(from) ?? files.get(from)!,
		});
	}
	recordMany(changes.map((c) => snap(c.path)));
	await writeFiles(changes);
	const n = [...refs.values()].reduce((a, r) => a + r.files.size, 0);
	if (selected && renames.has(selected)) selected = renames.get(selected)!;
	if (filesSelected && renames.has(filesSelected))
		filesSelected = renames.get(filesSelected)!;
	filesHighlight = [...renames.values()][0];
	status = `Moved ${renames.size} file${renames.size === 1 ? "" : "s"}${n ? `; updated references in ${new Set([...refs.values()].flatMap((r) => [...r.files.keys()])).size} file(s)` : ""}.`;
}

async function deletePath(path: string) {
	const gone = pathsUnder(files, path);
	if (!gone.length) return;
	const refs = findRefs(files, gone);
	const users = [
		...new Set([...refs.values()].flatMap((r) => [...r.files.keys()])),
	].filter((f) => !gone.includes(f));
	const ok = await confirmAction({
		title:
			gone.length === 1 && files.has(path)
				? `Delete '${path}'?`
				: `Delete folder '${path}' (${gone.filter((p) => !isKeep(p)).length} files)?`,
		message: users.length
			? `Used by ${users.join(", ")}. Those will show a missing file. Undo brings it back.`
			: "Undo brings it back.",
		confirm: "Delete",
		danger: true,
	});
	if (!ok) return;
	const changes: Snapshot = gone.map((p) => ({ path: p, data: null }));
	// Keep the folder itself when its last file goes.
	const dir = dirOf(path);
	if (
		dir &&
		![...files.keys()].some((p) => p.startsWith(`${dir}/`) && !gone.includes(p))
	)
		changes.push({ path: join(dir, keepName), data: new Uint8Array() });
	recordMany(changes.map((c) => snap(c.path)));
	await writeFiles(changes);
	if (selected && gone.includes(selected)) selected = null;
	if (filesSelected && gone.includes(filesSelected)) filesSelected = null;
	status = `Deleted ${gone.length === 1 ? path : `${gone.length} files`}.`;
}

async function newFolder(parent: string, name: string) {
	const path = join(join(parent, name), keepName);
	recordMany([snap(path)]);
	await writeFiles([{ path, data: new Uint8Array() }]);
}

async function duplicateFile(path: string) {
	const data = files.get(path);
	if (!data) return;
	const to = freePath(files, path);
	recordMany([snap(to)]);
	await writeFiles([{ path: to, data }]);
	filesSelected = to;
	filesHighlight = to;
}

function copyPath(path: string) {
	navigator.clipboard?.writeText(path).catch(() => {});
	status = `Copied '${path}'. Paste it into an image or font field.`;
}

/** Opening a file from the browser: text files go to the Advanced view in builder mode only on request. */
function openFromBrowser(path: string) {
	filesSelected = path;
	if (mode === "code") selected = path;
}

const filesPreviewUrl = $derived.by(() => {
	const p = filesSelected;
	if (!p || !isImage(p)) return "";
	const d = files.get(p);
	return d ? URL.createObjectURL(new Blob([d as BlobPart])) : "";
});
$effect(() => {
	const u = filesPreviewUrl;
	return () => u && URL.revokeObjectURL(u);
});

// ---------------------------------------------------------------- card browser

let browsing = $state(false);
const thumbCache = new Map<string, Promise<string | null>>();
let thumbFiles: Files | null = null;

/** A small render of card `i` of the current set, cached until a file changes. */
function cardThumb(i: number): Promise<string | null> {
	if (thumbFiles !== files) {
		for (const p of thumbCache.values())
			p.then((u) => u && URL.revokeObjectURL(u));
		thumbCache.clear();
		thumbFiles = files;
	}
	const key = `${setName}\u0000${i}`;
	let p = thumbCache.get(key);
	if (!p) {
		p = engine
			.render({
				set: setName,
				card: i,
				date: today,
				preview: true,
				format: "png",
			})
			.then((r) =>
				r.bin.length
					? URL.createObjectURL(
							new Blob([r.bin as BlobPart], {
								type: "image/png",
							}),
						)
					: null,
			)
			.catch(() => null);
		thumbCache.set(key, p);
	}
	return p;
}

async function addFiles() {
	const list = await pickFiles("", { multiple: true });
	if (list.length) await importFiles(list, uploadFolder || null);
}

let dropping = $state(false);

function onDragOver(e: DragEvent) {
	if (!e.dataTransfer?.types.includes("Files")) return;
	e.preventDefault();
	dropping = true;
}

function onDrop(e: DragEvent) {
	// A drop on a folder in the Files tab was already handled there.
	if (e.defaultPrevented) {
		dropping = false;
		return;
	}
	if (!e.dataTransfer?.files.length) return;
	e.preventDefault();
	dropping = false;
	const list = Array.from(e.dataTransfer.files);
	// A dropped project file (.yoshida, or an older plain .zip) opens as a project; anything else is added to this one.
	if (list.length === 1 && projectFileRe.test(list[0].name))
		openProjectFileFrom(list[0]);
	else importFiles(list);
}

/** Writes the whole project to a folder the user picks, then saves there. */
async function saveToFolder() {
	try {
		const handle = await pickDirectory();
		for (const [p, d] of files) await writeFile(handle, p, d);
		dirHandle = handle;
		dirty = new Set();
		status = `Saved ${files.size} file(s) to ${handle.name}.`;
	} catch (e) {
		if ((e as Error).name !== "AbortError")
			status = `Could not save: ${(e as Error).message}`;
	}
}

// ---------------------------------------------------------------- refresh

let running = false;
let again = false;
let timer: ReturnType<typeof setTimeout> | undefined;

function scheduleRefresh() {
	clearTimeout(timer);
	timer = setTimeout(refresh, 250);
}

async function refresh() {
	clearTimeout(timer);
	if (running) {
		again = true;
		return;
	}
	running = true;
	try {
		check = await engine.check();
		const s = check.project.sets;
		if (!s.find((x) => x.name === setName)) {
			setName = s[0]?.name ?? "";
			cardIndex = 0;
		}
		const cs = s.find((x) => x.name === setName);
		if (cs && cardIndex >= cs.cards.length)
			cardIndex = Math.max(0, cs.cards.length - 1);
		await renderPreview();
	} catch (e) {
		status = `Error: ${(e as Error).message}`;
	} finally {
		running = false;
		if (again) {
			again = false;
			refresh();
		}
	}
}

async function renderPreview() {
	if (!currentSet?.cards.length) {
		lastRender = null;
		stale = !!image;
		status = sets.length ? "This set has no cards." : "No designs found.";
		return;
	}
	if (!currentSet.ok) {
		// Keep the last good picture (dimmed) so the canvas does not jump away
		// while a field is being typed.
		lastRender = null;
		stale = !!image;
		status = "Fix the errors to see the preview.";
		return;
	}
	const t0 = performance.now();
	const r = await engine.render({
		set: setName,
		card: cardIndex,
		date: today,
		preview: true,
		format: "rgba",
		layout: true,
	});
	renderMs = Math.round(performance.now() - t0);
	lastRender = r;
	if (r.width) {
		image = new ImageData(
			new Uint8ClampedArray(
				r.bin.buffer as ArrayBuffer,
				r.bin.byteOffset,
				r.bin.byteLength,
			),
			r.width,
			r.height,
		);
		layout = r.layout ?? [];
		stale = false;
		status = `${r.width} × ${r.height} px, rendered in ${renderMs} ms`;
	} else {
		stale = !!image;
		status = "Nothing could be drawn; see the problems below.";
	}
}

// ---------------------------------------------------------------- files and undo

async function updateFile(path: string, text: string, immediate = false) {
	const data = bytesOf(text);
	files = new Map(files).set(path, data);
	dirty = new Set(dirty).add(path);
	await engine.put(path, data);
	if (immediate) refresh();
	else scheduleRefresh();
}

/** The files one step changed, as they were before it (null: did not exist). */
type Snapshot = { path: string; data: Uint8Array | null }[];
let undoStack = $state.raw<Snapshot[]>([]);
let redoStack = $state.raw<Snapshot[]>([]);
let lastKey = "";
let lastTime = 0;

/**
 * Remembers a file's text before a change. Changes with the same key in
 * quick succession (typing, scrubbing, nudging) become one undo step.
 */
function record(path: string, before: string, key = "") {
	const now = performance.now();
	if (key && key === lastKey && now - lastTime < 1500) {
		lastTime = now;
		return;
	}
	lastKey = key;
	lastTime = now;
	undoStack = [...undoStack.slice(-199), [{ path, data: bytesOf(before) }]];
	redoStack = [];
}

/** One undo step for a change that touches several files. */
function recordMany(before: Snapshot) {
	lastKey = "";
	undoStack = [...undoStack.slice(-199), before];
	redoStack = [];
}

function currentText(path: string) {
	const d = files.get(path);
	return d ? textOf(d) : "";
}

/** The current state of a file, for an undo step. */
function snap(path: string) {
	return { path, data: files.get(path) ?? null };
}

function restore(s: Snapshot) {
	writeFiles(s);
}

/**
 * Writes several files at once (null deletes) and re-checks the project.
 * A folder's .keep marker goes away once the folder has other files.
 */
async function writeFiles(changes: Snapshot) {
	const next = new Map(files);
	const d = new Set(dirty);
	for (const c of changes) {
		if (c.data) next.set(c.path, c.data);
		else next.delete(c.path);
		d.add(c.path);
	}
	for (const c of changes) {
		const keep = join(dirOf(c.path), keepName);
		if (c.data && !isKeep(c.path) && next.has(keep)) {
			next.delete(keep);
			d.add(keep);
		}
	}
	files = next;
	dirty = d;
	for (const c of changes) {
		if (c.data) await engine.put(c.path, c.data);
		else await engine.remove(c.path);
	}
	await refresh();
}

function undo() {
	const s = undoStack.at(-1);
	if (!s) return;
	undoStack = undoStack.slice(0, -1);
	redoStack = [...redoStack, s.map((f) => snap(f.path))];
	lastKey = "";
	restore(s);
}

function redo() {
	const s = redoStack.at(-1);
	if (!s) return;
	redoStack = redoStack.slice(0, -1);
	undoStack = [...undoStack, s.map((f) => snap(f.path))];
	lastKey = "";
	restore(s);
}

function editText(path: string, text: string) {
	record(path, currentText(path), `text:${path}`);
	updateFile(path, text);
}

function setCard(param: string, value: unknown) {
	const cf = currentSet?.cards_file;
	if (!cf) return;
	const text = currentText(cf);
	try {
		const next = setCardValue(cf, text, cardIndex, param, value);
		record(cf, text, `card:${cardIndex}:${param}`);
		updateFile(cf, next, true);
	} catch (e) {
		status = `Could not update ${cf}: ${(e as Error).message}`;
	}
}

function editCards(op: CardListOp) {
	const cf = currentSet?.cards_file;
	if (!cf || !currentSet) return;
	const text = currentText(cf);
	try {
		const r = editCardList(
			cf,
			text,
			op,
			currentSet.cards.map((c) => c.id),
		);
		record(cf, text);
		cardIndex = r.index;
		updateFile(cf, r.text, true);
	} catch (e) {
		status = `Could not update ${cf}: ${(e as Error).message}`;
	}
}

let cardIdError = $state("");

function renameCard(id: string) {
	if (!currentSet || !currentCard || id === currentCard.id) {
		cardIdError = "";
		return cardIdError;
	}
	if (!cardIdRe.test(id)) {
		cardIdError = "Use letters, digits, ., _ and - only.";
		return cardIdError;
	}
	if (currentSet.cards.some((c) => c.id === id)) {
		cardIdError = `There is already a card '${id}'.`;
		return cardIdError;
	}
	cardIdError = "";
	editCards({ op: "rename", index: cardIndex, id });
}

/** Renames a param in the design and in every card file of its sets. */
function renameParamEverywhere(from: string, to: string) {
	if (!designPath || !doc) return;
	editDesignAndCards(
		(d) => renameParam(d, from, to),
		(path, text) =>
			renameParamInCards(
				path,
				text,
				from,
				to,
				{ parse: parseCsv, write: writeCsv },
				formatJson,
			),
	);
}

/** Renames an enum option in the design (options, default) and in every card that uses it. */
function renameOptionEverywhere(param: string, from: string, to: string) {
	editDesignAndCards(
		(d) => renameEnumOption(d, param, from, to),
		(path, text) =>
			renameValueInCards(
				path,
				text,
				param,
				from,
				to,
				{ parse: parseCsv, write: writeCsv },
				formatJson,
			),
	);
}

/** One undo step that changes the design and the card files of its sets. */
function editDesignAndCards(
	design: (d: Obj) => void,
	cards: (path: string, text: string) => string,
) {
	if (!designPath || !doc) return;
	const next = clone(doc);
	design(next);
	const changes: Snapshot = [
		{ path: designPath, data: bytesOf(formatJson(next)) },
	];
	for (const s of sets) {
		if (s.design !== designPath || !s.cards_file || !files.has(s.cards_file))
			continue;
		const text = currentText(s.cards_file);
		try {
			const out = cards(s.cards_file, text);
			if (out !== text)
				changes.push({ path: s.cards_file, data: bytesOf(out) });
		} catch {
			// A card file with a syntax error is left alone; the core reports it.
		}
	}
	recordMany(changes.map((c) => snap(c.path)));
	writeFiles(changes);
}

/** Cards of every set drawn with the design being edited. */
const designCards = $derived(
	sets.filter((s) => s.design === designPath).flatMap((s) => s.cards),
);

// ---------------------------------------------------------------- design edits

/** Applies `fn` to a copy of the design and writes it back formatted. */
function editDoc(fn: (d: Obj) => void, key = "") {
	if (!designPath || !doc) return;
	const next = clone(doc);
	fn(next);
	const text = formatJson(next);
	if (text === designText) return;
	record(designPath, designText, key ? `design:${key}` : "");
	updateFile(designPath, text, true);
}

function editLayer(fn: (own: Obj) => void, key = "") {
	const id = selectedLayer;
	if (!id) return;
	editDoc(
		(d) => {
			const l = findLayer(d, id);
			if (l) fn(l);
		},
		key ? `${id}.${key}` : "",
	);
}

function renameSelected(from: string, to: string): string {
	if (!doc) return "";
	if (!identRe.test(to))
		return "Use letters, digits and _, not starting with a digit.";
	if (findLayer(doc, to)) return `There is already a layer '${to}'.`;
	editDoc((d) => renameLayer(d, from, to));
	if (locked.has(from))
		locked = new Set([...locked].map((x) => (x === from ? to : x)));
	selectedLayers = [to];
	return "";
}

function addLayer(type: LayerType) {
	if (!doc) return;
	const imageParams = paramsOf(doc)
		.filter(([, p]) => p.type === "image")
		.map(([n]) => n);
	const layer = newLayer(doc, type, {
		canvas: canvasSize,
		imageFiles,
		imageParams,
	});
	editDoc((d) => insertLayer(d, layer, selectedLayer));
	selectedLayers = [String(layer.id)];
	leftTab = "layers";
}

/** Adds an empty group or a divider above the selection (or on top). */
async function addContainer(type: "group" | "divider") {
	if (!doc) return;
	let label = "";
	if (type === "divider") {
		const v = await askText({
			title: "New divider",
			message: "A titled line in the layer list. It is not drawn on the card.",
			placeholder: "Monster stats",
			confirm: "Add divider",
			validate: () => "",
		}).catch(() => null);
		if (v === null) return;
		label = v.trim();
	}
	const layer = newContainer(doc, type, label);
	editDoc((d) => insertLayer(d, layer, selectedLayer));
	selectedLayers = [String(layer.id)];
	leftTab = "layers";
}

async function removeLayers(ids: string[]) {
	if (!doc || !ids.length) return;
	const gone = new Set(ids.flatMap((id) => [id, ...descendantsOf(id)]));
	const refs = [
		...new Set([...gone].flatMap((id) => referencesTo(doc!, id))),
	].filter((r) => !gone.has(r));
	if (refs.length) {
		const ok = await confirmAction({
			title:
				ids.length > 1 ? `Delete ${ids.length} layers?` : `Delete '${ids[0]}'?`,
			message: `${refs.map((r) => `'${r}'`).join(", ")} ${refs.length > 1 ? "refer" : "refers"} to ${ids.length > 1 ? "these layers" : "it"} and will show errors.`,
			confirm: "Delete",
			danger: true,
		});
		if (!ok) return;
	}
	editDoc((d) => {
		for (const id of ids)
			if (!ancestorsOf(d, id).some((a) => ids.includes(a))) deleteLayer(d, id);
	});
	selectedLayers = selectedLayers.filter((x) => !gone.has(x));
}

function descendantsOf(id: string): string[] {
	const l = doc ? findLayer(doc, id) : undefined;
	return l && isGroup(l) ? layersOf(l).map((x) => String(x.id)) : [];
}

// ---------------------------------------------------------------- groups

function groupSelected() {
	if (!doc || !selectedLayers.length) return;
	let g: string | null = null;
	editDoc((d) => (g = groupLayers(d, selectedLayers)));
	if (g) selectedLayers = [g];
}

function ungroupSelected() {
	if (!doc) return;
	const groups = selectedLayers.filter((id) => isGroup(findLayer(doc!, id)));
	if (!groups.length) return;
	let kids: string[] = [];
	editDoc((d) => (kids = groups.flatMap((g) => ungroupLayer(d, g))));
	selectedLayers = kids;
}

/** Drag and drop in the layer list; `ids` keep their stacking order. */
function moveInTree(
	ids: string[],
	target: string | null,
	where: "above" | "below" | "into",
) {
	const order = inStackOrder(ids).filter(
		(id) => !ancestorsOf(doc!, id).some((a) => ids.includes(a)),
	);
	editDoc((d) => {
		if (where === "into" && target)
			for (const id of order) moveIntoGroup(d, id, target);
		else if (where === "below" && target)
			for (const id of order) reorderLayer(d, id, target, true);
		else for (const id of [...order].reverse()) reorderLayer(d, id, target);
	});
}

/**
 * The layer a canvas click on `id` selects: the outermost group around
 * it, unless that group (or a layer next to it in a group) is already
 * being edited. `deep` (double click) picks the layer itself.
 */
function pickOnCanvas(id: string, deep: boolean): string | null {
	if (!doc) return id;
	const chain = [...ancestorsOf(doc, id).reverse(), id];
	if (locked.has(chain[0])) return null;
	if (deep) return id;
	for (const s of selectedLayers) {
		if (chain.includes(s)) return s;
		const p = parentOf(doc, s);
		const k = p ? chain.indexOf(p) : -1;
		if (k >= 0) return chain[k + 1];
	}
	return chain[0];
}

function renameAsk(id: string) {
	askText({
		title: `Rename '${id}'`,
		message: "References like @old.bounds are updated too.",
		value: id,
		confirm: "Rename",
		validate: (v) =>
			v.trim() === id
				? ""
				: identRe.test(v.trim())
					? findLayer(doc!, v.trim())
						? `There is already a layer '${v.trim()}'.`
						: ""
					: "Use letters, digits and _, not starting with a digit.",
	}).then((v) => {
		if (v && v.trim() !== id) renameSelected(id, v.trim());
	});
}

/** Right-click menu for the layer list and the canvas. */
function layerMenu(e: MouseEvent, id: string | null) {
	if (!doc) return;
	const ids = id && !selectedLayers.includes(id) ? [id] : selectedLayers;
	if (id && !selectedLayers.includes(id)) selectedLayers = [id];
	const one = ids.length === 1 ? ids[0] : null;
	const l = one ? findLayer(doc, one) : undefined;
	const anyGroup = ids.some((x) => isGroup(findLayer(doc!, x)));
	const items: MenuItem[] = [];
	// Empty space: adding layers (above the selection, if any), paste, select all.
	if (id === null) {
		items.push({
			heading: selectedLayer ? `Add above '${selectedLayer}'` : "Add",
		});
		for (const t of layerTypes)
			items.push({
				label: typeLabels[t].replace(/^\S+\s/, ""),
				icon: typeLabels[t].split(" ")[0],
				action: () => addLayer(t),
			});
		items.push(
			{
				label: "Group",
				icon: "▤",
				detail: "empty",
				action: () => addContainer("group"),
			},
			{
				label: "Divider…",
				icon: "―",
				detail: "only in this list",
				action: () => addContainer("divider"),
			},
			{ separator: true },
		);
		items.push(
			{
				label: "Paste",
				shortcut: "Ctrl+V",
				disabled: !clipboard.length,
				action: () => pasteFromMemory(),
			},
			{
				label: "Select all",
				shortcut: "Ctrl+A",
				action: () =>
					(selectedLayers = layersOf(doc!)
						.filter((x) => !parentOf(doc!, String(x.id)))
						.map((x) => String(x.id))),
			},
		);
		openMenu(e.clientX, e.clientY, items);
		return;
	}
	if (one)
		items.push({
			label: "Rename…",
			icon: "✎",
			action: () => renameAsk(one),
		});
	if (one && isDivider(l))
		items.push({
			label: "Edit title…",
			action: () => editDividerLabel(one),
		});
	if (one)
		items.push({
			label: "Add above",
			icon: "＋",
			detail: "layer, group or divider",
			action: () => {
				selectedLayers = [one];
				layerMenu(
					{
						clientX: e.clientX + 8,
						clientY: e.clientY + 8,
					} as MouseEvent,
					null,
				);
			},
		});
	items.push(
		{
			label: "Duplicate",
			icon: "⧉",
			shortcut: "Ctrl+D",
			action: () => duplicateMany(ids),
		},
		{
			label: "Copy",
			shortcut: "Ctrl+C",
			action: () => copyToMemory(ids),
		},
		{
			label: "Cut",
			shortcut: "Ctrl+X",
			action: () => {
				copyToMemory(ids);
				removeLayers(ids);
			},
		},
		{
			label: "Paste above",
			shortcut: "Ctrl+V",
			disabled: !clipboard.length,
			action: () => pasteFromMemory(),
		},
		{ separator: true },
		{
			label: "Group",
			icon: "▤",
			shortcut: "Ctrl+G",
			action: groupSelected,
		},
		{
			label: "Ungroup",
			shortcut: "Ctrl+Shift+G",
			disabled: !anyGroup,
			action: ungroupSelected,
		},
	);
	if (one) {
		const at = parentOf(doc, one);
		items.push(
			{
				label: "Bring forward",
				shortcut: "Ctrl+↑",
				action: () => editDoc((d) => stepLayer(d, one, 1)),
			},
			{
				label: "Send backward",
				shortcut: "Ctrl+↓",
				action: () => editDoc((d) => stepLayer(d, one, -1)),
			},
		);
		if (at)
			items.push({
				label: `Move out of '${at}'`,
				action: () => editDoc((d) => reorderLayer(d, one, at)),
			});
	}
	items.push({ separator: true });
	if (l) {
		items.push(
			{
				label: l.visible === false ? "Show" : "Hide",
				icon: l.visible === false ? "◉" : "○",
				action: () => toggleVisible(one!),
			},
			{
				label: locked.has(one!) ? "Unlock" : "Lock",
				icon: "🔒",
				action: () => toggleLock(one!),
			},
		);
	}
	items.push({
		label: ids.length > 1 ? `Delete ${ids.length} layers` : "Delete",
		icon: "🗑",
		shortcut: "Del",
		danger: true,
		action: () => removeLayers(ids),
	});
	openMenu(e.clientX, e.clientY, items);
}

async function editDividerLabel(id: string) {
	const cur = doc ? findLayer(doc, id) : undefined;
	const v = await askText({
		title: "Divider title",
		value: typeof cur?.label === "string" ? cur.label : "",
		placeholder: id,
		confirm: "Save",
		validate: () => "",
	});
	if (v === null) return;
	editDoc((d) => {
		const l = findLayer(d, id);
		if (!l) return;
		if (v.trim()) l.label = v.trim();
		else delete l.label;
	});
}

function copyToMemory(ids: string[]) {
	clipboard = inStackOrder(ids).map((id) => clone(findLayer(doc!, id)!));
	navigator.clipboard
		?.writeText(JSON.stringify({ yoshida_layers: clipboard }, null, 2))
		.catch(() => {});
	status = `Copied ${clipboard.length} layer(s).`;
}

function pasteFromMemory() {
	if (!clipboard.length) return;
	const above = selectedLayers.length
		? inStackOrder(selectedLayers).at(-1)!
		: null;
	let made: string[] = [];
	editDoc((d) => (made = pasteLayers(d, clipboard, above)));
	selectedLayers = made;
}

/** Layers in design order (bottom first), so copies keep their stacking. */
function inStackOrder(ids: string[]) {
	return layersOf(doc ?? {})
		.map((l) => String(l.id))
		.filter((id) => ids.includes(id));
}

function duplicateMany(ids: string[]) {
	if (!doc || !ids.length) return;
	if (ids.length === 1) {
		let copy: string | null = null;
		editDoc((d) => (copy = duplicateLayer(d, ids[0])));
		if (copy) selectedLayers = [copy];
		return;
	}
	const order = inStackOrder(ids);
	const layers = order.map((id) => clone(findLayer(doc!, id)!));
	let made: string[] = [];
	editDoc((d) => (made = pasteLayers(d, layers, order.at(-1)!)));
	selectedLayers = made;
}

// Copy and paste use the system clipboard (JSON, so layers can move
// between tabs and projects) with an in-memory fallback.
let clipboard: Obj[] = [];

function canUseClipboard(e: ClipboardEvent) {
	const t = e.target as HTMLElement | null;
	return (
		mode === "build" &&
		!!doc &&
		!t?.closest("input, textarea, select, [contenteditable], .cm-editor")
	);
}

function onCopy(e: ClipboardEvent, cut = false) {
	if (!canUseClipboard(e) || !selectedLayers.length) return;
	e.preventDefault();
	clipboard = inStackOrder(selectedLayers).map((id) =>
		clone(findLayer(doc!, id)!),
	);
	e.clipboardData?.setData(
		"text/plain",
		JSON.stringify({ yoshida_layers: clipboard }, null, 2),
	);
	status = `${cut ? "Cut" : "Copied"} ${clipboard.length} layer(s).`;
	if (cut) removeLayers([...selectedLayers]);
}

function onPaste(e: ClipboardEvent) {
	if (!canUseClipboard(e)) return;
	let layers = clipboard;
	try {
		const data = JSON.parse(e.clipboardData?.getData("text/plain") ?? "");
		if (Array.isArray(data?.yoshida_layers))
			layers = data.yoshida_layers.filter(isObj);
		else if (isObj(data) && typeof data.type === "string") layers = [data];
	} catch {
		// Not our JSON: use the in-memory copy.
	}
	if (!layers.length) return;
	e.preventDefault();
	const above = selectedLayers.length
		? inStackOrder(selectedLayers).at(-1)!
		: null;
	let made: string[] = [];
	editDoc((d) => (made = pasteLayers(d, layers, above)));
	selectedLayers = made;
	leftTab = "layers";
}

function align(m: AlignMode) {
	editDoc((d) => alignLayers(d, selectedLayers, m, layout, canvasSize));
}

function distribute(axis: "x" | "y") {
	editDoc((d) => distributeLayers(d, selectedLayers, axis, layout, canvasSize));
}

function toggleVisible(id: string) {
	editDoc((d) => {
		const l = findLayer(d, id);
		if (!l) return;
		if (l.visible === false) delete l.visible;
		else l.visible = false;
	});
}

function toggleLock(id: string) {
	const next = new Set(locked);
	if (!next.delete(id)) next.add(id);
	locked = next;
}

function handlesFor(id: string): HandleMode {
	const l = doc ? effectiveLayer(doc, id) : undefined;
	if (!l) return "none";
	switch (l.type) {
		case "divider":
			return "none";
		case "group":
			return "group";
		case "text":
			return "text";
		case "polygon":
			return "polygon";
		case "image": {
			const box = isObj(l.box) ? l.box : {};
			return box.w === "auto" || box.h === "auto" ? "aspect" : "box";
		}
		default:
			return "box";
	}
}

// Canvas gestures are applied to the design as it was when the gesture
// started, so every move recomputes from the same base.
let gestureBase: string | null = null;

function onGesture(g: Gesture, phase: "start" | "move" | "end") {
	if (!designPath) return;
	if (phase === "start") {
		gestureBase = designText;
		return;
	}
	if (gestureBase === null) return;
	let d: Obj;
	try {
		d = JSON.parse(gestureBase);
	} catch {
		return;
	}
	if (g.mode === "move") moveLayers(d, g.ids, g.dx, g.dy, canvasSize);
	else if (g.mode === "resize")
		resizeLayer(d, g.id, g.from, g.to, canvasSize, g.angle);
	else if (g.mode === "rotate") rotateLayer(d, g.id, g.angle);
	else movePoint(d, g.id, g.index, g.dx, g.dy, canvasSize);
	const text = formatJson(d);
	if (phase === "end") {
		if (text !== gestureBase) record(designPath, gestureBase);
		lastKey = "";
		gestureBase = null;
	}
	if (text !== designText) updateFile(designPath, text, true);
}

function nudge(ids: string[], dx: number, dy: number) {
	editDoc(
		(d) => moveLayers(d, ids, dx, dy, canvasSize),
		`nudge:${ids.join(",")}`,
	);
}

function onKey(e: KeyboardEvent) {
	const t = e.target as HTMLElement | null;
	const typing = !!t?.closest("input, textarea, select, [contenteditable]");
	const mod = e.ctrlKey || e.metaKey;
	const k = e.key.toLowerCase();
	if (mod && !typing && (k === "z" || k === "y")) {
		e.preventDefault();
		if (k === "y" || e.shiftKey) redo();
		else undo();
		return;
	}
	if (k === "escape" && browsing && !typing) {
		browsing = false;
		return;
	}
	if (mode !== "build" || typing || !doc) return;
	if (k === "escape") selectedLayers = [];
	if (mod && k === "a") {
		e.preventDefault();
		selectedLayers = childrenOf(doc)
			.map((l) => String(l.id))
			.filter((id) => !locked.has(id));
		return;
	}
	const ids = selectedLayers.filter((id) => !locked.has(id));
	if (!ids.length) return;
	if (mod && k === "d") {
		e.preventDefault();
		duplicateMany(ids);
	} else if (mod && k === "g") {
		e.preventDefault();
		if (e.shiftKey) ungroupSelected();
		else groupSelected();
	} else if (k === "delete" || k === "backspace") {
		e.preventDefault();
		removeLayers(ids);
	} else if (k.startsWith("arrow")) {
		e.preventDefault();
		const step = e.shiftKey ? 10 : 1;
		const dx = k === "arrowleft" ? -step : k === "arrowright" ? step : 0;
		const dy = k === "arrowup" ? -step : k === "arrowdown" ? step : 0;
		if (mod) {
			// Ctrl+Up/Down moves the layer in the stack.
			if (dy && ids.length === 1)
				editDoc((d) => stepLayer(d, ids[0], dy < 0 ? 1 : -1));
		} else nudge(ids, dx, dy);
	}
}

// ---------------------------------------------------------------- problems

/** Problems panel filter set from the inspector: a layer id, or '' for the design itself. */
let problemFocus: string | null = $state(null);

const focus = $derived.by(() => {
	if (problemFocus === null || !doc) return null;
	const id = problemFocus;
	if (!id)
		return {
			label: "design settings",
			match: (d: Diagnostic) =>
				d.file === designPath && !layerAtPointer(doc!, d.path),
		};
	const ids = new Set([id, ...descendantsOf(id)]);
	return {
		label: `layer '${id}'`,
		match: (d: Diagnostic) =>
			d.file === designPath && ids.has(layerAtPointer(doc!, d.path) ?? ""),
	};
});

$effect(() => {
	if (problemFocus && doc && !findLayer(doc, problemFocus)) problemFocus = null;
});

/** Readable location of a problem: layer path then field, or the card. */
function crumbsOf(d: Diagnostic): string[] {
	const steps = (ptr: string) =>
		ptr
			.split("/")
			.filter(Boolean)
			.filter((x) => x !== "layers");
	if (d.file === designPath && doc) {
		const id = layerAtPointer(doc, d.path);
		if (id)
			return [
				...ancestorsOf(doc, id).reverse(),
				id,
				...steps(d.path.slice(layerPointer(doc, id)?.length ?? 0)),
			];
		return steps(d.path);
	}
	return [...(d.card ? [`card ${d.card}`] : []), ...steps(d.path)];
}

function openDiagnostic(d: Diagnostic) {
	if (!d.file || !files.has(d.file)) return;
	if (d.card && currentSet) {
		const i = currentSet.cards.findIndex((c) => c.id === d.card);
		if (i >= 0 && i !== cardIndex) {
			cardIndex = i;
			renderPreview();
		}
	}
	if (mode === "build" && d.file === designPath && doc) {
		const id = layerAtPointer(doc, d.path);
		if (id) {
			selectedLayers = [id];
			leftTab = "layers";
			return;
		}
		if (d.path.startsWith("/params")) {
			leftTab = "params";
			return;
		}
		if (d.path.startsWith("/canvas") || d.path === "/name") {
			selectedLayers = [];
			return;
		}
	}
	if (mode === "build" && d.file === currentSet?.cards_file) {
		leftTab = "card";
		return;
	}
	mode = "code";
	selected = d.file;
	sidePanel = "files";
	jump = { line: d.line || 1, col: d.col || 1, nonce: Math.random() };
}

function openJson() {
	mode = "code";
	if (designPath) selected = designPath;
	sidePanel = "files";
}

/** Writes the changed files back into the folder opened with write access. */
async function save() {
	if (!dirty.size || !dirHandle) return;
	for (const p of dirty) {
		const d = files.get(p);
		if (d) await writeFile(dirHandle, p, d);
		else await removeFile(dirHandle, p);
	}
	status = `Saved ${dirty.size} file(s) to ${dirHandle.name}.`;
	dirty = new Set();
}

// ---------------------------------------------------------------- export

async function exportPng() {
	if (!currentSet || !currentCard) return;
	busy = "Rendering PNG…";
	try {
		const r = await engine.render({
			set: setName,
			card: cardIndex,
			date: today,
			preview: false,
			format: "png",
		});
		if (r.bin.length) download(`${currentCard.id}.png`, r.bin, "image/png");
		lastRender = { ...r, bin: new Uint8Array() };
		const errs = r.diagnostics.filter((d) => d.severity === "error").length;
		if (errs) status = `Exported with ${errs} error(s); see the problems.`;
	} finally {
		busy = "";
	}
}

async function exportZip() {
	if (!currentSet) return;
	if (useServer && server?.render) return exportZipServer();
	busy = "Rendering 0%";
	try {
		const ids = currentSet.cards.map((c) => c.id);
		const r = await engine.renderAll(
			{ set: setName, date: today, preview: false, format: "png" },
			ids,
			(p) => (busy = `Rendering ${Math.round(p * 100)}%`),
		);
		const zip: Record<string, Uint8Array> = {};
		for (const f of r.files) zip[`${setName}/${f.id}.png`] = f.png;
		download(
			`${projectName}-${setName}.zip`,
			zipSync(zip, { level: 0 }),
			"application/zip",
		);
		const errs = r.diagnostics.filter((d) => d.severity === "error").length;
		status =
			`Exported ${r.files.length} card(s)` +
			(errs ? ` with ${errs} error(s)` : "");
		if (errs)
			lastRender = {
				width: 0,
				height: 0,
				missing_urls: [],
				bin: new Uint8Array(),
				diagnostics: r.diagnostics,
			};
	} finally {
		busy = "";
	}
}

function b64(data: Uint8Array) {
	let s = "";
	for (let i = 0; i < data.length; i += 0x8000)
		s += String.fromCharCode(...data.subarray(i, i + 0x8000));
	return btoa(s);
}

async function exportZipServer() {
	busy = "Uploading to the server…";
	try {
		const body = JSON.stringify({
			files: Object.fromEntries([...files].map(([p, d]) => [p, b64(d)])),
			set: setName,
			date: today,
			format: "png",
		});
		const res = await fetch("api/render", {
			method: "POST",
			headers: { "content-type": "application/json" },
			body,
		});
		if (!res.ok) {
			const err = await res.json().catch(() => ({ error: res.statusText }));
			status = `Server render failed: ${err.error ?? res.status}`;
			if (err.diagnostics)
				lastRender = {
					width: 0,
					height: 0,
					missing_urls: [],
					bin: new Uint8Array(),
					diagnostics: err.diagnostics,
				};
			return;
		}
		download(
			`${projectName}-${setName}.zip`,
			await res.blob(),
			"application/zip",
		);
		status = "Exported on the server.";
	} finally {
		busy = "";
	}
}

const typeLabels: Record<LayerType, string> = {
	rect: "▭ Rect",
	ellipse: "◯ Ellipse",
	text: "T Text",
	image: "🖼 Image",
	polygon: "△ Polygon",
};
</script>

<svelte:document onvisibilitychange={onHide} />
<svelte:window
	bind:innerWidth={winW}
	bind:innerHeight={winH}
	onkeydown={onKey}
	oncopy={(e) => onCopy(e)}
	oncut={(e) => onCopy(e, true)}
	onpaste={onPaste}
/>

{#snippet previewBar()}
	<span class="pick">
	<span class="caption">Design</span>
	<Select
		value={setName}
		label="Design"
		title="The design (card layout) being edited, with its card set"
		options={sets.map((s) => ({
			value: s.name,
			label: s.design_name,
			detail: `${s.cards.length} card${s.cards.length === 1 ? "" : "s"} · ${s.cards_file ?? s.name}`,
		}))}
		onchange={(v) => {
			setName = v;
			cardIndex = 0;
			selectedLayers = [];
			renderPreview();
		}}
	/>
	<CardPicker
		cards={currentSet?.cards ?? []}
		params={currentSet?.params ?? []}
		onbrowse={() => (browsing = true)}
		index={cardIndex}
		disabled={!currentSet?.cards.length}
		onpick={(i) => {
			cardIndex = i;
			cardIdError = "";
			renderPreview();
		}}
	/>
	</span>
	<span class="exports">
	<button
		onclick={exportPng}
		title="Export this card as a PNG"
		disabled={!!busy || !currentSet?.ok}>PNG</button
	>
	<button
		onclick={exportZip}
		disabled={!!busy || !currentSet?.ok}
		title="Render every card of this design into a zip">ZIP</button
	>
	{#if server?.render}
		<label
			class="server"
			title="Render the zip on the server at full quality"
		>
			<input type="checkbox" bind:checked={useServer} /> on server
		</label>
	{/if}
	</span>
{/snippet}

{#snippet filesPanel()}
	<FileBrowser
		{files}
		{dirty}
		uses={fileUses}
		bind:selected={filesSelected}
		bind:folder={uploadFolder}
		highlight={filesHighlight}
		onopen={openFromBrowser}
		onrename={(from, to) => movePaths([[from, to]])}
		ondelete={deletePath}
		onmove={(paths, folder) =>
			movePaths(paths.map((p) => [p, join(folder, baseOf(p))]))}
		onnewfolder={newFolder}
		onupload={uploadTo}
		onduplicate={duplicateFile}
		ondropfiles={(list, folder) => importFiles(list, folder)}
	/>
	{#if mode === "build" && filesSelected && files.has(filesSelected)}
		{@const f = filesSelected}
		<div class="file-info">
			<div class="file-name mono" title={f}>{f}</div>
			{#if filesPreviewUrl}<img
					class="file-preview"
					src={filesPreviewUrl}
					alt={f}
				/>{/if}
			<div class="muted small">
				{formatSize(files.get(f)?.length ?? 0)}{fileUses.get(f)
					? ` · used by ${fileUses.get(f)} file${fileUses.get(f) === 1 ? "" : "s"}`
					: " · not referred to by name"}
			</div>
			<div class="row-btns">
				<button
					onclick={() => copyPath(f)}
					title="Copy the path, for use in a field">Copy path</button
				>
				{#if isText(f)}<button
						onclick={() => {
							mode = "code";
							selected = f;
							sidePanel = "files";
						}}>Open in JSON</button
					>{/if}
			</div>
		</div>
	{/if}
{/snippet}

{#snippet cardList()}
	{#if currentSet}
		<div class="cards">
			<div class="cards-head">
				<span
					>Cards of <b>{currentSet.design_name}</b>
					<span class="muted">({currentSet.cards.length})</span></span
				>
				<button
					class="mini"
					onclick={() => (browsing = true)}
					title="Browse all cards in a big window, as a table or as pictures"
					>⤢ Browse</button
				>
			</div>
			<CardList
				cards={currentSet.cards}
				params={currentSet.params}
				index={cardIndex}
				height={Math.max(
					60,
					Math.min(sizes.cardList, currentSet.cards.length * 34 + 8),
				)}
				onpick={(i) => {
					cardIndex = i;
					cardIdError = "";
					renderPreview();
				}}
			/>
			{#if currentSet.cards.length > 3}
				<div class="list-split">
					<Splitter
						axis="y"
						label="Card list height"
						size={() => sizes.cardList}
						min={80}
						max={2000}
						onresize={(px) => (sizes.cardList = px)}
						onreset={() =>
							(sizes.cardList = layoutDefaults.cardList)}
						ondone={saveSizes}
					/>
				</div>
			{/if}
			{#if currentSet.cards_file}
				<div class="card-tools">
					<button
						onclick={() =>
							editCards({ op: "add", after: cardIndex })}
						title="Add a card after this one">+ Card</button
					>
					<button
						disabled={!currentCard}
						onclick={() =>
							editCards({ op: "duplicate", index: cardIndex })}
						title="Duplicate this card"
						aria-label="Duplicate this card"><Icon name="copy" /></button
					>
					<button
						disabled={!currentCard || cardIndex === 0}
						onclick={() =>
							editCards({
								op: "move",
								index: cardIndex,
								to: cardIndex - 1,
							})}
						title="Move up"
						aria-label="Move the card up"><Icon name="up" /></button
					>
					<button
						disabled={!currentCard ||
							cardIndex >= currentSet.cards.length - 1}
						onclick={() =>
							editCards({
								op: "move",
								index: cardIndex,
								to: cardIndex + 1,
							})}
						title="Move down"
						aria-label="Move the card down"><Icon name="down" /></button
					>
					<button
						disabled={!currentCard}
						onclick={async () =>
							(await confirmAction({
								title: `Delete card '${currentCard?.id}'?`,
								message:
									"The card is removed from the card file. Undo brings it back.",
								confirm: "Delete",
								danger: true,
							})) &&
							editCards({ op: "delete", index: cardIndex })}
						title="Delete this card"
						aria-label="Delete this card"><Icon name="trash" /></button
					>
				</div>
				{#if currentCard}
					<label class="card-id">
						<span>id</span>
						<input
							value={currentCard.id}
							onchange={(e) =>
								renameCard(e.currentTarget.value.trim())}
							onkeydown={(e) =>
								e.key === "Enter" && e.currentTarget.blur()}
						/>
					</label>
					{#if cardIdError}<p class="err">{cardIdError}</p>{/if}
				{/if}
			{/if}
		</div>
	{/if}
{/snippet}

{#if fatal}
	<div class="fatal">{fatal}</div>
{:else}
	<div
		bind:this={appEl}
		class="app"
		style:--left-w="{leftW}px"
		style:--right-w="{rightW}px"
		style:--bottom-h="{bottomH}px"
		style:--files-w="{filesW}px"
		style:--preview-w={previewW
			? `${previewW}px`
			: "minmax(320px, 1fr)"}
		class:build={mode === "build"}
		class:dropping
		ondragover={onDragOver}
		ondragleave={(e) => {
			if (!e.relatedTarget) dropping = false;
		}}
		ondrop={onDrop}
		role="application"
	>
		<header class="top">
			<strong class="brand">yoshida</strong>
			<span class="ver">{engine.version}</span>
			<button
				class="project-btn"
				onclick={projectMenu}
				aria-haspopup="menu"
				title="Projects: new, open, export, saved in this browser, examples"
			>
				<span class="pname">{projectName || "No project"}</span>
				{#if !projectId && projectName}<span class="tag">example</span
					>{/if}
				<svg viewBox="0 0 10 6" aria-hidden="true"
					><path
						d="M1 1l4 4 4-4"
						fill="none"
						stroke="currentColor"
						stroke-width="1.5"
					/></svg
				>
			</button>
			<span
				class="saved {saveState}"
				title="Projects are saved in this browser only; nothing is sent to a server. Export a .yoshida file to keep a copy elsewhere."
			>
				{saveState === "saving"
					? "Saving…"
					: saveState === "saved"
						? "✓ Saved in this browser"
						: saveState === "unsaved"
							? "● Unsaved"
							: saveState === "error"
								? "⚠ Not saved"
								: "Example (saved once you change it)"}
			</span>
			<button
				onclick={newDesign}
				disabled={!projectName}
				title="Add a blank design and card file to this project"
				>+ Design</button
			>
			<button
				onclick={uploadImage}
				disabled={!projectName}
				title="Add an image from your computer to {uploadFolder
					? `${uploadFolder}/`
					: 'assets/images/'} (it stays in your browser; choose the folder in the Files tab)"
				>Upload image</button
			>
			<button
				onclick={addFiles}
				disabled={!projectName}
				title="Add images, fonts or data files (or drop them on the window)"
				>Add files</button
			>
			<span class="spacer"></span>
			<div class="segmented" role="tablist">
				<button
					role="tab"
					aria-selected={mode === "build"}
					class:active={mode === "build"}
					onclick={() => (mode = "build")}>Builder</button
				>
				<button
					role="tab"
					aria-selected={mode === "code"}
					class:active={mode === "code"}
					onclick={() => (mode = "code")}
					title="Raw files, for everything the builder does not cover"
					>Advanced (JSON)</button
				>
			</div>
			<button
				onclick={undo}
				disabled={!undoStack.length}
				title="Undo (Ctrl+Z)">↶</button
			>
			<button
				onclick={redo}
				disabled={!redoStack.length}
				title="Redo (Ctrl+Shift+Z)">↷</button
			>
			{#if dirHandle}
				<button
					onclick={save}
					disabled={!dirty.size}
					title="Write changes to {dirHandle.name}"
					>Save to folder{dirty.size
						? ` (${dirty.size})`
						: ""}</button
				>
			{:else if canOpenWritable()}
				<button
					onclick={saveToFolder}
					title="Write the whole project to a folder on your computer and keep saving there"
					>Save to folder…</button
				>
			{/if}
			<button
				onclick={exportProject}
				disabled={!files.size}
				title="Download the whole project, images and fonts included, as a .yoshida file"
				>Export .yoshida</button
			>
		</header>

		{#if mode === "build"}
			<aside class="left">
				<div class="tabs">
					<button
						class:active={leftTab === "layers"}
						onclick={() => (leftTab = "layers")}>Layers</button
					>
					<button
						class:active={leftTab === "params"}
						onclick={() => (leftTab = "params")}>Params</button
					>
					<button
						class:active={leftTab === "card"}
						onclick={() => (leftTab = "card")}>Card data</button
					>
					<button
						class:active={leftTab === "files"}
						onclick={() => (leftTab = "files")}
						title="Project files: images, fonts, designs and card data"
						>Files</button
					>
				</div>
				{#if leftTab === "files"}
					{@render filesPanel()}
				{:else if !doc}
					<p class="muted pad">
						{#if parsed.error}The design file has a syntax error ({parsed.error}).
							<button onclick={openJson}>Fix it in JSON</button
							>{:else}No design in this project.{/if}
					</p>
				{:else if leftTab === "layers"}
					<div class="fill">
						<LayerTree
							layers={childrenOf(doc)}
							selected={selectedLayers}
							{locked}
							problems={layerProblems}
							onselect={(ids) => (selectedLayers = ids)}
							onvisible={toggleVisible}
							onlock={toggleLock}
							onmove={moveInTree}
							oncontext={layerMenu}
						/>
					</div>
				{:else if leftTab === "params"}
					<ParamsPanel
						{doc}
						{imageFiles}
						upload={uploadImage}
						{diagnostics}
						designFile={designPath ?? ""}
						{editDoc}
						onrename={renameParamEverywhere}
						cards={designCards}
						onrenameoption={renameOptionEverywhere}
					/>
				{:else if currentSet}
					{@render cardList()}
					<CardForm
						params={currentSet.params}
						card={currentCard}
						editable={!!currentSet.cards_file}
						{imageFiles}
						upload={uploadImage}
						onchange={setCard}
					/>
				{/if}
			</aside>
			<div class="split-l">
				<Splitter
					axis="x"
					label="Left panel width"
					size={() => areaSize(".left", "x")}
					min={200}
					max={sideRoom - rightW}
					onresize={(px) => (sizes.left = px)}
					onreset={() => (sizes.left = layoutDefaults.left)}
					ondone={saveSizes}
				/>
			</div>

			<main class="center">
				<div class="toolbar">
					<span class="group" aria-label="Add layer">
						{#each layerTypes as t}
							<button
								disabled={!doc}
								onclick={() => addLayer(t)}
								aria-label="Add a {t} layer"
								title="Add a {t} layer"
								><span class="ico" aria-hidden="true"
									>{typeLabels[t].split(" ")[0]}</span
								><span class="lbl" aria-hidden="true"
									>{typeLabels[t].replace(/^\S+\s/, "")}</span
								></button
							>
						{/each}
					</span>
					<span class="sep"></span>
					{@render previewBar()}
				</div>
				<Stage
					{image}
					{layout}
					selected={selectedLayers}
					handles={handlesFor}
					{locked}
					{stale}
					staleNote={status}
					interactive={!!doc}
					onselect={(ids) => (selectedLayers = ids)}
					ongesture={onGesture}
					pick={pickOnCanvas}
					oncontext={layerMenu}
				/>
				<div class="status">{busy || status}</div>
			</main>

			<div class="split-r">
				<Splitter
					axis="x"
					sign={-1}
					label="Right panel width"
					size={() => areaSize(".right", "x")}
					min={260}
					max={sideRoom - leftW}
					onresize={(px) => (sizes.right = px)}
					onreset={() => (sizes.right = layoutDefaults.right)}
					ondone={saveSizes}
				/>
			</div>
			<aside class="right">
				{#if doc}
					<Inspector
						{doc}
						ids={selectedLayers}
						{imageFiles}
						upload={uploadImage}
						{fontFiles}
						{diagnostics}
						designFile={designPath ?? ""}
						{editLayer}
						{editDoc}
						rename={renameSelected}
						onalign={align}
						ondistribute={distribute}
						onduplicate={() => duplicateMany(selectedLayers)}
						ondelete={() => removeLayers(selectedLayers)}
						ongroup={groupSelected}
						onungroup={ungroupSelected}
						onproblems={(id) => (problemFocus = id ?? "")}
						{listKeys}
					/>
					<p class="advanced">
						Need something the builder does not cover? <button
							class="link"
							onclick={openJson}>Edit the JSON</button
						>
					</p>
				{/if}
			</aside>
		{:else}
			<aside class="files">
				<div class="tabs">
					<button
						class:active={sidePanel === "card"}
						onclick={() => (sidePanel = "card")}>Card</button
					>
					<button
						class:active={sidePanel === "files"}
						onclick={() => (sidePanel = "files")}>Files</button
					>
				</div>
				{#if sidePanel === "files"}
					{@render filesPanel()}
				{:else if currentSet}
					<CardForm
						params={currentSet.params}
						card={currentCard}
						editable={!!currentSet.cards_file}
						{imageFiles}
						upload={uploadImage}
						onchange={setCard}
					/>
				{/if}
			</aside>

			<div class="split-f">
				<Splitter
					axis="x"
					label="Files panel width"
					size={() => areaSize(".files", "x")}
					min={200}
					max={sideRoom - (previewW ?? 320)}
					onresize={(px) => (sizes.files = px)}
					onreset={() => (sizes.files = layoutDefaults.files)}
					ondone={saveSizes}
				/>
			</div>
			<main class="editor-pane">
				<div class="pane-title">{selected ?? "No file"}</div>
				{#if selected && isText(selected)}
					{#await loadEditor()}
						<p class="muted pad">Loading the editor…</p>
					{:then { default: Editor }}
						<Editor
							text={selectedText}
							path={selected}
							diagnostics={fileDiagnostics}
							{jump}
							onchange={(t) => editText(selected!, t)}
						/>
					{/await}
				{:else if imageUrl}
					<div class="image-view">
						<img src={imageUrl} alt={selected} />
					</div>
				{:else if selected}
					<p class="muted pad">
						Binary file ({files.get(selected)?.length ?? 0} bytes).
					</p>
				{/if}
			</main>

			<div class="split-p">
				<Splitter
					axis="x"
					sign={-1}
					label="Preview width"
					size={() => areaSize(".preview-pane", "x")}
					min={260}
					max={sideRoom - filesW}
					onresize={(px) => (sizes.preview = px)}
					onreset={() => (sizes.preview = null)}
					ondone={saveSizes}
				/>
			</div>
			<section class="preview-pane">
				<div class="pane-title row">{@render previewBar()}</div>
				<Stage
					{image}
					{layout}
					selected={[]}
					handles={() => "none"}
					{locked}
					{stale}
					staleNote={status}
					interactive={false}
					onselect={() => {}}
					ongesture={() => {}}
				/>
				<div class="status">{busy || status}</div>
			</section>
		{/if}

		<div class="split-b">
			<Splitter
				axis="y"
				sign={-1}
				label="Problems panel height"
				size={() => areaSize(".problems-pane", "y")}
				min={60}
				max={bottomMax}
				onresize={(px) =>
					mode === "build"
						? (sizes.bottom = px)
						: (sizes.codeBottom = px)}
				onreset={() =>
					mode === "build"
						? (sizes.bottom = layoutDefaults.bottom)
						: (sizes.codeBottom = layoutDefaults.codeBottom)}
				ondone={saveSizes}
			/>
		</div>
		<footer class="problems-pane">
			<Problems
				{diagnostics}
				onselect={openDiagnostic}
				crumbs={crumbsOf}
				focus={mode === "build" ? focus : null}
				onclearfocus={() => (problemFocus = null)}
			/>
		</footer>
	</div>
{/if}

{#if browsing && currentSet}
	<Window
		key="cards"
		title="Cards of {currentSet.design_name} ({currentSet.cards.length})"
		width={860}
		height={560}
		onclose={() => (browsing = false)}
	>
		<CardBrowser
			cards={currentSet.cards}
			params={currentSet.params}
			index={cardIndex}
			canRender={currentSet.ok}
			thumb={cardThumb}
			onpick={(i) => {
				cardIndex = i;
				cardIdError = "";
				renderPreview();
			}}
		/>
	</Window>
{/if}

<DialogHost />
<MenuHost />

<style>
	/* Splitters sit in their own 5px tracks between the panels. */
	.app {
		display: grid;
		grid-template-columns: var(--files-w) 5px minmax(300px, 1fr) 5px var(
				--preview-w
			);
		grid-template-rows: auto minmax(0, 1fr) 5px var(--bottom-h);
		grid-template-areas:
			"top top top top top"
			"files fsplit editor psplit preview"
			"files fsplit bsplit bsplit bsplit"
			"files fsplit problems problems problems";
		height: 100vh;
	}
	.app.build {
		grid-template-columns: var(--left-w) 5px minmax(360px, 1fr) 5px var(
				--right-w
			);
		grid-template-areas:
			"top top top top top"
			"left lsplit center rsplit right"
			"left lsplit bsplit rsplit right"
			"left lsplit problems rsplit right";
	}
	.split-l {
		grid-area: lsplit;
	}
	.split-r {
		grid-area: rsplit;
	}
	.split-f {
		grid-area: fsplit;
	}
	.split-p {
		grid-area: psplit;
	}
	.split-b {
		grid-area: bsplit;
	}
	.split-l,
	.split-r,
	.split-f,
	.split-p,
	.split-b {
		min-width: 0;
		min-height: 0;
	}
	.left {
		display: flex;
		flex-direction: column;
	}
	.fill {
		flex: 1 0 auto;
		display: flex;
		flex-direction: column;
	}
	.fill > :global(.tree) {
		flex: 1;
	}
	.list-split {
		height: 6px;
		margin: -2px 0 0;
	}
	.cards-head .mini {
		padding: 1px 8px;
		font-size: 12px;
	}
	.cards-head {
		align-items: center;
	}
	.file-info {
		border-top: 1px solid var(--line);
		padding: 8px 12px 12px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		position: sticky;
		bottom: 0;
		background: var(--bg);
	}
	.file-name {
		font-size: 12px;
		word-break: break-all;
	}
	.file-preview {
		max-width: 100%;
		max-height: 180px;
		object-fit: contain;
		align-self: center;
		background: repeating-conic-gradient(#ccc 0 25%, #eee 0 50%) 0 0 / 12px
			12px;
	}
	.small {
		font-size: 11px;
	}
	.mono {
		font-family: var(--mono);
	}
	.row-btns {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
	}
	.row-btns button {
		font-size: 12px;
		padding: 2px 8px;
	}
	/* The top bar wraps onto a second row when it runs out of room, instead
	   of squeezing its buttons into two-line labels. */
	.top {
		grid-area: top;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px 8px;
		padding: 6px 12px;
		border-bottom: 1px solid var(--line);
		background: var(--bg-bar);
		min-width: 0;
	}
	.top > button,
	.top > .segmented {
		flex: none;
		white-space: nowrap;
	}
	.brand {
		font-size: 16px;
	}
	.project-btn {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		max-width: 260px;
		font-weight: 600;
	}
	.project-btn svg {
		width: 10px;
		height: 6px;
		flex: none;
		color: var(--muted);
	}
	.pname {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.tag {
		font-size: 10px;
		font-weight: 500;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		padding: 0 5px;
		border-radius: 4px;
		background: var(--hover);
		color: var(--muted);
	}
	.saved {
		font-size: 12px;
		color: var(--muted);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 16em;
	}
	.saved.unsaved {
		color: var(--warn);
	}
	.saved.error {
		color: var(--err);
	}
	.ver {
		color: var(--muted);
		font-size: 12px;
	}
	.spacer {
		flex: 1;
	}
	.segmented {
		display: flex;
		border: 1px solid var(--line);
		border-radius: 7px;
		overflow: hidden;
	}
	.segmented button {
		border: 0;
		border-radius: 0;
		white-space: nowrap;
	}
	.segmented button.active {
		background: var(--accent-strong);
		color: var(--on-accent);
	}
	.files,
	.left {
		border-right: 1px solid var(--line);
		overflow: auto;
		min-height: 0;
	}
	.files {
		grid-area: files;
	}
	.left {
		grid-area: left;
	}
	.right {
		grid-area: right;
		border-left: 1px solid var(--line);
		overflow: auto;
		min-height: 0;
	}
	.center {
		grid-area: center;
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
		overflow: hidden;
		container-type: inline-size;
	}
	/* Toolbars wrap whole groups, never single buttons; the export group
	   stays on the right. */
	.toolbar,
	.pane-title.row {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		align-items: center;
		padding: 6px 10px;
		border-bottom: 1px solid var(--line);
	}
	.toolbar .group,
	.pick,
	.exports {
		display: flex;
		gap: 4px;
		align-items: center;
		flex: none;
	}
	.pick {
		gap: 6px;
		flex: 0 1 auto;
		flex-wrap: wrap;
		min-width: 0;
	}
	.exports {
		margin-left: auto;
	}
	.toolbar .group button {
		padding: 4px 8px;
		white-space: nowrap;
	}
	.toolbar .group .ico {
		display: inline-block;
		min-width: 1em;
		margin-right: 4px;
		text-align: center;
	}
	/* A narrow stage keeps the layer buttons as icons (names in the tooltip). */
	@container (max-width: 860px) {
		.toolbar .group .lbl {
			display: none;
		}
		.toolbar .group .ico {
			margin-right: 0;
		}
	}
	.sep {
		width: 1px;
		align-self: stretch;
		background: var(--line);
		margin: 0 4px;
	}
	.tabs {
		display: flex;
		border-bottom: 1px solid var(--line);
		position: sticky;
		top: 0;
		background: var(--bg);
		z-index: 1;
	}
	.tabs button {
		flex: 1 1 auto;
		border: 0;
		border-radius: 0;
		background: none;
		padding: 8px 4px;
		white-space: nowrap;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.tabs button.active {
		border-bottom: 2px solid var(--accent);
		font-weight: 600;
	}
	.editor-pane {
		grid-area: editor;
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
		border-right: 1px solid var(--line);
	}
	.editor-pane > :global(.editor) {
		flex: 1;
	}
	.pane-title {
		padding: 6px 12px;
		font: 12px var(--mono);
		border-bottom: 1px solid var(--line);
		color: var(--muted);
	}
	.pane-title.row {
		font: inherit;
		color: inherit;
		padding: 6px 12px;
	}
	.image-view {
		overflow: auto;
		padding: 12px;
	}
	.image-view img {
		max-width: 100%;
		background: repeating-conic-gradient(#ccc 0 25%, #eee 0 50%) 0 0 / 16px
			16px;
	}
	.preview-pane {
		grid-area: preview;
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
		overflow: hidden;
	}
	.status {
		padding: 4px 12px;
		font-size: 12px;
		color: var(--muted);
		border-top: 1px solid var(--line);
	}
	.problems-pane {
		grid-area: problems;
		border-top: 1px solid var(--line);
		min-height: 0;
	}
	.server {
		font-size: 12px;
		display: flex;
		gap: 4px;
		align-items: center;
	}
	.advanced {
		font-size: 12px;
		color: var(--muted);
		padding: 10px 12px;
		margin: 0;
	}
	.link {
		all: unset;
		color: var(--accent);
		cursor: pointer;
		text-decoration: underline;
	}
	.muted {
		color: var(--muted);
	}
	.pad {
		padding: 12px;
	}
	.fatal {
		padding: 24px;
		color: var(--err);
	}
	@media (max-width: 900px) {
		.split-l,
		.split-r,
		.split-f,
		.split-p,
		.split-b {
			display: none;
		}
		.app,
		.app.build {
			/* minmax(0, …): a wide code line must not widen the page. */
			grid-template-columns: minmax(0, 1fr);
			grid-template-rows: auto auto 60vh auto 240px;
			grid-template-areas: "top" "files" "preview" "editor" "problems";
			height: auto;
		}
		.app.build {
			grid-template-areas: "top" "center" "left" "right" "problems";
			grid-template-rows: auto 60vh auto auto 240px;
		}
		.files,
		.left,
		.right {
			max-height: 50vh;
		}
		.top {
			flex-wrap: wrap;
		}
	}
	.app.dropping {
		outline: 3px dashed var(--accent);
		outline-offset: -3px;
	}
	.cards {
		padding: 8px 12px 4px;
		border-bottom: 1px solid var(--line);
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.cards-head {
		display: flex;
		justify-content: space-between;
		font-size: 12px;
	}
	.caption {
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--muted);
	}
	.card-tools {
		display: flex;
		gap: 4px;
	}
	.card-tools button {
		min-width: 30px;
		min-height: 28px;
	}
	.card-id {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		color: var(--muted);
	}
	.card-id input {
		flex: 1;
		font-family: var(--mono);
	}
	.err {
		color: var(--err);
		font-size: 12px;
		margin: 0;
	}
</style>
