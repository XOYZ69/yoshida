// The expression editor in an inspector field: suggestions while typing,
// signature help inside a call, and the ƒ reference. Poker example, a text
// layer (index_rank) selected in the Layers tree.
export const shots = [
	{
		name: "editor-expr-suggest",
		page: "builder-expression-editor.md",
		alt: "Suggestions while typing: the autocomplete list open under an expression field",
		async run(h) {
			const p = h.p;
			await h.selectLayer("index_rank");
			const field = p.locator('aside.right .cm-content[aria-label="at.x"]').first();
			await field.click();
			await p.keyboard.press("Control+A");
			await p.keyboard.type("r", { delay: 30 });
			await p.waitForSelector(".cm-tooltip-autocomplete li");
			await h.settle(300);
		},
	},
	{
		name: "editor-expr-signature",
		page: "builder-expression-editor.md",
		alt: "Signature help: the min() signature with the second argument highlighted",
		async run(h) {
			const p = h.p;
			await h.selectLayer("index_rank");
			const field = p.locator('aside.right .cm-content[aria-label="size"]').first();
			await field.click();
			await p.keyboard.press("Control+A");
			await p.keyboard.type("min(index_x, ", { delay: 30 });
			await p.waitForSelector(".yx-sighelp");
			await h.settle(300);
		},
	},
	{
		name: "editor-expr-reference",
		page: "builder-expression-editor.md",
		alt: "The ƒ reference: the reference panel open for an expression field",
		async run(h) {
			const p = h.p;
			await h.selectLayer("index_rank");
			const field = p.locator('aside.right .cm-content[aria-label="at.x"]').first();
			await field.hover();
			await p.locator('aside.right button[aria-label="Expression reference"]').first().click();
			await p.waitForSelector('[role=dialog][aria-label="Expression reference"]');
			await h.settle(300);
		},
	},
];
