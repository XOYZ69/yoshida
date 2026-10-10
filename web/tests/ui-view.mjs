// End-to-end checks for moving around the canvas: Ctrl+wheel zooms toward
// the pointer, the zoom buttons zoom around the middle, the wheel pans, the
// middle mouse button drags the view (also over layers) without touching
// the selection, and the card stays in view when the window shrinks.
//
//   node tests/ui-view.mjs [http://localhost:4173/]
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

await p.goto(base);
await p.waitForFunction(
	() =>
		/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
	null,
	{ timeout: 30000 },
);

const card = () => p.locator(".stage svg").boundingBox();
const view = () => p.locator(".stage-wrap").boundingBox();
const near = (a, b2, tol = 1.5) => Math.abs(a - b2) <= tol;
const fmt = (n) => n.toFixed(1);
const selected = () => p.locator(".tree li.selected .name").allTextContents();
const fitOn = () => p.locator(".zoom button.on:text-is('Fit')").count();

ok("starts fitted", (await fitOn()) === 1);

// Ctrl+wheel keeps the card point under the pointer in place.
async function wheelZoomKeepsPoint(name, fx, fy, deltaY) {
	const r = await card();
	const mx = r.x + r.width * fx;
	const my = r.y + r.height * fy;
	await p.mouse.move(mx, my);
	await p.keyboard.down("Control");
	await p.mouse.wheel(0, deltaY);
	await p.keyboard.up("Control");
	await p.waitForTimeout(150);
	const r2 = await card();
	const x2 = r2.x + r2.width * fx;
	const y2 = r2.y + r2.height * fy;
	ok(
		name,
		r2.width !== r.width && near(x2, mx) && near(y2, my),
		`width ${fmt(r.width)} -> ${fmt(r2.width)}, point ${fmt(mx)},${fmt(my)} -> ${fmt(x2)},${fmt(y2)}`,
	);
}
await wheelZoomKeepsPoint(
	"ctrl+wheel zooms in at the pointer",
	0.2,
	0.25,
	-100,
);
ok("zooming leaves fit", (await fitOn()) === 0);
await wheelZoomKeepsPoint("ctrl+wheel zooms in again", 0.8, 0.7, -100);
await wheelZoomKeepsPoint(
	"ctrl+wheel zooms out at the pointer",
	0.35,
	0.6,
	100,
);
// A pinch sends small ctrl+wheel deltas: a small, smooth step.
{
	const r = await card();
	await p.mouse.move(r.x + r.width * 0.5, r.y + r.height * 0.5);
	await p.keyboard.down("Control");
	await p.mouse.wheel(0, -10);
	await p.keyboard.up("Control");
	await p.waitForTimeout(150);
	const r2 = await card();
	const f = r2.width / r.width;
	ok("small deltas zoom a little", f > 1 && f < 1.02, `factor ${f.toFixed(4)}`);
}

// The buttons zoom around the middle of the stage.
{
	const v = await view();
	const r = await card();
	const cx = v.x + v.width / 2;
	const cy = v.y + v.height / 2;
	const fx = (cx - r.x) / r.width;
	const fy = (cy - r.y) / r.height;
	await p.click(".zoom button[aria-label='Zoom in']");
	await p.waitForTimeout(150);
	const r2 = await card();
	ok(
		"zoom button keeps the middle in place",
		r2.width > r.width &&
			near(r2.x + r2.width * fx, cx) &&
			near(r2.y + r2.height * fy, cy),
		`${fmt(r2.x + r2.width * fx)},${fmt(r2.y + r2.height * fy)} vs ${fmt(cx)},${fmt(cy)}`,
	);
}

// The wheel pans the view when it is not fitted.
{
	const r = await card();
	const v = await view();
	await p.mouse.move(v.x + v.width / 2, v.y + v.height / 2);
	await p.mouse.wheel(0, 60);
	await p.waitForTimeout(150);
	const r2 = await card();
	ok(
		"wheel pans the view",
		near(r2.y, r.y - 60) && near(r2.x, r.x) && near(r2.width, r.width),
		`${fmt(r.y)} -> ${fmt(r2.y)}`,
	);
}

