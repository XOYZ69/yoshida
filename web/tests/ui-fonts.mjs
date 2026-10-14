// End-to-end checks for the Fonts window: it opens from the Aa button of a
// text layer, the font dropdown and the project menu; Google Fonts asks for
// consent first; a Google family is imported and used (one undo step); a
// WOFF2 upload is refused and a TTF upload is added and used; Escape closes
// the window. No network: the Google hosts are answered by page.route.
//
//   node tests/ui-fonts.mjs [http://localhost:4173/]
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const fontsDir = new URL("../../examples/poker/assets/fonts/", import.meta.url);
const dmSerifTtf = await readFile(
	new URL("DMSerifDisplay-Regular.ttf", fontsDir),
);
const cinzelTtf = await readFile(
	new URL("CinzelDecorative-Bold.ttf", fontsDir),
);
const woff2 = Buffer.concat([Buffer.from("wOF2"), Buffer.alloc(64)]);

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

// Google hosts: every request is answered here, and recorded.
const googleHosts = [];
const cors = { "access-control-allow-origin": "*" };
await p.route(
	(url) =>
		/^(fonts\.googleapis\.com|fonts\.gstatic\.com|raw\.githubusercontent\.com)$/.test(
			url.hostname,
		),
	async (route) => {
		const u = new URL(route.request().url());
		googleHosts.push(`${u.hostname}${u.pathname}`);
		if (u.hostname === "fonts.googleapis.com") {
			const family = (u.searchParams.get("family") ?? "").split(":")[0];
			const css = `/* ${family} */\n@font-face { font-family: '${family}'; font-style: normal; font-weight: 400; src: url(https://fonts.gstatic.com/fake.woff2) format('woff2'); }\n`;
			return route.fulfill({
				status: 200,
				headers: { ...cors, "content-type": "text/css" },
				body: css,
			});
		}
		if (u.hostname === "fonts.gstatic.com") {
			// The woff2 preview and the .ttf downloads both get TTF bytes.
			return route.fulfill({
				status: 200,
				headers: { ...cors, "content-type": "font/ttf" },
				body: dmSerifTtf,
			});
		}
		return route.fulfill({
			status: 200,
			headers: { ...cors, "content-type": "text/plain" },
			body: "SIL Open Font License, Version 1.1 (fake text for the test)\n",
		});
	},
);

const row = (id) => p.locator(`.tree .row:has(.name:text-is("${id}"))`).first();
const win = () => p.locator('[role="dialog"][aria-label^="Fonts"]');
const tab = (name) => win().getByRole("tab", { name, exact: true });
const fontField = () =>
	p.locator('aside.right button[aria-label="font"]').first();
const aaButton = () =>
	p.locator('aside.right button[aria-label="Browse fonts"]').first();
const flat = (ls) =>
	ls.flatMap((l) => [l, ...(l.layers ? flat(l.layers) : [])]);

// Going to the Advanced view and back clears the layer selection.
async function selectTitle() {
	await row("title").click();
	await p.waitForTimeout(150);
}

// The design JSON, read the way ui-features.mjs reads a file.
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
	await selectTitle();
	return t;
}
const design = async () =>
	JSON.parse(await fileText("designs/board.design.json"));
// Whether a project file is listed in the Files tab.
async function inFiles(path) {
	await p.click('button[role=tab]:has-text("Advanced")');
	await p.click('aside.files .tabs button:has-text("Files")');
	const n = await p.locator(`aside.files li[data-path="${path}"]`).count();
	await p.click('button[role=tab]:has-text("Builder")');
	await selectTitle();
	return n === 1;
}

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();

// ---------------------------------------------------------------- 1. In project

await row("panel").click();
if (!(await row("title").count())) {
	await p
		.locator('.tree .row:has(.name:text-is("panel")) button')
		.first()
		.click()
		.catch(() => {});
}
await row("title").click();
await p.waitForTimeout(200);
ok(
	"the title layer's font field shows bebas",
	(await fontField().innerText()).includes("bebas"),
	await fontField()
		.innerText()
		.catch(() => "no font field"),
);

await aaButton().click();
await win()
	.waitFor({ state: "visible", timeout: 5000 })
	.catch(() => {});
ok(
	"the Aa button opens the Fonts window",
	await win()
		.isVisible()
		.catch(() => false),
	(await win()
		.getAttribute("aria-label")
		.catch(() => "")) ?? "",
);
ok(
	"the window is titled Fonts and opens on In project",
	(
		(await win()
			.getAttribute("aria-label")
			.catch(() => "")) ?? ""
	).startsWith("Fonts") &&
		(await tab("In project").getAttribute("aria-selected")) === "true",
);
ok(
	"In project lists BebasNeue-Regular",
	(await win()
		.locator('[role="option"][title="assets/fonts/BebasNeue-Regular.ttf"]')
		.count()) === 1,
);
ok(
	"BebasNeue-Regular shows its OFL license file and no warning",
	(await win()
		.locator(".detail .tag")
		.first()
		.innerText()
		.catch(() => "")) === "OFL" &&
		(await win().locator(".warn-line").count()) === 0,
	await win()
		.locator(".warn-line")
		.innerText()
		.catch(() => "no warning"),
);
await p.screenshot({ path: `${shots}/ui-fonts-project.png` });

