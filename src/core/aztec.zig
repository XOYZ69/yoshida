//! Aztec Code (ISO/IEC 24778): compact (1 to 4 layers) and full range (1 to
//! 32 layers) symbols. The text is split into the five character modes
//! (upper, lower, mixed, punctuation, digit) and binary runs by a
//! shortest-path search, so digits and capitals stay small.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sym = @import("symbol.zig");
const Symbol = sym.Symbol;
const Problem = sym.Problem;
const Error = sym.Error;
const problem = sym.problem;

/// Most data bytes any symbol can hold (a rough ceiling for messages).
pub const max_bytes = 3000;

const Mode = enum(u3) { upper, lower, mixed, punct, digit };
const modes = [_]Mode{ .upper, .lower, .mixed, .punct, .digit };

fn bitsOf(m: Mode) u8 {
    return if (m == .digit) 4 else 5;
}

const mixed_table = [_]u8{ 0, ' ', 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 27, 28, 29, 30, 31, '@', '\\', '^', '_', '`', '|', '~', 127 };
const punct_table = [_]u8{ 0, 13, 0, 0, 0, 0, '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '[', ']', '{', '}' };

/// The code of `c` in mode `m`, or null when the mode has no such character.
fn charCode(m: Mode, c: u8) ?u8 {
    switch (m) {
        .upper => {
            if (c == ' ') return 1;
            if (c >= 'A' and c <= 'Z') return c - 'A' + 2;
        },
        .lower => {
            if (c == ' ') return 1;
            if (c >= 'a' and c <= 'z') return c - 'a' + 2;
        },
        .digit => {
            if (c == ' ') return 1;
            if (c >= '0' and c <= '9') return c - '0' + 2;
            if (c == ',') return 12;
            if (c == '.') return 13;
        },
        .mixed => {
            for (mixed_table, 0..) |t, i| if (i > 0 and t == c) return @intCast(i);
        },
        .punct => {
            if (c == 13) return 1;
            for (punct_table, 0..) |t, i| if (i >= 6 and t == c) return @intCast(i);
        },
    }
    return null;
}

/// One step of a latch: the code (in mode `from`) that moves to mode `to`.
const Latch = struct { code: u8, bits: u8 };

fn latchStep(from: Mode, to: Mode) ?Latch {
    return switch (from) {
        .upper => switch (to) {
            .lower => .{ .code = 28, .bits = 5 },
            .mixed => .{ .code = 29, .bits = 5 },
            .digit => .{ .code = 30, .bits = 5 },
            else => null,
        },
        .lower => switch (to) {
            .mixed => .{ .code = 29, .bits = 5 },
            .digit => .{ .code = 30, .bits = 5 },
            else => null,
        },
        .mixed => switch (to) {
            .upper => .{ .code = 29, .bits = 5 },
            .lower => .{ .code = 28, .bits = 5 },
            .punct => .{ .code = 30, .bits = 5 },
            else => null,
        },
        .digit => switch (to) {
            .upper => .{ .code = 14, .bits = 4 },
            else => null,
        },
        .punct => switch (to) {
            .upper => .{ .code = 31, .bits = 5 },
            else => null,
        },
    };
}

const inf = std.math.maxInt(u32) / 4;

/// Latch costs between any two modes, and the first step of the cheapest way.
const Paths = struct {
    cost: [5][5]u32,
    next: [5][5]u8,

    fn init() Paths {
        var p: Paths = .{ .cost = undefined, .next = undefined };
        for (modes) |a| for (modes) |b| {
            const i = @intFromEnum(a);
            const j = @intFromEnum(b);
            if (a == b) {
                p.cost[i][j] = 0;
                p.next[i][j] = @intCast(j);
            } else if (latchStep(a, b)) |l| {
                p.cost[i][j] = l.bits;
                p.next[i][j] = @intCast(j);
            } else {
                p.cost[i][j] = inf;
                p.next[i][j] = 0;
            }
        };
        for (0..5) |k| for (0..5) |i| for (0..5) |j| {
            if (p.cost[i][k] + p.cost[k][j] < p.cost[i][j]) {
                p.cost[i][j] = p.cost[i][k] + p.cost[k][j];
                p.next[i][j] = p.next[i][k];
            }
        };
        return p;
    }
};

const paths = Paths.init();

const BitList = struct {
    list: std.ArrayList(bool) = .empty,

    fn add(b: *BitList, a: Allocator, value: usize, count: usize) Allocator.Error!void {
        var i = count;
        while (i > 0) {
            i -= 1;
            try b.list.append(a, (value >> @intCast(i)) & 1 == 1);
        }
    }
};

const Op = union(enum) {
    latch: struct { from: Mode, to: Mode },
    char: struct { mode: Mode, code: u8 },
    shift: struct { from: Mode, via: Mode, code: u8 },
    binary: struct { from: Mode, start: usize, len: usize },
};

const Kind = enum(u8) { none, start, latch, char, shift, binary };

const Par = struct {
    kind: Kind = .none,
    prev_mode: u8 = 0,
    prev_i: u32 = 0,
    via: u8 = 0,
    code: u8 = 0,
};

fn shiftTo(from: Mode, via: Mode) ?Latch {
    return switch (via) {
        .punct => switch (from) {
            .upper, .lower, .mixed => .{ .code = 0, .bits = 5 },
            .digit => .{ .code = 0, .bits = 4 },
            else => null,
        },
        .upper => switch (from) {
            .lower => .{ .code = 28, .bits = 5 },
            .digit => .{ .code = 15, .bits = 4 },
            else => null,
        },
        else => null,
    };
}

/// The bit string of the text: the cheapest walk through the modes.
fn highLevel(a: Allocator, text: []const u8) Allocator.Error!BitList {
    const n = text.len;
    const stride = 5;
    const dp = try a.alloc(u32, (n + 1) * stride);
    const arrive = try a.alloc(u32, (n + 1) * stride);
    const par = try a.alloc(Par, (n + 1) * stride); // how dp[i][m] was reached after latches
    const apar = try a.alloc(Par, (n + 1) * stride); // how arrive[i][m] was reached
    @memset(dp, inf);
    @memset(arrive, inf);
    @memset(par, .{});
    @memset(apar, .{});
    arrive[0] = 0;
    apar[0] = .{ .kind = .start };

    var i: usize = 0;
    while (i <= n) : (i += 1) {
        for (0..5) |m| {
            dp[i * stride + m] = arrive[i * stride + m];
            par[i * stride + m] = apar[i * stride + m];
        }
        for (0..5) |to| for (0..5) |from| {
            if (from == to or arrive[i * stride + from] >= inf) continue;
            const c = arrive[i * stride + from] + paths.cost[from][to];
            if (c < dp[i * stride + to]) {
                dp[i * stride + to] = c;
                par[i * stride + to] = .{ .kind = .latch, .prev_mode = @intCast(from) };
            }
        };
        if (i == n) break;
        const c = text[i];
        for (modes) |m| {
            const mi = @intFromEnum(m);
            const here = dp[i * stride + mi];
            if (here >= inf) continue;
            if (charCode(m, c)) |code| {
                const cost = here + bitsOf(m);
                const idx = (i + 1) * stride + mi;
                if (cost < arrive[idx]) {
                    arrive[idx] = cost;
                    apar[idx] = .{ .kind = .char, .prev_mode = @intCast(mi), .prev_i = @intCast(i), .code = code };
                }
            }
            for ([_]Mode{ .punct, .upper }) |via| {
                if (via == m) continue;
                const sh = shiftTo(m, via) orelse continue;
                const code = charCode(via, c) orelse continue;
                const cost = here + sh.bits + bitsOf(via);
                const idx = (i + 1) * stride + mi;
                if (cost < arrive[idx]) {
                    arrive[idx] = cost;
                    apar[idx] = .{ .kind = .shift, .prev_mode = @intCast(mi), .prev_i = @intCast(i), .via = @intFromEnum(via), .code = code };
                }
            }
            if (m == .upper or m == .lower or m == .mixed) {
                const rest = n - i;
                // Short runs of every length, and the whole rest as one run.
                const short = @min(rest, 31);
                const long = @min(rest, 2078);
                const count = short + @as(usize, if (long > short) 1 else 0);
                for (0..count) |j| {
                    const k = if (j < short) j + 1 else long;
                    const extra: u32 = if (k > 31) 16 else 5;
                    const cost = here + 5 + extra + 8 * @as(u32, @intCast(k));
                    const idx = (i + k) * stride + mi;
                    if (cost < arrive[idx]) {
                        arrive[idx] = cost;
                        apar[idx] = .{ .kind = .binary, .prev_mode = @intCast(mi), .prev_i = @intCast(i) };
                    }
                }
            }
        }
    }

    // The cheapest end state, then back to the start.
    var best_m: usize = 0;
    for (1..5) |m| if (dp[n * stride + m] < dp[n * stride + best_m]) {
        best_m = m;
    };
    var ops: std.ArrayList(Op) = .empty;
    var wi = n;
    var wm = best_m;
    var final = true;
    while (true) {
        const p = if (final) par[wi * stride + wm] else apar[wi * stride + wm];
        switch (p.kind) {
            .start, .none => break,
            .latch => {
                try ops.append(a, .{ .latch = .{ .from = @enumFromInt(p.prev_mode), .to = @enumFromInt(wm) } });
                wm = p.prev_mode;
                final = false;
            },
            .char => {
                try ops.append(a, .{ .char = .{ .mode = @enumFromInt(wm), .code = p.code } });
                wi = p.prev_i;
                wm = p.prev_mode;
                final = true;
            },
            .shift => {
                try ops.append(a, .{ .shift = .{ .from = @enumFromInt(p.prev_mode), .via = @enumFromInt(p.via), .code = p.code } });
                wi = p.prev_i;
                wm = p.prev_mode;
                final = true;
            },
            .binary => {
                // The run's length is in `code` modulo 256: recover it from the positions.
                try ops.append(a, .{ .binary = .{ .from = @enumFromInt(p.prev_mode), .start = p.prev_i, .len = wi - p.prev_i } });
                wi = p.prev_i;
                wm = p.prev_mode;
                final = true;
            },
        }
    }
    std.mem.reverse(Op, ops.items);

    var bits: BitList = .{};
    for (ops.items) |op| switch (op) {
        .latch => |l| {
            var cur = l.from;
            while (cur != l.to) {
                const nxt: Mode = @enumFromInt(paths.next[@intFromEnum(cur)][@intFromEnum(l.to)]);
                const st = latchStep(cur, nxt).?;
                try bits.add(a, st.code, st.bits);
                cur = nxt;
            }
        },
        .char => |c| try bits.add(a, c.code, bitsOf(c.mode)),
        .shift => |s| {
            const sh = shiftTo(s.from, s.via).?;
            try bits.add(a, sh.code, sh.bits);
            try bits.add(a, s.code, bitsOf(s.via));
        },
        .binary => |b| {
            try bits.add(a, 31, 5);
            if (b.len <= 31) {
                try bits.add(a, b.len, 5);
            } else {
                try bits.add(a, 0, 5);
                try bits.add(a, b.len - 31, 11);
            }
            for (text[b.start .. b.start + b.len]) |byte| try bits.add(a, byte, 8);
        },
    };
    return bits;
}

// ---------------------------------------------------------- Reed-Solomon

const Field = struct {
    size: usize,
    exp: []u16,
    log: []u16,

    fn init(a: Allocator, word_size: usize) Allocator.Error!Field {
        const poly: usize = switch (word_size) {
            4 => 0x13,
            6 => 0x43,
            8 => 0x12D,
            10 => 0x409,
            else => 0x1069,
        };
        const size = @as(usize, 1) << @intCast(word_size);
        var f: Field = .{ .size = size, .exp = try a.alloc(u16, size * 2), .log = try a.alloc(u16, size) };
        var x: usize = 1;
        for (0..size - 1) |i| {
            f.exp[i] = @intCast(x);
            f.log[x] = @intCast(i);
            x <<= 1;
            if (x >= size) x ^= poly;
        }
        for (size - 1..size * 2) |i| f.exp[i] = f.exp[i - (size - 1)];
        f.log[0] = 0;
        return f;
    }

    fn mul(f: *const Field, x: u16, y: u16) u16 {
        if (x == 0 or y == 0) return 0;
        return f.exp[@as(usize, f.log[x]) + f.log[y]];
    }
};

/// Appends `n` check words (roots 2^1 to 2^n) to `words`, which holds the
/// data words in its first `words.len - n` places.
fn rsEncode(a: Allocator, f: *const Field, words: []u16, n: usize) Allocator.Error!void {
    const gen = try a.alloc(u16, n + 1);
    @memset(gen, 0);
    gen[0] = 1;
    var deg: usize = 0;
    for (1..n + 1) |root| {
        const r = f.exp[root % (f.size - 1)];
        var i = deg + 1;
        while (i > 0) : (i -= 1) gen[i] = gen[i - 1] ^ f.mul(gen[i], r);
        gen[0] = f.mul(gen[0], r);
        deg += 1;
    }
    const data_len = words.len - n;
    const ecc = try a.alloc(u16, n);
    @memset(ecc, 0);
    for (words[0..data_len]) |d| {
        const lead = d ^ ecc[0];
        for (0..n - 1) |i| ecc[i] = ecc[i + 1] ^ f.mul(gen[n - 1 - i], lead);
        ecc[n - 1] = f.mul(gen[0], lead);
    }
    @memcpy(words[data_len..], ecc);
}

fn wordSizeFor(layers: usize) usize {
    if (layers <= 2) return 6;
    if (layers <= 8) return 8;
    if (layers <= 22) return 10;
    return 12;
}

fn totalBitsIn(layers: usize, compact: bool) usize {
    return ((if (compact) @as(usize, 88) else 112) + 16 * layers) * layers;
}

/// The data bits cut into words of `word_size` bits, where a word of all
/// zeros or all ones (apart from its last bit) gets a bit of the other kind
/// stuffed in.
fn stuff(a: Allocator, bits: []const bool, word_size: usize) Allocator.Error![]bool {
    var out: std.ArrayList(bool) = .empty;
    const mask: usize = (@as(usize, 1) << @intCast(word_size)) - 2;
    const ws: isize = @intCast(word_size);
    const n: isize = @intCast(bits.len);
    var i: isize = 0;
    while (i < n) : (i += ws) {
        var word: usize = 0;
        for (0..word_size) |j| {
            const idx = i + @as(isize, @intCast(j));
            if (idx >= n or bits[@intCast(idx)]) word |= @as(usize, 1) << @intCast(word_size - 1 - j);
        }
        var w = word;
        if (word & mask == mask) {
            w = word & mask;
            i -= 1;
        } else if (word & mask == 0) {
            w = word | 1;
            i -= 1;
        }
        for (0..word_size) |j| try out.append(a, (w >> @intCast(word_size - 1 - j)) & 1 == 1);
    }
    return out.items;
}

/// The data bits plus check words, laid out as `total_bits` bits.
fn checkWords(a: Allocator, bits: []const bool, total_bits: usize, word_size: usize) Allocator.Error![]bool {
    const msg_words = bits.len / word_size;
    const total_words = total_bits / word_size;
    const words = try a.alloc(u16, total_words);
    @memset(words, 0);
    for (0..msg_words) |i| {
        var v: u16 = 0;
        for (0..word_size) |j| v = (v << 1) | @intFromBool(bits[i * word_size + j]);
        words[i] = v;
    }
    const f = try Field.init(a, word_size);
    try rsEncode(a, &f, words, total_words - msg_words);
    const start_pad = total_bits % word_size;
    const out = try a.alloc(bool, total_bits);
    @memset(out[0..start_pad], false);
    for (words, 0..) |w, i| {
        for (0..word_size) |j| out[start_pad + i * word_size + j] = (w >> @intCast(word_size - 1 - j)) & 1 == 1;
    }
    return out;
}

pub const Options = struct {
    /// Smallest share of check words, in percent of the data.
    ecc: u8 = 23,
};

pub fn encode(a: Allocator, prob: *Problem, text: []const u8, o: Options) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Aztec needs text, but it is empty", .{}, null);
    // Bytes above 127 are announced as UTF-8 (ECI 26) so that readers do not
    // guess a character set.
    var utf8 = false;
    for (text) |c| if (c >= 128) {
        utf8 = true;
    };
    var data: BitList = .{};
    if (utf8) {
        // M/L, P/L, FLG(2) with digits 2 6, then U/L back to upper.
        try data.add(a, 29, 5);
        try data.add(a, 30, 5);
        try data.add(a, 0, 5);
        try data.add(a, 2, 3);
        try data.add(a, 2 + 2, 4);
        try data.add(a, 2 + 6, 4);
        try data.add(a, 31, 5);
    }
    const body = try highLevel(a, text);
    try data.list.appendSlice(a, body.list.items);
    const bits = data.list.items;

    const ecc_bits: usize = bits.len * o.ecc / 100 + 11;
    const total_size = bits.len + ecc_bits;
    var chosen_layers: usize = 0;
    var compact = false;
    var word_size: usize = 0;
    var stuffed: []bool = &.{};
    var found = false;
    var i: usize = 0;
    while (i <= 32) : (i += 1) {
        const is_compact = i <= 3;
        const layers = if (is_compact) i + 1 else i;
        const total_in_layer = totalBitsIn(layers, is_compact);
        if (total_size > total_in_layer) continue;
        if (word_size != wordSizeFor(layers)) {
            word_size = wordSizeFor(layers);
            stuffed = try stuff(a, bits, word_size);
        }
        if (is_compact and stuffed.len > word_size * 64) continue;
        const usable = total_in_layer - total_in_layer % word_size;
        if (stuffed.len + ecc_bits <= usable) {
            chosen_layers = layers;
            compact = is_compact;
            found = true;
            break;
        }
    }
    if (!found) return problem(a, prob, "the text is too long for an Aztec code ({d} bytes)", .{text.len}, "shorten the text, or use a QR code");
    const layers = chosen_layers;
    const total_bits = totalBitsIn(layers, compact);
    const msg_words = stuffed.len / word_size;
    const message = try checkWords(a, stuffed, total_bits, word_size);

    // Mode message: layers and word count, with its own check nibbles.
    var mm: BitList = .{};
    if (compact) {
        try mm.add(a, layers - 1, 2);
        try mm.add(a, msg_words - 1, 6);
    } else {
        try mm.add(a, layers - 1, 5);
        try mm.add(a, msg_words - 1, 11);
    }
    const mode_msg = try checkWords(a, mm.list.items, if (compact) 28 else 40, 4);

    const base: usize = (if (compact) @as(usize, 11) else 14) + layers * 4;
    const size: usize = if (compact) base else base + 1 + 2 * ((base / 2 - 1) / 15);
    const align_map = try a.alloc(usize, base);
    if (compact) {
        for (align_map, 0..) |*m, k| m.* = k;
    } else {
        const orig_center = base / 2;
        const center = size / 2;
        for (0..orig_center) |k| {
            const off = k + k / 15;
            align_map[orig_center - k - 1] = center - off - 1;
            align_map[orig_center + k] = center + off + 1;
        }
    }
    const cells = try a.alloc(bool, size * size);
    @memset(cells, false);
    const set = struct {
        fn at(c: []bool, sz: usize, x: usize, y: usize) void {
            c[y * sz + x] = true;
        }
    }.at;

    var row_offset: usize = 0;
    for (0..layers) |li| {
        const row_size = (layers - li) * 4 + (if (compact) @as(usize, 9) else 12);
        for (0..row_size) |j| {
            const col_offset = j * 2;
            for (0..2) |k| {
                if (message[row_offset + col_offset + k]) set(cells, size, align_map[li * 2 + k], align_map[li * 2 + j]);
                if (message[row_offset + row_size * 2 + col_offset + k]) set(cells, size, align_map[li * 2 + j], align_map[base - 1 - li * 2 - k]);
                if (message[row_offset + row_size * 4 + col_offset + k]) set(cells, size, align_map[base - 1 - li * 2 - k], align_map[base - 1 - li * 2 - j]);
                if (message[row_offset + row_size * 6 + col_offset + k]) set(cells, size, align_map[base - 1 - li * 2 - j], align_map[li * 2 + k]);
            }
        }
        row_offset += row_size * 8;
    }

    const center = size / 2;
    if (compact) {
        for (0..7) |k| {
            const off = center - 3 + k;
            if (mode_msg[k]) set(cells, size, off, center - 5);
            if (mode_msg[k + 7]) set(cells, size, center + 5, off);
            if (mode_msg[20 - k]) set(cells, size, off, center + 5);
            if (mode_msg[27 - k]) set(cells, size, center - 5, off);
        }
    } else {
        for (0..10) |k| {
            const off = center - 5 + k + k / 5;
            if (mode_msg[k]) set(cells, size, off, center - 7);
            if (mode_msg[k + 10]) set(cells, size, center + 7, off);
            if (mode_msg[29 - k]) set(cells, size, off, center + 7);
            if (mode_msg[39 - k]) set(cells, size, center - 7, off);
        }
    }

    // The bull's eye in the middle.
    const eye: usize = if (compact) 5 else 7;
    var d: usize = 0;
    while (d < eye) : (d += 2) {
        var j = center - d;
        while (j <= center + d) : (j += 1) {
            set(cells, size, j, center - d);
            set(cells, size, j, center + d);
            set(cells, size, center - d, j);
            set(cells, size, center + d, j);
        }
    }
    set(cells, size, center - eye, center - eye);
    set(cells, size, center - eye + 1, center - eye);
    set(cells, size, center - eye, center - eye + 1);
    set(cells, size, center + eye, center - eye);
    set(cells, size, center + eye, center - eye + 1);
    set(cells, size, center + eye, center + eye - 1);

    // Full symbols: a reference grid every 16 modules.
    if (!compact) {
        var ii: usize = 0;
        var jj: usize = 0;
        while (ii < base / 2 - 1) : ({
            ii += 15;
            jj += 16;
        }) {
            var k = center & 1;
            while (k < size) : (k += 2) {
                set(cells, size, center - jj, k);
                set(cells, size, center + jj, k);
                set(cells, size, k, center - jj);
                set(cells, size, k, center + jj);
            }
        }
    }

    return .{
        .format = .aztec,
        .w = size,
        .h = size,
        .cells = cells,
        .normalized = text,
        .version = @intCast(layers),
        .capacity = max_bytes,
    };
}

test "Aztec sizes grow with the text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prob: Problem = .{};
    const s = try encode(arena.allocator(), &prob, "Aztec", .{});
    try std.testing.expectEqual(@as(usize, 15), s.w);
    const t = try encode(arena.allocator(), &prob, "Yoshida makes cards from JSON, with Aztec codes in the corner.", .{});
    try std.testing.expect(t.w > 15);
}
