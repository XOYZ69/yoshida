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
};

/// Shortest readable decimal: 5, 0.5, never 5.0.
pub fn writeNumber(w: *std.Io.Writer, x: f64) std.Io.Writer.Error!void {
    if (x == 0) return w.writeByte('0');
    if (x == @trunc(x) and @abs(x) < 1e15) {
        return w.print("{d}", .{@as(i64, @intFromFloat(x))});
    }
    try w.print("{d}", .{x});
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
    try std.testing.expect(Color.parseHex("#FFF") == null);
    var buf: [9]u8 = undefined;
    try std.testing.expectEqualStrings("#FF000080", c.hex8String(&buf));
}
