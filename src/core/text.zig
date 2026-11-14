//! Fonts (stb_truetype) and text layout: line breaks, greedy word wrap,
//! alignment, justification and max_lines truncation
//! (docs: site/content/docs/layer-text.md).

const std = @import("std");
const c = @import("c.zig");
const raster = @import("raster.zig");
const Allocator = std.mem.Allocator;

pub const Font = struct {
    data: []const u8,
    info: []align(16) u8,
    ascent: i32,
    descent: i32,
    line_gap: i32,
    /// Font used for code points this one has no glyph for (the default
    /// font, then the bundled symbol font).
    fallback: ?*const Font = null,

    /// `data` must outlive the font.
    pub fn init(gpa: Allocator, data: []const u8) Allocator.Error!?Font {
        if (data.len < 12) return null;
        const offset = c.stbtt_GetFontOffsetForIndex(data.ptr, 0);
        if (offset < 0) return null;
        const info = try gpa.alignedAlloc(u8, .@"16", @intCast(c.ystb_fontinfo_size()));
        if (c.stbtt_InitFont(info.ptr, data.ptr, offset) == 0) {
            gpa.free(info);
            return null;
        }
        var f: Font = .{ .data = data, .info = info, .ascent = 0, .descent = 0, .line_gap = 0 };
        var a: c_int = 0;
        var d: c_int = 0;
        var g: c_int = 0;
        c.stbtt_GetFontVMetrics(info.ptr, &a, &d, &g);
        f.ascent = a;
        f.descent = d;
        f.line_gap = g;
        return f;
    }

    pub fn deinit(f: *Font, gpa: Allocator) void {
        gpa.free(f.info);
    }

    /// Scale for a font size given as the em height in pixels.
    pub fn scale(f: *const Font, size: f32) f32 {
        return c.stbtt_ScaleForMappingEmToPixels(f.info.ptr, size);
    }

    /// The glyph index of `cp` (0, the missing-glyph box, when absent).
    pub fn glyphIndex(f: *const Font, cp: u21) u32 {
        return @intCast(c.stbtt_FindGlyphIndex(f.info.ptr, @intCast(cp)));
    }

    pub fn hasGlyph(f: *const Font, cp: u21) bool {
        return c.stbtt_FindGlyphIndex(f.info.ptr, @intCast(cp)) != 0;
    }

    fn advance(f: *const Font, cp: u21) i32 {
        var adv: c_int = 0;
        var lsb: c_int = 0;
        c.stbtt_GetCodepointHMetrics(f.info.ptr, @intCast(cp), &adv, &lsb);
        return adv;
    }

    fn kern(f: *const Font, a: u21, b: u21) i32 {
        return c.stbtt_GetCodepointKernAdvance(f.info.ptr, @intCast(a), @intCast(b));
    }

    /// The font that draws `cp`: this one, else the first fallback that has
    /// the glyph, else this one (which draws its missing-glyph box).
    pub fn pick(f: *const Font, cp: u21) *const Font {
        if (cp == ' ' or cp == '\t' or f.hasGlyph(cp)) return f;
        var fb = f.fallback;
        while (fb) |x| : (fb = x.fallback) if (x.hasGlyph(cp)) return x;
        return f;
    }

    /// True when neither this font nor a fallback has the glyph.
    pub fn missing(f: *const Font, cp: u21) bool {
        return cp != ' ' and !f.pick(cp).hasGlyph(cp);
    }

    /// Width in pixels of a single line at font size `size`.
    pub fn measure(f: *const Font, s: []const u8, size: f32) f32 {
        var total: f32 = 0;
        var prev: ?u21 = null;
        var prev_font: ?*const Font = null;
        var it = codepoints(s);
        while (it.next()) |cp| {
            const g = f.pick(cp);
            const sc = g.scale(size);
            if (prev) |p| if (prev_font == g) {
                total += @as(f32, @floatFromInt(g.kern(p, cp))) * sc;
            };
            total += @as(f32, @floatFromInt(g.advance(cp))) * sc;
            prev = cp;
            prev_font = g;
        }
        return total;
    }
};

