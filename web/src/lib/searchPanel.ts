// Search panel for the editor (Ctrl+F): a compact two-row panel in the app's
// style. The search state and commands are still @codemirror/search's; only
// the panel DOM and its keys are ours. Styles live in Editor.svelte (`ys-` classes).

import {
	closeSearchPanel,
	findNext,
	findPrevious,
	getSearchQuery,
	replaceAll,
	replaceNext,
	search,
	SearchQuery,
	searchPanelOpen,
	setSearchQuery,
} from "@codemirror/search";
import type { EditorState, Extension } from "@codemirror/state";
import { EditorView, keymap, type Panel, type ViewUpdate } from "@codemirror/view";

type Option = "caseSensitive" | "wholeWord" | "regexp";

// Match counts above this are shown as "1000+".
const MATCH_CAP = 1000;

// Keyed by KeyboardEvent.code so Alt+letter works on every keyboard layout.
const OPTION_BY_CODE: Record<string, Option> = {
	KeyC: "caseSensitive",
	KeyW: "wholeWord",
	KeyR: "regexp",
};

function svg(body: string): string {
	return `<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
}

const icons = {
	prev: svg('<path d="M10 3.5 5.5 8l4.5 4.5"/>'),
	next: svg('<path d="M6 3.5 10.5 8 6 12.5"/>'),
	close: svg('<path d="M4 4l8 8M12 4l-8 8"/>'),
	replace: svg('<path d="M3 3v4.5A2.5 2.5 0 0 0 5.5 10H13"/><path d="M10.5 7.5 13 10l-2.5 2.5"/>'),
	replaceAll: svg(
		'<path d="M2.5 1.5h11"/><path d="M3 4.5v3A2.5 2.5 0 0 0 5.5 10H13"/><path d="M10.5 7.5 13 10l-2.5 2.5"/>',
	),
};

function elt<K extends keyof HTMLElementTagNameMap>(tag: K, cls: string): HTMLElementTagNameMap[K] {
	const node = document.createElement(tag);
	node.className = cls;
	return node;
}

function textInput(placeholder: string): HTMLInputElement {
	const input = elt("input", "ys-input");
	input.placeholder = placeholder;
	input.setAttribute("aria-label", placeholder);
	input.spellcheck = false;
	return input;
}

function iconButton(cls: string, title: string, icon: string, onclick: () => void): HTMLButtonElement {
	const btn = elt("button", `ys-btn ${cls}`);
	btn.type = "button";
	btn.title = title;
	btn.setAttribute("aria-label", title);
	btn.innerHTML = icon;
	// Keep focus in the field when a button is pressed.
	btn.addEventListener("mousedown", (e) => e.preventDefault());
	btn.addEventListener("click", onclick);
	return btn;
}

function optionButton(view: EditorView, option: Option, label: string, title: string): HTMLButtonElement {
	const btn = elt("button", option === "wholeWord" ? "ys-toggle ys-toggle-word" : "ys-toggle");
	btn.type = "button";
	btn.textContent = label;
	btn.title = title;
	btn.setAttribute("aria-label", title);
	btn.setAttribute("aria-pressed", "false");
	btn.addEventListener("mousedown", (e) => e.preventDefault());
	btn.addEventListener("click", () => setOption(view, option));
	return btn;
}

function setOption(view: EditorView, option: Option): void {
	const q = getSearchQuery(view.state);
	const spec = {
		search: q.search,
		caseSensitive: q.caseSensitive,
		literal: q.literal,
		regexp: q.regexp,
		replace: q.replace,
		wholeWord: q.wholeWord,
	};
	spec[option] = !spec[option];
	view.dispatch({ effects: setSearchQuery.of(new SearchQuery(spec)) });
}

function toggleOption(view: EditorView, option: Option): boolean {
	if (!searchPanelOpen(view.state)) return false;
	setOption(view, option);
	return true;
}

class SearchPanel implements Panel {
	readonly dom: HTMLElement;
	private view: EditorView;
	private query: SearchQuery;
	private findField: HTMLElement;
	private findInput: HTMLInputElement;
	private replaceInput: HTMLInputElement | null = null;
	private toggles: Record<Option, HTMLButtonElement>;
	private counter: HTMLElement;

	constructor(view: EditorView) {
		this.view = view;
		this.query = getSearchQuery(view.state);

		this.findInput = textInput("Find");
		this.findInput.addEventListener("input", () => this.commit());
		this.toggles = {
			caseSensitive: optionButton(view, "caseSensitive", "Aa", "Match case (Alt+C)"),
			wholeWord: optionButton(view, "wholeWord", "ab", "Match whole word (Alt+W)"),
			regexp: optionButton(view, "regexp", ".*", "Use regular expression (Alt+R)"),
		};
		const toggles = elt("div", "ys-toggles");
		toggles.append(this.toggles.caseSensitive, this.toggles.wholeWord, this.toggles.regexp);
		this.findField = elt("div", "ys-field");
		this.findField.append(this.findInput, toggles);

		this.counter = elt("span", "ys-count");
		const findRow = elt("div", "ys-row");
		findRow.append(
			this.findField,
			iconButton("ys-prev", "Previous match (Shift+Enter)", icons.prev, () => findPrevious(view)),
			iconButton("ys-next", "Next match (Enter)", icons.next, () => findNext(view)),
			this.counter,
			iconButton("ys-close", "Close (Escape)", icons.close, () => this.close()),
		);

		this.dom = elt("div", "cm-search ys-search");
		this.dom.append(findRow);
		this.dom.addEventListener("keydown", (e) => this.keydown(e));

		if (!view.state.readOnly) {
			this.replaceInput = textInput("Replace");
			this.replaceInput.addEventListener("input", () => this.commit());
			const replaceField = elt("div", "ys-field");
			replaceField.append(this.replaceInput);
			const replaceRow = elt("div", "ys-row");
			replaceRow.append(
				replaceField,
				iconButton("ys-replace", "Replace next (Enter in replace field)", icons.replace, () =>
					replaceNext(view),
				),
				iconButton("ys-replace-all", "Replace all (Ctrl+Alt+Enter)", icons.replaceAll, () =>
					replaceAll(view),
				),
			);
			this.dom.append(replaceRow);
		}

		this.sync(view.state);
	}

	mount() {
		this.findInput.select();
	}

	update(u: ViewUpdate) {
		if (u.docChanged || u.selectionSet || !getSearchQuery(u.state).eq(this.query)) this.sync(u.state);
	}

	private commit() {
		const old = this.query;
		const query = new SearchQuery({
			search: this.findInput.value,
			caseSensitive: old.caseSensitive,
			literal: old.literal,
			regexp: old.regexp,
			wholeWord: old.wholeWord,
			replace: this.replaceInput ? this.replaceInput.value : old.replace,
		});
		if (!query.eq(old)) this.view.dispatch({ effects: setSearchQuery.of(query) });
	}

	private keydown(e: KeyboardEvent) {
		const option = OPTION_BY_CODE[e.code];
		if (e.key === "Escape") {
			e.preventDefault();
			e.stopPropagation();
			this.close();
		} else if (e.altKey && !e.ctrlKey && !e.metaKey && option) {
			e.preventDefault();
			setOption(this.view, option);
		} else if (e.key === "Enter" && e.target instanceof HTMLInputElement) {
			e.preventDefault();
			if (e.ctrlKey && e.altKey) replaceAll(this.view);
			else if (e.target === this.replaceInput) replaceNext(this.view);
			else if (e.shiftKey) findPrevious(this.view);
			else findNext(this.view);
		}
	}

	private close() {
		closeSearchPanel(this.view);
		this.view.focus();
	}

	// Bring the fields, toggles, invalid marker and counter in line with the state's query.
	private sync(state: EditorState) {
		const q = getSearchQuery(state);
		this.query = q;
		if (this.findInput.value !== q.search) this.findInput.value = q.search;
		if (this.replaceInput && this.replaceInput.value !== q.replace) this.replaceInput.value = q.replace;
		this.toggles.caseSensitive.setAttribute("aria-pressed", String(q.caseSensitive));
		this.toggles.wholeWord.setAttribute("aria-pressed", String(q.wholeWord));
		this.toggles.regexp.setAttribute("aria-pressed", String(q.regexp));
		this.findField.classList.toggle("ys-invalid", q.search !== "" && !q.valid);
		this.counter.textContent = this.matchLabel(state, q);
	}

	// "current/total" for the main selection, or "" when there is nothing to count.
	private matchLabel(state: EditorState, q: SearchQuery): string {
		if (!q.search || !q.valid) return "";
		const sel = state.selection.main;
		const cursor = q.getCursor(state);
		let total = 0;
		let current = 0;
		for (let r = cursor.next(); !r.done; r = cursor.next()) {
			total++;
			if (!current && r.value.from <= sel.from && sel.to <= r.value.to) current = total;
			if (total === MATCH_CAP) return `${MATCH_CAP}+`;
		}
		return `${current}/${total}`;
	}
}

export function searchPanel(): Extension {
	return [
		search({ createPanel: (view) => new SearchPanel(view) }),
		keymap.of([
			{ key: "Alt-c", run: (view) => toggleOption(view, "caseSensitive") },
			{ key: "Alt-w", run: (view) => toggleOption(view, "wholeWord") },
			{ key: "Alt-r", run: (view) => toggleOption(view, "regexp") },
		]),
	];
}
