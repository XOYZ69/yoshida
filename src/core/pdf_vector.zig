//! Vector pages for the PDF writer: a vector scene as page content (paths,
//! glyph outlines, images, transparency groups and soft masks), at the same
//! page size and boxes as the image page of the same card
//! (docs: site/content/docs/saving-images-and-privacy.md).

const std = @import("std");
const pdf = @import("pdf.zig");
const raster = @import("raster.zig");
const text = @import("text.zig");
const vector = @import("vector.zig");
const Color = @import("value.zig").Color;
const Allocator = std.mem.Allocator;
const Writer = pdf.Writer;
const Out = std.Io.Writer.Allocating;

/// Objects that pages of one file share, by object number.
pub const Shared = struct {
    glyphs: std.AutoHashMapUnmanaged(GlyphKey, u32) = .empty,
    images: std.AutoHashMapUnmanaged(ImageKey, u32) = .empty,

    pub fn deinit(s: *Shared, gpa: Allocator) void {
        s.glyphs.deinit(gpa);
        s.images.deinit(gpa);
    }
};

const GlyphKey = struct { font: *const text.Font, gid: u32, outline: bool };
const ImageKey = struct { image: *const raster.Image, smooth: bool };

/// A box that no content reaches out of (clipping is done with real clips).
const huge_box = "[-100000 -100000 100000 100000]";

/// Adds the scene as a page. With `crop_marks` the page gets the same white
/// margin with marks at the trim lines as `raster.withCropMarks`.
pub fn addPage(w: *Writer, scene: *const vector.Scene, crop_marks: bool) !void {
    var arena_state = std.heap.ArenaAllocator.init(w.gpa);
    defer arena_state.deinit();
    var b: Builder = .{ .w = w, .arena = arena_state.allocator(), .scene = scene };
    const k: f64 = 72.0 / (if (scene.dpi > 0) scene.dpi else 72.0);
    const sheet = Sheet.of(scene, crop_marks);
    const root = try b.newStream();
    const o = &root.out.writer;
    // Canvas pixels, y down, inside the margin.
    try o.writeAll("q ");
    try num(o, k);
    try o.writeAll(" 0 0 ");
    try num(o, -k);
    try o.writeByte(' ');
    try num(o, sheet.margin * k);
    try o.writeByte(' ');
    try num(o, (@as(f64, @floatFromInt(scene.height)) + sheet.margin) * k);
    try o.writeAll(" cm\n");
    if (scene.background) |bg| try b.fillRect(.{ 0, 0, @floatFromInt(scene.width), @floatFromInt(scene.height) }, bg);
    try b.items();
    try o.writeAll("Q\n");
    if (crop_marks) try b.marks(sheet, k);

    const content = try raster.deflate(w.gpa, root.out.written());
    defer w.gpa.free(content);
    const content_id = try w.begin();
    try w.stream("/Filter /FlateDecode", content);
    const resources = try b.resources(root);
    // Boxes in PDF points, origin bottom-left; the bleed box is the card, the
    // trim box is inside it by `bleed`.
    const pw = sheet.width * k;
    const ph = sheet.height * k;
    const m = sheet.margin * k;
    const bl = scene.bleed * k;
    const page = try w.begin();
    w.out.writer.print(
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {d:.4} {d:.4}] /BleedBox [{d:.4} {d:.4} {d:.4} {d:.4}] /TrimBox [{d:.4} {d:.4} {d:.4} {d:.4}] /Resources {s} /Contents {d} 0 R >>\nendobj\n",
        .{ pw, ph, m, m, pw - m, ph - m, m + bl, m + bl, pw - m - bl, ph - m - bl, resources, content_id },
    ) catch return error.OutOfMemory;
    try w.pages.append(w.gpa, page);
}

/// The page in canvas pixels: the card and the margin for crop marks.
const Sheet = struct {
    width: f64,
    height: f64,
    margin: f64,
    /// Marks: pixels per mm, gap, length, and line width.
    unit: f64,

    fn of(scene: *const vector.Scene, crop_marks: bool) Sheet {
        const unit: f64 = if (scene.dpi > 0) scene.dpi / 25.4 else 300.0 / 25.4;
        const m: f64 = if (crop_marks) @round(2 * unit) + @round(5 * unit) else 0;
        return .{
            .width = @as(f64, @floatFromInt(scene.width)) + 2 * m,
            .height = @as(f64, @floatFromInt(scene.height)) + 2 * m,
            .margin = m,
            .unit = unit,
        };
    }
};

