//! Renders one card: evaluates every layer for the card's values (resolving
//! `@layer` references lazily, with cycle detection), draws, applies effects
//! and composites (docs: site/content/docs/layers.md and
//! site/content/docs/rendering-model.md).

const std = @import("std");
const c = @import("c.zig");
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const bdate = @import("builtins/date.zig");
const expr = @import("expr.zig");
const design_mod = @import("design.zig");
const project = @import("project.zig");
const raster = @import("raster.zig");
const text = @import("text.zig");
const vector = @import("vector.zig");
const Allocator = std.mem.Allocator;
const Value = value.Value;
const Color = value.Color;
const Design = design_mod.Design;
const Layer = design_mod.Layer;
const Prop = design_mod.Prop;

pub const default_font_data = @embedFile("assets/Lato-Regular.ttf");
/// Arrows, shapes, stars, check marks, dice: the last fallback for glyphs.
pub const symbol_font_data = @embedFile("assets/NotoSansSymbols2-Subset.ttf");

pub const limits = struct {
    pub const canvas_side = 10000;
    pub const layers = 500;
    pub const iterations = 1000;
    pub const image_pixels = 50_000_000;
};

/// An expression (or template) evaluated in place of the field at `pos` of
/// design `file`, the first time the card evaluates that field, with every
/// node's value traced. The field's own value is used for the card as usual.
/// Values and the problem are copied into the trace's arena.
pub const Probe = struct {
    file: []const u8,
    pos: u32,
    root: ?*const expr.Node = null,
    tmpl: ?expr.Template = null,
    trace: expr.Trace,
    /// How often the card evaluated the field (iterations, calls, layout
    /// passes); 0 when it never did.
    hits: u32 = 0,
    value: ?Value = null,
    problem: ?expr.Problem = null,
};

