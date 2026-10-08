//! The expression language (FORMAT.md section 6): lexer, Pratt parser, type
//! checker, evaluator and `{}` templates.

const std = @import("std");
const value = @import("value.zig");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const Value = value.Value;
const Type = value.Type;
const Color = value.Color;

pub const Axis = enum { none, x, y };
pub const Unit = enum { percent, vw, vh };
pub const LayerKind = enum { rect, ellipse, polygon, text, image, group };

pub const Builtin = enum {
    canvas_w,
    canvas_h,
    card_id,
    render_index,
    render_date,

    fn ty(b: Builtin) Type {
        return switch (b) {
            .canvas_w, .canvas_h, .render_index => .number,
            .card_id, .render_date => .text,
        };
    }
};

pub const Func = enum {
    min,
    max,
    clamp,
    abs,
    floor,
    ceil,
    round,
    len,
    upper,
    lower,
    trim,
    fmt,
    avg_color,
    mix,
    with_alpha,
    rgb,
    rgba,
};

pub const function_names = blk: {
    const fields = @typeInfo(Func).@"enum".fields;
    var names: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| names[i] = f.name;
    break :blk names;
};

pub const reserved_names = [_][]const u8{ "canvas", "render", "card", "true", "false", "and", "or", "not" };

pub fn isReserved(name: []const u8) bool {
    for (reserved_names) |r| if (std.mem.eql(u8, r, name)) return true;
    return std.meta.stringToEnum(Func, name) != null;
}

pub fn isIdent(s: []const u8) bool {
    if (s.len == 0) return false;
    if (!(std.ascii.isLower(s[0]) or s[0] == '_')) return false;
    for (s[1..]) |ch| {
        if (!(std.ascii.isLower(ch) or std.ascii.isDigit(ch) or ch == '_')) return false;
    }
    return true;
}

pub const BinOp = enum { @"or", @"and", eq, ne, lt, le, gt, ge, add, sub, mul, div, mod };

pub const Node = struct {
    start: u32,
    end: u32,
    ty: Type = .number,
    data: Data,

    pub const Data = union(enum) {
        number: f64,
        unit: struct { value: f64, unit: Unit },
        string: []const u8,
        boolean: bool,
        color: Color,
        name: []const u8,
        builtin: Builtin,
        layer_ref: struct { id: []const u8, path: []const []const u8 },
        field: struct { obj: *Node, name: []const u8, index: usize = 0 },
        index: struct { obj: *Node, idx: *Node },
        /// A list item found by its key (`stats.speed`, `stats["Speed"]`):
        /// the first item whose key field equals `key`; the value field when
        /// the list is a key/value list, else the whole item.
        lookup: struct { obj: *Node, key: *Node, key_field: usize, value_field: ?usize },
        call: struct { func: Func, args: []*Node },
        neg: *Node,
        not: *Node,
        binary: struct { op: BinOp, l: *Node, r: *Node },
        cond: struct { c: *Node, a: *Node, b: *Node },
    };
};

/// A problem found while parsing, checking or evaluating an expression.
pub const Problem = struct {
    code: u16,
    start: u32,
    end: u32,
    message: []const u8,
    hint: ?[]const u8 = null,
};

pub const Error = error{ Invalid, OutOfMemory };

// ------------------------------------------------------------------ lexer

const Tok = struct {
    kind: Kind,
    start: u32,
    end: u32,
    text: []const u8 = "",
    num: f64 = 0,
    unit: ?Unit = null,

    const Kind = enum { number, string, color, ref, name, op, end };
};

