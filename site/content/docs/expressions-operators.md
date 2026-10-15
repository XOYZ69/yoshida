+++
title = "Expressions: Operators"
description = "Arithmetic, comparison and logic operators, by precedence."
+++

Highest precedence first:

| Operators | Operand types | Result |
| --- | --- | --- |
| `( )`, `f(...)`, `a.b`, `a[n]` | | |
| unary `-`, `not` | number / bool | number / bool |
| `*` `/` `%` | number | number. Division by zero is error 3103 (at render time). `%` is the floored modulo, see the notes |
| `+` `-` | number | number |
| `<` `<=` `>` `>=` | number | bool |
| `==` `!=` | same type on both sides | bool |
| `in` | left: number, text, bool or color; right: a bracket list of the same type | bool, short-circuit |
| `and` | bool | bool, short-circuit |
| `or` | bool | bool, short-circuit |
| `c ? a : b` | bool, then two values of the same type | right-associative |

## Notes

- There is **no assignment**, **no string concatenation operator** (use [templates](@/docs/expressions-templates.md): `"{first} {last}"`) and **no implicit conversion**. `'5' + 1` is error 3003.
- `==` and `!=` compare values of the same type: numbers with numbers, text with text, colors with colors, bools with bools.
- `%` is the modulo operator. The result has the sign of the right operand, as in maths and Excel's MOD: `-7 % 3` is `2`, and `7 % -3` is `-2`. It needs operands on both sides, and after a number literal a space: write `7 % 3`. `7%3` reads `7%` as a percent and is error 3001 with a hint. `50%` directly after a number is the percent unit (see [Literals and units](@/docs/expressions-literals-and-units.md)).
- `and` and `or` short-circuit, so `len(list) > 0 and list[0].value > 3` does not index an empty list.
- `in` takes a bracket list written right there: `k in ['back', 'forward']` or `k in [0, 4, 8]`. The list has one or more items and no trailing comma. Lists are not values elsewhere, so a list cannot be stored in a constant or param. A missing or empty list is error 3001, and an item of another type is error 3003. The check stops at the first equal item.
- `not` binds tighter than `in`, so write `not (k in [...])`.
- The conditional `c ? a : b` needs both branches to have the same type. It nests to the right, so a chain needs no brackets: `a ? 1 : b ? 2 : 3` is `a ? 1 : (b ? 2 : 3)`.

## Examples

```json
"visible": "level >= 5 and not foil"
"fill": "card_type == 'spell' ? #1D7874 : #8E2C48"
"x": "50% + (i - (n - 1) / 2) * 56"
"size": "clamp(90 - len(title) * 2, 40, 90)"
"opacity": "foil ? 1 : 0.4"
"visible": "not (k in [0, 4, 8])"
```
