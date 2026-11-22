//! 1D barcodes: Code 128 (sets A, B and C chosen for the fewest symbols),
//! EAN-13, EAN-8, UPC-A, Code 39, Interleaved 2 of 5 (and ITF-14),
//! Codabar and Code 93. Each encoder returns the bars as modules, one row;
//! the renderer gives them a height.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sym = @import("symbol.zig");
const Symbol = sym.Symbol;
const Problem = sym.Problem;
const Error = sym.Error;
const Bars = sym.Bars;
const Check = sym.Check;
const problem = sym.problem;

fn finish(a: Allocator, format: sym.Format, bars: *Bars) Allocator.Error!Symbol {
    const cells = try bars.list.toOwnedSlice(a);
    return .{ .format = format, .w = cells.len, .h = 1, .cells = cells };
}

/// The characters of `text` that are digits, spaces and hyphens dropped;
/// anything else is a problem.
fn digitsOnly(a: Allocator, prob: *Problem, name: []const u8, text: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |c| {
        if (c == ' ' or c == '-') continue;
        if (c < '0' or c > '9') {
            if (c >= 0x20 and c < 0x7f) return problem(a, prob, "{s} holds digits only, but the text has '{c}'", .{ name, c }, "remove the letters and symbols; spaces and hyphens are dropped");
            return problem(a, prob, "{s} holds digits only, but the text has a character that is not a digit", .{name}, "remove everything but digits");
        }
        try out.append(a, c);
    }
    return out.items;
}

// ------------------------------------------------------------- Code 128

const code128_patterns = [107][]const u8{
    "212222", "222122", "222221", "121223", "121322", "131222", "122213",  "122312", "132212", "221213",
    "221312", "231212", "112232", "122132", "122231", "113222", "123122",  "123221", "223211", "221132",
    "221231", "213212", "223112", "312131", "311222", "321122", "321221",  "312212", "322112", "322211",
    "212123", "212321", "232121", "111323", "131123", "131321", "112313",  "132113", "132311", "211313",
    "231113", "231311", "112133", "112331", "132131", "113123", "113321",  "133121", "313121", "211331",
    "231131", "213113", "213311", "213131", "311123", "311321", "331121",  "312113", "312311", "332111",
    "314111", "221411", "431111", "111224", "111422", "121124", "121421",  "141122", "141221", "112214",
    "112412", "122114", "122411", "142112", "142211", "241211", "221114",  "413111", "241112", "134111",
    "111242", "121142", "121241", "114212", "124112", "124211", "411212",  "421112", "421211", "212141",
    "214121", "412121", "111143", "111341", "131141", "114113", "114311",  "411113", "411311", "113141",
    "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
};

const set_a = 0;
const set_b = 1;
const set_c = 2;

fn code128Value(set: usize, c: u8) ?u8 {
    return switch (set) {
        set_a => if (c < 32) c + 64 else if (c < 96) c - 32 else null,
        set_b => if (c >= 32) c - 32 else null,
        else => null,
    };
}

