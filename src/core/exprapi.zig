//! Editor queries about one expression field of a design, named by its JSON
//! Pointer: the names it can use (`writeScope`) and the live value of an
//! edited expression for one card (`writeEval`).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const expr = @import("expr.zig");
const exprjson = @import("exprjson.zig");
const design_mod = @import("design.zig");
const project = @import("project.zig");
const render = @import("render.zig");
const api = @import("api.zig");
const Design = design_mod.Design;
const FieldInfo = design_mod.FieldInfo;
const Type = value.Type;
const Value = value.Value;

/// The expression field at a JSON Pointer of the design, e.g. "/layers/3/fill".
pub fn fieldAt(d: *const Design, pointer: []const u8) ?*const FieldInfo {
    const n = json.resolve(&d.root, pointer) orelse return null;
    return d.fieldAt(n.pos);
}

/// Writes what the field can use:
/// `{"want","template","axis","units","builtins","layers","params":[...],
/// "consts":[...],"functions":[...],"locals":[...],"layer_refs":[...]}`.
/// Layer refs carry "ref": "ok" (one position), "index" (needs `[i]`) or
/// "none" (cannot be referenced from here).
pub fn writeScope(w: *Writer, d: *const Design, f: *const FieldInfo) Writer.Error!void {
    const s = &f.scope;
    try w.writeAll("{\"want\":");
    try exprjson.typeName(w, f.want);
    try w.print(",\"template\":{},\"axis\":\"{s}\",\"units\":{},\"builtins\":{},\"layers\":{}", .{
        f.template, @tagName(s.axis), s.allow_units, s.allow_builtins, s.layers != null,
    });
    try w.writeAll(",\"params\":[");
    for (s.params, 0..) |p, i| {
        if (i > 0) try w.writeByte(',');
        try writeSymbol(w, p.name, p.ty, findParam(d, p.name));
    }
    try w.writeAll("],\"consts\":[");
    for (s.consts, 0..) |k, i| {
        if (i > 0) try w.writeByte(',');
        try writeSymbol(w, k.name, k.ty, null);
    }
    try w.writeAll("],\"functions\":[");
    for (s.functions, 0..) |fs, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try json.writeString(w, fs.name);
        try w.writeAll(",\"args\":[");
        for (fs.args, 0..) |a, j| {
            if (j > 0) try w.writeByte(',');
            try writeSymbol(w, a.name, a.ty, null);
        }
        try w.writeAll("],\"ret\":");
        try exprjson.typeName(w, fs.ret);
        try w.writeByte('}');
    }
    try w.writeAll("],\"locals\":[");
    for (s.locals, 0..) |l, i| {
        if (i > 0) try w.writeByte(',');
        try writeSymbol(w, l.name, l.ty, null);
    }
    try w.writeAll("],\"layer_refs\":[");
    for (s.layers orelse &.{}, 0..) |l, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"id\":");
        try json.writeString(w, l.id);
        const ref = switch (l.unshared(s.rgroups)) {
            0 => "ok",
            1 => "index",
            else => "none",
        };
        try w.print(",\"kind\":\"{s}\",\"ref\":\"{s}\"}}", .{ @tagName(l.kind), ref });
    }
    try w.writeAll("]}");
}

fn findParam(d: *const Design, name: []const u8) ?*const design_mod.Param {
    for (d.params) |*p| if (std.mem.eql(u8, p.name, name)) return p;
    return null;
}

/// `{"name","type"}`, plus `"kind"` and `"options"` for params and
/// `"fields"` for lists and list items.
fn writeSymbol(w: *Writer, name: []const u8, ty: Type, param: ?*const design_mod.Param) Writer.Error!void {
    try w.writeAll("{\"name\":");
    try json.writeString(w, name);
    try w.writeAll(",\"type\":");
    try exprjson.typeName(w, ty);
    if (param) |p| {
        try w.print(",\"kind\":\"{s}\"", .{@tagName(p.kind)});
        if (p.options.len > 0) try writeWords(w, "options", p.options);
    }
    const def = switch (ty) {
        .list, .item => |x| x,
        else => null,
    };
    if (def) |item| {
        try w.writeAll(",\"fields\":[");
        for (item.names, item.types, 0..) |n, t, j| {
            if (j > 0) try w.writeByte(',');
            try w.writeAll("{\"name\":");
            try json.writeString(w, n);
            try w.print(",\"type\":\"{s}\"", .{t.toType().name()});
            const opts = item.optionsOf(j);
            if (opts.len > 0) try writeWords(w, "options", opts);
            try w.writeByte('}');
        }
        try w.writeByte(']');
    }
    try w.writeByte('}');
}

