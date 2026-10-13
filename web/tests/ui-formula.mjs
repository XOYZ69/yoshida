// End-to-end checks for the formula panel: a match in an expression field
// opens the panel from the ⤢ button, a result cell is edited, Apply writes
// the new text into the field, and Escape closes the panel.
//
//   node tests/ui-formula.mjs [http://localhost:4173/]
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
// The ⤢ button sits in the same field box as the editor.
const formulaButton = (label) =>
	field(label)
		.locator(
			'xpath=ancestor::div[contains(concat(" ", normalize-space(@class), " "), " expr ")][1]',
		)
		.locator('button[aria-label="Formula panel"]');
const drawer = p.locator('[role="dialog"][aria-label="Formula panel"]');

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
await row("paper").click();

// A match with two keys, in the fill field.
const fill = field("fill");
await fill.click();
await p.keyboard.press("Control+a");
await p.keyboard.type("match('x', 'a', #ff0000, 'b', #0000ff, #000000)", {
	delay: 5,
});
await p.keyboard.press("Enter");
await rendered();

// Open the panel from the ⤢ button of the field.
await fill.click();
await formulaButton("fill").click();
await drawer.waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
ok("the formula panel opens from ⤢", await drawer.isVisible());
await p.screenshot({ path: `${shots}/formula-open.png` });

// The first result is a cell of the table: change it and press Enter.
const cell = drawer.getByLabel("result 1");
ok(
	"the first result cell shows its text",
	(await cell.inputValue()) === "#ff0000",
	await cell.inputValue(),
);
await cell.fill("#00ff00");
await cell.press("Enter");
await p.waitForTimeout(100);
const text = drawer.locator("textarea");
ok(
	"editing a cell updates the text below",
	(await text.inputValue()).includes("#00ff00"),
	await text.inputValue(),
);

// Apply hands the text to the field.
await drawer.getByRole("button", { name: "Apply" }).click();
await p.waitForTimeout(300);
ok(
	"Apply changes the field text",
	(await fill.innerText()).includes("#00ff00") &&
		!(await fill.innerText()).includes("#ff0000"),
	await fill.innerText(),
);
await rendered();
ok(
	"the design still renders after the edit",
	!(await p.locator(".status").innerText()).match(/error|failed/i),
	await p.locator(".status").innerText(),
);

// Live values for the card on the stage: the default row is the one taken.
await p.waitForTimeout(500);
ok(
	"live values show the value of the taken row",
	(
		await drawer
			.locator("tr.hit")
			.innerText()
			.catch(() => "")
	).includes("default"),
	await drawer
		.locator("tr.hit")
		.innerText()
		.catch(() => "none"),
);

// Quick action: the match becomes a ?: chain and back.
await drawer.getByRole("button", { name: "Convert to ?: chain" }).click();
ok(
	"convert to ?: chain rewrites the text",
	(await text.inputValue()).startsWith("'x' == 'a' ?"),
	await text.inputValue(),
);
// The chain rows read "when … then …": no arrows, and no "–" placeholder for
// a value that is not there.
ok(
	"chain rows have no arrows or dash placeholders",
	!(
		await drawer
			.locator(".chain")
			.innerText()
			.catch(() => "")
	).match(/[→–]/) &&
		(await drawer.getByText("–", { exact: true }).count()) === 0,
	await drawer
		.locator(".chain")
		.innerText()
		.catch(() => "no chain"),
);
await drawer.getByRole("button", { name: "Convert to match" }).click();
ok(
	"convert to match restores it",
	(await text.inputValue()).startsWith("match('x', 'a', #00ff00"),
	await text.inputValue(),
);

// Extract to a constant: the part moves into a new design constant and its
// name takes its place. The name is asked for in the app's text dialog.
const extract = drawer.getByRole("group", { name: "Extract" });
ok(
	"the Extract group offers Constant and Function",
	(await extract
		.getByRole("button", { name: "Constant", exact: true })
		.count()) === 1 &&
		(await extract
			.getByRole("button", { name: "Function", exact: true })
			.count()) === 1,
);
// The dialog is found by its title; it is not inside the panel.
const dialog = (title) => p.getByRole("dialog", { name: title, exact: true });
const dialogConfirm = (title) =>
	dialog(title).getByRole("button", { name: "Extract", exact: true });

// First opening: an invalid name and a taken name keep the dialog open.
await extract.getByRole("button", { name: "Constant", exact: true }).click();
const constDialog = dialog("Extract to constant");
await constDialog.waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
ok(
	"Constant opens the dialog 'Extract to constant'",
	await constDialog.isVisible().catch(() => false),
);
ok(
	"the dialog message says what moves",
	(
		await constDialog
			.locator("p.msg")
			.innerText()
			.catch(() => "")
	).includes("match"),
	await constDialog
		.locator("p.msg")
		.innerText()
		.catch(() => "none"),
);
await constDialog.locator("input").fill("Bad Name");
await dialogConfirm("Extract to constant").click();
await p.waitForTimeout(100);
ok(
	"an invalid name shows a validation error and keeps the dialog open",
	(
		await constDialog
			.locator(".err")
			.innerText()
			.catch(() => "")
	).length > 0 && (await constDialog.isVisible().catch(() => false)),
	await constDialog
		.locator(".err")
		.innerText()
		.catch(() => "no error"),
);
await constDialog.locator("input").fill("tile");
await dialogConfirm("Extract to constant").click();
await p.waitForTimeout(100);
ok(
	"a taken name shows a validation error and keeps the dialog open",
	(
		await constDialog
			.locator(".err")
			.innerText()
			.catch(() => "")
	).length > 0 && (await constDialog.isVisible().catch(() => false)),
	await constDialog
		.locator(".err")
		.innerText()
		.catch(() => "no error"),
);
await constDialog.getByRole("button", { name: "Cancel" }).click();
await p.waitForTimeout(100);

// Second opening: Escape closes only the dialog, the panel stays.
await extract.getByRole("button", { name: "Constant", exact: true }).click();
await constDialog.waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
ok(
	"the dialog opens a second time",
	await constDialog.isVisible().catch(() => false),
);
await p.keyboard.press("Escape");
await p.waitForTimeout(100);
ok("Escape closes the dialog", (await constDialog.count()) === 0);
ok(
	"Escape in the dialog keeps the panel open",
	await drawer.isVisible().catch(() => false),
);

// Third opening: a valid name extracts the match.
await extract.getByRole("button", { name: "Constant", exact: true }).click();
await constDialog.waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
await constDialog.locator("input").fill("paper_fill");
await dialogConfirm("Extract to constant").click();
await p.waitForTimeout(300);
ok("a valid name closes the dialog", (await constDialog.count()) === 0);
ok(
	"extract constant puts the name in the field",
	(await text.inputValue()) === "paper_fill" &&
		(await fill.innerText()).trim() === "paper_fill",
	`${await text.inputValue()} / ${await fill.innerText()}`,
);
await rendered();
ok(
	"the design renders with the new constant",
	!(await p.locator(".status").innerText()).match(/error|failed|fix/i),
	await p.locator(".status").innerText(),
);

// Escape closes the panel.
await p.keyboard.press("Escape");
await p.waitForTimeout(100);
ok("Escape closes the panel", (await drawer.count()) === 0);

// Ctrl+Shift+E from inside the field opens it again.
await fill.click();
await p.keyboard.press("Control+Shift+E");
ok(
	"Ctrl+Shift+E opens the panel from the field",
	await drawer.isVisible().catch(() => false),
);
await p.keyboard.press("Escape");
await p.waitForTimeout(100);

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
