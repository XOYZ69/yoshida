+++
title = "Expressions: Functions"
+++

| Function | Signature | Notes |
| --- | --- | --- |
| `min`, `max` | `(number, number, ...) -> number` | Any number of arguments |
| `clamp` | `(value, lo, hi) -> number` | |
| `abs`, `floor`, `ceil` | `(number) -> number` | |
| `round` | `(number, digits = 0) -> number` | |
| `len` | `(list or text) -> number` | Items in a list, characters in text |
| `upper`, `lower`, `trim` | `(text) -> text` | |
| `fmt` | `(number, decimals) -> text` | `fmt(0.5, 2)` is `0.50` |
| `avg_color` | `(image) -> color` | Average of the opaque pixels of an image param |
| `mix` | `(color, color, t) -> color` | Linear blend, `t` from 0 to 1 |
| `with_alpha` | `(color, a) -> color` | `a` from 0 (transparent) to 1 |
| `rgb`, `rgba` | `(r, g, b[, a]) -> color` | Channels 0 to 255, `a` from 0 to 1 |

Calling an unknown function is error 3002 (with a "did you mean" hint). A wrong number of arguments or a wrong argument type is error 3003.

Function names cannot be used as param names (error 1106).

A design can add its own functions, such as `tile_x(i)`, and named constants: see [Constants and functions](@/docs/expressions-constants-and-functions.md).

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
