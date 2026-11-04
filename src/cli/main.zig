//! yoshida command-line interface.

const std = @import("std");
const y = @import("yoshida");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage =
    \\yoshida {s} (format {d})
    \\
    \\Usage:
    \\  yoshida check  <project>  [--set NAME] [--card ID] [--format text|json]
    \\                            [--now YYYY-MM-DDTHH:MM:SSZ] [--utc-offset HOURS]
    \\  yoshida render <project>  [--set NAME] [--card ID] [--out DIR]
    \\                            [--date YYYY-MM-DD] [--now YYYY-MM-DDTHH:MM:SSZ]
    \\                            [--utc-offset HOURS] [--16bit] [--preview]
    \\                            [--offline] [--pdf] [--crop-marks] [--svg]
    \\                            [--vector] [--scale N] [--format text|json]
    \\  yoshida fmt    <project or file>  [--check]
    \\  yoshida version
    \\
    \\check   loads every design and card file and evaluates every card
    \\        (without drawing), then reports problems.
    \\render  writes <out>/<set>/<card id>.png (default out: <project>/out).
    \\        Images given as https:// URLs are downloaded (once per run);
    \\        --offline turns that off. --pdf writes <out>/<set>.pdf instead,
    \\        one page per card; --crop-marks adds a margin with crop marks
    \\        at the trim line (canvas.bleed inside the edge).
    \\        --svg writes <out>/<set>/<card id>.svg, a vector file, instead of
    \\        a PNG. --pdf --vector draws the PDF pages as vectors (sharp at
    \\        any zoom) instead of as images.
    \\        --scale N (1 to 4) renders PNGs and PDF images at N times the
    \\        canvas size, at the same print size. With --svg or --vector it
    \\        sets the resolution of the parts that stay pixels (default 2).
    \\clock   --now is the UTC instant the cards are rendered at (render.now,
    \\        render.date, render.time). Without --now or --date it is the
    \\        current UTC time; --date alone pins the local date at midnight.
    \\        --utc-offset (-14 to 14 hours) replaces the project's utc_offset.
    \\fmt     rewrites JSON files in the canonical layout; --check only lists
    \\        the files that are not formatted (exit status 1 if any).
    \\
    \\Exit status: 0 no errors, 1 errors were reported, 2 usage error.
    \\
;