/// One content stream and the resources it names.
const Stream = struct {
    out: Out,
    /// Resource entries: `/G1 << ... >>` (graphics states).
    states: std.ArrayList([]const u8) = .empty,
    /// Object numbers of the XObjects used; named `/X<index>`.
    xobjects: std.ArrayList(u32) = .empty,
};

/// What a group does when it closes.
const Frame = union(enum) {
    /// Closes with `Q`.
    save,
    /// A transparency group: its own stream, drawn as a whole with
    /// `opacity` under `matrix` (a `cm` operand list), and through the soft
    /// mask object `mask` when there is one. A soft mask replaces the one
    /// before it and is ignored by images that have their own, so a fade
    /// always works on a group.
    group: struct { stream: *Stream, opacity: f32, matrix: [6]f64, mask: ?u32 = null },
};

const Builder = struct {
    w: *Writer,
    /// Scratch for streams and resource text; freed after the page.
    arena: Allocator,
    scene: *const vector.Scene,
    /// The streams being written: the page's, then one per open group.
    streams: std.ArrayList(*Stream) = .empty,
    frames: std.ArrayList(Frame) = .empty,

    fn newStream(b: *Builder) !*Stream {
        const s = try b.arena.create(Stream);
        s.* = .{ .out = .init(b.arena) };
        try b.streams.append(b.arena, s);
        return s;
    }

    fn cur(b: *Builder) *Stream {
        return b.streams.items[b.streams.items.len - 1];
    }

    fn out(b: *Builder) *std.Io.Writer {
        return &b.cur().out.writer;
    }

    fn items(b: *Builder) !void {
        const list = b.scene.items.items;
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            switch (list[i]) {
                .fill => |f| {
                    // Opaque fill and stroke of one path: one operator.
                    if (i + 1 < list.len and list[i + 1] == .stroke and samePath(f.path, list[i + 1].stroke.path) and f.color.a == 65535 and list[i + 1].stroke.color.a == 65535) {
                        try b.paint(f.path, f.color, list[i + 1].stroke);
                        i += 1;
                    } else try b.paint(f.path, f.color, null);
                },
                .stroke => |s| try b.paint(s.path, null, s),
                .glyph => |g| try b.glyph(g),
                .image => |im| try b.image(im),
                .raster => |r| try b.rasterImage(r),
                .begin => |g| try b.begin(g),
                .end => try b.end(),
            }
        }
        while (b.frames.items.len > 0) try b.end();
    }

    // ------------------------------------------------------------ painting

    fn fillRect(b: *Builder, r: [4]f32, c: Color) !void {
        const o = b.out();
        const alpha = c.a < 65535;
        if (alpha) try b.setAlpha(c.a, c.a);
        try setColor(o, c, "rg");
        try rect(o, r[0], r[1], r[2] - r[0], r[3] - r[1]);
        try o.writeAll(" f\n");
        if (alpha) try o.writeAll("Q\n");
    }

    /// Starts `q` and sets the fill and stroke alpha (`ca`, `CA`).
    fn setAlpha(b: *Builder, fill_a: u16, stroke_a: u16) !void {
        const o = b.out();
        try o.writeAll("q ");
        const entry = try std.fmt.allocPrint(b.arena, "<< /ca {d:.4} /CA {d:.4} >>", .{ alphaOf(fill_a), alphaOf(stroke_a) });
        try o.print("/G{d} gs\n", .{try b.stateName(entry)});
    }

    fn stateName(b: *Builder, entry: []const u8) !usize {
        const s = b.cur();
        for (s.states.items, 0..) |e, i| if (std.mem.eql(u8, e, entry)) return i;
        try s.states.append(b.arena, entry);
        return s.states.items.len - 1;
    }

    fn xobjectName(b: *Builder, id: u32) !usize {
        const s = b.cur();
        for (s.xobjects.items, 0..) |e, i| if (e == id) return i;
        try s.xobjects.append(b.arena, id);
        return s.xobjects.items.len - 1;
    }

    fn paint(b: *Builder, path: vector.Path, fill: ?Color, stroke: ?vector.Stroke) !void {
        const o = b.out();
        const fa: u16 = if (fill) |c| c.a else 65535;
        const sa: u16 = if (stroke) |s| s.color.a else 65535;
        if (fill) |c| if (c.a == 0) return;
        const shaded = fa < 65535 or sa < 65535;
        if (shaded) try b.setAlpha(fa, sa) else try o.writeAll("q ");
        if (fill) |c| try setColor(o, c, "rg");
        if (stroke) |s| {
            try setColor(o, s.color, "RG");
            try num(o, s.width);
            try o.writeAll(" w 1 j 1 J ");
            if (s.dash.len > 0) {
                try o.writeByte('[');
                for (s.dash, 0..) |d, i| {
                    if (i > 0) try o.writeByte(' ');
                    try num(o, d);
                }
                try o.writeAll("] 0 d ");
            }
        }
        try pathOps(o, path);
        try o.writeAll(if (fill != null and stroke != null) " B" else if (fill != null) " f" else " S");
        try o.writeAll(" Q\n");
    }

    fn glyph(b: *Builder, g: vector.Glyph) !void {
        if (g.color.a == 0) return;
        const outline = g.stroke > 0;
        const id = try b.glyphForm(g.font, g.gid, outline);
        const o = b.out();
        const shaded = g.color.a < 65535;
        if (shaded) try b.setAlpha(g.color.a, g.color.a) else try o.writeAll("q ");
        try matrix(o, .{ g.scale, 0, 0, g.scale, g.x, g.y });
        try o.writeAll(" cm ");
        try setColor(o, g.color, "rg");
        if (outline) {
            try setColor(o, g.color, "RG");
            // The stroke width is in glyph units, which the matrix scales.
            try num(o, g.stroke / g.scale);
            try o.writeAll(" w 1 j ");
        }
        try o.print("/X{d} Do Q\n", .{try b.xobjectName(id)});
    }

    /// The glyph outline as a form that paints with the current colors.
    fn glyphForm(b: *Builder, font: *const text.Font, gid: u32, outline: bool) !u32 {
        const key: GlyphKey = .{ .font = font, .gid = gid, .outline = outline };
        if (b.w.shared.glyphs.get(key)) |id| return id;
        const path = try vector.glyphPath(b.arena, font, gid);
        var content = Out.init(b.arena);
        try pathOps(&content.writer, path);
        try content.writer.writeAll(if (outline) " B" else " f");
        const id = try b.writeForm(huge_box, "<< >>", content.written(), false);
        try b.w.shared.glyphs.put(b.w.gpa, key, id);
        return id;
    }

    // ------------------------------------------------------------ images

    fn image(b: *Builder, im: vector.Image) !void {
        const id = try b.imageObject(im);
        const o = b.out();
        const clipped = !(im.clip[0] == im.rect[0] and im.clip[1] == im.rect[1] and im.clip[2] == im.rect[0] + im.rect[2] and im.clip[3] == im.rect[1] + im.rect[3]);
        try o.writeAll("q ");
        if (clipped) {
            try rect(o, im.clip[0], im.clip[1], im.clip[2] - im.clip[0], im.clip[3] - im.clip[1]);
            try o.writeAll(" W n ");
        }
        try b.placeImage(id, im.rect);
    }

    /// `cm` and `Do` for an image that fills `r` (x, y, w, h); closes the `q`.
    fn placeImage(b: *Builder, id: u32, r: [4]f32) !void {
        const o = b.out();
        // The image's unit square has y up, the page space here y down.
        try matrix(o, .{ r[2], 0, 0, -r[3], r[0], r[1] + r[3] });
        try o.print(" cm /X{d} Do Q\n", .{try b.xobjectName(id)});
    }

    fn rasterImage(b: *Builder, r: vector.Raster) !void {
        var px = try pdf.Pixels.init(b.w.gpa, r.bitmap.px, r.bitmap.w, r.bitmap.h);
        defer px.deinit(b.w.gpa);
        const id = try b.rgbImage(px, r.bitmap.w, r.bitmap.h, true);
        const k = r.scale;
        try b.out().writeAll("q ");
        try b.placeImage(id, .{
            @as(f32, @floatFromInt(r.bitmap.x)) / k,
            @as(f32, @floatFromInt(r.bitmap.y)) / k,
            @as(f32, @floatFromInt(r.bitmap.w)) / k,
            @as(f32, @floatFromInt(r.bitmap.h)) / k,
        });
    }

    /// The image object for a source image, shared by every page. JPEG
    /// files go in as their image data (`vector.embeddable`), the rest as
    /// Flate-compressed pixels.
    fn imageObject(b: *Builder, im: vector.Image) !u32 {
        const key: ImageKey = .{ .image = im.image, .smooth = im.smooth };
        if (b.w.shared.images.get(key)) |id| return id;
        const id = try b.encodeImage(im);
        try b.w.shared.images.put(b.w.gpa, key, id);
        return id;
    }

    fn encodeImage(b: *Builder, im: vector.Image) !u32 {
        if (try b.jpegImage(im)) |id| return id;
        const img = im.image;
        var px = try pdf.Pixels.init(b.w.gpa, img.px, img.w, img.h);
        defer px.deinit(b.w.gpa);
        return b.rgbImage(px, img.w, img.h, im.smooth);
    }

    /// A gray or RGB JPEG file of the decoded size as a DCTDecode image;
    /// null for anything else.
    fn jpegImage(b: *Builder, im: vector.Image) !?u32 {
        const info = vector.jpegInfo(im.bytes) orelse return null;
        const gray = info.components == 1;
        if (!(gray or info.components == 3) or info.w != im.image.w or info.h != im.image.h) return null;
        const e = (try vector.embeddable(b.w.gpa, im.bytes)) orelse return null;
        defer b.w.gpa.free(e.bytes);
        if (!std.mem.eql(u8, e.mime, "image/jpeg")) return null;
        const id = try b.w.begin();
        const dict = try std.fmt.allocPrint(b.arena, "/Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /{s} /BitsPerComponent 8 /Interpolate {} /Filter /DCTDecode", .{ info.w, info.h, if (gray) "DeviceGray" else "DeviceRGB", im.smooth });
        try b.w.stream(dict, e.bytes);
        return id;
    }

    fn rgbImage(b: *Builder, px: pdf.Pixels, w: u32, h: u32, smooth: bool) !u32 {
        var mask_id: ?u32 = null;
        if (px.alpha) |a| {
            const z = try raster.deflate(b.w.gpa, a);
            defer b.w.gpa.free(z);
            mask_id = try b.w.begin();
            const dict = try std.fmt.allocPrint(b.arena, "/Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /DeviceGray /BitsPerComponent 8 /Interpolate {} /Filter /FlateDecode", .{ w, h, smooth });
            try b.w.stream(dict, z);
        }
        const z = try raster.deflate(b.w.gpa, px.rgb);
        defer b.w.gpa.free(z);
        const id = try b.w.begin();
        const sm = if (mask_id) |m| try std.fmt.allocPrint(b.arena, " /SMask {d} 0 R", .{m}) else "";
        const dict = try std.fmt.allocPrint(b.arena, "/Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Interpolate {} /Filter /FlateDecode{s}", .{ w, h, smooth, sm });
        try b.w.stream(dict, z);
        return id;
    }

    // ------------------------------------------------------------ groups

    fn begin(b: *Builder, g: vector.Begin) !void {
        switch (g) {
            .transform => |t| {
                const m = rotation(t.rotate, t.pivot);
                if (t.opacity >= 1) {
                    const o = b.out();
                    try o.writeAll("q ");
                    try matrix(o, m);
                    try o.writeAll(" cm\n");
                    return b.frames.append(b.arena, .save);
                }
                // Opacity applies to the group as a whole: its own stream.
                const s = try b.newStream();
                try b.frames.append(b.arena, .{ .group = .{ .stream = s, .opacity = t.opacity, .matrix = m } });
            },
            .crop => |c| {
                const o = b.out();
                try o.writeAll("q ");
                if (c.dx != 0 or c.dy != 0) {
                    try matrix(o, .{ 1, 0, 0, 1, c.dx, c.dy });
                    try o.writeAll(" cm ");
                }
                try rect(o, c.clip[0], c.clip[1], c.clip[2] - c.clip[0], c.clip[3] - c.clip[1]);
                try o.writeAll(" W n\n");
                try b.frames.append(b.arena, .save);
            },
            .fade => |f| {
                const mask = try b.fadeMask(f);
                const s = try b.newStream();
                try b.frames.append(b.arena, .{ .group = .{ .stream = s, .opacity = 1, .matrix = .{ 1, 0, 0, 1, 0, 0 }, .mask = mask } });
            },
        }
    }

    fn end(b: *Builder) !void {
        const f = b.frames.pop() orelse return;
        switch (f) {
            .save => try b.out().writeAll("Q\n"),
            .group => |g| {
                _ = b.streams.pop();
                const id = try b.writeForm(huge_box, try b.resources(g.stream), g.stream.out.written(), true);
                const entry = if (g.mask) |m|
                    try std.fmt.allocPrint(b.arena, "<< /SMask << /Type /Mask /S /Luminosity /G {d} 0 R >> >>", .{m})
                else
                    try std.fmt.allocPrint(b.arena, "<< /ca {d:.4} /CA {d:.4} >>", .{ g.opacity, g.opacity });
                const o = b.out();
                try o.writeAll("q ");
                try matrix(o, g.matrix);
                try o.print(" cm /G{d} gs /X{d} Do Q\n", .{ try b.stateName(entry), try b.xobjectName(id) });
            },
        }
    }

    /// The luminosity mask form of a fade: 0 at the faded side of the
    /// rectangle, 1 `len` pixels in, and 0 outside the rectangle.
    fn fadeMask(b: *Builder, f: vector.Begin.Fade) !u32 {
        const r = f.rect;
        const line: [4]f32 = switch (f.side) {
            .top => .{ r[0], r[1], r[0], r[1] + f.len },
            .bottom => .{ r[0], r[3], r[0], r[3] - f.len },
            .left => .{ r[0], r[1], r[0] + f.len, r[1] },
            .right => .{ r[2], r[1], r[2] - f.len, r[1] },
        };
        var res = Out.init(b.arena);
        const rw = &res.writer;
        try rw.writeAll("<< /Shading << /Sh0 << /ShadingType 2 /ColorSpace /DeviceGray /Coords [");
        for (line, 0..) |v, i| {
            if (i > 0) try rw.writeByte(' ');
            try num(rw, v);
        }
        try rw.writeAll("] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> /Extend [true true] >> >> >>");
        var content = Out.init(b.arena);
        try rect(&content.writer, r[0], r[1], r[2] - r[0], r[3] - r[1]);
        try content.writer.writeAll(" W n /Sh0 sh");
        var box = Out.init(b.arena);
        try box.writer.writeAll("[");
        for (r, 0..) |v, i| {
            if (i > 0) try box.writer.writeByte(' ');
            try num(&box.writer, v);
        }
        try box.writer.writeAll("]");
        return b.writeFormWithColorSpace(box.written(), res.written(), content.written(), "DeviceGray");
    }

    /// A form XObject; `group` makes it an isolated transparency group.
    fn writeForm(b: *Builder, bbox: []const u8, res: []const u8, content: []const u8, group: bool) !u32 {
        return b.writeFormWithColorSpace(bbox, res, content, if (group) "DeviceRGB" else null);
    }

    fn writeFormWithColorSpace(b: *Builder, bbox: []const u8, res: []const u8, content: []const u8, group_cs: ?[]const u8) !u32 {
        const z = try raster.deflate(b.w.gpa, content);
        defer b.w.gpa.free(z);
        const id = try b.w.begin();
        const grp = if (group_cs) |cs| try std.fmt.allocPrint(b.arena, " /Group << /S /Transparency /CS /{s} /I true >>", .{cs}) else "";
        const dict = try std.fmt.allocPrint(b.arena, "/Type /XObject /Subtype /Form /BBox {s} /Resources {s}{s} /Filter /FlateDecode", .{ bbox, res, grp });
        try b.w.stream(dict, z);
        return id;
    }

    /// The resource dictionary of a stream.
    fn resources(b: *Builder, s: *const Stream) ![]const u8 {
        var o = Out.init(b.arena);
        const w = &o.writer;
        try w.writeAll("<<");
        if (s.states.items.len > 0) {
            try w.writeAll(" /ExtGState <<");
            for (s.states.items, 0..) |e, i| try w.print(" /G{d} {s}", .{ i, e });
            try w.writeAll(" >>");
        }
        if (s.xobjects.items.len > 0) {
            try w.writeAll(" /XObject <<");
            for (s.xobjects.items, 0..) |id, i| try w.print(" /X{d} {d} 0 R", .{ i, id });
            try w.writeAll(" >>");
        }
        try w.writeAll(" >>");
        return o.written();
    }

    // ------------------------------------------------------------ crop marks

    /// Marks at the trim lines, in the margin, like `raster.withCropMarks`.
    fn marks(b: *Builder, sheet: Sheet, k: f64) !void {
        const unit = sheet.unit;
        const len = @round(5 * unit);
        const lw = @max(1, @round(unit * 0.1));
        const bleed = b.scene.bleed;
        const t0 = sheet.margin + bleed;
        const t1x = sheet.margin + @as(f64, @floatFromInt(b.scene.width)) - bleed;
        const t1y = sheet.margin + @as(f64, @floatFromInt(b.scene.height)) - bleed;
        const o = b.out();
        // Sheet pixels, y down.
        try o.writeAll("q ");
        try matrix(o, .{ k, 0, 0, -k, 0, sheet.height * k });
        try o.writeAll(" cm 0 0 0 RG ");
        try num(o, lw);
        try o.writeAll(" w 1 J\n");
        for ([_]f64{ t0, t1x }) |x| {
            try markLine(o, x, 0, x, len);
            try markLine(o, x, sheet.height - len, x, sheet.height);
        }
        for ([_]f64{ t0, t1y }) |y| {
            try markLine(o, 0, y, len, y);
            try markLine(o, sheet.width - len, y, sheet.width, y);
        }
        try o.writeAll("Q\n");
    }
};

