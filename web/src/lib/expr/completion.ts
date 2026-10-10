// CodeMirror completion for yoshida expressions: params, repeat names,
// layers (`@id`) and their fields, built-ins and their fields, item fields,
// functions with signatures and docs, keywords. Every option shows its type;
// options that do not fit the type the field needs are ranked lower and
// dimmed.

import {
	type CompletionContext as CmContext,
	type Completion,
	type CompletionResult,
	type CompletionSection,
	pickedCompletion,
	startCompletion,
} from "@codemirror/autocomplete";
import type { EditorView } from "@codemirror/view";
import type { CompletionContext } from "../builder/complete";
import {
	BUILTINS,
	type Expect,
	type FnDoc,
	FUNCTIONS,
	fit,
	fnSignature,
	KEYWORDS,
	keyField,
	layerFields,
	lookupType,
	typeLabel,
	valueType,
} from "./catalog";
import { exprAt, inString } from "./scan";

type Opt = Completion & { kind: string; fitness: number };

const sec = (name: string, rank: number): CompletionSection => ({ name, rank });
const S = {
	repeat: sec("Repeat", 0),
	keys: sec("Keys", 0),
	params: sec("Params", 1),
	fields: sec("Fields", 1),
	layers: sec("Layers", 2),
	builtins: sec("Built-ins", 3),
	functions: sec("Functions", 4),
	keywords: sec("Keywords", 5),
};

function el(tag: string, cls: string, text?: string) {
	const e = document.createElement(tag);
	e.className = cls;
	if (text !== undefined) e.textContent = text;
	return e;
}

/** The docs panel next to the selected option. */
function info(
	head: string | Node,
	body: string,
	extra?: string,
	warn?: string,
) {
	return () => {
		const d = el("div", "yx-info");
		const h = el("div", "yx-info-head");
		if (typeof head === "string") h.textContent = head;
		else h.appendChild(head);
		d.appendChild(h);
		if (body) d.appendChild(el("div", "yx-info-body", body));
		if (extra) d.appendChild(el("div", "yx-info-extra", extra));
		if (warn) d.appendChild(el("div", "yx-info-warn", warn));
		return d;
	};
}

export function signatureNode(f: FnDoc, active = -1) {
	const s = el("span", "yx-sig");
	for (const p of fnSignature(f, active).parts)
		s.appendChild(
			el("span", p.active ? "yx-sig-arg yx-sig-active" : "yx-sig-arg", p.text),
		);
	return s;
}

function mismatch(type: string, expect: Expect | undefined) {
	return expect && expect !== "any" && fit(type, expect) === 0
		? `This field needs ${expect}; this is ${valueType(type)}.`
		: undefined;
}

/** Inserts text, then reopens completion (after `@id.` or `canvas.`). */
function insertThenComplete(text: string) {
	return (view: EditorView, c: Completion, from: number, to: number) => {
		view.dispatch({
			changes: { from, to, insert: text },
			selection: { anchor: from + text.length },
			annotations: pickedCompletion.of(c),
			userEvent: "input.complete",
		});
		setTimeout(() => startCompletion(view), 0);
	};
}

function opt(o: Omit<Opt, "boost">, expect: Expect | undefined, base = 0): Opt {
	return {
		...o,
		boost: base + (expect && expect !== "any" ? (o.fitness - 1) * 20 : 0),
	};
}

