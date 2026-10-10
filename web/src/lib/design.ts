// Editing a design document as data: the visual builder changes the parsed
// JSON with these helpers and writes it back through the formatter.

export type Json =
	| null
	| boolean
	| number
	| string
	| Json[]
	| { [k: string]: Json };
export type Obj = { [k: string]: Json };
export type LayerType = "rect" | "ellipse" | "polygon" | "text" | "image";

/** Resolved bounds of one layer (or one repeat iteration) from the core. */
export type Placed = {
	id: string;
	instance?: number;
	visible: boolean;
	x: number;
	y: number;
	w: number;
	h: number;
	/** Degrees clockwise around (px, py). */
	rotate?: number;
	px?: number;
	py?: number;
	/** Text size after auto-shrink. */
	size?: number;
	points?: [number, number][];
};

export type Bounds = { x: number; y: number; w: number; h: number };

/**
 * Which canvas handles a layer gets. `aspect`: box handles that keep the
 * ratio; `group`: move and rotate only (its size comes from its layers).
 */
export type HandleMode =
	| "box"
	| "aspect"
	| "text"
	| "polygon"
	| "group"
	| "none";

/** A finished or ongoing canvas gesture, in canvas pixels. */
export type Gesture =
	| { mode: "move"; ids: string[]; dx: number; dy: number }
	| { mode: "resize"; id: string; from: Bounds; to: Bounds; angle: number }
	| { mode: "point"; id: string; index: number; dx: number; dy: number }
	| { mode: "rotate"; id: string; angle: number };

export const layerTypes: LayerType[] = [
	"rect",
	"ellipse",
	"text",
	"image",
	"polygon",
];

export const anchors = [
	"top-left",
	"top",
	"top-right",
	"left",
	"center",
	"right",
	"bottom-left",
	"bottom",
	"bottom-right",
];
export const textAnchors = [
	...anchors,
	"baseline-left",
	"baseline",
	"baseline-right",
];

const anchorFactors: Record<string, [number, number]> = {
	"top-left": [0, 0],
	top: [0.5, 0],
	"top-right": [1, 0],
	left: [0, 0.5],
	center: [0.5, 0.5],
	right: [1, 0.5],
	"bottom-left": [0, 1],
	bottom: [0.5, 1],
	"bottom-right": [1, 1],
	"baseline-left": [0, 0],
	baseline: [0.5, 0],
	"baseline-right": [1, 0],
};

export function anchorOf(layer: Obj): [number, number] {
	return anchorFactors[String(layer.anchor ?? "top-left")] ?? [0, 0];
}

export const identRe = /^[A-Za-z_][A-Za-z0-9_]*$/;

export function isObj(v: unknown): v is Obj {
	return v !== null && typeof v === "object" && !Array.isArray(v);
}

export function clone<T>(v: T): T {
	return structuredClone(v);
}

export function isGroup(l: Json | undefined): l is Obj {
	return isObj(l) && l.type === "group";
}

/** Dividers only organise the layer list; the core never draws them. */
export function isDivider(l: Json | undefined): l is Obj {
	return isObj(l) && l.type === "divider";
}

/** The layers directly in `doc` or in a group. */
export function childrenOf(owner: Obj): Obj[] {
	return Array.isArray(owner.layers)
		? (owner.layers.filter(isObj) as Obj[])
		: [];
}

/** Every layer, groups included, in document order (a group before its children). */
export function layersOf(doc: Obj): Obj[] {
	const out: Obj[] = [];
	const walk = (owner: Obj) => {
		for (const l of childrenOf(owner)) {
			out.push(l);
			if (isGroup(l)) walk(l);
		}
	};
	walk(doc);
	return out;
}

export function findLayer(doc: Obj, id: string): Obj | undefined {
	return layersOf(doc).find((l) => l.id === id);
}

/** Where a layer sits: its sibling array, index in it, and its group (null at the top). */
export function locate(
	doc: Obj,
	id: string,
): { list: Json[]; index: number; parent: Obj | null } | null {
	const walk = (owner: Obj, parent: Obj | null): ReturnType<typeof locate> => {
		if (!Array.isArray(owner.layers)) return null;
		const list = owner.layers as Json[];
		for (let i = 0; i < list.length; i++) {
			const l = list[i];
			if (!isObj(l)) continue;
			if (l.id === id) return { list, index: i, parent };
			if (isGroup(l)) {
				const r = walk(l, l);
				if (r) return r;
			}
		}
		return null;
	};
	return walk(doc, null);
}

/** JSON pointer of a layer, such as `/layers/2/layers/0`. */
export function layerPointer(doc: Obj, id: string): string | null {
	const walk = (owner: Obj, base: string): string | null => {
		const list = Array.isArray(owner.layers) ? owner.layers : [];
		for (let i = 0; i < list.length; i++) {
			const l = list[i];
			if (!isObj(l)) continue;
			if (l.id === id) return `${base}/layers/${i}`;
			if (isGroup(l)) {
				const r = walk(l, `${base}/layers/${i}`);
				if (r) return r;
			}
		}
		return null;
	};
	return walk(doc, "");
}

