// End-to-end checks for renaming fonts and design functions from the
// inspector (pencil, confirm/cancel, "update uses" or "rename only") and
// for the optional font notes.
//
//   node tests/ui-rename.mjs [http://localhost:4173/]
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
let failed = 0;
const b = await chromium.launch();
const p = await (await b.newContext({ viewport: { width: 1700, height: 1000 }, colorScheme: "dark", deviceScaleFactor: 1.5 })).newPage();
p.on("pageerror", (e) => console.log("pageerror", e.message));
const ok = (n, c, x = "") => {
	if (!c) failed++;
	console.log(`${c ? "PASS" : "FAIL"} ${n} ${x}`);
};
const rendered = () => p.waitForFunction(() => /rendered in/.test(document.querySelector(".status")?.textContent ?? ""), null, { timeout: 30000 });
await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("poker")').click();
await rendered();
await p.keyboard.press("Escape");
await p.waitForTimeout(400);
const fonts = p.locator('section:has(h3:text-is("Fonts"))');
ok("notes hidden by default", (await fonts.locator('input[aria-label^="Note for"]').count()) === 0);
await fonts.locator('label.toggle input').check();
const noteIn = fonts.locator('input[aria-label="Note for serif"]');
await noteIn.fill("Titles and court names");
await noteIn.press("Tab");
await p.waitForTimeout(500);
// font rename
await fonts.locator('button[aria-label="Rename serif"]').click();
const ri = fonts.locator('input[aria-label="New name for serif"]');
await ri.fill("2bad");
await ri.press("Enter");
ok("invalid name shows error", (await fonts.locator(".rename-err").count()) === 1);
await ri.fill("title_serif");
await fonts.locator('button[aria-label="Confirm rename"]').click();
await p.waitForSelector('.dialog');
const msg = await p.locator('.dialog').innerText();
ok("font dialog names the layer", msg.includes("layer index_rank"), msg);
await p.locator('.dialog button:has-text("Update and rename")').click();
await p.waitForTimeout(800);
ok("font renamed", (await fonts.locator('strong:text-is("title_serif")').count()) === 1);
ok("note kept", (await fonts.locator('input[aria-label="Note for title_serif"]').inputValue()) === "Titles and court names");
// function rename, cancel via Esc first
const fsec = p.locator('section:has(> h3:text-is("Functions"))');
await fsec.locator('button[aria-label="Rename side_n"]').click();
await fsec.locator('input[aria-label="New name for side_n"]').press("Escape");
ok("esc cancels", (await fsec.locator('input[aria-label="New name for side_n"]').count()) === 0);
await fsec.locator('button[aria-label="Rename side_n"]').click();
await fsec.locator('input[aria-label="New name for side_n"]').fill("side_count");
await fsec.locator('button[aria-label="Confirm rename"]').click();
await p.waitForSelector('.dialog');
const fmsg = await p.locator(".dialog").innerText();
ok("function dialog lists the uses", fmsg.includes("function side_t") && fmsg.includes("layer pips_side"), fmsg);
await p.locator('.dialog button:has-text("Update and rename")').click();
await p.waitForTimeout(1200);
const body = await p.locator('[data-goto="function:side_t"] .cm-content').innerText();
ok("call updated in side_t", body.includes("side_count("), body);
await rendered();
ok("still renders after the rename", true);
// rename only for function: layers break
await fsec.locator('button[aria-label="Rename mid_n"]').click();
await fsec.locator('input[aria-label="New name for mid_n"]').fill("mid_count");
await fsec.locator('input[aria-label="New name for mid_n"]').press("Enter");
await p.waitForSelector('.dialog');
await p.locator('.dialog button:has-text("Rename only")').click();
await p.waitForTimeout(1500);
const probs = await p.locator("text=unknown function").count();
ok("rename only leaves the old call as an error", probs > 0);
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
