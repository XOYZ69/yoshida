+++
title = "Expressions: Literals and Units"
description = "Numbers, units, strings, colours and lists."
+++

## Literals

- **Numbers**: `12`, `0.5`. A leading dot (`.5`) is invalid. An optional unit suffix follows: `%`, `vw`, `vh`.
- **Strings**: `'single'` or `"double"` quotes, with the escapes `\'`, `\"`, `\\` and `\n`. Single quotes avoid escaping inside JSON: `"foil ? 'FOIL' : 'NEW'"`.
- **Booleans**: `true`, `false`.
- **Colors**: `#RRGGBB`, `#RRGGBBAA` (8-bit per channel), `#RRRRGGGGBBBB`, `#RRRRGGGGBBBBAAAA` (16-bit per channel). Hex digits are case-insensitive.

Internally all colors are 16-bit RGBA; an 8-bit value `v` becomes `v * 257`, so `#FF` is exactly full. Use the 16-bit forms when you need fine gradations in 16-bit PNG output (`yoshida render --16bit`).

A hex color is a valid expression, so `"fill": "#FF0000"` and `"fill": "accent"` are both fine, and so is `"fill": "foil ? #F5C542 : accent"`.

## Units

Numbers can carry a unit. Without one a number is a pixel value.

| Unit | Means |
| --- | --- |
| `N%` | N percent of the canvas **along the field's axis** |
| `Nvw` | N percent of the canvas width, valid in any number field |
| `Nvh` | N percent of the canvas height, valid in any number field |

### Where `%` works

`%` needs an axis, so it is valid only in fields that have one:

| Horizontal fields (percent of canvas width) | Vertical fields (percent of canvas height) |
| --- | --- |
| `box.x`, `box.w` | `box.y`, `box.h` |
| `at.x` | `at.y` |
| a polygon point's first value | a polygon point's second value |
| `wrap`, `max_width` | `max_height` |
| `crop` / `fade` `length` toward `left` or `right` | `crop` / `fade` `length` toward `top` or `bottom` |

Anywhere else (`size`, `radius`, `stroke.width`, `line_spacing`, ...) `%` is error 3006 with the hint to use `vw` or `vh`. Those two always work.

`canvas.width` and `canvas.height` cannot use any unit, because the canvas is being defined (error 3006).

### Combining units

Units are part of a number, not a separate type, so they can be combined with arithmetic:

```json
"x": "50% - 100"
"w": "90% - 2 * 40"
"size": "6vh"
```

### `%` as the modulo operator

`%` as an operator needs operands on both sides (`a % b`). `50%` directly after a number is the unit. See [Operators](@/docs/expressions-operators.md).

## Next

[Names and references](@/docs/expressions-names-and-references.md)
