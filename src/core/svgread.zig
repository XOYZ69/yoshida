//! Prepares an SVG file for nanosvg, which draws shapes and gradients but
//! knows neither `<text>` nor `<pattern>`, and reads gradient coordinates
//! given as fractions of the bounding box (`x2="1"`) as pixels
//! (docs: site/content/docs/layer-image.md).
//!
//! `prepare` rewrites the document: text becomes glyph outlines, gradients
//! get their inherited attributes and percentages, and each pattern is
//! taken out and returned, with a marker gradient left under its id so
//! that nanosvg keeps the shapes that use it. The caller (render.zig)
//! draws those shapes itself, from tiles made with `tileDoc`.

const std = @import("std");
const c = @import("c.zig");
const text = @import("text.zig");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

/// The font for a `font-family` list; `faux_bold` when bold was asked for
/// and the font is a regular one.
pub const Found = struct { font: *const text.Font, faux_bold: bool = false };

pub const Fonts = struct {
    ptr: *anyopaque,
    findFn: *const fn (ptr: *anyopaque, families: []const u8, bold: bool, italic: bool) Allocator.Error!Found,

    fn find(f: Fonts, families: []const u8, bold: bool, italic: bool) Allocator.Error!Found {
        return f.findFn(f.ptr, families, bold, italic);
    }
};

/// An affine transform as nanosvg stores it:
/// x' = x*t[0] + y*t[2] + t[4], y' = x*t[1] + y*t[3] + t[5].
pub const Xform = [6]f32;
pub const identity: Xform = .{ 1, 0, 0, 1, 0, 0 };

pub fn apply(t: Xform, x: f32, y: f32) [2]f32 {
    return .{ x * t[0] + y * t[2] + t[4], x * t[1] + y * t[3] + t[5] };
}

/// The transform that does `a` first and `b` second.
pub fn then(a: Xform, b: Xform) Xform {
    return .{
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
        a[4] * b[0] + a[5] * b[2] + b[4],
        a[4] * b[1] + a[5] * b[3] + b[5],
    };
}

pub fn inverse(t: Xform) ?Xform {
    const det = t[0] * t[3] - t[2] * t[1];
    if (@abs(det) < 1e-12 or !std.math.isFinite(det)) return null;
    const k = 1 / det;
    return .{
        t[3] * k,
        -t[1] * k,
        -t[2] * k,
        t[0] * k,
        (t[2] * t[5] - t[3] * t[4]) * k,
        (t[1] * t[4] - t[0] * t[5]) * k,
    };
}

/// A length that may be a percentage.
const Len = struct { v: f32 = 0, pct: bool = false };

pub const Pattern = struct {
    id: []const u8,
    x: Len = .{},
    y: Len = .{},
    w: Len = .{},
    h: Len = .{},
    /// `patternUnits`: x, y, width and height are fractions of the bounding
    /// box of the shape (the default) or user units.
    bbox_units: bool = true,
    /// `patternContentUnits`: the content is in bounding box fractions.
    content_bbox: bool = false,
    transform: Xform = identity,
    view_box: ?[]const u8 = null,
    aspect: ?[]const u8 = null,
    /// The elements inside the pattern, as written.
    body: []const u8 = "",

    pub const Tile = struct { x: f32, y: f32, w: f32, h: f32 };

    /// The tile in the pattern's own coordinates, for a shape whose
    /// bounding box is `bbox` (x0, y0, x1, y1); null when it has no area.
    pub fn tile(p: *const Pattern, bbox: [4]f32, view: [2]f32) ?Tile {
        const bw = bbox[2] - bbox[0];
        const bh = bbox[3] - bbox[1];
        const t: Tile = if (p.bbox_units) .{
            .x = bbox[0] + frac(p.x) * bw,
            .y = bbox[1] + frac(p.y) * bh,
            .w = frac(p.w) * bw,
            .h = frac(p.h) * bh,
        } else .{
            .x = user(p.x, view[0]),
            .y = user(p.y, view[1]),
            .w = user(p.w, view[0]),
            .h = user(p.h, view[1]),
        };
        if (!(t.w > 0 and t.h > 0) or !std.math.isFinite(t.w + t.h + t.x + t.y)) return null;
        return t;
    }

    fn frac(l: Len) f32 {
        return if (l.pct) l.v / 100 else l.v;
    }

    fn user(l: Len, ref: f32) f32 {
        return if (l.pct) l.v / 100 * ref else l.v;
    }
};

pub const Prepared = struct {
    /// The document for nanosvg, which changes it while parsing.
    doc: [:0]u8,
    patterns: []const Pattern = &.{},
    /// The gradients, patterns and style sheets of the file as written,
    /// for the tile documents.
    defs: []const u8 = "",
    /// Width and height of the root view box (or size), for percentages.
    view: [2]f32 = .{ 0, 0 },

    pub fn pattern(p: *const Prepared, id: []const u8) ?*const Pattern {
        for (p.patterns) |*pt| if (std.mem.eql(u8, pt.id, id)) return pt;
        return null;
    }
};

/// True when the file has something `prepare` changes. Other files go to
/// nanosvg as they are.
pub fn needed(src: []const u8) bool {
    return std.mem.indexOf(u8, src, "<text") != null or
        std.mem.indexOf(u8, src, "<pattern") != null or
        std.mem.indexOf(u8, src, "Gradient") != null;
}

/// Rewrites `src` for nanosvg. Without `fonts` text is left out; without
/// `keep_patterns` shapes filled with a pattern are not painted.
pub fn prepare(arena: Allocator, src: []const u8, fonts: ?Fonts, keep_patterns: bool) Allocator.Error!Prepared {
    var p: Prep = .{ .arena = arena, .src = src, .fonts = fonts, .keep_patterns = keep_patterns, .out = .init(arena) };
    return p.run() catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        // The allocating writer has no other failure.
        error.WriteFailed => error.OutOfMemory,
    };
}

/// The standalone document of one pattern tile, `tw` x `th` pixels.
/// `bbox` is the bounding box of the shape that is filled.
pub fn tileDoc(arena: Allocator, prep: *const Prepared, p: *const Pattern, t: Pattern.Tile, bbox: [4]f32, tw: u32, th: u32) Allocator.Error![]u8 {
    var out: Writer.Allocating = .init(arena);
    const w = &out.writer;
    tileDocTo(w, prep, p, t, bbox, tw, th) catch return error.OutOfMemory;
    return out.written();
}

