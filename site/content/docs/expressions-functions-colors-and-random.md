+++
title = "Expressions: Colors and Random"
description = "Build colors from hue, saturation and lightness, choose readable text, and make seeded random values."
+++

## Colors

Colors are described in the [literals and units](@/docs/expressions-literals-and-units.md) page. The functions here build one from HSL values or read one.

HSL is hue, saturation and lightness. The hue is an angle in degrees, where 0 is red, 120 is green and 240 is blue. Saturation and lightness go from 0 to 100.

Out-of-range values are clamped or wrapped, as described for each function, so these functions raise no error for them.

### `hsl(h, s, l)`

`(number, number, number) -> color`. An opaque color. `h` is an angle in degrees and wraps around, so 370 is the same as 10. `s` and `l` go from 0 to 100, as in CSS, and are clamped to that range.

- `hsl(0, 100, 50)` is `#FF0000`, and `hsl(120, 100, 50)` is `#00FF00`.

### `hsla(h, s, l, a)`

`(number, number, number, number) -> color`. As `hsl`, with alpha `a` from 0 (transparent) to 1 (opaque), clamped. The alpha is stored on the 8-bit grid, as in `rgba`.

- `hsla(0, 100, 50, 0.5)` is half-transparent red.

### `lighten(c, n)`, `darken(c, n)`

`(color, number) -> color`. Changes the lightness of `c` by `n` points on the 0 to 100 scale: `lighten` adds them and `darken` subtracts them. The hue and saturation stay the same, the lightness is clamped to its range, and the alpha is kept.

- `darken(accent, 20)` is a shade of `accent` that is 20 points darker in lightness.
- To blend toward a colour, use `mix` instead; `lighten` and `darken` change lightness only.

Example: a border a little darker than the theme colour:

```json
"stroke": { "color": "darken(accent, 15)", "width": 4 }
```

### `luminance(c)`

`(color) -> number`. The relative luminance of `c` as defined by WCAG 2: 0 for black, 1 for white. The alpha is ignored.

- `luminance(#FFFFFF)` is `1`. `luminance(#000000)` is `0`.
- Mid-grey `#808080` is about `0.22`, not `0.5`, so `luminance(c) > 0.5` is not a test for light colours. Use `readable` to choose a text colour.

### `readable(bg[, light, dark])`

`(color[, color, color]) -> color`. Chooses between two colors, for text on the background `bg`: it gives `light` when `light` has at least the WCAG contrast ratio against `bg` that `dark` has, and `dark` otherwise. So when both have the same contrast, `light` is chosen. `light` defaults to white (`#FFFFFF`) and `dark` to black (`#000000`).

- `readable(accent)` is white on a dark accent and black on a light one.
- `readable(bg, #FFF8E7, #3B2F2F)` picks a cream or a dark brown text colour.

## Random

Random values in an expression are **seeded**. A seed is a value you pass in, such as `card.id`, and the result is a fixed function of the seeds. The same seeds give the same value on every render, in every build of yoshida. The value changes only when the seeds change.

To make a value differ between cards, put something that differs between cards in the seeds, such as `card.id` or `render.index`. To make it change from day to day, include `render.date`. A seed's type matters: `rand(1)` and `rand('1')` are different values.

The mapping from seeds to values is fixed. A later version of yoshida gives the same values for the same seeds, so a design does not reshuffle when yoshida is updated.

### `rand(seed, ...)`

`(seed, ...) -> number`. A number from 0 (inclusive) up to 1 (exclusive). There must be at least one seed. Each seed is a number, a text, a bool or a color, and the seeds are taken together, in order.

- `rand(card.id)` is the same on every render of that card.
- `rand(card.id, 'x')` and `rand(card.id, 'y')` are two different values for the same card.

Example: a scatter position for a token on each card, the same on every render:

```json
"box": { "x": "rand(card.id, 'x') * 80%", "y": "rand(card.id, 'y') * 80%", "w": 20, "h": 20 }
```

### `rand_int(lo, hi, seed, ...)`

`(number, number, seed, ...) -> number`. A whole number from `lo` to `hi`, both included. `lo` and `hi` are floored. There must be at least one seed, as for `rand`.

- `rand_int(1, 6, card.id, 'dice')` is a whole number from 1 to 6, the same on every render.
- `rand_int(4, 4, card.id)` is always `4`.
- `lo` greater than `hi` is error 3107.

### `pick(seed, a, b, ...)`

`(seed, T, T, ...) -> T`. Chooses one of the choices, which are at least two values of the same type `T`. The seed is one value: a number, a text, a bool or a color. Each choice has an equal share of the seeded range. The result has the type of the choices.

- `pick(card.id, 'red', 'green', 'blue')` is one of the three texts, the same on every render of the card.
- Choices of different types are error 3003.

Example: a texture variant for each card:

```json
"fill": "pick(card.id, #C8A96A, #B5C4A1, #D9B8B0)"
```
