+++
title = "Expressions: Numbers"
description = "Roots, powers, trigonometry in radians, and interpolation between ranges."
+++

Each function takes numbers and returns a number. Trigonometry takes and returns **radians**, as in ordinary maths: `sin(pi / 2)` is `1`. The angle fields such as `rotate` take degrees; see [Trigonometry](#trigonometry).

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

Angles are in **radians**, as in ordinary mathematics: a full turn is `2 * pi`. `pi` is a built-in number, 3.14159…; a param or constant named `pi` takes its place. `deg(x)` and `rad(x)` convert between the two. The angle fields are the exception: `rotate`, the `arc` start and end, and the hue of `hsl` take degrees, so convert with `deg` where needed.

### `sin(x)`, `cos(x)`, `tan(x)`

`(number) -> number`. The sine, cosine and tangent of the angle `x`, in radians. `sin` and `cos` are exact at multiples of `pi / 2`, and `tan` at multiples of `pi / 4`.

- `sin(pi)` is `0`, `cos(pi / 2)` is `0` and `tan(pi / 4)` is `1`, exactly.
- `tan` at `pi / 2 + k * pi`, such as `tan(pi / 2)`, is error 3103.

### `asin(x)`, `acos(x)`

`(number) -> number`. The inverse sine and cosine of `x`, as an angle in radians. `asin` gives a value from `-pi / 2` to `pi / 2`, and `acos` a value from `0` to `pi`.

- `asin(1)` is `pi / 2`. `acos(-1)` is `pi`.
- `|x| > 1` is error 3103.

### `atan2(y, x)`

`(number, number) -> number`. The angle of the point `(x, y)` measured from the positive x axis, in radians. The result is greater than `-pi` and at most `pi`. Note the order: `y` comes first.

- `atan2(1, 1)` is `pi / 4`. `atan2(0, -1)` is `pi`.
- `atan2(0, 0)` is `0`.

To use the angle as a `rotate` value, which takes degrees: `"rotate": "deg(atan2(dy, dx))"`.

### `deg(x)`, `rad(x)`

`(number) -> number`. `deg(x)` converts radians to degrees, and `rad(x)` converts degrees to radians.

- `deg(pi)` is `180`. `rad(90)` is `pi / 2`.

Example: the points of a ring of six pips, evenly spaced from the top. Neighbouring pips are a sixth of a turn apart, `pi / 3`:

```json
"x": "50% + 200 * sin(i * pi / 3)",
"y": "50% - 200 * cos(i * pi / 3)"
```

Example: a wave of circles, one full wave every 12 items (`pi / 6` per item):

```json
"box": { "x": "60 + i * 60", "y": "450 + sin(i * pi / 6) * 80", "w": 40, "h": 40 }
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