/** The layer a JSON pointer points into (the innermost one), or null. */
export function layerAtPointer(doc: Obj, ptr: string): string | null {
	let owner: Obj = doc;
	let found: string | null = null;
	const re = /^\/layers\/(\d+)/;
	let rest = ptr;
	for (;;) {
		const m = re.exec(rest);
		if (!m) return found;
		const l = Array.isArray(owner.layers)
			? owner.layers[Number(m[1])]
			: undefined;
		if (!isObj(l)) return found;
		found = typeof l.id === "string" ? l.id : found;
		owner = l;
		rest = rest.slice(m[0].length);
	}
}

/** The group a layer is in, or null. */
export function parentOf(doc: Obj, id: string): string | null {
	const p = locate(doc, id)?.parent;
	return p ? String(p.id) : null;
}

/** Groups around a layer, innermost first. */
export function ancestorsOf(doc: Obj, id: string): string[] {
	const out: string[] = [];
	for (let p = parentOf(doc, id); p; p = parentOf(doc, p)) out.push(p);
	return out;
}

/** Ids of every layer inside a group (all levels). */
export function descendantIds(layer: Obj): string[] {
	const out: string[] = [];
	for (const c of childrenOf(layer)) {
		out.push(String(c.id));
		if (isGroup(c)) out.push(...descendantIds(c));
	}
	return out;
}

const mergedKeys = new Set(["box", "at", "stroke", "repeat", "arc", "shape"]);
const ownKeys = new Set(["id", "extends", "note"]);

/**
 * The layer with its `extends` chain applied (FORMAT.md 5.8): objects merge
 * key by key, everything else is replaced, id/extends/note are not inherited.
 */
export function effectiveLayer(
	doc: Obj,
	id: string,
	seen = new Set<string>(),
): Obj | undefined {
	const own = findLayer(doc, id);
	if (!own) return undefined;
	if (typeof own.extends !== "string" || seen.has(id)) return own;
	seen.add(id);
	const base = effectiveLayer(doc, own.extends, seen);
	if (!base) return own;
	const out: Obj = {};
	for (const [k, v] of Object.entries(base)) if (!ownKeys.has(k)) out[k] = v;
	for (const [k, v] of Object.entries(own)) {
		out[k] =
			mergedKeys.has(k) && isObj(v) && isObj(out[k])
				? { ...(out[k] as Obj), ...v }
				: v;
	}
	return out;
}

/** Sets `layer[path...]`, or removes it for `undefined` (dropping emptied objects). */
export function setPath(target: Obj, path: string[], value: Json | undefined) {
	if (path.length === 1) {
		if (value === undefined) delete target[path[0]];
		else target[path[0]] = value;
		return;
	}
	const [head, ...rest] = path;
	let child = target[head];
	if (!isObj(child)) {
		if (value === undefined) return;
		child = {};
		target[head] = child;
	}
	setPath(child, rest, value);
	if (Object.keys(child).length === 0) delete target[head];
}

export function getPath(
	target: Json | undefined,
	path: string[],
): Json | undefined {
	let v: Json | undefined = target;
	for (const k of path) {
		if (!isObj(v)) return undefined;
		v = v[k];
	}
	return v;
}

// ---------------------------------------------------------------- numbers

export function round(n: number, digits = 2) {
	const f = 10 ** digits;
	return Math.round(n * f) / f;
}

const numRe = /^-?\d+(?:\.\d+)?$/;
const pctRe = /^(-?\d+(?:\.\d+)?)%$/;

/** Removes quoted strings so operators inside them are not seen. */
function stripStrings(s: string) {
	return s.replace(/'[^']*'|"[^"]*"/g, "''");
}

/** No operator that binds looser than `+`/`-`, so `expr + n` keeps its meaning. */
function isAdditive(s: string) {
	return !/[?:<>=!]|\band\b|\bor\b|\bnot\b/.test(stripStrings(s));
}

function signed(n: number) {
	return `${n < 0 ? "-" : "+"} ${Math.abs(n)}`;
}

/**
 * Adds `delta` pixels to a number field while keeping how it is written:
 * literals stay literals, `50%` stays a percentage of `size`, a trailing
 * constant (`@a.bounds.top + 60`) is adjusted, and any other expression gets
 * `+ delta` appended (in parentheses when needed).
 */
export function shiftValue(
	v: Json | undefined,
	delta: number,
	size: number,
): Json | undefined {
	if (v === undefined || v === null) return v;
	if (Math.abs(delta) < 1e-9) return v;
	if (typeof v === "number") return round(v + delta);
	if (typeof v !== "string") return v;
	const s = v.trim();
	if (s === "auto") return v;
	if (numRe.test(s)) return round(Number(s) + delta);
	const pm = pctRe.exec(s);
	if (pm && size > 0) return `${round(Number(pm[1]) + (delta / size) * 100)}%`;
	if (isAdditive(s)) {
		const m = /^(.*\S)\s*([+-])\s*(\d+(?:\.\d+)?)$/.exec(s);
		if (m && /[\w%)'"]$/.test(m[1])) {
			const c = round((m[2] === "-" ? -1 : 1) * Number(m[3]) + delta);
			return c === 0 ? m[1] : `${m[1]} ${signed(c)}`;
		}
		return `${s} ${signed(round(delta))}`;
	}
	return `(${s}) ${signed(round(delta))}`;
}

