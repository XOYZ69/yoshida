//! Text builtins for the expression language (SPEC.md, text.zig section).
//! Indices and lengths count Unicode code points. Invalid UTF-8 bytes count as
//! one code point each and are copied unchanged.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ TooLong, Range, OutOfMemory };

/// Longest text result a builtin may produce, in bytes.
pub const max_len = 10_000;

/// One decoded code point. `valid` is false for a byte that does not start a
/// well-formed sequence; `cp` is then the byte value and `len` is 1.
const Decoded = struct {
    cp: u21,
    len: usize,
    valid: bool,
};

fn decodeAt(s: []const u8, i: usize) Decoded {
    const first = s[i];
    if (first < 0x80) return .{ .cp = first, .len = 1, .valid = true };
    const invalid: Decoded = .{ .cp = first, .len = 1, .valid = false };
    const n: usize = std.unicode.utf8ByteSequenceLength(first) catch return invalid;
    if (i + n > s.len) return invalid;
    const cp = std.unicode.utf8Decode(s[i .. i + n]) catch return invalid;
    return .{ .cp = cp, .len = n, .valid = true };
}

fn cpCount(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (n += 1) i += decodeAt(s, i).len;
    return n;
}

/// Byte offset of code point `k` in `s`; `s.len` when `k` is past the end.
fn byteOffset(s: []const u8, k: usize) usize {
    var i: usize = 0;
    var n: usize = 0;
    while (n < k and i < s.len) : (n += 1) i += decodeAt(s, i).len;
    return i;
}

fn toUpper(cp: u21) u21 {
    return switch (cp) {
        'a'...'z' => cp - 0x20,
        0xE0...0xF6, 0xF8...0xFE => cp - 0x20,
        0xFF => 0x178,
        0x100...0x17F => latinAUpper(cp),
        0x3AC => 0x386,
        0x3AD...0x3AF => cp - 0x25,
        0x3B1...0x3C9 => if (cp == 0x3C2) 0x3A3 else cp - 0x20,
        0x3CA...0x3CB => cp - 0x20,
        0x3CC => 0x38C,
        0x3CD => 0x38E,
        0x3CE => 0x38F,
        0x430...0x44F => cp - 0x20,
        0x450...0x45F => cp - 0x50,
        else => cp,
    };
}

fn toLower(cp: u21) u21 {
    return switch (cp) {
        'A'...'Z' => cp + 0x20,
        0xC0...0xD6, 0xD8...0xDE => cp + 0x20,
        0x100...0x17F => latinALower(cp),
        0x386 => 0x3AC,
        0x388...0x38A => cp + 0x25,
        0x38C => 0x3CC,
        0x38E => 0x3CD,
        0x38F => 0x3CE,
        0x391...0x3A1, 0x3A3...0x3A9 => cp + 0x20,
        0x3AA...0x3AB => cp + 0x20,
        0x400...0x40F => cp + 0x50,
        0x410...0x42F => cp + 0x20,
        else => cp,
    };
}

/// Latin Extended-A, lower to upper. Pairs are even upper / odd lower, except
/// the runs 0139-0148 and 0179-017E (odd upper / even lower).
fn latinAUpper(cp: u21) u21 {
    return switch (cp) {
        0x100...0x12F, 0x132...0x137, 0x14A...0x177 => if ((cp & 1) == 1) cp - 1 else cp,
        0x131 => 'I',
        0x139...0x148, 0x179...0x17E => if ((cp & 1) == 0) cp - 1 else cp,
        0x17F => 'S',
        else => cp,
    };
}

/// Latin Extended-A, upper to lower. Mirror of `latinAUpper`.
fn latinALower(cp: u21) u21 {
    return switch (cp) {
        0x100...0x12F, 0x132...0x137, 0x14A...0x177 => if ((cp & 1) == 0) cp + 1 else cp,
        0x130 => 'i',
        0x139...0x148, 0x179...0x17E => if ((cp & 1) == 1) cp + 1 else cp,
        0x178 => 0xFF,
        else => cp,
    };
}

