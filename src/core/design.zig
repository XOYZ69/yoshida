//! Loads and checks a design file (FORMAT.md sections 3 to 5). Every
//! expression is parsed and type-checked here, before anything is drawn.

const std = @import("std");
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const expr = @import("expr.zig");
const Allocator = std.mem.Allocator;
const Node = json.Node;
const Value = value.Value;
const Type = value.Type;
const LayerKind = expr.LayerKind;

/// A compiled number, bool or color field.
pub const Prop = struct {
    node: *expr.Node,
    /// Byte offset of the JSON value, for diagnostics.
    pos: u32,
    axis: expr.Axis = .none,
};

/// A compiled text or path field.
pub const Tmpl = struct {
    t: expr.Template,
    pos: u32,
};

pub const ParamKind = enum { number, integer, text, bool, color, @"enum", image, list };

pub const Param = struct {
    name: []const u8,
    kind: ParamKind,
    ty: Type,
    default: ?Value = null,
    required: bool = false,
    min: ?f64 = null,
    max: ?f64 = null,
    max_length: ?usize = null,
    options: []const []const u8 = &.{},
    item: ?*const value.ItemDef = null,
    label: ?[]const u8 = null,
    note: ?[]const u8 = null,
    /// Editor section the param is shown in; no effect on rendering.
    group: ?[]const u8 = null,
    pos: u32,
};

pub const Anchor = enum {
    @"top-left",
    top,
    @"top-right",
    left,
    center,
    right,
    @"bottom-left",
    bottom,
    @"bottom-right",
    @"baseline-left",
    baseline,
    @"baseline-right",

    /// Horizontal fraction of the box the anchor sits at.
    pub fn fx(a: Anchor) f64 {
        return switch (a) {
            .@"top-left", .left, .@"bottom-left", .@"baseline-left" => 0,
            .top, .center, .bottom, .baseline => 0.5,
            .@"top-right", .right, .@"bottom-right", .@"baseline-right" => 1,
        };
    }

    /// Vertical fraction; baseline anchors are handled by text layout.
    pub fn fy(a: Anchor) f64 {
        return switch (a) {
            .@"top-left", .top, .@"top-right" => 0,
            .left, .center, .right => 0.5,
            .@"bottom-left", .bottom, .@"bottom-right" => 1,
            .@"baseline-left", .baseline, .@"baseline-right" => 0,
        };
    }

    pub fn isBaseline(a: Anchor) bool {
        return a == .@"baseline-left" or a == .baseline or a == .@"baseline-right";
    }
};

pub const Side = enum { top, bottom, left, right };
pub const Align = enum { left, center, right, justify };
pub const Fit = enum { fill, contain, cover };
pub const Smoothing = enum { nearest, bilinear };
pub const EffectKind = enum { crop, fade, sharpen, detail, edge_enhance, find_edges };

pub const Effect = struct {
    kind: EffectKind,
    side: Side = .bottom,
    length: ?Prop = null,
    strength: ?Prop = null,
    pos: u32,
};

pub const Repeat = struct {
    count: ?Prop = null,
    each: ?Prop = null,
    index_name: []const u8 = "i",
    item_name: ?[]const u8 = null,
};

pub const Box = struct {
    x: Prop,
    y: Prop,
    /// null means "auto" (image layers only).
    w: ?Prop,
    h: ?Prop,
};

pub const Point = struct { x: Prop, y: Prop };

pub const Arrow = enum { none, start, end, both };

pub const Stroke = struct {
    color: Prop,
    width: Prop,
    /// Dash pattern: on, off, on, off... in pixels.
    dash: []const Prop = &.{},
    /// Arrowheads on open polygons.
    arrow: Arrow = .none,
};

/// Part of an ellipse: degrees clockwise from the top.
pub const Arc = struct {
    start: Prop,
    end: Prop,
    /// true: a slice (closed through the centre); false: only the curve.
    pie: bool = true,
};

pub const ShapeKind = enum { star, polygon, triangle, diamond, arrow, cross, chevron };

/// A polygon drawn from a preset inside `box` instead of from `points`.
pub const Shape = struct {
    kind: ShapeKind,
    /// polygon: number of sides; star: number of points.
    count: ?Prop = null,
    /// star: inner radius as a fraction of the outer one; arrow: shaft
    /// thickness; chevron: thickness; cross: arm thickness.
    inner: ?Prop = null,
};

pub const Layer = struct {
    id: []const u8,
    kind: LayerKind,
    index: usize,
    pos: u32,
    /// Index (in `Design.layers`) of the group this layer belongs to.
    parent: ?usize = null,
    /// Groups: index just past the group's last descendant. Descendants
    /// follow the group directly, in document order.
    end: usize = 0,
    /// Groups: moves every layer inside by (x, y); coordinates inside the
    /// group are relative to this origin.
    translate: ?Point = null,
    /// Text: layers with the same name use the smallest auto-shrunk size
    /// of all of them (and of all their iterations).
    shrink_group: ?[]const u8 = null,
    visible: ?Prop = null,
    opacity: ?Prop = null,
    /// Degrees clockwise around the anchor point (polygons: their centre).
    rotate: ?Prop = null,
    anchor: Anchor = .@"top-left",
    repeat: ?Repeat = null,
    effects: []const Effect = &.{},
    // rect, ellipse, image
    box: ?Box = null,
    // rect, ellipse, polygon
    fill: ?Prop = null,
    stroke: ?Stroke = null,
    // rect
    radius: ?Prop = null,
    // ellipse
    arc: ?Arc = null,
    // polygon
    points: []const Point = &.{},
    closed: bool = true,
    shape: ?Shape = null,
    // text
    text: ?Tmpl = null,
    at: ?Point = null,
    font: []const u8 = "default",
    size: ?Prop = null,
    color: ?Prop = null,
    alignment: Align = .left,
    wrap: ?Prop = null,
    line_spacing: ?Prop = null,
    max_lines: ?Prop = null,
    /// Auto-shrink: the size is reduced (down to `min_size`) until the
    /// block fits these limits.
    max_width: ?Prop = null,
    max_height: ?Prop = null,
    min_size: ?Prop = null,
    // image
    src: ?Tmpl = null,
    fit: Fit = .fill,
    smoothing: Smoothing = .bilinear,
};

/// A named value shared by every layer (`consts`), evaluated once per card.
pub const Const = struct {
    name: []const u8,
    prop: Prop,
};

/// A named formula with arguments (`functions`).
pub const Function = struct {
    name: []const u8,
    args: []const expr.Symbol,
    body: *expr.Node,
    ret: Type,
    pos: u32,
};

pub const Font = struct {
    name: []const u8,
    path: []const u8,
    pos: u32,
};

pub const Design = struct {
    file: []const u8,
    source: []const u8,
    root: Node,
    name: []const u8 = "",
    canvas_w: ?Prop = null,
    canvas_h: ?Prop = null,
    background: ?Prop = null,
    /// Print resolution, written to PNG and PDF files.
    dpi: ?Prop = null,
    /// Bleed in pixels on every side; the trim line is this far inside.
    bleed: ?Prop = null,
    fonts: []const Font = &.{},
    params: []const Param = &.{},
    layers: []const Layer = &.{},
    symbols: []const expr.Symbol = &.{},
    consts: []const Const = &.{},
    const_symbols: []const expr.Symbol = &.{},
    functions: []const Function = &.{},
    fn_sigs: []const expr.FnSig = &.{},
    /// False when loading found errors; such a design is never rendered.
    ok: bool = false,

    pub fn findParam(d: *const Design, name: []const u8) ?usize {
        for (d.params, 0..) |p, i| if (std.mem.eql(u8, p.name, name)) return i;
        return null;
    }

    pub fn findLayer(d: *const Design, id: []const u8) ?usize {
        for (d.layers, 0..) |l, i| if (std.mem.eql(u8, l.id, id)) return i;
        return null;
    }

    pub fn findFont(d: *const Design, name: []const u8) ?*const Font {
        for (d.fonts) |*f| if (std.mem.eql(u8, f.name, name)) return f;
        return null;
    }

    pub fn pathAt(d: *const Design, arena: Allocator, pos: u32) []const u8 {
        return json.pointerTo(arena, &d.root, pos) catch "";
    }
};

// ------------------------------------------------------------------ loader