pub const Options = struct {
    /// ISO date for `render.date`, chosen once by whoever starts the render.
    date: []const u8 = "1970-01-01",
    /// UTC instant of the render (`YYYY-MM-DDTHH:MM:SSZ`). When set,
    /// `render.date` and `render.time` come from it plus the UTC offset, and
    /// `date` is ignored.
    now: ?[]const u8 = null,
    /// Overrides the project's `utc_offset` (hours).
    utc_offset: ?f64 = null,
    /// Editor preview: missing images become a placeholder and a warning.
    preview: bool = false,
    /// When set, receives the resolved bounds of every layer (the editor uses
    /// them for selection and hit testing).
    outline: ?*Outline = null,
    /// Evaluate and count every layer without drawing (`yoshida check`):
    /// finds the errors that depend on card data. URL images that are not
    /// in the file system are skipped instead of reported.
    dry: bool = false,
    /// Bitmap pixels per canvas pixel. Below 1 a proxy render for the
    /// preview, above 1 a larger export; the bitmap must stay within
    /// `limits.canvas_side` per side. Layout, expressions and the outline
    /// stay in canvas pixels, so only the pixels get coarser or finer.
    scale: f64 = 1,
    /// Draw only some layers (editor drag preview). Layers that are hidden
    /// by the filter are still evaluated and outlined.
    filter: ?Filter = null,
    /// Editor live values: evaluates another expression where one field is
    /// evaluated, with the same names and layout (see `Probe`).
    probe: ?*Probe = null,
    /// Draw into this vector scene instead of pixels (see `renderVector`).
    /// The returned bitmap is then a placeholder.
    vector: ?*vector.Scene = null,

    pub const Filter = struct {
        ids: []const []const u8,
        mode: Mode,

        /// `only`: just these layers (and what is inside them), without the
        /// background. `except`: everything but these layers.
        pub const Mode = enum { only, except };
    };
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
    symbol_font: ?text.Font = null,
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
        if (a.symbol_font) |*f| f.deinit(a.gpa);
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

    /// The bundled default font; it falls back to the bundled symbol font.
    pub fn defaultFont(a: *Assets) Allocator.Error!*text.Font {
        if (a.default_font == null) {
            a.symbol_font = (try text.Font.init(a.gpa, symbol_font_data)).?;
            a.default_font = (try text.Font.init(a.gpa, default_font_data)).?;
            a.default_font.?.fallback = &a.symbol_font.?;
        }
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
                p.fallback = try a.defaultFont();
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
    stroke: ?struct { color: Color, width: f64, dash: []const f32 = &.{} } = null,
    radius: f64 = 0,
    /// Ellipse arc in degrees clockwise from the top.
    arc: ?[2]f64 = null,
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

/// A group's coordinate frame: its `translate`, and for a repeated group the
/// loop names of the iteration being evaluated.
const Frame = struct {
    locals: []const Local = &.{},
    translate: [2]f64 = .{ 0, 0 },
};

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
    clock: Clock = .{},
    canvas_w: f64 = 0,
    canvas_h: f64 = 0,
    /// Bitmap pixels per canvas pixel (`Options.scale`).
    k: f64 = 1,
    /// Inside a layer that `Options.filter` selected (mode `only`).
    filter_inside: bool = false,
    states: []State,
    resolved: []Resolved,
    /// Repeated layers: every iteration, evaluated once per card.
    instances: []?[]Resolved,
    locals: []const Local = &.{},
    current: ?usize = null,
    /// Visible layers drawn so far, and per layer (for the 5001 message).
    drawn: usize = 0,
    counts: []u32 = &.{},
    /// Design constants, evaluated once per card.
    consts: []?Value = &.{},
    /// Groups: the current frame (a repeated group only has one while one of
    /// its iterations is evaluated or drawn).
    frames: []?Frame = &.{},
    frame_busy: []bool = &.{},
    /// Repeated groups: the frame of every iteration.
    group_iters: []?[]Frame = &.{},
    /// Repeated layers being evaluated: iterations done so far (for
    /// references to earlier iterations such as @row[i - 1]).
    partial: []?[]Resolved = &.{},
    partial_done: []usize = &.{},
    /// Nesting of references into other iterations (cycle guard).
    depth: usize = 0,
    /// Iteration of the nearest repeated group being drawn (editor outline).
    outline_instance: ?u32 = null,
    /// Text `shrink_group`: smallest size per group name, per card.
    shrink: std.StringHashMapUnmanaged(f64) = .empty,
    shrink_busy: std.StringHashMapUnmanaged(void) = .empty,
    measuring: bool = false,
    /// The scene being filled; null while drawing pixels, also inside a
    /// part of a vector render that is drawn as pixels.
    scene: ?*vector.Scene = null,
    /// Set while a part of a vector render is drawn as pixels: where
    /// `finishLayer` leaves the finished bitmap instead of compositing it.
    capture: ?*?raster.Bitmap = null,

    fn newEnv(ctx: *Ctx) expr.Env {
        return .{
            .arena = ctx.arena,
            .canvas_w = ctx.canvas_w,
            .canvas_h = ctx.canvas_h,
            .card_id = ctx.card.id,
            .render_index = @floatFromInt(ctx.index),
            .render_date = ctx.clock.date,
            .render_time = ctx.clock.time,
            .render_now = ctx.clock.now,
            .ctx = ctx,
            .lookup = lookup,
            .layerRef = layerRef,
            .avgColor = avgColor,
            .constValue = constValue,
            .callUser = callUser,
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
        // The same problem can be found twice (a text measured for its
        // shrink group, then drawn); report it once.
        for (ctx.diags.items.items) |o| {
            if (o.code == d.code and o.line == d.line and o.col == d.col and std.mem.eql(u8, o.file, d.file) and std.mem.eql(u8, o.message, d.message) and eqlOpt(o.card, d.card)) return;
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
        try ctx.probeAt(env, p.pos);
        return env.eval(p.node) catch |e| return ctx.evalFailed(e, env, layer, p.pos);
    }

    /// Runs the probe when `pos` is its field (see `Probe`).
    fn probeAt(ctx: *Ctx, env: *const expr.Env, pos: u32) Allocator.Error!void {
        const pr = ctx.opts.probe orelse return;
        if (pr.pos != pos or !std.mem.eql(u8, pr.file, ctx.d.file)) return;
        pr.hits += 1;
        if (pr.hits > 1) return;
        var e = env.*;
        e.trace = &pr.trace;
        e.problem = null;
        const v = if (pr.tmpl) |t|
            if (e.template(t)) |out| Value{ .text = out } else |err| err
        else if (pr.root) |r| e.eval(r) else return;
        const got = v catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Eval => {
                if (e.problem) |p| pr.problem = .{
                    .code = p.code,
                    .start = p.start,
                    .end = p.end,
                    .message = try pr.trace.arena.dupe(u8, p.message),
                    .hint = if (p.hint) |h| try pr.trace.arena.dupe(u8, h) else null,
                };
                return;
            },
        };
        pr.value = try got.dupe(pr.trace.arena);
    }

    fn num(ctx: *Ctx, env: *expr.Env, layer: ?*const Layer, p: Prop) Failed!f64 {
        const v = (try ctx.eval(env, layer, p)).number;
        if (!std.math.isFinite(v)) {
            const msg = if (layer) |l| try ctx.layerMsg(l, "the value is not a finite number", .{}) else "the value is not a finite number";
            try ctx.report(.err, 3103, p.pos, null, msg, null);
            return error.Failed;
        }
        return v;
    }

    fn tmpl(ctx: *Ctx, env: *expr.Env, layer: *const Layer, t: design_mod.Tmpl) Failed![]const u8 {
        env.axis = .none;
        try ctx.probeAt(env, t.pos);
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

    fn layerRef(ptr: *anyopaque, id: []const u8, path: []const []const u8, index: ?f64) expr.EvalError!Value {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        const li = ctx.d.findLayer(id) orelse return error.Eval;
        const got = ctx.refTarget(li, index) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => return error.Eval,
        };
        // Positions are read in the referencing layer's frame.
        const off = if (ctx.current) |cur| ctx.offsetOf(cur) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => return error.Eval,
        } else [2]f64{ 0, 0 };
        return readField(&got, path, off) orelse error.Eval;
    }

    /// The layer a reference reads: the layer itself, or one iteration of
    /// it (its own repeat, or the repeated group around it).
    fn refTarget(ctx: *Ctx, li: usize, index: ?f64) Failed!Resolved {
        const kf = index orelse return (try ctx.resolve(li)).*;
        const l = &ctx.d.layers[li];
        const k: usize = if (kf >= 0 and kf < 1e9) @intFromFloat(@floor(kf)) else std.math.maxInt(usize);
        // The repeated group around `li` that is not in an iteration now.
        var open_group: ?usize = null;
        var p = l.parent;
        while (p) |gi| : (p = ctx.d.layers[gi].parent) {
            if (ctx.d.layers[gi].repeat != null and ctx.frames[gi] == null) open_group = gi;
        }
        if (open_group == null) {
            // Its own repeat. An iteration may read the ones before it.
            if (l.repeat == null) return (try ctx.resolve(li)).*;
            if (ctx.states[li] == .busy) if (ctx.partial[li]) |part| {
                if (k < ctx.partial_done[li]) return part[k];
                try ctx.report(.err, 3004, l.pos, null, try ctx.layerMsg(l, "iteration {d} is read before it is evaluated; an iteration can only read earlier ones", .{k}), null);
                return error.Failed;
            };
            const list = try ctx.repeatInstances(li);
            if (k >= list.len) return ctx.noIteration(l, k, list.len);
            return list[k];
        }
        const g = open_group.?;
        const iters = ctx.group_iters[g] orelse blk: {
            _ = try ctx.repeatInstances(g);
            break :blk ctx.group_iters[g] orelse return error.Failed;
        };
        if (k >= iters.len) return ctx.noIteration(l, k, iters.len);
        if (ctx.depth >= 16) {
            try ctx.report(.err, 3004, l.pos, null, try ctx.layerMsg(l, "references between iterations go around in a circle", .{}), null);
            return error.Failed;
        }
        ctx.depth += 1;
        defer ctx.depth -= 1;
        var saved = try ctx.saveGroup(g);
        defer ctx.restoreGroup(g, &saved);
        ctx.enterIteration(g, k);
        return (try ctx.resolve(li)).*;
    }

    fn noIteration(ctx: *Ctx, l: *const Layer, k: usize, n: usize) Failed {
        const from: ?*const Layer = if (ctx.current) |cur| &ctx.d.layers[cur] else null;
        const pos = if (from) |x| x.pos else l.pos;
        try ctx.report(.err, 3102, pos, null, try std.fmt.allocPrint(ctx.arena, "{s}iteration {d} of '{s}' does not exist; it has {d}", .{ if (from) |x| try std.fmt.allocPrint(ctx.arena, "layer '{s}': ", .{x.id}) else "", k, l.id, n }), null);
        return error.Failed;
    }

    // ---------------------------------------------------------- frames

    /// Loop names of the repeated groups around `li`, outermost first.
    fn outerLocals(ctx: *Ctx, li: usize) Failed![]const Local {
        var n: usize = 0;
        var p = ctx.d.layers[li].parent;
        while (p) |gi| : (p = ctx.d.layers[gi].parent) {
            if (ctx.d.layers[gi].repeat == null) continue;
            const fr = ctx.frames[gi] orelse return error.Failed;
            n += fr.locals.len;
        }
        if (n == 0) return &.{};
        const out = try ctx.arena.alloc(Local, n);
        var end = n;
        p = ctx.d.layers[li].parent;
        while (p) |gi| : (p = ctx.d.layers[gi].parent) {
            if (ctx.d.layers[gi].repeat == null) continue;
            const ls = ctx.frames[gi].?.locals;
            end -= ls.len;
            @memcpy(out[end..][0..ls.len], ls);
        }
        return out;
    }

    /// The frame of group `gi`: set by an iteration for a repeated group,
    /// computed once per card otherwise.
    fn frameOf(ctx: *Ctx, gi: usize) Failed!Frame {
        if (ctx.frames[gi]) |f| return f;
        const g = &ctx.d.layers[gi];
        if (g.repeat != null) return error.Failed;
        const t = g.translate orelse {
            ctx.frames[gi] = .{};
            return .{};
        };
        if (ctx.frame_busy[gi]) {
            try ctx.report(.err, 3004, g.pos, null, try ctx.layerMsg(g, "translate depends on a layer inside the group", .{}), "translate can use params, constants and layers outside the group");
            return error.Failed;
        }
        ctx.frame_busy[gi] = true;
        defer ctx.frame_busy[gi] = false;
        const xy = try ctx.evalTranslate(gi, t, try ctx.outerLocals(gi));
        ctx.frames[gi] = .{ .translate = xy };
        return ctx.frames[gi].?;
    }

    fn evalTranslate(ctx: *Ctx, gi: usize, t: design_mod.Point, locals: []const Local) Failed![2]f64 {
        const g = &ctx.d.layers[gi];
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        ctx.locals = locals;
        ctx.current = gi;
        defer {
            ctx.locals = saved_locals;
            ctx.current = saved_current;
        }
        var e = ctx.newEnv();
        return .{ try ctx.num(&e, g, t.x), try ctx.num(&e, g, t.y) };
    }

    /// How far the groups around `li` move it.
    fn offsetOf(ctx: *Ctx, li: usize) Failed![2]f64 {
        var off = [2]f64{ 0, 0 };
        var p = ctx.d.layers[li].parent;
        while (p) |gi| : (p = ctx.d.layers[gi].parent) {
            const f = try ctx.frameOf(gi);
            off[0] += f.translate[0];
            off[1] += f.translate[1];
        }
        return off;
    }

    /// Everything cached for the layers inside group `gi` (and its frame).
    const Saved = struct {
        frame: ?Frame,
        states: []State,
        resolved: []Resolved,
        instances: []?[]Resolved,
        frames: []?Frame,
        group_iters: []?[]Frame,
        partial: []?[]Resolved,
        partial_done: []usize,
    };

    fn saveGroup(ctx: *Ctx, gi: usize) Allocator.Error!Saved {
        const a = gi + 1;
        const b = ctx.d.layers[gi].end;
        return .{
            .frame = ctx.frames[gi],
            .states = try ctx.arena.dupe(State, ctx.states[a..b]),
            .resolved = try ctx.arena.dupe(Resolved, ctx.resolved[a..b]),
            .instances = try ctx.arena.dupe(?[]Resolved, ctx.instances[a..b]),
            .frames = try ctx.arena.dupe(?Frame, ctx.frames[a..b]),
            .group_iters = try ctx.arena.dupe(?[]Frame, ctx.group_iters[a..b]),
            .partial = try ctx.arena.dupe(?[]Resolved, ctx.partial[a..b]),
            .partial_done = try ctx.arena.dupe(usize, ctx.partial_done[a..b]),
        };
    }

    fn restoreGroup(ctx: *Ctx, gi: usize, s: *const Saved) void {
        const a = gi + 1;
        ctx.frames[gi] = s.frame;
        @memcpy(ctx.states[a..][0..s.states.len], s.states);
        @memcpy(ctx.resolved[a..][0..s.resolved.len], s.resolved);
        @memcpy(ctx.instances[a..][0..s.instances.len], s.instances);
        @memcpy(ctx.frames[a..][0..s.frames.len], s.frames);
        @memcpy(ctx.group_iters[a..][0..s.group_iters.len], s.group_iters);
        @memcpy(ctx.partial[a..][0..s.partial.len], s.partial);
        @memcpy(ctx.partial_done[a..][0..s.partial_done.len], s.partial_done);
    }

    /// Forgets what was evaluated inside group `gi`.
    fn resetGroup(ctx: *Ctx, gi: usize) void {
        const a = gi + 1;
        const b = ctx.d.layers[gi].end;
        @memset(ctx.states[a..b], .todo);
        @memset(ctx.instances[a..b], null);
        @memset(ctx.frames[a..b], null);
        @memset(ctx.group_iters[a..b], null);
        @memset(ctx.partial[a..b], null);
    }

    /// Makes iteration `k` of repeated group `gi` the current one.
    fn enterIteration(ctx: *Ctx, gi: usize, k: usize) void {
        ctx.frames[gi] = ctx.group_iters[gi].?[k];
        ctx.resetGroup(gi);
    }

    fn leaveIteration(ctx: *Ctx, gi: usize) void {
        ctx.frames[gi] = null;
        ctx.resetGroup(gi);
    }

    fn constValue(ptr: *anyopaque, index: usize) expr.EvalError!Value {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        if (ctx.consts[index]) |v| return v;
        const k = &ctx.d.consts[index];
        const saved = ctx.locals;
        ctx.locals = &.{};
        defer ctx.locals = saved;
        var e = ctx.newEnv();
        const v = ctx.eval(&e, null, k.prop) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => return error.Eval,
        };
        ctx.consts[index] = v;
        return v;
    }

    /// Evaluates a design function with its arguments as the only loop names.
    fn callUser(ptr: *anyopaque, index: usize, args: []const Value) expr.EvalError!Value {
        const ctx: *Ctx = @ptrCast(@alignCast(ptr));
        const f = &ctx.d.functions[index];
        const locals = try ctx.arena.alloc(Local, args.len);
        for (locals, f.args, args) |*lv, a, v| lv.* = .{ .name = a.name, .value = v };
        const saved = ctx.locals;
        ctx.locals = locals;
        defer ctx.locals = saved;
        var e = ctx.newEnv();
        try ctx.probeAt(&e, f.pos);
        return e.eval(f.body) catch |err| {
            // Report inside the function, where the expression is.
            if (ctx.evalFailed(err, &e, null, f.pos) == error.OutOfMemory) return error.OutOfMemory;
            return error.Eval;
        };
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
                if (ctx.opts.dry and project.isUrl(path)) return null;
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
        const outer = try ctx.outerLocals(li);
        ctx.states[li] = .busy;
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        ctx.locals = outer;
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
            .rect, .ellipse, .image => try ctx.evalBox(&e, l, r),
            .polygon => if (l.shape) |shape| {
                try ctx.evalBox(&e, l, r);
                r.points = try ctx.shapePoints(&e, l, shape, r);
                if (l.fill) |p| r.fill = (try ctx.eval(&e, l, p)).color;
            } else {
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
                if (l.shrink_group) |name| if (!ctx.measuring) {
                    const m = try ctx.shrinkMin(name);
                    if (m < r.size - 0.001) {
                        opts.size = @floatCast(m);
                        lay = try text.layout(ctx.arena, r.font.?, r.text, opts);
                        r.size = m;
                    }
                };
                r.layout = lay;
                if (lay.truncated) try ctx.report(.warning, 3201, l.max_lines.?.pos, null, try ctx.layerMsg(l, "text was cut to {d} line(s)", .{max_lines.?}), null);
                if (lay.missing_glyphs) try ctx.report(.warning, 4003, l.text.?.pos, null, try ctx.layerMsg(l, "neither the font nor the bundled fallback fonts have glyphs for some characters; they are drawn as boxes", .{}), null);
                r.w = lay.block_w;
                r.h = lay.block_h;
                r.left = r.at[0] - fx * r.w;
                r.top = if (l.anchor.isBaseline()) r.at[1] - lay.ascent else r.at[1] - fy * r.h;
                r.pivot = r.at;
            },
        }
        if (l.stroke) |s| {
            var dash: []f32 = &.{};
            if (s.dash.len > 0) {
                dash = try ctx.arena.alloc(f32, s.dash.len);
                for (s.dash, dash) |p, *d| d.* = @floatCast(@max(0, try ctx.num(&e, l, p)));
            }
            r.stroke = .{
                .color = (try ctx.eval(&e, l, s.color)).color,
                .width = @max(0, try ctx.num(&e, l, s.width)),
                .dash = dash,
            };
        }
        if (l.arc) |a| r.arc = .{ try ctx.num(&e, l, a.start), try ctx.num(&e, l, a.end) };
        if (l.kind != .group) {
            // Inside translated groups: from the group's frame to the canvas.
            const off = try ctx.offsetOf(ctx.indexOf(l));
            if (off[0] != 0 or off[1] != 0) {
                r.left += off[0];
                r.top += off[1];
                r.box[0] += off[0];
                r.box[1] += off[1];
                r.at[0] += off[0];
                r.at[1] += off[1];
                r.pivot[0] += off[0];
                r.pivot[1] += off[1];
                if (r.points.len > 0) {
                    const pts = try ctx.arena.alloc([2]f32, r.points.len);
                    for (r.points, pts) |p, *q| q.* = .{ p[0] + @as(f32, @floatCast(off[0])), p[1] + @as(f32, @floatCast(off[1])) };
                    r.points = pts;
                }
            }
        }
    }

    /// The smallest size any text of `shrink_group` `name` needs, over all
    /// their iterations (each measured on its own first).
    fn shrinkMin(ctx: *Ctx, name: []const u8) Failed!f64 {
        if (ctx.shrink.get(name)) |m| return m;
        // A member read while the group is measured gets its own size.
        if (ctx.shrink_busy.contains(name)) return std.math.inf(f64);
        try ctx.shrink_busy.put(ctx.arena, name, {});
        defer _ = ctx.shrink_busy.remove(name);
        const saved = ctx.measuring;
        ctx.measuring = true;
        defer ctx.measuring = saved;
        var m: f64 = std.math.inf(f64);
        for (ctx.d.layers, 0..) |*l, li| {
            const g = l.shrink_group orelse continue;
            if (!std.mem.eql(u8, g, name)) continue;
            ctx.measure(li, &m, 0) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Failed => {},
            };
        }
        try ctx.shrink.put(ctx.arena, name, m);
        return m;
    }

    /// Lowers `m` to the size of every visible iteration of text layer `li`,
    /// going through every iteration of the repeated groups around it
    /// (from `level` on, outermost first).
    fn measure(ctx: *Ctx, li: usize, m: *f64, level: usize) Failed!void {
        const l = &ctx.d.layers[li];
        var chain: [16]usize = undefined;
        var n: usize = 0;
        var p = l.parent;
        while (p) |gi| : (p = ctx.d.layers[gi].parent) {
            if (ctx.d.layers[gi].repeat == null) continue;
            std.mem.copyBackwards(usize, chain[1 .. n + 1], chain[0..n]);
            chain[0] = gi;
            n += 1;
        }
        if (level < n) {
            const g = chain[level];
            const iters = ctx.group_iters[g] orelse blk: {
                _ = try ctx.repeatInstances(g);
                break :blk ctx.group_iters[g] orelse return error.Failed;
            };
            var saved = try ctx.saveGroup(g);
            defer ctx.restoreGroup(g, &saved);
            for (0..iters.len) |k| {
                ctx.enterIteration(g, k);
                ctx.measure(li, m, level + 1) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Failed => {},
                };
            }
            return;
        }
        if (l.repeat != null) {
            for (try ctx.evalRepeat(li)) |r| if (r.visible) {
                m.* = @min(m.*, r.size);
            };
            return;
        }
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        ctx.locals = try ctx.outerLocals(li);
        ctx.current = li;
        defer {
            ctx.locals = saved_locals;
            ctx.current = saved_current;
        }
        var r: Resolved = .{};
        try ctx.evalLayer(l, &r);
        if (r.visible) m.* = @min(m.*, r.size);
    }

    /// `box` with its anchor: rect, ellipse, image and shape polygons.
    fn evalBox(ctx: *Ctx, e: *expr.Env, l: *const Layer, r: *Resolved) Failed!void {
        const box = l.box orelse return error.Failed;
        const fx = l.anchor.fx();
        const fy = l.anchor.fy();
        r.box[0] = try ctx.num(e, l, box.x);
        r.box[1] = try ctx.num(e, l, box.y);
        if (box.w) |p| r.box[2] = try ctx.num(e, l, p);
        if (box.h) |p| r.box[3] = try ctx.num(e, l, p);
        if (l.kind == .image) {
            r.src = try ctx.tmpl(e, l, l.src.?);
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
        if (l.kind == .rect or l.kind == .ellipse) {
            if (l.fill) |p| r.fill = (try ctx.eval(e, l, p)).color;
            if (l.radius) |p| r.radius = try ctx.num(e, l, p);
        }
    }

    /// Points of a preset shape filling the layer's box.
    fn shapePoints(ctx: *Ctx, e: *expr.Env, l: *const Layer, shape: design_mod.Shape, r: *const Resolved) Failed![]const [2]f32 {
        var unit: std.ArrayList([2]f64) = .empty;
        const a = ctx.arena;
        const count: f64 = if (shape.count) |p| @floor(try ctx.num(e, l, p)) else switch (shape.kind) {
            .star => 5,
            else => 6,
        };
        const inner_default: f64 = switch (shape.kind) {
            .star => 0.5,
            .arrow => 0.45,
            .cross => 0.34,
            .chevron => 0.4,
            else => 0,
        };
        const inner = std.math.clamp(if (shape.inner) |p| try ctx.num(e, l, p) else inner_default, 0.01, 1);
        // Shapes in a unit square (0..1), y down.
        switch (shape.kind) {
            .star, .polygon => {
                const n: usize = @intFromFloat(std.math.clamp(count, 3, 100));
                const steps = if (shape.kind == .star) n * 2 else n;
                for (0..steps) |i| {
                    const ang = (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps))) * 2 * std.math.pi - std.math.pi / 2.0;
                    const rad: f64 = if (shape.kind == .star and i % 2 == 1) 0.5 * inner else 0.5;
                    try unit.append(a, .{ 0.5 + rad * @cos(ang), 0.5 + rad * @sin(ang) });
                }
            },
            .triangle => try unit.appendSlice(a, &.{ .{ 0.5, 0 }, .{ 1, 1 }, .{ 0, 1 } }),
            .diamond => try unit.appendSlice(a, &.{ .{ 0.5, 0 }, .{ 1, 0.5 }, .{ 0.5, 1 }, .{ 0, 0.5 } }),
            .arrow => {
                // Pointing right; the head takes 40 % of the length.
                const t = inner / 2;
                try unit.appendSlice(a, &.{ .{ 0, 0.5 - t }, .{ 0.6, 0.5 - t }, .{ 0.6, 0 }, .{ 1, 0.5 }, .{ 0.6, 1 }, .{ 0.6, 0.5 + t }, .{ 0, 0.5 + t } });
            },
            .cross => {
                const t = inner / 2;
                try unit.appendSlice(a, &.{ .{ 0.5 - t, 0 }, .{ 0.5 + t, 0 }, .{ 0.5 + t, 0.5 - t }, .{ 1, 0.5 - t }, .{ 1, 0.5 + t }, .{ 0.5 + t, 0.5 + t }, .{ 0.5 + t, 1 }, .{ 0.5 - t, 1 }, .{ 0.5 - t, 0.5 + t }, .{ 0, 0.5 + t }, .{ 0, 0.5 - t }, .{ 0.5 - t, 0.5 - t } });
            },
            .chevron => {
                // Pointing right.
                const t = inner;
                try unit.appendSlice(a, &.{ .{ 0, 0 }, .{ t, 0 }, .{ 1, 0.5 }, .{ t, 1 }, .{ 0, 1 }, .{ 1 - t, 0.5 } });
            },
        }
        const pts = try a.alloc([2]f32, unit.items.len);
        for (unit.items, pts) |u, *p| p.* = .{ @floatCast(r.left + u[0] * r.w), @floatCast(r.top + u[1] * r.h) };
        return pts;
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
        const outer = try ctx.outerLocals(li);
        const saved_locals = ctx.locals;
        const saved_current = ctx.current;
        const saved_partial = ctx.partial[li];
        const saved_done = ctx.partial_done[li];
        ctx.current = li;
        ctx.locals = outer;
        defer {
            ctx.locals = saved_locals;
            ctx.current = saved_current;
            ctx.partial[li] = saved_partial;
            ctx.partial_done[li] = saved_done;
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
        // Every iteration's loop names: the groups' around it, then its own.
        const all = try ctx.arena.alloc([]Local, count);
        for (0..count) |i| {
            const own = try ctx.arena.alloc(Local, if (rep.item_name != null) 2 else 1);
            own[0] = .{ .name = rep.index_name, .value = .{ .number = @floatFromInt(i) } };
            if (rep.item_name) |name| own[1] = .{ .name = name, .value = .{ .item = list[i] } };
            all[i] = try std.mem.concat(ctx.arena, Local, &.{ outer, own });
        }
        const out = try ctx.arena.alloc(Resolved, count);
        if (l.kind == .group) {
            // A repeated group: first every iteration's frame (so layers can
            // read other iterations), then the layers inside, once per iteration.
            const iters = try ctx.arena.alloc(Frame, count);
            for (iters, 0..) |*fr, i| {
                fr.* = .{ .locals = all[i][outer.len..] };
                if (l.translate) |t| fr.translate = try ctx.evalTranslate(li, t, all[i]);
            }
            ctx.group_iters[li] = iters;
            defer ctx.leaveIteration(li);
            for (0..count) |i| {
                ctx.enterIteration(li, i);
                ctx.locals = all[i];
                try ctx.evalLayer(l, &out[i]);
            }
            return out;
        }
        ctx.partial[li] = out;
        for (0..count) |i| {
            ctx.partial_done[li] = i;
            ctx.locals = all[i];
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
        // Over the limit (or checking): keep counting the children.
        if (!ctx.countDrawn(gi) or ctx.opts.dry) return ctx.drawChildren(canvas, l, gi);
        // A plain group (no effects, fully opaque, not rotated) composites
        // exactly like its children drawn one by one, so they draw straight
        // onto the target without a scratch bitmap.
        if (l.effects.len == 0 and r.opacity >= 1 and r.rotate == 0) return ctx.drawChildren(canvas, l, gi);
        if (ctx.scene) |sc| return if (hasConvolve(l)) ctx.captureGroup(sc, canvas, l, gi, r) else ctx.emitGroup(sc, canvas, l, gi, r);
        const bb = ctx.groupBounds(l, r) orelse return;
        var tmp: ?raster.Bitmap = try ctx.scratch(bb[0], bb[1], bb[2], bb[3]);
        defer if (tmp) |*t| t.deinit(ctx.gpa);
        try ctx.drawChildren(&tmp.?, l, gi);
        try ctx.finishLayer(canvas, l, r, &tmp);
    }

    /// The canvas rectangle (x0, y0, x1, y1) a group's scratch bitmap
    /// covers; null when it is empty.
    fn groupBounds(ctx: *Ctx, l: *const Layer, r: *const Resolved) ?[4]f64 {
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
        if (x1 - x0 < 1 or y1 - y0 < 1) return null;
        if ((r.rotate == 0 and l.effects.len == 0) or (x1 - x0) * (y1 - y0) * ctx.k * ctx.k > limits.image_pixels) {
            x0 = 0;
            y0 = 0;
            x1 = ctx.canvas_w;
            y1 = ctx.canvas_h;
        }
        return .{ x0, y0, x1, y1 };
    }

    /// A transparent bitmap for the canvas rectangle (x0, y0)-(x1, y1), in
    /// bitmap pixels (`Options.scale`).
    fn scratch(ctx: *Ctx, x0: f64, y0: f64, x1: f64, y1: f64) Allocator.Error!raster.Bitmap {
        const px0 = @floor(x0 * ctx.k);
        const py0 = @floor(y0 * ctx.k);
        const px1 = @max(px0 + 1, @ceil(x1 * ctx.k));
        const py1 = @max(py0 + 1, @ceil(y1 * ctx.k));
        return raster.Bitmap.init(ctx.gpa, @intFromFloat(px0), @intFromFloat(py0), @intFromFloat(px1 - px0), @intFromFloat(py1 - py0));
    }

    /// Canvas points in bitmap pixels.
    fn scalePoints(ctx: *Ctx, pts: []const [2]f32) Allocator.Error![]const [2]f32 {
        if (ctx.k == 1) return pts;
        const k: f32 = @floatCast(ctx.k);
        const out = try ctx.arena.alloc([2]f32, pts.len);
        for (out, pts) |*o, q| o.* = .{ q[0] * k, q[1] * k };
        return out;
    }

    fn drawChildren(ctx: *Ctx, target: *raster.Bitmap, l: *const Layer, gi: usize) Failed!void {
        var ci = gi + 1;
        while (ci < l.end) : (ci += 1) {
            const child = &ctx.d.layers[ci];
            if (child.parent != gi) continue;
            drawOne(ctx, target, child, ci) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Failed => continue,
            };
        }
    }

    /// Counts one drawn layer; false once the card is over the limit.
    fn countDrawn(ctx: *Ctx, li: usize) bool {
        ctx.drawn += 1;
        ctx.counts[li] += 1;
        return ctx.drawn <= limits.layers;
    }

    /// Error 5001 for a card over the layer limit, naming the layers that
    /// use most of it.
    fn reportLayerLimit(ctx: *Ctx) Allocator.Error!void {
        const order = try ctx.arena.alloc(usize, ctx.counts.len);
        for (order, 0..) |*o, i| o.* = i;
        std.mem.sort(usize, order, ctx.counts, struct {
            fn gt(counts: []u32, a: usize, b: usize) bool {
                return counts[a] > counts[b];
            }
        }.gt);
        var aw: std.Io.Writer.Allocating = .init(ctx.arena);
        const w = &aw.writer;
        w.print("{d} visible layers after repeat, the limit is {d}; most: ", .{ ctx.drawn, limits.layers }) catch return error.OutOfMemory;
        var shown: usize = 0;
        for (order) |li| {
            if (ctx.counts[li] == 0 or shown == 5) break;
            if (shown > 0) w.writeAll(", ") catch return error.OutOfMemory;
            w.print("'{s}' {d}", .{ ctx.d.layers[li].id, ctx.counts[li] }) catch return error.OutOfMemory;
            shown += 1;
        }
        const top = &ctx.d.layers[order[0]];
        try ctx.report(.err, 5001, top.pos, null, aw.written(), "hide variants with \"visible\" (hidden layers do not count), or draw fewer layers per item");
    }

    fn drawLayer(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved) Failed!void {
        if (!ctx.countDrawn(ctx.indexOf(l))) return error.Failed;
        const bb = layerBounds(l, r);
        const rotated = r.rotate != 0;
        if (!rotated and (bb[2] <= 0 or bb[3] <= 0 or bb[0] >= ctx.canvas_w or bb[1] >= ctx.canvas_h)) {
            try ctx.report(.hint, 3202, l.pos, null, try ctx.layerMsg(l, "the layer is entirely outside the canvas", .{}), null);
            return;
        }
        if (ctx.opts.dry) return;
        if (ctx.scene) |sc| return if (hasConvolve(l)) ctx.captureLayer(sc, canvas, l, r, bb) else ctx.emitLayer(sc, l, r, bb);
        return ctx.paintLayer(canvas, l, r, bb);
    }

    /// The canvas rectangle (x0, y0, x1, y1) a layer can draw in: its
    /// bounds plus room for strokes and glyph overhang.
    fn layerBounds(l: *const Layer, r: *const Resolved) [4]f64 {
        var m: f64 = 2;
        if (r.stroke) |s| m += s.width / 2;
        if (l.kind == .text) m += r.size * 0.6 + (if (r.stroke) |s| s.width else 0);
        return .{ r.left - m, r.top - m, r.left + r.w + m, r.top + r.h + m };
    }

    /// Draws a layer into pixels: straight onto `canvas`, or into a scratch
    /// bitmap when it has effects, opacity or rotation.
    fn paintLayer(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved, bb: [4]f64) Failed!void {
        const x0 = bb[0];
        const y0 = bb[1];
        const x1 = bb[2];
        const y1 = bb[3];
        const rotated = r.rotate != 0;
        const direct = l.effects.len == 0 and r.opacity >= 1 and !rotated and ctx.capture == null;
        var tmp: ?raster.Bitmap = null;
        defer if (tmp) |*t| t.deinit(ctx.gpa);
        var target = canvas;
        if (!direct) {
            var bx0 = @floor(x0);
            var by0 = @floor(y0);
            var bx1 = @ceil(x1);
            var by1 = @ceil(y1);
            if ((l.effects.len == 0 and !rotated) or (bx1 - bx0) * (by1 - by0) * ctx.k * ctx.k > limits.image_pixels) {
                bx0 = @max(bx0, 0);
                by0 = @max(by0, 0);
                bx1 = @min(bx1, ctx.canvas_w);
                by1 = @min(by1, ctx.canvas_h);
            }
            tmp = try ctx.scratch(bx0, by0, bx1, by1);
            target = &tmp.?;
        }
        // Everything below is in bitmap pixels: canvas pixels times k.
        const k: f32 = @floatCast(ctx.k);
        const stroke: ?raster.StrokeStyle = if (r.stroke) |s| .{
            .paint = raster.paint(s.color, 1),
            .width = @as(f32, @floatCast(s.width)) * k,
            .dash = if (k == 1 or s.dash.len == 0) s.dash else blk: {
                const dash = try ctx.arena.alloc(f32, s.dash.len);
                for (dash, s.dash) |*o, v| o.* = v * k;
                break :blk dash;
            },
        } else null;
        const lf: f32 = @as(f32, @floatCast(r.left)) * k;
        const tf: f32 = @as(f32, @floatCast(r.top)) * k;
        const wf: f32 = @as(f32, @floatCast(r.w)) * k;
        const hf: f32 = @as(f32, @floatCast(r.h)) * k;
        const radius: f32 = @as(f32, @floatCast(r.radius)) * k;
        switch (l.kind) {
            .group => unreachable,
            .rect => if (stroke != null and stroke.?.dash.len > 0) {
                raster.drawShape(target, .rect, lf, tf, wf, hf, radius, raster.paint(r.fill, 1), null);
                raster.strokePolyline(target, try raster.roundRectPath(ctx.arena, lf, tf, wf, hf, radius), true, stroke.?);
            } else raster.drawShape(target, .rect, lf, tf, wf, hf, radius, raster.paint(r.fill, 1), stroke),
            .ellipse => if (r.arc) |arc| {
                const cx = lf + wf / 2;
                const cy = tf + hf / 2;
                const curve = try raster.ellipsePath(ctx.arena, cx, cy, wf / 2, hf / 2, @floatCast(arc[0]), @floatCast(arc[1]));
                if (l.arc.?.pie) {
                    const slice = try ctx.arena.alloc([2]f32, curve.len + 1);
                    slice[0] = .{ cx, cy };
                    @memcpy(slice[1..], curve);
                    try raster.fillPolygon(ctx.gpa, target, slice, raster.paint(r.fill, 1));
                    if (stroke) |s| raster.strokePolyline(target, slice, true, s);
                } else if (stroke) |s| raster.strokePolyline(target, curve, false, s);
            } else if (stroke != null and stroke.?.dash.len > 0) {
                raster.drawShape(target, .ellipse, lf, tf, wf, hf, 0, raster.paint(r.fill, 1), null);
                raster.strokePolyline(target, try raster.ellipsePath(ctx.arena, lf + wf / 2, tf + hf / 2, wf / 2, hf / 2, 0, 360), true, stroke.?);
            } else raster.drawShape(target, .ellipse, lf, tf, wf, hf, 0, raster.paint(r.fill, 1), stroke),
            .polygon => {
                const pts = try ctx.scalePoints(r.points);
                if (l.closed) try raster.fillPolygon(ctx.gpa, target, pts, raster.paint(r.fill, 1));
                if (stroke) |s| try ctx.strokeWithArrows(target, l, pts, s);
            },
            .text => try text.draw(ctx.gpa, target, r.font.?, &r.layout.?, lf, tf, switch (l.alignment) {
                .left => .left,
                .center => .center,
                .right => .right,
                .justify => .justify,
            }, raster.paint(r.color, 1), if (r.stroke) |s| .{ .paint = raster.paint(s.color, 1), .width = @floatCast(s.width) } else null, k),
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

    /// A polygon's stroke; open polygons may end in arrowheads, and the line
    /// stops at the base of each head so it does not poke through the tip.
    fn strokeWithArrows(ctx: *Ctx, target: *raster.Bitmap, l: *const Layer, pts_in: []const [2]f32, s: raster.StrokeStyle) Failed!void {
        const a = try ctx.arrows(l, pts_in, s.width);
        raster.strokePolyline(target, a.pts, a.closed, s);
        for (a.heads) |h| if (h) |tri| try raster.fillPolygon(ctx.gpa, target, &tri, s.paint);
    }

    const Arrows = struct {
        /// The line to stroke (shortened where a head sits).
        pts: []const [2]f32,
        closed: bool,
        /// Triangles at the end and at the start.
        heads: [2]?[3][2]f32 = .{ null, null },
    };

    fn arrows(ctx: *Ctx, l: *const Layer, pts_in: []const [2]f32, width: f32) Allocator.Error!Arrows {
        const arrow = l.stroke.?.arrow;
        if (arrow == .none or l.closed or pts_in.len < 2) return .{ .pts = pts_in, .closed = l.closed };
        const pts = try ctx.arena.dupe([2]f32, pts_in);
        // `width` is in bitmap pixels (canvas pixels for a vector scene), so
        // the minimum head size of 6 by 4 canvas pixels is scaled to match.
        const k: f32 = @floatCast(ctx.k);
        const len = @max(6 * k, width * 4);
        const half = @max(4 * k, width * 2.2);
        const n = pts.len;
        var out: Arrows = .{ .pts = pts, .closed = false };
        if (arrow == .end or arrow == .both) {
            out.heads[0] = raster.arrowHead(pts[n - 1], pts[n - 2], len, half);
            pts[n - 1] = pullBack(pts[n - 1], pts[n - 2], len * 0.8);
        }
        if (arrow == .start or arrow == .both) {
            out.heads[1] = raster.arrowHead(pts[0], pts[1], len, half);
            pts[0] = pullBack(pts[0], pts[1], len * 0.8);
        }
        return out;
    }

    fn finishLayer(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved, tmp: *?raster.Bitmap) Failed!void {
        const t = if (tmp.*) |*t| t else return;
        var e = ctx.newEnv();
        for (l.effects) |eff| {
            switch (eff.kind) {
                .crop, .fade => {
                    const len: f32 = @floatCast(try ctx.num(&e, l, eff.length.?) * ctx.k);
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
        // A vector render takes the pixels as they are and places them
        // (rotated, translucent) itself.
        if (ctx.capture) |out| {
            out.* = t.*;
            tmp.* = null;
            return;
        }
        if (r.rotate != 0) {
            raster.compositeRotated(canvas, t, @floatCast(r.rotate * std.math.pi / 180), @floatCast(r.pivot[0] * ctx.k), @floatCast(r.pivot[1] * ctx.k), @floatCast(r.opacity));
            return;
        }
        raster.multiplyOpacity(t, @floatCast(r.opacity));
        raster.composite(canvas, t);
    }

    // ---------------------------------------------------------- vector output

    /// A group's children as items between begin and end items.
    fn emitGroup(ctx: *Ctx, sc: *vector.Scene, canvas: *raster.Bitmap, l: *const Layer, gi: usize, r: *const Resolved) Failed!void {
        const bb = ctx.groupBounds(l, r) orelse return;
        const mark = sc.items.items.len;
        errdefer sc.items.shrinkRetainingCapacity(mark);
        const n = try ctx.openFrame(sc, l, r, scratchRect(bb)) orelse return;
        try ctx.drawChildren(canvas, l, gi);
        try closeFrame(sc, n);
    }

    /// A layer as items: shapes, glyphs or an image, inside the groups of
    /// its effects, rotation and opacity.
    fn emitLayer(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved, bb: [4]f64) Failed!void {
        const mark = sc.items.items.len;
        errdefer sc.items.shrinkRetainingCapacity(mark);
        const n = try ctx.openFrame(sc, l, r, scratchRect(bb)) orelse return;
        switch (l.kind) {
            .group => unreachable,
            .rect, .ellipse => try ctx.emitBox(sc, l, r),
            .polygon => try ctx.emitPolygon(sc, l, r),
            .text => try ctx.emitText(sc, l, r),
            .image => try ctx.emitImage(sc, l, r),
        }
        try closeFrame(sc, n);
    }

    /// Opens the groups that the layer's crop and fade effects, its
    /// rotation and its opacity become, outermost first. `rect` is the
    /// layer's scratch bitmap, which the effects work on (see
    /// `raster.crop` and `raster.fade`). Returns how many groups were
    /// opened, null when the crop leaves nothing.
    fn openFrame(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved, rect: vector.IRect) Failed!?usize {
        var effects: std.ArrayList(vector.Begin) = .empty;
        var cur = rect;
        var e = ctx.newEnv();
        for (l.effects) |eff| {
            const len: f32 = @floatCast(try ctx.num(&e, l, eff.length.?));
            const side: raster.Side = switch (eff.side) {
                .top => .top,
                .bottom => .bottom,
                .left => .left,
                .right => .right,
            };
            if (eff.kind == .crop) {
                const g = vector.cropGeometry(cur, side, len, @floatCast(l.anchor.fx()), @floatCast(l.anchor.fy())) orelse continue;
                if (g.keep.w == 0 or g.keep.h == 0) return null;
                try effects.append(ctx.arena, .{ .crop = .{
                    .clip = rectCorners(g.keep),
                    .dx = @floatFromInt(g.to.x - g.keep.x),
                    .dy = @floatFromInt(g.to.y - g.keep.y),
                } });
                cur = g.to;
            } else if (len > 0) {
                try effects.append(ctx.arena, .{ .fade = .{ .side = side, .len = len, .rect = rectCorners(cur) } });
            }
        }
        var opened: usize = 0;
        if (r.rotate != 0 or r.opacity < 1) {
            try sc.add(.{ .begin = .{ .transform = .{
                .rotate = @floatCast(r.rotate),
                .pivot = .{ @floatCast(r.pivot[0]), @floatCast(r.pivot[1]) },
                .opacity = @floatCast(r.opacity),
            } } });
            opened += 1;
        }
        // The last effect works on the result of the ones before it.
        var i = effects.items.len;
        while (i > 0) : (i -= 1) {
            try sc.add(.{ .begin = effects.items[i - 1] });
            opened += 1;
        }
        return opened;
    }

    fn emitBox(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved) Failed!void {
        _ = ctx;
        var b = vector.PathBuilder.init(sc.allocator());
        const x: f32 = @floatCast(r.left);
        const y: f32 = @floatCast(r.top);
        const w: f32 = @floatCast(r.w);
        const h: f32 = @floatCast(r.h);
        var fill = true;
        if (l.kind == .rect) {
            try b.roundRect(x, y, w, h, @floatCast(r.radius));
        } else if (r.arc) |a| {
            // The slice is closed through the centre; a plain arc is only a curve.
            const pie = l.arc.?.pie;
            const cx = x + w / 2;
            const cy = y + h / 2;
            if (pie) try b.moveTo(.{ cx, cy });
            try b.arc(cx, cy, w / 2, h / 2, @floatCast(a[0]), @floatCast(a[1]), !pie);
            if (pie) try b.close();
            fill = pie;
        } else {
            try b.arc(x + w / 2, y + h / 2, w / 2, h / 2, 0, 360, true);
            try b.close();
        }
        const path = b.finish();
        if (fill) try addFill(sc, path, r.fill);
        try addStroke(sc, path, r);
    }

    fn emitPolygon(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved) Failed!void {
        var b = vector.PathBuilder.init(sc.allocator());
        if (l.closed and r.points.len >= 3) {
            try b.polyline(r.points, true);
            try addFill(sc, b.finish(), r.fill);
        }
        const s = r.stroke orelse return;
        if (s.width <= 0 or r.points.len < 2) return;
        const a = try ctx.arrows(l, r.points, @floatCast(s.width));
        var line = vector.PathBuilder.init(sc.allocator());
        try line.polyline(a.pts, a.closed);
        try addStroke(sc, line.finish(), r);
        for (a.heads) |head| if (head) |tri| {
            var hb = vector.PathBuilder.init(sc.allocator());
            try hb.polyline(&tri, true);
            try addFill(sc, hb.finish(), s.color);
        };
    }

    fn emitText(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved) Failed!void {
        _ = ctx;
        const alignment: text.Align = switch (l.alignment) {
            .left => .left,
            .center => .center,
            .right => .right,
            .justify => .justify,
        };
        const left: f32 = @floatCast(r.left);
        const top: f32 = @floatCast(r.top);
        // The outline pass comes first, for every glyph, then the fill.
        if (r.stroke) |s| if (s.width > 0 and s.color.a > 0) {
            var pass: GlyphPass = .{ .scene = sc, .color = s.color, .stroke = @floatCast(s.width * 2) };
            try text.walk(r.font.?, &r.layout.?, left, top, alignment, &pass, GlyphPass.add);
        };
        if (r.color.a == 0) return;
        var pass: GlyphPass = .{ .scene = sc, .color = r.color };
        try text.walk(r.font.?, &r.layout.?, left, top, alignment, &pass, GlyphPass.add);
    }

    fn emitImage(ctx: *Ctx, sc: *vector.Scene, l: *const Layer, r: *const Resolved) Failed!void {
        const img = r.image orelse return;
        const lf: f32 = @floatCast(r.left);
        const tf: f32 = @floatCast(r.top);
        const wf: f32 = @floatCast(r.w);
        const hf: f32 = @floatCast(r.h);
        var rect: [4]f32 = .{ lf, tf, wf, hf };
        if (l.fit != .fill) {
            const iw: f32 = @floatFromInt(img.w);
            const ih: f32 = @floatFromInt(img.h);
            const s = if (l.fit == .contain) @min(wf / iw, hf / ih) else @max(wf / iw, hf / ih);
            rect = .{ lf + (wf - iw * s) / 2, tf + (hf - ih * s) / 2, iw * s, ih * s };
        }
        if (rect[2] <= 0 or rect[3] <= 0) return;
        const path = (try project.normalize(ctx.arena, r.src)) orelse "";
        try sc.add(.{ .image = .{
            .image = img,
            .bytes = ctx.assets.vfs.read(path) orelse "",
            .rect = rect,
            .clip = .{ lf, tf, lf + wf, tf + hf },
            .smooth = l.smoothing == .bilinear,
        } });
    }

    /// A layer with a convolve effect: drawn as pixels at the scene's
    /// raster scale, placed with its rotation and opacity as vector groups.
    fn captureLayer(ctx: *Ctx, sc: *vector.Scene, canvas: *raster.Bitmap, l: *const Layer, r: *const Resolved, bb: [4]f64) Failed!void {
        var cap: ?raster.Bitmap = null;
        errdefer if (cap) |*b| b.deinit(ctx.gpa);
        var k: f64 = 1;
        {
            const saved = ctx.pixelMode(sc, bb[2] - bb[0], bb[3] - bb[1]);
            defer ctx.restoreMode(saved);
            k = ctx.k;
            ctx.capture = &cap;
            try ctx.paintLayer(canvas, l, r, bb);
        }
        try placeCaptured(sc, r, &cap, @floatCast(k));
    }

    /// The same for a group: its children are drawn as pixels.
    fn captureGroup(ctx: *Ctx, sc: *vector.Scene, canvas: *raster.Bitmap, l: *const Layer, gi: usize, r: *const Resolved) Failed!void {
        const bb = ctx.groupBounds(l, r) orelse return;
        var cap: ?raster.Bitmap = null;
        errdefer if (cap) |*b| b.deinit(ctx.gpa);
        var k: f64 = 1;
        {
            const saved = ctx.pixelMode(sc, bb[2] - bb[0], bb[3] - bb[1]);
            defer ctx.restoreMode(saved);
            k = ctx.k;
            var tmp: ?raster.Bitmap = try ctx.scratch(bb[0], bb[1], bb[2], bb[3]);
            defer if (tmp) |*t| t.deinit(ctx.gpa);
            try ctx.drawChildren(&tmp.?, l, gi);
            // Only the group's own bitmap is taken, not the children's.
            ctx.capture = &cap;
            try ctx.finishLayer(canvas, l, r, &tmp);
        }
        try placeCaptured(sc, r, &cap, @floatCast(k));
    }

    const Mode = struct { scene: ?*vector.Scene, k: f64, capture: ?*?raster.Bitmap };

    /// Switches to drawing pixels for an area of `w` x `h` canvas pixels, at
    /// the scene's raster scale (lowered for a large area to bound memory).
    fn pixelMode(ctx: *Ctx, sc: *const vector.Scene, w: f64, h: f64) Mode {
        const saved: Mode = .{ .scene = ctx.scene, .k = ctx.k, .capture = ctx.capture };
        const budget: f64 = 8_000_000;
        ctx.k = @min(sc.raster_scale, @sqrt(budget / @max(1, w * h)));
        ctx.scene = null;
        return saved;
    }

    fn restoreMode(ctx: *Ctx, m: Mode) void {
        ctx.scene = m.scene;
        ctx.k = m.k;
        ctx.capture = m.capture;
    }

    /// Adds the pixels `finishLayer` left, inside the layer's rotation and
    /// opacity.
    fn placeCaptured(sc: *vector.Scene, r: *const Resolved, cap: *?raster.Bitmap, k: f32) Failed!void {
        const b = cap.* orelse return;
        const wrapped = r.rotate != 0 or r.opacity < 1;
        if (wrapped) try sc.add(.{ .begin = .{ .transform = .{
            .rotate = @floatCast(r.rotate),
            .pivot = .{ @floatCast(r.pivot[0]), @floatCast(r.pivot[1]) },
            .opacity = @floatCast(r.opacity),
        } } });
        try sc.add(.{ .raster = .{ .bitmap = b, .scale = k } });
        cap.* = null;
        if (wrapped) try sc.add(.end);
    }
};

fn hasConvolve(l: *const Layer) bool {
    for (l.effects) |eff| switch (eff.kind) {
        .crop, .fade => {},
        else => return true,
    };
    return false;
}

/// The pixel rectangle `Ctx.scratch` makes for a canvas rectangle at scale 1.
fn scratchRect(bb: [4]f64) vector.IRect {
    const x0 = @floor(bb[0]);
    const y0 = @floor(bb[1]);
    const x1 = @max(x0 + 1, @ceil(bb[2]));
    const y1 = @max(y0 + 1, @ceil(bb[3]));
    return .{ .x = @intFromFloat(x0), .y = @intFromFloat(y0), .w = @intFromFloat(x1 - x0), .h = @intFromFloat(y1 - y0) };
}

fn rectCorners(r: vector.IRect) [4]f32 {
    return .{ @floatFromInt(r.x), @floatFromInt(r.y), @floatFromInt(@as(i64, r.x) + r.w), @floatFromInt(@as(i64, r.y) + r.h) };
}

fn closeFrame(sc: *vector.Scene, n: usize) Allocator.Error!void {
    for (0..n) |_| try sc.add(.end);
}

fn addFill(sc: *vector.Scene, path: vector.Path, color: Color) Allocator.Error!void {
    if (color.a == 0) return;
    try sc.add(.{ .fill = .{ .path = path, .color = color } });
}

/// The layer's stroke along `path`. Dash patterns are even in length (an
/// odd pattern repeats twice, as in SVG), and empty when they are all 0.
fn addStroke(sc: *vector.Scene, path: vector.Path, r: *const Resolved) Allocator.Error!void {
    const s = r.stroke orelse return;
    if (s.width <= 0 or s.color.a == 0) return;
    var period: f32 = 0;
    for (s.dash) |d| period += d;
    var dash: []const f32 = &.{};
    if (s.dash.len > 0 and period > 0.01) {
        dash = if (s.dash.len % 2 == 1) try std.mem.concat(sc.allocator(), f32, &.{ s.dash, s.dash }) else try sc.allocator().dupe(f32, s.dash);
    }
    try sc.add(.{ .stroke = .{ .path = path, .color = s.color, .width = @floatCast(s.width), .dash = dash } });
}

/// Adds every glyph of a text walk to the scene in one color.
const GlyphPass = struct {
    scene: *vector.Scene,
    color: Color,
    stroke: f32 = 0,

    fn add(p: *GlyphPass, g: text.Placed) Allocator.Error!void {
        try p.scene.add(.{ .glyph = .{
            .font = g.font,
            .gid = g.font.glyphIndex(g.cp),
            .x = g.x,
            .y = g.baseline,
            .scale = g.scale,
            .color = p.color,
            .stroke = p.stroke,
        } });
    }
};

/// `p` moved `d` pixels toward `toward` (not past it).
fn pullBack(p: [2]f32, toward: [2]f32, d: f32) [2]f32 {
    const dx = toward[0] - p[0];
    const dy = toward[1] - p[1];
    const l = @sqrt(dx * dx + dy * dy);
    if (l < 1e-6) return p;
    const k = @min(d, l) / l;
    return .{ p[0] + dx * k, p[1] + dy * k };
}

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

fn eqlOpt(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}

/// A field of a resolved layer. Positions are moved by `-off` into the
/// frame of the layer that reads them.
fn readField(r: *const Resolved, path: []const []const u8, off: [2]f64) ?Value {
    const eq = std.mem.eql;
    if (path.len == 2) {
        const a = path[0];
        const b = path[1];
        if (eq(u8, a, "bounds")) {
            const left = r.left - off[0];
            const top = r.top - off[1];
            const v: f64 = if (eq(u8, b, "left")) left else if (eq(u8, b, "top")) top else if (eq(u8, b, "right")) left + r.w else if (eq(u8, b, "bottom")) top + r.h else if (eq(u8, b, "w")) r.w else if (eq(u8, b, "h")) r.h else if (eq(u8, b, "cx")) left + r.w / 2 else if (eq(u8, b, "cy")) top + r.h / 2 else return null;
            return .{ .number = v };
        }
        if (eq(u8, a, "box")) {
            const i: usize = if (eq(u8, b, "x")) 0 else if (eq(u8, b, "y")) 1 else if (eq(u8, b, "w")) 2 else 3;
            return .{ .number = if (i < 2) r.box[i] - off[i] else r.box[i] };
        }
        if (eq(u8, a, "at")) return .{ .number = if (eq(u8, b, "x")) r.at[0] - off[0] else r.at[1] - off[1] };
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

/// What `render.date`, `render.time` and `render.now` read.
pub const Clock = struct {
    date: []const u8 = "1970-01-01",
    time: []const u8 = "00:00:00",
    now: []const u8 = "1970-01-01T00:00:00Z",
};

/// The render's clock: `opts.now` shifted by the UTC offset, or `opts.date`
/// at midnight when there is no (valid) instant.
pub fn clockFor(arena: Allocator, opts: Options, project_offset: f64) Allocator.Error!Clock {
    const at_midnight: Clock = .{ .date = opts.date, .now = try std.fmt.allocPrint(arena, "{s}T00:00:00Z", .{opts.date}) };
    const now = opts.now orelse return at_midnight;
    const p = bdate.parse(now) catch return at_midnight;
    if (p.kind != .datetime) return at_midnight;
    const offset = opts.utc_offset orelse project_offset;
    const local = bdate.localFromUtc(arena, now, offset) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadDate, error.TooLong => return at_midnight,
    };
    const utc = bdate.localFromUtc(arena, now, 0) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadDate, error.TooLong => return at_midnight,
    };
    return .{ .date = local.date, .time = local.time, .now = try std.fmt.allocPrint(arena, "{s}T{s}Z", .{ utc.date, utc.time }) };
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
        .counts = try arena.alloc(u32, d.layers.len),
        .consts = try arena.alloc(?Value, d.consts.len),
        .frames = try arena.alloc(?Frame, d.layers.len),
        .frame_busy = try arena.alloc(bool, d.layers.len),
        .group_iters = try arena.alloc(?[]Frame, d.layers.len),
        .partial = try arena.alloc(?[]Resolved, d.layers.len),
        .partial_done = try arena.alloc(usize, d.layers.len),
    };
    @memset(ctx.counts, 0);
    @memset(ctx.consts, null);
    @memset(ctx.frames, null);
    @memset(ctx.frame_busy, false);
    @memset(ctx.group_iters, null);
    @memset(ctx.partial, null);
    @memset(ctx.partial_done, 0);
    ctx.clock = try clockFor(arena, opts, set.utc_offset);

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
    var dpi: f64 = 0;
    var bleed: f64 = 0;
    if (d.dpi) |p| dpi = ctx.num(&e, null, p) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => 0,
    };
    if (d.bleed) |p| bleed = ctx.num(&e, null, p) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Failed => 0,
    };
    if (!(dpi >= 0 and dpi <= 10000)) dpi = 0;
    bleed = std.math.clamp(bleed, 0, @min(w, h) / 2);
    e = ctx.newEnv();
    // A vector render has no pixels of its own: it works in canvas pixels,
    // and the parts it draws as pixels use the scene's raster scale.
    ctx.scene = if (opts.dry) null else opts.vector;
    ctx.k = if (ctx.scene == null and opts.scale > 0 and std.math.isFinite(opts.scale)) opts.scale else 1;
    const pw = @max(1, @round(w * ctx.k));
    const ph = @max(1, @round(h * ctx.k));
    if (ctx.scene == null and (pw > limits.canvas_side or ph > limits.canvas_side)) {
        try ctx.report(.err, 5001, d.canvas_w.?.pos, null, try std.fmt.allocPrint(arena, "at {d}x the image would be {d} x {d} pixels; the limit is 10000 x 10000", .{ ctx.k, pw, ph }), "choose a lower resolution");
        return null;
    }
    var canvas = if (opts.dry or ctx.scene != null) try raster.Bitmap.init(gpa, 0, 0, 1, 1) else try raster.Bitmap.init(gpa, 0, 0, @intFromFloat(pw), @intFromFloat(ph));
    errdefer canvas.deinit(gpa);
    const filter_only = if (opts.filter) |f| f.mode == .only else false;
    if (d.background != null and !filter_only) {
        const bg = d.background.?;
        const v = ctx.eval(&e, null, bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => Value{ .color = Color.transparent },
        };
        if (ctx.scene) |sc| {
            sc.background = if (v.color.a > 0) v.color else null;
        } else canvas.fill(raster.paint(v.color, 1));
    }
    if (ctx.scene) |sc| {
        sc.width = @intFromFloat(w);
        sc.height = @intFromFloat(h);
        sc.dpi = dpi;
        sc.bleed = bleed;
    }

    for (d.layers, 0..) |*l, li| {
        if (l.parent != null) continue;
        drawOne(&ctx, &canvas, l, li) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => continue,
        };
    }
    if (ctx.drawn > limits.layers) try ctx.reportLayerLimit();
    canvas.dpi = dpi * ctx.k;
    canvas.bleed = bleed * ctx.k;
    canvas.scale = ctx.k;
    canvas.canvas_w = @intFromFloat(w);
    canvas.canvas_h = @intFromFloat(h);
    return canvas;
}

