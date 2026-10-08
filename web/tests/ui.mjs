// End-to-end check of the editor in a real browser (Chromium via Playwright).
//
//   npm run build && npx vite preview --port 4173 &
//   node tests/ui.mjs [http://localhost:4173/]
//
// Prints PASS/FAIL per check and exits with 1 when any check fails.
// Screenshots go to test-results/.
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";
import { unzipSync } from "fflate";

const base =
  process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({
  viewport: { width: 1500, height: 950 },
  permissions: ["clipboard-read", "clipboard-write"],
  acceptDownloads: true,
});
const p = await ctx.newPage();
const logs = [];
let failed = 0;
p.on("pageerror", (e) => logs.push("pageerror: " + e.message));
p.on(
  "console",
  (m) =>
    m.type() === "error" &&
    !/api\/capabilities|status of 404|status of 502/.test(
      m.text() + m.location().url,
    ) &&
    logs.push("console: " + m.text()),
);
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

await p.goto(base);
await rendered();
ok("loads feature-tour", true, await status());

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
const design = "designs/tour.design.json";
const cards = "cards/tour.cards.json";

// Multi-select from the layer list
const row = (id) => p.locator(`.tree .row:has(.name:text-is("${id}"))`).first();
await row("badge").click();
await row("art").click({ modifiers: ["Control"] });
const n = await p.locator(".tree li.selected").count();
ok("ctrl+click selects two layers", n === 2, `selected=${n}`);
ok(
  "inspector shows multi section",
  (await p.locator("text=2 layers selected").count()) === 1,
);

// Align left
let before = JSON.parse(await fileText(design));
await row("badge").click();
await row("art").click({ modifiers: ["Control"] });
await p.click('button[title^="Align left"]');
await settle();
let after = JSON.parse(await fileText(design));
const flat = (ls) =>
  ls.flatMap((l) => [l, ...(l.type === "group" ? flat(l.layers) : [])]);
const L = (d, id) => flat(d.layers).find((l) => l.id === id);
const newGroups = (d) =>
  d.layers.filter((l) => l.type === "group" && l.id !== "level_badge");
ok(
  "align left changes positions",
  JSON.stringify(L(before, "badge")) !== JSON.stringify(L(after, "badge")) ||
    JSON.stringify(L(before, "art")) !== JSON.stringify(L(after, "art")),
  JSON.stringify([
    L(after, "badge").box ?? L(after, "badge").at,
    L(after, "art").box,
  ]),
);
ok("align keeps 0 errors", !/error/i.test(await status()), await status());
await p.keyboard.press("Control+z");
await settle();

// Copy and paste
await row("badge").click();
await p
  .locator(".stage-wrap")
  .click({ position: { x: 5, y: 5 } })
  .catch(() => {});
await row("badge").click();
await p.locator("body").focus?.();
await p.keyboard.press("Control+c");
await p.keyboard.press("Control+v");
await settle();
ok(
  "paste adds badge_copy",
  (await row("badge_copy").count()) === 1,
  await status(),
);

// Select all, then Escape
await p.keyboard.press("Escape");
await p.keyboard.press("Control+a");
const all = await p.locator(".tree li.selected").count();
ok("ctrl+a selects all", all > 5, `selected=${all}`);
await p.keyboard.press("Escape");
ok("escape clears", (await p.locator(".tree li.selected").count()) === 0);

// Rotate with the handle
await row("art").click();
const rot = p.locator('[data-handle="rot"]');
const rb = await rot.boundingBox();
await p.mouse.move(rb.x + rb.width / 2, rb.y + rb.height / 2);
await p.mouse.down();
await p.mouse.move(rb.x + 150, rb.y + 120, { steps: 8 });
await p.mouse.up();
await settle();
after = JSON.parse(await fileText(design));
ok(
  "rotate handle writes rotate",
  typeof L(after, "art").rotate === "number",
  String(L(after, "art").rotate),
);
await p.screenshot({ path: `${shots}/v02-rotate.png` });
await p.keyboard.press("Control+z");
await settle();

