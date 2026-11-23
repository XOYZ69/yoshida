// Polygon points made by runs: reading the entries and moving the layer.
// Run: node --experimental-strip-types tests/polygon-points.mjs
import assert from 'node:assert/strict';
import { hasPointRun, moveLayer, pointEntries } from '../src/lib/design.ts';

const canvas = { w: 200, h: 100 };

// A run on its own stands for a list of one.
const run = { each: 'pts', item: 'q', x: 'q.px', y: 'q.py' };
assert.deepEqual(pointEntries(run), [run]);
assert.deepEqual(pointEntries([[1, 2], run]), [[1, 2], run]);
assert.deepEqual(pointEntries(undefined), []);
assert.equal(hasPointRun({ points: [[0, 0], [1, 1], [2, 2]] }), false);
assert.equal(hasPointRun({ points: [[0, 0], run] }), true);
assert.equal(hasPointRun({ points: run }), true);

// Moving shifts the fixed points and the x and y of a run, and keeps the order.
const doc = {
	format: 1,
	layers: [
		{
			id: 'p',
			type: 'polygon',
			points: [[10, 10], { count: 3, x: 'i * 20', y: 5 }],
		},
		{ id: 'solo', type: 'polygon', points: { count: 4, x: '10 + i * 5', y: '20' } },
	],
};
moveLayer(doc, 'p', 5, 7, canvas);
assert.deepEqual(doc.layers[0].points, [[15, 17], { count: 3, x: 'i * 20 + 5', y: 12 }]);
moveLayer(doc, 'solo', -10, 0, canvas);
assert.deepEqual(doc.layers[1].points, [{ count: 4, x: '10 + i * 5 - 10', y: '20' }]);

console.log('polygon-points: ok');