/// Renders card `index` of `set` into `scene` (a fresh one) as vectors, in
/// canvas pixels. Everything else about the render is as `renderCard`.
/// Returns false when nothing could be drawn (the reasons are in `diags`).
pub fn renderVector(gpa: Allocator, assets: *Assets, set: *const project.Set, index: usize, opts: Options, scene: *vector.Scene, diags: *diag.List) Allocator.Error!bool {
    var o = opts;
    o.vector = scene;
    var placeholder = (try renderCard(gpa, assets, set, index, o, diags)) orelse return false;
    placeholder.deinit(gpa);
    return true;
}

fn drawOne(ctx: *Ctx, canvas: *raster.Bitmap, l: *const Layer, li: usize) Failed!void {
    // Options.filter: hidden layers are evaluated and outlined, not drawn.
    var hide = false;
    const saved_inside = ctx.filter_inside;
    defer ctx.filter_inside = saved_inside;
    if (ctx.opts.filter) |f| {
        var listed = false;
        for (f.ids) |id| if (std.mem.eql(u8, id, l.id)) {
            listed = true;
            break;
        };
        switch (f.mode) {
            .except => hide = listed,
            .only => if (!ctx.filter_inside) {
                if (listed) ctx.filter_inside = true else hide = l.kind != .group;
            },
        }
    }
    if (l.repeat == null) {
        const r = try ctx.resolve(li);
        if (ctx.opts.outline) |o| try o.add(l, ctx.outline_instance, r);
        if (!r.visible or hide) return;
        if (l.kind == .group) return ctx.drawGroup(canvas, l, li, r);
        return ctx.drawLayer(canvas, l, r);
    }
    const list = try ctx.repeatInstances(li);
    if (l.kind == .group) {
        // Draw the layers inside once per iteration, in that iteration.
        const saved_instance = ctx.outline_instance;
        defer ctx.outline_instance = saved_instance;
        defer ctx.leaveIteration(li);
        for (list, 0..) |*r, i| {
            if (ctx.opts.outline) |o| try o.add(l, @intCast(i), r);
            if (!r.visible or hide) continue;
            ctx.enterIteration(li, i);
            ctx.outline_instance = @intCast(i);
            ctx.drawGroup(canvas, l, li, r) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Failed => {},
            };
        }
        return;
    }
    for (list, 0..) |*r, i| {
        if (ctx.opts.outline) |o| try o.add(l, @intCast(i), r);
        if (r.visible and !hide) ctx.drawLayer(canvas, l, r) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Failed => {},
        };
    }
}

