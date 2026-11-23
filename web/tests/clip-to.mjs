import assert from "node:assert/strict";
import { referencesTo, renameLayer, renameParam } from "../src/lib/design.ts";

// `clip_to` names a layer: renaming the layer follows it, and the layer it
// names lists the clipped layers among the ones that use it.
const doc = () => ({
	format: 1,
	name: "t",
	canvas: { width: 100, height: 100 },
	params: { frame: { type: "number", default: 1 } },
	layers: [
		{ id: "frame", type: "rect", box: { x: 0, y: 0, w: 10, h: 10 }, visible: false },
		{ id: "art", type: "rect", box: { x: 0, y: 0, w: 10, h: 10 }, clip_to: "frame" },
		{ id: "g", type: "group", clip_to: "frame", layers: [] },
	],
});

const d = doc();
assert.deepEqual(referencesTo(d, "frame"), ["art", "g"]);
renameLayer(d, "frame", "window");
assert.equal(d.layers[0].id, "window");
assert.equal(d.layers[1].clip_to, "window");
assert.equal(d.layers[2].clip_to, "window");

// A param of the same name is not a layer id: clip_to stays.
const p = doc();
renameParam(p, "frame", "size");
assert.equal(p.layers[1].clip_to, "frame");

console.log("clip-to: ok");
