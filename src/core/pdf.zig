//! A minimal PDF writer: one page per card, the card as an image. The page
//! size comes from `canvas.dpi` (72 when unknown, one pixel per point);
//! `canvas.bleed` sets the TrimBox and BleedBox.

const std = @import("std");
const raster = @import("raster.zig");
const Allocator = std.mem.Allocator;

/// One card's compressed pixels and page geometry.
pub const Page = struct {
    w: u32,
    h: u32,
    dpi: f64,
    bleed: f64,
    margin: f64,
    rgb: []u8,
    /// Soft mask; null when every pixel is opaque.
    alpha: ?[]u8,

    pub fn init(gpa: Allocator, b: *const raster.Bitmap) !Page {
        const n = @as(usize, b.w) * b.h;
        const rgb = try gpa.alloc(u8, n * 3);
        defer gpa.free(rgb);
        const alpha = try gpa.alloc(u8, n);
        defer gpa.free(alpha);
        var opaque_all = true;
        for (0..n) |i| {
            const p = b.px[i * 4 ..][0..4];
            const a: u32 = p[3];
            alpha[i] = @intCast((a * 255 + 32767) / 65535);
            if (alpha[i] != 255) opaque_all = false;
            inline for (0..3) |k| {
                const straight: u32 = if (a == 0) 0 else @min(65535, (@as(u32, p[k]) * 65535 + a / 2) / a);
                rgb[i * 3 + k] = @intCast((straight * 255 + 32767) / 65535);
            }
        }
        const rgb_z = try raster.deflate(gpa, rgb);
        errdefer gpa.free(rgb_z);
        return .{ .w = b.w, .h = b.h, .dpi = b.dpi, .bleed = b.bleed, .margin = b.margin, .rgb = rgb_z, .alpha = if (opaque_all) null else try raster.deflate(gpa, alpha) };
    }

    pub fn deinit(p: *Page, gpa: Allocator) void {
        gpa.free(p.rgb);
        if (p.alpha) |a| gpa.free(a);
    }
};