fn writeWords(w: *Writer, key: []const u8, words: []const []const u8) Writer.Error!void {
    try w.print(",\"{s}\":[", .{key});
    for (words, 0..) |o, i| {
        if (i > 0) try w.writeByte(',');
        try json.writeString(w, o);
    }
    try w.writeByte(']');
}

pub const EvalOptions = struct {
    card: usize = 0,
    date: []const u8 = "1970-01-01",
    /// The render clock, as `render.Options.now` and `utc_offset`.
    now: ?[]const u8 = null,
    utc_offset: ?f64 = null,
};

/// Evaluates `src` in place of field `f` while rendering one card of `set`
/// (without drawing), so it sees the card's params, loop names and layer
/// positions. Writes `{"hits","value","type","problems":[...],"trace":[...]}`:
/// the trace holds the value of every syntax tree node in the pre-order of
/// `exprjson.writeParse`, null where a node was not evaluated. Spans are
/// UTF-16 offsets into `src`.
pub fn writeEval(
    gpa: Allocator,
    arena: Allocator,
    w: *Writer,
    assets: *render.Assets,
    set: *const project.Set,
    f: *const FieldInfo,
    src: []const u8,
    opts: EvalOptions,
) (Allocator.Error || Writer.Error)!void {
    const d = set.design;
    const u = try exprjson.Utf16.init(arena, src);
    var probe: render.Probe = .{ .file = d.file, .pos = f.pos, .trace = undefined };

    if (try compile(arena, f, src, &probe)) |problem| {
        return writeResult(w, null, &.{problem}, &.{}, 0, u);
    }
    if (!d.ok or opts.card >= set.cards.len) {
        return writeResult(w, null, &.{}, probe.trace.values, 0, u);
    }
    var diags = diag.List.init(arena);
    if (try render.renderCard(gpa, assets, set, opts.card, .{ .date = opts.date, .now = opts.now, .utc_offset = opts.utc_offset, .preview = true, .dry = true, .probe = &probe }, &diags)) |bmp_const| {
        var bmp = bmp_const;
        bmp.deinit(gpa);
    }
    const problems: []const expr.Problem = if (probe.problem) |p| &.{p} else &.{};
    try writeResult(w, probe.value, problems, probe.trace.values, probe.hits, u);
}

/// Parses and checks `src` as field `f` would, and sets up the probe; the
/// problem when it is not valid there.
fn compile(arena: Allocator, f: *const FieldInfo, src: []const u8, probe: *render.Probe) Allocator.Error!?expr.Problem {
    var scope = f.scope;
    scope.arena = arena;
    var problem: ?expr.Problem = null;
    if (f.template) {
        const t = expr.parseTemplate(arena, src, &problem) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => return problem.?,
        };
        expr.checkTemplate(t, &scope, &problem) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => return problem.?,
        };
        var roots: std.ArrayList(*const expr.Node) = .empty;
        for (t.parts) |part| if (part == .expr) try roots.append(arena, part.expr);
        probe.tmpl = t;
        probe.trace = try expr.Trace.init(arena, roots.items);
        return null;
    }
    const node = expr.parse(arena, src, 0, &problem) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return problem.?,
    };
    var c: expr.Checker = .{ .scope = &scope, .problem = &problem };
    const t = c.check(node) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return problem.?,
    };
    if (f.want) |want| {
        // `repeat.count` also takes a list (its length).
        const counts = want == .number and t == .list;
        if (!counts and !t.eql(want)) return .{
            .code = 3003,
            .start = node.start,
            .end = node.end,
            .message = try std.fmt.allocPrint(arena, "expected a {s}, the expression gives a {s}", .{ want.name(), t.name() }),
        };
    }
    probe.root = node;
    probe.trace = try expr.Trace.init(arena, &.{node});
    return null;
}