fn markLine(o: *std.Io.Writer, x0: f64, y0: f64, x1: f64, y1: f64) !void {
    try num(o, x0);
    try o.writeByte(' ');
    try num(o, y0);
    try o.writeAll(" m ");
    try num(o, x1);
    try o.writeByte(' ');
    try num(o, y1);
    try o.writeAll(" l S\n");
}

fn samePath(a: vector.Path, b: vector.Path) bool {
    return a.cmds.ptr == b.cmds.ptr and a.cmds.len == b.cmds.len;
}

fn alphaOf(a: u16) f32 {
    return @as(f32, @floatFromInt(a)) / 65535.0;
}

fn rect(o: *std.Io.Writer, x: f32, y: f32, w: f32, h: f32) !void {
    for ([_]f32{ x, y, w, h }) |v| {
        try num(o, v);
        try o.writeByte(' ');
    }
    try o.writeAll("re");
}

/// Operands for `cm`: a rotation clockwise on screen about `pivot`, in a
/// page space with y down.
fn rotation(deg: f32, pivot: vector.Point) [6]f64 {
    const a: f64 = @as(f64, deg) * std.math.pi / 180.0;
    const c = @cos(a);
    const s = @sin(a);
    const px: f64 = pivot[0];
    const py: f64 = pivot[1];
    return .{ c, s, -s, c, px - c * px + s * py, py - s * px - c * py };
}

