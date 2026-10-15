// Checks the expression core (expr.wasm) without a browser: token kinds and
// UTF-16 spans, problems, the tree root, templates, and the formatter.
//
//   node tests/expr-core.mjs [path/to/expr.wasm]
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const wasmPath =
	process.argv[2] ??
	fileURLToPath(new URL("../public/expr.wasm", import.meta.url));
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

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Tokens of `a + 10%`: name, op, number, unit.
{
	const src = "a + 10%";
	const [rc, r] = call({ op: "parse", src, template: false });
	ok(
		"tokens of `a + 10%`",
		rc === 0 &&
			same(r.tokens, [
				[0, 1, "name"],
				[2, 3, "op"],
				[4, 6, "number"],
				[6, 7, "unit"],
			]),
		JSON.stringify(r.tokens),
	);
}

// Spans are UTF-16 offsets: ♥ is one unit, an emoji is two.
{
	const src = "'♥' + x";
	const [, r] = call({ op: "parse", src, template: false });
	const str = r.tokens.find((t) => t[2] === "string");
	const name = r.tokens.find((t) => t[2] === "name");
	ok(
		"spans of `'♥' + x` index the JS string",
		str &&
			src.slice(str[0], str[1]) === "'♥'" &&
			src.slice(name[0], name[1]) === "x",
		JSON.stringify(r.tokens),
	);
	const emoji = "'😀' + x";
	const [, e] = call({ op: "parse", src: emoji, template: false });
	const name2 = e.tokens.find((t) => t[2] === "name");
	ok(
		"spans count an emoji as two UTF-16 units",
		name2 && emoji.slice(name2[0], name2[1]) === "x" && name2[0] === 7,
		JSON.stringify(e.tokens),
	);
}

// A call left open: a problem, and the tree still has a call at the root.
{
	const [rc, r] = call({ op: "parse", src: "max(1, ", template: false });
	ok(
		"`max(1, ` has a problem",
		rc === 0 && r.problems.length >= 1,
		JSON.stringify(r.problems),
	);
	ok("`max(1, ` parses to a call at the root", r.root?.k === "call", r.root?.k);
}

// `!` is not an operator: a bad token.
{
	const [, r] = call({ op: "parse", src: "!a", template: false });
	ok(
		"`!a` gives a bad token",
		r.tokens.some((t) => t[2] === "bad"),
		JSON.stringify(r.tokens),
	);
}

// A template: text and braces around a hole.
{
	const src = "Lv {n}";
	const [, r] = call({ op: "parse", src, template: true });
	const kinds = r.tokens.map((t) => t[2]);
	ok(
		"template `Lv {n}` gives text, brace, name, brace",
		same(kinds, ["text", "brace", "name", "brace"]),
		JSON.stringify(r.tokens),
	);
	ok(
		"template hole spans include its braces",
		r.holes?.length === 1 && same(r.holes[0].span, [3, 6]),
		JSON.stringify(r.holes),
	);
}

// The formatter breaks a long call over lines, and the result parses cleanly.
{
	const src =
		"match(k, 'start', c_start, 'finish', c_finish, 'safe', c_safe, 'skip', c_skip, 'back', c_back, 'forward', c_forward, 'shortcut', c_shortcut, 'dare', c_dare, c_plain)";
	ok("the sample is 165 characters", src.length === 165, String(src.length));
	const [rc, f] = call({ op: "format", src, width: 60 });
	ok(
		"format at width 60 succeeds",
		rc === 0 && typeof f.text === "string",
		JSON.stringify(f.problems),
	);
	const text = f.text ?? "";
	ok("formatted output is multi-line", text.includes("\n"));
	const [, again] = call({ op: "parse", src: text, template: false });
	ok(
		"formatted output re-parses without problems",
		again.problems.length === 0,
		JSON.stringify(again.problems),
	);
	const [, idem] = call({ op: "format", src: text, width: 60 });
	ok("formatting the output again changes nothing", idem.text === text);
}

// A broken expression has no formatted text.
{
	const [, f] = call({ op: "format", src: "max(1, ", width: 60 });
	ok(
		"format returns null text for an expression with problems",
		f.text === null,
	);
}

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
