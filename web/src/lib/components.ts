// Components in the builder. A component is a file of layers that groups take
// with `"include"`. The builder edits a design with every component filled in
// (the group gets the component's layers next to its `include`), so those
// layers can be selected and changed like any other; `splitIncludes` turns
// the result back into the design file and the component files.

import { childrenOf, clone, isGroup, isObj, type Json, type Obj } from "./design.ts";

/** The text of a project file, or undefined when it is missing. */
export type ReadText = (path: string) => string | undefined;

/**
 * A group in a file that has both `layers` and `include` (an error the core
 * reports) keeps its own layers; its include is parked under this key while
 * the builder has the design, so it is never written into the component.
 */
const PARKED = "include (ignored)";

export const componentRe = /\.component\.json$/i;

/** The component file a group takes its layers from. */
export function includeOf(l: Json | undefined): string | null {
	return isGroup(l) && typeof l.include === "string" ? l.include : null;
}

function parseComponent(text: string | undefined): Obj | null {
	if (text === undefined) return null;
	try {
		const v = JSON.parse(text);
		return isObj(v) && Array.isArray(v.layers) ? v : null;
	} catch {
		return null;
	}
}

/** Whether a project file is a component: an object with layers and no canvas. */
export function isComponentFile(path: string, text: string | undefined) {
	if (!/\.json$/i.test(path) || /\.(design|cards)\.json$/i.test(path))
		return false;
	const c = parseComponent(text);
	return !!c && c.canvas === undefined && c.format !== undefined;
}

function walkGroups(list: Json[], f: (g: Obj) => void) {
	for (const l of list) {
		if (!isGroup(l)) continue;
		f(l);
		if (Array.isArray(l.layers)) walkGroups(l.layers as Json[], f);
	}
}

/** Paths of every component a design uses, components of components included. */
export function includedPaths(doc: Obj, read: ReadText): string[] {
	const out: string[] = [];
	const visit = (layers: Json[]) =>
		walkGroups(layers, (g) => {
			const p = includeOf(g);
			if (!p || Array.isArray(g.layers) || out.includes(p)) return;
			out.push(p);
			const c = parseComponent(read(p));
			if (c) visit(c.layers as Json[]);
		});
	if (Array.isArray(doc.layers)) visit(doc.layers as Json[]);
	return out;
}

/**
 * The design with each including group's layers filled in from its component
 * file. A component that is missing, broken, included a second time or part
 * of a cycle is left as the bare include.
 */
export function expandIncludes(doc: Obj, read: ReadText): Obj {
	if (!Array.isArray(doc.layers)) return doc;
	const out = clone(doc);
	const used = new Set<string>();
	const fill = (layers: Json[], stack: string[]) => {
		for (const g of layers) {
			if (!isGroup(g)) continue;
			const p = includeOf(g);
			if (p && Array.isArray(g.layers)) {
				g[PARKED] = p;
				delete g.include;
			} else if (p && !used.has(p) && !stack.includes(p)) {
				const c = parseComponent(read(p));
				if (c) {
					used.add(p);
					g.layers = clone(c.layers);
					fill(g.layers as Json[], [...stack, p]);
					continue;
				}
			}
			if (Array.isArray(g.layers)) fill(g.layers as Json[], stack);
		}
	};
	fill(out.layers as Json[], []);
	return out;
}

const titleOf = (path: string) =>
	(path.split("/").pop() ?? path).replace(/(\.component)?\.json$/i, "");

/** A short name for a component file: `effect-row` for `x/effect-row.component.json`. */
export const componentLabel = titleOf;

/**
 * Splits an expanded design: `design` is what the design file holds (groups
 * keep only their `include`), `components` the new content of each component
 * file whose layers changed (the file's other fields are kept; a file that
 * did not exist is made).
 */
