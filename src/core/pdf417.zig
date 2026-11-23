//! PDF417 (ISO/IEC 15438): text, byte and numeric compaction, error
//! correction levels 0 to 8 over GF(929), 1 to 30 data columns and 3 to 90
//! rows chosen for a wide symbol. Each row is drawn three modules high.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sym = @import("symbol.zig");
const table = @import("pdf417_table.zig");
const Symbol = sym.Symbol;
const Problem = sym.Problem;
const Error = sym.Error;
const problem = sym.problem;

/// Most codewords of a symbol, data and error correction together.
pub const max_codewords = 929;

/// Error correction level for `ecc` when none is asked for.
pub const auto_level: u8 = 255;

const Sub = enum { alpha, lower, mixed, punct };

const mixed_chars = "0123456789&\r\t,:#-.$/+%*=^";
const punct_chars = ";<>@[\\]_`~!\r\t,:\n-.$/\"|*()?{}'";

fn textVal(sub: Sub, c: u8) ?u8 {
    switch (sub) {
        .alpha => {
            if (c >= 'A' and c <= 'Z') return c - 'A';
            if (c == ' ') return 26;
        },
        .lower => {
            if (c >= 'a' and c <= 'z') return c - 'a';
            if (c == ' ') return 26;
        },
        .mixed => {
            if (std.mem.indexOfScalar(u8, mixed_chars, c)) |i| return @intCast(i);
            if (c == ' ') return 26;
        },
        .punct => {
            if (std.mem.indexOfScalar(u8, punct_chars, c)) |i| return @intCast(i);
        },
    }
    return null;
}

fn isText(c: u8) bool {
    return (c >= 32 and c < 127) or c == '\t' or c == '\r' or c == '\n';
}

const Kind = enum { text, byte, numeric };

const Seg = struct { kind: Kind, start: usize, end: usize };

fn segments(a: Allocator, text: []const u8) Allocator.Error![]Seg {
    var out: std.ArrayList(Seg) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        var d = i;
        while (d < text.len and std.ascii.isDigit(text[d])) d += 1;
        if (d - i >= 13) {
            try out.append(a, .{ .kind = .numeric, .start = i, .end = d });
            i = d;
            continue;
        }
        const kind: Kind = if (isText(text[i])) .text else .byte;
        var e = i;
        while (e < text.len) {
            // A run of 13 digits or more ahead starts its own segment.
            var dd = e;
            while (dd < text.len and std.ascii.isDigit(text[dd])) dd += 1;
            if (dd - e >= 13 and e > i) break;
            if ((kind == .text) != isText(text[e])) break;
            e += 1;
        }
        try out.append(a, .{ .kind = kind, .start = i, .end = e });
        i = e;
    }
    return out.items;
}

fn textCompact(a: Allocator, out: *std.ArrayList(u16), s: []const u8) Allocator.Error!void {
    var vals: std.ArrayList(u8) = .empty;
    var cur: Sub = .alpha;
    for (s) |c| {
        if (textVal(cur, c)) |v| {
            try vals.append(a, v);
            continue;
        }
        if (cur != .punct) if (textVal(.punct, c)) |v| {
            try vals.append(a, 29);
            try vals.append(a, v);
            continue;
        };
        const target: Sub = if (textVal(.alpha, c) != null) .alpha else if (textVal(.lower, c) != null) .lower else .mixed;
        switch (cur) {
            .alpha => {
                try vals.append(a, if (target == .lower) 27 else 28);
                cur = target;
            },
            .lower => {
                if (target == .alpha) {
                    // Shift for one capital.
                    try vals.append(a, 27);
                    try vals.append(a, textVal(.alpha, c).?);
                    continue;
                }
                try vals.append(a, 28);
                cur = .mixed;
            },
            .mixed => {
                try vals.append(a, if (target == .alpha) 28 else 27);
                cur = if (target == .alpha) .alpha else .lower;
            },
            .punct => {
                try vals.append(a, 29);
                cur = .alpha;
                if (target == .lower) {
                    try vals.append(a, 27);
                    cur = .lower;
                } else if (target == .mixed) {
                    try vals.append(a, 28);
                    cur = .mixed;
                }
            },
        }
        try vals.append(a, textVal(cur, c).?);
    }
    if (vals.items.len % 2 == 1) try vals.append(a, 29);
    var i: usize = 0;
    while (i < vals.items.len) : (i += 2) try out.append(a, @as(u16, vals.items[i]) * 30 + vals.items[i + 1]);
}

