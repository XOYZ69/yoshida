+++
title = "Effects"
description = "Crop, fade, sharpen, blur and shadow effects applied to a layer's own pixels."
+++

`effects` is an array of operations applied, in order, to a layer's own pixels before the layer is composited onto the canvas. Effects work on every layer type, [groups](@/docs/layer-group.md) included.

```json
"effects": [
  { "type": "fade", "side": "bottom", "length": 120 },
  { "type": "sharpen", "strength": 0.5 }
]
```

| Effect | Fields | Meaning |
| --- | --- | --- |
| `crop` | `side` (`top`, `bottom`, `left`, `right`), `length` (number) | Removes `length` pixels from that side of the layer's pixels. What remains is drawn at the same anchor point |
| `fade` | `side`, `length` | Alpha ramps from opaque to transparent over the last `length` pixels toward `side` |
| `sharpen`, `detail`, `edge_enhance`, `find_edges` | `strength` (number, default `1`) | Convolution filters |
| `blur` | `radius` (number, required) | Softens the layer: its pixels spread about `radius` pixels in every direction. The layer's room grows by that much so the blur is not cut off |
| `shadow` | `x`, `y`, `blur`, `color` (all optional) | A soft shadow of the layer's shape under it, shifted by `x` and `y` pixels (defaults `0` and `4`), softened over `blur` pixels (default `6`) and tinted with `color` (default `#00000080`, black at half opacity) |

- `side` and `length` are required for `crop` and `fade`. Missing ones are error 1102.
- `length` is a number on the matching axis: for `left` and `right` it is horizontal (so `%` means percent of canvas width), for `top` and `bottom` vertical.
- An unknown effect type or `side` is error 1103 (with a hint listing the valid words); an unknown field in an effect is error 1101.
- Effects run before [rotation](@/docs/layers.md#rotate) and before `opacity`.
- On a group, effects are relative to the group's bounds.
- In [SVG files and vector PDFs](@/docs/command-line.md#svg), `crop` and `fade` stay vectors. The convolution filters, `blur` and `shadow` have no vector form: a layer or group with one is embedded as pixels at the export resolution (the export dialog's **Resolution**, `--scale` or `"scale"`; 2x when not given).

## Examples

Fade an image into the card at its bottom edge:

```json
{ "id": "art", "type": "image", "src": "{art}", "box": { "x": 0, "y": 0, "w": 800, "h": 500 },
  "effects": [{ "type": "fade", "side": "bottom", "length": 120 }] }
```

Show only the top 60% of a banner:

```json
"effects": [{ "type": "crop", "side": "bottom", "length": "@banner.box.h * 0.4" }]
```

A soft drop shadow under a panel, in its color at 35 % opacity:

```json
{ "id": "panel", "type": "rect", "box": { "x": 40, "y": 40, "w": 300, "h": 200 }, "radius": 16, "fill": "#FFFFFF",
  "effects": [{ "type": "shadow", "x": 0, "y": 8, "blur": 16, "color": "#00000059" }] }
```

Blur a background picture:

```json
"effects": [{ "type": "blur", "radius": 6 }]
```

`radius` and `blur` are in canvas pixels, so a render at another `--scale` looks the same. Effects run in order: a `shadow` after a `blur` casts the blurred shape, and a `blur` after a `shadow` softens both. On a [group](@/docs/layer-group.md) the shadow is of everything inside, and the group's bounds grow so the shadow is not cut off.
