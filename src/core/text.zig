//! Fonts (stb_truetype) and text layout: line breaks, greedy word wrap,
//! alignment, justification and max_lines truncation (FORMAT.md section 5.5).

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

pub const Line = struct {
    text: []const u8,
    width: f32,
    /// Stretch to the wrap width (justify, not the last line of a paragraph).
    stretch: bool,
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
};

pub fn layout(arena: Allocator, f: *const Font, text: []const u8, o: Options) Allocator.Error!Layout {
    const sc = f.scale(o.size);
    var lines: std.ArrayList(Line) = .empty;
    var paras = std.mem.splitScalar(u8, text, '\n');
    while (paras.next()) |para_raw| {
        const para = std.mem.trimEnd(u8, para_raw, "\r");
        const wrap = o.wrap orelse {
            try lines.append(arena, .{ .text = para, .width = f.measure(para, o.size), .stretch = false });
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
                if (f.measure(candidate, o.size) > wrap) {
                    const t = para[st..end];
                    try lines.append(arena, .{ .text = t, .width = f.measure(t, o.size), .stretch = o.justify });
                    start = ws;
                }
            } else start = ws;
            end = we;
        }
        if (start) |st| {
            const t = para[st..end];
            try lines.append(arena, .{ .text = t, .width = f.measure(t, o.size), .stretch = false });
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
            const t = try std.mem.concat(arena, u8, &.{ std.mem.trimEnd(u8, base, " "), ell });
            const wdt = f.measure(t, o.size);
            if (o.wrap == null or wdt <= o.wrap.? or base.len == 0) {
                last.* = .{ .text = t, .width = wdt, .stretch = false };
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
        while (it.next()) |cp| {
            if (f.missing(cp)) missing = true;
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

/// Draws a laid-out block whose top-left corner is at (left, top). With
/// `outline`, every glyph first gets an outline of that width around it.
pub fn draw(gpa: Allocator, b: *raster.Bitmap, f: *const Font, l: *const Layout, left: f32, top: f32, alignment: Align, p: raster.Paint, outline: ?Outline) Allocator.Error!void {
    if (outline) |o| if (o.width > 0) try drawPass(gpa, b, f, l, left, top, alignment, o.paint, o.width);
    try drawPass(gpa, b, f, l, left, top, alignment, p, null);
}

fn drawPass(gpa: Allocator, b: *raster.Bitmap, f: *const Font, l: *const Layout, left: f32, top: f32, alignment: Align, p: raster.Paint, outline: ?f32) Allocator.Error!void {
    var mask: std.ArrayList(u8) = .empty;
    defer mask.deinit(gpa);
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
        var it = codepoints(ln.text);
        while (it.next()) |cp| {
            const g = f.pick(cp);
            const sc = g.scale(l.size);
            if (prev) |pv| if (prev_font == g) {
                x += @as(f32, @floatFromInt(g.kern(pv, cp))) * sc;
            };
            prev = cp;
            prev_font = g;
            if (cp != ' ') {
                if (outline) |w| {
                    drawOutline(b, g, cp, sc, x, baseline, w, p);
                } else try drawGlyph(gpa, &mask, b, g, cp, sc, x, baseline, p);
            }
            x += @as(f32, @floatFromInt(g.advance(cp))) * sc;
            if (cp == ' ') x += gap_extra;
        }
    }
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
    try std.testing.expect(std.mem.endsWith(u8, cut.lines[1].text, "\u{2026}"));
}
