//! Numeric built-ins. Angles are radians, as in ordinary maths. Pure: no allocation, no expression types.

const std = @import("std");
const testing = std.testing;

pub const Error = error{
    /// Division by zero, a result that is not finite, or an argument outside the domain.
    Domain,
};

const deg_to_rad = std.math.pi / 180.0;
const rad_to_deg = 180.0 / std.math.pi;
const half_pi = std.math.pi / 2.0;
const quarter_pi = std.math.pi / 4.0;

/// Rejects NaN and infinities: every fallible result must be finite.
fn finite(x: f64) Error!f64 {
    if (!std.math.isFinite(x)) return error.Domain;
    // Adding +0 turns -0 into +0.
    return x + 0.0;
}

/// Square root. A negative argument is outside the domain.
pub fn sqrt(x: f64) Error!f64 {
    if (x < 0) return error.Domain;
    return finite(@sqrt(x));
}

/// `b` raised to `e`. A non-finite result (0 to a negative power, a negative base
/// to a fractional power, overflow) is a Domain error.
pub fn pow(b: f64, e: f64) Error!f64 {
    return finite(std.math.pow(f64, b, e));
}

/// -1, 0 or 1. `sign(-0) == 0`. NaN gives 0.
pub fn sign(x: f64) f64 {
    if (x > 0) return 1;
    if (x < 0) return -1;
    return 0;
}

/// How close `x` must be to a whole multiple of `step` (relative to `x`) to snap to it.
/// Covers the rounding in `pi`, `pi / 2`, `3 * pi / 2` and the like.
const snap_tol = 8 * std.math.floatEps(f64);

/// The whole number `k` when `x` is within rounding of `k * step`, else null.
fn multipleOf(x: f64, step: f64) ?i64 {
    const k = x / step;
    const r = @round(k);
    // Zero needs no snapping (sin(0) is exact) and small angles must keep their value.
    if (r == 0) return null;
    // Only the rounding error of writing `x` itself (pi, 3 * pi / 2, ...): a few ulps of x,
    // so large non-multiples such as 3e9 * pi / 2 + 0.004 are not snapped.
    if (@abs(x - r * step) > snap_tol * @abs(x)) return null;
    if (@abs(r) > 1e15) return null;
    return @intFromFloat(r);
}

/// Sine of `x` radians. Exact at multiples of pi / 2, so `sin(pi) == 0`.
pub fn sin(x: f64) Error!f64 {
    if (!std.math.isFinite(x)) return error.Domain;
    if (multipleOf(x, half_pi)) |k| return ([4]f64{ 0, 1, 0, -1 })[@intCast(@mod(k, 4))];
    return finite(std.math.sin(x));
}

/// Cosine of `x` radians. Exact at multiples of pi / 2, so `cos(pi / 2) == 0`.
pub fn cos(x: f64) Error!f64 {
    if (!std.math.isFinite(x)) return error.Domain;
    if (multipleOf(x, half_pi)) |k| return ([4]f64{ 1, 0, -1, 0 })[@intCast(@mod(k, 4))];
    return finite(std.math.cos(x));
}

/// Tangent of `x` radians. Exact at multiples of pi / 4; at pi / 2 + k * pi it is a Domain error.
pub fn tan(x: f64) Error!f64 {
    if (!std.math.isFinite(x)) return error.Domain;
    if (multipleOf(x, quarter_pi)) |k| {
        // Index is the multiple of pi / 4 modulo 2 pi; null marks the poles.
        const exact = [8]?f64{ 0, 1, null, -1, 0, 1, null, -1 };
        return exact[@intCast(@mod(k, 8))] orelse error.Domain;
    }
    return finite(std.math.tan(x));
}

/// Arc sine in radians, in [-pi / 2, pi / 2]. `|x| > 1` is a Domain error.
pub fn asin(x: f64) Error!f64 {
    if (@abs(x) > 1) return error.Domain;
    return finite(std.math.asin(x));
}

