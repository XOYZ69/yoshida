//! yoshida-server: serves the web editor and, when enabled, renders whole
//! sets on the server ("hybrid" mode for home labs).
//!
//!   GET  /api/capabilities   {"version", "channel", "format", "render", "max_cards", "max_body_mb",
//!                            "limits": {"layers", "repeat", "canvas", "image_mp", "set_cards"}} (null: unlimited)
//!   POST /api/render         {"files": {path: base64}, "set", "date", "now", "utc_offset", "format": "png"|"png16"|"pdf"|"svg"}
//!                            -> application/zip with <set>/<card id>.png (.svg for "svg"), application/pdf for
//!                            "pdf", or 422 with diagnostics
//!                            "now" is a UTC instant (YYYY-MM-DDTHH:MM:SSZ) and "utc_offset" the hours (-14 to 14)
//!                            that replace the project's; with neither "date" nor "now" the server's clock is used
//!                            Optional: "scale" (1 to 4, pixels per canvas pixel: of the whole image for png and
//!                            the image pdf, default 1; of the parts that stay pixels for svg and the vector pdf,
//!                            default 2), "vector" (bool, PDF only: pages drawn as vectors), "crop_marks" (bool,
//!                            PDF only), "compression" ("fast"|"default"|"smallest", PNG only)
//!                            "sheet": {"cols", "rows"} (PNG only) tiles the cards into sheets
//!                            (<set>.png, or <set>-1.png and so on) like `yoshida render --sheet`
//!                            An `x-yoshida-job: <hex id>` header makes its progress readable:
//!   GET  /api/render/progress?job=<hex id>
//!                            {"found", "stage", "done", "total"} (stage: receiving, loading,
//!                            rendering, packing, finished, failed)
//!   POST /api/telemetry/ping    optional, see telemetry.zig: one anonymous ping per editor session
//!   POST /api/telemetry/events  {"events": [{"k": "feature"|"export"|"error", "n": name}]} (advanced level)
//!   GET  /api/stats[?days=N]    only the stats the admin flagged public
//!   GET  /api/stats/page        the same public stats as a page, for people
//!   GET  /admin/telemetry       hidden admin page (404 unless an admin token is set)
//!   GET  /api/admin/stats       all stats, with `Authorization: Bearer <admin token>`
//!   PUT  /api/admin/public      {"public": [keys]} replaces the public flags (same auth)
//!   GET  /*                  static files from --web (the built editor, or the
//!                            site with the editor in editor/)
//!
//! The API also answers under /editor/api/, where the editor's relative
//! "api/..." calls land when it is served from /editor/.

const std = @import("std");
const y = @import("yoshida");
const zip = @import("zip.zig");
const tel = @import("telemetry.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Config = struct {
    host: []const u8 = "0.0.0.0",
    port: u16 = 8080,
    web: []const u8 = "web",
    render: bool = true,
    max_cards: usize = 1000,
    max_body_mb: usize = 200,
    threads: usize = 0,
    telemetry: tel.Config = .{},
    store: ?*tel.Store = null,
};

const usage =
    \\Usage: yoshida-server [--host ADDR] [--port N] [--web DIR] [--no-render]
    \\                      [--max-cards N] [--max-body-mb N] [--threads N]
    \\                      [--no-telemetry] [--telemetry-dir DIR] [--telemetry-default off|basic|advanced]
    \\                      [--telemetry-force off|basic] [--telemetry-retention-days N|infinite]
    \\                      [--telemetry-trust-proxy] [--admin-token TOKEN]
    \\
    \\Environment variables YOSHIDA_HOST, YOSHIDA_PORT, YOSHIDA_WEB, YOSHIDA_RENDER (0/1),
    \\YOSHIDA_MAX_CARDS, YOSHIDA_MAX_BODY_MB and YOSHIDA_THREADS set the same options, and
    \\YOSHIDA_TELEMETRY (0/1), YOSHIDA_TELEMETRY_DIR, YOSHIDA_TELEMETRY_DEFAULT,
    \\YOSHIDA_TELEMETRY_FORCE, YOSHIDA_TELEMETRY_RETENTION_DAYS, YOSHIDA_TELEMETRY_TRUST_PROXY (0/1)
    \\and YOSHIDA_ADMIN_TOKEN the telemetry ones. Prefer the environment for the admin token.
    \\
    \\YOSHIDA_MAX_LAYERS (default 500), YOSHIDA_MAX_REPEAT (1000), YOSHIDA_MAX_CANVAS (10000),
    \\YOSHIDA_MAX_IMAGE_MP (50) and YOSHIDA_MAX_SET_CARDS (10000) raise the limits of a design;
    \\each takes a whole number or the word unlimited. The editor served by this server follows them.
    \\
