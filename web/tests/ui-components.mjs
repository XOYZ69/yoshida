// End-to-end checks for components in the builder: the layers of an included
// component show inside its group and are edited in place (the change goes
// to the component file), a group becomes a component from its menu, a
// component is included from the Add bar, detached again, and layers take a
// colour tag.
//
//   node tests/ui-components.mjs [http://localhost:4173/]
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
	await p.waitForTimeout(300);
	const t = await p.evaluate(() => {
		const el = document.querySelector(".cm-content");
		const v = el.cmView?.view ?? el.cmTile?.view;
		return v ? v.state.doc.toString() : el.innerText;
	});
	await p.click('button[role=tab]:has-text("Builder")');
	return t;
}
const hasFile = (path) =>
	p.evaluate(async (path) => {
		// The Files tab of the builder lists every project file.
		return !!document.querySelector(`li[data-path="${path}"]`);
	}, path);
const row = (id) => p.locator(`.tree li[data-id="${id}"]`);
const menuItem = (label) =>
	p.locator(`.menu [role=menuitem]:has-text("${label}")`).first();
const component = "components/effect-row.component.json";
const design = "designs/project.design.json";

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("forge")').click();
await rendered();
await settle();
ok("forge renders", /rendered in/.test(await status()), await status());

// --- The component in the layer list.
ok("the including group has the component icon", (await row("effects").locator(".icon.cmp").count()) === 1);
ok("a plain group keeps the group icon", (await p.locator(".tree .icon.grp").count()) > 0);
const colors = await p.evaluate(() => {
	const c = (sel) => getComputedStyle(document.querySelector(sel)).color;
	return [c(".tree .icon.cmp"), c(".tree .icon.grp")];
});
ok("components and groups differ in colour", colors[0] !== colors[1], colors.join(" / "));
ok("the component's layers are listed inside it", (await row("effect_text").count()) === 1 && (await row("effect_bg").count()) === 1);
ok("they are marked as shared", await row("effect_text").evaluate((e) => e.classList.contains("shared")));
await row("effects").locator(".fold").click();
ok("a component folds like a group", (await row("effect_text").count()) === 0);
await row("effects").locator(".fold").click();

// --- Editing a layer of the component in place.
await row("effect_text").locator(".row").click();
ok(
	"the inspector says the layer is part of a component",
	/Part of the component/.test((await p.locator("aside.right .component-part").textContent()) ?? ""),
);
const size = p.locator('aside.right .cm-content[aria-label="size"]').first();
await size.click();
await p.keyboard.press("ControlOrMeta+a");
await p.keyboard.type("26");
await p.keyboard.press("Enter");
await settle();
await rendered();
let comp = JSON.parse(await fileText(component));
ok("the edit is written to the component file", comp.layers.find((l) => l.id === "effect_text")?.size === 26, JSON.stringify(comp.layers[1]?.size));
ok("the component keeps its name", comp.name === "Effect row");
let des = JSON.parse(await fileText(design));
const inc = des.layers.find((l) => l.id === "effects");
ok("the design still only includes it", inc.include === component && inc.layers === undefined);
ok("no errors after the edit", !/error/i.test(await status()), await status());
await p.keyboard.press("ControlOrMeta+z");
await settle();
comp = JSON.parse(await fileText(component));
ok("undo restores the component file", comp.layers.find((l) => l.id === "effect_text")?.size === 22);

// --- A click on the card selects the component, a double click the layer.
await row("effect_text").locator(".row").click();
const tb = await p.locator(".stage rect.sel").first().boundingBox();
await p.keyboard.press("Escape");
await p.mouse.click(tb.x + tb.width / 2, tb.y + tb.height / 2);
await settle();
ok("a click on the card selects the component", await row("effects").evaluate((e) => e.classList.contains("selected")));
await p.keyboard.press("Escape");
await p.mouse.dblclick(tb.x + tb.width / 2, tb.y + tb.height / 2);
await settle();
ok("a double click selects the layer inside", await row("effect_text").evaluate((e) => e.classList.contains("selected")));

// --- Moving the component only changes the design.
await row("effects").locator(".row").click();
await p.keyboard.press("ArrowRight");
await settle();
des = JSON.parse(await fileText(design));
comp = JSON.parse(await fileText(component));
ok("nudging a component moves its translate", des.layers.find((l) => l.id === "effects").translate.x === 31, JSON.stringify(des.layers.find((l) => l.id === "effects").translate));
ok("and leaves the shared layers where they are", comp.layers[0].box.x === 0);
await p.keyboard.press("ControlOrMeta+z");
await settle();