/** A number field as a number when it is a plain literal. */
export function literalNumber(v: Json | undefined): number | undefined {
	if (typeof v === "number") return v;
	if (typeof v === "string" && numRe.test(v.trim())) return Number(v);
	return undefined;
}

// ---------------------------------------------------------------- geometry edits

export type Canvas = { w: number; h: number };

/** Moves a layer by (dx, dy) canvas pixels; a group moves everything in it. */
export function moveLayer(
	doc: Obj,
	id: string,
	dx: number,
	dy: number,
	canvas: Canvas,
) {
	const own = findLayer(doc, id);
	const eff = effectiveLayer(doc, id);
	if (!own || !eff) return;
	switch (eff.type) {
		case "group": {
			// With a translate, the layers inside are relative to it.
			if (isObj(eff.translate)) {
				const t = eff.translate as Obj;
				setPath(own, ["translate", "x"], shiftValue(t.x ?? 0, dx, canvas.w));
				setPath(own, ["translate", "y"], shiftValue(t.y ?? 0, dy, canvas.h));
				return;
			}
			for (const c of childrenOf(own))
				moveLayer(doc, String(c.id), dx, dy, canvas);
			return;
		}
		case "text": {
			const at = eff.at as Obj | undefined;
			if (!at) return;
			setPath(own, ["at", "x"], shiftValue(at.x, dx, canvas.w));
			setPath(own, ["at", "y"], shiftValue(at.y, dy, canvas.h));
			return;
		}
		case "polygon": {
			if (isObj(eff.shape)) {
				const box = eff.box as Obj | undefined;
				if (!box) return;
				setPath(own, ["box", "x"], shiftValue(box.x, dx, canvas.w));
				setPath(own, ["box", "y"], shiftValue(box.y, dy, canvas.h));
				return;
			}
			if (!Array.isArray(eff.points)) return;
			own.points = eff.points.map((p) =>
				Array.isArray(p)
					? [shiftValue(p[0], dx, canvas.w)!, shiftValue(p[1], dy, canvas.h)!]
					: p,
			);
			return;
		}
		default: {
			const box = eff.box as Obj | undefined;
			if (!box) return;
			setPath(own, ["box", "x"], shiftValue(box.x, dx, canvas.w));
			setPath(own, ["box", "y"], shiftValue(box.y, dy, canvas.h));
		}
	}
}

/** Moves one polygon point. */
export function movePoint(
	doc: Obj,
	id: string,
	index: number,
	dx: number,
	dy: number,
	canvas: Canvas,
) {
	const own = findLayer(doc, id);
	const eff = effectiveLayer(doc, id);
	if (!own || !eff || !Array.isArray(eff.points)) return;
	const pts = clone(eff.points);
	const p = pts[index];
	if (!Array.isArray(p)) return;
	pts[index] = [
		shiftValue(p[0], dx, canvas.w)!,
		shiftValue(p[1], dy, canvas.h)!,
	];
	own.points = pts;
}

/**
 * Applies a new on-canvas rectangle to a box or text layer: the anchor point,
 * width and height fields are shifted by how much they changed. Text layers
 * only change width, through `wrap`.
 */
export function resizeLayer(
	doc: Obj,
	id: string,
	from: Bounds,
	to: Bounds,
	canvas: Canvas,
	angle = 0,
) {
	const own = findLayer(doc, id);
	const eff = effectiveLayer(doc, id);
	if (!own || !eff) return;
	const [fx, fy] = anchorOf(eff);
	// `from` and `to` are in the layer's unrotated frame; the anchor point is
	// the rotation pivot, so its offset is turned into canvas coordinates.
	const lx = to.x + fx * to.w - (from.x + fx * from.w);
	const ly = to.y + fy * to.h - (from.y + fy * from.h);
	const a = (angle * Math.PI) / 180;
	const dax = round(Math.cos(a) * lx - Math.sin(a) * ly);
	const day = round(Math.sin(a) * lx + Math.cos(a) * ly);
	if (eff.type === "text") {
		const at = eff.at as Obj | undefined;
		if (!at) return;
		setPath(own, ["at", "x"], shiftValue(at.x, dax, canvas.w));
		own.wrap =
			eff.wrap === undefined
				? Math.max(1, Math.round(to.w))
				: shiftValue(eff.wrap, to.w - from.w, canvas.w)!;
		return;
	}
	const box = eff.box as Obj | undefined;
	if (!box) return;
	setPath(own, ["box", "x"], shiftValue(box.x, dax, canvas.w));
	setPath(own, ["box", "y"], shiftValue(box.y, day, canvas.h));
	if (box.w !== "auto")
		setPath(own, ["box", "w"], shiftValue(box.w, to.w - from.w, canvas.w));
	if (box.h !== "auto")
		setPath(own, ["box", "h"], shiftValue(box.h, to.h - from.h, canvas.h));
}