;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    var cfg: Config = .{};
    const env = init.environ_map;
    if (env.get("YOSHIDA_HOST")) |v| cfg.host = v;
    if (env.get("YOSHIDA_PORT")) |v| cfg.port = std.fmt.parseInt(u16, v, 10) catch cfg.port;
    if (env.get("YOSHIDA_WEB")) |v| cfg.web = v;
    if (env.get("YOSHIDA_RENDER")) |v| cfg.render = !std.mem.eql(u8, v, "0");
    if (env.get("YOSHIDA_MAX_CARDS")) |v| cfg.max_cards = std.fmt.parseInt(usize, v, 10) catch cfg.max_cards;
    if (env.get("YOSHIDA_MAX_BODY_MB")) |v| cfg.max_body_mb = std.fmt.parseInt(usize, v, 10) catch cfg.max_body_mb;
    if (env.get("YOSHIDA_THREADS")) |v| cfg.threads = std.fmt.parseInt(usize, v, 10) catch 0;

    // The core's limits (layers per card and so on), see core/limits.zig.
    for (y.limits.settings) |setting| {
        const text = env.get(setting.env) orelse continue;
        const v = y.limits.parse(setting, text) catch {
            var buf: [320]u8 = undefined;
            std.debug.print("{s}\n", .{y.limits.invalidMessage(&buf, setting, text)});
            return 2;
        } orelse continue;
        y.limits.set(setting, v);
    }

    var bad_option: ?[]const u8 = null;
    const tc = &cfg.telemetry;
    if (env.get("YOSHIDA_TELEMETRY")) |v| tc.enabled = !std.mem.eql(u8, v, "0");
    if (env.get("YOSHIDA_TELEMETRY_DIR")) |v| tc.dir = v;
    if (env.get("YOSHIDA_TELEMETRY_DEFAULT")) |v| setTelemetryOption(tc, "default", v, &bad_option);
    if (env.get("YOSHIDA_TELEMETRY_FORCE")) |v| setTelemetryOption(tc, "force", v, &bad_option);
    if (env.get("YOSHIDA_TELEMETRY_RETENTION_DAYS")) |v| setTelemetryOption(tc, "retention", v, &bad_option);
    if (env.get("YOSHIDA_TELEMETRY_TRUST_PROXY")) |v| tc.trust_proxy = std.mem.eql(u8, v, "1");
    // An empty value (the line left blank in an env file) means no token.
    if (env.get("YOSHIDA_ADMIN_TOKEN")) |v| if (v.len > 0) {
        tc.admin_token = v;
    };

    const argv = try init.minimal.args.toSlice(arena);
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--no-render")) {
            cfg.render = false;
            continue;
        }
        if (std.mem.eql(u8, a, "--no-telemetry")) {
            tc.enabled = false;
            continue;
        }
        if (std.mem.eql(u8, a, "--telemetry-trust-proxy")) {
            tc.trust_proxy = true;
            continue;
        }
        if (std.mem.eql(u8, a, "--help") or i + 1 >= argv.len) {
            std.debug.print(usage, .{});
            return if (std.mem.eql(u8, a, "--help")) 0 else 2;
        }
        i += 1;
        const v = argv[i];
        if (std.mem.eql(u8, a, "--host")) cfg.host = v else if (std.mem.eql(u8, a, "--port")) cfg.port = try std.fmt.parseInt(u16, v, 10) else if (std.mem.eql(u8, a, "--web")) cfg.web = v else if (std.mem.eql(u8, a, "--max-cards")) cfg.max_cards = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--max-body-mb")) cfg.max_body_mb = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--threads")) cfg.threads = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--telemetry-dir")) tc.dir = v else if (std.mem.eql(u8, a, "--telemetry-default")) setTelemetryOption(tc, "default", v, &bad_option) else if (std.mem.eql(u8, a, "--telemetry-force")) setTelemetryOption(tc, "force", v, &bad_option) else if (std.mem.eql(u8, a, "--telemetry-retention-days")) setTelemetryOption(tc, "retention", v, &bad_option) else if (std.mem.eql(u8, a, "--admin-token")) tc.admin_token = v else {
            std.debug.print("unknown option {s}\n\n" ++ usage, .{a});
            return 2;
        }
    }
    if (cfg.threads == 0) cfg.threads = @max(1, std.Thread.getCpuCount() catch 1);
    if (bad_option) |msg| {
        std.debug.print("{s}\n", .{msg});
        return 2;
    }
    if (tc.admin_token) |t| if (t.len < tel.min_token_len) {
        std.debug.print("telemetry: the admin token needs at least {d} characters; the admin page is disabled\n", .{tel.min_token_len});
        tc.admin_token = null;
    };
    if (tc.force != null and !tc.enabled) tc.force = null;

    const addr = try Io.net.IpAddress.parse(cfg.host, cfg.port);
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.debug.print("yoshida-server {s} listening on http://{s}:{d} (web: {s}, server render: {s}, {d} threads)\n", .{
        y.version, cfg.host, cfg.port, cfg.web, if (cfg.render) "on" else "off", cfg.threads,
    });

    for (y.limits.settings) |setting| {
        const now = y.limits.shown(setting, y.limits.current);
        if (now != null and now.? == y.limits.shown(setting, y.limits.defaults).?) continue;
        if (now) |n| {
            std.debug.print("limits: {d} {s} ({s})\n", .{ n, setting.unit, setting.env });
        } else {
            std.debug.print("limits: unlimited {s} ({s})\n", .{ setting.unit, setting.env });
        }
    }

    var store = tel.Store.init(init.gpa, io, cfg.telemetry);
    defer store.deinit();
    var group: Io.Group = .init;
    defer group.cancel(io);
    if (cfg.telemetry.enabled) {
        store.load(unixNow(io));
        cfg.store = &store;
        std.debug.print("telemetry: default {s}{s}, keeping {s}, data in {s}{s}\n", .{
            cfg.telemetry.default_level.name(),
            if (cfg.telemetry.force) |f| (if (f == .off) ", forced off" else ", forced basic") else "",
            if (cfg.telemetry.retention_days) |d| std.fmt.allocPrint(arena, "{d} days", .{d}) catch "?" else "all days",
            if (store.persist) cfg.telemetry.dir else "memory only",
            if (cfg.telemetry.admin_token != null) ", admin page on" else "",
        });
        group.concurrent(io, flushLoop, .{ io, &store }) catch {};
    }
    while (true) {
        const stream = server.accept(io) catch |e| {
            std.debug.print("accept failed: {s}\n", .{@errorName(e)});
            continue;
        };
        group.concurrent(io, serveConnection, .{ io, init.gpa, &cfg, stream }) catch {
            serveConnection(io, init.gpa, &cfg, stream);
        };
    }
}

/// The client address as bytes: used for the daily unique hash and nothing else.
fn peerBytes(stream: Io.net.Stream, buf: *[16]u8) []const u8 {
    switch (stream.socket.address) {
        .ip4 => |a| {
            buf[0..4].* = a.bytes;
            return buf[0..4];
        },
        .ip6 => |a| {
            buf.* = a.bytes;
            return buf[0..16];
        },
    }
}

fn unixNow(io: Io) i64 {
    return @intCast(@divFloor(Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s));
}

fn flushLoop(io: Io, store: *tel.Store) void {
    while (true) {
        io.sleep(.fromSeconds(15), .awake) catch return;
        store.flush(unixNow(io));
    }
}

fn setTelemetryOption(tc: *tel.Config, which: []const u8, v: []const u8, bad: *?[]const u8) void {
    if (std.mem.eql(u8, which, "default")) {
        tc.default_level = tel.Level.parse(v) orelse {
            bad.* = "telemetry: the default level must be off, basic or advanced";
            return;
        };
    } else if (std.mem.eql(u8, which, "force")) {
        if (v.len == 0 or std.ascii.eqlIgnoreCase(v, "none")) {
            tc.force = null;
        } else tc.force = tel.parseForce(v) orelse {
            bad.* = "telemetry: a forced level can only be off or basic (the server may take data away, never add)";
            return;
        };
    } else {
        tc.retention_days = tel.parseRetention(v) orelse {
            bad.* = "telemetry: the retention must be a number of days or \"infinite\"";
            return;
        };
    }
}

fn serveConnection(io: Io, gpa: Allocator, cfg: *const Config, stream: Io.net.Stream) void {
    defer stream.close(io);
    var peer_buf: [16]u8 = undefined;
    const peer = peerBytes(stream, &peer_buf);
    var in_buf: [16 * 1024]u8 = undefined;
    var out_buf: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &in_buf);
    var writer = stream.writer(io, &out_buf);
    var http = std.http.Server.init(&reader.interface, &writer.interface);
    while (true) {
        var req = http.receiveHead() catch return;
        handle(io, gpa, cfg, &req, peer) catch |e| {
            std.debug.print("{s} {s}: {s}\n", .{ @tagName(req.head.method), req.head.target, @errorName(e) });
            return;
        };
        if (!req.head.keep_alive) return;
    }
}

