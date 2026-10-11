// End-to-end checks for the UI review round: list enum fields, the item
// field editor, tabs, button groups, splitter lines, the project menu,
// themed tooltips, the export progress window and rendering on the server.
//
//   node tests/ui-review.mjs [http://localhost:4173/]
//
// The server steps use a mocked /api (capabilities, render, progress), so
// they run against `vite preview`. With SERVER_URL set (a yoshida-server
// serving this build, e.g. `yoshida-server --web web/dist`), the real
// server render is checked too.
import { mkdir, readFile } from "node:fs/promises";
import { unzipSync } from "fflate";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const serverUrl = process.env.SERVER_URL ?? "";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({
	viewport: { width: 1500, height: 950 },
	acceptDownloads: true,
});
let p = await ctx.newPage();
const logs = [];
let failed = 0;
const watch = (page) => {
	page.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
	page.on(
		"console",
		(m) =>
			m.type() === "error" &&
			!/api\/capabilities|status of 404|status of 422|status of 502/.test(
				m.text() + m.location().url,
			) &&
			logs.push(`console: ${m.text()}`),
	);
};
watch(p);
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

async function openExample(name) {
	await p.click(".project-btn");
	await p.locator(`.menu [role=menuitem]:has-text("${name}")`).click();
	await rendered();
}

const design = "designs/board.design.json";
const cards = "cards/boards.cards.json";

await p.goto(base);
await rendered();

// ------------------------------------------------------------ top bar and menu

ok(
	"top bar has no export or add buttons",
	(await p
		.locator(
			'header.top > button:has-text("Export"), header.top > button:has-text("Design"), header.top > button:has-text("Upload image"), header.top > button:has-text("Add files")',
		)
		.count()) === 0,
);
const history = p.locator("header .btn-group.history > button");
const hBoxes = await history.evaluateAll((els) =>
	els.map((e) => e.getBoundingClientRect().toJSON()),
);
ok(
	"undo and redo are one joined group",
	hBoxes.length === 2 &&
		Math.abs(hBoxes[0].right - hBoxes[1].left) <= 1.5 &&
		hBoxes[0].height === hBoxes[1].height,
	JSON.stringify(hBoxes.map((r) => [r.left, r.right])),
);
ok(
	"redo has an inner divider",
	(await history
		.nth(1)
		.evaluate((e) => getComputedStyle(e).borderLeftWidth)) === "1px",
);

await p.click(".project-btn");
const menu = await p.locator(".menu").innerText();
ok(
	"project menu has the project actions in sections",
	/START/i.test(menu) &&
		/THIS PROJECT/i.test(menu) &&
		/New design/.test(menu) &&
		/Add files/.test(menu) &&
		/Export project file/.test(menu) &&
		/Rename/.test(menu) &&
		/EXAMPLES/i.test(menu),
);
ok(
	"menu icons are line icons, not emoji",
	(await p.locator(".menu .icon svg").count()) >= 7 &&
		!/[📁🗑⤓⤒]/u.test(menu),
);
await p.keyboard.press("Escape");

// ------------------------------------------------------------ panels and tabs

const leftBorder = await p
	.locator("aside.left")
	.evaluate((e) => getComputedStyle(e).borderRightWidth);
const split = await p.locator(".split-l").boundingBox();
ok(
	"one 1px line between panels (no double border)",
	leftBorder === "0px" && Math.round(split.width) === 1,
	`border=${leftBorder} split=${split.width}`,
);
const tabs = p.locator(".left .tabbar > button");
const tabStyle = await tabs.evaluateAll((els) =>
	els.map((e) => {
		const s = getComputedStyle(e);
		return { br: s.borderRightWidth, bg: s.backgroundColor };
	}),
);
ok(
	"tabs have vertical dividers",
	tabStyle.slice(0, -1).every((t) => t.br === "1px"),
	JSON.stringify(tabStyle.map((t) => t.br)),
);
ok(
	"the selected tab is shaded",
	tabStyle[0].bg !== tabStyle[1].bg,
	`${tabStyle[0].bg} vs ${tabStyle[1].bg}`,
);
ok(
	"tabs say which one is selected",
	(await tabs.first().getAttribute("aria-selected")) === "true",
);

