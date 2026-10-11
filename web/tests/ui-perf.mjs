// Proxy renders and export progress, on the board game (4 cards, A3 at
// 300 dpi): the preview renders about as many pixels as the screen shows,
// thumbnails are small, moving a layer does not render on every pointer
// move, and the PDF export counts pages as they are done.
//
//   node tests/ui-perf.mjs [http://localhost:4173/]
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({
	viewport: { width: 1500, height: 950 },
	acceptDownloads: true,
});
// Count render requests sent to the worker.
await ctx.addInitScript(() => {
	window.__renders = [];
	const post = Worker.prototype.postMessage;
	Worker.prototype.postMessage = function (msg, ...rest) {
		if (msg?.op === "render") window.__renders.push(msg.args);
		return post.call(this, msg, ...rest);
	};
});
const p = await ctx.newPage();
const logs = [];
let failed = 0;
p.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const status = () => p.textContent(".status .status-text");
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(
				document.querySelector(".status .status-text")?.textContent ?? "",
			),
		null,
		{ timeout: 60000 },
	);
const renders = () => p.evaluate(() => window.__renders.length);
const canvasWidth = () =>
	p.evaluate(() => document.querySelector(".stage canvas")?.width ?? 0);

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await p.waitForFunction(
	() => /4961 × 3508/.test(document.querySelector(".status")?.textContent ?? ""),
	null,
	{ timeout: 60000 },
);
await rendered();
// The stage reports its zoom, and a sharper or cheaper render follows.
await p.waitForTimeout(1500);
await rendered();
const proxyText = await status();
const proxyW = await canvasWidth();
ok(
	"preview renders fewer pixels than the card",
	/preview at/.test(proxyText) && proxyW > 0 && proxyW < 4961,
	`${proxyText} (canvas ${proxyW})`,
);
ok(
	"the stage keeps the card's size (layout in canvas pixels)",
	await p.evaluate(() => {
		const svg = document.querySelector(".stage svg");
		return svg?.getAttribute("viewBox") === "0 0 4961 3508";
	}),
);

// Full size on request.
await p.click('.status button:has-text("Preview")');
await p.locator('.menu [role=option]:has-text("Full size"), [role=listbox] [role=option]:has-text("Full size")').first().click();
await p.waitForFunction(
	() => document.querySelector(".stage canvas")?.width === 4961,
	null,
	{ timeout: 60000 },
);
ok("full size renders every pixel", (await canvasWidth()) === 4961);
await p.click('.status button:has-text("Preview")');
await p.locator('[role=option]:has-text("Sharp on screen")').first().click();
await p.waitForFunction(
	(w) => (document.querySelector(".stage canvas")?.width ?? 0) < w,
	4961,
	{ timeout: 60000 },
);
ok("back to the screen-sized preview", (await canvasWidth()) < 4961);
await rendered();

// Moving a layer: two renders at the start (the card without it, and it
// alone), none while the pointer moves, one after the release.
await p.locator('.tree .row:has(.name:text-is("panel"))').first().click();
await p.waitForTimeout(300);
const box = await p.locator(".stage svg rect.sel").first().boundingBox();
const before = await renders();
const sx = box.x + box.width / 2;
const sy = box.y + box.height / 2;
// A checksum of the picture on the stage.
const picture = () =>
	p.evaluate(() => {
		const c = document.querySelector(".stage canvas");
		const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
		let h = 0;
		for (let i = 0; i < d.length; i += 7) h = (h * 31 + d[i]) | 0;
		return h;
	});
const under = await picture();
await p.mouse.move(sx, sy);
await p.mouse.down();
for (let i = 1; i <= 12; i++) {
	await p.mouse.move(sx - i * 12, sy + i * 4);
	await p.waitForTimeout(40);
}
// Let the sprite arrive, then keep moving.
await p.waitForTimeout(2500);
for (let i = 13; i <= 30; i++) {
	await p.mouse.move(sx - i * 12, sy + i * 4);
	await p.waitForTimeout(20);
}
await p.waitForTimeout(300);
const during = (await renders()) - before;
const afterMove = await picture();
await p.screenshot({ path: `${shots}/perf-drag.png` });
ok("no render per pointer move (2 for the sprite)", during === 2, `${during} renders`);
ok(
	"the picture follows the drag before the release",
	afterMove !== under,
	`${under} -> ${afterMove}`,
);
await p.mouse.up();
await p.waitForTimeout(500);
await rendered();
ok(
	"one render after the release",
	(await renders()) - before === 3,
	`${(await renders()) - before} renders`,
);
// Undo the move.
await p.keyboard.press("Control+z");
await p.waitForTimeout(500);
await rendered();

// Thumbnails in the card browser are small renders.
const tb = await renders();
await p.click(".picker button.current");
await p.click(".pop .browse");
await p.waitForSelector(".win");
await p.click('.win .btn-group button:has-text("Grid")');
await p.waitForSelector(".win .tile .pic img", { timeout: 60000 });
await p.waitForTimeout(1500);
const thumbs = await p.evaluate(() => window.__renders.slice(-4));
const sizes = await p.$$eval(".tile .pic img", (imgs) =>
	imgs.map((i) => i.naturalWidth),
);
ok(
	"thumbnails render at a small scale",
	thumbs.length > 0 && thumbs.every((a) => a.scale && a.scale <= 0.25) && sizes.every((w) => w > 0 && w < 1300),
	`scales ${thumbs.map((a) => a.scale).join(",")} widths ${sizes.join(",")} (${(await renders()) - tb} renders)`,
);
await p.locator(".win .ghost, .win button[aria-label=Close]").first().click().catch(() => p.keyboard.press("Escape"));
await p.waitForTimeout(300);

// PDF export: the count follows the pages, and the bar moves between them.
const seen = [];
const watch = setInterval(async () => {
	const t = await p
		.locator(".progress .count")
		.innerText()
		.catch(() => "");
	if (t) seen.push(t);
}, 100);
const [dl] = await Promise.all([
	p.waitForEvent("download", { timeout: 180000 }),
	p.click('.exports button:has-text("PDF")'),
]);
clearInterval(watch);
await dl.path();
const pages = [...new Set(seen.map((t) => t.match(/^(\d) of 4 pages/)?.[1]).filter(Boolean))];
const pct = seen
	.map((t) => Number(t.match(/(\d+)%/)?.[1]))
	.filter((v) => !Number.isNaN(v));
ok(
	"PDF progress counts the pages one by one",
	pages.length >= 3,
	`seen ${pages.join(",")} of 4`,
);
ok(
	"PDF progress only goes up",
	pct.length > 3 && pct.every((v, i) => i === 0 || v >= pct[i - 1]),
	pct.join(" "),
);
ok(
	"the bar is near its end before it finishes",
	pct.length > 0 && Math.max(...pct) >= 70,
	`max ${Math.max(...pct)}%`,
);

ok("no page errors", logs.length === 0, logs.join("\n"));
await b.close();
if (failed) {
	console.log(`${failed} check(s) failed`);
	process.exit(1);
}
console.log("all checks passed");