const Lexer = struct {
    arena: Allocator,
    src: []const u8,
    base: u32,
    i: usize = 0,
    problem: *?Problem,

    fn fail(lx: *Lexer, code: u16, start: usize, end: usize, msg: []const u8, hint: ?[]const u8) Error {
        lx.problem.* = .{
            .code = code,
            .start = lx.base + @as(u32, @intCast(start)),
            .end = lx.base + @as(u32, @intCast(end)),
            .message = msg,
            .hint = hint,
        };
        return error.Invalid;
    }

    fn all(lx: *Lexer) Error![]Tok {
        var toks: std.ArrayList(Tok) = .empty;
        while (true) {
            const t = try lx.next();
            try toks.append(lx.arena, t);
            if (t.kind == .end) return toks.items;
        }
    }

    fn tok(lx: *Lexer, kind: Tok.Kind, start: usize) Tok {
        return .{
            .kind = kind,
            .start = lx.base + @as(u32, @intCast(start)),
            .end = lx.base + @as(u32, @intCast(lx.i)),
            .text = lx.src[start..lx.i],
        };
    }

    fn next(lx: *Lexer) Error!Tok {
        const s = lx.src;
        while (lx.i < s.len and (s[lx.i] == ' ' or s[lx.i] == '\t' or s[lx.i] == '\n' or s[lx.i] == '\r')) lx.i += 1;
        const start = lx.i;
        if (lx.i >= s.len) return lx.tok(.end, start);
        const ch = s[lx.i];
        if (std.ascii.isDigit(ch)) {
            while (lx.i < s.len and std.ascii.isDigit(s[lx.i])) lx.i += 1;
            if (lx.i + 1 < s.len and s[lx.i] == '.' and std.ascii.isDigit(s[lx.i + 1])) {
                lx.i += 1;
                while (lx.i < s.len and std.ascii.isDigit(s[lx.i])) lx.i += 1;
            }
            const num = std.fmt.parseFloat(f64, s[start..lx.i]) catch unreachable;
            var unit: ?Unit = null;
            if (lx.i < s.len and s[lx.i] == '%') {
                unit = .percent;
                lx.i += 1;
            } else if (std.mem.startsWith(u8, s[lx.i..], "vw") or std.mem.startsWith(u8, s[lx.i..], "vh")) {
                const after = lx.i + 2;
                if (after >= s.len or !(std.ascii.isAlphanumeric(s[after]) or s[after] == '_')) {
                    unit = if (s[lx.i + 1] == 'w') .vw else .vh;
                    lx.i = after;
                }
            }
            if (lx.i < s.len and (std.ascii.isAlphabetic(s[lx.i]) or s[lx.i] == '_')) {
                var e = lx.i;
                while (e < s.len and std.ascii.isAlphanumeric(s[e])) e += 1;
                return lx.fail(3001, start, e, "unknown unit after a number", "valid units are %, vw and vh");
            }
            var t = lx.tok(.number, start);
            t.num = num;
            t.unit = unit;
            return t;
        }
        if (ch == '#') {
            lx.i += 1;
            while (lx.i < s.len and std.ascii.isAlphanumeric(s[lx.i])) lx.i += 1;
            const t = lx.tok(.color, start);
            if (Color.parseHex(t.text) == null) {
                return lx.fail(3001, start, lx.i, "invalid color literal", "use #RRGGBB, #RRGGBBAA, #RRRRGGGGBBBB or #RRRRGGGGBBBBAAAA");
            }
            return t;
        }
        if (ch == '\'' or ch == '"') {
            lx.i += 1;
            var out: std.ArrayList(u8) = .empty;
            while (lx.i < s.len and s[lx.i] != ch) {
                if (s[lx.i] == '\\' and lx.i + 1 < s.len) {
                    const e = s[lx.i + 1];
                    try out.append(lx.arena, switch (e) {
                        'n' => '\n',
                        '\\', '\'', '"' => e,
                        else => return lx.fail(3001, lx.i, lx.i + 2, "invalid escape in string", "valid escapes are \\' \\\" \\\\ \\n"),
                    });
                    lx.i += 2;
                } else {
                    try out.append(lx.arena, s[lx.i]);
                    lx.i += 1;
                }
            }
            if (lx.i >= s.len) return lx.fail(3001, start, s.len, "unterminated string", null);
            lx.i += 1;
            var t = lx.tok(.string, start);
            t.text = out.items;
            return t;
        }
        if (ch == '@') {
            lx.i += 1;
            const ns = lx.i;
            while (lx.i < s.len and (std.ascii.isLower(s[lx.i]) or std.ascii.isDigit(s[lx.i]) or s[lx.i] == '_')) lx.i += 1;
            if (lx.i == ns) return lx.fail(3001, start, lx.i + 1, "expected a layer id after '@'", null);
            var t = lx.tok(.ref, start);
            t.text = s[ns..lx.i];
            return t;
        }
        if (std.ascii.isAlphabetic(ch) or ch == '_') {
            while (lx.i < s.len and (std.ascii.isAlphanumeric(s[lx.i]) or s[lx.i] == '_')) lx.i += 1;
            // Mixed case is only allowed after '.', for list keys such as stats.Speed;
            // the parser checks every other name.
            const t = lx.tok(.name, start);
            const after_dot = start > 0 and s[start - 1] == '.';
            if (!after_dot and !isIdent(t.text)) {
                return lx.fail(3001, start, lx.i, "names are lowercase letters, digits and '_'", null);
            }
            return t;
        }
        const two = [_][]const u8{ "==", "!=", "<=", ">=" };
        for (two) |op| {
            if (std.mem.startsWith(u8, s[lx.i..], op)) {
                lx.i += 2;
                return lx.tok(.op, start);
            }
        }
        if (std.mem.indexOfScalar(u8, "+-*/%<>()[].,?:", ch) != null) {
            lx.i += 1;
            return lx.tok(.op, start);
        }
        if (ch == '=') return lx.fail(3001, start, start + 1, "unexpected '='", "use '==' to compare");
        if (ch == '&' or ch == '|') return lx.fail(3001, start, start + 1, "unexpected character", "use 'and' / 'or'");
        if (ch == '!') return lx.fail(3001, start, start + 1, "unexpected '!'", "use 'not'");
        return lx.fail(3001, start, start + 1, "unexpected character", null);
    }
};

// ------------------------------------------------------------------ parser

