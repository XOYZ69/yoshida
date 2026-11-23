+++
title = "Layer: image"
description = "Pictures from the project or the web, with fill, contain and cover fitting."
+++

A picture from a file in the project or from the web.

```json
{
  "id": "art",
  "type": "image",
  "src": "{art}",
  "anchor": "top",
  "box": { "x": "50%", "y": "@panel.bounds.top + 60", "w": "80%", "h": 420 },
  "fit": "cover",
  "effects": [{ "type": "fade", "side": "bottom", "length": 120 }]
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `src` | path ([template](@/docs/expressions-templates.md)) | required | Project path or `https://` URL |
| `box` | `{ x, y, w, h }`, number | required | Position and size |
| `fit` | enum | `fill` | `fill` stretches, `contain` letterboxes inside the box, `cover` crops to fill the box |
| `smoothing` | enum | `bilinear` | `nearest` or `bilinear` |

## Supported formats

PNG, JPEG, WebP (lossy and lossless), GIF (first frame), BMP and SVG. Images can be at most 50 megapixels.

SVG files work too. An SVG is drawn at the size it is used at (for `--scale` and PDF too), so it stays sharp; for `"auto"` box sizes and `fit` its own width and height (or viewBox) give the proportions. In SVG and vector PDF output an SVG image is embedded as pixels at the `--scale` resolution.

### What an SVG file may contain

| Feature | Support |
| --- | --- |
| Paths, basic shapes, fills, strokes, transforms, opacity | Yes |
| Linear and radial gradients | Yes, also with coordinates as fractions of the shape (`x2="1"`) and attributes inherited through `href` |
| `<pattern>` fills and strokes | Yes: `patternUnits`, `patternContentUnits`, `patternTransform`, `viewBox` and patterns that refer to another with `href`; the tile is clipped to its size |
| `<text>` and `<tspan>` | Yes, as one line per position: `x`, `y`, `dx`, `dy`, `text-anchor`, `font-size`, `font-weight`, `letter-spacing`, `xml:space`, from attributes, `style` and simple `.class` rules |
| Filters, masks, clip paths, `<use>`, embedded images, text on a path | No; convert such files to PNG first |

### Fonts for SVG text

An SVG file names fonts by family (`font-family="Chip Sans, sans-serif"`), a design by the names in its [`fonts`](@/docs/designs.md). The text is drawn with the first family of the list that a declared font is named after; only letters and digits count and case does not, so `Chip Sans` finds a font declared as `chip-sans` or `ChipSans`. Any other family is drawn with the bundled default font (Lato), with the bundled symbol font for characters it lacks.

For bold or italic text a font declared as the family name plus `bold`, `italic` or `bold italic` (`chip-sans-bold`) is used. Without one, bold is the regular font with a thin outline in the fill color, and italic is drawn upright.

```json
"fonts": { "chip-sans": "assets/fonts/ChipSans.ttf", "chip-sans-bold": "assets/fonts/ChipSans-Bold.ttf" }
```

Fonts installed on the computer are never used, so a card looks the same everywhere. If the text must match another program exactly, convert it to paths there.

## Box with `"auto"`

`w` or `h` (not both) may be the string `"auto"` to keep the image's aspect ratio. Both `"auto"` is error 1110.

```json
"box": { "x": 24, "y": 40, "w": 48, "h": "auto" }
```

`"auto"` only applies to image layers.

## `src` is a template

Because `src` is a template, params can pick the file:

```json
"src": "{art}"
"src": "assets/images/attributes/attribute-{attribute}.png"
```

The result must be a project path or an `https://` URL. If the path is built from a param, the editor cannot rewrite it when you rename a file; the Files tab lists such templates first. See [Builder: Files](@/docs/builder-files.md).

## Missing or unreadable images

- Not found or unreachable: error 4001.
- Found but cannot be decoded: error 4002.

Both stop a normal render. The editor preview (and `yoshida render --preview`) draws a checkered placeholder and continues, so you can keep designing while an image is missing.

A hidden image (`"visible": false`, or an expression that is false for the card) is not loaded, so its file may be missing. With `"optional": true` a missing file (or an empty `src`) hides the layer instead of being an error; other layers can read `@art.visible` to react to it.

## Rounded corners and clipping

`"radius": 24` clips the image to its box with rounded corners. `"clip"` clips it to a polygon, given as points like a [polygon layer](@/docs/layer-polygon.md): `"clip": [[0, 0], [400, 0], [400, 300], [0, 360]]`. In SVG and vector PDF output a clipped image stays pixels (at the `--scale` resolution). To clip with a real vector clip path, or to clip other layers and groups, use [`clip_to`](@/docs/layers.md#clip-to) with a shape layer.

## Images from the web

`https://` (and `http://`) images are fetched by the front end, never by the core:

| Front end | Behaviour |
| --- | --- |
| CLI | Downloads each URL once per run (`--offline` turns this off) |
| Editor | The browser downloads it; the remote site must send CORS headers |
| Server | Does not download anything; upload the image with the project (an unreachable URL is error 4001) |

For anything you must be able to reproduce, copy the image into the project instead. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md).

## Using an image in expressions

An `image` [param](@/docs/params.md) can be passed to `avg_color(art)` to get the average color of its opaque pixels, for example to tint a frame: `"fill": "mix(avg_color(art), #000000, 0.5)"`. See [Functions](@/docs/expressions-functions.md).

## Reading values

`@art.src` (text), `@art.box.x` ... `@art.box.h`, and the resolved bounds `@art.bounds.*` (after `auto` sizing and anchoring). See [Names and references](@/docs/expressions-names-and-references.md).