fn writeResult(w: *Writer, v: ?Value, problems: []const expr.Problem, trace: []const ?Value, hits: u32, u: exprjson.Utf16) Writer.Error!void {
    try w.print("{{\"hits\":{d},\"value\":", .{hits});
    if (v) |x| try api.writeValue(w, x) else try w.writeAll("null");
    try w.writeAll(",\"type\":");
    if (v) |x| try w.print("\"{s}\"", .{typeOf(x)}) else try w.writeAll("null");
    try w.writeAll(",\"problems\":");
    try exprjson.writeProblems(w, problems, u);
    try w.writeAll(",\"trace\":[");
    for (trace, 0..) |t, i| {
        if (i > 0) try w.writeByte(',');
        if (t) |x| try api.writeValue(w, x) else try w.writeAll("null");
    }
    try w.writeAll("]}");
}

fn typeOf(v: Value) []const u8 {
    return switch (v) {
        .item => "list item",
        else => @tagName(v),
    };
}

// ------------------------------------------------------------------ tests

const test_design =
    \\{"format": 1, "name": "t", "canvas": {"width": 100, "height": 50},
    \\ "params": {"kind": {"type": "enum", "options": ["a", "b"], "default": "a"},
    \\            "n": {"type": "number", "default": 2}},
    \\ "consts": {"gap": "n * 10"},
    \\ "functions": {"twice": {"args": {"x": "number"}, "expr": "x * 2"}},
    \\ "layers": [
    \\   {"id": "bg", "type": "rect", "box": {"x": 0, "y": 0, "w": "twice(gap)", "h": 10},
    \\    "fill": "match(kind, 'a', #ff0000, #00ff00)"},
    \\   {"id": "dots", "type": "group", "repeat": {"count": 3, "index": "i"}, "layers": [
    \\     {"id": "dot", "type": "ellipse", "box": {"x": "i * 10", "y": "@bg.bounds.h", "w": 5, "h": 5}, "fill": "#000000"}]},
    \\   {"id": "label", "type": "text", "text": "n is {n}", "at": {"x": 0, "y": 0}}
    \\ ]}
;

const TestProject = struct {
    arena_state: std.heap.ArenaAllocator,
    fs: project.MemFs,
    proj: project.Project,

    fn init(t: *TestProject) !void {
        t.arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
        errdefer t.arena_state.deinit();
        t.fs = project.MemFs.init(std.testing.allocator);
        errdefer t.fs.deinit();
        const arena = t.arena_state.allocator();
        try t.fs.put("d.design.json", test_design);
        try t.fs.put("c.cards.json", "{\"format\": 1, \"design\": \"d.design.json\", \"cards\": [{\"id\": \"one\", \"kind\": \"b\", \"n\": 3}]}");
        var diags = diag.List.init(arena);
        t.proj = try project.load(arena, t.fs.vfs(), &diags);
        try std.testing.expectEqual(@as(usize, 0), diags.errorCount());
    }

    fn deinit(t: *TestProject) void {
        t.fs.deinit();
        t.arena_state.deinit();
    }
};

fn evalAt(t: *TestProject, pointer: []const u8, src: []const u8) ![]const u8 {
    const arena = t.arena_state.allocator();
    var assets = render.Assets.init(std.testing.allocator, t.fs.vfs());
    defer assets.deinit();
    const set = &t.proj.sets[0];
    const f = fieldAt(set.design, pointer) orelse return error.NoField;
    var aw: Writer.Allocating = .init(arena);
    try writeEval(std.testing.allocator, arena, &aw.writer, &assets, set, f, src, .{});
    return aw.written();
}

