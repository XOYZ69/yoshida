//! Vector scene: what a card draws as an ordered display list in canvas
//! pixels (paths, glyphs, images, groups), for the SVG and PDF writers
//! (docs: site/content/docs/rendering-model.md). The renderer fills one
//! when `render.Options.vector` is set instead of drawing pixels.

const std = @import("std");
const c = @import("c.zig");
const raster = @import("raster.zig");
const text = @import("text.zig");
const Color = @import("value.zig").Color;
const Allocator = std.mem.Allocator;

pub const Point = [2]f32;

pub const Cmd = union(enum) {
    move: Point,
    line: Point,
    quad: [2]Point,
    cubic: [3]Point,
    close,
};

pub const Path = struct {
    cmds: []const Cmd = &.{},
};

/// Fills with the nonzero rule.
pub const Fill = struct { path: Path, color: Color };

/// A stroke centered on the path with round joins and caps. `dash` is empty
/// for a solid line, else an even number of lengths (on, off, ...).
pub const Stroke = struct { path: Path, color: Color, width: f32, dash: []const f32 = &.{} };

/// One glyph of a font: filled with `color`, and when `stroke` is above 0
/// also stroked with the same color (the text outline pass).
pub const Glyph = struct {
    font: *const text.Font,
    gid: u32,
    /// Origin on the baseline, canvas pixels.
    x: f32,
    y: f32,
    /// Font units to canvas pixels.
    scale: f32,
    color: Color,
    stroke: f32 = 0,
};

/// An image stretched to `rect` (x, y, w, h) and clipped to `clip` (x0, y0,
/// x1, y1). `bytes` is the file it was decoded from; the writers embed its
/// image data (see `embeddable`) when they can.
pub const Image = struct {
    image: *const raster.Image,
    bytes: []const u8,
    rect: [4]f32,
    clip: [4]f32,
    smooth: bool,
};

/// Pixels drawn by the raster code, for what has no vector form. The bitmap
/// is `scale` times larger than the canvas area it covers.
pub const Raster = struct { bitmap: raster.Bitmap, scale: f32 };

/// Opens a group. Its children are drawn in their own coordinates, then:
/// `crop` clips them to a rectangle and moves them, `fade` ramps their
/// alpha to 0 toward a side of a rectangle, `transform` rotates them about
/// a pivot and applies opacity to them as a whole.
pub const Begin = union(enum) {
    transform: Transform,
    crop: Crop,
    fade: Fade,

    pub const Transform = struct {
        /// Degrees clockwise around `pivot`.
        rotate: f32,
        pivot: Point,
        opacity: f32,
    };

    /// Keeps `clip` (x0, y0, x1, y1) of the children, moved by (dx, dy).
    pub const Crop = struct { clip: [4]f32, dx: f32, dy: f32 };

    /// Alpha is 0 at `side` of `rect` (x0, y0, x1, y1) and 1 at `len`
    /// pixels from it.
    pub const Fade = struct { side: raster.Side, len: f32, rect: [4]f32 };
};

pub const Item = union(enum) {
    fill: Fill,
    stroke: Stroke,
    glyph: Glyph,
    image: Image,
    raster: Raster,
    begin: Begin,
    end,
};

pub const Scene = struct {
    gpa: Allocator,
    /// Paths, dashes and the item list; freed with the scene.
    arena: std.heap.ArenaAllocator,
    /// Canvas size in pixels.
    width: u32 = 0,
    height: u32 = 0,
    /// Print resolution (`canvas.dpi`), 0 when unknown.
    dpi: f64 = 0,
    /// Bleed in pixels on every side (`canvas.bleed`).
    bleed: f64 = 0,
    background: ?Color = null,
    /// Bitmap pixels per canvas pixel for `Raster` items.
    raster_scale: f32 = 2,
    items: std.ArrayList(Item) = .empty,

    pub fn init(gpa: Allocator) Scene {
        return .{ .gpa = gpa, .arena = .init(gpa) };
    }

    pub fn deinit(s: *Scene) void {
        for (s.items.items) |*it| switch (it.*) {
            .raster => |*r| r.bitmap.deinit(s.gpa),
            else => {},
        };
        s.arena.deinit();
    }

    pub fn allocator(s: *Scene) Allocator {
        return s.arena.allocator();
    }

    pub fn add(s: *Scene, item: Item) Allocator.Error!void {
        try s.items.append(s.allocator(), item);
    }
};

// ------------------------------------------------------------------ paths