/// The six operands of `cm` (numbers of any type).
fn matrix(o: *std.Io.Writer, m: anytype) !void {
    inline for (m, 0..) |v, i| {
        if (i > 0) try o.writeByte(' ');
        // Scales need more digits than positions.
        try numP(o, if (@typeInfo(@TypeOf(v)) == .float) @as(f64, v) else @as(f64, @floatFromInt(v)), if (i < 4) 8 else 3);
    }
}

/// Sets a color from its 8-bit value as the PNG and SVG outputs have it.
/// The middle of the 8-bit step is written, so a viewer that rounds and one
/// that truncates both land on the same value; 0 and 1 stay exact.
fn setColor(o: *std.Io.Writer, c: Color, op: []const u8) !void {
    for ([_]u16{ c.r, c.g, c.b }) |v| {
        const v8: f64 = @floatFromInt(@import("svg.zig").to8(v));
        try numP(o, if (v8 == 0) 0 else if (v8 == 255) 1 else (v8 + 0.5) / 255.0, 5);
        try o.writeByte(' ');
    }
    try o.print("{s} ", .{op});
}

fn pathOps(o: *std.Io.Writer, path: vector.Path) !void {
    var cur: vector.Point = .{ 0, 0 };
    for (path.cmds, 0..) |cmd, i| {
        if (i > 0) try o.writeByte(' ');
        switch (cmd) {
            .move => |p| {
                try point(o, p);
                try o.writeAll(" m");
                cur = p;
            },
            .line => |p| {
                try point(o, p);
                try o.writeAll(" l");
                cur = p;
            },
            .quad => |q| {
                // PDF has cubics only: the same curve with its control points.
                const c1: vector.Point = .{ cur[0] + 2.0 / 3.0 * (q[0][0] - cur[0]), cur[1] + 2.0 / 3.0 * (q[0][1] - cur[1]) };
                const c2: vector.Point = .{ q[1][0] + 2.0 / 3.0 * (q[0][0] - q[1][0]), q[1][1] + 2.0 / 3.0 * (q[0][1] - q[1][1]) };
                try point(o, c1);
                try o.writeByte(' ');
                try point(o, c2);
                try o.writeByte(' ');
                try point(o, q[1]);
                try o.writeAll(" c");
                cur = q[1];
            },
            .cubic => |q| {
                try point(o, q[0]);
                try o.writeByte(' ');
                try point(o, q[1]);
                try o.writeByte(' ');
                try point(o, q[2]);
                try o.writeAll(" c");
                cur = q[2];
            },
            .close => try o.writeAll("h"),
        }
    }
}

