//! Canonical pretty-printer for the expression language (FORMAT.md section 6).
//!
//! The printer works from the parsed tree, so spacing, parentheses and
//! breaks come out the same whatever the author wrote. Literals keep their
//! source text (`0.50`, `10%`, quote style); everything else is rebuilt.
//! Parentheses are kept only where the Pratt parser would otherwise read a
//! different tree.

const std = @import("std");
const expr = @import("expr.zig");
const Allocator = std.mem.Allocator;
const Node = expr.Node;

pub const Options = struct { width: usize = 72, indent: []const u8 = "  " };

/// Canonical text for `n`, parsed from `src` (spans index into `src`). Minimal
/// parentheses; breaks across lines only when a line would exceed `width`.
pub fn print(arena: Allocator, n: *const Node, src: []const u8, opts: Options) Allocator.Error![]const u8 {
    var p: Printer = .{ .arena = arena, .src = src, .width = opts.width, .indent = opts.indent };
    try p.emit(n, 0, 0);
    return p.out.items;
}

/// Same, always on one line.
pub fn printFlat(arena: Allocator, n: *const Node, src: []const u8) Allocator.Error![]const u8 {
    var p: Printer = .{ .arena = arena, .src = src, .width = std.math.maxInt(usize), .indent = "" };
    try p.flat(n);
    return p.out.items;
}

/// Structural equality ignoring spans and `.paren` wrappers (used by tests and callers).
pub fn sameTree(a: *const Node, b: *const Node, src_a: []const u8, src_b: []const u8) bool {
    const x = unparen(a);
    const y = unparen(b);
    if (std.meta.activeTag(x.data) != std.meta.activeTag(y.data)) return false;
    return switch (x.data) {
        .number => |v| v == y.data.number,
        .unit => |u| u.value == y.data.unit.value and u.unit == y.data.unit.unit,
        .string => |s| std.mem.eql(u8, s, y.data.string),
        .boolean => |v| v == y.data.boolean,
        .color => |c| std.meta.eql(c, y.data.color),
        .name => |nm| std.mem.eql(u8, nm.text, y.data.name.text),
        .builtin => |bi| bi == y.data.builtin,
        .layer_ref => |lr| blk: {
            const ly = y.data.layer_ref;
            if (!std.mem.eql(u8, lr.id, ly.id) or lr.path.len != ly.path.len) break :blk false;
            for (lr.path, ly.path) |pa, pb| if (!std.mem.eql(u8, pa, pb)) break :blk false;
            if (lr.index) |ia| {
                const ib = ly.index orelse break :blk false;
                break :blk sameTree(ia, ib, src_a, src_b);
            }
            break :blk ly.index == null;
        },
        .field => |f| std.mem.eql(u8, f.name, y.data.field.name) and sameTree(f.obj, y.data.field.obj, src_a, src_b),
        .index => |ix| sameTree(ix.obj, y.data.index.obj, src_a, src_b) and sameTree(ix.idx, y.data.index.idx, src_a, src_b),
        .call => |c| c.func == y.data.call.func and sameList(c.args, y.data.call.args, src_a, src_b),
        .ucall => |c| std.mem.eql(u8, c.name, y.data.ucall.name) and sameList(c.args, y.data.ucall.args, src_a, src_b),
        .neg => |v| sameTree(v, y.data.neg, src_a, src_b),
        .not => |v| sameTree(v, y.data.not, src_a, src_b),
        .binary => |bn| bn.op == y.data.binary.op and
            sameTree(bn.l, y.data.binary.l, src_a, src_b) and
            sameTree(bn.r, y.data.binary.r, src_a, src_b),
        .cond => |cn| sameTree(cn.c, y.data.cond.c, src_a, src_b) and
            sameTree(cn.a, y.data.cond.a, src_a, src_b) and
            sameTree(cn.b, y.data.cond.b, src_a, src_b),
        .in_list => |l| sameTree(l.v, y.data.in_list.v, src_a, src_b) and
            sameList(l.items, y.data.in_list.items, src_a, src_b),
        .err => std.mem.eql(u8, src_a[x.start..x.end], src_b[y.start..y.end]),
        .paren => unreachable,
    };
}

