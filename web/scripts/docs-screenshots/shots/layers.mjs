// Layers tab, layer groups and the text Inspector (used by builder-layers,
// layer-group, layer-text and the landing page's editor picture).

/** Switches the poker project to the court-card design and previews the Queen of spades. */
async function courtQueen(h) {
	await h.p.locator('button[aria-label="Design file"]').click();
	await h.p.locator('[role=option]:has-text("Court cards")').click();
	await h.rendered();
	await h.p.locator('button[title="Next card"]').click();
	await h.rendered();
}

export const shots = [
	{
		name: "editor-layers-group",
		page: "builder-layers.md, layer-group.md",
		alt: "The Layers tab with a group expanded and a layer inside it selected",
		async run(h) {
			await courtQueen(h);
			await h.leftTab("Layers");
			await h.selectLayer("crown_k");
		},
	},
	{
		name: "editor-text-layer",
		page: "layer-text.md",
		alt: "A text layer selected in the editor, with its fields in the Inspector",
		async run(h) {
			await h.leftTab("Layers");
			await h.selectLayer("index_rank");
		},
	},
	{
		name: "landing-editor",
		page: "landing page (showcase picture of the editor)",
		alt: "The editor showing a court card with a layer selected",
		async run(h) {
			await courtQueen(h);
			await h.leftTab("Layers");
			await h.selectLayer("medallion");
		},
	},
];