const test_design =
    \\{
    \\  "format": 1,
    \\  "name": "t",
    \\  "canvas": { "width": 200, "height": 100, "background": "#FFFFFF" },
    \\  "layers": [
    \\    { "id": "g", "type": "group", "layers": [
    \\      { "id": "a", "type": "rect", "box": { "x": 10, "y": 10, "w": 60, "h": 40 }, "fill": "#FF0000", "radius": 6 },
    \\      { "id": "zig", "type": "polygon", "closed": false, "points": [[10, 90], [60, 60], [110, 90], [160, 60]], "stroke": { "color": "#0000FF", "width": 5 } }
    \\    ] },
    \\    { "id": "h", "type": "group", "opacity": 0.5, "layers": [
    \\      { "id": "b", "type": "ellipse", "box": { "x": 120, "y": 10, "w": 60, "h": 40 }, "fill": "#00FF00" }
    \\    ] }
    \\  ]
    \\}
;

fn testRender(gpa: Allocator, opts: Options) !raster.Bitmap {
    return (try testRenderDesign(gpa, test_design, opts, null)).?;
}

/// Renders the one card of `design`; null (and the first error code in
/// `code`) when the card is not drawn.
fn testRenderDesign(gpa: Allocator, design: []const u8, opts: Options, code: ?*u16) !?raster.Bitmap {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fs = project.MemFs.init(gpa);
    defer fs.deinit();
    try fs.put("t.design.json", design);
    try fs.put("t.cards.json", "{ \"format\": 1, \"design\": \"t.design.json\", \"cards\": [{ \"id\": \"one\" }] }");
    var diags = diag.List.init(arena);
    const proj = try project.load(arena, fs.vfs(), &diags);
    try std.testing.expectEqual(@as(usize, 0), diags.errorCount());
    var assets = Assets.init(gpa, fs.vfs());
    defer assets.deinit();
    const b = try renderCard(gpa, &assets, &proj.sets[0], 0, opts, &diags);
    if (code) |out| for (diags.items.items) |d| if (d.severity == .err) {
        out.* = d.code;
        break;
    };
    return b;
}

