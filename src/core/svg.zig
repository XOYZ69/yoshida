//! SVG writer: a vector scene as a standalone SVG 1.1 file
//! (docs: site/content/docs/saving-images-and-privacy.md). Glyph outlines
//! are defined once per font and glyph, images once per source, and the
//! output is the same bytes for the same scene.

const std = @import("std");
const raster = @import("raster.zig");
const text = @import("text.zig");
const vector = @import("vector.zig");
const Color = @import("value.zig").Color;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

/// Writes the scene. The caller owns the result.
pub fn write(gpa: Allocator, scene: *const vector.Scene) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    var s: Svg = .{ .gpa = gpa, .arena = arena_state.allocator(), .scene = scene, .defs = .init(gpa), .body = .init(gpa) };
    defer s.defs.deinit();
    defer s.body.deinit();
    try s.items();
    var out: Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try s.document(&out.writer);
    return out.toOwnedSlice();
}

const Svg = struct {
    gpa: Allocator,
    /// Scratch for glyph outlines and encoded images; freed after the write.
    arena: Allocator,
    scene: *const vector.Scene,
    /// `<defs>` content, and the drawing.
    defs: Writer.Allocating,
    body: Writer.Allocating,
    fonts: std.ArrayList(*const text.Font) = .empty,
    glyphs: std.AutoHashMapUnmanaged(u64, void) = .empty,
    images: std.AutoHashMapUnmanaged(*const raster.Image, usize) = .empty,
    /// Next number for clip paths, masks and gradients.
    next_id: usize = 0,
    /// Per open group: how many elements it opened.
    open: std.ArrayList(u8) = .empty,

    fn document(s: *Svg, w: *Writer) !void {
        const sc = s.scene;
        const wpx: f64 = @floatFromInt(sc.width);
        const hpx: f64 = @floatFromInt(sc.height);
        try w.writeAll("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" ");
        // Millimetres when the print size is known, else pixels.
        if (sc.dpi > 0) {
            try w.writeAll("width=\"");
            try num(w, wpx / sc.dpi * 25.4);
            try w.writeAll("mm\" height=\"");
            try num(w, hpx / sc.dpi * 25.4);
            try w.writeAll("mm\"");
        } else {
            try w.print("width=\"{d}\" height=\"{d}\"", .{ sc.width, sc.height });
        }
        try w.print(" viewBox=\"0 0 {d} {d}\">\n", .{ sc.width, sc.height });
        if (s.defs.written().len > 0) {
            try w.writeAll("<defs>\n");
            try w.writeAll(s.defs.written());
            try w.writeAll("</defs>\n");
        }
        if (sc.background) |bg| {
            try w.print("<rect width=\"{d}\" height=\"{d}\"", .{ sc.width, sc.height });
            try paintAttr(w, "fill", bg);
            try w.writeAll("/>\n");
        }
        try w.writeAll(s.body.written());
        try w.writeAll("</svg>\n");
    }

    fn items(s: *Svg) !void {
        const list = s.scene.items.items;
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            switch (list[i]) {
                .fill => |f| {
                    // A fill and a stroke of the same path make one element.
                    if (i + 1 < list.len and list[i + 1] == .stroke and samePath(f.path, list[i + 1].stroke.path)) {
                        try s.pathElement(f.path, f.color, list[i + 1].stroke);
                        i += 1;
                    } else try s.pathElement(f.path, f.color, null);
                },
                .stroke => |st| try s.pathElement(st.path, null, st),
                .glyph => i = try s.glyphRun(list, i),
                .image => |im| try s.image(im),
                .raster => |r| try s.rasterImage(r),
                .begin => |b| try s.begin(b),
                .end => try s.closeGroup(),
            }
        }
        // Unbalanced input: close what is open so the file stays well formed.
        while (s.open.items.len > 0) try s.closeGroup();
    }

    fn pathElement(s: *Svg, path: vector.Path, fill: ?Color, stroke: ?vector.Stroke) !void {
        const w = &s.body.writer;
        try w.writeAll("<path d=\"");
        try pathData(w, path);
        try w.writeAll("\"");
        if (fill) |c| try paintAttr(w, "fill", c) else try w.writeAll(" fill=\"none\"");
        if (stroke) |st| {
            try paintAttr(w, "stroke", st.color);
            try w.writeAll(" stroke-width=\"");
            try num(w, st.width);
            try w.writeAll("\" stroke-linejoin=\"round\"");
            if (st.dash.len > 0) {
                // Round caps make the dashes round, as in the raster output.
                try w.writeAll(" stroke-linecap=\"round\" stroke-dasharray=\"");
                for (st.dash, 0..) |d, k| {
                    if (k > 0) try w.writeByte(' ');
                    try num(w, d);
                }
                try w.writeAll("\"");
            } else try w.writeAll(" stroke-linecap=\"round\"");
        }
        try w.writeAll("/>\n");
    }

    /// Consecutive glyphs of one color and outline share a group; returns the
    /// index of the last glyph written.
    fn glyphRun(s: *Svg, list: []const vector.Item, start: usize) !usize {
        const first = list[start].glyph;
        var end = start;
        while (end + 1 < list.len and list[end + 1] == .glyph and sameLook(first, list[end + 1].glyph)) end += 1;
        const w = &s.body.writer;
        try w.writeAll("<g");
        try paintAttr(w, "fill", first.color);
        if (first.stroke > 0) {
            try paintAttr(w, "stroke", first.color);
            try w.writeAll(" stroke-linejoin=\"round\"");
        }
        try w.writeAll(">\n");
        for (list[start .. end + 1]) |it| {
            const g = it.glyph;
            const id = try s.glyphDef(g.font, g.gid);
            try w.print("<use xlink:href=\"#{s}\" transform=\"matrix(", .{id});
            try numP(w, g.scale, 8);
            try w.writeAll(" 0 0 ");
            try numP(w, g.scale, 8);
            try w.writeByte(' ');
            try num(w, g.x);
            try w.writeByte(' ');
            try num(w, g.y);
            try w.writeAll(")\"");
            // The stroke width is in glyph units, which the matrix scales.
            if (g.stroke > 0 and g.scale > 0) {
                try w.writeAll(" stroke-width=\"");
                try numP(w, g.stroke / g.scale, 3);
                try w.writeAll("\"");
            }
            try w.writeAll("/>\n");
        }
        try w.writeAll("</g>\n");
        return end;
    }

    /// The id of a glyph's outline in `<defs>`, written on first use.
    fn glyphDef(s: *Svg, font: *const text.Font, gid: u32) ![]const u8 {
        var fi: usize = 0;
        while (fi < s.fonts.items.len and s.fonts.items[fi] != font) fi += 1;
        if (fi == s.fonts.items.len) try s.fonts.append(s.arena, font);
        const id = try std.fmt.allocPrint(s.arena, "g{d}-{d}", .{ fi, gid });
        const key = (@as(u64, fi) << 32) | gid;
        if ((try s.glyphs.getOrPut(s.arena, key)).found_existing) return id;
        const path = try vector.glyphPath(s.arena, font, gid);
        const w = &s.defs.writer;
        try w.print("<path id=\"{s}\" d=\"", .{id});
        try pathData(w, path);
        try w.writeAll("\"/>\n");
        return id;
    }

    fn image(s: *Svg, im: vector.Image) !void {
        const w = &s.body.writer;
        const id = try s.imageDef(im);
        const iw: f32 = @floatFromInt(im.image.w);
        const ih: f32 = @floatFromInt(im.image.h);
        const clipped = !(im.clip[0] == im.rect[0] and im.clip[1] == im.rect[1] and im.clip[2] == im.rect[0] + im.rect[2] and im.clip[3] == im.rect[1] + im.rect[3]);
        if (clipped) {
            const cid = try s.clipPath(im.clip);
            try w.print("<g clip-path=\"url(#c{d})\">\n", .{cid});
        }
        try w.print("<use xlink:href=\"#p{d}\" transform=\"matrix(", .{id});
        try numP(w, im.rect[2] / iw, 8);
        try w.writeAll(" 0 0 ");
        try numP(w, im.rect[3] / ih, 8);
        try w.writeByte(' ');
        try num(w, im.rect[0]);
        try w.writeByte(' ');
        try num(w, im.rect[1]);
        try w.writeAll(")\"");
        if (!im.smooth) try w.writeAll(" image-rendering=\"optimizeSpeed\" style=\"image-rendering:pixelated\"");
        try w.writeAll("/>\n");
        if (clipped) try w.writeAll("</g>\n");
    }

    /// The number of the image in `<defs>`, written on first use.
    fn imageDef(s: *Svg, im: vector.Image) !usize {
        const got = try s.images.getOrPut(s.arena, im.image);
        if (got.found_existing) return got.value_ptr.*;
        got.value_ptr.* = s.images.count() - 1;
        const w = &s.defs.writer;
        try w.print("<image id=\"p{d}\" width=\"{d}\" height=\"{d}\" preserveAspectRatio=\"none\" xlink:href=\"", .{ got.value_ptr.*, im.image.w, im.image.h });
        if (try vector.embeddable(s.gpa, im.bytes)) |e| {
            defer s.gpa.free(e.bytes);
            try dataUri(w, e.mime, e.bytes);
        } else {
            var view: raster.Bitmap = .{ .w = im.image.w, .h = im.image.h, .px = im.image.px };
            const png = try raster.encodePng(s.gpa, &view, false);
            defer s.gpa.free(png);
            try dataUri(w, "image/png", png);
        }
        try w.writeAll("\"/>\n");
        return got.value_ptr.*;
    }

    fn rasterImage(s: *Svg, r: vector.Raster) !void {
        const w = &s.body.writer;
        const k = r.scale;
        const png = try raster.encodePng(s.gpa, &r.bitmap, false);
        defer s.gpa.free(png);
        try w.writeAll("<image x=\"");
        try num(w, @as(f32, @floatFromInt(r.bitmap.x)) / k);
        try w.writeAll("\" y=\"");
        try num(w, @as(f32, @floatFromInt(r.bitmap.y)) / k);
        try w.writeAll("\" width=\"");
        try num(w, @as(f32, @floatFromInt(r.bitmap.w)) / k);
        try w.writeAll("\" height=\"");
        try num(w, @as(f32, @floatFromInt(r.bitmap.h)) / k);
        try w.writeAll("\" preserveAspectRatio=\"none\" xlink:href=\"");
        try dataUri(w, "image/png", png);
        try w.writeAll("\"/>\n");
    }

    fn clipPath(s: *Svg, r: [4]f32) !usize {
        const id = s.next_id;
        s.next_id += 1;
        const w = &s.defs.writer;
        try w.print("<clipPath id=\"c{d}\">", .{id});
        try rectElement(w, r, "");
        try w.writeAll("</clipPath>\n");
        return id;
    }

    fn begin(s: *Svg, b: vector.Begin) !void {
        const w = &s.body.writer;
        switch (b) {
            .transform => |t| {
                try w.writeAll("<g");
                if (t.rotate != 0) {
                    try w.writeAll(" transform=\"rotate(");
                    try num(w, t.rotate);
                    try w.writeByte(' ');
                    try num(w, t.pivot[0]);
                    try w.writeByte(' ');
                    try num(w, t.pivot[1]);
                    try w.writeAll(")\"");
                }
                if (t.opacity < 1) {
                    try w.writeAll(" opacity=\"");
                    try numP(w, t.opacity, 3);
                    try w.writeAll("\"");
                }
                try w.writeAll(">\n");
                try s.open.append(s.arena, 1);
            },
            .crop => |c| {
                // The clip is in the children's coordinates, the move after it.
                var n: u8 = 1;
                if (c.dx != 0 or c.dy != 0) {
                    try w.writeAll("<g transform=\"translate(");
                    try num(w, c.dx);
                    try w.writeByte(' ');
                    try num(w, c.dy);
                    try w.writeAll(")\">\n");
                    n += 1;
                }
                const id = try s.clipPath(c.clip);
                try w.print("<g clip-path=\"url(#c{d})\">\n", .{id});
                try s.open.append(s.arena, n);
            },
            .fade => |f| {
                const id = s.next_id;
                s.next_id += 1;
                const d = &s.defs.writer;
                const r = f.rect;
                // The gradient runs from the faded side inward.
                const line: [4]f32 = switch (f.side) {
                    .top => .{ r[0], r[1], r[0], r[1] + f.len },
                    .bottom => .{ r[0], r[3], r[0], r[3] - f.len },
                    .left => .{ r[0], r[1], r[0] + f.len, r[1] },
                    .right => .{ r[2], r[1], r[2] - f.len, r[1] },
                };
                try d.print("<linearGradient id=\"a{d}\" gradientUnits=\"userSpaceOnUse\" x1=\"", .{id});
                try num(d, line[0]);
                try d.writeAll("\" y1=\"");
                try num(d, line[1]);
                try d.writeAll("\" x2=\"");
                try num(d, line[2]);
                try d.writeAll("\" y2=\"");
                try num(d, line[3]);
                try d.writeAll("\"><stop offset=\"0\" stop-color=\"#fff\" stop-opacity=\"0\"/><stop offset=\"1\" stop-color=\"#fff\"/></linearGradient>\n");
                try d.print("<mask id=\"m{d}\" maskUnits=\"userSpaceOnUse\" x=\"", .{id});
                try num(d, r[0]);
                try d.writeAll("\" y=\"");
                try num(d, r[1]);
                try d.writeAll("\" width=\"");
                try num(d, r[2] - r[0]);
                try d.writeAll("\" height=\"");
                try num(d, r[3] - r[1]);
                try d.print("\">", .{});
                var fill_buf: [32]u8 = undefined;
                try rectElement(d, r, try std.fmt.bufPrint(&fill_buf, " fill=\"url(#a{d})\"", .{id}));
                try d.writeAll("</mask>\n");
                try w.print("<g mask=\"url(#m{d})\">\n", .{id});
                try s.open.append(s.arena, 1);
            },
        }
    }

    fn closeGroup(s: *Svg) !void {
        const n = s.open.pop() orelse return;
        for (0..n) |_| try s.body.writer.writeAll("</g>\n");
    }
};