const Args = struct {
    command: []const u8 = "",
    project: ?[]const u8 = null,
    set: ?[]const u8 = null,
    card: ?[]const u8 = null,
    out: ?[]const u8 = null,
    date: ?[]const u8 = null,
    now: ?[]const u8 = null,
    utc_offset: ?[]const u8 = null,
    sixteen: bool = false,
    preview: bool = false,
    json: bool = false,
    offline: bool = false,
    check: bool = false,
    pdf: bool = false,
    crop_marks: bool = false,
    scale: ?[]const u8 = null,
    svg: bool = false,
    vector: bool = false,
};

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    var out_buf: [8192]u8 = undefined;
    var stdout_w = Io.File.Writer.init(.stdout(), io, &out_buf);
    const out = &stdout_w.interface;
    var err_buf: [4096]u8 = undefined;
    var stderr_w = Io.File.Writer.init(.stderr(), io, &err_buf);
    const err = &stderr_w.interface;
    defer out.flush() catch {};
    defer err.flush() catch {};

    const argv = try init.minimal.args.toSlice(arena);
    const args = parseArgs(argv[1..]) catch |e| {
        try err.print("error: {s}\n\n", .{@errorName(e)});
        try err.print(usage, .{ y.version, y.format_version });
        return 2;
    };
    if (std.mem.eql(u8, args.command, "version")) {
        try out.print("yoshida {s} (format {d})\n", .{ y.version, y.format_version });
        return 0;
    }
    if (args.command.len == 0 or std.mem.eql(u8, args.command, "help") or args.project == null) {
        try out.print(usage, .{ y.version, y.format_version });
        return if (args.command.len == 0 or std.mem.eql(u8, args.command, "help")) 0 else 2;
    }
    if (std.mem.eql(u8, args.command, "fmt")) return formatCommand(io, arena, args, out, err);
    const is_render = std.mem.eql(u8, args.command, "render");
    if (!is_render and !std.mem.eql(u8, args.command, "check")) {
        try err.print("error: unknown command '{s}'\n\n", .{args.command});
        try err.print(usage, .{ y.version, y.format_version });
        return 2;
    }
    if (args.svg and args.pdf) {
        try err.print("error: --svg and --pdf cannot be used together\n", .{});
        return 2;
    }
    if (args.vector and !args.pdf) {
        try err.print("error: --vector goes with --pdf (--svg is always a vector file)\n", .{});
        return 2;
    }
    if (args.now) |n| if (!validUtcInstant(n)) {
        try err.print("error: --now must be a UTC instant like 2026-10-15T09:30:00Z, got '{s}'\n", .{n});
        return 2;
    };
    var utc_offset: ?f64 = null;
    if (args.utc_offset) |s| {
        utc_offset = parseOffset(s) orelse {
            try err.print("error: --utc-offset must be a number of hours from -14 to 14, got '{s}'\n", .{s});
            return 2;
        };
    }
    // Bitmap pixels per canvas pixel: of the whole image for PNG and image
    // PDF output (default 1), of the parts that stay pixels for --svg and
    // --vector (default 2).
    var scale: ?f64 = null;
    if (args.scale) |s| {
        const k = std.fmt.parseFloat(f64, s) catch -1;
        if (!(k >= 1 and k <= 4)) {
            try err.print("error: --scale must be a number from 1 to 4, got '{s}'\n", .{s});
            return 2;
        }
        scale = k;
    }
    // One clock for the whole run: the current UTC instant unless the
    // render is pinned with --date alone (then the date is local midnight).
    const instant = try utcNow(io, arena);
    const now: ?[]const u8 = args.now orelse if (args.date == null) instant else null;
    const date = args.date orelse instant[0..10];

    var disk = DiskFs.open(io, arena, args.project.?) catch |e| {
        try err.print("error: cannot open project folder '{s}': {s}\n", .{ args.project.?, @errorName(e) });
        return 1;
    };
    var http: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http.deinit();
    if (is_render and !args.offline) {
        http.initDefaultProxies(arena, init.environ_map) catch {};
        disk.http = &http;
        disk.log = err;
    }
    var diags = y.diag.List.init(arena);
    const proj = try y.project.load(arena, disk.vfs(), &diags);

    var rendered: usize = 0;
    var rendered_files: std.ArrayList([]const u8) = .empty;
    var failed_files: std.ArrayList([]const u8) = .empty;
    var checked_cards: usize = 0;
    if (!is_render and diags.errorCount() == 0) {
        // Errors that depend on card data (layer limit, missing images,
        // indexes out of range) only show up while a card is evaluated.
        var assets = y.render.Assets.init(gpa, disk.vfs());
        defer assets.deinit();
        for (proj.sets) |*set| {
            if (args.set) |s| if (!std.mem.eql(u8, s, set.name)) continue;
            if (!set.ok) continue;
            for (set.cards, 0..) |card, i| {
                if (args.card) |cid| if (!std.mem.eql(u8, cid, card.id)) continue;
                var bmp = (try y.render.renderCard(gpa, &assets, set, i, .{ .date = date, .now = now, .utc_offset = utc_offset, .dry = true }, &diags)) orelse continue;
                bmp.deinit(gpa);
                checked_cards += 1;
            }
        }
    }
    if (is_render and diags.errorCount() == 0) {
        const out_root = args.out orelse try std.fs.path.join(arena, &.{ args.project.?, "out" });
        var assets = y.render.Assets.init(gpa, disk.vfs());
        defer assets.deinit();
        var matched_set = args.set == null;
        for (proj.sets) |*set| {
            if (args.set) |s| if (!std.mem.eql(u8, s, set.name)) continue;
            matched_set = true;
            if (!set.ok) continue;
            const dir = if (args.pdf) out_root else try std.fs.path.join(arena, &.{ out_root, set.name });
            Io.Dir.cwd().createDirPath(io, dir) catch |e| {
                try err.print("error: cannot create '{s}': {s}\n", .{ dir, @errorName(e) });
                return 1;
            };
            var pdf: ?y.pdf.Writer = if (args.pdf) try y.pdf.Writer.init(gpa) else null;
            defer if (pdf) |*p| p.deinit();
            var pdf_pages: usize = 0;
            var pdf_errors = false;
            for (set.cards, 0..) |card, i| {
                if (args.card) |cid| if (!std.mem.eql(u8, cid, card.id)) continue;
                const errors_before = diags.errorCount();
                if (args.pdf and args.vector) {
                    var scene = y.vector.Scene.init(gpa);
                    defer scene.deinit();
                    scene.raster_scale = @floatCast(scale orelse 2);
                    if (!try y.render.renderVector(gpa, &assets, set, i, .{ .date = date, .now = now, .utc_offset = utc_offset, .preview = args.preview }, &scene, &diags)) continue;
                    try pdf.?.addVector(&scene, args.crop_marks);
                    pdf_pages += 1;
                    if (diags.errorCount() > errors_before) pdf_errors = true;
                    continue;
                }
                if (args.svg) {
                    var scene = y.vector.Scene.init(gpa);
                    defer scene.deinit();
                    scene.raster_scale = @floatCast(scale orelse 2);
                    if (!try y.render.renderVector(gpa, &assets, set, i, .{ .date = date, .now = now, .utc_offset = utc_offset, .preview = args.preview }, &scene, &diags)) continue;
                    const card_errors = diags.errorCount() - errors_before;
                    const svg = try y.svg.write(gpa, &scene);
                    defer gpa.free(svg);
                    const file = try std.fmt.allocPrint(arena, "{s}/{s}.svg", .{ dir, card.id });
                    Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = svg }) catch |e| {
                        try err.print("error: cannot write '{s}': {s}\n", .{ file, @errorName(e) });
                        return 1;
                    };
                    rendered += 1;
                    try rendered_files.append(arena, file);
                    if (card_errors > 0) try failed_files.append(arena, file);
                    if (args.json) {} else if (card_errors > 0) {
                        try out.print("wrote {s} ({d} x {d}) with {d} error(s): parts of the card are missing\n", .{ file, scene.width, scene.height, card_errors });
                    } else try out.print("wrote {s} ({d} x {d})\n", .{ file, scene.width, scene.height });
                    continue;
                }
                var bmp = (try y.render.renderCard(gpa, &assets, set, i, .{ .date = date, .now = now, .utc_offset = utc_offset, .preview = args.preview, .scale = scale orelse 1 }, &diags)) orelse continue;
                const card_errors = diags.errorCount() - errors_before;
                defer bmp.deinit(gpa);
                if (args.crop_marks) {
                    const marked = try y.raster.withCropMarks(gpa, &bmp);
                    bmp.deinit(gpa);
                    bmp = marked;
                }
                if (pdf) |*p| {
                    try p.addPage(&bmp);
                    pdf_pages += 1;
                    if (card_errors > 0) pdf_errors = true;
                    continue;
                }
                const png = try y.raster.encodePng(gpa, &bmp, args.sixteen);
                defer gpa.free(png);
                const file = try std.fmt.allocPrint(arena, "{s}/{s}.png", .{ dir, card.id });
                Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = png }) catch |e| {
                    try err.print("error: cannot write '{s}': {s}\n", .{ file, @errorName(e) });
                    return 1;
                };
                rendered += 1;
                try rendered_files.append(arena, file);
                if (card_errors > 0) try failed_files.append(arena, file);
                if (args.json) {} else if (card_errors > 0) {
                    try out.print("wrote {s} ({d} x {d}) with {d} error(s): parts of the card are missing\n", .{ file, bmp.w, bmp.h, card_errors });
                } else try out.print("wrote {s} ({d} x {d})\n", .{ file, bmp.w, bmp.h });
            }
            if (pdf) |*p| if (pdf_pages > 0) {
                const bytes = try p.finish();
                defer gpa.free(bytes);
                const file = try std.fmt.allocPrint(arena, "{s}/{s}.pdf", .{ dir, set.name });
                Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = bytes }) catch |e| {
                    try err.print("error: cannot write '{s}': {s}\n", .{ file, @errorName(e) });
                    return 1;
                };
                rendered += pdf_pages;
                try rendered_files.append(arena, file);
                if (pdf_errors) try failed_files.append(arena, file);
                if (!args.json) try out.print("wrote {s} ({d} page(s)){s}\n", .{ file, pdf_pages, if (pdf_errors) " with errors: parts of some cards are missing" else "" });
            };
        }
        if (!matched_set) {
            try err.print("error: no set named '{s}'. Sets:", .{args.set.?});
            for (proj.sets) |s| try err.print(" {s}", .{s.name});
            try err.writeByte('\n');
            return 2;
        }
    }

    if (args.json) {
        try out.writeAll("{\"diagnostics\":");
        try diags.writeJson(out);
        try out.writeAll(",\"sets\":[");
        for (proj.sets, 0..) |s, i| {
            if (i > 0) try out.writeByte(',');
            try out.writeAll("{\"name\":");
            try y.json.writeString(out, s.name);
            try out.writeAll(",\"design\":");
            try y.json.writeString(out, s.design_path);
            try out.print(",\"cards\":{d},\"ok\":{}}}", .{ s.cards.len, s.ok });
        }
        try out.writeAll("],\"written\":[");
        for (rendered_files.items, 0..) |f, i| {
            if (i > 0) try out.writeByte(',');
            try y.json.writeString(out, f);
        }
        try out.writeAll("],\"with_errors\":[");
        for (failed_files.items, 0..) |f, i| {
            if (i > 0) try out.writeByte(',');
            try y.json.writeString(out, f);
        }
        try out.writeAll("]}\n");
    } else {
        try diags.writeText(out);
        if (!is_render) {
            for (proj.sets) |s| {
                try out.print("set {s}: {s}, {d} card(s){s}\n", .{ s.name, s.design_path, s.cards.len, if (s.ok) "" else " (has errors)" });
            }
        }
        try out.print("{d} error(s), {d} warning(s), {d} hint(s)", .{ diags.count(.err), diags.count(.warning), diags.count(.hint) });
        if (is_render) try out.print(", {d} card(s) rendered", .{rendered}) else if (checked_cards > 0) try out.print(", {d} card(s) checked", .{checked_cards});
        if (failed_files.items.len > 0) try out.print(", {d} with errors", .{failed_files.items.len});
        try out.writeByte('\n');
        if (is_render and diags.errorCount() > 0 and rendered == 0) try out.writeAll("nothing was rendered because of the errors above\n");
    }
    return if (diags.errorCount() > 0) 1 else 0;
}