const Loader = struct {
    arena: Allocator,
    diags: *diag.List,
    src: diag.Source,
    root: *const Node,
    errors: usize = 0,
    /// Set while compiling `repeat.count`: a list there counts its items.
    list_counts: bool = false,

    fn report(l: *Loader, sev: diag.Severity, code: u16, pos: u32, msg: []const u8, hint: ?[]const u8) Allocator.Error!void {
        if (sev == .err) l.errors += 1;
        const path = try json.pointerTo(l.arena, l.root, pos);
        try l.diags.at(sev, code, l.src, pos, path, msg, hint);
    }

    fn err(l: *Loader, code: u16, pos: u32, comptime f: []const u8, args: anytype) Allocator.Error!void {
        try l.report(.err, code, pos, try std.fmt.allocPrint(l.arena, f, args), null);
    }

    fn errHint(l: *Loader, code: u16, pos: u32, msg: []const u8, hint: ?[]const u8) Allocator.Error!void {
        try l.report(.err, code, pos, msg, hint);
    }

    fn exprProblem(l: *Loader, pos: u32, p: expr.Problem) Allocator.Error!void {
        l.errors += 1;
        const path = try json.pointerTo(l.arena, l.root, pos);
        const lc = json.lineCol(l.src.text, pos);
        try l.diags.add(.{
            .severity = .err,
            .code = p.code,
            .file = l.src.file,
            .path = path,
            .line = lc.line,
            .col = lc.col,
            .span_start = p.start,
            .span_end = p.end,
            .message = p.message,
            .hint = p.hint,
        });
    }

    /// Reports keys of `obj` not in `allowed` [1101].
    fn checkFields(l: *Loader, obj: *const Node, allowed: []const []const u8, what: []const u8) Allocator.Error!void {
        for (obj.data.object) |f| {
            var known = false;
            for (allowed) |a| {
                if (std.mem.eql(u8, a, f.key)) known = true;
            }
            if (!known) {
                try l.errHint(1101, f.key_pos, try std.fmt.allocPrint(l.arena, "unknown field '{s}' in {s}", .{ f.key, what }), diag.suggest(l.arena, f.key, allowed));
            }
        }
    }

    fn expectObject(l: *Loader, n: *const Node, what: []const u8) Allocator.Error!bool {
        if (n.data == .object) return true;
        try l.err(1103, n.pos, "{s} must be an object, found {s}", .{ what, n.kindName() });
        return false;
    }

    fn literalString(l: *Loader, n: *const Node, what: []const u8) Allocator.Error!?[]const u8 {
        if (n.data == .string) return n.data.string;
        try l.err(1103, n.pos, "{s} must be a string, found {s}", .{ what, n.kindName() });
        return null;
    }

    fn enumField(l: *Loader, comptime E: type, n: *const Node, what: []const u8) Allocator.Error!?E {
        const s = (try l.literalString(n, what)) orelse return null;
        if (std.meta.stringToEnum(E, s)) |e| return e;
        const names = comptime blk: {
            const fields = @typeInfo(E).@"enum".fields;
            var out: [fields.len][]const u8 = undefined;
            for (fields, 0..) |f, i| out[i] = f.name;
            break :blk out;
        };
        const all = try std.mem.join(l.arena, ", ", &names);
        try l.errHint(1103, n.pos, try std.fmt.allocPrint(l.arena, "'{s}' is not a valid {s}; expected one of {s}", .{ s, what, all }), diag.suggest(l.arena, s, &names));
        return null;
    }

    /// Compiles a number, bool or color field.
    fn prop(l: *Loader, n: *const Node, want: Type, scope: *const expr.Scope) Allocator.Error!?Prop {
        var problem: ?expr.Problem = null;
        switch (n.data) {
            .number => |x| {
                if (want != .number) {
                    try l.err(1103, n.pos, "expected a {s}, found a number", .{want.name()});
                    return null;
                }
                const node = try l.arena.create(expr.Node);
                node.* = .{ .start = 0, .end = 0, .data = .{ .number = x } };
                return .{ .node = node, .pos = n.pos, .axis = scope.axis };
            },
            .bool => |b| {
                if (want != .bool) {
                    try l.err(1103, n.pos, "expected a {s}, found a bool", .{want.name()});
                    return null;
                }
                const node = try l.arena.create(expr.Node);
                node.* = .{ .start = 0, .end = 0, .ty = .bool, .data = .{ .boolean = b } };
                return .{ .node = node, .pos = n.pos };
            },
            .string => |s| {
                const node = expr.parse(l.arena, s, 0, &problem) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => {
                        try l.exprProblem(n.pos, problem.?);
                        return null;
                    },
                };
                var c: expr.Checker = .{ .scope = scope, .problem = &problem };
                const t = c.check(node) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => {
                        try l.exprProblem(n.pos, problem.?);
                        return null;
                    },
                };
                if (want == .number and t == .list and l.list_counts) {
                    const args = try l.arena.alloc(*expr.Node, 1);
                    args[0] = node;
                    const len = try l.arena.create(expr.Node);
                    len.* = .{ .start = node.start, .end = node.end, .ty = .number, .data = .{ .call = .{ .func = .len, .args = args } } };
                    return .{ .node = len, .pos = n.pos, .axis = scope.axis };
                }
                if (!t.eql(want)) {
                    try l.exprProblem(n.pos, .{
                        .code = 3003,
                        .start = node.start,
                        .end = node.end,
                        .message = try std.fmt.allocPrint(l.arena, "expected a {s}, the expression gives a {s}", .{ want.name(), t.name() }),
                    });
                    return null;
                }
                return .{ .node = node, .pos = n.pos, .axis = scope.axis };
            },
            else => {
                try l.err(1103, n.pos, "expected a {s} or an expression string, found {s}", .{ want.name(), n.kindName() });
                return null;
            },
        }
    }

    fn template(l: *Loader, n: *const Node, scope: *const expr.Scope) Allocator.Error!?Tmpl {
        const s = switch (n.data) {
            .string => |s| s,
            else => {
                try l.err(1103, n.pos, "expected text, found {s}", .{n.kindName()});
                return null;
            },
        };
        var problem: ?expr.Problem = null;
        const t = expr.parseTemplate(l.arena, s, &problem) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => {
                try l.exprProblem(n.pos, problem.?);
                return null;
            },
        };
        expr.checkTemplate(t, scope, &problem) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => {
                try l.exprProblem(n.pos, problem.?);
                return null;
            },
        };
        return .{ .t = t, .pos = n.pos };
    }

    fn withAxis(scope: *const expr.Scope, axis: expr.Axis) expr.Scope {
        var s = scope.*;
        s.axis = axis;
        return s;
    }
};

const top_fields = [_][]const u8{ "$schema", "format", "name", "note", "canvas", "fonts", "params", "consts", "functions", "layers" };
const param_fields = [_][]const u8{ "type", "default", "required", "label", "note", "min", "max", "max_length", "options", "item", "group" };
const common_fields = [_][]const u8{ "id", "type", "note", "visible", "opacity", "rotate", "anchor", "repeat", "extends", "effects" };

fn kindFields(kind: LayerKind) []const []const u8 {
    return switch (kind) {
        .rect => &.{ "box", "fill", "radius", "stroke" },
        .ellipse => &.{ "box", "fill", "stroke", "arc" },
        .polygon => &.{ "points", "closed", "fill", "stroke", "shape", "box" },
        .text => &.{ "text", "at", "font", "size", "color", "align", "wrap", "line_spacing", "max_lines", "max_width", "max_height", "min_size", "stroke", "shrink_group" },
        .image => &.{ "src", "box", "fit", "smoothing" },
        .group => &.{"layers"},
    };
}

/// Checks `format` [1104, 1105]. Shared by every file type.
pub fn checkFormat(root: *const Node, diags: *diag.List, src: diag.Source) Allocator.Error!bool {
    const f = root.get("format") orelse {
        try diags.at(.err, 1104, src, root.pos, "", "\"format\" is missing", "add \"format\": 1");
        return false;
    };
    if (f.data != .number or f.data.number != 1) {
        try diags.at(.err, 1105, src, f.pos, "/format", "unsupported format version", "this version of yoshida reads \"format\": 1");
        return false;
    }
    return true;
}

/// Parses a JSON file and reports syntax errors [1001]. Returns null on error.
pub fn parseJson(arena: Allocator, diags: *diag.List, src: diag.Source) Allocator.Error!?Node {
    switch (try json.parse(arena, src.text)) {
        .ok => |n| {
            if (n.data != .object) {
                try diags.at(.err, 1103, src, n.pos, "", "the file must contain a JSON object", null);
                return null;
            }
            return n;
        },
        .err => |e| {
            try diags.at(.err, 1001, src, e.pos, "", e.message, null);
            return null;
        },
    }
}

pub const Converted = union(enum) { ok: Value, bad: []const u8 };

