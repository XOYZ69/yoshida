//! Renders one card: evaluates every layer for the card's values (resolving
//! `@layer` references lazily, with cycle detection), draws, applies effects
//! and composites (FORMAT.md sections 5 and 8).

const std = @import("std");
const c = @import("c.zig");
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const expr = @import("expr.zig");
const design_mod = @import("design.zig");
const project = @import("project.zig");
const raster = @import("raster.zig");
const text = @import("text.zig");
const Allocator = std.mem.Allocator;
const Value = value.Value;
const Color = value.Color;
const Design = design_mod.Design;
const Layer = design_mod.Layer;
const Prop = design_mod.Prop;

pub const default_font_data = @embedFile("assets/Lato-Regular.ttf");

pub const limits = struct {
    pub const canvas_side = 10000;
    pub const layers = 500;
    pub const iterations = 1000;
    pub const image_pixels = 50_000_000;
};

pub const Options = struct {
    /// ISO date for `render.date`, chosen once by whoever starts the render.
    date: []const u8 = "1970-01-01",
    /// Editor preview: missing images become a placeholder and a warning.
    preview: bool = false,
    /// When set, receives the resolved bounds of every layer (the editor uses
    /// them for selection and hit testing).
    outline: ?*Outline = null,
};

/// Where a layer ended up on the canvas. Repeated layers appear once per
/// iteration, with `instance` set.
pub const Placed = struct {
    id: []const u8,
    instance: ?u32 = null,
    visible: bool,
    left: f64,
    top: f64,
    w: f64,
    h: f64,
    /// Degrees clockwise around (`px`, `py`).
    rotate: f64 = 0,
    px: f64 = 0,
    py: f64 = 0,
    /// Text size after auto-shrink.
    size: ?f64 = null,
    /// Polygon points in canvas pixels; empty for other layer types.
    points: []const [2]f32 = &.{},
};

pub const Outline = struct {
    arena: Allocator,
    items: std.ArrayList(Placed) = .empty,

    fn add(o: *Outline, l: *const Layer, instance: ?u32, r: *const Resolved) Allocator.Error!void {
        try o.items.append(o.arena, .{
            .id = l.id,
            .instance = instance,
            .visible = r.visible,
            .left = r.left,
            .top = r.top,
            .w = r.w,
            .h = r.h,
            .rotate = r.rotate,
            .px = r.pivot[0],
            .py = r.pivot[1],
            .size = if (l.kind == .text) r.size else null,
            .points = try o.arena.dupe([2]f32, r.points),
        });
    }
};

