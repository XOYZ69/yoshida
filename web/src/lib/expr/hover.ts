// Hover info and go to definition for expression fields. Hovering a name
// shows what it is (kind, type, value or signature, docs); Ctrl/Cmd+click
// on it, or F12 with the caret on it, shows where it is defined: the param
// in the Params tab, the constant or function in the design settings, the
// layer in the tree, the repeat (or function) that a local name comes from.
// Holding Ctrl/Cmd underlines the names that can be followed.

import {
	type EditorState,
	type Extension,
	Prec,
	StateEffect,
	StateField,
} from "@codemirror/state";
import {
	Decoration,
	type DecorationSet,
	EditorView,
	hoverTooltip,
	keymap,
	type Tooltip,
	ViewPlugin,
} from "@codemirror/view";
import type { CompletionContext, GotoTarget } from "../builder/complete";
import {
	BUILTINS,
	FN_BY_NAME,
	KEYWORDS,
	keyField,
	layerFields,
	lookupType,
	typeLabel,
} from "./catalog";
import { info, signatureNode } from "./completion";
import { exprAt, inString } from "./scan";

/** The dotted name under a position: `parts[index]` is the part at it. */
export type NameRef = {
	parts: string[];
	index: number;
	/** Starts with `@` (a layer reference). */
	at: boolean;
	/** Followed by `(`: a function call. */
	call: boolean;
	/** Range of the part at the position (with the `@` for a layer). */
	from: number;
	to: number;
};

const nameRe = /@?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/g;