/// Converts a JSON literal to a param value, or returns a reason it does not fit.
pub fn convertJson(arena: Allocator, p: *const Param, n: *const Node) Allocator.Error!Converted {
    const Ret = Converted;
    switch (p.kind) {
        .number, .integer => {
            if (n.data != .number) return Ret{ .bad = try std.fmt.allocPrint(arena, "expected a number, found {s}", .{n.kindName()}) };
            const x = n.data.number;
            if (p.kind == .integer and x != @trunc(x)) return Ret{ .bad = "expected a whole number" };
            return Ret{ .ok = .{ .number = x } };
        },
        .bool => {
            if (n.data != .bool) return Ret{ .bad = try std.fmt.allocPrint(arena, "expected true or false, found {s}", .{n.kindName()}) };
            return Ret{ .ok = .{ .bool = n.data.bool } };
        },
        .text, .image, .@"enum" => {
            if (n.data != .string) return Ret{ .bad = try std.fmt.allocPrint(arena, "expected a string, found {s}", .{n.kindName()}) };
            return convertText(arena, p, n.data.string);
        },
        .color => {
            if (n.data != .string) return Ret{ .bad = "expected a color string like \"#RRGGBB\"" };
            return convertText(arena, p, n.data.string);
        },
        .list => {
            const def = p.item.?;
            if (n.data == .object) {
                // Changes to single items of the default list: {"11": {"kind": "safe"}}.
                const base = if (p.default) |dv| dv.list else return Ret{ .bad = "a list given as an object changes items of the default list, but this param has no default" };
                const items = try arena.dupe([]const Value, base);
                for (n.data.object) |f| {
                    const i = std.fmt.parseInt(usize, f.key, 10) catch return Ret{ .bad = try std.fmt.allocPrint(arena, "'{s}' is not an item position; use 0, 1, 2, ...", .{f.key}) };
                    if (i >= items.len) return Ret{ .bad = try std.fmt.allocPrint(arena, "item {d} does not exist; the default list has {d} item(s)", .{ i, items.len }) };
                    if (f.value.data != .object) return Ret{ .bad = try std.fmt.allocPrint(arena, "item {d} must be an object", .{i}) };
                    const vals = try arena.dupe(Value, items[i]);
                    if (try setItemFields(arena, def, vals, &f.value, i)) |msg| return Ret{ .bad = msg };
                    items[i] = vals;
                }
                return Ret{ .ok = .{ .list = items } };
            }
            if (n.data != .array) return Ret{ .bad = try std.fmt.allocPrint(arena, "expected an array (or an object that changes items of the default), found {s}", .{n.kindName()}) };
            const items = try arena.alloc([]const Value, n.data.array.len);
            for (n.data.array, 0..) |*it, i| {
                if (it.data != .object) return Ret{ .bad = try std.fmt.allocPrint(arena, "item {d} must be an object", .{i}) };
                const vals = try arena.alloc(Value, def.names.len);
                for (vals, 0..) |*v, j| v.* = def.defaultOf(j);
                if (try setItemFields(arena, def, vals, it, i)) |msg| return Ret{ .bad = msg };
                items[i] = vals;
            }
            return Ret{ .ok = .{ .list = items } };
        },
    }
}

/// Sets the fields an item object gives. Returns a message when one does not fit.
fn setItemFields(arena: Allocator, def: *const value.ItemDef, vals: []Value, it: *const Node, i: usize) Allocator.Error!?[]const u8 {
    for (it.data.object) |f| {
        const j = def.find(f.key) orelse return try std.fmt.allocPrint(arena, "item {d} has unknown field '{s}'", .{ i, f.key });
        if (try itemFieldValue(arena, def, j, &f.value)) |v| {
            vals[j] = v;
        } else {
            const opts = def.optionsOf(j);
            if (opts.len > 0 and f.value.data == .string) {
                const all = try std.mem.join(arena, ", ", opts);
                return try std.fmt.allocPrint(arena, "item {d} field '{s}': '{s}' is not one of {s}", .{ i, f.key, f.value.data.string, all });
            }
            return try std.fmt.allocPrint(arena, "item {d} field '{s}' must be a{s} {s}", .{ i, f.key, if (opts.len > 0) "n" else "", if (opts.len > 0) "enum option" else @tagName(def.types[j]) });
        }
    }
    return null;
}

/// The value of item field `j` from JSON, or null when it does not fit.
fn itemFieldValue(arena: Allocator, def: *const value.ItemDef, j: usize, n: *const Node) Allocator.Error!?Value {
    _ = arena;
    const opts = def.optionsOf(j);
    return switch (def.types[j]) {
        .number => if (n.data == .number) .{ .number = n.data.number } else null,
        .bool => if (n.data == .bool) .{ .bool = n.data.bool } else null,
        .text => blk: {
            if (n.data != .string) break :blk null;
            if (opts.len > 0) {
                for (opts) |o| if (std.mem.eql(u8, o, n.data.string)) break :blk Value{ .text = n.data.string };
                break :blk null;
            }
            break :blk .{ .text = n.data.string };
        },
        .image => if (n.data == .string) .{ .image = n.data.string } else null,
        .color => if (n.data == .string) (if (value.Color.parseHex(n.data.string)) |c| Value{ .color = c } else null) else null,
    };
}

/// Converts a CSV cell or JSON string to a param value.
pub fn convertText(arena: Allocator, p: *const Param, s: []const u8) Allocator.Error!Converted {
    const Ret = Converted;
    switch (p.kind) {
        .number, .integer => {
            const x = std.fmt.parseFloat(f64, std.mem.trim(u8, s, " ")) catch return Ret{ .bad = try std.fmt.allocPrint(arena, "'{s}' is not a number", .{s}) };
            if (!std.math.isFinite(x)) return Ret{ .bad = "number out of range" };
            if (p.kind == .integer and x != @trunc(x)) return Ret{ .bad = "expected a whole number" };
            return Ret{ .ok = .{ .number = x } };
        },
        .bool => {
            if (std.mem.eql(u8, s, "true")) return Ret{ .ok = .{ .bool = true } };
            if (std.mem.eql(u8, s, "false")) return Ret{ .ok = .{ .bool = false } };
            return Ret{ .bad = "expected true or false" };
        },
        .text => return Ret{ .ok = .{ .text = s } },
        .image => return Ret{ .ok = .{ .image = s } },
        .@"enum" => {
            for (p.options) |o| if (std.mem.eql(u8, o, s)) return Ret{ .ok = .{ .text = s } };
            const all = try std.mem.join(arena, ", ", p.options);
            return Ret{ .bad = try std.fmt.allocPrint(arena, "'{s}' is not one of {s}", .{ s, all }) };
        },
        .color => {
            const c = value.Color.parseHex(s) orelse return Ret{ .bad = try std.fmt.allocPrint(arena, "'{s}' is not a color like #RRGGBB or #RRGGBBAA", .{s}) };
            return Ret{ .ok = .{ .color = c } };
        },
        .list => {
            switch (try json.parse(arena, s)) {
                .ok => |n| return convertJson(arena, p, &n),
                .err => |e| return Ret{ .bad = try std.fmt.allocPrint(arena, "list cell is not valid JSON: {s}", .{e.message}) },
            }
        },
    }
}

/// Checks min, max and max_length. Returns a message when the value is outside.
pub fn checkRange(arena: Allocator, p: *const Param, v: Value) Allocator.Error!?[]const u8 {
    switch (v) {
        .number => |x| {
            if (p.min) |m| if (x < m) return try std.fmt.allocPrint(arena, "{d} is below the minimum {d}", .{ x, m });
            if (p.max) |m| if (x > m) return try std.fmt.allocPrint(arena, "{d} is above the maximum {d}", .{ x, m });
        },
        .text => |t| if (p.max_length) |m| {
            const n = std.unicode.utf8CountCodepoints(t) catch t.len;
            if (n > m) return try std.fmt.allocPrint(arena, "text has {d} characters, the maximum is {d}", .{ n, m });
        },
        else => {},
    }
    return null;
}