/// Appends `m`, the mapping of code point `cp` whose source bytes are `bytes`.
fn emit(arena: Allocator, list: *std.ArrayList(u8), bytes: []const u8, cp: u21, m: u21) Error!void {
    if (m == cp) {
        try list.appendSlice(arena, bytes);
    } else {
        var buf: [4]u8 = undefined;
        const k = std.unicode.utf8Encode(m, &buf) catch unreachable;
        try list.appendSlice(arena, buf[0..k]);
    }
}

fn caseMap(arena: Allocator, t: []const u8, upper_case: bool) Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < t.len) {
        const d = decodeAt(t, i);
        const bytes = t[i .. i + d.len];
        const m = if (!d.valid) d.cp else if (upper_case) toUpper(d.cp) else toLower(d.cp);
        try emit(arena, &list, bytes, d.cp, m);
        i += d.len;
    }
    return list.items;
}

/// Upper-cases `t` with the simple mappings of ASCII, Latin-1, Latin
/// Extended-A, Greek and Cyrillic. Other code points, including `ß`, stay.
pub fn upper(arena: Allocator, t: []const u8) Error![]const u8 {
    return caseMap(arena, t, true);
}

/// Lower-cases `t` with the same tables as `upper`.
pub fn lower(arena: Allocator, t: []const u8) Error![]const u8 {
    return caseMap(arena, t, false);
}

/// True when `s` occurs in `t`. The empty `s` is always found.
pub fn contains(t: []const u8, s: []const u8) bool {
    return std.mem.indexOf(u8, t, s) != null;
}

/// True when `t` starts with `s`.
pub fn startsWith(t: []const u8, s: []const u8) bool {
    return std.mem.startsWith(u8, t, s);
}

/// True when `t` ends with `s`.
pub fn endsWith(t: []const u8, s: []const u8) bool {
    return std.mem.endsWith(u8, t, s);
}

/// Replaces every occurrence of `old` with `new`, left to right. An empty
/// `old` returns `t` unchanged.
pub fn replace(arena: Allocator, t: []const u8, old: []const u8, new: []const u8) Error![]const u8 {
    if (old.len == 0) return t;
    const size = std.mem.replacementSize(u8, t, old, new);
    if (size > max_len) return Error.TooLong;
    const out = try arena.alloc(u8, size);
    _ = std.mem.replace(u8, t, old, new, out);
    return out;
}

/// Clamps a code point index: negative values count from `n`, the result is
/// in 0..n. NaN gives 0.
fn clampIndex(x: f64, n: usize) usize {
    const nf: f64 = @floatFromInt(n);
    var r = @floor(x);
    if (r < 0) r += nf;
    if (!(r >= 0)) r = 0;
    if (r > nf) r = nf;
    return @intFromFloat(r);
}

/// Code points `start` (inclusive) to `end` (exclusive), both floored.
/// Negative values count from the end and are clamped to the text. A null
/// `end` means the end of the text. `end <= start` gives "". The result is a
/// sub-slice of `t`; `arena` is unused.
pub fn slice(arena: Allocator, t: []const u8, start: f64, end: ?f64) Error![]const u8 {
    _ = arena;
    const n = cpCount(t);
    const a = clampIndex(start, n);
    const b = if (end) |e| clampIndex(e, n) else n;
    if (b <= a) return "";
    return t[byteOffset(t, a)..byteOffset(t, b)];
}

/// Pads `t` on the left with the first code point of `fill` up to `width`
/// code points (floored). Returns `t` when `fill` is empty or `t` is already
/// wide enough.
pub fn padStart(arena: Allocator, t: []const u8, width: f64, fill: []const u8) Error![]const u8 {
    if (fill.len == 0) return t;
    const cur = cpCount(t);
    const w = @floor(width);
    if (!(w > @as(f64, @floatFromInt(cur)))) return t;
    if (w > max_len) return Error.TooLong;
    const f = decodeAt(fill, 0);
    const pad_unit = fill[0..f.len];
    const needed = @as(usize, @intFromFloat(w)) - cur;
    const pad_bytes = std.math.mul(usize, needed, pad_unit.len) catch return Error.TooLong;
    const total = std.math.add(usize, t.len, pad_bytes) catch return Error.TooLong;
    if (total > max_len) return Error.TooLong;
    var list: std.ArrayList(u8) = .empty;
    try list.ensureTotalCapacity(arena, total);
    for (0..needed) |_| list.appendSliceAssumeCapacity(pad_unit);
    list.appendSliceAssumeCapacity(t);
    return list.items;
}

