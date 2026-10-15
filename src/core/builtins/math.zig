//! Numeric built-ins. Angles are degrees. Pure: no allocation, no expression types.

const std = @import("std");
const testing = std.testing;

pub const Error = error{
    /// Division by zero, a result that is not finite, or an argument outside the domain.
    Domain,
};

const deg_to_rad = std.math.pi / 180.0;
const rad_to_deg = 180.0 / std.math.pi;

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

/// Reduces degrees to (-360, 360). `@rem` is exact, so small negative angles keep precision.
/// Non-finite input is a Domain error.
fn reduce(d: f64) Error!f64 {
    return finite(@rem(d, 360.0));
}

/// Index 0..3 when `r` (in (-360, 360)) is a multiple of 90 degrees, folded to [0, 360).
fn quarter(r: f64) ?usize {
    const k = r / 90.0;
    if (k != @floor(k)) return null;
    const m: usize = @intCast(@mod(@as(i32, @intFromFloat(k)), 4));
    return m;
}

/// Sine of `d` degrees. Exact at multiples of 90.
pub fn sin(d: f64) Error!f64 {
    const r = try reduce(d);
    if (quarter(r)) |q| {
        const table = [4]f64{ 0, 1, 0, -1 };
        return table[q];
    }
    return finite(std.math.sin(r * deg_to_rad));
}

/// Cosine of `d` degrees. Exact at multiples of 90.
pub fn cos(d: f64) Error!f64 {
    const r = try reduce(d);
    if (quarter(r)) |q| {
        const table = [4]f64{ 1, 0, -1, 0 };
        return table[q];
    }
    return finite(std.math.cos(r * deg_to_rad));
}

/// Tangent of `d` degrees. Exact at multiples of 45. At 90 + k * 180 it is a Domain error.
pub fn tan(d: f64) Error!f64 {
    const r = try reduce(d);
    const k = r / 45.0;
    if (k == @floor(k)) {
        // Index is the multiple of 45 modulo 360; null marks the poles at 90 and 270.
        const exact = [8]?f64{ 0, 1, null, -1, 0, 1, null, -1 };
        const m: usize = @intCast(@mod(@as(i32, @intFromFloat(k)), 8));
        return exact[m] orelse error.Domain;
    }
    return finite(std.math.tan(r * deg_to_rad));
}

/// Arc sine in degrees. `|x| > 1` is a Domain error.
pub fn asin(x: f64) Error!f64 {
    if (@abs(x) > 1) return error.Domain;
    return finite(std.math.asin(x) * rad_to_deg);
}

/// Arc cosine in degrees. `|x| > 1` is a Domain error.
pub fn acos(x: f64) Error!f64 {
    if (@abs(x) > 1) return error.Domain;
    return finite(std.math.acos(x) * rad_to_deg);
}

/// Angle of the point (x, y) in degrees, in (-180, 180]. `atan2(0, 0) == 0`.
pub fn atan2(y: f64, x: f64) Error!f64 {
    if (y == 0 and x == 0) return 0;
    var d = std.math.atan2(y, x) * rad_to_deg;
    // The range is (-180, 180]: -180 is 180, and rounding may overshoot 180 slightly.
    if (d > 180 or d <= -180) d = 180;
    return finite(d);
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

test "sin exact at multiples of 90" {
    try testing.expectEqual(@as(f64, 0), try sin(0));
    try testing.expectEqual(@as(f64, 1), try sin(90));
    try testing.expectEqual(@as(f64, 0), try sin(180));
    try testing.expectEqual(@as(f64, -1), try sin(270));
    try testing.expectEqual(@as(f64, 0), try sin(360));
    try testing.expectEqual(@as(f64, -1), try sin(-90));
    try testing.expectEqual(@as(f64, 1), try sin(450));
    try testing.expectEqual(@as(f64, 0), try sin(-720));
}

test "sin and cos keep precision for small and negative angles" {
    // Relative error stays tiny: the old modulo reduction lost it near zero.
    const want = -1e-12 * std.math.pi / 180.0;
    try testing.expectApproxEqRel(want, try sin(-1e-12), 1e-9);
    try testing.expectEqual(@as(f64, -1), try sin(-90));
    try testing.expectEqual(@as(f64, 0), try sin(-180));
    try testing.expectEqual(@as(f64, 0), try sin(-360));
    try testing.expectApproxEqAbs(@as(f64, -0.5), try sin(-30), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.5), try cos(-60), 1e-12);
    try testing.expectEqual(@as(f64, 0), try cos(-270));
    try testing.expectEqual(@as(f64, 1), try cos(-720));
}