fn sameList(a: []const *Node, b: []const *Node, src_a: []const u8, src_b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!sameTree(x, y, src_a, src_b)) return false;
    return true;
}

// ------------------------------------------------------------------ precedence

/// Precedence levels as the parser sees them. A child is printed without
/// parentheses only where the parser reads it back the same way.
const in_prec: u8 = 3;
const not_prec: u8 = 7;
const atom_prec: u8 = 9;

fn unparen(n: *const Node) *const Node {
    var cur = n;
    while (cur.data == .paren) cur = cur.data.paren;
    return cur;
}

fn opPrec(op: expr.BinOp) u8 {
    return switch (op) {
        .@"or" => 1,
        .@"and" => 2,
        .eq, .ne => 3,
        .lt, .le, .gt, .ge => 4,
        .add, .sub => 5,
        .mul, .div, .mod => 6,
    };
}

/// `n` must be unparenthesised.
fn prec(n: *const Node) u8 {
    return switch (n.data) {
        .cond => 0,
        .binary => |b| opPrec(b.op),
        .in_list => in_prec,
        .neg, .not => not_prec,
        else => atom_prec,
    };
}

/// The left operand of a left-associative binary at `level`. An `in` list
/// takes everything to its left as its own operand, so it never needs
/// parentheses here; its value does (see `wrapV`).
fn wrapLeft(level: u8, child: *const Node) bool {
    const c = unparen(child);
    if (c.data == .in_list) return false;
    return prec(c) < level;
}

/// The right operand of a binary at `level`. Equal precedence needs parens
/// for left associativity. From level 3 up, an `in` at the start of the
/// operand would be taken by the operand's parse, so it needs them too.
fn wrapRight(level: u8, child: *const Node) bool {
    const c = unparen(child);
    if (prec(c) <= level) return true;
    return level >= in_prec and bareIn(c);
}

/// True when the parser would read a bare `in` at the start of `n` in the
/// caller's right operand context.
fn bareIn(n: *const Node) bool {
    return switch (n.data) {
        .in_list => true,
        .binary => |b| blk: {
            const l = unparen(b.l);
            if (wrapLeft(opPrec(b.op), l)) break :blk false;
            break :blk bareIn(l);
        },
        else => false,
    };
}

fn wrapOperand(child: *const Node) bool {
    return prec(unparen(child)) < not_prec;
}

/// The receiver of `.name` or `[i]`: only these parse as postfix receivers.
fn wrapReceiver(child: *const Node) bool {
    return switch (unparen(child).data) {
        .name, .builtin, .call, .ucall, .string, .number, .unit, .field, .index => false,
        else => true,
    };
}

fn wrapV(child: *const Node) bool {
    return prec(unparen(child)) < in_prec;
}

fn isCond(child: *const Node) bool {
    return unparen(child).data == .cond;
}