/// `t` repeated `n` times (`n` floored). `n <= 0` gives "".
pub fn repeat(arena: Allocator, t: []const u8, n: f64) Error![]const u8 {
    const k = @floor(n);
    if (!(k >= 1) or t.len == 0) return "";
    if (k > max_len) return Error.TooLong;
    const count: usize = @intFromFloat(k);
    const total = std.math.mul(usize, t.len, count) catch return Error.TooLong;
    if (total > max_len) return Error.TooLong;
    const out = try arena.alloc(u8, total);
    for (0..count) |i| @memcpy(out[i * t.len ..][0..t.len], t);
    return out;
}

/// True for the characters that separate words in `titleCase`.
fn isSeparator(d: Decoded) bool {
    if (!d.valid) return false;
    if (d.cp == '-' or d.cp == 0xA0) return true;
    return d.cp < 0x80 and std.ascii.isWhitespace(@intCast(d.cp));
}

/// Upper-cases the first code point of each word. Words are split on
/// whitespace and `-`. Only that first code point is considered, and
/// `toUpper` changes only letters, so "2nd place" gives "2nd Place" and
/// "(x) y" gives "(x) Y".
pub fn titleCase(arena: Allocator, t: []const u8) Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    var word_start = true;
    var i: usize = 0;
    while (i < t.len) {
        const d = decodeAt(t, i);
        const bytes = t[i .. i + d.len];
        i += d.len;
        if (isSeparator(d)) {
            word_start = true;
            try list.appendSlice(arena, bytes);
        } else if (word_start) {
            word_start = false;
            const m = if (d.valid) toUpper(d.cp) else d.cp;
            try emit(arena, &list, bytes, d.cp, m);
        } else {
            try list.appendSlice(arena, bytes);
        }
    }
    return list.items;
}

/// Roman numeral for `n` (floored), 1..3999, upper case. Other values give
/// Range.
pub fn roman(arena: Allocator, n: f64) Error![]const u8 {
    const f = @floor(n);
    if (!(f >= 1 and f <= 3999)) return Error.Range;
    var v: usize = @intFromFloat(f);
    const table = [_]struct { v: usize, s: []const u8 }{
        .{ .v = 1000, .s = "M" },
        .{ .v = 900, .s = "CM" },
        .{ .v = 500, .s = "D" },
        .{ .v = 400, .s = "CD" },
        .{ .v = 100, .s = "C" },
        .{ .v = 90, .s = "XC" },
        .{ .v = 50, .s = "L" },
        .{ .v = 40, .s = "XL" },
        .{ .v = 10, .s = "X" },
        .{ .v = 9, .s = "IX" },
        .{ .v = 5, .s = "V" },
        .{ .v = 4, .s = "IV" },
        .{ .v = 1, .s = "I" },
    };
    var list: std.ArrayList(u8) = .empty;
    for (table) |e| {
        while (v >= e.v) : (v -= e.v) try list.appendSlice(arena, e.s);
    }
    return list.items;
}

/// Piece `n` (floored, 0-based, negative from the end) of `t` split on `sep`.
/// An index out of range gives "". An empty `sep` gives Range. The result is
/// a sub-slice of `t`.
pub fn part(t: []const u8, sep: []const u8, n: f64) Error![]const u8 {
    if (sep.len == 0) return Error.Range;
    const pieces: usize = std.mem.count(u8, t, sep) + 1;
    const pf: f64 = @floatFromInt(pieces);
    var k = @floor(n);
    if (k < 0) k += pf;
    if (!(k >= 0 and k < pf)) return "";
    const idx: usize = @intFromFloat(k);
    var it = std.mem.splitSequence(u8, t, sep);
    var i: usize = 0;
    while (it.next()) |piece| : (i += 1) {
        if (i == idx) return piece;
    }
    return "";
}