const CpIter = struct {
    s: []const u8,
    i: usize = 0,

    fn next(it: *CpIter) ?u21 {
        if (it.i >= it.s.len) return null;
        const n = std.unicode.utf8ByteSequenceLength(it.s[it.i]) catch {
            it.i += 1;
            return 0xFFFD;
        };
        if (it.i + n > it.s.len) {
            it.i = it.s.len;
            return 0xFFFD;
        }
        const cp = std.unicode.utf8Decode(it.s[it.i .. it.i + n]) catch 0xFFFD;
        it.i += n;
        return cp;
    }
};

fn codepoints(s: []const u8) CpIter {
    return .{ .s = s };
}

/// Style bits of one byte of rich text.
pub const bold: u8 = 1;
pub const italic: u8 = 2;
pub const icon_bit: u8 = 4;

/// The code point that stands for an inline icon in rich text.
pub const icon_cp: u21 = 0xFFFC;

/// Text with bold, italic and inline icons (see `parseMarkup`). Layout and
/// walks look up the style of every byte by its position in `base`; text
/// outside `base` (an ellipsis) is regular.
pub const Rich = struct {
    base: []const u8,
    /// Per byte of `base`: `bold`, `italic` and `icon_bit`.
    style: []const u8,
    /// Per byte: the icon index where `icon_bit` is set.
    icon: []const u16,
    /// Fonts for regular, bold, italic and bold italic; a style without a
    /// font of its own uses the nearest one (see `faux`).
    fonts: [4]*const Font,
    /// Styles drawn bold by thickening the glyphs (no bold font).
    faux: [4]bool = .{ false, false, false, false },
    /// Width over height of every icon.
    icon_ratio: []const f32 = &.{},
    /// Icon height in font sizes.
    icon_scale: f32 = 1,

    /// The style of the byte at `p`, 0 when it is not in `base`.
    pub fn styleAt(r: *const Rich, p: [*]const u8) u8 {
        const a = @intFromPtr(r.base.ptr);
        const x = @intFromPtr(p);
        if (x < a or x >= a + r.base.len) return 0;
        return r.style[x - a];
    }

    fn iconAt(r: *const Rich, p: [*]const u8) u16 {
        return r.icon[@intFromPtr(p) - @intFromPtr(r.base.ptr)];
    }

    fn iconWidth(r: *const Rich, idx: u16, size: f32) f32 {
        const ratio: f32 = if (idx < r.icon_ratio.len) r.icon_ratio[idx] else 1;
        return size * r.icon_scale * ratio;
    }
};

/// Rich text from markup: `<b>`...`</b>`, `<i>`...`</i>` (nested as you
/// like) and `{icon:name}`. Anything else, unknown tags included, is text.
pub const Markup = struct {
    text: []const u8,
    style: []const u8,
    icon: []const u16,
    /// Icon names in order of first use; `icon` indexes into them.
    icons: []const []const u8,
};

pub fn parseMarkup(arena: Allocator, src: []const u8) Allocator.Error!Markup {
    var out: std.ArrayList(u8) = .empty;
    var style: std.ArrayList(u8) = .empty;
    var icon: std.ArrayList(u16) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var b: u32 = 0;
    var it: u32 = 0;
    var i: usize = 0;
    while (i < src.len) {
        const rest = src[i..];
        const tags = [_]struct { t: []const u8, d: *u32, open: bool }{
            .{ .t = "<b>", .d = &b, .open = true },
            .{ .t = "</b>", .d = &b, .open = false },
            .{ .t = "<i>", .d = &it, .open = true },
            .{ .t = "</i>", .d = &it, .open = false },
        };
        var matched = false;
        for (tags) |t| if (std.mem.startsWith(u8, rest, t.t)) {
            if (t.open) t.d.* += 1 else if (t.d.* > 0) t.d.* -= 1;
            i += t.t.len;
            matched = true;
            break;
        };
        if (matched) continue;
        if (std.mem.startsWith(u8, rest, "{icon:")) {
            if (std.mem.indexOfScalar(u8, rest, '}')) |end| {
                const name = rest[6..end];
                if (name.len > 0 and isIconName(name)) {
                    var idx: ?usize = null;
                    for (names.items, 0..) |n, k| if (std.mem.eql(u8, n, name)) {
                        idx = k;
                    };
                    if (idx == null) {
                        idx = names.items.len;
                        try names.append(arena, name);
                    }
                    var buf: [3]u8 = undefined;
                    const n = std.unicode.utf8Encode(icon_cp, &buf) catch unreachable;
                    const st: u8 = icon_bit | (if (b > 0) bold else 0) | (if (it > 0) italic else 0);
                    for (buf[0..n]) |ch| {
                        try out.append(arena, ch);
                        try style.append(arena, st);
                        try icon.append(arena, @intCast(idx.?));
                    }
                    i += end + 1;
                    continue;
                }
            }
        }
        try out.append(arena, src[i]);
        try style.append(arena, (if (b > 0) bold else 0) | (if (it > 0) italic else 0));
        try icon.append(arena, 0);
        i += 1;
    }
    return .{ .text = out.items, .style = style.items, .icon = icon.items, .icons = names.items };
}