fn byteCompact(a: Allocator, out: *std.ArrayList(u16), s: []const u8) Allocator.Error!void {
    var i: usize = 0;
    while (i + 6 <= s.len) : (i += 6) {
        var v: u64 = 0;
        for (s[i .. i + 6]) |b| v = v * 256 + b;
        var five: [5]u16 = undefined;
        var k: usize = 5;
        while (k > 0) {
            k -= 1;
            five[k] = @intCast(v % 900);
            v /= 900;
        }
        try out.appendSlice(a, &five);
    }
    for (s[i..]) |b| try out.append(a, b);
}

fn numericCompact(a: Allocator, out: *std.ArrayList(u16), s: []const u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < s.len) {
        const take = @min(44, s.len - i);
        // "1" and the digits as one decimal number, written in base 900.
        var digits: [45]u8 = undefined;
        digits[0] = 1;
        for (s[i .. i + take], 0..) |c, k| digits[k + 1] = c - '0';
        var n: usize = take + 1;
        var rev: [15]u16 = undefined;
        var count: usize = 0;
        var start: usize = 0;
        while (start < n) {
            var rem: u32 = 0;
            for (digits[start..n]) |*d| {
                const cur = rem * 10 + d.*;
                d.* = @intCast(cur / 900);
                rem = cur % 900;
            }
            rev[count] = @intCast(rem);
            count += 1;
            while (start < n and digits[start] == 0) start += 1;
        }
        n = count;
        while (n > 0) {
            n -= 1;
            try out.append(a, rev[n]);
        }
        i += take;
    }
}

fn gfPow3(e: usize) u32 {
    var r: u32 = 1;
    for (0..e) |_| r = r * 3 % 929;
    return r;
}

/// The check codewords for `data` at `level`.
fn errorCorrection(a: Allocator, data: []const u16, level: u8) Allocator.Error![]u16 {
    const k: usize = @as(usize, 2) << @intCast(level);
    // Generator: the product of (x - 3^i), constant term first, monic.
    const g = try a.alloc(u32, k + 1);
    @memset(g, 0);
    g[0] = 1;
    var deg: usize = 0;
    for (1..k + 1) |root| {
        const r = gfPow3(root);
        var i = deg + 1;
        g[i] = 0;
        while (i > 0) : (i -= 1) g[i] = (g[i - 1] + (929 - r) * g[i] % 929) % 929;
        g[0] = (929 - r) * g[0] % 929;
        deg += 1;
    }
    const e = try a.alloc(u32, k);
    @memset(e, 0);
    for (data) |d| {
        const t1 = (d + e[k - 1]) % 929;
        var j = k - 1;
        while (j >= 1) : (j -= 1) {
            const t2 = t1 * g[j] % 929;
            e[j] = (e[j - 1] + 929 - t2) % 929;
        }
        e[0] = (929 - t1 * g[0] % 929) % 929;
    }
    const out = try a.alloc(u16, k);
    for (0..k) |j| {
        const v = e[k - 1 - j];
        out[j] = @intCast(if (v != 0) 929 - v else 0);
    }
    return out;
}

const start_bits = "11111111010101000";
const stop_bits = "111111101000101001";

