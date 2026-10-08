//! A small JSON parser that keeps the byte offset of every value and key, so
//! diagnostics can point at a line and column. Objects keep their key order.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Node = struct {
    pos: u32,
    data: Data,

    pub const Data = union(enum) {
        null,
        bool: bool,
        number: f64,
        string: []const u8,
        array: []const Node,
        object: []const Field,
    };

    pub const Field = struct {
        key: []const u8,
        key_pos: u32,
        value: Node,
    };

    pub fn get(self: *const Node, key: []const u8) ?*const Node {
        const fields = switch (self.data) {
            .object => |o| o,
            else => return null,
        };
        for (fields) |*f| {
            if (std.mem.eql(u8, f.key, key)) return &f.value;
        }
        return null;
    }

    pub fn kindName(self: *const Node) []const u8 {
        return switch (self.data) {
            .null => "null",
            .bool => "a bool",
            .number => "a number",
            .string => "a string",
            .array => "an array",
            .object => "an object",
        };
    }
};

pub const Error = struct {
    pos: u32,
    message: []const u8,
};

pub const Result = union(enum) {
    ok: Node,
    err: Error,
};

pub fn parse(arena: Allocator, src: []const u8) Allocator.Error!Result {
    var p: Parser = .{ .arena = arena, .src = src };
    p.skipWs();
    const node = p.value(0) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Syntax => return .{ .err = p.err },
    };
    p.skipWs();
    if (p.i < src.len) {
        p.fail("unexpected content after the end of the document");
        return .{ .err = p.err };
    }
    return .{ .ok = node };
}

const ParseError = error{ Syntax, OutOfMemory };

