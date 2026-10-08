// End-to-end checks for organising a project: param groups and views, the
// enum options editor, notes in the card form, dividers and the empty-space
// layer menu, the Files tab (upload folder, rename with reference rewrite),
// the card browser, splitters and movable dialogs.
//
//   node tests/ui-organise.mjs [http://localhost:4173/]
import { mkdir, readFile } from "node:fs/promises";
import { chromium } from "playwright";

const base =
  process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
const shots = "test-results";
await mkdir(shots, { recursive: true });

const b = await chromium.launch();
const ctx = await b.newContext({
  viewport: { width: 1500, height: 950 },
  permissions: ["clipboard-read", "clipboard-write"],
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
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("yugioh")').click();
await rendered();
ok("opens yugioh", /rendered in/.test(await status()), await status());
const design = "designs/monster.design.json";
const cards = "cards/test.cards.json";

// Dividers in the layer list
const dividers = await p
  .locator(".tree .row.divider .dlabel")
  .allTextContents();
ok(
  "dividers show as titled rows",
  dividers.join("|") === "Print info|Text and stats|Artwork and frame",
  dividers.join("|"),
);

// Right-click on empty space in the layer list
await p.click(".tree li.end", { button: "right", force: true });
const addItems = await p.locator(".menu [role=menuitem]").allTextContents();
ok(
  "empty-space menu offers adding",
  addItems.some((t) => t.includes("Rect")) &&
    addItems.some((t) => t.includes("Divider")),
  addItems.join(" | "),
);
await p.locator('.menu [role=menuitem]:has-text("Divider")').click();
await p.locator(".dialog input").fill("Stats");
await p.click(".dialog .primary");
await settle();
let d = JSON.parse(await fileText(design));
const added = d.layers.find((l) => l.type === "divider" && l.label === "Stats");
ok("divider added to the design", !!added, added?.id);
await rendered();
ok(
  "divider renders without errors",
  /rendered in/.test(await status()),
  await status(),
);

// Params: groups, A to Z view, filter
await p.click('.left .tabs button:has-text("Params")');
const sections = await p.locator(".params .section .title").allTextContents();
ok(
  "params are grouped",
  sections.join("|") === "No group|Card text|Monster stats|Print",
  sections.join("|"),
);
await p.click('.params .section:has(.title:text-is("Print")) .fold');
ok(
  "a group folds",
  (await p.locator('.param .head .mono:text-is("set_code")').count()) === 0,
);
await p.locator(".params .bar input").fill("atk");
ok("filter narrows params", (await p.locator(".param").count()) === 1);
await p.locator(".params .bar input").fill("");
await p.locator('.params .bar [aria-label="Show params"]').click();
await p.locator('[role=option]:has-text("A to Z")').click();
const az = await p.locator(".param .head .mono").allTextContents();
ok(
  "A to Z view",
  az.join(",") === [...az].sort().join(",") && az.length === 15,
  az.slice(0, 4).join(","),
);
await p.locator('.params .bar [aria-label="Show params"]').click();
await p.locator('[role=option]:has-text("Groups")').click();
ok("back to groups", (await p.locator(".params .section").count()) >= 3);

// Drag a param into another group
await p
  .locator('.param:has(.head .mono:text-is("scale"))')
  .dragTo(p.locator('.param:has(.head .mono:text-is("atk"))'), {
    targetPosition: { x: 40, y: 4 },
  });
await settle();
d = JSON.parse(await fileText(design));
const keys = Object.keys(d.params);
ok(
  "drag moves the param into the group",
  d.params.scale.group === "Monster stats" &&
    keys.indexOf("scale") === keys.indexOf("atk") - 1,
  keys.join(","),
);

// Enum options editor: add, rename (updates the cards), templates warn
await p.click('.left .tabs button:has-text("Params")');
await p.click('.param .head:has(.mono:text-is("star_type"))');
const optInputs = p.locator(".param.open .opts li input");
ok("enum options are rows", (await optInputs.count()) === 2);
await p.locator(".param.open .opts > input").fill("green");
await p.locator(".param.open .opts > input").press("Enter");
await settle();
ok(
  "enter adds an option",
  (await p.locator(".param.open .opts li input").count()) === 3,
);
// Give the card a value, then rename that option.
await p.click('.left .tabs button:has-text("Card data")');
await p
  .locator('.fld:has(.name:has-text("star_type")) button[aria-haspopup]')
  .first()
  .click();
await p.locator('[role=option]:has-text("red")').click();
await settle();
await p.click('.left .tabs button:has-text("Params")');
await p.click('.param .head:has(.mono:text-is("star_type"))');
const red = p.locator(".param.open .opts li input").nth(1);
await red.fill("crimson");
await red.press("Enter");
ok(
  "renaming warns about path templates",
  (await p.locator(".dialog .msg").textContent())?.includes(
    "level-star-{star_type}",
  ),
);
await p.click(".dialog .primary");
await settle();
d = JSON.parse(await fileText(design));
let c = JSON.parse(await fileText(cards));
ok(
  "option renamed in design and cards",
  d.params.star_type.options.includes("crimson") &&
    c.cards[0].star_type === "crimson",
  JSON.stringify(d.params.star_type.options),
);
await p.keyboard.press("Control+z");
await settle();
c = JSON.parse(await fileText(cards));
ok(
  "undo restores the card value",
  c.cards[0].star_type === "red",
  c.cards[0].star_type,
);

// Notes in the card form
await p.click('.left .tabs button:has-text("Card data")');
const info = p.locator('.fld:has(.name:has-text("author")) .info');
ok("note shows an info icon", (await info.count()) === 1);
await info.hover();
ok(
  "note tooltip on hover",
  await p.locator('.fld:has(.name:has-text("author")) .tip').isVisible(),
);
ok(
  "card form has group sections",
  (await p.locator(".form .section").count()) === 3,
);
await p.screenshot({ path: `${shots}/v04-card-form.png` });

// Files tab: choose a folder, upload into it, rename a referenced file
await p.click('.left .tabs button:has-text("Files")');
await p.click('.ftree li[data-path="assets/images/lvl"] .row');
const png = await readFile(`${shots}/v04-card-form.png`);
let chooser = p.waitForEvent("filechooser");
await p.click('header button:has-text("Upload image")');
await (
  await chooser
).setFiles({ name: "star.png", mimeType: "image/png", buffer: png });
await settle();
ok(
  "upload goes to the chosen folder",
  /assets\/images\/lvl\/star\.png/.test(await status()),
  await status(),
);
ok(
  "new file is in the tree",
  (await p
    .locator('.ftree li[data-path="assets/images/lvl/star.png"]')
    .count()) === 1,
);
await p.click('.ftree li[data-path="assets/images/shiro_square.jpg"] .row', {
  button: "right",
});
await p.locator('.menu [role=menuitem]:has-text("Rename")').click();
await p.locator(".dialog input").fill("shiro.jpg");
await p.click(".dialog .primary");
await settle();
c = JSON.parse(await fileText(cards));
ok(
  "rename rewrites card references",
  c.cards[0].art === "assets/images/shiro.jpg",
  c.cards[0].art,
);
const probs = (await p.textContent(".problems-pane")) ?? "";
ok(
  "no problems after the rename",
  !probs.includes("shiro"),
  probs.slice(0, 120),
);
await p.click('.left .tabs button:has-text("Files")');
await p
  .locator('.ftree li[data-path="assets/images/cards/monster-effect.png"]')
  .dragTo(p.locator('.ftree li[data-path="assets/images"]'));
ok(
  "moving a templated file warns",
  (await p.locator(".dialog .msg").textContent())?.includes("{card_type}"),
);
await p.click(".dialog .ghost");
await p.screenshot({ path: `${shots}/v04-files.png` });

// Card browser
await p.click('.left .tabs button:has-text("Card data")');
await p.click('.cards-head button:has-text("Browse")');
await p.waitForSelector(".win");
ok("card browser table", (await p.locator(".win .tr").count()) === 1);
await p.click('.win .seg button:has-text("Grid")');
await p.waitForSelector(".win .tile img", { timeout: 15000 }).catch(() => null);
ok(
  "grid shows a rendered thumbnail",
  (await p.locator(".win .tile img").count()) === 1,
);
const box0 = await p.locator(".win").boundingBox();
await p.mouse.move(box0.x + box0.width - 6, box0.y + box0.height - 6);
await p.mouse.down();
await p.mouse.move(box0.x + box0.width + 94, box0.y + box0.height + 44, {
  steps: 4,
});
await p.mouse.up();
const box1 = await p.locator(".win").boundingBox();
ok(
  "window resizes from the corner",
  Math.round(box1.width - box0.width) === 100,
  `${box0.width} -> ${box1.width}`,
);
await p.mouse.move(box1.x + 60, box1.y + 12);
await p.mouse.down();
await p.mouse.move(box1.x + 10, box1.y + 40, { steps: 4 });
await p.mouse.up();
const box2 = await p.locator(".win").boundingBox();
ok(
  "window moves by its title",
  Math.round(box2.x - box1.x) === -50,
  `${box1.x} -> ${box2.x}`,
);
await p.screenshot({ path: `${shots}/v04-card-browser.png` });
await p.keyboard.press("Escape");
ok("escape closes the window", (await p.locator(".win").count()) === 0);

// Splitters
const left0 = (await p.locator("aside.left").boundingBox()).width;
const sp = await p.locator(".split-l .split").boundingBox();
await p.mouse.move(sp.x + 2, sp.y + 200);
await p.mouse.down();
await p.mouse.move(sp.x + 82, sp.y + 200, { steps: 4 });
await p.mouse.up();
const left1 = (await p.locator("aside.left").boundingBox()).width;
ok(
  "left panel resizes",
  Math.round(left1 - left0) === 80,
  `${left0} -> ${left1}`,
);
await p.reload();
await rendered();
ok(
  "panel size is remembered",
  Math.round((await p.locator("aside.left").boundingBox()).width) ===
    Math.round(left1),
);
await p.dblclick(".split-l .split");
ok(
  "double-click resets",
  Math.round((await p.locator("aside.left").boundingBox()).width) === 250,
);

// Themed dialogs move by their title
await p.click('.left .tabs button:has-text("Layers")');
await p.click(".tree li.end", { button: "right", force: true });
await p.locator('.menu [role=menuitem]:has-text("Divider")').click();
await p.waitForTimeout(300);
const dl0 = await p.locator(".dialog").boundingBox();
await p.mouse.move(dl0.x + 40, dl0.y + 24);
await p.mouse.down();
await p.mouse.move(dl0.x + 140, dl0.y + 24, { steps: 4 });
await p.mouse.up();
const dl1 = await p.locator(".dialog").boundingBox();
ok(
  "dialog moves by its title",
  Math.round(dl1.x - dl0.x) === 100,
  `${dl0.x} -> ${dl1.x}`,
);
await p.click(".dialog .ghost");

// List items by key: suggestions after `list.` and `list["`, bracket form for
// keys that are not plain names.
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("cocktail")').click();
await rendered();
await p.locator('.tree .row:has-text("total_volume_text")').first().click();
const tmpl = p.locator('aside.right .cm-content[aria-label="text"]').first();
const keyOptions = () =>
  p.locator(".cm-tooltip-autocomplete li").allTextContents();
await tmpl.click();
await p.keyboard.press("Control+a");
await p.keyboard.type("{ingredients.");
await p.waitForSelector(".cm-tooltip-autocomplete li");
let opts = await keyOptions();
ok(
  "dot suggests the keys seen in the cards",
  opts.some((t) => t.startsWith("kGin")) &&
    opts.some((t) => t.startsWith("kBlue Curacao")),
  opts.slice(0, 3).join("|"),
);
await p
  .locator('.cm-tooltip-autocomplete li:has-text("Blue Curacao")')
  .first()
  .click();
ok(
  "a key with a space becomes the bracket form",
  (await tmpl.innerText()).includes('{ingredients["Blue Curacao"]'),
  await tmpl.innerText(),
);
await p.keyboard.press("Control+a");
await p.keyboard.type('{ingredients["');
await p.waitForSelector(".cm-tooltip-autocomplete li");
ok(
  "a quote suggests the keys too",
  (await keyOptions()).some((t) => t.startsWith("kGin")),
);
await p.keyboard.press("Escape");
await p.keyboard.press("Control+a");
await p.keyboard.type("{ingredients.Gin}");
ok(
  "a key after the dot is not flagged",
  (await p.locator("aside.right .cm-content [class*=unknown]").count()) === 0,
);

await p.emulateMedia({ colorScheme: "dark" });
await p.click('.left .tabs button:has-text("Params")');
await p.screenshot({ path: `${shots}/v04-params-dark.png` });
ok("no page errors", !logs.length, logs.join("\n"));
await b.close();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exitCode = failed ? 1 : 0;