/** The name at `pos` (on either side of it when `side` is 0), or null in strings, numbers and literal template text. */
export function nameAt(
	text: string,
	pos: number,
	template: boolean,
	side: -1 | 0 | 1 = 0,
): NameRef | null {
	const range = exprAt(text, pos, template);
	if (!range) return null;
	const src = text.slice(range.from, range.to);
	nameRe.lastIndex = 0;
	for (let m = nameRe.exec(src); m; m = nameRe.exec(src)) {
		const start = range.from + m.index;
		const end = start + m[0].length;
		if (pos < start || pos > end) continue;
		if ((pos === start && side < 0) || (pos === end && side > 0)) continue;
		// Not a name: units (`50vw`), colors (`#c0ffee`), fields of something
		// that is not a name (`list[0].name`), text in quotes.
		const prev = text[start - 1] ?? "";
		if (/[0-9#.\])]/.test(prev) && start > range.from) return null;
		if (inString(text, range.from, start)) return null;
		const at = m[0].startsWith("@");
		const parts = (at ? m[0].slice(1) : m[0]).split(".");
		let p = start + (at ? 1 : 0);
		let index = parts.length - 1;
		let from = start;
		let to = end;
		for (let i = 0; i < parts.length; i++) {
			const a = p;
			const b = p + parts[i].length;
			if (pos <= b) {
				index = i;
				from = i === 0 ? start : a;
				to = b;
				break;
			}
			p = b + 1;
		}
		let k = end;
		while (k < range.to && text[k] === " ") k++;
		return { parts, index, at, call: text[k] === "(", from, to };
	}
	return null;
}

/** What a name is: the hover's content and where it is defined. */
export type NameInfo = {
	head: string | Node;
	body: string;
	extra?: string;
	warn?: string;
	target?: GotoTarget;
};

/** Short display of a value for the hover (lists and long text are cut). */
export function preview(v: unknown): string {
	if (v === undefined || v === null) return "";
	if (Array.isArray(v)) return `${v.length} item${v.length === 1 ? "" : "s"}`;
	const s =
		typeof v !== "string"
			? JSON.stringify(v)
			: /^#[0-9a-f]{6,16}$/i.test(v)
				? v
				: `'${v}'`;
	return s.length > 60 ? `${s.slice(0, 57)}…` : s;
}

export function describe(
	ctx: CompletionContext,
	ref: NameRef,
): NameInfo | null {
	const [head] = ref.parts;
	const sub = ref.parts.slice(1, ref.index + 1);

	if (ref.at) {
		const l = ctx.layers.find((x) => x.id === head);
		if (!l)
			return {
				head: `@${head}`,
				body: "",
				warn: `No layer '${head}' can be referenced here.`,
			};
		const target: GotoTarget = { kind: "layer", id: l.id };
		if (ref.index === 0)
			return {
				head: `@${l.id}`,
				body: `The ${l.type} layer '${l.id}'.`,
				extra: "Ctrl+click to select it.",
				target,
			};
		// Layer fields can be dotted themselves (`bounds.w`): use the whole rest.
		const rest = ref.parts.slice(1).join(".");
		const fields = layerFields(l.type);
		const f =
			fields.find((x) => x.name === rest) ??
			fields.find((x) => x.name === sub.join("."));
		if (f)
			return { head: `@${l.id}.${f.name}: ${f.type}`, body: f.doc, target };
		const group = fields.filter((x) => x.name.startsWith(`${sub.join(".")}.`));
		if (group.length)
			return {
				head: `@${l.id}.${sub.join(".")}`,
				body: group.map((x) => `.${x.name.split(".").pop()}`).join(" "),
				target,
			};
		return {
			head: `@${l.id}.${rest}`,
			body: "",
			warn: `A ${l.type} layer has no field '${rest}'.`,
			target,
		};
	}

	if (ref.parts.length === 1) {
		const k = KEYWORDS.find((x) => x.name === head);
		if (k) return { head: `${k.name}: ${k.type}`, body: k.doc };
	}

	if (ref.index === 0 && ref.call) {
		const own = ctx.functions?.find((x) => x.name === head);
		if (own) return designFunction(own);
		const f = FN_BY_NAME.get(head);
		if (f)
			return {
				head: signatureNode(f),
				body: f.doc,
				extra: `e.g. ${f.example}`,
			};
		return { head: `${head}()`, body: "", warn: `Unknown function '${head}'.` };
	}

	const b = BUILTINS[head];
	if (b) {
		if (ref.index === 0)
			return {
				head,
				body: b.doc,
				extra: b.fields.map((f) => `${head}.${f.name}: ${f.type}`).join("\n"),
			};
		const f = b.fields.find((x) => x.name === sub[0]);
		return f
			? { head: `${head}.${f.name}: ${f.type}`, body: f.doc }
			: {
					head: `${head}.${sub[0]}`,
					body: "",
					warn: `'${head}' has no field '${sub[0]}'.`,
				};
	}

	const local = ctx.locals.find((x) => x.name === head);
	if (local) {
		const target = local.source;
		if (ref.index === 0) {
			const fields = Object.entries(local.fields ?? {})
				.map(([k, t]) => `${k}: ${t}`)
				.join(", ");
			return {
				head: `${local.name}: ${local.type ?? (local.fields ? "item" : "number")}`,
				body: local.detail,
				extra: fields
					? `fields: ${fields}`
					: local.type
						? undefined
						: "Counts from 0.",
				target,
			};
		}
		const t = local.fields?.[sub[0]];
		return t
			? {
					head: `${head}.${sub[0]}: ${t}`,
					body: `Field of the current item (${local.detail}).`,
					target,
				}
			: {
					head: `${head}.${sub[0]}`,
					body: "",
					warn: `The item has no field '${sub[0]}'.`,
					target,
				};
	}

	const p = ctx.params.find((x) => x.name === head);
	if (p) {
		const target: GotoTarget = { kind: "param", name: p.name };
		if (ref.index === 0) {
			const t = typeLabel(p.type, p.item);
			const shown = preview(p.value);
			return {
				head: `${p.name}: ${t}`,
				body:
					p.label || p.note
						? [p.label, p.note].filter(Boolean).join(" — ")
						: "A param: each card fills it in (or uses its default).",
				extra: shown ? `on this card: ${shown}` : undefined,
				target,
			};
		}
		if (p.type === "list" && p.item) {
			const key = sub[0];
			const look = lookupType(p.item);
			if (ref.index === 1) {
				const known = p.keys?.includes(key);
				return {
					head: `${p.name}.${key}: ${look.type}`,
					body: `The ${p.name} item whose ${keyField(p.item) ?? "key"} is '${key}'${look.field ? `; gives its ${look.field}` : ""}.`,
					warn:
						known || !p.keys
							? undefined
							: `No card has a ${p.name} item '${key}' yet.`,
					target,
				};
			}
			const t = p.item[sub[1]];
			if (t)
				return {
					head: `${p.name}.${key}.${sub[1]}: ${t}`,
					body: `Field of the ${p.name} item '${key}'.`,
					target,
				};
		}
		return {
			head: ref.parts.slice(0, ref.index + 1).join("."),
			body: "",
			target,
		};
	}

	const c = ctx.consts?.find((x) => x.name === head);
	if (c)
		return {
			head: `${c.name}: constant`,
			body: "A design constant.",
			extra: c.expr !== undefined ? `= ${c.expr}` : undefined,
			target: { kind: "const", name: c.name },
		};

	const own = ctx.functions?.find((x) => x.name === head);
	if (own) return designFunction(own);
	const f = FN_BY_NAME.get(head);
	if (f)
		return { head: signatureNode(f), body: f.doc, extra: `e.g. ${f.example}` };

	if (ref.index > 0) return null;
	return { head, body: "", warn: `Unknown name '${head}'.` };
}

function designFunction(
	f: NonNullable<CompletionContext["functions"]>[number],
): NameInfo {
	return {
		head: `${f.name}(${f.args})`,
		body: f.note || "A design function.",
		extra: f.expr !== undefined ? `= ${f.expr}` : undefined,
		target: { kind: "function", name: f.name },
	};
}

// ------------------------------------------------------------ extension

const setLink = StateEffect.define<{ from: number; to: number } | null>();
const linkMark = Decoration.mark({ class: "yx-link" });

const linkField = StateField.define<DecorationSet>({
	create: () => Decoration.none,
	update(v, tr) {
		v = v.map(tr.changes);
		for (const e of tr.effects)
			if (e.is(setLink))
				v = e.value
					? Decoration.set([linkMark.range(e.value.from, e.value.to)])
					: Decoration.none;
		return v;
	},
	provide: (f) => EditorView.decorations.from(f),
});

export function exprHover(
	getCtx: () => CompletionContext | null,
	template: boolean,
	/** Shows the definition; absent where nothing can be shown. */
	goto: ((t: GotoTarget) => void) | undefined,
): Extension {
	const lookup = (state: EditorState, pos: number, side: -1 | 0 | 1) => {
		const ctx = getCtx();
		if (!ctx) return null;
		const ref = nameAt(state.doc.toString(), pos, template, side);
		const d = ref && describe(ctx, ref);
		return ref && d ? { ref, d } : null;
	};
	const follow = (view: EditorView, pos: number, side: -1 | 0 | 1) => {
		const t = lookup(view.state, pos, side)?.d.target;
		if (!t || !goto) return false;
		goto(t);
		return true;
	};
	let modDown = false;
	let lastMouse: { x: number; y: number } | null = null;
	const updateLink = (view: EditorView) => {
		let link: { from: number; to: number } | null = null;
		if (modDown && goto && lastMouse) {
			const pos = view.posAtCoords(lastMouse);
			const hit = pos !== null ? lookup(view.state, pos, 1) : null;
			if (hit?.d.target) link = { from: hit.ref.from, to: hit.ref.to };
		}
		const cur = view.state.field(linkField).iter();
		const same = link
			? cur.value && cur.from === link.from && cur.to === link.to
			: !cur.value;
		if (!same) view.dispatch({ effects: setLink.of(link) });
	};

	return [
		hoverTooltip(
			(view, pos, side): Tooltip | null => {
				const hit = lookup(view.state, pos, side);
				if (!hit) return null;
				const { d, ref } = hit;
				const tip =
					goto && d.target
						? `${navigator.platform.startsWith("Mac") ? "⌘" : "Ctrl"}+click to show where it is defined`
						: undefined;
				return {
					pos: ref.from,
					end: ref.to,
					above: true,
					create: () => {
						const dom = info(d.head, d.body, d.extra, d.warn)();
						dom.classList.add("yx-hover");
						if (tip) {
							const h = document.createElement("div");
							h.className = "yx-hover-hint";
							h.textContent = tip;
							dom.appendChild(h);
						}
						return { dom };
					},
				};
			},
			{ hoverTime: 350, hideOnChange: true },
		),
		linkField,
		EditorView.domEventHandlers({
			mousedown(e, view) {
				if (e.button !== 0 || !(e.ctrlKey || e.metaKey) || !goto) return false;
				const pos = view.posAtCoords({ x: e.clientX, y: e.clientY });
				if (pos === null || !follow(view, pos, 1)) return false;
				e.preventDefault();
				return true;
			},
			mousemove(e, view) {
				lastMouse = { x: e.clientX, y: e.clientY };
				modDown = e.ctrlKey || e.metaKey;
				updateLink(view);
				return false;
			},
			mouseleave(_e, view) {
				lastMouse = null;
				updateLink(view);
				return false;
			},
		}),
		// Ctrl/Cmd pressed or released while the pointer is over the field,
		// which usually does not have the focus: listen on the window.
		ViewPlugin.define((view) => {
			const key = (e: KeyboardEvent) => {
				if (e.key !== "Control" && e.key !== "Meta") return;
				modDown = e.type === "keydown";
				if (lastMouse) updateLink(view);
			};
			const blur = () => {
				modDown = false;
				if (lastMouse) updateLink(view);
			};
			window.addEventListener("keydown", key);
			window.addEventListener("keyup", key);
			window.addEventListener("blur", blur);
			return {
				destroy() {
					window.removeEventListener("keydown", key);
					window.removeEventListener("keyup", key);
					window.removeEventListener("blur", blur);
				},
			};
		}),
		Prec.high(
			keymap.of([
				{
					key: "F12",
					run: (view) => follow(view, view.state.selection.main.head, 0),
				},
			]),
		),
	];
}
