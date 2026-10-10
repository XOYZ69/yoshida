//! yoshida-server: serves the web editor and, when enabled, renders whole
//! sets on the server ("hybrid" mode for home labs).
//!
//!   GET  /api/capabilities   {"version", "format", "render", "max_cards", "max_body_mb"}
//!   POST /api/render         {"files": {path: base64}, "set", "date", "format": "png"|"png16"|"pdf"}
//!                            -> application/zip with <set>/<card id>.png, or 422 with diagnostics
//!   GET  /*                  static files from --web (the built editor)

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
    const path = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;

    if (std.mem.eql(u8, path, "/api/capabilities")) {
        const body = try std.fmt.allocPrint(arena, "{{\"version\":\"{s}\",\"format\":{d},\"render\":{},\"max_cards\":{d},\"max_body_mb\":{d}}}", .{ y.version, y.format_version, cfg.render, cfg.max_cards, cfg.max_body_mb });
        return req.respond(body, .{ .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
    }
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
    };
    inline for (map) |m| if (std.ascii.eqlIgnoreCase(ext, m[0])) return m[1];
    return "application/octet-stream";
}

fn serveStatic(io: Io, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request, url_path: []const u8) !void {
    var rel = std.mem.trimStart(u8, url_path, "/");
    if (rel.len == 0 or rel[rel.len - 1] == '/') rel = try std.mem.concat(arena, u8, &.{ rel, "index.html" });
    // Percent-decoding is limited to spaces and '!' (used by the example font names).
    const decoded = try std.mem.replaceOwned(u8, arena, try std.mem.replaceOwned(u8, arena, rel, "%20", " "), "%21", "!");
    const clean = (try y.project.normalize(arena, decoded)) orelse return jsonError(req, .not_found, "not found");
    const full = try std.fs.path.join(arena, &.{ cfg.web, clean });
    const data = Io.Dir.cwd().readFileAlloc(io, full, arena, .limited(64 * 1024 * 1024)) catch {
        return jsonError(req, .not_found, "not found");
    };
    return req.respond(data, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = contentType(clean) },
        .{ .name = "cache-control", .value = "no-cache" },
    } });
}

const Job = struct {
    gpa: Allocator,
    fs: *y.project.MemFs,
    set: *const y.project.Set,
    date: []const u8,
    sixteen: bool,
    pdf: bool = false,
    /// Cards with index % stride == offset belong to this job.
    offset: usize,
    stride: usize,
    pngs: [][]u8,
    pages: []?y.pdf.Page = &.{},
    diags: y.diag.List,
    failed: bool = false,

    fn run(job: *Job) void {
        var assets = y.render.Assets.init(job.gpa, job.fs.vfs());
        defer assets.deinit();
        var i = job.offset;
        while (i < job.set.cards.len) : (i += job.stride) {
            var bmp = (y.render.renderCard(job.gpa, &assets, job.set, i, .{ .date = job.date }, &job.diags) catch {
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
};

fn renderSet(io: Io, gpa: Allocator, arena: Allocator, cfg: *const Config, req: *std.http.Server.Request) !void {
    const max_body = cfg.max_body_mb * 1024 * 1024;
    if (req.head.content_length) |n| if (n > max_body) return jsonError(req, .payload_too_large, "request body is too large");
    var body_buf: [16 * 1024]u8 = undefined;
    const body_reader = req.readerExpectNone(&body_buf);
    const body = body_reader.allocRemaining(arena, .limited(max_body)) catch return jsonError(req, .bad_request, "could not read the request body");

    const doc = switch (try y.json.parse(arena, body)) {
        .ok => |n| n,
        .err => |e| return jsonError(req, .bad_request, try std.fmt.allocPrint(arena, "invalid JSON: {s}", .{e.message})),
    };
    const files = doc.get("files") orelse return jsonError(req, .bad_request, "missing \"files\"");
    if (files.data != .object) return jsonError(req, .bad_request, "\"files\" must be an object of path to base64");
    const set_name = if (doc.get("set")) |s| (if (s.data == .string) s.data.string else "") else "";
    const date = if (doc.get("date")) |d| (if (d.data == .string) d.data.string else "1970-01-01") else "1970-01-01";
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
    const set = proj.findSet(set_name) orelse return jsonError(req, .not_found, "unknown set");
    if (set.cards.len > cfg.max_cards) return jsonError(req, .payload_too_large, try std.fmt.allocPrint(arena, "the set has {d} cards; this server allows {d}", .{ set.cards.len, cfg.max_cards }));
    if (!set.ok) return diagnosticsResponse(arena, req, &diags);

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
    const jobs = try arena.alloc(Job, n_jobs);
    const threads = try arena.alloc(?std.Thread, n_jobs);
    // Each job keeps its own diagnostics arena; the main arena is not thread-safe.
    const job_arenas = try arena.alloc(std.heap.ArenaAllocator, n_jobs);
    for (jobs, 0..) |*job, j| {
        job_arenas[j] = std.heap.ArenaAllocator.init(gpa);
        job.* = .{ .gpa = gpa, .fs = &fs, .set = set, .date = date, .sixteen = sixteen, .pdf = want_pdf, .pages = pages, .offset = j, .stride = n_jobs, .pngs = pngs, .diags = y.diag.List.init(job_arenas[j].allocator()) };
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
    if (failed) return jsonError(req, .internal_server_error, "out of memory while rendering");
    if (diags.errorCount() > 0) return diagnosticsResponse(arena, req, &diags);

    if (want_pdf) {
        var w = try y.pdf.Writer.init(gpa);
        defer w.deinit();
        for (pages) |*p| if (p.*) |*pg| try w.addPrepared(pg);
        const bytes = try w.finish();
        defer gpa.free(bytes);
        const pdf_disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.pdf\"", .{set.name});
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
    _ = io;
    const disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.zip\"", .{set.name});
    return req.respond(archive, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = "application/zip" },
        .{ .name = "content-disposition", .value = disposition },
    } });
}

fn diagnosticsResponse(arena: Allocator, req: *std.http.Server.Request, diags: *y.diag.List) !void {
    var aw: Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll("{\"error\":\"the project has errors\",\"diagnostics\":");
    try diags.writeJson(&aw.writer);
    try aw.writer.writeAll("}");
    return req.respond(aw.written(), .{ .status = .unprocessable_entity, .extra_headers = &.{.{ .name = "content-type", .value = "application/json" }} });
}