pub fn code128(a: Allocator, prob: *Problem, text: []const u8) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Code 128 needs text, but it is empty", .{}, null);
    for (text) |c| if (c > 127) return problem(a, prob, "Code 128 holds ASCII characters (0 to 127) only; the text has umlauts or symbols beyond that", .{}, "use a QR code, Data Matrix or Aztec code for other characters");
    const n = text.len;
    const inf = std.math.maxInt(u32);
    // fin[i][s]: fewest symbols to encode the first i characters and end in
    // set s, after any switch at i; arr[i][s]: the same without a switch.
    const fin = try a.alloc(u32, (n + 1) * 3);
    const arr = try a.alloc(u32, (n + 1) * 3);
    const from = try a.alloc(i8, (n + 1) * 3);
    @memset(fin, inf);
    @memset(arr, inf);
    @memset(from, -1);
    for (0..3) |s| {
        arr[s] = 1;
        fin[s] = 1;
    }
    for (0..n + 1) |i| {
        if (i > 0) {
            for (0..3) |s| {
                const step: usize = if (s == set_c) 2 else 1;
                if (i < step) continue;
                const c0 = text[i - step];
                const ok = switch (s) {
                    set_c => c0 >= '0' and c0 <= '9' and text[i - 1] >= '0' and text[i - 1] <= '9',
                    else => code128Value(s, c0) != null,
                };
                const prev = fin[(i - step) * 3 + s];
                if (ok and prev != inf) arr[i * 3 + s] = prev + 1;
            }
            for (0..3) |t| {
                fin[i * 3 + t] = arr[i * 3 + t];
                from[i * 3 + t] = -1;
            }
            for (0..3) |t| for (0..3) |s| {
                if (s == t or arr[i * 3 + s] == inf) continue;
                if (i == n) continue;
                if (arr[i * 3 + s] + 1 < fin[i * 3 + t]) {
                    fin[i * 3 + t] = arr[i * 3 + s] + 1;
                    from[i * 3 + t] = @intCast(s);
                }
            };
        }
    }
    var best: usize = 0;
    for (1..3) |s| if (arr[n * 3 + s] < arr[n * 3 + best]) {
        best = s;
    };
    if (arr[n * 3 + best] == inf) return problem(a, prob, "this text cannot be encoded in Code 128", .{}, null);

    // Walk back from the end, then reverse.
    var rev: std.ArrayList(u8) = .empty;
    var i = n;
    var s = best;
    var as_arrive = true;
    while (true) {
        if (!as_arrive and from[i * 3 + s] >= 0) {
            // A switch into s at position i: the code that selects s.
            try rev.append(a, switch (s) {
                set_a => 101,
                set_b => 100,
                else => 99,
            });
            s = @intCast(from[i * 3 + s]);
            as_arrive = true;
            continue;
        }
        if (i == 0) break;
        const step: usize = if (s == set_c) 2 else 1;
        if (s == set_c) {
            try rev.append(a, (text[i - 2] - '0') * 10 + (text[i - 1] - '0'));
        } else try rev.append(a, code128Value(s, text[i - 1]).?);
        i -= step;
        as_arrive = false;
    }
    try rev.append(a, switch (s) {
        set_a => 103,
        set_b => 104,
        else => 105,
    });
    std.mem.reverse(u8, rev.items);
    var sum: usize = rev.items[0];
    for (rev.items[1..], 1..) |v, k| sum += @as(usize, v) * k;
    try rev.append(a, @intCast(sum % 103));
    try rev.append(a, 106);

    var bars: Bars = .{};
    for (rev.items) |v| try bars.widths(a, code128_patterns[v]);
    var out = try finish(a, .code128, &bars);
    out.normalized = text;
    return out;
}

// ------------------------------------------------------------ EAN and UPC

const ean_l = [10][]const u8{ "0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011" };
const ean_g = [10][]const u8{ "0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111" };
const ean_r = [10][]const u8{ "1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100" };
const ean_parity = [10][]const u8{ "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL" };

/// Mod 10 check digit with weights 3, 1, 3, ... from the right of `digits`
/// (the digits without the check digit).
pub fn mod10(digits: []const u8) u8 {
    var sum: usize = 0;
    var w: usize = 3;
    var i = digits.len;
    while (i > 0) {
        i -= 1;
        sum += (digits[i] - '0') * w;
        w = 4 - w;
    }
    return @intCast('0' + (10 - sum % 10) % 10);
}

/// Like `problem`, for a wrong number of digits or a wrong check digit [3112].
fn wrongDigits(a: Allocator, prob: *Problem, comptime fmt: []const u8, args: anytype, hint: ?[]const u8) Error {
    const e = problem(a, prob, fmt, args, hint);
    prob.code = 3112;
    return e;
}