// --- Detach, then create a component from the group again.
await row("effects").locator(".row").click({ button: "right" });
await menuItem("Detach from component").click();
await settle();
des = JSON.parse(await fileText(design));
let g = des.layers.find((l) => l.id === "effects");
ok("detach keeps a copy of the layers in the design", g.include === undefined && g.layers?.length === 2);
ok("a detached group has the group icon", (await row("effects").locator(".icon.grp").count()) === 1);
ok("detached renders", !/error/i.test(await status()), await status());

await row("effects").locator(".row").click({ button: "right" });
await menuItem("Create component").click();
await p.locator(".dialog input, dialog input").first().fill("Effect panel");
await p.keyboard.press("Enter");
await settle();
await rendered();
const made = "components/effect-panel.component.json";
des = JSON.parse(await fileText(design));
g = des.layers.find((l) => l.id === "effects");
ok("create component: the group includes the new file", g.include === made && g.layers === undefined, JSON.stringify(g));
const madeDoc = JSON.parse(await fileText(made));
ok("create component: the file has the layers and the name", madeDoc.name === "Effect panel" && madeDoc.format === 1 && madeDoc.layers.length === 2);
ok("create component: the card still renders", !/error/i.test(await status()), await status());
ok("create component: the group shows as a component", (await row("effects").locator(".icon.cmp").count()) === 1);
await p.keyboard.press("ControlOrMeta+z");
await settle();
des = JSON.parse(await fileText(design));
ok("one undo takes the component back", des.layers.find((l) => l.id === "effects").layers?.length === 2);
ok("and removes its file", !(await hasFileIn(made)));
await p.keyboard.press("ControlOrMeta+z");
await settle();
des = JSON.parse(await fileText(design));
ok("a second undo includes the old component again", des.layers.find((l) => l.id === "effects").include === component);

// --- Including a component from the Add bar.
await p.locator(".toolbar .add-component").click();
const entry = menuItem("effect-row");
ok("a component already in the design cannot be added twice", await entry.isDisabled(), (await entry.textContent()) ?? "");
await p.keyboard.press("Escape");
await row("effects").locator(".row").click();
await p.keyboard.press("Delete");
await settle();
await p.locator(".toolbar .add-component").click();
await menuItem("effect-row").click();
await settle();
await rendered();
des = JSON.parse(await fileText(design));
g = des.layers.find((l) => l.include === component);
ok("the Add bar includes a component", !!g && g.type === "group" && g.layers === undefined, JSON.stringify(g));
ok("its layers show again", (await row("effect_text").count()) === 1);

// --- Duplicating a component gives a plain copy.
await row(g.id).locator(".row").click();
await p.keyboard.press("ControlOrMeta+d");
await settle();
des = JSON.parse(await fileText(design));
const groups = des.layers.filter((l) => l.type === "group" && (l.include === component || l.layers?.some((x) => /^effect_/.test(x.id))));
ok("a duplicate is a plain group with renamed layers", groups.length === 2 && groups.filter((x) => x.include).length === 1 && groups.find((x) => !x.include).layers.every((x) => /_copy/.test(x.id)), JSON.stringify(groups.map((x) => x.id)));
ok("the duplicate renders without errors", !/error/i.test(await status()), await status());
await p.keyboard.press("ControlOrMeta+z");
await settle();

// --- Colour tags.
await row("name").locator(".row").click({ button: "right" });
await menuItem("Colour").click();
await menuItem("Green").click();
await settle();
des = JSON.parse(await fileText(design));
ok("a colour tag is saved in the design", des.layers.find((l) => l.id === "name")?.tag === "green");
ok("the row is tagged", (await row("name").getAttribute("data-tag")) === "green");
const bg = await p.evaluate(() => {
	const c = (id) => getComputedStyle(document.querySelector(`.tree li[data-id="${id}"]`)).backgroundColor;
	return [c("name"), c("header")];
});
ok("the tag tints the row's background", bg[0] !== bg[1], bg.join(" / "));
ok("a tagged design renders without problems", !/error|warning/i.test(await status()), await status());
await p.screenshot({ path: `${shots}/components.png` });
await row("name").locator(".row").click({ button: "right" });
await menuItem("Colour").click();
await menuItem("None").click();
await settle();
des = JSON.parse(await fileText(design));
ok("None removes the tag", des.layers.find((l) => l.id === "name")?.tag === undefined);

async function hasFileIn(path) {
	await p.click('button[role=tab]:has-text("Advanced")');
	await p.click('aside.files .tabs button:has-text("Files")');
	const n = await p.locator(`aside.files li[data-path="${path}"]`).count();
	await p.click('button[role=tab]:has-text("Builder")');
	return n > 0;
}
void hasFile;

ok("no page errors", logs.length === 0, logs.join("\n"));
await b.close();
process.exit(failed ? 1 : 0);
