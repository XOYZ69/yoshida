//! Dates, times and date-times as text: parsing, `date_fmt` patterns and day
//! arithmetic. Pure: no clock reads and no time-zone data. Day numbers use
//! Howard Hinnant's days-from-civil and civil-from-days algorithms.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Error = error{ BadDate, OutOfMemory, TooLong };

/// Longest text `format` will produce, in bytes.
pub const max_len = 10_000;

pub const Kind = enum { date, time, datetime };

pub const Parsed = struct {
    kind: Kind,
    y: i32 = 0,
    mo: u8 = 0,
    d: u8 = 0,
    h: u8 = 0,
    mi: u8 = 0,
    s: u8 = 0,
    z: bool = false,
};

const month_names = [_][]const u8{
    "January", "February", "March",     "April",   "May",      "June",
    "July",    "August",   "September", "October", "November", "December",
};

/// Monday first, as ISO weekdays number them.
const day_names = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };

/// Format tokens, longest first so that the first match is the longest one.
const Tok = enum { YYYY, MMMM, dddd, MMM, ddd, YY, MM, DD, HH, mm, ss, M, D, H };

/// Largest shift accepted by the arithmetic functions, in days or hours.
const max_shift: f64 = 1e9;

/// Parses `YYYY-MM-DD`, `HH:MM[:SS]` or `YYYY-MM-DDTHH:MM[:SS][Z]`.
pub fn parse(t: []const u8) Error!Parsed {
    if (t.len == 10) return parseDate(t);
    if (t.len == 5 or t.len == 8) return parseTime(t);
    if (t.len < 16 or t[10] != 'T') return error.BadDate;
    const z = t[t.len - 1] == 'Z';
    const body = if (z) t[0 .. t.len - 1] else t;
    const dt = try parseDate(body[0..10]);
    const tm = try parseTime(body[11..]);
    return .{ .kind = .datetime, .y = dt.y, .mo = dt.mo, .d = dt.d, .h = tm.h, .mi = tm.mi, .s = tm.s, .z = z };
}

fn parseDate(t: []const u8) Error!Parsed {
    if (t.len != 10 or t[4] != '-' or t[7] != '-') return error.BadDate;
    const y = try digits(t[0..4]);
    const mo = try digits(t[5..7]);
    const d = try digits(t[8..10]);
    if (y < 1 or mo < 1 or mo > 12 or d < 1 or d > daysInMonth(y, mo)) return error.BadDate;
    return .{ .kind = .date, .y = @intCast(y), .mo = @intCast(mo), .d = @intCast(d) };
}

fn parseTime(t: []const u8) Error!Parsed {
    if (t.len != 5 and t.len != 8) return error.BadDate;
    if (t[2] != ':') return error.BadDate;
    if (t.len == 8 and t[5] != ':') return error.BadDate;
    const h = try digits(t[0..2]);
    const mi = try digits(t[3..5]);
    const s = if (t.len == 8) try digits(t[6..8]) else 0;
    if (h > 23 or mi > 59 or s > 59) return error.BadDate;
    return .{ .kind = .time, .h = @intCast(h), .mi = @intCast(mi), .s = @intCast(s) };
}

/// Reads a string of ASCII digits; anything else is BadDate.
fn digits(s: []const u8) Error!i64 {
    var n: i64 = 0;
    for (s) |ch| {
        if (!std.ascii.isDigit(ch)) return error.BadDate;
        n = n * 10 + (ch - '0');
    }
    return n;
}

fn isLeap(y: i64) bool {
    return @mod(y, 4) == 0 and (@mod(y, 100) != 0 or @mod(y, 400) == 0);
}