const Parser = struct {
    arena: Allocator,
    toks: []Tok,
    i: usize = 0,
    problem: *?Problem,

    fn peek(p: *Parser) Tok {
        return p.toks[p.i];
    }

    fn isOp(t: Tok, op: []const u8) bool {
        return t.kind == .op and std.mem.eql(u8, t.text, op);
    }

    fn fail(p: *Parser, code: u16, t: Tok, msg: []const u8, hint: ?[]const u8) Error {
        p.problem.* = .{ .code = code, .start = t.start, .end = t.end, .message = msg, .hint = hint };
        return error.Invalid;
    }

    fn expect(p: *Parser, op: []const u8) Error!Tok {
        const t = p.peek();
        if (!isOp(t, op)) {
            const msg = if (t.kind == .end)
                try std.fmt.allocPrint(p.arena, "expected '{s}' but the expression ended", .{op})
            else
                try std.fmt.allocPrint(p.arena, "expected '{s}' but found '{s}'", .{ op, t.text });
            return p.fail(3001, t, msg, null);
        }
        p.i += 1;
        return t;
    }

    fn node(p: *Parser, start: u32, end: u32, data: Node.Data) Error!*Node {
        const n = try p.arena.create(Node);
        n.* = .{ .start = start, .end = end, .data = data };
        return n;
    }

    fn binOp(t: Tok) ?struct { op: BinOp, bp: u8 } {
        if (t.kind == .name) {
            if (std.mem.eql(u8, t.text, "or")) return .{ .op = .@"or", .bp = 1 };
            if (std.mem.eql(u8, t.text, "and")) return .{ .op = .@"and", .bp = 2 };
            return null;
        }
        if (t.kind != .op) return null;
        const table = .{
            .{ "==", BinOp.eq, 3 }, .{ "!=", BinOp.ne, 3 },
            .{ "<", BinOp.lt, 4 },  .{ "<=", BinOp.le, 4 },
            .{ ">", BinOp.gt, 4 },  .{ ">=", BinOp.ge, 4 },
            .{ "+", BinOp.add, 5 }, .{ "-", BinOp.sub, 5 },
            .{ "*", BinOp.mul, 6 }, .{ "/", BinOp.div, 6 },
            .{ "%", BinOp.mod, 6 },
        };
        inline for (table) |e| {
            if (std.mem.eql(u8, t.text, e[0])) return .{ .op = e[1], .bp = e[2] };
        }
        return null;
    }

    fn expr(p: *Parser, min_bp: u8) Error!*Node {
        var left = try p.prefix();
        while (true) {
            const t = p.peek();
            if (isOp(t, "?") and min_bp == 0) {
                p.i += 1;
                const a = try p.expr(0);
                _ = try p.expect(":");
                const b = try p.expr(0);
                left = try p.node(left.start, b.end, .{ .cond = .{ .c = left, .a = a, .b = b } });
                continue;
            }
            const info = binOp(t) orelse return left;
            if (info.bp <= min_bp) return left;
            p.i += 1;
            const right = try p.expr(info.bp);
            left = try p.node(left.start, right.end, .{ .binary = .{ .op = info.op, .l = left, .r = right } });
        }
    }

    fn prefix(p: *Parser) Error!*Node {
        const t = p.peek();
        p.i += 1;
        switch (t.kind) {
            .end => return p.fail(3001, t, "expected a value but the expression ended", null),
            .number => {
                const n = if (t.unit) |u|
                    try p.node(t.start, t.end, .{ .unit = .{ .value = t.num, .unit = u } })
                else
                    try p.node(t.start, t.end, .{ .number = t.num });
                return p.postfix(n);
            },
            .string => return p.postfix(try p.node(t.start, t.end, .{ .string = t.text })),
            .color => return p.node(t.start, t.end, .{ .color = Color.parseHex(t.text).? }),
            .ref => {
                var path: std.ArrayList([]const u8) = .empty;
                var end = t.end;
                while (isOp(p.peek(), ".")) {
                    p.i += 1;
                    const f = p.peek();
                    if (f.kind != .name) return p.fail(3001, f, "expected a field name after '.'", null);
                    p.i += 1;
                    try path.append(p.arena, f.text);
                    end = f.end;
                }
                if (path.items.len == 0) {
                    return p.fail(3003, t, "a layer reference needs a field", try std.fmt.allocPrint(p.arena, "for example @{s}.bounds.cx", .{t.text}));
                }
                return p.node(t.start, end, .{ .layer_ref = .{ .id = t.text, .path = path.items } });
            },
            .name => {
                if (std.mem.eql(u8, t.text, "true")) return p.node(t.start, t.end, .{ .boolean = true });
                if (std.mem.eql(u8, t.text, "false")) return p.node(t.start, t.end, .{ .boolean = false });
                if (std.mem.eql(u8, t.text, "not")) {
                    const operand = try p.expr(7);
                    return p.node(t.start, operand.end, .{ .not = operand });
                }
                if (std.mem.eql(u8, t.text, "and") or std.mem.eql(u8, t.text, "or")) {
                    return p.fail(3001, t, try std.fmt.allocPrint(p.arena, "unexpected '{s}'", .{t.text}), null);
                }
                if (isOp(p.peek(), "(")) return p.postfix(try p.call(t));
                if (std.mem.eql(u8, t.text, "canvas") or std.mem.eql(u8, t.text, "render") or std.mem.eql(u8, t.text, "card")) {
                    return p.builtin(t);
                }
                return p.postfix(try p.node(t.start, t.end, .{ .name = t.text }));
            },
            .op => {
                if (isOp(t, "(")) {
                    const inner = try p.expr(0);
                    const close = try p.expect(")");
                    inner.start = t.start;
                    inner.end = close.end;
                    return p.postfix(inner);
                }
                if (isOp(t, "-")) {
                    const operand = try p.expr(7);
                    return p.node(t.start, operand.end, .{ .neg = operand });
                }
                if (isOp(t, ".")) return p.fail(3001, t, "unexpected '.'", "write numbers with a leading digit, e.g. 0.5");
                return p.fail(3001, t, try std.fmt.allocPrint(p.arena, "unexpected '{s}'", .{t.text}), null);
            },
        }
    }

    fn builtin(p: *Parser, t: Tok) Error!*Node {
        const fields: []const struct { []const u8, Builtin } = if (std.mem.eql(u8, t.text, "canvas"))
            &.{ .{ "w", .canvas_w }, .{ "h", .canvas_h } }
        else if (std.mem.eql(u8, t.text, "render"))
            &.{ .{ "index", .render_index }, .{ "date", .render_date } }
        else
            &.{.{ "id", .card_id }};
        var names: [2][]const u8 = undefined;
        for (fields, 0..) |f, i| names[i] = f[0];
        if (!isOp(p.peek(), ".")) {
            return p.fail(3003, t, try std.fmt.allocPrint(p.arena, "'{s}' needs a field", .{t.text}), try std.fmt.allocPrint(p.arena, "for example {s}.{s}", .{ t.text, fields[0][0] }));
        }
        p.i += 1;
        const f = p.peek();
        if (f.kind != .name) return p.fail(3001, f, "expected a field name after '.'", null);
        p.i += 1;
        for (fields) |e| {
            if (std.mem.eql(u8, e[0], f.text)) return p.postfix(try p.node(t.start, f.end, .{ .builtin = e[1] }));
        }
        return p.fail(3002, f, try std.fmt.allocPrint(p.arena, "'{s}' has no field '{s}'", .{ t.text, f.text }), diag.suggest(p.arena, f.text, names[0..fields.len]));
    }

    fn call(p: *Parser, t: Tok) Error!*Node {
        const func = std.meta.stringToEnum(Func, t.text) orelse {
            return p.fail(3002, t, try std.fmt.allocPrint(p.arena, "unknown function '{s}'", .{t.text}), diag.suggest(p.arena, t.text, &function_names));
        };
        _ = try p.expect("(");
        var args: std.ArrayList(*Node) = .empty;
        if (!isOp(p.peek(), ")")) {
            try args.append(p.arena, try p.expr(0));
            while (isOp(p.peek(), ",")) {
                p.i += 1;
                try args.append(p.arena, try p.expr(0));
            }
        }
        const close = try p.expect(")");
        return p.node(t.start, close.end, .{ .call = .{ .func = func, .args = args.items } });
    }

    fn postfix(p: *Parser, start_node: *Node) Error!*Node {
        var n = start_node;
        while (true) {
            const t = p.peek();
            if (isOp(t, ".")) {
                p.i += 1;
                const f = p.peek();
                if (f.kind != .name) return p.fail(3001, f, "expected a field name after '.'", null);
                p.i += 1;
                n = try p.node(n.start, f.end, .{ .field = .{ .obj = n, .name = f.text } });
            } else if (isOp(t, "[")) {
                p.i += 1;
                const idx = try p.expr(0);
                const close = try p.expect("]");
                n = try p.node(n.start, close.end, .{ .index = .{ .obj = n, .idx = idx } });
            } else return n;
        }
    }
};