fn point(o: *std.Io.Writer, p: vector.Point) !void {
    try num(o, p[0]);
    try o.writeByte(' ');
    try num(o, p[1]);
}

/// A number with up to 3 decimals, without trailing zeros.
fn num(o: *std.Io.Writer, v: anytype) !void {
    try numP(o, @as(f64, if (@typeInfo(@TypeOf(v)) == .float) v else @floatFromInt(v)), 3);
}

fn numP(o: *std.Io.Writer, v: f64, decimals: usize) !void {
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ v, decimals }) catch unreachable;
    var end = s.len;
    if (std.mem.indexOfScalar(u8, s, '.') != null) {
        while (end > 0 and s[end - 1] == '0') end -= 1;
        if (end > 0 and s[end - 1] == '.') end -= 1;
    }
    const t = s[0..end];
    try o.writeAll(if (std.mem.eql(u8, t, "-0")) "0" else t);
}

// ------------------------------------------------------------------ tests

/// Checks the file's structure: every xref offset points at its object,
/// every reference points at an existing object, every Flate stream
/// inflates, and returns the number of objects.
pub fn expectWellFormed(gpa: Allocator, pdf_bytes: []const u8) !usize {
    try std.testing.expect(std.mem.startsWith(u8, pdf_bytes, "%PDF-1.4"));
    try std.testing.expect(std.mem.endsWith(u8, pdf_bytes, "%%EOF\n"));
    const sx = std.mem.lastIndexOf(u8, pdf_bytes, "startxref\n") orelse return error.NoStartxref;
    const xref_at = try std.fmt.parseInt(usize, std.mem.trim(u8, pdf_bytes[sx + 10 ..][0..std.mem.indexOfScalar(u8, pdf_bytes[sx + 10 ..], '\n').?], " "), 10);
    try std.testing.expect(std.mem.startsWith(u8, pdf_bytes[xref_at..], "xref\n0 "));
    var lines = std.mem.splitScalar(u8, pdf_bytes[xref_at + 5 ..], '\n');
    const count = try std.fmt.parseInt(usize, lines.next().?["0 ".len..], 10);
    _ = lines.next(); // the free entry
    for (1..count) |n| {
        const entry = lines.next().?;
        const off = try std.fmt.parseInt(usize, entry[0..10], 10);
        var want: [32]u8 = undefined;
        const head = try std.fmt.bufPrint(&want, "{d} 0 obj\n", .{n});
        try std.testing.expect(std.mem.startsWith(u8, pdf_bytes[off..], head));
        const end = std.mem.indexOfPos(u8, pdf_bytes, off, "endobj") orelse return error.NoEndobj;
        const obj = pdf_bytes[off..end];
        // References.
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, obj, i, " 0 R")) |r| : (i = r + 4) {
            var s = r;
            while (s > 0 and std.ascii.isDigit(obj[s - 1])) s -= 1;
            const target = try std.fmt.parseInt(usize, obj[s..r], 10);
            try std.testing.expect(target >= 1 and target < count);
        }
        // Streams.
        if (std.mem.indexOf(u8, obj, "/FlateDecode") != null) {
            const lp = std.mem.indexOf(u8, obj, "/Length ").? + 8;
            const len = try std.fmt.parseInt(usize, obj[lp..][0..std.mem.indexOfScalar(u8, obj[lp..], ' ').?], 10);
            const data = obj[std.mem.indexOf(u8, obj, "stream\n").? + 7 ..][0..len];
            var in: std.Io.Reader = .fixed(data);
            var dec = std.compress.flate.Decompress.init(&in, .zlib, &.{});
            const inflated = try dec.reader.allocRemaining(gpa, .unlimited);
            gpa.free(inflated);
        }
    }
    return count - 1;
}

