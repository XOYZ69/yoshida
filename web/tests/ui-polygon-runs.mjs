// A polygon whose points include a run: the inspector shows it, the canvas
// draws every point it makes and offers no vertex handles for them.
//
//   npm run build && npx vite preview --port 4173 &
//   node tests/ui-polygon-runs.mjs [http://localhost:4173/]
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1500, height: 950 } });
const p = await ctx.newPage();
const logs = [];
let failed = 0;
p.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
p.on(
	"console",
	(m) =>
		m.type() === "error" &&
		!/api\/capabilities|status of 404|status of 502/.test(
			m.text() + m.location().url,
		) &&
		logs.push(`console: ${m.text()}`),
);
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const settle = () => p.waitForTimeout(900);
const status = () => p.textContent(".status");
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
const outline = () =>
	p.evaluate(() =>
		[...document.querySelectorAll(".stage polygon.sel")].map(
			(e) => e.getAttribute("points")?.split(" ").length ?? 0,
		),
	);
const vertices = () => p.locator(".stage circle[data-vertex]").count();

await p.goto(base);
await rendered();

await p.click('button[aria-label="Add a polygon layer"]');
await settle();
ok("a new polygon has 3 outline points", (await outline()).includes(3), JSON.stringify(await outline()));
ok("a new polygon has vertex handles", (await vertices()) === 3, String(await vertices()));

await p.locator('aside.right button:has-text("+ run")').click();
await rendered();
await settle();
ok("the run shows in the inspector", (await p.locator("aside.right .run").count()) === 1);
ok("the run adds 3 points to the outline", (await outline()).includes(6), JSON.stringify(await outline()));
ok("a polygon with a run has no vertex handles", (await vertices()) === 0, String(await vertices()));
ok("no error after adding the run", !/error/i.test(await status()), await status());

const count = p.locator('aside.right .run-head input[title="Number of points"]');
await count.fill("5");
await count.press("Tab");
await rendered();
await settle();
ok("the count changes the points", (await outline()).includes(8), JSON.stringify(await outline()));

await p.locator('aside.right .run-head button[title="Remove run"]').click();
await rendered();
await settle();
ok("removing the run restores the outline", (await outline()).includes(3), JSON.stringify(await outline()));
ok("and the vertex handles", (await vertices()) === 3, String(await vertices()));
await p.screenshot({ path: `${shots}/polygon-runs.png` });

ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