fn parseArgs(argv: []const [:0]const u8) !Args {
    var a: Args = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const s = argv[i];
        if (std.mem.startsWith(u8, s, "--")) {
            const name = s[2..];
            if (std.mem.eql(u8, name, "16bit")) {
                a.sixteen = true;
                continue;
            }
            if (std.mem.eql(u8, name, "preview")) {
                a.preview = true;
                continue;
            }
            if (std.mem.eql(u8, name, "offline")) {
                a.offline = true;
                continue;
            }
            if (std.mem.eql(u8, name, "check")) {
                a.check = true;
                continue;
            }
            if (std.mem.eql(u8, name, "pdf")) {
                a.pdf = true;
                continue;
            }
            if (std.mem.eql(u8, name, "crop-marks")) {
                a.crop_marks = true;
                continue;
            }
            if (std.mem.eql(u8, name, "svg")) {
                a.svg = true;
                continue;
            }
            if (std.mem.eql(u8, name, "vector")) {
                a.vector = true;
                continue;
            }
            if (std.mem.eql(u8, name, "help")) {
                a.command = "help";
                continue;
            }
            if (std.mem.eql(u8, name, "version")) {
                a.command = "version";
                continue;
            }
            if (i + 1 >= argv.len) return error.MissingOptionValue;
            i += 1;
            const v = argv[i];
            if (std.mem.eql(u8, name, "set")) a.set = v else if (std.mem.eql(u8, name, "card")) a.card = v else if (std.mem.eql(u8, name, "out")) a.out = v else if (std.mem.eql(u8, name, "date")) a.date = v else if (std.mem.eql(u8, name, "now")) a.now = v else if (std.mem.eql(u8, name, "utc-offset")) a.utc_offset = v else if (std.mem.eql(u8, name, "scale")) a.scale = v else if (std.mem.eql(u8, name, "format")) {
                if (std.mem.eql(u8, v, "json")) a.json = true else if (!std.mem.eql(u8, v, "text")) return error.UnknownFormat;
            } else return error.UnknownOption;
        } else if (std.mem.eql(u8, s, "-h")) {
            a.command = "help";
        } else if (a.command.len == 0) {
            a.command = s;
        } else if (a.project == null) {
            a.project = s;
        } else return error.TooManyArguments;
    }
    return a;
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