test "upper ascii and empty" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ABC XYZ 019!", try upper(arena, "abc xyz 019!"));
    try std.testing.expectEqualStrings("", try upper(arena, ""));
}

test "lower ascii and empty" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("abc xyz 019!", try lower(arena, "ABC xyz 019!"));
    try std.testing.expectEqualStrings("", try lower(arena, ""));
}

test "upper latin-1" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ÉCOLE", try upper(arena, "école"));
    try std.testing.expectEqualStrings("ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ", try upper(arena, "àáâãäåæçèéêëìíîïðñòóôõö"));
    try std.testing.expectEqualStrings("ØÙÚÛÜÝÞ", try upper(arena, "øùúûüýþ"));
    // ß has no simple upper case; × and ÷ are not letters.
    try std.testing.expectEqualStrings("STRAßE", try upper(arena, "straße"));
    try std.testing.expectEqualStrings("×÷", try upper(arena, "×÷"));
    // ÿ upper-cases to Ÿ (U+0178).
    try std.testing.expectEqualStrings("Ÿ", try upper(arena, "ÿ"));
}

test "lower latin-1" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("àéî", try lower(arena, "ÀÉÎ"));
    try std.testing.expectEqualStrings("ÿ", try lower(arena, "Ÿ"));
    try std.testing.expectEqualStrings("ß×÷", try lower(arena, "ß×÷"));
    try std.testing.expectEqualStrings("àéî", try lower(arena, "àéî"));
}

test "latin extended-a" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ĀĂĄ ĆČ ĐĒ", try upper(arena, "āăą ćč đē"));
    try std.testing.expectEqualStrings("āăą ćč đē", try lower(arena, "ĀĂĄ ĆČ ĐĒ"));
    try std.testing.expectEqualStrings("ĹĻŇ", try upper(arena, "ĺļň"));
    try std.testing.expectEqualStrings("ĺļň", try lower(arena, "ĹĻŇ"));
    try std.testing.expectEqualStrings("ŽŁ", try upper(arena, "žł"));
    try std.testing.expectEqualStrings("ĲĿŊ", try upper(arena, "ĳŀŋ"));
    // Irregular: dotless i, long s, dotted capital I, ŉ and ĸ have no pair.
    try std.testing.expectEqualStrings("I", try upper(arena, "ı"));
    try std.testing.expectEqualStrings("S", try upper(arena, "ſ"));
    try std.testing.expectEqualStrings("i", try lower(arena, "İ"));
    try std.testing.expectEqualStrings("ŉĸ", try upper(arena, "ŉĸ"));
    try std.testing.expectEqualStrings("ŉĸ", try lower(arena, "ŉĸ"));
    try std.testing.expectEqualStrings("ſ", try lower(arena, "ſ"));
}

test "greek" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ΑΒΓΔΩ", try upper(arena, "αβγδω"));
    try std.testing.expectEqualStrings("αβγδω", try lower(arena, "ΑΒΓΔΩ"));
    try std.testing.expectEqualStrings("Ω", try upper(arena, "Ω"));
    // Final sigma upper-cases to capital sigma; lower sigma is not final.
    try std.testing.expectEqualStrings("ΣΣ", try upper(arena, "σς"));
    try std.testing.expectEqualStrings("σσ", try lower(arena, "ΣΣ"));
    try std.testing.expectEqualStrings("ΆΈΉΊΌΎΏ", try upper(arena, "άέήίόύώ"));
    try std.testing.expectEqualStrings("άέήίόύώ", try lower(arena, "ΆΈΉΊΌΎΏ"));
    try std.testing.expectEqualStrings("Ϊ Ϋ", try upper(arena, "ϊ ϋ"));
    try std.testing.expectEqualStrings("ϊ ϋ", try lower(arena, "Ϊ Ϋ"));
}

test "cyrillic" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ЖЖ АЯ", try upper(arena, "жж ая"));
    try std.testing.expectEqualStrings("жж ая", try lower(arena, "ЖЖ АЯ"));
    try std.testing.expectEqualStrings("ЀЏ", try upper(arena, "ѐџ"));
    try std.testing.expectEqualStrings("ѐџ", try lower(arena, "ЀЏ"));
}