/// Decoded images and fonts, shared by every card of a render. Not thread-safe:
/// use one per thread.
pub const Assets = struct {
    gpa: Allocator,
    vfs: project.Vfs,
    images: std.StringHashMapUnmanaged(ImageEntry) = .empty,
    fonts: std.StringHashMapUnmanaged(?*text.Font) = .empty,
    default_font: ?text.Font = null,
    /// URLs that were needed but are not in the file system. The shell may
    /// fetch them, add them under the URL as path, and render again.
    missing_urls: std.ArrayList([]const u8) = .empty,

    pub const ImageEntry = union(enum) {
        ok: *raster.Image,
        missing,
        bad: []const u8,
    };

    pub fn init(gpa: Allocator, vfs: project.Vfs) Assets {
        return .{ .gpa = gpa, .vfs = vfs };
    }

    pub fn deinit(a: *Assets) void {
        var it = a.images.iterator();
        while (it.next()) |e| {
            switch (e.value_ptr.*) {
                .ok => |img| {
                    img.deinit(a.gpa);
                    a.gpa.destroy(img);
                },
                .bad => |msg| a.gpa.free(msg),
                .missing => {},
            }
            a.gpa.free(e.key_ptr.*);
        }
        a.images.deinit(a.gpa);
        var fit = a.fonts.iterator();
        while (fit.next()) |e| {
            if (e.value_ptr.*) |f| {
                f.deinit(a.gpa);
                a.gpa.destroy(f);
            }
            a.gpa.free(e.key_ptr.*);
        }
        a.fonts.deinit(a.gpa);
        if (a.default_font) |*f| f.deinit(a.gpa);
        for (a.missing_urls.items) |u| a.gpa.free(u);
        a.missing_urls.deinit(a.gpa);
    }

    /// Drops cached files, e.g. after the editor changed one.
    pub fn invalidate(a: *Assets, path: []const u8) void {
        if (a.images.fetchRemove(path)) |kv| {
            switch (kv.value) {
                .ok => |img| {
                    img.deinit(a.gpa);
                    a.gpa.destroy(img);
                },
                .bad => |msg| a.gpa.free(msg),
                .missing => {},
            }
            a.gpa.free(kv.key);
        }
        if (a.fonts.fetchRemove(path)) |kv| {
            if (kv.value) |f| {
                f.deinit(a.gpa);
                a.gpa.destroy(f);
            }
            a.gpa.free(kv.key);
        }
    }

    pub fn image(a: *Assets, path: []const u8) Allocator.Error!ImageEntry {
        if (a.images.get(path)) |e| return e;
        const entry = try a.decode(path);
        try a.images.put(a.gpa, try a.gpa.dupe(u8, path), entry);
        return entry;
    }

    fn decode(a: *Assets, path: []const u8) Allocator.Error!ImageEntry {
        const bytes = a.vfs.read(path) orelse {
            if (project.isUrl(path)) {
                for (a.missing_urls.items) |u| if (std.mem.eql(u8, u, path)) return .missing;
                try a.missing_urls.append(a.gpa, try a.gpa.dupe(u8, path));
            }
            return .missing;
        };
        if (bytes.len > std.math.maxInt(c_int)) return .{ .bad = try a.gpa.dupe(u8, "file too large") };
        var w: c_int = 0;
        var h: c_int = 0;
        var ch: c_int = 0;
        if (bytes.len >= 12 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP")) {
            return a.decodeWebp(bytes);
        }
        const px = c.stbi_load_16_from_memory(bytes.ptr, @intCast(bytes.len), &w, &h, &ch, 4) orelse {
            const reason = if (c.stbi_failure_reason()) |r| std.mem.span(r) else "unknown format";
            return .{ .bad = try std.fmt.allocPrint(a.gpa, "cannot decode image ({s}); PNG, JPEG, WebP, GIF and BMP are supported", .{reason}) };
        };
        defer c.stbi_image_free(px);
        const uw: u32 = @intCast(w);
        const uh: u32 = @intCast(h);
        if (@as(u64, uw) * uh > limits.image_pixels) {
            return .{ .bad = try std.fmt.allocPrint(a.gpa, "image is {d} x {d}, above the 50 megapixel limit", .{ uw, uh }) };
        }
        const img = try a.gpa.create(raster.Image);
        errdefer a.gpa.destroy(img);
        img.* = try raster.Image.fromStraight(a.gpa, uw, uh, px[0 .. @as(usize, uw) * uh * 4]);
        return .{ .ok = img };
    }

    fn decodeWebp(a: *Assets, bytes: []const u8) Allocator.Error!ImageEntry {
        var webp: ?*c.simplewebp = null;
        // simplewebp reads but never writes the input; its API is not const.
        const err = c.simplewebp_load_from_memory(@constCast(bytes.ptr), bytes.len, null, &webp);
        if (err != 0 or webp == null) {
            return .{ .bad = try std.fmt.allocPrint(a.gpa, "cannot decode WebP image ({s})", .{std.mem.span(c.simplewebp_get_error_text(err))}) };
        }
        defer c.simplewebp_unload(webp.?);
        var w: usize = 0;
        var h: usize = 0;
        c.simplewebp_get_dimensions(webp.?, &w, &h);
        if (w == 0 or h == 0 or @as(u64, w) * h > limits.image_pixels) {
            return .{ .bad = try std.fmt.allocPrint(a.gpa, "image is {d} x {d}, above the 50 megapixel limit", .{ w, h }) };
        }
        const rgba8 = try a.gpa.alloc(u8, w * h * 4);
        defer a.gpa.free(rgba8);
        const derr = c.simplewebp_decode(webp.?, rgba8.ptr, null);
        if (derr != 0) {
            return .{ .bad = try std.fmt.allocPrint(a.gpa, "cannot decode WebP image ({s})", .{std.mem.span(c.simplewebp_get_error_text(derr))}) };
        }
        const px = try a.gpa.alloc(u16, rgba8.len);
        defer a.gpa.free(px);
        for (rgba8, px) |b, *o| o.* = @as(u16, b) * 257;
        const img = try a.gpa.create(raster.Image);
        errdefer a.gpa.destroy(img);
        img.* = try raster.Image.fromStraight(a.gpa, @intCast(w), @intCast(h), px);
        return .{ .ok = img };
    }

    pub fn defaultFont(a: *Assets) Allocator.Error!*text.Font {
        if (a.default_font == null) a.default_font = (try text.Font.init(a.gpa, default_font_data)).?;
        return &a.default_font.?;
    }

    /// null when the file is missing or not a font.
    pub fn font(a: *Assets, path: []const u8) Allocator.Error!?*text.Font {
        if (a.fonts.get(path)) |f| return f;
        var result: ?*text.Font = null;
        if (a.vfs.read(path)) |bytes| {
            if (try text.Font.init(a.gpa, bytes)) |f| {
                const p = try a.gpa.create(text.Font);
                p.* = f;
                result = p;
            }
        }
        try a.fonts.put(a.gpa, try a.gpa.dupe(u8, path), result);
        return result;
    }
};

/// Everything a layer evaluates to for one card (and one repeat iteration).
const Resolved = struct {
    visible: bool = true,
    opacity: f64 = 1,
    /// Degrees clockwise around `pivot`.
    rotate: f64 = 0,
    pivot: [2]f64 = .{ 0, 0 },
    // Final bounds after anchor and layout.
    left: f64 = 0,
    top: f64 = 0,
    w: f64 = 0,
    h: f64 = 0,
    box: [4]f64 = .{ 0, 0, 0, 0 },
    at: [2]f64 = .{ 0, 0 },
    fill: Color = Color.white,
    stroke: ?struct { color: Color, width: f64 } = null,
    radius: f64 = 0,
    points: []const [2]f32 = &.{},
    text: []const u8 = "",
    font: ?*text.Font = null,
    size: f64 = 16,
    color: Color = Color.black,
    wrap: ?f64 = null,
    line_spacing: f64 = 4,
    max_lines: ?f64 = null,
    layout: ?text.Layout = null,
    src: []const u8 = "",
    image: ?*raster.Image = null,
};

const State = enum { todo, busy, done, failed };

const Local = struct { name: []const u8, value: Value };

const Failed = error{ Failed, OutOfMemory };