pub const Writer = struct {
    gpa: Allocator,
    out: std.Io.Writer.Allocating,
    /// Byte offset of every object, by object number - 1.
    offsets: std.ArrayList(usize) = .empty,
    pages: std.ArrayList(u32) = .empty,

    pub fn init(gpa: Allocator) Allocator.Error!Writer {
        var w: Writer = .{ .gpa = gpa, .out = .init(gpa) };
        errdefer w.out.deinit();
        w.out.writer.writeAll("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n") catch return error.OutOfMemory;
        // Objects 1 (catalog) and 2 (pages) are written by `finish`.
        try w.offsets.appendSlice(gpa, &.{ 0, 0 });
        return w;
    }

    pub fn deinit(w: *Writer) void {
        w.out.deinit();
        w.offsets.deinit(w.gpa);
        w.pages.deinit(w.gpa);
    }

    fn begin(w: *Writer) Allocator.Error!u32 {
        try w.offsets.append(w.gpa, w.out.written().len);
        const n: u32 = @intCast(w.offsets.items.len);
        w.out.writer.print("{d} 0 obj\n", .{n}) catch return error.OutOfMemory;
        return n;
    }

    fn beginReserved(w: *Writer, n: u32) Allocator.Error!void {
        w.offsets.items[n - 1] = w.out.written().len;
        w.out.writer.print("{d} 0 obj\n", .{n}) catch return error.OutOfMemory;
    }

    fn stream(w: *Writer, dict: []const u8, data: []const u8) Allocator.Error!void {
        const o = &w.out.writer;
        o.print("<< {s} /Length {d} >>\nstream\n", .{ dict, data.len }) catch return error.OutOfMemory;
        o.writeAll(data) catch return error.OutOfMemory;
        o.writeAll("\nendstream\nendobj\n") catch return error.OutOfMemory;
    }

    /// Adds one page showing `b` (with its dpi, bleed and crop-mark margin).
    pub fn addPage(w: *Writer, b: *const raster.Bitmap) !void {
        var page = try Page.init(w.gpa, b);
        defer page.deinit(w.gpa);
        try w.addPrepared(&page);
    }

    /// Adds a page prepared (perhaps on another thread) with `Page.init`.
    pub fn addPrepared(w: *Writer, pg: *const Page) !void {
        var smask: ?u32 = null;
        if (pg.alpha) |z| {
            smask = try w.begin();
            var buf: [160]u8 = undefined;
            try w.stream(try std.fmt.bufPrint(&buf, "/Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode", .{ pg.w, pg.h }), z);
        }
        const img = try w.begin();
        {
            var buf: [200]u8 = undefined;
            var sm: [32]u8 = undefined;
            const sm_text = if (smask) |sid| try std.fmt.bufPrint(&sm, " /SMask {d} 0 R", .{sid}) else "";
            try w.stream(try std.fmt.bufPrint(&buf, "/Type /XObject /Subtype /Image /Width {d} /Height {d} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode{s}", .{ pg.w, pg.h, sm_text }), pg.rgb);
        }
        const k: f64 = 72.0 / (if (pg.dpi > 0) pg.dpi else 72.0);
        const pw = @as(f64, @floatFromInt(pg.w)) * k;
        const ph = @as(f64, @floatFromInt(pg.h)) * k;
        const content = blk: {
            var buf: [128]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "q {d:.4} 0 0 {d:.4} 0 0 cm /Im0 Do Q", .{ pw, ph });
            const id = try w.begin();
            try w.stream("", text);
            break :blk id;
        };
        const page = try w.begin();
        // Boxes in PDF points, origin bottom-left; the bleed box is the card,
        // the trim box is inside it by `bleed`.
        const m = pg.margin * k;
        const bl = pg.bleed * k;
        w.out.writer.print(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {d:.4} {d:.4}] /BleedBox [{d:.4} {d:.4} {d:.4} {d:.4}] /TrimBox [{d:.4} {d:.4} {d:.4} {d:.4}] /Resources << /XObject << /Im0 {d} 0 R >> >> /Contents {d} 0 R >>\nendobj\n",
            .{ pw, ph, m, m, pw - m, ph - m, m + bl, m + bl, pw - m - bl, ph - m - bl, img, content },
        ) catch return error.OutOfMemory;
        try w.pages.append(w.gpa, page);
    }

    /// The finished file. The writer can be deinitialised afterwards.
    pub fn finish(w: *Writer) Allocator.Error![]u8 {
        const o = &w.out.writer;
        try w.beginReserved(1);
        o.writeAll("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n") catch return error.OutOfMemory;
        try w.beginReserved(2);
        o.writeAll("<< /Type /Pages /Kids [") catch return error.OutOfMemory;
        for (w.pages.items, 0..) |p, i| o.print("{s}{d} 0 R", .{ if (i > 0) " " else "", p }) catch return error.OutOfMemory;
        o.print("] /Count {d} >>\nendobj\n", .{w.pages.items.len}) catch return error.OutOfMemory;
        const xref = w.out.written().len;
        o.print("xref\n0 {d}\n0000000000 65535 f \n", .{w.offsets.items.len + 1}) catch return error.OutOfMemory;
        for (w.offsets.items) |off| o.print("{d:0>10} 00000 n \n", .{off}) catch return error.OutOfMemory;
        o.print("trailer\n<< /Size {d} /Root 1 0 R >>\nstartxref\n{d}\n%%EOF\n", .{ w.offsets.items.len + 1, xref }) catch return error.OutOfMemory;
        return w.out.toOwnedSlice() catch return error.OutOfMemory;
    }
};

test "pdf with one page" {
    const gpa = std.testing.allocator;
    var b = try raster.Bitmap.init(gpa, 0, 0, 4, 2);
    defer b.deinit(gpa);
    b.fill(.{ 65535, 0, 0, 65535 });
    b.dpi = 144;
    var w = try Writer.init(gpa);
    defer w.deinit();
    try w.addPage(&b);
    const out = try w.finish();
    defer gpa.free(out);
    try std.testing.expect(std.mem.startsWith(u8, out, "%PDF-1.4"));
    try std.testing.expect(std.mem.indexOf(u8, out, "/MediaBox [0 0 2.0000 1.0000]") != null);
    try std.testing.expect(std.mem.endsWith(u8, out, "%%EOF\n"));
}
