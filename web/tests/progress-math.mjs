// Unit checks for the export progress bar and time left (no browser).
// Run: node --experimental-strip-types tests/progress-math.mjs
import { overall, stepFraction, timeLeft } from "../src/lib/ui/progressMath.ts";

let failed = 0;
function ok(name, cond, extra = "") {
	console.log(`${cond ? "ok  " : "FAIL"} ${name}${cond ? "" : ` ${extra}`}`);
	if (!cond) failed++;
}
const near = (a, b) => Math.abs(a - b) < 1e-9;

// Browser ZIP of 4 cards: render 94, pack 4, save 2.
const zip = (state, done, extra = {}) => ({
	steps: [
		{ weight: 94, state: state[0] },
		{ weight: 4, state: state[1] },
		{ weight: 2, state: state[2] },
	],
	done,
	total: 4,
	fraction: null,
	unitStarted: null,
	perUnitMs: null,
	...extra,
});

ok("nothing done is 0, not a guess", overall(zip(["active", "todo", "todo"], 0), 0) === 0);
ok(
	"three of four cards is 70.5 %",
	near(overall(zip(["active", "todo", "todo"], 3), 0), (94 * 0.75) / 100),
);
ok(
	"all cards rendered is 94 %, not done",
	near(overall(zip(["active", "todo", "todo"], 4), 0), 0.94),
);
ok(
	"packing step without a count keeps the rendered share",
	near(
		overall({ ...zip(["done", "active", "todo"], 0), total: 0 }, 0),
		0.94,
	),
);
// The card in flight creeps, but never past 90 % of itself.
const flight = zip(["active", "todo", "todo"], 1, {
	unitStarted: 1000,
	perUnitMs: 2000,
});
ok("card in flight halfway", near(stepFraction(flight, 2000), 0.25 + 0.5 / 4));
ok("card in flight is capped", near(stepFraction(flight, 99999), 0.25 + 0.9 / 4));
ok(
	"never past the next card boundary",
	overall(flight, 99999) < (94 * 0.5) / 100,
);

// One call with no progress: indeterminate.
ok(
	"no steps and nothing measured is indeterminate",
	overall({ steps: [], done: 0, total: 0, fraction: null, unitStarted: null, perUnitMs: null }, 0) === null,
);
// Upload by bytes on a server export: pack 3 done, upload 10 at 60 %.
const server = {
	steps: [3, 10, 77, 8, 2].map((weight, i) => ({
		weight,
		state: i === 0 ? "done" : i === 1 ? "active" : "todo",
	})),
	done: 0,
	total: 0,
	fraction: 0.6,
	unitStarted: null,
	perUnitMs: null,
};
ok("60 % of the upload is 9 % overall", near(overall(server, 0), 0.09));

ok("no time left before there is a pace", timeLeft(0.01, 0, 5000) === null);
ok("time left from the pace", near(timeLeft(0.25, 0, 10000), 30000));
ok("no time left when finished", timeLeft(1, 0, 10000) === null);

if (failed) {
	console.log(`${failed} check(s) failed`);
	process.exit(1);
}
console.log("all progress checks passed");
