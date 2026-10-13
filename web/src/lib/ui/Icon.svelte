<script lang="ts" module>
// Small line icons for buttons and menus, so toolbars do not mix emoji,
// arrows and symbols from different fonts. They follow the text color.
export const icons = {
	upload: "M8 11V3M4.5 6.5 8 3l3.5 3.5M3 13h10",
	download: "M8 3v7.5M4.5 7.5 8 11l3.5-3.5M3 13h10",
	"folder-plus":
		"M2 4.5V12a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H8L6.5 3.5H3a1 1 0 0 0-1 1ZM8 7.5v3.5M6.25 9.25h3.5",
	folder:
		"M2 4.5V12a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V6a1 1 0 0 0-1-1H8L6.5 3.5H3a1 1 0 0 0-1 1Z",
	file: "M9 2.5H4.5a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V6L9 2.5ZM9 2.5V6h3.5",
	files: "M6 2.5h4.5l3 3v6.5H6zM10.5 2.5v3h3M3.5 5v8.5H10",
	copy: "M5.5 5.5h7v7h-7zM3.5 10.5v-7h7",
	up: "M8 13V3M4 7l4-4 4 4",
	down: "M8 3v10M4 9l4 4 4-4",
	trash: "M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.5 8.5h6l.5-8.5M7 7v4M9 7v4",
	plus: "M8 3v10M3 8h10",
	pencil: "M10.5 3 13 5.5 6 12.5H3.5V10Z",
	check: "M3 8.5l3 3 7-7",
	save: "M3 2.5h8l2.5 2.5v8.5h-11zM5.5 2.5v3h4.5v-3M5.5 13.5V9.5h5v4",
	design: "M2.5 2.5h11v11h-11zM2.5 6h11M6 6v7.5",
	image:
		"M2.5 3.5h11v9h-11zM2.5 10.5l3-3 3 3 2-2 3 3M10 6.25a.75.75 0 1 0 1.5 0 .75.75 0 1 0-1.5 0",
	cloud: "M4.5 12.5a3 3 0 0 1-.4-6 4 4 0 0 1 7.7-.9 3.3 3.3 0 0 1-.3 6.9Z",
	undo: "M5.5 4 2.5 7l3 3M3 7h6.5a3.25 3.25 0 0 1 0 6.5H8",
	redo: "M10.5 4l3 3-3 3M13 7H6.5a3.25 3.25 0 0 0 0 6.5H8",
	rect: "M2.5 4h11v8h-11z",
	ellipse:
		"M8 3.5c3 0 5.5 2 5.5 4.5S11 12.5 8 12.5 2.5 10.5 2.5 8 5 3.5 8 3.5Z",
	text: "M3.5 4h9M8 4v9M6.25 13h3.5",
	polygon: "M8 2.75l5.5 9.75h-11z",
	"check-all":
		"M2.5 4.5 4 6l2.5-2.5M2.5 10.5 4 12l2.5-2.5M8.5 5h5M8.5 11h5",
	close: "M4 4l8 8M12 4l-8 8",
	"align-left": "M2.5 2.5v11M5 5h8M5 11h5",
	"align-hcenter": "M8 2.5v11M4 5h8M5.5 11h5",
	"align-right": "M13.5 2.5v11M3 5h8M6 11h5",
	"align-top": "M2.5 2.5h11M5 5v8M11 5v5",
	"align-vcenter": "M2.5 8h11M5 4v8M11 5.5v5",
	"align-bottom": "M2.5 13.5h11M5 3v8M11 6v5",
	"distribute-x": "M2.5 2.5v11M13.5 2.5v11M6.5 5h3v6h-3z",
	"distribute-y": "M2.5 2.5h11M2.5 13.5h11M5 6.5h6v3H5z",
	group: "M2.5 5.5 8 2.5l5.5 3L8 8.5zM2.5 8.5 8 11.5l5.5-3",
	divider: "M2.5 8h3.5M10 8h3.5",
	eye: "M1.5 8s2.3-4 6.5-4 6.5 4 6.5 4-2.3 4-6.5 4S1.5 8 1.5 8ZM6.25 8a1.75 1.75 0 1 0 3.5 0 1.75 1.75 0 1 0-3.5 0",
	"eye-off": "M1.5 8s2.3-4 6.5-4 6.5 4 6.5 4-2.3 4-6.5 4S1.5 8 1.5 8ZM2.5 2.5l11 11",
	lock: "M3.5 7.5h9v6h-9zM5.5 7.5V5.25a2.5 2.5 0 0 1 5 0V7.5",
	unlock: "M3.5 7.5h9v6h-9zM5.5 7.5V5.25a2.5 2.5 0 0 1 4.7-1.2",
	more: "M3.25 8h.01M8 8h.01M12.75 8h.01",
	grip: "M6 4.5h.01M10 4.5h.01M6 8h.01M10 8h.01M6 11.5h.01M10 11.5h.01",
	repeat: "M13 8a5 5 0 1 1-1.5-3.5M13 3v2.5h-2.5",
	effects: "M8 2.5l1.3 3.2 3.2 1.3-3.2 1.3L8 11.5 6.7 8.3 3.5 7l3.2-1.3Z",
	extends: "M4 3v5a2 2 0 0 0 2 2h6M9.5 7.5 12 10l-2.5 2.5",
	table: "M2.5 3.5h11v9h-11zM2.5 6.5h11M6.5 6.5v6M10 6.5v6",
	"folder-open":
		"M2 12.5V4.5a1 1 0 0 1 1-1h3l1.5 1.5H13a1 1 0 0 1 1 1V7.5M2 12.5l1.6-5h10.4l-1.6 5a.5.5 0 0 1-.5.5H2.5a.5.5 0 0 1-.5-.5Z",
	"select-all":
		"M2.5 2.5h2M7 2.5h2M11.5 2.5h2M2.5 13.5h2M7 13.5h2M11.5 13.5h2M2.5 2.5v2M2.5 7v2M2.5 11.5v2M13.5 2.5v2M13.5 7v2M13.5 11.5v2M5.5 5.5h5v5h-5z",
	ungroup: "M2.5 2.5h4.5v4.5h-4.5zM9 9h4.5v4.5H9z",
	"move-out":
		"M7 3.5H3.5a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1H7M6 8h7M10.5 5.5 13 8l-2.5 2.5",
	paste:
		"M5.5 3.5h-1a1 1 0 0 0-1 1V12a1 1 0 0 0 1 1h3.5M10.5 3.5h1a1 1 0 0 1 1 1V7M5.5 2.5h5v2h-5zM11.5 9v4M9.75 11.5l1.75 1.75 1.75-1.75",
	expand: "M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5 9 7M2.5 13.5 7 9",
	alert: "M8 2.75l5.75 10.5H2.25ZM8 6.5v3M8 11.25h.01",
	info: "M8 2.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 1 0 0-11ZM8 7.5v3.5M8 5.25h.01",
	"chevron-right": "M6 3.5 10.5 8 6 12.5",
	"chevron-down": "M3.5 6 8 10.5 12.5 6",
	"chevron-up": "M3.5 10 8 5.5l4.5 4.5",
	clipboard:
		"M5.5 3.5h-1a1 1 0 0 0-1 1v8.5a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V4.5a1 1 0 0 0-1-1h-1M5.5 2.5h5v2h-5z",
	scissors:
		"M4.5 6.5a1.75 1.75 0 1 0 0-3.5 1.75 1.75 0 0 0 0 3.5ZM4.5 9.5a1.75 1.75 0 1 0 0 3.5 1.75 1.75 0 0 0 0-3.5ZM6 5.5 13 12M6 10.5 13 4",
} as const;

export type IconName = keyof typeof icons;

export const isIcon = (s: string | undefined): s is IconName =>
	!!s && s in icons;

/** The icon of each layer kind. The Add bar, the layer list and the menus
 * all take their icon from here. */
const layerIcons: Record<string, IconName> = {
	rect: "rect",
	ellipse: "ellipse",
	polygon: "polygon",
	text: "text",
	image: "image",
	group: "group",
	divider: "divider",
};

/** Undefined for a type the editor does not know. */
export const layerIcon = (type: string): IconName | undefined =>
	layerIcons[type];
</script>

<script lang="ts">
let { name }: { name: IconName } = $props();
</script>

<svg viewBox="0 0 16 16" aria-hidden="true"
  ><path d={icons[name]} fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" /></svg
>

<style>
  svg {
    width: 14px;
    height: 14px;
    display: block;
    margin: 0 auto;
    flex: none;
  }
</style>