// ------------------------------------------------------------ toolbar

const adds = p.locator('.toolbar [aria-label="Add layer"] > button');
const addBoxes = await adds.evaluateAll((els) =>
	els.map((e) => {
		const r = e.getBoundingClientRect();
		const s = getComputedStyle(e);
		return {
			h: r.height,
			pl: s.paddingLeft,
			icon: e.querySelector("svg")?.getBoundingClientRect().width,
		};
	}),
);
ok(
	"layer buttons share height, padding and icon size",
	addBoxes.length === 5 &&
		addBoxes.every(
			(x) =>
				x.h === addBoxes[0].h && x.pl === addBoxes[0].pl && x.icon === 14,
		),
	JSON.stringify(addBoxes[0]),
);
ok(
	"export buttons are one labelled group",
	(await p.locator('.exports [role=group][aria-label="Export"] > button').count()) ===
		3 && /export/i.test(await p.locator(".exports .group-cap").innerText()),
);
const pickH = await p.evaluate(() =>
	[".pick .select", ".picker", '.toolbar [aria-label="Add layer"]'].map(
		(s) => document.querySelector(s)?.getBoundingClientRect().height,
	),
);
ok(
	"pickers and groups line up",
	pickH.every((h) => h === pickH[0]),
	JSON.stringify(pickH),
);
ok(
	"design picker has a caption inside",
	(await p.locator(".pick .select .cap").innerText()).toLowerCase() ===
		"design",
);
ok(
	"Check all cards sits with the problems",
	(await p.locator('.problems button:has-text("Check all cards")').count()) ===
		1 && (await p.locator('.exports button:has-text("Check")').count()) === 0,
);

// ------------------------------------------------------------ tooltips

const zip = p.locator('.exports button:has-text("ZIP")');
const zipTitle = await zip.getAttribute("title");
await zip.hover();
await p.waitForSelector(".yx-tip", { timeout: 3000 }).catch(() => null);
const tip = p.locator(".yx-tip");
ok(
	"hover shows a themed tooltip",
	(await tip.count()) === 1 && (await tip.innerText()) === zipTitle,
	await tip.innerText().catch(() => "none"),
);
ok(
	"the browser tooltip is suppressed while it shows",
	(await zip.getAttribute("title")) === null,
);
await p.mouse.move(5, 500);
await p.waitForTimeout(100);
ok(
	"tooltip hides and the title comes back",
	(await tip.count()) === 0 && (await zip.getAttribute("title")) === zipTitle,
);
await p.screenshot({ path: `${shots}/review-toolbar.png` });

// ------------------------------------------------------------ list enums (board game)

await openExample("board-game");
await p.click('.left .tabs button:has-text("Card data")');
await settle();
const widths = await p
	.locator(".form .items")
	.first()
	.locator("tbody tr")
	.evaluateAll((rows) =>
		rows.map((r) =>
			Math.round(r.querySelector(".select").getBoundingClientRect().width),
		),
	);
ok(
	"enum dropdowns in a list all have the same width",
	widths.length > 3 && widths.every((w) => w === widths[0]),
	JSON.stringify(widths.slice(0, 6)),
);
await p.screenshot({ path: `${shots}/review-list-enums.png` });

// The item field editor of a list param: enum fields use the options editor.
await p.click('.left .tabs button:has-text("Params")');
await p.click('.param[data-param="tiles"] .head');
await settle();
const kind = p.locator('.param[data-param="tiles"] .item-field[data-field="kind"]');
ok(
	"enum item field shows one row per option",
	(await kind.locator(".opts li input").count()) === 9,
	String(await kind.locator(".opts li input").count()),
);
ok(
	"enum item field default is a dropdown of its options",
	(await kind.locator(".select").count()) >= 2,
);
await kind.locator('.opts input[placeholder^="+ option"]').fill("bonus");
await kind.locator('.opts input[placeholder^="+ option"]').press("Enter");
await settle();
let d = JSON.parse(await fileText(design));
ok(
	"adding an item option saves it",
	d.params.tiles.item.kind.options.includes("bonus") &&
		d.params.tiles.item.kind.default === "plain",
	JSON.stringify(d.params.tiles.item.kind.options),
);
await p.click('.left .tabs button:has-text("Params")');
const openTiles = async () => {
	if (!(await p.locator('.param.open[data-param="tiles"]').count()))
		await p.click('.param[data-param="tiles"] .head');
};
await openTiles();
const opt = p
	.locator('.param[data-param="tiles"] .item-field[data-field="kind"] .opts li input')
	.nth(8);