fn daysInMonth(y: i64, m: i64) i64 {
    return switch (m) {
        2 => if (isLeap(y)) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
}

/// Days since 1970-01-01 of a proleptic Gregorian date.
fn daysFromCivil(y0: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y0 - 1 else y0;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

const Civil = struct { y: i64, m: i64, d: i64 };

/// Inverse of `daysFromCivil`.
fn civilFromDays(z0: i64) Civil {
    const z = z0 + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    const y = yoe + era * 400 + @intFromBool(m <= 2);
    return .{ .y = y, .m = m, .d = d };
}

fn dayNumber(p: Parsed) i64 {
    return daysFromCivil(p.y, p.mo, p.d);
}

/// ISO weekday, 1 = Monday. Day 0 (1970-01-01) is a Thursday.
fn isoWeekday(days: i64) i64 {
    return @mod(days + 3, 7) + 1;
}

/// Seconds since 1970-01-01T00:00:00 of a date or date-time (time-only reads as 0 days).
fn toSecs(p: Parsed) i64 {
    return dayNumber(p) * 86400 + @as(i64, p.h) * 3600 + @as(i64, p.mi) * 60 + p.s;
}

/// A date-time from seconds since the epoch; the year must stay in 1..9999.
fn fromSecs(total: i64) Error!Parsed {
    const days = @divFloor(total, 86400);
    const sod = total - days * 86400;
    const c = civilFromDays(days);
    if (c.y < 1 or c.y > 9999) return error.BadDate;
    return .{
        .kind = .datetime,
        .y = @intCast(c.y),
        .mo = @intCast(c.m),
        .d = @intCast(c.d),
        .h = @intCast(@divFloor(sod, 3600)),
        .mi = @intCast(@divFloor(@mod(sod, 3600), 60)),
        .s = @intCast(@mod(sod, 60)),
    };
}

/// Hours to whole seconds, rounded half away from zero.
fn hoursToSecs(h: f64) Error!i64 {
    if (!std.math.isFinite(h) or @abs(h) > max_shift) return error.BadDate;
    return @intFromFloat(@round(h * 3600.0));
}

pub fn year(p: Parsed) Error!f64 {
    if (p.kind == .time) return error.BadDate;
    return @floatFromInt(p.y);
}

pub fn month(p: Parsed) Error!f64 {
    if (p.kind == .time) return error.BadDate;
    return @floatFromInt(p.mo);
}

pub fn day(p: Parsed) Error!f64 {
    if (p.kind == .time) return error.BadDate;
    return @floatFromInt(p.d);
}

/// ISO weekday, 1 = Monday ... 7 = Sunday.
pub fn weekday(p: Parsed) Error!f64 {
    if (p.kind == .time) return error.BadDate;
    return @floatFromInt(isoWeekday(dayNumber(p)));
}

pub fn hour(p: Parsed) f64 {
    return @floatFromInt(p.h);
}

pub fn minute(p: Parsed) f64 {
    return @floatFromInt(p.mi);
}

/// Renders `p` with a pattern. Tokens are matched longest first; text in
/// `[...]` is copied without the brackets; any other byte is literal. Date
/// tokens on a time-only value are BadDate; time tokens on a date give 00.
/// Text over `max_len` bytes is TooLong.
pub fn format(arena: Allocator, p0: Parsed, pattern: []const u8) Error![]const u8 {
    var p = p0;
    try validate(p);
    if (p.kind == .date) {
        p.h = 0;
        p.mi = 0;
        p.s = 0;
    }
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < pattern.len) {
        if (pattern[i] == '[') {
            if (std.mem.indexOfScalarPos(u8, pattern, i + 1, ']')) |close| {
                try emit(arena, &out, pattern[i + 1 .. close]);
                i = close + 1;
                continue;
            }
        }
        if (token(pattern[i..])) |tok| {
            try writeToken(arena, &out, p, tok);
            i += @tagName(tok).len;
            continue;
        }
        try emit(arena, &out, pattern[i .. i + 1]);
        i += 1;
    }
    return out.items;
}

/// Appends to the output, refusing to grow it past `max_len`.
fn emit(arena: Allocator, out: *std.ArrayList(u8), bytes: []const u8) Error!void {
    if (bytes.len > max_len - out.items.len) return error.TooLong;
    try out.appendSlice(arena, bytes);
}

/// Rejects a caller-built value whose used fields are out of range.
fn validate(p: Parsed) Error!void {
    if (p.kind != .time) {
        if (p.y < 1 or p.y > 9999 or p.mo < 1 or p.mo > 12) return error.BadDate;
        if (p.d < 1 or p.d > daysInMonth(p.y, p.mo)) return error.BadDate;
    }
    if (p.kind != .date) {
        if (p.h > 23 or p.mi > 59 or p.s > 59) return error.BadDate;
    }
}

fn token(s: []const u8) ?Tok {
    for (std.enums.values(Tok)) |t| {
        if (std.mem.startsWith(u8, s, @tagName(t))) return t;
    }
    return null;
}

fn writeToken(arena: Allocator, out: *std.ArrayList(u8), p: Parsed, tok: Tok) Error!void {
    const is_time = switch (tok) {
        .HH, .H, .mm, .ss => true,
        else => false,
    };
    if (p.kind == .time and !is_time) return error.BadDate;
    const text: []const u8 = switch (tok) {
        .YYYY => try std.fmt.allocPrint(arena, "{d:0>4}", .{@as(u32, @intCast(p.y))}),
        .YY => try std.fmt.allocPrint(arena, "{d:0>2}", .{@as(u32, @intCast(@mod(p.y, 100)))}),
        .MMMM => month_names[p.mo - 1],
        .MMM => month_names[p.mo - 1][0..3],
        .MM => try std.fmt.allocPrint(arena, "{d:0>2}", .{p.mo}),
        .M => try std.fmt.allocPrint(arena, "{d}", .{p.mo}),
        .DD => try std.fmt.allocPrint(arena, "{d:0>2}", .{p.d}),
        .D => try std.fmt.allocPrint(arena, "{d}", .{p.d}),
        .dddd => day_names[@intCast(isoWeekday(dayNumber(p)) - 1)],
        .ddd => day_names[@intCast(isoWeekday(dayNumber(p)) - 1)][0..3],
        .HH => try std.fmt.allocPrint(arena, "{d:0>2}", .{p.h}),
        .H => try std.fmt.allocPrint(arena, "{d}", .{p.h}),
        .mm => try std.fmt.allocPrint(arena, "{d:0>2}", .{p.mi}),
        .ss => try std.fmt.allocPrint(arena, "{d:0>2}", .{p.s}),
    };
    try emit(arena, out, text);
}

/// Canonical text of a parsed value: date, time or date-time (`Z` kept).
fn render(arena: Allocator, p: Parsed) Error![]const u8 {
    return format(arena, p, switch (p.kind) {
        .date => "YYYY-MM-DD",
        .time => "HH:mm:ss",
        .datetime => if (p.z) "YYYY-MM-DDTHH:mm:ss[Z]" else "YYYY-MM-DDTHH:mm:ss",
    });
}

/// Adds `n` days (floored). A date stays a date; a date-time keeps its time and `Z`.
pub fn addDays(arena: Allocator, t: []const u8, n: f64) Error![]const u8 {
    const p = try parse(t);
    if (p.kind == .time) return error.BadDate;
    if (!std.math.isFinite(n) or @abs(n) > max_shift) return error.BadDate;
    const k: i64 = @intFromFloat(@floor(n));
    var r = try fromSecs(toSecs(p) + k * 86400);
    r.kind = p.kind;
    r.z = p.z;
    return render(arena, r);
}

/// Whole days from the date part of `a` to the date part of `b` (b - a).
pub fn daysBetween(a: []const u8, b: []const u8) Error!f64 {
    const pa = try parse(a);
    const pb = try parse(b);
    if (pa.kind == .time or pb.kind == .time) return error.BadDate;
    return @floatFromInt(dayNumber(pb) - dayNumber(pa));
}

/// Adds hours (rounded to whole seconds). A date or date-time gives a date-time.
pub fn addHours(arena: Allocator, t: []const u8, h: f64) Error![]const u8 {
    const p = try parse(t);
    if (p.kind == .time) return error.BadDate;
    const delta = try hoursToSecs(h);
    var r = try fromSecs(toSecs(p) + delta);
    r.z = p.z;
    return render(arena, r);
}

/// Shifts a UTC date-time by `offset_hours` and gives the local `YYYY-MM-DD` and `HH:MM:SS`.
pub fn localFromUtc(arena: Allocator, now: []const u8, offset_hours: f64) Error!struct { date: []const u8, time: []const u8 } {
    const p = try parse(now);
    if (p.kind != .datetime) return error.BadDate;
    const delta = try hoursToSecs(offset_hours);
    const r = try fromSecs(toSecs(p) + delta);
    const date = try format(arena, r, "YYYY-MM-DD");
    const time = try format(arena, r, "HH:mm:ss");
    return .{ .date = date, .time = time };
}

// ------------------------------------------------------------------ tests

fn testArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(testing.allocator);
}

