//! Colour built-ins over `value.Color` (16-bit, straight alpha). Hue is in degrees.

const std = @import("std");
const value = @import("../value.zig");
const testing = std.testing;
const Color = value.Color;

/// Colour functions cannot fail; the set is empty so callers can treat every module alike.
pub const Error = error{};

/// Clamps to [lo, hi]; NaN becomes `lo`.
fn clampTo(x: f64, lo: f64, hi: f64) f64 {
    if (std.math.isNan(x)) return lo;
    return std.math.clamp(x, lo, hi);
}

/// A unit float as a 16-bit channel, rounded to nearest (the same as `rgb()`).
fn unit16(x: f64) u16 {
    return @intFromFloat(@round(std.math.clamp(x, 0, 1) * 65535));
}

/// An 8-bit channel (0..1 scale) as a 16-bit one, on the same lattice as `rgb()`.
fn chan8(x: f64) u16 {
    return @as(u16, @intFromFloat(@round(std.math.clamp(x, 0, 1) * 255))) * 257;
}

/// Red, green and blue in 0..1 from HSL: `h` degrees (wrapped; non-finite is 0),
/// `s` and `l` in 0..100 (clamped; NaN is 0). Full precision, not yet quantised.
fn hslRgb(h: f64, s: f64, l: f64) [3]f64 {
    const hue = if (std.math.isFinite(h)) @mod(h, 360.0) else 0;
    const sat = clampTo(s, 0, 100) / 100;
    const lig = clampTo(l, 0, 100) / 100;

    const chroma = (1 - @abs(2 * lig - 1)) * sat;
    const hp = hue / 60.0;
    const x = chroma * (1 - @abs(@mod(hp, 2.0) - 1));
    // hp can be exactly 6 when the hue rounds up to 360.
    const sector: u32 = @min(5, @as(u32, @intFromFloat(@floor(hp))));
    const ch: [3]f64 = switch (sector) {
        0 => .{ chroma, x, 0 },
        1 => .{ x, chroma, 0 },
        2 => .{ 0, chroma, x },
        3 => .{ 0, x, chroma },
        4 => .{ x, 0, chroma },
        else => .{ chroma, 0, x },
    };
    const m = lig - chroma / 2;
    return .{ ch[0] + m, ch[1] + m, ch[2] + m };
}

/// Colour from HSL: `h` degrees (wrapped), s and l in 0..100, a in 0..1, all clamped.
/// Channels land on the 8-bit grid like `rgb()`, so `hsl(0, 100, 75)` equals `rgb(255, 128, 128)`.
pub fn hsl(h: f64, s: f64, l: f64, a: f64) Color {
    const c = hslRgb(h, s, l);
    return .{
        .r = chan8(c[0]),
        .g = chan8(c[1]),
        .b = chan8(c[2]),
        // Alpha on the 8-bit grid like rgba(), so hsla(...) == #RRGGBBAA holds.
        .a = @as(u16, @intFromFloat(@round(clampTo(a, 0, 1) * 255))) * 257,
    };
}

/// Hue (degrees), saturation (0..100) and lightness (0..100) of `c`.
fn toHsl(c: Color) [3]f64 {
    const r = @as(f64, @floatFromInt(c.r)) / 65535.0;
    const g = @as(f64, @floatFromInt(c.g)) / 65535.0;
    const b = @as(f64, @floatFromInt(c.b)) / 65535.0;
    const mx = @max(r, @max(g, b));
    const mn = @min(r, @min(g, b));
    const d = mx - mn;
    const l = (mx + mn) / 2;
    if (d == 0) return .{ 0, 0, l * 100 };
    const s = d / (1 - @abs(2 * l - 1));
    const h = if (mx == r)
        60 * @mod((g - b) / d, 6)
    else if (mx == g)
        60 * ((b - r) / d + 2)
    else
        60 * ((r - g) / d + 4);
    return .{ h, s * 100, l * 100 };
}

/// Adds `delta` (0..100 lightness points) to `c`, clamped. Hue, saturation and alpha are kept.
/// Stays at 16-bit precision, so repeated shifts do not quantise to 8 bits.
fn shift(c: Color, delta: f64) Color {
    const step = if (std.math.isNan(delta)) 0 else delta;
    const hsv = toHsl(c);
    const ch = hslRgb(hsv[0], hsv[1], clampTo(hsv[2] + step, 0, 100));
    return .{ .r = unit16(ch[0]), .g = unit16(ch[1]), .b = unit16(ch[2]), .a = c.a };
}

/// `c` with its lightness raised by `amount` (0..100 scale).
pub fn lighten(c: Color, amount: f64) Color {
    return shift(c, amount);
}

/// `c` with its lightness lowered by `amount` (0..100 scale).
pub fn darken(c: Color, amount: f64) Color {
    return shift(c, -amount);
}

/// One channel (16-bit) as linear light, per WCAG 2.
fn linear(v: u16) f64 {
    const s = @as(f64, @floatFromInt(v)) / 65535.0;
    if (s <= 0.03928) return s / 12.92;
    return std.math.pow(f64, (s + 0.055) / 1.055, 2.4);
}

