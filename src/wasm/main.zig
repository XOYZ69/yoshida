//! WebAssembly entry points for the browser editor. The page puts project
//! files into an in-memory file system, then sends JSON requests:
//!
//!   {"op":"info"}
//!   {"op":"check"}
//!   {"op":"render","set":"name","card":0,"date":"2026-10-07","preview":true,"format":"rgba"|"png"|"png16","layout":true,
//!    "scale":0.5,"compression":"fast"|"default"|"smallest","only":["id",...] | "except":["id",...]}
//!   scale is bitmap pixels per canvas pixel: below 1 for the preview, above
//!   1 for a larger export (each side at most 10000 pixels); compression is
//!   the PNG deflate level (default "default"). The result has the bitmap's
//!   "dpi" (canvas.dpi times scale, 0 when the design has none) and "bleed"
//!   (canvas.bleed times scale, in bitmap pixels).
//!   {"op":"svg","set":"name","card":0,"date":"...","scale":2}: the card as a
//!   vector SVG (result_bin), with {"width","height","diagnostics","missing_urls"}.
//!   "scale" (1 to 4, default 2) sets the resolution of the few parts that
//!   stay pixels (convolve effects), in pixels per canvas pixel.
//!   {"op":"pdf","set":"name","date":"...","crop_marks":false,"scale":2,"vector":false}
//!   {"op":"pdf_begin"}, then {"op":"pdf_page","set":"name","card":0,"date":"...","crop_marks":false,"scale":2,"vector":false}
//!   per card, then {"op":"pdf_finish"}: the same PDF one page per request,
//!   so the page can show real progress. By default each card is an image
//!   on its page and "scale" (default 1) sets the resolution of that image.
//!   With "vector": true the pages are drawn as vectors (sharp at any zoom,
//!   text as outlines) and "scale" works as for svg. The page size does not
//!   change with the scale.
//!   {"op":"scope","set":"name","path":"/layers/3/fill"}: the names and types an
//!   expression field can use.
//!   {"op":"eval","set":"name","card":0,"date":"...","path":"/layers/3/fill","src":"..."}:
//!   the value of every node of `src` evaluated in place of that field.
//!
//! The render clock is set by the optional "now" (a UTC instant,
//! `YYYY-MM-DDTHH:MM:SSZ`) and "utc_offset" (hours, -14 to 14; other values
//! are ignored) fields of render, svg, pdf, check_cards, pdf_page and eval. With
//! "now", render.date and render.time come from it plus the offset (the
//! project's utc_offset unless "utc_offset" is given). Without it, "date" is
//! used at midnight. The page supplies the instant: this module has no clock.
//!
//! Each request leaves a JSON result and an optional binary result (pixels, a
//! PNG, an SVG or a PDF) that the page reads through the result_* exports.

const std = @import("std");
const y = @import("yoshida");

const gpa = std.heap.wasm_allocator;

var fs: y.project.MemFs = .{ .gpa = std.heap.wasm_allocator };
var assets: ?y.render.Assets = null;
var result_json: std.ArrayList(u8) = .empty;
var result_bin: []u8 = &.{};
/// The PDF being built by pdf_begin / pdf_page / pdf_finish.
var pdf_pages: ?y.pdf.Writer = null;

fn getAssets() *y.render.Assets {
    if (assets == null) assets = y.render.Assets.init(gpa, fs.vfs());
    return &assets.?;
}

export fn alloc(len: usize) ?[*]u8 {
    const m = gpa.alloc(u8, @max(len, 1)) catch return null;
    return m.ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    gpa.free(ptr[0..@max(len, 1)]);
}

export fn vfs_put(path_ptr: [*]const u8, path_len: usize, data_ptr: [*]const u8, data_len: usize) i32 {
    const path = path_ptr[0..path_len];
    fs.put(path, data_ptr[0..data_len]) catch return -1;
    if (assets) |*a| a.invalidate(path);
    return 0;
}

export fn vfs_remove(path_ptr: [*]const u8, path_len: usize) void {
    const path = path_ptr[0..path_len];
    fs.remove(path);
    if (assets) |*a| a.invalidate(path);
}

export fn vfs_clear() void {
    fs.clear();
    if (assets) |*a| {
        a.deinit();
        assets = null;
    }
}

export fn result_json_ptr() [*]const u8 {
    return result_json.items.ptr;
}

export fn result_json_len() usize {
    return result_json.items.len;
}