/// Circle quarter as a cubic: the control distance for a 90 degree arc.
const kappa = 0.5522847498;

pub const PathBuilder = struct {
    arena: Allocator,
    cmds: std.ArrayList(Cmd) = .empty,

    pub fn init(arena: Allocator) PathBuilder {
        return .{ .arena = arena };
    }

    pub fn finish(b: *PathBuilder) Path {
        return .{ .cmds = b.cmds.items };
    }

    pub fn moveTo(b: *PathBuilder, p: Point) Allocator.Error!void {
        try b.cmds.append(b.arena, .{ .move = p });
    }

    pub fn lineTo(b: *PathBuilder, p: Point) Allocator.Error!void {
        try b.cmds.append(b.arena, .{ .line = p });
    }

    pub fn quadTo(b: *PathBuilder, c1: Point, p: Point) Allocator.Error!void {
        try b.cmds.append(b.arena, .{ .quad = .{ c1, p } });
    }

    pub fn cubicTo(b: *PathBuilder, c1: Point, c2: Point, p: Point) Allocator.Error!void {
        try b.cmds.append(b.arena, .{ .cubic = .{ c1, c2, p } });
    }

    pub fn close(b: *PathBuilder) Allocator.Error!void {
        try b.cmds.append(b.arena, .close);
    }

    /// Points joined by lines, optionally closed.
    pub fn polyline(b: *PathBuilder, pts: []const Point, closed: bool) Allocator.Error!void {
        if (pts.len == 0) return;
        try b.moveTo(pts[0]);
        for (pts[1..]) |p| try b.lineTo(p);
        if (closed) try b.close();
    }

    /// Arc of an ellipse from angle `start` to `end` in degrees, clockwise
    /// from 12 o'clock (as `raster.ellipsePath`), as cubics of at most a
    /// quarter turn. Starts with a line to the first point (or a move when
    /// `fresh`).
    pub fn arc(b: *PathBuilder, cx: f32, cy: f32, rx: f32, ry: f32, start: f32, end: f32, fresh: bool) Allocator.Error!void {
        const sweep = end - start;
        const n: usize = @intFromFloat(std.math.clamp(@ceil(@abs(sweep) / 90), 1, 16));
        const step = sweep / @as(f32, @floatFromInt(n)) * std.math.pi / 180.0;
        // Control distance for an arc of `step` radians.
        const k = 4.0 / 3.0 * @tan(step / 4);
        var a0 = start * std.math.pi / 180.0;
        const first = ellipsePoint(cx, cy, rx, ry, a0);
        if (fresh) try b.moveTo(first) else try b.lineTo(first);
        for (0..n) |_| {
            const a1 = a0 + step;
            const p0 = ellipsePoint(cx, cy, rx, ry, a0);
            const p1 = ellipsePoint(cx, cy, rx, ry, a1);
            // Derivative of the point with respect to the angle.
            const d0: Point = .{ rx * @cos(a0), ry * @sin(a0) };
            const d1: Point = .{ rx * @cos(a1), ry * @sin(a1) };
            try b.cubicTo(.{ p0[0] + k * d0[0], p0[1] + k * d0[1] }, .{ p1[0] - k * d1[0], p1[1] - k * d1[1] }, p1);
            a0 = a1;
        }
    }

    /// A rounded rectangle clockwise, from the right end of the top edge
    /// (where `raster.roundRectPath` starts, so dashes line up).
    pub fn roundRect(b: *PathBuilder, x: f32, y: f32, w: f32, h: f32, radius: f32) Allocator.Error!void {
        const r = std.math.clamp(radius, 0, @min(w, h) / 2);
        if (r < 0.5) return b.polyline(&.{ .{ x, y }, .{ x + w, y }, .{ x + w, y + h }, .{ x, y + h } }, true);
        const q = r * kappa;
        try b.moveTo(.{ x + w - r, y });
        try b.cubicTo(.{ x + w - r + q, y }, .{ x + w, y + r - q }, .{ x + w, y + r });
        try b.lineTo(.{ x + w, y + h - r });
        try b.cubicTo(.{ x + w, y + h - r + q }, .{ x + w - r + q, y + h }, .{ x + w - r, y + h });
        try b.lineTo(.{ x + r, y + h });
        try b.cubicTo(.{ x + r - q, y + h }, .{ x, y + h - r + q }, .{ x, y + h - r });
        try b.lineTo(.{ x, y + r });
        try b.cubicTo(.{ x, y + r - q }, .{ x + r - q, y }, .{ x + r, y });
        try b.close();
    }
};

