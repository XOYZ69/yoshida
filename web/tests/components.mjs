// Checks the component helpers of the builder (src/lib/components.ts):
// filling a design's including groups in, splitting an edited design back
// into the design and component files, detached copies and the include checks.
//
//   node --experimental-strip-types tests/components.mjs
import {
	componentAround,
	componentPath,
	detached,
	expandIncludes,
	includeBlocker,
	includedPaths,
	includersOf,
	isComponentFile,
	splitIncludes,
} from "../src/lib/components.ts";
import { findLayer, moveLayer } from "../src/lib/design.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const row = {
	format: 1,
	name: "Effect row",
	note: "kept",
	layers: [
		{ id: "bg", type: "rect", box: { x: 0, y: 0, w: 10, h: 10 } },
		{ id: "inner", type: "group", include: "c/icon.component.json" },
	],
};
const icon = {
	format: 1,
	layers: [{ id: "dot", type: "ellipse", box: { x: 1, y: 1, w: 2, h: 2 } }],
};
const design = {
	format: 1,
	canvas: { width: 100, height: 100 },
	layers: [
		{ id: "title", type: "text", at: { x: 5, y: 5 }, text: "T" },
		{ id: "effects", type: "group", include: "c/row.component.json", translate: { x: 3, y: 4 } },
		{ id: "plain", type: "group", layers: [] },
	],
};
const files = {
	"designs/a.design.json": JSON.stringify(design),
	"c/row.component.json": JSON.stringify(row),
	"c/icon.component.json": JSON.stringify(icon),
	"yoshida.json": JSON.stringify({ format: 1, sets: [] }),
};
const read = (p) => files[p];

ok(
	"included paths, nested ones too",
	same(includedPaths(design, read), ["c/row.component.json", "c/icon.component.json"]),
);
const full = expandIncludes(design, read);
ok("the file's object is not changed", design.layers[1].layers === undefined);
ok("component layers are filled in", !!findLayer(full, "bg") && !!findLayer(full, "dot"));
ok("the group keeps its include", findLayer(full, "effects").include === "c/row.component.json");
ok("a layer knows its component", componentAround(full, "bg")?.id === "effects");
ok("the innermost component counts", componentAround(full, "dot")?.id === "inner");
ok("a design layer has none", componentAround(full, "title") === null);

// Round trip without an edit: nothing to write.
let out = splitIncludes(full, read);
ok("unchanged: the design is as in the file", same(out.design, design));
ok("unchanged: no component is written", out.components.size === 0);

// An edit inside the component goes to its file, other fields are kept.
let edited = structuredClone(full);
findLayer(edited, "bg").fill = "#FF0000";
out = splitIncludes(edited, read);
ok("edit inside: the design file is unchanged", same(out.design, design));
const written = out.components.get("c/row.component.json");
ok("edit inside: the component gets the layer", written?.layers[0].fill === "#FF0000");
ok("edit inside: name and note are kept", written?.name === "Effect row" && written?.note === "kept");
ok("edit inside: the nested include stays bare", same(written?.layers[1], row.layers[1]));
ok("edit inside: the nested component is untouched", !out.components.has("c/icon.component.json"));

// An edit in the nested component only writes that one.
edited = structuredClone(full);
findLayer(edited, "dot").fill = "#00FF00";
out = splitIncludes(edited, read);
ok(
	"nested edit writes only the inner file",
	out.components.size === 1 && out.components.get("c/icon.component.json")?.layers[0].fill === "#00FF00",
);

// Moving the including group changes its translate, never the shared layers.
edited = structuredClone(full);
moveLayer(edited, "effects", 10, 20, { w: 100, h: 100 });
out = splitIncludes(edited, read);
ok("moving a component moves its translate", same(findLayer(out.design, "effects").translate, { x: 13, y: 24 }));
ok("moving a component leaves its file alone", out.components.size === 0);
const bare = expandIncludes(
	{ layers: [{ id: "g", type: "group", include: "c/icon.component.json" }] },
	read,
);
moveLayer(bare, "g", 5, 6, { w: 100, h: 100 });
out = splitIncludes(bare, read);
ok("a component without a translate gets one", same(out.design.layers[0].translate, { x: 5, y: 6 }) && out.components.size === 0);