/// Arc cosine in radians, in [0, pi]. `|x| > 1` is a Domain error.
pub fn acos(x: f64) Error!f64 {
    if (@abs(x) > 1) return error.Domain;
    return finite(std.math.acos(x));
}

/// Angle of the point (x, y) in radians, in (-pi, pi]. `atan2(0, 0) == 0`.
pub fn atan2(y: f64, x: f64) Error!f64 {
    if (y == 0 and x == 0) return 0;
    var r = std.math.atan2(y, x);
    // The range is (-pi, pi]: -pi (from y = -0) is pi.
    if (r <= -std.math.pi) r = std.math.pi;
    return finite(r);
}

/// Radians to degrees, for fields such as `rotate` that take degrees.
pub fn deg(x: f64) Error!f64 {
    return finite(x * rad_to_deg);
}

/// Degrees to radians.
pub fn rad(x: f64) Error!f64 {
    return finite(x * deg_to_rad);
}

/// Linear interpolation `a + (b - a) * t`. `t` is not clamped.
pub fn lerp(a: f64, b: f64, t: f64) Error!f64 {
    return finite(a + (b - a) * t);
}

/// Maps `v` from [a, b] to [c, d]. The result is not clamped. `a == b` is a Domain error.
pub fn remap(v: f64, a: f64, b: f64, c: f64, d: f64) Error!f64 {
    if (a == b) return error.Domain;
    // Divide first so large magnitudes do not overflow the product.
    return finite(c + (v - a) / (b - a) * (d - c));
}

/// `v` modulo `n`, with the sign of `n`: [0, n) for n > 0, (n, 0] for n < 0.
/// `n == 0` is a Domain error.
pub fn wrap(v: f64, n: f64) Error!f64 {
    if (n == 0) return error.Domain;
    // `@mod` is exact for finite values, unlike v - n * floor(v / n).
    var r = try finite(@mod(v, n));
    if (n > 0) {
        // Rounding can leave a tiny negative result, or exactly n: both mean "just below n" or 0.
        if (r < 0) r += n;
        if (r >= n) r = 0;
        if (r < 0) r = 0;
    }
    return r;
}

// ------------------------------------------------------------------ tests

test "sqrt" {
    try testing.expectEqual(@as(f64, 3), try sqrt(9));
    try testing.expectEqual(@as(f64, 0), try sqrt(0));
    try testing.expectEqual(@as(f64, 0), try sqrt(-0.0));
    try testing.expectError(error.Domain, sqrt(-1));
    try testing.expectError(error.Domain, sqrt(std.math.nan(f64)));
    try testing.expectError(error.Domain, sqrt(std.math.inf(f64)));
}

test "pow" {
    try testing.expectEqual(@as(f64, 1024), try pow(2, 10));
    try testing.expectEqual(@as(f64, 1), try pow(0, 0));
    try testing.expectEqual(@as(f64, 0.25), try pow(2, -2));
    try testing.expectEqual(@as(f64, -8), try pow(-2, 3));
    try testing.expectError(error.Domain, pow(0, -1));
    try testing.expectError(error.Domain, pow(-8, 1.0 / 3.0));
    try testing.expectError(error.Domain, pow(10, 400));
}

test "sign" {
    try testing.expectEqual(@as(f64, 1), sign(5));
    try testing.expectEqual(@as(f64, 1), sign(1e-300));
    try testing.expectEqual(@as(f64, -1), sign(-0.5));
    try testing.expectEqual(@as(f64, 0), sign(0));
    try testing.expectEqual(@as(f64, 0), sign(-0.0));
    try testing.expectEqual(@as(f64, 0), sign(std.math.nan(f64)));
}