fn builtinText(b: expr.Builtin) []const u8 {
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

// ------------------------------------------------------------------ printer

const Printer = struct {
    arena: Allocator,
    src: []const u8,
    width: usize,
    indent: []const u8,
    out: std.ArrayList(u8) = .empty,
    /// Column on the current line, not counting pending indentation.
    col: usize = 0,
    /// Indent level to write before the next text on a new line.
    pending: ?usize = null,

    const Mark = struct { len: usize, col: usize, pending: ?usize };

    fn mark(p: *const Printer) Mark {
        return .{ .len = p.out.items.len, .col = p.col, .pending = p.pending };
    }

    fn reset(p: *Printer, m: Mark) void {
        p.out.shrinkRetainingCapacity(m.len);
        p.col = m.col;
        p.pending = m.pending;
    }

    /// Column the next text would start at, indentation included.
    fn colNow(p: *const Printer) usize {
        if (p.pending) |lvl| return lvl * p.indent.len;
        return p.col;
    }

    fn put(p: *Printer, s: []const u8) Allocator.Error!void {
        if (s.len == 0) return;
        if (p.pending) |lvl| {
            for (0..lvl) |_| try p.out.appendSlice(p.arena, p.indent);
            p.col = lvl * p.indent.len;
            p.pending = null;
        }
        try p.out.appendSlice(p.arena, s);
        p.col += s.len;
    }

    fn newline(p: *Printer, lvl: usize) Allocator.Error!void {
        try p.out.append(p.arena, '\n');
        p.col = 0;
        p.pending = lvl;
    }

    // -- one line

    fn flatOperand(p: *Printer, child: *const Node, need: bool) Allocator.Error!void {
        if (need) {
            try p.put("(");
            try p.flat(child);
            try p.put(")");
        } else try p.flat(child);
    }

    fn flatArgs(p: *Printer, args: []const *Node) Allocator.Error!void {
        for (args, 0..) |a, i| {
            if (i > 0) try p.put(", ");
            try p.flat(a);
        }
    }

    fn flat(p: *Printer, n0: *const Node) Allocator.Error!void {
        const n = unparen(n0);
        switch (n.data) {
            .number, .unit, .color, .string, .err => try p.put(p.src[n.start..n.end]),
            .boolean => |b| try p.put(if (b) "true" else "false"),
            .name => |nm| try p.put(nm.text),
            .builtin => |b| try p.put(builtinText(b)),
            .layer_ref => |lr| {
                try p.put("@");
                try p.put(lr.id);
                if (lr.index) |idx| {
                    try p.put("[");
                    try p.flat(idx);
                    try p.put("]");
                }
                for (lr.path) |part| {
                    try p.put(".");
                    try p.put(part);
                }
            },
            .field => |f| {
                try p.flatOperand(f.obj, wrapReceiver(f.obj));
                try p.put(".");
                try p.put(f.name);
            },
            .index => |ix| {
                try p.flatOperand(ix.obj, wrapReceiver(ix.obj));
                try p.put("[");
                try p.flat(ix.idx);
                try p.put("]");
            },
            .call => |c| {
                try p.put(@tagName(c.func));
                try p.put("(");
                try p.flatArgs(c.args);
                try p.put(")");
            },
            .ucall => |c| {
                try p.put(c.name);
                try p.put("(");
                try p.flatArgs(c.args);
                try p.put(")");
            },
            .neg => |x| {
                try p.put("-");
                try p.flatOperand(x, wrapOperand(x));
            },
            .not => |x| {
                try p.put("not ");
                try p.flatOperand(x, wrapOperand(x));
            },
            .binary => |b| {
                const level = opPrec(b.op);
                try p.flatOperand(b.l, wrapLeft(level, b.l));
                try p.put(" ");
                try p.put(expr.opText(b.op));
                try p.put(" ");
                try p.flatOperand(b.r, wrapRight(level, b.r));
            },
            .cond => |c| {
                try p.flatOperand(c.c, isCond(c.c));
                try p.put(" ? ");
                try p.flatOperand(c.a, isCond(c.a));
                try p.put(" : ");
                try p.flat(c.b);
            },
            .in_list => |l| {
                try p.flatOperand(l.v, wrapV(l.v));
                try p.put(" in [");
                try p.flatArgs(l.items);
                try p.put("]");
            },
            .paren => unreachable,
        }
    }

    // -- breaking

    /// Writes `n` on the current line when it fits in `width` with `trail`
    /// more columns after it; otherwise breaks it, one level deeper than `lvl`
    /// for the parts that go on their own lines.
    fn emit(p: *Printer, n0: *const Node, lvl: usize, trail: usize) Allocator.Error!void {
        const n = unparen(n0);
        if (!breakable(n)) return p.flat(n);
        const m = p.mark();
        try p.flat(n);
        if (p.colNow() + trail <= p.width) return;
        p.reset(m);
        switch (n.data) {
            .cond => try p.breakCond(n, lvl, trail),
            .binary => try p.breakChain(n, lvl, trail),
            .in_list => |l| {
                try p.emitOperand(l.v, wrapV(l.v), lvl, 5);
                try p.put(" in [");
                try p.breakItems(l.items, lvl);
                try p.put("]");
            },
            .call => |c| {
                if (c.func == .match and c.args.len >= 4 and c.args.len % 2 == 0) {
                    try p.breakMatch(c.args, lvl);
                } else {
                    try p.breakArgs(@tagName(c.func), c.args, lvl);
                }
            },
            .ucall => |c| try p.breakArgs(c.name, c.args, lvl),
            .neg => |x| {
                try p.put("-");
                try p.emitOperand(x, wrapOperand(x), lvl, trail);
            },
            .not => |x| {
                try p.put("not ");
                try p.emitOperand(x, wrapOperand(x), lvl, trail);
            },
            .field => |f| {
                try p.emitOperand(f.obj, wrapReceiver(f.obj), lvl, f.name.len + 1);
                try p.put(".");
                try p.put(f.name);
            },
            .index => |ix| {
                try p.emitOperand(ix.obj, wrapReceiver(ix.obj), lvl, 1);
                try p.put("[");
                try p.emit(ix.idx, lvl, 1);
                try p.put("]");
            },
            else => unreachable,
        }
    }

    fn breakable(n: *const Node) bool {
        return switch (n.data) {
            .cond, .binary, .in_list, .call, .ucall, .neg, .not, .field, .index => true,
            else => false,
        };
    }

    fn emitOperand(p: *Printer, child: *const Node, need: bool, lvl: usize, trail: usize) Allocator.Error!void {
        if (need) {
            try p.put("(");
            try p.emit(child, lvl, trail + 1);
            try p.put(")");
        } else try p.emit(child, lvl, trail);
    }

    /// `c1 ? a1 :` / `c2 ? a2 :` / default, one clause per line at `lvl`.
    fn breakCond(p: *Printer, n: *const Node, lvl: usize, trail: usize) Allocator.Error!void {
        var cur = n;
        while (true) {
            const c = cur.data.cond;
            try p.emitOperand(c.c, isCond(c.c), lvl, 3);
            try p.put(" ? ");
            try p.emitOperand(c.a, isCond(c.a), lvl, 2);
            try p.put(" :");
            try p.newline(lvl);
            const next = unparen(c.b);
            if (next.data != .cond) {
                try p.emit(next, lvl, trail);
                return;
            }
            cur = next;
        }
    }

    /// Breaks before each operator of a chain of same-precedence binaries.
    fn breakChain(p: *Printer, n: *const Node, lvl: usize, trail: usize) Allocator.Error!void {
        const Pair = struct { op: expr.BinOp, r: *Node };
        var pairs: std.ArrayList(Pair) = .empty;
        const level = opPrec(n.data.binary.op);
        var cur = n;
        const left: *const Node = while (true) {
            const b = cur.data.binary;
            try pairs.append(p.arena, .{ .op = b.op, .r = b.r });
            const l = unparen(b.l);
            if (l.data == .binary and opPrec(l.data.binary.op) == level) {
                cur = l;
            } else break l;
        };
        try p.emitOperand(left, wrapLeft(level, left), lvl, 0);
        var j = pairs.items.len;
        while (j > 0) {
            j -= 1;
            const pr = pairs.items[j];
            try p.newline(lvl + 1);
            try p.put(expr.opText(pr.op));
            try p.put(" ");
            try p.emitOperand(pr.r, wrapRight(level, pr.r), lvl + 1, if (j == 0) trail else 0);
        }
    }

    fn breakItems(p: *Printer, items: []const *Node, lvl: usize) Allocator.Error!void {
        try p.newline(lvl + 1);
        for (items, 0..) |it, i| {
            const last = i + 1 == items.len;
            try p.emit(it, lvl + 1, if (last) 0 else 1);
            if (!last) {
                try p.put(",");
                try p.newline(lvl + 1);
            }
        }
        try p.newline(lvl);
    }

    fn breakArgs(p: *Printer, name: []const u8, args: []const *Node, lvl: usize) Allocator.Error!void {
        try p.put(name);
        try p.put("(");
        if (args.len == 0) return p.put(")");
        try p.breakItems(args, lvl);
        try p.put(")");
    }

    /// `match(` then the subject, one `key, result,` pair per line, then the default.
    fn breakMatch(p: *Printer, args: []const *Node, lvl: usize) Allocator.Error!void {
        try p.put("match(");
        try p.newline(lvl + 1);
        try p.emit(args[0], lvl + 1, 1);
        try p.put(",");
        var i: usize = 1;
        while (i + 2 < args.len) : (i += 2) {
            try p.newline(lvl + 1);
            try p.emit(args[i], lvl + 1, 2);
            try p.put(", ");
            try p.emit(args[i + 1], lvl + 1, 1);
            try p.put(",");
        }
        try p.newline(lvl + 1);
        try p.emit(args[args.len - 1], lvl + 1, 0);
        try p.newline(lvl);
        try p.put(")");
    }
};

// ------------------------------------------------------------------ tests

const testing = std.testing;

fn parseTest(arena: Allocator, src: []const u8) !*Node {
    var problem: ?expr.Problem = null;
    return expr.parse(arena, src, 0, &problem) catch |err| {
        std.debug.print("parse failed for '{s}': {?s}\n", .{ src, if (problem) |pr| pr.message else null });
        return err;
    };
}

fn expectFlat(src: []const u8, want: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const n = try parseTest(a, src);
    const got = try printFlat(a, n, src);
    try testing.expectEqualStrings(want, got);
    const back = try parseTest(a, got);
    try testing.expect(sameTree(n, back, src, got));
}

test "flat: parentheses only where they change the tree" {
    try expectFlat("(1 + 2) * 3", "(1 + 2) * 3");
    try expectFlat("1 + (2 * 3)", "1 + 2 * 3");
    try expectFlat("a - (b - c)", "a - (b - c)");
    try expectFlat("(a - b) - c", "a - b - c");
    try expectFlat("not (a == b)", "not (a == b)");
    try expectFlat("(not a) == b", "not a == b");
    try expectFlat("-(a + b)", "-(a + b)");
    try expectFlat("(a ? b : c) ? d : e", "(a ? b : c) ? d : e");
    try expectFlat("a ? b : (c ? d : e)", "a ? b : c ? d : e");
    try expectFlat("a ? (c ? d : e) : f", "a ? (c ? d : e) : f");
    try expectFlat("x == (y in [1, 2])", "x == (y in [1, 2])");
    try expectFlat("(@a.bounds.cx) + 1", "@a.bounds.cx + 1");
    try expectFlat("max( 1 ,2 )", "max(1, 2)");
    try expectFlat("0.50 + 10%", "0.50 + 10%");
    try expectFlat("(#FF0000)", "#FF0000");
    try expectFlat("with_alpha( gold ,0.3)", "with_alpha(gold, 0.3)");
    try expectFlat("stats[\"Speed\"]", "stats[\"Speed\"]");
    try expectFlat("'it\\'s'", "'it\\'s'");
}

test "flat: more precedence and receiver cases" {
    try expectFlat("(a + b).c", "(a + b).c");
    try expectFlat("(a).b", "a.b");
    try expectFlat("(#FF0000).x", "(#FF0000).x");
    try expectFlat("(-a).b", "(-a).b");
    try expectFlat("-a.b", "-a.b");
    try expectFlat("a and (b or c)", "a and (b or c)");
    try expectFlat("(a and b) or c", "a and b or c");
    try expectFlat("a * not b + 1", "a * not b + 1");
    try expectFlat("(x ? 1 : 2) + 3", "(x ? 1 : 2) + 3");
    try expectFlat("(v in [1]) == true", "v in [1] == true");
    try expectFlat("a == (v in [1] + 2)", "a == (v in [1] + 2)");
    try expectFlat("v in [a ? 1 : 2, -b]", "v in [a ? 1 : 2, -b]");
    try expectFlat("(a or b) in [true]", "(a or b) in [true]");
    try expectFlat("s[c ? 1 : 2]", "s[c ? 1 : 2]");
    try expectFlat("@a[i].bounds.cx * 2", "@a[i].bounds.cx * 2");
    try expectFlat("canvas.w / 2 - card.id", "canvas.w / 2 - card.id");
    try expectFlat("true and false", "true and false");
}

test "breaking: cond chain and match layout" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const chain = "r == 2 ? i : r == 3 ? i / 2 : r == 7 ? 0.25 : 0.5";
    const n = try parseTest(a, chain);
    const got = try print(a, n, chain, .{ .width = 30 });
    try testing.expectEqualStrings(
        \\r == 2 ? i :
        \\r == 3 ? i / 2 :
        \\r == 7 ? 0.25 :
        \\0.5
    , got);
    try testing.expect(sameTree(n, try parseTest(a, got), chain, got));

    const m = "match(k, 'start', c_start, 'finish', c_finish, 'safe', c_safe, 'skip', c_skip, 'back', c_back, 'forward', c_forward, 'shortcut', c_shortcut, 'dare', c_dare, c_plain)";
    try testing.expectEqual(@as(usize, 165), m.len);
    const mn = try parseTest(a, m);
    const mgot = try print(a, mn, m, .{ .width = 72 });
    try testing.expectEqualStrings(
        \\match(
        \\  k,
        \\  'start', c_start,
        \\  'finish', c_finish,
        \\  'safe', c_safe,
        \\  'skip', c_skip,
        \\  'back', c_back,
        \\  'forward', c_forward,
        \\  'shortcut', c_shortcut,
        \\  'dare', c_dare,
        \\  c_plain
        \\)
    , mgot);
    try testing.expect(sameTree(mn, try parseTest(a, mgot), m, mgot));
}