fn handle(io: Io, gpa: Allocator, cfg: *const Config, req: *std.http.Server.Request, peer: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const target = req.head.target;
    const full_path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;
    const path = if (std.mem.startsWith(u8, full_path, "/editor/api/")) full_path["/editor".len..] else full_path;

    if (std.mem.eql(u8, path, "/api/capabilities")) {
        const body = try capabilities(arena, cfg);
        return req.respond(body, .{ .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
    }
    if (std.mem.eql(u8, path, "/api/render/progress")) return progressResponse(arena, req, target);
    if (std.mem.eql(u8, path, "/api/render")) {
        if (req.head.method != .POST) return jsonError(req, .method_not_allowed, "use POST");
        if (!cfg.render) return jsonError(req, .forbidden, "server rendering is disabled on this server");
        return renderSet(io, gpa, arena, cfg, req);
    }
    if (std.mem.startsWith(u8, path, "/api/telemetry/") or std.mem.eql(u8, path, "/api/stats") or std.mem.eql(u8, path, "/api/stats/page") or std.mem.startsWith(u8, path, "/api/admin/") or std.mem.eql(u8, path, "/admin/telemetry")) {
        if (try telemetryRoute(io, arena, cfg, req, path, target, peer)) return;
    }
    if (std.mem.startsWith(u8, path, "/api/")) return jsonError(req, .not_found, "unknown API endpoint");
    if (req.head.method != .GET and req.head.method != .HEAD) return jsonError(req, .method_not_allowed, "method not allowed");
    return serveStatic(io, arena, cfg, req, path);
}

fn jsonError(req: *std.http.Server.Request, status: std.http.Status, msg: []const u8) !void {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try w.writeAll("{\"error\":");
    try y.json.writeString(&w, msg);
    try w.writeAll("}");
    return req.respond(w.buffered(), .{ .status = status, .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
}

fn contentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    const map = .{
        .{ ".html", "text/html; charset=utf-8" }, .{ ".js", "text/javascript" },
        .{ ".css", "text/css" },                  .{ ".wasm", "application/wasm" },
        .{ ".json", "application/json" },         .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },                .{ ".jpeg", "image/jpeg" },
        .{ ".svg", "image/svg+xml" },             .{ ".csv", "text/csv" },
        .{ ".ttf", "font/ttf" },                  .{ ".otf", "font/otf" },
        .{ ".woff2", "font/woff2" },              .{ ".webp", "image/webp" },
        .{ ".xml", "application/xml" },           .{ ".ico", "image/x-icon" },
    };
    inline for (map) |m| if (std.ascii.eqlIgnoreCase(ext, m[0])) return m[1];
    return "application/octet-stream";
}

fn serveStatic(io: Io, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request, url_path: []const u8) !void {
    var rel = std.mem.trimStart(u8, url_path, "/");
    if (rel.len == 0 or rel[rel.len - 1] == '/') rel = try std.mem.concat(arena, u8, &.{ rel, "index.html" });
    // Percent-decoding is limited to spaces and '!' (used by the example font names).
    const decoded = try std.mem.replaceOwned(u8, arena, try std.mem.replaceOwned(u8, arena, rel, "%20", " "), "%21", "!");
    const clean = (try y.project.normalize(arena, decoded)) orelse return notFound(io, arena, cfg, req);
    const full = try std.fs.path.join(arena, &.{ cfg.web, clean });
    const data = Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(64 * 1024 * 1024)) catch {
        // A folder without its trailing slash ("/editor"): redirect, so the
        // relative URLs in its index.html resolve inside the folder.
        if (url_path[url_path.len - 1] != '/') {
            const index = try std.fs.path.join(arena, &.{ full, "index.html" });
            if (Io.Dir.cwd().readFileAlloc(io, index, arena, .limited(64 * 1024 * 1024))) |_| {
                const location = try std.mem.concat(arena, u8, &.{ url_path, "/" });
                return req.respond("", .{ .status = .moved_permanently, .extra_headers = &.{.{ .name = "location", .value = location }} });
            } else |_| {}
        }
        return notFound(io, arena, cfg, req);
    };
    return req.respond(data, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = contentType(clean) },
        .{ .name = "cache-control", .value = "no-cache" },
    } });
}

/// The site's own 404.html when --web has one (Zola writes it), else a JSON error.
fn notFound(io: Io, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request) !void {
    const path = try std.fs.path.join(arena, &.{ cfg.web, "404.html" });
    const page = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1024 * 1024)) catch {
        return jsonError(req, .not_found, "not found");
    };
    return req.respond(page, .{ .status = .not_found, .extra_headers = &.{.{ .name = "content-type", .value = "text/html; charset=utf-8" }} });
}

// ---------------------------------------------------------------- render progress

/// What a render request is doing, for GET /api/render/progress.
const Stage = enum(u8) { free, receiving, loading, rendering, packing, finished, failed };

/// One render request the editor can follow. Slots are reused once their
/// request is over; a request that finds no free slot renders without one.
const Progress = struct {
    id: std.atomic.Value(u64) = .init(0),
    stage: std.atomic.Value(u8) = .init(@intFromEnum(Stage.free)),
    done: std.atomic.Value(usize) = .init(0),
    total: std.atomic.Value(usize) = .init(0),

    fn set(p: *Progress, stage: Stage) void {
        p.stage.store(@intFromEnum(stage), .release);
    }
};

var progress_slots: [32]Progress = @splat(.{});
/// Numbers the render requests in the log.
var request_count: std.atomic.Value(u32) = .init(0);

fn claimProgress(id: u64) ?*Progress {
    if (id == 0) return null;
    for (&progress_slots) |*p| {
        const stage: Stage = @enumFromInt(p.stage.load(.acquire));
        if (stage != .free and stage != .finished and stage != .failed) continue;
        const old = p.id.load(.acquire);
        if (p.id.cmpxchgStrong(old, id, .acq_rel, .acquire) != null) continue;
        p.done.store(0, .release);
        p.total.store(0, .release);
        p.set(.receiving);
        return p;
    }
    return null;
}

fn findProgress(id: u64) ?*Progress {
    if (id == 0) return null;
    for (&progress_slots) |*p| {
        if (p.id.load(.acquire) == id and p.stage.load(.acquire) != @intFromEnum(Stage.free)) return p;
    }
    return null;
}

