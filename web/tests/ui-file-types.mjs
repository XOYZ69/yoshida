// End-to-end checks for the Files tab: the icon of each file kind, image
// thumbnails, the details of the selected file (pixel size, font name,
// card count), the upload target line and its reset button, the marked
// target folder, and the size column lining up at every depth. Uses the
// poker example and the fixture project in tests/fixtures/editor-test.
//
//   node tests/ui-file-types.mjs [http://localhost:4173/]
import { mkdir, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { zipSync } from "fflate";
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
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
const row = (file) => p.locator(`.ftree li[data-path="${file}"]`);
const details = () => p.textContent(".file-info .file-details");
const target = async () =>
	((await p.textContent(".browser .target")) ?? "").replace(/\s+/g, " ").trim();

// Packs the fixture folder into a .yoshida file (a zip with one top folder).
async function packFixture(name) {
	const root = path.join(import.meta.dirname, "fixtures", name);
	const files = {};
	const walk = async (dir, rel) => {
		for (const e of await readdir(dir, { withFileTypes: true })) {
			const r = `${rel}/${e.name}`;
			if (e.isDirectory()) await walk(path.join(dir, e.name), r);
			else files[r] = new Uint8Array(await readFile(path.join(dir, e.name)));
		}
	};
	await walk(root, name);
	return Buffer.from(zipSync(files));
}

await p.goto(base);
await rendered();
await p.click('.left .tabs button:has-text("Files")');

// Icons per file kind (poker)
const kinds = {
	"designs/number.design.json": "design",
	"cards/numbers.cards.json": "cards",
	"yoshida.json": "json",
	"assets/fonts/CinzelDecorative-Bold.ttf": "font",
	"assets/fonts/CinzelDecorative-Bold-license.txt": "text",
	"README.md": "markdown",
	assets: "folder",
};
const seen = {};
for (const file of Object.keys(kinds))
	seen[file] = await row(file)
		.locator(".row > .icon")
		.getAttribute("data-type");
const wrong = Object.entries(kinds).filter(([file, k]) => seen[file] !== k);
ok(
	"icon type per file kind",
	!wrong.length,
	wrong.map(([file]) => `${file}: ${seen[file]}`).join(", "),
);
ok(
	"icons are drawn, not text badges",
	(await p.locator(".ftree .row > .icon svg").count()) ===
		(await p.locator(".ftree .row > .icon").count()),
);
const colors = await p.$$eval(".ftree .row > .icon", (els) => [
	...new Set(els.map((e) => getComputedStyle(e).color)),
]);
ok(
	"file kinds have their own colours",
	colors.length >= 6,
	String(colors.length),
);

// The uses count only shows when something uses the file
ok(
	"uses count on a used file",
	/^3/.test(
		(await row("assets/fonts/CinzelDecorative-Bold.ttf")
			.locator(".uses")
			.textContent()) ?? "",
	),
);
ok(
	"no uses count when nothing uses the file",
	(await row("README.md").locator(".uses").count()) === 0,
);

// Upload target line
ok(
	"target line names the project root",
	(await target()) === "Uploads go to the project root",
	await target(),
);
ok(
	"no reset button at the root",
	(await p.locator(".browser .target button").count()) === 0,
);
await row("assets/fonts").locator(".row").click();
ok(
	"target line names the clicked folder",
	(await target()) === "Uploads go to assets/fonts/",
	await target(),
);
ok(
	"the target folder is marked in the tree",
	(await p.locator(".ftree li.upload-dir").getAttribute("data-path")) ===
		"assets/fonts",
);
await row("assets/fonts").locator(".row").click(); // unfold it again
await row("assets/fonts/CinzelDecorative-Bold.ttf").locator(".row").click();
ok(
	"clicking a file keeps the target",
	(await target()) === "Uploads go to assets/fonts/" &&
		(await p.locator(".ftree li.upload-dir").count()) === 1,
	await target(),
);
ok(
	"font details",
	/^Font: Cinzel Decorative Bold · 61 KB · used by 3 files$/.test(
		((await details()) ?? "").replace(/\s+/g, " ").trim(),
	),
	await details(),
);
ok(
	"used by lists the files in a tooltip",
	((await p.getAttribute(".file-info .used-by", "title")) ?? "").includes(
		"designs/",
	),
);
await p.click('.browser .target button[aria-label="Use the project root"]');
ok(
	"reset goes back to the project root",
	(await target()) === "Uploads go to the project root" &&
		(await p.locator(".ftree li.upload-dir").count()) === 0,
	await target(),
);
await row("cards/numbers.cards.json").locator(".row").click();
ok(
	"card data details",
	/^Card data, 40 cards · 2 KB · used by 1 file$/.test(
		((await details()) ?? "").replace(/\s+/g, " ").trim(),
	),
	await details(),
);
await row("README.md").locator(".row").click();
ok(
	"no wording about references when nothing uses the file",
	!/referred|used by/.test((await details()) ?? ""),
	await details(),
);

// Fixture: images and nested folders
await p.click(".project-btn");
const chooser = p.waitForEvent("filechooser");
await p.locator('.menu [role=menuitem]:has-text("Open project file")').click();
await (await chooser).setFiles({
	name: "editor-test.yoshida",
	mimeType: "application/zip",
	buffer: await packFixture("editor-test"),
});
await rendered();
await p.click('.left .tabs button:has-text("Files")');
ok(
	"images show a thumbnail",
	(await row("assets/images/cards/spell.png")
		.locator("img.thumb[data-type=image]")
		.count()) === 1,
);
await row("assets/images/cards/spell.png").locator(".row").click();
await p.waitForFunction(() =>
	/px/.test(document.querySelector(".file-details")?.textContent ?? ""),
);
ok(
	"image details show the pixel size",
	/^300 × 420 px · 1 KB$/.test(
		((await details()) ?? "").replace(/\s+/g, " ").trim(),
	),
	await details(),
);

// An image the browser cannot draw falls back to the image icon
const upload = p.waitForEvent("filechooser");
await p.click('.browser .bar button[aria-label="Upload files"]');
await (await upload).setFiles({
	name: "broken.png",
	mimeType: "image/png",
	buffer: Buffer.from("not an image"),
});
await p.waitForSelector('.ftree li[data-path="broken.png"]');
await p
	.waitForSelector('.ftree li[data-path="broken.png"] .icon[data-type=image]', {
		timeout: 5000,
	})
	.catch(() => null);
ok(
	"a broken image shows the image icon",
	(await row("broken.png").locator(".icon[data-type=image] svg").count()) ===
		1 && (await row("broken.png").locator("img").count()) === 0,
);

// Sizes line up at every depth, folders included
const sizeEdges = async () =>
	p.$$eval(".ftree .row .size", (els) => [
		...new Set(els.map((e) => Math.round(e.getBoundingClientRect().right))),
	]);
const depths = await p.$$eval(".ftree li", (els) => [
	...new Set(els.map((e) => e.style.getPropertyValue("--depth"))),
]);
let edges = await sizeEdges();
ok(
	"size column lines up",
	depths.length >= 4 && edges.length === 1,
	`depths ${depths} edges ${edges}`,
);
const nameW = await row("assets/images/lvl/level-star-blue.png")
	.locator(".name")
	.evaluate((e) => e.getBoundingClientRect().width);

// Narrowest left panel
const sp = await p.locator(".split-l .split").boundingBox();
await p.mouse.move(sp.x + sp.width / 2, sp.y + sp.height / 2);
await p.mouse.down();
await p.mouse.move(0, sp.y + sp.height / 2, { steps: 4 });
await p.mouse.up();
edges = await sizeEdges();
ok("size column lines up at 200px", edges.length === 1, `${edges}`);
const narrowW = await row("assets/images/lvl/level-star-blue.png")
	.locator(".name")
	.evaluate((e) => e.getBoundingClientRect().width);
ok(
	"deep names keep room at 200px",
	narrowW >= 70 && narrowW < nameW,
	`${narrowW} of ${nameW}`,
);
await row("assets/images/lvl/level-star-blue.png").locator(".row").hover();
ok(
	"a cut-off name shows its path as a tooltip",
	(await row("assets/images/lvl/level-star-blue.png")
		.locator(".name")
		.getAttribute("title")) === "assets/images/lvl/level-star-blue.png",
);
await row("cards").locator(".row").hover();
ok(
	"a name that fits has no tooltip",
	!(await row("cards").locator(".name").getAttribute("title")),
);
await p.screenshot({ path: `${shots}/files-narrow.png` });
await p.dblclick(".split-l .split");

ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
