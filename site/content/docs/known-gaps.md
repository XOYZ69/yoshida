+++
title = "Known Gaps"
description = "What does not work yet."
+++

What does not work yet, so you do not have to find out the hard way.

## Format

- **Rich text** (mixed fonts, sizes or colors inside one text layer) is not in the format.
- **Shared design parts** (`include`) are not in the format, and `extends` only reaches layers of the same design. Designs that share a look repeat those layers, as the four designs of the [poker example](@/docs/example-poker.md) do.
- **Per-card layer overrides** are not in the format; cards change params only. (Single items of a default list can be changed, see [Params](@/docs/params.md#changing-single-items-of-the-default).)
- The **layer limit** is fixed at 500 visible layers per card; it cannot be raised. `yoshida check` finds cards over it. See [Repeat](@/docs/repeat.md#the-layer-limit).
- A layer inside **two nested repeats** cannot be referenced from outside both (error 3005); an index picks one level only. See [Repeat](@/docs/repeat.md#reading-one-iteration).
- **Functions** cannot read layers or loop names (pass them as arguments) and cannot call themselves. See [Constants and functions](@/docs/expressions-constants-and-functions.md).
- A typo in a word compared with an **enum** value inside an expression (`t.kind == 'saef'`) is not reported; card values of enum params and enum item fields are checked.
- **Percentages are always of the canvas**: `%`, `vw` and `vh` inside a group moved with `translate` still refer to the canvas, so a group cannot be laid out in its own percentages.
- Functions **cannot build lists**. There are no `map`, `filter` or `sort`; lists come only from list params and `repeat`. See [List functions](@/docs/expressions-functions-lists.md).

## Drawing

- **Emoji** and color fonts are not drawn; characters without a glyph in the font, the default font and the bundled symbol font are boxes (warning 4003).
- Polygon strokes always have **round joins and ends**; there are no miter or bevel joins and no square caps.
- Text outlines cannot be dashed.

## Output

- PDF pages hold the card as an 8-bit image (no 16-bit, no vector output). Crop marks are drawn in a white margin; there are no color bars or registration marks.

## Dates and times

- **Named time zones** such as `Europe/Berlin` are not supported. A project has one fixed offset from UTC (`utc_offset`, in hours), and it does not follow daylight saving time. See [Time zone](@/docs/project-layout-and-manifest.md#time-zone).
- **Month and day names are English only**: `MMMM`, `MMM`, `dddd` and `ddd` in `date_fmt` write English names, and there is no locale setting.

## Wishes

Not planned or implemented yet:

- A configurable layer limit.
- Checking words compared with enum values in expressions.
- Emoji and color font support.
- Miter and bevel line joins.
- Rich text and shared design parts.
- Named time zones and month and day names in other languages.

These are candidates for a later 1.x or 2 format. See [Limits and Versioning](@/docs/limits-and-versioning.md).

## Images

- In the browser, `https://` images only load when the remote server sends CORS headers.
- The server does not download images at all; upload them with the project.
- The CLI downloads images; behind a TLS-intercepting proxy the download can fail. Use `--offline` and local files then.

## Builder

- Layers inside a **rotated group** show unrotated selection boxes on the canvas.
- **Groups have no resize handles**; their size comes from their layers.
- **Repeated layers** are moved as a whole: the offset applies to every iteration. A repeated group with a `translate` is moved by changing the translate.
- **Polygons** rotate around their bounds centre, which moves when points change.

See [Builder: Canvas](@/docs/builder-canvas.md).

## Distribution

- The **macOS binaries are unsigned**. `start.sh` clears the quarantine flag; if that is not possible, Gatekeeper may ask once (right-click, Open).
- On **Windows**, only x86_64 is prebuilt. `zig build -Dtarget=aarch64-windows` works from source.

## CLI

- `yoshida migrate` is not implemented (there is only format 1).
- There is no option to pick a design for CSV card data on the command line; list the file in a set of `yoshida.json`. See [Project Layout and Manifest](@/docs/project-layout-and-manifest.md).
