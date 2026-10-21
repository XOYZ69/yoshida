// The editor as a whole and its left-panel tabs.
export const shots = [
	{
		name: "editor-params",
		page: "builder.md, builder-params.md",
		alt: "The Params tab of the poker design, with params in sections and the suit param expanded",
		async run(h) {
			await h.leftTab("Params");
			await h.p.locator('.param[data-param="suit"] .head').click();
			await h.p.locator('.param[data-param="suit"].open').waitFor();
		},
	},
	{
		name: "editor-design-settings",
		page: "builder-inspector.md",
		alt: "The right panel with the design settings, nothing selected",
		async run(h) {
			await h.leftTab("Layers");
			// Nothing selected: click empty canvas (outside the card), so no focus ring is left behind.
			await h.p.mouse.click(300, 300);
			await h.p.waitForFunction(() => !document.querySelector(".tree .row.sel"));
			// Show the top of the layer list.
			await h.p.evaluate(() => {
				for (let el = document.querySelector(".tree"); el; el = el.parentElement)
					if (el.scrollTop) el.scrollTop = 0;
			});
		},
	},
	{
		name: "editor-files",
		page: "builder-files.md",
		alt: "The Files tab as a folder tree of the poker project, with a font file selected",
		async run(h) {
			await h.leftTab("Files");
			const font = '[data-path="assets/fonts/DMSerifDisplay-Regular.ttf"]';
			await h.p.locator(`${font} .row`).click();
			await h.p.locator(`${font}.sel`).waitFor();
		},
	},
	{
		name: "editor-project-menu",
		page: "builder.md, saving-images-and-privacy.md",
		alt: "The project menu open from the project button, listing the saved project",
		async run(h) {
			// Renaming the example makes it a saved project in this browser.
			await h.p.click(".project-btn");
			await h.p.locator('.menu [role=menuitem]:has-text("Rename")').click();
			await h.p.locator(".dialog input").fill("My poker deck");
			await h.p.locator(".dialog button.primary").click();
			await h.p.waitForFunction(() =>
				/Saved in this browser/.test(document.querySelector(".saved")?.textContent ?? ""),
			);
			// Open the menu again.
			await h.p.click(".project-btn");
			await h.p.locator(".menu").waitFor();
			const menu = await h.clipOf(".menu", 16);
			const bar = await h.clipOf(".project-btn", 0);
			const width = Math.max(menu.x + menu.width, bar.x + bar.width) + 16;
			const height = menu.y + menu.height + 16;
			return { x: 0, y: 0, width: Math.min(width, 1500), height: Math.min(height, 950) };
		},
	},
	{
		name: "editor-export",
		page: "builder.md",
		alt: "The export dialog with PNG and PDF chosen for the poker number cards",
		async run(h) {
			await h.p.locator('button[aria-haspopup="dialog"]:has-text("Export…")').click();
			const dialog = h.p.locator('[role=dialog][aria-labelledby="export-title"]');
			await dialog.waitFor({ state: "visible" });
			await dialog.locator('label.opt:has-text("PDF") input[type=checkbox]').check();
			await h.p.waitForFunction(() => /PDF/.test(document.querySelector(".dialog .summary")?.textContent ?? ""));
			return h.clipOf(dialog, 16);
		},
	},
];
