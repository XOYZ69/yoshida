//! WebAssembly entry points for the browser editor. The page puts project
//! files into an in-memory file system, then sends JSON requests:
//!
//!   {"op":"info"}
//!   {"op":"check"}
//!   {"op":"render","set":"name","card":0,"date":"2026-10-07","preview":true,"format":"rgba"|"png"|"png16","layout":true}
//!
//! Each request leaves a JSON result and an optional binary result (pixels or
//! a PNG) that the page reads through the result_* exports.

const std = @import("std");
const y = @import("yoshida");

const gpa = std.heap.wasm_allocator;

var fs: y.project.MemFs = .{ .gpa = std.heap.wasm_allocator };
var assets: ?y.render.Assets = null;
var result_json: std.ArrayList(u8) = .empty;
var result_bin: []u8 = &.{};

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
        var outline: y.render.Outline = .{ .arena = arena };

        const a = getAssets();
        for (a.missing_urls.items) |u| gpa.free(u);
        a.missing_urls.clearRetainingCapacity();

        var width: u32 = 0;
        var height: u32 = 0;
        if (proj.findSet(set_name)) |set| {
            if (try y.render.renderCard(gpa, a, set, card_index, .{ .date = date, .preview = preview, .outline = if (want_layout) &outline else null }, &diags)) |bmp_const| {
                var bmp = bmp_const;
                defer bmp.deinit(gpa);
                width = bmp.w;
                height = bmp.h;
                if (std.mem.eql(u8, format, "png") or std.mem.eql(u8, format, "png16")) {
                    result_bin = try y.raster.encodePng(gpa, &bmp, std.mem.eql(u8, format, "png16"));
                } else {
                    result_bin = try y.raster.toRgba8(gpa, &bmp);
                }
            }
        } else {
            try w.writeAll("{\"error\":\"unknown set\"}");
            return 1;
        }
        try w.print("{{\"width\":{d},\"height\":{d},\"diagnostics\":", .{ width, height });
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

    if (std.mem.eql(u8, op, "pdf") or std.mem.eql(u8, op, "check_cards")) {
        // pdf: every card of the set as one PDF (result_bin), optionally with
        // crop marks. check_cards: evaluate every card without drawing.
        const set_name = if (req.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
        const date = if (req.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
        const marks = if (req.get("crop_marks")) |p| (p.data == .bool and p.data.bool) else false;
        const dry = std.mem.eql(u8, op, "check_cards");
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
                var bmp = (try y.render.renderCard(gpa, a, set, i, .{ .date = date, .preview = dry, .dry = dry }, &diags)) orelse continue;
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

    try w.writeAll("{\"error\":\"unknown op\"}");
    return 1;
}