/// Icon names: letters, digits, '_', '-' and '.'.
pub fn isIconName(s: []const u8) bool {
    for (s) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')) return false;
    return true;
}

/// What a line of text is measured and drawn with: one font, or rich text.
const Face = struct {
    font: *const Font,
    rich: ?*const Rich,

    const Item = struct {
        font: *const Font,
        style: u8,
        /// Icon index; the item is then not a glyph.
        icon: ?u16 = null,
    };

    fn item(f: Face, p: [*]const u8, cp: u21, style_override: ?u8) Item {
        const r = f.rich orelse return .{ .font = f.font.pick(cp), .style = 0 };
        const st = style_override orelse r.styleAt(p);
        if (st & icon_bit != 0 and style_override == null) return .{ .font = r.fonts[0], .style = st, .icon = r.iconAt(p) };
        return .{ .font = r.fonts[st & 3].pick(cp), .style = st & 3 };
    }

    /// Width of a line in pixels; `style` overrides the style of every
    /// byte (for an ellipsis).
    fn measure(f: Face, s: []const u8, size: f32, style: ?u8) f32 {
        if (f.rich == null) return f.font.measure(s, size);
        var total: f32 = 0;
        var prev: ?u21 = null;
        var prev_font: ?*const Font = null;
        var it = codepoints(s);
        while (true) {
            const at = it.i;
            const cp = it.next() orelse break;
            const x = f.item(s.ptr + at, cp, style);
            if (x.icon) |idx| {
                total += f.rich.?.iconWidth(idx, size);
                prev = null;
                prev_font = null;
                continue;
            }
            const g = x.font;
            const sc = g.scale(size);
            if (prev) |pv| if (prev_font == g) {
                total += @as(f32, @floatFromInt(g.kern(pv, cp))) * sc;
            };
            total += @as(f32, @floatFromInt(g.advance(cp))) * sc;
            prev = cp;
            prev_font = g;
        }
        return total;
    }

    fn missing(f: Face, p: [*]const u8, cp: u21, style: ?u8) bool {
        const x = f.item(p, cp, style);
        if (x.icon != null) return false;
        return cp != ' ' and !x.font.hasGlyph(cp);
    }
};

pub const Line = struct {
    text: []const u8,
    width: f32,
    /// Stretch to the wrap width (justify, not the last line of a paragraph).
    stretch: bool,
    /// Drawn after `text` when the block was cut by max_lines.
    ellipsis: []const u8 = "",
};

pub const Layout = struct {
    lines: []const Line,
    size: f32,
    /// Pixels from the block top to the first baseline.
    ascent: f32,
    /// Height of one line without spacing.
    line_h: f32,
    spacing: f32,
    block_w: f32,
    block_h: f32,
    truncated: bool,
    missing_glyphs: bool,
};

pub const Options = struct {
    size: f32,
    wrap: ?f32 = null,
    line_spacing: f32 = 4,
    max_lines: ?usize = null,
    justify: bool = false,
    /// Rich text: `text` must then be `rich.base`.
    rich: ?*const Rich = null,
};