/// A UTC offset in hours from -14 to 14 (NaN is rejected too).
fn parseOffset(s: []const u8) ?f64 {
    const v = std.fmt.parseFloat(f64, s) catch return null;
    return if (v >= -14 and v <= 14) v else null;
}

/// A project folder on disk, read lazily and cached for the whole run.
const DiskFs = struct {
    io: Io,
    arena: Allocator,
    dir: Io.Dir,
    files: []const []const u8,
    cache: std.StringHashMapUnmanaged(?[]const u8) = .empty,
    /// Downloads https:// images when set.
    http: ?*std.http.Client = null,
    log: ?*Io.Writer = null,

    fn open(io: Io, arena: Allocator, path: []const u8) !DiskFs {
        const dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        var files: std.ArrayList([]const u8) = .empty;
        var walker = try dir.walkSelectively(arena);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind == .directory) {
                const skip = [_][]const u8{ ".git", ".yoshida", "node_modules", "out", "zig-out", ".zig-cache" };
                var skipped = false;
                for (skip) |s| if (std.mem.eql(u8, e.basename, s)) {
                    skipped = true;
                };
                if (!skipped) try walker.enter(io, e);
                continue;
            }
            if (e.kind != .file and e.kind != .sym_link) continue;
            const p = try arena.dupe(u8, e.path);
            std.mem.replaceScalar(u8, p, '\\', '/');
            try files.append(arena, p);
        }
        std.mem.sort([]const u8, files.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lt);
        return .{ .io = io, .arena = arena, .dir = dir, .files = files.items };
    }

    fn vfs(d: *DiskFs) y.project.Vfs {
        return .{ .ctx = d, .readFn = read, .listFn = list };
    }

    fn read(ctx: *anyopaque, path: []const u8) ?[]const u8 {
        const d: *DiskFs = @ptrCast(@alignCast(ctx));
        if (d.cache.get(path)) |v| return v;
        const data: ?[]const u8 = if (y.project.isUrl(path)) d.download(path) else d.dir.readFileAlloc(d.io, path, d.arena, .limited(256 * 1024 * 1024)) catch null;
        const key = d.arena.dupe(u8, path) catch return data;
        d.cache.put(d.arena, key, data) catch {};
        return data;
    }

    fn download(d: *DiskFs, url: []const u8) ?[]const u8 {
        const client = d.http orelse return null;
        var body: std.Io.Writer.Allocating = .init(d.arena);
        const res = client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer }) catch |e| {
            if (d.log) |l| l.print("warning: cannot download {s}: {s}\n", .{ url, @errorName(e) }) catch {};
            return null;
        };
        if (res.status != .ok) {
            if (d.log) |l| l.print("warning: cannot download {s}: HTTP {d}\n", .{ url, @intFromEnum(res.status) }) catch {};
            return null;
        }
        return body.written();
    }

    fn list(ctx: *anyopaque, _: Allocator) Allocator.Error![]const []const u8 {
        const d: *DiskFs = @ptrCast(@alignCast(ctx));
        return d.files;
    }
};