/// Parses one expression. `base` is added to every span (used for templates).
pub fn parse(arena: Allocator, src: []const u8, base: u32, problem: *?Problem) Error!*Node {
    var lx: Lexer = .{ .arena = arena, .src = src, .base = base, .problem = problem };
    const toks = try lx.all();
    var p: Parser = .{ .arena = arena, .toks = toks, .problem = problem };
    const n = try p.expr(0);
    const t = p.peek();
    if (t.kind != .end) {
        return p.fail(3001, t, try std.fmt.allocPrint(arena, "unexpected '{s}'", .{t.text}), if (Parser.isOp(t, "%")) "the '%' unit must follow a number directly; the '%' operator needs operands on both sides" else null);
    }
    return n;
}

// ------------------------------------------------------------------ templates

pub const Template = struct {
    parts: []const Part,

    pub const Part = union(enum) {
        lit: []const u8,
        expr: *Node,
    };

    /// True when the template has no `{}` holes.
    pub fn isLiteral(t: Template) bool {
        for (t.parts) |part| if (part == .expr) return false;
        return true;
    }
};

pub fn parseTemplate(arena: Allocator, src: []const u8, problem: *?Problem) Error!Template {
    var parts: std.ArrayList(Template.Part) = .empty;
    var lit: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < src.len) {
        const ch = src[i];
        if ((ch == '{' or ch == '}') and i + 1 < src.len and src[i + 1] == ch) {
            try lit.append(arena, ch);
            i += 2;
            continue;
        }
        if (ch == '}') {
            problem.* = .{ .code = 3001, .start = @intCast(i), .end = @intCast(i + 1), .message = "stray '}' in text", .hint = "write '}}' for a literal brace" };
            return error.Invalid;
        }
        if (ch != '{') {
            try lit.append(arena, ch);
            i += 1;
            continue;
        }
        // Find the matching '}', skipping quoted strings.
        var j = i + 1;
        var quote: u8 = 0;
        while (j < src.len) : (j += 1) {
            const c = src[j];
            if (quote != 0) {
                if (c == '\\') j += 1 else if (c == quote) quote = 0;
            } else if (c == '\'' or c == '"') {
                quote = c;
            } else if (c == '}') break;
        }
        if (j >= src.len) {
            problem.* = .{ .code = 3001, .start = @intCast(i), .end = @intCast(src.len), .message = "unclosed '{' in text", .hint = "write '{{' for a literal brace" };
            return error.Invalid;
        }
        if (lit.items.len > 0) {
            try parts.append(arena, .{ .lit = lit.items });
            lit = .empty;
        }
        const inner = src[i + 1 .. j];
        if (std.mem.trim(u8, inner, " ").len == 0) {
            problem.* = .{ .code = 3001, .start = @intCast(i), .end = @intCast(j + 1), .message = "empty '{}' in text", .hint = "write '{{}}' for literal braces" };
            return error.Invalid;
        }
        try parts.append(arena, .{ .expr = try parse(arena, inner, @intCast(i + 1), problem) });
        i = j + 1;
    }
    if (lit.items.len > 0) try parts.append(arena, .{ .lit = lit.items });
    return .{ .parts = parts.items };
}

// ------------------------------------------------------------------ checker

pub const Symbol = struct {
    name: []const u8,
    ty: Type,
};

pub const LayerSymbol = struct {
    id: []const u8,
    kind: LayerKind,
    repeated: bool,
};

pub const Scope = struct {
    arena: Allocator,
    params: []const Symbol,
    locals: []const Symbol = &.{},
    /// null: layer references are not allowed here.
    layers: ?[]const LayerSymbol = &.{},
    axis: Axis = .none,
    /// false inside `canvas.width` / `canvas.height`.
    allow_units: bool = true,
    allow_builtins: bool = true,
};