/** Sets a layer's rotation in degrees (0 removes the field). */
export function rotateLayer(doc: Obj, id: string, angle: number) {
	const own = findLayer(doc, id);
	if (!own) return;
	const a = round(angle, 1);
	if (a === 0) delete own.rotate;
	else own.rotate = a;
}

export function moveLayers(
	doc: Obj,
	ids: string[],
	dx: number,
	dy: number,
	canvas: Canvas,
) {
	// A layer inside a moved group already moves with it.
	const set = new Set(ids);
	for (const id of ids)
		if (!ancestorsOf(doc, id).some((a) => set.has(a)))
			moveLayer(doc, id, dx, dy, canvas);
}

/** Union of a layer's boxes (all repeat iterations). */
export function boundsOf(layout: Placed[], id: string): Bounds | null {
	const bs = layout.filter((b) => b.id === id);
	if (!bs.length) return null;
	const x0 = Math.min(...bs.map((b) => b.x));
	const y0 = Math.min(...bs.map((b) => b.y));
	const x1 = Math.max(...bs.map((b) => b.x + b.w));
	const y1 = Math.max(...bs.map((b) => b.y + b.h));
	return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

export type AlignMode =
	| "left"
	| "hcenter"
	| "right"
	| "top"
	| "vcenter"
	| "bottom";

/**
 * Aligns layers to each other (two or more) or to the canvas (one), using
 * their rendered bounds.
 */
export function alignLayers(
	doc: Obj,
	ids: string[],
	mode: AlignMode,
	layout: Placed[],
	canvas: Canvas,
) {
	const boxes = ids
		.map((id) => [id, boundsOf(layout, id)] as const)
		.filter((x): x is readonly [string, Bounds] => !!x[1]);
	if (!boxes.length) return;
	const all: Bounds =
		boxes.length === 1
			? { x: 0, y: 0, w: canvas.w, h: canvas.h }
			: (() => {
					const x0 = Math.min(...boxes.map(([, b]) => b.x));
					const y0 = Math.min(...boxes.map(([, b]) => b.y));
					return {
						x: x0,
						y: y0,
						w: Math.max(...boxes.map(([, b]) => b.x + b.w)) - x0,
						h: Math.max(...boxes.map(([, b]) => b.y + b.h)) - y0,
					};
				})();
	for (const [id, b] of boxes) {
		let dx = 0;
		let dy = 0;
		if (mode === "left") dx = all.x - b.x;
		if (mode === "hcenter") dx = all.x + all.w / 2 - (b.x + b.w / 2);
		if (mode === "right") dx = all.x + all.w - (b.x + b.w);
		if (mode === "top") dy = all.y - b.y;
		if (mode === "vcenter") dy = all.y + all.h / 2 - (b.y + b.h / 2);
		if (mode === "bottom") dy = all.y + all.h - (b.y + b.h);
		moveLayer(doc, id, round(dx), round(dy), canvas);
	}
}

/** Equal gaps between three or more layers, keeping the outer two in place. */
export function distributeLayers(
	doc: Obj,
	ids: string[],
	axis: "x" | "y",
	layout: Placed[],
	canvas: Canvas,
) {
	const boxes = ids
		.map((id) => [id, boundsOf(layout, id)] as const)
		.filter((x): x is readonly [string, Bounds] => !!x[1]);
	if (boxes.length < 3) return;
	const pos = (b: Bounds) => (axis === "x" ? b.x : b.y);
	const size = (b: Bounds) => (axis === "x" ? b.w : b.h);
	boxes.sort((a, b) => pos(a[1]) - pos(b[1]));
	const first = boxes[0][1];
	const last = boxes[boxes.length - 1][1];
	const total = boxes.reduce((n, [, b]) => n + size(b), 0);
	const gap =
		(pos(last) + size(last) - pos(first) - total) / (boxes.length - 1);
	let at = pos(first) + size(first) + gap;
	for (const [id, b] of boxes.slice(1, -1)) {
		const d = round(at - pos(b));
		moveLayer(doc, id, axis === "x" ? d : 0, axis === "y" ? d : 0, canvas);
		at += size(b) + gap;
	}
}

// ---------------------------------------------------------------- layer list edits

export function uniqueId(doc: Obj, base: string) {
	const ids = new Set(layersOf(doc).map((l) => l.id));
	const stem = base.replace(/\d+$/, "") || "layer";
	for (let n = 1; ; n++) if (!ids.has(`${stem}${n}`)) return `${stem}${n}`;
}

export type NewLayerContext = {
	canvas: Canvas;
	imageFiles: string[];
	imageParams: string[];
};

/** A new layer of `type`, centred on the canvas, with literal values. */
export function newLayer(doc: Obj, type: LayerType, ctx: NewLayerContext): Obj {
	const { w, h } = ctx.canvas;
	const cx = Math.round(w / 2);
	const cy = Math.round(h / 2);
	const id = uniqueId(doc, type);
	const side = Math.round(Math.min(w, h) * 0.3);
	switch (type) {
		case "rect":
			return {
				id,
				type,
				anchor: "center",
				box: { x: cx, y: cy, w: side, h: side },
				fill: "#3B6CF6",
				radius: 0,
			};
		case "ellipse":
			return {
				id,
				type,
				anchor: "center",
				box: { x: cx, y: cy, w: side, h: side },
				fill: "#F5C542",
			};
		case "text":
			return {
				id,
				type,
				anchor: "center",
				at: { x: cx, y: cy },
				text: "Text",
				size: Math.max(12, Math.round(h / 20)),
				color: "#000000",
			};
		case "image": {
			const src = ctx.imageParams.length
				? `{${ctx.imageParams[0]}}`
				: (ctx.imageFiles[0] ?? "assets/image.png");
			return {
				id,
				type,
				anchor: "center",
				box: { x: cx, y: cy, w: side, h: "auto" },
				src,
				fit: "contain",
			};
		}
		case "polygon":
			return {
				id,
				type,
				points: [
					[cx, cy - side / 2],
					[cx + side / 2, cy + side / 2],
					[cx - side / 2, cy + side / 2],
				],
				fill: "#3B6CF6",
			};
	}
}

/** An empty group, or a divider titled `label`. */
export function newContainer(
	doc: Obj,
	type: "group" | "divider",
	label = "",
): Obj {
	if (type === "group") return { id: uniqueId(doc, "group"), type, layers: [] };
	const id = uniqueId(doc, "divider");
	return label ? { id, type, label } : { id, type };
}

/** Inserts above (after) the layer `aboveId` in its group, or on top. Returns the index. */
export function insertLayer(
	doc: Obj,
	layer: Obj,
	aboveId: string | null,
): number {
	if (!Array.isArray(doc.layers)) doc.layers = [];
	const at = aboveId ? locate(doc, aboveId) : null;
	const list = at ? at.list : (doc.layers as Json[]);
	const i = at ? at.index + 1 : list.length;
	list.splice(i, 0, layer);
	return i;
}

export function duplicateLayer(doc: Obj, id: string): string | null {
	const own = findLayer(doc, id);
	if (!own) return null;
	return pasteLayers(doc, [own], id)[0] ?? null;
}

/** Takes a layer out of the design (it can be inserted elsewhere). */
function detach(doc: Obj, id: string): Obj | null {
	const at = locate(doc, id);
	if (!at) return null;
	return at.list.splice(at.index, 1)[0] as Obj;
}

/**
 * Moves a layer directly above `target` (below it with `below`, in the
 * target's group), or to the bottom of the top level for null. A group never moves into itself.
 */
export function reorderLayer(
	doc: Obj,
	id: string,
	target: string | null,
	below = false,
) {
	if (target === id) return;
	const own = findLayer(doc, id);
	if (!own || (target && isGroup(own) && descendantIds(own).includes(target)))
		return;
	const l = detach(doc, id)!;
	if (target === null) {
		(doc.layers as Json[]).splice(0, 0, l);
		return;
	}
	const at = locate(doc, target);
	if (!at) (doc.layers as Json[]).push(l);
	else at.list.splice(below ? at.index : at.index + 1, 0, l);
}

/** Moves a layer into a group, on top of the group's layers. */
export function moveIntoGroup(doc: Obj, id: string, groupId: string) {
	const own = findLayer(doc, id);
	const g = findLayer(doc, groupId);
	if (
		!own ||
		!isGroup(g) ||
		id === groupId ||
		(isGroup(own) && descendantIds(own).includes(groupId))
	)
		return;
	const l = detach(doc, id)!;
	if (!Array.isArray(g.layers)) g.layers = [];
	(g.layers as Json[]).push(l);
}

/** Moves a layer one step up (+1) or down (-1) within its group. */
export function stepLayer(doc: Obj, id: string, step: 1 | -1) {
	const at = locate(doc, id);
	if (!at) return;
	const to = at.index + step;
	if (to < 0 || to >= at.list.length) return;
	[at.list[at.index], at.list[to]] = [at.list[to], at.list[at.index]];
}

/**
 * Puts layers into a new group placed where the topmost of them was. Layers
 * keep their stacking order. Returns the group's id.
 */
export function groupLayers(doc: Obj, ids: string[]): string | null {
	const all = layersOf(doc).map((l) => String(l.id));
	const set = new Set(ids);
	// Layers inside another selected group come along with it.
	const picked = all.filter(
		(id) => set.has(id) && !ancestorsOf(doc, id).some((a) => set.has(a)),
	);
	if (!picked.length) return null;
	const top = picked[picked.length - 1];
	const id = uniqueId(doc, "group");
	const group: Obj = { id, type: "group", layers: [] };
	insertLayer(doc, group, top);
	for (const x of picked) (group.layers as Json[]).push(detach(doc, x)!);
	return id;
}

/** Replaces a group by its layers, in place. */
export function ungroupLayer(doc: Obj, id: string): string[] {
	const at = locate(doc, id);
	const g = at ? (at.list[at.index] as Obj) : null;
	if (!at || !isGroup(g)) return [];
	const kids = childrenOf(g);
	at.list.splice(at.index, 1, ...kids);
	return kids.map((k) => String(k.id));
}

function mapStrings(v: Json, f: (s: string) => string): Json {
	if (typeof v === "string") return f(v);
	if (Array.isArray(v)) return v.map((x) => mapStrings(x, f));
	if (isObj(v))
		return Object.fromEntries(
			Object.entries(v).map(([k, x]) => [k, mapStrings(x, f)]),
		);
	return v;
}

function refRe(id: string) {
	return new RegExp(`@${id}(?![A-Za-z0-9_])`, "g");
}

/** A layer's own fields (a group without its layers). */
function ownFields(l: Obj): Obj {
	if (!isGroup(l)) return l;
	const { layers: _, ...rest } = l;
	return rest;
}

/** Layers whose fields mention `@id` or extend it. */
export function referencesTo(doc: Obj, id: string): string[] {
	const re = refRe(id);
	return layersOf(doc)
		.filter((l) => {
			re.lastIndex = 0;
			return (
				l.id !== id &&
				(l.extends === id || re.test(JSON.stringify(ownFields(l))))
			);
		})
		.map((l) => String(l.id));
}

/** Applies `f` to every layer of a list, recursing into groups. */
function mapLayerTree(list: Json[], f: (l: Obj) => Obj): Json[] {
	return list.map((l) => {
		if (!isObj(l)) return l;
		const out = f(l);
		if (isGroup(out) && Array.isArray(out.layers))
			out.layers = mapLayerTree(out.layers as Json[], f);
		return out;
	});
}

/** Renames layers and every `@id` reference and `extends` pointing at them. */
function renameIds(list: Json[], renames: Map<string, string>): Json[] {
	return mapLayerTree(list, (l) => {
		const { id, layers, ...rest } = l;
		let next = rest as Json;
		for (const [from, to] of renames) {
			if (from === to) continue;
			const re = refRe(from);
			next = mapStrings(next, (s) => s.replace(re, `@${to}`));
		}
		const n = next as Obj;
		if (typeof n.extends === "string" && renames.has(n.extends))
			n.extends = renames.get(n.extends)!;
		const out: Obj = { id: renames.get(String(id)) ?? id, ...n };
		if (layers !== undefined) out.layers = layers;
		return out;
	});
}

/** Renames a layer and every `@id` reference and `extends` pointing at it. */
export function renameLayer(doc: Obj, from: string, to: string) {
	if (Array.isArray(doc.layers))
		doc.layers = renameIds(doc.layers as Json[], new Map([[from, to]]));
}

/**
 * Inserts copies of `layers` above `aboveId` with fresh ids; references
 * between the pasted layers follow the new ids. Returns the new ids.
 */
export function pasteLayers(
	doc: Obj,
	layers: Obj[],
	aboveId: string | null,
): string[] {
	const renames = new Map<string, string>();
	const taken = new Set(layersOf(doc).map((l) => String(l.id)));
	const pastedIds = layersOf({ layers }).map((l) => String(l.id ?? "layer"));
	for (const old of pastedIds) {
		let next = old;
		if (taken.has(next)) {
			const stem = old.replace(/_copy\d*$|\d+$/, "") || "layer";
			for (let n = 1; ; n++) {
				next = `${stem}_copy${n === 1 ? "" : n}`;
				if (!taken.has(next)) break;
			}
		}
		taken.add(next);
		renames.set(old, next);
	}
	let above = aboveId;
	const ids: string[] = [];
	const copies = renameIds(clone(layers) as Json[], renames) as Obj[];
	for (const copy of copies) {
		insertLayer(doc, copy, above);
		above = String(copy.id);
		ids.push(above);
	}
	return ids;
}

export function deleteLayer(doc: Obj, id: string) {
	detach(doc, id);
}

// ---------------------------------------------------------------- params

export const paramTypes = [
	"text",
	"number",
	"integer",
	"bool",
	"color",
	"enum",
	"image",
	"list",
] as const;
export type ParamTypeName = (typeof paramTypes)[number];

export function newParam(type: ParamTypeName, imageFiles: string[]): Obj {
	switch (type) {
		case "text":
			return { type, default: "" };
		case "number":
		case "integer":
			return { type, default: 0 };
		case "bool":
			return { type, default: false };
		case "color":
			return { type, default: "#000000" };
		case "enum":
			return { type, options: ["a", "b"], default: "a" };
		case "image":
			return imageFiles.length
				? { type, default: imageFiles[0] }
				: { type, required: true };
		case "list":
			return { type, item: { name: "text" }, default: [] };
	}
}

/** Keeps a param's fields valid for a new type (default, min/max, options...). */
export function retypeParam(
	p: Obj,
	type: ParamTypeName,
	imageFiles: string[],
): Obj {
	const fresh = newParam(type, imageFiles);
	const out: Obj = { type };
	for (const k of ["label", "note", "group"])
		if (p[k] !== undefined) out[k] = p[k];
	return { ...out, ...fresh, type };
}

export function paramsOf(doc: Obj): [string, Obj][] {
	return isObj(doc.params)
		? (Object.entries(doc.params).filter(([, v]) => isObj(v)) as [
				string,
				Obj,
			][])
		: [];
}

/** Literal for a color field, or null when it is an expression. */
export function hexOf(v: Json | undefined): string | null {
	return typeof v === "string" &&
		/^#([0-9a-f]{6}|[0-9a-f]{8}|[0-9a-f]{12}|[0-9a-f]{16})$/i.test(v.trim())
		? v.trim()
		: null;
}

// ---------------------------------------------------------------- param rename

/** Renames identifier `from` in one expression (not after `.` or `@`, not in strings). */
export function renameInExpr(src: string, from: string, to: string): string {
	let out = "";
	let i = 0;
	while (i < src.length) {
		const c = src[i];
		if (c === "'" || c === '"') {
			const end = src.indexOf(c, i + 1);
			const j = end < 0 ? src.length : end + 1;
			out += src.slice(i, j);
			i = j;
			continue;
		}
		if (c === "#") {
			const m = /^#[0-9A-Fa-f]*/.exec(src.slice(i))!;
			out += m[0];
			i += m[0].length;
			continue;
		}
		if (/[A-Za-z_]/.test(c)) {
			const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i))!;
			const prev = src.slice(0, i).trimEnd().slice(-1);
			out += m[0] === from && prev !== "." && prev !== "@" ? to : m[0];
			i += m[0].length;
			continue;
		}
		if (/[0-9]/.test(c)) {
			// Numbers with units (10vw) must not be read as identifiers.
			const m = /^[0-9]+(\.[0-9]+)?([A-Za-z%]+)?/.exec(src.slice(i))!;
			out += m[0];
			i += m[0].length;
			continue;
		}
		out += c;
		i++;
	}
	return out;
}