const Ctx = struct {
    gpa: Allocator,
    arena: Allocator,
    assets: *Assets,
    d: *const Design,
    card: *const project.Card,
    index: usize,
    opts: Options,
    diags: *diag.List,
    canvas_w: f64 = 0,
    canvas_h: f64 = 0,
    states: []State,
    resolved: []Resolved,
    /// Repeated layers: every iteration, evaluated once per card.
    instances: []?[]Resolved,
    locals: []const Local = &.{},
    current: ?usize = null,
    drawn: usize = 0,

    fn newEnv(ctx: *Ctx) expr.Env {
        return .{
            .arena = ctx.arena,
            .canvas_w = ctx.canvas_w,
            .canvas_h = ctx.canvas_h,
            .card_id = ctx.card.id,
            .render_index = @floatFromInt(ctx.index),
            .render_date = ctx.opts.date,
            .ctx = ctx,
            .lookup = lookup,
            .layerRef = layerRef,
            .avgColor = avgColor,
        };
    }

    fn report(ctx: *Ctx, sev: diag.Severity, code: u16, pos: ?u32, span: ?[2]u32, msg: []const u8, hint: ?[]const u8) Allocator.Error!void {
        return ctx.reportFor(ctx.card.id, sev, code, pos, span, msg, hint);
    }

    /// `card` null: the problem is not specific to one card (reported once).
    fn reportFor(ctx: *Ctx, card: ?[]const u8, sev: diag.Severity, code: u16, pos: ?u32, span: ?[2]u32, msg: []const u8, hint: ?[]const u8) Allocator.Error!void {
        const da = ctx.diags.arena;
        var d: diag.Diagnostic = .{
            .severity = sev,
            .code = code,
            .file = ctx.d.file,
            .path = if (pos) |p| ctx.d.pathAt(da, p) else "",
            .message = try da.dupe(u8, msg),
            .hint = if (hint) |h| try da.dupe(u8, h) else null,
            .card = card,
        };
        if (pos) |p| {
            const lc = json.lineCol(ctx.d.source, p);
            d.line = lc.line;
            d.col = lc.col;
        }
        if (span) |s| {
            d.span_start = s[0];
            d.span_end = s[1];
        }
        try ctx.diags.add(d);
    }

    fn layerMsg(ctx: *Ctx, layer: *const Layer, comptime f: []const u8, args: anytype) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(ctx.arena, "layer '{s}': " ++ f, .{layer.id} ++ args);
    }

    /// Turns an evaluation error into a diagnostic (unless it was already
    /// reported by a referenced layer).
    fn evalFailed(ctx: *Ctx, e: expr.EvalError, env: *expr.Env, layer: ?*const Layer, pos: u32) Failed {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (env.problem) |p| {
            const msg = if (layer) |l| ctx.layerMsg(l, "{s}", .{p.message}) catch return error.OutOfMemory else p.message;
            ctx.report(.err, p.code, pos, .{ p.start, p.end }, msg, p.hint) catch return error.OutOfMemory;
            env.problem = null;
        }
        return error.Failed;
    }

    fn eval(ctx: *Ctx, env: *expr.Env, layer: ?*const Layer, p: Prop) Failed!Value {
        env.axis = p.axis;
        return env.eval(p.node) catch |e| return ctx.evalFailed(e, env, layer, p.pos);
    }

    fn num(ctx: *Ctx, env: *expr.Env, layer: ?*const Layer, p: Prop) Failed!f64 {
        const v = (try ctx.eval(env, layer, p)).number;
        if (!std.math.isFinite(v)) {
            try ctx.report(.err, 3103, p.pos, null, try ctx.layerMsg(layer.?, "the value is not a finite number", .{}), null);
            return error.Failed;
        }
        return v;
    }

    fn tmpl(ctx: *Ctx, env: *expr.Env, layer: *const Layer, t: design_mod.Tmpl) Failed![]const u8 {
        env.axis = .none;
        return env.template(t.t) catch |e| return ctx.evalFailed(e, env, layer, t.pos);
    }

    // ---------------------------------------------------------- env callbacks

    fn lookup(ptr: *anyopaque, name: []const u8) ?Value {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        var i = ctx.locals.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, ctx.locals[i].name, name)) return ctx.locals[i].value;
        }
        const pi = ctx.d.findParam(name) orelse return null;
        return paramValue(ctx.d, ctx.card, pi);
    }

    fn layerRef(ptr: *anyopaque, id: []const u8, path: []const []const u8) expr.EvalError!Value {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        const li = ctx.d.findLayer(id) orelse return error.Eval;
        const r = ctx.resolve(li) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => return error.Eval,
        };
        return readField(r, path) orelse error.Eval;
    }

    fn avgColor(ptr: *anyopaque, path: []const u8) expr.EvalError!Color {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        const layer: ?*const Layer = if (ctx.current) |i| &ctx.d.layers[i] else null;
        const img = ctx.loadImage(layer, path, null) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => return error.Eval,
        };
        if (img) |i| return i.average();
        return .{ .r = 40000, .g = 40000, .b = 40000, .a = 65535 };
    }

    /// Loads an image for a layer. Returns null for a placeholder (preview).
    fn loadImage(ctx: *Ctx, layer: ?*const Layer, raw_path: []const u8, pos: ?u32) Failed!?*raster.Image {
        const where = if (pos) |p| p else if (layer) |l| l.pos else null;
        const lid = if (layer) |l| l.id else "?";
        const path = (try project.normalize(ctx.arena, raw_path)) orelse {
            try ctx.report(.err, 1203, where, null, try std.fmt.allocPrint(ctx.arena, "layer '{s}': path '{s}' is outside the project", .{ lid, raw_path }), "paths are relative to the project folder");
            return error.Failed;
        };
        switch (try ctx.assets.image(path)) {
            .ok => |img| return img,
            .missing => {
                const sev: diag.Severity = if (ctx.opts.preview) .warning else .err;
                const hint: ?[]const u8 = if (project.isUrl(path)) "the image could not be downloaded; add it to the project and use a project path" else null;
                try ctx.report(sev, 4001, where, null, try std.fmt.allocPrint(ctx.arena, "layer '{s}': image '{s}' not found", .{ lid, path }), hint);
                if (ctx.opts.preview) return null;
                return error.Failed;
            },
            .bad => |msg| {
                try ctx.report(.err, 4002, where, null, try std.fmt.allocPrint(ctx.arena, "layer '{s}': '{s}': {s}", .{ lid, path, msg }), null);
                if (ctx.opts.preview) return null;
                return error.Failed;
            },
        }
    }

    // ---------------------------------------------------------- resolution

    /// Resolves a non-repeated layer once per card.
    fn resolve(ctx: *Ctx, li: usize) Failed!*Resolved {
        switch (ctx.states[li]) {
            .done => return &ctx.resolved[li],
            .failed => return error.Failed,
            .busy => {
                const from = if (ctx.current) |i| ctx.d.layers[i].id else "?";
                const l = &ctx.d.layers[li];
                try ctx.report(.err, 3004, l.pos, null, try std.fmt.allocPrint(ctx.arena, "reference cycle: layer '{s}' and layer '{s}' depend on each other", .{ l.id, from }), "follow the @references between these layers and break one");
                return error.Failed;
            },
            .todo => {},
        }
        ctx.states[li] = .busy;
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        ctx.locals = &.{};
        ctx.current = li;
        defer {
            ctx.locals = saved_locals;
            ctx.current = saved_current;
        }
        ctx.evalLayer(&ctx.d.layers[li], &ctx.resolved[li]) catch |e| {
            ctx.states[li] = .failed;
            return e;
        };
        ctx.states[li] = .done;
        return &ctx.resolved[li];
    }

    fn evalLayer(ctx: *Ctx, l: *const Layer, r: *Resolved) Failed!void {
        var e = ctx.newEnv();
        r.* = .{};
        if (l.visible) |p| r.visible = (try ctx.eval(&e, l, p)).bool;
        if (l.opacity) |p| r.opacity = std.math.clamp(try ctx.num(&e, l, p), 0, 1);
        if (l.rotate) |p| r.rotate = @mod(try ctx.num(&e, l, p), 360);
        const fx = l.anchor.fx();
        const fy = l.anchor.fy();
        switch (l.kind) {
            .group => {
                // Bounds: the union of the visible children (and their
                // repeat iterations).
                const gi = ctx.indexOf(l);
                var b = [4]f64{ std.math.inf(f64), std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };
                var ci = gi + 1;
                while (ci < l.end) : (ci += 1) {
                    const child = &ctx.d.layers[ci];
                    if (child.parent != gi) continue;
                    const list: []const Resolved = if (child.repeat != null) try ctx.repeatInstances(ci) else (try ctx.resolve(ci))[0..1];
                    for (list) |*cr| {
                        if (!cr.visible) continue;
                        b[0] = @min(b[0], cr.left);
                        b[1] = @min(b[1], cr.top);
                        b[2] = @max(b[2], cr.left + cr.w);
                        b[3] = @max(b[3], cr.top + cr.h);
                    }
                }
                if (b[0] <= b[2]) {
                    r.left = b[0];
                    r.top = b[1];
                    r.w = b[2] - b[0];
                    r.h = b[3] - b[1];
                }
                r.pivot = .{ r.left + r.w / 2, r.top + r.h / 2 };
            },
            .rect, .ellipse, .image => {
                const box = l.box orelse return error.Failed;
                r.box[0] = try ctx.num(&e, l, box.x);
                r.box[1] = try ctx.num(&e, l, box.y);
                if (box.w) |p| r.box[2] = try ctx.num(&e, l, p);
                if (box.h) |p| r.box[3] = try ctx.num(&e, l, p);
                if (l.kind == .image) {
                    r.src = try ctx.tmpl(&e, l, l.src.?);
                    r.image = try ctx.loadImage(l, r.src, l.src.?.pos);
                    const ratio: f64 = if (r.image) |img| @as(f64, @floatFromInt(img.w)) / @as(f64, @floatFromInt(img.h)) else 1;
                    if (box.w == null) r.box[2] = r.box[3] * ratio;
                    if (box.h == null) r.box[3] = r.box[2] / ratio;
                }
                if (r.box[2] < 0 or r.box[3] < 0) {
                    const p = if (r.box[2] < 0) box.w.? else box.h.?;
                    try ctx.report(.err, 3101, p.pos, null, try ctx.layerMsg(l, "negative size {d} x {d}", .{ r.box[2], r.box[3] }), null);
                    return error.Failed;
                }
                r.w = r.box[2];
                r.h = r.box[3];
                r.left = r.box[0] - fx * r.w;
                r.top = r.box[1] - fy * r.h;
                r.pivot = .{ r.box[0], r.box[1] };
                if (l.kind != .image) {
                    if (l.fill) |p| r.fill = (try ctx.eval(&e, l, p)).color;
                    if (l.radius) |p| r.radius = try ctx.num(&e, l, p);
                }
            },
            .polygon => {
                const pts = try ctx.arena.alloc([2]f32, l.points.len);
                var minx: f64 = std.math.inf(f64);
                var miny: f64 = std.math.inf(f64);
                var maxx: f64 = -std.math.inf(f64);
                var maxy: f64 = -std.math.inf(f64);
                for (l.points, 0..) |p, i| {
                    const x = try ctx.num(&e, l, p.x);
                    const y = try ctx.num(&e, l, p.y);
                    pts[i] = .{ @floatCast(x), @floatCast(y) };
                    minx = @min(minx, x);
                    miny = @min(miny, y);
                    maxx = @max(maxx, x);
                    maxy = @max(maxy, y);
                }
                r.points = pts;
                if (pts.len > 0) {
                    r.left = minx;
                    r.top = miny;
                    r.w = maxx - minx;
                    r.h = maxy - miny;
                }
                r.pivot = .{ r.left + r.w / 2, r.top + r.h / 2 };
                if (l.fill) |p| r.fill = (try ctx.eval(&e, l, p)).color;
            },
            .text => {
                r.text = try ctx.tmpl(&e, l, l.text.?);
                if (l.size) |p| r.size = try ctx.num(&e, l, p);
                if (l.color) |p| r.color = (try ctx.eval(&e, l, p)).color;
                if (l.wrap) |p| r.wrap = try ctx.num(&e, l, p);
                if (l.line_spacing) |p| r.line_spacing = try ctx.num(&e, l, p);
                if (l.max_lines) |p| r.max_lines = try ctx.num(&e, l, p);
                r.at[0] = try ctx.num(&e, l, l.at.?.x);
                r.at[1] = try ctx.num(&e, l, l.at.?.y);
                if (r.size <= 0) {
                    try ctx.report(.err, 3101, l.size.?.pos, null, try ctx.layerMsg(l, "font size must be above 0, got {d}", .{r.size}), null);
                    return error.Failed;
                }
                r.font = try ctx.fontFor(l);
                const max_lines: ?usize = if (r.max_lines) |m| @intFromFloat(@max(1, @floor(m))) else null;
                var opts: text.Options = .{
                    .size = @floatCast(r.size),
                    .wrap = if (r.wrap) |w| @floatCast(@max(1, w)) else null,
                    .line_spacing = @floatCast(r.line_spacing),
                    .max_lines = max_lines,
                    .justify = l.alignment == .justify,
                };
                var lay = try text.layout(ctx.arena, r.font.?, r.text, opts);
                // Auto-shrink: largest size (in 0.5 px steps) whose block fits.
                const max_w: ?f64 = if (l.max_width) |p| try ctx.num(&e, l, p) else null;
                const max_h: ?f64 = if (l.max_height) |p| try ctx.num(&e, l, p) else null;
                if (max_w != null or max_h != null) {
                    const fits = struct {
                        fn f(x: text.Layout, mw: ?f64, mh: ?f64) bool {
                            return (mw == null or x.block_w <= mw.? + 0.01) and (mh == null or x.block_h <= mh.? + 0.01);
                        }
                    }.f;
                    if (!fits(lay, max_w, max_h)) {
                        const min_size = if (l.min_size) |p| @max(1, try ctx.num(&e, l, p)) else @min(r.size, 8);
                        var lo: f64 = @floor(@min(min_size, r.size) * 2);
                        var hi: f64 = @floor(r.size * 2);
                        var best: ?text.Layout = null;
                        var best_size: f64 = lo / 2;
                        while (lo <= hi) {
                            const mid = @floor((lo + hi) / 2);
                            opts.size = @floatCast(mid / 2);
                            const t = try text.layout(ctx.arena, r.font.?, r.text, opts);
                            if (fits(t, max_w, max_h)) {
                                best = t;
                                best_size = mid / 2;
                                lo = mid + 1;
                            } else hi = mid - 1;
                        }
                        if (best) |b| {
                            lay = b;
                        } else {
                            opts.size = @floatCast(best_size);
                            lay = try text.layout(ctx.arena, r.font.?, r.text, opts);
                            try ctx.report(.warning, 3203, l.pos, null, try ctx.layerMsg(l, "the text does not fit even at min_size {d}", .{best_size}), "allow a smaller min_size, a larger box or shorter text");
                        }
                        r.size = best_size;
                    }
                }
                r.layout = lay;
                if (lay.truncated) try ctx.report(.warning, 3201, l.max_lines.?.pos, null, try ctx.layerMsg(l, "text was cut to {d} line(s)", .{max_lines.?}), null);
                if (lay.missing_glyphs) try ctx.report(.warning, 4003, l.text.?.pos, null, try ctx.layerMsg(l, "the font has no glyphs for some characters; they are drawn as boxes", .{}), null);
                r.w = lay.block_w;
                r.h = lay.block_h;
                r.left = r.at[0] - fx * r.w;
                r.top = if (l.anchor.isBaseline()) r.at[1] - lay.ascent else r.at[1] - fy * r.h;
                r.pivot = r.at;
            },
        }
        if (l.stroke) |s| {
            r.stroke = .{
                .color = (try ctx.eval(&e, l, s.color)).color,
                .width = @max(0, try ctx.num(&e, l, s.width)),
            };
        }
    }

    fn indexOf(ctx: *Ctx, l: *const Layer) usize {
        return (@intFromPtr(l) - @intFromPtr(ctx.d.layers.ptr)) / @sizeOf(Layer);
    }

    /// Evaluates every iteration of a repeated layer (once per card).
    fn repeatInstances(ctx: *Ctx, li: usize) Failed![]Resolved {
        if (ctx.instances[li]) |x| return x;
        switch (ctx.states[li]) {
            .failed => return error.Failed,
            .busy => {
                const l = &ctx.d.layers[li];
                try ctx.report(.err, 3004, l.pos, null, try ctx.layerMsg(l, "the layer depends on itself through its group", .{}), null);
                return error.Failed;
            },
            else => {},
        }
        ctx.states[li] = .busy;
        const out = ctx.evalRepeat(li) catch |e| {
            ctx.states[li] = .failed;
            return e;
        };
        ctx.states[li] = .done;
        ctx.instances[li] = out;
        return out;
    }

    fn evalRepeat(ctx: *Ctx, li: usize) Failed![]Resolved {
        const l = &ctx.d.layers[li];
        const rep = l.repeat.?;
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        ctx.current = li;
        ctx.locals = &.{};
        defer {
            ctx.locals = saved_locals;
            ctx.current = saved_current;
        }
        var e = ctx.newEnv();
        var count: usize = 0;
        var list: []const []const Value = &.{};
        if (rep.count) |p| {
            const n = @floor(try ctx.num(&e, l, p));
            if (n > limits.iterations) {
                try ctx.report(.err, 5001, p.pos, null, try ctx.layerMsg(l, "repeat count {d} is above the limit of {d}", .{ n, limits.iterations }), null);
                return error.Failed;
            }
            count = if (n > 0) @intFromFloat(n) else 0;
        } else if (rep.each) |p| {
            list = (try ctx.eval(&e, l, p)).list;
            if (list.len > limits.iterations) {
                try ctx.report(.err, 5001, p.pos, null, try ctx.layerMsg(l, "repeat over {d} items is above the limit of {d}", .{ list.len, limits.iterations }), null);
                return error.Failed;
            }
            count = list.len;
        }
        const out = try ctx.arena.alloc(Resolved, count);
        var locals: [2]Local = undefined;
        for (0..count) |i| {
            locals[0] = .{ .name = rep.index_name, .value = .{ .number = @floatFromInt(i) } };
            var n: usize = 1;
            if (rep.item_name) |name| {
                locals[1] = .{ .name = name, .value = .{ .item = list[i] } };
                n = 2;
            }
            ctx.locals = locals[0..n];
            try ctx.evalLayer(l, &out[i]);
        }
        return out;
    }

    fn fontFor(ctx: *Ctx, l: *const Layer) Failed!*text.Font {
        if (ctx.d.findFont(l.font)) |f| {
            const path = (try project.normalize(ctx.arena, f.path)) orelse {
                try ctx.report(.err, 1203, f.pos, null, try std.fmt.allocPrint(ctx.arena, "font path '{s}' is outside the project", .{f.path}), null);
                return error.Failed;
            };
            if (try ctx.assets.font(path)) |font| return font;
            try ctx.reportFor(null, .warning, 4005, f.pos, null, try std.fmt.allocPrint(ctx.arena, "font '{s}' ('{s}') is missing or not a TrueType/OpenType font; using the default font", .{ f.name, path }), "add the font file to the project");
        }
        return ctx.assets.defaultFont();
    }

    // ---------------------------------------------------------- drawing

    /// Draws a group's children into their own bitmap, then applies the
    /// group's effects, opacity and rotation like a single layer.
    fn drawGroup(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, gi: usize, r: *const Resolved) Failed!void {
        ctx.drawn += 1;
        if (ctx.drawn > limits.layers) return error.Failed;
        // Effects work on the group's own bounds (like a single layer's);
        // otherwise the children draw onto a canvas-sized bitmap, grown to
        // the bounds when rotation can bring off-canvas parts into view.
        var x0: f64 = @floor(@min(0, r.left - 64));
        var y0: f64 = @floor(@min(0, r.top - 64));
        var x1: f64 = @ceil(@max(ctx.canvas_w, r.left + r.w + 64));
        var y1: f64 = @ceil(@max(ctx.canvas_h, r.top + r.h + 64));
        if (l.effects.len > 0) {
            x0 = @floor(r.left - 2);
            y0 = @floor(r.top - 2);
            x1 = @ceil(r.left + r.w + 2);
            y1 = @ceil(r.top + r.h + 2);
        }
        if (x1 - x0 < 1 or y1 - y0 < 1) return;
        if ((r.rotate == 0 and l.effects.len == 0) or (x1 - x0) * (y1 - y0) > limits.image_pixels) {
            x0 = 0;
            y0 = 0;
            x1 = ctx.canvas_w;
            y1 = ctx.canvas_h;
        }
        var tmp: ?raster.Bitmap = try raster.Bitmap.init(ctx.gpa, @intFromFloat(x0), @intFromFloat(y0), @intFromFloat(x1 - x0), @intFromFloat(y1 - y0));
        defer if (tmp) |*t| t.deinit(ctx.gpa);
        var ci = gi + 1;
        while (ci < l.end) : (ci += 1) {
            const child = &ctx.d.layers[ci];
            if (child.parent != gi) continue;
            drawOne(ctx, &tmp.?, child, ci) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Failed => continue,
            };
        }
        try ctx.finishLayer(canvas, l, r, &tmp);
    }

    fn drawLayer(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved) Failed!void {
        ctx.drawn += 1;
        if (ctx.drawn > limits.layers) {
            if (ctx.drawn == limits.layers + 1) try ctx.report(.err, 5001, l.pos, null, try ctx.layerMsg(l, "more than {d} layers after repeat", .{limits.layers}), null);
            return error.Failed;
        }
        var m: f64 = 2;
        if (r.stroke) |s| m += s.width / 2;
        if (l.kind == .text) m += r.size * 0.6;
        const x0 = r.left - m;
        const y0 = r.top - m;
        const x1 = r.left + r.w + m;
        const y1 = r.top + r.h + m;
        const rotated = r.rotate != 0;
        if (!rotated and (x1 <= 0 or y1 <= 0 or x0 >= ctx.canvas_w or y0 >= ctx.canvas_h)) {
            try ctx.report(.hint, 3202, l.pos, null, try ctx.layerMsg(l, "the layer is entirely outside the canvas", .{}), null);
            return;
        }
        const direct = l.effects.len == 0 and r.opacity >= 1 and !rotated;
        var tmp: ?raster.Bitmap = null;
        defer if (tmp) |*t| t.deinit(ctx.gpa);
        var target = canvas;
        if (!direct) {
            var bx0 = @floor(x0);
            var by0 = @floor(y0);
            var bx1 = @ceil(x1);
            var by1 = @ceil(y1);
            if ((l.effects.len == 0 and !rotated) or (bx1 - bx0) * (by1 - by0) > limits.image_pixels) {
                bx0 = @max(bx0, 0);
                by0 = @max(by0, 0);
                bx1 = @min(bx1, ctx.canvas_w);
                by1 = @min(by1, ctx.canvas_h);
            }
            tmp = try raster.Bitmap.init(ctx.gpa, @intFromFloat(bx0), @intFromFloat(by0), @intFromFloat(bx1 - bx0), @intFromFloat(by1 - by0));
            target = &tmp.?;
        }
        const stroke: ?raster.StrokeStyle = if (r.stroke) |s| .{ .paint = raster.paint(s.color, 1), .width = @floatCast(s.width) } else null;
        const lf: f32 = @floatCast(r.left);
        const tf: f32 = @floatCast(r.top);
        const wf: f32 = @floatCast(r.w);
        const hf: f32 = @floatCast(r.h);
        switch (l.kind) {
            .group => unreachable,
            .rect => raster.drawShape(target, .rect, lf, tf, wf, hf, @floatCast(r.radius), raster.paint(r.fill, 1), stroke),
            .ellipse => raster.drawShape(target, .ellipse, lf, tf, wf, hf, 0, raster.paint(r.fill, 1), stroke),
            .polygon => {
                if (l.closed) try raster.fillPolygon(ctx.gpa, target, r.points, raster.paint(r.fill, 1));
                if (stroke) |s| raster.strokePolyline(target, r.points, l.closed, s);
            },
            .text => try text.draw(ctx.gpa, target, r.font.?, &r.layout.?, lf, tf, switch (l.alignment) {
                .left => .left,
                .center => .center,
                .right => .right,
                .justify => .justify,
            }, raster.paint(r.color, 1)),
            .image => {
                const img = r.image orelse {
                    raster.drawPlaceholder(target, lf, tf, wf, hf);
                    return ctx.finishLayer(canvas, l, r, &tmp);
                };
                var dx = lf;
                var dy = tf;
                var dw = wf;
                var dh = hf;
                const iw: f32 = @floatFromInt(img.w);
                const ih: f32 = @floatFromInt(img.h);
                switch (l.fit) {
                    .fill => {},
                    .contain, .cover => {
                        const s = if (l.fit == .contain) @min(wf / iw, hf / ih) else @max(wf / iw, hf / ih);
                        dw = iw * s;
                        dh = ih * s;
                        dx = lf + (wf - dw) / 2;
                        dy = tf + (hf - dh) / 2;
                    },
                }
                try raster.drawImage(ctx.gpa, target, img, dx, dy, dw, dh, .{ lf, tf, lf + wf, tf + hf }, l.smoothing == .bilinear, 1);
            },
        }
        try ctx.finishLayer(canvas, l, r, &tmp);
    }

    fn finishLayer(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved, tmp: *?raster.Bitmap) Failed!void {
        const t = if (tmp.*) |*t| t else return;
        var e = ctx.newEnv();
        for (l.effects) |eff| {
            switch (eff.kind) {
                .crop, .fade => {
                    const len: f32 = @floatCast(try ctx.num(&e, l, eff.length.?));
                    const side: raster.Side = switch (eff.side) {
                        .top => .top,
                        .bottom => .bottom,
                        .left => .left,
                        .right => .right,
                    };
                    if (eff.kind == .crop) {
                        try raster.crop(ctx.gpa, t, side, len, @floatCast(l.anchor.fx()), @floatCast(l.anchor.fy()));
                    } else raster.fade(t, side, len);
                },
                else => {
                    const strength: f32 = if (eff.strength) |p| @floatCast(try ctx.num(&e, l, p)) else 1;
                    try raster.convolve(ctx.gpa, t, switch (eff.kind) {
                        .sharpen => .sharpen,
                        .detail => .detail,
                        .edge_enhance => .edge_enhance,
                        .find_edges => .find_edges,
                        else => unreachable,
                    }, strength);
                },
            }
        }
        if (r.rotate != 0) {
            raster.compositeRotated(canvas, t, @floatCast(r.rotate * std.math.pi / 180), @floatCast(r.pivot[0]), @floatCast(r.pivot[1]), @floatCast(r.opacity));
            return;
        }
        raster.multiplyOpacity(t, @floatCast(r.opacity));
        raster.composite(canvas, t);
    }
};