test "vector page structure" {
    const gpa = std.testing.allocator;
    var font = (try text.Font.init(gpa, @import("root.zig").default_font)).?;
    defer font.deinit(gpa);
    var sc = vector.Scene.init(gpa);
    defer sc.deinit();
    sc.width = 200;
    sc.height = 100;
    sc.dpi = 300;
    sc.bleed = 4;
    sc.background = Color.white;
    var pb = vector.PathBuilder.init(sc.allocator());
    try pb.roundRect(10, 10, 80, 40, 6);
    const rr = pb.finish();
    const red: Color = .{ .r = 65535, .g = 0, .b = 0, .a = 65535 };
    try sc.add(.{ .fill = .{ .path = rr, .color = red } });
    try sc.add(.{ .stroke = .{ .path = rr, .color = Color.black, .width = 3, .dash = &.{ 4, 2 } } });
    try sc.add(.{ .fill = .{ .path = rr, .color = .{ .r = 0, .g = 0, .b = 65535, .a = 30000 } } });
    try sc.add(.{ .glyph = .{ .font = &font, .gid = font.glyphIndex('A'), .x = 20, .y = 80, .scale = font.scale(30), .color = Color.black } });
    try sc.add(.{ .glyph = .{ .font = &font, .gid = font.glyphIndex('A'), .x = 60, .y = 80, .scale = font.scale(30), .color = Color.white, .stroke = 4 } });
    var img = try raster.Image.fromStraight(gpa, 2, 2, &.{ 65535, 0, 0, 65535, 0, 65535, 0, 30000, 0, 0, 65535, 65535, 0, 0, 0, 65535 });
    defer img.deinit(gpa);
    try sc.add(.{ .image = .{ .image = &img, .bytes = "", .rect = .{ 120, 10, 40, 40 }, .clip = .{ 120, 10, 160, 40 }, .smooth = false } });
    try sc.add(.{ .begin = .{ .transform = .{ .rotate = 20, .pivot = .{ 100, 50 }, .opacity = 0.5 } } });
    try sc.add(.{ .begin = .{ .fade = .{ .side = .right, .len = 20, .rect = .{ 100, 40, 180, 90 } } } });
    try sc.add(.{ .begin = .{ .crop = .{ .clip = .{ 110, 50, 170, 90 }, .dx = -4, .dy = 0 } } });
    try sc.add(.{ .fill = .{ .path = rr, .color = red } });
    try sc.add(.end);
    try sc.add(.end);
    try sc.add(.end);
    var bm = try raster.Bitmap.init(gpa, 20, 20, 8, 8);
    bm.fill(.{ 65535, 0, 0, 65535 });
    try sc.add(.{ .raster = .{ .bitmap = bm, .scale = 2 } });

    var w = try Writer.init(gpa);
    defer w.deinit();
    try w.addVector(&sc, false);
    try w.addVector(&sc, true);
    const bytes = try w.finish();
    defer gpa.free(bytes);
    const objects = try expectWellFormed(gpa, bytes);
    try std.testing.expect(objects > 10);
    // Two pages, the second with the crop-mark margin (83 px at 300 dpi: 2 mm gap and 5 mm marks).
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/Count 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/MediaBox [0 0 48.0000 24.0000]") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "/MediaBox [0 0 87.8400 63.8400]") != null);
    // Shared by both pages: one outline form per glyph look, one image.
    try std.testing.expectEqual(@as(usize, 2), w.shared.glyphs.count());
    try std.testing.expectEqual(@as(usize, 1), w.shared.images.count());
    const again = blk: {
        var w2 = try Writer.init(gpa);
        defer w2.deinit();
        try w2.addVector(&sc, false);
        try w2.addVector(&sc, true);
        break :blk try w2.finish();
    };
    defer gpa.free(again);
    try std.testing.expectEqualSlices(u8, bytes, again);
}
