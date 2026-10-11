+++
title = "Layer: ellipse"
description = "Ellipses and circles that fill their box."
+++

An ellipse that fills its box. A circle is an ellipse with equal `w` and `h`.

```json
{
  "id": "badge",
  "type": "ellipse",
  "anchor": "center",
  "box": { "x": 900, "y": 130, "w": 110, "h": 110 },
  "fill": "foil ? #F5C542 : accent",
  "stroke": { "color": "#FFFFFF", "width": 6 }
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `box` | `{ x, y, w, h }`, all number | required | The ellipse fills this box |
| `fill` | color | `#FFFFFFFF` | |
| `stroke` | `{ color, width, dash }` | none | Drawn centred on the edge. `color` defaults to opaque black, `width` to `1`. `dash` as for [rect](@/docs/layer-rect.md#stroke) |
| `arc` | `{ start, end, pie }` | none | Draw only part of the ellipse, see below |

It has the same fields as [`rect`](@/docs/layer-rect.md) except `radius`. The box rules (units, `anchor`, negative sizes) are the same.

Use `@badge.bounds.cx` and `@badge.bounds.cy` to place something at the centre, as in the [group](@/docs/layer-group.md) example.

## Arcs and pie slices

`arc` draws the part of the ellipse from `start` to `end`, in degrees **clockwise from the top** (12 o'clock). Both are numbers or expressions; the defaults are 0 and 360.

```json
{ "id": "timer", "type": "ellipse", "box": { "x": 320, "y": 20, "w": 100, "h": 100 },
  "fill": "#D1495B", "arc": { "start": 0, "end": "360 * progress" }, "stroke": { "color": "#2B2B3A", "width": 2 } }
{ "id": "curve", "type": "ellipse", "box": { "x": 440, "y": 20, "w": 100, "h": 100 },
  "arc": { "start": -90, "end": 90, "pie": false }, "stroke": { "color": "#2B2B3A", "width": 6, "dash": [10, 6] } }
```

- `"pie": true` (the default) fills a slice through the centre, and the stroke goes around the slice.
- `"pie": false` draws only the curve with the stroke; the fill is not used.
- The layer's bounds stay the whole box.
