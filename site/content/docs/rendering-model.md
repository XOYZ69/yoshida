+++
title = "Rendering Model"
description = "How a card becomes pixels, step by step."
+++

How a card becomes pixels.

## Order of work

1. **Load.** The manifest, every design and every card file are parsed. Expressions are parsed and type-checked. All problems are collected, not just the first.
2. **Check.** If there is any **error**, rendering does not start. Warnings and hints never block rendering.
3. **Evaluate.** For each card, the core evaluates the layers lazily by dependency: `@layer` references are resolved in the order they need, and cycles are caught.
4. **Draw.** Layers are drawn in array order.

## Pixels

- Coordinates are floating-point pixels, origin top-left, y down. Shapes and text are anti-aliased.
- Each layer is rendered to its own pixels, [effects](@/docs/effects.md) are applied, opacity is multiplied in, rotation is applied, then it is composited onto the canvas with **source-over** on premultiplied 16-bit sRGB values. There is no linearization in format version 1.
- Anything outside the canvas is clipped silently. A layer entirely outside the canvas is hint 3202.
- Groups render their layers into a separate picture first, then apply the group's effects, opacity and rotation, then composite it. See [Layer: group](@/docs/layer-group.md).

## Output

PNG, RGBA, **8-bit or 16-bit** per channel (`--16bit`), with the resolution when `canvas.dpi` is set. Files are named `<set>/<card id>.png`. Or one PDF per set, one page per card, with the bleed and trim boxes from `canvas.bleed`, and optionally crop marks. See [Command Line](@/docs/command-line.md#pdf).

## Text

Text uses the layer's font; characters it has no glyph for come from the bundled default font, then from the bundled symbol font. An outline (`stroke`) is drawn under the letters from a distance field of each glyph. See [Layer: text](@/docs/layer-text.md).

## Determinism

The same project, card data and render clock (`render.now` with the `utc_offset`, or `render.date`) always produce the same pixels, in every build (WebAssembly in the browser, the CLI, the server). The core has no clock, network or file access of its own; each front end gives it a virtual file system and the render clock. Seeded random functions are pure. The browser export, the server zip and the CLI output were compared byte for byte on the examples.

## What happens to a bad card

Errors found at load time stop the render. Errors that depend on a card's values (a missing key, an index out of range, division by zero, a missing image, too many layers) are reported for that card; `yoshida check` finds them by evaluating every card without drawing. When rendering, the failing layer is skipped and the rest of the card is still drawn and written, marked as written with errors; the other cards are rendered normally by the CLI. The server answers 422 with the diagnostics and no zip if any card has an error.

## Limits

Canvas up to 10000 x 10000 pixels, 500 visible layers per card after repeat expansion, 1000 iterations per repeat, images up to 50 megapixels, 10000 cards per set. See [Limits and Versioning](@/docs/limits-and-versioning.md).
