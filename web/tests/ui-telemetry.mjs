// End-to-end checks for the optional telemetry: the start-up notice, that
// nothing is sent before it is confirmed, the levels, the live "what we
// track" view, the data download, and a server that locks the level.
// The yoshida server is played by request interception, so this runs against
// any static preview too.
//
//   node tests/ui-telemetry.mjs [http://localhost:4173/]
import { readFileSync } from "node:fs";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
let failed = 0;
const ok = (n, c, x = "") => {
	if (!c) failed++;
	console.log(`${c ? "PASS" : "FAIL"} ${n} ${x}`);
};
const b = await chromium.launch();

/** A page whose "server" has this telemetry configuration; returns what it received. */
async function open(telemetry, { storage = {} } = {}) {
	const ctx = await b.newContext({ viewport: { width: 1500, height: 900 }, acceptDownloads: true });
	const p = await ctx.newPage();
	p.on("pageerror", (e) => console.log("pageerror", e.message));
	const sent = { pings: [], events: [] };
	await p.route("**/api/capabilities", (r) =>
		r.fulfill({
			contentType: "application/json",
			body: JSON.stringify({ version: "0.0.0", format: 1, render: false, max_cards: 10, telemetry }),
		}),
	);
	await p.route("**/api/telemetry/ping", (r) => {
		sent.pings.push(r.request().postData());
		return r.fulfill({ status: 204 });
	});
	await p.route("**/api/telemetry/events", (r) => {
		sent.events.push(r.request().postData());
		return r.fulfill({ status: 204 });
	});
	await p.addInitScript((s) => {
		for (const [k, v] of Object.entries(s)) if (!localStorage.getItem(k)) localStorage.setItem(k, v);
	}, storage);
	await p.goto(base);
	await p.waitForSelector('[data-testid="privacy-button"]', { timeout: 30000 });
	return { p, ctx, sent };
}
const on = (extra = {}) => ({ enabled: true, default: "basic", force: null, retention_days: 90, ...extra });

// 1. First visit: the notice comes first and nothing is sent until it is confirmed.
{
	const { p, ctx, sent } = await open(on());
	await p.waitForSelector('[data-testid="telemetry-notice"]', { timeout: 5000 });
	await p.waitForTimeout(1200);
	ok("notice shown on the first visit", true);
	ok("nothing sent before the notice is confirmed", sent.pings.length === 0 && sent.events.length === 0);
	ok("the server default is preselected", await p.locator('input[name="tel-level"][value="basic"]').isChecked());
	await p.locator('input[name="tel-level"][value="advanced"]').check();
	await p.click('[data-testid="telemetry-accept"]');
	await p.waitForFunction(() => !document.querySelector('[data-testid="telemetry-notice"]'));
	await p.waitForTimeout(600);
	ok("one ping after confirming", sent.pings.length === 1, JSON.stringify(sent.pings));
	ok("the ping carries only the level", sent.pings[0] === '{"level":"advanced"}');
	// Advanced: opening the Fonts-free feature "functions" through the toolbar.
	await p.click(".fn-btn:has-text('Functions')");
	await p.waitForTimeout(300);
	await p.click('[data-testid="privacy-button"]');
	const win = p.locator('[data-testid="telemetry-window"]');
	await win.waitFor({ timeout: 5000 });
	const logText = await p.locator('[data-testid="telemetry-log"]').innerText();
	ok("live view lists the ping", /ping/.test(logText), logText);
	ok("live view lists the feature event", /feature:functions\.open/.test(logText), logText);
	// The batch goes out within a few seconds.
	await p.waitForFunction(() => /sent/.test(document.querySelector('[data-testid="telemetry-log"]')?.textContent ?? ""), null, { timeout: 15000 });
	await p.waitForTimeout(9000);
	ok("events were posted as group and name only", sent.events.length >= 1 && sent.events[0] === '{"events":[{"k":"feature","n":"functions.open"}]}', JSON.stringify(sent.events));
	// Switch to Off: no more events.
	await win.locator('input[name="tel-level-settings"][value="off"]').check();
	const before = sent.events.length;
	await p.keyboard.press("Escape");
	await p.click(".fn-btn:has-text('Functions')");
	await p.click(".fn-btn:has-text('Functions')");
	await p.waitForTimeout(9500);
	ok("no events after switching to Off", sent.events.length === before);
	// Download
	await p.click('[data-testid="privacy-button"]').catch(() => {});
	const dl = p.waitForEvent("download", { timeout: 5000 });
	await p.click('[data-testid="telemetry-download"]');
	const file = await dl;
	const path = await file.path();
	const data = JSON.parse(readFileSync(path, "utf8"));
	ok("download holds the local log", Array.isArray(data.events) && data.events.length >= 2, `${data.events?.length} events`);
	ok("download names the level in force", data.settings.level_in_force === "off");
	ok("download file name", file.suggestedFilename() === "yoshida-telemetry-log.json");
	await ctx.close();
}

