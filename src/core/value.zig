//! Runtime values and static types shared by params, card data and expressions.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// 16-bit RGBA with straight (not premultiplied) alpha.
pub const Color = struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const white: Color = .{ .r = 65535, .g = 65535, .b = 65535, .a = 65535 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 65535 };

    pub fn eql(a: Color, b: Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }

    /// Parses `#RRGGBB`, `#RRGGBBAA`, `#RRRRGGGGBBBB` or `#RRRRGGGGBBBBAAAA`.
    pub fn parseHex(s: []const u8) ?Color {
        if (s.len < 1 or s[0] != '#') return null;
        const h = s[1..];
        for (h) |ch| if (!std.ascii.isHex(ch)) return null;
        return switch (h.len) {
            // CSS short forms: each digit doubled, #F80 is #FF8800.
            3, 4 => .{
                .r = hex4(h[0]) * 0x1111,
                .g = hex4(h[1]) * 0x1111,
                .b = hex4(h[2]) * 0x1111,
                .a = if (h.len == 4) hex4(h[3]) * 0x1111 else 65535,
            },
            6, 8 => .{
                .r = hex8(h[0..2]) * 257,
                .g = hex8(h[2..4]) * 257,
                .b = hex8(h[4..6]) * 257,
                .a = if (h.len == 8) hex8(h[6..8]) * 257 else 65535,
            },
            12, 16 => .{
                .r = hex16(h[0..4]),
                .g = hex16(h[4..8]),
                .b = hex16(h[8..12]),
                .a = if (h.len == 16) hex16(h[12..16]) else 65535,
            },
            else => null,
        };
    }

    fn hex4(c: u8) u16 {
        return std.fmt.charToDigit(c, 16) catch 0;
    }

    fn hex8(s: []const u8) u16 {
        return std.fmt.parseInt(u8, s, 16) catch 0;
    }

    fn hex16(s: []const u8) u16 {
        return std.fmt.parseInt(u16, s, 16) catch 0;
    }

    /// `#RRGGBBAA` with 8-bit channels.
    pub fn hex8String(c: Color, buf: *[9]u8) []const u8 {
        return std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{
            to8(c.r), to8(c.g), to8(c.b), to8(c.a),
        }) catch unreachable;
    }

    fn to8(v: u16) u8 {
        return @intCast((@as(u32, v) * 255 + 32767) / 65535);
    }
};

/// Scalar field types used by list items.
pub const Scalar = enum {
    number,
    bool,
    text,
    color,
    image,

    pub fn fromName(s: []const u8) ?Scalar {
        if (std.mem.eql(u8, s, "integer")) return .number;
        return std.meta.stringToEnum(Scalar, s);
    }

    pub fn zero(s: Scalar) Value {
        return switch (s) {
            .number => .{ .number = 0 },
            .bool => .{ .bool = false },
            .text => .{ .text = "" },
            .color => .{ .color = Color.transparent },
            .image => .{ .image = "" },
        };
    }

    pub fn toType(s: Scalar) Type {
        return switch (s) {
            .number => .number,
            .bool => .bool,
            .text => .text,
            .color => .color,
            .image => .image,
        };
    }
};

/// The fields of a list param's items.
pub const ItemDef = struct {
    names: []const []const u8,
    types: []const Scalar,
    /// Per field: the allowed words of an enum field, empty otherwise.
    options: []const []const []const u8 = &.{},
    /// Per field: the value an item gets when it leaves the field out.
    defaults: []const ?Value = &.{},

    pub fn optionsOf(self: *const ItemDef, i: usize) []const []const u8 {
        return if (i < self.options.len) self.options[i] else &.{};
    }

    pub fn defaultOf(self: *const ItemDef, i: usize) Value {
        if (i < self.defaults.len) if (self.defaults[i]) |v| return v;
        const opts = self.optionsOf(i);
        if (opts.len > 0) return .{ .text = opts[0] };
        return self.types[i].zero();
    }

    pub fn find(self: *const ItemDef, name: []const u8) ?usize {
        for (self.names, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return i;
        }
        return null;
    }
};

pub const Type = union(enum) {
    number,
    bool,
    text,
    color,
    image,
    list: *const ItemDef,
    item: *const ItemDef,

    pub fn name(t: Type) []const u8 {
        return switch (t) {
            .number => "number",
            .bool => "bool",
            .text => "text",
            .color => "color",
            .image => "image",
            .list => "list",
            .item => "list item",
        };
    }

    pub fn eql(a: Type, b: Type) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .list => |d| d == b.list,
            .item => |d| d == b.item,
            else => true,
        };
    }

    /// Text and image paths compare with each other.
    pub fn comparable(a: Type, b: Type) bool {
        const at = a == .text or a == .image;
        const bt = b == .text or b == .image;
        if (at and bt) return true;
        return eql(a, b) and a != .list and a != .item;
    }
};

pub const Value = union(enum) {
    number: f64,
    bool: bool,
    text: []const u8,
    color: Color,
    /// A project path or https URL.
    image: []const u8,
    list: []const []const Value,
    item: []const Value,

    pub fn eql(a: Value, b: Value) bool {
        return switch (a) {
            .number => |x| b == .number and x == b.number,
            .bool => |x| b == .bool and x == b.bool,
            .text, .image => |x| switch (b) {
                .text, .image => |y| std.mem.eql(u8, x, y),
                else => false,
            },
            .color => |x| b == .color and x.eql(b.color),
            .list, .item => false,
        };
    }

    /// A deep copy in `arena`.
    pub fn dupe(v: Value, arena: Allocator) Allocator.Error!Value {
        return switch (v) {
            .number, .bool, .color => v,
            .text => |x| .{ .text = try arena.dupe(u8, x) },
            .image => |x| .{ .image = try arena.dupe(u8, x) },
            .item => |fields| .{ .item = try dupeAll(fields, arena) },
            .list => |items| blk: {
                const out = try arena.alloc([]const Value, items.len);
                for (items, out) |it, *o| o.* = try dupeAll(it, arena);
                break :blk .{ .list = out };
            },
        };
    }

    fn dupeAll(vs: []const Value, arena: Allocator) Allocator.Error![]const Value {
        const out = try arena.alloc(Value, vs.len);
        for (vs, out) |x, *o| o.* = try x.dupe(arena);
        return out;
    }
};

