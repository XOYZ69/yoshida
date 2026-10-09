<script lang="ts">
// Small line icons for icon-only buttons, so toolbars do not mix emoji,
// arrows and symbols from different fonts. They follow the text color.
const paths = {
	upload: "M8 11V3M4.5 6.5 8 3l3.5 3.5M3 13h10",
	"folder-plus":
		"M2 4.5V12a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H8L6.5 3.5H3a1 1 0 0 0-1 1ZM8 7.5v3.5M6.25 9.25h3.5",
	copy: "M5.5 5.5h7v7h-7zM3.5 10.5v-7h7",
	up: "M8 13V3M4 7l4-4 4 4",
	down: "M8 3v10M4 9l4 4 4-4",
	trash: "M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.5 8.5h6l.5-8.5M7 7v4M9 7v4",
} as const;

let { name }: { name: keyof typeof paths } = $props();
</script>

<svg viewBox="0 0 16 16" aria-hidden="true"
  ><path d={paths[name]} fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" /></svg
>

<style>
  svg {
    width: 14px;
    height: 14px;
    display: block;
    margin: 0 auto;
  }
</style>