test "breaking: and/or chains, calls and lists" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const logic = "a == 1 or b == 2";
    const got = try print(a, try parseTest(a, logic), logic, .{ .width = 14 });
    try testing.expectEqualStrings("a == 1\n  or b == 2", got);

    const call = "with_alpha(gold, 0.3)";
    const cgot = try print(a, try parseTest(a, call), call, .{ .width = 10 });
    try testing.expectEqualStrings("with_alpha(\n  gold,\n  0.3\n)", cgot);

    const list = "k in ['alpha', 'beta', 'gamma']";
    const lgot = try print(a, try parseTest(a, list), list, .{ .width = 18 });
    try testing.expectEqualStrings("k in [\n  'alpha',\n  'beta',\n  'gamma'\n]", lgot);
}

fn decodeCorpusLine(arena: Allocator, line: []const u8) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '\\' and i + 1 < line.len) {
            i += 1;
            try out.append(arena, if (line[i] == 'n') '\n' else line[i]);
        } else try out.append(arena, line[i]);
    }
    return out.items;
}

test "corpus: printed text re-parses to the same tree" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const corpus = @embedFile("testdata/expr-corpus.txt");
    var parsed: usize = 0;
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    _ = lines.next(); // the header comment
    while (lines.next()) |raw| {
        if (raw.len == 0) continue;
        const x = try decodeCorpusLine(a, raw);
        var problem: ?expr.Problem = null;
        const n = expr.parse(a, x, 0, &problem) catch continue;
        parsed += 1;

        const widths = [_]usize{ 72, 24 };
        for (widths) |w| {
            const p1 = try print(a, n, x, .{ .width = w });
            const back = try parseTest(a, p1);
            try testing.expect(sameTree(back, n, p1, x));
            const again = try print(a, back, p1, .{ .width = w });
            try testing.expectEqualStrings(p1, again);
        }

        const f = try printFlat(a, n, x);
        const fback = try parseTest(a, f);
        try testing.expect(sameTree(fback, n, f, x));
        try testing.expectEqualStrings(f, try printFlat(a, fback, f));
    }
    // 411 of the 559 lines in testdata/expr-corpus.txt parse.
    try testing.expectEqual(@as(usize, 411), parsed);
}
