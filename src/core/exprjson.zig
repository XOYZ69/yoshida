//! JSON views of expressions for editors: tokens, the syntax tree, problems
//! and canonical text. Used by the small `expr.wasm` (parse and format on
//! every keystroke) and by the main module.
//!
//! Every span in the output is in UTF-16 code units, the way JavaScript
//! strings count, so the editor can use them directly.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const expr = @import("expr.zig");
const exprprint = @import("exprprint.zig");
pub const json = @import("json.zig");

/// Problems kept per expression.
pub const max_problems = 8;

/// Byte offset to UTF-16 offset, for every byte position of a string.
pub const Utf16 = struct {
    map: []const u32,

    pub fn init(arena: Allocator, src: []const u8) Allocator.Error!Utf16 {
        const map = try arena.alloc(u32, src.len + 1);
        var u: u32 = 0;
        var i: usize = 0;
        while (i < src.len) {
            const n = std.unicode.utf8ByteSequenceLength(src[i]) catch 1;
            const len = @min(n, src.len - i);
            const cp = std.unicode.utf8Decode(src[i .. i + len]) catch 0xFFFD;
            for (0..len) |k| map[i + k] = u;
            u += if (cp >= 0x10000) 2 else 1;
            i += len;
        }
        map[src.len] = u;
        return .{ .map = map };
    }

    pub fn at(self: Utf16, byte: u32) u32 {
        return self.map[@min(byte, self.map.len - 1)];
    }
};

/// Writes `{"tokens":[...],"problems":[...],"truncated":b,"root":...}` for
/// an expression, or `"holes":[...]` instead of `"root"` for a template.
pub fn writeParse(arena: Allocator, w: *Writer, src: []const u8, template: bool) (Allocator.Error || Writer.Error)!void {
    const u = try Utf16.init(arena, src);
    if (!template) {
        const parsed = try expr.parseTolerant(arena, src, 0, max_problems);
        try w.writeAll("{\"tokens\":");
        try writeTokens(w, try expr.tokenize(arena, src, 0), u);
        try w.writeAll(",\"problems\":");
        try writeProblems(w, parsed.problems, u);
        try w.print(",\"truncated\":{},\"root\":", .{parsed.truncated});
        var ids: u32 = 0;
        try writeNode(w, parsed.root, src, u, &ids);
        try w.writeAll("}");
        return;
    }
    const t = try expr.parseTemplateTolerant(arena, src, max_problems);
    try w.writeAll("{\"tokens\":[");
    var first = true;
    for (t.pieces) |piece| {
        switch (piece.kind) {
            .lit => {
                try sep(w, &first);
                try writeTok(w, "text", piece.start, piece.end, u);
            },
            .escape => {
                try sep(w, &first);
                try writeTok(w, "escape", piece.start, piece.end, u);
            },
            .hole => {
                const closed = piece.end > piece.start + 1 and src[piece.end - 1] == '}';
                try sep(w, &first);
                try writeTok(w, "brace", piece.start, piece.start + 1, u);
                const inner_end = if (closed) piece.end - 1 else piece.end;
                const toks = try expr.tokenize(arena, src[piece.start + 1 .. inner_end], piece.start + 1);
                for (toks) |tk| {
                    try sep(w, &first);
                    try writeTok(w, @tagName(tk.kind), tk.start, tk.end, u);
                }
                if (closed) {
                    try sep(w, &first);
                    try writeTok(w, "brace", piece.end - 1, piece.end, u);
                }
            },
        }
    }
    try w.writeAll("],\"problems\":");
    try writeProblems(w, t.problems, u);
    try w.print(",\"truncated\":{},\"holes\":[", .{t.truncated});
    first = true;
    var ids: u32 = 0;
    for (t.pieces) |piece| {
        if (piece.kind != .hole) continue;
        try sep(w, &first);
        try w.print("{{\"span\":[{d},{d}],\"root\":", .{ u.at(piece.start), u.at(piece.end) });
        if (piece.root) |r| try writeNode(w, r, src, u, &ids) else try w.writeAll("null");
        try w.writeAll("}");
    }
    try w.writeAll("]}");
}

