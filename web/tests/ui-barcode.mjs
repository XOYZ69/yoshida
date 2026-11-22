// The designer's barcode support: one Add entry, the format picker with
// previews, the info line from the encoder, fields greyed out for formats
// that ignore them, and the preview rendering the code.
//
//   node tests/ui-barcode.mjs [http://localhost:4173/]
import { mkdir } from "node:fs/promises";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1500, height: 950 } });
await ctx.route("**/api/capabilities", (r) => r.fulfill({ status: 404, body: "" }));
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
const info = () => p.locator("aside.right p.sub[role=status]").first().innerText();

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("forge")').first().click();
await rendered();

// One entry for every kind of code.
const adds = await p.locator('[aria-label="Add layer"] button').allTextContents();
ok("a single Barcode / QR entry in the Add bar", adds.filter((t) => /Barcode/.test(t)).length === 1 && !adds.some((t) => /^\s*QR code/.test(t)), adds.join("|"));
await p.click('button[aria-label="Add a barcode layer"]');
await rendered();
ok("the new layer is a QR code barcode", /QR code/.test(await p.locator("aside.right .picker .current").innerText()));
await p.screenshot({ path: `${shots}/barcode-1-added.png` });

// The picker lists every format with a preview drawn by the encoder.
await p.click("aside.right .picker .current");
await p.waitForSelector("aside.right .picker .tile svg");
await p.waitForFunction(() => document.querySelectorAll("aside.right .picker .tile svg").length >= 12);
const tiles = await p.locator("aside.right .picker .tile").allTextContents();
ok("the picker has 13 formats", tiles.length === 13, tiles.join("|"));
ok("PDF417 can be picked", !(await p.locator('aside.right .picker .tile:has-text("PDF417")').isDisabled()));
await p.screenshot({ path: `${shots}/barcode-2-picker.png` });

// Pick EAN-13 and give it digits: the info line says what was done to them.
await p.locator('aside.right .picker .tile:has-text("EAN-13")').click();
await rendered();
const text = p.locator('aside.right .cm-content[aria-label="text"]').first();
await text.click();
await p.keyboard.press("Control+A");
await p.keyboard.type("400638133393");
await p.keyboard.press("Tab");
await p.waitForFunction(() => /check digit 1 added/.test(document.querySelector("aside.right p.sub[role=status]")?.textContent ?? ""), null, { timeout: 5000 });
ok("the info line shows the added check digit", /EAN-13 · 95 modules wide · check digit 1 added/.test(await info()), await info());
ok("the info line gives a size hint", /Box at least \d+ px wide/.test(await info()), await info());
await rendered();
await p.screenshot({ path: `${shots}/barcode-3-ean.png` });

// A wrong check digit is explained.
await text.click();
await p.keyboard.press("Control+A");
await p.keyboard.type("4006381333932");
await p.keyboard.press("Tab");
await p.waitForFunction(() => /check digit/.test(document.querySelector("aside.right p.sub[role=status]")?.textContent ?? "") && /ends in 2/.test(document.querySelector("aside.right p.sub[role=status]")?.textContent ?? ""), null, { timeout: 5000 });
ok("a wrong check digit is explained", /ends in 2/.test(await info()), await info());

// Fields the format does not read are greyed out and inert.
ok("QR-only fields are not offered for an EAN", (await p.locator('aside.right .label:text-is("level"), aside.right .label:text-is("eye"), aside.right .label:text-is("logo")').count()) === 0);
const ignored = await p.locator("aside.right .ignored[inert]").count();
ok("the module style is greyed out for bars", ignored >= 1, `${ignored}`);

// Back to a QR code: the QR fields return.
await p.click("aside.right .picker .current");
await p.locator('aside.right .picker .tile:has-text("QR code")').click();
await rendered();
ok("QR fields come back for a QR code", (await p.locator('aside.right .label:text-is("eye")').count()) === 1 && (await p.locator('aside.right .label:text-is("level")').count()) === 1);

// A Data Matrix.
await p.click("aside.right .picker .current");
await p.locator('aside.right .picker .tile:has-text("Data Matrix")').click();
await rendered();
await p.waitForFunction(() => /Data Matrix · \d+ × \d+ modules/.test(document.querySelector("aside.right p.sub[role=status]")?.textContent ?? ""), null, { timeout: 5000 });
ok("Data Matrix shows its size", /Data Matrix · 1\d × 1\d modules|Data Matrix · \d+ × \d+ modules/.test(await info()), await info());
await p.screenshot({ path: `${shots}/barcode-4-datamatrix.png` });

if (logs.length) console.log(logs.join("\n"));
ok("no page errors", logs.length === 0);
await b.close();
process.exit(failed ? 1 : 0);