/// Digits with the check digit settled: `total` is the length with it.
fn withCheck(a: Allocator, prob: *Problem, name: []const u8, text: []const u8, total: usize, check: Check, out_check: *?u8) Error![]u8 {
    const d = try digitsOnly(a, prob, name, text);
    if (d.len == total - 1 and check != .none) {
        const full = try a.alloc(u8, total);
        @memcpy(full[0 .. total - 1], d);
        full[total - 1] = mod10(d);
        out_check.* = full[total - 1];
        return full;
    }
    if (d.len != total) {
        if (check == .none) return wrongDigits(a, prob, "{s} needs {d} digits, but the text has {d}", .{ name, total, d.len }, "give all digits, check digit included, or use \"check\": \"auto\" to have it added");
        return wrongDigits(a, prob, "{s} needs {d} digits ({d} when the check digit is left out), but the text has {d}", .{ name, total, total - 1, d.len }, null);
    }
    if (check != .none and mod10(d[0 .. total - 1]) != d[total - 1]) {
        return wrongDigits(a, prob, "the check digit of the {s} is {c}, but the text ends in {c}", .{ name, mod10(d[0 .. total - 1]), d[total - 1] }, "leave the last digit out to have the right one added, or set \"check\": \"none\"");
    }
    return d;
}

fn eanSide(a: Allocator, bars: *Bars, digits: []const u8, parity: []const u8) Allocator.Error!void {
    for (digits, parity) |d, p| try bars.bits(a, switch (p) {
        'G' => ean_g[d - '0'],
        'R' => ean_r[d - '0'],
        else => ean_l[d - '0'],
    });
}

fn groups(a: Allocator, list: []const sym.LabelGroup) Allocator.Error![]const sym.LabelGroup {
    return a.dupe(sym.LabelGroup, list);
}

pub fn ean13(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    var chk: ?u8 = null;
    const d = try withCheck(a, prob, "EAN-13", text, 13, check, &chk);
    var bars: Bars = .{};
    try bars.bits(a, "101");
    try eanSide(a, &bars, d[1..7], ean_parity[d[0] - '0']);
    try bars.bits(a, "01010");
    try eanSide(a, &bars, d[7..13], "RRRRRR");
    try bars.bits(a, "101");
    var out = try finish(a, .ean13, &bars);
    out.normalized = d;
    out.check_digit = chk;
    out.groups = try groups(a, &.{
        .{ .text = d[0..1], .x0 = -9, .x1 = -1 },
        .{ .text = d[1..7], .x0 = 3, .x1 = 45 },
        .{ .text = d[7..13], .x0 = 50, .x1 = 92 },
    });
    out.guards = try a.dupe([2]u16, &.{ .{ 0, 3 }, .{ 45, 50 }, .{ 92, 95 } });
    return out;
}

pub fn ean8(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    var chk: ?u8 = null;
    const d = try withCheck(a, prob, "EAN-8", text, 8, check, &chk);
    var bars: Bars = .{};
    try bars.bits(a, "101");
    try eanSide(a, &bars, d[0..4], "LLLL");
    try bars.bits(a, "01010");
    try eanSide(a, &bars, d[4..8], "RRRR");
    try bars.bits(a, "101");
    var out = try finish(a, .ean8, &bars);
    out.normalized = d;
    out.check_digit = chk;
    out.groups = try groups(a, &.{
        .{ .text = d[0..4], .x0 = 3, .x1 = 31 },
        .{ .text = d[4..8], .x0 = 36, .x1 = 64 },
    });
    out.guards = try a.dupe([2]u16, &.{ .{ 0, 3 }, .{ 31, 36 }, .{ 64, 67 } });
    return out;
}

pub fn upca(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    var chk: ?u8 = null;
    const d = try withCheck(a, prob, "UPC-A", text, 12, check, &chk);
    var bars: Bars = .{};
    try bars.bits(a, "101");
    try eanSide(a, &bars, d[0..6], "LLLLLL");
    try bars.bits(a, "01010");
    try eanSide(a, &bars, d[6..12], "RRRRRR");
    try bars.bits(a, "101");
    var out = try finish(a, .upca, &bars);
    out.normalized = d;
    out.check_digit = chk;
    out.groups = try groups(a, &.{
        .{ .text = d[0..1], .x0 = -9, .x1 = -1 },
        .{ .text = d[1..6], .x0 = 10, .x1 = 45 },
        .{ .text = d[6..11], .x0 = 50, .x1 = 85 },
        .{ .text = d[11..12], .x0 = 96, .x1 = 104 },
    });
    // The number system and check digits' bars run down too.
    out.guards = try a.dupe([2]u16, &.{ .{ 0, 10 }, .{ 45, 50 }, .{ 85, 95 } });
    return out;
}