pub fn encode(a: Allocator, prob: *Problem, text: []const u8, ecc: u8) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "PDF417 needs text, but it is empty", .{}, null);
    var words: std.ArrayList(u16) = .empty;
    var high = false;
    for (text) |c| if (c >= 128) {
        high = true;
    };
    // UTF-8 is announced with ECI 26.
    if (high) try words.appendSlice(a, &.{ 927, 26 });
    var mode: Kind = .text;
    for (try segments(a, text)) |sg| {
        const s = text[sg.start..sg.end];
        switch (sg.kind) {
            .text => {
                if (mode != .text) try words.append(a, 900);
                try textCompact(a, &words, s);
            },
            .byte => {
                try words.append(a, if (s.len % 6 == 0) 924 else 901);
                try byteCompact(a, &words, s);
            },
            .numeric => {
                try words.append(a, 902);
                try numericCompact(a, &words, s);
            },
        }
        mode = sg.kind;
    }
    // The length descriptor counts itself, the data and the padding.
    const data_len = words.items.len + 1;
    var level: u8 = if (ecc == auto_level) (if (data_len <= 40) 2 else if (data_len <= 160) 3 else if (data_len <= 320) 4 else 5) else @min(ecc, 8);
    // Left to itself, a text that is a little too long gets less error correction.
    if (ecc == auto_level) {
        while (level > 0 and data_len + (@as(usize, 2) << @intCast(level)) > max_codewords) level -= 1;
    }
    const ecc_len: usize = @as(usize, 2) << @intCast(level);
    if (data_len + ecc_len > max_codewords) {
        return problem(a, prob, "the text needs {d} codewords with error correction level {d}, but a PDF417 holds at most {d}", .{ data_len + ecc_len, level, max_codewords }, "shorten the text or use a lower \"ecc\" level");
    }
    // Columns: a wide symbol, about three times as wide as it is high.
    var cols: usize = 1;
    var best_score: f64 = std.math.inf(f64);
    for (1..31) |c| {
        const total = data_len + ecc_len;
        const rows = @max(3, (total + c - 1) / c);
        if (rows > 90) continue;
        const w: f64 = @floatFromInt(17 * c + 69);
        const h: f64 = @floatFromInt(3 * rows);
        const score = @abs(w / h - 3);
        if (score < best_score) {
            best_score = score;
            cols = c;
        }
    }
    const total = data_len + ecc_len;
    const rows = @max(3, (total + cols - 1) / cols);
    if (rows > 90) return problem(a, prob, "the text does not fit a PDF417 of 30 columns and 90 rows", .{}, "shorten the text or use a lower \"ecc\" level");
    const body_len = rows * cols - ecc_len;
    const all = try a.alloc(u16, rows * cols);
    all[0] = @intCast(body_len);
    @memcpy(all[1 .. 1 + words.items.len], words.items);
    for (1 + words.items.len..body_len) |i| all[i] = 900;
    const check = try errorCorrection(a, all[0..body_len], level);
    @memcpy(all[body_len..], check);

    const width = 17 * cols + 69;
    const height = 3 * rows;
    const cells = try a.alloc(bool, width * height);
    @memset(cells, false);
    for (0..rows) |r| {
        const cluster = r % 3;
        const base: usize = 30 * (r / 3);
        const rows_m1 = rows - 1;
        const left: usize = switch (cluster) {
            0 => base + rows_m1 / 3,
            1 => base + @as(usize, level) * 3 + rows_m1 % 3,
            else => base + cols - 1,
        };
        const right: usize = switch (cluster) {
            0 => base + cols - 1,
            1 => base + rows_m1 / 3,
            else => base + @as(usize, level) * 3 + rows_m1 % 3,
        };
        var x: usize = 0;
        const row = cells[r * 3 * width ..][0..width];
        for (start_bits) |ch| {
            row[x] = ch == '1';
            x += 1;
        }
        const put = struct {
            fn cw(rw: []bool, xp: *usize, pattern: u32) void {
                var bit: u5 = 16;
                while (true) {
                    rw[xp.*] = (pattern >> bit) & 1 == 1;
                    xp.* += 1;
                    if (bit == 0) break;
                    bit -= 1;
                }
            }
        }.cw;
        put(row, &x, table.clusters[cluster][left]);
        for (0..cols) |c| put(row, &x, table.clusters[cluster][all[r * cols + c]]);
        put(row, &x, table.clusters[cluster][right]);
        for (stop_bits) |ch| {
            row[x] = ch == '1';
            x += 1;
        }
        @memcpy(cells[(r * 3 + 1) * width ..][0..width], row);
        @memcpy(cells[(r * 3 + 2) * width ..][0..width], row);
    }
    return .{
        .format = .pdf417,
        .w = width,
        .h = height,
        .cells = cells,
        .normalized = text,
        .version = @intCast(cols),
        .capacity = max_codewords,
    };
}

test "PDF417 makes a wide symbol" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prob: Problem = .{};
    const s = try encode(arena.allocator(), &prob, "Hello PDF417", auto_level);
    try std.testing.expect(s.w > s.h);
    // Every row starts with the start pattern.
    try std.testing.expect(s.get(0, 0) and s.get(7, 0) and !s.get(8, 0));
}
