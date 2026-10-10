// Themed replacements for the browser's prompt(), confirm() and context
// menus. Components call these functions; DialogHost and MenuHost (mounted
// once in App) draw them.

export type DialogRequest =
	| {
			kind: "text";
			title: string;
			message?: string;
			value: string;
			placeholder?: string;
			confirm: string;
			validate?: (v: string) => string;
			resolve: (v: string | null) => void;
	  }
	| {
			kind: "confirm";
			title: string;
			message?: string;
			confirm: string;
			danger: boolean;
			resolve: (ok: boolean) => void;
	  };

export type MenuItem =
	| {
			label: string;
			detail?: string;
			shortcut?: string;
			disabled?: boolean;
			danger?: boolean;
			icon?: string;
			action: () => void;
	  }
	| { separator: true }
	| { heading: string };

export const overlay = $state<{
	dialog: DialogRequest | null;
	menu: { x: number; y: number; items: MenuItem[] } | null;
}>({
	dialog: null,
	menu: null,
});

/** Asks for a line of text. Resolves to null when cancelled. */
export function askText(opts: {
	title: string;
	message?: string;
	value?: string;
	placeholder?: string;
	confirm?: string;
	validate?: (v: string) => string;
}): Promise<string | null> {
	return new Promise((resolve) => {
		overlay.dialog = {
			kind: "text",
			value: "",
			confirm: "OK",
			...opts,
			resolve,
		};
	});
}

/** Asks a yes/no question. */
export function confirmAction(opts: {
	title: string;
	message?: string;
	confirm?: string;
	danger?: boolean;
}): Promise<boolean> {
	return new Promise((resolve) => {
		overlay.dialog = {
			kind: "confirm",
			confirm: "OK",
			danger: false,
			...opts,
			resolve,
		};
	});
}

export function openMenu(x: number, y: number, items: MenuItem[]) {
	overlay.menu = { x, y, items };
}

export function closeMenu() {
	overlay.menu = null;
}

/**
 * Fixed position for a popup of size (w, h) next to `anchor`: below it if
 * it fits, else above; kept inside the window.
 */
export function placeNear(
	anchor: DOMRect,
	w: number,
	h: number,
	gap = 4,
): { left: number; top: number; maxHeight: number } {
	const vw = window.innerWidth;
	const vh = window.innerHeight;
	const below = vh - anchor.bottom - gap - 8;
	const above = anchor.top - gap - 8;
	const down = h <= below || below >= above;
	const maxHeight = Math.max(120, down ? below : above);
	const top = down
		? anchor.bottom + gap
		: Math.max(8, anchor.top - gap - Math.min(h, maxHeight));
	const left = Math.max(8, Math.min(anchor.left, vw - w - 8));
	return { left, top, maxHeight };
}
