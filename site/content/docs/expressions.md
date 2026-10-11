+++
title = "Expressions"
+++

Almost every value in a design can be an **expression**: a small formula that reads params, other layers and the canvas. Expressions have no assignments, no loops and no side effects, and are checked for types when the design loads, before anything is drawn.

```json
"box": { "x": "50% + (i - (level - 1) / 2) * 56", "y": "@title.bounds.bottom + 50", "w": 48, "h": "auto" }
"fill": "foil ? #F5C542 : accent"
"text": "{upper(title)} · {fmt(cost, 1)} pts"
```

## Value kinds

Every field has one of these kinds. The kind decides how a JSON value in that field is read.

| Kind | JSON number | JSON bool | JSON string means |
| --- | --- | --- | --- |
| `number` | literal | error | expression yielding a number |
| `bool` | error | literal | expression yielding a bool |
| `color` | error | error | expression yielding a color (a hex literal is a valid expression) |
| `text` | error | error | [template](@/docs/expressions-templates.md) |
| `path` | error | error | template; the result must be a project path or `https://` URL |
| `enum(...)` | error | error | one of the listed words, literal only |
| `ident` | error | error | an identifier `[a-z_][a-z0-9_]*`, literal only |

A wrong JSON type is error 1103. A number field accepts a plain JSON number (`120`) as well as a string expression (`"120 + 10"`).

## Types

Expressions have the types number, bool, text, color, image, list and list item. There is no implicit conversion: `'5' + 1` is a type error (3003).

## The pages

| Page | Covers |
| --- | --- |
| [Literals and units](@/docs/expressions-literals-and-units.md) | numbers, strings, booleans, colors, `%`, `vw`, `vh` |
| [Names and references](@/docs/expressions-names-and-references.md) | params, loop names, `canvas`, `card`, `render`, `@layer` references |
| [Operators](@/docs/expressions-operators.md) | precedence, arithmetic, comparison, logic, `? :` |
| [Functions](@/docs/expressions-functions.md) | `min`, `clamp`, `round`, `fmt`, `mix`, `avg_color`, ... |
| [Templates](@/docs/expressions-templates.md) | `{expression}` holes in `text` and `path` fields |
| [List lookup by key](@/docs/expressions-list-lookup.md) | `stats.Speed`, `stats["Speed"]` |
| [Constants and functions](@/docs/expressions-constants-and-functions.md) | `consts` and `functions` of a design: named values and formulas |

## Determinism

The same project, card data and `render.date` always produce the same pixels in every build (WebAssembly, CLI, server). Expressions have no clock, no randomness, no network and no file access.

## Errors

- Syntax errors are 3001, unknown names or functions 3002 (with a "did you mean" hint), type mismatches and wrong function arguments 3003, reference cycles 3004, references to repeated layers without an iteration index 3005, units in the wrong place 3006.
- Division by zero (3103), a list or iteration index out of range (3102), a list key that does not exist (3104) and a negative width or height (3101) can only be found while evaluating a specific card, so they are reported with the card's id, by `yoshida check` (which evaluates every card) and when rendering.

See [Diagnostics](@/docs/diagnostics.md). In the editor, expression fields are small code editors with highlighting, completion and a reference: [Builder: Expression editor](@/docs/builder-expression-editor.md).