test "parse valid dates, times and date-times" {
    const d = try parse("2024-02-29");
    try testing.expectEqual(Kind.date, d.kind);
    try testing.expectEqual(@as(i32, 2024), d.y);
    try testing.expectEqual(@as(u8, 2), d.mo);
    try testing.expectEqual(@as(u8, 29), d.d);
    try testing.expectEqual(@as(i32, 2000), (try parse("2000-02-29")).y);

    const tm = try parse("23:59");
    try testing.expectEqual(Kind.time, tm.kind);
    try testing.expectEqual(@as(u8, 23), tm.h);
    try testing.expectEqual(@as(u8, 59), tm.mi);
    try testing.expectEqual(@as(u8, 0), tm.s);
    const tms = try parse("00:00:07");
    try testing.expectEqual(@as(u8, 7), tms.s);

    const dt = try parse("2026-10-15T10:30:05Z");
    try testing.expectEqual(Kind.datetime, dt.kind);
    try testing.expectEqual(@as(i32, 2026), dt.y);
    try testing.expectEqual(@as(u8, 15), dt.d);
    try testing.expectEqual(@as(u8, 10), dt.h);
    try testing.expectEqual(@as(u8, 30), dt.mi);
    try testing.expectEqual(@as(u8, 5), dt.s);
    try testing.expect(dt.z);

    const dt2 = try parse("2026-10-15T08:00");
    try testing.expect(!dt2.z);
    try testing.expectEqual(@as(u8, 0), dt2.s);
    try testing.expect((try parse("2026-10-15T10:00Z")).z);
}