// Creating: a group that gains an include makes the file.
edited = structuredClone(full);
const plain = findLayer(edited, "plain");
plain.layers = [{ id: "new", type: "rect" }];
plain.include = "c/new.component.json";
out = splitIncludes(edited, read);
ok("create: the file is made", same(out.components.get("c/new.component.json"), { format: 1, name: "new", layers: [{ id: "new", type: "rect" }] }));
ok("create: the group keeps only the include", findLayer(out.design, "plain").layers === undefined);

// Detaching: without the include the layers stay in the design.
edited = structuredClone(full);
delete findLayer(edited, "effects").include;
out = splitIncludes(edited, read);
ok("detach: the layers are the design's", findLayer(out.design, "effects").layers.length === 2 && out.components.size === 0);
ok("detach: an inner component stays included", same(findLayer(out.design, "inner"), row.layers[1]));

const copy = detached(findLayer(full, "effects"));
ok("a detached copy includes nothing", copy.include === undefined && copy.layers[1].include === undefined && copy.layers[1].layers.length === 1);
ok("detaching leaves the original", findLayer(full, "effects").include !== undefined);

// A group with both layers and include (an error in the file) is not touched.
const both = { layers: [{ id: "g", type: "group", include: "c/icon.component.json", layers: [{ id: "own", type: "rect" }] }] };
const bothFull = expandIncludes(both, read);
ok("both: the own layers stay", !!findLayer(bothFull, "own") && !findLayer(bothFull, "dot"));
findLayer(bothFull, "own").fill = "#000000";
out = splitIncludes(bothFull, read);
ok("both: the component is never overwritten", out.components.size === 0);
ok("both: the include comes back", out.design.layers[0].include === "c/icon.component.json" && out.design.layers[0].layers[0].fill === "#000000");

// Missing, broken, cyclic and repeated includes stay bare.
const odd = {
	layers: [
		{ id: "a", type: "group", include: "missing.json" },
		{ id: "b", type: "group", include: "broken.json" },
		{ id: "c", type: "group", include: "loop.json" },
		{ id: "d", type: "group", include: "c/icon.component.json" },
		{ id: "e", type: "group", include: "c/icon.component.json" },
	],
};
const oddRead = (p) =>
	({ "broken.json": "{", "loop.json": JSON.stringify({ format: 1, layers: [{ id: "again", type: "group", include: "loop.json" }] }) })[p] ?? read(p);
const oddFull = expandIncludes(odd, oddRead);
ok("missing and broken includes stay bare", oddFull.layers[0].layers === undefined && oddFull.layers[1].layers === undefined);
ok("a cycle is filled in once", oddFull.layers[2].layers.length === 1 && oddFull.layers[2].layers[0].layers === undefined);
ok("a second include of a component stays bare", oddFull.layers[3].layers.length === 1 && oddFull.layers[4].layers === undefined);
out = splitIncludes(oddFull, oddRead);
ok("odd includes round trip", same(out.design, odd) && out.components.size === 0);

ok("component files are recognised", isComponentFile("c/row.component.json", files["c/row.component.json"]));
ok("a design is not a component", !isComponentFile("designs/a.design.json", files["designs/a.design.json"]));
ok("the manifest is not a component", !isComponentFile("yoshida.json", files["yoshida.json"]));
ok(
	"who includes a component",
	same(includersOf("c/icon.component.json", Object.keys(files), read), ["c/row.component.json"]) &&
		same(includersOf("c/row.component.json", Object.keys(files), read), ["designs/a.design.json"]),
);
ok("a used component cannot be included again", includeBlocker(full, "c/row.component.json", read) === "already in this design");
ok(
	"a component with a taken id is refused",
	/layer id 'dot'/.test(includeBlocker({ layers: [{ id: "dot", type: "rect" }] }, "c/icon.component.json", read)),
);
ok("a fitting component is allowed", includeBlocker({ layers: [{ id: "x", type: "rect" }] }, "c/icon.component.json", read) === "");
ok("component paths are slugs", componentPath("Effect Row!", () => false) === "components/effect-row.component.json");
ok("component paths avoid files", componentPath("a", (p) => p === "components/a.component.json") === "components/a-2.component.json");

process.exit(failed ? 1 : 0);
