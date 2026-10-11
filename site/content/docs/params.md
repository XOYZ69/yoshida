+++
title = "Params"
description = "The inputs a card can set: types, defaults, lists and enums."
+++

Params are the inputs a card can set. Each one has a name and a type. Layers read them by name in [expressions](@/docs/expressions.md) and [templates](@/docs/expressions-templates.md): `{title}`, `level * 2`, `accent`.

```json
"params": {
  "scale":       { "type": "number",  "default": 2, "min": 0.5 },
  "level":       { "type": "integer", "default": 4, "min": 0, "max": 12 },
  "title":       { "type": "text",    "default": "Untitled", "max_length": 60 },
  "foil":        { "type": "bool",    "default": false },
  "accent":      { "type": "color",   "default": "#660940" },
  "card_type":   { "type": "enum",    "options": ["spell", "trap"], "default": "spell" },
  "art":         { "type": "image",   "required": true },
  "ingredients": { "type": "list", "item": { "amount": "text", "unit": "text", "name": "text" }, "default": [] }
}
```

## Names

A param name follows the identifier rule `[a-z_][a-z0-9_]*` (lowercase letters, digits and underscores, not starting with a digit). It must not be a reserved word (`canvas`, `render`, `card`, `true`, `false`, `and`, `or`, `not`) or a [function name](@/docs/expressions-functions.md); that is error 1106.

| Name | Valid? |
| --- | --- |
| `title`, `c_start`, `tile_num`, `stat2`, `_tmp` | yes |
| `tile_Num`, `Title` | no: uppercase letters |
| `2nd`, `tile-num` | no: starts with a digit, contains `-` |

The same rule applies to the loop names in [`repeat`](@/docs/repeat.md) (`index`, `item`), where a bad name is error 1103.

Params and layers live in separate namespaces, because layer references always start with `@`. A param called `background` and a layer called `background` can coexist.

## Types

| Type | Value in card data | Notes |
| --- | --- | --- |
| `number` | JSON number | Any real number |
| `integer` | JSON number | Whole numbers only |
| `text` | JSON string | |
| `bool` | `true` / `false` | |
| `color` | hex string such as `"#660940"` | `#RRGGBB`, `#RRGGBBAA`, or the 16-bit forms |
| `enum` | one of `options` | Literal word, not an expression |
| `image` | project path or `https://` URL | Used in `src` templates and image functions (`avg_color(art)`) |
| `list` | array of objects | Items described by `item` |

## Fields

| Field | Applies to | Meaning |
| --- | --- | --- |
| `type` | all | One of the types above |
| `default` | all | Literal value used when the card does not set it. A JSON literal, not an expression |
| `required` | all | `true`: the card must set it (error 2003). A required param has no default |
| `label`, `note` | all | Shown in the editor |
| `group` | all | Free text naming the editor section the param belongs to, such as `"Monster stats"`. Params with the same group are shown together in the editor's params list and card form, in order of first appearance; params without one come first. No effect on rendering |
| `min`, `max` | number, integer | Inclusive range (error 2002 when a card is outside it) |
| `max_length` | text | Maximum characters (error 2002) |
| `options` | enum | Non-empty array of strings |
| `item` | list | Object of field name to field type: `number`, `integer`, `text`, `bool`, `color`, or `{ "type": ..., "options": [...], "default": ... }` for enum fields and defaults. `image` and `list` fields are error 1103. See [lists](#lists) |

A param with neither `default` nor `required: true` is error 1107.

When a card leaves out a param that has no default and is not required (which 1107 prevents), the value would be the type's zero value: `0`, `""`, `false`, transparent, an empty list.

## Lists

A list param holds several items, each with the same fields:

```json
"stats": {
  "type": "list",
  "item": { "name": "text", "value": "number" },
  "default": []
}
```

In card data:

```json
{ "id": "001", "stats": [ { "name": "Speed", "value": 8 }, { "name": "Power", "value": 3 } ] }
```

### Item fields

A field is a type name, or an object with `type`, `options` (enum fields only) and `default`:

```json
"tiles": {
  "type": "list",
  "item": {
    "kind": { "type": "enum", "options": ["plain", "safe", "skip"], "default": "plain" },
    "text": "text",
    "color": { "type": "color", "default": "#7FD1E8" }
  },
  "default": []
}
```

- An **enum field** must have one of its `options` in every item: `"kind": "shortcuts"` in card data is error 2006 (`item 1 field 'kind': 'shortcuts' is not one of plain, safe, skip`), not a plain tile. In expressions it reads as text: `t.kind == 'safe'`. A typo in the expression itself (`t.kind == 'saef'`) is not found.
- A field an item leaves out takes the field's `default`; without one, the zero value of its type (`0`, `""`, `false`, `#00000000`), and an enum field its first option.
- Item fields have no `min`, `max` or `max_length`.

### Changing single items of the default

A card's list value replaces the default list. To change only some items, give an **object of positions** (0-based) instead of an array; the rest of the default stays:

```json
{ "id": "variant", "tiles": { "11": { "kind": "safe", "text": "Rest stop" }, "20": { "kind": "skip" } } }
```

Each change sets only the fields it names. A position the default list does not have is error 2006, and so is an object for a list param without a default. In CSV the cell holds the same JSON object. The editor saves card edits this way when the default list has items and the card keeps their number.

You can use a list three ways:

- **Index**: `stats[0].value` (0-based; an index out of range is error 3102 at render time).
- **Key**: `stats.Speed` or `stats["Speed"]`. See [List lookup by key](@/docs/expressions-list-lookup.md).
- **Repeat**: draw a layer once per item with `"repeat": { "each": "stats", "item": "s" }`, or use `"count": "stats"` (the number of items). See [Repeat](@/docs/repeat.md).

In CSV files a list cell holds a JSON array, see [Card Data](@/docs/card-data.md).

## Image params

An `image` value is a path inside the project (`assets/images/shiro.jpg`) or an `https://` URL. Use it in an image layer's `src`:

```json
{ "id": "art", "type": "image", "src": "{art}", "box": { "x": 0, "y": 0, "w": 400, "h": "auto" } }
```

## In the editor

The editor builds its card form from the params: a color picker for `color`, a dropdown for `enum`, a file picker for `image`, a table for `list`. The order of `params` in the file is the order of the form, within each group. See [Builder: Params](@/docs/builder-params.md) and [Builder: Card data](@/docs/builder-card-data.md).