/// Writes `{"text":"...","problems":[]}` with the canonical text of an
/// expression, or `{"text":null,"problems":[...]}` when it does not parse.
pub fn writeFormat(arena: Allocator, w: *Writer, src: []const u8, width: usize) (Allocator.Error || Writer.Error)!void {
    const u = try Utf16.init(arena, src);
    const parsed = try expr.parseTolerant(arena, src, 0, max_problems);
    if (parsed.problems.len > 0) {
        try w.writeAll("{\"text\":null,\"problems\":");
        try writeProblems(w, parsed.problems, u);
        try w.writeAll("}");
        return;
    }
    const text = try exprprint.print(arena, parsed.root, src, .{ .width = width });
    try w.writeAll("{\"text\":");
    try json.writeString(w, text);
    try w.writeAll(",\"problems\":[]}");
}

/// Writes what the language offers, for completion and documentation:
/// `{"functions":[...],"builtins":[...],"layer_fields":{kind:[...]},"reserved":[...]}`.
pub fn writeCatalog(w: *Writer) Writer.Error!void {
    try w.writeAll("{\"functions\":[");
    for (std.enums.values(expr.Func), 0..) |f, i| {
        if (i > 0) try w.writeAll(",");
        const sig = expr.funcSig(f);
        try w.print("{{\"name\":\"{s}\",\"min\":{d},\"max\":{d},\"args\":[", .{ @tagName(f), sig.min, sig.max });
        for (sig.args, 0..) |a, j| {
            if (j > 0) try w.writeAll(",");
            try typeName(w, a);
        }
        try w.writeAll("],\"ret\":");
        try typeName(w, sig.ret);
        try w.writeAll("}");
    }
    try w.writeAll("],\"builtins\":[");
    for (std.enums.values(expr.Builtin), 0..) |b, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"name\":\"{s}\",\"type\":\"{s}\"}}", .{ builtinName(b), b.ty().name() });
    }
    try w.writeAll("],\"layer_fields\":{");
    const paths = [_][]const []const u8{
        &.{ "bounds", "left" }, &.{ "bounds", "top" }, &.{ "bounds", "right" }, &.{ "bounds", "bottom" },
        &.{ "bounds", "w" },    &.{ "bounds", "h" },   &.{ "bounds", "cx" },    &.{ "bounds", "cy" },
        &.{ "box", "x" },       &.{ "box", "y" },      &.{ "box", "w" },        &.{ "box", "h" },
        &.{ "at", "x" },        &.{ "at", "y" },       &.{ "stroke", "color" }, &.{ "stroke", "width" },
        &.{"opacity"},          &.{"rotate"},          &.{"visible"},           &.{"fill"},
        &.{"radius"},           &.{"color"},           &.{"text"},              &.{"size"},
        &.{"line_spacing"},     &.{"wrap"},            &.{"max_lines"},         &.{"src"},
    };
    for (std.enums.values(expr.LayerKind), 0..) |kind, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\":[", .{@tagName(kind)});
        var first = true;
        for (paths) |path| {
            const t = expr.refType(kind, path) orelse continue;
            try sep(w, &first);
            try w.writeAll("{\"path\":\"");
            for (path, 0..) |part, j| {
                if (j > 0) try w.writeAll(".");
                try w.writeAll(part);
            }
            try w.print("\",\"type\":\"{s}\"}}", .{t.name()});
        }
        try w.writeAll("]");
    }
    try w.writeAll("},\"reserved\":[");
    for (expr.reserved_names, 0..) |r, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\"", .{r});
    }
    try w.writeAll("]}");
}

pub fn typeName(w: *Writer, t: ?@import("value.zig").Type) Writer.Error!void {
    if (t) |x| try w.print("\"{s}\"", .{x.name()}) else try w.writeAll("null");
}

