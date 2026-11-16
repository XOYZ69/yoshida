+++
title = "Expressions: Constants and Functions"
description = "Name a value or formula once and reuse it in every layer."
+++

A design can give names to values and formulas that several layers use, so a formula is written once instead of being pasted into every layer.

```json
"consts": {
  "tile": 170,
  "gap": "tile / 10",
  "pale": "mix(accent, #FFFFFF, 0.6)"
},
"functions": {
  "tile_x": { "args": { "i": "number" }, "expr": "65 + (i <= 12 ? i : 12) * tile" },
  "has_n": { "args": { "k": "text" }, "expr": "k == 'back' or k == 'forward' or k == 'shortcut'", "note": "Tiles that show a number" }
}
```

Layers use them like params and built-in functions:

```json
"translate": { "x": "tile_x(i)", "y": 40 },
"visible": "has_n(t.kind)",
"box": { "x": 0, "y": 0, "w": "tile - gap", "h": "tile - gap" }
```

## Constants

| Value | Means |
| --- | --- |
| a JSON number | a number |
| `true` / `false` | a bool |
| a string | an [expression](@/docs/expressions.md); the constant has the expression's type (number, bool, text, color, image) |
| a JSON array | a [list constant](#list-constants) |

- A constant can use params, `canvas.w`, `canvas.h`, `card.id`, `render.*` and the constants **above** it. Not loop names. It can also read a layer's bounds, see [Constants that read layers](#constants-that-read-layers).
- It is evaluated once per card (a constant that reads a layer, at each use).
- A text constant is an expression too, so it needs quotes inside: `"title_prefix": "'No. '"`.
- An expression cannot give a list or a list item (error 3003); write the list as a JSON array.

### List constants

A constant can be a list, for values every card shares, such as column widths or a table of costs. It is written as a JSON array, and used like a list param: by index, by key, in `repeat` and with `len()`.

```json
"consts": {
  "widths": [120, 80, 80],
  "rows": [{ "name": "Attack", "cost": 2 }, { "name": "Defense", "cost": 3 }]
}
```

- An array of numbers, true/false values or texts becomes a list whose items have one field, `value`: `widths[1].value`, or `"repeat": { "each": "widths", "item": "w" }` and `w.value`.
- An array of objects becomes a list of items. Every item has the same fields as the first, with the same types (number, true/false or text; no colors, images or nested lists). Field names are lowercase letters, digits and `_`.
- The first field is the key: `rows.Defense` is `3` (see [List lookup by key](@/docs/expressions-list-lookup.md)).
- An empty array is error 3003, because the fields of its items are not known. Items with other fields or types than the first are error 1103.
- A list constant has fixed values. It cannot use expressions; to compute a list from params use a list param.

### Constants that read layers

A constant may read a layer, such as `"edge": "@frame.bounds.right + gap"`, so a number is named once and used wherever it is needed:

- The constant is worked out where it is used, in the same frame as the layer that uses it, so it follows `translate` and layouts like a direct `@frame...` would.
- **Every constant after the first one that reads a layer is handled the same way**, so keep constants that only use numbers above it.
- These constants can be used by layers, but not by `functions` and not by `canvas` (a function cannot read layers, and the canvas comes before them).
- A layer that reads the constant must not be one the constant reads, even through other layers: that cycle is error 3004 when the card is drawn.

## Functions

| Field | Meaning |
| --- | --- |
| `args` | The arguments: an object of name to type (`number`, `text`, `bool`, `color`), in order, or an array of names (all numbers): `["i", "j"]` |
| `expr` | The body: an expression with the arguments, params, constants and the functions **above** this one |
| `note` | A description of the function, shown in the editor |

- Call a function like a built-in one: `tile_x(i)`. The number and types of the arguments are checked when the design loads (error 3003).
- The return type is the type of `expr`.
- The body cannot read layers or loop names; pass what it needs as arguments. A function cannot call itself or a function below it, so there is no recursion.
- A function may take a built-in's name. Its body sees only the functions above it, so inside its own body the name is still the built-in. For example, `"round": { "args": { "v": "number" }, "expr": "round(v * 2) / 2" }` rounds to halves, and every later `round(...)` in the design calls this function. The loader gives warning 1113.
- An error while a body is evaluated (such as a division by zero) is reported at the body, `/functions/<name>/expr`, with the card's id.

## Names

Constant and function names follow the identifier rule `[a-z_][a-z0-9_]*` and must not be a param, a reserved word, or another constant or function (error 1106). A loop name in a layer can hide a constant inside that layer.

A name may equal a built-in function's name. A constant with such a name works, because a bare name is a value and calls of the built-in still work. A **function** with a built-in's name replaces that built-in in this design, and the design gets warning 1113: calls to it run the design's function. See [Functions](@/docs/expressions-functions.md#names-of-functions-and-other-names).

## In the editor

With nothing selected, the inspector lists the design's constants and functions with fields to change them, and **Add** buttons. Expression fields suggest them as you type. See [Builder: Inspector](@/docs/builder-inspector.md).

A function's `note` is its description in expression fields: the suggestion list, the tooltip when you hover a call and the signature help show it. Without a note they show "A design function".
