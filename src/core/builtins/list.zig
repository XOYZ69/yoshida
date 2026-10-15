//! List helpers over list items (`[]const []const Value`): lookup, number
//! aggregates, counting and joining. Fields are addressed by index.

const std = @import("std");
const value = @import("../value.zig");
const Value = value.Value;
const Color = value.Color;

pub const Error = error{ Domain, TooLong, OutOfMemory };

/// Longest text result, in bytes.
pub const max_len = 10_000;

/// Index of the first item whose `key_field` text equals `key`.
pub fn indexOf(items: []const []const Value, key_field: usize, key: []const u8) ?usize {
    for (items, 0..) |item, i| {
        if (key_field >= item.len) continue;
        switch (item[key_field]) {
            .text => |s| if (std.mem.eql(u8, s, key)) return i,
            else => {},
        }
    }
    return null;
}

/// Sum of the number field over all items. Other types count as 0.
pub fn sum(items: []const []const Value, field: usize) f64 {
    var total: f64 = 0;
    for (items) |item| total += numberAt(item, field) orelse 0;
    return total;
}

/// Mean of the number field. No numbers, or a non-finite result, is Domain.
pub fn avg(items: []const []const Value, field: usize) Error!f64 {
    var total: f64 = 0;
    var n: usize = 0;
    for (items) |item| {
        if (numberAt(item, field)) |x| {
            total += x;
            n += 1;
        }
    }
    if (n == 0) return error.Domain;
    return finite(total / @as(f64, @floatFromInt(n)));
}

/// Smallest number of the field. No numbers, or any NaN, is Domain.
pub fn minOf(items: []const []const Value, field: usize) Error!f64 {
    var best: ?f64 = null;
    for (items) |item| {
        if (numberAt(item, field)) |x| {
            if (std.math.isNan(x)) return error.Domain;
            if (best == null or x < best.?) best = x;
        }
    }
    return finite(best orelse return error.Domain);
}

/// Largest number of the field. No numbers, or any NaN, is Domain.
pub fn maxOf(items: []const []const Value, field: usize) Error!f64 {
    var best: ?f64 = null;
    for (items) |item| {
        if (numberAt(item, field)) |x| {
            if (std.math.isNan(x)) return error.Domain;
            if (best == null or x > best.?) best = x;
        }
    }
    return finite(best orelse return error.Domain);
}

/// Number of items whose field equals `v`.
pub fn count(items: []const []const Value, field: usize, v: Value) usize {
    var n: usize = 0;
    for (items) |item| {
        if (field < item.len and item[field].eql(v)) n += 1;
    }
    return n;
}

/// Prints the field of each item, separated by `sep`, the way templates print
/// values. Items without the field, and list fields, are skipped. TooLong over
/// `max_len` bytes.
pub fn join(
    arena: std.mem.Allocator,
    items: []const []const Value,
    field: usize,
    sep: []const u8,
) Error![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    var first = true;
    for (items) |item| {
        if (field >= item.len) continue;
        const v = item[field];
        if (!printable(v)) continue;
        if (!first) try append(w, sep);
        first = false;
        try writeValue(w, v);
        if (aw.written().len > max_len) return error.TooLong;
    }
    return aw.written();
}

fn numberAt(item: []const Value, field: usize) ?f64 {
    if (field >= item.len) return null;
    return switch (item[field]) {
        .number => |x| x,
        else => null,
    };
}

fn finite(x: f64) Error!f64 {
    if (!std.math.isFinite(x)) return error.Domain;
    return x;
}

fn printable(v: Value) bool {
    return switch (v) {
        .list, .item => false,
        else => true,
    };
}

fn append(w: *std.Io.Writer, s: []const u8) Error!void {
    w.writeAll(s) catch return error.OutOfMemory;
}

fn writeValue(w: *std.Io.Writer, v: Value) Error!void {
    switch (v) {
        .number => |x| value.writeDisplayNumber(w, x) catch return error.OutOfMemory,
        .bool => |b| try append(w, if (b) "true" else "false"),
        .text, .image => |s| try append(w, s),
        .color => |c| {
            var buf: [9]u8 = undefined;
            try append(w, c.hex8String(&buf));
        },
        .list, .item => unreachable,
    }
}

// ------------------------------------------------------------------ tests

const testing = std.testing;

const red: Color = .{ .r = 65535, .g = 0, .b = 0, .a = 65535 };

// Fields: name (text), cost (number), color (colour), active (bool).
const rifle = [_]Value{ .{ .text = "Rifle" }, .{ .number = 30 }, .{ .color = Color.white }, .{ .bool = true } };
const blade = [_]Value{ .{ .text = "Blade" }, .{ .number = 5 }, .{ .color = red }, .{ .bool = false } };
const shield = [_]Value{ .{ .text = "Shield" }, .{ .number = 12 }, .{ .color = red }, .{ .bool = true } };
const units: []const []const Value = &.{ &rifle, &blade, &shield };
const empty: []const []const Value = &.{};

const half = [_]Value{.{ .number = 0.5 }};
const one = [_]Value{.{ .number = 1 }};
const nums: []const []const Value = &.{ &one, &half };

