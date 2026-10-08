//! Pixels: premultiplied 16-bit RGBA bitmaps, anti-aliased shapes, image
//! sampling, effects, compositing and PNG encoding (FORMAT.md section 8).

const std = @import("std");
const Color = @import("value.zig").Color;
const Allocator = std.mem.Allocator;

/// Premultiplied RGBA, each channel 0..65535.
pub const Paint = [4]f32;

pub fn paint(c: Color, opacity: f64) Paint {
    const a = @as(f32, @floatFromInt(c.a)) * @as(f32, @floatCast(std.math.clamp(opacity, 0, 1)));
    const k = a / 65535.0;
    return .{
        @as(f32, @floatFromInt(c.r)) * k,
        @as(f32, @floatFromInt(c.g)) * k,
        @as(f32, @floatFromInt(c.b)) * k,
        a,
    };
}

pub const Bitmap = struct {
    /// Position of the top-left pixel on the canvas.
    x: i32 = 0,
    y: i32 = 0,
    w: u32,
    h: u32,
    /// Premultiplied RGBA, row-major, 4 values per pixel.
    px: []u16,

    pub fn init(gpa: Allocator, x: i32, y: i32, w: u32, h: u32) Allocator.Error!Bitmap {
        const px = try gpa.alloc(u16, @as(usize, w) * h * 4);
        @memset(px, 0);
        return .{ .x = x, .y = y, .w = w, .h = h, .px = px };
    }

    pub fn deinit(b: *Bitmap, gpa: Allocator) void {
        gpa.free(b.px);
        b.* = undefined;
    }

    pub fn fill(b: *Bitmap, p: Paint) void {
        const v = [4]u16{ q16(p[0]), q16(p[1]), q16(p[2]), q16(p[3]) };
        var i: usize = 0;
        while (i < b.px.len) : (i += 4) @memcpy(b.px[i..][0..4], &v);
    }

    /// Blends `p` scaled by coverage onto canvas pixel (cx, cy), source-over.
    pub inline fn blend(b: *Bitmap, cx: i32, cy: i32, p: Paint, cov: f32) void {
        const lx = cx - b.x;
        const ly = cy - b.y;
        if (lx < 0 or ly < 0 or lx >= b.w or ly >= b.h) return;
        blendAt(b.px[(@as(usize, @intCast(ly)) * b.w + @as(usize, @intCast(lx))) * 4 ..][0..4], p, cov);
    }

    /// Pixel rectangle (canvas coordinates) clipped to this bitmap.
    pub fn clip(b: *const Bitmap, x0: i64, y0: i64, x1: i64, y1: i64) ?[4]i32 {
        const cx0 = @max(x0, b.x);
        const cy0 = @max(y0, b.y);
        const cx1 = @min(x1, @as(i64, b.x) + b.w);
        const cy1 = @min(y1, @as(i64, b.y) + b.h);
        if (cx0 >= cx1 or cy0 >= cy1) return null;
        return .{ @intCast(cx0), @intCast(cy0), @intCast(cx1), @intCast(cy1) };
    }
};

inline fn q16(v: f32) u16 {
    return @intFromFloat(std.math.clamp(v + 0.5, 0, 65535));
}

inline fn blendAt(d: *[4]u16, p: Paint, cov: f32) void {
    if (cov <= 0) return;
    const c = @min(cov, 1);
    const sa = p[3] * c;
    if (sa <= 0) return;
    const inv = 1 - sa / 65535.0;
    inline for (0..4) |i| {
        d[i] = q16(p[i] * c + @as(f32, @floatFromInt(d[i])) * inv);
    }
}

/// Source-over of `src` onto `dst` at their canvas positions.
pub fn composite(dst: *Bitmap, src: *const Bitmap) void {
    const r = dst.clip(src.x, src.y, @as(i64, src.x) + src.w, @as(i64, src.y) + src.h) orelse return;
    var y = r[1];
    while (y < r[3]) : (y += 1) {
        const sy: usize = @intCast(y - src.y);
        const dy: usize = @intCast(y - dst.y);
        var x = r[0];
        while (x < r[2]) : (x += 1) {
            const s = src.px[(sy * src.w + @as(usize, @intCast(x - src.x))) * 4 ..][0..4];
            if (s[3] == 0) continue;
            const d = dst.px[(dy * dst.w + @as(usize, @intCast(x - dst.x))) * 4 ..][0..4];
            if (s[3] == 65535) {
                @memcpy(d, s);
                continue;
            }
            const inv: u32 = 65535 - s[3];
            inline for (0..4) |i| {
                d[i] = @intCast(@min(65535, @as(u32, s[i]) + (@as(u32, d[i]) * inv + 32767) / 65535));
            }
        }
    }
}