fn tileDocTo(w: *Writer, prep: *const Prepared, p: *const Pattern, t: Pattern.Tile, bbox: [4]f32, tw: u32, th: u32) Writer.Error!void {
    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"{d}\" height=\"{d}\"", .{ tw, th });
    if (p.view_box) |vb| {
        try w.print(" viewBox=\"{s}\" preserveAspectRatio=\"{s}\">", .{ vb, p.aspect orelse "xMidYMid meet" });
    } else {
        try w.print(" viewBox=\"0 0 {d} {d}\" preserveAspectRatio=\"none\">", .{ t.w, t.h });
    }
    try w.print("<defs>{s}</defs>", .{prep.defs});
    const scaled = p.content_bbox and p.view_box == null;
    if (scaled) try w.print("<g transform=\"scale({d} {d})\">", .{ bbox[2] - bbox[0], bbox[3] - bbox[1] });
    try w.writeAll(p.body);
    if (scaled) try w.writeAll("</g>");
    try w.writeAll("</svg>");
}

// ------------------------------------------------------------------ XML

const Tok = struct {
    kind: Kind,
    start: usize,
    end: usize,
    /// Element name of an open or close tag.
    name: []const u8 = "",
    /// The attributes of an open tag, as written.
    attrs: []const u8 = "",
    self_closing: bool = false,
    /// Character data (still with entities) or the inside of a CDATA section.
    body: []const u8 = "",

    const Kind = enum { open, close, chars, cdata, other };
};

const Scanner = struct {
    s: []const u8,
    i: usize = 0,

    fn next(sc: *Scanner) ?Tok {
        const s = sc.s;
        const start = sc.i;
        if (start >= s.len) return null;
        if (s[start] != '<' or !tagStart(s, start)) {
            var j = start + 1;
            while (j < s.len and !(s[j] == '<' and tagStart(s, j))) j += 1;
            sc.i = j;
            return .{ .kind = .chars, .start = start, .end = j, .body = s[start..j] };
        }
        const rest = s[start..];
        if (std.mem.startsWith(u8, rest, "<!--")) return sc.until(start, "-->", .other, 4);
        if (std.mem.startsWith(u8, rest, "<![CDATA[")) return sc.until(start, "]]>", .cdata, 9);
        if (std.mem.startsWith(u8, rest, "<?")) return sc.until(start, "?>", .other, 2);
        if (rest.len > 1 and rest[1] == '!') {
            // A doctype, with or without an internal subset in [ ].
            var depth: usize = 0;
            var j = start + 2;
            while (j < s.len) : (j += 1) {
                if (s[j] == '[') depth += 1;
                if (s[j] == ']' and depth > 0) depth -= 1;
                if (s[j] == '>' and depth == 0) break;
            }
            sc.i = @min(j + 1, s.len);
            return .{ .kind = .other, .start = start, .end = sc.i };
        }
        if (rest.len > 1 and rest[1] == '/') {
            const j = std.mem.indexOfScalarPos(u8, s, start, '>') orelse s.len;
            sc.i = @min(j + 1, s.len);
            return .{ .kind = .close, .start = start, .end = sc.i, .name = std.mem.trim(u8, s[start + 2 .. j], " \t\r\n") };
        }
        var j = start + 1;
        while (j < s.len and !isSpace(s[j]) and s[j] != '/' and s[j] != '>') j += 1;
        const name = s[start + 1 .. j];
        const attrs_start = j;
        var quote: u8 = 0;
        while (j < s.len) : (j += 1) {
            if (quote != 0) {
                if (s[j] == quote) quote = 0;
            } else if (s[j] == '"' or s[j] == '\'') {
                quote = s[j];
            } else if (s[j] == '>') break;
        }
        const self_closing = j > attrs_start and j <= s.len and s[j - 1] == '/';
        sc.i = @min(j + 1, s.len);
        return .{
            .kind = .open,
            .start = start,
            .end = sc.i,
            .name = name,
            .attrs = s[attrs_start..if (self_closing) j - 1 else j],
            .self_closing = self_closing,
        };
    }

    fn until(sc: *Scanner, start: usize, close: []const u8, kind: Tok.Kind, skip: usize) Tok {
        const j = std.mem.indexOfPos(u8, sc.s, @min(start + skip, sc.s.len), close);
        const body_end = j orelse sc.s.len;
        sc.i = if (j) |x| x + close.len else sc.s.len;
        return .{ .kind = kind, .start = start, .end = sc.i, .body = sc.s[@min(start + skip, body_end)..body_end] };
    }

    /// Moves past the element that `open` starts; returns where its close
    /// tag begins (the end of its content).
    fn skipElement(sc: *Scanner, open: Tok) usize {
        if (open.self_closing) return open.end;
        var depth: usize = 1;
        while (sc.next()) |t| switch (t.kind) {
            .open => {
                if (!t.self_closing) depth += 1;
            },
            .close => {
                depth -= 1;
                if (depth == 0) return t.start;
            },
            else => {},
        };
        return sc.s.len;
    }
};