// Middle-button drag over a layer pans and leaves the selection alone.
await p.click('.tree .row:has(.name:text-is("art"))');
const before = await selected();
const art = await p.locator(".stage rect.sel").first().boundingBox();
{
	const r = await card();
	const sx = art.x + art.width / 2;
	const sy = art.y + art.height / 2;
	await p.mouse.move(sx, sy);
	await p.mouse.down({ button: "middle" });
	await p.mouse.move(sx + 60, sy + 40, { steps: 4 });
	const during = await p.evaluate(
		([x, y]) => ({
			panning: document
				.querySelector(".stage-wrap")
				.classList.contains("panning"),
			cursor: getComputedStyle(document.elementFromPoint(x, y)).cursor,
		}),
		[sx + 60, sy + 40],
	);
	ok(
		"middle drag shows the grabbing cursor",
		during.panning && during.cursor === "grabbing",
		JSON.stringify(during),
	);
	await p.mouse.move(sx + 120, sy + 80, { steps: 4 });
	await p.mouse.up({ button: "middle" });
	await p.waitForTimeout(150);
	const r2 = await card();
	ok(
		"middle drag pans the view",
		near(r2.x, r.x + 120) && near(r2.y, r.y + 80) && near(r2.width, r.width),
		`${fmt(r.x)},${fmt(r.y)} -> ${fmt(r2.x)},${fmt(r2.y)}`,
	);
	ok(
		"cursor is back after the drag",
		!(await p
			.locator(".stage-wrap")
			.evaluate((el) => el.classList.contains("panning"))),
	);
}
const afterPan = await selected();
ok(
	"middle drag keeps the selection",
	JSON.stringify(afterPan) === JSON.stringify(before),
	JSON.stringify(afterPan),
);
ok(
	"middle drag does not edit",
	!(await p.locator(".status").textContent()).includes("error"),
	await p.locator(".status").textContent(),
);

// Selection and the marquee still work after panning.
await p.keyboard.press("Escape");
{
	const a = await p.locator(".stage svg").boundingBox();
	await p.mouse.click(a.x + 3, a.y + 3);
	await p.keyboard.press("Escape");
	const sel = await p.locator(".tree li.selected").count();
	ok("escape still clears", sel === 0, `selected=${sel}`);
}
await p.click('.tree .row:has(.name:text-is("art"))');
const artNow = await p.locator(".stage rect.sel").first().boundingBox();
await p.keyboard.press("Escape");
await p.mouse.click(artNow.x + artNow.width / 2, artNow.y + artNow.height / 2);
const clicked = await selected();
ok(
	"click still selects after a pan",
	clicked.length === 1,
	JSON.stringify(clicked),
);
await p.keyboard.press("Escape");

// Fit centres the card again.
await p.click(".zoom button:text-is('Fit')");
await p.waitForTimeout(150);
{
	const v = await view();
	const r = await card();
	ok(
		"fit centres the card",
		(await fitOn()) === 1 &&
			near(r.x + r.width / 2, v.x + v.width / 2) &&
			near(r.y + r.height / 2, v.y + v.height / 2),
		`${fmt(r.x + r.width / 2)},${fmt(r.y + r.height / 2)} vs ${fmt(v.x + v.width / 2)},${fmt(v.y + v.height / 2)}`,
	);
	// Middle drag from the fitted view starts at the same place.
	await p.mouse.move(v.x + 20, v.y + 20);
	await p.mouse.down({ button: "middle" });
	await p.mouse.move(v.x + 50, v.y + 20, { steps: 3 });
	await p.mouse.up({ button: "middle" });
	await p.waitForTimeout(150);
	const r2 = await card();
	ok(
		"middle drag from fit has no jump",
		near(r2.x, r.x + 30) && near(r2.y, r.y) && near(r2.width, r.width),
		`${fmt(r.x)} -> ${fmt(r2.x)}`,
	);
}

// The card stays reachable when the window gets smaller.
{
	const v = await view();
	const r = await card();
	await p.mouse.move(v.x + 10, v.y + 10);
	await p.mouse.down({ button: "middle" });
	await p.mouse.move(v.x + v.width + 400, v.y + 10, { steps: 6 });
	await p.mouse.up({ button: "middle" });
	await p.setViewportSize({ width: 900, height: 700 });
	await p.waitForTimeout(400);
	const v2 = await view();
	const r2 = await card();
	ok(
		"card stays in view after a shrink",
		r2.x < v2.x + v2.width - 20 && r2.x + r2.width > v2.x + 20 && r.width > 0,
		`card x ${fmt(r2.x)}..${fmt(r2.x + r2.width)}, view ${fmt(v2.x)}..${fmt(v2.x + v2.width)}`,
	);
	await p.screenshot({ path: `${shots}/view-small.png` });
}

ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