fn jobHeader(req: *std.http.Server.Request) u64 {
    var it = req.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "x-yoshida-job"))
            return std.fmt.parseInt(u64, std.mem.trim(u8, h.value, " "), 16) catch 0;
    }
    return 0;
}

fn progressResponse(arena: Allocator, req: *std.http.Server.Request, target: []const u8) !void {
    const query = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[q + 1 ..] else "";
    var id: u64 = 0;
    var parts = std.mem.splitScalar(u8, query, '&');
    while (parts.next()) |kv| {
        if (std.mem.startsWith(u8, kv, "job=")) id = std.fmt.parseInt(u64, kv[4..], 16) catch 0;
    }
    const body = if (findProgress(id)) |p|
        try std.fmt.allocPrint(arena, "{{\"found\":true,\"stage\":\"{s}\",\"done\":{d},\"total\":{d}}}", .{
            @tagName(@as(Stage, @enumFromInt(p.stage.load(.acquire)))), p.done.load(.acquire), p.total.load(.acquire),
        })
    else
        "{\"found\":false}";
    return req.respond(body, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "cache-control", .value = "no-store" },
    } });
}

fn mb(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024 * 1024);
}

const Job = struct {
    gpa: Allocator,
    fs: *y.project.MemFs,
    set: *const y.project.Set,
    date: []const u8,
    now: ?[]const u8,
    utc_offset: ?f64,
    sixteen: bool,
    pdf: bool = false,
    /// Bitmap pixels per canvas pixel (the request's "scale").
    scale: f64 = 1,
    crop_marks: bool = false,
    compression: y.raster.Compression = .default,
    /// SVG files in `pngs`, instead of PNG.
    svg: bool = false,
    /// Pixels per canvas pixel for the parts of a vector file that are pixels.
    raster_scale: f32 = 2,
    /// Cards with index % stride == offset belong to this job.
    offset: usize,
    stride: usize,
    pngs: [][]u8,
    pages: []?y.pdf.Page = &.{},
    diags: y.diag.List,
    failed: bool = false,
    progress: ?*Progress = null,
    /// Request number, for the log.
    n: u32 = 0,

    fn run(job: *Job) void {
        var assets = y.render.Assets.init(job.gpa, job.fs.vfs());
        defer assets.deinit();
        var i = job.offset;
        while (i < job.set.cards.len) : (i += job.stride) {
            defer job.cardDone();
            if (job.svg) {
                job.runSvg(&assets, i) catch {
                    job.failed = true;
                    return;
                };
                continue;
            }
            var bmp = (y.render.renderCard(job.gpa, &assets, job.set, i, .{ .date = job.date, .now = job.now, .utc_offset = job.utc_offset, .scale = job.scale }, &job.diags) catch {
                job.failed = true;
                return;
            }) orelse continue;
            defer bmp.deinit(job.gpa);
            if (job.pdf) {
                if (job.crop_marks) {
                    const marked = y.raster.withCropMarks(job.gpa, &bmp) catch {
                        job.failed = true;
                        return;
                    };
                    bmp.deinit(job.gpa);
                    bmp = marked;
                }
                job.pages[i] = y.pdf.Page.init(job.gpa, &bmp) catch {
                    job.failed = true;
                    return;
                };
                continue;
            }
            job.pngs[i] = y.raster.encodePngLevel(job.gpa, &bmp, job.sixteen, job.compression) catch {
                job.failed = true;
                return;
            };
        }
    }

    fn runSvg(job: *Job, assets: *y.render.Assets, i: usize) !void {
        var scene = y.vector.Scene.init(job.gpa);
        defer scene.deinit();
        scene.raster_scale = job.raster_scale;
        if (!try y.render.renderVector(job.gpa, assets, job.set, i, .{ .date = job.date, .now = job.now, .utc_offset = job.utc_offset }, &scene, &job.diags)) return;
        job.pngs[i] = try y.svg.write(job.gpa, &scene);
    }

    /// Counts a finished card; the log gets a line at every 10%.
    fn cardDone(job: *Job) void {
        const p = job.progress orelse return;
        const total = job.set.cards.len;
        const done = p.done.fetchAdd(1, .acq_rel) + 1;
        if (total >= 20 and done * 10 / total != (done - 1) * 10 / total)
            std.debug.print("render #{d}: {d}/{d} cards\n", .{ job.n, done, total });
    }
};