pub fn builtinName(b: expr.Builtin) []const u8 {
    return switch (b) {
        .canvas_w => "canvas.w",
        .canvas_h => "canvas.h",
        .card_id => "card.id",
        .render_index => "render.index",
        .render_date => "render.date",
        .render_time => "render.time",
        .render_now => "render.now",
    };
}

fn sep(w: *Writer, first: *bool) Writer.Error!void {
    if (!first.*) try w.writeAll(",");
    first.* = false;
}

fn writeTok(w: *Writer, kind: []const u8, start: u32, end: u32, u: Utf16) Writer.Error!void {
    try w.print("[{d},{d},\"{s}\"]", .{ u.at(start), u.at(end), kind });
}

pub fn writeTokens(w: *Writer, toks: []const expr.Token, u: Utf16) Writer.Error!void {
    try w.writeAll("[");
    for (toks, 0..) |t, i| {
        if (i > 0) try w.writeAll(",");
        try writeTok(w, @tagName(t.kind), t.start, t.end, u);
    }
    try w.writeAll("]");
}

pub fn writeProblems(w: *Writer, problems: []const expr.Problem, u: Utf16) Writer.Error!void {
    try w.writeAll("[");
    for (problems, 0..) |p, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"code\":{d},\"span\":[{d},{d}],\"message\":", .{ p.code, u.at(p.start), u.at(p.end) });
        try json.writeString(w, p.message);
        try w.writeAll(",\"hint\":");
        if (p.hint) |h| try json.writeString(w, h) else try w.writeAll("null");
        try w.writeAll("}");
    }
    try w.writeAll("]");
}

/// Writes one node: `{"id":n,"k":"<kind>","span":[s,e], ...fields}`. Ids
/// count nodes in pre-order, so they are stable for the same text.
pub fn writeNode(w: *Writer, n: *const expr.Node, src: []const u8, u: Utf16, ids: *u32) Writer.Error!void {
    const id = ids.*;
    ids.* += 1;
    try w.print("{{\"id\":{d},\"k\":\"{s}\",\"span\":[{d},{d}]", .{ id, @tagName(n.data), u.at(n.start), u.at(n.end) });
    switch (n.data) {
        .number => |x| try w.print(",\"v\":{d}", .{x}),
        .unit => |x| try w.print(",\"v\":{d},\"unit\":\"{s}\"", .{ x.value, switch (x.unit) {
            .percent => "%",
            .vw => "vw",
            .vh => "vh",
        } }),
        .string => |s| {
            try w.writeAll(",\"v\":");
            try json.writeString(w, s);
        },
        .boolean => |b| try w.print(",\"v\":{}", .{b}),
        .color => {
            try w.writeAll(",\"v\":");
            try json.writeString(w, src[@min(n.start, src.len)..@min(n.end, src.len)]);
        },
        .name => |nm| {
            try w.writeAll(",\"name\":");
            try json.writeString(w, nm.text);
        },
        .builtin => |b| try w.print(",\"name\":\"{s}\"", .{builtinName(b)}),
        .layer_ref => |r| {
            try w.writeAll(",\"id_\":");
            try json.writeString(w, r.id);
            try w.writeAll(",\"path\":[");
            for (r.path, 0..) |part, i| {
                if (i > 0) try w.writeAll(",");
                try json.writeString(w, part);
            }
            try w.writeAll("]");
            if (r.index) |ix| try child(w, "index", ix, src, u, ids);
        },
        .field => |f| {
            try child(w, "obj", f.obj, src, u, ids);
            try w.writeAll(",\"name\":");
            try json.writeString(w, f.name);
        },
        .index => |ix| {
            try child(w, "obj", ix.obj, src, u, ids);
            try child(w, "idx", ix.idx, src, u, ids);
        },
        .call => |c| {
            try w.print(",\"fn\":\"{s}\"", .{@tagName(c.func)});
            try children(w, "args", c.args, src, u, ids);
        },
        .ucall => |c| {
            try w.writeAll(",\"fn\":");
            try json.writeString(w, c.name);
            try children(w, "args", c.args, src, u, ids);
        },
        .neg, .not, .paren => |x| try child(w, "x", x, src, u, ids),
        .binary => |b| {
            try w.print(",\"op\":\"{s}\"", .{expr.opText(b.op)});
            try child(w, "l", b.l, src, u, ids);
            try child(w, "r", b.r, src, u, ids);
        },
        .cond => |c| {
            try child(w, "c", c.c, src, u, ids);
            try child(w, "a", c.a, src, u, ids);
            try child(w, "b", c.b, src, u, ids);
        },
        .in_list => |il| {
            try child(w, "value", il.v, src, u, ids);
            try children(w, "items", il.items, src, u, ids);
        },
        .err => |x| if (x) |c| try child(w, "x", c, src, u, ids),
    }
    try w.writeAll("}");
}

