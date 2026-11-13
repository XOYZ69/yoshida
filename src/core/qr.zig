//! QR code encoder (ISO/IEC 18004): byte mode, versions 1 to 40, error
//! correction levels L, M, Q and H, automatic mask choice. It needs no
//! allocator: everything lives in fixed arrays, so it also runs in the
//! WebAssembly module.

const std = @import("std");

pub const Level = enum { low, medium, quartile, high };

/// Modules per side of the largest symbol (version 40).
pub const max_size = 177;

/// The result of `encode`: a square of dark and light modules.
pub const Code = struct {
    /// Modules per side, 21 to 177.
    size: u8 = 0,
    version: u8 = 0,
    /// Mask pattern that was applied, 0 to 7.
    mask: u8 = 0,
    dark: [max_size * max_size]bool = undefined,

    pub fn get(c: *const Code, x: usize, y: usize) bool {
        return c.dark[y * c.size + x];
    }
};

pub const Error = error{TooLong};

// Error correction codewords per block and number of blocks, by version
// (index 0 is unused) and level (low, medium, quartile, high).
const ecc_per_block = [4][41]u8{
    .{ 0, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 },
    .{ 0, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
    .{ 0, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
};
const num_blocks = [4][41]u8{
    .{ 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 },
    .{ 0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 },
    .{ 0, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 },
    .{ 0, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 },
};

/// Most codewords (data plus error correction) in any symbol, version 40.
const max_codewords = 3706;
const max_blocks = 81;
const max_ecc = 30;

fn rawModules(version: usize) usize {
    var r: usize = (16 * version + 128) * version + 64;
    if (version >= 2) {
        const n = version / 7 + 2;
        r -= (25 * n - 10) * n - 55;
        if (version >= 7) r -= 36;
    }
    return r;
}

fn dataCodewords(version: usize, level: Level) usize {
    const l = @intFromEnum(level);
    return rawModules(version) / 8 - @as(usize, ecc_per_block[l][version]) * num_blocks[l][version];
}

/// Largest number of bytes a symbol of `level` can hold (version 40).
pub fn capacity(level: Level) usize {
    return dataCodewords(40, level) - 3;
}

/// Encodes `data` (as bytes, normally UTF-8). `force_mask` is for tests;
/// null picks the mask with the lowest penalty, as the standard asks.
pub fn encode(code: *Code, data: []const u8, level: Level, force_mask: ?u3) Error!void {
    // Smallest version that fits: mode (4 bits), count (8 or 16), bytes.
    var version: usize = 1;
    while (true) : (version += 1) {
        if (version > 40) return error.TooLong;
        const count_bits: usize = if (version <= 9) 8 else 16;
        if (4 + count_bits + 8 * data.len <= dataCodewords(version, level) * 8) break;
    }
    const n_data = dataCodewords(version, level);

    // Bit stream: 0100, count, bytes, terminator, padding.
    var buf: [max_codewords]u8 = @splat(0);
    var bits: usize = 0;
    appendBits(&buf, &bits, 0b0100, 4);
    appendBits(&buf, &bits, data.len, if (version <= 9) 8 else 16);
    for (data) |b| appendBits(&buf, &bits, b, 8);
    const cap_bits = n_data * 8;
    appendBits(&buf, &bits, 0, @min(4, cap_bits - bits));
    appendBits(&buf, &bits, 0, (8 - bits % 8) % 8);
    var pad: u8 = 0xEC;
    while (bits < cap_bits) : (pad ^= 0xEC ^ 0x11) appendBits(&buf, &bits, pad, 8);

    var words: [max_codewords]u8 = undefined;
    addEccAndInterleave(buf[0..n_data], version, level, &words);

    const size: usize = version * 4 + 17;
    var b: Builder = .{ .size = size };
    b.drawFunctionPatterns(version, level);
    b.drawCodewords(words[0 .. rawModules(version) / 8]);

    var best: u3 = 0;
    if (force_mask) |m| {
        best = m;
    } else {
        var best_score: u32 = std.math.maxInt(u32);
        for (0..8) |mi| {
            const m: u3 = @intCast(mi);
            b.applyMask(m);
            b.drawFormatBits(level, m);
            const score = b.penalty();
            if (score < best_score) {
                best = m;
                best_score = score;
            }
            b.applyMask(m);
        }
    }
    b.applyMask(best);
    b.drawFormatBits(level, best);

    code.size = @intCast(size);
    code.version = @intCast(version);
    code.mask = best;
    @memcpy(code.dark[0 .. size * size], b.dark[0 .. size * size]);
}

fn appendBits(buf: []u8, len: *usize, value: usize, count: usize) void {
    var i: usize = count;
    while (i > 0) {
        i -= 1;
        const bit: u8 = @intCast((value >> @intCast(i)) & 1);
        buf[len.* >> 3] |= bit << @intCast(7 - (len.* & 7));
        len.* += 1;
    }
}

// ---------------------------------------------------------- Reed-Solomon

fn gfMul(x: u8, y: u8) u8 {
    var z: u32 = 0;
    var i: i32 = 7;
    while (i >= 0) : (i -= 1) {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        z ^= @as(u32, (y >> @intCast(i)) & 1) * x;
    }
    return @truncate(z);
}

fn rsDivisor(degree: usize, out: *[max_ecc]u8) void {
    @memset(out, 0);
    out[degree - 1] = 1;
    var root: u8 = 1;
    for (0..degree) |_| {
        for (0..degree) |j| {
            out[j] = gfMul(out[j], root);
            if (j + 1 < degree) out[j] ^= out[j + 1];
        }
        root = gfMul(root, 0x02);
    }
}

fn rsRemainder(data: []const u8, divisor: *const [max_ecc]u8, degree: usize, out: *[max_ecc]u8) void {
    @memset(out, 0);
    for (data) |b| {
        const factor = b ^ out[0];
        var i: usize = 0;
        while (i + 1 < degree) : (i += 1) out[i] = out[i + 1];
        out[degree - 1] = 0;
        for (0..degree) |j| out[j] ^= gfMul(divisor[j], factor);
    }
}

fn addEccAndInterleave(data: []const u8, version: usize, level: Level, out: *[max_codewords]u8) void {
    const l = @intFromEnum(level);
    const blocks: usize = num_blocks[l][version];
    const ecc_len: usize = ecc_per_block[l][version];
    const raw = rawModules(version) / 8;
    const short_blocks = blocks - raw % blocks;
    const short_len = raw / blocks;

    var divisor: [max_ecc]u8 = undefined;
    rsDivisor(ecc_len, &divisor);

    var eccs: [max_blocks][max_ecc]u8 = undefined;
    var starts: [max_blocks]usize = undefined;
    var lens: [max_blocks]usize = undefined;
    var k: usize = 0;
    for (0..blocks) |i| {
        const dat_len = short_len - ecc_len + @as(usize, if (i < short_blocks) 0 else 1);
        starts[i] = k;
        lens[i] = dat_len;
        rsRemainder(data[k .. k + dat_len], &divisor, ecc_len, &eccs[i]);
        k += dat_len;
    }

    var n: usize = 0;
    for (0..short_len - ecc_len + 1) |j| {
        for (0..blocks) |i| {
            if (j < lens[i]) {
                out[n] = data[starts[i] + j];
                n += 1;
            }
        }
    }
    for (0..ecc_len) |j| {
        for (0..blocks) |i| {
            out[n] = eccs[i][j];
            n += 1;
        }
    }
}

// ---------------------------------------------------------- the matrix

const Builder = struct {
    size: usize,
    dark: [max_size * max_size]bool = @splat(false),
    func: [max_size * max_size]bool = @splat(false),

    fn at(b: *const Builder, x: usize, y: usize) usize {
        return y * b.size + x;
    }

    fn setFunction(b: *Builder, x: i32, y: i32, dark: bool) void {
        const i = b.at(@intCast(x), @intCast(y));
        b.dark[i] = dark;
        b.func[i] = true;
    }

    fn drawFunctionPatterns(b: *Builder, version: usize, level: Level) void {
        const size: i32 = @intCast(b.size);
        for (0..b.size) |i| {
            const ii: i32 = @intCast(i);
            b.setFunction(6, ii, i % 2 == 0);
            b.setFunction(ii, 6, i % 2 == 0);
        }
        b.drawFinder(3, 3);
        b.drawFinder(size - 4, 3);
        b.drawFinder(3, size - 4);

        var pos: [7]i32 = undefined;
        const n = alignmentPositions(version, &pos);
        for (0..n) |i| {
            for (0..n) |j| {
                if ((i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0)) continue;
                b.drawAlignment(pos[i], pos[j]);
            }
        }
        b.drawFormatBits(level, 0);
        b.drawVersion(version);
    }

    fn drawFinder(b: *Builder, cx: i32, cy: i32) void {
        const size: i32 = @intCast(b.size);
        var dy: i32 = -4;
        while (dy <= 4) : (dy += 1) {
            var dx: i32 = -4;
            while (dx <= 4) : (dx += 1) {
                const dist = @max(@abs(dx), @abs(dy));
                const x = cx + dx;
                const y = cy + dy;
                if (x >= 0 and x < size and y >= 0 and y < size) b.setFunction(x, y, dist != 2 and dist != 4);
            }
        }
    }

    fn drawAlignment(b: *Builder, cx: i32, cy: i32) void {
        var dy: i32 = -2;
        while (dy <= 2) : (dy += 1) {
            var dx: i32 = -2;
            while (dx <= 2) : (dx += 1) b.setFunction(cx + dx, cy + dy, @max(@abs(dx), @abs(dy)) != 1);
        }
    }

    fn drawFormatBits(b: *Builder, level: Level, mask: u3) void {
        const size: i32 = @intCast(b.size);
        const level_bits: u32 = switch (level) {
            .low => 1,
            .medium => 0,
            .quartile => 3,
            .high => 2,
        };
        const data: u32 = (level_bits << 3) | mask;
        var rem: u32 = data;
        for (0..10) |_| rem = (rem << 1) ^ ((rem >> 9) * 0x537);
        const bits: u32 = ((data << 10) | rem) ^ 0x5412;

        var i: i32 = 0;
        while (i <= 5) : (i += 1) b.setFunction(8, i, fmtBit(bits, i));
        b.setFunction(8, 7, fmtBit(bits, 6));
        b.setFunction(8, 8, fmtBit(bits, 7));
        b.setFunction(7, 8, fmtBit(bits, 8));
        i = 9;
        while (i < 15) : (i += 1) b.setFunction(14 - i, 8, fmtBit(bits, i));

        i = 0;
        while (i < 8) : (i += 1) b.setFunction(size - 1 - i, 8, fmtBit(bits, i));
        i = 8;
        while (i < 15) : (i += 1) b.setFunction(8, size - 15 + i, fmtBit(bits, i));
        b.setFunction(8, size - 8, true);
    }

    fn drawVersion(b: *Builder, version: usize) void {
        if (version < 7) return;
        const size: i32 = @intCast(b.size);
        var rem: u32 = @intCast(version);
        for (0..12) |_| rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
        const bits: u32 = (@as(u32, @intCast(version)) << 12) | rem;
        var i: i32 = 0;
        while (i < 18) : (i += 1) {
            const bit = fmtBit(bits, i);
            const a = size - 11 + @mod(i, 3);
            const c = @divTrunc(i, 3);
            b.setFunction(a, c, bit);
            b.setFunction(c, a, bit);
        }
    }

    /// Zigzag placement of the codewords in the free modules.
    fn drawCodewords(b: *Builder, data: []const u8) void {
        const size: i32 = @intCast(b.size);
        var i: usize = 0;
        var right: i32 = size - 1;
        while (right >= 1) : (right -= 2) {
            if (right == 6) right = 5;
            var vert: i32 = 0;
            while (vert < size) : (vert += 1) {
                var j: i32 = 0;
                while (j < 2) : (j += 1) {
                    const x = right - j;
                    const upward = ((right + 1) & 2) == 0;
                    const y = if (upward) size - 1 - vert else vert;
                    const idx = b.at(@intCast(x), @intCast(y));
                    if (!b.func[idx] and i < data.len * 8) {
                        b.dark[idx] = ((data[i >> 3] >> @intCast(7 - (i & 7))) & 1) != 0;
                        i += 1;
                    }
                }
            }
        }
    }

    /// XORs the mask onto the data modules; applying it twice undoes it.
    fn applyMask(b: *Builder, mask: u3) void {
        for (0..b.size) |y| {
            for (0..b.size) |x| {
                const invert = switch (mask) {
                    0 => (x + y) % 2 == 0,
                    1 => y % 2 == 0,
                    2 => x % 3 == 0,
                    3 => (x + y) % 3 == 0,
                    4 => (x / 3 + y / 2) % 2 == 0,
                    5 => x * y % 2 + x * y % 3 == 0,
                    6 => (x * y % 2 + x * y % 3) % 2 == 0,
                    7 => ((x + y) % 2 + x * y % 3) % 2 == 0,
                };
                const idx = b.at(x, y);
                if (!b.func[idx] and invert) b.dark[idx] = !b.dark[idx];
            }
        }
    }

    // Penalty rules of the standard.
    const n1 = 3;
    const n2 = 3;
    const n3 = 40;
    const n4 = 10;

    fn penalty(b: *const Builder) u32 {
        const size = b.size;
        var result: u32 = 0;

        // Runs in rows and columns, and finder-like patterns.
        for (0..2) |dir| {
            for (0..size) |a| {
                var run_color = false;
                var run_len: usize = 0;
                var history: [7]usize = @splat(0);
                for (0..size) |c| {
                    const color = if (dir == 0) b.dark[b.at(c, a)] else b.dark[b.at(a, c)];
                    if (color == run_color) {
                        run_len += 1;
                        if (run_len == 5) result += n1 else if (run_len > 5) result += 1;
                    } else {
                        finderAddHistory(size, run_len, &history);
                        if (!run_color) result += finderCount(&history) * n3;
                        run_color = color;
                        run_len = 1;
                    }
                }
                result += finderTerminate(size, run_color, run_len, &history) * n3;
            }
        }

        // 2 x 2 blocks of one color.
        for (0..size - 1) |y| {
            for (0..size - 1) |x| {
                const c = b.dark[b.at(x, y)];
                if (c == b.dark[b.at(x + 1, y)] and c == b.dark[b.at(x, y + 1)] and c == b.dark[b.at(x + 1, y + 1)]) result += n2;
            }
        }

        // Balance of dark and light modules.
        var dark: usize = 0;
        for (b.dark[0 .. size * size]) |d| {
            if (d) dark += 1;
        }
        const total = size * size;
        const diff = if (dark * 20 > total * 10) dark * 20 - total * 10 else total * 10 - dark * 20;
        const k = (diff + total - 1) / total - 1;
        result += @intCast(k * n4);
        return result;
    }
};

fn fmtBit(bits: u32, i: i32) bool {
    return ((bits >> @intCast(i)) & 1) != 0;
}

fn finderCount(h: *const [7]usize) u32 {
    const n = h[1];
    const core = n > 0 and h[2] == n and h[3] == n * 3 and h[4] == n and h[5] == n;
    var r: u32 = 0;
    if (core and h[0] >= n * 4 and h[6] >= n) r += 1;
    if (core and h[6] >= n * 4 and h[0] >= n) r += 1;
    return r;
}

fn finderTerminate(size: usize, run_color: bool, run_len_in: usize, h: *[7]usize) u32 {
    var run_len = run_len_in;
    if (run_color) {
        finderAddHistory(size, run_len, h);
        run_len = 0;
    }
    run_len += size;
    finderAddHistory(size, run_len, h);
    return finderCount(h);
}

fn finderAddHistory(size: usize, run_len_in: usize, h: *[7]usize) void {
    var run_len = run_len_in;
    if (h[0] == 0) run_len += size;
    var i: usize = 6;
    while (i > 0) : (i -= 1) h[i] = h[i - 1];
    h[0] = run_len;
}

/// Centres of the alignment patterns along one axis; returns how many.
fn alignmentPositions(version: usize, out: *[7]i32) usize {
    if (version == 1) return 0;
    const n = version / 7 + 2;
    const size: i32 = @intCast(version * 4 + 17);
    const step: i32 = if (version == 32) 26 else blk: {
        const v: i32 = @intCast(version);
        const nn: i32 = @intCast(n);
        break :blk @divTrunc(v * 8 + nn * 3 + 5, nn * 4 - 4) * 2;
    };
    out[0] = 6;
    var pos: i32 = size - 7;
    var i: usize = n - 1;
    while (i >= 1) : (i -= 1) {
        out[i] = pos;
        pos -= step;
    }
    return n;
}

// ---------------------------------------------------------- tests

const testing = std.testing;

test "capacity of the version 1 to 40 symbols" {
    // Total data modules and byte capacities from the standard.
    try testing.expectEqual(@as(usize, 208), rawModules(1));
    try testing.expectEqual(@as(usize, 3706 * 8 + 0), rawModules(40));
    try testing.expectEqual(@as(usize, 2953), capacity(.low));
    try testing.expectEqual(@as(usize, 2331), capacity(.medium));
    try testing.expectEqual(@as(usize, 1663), capacity(.quartile));
    try testing.expectEqual(@as(usize, 1273), capacity(.high));
}

test "hello world fits in version 1 at level Q" {
    var c: Code = .{};
    try encode(&c, "HELLO WORLD", .quartile, null);
    try testing.expectEqual(@as(u8, 1), c.version);
    try testing.expectEqual(@as(u8, 21), c.size);
    // Finder patterns.
    try testing.expect(c.get(0, 0) and c.get(6, 0) and c.get(0, 6) and !c.get(1, 1) and c.get(2, 2));
    try testing.expect(c.get(14, 0) and c.get(20, 20 - 14));
    // The module left of the lower-left finder's separator is always dark.
    try testing.expect(c.get(8, 21 - 8));
}

test "too much data" {
    var c: Code = .{};
    var big: [3000]u8 = @splat('a');
    try testing.expectError(error.TooLong, encode(&c, &big, .low, null));
    try encode(&c, big[0..2953], .low, null);
    try testing.expectEqual(@as(u8, 40), c.version);
}

test "alignment positions" {
    var p: [7]i32 = undefined;
    try testing.expectEqual(@as(usize, 0), alignmentPositions(1, &p));
    try testing.expectEqual(@as(usize, 2), alignmentPositions(2, &p));
    try testing.expectEqualSlices(i32, &.{ 6, 18 }, p[0..2]);
    try testing.expectEqual(@as(usize, 3), alignmentPositions(7, &p));
    try testing.expectEqualSlices(i32, &.{ 6, 22, 38 }, p[0..3]);
    try testing.expectEqual(@as(usize, 7), alignmentPositions(40, &p));
    try testing.expectEqualSlices(i32, &.{ 6, 30, 58, 86, 114, 142, 170 }, p[0..7]);
    try testing.expectEqual(@as(usize, 6), alignmentPositions(32, &p));
    try testing.expectEqualSlices(i32, &.{ 6, 34, 60, 86, 112, 138 }, p[0..6]);
}