test "tan for negative angles" {
    try testing.expectEqual(@as(f64, 1), try tan(-135));
    try testing.expectEqual(@as(f64, -1), try tan(-45));
    try testing.expectEqual(@as(f64, 0), try tan(-180));
    try testing.expectError(error.Domain, tan(-270));
    try testing.expectError(error.Domain, tan(-450));
}

test "results are never negative zero" {
    try testing.expect(!std.math.signbit(try sqrt(-0.0)));
    try testing.expect(!std.math.signbit(try asin(-0.0)));
    try testing.expect(!std.math.signbit(try atan2(-0.0, 1)));
    try testing.expect(!std.math.signbit(try sin(-0.0)));
    try testing.expect(!std.math.signbit(try lerp(-0.0, 0, 0.5)));
}

test "sin general values" {
    try testing.expectApproxEqAbs(@as(f64, 0.5), try sin(30), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -0.5), try sin(210), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, std.math.sqrt(0.5)), try sin(45), 1e-12);
    try testing.expectError(error.Domain, sin(std.math.inf(f64)));
    try testing.expectError(error.Domain, sin(std.math.nan(f64)));
}

test "cos exact at multiples of 90" {
    try testing.expectEqual(@as(f64, 1), try cos(0));
    try testing.expectEqual(@as(f64, 0), try cos(90));
    try testing.expectEqual(@as(f64, -1), try cos(180));
    try testing.expectEqual(@as(f64, 0), try cos(270));
    try testing.expectEqual(@as(f64, 1), try cos(360));
    try testing.expectEqual(@as(f64, -1), try cos(-180));
    try testing.expectEqual(@as(f64, 0), try cos(-90));
}

test "cos general values" {
    try testing.expectApproxEqAbs(@as(f64, 0.5), try cos(60), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -0.5), try cos(120), 1e-12);
    try testing.expectError(error.Domain, cos(std.math.inf(f64)));
}

test "tan exact and poles" {
    try testing.expectEqual(@as(f64, 0), try tan(0));
    try testing.expectEqual(@as(f64, 1), try tan(45));
    try testing.expectEqual(@as(f64, -1), try tan(135));
    try testing.expectEqual(@as(f64, 1), try tan(225));
    try testing.expectEqual(@as(f64, -1), try tan(315));
    try testing.expectEqual(@as(f64, 0), try tan(180));
    try testing.expectEqual(@as(f64, 0), try tan(-360));
    try testing.expectApproxEqAbs(@as(f64, 1.0 / @sqrt(3.0)), try tan(30), 1e-12);
    try testing.expectError(error.Domain, tan(90));
    try testing.expectError(error.Domain, tan(270));
    try testing.expectError(error.Domain, tan(-90));
    try testing.expectError(error.Domain, tan(450));
    try testing.expectError(error.Domain, tan(std.math.nan(f64)));
}

test "asin and acos in degrees" {
    try testing.expectApproxEqAbs(@as(f64, 0), try asin(0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 90), try asin(1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -90), try asin(-1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 30), try asin(0.5), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0), try acos(1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 90), try acos(0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 180), try acos(-1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 60), try acos(0.5), 1e-12);
    try testing.expectError(error.Domain, asin(1.5));
    try testing.expectError(error.Domain, asin(-1.0000001));
    try testing.expectError(error.Domain, acos(-2));
    try testing.expectError(error.Domain, acos(std.math.nan(f64)));
}

test "atan2 in degrees" {
    try testing.expectApproxEqAbs(@as(f64, 0), try atan2(0, 1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 90), try atan2(1, 0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 180), try atan2(0, -1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -90), try atan2(-1, 0), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 45), try atan2(1, 1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, -135), try atan2(-1, -1), 1e-12);
}

test "atan2 range is (-180, 180]" {
    // Negative zero on the negative x axis would give -180 in radians.
    try testing.expectApproxEqAbs(@as(f64, 180), try atan2(-0.0, -1), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 180), try atan2(-1e-300, -1), 1e-9);
    try testing.expectEqual(@as(f64, 0), try atan2(0, 0));
    try testing.expectEqual(@as(f64, 0), try atan2(-0.0, 0));
    try testing.expectEqual(@as(f64, 0), try atan2(0, -0.0));
    try testing.expectError(error.Domain, atan2(std.math.nan(f64), 1));

    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    for (0..2000) |_| {
        const y = rnd.float(f64) * 20 - 10;
        const x = rnd.float(f64) * 20 - 10;
        const d = try atan2(y, x);
        try testing.expect(d > -180 and d <= 180);
    }
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
