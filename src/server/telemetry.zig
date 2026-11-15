//! Optional usage statistics for the server that hosts the editor.
//!
//! Everything stays on this server: nothing is uploaded anywhere. The store
//! only holds counters per UTC day, never a person, an address or any project
//! content.
//!
//!   basic     one anonymous ping per editor session. The server counts
//!             unique visitors per day with SHA-256(daily random salt, client
//!             address, user agent). The salt lives in memory only and is
//!             replaced at UTC midnight, the hashes are never written to disk,
//!             and the address itself is never stored or logged.
//!   advanced  (opt-in in the editor) counts of feature, export and error-code
//!             names. Names are short lowercase tokens; no text, file names,
//!             card data or numbers other than the counts.
//!
//! This file has no HTTP code, so it can be tested on its own; main.zig does
//! the routing.

const std = @import("std");
const y = @import("yoshida");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Level = enum {
    off,
    basic,
    advanced,

    pub fn parse(s: []const u8) ?Level {
        inline for (@typeInfo(Level).@"enum".fields) |f| {
            if (std.ascii.eqlIgnoreCase(s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    pub fn name(l: Level) []const u8 {
        return @tagName(l);
    }
};

pub const Config = struct {
    /// false: no endpoints, no storage, the editor shows no notice.
    enabled: bool = true,
    /// Where the day files and public.json live. Unwritable: counts stay in memory.
    dir: []const u8 = "telemetry-data",
    /// The level the editor starts with (the notice preselects it).
    default_level: Level = .basic,
    /// Locks the level for everybody. Only .off and .basic are allowed: a
    /// server can take data collection away from its users, never add to it.
    force: ?Level = null,
    /// Days to keep. null keeps everything.
    retention_days: ?u32 = 90,
    /// Use the first X-Forwarded-For address (behind a reverse proxy).
    trust_proxy: bool = false,
    /// Enables the hidden admin page and API. At least `min_token_len` bytes.
    admin_token: ?[]const u8 = null,
};

pub const min_token_len = 16;
pub const max_events_per_request = 50;
pub const max_name_len = 40;
/// Distinct event names kept per day; further new names are dropped.
pub const max_keys_per_day = 400;
/// Hashes remembered for the unique count; past it, only sessions are counted.
pub const max_seen = 200_000;
pub const max_public_flags = 200;
pub const max_body = 8 * 1024;

pub const notice_blurb = "Anonymous counts only, kept on the server that hosts this editor.";

/// The groups an event name can belong to.
pub const kinds = [_][]const u8{ "feature", "export", "error" };

/// The per-day counters that are not events.
pub const base_stats = [_][]const u8{ "sessions", "uniques", "advanced_sessions" };

const Day = struct {
    sessions: u64 = 0,
    uniques: u64 = 0,
    advanced_sessions: u64 = 0,
    /// "kind:name" to count.
    events: std.StringArrayHashMapUnmanaged(u64) = .empty,
    dirty: bool = false,
};

pub const Store = struct {
    gpa: Allocator,
    io: Io,
    cfg: Config,
    mutex: Io.Mutex = .init,
    /// Epoch day to counters.
    days: std.AutoArrayHashMapUnmanaged(u32, Day) = .empty,
    salt: [32]u8 = @splat(0),
    salt_day: u32 = std.math.maxInt(u32),
    seen: std.AutoHashMapUnmanaged([16]u8, void) = .empty,
    /// Keys the public stats endpoint may show.
    public: std.StringArrayHashMapUnmanaged(void) = .empty,
    public_dirty: bool = false,
    /// false when the data dir could not be used.
    persist: bool = false,
    purged_day: u32 = std.math.maxInt(u32),

    pub fn init(gpa: Allocator, io: Io, cfg: Config) Store {
        return .{ .gpa = gpa, .io = io, .cfg = cfg };
    }

    pub fn deinit(s: *Store) void {
        for (s.days.values()) |*d| freeDay(s.gpa, d);
        s.days.deinit(s.gpa);
        for (s.public.keys()) |k| s.gpa.free(k);
        s.public.deinit(s.gpa);
        s.seen.deinit(s.gpa);
    }

    fn lock(s: *Store) void {
        s.mutex.lockUncancelable(s.io);
    }
    fn unlock(s: *Store) void {
        s.mutex.unlock(s.io);
    }

    // ------------------------------------------------------------ recording

    /// Replaces the salt and forgets the hashes when the UTC day changes.
    /// The old salt is overwritten, so yesterday's hashes cannot be rebuilt.
    fn rotate(s: *Store, day: u32) void {
        if (s.salt_day == day) return;
        s.io.random(&s.salt);
        s.salt_day = day;
        s.seen.clearRetainingCapacity();
    }

    fn today(s: *Store, day: u32) !*Day {
        const gop = try s.days.getOrPut(s.gpa, day);
        if (!gop.found_existing) gop.value_ptr.* = .{};
        return gop.value_ptr;
    }

    /// One editor session started. `client` identifies the visitor for the
    /// unique count only (address bytes or text); it is hashed and dropped.
    pub fn ping(s: *Store, now_secs: i64, client: []const u8, user_agent: []const u8, level: Level) !void {
        const day = epochDay(now_secs);
        s.lock();
        defer s.unlock();
        s.rotate(day);
        const d = try s.today(day);
        d.sessions += 1;
        if (level == .advanced) d.advanced_sessions += 1;
        d.dirty = true;
        if (s.seen.count() < max_seen) {
            var h: [32]u8 = undefined;
            var sha = std.crypto.hash.sha2.Sha256.init(.{});
            sha.update(&s.salt);
            sha.update(client);
            sha.update(&.{0});
            sha.update(user_agent[0..@min(user_agent.len, 256)]);
            sha.final(&h);
            const gop = try s.seen.getOrPut(s.gpa, h[0..16].*);
            if (!gop.found_existing) d.uniques += 1;
        }
    }

    pub const EventResult = struct { accepted: usize, dropped: usize };

    /// Counts the events of a request body: {"events":[{"k":"feature","n":"layer.rect"}]}.
    pub fn events(s: *Store, now_secs: i64, body: []const u8) !EventResult {
        var arena_state = std.heap.ArenaAllocator.init(s.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const doc = switch (try y.json.parse(arena, body)) {
            .ok => |n| n,
            .err => return error.BadRequest,
        };
        const list = doc.get("events") orelse return error.BadRequest;
        if (list.data != .array) return error.BadRequest;
        if (list.data.array.len > max_events_per_request) return error.BadRequest;

        const day = epochDay(now_secs);
        s.lock();
        defer s.unlock();
        s.rotate(day);
        const d = try s.today(day);
        var res: EventResult = .{ .accepted = 0, .dropped = 0 };
        var key_buf: [kinds[0].len + 1 + max_name_len + 8]u8 = undefined;
        for (list.data.array) |item| {
            const k = if (item.get("k")) |v| (if (v.data == .string) v.data.string else "") else "";
            const n = if (item.get("n")) |v| (if (v.data == .string) v.data.string else "") else "";
            if (!validEvent(k, n)) {
                res.dropped += 1;
                continue;
            }
            const key = std.fmt.bufPrint(&key_buf, "{s}:{s}", .{ k, n }) catch unreachable;
            if (d.events.getPtr(key)) |c| {
                c.* += 1;
            } else if (d.events.count() < max_keys_per_day) {
                try d.events.put(s.gpa, try s.gpa.dupe(u8, key), 1);
            } else {
                res.dropped += 1;
                continue;
            }
            d.dirty = true;
            res.accepted += 1;
        }
        return res;
    }

    // ---------------------------------------------------------- public flags

    /// Replaces the set of public keys. Every key must be a base stat, a
    /// group ("feature") or a "group:name" event; anything else is refused
    /// and nothing changes.
    pub fn setPublic(s: *Store, keys: []const []const u8) !void {
        if (keys.len > max_public_flags) return error.BadRequest;
        for (keys) |k| if (!validFlag(k)) return error.BadRequest;
        s.lock();
        defer s.unlock();
        for (s.public.keys()) |k| s.gpa.free(k);
        s.public.clearRetainingCapacity();
        for (keys) |k| {
            if (s.public.contains(k)) continue;
            try s.public.put(s.gpa, try s.gpa.dupe(u8, k), {});
        }
        s.public_dirty = true;
    }

    /// Whether `key` ("sessions", "feature:layer.rect") is public.
    fn isPublic(s: *const Store, key: []const u8) bool {
        if (s.public.contains(key)) return true;
        if (std.mem.indexOfScalar(u8, key, ':')) |i| return s.public.contains(key[0..i]);
        return false;
    }

    // ---------------------------------------------------------------- output

    /// {"retention_days","stats":[...days, oldest first...],"public":[...keys]}. A day is
    /// {"day","sessions","uniques","advanced_sessions","events":{...}}.
    /// `last_days` limits the output to that many days up to `now_secs`;
    /// `public_only` hides everything that is not flagged (the public endpoint).
    pub fn statsJson(s: *Store, arena: Allocator, now_secs: i64, last_days: u32, public_only: bool) ![]u8 {
        s.lock();
        defer s.unlock();
        const today_n = epochDay(now_secs);
        const first = today_n -| (last_days -| 1);

        var order: std.ArrayList(u32) = .empty;
        for (s.days.keys()) |k| if (k >= first and k <= today_n) try order.append(arena, k);
        std.mem.sort(u32, order.items, {}, std.sort.asc(u32));

        var aw: Io.Writer.Allocating = .init(arena);
        const w = &aw.writer;
        try w.writeAll("{\"retention_days\":");
        if (s.cfg.retention_days) |r| try w.print("{d}", .{r}) else try w.writeAll("null");
        try w.writeAll(",\"days\":[");
        for (order.items, 0..) |dn, i| {
            const d = s.days.getPtr(dn).?;
            if (i > 0) try w.writeAll(",");
            var date_buf: [10]u8 = undefined;
            try w.print("{{\"day\":\"{s}\"", .{fmtDay(&date_buf, dn)});
            inline for (base_stats) |b| {
                if (!public_only or s.isPublic(b)) try w.print(",\"{s}\":{d}", .{ b, @field(d, b) });
            }
            try w.writeAll(",\"events\":{");
            var first_ev = true;
            // Sorted, so the output is stable.
            const ks = try arena.dupe([]const u8, d.events.keys());
            std.mem.sort([]const u8, ks, {}, lessString);
            for (ks) |k| {
                if (public_only and !s.isPublic(k)) continue;
                if (!first_ev) try w.writeAll(",");
                first_ev = false;
                try y.json.writeString(w, k);
                try w.print(":{d}", .{d.events.get(k).?});
            }
            try w.writeAll("}}");
        }
        try w.writeAll("]");
        if (!public_only) {
            try w.writeAll(",\"public\":[");
            for (s.public.keys(), 0..) |k, i| {
                if (i > 0) try w.writeAll(",");
                try y.json.writeString(w, k);
            }
            try w.writeAll("]");
        }
        try w.writeAll("}");
        return aw.toOwnedSlice();
    }

    // ----------------------------------------------------------- persistence

    /// Reads the day files and public.json from the data dir, creating the
    /// dir when it is missing, and applies the retention. Never fails: an
    /// unusable dir only means counts are not kept across restarts.
    pub fn load(s: *Store, now_secs: i64) void {
        const cwd = Io.Dir.cwd();
        cwd.createDirPath(s.io, s.cfg.dir) catch |e| {
            std.debug.print("telemetry: cannot use {s} ({s}); counts are kept in memory only\n", .{ s.cfg.dir, @errorName(e) });
            return;
        };
        var dir = cwd.openDir(s.io, s.cfg.dir, .{ .iterate = true }) catch return;
        defer dir.close(s.io);
        s.persist = true;

        var arena_state = std.heap.ArenaAllocator.init(s.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var names: std.ArrayList([]const u8) = .empty;
        var it = dir.iterate();
        while (it.next(s.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            names.append(arena, arena.dupe(u8, entry.name) catch continue) catch continue;
        }
        s.lock();
        defer s.unlock();
        for (names.items) |name| {
            const data = dir.readFileAlloc(s.io, name, arena, .limited(4 * 1024 * 1024)) catch continue;
            if (std.mem.eql(u8, name, "public.json")) {
                s.loadPublic(arena, data);
            } else if (dayOfFile(name)) |dn| {
                s.loadDay(arena, dn, data) catch {};
            }
        }
        s.purgeLocked(&dir, epochDay(now_secs));
    }

    fn loadPublic(s: *Store, arena: Allocator, data: []const u8) void {
        const doc = switch (y.json.parse(arena, data) catch return) {
            .ok => |n| n,
            .err => return,
        };
        const list = doc.get("public") orelse return;
        if (list.data != .array) return;
        for (list.data.array) |item| {
            if (item.data != .string or !validFlag(item.data.string)) continue;
            if (s.public.contains(item.data.string)) continue;
            s.public.put(s.gpa, s.gpa.dupe(u8, item.data.string) catch continue, {}) catch continue;
        }
    }

    fn loadDay(s: *Store, arena: Allocator, dn: u32, data: []const u8) !void {
        const doc = switch (try y.json.parse(arena, data)) {
            .ok => |n| n,
            .err => return,
        };
        const d = try s.today(dn);
        inline for (base_stats) |b| {
            if (doc.get(b)) |v| if (v.data == .number and v.data.number >= 0) {
                @field(d, b) = @intFromFloat(@min(v.data.number, 1e15));
            };
        }
        if (doc.get("events")) |evs| if (evs.data == .object) {
            for (evs.data.object) |f| {
                if (f.value.data != .number or f.value.data.number < 0) continue;
                const colon = std.mem.indexOfScalar(u8, f.key, ':') orelse continue;
                if (!validEvent(f.key[0..colon], f.key[colon + 1 ..])) continue;
                try d.events.put(s.gpa, try s.gpa.dupe(u8, f.key), @intFromFloat(@min(f.value.data.number, 1e15)));
            }
        };
    }

    /// Writes the days and the public flags that changed. Called every few
    /// seconds by the flush loop.
    pub fn flush(s: *Store, now_secs: i64) void {
        var arena_state = std.heap.ArenaAllocator.init(s.gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        s.lock();
        defer s.unlock();
        if (!s.persist) return;
        var dir = Io.Dir.cwd().openDir(s.io, s.cfg.dir, .{ .iterate = true }) catch return;
        defer dir.close(s.io);

        for (s.days.keys(), s.days.values()) |dn, *d| {
            if (!d.dirty) continue;
            const text = dayJson(arena, dn, d) catch continue;
            const file = dayFileName(dn);
            if (writeAtomic(s.io, dir, &file, text)) d.dirty = false else |_| {}
        }
        if (s.public_dirty) {
            var aw: Io.Writer.Allocating = .init(arena);
            const w = &aw.writer;
            w.writeAll("{\"public\":[") catch return;
            for (s.public.keys(), 0..) |k, i| {
                if (i > 0) w.writeAll(",") catch return;
                y.json.writeString(w, k) catch return;
            }
            w.writeAll("]}\n") catch return;
            if (writeAtomic(s.io, dir, "public.json", aw.written())) s.public_dirty = false else |_| {}
        }
        s.purgeLocked(&dir, epochDay(now_secs));
    }

    /// Deletes the days older than the retention, once per UTC day.
    fn purgeLocked(s: *Store, dir: *Io.Dir, today_n: u32) void {
        const keep = s.cfg.retention_days orelse return;
        if (s.purged_day == today_n) return;
        s.purged_day = today_n;
        const oldest = today_n -| (keep -| 1);
        var i: usize = 0;
        while (i < s.days.count()) {
            const dn = s.days.keys()[i];
            if (dn >= oldest) {
                i += 1;
                continue;
            }
            const file = dayFileName(dn);
            dir.deleteFile(s.io, &file) catch {};
            freeDay(s.gpa, s.days.getPtr(dn).?);
            s.days.swapRemoveAt(i);
        }
        // Files left on disk from before this start (unparsed or foreign dates).
        var it = dir.iterate();
        var stale: std.ArrayList([32]u8) = .empty;
        defer stale.deinit(s.gpa);
        while (it.next(s.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            const dn = dayOfFile(entry.name) orelse continue;
            if (dn >= oldest or entry.name.len > 32) continue;
            var nm: [32]u8 = @splat(0);
            @memcpy(nm[0..entry.name.len], entry.name);
            stale.append(s.gpa, nm) catch {};
        }
        for (stale.items) |nm| dir.deleteFile(s.io, std.mem.sliceTo(&nm, 0)) catch {};
    }
};

fn freeDay(gpa: Allocator, d: *Day) void {
    for (d.events.keys()) |k| gpa.free(k);
    d.events.deinit(gpa);
}

fn lessString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn writeAtomic(io: Io, dir: Io.Dir, name: []const u8, data: []const u8) !void {
    var tmp_buf: [48]u8 = undefined;
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{name});
    try dir.writeFile(io, .{ .sub_path = tmp, .data = data });
    try dir.rename(tmp, dir, name, io);
}

fn dayJson(arena: Allocator, dn: u32, d: *const Day) ![]u8 {
    var aw: Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    var date_buf: [10]u8 = undefined;
    try w.print("{{\"day\":\"{s}\"", .{fmtDay(&date_buf, dn)});
    inline for (base_stats) |b| try w.print(",\"{s}\":{d}", .{ b, @field(d, b) });
    try w.writeAll(",\"events\":{");
    for (d.events.keys(), d.events.values(), 0..) |k, v, i| {
        if (i > 0) try w.writeAll(",");
        try y.json.writeString(w, k);
        try w.print(":{d}", .{v});
    }
    try w.writeAll("}}\n");
    return aw.toOwnedSlice();
}

// ------------------------------------------------------------------ helpers

pub fn epochDay(secs: i64) u32 {
    return @intCast(@divFloor(@max(secs, 0), std.time.s_per_day));
}

/// "2026-11-09" for an epoch day.
pub fn fmtDay(buf: *[10]u8, dn: u32) []const u8 {
    const ed: std.time.epoch.EpochDay = .{ .day = dn };
    const yd = ed.calculateYearDay();
    const md = yd.calculateMonthDay();
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ yd.year, md.month.numeric(), md.day_index + 1 }) catch unreachable;
}

fn dayFileName(dn: u32) [15]u8 {
    var date: [10]u8 = undefined;
    _ = fmtDay(&date, dn);
    var out: [15]u8 = undefined;
    @memcpy(out[0..10], &date);
    @memcpy(out[10..], ".json");
    return out;
}

/// The epoch day of a "YYYY-MM-DD.json" file name.
fn dayOfFile(name: []const u8) ?u32 {
    if (name.len != 15 or !std.mem.endsWith(u8, name, ".json")) return null;
    if (name[4] != '-' or name[7] != '-') return null;
    const yr = std.fmt.parseInt(u16, name[0..4], 10) catch return null;
    const mo = std.fmt.parseInt(u8, name[5..7], 10) catch return null;
    const dd = std.fmt.parseInt(u8, name[8..10], 10) catch return null;
    if (yr < 1970 or mo < 1 or mo > 12 or dd < 1) return null;
    const month: std.time.epoch.Month = @enumFromInt(mo);
    if (dd > std.time.epoch.getDaysInMonth(yr, month)) return null;
    var days: u32 = 0;
    var yy: u16 = 1970;
    while (yy < yr) : (yy += 1) days += std.time.epoch.getDaysInYear(yy);
    var mm: u8 = 1;
    while (mm < mo) : (mm += 1) days += std.time.epoch.getDaysInMonth(yr, @enumFromInt(mm));
    return days + dd - 1;
}

fn nameChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '.' or c == '_' or c == '-';
}

fn validName(n: []const u8) bool {
    if (n.len == 0 or n.len > max_name_len) return false;
    for (n) |c| if (!nameChar(c)) return false;
    return true;
}

/// A kind from `kinds` and a short lowercase token. Error names are the
/// four-digit diagnostic codes only.
pub fn validEvent(kind: []const u8, name: []const u8) bool {
    var known = false;
    for (kinds) |k| if (std.mem.eql(u8, k, kind)) {
        known = true;
    };
    if (!known or !validName(name)) return false;
    if (std.mem.eql(u8, kind, "error")) {
        if (name.len != 4) return false;
        for (name) |c| if (c < '0' or c > '9') return false;
    }
    return true;
}

/// A base stat, a kind, or "kind:name".
pub fn validFlag(key: []const u8) bool {
    for (base_stats) |b| if (std.mem.eql(u8, b, key)) return true;
    for (kinds) |k| if (std.mem.eql(u8, k, key)) return true;
    const colon = std.mem.indexOfScalar(u8, key, ':') orelse return false;
    return validEvent(key[0..colon], key[colon + 1 ..]);
}

/// Compares in constant time for equal lengths. The length of the real token
/// is not a secret worth hiding.
pub fn tokenOk(cfg: Config, supplied: []const u8) bool {
    const token = cfg.admin_token orelse return false;
    if (token.len < min_token_len or token.len != supplied.len) return false;
    var diff: u8 = 0;
    for (token, supplied) |a, b| diff |= a ^ b;
    return diff == 0;
}

/// "infinite" (or "0") to keep forever, else a number of days.
pub fn parseRetention(s: []const u8) ?(?u32) {
    const t = std.mem.trim(u8, s, " ");
    for ([_][]const u8{ "infinite", "inf", "forever", "never" }) |w| {
        if (std.ascii.eqlIgnoreCase(t, w)) return @as(?u32, null);
    }
    const n = std.fmt.parseInt(u32, t, 10) catch return null;
    return if (n == 0) @as(?u32, null) else @as(?u32, n);
}

/// A forced level can only be off or basic.
pub fn parseForce(s: []const u8) ?Level {
    const l = Level.parse(s) orelse return null;
    return if (l == .advanced) null else l;
}

// -------------------------------------------------------------------- tests

const testing = std.testing;

fn testStore(cfg: Config) Store {
    var s = Store.init(testing.allocator, testing.io, cfg);
    s.cfg.dir = ".zig-cache/telemetry-test";
    return s;
}

test "unique visitors are counted once per day and re-counted the next day" {
    var s = testStore(.{});
    defer s.deinit();
    const d0: i64 = 20_000 * std.time.s_per_day + 100;
    try s.ping(d0, "1.2.3.4", "ua", .basic);
    try s.ping(d0 + 5, "1.2.3.4", "ua", .basic);
    try s.ping(d0 + 6, "5.6.7.8", "ua", .advanced);
    try s.ping(d0 + 7, "1.2.3.4", "other-ua", .basic);
    const day = s.days.get(20_000).?;
    try testing.expectEqual(@as(u64, 4), day.sessions);
    try testing.expectEqual(@as(u64, 3), day.uniques);
    try testing.expectEqual(@as(u64, 1), day.advanced_sessions);

    const salt_before = s.salt;
    try s.ping(d0 + std.time.s_per_day, "1.2.3.4", "ua", .basic);
    try testing.expect(!std.mem.eql(u8, &salt_before, &s.salt));
    try testing.expectEqual(@as(u64, 1), s.days.get(20_001).?.uniques);
    try testing.expectEqual(@as(usize, 1), s.seen.count());
}

test "events are validated, counted and capped" {
    var s = testStore(.{});
    defer s.deinit();
    const now: i64 = 20_000 * std.time.s_per_day;
    const r = try s.events(now,
        \\{"events":[{"k":"feature","n":"layer.rect"},{"k":"feature","n":"layer.rect"},
        \\{"k":"export","n":"png"},{"k":"error","n":"4001"},{"k":"error","n":"my project"},
        \\{"k":"feature","n":"Has Capitals"},{"k":"secret","n":"x"},{"k":"feature"}]}
    );
    try testing.expectEqual(@as(usize, 4), r.accepted);
    try testing.expectEqual(@as(usize, 4), r.dropped);
    const d = s.days.get(20_000).?;
    try testing.expectEqual(@as(u64, 2), d.events.get("feature:layer.rect").?);
    try testing.expectEqual(@as(u64, 1), d.events.get("error:4001").?);
    try testing.expectError(error.BadRequest, s.events(now, "{\"events\":5}"));
    try testing.expectError(error.BadRequest, s.events(now, "not json"));
}

test "validators" {
    try testing.expect(validEvent("feature", "layer.rect"));
    try testing.expect(!validEvent("feature", ""));
    try testing.expect(!validEvent("feature", "a" ** 41));
    try testing.expect(!validEvent("error", "40012"));
    try testing.expect(!validEvent("error", "abcd"));
    try testing.expect(validFlag("sessions"));
    try testing.expect(validFlag("export"));
    try testing.expect(validFlag("export:pdf"));
    try testing.expect(!validFlag("export:PDF"));
    try testing.expect(!validFlag("ip"));
}

test "retention and force parsing" {
    try testing.expectEqual(@as(?(?u32), 90), parseRetention("90"));
    try testing.expectEqual(@as(?(?u32), null), parseRetention("nope"));
    try testing.expectEqual(@as(?(?u32), @as(?u32, null)), parseRetention("infinite"));
    try testing.expectEqual(@as(?(?u32), @as(?u32, null)), parseRetention("0"));
    try testing.expectEqual(@as(?Level, .off), parseForce("off"));
    try testing.expectEqual(@as(?Level, .basic), parseForce("Basic"));
    try testing.expectEqual(@as(?Level, null), parseForce("advanced"));
}

test "admin token compare" {
    const cfg: Config = .{ .admin_token = "0123456789abcdef" };
    try testing.expect(tokenOk(cfg, "0123456789abcdef"));
    try testing.expect(!tokenOk(cfg, "0123456789abcdeX"));
    try testing.expect(!tokenOk(cfg, ""));
    try testing.expect(!tokenOk(.{ .admin_token = "short" }, "short"));
    try testing.expect(!tokenOk(.{}, "anything"));
}

test "public flags filter the public stats" {
    var s = testStore(.{});
    defer s.deinit();
    const now: i64 = 20_000 * std.time.s_per_day;
    try s.ping(now, "a", "ua", .basic);
    _ = try s.events(now, "{\"events\":[{\"k\":\"feature\",\"n\":\"a\"},{\"k\":\"export\",\"n\":\"png\"}]}");
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const none = try s.statsJson(arena, now, 30, true);
    try testing.expect(std.mem.indexOf(u8, none, "sessions") == null);
    try testing.expect(std.mem.indexOf(u8, none, "feature:a") == null);

    try s.setPublic(&.{ "sessions", "feature" });
    const some = try s.statsJson(arena, now, 30, true);
    try testing.expect(std.mem.indexOf(u8, some, "\"sessions\":1") != null);
    try testing.expect(std.mem.indexOf(u8, some, "\"uniques\"") == null);
    try testing.expect(std.mem.indexOf(u8, some, "feature:a") != null);
    try testing.expect(std.mem.indexOf(u8, some, "export:png") == null);
    try testing.expect(std.mem.indexOf(u8, some, "\"public\"") == null);

    const full = try s.statsJson(arena, now, 30, false);
    try testing.expect(std.mem.indexOf(u8, full, "export:png") != null);
    try testing.expect(std.mem.indexOf(u8, full, "\"public\":[\"sessions\",\"feature\"]") != null);
    try testing.expectError(error.BadRequest, s.setPublic(&.{"client_ip"}));
}

test "day files round trip and retention deletes old days" {
    const dir = ".zig-cache/telemetry-test-rt";
    Io.Dir.cwd().deleteTree(testing.io, dir) catch {};
    defer Io.Dir.cwd().deleteTree(testing.io, dir) catch {};
    const now: i64 = 20_000 * std.time.s_per_day + 10;
    {
        var s = Store.init(testing.allocator, testing.io, .{ .dir = dir, .retention_days = 3 });
        defer s.deinit();
        s.load(now);
        try testing.expect(s.persist);
        // An old and a current day.
        try s.ping(now - 10 * std.time.s_per_day, "a", "ua", .basic);
        try s.ping(now - std.time.s_per_day, "a", "ua", .basic);
        _ = try s.events(now - std.time.s_per_day, "{\"events\":[{\"k\":\"export\",\"n\":\"zip\"}]}");
        try s.setPublic(&.{"sessions"});
        s.flush(now - 11 * std.time.s_per_day); // writes both days without purging them
    }
    var s = Store.init(testing.allocator, testing.io, .{ .dir = dir, .retention_days = 3 });
    defer s.deinit();
    s.load(now);
    try testing.expect(s.days.get(19_990) == null);
    const d = s.days.get(19_999).?;
    try testing.expectEqual(@as(u64, 1), d.sessions);
    try testing.expectEqual(@as(u64, 1), d.events.get("export:zip").?);
    try testing.expect(s.public.contains("sessions"));
}

test "infinite retention keeps old days" {
    const dir = ".zig-cache/telemetry-test-inf";
    Io.Dir.cwd().deleteTree(testing.io, dir) catch {};
    defer Io.Dir.cwd().deleteTree(testing.io, dir) catch {};
    const now: i64 = 20_000 * std.time.s_per_day;
    {
        var s = Store.init(testing.allocator, testing.io, .{ .dir = dir, .retention_days = null });
        defer s.deinit();
        s.load(now);
        try s.ping(now - 1000 * std.time.s_per_day, "a", "ua", .basic);
        s.flush(now);
    }
    var s = Store.init(testing.allocator, testing.io, .{ .dir = dir, .retention_days = null });
    defer s.deinit();
    s.load(now);
    try testing.expectEqual(@as(usize, 1), s.days.count());
}

test "date helpers" {
    var buf: [10]u8 = undefined;
    try testing.expectEqualStrings("2024-02-29", fmtDay(&buf, dayOfFile("2024-02-29.json").?));
    try testing.expect(dayOfFile("2023-02-29.json") == null);
    try testing.expect(dayOfFile("public.json") == null);
    try testing.expectEqual(@as(u32, 0), dayOfFile("1970-01-01.json").?);
}
