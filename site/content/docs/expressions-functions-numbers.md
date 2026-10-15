+++
title = "Expressions: Numbers"
description = "Roots, powers, trigonometry in degrees, and interpolation between ranges."
+++

Each function takes numbers and returns a number. Angles are in **degrees** everywhere, as in `rotate`: `sin(90)` is `1`.

A math error is error 3103. It happens for division by zero, and for a result that is not a finite number, such as the square root of a negative number. Such a value never reaches a layer.

## Powers and roots

### `sqrt(x)`

`(number) -> number`. The square root of `x`.

- `sqrt(16)` is `4`.
- `x < 0` is error 3103.

### `pow(base, exp)`

`(number, number) -> number`. `base` raised to the power `exp`.

- `pow(2, 10)` is `1024`.
- A result that is not a finite number is error 3103: `pow(-8, 1/3)` (not a real number) and `pow(0, -1)` (infinite).

### `sign(x)`

`(number) -> number`. `-1`, `0` or `1`, the sign of `x`.

- `sign(-4)` is `-1`. `sign(-0)` is `0`.

## Trigonometry

Each angle is in degrees, and results are exact at the multiples of 90 degrees.

### `sin(d)`, `cos(d)`, `tan(d)`

`(number) -> number`. The sine, cosine and tangent of the angle `d`, in degrees. The angle is reduced modulo 360 first.

- `sin(180)` is `0`, `cos(90)` is `0` and `tan(45)` is `1`, exactly.
- `tan` at 90 plus any multiple of 180, such as `tan(90)`, is error 3103.

### `asin(x)`, `acos(x)`

`(number) -> number`. The inverse sine and cosine of `x`, as an angle in degrees.

- `asin(1)` is `90`. `acos(0)` is `90`.
- `|x| > 1` is error 3103.

### `atan2(y, x)`

`(number, number) -> number`. The angle of the point `(x, y)` measured from the positive x axis, in degrees. The result is greater than -180 and at most 180. Note the order: `y` comes first.

- `atan2(1, 1)` is `45`. `atan2(-1, -1)` is `-135`.
- `atan2(0, 0)` is `0`.

Example: the points of a ring of pips, with 6 pips evenly spaced from the top:

```json
"x": "50% + 200 * sin(i * 60)",
"y": "50% - 200 * cos(i * 60)"
```

## Interpolation

### `lerp(a, b, t)`

`(number, number, number) -> number`. `a + (b - a) * t`. `t` is 0 at `a` and 1 at `b`. Not clamped.

- `lerp(10, 20, 0.5)` is `15`.
- `lerp(0, 100, 1.5)` is `150`.

### `remap(v, a, b, c, d)`

`(number, number, number, number, number) -> number`. Maps `v` from the range `a` to `b` onto the range `c` to `d`: `c + (v - a) * (d - c) / (b - a)`. Not clamped, and `b` may be less than `a`.

- `remap(50, 0, 100, 0, 1)` is `0.5`.
- `remap(150, 0, 100, 0, 1)` is `1.5`.
- `remap(25, 0, 100, 1, 0)` is `0.75`.
- `a == b` is error 3103.

Example: a stat bar as a fraction of the canvas width, for a stat from 0 to 10:

```json
"w": "remap(stat, 0, 10, 0, 90%)"
```

### `wrap(v, n)`

`(number, number) -> number`. `v - n * floor(v / n)`: `v` moved into the range from 0 up to `n`. Useful for cycling through options with negative indices.

- `wrap(-1, 4)` is `3`. `wrap(5, 4)` is `1`.
- For `n > 0` the result is at least 0 and less than `n`.
- `n == 0` is error 3103.
