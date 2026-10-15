// End-to-end checks for the JSON pointers of the inspector's fields: a layer's
// expression fields point into its layer (/layers/0/fill), and the design
// settings point to the canvas, constants and functions from the document root.
//
//   node tests/ui-paths.mjs [http://localhost:4173/]
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
const paths = () =>
	p.$$eval("aside.right [data-path]", (els) =>
		els.map((el) => el.getAttribute("data-path")),
	);

await p.goto(base);
await rendered();
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
await row("paper").click();

const layer = await paths();
ok(
	"a selected layer's fields carry data-path",
	layer.length > 0,
	`${layer.length} fields`,
);
ok(
	"every layer field path starts with /layers/",
	layer.length > 0 && layer.every((x) => x.startsWith("/layers/")),
	layer.slice(0, 4).join(" "),
);
ok(
	"the fill of the first layer is /layers/0/fill",
	(await p
		.locator('aside.right .field[data-path="/layers/0/fill"]')
		.count()) === 1,
);
await p.screenshot({ path: `${shots}/paths-layer.png` });

// Back to the design settings: the paths start at the document root.
await p.click("aside.right button.back");
await rendered();
const design = await paths();
ok("design fields point at /canvas/width", design.includes("/canvas/width"));
ok("a constant points at /consts/<name>", design.includes("/consts/tile"));
ok(
	"a function expression points at /functions/<name>/expr",
	design.includes("/functions/tile_x/expr"),
);

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