fn child(w: *Writer, key: []const u8, n: *const expr.Node, src: []const u8, u: Utf16, ids: *u32) Writer.Error!void {
    try w.print(",\"{s}\":", .{key});
    try writeNode(w, n, src, u, ids);
}

fn children(w: *Writer, key: []const u8, ns: []const *expr.Node, src: []const u8, u: Utf16, ids: *u32) Writer.Error!void {
    try w.print(",\"{s}\":[", .{key});
    for (ns, 0..) |n, i| {
        if (i > 0) try w.writeAll(",");
        try writeNode(w, n, src, u, ids);
    }
    try w.writeAll("]");
}

const testing = std.testing;

fn parseJson(arena: Allocator, src: []const u8, template: bool) ![]const u8 {
    var aw: Writer.Allocating = .init(arena);
    try writeParse(arena, &aw.writer, src, template);
    return aw.written();
}

test "parse json" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try testing.expectEqualStrings(
        \\{"tokens":[[0,1,"name"],[2,3,"op"],[4,6,"number"],[6,7,"unit"]],"problems":[],"truncated":false,"root":{"id":0,"k":"binary","span":[0,7],"op":"+","l":{"id":1,"k":"name","span":[0,1],"name":"a"},"r":{"id":2,"k":"unit","span":[4,7],"v":10,"unit":"%"}}}
    , try parseJson(a, "a + 10%", false));
    // Spans count UTF-16 units: the glyph is 3 bytes but 1 unit.
    const out = try parseJson(a, "'\u{2665}' + x", false);
    try testing.expect(std.mem.indexOf(u8, out, "[0,3,\"string\"]") != null);
    try testing.expect(std.mem.indexOf(u8, out, "[6,7,\"name\"]") != null);
    // A template: text, braces and the hole's tokens.
    try testing.expectEqualStrings(
        \\{"tokens":[[0,3,"text"],[3,4,"brace"],[4,5,"name"],[5,6,"brace"]],"problems":[],"truncated":false,"holes":[{"span":[3,6],"root":{"id":0,"k":"name","span":[4,5],"name":"n"}}]}
    , try parseJson(a, "Lv {n}", true));
    // Problems carry spans; the tree is still there.
    const bad = try parseJson(a, "max(1, ", false);
    try testing.expect(std.mem.indexOf(u8, bad, "\"k\":\"call\"") != null);
    try testing.expect(std.mem.indexOf(u8, bad, "\"code\":3001") != null);

    var aw: Writer.Allocating = .init(a);
    try writeCatalog(&aw.writer);
    const cat = aw.written();
    try testing.expect(std.mem.indexOf(u8, cat, "{\"name\":\"with_alpha\",\"min\":2,\"max\":2,\"args\":[\"color\",\"number\"],\"ret\":\"color\"}") != null);
    try testing.expect(std.mem.indexOf(u8, cat, "\"text\":[{\"path\":\"bounds.left\"") != null);
}