fn sameLook(a: vector.Glyph, b: vector.Glyph) bool {
    return a.color.eql(b.color) and a.stroke == b.stroke;
}

fn samePath(a: vector.Path, b: vector.Path) bool {
    return a.cmds.ptr == b.cmds.ptr and a.cmds.len == b.cmds.len;
}

fn rectElement(w: *Writer, r: [4]f32, extra: []const u8) !void {
    try w.writeAll("<rect x=\"");
    try num(w, r[0]);
    try w.writeAll("\" y=\"");
    try num(w, r[1]);
    try w.writeAll("\" width=\"");
    try num(w, r[2] - r[0]);
    try w.writeAll("\" height=\"");
    try num(w, r[3] - r[1]);
    try w.writeAll("\"");
    try w.writeAll(extra);
    try w.writeAll("/>");
}

/// ` fill="#rrggbb" fill-opacity="a"` (the opacity only when below 1).
fn paintAttr(w: *Writer, name: []const u8, c: Color) !void {
    try w.print(" {s}=\"#{x:0>2}{x:0>2}{x:0>2}\"", .{ name, to8(c.r), to8(c.g), to8(c.b) });
    if (c.a < 65535) {
        try w.print(" {s}-opacity=\"", .{name});
        try numP(w, @as(f32, @floatFromInt(c.a)) / 65535.0, 3);
        try w.writeAll("\"");
    }
}

