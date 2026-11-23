//! Data Matrix ECC 200 (ISO/IEC 16022), square symbols from 10 x 10 to
//! 144 x 144. Text is encoded in ASCII mode with digit pairs packed two to
//! a codeword; bytes above 127 use the upper shift.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sym = @import("symbol.zig");
const Symbol = sym.Symbol;
const Problem = sym.Problem;
const Error = sym.Error;
const problem = sym.problem;

/// One symbol size: the modules per side, the data regions (a grid of
/// `regions` by `regions`, each `region` modules square), the codewords.
const Size = struct {
    side: u8,
    regions: u8,
    region: u8,
    data: u16,
    ecc_total: u16,
    blocks: u8,
};

const sizes = [_]Size{
    .{ .side = 10, .regions = 1, .region = 8, .data = 3, .ecc_total = 5, .blocks = 1 },
    .{ .side = 12, .regions = 1, .region = 10, .data = 5, .ecc_total = 7, .blocks = 1 },
    .{ .side = 14, .regions = 1, .region = 12, .data = 8, .ecc_total = 10, .blocks = 1 },
    .{ .side = 16, .regions = 1, .region = 14, .data = 12, .ecc_total = 12, .blocks = 1 },
    .{ .side = 18, .regions = 1, .region = 16, .data = 18, .ecc_total = 14, .blocks = 1 },
    .{ .side = 20, .regions = 1, .region = 18, .data = 22, .ecc_total = 18, .blocks = 1 },
    .{ .side = 22, .regions = 1, .region = 20, .data = 30, .ecc_total = 20, .blocks = 1 },
    .{ .side = 24, .regions = 1, .region = 22, .data = 36, .ecc_total = 24, .blocks = 1 },
    .{ .side = 26, .regions = 1, .region = 24, .data = 44, .ecc_total = 28, .blocks = 1 },
    .{ .side = 32, .regions = 2, .region = 14, .data = 62, .ecc_total = 36, .blocks = 1 },
    .{ .side = 36, .regions = 2, .region = 16, .data = 86, .ecc_total = 42, .blocks = 1 },
    .{ .side = 40, .regions = 2, .region = 18, .data = 114, .ecc_total = 48, .blocks = 1 },
    .{ .side = 44, .regions = 2, .region = 20, .data = 144, .ecc_total = 56, .blocks = 1 },
    .{ .side = 48, .regions = 2, .region = 22, .data = 174, .ecc_total = 68, .blocks = 1 },
    .{ .side = 52, .regions = 2, .region = 24, .data = 204, .ecc_total = 84, .blocks = 2 },
    .{ .side = 64, .regions = 4, .region = 14, .data = 280, .ecc_total = 112, .blocks = 2 },
    .{ .side = 72, .regions = 4, .region = 16, .data = 368, .ecc_total = 144, .blocks = 4 },
    .{ .side = 80, .regions = 4, .region = 18, .data = 456, .ecc_total = 192, .blocks = 4 },
    .{ .side = 88, .regions = 4, .region = 20, .data = 576, .ecc_total = 224, .blocks = 4 },
    .{ .side = 96, .regions = 4, .region = 22, .data = 696, .ecc_total = 272, .blocks = 4 },
    .{ .side = 104, .regions = 4, .region = 24, .data = 816, .ecc_total = 336, .blocks = 6 },
    .{ .side = 120, .regions = 6, .region = 18, .data = 1050, .ecc_total = 408, .blocks = 6 },
    .{ .side = 132, .regions = 6, .region = 20, .data = 1304, .ecc_total = 496, .blocks = 8 },
    .{ .side = 144, .regions = 6, .region = 22, .data = 1558, .ecc_total = 620, .blocks = 10 },
};

/// Largest number of data codewords of any size.
pub const max_codewords = 1558;

