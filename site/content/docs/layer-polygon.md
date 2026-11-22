+++
title = "Layer: polygon"
description = "Triangles, banners, stars, open lines with arrowheads and preset shapes."
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
| `points` | array of `[x, y]` and [point runs](#points-from-a-list-or-a-count) | required unless `shape` is given | Absolute canvas coordinates (inside a [translated group](@/docs/layer-group.md#translate), relative to its origin) |
| `closed` | bool literal | `true` | `false` draws an open line through the points |
| `fill` | color | `#FFFFFFFF` | Ignored when the polygon is not closed |
| `stroke` | `{ color, width, dash, arrow }` | none | `color` defaults to opaque black, `width` to `1`. `dash` as for [rect](@/docs/layer-rect.md#stroke). `arrow`: see below |
| `shape` | `{ type, count, inner }` | none | A preset shape that fills `box`, instead of `points` |
| `box` | `{ x, y, w, h }` | | Only with `shape` |

- A closed polygon needs at least 3 points, an open one at least 2 (error 1109 when the points are all written out, 3110 when point runs give too few at render time). An entry that is neither a two-item array nor a point run is error 1103.
- Points are **absolute canvas coordinates**; `anchor` does not apply to them.
- Every coordinate is an [expression](@/docs/expressions.md), so polygons scale with params: `[["10%", 0], ["canvas.w - 40", "height * 0.5"]]`. The first value of a point is a horizontal coordinate (`%` is a percentage of the canvas width), the second a vertical one.
- `closed` must be the literal `true` or `false`, not an expression.
- `rotate` turns a polygon with points around the centre of its bounds.
- Stroke joins and line ends are round.

## Points from a list or a count

An entry of `points` may also be an object, a *point run*. It makes one point per iteration, the way [`repeat`](@/docs/repeat.md) makes one layer per iteration, so a polygon can follow a list in the card data or a count, and fixed points and runs can be mixed (the points keep the order of the entries).

| Field | Kind | Meaning |
| --- | --- | --- |
| `count` | number or expression | Number of points. A list gives its length |
| `each` | expression giving a [list](@/docs/params.md) | One point per item |
| `index` | name | Name of the iteration number, from 0. Default `i` |
| `item` | name | With `each`: name of the current item, read as `name.field`. Without it, use `list[i].field` |
| `x`, `y` | number or expression | The point. They see `index` and `item`; `%` and the other [units](@/docs/expressions-literals-and-units.md) work as in a fixed point |

A run needs exactly one of `count` and `each` (error 1111), and `x` and `y` (error 1102). When `points` is a single run, the brackets can be left out.

```json
{
  "params": { "scores": { "type": "list", "item": { "label": "text", "value": "number" }, "default": [] } },
  "layers": [
    { "id": "chart", "type": "polygon", "closed": false,
      "points": [{ "each": "scores", "item": "s", "x": "40 + i * 50", "y": "300 - s.value * 2" }],
      "stroke": { "color": "#D1495B", "width": 3 } }
  ]
}
```

A star of `n` points from a count (angles are in radians):

```json
{ "id": "star", "type": "polygon", "fill": "#FFD166",
  "points": [{ "count": "n * 2", "index": "k",
    "x": "100 + (k % 2 == 0 ? 80 : 35) * sin(k * pi / n)",
    "y": "100 - (k % 2 == 0 ? 80 : 35) * cos(k * pi / n)" }] }
```

- A run gives at most as many points as a `repeat` gives iterations (error 5001 above the limit, `YOSHIDA_MAX_REPEAT`).
- A run's `index` hides a name from the layer's own `repeat` that is the same (both default to `i`); give one of them another name.
- In the editor the points of a run are drawn but cannot be dragged; edit the fields in the inspector.

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

## Gradient

`gradient` fills the layer with blended colors instead of `fill`, as on a [rect](@/docs/layer-rect.md#gradient).