test "case mapping leaves other code points and emoji alone" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("😀中文 1 ÉÉ", try upper(arena, "😀中文 1 éé"));
    try std.testing.expectEqualStrings("😀中文 1 éé", try lower(arena, "😀中文 1 ÉÉ"));
}

test "case mapping keeps invalid utf-8 bytes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // 0xE9 is é in Latin-1 but not valid UTF-8 here: copied, ASCII still maps.
    try std.testing.expectEqualStrings("A\xe9B", try upper(arena, "a\xe9b"));
    try std.testing.expectEqualStrings("a\xffb\xc3", try lower(arena, "A\xffB\xc3"));
}

test "contains" {
    try std.testing.expect(contains("hello", "ell"));
    try std.testing.expect(contains("hello", ""));
    try std.testing.expect(contains("", ""));
    try std.testing.expect(!contains("hello", "x"));
    try std.testing.expect(!contains("", "x"));
    try std.testing.expect(contains("héllo", "é"));
}

test "startsWith and endsWith" {
    try std.testing.expect(startsWith("hello", "he"));
    try std.testing.expect(startsWith("hello", ""));
    try std.testing.expect(!startsWith("hello", "lo"));
    try std.testing.expect(!startsWith("he", "hello"));
    try std.testing.expect(endsWith("hello", "lo"));
    try std.testing.expect(endsWith("hello", ""));
    try std.testing.expect(!endsWith("hello", "he"));
    try std.testing.expect(!endsWith("", "x"));
}

test "replace" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("a+b+c", try replace(arena, "a-b-c", "-", "+"));
    try std.testing.expectEqualStrings("ba", try replace(arena, "aaa", "aa", "b"));
    try std.testing.expectEqualStrings("abc", try replace(arena, "abc", "x", "y"));
    try std.testing.expectEqualStrings("abc", try replace(arena, "abc", "", "y"));
    try std.testing.expectEqualStrings("", try replace(arena, "", "a", "b"));
    try std.testing.expectEqualStrings("", try replace(arena, "a", "a", ""));
    try std.testing.expectEqualStrings("ééé", try replace(arena, "ÀÀÀ", "À", "é"));
    try std.testing.expectEqualStrings("xyz", try replace(arena, "xyz", "xyz", "xyz"));
}

test "replace too long" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const at_limit = try replace(arena, "a" ** 5000, "a", "bb");
    try std.testing.expectEqual(@as(usize, max_len), at_limit.len);
    try std.testing.expectError(Error.TooLong, replace(arena, "a" ** 5001, "a", "bb"));
    try std.testing.expectEqual(@as(usize, 10001), (try replace(arena, "a" ** 10001, "", "")).len);
}

test "slice basic and negative indices" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("he", try slice(arena, "hello", 0, 2));
    try std.testing.expectEqualStrings("ello", try slice(arena, "hello", 1, null));
    try std.testing.expectEqualStrings("llo", try slice(arena, "hello", -3, null));
    try std.testing.expectEqualStrings("ll", try slice(arena, "hello", -3, -1));
    try std.testing.expectEqualStrings("o", try slice(arena, "hello", -1, null));
    try std.testing.expectEqualStrings("hello", try slice(arena, "hello", 0, null));
}

test "slice clamping and empty results" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("he", try slice(arena, "hello", -100, 2));
    try std.testing.expectEqualStrings("llo", try slice(arena, "hello", 2, 100));
    try std.testing.expectEqualStrings("hello", try slice(arena, "hello", -std.math.inf(f64), std.math.inf(f64)));
    try std.testing.expectEqualStrings("", try slice(arena, "hello", 3, 2));
    try std.testing.expectEqualStrings("", try slice(arena, "hello", 2, 2));
    try std.testing.expectEqualStrings("", try slice(arena, "hello", 10, 20));
    try std.testing.expectEqualStrings("", try slice(arena, "hello", -2, -2));
    try std.testing.expectEqualStrings("", try slice(arena, "", 0, null));
    try std.testing.expectEqualStrings("", try slice(arena, "", -1, 5));
    try std.testing.expectEqualStrings("hello", try slice(arena, "hello", std.math.nan(f64), null));
}