/// WCAG 2 relative luminance in 0..1. Alpha is ignored.
pub fn luminance(c: Color) f64 {
    return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
}

/// WCAG contrast ratio of two luminances, always >= 1.
fn contrast(a: f64, b: f64) f64 {
    return (@max(a, b) + 0.05) / (@min(a, b) + 0.05);
}

/// `light` when its contrast against `bg` is at least that of `dark`, otherwise `dark`.
pub fn readable(bg: Color, light: Color, dark: Color) Color {
    const lb = luminance(bg);
    const ratio_light = contrast(lb, luminance(light));
    const ratio_dark = contrast(lb, luminance(dark));
    return if (ratio_light >= ratio_dark) light else dark;
}

// ------------------------------------------------------------------ tests

fn rgb(r: u16, g: u16, b: u16) Color {
    return .{ .r = r, .g = g, .b = b, .a = 65535 };
}

test "hsl primary colours" {
    try testing.expect(hsl(0, 100, 50, 1).eql(rgb(65535, 0, 0)));
    try testing.expect(hsl(60, 100, 50, 1).eql(rgb(65535, 65535, 0)));
    try testing.expect(hsl(120, 100, 50, 1).eql(rgb(0, 65535, 0)));
    try testing.expect(hsl(180, 100, 50, 1).eql(rgb(0, 65535, 65535)));
    try testing.expect(hsl(240, 100, 50, 1).eql(rgb(0, 0, 65535)));
    try testing.expect(hsl(300, 100, 50, 1).eql(rgb(65535, 0, 65535)));
}

test "hsl dark and light shades" {
    // l = 25: chroma 0.5, so the green channel is 127.5 -> 128 on the 8-bit grid.
    try testing.expect(hsl(120, 100, 25, 1).eql(rgb(0, 32896, 0)));
    try testing.expect(hsl(0, 100, 75, 1).eql(rgb(65535, 32896, 32896)));
    try testing.expect(hsl(0, 100, 0, 1).eql(rgb(0, 0, 0)));
    try testing.expect(hsl(0, 100, 100, 1).eql(rgb(65535, 65535, 65535)));
}

test "hsl matches rgb() on the 8-bit grid" {
    // rgb() scales 0..255 by 257; hsl() must produce the same channel values.
    try testing.expect(hsl(0, 100, 75, 1).eql(rgb(255 * 257, 128 * 257, 128 * 257)));
    try testing.expect(hsl(0, 100, 75, 1).eql(rgb(65535, 32896, 32896)));
    try testing.expect(hsl(120, 100, 25, 1).eql(rgb(0, 128 * 257, 0)));
}

test "lighten round trips do not quantise to 8 bits" {
    // An 8-bit round trip would drift by up to 128 units per channel.
    var c = rgb(12345, 54321, 999);
    const start = c;
    for (0..20) |_| c = lighten(c, 0);
    try testing.expect(@abs(@as(i32, c.r) - @as(i32, start.r)) <= 20);
    try testing.expect(@abs(@as(i32, c.g) - @as(i32, start.g)) <= 20);
    try testing.expect(@abs(@as(i32, c.b) - @as(i32, start.b)) <= 20);
}

test "hsl grey when saturation is zero" {
    try testing.expect(hsl(42, 0, 50, 1).eql(rgb(32896, 32896, 32896)));
    try testing.expect(hsl(0, 0, 0, 1).eql(Color.black));
    try testing.expect(hsl(77, 0, 100, 1).eql(Color.white));
}

test "hsl hue wraps" {
    try testing.expect(hsl(360, 100, 50, 1).eql(hsl(0, 100, 50, 1)));
    try testing.expect(hsl(-120, 100, 50, 1).eql(hsl(240, 100, 50, 1)));
    try testing.expect(hsl(480, 100, 50, 1).eql(hsl(120, 100, 50, 1)));
    // A tiny negative hue rounds to 360 in the modulo; it must still land in a sector.
    _ = hsl(-1e-20, 100, 50, 1);
}

test "hsl clamps and handles invalid numbers" {
    try testing.expect(hsl(0, 200, 50, 1).eql(hsl(0, 100, 50, 1)));
    try testing.expect(hsl(0, -5, 50, 1).eql(hsl(0, 0, 50, 1)));
    try testing.expect(hsl(0, 100, 150, 1).eql(Color.white));
    try testing.expect(hsl(0, 100, -10, 1).eql(Color.black));
    try testing.expect(hsl(std.math.nan(f64), 100, 50, 1).eql(hsl(0, 100, 50, 1)));
    try testing.expect(hsl(std.math.inf(f64), 100, 50, 1).eql(hsl(0, 100, 50, 1)));
    try testing.expect(hsl(0, std.math.nan(f64), 50, 1).eql(hsl(0, 0, 50, 1)));
    try testing.expect(hsl(0, 100, std.math.inf(f64), 1).eql(Color.white));
}