/// The card's value for a param, or the default, or the type's zero value.
pub fn paramValue(d: *const Design, card: *const project.Card, pi: usize) Value {
    if (pi < card.values.len) if (card.values[pi]) |v| return v;
    const p = &d.params[pi];
    if (p.default) |v| return v;
    return switch (p.kind) {
        .number, .integer => .{ .number = 0 },
        .bool => .{ .bool = false },
        .text, .@"enum" => .{ .text = if (p.options.len > 0) p.options[0] else "" },
        .color => .{ .color = Color.transparent },
        .image => .{ .image = "" },
        .list => .{ .list = &.{} },
    };
}

fn readField(r: *const Resolved, path: []const []const u8) ?Value {
    const eq = std.mem.eql;
    if (path.len == 2) {
        const a = path[0];
        const b = path[1];
        if (eq(u8, a, "bounds")) {
            const v: f64 = if (eq(u8, b, "left")) r.left else if (eq(u8, b, "top")) r.top else if (eq(u8, b, "right")) r.left + r.w else if (eq(u8, b, "bottom")) r.top + r.h else if (eq(u8, b, "w")) r.w else if (eq(u8, b, "h")) r.h else if (eq(u8, b, "cx")) r.left + r.w / 2 else if (eq(u8, b, "cy")) r.top + r.h / 2 else return null;
            return .{ .number = v };
        }
        if (eq(u8, a, "box")) {
            const i: usize = if (eq(u8, b, "x")) 0 else if (eq(u8, b, "y")) 1 else if (eq(u8, b, "w")) 2 else 3;
            return .{ .number = r.box[i] };
        }
        if (eq(u8, a, "at")) return .{ .number = if (eq(u8, b, "x")) r.at[0] else r.at[1] };
        if (eq(u8, a, "stroke")) {
            const s = r.stroke orelse return if (eq(u8, b, "width")) Value{ .number = 0 } else Value{ .color = Color.transparent };
            return if (eq(u8, b, "width")) .{ .number = s.width } else .{ .color = s.color };
        }
        return null;
    }
    const f = path[0];
    if (eq(u8, f, "opacity")) return .{ .number = r.opacity };
    if (eq(u8, f, "rotate")) return .{ .number = r.rotate };
    if (eq(u8, f, "visible")) return .{ .bool = r.visible };
    if (eq(u8, f, "fill")) return .{ .color = r.fill };
    if (eq(u8, f, "radius")) return .{ .number = r.radius };
    if (eq(u8, f, "color")) return .{ .color = r.color };
    if (eq(u8, f, "text")) return .{ .text = r.text };
    if (eq(u8, f, "size")) return .{ .number = r.size };
    if (eq(u8, f, "line_spacing")) return .{ .number = r.line_spacing };
    if (eq(u8, f, "wrap")) return .{ .number = r.wrap orelse 0 };
    if (eq(u8, f, "max_lines")) return .{ .number = r.max_lines orelse 0 };
    if (eq(u8, f, "src")) return .{ .text = r.src };
    return null;
}

