// Proxy renders: the editor previews and thumbnails render with fewer pixels
// than the card (render `scale`), matched to what the screen shows. Exports
// always render at full size.

export type PreviewQuality = "auto" | "fast" | "full";

export const qualityLabels: Record<PreviewQuality, string> = {
	auto: "Sharp on screen",
	fast: "Fast (half of the screen)",
	full: "Full size",
};

/** Smallest proxy scale: below this the preview is a blur. */
const MIN_SCALE = 1 / 64;

/**
 * Rounds `k` up to the next step of half an octave (1, 0.71, 0.5, 0.35, ...),
 * so small zoom changes do not ask for a new render.
 */
export function stepUp(k: number): number {
	if (!(k > 0) || k >= 1) return 1;
	const steps = Math.floor(-Math.log2(k) * 2);
	return Math.max(MIN_SCALE, Math.min(1, 2 ** (-steps / 2)));
}

/**
 * Render scale for the editor canvas: `shown` is screen (CSS) pixels per
 * canvas pixel, `dpr` the device pixel ratio.
 */
export function previewScale(
	q: PreviewQuality,
	shown: number,
	dpr: number,
): number {
	if (q === "full" || !(shown > 0)) return 1;
	const k = shown * (dpr || 1);
	return stepUp(q === "fast" ? k / 2 : k);
}

/** Render scale for a thumbnail whose longer side is `px` device pixels. */
export function thumbScale(canvas: { w: number; h: number }, px: number): number {
	const side = Math.max(canvas.w, canvas.h);
	return side > 0 ? stepUp(px / side) : 1;
}