/** Renames inside the `{...}` parts of a template. */
export function renameInTemplate(
	src: string,
	from: string,
	to: string,
): string {
	let out = "";
	let i = 0;
	while (i < src.length) {
		if (src.startsWith("{{", i) || src.startsWith("}}", i)) {
			out += src.slice(i, i + 2);
			i += 2;
			continue;
		}
		if (src[i] === "{") {
			const end = src.indexOf("}", i + 1);
			if (end < 0) {
				out += src.slice(i);
				break;
			}
			out += `{${renameInExpr(src.slice(i + 1, end), from, to)}}`;
			i = end + 1;
			continue;
		}
		out += src[i++];
	}
	return out;
}

const templateFields = new Set(["text", "src"]);
const plainFields = new Set([
	"id",
	"type",
	"note",
	"anchor",
	"extends",
	"font",
	"align",
	"fit",
	"smoothing",
	"closed",
	"side",
	"shrink_group",
	"arrow",
]);

function renameInLayerValue(
	v: Json,
	key: string,
	from: string,
	to: string,
): Json {
	if (typeof v === "string") {
		if (plainFields.has(key)) return v;
		return templateFields.has(key)
			? renameInTemplate(v, from, to)
			: renameInExpr(v, from, to);
	}
	if (Array.isArray(v))
		return v.map((x) => renameInLayerValue(x, key, from, to));
	if (isObj(v)) {
		const out: Obj = {};
		for (const [k, x] of Object.entries(v))
			out[k] =
				key === "repeat" && (k === "index" || k === "item")
					? x
					: renameInLayerValue(x, k, from, to);
		return out;
	}
	return v;
}

