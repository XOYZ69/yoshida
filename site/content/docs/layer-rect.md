+++
title = "Layer: rect"
description = "Rectangles with rounded corners, fill and stroke."
+++

A rectangle, optionally with rounded corners, a fill and a stroke.

```json
{
  "id": "panel",
  "type": "rect",
  "box": { "x": "5%", "y": "5%", "w": "90%", "h": "90%" },
  "fill": "mix(accent, #FFFFFF, 0.85)",
  "radius": 40,
  "stroke": { "color": "accent", "width": 8 }
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `box` | `{ x, y, w, h }`, all number | required | Position and size. `x`, `y` refer to the point chosen by `anchor` |
| `fill` | color | `#FFFFFFFF` (opaque white) | Use `#00000000` for no fill |
| `radius` | number | `0` | Corner radius in pixels |
| `stroke` | `{ color, width, dash }` | none | Outline |

## Box

`x` and `w` can use `%` of the canvas width; `y` and `h` use `%` of the canvas height. `vw` and `vh` work in any number field. See [Literals and units](@/docs/expressions-literals-and-units.md).

A negative width or height is error 3101 at render time.

## Gradient

`gradient` fills the layer with colors blended across its bounds, instead of `fill`. It works on rect, ellipse and polygon layers.

```json
"gradient": { "type": "linear", "angle": 90, "stops": ["#2B5876", "#4E4376"] }
```

```json
"gradient": { "type": "radial", "stops": [{ "color": "#FFE29F", "at": 0 }, { "color": "#FFE29F00", "at": 1 }] }
```

| Field | Default | Meaning |
|---|---|---|
| `type` | `linear` | `linear` or `radial` |
| `angle` | `0` | Linear only: degrees clockwise, 0 runs left to right, 90 top to bottom. The gradient reaches the corners, as in CSS |
| `stops` | — | Two or more colors, or `{ "color", "at" }` with `at` from 0 to 1. Stops without `at` are spread evenly |

A radial gradient runs from the centre of the bounds to their corners. Colors and positions may be expressions. The stroke is drawn over the gradient. In SVG and vector PDF output a gradient layer stays pixels (at the `--scale` resolution).

## Stroke

The stroke is drawn **centred on the edge**, so half of the width lies outside the box. `color` defaults to opaque black and `width` to `1` when left out.

A rect with only a stroke (an outline frame) needs `"fill": "#00000000"`.

`dash` makes the stroke dashed: lengths in pixels, on, off, on, off... (`[12, 6]`; a list with an odd number of values repeats twice). Dash ends are round, and dashes follow rounded corners. Every value can be an expression.

```json
"stroke": { "color": "#2B2B3A", "width": 4, "dash": [14, 8] }
```

## Reading values

Other layers can read `@panel.box.x`, `@panel.box.w`, `@panel.fill`, `@panel.radius`, `@panel.stroke.width`, `@panel.stroke.color` and the resolved bounds `@panel.bounds.left` ... `@panel.bounds.cy`. See [Names and references](@/docs/expressions-names-and-references.md).
