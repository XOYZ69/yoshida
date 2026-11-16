// End-to-end checks for sets in the editor: a new project starts with a
// manifest that lists its set, the project menu's "Add set…" adds a card
// file and a manifest entry, and the Design picker shows the sets.
//
//   node tests/ui-sets.mjs [http://localhost:4173/]
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

await p.goto(base);
await rendered();

// New project: a manifest that lists the set.
await p.click(".project-btn");
await p.click('[role=menuitem]:has-text("New project")');
await p.locator(".dialog input").fill("Fresh Cards");
await p.keyboard.press("Enter");
await rendered();
ok("new project opens", (await p.textContent(".pname")) === "fresh-cards");
const manifest = JSON.parse(await fileText("yoshida.json"));
ok(
	"the new project has a manifest with its set",
	manifest.name === "Fresh Cards" &&
		manifest.sets?.length === 1 &&
		manifest.sets[0].design === "designs/fresh-cards.design.json",
	JSON.stringify(manifest),
);

// Add set: a card file for the design, listed in the manifest.
await p.click(".project-btn");
await p.click('[role=menuitem]:has-text("Add set")');
// With one design the menu offers it; pick it.
const item = p.locator('.menu [role=menuitem]').first();
if (await item.count()) await item.click();
await p.locator(".dialog input").fill("Second set");
await p.keyboard.press("Enter");
await rendered();
const after = JSON.parse(await fileText("yoshida.json"));
ok(
	"Add set lists the new set in the manifest",
	after.sets?.length === 2 && after.sets[1].name === "second-set",
	JSON.stringify(after.sets),
);
const cardsFile = await fileText("cards/second-set.cards.json");
ok("Add set creates the card file", cardsFile.includes('"cards"'));

// Both sets are in the Design picker.
await p.click('.toolbar button[aria-label="Design file"]');
const rows = await p.locator("[role=option]:not(.action)").count();
await p.keyboard.press("Escape");
ok("the Design picker lists both sets", rows === 2, String(rows));
await p.screenshot({ path: `${shots}/sets.png` });

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
process.exit(failed ? 1 : 0);
