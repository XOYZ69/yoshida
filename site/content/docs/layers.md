+++
title = "Layers"
+++

The design's `layers` array is drawn in order: the first layer is at the bottom, the last on top. Each layer has a type.

| Type | What it is |
| --- | --- |
| [`rect`](@/docs/layer-rect.md) | Rectangle with optional rounded corners, fill and stroke |
| [`ellipse`](@/docs/layer-ellipse.md) | Ellipse filling a box |
| [`polygon`](@/docs/layer-polygon.md) | Closed or open shape through points |
| [`text`](@/docs/layer-text.md) | Text with wrapping, alignment, auto-shrink |
| [`image`](@/docs/layer-image.md) | PNG, JPEG, WebP, GIF or BMP picture |
| [`group`](@/docs/layer-group.md) | Holds other layers and draws them as one picture |
| [`divider`](@/docs/layer-divider.md) | Draws nothing; organises the layer list in the editor |

## Fields every layer has

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `id` | ident | required | Unique in the whole design (also across groups), error 1108 otherwise |
| `type` | enum | required | One of the types above |
| `note` | text literal | | Comment |
| `visible` | bool | `true` | `false`: the layer is not drawn, but its values can still be referenced |
| `opacity` | number | `1` | 0 to 1, multiplies the layer's alpha |
| `rotate` | number | `0` | Degrees clockwise, taken modulo 360. See below |
| `anchor` | enum | `top-left` | Which point of the layer `at` or `box.x`/`box.y` refers to. See below |
| `repeat` | object | | Draw once per iteration, see [Repeat](@/docs/repeat.md) |
| `extends` | ident | | Start from another layer's fields, see [Extends](@/docs/extends.md) |
| `effects` | array | `[]` | See [Effects](@/docs/effects.md) |

Unknown fields are error 1101, with a "did you mean" hint when a known field is one edit away.

Each of `visible`, `opacity` and `rotate` accepts a literal or an [expression](@/docs/expressions.md), so they can depend on params: `"visible": "foil"`, `"opacity": "foil ? 1 : 0.4"`.

## `id`

An identifier: lowercase letters, digits and underscores, not starting with a digit. Layers are referenced from other layers as `@id` (see [Names and references](@/docs/expressions-names-and-references.md)). Renaming a layer in the editor updates every reference.

## `anchor`

`anchor` says which point of the layer the position refers to.

```txt
top-left      top      top-right
left        center     right
bottom-left  bottom    bottom-right
```

Text layers also allow `baseline-left`, `baseline` and `baseline-right`, which use the first line's baseline. A baseline anchor on any other type is error 1103.

Examples: a rect with `"anchor": "center"` and `box.x`, `box.y` set to `50%` is centred on the canvas; a text layer with `"anchor": "baseline"` sits on the line given by `at.y`.

`polygon` and `group` layers have no `anchor`. (Polygon points are absolute coordinates; groups have no position of their own, but can move what is inside with [`translate`](@/docs/layer-group.md#translate).) A polygon drawn from a preset [`shape`](@/docs/layer-polygon.md#preset-shapes) uses `box` and `anchor` like a rect.

## `rotate`

Degrees, clockwise.

- Box layers (`rect`, `ellipse`, `image`) turn around their anchor point (`box.x`, `box.y`).
- Text turns around `at`.
- Polygons turn around the centre of their bounds.
- Groups turn around the centre of the group's bounds.

Rotation is applied when the layer is composited, after [effects](@/docs/effects.md). `@layer.bounds.*` always describes the **unrotated** layer so references and alignment stay simple; `@layer.rotate` gives the angle. A rotated label can follow another layer with `"rotate": "@ribbon.rotate"`.

## Drawing order and references

Drawing order is always array order. References between layers may point forward or backward: the core orders evaluation by dependency and reports cycles as error 3004. A layer inside a group is an ordinary layer and can be referenced from anywhere; inside a [repeated group](@/docs/layer-group.md#repeat) pick the iteration with `@layer[n]`.

## Coordinates

Floating-point pixels, origin top-left, y pointing down. Numbers can use units (`50%`, `10vw`, `20vh`), see [Literals and units](@/docs/expressions-literals-and-units.md).

## Layer limits

At most 500 visible layers are drawn per card after [repeat](@/docs/repeat.md) expansion (error 5001); hidden layers do not count. See [the layer limit](@/docs/repeat.md#the-layer-limit).
