+++
title = "Layers"
description = "How layers are drawn, and the fields every layer type shares."
+++

The design's `layers` array is drawn in order: the first layer is at the bottom, the last on top. Each layer has a type.

| Type | What it is |
| --- | --- |
| [`rect`](@/docs/layer-rect.md) | Rectangle with optional rounded corners, fill and stroke |
| [`ellipse`](@/docs/layer-ellipse.md) | Ellipse filling a box |
| [`polygon`](@/docs/layer-polygon.md) | Closed or open shape through points |
| [`text`](@/docs/layer-text.md) | Text with wrapping, alignment, auto-shrink |
| [`image`](@/docs/layer-image.md) | PNG, JPEG, WebP, GIF, BMP or SVG picture |
| [`qr`](@/docs/layer-qr.md) | QR code made from text |
| [`barcode`](@/docs/layer-barcode.md) | Barcodes and 2D codes (Code 128, EAN, UPC, Code 39, ITF, QR, Data Matrix, Aztec, PDF417) made from text |
| [`group`](@/docs/layer-group.md) | Holds other layers and draws them as one picture |
| [`divider`](@/docs/layer-divider.md) | Draws nothing; organises the layer list in the editor |

## Fields every layer has

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `id` | ident | required | Unique in the whole design (also across groups), error 1108 otherwise |
| `type` | enum | required | One of the types above |
| `note` | text literal | | Comment |
| `tag` | `red`, `orange`, `yellow`, `green`, `teal`, `blue`, `purple`, `pink` or `gray` | | Colour of the layer's row in the builder's layer list; never drawn, not inherited through `extends`. Also on groups and dividers |
| `visible` | bool | `true` | `false`: the layer is not drawn, but its values can still be referenced |
| `opacity` | number | `1` | 0 to 1, multiplies the layer's alpha |
| `rotate` | number | `0` | Degrees clockwise, taken modulo 360. See below |
| `anchor` | enum | `top-left` | Which point of the layer `at` or `box.x`/`box.y` refers to. See below |
| `repeat` | object | | Draw once per iteration, see [Repeat](@/docs/repeat.md) |
| `extends` | ident | | Start from another layer's fields, see [Extends](@/docs/extends.md) |
| `effects` | array | `[]` | See [Effects](@/docs/effects.md) |
| `clip_to` | layer id | | Draw only inside the shape of a `rect`, `ellipse` or `polygon` layer. Also on groups. See below |

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

`anchor` can also be an expression that gives one of these names, evaluated for every card: `"anchor": "side == 'left' ? 'top-left' : 'top-right'"`, or a text param's name. A string that is one of the names is that name; a single word that is neither a name nor a param or constant is error 1103 (with a suggestion), and an expression that gives a word that is not an anchor is error 3109 at render time. The same goes for `align` on text layers, `fit` and `smoothing` on image layers, `level`, `style` and `eye` on QR layers, and `align` and `cross` of a group's `layout`.

Examples: a rect with `"anchor": "center"` and `box.x`, `box.y` set to `50%` is centred on the canvas; a text layer with `"anchor": "baseline"` sits on the line given by `at.y`.

`polygon` and `group` layers have no `anchor`. (Polygon points are absolute coordinates; groups have no position of their own, but can move what is inside with [`translate`](@/docs/layer-group.md#translate).) A polygon drawn from a preset [`shape`](@/docs/layer-polygon.md#preset-shapes) uses `box` and `anchor` like a rect.

## `rotate`

Degrees, clockwise. The value is taken modulo 360, and `@layer.rotate` reads back that reduced value: `rotate: 370` reads as `10`.

- Box layers (`rect`, `ellipse`, `image`) turn around their anchor point (`box.x`, `box.y`).
- Text turns around `at`.
- Polygons turn around the centre of their bounds.
- Groups turn around the centre of the group's bounds.

Rotation is applied when the layer is composited, after [effects](@/docs/effects.md). `@layer.bounds.*` always describes the **unrotated** layer so references and alignment stay simple; `@layer.rotate` gives the angle. A rotated label can follow another layer with `"rotate": "@ribbon.rotate"`.

## `clip_to`

`"clip_to": "frame"` hides every part of the layer outside the shape of the layer `frame`: a `rect` (with its `radius`), an `ellipse` (an `arc` clips to its slice) or a `polygon` (its points or preset `shape`; an open polygon clips to the area its points enclose). On a group it clips everything inside the group as one picture. Content inside the shape is drawn as without the clip; the edge is anti-aliased like a filled shape.

```json
{ "id": "frame", "type": "rect", "box": { "x": 40, "y": 40, "w": 670, "h": 480 }, "radius": 24, "visible": false },
{ "id": "art", "type": "image", "src": "art/{art}", "box": { "x": 0, "y": 0, "w": 750, "h": 560 }, "fit": "cover", "clip_to": "frame" }
```

- The shape is where the shape layer is: its final box, anchor, `translate` of the groups around it and its own `rotate`. Its fill, stroke, opacity and effects do not matter. It is drawn as usual unless it has `"visible": false`, which is the usual way to keep a clip shape out of the picture; a hidden shape still clips.
- The clip works on the finished layer (after its effects, opacity and rotation), in the coordinates the layer is drawn in. For a layer inside a rotated or cropped group, the group's rotation and effects turn and cut the clip along with the layer.
- `@layer.bounds.*` of the clipped layer or group stay unclipped.
- The shape cannot be the layer itself, nor a `text`, `image`, `qr`, `barcode` or `group` (error 1116). An unknown id is error 3002, with a suggestion.
- The shape must be drawn once: a repeated shape layer is error 3005. A shape inside a [repeated group](@/docs/layer-group.md#repeat) works for layers in the same group, which take the shape of their own iteration; for a layer outside that group it is error 3005.
- `clip_to` is inherited through `extends`, and follows the component's id prefix when it names a layer of the same [component](@/docs/layer-group.md#including-a-component-twice-id-prefix).
- In SVG files and vector PDFs the clip is a real clip path (`<clipPath>`, and `W n` in the PDF), so it stays sharp at any zoom.

Why a reference and not a shape written into the layer: the shape layer already has every option a shape needs (boxes, anchors, expressions, radius, preset shapes, point runs, rotation), it can be placed and checked on the canvas in the editor like any layer, and one shape can clip several layers. An image's own [`radius` and `clip`](@/docs/layer-image.md#rounded-corners-and-clipping) remain for the simple case of one picture.

## Drawing order and references

Drawing order is always array order. References between layers may point forward or backward: the core orders evaluation by dependency and reports cycles as error 3004. A layer inside a group is an ordinary layer and can be referenced from anywhere; inside a [repeated group](@/docs/layer-group.md#repeat) pick the iteration with `@layer[n]`.

## Coordinates

Floating-point pixels, origin top-left, y pointing down. Numbers can use units (`50%`, `10vw`, `20vh`), see [Literals and units](@/docs/expressions-literals-and-units.md).

## Layer limits

At most 500 visible layers are drawn per card after [repeat](@/docs/repeat.md) expansion (error 5001); hidden layers do not count. See [the layer limit](@/docs/repeat.md#the-layer-limit).
