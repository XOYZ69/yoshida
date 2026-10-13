<script lang="ts" module>
export type FontAdd = { path: string; data: Uint8Array };
export type FontsTarget = {
	tab?: "project" | "google";
	path?: string;
	upload?: boolean;
};
</script>

<script lang="ts">
// The Fonts window: find, preview, upload and import fonts, and use them
// in the design. "In project" lists the font files of the project (offline);
// "Google Fonts" browses the bundled catalog once the user allows it.
import { tick } from "svelte";
import type { Files } from "../project";
import { bytesOf, textOf } from "../project";
import { freePath } from "../paths";
import { loadPref, savePref } from "../ui/drag";
import Select from "../ui/Select.svelte";
import Window from "../ui/Window.svelte";
import {
	CATEGORIES,
	type Category,
	downloadLicense,
	downloadStyle,
	type Family,
	fileStem,
	fontName,
	LICENSES,
	loadCatalog,
	mainStyle,
	previewFamily,
	search,
	type Style,
	styleLabel,
} from "./catalog";
import {
	fontFileRe,
	fontWarning,
	freeFontName,
	layersUsing,
	licenseKind,
	licensePathFor,
	nameForFile,
	previewFace,
	projectFont,
	webFontRe,
} from "./project";
import { drawable, fontFormat } from "./sfnt";

let {
	files,
	doc,
	layer = null,
	target = {},
	onapply,
	onclose,
}: {
	files: Files;
	/** The design being edited (its `fonts` and layers). */
	doc: Record<string, unknown>;
	/** The selected text layer, which "use" switches to the chosen font. */
	layer?: { id: string; font: string; text: string } | null;
	target?: FontsTarget;
	/** Writes files, declares font names and sets the layer's font, as one undo step. */
	onapply: (add: FontAdd[], declare: Record<string, string>, use: string | null) => Promise<void>;
	onclose: () => void;
} = $props();

const FOLDER = "assets/fonts";
const SIZES = { S: 15, M: 28, L: 48 } as const;
type Size = keyof typeof SIZES;
const ROW = { S: 34, M: 52, L: 78 } as const;
const identRe = /^[A-Za-z_][A-Za-z0-9_]*$/;

const prefs = loadPref("yoshida.fonts", { size: "M" as Size, google: "" as "" | "allowed" | "declined" });
// svelte-ignore state_referenced_locally
let size = $state<Size>(SIZES[prefs.size] ? prefs.size : "M");
// svelte-ignore state_referenced_locally
let google = $state(prefs.google);
function savePrefs() {
	savePref("yoshida.fonts", { size, google });
}

const declared = $derived(
	doc.fonts && typeof doc.fonts === "object" && !Array.isArray(doc.fonts)
		? (doc.fonts as Record<string, unknown>)
		: {},
);
const fontPaths = $derived(
	[...files.keys()].filter((p) => fontFileRe.test(p)).sort((a, b) => a.localeCompare(b)),
);

// svelte-ignore state_referenced_locally
let tab = $state<"project" | "google">(target.tab ?? (target.path || fontPaths.length ? "project" : "google"));
let query = $state("");
let category = $state<Category | "">("");
// svelte-ignore state_referenced_locally
let previewText = $state(layer?.text || "");
const sampleText = $derived(previewText.trim() || "");
let status = $state("");
let busy = $state(false);

// ---------------------------------------------------------------- project list

type ProjectItem = { path: string; names: string[]; missing: boolean };

const projectItems = $derived.by((): ProjectItem[] => {
	const byPath = new Map<string, string[]>();
	for (const [name, p] of Object.entries(declared)) {
		const list = byPath.get(String(p)) ?? [];
		list.push(name);
		byPath.set(String(p), list);
	}
	const items: ProjectItem[] = fontPaths.map((path) => ({ path, names: byPath.get(path) ?? [], missing: false }));
	for (const [path, names] of byPath) if (!files.has(path)) items.push({ path, names, missing: true });
	const q = query.trim().toLowerCase();
	return q ? items.filter((i) => i.path.toLowerCase().includes(q) || i.names.some((n) => n.toLowerCase().includes(q))) : items;
});

// svelte-ignore state_referenced_locally
let projectSel = $state<string | null>(target.path ?? null);
const projectCur = $derived(projectItems.find((i) => i.path === projectSel) ?? projectItems[0] ?? null);
const projectInfo = $derived(projectCur && !projectCur.missing ? projectFont(files, projectCur.path) : null);