// 2. Returning visitor who confirmed Basic: pings at once, no notice, no events.
{
	const { p, ctx, sent } = await open(on(), {
		storage: { "yoshida.telemetry": JSON.stringify({ level: "basic", notice: 1 }) },
	});
	await p.waitForTimeout(1200);
	ok("no notice for a returning visitor", (await p.locator('[data-testid="telemetry-notice"]').count()) === 0);
	ok("returning visitor pings", sent.pings.length === 1 && sent.pings[0] === '{"level":"basic"}');
	await p.click(".fn-btn:has-text('Functions')");
	await p.waitForTimeout(500);
	ok("basic sends no events", sent.events.length === 0);
	await ctx.close();
}

// 3. Server locks the level to off: banner, no choice, nothing sent, even with an old Advanced choice.
{
	const { p, ctx, sent } = await open(on({ force: "off" }), {
		storage: { "yoshida.telemetry": JSON.stringify({ level: "advanced", notice: 0 }) },
	});
	await p.waitForSelector('[data-testid="telemetry-notice"]', { timeout: 5000 });
	ok("locked notice has no level choice", (await p.locator('input[name="tel-level"]').count()) === 0);
	await p.click('[data-testid="telemetry-accept"]');
	await p.waitForTimeout(800);
	ok("forced off sends nothing", sent.pings.length === 0 && sent.events.length === 0);
	await p.click('[data-testid="privacy-button"]');
	await p.waitForSelector('[data-testid="telemetry-locked"]', { timeout: 5000 });
	ok("settings show the lock banner", /locks the level to off/.test(await p.locator('[data-testid="telemetry-locked"]').innerText()));
	ok("level radios are disabled", await p.locator('input[name="tel-level-settings"][value="advanced"]').isDisabled());
	await ctx.close();
}

// 4. A server that locks to Basic ignores a stored Advanced choice.
{
	const { p, ctx, sent } = await open(on({ force: "basic" }), {
		storage: { "yoshida.telemetry": JSON.stringify({ level: "advanced", notice: 1 }) },
	});
	await p.waitForTimeout(1000);
	ok("forced basic pings as basic", sent.pings.length === 1 && sent.pings[0] === '{"level":"basic"}', JSON.stringify(sent.pings));
	await p.click(".fn-btn:has-text('Functions')");
	await p.waitForTimeout(500);
	await p.click('[data-testid="privacy-button"]');
	await p.waitForTimeout(8500);
	ok("forced basic sends no events", sent.events.length === 0);
	await ctx.close();
}

// 5. No yoshida server (static hosting): nothing at all, no notice.
{
	const { p, ctx, sent } = await open({ enabled: false });
	await p.waitForTimeout(1000);
	ok("disabled server: no notice", (await p.locator('[data-testid="telemetry-notice"]').count()) === 0);
	ok("disabled server: nothing sent", sent.pings.length === 0);
	await p.click('[data-testid="privacy-button"]');
	await p.waitForSelector('[data-testid="telemetry-window"]');
	ok("settings explain that nothing is sent", /nothing is sent/i.test(await p.locator('[data-testid="telemetry-window"]').innerText()));
	await ctx.close();
}

await b.close();
process.exit(failed ? 1 : 0);
