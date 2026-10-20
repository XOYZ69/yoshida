+++
title = "Expressions: Functions"
description = "Every built-in function, with arguments and return types."
+++

A function is called by its name, with its arguments in parentheses: `round(price, 1)`. Arguments and results have [types](@/docs/expressions.md#types); there is no conversion between them. Calling an unknown function is error 3002 (with a "did you mean" hint). A wrong number of arguments or a wrong argument type is error 3003.

The functions are grouped by what they work on. The table below lists every group; the existing functions are described on this page, and the others on the pages linked from the table.

| Group | Functions | Page |
| --- | --- | --- |
| Existing | `min` `max` `clamp` `abs` `floor` `ceil` `round` `len` `upper` `lower` `trim` `fmt` `avg_color` `mix` `with_alpha` `rgb` `rgba` `match` | this page |
| Numbers and trigonometry | `sqrt` `pow` `sign` `sin` `cos` `tan` `asin` `acos` `atan2` `deg` `rad` `lerp` `remap` `wrap` | [Numbers](@/docs/expressions-functions-numbers.md) |
| Text | `contains` `starts_with` `ends_with` `replace` `slice` `pad_start` `repeat` `title_case` `roman` `part` | [Text](@/docs/expressions-functions-text.md) |
| Lists | `has` `get` `index_of` `sum` `avg` `min` `max` `count` `join` `last` | [Lists](@/docs/expressions-functions-lists.md) |
| Dates and times | `date_fmt` `year` `month` `day` `weekday` `hour` `minute` `add_days` `add_hours` `days_between` | [Dates and times](@/docs/expressions-functions-dates.md) |
| Colors | `hsl` `hsla` `lighten` `darken` `luminance` `readable` | [Colors and random](@/docs/expressions-functions-colors-and-random.md) |
| Random | `rand` `rand_int` `pick` | [Colors and random](@/docs/expressions-functions-colors-and-random.md) |

## Existing functions

| Function | Signature | Notes |
| --- | --- | --- |
| `min`, `max` | `(number, number, ...) -> number` | Any number of arguments. When the first argument is a list, see [Lists](@/docs/expressions-functions-lists.md) |
| `clamp` | `(value, lo, hi) -> number` | The middle of the three values; the CSS order `clamp(lo, value, hi)` also works. With `lo` above `hi` it is not an error and still gives the middle value: `clamp(10, 5, 0)` is `5` |
| `abs`, `floor`, `ceil` | `(number) -> number` | |
| `round` | `(number, digits = 0) -> number` | Halves away from zero, on the decimal digits: `round(1.005, 2)` is `1.01`. `digits` may be negative: `round(1234.5, -2)` is `1200`. `digits` is rounded to a whole number and limited to -15 to 15 |
| `len` | `(list or text) -> number` | Items in a list, characters in text |
| `upper`, `lower`, `trim` | `(text) -> text` | See below for `upper` and `lower` |
| `fmt` | `(number, decimals) -> text` | `fmt(0.5, 2)` is `0.50`. Rounds as `round` does, and never prints `-0.00`. `decimals` is rounded to a whole number and kept between 0 and 15 |
| `avg_color` | `(image) -> color` | Average of the opaque pixels of an image param |
| `mix` | `(color, color, t) -> color` | Linear blend, `t` from 0 to 1 |
| `with_alpha` | `(color, a) -> color` | `a` from 0 (transparent) to 1 |
| `rgb`, `rgba` | `(r, g, b[, a]) -> color` | Channels 0 to 255, `a` from 0 to 1, stored on the 8-bit grid: `rgba(255, 0, 0, 0.5)` is `#FF000080` |
| `match` | `(value, key, result, ..., default) -> result type` | Result of the first key equal to `value`, else `default`. See below |

`upper` and `lower` change the case of letters in the ASCII, Latin-1 Supplement, Latin Extended-A, Greek and Cyrillic blocks. Other characters are unchanged, and so is `ß`: `upper('ß')` is `ß`.

## Names of functions and other names

A bare name never calls a function, and a call always has parentheses. So a param, constant, loop name or function argument may use the name of a built-in function. `min` as a param is a value, and `min(a, b)` still calls the built-in.

A **design function** may also use a built-in's name, such as `round`. Inside that design the design function replaces the built-in: later calls to `round(...)` run the design's function, and the design gets warning 1113. The function's own body still sees the built-in, so a wrapper can call it (see [Constants and functions](@/docs/expressions-constants-and-functions.md)). Other designs are not affected.

Reserved words (`canvas`, `render`, `card`, `true`, `false`, `and`, `or`, `not`, `in`) cannot be used for any name (error 1106).

A design can add its own functions, such as `tile_x(i)`, and named constants: see [Constants and functions](@/docs/expressions-constants-and-functions.md).

## Choosing between several values

`match` gives the result of the first key equal to the value, and `in` tests whether a value equals one item of a list. Both replace long chains of `==` tests. Keys have the value's type, and all results and the default share one type. Only the chosen result is evaluated, as with `? :`.

Membership, with `in` in place of `or`.

Before:

```json
"has_n": "k == 'back' or k == 'forward' or k == 'shortcut'"
```

After:

```json
"has_n": "k in ['back', 'forward', 'shortcut']"
```

A value picked by key, with `match` in place of a `? :` chain.

Before:

```json
"kind_color": "k == 'start' ? c_start : k == 'finish' ? c_finish : k == 'safe' ? c_safe : c_plain"
```

After:

```json
"kind_color": "match(k, 'start', c_start, 'finish', c_finish, 'safe', c_safe, c_plain)"
```

Which pips of a die face are shown, with one `match` in place of six comparisons.

Before:

```json
"pip": "face == 1 ? k == 4 : face == 2 ? (k == 0 or k == 8) : face == 3 ? (k == 0 or k == 4 or k == 8) : face == 4 ? (k == 0 or k == 2 or k == 6 or k == 8) : face == 5 ? (k == 0 or k == 2 or k == 4 or k == 6 or k == 8) : (k == 0 or k == 2 or k == 3 or k == 5 or k == 6 or k == 8)"
```

After:

```json
"pip": "match(face, 1, k in [4], 2, k in [0, 8], 3, k in [0, 4, 8], 4, k in [0, 2, 6, 8], 5, k in [0, 2, 4, 6, 8], k in [0, 2, 3, 5, 6, 8])"
```

## Examples

```json
"text": "{upper(title)}"
"text": "{fmt(price, 2)} €"
"fill": "mix(accent, #FFFFFF, 0.85)"
"color": "with_alpha(accent, 0.6)"
"fill": "rgb(30, 30, 40)"
"fill": "rgba(0, 0, 0, 0.5)"
"w": "min(80%, len(title) * 40)"
"size": "round(base * 1.5)"
"fill": "mix(avg_color(art), #000000, 0.4)"
```

`avg_color(art)` needs an `image` [param](@/docs/params.md) (or an image-typed value) as its argument, and the image has to load, so it follows the same rules as an [image layer](@/docs/layer-image.md) for missing files.

The editor shows each function's signature, description and an example as you type; see [Builder: Expression editor](@/docs/builder-expression-editor.md).
