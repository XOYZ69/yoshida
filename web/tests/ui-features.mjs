// End-to-end checks for the format features from the board game report:
// a repeated group with translate, design functions, enum list fields and
// saving only the changed items of a default list, checking every card,
// PDF export, dashed strokes and preset shapes.
//
//   node tests/ui-features.mjs [http://localhost:4173/]
import { mkdir, readFile } from "node:fs/promises";
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

async function fileText(path) {
	await p.click('button[role=tab]:has-text("Advanced")');
	await p.click('aside.files .tabs button:has-text("Files")');
	await p.click(`aside.files li[data-path="${path}"] .row`);
	await p.waitForSelector(".cm-content");
	const t = await p.evaluate(() => {
		const el = document.querySelector(".cm-content");
		const v = el.cmView?.view ?? el.cmTile?.view;
		return v ? v.state.doc.toString() : el.innerText;
	});
	await p.click('button[role=tab]:has-text("Builder")');
	return t;
}
const row = (id) => p.locator(`.tree .row:has(.name:text-is("${id}"))`).first();
const design = "designs/board.design.json";
const cards = "cards/boards.cards.json";

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
ok(
	"board game renders without errors",
	/rendered in/.test(await status()) && !/error/i.test(await status()),
	await status(),
);
await p.screenshot({ path: `${shots}/features-board.png` });

// The repeated tile group: translate and repeat in the inspector.
await row("tile").click();
const translate = await p
	.locator('aside.right .cm-content[aria-label="translate.x"]')
	.first()
	.innerText();
ok("group shows its translate", translate.includes("tile_x(i)"), translate);
ok(
	"group shows its repeat",
	(
		await p.locator('aside.right [aria-label="Repeat mode"]').textContent()
	)?.includes("each"),
);
const boxes = await p.locator(".stage rect.sel").count();
ok("every iteration of the group is outlined", boxes === 40, `${boxes}`);
await p.keyboard.press("Escape");

// Design functions in the design inspector.
const fnHeads = await p
	.locator("aside.right section:has(h3:text-is('Functions')) strong")
	.allTextContents();
ok(
	"functions are listed",
	fnHeads.some((t) => t.startsWith("tile_x(i: number)")),
	fnHeads.join(" | "),
);

// Enum item fields: a dropdown in the card form; one changed tile is saved
// as a change to the default list.
await p.click('.left .tabs button:has-text("Card data")');
const kind12 = p.locator('button[aria-label="kind of row 12"]');
ok("enum item field is a dropdown", (await kind12.count()) === 1);
await kind12.click();
await p
	.locator('[role=listbox] [role=option]:has-text("dare")')
	.first()
	.click();
await settle();
await rendered();
const c = JSON.parse(await fileText(cards));
const tiles = c.cards[0].tiles;
ok(
	"an edited enum item field is saved",
	Array.isArray(tiles)
		? tiles[11]?.kind === "dare"
		: tiles?.["11"]?.kind === "dare",
	JSON.stringify(Array.isArray(tiles) ? tiles[11] : tiles?.["11"]),
);

// Check all cards.
await p.click('.exports button:has-text("Check all")');
await p.waitForFunction(
	() =>
		/Checked \d+ card/.test(
			document.querySelector(".status")?.textContent ?? "",
		),
	null,
	{ timeout: 30000 },
);
ok(
	"check all cards finds no errors",
	/Checked 3 card\(s\): 0 error/.test(await status()),
	await status(),
);

// PDF export.
const [dl] = await Promise.all([
	p.waitForEvent("download", { timeout: 60000 }),
	p.click('.exports button:has-text("PDF")'),
]);
const pdf = await readFile(await dl.path());
ok(
	"PDF export has one page per card",
	pdf.subarray(0, 5).toString() === "%PDF-" &&
		/\/Count 3/.test(pdf.toString("latin1")),
	dl.suggestedFilename(),
);

// A dashed stroke and a preset shape on new layers.
await p.click('.left .tabs button:has-text("Layers")').catch(() => {});
await p.click('button[aria-label="Add a rect layer"]');
await settle();
await p
	.locator(
		'aside.right .field-like:has(.lbl:text-is("stroke")) input[type=checkbox]',
	)
	.check();
await settle();
await p
	.locator('aside.right input[placeholder="solid, or e.g. 12, 6"]')
	.fill("10, 5");
await p.keyboard.press("Enter");
await p.locator('aside.right input[placeholder="solid, or e.g. 12, 6"]').blur();
await settle();
let d = JSON.parse(await fileText(design));
const rect = d.layers.find(
	(l) => l.type === "rect" && Array.isArray(l.stroke?.dash),
);
ok(
	"dash pattern is saved",
	JSON.stringify(rect?.stroke?.dash) === "[10,5]",
	JSON.stringify(rect?.stroke),
);
await rendered();
ok("dashed rect renders", !/error/i.test(await status()), await status());

await p.click('button[aria-label="Add a polygon layer"]');
await settle();
await p.locator('aside.right [aria-label="Polygon drawn from"]').click();
await p.locator('[role=option]:has-text("shape")').click();
await settle();
d = JSON.parse(await fileText(design));
const star = d.layers.find((l) => l.type === "polygon" && l.shape);
ok(
	"polygon becomes a preset shape in a box",
	star?.shape?.type === "star" &&
		typeof star?.box?.w === "number" &&
		!star.points,
	JSON.stringify(star),
);
await rendered();
ok("star renders", !/error/i.test(await status()), await status());
// The star's outline on the canvas comes from its points, not the box.
await settle();
const starPts = await p.evaluate(() =>
	[...document.querySelectorAll(".stage polygon.sel")].map(
		(e) => e.getAttribute("points")?.split(" ").length ?? 0,
	),
);
ok("star outline has 10 points", starPts.includes(10), JSON.stringify(starPts));
await p.screenshot({ path: `${shots}/features-shapes.png` });

ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