pub const Checker = struct {
    scope: *const Scope,
    problem: *?Problem,

    fn fail(c: *Checker, code: u16, n: *const Node, msg: []const u8, hint: ?[]const u8) Error {
        c.problem.* = .{ .code = code, .start = n.start, .end = n.end, .message = msg, .hint = hint };
        return error.Invalid;
    }

    fn print(c: *Checker, comptime f: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(c.scope.arena, f, args);
    }

    pub fn check(c: *Checker, n: *Node) Error!Type {
        const t = try c.infer(n);
        n.ty = t;
        return t;
    }

    fn expectType(c: *Checker, n: *Node, want: Type, what: []const u8) Error!void {
        const t = try c.check(n);
        if (!t.eql(want)) {
            return c.fail(3003, n, try c.print("{s} needs a {s}, got a {s}", .{ what, want.name(), t.name() }), null);
        }
    }

    /// Turns `n` into a key lookup on a list: by its first text field, giving
    /// the other field for two-field (key/value) items, else the item.
    fn keyLookup(c: *Checker, n: *Node, obj: *Node, key: *Node, def: *const value.ItemDef) Error!Type {
        const kf = keyField(def) orelse {
            return c.fail(3003, n, "this list has no text field to look items up by", "use a position instead, e.g. list[0]");
        };
        const vf = valueField(def, kf);
        n.data = .{ .lookup = .{ .obj = obj, .key = key, .key_field = kf, .value_field = vf } };
        return if (vf) |v| def.types[v].toType() else .{ .item = def };
    }

    fn infer(c: *Checker, n: *Node) Error!Type {
        const s = c.scope;
        switch (n.data) {
            .number => return .number,
            .unit => |u| {
                if (!s.allow_units) return c.fail(3006, n, "units are not allowed here", "the canvas size cannot depend on itself");
                if (u.unit == .percent and s.axis == .none) {
                    return c.fail(3006, n, "'%' has no axis in this field", "use vw or vh for percent of the canvas width or height");
                }
                return .number;
            },
            .string => return .text,
            .boolean => return .bool,
            .color => return .color,
            .builtin => |b| {
                if (!s.allow_builtins) return c.fail(3002, n, "canvas, card and render are not available here", null);
                return b.ty();
            },
            .name => |name| {
                var i = s.locals.len;
                while (i > 0) {
                    i -= 1;
                    if (std.mem.eql(u8, s.locals[i].name, name)) return s.locals[i].ty;
                }
                for (s.params) |p| if (std.mem.eql(u8, p.name, name)) return p.ty;
                var names: std.ArrayList([]const u8) = .empty;
                for (s.locals) |l| try names.append(s.arena, l.name);
                for (s.params) |p| try names.append(s.arena, p.name);
                var hint = diag.suggest(s.arena, name, names.items);
                if (hint == null and s.layers != null) {
                    for (s.layers.?) |l| if (std.mem.eql(u8, l.id, name)) {
                        hint = try c.print("layer references start with '@', e.g. @{s}.bounds.cx", .{name});
                    };
                }
                return c.fail(3002, n, try c.print("unknown name '{s}'", .{name}), hint);
            },
            .layer_ref => |r| {
                const layers = s.layers orelse return c.fail(3002, n, "layer references are not allowed here", null);
                for (layers) |l| {
                    if (!std.mem.eql(u8, l.id, r.id)) continue;
                    if (l.repeated) return c.fail(3005, n, try c.print("layer '{s}' is repeated and cannot be referenced", .{r.id}), null);
                    return refType(l.kind, r.path) orelse {
                        const joined = try std.mem.join(s.arena, ".", r.path);
                        return c.fail(3002, n, try c.print("{s} layer '{s}' has no field '{s}'", .{ @tagName(l.kind), r.id, joined }), "try bounds.left, bounds.top, bounds.w, bounds.h, bounds.cx or bounds.cy");
                    };
                }
                var ids: std.ArrayList([]const u8) = .empty;
                for (layers) |l| try ids.append(s.arena, l.id);
                return c.fail(3002, n, try c.print("unknown layer '{s}'", .{r.id}), diag.suggest(s.arena, r.id, ids.items));
            },
            .field => |*f| {
                const t = try c.check(f.obj);
                switch (t) {
                    .list => |def| {
                        // stats.Speed: the item whose key is "Speed".
                        const key = try s.arena.create(Node);
                        key.* = .{ .start = n.start, .end = n.end, .ty = .text, .data = .{ .string = f.name } };
                        return c.keyLookup(n, f.obj, key, def);
                    },
                    .item => |def| {
                        f.index = def.find(f.name) orelse {
                            return c.fail(3002, n, try c.print("list item has no field '{s}'", .{f.name}), diag.suggest(s.arena, f.name, def.names));
                        };
                        return def.types[f.index].toType();
                    },
                    else => return c.fail(3003, n, try c.print("'.{s}' on a {s}", .{ f.name, t.name() }), null),
                }
            },
            .index => |ix| {
                const t = try c.check(ix.obj);
                const def = switch (t) {
                    .list => |d| d,
                    else => return c.fail(3003, n, try c.print("cannot index a {s}", .{t.name()}), null),
                };
                const it = try c.check(ix.idx);
                if (it == .text) return c.keyLookup(n, ix.obj, ix.idx, def);
                if (it != .number) return c.fail(3003, ix.idx, try c.print("a list index needs a number (position) or text (key), got a {s}", .{it.name()}), null);
                return .{ .item = def };
            },
            .lookup => |lk| {
                const t = try c.check(lk.obj);
                _ = try c.check(lk.key);
                return switch (t) {
                    .list => |def| if (lk.value_field) |v| def.types[v].toType() else .{ .item = def },
                    else => unreachable,
                };
            },
            .neg => |o| {
                try c.expectType(o, .number, "'-'");
                return .number;
            },
            .not => |o| {
                try c.expectType(o, .bool, "'not'");
                return .bool;
            },
            .binary => |b| {
                const lt = try c.check(b.l);
                const rt = try c.check(b.r);
                switch (b.op) {
                    .@"and", .@"or" => {
                        if (lt != .bool or rt != .bool) return c.fail(3003, n, try c.print("'{s}' needs bools, got {s} and {s}", .{ @tagName(b.op), lt.name(), rt.name() }), null);
                        return .bool;
                    },
                    .eq, .ne => {
                        if (!lt.comparable(rt)) return c.fail(3003, n, try c.print("cannot compare a {s} with a {s}", .{ lt.name(), rt.name() }), null);
                        return .bool;
                    },
                    else => {
                        if (lt != .number or rt != .number) {
                            const hint: ?[]const u8 = if (b.op == .add and (lt == .text or rt == .text)) "join text with a template, e.g. \"{a} {b}\"" else null;
                            return c.fail(3003, n, try c.print("'{s}' needs numbers, got {s} and {s}", .{ opText(b.op), lt.name(), rt.name() }), hint);
                        }
                        return switch (b.op) {
                            .lt, .le, .gt, .ge => .bool,
                            else => .number,
                        };
                    },
                }
            },
            .cond => |cd| {
                try c.expectType(cd.c, .bool, "the condition of '? :'");
                const a = try c.check(cd.a);
                const b = try c.check(cd.b);
                if (!a.eql(b)) return c.fail(3003, n, try c.print("the branches of '? :' differ: {s} and {s}", .{ a.name(), b.name() }), null);
                return a;
            },
            .call => |cl| return c.checkCall(n, cl.func, cl.args),
        }
    }

    fn checkCall(c: *Checker, n: *Node, func: Func, args: []*Node) Error!Type {
        const Sig = struct { min: usize, max: usize, args: []const ?Type, ret: Type };
        const num: ?Type = .number;
        const txt: ?Type = .text;
        const col: ?Type = .color;
        const sig: Sig = switch (func) {
            .min, .max => .{ .min = 2, .max = 64, .args = &.{num}, .ret = .number },
            .clamp => .{ .min = 3, .max = 3, .args = &.{ num, num, num }, .ret = .number },
            .abs, .floor, .ceil => .{ .min = 1, .max = 1, .args = &.{num}, .ret = .number },
            .round => .{ .min = 1, .max = 2, .args = &.{ num, num }, .ret = .number },
            .len => .{ .min = 1, .max = 1, .args = &.{null}, .ret = .number },
            .upper, .lower, .trim => .{ .min = 1, .max = 1, .args = &.{txt}, .ret = .text },
            .fmt => .{ .min = 2, .max = 2, .args = &.{ num, num }, .ret = .text },
            .avg_color => .{ .min = 1, .max = 1, .args = &.{null}, .ret = .color },
            .mix => .{ .min = 3, .max = 3, .args = &.{ col, col, num }, .ret = .color },
            .with_alpha => .{ .min = 2, .max = 2, .args = &.{ col, num }, .ret = .color },
            .rgb => .{ .min = 3, .max = 3, .args = &.{ num, num, num }, .ret = .color },
            .rgba => .{ .min = 4, .max = 4, .args = &.{ num, num, num, num }, .ret = .color },
        };
        if (args.len < sig.min or args.len > sig.max) {
            const msg = if (sig.min == sig.max)
                try c.print("{s}() takes {d} argument{s}, got {d}", .{ @tagName(func), sig.min, if (sig.min == 1) "" else "s", args.len })
            else
                try c.print("{s}() takes {d} to {d} arguments, got {d}", .{ @tagName(func), sig.min, sig.max, args.len });
            return c.fail(3003, n, msg, null);
        }
        for (args, 0..) |a, i| {
            const want = sig.args[@min(i, sig.args.len - 1)];
            const t = try c.check(a);
            if (want) |w| {
                if (!t.eql(w)) return c.fail(3003, a, try c.print("argument {d} of {s}() must be a {s}, got a {s}", .{ i + 1, @tagName(func), w.name(), t.name() }), null);
            } else switch (func) {
                .len => if (t != .list and t != .text) return c.fail(3003, a, try c.print("len() needs a list or text, got a {s}", .{t.name()}), null),
                .avg_color => if (t != .image and t != .text) return c.fail(3003, a, try c.print("avg_color() needs an image, got a {s}", .{t.name()}), null),
                else => unreachable,
            }
        }
        return sig.ret;
    }
};

