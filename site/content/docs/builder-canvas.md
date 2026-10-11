+++
title = "Builder: Canvas"
+++

The canvas shows the card as it will be rendered (the real core, running in your browser), with an overlay for selection and editing. The overlay uses the resolved bounds the core returns for every layer and every repeat iteration (with rotation, pivot, polygon points and the text size after auto-shrink).

## Selecting

- **Click** a layer to select it. A click on a layer inside a group selects the **group**; **double-click** selects the layer itself, and once you are inside a group, clicks stay at that level.
- <kbd>Shift</kbd>/<kbd>Ctrl</kbd>/<kbd>Cmd</kbd>+click adds or removes a layer from the selection.
- **Drag on empty space** selects by rectangle (marquee).
- <kbd>Alt</kbd>+click picks the layer underneath.
- Locked layers (lock icon in the [layer tree](@/docs/builder-layers.md)) ignore canvas clicks. Locking exists in the editor only; it is not stored in the design.

## Moving, resizing, rotating

- **Drag** to move; all selected layers move together.
- **Handles** resize: box layers on all sides, text layers left and right (which sets `wrap`).
- The **round handle** above the box rotates. Hold <kbd>Shift</kbd> for 15° steps.
- Drag **polygon points** to reshape a polygon.
- Resizing a rotated layer works in the layer's own (rotated) frame; snapping is off while a rotated layer is resized.

Moves and resizes keep how the value was written (a number stays a number, a percentage stays a percentage, an expression gets an offset appended). See [Builder: how edits are written](@/docs/builder.md#how-edits-are-written).

## Snapping

The canvas snaps to the canvas edges and centre and to other layers. Hold <kbd>Ctrl</kbd> to place freely, without snapping.

## Zoom and pan

- <kbd>Ctrl</kbd>+wheel (or a pinch on a touchpad) zooms **toward the pointer**: the point of the card under the mouse stays where it is.
- The corner buttons zoom out (−) and in (+) around the middle of the canvas panel; the percentage sets 100 %.
- **Fit** fits the card to the panel and centres it. It stays fitted when the panel or window changes size, until you zoom or pan.
- Hold the **middle mouse button** and drag to move the view. It works anywhere over the canvas, also over layers, and does not select or move anything; the cursor shows a grabbing hand while you drag.
- The **wheel** moves the view up and down (<kbd>Shift</kbd>+wheel: sideways) once the card is zoomed; a fitted card does not move.
- A strip of the card always stays in view; **Fit** brings it back.

Zoom goes from 5 % to 800 %. The picture size and render time are shown under the canvas.

## Right-click

Right-click on a layer opens the [layer menu](@/docs/builder-layers.md#layer-menu). Right-click on empty space adds a layer, an empty group or a divider.

## Limits

- Layers inside a rotated group show unrotated selection boxes.
- Groups have no resize handles.
- A repeated layer is moved as a whole: the offset applies to every iteration.
- Polygons rotate around their bounds centre, which moves when points change.

See [Known Gaps](@/docs/known-gaps.md).
