+++
title = "Layer: group"
+++

A group holds other layers and draws them as one picture, so they can be organised, moved, hidden, faded and rotated together.

```json
{
  "id": "badge",
  "type": "group",
  "opacity": 0.9,
  "rotate": -8,
  "layers": [
    { "id": "badge_bg", "type": "ellipse", "box": { "x": 820, "y": 60, "w": 120, "h": 120 }, "fill": "accent" },
    { "id": "badge_text", "type": "text", "text": "{level}", "anchor": "center",
      "at": { "x": "@badge_bg.bounds.cx", "y": "@badge_bg.bounds.cy" } }
  ]
}
```

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `layers` | array of layers | required (error 1102) | Drawn in array order inside the group, first is bottom. Groups may contain groups |
| `translate` | `{ x, y }`, number | `{ 0, 0 }` | The group's origin: everything inside moves by it, and coordinates inside are relative to it. See [translate](#translate) |
| `repeat` | object | none | Draw the layers inside once per iteration, as one unit. See [repeat](#repeat) |
| `id`, `note`, `visible`, `opacity`, `rotate`, `effects` | | | As in [Layers](@/docs/layers.md), applied to the group's picture (per iteration in a repeated group) |

## How it works

- A group has **no position or size of its own**. `@group.bounds.*` is the union of the bounds of its visible layers, including all [repeat](@/docs/repeat.md) iterations. An empty or fully hidden group has zero bounds at the origin. `@group.opacity`, `@group.visible` and `@group.rotate` can be referenced too.
- The layers inside are drawn into a separate picture. Then the group's [effects](@/docs/effects.md) (relative to the group's bounds, so `fade` and `crop` work on the group's edges), `opacity` and `rotate` (around the centre of the bounds) are applied, and the picture is composited at the group's place in the stack.
- Layers inside a group are ordinary layers: ids are unique across the whole design (error 1108), they can be referenced from anywhere, and they can use `repeat` and `extends`.
- A group itself cannot have `anchor` or `extends` (error 1101). Nesting deeper than 16 levels is error 5001.
- A hidden layer (`visible: false`) is not drawn, but it can still be referenced with `@` and used as an [`extends`](@/docs/extends.md) base, inside a group or not. A hidden group's layers can be referenced too.
- Diagnostics inside a group use nested pointers, such as `/layers/2/layers/0/box/x`.

## Translate

Without `translate`, coordinates inside a group are canvas coordinates. With it, they are **relative to the group's origin**:

```json
{ "id": "badge", "type": "group", "translate": { "x": 820, "y": 60 }, "layers": [
  { "id": "badge_bg", "type": "ellipse", "box": { "x": 0, "y": 0, "w": 120, "h": 120 }, "fill": "accent" },
  { "id": "badge_text", "type": "text", "text": "{level}", "anchor": "center",
    "at": { "x": "@badge_bg.bounds.cx", "y": "@badge_bg.bounds.cy" } }
] }
```

- Moving the badge means changing only the translate. Translates of nested groups add up.
- `@layer` positions (`bounds.*`, `box.x`, `box.y`, `at.x`, `at.y`) are given **in the frame of the layer that reads them**: inside the group, `@badge_bg.bounds.cx` is 60; outside it, 880. So references work the same everywhere.
- `%`, `vw` and `vh` stay relative to the canvas size.
- `translate.x` and `translate.y` are expressions; they can use params, constants, the group's own loop names and layers outside the group. A layer inside the group is a cycle (error 3004).

## Repeat

A group can [repeat](@/docs/repeat.md): the layers inside are drawn once per iteration, as one unit, and every layer inside can use the group's loop names. With `translate`, each iteration gets its own origin:

```json
{ "id": "tile", "type": "group",
  "repeat": { "each": "tiles", "item": "t", "index": "i" },
  "translate": { "x": "tile_x(i)", "y": "tile_y(i)" },
  "layers": [
    { "id": "tile_bg", "type": "rect", "box": { "x": 6, "y": 6, "w": 158, "h": 158 }, "fill": "t.kind == 'safe' ? c_safe : c_plain" },
    { "id": "tile_text", "type": "text", "text": "{t.text}", "anchor": "center",
      "at": { "x": "@tile_bg.bounds.cx", "y": "@tile_bg.bounds.cy + 30" } }
  ] }
```

- References between layers inside the same repeated group mean **the same iteration**: in the example, each text is centred on its own tile.
- From outside, pick an iteration with an index: `@tile_bg[3].bounds.cx` is the background of tile 4, `@tile[3].bounds` the whole tile. See [Repeat](@/docs/repeat.md#reading-one-iteration).
- `visible`, `opacity` and `rotate` of the group can use the loop names, so single iterations can be hidden.
- The group counts as one layer per visible iteration toward the [layer limit](@/docs/repeat.md#the-layer-limit), plus its visible layers.

The [board game example](@/docs/example-board-game.md) draws its 40 tiles this way.

## Moving a group

In the editor, moving a group with a `translate` changes the translate; moving a group without one moves every layer in it. Group a set of layers with <kbd>Ctrl</kbd>+<kbd>G</kbd> (the group takes the place of the topmost selected layer and keeps the order) and ungroup with <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd>. See [Builder: Layers](@/docs/builder-layers.md).

## Known limits

In the editor, layers inside a *rotated* group show unrotated selection boxes on the canvas, and groups have no resize handles (their size comes from their layers). Layers inside a repeated group are outlined once per iteration. See [Known Gaps](@/docs/known-gaps.md).

![Layers in a group in the editor](../images/builder-v03-light-group.png)