test "sin and cos exact at multiples of pi / 2" {
    const pi = std.math.pi;
    try testing.expectEqual(@as(f64, 0), try sin(0));
    try testing.expectEqual(@as(f64, 1), try sin(pi / 2.0));
    try testing.expectEqual(@as(f64, 0), try sin(pi));
    try testing.expectEqual(@as(f64, -1), try sin(3.0 * pi / 2.0));
    try testing.expectEqual(@as(f64, 0), try sin(2.0 * pi));
    try testing.expectEqual(@as(f64, -1), try sin(-pi / 2.0));
    try testing.expectEqual(@as(f64, 0), try sin(-4.0 * pi));
    try testing.expectEqual(@as(f64, 1), try cos(0));
    try testing.expectEqual(@as(f64, 0), try cos(pi / 2.0));
    try testing.expectEqual(@as(f64, -1), try cos(pi));
    try testing.expectEqual(@as(f64, 0), try cos(-pi / 2.0));
    try testing.expectEqual(@as(f64, 1), try cos(2.0 * pi));
}

test "sin and cos general values in radians" {
    const pi = std.math.pi;
    try testing.expectApproxEqAbs(@as(f64, 0.5), try sin(pi / 6.0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -0.5), try sin(7.0 * pi / 6.0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.5), try cos(-pi / 3.0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.8414709848078965), try sin(1), 1e-15);
    try testing.expectApproxEqAbs(@as(f64, 0.5403023058681398), try cos(1), 1e-15);
    try testing.expectApproxEqRel(@as(f64, -1e-12), try sin(-1e-12), 1e-9);
    try testing.expectError(error.Domain, sin(std.math.inf(f64)));
    try testing.expectError(error.Domain, cos(std.math.nan(f64)));
}

test "large non-multiples are not snapped" {
    const pi = std.math.pi;
    const x = 3000000000.0 * pi / 2.0 + 0.004;
    try testing.expect(@abs(try sin(x)) > 0.003);
    try testing.expectEqual(@as(f64, -1), try sin(7.0 * pi / 2.0));
    try testing.expectEqual(@as(f64, 0), try cos(3.0 * pi / 6.0));
    try testing.expectEqual(@as(f64, 1), try tan(5.0 * pi / 4.0));
}

test "tan exact and poles" {
    const pi = std.math.pi;
    try testing.expectEqual(@as(f64, 0), try tan(0));
    try testing.expectEqual(@as(f64, 1), try tan(pi / 4.0));
    try testing.expectEqual(@as(f64, -1), try tan(3.0 * pi / 4.0));
    try testing.expectEqual(@as(f64, -1), try tan(-pi / 4.0));
    try testing.expectEqual(@as(f64, 0), try tan(pi));
    try testing.expectApproxEqAbs(@as(f64, 1.0 / @sqrt(3.0)), try tan(pi / 6.0), 1e-12);
    try testing.expectError(error.Domain, tan(pi / 2.0));
    try testing.expectError(error.Domain, tan(-pi / 2.0));
    try testing.expectError(error.Domain, tan(3.0 * pi / 2.0));
    try testing.expectError(error.Domain, tan(std.math.nan(f64)));
}

test "results are never negative zero" {
    try testing.expect(!std.math.signbit(try sqrt(-0.0)));
    try testing.expect(!std.math.signbit(try asin(-0.0)));
    try testing.expect(!std.math.signbit(try atan2(-0.0, 1)));
    try testing.expect(!std.math.signbit(try sin(-0.0)));
}

test "asin, acos and atan2 in radians" {
    const pi = std.math.pi;
    try testing.expectApproxEqAbs(pi / 2.0, try asin(1), 1e-15);
    try testing.expectApproxEqAbs(pi / 6.0, try asin(0.5), 1e-15);
    try testing.expectApproxEqAbs(pi, try acos(-1), 1e-15);
    try testing.expectEqual(@as(f64, 0), try acos(1));
    try testing.expectError(error.Domain, asin(1.0000001));
    try testing.expectError(error.Domain, acos(-2));
    try testing.expectApproxEqAbs(pi / 4.0, try atan2(1, 1), 1e-15);
    try testing.expectApproxEqAbs(3.0 * pi / 4.0, try atan2(1, -1), 1e-15);
    try testing.expectApproxEqAbs(-3.0 * pi / 4.0, try atan2(-1, -1), 1e-15);
    try testing.expectEqual(@as(f64, pi), try atan2(0, -1));
    try testing.expectEqual(@as(f64, pi), try atan2(-0.0, -1));
    try testing.expectEqual(@as(f64, 0), try atan2(0, 0));
}

