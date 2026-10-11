+++
title = "Layer: polygon"
+++

A shape through a list of points: a triangle, a banner, a star, or an open line with arrowheads. Or a preset shape (star, polygon, arrow, ...) in a box.

```json
{
  "id": "corner",
  "type": "polygon",
  "points": [[0, 0], [180, 0], [0, 190]],
  "fill": "with_alpha(accent, 0.8)",
  "stroke": { "color": "#FFFFFF", "width": 2 }
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `points` | array of `[x, y]` | required unless `shape` is given | Absolute canvas coordinates (inside a [translated group](@/docs/layer-group.md#translate), relative to its origin) |
| `closed` | bool literal | `true` | `false` draws an open line through the points |
| `fill` | color | `#FFFFFFFF` | Ignored when the polygon is not closed |
| `stroke` | `{ color, width, dash, arrow }` | none | `color` defaults to opaque black, `width` to `1`. `dash` as for [rect](@/docs/layer-rect.md#stroke). `arrow`: see below |
| `shape` | `{ type, count, inner }` | none | A preset shape that fills `box`, instead of `points` |
| `box` | `{ x, y, w, h }` | | Only with `shape` |

- A closed polygon needs at least 3 points, an open one at least 2 (error 1109). A point that is not a two-item array is error 1103.
- Points are **absolute canvas coordinates**; `anchor` does not apply to them.
- Every coordinate is an [expression](@/docs/expressions.md), so polygons scale with params: `[["10%", 0], ["canvas.w - 40", "height * 0.5"]]`. The first value of a point is a horizontal coordinate (`%` is a percentage of the canvas width), the second a vertical one.
- `closed` must be the literal `true` or `false`, not an expression.
- `rotate` turns a polygon with points around the centre of its bounds.
- Stroke joins and line ends are round.

## Arrowheads

On an open polygon, `"arrow": "end"` (or `"start"`, `"both"`) in the stroke draws arrowheads at the ends, 4 times the stroke width long. The line stops at the base of the head. Arrowheads only apply to polygons (error 1101 elsewhere).

```json
{ "id": "link", "type": "polygon", "closed": false,
  "points": [["@a.bounds.cx", "@a.bounds.bottom"], ["@b.bounds.cx", "@b.bounds.top"]],
  "stroke": { "color": "#D1495B", "width": 4, "dash": [10, 6], "arrow": "end" } }
```

## Preset shapes

With `shape` instead of `points`, the polygon fills `box`, and `anchor` and `rotate` work like on a [rect](@/docs/layer-rect.md) (it turns around the anchor point). A polygon needs exactly one of `points` and `shape` (error 1111).

```json
{ "id": "star", "type": "polygon", "shape": { "type": "star" }, "box": { "x": 340, "y": 160, "w": 80, "h": 80 }, "fill": "#FFD166" }
```

| `type` | Shape | `count` | `inner` |
| --- | --- | --- | --- |
| `star` | A star, point up | points, default 5 | inner radius as a fraction of the outer, default 0.5 |
| `polygon` | A regular polygon, corner up | sides, default 6 | |
| `triangle` | Point up | | |
| `diamond` | | | |
| `arrow` | A block arrow pointing right (turn it with `rotate`) | | shaft thickness, default 0.45 |
| `cross` | A plus sign | | arm thickness, default 0.34 |
| `chevron` | Pointing right | | thickness, default 0.4 |

`count` and `inner` are numbers or expressions.

In the editor you drag polygon points on the canvas; a shape polygon gets box handles instead, and the inspector switches between points and a shape. See [Builder: Canvas](@/docs/builder-canvas.md).
