// Helpers shared by the screenshot shots: a fresh browser context per shot
// (so no saved state leaks in), the theme, the example project, and a few
// common editor actions.
import { chromium } from "playwright";

export const VIEWPORT = { width: 1500, height: 950 };

/** Styles that keep screenshots deterministic: no caret blink, no animations. */
const FREEZE = `*, *::before, *::after {
	caret-color: transparent !important;
	animation: none !important;
	transition: none !important;
	scroll-behavior: auto !important;
}`;

export async function launch() {
	return chromium.launch();
}

/**
 * Opens the editor in a fresh context with the given theme ("light" or
 * "dark") and example project ("Poker deck" is what a fresh editor opens;
 * "board-game" is the other example). Returns the helper object that shots use.
 */
export async function open(browser, { base, theme, project = "poker", viewport = VIEWPORT }) {
	const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, colorScheme: theme });
	await ctx.addInitScript((t) => localStorage.setItem("yoshida.theme", t), theme);
	const p = await ctx.newPage();
	const logs = [];
	p.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
	p.on(
		"console",
		(m) =>
			m.type() === "error" &&
			!/api\/capabilities|status of 404|status of 502/.test(m.text() + m.location().url) &&
			logs.push(`console: ${m.text()}`),
	);
	await p.goto(base);
	await p.addStyleTag({ content: FREEZE });
	const h = helpers(p, logs, ctx);
	await h.rendered();
	if (project !== "poker") await h.openExample(project);
	return h;
}

function helpers(p, logs, ctx) {
	const h = {
		p,
		ctx,
		logs,
		/** Waits until the status line says a render finished. */
		rendered: () =>
			p.waitForFunction(
				() => /rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
				null,
				{ timeout: 30000 },
			),
		/** Opens an example from the project menu (the label is the menu text, e.g. "board-game"). */
		async openExample(label) {
			await p.click(".project-btn");
			await p.locator(`.menu [role=menuitem]:has-text("${label}")`).click();
			await h.rendered();
		},
		/** Left panel tab: Layers, Params, Card data or Files. */
		async leftTab(name) {
			await p.click(`.left .tabs button:has-text("${name}")`);
			await p.waitForTimeout(150);
		},
		/** Selects a layer by its id in the layer tree. */
		async selectLayer(id) {
			await p.locator(`.tree .row:has(.name:text-is("${id}"))`).first().click();
			await p.waitForTimeout(150);
		},
		/** Moves the mouse out of the way and lets fonts, previews and layout settle. */
		async settle(ms = 250) {
			await p.mouse.move(2, 2);
			await p.evaluate(() => document.fonts.ready);
			await p.waitForTimeout(ms);
		},
		/** Saves a screenshot. `clip` is {x, y, width, height} in page pixels; without it the whole viewport. */
		async save(path, clip) {
			await p.screenshot({ path, ...(clip ? { clip } : {}) });
		},
		/** Bounding box of a locator as a clip, grown by `pad` px and kept inside the viewport. */
		async clipOf(locator, pad = 0) {
			const b = await (typeof locator === "string" ? p.locator(locator).first() : locator).boundingBox();
			if (!b) throw new Error(`no box for ${locator}`);
			const x = Math.max(0, Math.floor(b.x - pad));
			const y = Math.max(0, Math.floor(b.y - pad));
			const vp = p.viewportSize();
			return {
				x,
				y,
				width: Math.min(vp.width - x, Math.ceil(b.width + 2 * pad)),
				height: Math.min(vp.height - y, Math.ceil(b.height + 2 * pad)),
			};
		},
	};
	return h;
}