/// `<` starts markup when a name, `/`, `!` or `?` follows.
fn tagStart(s: []const u8, i: usize) bool {
    if (i + 1 >= s.len) return false;
    const ch = s[i + 1];
    return std.ascii.isAlphabetic(ch) or ch == '/' or ch == '!' or ch == '?' or ch == '_' or ch >= 0x80;
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

const AttrIter = struct {
    s: []const u8,
    i: usize = 0,

    const Attr = struct { name: []const u8, value: []const u8 };

    fn next(it: *AttrIter) ?Attr {
        const s = it.s;
        var i = it.i;
        while (i < s.len and (isSpace(s[i]) or s[i] == '/')) i += 1;
        const name_start = i;
        while (i < s.len and !isSpace(s[i]) and s[i] != '=') i += 1;
        if (i == name_start) return null;
        const name = s[name_start..i];
        while (i < s.len and isSpace(s[i])) i += 1;
        if (i >= s.len or s[i] != '=') {
            it.i = i;
            return .{ .name = name, .value = "" };
        }
        i += 1;
        while (i < s.len and isSpace(s[i])) i += 1;
        if (i >= s.len) {
            it.i = i;
            return .{ .name = name, .value = "" };
        }
        if (s[i] == '"' or s[i] == '\'') {
            const end = std.mem.indexOfScalarPos(u8, s, i + 1, s[i]) orelse s.len;
            it.i = @min(end + 1, s.len);
            return .{ .name = name, .value = s[i + 1 .. end] };
        }
        const value_start = i;
        while (i < s.len and !isSpace(s[i])) i += 1;
        it.i = i;
        return .{ .name = name, .value = s[value_start..i] };
    }
};

/// The value of attribute `name`, as written (entities are not decoded).
fn attr(attrs: []const u8, name: []const u8) ?[]const u8 {
    var it: AttrIter = .{ .s = attrs };
    while (it.next()) |a| if (std.mem.eql(u8, a.name, name)) return a.value;
    return null;
}

/// The id an `href` or `xlink:href` points at.
fn hrefId(attrs: []const u8) ?[]const u8 {
    const v = attr(attrs, "xlink:href") orelse attr(attrs, "href") orelse return null;
    const t = std.mem.trim(u8, v, " \t\r\n");
    return if (t.len > 1 and t[0] == '#') t[1..] else null;
}

/// Appends `s` with its character and entity references replaced.
fn decodeTo(arena: Allocator, out: *std.ArrayList(u8), s: []const u8) Allocator.Error!void {
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] != '&') {
            try out.append(arena, s[i]);
            i += 1;
            continue;
        }
        const end = std.mem.indexOfScalarPos(u8, s, i, ';') orelse {
            try out.append(arena, '&');
            i += 1;
            continue;
        };
        const name = s[i + 1 .. end];
        var cp: ?u21 = null;
        if (name.len > 1 and name[0] == '#') {
            const hex = name[1] == 'x' or name[1] == 'X';
            cp = std.fmt.parseInt(u21, name[if (hex) 2 else 1..], if (hex) 16 else 10) catch null;
        } else if (std.mem.eql(u8, name, "amp")) {
            cp = '&';
        } else if (std.mem.eql(u8, name, "lt")) {
            cp = '<';
        } else if (std.mem.eql(u8, name, "gt")) {
            cp = '>';
        } else if (std.mem.eql(u8, name, "quot")) {
            cp = '"';
        } else if (std.mem.eql(u8, name, "apos")) {
            cp = '\'';
        } else if (std.mem.eql(u8, name, "nbsp")) {
            cp = 0xA0;
        }
        var buf: [4]u8 = undefined;
        const n = if (cp) |x| std.unicode.utf8Encode(x, &buf) catch 0 else 0;
        if (n == 0) {
            try out.append(arena, '&');
            i += 1;
            continue;
        }
        try out.appendSlice(arena, buf[0..n]);
        i = end + 1;
    }
}

// ------------------------------------------------------------------ values

/// The number at the start of `s` and what follows it.
fn number(s: []const u8) ?struct { v: f32, rest: []const u8 } {
    var i: usize = 0;
    if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
    const digits = i;
    while (i < s.len and (std.ascii.isDigit(s[i]) or s[i] == '.')) i += 1;
    if (i == digits) return null;
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        var j = i + 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        if (j < s.len and std.ascii.isDigit(s[j])) {
            while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
            i = j;
        }
    }
    const v = std.fmt.parseFloat(f32, s[0..i]) catch return null;
    if (!std.math.isFinite(v)) return null;
    return .{ .v = v, .rest = s[i..] };
}

/// A length in pixels (96 per inch, as nanosvg is asked to read the file).
/// `em` is the font size and `ref` what a percentage is of.
fn length(raw: []const u8, em: f32, ref: f32) ?f32 {
    const n = number(std.mem.trim(u8, raw, " \t\r\n")) orelse return null;
    const unit = std.mem.trim(u8, n.rest, " \t\r\n");
    const k: f32 = if (unit.len == 0 or std.mem.eql(u8, unit, "px"))
        1
    else if (std.mem.eql(u8, unit, "pt"))
        96.0 / 72.0
    else if (std.mem.eql(u8, unit, "pc"))
        16
    else if (std.mem.eql(u8, unit, "mm"))
        96.0 / 25.4
    else if (std.mem.eql(u8, unit, "cm"))
        96.0 / 2.54
    else if (std.mem.eql(u8, unit, "in"))
        96
    else if (std.mem.eql(u8, unit, "em"))
        em
    else if (std.mem.eql(u8, unit, "ex"))
        em * 0.5
    else if (std.mem.eql(u8, unit, "%"))
        ref / 100
    else
        return null;
    return n.v * k;
}

/// The first length of a list such as `x="10 20 30"`.
fn firstLength(raw: []const u8, em: f32, ref: f32) ?f32 {
    var it = std.mem.tokenizeAny(u8, raw, " \t\r\n,");
    return length(it.next() orelse return null, em, ref);
}

fn len(raw: []const u8) ?Len {
    const t = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.endsWith(u8, t, "%")) {
        const n = number(t) orelse return null;
        return .{ .v = n.v, .pct = true };
    }
    return .{ .v = length(t, 16, 0) orelse return null };
}

/// A `transform` list: matrix, translate, scale, rotate, skewX and skewY.
fn parseTransform(raw: []const u8) Xform {
    var t = identity;
    var s = raw;
    while (true) {
        s = std.mem.trimStart(u8, s, " \t\r\n,");
        const open = std.mem.indexOfScalar(u8, s, '(') orelse break;
        const close = std.mem.indexOfScalarPos(u8, s, open, ')') orelse break;
        const name = std.mem.trim(u8, s[0..open], " \t\r\n");
        var a: [6]f32 = @splat(0);
        var n: usize = 0;
        var it = std.mem.tokenizeAny(u8, s[open + 1 .. close], " \t\r\n,");
        while (it.next()) |tok| {
            if (n == a.len) break;
            a[n] = (number(tok) orelse break).v;
            n += 1;
        }
        s = s[close + 1 ..];
        var m = identity;
        if (std.mem.eql(u8, name, "matrix") and n == 6) {
            m = a;
        } else if (std.mem.eql(u8, name, "translate") and n >= 1) {
            m[4] = a[0];
            m[5] = if (n > 1) a[1] else 0;
        } else if (std.mem.eql(u8, name, "scale") and n >= 1) {
            m[0] = a[0];
            m[3] = if (n > 1) a[1] else a[0];
        } else if (std.mem.eql(u8, name, "rotate") and n >= 1) {
            const r = a[0] * std.math.pi / 180.0;
            const rot: Xform = .{ @cos(r), @sin(r), -@sin(r), @cos(r), 0, 0 };
            m = if (n >= 3) then(then(.{ 1, 0, 0, 1, -a[1], -a[2] }, rot), .{ 1, 0, 0, 1, a[1], a[2] }) else rot;
        } else if (std.mem.eql(u8, name, "skewX") and n >= 1) {
            m[2] = @tan(a[0] * std.math.pi / 180.0);
        } else if (std.mem.eql(u8, name, "skewY") and n >= 1) {
            m[1] = @tan(a[0] * std.math.pi / 180.0);
        }
        // The leftmost transform is the outermost one.
        t = then(m, t);
    }
    return t;
}