fn renderSet(io: Io, gpa: Allocator, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request) !void {
    const req_n = request_count.fetchAdd(1, .monotonic) + 1;
    const started = Io.Timestamp.now(io, .awake);
    // Headers must be read before the body.
    const progress = claimProgress(jobHeader(req));
    var ok = false;
    defer if (progress) |p| p.set(if (ok) .finished else .failed);
    const max_body = cfg.max_body_mb * 1024 * 1024;
    std.debug.print("render #{d}: receiving {d:.1} MB\n", .{ req_n, mb(req.head.content_length orelse 0) });
    if (req.head.content_length) |len| if (len > max_body) {
        std.debug.print("render #{d}: refused, the body is over --max-body-mb {d}\n", .{ req_n, cfg.max_body_mb });
        return jsonError(req, .payload_too_large, "request body is too large");
    };
    var body_buf: [16 * 1024]u8 = undefined;
    const body_reader = req.readerExpectNone(&body_buf);
    const body = body_reader.allocRemaining(arena, .limited(max_body)) catch return jsonError(req, .bad_request, "could not read the request body");
    if (progress) |p| p.set(.loading);

    const doc = switch (try y.json.parse(arena, body)) {
        .ok => |n| n,
        .err => |e| return jsonError(req, .bad_request, try std.fmt.allocPrint(arena, "invalid JSON: {s}", .{e.message})),
    };
    const files = doc.get("files") orelse return jsonError(req, .bad_request, "missing \"files\"");
    if (files.data != .object) return jsonError(req, .bad_request, "\"files\" must be an object of path to base64");
    const set_name = if (doc.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
    const date = if (doc.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
    var now: ?[]const u8 = null;
    if (doc.get("now")) |n| {
        if (n.data != .string or !validUtcInstant(n.data.string)) return jsonError(req, .bad_request, "\"now\" must be a UTC instant like 2026-10-15T09:30:00Z");
        now = n.data.string;
    }
    var utc_offset: ?f64 = null;
    if (doc.get("utc_offset")) |o| {
        if (o.data != .number or !(o.data.number >= -14 and o.data.number <= 14)) return jsonError(req, .bad_request, "\"utc_offset\" must be a number of hours from -14 to 14");
        utc_offset = o.data.number;
    }
    // Neither date nor now: the render happens at the server's current UTC instant.
    if (now == null and doc.get("date") == null) now = try utcNow(io, arena);
    const sixteen = if (doc.get("format")) |f| (f.data == .string and std.mem.eql(u8, f.data.string, "png16")) else false;
    const want_pdf = if (doc.get("format")) |f| (f.data == .string and std.mem.eql(u8, f.data.string, "pdf")) else false;
    const want_svg = if (doc.get("format")) |f| (f.data == .string and std.mem.eql(u8, f.data.string, "svg")) else false;
    var want_vector = false;
    if (doc.get("vector")) |v| {
        if (v.data != .bool) return jsonError(req, .bad_request, "\"vector\" must be true or false");
        if (v.data.bool and !want_pdf) return jsonError(req, .bad_request, "\"vector\" goes with \"format\": \"pdf\" (\"svg\" is always a vector file)");
        want_vector = v.data.bool;
    }
    var crop_marks = false;
    if (doc.get("crop_marks")) |c| {
        if (c.data != .bool) return jsonError(req, .bad_request, "\"crop_marks\" must be true or false");
        crop_marks = c.data.bool;
    }
    // "sheet": {"cols", "rows"}: the cards tiled into PNG sheets instead of one file each.
    var sheet_grid: ?[2]u32 = null;
    if (doc.get("sheet")) |sh| {
        const cols = if (sh.get("cols")) |c| (if (c.data == .number) c.data.number else 0) else 0;
        const rows = if (sh.get("rows")) |r| (if (r.data == .number) r.data.number else 0) else 0;
        if (sh.data != .object or !y.raster.Sheet.validGrid(cols, rows)) return jsonError(req, .bad_request, "\"sheet\" must be {\"cols\": 1 to 100, \"rows\": 1 to 100}");
        if (want_pdf or want_svg or sixteen) return jsonError(req, .bad_request, "\"sheet\" goes with \"format\": \"png\"");
        if (crop_marks) return jsonError(req, .bad_request, "\"sheet\" cannot have crop marks");
        sheet_grid = .{ @intFromFloat(cols), @intFromFloat(rows) };
    }
    var scale: ?f64 = null;
    if (doc.get("scale")) |k| {
        if (k.data != .number or !(k.data.number >= 1 and k.data.number <= 4)) return jsonError(req, .bad_request, "\"scale\" must be a number from 1 to 4");
        scale = k.data.number;
    }
    // Vector files (svg, vector pdf) use the scale for the parts that stay
    // pixels: 2 when it is not given.
    const raster_scale: f32 = @floatCast(scale orelse 2);
    var compression: y.raster.Compression = .default;
    if (doc.get("compression")) |c| {
        const level = if (c.data == .string) std.meta.stringToEnum(y.raster.Compression, c.data.string) else null;
        compression = level orelse return jsonError(req, .bad_request, "\"compression\" must be \"fast\", \"default\" or \"smallest\"");
    }

    var fs = y.project.MemFs.init(gpa);
    defer fs.deinit();
    const dec = std.base64.standard.Decoder;
    for (files.data.object) |f| {
        if (f.value.data != .string) return jsonError(req, .bad_request, "file contents must be base64 strings");
        const clean = (try y.project.normalize(arena, f.key)) orelse return jsonError(req, .bad_request, "file path outside the project");
        const n = dec.calcSizeForSlice(f.value.data.string) catch return jsonError(req, .bad_request, "invalid base64");
        const bytes = try arena.alloc(u8, n);
        dec.decode(bytes, f.value.data.string) catch return jsonError(req, .bad_request, "invalid base64");
        try fs.put(clean, bytes);
    }

    var diags = y.diag.List.init(arena);
    const proj = try y.project.load(arena, fs.vfs(), &diags);
    const set = proj.findSet(set_name) orelse {
        std.debug.print("render #{d}: unknown set '{s}'\n", .{ req_n, set_name });
        return jsonError(req, .not_found, "unknown set");
    };
    if (set.cards.len > cfg.max_cards) {
        std.debug.print("render #{d}: refused, {d} cards is over --max-cards {d}\n", .{ req_n, set.cards.len, cfg.max_cards });
        return jsonError(req, .payload_too_large, try std.fmt.allocPrint(arena, "the set has {d} cards; this server allows {d}", .{ set.cards.len, cfg.max_cards }));
    }
    if (!set.ok) {
        std.debug.print("render #{d}: set '{s}' has {d} error(s), sent the problems back\n", .{ req_n, set.name, diags.errorCount() });
        return diagnosticsResponse(arena, req, &diags);
    }
    if (progress) |p| {
        p.total.store(set.cards.len, .release);
        p.set(.rendering);
    }

    if (want_vector) return vectorPdf(io, gpa, arena, req, &fs, set, .{ .date = date, .now = now, .utc_offset = utc_offset, .raster_scale = raster_scale, .marks = crop_marks, .n = req_n, .progress = progress, .started = started, .ok = &ok });

    const pngs = try gpa.alloc([]u8, set.cards.len);
    defer {
        for (pngs) |p| if (p.len > 0) gpa.free(p);
        gpa.free(pngs);
    }
    @memset(pngs, &.{});
    const pages = try gpa.alloc(?y.pdf.Page, set.cards.len);
    defer {
        for (pages) |*p| if (p.*) |*pg| pg.deinit(gpa);
        gpa.free(pages);
    }
    @memset(pages, null);
    const n_jobs = @min(cfg.threads, @max(1, set.cards.len));
    const shown_scale: f64 = if (want_svg) raster_scale else scale orelse 1;
    std.debug.print("render #{d}: {d} files, set '{s}', {d} cards as {s} at {d}x on {d} thread(s)\n", .{
        req_n, files.data.object.len, set.name, set.cards.len, if (want_pdf) "pdf" else if (want_svg) "svg" else if (sixteen) "png16" else "png", shown_scale, n_jobs,
    });
    const jobs = try arena.alloc(Job, n_jobs);
    const threads = try arena.alloc(?std.Thread, n_jobs);
    // Each job keeps its own diagnostics arena; the main arena is not thread-safe.
    const job_arenas = try arena.alloc(std.heap.ArenaAllocator, n_jobs);
    for (jobs, 0..) |*job, j| {
        job_arenas[j] = std.heap.ArenaAllocator.init(gpa);
        job.* = .{ .gpa = gpa, .fs = &fs, .set = set, .date = date, .now = now, .utc_offset = utc_offset, .sixteen = sixteen, .pdf = want_pdf, .scale = scale orelse 1, .crop_marks = crop_marks, .compression = compression, .svg = want_svg, .raster_scale = raster_scale, .pages = pages, .offset = j, .stride = n_jobs, .pngs = pngs, .diags = y.diag.List.init(job_arenas[j].allocator()), .progress = progress, .n = req_n };
    }
    defer for (job_arenas) |*a| a.deinit();
    for (jobs, 0..) |*job, j| {
        threads[j] = std.Thread.spawn(.{}, Job.run, .{job}) catch null;
        if (threads[j] == null) job.run();
    }
    for (threads) |t| if (t) |th| th.join();
    var failed = false;
    for (jobs) |*job| {
        failed = failed or job.failed;
        for (job.diags.items.items) |d| try diags.add(d);
    }
    if (failed) {
        std.debug.print("render #{d}: out of memory while rendering\n", .{req_n});
        return jsonError(req, .internal_server_error, "out of memory while rendering");
    }
    if (diags.errorCount() > 0) {
        std.debug.print("render #{d}: {d} error(s) while rendering, sent the problems back\n", .{ req_n, diags.errorCount() });
        return diagnosticsResponse(arena, req, &diags);
    }
    if (progress) |p| p.set(.packing);

    if (want_pdf) {
        var w = try y.pdf.Writer.init(gpa);
        defer w.deinit();
        for (pages) |*p| if (p.*) |*pg| try w.addPrepared(pg);
        const bytes = try w.finish();
        defer gpa.free(bytes);
        const pdf_disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.pdf\"", .{set.name});
        std.debug.print("render #{d}: done, {d} pages in {d} ms, sending {d:.1} MB of PDF\n", .{ req_n, set.cards.len, started.untilNow(io, .awake).toMilliseconds(), mb(bytes.len) });
        ok = true;
        return req.respond(bytes, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "application/pdf" },
            .{ .name = "content-disposition", .value = pdf_disposition },
        } });
    }

    var entries: std.ArrayList(zip.Entry) = .empty;
    if (sheet_grid) |grid| {
        const made = sheetEntries(gpa, arena, set.name, grid, pngs, &entries) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.TooLarge => {
                std.debug.print("render #{d}: the sheet is too large\n", .{req_n});
                return jsonError(req, .unprocessable_entity, try std.fmt.allocPrint(arena, "a {d}x{d} sheet of these cards is above the limit of {d} pixels per side", .{ grid[0], grid[1], y.raster.Sheet.max_side }));
            },
        };
        const archive = try zip.store(arena, entries.items);
        const disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.zip\"", .{set.name});
        std.debug.print("render #{d}: done, {d} cards on {d} sheet(s) of {d}x{d} in {d} ms, sending {d:.1} MB of zip\n", .{ req_n, set.cards.len, made, grid[0], grid[1], started.untilNow(io, .awake).toMilliseconds(), mb(archive.len) });
        ok = true;
        return req.respond(archive, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "application/zip" },
            .{ .name = "content-disposition", .value = disposition },
        } });
    }
    for (set.cards, 0..) |card, ci| {
        if (pngs[ci].len == 0) continue;
        try entries.append(arena, .{ .name = try std.fmt.allocPrint(arena, "{s}/{s}.{s}", .{ set.name, card.id, if (want_svg) "svg" else "png" }), .data = pngs[ci] });
    }
    const archive = try zip.store(arena, entries.items);
    const disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.zip\"", .{set.name});
    std.debug.print("render #{d}: done, {d} cards in {d} ms, sending {d:.1} MB of zip\n", .{ req_n, entries.items.len, started.untilNow(io, .awake).toMilliseconds(), mb(archive.len) });
    ok = true;
    return req.respond(archive, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = "application/zip" },
        .{ .name = "content-disposition", .value = disposition },
    } });
}