// CSS family per project font file, loaded from its bytes.
let faces = $state<Record<string, string | null>>({});
$effect(() => {
	for (const p of fontPaths) {
		const data = files.get(p);
		if (!data || p in faces) continue;
		previewFace(data).then((name) => {
			faces = { ...faces, [p]: name };
		});
	}
});

let newName = $state("");
$effect(() => {
	// A fresh name suggestion whenever another project font is shown.
	const cur = projectCur;
	newName = cur && projectInfo ? freeFontName(nameForFile(cur.path, projectInfo.info), Object.keys(declared)) : "";
});

const usedBy = $derived(projectCur ? projectCur.names.flatMap((n) => layersUsing(doc, n)) : []);

// ---------------------------------------------------------------- google list

let catalog = $state.raw<Family[] | null>(null);
let catalogError = $state("");

async function ensureCatalog() {
	if (catalog || google !== "allowed") return;
	try {
		catalogError = "";
		catalog = await loadCatalog();
	} catch (e) {
		catalogError = (e as Error).message;
	}
}
$effect(() => {
	if (tab === "google" && google === "allowed") ensureCatalog();
});

const googleItems = $derived(catalog ? search(catalog, query, category) : []);
let googleSel = $state<string | null>(null);
const googleCur = $derived(googleItems.find((f) => f.name === googleSel) ?? googleItems[0] ?? null);

// Preview text for Google previews settles before it is sent.
let googleText = $state("");
$effect(() => {
	const t = sampleText;
	const id = setTimeout(() => (googleText = t), 300);
	return () => clearTimeout(id);
});
let gfaces = $state<Record<string, string | null>>({});
// Previews asked for (not state: the template asks while it renders).
const asked = new Set<string>();
function googleFace(f: Family, s: Style) {
	const text = googleText || f.name;
	const key = `${f.name}|${s.key}|${text}`;
	if (!asked.has(key) && google === "allowed") {
		asked.add(key);
		previewFamily(f, s, text).then((name) => {
			if (name) gfaces = { ...gfaces, [key]: name };
		});
	}
	return gfaces[key] ?? null;
}

let chosen = $state<Record<string, boolean>>({});
let names = $state<Record<string, string>>({});
let licenseOpen = $state(false);
let licenseText = $state("");
$effect(() => {
	// Defaults for the family shown: its main style, names that are free.
	const f = googleCur;
	if (!f) return;
	const main = mainStyle(f);
	chosen = { [main.key]: true };
	const taken = new Set(Object.keys(declared));
	const n: Record<string, string> = {};
	for (const s of f.styles) {
		const want = fontName(f, s);
		const path = `${FOLDER}/${fileStem(f, s)}.ttf`;
		n[s.key] = declared[want] === path ? want : freeFontName(want, taken);
		taken.add(n[s.key]);
	}
	names = n;
	licenseOpen = false;
	licenseText = "";
});
const chosenStyles = $derived(googleCur ? googleCur.styles.filter((s) => chosen[s.key]) : []);

function nameError(name: string, own: string | null = null) {
	if (!identRe.test(name)) return "Use letters, digits and _, not starting with a digit.";
	const at = declared[name];
	if (at !== undefined && at !== own) return `"${name}" already names ${String(at).split("/").pop()}.`;
	return "";
}
const googleErrors = $derived(chosenStyles.map((s) => nameError(names[s.key] ?? "", `${FOLDER}/${googleCur ? fileStem(googleCur, s) : ""}.ttf`)).filter(Boolean));

async function toggleLicense() {
	licenseOpen = !licenseOpen;
	if (licenseOpen && !licenseText && googleCur) {
		licenseText = "Loading…";
		licenseText = await downloadLicense(googleCur).catch((e) => `Could not load the license: ${(e as Error).message}`);
	}
}

// ---------------------------------------------------------------- list (virtualized)

let listEl = $state<HTMLDivElement>();
let scrollTop = $state(0);
let listH = $state(400);
const rowH = $derived(ROW[size]);
const count = $derived(tab === "project" ? projectItems.length : googleItems.length);
const first = $derived(Math.max(0, Math.floor(scrollTop / rowH) - 4));
const last = $derived(Math.min(count, Math.ceil((scrollTop + listH) / rowH) + 4));
const activeIndex = $derived(
	tab === "project"
		? projectItems.findIndex((i) => i.path === projectCur?.path)
		: googleItems.findIndex((f) => f.name === googleCur?.name),
);

function pick(i: number) {
	if (i < 0 || i >= count) return;
	if (tab === "project") projectSel = projectItems[i].path;
	else googleSel = googleItems[i].name;
	status = "";
	const el = listEl;
	if (el) {
		if (i * rowH < el.scrollTop) el.scrollTop = i * rowH;
		else if ((i + 1) * rowH > el.scrollTop + el.clientHeight) el.scrollTop = (i + 1) * rowH - el.clientHeight;
	}
}

