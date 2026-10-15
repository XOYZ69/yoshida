//! Seeded pseudo-random built-ins. The same seed values always give the same
//! number, so a card renders the same every time.

const std = @import("std");
const value = @import("../value.zig");
const testing = std.testing;
const Value = value.Value;
const Color = value.Color;

pub const Error = error{
    /// Argument out of range: `int` with lo > hi, or a non-finite bound.
    Range,
};

const fnv_offset: u64 = 0xcbf29ce484222325;
const fnv_prime: u64 = 0x100000001b3;

/// Canonical bits of NaN, so every NaN hashes the same.
const canonical_nan_bits: u64 = 0x7ff8000000000000;

fn fnvBytes(h: u64, bytes: []const u8) u64 {
    var out = h;
    for (bytes) |b| {
        out ^= b;
        out *%= fnv_prime;
    }
    return out;
}

fn fnvInt(comptime T: type, h: u64, x: T) u64 {
    var buf: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buf, x, .little);
    return fnvBytes(h, &buf);
}

/// Feeds one value into the running hash. Each value starts with a type tag byte.
fn feed(h: u64, v: Value) u64 {
    return switch (v) {
        .number => |x| blk: {
            // -0 is 0, and every NaN is the same NaN, so equal numbers hash equally.
            const canon: f64 = if (std.math.isNan(x)) @bitCast(canonical_nan_bits) else if (x == 0) 0 else x;
            break :blk fnvInt(u64, fnvBytes(h, &.{1}), @bitCast(canon));
        },
        .bool => |x| fnvBytes(h, &.{ 2, @intFromBool(x) }),
        .text, .image => |s| fnvBytes(fnvInt(u32, fnvBytes(h, &.{3}), @truncate(s.len)), s),
        .color => |c| blk: {
            var out = fnvBytes(h, &.{4});
            out = fnvInt(u16, out, c.r);
            out = fnvInt(u16, out, c.g);
            out = fnvInt(u16, out, c.b);
            break :blk fnvInt(u16, out, c.a);
        },
        .list => |items| blk: {
            // Lists are not seedable in the expression language; hashed for completeness.
            var out = fnvInt(u32, fnvBytes(h, &.{5}), @truncate(items.len));
            for (items) |fields| {
                out = fnvInt(u32, out, @truncate(fields.len));
                for (fields) |f| out = feed(out, f);
            }
            break :blk out;
        },
        .item => |fields| blk: {
            var out = fnvInt(u32, fnvBytes(h, &.{6}), @truncate(fields.len));
            for (fields) |f| out = feed(out, f);
            break :blk out;
        },
    };
}

