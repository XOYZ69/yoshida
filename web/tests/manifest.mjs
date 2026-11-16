// Checks the manifest helpers of the editor (src/lib/project.ts).
//
//   node --experimental-strip-types tests/manifest.mjs
import { groupSets, newProjectFiles, withSet } from "../src/lib/project.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const dec = new TextDecoder();

const a = JSON.parse(withSet(undefined, { name: "a", design: "d.design.json" }));
ok("a missing manifest starts as format 1", a.format === 1 && a.sets.length === 1);

const b = JSON.parse(
	withSet(JSON.stringify({ format: 1, name: "X", sets: [{ name: "a", design: "d" }] }), {
		name: "b",
		design: "e",
		cards: "c",
	}),
);
ok("a set is appended and the rest is kept", b.name === "X" && b.sets.length === 2 && b.sets[1].name === "b");

const c = JSON.parse(withSet(JSON.stringify({ format: 1, sets: [{ name: "a", design: "d" }] }), { name: "a", design: "z" }));
ok("a set of the same name is replaced", c.sets.length === 1 && c.sets[0].design === "z");

let threw = false;
try {
	withSet("[]", { name: "a", design: "d" });
} catch {
	threw = true;
}
ok("a manifest that is not an object throws", threw);

const f = newProjectFiles("My cards", "my-cards");
const m = JSON.parse(dec.decode(f.get("yoshida.json")));
ok("a new project has a manifest with its set", m.name === "My cards" && m.sets[0].design === "designs/my-cards.design.json");
ok("a new project has the design and the cards", f.has("designs/my-cards.design.json") && f.has("cards/my-cards.cards.json") && f.size === 3);

const g = groupSets([
	{ n: 1, group: "A" },
	{ n: 2, group: "B" },
	{ n: 3, group: "A" },
	{ n: 4, group: "B" },
]);
ok("sets are grouped, keeping order inside a group", g.map((x) => x.n).join("") === "1324");

if (failed) process.exit(1);