pub fn layout(arena: Allocator, f: *const Font, text: []const u8, o: Options) Allocator.Error!Layout {
    const sc = f.scale(o.size);
    const face: Face = .{ .font = f, .rich = o.rich };
    var lines: std.ArrayList(Line) = .empty;
    var paras = std.mem.splitScalar(u8, text, '\n');
    while (paras.next()) |para_raw| {
        const para = std.mem.trimEnd(u8, para_raw, "\r");
        const wrap = o.wrap orelse {
            try lines.append(arena, .{ .text = para, .width = face.measure(para, o.size, null), .stretch = false });
            continue;
        };
        // Greedy wrap on spaces.
        var words = std.mem.tokenizeScalar(u8, para, ' ');
        var start: ?usize = null;
        var end: usize = 0;
        const first_line = lines.items.len;
        while (words.next()) |word| {
            const ws = @intFromPtr(word.ptr) - @intFromPtr(para.ptr);
            const we = ws + word.len;
            if (start) |st| {
                const candidate = para[st..we];
                if (face.measure(candidate, o.size, null) > wrap) {
                    const t = para[st..end];
                    try lines.append(arena, .{ .text = t, .width = face.measure(t, o.size, null), .stretch = o.justify });
                    start = ws;
                }
            } else start = ws;
            end = we;
        }
        if (start) |st| {
            const t = para[st..end];
            try lines.append(arena, .{ .text = t, .width = face.measure(t, o.size, null), .stretch = false });
        } else {
            try lines.append(arena, .{ .text = "", .width = 0, .stretch = false });
        }
        _ = first_line;
    }

    var truncated = false;
    if (o.max_lines) |ml| if (lines.items.len > ml and ml > 0) {
        truncated = true;
        lines.shrinkRetainingCapacity(ml);
        const last = &lines.items[ml - 1];
        const ell = if (!f.missing(0x2026)) "\u{2026}" else "...";
        var base = last.text;
        while (true) {
            const t = std.mem.trimEnd(u8, base, " ");
            const st: u8 = if (t.len > 0) (if (o.rich) |r| r.styleAt(t.ptr + t.len - 1) & 3 else 0) else 0;
            const wdt = face.measure(t, o.size, null) + face.measure(ell, o.size, st);
            if (o.wrap == null or wdt <= o.wrap.? or base.len == 0) {
                last.* = .{ .text = t, .width = wdt, .stretch = false, .ellipsis = ell };
                break;
            }
            // Drop the last code point.
            var cut = base.len - 1;
            while (cut > 0 and (base[cut] & 0xC0) == 0x80) cut -= 1;
            base = base[0..cut];
        }
    };

    var missing = false;
    var maxw: f32 = 0;
    for (lines.items) |ln| {
        maxw = @max(maxw, ln.width);
        var it = codepoints(ln.text);
        while (true) {
            const at = it.i;
            const cp = it.next() orelse break;
            if (face.missing(ln.text.ptr + at, cp, null)) missing = true;
        }
    }
    const ascent = @as(f32, @floatFromInt(f.ascent)) * sc;
    const line_h = @as(f32, @floatFromInt(f.ascent - f.descent)) * sc;
    const n: f32 = @floatFromInt(lines.items.len);
    return .{
        .lines = lines.items,
        .size = o.size,
        .ascent = ascent,
        .line_h = line_h,
        .spacing = o.line_spacing,
        .block_w = o.wrap orelse maxw,
        .block_h = n * line_h + @max(0, n - 1) * o.line_spacing,
        .truncated = truncated,
        .missing_glyphs = missing,
    };
}

pub const Align = enum { left, center, right, justify };

pub const Outline = struct { paint: raster.Paint, width: f32 };

/// Draws a laid-out block whose top-left corner is at (left, top), in bitmap
/// pixels. The layout and the outline width are in canvas pixels; `k` is
/// bitmap pixels per canvas pixel (1 except for proxy renders). With
/// `outline`, every glyph first gets an outline of that width around it.
pub fn draw(gpa: Allocator, b: *raster.Bitmap, f: *const Font, rich: ?*const Rich, l: *const Layout, left: f32, top: f32, alignment: Align, p: raster.Paint, outline: ?Outline, k: f32) Allocator.Error!void {
    if (outline) |o| if (o.width > 0) try drawPass(gpa, b, f, rich, l, left / k, top / k, alignment, o.paint, o.width, k);
    try drawPass(gpa, b, f, rich, l, left / k, top / k, alignment, p, null, k);
}

