// The expression core: the Zig parser and formatter, compiled to expr.wasm
// (src/expr). It parses expressions and templates tolerantly, never fails,
// and returns tokens, problems and a syntax tree, so the editor has one
// definition of what is valid. Loaded once at startup (main.ts); parse and
// format are synchronous after that (a parse takes about 0.1 ms).
//
// Spans are UTF-16 offsets into the source string.

export type TokenKind =
	| "number"
	| "unit"
	| "string"
	| "color"
	| "ref"
	| "name"
	| "keyword"
	| "op"
	| "punct"
	| "bad"
	| "text"
	| "escape"
	| "brace";

/** `[start, end, kind]` */
export type ExprToken = [number, number, TokenKind];

export type Span = [number, number];

export type Problem = {
	code: number;
	span: Span;
	message: string;
	hint: string | null;
};

export type NodeKind =
	| "number"
	| "unit"
	| "string"
	| "boolean"
	| "color"
	| "name"
	| "builtin"
	| "layer_ref"
	| "field"
	| "index"
	| "call"
	| "ucall"
	| "neg"
	| "not"
	| "binary"
	| "cond"
	| "in_list"
	| "paren"
	| "err";

/** A syntax tree node. Which fields are set depends on `k`. */
export type Node = {
	id: number;
	k: NodeKind;
	span: Span;
	/** number, string, boolean, color (and unit: the number). */
	v?: number | string | boolean;
	/** unit: the unit suffix (`%`, `vw`, `vh`). */
	unit?: string;
	/** name, builtin (e.g. `canvas.w`), field: the name. */
	name?: string;
	/** layer_ref: the layer id, its field path and an optional index. */
	id_?: string;
	path?: string[];
	index?: number;
	/** field, index: the object. */
	obj?: Node;
	/** index: the subscript. */
	idx?: Node;
	/** call, ucall: the function name and its arguments. */
	fn?: string;
	args?: Node[];
	/** neg, not, paren, err: the operand. */
	x?: Node;
	/** binary: the operator and its operands. */
	op?: string;
	l?: Node;
	r?: Node;
	/** cond: the condition, the then and the else branch. */
	c?: Node;
	a?: Node;
	b?: Node;
	/** in_list: the value and the list items. */
	value?: Node;
	items?: Node[];
};

/** A `{...}` hole of a template: its span includes the braces. */
export type TemplateHole = { span: Span; root: Node | null };

export type ParseResult = {
	tokens: ExprToken[];
	problems: Problem[];
	truncated: boolean;
	/** The tree of an expression (`template` false). */
	root?: Node | null;
	/** The holes of a template (`template` true). */
	holes?: TemplateHole[];
};

type Exports = {
	memory: WebAssembly.Memory;
	alloc(len: number): number;
	free(ptr: number, len: number): void;
	request(ptr: number, len: number): number;
	result_ptr(): number;
	result_len(): number;
};

let wasm: Exports | null = null;
let loading: Promise<void> | null = null;
const enc = new TextEncoder();
const dec = new TextDecoder();

/** Loads expr.wasm next to the page, as yoshida.wasm is found. Safe to call twice. */
export function loadExprCore(): Promise<void> {
	if (!loading) {
		loading = (async () => {
			const url = new URL("expr.wasm", document.baseURI).href;
			const res = await fetch(url);
			if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
			const { instance } = await WebAssembly.instantiate(
				await res.arrayBuffer(),
				{},
			);
			wasm = instance.exports as unknown as Exports;
		})();
		// Let a later call retry after a failure.
		loading.catch(() => {
			loading = null;
		});
	}
	return loading;
}

/** True once expr.wasm is loaded; the parse and format functions need it. */
export function exprCoreReady(): boolean {
	return wasm !== null;
}

function call<T>(req: object): T {
	const x = wasm;
	if (!x) throw new Error("The expression core is not loaded");
	const bytes = enc.encode(JSON.stringify(req));
	const p = x.alloc(bytes.length);
	new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
	const rc = x.request(p, bytes.length);
	x.free(p, bytes.length);
	const out = dec.decode(
		new Uint8Array(x.memory.buffer, x.result_ptr(), x.result_len()),
	);
	if (rc !== 0) throw new Error(`expr.wasm request failed (${rc}): ${out}`);
	return JSON.parse(out) as T;
}

// The last parse of each kind (expression, template): a keystroke that
// re-scans the same text reuses it.
const cache: ({ src: string; result: ParseResult } | null)[] = [null, null];

/** Parses an expression, or a template when `template` is true. Throws if the core is not loaded. */
export function parseExpr(src: string, template: boolean): ParseResult {
	const slot = template ? 1 : 0;
	const hit = cache[slot];
	if (hit && hit.src === src) return hit.result;
	const result = call<ParseResult>({ op: "parse", src, template });
	cache[slot] = { src, result };
	return result;
}

/** The canonical text of an expression at `width` characters, or null when it has problems. */
export function formatExpr(src: string, width: number): string | null {
	const r = call<{ text: string | null }>({ op: "format", src, width });
	return r.text;
}
