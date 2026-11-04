// End-to-end checks for the Files panel layout on a short window: only the
// tree scrolls, the search bar stays at the top and the footer (file total,
// selected file) stays below the tree without covering rows. Builder and
// Advanced (JSON) mode.
//
//   node tests/ui-files.mjs [http://localhost:4173/]
import { readFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
let failed = 0;
const b = await chromium.launch();
const p = await (
	await b.newContext({ viewport: { width: 1440, height: 560 } })
).newPage();
p.on("pageerror", (e) => console.log("pageerror", e.message));
const ok = (n, c, x = "") => {
	if (!c) failed++;
	console.log(`${c ? "PASS" : "FAIL"} ${n} ${x}`);
};
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);

await p.goto(base);
await rendered();
await p.click('.left .tabs button:has-text("Files")');

// Enough files to overflow the tree. The first one added sorts last, so
// showing it after the upload means scrolling the tree to the end.
const png = await readFile(
	path.join(
		import.meta.dirname,
		"fixtures/editor-test/assets/images/cards/spell.png",
	),
);
const names = Array.from(
	{ length: 20 },
	(_, i) => `zz-extra-${String(19 - i).padStart(2, "0")}.png`,
);
const chooser = p.waitForEvent("filechooser");
await p.click('.left .bar button[aria-label="Upload files"]');
await (await chooser).setFiles(
	names.map((name) => ({ name, mimeType: "image/png", buffer: png })),
);
await p.waitForSelector('.left li[data-path="zz-extra-19.png"]');
await p.waitForTimeout(500);

// Geometry of the panel in `aside`, and whether the given row is the
// topmost element at its centre (not covered by the footer).
const layout = (aside, row) =>
	p.evaluate(
		([aside, row]) => {
			const a = document.querySelector(aside);
			const tree = a.querySelector(".ftree");
			const t = tree.getBoundingClientRect();
			const box = a.getBoundingClientRect();
			// What the panel shows of the tree.
			const top = Math.max(t.top, box.top);
			const bottom = Math.min(t.bottom, box.bottom);
			const foot = [a.querySelector(".total"), a.querySelector(".file-info")]
				.filter(Boolean)
				.map((e) => e.getBoundingClientRect());
			const footTop = Math.min(...foot.map((r) => r.top));
			// The shown part of each row that shows at all.
			const rows = [...tree.querySelectorAll("li[data-path]")]
				.map((li) => li.getBoundingClientRect())
				.map((r) => [Math.max(r.top, top), Math.min(r.bottom, bottom)])
				.filter(([t0, b0]) => b0 - t0 > 0.5);
			const covered = rows.filter(([t0, b0]) =>
				foot.some((f) => t0 < f.bottom - 0.5 && b0 > f.top + 0.5),
			).length;
			const li = tree.querySelector(`li[data-path="${row}"]`);
			const r = li.getBoundingClientRect();
			const hit = document.elementFromPoint(r.left + 40, (r.top + r.bottom) / 2);
			const search = a.querySelector(".bar input").getBoundingClientRect();
			const s = document.elementFromPoint(
				search.left + 10,
				(search.top + search.bottom) / 2,
			);
			return {
				scrolls: tree.scrollHeight > tree.clientHeight,
				asideScrolls: a.scrollHeight > a.clientHeight,
				treeBottom: t.bottom,
				footTop,
				visibleRows: rows.length,
				covered,
				rowInside: r.top >= t.top - 0.5 && r.bottom <= t.bottom + 0.5,
				rowOnTop: li.contains(hit),
				searchOnTop: s?.matches(".bar input") ?? false,
				searchTop: search.top,
				asideTop: a.getBoundingClientRect().top,
			};
		},
		[aside, row],
	);

const last = "zz-extra-19.png";
let g = await layout("aside.left", last);
ok(
	"builder: a new file is scrolled into view in the tree",
	g.rowInside && g.rowOnTop,
	JSON.stringify(g),
);

async function check(label, aside) {
	await p.click(`${aside} li[data-path="zz-extra-05.png"] .row`);
	await p.waitForTimeout(300);
	await p.evaluate((a) => {
		document.querySelector(`${a} .ftree`).scrollTop = 0;
	}, aside);
	g = await layout(aside, last);
	ok(`${label}: only the tree scrolls`, g.scrolls && !g.asideScrolls, JSON.stringify(g));
	ok(
		`${label}: the footer sits below the tree`,
		g.footTop >= g.treeBottom - 0.5 && g.covered === 0 && g.visibleRows > 3,
		JSON.stringify(g),
	);
	await p.evaluate((a) => {
		const t = document.querySelector(`${a} .ftree`);
		t.scrollTop = t.scrollHeight;
	}, aside);
	await p.waitForTimeout(200);
	g = await layout(aside, last);
	ok(
		`${label}: the last file shows above the footer`,
		g.rowInside && g.rowOnTop && g.covered === 0,
		JSON.stringify(g),
	);
	ok(
		`${label}: the search field stays visible`,
		g.searchOnTop && g.searchTop > g.asideTop,
		JSON.stringify(g),
	);
}

await check("builder", "aside.left");
ok(
	"builder: the selected file shows its preview",
	await p.locator("aside.left .file-info .file-preview").isVisible(),
);
await p.click('button[role=tab]:has-text("Advanced")');
await p.click('aside.files .tabs button:has-text("Files")');
await p.waitForSelector("aside.files .ftree");
await check("advanced", "aside.files");

await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