ok("dare option is listed", (await opt.inputValue()) === "dare");
await opt.fill("truth");
await opt.press("Enter");
await settle();
d = JSON.parse(await fileText(design));
const c = JSON.parse(await fileText(cards));
const kinds = c.cards.flatMap((x) =>
	Array.isArray(x.tiles)
		? x.tiles.map((t) => t.kind)
		: Object.values(x.tiles ?? {}).map((t) => t.kind),
);
ok(
	"renaming an item option renames it in card data",
	d.params.tiles.item.kind.options.includes("truth") &&
		!d.params.tiles.item.kind.options.includes("dare") &&
		kinds.includes("truth") &&
		!kinds.includes("dare"),
	`truth=${kinds.filter((k) => k === "truth").length}`,
);
await p.keyboard.press("Control+z");
await settle();
const back = JSON.parse(await fileText(cards));
ok(
	"one undo puts the option back in the cards",
	back.cards.some((x) =>
		(Array.isArray(x.tiles) ? x.tiles : Object.values(x.tiles ?? {})).some(
			(t) => t.kind === "dare",
		),
	),
);
await p.click('.left .tabs button:has-text("Params")');
await openTiles();
await p.locator('.param[data-param="tiles"]').scrollIntoViewIfNeeded();
await p.screenshot({ path: `${shots}/review-item-fields.png` });

// ------------------------------------------------------------ export progress

const [zipDl] = await Promise.all([
	p.waitForEvent("download", { timeout: 90000 }),
	(async () => {
		await p.click('.exports button:has-text("ZIP")');
		await p.waitForSelector(".progress", { timeout: 3000 });
		await p.waitForTimeout(1200);
		ok(
			"export shows the progress window over a blurred app",
			(await p.locator(".backdrop").evaluate((e) =>
				getComputedStyle(e).backdropFilter,
			)) !== "none" &&
				/of 3 cards/.test(await p.locator(".progress .count").innerText()),
			await p.locator(".progress .count").innerText(),
		);
		ok(
			"progress lists the steps and a Cancel button",
			(await p.locator(".progress .steps li").count()) === 3 &&
				(await p.locator('.progress button:has-text("Cancel")').count()) === 1,
		);
		await p.screenshot({ path: `${shots}/review-progress.png` });
	})(),
]);
const zipped = unzipSync(new Uint8Array(await readFile(await zipDl.path())));
ok(
	"the zip has every card",
	Object.keys(zipped).length === 3,
	Object.keys(zipped).join(", "),
);
await p.waitForSelector(".progress", { state: "detached", timeout: 5000 });
ok("progress window closes when done", (await p.locator(".progress").count()) === 0);

// Cancelling a local export.
await p.click('.exports button:has-text("ZIP")');
await p.waitForSelector('.progress button:has-text("Cancel")');
await p.click('.progress button:has-text("Cancel")');
await p.waitForSelector(".progress", { state: "detached", timeout: 15000 });
await p.waitForFunction(
	() => /cancelled/.test(document.querySelector(".status")?.textContent ?? ""),
	null,
	{ timeout: 15000 },
);
ok("cancel stops the export", /cancelled/.test(await status()), await status());

// ------------------------------------------------------------ server (mocked)