// ---------------------------------------------------------------- 2. Google consent

await tab("Google Fonts").click();
await win()
	.getByRole("region", { name: "Google Fonts" })
	.waitFor({ timeout: 5000 })
	.catch(() => {});
ok(
	"Google Fonts shows the consent card",
	(await win().getByRole("region", { name: "Google Fonts" }).count()) === 1 &&
		(await win().locator("h3", { hasText: "Use Google Fonts?" }).count()) === 1,
);
ok(
	"no request to a Google host before consent",
	googleHosts.length === 0,
	googleHosts.join(", "),
);
await win().getByRole("button", { name: "Not now" }).click();
await p.waitForTimeout(100);
ok(
	"Not now goes back to In project",
	(await tab("In project").getAttribute("aria-selected")) === "true",
);

await tab("Google Fonts").click();
await win().getByRole("button", { name: "Allow Google Fonts" }).click();
await p
	.waitForFunction(
		() =>
			/of 1,935/.test(
				document
					.querySelector('[role="dialog"][aria-label^="Fonts"]')
					?.getAttribute("aria-label") ?? "",
			),
		null,
		{ timeout: 15000 },
	)
	.catch(() => {});
const winTitle =
	(await win()
		.getAttribute("aria-label")
		.catch(() => "")) ?? "";
ok("the Google list loads with its count", /of 1,935/.test(winTitle), winTitle);

await win().getByRole("searchbox", { name: "Search fonts" }).fill("dm serif");
await p.waitForTimeout(200);
const googleList = win().locator(
	'[role="listbox"][aria-label="Google Fonts families"]',
);
const firstRow = googleList.locator('[role="option"]').first();
ok(
	"searching dm serif puts DM Serif Display first",
	(await firstRow.innerText().catch(() => "")).includes("DM Serif Display"),
	await firstRow.innerText().catch(() => "no rows"),
);
await firstRow.click();
await p.screenshot({ path: `${shots}/ui-fonts-google.png` });

// ---------------------------------------------------------------- 3. Import and use

ok(
	"Regular is checked by default",
	await win().locator('input[type="checkbox"]').first().isChecked(),
);
const nameInput = win().locator(
	'input[aria-label="Font name for Regular 400"]',
);
ok(
	"the name is prefilled dm_serif_display",
	(await nameInput.inputValue()) === "dm_serif_display",
	await nameInput.inputValue().catch(() => "no name field"),
);
await win()
	.getByRole("button", { name: "Import and use", exact: true })
	.click();
await p
	.waitForFunction(
		() =>
			/Imported/.test(
				document.querySelector(
					'[role="dialog"][aria-label^="Fonts"] [role="status"]',
				)?.textContent ?? "",
			),
		null,
		{ timeout: 15000 },
	)
	.catch(() => {});
ok(
	"the status says Imported",
	/Imported/.test(
		await win()
			.locator('[role="status"]')
			.innerText()
			.catch(() => ""),
	),
	await win()
		.locator('[role="status"]')
		.innerText()
		.catch(() => "no status"),
);
await p.waitForTimeout(300);
ok(
	"the title layer's font field shows dm_serif_display",
	(await fontField().innerText()).includes("dm_serif_display"),
	await fontField()
		.innerText()
		.catch(() => "no font field"),
);

await p.keyboard.press("Escape");
await win()
	.waitFor({ state: "detached", timeout: 3000 })
	.catch(() => {});
ok("Escape closes the window after the import", (await win().count()) === 0);
// Continue with the window's close button when Escape did not close it.
if (await win().count())
	await win().locator('button[aria-label="Close"]').click();
await win()
	.waitFor({ state: "detached", timeout: 3000 })
	.catch(() => {});

const after = await design();
const title = flat(after.layers ?? []).find((l) => l.id === "title");
ok(
	"the design declares dm_serif_display",
	after.fonts?.dm_serif_display === "assets/fonts/DMSerifDisplay-Regular.ttf",
	JSON.stringify(after.fonts),
);
ok(
	"the design's title layer uses dm_serif_display",
	title?.font === "dm_serif_display",
	title?.font,
);
ok(
	"the project has the TTF and its license file",
	(await inFiles("assets/fonts/DMSerifDisplay-Regular.ttf")) &&
		(await inFiles("assets/fonts/DMSerifDisplay-Regular-license.txt")),
);
await rendered();
ok(
	"the design renders after the import",
	!(await p.locator(".status").innerText()).match(/error|failed/i),
	await p.locator(".status").innerText(),
);

