<script lang="ts">
// Cycles the colour scheme: follow the system, light, dark.
import { onMount } from "svelte";
import { applyTheme, loadTheme, nextTheme, setTheme, THEME_KEY, type ThemePref } from "../theme";

const labels: Record<ThemePref, string> = {
	system: "Theme: follows your system",
	light: "Theme: light",
	dark: "Theme: dark",
};

let pref: ThemePref = $state(loadTheme());

function toggle() {
	pref = nextTheme(pref);
	setTheme(pref);
}

onMount(() => {
	// Keep open tabs (editor and site) in step when the choice changes in another one.
	const onStorage = (e: StorageEvent) => {
		if (e.key !== THEME_KEY && e.key !== null) return;
		pref = loadTheme();
		applyTheme(pref);
	};
	window.addEventListener("storage", onStorage);
	return () => window.removeEventListener("storage", onStorage);
});
</script>

<button class="theme" onclick={toggle} title="{labels[pref]} (click to change)" aria-label={labels[pref]}>
  <svg viewBox="0 0 16 16" aria-hidden="true">
    {#if pref === "light"}
      <circle cx="8" cy="8" r="3" fill="none" stroke="currentColor" stroke-width="1.4" />
      <path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.4 3.4l1.06 1.06M11.54 11.54l1.06 1.06M3.4 12.6l1.06-1.06M11.54 4.46l1.06-1.06" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
    {:else if pref === "dark"}
      <path d="M13 9.5A5.5 5.5 0 0 1 6.5 3a5.5 5.5 0 1 0 6.5 6.5Z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" />
    {:else}
      <circle cx="8" cy="8" r="5.5" fill="none" stroke="currentColor" stroke-width="1.4" />
      <path d="M8 2.5a5.5 5.5 0 0 1 0 11Z" fill="currentColor" />
    {/if}
  </svg>
</button>

<style>
  .theme {
    flex: none;
    display: inline-grid;
    place-items: center;
    padding: 4px 7px;
  }
  svg {
    width: 15px;
    height: 15px;
    display: block;
  }
</style>