pub fn load(arena: Allocator, diags: *diag.List, file: []const u8, text: []const u8) Allocator.Error!*Design {
    const d = try arena.create(Design);
    const src: diag.Source = .{ .file = file, .text = text };
    d.* = .{ .file = file, .source = text, .root = .{ .pos = 0, .data = .null } };
    d.root = (try parseJson(arena, diags, src)) orelse return d;
    var l: Loader = .{ .arena = arena, .diags = diags, .src = src, .root = &d.root };
    const root = &d.root;
    if (!try checkFormat(root, diags, src)) l.errors += 1;
    try l.checkFields(root, &top_fields, "a design");

    if (root.get("name")) |n| {
        if (try l.literalString(n, "name")) |s| d.name = s;
    } else try l.err(1102, root.pos, "the design needs a \"name\"", .{});

    // Params
    var params: std.ArrayList(Param) = .empty;
    var symbols: std.ArrayList(expr.Symbol) = .empty;
    if (root.get("params")) |pn| if (try l.expectObject(pn, "params")) {
        for (pn.data.object) |*f| {
            if (try loadParam(&l, f)) |p| {
                try params.append(arena, p);
                try symbols.append(arena, .{ .name = p.name, .ty = p.ty });
            }
        }
    };
    d.params = params.items;
    d.symbols = symbols.items;

    // Canvas
    const canvas_scope: expr.Scope = .{ .arena = arena, .params = d.symbols, .layers = null, .allow_units = false, .allow_builtins = false };
    if (root.get("canvas")) |cn| {
        if (try l.expectObject(cn, "canvas")) {
            try l.checkFields(cn, &.{ "width", "height", "background", "dpi", "bleed" }, "canvas");
            if (cn.get("width")) |w| d.canvas_w = try l.prop(w, .number, &canvas_scope) else try l.err(1102, cn.pos, "canvas needs \"width\"", .{});
            if (cn.get("height")) |h| d.canvas_h = try l.prop(h, .number, &canvas_scope) else try l.err(1102, cn.pos, "canvas needs \"height\"", .{});
            if (cn.get("background")) |b| d.background = try l.prop(b, .color, &canvas_scope);
            if (cn.get("dpi")) |v| d.dpi = try l.prop(v, .number, &canvas_scope);
            if (cn.get("bleed")) |v| d.bleed = try l.prop(v, .number, &canvas_scope);
        }
    } else try l.err(1102, root.pos, "the design needs a \"canvas\" with width and height", .{});

    try loadConsts(&l, d);
    try loadFunctions(&l, d);

    // Fonts
    var fonts: std.ArrayList(Font) = .empty;
    if (root.get("fonts")) |fnode| if (try l.expectObject(fnode, "fonts")) {
        for (fnode.data.object) |f| {
            if (!expr.isIdent(f.key)) try l.err(1103, f.key_pos, "font name '{s}' must be lowercase letters, digits and '_'", .{f.key});
            if (try l.literalString(&f.value, "a font path")) |p| try fonts.append(arena, .{ .name = f.key, .path = p, .pos = f.value.pos });
        }
    };
    d.fonts = fonts.items;

    // Layers
    if (root.get("layers")) |ln| {
        if (ln.data == .array) {
            d.layers = try loadLayers(&l, d, ln.data.array);
        } else try l.err(1103, ln.pos, "layers must be an array, found {s}", .{ln.kindName()});
    } else try l.err(1102, root.pos, "the design needs \"layers\"", .{});

    d.ok = l.errors == 0;
    return d;
}

/// True when `name` is taken by a param, constant or function [1106].
fn nameTaken(d: *const Design, consts: []const expr.Symbol, fns: []const expr.FnSig, name: []const u8) bool {
    if (expr.isReserved(name) or d.findParam(name) != null) return true;
    for (consts) |k| if (std.mem.eql(u8, k.name, name)) return true;
    for (fns) |f| if (std.mem.eql(u8, f.name, name)) return true;
    return false;
}

/// `"consts": { "tile": 170, "gap": "tile / 10" }`: each sees params, the
/// canvas size and the constants before it.
fn loadConsts(l: *Loader, d: *Design) Allocator.Error!void {
    const cn = d.root.get("consts") orelse return;
    if (!try l.expectObject(cn, "consts")) return;
    var consts: std.ArrayList(Const) = .empty;
    var syms: std.ArrayList(expr.Symbol) = .empty;
    for (cn.data.object) |*f| {
        if (!expr.isIdent(f.key) or nameTaken(d, syms.items, &.{}, f.key)) {
            try l.err(1106, f.key_pos, "constant name '{s}' must be lowercase letters, digits and '_', and not a param, reserved word or function name", .{f.key});
            continue;
        }
        const scope: expr.Scope = .{ .arena = l.arena, .params = d.symbols, .consts = syms.items, .layers = null };
        const want: Type = switch (f.value.data) {
            .number => .number,
            .bool => .bool,
            .string => |src| {
                // The type is whatever the expression gives.
                var problem: ?expr.Problem = null;
                const node = expr.parse(l.arena, src, 0, &problem) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => {
                        try l.exprProblem(f.value.pos, problem.?);
                        continue;
                    },
                };
                var c: expr.Checker = .{ .scope = &scope, .problem = &problem };
                const t = c.check(node) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => {
                        try l.exprProblem(f.value.pos, problem.?);
                        continue;
                    },
                };
                if (t == .list or t == .item) {
                    try l.err(3003, f.value.pos, "a constant cannot be a list or a list item", .{});
                    continue;
                }
                try consts.append(l.arena, .{ .name = f.key, .prop = .{ .node = node, .pos = f.value.pos } });
                try syms.append(l.arena, .{ .name = f.key, .ty = t });
                continue;
            },
            else => {
                try l.err(1103, f.value.pos, "a constant is a number, true/false or an expression string", .{});
                continue;
            },
        };
        const p = (try l.prop(&f.value, want, &scope)) orelse continue;
        try consts.append(l.arena, .{ .name = f.key, .prop = p });
        try syms.append(l.arena, .{ .name = f.key, .ty = want });
    }
    d.consts = consts.items;
    d.const_symbols = syms.items;
}

/// `"functions": { "tile_x": { "args": { "i": "number" }, "expr": "65 + i * 170" } }`:
/// each sees its arguments, params, constants and the functions before it.
fn loadFunctions(l: *Loader, d: *Design) Allocator.Error!void {
    const fnode = d.root.get("functions") orelse return;
    if (!try l.expectObject(fnode, "functions")) return;
    const arena = l.arena;
    var fns: std.ArrayList(Function) = .empty;
    var sigs: std.ArrayList(expr.FnSig) = .empty;
    for (fnode.data.object) |*f| {
        if (!expr.isIdent(f.key) or nameTaken(d, d.const_symbols, sigs.items, f.key)) {
            try l.err(1106, f.key_pos, "function name '{s}' must be lowercase letters, digits and '_', and not a param, constant, reserved word or built-in function", .{f.key});
            continue;
        }
        if (!try l.expectObject(&f.value, "a function")) continue;
        try l.checkFields(&f.value, &.{ "args", "expr", "note" }, "a function");
        var args: std.ArrayList(expr.Symbol) = .empty;
        if (f.value.get("args")) |an| {
            switch (an.data) {
                // ["i", "j"]: numbers.
                .array => |items| for (items) |*it| {
                    if (try l.literalString(it, "an argument name")) |name| try args.append(arena, .{ .name = name, .ty = .number });
                },
                .object => |fields| for (fields) |af| {
                    const tn = (try l.literalString(&af.value, "an argument type")) orelse continue;
                    const ty: ?Type = if (std.mem.eql(u8, tn, "number")) .number else if (std.mem.eql(u8, tn, "text")) .text else if (std.mem.eql(u8, tn, "bool")) .bool else if (std.mem.eql(u8, tn, "color")) .color else null;
                    if (ty) |t| try args.append(arena, .{ .name = af.key, .ty = t }) else try l.err(1103, af.value.pos, "'{s}' is not an argument type; use number, text, bool or color", .{tn});
                },
                else => try l.err(1103, an.pos, "args must be an object of name to type, e.g. {{\"i\": \"number\"}}", .{}),
            }
        }
        for (args.items) |a| if (!expr.isIdent(a.name) or expr.isReserved(a.name)) try l.err(1103, f.value.pos, "'{s}' is not a valid argument name", .{a.name});
        const en = f.value.get("expr") orelse {
            try l.err(1102, f.value.pos, "function '{s}' needs \"expr\"", .{f.key});
            continue;
        };
        const src = (try l.literalString(en, "expr")) orelse continue;
        const scope: expr.Scope = .{ .arena = arena, .params = d.symbols, .locals = args.items, .consts = d.const_symbols, .functions = sigs.items, .layers = null };
        var problem: ?expr.Problem = null;
        const node = expr.parse(arena, src, 0, &problem) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => {
                try l.exprProblem(en.pos, problem.?);
                continue;
            },
        };
        var c: expr.Checker = .{ .scope = &scope, .problem = &problem };
        const t = c.check(node) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => {
                try l.exprProblem(en.pos, problem.?);
                continue;
            },
        };
        try fns.append(arena, .{ .name = f.key, .args = args.items, .body = node, .ret = t, .pos = en.pos });
        try sigs.append(arena, .{ .name = f.key, .args = args.items, .ret = t });
    }
    d.functions = fns.items;
    d.fn_sigs = sigs.items;
}