/// The point at `a` radians clockwise from 12 o'clock.
fn ellipsePoint(cx: f32, cy: f32, rx: f32, ry: f32, a: f32) Point {
    return .{ cx + rx * @sin(a), cy - ry * @cos(a) };
}

/// A glyph's outline in font units with y down (so a writer only scales and
/// moves it), as stb_truetype reports it: quadratics for TrueType, cubics
/// for CFF fonts.
pub fn glyphPath(arena: Allocator, font: *const text.Font, gid: u32) Allocator.Error!Path {
    var verts: ?[*]c.stbtt_vertex = null;
    const n = c.stbtt_GetGlyphShape(font.info.ptr, @intCast(gid), &verts);
    if (n <= 0) return .{};
    defer c.stbtt_FreeShape(font.info.ptr, verts);
    var b = PathBuilder.init(arena);
    var open = false;
    for (verts.?[0..@intCast(n)]) |v| {
        const p: Point = .{ @floatFromInt(v.x), -@as(f32, @floatFromInt(v.y)) };
        switch (v.kind) {
            c.stbtt_vertex.move => {
                if (open) try b.close();
                try b.moveTo(p);
                open = true;
            },
            c.stbtt_vertex.line => try b.lineTo(p),
            c.stbtt_vertex.quad => try b.quadTo(.{ @floatFromInt(v.cx), -@as(f32, @floatFromInt(v.cy)) }, p),
            c.stbtt_vertex.cubic => try b.cubicTo(.{ @floatFromInt(v.cx), -@as(f32, @floatFromInt(v.cy)) }, .{ @floatFromInt(v.cx1), -@as(f32, @floatFromInt(v.cy1)) }, p),
            else => {},
        }
    }
    if (open) try b.close();
    return b.finish();
}

// ------------------------------------------------------------------ images

/// A source image file as a vector file embeds it.
pub const Embedded = struct { mime: []const u8, bytes: []u8 };

/// A PNG or JPEG file reduced to its image data, without text, EXIF, XMP,
/// color profiles or data after the image: viewers then show the pixels the
/// renderer decoded (it applies no EXIF orientation and no color profile),
/// and nothing else of the file leaves the project. Null for other formats
/// and for files this cannot take apart; the caller then embeds the decoded
/// pixels. The caller owns `bytes`.
pub fn embeddable(gpa: Allocator, bytes: []const u8) Allocator.Error!?Embedded {
    const png = std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n");
    if (!png and !std.mem.startsWith(u8, bytes, "\xff\xd8\xff")) return null;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    if (!(if (png) try pngImageData(gpa, &out, bytes) else try jpegImageData(gpa, &out, bytes))) return null;
    return .{ .mime = if (png) "image/png" else "image/jpeg", .bytes = try out.toOwnedSlice(gpa) };
}

/// Copies the signature and the IHDR, PLTE, tRNS, IDAT and IEND chunks.
/// False for a broken file or another critical chunk (such as Apple's
/// CgBI), without which viewers could not show it.
fn pngImageData(gpa: Allocator, out: *std.ArrayList(u8), b: []const u8) Allocator.Error!bool {
    try out.appendSlice(gpa, b[0..8]);
    var i: usize = 8;
    while (b.len - i >= 12) {
        const len = std.mem.readInt(u32, b[i..][0..4], .big);
        if (len > b.len - i - 12) return false;
        const kind = b[i + 4 ..][0..4];
        const chunk = b[i .. i + 12 + len];
        i += 12 + len;
        if (std.mem.eql(u8, kind, "IEND")) {
            try out.appendSlice(gpa, chunk);
            return true;
        }
        // Bit 5 of the first letter: 0 for chunks a decoder must understand.
        if (kind[0] & 0x20 == 0) {
            if (!(std.mem.eql(u8, kind, "IHDR") or std.mem.eql(u8, kind, "PLTE") or std.mem.eql(u8, kind, "IDAT"))) return false;
            try out.appendSlice(gpa, chunk);
        } else if (std.mem.eql(u8, kind, "tRNS")) try out.appendSlice(gpa, chunk);
    }
    return false;
}