/// Composites `src` rotated by `angle` radians (clockwise on screen) around
/// the canvas point (`pivot_x`, `pivot_y`), sampling bilinearly, with
/// `opacity` applied.
pub fn compositeRotated(dst: *Bitmap, src: *const Bitmap, angle: f32, pivot_x: f32, pivot_y: f32, opacity: f32) void {
    const cs = @cos(angle);
    const sn = @sin(angle);
    // Destination bounds: the rotated corners of the source rectangle.
    const sx0: f32 = @floatFromInt(src.x);
    const sy0: f32 = @floatFromInt(src.y);
    const sx1 = sx0 + @as(f32, @floatFromInt(src.w));
    const sy1 = sy0 + @as(f32, @floatFromInt(src.h));
    var min_x: f32 = std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    for ([_][2]f32{ .{ sx0, sy0 }, .{ sx1, sy0 }, .{ sx0, sy1 }, .{ sx1, sy1 } }) |p| {
        const dx = p[0] - pivot_x;
        const dy = p[1] - pivot_y;
        const x = pivot_x + cs * dx - sn * dy;
        const y = pivot_y + sn * dx + cs * dy;
        min_x = @min(min_x, x);
        min_y = @min(min_y, y);
        max_x = @max(max_x, x);
        max_y = @max(max_y, y);
    }
    const r = dst.clip(@intFromFloat(@floor(min_x)), @intFromFloat(@floor(min_y)), @intFromFloat(@ceil(max_x)), @intFromFloat(@ceil(max_y))) orelse return;
    const op = std.math.clamp(opacity, 0, 1);
    const sw: i32 = @intCast(src.w);
    const sh: i32 = @intCast(src.h);
    var y = r[1];
    while (y < r[3]) : (y += 1) {
        var x = r[0];
        while (x < r[2]) : (x += 1) {
            // Inverse rotation of the destination pixel centre into source pixels.
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - pivot_x;
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - pivot_y;
            const fx = pivot_x + cs * dx + sn * dy - sx0 - 0.5;
            const fy = pivot_y - sn * dx + cs * dy - sy0 - 0.5;
            if (fx <= -1 or fy <= -1 or fx >= @as(f32, @floatFromInt(sw)) or fy >= @as(f32, @floatFromInt(sh))) continue;
            const ix: i32 = @intFromFloat(@floor(fx));
            const iy: i32 = @intFromFloat(@floor(fy));
            const tx = fx - @as(f32, @floatFromInt(ix));
            const ty = fy - @as(f32, @floatFromInt(iy));
            var acc = [4]f32{ 0, 0, 0, 0 };
            inline for (.{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |o| {
                const px = ix + o[0];
                const py = iy + o[1];
                if (px >= 0 and py >= 0 and px < sw and py < sh) {
                    const wgt = (if (o[0] == 0) 1 - tx else tx) * (if (o[1] == 0) 1 - ty else ty);
                    const s = src.px[(@as(usize, @intCast(py)) * src.w + @as(usize, @intCast(px))) * 4 ..][0..4];
                    inline for (0..4) |i| acc[i] += wgt * @as(f32, @floatFromInt(s[i]));
                }
            }
            if (acc[3] < 0.5) continue;
            const d = dst.px[(@as(usize, @intCast(y - dst.y)) * dst.w + @as(usize, @intCast(x - dst.x))) * 4 ..][0..4];
            const sa = acc[3] * op;
            const inv = 1 - sa / 65535;
            inline for (0..4) |i| {
                const v = acc[i] * op + @as(f32, @floatFromInt(d[i])) * inv;
                d[i] = @intFromFloat(std.math.clamp(@round(v), 0, 65535));
            }
        }
    }
}

// ------------------------------------------------------------------ shapes

pub const StrokeStyle = struct { paint: Paint, width: f32 };

/// Rounded rectangle via a signed distance field. Covers rect and ellipse
/// (ellipse uses an approximate distance).
pub fn drawShape(b: *Bitmap, kind: enum { rect, ellipse }, x: f32, y: f32, w: f32, h: f32, radius: f32, fill: ?Paint, stroke: ?StrokeStyle) void {
    const sw = if (stroke) |s| s.width else 0;
    const m = sw / 2 + 1;
    const r = b.clip(@intFromFloat(@floor(x - m)), @intFromFloat(@floor(y - m)), @intFromFloat(@ceil(x + w + m)), @intFromFloat(@ceil(y + h + m))) orelse return;
    const hw = w / 2;
    const hh = h / 2;
    const cx = x + hw;
    const cy = y + hh;
    const rad = std.math.clamp(radius, 0, @min(hw, hh));
    var py = r[1];
    while (py < r[3]) : (py += 1) {
        const fy = @as(f32, @floatFromInt(py)) + 0.5 - cy;
        var px = r[0];
        while (px < r[2]) : (px += 1) {
            const fx = @as(f32, @floatFromInt(px)) + 0.5 - cx;
            const d = switch (kind) {
                .rect => sdRoundBox(fx, fy, hw, hh, rad),
                .ellipse => sdEllipse(fx, fy, hw, hh),
            };
            if (fill) |f| b.blend(px, py, f, std.math.clamp(0.5 - d, 0, 1));
            if (stroke) |s| if (s.width > 0) {
                b.blend(px, py, s.paint, std.math.clamp(s.width / 2 + 0.5 - @abs(d), 0, 1) * @min(1, s.width));
            };
        }
    }
}

fn sdRoundBox(px: f32, py: f32, hw: f32, hh: f32, r: f32) f32 {
    const qx = @abs(px) - (hw - r);
    const qy = @abs(py) - (hh - r);
    const ox = @max(qx, 0);
    const oy = @max(qy, 0);
    return @sqrt(ox * ox + oy * oy) + @min(@max(qx, qy), 0) - r;
}

fn sdEllipse(px: f32, py: f32, a: f32, b: f32) f32 {
    if (a <= 0 or b <= 0) return 1e9;
    const k1 = @sqrt((px / a) * (px / a) + (py / b) * (py / b));
    const k2 = @sqrt((px / (a * a)) * (px / (a * a)) + (py / (b * b)) * (py / (b * b)));
    if (k2 == 0) return -@min(a, b);
    return k1 * (k1 - 1) / k2;
}

/// Polygon fill with the nonzero rule, anti-aliased with 16 sub-scanlines.
pub fn fillPolygon(gpa: Allocator, b: *Bitmap, pts: []const [2]f32, p: Paint) Allocator.Error!void {
    if (pts.len < 3) return;
    var minx: f32 = pts[0][0];
    var maxx: f32 = pts[0][0];
    var miny: f32 = pts[0][1];
    var maxy: f32 = pts[0][1];
    for (pts) |q| {
        minx = @min(minx, q[0]);
        maxx = @max(maxx, q[0]);
        miny = @min(miny, q[1]);
        maxy = @max(maxy, q[1]);
    }
    const r = b.clip(@intFromFloat(@floor(minx)), @intFromFloat(@floor(miny)), @intFromFloat(@ceil(maxx)), @intFromFloat(@ceil(maxy))) orelse return;
    const width: usize = @intCast(r[2] - r[0]);
    const cov = try gpa.alloc(f32, width);
    defer gpa.free(cov);
    const Cross = struct { x: f32, dir: i32 };
    var xs: std.ArrayList(Cross) = .empty;
    defer xs.deinit(gpa);
    const subs = 16;
    const x0f: f32 = @floatFromInt(r[0]);
    var py = r[1];
    while (py < r[3]) : (py += 1) {
        @memset(cov, 0);
        var any = false;
        for (0..subs) |s| {
            const sy = @as(f32, @floatFromInt(py)) + (@as(f32, @floatFromInt(s)) + 0.5) / subs;
            xs.clearRetainingCapacity();
            for (pts, 0..) |a, i| {
                const c = pts[(i + 1) % pts.len];
                if ((a[1] <= sy) == (c[1] <= sy)) continue;
                const t = (sy - a[1]) / (c[1] - a[1]);
                try xs.append(gpa, .{ .x = a[0] + t * (c[0] - a[0]), .dir = if (c[1] > a[1]) 1 else -1 });
            }
            std.mem.sort(Cross, xs.items, {}, struct {
                fn lt(_: void, l: Cross, rr: Cross) bool {
                    return l.x < rr.x;
                }
            }.lt);
            var wind: i32 = 0;
            for (xs.items, 0..) |cr, i| {
                const prev = wind;
                wind += cr.dir;
                if (prev != 0 or wind == 0 or i + 1 >= xs.items.len) continue;
                // Span from cr.x to the point where the winding returns to zero.
                var j = i + 1;
                var w2 = wind;
                while (j < xs.items.len) : (j += 1) {
                    w2 += xs.items[j].dir;
                    if (w2 == 0) break;
                }
                if (j >= xs.items.len) j = xs.items.len - 1;
                addSpan(cov, cr.x - x0f, xs.items[j].x - x0f, 1.0 / @as(f32, subs));
                any = true;
            }
        }
        if (!any) continue;
        for (cov, 0..) |c, i| {
            if (c > 0) b.blend(r[0] + @as(i32, @intCast(i)), py, p, c);
        }
    }
}

fn addSpan(cov: []f32, a: f32, c: f32, weight: f32) void {
    const lo = @max(a, 0);
    const hi = @min(c, @as(f32, @floatFromInt(cov.len)));
    if (hi <= lo) return;
    const ia: usize = @intFromFloat(@floor(lo));
    const ib: usize = @min(cov.len - 1, @as(usize, @intFromFloat(@floor(hi))));
    if (ia == ib) {
        cov[ia] += (hi - lo) * weight;
        return;
    }
    cov[ia] += (@as(f32, @floatFromInt(ia + 1)) - lo) * weight;
    for (cov[ia + 1 .. ib]) |*v| v.* += weight;
    if (ib < cov.len) cov[ib] += (hi - @as(f32, @floatFromInt(ib))) * weight;
}

/// Polyline stroke with round joins and caps.
pub fn strokePolyline(b: *Bitmap, pts: []const [2]f32, closed: bool, s: StrokeStyle) void {
    if (pts.len < 2 or s.width <= 0) return;
    const hw = s.width / 2;
    var minx: f32 = pts[0][0];
    var maxx: f32 = pts[0][0];
    var miny: f32 = pts[0][1];
    var maxy: f32 = pts[0][1];
    for (pts) |q| {
        minx = @min(minx, q[0]);
        maxx = @max(maxx, q[0]);
        miny = @min(miny, q[1]);
        maxy = @max(maxy, q[1]);
    }
    const m = hw + 1;
    const nseg = if (closed) pts.len else pts.len - 1;
    // Walk each segment's bounding box; take the minimum distance over all segments per pixel.
    const r = b.clip(@intFromFloat(@floor(minx - m)), @intFromFloat(@floor(miny - m)), @intFromFloat(@ceil(maxx + m)), @intFromFloat(@ceil(maxy + m))) orelse return;
    var py = r[1];
    while (py < r[3]) : (py += 1) {
        const fy = @as(f32, @floatFromInt(py)) + 0.5;
        var px = r[0];
        while (px < r[2]) : (px += 1) {
            const fx = @as(f32, @floatFromInt(px)) + 0.5;
            var best: f32 = 1e9;
            for (0..nseg) |i| {
                const a = pts[i];
                const c = pts[(i + 1) % pts.len];
                // Quick reject by segment bounding box.
                if (fx < @min(a[0], c[0]) - m or fx > @max(a[0], c[0]) + m or fy < @min(a[1], c[1]) - m or fy > @max(a[1], c[1]) + m) continue;
                best = @min(best, segDist(fx, fy, a, c));
            }
            const cov = std.math.clamp(hw + 0.5 - best, 0, 1) * @min(1, s.width);
            if (cov > 0) b.blend(px, py, s.paint, cov);
        }
    }
}

fn segDist(px: f32, py: f32, a: [2]f32, c: [2]f32) f32 {
    const dx = c[0] - a[0];
    const dy = c[1] - a[1];
    const l2 = dx * dx + dy * dy;
    const t = if (l2 == 0) 0 else std.math.clamp(((px - a[0]) * dx + (py - a[1]) * dy) / l2, 0, 1);
    const ex = px - (a[0] + t * dx);
    const ey = py - (a[1] + t * dy);
    return @sqrt(ex * ex + ey * ey);
}

/// Blends an 8-bit coverage mask (a glyph) at canvas position (x, y).
pub fn blitMask(b: *Bitmap, x: i32, y: i32, mask: []const u8, w: usize, h: usize, p: Paint) void {
    for (0..h) |j| {
        for (0..w) |i| {
            const m = mask[j * w + i];
            if (m == 0) continue;
            b.blend(x + @as(i32, @intCast(i)), y + @as(i32, @intCast(j)), p, @as(f32, @floatFromInt(m)) / 255.0);
        }
    }
}

// ------------------------------------------------------------------ images

/// A decoded image, premultiplied RGBA 16-bit, with a chain of halved copies
/// for good-quality downscaling.
pub const Image = struct {
    w: u32,
    h: u32,
    px: []u16,
    half: ?*Image = null,

    pub fn deinit(img: *Image, gpa: Allocator) void {
        if (img.half) |h| {
            h.deinit(gpa);
            gpa.destroy(h);
        }
        gpa.free(img.px);
    }

    /// Builds from straight-alpha 16-bit RGBA.
    pub fn fromStraight(gpa: Allocator, w: u32, h: u32, straight: []const u16) Allocator.Error!Image {
        const px = try gpa.alloc(u16, @as(usize, w) * h * 4);
        var i: usize = 0;
        while (i < px.len) : (i += 4) {
            const a: u32 = straight[i + 3];
            inline for (0..3) |k| px[i + k] = @intCast((@as(u32, straight[i + k]) * a + 32767) / 65535);
            px[i + 3] = @intCast(a);
        }
        return .{ .w = w, .h = h, .px = px };
    }

    fn halved(img: *Image, gpa: Allocator) Allocator.Error!?*Image {
        if (img.half) |h| return h;
        if (img.w < 2 or img.h < 2) return null;
        const nw = img.w / 2;
        const nh = img.h / 2;
        const px = try gpa.alloc(u16, @as(usize, nw) * nh * 4);
        for (0..nh) |y| for (0..nw) |x| {
            inline for (0..4) |k| {
                const s = @as(u32, img.at(x * 2, y * 2)[k]) + img.at(x * 2 + 1, y * 2)[k] + img.at(x * 2, y * 2 + 1)[k] + img.at(x * 2 + 1, y * 2 + 1)[k];
                px[(y * nw + x) * 4 + k] = @intCast((s + 2) / 4);
            }
        };
        const h = try gpa.create(Image);
        h.* = .{ .w = nw, .h = nh, .px = px };
        img.half = h;
        return h;
    }

    inline fn at(img: *const Image, x: usize, y: usize) *const [4]u16 {
        return img.px[(y * img.w + x) * 4 ..][0..4];
    }

    fn sample(img: *const Image, u: f32, v: f32, bilinear: bool) Paint {
        const fw: f32 = @floatFromInt(img.w);
        const fh: f32 = @floatFromInt(img.h);
        if (!bilinear) {
            const x: usize = @intFromFloat(std.math.clamp(@floor(u), 0, fw - 1));
            const y: usize = @intFromFloat(std.math.clamp(@floor(v), 0, fh - 1));
            const s = img.at(x, y);
            return .{ @floatFromInt(s[0]), @floatFromInt(s[1]), @floatFromInt(s[2]), @floatFromInt(s[3]) };
        }
        const sx = std.math.clamp(u - 0.5, 0, fw - 1);
        const sy = std.math.clamp(v - 0.5, 0, fh - 1);
        const x0: usize = @intFromFloat(@floor(sx));
        const y0: usize = @intFromFloat(@floor(sy));
        const x1 = @min(x0 + 1, img.w - 1);
        const y1 = @min(y0 + 1, img.h - 1);
        const tx = sx - @as(f32, @floatFromInt(x0));
        const ty = sy - @as(f32, @floatFromInt(y0));
        var out: Paint = undefined;
        inline for (0..4) |k| {
            const a = @as(f32, @floatFromInt(img.at(x0, y0)[k])) * (1 - tx) + @as(f32, @floatFromInt(img.at(x1, y0)[k])) * tx;
            const c = @as(f32, @floatFromInt(img.at(x0, y1)[k])) * (1 - tx) + @as(f32, @floatFromInt(img.at(x1, y1)[k])) * tx;
            out[k] = a * (1 - ty) + c * ty;
        }
        return out;
    }

    /// Alpha-weighted average color.
    pub fn average(img: *const Image) Color {
        var sum: [4]f64 = .{ 0, 0, 0, 0 };
        var i: usize = 0;
        while (i < img.px.len) : (i += 4) {
            inline for (0..4) |k| sum[k] += @floatFromInt(img.px[i + k]);
        }
        if (sum[3] == 0) return Color.transparent;
        return .{
            .r = @intFromFloat(@round(sum[0] / sum[3] * 65535)),
            .g = @intFromFloat(@round(sum[1] / sum[3] * 65535)),
            .b = @intFromFloat(@round(sum[2] / sum[3] * 65535)),
            .a = 65535,
        };
    }
};

/// Draws `img` stretched to the destination rectangle, clipped to `clip_rect`.
pub fn drawImage(gpa: Allocator, b: *Bitmap, img: *Image, dx: f32, dy: f32, dw: f32, dh: f32, clip_rect: [4]f32, bilinear: bool, opacity: f32) Allocator.Error!void {
    if (dw <= 0 or dh <= 0) return;
    // Pick a pre-shrunk copy so each step scales down by at most 2x.
    var src: *Image = img;
    if (bilinear) {
        while (@as(f32, @floatFromInt(src.w)) > dw * 2 and @as(f32, @floatFromInt(src.h)) > dh * 2) {
            src = (try src.halved(gpa)) orelse break;
        }
    }
    const cx0 = @max(dx, clip_rect[0]);
    const cy0 = @max(dy, clip_rect[1]);
    const cx1 = @min(dx + dw, clip_rect[2]);
    const cy1 = @min(dy + dh, clip_rect[3]);
    if (cx1 <= cx0 or cy1 <= cy0) return;
    const r = b.clip(@intFromFloat(@floor(cx0)), @intFromFloat(@floor(cy0)), @intFromFloat(@ceil(cx1)), @intFromFloat(@ceil(cy1))) orelse return;
    const sxk = @as(f32, @floatFromInt(src.w)) / dw;
    const syk = @as(f32, @floatFromInt(src.h)) / dh;
    var py = r[1];
    while (py < r[3]) : (py += 1) {
        const fy = @as(f32, @floatFromInt(py));
        const covy = @max(0, @min(fy + 1, cy1) - @max(fy, cy0));
        const v = (fy + 0.5 - dy) * syk;
        var px = r[0];
        while (px < r[2]) : (px += 1) {
            const fx = @as(f32, @floatFromInt(px));
            const covx = @max(0, @min(fx + 1, cx1) - @max(fx, cx0));
            const s = src.sample((fx + 0.5 - dx) * sxk, v, bilinear);
            b.blend(px, py, s, covx * covy * opacity);
        }
    }
}

/// Grey checkerboard used in previews for images that are missing.
pub fn drawPlaceholder(b: *Bitmap, x: f32, y: f32, w: f32, h: f32) void {
    const r = b.clip(@intFromFloat(@floor(x)), @intFromFloat(@floor(y)), @intFromFloat(@ceil(x + w)), @intFromFloat(@ceil(y + h))) orelse return;
    const light = paint(.{ .r = 52000, .g = 52000, .b = 52000, .a = 65535 }, 1);
    const dark = paint(.{ .r = 38000, .g = 38000, .b = 38000, .a = 65535 }, 1);
    const cell: i32 = @max(8, @as(i32, @intFromFloat(@min(w, h) / 8)));
    var py = r[1];
    while (py < r[3]) : (py += 1) {
        var px = r[0];
        while (px < r[2]) : (px += 1) {
            const odd = @mod(@divFloor(px - r[0], cell) + @divFloor(py - r[1], cell), 2) == 1;
            b.blend(px, py, if (odd) dark else light, 1);
        }
    }
}

// ------------------------------------------------------------------ effects

pub fn multiplyOpacity(b: *Bitmap, opacity: f32) void {
    const k = std.math.clamp(opacity, 0, 1);
    if (k >= 1) return;
    for (b.px) |*v| v.* = @intFromFloat(@as(f32, @floatFromInt(v.*)) * k + 0.5);
}

pub const Side = enum { top, bottom, left, right };

/// Alpha ramps to transparent over the last `len` pixels toward `side`.
pub fn fade(b: *Bitmap, side: Side, len: f32) void {
    if (len <= 0) return;
    for (0..b.h) |y| for (0..b.w) |x| {
        const dist: f32 = switch (side) {
            .top => @floatFromInt(y),
            .bottom => @floatFromInt(b.h - 1 - y),
            .left => @floatFromInt(x),
            .right => @floatFromInt(b.w - 1 - x),
        };
        const t = (dist + 0.5) / len;
        if (t >= 1) continue;
        const p = b.px[(y * b.w + x) * 4 ..][0..4];
        for (p) |*v| v.* = @intFromFloat(@as(f32, @floatFromInt(v.*)) * @max(0, t) + 0.5);
    };
}

/// Removes `len` pixels from `side`; the rest keeps the anchor point (fx, fy).
pub fn crop(gpa: Allocator, b: *Bitmap, side: Side, len_f: f32, fx: f32, fy: f32) Allocator.Error!void {
    const full = if (side == .left or side == .right) b.w else b.h;
    const len: u32 = @intFromFloat(std.math.clamp(@round(len_f), 0, @as(f32, @floatFromInt(full))));
    if (len == 0) return;
    const nw = if (side == .left or side == .right) b.w - len else b.w;
    const nh = if (side == .top or side == .bottom) b.h - len else b.h;
    const ox: u32 = if (side == .left) len else 0;
    const oy: u32 = if (side == .top) len else 0;
    const px = try gpa.alloc(u16, @as(usize, nw) * nh * 4);
    for (0..nh) |y| {
        const s = b.px[((y + oy) * b.w + ox) * 4 ..][0 .. nw * 4];
        @memcpy(px[y * nw * 4 ..][0 .. nw * 4], s);
    }
    const ax = @as(f32, @floatFromInt(b.x)) + fx * @as(f32, @floatFromInt(b.w));
    const ay = @as(f32, @floatFromInt(b.y)) + fy * @as(f32, @floatFromInt(b.h));
    gpa.free(b.px);
    b.px = px;
    b.w = nw;
    b.h = nh;
    b.x = @intFromFloat(@round(ax - fx * @as(f32, @floatFromInt(nw))));
    b.y = @intFromFloat(@round(ay - fy * @as(f32, @floatFromInt(nh))));
}

pub const Filter = enum { sharpen, detail, edge_enhance, find_edges };

/// 3x3 convolutions with the kernels of Pillow's ImageFilter, blended with the
/// original by `strength` (1 = the plain filter).
pub fn convolve(gpa: Allocator, b: *Bitmap, f: Filter, strength: f32) Allocator.Error!void {
    const k: [9]f32, const div: f32 = switch (f) {
        .sharpen => .{ .{ -2, -2, -2, -2, 32, -2, -2, -2, -2 }, 16 },
        .detail => .{ .{ 0, -1, 0, -1, 10, -1, 0, -1, 0 }, 6 },
        .edge_enhance => .{ .{ -1, -1, -1, -1, 10, -1, -1, -1, -1 }, 2 },
        .find_edges => .{ .{ -1, -1, -1, -1, 8, -1, -1, -1, -1 }, 1 },
    };
    const src = try gpa.dupe(u16, b.px);
    defer gpa.free(src);
    const w: i64 = b.w;
    const h: i64 = b.h;
    for (0..b.h) |yu| for (0..b.w) |xu| {
        const y: i64 = @intCast(yu);
        const x: i64 = @intCast(xu);
        const o = (yu * b.w + xu) * 4;
        const a = src[o + 3];
        var acc: [3]f32 = .{ 0, 0, 0 };
        var ki: usize = 0;
        var dy: i64 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i64 = -1;
            while (dx <= 1) : (dx += 1) {
                const sx: usize = @intCast(std.math.clamp(x + dx, 0, w - 1));
                const sy: usize = @intCast(std.math.clamp(y + dy, 0, h - 1));
                const so = (sy * b.w + sx) * 4;
                inline for (0..3) |c| acc[c] += @as(f32, @floatFromInt(src[so + c])) * k[ki];
                ki += 1;
            }
        }
        inline for (0..3) |c| {
            const orig: f32 = @floatFromInt(src[o + c]);
            const filtered = acc[c] / div;
            const v = orig + (filtered - orig) * strength;
            b.px[o + c] = @intFromFloat(std.math.clamp(v, 0, @as(f32, @floatFromInt(a))) + 0.0);
        }
    };
}

// ------------------------------------------------------------------ PNG

/// Straight-alpha 8-bit RGBA, e.g. for an HTML canvas ImageData.
pub fn toRgba8(gpa: Allocator, b: *const Bitmap) Allocator.Error![]u8 {
    const out = try gpa.alloc(u8, @as(usize, b.w) * b.h * 4);
    var i: usize = 0;
    while (i < out.len) : (i += 4) {
        const a: u32 = b.px[i + 3];
        if (a == 0) {
            @memset(out[i..][0..4], 0);
            continue;
        }
        inline for (0..3) |k| {
            const straight: u32 = @min(65535, (@as(u32, b.px[i + k]) * 65535 + a / 2) / a);
            out[i + k] = @intCast((straight * 255 + 32767) / 65535);
        }
        out[i + 3] = @intCast((a * 255 + 32767) / 65535);
    }
    return out;
}

/// Encodes a bitmap as RGBA PNG, 8 or 16 bits per channel.
pub fn encodePng(gpa: Allocator, b: *const Bitmap, sixteen: bool) ![]u8 {
    const bpp: usize = if (sixteen) 8 else 4;
    const stride = @as(usize, b.w) * bpp;
    // Raw scanlines with a filter byte each (Paeth for every row).
    const raw = try gpa.alloc(u8, (stride + 1) * b.h);
    defer gpa.free(raw);
    const prev = try gpa.alloc(u8, stride);
    defer gpa.free(prev);
    const cur = try gpa.alloc(u8, stride);
    defer gpa.free(cur);
    @memset(prev, 0);
    for (0..b.h) |y| {
        for (0..b.w) |x| {
            const p = b.px[(y * b.w + x) * 4 ..][0..4];
            const a: u32 = p[3];
            var s: [4]u16 = undefined;
            if (a == 0) {
                s = .{ 0, 0, 0, 0 };
            } else {
                inline for (0..3) |k| s[k] = @intCast(@min(65535, (@as(u32, p[k]) * 65535 + a / 2) / a));
                s[3] = p[3];
            }
            const o = x * bpp;
            if (sixteen) {
                inline for (0..4) |k| std.mem.writeInt(u16, cur[o + k * 2 ..][0..2], s[k], .big);
            } else {
                inline for (0..4) |k| cur[o + k] = @intCast((@as(u32, s[k]) * 255 + 32767) / 65535);
            }
        }
        const row = raw[y * (stride + 1) ..][0 .. stride + 1];
        row[0] = 4; // Paeth
        for (0..stride) |i| {
            const left: i16 = if (i >= bpp) cur[i - bpp] else 0;
            const up: i16 = prev[i];
            const ul: i16 = if (i >= bpp) prev[i - bpp] else 0;
            const pp = left + up - ul;
            const pa = @abs(pp - left);
            const pb = @abs(pp - up);
            const pc = @abs(pp - ul);
            const pred: i16 = if (pa <= pb and pa <= pc) left else if (pb <= pc) up else ul;
            row[1 + i] = cur[i] -% @as(u8, @intCast(pred));
        }
        @memcpy(prev, cur);
    }

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.writeAll("\x89PNG\r\n\x1a\n");
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], b.w, .big);
    std.mem.writeInt(u32, ihdr[4..8], b.h, .big);
    ihdr[8] = if (sixteen) 16 else 8;
    ihdr[9] = 6; // RGBA
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try chunk(w, "IHDR", &ihdr);

    var z: std.Io.Writer.Allocating = try .initCapacity(gpa, raw.len / 2 + 64);
    defer z.deinit();
    {
        const window = try gpa.alloc(u8, std.compress.flate.max_window_len);
        defer gpa.free(window);
        var comp = try std.compress.flate.Compress.init(&z.writer, window, .zlib, .level_4);
        try comp.writer.writeAll(raw);
        try comp.finish();
    }
    try chunk(w, "IDAT", z.written());
    try chunk(w, "IEND", "");
    return out.toOwnedSlice();
}