fn loadParam(l: *Loader, f: *const Node.Field) Allocator.Error!?Param {
    const arena = l.arena;
    const name = f.key;
    if (!expr.isIdent(name)) {
        try l.err(1106, f.key_pos, "param name '{s}' must be lowercase letters, digits and '_'", .{name});
        return null;
    }
    if (expr.isReserved(name)) {
        try l.err(1106, f.key_pos, "param name '{s}' is a reserved word or function name", .{name});
        return null;
    }
    const n = &f.value;
    if (!try l.expectObject(n, "a param")) return null;
    try l.checkFields(n, &param_fields, "a param");
    const tn = n.get("type") orelse {
        try l.err(1102, n.pos, "param '{s}' needs a \"type\"", .{name});
        return null;
    };
    const kind = (try l.enumField(ParamKind, tn, "param type")) orelse return null;
    var p: Param = .{ .name = name, .kind = kind, .ty = .number, .pos = f.key_pos };
    p.ty = switch (kind) {
        .number, .integer => .number,
        .text, .@"enum" => .text,
        .bool => .bool,
        .color => .color,
        .image => .image,
        .list => .number, // set below
    };
    if (n.get("label")) |v| p.label = try l.literalString(v, "label");
    if (n.get("note")) |v| p.note = if (v.data == .string) v.data.string else null;
    if (n.get("group")) |v| p.group = try l.literalString(v, "group");
    if (n.get("required")) |v| {
        if (v.data == .bool) p.required = v.data.bool else try l.err(1103, v.pos, "required must be true or false", .{});
    }
    for ([_][]const u8{ "min", "max" }) |key| if (n.get(key)) |v| {
        if (kind != .number and kind != .integer) {
            try l.err(1101, v.pos, "'{s}' only applies to number and integer params", .{key});
        } else if (v.data != .number) {
            try l.err(1103, v.pos, "'{s}' must be a number", .{key});
        } else if (key[1] == 'i') p.min = v.data.number else p.max = v.data.number;
    };
    if (n.get("max_length")) |v| {
        if (kind != .text) try l.err(1101, v.pos, "'max_length' only applies to text params", .{}) else if (v.data != .number or v.data.number < 0) try l.err(1103, v.pos, "'max_length' must be a positive number", .{}) else p.max_length = @intFromFloat(v.data.number);
    }
    if (kind == .@"enum") {
        const on = n.get("options") orelse {
            try l.err(1102, n.pos, "enum param '{s}' needs \"options\"", .{name});
            return null;
        };
        var opts: std.ArrayList([]const u8) = .empty;
        if (on.data == .array and on.data.array.len > 0) {
            for (on.data.array) |*o| {
                if (try l.literalString(o, "an option")) |s| try opts.append(arena, s);
            }
        } else try l.err(1103, on.pos, "options must be a non-empty array of strings", .{});
        p.options = opts.items;
    } else if (n.get("options")) |v| try l.err(1101, v.pos, "'options' only applies to enum params", .{});
    if (kind == .list) {
        const in = n.get("item") orelse {
            try l.err(1102, n.pos, "list param '{s}' needs \"item\"", .{name});
            return null;
        };
        if (!try l.expectObject(in, "item")) return null;
        const def = try arena.create(value.ItemDef);
        var names: std.ArrayList([]const u8) = .empty;
        var types: std.ArrayList(value.Scalar) = .empty;
        var options: std.ArrayList([]const []const u8) = .empty;
        var defaults: std.ArrayList(?Value) = .empty;
        var default_nodes: std.ArrayList(?*const Node) = .empty;
        for (in.data.object) |*itf| {
            // "kind": "text", or "kind": { "type": "enum", "options": [...], "default": "plain" }.
            var type_node: *const Node = &itf.value;
            var opts: std.ArrayList([]const u8) = .empty;
            var default_node: ?*const Node = null;
            if (itf.value.data == .object) {
                try l.checkFields(&itf.value, &.{ "type", "options", "default" }, "an item field");
                type_node = itf.value.get("type") orelse {
                    try l.err(1102, itf.value.pos, "item field '{s}' needs a \"type\"", .{itf.key});
                    continue;
                };
                default_node = itf.value.get("default");
                if (itf.value.get("options")) |on| {
                    if (on.data == .array and on.data.array.len > 0) {
                        for (on.data.array) |*o| if (try l.literalString(o, "an option")) |os| try opts.append(arena, os);
                    } else try l.err(1103, on.pos, "options must be a non-empty array of strings", .{});
                }
            }
            const s = (try l.literalString(type_node, "an item field type")) orelse continue;
            const is_enum = std.mem.eql(u8, s, "enum");
            const sc = if (is_enum) value.Scalar.text else value.Scalar.fromName(s) orelse {
                try l.errHint(1103, type_node.pos, try std.fmt.allocPrint(arena, "'{s}' is not an item field type", .{s}), "use number, integer, text, bool, color or enum");
                continue;
            };
            if (is_enum and opts.items.len == 0) {
                try l.err(1102, itf.value.pos, "enum item field '{s}' needs \"options\"", .{itf.key});
                continue;
            }
            if (!is_enum and opts.items.len > 0) try l.err(1101, itf.value.pos, "'options' only applies to enum item fields", .{});
            try names.append(arena, itf.key);
            try types.append(arena, sc);
            try options.append(arena, if (is_enum) opts.items else &.{});
            try defaults.append(arena, null);
            try default_nodes.append(arena, default_node);
        }
        def.* = .{ .names = names.items, .types = types.items, .options = options.items, .defaults = defaults.items };
        for (default_nodes.items, 0..) |dn, j| if (dn) |n2| {
            if (try itemFieldValue(arena, def, j, n2)) |v| {
                defaults.items[j] = v;
            } else try l.err(1103, n2.pos, "default of item field '{s}' does not fit its type", .{def.names[j]});
        };
        p.item = def;
        p.ty = .{ .list = def };
    } else if (n.get("item")) |v| try l.err(1101, v.pos, "'item' only applies to list params", .{});

    if (n.get("default")) |dv| {
        switch (try convertJson(arena, &p, dv)) {
            .ok => |v| {
                p.default = v;
                if (try checkRange(arena, &p, v)) |msg| try l.err(2002, dv.pos, "default of '{s}': {s}", .{ name, msg });
            },
            .bad => |msg| try l.err(1103, dv.pos, "default of '{s}': {s}", .{ name, msg }),
        }
    } else if (!p.required) {
        try l.errHint(1107, f.key_pos, try std.fmt.allocPrint(arena, "param '{s}' has neither a default nor required: true", .{name}), "add a \"default\" or \"required\": true");
    }
    return p;
}

const Raw = struct {
    node: *const Node,
    parent: ?usize = null,
    id: []const u8 = "",
    kind: ?LayerKind = null,
    /// Dividers only organise the layer list: they keep their id but are
    /// never compiled, drawn or referenced.
    divider: bool = false,
    merged: ?Node = null,
    state: enum { todo, busy, done } = .todo,
};

const group_fields = [_][]const u8{ "id", "type", "note", "visible", "opacity", "rotate", "effects", "layers", "repeat", "translate" };
const divider_fields = [_][]const u8{ "id", "type", "note", "label" };

fn isGroup(n: *const Node) bool {
    const t = n.get("type") orelse return false;
    return t.data == .string and std.mem.eql(u8, t.data.string, "group");
}

fn isDivider(n: *const Node) bool {
    const t = n.get("type") orelse return false;
    return t.data == .string and std.mem.eql(u8, t.data.string, "divider");
}

/// Flattens nested groups into one list in document order (a group comes
/// right before its descendants).
fn flatten(l: *Loader, out: *std.ArrayList(Raw), nodes: []const Node, parent: ?usize, depth: usize) Allocator.Error!void {
    for (nodes) |*n| {
        const i = out.items.len;
        try out.append(l.arena, .{ .node = n, .parent = parent });
        if (n.data != .object or !isGroup(n)) continue;
        const ln = n.get("layers") orelse {
            try l.err(1102, n.pos, "a group needs \"layers\"", .{});
            continue;
        };
        if (ln.data != .array) {
            try l.err(1103, ln.pos, "layers must be an array", .{});
            continue;
        }
        if (depth >= 16) {
            try l.err(5001, ln.pos, "groups are nested more than 16 deep", .{});
            continue;
        }
        try flatten(l, out, ln.data.array, i, depth + 1);
    }
}