/** Options for a bare word (no dot): everything in scope. */
function topLevel(ctx: CompletionContext, expect: Expect | undefined): Opt[] {
	const out: Opt[] = [];
	for (const l of ctx.locals) {
		const fields = l.fields
			? Object.entries(l.fields)
					.map(([k, t]) => `${k}: ${t}`)
					.join(", ")
			: "";
		out.push(
			opt(
				{
					label: l.name,
					kind: "local",
					detail: l.fields ? "item" : "number",
					section: S.repeat,
					fitness: l.fields ? 1 : fit("number", expect),
					info: info(
						l.name,
						l.detail,
						fields
							? `fields: ${fields} — write ${l.name}.<field>`
							: "Counts from 0.",
					),
				},
				expect,
				2,
			),
		);
	}
	for (const p of ctx.params) {
		const t = typeLabel(p.type, p.item);
		const f = fit(p.type, expect);
		const fields = p.item
			? Object.entries(p.item)
					.map(([k, ty]) => `${k}: ${ty}`)
					.join(", ")
			: "";
		const key = keyField(p.item);
		const lookup = key
			? ` — look items up by ${key}: ${p.name}.${p.keys?.[0] ?? "<key>"}`
			: "";
		out.push(
			opt(
				{
					label: p.name,
					kind: "param",
					detail: t,
					section: S.params,
					fitness: f,
					info: info(
						`${p.name}: ${t}`,
						p.label || p.note
							? [p.label, p.note].filter(Boolean).join(" — ")
							: "Card value (or the param’s default).",
						fields ? `item fields: ${fields}${lookup}` : undefined,
						mismatch(p.type, expect),
					),
				},
				expect,
				1,
			),
		);
	}
	for (const k of ctx.consts ?? []) {
		out.push(
			opt(
				{
					label: k.name,
					kind: "param",
					detail: "constant",
					section: S.params,
					fitness: 1,
					info: info(k.name, "A design constant (consts)."),
				},
				expect,
				1,
			),
		);
	}
	for (const f of ctx.functions ?? []) {
		out.push(
			opt(
				{
					label: f.name,
					kind: "fn",
					detail: `(${f.args})`,
					section: S.functions,
					fitness: 1,
					apply: insertThenComplete(`${f.name}(`),
					info: info(`${f.name}(${f.args})`, "A design function (functions)."),
				},
				expect,
				1,
			),
		);
	}
	for (const l of ctx.layers) {
		out.push({
			label: `@${l.id}`,
			kind: "layer",
			detail: `${l.type} layer`,
			section: S.layers,
			fitness: 1,
			apply: insertThenComplete(`@${l.id}.`),
			info: info(
				`@${l.id}`,
				`Read a value of the ${l.type} layer '${l.id}', e.g. @${l.id}.bounds.bottom.`,
			),
			boost: 0,
		});
	}
	for (const [name, b] of Object.entries(BUILTINS)) {
		out.push({
			label: name,
			kind: "builtin",
			detail: b.fields.map((f) => `.${f.name}`).join(" "),
			section: S.builtins,
			fitness: 1,
			apply: insertThenComplete(`${name}.`),
			info: info(
				name,
				b.doc,
				b.fields
					.map((f) => `${name}.${f.name}: ${f.type} — ${f.doc}`)
					.join("\n"),
			),
			boost: 0,
		});
	}
	for (const f of FUNCTIONS) {
		out.push(
			opt(
				{
					label: f.name,
					kind: "fn",
					detail: `→ ${f.ret}`,
					section: S.functions,
					fitness: fit(f.ret, expect),
					apply: insertThenComplete(`${f.name}(`),
					info: info(
						signatureNode(f),
						f.doc,
						`e.g. ${f.example}`,
						mismatch(f.ret, expect),
					),
				},
				expect,
			),
		);
	}
	for (const k of KEYWORDS) {
		const isBool = k.name === "true" || k.name === "false";
		out.push(
			opt(
				{
					label: k.name,
					kind: "keyword",
					detail: isBool ? "bool" : "operator",
					section: S.keywords,
					fitness: isBool ? fit("bool", expect) : 1,
					info: info(k.name, k.doc),
				},
				expect,
				-5,
			),
		);
	}
	return out;
}

function fieldOpts(
	fields: { name: string; type: string; doc: string }[],
	owner: string,
	expect: Expect | undefined,
): Opt[] {
	return fields.map((f) =>
		opt(
			{
				label: f.name,
				kind: "field",
				detail: f.type,
				section: S.fields,
				fitness: fit(f.type, expect),
				info: info(
					`${owner}.${f.name}: ${f.type}`,
					f.doc,
					undefined,
					mismatch(f.type, expect),
				),
			},
			expect,
		),
	);
}

const identRe = /^[A-Za-z_][A-Za-z0-9_]*$/;

type ListParam = CompletionContext["params"][number];

/**
 * Keys of a list param as options (FORMAT.md 6.3.1). After a dot, keys that
 * are not names are written in brackets instead: `list["Two words"]`.
 * `quote` is set inside `list["...`: the option then closes the bracket.
 */
function keyOpts(
	p: ListParam,
	expect: Expect | undefined,
	quote?: { q: string; closed: boolean },
): Opt[] {
	const item = p.item ?? {};
	const look = lookupType(item);
	const what = look.field ? `its ${look.field}` : "the whole item";
	const esc = (k: string, q: string) =>
		k.replace(/\\/g, "\\\\").replace(new RegExp(q, "g"), `\\${q}`);
	return (p.keys ?? []).map((k) => {
		const o: Opt = opt(
			{
				label: k,
				kind: "key",
				detail: look.type === "item" ? "item" : look.type,
				section: S.keys,
				fitness: look.type === "item" ? 1 : fit(look.type, expect),
				info: info(
					`${p.name}.${k}`,
					`The ${p.name} item whose ${keyField(item)} is '${k}'; gives ${what}. Keys are case-sensitive.`,
					look.type === "item"
						? `fields: ${Object.keys(item).join(", ")}`
						: undefined,
					look.type === "item" ? undefined : mismatch(look.type, expect),
				),
			},
			expect,
			2,
		);
		if (quote) o.apply = esc(k, quote.q) + (quote.closed ? "" : `${quote.q}]`);
		else if (!identRe.test(k)) {
			// Replace the dot as well: `list.` + key becomes `list["key"]`.
			o.apply = (view: EditorView, c: Completion, from: number, to: number) => {
				const insert = `["${esc(k, '"')}"]`;
				view.dispatch({
					changes: { from: from - 1, to, insert },
					selection: { anchor: from - 1 + insert.length },
					annotations: pickedCompletion.of(c),
					userEvent: "input.complete",
				});
			};
		}
		return o;
	});
}

