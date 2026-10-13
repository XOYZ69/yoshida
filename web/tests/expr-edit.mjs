// Checks the formula panel's edits (src/lib/expr/edit.ts) against expr.wasm:
// a match result, match rows, a ?: chain row, a cell that does not parse,
// and `in` chips. Run without a browser:
//
//   node --experimental-strip-types tests/expr-edit.mjs [path/to/expr.wasm]
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
	addChip,
	addMatchRow,
	condChain,
	listView,
	matchView,
	removeChip,
	removeMatchRow,
	replaceSlot,
} from "../src/lib/expr/edit.ts";

const wasmPath =
	process.argv[2] ??
	fileURLToPath(new URL("../public/expr.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const x = instance.exports;
const enc = new TextEncoder();
const dec = new TextDecoder();

/** One request to the core: the parsed JSON response. */
function call(req) {
	const bytes = enc.encode(JSON.stringify(req));
	const p = x.alloc(bytes.length);
	new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
	const rc = x.request(p, bytes.length);
	x.free(p, bytes.length);
	const out = dec.decode(
		new Uint8Array(x.memory.buffer, x.result_ptr(), x.result_len()),
	);
	if (rc !== 0) throw new Error(`request failed (${rc}): ${out}`);
	return JSON.parse(out);
}

const format = (src, width) => call({ op: "format", src, width }).text;
const rootOf = (src) => call({ op: "parse", src, template: false }).root;

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${cond ? "" : extra}`);
};

// Replacing a match result: the text is re-laid-out, the rest is kept.
{
	const text = "match(k, 'a', 1, 'b', 2, 0)";
	const root = rootOf(text);
	const mv = matchView(root, text);
	ok(
		"match view has the subject, two rows and the default",
		mv?.rows.length === 2 &&
			mv.subject.text === "k" &&
			mv.fallback.text === "0",
		JSON.stringify(mv),
	);
	const next = replaceSlot(text, mv.rows[0].result.span, "5 * 2", format);
	ok(
		"replacing a match result keeps the other slots",
		next === "match(k, 'a', 5 * 2, 'b', 2, 0)",
		String(next),
	);
}

// Adding and removing match rows.
{
	const text = "match(k, 'a', 1, 0)";
	const root = rootOf(text);
	const added = addMatchRow(text, root, format);
	ok(
		"+ row adds 'key' with the default as its result, before the default",
		added === "match(k, 'a', 1, 'key', 0, 0)",
		String(added),
	);
	const two = "match(k, 'a', 1, 'b', 2, 0)";
	const removed = removeMatchRow(two, rootOf(two), 0, format);
	ok(
		"removing the first row keeps the second",
		removed === "match(k, 'b', 2, 0)",
		String(removed),
	);
	ok(
		"removing the only row is refused",
		removeMatchRow(text, root, 0, format) === null,
	);
}

// A ?: chain: rows, and a row edit.
{
	const text = "a == 1 ? 'x' : b == 2 ? 'y' : 'z'";
	const root = rootOf(text);
	const chain = condChain(root, text);
	ok(
		"a chain has two rows and a fallback",
		chain?.rows.length === 2 && chain.fallback.text === "'z'",
		JSON.stringify(chain),
	);
	const next = replaceSlot(text, chain.rows[1].result.span, "'w'", format);
	ok(
		"editing a chain row changes only that row",
		next === "a == 1 ? 'x' : b == 2 ? 'w' : 'z'",
		String(next),
	);
	ok(
		"a single cond is a chain of one row",
		condChain(rootOf("a ? 1 : 2"), "a ? 1 : 2")?.rows.length === 1,
	);
}

// A cell that does not parse gives null; the caller keeps the text.
{
	const text = "match(k, 'a', 1, 0)";
	const mv = matchView(rootOf(text), text);
	ok(
		"a cell that does not parse gives null",
		replaceSlot(text, mv.rows[0].result.span, "1 +", format) === null,
	);
	ok(
		"a cell with a stray comma gives null",
		replaceSlot(text, mv.rows[0].result.span, "1, 2", format) === null,
	);
}

// Not a match: no match view.
ok(
	"a match with a key and no result has no view",
	matchView(rootOf("match(k, 'a', 1, 'b', 2)"), "match(k, 'a', 1, 'b', 2)") ===
		null,
);
ok(
	"a call of another name has no match view",
	matchView(rootOf("max(1, 2, 3, 4)"), "max(1, 2, 3, 4)") === null,
);

// `in` chips: add and remove. The value is parenthesised on rewrite.
{
	const text = "a + 1 in [1, 2]";
	const root = rootOf(text);
	const lv = listView(root, text);
	ok(
		"in_list view has the value and two chips",
		lv?.items.length === 2 && lv.value.text === "a + 1",
		JSON.stringify(lv),
	);
	ok(
		"adding a chip keeps the value",
		addChip(text, root, "3", format) === "a + 1 in [1, 2, 3]",
		String(addChip(text, root, "3", format)),
	);
	ok(
		"adding an empty chip is refused",
		addChip(text, root, "  ", format) === null,
	);
	ok(
		"removing a chip",
		removeChip(text, root, 0, format) === "a + 1 in [2]",
		String(removeChip(text, root, 0, format)),
	);
	ok(
		"removing the last chip is refused (an empty list does not parse)",
		removeChip("x in [1]", rootOf("x in [1]"), 0, format) === null,
	);
}

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