fn pixel(b: *const raster.Bitmap, x: usize, y: usize) [4]u16 {
    return b.px[(y * b.w + x) * 4 ..][0..4].*;
}

test "proxy render is the full render at a smaller size" {
    const gpa = std.testing.allocator;
    var full = try testRender(gpa, .{});
    defer full.deinit(gpa);
    var half = try testRender(gpa, .{ .scale = 0.5 });
    defer half.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 100), half.w);
    try std.testing.expectEqual(@as(u32, 50), half.h);
    try std.testing.expectEqual(@as(u32, 200), half.canvas_w);
    try std.testing.expectEqual(@as(u32, 100), half.canvas_h);
    // Each proxy pixel is close to the average of the 2 x 2 full pixels.
    var worst: f32 = 0;
    for (0..half.h) |y| for (0..half.w) |x| for (0..4) |ch| {
        var sum: f32 = 0;
        for ([_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |o| sum += @floatFromInt(pixel(&full, x * 2 + o[0], y * 2 + o[1])[ch]);
        const d = @abs(sum / 4 - @as(f32, @floatFromInt(pixel(&half, x, y)[ch])));
        // Edges differ a little (coverage is sampled at the coarser grid);
        // flat areas must match.
        worst = @max(worst, d);
    };
    try std.testing.expect(worst < 65535 * 0.35);
    try std.testing.expectEqual(pixel(&full, 40, 30), pixel(&half, 20, 15));
}

test "export at a larger scale is the full render at a larger size" {
    const gpa = std.testing.allocator;
    var full = try testRender(gpa, .{});
    defer full.deinit(gpa);
    var double = try testRender(gpa, .{ .scale = 2 });
    defer double.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 400), double.w);
    try std.testing.expectEqual(@as(u32, 200), double.h);
    try std.testing.expectEqual(@as(u32, 200), double.canvas_w);
    try std.testing.expectEqual(@as(f64, 2), double.scale);
    // Each 1x pixel is close to the average of the 2 x 2 pixels at 2x.
    var worst: f32 = 0;
    for (0..full.h) |y| for (0..full.w) |x| for (0..4) |ch| {
        var sum: f32 = 0;
        for ([_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |o| sum += @floatFromInt(pixel(&double, x * 2 + o[0], y * 2 + o[1])[ch]);
        worst = @max(worst, @abs(sum / 4 - @as(f32, @floatFromInt(pixel(&full, x, y)[ch]))));
    };
    try std.testing.expect(worst < 65535 * 0.35);
    // Flat areas match: the rect, the stroke's middle, the translucent ellipse.
    try std.testing.expectEqual(pixel(&full, 40, 30), pixel(&double, 80, 60));
    try std.testing.expectEqual(pixel(&full, 60, 60), pixel(&double, 120, 120));
    try std.testing.expectEqual(pixel(&full, 150, 30), pixel(&double, 300, 60));
}

test "export scale keeps the print size and scales text" {
    const gpa = std.testing.allocator;
    const design =
        \\{
        \\  "format": 1,
        \\  "name": "t",
        \\  "canvas": { "width": 100, "height": 50, "dpi": 300, "bleed": 4, "background": "#FFFFFF" },
        \\  "layers": [
        \\    { "id": "t", "type": "text", "text": "Hi", "at": { "x": 10, "y": 10 }, "size": 20, "color": "#000000" }
        \\  ]
        \\}
    ;
    var one = (try testRenderDesign(gpa, design, .{}, null)).?;
    defer one.deinit(gpa);
    var three = (try testRenderDesign(gpa, design, .{ .scale = 3 }, null)).?;
    defer three.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 300), three.w);
    try std.testing.expectEqual(@as(f64, 900), three.dpi);
    try std.testing.expectEqual(@as(f64, 12), three.bleed);
    // The ink of the text: three times as wide and tall, give or take the
    // pixel rounding at the edges.
    const ink = struct {
        fn box(b: *const raster.Bitmap) [4]usize {
            var r: [4]usize = .{ b.w, b.h, 0, 0 };
            for (0..b.h) |y| for (0..b.w) |x| if (pixel(b, x, y)[0] < 32768) {
                r = .{ @min(r[0], x), @min(r[1], y), @max(r[2], x + 1), @max(r[3], y + 1) };
            };
            return r;
        }
    }.box;
    const a = ink(&one);
    const b = ink(&three);
    try std.testing.expect(a[2] > a[0] and a[3] > a[1]);
    for (0..4) |i| {
        const want: f64 = @floatFromInt(a[i] * 3);
        const got: f64 = @floatFromInt(b[i]);
        try std.testing.expect(@abs(got - want) <= 4);
    }
}