// Groups: Ctrl+G, canvas pick, context menu, ungroup
await row("title").click();
await row("art").click({ modifiers: ["Control"] });
await p.keyboard.press("Control+g");
await settle();
after = JSON.parse(await fileText(design));
const grp = newGroups(after)[0];
ok(
  "ctrl+g makes a group",
  !!grp &&
    grp.layers
      .map((l) => l.id)
      .sort()
      .join() === "art,title",
  JSON.stringify(grp?.layers.map((l) => l.id)),
);
ok(
  "group renders without errors",
  /rendered in/.test(await status()),
  await status(),
);
ok("tree shows group rows", (await p.locator(".tree .icon.grp").count()) === 2);
await p.keyboard.press("Escape");
// Click on the art layer on the canvas: picks the group
await row("art").click();
const ab = await p.locator(".stage rect.sel").first().boundingBox();
await p.keyboard.press("Escape");
const at = { x: ab.x + ab.width / 2, y: ab.y + ab.height / 2 };
await p.mouse.click(at.x, at.y);
const picked = await p.locator(".tree li.selected .name").allTextContents();
ok(
  "canvas click picks the group",
  picked.length === 1 && picked[0] === grp.id,
  JSON.stringify(picked),
);
await p.mouse.dblclick(at.x, at.y);
const deep = await p.locator(".tree li.selected .name").allTextContents();
ok(
  "double click picks inside",
  deep.length === 1 && deep[0] !== grp.id,
  JSON.stringify(deep),
);
await row(grp.id).click({ button: "right" });
await p.waitForSelector(".menu");
const items = await p.locator(".menu [role=menuitem] .label").allTextContents();
ok(
  "context menu has group items",
  items.includes("Ungroup") &&
    items.includes("Rename…") &&
    items.includes("Delete"),
  items.join(" | "),
);
await p.screenshot({ path: `${shots}/v03-menu.png` });
await p.locator('.menu [role=menuitem]:has-text("Rename…")').click();
await p.locator(".dialog input").fill("hero");
await p.keyboard.press("Enter");
await settle();
ok("rename via menu", (await row("hero").count()) === 1);
await p.keyboard.press("Control+Shift+g");
await settle();
after = JSON.parse(await fileText(design));
ok(
  "ctrl+shift+g ungroups",
  !newGroups(after).length && after.layers.some((l) => l.id === "art"),
);
await p.keyboard.press("Control+z");
await p.keyboard.press("Control+z");
await p.keyboard.press("Control+z");
await settle();
after = JSON.parse(await fileText(design));
ok("undo back to no group", !newGroups(after).length);

// Themed selects
await p.locator(".toolbar .picker .current").click();
await p.waitForSelector('.pop input[aria-label="Search cards"]');
await p.keyboard.type("gol");
await p.keyboard.press("Enter");
await settle();
ok(
  "card picker search",
  (await p.textContent(".picker .current")).includes("gold"),
  await p.textContent(".picker .current"),
);
ok(
  "no native selects left",
  (await p.locator("select").count()) === 0,
  String(await p.locator("select").count()),
);

// Param rename
await p.click('.left .tabs button:has-text("Params")');
await p.click('.param .head:has(.mono:text-is("title"))');
const nameInput = p.locator(".param.open input.mono").first();
await nameInput.fill("heading");
await nameInput.press("Enter");
await settle();
after = JSON.parse(await fileText(design));
const cardsAfter = JSON.parse(await fileText(cards));
ok("param renamed in design", !!after.params.heading && !after.params.title);
ok(
  "param renamed in layers",
  L(after, "title").text.includes("heading"),
  L(after, "title").text,
);
ok(
  "param renamed in cards",
  cardsAfter.cards.every((c) => !("title" in c)) &&
    cardsAfter.cards.some((c) => "heading" in c),
);
ok("no errors after rename", !/error/i.test(await status()), await status());
await p.keyboard.press("Control+z");
await settle();
ok(
  "undo restores both files",
  JSON.parse(await fileText(cards)).cards[0].title === "Shiro",
);

// Card list
await p.click('.left .tabs button:has-text("Card data")');
const cardCount = async () =>
  Number((await p.textContent(".cards-head .muted")).replace(/\D/g, ""));
const c0 = await cardCount();
await p.click('button:has-text("+ Card")');
await settle();
const c1 = await cardCount();
ok("add card", c1 === c0 + 1, `${c0} -> ${c1}`);
await p.click('.card-tools button[title="Duplicate this card"]');
await settle();
ok("duplicate card", (await cardCount()) === c1 + 1);
const idInput = p.locator(".card-id input");
await idInput.fill("renamed");
await idInput.press("Enter");
await settle();
ok(
  "rename card",
  (await p
    .locator('.left .cards [role=option] .id:text-is("renamed")')
    .count()) === 1,
);
await p.click('.card-tools button[title="Delete this card"]');
await p.waitForSelector(".dialog");
ok(
  "delete asks in a themed dialog",
  (await p.locator(".dialog").textContent()).includes("Delete card 'renamed'"),
);
await p.click(".dialog .primary");
await settle();
ok("delete card", (await cardCount()) === c1);
await p.locator('.left .cards input[aria-label="Search cards"]').fill("blu");
await p.waitForTimeout(150);
const found = await p.locator(".left .cards [role=option]").count();
ok("card search filters", found === 1, `rows=${found}`);

// List param table (stats)
const rows0 = await p.locator(".items tbody tr").count();
await p.locator('.left .cards [role=option]:has(.id:text-is("blue"))').click();
await settle();
const rowsBlue = await p.locator(".items tbody tr").count();
ok("stats table shows rows", rowsBlue === 3, `rows=${rowsBlue} (${rows0})`);
await p.click(".items .add");
await settle();
ok("add list row", (await p.locator(".items tbody tr").count()) === 4);