// One Ctrl+Z undoes the declaration, the layer's font and both files.
await p.keyboard.press("Control+z");
await p.waitForTimeout(500);
const undone = await design();
const titleUndone = flat(undone.layers ?? []).find((l) => l.id === "title");
ok(
	"Ctrl+Z puts the title font back to bebas",
	titleUndone?.font === "bebas" &&
		(await fontField().innerText()).includes("bebas"),
	titleUndone?.font,
);
ok(
	"Ctrl+Z removes the declared name",
	undone.fonts?.dm_serif_display === undefined &&
		undone.fonts?.bebas !== undefined,
	JSON.stringify(undone.fonts),
);
ok(
	"Ctrl+Z removes the imported files",
	!(await inFiles("assets/fonts/DMSerifDisplay-Regular.ttf")) &&
		!(await inFiles("assets/fonts/DMSerifDisplay-Regular-license.txt")),
);

// ---------------------------------------------------------------- 4. Upload

await aaButton().click();
await win()
	.waitFor({ state: "visible", timeout: 5000 })
	.catch(() => {});
const titleBefore = (await win().getAttribute("aria-label")) ?? "";
const [woffChooser] = await Promise.all([
	p.waitForEvent("filechooser"),
	win()
		.getByRole("button", { name: /Upload font file/ })
		.click(),
]);
await woffChooser.setFiles({
	name: "web.woff2",
	mimeType: "font/woff2",
	buffer: woff2,
});
await p.waitForTimeout(400);
ok(
	"a WOFF2 upload is refused with a WOFF message",
	/WOFF/.test(
		await win()
			.locator('[role="status"]')
			.innerText()
			.catch(() => ""),
	),
	await win()
		.locator('[role="status"]')
		.innerText()
		.catch(() => "no status"),
);
ok(
	"the refused WOFF2 adds nothing to the project",
	((await win().getAttribute("aria-label")) ?? "") === titleBefore &&
		(await win().locator('[role="option"][title$="web.woff2"]').count()) === 0,
	(await win().getAttribute("aria-label")) ?? "",
);

const [ttfChooser] = await Promise.all([
	p.waitForEvent("filechooser"),
	win()
		.getByRole("button", { name: /Upload font file/ })
		.click(),
]);
await ttfChooser.setFiles({
	name: "CinzelDecorative-Bold.ttf",
	mimeType: "font/ttf",
	buffer: cinzelTtf,
});
await p.waitForTimeout(500);
const cinzelRow = win().locator(
	'[role="option"][title="assets/fonts/CinzelDecorative-Bold.ttf"]',
);
ok(
	"the uploaded TTF appears in the In project list",
	(await cinzelRow.count()) === 1,
);
ok(
	"the uploaded TTF is selected",
	(await cinzelRow.getAttribute("aria-selected")) === "true",
);
const suggested = await win().locator("input.mono").first().inputValue();
ok("the name field suggests a name", suggested.length > 0, suggested);
await win().getByRole("button", { name: "Add and use", exact: true }).click();
await p.waitForTimeout(400);
ok(
	"Add and use sets the title layer to the new name",
	(await fontField().innerText()).includes(suggested),
	`${suggested} / ${await fontField()
		.innerText()
		.catch(() => "")}`,
);
await p.keyboard.press("Escape");
await win()
	.waitFor({ state: "detached", timeout: 3000 })
	.catch(() => {});
const withCinzel = await design();
ok(
	"the design declares the uploaded font under that name",
	withCinzel.fonts?.[suggested] === "assets/fonts/CinzelDecorative-Bold.ttf" &&
		flat(withCinzel.layers ?? []).find((l) => l.id === "title")?.font ===
			suggested,
	JSON.stringify(withCinzel.fonts),
);

// ---------------------------------------------------------------- 5. Inspector dropdown

await fontField().click();
const browse = p
	.locator('[role="listbox"] [role="option"]:has-text("Browse fonts")')
	.first();
await browse.waitFor({ state: "visible", timeout: 3000 }).catch(() => {});
ok("the font dropdown has a Browse fonts row", (await browse.count()) === 1);
ok(
	"the font dropdown has an Upload font file row",
	(await p
		.locator('[role="listbox"] [role="option"]:has-text("Upload font file")')
		.count()) >= 1,
);
await browse.click();
await win()
	.waitFor({ state: "visible", timeout: 5000 })
	.catch(() => {});
ok(
	"Browse fonts from the dropdown opens the window",
	await win()
		.isVisible()
		.catch(() => false),
);
await p.keyboard.press("Escape");
await win()
	.waitFor({ state: "detached", timeout: 3000 })
	.catch(() => {});
ok(
	"Escape closes the window opened from the dropdown",
	(await win().count()) === 0,
);

// ---------------------------------------------------------------- 6. Dark theme

await p.emulateMedia({ colorScheme: "dark" });
await aaButton().click();
await win()
	.waitFor({ state: "visible", timeout: 5000 })
	.catch(() => {});
await p.waitForTimeout(300);
await p.screenshot({ path: `${shots}/ui-fonts-dark.png` });
await p.keyboard.press("Escape");
await win()
	.waitFor({ state: "detached", timeout: 3000 })
	.catch(() => {});

// ---------------------------------------------------------------- 7. Errors

ok("no page errors or console errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