test "export scale over the side limit is an error" {
    const gpa = std.testing.allocator;
    var code: u16 = 0;
    // 200 x 100 at 60x would be 12000 pixels wide.
    try std.testing.expect(try testRenderDesign(gpa, test_design, .{ .scale = 60 }, &code) == null);
    try std.testing.expectEqual(@as(u16, 5001), code);
    // 50x is exactly 10000 x 5000: allowed (checked without drawing).
    code = 0;
    var b = (try testRenderDesign(gpa, test_design, .{ .scale = 50, .dry = true }, &code)).?;
    defer b.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 0), code);
}

test "layer filter" {
    const gpa = std.testing.allocator;
    var only = try testRender(gpa, .{ .filter = .{ .ids = &.{"g"}, .mode = .only } });
    defer only.deinit(gpa);
    // No background, the group's rect is there, the other group is not.
    try std.testing.expectEqual([4]u16{ 0, 0, 0, 0 }, pixel(&only, 190, 5));
    try std.testing.expectEqual([4]u16{ 65535, 0, 0, 65535 }, pixel(&only, 40, 30));
    try std.testing.expectEqual(@as(u16, 0), pixel(&only, 150, 30)[3]);
    var except = try testRender(gpa, .{ .filter = .{ .ids = &.{"a"}, .mode = .except } });
    defer except.deinit(gpa);
    try std.testing.expectEqual([4]u16{ 65535, 65535, 65535, 65535 }, pixel(&except, 40, 30));
    try std.testing.expect(pixel(&except, 150, 30)[0] < 65535);
}