// GF(256) with the polynomial x^8 + x^5 + x^3 + x^2 + 1 (0x12D).
const Gf = struct {
    exp: [512]u8,
    log: [256]u8,

    fn init() Gf {
        var g: Gf = .{ .exp = undefined, .log = undefined };
        var x: u16 = 1;
        for (0..255) |i| {
            g.exp[i] = @intCast(x);
            g.log[x] = @intCast(i);
            x <<= 1;
            if (x & 0x100 != 0) x ^= 0x12D;
        }
        for (255..512) |i| g.exp[i] = g.exp[i - 255];
        g.log[0] = 0;
        return g;
    }

    fn mul(g: *const Gf, a: u8, b: u8) u8 {
        if (a == 0 or b == 0) return 0;
        return g.exp[@as(usize, g.log[a]) + g.log[b]];
    }
};

const gf = Gf.init();

/// Error correction codewords of `data`: the remainder of data * x^n
/// divided by the generator with roots 2^1 .. 2^n.
fn rsEncode(data: []const u8, ecc: []u8) void {
    const n = ecc.len;
    var gen: [70]u8 = undefined;
    gen[0] = 1;
    var deg: usize = 0;
    for (1..n + 1) |root| {
        // Multiply the generator by (x + 2^root).
        const r = gf.exp[root];
        gen[deg + 1] = 0;
        var i = deg + 1;
        while (i > 0) : (i -= 1) {
            gen[i] = gen[i - 1] ^ gf.mul(gen[i], r);
        }
        gen[0] = gf.mul(gen[0], r);
        deg += 1;
    }
    @memset(ecc, 0);
    for (data) |d| {
        const f = d ^ ecc[0];
        for (0..n - 1) |i| ecc[i] = ecc[i + 1] ^ gf.mul(gen[n - 1 - i], f);
        ecc[n - 1] = gf.mul(gen[0], f);
    }
}

/// ASCII-mode codewords of `text`.
fn encodeAscii(a: Allocator, text: []const u8) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (std.ascii.isDigit(c) and i + 1 < text.len and std.ascii.isDigit(text[i + 1])) {
            try out.append(a, 130 + (c - '0') * 10 + (text[i + 1] - '0'));
            i += 2;
        } else if (c < 128) {
            try out.append(a, c + 1);
            i += 1;
        } else {
            try out.append(a, 235);
            try out.append(a, c - 128 + 1);
            i += 1;
        }
    }
    return out.items;
}

pub fn capacityDigits() usize {
    return max_codewords * 2;
}

