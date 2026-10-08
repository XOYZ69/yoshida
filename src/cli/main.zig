//! yoshida command-line interface.

const std = @import("std");
const y = @import("yoshida");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage =
    \\yoshida {s} (format {d})
    \\
    \\Usage:
    \\  yoshida check  <project>  [--format text|json]
    \\  yoshida render <project>  [--set NAME] [--card ID] [--out DIR]
    \\                            [--date YYYY-MM-DD] [--16bit] [--preview]
    \\                            [--offline] [--format text|json]
    \\  yoshida fmt    <project or file>  [--check]
    \\  yoshida version
    \\
    \\check   loads every design and card file and reports problems.
    \\render  writes <out>/<set>/<card id>.png (default out: <project>/out).
    \\        Images given as https:// URLs are downloaded (once per run);
    \\        --offline turns that off.
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
    sixteen: bool = false,
    preview: bool = false,
    json: bool = false,
    offline: bool = false,
    check: bool = false,
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
    if (is_render and diags.errorCount() == 0) {
        const date = args.date orelse try today(io, arena);
        const out_root = args.out orelse try std.fs.path.join(arena, &.{ args.project.?, "out" });
        var assets = y.render.Assets.init(gpa, disk.vfs());
        defer assets.deinit();
        var matched_set = args.set == null;
        for (proj.sets) |*set| {
            if (args.set) |s| if (!std.mem.eql(u8, s, set.name)) continue;
            matched_set = true;
            if (!set.ok) continue;
            const dir = try std.fs.path.join(arena, &.{ out_root, set.name });
            Io.Dir.cwd().createDirPath(io, dir) catch |e| {
                try err.print("error: cannot create '{s}': {s}\n", .{ dir, @errorName(e) });
                return 1;
            };
            for (set.cards, 0..) |card, i| {
                if (args.card) |cid| if (!std.mem.eql(u8, cid, card.id)) continue;
                var bmp = (try y.render.renderCard(gpa, &assets, set, i, .{ .date = date, .preview = args.preview }, &diags)) orelse continue;
                defer bmp.deinit(gpa);
                const png = try y.raster.encodePng(gpa, &bmp, args.sixteen);
                defer gpa.free(png);
                const file = try std.fmt.allocPrint(arena, "{s}/{s}.png", .{ dir, card.id });
                Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = png }) catch |e| {
                    try err.print("error: cannot write '{s}': {s}\n", .{ file, @errorName(e) });
                    return 1;
                };
                rendered += 1;
                try rendered_files.append(arena, file);
                if (!args.json) try out.print("wrote {s} ({d} x {d})\n", .{ file, bmp.w, bmp.h });
            }
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
        try out.writeAll("]}\n");
    } else {
        try diags.writeText(out);
        if (!is_render) {
            for (proj.sets) |s| {
                try out.print("set {s}: {s}, {d} card(s){s}\n", .{ s.name, s.design_path, s.cards.len, if (s.ok) "" else " (has errors)" });
            }
        }
        try out.print("{d} error(s), {d} warning(s), {d} hint(s)", .{ diags.count(.err), diags.count(.warning), diags.count(.hint) });
        if (is_render) try out.print(", {d} card(s) rendered", .{rendered});
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
            if (std.mem.eql(u8, name, "set")) a.set = v else if (std.mem.eql(u8, name, "card")) a.card = v else if (std.mem.eql(u8, name, "out")) a.out = v else if (std.mem.eql(u8, name, "date")) a.date = v else if (std.mem.eql(u8, name, "format")) {
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

fn today(io: Io, arena: Allocator) ![]const u8 {
    const ns = Io.Clock.real.now(io).nanoseconds;
    const secs: u64 = @intCast(@max(0, @divFloor(ns, std.time.ns_per_s)));
    const es: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    return std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2}", .{ yd.year, md.month.numeric(), md.day_index + 1 });
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