// --------------------------------------------------------------- Code 39

const code39_chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%";
const code39_patterns = [43][]const u8{
    "nnnwwnwnn", "wnnwnnnnw", "nnwwnnnnw", "wnwwnnnnn", "nnnwwnnnw", "wnnwwnnnn", "nnwwwnnnn", "nnnwnnwnw", "wnnwnnwnn", "nnwwnnwnn",
    "wnnnnwnnw", "nnwnnwnnw", "wnwnnwnnn", "nnnnwwnnw", "wnnnwwnnn", "nnwnwwnnn", "nnnnnwwnw", "wnnnnwwnn", "nnwnnwwnn", "nnnnwwwnn",
    "wnnnnnnww", "nnwnnnnww", "wnwnnnnwn", "nnnnwnnww", "wnnnwnnwn", "nnwnwnnwn", "nnnnnnwww", "wnnnnnwwn", "nnwnnnwwn", "nnnnwnwwn",
    "wwnnnnnnw", "nwwnnnnnw", "wwwnnnnnn", "nwnnwnnnw", "wwnnwnnnn", "nwwnwnnnn", "nwnnnnwnw", "wwnnnnwnn", "nwwnnnwnn", "nwnwnwnnn",
    "nwnwnnnwn", "nwnnnwnwn", "nnnwnwnwn",
};
const code39_star = "nwnnwnwnn";

pub fn code39(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Code 39 needs text, but it is empty", .{}, null);
    var data: std.ArrayList(u8) = .empty;
    for (text) |c| {
        const up = std.ascii.toUpper(c);
        if (std.mem.indexOfScalar(u8, code39_chars, up) == null) {
            if (c >= 0x20 and c < 0x7f) return problem(a, prob, "Code 39 holds digits, capital letters and - . space $ / + % only, but the text has '{c}'", .{c}, "use Code 128 for lower case and other symbols");
            return problem(a, prob, "Code 39 holds digits, capital letters and - . space $ / + % only", .{}, "use Code 128 for other characters");
        }
        try data.append(a, up);
    }
    var chk: ?u8 = null;
    if (check == .add) {
        var sum: usize = 0;
        for (data.items) |c| sum += std.mem.indexOfScalar(u8, code39_chars, c).?;
        const cc = code39_chars[sum % 43];
        try data.append(a, cc);
        chk = cc;
    }
    var bars: Bars = .{};
    try bars.nw(a, code39_star, 3);
    for (data.items) |c| {
        try bars.bits(a, "0");
        try bars.nw(a, code39_patterns[std.mem.indexOfScalar(u8, code39_chars, c).?], 3);
    }
    try bars.bits(a, "0");
    try bars.nw(a, code39_star, 3);
    var out = try finish(a, .code39, &bars);
    out.normalized = data.items;
    out.check_digit = chk;
    return out;
}

// ---------------------------------------------- Interleaved 2 of 5 (ITF)

const itf_patterns = [10][]const u8{ "nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw", "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn" };

fn itfBars(a: Allocator, digits: []const u8) Allocator.Error!Bars {
    var bars: Bars = .{};
    // Start: narrow bar, space, bar, space.
    try bars.nw(a, "nnnn", 3);
    var i: usize = 0;
    while (i < digits.len) : (i += 2) {
        const p1 = itf_patterns[digits[i] - '0'];
        const p2 = itf_patterns[digits[i + 1] - '0'];
        // Bars carry the first digit, spaces the second, interleaved.
        for (0..5) |k| {
            const bw: u8 = if (p1[k] == 'w') 3 else 1;
            const sw: u8 = if (p2[k] == 'w') 3 else 1;
            for (0..bw) |_| try bars.list.append(a, true);
            for (0..sw) |_| try bars.list.append(a, false);
        }
    }
    // Stop: wide bar, narrow space, narrow bar.
    try bars.nw(a, "wnn", 3);
    return bars;
}