// ------------------------------------------------------------------ style

const Anchor = enum { start, middle, end };

/// The inherited properties text needs.
const Style = struct {
    family: []const u8 = "",
    size: f32 = 16,
    bold: bool = false,
    italic: bool = false,
    anchor: Anchor = .start,
    spacing: f32 = 0,
    /// The fill paint as written; nanosvg's default is black.
    fill: []const u8 = "#000",
    stroked: bool = false,
    /// `xml:space="preserve"`.
    preserve: bool = false,

    fn set(st: *Style, name: []const u8, raw: []const u8) void {
        const v = std.mem.trim(u8, raw, " \t\r\n");
        if (v.len == 0 or std.mem.eql(u8, v, "inherit")) return;
        if (std.mem.eql(u8, name, "font-family")) {
            st.family = v;
        } else if (std.mem.eql(u8, name, "font-size")) {
            if (length(v, st.size, st.size)) |x| {
                if (x >= 0) st.size = x;
            }
        } else if (std.mem.eql(u8, name, "font-weight")) {
            if (std.mem.eql(u8, v, "bold") or std.mem.eql(u8, v, "bolder")) {
                st.bold = true;
            } else if (std.mem.eql(u8, v, "normal") or std.mem.eql(u8, v, "lighter")) {
                st.bold = false;
            } else if (number(v)) |n| {
                st.bold = n.v >= 600;
            }
        } else if (std.mem.eql(u8, name, "font-style")) {
            st.italic = std.mem.eql(u8, v, "italic") or std.mem.startsWith(u8, v, "oblique");
        } else if (std.mem.eql(u8, name, "text-anchor")) {
            st.anchor = std.meta.stringToEnum(Anchor, v) orelse st.anchor;
        } else if (std.mem.eql(u8, name, "letter-spacing")) {
            st.spacing = length(v, st.size, st.size) orelse 0;
        } else if (std.mem.eql(u8, name, "fill")) {
            st.fill = v;
        } else if (std.mem.eql(u8, name, "stroke")) {
            st.stroked = !std.mem.eql(u8, v, "none");
        } else if (std.mem.eql(u8, name, "xml:space")) {
            st.preserve = std.mem.eql(u8, v, "preserve");
        }
    }

    fn setList(st: *Style, decls: []const u8) void {
        var it = std.mem.splitScalar(u8, decls, ';');
        while (it.next()) |d| {
            const colon = std.mem.indexOfScalar(u8, d, ':') orelse continue;
            st.set(std.mem.trim(u8, d[0..colon], " \t\r\n"), d[colon + 1 ..]);
        }
    }
};

/// One rule of a `<style>` sheet: `.name` or an element name, as nanosvg
/// reads them too.
const Rule = struct { selector: []const u8, decls: []const u8 };

// ------------------------------------------------------------------ prepare

const Gradient = struct { id: []const u8, attrs: []const u8 };

const PatternSrc = struct { id: []const u8, attrs: []const u8, body: []const u8 };