/// Tiles the cards' PNGs into sheets of `grid` (columns, rows), like
/// `yoshida render --sheet`: `<set>.png`, or `<set>-1.png`, `<set>-2.png`
/// when the set takes several. Returns the number of sheets.
fn sheetEntries(gpa: Allocator, arena: Allocator, set_name: []const u8, grid: [2]u32, pngs: []const []const u8, entries: *std.ArrayList(zip.Entry)) error{ OutOfMemory, TooLarge }!usize {
    var drawn: usize = 0;
    for (pngs) |p| {
        if (p.len > 0) drawn += 1;
    }
    const capacity = @as(usize, grid[0]) * grid[1];
    const many = drawn > capacity;
    var sheet: ?y.raster.Sheet = null;
    defer if (sheet) |*s| s.deinit(gpa);
    var on_sheet: usize = 0;
    var made: usize = 0;
    for (pngs) |png| {
        if (png.len == 0) continue;
        var w: c_int = 0;
        var h: c_int = 0;
        var ch: c_int = 0;
        const px = y.c.stbi_load_from_memory(png.ptr, @intCast(png.len), &w, &h, &ch, 4) orelse continue;
        defer y.c.stbi_image_free(px);
        const uw: u32 = @intCast(w);
        const uh: u32 = @intCast(h);
        if (sheet == null) sheet = try y.raster.Sheet.init(gpa, grid[0], grid[1], uw, uh);
        sheet.?.putRgba8(on_sheet, px[0 .. @as(usize, uw) * uh * 4], uw, uh);
        on_sheet += 1;
        if (on_sheet == capacity) {
            made += 1;
            try entries.append(arena, .{ .name = try y.raster.Sheet.fileName(arena, set_name, made, many), .data = try sheetPng(gpa, arena, &sheet.?) });
            sheet.?.deinit(gpa);
            sheet = null;
            on_sheet = 0;
        }
    }
    if (sheet) |*s| {
        made += 1;
        try entries.append(arena, .{ .name = try y.raster.Sheet.fileName(arena, set_name, made, many), .data = try sheetPng(gpa, arena, s) });
    }
    return made;
}

/// A sheet as PNG bytes that live in `arena`.
fn sheetPng(gpa: Allocator, arena: Allocator, sheet: *const y.raster.Sheet) Allocator.Error![]const u8 {
    const bytes = sheet.encodePng(gpa) catch return error.OutOfMemory;
    defer gpa.free(bytes);
    return arena.dupe(u8, bytes);
}

const VectorPdf = struct {
    date: []const u8,
    now: ?[]const u8,
    utc_offset: ?f64,
    raster_scale: f32,
    /// Crop marks in a margin around the page (like the image PDF's).
    marks: bool = false,
    n: u32,
    progress: ?*Progress,
    started: Io.Timestamp,
    ok: *bool,
};