test "scope of a field" {
    var t: TestProject = undefined;
    try t.init();
    defer t.deinit();
    const d = t.proj.sets[0].design;
    const arena = t.arena_state.allocator();
    var aw: Writer.Allocating = .init(arena);

    try writeScope(&aw.writer, d, fieldAt(d, "/layers/1/layers/0/box/x").?);
    const s = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, s, "\"want\":\"number\",\"template\":false,\"axis\":\"x\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "{\"name\":\"kind\",\"type\":\"text\",\"kind\":\"enum\",\"options\":[\"a\",\"b\"]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"consts\":[{\"name\":\"gap\",\"type\":\"number\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"functions\":[{\"name\":\"twice\",\"args\":[{\"name\":\"x\",\"type\":\"number\"}],\"ret\":\"number\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "{\"name\":\"i\",\"type\":\"number\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "{\"id\":\"bg\",\"kind\":\"rect\",\"ref\":\"ok\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "{\"id\":\"dot\",\"kind\":\"ellipse\",\"ref\":\"ok\"}") != null);

    aw.clearRetainingCapacity();
    try writeScope(&aw.writer, d, fieldAt(d, "/layers/0/fill").?);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "{\"id\":\"dot\",\"kind\":\"ellipse\",\"ref\":\"index\"}") != null);

    aw.clearRetainingCapacity();
    try writeScope(&aw.writer, d, fieldAt(d, "/functions/twice/expr").?);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "\"want\":null,\"template\":false,\"axis\":\"none\",\"units\":true,\"builtins\":true,\"layers\":false") != null);

    try std.testing.expect(fieldAt(d, "/layers/0/id") == null);
    try std.testing.expect(fieldAt(d, "/nope") == null);
}

test "eval traces a match for the card" {
    var t: TestProject = undefined;
    try t.init();
    defer t.deinit();
    // Nodes: match(0) kind(1) 'a'(2) #ff0000(3) 'b'(4) #0000ff(5) #00ff00(6).
    try std.testing.expectEqualStrings(
        "{\"hits\":1,\"value\":\"#0000FFFF\",\"type\":\"color\",\"problems\":[],\"trace\":[\"#0000FFFF\",\"b\",\"a\",null,\"b\",\"#0000FFFF\",null]}",
        try evalAt(&t, "/layers/0/fill", "match(kind, 'a', #ff0000, 'b', #0000ff, #00ff00)"),
    );
}

test "eval sees loop names, layout and functions" {
    var t: TestProject = undefined;
    try t.init();
    defer t.deinit();
    // Three iterations, each measured and then drawn.
    try std.testing.expectEqualStrings(
        "{\"hits\":6,\"value\":10,\"type\":\"number\",\"problems\":[],\"trace\":[10,0,0,10,10]}",
        try evalAt(&t, "/layers/1/layers/0/box/x", "i * 10 + @bg.bounds.h"),
    );
    try std.testing.expectEqualStrings(
        "{\"hits\":1,\"value\":60,\"type\":\"number\",\"problems\":[],\"trace\":[60,30,2]}",
        try evalAt(&t, "/functions/twice/expr", "x * 2"),
    );
    try std.testing.expectEqualStrings(
        "{\"hits\":1,\"value\":\"n = 3!\",\"type\":\"text\",\"problems\":[],\"trace\":[3]}",
        try evalAt(&t, "/layers/2/text", "n = {n}!"),
    );
}

test "eval reports problems in UTF-16" {
    var t: TestProject = undefined;
    try t.init();
    defer t.deinit();
    const out = try evalAt(&t, "/layers/0/fill", "'ü' + nope");
    try std.testing.expect(std.mem.startsWith(u8, out, "{\"hits\":0,\"value\":null,\"type\":null,\"problems\":[{\"code\":3002,\"span\":[6,10]"));
    const typed = try evalAt(&t, "/layers/0/fill", "n + 1");
    try std.testing.expect(std.mem.indexOf(u8, typed, "expected a color, the expression gives a number") != null);
    const runtime = try evalAt(&t, "/layers/0/box/w", "1 / (n - 3)");
    try std.testing.expect(std.mem.indexOf(u8, runtime, "\"hits\":1,\"value\":null") != null);
}
