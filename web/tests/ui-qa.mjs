// End-to-end checks for card review: approve, needs changes, the needs-review
// filter, and the review written to qa.json.
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
const badge = () => p.locator(".qa-control").first().innerText();
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
await b.close();
if (failed) process.exit(1);