/**
 * Renames a param in the design: its declaration (keeping the order) and
 * every use in layer fields and the canvas, except inside layers whose
 * repeat names shadow it.
 */
export function renameParam(doc: Obj, from: string, to: string) {
	if (isObj(doc.params)) {
		doc.params = Object.fromEntries(
			Object.entries(doc.params).map(([k, v]) => [k === from ? to : k, v]),
		);
	}
	if (isObj(doc.canvas)) {
		for (const k of ["width", "height", "background", "dpi", "bleed"]) {
			const v = doc.canvas[k];
			if (typeof v === "string") doc.canvas[k] = renameInExpr(v, from, to);
		}
	}
	if (isObj(doc.consts))
		for (const [k, v] of Object.entries(doc.consts))
			if (typeof v === "string") doc.consts[k] = renameInExpr(v, from, to);
	if (isObj(doc.functions))
		for (const f of Object.values(doc.functions)) {
			if (!isObj(f) || typeof f.expr !== "string") continue;
			// An argument of the same name hides the param.
			const args = isObj(f.args)
				? Object.keys(f.args)
				: Array.isArray(f.args)
					? f.args.map(String)
					: [];
			if (!args.includes(from)) f.expr = renameInExpr(f.expr, from, to);
		}
	if (!Array.isArray(doc.layers)) return;
	const walk = (list: Json[]): Json[] =>
		list.map((l) => {
			if (!isObj(l)) return l;
			const rep = isObj(l.repeat) ? l.repeat : null;
			if (
				rep &&
				(rep.index === from ||
					rep.item === from ||
					(rep.index === undefined && from === "i"))
			)
				return l;
			const out: Obj = {};
			for (const [k, v] of Object.entries(l))
				out[k] =
					k === "layers" && isGroup(l) && Array.isArray(v)
						? walk(v)
						: renameInLayerValue(v, k, from, to);
			return out;
		});
	doc.layers = walk(doc.layers as Json[]);
}