const Parser = struct {
    arena: Allocator,
    src: []const u8,
    i: usize = 0,
    err: Error = .{ .pos = 0, .message = "" },

    fn fail(p: *Parser, msg: []const u8) void {
        p.err = .{ .pos = @intCast(@min(p.i, p.src.len)), .message = msg };
    }

    fn skipWs(p: *Parser) void {
        while (p.i < p.src.len) : (p.i += 1) {
            switch (p.src[p.i]) {
                ' ', '\t', '\n', '\r' => {},
                else => return,
            }
        }
    }

    fn value(p: *Parser, depth: u32) ParseError!Node {
        if (depth > 128) {
            p.fail("nesting is too deep");
            return error.Syntax;
        }
        if (p.i >= p.src.len) {
            p.fail("unexpected end of file");
            return error.Syntax;
        }
        const pos: u32 = @intCast(p.i);
        switch (p.src[p.i]) {
            '{' => return .{ .pos = pos, .data = .{ .object = try p.object(depth) } },
            '[' => return .{ .pos = pos, .data = .{ .array = try p.array(depth) } },
            '"' => return .{ .pos = pos, .data = .{ .string = try p.string() } },
            't' => return p.keyword("true", .{ .pos = pos, .data = .{ .bool = true } }),
            'f' => return p.keyword("false", .{ .pos = pos, .data = .{ .bool = false } }),
            'n' => return p.keyword("null", .{ .pos = pos, .data = .null }),
            '-', '0'...'9' => return .{ .pos = pos, .data = .{ .number = try p.number() } },
            else => {
                p.fail(switch (p.src[p.i]) {
                    '\'' => "strings use double quotes in JSON",
                    '/' => "comments are not allowed in JSON; use a \"note\" field",
                    else => "expected a value",
                });
                return error.Syntax;
            },
        }
    }

    fn keyword(p: *Parser, word: []const u8, node: Node) ParseError!Node {
        if (!std.mem.startsWith(u8, p.src[p.i..], word)) {
            p.fail("expected a value");
            return error.Syntax;
        }
        p.i += word.len;
        return node;
    }

    fn number(p: *Parser) ParseError!f64 {
        const start = p.i;
        if (p.src[p.i] == '-') p.i += 1;
        while (p.i < p.src.len) : (p.i += 1) {
            switch (p.src[p.i]) {
                '0'...'9', '.', 'e', 'E', '+', '-' => {},
                else => break,
            }
        }
        const text = p.src[start..p.i];
        const v = std.fmt.parseFloat(f64, text) catch {
            p.i = start;
            p.fail("invalid number");
            return error.Syntax;
        };
        if (!std.math.isFinite(v)) {
            p.i = start;
            p.fail("number out of range");
            return error.Syntax;
        }
        return v;
    }

    fn string(p: *Parser) ParseError![]const u8 {
        p.i += 1; // opening quote
        const start = p.i;
        // Fast path: no escapes.
        while (p.i < p.src.len) : (p.i += 1) {
            const ch = p.src[p.i];
            if (ch == '"') {
                const s = p.src[start..p.i];
                p.i += 1;
                return s;
            }
            if (ch == '\\') break;
            if (ch < 0x20) {
                p.fail("control character in string (use \\n)");
                return error.Syntax;
            }
        }
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(p.arena, p.src[start..p.i]);
        while (p.i < p.src.len) {
            const ch = p.src[p.i];
            if (ch == '"') {
                p.i += 1;
                return out.items;
            }
            if (ch < 0x20) {
                p.fail("control character in string (use \\n)");
                return error.Syntax;
            }
            if (ch != '\\') {
                try out.append(p.arena, ch);
                p.i += 1;
                continue;
            }
            p.i += 1;
            if (p.i >= p.src.len) break;
            const esc = p.src[p.i];
            p.i += 1;
            switch (esc) {
                '"' => try out.append(p.arena, '"'),
                '\\' => try out.append(p.arena, '\\'),
                '/' => try out.append(p.arena, '/'),
                'b' => try out.append(p.arena, 8),
                'f' => try out.append(p.arena, 12),
                'n' => try out.append(p.arena, '\n'),
                'r' => try out.append(p.arena, '\r'),
                't' => try out.append(p.arena, '\t'),
                'u' => {
                    var cp: u21 = try p.hex4();
                    if (cp >= 0xD800 and cp < 0xDC00) {
                        if (p.i + 6 <= p.src.len and p.src[p.i] == '\\' and p.src[p.i + 1] == 'u') {
                            p.i += 2;
                            const lo = try p.hex4();
                            if (lo < 0xDC00 or lo > 0xDFFF) {
                                p.fail("invalid surrogate pair");
                                return error.Syntax;
                            }
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                        } else {
                            p.fail("lone surrogate in \\u escape");
                            return error.Syntax;
                        }
                    }
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &buf) catch {
                        p.fail("invalid \\u escape");
                        return error.Syntax;
                    };
                    try out.appendSlice(p.arena, buf[0..n]);
                },
                else => {
                    p.i -= 2;
                    p.fail("invalid escape sequence");
                    return error.Syntax;
                },
            }
        }
        p.fail("unterminated string");
        return error.Syntax;
    }

    fn hex4(p: *Parser) ParseError!u21 {
        if (p.i + 4 > p.src.len) {
            p.fail("invalid \\u escape");
            return error.Syntax;
        }
        const v = std.fmt.parseInt(u16, p.src[p.i .. p.i + 4], 16) catch {
            p.fail("invalid \\u escape");
            return error.Syntax;
        };
        p.i += 4;
        return v;
    }

    fn array(p: *Parser, depth: u32) ParseError![]const Node {
        p.i += 1;
        var items: std.ArrayList(Node) = .empty;
        p.skipWs();
        if (p.i < p.src.len and p.src[p.i] == ']') {
            p.i += 1;
            return items.items;
        }
        while (true) {
            p.skipWs();
            try items.append(p.arena, try p.value(depth + 1));
            p.skipWs();
            if (p.i >= p.src.len) {
                p.fail("unterminated array, expected ']'");
                return error.Syntax;
            }
            switch (p.src[p.i]) {
                ',' => {
                    p.i += 1;
                    p.skipWs();
                    if (p.i < p.src.len and p.src[p.i] == ']') {
                        p.fail("trailing comma is not allowed in JSON");
                        return error.Syntax;
                    }
                },
                ']' => {
                    p.i += 1;
                    return items.items;
                },
                else => {
                    p.fail("expected ',' or ']'");
                    return error.Syntax;
                },
            }
        }
    }

    fn object(p: *Parser, depth: u32) ParseError![]const Node.Field {
        p.i += 1;
        var fields: std.ArrayList(Node.Field) = .empty;
        p.skipWs();
        if (p.i < p.src.len and p.src[p.i] == '}') {
            p.i += 1;
            return fields.items;
        }
        while (true) {
            p.skipWs();
            if (p.i >= p.src.len or p.src[p.i] != '"') {
                p.fail("expected a key in double quotes");
                return error.Syntax;
            }
            const key_pos: u32 = @intCast(p.i);
            const key = try p.string();
            for (fields.items) |f| {
                if (std.mem.eql(u8, f.key, key)) {
                    p.i = key_pos;
                    p.fail("duplicate key");
                    return error.Syntax;
                }
            }
            p.skipWs();
            if (p.i >= p.src.len or p.src[p.i] != ':') {
                p.fail("expected ':' after the key");
                return error.Syntax;
            }
            p.i += 1;
            p.skipWs();
            const v = try p.value(depth + 1);
            try fields.append(p.arena, .{ .key = key, .key_pos = key_pos, .value = v });
            p.skipWs();
            if (p.i >= p.src.len) {
                p.fail("unterminated object, expected '}'");
                return error.Syntax;
            }
            switch (p.src[p.i]) {
                ',' => {
                    p.i += 1;
                    p.skipWs();
                    if (p.i < p.src.len and p.src[p.i] == '}') {
                        p.fail("trailing comma is not allowed in JSON");
                        return error.Syntax;
                    }
                },
                '}' => {
                    p.i += 1;
                    return fields.items;
                },
                else => {
                    p.fail("expected ',' or '}'");
                    return error.Syntax;
                },
            }
        }
    }
};