fn drawPass(gpa: Allocator, b: *raster.Bitmap, f: *const Font, rich: ?*const Rich, l: *const Layout, left: f32, top: f32, alignment: Align, p: raster.Paint, outline: ?f32, k: f32) Allocator.Error!void {
    var pass: Pass = .{ .gpa = gpa, .b = b, .p = p, .outline = outline, .k = k, .size = l.size };
    defer pass.mask.deinit(gpa);
    try walkRich(f, rich, l, left, top, alignment, &pass, Pass.glyph);
}

/// What `drawPass` does with every glyph of the walk.
const Pass = struct {
    gpa: Allocator,
    b: *raster.Bitmap,
    p: raster.Paint,
    outline: ?f32,
    k: f32,
    size: f32,
    mask: std.ArrayList(u8) = .empty,

    fn glyph(s: *Pass, g: Placed) Allocator.Error!void {
        if (g.icon != null) return;
        const sc = g.scale * s.k;
        const thick: f32 = if (g.faux_bold) fauxBoldWidth(s.size) else 0;
        if (s.outline) |w| {
            drawOutline(s.b, g.font, g.cp, sc, g.x * s.k, g.baseline * s.k, (w + thick) * s.k, s.p);
        } else {
            try drawGlyph(s.gpa, &s.mask, s.b, g.font, g.cp, sc, g.x * s.k, g.baseline * s.k, s.p);
            if (thick > 0) drawOutline(s.b, g.font, g.cp, sc, g.x * s.k, g.baseline * s.k, thick * s.k, s.p);
        }
    }
};

/// A glyph of a laid-out block: the font that draws it (a fallback for code
/// points the block's font lacks), its scale, and where its origin sits on
/// the baseline.
pub const Placed = struct {
    font: *const Font,
    cp: u21,
    scale: f32,
    x: f32,
    baseline: f32,
    /// Rich text: draw thicker (bold without a bold font).
    faux_bold: bool = false,
    /// Rich text: an inline icon (index into `Rich.icon_ratio`), `w` x `h`
    /// pixels with its left edge at `x`, centred on the capital letters.
    icon: ?u16 = null,
    w: f32 = 0,
    h: f32 = 0,

    /// Top of an icon.
    pub fn iconTop(p: Placed, size: f32) f32 {
        return p.baseline - 0.35 * size - p.h / 2;
    }
};

/// Calls `visit` for every glyph of the block whose top-left corner is at
/// (left, top), in drawing order and without spaces. The bitmap and the
/// vector scene both draw from this walk, so they place text identically.
pub fn walk(f: *const Font, l: *const Layout, left: f32, top: f32, alignment: Align, ctx: anytype, comptime visit: fn (@TypeOf(ctx), Placed) Allocator.Error!void) Allocator.Error!void {
    return walkRich(f, null, l, left, top, alignment, ctx, visit);
}

/// `walk` for rich text (the layout's `Options.rich`).
pub fn walkRich(f: *const Font, rich: ?*const Rich, l: *const Layout, left: f32, top: f32, alignment: Align, ctx: anytype, comptime visit: fn (@TypeOf(ctx), Placed) Allocator.Error!void) Allocator.Error!void {
    const face: Face = .{ .font = f, .rich = rich };
    for (l.lines, 0..) |ln, i| {
        const baseline = top + l.ascent + @as(f32, @floatFromInt(i)) * (l.line_h + l.spacing);
        var x = left + switch (alignment) {
            .left, .justify => 0,
            .center => (l.block_w - ln.width) / 2,
            .right => l.block_w - ln.width,
        };
        var gap_extra: f32 = 0;
        if (alignment == .justify and ln.stretch) {
            const spaces = std.mem.count(u8, ln.text, " ");
            if (spaces > 0) gap_extra = (l.block_w - ln.width) / @as(f32, @floatFromInt(spaces));
        }
        var prev: ?u21 = null;
        var prev_font: ?*const Font = null;
        const ell_style: u8 = if (ln.text.len > 0) (if (rich) |r| r.styleAt(ln.text.ptr + ln.text.len - 1) & 3 else 0) else 0;
        for ([_][]const u8{ ln.text, ln.ellipsis }, 0..) |seg, si| {
            const override: ?u8 = if (si == 1) ell_style else null;
            var it = codepoints(seg);
            while (true) {
                const at = it.i;
                const cp = it.next() orelse break;
                const item = face.item(seg.ptr + at, cp, override);
                if (item.icon) |idx| {
                    const w = rich.?.iconWidth(idx, l.size);
                    try visit(ctx, .{ .font = item.font, .cp = cp, .scale = 0, .x = x, .baseline = baseline, .icon = idx, .w = w, .h = l.size * rich.?.icon_scale });
                    x += w;
                    prev = null;
                    prev_font = null;
                    continue;
                }
                const g = item.font;
                const sc = g.scale(l.size);
                if (prev) |pv| if (prev_font == g) {
                    x += @as(f32, @floatFromInt(g.kern(pv, cp))) * sc;
                };
                prev = cp;
                prev_font = g;
                const faux = if (rich) |r| r.faux[item.style] else false;
                if (cp != ' ') try visit(ctx, .{ .font = g, .cp = cp, .scale = sc, .x = x, .baseline = baseline, .faux_bold = faux });
                x += @as(f32, @floatFromInt(g.advance(cp))) * sc;
                if (cp == ' ') x += gap_extra;
            }
        }
    }
}