/** Same rename in card data: JSON keys or the CSV header. */
export function renameParamInCards(
	path: string,
	text: string,
	from: string,
	to: string,
	csv: { parse: (t: string) => string[][]; write: (r: string[][]) => string },
	format: (v: unknown) => string,
): string {
	if (path.endsWith(".csv")) {
		const rows = csv.parse(text);
		if (!rows.length) return text;
		rows[0] = rows[0].map((h) => (h === from ? to : h));
		return csv.write(rows);
	}
	const d = JSON.parse(text);
	if (!Array.isArray(d.cards)) return text;
	d.cards = d.cards.map((c: unknown) =>
		isObj(c)
			? Object.fromEntries(
					Object.entries(c).map(([k, v]) => [k === from ? to : k, v]),
				)
			: c,
	);
	return format(d);
}

// ---------------------------------------------------------------- param order and groups

/** Group of a param, '' for none. */
export function groupOf(p: Obj): string {
	return typeof p.group === "string" ? p.group.trim() : "";
}

/**
 * Params in sections: ungrouped first, then each group in order of its
 * first param. Order inside a section is file order.
 */
export function paramSections<T>(
	params: [string, T][],
	group: (p: T) => string,
): { group: string; params: [string, T][] }[] {
	const out = new Map<string, [string, T][]>([["", []]]);
	for (const e of params) {
		const g = group(e[1]);
		if (!out.has(g)) out.set(g, []);
		out.get(g)!.push(e);
	}
	return [...out]
		.filter(([g, ps]) => (g === "" ? ps.length : true))
		.map(([g, ps]) => ({ group: g, params: ps }));
}