/// A vector PDF of the set. The scenes point into the fonts and images of
/// one set of assets, so the pages are drawn one after the other here
/// instead of on the render threads; vector pages are quick to make.
fn vectorPdf(io: Io, gpa: Allocator, arena: Allocator, req: *std.http.Server.Request, fs: *y.project.MemFs, set: *const y.project.Set, o: VectorPdf) !void {
    var diags = y.diag.List.init(arena);
    var assets = y.render.Assets.init(gpa, fs.vfs());
    defer assets.deinit();
    var w = try y.pdf.Writer.init(gpa);
    defer w.deinit();
    std.debug.print("render #{d}: {d} cards of set '{s}' as vector pdf at {d}x\n", .{ o.n, set.cards.len, set.name, o.raster_scale });
    for (0..set.cards.len) |i| {
        var scene = y.vector.Scene.init(gpa);
        defer scene.deinit();
        scene.raster_scale = o.raster_scale;
        if (try y.render.renderVector(gpa, &assets, set, i, .{ .date = o.date, .now = o.now, .utc_offset = o.utc_offset }, &scene, &diags)) try w.addVector(&scene, o.marks);
        if (o.progress) |p| _ = p.done.fetchAdd(1, .acq_rel);
    }
    if (diags.errorCount() > 0) {
        std.debug.print("render #{d}: {d} error(s) while rendering, sent the problems back\n", .{ o.n, diags.errorCount() });
        return diagnosticsResponse(arena, req, &diags);
    }
    if (o.progress) |p| p.set(.packing);
    const bytes = try w.finish();
    defer gpa.free(bytes);
    const disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.pdf\"", .{set.name});
    std.debug.print("render #{d}: done, {d} pages in {d} ms, sending {d:.1} MB of PDF\n", .{ o.n, set.cards.len, o.started.untilNow(io, .awake).toMilliseconds(), mb(bytes.len) });
    o.ok.* = true;
    return req.respond(bytes, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = "application/pdf" },
        .{ .name = "content-disposition", .value = disposition },
    } });
}

/// The current UTC instant as `YYYY-MM-DDTHH:MM:SSZ` (seconds precision).
fn utcNow(io: Io, arena: Allocator) ![]const u8 {
    const ns = Io.Clock.real.now(io).nanoseconds;
    const secs: u64 = @intCast(@max(0, @divFloor(ns, std.time.ns_per_s)));
    const es: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,              md.month.numeric(),      md.day_index + 1,
        ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute(),
    });
}

/// `YYYY-MM-DDTHH:MM:SSZ` with a real calendar date and time of day.
fn validUtcInstant(s: []const u8) bool {
    const shape = "dddd-dd-ddTdd:dd:ddZ";
    if (s.len != shape.len) return false;
    for (s, shape) |ch, p| {
        const ok = if (p == 'd') std.ascii.isDigit(ch) else ch == p;
        if (!ok) return false;
    }
    const year = std.fmt.parseInt(u16, s[0..4], 10) catch return false;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return false;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return false;
    const hour = std.fmt.parseInt(u8, s[11..13], 10) catch return false;
    const minute = std.fmt.parseInt(u8, s[14..16], 10) catch return false;
    const second = std.fmt.parseInt(u8, s[17..19], 10) catch return false;
    if (month < 1 or month > 12 or day < 1 or hour > 23 or minute > 59 or second > 59) return false;
    return day <= std.time.epoch.getDaysInMonth(year, @enumFromInt(month));
}

