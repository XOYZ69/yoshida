// Checks the card review helpers of the editor (src/lib/qa.ts).
//
//   node --experimental-strip-types tests/qa.mjs
import {
	cardHash,
	contentHash,
	designFingerprint,
	hashText,
	needsReview,
	parseQa,
	reconcileQa,
	stableJson,
	statusOf,
	tally,
	openComments,
	withComment,
	withCommentEdit,
	withMark,
	withoutComment,
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

const K = "cards/a.cards.json";
let doc = withMark(parseQa(undefined), K, "1", "approved", h, { by: "yuki", at: "2026-11-23T04:00Z" });
ok("a mark records who and when", doc.cards[K]["1"].by === "yuki" && doc.cards[K]["1"].at === "2026-11-23T04:00Z");
let r = withComment(doc, K, "1", h, { text: "  fix title ", x: 10.4, y: 20.6, by: "yuki" });
doc = r.doc;
ok("a comment is added with a pin", r.id === "c1" && doc.cards[K]["1"].comments[0].x === 10 && doc.cards[K]["1"].comments[0].y === 21);
ok("a comment keeps the mark", doc.cards[K]["1"].status === "approved");
ok("an open comment means needs changes", statusOf(doc.cards[K]["1"], h) === "needs-changes");
doc = withCommentEdit(doc, K, "1", "c1", { resolved: true });
ok("resolving brings the mark back", statusOf(doc.cards[K]["1"], h) === "approved" && openComments(doc.cards[K]["1"]).length === 0);
r = withComment(doc, K, "1", h, { text: "second" });
ok("comment ids count up", r.id === "c2");
doc = withCommentEdit(r.doc, K, "1", "c2", { text: "  " });
ok("an emptied comment is removed", doc.cards[K]["1"].comments.length === 1);
doc = withCommentEdit(doc, K, "1", "c1", { x: undefined, y: undefined });
ok("a pin can be removed", doc.cards[K]["1"].comments[0].x === undefined);
const onlyComment = withComment(parseQa(undefined), K, "7", h, { text: "look" }).doc;
ok("a comment without a mark counts as needs changes", statusOf(onlyComment.cards[K]["7"], h) === "needs-changes");
const resolvedOnly = withCommentEdit(onlyComment, K, "7", "c1", { resolved: true });
ok("resolved comments without a mark are unreviewed", statusOf(resolvedOnly.cards[K]["7"], h) === "unreviewed");
ok("removing the last comment drops the entry", !(("7") in withoutComment(onlyComment, K, "7", "c1").cards[K]));
const noMark = withMark(doc, K, "1", null, h);
ok("clearing the mark keeps the comments", !noMark.cards[K]["1"].status && noMark.cards[K]["1"].comments.length === 1);
ok("clearing a card without comments drops it", !("1" in withMark(withMark(parseQa(undefined), K, "1", "approved", h), K, "1", null, h).cards[K]));
doc = withMark(doc, K, "2", "needs-changes", "x");
const text = writeQa(doc);
ok("round trip", writeQa(parseQa(text)) === text);
ok("canonical text is format 2 and ends with a newline", text.endsWith("\n") && text.startsWith('{\n  "format": 2,'));
const v1 = parseQa('{"format":1,"cards":{"k":{"1":{"status":"needs-changes","hash":"a","note":"fix it"},"2":{"status":"approved","hash":"b"}}}}');
ok("a format 1 note becomes a comment", v1.cards.k["1"].comments[0].text === "fix it" && v1.cards.k["1"].status === "needs-changes" && !v1.cards.k["2"].comments);
ok("an upgraded file is written as format 2", writeQa(v1).includes('"format": 2') && !writeQa(v1).includes('"note"'));
ok("empty sets are not written", !writeQa(withMark(withMark(parseQa(undefined), "k", "1", "approved", h), "k", "1", null, h)).includes('"k"'));

ok("bad JSON is an empty document", Object.keys(parseQa("{nope").cards).length === 0);
const bad = parseQa('{"format":2,"cards":{"k":{"1":{"status":"maybe"},"2":{"status":"approved","hash":"a","comments":[{"id":"c1","text":""},{"text":"ok","x":"a"}]},"3":null},"j":[]}}');
ok("bad entries are dropped", Object.keys(bad.cards.k).join() === "2" && bad.cards.k["2"].comments.length === 1 && bad.cards.k["2"].comments[0].x === undefined && !bad.cards.j);

const rd = withComment(withMark(withMark(parseQa(undefined), "a.cards.json", "1", "approved", "h1"), "a.cards.json", "2", "needs-changes", "h2"), "a.cards.json", "2", "h2", { text: "fix" }).doc;
const moved = reconcileQa(rd, [
	{ key: "a.cards.json", cards: [{ id: "one", hash: "h1" }] },
	{ key: "b.cards.json", cards: [{ id: "x", hash: "h2" }, { id: "y", hash: "h9" }] },
]);
ok("a renamed id keeps its review", moved.cards["a.cards.json"].one?.status === "approved" && !moved.cards["a.cards.json"]["1"]);
ok("a card moved to another set keeps its review and note", moved.cards["b.cards.json"].x?.comments?.[0].text === "fix" && !moved.cards["a.cards.json"]["2"]);
ok("a card with new content starts over", !moved.cards["b.cards.json"].y);
ok("nothing to follow gives the same document", reconcileQa(rd, [{ key: "a.cards.json", cards: [{ id: "1", hash: "h1" }, { id: "2", hash: "h2" }] }]) === rd);
const dup = reconcileQa(withMark(parseQa(undefined), "k", "old", "approved", "h"), [{ key: "k", cards: [{ id: "a", hash: "h" }, { id: "b", hash: "h" }] }]);
ok("identical cards share one review only once", Object.keys(dup.cards.k).join() === "a");

// A design that shows the card id: a rename must still find the review.
const idCard = { id: "1", values: { t: "x" } };
const ih = cardHash(idCard, idInputs);
const ic = contentHash(idCard, idInputs);
const idDoc = withMark(parseQa(undefined), "k", "1", "approved", ih, {}, ic);
ok("the content hash ignores the id", ic === contentHash({ ...idCard, id: "2" }, idInputs) && ih !== cardHash({ ...idCard, id: "2" }, idInputs));
const renamed = reconcileQa(idDoc, [{ key: "k", cards: [{ id: "2", hash: cardHash({ ...idCard, id: "2" }, idInputs), content: ic }] }]);
ok("a renamed card is found by its content hash", renamed.cards.k["2"]?.status === "approved");
ok("its approval is stale, as the id is drawn on the card", statusOf(renamed.cards.k["2"], cardHash({ ...idCard, id: "2" }, idInputs)) === "stale");
ok("the content hash survives a round trip", parseQa(writeQa(idDoc)).cards.k["1"].content === ic);

const t = tally(["approved", "stale", "stale", "unreviewed"]);
ok("tally counts", t.approved === 1 && t.stale === 2 && t.unreviewed === 1 && t["needs-changes"] === 0);

if (failed) {
	console.log(`${failed} FAILED`);
	process.exit(1);
}