pub fn opText(op: BinOp) []const u8 {
    return switch (op) {
        .@"or" => "or",
        .@"and" => "and",
        .eq => "==",
        .ne => "!=",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
    };
}

/// The type of `@layer.<path>`, or null when the layer kind has no such field.
pub fn refType(kind: LayerKind, path: []const []const u8) ?Type {
    const eq = std.mem.eql;
    if (path.len == 2) {
        const a = path[0];
        const b = path[1];
        if (eq(u8, a, "bounds")) {
            for ([_][]const u8{ "left", "top", "right", "bottom", "w", "h", "cx", "cy" }) |f| {
                if (eq(u8, b, f)) return .number;
            }
            return null;
        }
        if (eq(u8, a, "box") and (kind == .rect or kind == .ellipse or kind == .image)) {
            for ([_][]const u8{ "x", "y", "w", "h" }) |f| if (eq(u8, b, f)) return .number;
            return null;
        }
        if (eq(u8, a, "at") and kind == .text) {
            if (eq(u8, b, "x") or eq(u8, b, "y")) return .number;
            return null;
        }
        if (eq(u8, a, "stroke") and (kind == .rect or kind == .ellipse or kind == .polygon)) {
            if (eq(u8, b, "color")) return .color;
            if (eq(u8, b, "width")) return .number;
        }
        return null;
    }
    if (path.len != 1) return null;
    const f = path[0];
    if (eq(u8, f, "opacity") or eq(u8, f, "rotate")) return .number;
    if (eq(u8, f, "visible")) return .bool;
    return switch (kind) {
        .rect, .ellipse, .polygon => if (eq(u8, f, "fill")) .color else if (kind == .rect and eq(u8, f, "radius")) .number else null,
        .text => if (eq(u8, f, "color")) .color else if (eq(u8, f, "text")) .text else if (eq(u8, f, "size") or eq(u8, f, "line_spacing") or eq(u8, f, "wrap") or eq(u8, f, "max_lines")) .number else null,
        .image => if (eq(u8, f, "src")) .text else null,
        .group => null,
    };
}

/// The field list items are looked up by: the first text field.
pub fn keyField(def: *const value.ItemDef) ?usize {
    for (def.types, 0..) |t, i| if (t == .text) return i;
    return null;
}

/// For items with exactly a key and one other field, that other field.
pub fn valueField(def: *const value.ItemDef, key: usize) ?usize {
    if (def.types.len != 2) return null;
    return 1 - key;
}

pub fn checkTemplate(t: Template, scope: *const Scope, problem: *?Problem) Error!void {
    var c: Checker = .{ .scope = scope, .problem = problem };
    for (t.parts) |part| {
        const n = switch (part) {
            .expr => |e| e,
            .lit => continue,
        };
        const ty = try c.check(n);
        if (ty == .list or ty == .item) {
            return c.fail(3003, n, try c.print("cannot put a {s} into text", .{ty.name()}), "use a field, e.g. {item.name}");
        }
    }
}

// ------------------------------------------------------------------ evaluator

pub const EvalError = error{ Eval, OutOfMemory };