export fn result_bin_ptr() [*]const u8 {
    return result_bin.ptr;
}

export fn result_bin_len() usize {
    return result_bin.len;
}

/// Returns 0 on success, 1 when the request itself was invalid (the JSON
/// result then holds {"error": ...}), -1 when out of memory.
export fn request(ptr: [*]const u8, len: usize) i32 {
    result_json.clearRetainingCapacity();
    if (result_bin.len > 0) gpa.free(result_bin);
    result_bin = &.{};
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    return handle(arena_state.allocator(), ptr[0..len]) catch -1;
}

/// The optional render clock of a request: "now" (UTC instant) and
/// "utc_offset" (hours, -14 to 14). Anything else is left out.
const Clock = struct { now: ?[]const u8 = null, utc_offset: ?f64 = null };

fn clockOf(req: *const y.json.Node) Clock {
    var c: Clock = .{};
    if (req.get("now")) |n| {
        if (n.data == .string) c.now = n.data.string;
    }
    if (req.get("utc_offset")) |o| {
        if (o.data == .number and o.data.number >= -14 and o.data.number <= 14) c.utc_offset = o.data.number;
    }
    return c;
}

/// The optional "scale" of a request (1 when absent or not a number; the
/// core rejects a scale that makes the bitmap too large).
fn scaleOf(req: *const y.json.Node) f64 {
    const p = req.get("scale") orelse return 1;
    return if (p.data == .number) p.data.number else 1;
}

/// The optional "scale" of a vector request: pixels per canvas pixel for
/// the parts drawn as pixels, 1 to 4 (default 2).
fn rasterScale(req: *const y.json.Node) f32 {
    const v = if (req.get("scale")) |s| (if (s.data == .number) s.data.number else 2) else 2;
    return @floatCast(std.math.clamp(v, 1, 4));
}

/// True when the request has "vector": true.
fn wantsVector(req: *const y.json.Node) bool {
    return if (req.get("vector")) |p| (p.data == .bool and p.data.bool) else false;
}

/// Draws card `index` as a vector page of `pdf`; false when nothing could be drawn.
fn addVectorPage(pdf: *y.pdf.Writer, a: *y.render.Assets, set: *const y.project.Set, index: usize, date: []const u8, clock: Clock, marks: bool, scale: f32, diags: *y.diag.List) !bool {
    var scene = y.vector.Scene.init(gpa);
    defer scene.deinit();
    scene.raster_scale = scale;
    if (!try y.render.renderVector(gpa, a, set, index, .{ .date = date, .now = clock.now, .utc_offset = clock.utc_offset }, &scene, diags)) return false;
    try pdf.addVector(&scene, marks);
    return true;
}