const projectPage = p;
p = await ctx.newPage();
watch(p);
let progressCalls = 0;
let renderBody = null;
let fail = false;
await p.route("**/api/capabilities", (r) =>
	r.fulfill({
		contentType: "application/json",
		body: JSON.stringify({
			version: "0.0.0-test",
			format: 1,
			render: true,
			max_cards: 1000,
			max_body_mb: 200,
		}),
	}),
);
await p.route("**/api/render/progress*", (r) => {
	progressCalls++;
	r.fulfill({
		contentType: "application/json",
		body: JSON.stringify({
			found: true,
			stage: "rendering",
			done: Math.min(2, progressCalls),
			total: 2,
		}),
	});
});
await p.route("**/api/render", async (r) => {
	renderBody = JSON.parse(r.request().postData() ?? "{}");
	renderBody.job = r.request().headers()["x-yoshida-job"];
	await new Promise((res) => setTimeout(res, 1500));
	if (fail)
		return r.fulfill({
			status: 422,
			contentType: "application/json",
			body: JSON.stringify({
				error: "the project has errors",
				diagnostics: [
					{
						severity: "error",
						code: 3001,
						file: "designs/tour.design.json",
						path: "/layers/0",
						line: 1,
						col: 1,
						span: [0, 0],
						message: "mocked server error",
						hint: null,
						card: null,
					},
				],
			}),
		});
	r.fulfill({
		contentType: "application/zip",
		body: Buffer.from("PK\u0005\u0006".padEnd(22, "\u0000"), "latin1"),
	});
});
await p.goto(base);
await rendered();
const sw = p.locator('.exports label.switch input[role="switch"]');
ok(
	"render on server is a labelled switch",
	(await sw.count()) === 1 &&
		/Render on server/.test(await p.locator(".exports label.switch").innerText()),
);
await sw.check();
const [srvDl] = await Promise.all([
	p.waitForEvent("download", { timeout: 30000 }),
	(async () => {
		await p.click('.exports button:has-text("ZIP")');
		await p.waitForSelector(".progress");
		await p.waitForTimeout(1000);
		const steps = await p.locator(".progress .steps li").allInnerTexts();
		ok(
			"server export shows its steps",
			steps.length === 5 &&
				/Upload/.test(steps[1]) &&
				/Render on the server/.test(steps[2]),
			JSON.stringify(steps),
		);
		ok(
			"server progress counts the cards",
			/of 2 cards/.test(await p.locator(".progress .count").innerText()),
			await p.locator(".progress .count").innerText(),
		);
		await p.screenshot({ path: `${shots}/review-server-progress.png` });
	})(),
]);
ok("server export downloads the zip", /\.zip$/.test(srvDl.suggestedFilename()));
ok(
	"the upload carries the job id and the files",
	/^[0-9a-f]{16}$/.test(renderBody?.job ?? "") &&
		Object.keys(renderBody?.files ?? {}).length > 3,
	renderBody?.job,
);
const log = await p.evaluate(() => document.querySelector(".status")?.textContent);
ok("status says it rendered on the server", /on the server/.test(log), log);

// A server error keeps the window open with the reason and the activity log.
fail = true;
await p.waitForSelector(".progress", { state: "detached", timeout: 5000 });
await p.click('.exports button:has-text("PDF")');
await p.waitForSelector(".progress .err", { timeout: 15000 });
ok(
	"a server error stays visible",
	/mocked|project has errors/.test(await p.locator(".progress .err").innerText()) &&
		(await p.locator(".progress .log li").count()) >= 3,
	await p.locator(".progress .err").innerText(),
);
ok(
	"its problems reach the problems panel",
	/mocked server error/.test(await p.locator(".problems").innerText()),
);
await p.screenshot({ path: `${shots}/review-server-error.png` });
await p.click('.progress button:has-text("Close")');
ok("Close dismisses the error", (await p.locator(".progress").count()) === 0);
await p.close();
p = projectPage;

// ------------------------------------------------------------ real server

if (serverUrl) {
	const sp = await ctx.newPage();
	watch(sp);
	await sp.goto(serverUrl);
	await sp.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
	await sp.check('.exports label.switch input[role="switch"]');
	const [dl] = await Promise.all([
		sp.waitForEvent("download", { timeout: 60000 }),
		sp.click('.exports button:has-text("ZIP")'),
	]);
	const files = unzipSync(new Uint8Array(await readFile(await dl.path())));
	ok(
		"real server renders the zip",
		Object.keys(files).length >= 1 &&
			Object.keys(files).every((f) => f.endsWith(".png")),
		Object.keys(files).join(", "),
	);
	await sp.close();
}

if (logs.length) console.log(logs.join("\n"));
ok("no page errors", logs.length === 0);
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exit(failed ? 1 : 0);
