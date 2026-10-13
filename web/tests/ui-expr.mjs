// End-to-end checks for the expression editor: a syntax error gets a mark,
// the breadcrumb shows the path to the caret in a call argument, a long
// one-line expression does not wrap, the formula button shows for an
// expression and not for a literal, and Shift+Alt+F reformats a long
// expression over several lines.
//
//   node tests/ui-expr.mjs [http://localhost:4173/]
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

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
await row("paper").click();

const fill = field("fill");
await fill.click();
await p.keyboard.press("Control+a");
await p.keyboard.type("max(1, ", { delay: 5 });
await p.waitForTimeout(200);

// An open call is a syntax error: the Zig core marks it.
ok(
	"an unfinished call gets an error mark",
	(await fill.locator(".yx-error").count()) > 0,
);

// The caret is in the second argument of max.
const crumbs = p.locator("aside.right .yx-crumbs");
ok(
	"the breadcrumb shows the path to the caret",
	(await crumbs.count()) === 1 &&
		(await crumbs.innerText()).trim() === "max › arg 2",
	(await crumbs.count()) ? await crumbs.innerText() : "none",
);
await p.screenshot({ path: `${shots}/expr-crumbs.png` });

// A long expression in a one-line field: it scrolls sideways, it does not wrap.
const long =
	"with_alpha(c_paper, min(max(0.25, 0.5), 1) + 0 * (1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16 + 17 + 18 + 19 + 20 + 21 + 22 + 23 + 24 + 25))";
await p.keyboard.press("Control+a");
await p.keyboard.insertText(long);
await p.waitForTimeout(200);
const oneLine = await fill.evaluate((content) => {
	const scroller = content.closest(".cm-scroller");
	return {
		lines: content.querySelectorAll(".cm-line").length,
		content: content.getBoundingClientRect().height,
		line: content.querySelector(".cm-line").getBoundingClientRect().height,
		overflows: scroller.scrollWidth > scroller.clientWidth,
	};
});
ok(
	"a long one-line expression does not wrap",
	oneLine.lines === 1 &&
		oneLine.content <= oneLine.line + 8 &&
		oneLine.overflows,
	JSON.stringify(oneLine),
);

// The formula button (⤢) is for expressions only: not for a literal.
const formulaBtn = (f) =>
	f
		.locator(
			'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " expr ")][1]',
		)
		.locator("button.fe");
await p.keyboard.press("Control+a");
await p.keyboard.insertText("with_alpha(#ff0000, 0.5)");
await p.waitForTimeout(100);
ok(
	"the formula button shows for an expression",
	(await formulaBtn(fill).count()) === 1 &&
		(await formulaBtn(fill).isVisible()),
);
await p.keyboard.press("Control+a");
await p.keyboard.insertText("#ff0000");
await p.waitForTimeout(100);
ok(
	"the formula button is hidden for a literal",
	(await formulaBtn(fill).count()) === 0,
);
await p.keyboard.press("Control+a");
await p.keyboard.insertText(long);
await p.waitForTimeout(200);

// A long expression, then Shift+Alt+F: it is laid out over several lines.
await p.keyboard.press("Shift+Alt+F");
await p.waitForTimeout(300);
const lines = await fill.locator(".cm-line").count();
ok(
	"Shift+Alt+F lays the expression out over several lines",
	lines > 1,
	`${lines} lines`,
);
ok(
	"the formatted expression has no syntax errors",
	(await fill.locator(".yx-error").count()) === 0,
);
await rendered();
ok(
	"the design still renders after reformatting",
	!(await p.locator(".status").innerText()).match(/error|failed/i),
	await p.locator(".status").innerText(),
);
await p.screenshot({ path: `${shots}/expr-reformat.png` });

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