test "hsl alpha" {
    try testing.expectEqual(@as(u16, 65535), hsl(0, 100, 50, 1).a);
    try testing.expectEqual(@as(u16, 32896), hsl(0, 100, 50, 0.5).a);
    try testing.expectEqual(@as(u16, 0), hsl(0, 100, 50, 0).a);
    try testing.expectEqual(@as(u16, 65535), hsl(0, 100, 50, 2).a);
    try testing.expectEqual(@as(u16, 0), hsl(0, 100, 50, -1).a);
}

test "lighten and darken move lightness" {
    const red = rgb(65535, 0, 0);
    const up = lighten(red, 25);
    const hsv = toHsl(up);
    try testing.expectApproxEqAbs(@as(f64, 75), hsv[2], 0.01);
    try testing.expectApproxEqAbs(@as(f64, 0), hsv[0], 0.01);
    try testing.expectApproxEqAbs(@as(f64, 100), hsv[1], 0.01);

    const down = darken(red, 25);
    try testing.expectApproxEqAbs(@as(f64, 25), toHsl(down)[2], 0.01);
    try testing.expect(down.r < red.r);
    try testing.expectEqual(@as(u16, 0), down.g);
}

test "lighten and darken clamp and keep alpha" {
    const c: Color = .{ .r = 65535, .g = 0, .b = 0, .a = 1000 };
    try testing.expect(lighten(c, 500).eql(.{ .r = 65535, .g = 65535, .b = 65535, .a = 1000 }));
    try testing.expect(darken(c, 500).eql(.{ .r = 0, .g = 0, .b = 0, .a = 1000 }));
    try testing.expectEqual(@as(u16, 1000), lighten(c, 10).a);
    try testing.expectEqual(@as(u16, 1000), darken(c, 10).a);
    // Negative amounts move the other way.
    try testing.expect(lighten(c, -10).eql(darken(c, 10)));
    // Not a number changes nothing.
    try testing.expect(lighten(c, std.math.nan(f64)).eql(lighten(c, 0)));
}

test "lighten by zero is close to the input" {
    const samples = [_]Color{
        rgb(65535, 0, 0),
        rgb(12345, 54321, 999),
        rgb(0, 0, 0),
        rgb(65535, 65535, 65535),
    };
    for (samples) |c| {
        const back = lighten(c, 0);
        try testing.expect(@abs(@as(i32, back.r) - @as(i32, c.r)) <= 2);
        try testing.expect(@abs(@as(i32, back.g) - @as(i32, c.g)) <= 2);
        try testing.expect(@abs(@as(i32, back.b) - @as(i32, c.b)) <= 2);
    }
}

test "luminance of primaries and grey" {
    try testing.expectEqual(@as(f64, 0), luminance(Color.black));
    try testing.expectApproxEqAbs(@as(f64, 1), luminance(Color.white), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.2126), luminance(rgb(65535, 0, 0)), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.7152), luminance(rgb(0, 65535, 0)), 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.0722), luminance(rgb(0, 0, 65535)), 1e-12);
    // Mid grey, sRGB 0x80 (about 0.2159 linear).
    try testing.expectApproxEqAbs(@as(f64, 0.2159), luminance(rgb(32896, 32896, 32896)), 1e-3);
}

test "luminance ignores alpha" {
    const solid = rgb(10000, 20000, 30000);
    const clear: Color = .{ .r = 10000, .g = 20000, .b = 30000, .a = 0 };
    try testing.expectEqual(luminance(solid), luminance(clear));
}

test "readable picks the higher contrast colour" {
    // Dark background: white text.
    try testing.expect(readable(Color.black, Color.white, Color.black).eql(Color.white));
    try testing.expect(readable(rgb(0, 0, 32768), Color.white, Color.black).eql(Color.white));
    // Light background: black text.
    try testing.expect(readable(Color.white, Color.white, Color.black).eql(Color.black));
    try testing.expect(readable(rgb(65535, 65535, 0), Color.white, Color.black).eql(Color.black));
    // Mid greys: #444 is dark enough for white, #777 is not.
    const dark_grey = Color.parseHex("#444444").?;
    const mid_grey = Color.parseHex("#777777").?;
    try testing.expect(readable(dark_grey, Color.white, Color.black).eql(Color.white));
    try testing.expect(readable(mid_grey, Color.white, Color.black).eql(Color.black));
}

test "readable returns one of its arguments unchanged" {
    const a = rgb(1, 2, 3);
    const b = rgb(4, 5, 6);
    const r = readable(Color.black, a, b);
    try testing.expect(r.eql(a) or r.eql(b));
    // Yellow beats navy on black, and navy beats yellow on white.
    const yellow = rgb(65535, 65535, 0);
    const navy = rgb(0, 0, 32768);
    try testing.expect(readable(Color.black, yellow, navy).eql(yellow));
    try testing.expect(readable(Color.white, yellow, navy).eql(navy));
    // Equal candidates always return one of them.
    try testing.expect(readable(Color.black, b, b).eql(b));
}
