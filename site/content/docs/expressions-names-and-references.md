+++
title = "Expressions: Names and References"
description = "Params, layer fields, canvas and card names, and reserved words."
+++

| Name | Type | Meaning |
| --- | --- | --- |
| a param name | the param's type | The card's value, or the default |
| loop names | number / item | From [`repeat`](@/docs/repeat.md): the index, and the current item with `each`; also those of the [repeated groups](@/docs/layer-group.md#repeat) around the layer |
| a constant | the constant's type | From [`consts`](@/docs/expressions-constants-and-functions.md) |
| `canvas.w`, `canvas.h` | number | Canvas size in pixels |
| `pi` | number | The circle constant, 3.14159…. A param or constant named `pi` takes its place |
| `card.id` | text | The card's id |
| `render.index` | number | 0-based position of the card in its set |
| `render.date` | text | ISO date `YYYY-MM-DD` in the project's time zone (`utc_offset`), chosen once by whoever starts the render (`--date` or `--now` on the CLI) |
| `render.time` | text | Time `HH:MM:SS` in the same time zone |
| `render.now` | text | The instant the render starts, in UTC, as `YYYY-MM-DDTHH:MM:SSZ` (`--now` on the CLI); not changed by `utc_offset` |
| `@<layer_id>.<field>` | the field's type | Another layer's evaluated field |
| `@<layer_id>.bounds.<f>` | number | The layer's final pixel bounds |
| `@<layer_id>[n].<field>` | the field's type | Iteration `n` of a repeated layer (or of the repeated group around it) |
| `list[n]`, `item.field` | | Indexing (0-based) and field access |
| `list.Key`, `list["Key"]` | | [Lookup by key](@/docs/expressions-list-lookup.md) |

Reserved words that cannot be used as param, constant, function or loop names: `canvas`, `render`, `card`, `true`, `false`, `and`, `or`, `not`, `in` (error 1106). Built-in function names are not reserved: a param or constant may use one, because a bare name is a value and not a call. A design function with a built-in's name hides the built-in in that design, with warning 1113. See [Functions](@/docs/expressions-functions.md#names-of-functions-and-other-names).

## Layer references

Layer references always start with `@`, so params and layer ids live in separate namespaces: a param `background` and a layer `background` can coexist.

```json
"y": "@art.bounds.bottom + 90"
"w": "@art.bounds.w"
"fill": "@panel.stroke.color"
```

References between layers may point forward or backward. The core orders evaluation by dependency; a cycle is error 3004. Drawing order is always the array order, independent of references.

An unknown layer or field is error 3002 with a "did you mean" hint. A layer that uses [`repeat`](@/docs/repeat.md) has no single position: read one iteration with `@layer[n].field` (without an index it is error 3005), see [Repeat](@/docs/repeat.md#reading-one-iteration). Inside a [repeated group](@/docs/layer-group.md#repeat), references between its layers mean the same iteration. A [divider](@/docs/layer-divider.md) cannot be referenced at all (3002). Other layers inside groups can be referenced from anywhere.

Positions read from another layer (`bounds.*`, `box.x`, `box.y`, `at.x`, `at.y`) are given in the coordinate frame of the reading layer: inside a [translated group](@/docs/layer-group.md#translate) they are relative to its origin.

### Bounds

`@layer.bounds.<f>` is the **final pixel bounds after anchor, size and layout**, always of the *unrotated* layer:

| Field | Meaning |
| --- | --- |
| `left`, `top`, `right`, `bottom` | Edges |
| `w`, `h` | Width and height |
| `cx`, `cy` | Centre |

This is what makes layouts compose: put a text under an image with `"y": "@art.bounds.bottom + 20"`, centre a badge number on its circle with `@badge.bounds.cx` / `@badge.bounds.cy`, size a frame to its content with `@art.bounds.w`. For text, the bounds include the effect of wrapping and auto-shrink. For a [group](@/docs/layer-group.md), the bounds are the union of its visible layers.

### Readable fields

These fields of a layer can be read (when the layer has them):

| Field path | Type |
| --- | --- |
| `bounds.left`, `.top`, `.right`, `.bottom`, `.w`, `.h`, `.cx`, `.cy` | number |
| `box.x`, `box.y`, `box.w`, `box.h` | number |
| `at.x`, `at.y` | number |
| `stroke.width`, `stroke.color` | number, color (zero width / transparent when there is no stroke); also the outline of a text layer |
| `opacity`, `rotate` | number |
| `visible` | bool |
| `fill`, `color` | color |
| `radius`, `size`, `line_spacing`, `wrap`, `max_lines` | number (`wrap` and `max_lines` read 0 when unset) |
| `text`, `src` | text |

`@layer.size` is the font size actually used after auto-shrink. `@layer.rotate` is the angle taken modulo 360 (bounds ignore rotation). A hidden layer (`visible: false`) is not drawn, but its values can still be read.

## Params

A param name used in an expression gives the card's value, or the param's default when the card does not set it. An `enum` param reads as text, an `image` param as an image (usable in `src` templates and in `avg_color`), a `list` as a list.

## Lists and items

`ingredients[0]` is the first item (an index out of range is error 3102). `ing.name` reads a field of an item, for example the loop item in `repeat.each`. `len(list)` gives the number of items. Items can also be found by key: [List lookup by key](@/docs/expressions-list-lookup.md).

## Card and render values

- `card.id`: the card's id as text (`001`, or whatever the card file says).
- `render.index`: 0 for the first card of the set, 1 for the second, and so on.
- `render.date`: for example `2026-10-08`, the local date in the project's time zone. Use it for footers, and pass `--now` (or `--date`) when you need identical output on different days.
- `render.time`: for example `14:05:09`, the local time in the same zone.
- `render.now`: for example `2026-10-08T12:05:09Z`, the UTC instant of the render. Pass `--now` to pin it.

```json
"text": "#{card.id} · {render.date}"
```

The date and time functions are on [Dates and times](@/docs/expressions-functions-dates.md), and the time zone is set with `utc_offset` in [Project Layout and Manifest](@/docs/project-layout-and-manifest.md#time-zone).