function listKey(e: KeyboardEvent) {
	const page = Math.max(1, Math.floor(listH / rowH) - 1);
	const i = activeIndex;
	const to: Record<string, number> = {
		ArrowDown: i + 1,
		ArrowUp: i - 1,
		PageDown: i + page,
		PageUp: i - page,
		Home: 0,
		End: count - 1,
	};
	if (e.key in to) {
		e.preventDefault();
		pick(Math.max(0, Math.min(count - 1, to[e.key])));
	} else if (e.key === "Enter") {
		e.preventDefault();
		primary.run?.();
	}
}

function switchTab(t: "project" | "google") {
	if (t !== tab) query = "";
	tab = t;
	status = "";
	scrollTop = 0;
	if (listEl) listEl.scrollTop = 0;
}

// ---------------------------------------------------------------- actions

/** The project path for a new font file: the same bytes reuse their file. */
function placeFor(want: string, data: Uint8Array, taken: Files): { path: string; add: boolean } {
	const same = taken.get(want);
	if (same && same.length === data.length && same.every((b, i) => b === data[i])) return { path: want, add: false };
	return { path: freePath(taken, want), add: true };
}

async function importGoogle() {
	const f = googleCur;
	if (!f || !chosenStyles.length || googleErrors.length) return;
	busy = true;
	status = `Downloading ${f.name}…`;
	try {
		const [license, ...datas] = await Promise.all([downloadLicense(f), ...chosenStyles.map((s) => downloadStyle(f, s))]);
		const taken = new Map(files);
		const add: FontAdd[] = [];
		const declare: Record<string, string> = {};
		const header = `${f.name}, from Google Fonts (https://fonts.google.com/specimen/${encodeURIComponent(f.name).replace(/%20/g, "+")}).\nLicense: ${LICENSES[f.license].name}.\n\n`;
		const licenseData = bytesOf(header + license);
		chosenStyles.forEach((s, i) => {
			const data = datas[i];
			if (!drawable(fontFormat(data))) throw new Error(`${f.name} ${styleLabel(s)} is not a TrueType file`);
			const at = placeFor(`${FOLDER}/${fileStem(f, s)}.ttf`, data, taken);
			if (at.add) {
				add.push({ path: at.path, data });
				taken.set(at.path, data);
			}
			const lp = licensePathFor(at.path);
			if (!taken.has(lp)) {
				add.push({ path: lp, data: licenseData });
				taken.set(lp, licenseData);
			}
			declare[names[s.key]] = at.path;
		});
		const use = layer ? names[chosenStyles[0].key] : null;
		await onapply(add, declare, use);
		status = `Imported ${chosenStyles.length === 1 ? names[chosenStyles[0].key] : `${chosenStyles.length} styles`}${use ? ` and set it on ${layer?.id}` : ""}. Undo with Ctrl+Z.`;
	} catch (e) {
		status = `Nothing was imported: ${(e as Error).message}. Check the connection and try again.`;
	} finally {
		busy = false;
		keepFocus();
	}
}

/** The busy primary button was disabled while focused, which drops focus to the page; take it back so Esc still closes. */
async function keepFocus() {
	await tick();
	if (!fwEl?.contains(document.activeElement)) (primaryEl ?? searchEl)?.focus();
}

async function useProject() {
	const cur = projectCur;
	if (!cur || cur.missing) return;
	if (cur.names.length) {
		if (!layer) return;
		await onapply([], {}, cur.names[0]);
		status = `${layer.id} now uses ${cur.names[0]}.`;
		return;
	}
	if (nameError(newName)) return;
	await onapply([], { [newName]: cur.path }, layer ? newName : null);
	status = `Added ${newName} to the design${layer ? ` and set it on ${layer.id}` : ""}.`;
}

async function saveEmbeddedLicense() {
	const f = projectInfo;
	if (!f) return;
	const text = [f.info.copyright, f.info.license, f.info.licenseUrl].filter(Boolean).join("\n\n");
	await onapply([{ path: licensePathFor(f.path), data: bytesOf(`${text}\n`) }], {}, null);
	status = `Saved ${licensePathFor(f.path)}.`;
}

let fileInput = $state<HTMLInputElement>();
let licenseInput = $state<HTMLInputElement>();