fn loadLayers(l: *Loader, d: *Design, top: []const Node) Allocator.Error![]const Layer {
    const arena = l.arena;
    var flat: std.ArrayList(Raw) = .empty;
    try flatten(l, &flat, top, null, 0);
    const raws = flat.items;
    // Pass 1: ids and types.
    for (raws, 0..) |*raw, i| {
        const n = raw.node;
        if (!try l.expectObject(n, "a layer")) continue;
        if (n.get("id")) |idn| {
            if (idn.data == .string and expr.isIdent(idn.data.string)) {
                for (raws[0..i]) |r| if (std.mem.eql(u8, r.id, idn.data.string)) {
                    try l.err(1108, idn.pos, "duplicate layer id '{s}'", .{idn.data.string});
                };
                raws[i].id = idn.data.string;
            } else try l.errHint(1108, idn.pos, "invalid layer id", "ids are lowercase letters, digits and '_', starting with a letter or '_'");
        } else try l.err(1102, n.pos, "layer {d} needs an \"id\"", .{i});
        if (isDivider(n)) {
            raws[i].divider = true;
            try l.checkFields(n, &divider_fields, "a divider");
            if (n.get("label")) |v| _ = try l.literalString(v, "label");
            continue;
        }
        if (n.get("type")) |tn| {
            raws[i].kind = try l.enumField(LayerKind, tn, "layer type");
        } else try l.err(1102, n.pos, "layer {d} needs a \"type\"", .{i});
        if (raws[i].kind == .group) {
            try l.checkFields(n, &group_fields, "a group");
        } else if (raws[i].kind) |k| {
            var allowed: std.ArrayList([]const u8) = .empty;
            try allowed.appendSlice(arena, &common_fields);
            try allowed.appendSlice(arena, kindFields(k));
            try l.checkFields(n, allowed.items, try std.fmt.allocPrint(arena, "a {s} layer", .{@tagName(k)}));
        }
    }
    // Pass 2: extends.
    for (raws) |*r| _ = try merge(l, raws, r);

    // Pass 3: symbols for @ references, with the repeated groups around
    // each layer (raw indices, outermost first).
    const rgroups = try arena.alloc([]const usize, raws.len);
    for (raws, 0..) |r, i| {
        var chain: std.ArrayList(usize) = .empty;
        var p = r.parent;
        while (p) |pi| : (p = raws[pi].parent) {
            if (raws[pi].merged) |pm| if (pm.get("repeat") != null) try chain.insert(arena, 0, pi);
        }
        rgroups[i] = chain.items;
    }
    var lsyms: std.ArrayList(expr.LayerSymbol) = .empty;
    for (raws, 0..) |r, i| {
        const k = r.kind orelse continue;
        if (r.id.len == 0) continue;
        const m = r.merged orelse continue;
        try lsyms.append(arena, .{ .id = r.id, .kind = k, .repeated = m.get("repeat") != null, .rgroups = rgroups[i] });
    }

    // Pass 4: compile. Layers inside a repeated group see its loop names.
    var layers: std.ArrayList(Layer) = .empty;
    const at = try arena.alloc(?usize, raws.len);
    const exposed = try arena.alloc([]const expr.Symbol, raws.len);
    for (raws, 0..) |r, i| {
        at[i] = null;
        exposed[i] = &.{};
        const k = r.kind orelse continue;
        const m = r.merged orelse continue;
        if (r.id.len == 0) continue;
        const outer: []const expr.Symbol = if (r.parent) |p| exposed[p] else &.{};
        if (try compileLayer(l, d, lsyms.items, &m, r.id, k, i, outer, rgroups[i], &exposed[i])) |layer| {
            var x = layer;
            x.parent = if (r.parent) |p| at[p] else null;
            at[i] = layers.items.len;
            try layers.append(arena, x);
        }
    }
    // Group extents: descendants follow their group directly.
    const ls = layers.items;
    for (ls, 0..) |*g, gi| {
        if (g.kind != .group) continue;
        var e = gi + 1;
        while (e < ls.len and isInside(ls, e, gi)) e += 1;
        g.end = e;
    }
    return ls;
}

fn isInside(ls: []const Layer, i: usize, group: usize) bool {
    var p = ls[i].parent;
    while (p) |x| : (p = ls[x].parent) if (x == group) return true;
    return false;
}

/// Resolves `extends` for one layer; objects merge key by key [1112, 3004].
fn merge(l: *Loader, raws: []Raw, r: *Raw) Allocator.Error!?Node {
    switch (r.state) {
        .done => return r.merged,
        .busy => return null,
        .todo => {},
    }
    if (r.node.data != .object) {
        r.state = .done;
        return null;
    }
    r.state = .busy;
    defer r.state = .done;
    const ext = r.node.get("extends") orelse {
        r.merged = r.node.*;
        return r.merged;
    };
    const base_id = switch (ext.data) {
        .string => |s| s,
        else => {
            try l.err(1103, ext.pos, "extends must be a layer id string", .{});
            return null;
        },
    };
    var base: ?*Raw = null;
    var ids: std.ArrayList([]const u8) = .empty;
    for (raws) |*o| {
        if (std.mem.eql(u8, o.id, base_id) and o != r) base = o;
        if (o.id.len > 0) try ids.append(l.arena, o.id);
    }
    const b = base orelse {
        try l.errHint(3002, ext.pos, try std.fmt.allocPrint(l.arena, "unknown layer '{s}' in extends", .{base_id}), diag.suggest(l.arena, base_id, ids.items));
        return null;
    };
    if (b.state == .busy) {
        try l.err(3004, ext.pos, "extends cycle through '{s}'", .{base_id});
        return null;
    }
    if (b.divider) {
        try l.err(1112, ext.pos, "'{s}' is a divider, layers cannot extend it", .{base_id});
        return null;
    }
    const parent = (try merge(l, raws, b)) orelse return null;
    if (b.kind != null and r.kind != null and b.kind.? != r.kind.?) {
        try l.err(1112, ext.pos, "'{s}' is a {s} layer, this is a {s} layer", .{ base_id, @tagName(b.kind.?), @tagName(r.kind.?) });
        return null;
    }
    var fields: std.ArrayList(Node.Field) = .empty;
    for (parent.data.object) |f| {
        if (std.mem.eql(u8, f.key, "id") or std.mem.eql(u8, f.key, "extends") or std.mem.eql(u8, f.key, "note")) continue;
        try fields.append(l.arena, f);
    }
    for (r.node.data.object) |f| {
        var replaced = false;
        for (fields.items) |*e| {
            if (!std.mem.eql(u8, e.key, f.key)) continue;
            replaced = true;
            if (e.value.data == .object and f.value.data == .object) {
                var sub: std.ArrayList(Node.Field) = .empty;
                try sub.appendSlice(l.arena, e.value.data.object);
                outer: for (f.value.data.object) |sf| {
                    for (sub.items) |*se| if (std.mem.eql(u8, se.key, sf.key)) {
                        se.* = sf;
                        continue :outer;
                    };
                    try sub.append(l.arena, sf);
                }
                e.* = .{ .key = f.key, .key_pos = f.key_pos, .value = .{ .pos = f.value.pos, .data = .{ .object = sub.items } } };
            } else e.* = f;
        }
        if (!replaced) try fields.append(l.arena, f);
    }
    r.merged = .{ .pos = r.node.pos, .data = .{ .object = fields.items } };
    return r.merged;
}