fn handle(arena: std.mem.Allocator, req_text: []const u8) !i32 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    defer {
        result_json.clearRetainingCapacity();
        result_json.appendSlice(gpa, aw.written()) catch {};
    }
    const req = switch (try y.json.parse(arena, req_text)) {
        .ok => |n| n,
        .err => |e| {
            try w.print("{{\"error\":\"invalid request JSON: {s}\"}}", .{e.message});
            return 1;
        },
    };
    const op = if (req.get("op")) |o| (if (o.data == .string) o.data.string else "") else "";
    const clock = clockOf(&req);

    if (std.mem.eql(u8, op, "info")) {
        try w.print("{{\"version\":\"{s}\",\"format\":{d}}}", .{ y.version, y.format_version });
        return 0;
    }

    var diags = y.diag.List.init(arena);
    const proj = try y.project.load(arena, fs.vfs(), &diags);

    if (std.mem.eql(u8, op, "check")) {
        try w.writeAll("{\"diagnostics\":");
        try diags.writeJson(w);
        try w.writeAll(",\"project\":");
        try y.api.writeProject(w, &proj);
        try w.writeAll("}");
        return 0;
    }

    if (std.mem.eql(u8, op, "render")) {
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const card_index: usize = if (req.get("card")) |c| (if (c.data == .number and c.data.number >= 0) @intFromFloat(c.data.number) else 0) else 0;
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        const preview = if (req.get("preview")) |p| (p.data == .bool and p.data.bool) else true;
        const format = if (req.get("format")) |f| (if (f.data == .string) f.data.string else "rgba") else "rgba";
        const want_layout = if (req.get("layout")) |p| (p.data == .bool and p.data.bool) else false;
        const scale = scaleOf(&req);
        const compression = std.meta.stringToEnum(y.raster.Compression, if (req.get("compression")) |c| (if (c.data == .string) c.data.string else "") else "") orelse .default;
        var outline: y.render.Outline = .{ .arena = arena };
        var filter: ?y.render.Options.Filter = null;
        inline for (.{ "only", "except" }) |mode| if (req.get(mode)) |list| if (list.data == .array) {
            const ids = try arena.alloc([]const u8, list.data.array.len);
            var n: usize = 0;
            for (list.data.array) |item| if (item.data == .string) {
                ids[n] = item.data.string;
                n += 1;
            };
            filter = .{ .ids = ids[0..n], .mode = @field(y.render.Options.Filter.Mode, mode) };
        };

        const a = getAssets();
        for (a.missing_urls.items) |u| gpa.free(u);
        a.missing_urls.clearRetainingCapacity();

        var width: u32 = 0;
        var height: u32 = 0;
        var canvas_w: u32 = 0;
        var canvas_h: u32 = 0;
        var dpi: f64 = 0;
        var bleed: f64 = 0;
        if (proj.findSet(set_name)) |set| {
            if (try y.render.renderCard(gpa, a, set, card_index, .{ .date = date, .now = clock.now, .utc_offset = clock.utc_offset, .preview = preview, .outline = if (want_layout) &outline else null, .scale = scale, .filter = filter }, &diags)) |bmp_const| {
                var bmp = bmp_const;
                defer bmp.deinit(gpa);
                width = bmp.w;
                height = bmp.h;
                canvas_w = bmp.canvas_w;
                canvas_h = bmp.canvas_h;
                dpi = bmp.dpi;
                bleed = bmp.bleed;
                if (std.mem.eql(u8, format, "png") or std.mem.eql(u8, format, "png16")) {
                    result_bin = try y.raster.encodePngLevel(gpa, &bmp, std.mem.eql(u8, format, "png16"), compression);
                } else {
                    result_bin = try y.raster.toRgba8(gpa, &bmp);
                }
            }
        } else {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        }
        try w.print("{{\"width\":{d},\"height\":{d},\"canvas_width\":{d},\"canvas_height\":{d},\"dpi\":{d},\"bleed\":{d},\"diagnostics\":", .{ width, height, canvas_w, canvas_h, dpi, bleed });
        try diags.writeJson(w);
        try w.writeAll(",\"missing_urls\":");
        try y.api.writeMissingUrls(w, a);
        if (want_layout) {
            try w.writeAll(",\"layout\":");
            try y.api.writeOutline(w, outline.items.items);
        }
        try w.writeAll("}");
        return 0;
    }

    if (std.mem.eql(u8, op, "svg")) {
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const card_index: usize = if (req.get("card")) |c| (if (c.data == .number and c.data.number >= 0) @intFromFloat(c.data.number) else 0) else 0;
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        const set = proj.findSet(set_name) orelse {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        };
        const a = getAssets();
        for (a.missing_urls.items) |u| gpa.free(u);
        a.missing_urls.clearRetainingCapacity();
        var scene = y.vector.Scene.init(gpa);
        defer scene.deinit();
        scene.raster_scale = rasterScale(&req);
        var drawn = false;
        if (set.ok) drawn = try y.render.renderVector(gpa, a, set, card_index, .{ .date = date, .now = clock.now, .utc_offset = clock.utc_offset }, &scene, &diags);
        if (drawn) result_bin = try y.svg.write(gpa, &scene);
        try w.print("{{\"width\":{d},\"height\":{d},\"diagnostics\":", .{ scene.width, scene.height });
        try diags.writeJson(w);
        try w.writeAll(",\"missing_urls\":");
        try y.api.writeMissingUrls(w, a);
        try w.writeAll("}");
        return 0;
    }

    if (std.mem.eql(u8, op, "scope") or std.mem.eql(u8, op, "eval")) {
        // The expression field at JSON pointer `path` of the set's design:
        // what it can use (scope), or the live value of `src` in its place
        // for one card (eval).
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const path = if (req.get("path")) |p| (if (p.data == .string) p.data.string else "") else "";
        const set = proj.findSet(set_name) orelse {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        };
        const field = y.exprapi.fieldAt(set.design, path) orelse {
            try w.writeAll("{\"error\":\"no expression field at path\"}");
            return 1;
        };
        if (std.mem.eql(u8, op, "scope")) {
            try y.exprapi.writeScope(w, set.design, field);
            return 0;
        }
        const src = if (req.get("src")) |s| (if (s.data == .string) s.data.string else "") else "";
        const card_index: usize = if (req.get("card")) |c| (if (c.data == .number and c.data.number >= 0) @intFromFloat(c.data.number) else 0) else 0;
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        try y.exprapi.writeEval(gpa, arena, w, getAssets(), set, field, src, .{ .card = card_index, .date = date, .now = clock.now, .utc_offset = clock.utc_offset });
        return 0;
    }

    if (std.mem.eql(u8, op, "pdf") or std.mem.eql(u8, op, "check_cards")) {
        // pdf: every card of the set as one PDF (result_bin), optionally with
        // crop marks. check_cards: evaluate every card without drawing.
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        const marks = if (req.get("crop_marks")) |p| (p.data == .bool and p.data.bool) else false;
        const vector = wantsVector(&req);
        const dry = std.mem.eql(u8, op, "check_cards");
        const scale = scaleOf(&req);
        const set = proj.findSet(set_name) orelse {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        };
        const a = getAssets();
        var pages: usize = 0;
        if (set.ok) {
            var pdf = try y.pdf.Writer.init(gpa);
            defer pdf.deinit();
            for (0..set.cards.len) |i| {
                if (vector and !dry) {
                    if (try addVectorPage(&pdf, a, set, i, date, clock, marks, rasterScale(&req), &diags)) pages += 1;
                    continue;
                }
                var bmp = (try y.render.renderCard(gpa, a, set, i, .{ .date = date, .now = clock.now, .utc_offset = clock.utc_offset, .preview = dry, .dry = dry, .scale = if (dry) 1 else scale }, &diags)) orelse continue;
                defer bmp.deinit(gpa);
                if (dry) continue;
                if (marks) {
                    const marked = try y.raster.withCropMarks(gpa, &bmp);
                    bmp.deinit(gpa);
                    bmp = marked;
                }
                try pdf.addPage(&bmp);
                pages += 1;
            }
            if (!dry and pages > 0) result_bin = try pdf.finish();
        }
        try w.print("{{\"pages\":{d},\"diagnostics\":", .{pages});
        try diags.writeJson(w);
        try w.writeAll("}");
        return 0;
    }

    if (std.mem.eql(u8, op, "pdf_begin")) {
        if (pdf_pages) |*p| p.deinit();
        pdf_pages = try y.pdf.Writer.init(gpa);
        try w.writeAll("{\"pages\":0}");
        return 0;
    }

    if (std.mem.eql(u8, op, "pdf_page")) {
        const pdf = if (pdf_pages) |*p| p else {
            try w.writeAll("{\"error\":\"no pdf_begin\"}");
            return 1;
        };
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const card_index: usize = if (req.get("card")) |c| (if (c.data == .number and c.data.number >= 0) @intFromFloat(c.data.number) else 0) else 0;
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        const marks = if (req.get("crop_marks")) |p| (p.data == .bool and p.data.bool) else false;
        const set = proj.findSet(set_name) orelse {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        };
        if (set.ok and wantsVector(&req)) {
            _ = try addVectorPage(pdf, getAssets(), set, card_index, date, clock, marks, rasterScale(&req), &diags);
        } else if (set.ok) if (try y.render.renderCard(gpa, getAssets(), set, card_index, .{ .date = date, .now = clock.now, .utc_offset = clock.utc_offset, .scale = scaleOf(&req) }, &diags)) |bmp_const| {
            var bmp = bmp_const;
            defer bmp.deinit(gpa);
            if (marks) {
                const marked = try y.raster.withCropMarks(gpa, &bmp);
                bmp.deinit(gpa);
                bmp = marked;
            }
            try pdf.addPage(&bmp);
        };
        try w.print("{{\"pages\":{d},\"diagnostics\":", .{pdf.pages.items.len});
        try diags.writeJson(w);
        try w.writeAll("}");
        return 0;
    }

    if (std.mem.eql(u8, op, "pdf_finish")) {
        var pdf = pdf_pages orelse {
            try w.writeAll("{\"error\":\"no pdf_begin\"}");
            return 1;
        };
        pdf_pages = null;
        defer pdf.deinit();
        const pages = pdf.pages.items.len;
        if (pages > 0) result_bin = try pdf.finish();
        try w.print("{{\"pages\":{d}}}", .{pages});
        return 0;
    }

    try w.writeAll("{\"error\":\"unknown op\"}");
    return 1;
}
