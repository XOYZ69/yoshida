+++
title = "Extends"
description = "Start a layer from another layer and change only what differs."
+++

`"extends": "other_id"` starts from another layer's fields and applies this layer's own fields on top. It is how you avoid copy-pasting a layer that differs in a few values.

```json
{ "id": "label", "type": "text", "at": { "x": 40, "y": 100 }, "size": 28, "color": "#333333", "text": "Speed" },
{ "id": "label2", "type": "text", "extends": "label", "at": { "y": 146 }, "text": "Power" }
```

`label2` is drawn at `x: 40, y: 146` with the same size and color.

## A hidden base layer

The base does not have to be drawn. A layer with `"visible": false` is not drawn, but other layers can extend it and reference it with `@`, so it works as a template:

```json
{ "id": "tile_base", "type": "rect", "visible": false,
  "box": { "x": "65 + i * 170", "y": 65, "w": 160, "h": 160 },
  "repeat": { "each": "tiles", "item": "t", "index": "i" } },
{ "id": "tile_shadow", "type": "rect", "extends": "tile_base", "visible": true,
  "box": { "x": "71 + i * 170", "y": 71 }, "fill": "#00000033" },
{ "id": "tile_bg", "type": "rect", "extends": "tile_base", "visible": true, "fill": "c_plain" }
```

Both tiles inherit `box` and `repeat` from `tile_base` and set `visible` back to `true`. Hidden layers do not count toward the [500-layer limit](@/docs/repeat.md#the-layer-limit). The [board game example](@/docs/example-board-game.md) is built this way, and so are the pips of the [poker example](@/docs/example-poker.md): one hidden `pip` layer, extended by the side pips, the middle pips and the ace.

A turned copy is a common use: the [poker example](@/docs/example-poker.md)'s bottom-right index extends the top-left one and only sets a mirrored `at` and `"rotate": 180`.

## Merging rules

- Objects (`box`, `at`, `stroke`, `repeat`, `arc`, `shape`) merge **key by key**: giving only `at.y` keeps the base layer's `at.x`.
- Everything else is **replaced**: giving `effects` replaces the whole effects list.
- `id`, `extends` and `note` are never inherited.
- Both layers must have the same `type`. A mismatch (including a group, or a divider as the base) is error 1112.
- Chains are allowed (`c` extends `b` extends `a`). A cycle is error 3004.
- An unknown base id is error 3002 with a "did you mean" hint.
- A group cannot use `extends` (error 1101), but the layers inside a group can.

## In the editor

Fields a layer inherits through `extends` are marked with an arrow (↳) in the inspector. Editing one adds an override to this layer. Renaming the base layer updates every `extends` that points to it. See [Builder: Inspector](@/docs/builder-inspector.md).