fn chunk(w: *std.Io.Writer, kind: *const [4]u8, data: []const u8) !void {
    try w.writeInt(u32, @intCast(data.len), .big);
    try w.writeAll(kind);
    try w.writeAll(data);
    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);
    try w.writeInt(u32, crc.final(), .big);
}

test "png roundtrip through stb_image" {
    const c = @import("c.zig");
    const gpa = std.testing.allocator;
    var b = try Bitmap.init(gpa, 0, 0, 20, 10);
    defer b.deinit(gpa);
    b.fill(paint(.{ .r = 65535, .g = 0, .b = 0, .a = 65535 }, 1));
    drawShape(&b, .ellipse, 2, 2, 10, 6, 0, paint(Color.white, 0.5), null);
    const png = try encodePng(gpa, &b, false);
    defer gpa.free(png);
    var w: c_int = 0;
    var h: c_int = 0;
    var ch: c_int = 0;
    const px = c.stbi_load_from_memory(png.ptr, @intCast(png.len), &w, &h, &ch, 4) orelse return error.DecodeFailed;
    defer c.stbi_image_free(px);
    try std.testing.expectEqual(@as(c_int, 20), w);
    try std.testing.expectEqual(@as(u8, 255), px[0]);
    try std.testing.expectEqual(@as(u8, 0), px[1]);
    // Centre of the ellipse: half white over red.
    const o: usize = (5 * 20 + 7) * 4;
    try std.testing.expect(px[o + 1] > 120 and px[o + 1] < 135);
}

test "rgba8 output" {
    const gpa = std.testing.allocator;
    var b = try Bitmap.init(gpa, 0, 0, 2, 1);
    defer b.deinit(gpa);
    b.fill(paint(Color.white, 1));
    const out = try toRgba8(gpa, &b);
    defer gpa.free(out);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255, 255, 255, 255, 255 }, out);
}
