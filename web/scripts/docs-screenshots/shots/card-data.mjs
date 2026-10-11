// The Card data tab, the card browser window and the card picker (builder-card-data.md).
export const shots = [
	{
		name: "editor-card-form",
		page: "builder-card-data.md",
		alt: "The card form",
		async run(h) {
			await h.leftTab("Card data");
			await h.p.locator(".form").first().waitFor({ state: "visible" });
		},
	},
	{
		name: "editor-card-browser",
		page: "builder-card-data.md",
		alt: "The card browser",
		async run(h) {
			await h.leftTab("Card data");
			await h.p.click(`.cards-head button:has-text("Browse")`);
			const win = h.p.locator(".win").filter({ hasText: "Cards of" }).first();
			await win.waitFor({ state: "visible" });
			await win.locator(`.btn-group [role=tab]:has-text("Grid")`).click();
			await win.locator(".tile img").first().waitFor({ state: "visible" });
			await h.p.waitForFunction(
				() => {
					const imgs = [...document.querySelectorAll(".win .tile img")];
					return imgs.length > 0 && imgs.every((i) => i.complete && i.naturalWidth > 0);
				},
				null,
				{ timeout: 30000 },
			);
			await h.p.mouse.move(2, 2);
		},
	},
	{
		name: "editor-card-picker",
		page: "builder-card-data.md",
		alt: "The card picker",
		project: "board-game",
		async run(h) {
			await h.p.click(`.picker .current`);
			const pop = h.p.locator(".pop").first();
			await pop.waitFor({ state: "visible" });
			await pop.locator(".row").first().waitFor({ state: "visible" });
			const a = await h.p.locator(".picker").first().boundingBox();
			const b = await pop.boundingBox();
			const x = Math.max(0, Math.floor(Math.min(a.x, b.x) - 16));
			const y = Math.max(0, Math.floor(Math.min(a.y, b.y) - 16));
			const right = Math.max(a.x + a.width, b.x + b.width) + 16;
			const bottom = Math.max(a.y + a.height, b.y + b.height) + 16;
			return { x, y, width: Math.ceil(right - x), height: Math.ceil(bottom - y) };
		},
	},
];