test "parse invalid text" {
    const bad = [_][]const u8{
        "2023-02-29",         "1900-02-29",       "0000-01-01",       "2026-13-01",         "2026-00-10",
        "2026-10-00",         "2026-1-5",         "2026/10/15",       "2026-10-15x",        "+2026-10-15",
        "24:00",              "10:60",            "10:00:60",         "10:0",               "10:00Z",
        "2026-10-15Z",        "2026-10-15 10:00", "2026-10-15t10:00", "2026-10-15T10:00ZZ", "2026-10-15T10:0Z",
        "2026-10-15T10:00:0", "2026-10-15T24:00", "10:00 junk",       "",
    };
    for (bad) |s| try testing.expectError(error.BadDate, parse(s));
}

test "format every token" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const p: Parsed = .{ .kind = .datetime, .y = 2026, .mo = 3, .d = 5, .h = 9, .mi = 5, .s = 3 };
    const cases = [_][2][]const u8{
        .{ "YYYY", "2026" },
        .{ "YY", "26" },
        .{ "MMMM", "March" },
        .{ "MMM", "Mar" },
        .{ "MM", "03" },
        .{ "M", "3" },
        .{ "DD", "05" },
        .{ "D", "5" },
        .{ "dddd", "Thursday" },
        .{ "ddd", "Thu" },
        .{ "HH", "09" },
        .{ "H", "9" },
        .{ "mm", "05" },
        .{ "ss", "03" },
        .{ "YYYY-MM-DD HH:mm:ss", "2026-03-05 09:05:03" },
        .{ "YYYYY", "2026Y" },
        .{ "dddddd", "Thursdaydd" },
        .{ "[MMMM] M", "MMMM 3" },
        .{ "[D", "[5" },
        .{ "[]", "" },
        .{ "D MMMM, [week] ddd", "5 March, week Thu" },
        .{ "HH:mm", "09:05" },
    };
    for (cases) |c| try testing.expectEqualStrings(c[1], try format(arena, p, c[0]));
}

test "format on time-only and date-only values" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const tm = try parse("09:05:03");
    try testing.expectEqualStrings("09:05:03", try format(arena, tm, "HH:mm:ss"));
    try testing.expectError(error.BadDate, format(arena, tm, "YYYY"));
    try testing.expectError(error.BadDate, format(arena, tm, "DD MMM"));
    const dt = try parse("2026-10-15");
    try testing.expectEqualStrings("00:00:00", try format(arena, dt, "HH:mm:ss"));
    try testing.expectEqualStrings("0:m", try format(arena, dt, "H:m"));
}