test "plain and translucent groups" {
    const gpa = std.testing.allocator;
    var b = try testRender(gpa, .{});
    defer b.deinit(gpa);
    try std.testing.expectEqual([4]u16{ 65535, 0, 0, 65535 }, pixel(&b, 40, 30));
    // Half-transparent green over white.
    const p = pixel(&b, 150, 30);
    try std.testing.expect(p[0] > 32000 and p[0] < 33500);
    try std.testing.expectEqual(@as(u16, 65535), p[1]);
}

/// A project with one design and one card, and the vector scene of the card.
/// The scene points into the assets (fonts, images), so they live together.
const VectorRig = struct {
    arena_state: std.heap.ArenaAllocator,
    fs: project.MemFs,
    assets: Assets,
    scene: vector.Scene,

    fn init(rig: *VectorRig, gpa: Allocator, design: []const u8) !void {
        return rig.initWithFiles(gpa, design, &.{});
    }

    /// `files` are more project files: path, content.
    fn initWithFiles(rig: *VectorRig, gpa: Allocator, design: []const u8, files: []const [2][]const u8) !void {
        rig.arena_state = std.heap.ArenaAllocator.init(gpa);
        rig.fs = project.MemFs.init(gpa);
        for (files) |f| try rig.fs.put(f[0], f[1]);
        try rig.fs.put("t.design.json", design);
        try rig.fs.put("t.cards.json", "{ \"format\": 1, \"design\": \"t.design.json\", \"cards\": [{ \"id\": \"one\" }] }");
        const arena = rig.arena_state.allocator();
        var diags = diag.List.init(arena);
        const proj = try project.load(arena, rig.fs.vfs(), &diags);
        try std.testing.expectEqual(@as(usize, 0), diags.errorCount());
        rig.assets = Assets.init(gpa, rig.fs.vfs());
        rig.scene = vector.Scene.init(gpa);
        try std.testing.expect(try renderVector(gpa, &rig.assets, &proj.sets[0], 0, .{}, &rig.scene, &diags));
    }

    fn deinit(rig: *VectorRig) void {
        rig.scene.deinit();
        rig.assets.deinit();
        rig.fs.deinit();
        rig.arena_state.deinit();
    }
};

