+++
title = "Repeat"
description = "Draw a layer once per item, for example a row of stars or one line per list item."
+++

`repeat` draws a layer once per iteration. Inside the layer's fields the loop names are in scope.

```json
"repeat": { "count": "level", "index": "i" }
"repeat": { "each": "ingredients", "item": "ing", "index": "i" }
```

| Field | Kind | Meaning |
| --- | --- | --- |
| `count` | number or list | Number of iterations. Rounded down; negative is 0. A list counts its items: `"count": "stats"` is the same as `len(stats)` |
| `each` | expression yielding a list | Iterate over the list |
| `index` | ident | Name for the 0-based index. Default `i` |
| `item` | ident | Name for the current list item. Only with `each` |

Exactly one of `count` and `each` must be given (error 1111). `item` without `each` is error 1101.

## Example: a row of stars

```json
{
  "id": "stars",
  "type": "image",
  "anchor": "center",
  "src": "assets/star.png",
  "box": {
    "x": "50% + (i - (level - 1) / 2) * 56",
    "y": "@title.bounds.bottom + 50",
    "w": 48,
    "h": "auto"
  },
  "repeat": { "count": "level", "index": "i" }
}
```

A card with `level` 3 gets three stars, centred as a row.

## Example: one line per list item

```json
{
  "id": "stat_name",
  "type": "text",
  "anchor": "left",
  "at": { "x": "15%", "y": "@stats_row.bounds.top + 33 + i * 46" },
  "repeat": { "each": "stats", "item": "s", "index": "i" },
  "text": "{s.name}"
}
```

`s.name` reads a field of the current item, see [Params](@/docs/params.md#lists).

## Rules

- The `repeat` expressions themselves see params, [constants](@/docs/expressions-constants-and-functions.md) and the loop names of the [repeated groups](@/docs/layer-group.md#repeat) around the layer, not the layer's own loop names.
- Loop names follow the same rule as [param names](@/docs/params.md#names), `[a-z_][a-z0-9_]*`, and must not be reserved words (error 1103): `"index": "tile"` and `"index": "row_2"` work, `"index": "Tile"` does not.
- More than **1000 iterations** is error 5001.
- A card may draw at most **500 layers** after expansion. See [the layer limit](#the-layer-limit) below.
- A repeated layer has no single position, so `@layer.field` is error 3005. Read one iteration with an index, see [reading one iteration](#reading-one-iteration); `@group.bounds.*` of a [group](@/docs/layer-group.md) around the repeated layers covers all iterations.
- A [group](@/docs/layer-group.md#repeat) can repeat too: everything inside is drawn once per iteration, as one unit, with its own origin (`translate`).
- Each iteration of a text layer with auto-shrink (`max_width`, `max_height`) gets its own size, unless the layer has a [`shrink_group`](@/docs/layer-text.md#auto-shrink), which gives every iteration the smallest size.
- [`extends`](@/docs/extends.md) merges `repeat` key by key like other objects.
- In the editor, a repeated layer is moved as a whole: the offset applies to every iteration.

## Reading one iteration

`@layer[n].field` reads iteration `n` (0-based) of a repeated layer, or of the [repeated group](@/docs/layer-group.md#repeat) the layer is in:

```json
"y": "@stat_name[0].bounds.top"
"points": [["@tile_bg[i].bounds.cx", "@tile_bg[i].bounds.bottom"], ["@tile_bg[t.n - 1].bounds.cx", "@tile_bg[t.n - 1].bounds.bottom"]]
```

- `n` is any number expression; it is rounded down. An iteration that does not exist is error 3102 when the card is rendered.
- An iteration may read the iterations **before** it of its own layer, for stacking: `"y": "i == 0 ? 100 : @row[i - 1].bounds.bottom + 8"`. Reading a later one is a cycle (error 3004).
- A layer that is not repeated has no index (error 3003). Inside the same repeated group, references without an index mean the same iteration. A layer inside two nested repeats the reader is not in cannot be referenced (error 3005).

## The layer limit

A card may draw at most 500 layers. The count is taken while the card is drawn:

- Every **visible** iteration of a repeated layer counts as one layer. Iterations whose `visible` is false do not count, so one repeated layer per variant with `"visible": "t.kind == 'safe'"` costs only the iterations that are actually drawn.
- A visible group counts as one, plus its visible layers. The layers of a hidden group do not count.
- Hidden layers do not count. Layers that are visible but lie outside the canvas do count.

Because it depends on card data, the limit is evaluated **per card**: `yoshida check` evaluates every card (without drawing) and reports it for the cards that go over, and so does **Check all** in the editor. The message gives the total and the layers that use most of it:

```txt
error[5001]: card bigshown: 631 visible layers after repeat, the limit is 500; most: 'many' 600, 'few' 30, 'last' 1
```

When rendering, the layers up to the limit are still drawn and the card is written, marked `with 1 error(s): parts of the card are missing`, and the run ends with exit status 1. See [Command Line](@/docs/command-line.md#errors-while-rendering).

To stay under the limit, keep variants as hidden iterations and count roughly *visible layers per item x items*. The [board game example](@/docs/example-board-game.md) draws 6 to 8 per tile (the repeated tile group, its icon group and their visible layers), about 330 per card.
