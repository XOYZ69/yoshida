+++
title = "Layer: qr"
description = "QR codes made on the fly from text, for example a link on each card."
+++

A QR code that holds text. The text is a [template](@/docs/expressions-templates.md), so every card can carry its own link, id or message, and nothing has to be prepared as an image.

```json
{
  "id": "recipe_qr",
  "type": "qr",
  "text": "{recipe_url}",
  "box": { "x": "canvas.w - 160", "y": 40, "w": 120, "h": 120 },
  "color": "#24121C",
  "fill": "#FFFFFF",
  "level": "medium"
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `text` | text ([template](@/docs/expressions-templates.md)) | required | What the code holds. Read as bytes (UTF-8), so umlauts and symbols work |
| `box` | `{ x, y, w, h }`, all number | required | Position and size. `x`, `y` refer to the point chosen by `anchor`. The code is a square that fits the smaller of `w` and `h` |
| `color` | color | `#000000FF` | The dark modules |
| `fill` | color | `#FFFFFFFF` | The area behind the code, quiet zone included. `#00000000` for none |
| `margin` | number | `4` | Quiet zone in modules, 0 to 16. Scanners want 4 (the standard); with a light background around the code 1 or 2 usually works too |
| `level` | enum | `medium` | Error correction: `low` (7 %), `medium` (15 %), `quartile` (25 %) or `high` (30 %). A higher level survives more damage but makes a bigger, denser code |

## Size

The code is as small as the text allows (versions 1 to 40, 21 to 177 modules per side), so a short text gives a coarse, easy to scan code and a long text a fine one. Each module is a **whole number of pixels** wide (rounded down) so that its edges stay sharp, and the code is centred in the box. That means the layer can be a little smaller than `box`, and `@code.bounds.*` is the symbol that is really drawn, quiet zone included.

Keep a module at least 2 px wide on screen and about 0.25 mm in print, or scanners struggle (3 px per module at 300 dpi). A link of 40 characters at level `medium` is 29 modules, 37 with the default quiet zone, so it wants a box of at least 75 x 75 px on screen and about 9 mm in print. Short links scan better than long ones.

## Limits

- One code holds at most 2953 bytes at level `low`, 2331 at `medium`, 1663 at `quartile` and 1273 at `high`. More is error 3108.
- A module narrower than one pixel is warning 3204.
- The text is always encoded as bytes. There is no numeric or alphanumeric mode, so a code of digits only is a little larger than it could be.

## Exports

In PNG files the modules are exact pixels. In [SVG files and vector PDFs](@/docs/command-line.md#svg) the code stays a vector, one path of squares. With `--scale` the module size is rounded at the export resolution, so the code stays sharp there too. [Effects](@/docs/effects.md), `rotate` and `opacity` work as on any layer; a rotated code is drawn smoothly and still scans.

## Reading values

`@code.bounds.*` and `@code.box.*`, `@code.text`, `@code.color`, `@code.fill`. See [Names and references](@/docs/expressions-names-and-references.md).

## Example: a link from a card

```json
"params": { "recipe_url": { "type": "text", "default": "https://example.com/" } }
```

```json
{ "id": "qr_tile", "type": "rect", "box": { "x": 600, "y": 800, "w": 130, "h": 130 }, "fill": "#FFFFFF", "radius": 14 },
{ "id": "qr", "type": "qr", "text": "{recipe_url}", "fill": "#00000000", "margin": 1,
  "anchor": "center", "box": { "x": 665, "y": 865, "w": 118, "h": 118 } }
```

A rounded tile behind the code, with the code's own fill switched off and a quiet zone of one module, so the tile is what the scanner sees around it.