const inf = [_]Value{.{ .number = std.math.inf(f64) }};
const inf_list: []const []const Value = &.{&inf};

const nan = [_]Value{.{ .number = std.math.nan(f64) }};
const three = [_]Value{.{ .number = 3 }};
const nan_first: []const []const Value = &.{ &nan, &three };
const nan_last: []const []const Value = &.{ &three, &nan };

test "indexOf finds the first match or null" {
    try testing.expectEqual(@as(?usize, 1), indexOf(units, 0, "Blade"));
    try testing.expectEqual(@as(?usize, null), indexOf(units, 0, "Bow"));
    try testing.expectEqual(@as(?usize, null), indexOf(units, 1, "5"));
    try testing.expectEqual(@as(?usize, null), indexOf(units, 9, "Blade"));
    try testing.expectEqual(@as(?usize, null), indexOf(empty, 0, "Blade"));
}

test "sum of number fields" {
    try testing.expectEqual(@as(f64, 47), sum(units, 1));
    try testing.expectEqual(@as(f64, 0), sum(units, 0));
    try testing.expectEqual(@as(f64, 0), sum(empty, 1));
}

test "avg of number fields" {
    try testing.expectApproxEqAbs(47.0 / 3.0, try avg(units, 1), 1e-9);
    try testing.expectApproxEqAbs(0.75, try avg(nums, 0), 1e-9);
    try testing.expectError(error.Domain, avg(empty, 1));
    try testing.expectError(error.Domain, avg(units, 0));
    try testing.expectError(error.Domain, avg(inf_list, 0));
    try testing.expectError(error.Domain, avg(nan_first, 0));
    try testing.expectError(error.Domain, avg(nan_last, 0));
}

test "min and max reject NaN in either position" {
    try testing.expectError(error.Domain, minOf(nan_first, 0));
    try testing.expectError(error.Domain, minOf(nan_last, 0));
    try testing.expectError(error.Domain, maxOf(nan_first, 0));
    try testing.expectError(error.Domain, maxOf(nan_last, 0));
}

test "join skips items missing the field" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const short = [_]Value{.{ .text = "Short" }};
    const mixed: []const []const Value = &.{ &rifle, &short, &blade };
    try testing.expectEqualStrings("30, 5", try join(arena, mixed, 1, ", "));
    try testing.expectEqualStrings("Rifle|Short|Blade", try join(arena, mixed, 0, "|"));
}

test "min and max of number fields" {
    try testing.expectEqual(@as(f64, 5), try minOf(units, 1));
    try testing.expectEqual(@as(f64, 30), try maxOf(units, 1));
    try testing.expectEqual(@as(f64, 0.5), try minOf(nums, 0));
    try testing.expectError(error.Domain, minOf(empty, 1));
    try testing.expectError(error.Domain, maxOf(empty, 1));
    try testing.expectError(error.Domain, maxOf(units, 9));
    try testing.expectError(error.Domain, minOf(inf_list, 0));
    try testing.expectError(error.Domain, maxOf(inf_list, 0));
}

test "count matches by type and value" {
    try testing.expectEqual(@as(usize, 1), count(units, 0, .{ .text = "Shield" }));
    try testing.expectEqual(@as(usize, 0), count(units, 0, .{ .text = "Bow" }));
    try testing.expectEqual(@as(usize, 1), count(units, 1, .{ .number = 5 }));
    try testing.expectEqual(@as(usize, 0), count(units, 1, .{ .text = "5" }));
    try testing.expectEqual(@as(usize, 2), count(units, 2, .{ .color = red }));
    try testing.expectEqual(@as(usize, 1), count(units, 2, .{ .color = Color.white }));
    try testing.expectEqual(@as(usize, 2), count(units, 3, .{ .bool = true }));
    try testing.expectEqual(@as(usize, 1), count(units, 3, .{ .bool = false }));
    try testing.expectEqual(@as(usize, 0), count(units, 9, .{ .bool = true }));
    try testing.expectEqual(@as(usize, 0), count(empty, 0, .{ .text = "Rifle" }));
}

test "join numbers, halves and zero" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("30, 5, 12", try join(arena, units, 1, ", "));
    try testing.expectEqualStrings("1, 0.5", try join(arena, nums, 0, ", "));
}

test "join bools, colours and text" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("true|false|true", try join(arena, units, 3, "|"));
    try testing.expectEqualStrings("#FFFFFFFF #FF0000FF #FF0000FF", try join(arena, units, 2, " "));
    try testing.expectEqualStrings("RifleBladeShield", try join(arena, units, 0, ""));
}

test "join of empty list and missing field is empty" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("", try join(arena, empty, 0, ", "));
    try testing.expectEqualStrings("", try join(arena, units, 9, ", "));
}

test "join stops at max_len" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var big: [5000]u8 = undefined;
    @memset(&big, 'a');
    const row = [_]Value{.{ .text = &big }};
    const rows: []const []const Value = &.{ &row, &row };
    try testing.expectEqual(@as(usize, max_len), (try join(arena, rows, 0, "")).len);
    try testing.expectError(error.TooLong, join(arena, rows, 0, "x"));
}