pub fn to8(v: u16) u8 {
    return @intCast((@as(u32, v) * 255 + 32767) / 65535);
}

fn pathData(w: *Writer, path: vector.Path) !void {
    for (path.cmds, 0..) |cmd, i| {
        if (i > 0) try w.writeByte(' ');
        switch (cmd) {
            .move => |p| try pair(w, 'M', &.{p}),
            .line => |p| try pair(w, 'L', &.{p}),
            .quad => |q| try pair(w, 'Q', &q),
            .cubic => |q| try pair(w, 'C', &q),
            .close => try w.writeByte('Z'),
        }
    }
}

fn pair(w: *Writer, op: u8, pts: []const vector.Point) !void {
    try w.writeByte(op);
    for (pts, 0..) |p, i| {
        if (i > 0) try w.writeByte(' ');
        try num(w, p[0]);
        try w.writeByte(' ');
        try num(w, p[1]);
    }
}

/// A number with up to 3 decimals, without trailing zeros.
fn num(w: *Writer, v: anytype) !void {
    try numP(w, v, 3);
}

fn numP(w: *Writer, v: anytype, decimals: usize) !void {
    var buf: [64]u8 = undefined;
    const f: f64 = if (@typeInfo(@TypeOf(v)) == .float) v else @floatFromInt(v);
    const s = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ f, decimals }) catch unreachable;
    var end = s.len;
    if (std.mem.indexOfScalar(u8, s, '.') != null) {
        while (end > 0 and s[end - 1] == '0') end -= 1;
        if (end > 0 and s[end - 1] == '.') end -= 1;
    }
    const t = s[0..end];
    // "-0" (a tiny negative number) is just 0.
    try w.writeAll(if (std.mem.eql(u8, t, "-0")) "0" else t);
}

