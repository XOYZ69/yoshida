//! yoshida-server: serves the web editor and, when enabled, renders whole
//! sets on the server ("hybrid" mode for home labs).
//!
//!   GET  /api/capabilities   {"version", "format", "render", "max_cards", "max_body_mb"}
//!   POST /api/render         {"files": {path: base64}, "set", "date", "now", "utc_offset", "format": "png"|"png16"|"pdf"}
//!                            -> application/zip with <set>/<card id>.png, or 422 with diagnostics
//!                            "now" is a UTC instant (YYYY-MM-DDTHH:MM:SSZ) and "utc_offset" the hours (-14 to 14)
//!                            that replace the project's; with neither "date" nor "now" the server's clock is used
//!                            An `x-yoshida-job: <hex id>` header makes its progress readable:
//!   GET  /api/render/progress?job=<hex id>
//!                            {"found", "stage", "done", "total"} (stage: receiving, loading,
//!                            rendering, packing, finished, failed)
//!   GET  /*                  static files from --web (the built editor, or the
//!                            site with the editor in editor/)
//!
//! The API also answers under /editor/api/, where the editor's relative
//! "api/..." calls land when it is served from /editor/.

const std = @import("std");
const y = @import("yoshida");
const zip = @import("zip.zig");
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
};

const usage =
    \\Usage: yoshida-server [--host ADDR] [--port N] [--web DIR] [--no-render]
    \\                      [--max-cards N] [--max-body-mb N] [--threads N]
    \\
    \\Environment variables YOSHIDA_HOST, YOSHIDA_PORT, YOSHIDA_WEB, YOSHIDA_RENDER (0/1),
    \\YOSHIDA_MAX_CARDS, YOSHIDA_MAX_BODY_MB and YOSHIDA_THREADS set the same options.
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

    const argv = try init.minimal.args.toSlice(arena);
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--no-render")) {
            cfg.render = false;
            continue;
        }
        if (std.mem.eql(u8, a, "--help") or i + 1 >= argv.len) {
            std.debug.print(usage, .{});
            return if (std.mem.eql(u8, a, "--help")) 0 else 2;
        }
        i += 1;
        const v = argv[i];
        if (std.mem.eql(u8, a, "--host")) cfg.host = v else if (std.mem.eql(u8, a, "--port")) cfg.port = try std.fmt.parseInt(u16, v, 10) else if (std.mem.eql(u8, a, "--web")) cfg.web = v else if (std.mem.eql(u8, a, "--max-cards")) cfg.max_cards = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--max-body-mb")) cfg.max_body_mb = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--threads")) cfg.threads = try std.fmt.parseInt(usize, v, 10) else {
            std.debug.print("unknown option {s}\n\n" ++ usage, .{a});
            return 2;
        }
    }
    if (cfg.threads == 0) cfg.threads = @max(1, std.Thread.getCpuCount() catch 1);

    const addr = try Io.net.IpAddress.parse(cfg.host, cfg.port);
    var server = try addr.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.debug.print("yoshida-server {s} listening on http://{s}:{d} (web: {s}, server render: {s}, {d} threads)\n", .{
        y.version, cfg.host, cfg.port, cfg.web, if (cfg.render) "on" else "off", cfg.threads,
    });

    var group: Io.Group = .init;
    defer group.cancel(io);
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

fn serveConnection(io: Io, gpa: Allocator, cfg: *const Config, stream: Io.net.Stream) void {
    defer stream.close(io);
    var in_buf: [16 * 1024]u8 = undefined;
    var out_buf: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &in_buf);
    var writer = stream.writer(io, &out_buf);
    var http = std.http.Server.init(&reader.interface, &writer.interface);
    while (true) {
        var req = http.receiveHead() catch return;
        handle(io, gpa, cfg, &req) catch |e| {
            std.debug.print("{s} {s}: {s}\n", .{ @tagName(req.head.method), req.head.target, @errorName(e) });
            return;
        };
        if (!req.head.keep_alive) return;
    }
}

fn handle(io: Io, gpa: Allocator, cfg: *const Config, req: *std.http.Server.Request) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const target = req.head.target;
    const full_path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;
    const path = if (std.mem.startsWith(u8, full_path, "/editor/api/")) full_path["/editor".len..] else full_path;

    if (std.mem.eql(u8, path, "/api/capabilities")) {
        const body = try std.fmt.allocPrint(arena, "{{\"version\":\"{s}\",\"format\":{d},\"render\":{},\"max_cards\":{d},\"max_body_mb\":{d}}}", .{ y.version, y.format_version, cfg.render, cfg.max_cards, cfg.max_body_mb });
        return req.respond(body, .{ .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
    }
    if (std.mem.eql(u8, path, "/api/render/progress")) return progressResponse(arena, req, target);
    if (std.mem.eql(u8, path, "/api/render")) {
        if (req.head.method != .POST) return jsonError(req, .method_not_allowed, "use POST");
        if (!cfg.render) return jsonError(req, .forbidden, "server rendering is disabled on this server");
        return renderSet(io, gpa, arena, cfg, req);
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
            var bmp = (y.render.renderCard(job.gpa, &assets, job.set, i, .{ .date = job.date, .now = job.now, .utc_offset = job.utc_offset }, &job.diags) catch {
                job.failed = true;
                return;
            }) orelse continue;
            defer bmp.deinit(job.gpa);
            if (job.pdf) {
                job.pages[i] = y.pdf.Page.init(job.gpa, &bmp) catch {
                    job.failed = true;
                    return;
                };
                continue;
            }
            job.pngs[i] = y.raster.encodePng(job.gpa, &bmp, job.sixteen) catch {
                job.failed = true;
                return;
            };
        }
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
    std.debug.print("render #{d}: {d} files, set '{s}', {d} cards as {s} on {d} thread(s)\n", .{
        req_n, files.data.object.len, set.name, set.cards.len, if (want_pdf) "pdf" else if (sixteen) "png16" else "png", n_jobs,
    });
    const jobs = try arena.alloc(Job, n_jobs);
    const threads = try arena.alloc(?std.Thread, n_jobs);
    // Each job keeps its own diagnostics arena; the main arena is not thread-safe.
    const job_arenas = try arena.alloc(std.heap.ArenaAllocator, n_jobs);
    for (jobs, 0..) |*job, j| {
        job_arenas[j] = std.heap.ArenaAllocator.init(gpa);
        job.* = .{ .gpa = gpa, .fs = &fs, .set = set, .date = date, .now = now, .utc_offset = utc_offset, .sixteen = sixteen, .pdf = want_pdf, .pages = pages, .offset = j, .stride = n_jobs, .pngs = pngs, .diags = y.diag.List.init(job_arenas[j].allocator()), .progress = progress, .n = req_n };
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
    for (set.cards, 0..) |card, ci| {
        if (pngs[ci].len == 0) continue;
        try entries.append(arena, .{ .name = try std.fmt.allocPrint(arena, "{s}/{s}.png", .{ set.name, card.id }), .data = pngs[ci] });
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
