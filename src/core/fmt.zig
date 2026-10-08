//! Canonical JSON layout (FORMAT.md, "Canonical formatting"), the same rules
//! as the editor's formatter: 2 spaces, LF, trailing newline, key order as
//! written, and objects or arrays of scalars (or arrays of arrays of
//! scalars) on one line when they fit in 100 columns.

const std = @import("std");
const json = @import("json.zig");
const value = @import("value.zig");
const Allocator = std.mem.Allocator;
const Node = json.Node;

pub const max_width = 100;

/// Formats parsed JSON. The caller owns the returned text (arena).
pub fn format(arena: Allocator, root: *const Node) Allocator.Error![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    fmtNode(arena, &aw.writer, root, 0, 0) catch return error.OutOfMemory;
    aw.writer.writeByte('\n') catch return error.OutOfMemory;
    return aw.written();
}

/// Parses and formats `src`; null when it is not valid JSON.
pub fn formatSource(arena: Allocator, src: []const u8) Allocator.Error!?[]const u8 {
    return switch (try json.parse(arena, src)) {
        .ok => |n| try format(arena, &n),
        .err => null,
    };
}

fn isScalar(n: *const Node) bool {
    return switch (n.data) {
        .array, .object => false,
        else => true,
    };
}

fn writeScalar(w: *std.Io.Writer, n: *const Node) std.Io.Writer.Error!void {
    switch (n.data) {
        .null => try w.writeAll("null"),
        .bool => |b| try w.writeAll(if (b) "true" else "false"),
        .number => |x| try value.writeNumber(w, x),
        .string => |s| try json.writeString(w, s),
        else => unreachable,
    }
}

/// The one-line form, or null when the value may not be written on one line.
fn oneLine(arena: Allocator, n: *const Node) Allocator.Error!?[]const u8 {
    if (!inlineable(n, 0)) return null;
    var aw: std.Io.Writer.Allocating = .init(arena);
    writeInline(&aw.writer, n) catch return error.OutOfMemory;
    return aw.written();
}

/// Scalars; objects of scalars; arrays of scalars or of arrays of scalars.
fn inlineable(n: *const Node, depth: usize) bool {
    return switch (n.data) {
        .array => |items| for (items) |*x| {
            if (isScalar(x)) continue;
            if (depth == 0 and x.data == .array and inlineable(x, 1)) continue;
            break false;
        } else true,
        .object => |fields| for (fields) |*f| {
            if (!isScalar(&f.value)) break false;
        } else true,
        else => true,
    };
}

fn writeInline(w: *std.Io.Writer, n: *const Node) std.Io.Writer.Error!void {
    switch (n.data) {
        .array => |items| {
            try w.writeByte('[');
            for (items, 0..) |*x, i| {
                if (i > 0) try w.writeAll(", ");
                try writeInline(w, x);
            }
            try w.writeByte(']');
        },
        .object => |fields| {
            if (fields.len == 0) return w.writeAll("{}");
            try w.writeAll("{ ");
            for (fields, 0..) |*f, i| {
                if (i > 0) try w.writeAll(", ");
                try json.writeString(w, f.key);
                try w.writeAll(": ");
                try writeScalar(w, &f.value);
            }
            try w.writeAll(" }");
        },
        else => try writeScalar(w, n),
    }
}

/// Length as JavaScript counts it (UTF-16 code units), so both formatters
/// break lines at the same place.
fn jsLength(s: []const u8) usize {
    var n: usize = 0;
    for (s) |b| {
        if (b & 0xC0 == 0x80) continue; // continuation byte
        n += if (b >= 0xF0) 2 else 1;
    }
    return n;
}

fn fmtNode(arena: Allocator, w: *std.Io.Writer, n: *const Node, indent: usize, key_len: usize) !void {
    if (isScalar(n)) return writeScalar(w, n);
    if (try oneLine(arena, n)) |line| {
        if (indent * 2 + key_len + jsLength(line) <= max_width) return w.writeAll(line);
    }
    switch (n.data) {
        .array => |items| {
            if (items.len == 0) return w.writeAll("[]");
            try w.writeAll("[\n");
            for (items, 0..) |*x, i| {
                try w.splatByteAll(' ', (indent + 1) * 2);
                try fmtNode(arena, w, x, indent + 1, 0);
                try w.writeAll(if (i + 1 < items.len) ",\n" else "\n");
            }
            try w.splatByteAll(' ', indent * 2);
            try w.writeByte(']');
        },
        .object => |fields| {
            if (fields.len == 0) return w.writeAll("{}");
            try w.writeAll("{\n");
            for (fields, 0..) |*f, i| {
                try w.splatByteAll(' ', (indent + 1) * 2);
                var kw: std.Io.Writer.Allocating = .init(arena);
                try json.writeString(&kw.writer, f.key);
                try kw.writer.writeAll(": ");
                const key = kw.written();
                try w.writeAll(key);
                try fmtNode(arena, w, &f.value, indent + 1, jsLength(key));
                try w.writeAll(if (i + 1 < fields.len) ",\n" else "\n");
            }
            try w.splatByteAll(' ', indent * 2);
            try w.writeByte('}');
        },
        else => unreachable,
    }
}

test "canonical layout" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = (try formatSource(arena, "{\"a\":1,\"box\":{\"x\":\"50%\",\"y\":2},\"pts\":[[0,0],[1,2]],\"layers\":[{\"id\":\"x\",\"box\":{\"w\":1}}],\"e\":[],\"o\":{}}")).?;
    try std.testing.expectEqualStrings(
        \\{
        \\  "a": 1,
        \\  "box": { "x": "50%", "y": 2 },
        \\  "pts": [[0, 0], [1, 2]],
        \\  "layers": [
        \\    {
        \\      "id": "x",
        \\      "box": { "w": 1 }
        \\    }
        \\  ],
        \\  "e": [],
        \\  "o": {}
        \\}
        \\
    , out);
}
