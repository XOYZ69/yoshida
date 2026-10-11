+++
title = "Expressions: Constants and Functions"
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

- A constant can use params, `canvas.w`, `canvas.h`, `card.id`, `render.*` and the constants **above** it. Not layers, not loop names.
- It is evaluated once per card.
- A text constant is an expression too, so it needs quotes inside: `"title_prefix": "'No. '"`.
- A constant cannot be a list (error 3003).

## Functions

| Field | Meaning |
| --- | --- |
| `args` | The arguments: an object of name to type (`number`, `text`, `bool`, `color`), in order, or an array of names (all numbers): `["i", "j"]` |
| `expr` | The body: an expression with the arguments, params, constants and the functions **above** this one |
| `note` | A comment |

- Call a function like a built-in one: `tile_x(i)`. The number and types of the arguments are checked when the design loads (error 3003).
- The return type is the type of `expr`.
- The body cannot read layers or loop names; pass what it needs as arguments. A function cannot call itself or a function below it, so there is no recursion.
- An error while a body is evaluated (such as a division by zero) is reported at the body, `/functions/<name>/expr`, with the card's id.

## Names

Constant and function names follow the identifier rule `[a-z_][a-z0-9_]*` and must not be a param, a reserved word, a built-in function or another constant or function (error 1106). A loop name in a layer can hide a constant inside that layer.

## In the editor

With nothing selected, the inspector lists the design's constants and functions with fields to change them, and **Add** buttons. Expression fields suggest them as you type. See [Builder: Inspector](@/docs/builder-inspector.md).