test "deg and rad" {
    try testing.expectApproxEqAbs(@as(f64, 180), try deg(std.math.pi), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, std.math.pi / 2.0), try rad(90), 1e-15);
    try testing.expectApproxEqAbs(@as(f64, 30), try deg(try rad(30)), 1e-12);
}

test "lerp" {
    try testing.expectEqual(@as(f64, 5), try lerp(0, 10, 0.5));
    try testing.expectEqual(@as(f64, 0), try lerp(0, 10, 0));
    try testing.expectEqual(@as(f64, 10), try lerp(0, 10, 1));
    try testing.expectEqual(@as(f64, 20), try lerp(0, 10, 2));
    try testing.expectEqual(@as(f64, -10), try lerp(0, 10, -1));
    try testing.expectEqual(@as(f64, 7.5), try lerp(10, 0, 0.25));
    try testing.expectEqual(@as(f64, 1), try lerp(1, 1, 123));
    try testing.expectError(error.Domain, lerp(-1e308, 1e308, 0.5));
    try testing.expectError(error.Domain, lerp(0, 1, std.math.nan(f64)));
}

test "remap" {
    try testing.expectEqual(@as(f64, 50), try remap(5, 0, 10, 0, 100));
    try testing.expectEqual(@as(f64, 150), try remap(15, 0, 10, 0, 100));
    try testing.expectEqual(@as(f64, -50), try remap(-5, 0, 10, 0, 100));
    try testing.expectEqual(@as(f64, 1), try remap(0, 10, 0, 0, 1));
    try testing.expectEqual(@as(f64, 0), try remap(10, 10, 0, 0, 1));
    try testing.expectEqual(@as(f64, 7), try remap(3, 0, 1, 7, 7));
    try testing.expectError(error.Domain, remap(1, 2, 2, 0, 1));
    try testing.expectError(error.Domain, remap(1, 0, 1e-320, 0, 1e300));
    // Large magnitudes: no overflow in the intermediate product.
    try testing.expectEqual(@as(f64, 1e200), try remap(1e200, 0, 1e200, 0, 1e200));
}

test "wrap precision for large values" {
    // 1e300 is an integer in binary; its exact remainder mod 7 is 1.
    try testing.expectEqual(@as(f64, 1), try wrap(1e300, 7));
    try testing.expectEqual(@as(f64, 6), try wrap(-1e300, 7));
}

test "wrap" {
    try testing.expectEqual(@as(f64, 10), try wrap(370, 360));
    try testing.expectEqual(@as(f64, 350), try wrap(-10, 360));
    try testing.expectEqual(@as(f64, 0), try wrap(360, 360));
    try testing.expectEqual(@as(f64, 0), try wrap(-720, 360));
    try testing.expectEqual(@as(f64, 1.5), try wrap(5.5, 2));
    try testing.expectEqual(@as(f64, 3), try wrap(3, 5));
    try testing.expectEqual(@as(f64, 0), try wrap(0, 5));
    // Negative modulus: result in (n, 0].
    try testing.expectEqual(@as(f64, -2), try wrap(1, -3));
    try testing.expectError(error.Domain, wrap(1, 0));
    try testing.expectError(error.Domain, wrap(std.math.inf(f64), 3));
    try testing.expectError(error.Domain, wrap(1, std.math.nan(f64)));
}

test "wrap stays in [0, n) over many inputs" {
    var prng = std.Random.DefaultPrng.init(11);
    const rnd = prng.random();
    const moduli = [_]f64{ 1, 7, 360, 0.1, 2.5 };
    for (moduli) |n| {
        for (0..2000) |_| {
            const v = rnd.float(f64) * 4000 - 2000;
            const r = try wrap(v, n);
            try testing.expect(r >= 0 and r < n);
        }
    }
    // A tiny negative input would round up to n without the guard.
    try testing.expectEqual(@as(f64, 0), try wrap(-1e-20, 360));
}