const Prep = struct {
    arena: Allocator,
    src: []const u8,
    fonts: ?Fonts,
    keep_patterns: bool,
    out: Writer.Allocating,
    gradients: std.ArrayList(Gradient) = .empty,
    pattern_srcs: std.ArrayList(PatternSrc) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    defs: std.ArrayList(u8) = .empty,
    view: [2]f32 = .{ 0, 0 },

    const Error = Allocator.Error || Writer.Error;

    fn run(p: *Prep) Error!Prepared {
        try p.collect();
        try p.rewrite();
        const written = p.out.written();
        const doc = try p.arena.allocSentinel(u8, written.len, 0);
        @memcpy(doc, written);
        // nanosvg stops at a 0 byte anyway.
        for (doc) |*b| if (b.* == 0) {
            b.* = ' ';
        };
        var patterns: std.ArrayList(Pattern) = .empty;
        if (p.keep_patterns) for (p.pattern_srcs.items) |ps| {
            if (ps.id.len == 0) continue;
            try patterns.append(p.arena, p.resolvePattern(ps));
        };
        return .{ .doc = doc, .patterns = patterns.items, .defs = p.defs.items, .view = p.view };
    }

    /// First pass: the gradients, patterns and style rules of the file.
    fn collect(p: *Prep) Error!void {
        var sc: Scanner = .{ .s = p.src };
        var root = true;
        while (sc.next()) |t| {
            if (t.kind != .open) continue;
            if (root and std.mem.eql(u8, t.name, "svg")) {
                root = false;
                p.rootView(t.attrs);
            } else if (isGradient(t.name)) {
                try p.gradients.append(p.arena, .{ .id = attr(t.attrs, "id") orelse "", .attrs = t.attrs });
                _ = try p.defsElement(&sc, t);
            } else if (std.mem.eql(u8, t.name, "pattern")) {
                const end = try p.defsElement(&sc, t);
                try p.pattern_srcs.append(p.arena, .{ .id = attr(t.attrs, "id") orelse "", .attrs = t.attrs, .body = p.src[@min(t.end, end)..end] });
            } else if (std.mem.eql(u8, t.name, "style")) {
                const end = try p.defsElement(&sc, t);
                try p.styleSheet(p.src[@min(t.end, end)..end]);
            }
        }
    }

    /// Skips the element and keeps it, as written, for the tile documents.
    fn defsElement(p: *Prep, sc: *Scanner, open: Tok) Error!usize {
        const end = sc.skipElement(open);
        try p.defs.appendSlice(p.arena, p.src[open.start..sc.i]);
        return end;
    }

    fn rootView(p: *Prep, attrs: []const u8) void {
        if (attr(attrs, "viewBox")) |vb| {
            var it = std.mem.tokenizeAny(u8, vb, " \t\r\n,");
            var v: [4]f32 = @splat(0);
            var n: usize = 0;
            while (it.next()) |tok| {
                if (n == 4) break;
                v[n] = (number(tok) orelse break).v;
                n += 1;
            }
            if (n == 4) {
                p.view = .{ v[2], v[3] };
                return;
            }
        }
        p.view = .{
            if (attr(attrs, "width")) |w| length(w, 16, 0) orelse 0 else 0,
            if (attr(attrs, "height")) |h| length(h, 16, 0) orelse 0 else 0,
        };
    }

    fn styleSheet(p: *Prep, raw: []const u8) Error!void {
        var css = std.mem.trim(u8, raw, " \t\r\n");
        if (std.mem.startsWith(u8, css, "<![CDATA[")) css = css[9..];
        var i: usize = 0;
        while (i < css.len) {
            const open = std.mem.indexOfScalarPos(u8, css, i, '{') orelse break;
            const close = std.mem.indexOfScalarPos(u8, css, open, '}') orelse break;
            var sel = std.mem.splitScalar(u8, css[i..open], ',');
            while (sel.next()) |s| {
                // A comment before the selector is not part of it.
                var name = std.mem.trim(u8, s, " \t\r\n");
                if (std.mem.lastIndexOf(u8, name, "*/")) |e| name = std.mem.trim(u8, name[e + 2 ..], " \t\r\n");
                if (name.len > 0) try p.rules.append(p.arena, .{ .selector = name, .decls = css[open + 1 .. close] });
            }
            i = close + 1;
        }
    }

    /// The style of an element: inherited, then its presentation
    /// attributes, the style sheet and its `style` attribute.
    fn styleOf(p: *const Prep, parent: Style, t: Tok) Style {
        var st = parent;
        var it: AttrIter = .{ .s = t.attrs };
        while (it.next()) |a| st.set(a.name, a.value);
        for (p.rules.items) |r| {
            if (r.selector[0] == '.') {
                var classes = std.mem.tokenizeAny(u8, attr(t.attrs, "class") orelse "", " \t\r\n");
                while (classes.next()) |cl| if (std.mem.eql(u8, cl, r.selector[1..])) st.setList(r.decls);
            } else if (std.mem.eql(u8, r.selector, t.name)) st.setList(r.decls);
        }
        if (attr(t.attrs, "style")) |s| st.setList(s);
        return st;
    }

    /// Second pass: copies the file, with gradients, patterns and text
    /// replaced.
    fn rewrite(p: *Prep) Error!void {
        const w = &p.out.writer;
        var sc: Scanner = .{ .s = p.src };
        var stack: std.ArrayList(Style) = .empty;
        try stack.append(p.arena, .{});
        var copied: usize = 0;
        while (sc.next()) |t| switch (t.kind) {
            .open => {
                const parent = stack.items[stack.items.len - 1];
                if (isGradient(t.name)) {
                    try w.writeAll(p.src[copied..t.start]);
                    try p.gradientTag(w, t);
                    copied = t.end;
                    if (!t.self_closing) try stack.append(p.arena, parent);
                } else if (std.mem.eql(u8, t.name, "pattern")) {
                    try w.writeAll(p.src[copied..t.start]);
                    _ = sc.skipElement(t);
                    copied = sc.i;
                    const id = attr(t.attrs, "id") orelse "";
                    // nanosvg keeps a shape whose paint is a gradient it
                    // knows; the gradient's transform then maps the image
                    // to the shape's own coordinates.
                    if (p.keep_patterns and id.len > 0) try w.print("<linearGradient id=\"{s}\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#000\"/></linearGradient>", .{id});
                } else if (std.mem.eql(u8, t.name, "text")) {
                    try w.writeAll(p.src[copied..t.start]);
                    try p.textElement(w, &sc, t, parent);
                    copied = sc.i;
                } else if (!t.self_closing) {
                    try stack.append(p.arena, p.styleOf(parent, t));
                }
            },
            .close => {
                if (stack.items.len > 1) _ = stack.pop();
            },
            else => {},
        };
        try w.writeAll(p.src[copied..]);
    }

    // -------------------------------------------------------- gradients

    fn isGradient(name: []const u8) bool {
        return std.mem.eql(u8, name, "linearGradient") or std.mem.eql(u8, name, "radialGradient");
    }

    fn gradientAttr(p: *const Prep, attrs: []const u8, name: []const u8) ?[]const u8 {
        var cur = attrs;
        var hops: usize = 0;
        while (hops < 32) : (hops += 1) {
            if (attr(cur, name)) |v| return v;
            const ref = hrefId(cur) orelse return null;
            cur = for (p.gradients.items) |g| {
                if (std.mem.eql(u8, g.id, ref)) break g.attrs;
            } else return null;
        }
        return null;
    }

    /// The open tag of a gradient with what nanosvg does not work out
    /// itself: attributes inherited through `href`, and bounding box
    /// fractions as percentages (it reads a plain `1` as one pixel).
    fn gradientTag(p: *const Prep, w: *Writer, t: Tok) Error!void {
        try w.print("<{s}", .{t.name});
        if (attr(t.attrs, "id")) |id| try w.print(" id=\"{s}\"", .{id});
        const units = p.gradientAttr(t.attrs, "gradientUnits");
        const bbox = units == null or std.mem.eql(u8, std.mem.trim(u8, units.?, " \t\r\n"), "objectBoundingBox");
        if (units) |u| try w.print(" gradientUnits=\"{s}\"", .{u});
        for ([_][]const u8{ "gradientTransform", "spreadMethod" }) |name| {
            if (p.gradientAttr(t.attrs, name)) |v| try w.print(" {s}=\"{s}\"", .{ name, v });
        }
        for ([_][]const u8{ "x1", "y1", "x2", "y2", "cx", "cy", "r", "fx", "fy" }) |name| {
            const raw = p.gradientAttr(t.attrs, name) orelse continue;
            const v = std.mem.trim(u8, raw, " \t\r\n");
            if (bbox) if (number(v)) |n| if (n.rest.len == 0) {
                try w.print(" {s}=\"{d}%\"", .{ name, n.v * 100 });
                continue;
            };
            try w.print(" {s}=\"{s}\"", .{ name, v });
        }
        // nanosvg follows this for the stops; it knows no plain `href`.
        if (hrefId(t.attrs)) |ref| try w.print(" xlink:href=\"#{s}\"", .{ref});
        try w.writeAll(if (t.self_closing) "/>" else ">");
    }

    // -------------------------------------------------------- patterns

    fn patternAttr(p: *const Prep, ps: PatternSrc, name: []const u8) ?[]const u8 {
        var cur = ps;
        var hops: usize = 0;
        while (hops < 32) : (hops += 1) {
            if (attr(cur.attrs, name)) |v| return v;
            cur = p.patternRef(cur) orelse return null;
        }
        return null;
    }

    fn patternRef(p: *const Prep, ps: PatternSrc) ?PatternSrc {
        const ref = hrefId(ps.attrs) orelse return null;
        for (p.pattern_srcs.items) |o| if (std.mem.eql(u8, o.id, ref)) return o;
        return null;
    }

    fn resolvePattern(p: *const Prep, ps: PatternSrc) Pattern {
        var out: Pattern = .{ .id = ps.id };
        if (p.patternAttr(ps, "x")) |v| out.x = len(v) orelse .{};
        if (p.patternAttr(ps, "y")) |v| out.y = len(v) orelse .{};
        if (p.patternAttr(ps, "width")) |v| out.w = len(v) orelse .{};
        if (p.patternAttr(ps, "height")) |v| out.h = len(v) orelse .{};
        if (p.patternAttr(ps, "patternUnits")) |v| out.bbox_units = !std.mem.eql(u8, std.mem.trim(u8, v, " \t\r\n"), "userSpaceOnUse");
        if (p.patternAttr(ps, "patternContentUnits")) |v| out.content_bbox = std.mem.eql(u8, std.mem.trim(u8, v, " \t\r\n"), "objectBoundingBox");
        if (p.patternAttr(ps, "patternTransform")) |v| out.transform = parseTransform(v);
        out.view_box = p.patternAttr(ps, "viewBox");
        out.aspect = p.patternAttr(ps, "preserveAspectRatio");
        // A pattern without content of its own draws the one it refers to.
        var cur = ps;
        var hops: usize = 0;
        while (hops < 32) : (hops += 1) {
            if (hasElements(cur.body)) break;
            cur = p.patternRef(cur) orelse break;
        }
        out.body = cur.body;
        return out;
    }

    fn hasElements(body: []const u8) bool {
        var sc: Scanner = .{ .s = body };
        while (sc.next()) |t| if (t.kind == .open) return true;
        return false;
    }

    // -------------------------------------------------------- text

    const Run = struct {
        chars: []const u8,
        style: Style,
        /// A new absolute position, and a shift, before this run.
        x: ?f32 = null,
        y: ?f32 = null,
        dx: f32 = 0,
        dy: f32 = 0,
        found: Found = undefined,
        width: f32 = 0,
        /// Where the run starts, once laid out.
        px: f32 = 0,
        py: f32 = 0,
    };

    const Event = union(enum) {
        /// The attributes of the `<text>` or `<tspan>`, for a `<g>` that
        /// carries its paint, transform and visibility to nanosvg.
        open: []const u8,
        close,
        run: usize,
    };

    const Pending = struct { x: ?f32 = null, y: ?f32 = null, dx: f32 = 0, dy: f32 = 0 };

    fn textElement(p: *Prep, w: *Writer, sc: *Scanner, open: Tok, parent: Style) Error!void {
        var events: std.ArrayList(Event) = .empty;
        var runs: std.ArrayList(Run) = .empty;
        var stack: std.ArrayList(Style) = .empty;
        var pending: Pending = .{};
        // Leading spaces are dropped, as after a space.
        var after_space = true;
        try stack.append(p.arena, p.styleOf(parent, open));
        p.position(&pending, open, stack.items[0]);
        try events.append(p.arena, .{ .open = open.attrs });
        if (!open.self_closing) while (sc.next()) |t| switch (t.kind) {
            .open => {
                const st = p.styleOf(stack.items[stack.items.len - 1], t);
                p.position(&pending, t, st);
                if (t.self_closing) continue;
                try stack.append(p.arena, st);
                try events.append(p.arena, .{ .open = t.attrs });
            },
            .close => {
                _ = stack.pop();
                try events.append(p.arena, .close);
                if (stack.items.len == 0) break;
            },
            .chars, .cdata => {
                const st = stack.items[stack.items.len - 1];
                var decoded: std.ArrayList(u8) = .empty;
                if (t.kind == .cdata) try decoded.appendSlice(p.arena, t.body) else try decodeTo(p.arena, &decoded, t.body);
                const chars = try p.spaces(decoded.items, st.preserve, &after_space);
                if (chars.len == 0) continue;
                try events.append(p.arena, .{ .run = runs.items.len });
                try runs.append(p.arena, .{ .chars = chars, .style = st, .x = pending.x, .y = pending.y, .dx = pending.dx, .dy = pending.dy });
                pending = .{};
            },
            .other => {},
        };
        // A file that ends inside the text: close what is open.
        for (stack.items) |_| try events.append(p.arena, .close);

        const fonts = p.fonts orelse return;
        if (runs.items.len == 0) return;
        // A space at the very end is dropped too.
        const last = &runs.items[runs.items.len - 1];
        if (!last.style.preserve and std.mem.endsWith(u8, last.chars, " ")) last.chars = last.chars[0 .. last.chars.len - 1];
        for (runs.items) |*r| {
            r.found = try fonts.find(r.style.family, r.style.bold, r.style.italic);
            r.width = measure(r.found.font, r.chars, r.style.size, r.style.spacing);
        }
        layoutRuns(runs.items);
        for (events.items) |e| switch (e) {
            .open => |attrs| try w.print("<g{s}{s}>", .{ if (attrs.len > 0 and !isSpace(attrs[0])) " " else "", attrs }),
            .close => try w.writeAll("</g>"),
            .run => |i| try p.runPath(w, &runs.items[i]),
        };
    }

    /// `x`, `y`, `dx` and `dy` of a `<text>` or `<tspan>`: the first value
    /// of each (a list would place single characters).
    fn position(p: *const Prep, pending: *Pending, t: Tok, st: Style) void {
        if (attr(t.attrs, "x")) |v| pending.x = firstLength(v, st.size, p.view[0]) orelse pending.x;
        if (attr(t.attrs, "y")) |v| pending.y = firstLength(v, st.size, p.view[1]) orelse pending.y;
        if (attr(t.attrs, "dx")) |v| pending.dx += firstLength(v, st.size, p.view[0]) orelse 0;
        if (attr(t.attrs, "dy")) |v| pending.dy += firstLength(v, st.size, p.view[1]) orelse 0;
    }

    /// White space as SVG treats it: line breaks and tabs are spaces, and
    /// unless it is preserved a run of spaces is one.
    fn spaces(p: *Prep, s: []const u8, preserve: bool, after_space: *bool) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (s) |ch| {
            const space = isSpace(ch);
            if (space and !preserve and after_space.*) continue;
            try out.append(p.arena, if (space) ' ' else ch);
            after_space.* = space;
        }
        return out.items;
    }

    /// Places the runs: a run with an `x` starts a chunk, and `text-anchor`
    /// moves the whole chunk.
    fn layoutRuns(runs: []Run) void {
        var x: f32 = 0;
        var y: f32 = 0;
        var i: usize = 0;
        while (i < runs.len) {
            var end = i + 1;
            while (end < runs.len and runs[end].x == null) end += 1;
            var total: f32 = 0;
            for (runs[i..end], 0..) |r, k| total += r.width + if (k > 0) r.dx else 0;
            x = (runs[i].x orelse x) + runs[i].dx - switch (runs[i].style.anchor) {
                .start => 0,
                .middle => total / 2,
                .end => total,
            };
            for (runs[i..end], 0..) |*r, k| {
                if (k > 0) x += r.dx;
                if (r.y) |v| y = v;
                y += r.dy;
                r.px = x;
                r.py = y;
                x += r.width;
            }
            i = end;
        }
    }

    fn measure(font: *const text.Font, s: []const u8, size: f32, spacing: f32) f32 {
        var total: f32 = 0;
        var prev: ?u21 = null;
        var prev_font: ?*const text.Font = null;
        var it = (std.unicode.Utf8View.init(s) catch return 0).iterator();
        while (it.nextCodepoint()) |cp| {
            const g = font.pick(cp);
            const sc = g.scale(size);
            if (prev) |q| if (prev_font == g) {
                total += @as(f32, @floatFromInt(g.kern(q, cp))) * sc;
            };
            total += @as(f32, @floatFromInt(g.advance(cp))) * sc + spacing;
            prev = cp;
            prev_font = g;
        }
        return total;
    }

    /// One run as a `<path>` of glyph outlines.
    fn runPath(p: *Prep, w: *Writer, r: *const Run) Error!void {
        _ = p;
        const size = r.style.size;
        if (!(size > 0) or size > 100000) return;
        var x = r.px;
        var prev: ?u21 = null;
        var prev_font: ?*const text.Font = null;
        var any = false;
        var it = (std.unicode.Utf8View.init(r.chars) catch return).iterator();
        while (it.nextCodepoint()) |cp| {
            const g = r.found.font.pick(cp);
            const sc = g.scale(size);
            if (prev) |q| if (prev_font == g) {
                x += @as(f32, @floatFromInt(g.kern(q, cp))) * sc;
            };
            prev = cp;
            prev_font = g;
            var verts: ?[*]c.stbtt_vertex = null;
            const n = if (cp == ' ') 0 else c.stbtt_GetGlyphShape(g.info.ptr, @intCast(g.glyphIndex(cp)), &verts);
            if (n > 0) {
                defer c.stbtt_FreeShape(g.info.ptr, verts);
                if (!any) try w.writeAll("<path d=\"");
                any = true;
                var open = false;
                for (verts.?[0..@intCast(n)]) |v| {
                    const px = x + @as(f32, @floatFromInt(v.x)) * sc;
                    const py = r.py - @as(f32, @floatFromInt(v.y)) * sc;
                    const cx = x + @as(f32, @floatFromInt(v.cx)) * sc;
                    const cy = r.py - @as(f32, @floatFromInt(v.cy)) * sc;
                    switch (v.kind) {
                        c.stbtt_vertex.move => {
                            if (open) try w.writeAll("Z");
                            open = true;
                            try w.print("M{d:.3} {d:.3}", .{ px, py });
                        },
                        c.stbtt_vertex.line => try w.print("L{d:.3} {d:.3}", .{ px, py }),
                        c.stbtt_vertex.quad => try w.print("Q{d:.3} {d:.3} {d:.3} {d:.3}", .{ cx, cy, px, py }),
                        c.stbtt_vertex.cubic => try w.print("C{d:.3} {d:.3} {d:.3} {d:.3} {d:.3} {d:.3}", .{
                            cx,                                      cy,
                            x + @as(f32, @floatFromInt(v.cx1)) * sc, r.py - @as(f32, @floatFromInt(v.cy1)) * sc,
                            px,                                      py,
                        }),
                        else => {},
                    }
                }
                if (open) try w.writeAll("Z");
            }
            x += @as(f32, @floatFromInt(g.advance(cp))) * sc + r.style.spacing;
        }
        if (!any) return;
        try w.writeAll("\"");
        // Bold from a regular font: an outline in the fill paint, when the
        // text has no outline of its own.
        const fill = r.style.fill;
        if (r.found.faux_bold and !r.style.stroked and !std.mem.eql(u8, fill, "none") and std.mem.indexOfAny(u8, fill, "\"<&") == null) {
            try w.print(" stroke=\"{s}\" stroke-width=\"{d:.3}\" stroke-linejoin=\"round\"", .{ fill, text.fauxBoldWidth(size) });
        }
        try w.writeAll("/>");
    }
};

