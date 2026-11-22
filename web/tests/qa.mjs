// Checks the card review helpers of the editor (src/lib/qa.ts).
//
//   node --experimental-strip-types tests/qa.mjs
import {
	cardHash,
	designInputs,
	hashText,
	needsReview,
	parseQa,
	stableJson,
	statusOf,
	tally,
	withNote,
	withReview,
	writeQa,
} from "../src/lib/qa.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const bytes = (s) => new TextEncoder().encode(s);

ok("stableJson ignores key order", stableJson({ b: 1, a: [{ d: 1, c: 2 }] }) === stableJson({ a: [{ c: 2, d: 1 }], b: 1 }));
ok("hashText is deterministic and 14 hex digits", hashText("x") === hashText("x") && /^[0-9a-f]{14}$/.test(hashText("x")));
ok("hashText tells texts apart", hashText("a") !== hashText("b"));

const files = new Map([
	["designs/a.design.json", bytes('{"name":"A"}')],
	["components/r.component.json", bytes('{"r":1}')],
	["assets/x.png", bytes("png")],
]);
const inputs = designInputs(files, "designs/a.design.json");
const card = { id: "1", values: { title: "Hi", n: 2 } };
const h = cardHash(card, inputs);
ok("same card, same hash", h === cardHash({ id: "1", values: { n: 2, title: "Hi" } }, inputs));
ok("a changed value changes the hash", h !== cardHash({ id: "1", values: { title: "Ho", n: 2 } }, inputs));
ok("a renamed id changes the hash", h !== cardHash({ ...card, id: "2" }, inputs));
const edited = new Map(files).set("designs/a.design.json", bytes('{"name":"B"}'));
ok("a design edit changes the hash", h !== cardHash(card, designInputs(edited, "designs/a.design.json")));
const comp = new Map(files).set("components/r.component.json", bytes('{"r":2}'));
ok("a component edit changes the hash", h !== cardHash(card, designInputs(comp, "designs/a.design.json")));
const img = new Map(files).set("assets/x.png", bytes("other"));
ok("an image edit does not", h === cardHash(card, designInputs(img, "designs/a.design.json")));

ok("no entry is unreviewed", statusOf(undefined, h) === "unreviewed");
ok("a matching approval holds", statusOf({ status: "approved", hash: h }, h) === "approved");
ok("an approval of other content is stale", statusOf({ status: "approved", hash: h }, "zz") === "stale");
ok("needs-changes stays whatever the hash", statusOf({ status: "needs-changes", hash: h }, "zz") === "needs-changes");
ok("unreviewed and stale need review", needsReview("unreviewed") && needsReview("stale") && !needsReview("approved") && !needsReview("needs-changes"));

let doc = withReview(parseQa(undefined), "cards/a.cards.json", "1", "approved", h);
doc = withReview(doc, "cards/a.cards.json", "2", "needs-changes", "x", "  fix title ");
ok("a note is trimmed", doc.cards["cards/a.cards.json"]["2"].note === "fix title");
doc = withNote(doc, "cards/a.cards.json", "1", "ok");
ok("a note keeps the mark and hash", doc.cards["cards/a.cards.json"]["1"].hash === h && doc.cards["cards/a.cards.json"]["1"].note === "ok");
ok("a note on a card without an entry is ignored", withNote(doc, "cards/a.cards.json", "9", "n") === doc);
const text = writeQa(doc);
ok("round trip", writeQa(parseQa(text)) === text);
ok("canonical text ends with a newline", text.endsWith("\n") && text.startsWith('{\n  "format": 1,'));
const cleared = withReview(doc, "cards/a.cards.json", "1", null, h);
ok("clearing removes the entry", !("1" in cleared.cards["cards/a.cards.json"]));
ok("empty sets are not written", !writeQa(withReview(withReview(parseQa(undefined), "k", "1", "approved", h), "k", "1", null, h)).includes('"k"'));

ok("bad JSON is an empty document", Object.keys(parseQa("{nope").cards).length === 0);
const bad = parseQa('{"format":1,"cards":{"k":{"1":{"status":"maybe"},"2":{"status":"approved","hash":"a","note":3},"3":null},"j":[]}}');
ok("bad entries are dropped", Object.keys(bad.cards.k).join() === "2" && !bad.cards.k["2"].note && !bad.cards.j);

const t = tally(["approved", "stale", "stale", "unreviewed"]);
ok("tally counts", t.approved === 1 && t.stale === 2 && t.unreviewed === 1 && t["needs-changes"] === 0);

if (failed) {
	console.log(`${failed} FAILED`);
	process.exit(1);
}
