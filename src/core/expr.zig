//! The expression language (FORMAT.md section 6): lexer, Pratt parser, type
//! checker, evaluator and `{}` templates.

const std = @import("std");
const value = @import("value.zig");
const diag = @import("diag.zig");
const Allocator = std.mem.Allocator;
const Value = value.Value;
const Type = value.Type;
const Color = value.Color;
const bmath = @import("builtins/math.zig");
const btext = @import("builtins/text.zig");
const blist = @import("builtins/list.zig");
const bdate = @import("builtins/date.zig");
const bcolor = @import("builtins/color.zig");
const brand = @import("builtins/rand.zig");

pub const Axis = enum { none, x, y };
pub const Unit = enum { percent, vw, vh };
pub const LayerKind = enum { rect, ellipse, polygon, text, image, group };

pub const Builtin = enum {
    canvas_w,
    canvas_h,
    card_id,
    render_index,
    render_date,
    render_time,
    render_now,

    pub fn ty(b: Builtin) Type {
        return switch (b) {
            .canvas_w, .canvas_h, .render_index => .number,
            .card_id, .render_date, .render_time, .render_now => .text,
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
    match,
    // Numbers.
    sqrt,
    pow,
    sign,
    sin,
    cos,
    tan,
    asin,
    acos,
    atan2,
    lerp,
    remap,
    wrap,
    // Text.
    contains,
    starts_with,
    ends_with,
    replace,
    slice,
    pad_start,
    repeat,
    title_case,
    roman,
    part,
    // Lists.
    has,
    get,
    index_of,
    sum,
    avg,
    count,
    join,
    last,
    // Dates and times.
    date_fmt,
    year,
    month,
    day,
    weekday,
    hour,
    minute,
    add_days,
    add_hours,
    days_between,
    // Colours.
    hsl,
    hsla,
    lighten,
    darken,
    luminance,
    readable,
    // Seeded random.
    rand,
    rand_int,
    pick,
};

pub const function_names = blk: {
    const fields = @typeInfo(Func).@"enum".fields;
    var names: [fields.len][]const u8 = undefined;
    for (fields, 0..) |f, i| names[i] = f.name;
    break :blk names;
};

pub const reserved_names = [_][]const u8{ "canvas", "render", "card", "true", "false", "and", "or", "not", "in" };

/// A reserved word: never a name. Built-in function names are not reserved;
/// a design function with one hides the built-in (warning 1113).
pub fn isReserved(name: []const u8) bool {
    for (reserved_names) |r| if (std.mem.eql(u8, r, name)) return true;
    return false;
}

pub fn isFunction(name: []const u8) bool {
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
        /// A param, loop name, function argument or design constant; the
        /// checker sets `konst` when the name is a constant.
        name: struct { text: []const u8, konst: ?usize = null },
        builtin: Builtin,
        /// `@id.path` or `@id[index].path` (one iteration of a repeated layer).
        layer_ref: struct { id: []const u8, path: []const []const u8, index: ?*Node = null },
        /// `obj.name`: a field of a list item (`index`), or a key lookup on a
        /// list (`key`, set by the checker; `stats.Speed`).
        field: struct { obj: *Node, name: []const u8, index: usize = 0, key: ?KeyLookup = null },
        /// `obj[idx]`: an item by position, or by key when `idx` is text
        /// (`key`, set by the checker; `stats["Speed"]`).
        index: struct { obj: *Node, idx: *Node, key: ?KeyLookup = null },
        call: Call,
        /// A call to a design function (`functions`); `index` is set by the checker.
        ucall: struct { name: []const u8, args: []*Node, index: usize = 0 },
        neg: *Node,
        not: *Node,
        binary: struct { op: BinOp, l: *Node, r: *Node },
        cond: struct { c: *Node, a: *Node, b: *Node },
        /// `v in [items...]`: true when some item equals `v`.
        in_list: struct { v: *Node, items: []*Node },
        /// `( inner )`, kept so the tree maps back to the source text.
        paren: *Node,
        /// Text that does not parse (only from `parseTolerant`), with the
        /// part that did parse, if any.
        err: ?*Node,
    };

    /// Finds list items by key: the first item whose `key_field` equals the
    /// key; gives the `value_field` when the list is a key/value list, else
    /// the whole item.
    pub const KeyLookup = struct { key_field: usize, value_field: ?usize };
};

/// A built-in call. List functions get `field` (the item field they read)
/// and `lk` (key lookup) from the checker.
pub const Call = struct {
    func: Func,
    args: []*Node,
    field: usize = 0,
    lk: ?Node.KeyLookup = null,
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

/// Problems collected by the tolerant parser, at most `max`.
const Diags = struct {
    arena: Allocator,
    list: std.ArrayList(Problem) = .empty,
    max: usize,
    truncated: bool = false,

    fn add(d: *Diags, pr: Problem) Allocator.Error!void {
        for (d.list.items) |q| if (q.start == pr.start) return;
        if (d.list.items.len >= d.max) {
            d.truncated = true;
            return;
        }
        try d.list.append(d.arena, pr);
    }
};

/// Nesting deeper than this is an error (it protects the stack).
const max_depth = 200;

// ------------------------------------------------------------------ lexer

const Tok = struct {
    kind: Kind,
    start: u32,
    end: u32,
    text: []const u8 = "",
    num: f64 = 0,
    unit: ?Unit = null,

    const Kind = enum { number, string, color, ref, name, op, bad, end };
};

const Lexer = struct {
    arena: Allocator,
    src: []const u8,
    base: u32,
    i: usize = 0,
    problem: *?Problem,
    /// Tolerant mode: a bad token is reported here and lexing goes on.
    diags: ?*Diags = null,

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
            const before = lx.i;
            const t = lx.next() catch |e| switch (e) {
                error.Invalid => {
                    const d = lx.diags orelse return e;
                    const pr = lx.problem.*.?;
                    lx.problem.* = null;
                    try d.add(pr);
                    // Skip the bad text; always move forward.
                    lx.i = @min(@max(pr.end - lx.base, before + 1), lx.src.len);
                    try toks.append(lx.arena, .{ .kind = .bad, .start = pr.start, .end = lx.base + @as(u32, @intCast(lx.i)), .text = lx.src[pr.start - lx.base .. lx.i] });
                    continue;
                },
                else => return e,
            };
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
            if (lx.i == ns) return lx.fail(3001, start, @min(lx.i + 1, s.len), "expected a layer id after '@'", null);
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
    /// Tolerant mode: problems are collected here and the bad part becomes
    /// an `err` node, so there is always a tree.
    diags: ?*Diags = null,
    depth: u32 = 0,

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
            if (p.diags) |d| {
                // Report it and go on as if it were there.
                try d.add(.{ .code = 3001, .start = t.start, .end = t.end, .message = msg });
                return .{ .kind = .op, .start = t.start, .end = t.start, .text = op };
            }
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

    /// A problem where a value was expected. Strict mode fails; tolerant
    /// mode reports it and gives an `err` node over [start, end) that keeps
    /// `child`, the part before the problem that did parse.
    fn bad(p: *Parser, code: u16, t: Tok, msg: []const u8, hint: ?[]const u8, start: u32, child: ?*Node) Error!*Node {
        const d = p.diags orelse return p.fail(code, t, msg, hint);
        try d.add(.{ .code = code, .start = t.start, .end = t.end, .message = msg, .hint = hint });
        return p.node(@min(start, t.start), @max(t.end, if (child) |c| c.end else t.end), .{ .err = child });
    }

    /// True for tokens a tolerant parse must not swallow as a bad value:
    /// they close or separate an enclosing construct.
    fn isCloser(t: Tok) bool {
        return t.kind == .end or isOp(t, ")") or isOp(t, "]") or isOp(t, ",") or isOp(t, ":");
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
            if (t.kind == .name and std.mem.eql(u8, t.text, "in")) {
                if (3 <= min_bp) return left;
                p.i += 1;
                left = try p.inList(left);
                continue;
            }
            const info = binOp(t) orelse return left;
            if (info.bp <= min_bp) return left;
            p.i += 1;
            const right = try p.expr(info.bp);
            left = try p.node(left.start, right.end, .{ .binary = .{ .op = info.op, .l = left, .r = right } });
        }
    }

    /// The bracket list after `in`: `[e1, e2, ...]`, one or more items.
    fn inList(p: *Parser, v: *Node) Error!*Node {
        const open = p.peek();
        if (!isOp(open, "[")) return p.bad(3001, open, "expected '[' after 'in'", "list the values, e.g. k in ['a', 'b']", v.start, v);
        p.i += 1;
        if (isOp(p.peek(), "]")) {
            const close = p.peek();
            const n = try p.bad(3001, close, "the list after 'in' is empty", null, v.start, v);
            p.i += 1;
            return n;
        }
        var items: std.ArrayList(*Node) = .empty;
        try items.append(p.arena, try p.expr(0));
        while (isOp(p.peek(), ",")) {
            p.i += 1;
            try items.append(p.arena, try p.expr(0));
        }
        const close = try p.expect("]");
        return p.node(v.start, close.end, .{ .in_list = .{ .v = v, .items = items.items } });
    }

    fn prefix(p: *Parser) Error!*Node {
        const t = p.peek();
        if (p.depth >= max_depth) {
            if (!isCloser(t)) p.i += 1;
            return p.bad(3001, t, "the expression is nested too deeply", null, t.start, null);
        }
        p.depth += 1;
        defer p.depth -= 1;
        if (p.diags != null and isCloser(t)) {
            // Leave the closer to the construct it belongs to.
            const msg = if (t.kind == .end) "expected a value but the expression ended" else try std.fmt.allocPrint(p.arena, "expected a value before '{s}'", .{t.text});
            const z: Tok = .{ .kind = t.kind, .start = t.start, .end = t.start, .text = t.text };
            return p.bad(3001, z, msg, null, t.start, null);
        }
        p.i += 1;
        switch (t.kind) {
            .end => return p.fail(3001, t, "expected a value but the expression ended", null),
            // Already reported by the lexer.
            .bad => return p.node(t.start, t.end, .{ .err = null }),
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
                var index: ?*Node = null;
                if (isOp(p.peek(), "[")) {
                    p.i += 1;
                    index = try p.expr(0);
                    end = (try p.expect("]")).end;
                }
                while (isOp(p.peek(), ".")) {
                    p.i += 1;
                    const f = p.peek();
                    if (f.kind != .name) return p.bad(3001, f, "expected a field name after '.'", null, t.start, null);
                    p.i += 1;
                    try path.append(p.arena, f.text);
                    end = f.end;
                }
                if (path.items.len == 0) {
                    return p.bad(3003, t, "a layer reference needs a field", try std.fmt.allocPrint(p.arena, "for example @{s}.bounds.cx", .{t.text}), t.start, null);
                }
                return p.node(t.start, end, .{ .layer_ref = .{ .id = t.text, .path = path.items, .index = index } });
            },
            .name => {
                if (std.mem.eql(u8, t.text, "true")) return p.node(t.start, t.end, .{ .boolean = true });
                if (std.mem.eql(u8, t.text, "false")) return p.node(t.start, t.end, .{ .boolean = false });
                if (std.mem.eql(u8, t.text, "not")) {
                    const operand = try p.expr(7);
                    return p.node(t.start, operand.end, .{ .not = operand });
                }
                if (std.mem.eql(u8, t.text, "and") or std.mem.eql(u8, t.text, "or") or std.mem.eql(u8, t.text, "in")) {
                    return p.bad(3001, t, try std.fmt.allocPrint(p.arena, "unexpected '{s}'", .{t.text}), null, t.start, null);
                }
                if (isOp(p.peek(), "(")) return p.postfix(try p.call(t));
                if (std.mem.eql(u8, t.text, "canvas") or std.mem.eql(u8, t.text, "render") or std.mem.eql(u8, t.text, "card")) {
                    return p.builtin(t);
                }
                return p.postfix(try p.node(t.start, t.end, .{ .name = .{ .text = t.text } }));
            },
            .op => {
                if (isOp(t, "(")) {
                    const inner = try p.expr(0);
                    const close = try p.expect(")");
                    return p.postfix(try p.node(t.start, close.end, .{ .paren = inner }));
                }
                if (isOp(t, "-")) {
                    const operand = try p.expr(7);
                    return p.node(t.start, operand.end, .{ .neg = operand });
                }
                if (isOp(t, ".")) return p.bad(3001, t, "unexpected '.'", "write numbers with a leading digit, e.g. 0.5", t.start, null);
                return p.bad(3001, t, try std.fmt.allocPrint(p.arena, "unexpected '{s}'", .{t.text}), null, t.start, null);
            },
        }
    }

    fn builtin(p: *Parser, t: Tok) Error!*Node {
        const fields: []const struct { []const u8, Builtin } = if (std.mem.eql(u8, t.text, "canvas"))
            &.{ .{ "w", .canvas_w }, .{ "h", .canvas_h } }
        else if (std.mem.eql(u8, t.text, "render"))
            &.{ .{ "index", .render_index }, .{ "date", .render_date }, .{ "time", .render_time }, .{ "now", .render_now } }
        else
            &.{.{ "id", .card_id }};
        var names: [4][]const u8 = undefined;
        for (fields, 0..) |f, i| names[i] = f[0];
        if (!isOp(p.peek(), ".")) {
            return p.bad(3003, t, try std.fmt.allocPrint(p.arena, "'{s}' needs a field", .{t.text}), try std.fmt.allocPrint(p.arena, "for example {s}.{s}", .{ t.text, fields[0][0] }), t.start, null);
        }
        p.i += 1;
        const f = p.peek();
        if (f.kind != .name) return p.bad(3001, f, "expected a field name after '.'", null, t.start, null);
        p.i += 1;
        for (fields) |e| {
            if (std.mem.eql(u8, e[0], f.text)) return p.postfix(try p.node(t.start, f.end, .{ .builtin = e[1] }));
        }
        return p.bad(3002, f, try std.fmt.allocPrint(p.arena, "'{s}' has no field '{s}'", .{ t.text, f.text }), diag.suggest(p.arena, f.text, names[0..fields.len]), t.start, null);
    }

    fn call(p: *Parser, t: Tok) Error!*Node {
        const func = std.meta.stringToEnum(Func, t.text);
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
        if (func) |f| return p.node(t.start, close.end, .{ .call = .{ .func = f, .args = args.items } });
        return p.node(t.start, close.end, .{ .ucall = .{ .name = t.text, .args = args.items } });
    }

    fn postfix(p: *Parser, start_node: *Node) Error!*Node {
        var n = start_node;
        while (true) {
            const t = p.peek();
            if (isOp(t, ".")) {
                p.i += 1;
                const f = p.peek();
                if (f.kind != .name) return p.bad(3001, f, "expected a field name after '.'", null, n.start, n);
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

/// A token for highlighting: the lexer's view of the text, never failing.
pub const Token = struct {
    kind: Kind,
    start: u32,
    end: u32,

    pub const Kind = enum { number, unit, string, color, ref, name, keyword, op, punct, bad };
};

/// The tokens of an expression (spans start at `base`); bad text becomes
/// `bad` tokens and lexing goes on.
pub fn tokenize(arena: Allocator, src: []const u8, base: u32) Allocator.Error![]const Token {
    var diags: Diags = .{ .arena = arena, .max = 0 };
    var problem: ?Problem = null;
    var lx: Lexer = .{ .arena = arena, .src = src, .base = base, .problem = &problem, .diags = &diags };
    const toks = lx.all() catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => unreachable, // tolerant lexing does not fail
    };
    var out: std.ArrayList(Token) = .empty;
    for (toks) |t| {
        const kind: Token.Kind = switch (t.kind) {
            .end => continue,
            .number => {
                // `10%` is one token for the parser, two for highlighting.
                const ulen: u32 = if (t.unit) |u| (if (u == .percent) 1 else 2) else 0;
                try out.append(arena, .{ .kind = .number, .start = t.start, .end = t.end - ulen });
                if (ulen > 0) try out.append(arena, .{ .kind = .unit, .start = t.end - ulen, .end = t.end });
                continue;
            },
            .string => .string,
            .color => .color,
            .ref => .ref,
            .bad => .bad,
            .name => if (isKeyword(t.text)) .keyword else .name,
            .op => if (std.mem.indexOfScalar(u8, "()[],.", t.text[0]) != null) .punct else .op,
        };
        try out.append(arena, .{ .kind = kind, .start = t.start, .end = t.end });
    }
    return out.items;
}

fn isKeyword(s: []const u8) bool {
    for ([_][]const u8{ "and", "or", "not", "in", "true", "false" }) |k| if (std.mem.eql(u8, s, k)) return true;
    return false;
}

/// The result of `parseTolerant`: always a tree, with `err` nodes where the
/// text does not parse, and the problems found (at most `max`).
pub const Parsed = struct {
    root: *Node,
    problems: []const Problem,
    /// More problems were found than were kept.
    truncated: bool = false,
};

/// Parses one expression without stopping at the first problem: for
/// editors, which need a tree while the user is typing.
pub fn parseTolerant(arena: Allocator, src: []const u8, base: u32, max: usize) Allocator.Error!Parsed {
    var diags: Diags = .{ .arena = arena, .max = max };
    const root = tolerantRoot(arena, src, base, &diags) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // Tolerant parsing reports instead of failing; keep a tree anyway.
        error.Invalid => blk: {
            const n = try arena.create(Node);
            n.* = .{ .start = base, .end = base + @as(u32, @intCast(src.len)), .data = .{ .err = null } };
            break :blk n;
        },
    };
    return .{ .root = root, .problems = diags.list.items, .truncated = diags.truncated };
}

fn tolerantRoot(arena: Allocator, src: []const u8, base: u32, diags: *Diags) Error!*Node {
    var problem: ?Problem = null;
    var lx: Lexer = .{ .arena = arena, .src = src, .base = base, .problem = &problem, .diags = diags };
    const toks = try lx.all();
    var p: Parser = .{ .arena = arena, .toks = toks, .problem = &problem, .diags = diags };
    const n = try p.expr(0);
    const t = p.peek();
    if (t.kind == .end) return n;
    // Text after a complete expression: one error node over all of it.
    try diags.add(.{ .code = 3001, .start = t.start, .end = t.end, .message = try std.fmt.allocPrint(arena, "unexpected '{s}'", .{t.text}) });
    return p.node(n.start, toks[toks.len - 1].start, .{ .err = n });
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

/// A template split for an editor: literal text, `{{`/`}}` escapes and
/// `{...}` holes, each with its span; every hole parsed tolerantly.
pub const TemplateParsed = struct {
    pieces: []const Piece,
    problems: []const Problem,
    truncated: bool = false,

    pub const Piece = struct {
        kind: enum { lit, escape, hole },
        start: u32,
        end: u32,
        /// The hole's expression (spans index into the whole template).
        root: ?*Node = null,
    };
};

/// Like `parseTemplate`, but never stops: a stray `}` stays text, an
/// unclosed `{` runs to the end, and problems are collected.
pub fn parseTemplateTolerant(arena: Allocator, src: []const u8, max: usize) Allocator.Error!TemplateParsed {
    var diags: Diags = .{ .arena = arena, .max = max };
    var pieces: std.ArrayList(TemplateParsed.Piece) = .empty;
    var lit_start: ?usize = null;
    var i: usize = 0;
    const flush = struct {
        fn f(a: Allocator, list: *std.ArrayList(TemplateParsed.Piece), from: *?usize, to: usize) Allocator.Error!void {
            if (from.*) |st| try list.append(a, .{ .kind = .lit, .start = @intCast(st), .end = @intCast(to) });
            from.* = null;
        }
    }.f;
    while (i < src.len) {
        const ch = src[i];
        if ((ch == '{' or ch == '}') and i + 1 < src.len and src[i + 1] == ch) {
            try flush(arena, &pieces, &lit_start, i);
            try pieces.append(arena, .{ .kind = .escape, .start = @intCast(i), .end = @intCast(i + 2) });
            i += 2;
            continue;
        }
        if (ch != '{') {
            if (ch == '}') try diags.add(.{ .code = 3001, .start = @intCast(i), .end = @intCast(i + 1), .message = "stray '}' in text", .hint = "write '}}' for a literal brace" });
            if (lit_start == null) lit_start = i;
            i += 1;
            continue;
        }
        try flush(arena, &pieces, &lit_start, i);
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
        const close = @min(j, src.len);
        if (j >= src.len) try diags.add(.{ .code = 3001, .start = @intCast(i), .end = @intCast(src.len), .message = "unclosed '{' in text", .hint = "write '{{' for a literal brace" });
        const inner = src[i + 1 .. close];
        var root: ?*Node = null;
        if (std.mem.trim(u8, inner, " ").len == 0) {
            try diags.add(.{ .code = 3001, .start = @intCast(i), .end = @intCast(@min(close + 1, src.len)), .message = "empty '{}' in text", .hint = "write '{{}}' for literal braces" });
        } else {
            const parsed = try parseTolerant(arena, inner, @intCast(i + 1), max);
            for (parsed.problems) |pr| try diags.add(pr);
            if (parsed.truncated) diags.truncated = true;
            root = parsed.root;
        }
        const end = @min(close + 1, src.len);
        try pieces.append(arena, .{ .kind = .hole, .start = @intCast(i), .end = @intCast(end), .root = root });
        i = end;
    }
    try flush(arena, &pieces, &lit_start, src.len);
    return .{ .pieces = pieces.items, .problems = diags.list.items, .truncated = diags.truncated };
}

// ------------------------------------------------------------------ checker

pub const Symbol = struct {
    name: []const u8,
    ty: Type,
};

pub const FnSig = struct {
    name: []const u8,
    args: []const Symbol,
    ret: Type,
};

pub const LayerSymbol = struct {
    id: []const u8,
    kind: LayerKind,
    repeated: bool,
    /// Repeated groups around the layer (outermost first).
    rgroups: []const usize = &.{},

    /// Repeat levels of the layer that a layer inside `rgroups` is not
    /// inside: 0 means one position, 1 means an `[index]` picks one, more
    /// means it cannot be referenced.
    pub fn unshared(l: LayerSymbol, rgroups: []const usize) usize {
        var n: usize = if (l.repeated) 1 else 0;
        for (l.rgroups) |g| {
            if (std.mem.indexOfScalar(usize, rgroups, g) == null) n += 1;
        }
        return n;
    }
};

pub const Scope = struct {
    arena: Allocator,
    params: []const Symbol,
    locals: []const Symbol = &.{},
    /// Design constants and functions visible here.
    consts: []const Symbol = &.{},
    functions: []const FnSig = &.{},
    /// Repeated groups around the layer being checked: references to layers
    /// in the same groups mean the same iteration.
    rgroups: []const usize = &.{},
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

    /// A key lookup on a list: by its first text field, giving the other
    /// field for two-field (key/value) items, else the item.
    fn keyLookup(c: *Checker, n: *Node, def: *const value.ItemDef) Error!struct { Node.KeyLookup, Type } {
        const kf = keyField(def) orelse {
            return c.fail(3003, n, "this list has no text field to look items up by", "use a position instead, e.g. list[0]");
        };
        const vf = valueField(def, kf);
        return .{ .{ .key_field = kf, .value_field = vf }, if (vf) |v| def.types[v].toType() else .{ .item = def } };
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
            .name => |*nm| {
                const name = nm.text;
                nm.konst = null;
                var i = s.locals.len;
                while (i > 0) {
                    i -= 1;
                    if (std.mem.eql(u8, s.locals[i].name, name)) return s.locals[i].ty;
                }
                for (s.params) |p| if (std.mem.eql(u8, p.name, name)) return p.ty;
                for (s.consts, 0..) |k, ki| if (std.mem.eql(u8, k.name, name)) {
                    nm.konst = ki;
                    return k.ty;
                };
                var names: std.ArrayList([]const u8) = .empty;
                for (s.locals) |l| try names.append(s.arena, l.name);
                for (s.params) |p| try names.append(s.arena, p.name);
                for (s.consts) |k| try names.append(s.arena, k.name);
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
                    const unshared = l.unshared(s.rgroups);
                    if (r.index) |ix| {
                        if (unshared == 0) return c.fail(3003, n, try c.print("layer '{s}' is not repeated here; remove the [index]", .{r.id}), null);
                        if (unshared > 1) return c.fail(3005, n, try c.print("layer '{s}' is inside nested repeats and cannot be referenced from here", .{r.id}), null);
                        try c.expectType(ix, .number, "an iteration index");
                    } else if (unshared > 0) {
                        if (unshared > 1) return c.fail(3005, n, try c.print("layer '{s}' is inside nested repeats and cannot be referenced from here", .{r.id}), null);
                        return c.fail(3005, n, try c.print("layer '{s}' is repeated{s} and has no single position", .{ r.id, if (l.repeated) "" else " (inside a repeated group)" }), try c.print("pick one iteration, e.g. @{s}[0].{s}", .{ r.id, try std.mem.join(s.arena, ".", r.path) }));
                    }
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
                f.key = null;
                switch (t) {
                    .list => |def| {
                        // stats.Speed: the item whose key is "Speed".
                        const r = try c.keyLookup(n, def);
                        f.key = r[0];
                        return r[1];
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
            .index => |*ix| {
                const t = try c.check(ix.obj);
                ix.key = null;
                const def = switch (t) {
                    .list => |d| d,
                    else => return c.fail(3003, n, try c.print("cannot index a {s}", .{t.name()}), null),
                };
                const it = try c.check(ix.idx);
                if (it == .text) {
                    const r = try c.keyLookup(n, def);
                    ix.key = r[0];
                    return r[1];
                }
                if (it != .number) return c.fail(3003, ix.idx, try c.print("a list index needs a number (position) or text (key), got a {s}", .{it.name()}), null);
                return .{ .item = def };
            },
            .paren => |inner| return c.check(inner),
            .err => return c.fail(3001, n, "this part does not parse", null),
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
            .in_list => |il| {
                const lt = try c.check(il.v);
                if (!keyable(lt)) return c.fail(3003, il.v, try c.print("'in' compares numbers, text, bools or colors, got a {s}", .{lt.name()}), null);
                for (il.items, 1..) |item, i| {
                    const it = try c.check(item);
                    if (!it.eql(lt)) return c.fail(3003, item, try c.print("item {d} of the list is a {s}, but the left side is a {s}", .{ i, it.name(), lt.name() }), null);
                }
                return .bool;
            },
            .cond => |cd| {
                try c.expectType(cd.c, .bool, "the condition of '? :'");
                const a = try c.check(cd.a);
                const b = try c.check(cd.b);
                if (!a.eql(b)) return c.fail(3003, n, try c.print("the branches of '? :' differ: {s} and {s}", .{ a.name(), b.name() }), null);
                return a;
            },
            .call => |*cl| {
                // A design function with a built-in's name hides the built-in.
                for (s.functions) |f| if (std.mem.eql(u8, f.name, @tagName(cl.func))) {
                    const call_args = cl.args;
                    n.data = .{ .ucall = .{ .name = f.name, .args = call_args } };
                    return c.infer(n);
                };
                return c.checkCall(n, cl);
            },
            .ucall => |*uc| {
                for (s.functions, 0..) |f, fi| {
                    if (!std.mem.eql(u8, f.name, uc.name)) continue;
                    if (uc.args.len != f.args.len) return c.fail(3003, n, try c.print("{s}() takes {d} argument{s}, got {d}", .{ f.name, f.args.len, if (f.args.len == 1) "" else "s", uc.args.len }), null);
                    for (uc.args, f.args, 0..) |a, want, i| {
                        const t = try c.check(a);
                        if (!t.eql(want.ty)) return c.fail(3003, a, try c.print("argument {d} of {s}() must be a {s}, got a {s}", .{ i + 1, f.name, want.ty.name(), t.name() }), null);
                    }
                    uc.index = fi;
                    return f.ret;
                }
                var names: std.ArrayList([]const u8) = .empty;
                try names.appendSlice(s.arena, &function_names);
                for (s.functions) |f| try names.append(s.arena, f.name);
                return c.fail(3002, n, try c.print("unknown function '{s}'", .{uc.name}), diag.suggest(s.arena, uc.name, names.items));
            },
        }
    }

    /// match(value, key1, result1, ..., default): the keys are compared with
    /// the value, and the results and the default share one type.
    fn checkMatch(c: *Checker, n: *Node, args: []*Node) Error!Type {
        if (args.len < 4 or args.len % 2 != 0) {
            return c.fail(3003, n, "match() needs a value, then key/result pairs, then a default", "e.g. match(k, 'a', 1, 'b', 2, 0)");
        }
        const vt = try c.check(args[0]);
        if (!keyable(vt)) return c.fail(3003, args[0], try c.print("match() compares numbers, text, bools or colors, got a {s}", .{vt.name()}), null);
        var i: usize = 1;
        var pair: usize = 1;
        while (i < args.len - 1) : (i += 2) {
            const kt = try c.check(args[i]);
            if (!kt.eql(vt)) return c.fail(3003, args[i], try c.print("key {d} of match() is a {s}, but the value is a {s}", .{ pair, kt.name(), vt.name() }), null);
            pair += 1;
        }
        const rt = try c.check(args[2]);
        var j: usize = 4;
        while (j < args.len) : (j += 2) try c.matchResult(args[j], rt);
        try c.matchResult(args[args.len - 1], rt);
        return rt;
    }

    fn matchResult(c: *Checker, a: *Node, rt: Type) Error!void {
        const t = try c.check(a);
        if (!t.eql(rt)) return c.fail(3003, a, try c.print("the results of match() differ: {s} and {s}", .{ rt.name(), t.name() }), null);
    }

    fn checkCall(c: *Checker, n: *Node, cl: *Call) Error!Type {
        const func = cl.func;
        const args = cl.args;
        if (func == .match) return c.checkMatch(n, args);
        switch (func) {
            .has, .get, .index_of, .sum, .avg, .count, .join, .last => return c.checkList(n, cl),
            .min, .max => if (args.len >= 1 and args.len <= 2 and (try c.check(args[0])) == .list) return c.checkList(n, cl),
            .rand, .rand_int, .pick => return c.checkRandom(n, func, args),
            else => {},
        }
        const sig = funcSig(func);
        try c.arity(n, func, args.len, sig.min, sig.max);
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
        return sig.ret.?;
    }

    fn arity(c: *Checker, n: *Node, func: Func, got: usize, min: usize, max: usize) Error!void {
        if (got >= min and got <= max) return;
        const name = @tagName(func);
        const msg = if (min == max)
            try c.print("{s}() takes {d} argument{s}, got {d}", .{ name, min, if (min == 1) "" else "s", got })
        else if (max >= 64)
            try c.print("{s}() takes at least {d} arguments, got {d}", .{ name, min, got })
        else
            try c.print("{s}() takes {d} to {d} arguments, got {d}", .{ name, min, max, got });
        return c.fail(3003, n, msg, null);
    }

    /// List functions: the first argument is a list param; field names are
    /// quoted literals, resolved here so a typo is a load-time error.
    fn checkList(c: *Checker, n: *Node, cl: *Call) Error!Type {
        const func = cl.func;
        const args = cl.args;
        const name = @tagName(func);
        const range: [2]usize = switch (func) {
            .has, .index_of => .{ 2, 2 },
            .get => .{ 3, 4 },
            .sum, .avg, .min, .max => .{ 1, 2 },
            .count => .{ 3, 3 },
            .join => .{ 2, 3 },
            .last => .{ 1, 1 },
            else => unreachable,
        };
        try c.arity(n, func, args.len, range[0], range[1]);
        const lt = try c.check(args[0]);
        const def = switch (lt) {
            .list => |d| d,
            else => return c.fail(3003, args[0], try c.print("{s}() needs a list, got a {s}", .{ name, lt.name() }), "lists come from list params"),
        };
        switch (func) {
            .has, .index_of => {
                try c.expectType(args[1], .text, try c.print("the key of {s}()", .{name}));
                cl.lk = (try c.keyLookup(n, def))[0];
                return if (func == .has) .bool else .number;
            },
            .get => {
                try c.expectType(args[1], .text, "the key of get()");
                const lk = (try c.keyLookup(n, def))[0];
                cl.lk = lk;
                const ft: Type = if (args.len == 4) blk: {
                    cl.field = try c.fieldArg(args[2], def, name);
                    break :blk def.types[cl.field].toType();
                } else blk: {
                    const vf = lk.value_field orelse return c.fail(3003, n, "get() with 3 arguments needs a key/value list", "name the field: get(list, key, 'field', fallback)");
                    cl.field = vf;
                    break :blk def.types[vf].toType();
                };
                const fb = args[args.len - 1];
                const t = try c.check(fb);
                if (!t.eql(ft)) return c.fail(3003, fb, try c.print("the fallback of get() must be a {s}, got a {s}", .{ ft.name(), t.name() }), null);
                return ft;
            },
            .sum, .avg, .min, .max => {
                cl.field = if (args.len == 2) try c.fieldArg(args[1], def, name) else try c.defaultField(n, def, name);
                if (def.types[cl.field] != .number) return c.fail(3003, if (args.len == 2) args[1] else n, try c.print("{s}() needs a number field, '{s}' is a {s}", .{ name, def.names[cl.field], def.types[cl.field].toType().name() }), null);
                return .number;
            },
            .count => {
                cl.field = try c.fieldArg(args[1], def, name);
                const ft = def.types[cl.field].toType();
                const t = try c.check(args[2]);
                if (!t.comparable(ft)) return c.fail(3003, args[2], try c.print("count() compares with field '{s}', a {s}, got a {s}", .{ def.names[cl.field], ft.name(), t.name() }), null);
                return .number;
            },
            .join => {
                cl.field = if (args.len == 3) try c.fieldArg(args[1], def, name) else try c.defaultField(n, def, name);
                try c.expectType(args[args.len - 1], .text, "the separator of join()");
                return .text;
            },
            .last => return .{ .item = def },
            else => unreachable,
        }
    }

    /// A quoted field name of the list's items.
    fn fieldArg(c: *Checker, a: *Node, def: *const value.ItemDef, func: []const u8) Error!usize {
        _ = try c.check(a);
        const fname = switch (a.data) {
            .string => |str| str,
            else => return c.fail(3003, a, try c.print("the field of {s}() must be a quoted field name", .{func}), try c.print("e.g. {s}(list, '{s}')", .{ func, def.names[0] })),
        };
        return def.find(fname) orelse c.fail(3002, a, try c.print("list item has no field '{s}'", .{fname}), diag.suggest(c.scope.arena, fname, def.names));
    }

    /// The field a list function reads when none is named: the only field,
    /// or the value of a key/value list.
    fn defaultField(c: *Checker, n: *Node, def: *const value.ItemDef, func: []const u8) Error!usize {
        if (def.types.len == 1) return 0;
        if (keyField(def)) |kf| if (valueField(def, kf)) |vf| return vf;
        return c.fail(3003, n, try c.print("{s}() needs a field name for this list", .{func}), try c.print("e.g. {s}(list, '{s}')", .{ func, def.names[0] }));
    }

    /// rand(seed, ...), rand_int(lo, hi, seed, ...), pick(seed, a, b, ...).
    fn checkRandom(c: *Checker, n: *Node, func: Func, args: []*Node) Error!Type {
        const name = @tagName(func);
        switch (func) {
            .rand => {
                try c.arity(n, func, args.len, 1, 64);
                for (args) |a| try c.seed(a, name);
                return .number;
            },
            .rand_int => {
                try c.arity(n, func, args.len, 3, 64);
                try c.expectType(args[0], .number, "lo of rand_int()");
                try c.expectType(args[1], .number, "hi of rand_int()");
                for (args[2..]) |a| try c.seed(a, name);
                return .number;
            },
            .pick => {
                try c.arity(n, func, args.len, 3, 64);
                try c.seed(args[0], name);
                const rt = try c.check(args[1]);
                if (rt == .list or rt == .item) return c.fail(3003, args[1], try c.print("pick() chooses numbers, text, bools, colours or images, got a {s}", .{rt.name()}), null);
                for (args[2..]) |a| {
                    const t = try c.check(a);
                    if (!t.eql(rt)) return c.fail(3003, a, try c.print("the choices of pick() differ: {s} and {s}", .{ rt.name(), t.name() }), null);
                }
                return rt;
            },
            else => unreachable,
        }
    }

    fn seed(c: *Checker, a: *Node, func: []const u8) Error!void {
        const t = try c.check(a);
        if (!keyable(t)) return c.fail(3003, a, try c.print("seeds of {s}() are numbers, text, bools or colours, got a {s}", .{ func, t.name() }), null);
    }
};

/// A built-in function's argument count and types. `args` repeats its last
/// entry for further arguments; null is checked by the function itself
/// (`len`: list or text; `avg_color`: image; `match`: see checkMatch).
pub const FuncSig = struct { min: usize, max: usize, args: []const ?Type, ret: ?Type };

pub fn funcSig(func: Func) FuncSig {
    const num: ?Type = .number;
    const txt: ?Type = .text;
    const col: ?Type = .color;
    return switch (func) {
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
        // Value, key/result pairs, default; the result type is the results'.
        .match => .{ .min = 4, .max = 64, .args = &.{null}, .ret = null },
        .sqrt, .sign, .sin, .cos, .tan, .asin, .acos => .{ .min = 1, .max = 1, .args = &.{num}, .ret = .number },
        .pow, .atan2, .wrap => .{ .min = 2, .max = 2, .args = &.{ num, num }, .ret = .number },
        .lerp => .{ .min = 3, .max = 3, .args = &.{ num, num, num }, .ret = .number },
        .remap => .{ .min = 5, .max = 5, .args = &.{ num, num, num, num, num }, .ret = .number },
        .contains, .starts_with, .ends_with => .{ .min = 2, .max = 2, .args = &.{ txt, txt }, .ret = .bool },
        .replace => .{ .min = 3, .max = 3, .args = &.{ txt, txt, txt }, .ret = .text },
        .slice => .{ .min = 2, .max = 3, .args = &.{ txt, num, num }, .ret = .text },
        .pad_start => .{ .min = 2, .max = 3, .args = &.{ txt, num, txt }, .ret = .text },
        .repeat => .{ .min = 2, .max = 2, .args = &.{ txt, num }, .ret = .text },
        .title_case => .{ .min = 1, .max = 1, .args = &.{txt}, .ret = .text },
        .roman => .{ .min = 1, .max = 1, .args = &.{num}, .ret = .text },
        .part => .{ .min = 3, .max = 3, .args = &.{ txt, txt, num }, .ret = .text },
        // List functions are checked by checkList: list, then field names.
        .has => .{ .min = 2, .max = 2, .args = &.{ null, txt }, .ret = null },
        .get => .{ .min = 3, .max = 4, .args = &.{ null, txt, null, null }, .ret = null },
        .index_of => .{ .min = 2, .max = 2, .args = &.{ null, txt }, .ret = null },
        .sum, .avg => .{ .min = 1, .max = 2, .args = &.{ null, txt }, .ret = null },
        .count => .{ .min = 3, .max = 3, .args = &.{ null, txt, null }, .ret = null },
        .join => .{ .min = 2, .max = 3, .args = &.{ null, txt, txt }, .ret = null },
        .last => .{ .min = 1, .max = 1, .args = &.{null}, .ret = null },
        .date_fmt => .{ .min = 2, .max = 2, .args = &.{ txt, txt }, .ret = .text },
        .year, .month, .day, .weekday, .hour, .minute => .{ .min = 1, .max = 1, .args = &.{txt}, .ret = .number },
        .add_days, .add_hours => .{ .min = 2, .max = 2, .args = &.{ txt, num }, .ret = .text },
        .days_between => .{ .min = 2, .max = 2, .args = &.{ txt, txt }, .ret = .number },
        .hsl => .{ .min = 3, .max = 3, .args = &.{ num, num, num }, .ret = .color },
        .hsla => .{ .min = 4, .max = 4, .args = &.{ num, num, num, num }, .ret = .color },
        .lighten, .darken => .{ .min = 2, .max = 2, .args = &.{ col, num }, .ret = .color },
        .luminance => .{ .min = 1, .max = 1, .args = &.{col}, .ret = .number },
        .readable => .{ .min = 1, .max = 3, .args = &.{ col, col, col }, .ret = .color },
        // Seeds are numbers, text, bools or colours (checkRandom).
        .rand => .{ .min = 1, .max = 64, .args = &.{null}, .ret = .number },
        .rand_int => .{ .min = 3, .max = 64, .args = &.{ num, num, null }, .ret = .number },
        .pick => .{ .min = 3, .max = 64, .args = &.{null}, .ret = null },
    };
}

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
        if (eq(u8, a, "stroke") and (kind == .rect or kind == .ellipse or kind == .polygon or kind == .text)) {
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

/// Types that `in` and `match()` can compare.
fn keyable(t: Type) bool {
    return switch (t) {
        .number, .text, .bool, .color => true,
        else => false,
    };
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

/// The children of a node, in the order editors number them (pre-order,
/// see `exprjson.writeNode`).
pub fn children(arena: Allocator, n: *const Node) Allocator.Error![]const *Node {
    var out: std.ArrayList(*Node) = .empty;
    switch (n.data) {
        .number, .unit, .string, .boolean, .color, .name, .builtin => {},
        .layer_ref => |r| if (r.index) |ix| try out.append(arena, ix),
        .field => |f| try out.append(arena, f.obj),
        .index => |ix| try out.appendSlice(arena, &.{ ix.obj, ix.idx }),
        .call => |c| try out.appendSlice(arena, c.args),
        .ucall => |c| try out.appendSlice(arena, c.args),
        .neg, .not, .paren => |x| try out.append(arena, x),
        .binary => |b| try out.appendSlice(arena, &.{ b.l, b.r }),
        .cond => |c| try out.appendSlice(arena, &.{ c.c, c.a, c.b }),
        .in_list => |il| {
            try out.append(arena, il.v);
            try out.appendSlice(arena, il.items);
        },
        .err => |x| if (x) |c| try out.append(arena, c),
    }
    return out.items;
}

/// Values of the nodes of one expression, recorded while it is evaluated
/// (for an editor's live values). Nodes that were not evaluated (the other
/// branch of `? :`) stay null.
pub const Trace = struct {
    /// Holds the values: they are copied, so they outlive the evaluation.
    arena: Allocator,
    ids: std.AutoHashMapUnmanaged(*const Node, u32) = .empty,
    values: []?Value = &.{},

    /// Numbers the nodes of `roots` in pre-order, continuing across roots
    /// (template holes), like `exprjson.writeNode`.
    pub fn init(arena: Allocator, roots: []const *const Node) Allocator.Error!Trace {
        var t: Trace = .{ .arena = arena };
        var next: u32 = 0;
        for (roots) |r| try t.number(arena, r, &next);
        t.values = try arena.alloc(?Value, next);
        @memset(t.values, null);
        return t;
    }

    fn number(t: *Trace, arena: Allocator, n: *const Node, next: *u32) Allocator.Error!void {
        try t.ids.put(arena, n, next.*);
        next.* += 1;
        for (try children(arena, n)) |c| try t.number(arena, c, next);
    }

    fn record(t: *Trace, n: *const Node, v: Value) Allocator.Error!void {
        // The first value wins: a loop or function evaluates it again.
        if (t.ids.get(n)) |id| if (t.values[id] == null) {
            t.values[id] = try v.dupe(t.arena);
        };
    }
};

pub const Env = struct {
    arena: Allocator,
    canvas_w: f64,
    canvas_h: f64,
    card_id: []const u8,
    render_index: f64,
    render_date: []const u8,
    /// Local time of the render, `HH:MM:SS`.
    render_time: []const u8 = "00:00:00",
    /// UTC instant of the render, `YYYY-MM-DDTHH:MM:SSZ`.
    render_now: []const u8 = "1970-01-01T00:00:00Z",
    axis: Axis = .none,
    ctx: *anyopaque,
    /// Params and loop names.
    lookup: *const fn (ctx: *anyopaque, name: []const u8) ?Value,
    layerRef: *const fn (ctx: *anyopaque, id: []const u8, path: []const []const u8, index: ?f64) EvalError!Value,
    avgColor: *const fn (ctx: *anyopaque, path: []const u8) EvalError!Color,
    /// Design constants and functions (null where there are none).
    constValue: ?*const fn (ctx: *anyopaque, index: usize) EvalError!Value = null,
    callUser: ?*const fn (ctx: *anyopaque, index: usize, args: []const Value) EvalError!Value = null,
    problem: ?Problem = null,
    /// When set, records the value of every node evaluated.
    trace: ?*Trace = null,

    fn fail(env: *Env, code: u16, n: *const Node, msg: []const u8) EvalError {
        env.problem = .{ .code = code, .start = n.start, .end = n.end, .message = msg };
        return error.Eval;
    }

    pub fn eval(env: *Env, n: *const Node) EvalError!Value {
        const v = try env.evalNode(n);
        if (env.trace) |t| try t.record(n, v);
        return v;
    }

    fn evalNode(env: *Env, n: *const Node) EvalError!Value {
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
                .render_time => .{ .text = env.render_time },
                .render_now => .{ .text = env.render_now },
            },
            .name => |nm| {
                if (nm.konst) |ki| return (env.constValue orelse return env.fail(3002, n, "constants are not available here"))(env.ctx, ki);
                return env.lookup(env.ctx, nm.text) orelse env.fail(3002, n, "unknown name");
            },
            .layer_ref => |r| return env.layerRef(env.ctx, r.id, r.path, if (r.index) |ix| (try env.eval(ix)).number else null),
            .field => |f| {
                const obj = try env.eval(f.obj);
                if (f.key) |lk| return env.keyLookup(n, obj.list, f.name, lk);
                return obj.item[f.index];
            },
            .index => |ix| {
                const list = (try env.eval(ix.obj)).list;
                if (ix.key) |lk| return env.keyLookup(n, list, (try env.eval(ix.idx)).text, lk);
                const idx = (try env.eval(ix.idx)).number;
                const i = @floor(idx);
                if (!(i >= 0 and i < @as(f64, @floatFromInt(list.len)))) {
                    return env.fail(3102, n, try std.fmt.allocPrint(env.arena, "index {d} is out of range for a list of {d}", .{ i, list.len }));
                }
                return .{ .item = list[@intFromFloat(i)] };
            },
            .paren => |inner| return env.eval(inner),
            .err => return env.fail(3001, n, "this part does not parse"),
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
            .in_list => |il| {
                const v = try env.eval(il.v);
                for (il.items) |item| {
                    if (v.eql(try env.eval(item))) return .{ .bool = true };
                }
                return .{ .bool = false };
            },
            .cond => |cd| return if ((try env.eval(cd.c)).bool) env.eval(cd.a) else env.eval(cd.b),
            .call => |cl| return env.call(n, cl),
            .ucall => |uc| {
                const f = env.callUser orelse return env.fail(3002, n, "functions are not available here");
                const vals = try env.arena.alloc(Value, uc.args.len);
                for (uc.args, vals) |a, *v| v.* = try env.eval(a);
                return f(env.ctx, uc.index, vals);
            },
        }
    }

    fn keyLookup(env: *Env, n: *const Node, list: []const []const Value, key: []const u8, lk: Node.KeyLookup) EvalError!Value {
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
    }

    fn num(env: *Env, n: *const Node) EvalError!f64 {
        return (try env.eval(n)).number;
    }

    fn call(env: *Env, n: *const Node, cl: Call) EvalError!Value {
        const func = cl.func;
        const args = cl.args;
        switch (func) {
            .min, .max => {
                if (args.len <= 2 and args[0].ty == .list) return env.listCall(n, cl);
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
                const t = try env.str(args[0]);
                return env.text(n, func, if (func == .upper) btext.upper(env.arena, t) else btext.lower(env.arena, t));
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
            .match => {
                // Lazy like `? :`: only the chosen result is evaluated.
                const v = try env.eval(args[0]);
                var i: usize = 1;
                while (i < args.len - 1) : (i += 2) {
                    if ((try env.eval(args[i])).eql(v)) return env.eval(args[i + 1]);
                }
                return env.eval(args[args.len - 1]);
            },
            .sqrt, .sign, .sin, .cos, .tan, .asin, .acos => {
                const x = try env.num(args[0]);
                return env.number(n, func, switch (func) {
                    .sqrt => bmath.sqrt(x),
                    .sign => bmath.sign(x),
                    .sin => bmath.sin(x),
                    .cos => bmath.cos(x),
                    .tan => bmath.tan(x),
                    .asin => bmath.asin(x),
                    .acos => bmath.acos(x),
                    else => unreachable,
                });
            },
            .pow => return env.number(n, func, bmath.pow(try env.num(args[0]), try env.num(args[1]))),
            .atan2 => return env.number(n, func, bmath.atan2(try env.num(args[0]), try env.num(args[1]))),
            .wrap => return env.number(n, func, bmath.wrap(try env.num(args[0]), try env.num(args[1]))),
            .lerp => return env.number(n, func, bmath.lerp(try env.num(args[0]), try env.num(args[1]), try env.num(args[2]))),
            .remap => {
                var v: [5]f64 = undefined;
                for (args, &v) |a, *x| x.* = try env.num(a);
                return env.number(n, func, bmath.remap(v[0], v[1], v[2], v[3], v[4]));
            },
            .contains, .starts_with, .ends_with => {
                const t = try env.str(args[0]);
                const sub = try env.str(args[1]);
                return .{ .bool = switch (func) {
                    .contains => btext.contains(t, sub),
                    .starts_with => btext.startsWith(t, sub),
                    else => btext.endsWith(t, sub),
                } };
            },
            .replace => return env.text(n, func, btext.replace(env.arena, try env.str(args[0]), try env.str(args[1]), try env.str(args[2]))),
            .slice => {
                const t = try env.str(args[0]);
                const start = try env.num(args[1]);
                const end: ?f64 = if (args.len > 2) try env.num(args[2]) else null;
                return env.text(n, func, btext.slice(env.arena, t, start, end));
            },
            .pad_start => {
                const t = try env.str(args[0]);
                const width = try env.num(args[1]);
                const fill = if (args.len > 2) try env.str(args[2]) else " ";
                return env.text(n, func, btext.padStart(env.arena, t, width, fill));
            },
            .repeat => return env.text(n, func, btext.repeat(env.arena, try env.str(args[0]), try env.num(args[1]))),
            .title_case => return env.text(n, func, btext.titleCase(env.arena, try env.str(args[0]))),
            .roman => return env.text(n, func, btext.roman(env.arena, try env.num(args[0]))),
            .part => return env.text(n, func, btext.part(try env.str(args[0]), try env.str(args[1]), try env.num(args[2]))),
            .has, .get, .index_of, .sum, .avg, .count, .join, .last => return env.listCall(n, cl),
            .date_fmt => {
                const p = try env.date(n, func, try env.str(args[0]));
                return env.text(n, func, bdate.format(env.arena, p, try env.str(args[1])));
            },
            .year, .month, .day, .weekday, .hour, .minute => {
                const p = try env.date(n, func, try env.str(args[0]));
                return env.number(n, func, switch (func) {
                    .year => bdate.year(p),
                    .month => bdate.month(p),
                    .day => bdate.day(p),
                    .weekday => bdate.weekday(p),
                    .hour => bdate.hour(p),
                    else => bdate.minute(p),
                });
            },
            .add_days => return env.text(n, func, bdate.addDays(env.arena, try env.str(args[0]), try env.num(args[1]))),
            .add_hours => return env.text(n, func, bdate.addHours(env.arena, try env.str(args[0]), try env.num(args[1]))),
            .days_between => return env.number(n, func, bdate.daysBetween(try env.str(args[0]), try env.str(args[1]))),
            .hsl, .hsla => {
                const h = try env.num(args[0]);
                const sat = try env.num(args[1]);
                const l = try env.num(args[2]);
                const a = if (func == .hsla) try env.num(args[3]) else 1;
                return .{ .color = bcolor.hsl(h, sat, l, a) };
            },
            .lighten, .darken => {
                const c = (try env.eval(args[0])).color;
                const amount = try env.num(args[1]);
                return .{ .color = if (func == .lighten) bcolor.lighten(c, amount) else bcolor.darken(c, amount) };
            },
            .luminance => return .{ .number = bcolor.luminance((try env.eval(args[0])).color) },
            .readable => {
                const bg = (try env.eval(args[0])).color;
                const light = if (args.len > 1) (try env.eval(args[1])).color else Color.white;
                const dark = if (args.len > 2) (try env.eval(args[2])).color else Color.black;
                return .{ .color = bcolor.readable(bg, light, dark) };
            },
            .rand => return .{ .number = brand.unit(try env.evalAll(args)) },
            .rand_int => {
                const lo = try env.num(args[0]);
                const hi = try env.num(args[1]);
                return env.number(n, func, brand.int(lo, hi, try env.evalAll(args[2..])));
            },
            .pick => {
                // Lazy like match(): only the chosen value is evaluated.
                const seed_v = try env.eval(args[0]);
                const i = brand.pickIndex(&.{seed_v}, args.len - 1);
                return env.eval(args[1 + i]);
            },
        }
    }

    fn str(env: *Env, n: *const Node) EvalError![]const u8 {
        return (try env.eval(n)).text;
    }

    fn evalAll(env: *Env, nodes: []const *Node) EvalError![]const Value {
        const out = try env.arena.alloc(Value, nodes.len);
        for (nodes, out) |a, *v| v.* = try env.eval(a);
        return out;
    }

    fn date(env: *Env, n: *const Node, func: Func, t: []const u8) EvalError!bdate.Parsed {
        return bdate.parse(t) catch |e| env.builtinFail(n, func, e);
    }

    /// A number result: a plain f64 or an error union from a builtin module.
    fn number(env: *Env, n: *const Node, func: Func, r: anytype) EvalError!Value {
        const x: f64 = if (@typeInfo(@TypeOf(r)) == .error_union) (r catch |e| return env.builtinFail(n, func, e)) else r;
        if (!std.math.isFinite(x)) return env.fail(3103, n, try std.fmt.allocPrint(env.arena, "{s}() has no finite result here", .{@tagName(func)}));
        return .{ .number = x };
    }

    fn text(env: *Env, n: *const Node, func: Func, r: anytype) EvalError!Value {
        return .{ .text = r catch |e| return env.builtinFail(n, func, e) };
    }

    /// Maps a builtin module's error to its diagnostic (SPEC: 3103, 3105, 3106, 3107).
    fn builtinFail(env: *Env, n: *const Node, func: Func, e: anyerror) EvalError {
        const name = @tagName(func);
        const a = env.arena;
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.Domain => env.fail(3103, n, try switch (func) {
                .avg, .min, .max => std.fmt.allocPrint(a, "{s}() of an empty list", .{name}),
                .remap => std.fmt.allocPrint(a, "remap() needs two different input ends", .{}),
                .wrap => std.fmt.allocPrint(a, "wrap() by zero", .{}),
                else => std.fmt.allocPrint(a, "{s}() has no result for these arguments", .{name}),
            }),
            error.BadDate => env.fail(3105, n, try std.fmt.allocPrint(a, "{s}() needs a date like 2026-10-15, a time like 18:30 or both like 2026-10-15T18:30", .{name})),
            error.TooLong => env.fail(3106, n, try std.fmt.allocPrint(a, "{s}() would make text longer than {d} bytes", .{ name, btext.max_len })),
            error.Range => env.fail(3107, n, try switch (func) {
                .roman => std.fmt.allocPrint(a, "roman() needs a number from 1 to 3999", .{}),
                .part => std.fmt.allocPrint(a, "part() needs a separator that is not empty", .{}),
                .rand_int => std.fmt.allocPrint(a, "rand_int() needs lo <= hi", .{}),
                else => std.fmt.allocPrint(a, "an argument of {s}() is out of range", .{name}),
            }),
            else => env.fail(3103, n, try std.fmt.allocPrint(a, "{s}() failed: {s}", .{ name, @errorName(e) })),
        };
    }

    /// List functions; `cl.field` and `cl.lk` were set by the checker.
    fn listCall(env: *Env, n: *const Node, cl: Call) EvalError!Value {
        const items = (try env.eval(cl.args[0])).list;
        const func = cl.func;
        switch (func) {
            .has, .index_of => {
                const i = blist.indexOf(items, cl.lk.?.key_field, try env.str(cl.args[1]));
                if (func == .has) return .{ .bool = i != null };
                return .{ .number = if (i) |x| @floatFromInt(x) else -1 };
            },
            .get => {
                const i = blist.indexOf(items, cl.lk.?.key_field, try env.str(cl.args[1])) orelse return env.eval(cl.args[cl.args.len - 1]);
                return items[i][cl.field];
            },
            .sum => return env.number(n, func, blist.sum(items, cl.field)),
            .avg => return env.number(n, func, blist.avg(items, cl.field)),
            .min => return env.number(n, func, blist.minOf(items, cl.field)),
            .max => return env.number(n, func, blist.maxOf(items, cl.field)),
            .count => return .{ .number = @floatFromInt(blist.count(items, cl.field, try env.eval(cl.args[2]))) },
            .join => return env.text(n, func, blist.join(env.arena, items, cl.field, try env.str(cl.args[cl.args.len - 1]))),
            .last => {
                if (items.len == 0) return env.fail(3102, n, "last() of an empty list");
                return .{ .item = items[items.len - 1] };
            },
            else => unreachable,
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
    try testing.expect((try testCheck(a, "edition in ['a', 'b']", &scope)) == .bool);
    try testing.expect((try testCheck(a, "level in [1, 2, 3]", &scope)) == .bool);
    try testing.expect((try testCheck(a, "match(level, 1, #FF0000, 2, #00FF00, #0000FF)", &scope)) == .color);
    try testing.expect((try testCheck(a, "match(edition, 'a', 1, 0)", &scope)) == .number);

    try expectProblem(a, "level in ['a']", &scope, 3003);
    try expectProblem(a, "level in 1", &scope, 3001);
    try expectProblem(a, "level in []", &scope, 3001);
    try expectProblem(a, "level in [1, 2,]", &scope, 3001);
    try expectProblem(a, "in", &scope, 3001);
    try expectProblem(a, "match(level, 1, 2)", &scope, 3003);
    try expectProblem(a, "match(level, 1)", &scope, 3003);
    try expectProblem(a, "match(level, 1, 2, 3, 4)", &scope, 3003);
    try expectProblem(a, "match(level, 'a', 1, 0)", &scope, 3003);
    try expectProblem(a, "match(level, 1, 'x', 0)", &scope, 3003);

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

/// Expects `src` to fail with `code`, either while parsing or while checking.
fn expectProblem(arena: Allocator, src: []const u8, scope: *const Scope, code: u16) !void {
    var problem: ?Problem = null;
    const n = parse(arena, src, 0, &problem) catch |e| {
        try testing.expectEqual(error.Invalid, e);
        try testing.expectEqual(code, problem.?.code);
        return;
    };
    var c: Checker = .{ .scope = scope, .problem = &problem };
    try testing.expectError(error.Invalid, c.check(n));
    try testing.expectEqual(code, problem.?.code);
}

fn testLookup(_: *anyopaque, name: []const u8) ?Value {
    if (std.mem.eql(u8, name, "level")) return .{ .number = 4 };
    return null;
}

fn testRef(_: *anyopaque, _: []const u8, _: []const []const u8, _: ?f64) EvalError!Value {
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

    try testing.expect((try env.eval(try parse(a, "level in [1, 4]", 0, &problem))).bool);
    try testing.expect(!(try env.eval(try parse(a, "level in [1, 2]", 0, &problem))).bool);
    try testing.expectEqual(@as(f64, 40), (try env.eval(try parse(a, "match(level, 1, 10, 4, 40, 0)", 0, &problem))).number);
    try testing.expectEqual(@as(f64, 0), (try env.eval(try parse(a, "match(level, 1, 10, 0)", 0, &problem))).number);
    try testing.expectEqual(@as(f64, 1), (try env.eval(try parse(a, "match(level, 4, 1, 1 / (level - 4))", 0, &problem))).number);
}

fn expectTolerant(arena: Allocator, src: []const u8, n_problems: usize, root_kind: std.meta.Tag(Node.Data)) !Parsed {
    const r = try parseTolerant(arena, src, 0, 8);
    testing.expectEqual(n_problems, r.problems.len) catch |e| {
        for (r.problems) |pr| std.debug.print("{s}: {d}..{d} {s}\n", .{ src, pr.start, pr.end, pr.message });
        return e;
    };
    try testing.expectEqual(root_kind, std.meta.activeTag(r.root.data));
    return r;
}

test "tolerant parse" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    // Valid input: same tree as the strict parser, no problems.
    _ = try expectTolerant(a, "1 + 2 * x", 0, .binary);
    _ = try expectTolerant(a, "(a)", 0, .paren);

    // Missing operand: the binary node is kept, its right side is an error.
    var r = try expectTolerant(a, "a + ", 1, .binary);
    try testing.expect(r.root.data.binary.r.data == .err);
    // Missing ')' is reported, the call is kept.
    r = try expectTolerant(a, "max(a, b", 1, .call);
    try testing.expectEqual(@as(usize, 2), r.root.data.call.args.len);
    // An empty argument does not swallow the ')'.
    r = try expectTolerant(a, "max(a, )", 1, .call);
    // Several problems are all reported.
    r = try expectTolerant(a, "a + ! + #zz", 2, .binary);
    // Text after a complete expression: one error node keeping the tree.
    r = try expectTolerant(a, "a b c", 1, .err);
    try testing.expect(r.root.data.err.?.data == .name);
    try testing.expectEqual(@as(u32, 5), r.root.end);
    // Cond missing its else branch.
    r = try expectTolerant(a, "x ? 1", 1, .cond);
    // Bad 'in' list keeps the left side.
    r = try expectTolerant(a, "k in 3", 1, .err);
    // Lexer problems become error tokens.
    r = try expectTolerant(a, "'open", 1, .err);
    r = try expectTolerant(a, "", 1, .err);
    r = try expectTolerant(a, ")", 1, .err);

    // Deep nesting is an error, not a crash.
    const deep = try a.alloc(u8, 600);
    @memset(deep[0..300], '(');
    @memset(deep[300..], ')');
    r = try parseTolerant(a, deep, 0, 8);
    try testing.expect(r.problems.len >= 1);
    var problem: ?Problem = null;
    try testing.expectError(error.Invalid, parse(a, deep, 0, &problem));

    // The problem list is capped.
    r = try parseTolerant(a, "! ! ! ! ! ! ! ! ! ! ! !", 0, 3);
    try testing.expectEqual(@as(usize, 3), r.problems.len);
    try testing.expect(r.truncated);

    // Every prefix of a real expression parses without failing.
    const src = "match(t.kind, 'back', with_alpha(c_ink, 0.5), 'forward', @tile[i - 1].bounds.cx > 2 ? #FF0000 : rgb(1, 2, 3), c_plain)";
    for (0..src.len + 1) |k| _ = try parseTolerant(a, src[0..k], 0, 8);
}

test "tolerant template parse" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var t = try parseTemplateTolerant(a, "Lv {level + 1} {{x}}", 8);
    try testing.expectEqual(@as(usize, 0), t.problems.len);
    try testing.expectEqual(@as(usize, 6), t.pieces.len);
    try testing.expect(t.pieces[1].kind == .hole);
    try testing.expectEqual(@as(u32, 4), t.pieces[1].root.?.start);
    t = try parseTemplateTolerant(a, "a } b {c + ", 8);
    try testing.expectEqual(@as(usize, 3), t.problems.len);
    t = try parseTemplateTolerant(a, "{}", 8);
    try testing.expectEqual(@as(usize, 1), t.problems.len);
}

test "tolerant parse never fails on random input" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const chars = "ab1.%#@()[],?:+-*/<>=!'\"{} \\_inotv";
    var prng = std.Random.DefaultPrng.init(42);
    const rnd = prng.random();
    var buf: [24]u8 = undefined;
    for (0..20000) |_| {
        const len = rnd.uintLessThan(usize, buf.len);
        for (buf[0..len]) |*ch| ch.* = chars[rnd.uintLessThan(usize, chars.len)];
        const r = try parseTolerant(a, buf[0..len], 0, 8);
        try testing.expect(r.root.end <= len);
        _ = try parseTemplateTolerant(a, buf[0..len], 8);
    }
}

// Built-in functions in expressions (the modules in builtins/ test their own
// edge cases; these check the wiring: types, field resolution, errors).

const units_def: value.ItemDef = .{
    .names = &.{ "name", "cost", "elite" },
    .types = &.{ .text, .number, .bool },
};
const stats_def: value.ItemDef = .{
    .names = &.{ "stat", "value" },
    .types = &.{ .text, .number },
};
const tags_def: value.ItemDef = .{ .names = &.{"tag"}, .types = &.{.text} };

fn builtinLookup(_: *anyopaque, name: []const u8) ?Value {
    const eq = std.mem.eql;
    if (eq(u8, name, "level")) return .{ .number = 4 };
    if (eq(u8, name, "units")) return .{ .list = &.{
        &.{ .{ .text = "Elf" }, .{ .number = 3 }, .{ .bool = false } },
        &.{ .{ .text = "Orc" }, .{ .number = 5 }, .{ .bool = true } },
        &.{ .{ .text = "Imp" }, .{ .number = 1 }, .{ .bool = true } },
    } };
    if (eq(u8, name, "stats")) return .{ .list = &.{
        &.{ .{ .text = "Speed" }, .{ .number = 7 } },
        &.{ .{ .text = "Power" }, .{ .number = 2 } },
    } };
    if (eq(u8, name, "tags")) return .{ .list = &.{ &.{.{ .text = "Fire" }}, &.{.{ .text = "Flying" }} } };
    if (eq(u8, name, "none") or eq(u8, name, "no_stats")) return .{ .list = &.{} };
    return null;
}

const BuiltinFixture = struct {
    scope: Scope,
    env: Env,

    fn eval(f: *BuiltinFixture, src: []const u8) !Value {
        var problem: ?Problem = null;
        const n = try parse(f.scope.arena, src, 0, &problem);
        var c: Checker = .{ .scope = &f.scope, .problem = &problem };
        _ = c.check(n) catch |e| {
            std.debug.print("{s}: {s}\n", .{ src, problem.?.message });
            return e;
        };
        return f.env.eval(n);
    }

    fn checkCode(f: *BuiltinFixture, src: []const u8) !u16 {
        var problem: ?Problem = null;
        const n = try parse(f.scope.arena, src, 0, &problem);
        var c: Checker = .{ .scope = &f.scope, .problem = &problem };
        if (c.check(n)) |_| return 0 else |_| return problem.?.code;
    }

    fn evalCode(f: *BuiltinFixture, src: []const u8) !u16 {
        f.env.problem = null;
        if (f.eval(src)) |_| return 0 else |e| switch (e) {
            error.Eval => return f.env.problem.?.code,
            else => return e,
        }
    }
};

fn builtinFixture(a: Allocator, dummy: *u8) BuiltinFixture {
    return .{
        .scope = .{
            .arena = a,
            .params = &.{
                .{ .name = "level", .ty = .number },
                .{ .name = "units", .ty = .{ .list = &units_def } },
                .{ .name = "stats", .ty = .{ .list = &stats_def } },
                .{ .name = "tags", .ty = .{ .list = &tags_def } },
                .{ .name = "none", .ty = .{ .list = &tags_def } },
                .{ .name = "no_stats", .ty = .{ .list = &stats_def } },
                // A param may share a built-in function's name.
                .{ .name = "sum", .ty = .number },
            },
            .layers = null,
        },
        .env = .{
            .arena = a,
            .canvas_w = 200,
            .canvas_h = 400,
            .card_id = "007",
            .render_index = 0,
            .render_date = "2026-10-15",
            .render_time = "18:30:00",
            .render_now = "2026-10-15T16:30:00Z",
            .ctx = dummy,
            .lookup = builtinLookup,
            .layerRef = testRef,
            .avgColor = testAvg,
        },
    };
}

test "built-in functions: numbers, text, dates, colours" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var dummy: u8 = 0;
    var f = builtinFixture(arena_state.allocator(), &dummy);

    try testing.expectEqual(@as(f64, 1), (try f.eval("sin(90)")).number);
    try testing.expectEqual(@as(f64, 0), (try f.eval("cos(90)")).number);
    try testing.expectEqual(@as(f64, 3), (try f.eval("sqrt(9)")).number);
    try testing.expectEqual(@as(f64, 8), (try f.eval("pow(2, 3)")).number);
    try testing.expectEqual(@as(f64, 50), (try f.eval("remap(5, 0, 10, 0, 100)")).number);
    try testing.expectEqual(@as(f64, 2), (try f.eval("wrap(-1, 3)")).number);
    try testing.expectEqual(@as(u16, 3103), try f.evalCode("sqrt(-1)"));
    try testing.expectEqual(@as(u16, 3103), try f.evalCode("remap(1, 2, 2, 0, 1)"));

    try testing.expect((try f.eval("starts_with(card.id, '00')")).bool);
    try testing.expectEqualStrings("007", (try f.eval("pad_start('7', 3, '0')")).text);
    try testing.expectEqualStrings("★★★", (try f.eval("repeat('★', 3)")).text);
    try testing.expectEqualStrings("Water", (try f.eval("part('Fire/Water', '/', 1)")).text);
    try testing.expectEqualStrings("XIV", (try f.eval("roman(level + 10)")).text);
    try testing.expectEqualStrings("ÉCLAIR", (try f.eval("upper('éclair')")).text);
    try testing.expectEqual(@as(u16, 3107), try f.evalCode("roman(0)"));
    try testing.expectEqual(@as(u16, 3106), try f.evalCode("repeat('ab', 6000)"));

    try testing.expectEqualStrings("15 Oct 2026", (try f.eval("date_fmt(render.date, 'D MMM YYYY')")).text);
    try testing.expectEqual(@as(f64, 18), (try f.eval("hour(render.time)")).number);
    try testing.expectEqual(@as(f64, 4), (try f.eval("weekday(render.date)")).number);
    try testing.expectEqualStrings("2026-10-25", (try f.eval("add_days(render.date, 10)")).text);
    try testing.expectEqual(@as(f64, 77), (try f.eval("days_between(render.date, '2026-12-31')")).number);
    try testing.expectEqualStrings("2026-10-15T11:30:00Z", (try f.eval("add_hours(render.now, -5)")).text);
    try testing.expectEqual(@as(u16, 3105), try f.evalCode("year('15.10.2026')"));

    try testing.expect((try f.eval("hsl(0, 100, 50) == #FF0000")).bool);
    try testing.expect((try f.eval("readable(#111111) == #FFFFFF")).bool);
    try testing.expect((try f.eval("readable(#EEEEEE) == #000000")).bool);

    const r1 = (try f.eval("rand(card.id, 1)")).number;
    try testing.expect(r1 >= 0 and r1 < 1);
    try testing.expectEqual(r1, (try f.eval("rand(card.id, 1)")).number);
    const k = (try f.eval("rand_int(1, 6, card.id)")).number;
    try testing.expect(k >= 1 and k <= 6 and k == @floor(k));
    try testing.expect((try f.eval("pick(card.id, 'a', 'b') in ['a', 'b']")).bool);

    try testing.expectEqual(@as(u16, 3003), try f.checkCode("sin('a')"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("rand()"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("pick(1, 'a', 2)"));
}

test "built-in functions: lists" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var dummy: u8 = 0;
    var f = builtinFixture(arena_state.allocator(), &dummy);

    try testing.expect((try f.eval("has(units, 'Orc')")).bool);
    try testing.expect(!(try f.eval("has(units, 'Elk')")).bool);
    try testing.expectEqual(@as(f64, 1), (try f.eval("index_of(units, 'Orc')")).number);
    try testing.expectEqual(@as(f64, -1), (try f.eval("index_of(units, 'Elk')")).number);
    try testing.expectEqual(@as(f64, 7), (try f.eval("get(stats, 'Speed', 0)")).number);
    try testing.expectEqual(@as(f64, 0), (try f.eval("get(stats, 'Luck', 0)")).number);
    try testing.expectEqual(@as(f64, 5), (try f.eval("get(units, 'Orc', 'cost', 0)")).number);
    try testing.expectEqual(@as(f64, 9), (try f.eval("sum(units, 'cost')")).number);
    try testing.expectEqual(@as(f64, 9), (try f.eval("sum(stats)")).number);
    try testing.expectEqual(@as(f64, 3), (try f.eval("avg(units, 'cost')")).number);
    try testing.expectEqual(@as(f64, 1), (try f.eval("min(units, 'cost')")).number);
    try testing.expectEqual(@as(f64, 7), (try f.eval("max(stats)")).number);
    try testing.expectEqual(@as(f64, 4), (try f.eval("max(level, 2)")).number);
    try testing.expectEqual(@as(f64, 2), (try f.eval("count(units, 'elite', true)")).number);
    try testing.expectEqualStrings("Fire, Flying", (try f.eval("join(tags, ', ')")).text);
    try testing.expectEqualStrings("3/5/1", (try f.eval("join(units, 'cost', '/')")).text);
    try testing.expectEqualStrings("Imp", (try f.eval("last(units).name")).text);
    // A param named like a built-in is still a plain name.
    try testing.expectEqual(@as(u16, 0), try f.checkCode("sum + 1"));

    try testing.expectEqual(@as(u16, 3103), try f.evalCode("avg(no_stats)"));
    try testing.expectEqual(@as(u16, 3102), try f.evalCode("last(none).tag"));
    try testing.expectEqual(@as(u16, 3002), try f.checkCode("sum(units, 'cots')"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("sum(units, 'name')"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("sum(units)"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("get(units, 'Orc', 0)"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("get(stats, 'Speed', 'x')"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("count(units, 'elite', 1)"));
    try testing.expectEqual(@as(u16, 3003), try f.checkCode("sum(level)"));
}

test "a design function hides a built-in of the same name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const scope: Scope = .{
        .arena = a,
        .params = &.{.{ .name = "level", .ty = .number }},
        .functions = &.{.{ .name = "sign", .args = &.{.{ .name = "t", .ty = .text }}, .ret = .text }},
        .layers = null,
    };
    try testing.expect((try testCheck(a, "sign('x')", &scope)) == .text);
    try expectProblem(a, "sign(level)", &scope, 3003);
}
