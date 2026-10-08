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

    /// Width in pixels of a single line.
    pub fn measure(f: *const Font, s: []const u8, sc: f32) f32 {
        var total: i32 = 0;
        var prev: ?u21 = null;
        var it = codepoints(s);
        while (it.next()) |cp| {
            if (prev) |p| total += f.kern(p, cp);
            total += f.advance(cp);
            prev = cp;
        }
        return @as(f32, @floatFromInt(total)) * sc;
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
    scale: f32,
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
            try lines.append(arena, .{ .text = para, .width = f.measure(para, sc), .stretch = false });
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
                if (f.measure(candidate, sc) > wrap) {
                    const t = para[st..end];
                    try lines.append(arena, .{ .text = t, .width = f.measure(t, sc), .stretch = o.justify });
                    start = ws;
                }
            } else start = ws;
            end = we;
        }
        if (start) |st| {
            const t = para[st..end];
            try lines.append(arena, .{ .text = t, .width = f.measure(t, sc), .stretch = false });
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
        const ell = if (f.hasGlyph(0x2026)) "\u{2026}" else "...";
        var base = last.text;
        while (true) {
            const t = try std.mem.concat(arena, u8, &.{ std.mem.trimEnd(u8, base, " "), ell });
            const wdt = f.measure(t, sc);
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
            if (cp != ' ' and !f.hasGlyph(cp)) missing = true;
        }
    }
    const ascent = @as(f32, @floatFromInt(f.ascent)) * sc;
    const line_h = @as(f32, @floatFromInt(f.ascent - f.descent)) * sc;
    const n: f32 = @floatFromInt(lines.items.len);
    return .{
        .lines = lines.items,
        .scale = sc,
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

/// Draws a laid-out block whose top-left corner is at (left, top).
pub fn draw(gpa: Allocator, b: *raster.Bitmap, f: *const Font, l: *const Layout, left: f32, top: f32, alignment: Align, p: raster.Paint) Allocator.Error!void {
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
        var it = codepoints(ln.text);
        while (it.next()) |cp| {
            if (prev) |pv| x += @as(f32, @floatFromInt(f.kern(pv, cp))) * l.scale;
            prev = cp;
            const xf = @floor(x);
            const shift_x = x - xf;
            const yf = @floor(baseline);
            const shift_y = baseline - yf;
            var ix0: c_int = 0;
            var iy0: c_int = 0;
            var ix1: c_int = 0;
            var iy1: c_int = 0;
            c.stbtt_GetCodepointBitmapBoxSubpixel(f.info.ptr, @intCast(cp), l.scale, l.scale, shift_x, shift_y, &ix0, &iy0, &ix1, &iy1);
            const gw: usize = @intCast(@max(0, ix1 - ix0));
            const gh: usize = @intCast(@max(0, iy1 - iy0));
            if (gw > 0 and gh > 0 and cp != ' ') {
                try mask.resize(gpa, gw * gh);
                @memset(mask.items, 0);
                c.stbtt_MakeCodepointBitmapSubpixel(f.info.ptr, mask.items.ptr, @intCast(gw), @intCast(gh), @intCast(gw), l.scale, l.scale, shift_x, shift_y, @intCast(cp));
                raster.blitMask(b, @as(i32, @intFromFloat(xf)) + ix0, @as(i32, @intFromFloat(yf)) + iy0, mask.items, gw, gh, p);
            }
            x += @as(f32, @floatFromInt(f.advance(cp))) * l.scale;
            if (cp == ' ') x += gap_extra;
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