// ------------------------------------------------------------------ tests

const TestFonts = struct {
    font: text.Font,
    asked: [64]u8 = undefined,
    asked_len: usize = 0,

    fn find(ptr: *anyopaque, families: []const u8, bold: bool, italic: bool) Allocator.Error!Found {
        _ = italic;
        const t: *TestFonts = @ptrCast(@alignCast(ptr));
        t.asked_len = @min(families.len, t.asked.len);
        @memcpy(t.asked[0..t.asked_len], families[0..t.asked_len]);
        return .{ .font = &t.font, .faux_bold = bold };
    }

    fn fonts(t: *TestFonts) Fonts {
        return .{ .ptr = t, .findFn = find };
    }
};

fn testPrepare(arena: Allocator, src: []const u8, tf: ?*TestFonts) !Prepared {
    return prepare(arena, src, if (tf) |t| t.fonts() else null, true);
}

test "a file without text, patterns and gradients is left alone" {
    try std.testing.expect(!needed("<svg><rect width=\"1\" height=\"1\"/></svg>"));
    try std.testing.expect(needed("<svg><text>a</text></svg>"));
    try std.testing.expect(needed("<svg><pattern id=\"p\"/></svg>"));
    try std.testing.expect(needed("<svg><linearGradient id=\"g\"/></svg>"));
}

