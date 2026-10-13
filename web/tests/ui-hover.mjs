// End-to-end checks for hover info and go to definition in expression
// fields: hovering a name shows what it is, Ctrl+click (or F12) shows where
// it is defined (param, design function, repeat, layer).
//
//   node tests/ui-hover.mjs [http://localhost:4173/]
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
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
const row = (id) => p.locator(`.tree .row:has(.name:text-is("${id}"))`).first();
const field = (label) =>
	p.locator(`aside.right .cm-content[aria-label="${label}"]`).first();
/** The token `text` in an expression field (a highlighted span). */
const token = (f, text) => f.locator(`span:text-is("${text}")`).first();
const tip = p.locator(".cm-tooltip-hover .yx-hover");

async function hover(f, text) {
	await p.mouse.move(5, 5);
	await tip.waitFor({ state: "detached", timeout: 3000 }).catch(() => {});
	await token(f, text).hover();
	await tip.waitFor({ timeout: 3000 }).catch(() => {});
	return (await tip.count()) ? await tip.innerText() : "";
}
async function ctrlClick(f, text) {
	await token(f, text).click({ modifiers: ["Control"] });
	await p.waitForTimeout(300);
}

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();

// A param: type, card value, Ctrl+click opens it in the Params tab. The
// first board leaves c_paper at its default; the night board sets it.
await p.locator(".toolbar .picker .current").click();
const pickerSearch = p.locator('.pop input[aria-label="Search cards"]');
await pickerSearch.waitFor();
await pickerSearch.fill("night");
await pickerSearch.press("Enter");
await rendered();
await row("paper").click();
const fill = field("fill");
let t = await hover(fill, "c_paper");
ok("hover on a param shows its type", /c_paper: color/.test(t), t);
ok("hover on a param shows the card value", /on this card: #/i.test(t), t);
ok("hover offers Ctrl+click", /Ctrl\+click/.test(t), t);
await p.screenshot({ path: `${shots}/hover-param.png` });

await p.keyboard.down("Control");
await token(fill, "c_paper").hover();
await p.waitForTimeout(150);
ok(
	"holding Ctrl underlines the name",
	(await fill.locator(".yx-link").count()) === 1,
);
await p.keyboard.up("Control");
await p.waitForTimeout(100);
ok(
	"releasing Ctrl removes the underline",
	(await fill.locator(".yx-link").count()) === 0,
);

await ctrlClick(fill, "c_paper");
ok(
	"Ctrl+click on a param opens the Params tab",
	await p
		.locator('.left .tabs button:has-text("Params")')
		.evaluate((e) => e.classList.contains("active")),
);
const param = p.locator('.param[data-param="c_paper"]');
ok(
	"the param is opened and highlighted",
	await param.evaluate(
		(e) => e.classList.contains("open") && e.classList.contains("goto-flash"),
	),
);
ok(
	"the text did not change",
	(await fill.innerText()).trim() === "c_paper",
	await fill.innerText(),
);

// A built-in function: signature and docs; Ctrl+click goes nowhere.
await p.click('.left .tabs button:has-text("Layers")');
await row("panel_shadow").click();
const shadowFill = field("fill");
t = await hover(shadowFill, "with_alpha");
ok("hover on a function shows its signature", /with_alpha\(/.test(t), t);
await ctrlClick(shadowFill, "with_alpha");
ok(
	"Ctrl+click on a built-in keeps the selection",
	(await p.locator(".tree li.selected .name").allTextContents()).join() ===
		"panel_shadow",
);

// Inside a repeated group: the repeat index and the design function.
await row("tile").click();
const tx = field("translate.x");
t = await hover(tx, "tile_x");
ok("hover on a design function shows it", /tile_x\(i: number\)/.test(t), t);
ok("hover on a design function shows its body", /= ox \+ ring_col\(i\)/.test(t), t);
t = await hover(tx, "i");
ok(
	"hover on a repeat name says where it comes from",
	/repeat index/.test(t),
	t,
);
await ctrlClick(tx, "i");
ok(
	"Ctrl+click on a repeat name shows the repeat settings",
	await p
		.locator('aside.right [data-goto="repeat"]')
		.evaluate((e) => e.classList.contains("goto-flash")),
);
await ctrlClick(field("translate.x"), "tile_x");
const fn = p.locator('aside.right [data-goto="function:tile_x"]');
ok(
	"Ctrl+click on a design function shows it in the design settings",
	(await fn.count()) === 1 &&
		(await fn.evaluate((e) => e.classList.contains("goto-flash"))),
);
await p.screenshot({ path: `${shots}/goto-function.png` });

// A function argument, in the function's own body.
const body = fn.locator(".cm-content").first();
t = await hover(body, "i");
ok("hover on a function argument", /argument of tile_x/.test(t), t);

// Item fields of the repeat.
await row("tile_bg").click();
const bg = field("fill");
t = await hover(bg, "kind");
ok(
	"hover on an item field shows its type",
	/t\.kind: enum|t\.kind: text/.test(t),
	t,
);

// A layer reference: hover, F12, Ctrl+click keeps an unsaved edit.
await row("rules_head").click();
const color = field("color");
await color.click();
await p.keyboard.press("Control+a");
await p.keyboard.type("@title.bounds.bottom > 0 ? c_text : nope", { delay: 5 });
await p.keyboard.press("Enter");
await p.waitForTimeout(300);
t = await hover(color, "@title");
ok("hover on a layer reference", /text layer 'title'/.test(t), t);
t = await hover(color, "bottom");
ok("hover on a layer field shows its doc", /bounds\.bottom: number/.test(t), t);
t = await hover(color, "nope");
ok("hover on an unknown name warns", /Unknown name 'nope'/.test(t), t);
ok(
	"unknown names have no native title next to the hover",
	(await color.locator(".yx-unknown[title]").count()) === 0,
);
await color.click();
// Ctrl+Home, not Home: the field wraps, so Home stops at the visual line.
await p.keyboard.press("Control+Home");
await p.keyboard.press("ArrowRight");
await p.keyboard.press("ArrowRight");
await p.keyboard.press("F12");
await p.waitForTimeout(300);
ok(
	"F12 on a layer reference selects the layer",
	(await p.locator(".tree li.selected .name").allTextContents()).join() ===
		"title",
);
await row("rules_head").click();
await field("color").click();
// Ctrl+End, not End: the field wraps, so End stops at the visual line.
await p.keyboard.press("Control+End");
await p.keyboard.type(" ", { delay: 5 });
await p.keyboard.press("Backspace");
await p.keyboard.type("x", { delay: 5 });
await ctrlClick(field("color"), "@title");
ok(
	"Ctrl+click on a layer reference selects the layer",
	(await p.locator(".tree li.selected .name").allTextContents()).join() ===
		"title",
);
await row("rules_head").click();
ok(
	"going to the definition keeps what was typed",
	(await field("color").innerText()).trim().endsWith("nopex"),
	await field("color").innerText(),
);

// Templates: names inside {holes}.
await row("subtitle").click();
const textField = field("text");
t = await hover(textField, "subtitle");
ok("hover works in template holes", /subtitle: text/.test(t), t);

ok("no page errors", logs.length === 0, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