test "weekday of known dates" {
    try testing.expectEqual(@as(f64, 4), try weekday(try parse("2026-10-15")));
    try testing.expectEqual(@as(f64, 6), try weekday(try parse("2000-01-01")));
    try testing.expectEqual(@as(f64, 4), try weekday(try parse("1970-01-01")));
    try testing.expectEqual(@as(f64, 4), try weekday(try parse("2024-02-29")));
    try testing.expectEqual(@as(f64, 7), try weekday(try parse("2026-10-18")));
    try testing.expectError(error.BadDate, weekday(try parse("10:00")));
}

test "year month day hour minute" {
    const p = try parse("2026-10-15");
    try testing.expectEqual(@as(f64, 2026), try year(p));
    try testing.expectEqual(@as(f64, 10), try month(p));
    try testing.expectEqual(@as(f64, 15), try day(p));
    try testing.expectEqual(@as(f64, 0), hour(p));
    try testing.expectEqual(@as(f64, 0), minute(p));

    const dt = try parse("2026-10-15T10:30:00");
    try testing.expectEqual(@as(f64, 10), hour(dt));
    try testing.expectEqual(@as(f64, 30), minute(dt));

    const tm = try parse("10:30");
    try testing.expectEqual(@as(f64, 30), minute(tm));
    try testing.expectError(error.BadDate, year(tm));
    try testing.expectError(error.BadDate, month(tm));
    try testing.expectError(error.BadDate, day(tm));
}

test "addDays across month, year and leap boundaries" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cases = [_][3][]const u8{
        .{ "2026-10-15", "1", "2026-10-16" },
        .{ "2026-12-31", "1", "2027-01-01" },
        .{ "2024-02-28", "1", "2024-02-29" },
        .{ "2024-02-28", "2", "2024-03-01" },
        .{ "2023-02-28", "1", "2023-03-01" },
        .{ "2026-03-01", "-1", "2026-02-28" },
        .{ "2024-03-01", "-1", "2024-02-29" },
        .{ "2026-01-01", "-1", "2025-12-31" },
        .{ "2026-10-15", "365", "2027-10-15" },
        .{ "2026-10-15", "366", "2027-10-16" },
        .{ "2026-10-15", "0.9", "2026-10-15" },
        .{ "2026-10-15", "-0.5", "2026-10-14" },
        .{ "2026-10-15T10:00", "1", "2026-10-16T10:00:00" },
        .{ "2026-12-31T23:30:00Z", "1", "2027-01-01T23:30:00Z" },
        .{ "2026-10-15T00:00:00Z", "-1", "2026-10-14T00:00:00Z" },
    };
    for (cases) |c| {
        const n = try std.fmt.parseFloat(f64, c[1]);
        try testing.expectEqualStrings(c[2], try addDays(arena, c[0], n));
    }
    try testing.expectError(error.BadDate, addDays(arena, "9999-12-31", 1));
    try testing.expectError(error.BadDate, addDays(arena, "0001-01-01", -1));
    try testing.expectError(error.BadDate, addDays(arena, "10:00", 1));
    try testing.expectError(error.BadDate, addDays(arena, "2026-10-15", std.math.nan(f64)));
}

test "daysBetween in both directions" {
    try testing.expectEqual(@as(f64, 1), try daysBetween("2026-10-15", "2026-10-16"));
    try testing.expectEqual(@as(f64, -1), try daysBetween("2026-10-16", "2026-10-15"));
    try testing.expectEqual(@as(f64, 2), try daysBetween("2024-02-28", "2024-03-01"));
    try testing.expectEqual(@as(f64, 0), try daysBetween("2026-10-15", "2026-10-15"));
    try testing.expectEqual(@as(f64, 10957), try daysBetween("1970-01-01", "2000-01-01"));
    try testing.expectEqual(@as(f64, 1), try daysBetween("2026-10-15T23:59:59Z", "2026-10-16T00:00:01"));
    try testing.expectError(error.BadDate, daysBetween("10:00", "2026-10-16"));
    try testing.expectError(error.BadDate, daysBetween("2026-10-15", "2026-02-30"));
}