test "slice floors fractional indices" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("él", try slice(arena, "héllo", 1.9, 3.2));
    try std.testing.expectEqualStrings("h", try slice(arena, "hello", 0, 1.99));
    try std.testing.expectEqualStrings("lo", try slice(arena, "hello", -1.5, null));
}

test "slice counts code points" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("本", try slice(arena, "日本語", 1, 2));
    try std.testing.expectEqualStrings("語", try slice(arena, "日本語", -1, null));
    try std.testing.expectEqualStrings("😀b", try slice(arena, "a😀b", 1, null));
    // Invalid bytes each count as one code point.
    try std.testing.expectEqualStrings("\xff", try slice(arena, "a\xffb", 1, 2));
}

test "padStart pads with first code point of fill" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("007", try padStart(arena, "7", 3, "0"));
    try std.testing.expectEqualStrings("aax", try padStart(arena, "x", 3, "ab"));
    try std.testing.expectEqualStrings("üüé", try padStart(arena, "é", 3, "ü"));
    try std.testing.expectEqualStrings("😀😀😀ab", try padStart(arena, "ab", 5, "😀"));
    try std.testing.expectEqualStrings("001", try padStart(arena, "1", 3.9, "0"));
}

test "padStart returns text unchanged when nothing to add" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("abc", try padStart(arena, "abc", 2, "0"));
    try std.testing.expectEqualStrings("abc", try padStart(arena, "abc", 3, "0"));
    try std.testing.expectEqualStrings("x", try padStart(arena, "x", 4, ""));
    try std.testing.expectEqualStrings("x", try padStart(arena, "x", -5, "0"));
    try std.testing.expectEqualStrings("", try padStart(arena, "", 0, "-"));
    try std.testing.expectEqualStrings("x", try padStart(arena, "x", std.math.nan(f64), "0"));
}

test "padStart too long" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const full = try padStart(arena, "", 10_000, "x");
    try std.testing.expectEqual(@as(usize, max_len), full.len);
    try std.testing.expectError(Error.TooLong, padStart(arena, "", 10_001, "x"));
    try std.testing.expectError(Error.TooLong, padStart(arena, "", 1e300, "x"));
    try std.testing.expectError(Error.TooLong, padStart(arena, "", 4000, "€"));
    try std.testing.expectError(Error.TooLong, padStart(arena, "a", 9999, "😀"));
}

test "repeat" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("ababab", try repeat(arena, "ab", 3));
    try std.testing.expectEqualStrings("abab", try repeat(arena, "ab", 2.9));
    try std.testing.expectEqualStrings("éé", try repeat(arena, "é", 2));
    try std.testing.expectEqualStrings("ab", try repeat(arena, "ab", 1));
    try std.testing.expectEqualStrings("", try repeat(arena, "ab", 0));
    try std.testing.expectEqualStrings("", try repeat(arena, "ab", -2));
    try std.testing.expectEqualStrings("", try repeat(arena, "ab", 0.5));
    try std.testing.expectEqualStrings("", try repeat(arena, "ab", std.math.nan(f64)));
    try std.testing.expectEqualStrings("", try repeat(arena, "", 1e9));
    try std.testing.expectEqualStrings("", try repeat(arena, "", 1e300));
}

test "repeat too long" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const at_limit = try repeat(arena, "x", 10_000);
    try std.testing.expectEqual(@as(usize, max_len), at_limit.len);
    try std.testing.expectError(Error.TooLong, repeat(arena, "x", 10_001));
    try std.testing.expectError(Error.TooLong, repeat(arena, "ab", 1e300));
    try std.testing.expectError(Error.TooLong, repeat(arena, "ab", std.math.inf(f64)));
    try std.testing.expectError(Error.TooLong, repeat(arena, "abc", 3334));
}

