+++
title = "Effects"
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

- `side` and `length` are required for `crop` and `fade`. Missing ones are error 1102.
- `length` is a number on the matching axis: for `left` and `right` it is horizontal (so `%` means percent of canvas width), for `top` and `bottom` vertical.
- An unknown effect type or `side` is error 1103 (with a hint listing the valid words); an unknown field in an effect is error 1101.
- Effects run before [rotation](@/docs/layers.md#rotate) and before `opacity`.
- On a group, effects are relative to the group's bounds.

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