test "addHours crosses midnight, keeps Z and rounds fractions" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("2026-10-16T00:30:00Z", try addHours(arena, "2026-10-15T23:30:00Z", 1));
    try testing.expectEqualStrings("2026-10-15T11:30:00", try addHours(arena, "2026-10-15T10:00", 1.5));
    try testing.expectEqualStrings("2026-10-16T00:00:00", try addHours(arena, "2026-10-15T23:45", 0.25));
    try testing.expectEqualStrings("2026-10-14T23:30:00Z", try addHours(arena, "2026-10-15T00:00:00Z", -0.5));
    try testing.expectEqualStrings("2026-10-16T00:00:00", try addHours(arena, "2026-10-15", 24));
    try testing.expectEqualStrings("2027-01-01T01:00:00Z", try addHours(arena, "2026-12-31T23:00:00Z", 2));
    try testing.expectEqualStrings("2025-12-31T23:00:00", try addHours(arena, "2026-01-01T00:00:00", -1));
    // 2.6 seconds rounds to 3; 0.4 seconds rounds to 0.
    try testing.expectEqualStrings("2026-10-15T10:00:03", try addHours(arena, "2026-10-15T10:00:00", 2.6 / 3600.0));
    try testing.expectEqualStrings("2026-10-15T10:00:00", try addHours(arena, "2026-10-15T10:00:00", 0.4 / 3600.0));
    try testing.expectError(error.BadDate, addHours(arena, "10:00", 1));
    try testing.expectError(error.BadDate, addHours(arena, "2026-10-15T10:00", std.math.nan(f64)));
}

test "localFromUtc with positive, negative and half-hour offsets" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const plus2 = try localFromUtc(arena, "2026-10-15T23:30:00Z", 2);
    try testing.expectEqualStrings("2026-10-16", plus2.date);
    try testing.expectEqualStrings("01:30:00", plus2.time);

    const minus4 = try localFromUtc(arena, "2026-10-15T01:15", -4);
    try testing.expectEqualStrings("2026-10-14", minus4.date);
    try testing.expectEqualStrings("21:15:00", minus4.time);

    const plus55 = try localFromUtc(arena, "2026-10-15T20:00:00Z", 5.5);
    try testing.expectEqualStrings("2026-10-16", plus55.date);
    try testing.expectEqualStrings("01:30:00", plus55.time);

    const newYear = try localFromUtc(arena, "2026-01-01T02:00:00Z", -4);
    try testing.expectEqualStrings("2025-12-31", newYear.date);
    try testing.expectEqualStrings("22:00:00", newYear.time);

    const zero = try localFromUtc(arena, "2026-10-15T12:00:00Z", 0);
    try testing.expectEqualStrings("2026-10-15", zero.date);
    try testing.expectEqualStrings("12:00:00", zero.time);

    try testing.expectError(error.BadDate, localFromUtc(arena, "2026-10-15", 2));
    try testing.expectError(error.BadDate, localFromUtc(arena, "10:00", 2));
    try testing.expectError(error.BadDate, localFromUtc(arena, "2026-10-15T10:00Z", std.math.inf(f64)));
}

test "format at the year range ends" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const first: Parsed = .{ .kind = .datetime, .y = 1, .mo = 1, .d = 1 };
    try testing.expectEqualStrings("0001-01-01 Monday", try format(arena, first, "YYYY-MM-DD dddd"));
    try testing.expectEqualStrings("01", try format(arena, first, "YY"));
    const last: Parsed = .{ .kind = .date, .y = 9999, .mo = 12, .d = 31 };
    try testing.expectEqualStrings("9999-12-31", try format(arena, last, "YYYY-MM-DD"));
    try testing.expectEqualStrings("99", try format(arena, last, "YY"));
}

