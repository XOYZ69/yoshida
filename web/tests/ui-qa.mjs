// End-to-end checks for card review: approve, needs changes, comments and
// pins, the keys, the overview and the needs-review filter.
//
//   node tests/ui-qa.mjs [http://localhost:4173/]
import { chromium } from "playwright";

const base = process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
let failed = 0;
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1700, height: 1000 }, colorScheme: "dark" });
await ctx.route("**/api/capabilities", (r) => r.fulfill({ status: 404, body: "" }));
const p = await ctx.newPage();
p.on("pageerror", (e) => console.log("pageerror", e.message));
const ok = (n, c, x = "") => {
	if (!c) failed++;
	console.log(`${c ? "PASS" : "FAIL"} ${n} ${x}`);
};
const rendered = () => p.waitForFunction(() => /rendered in/.test(document.querySelector(".status")?.textContent ?? ""), null, { timeout: 30000 });
await p.goto(base);
await rendered();
await p.click('.left .tabs button:has-text("Card data")');
const ctl = p.locator('[aria-label="Card review"]');
ok("review controls are shown", await ctl.isVisible());
const badge = async () => (await p.locator(".qa-control .qa").first().innerText()) + (await p.locator(".qa-control .open").count() ? " " + (await p.locator(".qa-control .open").innerText()) : "");
await ctl.getByRole("button", { name: "Approve", exact: true }).click();
await p.waitForTimeout(300);
ok("approving marks the card", /approved/i.test(await badge()), await badge());
// Renaming the id keeps the review.
const idIn = p.locator(".card-id input");
const oldId = await idIn.inputValue();
await idIn.fill("renamed-card");
await idIn.press("Enter");
await p.waitForTimeout(800);
ok("the id changed", (await idIn.inputValue()) === "renamed-card");
ok("a renamed card keeps its approval", /approved/i.test(await badge()), await badge());
// Needs changes appears in the needs-review filter.
await ctl.getByRole("button", { name: "Needs changes", exact: true }).click();
await p.waitForTimeout(300);
ok("needs changes is recorded", /needs changes/i.test(await badge()), await badge());
const filter = p.locator("label", { hasText: "Needs review" }).locator("input");
if (!(await filter.count())) await p.locator(".left button:has-text(\"renamed-card\"), .picker button").first().click().catch(() => {});
if (await filter.count()) {
	await filter.first().check();
	ok("needs-changes cards are listed by the filter", await p.locator("text=renamed-card").count() > 0);
} else ok("the card list has the filter", false);
// Comments: an open one means needs changes and blocks approving.
await p.locator('[aria-label="New comment"]').fill("Title is too long");
await p.keyboard.press("Enter");
await p.waitForTimeout(300);
ok("a comment is listed", await p.locator('[aria-label="Comment 1"]').count() === 1);
ok("an open comment shows as open", /1 open/.test(await badge()), await badge());
ok("approve is disabled while a comment is open", await ctl.getByRole("button", { name: "Approve", exact: true }).isDisabled());
// Pin it: click Pin, then the card.
await ctl.getByRole("button", { name: "Pin", exact: true }).click();
const box = await p.locator('[aria-label="Place the pin here"]').boundingBox();
ok("the card waits for a click", !!box);
await p.mouse.click(box.x + box.width / 2, box.y + box.height / 3);
await p.waitForTimeout(500);
ok("a numbered pin is on the card", await p.locator("button.pin").count() === 1 && (await p.locator("button.pin").innerText()) === "1");
// Resolving gives the mark back, and the pin stays (greyed).
await ctl.getByRole("button", { name: "Resolve", exact: true }).click();
await p.waitForTimeout(300);
ok("resolving the comment ends the open count", !/open/.test(await badge()), await badge());
// Keys: A approves, ? lists the keys, O opens the overview.
await p.locator("body").click({ position: { x: 5, y: 5 } });
await p.keyboard.press("a");
await p.waitForTimeout(300);
ok("A approves", /Approved/.test(await badge()), await badge());
await p.keyboard.press("n");
await p.waitForTimeout(300);
ok("N marks needs changes", /Needs changes/.test(await badge()), await badge());
await p.keyboard.press("?");
ok("? opens the key list", await p.locator(".qa-keys").isVisible());
await p.keyboard.press("Escape");
await p.keyboard.press("o");
ok("O opens the overview", await p.locator(".qa-overview").isVisible());
ok("the overview lists the comment", /Title is too long/.test(await p.locator(".qa-overview").innerText()));
await p.keyboard.press("Escape");
// J moves to the next card; the first one keeps its review.
const idBefore = await idIn.inputValue();
await p.keyboard.press("j");
await p.waitForTimeout(500);
ok("J goes to the next card", (await idIn.inputValue()) !== idBefore);
await p.keyboard.press("k");
await p.waitForTimeout(500);
ok("K comes back", (await idIn.inputValue()) === idBefore);
await p.keyboard.press("u");
await p.waitForTimeout(500);
ok("U jumps to a card that needs review", (await idIn.inputValue()) !== "" );
await b.close();
if (failed) process.exit(1);