/// Renders card `index` of `set`. Returns null when nothing could be drawn
/// (the reasons are in `diags`). The caller owns the returned bitmap.
pub fn renderCard(gpa: Allocator, assets: *Assets, set: *const project.Set, index: usize, opts: Options, diags: *diag.List) Allocator.Error!?raster.Bitmap {
    const d = set.design;
    if (!d.ok or index >= set.cards.len) return null;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const states = try arena.alloc(State, d.layers.len);
    @memset(states, .todo);
    const resolved = try arena.alloc(Resolved, d.layers.len);
    const instances = try arena.alloc(?[]Resolved, d.layers.len);
    @memset(instances, null);
    var ctx: Ctx = .{
        .gpa = gpa,
        .arena = arena,
        .assets = assets,
        .d = d,
        .card = &set.cards[index],
        .index = index,
        .opts = opts,
        .diags = diags,
        .states = states,
        .resolved = resolved,
        .instances = instances,
    };

    // Canvas
    var e = ctx.newEnv();
    const cw = ctx.num(&e, null, d.canvas_w.?) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return null,
    };
    const ch = ctx.num(&e, null, d.canvas_h.?) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => return null,
    };
    const w = @round(cw);
    const h = @round(ch);
    if (!(w >= 1 and h >= 1)) {
        try ctx.report(.err, 3101, d.canvas_w.?.pos, null, try std.fmt.allocPrint(arena, "the canvas is {d} x {d}; both sides must be at least 1", .{ w, h }), null);
        return null;
    }
    if (w > limits.canvas_side or h > limits.canvas_side) {
        try ctx.report(.err, 5001, d.canvas_w.?.pos, null, try std.fmt.allocPrint(arena, "the canvas is {d} x {d}; the limit is 10000 x 10000", .{ w, h }), null);
        return null;
    }
    ctx.canvas_w = w;
    ctx.canvas_h = h;
    e = ctx.newEnv();
    var canvas = try raster.Bitmap.init(gpa, 0, 0, @intFromFloat(w), @intFromFloat(h));
    errdefer canvas.deinit(gpa);
    if (d.background) |bg| {
        const v = ctx.eval(&e, null, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => Value{ .color = Color.transparent },
        };
        canvas.fill(raster.paint(v.color, 1));
    }

    for (d.layers, 0..) |*l, li| {
        if (l.parent != null) continue;
        drawOne(&ctx, &canvas, l, li) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => continue,
        };
    }
    return canvas;
}

fn drawOne(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, li: usize) Failed!void {
    if (l.repeat == null) {
        const r = try ctx.resolve(li);
        if (ctx.opts.outline) |o| try o.add(l, null, r);
        if (!r.visible) return;
        if (l.kind == .group) return ctx.drawGroup(canvas, l, li, r);
        return ctx.drawLayer(canvas, l, r);
    }
    const list = try ctx.repeatInstances(li);
    for (list, 0..) |*r, i| {
        if (ctx.opts.outline) |o| try o.add(l, @intCast(i), r);
        if (r.visible) try ctx.drawLayer(canvas, l, r);
    }
}
