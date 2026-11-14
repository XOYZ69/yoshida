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
| `style` | enum | `square` | Shape of the data modules: `square`, `rounded` or `dots` |
| `eye` | enum | `square` | Shape of the three corner squares: `square`, `rounded` or `circle` |
| `eye_color` | color | same as `color` | Color of the corner squares |
| `logo` | number | `0` | Clears a square in the middle for a logo, as a share of the code's side (0 to 0.5). See [Logo](#logo) |
| `logo_src` | text | none | A picture drawn in the cleared middle: a path with `{...}` placeholders, so a file or an image param (`"{brand}"`). Without `logo` it clears 0.2 of the side. See [Logo](#logo) |

## Size

The code is as small as the text allows (versions 1 to 40, 21 to 177 modules per side), so a short text gives a coarse, easy to scan code and a long text a fine one. Each module is a **whole number of pixels** wide (rounded down) so that its edges stay sharp, and the code is centred in the box. That means the layer can be a little smaller than `box`, and `@code.bounds.*` is the symbol that is really drawn, quiet zone included.

Keep a module at least 2 px wide on screen and at least 0.5 mm in print, or scanners struggle. With a canvas `dpi` set, a module that prints narrower than 0.5 mm is warning 3208. A link of 40 characters at level `medium` is 29 modules, 37 with the default quiet zone, so it wants a box of about 16 mm at 300 dpi. Use the smallest level that does the job: a higher level makes the code denser, so the modules get smaller. Short links scan better than long ones.

## Style

`style`, `eye` and `eye_color` change how the code looks, not what it holds. `rounded` and `dots` draw every data module on its own, `eye` shapes the three corner squares, and `eye_color` gives them a color of their own, for example the accent color of a card while the data stays dark. Scanners read all of them, but the less a code looks like a plain one the more it depends on the scanner, so test a styled code on a phone before printing.

```json
{ "id": "qr", "type": "qr", "text": "{recipe_url}", "box": { "x": 200, "y": 200, "w": 190, "h": 190 },
  "style": "dots", "eye": "rounded", "color": "#24121C", "eye_color": "#C2185B", "margin": 2 }
```

## Logo

`logo_src` draws a picture in the middle of the code. It is a path like an image layer's `src`, so it can be a project file, an SVG, or an image param of the card:

```json
{ "id": "qr", "type": "qr", "text": "{recipe_url}", "level": "high", "logo_src": "{brand_logo}",
  "box": { "x": 200, "y": 200, "w": 190, "h": 190 } }
```

The picture keeps its proportions and sits half a module inside the cleared square. `logo` sets the size of that square (0.2 of the side by default with `logo_src`). A missing file is error 4001.

`logo` alone leaves the middle of the code empty, as an odd number of modules so that it is centred, for any other layer on top, centred on the code:

```json
{ "id": "qr", "type": "qr", "text": "{recipe_url}", "level": "high", "logo": 0.2,
  "box": { "x": 200, "y": 200, "w": 190, "h": 190 } },
{ "id": "mark", "type": "image", "src": "assets/logo.png", "anchor": "center", "fit": "contain",
  "box": { "x": "@qr.bounds.left + @qr.bounds.w / 2", "y": "@qr.bounds.top + @qr.bounds.h / 2",
           "w": "@qr.bounds.w * 0.18", "h": "@qr.bounds.w * 0.18" } }
```

The empty middle is not part of the code any more, so the error correction has to make up for it: use level `high` and keep the middle under 20 % of the code's area (`logo` up to about 0.44). Anything else is warning 3207. The size is a number of modules, so a small code gets a coarser middle than a big one.

## Standards

The layer warns about the usual rules for readable codes, and only warns: it still draws what you asked for.

- Dark modules on a light fill, with a luminance difference of at least 40 %, for `color` and for `eye_color` (scanners find the code by its corner squares, so a pale `eye_color` is the likeliest way to make a code unreadable). A lighter code, or one with less contrast, is warning 3205. A fully transparent `fill` is not checked, because the background is not known.
- A quiet zone of 4 modules. The layer does not check it: on a card the colored area around the code often does the job with `margin` 1 or 2.
- Modules of at least 0.5 mm in print (warning 3208, needs `canvas.dpi`).
- Level `high` with a logo, under 20 % of the area (warning 3207).

Gradients are not supported.

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