/// `yoshida fmt`: canonical layout for every JSON file of a project (or one file).
fn formatCommand(io: Io, arena: Allocator, args: Args, out: *Io.Writer, err: *Io.Writer) !u8 {
    const target = args.project.?;
    var paths: std.ArrayList([]const u8) = .empty;
    var base: []const u8 = "";
    if (std.mem.endsWith(u8, target, ".json")) {
        try paths.append(arena, target);
    } else {
        const disk = DiskFs.open(io, arena, target) catch |e| {
            try err.print("error: cannot open project folder '{s}': {s}\n", .{ target, @errorName(e) });
            return 1;
        };
        base = target;
        for (disk.files) |f| if (std.mem.endsWith(u8, f, ".json")) try paths.append(arena, try std.fs.path.join(arena, &.{ base, f }));
    }
    var changed: usize = 0;
    var failed: usize = 0;
    for (paths.items) |p| {
        const src = Io.Dir.cwd().readFileAlloc(io, p, arena, .limited(64 * 1024 * 1024)) catch |e| {
            try err.print("error: cannot read '{s}': {s}\n", .{ p, @errorName(e) });
            failed += 1;
            continue;
        };
        const formatted = (try y.fmt.formatSource(arena, src)) orelse {
            try err.print("error: '{s}' is not valid JSON; run 'yoshida check' for details\n", .{p});
            failed += 1;
            continue;
        };
        if (std.mem.eql(u8, formatted, src)) continue;
        changed += 1;
        if (args.check) {
            try out.print("not formatted: {s}\n", .{p});
            continue;
        }
        Io.Dir.cwd().writeFile(io, .{ .sub_path = p, .data = formatted }) catch |e| {
            try err.print("error: cannot write '{s}': {s}\n", .{ p, @errorName(e) });
            failed += 1;
            continue;
        };
        try out.print("formatted {s}\n", .{p});
    }
    try out.print("{d} file(s) checked, {d} {s}\n", .{ paths.items.len, changed, if (args.check) "not formatted" else "reformatted" });
    if (failed > 0) return 1;
    return if (args.check and changed > 0) 1 else 0;
}