const Place = struct {
    nrow: usize,
    ncol: usize,
    chr: []u16,
    bit: []u8,

    fn module(p: *Place, row_in: isize, col_in: isize, chr: u16, bit: u8) void {
        var row = row_in;
        var col = col_in;
        const nrow: isize = @intCast(p.nrow);
        const ncol: isize = @intCast(p.ncol);
        if (row < 0) {
            row += nrow;
            col += 4 - @mod(nrow + 4, 8);
        }
        if (col < 0) {
            col += ncol;
            row += 4 - @mod(ncol + 4, 8);
        }
        const idx: usize = @intCast(row * ncol + col);
        p.chr[idx] = chr;
        p.bit[idx] = bit;
    }

    fn utah(p: *Place, row: isize, col: isize, chr: u16) void {
        p.module(row - 2, col - 2, chr, 1);
        p.module(row - 2, col - 1, chr, 2);
        p.module(row - 1, col - 2, chr, 3);
        p.module(row - 1, col - 1, chr, 4);
        p.module(row - 1, col, chr, 5);
        p.module(row, col - 2, chr, 6);
        p.module(row, col - 1, chr, 7);
        p.module(row, col, chr, 8);
    }

    fn corner(p: *Place, which: u8, chr: u16) void {
        const nr: isize = @intCast(p.nrow);
        const nc: isize = @intCast(p.ncol);
        switch (which) {
            1 => {
                p.module(nr - 1, 0, chr, 1);
                p.module(nr - 1, 1, chr, 2);
                p.module(nr - 1, 2, chr, 3);
                p.module(0, nc - 2, chr, 4);
                p.module(0, nc - 1, chr, 5);
                p.module(1, nc - 1, chr, 6);
                p.module(2, nc - 1, chr, 7);
                p.module(3, nc - 1, chr, 8);
            },
            2 => {
                p.module(nr - 3, 0, chr, 1);
                p.module(nr - 2, 0, chr, 2);
                p.module(nr - 1, 0, chr, 3);
                p.module(0, nc - 4, chr, 4);
                p.module(0, nc - 3, chr, 5);
                p.module(0, nc - 2, chr, 6);
                p.module(0, nc - 1, chr, 7);
                p.module(1, nc - 1, chr, 8);
            },
            3 => {
                p.module(nr - 3, 0, chr, 1);
                p.module(nr - 2, 0, chr, 2);
                p.module(nr - 1, 0, chr, 3);
                p.module(0, nc - 2, chr, 4);
                p.module(0, nc - 1, chr, 5);
                p.module(1, nc - 1, chr, 6);
                p.module(2, nc - 1, chr, 7);
                p.module(3, nc - 1, chr, 8);
            },
            else => {
                p.module(nr - 1, 0, chr, 1);
                p.module(nr - 1, nc - 1, chr, 2);
                p.module(0, nc - 3, chr, 3);
                p.module(0, nc - 2, chr, 4);
                p.module(0, nc - 1, chr, 5);
                p.module(1, nc - 3, chr, 6);
                p.module(1, nc - 2, chr, 7);
                p.module(1, nc - 1, chr, 8);
            },
        }
    }

    /// The placement of ISO/IEC 16022 annex F: codewords snake diagonally
    /// through the mapping matrix, with four special corner shapes.
    fn run(p: *Place) void {
        const nrow: isize = @intCast(p.nrow);
        const ncol: isize = @intCast(p.ncol);
        var chr: u16 = 1;
        var row: isize = 4;
        var col: isize = 0;
        while (true) {
            if (row == nrow and col == 0) {
                p.corner(1, chr);
                chr += 1;
            }
            if (row == nrow - 2 and col == 0 and @mod(ncol, 4) != 0) {
                p.corner(2, chr);
                chr += 1;
            }
            if (row == nrow - 2 and col == 0 and @mod(ncol, 8) == 4) {
                p.corner(3, chr);
                chr += 1;
            }
            if (row == nrow + 4 and col == 2 and @mod(ncol, 8) == 0) {
                p.corner(4, chr);
                chr += 1;
            }
            while (true) {
                if (row < nrow and col >= 0 and p.chr[@intCast(row * ncol + col)] == 0) {
                    p.utah(row, col, chr);
                    chr += 1;
                }
                row -= 2;
                col += 2;
                if (!(row >= 0 and col < ncol)) break;
            }
            row += 1;
            col += 3;
            while (true) {
                if (row >= 0 and col < ncol and p.chr[@intCast(row * ncol + col)] == 0) {
                    p.utah(row, col, chr);
                    chr += 1;
                }
                row += 2;
                col -= 2;
                if (!(row < nrow and col >= 0)) break;
            }
            row += 3;
            col += 1;
            if (!(row < nrow or col < ncol)) break;
        }
    }
};