test "vector scene of a plain design" {
    const gpa = std.testing.allocator;
    var rig: VectorRig = undefined;
    try rig.init(gpa, test_design);
    defer rig.deinit();
    const scene = &rig.scene;
    try std.testing.expectEqual(@as(u32, 200), scene.width);
    try std.testing.expect(scene.background.?.eql(Color.white));
    const items = scene.items.items;
    // Rect, polyline, then the translucent group around the ellipse.
    try std.testing.expectEqual(@as(usize, 5), items.len);
    try std.testing.expect(items[0] == .fill);
    // Move, four corner cubics joined by three lines, close (the fourth line is implied).
    try std.testing.expectEqual(@as(usize, 9), items[0].fill.path.cmds.len);
    try std.testing.expect(items[1] == .stroke);
    try std.testing.expectEqual(@as(f32, 5), items[1].stroke.width);
    try std.testing.expectEqual(@as(usize, 4), items[1].stroke.path.cmds.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), items[2].begin.transform.opacity, 0.0001);
    try std.testing.expect(items[3] == .fill);
    try std.testing.expect(items[4] == .end);
}

const shapes_design =
    \\{
    \\  "format": 1,
    \\  "name": "t",
    \\  "canvas": { "width": 300, "height": 200 },
    \\  "layers": [
    \\    { "id": "pie", "type": "ellipse", "box": { "x": 10, "y": 10, "w": 60, "h": 60 }, "fill": "#00FF00", "arc": { "start": 0, "end": 90 }, "stroke": { "color": "#000000", "width": 2 } },
    \\    { "id": "curve", "type": "ellipse", "box": { "x": 80, "y": 10, "w": 60, "h": 60 }, "fill": "#00FF00", "arc": { "start": 0, "end": 270, "pie": false }, "stroke": { "color": "#000000", "width": 2, "dash": [5, 3, 2] } },
    \\    { "id": "line", "type": "polygon", "closed": false, "points": [[10, 100], [100, 100], [100, 150]], "stroke": { "color": "#FF0000", "width": 4, "arrow": "both" } },
    \\    { "id": "turn", "type": "rect", "box": { "x": 150, "y": 100, "w": 60, "h": 40 }, "fill": "#0000FF", "rotate": 30, "opacity": 0.5 },
    \\    { "id": "cut", "type": "rect", "box": { "x": 10, "y": 20, "w": 100, "h": 50 }, "fill": "#FF00FF", "effects": [{ "type": "crop", "side": "left", "length": 20 }, { "type": "fade", "side": "right", "length": 30 }] },
    \\    { "id": "sharp", "type": "rect", "box": { "x": 200, "y": 20, "w": 40, "h": 40 }, "fill": "#FF8800", "rotate": 10, "effects": [{ "type": "sharpen" }] },
    \\    { "id": "words", "type": "text", "text": "Hi ⚄", "at": { "x": 20, "y": 160 }, "size": 24, "stroke": { "color": "#FFFFFF", "width": 2 } }
    \\  ]
    \\}
;

test "vector scene of arcs, dashes, arrows and effects" {
    const gpa = std.testing.allocator;
    var rig: VectorRig = undefined;
    try rig.init(gpa, shapes_design);
    defer rig.deinit();
    const scene = &rig.scene;
    const items = scene.items.items;
    // The pie is filled, closed through the centre; the curve is only stroked.
    try std.testing.expect(items[0] == .fill and items[0].fill.path.cmds[0] == .move and items[0].fill.path.cmds[items[0].fill.path.cmds.len - 1] == .close);
    try std.testing.expect(items[1] == .stroke);
    try std.testing.expect(items[2] == .stroke);
    try std.testing.expect(items[2].stroke.dash.len == 6);
    try std.testing.expectEqualSlices(f32, &.{ 5, 3, 2, 5, 3, 2 }, items[2].stroke.dash);
    // The polyline with two arrowheads: its stroke, then a triangle at each end.
    try std.testing.expect(items[3] == .stroke and items[4] == .fill and items[5] == .fill);
    try std.testing.expectEqual(@as(usize, 4), items[4].fill.path.cmds.len);
    // Rotation and opacity wrap the rectangle.
    const turn = items[6].begin.transform;
    try std.testing.expectEqual(@as(f32, 30), turn.rotate);
    try std.testing.expectEqual(@as(f32, 0.5), turn.opacity);
    try std.testing.expectEqual(@as(f32, 150), turn.pivot[0]);
    try std.testing.expect(items[7] == .fill and items[8] == .end);
    // The fade is outside the crop (it works on what the crop left): the
    // scratch bitmap is 104 x 54 at (8, 18); 20 pixels go from the left.
    const fade = items[9].begin.fade;
    try std.testing.expectEqual(raster.Side.right, fade.side);
    try std.testing.expectEqual(@as(f32, 30), fade.len);
    try std.testing.expectEqualSlices(f32, &.{ 8, 18, 92, 72 }, &fade.rect);
    const crop = items[10].begin.crop;
    try std.testing.expectEqualSlices(f32, &.{ 28, 18, 112, 72 }, &crop.clip);
    try std.testing.expectEqual(@as(f32, -20), crop.dx);
    try std.testing.expectEqual(@as(f32, 0), crop.dy);
    try std.testing.expect(items[11] == .fill and items[12] == .end and items[13] == .end);
    // The convolve effect cannot be a vector: pixels at the raster scale,
    // still inside the layer's rotation.
    try std.testing.expect(items[14].begin == .transform);
    const px = items[15].raster;
    try std.testing.expectEqual(@as(f32, 2), px.scale);
    try std.testing.expect(px.bitmap.w > 40 * 2);
    try std.testing.expect(items[16] == .end);
    // Text: every glyph's outline pass comes before any fill pass, and the
    // die face comes from the symbol font.
    var strokes: usize = 0;
    var fills: usize = 0;
    var seen_fill = false;
    var fonts: [2]?*const text.Font = .{ null, null };
    for (items[17..]) |it| {
        const g = it.glyph;
        if (g.stroke > 0) {
            try std.testing.expect(!seen_fill);
            try std.testing.expectEqual(@as(f32, 4), g.stroke);
            strokes += 1;
        } else {
            seen_fill = true;
            fills += 1;
        }
        if (fonts[0] == null) fonts[0] = g.font else if (fonts[0] != g.font) fonts[1] = g.font;
    }
    try std.testing.expectEqual(@as(usize, 3), strokes);
    try std.testing.expectEqual(@as(usize, 3), fills);
    try std.testing.expect(fonts[1] != null);
}

test "svg of a vector scene is well formed and repeatable" {
    const gpa = std.testing.allocator;
    var rig: VectorRig = undefined;
    try rig.init(gpa, shapes_design);
    defer rig.deinit();
    const scene = &rig.scene;
    const a = try @import("svg.zig").write(gpa, scene);
    defer gpa.free(a);
    const b = try @import("svg.zig").write(gpa, scene);
    defer gpa.free(b);
    try std.testing.expectEqualStrings(a, b);
    try @import("svg.zig").expectBalanced(a);
    try std.testing.expect(std.mem.indexOf(u8, a, "<image x=") != null);
    // Glyphs are defined once and used per placement.
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, a, "<use xlink:href=\"#g"));
    try std.testing.expect(std.mem.count(u8, a, "<path id=\"g") <= 3);
}

const media_design =
    \\{
    \\  "format": 1,
    \\  "name": "t",
    \\  "canvas": { "width": 200, "height": 100 },
    \\  "layers": [
    \\    { "id": "photo", "type": "image", "src": "p.png", "box": { "x": 10, "y": 10, "w": 80, "h": 40 }, "fit": "cover", "smoothing": "nearest" },
    \\    { "id": "pair", "type": "group", "opacity": 0.5, "rotate": 90, "layers": [
    \\      { "id": "a", "type": "rect", "box": { "x": 100, "y": 10, "w": 20, "h": 20 }, "fill": "#FF0000" },
    \\      { "id": "b", "type": "image", "src": "p.png", "box": { "x": 130, "y": 10, "w": 40, "h": 40 }, "fit": "contain" }
    \\    ] }
    \\  ]
    \\}
;

test "vector scene of images and groups" {
    const gpa = std.testing.allocator;
    var px = try raster.Bitmap.init(gpa, 0, 0, 2, 2);
    defer px.deinit(gpa);
    px.fill(raster.paint(.{ .r = 0, .g = 0, .b = 65535, .a = 65535 }, 1));
    const png = try raster.encodePng(gpa, &px, false);
    defer gpa.free(png);
    var rig: VectorRig = undefined;
    try rig.initWithFiles(gpa, media_design, &.{.{ "p.png", png }});
    defer rig.deinit();
    const items = rig.scene.items.items;
    try std.testing.expectEqual(@as(usize, 5), items.len);
    // Cover: the 2 x 2 image grows to 80 x 80, centred, clipped to the box;
    // the writers get the file to embed.
    const photo = items[0].image;
    try std.testing.expectEqualSlices(f32, &.{ 10, -10, 80, 80 }, &photo.rect);
    try std.testing.expectEqualSlices(f32, &.{ 10, 10, 90, 50 }, &photo.clip);
    try std.testing.expect(!photo.smooth);
    try std.testing.expectEqualSlices(u8, png, photo.bytes);
    // The group's opacity and rotation (about the centre of its bounds) wrap
    // its layers.
    const t = items[1].begin.transform;
    try std.testing.expectEqual(@as(f32, 90), t.rotate);
    try std.testing.expectEqual(@as(f32, 0.5), t.opacity);
    try std.testing.expectEqualSlices(f32, &.{ 135, 30 }, &t.pivot);
    try std.testing.expect(items[2] == .fill);
    try std.testing.expect(items[3].image.smooth);
    try std.testing.expectEqualSlices(f32, &.{ 130, 10, 40, 40 }, &items[3].image.rect);
    try std.testing.expect(items[4] == .end);
}