fn compileLayer(l: *Loader, d: *Design, lsyms: []const expr.LayerSymbol, m: *const Node, id: []const u8, kind: LayerKind, index: usize, outer: []const expr.Symbol, rgroups: []const usize, exposed: *[]const expr.Symbol) Allocator.Error!?Layer {
    const arena = l.arena;
    var layer: Layer = .{ .id = id, .kind = kind, .index = index, .pos = m.pos };
    var base_scope: expr.Scope = .{ .arena = arena, .params = d.symbols, .locals = outer, .layers = lsyms, .consts = d.const_symbols, .functions = d.fn_sigs, .rgroups = rgroups };

    // repeat: its own expressions see params and the loop names of the
    // groups around the layer; the layer's fields also see its own.
    var locals: std.ArrayList(expr.Symbol) = .empty;
    try locals.appendSlice(arena, outer);
    if (m.get("repeat")) |rn| if (try l.expectObject(rn, "repeat")) {
        try l.checkFields(rn, &.{ "count", "each", "index", "item" }, "repeat");
        var rep: Repeat = .{};
        const has_count = rn.get("count") != null;
        const has_each = rn.get("each") != null;
        if (has_count == has_each) try l.err(1111, rn.pos, "repeat needs exactly one of \"count\" and \"each\"", .{});
        if (rn.get("index")) |v| {
            if (try l.literalString(v, "repeat.index")) |s| {
                if (expr.isIdent(s) and !expr.isReserved(s)) rep.index_name = s else try l.err(1103, v.pos, "'{s}' is not a valid loop name", .{s});
            }
        }
        try locals.append(arena, .{ .name = rep.index_name, .ty = .number });
        if (rn.get("count")) |v| {
            l.list_counts = true;
            defer l.list_counts = false;
            rep.count = try l.prop(v, .number, &base_scope);
        }
        if (rn.get("each")) |v| {
            var problem: ?expr.Problem = null;
            if (v.data != .string) {
                try l.err(1103, v.pos, "repeat.each must be an expression giving a list", .{});
            } else if (expr.parse(arena, v.data.string, 0, &problem)) |node| {
                var c: expr.Checker = .{ .scope = &base_scope, .problem = &problem };
                if (c.check(node)) |t| {
                    if (t == .list) {
                        rep.each = .{ .node = node, .pos = v.pos };
                        if (rn.get("item")) |itn| {
                            if (try l.literalString(itn, "repeat.item")) |s| {
                                if (expr.isIdent(s) and !expr.isReserved(s)) {
                                    rep.item_name = s;
                                    try locals.append(arena, .{ .name = s, .ty = .{ .item = t.list } });
                                } else try l.err(1103, itn.pos, "'{s}' is not a valid loop name", .{s});
                            }
                        }
                    } else try l.exprProblem(v.pos, .{ .code = 3003, .start = node.start, .end = node.end, .message = try std.fmt.allocPrint(arena, "repeat.each needs a list, got a {s}", .{t.name()}) });
                } else |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Invalid => try l.exprProblem(v.pos, problem.?),
                }
            } else |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Invalid => try l.exprProblem(v.pos, problem.?),
            }
        } else if (rn.get("item")) |itn| try l.err(1101, itn.pos, "repeat.item only applies with \"each\"", .{});
        layer.repeat = rep;
    };
    base_scope.locals = locals.items;
    exposed.* = locals.items;
    const scope = &base_scope;
    var sx = Loader.withAxis(scope, .x);
    var sy = Loader.withAxis(scope, .y);

    if (kind == .group) if (m.get("translate")) |tn| if (try l.expectObject(tn, "translate")) {
        try l.checkFields(tn, &.{ "x", "y" }, "translate");
        const px = if (tn.get("x")) |v| try l.prop(v, .number, &sx) else try constProp(arena, .{ .number = 0 }, tn.pos);
        const py = if (tn.get("y")) |v| try l.prop(v, .number, &sy) else try constProp(arena, .{ .number = 0 }, tn.pos);
        if (px != null and py != null) layer.translate = .{ .x = px.?, .y = py.? };
    };
    if (m.get("visible")) |v| layer.visible = try l.prop(v, .bool, scope);
    if (m.get("opacity")) |v| layer.opacity = try l.prop(v, .number, scope);
    if (m.get("rotate")) |v| layer.rotate = try l.prop(v, .number, scope);
    if (m.get("anchor")) |v| {
        if (try l.enumField(Anchor, v, "anchor")) |a| {
            if (a.isBaseline() and kind != .text) try l.err(1103, v.pos, "baseline anchors only apply to text layers", .{}) else layer.anchor = a;
        }
    }
    if (m.get("effects")) |en| {
        if (en.data == .array) {
            var effects: std.ArrayList(Effect) = .empty;
            for (en.data.array) |*e| {
                if (!try l.expectObject(e, "an effect")) continue;
                const tn = e.get("type") orelse {
                    try l.err(1102, e.pos, "effect needs a \"type\"", .{});
                    continue;
                };
                const ek = (try l.enumField(EffectKind, tn, "effect")) orelse continue;
                var eff: Effect = .{ .kind = ek, .pos = e.pos };
                if (ek == .crop or ek == .fade) {
                    try l.checkFields(e, &.{ "type", "side", "length" }, try std.fmt.allocPrint(arena, "a {s} effect", .{@tagName(ek)}));
                    if (e.get("side")) |sn| eff.side = (try l.enumField(Side, sn, "side")) orelse .bottom else try l.err(1102, e.pos, "{s} needs \"side\"", .{@tagName(ek)});
                    const ax: *const expr.Scope = if (eff.side == .left or eff.side == .right) &sx else &sy;
                    if (e.get("length")) |ln| eff.length = try l.prop(ln, .number, ax) else try l.err(1102, e.pos, "{s} needs \"length\"", .{@tagName(ek)});
                } else {
                    try l.checkFields(e, &.{ "type", "strength" }, try std.fmt.allocPrint(arena, "a {s} effect", .{@tagName(ek)}));
                    if (e.get("strength")) |sn| eff.strength = try l.prop(sn, .number, scope);
                }
                try effects.append(arena, eff);
            }
            layer.effects = effects.items;
        } else try l.err(1103, en.pos, "effects must be an array", .{});
    }

    const shape_polygon = kind == .polygon and m.get("shape") != null;
    switch (kind) {
        .rect, .ellipse, .image, .polygon => if (kind != .polygon or shape_polygon) {
            if (m.get("box")) |bn| {
                if (try l.expectObject(bn, "box")) {
                    try l.checkFields(bn, &.{ "x", "y", "w", "h" }, "box");
                    var ok = true;
                    var props: [4]?Prop = .{ null, null, null, null };
                    var autos: [2]bool = .{ false, false };
                    for ([_][]const u8{ "x", "y", "w", "h" }, 0..) |key, i| {
                        const vn = bn.get(key) orelse {
                            try l.err(1102, bn.pos, "box needs \"{s}\"", .{key});
                            ok = false;
                            continue;
                        };
                        if (i >= 2 and vn.data == .string and std.mem.eql(u8, vn.data.string, "auto")) {
                            if (kind != .image) {
                                try l.err(1103, vn.pos, "\"auto\" size only applies to image layers", .{});
                                ok = false;
                            }
                            autos[i - 2] = true;
                            continue;
                        }
                        props[i] = try l.prop(vn, .number, if (i % 2 == 0) &sx else &sy);
                        if (props[i] == null) ok = false;
                    }
                    if (autos[0] and autos[1]) {
                        try l.err(1110, bn.pos, "box w and h cannot both be \"auto\"", .{});
                        ok = false;
                    }
                    if (ok) layer.box = .{ .x = props[0].?, .y = props[1].?, .w = props[2], .h = props[3] };
                }
            } else try l.err(1102, m.pos, "{s} layer '{s}' needs a \"box\"", .{ @tagName(kind), id });
        } else if (m.get("box")) |bn| try l.err(1101, bn.pos, "a polygon has \"box\" only with \"shape\"", .{}),
        else => {},
    }
    switch (kind) {
        .rect, .ellipse, .polygon, .text => {
            if (kind != .text) if (m.get("fill")) |v| {
                layer.fill = try l.prop(v, .color, scope);
            };
            if (m.get("stroke")) |sn| if (try l.expectObject(sn, "stroke")) {
                try l.checkFields(sn, &.{ "color", "width", "dash", "arrow" }, "stroke");
                const cp = if (sn.get("color")) |v| try l.prop(v, .color, scope) else try constProp(arena, .{ .color = value.Color.black }, sn.pos);
                const wp = if (sn.get("width")) |v| try l.prop(v, .number, scope) else try constProp(arena, .{ .number = 1 }, sn.pos);
                var dash: std.ArrayList(Prop) = .empty;
                if (sn.get("dash")) |dn| {
                    if (kind == .text) {
                        try l.err(1101, dn.pos, "text outlines cannot be dashed", .{});
                    } else if (dn.data == .array and dn.data.array.len > 0) {
                        for (dn.data.array) |*dv| if (try l.prop(dv, .number, scope)) |p| try dash.append(arena, p);
                    } else try l.err(1103, dn.pos, "dash must be a non-empty array of lengths, e.g. [12, 6]", .{});
                }
                var arrow: Arrow = .none;
                if (sn.get("arrow")) |an| {
                    if (kind != .polygon) try l.err(1101, an.pos, "arrowheads only apply to polygons", .{}) else arrow = (try l.enumField(Arrow, an, "arrow")) orelse .none;
                }
                if (cp != null and wp != null) layer.stroke = .{ .color = cp.?, .width = wp.?, .dash = dash.items, .arrow = arrow };
            };
            if (kind == .ellipse) if (m.get("arc")) |an| if (try l.expectObject(an, "arc")) {
                try l.checkFields(an, &.{ "start", "end", "pie" }, "arc");
                const sp = if (an.get("start")) |v| try l.prop(v, .number, scope) else try constProp(arena, .{ .number = 0 }, an.pos);
                const ep = if (an.get("end")) |v| try l.prop(v, .number, scope) else try constProp(arena, .{ .number = 360 }, an.pos);
                var pie = true;
                if (an.get("pie")) |v| {
                    if (v.data == .bool) pie = v.data.bool else try l.err(1103, v.pos, "pie must be true or false", .{});
                }
                if (sp != null and ep != null) layer.arc = .{ .start = sp.?, .end = ep.?, .pie = pie };
            };
            if (kind == .rect) if (m.get("radius")) |v| {
                layer.radius = try l.prop(v, .number, scope);
            };
        },
        else => {},
    }
    switch (kind) {
        .polygon => {
            if (m.get("closed")) |v| {
                if (v.data == .bool) layer.closed = v.data.bool else try l.err(1103, v.pos, "closed must be true or false", .{});
            }
            if (m.get("shape")) |sn| {
                if (m.get("points")) |pn| try l.err(1111, pn.pos, "a polygon needs exactly one of \"points\" and \"shape\"", .{});
                if (try l.expectObject(sn, "shape")) {
                    try l.checkFields(sn, &.{ "type", "count", "inner" }, "shape");
                    if (sn.get("type")) |tn| {
                        if (try l.enumField(ShapeKind, tn, "shape type")) |sk| {
                            var shape: Shape = .{ .kind = sk };
                            if (sn.get("count")) |v| shape.count = try l.prop(v, .number, scope);
                            if (sn.get("inner")) |v| shape.inner = try l.prop(v, .number, scope);
                            layer.shape = shape;
                        }
                    } else try l.err(1102, sn.pos, "shape needs a \"type\"", .{});
                }
            } else if (m.get("points")) |pn| {
                if (pn.data == .array) {
                    const min_points: usize = if (layer.closed) 3 else 2;
                    if (pn.data.array.len < min_points) try l.err(1109, pn.pos, "a {s} polygon needs at least {d} points, found {d}", .{ if (layer.closed) "closed" else "open", min_points, pn.data.array.len });
                    var pts: std.ArrayList(Point) = .empty;
                    for (pn.data.array) |*pt| {
                        if (pt.data != .array or pt.data.array.len != 2) {
                            try l.err(1103, pt.pos, "a point must be an array [x, y]", .{});
                            continue;
                        }
                        const px = try l.prop(&pt.data.array[0], .number, &sx);
                        const py = try l.prop(&pt.data.array[1], .number, &sy);
                        if (px != null and py != null) try pts.append(arena, .{ .x = px.?, .y = py.? });
                    }
                    layer.points = pts.items;
                } else try l.err(1103, pn.pos, "points must be an array of [x, y] pairs", .{});
            } else try l.err(1102, m.pos, "polygon layer '{s}' needs \"points\" or \"shape\"", .{id});
        },
        .text => {
            if (m.get("text")) |v| layer.text = try l.template(v, scope) else try l.err(1102, m.pos, "text layer '{s}' needs \"text\"", .{id});
            if (m.get("at")) |an| {
                if (try l.expectObject(an, "at")) {
                    try l.checkFields(an, &.{ "x", "y" }, "at");
                    const xn = an.get("x");
                    const yn = an.get("y");
                    if (xn == null or yn == null) try l.err(1102, an.pos, "at needs \"x\" and \"y\"", .{});
                    if (xn != null and yn != null) {
                        const px = try l.prop(xn.?, .number, &sx);
                        const py = try l.prop(yn.?, .number, &sy);
                        if (px != null and py != null) layer.at = .{ .x = px.?, .y = py.? };
                    }
                }
            } else try l.err(1102, m.pos, "text layer '{s}' needs \"at\"", .{id});
            if (m.get("font")) |v| if (try l.literalString(v, "font")) |s| {
                layer.font = s;
                if (!std.mem.eql(u8, s, "default") and d.findFont(s) == null) {
                    var names: std.ArrayList([]const u8) = .empty;
                    try names.append(arena, "default");
                    for (d.fonts) |f| try names.append(arena, f.name);
                    try l.errHint(4004, v.pos, try std.fmt.allocPrint(arena, "font '{s}' is not declared in \"fonts\"", .{s}), diag.suggest(arena, s, names.items));
                }
            };
            if (m.get("size")) |v| layer.size = try l.prop(v, .number, scope);
            if (m.get("color")) |v| layer.color = try l.prop(v, .color, scope);
            if (m.get("align")) |v| layer.alignment = (try l.enumField(Align, v, "align")) orelse .left;
            if (m.get("wrap")) |v| layer.wrap = try l.prop(v, .number, &sx);
            if (m.get("line_spacing")) |v| layer.line_spacing = try l.prop(v, .number, scope);
            if (m.get("max_lines")) |v| layer.max_lines = try l.prop(v, .number, scope);
            if (m.get("max_width")) |v| layer.max_width = try l.prop(v, .number, &sx);
            if (m.get("max_height")) |v| layer.max_height = try l.prop(v, .number, &sy);
            if (m.get("min_size")) |v| layer.min_size = try l.prop(v, .number, scope);
            if (m.get("shrink_group")) |v| layer.shrink_group = try l.literalString(v, "shrink_group");
        },
        .image => {
            if (m.get("src")) |v| layer.src = try l.template(v, scope) else try l.err(1102, m.pos, "image layer '{s}' needs \"src\"", .{id});
            if (m.get("fit")) |v| layer.fit = (try l.enumField(Fit, v, "fit")) orelse .fill;
            if (m.get("smoothing")) |v| layer.smoothing = (try l.enumField(Smoothing, v, "smoothing")) orelse .bilinear;
        },
        else => {},
    }
    return layer;
}