pub fn encode(a: Allocator, prob: *Problem, text: []const u8) Error!Symbol {
    if (text.len == 0) return problem(a, prob, "Data Matrix needs text, but it is empty", .{}, null);
    const words = try encodeAscii(a, text);
    var chosen: ?Size = null;
    for (sizes) |s| if (words.len <= s.data) {
        chosen = s;
        break;
    };
    const size = chosen orelse return problem(a, prob, "the text needs {d} codewords, but a Data Matrix holds at most {d} (about {d} digits or {d} letters)", .{ words.len, max_codewords, max_codewords * 2, max_codewords - 1 }, "shorten the text, or use a QR code or Aztec code");

    // Pad: 129, then the scrambled pad codewords.
    const data = try a.alloc(u8, size.data);
    @memcpy(data[0..words.len], words);
    for (words.len..data.len) |i| {
        if (i == words.len) {
            data[i] = 129;
        } else {
            const k: usize = i + 1;
            var v: usize = 129 + (149 * k) % 253 + 1;
            if (v > 254) v -= 254;
            data[i] = @intCast(v);
        }
    }

    // Error correction per block, interleaved.
    const nb: usize = size.blocks;
    const ecc_per = size.ecc_total / nb;
    const total = size.data + size.ecc_total;
    const stream = try a.alloc(u8, total);
    const ecc_all = try a.alloc(u8, size.ecc_total);
    {
        const block = try a.alloc(u8, (size.data + nb - 1) / nb);
        for (0..nb) |b| {
            var len: usize = 0;
            var i = b;
            while (i < size.data) : (i += nb) {
                block[len] = data[i];
                len += 1;
            }
            const ecc = try a.alloc(u8, ecc_per);
            rsEncode(block[0..len], ecc);
            for (ecc, 0..) |e, j| ecc_all[j * nb + b] = e;
        }
    }
    @memcpy(stream[0..size.data], data);
    @memcpy(stream[size.data..], ecc_all);

    // Place into the mapping matrix, then into the data regions.
    const side: usize = size.side;
    const regions: usize = size.regions;
    const rs: usize = size.region;
    const nrow = regions * rs;
    const ncol = nrow;
    var pl: Place = .{ .nrow = nrow, .ncol = ncol, .chr = try a.alloc(u16, nrow * ncol), .bit = try a.alloc(u8, nrow * ncol) };
    @memset(pl.chr, 0);
    @memset(pl.bit, 0);
    pl.run();
    // The bottom right corner is a fixed pattern when nothing landed there.
    var fixed_corner = false;
    if (pl.chr[nrow * ncol - 1] == 0) fixed_corner = true;

    const cells = try a.alloc(bool, side * side);
    @memset(cells, false);
    for (0..regions) |ry| for (0..regions) |rx| {
        const ox = rx * (rs + 2);
        const oy = ry * (rs + 2);
        for (0..rs + 2) |i| {
            cells[(oy + i) * side + ox] = true; // left: solid
            cells[(oy + rs + 1) * side + ox + i] = true; // bottom: solid
            if (i % 2 == 0) cells[oy * side + ox + i] = true; // top: alternating
            if (i % 2 == 1) cells[(oy + i) * side + ox + rs + 1] = true; // right: alternating
        }
    };
    for (0..nrow) |r| for (0..ncol) |c| {
        const idx = r * ncol + c;
        var v = false;
        if (pl.chr[idx] != 0) {
            const cw = stream[pl.chr[idx] - 1];
            v = (cw >> @intCast(8 - pl.bit[idx])) & 1 == 1;
        } else if (fixed_corner and (idx == nrow * ncol - 1 or idx == nrow * ncol - ncol - 2)) {
            v = true;
        }
        const y = (r / rs) * (rs + 2) + 1 + r % rs;
        const x = (c / rs) * (rs + 2) + 1 + c % rs;
        cells[y * side + x] = v;
    };

    return .{
        .format = .datamatrix,
        .w = side,
        .h = side,
        .cells = cells,
        .normalized = text,
        .version = size.side,
        .capacity = max_codewords,
    };
}

test "Data Matrix 10 x 10 holds a short text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prob: Problem = .{};
    const s = try encode(arena.allocator(), &prob, "123456");
    try std.testing.expectEqual(@as(usize, 10), s.w);
    const t = try encode(arena.allocator(), &prob, "Hello, Data Matrix!");
    try std.testing.expectEqual(@as(usize, 20), t.w);
    // The left edge is solid, the top edge alternates.
    for (0..t.h) |y| try std.testing.expect(t.get(0, y));
    try std.testing.expect(t.get(0, 0) and !t.get(1, 0) and t.get(2, 0));
}
