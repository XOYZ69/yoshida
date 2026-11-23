// Checks the card review helpers of the editor (src/lib/qa.ts).
//
//   node --experimental-strip-types tests/qa.mjs
import {
	cardHash,
	designFingerprint,
	hashText,
	needsReview,
	parseQa,
	reconcileQa,
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
const inputs = designFingerprint(files, "designs/a.design.json");
const card = { id: "1", values: { title: "Hi", n: 2 } };
const h = cardHash(card, inputs);
ok("same card, same hash", h === cardHash({ id: "1", values: { n: 2, title: "Hi" } }, inputs));
ok("a changed value changes the hash", h !== cardHash({ id: "1", values: { title: "Ho", n: 2 } }, inputs));
ok("a renamed id does not change the hash", h === cardHash({ ...card, id: "2" }, inputs));
const idFiles = new Map(files).set("designs/a.design.json", bytes('{"t":"card.id"}'));
const idInputs = designFingerprint(idFiles, "designs/a.design.json");
ok("a design that reads card.id hashes the id", cardHash(card, idInputs) !== cardHash({ ...card, id: "2" }, idInputs));
ok("a reformat is not an edit", designFingerprint(new Map(files).set("designs/a.design.json", bytes('{\n  "name": "A"\n}')), "designs/a.design.json").print === inputs.print);
const inc = new Map(files).set("designs/a.design.json", bytes('{"layers":[{"include":"components/r.component.json"}]}'));
const incPrint = designFingerprint(inc, "designs/a.design.json").print;
ok("an included component counts", incPrint !== designFingerprint(new Map(inc).set("components/r.component.json", bytes('{"r":2}')), "designs/a.design.json").print);
ok("a component that is not included does not", inputs === inputs && designFingerprint(new Map(files).set("components/r.component.json", bytes('{"r":9}')), "designs/a.design.json").print === inputs.print);
const edited = new Map(files).set("designs/a.design.json", bytes('{"name":"B"}'));
ok("a design edit changes the hash", h !== cardHash(card, designFingerprint(edited, "designs/a.design.json")));
const img = new Map(files).set("assets/x.png", bytes("other"));
ok("an image edit does not", h === cardHash(card, designFingerprint(img, "designs/a.design.json")));

ok("no entry is unreviewed", statusOf(undefined, h) === "unreviewed");
ok("a matching approval holds", statusOf({ status: "approved", hash: h }, h) === "approved");
ok("an approval of other content is stale", statusOf({ status: "approved", hash: h }, "zz") === "stale");
ok("needs-changes stays whatever the hash", statusOf({ status: "needs-changes", hash: h }, "zz") === "needs-changes");
ok("everything but an up to date approval needs review", needsReview("unreviewed") && needsReview("stale") && needsReview("needs-changes") && !needsReview("approved"));

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

const rd = withReview(withReview(parseQa(undefined), "a.cards.json", "1", "approved", "h1"), "a.cards.json", "2", "needs-changes", "h2", "fix");
const moved = reconcileQa(rd, [
	{ key: "a.cards.json", cards: [{ id: "one", hash: "h1" }] },
	{ key: "b.cards.json", cards: [{ id: "x", hash: "h2" }, { id: "y", hash: "h9" }] },
]);
ok("a renamed id keeps its review", moved.cards["a.cards.json"].one?.status === "approved" && !moved.cards["a.cards.json"]["1"]);
ok("a card moved to another set keeps its review and note", moved.cards["b.cards.json"].x?.note === "fix" && !moved.cards["a.cards.json"]["2"]);
ok("a card with new content starts over", !moved.cards["b.cards.json"].y);
ok("nothing to follow gives the same document", reconcileQa(rd, [{ key: "a.cards.json", cards: [{ id: "1", hash: "h1" }, { id: "2", hash: "h2" }] }]) === rd);
const dup = reconcileQa(withReview(parseQa(undefined), "k", "old", "approved", "h"), [{ key: "k", cards: [{ id: "a", hash: "h" }, { id: "b", hash: "h" }] }]);
ok("identical cards share one review only once", Object.keys(dup.cards.k).join() === "a");

const t = tally(["approved", "stale", "stale", "unreviewed"]);
ok("tally counts", t.approved === 1 && t.stale === 2 && t.unreviewed === 1 && t["needs-changes"] === 0);

if (failed) {
	console.log(`${failed} FAILED`);
	process.exit(1);
}