pub const Env = struct {
    arena: Allocator,
    canvas_w: f64,
    canvas_h: f64,
    card_id: []const u8,
    render_index: f64,
    render_date: []const u8,
    axis: Axis = .none,
    ctx: *anyopaque,
    /// Params and loop names.
    lookup: *const fn (ctx: *anyopaque, name: []const u8) ?Value,
    layerRef: *const fn (ctx: *anyopaque, id: []const u8, path: []const []const u8) EvalError!Value,
    avgColor: *const fn (ctx: *anyopaque, path: []const u8) EvalError!Color,
    problem: ?Problem = null,

    fn fail(env: *Env, code: u16, n: *const Node, msg: []const u8) EvalError {
        env.problem = .{ .code = code, .start = n.start, .end = n.end, .message = msg };
        return error.Eval;
    }

    pub fn eval(env: *Env, n: *const Node) EvalError!Value {
        switch (n.data) {
            .number => |x| return .{ .number = x },
            .unit => |u| return .{ .number = u.value / 100 * switch (u.unit) {
                .vw => env.canvas_w,
                .vh => env.canvas_h,
                .percent => switch (env.axis) {
                    .x => env.canvas_w,
                    .y => env.canvas_h,
                    .none => env.canvas_w,
                },
            } },
            .string => |s| return .{ .text = s },
            .boolean => |b| return .{ .bool = b },
            .color => |c| return .{ .color = c },
            .builtin => |b| return switch (b) {
                .canvas_w => .{ .number = env.canvas_w },
                .canvas_h => .{ .number = env.canvas_h },
                .card_id => .{ .text = env.card_id },
                .render_index => .{ .number = env.render_index },
                .render_date => .{ .text = env.render_date },
            },
            .name => |name| return env.lookup(env.ctx, name) orelse env.fail(3002, n, "unknown name"),
            .layer_ref => |r| return env.layerRef(env.ctx, r.id, r.path),
            .field => |f| {
                const obj = try env.eval(f.obj);
                return obj.item[f.index];
            },
            .lookup => |lk| {
                const list = (try env.eval(lk.obj)).list;
                const key = (try env.eval(lk.key)).text;
                for (list) |it| {
                    if (std.mem.eql(u8, it[lk.key_field].text, key)) return if (lk.value_field) |v| it[v] else .{ .item = it };
                }
                var keys: std.ArrayList([]const u8) = .empty;
                for (list) |it| try keys.append(env.arena, it[lk.key_field].text);
                const hint = diag.suggest(env.arena, key, keys.items);
                const known = try std.mem.join(env.arena, ", ", keys.items);
                return env.fail(3104, n, try std.fmt.allocPrint(env.arena, "no item with key '{s}' in this list{s}{s}{s}", .{
                    key,
                    if (hint) |h| try std.fmt.allocPrint(env.arena, " ({s})", .{h}) else "",
                    if (keys.items.len > 0) "; keys: " else " (the list is empty)",
                    known,
                }));
            },
            .index => |ix| {
                const list = (try env.eval(ix.obj)).list;
                const idx = (try env.eval(ix.idx)).number;
                const i = @floor(idx);
                if (!(i >= 0 and i < @as(f64, @floatFromInt(list.len)))) {
                    return env.fail(3102, n, try std.fmt.allocPrint(env.arena, "index {d} is out of range for a list of {d}", .{ i, list.len }));
                }
                return .{ .item = list[@intFromFloat(i)] };
            },
            .neg => |o| return .{ .number = -(try env.eval(o)).number },
            .not => |o| return .{ .bool = !(try env.eval(o)).bool },
            .binary => |b| {
                switch (b.op) {
                    .@"and" => return .{ .bool = (try env.eval(b.l)).bool and (try env.eval(b.r)).bool },
                    .@"or" => return .{ .bool = (try env.eval(b.l)).bool or (try env.eval(b.r)).bool },
                    .eq => return .{ .bool = (try env.eval(b.l)).eql(try env.eval(b.r)) },
                    .ne => return .{ .bool = !(try env.eval(b.l)).eql(try env.eval(b.r)) },
                    else => {},
                }
                const l = (try env.eval(b.l)).number;
                const r = (try env.eval(b.r)).number;
                return switch (b.op) {
                    .lt => .{ .bool = l < r },
                    .le => .{ .bool = l <= r },
                    .gt => .{ .bool = l > r },
                    .ge => .{ .bool = l >= r },
                    .add => .{ .number = l + r },
                    .sub => .{ .number = l - r },
                    .mul => .{ .number = l * r },
                    .div => if (r == 0) env.fail(3103, n, "division by zero") else .{ .number = l / r },
                    .mod => if (r == 0) env.fail(3103, n, "division by zero") else .{ .number = @rem(l, r) },
                    else => unreachable,
                };
            },
            .cond => |cd| return if ((try env.eval(cd.c)).bool) env.eval(cd.a) else env.eval(cd.b),
            .call => |cl| return env.call(cl.func, cl.args),
        }
    }

    fn num(env: *Env, n: *const Node) EvalError!f64 {
        return (try env.eval(n)).number;
    }

    fn call(env: *Env, func: Func, args: []*Node) EvalError!Value {
        switch (func) {
            .min, .max => {
                var acc = try env.num(args[0]);
                for (args[1..]) |a| {
                    const v = try env.num(a);
                    acc = if (func == .min) @min(acc, v) else @max(acc, v);
                }
                return .{ .number = acc };
            },
            .clamp => {
                const v = try env.num(args[0]);
                const lo = try env.num(args[1]);
                const hi = try env.num(args[2]);
                return .{ .number = @max(lo, @min(hi, v)) };
            },
            .abs => return .{ .number = @abs(try env.num(args[0])) },
            .floor => return .{ .number = @floor(try env.num(args[0])) },
            .ceil => return .{ .number = @ceil(try env.num(args[0])) },
            .round => {
                const v = try env.num(args[0]);
                const digits = if (args.len > 1) @round(try env.num(args[1])) else 0;
                const f = std.math.pow(f64, 10, @max(-15, @min(15, digits)));
                return .{ .number = @round(v * f) / f };
            },
            .len => return switch (try env.eval(args[0])) {
                .list => |l| .{ .number = @floatFromInt(l.len) },
                .text => |t| .{ .number = @floatFromInt(std.unicode.utf8CountCodepoints(t) catch t.len) },
                else => unreachable,
            },
            .upper, .lower => {
                const t = (try env.eval(args[0])).text;
                const out = try env.arena.alloc(u8, t.len);
                for (t, 0..) |ch, i| out[i] = if (func == .upper) std.ascii.toUpper(ch) else std.ascii.toLower(ch);
                return .{ .text = out };
            },
            .trim => return .{ .text = std.mem.trim(u8, (try env.eval(args[0])).text, " \t\n\r") },
            .fmt => {
                const v = try env.num(args[0]);
                const d: usize = @intFromFloat(@max(0, @min(15, @round(try env.num(args[1])))));
                return .{ .text = try std.fmt.allocPrint(env.arena, "{d:.[1]}", .{ v, d }) };
            },
            .avg_color => {
                const path = switch (try env.eval(args[0])) {
                    .image, .text => |p| p,
                    else => unreachable,
                };
                return .{ .color = try env.avgColor(env.ctx, path) };
            },
            .mix => {
                const a = (try env.eval(args[0])).color;
                const b = (try env.eval(args[1])).color;
                const t = std.math.clamp(try env.num(args[2]), 0, 1);
                return .{ .color = .{
                    .r = lerp16(a.r, b.r, t),
                    .g = lerp16(a.g, b.g, t),
                    .b = lerp16(a.b, b.b, t),
                    .a = lerp16(a.a, b.a, t),
                } };
            },
            .with_alpha => {
                var c = (try env.eval(args[0])).color;
                c.a = unit16(try env.num(args[1]));
                return .{ .color = c };
            },
            .rgb, .rgba => {
                var c: Color = .{
                    .r = chan16(try env.num(args[0])),
                    .g = chan16(try env.num(args[1])),
                    .b = chan16(try env.num(args[2])),
                    .a = 65535,
                };
                if (func == .rgba) c.a = unit16(try env.num(args[3]));
                return .{ .color = c };
            },
        }
    }

    /// Expands a template to text.
    pub fn template(env: *Env, t: Template) EvalError![]const u8 {
        if (t.parts.len == 1 and t.parts[0] == .lit) return t.parts[0].lit;
        var aw: std.Io.Writer.Allocating = .init(env.arena);
        const w = &aw.writer;
        for (t.parts) |part| {
            switch (part) {
                .lit => |s| w.writeAll(s) catch return error.OutOfMemory,
                .expr => |e| {
                    switch (try env.eval(e)) {
                        .number => |x| value.writeNumber(w, x) catch return error.OutOfMemory,
                        .bool => |b| w.writeAll(if (b) "true" else "false") catch return error.OutOfMemory,
                        .text, .image => |s| w.writeAll(s) catch return error.OutOfMemory,
                        .color => |c| {
                            var buf: [9]u8 = undefined;
                            w.writeAll(c.hex8String(&buf)) catch return error.OutOfMemory;
                        },
                        .list, .item => unreachable,
                    }
                },
            }
        }
        return aw.written();
    }
};

