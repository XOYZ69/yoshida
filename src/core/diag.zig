//! Diagnostics: every problem the core finds, in one shape for the CLI, the
//! editor and the server (FORMAT.md section 9).

const std = @import("std");
const json = @import("json.zig");
const Allocator = std.mem.Allocator;

pub const Severity = enum {
    err,
    warning,
    hint,

    pub fn label(s: Severity) []const u8 {
        return switch (s) {
            .err => "error",
            .warning => "warning",
            .hint => "hint",
        };
    }
};

pub const Diagnostic = struct {
    severity: Severity,
    code: u16,
    /// Project-relative file, or "" when the problem is not tied to a file.
    file: []const u8,
    /// JSON Pointer into the file, e.g. "/layers/3/box/x".
    path: []const u8,
    /// 1-based line and column in the file; 0 when unknown.
    line: u32 = 0,
    col: u32 = 0,
    /// Byte range inside an expression string; equal values mean none.
    span_start: u32 = 0,
    span_end: u32 = 0,
    message: []const u8,
    hint: ?[]const u8 = null,
    /// Card the problem belongs to, for render-time problems.
    card: ?[]const u8 = null,
};

/// A source file, used to turn byte offsets into line and column.
pub const Source = struct {
    file: []const u8,
    text: []const u8,
};

pub const List = struct {
    arena: Allocator,
    items: std.ArrayList(Diagnostic) = .empty,

    pub fn init(arena: Allocator) List {
        return .{ .arena = arena };
    }

    pub fn add(self: *List, d: Diagnostic) Allocator.Error!void {
        for (self.items.items) |o| {
            if (o.code == d.code and o.line == d.line and o.col == d.col and
                std.mem.eql(u8, o.file, d.file) and std.mem.eql(u8, o.path, d.path) and
                std.mem.eql(u8, o.message, d.message) and optEql(o.card, d.card)) return;
        }
        try self.items.append(self.arena, d);
    }

    /// Adds a diagnostic located at byte `pos` of `src`.
    pub fn at(
        self: *List,
        severity: Severity,
        code: u16,
        src: Source,
        pos: ?u32,
        path: []const u8,
        message: []const u8,
        hint: ?[]const u8,
    ) Allocator.Error!void {
        var d: Diagnostic = .{
            .severity = severity,
            .code = code,
            .file = src.file,
            .path = path,
            .message = message,
            .hint = hint,
        };
        if (pos) |p| {
            const lc = json.lineCol(src.text, p);
            d.line = lc.line;
            d.col = lc.col;
        }
        try self.add(d);
    }

    pub fn fmt(self: *List, comptime f: []const u8, args: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.arena, f, args);
    }

    pub fn errorCount(self: *const List) usize {
        var n: usize = 0;
        for (self.items.items) |d| {
            if (d.severity == .err) n += 1;
        }
        return n;
    }

    pub fn count(self: *const List, sev: Severity) usize {
        var n: usize = 0;
        for (self.items.items) |d| {
            if (d.severity == sev) n += 1;
        }
        return n;
    }

    /// Human-readable output, one block per diagnostic.
    pub fn writeText(self: *const List, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.items.items) |d| {
            try w.print("{s}", .{if (d.file.len > 0) d.file else "<project>"});
            if (d.line > 0) try w.print(":{d}:{d}", .{ d.line, d.col });
            try w.print(": {s}[{d}]: ", .{ d.severity.label(), d.code });
            if (d.card) |c| try w.print("card {s}: ", .{c});
            try w.print("{s}\n", .{d.message});
            if (d.path.len > 0) try w.print("  at {s}", .{d.path});
            if (d.span_end > d.span_start) try w.print(" (expression bytes {d}..{d})", .{ d.span_start, d.span_end });
            if (d.path.len > 0 or d.span_end > d.span_start) try w.writeByte('\n');
            if (d.hint) |h| try w.print("  hint: {s}\n", .{h});
        }
    }

    pub fn writeJson(self: *const List, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeByte('[');
        for (self.items.items, 0..) |d, i| {
            if (i > 0) try w.writeByte(',');
            try writeOneJson(d, w);
        }
        try w.writeByte(']');
    }
};

pub fn writeOneJson(d: Diagnostic, w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.print("{{\"severity\":\"{s}\",\"code\":{d},\"file\":", .{ d.severity.label(), d.code });
    try json.writeString(w, d.file);
    try w.writeAll(",\"path\":");
    try json.writeString(w, d.path);
    try w.print(",\"line\":{d},\"col\":{d},\"span\":[{d},{d}],\"message\":", .{ d.line, d.col, d.span_start, d.span_end });
    try json.writeString(w, d.message);
    try w.writeAll(",\"hint\":");
    if (d.hint) |h| try json.writeString(w, h) else try w.writeAll("null");
    try w.writeAll(",\"card\":");
    if (d.card) |c| try json.writeString(w, c) else try w.writeAll("null");
    try w.writeByte('}');
}

fn optEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

/// Returns "did you mean 'x'?" for the closest option within a small edit
/// distance, or null.
pub fn suggest(arena: Allocator, name: []const u8, options: []const []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_d: usize = std.math.maxInt(usize);
    for (options) |o| {
        const d = distance(name, o);
        const limit = @max(1, @max(name.len, o.len) * 2 / 5);
        if (d <= limit and d < o.len and d < best_d) {
            best_d = d;
            best = o;
        }
    }
    if (best == null or best_d == 0) return null;
    return std.fmt.allocPrint(arena, "did you mean '{s}'?", .{best.?}) catch null;
}

/// Levenshtein distance for short ASCII names; longer names compare as far apart.
pub fn distance(a: []const u8, b: []const u8) usize {
    if (a.len > 63 or b.len > 63) return std.math.maxInt(usize) / 2;
    var prev: [64]usize = undefined;
    var cur: [64]usize = undefined;
    for (0..b.len + 1) |j| prev[j] = j;
    for (a, 0..) |ca, i| {
        cur[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (std.ascii.toLower(ca) == std.ascii.toLower(cb)) 0 else 1;
            cur[j + 1] = @min(@min(prev[j + 1] + 1, cur[j] + 1), prev[j] + cost);
        }
        @memcpy(prev[0 .. b.len + 1], cur[0 .. b.len + 1]);
    }
    return prev[b.len];
}

test "suggest" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("did you mean 'color'?", suggest(a, "colour", &.{ "fill", "color", "size" }).?);
    try std.testing.expect(suggest(a, "zzz", &.{ "fill", "color" }) == null);
}
