+++
title = "Designs"
description = "A design file: canvas, fonts, params and the layers that are drawn."
+++

A design file (`*.design.json`) describes one card layout: the canvas, the fonts, the parameters a card can set and the layers that are drawn.

```json
{
  "format": 1,
  "name": "Example",
  "canvas": { "width": 1200, "height": 1800, "background": "#00000000" },
  "fonts": { "body": "assets/fonts/Body.ttf" },
  "params": { "title": { "type": "text", "default": "Untitled" } },
  "layers": []
}
```

| Field | Kind | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `format` | `1` | yes | | See [Project Layout and Manifest](@/docs/project-layout-and-manifest.md) |
| `name` | text literal | yes | | Display name |
| `note` | text literal | no | | Comment |
| `canvas.width`, `canvas.height` | number | yes | | Pixels. May use [params](@/docs/params.md), but not `%` units and not layer references |
| `canvas.background` | color | no | `#00000000` | Transparent by default |
| `canvas.dpi` | number | no | none | Print resolution, stored in PNG files and used for the PDF page size. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md#png-files) |
| `canvas.bleed` | number | no | `0` | Pixels on every side that are cut off after printing. Crop marks and the PDF trim box sit this far inside the edge |
| `fonts` | object of name to path or `{ path, note }` | no | `{}` | Font families for text layers |
| `params` | object of name to param | no | `{}` | See [Params](@/docs/params.md) |
| `consts` | object of name to value | no | `{}` | Named values. See [Constants and functions](@/docs/expressions-constants-and-functions.md) |
| `functions` | object of name to function | no | `{}` | Named formulas with arguments. See [Constants and functions](@/docs/expressions-constants-and-functions.md) |
| `layers` | array of layers | yes | | Drawn in array order, **first is bottom**. See [Layers](@/docs/layers.md) |

Unknown top-level fields are error 1101.

The word *kind* (number, bool, color, text, path, enum, ident) says how a JSON value in a field is read. See [Expressions](@/docs/expressions.md#value-kinds).

## Canvas

`width` and `height` are numbers in pixels. Because they are [expressions](@/docs/expressions.md), a design can scale with a param:

```json
"canvas": { "width": "421 * scale", "height": "614 * scale" }
```

The canvas cannot use `%`, `vw` or `vh` (it is being defined, error 3006) and cannot refer to layers. The limit is 10000 x 10000 pixels (error 5001). The background is a color expression; transparent by default.

## Fonts

```json
"fonts": {
  "body": "assets/fonts/Body.ttf",
  "title": "assets/fonts/Title.otf"
}
```

- Names follow the identifier rule `[a-z_][a-z0-9_]*`.
- Values are project paths to TrueType or OpenType files.
- A value can also be an object with a `path` and an optional `note`, for example `"body": { "path": "assets/fonts/Body.ttf", "note": "Body text for rules cards" }`. The note is a comment for editors and does not change the rendering. A missing `path` is error 1102, and any other key is error 1101.
- A font named `default` is built in (Lato, SIL Open Font License). You may override it by declaring `default` yourself.
- A text layer picks a font with `"font": "body"`. A name that is not declared is error 4004.
- A font file that is missing or not a TrueType/OpenType font is warning 4005 and the default font is used for that name.
- Characters the font does not contain are drawn with the bundled default font, and if that has none either, with the bundled symbol font (arrows, shapes, stars, check marks, dice faces, dingbats). Only characters none of them has are drawn as boxes, and warning 4003 says so.

In the editor, the [Fonts window](@/docs/builder-fonts.md) adds entries to `fonts` when you import a font.

See [Layer: text](@/docs/layer-text.md).

## Canvas and card data together

Every card in a set uses the same design. The card supplies values for the design's [params](@/docs/params.md), see [Card Data](@/docs/card-data.md). Everything else (layer positions, colors, text) can be an expression that reads those params.

## Hand-editing tips

- Add `"$schema": "../schema/design.schema.json"` (adjust the path) for autocompletion and validation in editors like VS Code. See [Formatting and Schemas](@/docs/formatting-and-schemas.md).
- Run `yoshida check <project>` after every edit; messages carry file, line, column and a hint. See [Diagnostics](@/docs/diagnostics.md).
- Run `yoshida fmt <project>` before committing so files stay in the canonical layout.