test "titleCase" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("Hello World", try titleCase(arena, "hello world"));
    try std.testing.expectEqualStrings("Mary-Jane O'neil", try titleCase(arena, "mary-jane o'neil"));
    try std.testing.expectEqualStrings("  Two  Spaces ", try titleCase(arena, "  two  spaces "));
    try std.testing.expectEqualStrings("2nd Place", try titleCase(arena, "2nd place"));
    try std.testing.expectEqualStrings("(x) Y", try titleCase(arena, "(x) y"));
    try std.testing.expectEqualStrings("¿qué", try titleCase(arena, "¿qué"));
    try std.testing.expectEqualStrings("", try titleCase(arena, ""));
    try std.testing.expectEqualStrings("Élan Vital", try titleCase(arena, "élan vital"));
    try std.testing.expectEqualStrings("ÉCOLE Normale", try titleCase(arena, "ÉCOLE normale"));
    try std.testing.expectEqualStrings("Ωμέγα Жизнь", try titleCase(arena, "ωμέγα жизнь"));
    try std.testing.expectEqualStrings("ßa Ünter", try titleCase(arena, "ßa ünter"));
    try std.testing.expectEqualStrings("😀 Smile", try titleCase(arena, "😀 smile"));
}

test "roman numerals" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("I", try roman(arena, 1));
    try std.testing.expectEqualStrings("IV", try roman(arena, 4));
    try std.testing.expectEqualStrings("IX", try roman(arena, 9));
    try std.testing.expectEqualStrings("XIV", try roman(arena, 14));
    try std.testing.expectEqualStrings("XL", try roman(arena, 40));
    try std.testing.expectEqualStrings("XC", try roman(arena, 90));
    try std.testing.expectEqualStrings("CD", try roman(arena, 400));
    try std.testing.expectEqualStrings("MCMXCIV", try roman(arena, 1994));
    try std.testing.expectEqualStrings("MMMCMXCIX", try roman(arena, 3999));
    try std.testing.expectEqualStrings("MMXXVI", try roman(arena, 2026));
    try std.testing.expectEqualStrings("III", try roman(arena, 3.7));
}

test "roman range" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(Error.Range, roman(arena, 0));
    try std.testing.expectError(Error.Range, roman(arena, 0.9));
    try std.testing.expectError(Error.Range, roman(arena, -1));
    try std.testing.expectError(Error.Range, roman(arena, 4000));
    try std.testing.expectError(Error.Range, roman(arena, std.math.nan(f64)));
    try std.testing.expectError(Error.Range, roman(arena, std.math.inf(f64)));
}

test "part" {
    try std.testing.expectEqualStrings("a", try part("a,b,c", ",", 0));
    try std.testing.expectEqualStrings("b", try part("a,b,c", ",", 1));
    try std.testing.expectEqualStrings("c", try part("a,b,c", ",", 2));
    try std.testing.expectEqualStrings("b", try part("a::b::c", "::", 1));
    try std.testing.expectEqualStrings("wörld", try part("héllo wörld", " ", 1));
    try std.testing.expectEqualStrings("b", try part("a,b,c", ",", 1.8));
}

test "part negative and out of range" {
    try std.testing.expectEqualStrings("c", try part("a,b,c", ",", -1));
    try std.testing.expectEqualStrings("b", try part("a,b,c", ",", -2));
    try std.testing.expectEqualStrings("a", try part("a,b,c", ",", -3));
    try std.testing.expectEqualStrings("", try part("a,b,c", ",", -4));
    try std.testing.expectEqualStrings("", try part("a,b,c", ",", 3));
    try std.testing.expectEqualStrings("", try part("a,b,c", ",", 100));
    try std.testing.expectEqualStrings("", try part("a,b,c", ",", std.math.nan(f64)));
    try std.testing.expectEqualStrings("", try part("a,b,c", ",", std.math.inf(f64)));
}

test "part empty pieces and missing separator" {
    try std.testing.expectEqualStrings("", try part("a,,b", ",", 1));
    try std.testing.expectEqualStrings("a,,b", try part("a,,b", ";", 0));
    try std.testing.expectEqualStrings("", try part("a,,b", ";", 1));
    try std.testing.expectEqualStrings("", try part("", ",", 0));
    try std.testing.expectEqualStrings("", try part("", ",", -1));
    try std.testing.expectEqualStrings("", try part("a,", ",", 1));
}

test "part empty separator is a range error" {
    try std.testing.expectError(Error.Range, part("abc", "", 0));
    try std.testing.expectError(Error.Range, part("", "", 0));
}