pub fn itf(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    var d: std.ArrayList(u8) = .empty;
    try d.appendSlice(a, try digitsOnly(a, prob, "Interleaved 2 of 5", text));
    if (d.items.len == 0) return problem(a, prob, "Interleaved 2 of 5 needs digits, but the text has none", .{}, null);
    var note: []const u8 = "";
    var chk: ?u8 = null;
    if (check == .add) {
        // The check digit counts towards the even number of digits.
        if ((d.items.len + 1) % 2 == 1) {
            try d.insert(a, 0, '0');
            note = "a leading 0 was added, because the digits come in pairs";
        }
        chk = mod10(d.items);
        try d.append(a, chk.?);
    } else if (d.items.len % 2 == 1) {
        try d.insert(a, 0, '0');
        note = "a leading 0 was added, because the digits come in pairs";
    }
    var bars = try itfBars(a, d.items);
    var out = try finish(a, .itf, &bars);
    out.normalized = d.items;
    out.check_digit = chk;
    out.note = note;
    return out;
}

pub fn itf14(a: Allocator, prob: *Problem, text: []const u8, check: Check) Error!Symbol {
    var chk: ?u8 = null;
    const d = try withCheck(a, prob, "ITF-14", text, 14, check, &chk);
    var bars = try itfBars(a, d);
    var out = try finish(a, .itf14, &bars);
    out.normalized = d;
    out.check_digit = chk;
    out.bearer = true;
    return out;
}

// --------------------------------------------------------------- Codabar

const codabar_chars = "0123456789-$:/.+ABCD";
const codabar_patterns = [20][]const u8{
    "nnnnnww", "nnnnwwn", "nnnwnnw", "wwnnnnn", "nnwnnwn", "wnnnnwn", "nwnnnnw", "nwnnwnn", "nwwnnnn", "wnnwnnn",
    "nnnwwnn", "nnwwnnn", "wnnnwnw", "wnwnnnw", "wnwnwnn", "nnwnwnw", "nnwwnwn", "nwnwnnw", "nnnwnww", "nnnwwwn",
};

pub fn codabar(a: Allocator, prob: *Problem, text: []const u8) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Codabar needs text, but it is empty", .{}, null);
    var data: std.ArrayList(u8) = .empty;
    var note: []const u8 = "";
    const up0 = std.ascii.toUpper(text[0]);
    const upn = std.ascii.toUpper(text[text.len - 1]);
    const has_start = up0 >= 'A' and up0 <= 'D';
    const has_stop = upn >= 'A' and upn <= 'D';
    if (has_start != has_stop or (text.len == 1 and has_start)) {
        return problem(a, prob, "a Codabar text needs both a start and a stop letter (A to D) or neither", .{}, "write A1234B, or just 1234 to get A and B added");
    }
    if (!has_start) {
        try data.append(a, 'A');
        note = "start A and stop B were added";
    }
    for (text) |c| {
        const up = std.ascii.toUpper(c);
        if (std.mem.indexOfScalar(u8, codabar_chars, up) == null) {
            if (c >= 0x20 and c < 0x7f) return problem(a, prob, "Codabar holds digits and - $ : / . + only (plus start and stop letters A to D), but the text has '{c}'", .{c}, "use Code 128 for letters and other symbols");
            return problem(a, prob, "Codabar holds digits and - $ : / . + only", .{}, "use Code 128 for other characters");
        }
        try data.append(a, up);
    }
    if (!has_start) try data.append(a, 'B');
    var bars: Bars = .{};
    for (data.items, 0..) |c, k| {
        if (k > 0) try bars.bits(a, "0");
        try bars.nw(a, codabar_patterns[std.mem.indexOfScalar(u8, codabar_chars, c).?], 3);
    }
    var out = try finish(a, .codabar, &bars);
    out.normalized = data.items;
    out.note = note;
    return out;
}

// --------------------------------------------------------------- Code 93

const code93_chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%";
const code93_patterns = [47][]const u8{
    "100010100", "101001000", "101000100", "101000010", "100101000", "100100100", "100100010", "101010000", "100010010", "100001010",
    "110101000", "110100100", "110100010", "110010100", "110010010", "110001010", "101101000", "101100100", "101100010", "100110100",
    "100011010", "101011000", "101001100", "101000110", "100101100", "100010110", "110110100", "110110010", "110101100", "110100110",
    "110010110", "110011010", "101101100", "101100110", "100110110", "100111010", "100101110", "111010100", "111010010", "111001010",
    "101101110", "101110110", "110101110", "100100110", "111011010", "100110010", "111010110",
};
const code93_start = "101011110";