test "bounding box fractions of a gradient become percentages" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const p = try testPrepare(arena_state.allocator(),
        \\<svg><linearGradient id="g" x1="0" y1="0.25" x2="1" y2="50%"><stop offset="0"/></linearGradient>
        \\<radialGradient id="u" gradientUnits="userSpaceOnUse" cx="5" cy="5" r="5"/></svg>
    , null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<linearGradient id=\"g\" x1=\"0%\" y1=\"25%\" x2=\"100%\" y2=\"50%\">") != null);
    // User space coordinates stay as they are.
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<radialGradient id=\"u\" gradientUnits=\"userSpaceOnUse\" cx=\"5\" cy=\"5\" r=\"5\"/>") != null);
}

test "a gradient inherits attributes through href" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const p = try testPrepare(arena_state.allocator(),
        \\<svg><linearGradient id="b" href="#a"/>
        \\<linearGradient id="a" gradientUnits="userSpaceOnUse" x1="1" x2="9" gradientTransform="rotate(90)"><stop offset="0"/></linearGradient></svg>
    , null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<linearGradient id=\"b\" gradientUnits=\"userSpaceOnUse\" gradientTransform=\"rotate(90)\" x1=\"1\" x2=\"9\" xlink:href=\"#a\"/>") != null);
}