/// Shortest readable decimal: 5, 0.5, never 5.0.
pub fn writeNumber(w: *std.Io.Writer, x: f64) std.Io.Writer.Error!void {
    if (x == 0) return w.writeByte('0');
    if (x == @trunc(x) and @abs(x) < 1e15) {
        return w.print("{d}", .{@as(i64, @intFromFloat(x))});
    }
    try w.print("{d}", .{x});
}

/// Number as shown to the reader in rendered text (template `{...}` and
/// join()): rounded to 12 significant digits, trailing zeros and a trailing
/// dot dropped, -0 as 0. Plain digits for 1e-7 <= |x| < 1e21 (the JS range),
/// so 0.1 + 0.2 is 0.3 and 1e15 is 1000000000000000. Outside that range the
/// exponent form is used with no plus sign: 1.5e-8, 1e21. Not for round-trip
/// output (source, JSON); use writeNumber there.
pub fn writeDisplayNumber(w: *std.Io.Writer, x: f64) std.Io.Writer.Error!void {
    if (x == 0) return w.writeByte('0');
    if (!std.math.isFinite(x)) return writeNumber(w, x);
    if (x < 0) try w.writeByte('-');

    // "{e:.11}" rounds correctly to 12 significant digits: d.dddddddddddde[-]N.
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{e:.11}", .{@abs(x)}) catch unreachable;
    var digits: [12]u8 = undefined;
    var n: usize = 0;
    var exp: i32 = 0;
    for (s, 0..) |c, i| {
        if (c == 'e') {
            exp = std.fmt.parseInt(i32, s[i + 1 ..], 10) catch unreachable;
            break;
        }
        if (c != '.') {
            digits[n] = c;
            n += 1;
        }
    }
    while (n > 1 and digits[n - 1] == '0') n -= 1;

    if (exp >= 21 or exp < -7) {
        try w.writeByte(digits[0]);
        if (n > 1) {
            try w.writeByte('.');
            try w.writeAll(digits[1..n]);
        }
        return w.print("e{d}", .{exp});
    }
    if (exp >= 0) {
        const int_len: usize = @intCast(exp + 1);
        for (0..int_len) |i| try w.writeByte(if (i < n) digits[i] else '0');
        if (n > int_len) {
            try w.writeByte('.');
            try w.writeAll(digits[int_len..n]);
        }
    } else {
        try w.writeAll("0.");
        for (0..@as(usize, @intCast(-exp - 1))) |_| try w.writeByte('0');
        try w.writeAll(digits[0..n]);
    }
}

test "display number: 12 significant digits, trimmed" {
    const cases = [_]struct { x: f64, want: []const u8 }{
        .{ .x = 0.1 + 0.2, .want = "0.3" },
        .{ .x = 1.0 / 3.0, .want = "0.333333333333" },
        .{ .x = 2.0 / 3.0, .want = "0.666666666667" },
        .{ .x = 100.0 / 3.0, .want = "33.3333333333" },
        .{ .x = 1e15, .want = "1000000000000000" },
        .{ .x = 12.5, .want = "12.5" },
        .{ .x = 3, .want = "3" },
        .{ .x = -2.5, .want = "-2.5" },
        .{ .x = -0.0, .want = "0" },
        .{ .x = 0, .want = "0" },
        .{ .x = 123456789012345.67, .want = "123456789012000" },
        .{ .x = 0.999999999999999, .want = "1" },
        .{ .x = 12345.6789012345, .want = "12345.6789012" },
        .{ .x = 1.005, .want = "1.005" },
        .{ .x = 0.5, .want = "0.5" },
        .{ .x = 0.0000001, .want = "0.0000001" },
        .{ .x = 1.5e-8, .want = "1.5e-8" },
        .{ .x = -3e-12, .want = "-3e-12" },
        .{ .x = 1e20, .want = "100000000000000000000" },
        .{ .x = 1e21, .want = "1e21" },
        .{ .x = -1.25e25, .want = "-1.25e25" },
    };
    for (cases) |c| {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeDisplayNumber(&aw.writer, c.x);
        try std.testing.expectEqualStrings(c.want, aw.written());
    }
}

pub fn numberToText(arena: Allocator, x: f64) Allocator.Error![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    writeNumber(&aw.writer, x) catch return error.OutOfMemory;
    return aw.written();
}

test "color parse" {
    const c = Color.parseHex("#FF000080").?;
    try std.testing.expectEqual(@as(u16, 65535), c.r);
    try std.testing.expectEqual(@as(u16, 0x80 * 257), c.a);
    try std.testing.expect(Color.parseHex("#FFF").?.eql(Color.parseHex("#FFFFFF").?));
    try std.testing.expect(Color.parseHex("#F80A").?.eql(Color.parseHex("#FF8800AA").?));
    try std.testing.expect(Color.parseHex("#FFFFF") == null);
    var buf: [9]u8 = undefined;
    try std.testing.expectEqualStrings("#FF000080", c.hex8String(&buf));
}