/// The JSON Pointer of the value (or key) at byte `pos`, e.g. "/layers/3/box/x".
pub fn pointerTo(arena: Allocator, root: *const Node, pos: u32) Allocator.Error![]const u8 {
    var segs: std.ArrayList([]const u8) = .empty;
    if (!try findPath(arena, root, pos, &segs)) return "";
    var out: std.ArrayList(u8) = .empty;
    for (segs.items) |seg| {
        try out.append(arena, '/');
        for (seg) |ch| switch (ch) {
            '~' => try out.appendSlice(arena, "~0"),
            '/' => try out.appendSlice(arena, "~1"),
            else => try out.append(arena, ch),
        };
    }
    return out.items;
}

fn findPath(arena: Allocator, node: *const Node, pos: u32, segs: *std.ArrayList([]const u8)) Allocator.Error!bool {
    if (node.pos == pos) return true;
    switch (node.data) {
        .array => |items| for (items, 0..) |*item, i| {
            try segs.append(arena, try std.fmt.allocPrint(arena, "{d}", .{i}));
            if (try findPath(arena, item, pos, segs)) return true;
            _ = segs.pop();
        },
        .object => |fields| for (fields) |*f| {
            try segs.append(arena, f.key);
            if (f.key_pos == pos or try findPath(arena, &f.value, pos, segs)) return true;
            _ = segs.pop();
        },
        else => {},
    }
    return false;
}

/// 1-based line and column (in bytes) of a byte offset.
pub fn lineCol(src: []const u8, pos: u32) struct { line: u32, col: u32 } {
    var line: u32 = 1;
    var line_start: usize = 0;
    const end = @min(pos, src.len);
    for (src[0..end], 0..) |ch, i| {
        if (ch == '\n') {
            line += 1;
            line_start = i + 1;
        }
    }
    return .{ .line = line, .col = @intCast(end - line_start + 1) };
}

/// Writes `s` as a JSON string literal.
pub fn writeString(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    var start: usize = 0;
    for (s, 0..) |ch, i| {
        const esc: ?[]const u8 = switch (ch) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            else => null,
        };
        if (esc != null or ch < 0x20) {
            try w.writeAll(s[start..i]);
            if (esc) |e| try w.writeAll(e) else try w.print("\\u{x:0>4}", .{ch});
            start = i + 1;
        }
    }
    try w.writeAll(s[start..]);
    try w.writeByte('"');
}

test "parse keeps positions and order" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const src = "{\n  \"b\": [1, 2.5, \"x\\n\"],\n  \"a\": {\"t\": true}\n}";
    const r = try parse(arena_state.allocator(), src);
    const root = r.ok;
    try std.testing.expectEqualStrings("b", root.data.object[0].key);
    const a = root.get("a").?;
    try std.testing.expectEqual(true, a.get("t").?.data.bool);
    const lc = lineCol(src, a.pos);
    try std.testing.expectEqual(@as(u32, 3), lc.line);
    try std.testing.expectEqualStrings("x\n", root.get("b").?.data.array[2].data.string);
}

test "parse reports trailing comma" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const r = try parse(arena_state.allocator(), "{\"a\": 1,}");
    try std.testing.expect(r == .err);
}