test "a pattern is taken out and leaves a marker gradient" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\<svg viewBox="0 0 100 50"><defs>
        \\<pattern id="base" width="10" height="20" patternUnits="userSpaceOnUse"><rect width="5" height="20"/></pattern>
        \\<pattern id="turned" xlink:href="#base" patternTransform="translate(3 4)"/>
        \\<pattern id="box" width="0.5" height="25%"><circle r="1"/></pattern>
        \\</defs><rect width="100" height="50" fill="url(#turned)"/></svg>
    ;
    const p = try testPrepare(arena, src, null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<pattern") == null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<linearGradient id=\"turned\" gradientUnits=\"userSpaceOnUse\"") != null);
    try std.testing.expectEqual(@as(usize, 3), p.patterns.len);
    const turned = p.pattern("turned").?;
    // Size, units and content come from the pattern it refers to.
    try std.testing.expect(!turned.bbox_units);
    try std.testing.expectEqualStrings("<rect width=\"5\" height=\"20\"/>", turned.body);
    try std.testing.expectEqual(Pattern.Tile{ .x = 0, .y = 0, .w = 10, .h = 20 }, turned.tile(.{ 0, 0, 100, 50 }, p.view).?);
    try std.testing.expectEqual([2]f32{ 3, 4 }, apply(turned.transform, 0, 0));
    // Bounding box units: fractions of the shape.
    try std.testing.expectEqual(Pattern.Tile{ .x = 10, .y = 20, .w = 40, .h = 10 }, p.pattern("box").?.tile(.{ 10, 20, 90, 60 }, p.view).?);
    // The tile document has the content and the definitions of the file.
    const doc = try tileDoc(arena, &p, turned, turned.tile(.{ 0, 0, 100, 50 }, p.view).?, .{ 0, 0, 100, 50 }, 20, 40);
    try std.testing.expect(std.mem.startsWith(u8, doc, "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"20\" height=\"40\" viewBox=\"0 0 10 20\" preserveAspectRatio=\"none\"><defs><pattern id=\"base\""));
    try std.testing.expect(std.mem.endsWith(u8, doc, "</defs><rect width=\"5\" height=\"20\"/></svg>"));
    // Without patterns the shapes that use one are not painted.
    const plain = try prepare(arena, src, null, false);
    try std.testing.expectEqual(@as(usize, 0), plain.patterns.len);
    try std.testing.expect(std.mem.indexOf(u8, plain.doc, "linearGradient") == null);
}

test "transform lists" {
    const t = parseTransform("translate(10, 20) scale(2)");
    try std.testing.expectEqual([2]f32{ 12, 24 }, apply(t, 1, 2));
    const r = parseTransform("rotate(90 10 10)");
    const q = apply(r, 20, 10);
    try std.testing.expectApproxEqAbs(@as(f32, 10), q[0], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 20), q[1], 1e-4);
    const back = apply(inverse(t).?, 12, 24);
    try std.testing.expectEqual([2]f32{ 1, 2 }, back);
    try std.testing.expect(inverse(.{ 0, 0, 0, 0, 1, 1 }) == null);
}

test "text becomes outlines in a group with the element's attributes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var tf: TestFonts = .{ .font = (try text.Font.init(std.testing.allocator, @embedFile("assets/Lato-Regular.ttf"))).? };
    defer tf.font.deinit(std.testing.allocator);
    const p = try testPrepare(arena_state.allocator(),
        \\<svg><g font-family="Chip Sans" style="font-size: 20px"><text x="50" y="30" fill="#123" text-anchor="middle">M&#8364;</text></g></svg>
    , &tf);
    try std.testing.expectEqualStrings("Chip Sans", tf.asked[0..tf.asked_len]);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<text") == null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<g x=\"50\" y=\"30\" fill=\"#123\" text-anchor=\"middle\"><path d=\"M") != null);
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "/></g></g></svg>") != null);
    // Centred on x = 50: the outline starts within half the width of it.
    const width = Prep.measure(&tf.font, "M\u{20AC}", 20, 0);
    try std.testing.expect(width > 20 and width < 40);
    const d = p.doc[std.mem.indexOf(u8, p.doc, "d=\"M").? + 4 ..];
    const first_x = number(d).?.v;
    try std.testing.expect(first_x > 50 - width / 2 - 1 and first_x < 50 + width / 2);
}

test "text spaces, tspans and bold" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tf: TestFonts = .{ .font = (try text.Font.init(std.testing.allocator, @embedFile("assets/Lato-Regular.ttf"))).? };
    defer tf.font.deinit(std.testing.allocator);
    // One path per run; the tspan is a group of its own.
    const p = try testPrepare(arena,
        \\<svg><style>.b { font-weight: bold }</style><text y="10">
        \\  a   <tspan class="b" fill="red">b</tspan>
        \\</text></svg>
    , &tf);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, p.doc, "<path"));
    try std.testing.expect(std.mem.indexOf(u8, p.doc, "<g class=\"b\" fill=\"red\"><path d=\"") != null);
    // Bold from a regular font is an outline in the fill paint.
    try std.testing.expect(std.mem.indexOf(u8, p.doc, " stroke=\"red\" stroke-width=\"0.352\" stroke-linejoin=\"round\"/>") != null);
    // "a " then "b": the second run starts after the first and one space.
    var runs = [_]Prep.Run{
        .{ .chars = "a ", .style = .{}, .y = 10, .width = 12 },
        .{ .chars = "b", .style = .{}, .width = 8 },
        .{ .chars = "c", .style = .{ .anchor = .end }, .x = 100, .dy = 5, .width = 8 },
    };
    Prep.layoutRuns(&runs);
    try std.testing.expectEqual([3]f32{ 0, 12, 92 }, .{ runs[0].px, runs[1].px, runs[2].px });
    try std.testing.expectEqual([3]f32{ 10, 10, 15 }, .{ runs[0].py, runs[1].py, runs[2].py });
    // Without fonts the text is left out, and the file still closes.
    const none = try testPrepare(arena, "<svg><text>a<tspan>b</tspan></text><rect/></svg>", null);
    try std.testing.expectEqualStrings("<svg><rect/></svg>", none.doc);
}