async function uploadFonts(list: FileList | File[]) {
	const taken = new Map(files);
	const add: FontAdd[] = [];
	const refused: string[] = [];
	let firstPath = "";
	for (const file of Array.from(list)) {
		const data = new Uint8Array(await file.arrayBuffer());
		const format = fontFormat(data);
		if (format === "woff" || format === "woff2" || webFontRe.test(file.name)) {
			refused.push(`${file.name}: WOFF and WOFF2 are web formats the renderer cannot read. Use the .ttf or .otf version.`);
			continue;
		}
		if (!drawable(format)) {
			refused.push(`${file.name}: not a TrueType or OpenType font.`);
			continue;
		}
		const ext = format === "otf" ? "otf" : format === "ttc" ? "ttc" : "ttf";
		const base = file.name.replace(/\.[^.]*$/, "").replace(/[\\/]/g, "_") || "font";
		const at = placeFor(`${FOLDER}/${base}.${ext}`, data, taken);
		if (at.add) {
			add.push({ path: at.path, data });
			taken.set(at.path, data);
		}
		firstPath ||= at.path;
	}
	if (add.length) await onapply(add, {}, null);
	if (firstPath) {
		switchTab("project");
		projectSel = firstPath;
		await tick();
		pick(projectItems.findIndex((i) => i.path === firstPath));
	}
	status = refused.length
		? refused.join(" ")
		: add.length
			? `Added ${add.map((a) => a.path.split("/").pop()).join(", ")}. Give it a name to use it.`
			: firstPath
				? "That font is already in the project."
				: "";
}

async function addLicenseFile(list: FileList | null) {
	const file = list?.[0];
	const cur = projectCur;
	if (!file || !cur) return;
	await onapply([{ path: licensePathFor(cur.path), data: new Uint8Array(await file.arrayBuffer()) }], {}, null);
	status = `Saved ${licensePathFor(cur.path)}.`;
}

function allowGoogle(v: "allowed" | "declined") {
	google = v;
	savePrefs();
	if (v === "declined") switchTab("project");
}

// ---------------------------------------------------------------- footer

const primary = $derived.by((): { label: string; hint: string; disabled: boolean; run?: () => void } => {
	if (tab === "google") {
		if (google !== "allowed" || !googleCur) return { label: "Import", hint: "", disabled: true };
		const n = chosenStyles.length;
		return {
			label: layer ? "Import and use" : "Import",
			hint: n ? `Adds ${n} font file${n > 1 ? "s" : ""} and the license to ${FOLDER}/${layer ? `, then sets it on ${layer.id}` : ""}.` : "Choose at least one style.",
			disabled: busy || !n || googleErrors.length > 0,
			run: importGoogle,
		};
	}
	const cur = projectCur;
	if (!cur || cur.missing) return { label: "Use", hint: cur?.missing ? "This file is not in the project." : "", disabled: true };
	if (cur.names.length)
		return {
			label: "Use on layer",
			hint: !layer
				? "Select a text layer to use this font on it."
				: layer.font === cur.names[0]
					? `${layer.id} already uses ${cur.names[0]}.`
					: `Sets ${layer.id} to ${cur.names[0]}.`,
			disabled: busy || !layer || layer.font === cur.names[0],
			run: useProject,
		};
	return {
		label: layer ? "Add and use" : "Add to design",
		hint: `Declares the name in this design${layer ? ` and sets it on ${layer.id}` : ""}.`,
		disabled: busy || !!nameError(newName),
		run: useProject,
	};
});

const title = $derived(
	tab === "project"
		? `Fonts (${projectItems.length} in project)`
		: catalog
			? `Fonts (${googleItems.length.toLocaleString("en")} of ${catalog.length.toLocaleString("en")})`
			: "Fonts",
);

let searchEl = $state<HTMLInputElement>();
let fwEl = $state<HTMLDivElement>();
let primaryEl = $state<HTMLButtonElement>();
$effect(() => {
	searchEl?.focus();
});
// svelte-ignore state_referenced_locally
if (target.upload) tick().then(() => fileInput?.click());

let dropping = $state(false);
function onDrop(e: DragEvent) {
	if (!e.dataTransfer?.files.length) return;
	e.preventDefault();
	e.stopPropagation();
	dropping = false;
	uploadFonts(e.dataTransfer.files);
}

function onKey(e: KeyboardEvent) {
	if (e.key === "Escape" && !(e.target as HTMLElement).closest("[role=listbox], .yx-select-pop")) {
		if (e.target === searchEl && query) {
			query = "";
		} else onclose();
		e.stopPropagation();
	}
}

const licenseTag = (kind: string) =>
	kind === "OFL" ? "OFL" : kind === "APACHE2" ? "Apache" : kind === "UFL" ? "UFL" : kind === "restricted" ? "" : "License";
</script>