/// Copies every segment up to the end-of-image marker except APP1 to
/// APP13, APP15 (EXIF, XMP, ICC profile, IPTC, maker notes) and comments.
/// APP0 (JFIF) and APP14 (Adobe) stay: decoders read the color model from
/// them. False for a broken file.
fn jpegImageData(gpa: Allocator, out: *std.ArrayList(u8), b: []const u8) Allocator.Error!bool {
    try out.appendSlice(gpa, b[0..2]);
    var i: usize = 2;
    while (i + 1 < b.len) {
        if (b[i] != 0xff) return false;
        const marker = b[i + 1];
        // Fill bytes before a marker.
        if (marker == 0xff) {
            i += 1;
            continue;
        }
        if (marker == 0xd9) {
            try out.appendSlice(gpa, b[i .. i + 2]);
            return true;
        }
        if (b.len - i < 4) return false;
        const len = std.mem.readInt(u16, b[i + 2 ..][0..2], .big);
        if (len < 2 or len > b.len - i - 2) return false;
        const metadata = (marker >= 0xe1 and marker <= 0xed) or marker == 0xef or marker == 0xfe;
        if (!metadata) try out.appendSlice(gpa, b[i .. i + 2 + len]);
        i += 2 + len;
        if (marker == 0xda) {
            // The coded data of a scan runs to the next marker that is not
            // a stuffed zero byte (FF 00) or a restart marker (FF D0..D7).
            const start = i;
            while (i + 1 < b.len and !(b[i] == 0xff and b[i + 1] != 0 and (b[i + 1] < 0xd0 or b[i + 1] > 0xd7))) i += 1;
            try out.appendSlice(gpa, b[start..i]);
        }
    }
    return false;
}

pub const JpegInfo = struct { w: u32, h: u32, components: u8 };

/// Size and component count from the first start-of-frame segment.
pub fn jpegInfo(b: []const u8) ?JpegInfo {
    var i: usize = 2;
    while (i + 4 <= b.len and b[i] == 0xff) {
        const marker = b[i + 1];
        const len = std.mem.readInt(u16, b[i + 2 ..][0..2], .big);
        if (len < 2 or i + 2 + len > b.len) return null;
        // SOF0..SOF15 except DHT (c4), JPG (c8) and DAC (cc).
        if (marker >= 0xc0 and marker <= 0xcf and marker != 0xc4 and marker != 0xc8 and marker != 0xcc) {
            if (len < 8) return null;
            return .{ .h = std.mem.readInt(u16, b[i + 5 ..][0..2], .big), .w = std.mem.readInt(u16, b[i + 7 ..][0..2], .big), .components = b[i + 9] };
        }
        i += 2 + len;
    }
    return null;
}

// ------------------------------------------------------------------ crop

pub const IRect = struct { x: i32, y: i32, w: u32, h: u32 };

pub const Cropped = struct {
    /// What is kept, in the coordinates before the crop.
    keep: IRect,
    /// Where the kept part ends up.
    to: IRect,
};

/// The geometry of `raster.crop` on a bitmap covering `r`: `len_f` pixels
/// removed from `side`, the rest moved so the anchor (fx, fy) stays put.
/// Null when nothing is removed.
pub fn cropGeometry(r: IRect, side: raster.Side, len_f: f32, fx: f32, fy: f32) ?Cropped {
    const horizontal = side == .left or side == .right;
    const full = if (horizontal) r.w else r.h;
    const len: u32 = @intFromFloat(std.math.clamp(@round(len_f), 0, @as(f32, @floatFromInt(full))));
    if (len == 0) return null;
    const nw = if (horizontal) r.w - len else r.w;
    const nh = if (horizontal) r.h else r.h - len;
    const ox: i32 = if (side == .left) @intCast(len) else 0;
    const oy: i32 = if (side == .top) @intCast(len) else 0;
    const ax = @as(f32, @floatFromInt(r.x)) + fx * @as(f32, @floatFromInt(r.w));
    const ay = @as(f32, @floatFromInt(r.y)) + fy * @as(f32, @floatFromInt(r.h));
    return .{
        .keep = .{ .x = r.x + ox, .y = r.y + oy, .w = nw, .h = nh },
        .to = .{
            .x = @intFromFloat(@round(ax - fx * @as(f32, @floatFromInt(nw)))),
            .y = @intFromFloat(@round(ay - fy * @as(f32, @floatFromInt(nh)))),
            .w = nw,
            .h = nh,
        },
    };
}