test "format rejects out-of-range caller-built values" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const bad = [_]Parsed{
        .{ .kind = .date, .y = 0, .mo = 1, .d = 1 },
        .{ .kind = .date, .y = 10000, .mo = 1, .d = 1 },
        .{ .kind = .date, .y = 2026, .mo = 0, .d = 1 },
        .{ .kind = .date, .y = 2026, .mo = 13, .d = 1 },
        .{ .kind = .date, .y = 2026, .mo = 1, .d = 0 },
        .{ .kind = .date, .y = 2026, .mo = 1, .d = 32 },
        .{ .kind = .date, .y = 2026, .mo = 4, .d = 31 },
        .{ .kind = .date, .y = 2023, .mo = 2, .d = 29 },
        .{ .kind = .datetime, .y = 2026, .mo = 1, .d = 1, .h = 24 },
        .{ .kind = .datetime, .y = 2026, .mo = 1, .d = 1, .mi = 60 },
        .{ .kind = .datetime, .y = 2026, .mo = 1, .d = 1, .s = 60 },
        .{ .kind = .time, .h = 23, .mi = 59, .s = 60 },
    };
    for (bad) |p| try testing.expectError(error.BadDate, format(arena, p, "YYYY"));
}

test "addDays across century leap rules" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("1900-03-01", try addDays(arena, "1900-02-28", 1));
    try testing.expectEqualStrings("2000-02-29", try addDays(arena, "2000-02-28", 1));
    try testing.expectEqualStrings("2000-03-01", try addDays(arena, "2000-02-28", 2));
    try testing.expectEqualStrings("2100-03-01", try addDays(arena, "2100-02-28", 1));
    try testing.expectError(error.BadDate, parse("2100-02-29"));
}

test "addDays on a date-time keeps HH:mm:ss and Z" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("2026-10-16T10:20:30Z", try addDays(arena, "2026-10-15T10:20:30Z", 1));
    try testing.expectEqualStrings("2026-10-16T10:20:30", try addDays(arena, "2026-10-15T10:20:30", 1));
    try testing.expectEqualStrings("2026-10-12T23:59:59Z", try addDays(arena, "2026-10-15T23:59:59Z", -3));
}

test "huge shifts give BadDate" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectError(error.BadDate, addDays(arena, "2026-10-15", 1e9));
    try testing.expectError(error.BadDate, addDays(arena, "2026-10-15", -1e9));
    try testing.expectError(error.BadDate, addDays(arena, "2026-10-15", 1e300));
    try testing.expectError(error.BadDate, addDays(arena, "2026-10-15", std.math.nan(f64)));
    try testing.expectError(error.BadDate, addHours(arena, "2026-10-15T10:00", 1e9));
    try testing.expectError(error.BadDate, addHours(arena, "2026-10-15T10:00", 1e300));
    try testing.expectError(error.BadDate, addHours(arena, "2026-10-15T10:00", std.math.nan(f64)));
    try testing.expectError(error.BadDate, localFromUtc(arena, "2026-10-15T10:00Z", 1e300));
}

test "format returns TooLong past max_len" {
    var arena_state = testArena();
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const p: Parsed = .{ .kind = .datetime, .y = 2026, .mo = 3, .d = 5, .h = 9, .mi = 5, .s = 3 };

    const exact = try arena.alloc(u8, max_len);
    @memset(exact, 'x');
    try testing.expectEqual(@as(usize, max_len), (try format(arena, p, exact)).len);

    const over = try arena.alloc(u8, max_len + 1);
    @memset(over, 'x');
    try testing.expectError(error.TooLong, format(arena, p, over));

    const bracketed = try arena.alloc(u8, max_len + 3);
    @memset(bracketed, 'x');
    bracketed[0] = '[';
    bracketed[bracketed.len - 1] = ']';
    try testing.expectError(error.TooLong, format(arena, p, bracketed));

    const tokens = try arena.alloc(u8, 4 * 2500);
    for (0..2500) |k| @memcpy(tokens[k * 4 .. k * 4 + 4], "YYYY");
    try testing.expectEqual(@as(usize, max_len), (try format(arena, p, tokens)).len);
    const tokens_over = try arena.alloc(u8, 4 * 2501);
    for (0..2501) |k| @memcpy(tokens_over[k * 4 .. k * 4 + 4], "YYYY");
    try testing.expectError(error.TooLong, format(arena, p, tokens_over));
}