<Window key="fonts" {title} width={880} height={580} minWidth={640} minHeight={420} {onclose}>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="fw"
    class:dropping
    bind:this={fwEl}
    onkeydown={onKey}
    ondragover={(e) => {
      if (!e.dataTransfer?.types.includes('Files')) return;
      e.preventDefault();
      e.stopPropagation();
      dropping = true;
    }}
    ondragleave={(e) => {
      if (e.currentTarget === e.target) dropping = false;
    }}
    ondrop={onDrop}
  >
    <div class="bar">
      <div class="btn-group" role="tablist" aria-label="Source">
        <button role="tab" aria-selected={tab === 'project'} onclick={() => switchTab('project')}>In project</button>
        <button role="tab" aria-selected={tab === 'google'} onclick={() => switchTab('google')}>Google Fonts</button>
      </div>
      <input class="search" type="search" placeholder={tab === 'project' ? 'Search project fonts' : 'Search families or designers'} aria-label="Search fonts" bind:value={query} bind:this={searchEl} />
      {#if tab === 'google'}
        <Select
          value={category}
          compact
          caption="Category"
          label="Category"
          options={[{ value: '', label: 'All' }, ...CATEGORIES.map((c) => ({ value: c, label: c }))]}
          onchange={(v) => (category = v as Category | '')}
        />
      {/if}
      <span class="grow"></span>
      <button title="Add .ttf or .otf files from this computer (or drop them on this window)" onclick={() => fileInput?.click()}>Upload font file…</button>
      <input class="hidden" type="file" accept=".ttf,.otf,.ttc,.woff,.woff2" multiple bind:this={fileInput} onchange={(e) => { const t = e.currentTarget; if (t.files) uploadFonts(t.files); t.value = ''; }} />
    </div>
    <div class="bar">
      <label class="lbl" for="fw-preview">Preview</label>
      <input id="fw-preview" class="preview-text" placeholder="Type to preview, e.g. your card text" bind:value={previewText} />
      <span class="lbl">Size</span>
      <div class="btn-group" role="group" aria-label="Preview size">
        {#each Object.keys(SIZES) as s (s)}
          <button class:active={size === s} aria-pressed={size === s} title="{SIZES[s as Size]} px" onclick={() => { size = s as Size; savePrefs(); }}>{s}</button>
        {/each}
      </div>
    </div>

    <div class="main">
      {#if tab === 'google' && google !== 'allowed'}
        <div class="consent" role="region" aria-label="Google Fonts">
          <h3>Use Google Fonts?</h3>
          <p>Previews and imports download fonts from <b>fonts.googleapis.com</b> and <b>fonts.gstatic.com</b>, and license texts from <b>raw.githubusercontent.com</b>. Google receives your IP address and the preview text. Your project files are not sent.</p>
          <p class="muted">About 1,900 families, all under the SIL Open Font License, the Apache License or the Ubuntu Font Licence, so they may be shared inside a project. Your choice is remembered in this browser.</p>
          <div class="row end">
            <button onclick={() => allowGoogle('declined')}>Not now</button>
            <button class="primary" onclick={() => allowGoogle('allowed')}>Allow Google Fonts</button>
          </div>
        </div>
      {:else}
        <div
          class="list"
          role="listbox"
          tabindex="0"
          aria-label={tab === 'project' ? 'Project fonts' : 'Google Fonts families'}
          aria-activedescendant={activeIndex >= 0 ? `fw-row-${activeIndex}` : undefined}
          bind:this={listEl}
          bind:clientHeight={listH}
          onscroll={(e) => (scrollTop = e.currentTarget.scrollTop)}
          onkeydown={listKey}
        >
          <div class="spacer" style:height="{count * rowH}px">
            {#if tab === 'project'}
              {#each projectItems.slice(first, last) as item, k (item.path)}
                {@const i = first + k}
                {@const fam = faces[item.path]}
                <div id="fw-row-{i}" class="row-item" role="option" tabindex="-1" aria-selected={item.path === projectCur?.path} style:top="{i * rowH}px" style:height="{rowH}px" onclick={() => pick(i)} onkeydown={() => {}} title={item.path}>
                  <span class="sample" style:font-family={fam ? `"${fam}"` : undefined} style:font-size="{SIZES[size]}px" aria-hidden="true">{sampleText || item.path.split('/').pop()?.replace(/\.[^.]+$/, '')}</span>
                  <span class="meta">
                    <span class="mono">{item.names.join(', ') || 'not in this design'}</span>
                    <span class="file">{item.path.split('/').pop()}</span>
                    {#if item.missing}<span class="warn-pill">missing</span>{/if}
                  </span>
                </div>
              {/each}
            {:else}
              {#each googleItems.slice(first, last) as f, k (f.name)}
                {@const i = first + k}
                {@const fam = googleFace(f, mainStyle(f))}
                <div id="fw-row-{i}" class="row-item" role="option" tabindex="-1" aria-selected={f.name === googleCur?.name} style:top="{i * rowH}px" style:height="{rowH}px" onclick={() => pick(i)} onkeydown={() => {}}>
                  <span class="sample" class:loading={!fam} style:font-family={fam ? `"${fam}"` : undefined} style:font-size="{SIZES[size]}px" aria-hidden="true">{googleText || f.name}</span>
                  <span class="meta">
                    <span>{f.name}</span>
                    <span class="file">{f.styles.length} style{f.styles.length > 1 ? 's' : ''} · {LICENSES[f.license].short}</span>
                  </span>
                </div>
              {/each}
            {/if}
          </div>
          {#if !count}
            <p class="empty">
              {#if tab === 'google' && catalogError}The font list could not be loaded ({catalogError}). <button class="link" onclick={ensureCatalog}>Try again</button>
              {:else if tab === 'google' && !catalog}Loading the font list…
              {:else if query}No fonts match "{query}". <button class="link" onclick={() => (query = '')}>Clear search</button>
              {:else}No fonts in this project yet. Upload a .ttf or .otf file, drop one here, or import one from Google Fonts.{/if}
            </p>
          {/if}
        </div>

        <div class="detail">
          {#if tab === 'project' && projectCur}
            {@const fam = faces[projectCur.path]}
            <header>
              <h2>{projectInfo?.info.family || projectCur.path.split('/').pop()}</h2>
              <span class="muted">{[projectInfo?.info.style, projectInfo ? `weight ${projectInfo.info.weight}` : '', projectInfo?.info.format.toUpperCase()].filter(Boolean).join(' · ')}</span>
            </header>
            <div class="big" style:font-family={fam ? `"${fam}"` : undefined} aria-hidden="true">{sampleText || projectInfo?.info.family || 'Aa Bb Cc 123'}</div>
            {#if projectInfo && fontWarning(projectInfo)}
              <p class="warn-line"><span class="warn-pill">!</span>{fontWarning(projectInfo)}</p>
            {/if}
            {#if projectCur.missing}
              <p class="warn-line"><span class="warn-pill">!</span>This file is not in the project, so layers using {projectCur.names.join(', ')} draw with the default font. Upload it again or point the name at another file in the design's Fonts section.</p>
            {/if}
            <section>
              <h3>File</h3>
              <p class="mono small">{projectCur.path}</p>
              {#if projectCur.names.length}
                <p class="small">Named <b class="mono">{projectCur.names.join(', ')}</b> in this design{usedBy.length ? `, used by ${usedBy.length} layer${usedBy.length > 1 ? 's' : ''} (${usedBy.slice(0, 6).join(', ')}${usedBy.length > 6 ? '…' : ''})` : ', not used by any layer yet'}.</p>
              {:else if !projectCur.missing}
                <label class="name-row">
                  <span class="lbl">Name</span>
                  <input class="mono" bind:value={newName} aria-invalid={!!nameError(newName)} />
                </label>
                <p class="small muted">{nameError(newName) || 'Text layers pick this name in their font field.'}</p>
              {/if}
            </section>
            <section>
              <h3>License</h3>
              {#if projectInfo?.license}
                <p class="small"><span class="tag">{licenseTag(projectInfo.license.kind) || 'Limited'}</span> <span class="mono">{projectInfo.license.path}</span></p>
                {#if projectInfo.license.kind === 'restricted'}<p class="small">The license text limits sharing or redistribution. Read it before you share this project.</p>{/if}
                <details><summary>Show the license text</summary><pre>{projectInfo.license.text}</pre></details>
              {:else if projectInfo}
                {#if projectInfo.info.license || projectInfo.info.copyright}
                  <p class="small">No license file next to this font. The font file itself says:</p>
                  <blockquote class="small">{projectInfo.info.copyright}{projectInfo.info.license ? ` ${projectInfo.info.license}` : ''}{projectInfo.info.licenseUrl ? ` (${projectInfo.info.licenseUrl})` : ''}</blockquote>
                  {#if projectInfo.info.license}<button onclick={saveEmbeddedLicense}>Save this as the license file</button>{/if}
                {:else}
                  <p class="small">No license file next to this font, and the font names none.</p>
                {/if}
                <button onclick={() => licenseInput?.click()}>Add license file…</button>
                <input class="hidden" type="file" accept=".txt,.md,text/plain" bind:this={licenseInput} onchange={(e) => { addLicenseFile(e.currentTarget.files); e.currentTarget.value = ''; }} />
                <p class="small muted">Saved as <span class="mono">{licensePathFor(projectInfo.path)}</span>.</p>
              {/if}
              {#if projectInfo?.info.designer}<p class="small muted">Designer: {projectInfo.info.designer}</p>{/if}
            </section>
          {:else if tab === 'google' && googleCur}
            {@const f = googleCur}
            {@const lic = LICENSES[f.license]}
            {@const fam = googleFace(f, chosenStyles[0] ?? mainStyle(f))}
            <header>
              <h2>{f.name}</h2>
              <span class="muted">{f.category} · {f.designer} · Google Fonts</span>
            </header>
            <div class="big" style:font-family={fam ? `"${fam}"` : undefined} aria-hidden="true">{googleText || f.name}</div>
            <section>
              <h3>Styles</h3>
              {#each f.styles as s (s.key)}
                {@const sf = googleFace(f, s)}
                <label class="variant">
                  <input type="checkbox" bind:checked={chosen[s.key]} />
                  <span class="vname">{styleLabel(s)}</span>
                  <span class="vsample" style:font-family={sf ? `"${sf}"` : undefined} aria-hidden="true">{googleText || f.name}</span>
                  {#if chosen[s.key]}
                    <input class="mono vfont" aria-label="Font name for {styleLabel(s)}" bind:value={names[s.key]} aria-invalid={!!nameError(names[s.key] ?? '', `${FOLDER}/${fileStem(f, s)}.ttf`)} />
                  {/if}
                </label>
              {/each}
              {#if googleErrors.length}<p class="small err">{googleErrors[0]}</p>{/if}
              <p class="small muted">Each style is saved as <span class="mono">{FOLDER}/{fileStem(f, chosenStyles[0] ?? mainStyle(f))}.ttf</span> and declared under its name.</p>
            </section>
            <section>
              <h3>License</h3>
              <p class="small"><b>{lic.name}</b> · <a href={lic.url} target="_blank" rel="noreferrer">about</a></p>
              <p class="small">{lic.summary}</p>
              <p class="small muted">A plain summary, not legal advice. The license file saved next to each font has the full terms.</p>
              <button class="link" aria-expanded={licenseOpen} onclick={toggleLicense}>{licenseOpen ? 'Hide' : 'Show'} the license text</button>
              {#if licenseOpen}<pre>{licenseText}</pre>{/if}
            </section>
          {:else if tab === 'google' && google === 'allowed' && catalog}
            <p class="empty">Choose a family on the left.</p>
          {/if}
        </div>
      {/if}
    </div>

    <footer>
      <span class="hint" class:err={status.startsWith('Nothing') || status.includes('cannot read') || status.includes('not a TrueType')} role="status">{status || primary.hint}</span>
      {#if tab === 'google' && google === 'allowed'}
        <button class="link" title="Stop using Google Fonts in this browser" onclick={() => allowGoogle('declined')}>Turn off Google Fonts</button>
      {/if}
      <button onclick={onclose}>Close</button>
      <button class="primary" bind:this={primaryEl} disabled={primary.disabled} onclick={() => primary.run?.()}>{busy ? 'Importing…' : primary.label}</button>
    </footer>
    {#if dropping}<div class="drop">Drop .ttf or .otf files to add them to {FOLDER}/</div>{/if}
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
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: none;
    min-height: var(--bar-h);
    box-sizing: border-box;
    padding: 0 10px;
    border-bottom: 1px solid var(--line);
  }
  .bar .btn-group > button {
    height: calc(var(--ctl-h) - 2px);
    padding: 0 10px;
  }
  .search {
    width: 220px;
    height: var(--ctl-h);
    box-sizing: border-box;
  }
  .preview-text {
    flex: 1;
    min-width: 0;
    height: var(--ctl-h);
    box-sizing: border-box;
  }
  .grow {
    flex: 1;
  }
  .lbl {
    color: var(--muted);
  }
  .hidden {
    display: none;
  }
  .main {
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-columns: minmax(240px, 42%) 1fr;
  }
  .list {
    position: relative;
    overflow-y: auto;
    border-right: 1px solid var(--line);
    outline: none;
  }
  .list:focus-visible {
    box-shadow: inset 0 0 0 2px var(--accent);
  }
  .spacer {
    position: relative;
  }
  .row-item {
    position: absolute;
    left: 0;
    right: 0;
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 1px;
    padding: 0 12px;
    border-bottom: 1px solid color-mix(in srgb, var(--line) 60%, transparent);
    cursor: default;
    overflow: hidden;
  }
  .row-item:hover {
    background: var(--hover);
  }
  .row-item[aria-selected='true'] {
    background: var(--sel);
    box-shadow: inset 2px 0 0 var(--accent);
  }
  .sample {
    line-height: 1.15;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sample.loading {
    color: var(--muted);
  }
  .meta {
    display: flex;
    gap: 8px;
    align-items: baseline;
    font-size: 11px;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
  }
  .meta .mono {
    font-family: var(--mono);
    color: var(--fg);
  }
  .file {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .detail {
    overflow-y: auto;
    min-width: 0;
  }
  .detail header {
    display: flex;
    align-items: baseline;
    gap: 8px;
    flex-wrap: wrap;
    padding: 10px 12px 0;
  }
  h2 {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
  }
  .big {
    margin: 8px 12px 10px;
    padding: 12px;
    min-height: 64px;
    font-size: 44px;
    line-height: 1.2;
    background: var(--bg-code);
    border: 1px solid var(--line);
    border-radius: 8px;
    overflow-wrap: anywhere;
  }
  section {
    padding: 8px 12px 10px;
    border-top: 1px solid var(--line);
  }
  h3 {
    margin: 0 0 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
  }
  .small {
    margin: 0 0 6px;
    font-size: 12px;
  }
  .muted {
    color: var(--muted);
  }
  .err {
    color: var(--err);
  }
  .mono {
    font-family: var(--mono);
  }
  .variant {
    display: grid;
    grid-template-columns: 16px 110px 1fr auto;
    align-items: center;
    gap: 8px;
    min-height: 30px;
  }
  .vname {
    white-space: nowrap;
  }
  .vsample {
    font-size: 18px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .vfont {
    width: 170px;
    height: 24px;
    box-sizing: border-box;
  }
  .name-row {
    display: grid;
    grid-template-columns: 84px 1fr;
    align-items: center;
    margin-bottom: 4px;
  }
  .name-row input {
    height: var(--ctl-h);
    box-sizing: border-box;
  }
  input[aria-invalid='true'] {
    border-color: var(--err);
  }
  .tag {
    display: inline-block;
    padding: 0 6px;
    border: 1px solid var(--line);
    border-radius: 4px;
    font-size: 11px;
    color: var(--muted);
  }
  .warn-pill {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 16px;
    padding: 0 5px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    background: color-mix(in srgb, var(--warn) 14%, var(--bg));
    color: var(--warn-text);
  }
  .warn-line {
    display: flex;
    gap: 8px;
    align-items: baseline;
    margin: 0 12px 10px;
    color: var(--warn-text);
  }
  blockquote {
    margin: 0 0 6px;
    padding: 4px 8px;
    border-left: 2px solid var(--line);
    color: var(--muted);
    overflow-wrap: anywhere;
  }
  pre {
    max-height: 220px;
    overflow: auto;
    margin: 6px 0 0;
    padding: 8px;
    font-size: 11px;
    white-space: pre-wrap;
    background: var(--bg-code);
    border: 1px solid var(--line);
    border-radius: 6px;
  }
  details summary {
    cursor: pointer;
    color: var(--accent);
  }
  section > button {
    margin: 0 6px 6px 0;
  }
  .link {
    border: 0;
    background: none;
    padding: 0;
    color: var(--accent);
    cursor: pointer;
  }
  .consent {
    grid-column: 1 / -1;
    align-self: start;
    justify-self: center;
    max-width: 520px;
    margin: 40px 16px;
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--bg-bar);
  }
  .consent h3 {
    font-size: 13px;
    text-transform: none;
    letter-spacing: 0;
    color: var(--fg);
  }
  .consent p {
    margin: 0 0 10px;
    line-height: 1.45;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .row.end {
    justify-content: flex-end;
  }
  .empty {
    padding: 16px 12px;
    color: var(--muted);
  }
  footer {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: none;
    min-height: 44px;
    padding: 0 12px;
    border-top: 1px solid var(--line);
    background: var(--bg-bar);
  }
  .hint {
    flex: 1;
    min-width: 0;
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
  }
  footer .link {
    white-space: nowrap;
  }
  .primary {
    background: var(--accent-strong);
    border-color: var(--accent-strong);
    color: var(--on-accent);
    font-weight: 600;
  }
  .primary:disabled {
    opacity: 0.5;
  }
  .drop {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    border: 2px dashed var(--accent);
    border-radius: 0 0 10px 10px;
    font-size: 14px;
    pointer-events: none;
  }
</style>