fn dataUri(w: *Writer, mime: []const u8, bytes: []const u8) !void {
    try w.print("data:{s};base64,", .{mime});
    const enc = std.base64.standard.Encoder;
    var chunk: [4096]u8 = undefined;
    var i: usize = 0;
    while (i < bytes.len) {
        const n = @min(3072, bytes.len - i);
        const out = enc.encode(chunk[0..], bytes[i..][0..n]);
        try w.writeAll(out);
        i += n;
    }
}

// ------------------------------------------------------------------ tests

test "number formatting" {
    var aw: Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try num(&aw.writer, @as(f32, 12.5));
    try aw.writer.writeByte(' ');
    try num(&aw.writer, @as(f32, 3));
    try aw.writer.writeByte(' ');
    try num(&aw.writer, @as(f32, -0.0001));
    try aw.writer.writeByte(' ');
    try num(&aw.writer, @as(f32, 0.1234567));
    try std.testing.expectEqualStrings("12.5 3 0 0.123", aw.written());
}

test "scene to svg" {
    const gpa = std.testing.allocator;
    var sc = vector.Scene.init(gpa);
    defer sc.deinit();
    sc.width = 100;
    sc.height = 50;
    sc.dpi = 254;
    sc.background = Color.white;
    var b = vector.PathBuilder.init(sc.allocator());
    try b.roundRect(10, 10, 40, 20, 5);
    const path = b.finish();
    try sc.add(.{ .begin = .{ .transform = .{ .rotate = 10, .pivot = .{ 30, 20 }, .opacity = 0.5 } } });
    try sc.add(.{ .fill = .{ .path = path, .color = .{ .r = 65535, .g = 0, .b = 0, .a = 65535 } } });
    try sc.add(.{ .stroke = .{ .path = path, .color = Color.black, .width = 2, .dash = &.{ 4, 2 } } });
    try sc.add(.{ .begin = .{ .fade = .{ .side = .bottom, .len = 8, .rect = .{ 0, 0, 100, 50 } } } });
    try sc.add(.end);
    try sc.add(.end);
    const out = try write(gpa, &sc);
    defer gpa.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "<?xml"));
    try std.testing.expect(std.mem.indexOf(u8, out, "width=\"10mm\" height=\"5mm\" viewBox=\"0 0 100 50\"") != null);
    // One element for the fill and its stroke.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out, "<path d="));
    try std.testing.expect(std.mem.indexOf(u8, out, "stroke-dasharray=\"4 2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<mask id=\"m0\"") != null);
    const again = try write(gpa, &sc);
    defer gpa.free(again);
    try std.testing.expectEqualStrings(out, again);
    try expectBalanced(out);
}

/// Every opened tag is closed (comments and declarations aside).
pub fn expectBalanced(xml: []const u8) !void {
    var depth: i32 = 0;
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, xml, i, '<')) |lt| {
        const gt = std.mem.indexOfScalarPos(u8, xml, lt, '>') orelse return error.Unterminated;
        const tag = xml[lt + 1 .. gt];
        i = gt + 1;
        if (tag.len == 0 or tag[0] == '?' or tag[0] == '!') continue;
        if (tag[0] == '/') {
            depth -= 1;
            if (depth < 0) return error.Unbalanced;
        } else if (tag[tag.len - 1] != '/') depth += 1;
    }
    try std.testing.expectEqual(@as(i32, 0), depth);
}