/** Rewrites `params` so its keys follow `order`; unknown keys keep their place at the end. */
export function reorderParams(doc: Obj, order: string[]) {
	if (!isObj(doc.params)) return;
	const ps = doc.params;
	const next: Obj = {};
	for (const k of order) if (k in ps) next[k] = ps[k];
	for (const k of Object.keys(ps)) if (!(k in next)) next[k] = ps[k];
	doc.params = next;
}

/**
 * Moves param `name` before `before` (or to the end of `group` for null)
 * and gives it that group.
 */
export function moveParam(
	doc: Obj,
	name: string,
	before: string | null,
	group: string,
) {
	if (!isObj(doc.params) || !isObj(doc.params[name])) return;
	const p = doc.params[name] as Obj;
	if (group) p.group = group;
	else delete p.group;
	const keys = Object.keys(doc.params).filter((k) => k !== name);
	let at: number;
	if (before && keys.includes(before)) at = keys.indexOf(before);
	else {
		// After the last param of the group, or at the end.
		const ps = doc.params;
		const last = keys
			.map((k, i) => [k, i] as const)
			.filter(([k]) => isObj(ps[k]) && groupOf(ps[k] as Obj) === group)
			.pop();
		at = last ? last[1] + 1 : keys.length;
	}
	keys.splice(at, 0, name);
	reorderParams(doc, keys);
}

/** Renames a param group (or removes it, for to = ''). */
export function renameParamGroup(doc: Obj, from: string, to: string) {
	for (const [, p] of paramsOf(doc)) {
		if (groupOf(p) !== from) continue;
		if (to) p.group = to;
		else delete p.group;
	}
}

// ---------------------------------------------------------------- enum options

/**
 * Renames enum option `from` of param `name` in the design: the option
 * itself and the default. Card values are changed by `renameValueInCards`.
 */
export function renameEnumOption(
	doc: Obj,
	name: string,
	from: string,
	to: string,
) {
	const p = isObj(doc.params) ? doc.params[name] : undefined;
	if (!isObj(p) || !Array.isArray(p.options)) return;
	p.options = p.options.map((o) => (o === from ? to : o));
	if (p.default === from) p.default = to;
}

/** Sets `param` to `to` on every card whose value is `from` (JSON or CSV). */
export function renameValueInCards(
	path: string,
	text: string,
	param: string,
	from: string,
	to: string,
	csv: { parse: (t: string) => string[][]; write: (r: string[][]) => string },
	format: (v: unknown) => string,
): string {
	if (path.endsWith(".csv")) {
		const rows = csv.parse(text);
		const col = rows[0]?.indexOf(param) ?? -1;
		if (col < 0) return text;
		let changed = false;
		for (const r of rows.slice(1))
			if (r[col] === from) {
				r[col] = to;
				changed = true;
			}
		return changed ? csv.write(rows) : text;
	}
	const d = JSON.parse(text);
	if (!Array.isArray(d.cards)) return text;
	let changed = false;
	for (const c of d.cards)
		if (isObj(c) && c[param] === from) {
			c[param] = to;
			changed = true;
		}
	return changed ? format(d) : text;
}

/** Path templates (`src` fields) that use param `name`, such as `cards/{card_type}.png`. */
export function templatesUsing(doc: Obj, name: string): string[] {
	const out: string[] = [];
	for (const l of layersOf(doc)) {
		const src = l.src;
		if (typeof src !== "string" || !src.includes("{")) continue;
		if (renameInTemplate(src, name, "\u0000") !== src) out.push(src);
	}
	return [...new Set(out)];
}