fn lerp16(a: u16, b: u16, t: f64) u16 {
    const v = @as(f64, @floatFromInt(a)) + (@as(f64, @floatFromInt(b)) - @as(f64, @floatFromInt(a))) * t;
    return @intFromFloat(std.math.clamp(@round(v), 0, 65535));
}

fn unit16(x: f64) u16 {
    return @intFromFloat(@round(std.math.clamp(x, 0, 1) * 65535));
}

fn chan16(x: f64) u16 {
    return @intFromFloat(@round(std.math.clamp(x, 0, 255) * 257));
}

// ------------------------------------------------------------------ tests

const testing = std.testing;

fn testCheck(arena: Allocator, src: []const u8, scope: *const Scope) !Type {
    var problem: ?Problem = null;
    const n = try parse(arena, src, 0, &problem);
    var c: Checker = .{ .scope = scope, .problem = &problem };
    return c.check(n);
}

test "parse and check" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const scope: Scope = .{
        .arena = a,
        .params = &.{ .{ .name = "level", .ty = .number }, .{ .name = "edition", .ty = .text } },
        .layers = &.{.{ .id = "bg", .kind = .rect, .repeated = false }},
        .axis = .x,
    };
    try testing.expect((try testCheck(a, "100% - 2 * level", &scope)) == .number);
    try testing.expect((try testCheck(a, "edition == '1  Edition'", &scope)) == .bool);
    try testing.expect((try testCheck(a, "@bg.bounds.cx + 1", &scope)) == .number);
    try testing.expect((try testCheck(a, "level > 3 ? #FF0000 : rgb(0, 0, 255)", &scope)) == .color);

    var problem: ?Problem = null;
    const n = try parse(a, "lvl + 1", 0, &problem);
    var c: Checker = .{ .scope = &scope, .problem = &problem };
    try testing.expectError(error.Invalid, c.check(n));
    try testing.expectEqual(@as(u16, 3002), problem.?.code);
    try testing.expectEqualStrings("did you mean 'level'?", problem.?.hint.?);

    problem = null;
    const n2 = try parse(a, "'5' + 1", 0, &problem);
    try testing.expectError(error.Invalid, c.check(n2));
    try testing.expectEqual(@as(u16, 3003), problem.?.code);

    problem = null;
    try testing.expectError(error.Invalid, parse(a, "(1 + 2", 0, &problem));
    try testing.expectEqual(@as(u16, 3001), problem.?.code);
}

fn testLookup(_: *anyopaque, name: []const u8) ?Value {
    if (std.mem.eql(u8, name, "level")) return .{ .number = 4 };
    return null;
}

fn testRef(_: *anyopaque, _: []const u8, _: []const []const u8) EvalError!Value {
    return .{ .number = 10 };
}

fn testAvg(_: *anyopaque, _: []const u8) EvalError!Color {
    return Color.black;
}

test "evaluate" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var dummy: u8 = 0;
    var env: Env = .{
        .arena = a,
        .canvas_w = 200,
        .canvas_h = 400,
        .card_id = "001",
        .render_index = 0,
        .render_date = "2026-10-07",
        .axis = .y,
        .ctx = &dummy,
        .lookup = testLookup,
        .layerRef = testRef,
        .avgColor = testAvg,
    };
    var problem: ?Problem = null;
    try testing.expectEqual(@as(f64, 192), (try env.eval(try parse(a, "50% - 2 * level", 0, &problem))).number);
    try testing.expectEqual(@as(f64, 20), (try env.eval(try parse(a, "10vw", 0, &problem))).number);
    const t = try parseTemplate(a, "Lv {level} {{x}} {fmt(0.5, 2)} {card.id}", &problem);
    try testing.expectEqualStrings("Lv 4 {x} 0.50 001", try env.template(t));
    try testing.expectError(error.Eval, env.eval(try parse(a, "1 / (level - 4)", 0, &problem)));
    try testing.expectEqual(@as(u16, 3103), env.problem.?.code);
}