/// Outline width that makes a glyph look bold, in pixels at font size `size`.
pub fn fauxBoldWidth(size: f32) f32 {
    return size * 0.022;
}

fn drawGlyph(gpa: Allocator, mask: *std.ArrayList(u8), b: *raster.Bitmap, g: *const Font, cp: u21, sc: f32, x: f32, baseline: f32, p: raster.Paint) Allocator.Error!void {
    const xf = @floor(x);
    const shift_x = x - xf;
    const yf = @floor(baseline);
    const shift_y = baseline - yf;
    var ix0: c_int = 0;
    var iy0: c_int = 0;
    var ix1: c_int = 0;
    var iy1: c_int = 0;
    c.stbtt_GetCodepointBitmapBoxSubpixel(g.info.ptr, @intCast(cp), sc, sc, shift_x, shift_y, &ix0, &iy0, &ix1, &iy1);
    const gw: usize = @intCast(@max(0, ix1 - ix0));
    const gh: usize = @intCast(@max(0, iy1 - iy0));
    if (gw == 0 or gh == 0) return;
    try mask.resize(gpa, gw * gh);
    @memset(mask.items, 0);
    c.stbtt_MakeCodepointBitmapSubpixel(g.info.ptr, mask.items.ptr, @intCast(gw), @intCast(gh), @intCast(gw), sc, sc, shift_x, shift_y, @intCast(cp));
    raster.blitMask(b, @as(i32, @intFromFloat(xf)) + ix0, @as(i32, @intFromFloat(yf)) + iy0, mask.items, gw, gh, p);
}

/// An outline `width` pixels wide around the glyph, from its signed
/// distance field (sampled bilinearly so it lines up with the glyph).
fn drawOutline(b: *raster.Bitmap, g: *const Font, cp: u21, sc: f32, x: f32, baseline: f32, width: f32, p: raster.Paint) void {
    const pad: c_int = @intFromFloat(@ceil(width) + 2);
    const dist_scale: f32 = 120.0 / @as(f32, @floatFromInt(pad));
    var w: c_int = 0;
    var h: c_int = 0;
    var xoff: c_int = 0;
    var yoff: c_int = 0;
    const sdf = c.stbtt_GetCodepointSDF(g.info.ptr, sc, @intCast(cp), pad, 128, dist_scale, &w, &h, &xoff, &yoff) orelse return;
    defer c.stbtt_FreeSDF(sdf, null);
    const uw: usize = @intCast(w);
    const uh: usize = @intCast(h);
    // SDF pixel (i, j) covers canvas x + xoff + i (its centre at + 0.5).
    const ox = x + @as(f32, @floatFromInt(xoff));
    const oy = baseline + @as(f32, @floatFromInt(yoff));
    const x0: i32 = @intFromFloat(@floor(ox));
    const y0: i32 = @intFromFloat(@floor(oy));
    const at = struct {
        fn f(m: [*]const u8, mw: usize, mh: usize, i: isize, j: isize) f32 {
            if (i < 0 or j < 0 or i >= mw or j >= mh) return 0;
            return @floatFromInt(m[@as(usize, @intCast(j)) * mw + @as(usize, @intCast(i))]);
        }
    }.f;
    var py: i32 = y0 - 1;
    while (py <= y0 + h) : (py += 1) {
        var px: i32 = x0 - 1;
        while (px <= x0 + w) : (px += 1) {
            // Position of this canvas pixel's centre in SDF pixel units.
            const u = @as(f32, @floatFromInt(px)) + 0.5 - ox - 0.5;
            const v = @as(f32, @floatFromInt(py)) + 0.5 - oy - 0.5;
            const iu = @floor(u);
            const iv = @floor(v);
            const fu = u - iu;
            const fv = v - iv;
            const ii: isize = @intFromFloat(iu);
            const jj: isize = @intFromFloat(iv);
            const s00 = at(sdf, uw, uh, ii, jj);
            const s10 = at(sdf, uw, uh, ii + 1, jj);
            const s01 = at(sdf, uw, uh, ii, jj + 1);
            const s11 = at(sdf, uw, uh, ii + 1, jj + 1);
            const sv = (s00 * (1 - fu) + s10 * fu) * (1 - fv) + (s01 * (1 - fu) + s11 * fu) * fv;
            const dist = (sv - 128) / dist_scale;
            const cov = std.math.clamp(dist + width + 0.5, 0, 1);
            if (cov > 0) b.blend(px, py, p, cov);
        }
    }
}