/// splitmix64 finaliser: spreads every input bit over the output.
fn mix(x: u64) u64 {
    var z = x;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

/// 64-bit hash of a list of values. FNV-1a over a canonical encoding, then mixed.
pub fn hash(vals: []const Value) u64 {
    var h: u64 = fnv_offset;
    for (vals) |v| h = feed(h, v);
    return mix(h);
}

/// A pseudo-random number in [0, 1), from the hash of `vals`.
pub fn unit(vals: []const Value) f64 {
    return @as(f64, @floatFromInt(hash(vals) >> 11)) * 0x1p-53;
}

/// A pseudo-random whole number in [lo, hi] (both bounds floored). `lo > hi` is a Range error.
pub fn int(lo: f64, hi: f64, vals: []const Value) Error!f64 {
    const a = @floor(lo);
    const b = @floor(hi);
    if (!std.math.isFinite(a) or !std.math.isFinite(b) or a > b) return error.Range;
    const n = b - a + 1;
    if (!std.math.isFinite(n)) return error.Range;
    const r = a + @floor(unit(vals) * n);
    return @min(b, @max(a, r));
}

/// A pseudo-random index in [0, n). `n == 0` gives 0.
pub fn pickIndex(vals: []const Value, n: usize) usize {
    if (n == 0) return 0;
    const i: usize = @intFromFloat(@floor(unit(vals) * @as(f64, @floatFromInt(n))));
    return @min(i, n - 1);
}

// ------------------------------------------------------------------ tests

test "hash is stable for the same values" {
    const vals = [_]Value{ .{ .text = "a" }, .{ .number = 1 } };
    try testing.expectEqual(hash(&vals), hash(&vals));
    try testing.expectEqual(unit(&vals), unit(&vals));
}

test "hash separates values of different types" {
    const num = [_]Value{.{ .number = 1 }};
    const boolean = [_]Value{.{ .bool = true }};
    const text = [_]Value{.{ .text = "1" }};
    const color = [_]Value{.{ .color = Color.white }};
    try testing.expect(hash(&num) != hash(&boolean));
    try testing.expect(hash(&num) != hash(&text));
    try testing.expect(hash(&boolean) != hash(&text));
    try testing.expect(hash(&color) != hash(&text));
    // Text and image hash alike: they are the same kind of string.
    const img = [_]Value{.{ .image = "1" }};
    try testing.expectEqual(hash(&text), hash(&img));
}

test "hash keeps order and count" {
    const ab = [_]Value{ .{ .text = "a" }, .{ .text = "b" } };
    const ba = [_]Value{ .{ .text = "b" }, .{ .text = "a" } };
    try testing.expect(hash(&ab) != hash(&ba));
    // Text boundaries count: "ab" + "" differs from "a" + "b".
    const joined = [_]Value{.{ .text = "ab" }};
    const split = [_]Value{ .{ .text = "a" }, .{ .text = "b" } };
    try testing.expect(hash(&joined) != hash(&split));
    try testing.expect(hash(&[_]Value{}) != hash(&[_]Value{.{ .text = "" }}));
}

test "hash normalises -0 and NaN" {
    const pos = [_]Value{.{ .number = 0.0 }};
    const neg = [_]Value{.{ .number = -0.0 }};
    try testing.expectEqual(hash(&pos), hash(&neg));
    try testing.expectEqual(unit(&pos), unit(&neg));

    const nan_a = [_]Value{.{ .number = std.math.nan(f64) }};
    const nan_b = [_]Value{.{ .number = -std.math.nan(f64) }};
    const nan_c = [_]Value{.{ .number = @bitCast(@as(u64, 0x7ff0000000000001)) }};
    try testing.expectEqual(hash(&nan_a), hash(&nan_b));
    try testing.expectEqual(hash(&nan_a), hash(&nan_c));
    // Other numbers still differ.
    try testing.expect(hash(&pos) != hash(&[_]Value{.{ .number = 1 }}));
}

test "hash of lists and items" {
    const f1 = [_]Value{ .{ .number = 1 }, .{ .text = "x" } };
    const f2 = [_]Value{ .{ .number = 2 }, .{ .text = "y" } };
    const rows = [_][]const Value{ &f1, &f2 };
    const list: Value = .{ .list = &rows };
    const item: Value = .{ .item = &f1 };
    try testing.expect(hash(&[_]Value{list}) != hash(&[_]Value{item}));
    try testing.expect(hash(&[_]Value{list}) != hash(&[_]Value{.{ .list = &.{} }}));
    try testing.expectEqual(hash(&[_]Value{list}), hash(&[_]Value{list}));
}

test "unit pinned outputs" {
    // Fixed outputs: a change here means every seeded card would render differently.
    try testing.expectEqual(@as(f64, 0.13942925586746246), unit(&[_]Value{.{ .text = "a" }}));
    try testing.expectEqual(@as(f64, 0.56576324690047990), unit(&[_]Value{.{ .number = 1 }}));
    try testing.expectEqual(@as(f64, 0.23649031199485926), unit(&[_]Value{ .{ .number = 1 }, .{ .text = "x" } }));
    try testing.expectEqual(@as(f64, 0.74110030067418820), unit(&[_]Value{.{ .bool = true }}));
    try testing.expectEqual(@as(f64, 0.61994599552676120), unit(&[_]Value{ .{ .text = "card" }, .{ .number = 42 }, .{ .bool = false } }));
    try testing.expectEqual(@as(f64, 0.64233827078993540), unit(&[_]Value{.{ .color = Color.white }}));
    try testing.expectEqual(@as(f64, 0.91684615090121710), unit(&[_]Value{.{ .text = "" }}));
    try testing.expectEqual(@as(f64, 0.95767342524205610), unit(&[_]Value{}));
}

test "unit is in [0, 1)" {
    var buf: [64]Value = undefined;
    for (0..2000) |i| {
        buf[0] = .{ .number = @floatFromInt(i) };
        const u = unit(buf[0..1]);
        try testing.expect(u >= 0 and u < 1);
    }
}

test "int stays within bounds over many seeds" {
    var seen_lo = false;
    var seen_hi = false;
    for (0..3000) |i| {
        const vals = [_]Value{.{ .number = @floatFromInt(i) }};
        const r = try int(-3, 7, &vals);
        try testing.expect(r >= -3 and r <= 7);
        try testing.expectEqual(@floor(r), r);
        if (r == -3) seen_lo = true;
        if (r == 7) seen_hi = true;
    }
    try testing.expect(seen_lo and seen_hi);
}

test "int floors its bounds and handles equal bounds" {
    const vals = [_]Value{.{ .text = "k" }};
    try testing.expectEqual(@as(f64, 4), try int(4, 4, &vals));
    try testing.expectEqual(@as(f64, 0), try int(0.9, 0.1, &vals));
    try testing.expectEqual(@as(f64, -2), try int(-1.5, -1.2, &vals));
    for (0..500) |i| {
        const v = [_]Value{.{ .number = @floatFromInt(i) }};
        const r = try int(0.5, 2.9, &v);
        try testing.expect(r >= 0 and r <= 2);
    }
}

test "int invalid bounds" {
    const vals = [_]Value{};
    try testing.expectError(error.Range, int(5, 1, &vals));
    try testing.expectError(error.Range, int(std.math.nan(f64), 1, &vals));
    try testing.expectError(error.Range, int(0, std.math.inf(f64), &vals));
    try testing.expectError(error.Range, int(-std.math.inf(f64), 0, &vals));
    try testing.expectError(error.Range, int(-1e308, 1e308, &vals));
}

test "pickIndex stays below n" {
    try testing.expectEqual(@as(usize, 0), pickIndex(&[_]Value{}, 0));
    for (0..1000) |i| {
        const v = [_]Value{.{ .number = @floatFromInt(i) }};
        try testing.expectEqual(@as(usize, 0), pickIndex(&v, 1));
        try testing.expect(pickIndex(&v, 5) < 5);
    }
}

test "pickIndex covers every choice" {
    var counts = [_]usize{0} ** 4;
    for (0..2000) |i| {
        const v = [_]Value{.{ .number = @floatFromInt(i) }};
        counts[pickIndex(&v, 4)] += 1;
    }
    for (counts) |c| try testing.expect(c > 300);
}