pub fn code93(a: Allocator, prob: *Problem, text: []const u8) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Code 93 needs text, but it is empty", .{}, null);
    var vals: std.ArrayList(u8) = .empty;
    for (text) |c| {
        const up = std.ascii.toUpper(c);
        const idx = std.mem.indexOfScalar(u8, code93_chars, up) orelse {
            if (c >= 0x20 and c < 0x7f) return problem(a, prob, "Code 93 holds digits, capital letters and - . space $ / + % only, but the text has '{c}'", .{c}, "use Code 128 for lower case and other symbols");
            return problem(a, prob, "Code 93 holds digits, capital letters and - . space $ / + % only", .{}, "use Code 128 for other characters");
        };
        try vals.append(a, @intCast(idx));
    }
    // Two check characters, C then K, weights 1 to 20 and 1 to 15 from the right.
    var c_sum: usize = 0;
    for (vals.items, 0..) |v, i| c_sum += @as(usize, v) * ((vals.items.len - 1 - i) % 20 + 1);
    const c: u8 = @intCast(c_sum % 47);
    try vals.append(a, c);
    var k_sum: usize = 0;
    for (vals.items, 0..) |v, i| k_sum += @as(usize, v) * ((vals.items.len - 1 - i) % 15 + 1);
    try vals.append(a, @intCast(k_sum % 47));
    var bars: Bars = .{};
    try bars.bits(a, code93_start);
    for (vals.items) |v| try bars.bits(a, code93_patterns[v]);
    try bars.bits(a, code93_start);
    try bars.bits(a, "1");
    var out = try finish(a, .code93, &bars);
    out.normalized = text;
    return out;
}

// ------------------------------------------------------------------ tests

const testing = std.testing;

test "Code 128 patterns all span 11 modules" {
    for (code128_patterns[0..106]) |p| {
        var sum: usize = 0;
        for (p) |ch| sum += ch - '0';
        try testing.expectEqual(@as(usize, 11), sum);
    }
    var sum: usize = 0;
    for (code128_patterns[106]) |ch| sum += ch - '0';
    try testing.expectEqual(@as(usize, 13), sum);
}

test "Code 128 picks set C for digit runs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var prob: Problem = .{};
    const s = try code128(arena.allocator(), &prob, "1234567890");
    // Start C, five pairs, check, stop: 8 symbols of 11 plus the stop's 13.
    try testing.expectEqual(@as(usize, 7 * 11 + 13), s.w);
    const t = try code128(arena.allocator(), &prob, "Hello");
    try testing.expectEqual(@as(usize, (1 + 5 + 1) * 11 + 13), t.w);
}

test "EAN-13 checks digits" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var prob: Problem = .{};
    const s = try ean13(a, &prob, "400638133393", .auto);
    try testing.expectEqualStrings("4006381333931", s.normalized);
    try testing.expectEqual(@as(usize, 95), s.w);
    try testing.expectEqual(@as(u8, '1'), s.check_digit.?);
    try testing.expectError(error.Invalid, ean13(a, &prob, "4006381333932", .auto));
    try testing.expect(std.mem.indexOf(u8, prob.msg, "check digit") != null);
    const u = try upca(a, &prob, "03600029145", .auto);
    try testing.expectEqualStrings("036000291452", u.normalized);
    const e = try ean8(a, &prob, "9638507", .auto);
    try testing.expectEqualStrings("96385074", e.normalized);
}

test "Code 93 and Code 39 sizes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var prob: Problem = .{};
    const s = try code93(a, &prob, "TEST93");
    try testing.expectEqual(@as(usize, (1 + 6 + 2 + 1) * 9 + 1), s.w);
    const t = try code39(a, &prob, "ABC", .none);
    // Five characters of 15 modules (start, A, B, C, stop) and four gaps.
    try testing.expectEqual(@as(usize, 5 * 15 + 4), t.w);
}
