<script lang="ts">
	import { unzipSync, zipSync } from "fflate";
	import { onMount, setContext } from "svelte";
	import type { GotoTarget } from "./lib/builder/complete";
	import Inspector from "./lib/builder/Inspector.svelte";
	import LayerTree from "./lib/builder/LayerTree.svelte";
	import ParamsPanel from "./lib/builder/ParamsPanel.svelte";
	import Stage, { type Sprite } from "./lib/builder/Stage.svelte";
	import CardForm from "./lib/CardForm.svelte";
	import TelemetryNotice from "./lib/telemetry/TelemetryNotice.svelte";
	import TelemetryWindow from "./lib/telemetry/TelemetryWindow.svelte";
	import {
		initTelemetry,
		noticeDue,
		openSettings as openPrivacy,
		telemetry,
		track,
		trackOnce,
	} from "./lib/telemetry/state.svelte";
	import type { ServerTelemetry } from "./lib/telemetry/core";
	import Logo from "./lib/ui/Logo.svelte";
	import ThemeToggle from "./lib/ui/ThemeToggle.svelte";
	import {
		type AlignMode,
		alignLayers,
		ancestorsOf,
		childrenOf,
		clone,
		deleteLayer,
		distributeLayers,
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
		type Json,
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
		renameItemOption,
		renameItemValueInCards,
		renameLayer,
		renameParam,
		renameParamInCards,
		renameValueInCards,
		reorderLayer,
		resizeLayer,
		rotateLayer,
		stepLayer,
		ungroupLayer,
		uniqueId,
	} from "./lib/design";
	import {
		componentAround,
		componentLabel,
		componentPath,
		detached,
		expandIncludes,
		includeBlocker,
		includedPaths,
		includeOf,
		includersOf,
		isComponentFile,
		type ReadText,
		splitIncludes,
	} from "./lib/components";
	import { type LayerTag, layerTags, tagLabels } from "./lib/tags";
	import {
		type CheckResult,
		type CoreLimits,
		type Diagnostic,
		Engine,
		type Param,
		renderClock,
		type RenderResult,
		type SetInfo,
	} from "./lib/engine";
	import { listKeys as listKeysOf } from "./lib/expr/catalog";
	import { LIVE_CONTEXT, type LiveContext } from "./lib/expr/live";
	import { describeFile } from "./lib/filetypes";
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
		usedBy,
	} from "./lib/paths";
	import {
		blankCards,
		blankDesign,
		bytesOf,
		type CardListOp,
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
		isPicture,
		pictureUrl,
		isText,
		listExamples,
		loadExample,
		MANIFEST,
		PROJECT_EXT,
		PROJECT_MIME,
		parseCsv,
		projectFileRe,
		projectZip,
		setCardValue,
		slug,
		textOf,
		UTC_OFFSET_LIMIT,
		utcOffsetOf,
		groupSets,
		newProjectFiles,
		withSet,
		withUtcOffset,
		writeCsv,
	} from "./lib/project";
	import {
		type QaDoc,
		type QaMark,
		QA_FILE,
		cardHash,
		contentHash,
		designFingerprint,
		parseQa,
		reconcileQa,
		statusOf,
		openComments,
		stampNow,
		withComment,
		withCommentEdit,
		withMark,
		withoutComment,
		needsReview,
		type QaComment,
		writeQa,
	} from "./lib/qa";
	import {
		activeBackend,
		backendById,
		type FolderLink,
	} from "./lib/folder/backend";
	import "./lib/folder/browser";
	import {
		diffCount,
		diffFiles,
		type FileDiff,
		findExternalChanges,
		planReconnect,
		type Sigs,
	} from "./lib/folder/sync";
	import {
		deleteFolder,
		deleteProject,
		formatAge,
		formatSize,
		lastProject,
		listProjects,
		loadFolder,
		loadProject,
		newProjectId,
		type ProjectMeta,
		persistStorage,
		saveFolder,
		saveProject,
		setLastProject,
	} from "./lib/store";
	import CardBrowser from "./lib/ui/CardBrowser.svelte";
	import CardList from "./lib/ui/CardList.svelte";
	import QaControl from "./lib/ui/QaControl.svelte";
	import QaBadge from "./lib/ui/QaBadge.svelte";
	import CardPicker from "./lib/ui/CardPicker.svelte";
	import DialogHost from "./lib/ui/DialogHost.svelte";
	import ExportDialog from "./lib/ui/ExportDialog.svelte";
	import {
		type CanvasInfo,
		canEncodeLosslessWebp,
		canEncodeWebp,
		cleanSettings,
		designHasBleed,
		designOutputs,
		type ExportFormat,
		type ExportSettings,
		formatLabels,
		formatScale,
		hasBleed,
		imagePath,
		pdfPath,
		type PlanSet,
		planExport,
		setJpegDpi,
		setMaxSide,
		sheetCount,
		sheetPath,
	} from "./lib/exportPlan";
	import {
		type DragPreview,
		dragLabels,
		type PreviewQuality,
		previewScale,
		qualityLabels,
		thumbScale,
	} from "./lib/quality";
	import { loadPref, savePref } from "./lib/ui/drag";
	import FileBrowser from "./lib/ui/FileBrowser.svelte";
	import Icon, { layerIcon } from "./lib/ui/Icon.svelte";
	import MenuHost from "./lib/ui/MenuHost.svelte";
	import {
		askText,
		chooseAction,
		confirmAction,
		type MenuItem,
		openMenu,
	} from "./lib/ui/overlay.svelte";
	import ProgressHost from "./lib/ui/ProgressHost.svelte";
	import {
		formatBytes,
		formatMs,
		progress,
		Run,
	} from "./lib/ui/progress.svelte";
	import Select from "./lib/ui/Select.svelte";
	import Splitter from "./lib/ui/Splitter.svelte";
	import TooltipHost from "./lib/ui/TooltipHost.svelte";
	import Window from "./lib/ui/Window.svelte";
	import FunctionsWindow from "./lib/expr/FunctionsWindow.svelte";
	import {
		closeFunctions,
		functionsRef,
		openFunctions,
	} from "./lib/expr/functionsRef.svelte";
	import FontsWindow, {
		type FontAdd,
		type FontsTarget,
	} from "./lib/fonts/FontsWindow.svelte";
	import {
		findLicense,
		fontEntryPath,
		licenseKind,
		previewFace,
		previewTextOf,
	} from "./lib/fonts/project";

	// CodeMirror is only needed in the Advanced view; load it on demand.
	const loadEditor = () => import("./lib/Editor.svelte");

	const engine = new Engine();
	// "dev" for a preview build, known once the engine has loaded.
	let channel = $state("");

	let status = $state("Starting…");
	/**
	 * A project being opened: its name and the step it is in. Shown over the
	 * preview until the first card is drawn (see refresh).
	 */
	let loading = $state<{ name: string; step: number; label: string } | null>(
		null,
	);
	const loadSteps = ["Reading files", "Checking designs", "Drawing the first card"];
	function loadStep(step: number) {
		if (loading) loading = { ...loading, step, label: loadSteps[step] };
	}
	let fatal = $state("");
	let examples: Example[] = $state([]);
	let projectName = $state("");
	/** Id of the project in this browser's storage; null for an unchanged example. */
	let projectId: string | null = $state(null);
	let myProjects = $state.raw<ProjectMeta[]>([]);
	let files = $state.raw<Files>(new Map());
	let dirty = $state.raw(new Set<string>());
	/** The folder on disk this project is linked to, or null. */
	let folder = $state.raw<FolderLink | null>(null);
	/** Fingerprints of the folder's files after the last sync. */
	let folderSigs: Sigs = new Map();
	type FolderNotice =
		| { kind: "permission" }
		| { kind: "changed"; paths: string[]; sigs: Sigs }
		| { kind: "conflict"; diff: FileDiff }
		| { kind: "error"; message: string };
	/** Something about the linked folder that needs an answer from the user. */
	let folderNotice = $state.raw<FolderNotice | null>(null);
	let folderWriting = $state(false);
	let selected: string | null = $state(null);
	let check = $state.raw<CheckResult | null>(null);
	let setName = $state("");
	let cardIndex = $state(0);
	let lastRender = $state.raw<RenderResult | null>(null);
	let renderMs = $state(0);
	/** Proxy scale of the render that took `renderMs`. */
	let renderScale = 1;
	let jump: { line: number; col: number; nonce: number } | null =
		$state(null);
	let sidePanel: "card" | "files" = $state("card");
	type ServerInfo = {
		render: boolean;
		max_cards: number;
		max_body_mb?: number;
		version?: string;
		limits?: CoreLimits;
		telemetry?: ServerTelemetry;
	};
	let server = $state<ServerInfo | null>(null);
	let useServer = $state(false);
	let busy = $state("");

	// Builder state
	let mode: "build" | "code" = $state("build");
	let leftTab: "layers" | "params" | "card" | "files" = $state("layers");
	let selectedLayers: string[] = $state([]);
	// Go to definition from an expression field (Ctrl/Cmd+click, F12): which
	// param, inspector part or layer to bring into view; `n` makes each request new.
	let paramFocus: { name: string; n: number } | null = $state(null);
	let inspectorFocus: { key: string; n: number } | null = $state(null);
	let layerReveal: { id: string; n: number } | null = $state(null);
	let gotoCount = 0;

	function goto(t: GotoTarget) {
		const n = ++gotoCount;
		if (t.kind === "param") {
			leftTab = "params";
			paramFocus = { name: t.name, n };
		} else if (t.kind === "layer") {
			selectedLayers = [t.id];
			leftTab = "layers";
			layerReveal = { id: t.id, n };
		} else if (t.kind === "repeat") {
			selectedLayers = [t.layer];
			inspectorFocus = { key: "repeat", n };
			if (leftTab === "layers") layerReveal = { id: t.layer, n };
		} else {
			selectedLayers = [];
			inspectorFocus = { key: `${t.kind}:${t.name}`, n };
		}
	}
	setContext("yoshida-goto", goto);
	// Live values in the formula panel: the field evaluated for the card on
	// the stage.
	const live: LiveContext = {
		card: () => {
			const s = currentSet;
			const c = currentCard;
			return s && c ? `${c.id} (${cardIndex + 1}/${s.cards.length})` : null;
		},
		eval: (path, src) =>
			currentSet
				? engine.eval(currentSet.name, path, src, cardIndex, renderClock())
				: Promise.resolve(null),
		scope: (path) =>
			currentSet
				? engine.scope(currentSet.name, path)
				: Promise.resolve(null),
		design: () => doc,
		extract: (next, path, text) =>
			editDoc((d) => {
				for (const key of ["consts", "functions"])
					if (next[key] !== undefined) d[key] = next[key] as Json;
				setPointer(d, path, text);
			}, "extract"),
	};

	/** Sets the value at a JSON pointer of `d` (the parents exist: it is a field being edited). */
	function setPointer(d: Obj, path: string, v: string) {
		const segs = path
			.split("/")
			.slice(1)
			.map((s) => s.replace(/~1/g, "/").replace(/~0/g, "~"));
		let cur: unknown = d;
		for (const seg of segs.slice(0, -1))
			cur = (cur as Record<string, unknown> | undefined)?.[seg];
		if (cur && typeof cur === "object")
			(cur as Record<string, unknown>)[segs[segs.length - 1]] = v;
	}
	setContext(LIVE_CONTEXT, live);
	const selectedLayer = $derived(
		selectedLayers.length === 1 ? selectedLayers[0] : null,
	);
	let locked = $state.raw(new Set<string>());
	let image = $state.raw<ImageData | null>(null);
	/** Canvas size of the last render (the image is smaller for a proxy render). */
	let imageSize = $state.raw<{ w: number; h: number } | null>(null);
	let layout = $state.raw<Placed[]>([]);
	let stale = $state(false);

	// Proxy renders: the preview renders as many pixels as the screen shows.
	const qualityKey = "yoshida.preview";
	let previewQuality = $state<PreviewQuality>(
		loadPref(qualityKey, { quality: "auto" as PreviewQuality }).quality,
	);
	/** Screen (CSS) pixels per canvas pixel on the stage; 0 until it is laid out. */
	let stageShown = $state(0);
	/** The scale of the picture on the stage. */
	let shownScale = 1;
	const dpr = () =>
		typeof devicePixelRatio === "number" ? devicePixelRatio : 1;
	const wantedScale = $derived.by(() => {
		const c = canvasSize;
		// Before the stage is laid out, assume it is about 1400 pixels wide.
		const shown = stageShown || Math.min(1, 1400 / Math.max(c.w, c.h, 1));
		return previewScale(previewQuality, shown, dpr());
	});
	// A zoom or quality change that needs a sharper (or allows a cheaper) picture.
	$effect(() => {
		const k = wantedScale;
		if (image && k !== shownScale) scheduleRefresh();
	});

	function setPreviewQuality(q: PreviewQuality) {
		previewQuality = q;
		savePref(qualityKey, { quality: q });
	}

	// What the stage shows while a layer is dragged (see Stage's drag preview).
	const dragKey = "yoshida.dragPreview";
	let dragPreview = $state<DragPreview>(
		loadPref(dragKey, { mode: "live" as string }).mode === "fast"
			? "fast"
			: "live",
	);

	function setDragPreview(m: DragPreview) {
		dragPreview = m;
		savePref(dragKey, { mode: m });
	}

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
		sizes.preview === null
			? null
			: clamp(sizes.preview, 260, sideRoom - 200),
	);
	const filesW = $derived(
		clamp(sizes.files, 200, sideRoom - (previewW ?? 320)),
	);
	/** The problems panel leaves the stage (or editor) at least 240px plus the top bar. */
	const bottomMax = $derived(Math.max(60, winH - 320));
	const bottomH = $derived(
		clamp(
			mode === "build" ? sizes.bottom : sizes.codeBottom,
			60,
			bottomMax,
		),
	);
	let appEl: HTMLDivElement | undefined = $state();
	/** Current size of a grid area, for a splitter that starts dragging. */
	function areaSize(sel: string, axis: "x" | "y") {
		const el = appEl?.querySelector(sel) as HTMLElement | null;
		if (!el) return 0;
		const r = el.getBoundingClientRect();
		return axis === "x" ? r.width : r.height;
	}

	const fileList = $derived(
		[...files.keys()].filter((p) => !isKeep(p)).sort(),
	);
	const imageFiles = $derived(fileList.filter(isImage));
	const fontFiles = $derived(
		fileList.filter((f) => /\.(ttf|otf|ttc)$/i.test(f)),
	);
	// CSS font-family of each project font, loaded from its bytes for previews.
	let fontFaces = $state<Record<string, string | null>>({});
	$effect(() => {
		for (const p of fontFiles) {
			const data = files.get(p);
			if (!data) continue;
			previewFace(data).then((name) => {
				if (fontFaces[p] !== name) fontFaces = { ...fontFaces, [p]: name };
			});
		}
	});
	// License tag of each project font: "" when no license file is next to it.
	const fontLicenses = $derived(
		Object.fromEntries(
			fontFiles.map((p) => {
				const lp = findLicense(files, p);
				const kind = lp ? licenseKind(textOf(files.get(lp)!)) : "";
				const tags: Record<string, string> = {
					OFL: "OFL",
					APACHE2: "Apache",
					UFL: "UFL",
					restricted: "limited",
					other: "license",
				};
				return [p, kind ? tags[kind] : ""];
			}),
		),
	);
	const sets = $derived(check?.project.sets ?? []);
	const currentSet = $derived(sets.find((s) => s.name === setName));
	const currentCard = $derived(currentSet?.cards[cardIndex]);

	// Card review (qa.json): the status of each card of the current set. An
	// approval is stale once the card or the design inputs hash differently.
	// Reviews follow renamed and moved cards (`reconcileQa`); the file is
	// brought up to date with the next review that is recorded.
	const qaSets = $derived(
		sets.map((s) => {
			const inputs = designFingerprint(files, s.design);
			return {
				key: s.cards_file ?? s.name,
				cards: s.cards.map((c) => ({
					id: c.id,
					hash: cardHash(c, inputs),
					content: contentHash(c, inputs),
				})),
			};
		}),
	);
	const qaDoc = $derived(
		reconcileQa(
			parseQa(files.has(QA_FILE) ? textOf(files.get(QA_FILE)!) : undefined),
			qaSets,
		),
	);
	const qaKey = $derived(currentSet?.cards_file ?? currentSet?.name ?? "");
	const qaHashes = $derived(
		qaSets.find((s) => s.key === qaKey)?.cards.map((c) => c.hash) ?? [],
	);
	const qaContent = $derived(
		qaSets.find((s) => s.key === qaKey)?.cards.map((c) => c.content) ?? [],
	);
	const qaStatuses = $derived(
		(currentSet?.cards ?? []).map((c, i) =>
			statusOf(qaDoc.cards[qaKey]?.[c.id], qaHashes[i]),
		),
	);
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
	/** Same identity as the Problems list uses to show a problem once. */
	const diagnosticKey = (d: Diagnostic) =>
		[d.severity, d.code, d.file, d.path, d.line, d.col, d.message].join("\u0000");
	// The project check covers every file; the preview render adds what the
	// current card reports on top of it.
	// Error codes that showed up, counted once per session and code (advanced telemetry).
	$effect(() => {
		for (const d of check?.diagnostics ?? [])
			if (d.severity === "error")
				trackOnce("error", String(d.code).padStart(4, "0"));
	});

	const diagnostics: Diagnostic[] = $derived.by(() => {
		const seen = new Set<string>();
		const out: Diagnostic[] = [];
		for (const d of [
			...(check?.diagnostics ?? []),
			...(lastRender?.diagnostics ?? []),
		]) {
			const key = diagnosticKey(d);
			if (seen.has(key)) continue;
			seen.add(key);
			out.push(d);
		}
		return out;
	});
	/** Errors and warnings per file, for the Files tab. Hints do not count. */
	const fileProblems = $derived.by(() => {
		const m = new Map<string, { errors: number; warnings: number }>();
		for (const d of diagnostics) {
			if (!d.file || d.severity === "hint") continue;
			const c = m.get(d.file) ?? { errors: 0, warnings: 0 };
			if (d.severity === "error") c.errors++;
			else c.warnings++;
			m.set(d.file, c);
		}
		return m;
	});
	const fileDiagnostics = $derived(
		diagnostics.filter((d) => d.file === selected),
	);
	const selectedText = $derived(
		selected && isText(selected)
			? textOf(files.get(selected) ?? new Uint8Array())
			: "",
	);
	const imageUrl = $derived.by(() => {
		if (!selected || !isPicture(selected)) return "";
		const data = files.get(selected);
		return data ? pictureUrl(selected, data) : "";
	});
	$effect(() => {
		const u = imageUrl;
		return () => u && URL.revokeObjectURL(u);
	});

	// The design the builder edits: the current set's, else the first one.
	const designPath = $derived(
		currentSet?.design ??
			fileList.find((p) => p.endsWith(".design.json")) ??
			null,
	);
	const designText = $derived(
		designPath && files.has(designPath)
			? textOf(files.get(designPath)!)
			: "",
	);
	const readText: ReadText = (p) => {
		const d = files.get(p);
		return d ? textOf(d) : undefined;
	};
	const rawParsed = $derived.by((): { doc: Obj | null; error: string } => {
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
	// The component files the design includes, as one string: the design is
	// only filled in again when one of them changes, not on every file edit.
	const includeTexts = $derived.by(() => {
		const d = rawParsed.doc;
		const out: Record<string, string> = {};
		if (d)
			for (const p of includedPaths(d, readText)) {
				const t = readText(p);
				if (t !== undefined) out[p] = t;
			}
		return JSON.stringify(out);
	});
	// The builder works on the design with its components filled in: a group
	// with "include" also has the component's layers (see lib/components.ts).
	const parsed = $derived.by((): { doc: Obj | null; error: string } => {
		const d = rawParsed.doc;
		if (!d) return rawParsed;
		const texts = JSON.parse(includeTexts) as Record<string, string>;
		return { doc: expandIncludes(d, (p) => texts[p]), error: "" };
	});
	const doc = $derived(parsed.doc);
	/** Component files of the project, for including one. */
	const componentFiles = $derived(
		fileList.filter((p) => isComponentFile(p, readText(p))),
	);
	/** The layer a problem belongs to: one of the design, or one inside an included component. */
	function diagnosticLayer(d: Diagnostic): string | null {
		if (!doc || !d.file) return null;
		if (d.file === designPath) return layerAtPointer(doc, d.path);
		const g = layersOf(doc).find(
			(l) => includeOf(l) === d.file && Array.isArray(l.layers),
		);
		return g ? (layerAtPointer(g, d.path) ?? String(g.id)) : null;
	}
	const canvasSize = $derived.by(() => {
		if (image && imageSize) return imageSize;
		const w =
			literalNumber(getPath(doc ?? undefined, ["canvas", "width"])) ??
			1000;
		const h =
			literalNumber(getPath(doc ?? undefined, ["canvas", "height"])) ??
			1400;
		return { w, h };
	});
	const layerProblems = $derived.by(() => {
		const m = new Map<string, "error" | "warning">();
		if (!doc || !Array.isArray(doc.layers)) return m;
		for (const d of diagnostics) {
			if (d.severity === "hint") continue;
			const id = diagnosticLayer(d);
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
		channel = engine.channel;
		examples = await listExamples();
		try {
			const res = await fetch("api/capabilities");
			if (
				res.ok &&
				(res.headers.get("content-type") ?? "").includes("json")
			)
				server = await res.json();
		} catch {
			server = null;
		}
		// A server that raised its limits (YOSHIDA_MAX_LAYERS and the others):
		// the editor's own engine follows, so both accept the same designs.
		if (server?.limits && typeof server.limits === "object") {
			try {
				// A plain copy: the state proxy cannot be posted to the worker.
				const allowed = $state.snapshot(server.limits) as CoreLimits;
				setMaxSide((await engine.setLimits(allowed)).canvas);
			} catch {
				// An engine without the request keeps its defaults.
			}
		}
		// Without a yoshida server there is nothing to send to: no notice, no requests.
		initTelemetry(server?.telemetry);
		myProjects = await listProjects();
		const last = lastProject();
		if (last && (await openSaved(last))) return;
		const first = examples.find((e) => e.name === "poker") ?? examples[0];
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
		link: FolderLink | null = null,
		id: string | null = null,
		saved = false,
		sigs: Sigs = new Map(),
	) {
		loading = { name, step: 0, label: loadSteps[0] };
		projectName = name;
		projectId = id;
		savedFiles = saved ? f : null;
		saveState = saved ? "saved" : id ? "unsaved" : "idle";
		if (id) setLastProject(id);
		files = f;
		dirty = new Set();
		folder = link;
		folderSigs = sigs;
		folderNotice = null;
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
		try {
			await engine.setFiles(f);
		} catch (e) {
			loading = null;
			throw e;
		}
		selected =
			fileList.find((p) => p.endsWith(".design.json")) ??
			fileList[0] ??
			null;
		if (link && id) persistFolder();
		await refresh();
	}

	async function openExample(name: string) {
		const ex = examples.find((e) => e.name === name);
		if (!ex) return;
		track("feature", "example.open");
		status = `Loading ${ex.title}…`;
		await openProject(ex.name, await loadExample(ex));
	}

	async function openSaved(id: string): Promise<boolean> {
		try {
			const p = await loadProject(id);
			if (!p) return false;
			await openProject(p.meta.name, p.files, null, id, true);
			await reopenFolder(id);
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
		const backend = activeBackend();
		if (backend) {
			try {
				const link = await backend.pick();
				const { files: f, sigs } = await link.read();
				await openProject(link.name, f, link, newProjectId(), false, sigs);
			} catch (e) {
				if ((e as Error).name !== "AbortError")
					status = `Could not open the folder: ${(e as Error).message}`;
			}
			return;
		}
		await openFolderCopy();
	}

	/**
	 * Copies a folder into the project in this browser (the browser's upload
	 * dialog): the folder on disk is not linked and never written to.
	 */
	async function openFolderCopy() {
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
		track("feature", "project.export");
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
		if (document.visibilityState === "visible") checkFolder();
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
		// A linked project: the folder on disk is not touched, only the copy in
		// this browser and the link to the folder go.
		let linked: string | null = null;
		if (meta.id === projectId && folder) linked = folder.name;
		else {
			const rec = await loadFolder(meta.id).catch(() => null);
			if (rec) {
				try {
					linked = backendById(rec.backend)?.open(rec.ref).name ?? "a folder";
				} catch {
					linked = "a folder";
				}
			}
		}
		const ok = await confirmAction({
			title: `Delete '${meta.name}' from this browser?`,
			message: linked
				? `Its copy (images included) and the link to the folder '${linked}' are removed from this browser. The files in that folder stay exactly as they are: nothing on disk is deleted, and you can open the folder again later with Open folder…`
				: "Its files (images included) are removed from this browser. Export it as a .yoshida file first if you want to keep it.",
			confirm: "Delete",
			danger: true,
		});
		if (!ok) return;
		await deleteProject(meta.id);
		myProjects = await listProjects();
		if (meta.id === projectId) {
			await closeProject();
			status = `Deleted '${meta.name}' from this browser. Open a project to continue.`;
		}
	}

	/** Leaves the open project: the editor goes back to "No project". */
	async function closeProject() {
		projectName = "";
		projectId = null;
		savedFiles = null;
		saveState = "idle";
		files = new Map();
		dirty = new Set();
		folder = null;
		folderSigs = new Map();
		folderNotice = null;
		lastRender = null;
		check = null;
		setName = "";
		cardIndex = 0;
		selected = null;
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
		await engine.setFiles(files);
		await refresh();
	}

	function projectMenu(e: MouseEvent) {
		const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
		const current = myProjects.find((p) => p.id === projectId);
		const open = !!files.size;
		const items: MenuItem[] = [
			{ heading: "Start" },
			{ label: "New project…", icon: "plus", action: newProject },
			{
				label: "Open folder…",
				icon: "folder",
				detail: activeBackend()
					? "edit the files on disk in place"
					: "copies it into this browser",
				action: openFolder,
			},
			...(activeBackend()
				? [
						{
							label: "Open folder as a copy…",
							icon: "upload",
							detail: "upload it, the folder is left alone",
							action: openFolderCopy,
						} satisfies MenuItem,
					]
				: []),
			{
				label: "Open project file…",
				icon: "file",
				detail: ".yoshida",
				action: openProjectFile,
			},
			{ separator: true },
			{ heading: "This project" },
			{
				label: "New design…",
				icon: "design",
				detail: "with its own card file",
				disabled: !projectName,
				action: newDesign,
			},
			{
				label: "Add set…",
				icon: "table",
				detail: "a card file for a design, in the manifest",
				disabled: !projectName,
				action: () => addSet(),
			},
			{
				label: "Fonts…",
				icon: "text",
				detail: "preview, upload, Google Fonts",
				disabled: !projectName || !doc,
				action: () => openFonts(),
			},
			{
				label: "Add files…",
				icon: "files",
				detail: uploadFolder
					? `to ${uploadFolder}/`
					: "images, fonts, data",
				disabled: !projectName,
				action: addFiles,
			},
			folder
				? {
						label: `Unlink from ${folder.name}`,
						icon: "folder",
						detail: "keeps the files, stops writing to them",
						action: unlinkFolder,
					}
				: {
						label: "Link to folder…",
						icon: "folder",
						detail: activeBackend()
							? "edit the files on disk, saved as you work"
							: "not available in this browser, click to see why",
						disabled: !open,
						action: linkFolder,
					},
			...(folder
				? [
						{
							label: "Reload from folder",
							icon: "folder",
							detail: "after changes outside the editor",
							action: reloadFromFolder,
						} satisfies MenuItem,
					]
				: []),
			{
				label: "Export project file",
				icon: "download",
				detail: ".yoshida, with images and fonts",
				disabled: !open,
				action: exportProject,
			},
			{
				label: "Project settings…",
				detail: "UTC offset for render time",
				disabled: !open,
				action: openSettings,
			},
			{
				label: "Rename…",
				icon: "pencil",
				disabled: !open,
				action: renameProject,
			},
		];
		if (current)
			items.push({
				label: "Delete from this browser…",
				icon: "trash",
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
				icon: p.id === projectId ? "check" : undefined,
				detail: `${formatAge(p.updated)} · ${formatSize(p.size)}`,
				action: () =>
					p.id === projectId ? undefined : openSaved(p.id),
			});
		items.push({ separator: true }, { heading: "Examples" });
		for (const ex of examples)
			items.push({
				label: ex.title,
				icon: !projectId && ex.name === projectName ? "check" : undefined,
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
				message:
					"Starts an empty project with a manifest, one design and one card file.",
				value: "My cards",
				confirm: "Create",
				validate: needName,
			})
		)?.trim();
		if (!name) return;
		const stem = slug(name);
		const f: Files = newProjectFiles(name, stem);
		openProject(stem, f, null, newProjectId()).then(() => {
			dirty = new Set(f.keys());
			mode = "build";
		});
	}

	/** Value of the "New design…" command row in the DESIGN picker. */
	const newDesignOption = "\u0000new-design";

	/** Adds a blank design with its own card file to the open project. */
	async function newDesign() {
		track("feature", "design.new");
		const name = (
			await askText({
				title: "New design",
				message:
					"Adds a blank design and its own card file to this project.",
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

	/** The design's own defaults, keyed by param name (params without one are left out). */
	function sampleCard(params: Param[]): Record<string, unknown> {
		const card: Record<string, unknown> = {};
		for (const p of params)
			if (p.default !== undefined) card[p.name] = p.default;
		return card;
	}

	/**
	 * Adds a card file for a design to the open project and switches to it.
	 * Without a design, a menu asks which design it is for.
	 */
	async function newCardFile(
		design?: string,
		at?: { x: number; y: number },
		asSet = false,
	) {
		const named = new Map<string, string>();
		for (const s of sets)
			if (!named.has(s.design))
				named.set(s.design, s.design_name || baseOf(s.design));
		if (!named.size) return;
		if (!design) {
			const pos = at ?? {
				x: window.innerWidth / 2,
				y: window.innerHeight / 3,
			};
			const items: MenuItem[] = [{ heading: "Design" }];
			for (const [path, label] of named)
				items.push({
					label,
					icon: "design",
					detail: path,
					action: () => newCardFile(path, undefined, asSet),
				});
			openMenu(pos.x, pos.y, items);
			return;
		}
		if (!files.has(design)) return;
		const label = named.get(design) ?? baseOf(design);
		const name = (
			await askText({
				title: asSet ? "Add set" : "New card file",
				message: asSet
					? `Adds a set for ${label}: a card file listed in ${MANIFEST}.`
					: `Adds a card file for ${label}.`,
				value: `${label} cards`,
				confirm: asSet ? "Add set" : "Add card file",
				validate: needName,
			})
		)?.trim();
		if (!name) return;
		let stem = slug(name);
		for (let n = 2; files.has(`cards/${stem}.cards.json`); n++)
			stem = `${slug(name)}-${n}`;
		const cards = `cards/${stem}.cards.json`;
		const params = sets.find((x) => x.design === design)?.params ?? [];
		await updateFile(cards, blankCards(design, name, sampleCard(params)));
		if (asSet) {
			track("feature", "set.add");
			try {
				await updateFile(
					MANIFEST,
					withSet(manifestText(), { name: stem, design, cards }),
					true,
				);
			} catch (e) {
				status = `Could not update ${MANIFEST}: ${(e as Error).message}`;
			}
		}
		await refresh();
		const s = sets.find((x) => x.cards_file === cards);
		if (s) {
			setName = s.name;
			cardIndex = 0;
			await renderPreview();
		}
	}

	/** Adds a set (a card file for a design, listed in the manifest). */
	const addSet = (at?: { x: number; y: number }) =>
		newCardFile(undefined, at, true);

	/**
	 * Stem for a new card file of a design: the design's file name without
	 * ".design.json", kept as is when it is plain, else slugged; a number is
	 * added when the name is taken.
	 */
	function sampleStem(design: string): string {
		const base = baseOf(design).replace(/\.design\.json$/i, "");
		const first = /^[a-z0-9_-]+$/i.test(base) ? base : slug(base);
		let stem = first;
		for (let n = 2; files.has(`cards/${stem}.cards.json`); n++)
			stem = `${first}-${n}`;
		return stem;
	}

	/** Where "Create card file" writes for the open design, when it has no card file. */
	const sampleCardsPath = $derived(
		currentSet && !currentSet.cards_file
			? `cards/${sampleStem(currentSet.design)}.cards.json`
			: undefined,
	);

	/** Writes one sample card (the design's defaults) for the open design, without a dialog. */
	async function createSampleCards() {
		const set = currentSet;
		if (!set || set.cards_file) return;
		const stem = sampleStem(set.design);
		const cards = `cards/${stem}.cards.json`;
		await updateFile(
			cards,
			blankCards(set.design, set.design_name || stem, sampleCard(set.params)),
		);
		await refresh();
		const s = sets.find((x) => x.cards_file === cards);
		if (s) {
			setName = s.name;
			cardIndex = 0;
			await renderPreview();
		}
		status = `Created ${cards} with one sample card.`;
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
				folder !== null
					? join(folder, baseOf(f.name))
					: importPath(f.name);
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
	const fileUsedBy = $derived(usedBy(files));
	const fileUses = $derived(
		new Map([...fileUsedBy].map(([p, by]) => [p, by.length])),
	);

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
		if (selected && renames.has(selected))
			selected = renames.get(selected)!;
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
			![...files.keys()].some(
				(p) => p.startsWith(`${dir}/`) && !gone.includes(p),
			)
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
		if (!p || !isPicture(p)) return "";
		const d = files.get(p);
		return d ? pictureUrl(p, d) : "";
	});
	$effect(() => {
		const u = filesPreviewUrl;
		return () => u && URL.revokeObjectURL(u);
	});
	const isSvg = (path: string) => /\.svg$/i.test(path);
	/** Sample text for a font preview. */
	const fontSample = "The quick brown fox jumps over the lazy dog";
	/** Pixel size of the previewed image, once the browser has decoded it. */
	let filesPreviewSize = $state<{ url: string; w: number; h: number } | null>(
		null,
	);
	/** What the selected file is, e.g. "Card data, 40 cards"; images show their pixel size instead. */
	const filesSelectedKind = $derived.by(() => {
		const p = filesSelected;
		const d = p ? files.get(p) : undefined;
		if (!p || !d) return "";
		// An SVG has no pixel size of its own; it is drawn at the size it is used at.
		if (filesPreviewUrl && !isSvg(p)) {
			const s = filesPreviewSize;
			return s?.url === filesPreviewUrl ? `${s.w} × ${s.h} px` : "Image";
		}
		return describeFile(p, d);
	});

	// ---------------------------------------------------------------- card browser

	let browsing = $state(false);

	// ---------------------------------------------------------------- fonts window

	let fontsTarget = $state<FontsTarget | null>(null);

	/** The design's own functions, for the Functions window. */
	const designFunctions = $derived.by(() => {
		const fns = doc && isObj(doc.functions) ? doc.functions : {};
		return Object.entries(fns)
			.filter(([, f]) => isObj(f))
			.map(([name, f]) => {
				const fn = f as { args?: unknown; expr?: unknown; note?: unknown };
				const args = isObj(fn.args)
					? Object.entries(fn.args)
							.map(([a, t]) => `${a}: ${t}`)
							.join(", ")
					: "";
				const note = typeof fn.note === "string" ? fn.note : undefined;
				return { name, args, expr: String(fn.expr ?? ""), note };
			});
	});

	/** The selected text layer, for the Fonts window's preview and "use". */
	const fontLayer = $derived.by(() => {
		if (!doc || !selectedLayer) return null;
		const l = effectiveLayer(doc, selectedLayer);
		if (l?.type !== "text") return null;
		const values: Record<string, unknown> = {};
		for (const p of currentSet?.params ?? []) values[p.name] = p.default;
		const text = previewTextOf(String(l.text ?? ""), { ...values, ...currentCard?.values });
		return { id: selectedLayer, font: String(l.font ?? "default"), text };
	});

	function openFonts(target: FontsTarget = {}) {
		track("feature", "fonts.open");
		fontsTarget = { ...target };
	}

	// Project settings (the manifest's utc_offset).
	let settingsOpen = $state(false);
	let offsetText = $state("");
	let offsetError = $state("");

	function manifestText(): string | undefined {
		const d = files.get(MANIFEST);
		return d ? textOf(d) : undefined;
	}

	function openSettings() {
		offsetText = String(utcOffsetOf(manifestText()));
		offsetError = "";
		settingsOpen = true;
	}

	/** Writes utc_offset into yoshida.json (left out when 0). */
	async function setUtcOffset(hours: number) {
		const before = manifestText();
		// No manifest and no offset: nothing to write.
		if (before === undefined && hours === 0) return;
		try {
			const text = withUtcOffset(before, hours);
			offsetError = "";
			offsetText = hours ? String(hours) : "";
			await updateFile(MANIFEST, text, true);
			status = hours
				? `UTC offset set to ${hours} hours.`
				: "UTC offset removed (0 hours).";
		} catch (e) {
			offsetError = `Could not update ${MANIFEST}: ${(e as Error).message}`;
		}
	}

	/** Returns false, with the error shown, when raw is not a usable offset. */
	function offsetEntered(raw: string): boolean {
		const t = raw.trim();
		const v = t === "" ? 0 : Number(t);
		if (!Number.isFinite(v) || Math.abs(v) > UTC_OFFSET_LIMIT) {
			offsetError = `Enter a number from -${UTC_OFFSET_LIMIT} to ${UTC_OFFSET_LIMIT}.`;
			return false;
		}
		setUtcOffset(v);
		return true;
	}

	/**
	 * Adds font and license files, declares font names in the design and
	 * switches the selected text layer to `use`, all as one undo step.
	 */
	async function applyFonts(
		add: FontAdd[],
		declare: Record<string, string>,
		use: string | null,
	) {
		const changes: Snapshot = add.map((a) => ({ path: a.path, data: a.data }));
		if (designPath && doc && (Object.keys(declare).length || use)) {
			const next = clone(doc);
			if (Object.keys(declare).length) {
				const fonts: Record<string, Json> = isObj(next.fonts)
					? next.fonts
					: {};
				// A name already declared for the same file keeps its note.
				for (const [n, path] of Object.entries(declare))
					if (fontEntryPath(fonts[n]) !== path) fonts[n] = path;
				next.fonts = fonts;
			}
			if (use && selectedLayer) {
				const l = findLayer(next, selectedLayer);
				if (l) l.font = use;
			}
			for (const c of docChanges(next))
				changes.push({ path: c.path, data: bytesOf(c.text) });
		}
		if (!changes.length) return;
		recordMany(changes.map((c) => snap(c.path)));
		await writeFiles(changes);
	}
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
					...renderClock(),
					preview: true,
					format: "png",
					// Tiles are at most 320 x 448 screen pixels.
					scale: thumbScale(canvasSize, 448 * dpr()),
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

	// ---------------------------------------------------------------- linked folder
	//
	// A project can be linked to a folder on disk (lib/folder): every change
	// is written there as it happens, and changes made outside the editor (a
	// git pull, another editor) are noticed and offered for reload. The link
	// is kept in this browser, so a reload only asks for access again.

	/** Remembers the link and the last sync for the next visit. */
	async function persistFolder() {
		const link = folder;
		const id = projectId;
		if (!link || !id) return;
		try {
			await saveFolder(id, {
				backend: link.backend,
				ref: link.ref,
				sigs: [...folderSigs],
			});
		} catch {
			// Not stored: the link works until the page is closed.
		}
	}

	/** Reconnects the folder a saved project was linked to, if it had one. */
	async function reopenFolder(id: string) {
		const rec = await loadFolder(id);
		const backend = rec && backendById(rec.backend);
		if (!rec || !backend || id !== projectId) return;
		const link = backend.open(rec.ref);
		folder = link;
		folderSigs = new Map(rec.sigs);
		try {
			if ((await link.permission()) !== "granted")
				folderNotice = { kind: "permission" };
			else await reconcileFolder();
		} catch (e) {
			folderNotice = { kind: "error", message: (e as Error).message };
		}
	}

	/**
	 * Compares the project with the folder after a reconnect: it is left alone
	 * when equal, written out when only the project changed, and the user
	 * chooses when both did.
	 */
	async function reconcileFolder() {
		const link = folder;
		if (!link) return;
		const { files: onDisk, sigs } = await link.read();
		const plan = planReconnect(files, onDisk, sigs, folderSigs);
		if (link !== folder) return;
		if (plan.kind === "ask") {
			folderNotice = { kind: "conflict", diff: plan.diff };
			return;
		}
		folderSigs = plan.sigs;
		if (plan.kind === "push") markForWrite(plan.diff);
		persistFolder();
	}

	function markForWrite(d: { onlyMine: string[]; onlyTheirs: string[]; differ: string[] }) {
		dirty = new Set([...dirty, ...d.onlyMine, ...d.onlyTheirs, ...d.differ]);
	}

	/** Asks for access to the folder again (needs a click). */
	async function allowFolder() {
		const link = folder;
		if (!link) return;
		try {
			if ((await link.permission(true)) !== "granted") {
				status = `No access to ${link.name}. Allow it, or unlink the folder.`;
				return;
			}
			folderNotice = null;
			await reconcileFolder();
		} catch (e) {
			folderNotice = { kind: "error", message: (e as Error).message };
		}
	}

	/** Links the open project to a folder the user picks. */
	async function linkFolder() {
		const backend = activeBackend();
		if (!files.size) return;
		if (!backend) {
			await confirmAction({
				title: "This browser cannot link a folder",
				message:
					"Linking needs the File System Access API: Chrome, Edge and other Chromium browsers have it. Brave has it switched off: open brave://flags/#file-system-access-api, set it to Enabled and restart Brave. Firefox and Safari do not have it; use Export project file there.",
				confirm: "OK",
			});
			return;
		}
		try {
			const link = await backend.pick();
			const { files: onDisk, sigs } = await link.read();
			const diff = diffFiles(files, onDisk);
			if (diff.differ.length) {
				const ok = await confirmAction({
					title: `Link to '${link.name}'?`,
					message: `${diff.differ.length} file(s) in the folder are replaced by this project's version. ${
						diff.onlyTheirs.length
							? `${diff.onlyTheirs.length} file(s) that exist only in the folder are added to the project. `
							: ""
					}Nothing else in the folder is deleted.`,
					confirm: "Link and overwrite",
					danger: true,
				});
				if (!ok) return;
			}
			if (folder) await unlinkFolder();
			projectId ??= newProjectId();
			if (diff.onlyTheirs.length) {
				const next = new Map(files);
				for (const p of diff.onlyTheirs) {
					const d = onDisk.get(p) as Uint8Array;
					next.set(p, d);
					await engine.put(p, d);
				}
				files = next;
			}
			folder = link;
			folderSigs = sigs;
			folderNotice = null;
			markForWrite({ onlyMine: diff.onlyMine, onlyTheirs: [], differ: diff.differ });
			await saveInBrowser();
			await persistFolder();
			status = `Linked to ${link.name}: changes are saved there as you work.`;
			if (diff.onlyTheirs.length) await refresh();
		} catch (e) {
			if ((e as Error).name !== "AbortError")
				status = `Could not link the folder: ${(e as Error).message}`;
		}
	}

	/** Stops writing to the folder. Its files and the project's both stay as they are. */
	async function unlinkFolder() {
		const link = folder;
		if (!link) return;
		await flushFolder();
		folder = null;
		folderSigs = new Map();
		folderNotice = null;
		if (projectId) await deleteFolder(projectId).catch(() => {});
		status = `Unlinked from ${link.name}. The project stays in this browser.`;
	}

	/** Replaces the project's files with what is in the folder now. */
	async function reloadFromFolder() {
		const link = folder;
		if (!link) return;
		try {
			if ((await link.permission(true)) !== "granted") {
				folderNotice = { kind: "permission" };
				return;
			}
			const { files: f, sigs } = await link.read();
			if (link !== folder) return;
			files = f;
			dirty = new Set();
			folderSigs = sigs;
			folderNotice = null;
			undoStack = [];
			redoStack = [];
			if (filesSelected && !f.has(filesSelected)) filesSelected = null;
			await engine.setFiles(f);
			if (!selected || !f.has(selected))
				selected =
					fileList.find((p) => p.endsWith(".design.json")) ??
					fileList[0] ??
					null;
			await refresh();
			persistFolder();
			status = `Reloaded ${f.size} file(s) from ${link.name}.`;
		} catch (e) {
			folderNotice = { kind: "error", message: (e as Error).message };
		}
	}

	/** Keeps the project's version of the files the folder changed. */
	function keepProjectVersion() {
		const n = folderNotice;
		if (n?.kind === "changed") {
			folderSigs = n.sigs;
			// Files that were added outside the editor are left alone.
			dirty = new Set([...dirty, ...n.paths.filter((p) => files.has(p))]);
			folderNotice = null;
			persistFolder();
		} else if (n?.kind === "conflict") {
			// Files that exist only in the folder are not deleted.
			markForWrite({ ...n.diff, onlyTheirs: [] });
			folderNotice = null;
			// The folder's fingerprints are taken again so that the write
			// below is not mistaken for an outside change.
			folder?.scan().then((s) => {
				folderSigs = s;
				persistFolder();
			});
		}
	}

	let folderTimer: ReturnType<typeof setTimeout> | undefined;
	let folderFlush: Promise<void> = Promise.resolve();

	/** Writes the changed files to the folder, one flush at a time. */
	function flushFolder(): Promise<void> {
		clearTimeout(folderTimer);
		folderFlush = folderFlush.then(writeToFolder, writeToFolder);
		return folderFlush;
	}

	async function writeToFolder() {
		const link = folder;
		// Writing over a folder that has changed under us would lose those
		// changes, so it waits for the user's answer to a notice.
		if (!link || !dirty.size || (folderNotice && folderNotice.kind !== "error"))
			return;
		const todo = [...dirty].map((p) => [p, files.get(p)] as const);
		try {
			if ((await link.permission()) !== "granted") {
				folderNotice = { kind: "permission" };
				return;
			}
			folderWriting = true;
			const sigs = new Map(folderSigs);
			for (const [p, d] of todo) {
				if (d) sigs.set(p, await link.write(p, d));
				else {
					await link.remove(p);
					sigs.delete(p);
				}
			}
			if (link !== folder) return;
			folderSigs = sigs;
			// A file edited again while it was being written stays pending.
			const rest = new Set(dirty);
			for (const [p, d] of todo) if (files.get(p) === d) rest.delete(p);
			dirty = rest;
			if (folderNotice?.kind === "error") folderNotice = null;
			persistFolder();
		} catch (e) {
			folderNotice = { kind: "error", message: (e as Error).message };
		} finally {
			folderWriting = false;
		}
	}

	// Writes shortly after a change, so typing is not one write per key.
	$effect(() => {
		if (!folder || !dirty.size || (folderNotice && folderNotice.kind !== "error"))
			return;
		clearTimeout(folderTimer);
		folderTimer = setTimeout(flushFolder, 500);
		return () => clearTimeout(folderTimer);
	});

	/** Looks for changes made outside the editor. */
	async function checkFolder() {
		const link = folder;
		if (
			!link ||
			folderNotice ||
			folderWriting ||
			dirty.size ||
			document.visibilityState !== "visible"
		)
			return;
		const known = folderSigs;
		try {
			if ((await link.permission()) !== "granted") {
				folderNotice = { kind: "permission" };
				return;
			}
			const found = await findExternalChanges(link, files, known);
			// Edited, written or switched while scanning: the next check sees it.
			if (!found || link !== folder || known !== folderSigs || dirty.size) return;
			if (found.changed.length)
				folderNotice = { kind: "changed", paths: found.changed, sigs: found.sigs };
			else {
				folderSigs = found.sigs;
				persistFolder();
			}
		} catch {
			// A file may be half written (a git checkout): the next check tries again.
		}
	}

	$effect(() => {
		if (!folder) return;
		const t = setInterval(checkFolder, 3000);
		return () => clearInterval(t);
	});

	const folderNoticeText = $derived.by(() => {
		const n = folderNotice;
		const name = folder?.name ?? "";
		if (!n) return "";
		if (n.kind === "permission")
			return `The browser needs your permission to use the folder '${name}' again.`;
		if (n.kind === "changed") {
			const shown = n.paths.slice(0, 3).join(", ");
			return `${n.paths.length} file(s) in '${name}' changed outside the editor (${shown}${n.paths.length > 3 ? ", …" : ""}).`;
		}
		if (n.kind === "conflict")
			return `'${name}' differs from this project: ${diffCount(n.diff)} file(s). They changed while the project was closed.`;
		return `Could not write to '${name}': ${n.message}`;
	});

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
			loadStep(1);
			check = await engine.check();
			loadStep(2);
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
			} else loading = null;
		}
	}

	/** Puts a rendered picture (drawn at `scale`) on the stage; returns the canvas size. */
	function showPicture(r: RenderResult, scale: number) {
		shownScale = scale;
		const size = {
			w: r.canvas_width || r.width,
			h: r.canvas_height || r.height,
		};
		imageSize = size;
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
		return size;
	}

	async function renderPreview() {
		if (!currentSet?.cards.length) {
			lastRender = null;
			stale = !!image;
			status = sets.length
				? "This set has no cards."
				: "No designs found.";
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
		const scale = wantedScale;
		const r = await engine.render({
			set: setName,
			card: cardIndex,
			...renderClock(),
			preview: true,
			format: "rgba",
			layout: true,
			scale,
		});
		renderMs = Math.round(performance.now() - t0);
		renderScale = scale;
		lastRender = r;
		if (gestureBase !== null) {
			// A drag started while this render ran: its picture and layout are
			// older than what the stage shows. The release renders again.
			previewSkipped = true;
			return;
		}
		if (r.width) {
			const size = showPicture(r, scale);
			dragSprite = null;
			status =
				`${size.w} × ${size.h} px` +
				(scale < 1 ? ` (preview at ${r.width} × ${r.height})` : "") +
				`, rendered in ${renderMs} ms`;
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
		undoStack = [
			...undoStack.slice(-199),
			[{ path, data: bytesOf(before) }],
		];
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

	function writeQaDoc(next: QaDoc) {
		const before = currentText(QA_FILE);
		const text = writeQa(next);
		if (text === before) return;
		record(QA_FILE, before);
		updateFile(QA_FILE, text, true);
	}

	// Reviewer name: kept in this browser, written next to marks and comments.
	const reviewerKey = "yoshida.reviewer";
	let reviewer = $state(
		(() => {
			try {
				return localStorage.getItem(reviewerKey) ?? "";
			} catch {
				return "";
			}
		})(),
	);
	function setReviewer(name: string) {
		reviewer = name.trim().slice(0, 60);
		try {
			if (reviewer) localStorage.setItem(reviewerKey, reviewer);
			else localStorage.removeItem(reviewerKey);
		} catch {
			// The name just is not remembered.
		}
	}
	const stamp = () => ({ ...(reviewer ? { by: reviewer } : {}), at: stampNow() });

	const qaEntry = $derived(
		currentCard ? qaDoc.cards[qaKey]?.[currentCard.id] : undefined,
	);
	/** The comment shown highlighted, and the one waiting for a click on the card to be pinned. */
	let qaActive = $state<string | null>(null);
	let pinTarget = $state<string | null>(null);
	let qaComposer = $state<HTMLInputElement>();
	let qaOverviewOpen = $state(false);
	let qaKeysOpen = $state(false);
	// The comments belong to a card: another card starts clean.
	$effect(() => {
		void currentCard?.id;
		void setName;
		qaActive = null;
		pinTarget = null;
	});

	function reviewCard(mark: QaMark | null) {
		const c = currentCard;
		if (!c) return;
		if (mark === "approved" && openComments(qaEntry).length) {
			status = "Resolve the open comments before approving.";
			return;
		}
		writeQaDoc(
			withMark(
				qaDoc,
				qaKey,
				c.id,
				mark,
				qaHashes[cardIndex],
				stamp(),
				qaContent[cardIndex],
			),
		);
	}

	function addComment(text: string) {
		const c = currentCard;
		if (!c) return;
		const r = withComment(qaDoc, qaKey, c.id, qaHashes[cardIndex], {
			text,
			content: qaContent[cardIndex],
			...stamp(),
		});
		writeQaDoc(r.doc);
		qaActive = r.id;
	}

	function editComment(
		id: string,
		patch: Partial<Pick<QaComment, "text" | "resolved" | "x" | "y">>,
	) {
		if (currentCard)
			writeQaDoc(withCommentEdit(qaDoc, qaKey, currentCard.id, id, patch));
	}

	function removeComment(id: string) {
		if (currentCard)
			writeQaDoc(withoutComment(qaDoc, qaKey, currentCard.id, id));
		if (qaActive === id) qaActive = null;
		if (pinTarget === id) pinTarget = null;
	}

	function placePin(x: number, y: number) {
		if (!pinTarget) return;
		editComment(pinTarget, { x: Math.round(x), y: Math.round(y) });
		qaActive = pinTarget;
		pinTarget = null;
	}

	const qaPins = $derived(
		(qaEntry?.comments ?? []).flatMap((c, i) =>
			c.x === undefined || c.y === undefined
				? []
				: [
						{
							id: c.id,
							n: i + 1,
							x: c.x,
							y: c.y,
							resolved: !!c.resolved,
							active: qaActive === c.id,
						},
					],
		),
	);

	/** Every card with a mark or comments, for the overview. */
	const qaRows = $derived(
		sets.flatMap((s, si) =>
			s.cards.flatMap((c, i) => {
				const e = qaDoc.cards[qaSets[si]?.key]?.[c.id];
				if (!e) return [];
				return [
					{
						set: s.name,
						setLabel: s.design_name,
						index: i,
						id: c.id,
						status: statusOf(e, qaSets[si].cards[i].hash),
						entry: e,
					},
				];
			}),
		),
	);

	/** The card last looked at in each set, so switching designs comes back to it. */
	const lastCard = new Map<string, number>();

	function goToCard(set: string, index: number | null) {
		if (set !== setName) lastCard.set(setName, cardIndex);
		index ??= lastCard.get(set) ?? 0;
		if (set !== setName) {
			setName = set;
			selectedLayers = [];
		}
		cardIndex = index;
		cardIdError = "";
		renderPreview();
	}

	function stepCard(by: number) {
		const n = currentSet?.cards.length ?? 0;
		if (!n) return;
		goToCard(setName, Math.min(n - 1, Math.max(0, cardIndex + by)));
	}

	function stepSet(by: number) {
		if (sets.length < 2) return;
		const i = sets.findIndex((s) => s.name === setName);
		goToCard(sets[(i + by + sets.length) % sets.length].name, null);
	}

	/** The next card, in the sets' order after this one and wrapping round, that still needs review. */
	function nextToReview() {
		const flat = sets.flatMap((s, si) =>
			s.cards.map((c, i) => ({
				set: s.name,
				i,
				st: statusOf(qaDoc.cards[qaSets[si]?.key]?.[c.id], qaSets[si].cards[i].hash),
			})),
		);
		const at = flat.findIndex((x) => x.set === setName && x.i === cardIndex);
		for (let k = 1; k <= flat.length; k++) {
			const x = flat[(at + k) % flat.length];
			if (needsReview(x.st)) {
				goToCard(x.set, x.i);
				return;
			}
		}
		status = "No card needs review.";
	}

	/** The review keys; true when the key was one of them. */
	function reviewKey(e: KeyboardEvent): boolean {
		const k = e.key;
		if (k === "?" || (k === "/" && e.shiftKey)) qaKeysOpen = !qaKeysOpen;
		else if (k === "Escape" && (pinTarget || qaKeysOpen || qaOverviewOpen)) {
			pinTarget = null;
			qaKeysOpen = false;
			qaOverviewOpen = false;
		} else if (!currentCard) return false;
		else if (k === "j") stepCard(1);
		else if (k === "k") stepCard(-1);
		else if (k === "]") stepSet(1);
		else if (k === "[") stepSet(-1);
		else if (k === "a") reviewCard("approved");
		else if (k === "n") reviewCard("needs-changes");
		else if (k === "x") reviewCard(null);
		else if (k === "u") nextToReview();
		else if (k === "o") qaOverviewOpen = !qaOverviewOpen;
		else if (k === "c") queueMicrotask(() => qaComposer?.focus());
		else if (k === "p") {
			const target =
				qaActive ??
				[...(qaEntry?.comments ?? [])].reverse().find((c) => !c.resolved)?.id ??
				null;
			pinTarget = pinTarget || !target ? null : target;
		} else return false;
		return true;
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

	/** Renames an option of a list param's enum item field in the design and in every card. */
	function renameItemOptionEverywhere(
		param: string,
		field: string,
		from: string,
		to: string,
	) {
		editDesignAndCards(
			(d) => renameItemOption(d, param, field, from, to),
			(path, text) =>
				renameItemValueInCards(
					path,
					text,
					param,
					field,
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
		const changes: Snapshot = docChanges(next).map((c) => ({
			path: c.path,
			data: bytesOf(c.text),
		}));
		for (const s of sets) {
			if (
				s.design !== designPath ||
				!s.cards_file ||
				!files.has(s.cards_file)
			)
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
		if (!changes.length) return;
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
		writeDoc(next, key ? `design:${key}` : "");
	}

	type TextChange = { path: string; text: string };

	/**
	 * The files an edited design changes: the design file, and the component
	 * file of each including group whose layers changed. `named` gives a
	 * component file made by this edit its name.
	 */
	function docChanges(
		next: Obj,
		named?: { path: string; name: string },
	): TextChange[] {
		const { design, components } = splitIncludes(next, readText);
		const out: TextChange[] = [];
		const text = formatJson(design);
		if (text !== designText) out.push({ path: designPath!, text });
		for (const [path, c] of components) {
			if (named?.path === path) c.name = named.name;
			out.push({ path, text: formatJson(c) });
		}
		return out;
	}

	/** Writes an edited design as one undo step. False when nothing changed. */
	function writeDoc(
		next: Obj,
		key = "",
		named?: { path: string; name: string },
	): boolean {
		const changes = docChanges(next, named);
		if (!changes.length) return false;
		const only = changes.length === 1 ? changes[0] : null;
		if (only && files.has(only.path)) {
			record(only.path, currentText(only.path), key);
			updateFile(only.path, only.text, true);
		} else {
			recordMany(changes.map((c) => snap(c.path)));
			writeFiles(changes.map((c) => ({ path: c.path, data: bytesOf(c.text) })));
		}
		return true;
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
		track("feature", `layer.add.${type}`);
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
				message:
					"A titled line in the layer list. It is not drawn on the card.",
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
					ids.length > 1
						? `Delete ${ids.length} layers?`
						: `Delete '${ids[0]}'?`,
				message: `${refs.map((r) => `'${r}'`).join(", ")} ${refs.length > 1 ? "refer" : "refers"} to ${ids.length > 1 ? "these layers" : "it"} and will show errors.`,
				confirm: "Delete",
				danger: true,
			});
			if (!ok) return;
		}
		editDoc((d) => {
			for (const id of ids)
				if (!ancestorsOf(d, id).some((a) => ids.includes(a)))
					deleteLayer(d, id);
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
		const groups = selectedLayers.filter((id) =>
			isGroup(findLayer(doc!, id)),
		);
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
			else
				for (const id of [...order].reverse())
					reorderLayer(d, id, target);
		});
	}

	/**
	 * The layer a canvas click on `id` selects: the outermost group around
	 * it, unless that group (or a layer next to it in a group) is already
	 * being edited. `deep` (double click) picks the layer itself.
	 */
	function pickOnCanvas(id: string, deep: boolean): string | null {
		if (!doc) return id;
		// A layer of a component that could not be filled in (included
		// twice, say) is not in this design: a click picks its group.
		if (!findLayer(doc, id)) {
			const group = layout.find((b) => b.id === id)?.component;
			return group && findLayer(doc, group) ? pickOnCanvas(group, false) : null;
		}
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

	// ---------------------------------------------------------------- components

	/** Moves a group's layers into a new component file that the group then includes. */
	async function createComponent(id: string) {
		if (!doc) return;
		const g = findLayer(doc, id);
		if (!isGroup(g) || includeOf(g)) return;
		const name = await askText({
			title: "Create component",
			message:
				"The layers of this group move into a component file that other designs can include too. Changing them later changes every design that uses the component.",
			value: id.replace(/_/g, " "),
			confirm: "Create component",
			validate: (v) => (v.trim() ? "" : "Give the component a name."),
		}).catch(() => null);
		if (!name?.trim() || !doc) return;
		const path = componentPath(name, (p) => files.has(p));
		const next = clone(doc);
		const ng = findLayer(next, id);
		if (!isGroup(ng)) return;
		const layers = ng.layers ?? [];
		delete ng.layers;
		ng.include = path;
		ng.layers = layers;
		writeDoc(next, "", { path, name: name.trim() });
		status = `Component '${name.trim()}' saved as ${path}.`;
	}

	/** Includes a component: in the empty group `into`, or as a new group above the selection. */
	function includeComponent(path: string, into: string | null) {
		if (!doc) return;
		if (into) {
			editDoc((d) => {
				const g = findLayer(d, into);
				if (!isGroup(g)) return;
				delete g.layers;
				g.include = path;
			});
			selectedLayers = [into];
			return;
		}
		const base = componentLabel(path).replace(/[^A-Za-z0-9_]+/g, "_");
		const stem = identRe.test(base) ? base : "component";
		const id = findLayer(doc, stem) ? uniqueId(doc, `${stem}_`) : stem;
		const layer: Obj = { id, type: "group", include: path };
		editDoc((d) => insertLayer(d, layer, selectedLayer));
		selectedLayers = [id];
		leftTab = "layers";
	}

	/** The group keeps a copy of the component's layers and no longer follows the file. */
	function detachComponent(id: string) {
		editDoc((d) => {
			const g = findLayer(d, id);
			if (g) delete g.include;
		});
	}

	/** Menu of the project's components, to include one. */
	function componentMenu(x: number, y: number, into: string | null = null) {
		if (!doc) return;
		const items: MenuItem[] = [{ heading: "Include a component" }];
		for (const p of componentFiles) {
			const why = includeBlocker(doc, p, readText);
			items.push({
				label: componentLabel(p),
				icon: "component",
				detail: why || dirOf(p),
				disabled: !!why,
				action: () => includeComponent(p, into),
			});
		}
		if (!componentFiles.length)
			items.push({
				label: "No components yet",
				detail: "right-click a group, Create component",
				disabled: true,
				action: () => {},
			});
		openMenu(x, y, items);
	}

	/** Designs and components that include a component file, other than the open design. */
	function componentUsers(path: string): string[] {
		return includersOf(path, fileList, readText).filter(
			(p) => p !== designPath,
		);
	}

	function setTag(ids: string[], tag: LayerTag | null) {
		editDoc((d) => {
			for (const id of ids) {
				const l = findLayer(d, id);
				if (!l) continue;
				if (tag) l.tag = tag;
				else delete l.tag;
			}
		});
	}

	/** The row of colour dots at the top of the layer menu: one click sets the tag. */
	function tagRow(ids: string[]): MenuItem {
		// The current colour is marked when every selected layer has the same one.
		const tags = new Set(ids.map((id) => findLayer(doc!, id)?.tag ?? null));
		const cur = tags.size === 1 ? [...tags][0] : undefined;
		return {
			label: "Colour in the layer list",
			swatches: [
				{
					label: "No colour",
					color: null,
					current: cur === null,
					action: () => setTag(ids, null),
				},
				...layerTags.map((t) => ({
					label: tagLabels[t],
					color: `var(--tag-${t})`,
					current: cur === t,
					action: () => setTag(ids, t),
				})),
			],
		};
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
					label: typeLabels[t],
					icon: layerIcon(t),
					action: () => addLayer(t),
				});
			items.push(
				{
					label: "Group",
					icon: "group",
					detail: "empty",
					action: () => addContainer("group"),
				},
				{
					label: "Divider…",
					icon: "divider",
					detail: "only in this list",
					action: () => addContainer("divider"),
				},
				{
					label: "Component…",
					icon: "component",
					detail: "shared layers",
					action: () => componentMenu(e.clientX + 8, e.clientY + 8),
				},
				{ separator: true },
			);
			items.push(
				{
					label: "Paste",
					icon: "paste",
					shortcut: "Ctrl+V",
					disabled: !clipboard.length,
					action: () => pasteFromMemory(),
				},
				{
					label: "Select all",
					icon: "select-all",
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
		// Colour tags first: the dots are picked with one click.
		if (ids.length) items.push(tagRow(ids), { separator: true });
		if (one)
			items.push({
				label: "Rename…",
				icon: "pencil",
				action: () => renameAsk(one),
			});
		if (one && isDivider(l))
			items.push({
				label: "Edit title…",
				icon: "pencil",
				action: () => editDividerLabel(one),
			});
		if (one)
			items.push({
				label: "Add above",
				icon: "plus",
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
				icon: "copy",
				shortcut: "Ctrl+D",
				action: () => duplicateMany(ids),
			},
			{
				label: "Copy",
				icon: "clipboard",
				shortcut: "Ctrl+C",
				action: () => copyToMemory(ids),
			},
			{
				label: "Cut",
				icon: "scissors",
				shortcut: "Ctrl+X",
				action: () => {
					copyToMemory(ids);
					removeLayers(ids);
				},
			},
			{
				label: "Paste above",
				icon: "paste",
				shortcut: "Ctrl+V",
				disabled: !clipboard.length,
				action: () => pasteFromMemory(),
			},
			{ separator: true },
			{
				label: "Group",
				icon: "group",
				shortcut: "Ctrl+G",
				action: groupSelected,
			},
			{
				label: "Ungroup",
				icon: "ungroup",
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
					icon: "up",
					shortcut: "Ctrl+↑",
					action: () => editDoc((d) => stepLayer(d, one, 1)),
				},
				{
					label: "Send backward",
					icon: "down",
					shortcut: "Ctrl+↓",
					action: () => editDoc((d) => stepLayer(d, one, -1)),
				},
			);
			if (at)
				items.push({
					label: `Move out of '${at}'`,
					icon: "move-out",
					action: () => editDoc((d) => reorderLayer(d, one, at)),
				});
		}
		if (one && isGroup(l)) {
			const inc = includeOf(l);
			items.push({ separator: true });
			if (inc)
				items.push(
					{
						label: "Detach from component",
						icon: "ungroup",
						detail: "keeps a copy here",
						action: () => detachComponent(one),
					},
					{
						label: "Open component file",
						icon: "braces",
						action: () => openFileInCode(inc),
					},
				);
			else if (childrenOf(l).length)
				items.push({
					label: "Create component…",
					icon: "component",
					detail: "share with other designs",
					action: () => createComponent(one),
				});
			else
				items.push({
					label: "Include a component…",
					icon: "component",
					action: () => componentMenu(e.clientX + 8, e.clientY + 8, one),
				});
		}
		items.push({ separator: true });
		if (l) {
			items.push(
				{
					label: l.visible === false ? "Show" : "Hide",
					icon: l.visible === false ? "eye" : "eye-off",
					action: () => toggleVisible(one!),
				},
				{
					label: locked.has(one!) ? "Unlock" : "Lock",
					icon: locked.has(one!) ? "lock" : "unlock",
					action: () => toggleLock(one!),
				},
			);
		}
		items.push({
			label: ids.length > 1 ? `Delete ${ids.length} layers` : "Delete",
			icon: "trash",
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
		clipboard = inStackOrder(ids).map((id) => detached(findLayer(doc!, id)!));
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
		const order = inStackOrder(ids);
		// A design can include a component once: the copy of an including
		// group is a plain group with its own copy of the layers.
		const layers = order.map((id) => detached(findLayer(doc!, id)!));
		if (order.some((id) => includeOf(findLayer(doc!, id))))
			status = "The copy is a plain group: a design can include a component once.";
		let made: string[] = [];
		editDoc((d) => (made = pasteLayers(d, layers, order.at(-1)!)));
		selectedLayers = made;
	}

	// Copy and paste use the system clipboard (JSON, so layers can move
	// between tabs and projects) with an in-memory fallback.
	let clipboard: Obj[] = [];

	function canUseClipboard(e: ClipboardEvent) {
		// A text field handled it (CodeMirror cuts the whole line when
		// nothing is selected, which also removes the event's target from
		// the page, so the target alone cannot tell).
		if (e.defaultPrevented) return false;
		const editable =
			"input, textarea, select, [contenteditable], .cm-editor";
		const t = e.target as HTMLElement | null;
		const focused = document.activeElement as HTMLElement | null;
		return (
			mode === "build" &&
			!!doc &&
			!!t?.isConnected &&
			!t.closest(editable) &&
			!focused?.closest(editable)
		);
	}

	function onCopy(e: ClipboardEvent, cut = false) {
		if (!canUseClipboard(e) || !selectedLayers.length) return;
		e.preventDefault();
		clipboard = inStackOrder(selectedLayers).map((id) =>
			detached(findLayer(doc!, id)!),
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
			const data = JSON.parse(
				e.clipboardData?.getData("text/plain") ?? "",
			);
			if (Array.isArray(data?.yoshida_layers))
				layers = data.yoshida_layers.filter(isObj);
			else if (isObj(data) && typeof data.type === "string")
				layers = [data];
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
		editDoc((d) =>
			distributeLayers(d, selectedLayers, axis, layout, canvasSize),
		);
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
				return isObj(l.shape) ? "box" : "polygon";
			case "qr":
				return "aspect";
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
	/** Files a live preview put into the worker with the gesture applied. */
	let liveTouched = new Set<string>();

	/** Puts the files of a candidate design into the worker (not into the project). */
	async function putCandidate(d: Obj) {
		const changes = docChanges(d);
		const now = new Set(changes.map((c) => c.path));
		for (const c of changes) {
			liveTouched.add(c.path);
			await engine.put(c.path, bytesOf(c.text));
		}
		// A file an earlier step changed and this one does not.
		for (const p of liveTouched)
			if (!now.has(p) && files.has(p)) await engine.put(p, files.get(p)!);
	}

	function applyGesture(d: Obj, g: Gesture) {
		if (g.mode === "move") moveLayers(d, g.ids, g.dx, g.dy, canvasSize);
		else if (g.mode === "resize")
			resizeLayer(d, g.id, g.from, g.to, canvasSize, g.angle);
		else if (g.mode === "rotate") rotateLayer(d, g.id, g.angle);
		else movePoint(d, g.id, g.index, g.dx, g.dy, canvasSize);
	}

	// Moving layers, Fast drag preview: at the start the card is rendered as
	// three pictures, the layers below the moved ones (with the card), the moved
	// ones alone, and the layers above them alone. The stage slides the moved
	// picture over the first and draws the last over it. The real render
	// follows on release. (Layers that depend on the moved ones by expression
	// do not follow until then.)
	let dragSprite = $state.raw<Sprite | null>(null);
	let spriteToken: object | null = null;

	/**
	 * Layers drawn above the layers `ids` (in card order), at every level, not
	 * including them. A later sibling inside a group is listed as it is (the
	 * render filter takes nested ids); a group listed covers its children, so
	 * only the outermost of those are listed.
	 */
	function layersAbove(ids: string[]): string[] {
		const d = doc;
		if (!d || !Array.isArray(d.layers)) return [];
		const order = layersOf(d).map((l) => String(l.id));
		const cut = Math.max(-1, ...ids.map((id) => order.indexOf(id)));
		if (cut < 0) return [];
		const moved = new Set(ids);
		const out: string[] = [];
		const listed = new Set<string>();
		for (const id of order.slice(cut + 1)) {
			// Inside a moved layer (it moves with the layer) or inside a listed group.
			if (ancestorsOf(d, id).some((a) => moved.has(a) || listed.has(a))) continue;
			out.push(id);
			listed.add(id);
		}
		return out;
	}

	/**
	 * Whether Fast cannot draw the moved layers exactly, so the gesture uses
	 * Live: an ancestor group with a repeat, effects, opacity below 1 or a
	 * rotation (rendered through a scratch bitmap, or once per iteration), or a
	 * layer that is not moved lying between moved layers in card order.
	 */
	function needsLive(ids: string[]): boolean {
		const d = doc;
		if (!d || !Array.isArray(d.layers)) return true;
		const all = layersOf(d);
		const byId = new Map(all.map((l) => [String(l.id), l]));
		const moved = new Set(ids);
		const composites = (g: Obj) =>
			g.repeat != null ||
			(Array.isArray(g.effects) ? g.effects.length > 0 : g.effects != null) ||
			(typeof g.opacity === "number" ? g.opacity < 1 : g.opacity != null) ||
			(typeof g.rotate === "number" ? g.rotate !== 0 : g.rotate != null);
		for (const id of ids)
			for (const a of ancestorsOf(d, id))
				if (byId.has(a) && composites(byId.get(a)!)) return true;
		const pos = ids.map((id) => all.findIndex((l) => String(l.id) === id));
		if (pos.some((i) => i < 0)) return true;
		for (let i = Math.min(...pos) + 1; i < Math.max(...pos); i++) {
			const id = String(all[i].id);
			if (!moved.has(id) && !ancestorsOf(d, id).some((a) => moved.has(a)))
				return true;
		}
		return false;
	}

	async function prepareSprite(ids: string[]) {
		const token = {};
		spriteToken = token;
		const args = {
			set: setName,
			card: cardIndex,
			...renderClock(),
			preview: true,
			format: "rgba" as const,
			scale: wantedScale,
		};
		const above = layersAbove(ids);
		try {
			const [bg, fg, top] = await Promise.all([
				engine.render({ ...args, except: [...ids, ...above] }),
				engine.render({ ...args, only: ids }),
				above.length
					? engine.render({ ...args, only: above })
					: Promise.resolve(null),
			]);
			if (spriteToken !== token || !bg.width || !fg.width) return;
			// async: a throw here becomes a rejection, so the others are still closed.
			const bitmap = async (r: RenderResult) =>
				createImageBitmap(
					new ImageData(
						new Uint8ClampedArray(
							r.bin.buffer as ArrayBuffer,
							r.bin.byteOffset,
							r.bin.byteLength,
						),
						r.width,
						r.height,
					),
				);
			const settled = await Promise.allSettled([
				bitmap(bg),
				bitmap(fg),
				top?.width ? bitmap(top) : Promise.resolve(null),
			]);
			// Close the bitmaps that were made, also when a later one failed.
			const made: ImageBitmap[] = [];
			for (const s of settled)
				if (s.status === "fulfilled" && s.value) made.push(s.value);
			if (
				settled.some((s) => s.status === "rejected") ||
				spriteToken !== token
			) {
				for (const m of made) m.close();
				return;
			}
			const [b, f, t] = settled.map((s) =>
				s.status === "fulfilled" ? s.value : null,
			) as [ImageBitmap, ImageBitmap, ImageBitmap | null];
			dragSprite = {
				bg: b,
				fg: f,
				top: t,
				dx: spriteMove.dx,
				dy: spriteMove.dy,
			};
		} catch {
			// No sprite: the boxes still follow the pointer, the render comes on release.
		}
	}
	let spriteMove = { dx: 0, dy: 0 };

	// Live gesture preview (moving in Live mode, resizing, rotating, moving a
	// point): the whole card is re-rendered with the gesture applied, without
	// checking the project or touching the open files. One render runs at a
	// time; gestures that arrive meanwhile are skipped, the latest is rendered next.
	let liveToken: object | null = null;
	let liveWant: Gesture | null = null;
	let liveRunning = false;
	/** A preview render finished during a gesture and was not shown. */
	let previewSkipped = false;

	async function liveRender(token: object) {
		if (liveRunning) return;
		liveRunning = true;
		try {
			while (liveWant && liveToken === token) {
				const want = liveWant;
				liveWant = null;
				const d = JSON.parse(gestureBase!) as Obj;
				applyGesture(d, want);
				// The worker reads the design from its file system: put the candidate there.
				await putCandidate(d);
				if (liveToken !== token) break;
				const scale = wantedScale;
				const r = await engine.render({
					set: setName,
					card: cardIndex,
					...renderClock(),
					preview: true,
					format: "rgba",
					layout: true,
					scale,
				});
				if (liveToken !== token) break;
				if (r.width) showPicture(r, scale);
			}
		} catch (err) {
			// The last picture stays; the release renders again.
			status = `Live preview failed: ${err instanceof Error ? err.message : err}`;
		} finally {
			liveRunning = false;
			// A newer gesture may have asked for a render while this one ran.
			if (liveWant && liveToken) void liveRender(liveToken);
		}
	}

	$effect(() => {
		const sp = dragSprite;
		return () => {
			// Free the bitmaps once the next picture replaces them.
			if (sp && dragSprite?.bg !== sp.bg) {
				sp.bg.close();
				sp.fg.close();
				sp.top?.close();
			}
		};
	});

	function onGesture(g: Gesture, phase: "start" | "move" | "end") {
		if (!designPath || !doc) return;
		if (phase === "start") {
			gestureBase = JSON.stringify(doc);
			liveTouched = new Set();
			previewSkipped = false;
			spriteMove = { dx: 0, dy: 0 };
			if (g.mode === "move" && dragPreview === "fast" && !needsLive(g.ids)) {
				// A plain copy: the ids may be reactive state, which cannot be posted.
				prepareSprite([...g.ids]);
			} else {
				liveToken = {};
				liveWant = null;
			}
			return;
		}
		if (gestureBase === null) return;
		if (phase === "move") {
			if (liveToken) {
				// A plain copy, for the same reason.
				liveWant = $state.snapshot(g) as Gesture;
				void liveRender(liveToken);
			} else if (g.mode === "move") {
				spriteMove = { dx: g.dx, dy: g.dy };
				if (dragSprite) dragSprite = { ...dragSprite, dx: g.dx, dy: g.dy };
			}
			return;
		}
		// phase "end"
		const live = liveToken !== null;
		spriteToken = null;
		liveToken = null;
		liveWant = null;
		let d: Obj;
		try {
			d = JSON.parse(gestureBase);
		} catch {
			return;
		}
		applyGesture(d, g);
		gestureBase = null;
		const changed = new Set(docChanges(d).map((c) => c.path));
		// A live preview left changed files in the worker: put back the ones
		// that stay as they were.
		for (const p of liveTouched)
			if (!changed.has(p) && files.has(p)) engine.put(p, files.get(p)!);
		liveTouched = new Set();
		const wrote = writeDoc(d);
		lastKey = "";
		if (!wrote) {
			dragSprite = null;
			if (live || previewSkipped) refresh();
		}
	}

	function nudge(ids: string[], dx: number, dy: number) {
		editDoc(
			(d) => moveLayers(d, ids, dx, dy, canvasSize),
			`nudge:${ids.join(",")}`,
		);
	}

	function onKey(e: KeyboardEvent) {
		const t = e.target as HTMLElement | null;
		const typing = !!t?.closest(
			"input, textarea, select, [contenteditable]",
		);
		const mod = e.ctrlKey || e.metaKey;
		const k = e.key.toLowerCase();
		if (k === "f1" && !mod && !e.shiftKey && !e.altKey) {
			e.preventDefault();
			if (functionsRef.open) closeFunctions();
			else openFunctions();
			return;
		}
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
		if (!typing && !mod && !e.altKey && reviewKey(e)) {
			e.preventDefault();
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
			const dx =
				k === "arrowleft" ? -step : k === "arrowright" ? step : 0;
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
			match: (d: Diagnostic) => ids.has(diagnosticLayer(d) ?? ""),
		};
	});

	$effect(() => {
		if (problemFocus && doc && !findLayer(doc, problemFocus))
			problemFocus = null;
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
		if (mode === "build" && doc) {
			const id = diagnosticLayer(d);
			if (id) {
				selectedLayers = [id];
				leftTab = "layers";
				layerReveal = { id, n: ++gotoCount };
				return;
			}
		}
		if (mode === "build" && d.file === designPath && doc) {
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

	/** Shows a project file in the Advanced view, e.g. a component file. */
	function openFileInCode(path: string) {
		if (!files.has(path)) {
			status = `'${path}' is not in the project.`;
			return;
		}
		mode = "code";
		selected = path;
		sidePanel = "files";
	}

	function openJson() {
		mode = "code";
		if (designPath) selected = designPath;
		sidePanel = "files";
	}

	// ---------------------------------------------------------------- export

	/** Time per card of the last export in this browser, for the next estimate. */
	let perCardMs = 0;

	/**
	 * Expected time to render one card at full size here: the last export, or
	 * the preview scaled up to the full pixel count (render time is roughly
	 * proportional to the pixels).
	 */
	function fullCardEstimate(): number | null {
		if (perCardMs) return perCardMs;
		if (!renderMs) return null;
		return (renderMs / Math.max(renderScale * renderScale, 1 / 4096)) * 1.2;
	}
	/** ZIP and PDF exports go to the server (the switch next to the export buttons). */
	const onServer = $derived(useServer && !!server?.render);
	const errorCount = (ds: Diagnostic[]) =>
		ds.filter((d) => d.severity === "error").length;

	async function exportPng() {
		if (!currentSet || !currentCard) return;
		track("export", "png");
		const card = currentCard;
		const run = new Run(`Exporting ${card.id}.png`, []);
		const clock = renderClock();
		busy = "Rendering PNG…";
		try {
			run.log(`Rendering card '${card.id}' at full size in this browser`);
			// One call with no progress inside: the bar stays indeterminate and
			// the estimate is shown as text only.
			run.estimate(fullCardEstimate());
			const t0 = Date.now();
			const r = await engine.render({
				set: setName,
				card: cardIndex,
				...clock,
				preview: false,
				format: "png",
			});
			perCardMs = Date.now() - t0;
			if (r.bin.length) download(`${card.id}.png`, r.bin, "image/png");
			lastRender = { ...r, bin: new Uint8Array() };
			const errs = errorCount(r.diagnostics);
			if (errs) {
				status = `Exported with ${errs} error(s); see the problems.`;
				run.log(`${errs} error(s); see the problems panel`, "error");
			} else status = `Exported ${card.id}.png.`;
			if (r.bin.length)
				run.finish(
					`Saved ${card.id}.png (${formatBytes(r.bin.length)})`,
				);
			else run.fail("Nothing was drawn; see the problems panel.");
		} catch (e) {
			run.fail(`Could not render: ${(e as Error).message}`);
		} finally {
			busy = "";
		}
	}

	async function exportZip() {
		if (!currentSet) return;
		track("export", "zip");
		if (onServer) return exportOnServer("png");
		const set = currentSet;
		const name = setName;
		const n = set.cards.length;
		const clock = renderClock();
		// Weights: rendering is nearly all of the time; the zip is stored, not compressed.
		const run = new Run(
			`Exporting ${n} card${n === 1 ? "" : "s"} as a ZIP`,
			[
				["Render the cards", 94],
				["Pack the zip", 4],
				["Save", 2],
			],
		);
		let stop = false;
		run.onCancel(() => (stop = true));
		busy = "Exporting…";
		try {
			run.step(0, `0 / ${n}`);
			run.log(
				`Rendering ${n} card(s) of '${set.design_name}' in this browser`,
			);
			const zip: Record<string, Uint8Array> = {};
			const diagnostics: Diagnostic[] = [];
			const t0 = Date.now();
			run.perUnit(fullCardEstimate());
			for (let i = 0; i < n; i++) {
				run.count(i, n);
				const r = await engine.render({
					set: name,
					card: i,
					...clock,
					preview: false,
					format: "png",
				});
				if (stop) {
					status = "Export cancelled.";
					return;
				}
				diagnostics.push(...r.diagnostics);
				if (r.bin.length) zip[`${name}/${set.cards[i].id}.png`] = r.bin;
				run.count(i + 1, n);
				run.detail(0, `${i + 1} / ${n}`);
			}
			perCardMs = (Date.now() - t0) / Math.max(1, n);
			run.log(
				`Rendered ${n} card(s) in ${formatMs(Date.now() - t0)} (${(perCardMs / 1000).toFixed(2)} s per card)`,
			);
			run.step(1);
			// Let the bar show the step before the (blocking) packing.
			await new Promise((r) => setTimeout(r, 0));
			const bytes = zipSync(zip, { level: 0 });
			const fileName = `${projectName}-${name}.zip`;
			run.step(2, formatBytes(bytes.length));
			download(fileName, bytes, "application/zip");
			const errs = errorCount(diagnostics);
			status =
				`Exported ${Object.keys(zip).length} card(s)` +
				(errs ? ` with ${errs} error(s)` : "");
			if (errs) {
				showDiagnostics(diagnostics);
				run.log(`${errs} error(s); see the problems panel`, "error");
			}
			run.finish(`Saved ${fileName} (${formatBytes(bytes.length)})`);
		} catch (e) {
			run.fail(`Could not export: ${(e as Error).message}`);
		} finally {
			busy = "";
		}
	}

	/** Shows diagnostics found outside the preview render in the problems panel. */
	function showDiagnostics(diagnostics: Diagnostic[]) {
		lastRender = {
			width: 0,
			height: 0,
			missing_urls: [],
			bin: new Uint8Array(),
			diagnostics,
		};
	}

	/**
	 * Every card in one PDF, the pages drawn as vectors (sharp at any zoom,
	 * small files); with `canvas.bleed`, with crop marks. The export dialog
	 * offers pages as images instead.
	 */
	async function exportPdf() {
		if (!currentSet) return;
		track("export", "pdf");
		if (onServer) return exportOnServer("pdf");
		const n = currentSet.cards.length;
		const clock = renderClock();
		const run = new Run(
			`Exporting ${n} page${n === 1 ? "" : "s"} as a PDF`,
			[
				["Render the pages", 97],
				["Save", 3],
			],
			"pages",
		);
		busy = "Rendering PDF…";
		try {
			const bleed = hasBleed(doc?.canvas);
			run.step(0, `0 / ${n}`);
			// Pages are rendered one by one, and each one reports back.
			const per = fullCardEstimate();
			run.perUnit(per);
			run.count(0, n);
			run.log(
				`Rendering ${n} page(s) in this browser${bleed ? " with crop marks" : ""}` +
					(per ? `; about ${formatMs(per * n)} expected` : ""),
			);
			const t0 = Date.now();
			const r = await engine.pdf(
				setName,
				clock,
				bleed,
				n,
				(done) => {
					run.count(done, n);
					run.detail(0, `${done} / ${n}`);
				},
				{},
			);
			perCardMs = (Date.now() - t0) / Math.max(1, n);
			run.log(
				`Rendered ${r.pages} page(s) in ${formatMs(Date.now() - t0)} (${(perCardMs / 1000).toFixed(2)} s per page)`,
			);
			const fileName = `${projectName}-${setName}.pdf`;
			run.step(1, formatBytes(r.bin.length));
			if (r.bin.length) download(fileName, r.bin, "application/pdf");
			const errs = errorCount(r.diagnostics);
			status =
				`Exported ${r.pages} page(s)` +
				(bleed ? " with crop marks" : "") +
				(errs ? ` with ${errs} error(s)` : "");
			if (errs) {
				showDiagnostics(r.diagnostics);
				run.log(`${errs} error(s); see the problems panel`, "error");
			}
			if (r.bin.length)
				run.finish(`Saved ${fileName} (${formatBytes(r.bin.length)})`);
			else run.fail("No page was drawn; see the problems panel.");
		} catch (e) {
			run.fail(`Could not export: ${(e as Error).message}`);
		} finally {
			busy = "";
		}
	}

	/** Evaluates every card (without drawing) to find errors that depend on card data. */
	async function checkAllCards() {
		if (!currentSet) return;
		const n = currentSet.cards.length;
		const run = new Run(`Checking ${n} card${n === 1 ? "" : "s"}`, []);
		const doneTitle = `Checked ${n} card${n === 1 ? "" : "s"}`;
		busy = "Checking every card…";
		try {
			run.log(`Evaluating every card of '${currentSet.design_name}'`);
			const r = await engine.checkCards(setName, renderClock());
			const errs = errorCount(r.diagnostics);
			const warns = r.diagnostics.filter(
				(d) => d.severity === "warning",
			).length;
			const hints = r.diagnostics.filter(
				(d) => d.severity === "hint",
			).length;
			const plural = (k: number, word: string) =>
				`${k} ${word}${k === 1 ? "" : "s"}`;
			status = `Checked ${n} card(s): ${errs} error(s), ${warns} warning(s)`;
			showDiagnostics(r.diagnostics);
			run.finish(
				status,
				`Checked ${plural(n, "card")}: ${plural(errs, "error")}, ${plural(warns, "warning")}, ${plural(hints, "hint")}.`,
			);
			if (run.live && progress.task) progress.task.title = doneTitle;
		} catch (e) {
			run.fail(`Could not check the cards: ${(e as Error).message}`);
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

	const serverStages: Record<string, string> = {
		receiving: "receiving the project",
		loading: "loading the project",
		rendering: "rendering the cards",
		packing: "packing the result",
		finished: "finished",
		failed: "stopped with an error",
	};

	/**
	 * Posts one render request (`body`, for a set of `n` cards) to the
	 * server and follows its progress on `run`: `at` are the run's upload,
	 * render and download steps. `ctl.abort` cancels it.
	 */
	function postRender(
		run: Run,
		body: string,
		n: number,
		at: [number, number, number],
		ctl: { abort?: () => void },
	): Promise<{ status: number; blob: Blob }> {
		const [upStep, renderStep, downStep] = at;
		const url = new URL("api/render", document.baseURI).href;
		const job = Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) =>
			b.toString(16).padStart(2, "0"),
		).join("");
		const xhr = new XMLHttpRequest();
		let poll: ReturnType<typeof setInterval> | undefined;
		const stopPoll = () => clearInterval(poll);
		ctl.abort = () => {
			stopPoll();
			xhr.abort();
		};
		run.step(upStep, formatBytes(body.length));
		run.log(`Uploading ${formatBytes(body.length)} to ${url} (job ${job})`);
		const t0 = Date.now();
		let tRender = 0;
		let lastStage = "";
		/** The upload is complete: the server works now (upload events, or the server's own stage, say so). */
		const uploaded = () => {
			if (tRender) return;
			tRender = Date.now();
			run.log(`Uploaded in ${formatMs(tRender - t0)}`);
			run.step(renderStep, `0 / ${n}`);
			run.log(`The server is rendering ${n} card(s)`);
		};
		const startPoll = () => {
			poll = setInterval(async () => {
				try {
					const res = await fetch(`api/render/progress?job=${job}`, {
						cache: "no-store",
					});
					if (!res.ok) return;
					const p = await res.json();
					if (!p.found || !run.live || xhr.readyState >= 2) return;
					if (p.stage !== "receiving") uploaded();
					if (p.stage !== lastStage) {
						lastStage = p.stage;
						run.log(`Server: ${serverStages[p.stage] ?? p.stage}`);
					}
					if (p.total) {
						run.count(p.done, p.total);
						run.detail(renderStep, `${p.done} / ${p.total}`);
					}
				} catch {
					// Progress is optional (older servers do not report it).
				}
			}, 400);
		};
		return new Promise<{ status: number; blob: Blob }>((resolve, reject) => {
			xhr.open("POST", "api/render");
			xhr.responseType = "blob";
			xhr.setRequestHeader("content-type", "application/json");
			xhr.setRequestHeader("x-yoshida-job", job);
			xhr.upload.onprogress = (e) => {
				if (!e.lengthComputable) return;
				run.fraction(e.loaded / e.total);
				run.detail(
					upStep,
					`${formatBytes(e.loaded)} of ${formatBytes(e.total)}`,
				);
			};
			xhr.upload.onload = uploaded;
			xhr.onreadystatechange = () => {
				if (xhr.readyState !== XMLHttpRequest.HEADERS_RECEIVED) return;
				stopPoll();
				if (tRender)
					run.log(
						`Server answered ${xhr.status} after ${formatMs(Date.now() - tRender)} of rendering`,
					);
				if (xhr.status === 200) run.step(downStep);
			};
			xhr.onprogress = (e) => {
				if (xhr.status !== 200) return;
				if (e.lengthComputable) {
					run.fraction(e.loaded / e.total);
					run.detail(
						downStep,
						`${formatBytes(e.loaded)} of ${formatBytes(e.total)}`,
					);
				}
			};
			xhr.onload = () => resolve({ status: xhr.status, blob: xhr.response });
			xhr.onerror = () =>
				reject(new Error(`could not reach the server at ${url}`));
			xhr.onabort = () => reject(new DOMException("cancelled", "AbortError"));
			xhr.send(body);
			startPoll();
		}).finally(stopPoll);
	}

	/** The message (and problems) of a server answer that is not 200. */
	async function serverFailure(res: { status: number; blob: Blob }) {
		const text = await res.blob.text();
		let err: { error?: string; diagnostics?: Diagnostic[] };
		try {
			err = JSON.parse(text);
		} catch {
			err = { error: text.slice(0, 200) || `HTTP ${res.status}` };
		}
		if (err.diagnostics) showDiagnostics(err.diagnostics);
		return (
			`The server could not render: ${err.error ?? res.status}` +
			(err.diagnostics?.length
				? ` (${err.diagnostics.length} problem(s), see the problems panel)`
				: "")
		);
	}

	/** The project's files as the JSON of a render request's "files". */
	const filesJson = () =>
		JSON.stringify(Object.fromEntries([...files].map(([p, d]) => [p, b64(d)])));

	/**
	 * A render request for the project (`fj`: its files from `filesJson`);
	 * null (and the run failed) when it is too big for the server.
	 */
	function serverBody(run: Run, req: object, fj = filesJson()): string | null {
		const body = `{"files":${fj},${JSON.stringify(req).slice(1)}`;
		const limit = (server?.max_body_mb ?? 0) * 1024 * 1024;
		if (limit && body.length > limit) {
			run.fail(
				`The upload would be ${formatBytes(body.length)}; this server accepts up to ${server?.max_body_mb} MB (its --max-body-mb setting).`,
			);
			status = "Server render refused: the project is too big for this server.";
			return null;
		}
		return body;
	}

	/**
	 * Renders the whole set on the yoshida server this editor is served from:
	 * uploads the project, follows the server's progress, downloads the result.
	 */
	async function exportOnServer(format: "png" | "pdf") {
		if (!currentSet) return;
		const set = currentSet;
		const name = setName;
		const n = set.cards.length;
		const clock = renderClock();
		const what = format === "pdf" ? "PDF" : "ZIP";
		// Weights: a rough share of the time on a local network; the bar moves
		// with the bytes sent, the cards the server reports and the bytes received.
		const run = new Run(
			`Rendering ${n} card${n === 1 ? "" : "s"} on the server (${what})`,
			[
				["Pack the project", 3],
				["Upload to the server", 10],
				["Render on the server", 77],
				["Download the result", 8],
				["Save", 2],
			],
		);
		const ctl: { abort?: () => void } = {};
		run.onCancel(() => ctl.abort?.());
		busy = "Rendering on the server…";
		try {
			run.step(0);
			const raw = [...files.values()].reduce((a, d) => a + d.length, 0);
			run.log(
				`Packing ${files.size} file(s) (${formatBytes(raw)}) of '${projectName}'`,
			);
			// Let the overlay draw before the (blocking) encoding.
			await new Promise((r) => setTimeout(r, 30));
			// The quick PDF has vector pages, like the one made in this browser.
			const body = serverBody(run, {
				set: name,
				...clock,
				format,
				...(format === "pdf" ? { vector: true } : {}),
			});
			if (!body) return;
			const t0 = Date.now();
			const res = await postRender(run, body, n, [1, 2, 3], ctl);
			if (res.status !== 200) {
				const msg = await serverFailure(res);
				status = msg;
				run.fail(msg);
				return;
			}
			const ext = format === "pdf" ? "pdf" : "zip";
			const fileName = `${projectName}-${name}.${ext}`;
			run.step(4, formatBytes(res.blob.size));
			download(
				fileName,
				res.blob,
				format === "pdf" ? "application/pdf" : "application/zip",
			);
			status = `Rendered ${n} card(s) on the server in ${formatMs(Date.now() - t0)}; saved ${fileName}.`;
			run.finish(`Saved ${fileName} (${formatBytes(res.blob.size)})`);
		} catch (e) {
			if ((e as Error).name === "AbortError")
				status = "Server render cancelled.";
			else {
				status = `Server render failed: ${(e as Error).message}`;
				run.fail(status);
			}
		} finally {
			busy = "";
		}
	}

	// ------------------------------------------------------- export dialog

	const EXPORT_PREF = "yoshida.export";
	let exportOpen = $state(false);
	let exportButton: HTMLButtonElement | undefined = $state();
	let exportSettings = $state(cleanSettings(loadPref(EXPORT_PREF, {})));
	/** Whether this browser can write WebP, and lossless WebP; null until checked. */
	let webpOk = $state<boolean | null>(null);
	let webpLosslessOk = $state<boolean | null>(null);
	/** Each design's canvas (size, dpi and bleed), measured when the dialog opens. */
	let exportCanvases = $state<Record<string, CanvasInfo>>({});
	let exportMeasuring = $state(false);
	const planSets = $derived<PlanSet[]>(
		sets.map((x) => ({
			name: x.name,
			label: x.design_name,
			ok: x.ok,
			cards: x.cards.map((c) => c.id),
			canvas: exportCanvases[x.name] ?? null,
		})),
	);

	/**
	 * Measures the canvas of every design that can be exported: its size and
	 * dpi can be expressions, so the core evaluates them, at a tiny scale and
	 * without drawing a layer. The shown design is measured on the shown card.
	 */
	async function measureCanvases() {
		const clock = renderClock();
		const k = 1 / 64;
		const out: Record<string, CanvasInfo> = {};
		exportMeasuring = true;
		try {
			for (const x of sets) {
				if (!x.ok || !x.cards.length) continue;
				try {
					const r = await engine.render({
						set: x.name,
						card: x.name === setName ? cardIndex : 0,
						...clock,
						preview: true,
						format: "rgba",
						scale: k,
						only: [],
					});
					if (r.canvas_width && r.canvas_height)
						out[x.name] = {
							w: r.canvas_width,
							h: r.canvas_height,
							dpi: (r.dpi ?? 0) / k,
							bleed: (r.bleed ?? 0) / k,
						};
				} catch {
					// Not measured: the dialog shows its size as unknown.
				}
			}
		} finally {
			exportCanvases = out;
			exportMeasuring = false;
		}
	}

	function openExport() {
		// Until the measurement is back, the shown design's canvas comes from
		// its last render and its literal dpi and bleed.
		const dpi = getPath(doc ?? undefined, ["canvas", "dpi"]);
		const literal = dpi === undefined ? 0 : literalNumber(dpi);
		const bleed = getPath(doc ?? undefined, ["canvas", "bleed"]);
		if (
			lastRender?.canvas_width &&
			lastRender.canvas_height &&
			literal !== undefined &&
			!exportCanvases[setName]
		)
			exportCanvases = {
				...exportCanvases,
				[setName]: {
					w: lastRender.canvas_width,
					h: lastRender.canvas_height,
					dpi: literal,
					bleed: (bleed === undefined ? 0 : literalNumber(bleed)) ?? 0,
				},
			};
		exportOpen = true;
		measureCanvases();
		if (webpOk === null) canEncodeWebp().then((ok) => (webpOk = ok));
		if (webpLosslessOk === null)
			canEncodeLosslessWebp().then((ok) => (webpLosslessOk = ok));
	}

	function closeExport() {
		exportOpen = false;
		requestAnimationFrame(() => exportButton?.focus());
	}

	/** Crop marks for a set's PDF: the dialog's choice, or on when the design has a bleed. */
	function cropMarksFor(set: SetInfo, mode: ExportSettings["cropMarks"]) {
		if (mode !== "auto") return mode === "on";
		const d = files.get(set.design);
		return designHasBleed(d ? new TextDecoder().decode(d) : undefined);
	}

	const mimeOf: Record<string, string> = {
		png: "image/png",
		jpg: "image/jpeg",
		webp: "image/webp",
		svg: "image/svg+xml",
		pdf: "application/pdf",
	};

	/**
	 * Exports with the dialog's settings: card images and PDFs, rendered in
	 * this browser or (whole designs, PNG / SVG / PDF) on the server; one
	 * file downloads as it is, more go into one ZIP.
	 */
	async function exportWith(st: ExportSettings) {
		exportSettings = st;
		savePref(EXPORT_PREF, st);
		closeExport();
		const plan = planExport(st, projectName, planSets, setName, cardIndex);
		if (!plan.files) return;
		for (const f of st.formats) track("export", f);
		const clock = renderClock();
		// With a target dpi, each design renders at the scale that gives it
		// that dpi. The dialog measures the canvases when it opens; an export
		// started before that is done waits for it.
		if (
			st.resolution === "dpi" &&
			plan.targets.some((t) => !exportCanvases[t.set])
		)
			await measureCanvases();
		const scales = new Map(
			designOutputs(plan, planSets, st).map((o) => [o.set, o.scale]),
		);
		const scaleOf = (set: string) => scales.get(set) ?? st.scale;
		const oneScale = new Set(scales.values()).size === 1;
		// Whole designs go to the server as one request per set and format;
		// JPEG and WebP are encoded by the browser, so they render here.
		const viaServer = onServer && st.scope !== "card";
		const remote: ExportFormat[] = viaServer
			? (["png", "svg", "pdf", "sheet"] as const).filter((f) =>
					st.formats.includes(f),
				)
			: [];
		const localPng =
			plan.imageFormats.includes("png") && !remote.includes("png");
		const localSvg =
			plan.imageFormats.includes("svg") && !remote.includes("svg");
		const localPdf = plan.pdf && !remote.includes("pdf");
		const localSheet = plan.sheet && !remote.includes("sheet");
		const encodings = [
			...(plan.imageFormats.includes("jpeg")
				? [
						{
							type: "image/jpeg" as const,
							quality: st.jpegQuality / 100,
							background: st.jpegBackground,
						},
					]
				: []),
			...(plan.imageFormats.includes("webp")
				? [
						{
							type: "image/webp" as const,
							// Chromium writes lossless WebP at quality 1.
							quality: st.webpLossless ? 1 : st.webpQuality / 100,
						},
					]
				: []),
		];
		const passes =
			(localPng ? 1 : 0) +
			(encodings.length ? 1 : 0) +
			(localSvg ? 1 : 0) +
			(localPdf ? 1 : 0) +
			(localSheet ? 1 : 0);
		const units = plan.cards * passes;
		const steps: [string, number][] = [
			...(remote.length
				? ([
						["Pack the project", 3],
						["Upload to the server", 10],
						["Render on the server", passes ? 50 : 77],
						["Download the result", 8],
					] as [string, number][])
				: []),
			...(passes
				? ([["Render in this browser", remote.length ? 27 : 94]] as [
						string,
						number,
					][])
				: []),
			["Pack the zip", plan.zip ? 4 : 0.5],
			["Save", 2],
		];
		const at = { local: remote.length ? 4 : 0, pack: steps.length - 2 };
		const run = new Run(
			plan.zip
				? `Exporting ${plan.files} files into ${plan.fileName}`
				: `Exporting ${plan.fileName}`,
			steps,
			// Each card is rendered once per pass (PNG, JPEG and WebP, SVG, PDF).
			passes > 1 ? "renders" : "cards",
		);
		let stop = false;
		const ctl: { abort?: () => void } = {};
		run.onCancel(() => {
			stop = true;
			ctl.abort?.();
		});
		const cancelled = () => {
			status = "Export cancelled.";
		};
		busy = "Exporting…";
		const out: Record<string, Uint8Array> = {};
		const diagnostics: Diagnostic[] = [];
		const t0 = Date.now();
		try {
			if (plan.skipped.length)
				run.log(`Skipped (they have errors): ${plan.skipped.join(", ")}`);
			if (remote.length) {
				run.step(0);
				run.log(`Packing ${files.size} file(s) of '${projectName}'`);
				await new Promise((r) => setTimeout(r, 30));
				const fj = filesJson();
				for (const [ti, t] of plan.targets.entries()) {
					const info = sets.find((x) => x.name === t.set);
					if (!info) continue;
					for (const f of remote) {
						if (stop) return cancelled();
						const req = {
							set: t.set,
							...clock,
							format:
								f === "sheet"
									? "png"
									: f === "png" && st.pngDepth === 16
										? "png16"
										: f,
							scale: scaleOf(t.set),
							...(f === "png" ? { compression: st.pngCompression } : {}),
							...(f === "sheet"
								? { sheet: { cols: st.sheetCols, rows: st.sheetRows } }
								: {}),
							...(f === "pdf"
								? {
										crop_marks: cropMarksFor(info, st.cropMarks),
										vector: st.pdfVector,
									}
								: {}),
						};
						run.log(
							`Design ${ti + 1} of ${plan.targets.length}: '${info.design_name}' as ${formatLabels[f]} at ${formatScale(scaleOf(t.set))} on the server`,
						);
						const body = serverBody(run, req, fj);
						if (!body) return;
						const res = await postRender(
							run,
							body,
							t.cards.length,
							[1, 2, 3],
							ctl,
						);
						if (res.status !== 200) {
							const msg = await serverFailure(res);
							status = msg;
							run.fail(msg);
							return;
						}
						const bytes = new Uint8Array(await res.blob.arrayBuffer());
						if (f === "pdf") out[pdfPath(t.set)] = bytes;
						else if (f === "sheet")
							// <set>.png, or <set>-1.png and so on: the names of the ZIP.
							for (const [name, data] of Object.entries(unzipSync(bytes)))
								out[name.slice(name.lastIndexOf("/") + 1)] = data;
						else
							for (const [name, data] of Object.entries(unzipSync(bytes))) {
								// Entries are <set>/<card id>.<ext> or <card id>.<ext>.
								const base = name.slice(name.lastIndexOf("/") + 1);
								if (base) out[`${t.set}/${base}`] = data;
							}
					}
				}
			}
			if (passes) {
				run.step(at.local, `0 / ${units}`);
				run.log(
					oneScale
						? `Rendering ${plan.cards} card(s) at ${formatScale(scaleOf(plan.targets[0].set))} in this browser`
						: `Rendering ${plan.cards} card(s) in this browser, each design at the scale for ${st.dpi} dpi`,
				);
				// Time grows with the pixels: the scale squared, per card.
				const area =
					plan.targets.reduce(
						(a, t) => a + t.cards.length * scaleOf(t.set) ** 2,
						0,
					) / Math.max(1, plan.cards);
				const per = fullCardEstimate();
				run.perUnit(per ? per * area : null);
				let done = 0;
				const tick = () => {
					done++;
					run.count(done, units);
					run.detail(at.local, `${done} / ${units}`);
				};
				run.count(0, units);
				for (const t of plan.targets) {
					const info = sets.find((x) => x.name === t.set);
					if (!info) continue;
					const scale = scaleOf(t.set);
					if (!oneScale)
						run.log(`'${info.design_name}' at ${formatScale(scale)}`);
					const base = { set: t.set, ...clock, preview: false, scale };
					for (const i of t.cards) {
						const id = info.cards[i].id;
						if (localPng) {
							const r = await engine.render({
								...base,
								card: i,
								format: st.pngDepth === 16 ? "png16" : "png",
								compression: st.pngCompression,
							});
							if (stop) return cancelled();
							diagnostics.push(...r.diagnostics);
							if (r.bin.length) out[imagePath(t.set, id, "png")] = r.bin;
							tick();
						}
						if (encodings.length) {
							const r = await engine.encode({ ...base, card: i }, encodings);
							if (stop) return cancelled();
							diagnostics.push(...r.diagnostics);
							encodings.forEach((e, k) => {
								const data = r.files[k];
								if (!data?.length) return;
								if (e.type === "image/jpeg")
									out[imagePath(t.set, id, "jpeg")] = setJpegDpi(
										data,
										r.dpi ?? 0,
									);
								else out[imagePath(t.set, id, "webp")] = data;
							});
							tick();
						}
						if (localSvg) {
							const r = await engine.svg({
								set: t.set,
								card: i,
								...clock,
								scale,
							});
							if (stop) return cancelled();
							diagnostics.push(...r.diagnostics);
							if (r.bin.length) out[imagePath(t.set, id, "svg")] = r.bin;
							tick();
						}
					}
					if (localPdf) {
						const marks = cropMarksFor(info, st.cropMarks);
						await engine.pdfBegin();
						for (const i of t.cards) {
							const r = await engine.pdfPage({
								set: t.set,
								card: i,
								...clock,
								crop_marks: marks,
								scale,
								...(st.pdfVector ? { vector: true } : {}),
							});
							if (stop) {
								await engine.pdfFinish();
								return cancelled();
							}
							diagnostics.push(...r.diagnostics);
							tick();
						}
						const r = await engine.pdfFinish();
						if (r.bin.length) out[pdfPath(t.set)] = r.bin;
					}
					if (localSheet) {
						const many =
							sheetCount(t.cards.length, st.sheetCols, st.sheetRows) > 1;
						let n = 0;
						let open = false;
						const close = async () => {
							const r = await engine.sheetFinish();
							open = false;
							if (!r.bin.length) return;
							n++;
							out[sheetPath(t.set, n, many)] = r.bin;
							run.log(
								`Sheet ${n} of '${info.design_name}': ${r.cards} card(s), ${r.width} × ${r.height} px`,
							);
						};
						for (const i of t.cards) {
							if (!open) {
								await engine.sheetBegin(st.sheetCols, st.sheetRows);
								open = true;
							}
							const r = await engine.sheetCard({
								set: t.set,
								card: i,
								...clock,
								scale,
							});
							if (stop) {
								await engine.sheetFinish();
								return cancelled();
							}
							diagnostics.push(...r.diagnostics);
							tick();
							if (r.full) await close();
						}
						if (open) await close();
					}
				}
				if (area === 1 && localPng && passes === 1)
					perCardMs = (Date.now() - t0) / Math.max(1, plan.cards);
				run.log(`Rendered in ${formatMs(Date.now() - t0)}`);
			}
			// Problems in a design come back with every card; keep one of each.
			const seen = new Set<string>();
			const problems = diagnostics.filter((d) => {
				const key = JSON.stringify(d);
				if (seen.has(key)) return false;
				seen.add(key);
				return true;
			});
			const names = Object.keys(out);
			if (!names.length) {
				if (problems.length) showDiagnostics(problems);
				run.fail("Nothing was drawn; see the problems panel.");
				return;
			}
			run.step(at.pack);
			await new Promise((r) => setTimeout(r, 0));
			let fileName = plan.fileName;
			let bytes: Uint8Array;
			if (plan.zip) bytes = zipSync(out, { level: 0 });
			else {
				bytes = out[names[0]];
				fileName = plan.fileName;
			}
			run.step(at.pack + 1, formatBytes(bytes.length));
			const ext = fileName.slice(fileName.lastIndexOf(".") + 1);
			download(fileName, bytes, mimeOf[ext] ?? "application/zip");
			const errs = errorCount(problems);
			status =
				`Exported ${names.length} file(s)` +
				(errs ? ` with ${errs} error(s)` : "") +
				(plan.skipped.length
					? `; skipped ${plan.skipped.length} design(s) with errors`
					: "");
			if (errs) {
				showDiagnostics(problems);
				run.log(`${errs} error(s); see the problems panel`, "error");
			}
			run.finish(`Saved ${fileName} (${formatBytes(bytes.length)})`);
		} catch (e) {
			if ((e as Error).name === "AbortError") cancelled();
			else run.fail(`Could not export: ${(e as Error).message}`);
		} finally {
			busy = "";
		}
	}

	const typeLabels: Record<LayerType, string> = {
		rect: "Rect",
		ellipse: "Ellipse",
		text: "Text",
		image: "Image",
		qr: "QR code",
		polygon: "Polygon",
	};
</script>

<svelte:document onvisibilitychange={onHide} />
<svelte:window
	onfocus={checkFolder}
	bind:innerWidth={winW}
	bind:innerHeight={winH}
	onkeydown={onKey}
	oncopy={(e) => onCopy(e)}
	oncut={(e) => onCopy(e, true)}
	onpaste={onPaste}
/>

{#snippet previewBar()}
	<span class="pick">
		<Select
			value={setName}
			caption="Design"
			label="Design file"
			title="The design (card layout) being edited, with its card set"
			searchable={sets.length > 4}
			options={[
				...groupSets(sets).map((s) => ({
					value: s.name,
					label: s.design_name,
					group: sets.some((o) => o.group !== sets[0].group)
						? s.group
						: undefined,
					detail: `${s.cards.length} card${s.cards.length === 1 ? "" : "s"} · ${s.cards_file ?? s.name}`,
				})),
				{
					value: newDesignOption,
					label: "New design…",
					detail: "with its own card file",
					action: true,
					divider: true,
				},
			]}
			onchange={(v) => {
				if (v === newDesignOption) {
					newDesign();
					return;
				}
				setName = v;
				cardIndex = 0;
				selectedLayers = [];
				renderPreview();
			}}
		/>
		<CardPicker
			cards={currentSet?.cards ?? []}
			params={currentSet?.params ?? []}
			qa={qaStatuses}
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
	<span class="edit">
		<div class="btn-group mode" role="tablist" aria-label="View">
			<button
				role="tab"
				aria-selected={mode === "build"}
				class:active={mode === "build"}
				onclick={() => (mode = "build")}
				title="Build the design visually">Builder</button
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
		<div class="btn-group history" role="group" aria-label="History">
			<button
				onclick={undo}
				disabled={!undoStack.length}
				aria-label="Undo"
				title="Undo (Ctrl+Z)"><Icon name="undo" /></button
			>
			<button
				onclick={redo}
				disabled={!redoStack.length}
				aria-label="Redo"
				title="Redo (Ctrl+Shift+Z)"><Icon name="redo" /></button
			>
		</div>
	</span>
{/snippet}

{#snippet filesPanel()}
	<FileBrowser
		{files}
		{dirty}
		saveTarget={folder?.name ?? null}
		uses={fileUses}
		usedBy={fileUsedBy}
		problems={fileProblems}
		bind:selected={filesSelected}
		bind:folder={uploadFolder}
		highlight={filesHighlight}
		onopen={openFromBrowser}
		onrename={(from, to) => movePaths([[from, to]])}
		ondelete={deletePath}
		onmove={(paths, folder) =>
			movePaths(paths.map((p) => [p, join(folder, baseOf(p))]))}
		onnewfolder={newFolder}
		onnewdesign={newDesign}
		onnewcards={newCardFile}
		onupload={uploadTo}
		onduplicate={duplicateFile}
		ondropfiles={(list, folder) => importFiles(list, folder)}
	/>
	{#if mode === "build" && filesSelected && files.has(filesSelected)}
		{@const f = filesSelected}
		{@const n = fileUses.get(f) ?? 0}
		<div class="file-info">
			<div class="file-name mono" title={f}>{f}</div>
			{#if fontFaces[f]}
				<div
					class="font-preview"
					style:font-family={`"${fontFaces[f]}"`}
					title="Preview of the font"
				>
					<span class="font-preview-big">AaBbCc 123</span>
					<span>{fontSample}</span>
				</div>
			{/if}
			{#if filesPreviewUrl}<img
					class="file-preview"
					class:vector={isSvg(f)}
					src={filesPreviewUrl}
					alt={f}
					onload={(e) => {
						const img = e.currentTarget as HTMLImageElement;
						filesPreviewSize = {
							url: img.src,
							w: img.naturalWidth,
							h: img.naturalHeight,
						};
					}}
				/>{/if}
			<div class="muted small file-details">
				{filesSelectedKind} · <span
					>{formatSize(files.get(f)?.length ?? 0)}</span
				>{#if n}{" · "}<span
						class="used-by"
						title={`Used by:\n${(fileUsedBy.get(f) ?? []).join("\n")}`}
						>used by {n} file{n === 1 ? "" : "s"}</span
					>{/if}
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
					><Icon name="expand" /> Browse</button
				>
			</div>
			<CardList
				cards={currentSet.cards}
				params={currentSet.params}
				qa={qaStatuses}
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
						aria-label="Duplicate this card"
						><Icon name="copy" /></button
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
						aria-label="Move the card down"
						><Icon name="down" /></button
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
						aria-label="Delete this card"
						><Icon name="trash" /></button
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
			{#if currentCard}
				<QaControl
					status={qaStatuses[cardIndex] ?? "unreviewed"}
					entry={qaEntry}
					onmark={reviewCard}
					oncomment={addComment}
					onedit={editComment}
					onremove={removeComment}
					{pinTarget}
					onpin={(id) => {
						pinTarget = id;
						if (id) qaActive = id;
					}}
					active={qaActive}
					onactive={(id) => (qaActive = id)}
					onkeys={() => (qaKeysOpen = true)}
					onoverview={() => (qaOverviewOpen = true)}
					bind:composer={qaComposer}
				/>
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
		style:--preview-w={previewW ? `${previewW}px` : "minmax(320px, 1fr)"}
		class:build={mode === "build"}
		class:dropping
		ondragover={onDragOver}
		ondragleave={(e) => {
			if (!e.relatedTarget) dropping = false;
		}}
		ondrop={onDrop}
		role="application"
	>
		{#if folderNotice}
			<div class="folder-toast" role="alert" data-testid="folder-notice">
				<Icon name="alert" />
				<span class="msg">{folderNoticeText}</span>
				<span class="actions">
					{#if folderNotice.kind === "permission"}
						<button onclick={allowFolder}>Allow access</button>
					{:else if folderNotice.kind === "changed"}
						<button onclick={reloadFromFolder}>Reload from folder</button>
						<button onclick={keepProjectVersion}>Keep project version</button>
					{:else if folderNotice.kind === "conflict"}
						<button onclick={reloadFromFolder}>Use folder version</button>
						<button onclick={keepProjectVersion}>Use project version</button>
					{:else}
						<button onclick={flushFolder}>Try again</button>
					{/if}
					<button onclick={unlinkFolder}>Unlink</button>
				</span>
			</div>
		{/if}
		<header class="top">
			<span class="brand"><Logo size={26} /></span>
			<span class="ver">{engine.version}</span>
			{#if channel}
				<span
					class="channel"
					title="Preview build from the {channel} branch: newer than the latest release and not as well tested"
					>{channel.toUpperCase()}</span
				>
			{/if}
			<button
				class="project-btn"
				onclick={projectMenu}
				aria-haspopup="menu"
				title="Project: new, open, add designs and files, save, export, saved projects and examples"
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
				title={folder
					? `Linked to the folder '${folder.name}': changes are written to the files in it. The browser does not reveal where that folder is (a network drive works too), so check the folder itself. A copy is also kept in this browser. Nothing is sent to a server.`
					: "Projects are saved in this browser only; their content is never sent to a server. Use Export project file in the project menu to keep a copy elsewhere."}
			>
				{#if saveState === "saved"}<Icon name="check" />{:else if saveState === "unsaved"}<span class="dot" aria-hidden="true"></span>{:else if saveState === "error"}<Icon name="alert" />{/if}
				<span class="text"
					>{saveState === "saving"
						? "Saving…"
						: saveState === "saved"
							? folder
								? `Saved to folder ${folder.name}`
								: "Saved in this browser"
							: saveState === "unsaved"
								? "Unsaved"
								: saveState === "error"
									? "Not saved"
									: "Example (saved once you change it)"}</span
				>
			</span>
			<span class="spacer"></span>
			<span class="exports">
				<span class="btn-group" role="group" aria-label="Export">
					<span class="group-cap" aria-hidden="true"
						><Icon name="download" /> Export</span
					>
					<button
						onclick={exportPng}
						title="Export the card shown ({currentCard?.id ??
							'none'}) as a PNG image, rendered in this browser"
						disabled={!!busy || !currentSet?.ok || !currentCard}>PNG</button
					>
					<button
						onclick={exportZip}
						disabled={!!busy || !currentSet?.ok}
						title="Export all {currentSet?.cards.length ??
							0} cards of this design as PNG images in one ZIP{onServer
							? ', rendered on the server'
							: ''}">ZIP</button
					>
					<button
						onclick={exportPdf}
						disabled={!!busy || !currentSet?.ok}
						title="Export all {currentSet?.cards.length ??
							0} cards of this design in one PDF, one vector page per card, sharp at any zoom (with crop marks when the design has a bleed){onServer
							? ', rendered on the server'
							: ''}">PDF</button
					>
					<button
						bind:this={exportButton}
						onclick={openExport}
						disabled={!!busy || !sets.length}
						aria-haspopup="dialog"
						title="More formats and options: JPEG, WebP, SVG, vector PDF, 16-bit PNG, a higher resolution, crop marks, or every design at once"
						>Export…</button
					>
				</span>
				{#if server?.render}
					<label
						class="switch server"
						title="ZIP and PDF exports are rendered by the yoshida server this editor comes from, instead of in this browser. The project files are uploaded, the server renders with all its CPU cores and the result is downloaded; the progress window shows each step. PNG always renders here."
					>
						<input type="checkbox" role="switch" bind:checked={useServer} />
						<Icon name="cloud" />
						<span>Render on server</span>
					</label>
				{/if}
			</span>
			{#if folder}
				<span
					class="folder-chip"
					class:warn={!!folderNotice}
					data-testid="folder-chip"
					title="Linked to the folder {folder.name}: changes are written there as you make them, and changes made outside the editor are offered for reload"
				>
					<Icon name={folderNotice ? "alert" : "folder"} />
					<span class="text"
						>{folder.name} · {folderNotice
							? "needs attention"
							: folderWriting || dirty.size
								? "writing…"
								: "in sync"}</span
					>
				</span>
			{/if}
			<button
				class="fn-btn"
				onclick={() =>
					functionsRef.open ? closeFunctions() : openFunctions()}
				aria-pressed={functionsRef.open}
				title="Function reference: every function with a short example (F1)"
				><span class="fn-mark" aria-hidden="true">ƒ</span> Functions</button
			>
			<button
				class="fn-btn"
				onclick={openPrivacy}
				aria-pressed={telemetry.settingsOpen}
				data-testid="privacy-button"
				title="Privacy and usage statistics: what is counted on the server that hosts this editor, and what this browser sent"
				><Icon name="lock" /> Privacy</button
			>
			<ThemeToggle />
		</header>

		{#if mode === "build"}
			<aside class="left">
				<div class="tabs tabbar" role="tablist">
					<button
						role="tab"
						aria-selected={leftTab === "layers"}
						class:active={leftTab === "layers"}
						onclick={() => (leftTab = "layers")}>Layers</button
					>
					<button
						role="tab"
						aria-selected={leftTab === "params"}
						class:active={leftTab === "params"}
						onclick={() => (leftTab = "params")}>Params</button
					>
					<button
						role="tab"
						aria-selected={leftTab === "card"}
						class:active={leftTab === "card"}
						onclick={() => (leftTab = "card")}>Card data</button
					>
					<button
						role="tab"
						aria-selected={leftTab === "files"}
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
							reveal={layerReveal}
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
						onrenameitemoption={renameItemOptionEverywhere}
						focus={paramFocus}
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
						oncreate={createSampleCards}
						createPath={sampleCardsPath}
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
					<span class="adds">
						<span
							class="btn-group group"
							role="group"
							aria-label="Add layer"
						>
							<span class="group-cap" aria-hidden="true"
								><Icon name="plus" /> Add</span
							>
							{#each layerTypes as t}
								{@const ic = layerIcon(t)}
								<button
									disabled={!doc}
									onclick={() => addLayer(t)}
									aria-label="Add a {t} layer"
									title="Add a {t} layer"
									>{#if ic}<Icon name={ic} />{/if}<span
										class="lbl"
										aria-hidden="true">{typeLabels[t]}</span
									></button
								>
							{/each}
							<button
								class="add-component"
								disabled={!doc}
								onclick={(e) => {
									const b = e.currentTarget.getBoundingClientRect();
									componentMenu(b.left, b.bottom + 4);
								}}
								aria-label="Include a component"
								title="Include a component: layers shared between designs"
								><Icon name="component" /><span
									class="lbl"
									aria-hidden="true">Component</span
								></button
							>
						</span>
					</span>
					<span class="sep"></span>
					{@render previewBar()}
				</div>
				<Stage
					{image}
					size={imageSize}
					sprite={dragSprite}
					onview={(v) => (stageShown = v)}
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
					pins={qaPins}
					pinning={!!pinTarget}
					onpin={placePin}
					onpinselect={(id) => (qaActive = id)}
				/>
				{#if loading}
					<div class="loading" role="status" aria-live="polite">
						<span class="spinner" aria-hidden="true"></span>
						<strong>Opening {loading.name}…</strong>
						<span class="muted"
							>Step {loading.step + 1} of {loadSteps.length}: {loading.label}</span
						>
						<span
							class="loadbar"
							role="progressbar"
							aria-valuemin="0"
							aria-valuemax={loadSteps.length}
							aria-valuenow={loading.step}
							><span
								style:width="{((loading.step + 0.5) / loadSteps.length) * 100}%"
							></span></span
						>
					</div>
				{/if}
				<div class="status">
					<span class="status-text">{busy || status}</span>
					<Select
						compact
						caption="Preview"
						label="Preview quality"
						title="How many pixels the preview renders. Sharp on screen matches the zoom; exports always render at full size."
						value={previewQuality}
						options={(
							Object.keys(qualityLabels) as PreviewQuality[]
						).map((q) => ({ value: q, label: qualityLabels[q] }))}
						onchange={(v) => setPreviewQuality(v as PreviewQuality)}
					/>
					<Select
						compact
						caption="Drag"
						label="Drag preview"
						title="What the picture shows while layers are dragged. Live re-renders the whole card at the pointer, so layers above and below and layers that depend on the moved ones are right. Fast keeps the card still and moves only the dragged layers, drawn in their place in the stack; layers that depend on them follow on release. Fast switches to Live automatically for layers inside repeated or effect groups."
						value={dragPreview}
						options={(Object.keys(dragLabels) as DragPreview[]).map((m) => ({
							value: m,
							label: dragLabels[m],
						}))}
						onchange={(v) => setDragPreview(v as DragPreview)}
					/>
				</div>
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
						{fontFaces}
						{fontLicenses}
						fontText={fontLayer?.text ?? ""}
						onfonts={openFonts}
						onopenfile={openFileInCode}
						{componentUsers}
						ondetach={detachComponent}
						oncreatecomponent={createComponent}
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
						onback={() => (selectedLayers = [])}
						{listKeys}
						cardValues={currentCard?.values}
						focus={inspectorFocus}
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
				<div class="tabs tabbar" role="tablist">
					<button
						role="tab"
						aria-selected={sidePanel === "card"}
						class:active={sidePanel === "card"}
						onclick={() => (sidePanel = "card")}>Card</button
					>
					<button
						role="tab"
						aria-selected={sidePanel === "files"}
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
						oncreate={createSampleCards}
						createPath={sampleCardsPath}
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
						<img
							class:vector={isSvg(selected!)}
							src={imageUrl}
							alt={selected}
						/>
					</div>
				{:else if selected && fontFaces[selected]}
					<div
						class="font-view"
						style:font-family={`"${fontFaces[selected]}"`}
					>
						<p class="font-view-name">
							{describeFile(
								selected,
								files.get(selected) ?? new Uint8Array(),
							)}
						</p>
						<p class="font-view-glyphs">
							ABCDEFGHIJKLMNOPQRSTUVWXYZ<br />
							abcdefghijklmnopqrstuvwxyz<br />
							0123456789 .,:;!?&amp;@#%()+-=/
						</p>
						{#each [48, 32, 24, 16] as size (size)}
							<p style:font-size={`${size}px`}>{fontSample}</p>
						{/each}
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
					size={imageSize}
					onview={(v) => (stageShown = v)}
					{layout}
					selected={[]}
					handles={() => "none"}
					{locked}
					{stale}
					staleNote={status}
					interactive={false}
					onselect={() => {}}
					ongesture={() => {}}
					pins={qaPins}
					pinning={!!pinTarget}
					onpin={placePin}
					onpinselect={(id) => (qaActive = id)}
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
				oncheckall={checkAllCards}
				checkDisabled={!!busy || !currentSet?.ok}
				cardCount={currentSet?.cards.length ?? 0}
			/>
		</footer>
	</div>
{/if}

{#if exportOpen}
	<ExportDialog
		initial={exportSettings}
		project={projectName}
		sets={planSets}
		current={setName}
		card={cardIndex}
		webp={webpOk}
		webpLossless={webpLosslessOk}
		canServer={!!server?.render}
		measuring={exportMeasuring}
		bind:useServer
		onexport={exportWith}
		onclose={closeExport}
	/>
{/if}

{#if settingsOpen}
	<Window
		key="project-settings"
		title="Project settings"
		width={380}
		fit
		onclose={() => (settingsOpen = false)}
	>
		<div class="settings">
			<label class="offset">
				<span>UTC offset (hours)</span>
				<input
					type="number"
					step="0.25"
					min={-UTC_OFFSET_LIMIT}
					max={UTC_OFFSET_LIMIT}
					value={offsetText}
					onchange={(e) => {
						// A bad entry leaves the field showing the stored offset, next to its error.
						if (!offsetEntered(e.currentTarget.value))
							e.currentTarget.value = offsetText;
					}}
				/>
			</label>
			<p class="note">
				The core uses this offset with the UTC time of each render for
				render.date and render.time. Empty or 0 means UTC.
			</p>
			<button
				type="button"
				onclick={() => setUtcOffset(-new Date().getTimezoneOffset() / 60 || 0)}
			>Use my browser's offset</button>
			{#if offsetError}<p class="err" role="alert">{offsetError}</p>{/if}
			<label class="offset">
				<span>Your name for reviews</span>
				<input
					type="text"
					maxlength="60"
					placeholder="Optional, e.g. a username"
					value={reviewer}
					onchange={(e) => setReviewer(e.currentTarget.value)}
				/>
			</label>
			<p class="note">
				Written next to the marks and comments you add in card review.
				It is kept in this browser only, not in the project.
			</p>
		</div>
	</Window>
{/if}

{#if qaKeysOpen}
	<Window
		key="qa-keys"
		title="Card review keys"
		width={380}
		fit
		onclose={() => (qaKeysOpen = false)}
	>
		<div class="qa-keys">
			<p class="note">Work when the focus is not in a text field.</p>
			<table>
				<tbody>
					<tr><td><kbd>J</kbd> / <kbd>K</kbd></td><td>Next / previous card</td></tr>
					<tr><td><kbd>]</kbd> / <kbd>[</kbd></td><td>Next / previous design</td></tr>
					<tr><td><kbd>U</kbd></td><td>Next card that needs review</td></tr>
					<tr><td><kbd>A</kbd></td><td>Approve (needs no open comments)</td></tr>
					<tr><td><kbd>N</kbd></td><td>Needs changes</td></tr>
					<tr><td><kbd>X</kbd></td><td>Remove the mark</td></tr>
					<tr><td><kbd>C</kbd></td><td>Write a comment</td></tr>
					<tr><td><kbd>P</kbd></td><td>Pin the selected comment: then click the card</td></tr>
					<tr><td><kbd>O</kbd></td><td>Overview of all comments</td></tr>
					<tr><td><kbd>?</kbd></td><td>This list</td></tr>
					<tr><td><kbd>Esc</kbd></td><td>Cancel pinning, close this window</td></tr>
				</tbody>
			</table>
		</div>
	</Window>
{/if}

{#if qaOverviewOpen}
	<Window
		key="qa-overview"
		title="Card review overview"
		width={620}
		height={440}
		onclose={() => (qaOverviewOpen = false)}
	>
		<div class="qa-overview">
			{#if !qaRows.length}
				<p class="note">Nothing reviewed yet. Approve a card or write a comment on it.</p>
			{/if}
			{#each qaRows as r (r.set + "/" + r.id)}
				<button
					class="row"
					onclick={() => {
						goToCard(r.set, r.index);
						qaOverviewOpen = false;
					}}
				>
					<span class="head"
						><QaBadge status={r.status} text />
						<strong>{r.id}</strong>
						<span class="muted">{r.setLabel}</span></span
					>
					{#each r.entry.comments ?? [] as c, i}
						<span class="c" class:done={c.resolved}
							>{i + 1}. {c.text}
							{#if c.by}<span class="muted">· {c.by}</span>{/if}</span
						>
					{/each}
				</button>
			{/each}
		</div>
	</Window>
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

{#if fontsTarget && doc}
	{#key fontsTarget}
	<FontsWindow
		{files}
		{doc}
		layer={fontLayer}
		target={fontsTarget}
		onapply={applyFonts}
		onclose={() => (fontsTarget = null)}
	/>
	{/key}
{/if}

{#if telemetry.settingsOpen}
	<TelemetryWindow />
{/if}

{#if server?.telemetry?.enabled && noticeDue() && !telemetry.settingsOpen}
	<TelemetryNotice />
{/if}

{#if functionsRef.open}
	{#key functionsRef.nonce}
		<FunctionsWindow
			query={functionsRef.query}
			userFunctions={designFunctions}
			onclose={closeFunctions}
		/>
	{/key}
{/if}

<DialogHost />
<MenuHost />
<ProgressHost />
<TooltipHost />

<style>
	/* Splitters are the 1px lines between the panels (their own grid
	   tracks); the panels draw no border on those sides. */
	.app {
		display: grid;
		grid-template-columns: var(--files-w) 1px minmax(300px, 1fr) 1px var(
				--preview-w
			);
		grid-template-rows: auto minmax(0, 1fr) 1px var(--bottom-h);
		grid-template-areas:
			"top top top top top"
			"files fsplit editor psplit preview"
			"files fsplit bsplit bsplit bsplit"
			"files fsplit problems problems problems";
		height: 100vh;
	}
	.app.build {
		grid-template-columns: var(--left-w) 1px minmax(360px, 1fr) 1px var(
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
	/* Panels are columns, so the Files panel can fill the free height and
	   scroll its tree only. */
	.files,
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
		display: inline-flex;
		align-items: center;
		gap: 4px;
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
		flex: none;
		background: var(--bg);
	}
	.file-name {
		font-size: 12px;
		word-break: break-all;
	}
	.file-preview {
		max-width: 100%;
		/* Leaves room for the file tree on short windows. */
		max-height: min(180px, 25vh);
		object-fit: contain;
		align-self: center;
		background: repeating-conic-gradient(#ccc 0 25%, #eee 0 50%) 0 0 / 12px
			12px;
	}
	/* An SVG has no pixel size to show it at: it fills the preview area. */
	.file-preview.vector {
		width: 100%;
		height: min(180px, 25vh);
	}
	.font-preview {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 6px 8px;
		border: 1px solid var(--line);
		border-radius: 6px;
		font-size: 14px;
		line-height: 1.3;
		overflow: hidden;
	}
	.font-preview span {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.font-preview-big {
		font-size: 26px;
	}
	.small {
		font-size: 11px;
	}
	/* Keeps "61 KB" and "used by 3 files" whole when the line wraps. */
	.file-details span {
		white-space: nowrap;
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
	.top .btn-group {
		flex: none;
		white-space: nowrap;
		height: var(--ctl-h);
		box-sizing: border-box;
	}
	.top > button {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}
	.history > button {
		width: 32px;
		padding: 0;
	}
	.brand {
		display: inline-flex;
		align-items: center;
		flex: none;
		color: var(--fg);
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
	.fn-btn {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		height: var(--ctl-h);
		box-sizing: border-box;
		font-size: 12px;
	}
	.fn-btn[aria-pressed="true"] {
		border-color: var(--accent);
		background: var(--sel);
	}
	.fn-mark {
		font: italic 600 14px var(--mono);
		color: var(--accent);
	}
	.folder-chip {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-size: 12px;
		color: var(--muted);
		white-space: nowrap;
		overflow: hidden;
		max-width: 16em;
	}
	.folder-chip .text {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.folder-chip.warn {
		color: var(--warn);
	}
	.folder-toast {
		position: fixed;
		left: 50%;
		bottom: 40px;
		transform: translateX(-50%);
		z-index: 60;
		display: flex;
		align-items: center;
		gap: 10px;
		max-width: min(92vw, 720px);
		padding: 8px 12px;
		border: 1px solid var(--warn);
		border-radius: 8px;
		background: var(--bg);
		color: var(--fg);
		font-size: 12px;
		box-shadow: 0 6px 24px rgba(0, 0, 0, 0.25);
	}
	.folder-toast .msg {
		min-width: 0;
		overflow-wrap: anywhere;
	}
	.folder-toast .actions {
		display: flex;
		gap: 6px;
		flex: none;
	}
	.saved {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-size: 12px;
		color: var(--muted);
		white-space: nowrap;
		overflow: hidden;
		max-width: 16em;
	}
	.saved .text {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.saved .dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: currentColor;
		flex: none;
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
	/* Marks a preview build; release builds have no channel. */
	.channel {
		margin-left: -4px;
		padding: 1px 5px;
		border-radius: 4px;
		background: #d92d20;
		color: #fff;
		font-size: 10px;
		font-weight: 700;
		letter-spacing: 0.06em;
		line-height: 1.4;
		cursor: default;
	}
	.spacer {
		flex: 1;
	}
	.files,
	.left {
		overflow: auto;
		min-height: 0;
	}
	.files {
		grid-area: files;
	}
	.left {
		grid-area: left;
	}
	/* Over the preview while a project opens. It fades in after a moment, so
	   a project that opens at once never flashes it. */
	.loading {
		position: absolute;
		inset: 0;
		z-index: 5;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 10px;
		background: color-mix(in srgb, var(--bg) 82%, transparent);
		opacity: 0;
		animation: load-in 0.2s ease 0.35s forwards;
	}
	.loading .spinner {
		width: 28px;
		height: 28px;
		border: 3px solid var(--line);
		border-top-color: var(--accent);
		border-radius: 50%;
		animation: load-spin 0.8s linear infinite;
	}
	.loadbar {
		width: 220px;
		height: 4px;
		border-radius: 2px;
		background: var(--line);
		overflow: hidden;
	}
	.loadbar > span {
		display: block;
		height: 100%;
		background: var(--accent);
		transition: width 0.25s ease;
	}
	@keyframes load-in {
		to {
			opacity: 1;
		}
	}
	@keyframes load-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.loading .spinner {
			animation: none;
		}
		.loading {
			animation-duration: 0.01s;
		}
	}
	.right {
		grid-area: right;
		overflow: auto;
		min-height: 0;
	}
	.center {
		grid-area: center;
		position: relative;
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
		overflow: hidden;
		container-type: inline-size;
	}
	/* Toolbars wrap whole groups, never single buttons; the editing
	   switch and undo/redo stay on the right. Same height as the tab
	   strip beside them (.tabbar). */
	.toolbar,
	.pane-title.row {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		align-items: center;
		min-height: var(--bar-h);
		box-sizing: border-box;
		padding: 6px 10px;
		border-bottom: 1px solid var(--line);
	}
	.adds,
	.pick,
	.edit,
	.exports {
		display: flex;
		gap: 8px;
		align-items: center;
		flex: none;
	}
	.toolbar :global(.btn-group),
	.pane-title.row :global(.btn-group) {
		height: var(--ctl-h);
		box-sizing: border-box;
	}
	.pick {
		gap: 6px;
		flex: 0 1 auto;
		flex-wrap: wrap;
		min-width: 0;
	}
	.edit {
		margin-left: auto;
	}
	.exports {
		gap: 12px;
	}
	/* Every button in a group has the same padding, icon box and gap. */
	.toolbar .group button {
		padding: 0 10px;
		gap: 6px;
	}
	.exports .btn-group button {
		padding: 0 11px;
		font-weight: 500;
	}
	.group-cap {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 0 9px 0 8px;
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--muted);
		background: var(--bg-bar);
	}
	/* A narrow stage keeps the layer buttons as icons (names in the tooltip). */
	@container (max-width: 1180px) {
		.toolbar .group .lbl {
			display: none;
		}
		.toolbar .group button {
			padding: 0 8px;
		}
	}
	.sep {
		width: 1px;
		align-self: stretch;
		background: var(--line);
		margin: 0 4px;
	}
	.editor-pane {
		grid-area: editor;
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
	}
	.editor-pane > :global(.editor) {
		flex: 1;
	}
	/* Same height as the tab strips beside it, so the lines under them meet. */
	.pane-title {
		flex: none;
		height: var(--bar-h);
		box-sizing: border-box;
		padding: 0 12px;
		font: 12px/calc(var(--bar-h) - 1px) var(--mono);
		border-bottom: 1px solid var(--line);
		color: var(--muted);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.pane-title.row {
		height: auto;
		font: inherit;
		color: inherit;
		padding: 6px 12px;
		white-space: normal;
		overflow: visible;
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
	.image-view img.vector {
		width: 100%;
		max-height: 70vh;
		object-fit: contain;
	}
	.font-view {
		overflow: auto;
		padding: 16px 20px;
		line-height: 1.25;
	}
	.font-view p {
		margin: 0 0 14px;
	}
	.font-view-name {
		font-family: system-ui, sans-serif;
		font-size: 12px;
		color: var(--muted);
	}
	.font-view-glyphs {
		font-size: 28px;
		word-break: break-all;
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
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 12px;
		font-size: 12px;
		color: var(--muted);
		border-top: 1px solid var(--line);
	}
	.status-text {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.problems-pane {
		grid-area: problems;
		min-height: 0;
	}
	.server :global(svg) {
		color: var(--muted);
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
		/* The Files panel takes its whole share, so its tree has room to
		   scroll between the bar and the footer. */
		.files:has(:global(.browser)),
		.left:has(:global(.browser)) {
			height: 50vh;
		}
		.file-preview {
			max-height: 10vh;
		}
		.file-preview.vector {
			height: 10vh;
		}
		/* Without splitters the stacked panels need their own dividers. */
		.files,
		.left,
		.right,
		.editor-pane,
		.problems-pane {
			border-top: 1px solid var(--line);
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
	.settings {
		display: grid;
		gap: 12px;
		padding: 4px 2px;
	}
	.settings .offset {
		display: grid;
		grid-template-columns: 1fr 120px;
		align-items: center;
		gap: 8px;
	}
	.settings .offset input {
		width: 100%;
	}
	.settings .note {
		margin: 0;
		color: var(--muted);
		font-size: 12px;
	}
	.settings .err {
		margin: 0;
		color: var(--err);
		font-size: 12px;
	}
	.settings button {
		justify-self: start;
	}
	.qa-keys table {
		width: 100%;
		border-collapse: collapse;
		font-size: 13px;
	}
	.qa-keys td {
		padding: 3px 6px;
	}
	.qa-keys kbd {
		border: 1px solid var(--muted);
		border-radius: 3px;
		padding: 0 5px;
	}
	.qa-overview {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 8px;
		font-size: 13px;
	}
	.qa-overview .row {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		text-align: left;
		padding: 6px 8px;
	}
	.qa-overview .head {
		display: flex;
		gap: 8px;
		align-items: center;
	}
	.qa-overview .c.done {
		text-decoration: line-through;
		color: var(--muted);
	}
</style>