test "layout wraps and truncates" {
    const root = @import("root.zig");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var f = (try Font.init(a, root.default_font)).?;
    const one = try layout(a, &f, "Hello world", .{ .size = 20 });
    try std.testing.expectEqual(@as(usize, 1), one.lines.len);
    const wrapped = try layout(a, &f, "the quick brown fox jumps over the lazy dog", .{ .size = 20, .wrap = 120 });
    try std.testing.expect(wrapped.lines.len >= 3);
    for (wrapped.lines) |ln| try std.testing.expect(ln.width <= 120);
    const cut = try layout(a, &f, "the quick brown fox jumps over the lazy dog", .{ .size = 20, .wrap = 120, .max_lines = 2 });
    try std.testing.expectEqual(@as(usize, 2), cut.lines.len);
    try std.testing.expect(cut.truncated);
    try std.testing.expectEqualStrings("\u{2026}", cut.lines[1].ellipsis);
}

test "markup: bold, italic and icons" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const m = try parseMarkup(a, "Gain <b>2 {icon:steel}</b> <i>now</i> {icon:steel}{icon:gold} <3");
    try std.testing.expectEqualStrings("Gain 2 \u{FFFC} now \u{FFFC}\u{FFFC} <3", m.text);
    try std.testing.expectEqual(@as(usize, 2), m.icons.len);
    try std.testing.expectEqualStrings("steel", m.icons[0]);
    try std.testing.expectEqualStrings("gold", m.icons[1]);
    try std.testing.expectEqual(@as(u8, 0), m.style[0]);
    try std.testing.expectEqual(bold, m.style[5]);
    try std.testing.expectEqual(bold | icon_bit, m.style[7]);
    try std.testing.expectEqual(italic, m.style[11]);
}

test "rich layout measures icons and bold text" {
    const root = @import("root.zig");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var f = (try Font.init(a, root.default_font)).?;
    const m = try parseMarkup(a, "Gain 2 {icon:steel} and <b>more</b> words here");
    const rich: Rich = .{ .base = m.text, .style = m.style, .icon = m.icon, .fonts = .{ &f, &f, &f, &f }, .faux = .{ false, true, false, true }, .icon_ratio = &.{2} };
    const plain = try layout(a, &f, "Gain 2 and more words here", .{ .size = 20 });
    const lay = try layout(a, &f, m.text, .{ .size = 20, .rich = &rich });
    try std.testing.expect(!lay.missing_glyphs);
    // The icon is 40 px wide (twice the size) plus the space after it.
    const space = f.measure(" ", 20);
    try std.testing.expectApproxEqAbs(plain.block_w + 40 + space, lay.block_w, 0.01);
    // Wrapping and truncation keep the styles (the ellipsis is extra).
    const cut = try layout(a, &f, m.text, .{ .size = 20, .rich = &rich, .wrap = 120, .max_lines = 1 });
    try std.testing.expect(cut.truncated);
    try std.testing.expect(cut.lines[0].ellipsis.len > 0);
    try std.testing.expect(cut.lines[0].width <= 120);
}