// Upload an image from the header
const png = await readFile(`${shots}/v02-rotate.png`);
let chooser = p.waitForEvent("filechooser");
await p.click('header button:has-text("Upload image")');
await (
  await chooser
).setFiles({ name: "logo.png", mimeType: "image/png", buffer: png });
await settle();
ok(
  "upload image",
  /assets\/images\/logo\.png/.test(await status()),
  await status(),
);

// Upload an image from an image layer's picker
await p.click('.toolbar button:has-text("Image")');
await settle();
await p
  .locator('.inspector button[aria-label="Choose or upload an image"]')
  .click();
chooser = p.waitForEvent("filechooser");
await p.locator('[role=option]:has-text("Upload image")').click();
await (
  await chooser
).setFiles({ name: "photo.png", mimeType: "image/png", buffer: png });
await settle();
const imgLayer = flat(JSON.parse(await fileText(design)).layers).find(
  (l) => l.type === "image" && l.src === "assets/images/photo.png",
);
ok("image picker upload sets src", !!imgLayer, imgLayer?.id);

// Advanced view editor
await p.click('button[role=tab]:has-text("Advanced")');
ok(
  "codemirror loads",
  !!(await p
    .waitForSelector(".cm-editor", { timeout: 5000 })
    .catch(() => null)),
);
await p.screenshot({ path: `${shots}/v02-code.png` });
await p.click('button[role=tab]:has-text("Builder")');

// New design in this project
await p.click('button:has-text("+ Design")');
await p.locator(".dialog input").fill("Second Design");
await p.keyboard.press("Enter");
await p.waitForTimeout(1500);
ok("new design rendered", /rendered in/.test(await status()), await status());
await p.screenshot({ path: `${shots}/v02-newdesign.png` });

// Saved in this browser, survives a reload
await p.waitForSelector(".saved.saved", { timeout: 5000 }).catch(() => null);
ok(
  "autosaved",
  ((await p.textContent(".saved")) ?? "").includes("Saved in this browser"),
  await p.textContent(".saved"),
);
await p.reload();
await rendered();
ok(
  "reload reopens the project",
  (await p.textContent(".pname")) === "feature-tour" &&
    (await p.locator(".tag").count()) === 0,
);
await p.click('button[role=tab]:has-text("Advanced")');
await p.click('aside.files .tabs button:has-text("Files")');
ok(
  "uploaded image survives reload",
  (await p
    .locator('aside.files li[data-path="assets/images/logo.png"]')
    .count()) === 1,
);
await p.click('button[role=tab]:has-text("Builder")');
await p.click('.toolbar button[aria-label="Design"]');
const designsAfter = await p.locator("[role=option]").count();
await p.keyboard.press("Escape");
ok("new design survives reload", designsAfter === 2, String(designsAfter));

// Export the project as a zip with its images, then open that zip
const dl = p.waitForEvent("download");
await p.click('header button:has-text("Export zip")');
const zipPath = `${shots}/export.zip`;
await (await dl).saveAs(zipPath);
const zipped = unzipSync(new Uint8Array(await readFile(zipPath)));
ok(
  "export zip has images",
  !!zipped["feature-tour/assets/images/logo.png"] &&
    !!zipped["feature-tour/designs/tour.design.json"],
  Object.keys(zipped).length + " files",
);
await p.click(".project-btn");
chooser = p.waitForEvent("filechooser");
await p.locator('.menu [role=menuitem]:has-text("Open project zip")').click();
await (await chooser).setFiles(zipPath);
await rendered();
ok(
  "open project zip",
  (await p.textContent(".pname")) === "feature-tour" &&
    /rendered in/.test(await status()),
  await status(),
);

// New project
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("New project")').click();
await p.locator(".dialog input").fill("   ");
await p.click(".dialog .primary");
ok("dialog validates names", (await p.locator(".dialog .err").count()) === 1);
await p.locator(".dialog input").fill("Fresh Cards");
await p.click(".dialog .primary");
await p.waitForTimeout(1500);
ok(
  "new project",
  (await p.textContent(".pname")) === "fresh-cards" &&
    /rendered in/.test(await status()),
  await status(),
);
await p.click(".project-btn");
const saved = await p
  .locator('.menu .heading:text-is("Saved in this browser") ~ [role=menuitem]')
  .allTextContents();
ok(
  "menu lists saved projects",
  saved.filter((t) => /feature-tour|fresh-cards/.test(t)).length >= 3,
  saved.length + " items",
);
await p.screenshot({ path: `${shots}/project-menu.png` });
await p
  .locator('.menu [role=menuitem]:has-text("Delete from this browser")')
  .click();
await p.click(".dialog .primary");
await settle();
ok(
  "delete from browser",
  (await p.locator(".tag").count()) === 1 ||
    ((await p.textContent(".saved")) ?? "").includes("Example"),
  await p.textContent(".saved"),
);
await p.screenshot({ path: `${shots}/v02-newproject.png` });

await p.emulateMedia({ colorScheme: "dark" });
await p.screenshot({ path: `${shots}/v03-dark.png` });
ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