fn constProp(arena: Allocator, v: Value, pos: u32) Allocator.Error!?Prop {
    const node = try arena.create(expr.Node);
    node.* = .{ .start = 0, .end = 0, .data = switch (v) {
        .number => |x| .{ .number = x },
        .color => |c| .{ .color = c },
        .bool => |b| .{ .boolean = b },
        else => unreachable,
    } };
    return .{ .node = node, .pos = pos };
}

test "load a small design" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var diags = diag.List.init(a);
    const src =
        \\{
        \\  "format": 1,
        \\  "name": "t",
        \\  "canvas": { "width": 100, "height": 50 },
        \\  "params": { "level": { "type": "integer", "default": 3 } },
        \\  "layers": [
        \\    { "id": "bg", "type": "rect", "box": { "x": 0, "y": 0, "w": "100%", "h": "100%" }, "fill": "#FF0000" },
        \\    { "id": "t", "type": "text", "text": "Lv {level}", "at": { "x": "@bg.bounds.cx", "y": 5 }, "colour": "#000000" },
        \\    { "id": "t2", "type": "text", "extends": "t", "at": { "y": "lvl" } }
        \\  ]
        \\}
    ;
    const d = try load(a, &diags, "t.design.json", src);
    try std.testing.expectEqual(@as(usize, 2), diags.errorCount());
    try std.testing.expectEqual(@as(u16, 1101), diags.items.items[0].code);
    try std.testing.expectEqualStrings("/layers/1/colour", diags.items.items[0].path);
    try std.testing.expectEqualStrings("did you mean 'color'?", diags.items.items[0].hint.?);
    try std.testing.expectEqual(@as(u16, 3002), diags.items.items[1].code);
    try std.testing.expectEqualStrings("/layers/2/at/y", diags.items.items[1].path);
    try std.testing.expectEqual(@as(u32, 9), diags.items.items[1].line);
    try std.testing.expectEqual(@as(usize, 3), d.layers.len);
}

test "dividers and param groups" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var diags = diag.List.init(a);
    const src =
        \\{
        \\  "format": 1,
        \\  "name": "t",
        \\  "canvas": { "width": 100, "height": 50 },
        \\  "params": { "atk": { "type": "integer", "default": 3, "group": "Stats" } },
        \\  "layers": [
        \\    { "id": "stats", "type": "divider", "label": "Stats" },
        \\    { "id": "g", "type": "group", "layers": [
        \\      { "id": "inner", "type": "divider" },
        \\      { "id": "bg", "type": "rect", "box": { "x": 0, "y": 0, "w": 10, "h": 10 }, "fill": "#FF0000" }
        \\    ] },
        \\    { "id": "stats", "type": "divider", "fill": "#000000" },
        \\    { "id": "x", "type": "rect", "extends": "inner" },
        \\    { "id": "y", "type": "rect", "box": { "x": "@stats.box.x", "y": 0, "w": 1, "h": 1 } }
        \\  ]
        \\}
    ;
    const d = try load(a, &diags, "t.design.json", src);
    try std.testing.expectEqualStrings("Stats", d.params[0].group.?);
    try std.testing.expectEqual(@as(usize, 4), diags.errorCount());
    try std.testing.expectEqual(@as(u16, 1108), diags.items.items[0].code);
    try std.testing.expectEqual(@as(u16, 1101), diags.items.items[1].code);
    try std.testing.expectEqual(@as(u16, 1112), diags.items.items[2].code);
    try std.testing.expectEqual(@as(u16, 3002), diags.items.items[3].code);
    // Only the group and its rect are compiled.
    try std.testing.expectEqual(@as(usize, 3), d.layers.len);
}

test "list lookups by key and list counts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var diags = diag.List.init(a);
    const src =
        \\{
        \\  "format": 1,
        \\  "name": "t",
        \\  "canvas": { "width": 100, "height": 50 },
        \\  "params": {
        \\    "stats": { "type": "list", "item": { "name": "text", "value": "number" }, "default": [] },
        \\    "rows": { "type": "list", "item": { "label": "text", "x": "number", "y": "number" }, "default": [] },
        \\    "nums": { "type": "list", "item": { "n": "number" }, "default": [] }
        \\  },
        \\  "layers": [
        \\    { "id": "a", "type": "rect", "box": { "x": "stats.Speed * 2", "y": "stats['Power']", "w": "rows.top.x", "h": 1 } },
        \\    { "id": "b", "type": "rect", "repeat": { "count": "stats" }, "box": { "x": "stats[i].value", "y": 0, "w": 1, "h": 1 } },
        \\    { "id": "c", "type": "text", "text": "{stats.Speed}", "at": { "x": "nums.k", "y": 0 } },
        \\    { "id": "d", "type": "rect", "box": { "x": "stats[true]", "y": "Stats.speed", "w": 1, "h": 1 } }
        \\  ]
        \\}
    ;
    const d = try load(a, &diags, "t.design.json", src);
    _ = d;
    // nums has no text field; stats[true] is not a number or text; Stats is not a lowercase name.
    try std.testing.expectEqual(@as(usize, 3), diags.errorCount());
    try std.testing.expectEqualStrings("/layers/2/at/x", diags.items.items[0].path);
    try std.testing.expectEqualStrings("/layers/3/box/x", diags.items.items[1].path);
    try std.testing.expectEqualStrings("/layers/3/box/y", diags.items.items[2].path);
}