test "crop geometry matches raster.crop" {
    const gpa = std.testing.allocator;
    for ([_]raster.Side{ .top, .bottom, .left, .right }) |side| for ([_][2]f32{ .{ 0, 0 }, .{ 0.5, 0.5 }, .{ 1, 1 } }) |anchor| {
        var b = try raster.Bitmap.init(gpa, 13, -7, 41, 23);
        defer b.deinit(gpa);
        const g = cropGeometry(.{ .x = b.x, .y = b.y, .w = b.w, .h = b.h }, side, 9.4, anchor[0], anchor[1]).?;
        try raster.crop(gpa, &b, side, 9.4, anchor[0], anchor[1]);
        try std.testing.expectEqual(g.to.x, b.x);
        try std.testing.expectEqual(g.to.y, b.y);
        try std.testing.expectEqual(g.to.w, b.w);
        try std.testing.expectEqual(g.to.h, b.h);
    };
}

test "arc ends where asked" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var b = PathBuilder.init(arena.allocator());
    try b.arc(100, 100, 50, 30, 0, 90, true);
    const p = b.finish();
    try std.testing.expectEqual(@as(usize, 2), p.cmds.len);
    // 0 degrees is the top, 90 degrees the right end.
    try std.testing.expectApproxEqAbs(@as(f32, 70), p.cmds[0].move[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 150), p.cmds[1].cubic[2][0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), p.cmds[1].cubic[2][1], 0.001);
}

fn testChunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    try w.writeAll(kind);
    try w.writeAll(data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    try w.writeInt(u32, crc.final(), .big);
}

test "embedded images keep only their image data" {
    const gpa = std.testing.allocator;
    var b = try raster.Bitmap.init(gpa, 0, 0, 6, 4);
    defer b.deinit(gpa);
    b.fill(raster.paint(.{ .r = 65535, .g = 0, .b = 0, .a = 32768 }, 1));
    const png = try raster.encodePng(gpa, &b, false);
    defer gpa.free(png);
    // The same file with text, a gamma and an animation chunk, and data
    // after the end: only the image chunks are kept.
    var aw: std.Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    const w = &aw.writer;
    try w.writeAll(png[0..33]); // signature and IHDR
    try testChunk(w, "tEXt", "Author\x00someone");
    try testChunk(w, "gAMA", "\x00\x00\xb1\x8f");
    try testChunk(w, "acTL", "\x00\x00\x00\x01\x00\x00\x00\x00");
    try w.writeAll(png[33..]);
    try w.writeAll("more bytes");
    const e = (try embeddable(gpa, aw.written())).?;
    defer gpa.free(e.bytes);
    try std.testing.expectEqualStrings("image/png", e.mime);
    try std.testing.expectEqualSlices(u8, png, e.bytes);
    // A critical chunk viewers do not know, and a cut file: not embeddable.
    aw.clearRetainingCapacity();
    try w.writeAll(png[0..8]);
    try testChunk(w, "CgBI", "\x50\x00\x20\x06");
    try w.writeAll(png[8..]);
    try std.testing.expect(try embeddable(gpa, aw.written()) == null);
    try std.testing.expect(try embeddable(gpa, png[0 .. png.len - 4]) == null);

    // A JPEG's segments: EXIF, ICC profile and comment go, the coded data
    // (with a stuffed byte and a restart marker) stays, and so does nothing
    // after the end.
    const jfif = "\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00";
    const exif = "\xff\xe1\x00\x0eExif\x00\x00MM\x00\x2a\x00\x00";
    const icc = "\xff\xe2\x00\x08ICC_\x00\x01";
    const dqt = "\xff\xdb\x00\x04\x00\x01";
    const sof = "\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00";
    const com = "\xff\xfe\x00\x06note";
    const sos = "\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00";
    const data = "\x12\xff\x00\x34\xff\xd3\x56";
    const jpeg = "\xff\xd8" ++ jfif ++ exif ++ icc ++ dqt ++ sof ++ com ++ sos ++ data ++ "\xff\xd9" ++ "appended video";
    const j = (try embeddable(gpa, jpeg)).?;
    defer gpa.free(j.bytes);
    try std.testing.expectEqualStrings("image/jpeg", j.mime);
    try std.testing.expectEqualSlices(u8, "\xff\xd8" ++ jfif ++ dqt ++ sof ++ sos ++ data ++ "\xff\xd9", j.bytes);
    // No end-of-image marker, or a segment longer than the file.
    try std.testing.expect(try embeddable(gpa, jpeg[0 .. jpeg.len - 16]) == null);
    try std.testing.expect(try embeddable(gpa, "\xff\xd8\xff\xe1\x01\x00Exif") == null);
    try std.testing.expect(try embeddable(gpa, "GIF89a") == null);
}