fn diagnosticsResponse(arena: Allocator, req: *std.http.Server.Request, diags: *y.diag.List) !void {
    var aw: Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"error\":\"the project has errors\",\"diagnostics\":");
    try diags.writeJson(&aw.writer);
    try aw.writer.writeAll("}");
    return req.respond(aw.written(), .{ .status = .unprocessable_entity, .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
}

// ---------------------------------------------------------------- telemetry

const admin_page = @embedFile("admin.html");
const stats_page = @embedFile("stats.html");

fn capabilities(arena: Allocator, cfg: *const Config) ![]u8 {
    var aw: Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    try w.print("{{\"version\":\"{s}\",\"channel\":\"{s}\",\"format\":{d},\"render\":{},\"max_cards\":{d},\"max_body_mb\":{d},\"limits\":", .{ y.version, y.channel, y.format_version, cfg.render, cfg.max_cards, cfg.max_body_mb });
    try y.limits.writeJson(w, y.limits.current);
    try w.writeAll(",\"telemetry\":");
    if (cfg.store == null) {
        try w.writeAll("{\"enabled\":false}");
    } else {
        const t = cfg.telemetry;
        try w.print("{{\"enabled\":true,\"default\":\"{s}\",\"force\":", .{t.default_level.name()});
        if (t.force) |f| try w.print("\"{s}\"", .{f.name()}) else try w.writeAll("null");
        try w.writeAll(",\"retention_days\":");
        if (t.retention_days) |d| try w.print("{d}", .{d}) else try w.writeAll("null");
        try w.writeAll("}");
    }
    try w.writeAll("}");
    return aw.toOwnedSlice();
}

/// A copy of a request header. Read them before the body: the head buffer
/// is reused by the body reader.
fn header(arena: Allocator, req: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = req.iterateHeaders();
    while (it.next()) |h| if (std.ascii.eqlIgnoreCase(h.name, name)) return arena.dupe(u8, h.value) catch null;
    return null;
}

fn queryInt(target: []const u8, key: []const u8) ?u32 {
    const q = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    var parts = std.mem.splitScalar(u8, target[q + 1 ..], '&');
    while (parts.next()) |kv| {
        if (kv.len > key.len and kv[key.len] == '=' and std.mem.eql(u8, kv[0..key.len], key))
            return std.fmt.parseInt(u32, kv[key.len + 1 ..], 10) catch null;
    }
    return null;
}

/// Telemetry bodies must say how long they are (fetch and sendBeacon always do).
fn lengthKnown(req: *std.http.Server.Request) bool {
    return req.head.transfer_encoding != .none or req.head.content_length != null;
}

fn lengthRequired(req: *std.http.Server.Request) !void {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try w.writeAll("{\"error\":\"a body with a length is required\"}");
    return req.respond(w.buffered(), .{ .status = .length_required, .keep_alive = false, .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
}

fn readSmallBody(arena: Allocator, req: *std.http.Server.Request) ?[]u8 {
    if (req.head.content_length) |n| if (n > tel.max_body) return null;
    var buf: [1024]u8 = undefined;
    const r = req.readerExpectNone(&buf);
    return r.allocRemaining(arena, .limited(tel.max_body)) catch null;
}

fn noContent(req: *std.http.Server.Request) !void {
    return req.respond("", .{ .status = .no_content, .extra_headers = &.{.{ .name = "cache-control", .value = "no-store" }} });
}

/// Returns false when the path is not a telemetry route.
fn telemetryRoute(io: Io, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request, path: []const u8, target: []const u8, peer: []const u8) !bool {
    const store = cfg.store orelse {
        // Disabled: the endpoints do not exist.
        try jsonError(req, .not_found, "telemetry is not enabled on this server");
        return true;
    };
    const tc = cfg.telemetry;
    const now = unixNow(io);
    const user_agent = header(arena, req, "user-agent") orelse "";
    const forwarded = header(arena, req, "x-forwarded-for");
    const auth = header(arena, req, "authorization") orelse "";

    if (std.mem.eql(u8, path, "/admin/telemetry")) {
        if (tc.admin_token == null) return false;
        if (req.head.method != .GET and req.head.method != .HEAD) {
            try jsonError(req, .method_not_allowed, "method not allowed");
            return true;
        }
        try req.respond(admin_page, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            .{ .name = "cache-control", .value = "no-store" },
            .{ .name = "referrer-policy", .value = "no-referrer" },
            .{ .name = "x-robots-tag", .value = "noindex" },
            .{ .name = "content-security-policy", .value = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'" },
        } });
        return true;
    }

    if (std.mem.eql(u8, path, "/api/telemetry/ping")) {
        if (req.head.method != .POST) {
            try jsonError(req, .method_not_allowed, "use POST");
            return true;
        }
        if (tc.force != null and tc.force.? == .off) {
            try jsonError(req, .forbidden, "telemetry is forced off on this server");
            return true;
        }
        if (!lengthKnown(req)) {
            try lengthRequired(req);
            return true;
        }
        const body = readSmallBody(arena, req) orelse {
            try jsonError(req, .bad_request, "bad body");
            return true;
        };
        var level: tel.Level = .basic;
        if (body.len > 0) {
            if (y.json.parse(arena, body) catch null) |res| switch (res) {
                .ok => |n| if (n.get("level")) |l| if (l.data == .string and std.mem.eql(u8, l.data.string, "advanced") and (tc.force == null)) {
                    level = .advanced;
                },
                .err => {},
            };
        }
        // The address is only used for the daily hash; with --telemetry-trust-proxy
        // the first X-Forwarded-For entry stands in for it.
        var client: []const u8 = peer;
        if (tc.trust_proxy) if (forwarded) |xff| {
            const first = std.mem.trim(u8, xff[0..(std.mem.indexOfScalar(u8, xff, ',') orelse xff.len)], " ");
            if (first.len > 0) client = first;
        };
        store.ping(now, client, user_agent, level) catch {
            try jsonError(req, .internal_server_error, "out of memory");
            return true;
        };
        try noContent(req);
        return true;
    }

    if (std.mem.eql(u8, path, "/api/telemetry/events")) {
        if (req.head.method != .POST) {
            try jsonError(req, .method_not_allowed, "use POST");
            return true;
        }
        if (tc.force != null) {
            try jsonError(req, .forbidden, "advanced telemetry is turned off on this server");
            return true;
        }
        if (!lengthKnown(req)) {
            try lengthRequired(req);
            return true;
        }
        const body = readSmallBody(arena, req) orelse {
            try jsonError(req, .bad_request, "bad body");
            return true;
        };
        _ = store.events(now, body) catch |e| switch (e) {
            error.BadRequest => {
                try jsonError(req, .bad_request, "expected {\"events\":[{\"k\":...,\"n\":...}]}");
                return true;
            },
            else => {
                try jsonError(req, .internal_server_error, "out of memory");
                return true;
            },
        };
        try noContent(req);
        return true;
    }

    if (std.mem.eql(u8, path, "/api/stats")) {
        if (req.head.method != .GET) {
            try jsonError(req, .method_not_allowed, "use GET");
            return true;
        }
        const days = std.math.clamp(queryInt(target, "days") orelse 30, 1, 366);
        const body = try store.statsJson(arena, now, days, true);
        try req.respond(body, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "public, max-age=60" },
            .{ .name = "access-control-allow-origin", .value = "*" },
        } });
        return true;
    }

    if (std.mem.eql(u8, path, "/api/stats/page")) {
        if (req.head.method != .GET and req.head.method != .HEAD) {
            try jsonError(req, .method_not_allowed, "method not allowed");
            return true;
        }
        // The page loads the numbers itself from /api/stats, so it can be cached.
        try req.respond(stats_page, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            .{ .name = "cache-control", .value = "public, max-age=300" },
            .{ .name = "referrer-policy", .value = "no-referrer" },
            .{ .name = "x-robots-tag", .value = "noindex" },
            .{ .name = "content-security-policy", .value = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'" },
        } });
        return true;
    }

    if (std.mem.startsWith(u8, path, "/api/admin/")) {
        if (tc.admin_token == null) return false;
        const prefix = "Bearer ";
        const supplied = if (std.mem.startsWith(u8, auth, prefix)) auth[prefix.len..] else "";
        if (!tel.tokenOk(tc, supplied)) {
            io.sleep(.fromMilliseconds(400), .awake) catch {};
            try jsonError(req, .unauthorized, "missing or wrong admin token");
            return true;
        }
        if (std.mem.eql(u8, path, "/api/admin/stats") and req.head.method == .GET) {
            const days = std.math.clamp(queryInt(target, "days") orelse 90, 1, 3660);
            const body = try store.statsJson(arena, now, days, false);
            try req.respond(body, .{ .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
                .{ .name = "cache-control", .value = "no-store" },
            } });
            return true;
        }
        if (std.mem.eql(u8, path, "/api/admin/public") and (req.head.method == .PUT or req.head.method == .POST)) {
            if (!lengthKnown(req)) {
                try lengthRequired(req);
                return true;
            }
            const body = readSmallBody(arena, req) orelse {
                try jsonError(req, .bad_request, "bad body");
                return true;
            };
            const doc = switch (try y.json.parse(arena, body)) {
                .ok => |n| n,
                .err => {
                    try jsonError(req, .bad_request, "invalid JSON");
                    return true;
                },
            };
            const list = doc.get("public") orelse {
                try jsonError(req, .bad_request, "missing \"public\"");
                return true;
            };
            if (list.data != .array) {
                try jsonError(req, .bad_request, "\"public\" must be an array of keys");
                return true;
            }
            var keys: std.ArrayList([]const u8) = .empty;
            for (list.data.array) |item| {
                if (item.data != .string) {
                    try jsonError(req, .bad_request, "\"public\" must hold strings");
                    return true;
                }
                try keys.append(arena, item.data.string);
            }
            store.setPublic(keys.items) catch |e| switch (e) {
                error.BadRequest => {
                    try jsonError(req, .bad_request, "unknown or too many keys");
                    return true;
                },
                else => return e,
            };
            store.flush(now);
            try noContent(req);
            return true;
        }
        try jsonError(req, .not_found, "unknown API endpoint");
        return true;
    }
    return false;
}

test {
    _ = tel;
}
