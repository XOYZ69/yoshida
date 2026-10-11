// Colour scheme preference. The project website uses the same storage key
// and the same data-theme attribute on <html>, so a choice made on the site
// carries over to the editor and back (both are served from one origin).
// index.html applies the stored choice before the app loads, so the page
// never flashes in the wrong scheme.

export type ThemePref = "system" | "light" | "dark";

export const THEME_KEY = "yoshida.theme";

export function loadTheme(): ThemePref {
	try {
		const v = localStorage.getItem(THEME_KEY);
		return v === "light" || v === "dark" ? v : "system";
	} catch {
		return "system";
	}
}

/** Applies a preference to the page and remembers it. */
export function setTheme(pref: ThemePref): void {
	applyTheme(pref);
	try {
		if (pref === "system") localStorage.removeItem(THEME_KEY);
		else localStorage.setItem(THEME_KEY, pref);
	} catch {
		// Storage blocked (private mode): the choice lasts for this page only.
	}
}

export function applyTheme(pref: ThemePref): void {
	const root = document.documentElement;
	if (pref === "system") delete root.dataset.theme;
	else root.dataset.theme = pref;
}

/** System, then light, then dark, then back to system. */
export function nextTheme(pref: ThemePref): ThemePref {
	return pref === "system" ? "light" : pref === "light" ? "dark" : "system";
}