export function exprCompletion(
	getCtx: () => CompletionContext | null,
	template: boolean,
	getExpect: () => Expect | undefined,
) {
	return (c: CmContext): CompletionResult | null => {
		const text = c.state.doc.toString();
		const range = exprAt(text, c.pos, template);
		if (!range) return null;
		const ctx = getCtx() ?? { params: [], layers: [], locals: [] };
		const expect = getExpect();
		const before = text.slice(range.from, c.pos);
		if (inString(text, range.from, c.pos)) {
			// `list["Ke` or `list['Ke`: the list's keys.
			const k =
				/([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*(["'])((?:[^"'\\]|\\.)*)$/.exec(
					before,
				);
			const p =
				k && ctx.params.find((x) => x.name === k[1] && x.type === "list");
			if (!k || !p?.keys?.length) return null;
			const closed = text.slice(c.pos).startsWith(k[2]);
			return {
				from: c.pos - k[3].length,
				options: keyOpts(p, expect, { q: k[2], closed }),
				validFor: /^[^"'\]]*$/,
			};
		}
		const m =
			/(@?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\.?|@)$/.exec(
				before,
			);
		// A word glued to a number is a unit (`50vw`), not a name.
		if (m && /[0-9]$/.test(before.slice(0, before.length - m[1].length)))
			return null;
		if (!m) {
			if (!c.explicit) return null;
			return {
				from: c.pos,
				options: topLevel(ctx, expect),
				validFor: /^@?\w*$/,
			};
		}
		const word = m[1];
		const start = c.pos - word.length;
		const dot = word.indexOf(".");
		if (dot < 0)
			return {
				from: start,
				options: topLevel(ctx, expect),
				validFor: /^@?\w*$/,
			};

		const head = word.slice(0, dot);
		const from = start + dot + 1;
		let options: Opt[] = [];
		if (head.startsWith("@")) {
			const l = ctx.layers.find((x) => x.id === head.slice(1));
			if (!l) return null;
			options = fieldOpts(layerFields(l.type), head, expect);
		} else if (BUILTINS[head])
			options = fieldOpts(BUILTINS[head].fields, head, expect);
		else {
			const local = ctx.locals.find((x) => x.name === head);
			const list =
				!local && ctx.params.find((x) => x.name === head && x.type === "list");
			const rest = word.slice(dot + 1);
			if (local?.fields)
				options = fieldOpts(
					Object.entries(local.fields).map(([name, type]) => ({
						name,
						type,
						doc: `Field of the current item (${local.detail}).`,
					})),
					head,
					expect,
				);
			else if (list && !rest.includes(".")) {
				options = keyOpts(list, expect);
				if (!options.length) return null;
				return { from, options, validFor: /^\w*$/ };
			} else if (
				typeof list === "object" &&
				list.item &&
				rest.split(".").length === 2 &&
				lookupType(list.item).type === "item"
			) {
				// `list.Key.` on a list of bigger items: the item's fields.
				const key = rest.slice(0, rest.indexOf("."));
				options = fieldOpts(
					Object.entries(list.item).map(([name, type]) => ({
						name,
						type,
						doc: `Field of the ${head} item '${key}'.`,
					})),
					`${head}.${key}`,
					expect,
				);
				if (!options.length) return null;
				return { from: from + key.length + 1, options, validFor: /^\w*$/ };
			}
		}
		if (!options.length) return null;
		return { from, options, validFor: /^[\w.]*$/ };
	};
}

/** The badge drawn before each option's label (see autocompletion addToOptions). */
export const kindBadge = {
	position: 20,
	render(c: Completion) {
		const kind = (c as Opt).kind ?? "field";
		const glyph: Record<string, string> = {
			param: "P",
			local: "R",
			layer: "@",
			builtin: "B",
			fn: "ƒ",
			keyword: "K",
			field: "·",
			key: "k",
		};
		return el("span", `yx-badge yx-badge-${kind}`, glyph[kind] ?? "·");
	},
};

export function optionClass(c: Completion) {
	return (c as Opt).fitness === 0 ? "yx-dim" : "";
}
