// Checks the quick actions on expressions (src/lib/expr/rewrite.ts) against
// expr.wasm, without a browser.
//
//   node --experimental-strip-types tests/expr-rewrite.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import * as R from "../src/lib/expr/rewrite.ts";

const wasmPath = fileURLToPath(new URL("../public/expr.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const x = instance.exports;
const enc = new TextEncoder();
const dec = new TextDecoder();

/** One request to the core: [return code, parsed JSON response]. */
function call(req) {
	const bytes = enc.encode(JSON.stringify(req));
	const p = x.alloc(bytes.length);
	new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
	const rc = x.request(p, bytes.length);
	x.free(p, bytes.length);
	const out = dec.decode(
		new Uint8Array(x.memory.buffer, x.result_ptr(), x.result_len()),
	);
	return [rc, JSON.parse(out)];
}

const core = {
	parse(src) {
		const [, r] = call({ op: "parse", src, template: false });
		return { root: r.root, problems: r.problems };
	},
	format(src, width) {
		const [, r] = call({ op: "format", src, width });
		return r.text;
	},
};

/** Parses text and returns its root, for tests that need a tree. */
const rootOf = (text) => core.parse(text).root;

/** The tree without ids and spans, to compare shapes. */
const shape = (n) =>
	JSON.stringify(n, (k, v) => (k === "id" || k === "span" ? undefined : v));

/** The node covering text.indexOf(sub) .. the same length. */
function at(text, sub, root = rootOf(text)) {
	const from = text.indexOf(sub);
	return R.nodeAt(root, from, from + sub.length);
}

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const DESIGN = {
	params: { a: { type: "number", default: 1 } },
	consts: { base: 10 },
	functions: { twice: { args: ["v"], expr: "v * 2" } },
};

// 1. A three-way chain on one subject becomes a match.
{
	const text = "s == 'a' ? 1 : s == 'b' ? 2 : s == 'c' ? 3 : 4";
	const r = R.condChainToMatch(core, text, rootOf(text));
	ok(
		"three-way chain to match",
		r?.text === "match(s, 'a', 1, 'b', 2, 'c', 3, 4)",
		r?.text,
	);
}

// 2. The subject on the right side of the comparison.
{
	const text = "'a' == s ? 1 : 'b' == s ? 2 : 3";
	const r = R.condChainToMatch(core, text, rootOf(text));
	ok(
		"subject on the right side",
		r?.text === "match(s, 'a', 1, 'b', 2, 3)",
		r?.text,
	);
}

// 3. An `in` condition gives its keys the same result.
{
	const text = "s in [1, 2] ? 'x' : s == 3 ? 'y' : 'z'";
	const r = R.condChainToMatch(core, text, rootOf(text));
	ok(
		"`in` condition expands into keys",
		r?.text === "match(s, 1, 'x', 2, 'x', 3, 'y', 'z')",
		r?.text,
	);
}

// 4. Different subjects, a single condition, or a non-equality: no rewrite.
{
	const mixed = "a == 1 ? 1 : b == 2 ? 2 : 3";
	const single = "s == 1 ? 1 : 2";
	const less = "s < 1 ? 1 : s == 2 ? 2 : 3";
	ok(
		"non-uniform subjects give null",
		R.condChainToMatch(core, mixed, rootOf(mixed)) === null,
	);
	ok(
		"a single condition gives null",
		R.condChainToMatch(core, single, rootOf(single)) === null,
	);
	ok(
		"a `<` condition gives null",
		R.condChainToMatch(core, less, rootOf(less)) === null,
	);
}

// 5. A match back to a chain.
{
	const text = "match(k, 1, 'x', 2, 'y', 'z')";
	const r = R.matchToCondChain(core, text, rootOf(text));
	ok(
		"match to chain",
		r?.text === "k == 1 ? 'x' : k == 2 ? 'y' : 'z'" && r.note === undefined,
		r?.text,
	);
}

// 6. Chain to match and back gives the same tree shape.
{
	const chain = "s == 'a' ? 1 + x : s == 'b' ? (y ? 2 : 3) : 4";
	const m = R.condChainToMatch(core, chain, rootOf(chain));
	const back = m && R.matchToCondChain(core, m.text, rootOf(m.text));
	ok(
		"chain to match and back keeps the shape",
		back !== null &&
			back !== undefined &&
			shape(rootOf(back.text)) === shape(rootOf(chain)),
		`${m?.text} / ${back?.text}`,
	);
}

// 7. A computed subject works with a note: it is evaluated per condition.
{
	const text = "match(a + 1, 1, 'x', 'y')";
	const r = R.matchToCondChain(core, text, rootOf(text));
	ok(
		"computed subject gives a note",
		r?.text === "a + 1 == 1 ? 'x' : 'y'" &&
			r.note === "the subject is evaluated once per condition",
		JSON.stringify(r),
	);
}

// 8. Extracting a const replaces the text and adds the const.
{
	const text = "a + canvas.w * 0.5";
	const before = JSON.stringify(DESIGN);
	const r = R.extractConst(
		core,
		text,
		at(text, "canvas.w * 0.5"),
		"half_w",
		[],
		DESIGN,
	);
	ok("extract const replaces the text", r?.text === "a + half_w", r?.text);
	ok(
		"extract const adds the const",
		r?.design.consts?.half_w === "canvas.w * 0.5" &&
			r.design.consts.base === 10 &&
			JSON.stringify(DESIGN) === before,
		JSON.stringify(r?.design),
	);
}

// 9. Extracting a const is refused for locals, layer refs and taken names.
{
	const local = "n * 2";
	const layer = "@t.bounds.cx + 1";
	ok(
		"extract const refused for a local",
		R.extractConst(core, local, at(local, "n * 2"), "dbl", ["n"], DESIGN) ===
			null,
	);
	ok(
		"extract const refused for a layer ref",
		R.extractConst(
			core,
			layer,
			at(layer, "@t.bounds.cx + 1"),
			"dbl",
			[],
			DESIGN,
		) === null,
	);
	const taken = ["a", "base", "twice", "min", "match", "canvas", "Bad", "1x"];
	const text = "a + base * 3";
	const refused = taken.filter(
		(name) =>
			R.extractConst(core, text, at(text, "base * 3"), name, [], DESIGN) !==
			null,
	);
	ok(
		"extract const refused for taken or reserved names",
		refused.length === 0,
		`accepted: ${refused.join(", ")}`,
	);
}

// 10. Extracting a function gives `f(i)` and the function with its args.
{
	const text = "a + i * 2";
	const node = at(text, "i * 2");
	const used = R.freeNames(node, ["i", "j"]);
	ok(
		"freeNames finds the used locals",
		same(used, ["i"]),
		JSON.stringify(used),
	);
	const r = R.extractFunction(
		core,
		text,
		node,
		"slot",
		["i", "j"],
		[{ name: "i", type: "number" }],
		DESIGN,
	);
	ok("extract function gives a call", r?.text === "a + slot(i)", r?.text);
	ok(
		"extract function adds the function",
		same(r?.design.functions?.slot, {
			args: { i: "number" },
			expr: "i * 2",
		}),
		JSON.stringify(r?.design.functions),
	);
	const missing = R.extractFunction(
		core,
		text,
		node,
		"slot",
		["i", "j"],
		[],
		DESIGN,
	);
	ok("extract function refused without its free names", missing === null);
}

// 11. nodeAt gives the smallest covering node.
{
	const text = "a + b * c";
	const root = rootOf(text);
	const inner = R.nodeAt(root, 4, 9);
	ok(
		"nodeAt gives the smallest covering node",
		inner?.k === "binary" && inner.op === "*",
		JSON.stringify(inner?.k),
	);
	ok("nodeAt of the whole text is the root", R.nodeAt(root, 0, 9) === root);
	ok("nodeAt outside the text is null", R.nodeAt(root, 50, 51) === null);
}

// 12. The reserved and function names match catalog.ts.
{
	const catalog = readFileSync(
		fileURLToPath(new URL("../src/lib/expr/catalog.ts", import.meta.url)),
		"utf8",
	);
	const fns = [...catalog.matchAll(/name: "([a-z_]+)",\n\t\targs:/g)].map(
		(m) => m[1],
	);
	const builtins = [...catalog.matchAll(/^\t([a-z_]+): \{\n\t\tdoc:/gm)].map(
		(m) => m[1],
	);
	ok(
		"FUNCTION_NAMES matches catalog.ts",
		same([...R.FUNCTION_NAMES].sort(), [...new Set(fns)].sort()),
		JSON.stringify(fns),
	);
	ok(
		"BUILTIN_NAMES matches catalog.ts",
		same([...R.BUILTIN_NAMES].sort(), [...new Set(builtins)].sort()),
		JSON.stringify(builtins),
	);
}

// Extracting inside a function puts the new one above it, on one line.
{
	const text = "match(v, 1, 'one', 2, 'two', 'many') + 'x'";
	const node = at(text, "match(v, 1, 'one', 2, 'two', 'many')");
	const r = R.extractFunction(
		core,
		text,
		node,
		"word",
		["v"],
		[{ name: "v", type: "number" }],
		DESIGN,
		"twice",
	);
	ok(
		"extract function goes above the function it came from",
		r !== null &&
			JSON.stringify(Object.keys(r.design.functions)) === '["word","twice"]',
		JSON.stringify(r?.design.functions),
	);
	ok(
		"extracted body stays on one line",
		r !== null && !r.design.functions.word.expr.includes("\n"),
		JSON.stringify(r?.design.functions.word),
	);
}

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
