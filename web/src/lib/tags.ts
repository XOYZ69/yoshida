// Colour tags: a layer's "tag" tints its row in the layer list, to find
// layers that belong together. Tags are never drawn on the card.

export const layerTags = [
	"red",
	"orange",
	"yellow",
	"green",
	"teal",
	"blue",
	"purple",
	"pink",
	"gray",
] as const;
export type LayerTag = (typeof layerTags)[number];

export const tagLabels: Record<LayerTag, string> = {
	red: "Red",
	orange: "Orange",
	yellow: "Yellow",
	green: "Green",
	teal: "Teal",
	blue: "Blue",
	purple: "Purple",
	pink: "Pink",
	gray: "Gray",
};

export const isTag = (v: unknown): v is LayerTag =>
	typeof v === "string" && (layerTags as readonly string[]).includes(v);

/** The CSS colour of a tag (it follows the light or dark theme). */
export const tagColor = (tag: LayerTag) => `var(--tag-${tag})`;