export function splitIncludes(
	doc: Obj,
	read: ReadText,
): { design: Obj; components: Map<string, Obj> } {
	const design = clone(doc);
	const components = new Map<string, Obj>();
	const seen = new Set<string>();
	const strip = (layers: Json[]) => {
		for (const g of layers) {
			if (!isGroup(g)) continue;
			// Inner components first: the outer one keeps only their include.
			if (Array.isArray(g.layers)) strip(g.layers as Json[]);
			if (typeof g[PARKED] === "string") {
				const own = g.layers;
				delete g.layers;
				g.include = g[PARKED];
				delete g[PARKED];
				if (own !== undefined) g.layers = own;
				continue;
			}
			const p = includeOf(g);
			if (!p || !Array.isArray(g.layers)) continue;
			if (!seen.has(p)) {
				seen.add(p);
				const old = parseComponent(read(p));
				if (!old)
					components.set(p, { format: 1, name: titleOf(p), layers: g.layers });
				else if (JSON.stringify(old.layers) !== JSON.stringify(g.layers))
					components.set(p, { ...old, layers: g.layers });
			}
			delete g.layers;
		}
	};
	if (Array.isArray(design.layers)) strip(design.layers as Json[]);
	return { design, components };
}

/** A copy of a layer that no longer includes anything: its layers are its own. */
export function detached<T extends Json>(layer: T): T {
	const out = clone(layer);
	const walk = (l: Json) => {
		if (!isGroup(l)) return;
		if (Array.isArray(l.layers)) {
			delete l.include;
			delete l[PARKED];
			for (const c of l.layers) walk(c);
		}
	};
	walk(out);
	return out;
}

/** The including group a layer sits in (the innermost one), or null. */
export function componentAround(doc: Obj, id: string): Obj | null {
	let found: Obj | null = null;
	const walk = (owner: Obj, inside: Obj | null): boolean => {
		for (const l of childrenOf(owner)) {
			if (l.id === id) {
				found = inside;
				return true;
			}
			if (isGroup(l) && walk(l, includeOf(l) ? l : inside)) return true;
		}
		return false;
	};
	walk(doc, null);
	return found;
}

/** Design and component files that include `path`, sorted. */
export function includersOf(
	path: string,
	paths: string[],
	read: ReadText,
): string[] {
	const out: string[] = [];
	for (const p of paths) {
		if (p === path || !/\.json$/i.test(p) || /\.cards\.json$/i.test(p)) continue;
		const text = read(p);
		if (!text?.includes('"include"')) continue;
		const c = parseComponent(text);
		if (!c) continue;
		let hit = false;
		walkGroups(c.layers as Json[], (g) => {
			if (includeOf(g) === path) hit = true;
		});
		if (hit) out.push(p);
	}
	return out.sort();
}

/** A project path for a new component called `name` that no file has yet. */
export function componentPath(name: string, taken: (path: string) => boolean) {
	const stem =
		name
			.trim()
			.toLowerCase()
			.replace(/[^a-z0-9]+/g, "-")
			.replace(/^-+|-+$/g, "") || "component";
	for (let n = 1; ; n++) {
		const p = `components/${stem}${n === 1 ? "" : `-${n}`}.component.json`;
		if (!taken(p)) return p;
	}
}

/**
 * Why a component cannot be included in `doc` (expanded), or "". Layer ids
 * are unique in a design, so a component fits once, and not next to layers
 * that already use its ids.
 */
export function includeBlocker(doc: Obj, path: string, read: ReadText): string {
	const ids = new Set<string>();
	let used = false;
	const walk = (owner: Obj) => {
		for (const l of childrenOf(owner)) {
			ids.add(String(l.id));
			if (includeOf(l) === path) used = true;
			if (isGroup(l)) walk(l);
		}
	};
	walk(doc);
	if (used) return "already in this design";
	const c = parseComponent(read(path));
	if (!c) return "not a readable component";
	const clash: string[] = [];
	const check = (owner: Obj) => {
		for (const l of childrenOf(owner)) {
			if (ids.has(String(l.id))) clash.push(String(l.id));
			if (isGroup(l)) check(l);
		}
	};
	check(c);
	return clash.length ? `layer id '${clash[0]}' is already used` : "";
}
