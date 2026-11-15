//! The size limits of the core, and how a front end raises them.
//!
//! The core does no I/O, so it never reads the environment itself. The CLI
//! and the server read the `YOSHIDA_MAX_*` variables listed in `settings` and
//! call `set`; the browser build gets the same values in a "limits" request
//! (the editor takes them from the server's /api/capabilities). Without any
//! of that the defaults below apply.
//!
//! The limits are set once at start-up, before anything is loaded or drawn,
//! and only read after that.

const std = @import("std");

pub const Limits = struct {
    /// Visible layers drawn per card, after `repeat` expansion.
    layers: u64 = 500,
    /// Iterations of one `repeat`.
    iterations: u64 = 1000,
    /// Pixels per side of the canvas and of the rendered image.
    canvas_side: u64 = 10000,
    /// Pixels of one image file.
    image_pixels: u64 = 50_000_000,
    /// Cards in one set.
    cards: u64 = 10000,
};

pub const defaults: Limits = .{};

/// The limits in force. Read it as `limits.current.layers`.
pub var current: Limits = .{};

/// What "unlimited" means for a count: more than any design can reach.
pub const no_count_limit: u64 = std.math.maxInt(u32);
/// What "unlimited" means for a side of the canvas. The drawing code keeps
/// sizes in 32 bits and coordinates in single precision, which is exact up
/// to here.
pub const max_canvas_side: u64 = 65535;
/// The most pixels one bitmap may have so that its size in bytes (16 per
/// pixel at most) fits the address space: about 268 megapixels in the
/// browser's 32-bit WebAssembly, no bound that matters on a 64-bit machine.
pub const max_bitmap_pixels: u64 = std.math.maxInt(usize) / 16;

pub const Setting = struct {
    /// The environment variable the CLI and the server read.
    env: []const u8,
    /// The name in JSON (the "limits" request, /api/capabilities).
    key: []const u8,
    /// What the number counts, for messages.
    unit: []const u8,
    /// The number is multiplied by this (megapixels to pixels).
    factor: u64 = 1,
    /// The value that `unlimited` stands for.
    ceiling: u64,
    field: std.meta.FieldEnum(Limits),
};

pub const settings = [_]Setting{
    .{ .env = "YOSHIDA_MAX_LAYERS", .key = "layers", .unit = "visible layers per card", .ceiling = no_count_limit, .field = .layers },
    .{ .env = "YOSHIDA_MAX_REPEAT", .key = "repeat", .unit = "iterations of one repeat", .ceiling = no_count_limit, .field = .iterations },
    .{ .env = "YOSHIDA_MAX_CANVAS", .key = "canvas", .unit = "pixels per side", .ceiling = max_canvas_side, .field = .canvas_side },
    .{ .env = "YOSHIDA_MAX_IMAGE_MP", .key = "image_mp", .unit = "megapixels per image", .factor = 1_000_000, .ceiling = max_bitmap_pixels, .field = .image_pixels },
    .{ .env = "YOSHIDA_MAX_SET_CARDS", .key = "set_cards", .unit = "cards per set", .ceiling = no_count_limit, .field = .cards },
};

pub const unlimited_word = "unlimited";

pub const ParseError = error{Invalid};

/// The value of one setting as written by a person: empty (or only spaces)
/// keeps the default and gives null, a whole number of 1 or more sets the
/// limit, `unlimited` removes it. Anything else is `error.Invalid`.
/// A number above the setting's ceiling becomes the ceiling.
pub fn parse(setting: Setting, text: []const u8) ParseError!?u64 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return null;
    if (std.ascii.eqlIgnoreCase(t, unlimited_word)) return setting.ceiling;
    const n = std.fmt.parseInt(u64, t, 10) catch |e| switch (e) {
        // More digits than fit: as good as unlimited.
        error.Overflow => return if (allDigits(t)) setting.ceiling else error.Invalid,
        error.InvalidCharacter => return error.Invalid,
    };
    if (n == 0 or !allDigits(t)) return error.Invalid;
    const scaled = std.math.mul(u64, n, setting.factor) catch return setting.ceiling;
    return @min(scaled, setting.ceiling);
}

fn allDigits(t: []const u8) bool {
    for (t) |ch| if (!std.ascii.isDigit(ch)) return false;
    return t.len > 0;
}

/// Sets one limit of `current` to a value that `parse` returned.
pub fn set(setting: Setting, v: u64) void {
    switch (setting.field) {
        inline else => |f| @field(current, @tagName(f)) = v,
    }
}

/// The value of one limit of `l`, in the setting's own unit (megapixels for
/// images), or null when it is at its ceiling, that is unlimited.
pub fn shown(setting: Setting, l: Limits) ?u64 {
    const v = switch (setting.field) {
        inline else => |f| @field(l, @tagName(f)),
    };
    return if (v >= setting.ceiling) null else v / setting.factor;
}

/// The setting with this environment variable or JSON key.
pub fn find(name: []const u8) ?Setting {
    for (settings) |s| {
        if (std.mem.eql(u8, s.env, name) or std.mem.eql(u8, s.key, name)) return s;
    }
    return null;
}

/// `{"layers":500,"repeat":1000,...}` with null for an unlimited one: what
/// the server puts in /api/capabilities and the browser build takes back.
pub fn writeJson(w: *std.Io.Writer, l: Limits) std.Io.Writer.Error!void {
    try w.writeAll("{");
    for (settings, 0..) |s, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\":", .{s.key});
        if (shown(s, l)) |v| try w.print("{d}", .{v}) else try w.writeAll("null");
    }
    try w.writeAll("}");
}

/// The message for a value that `parse` refused.
pub fn invalidMessage(buf: []u8, setting: Setting, text: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}={s} is not valid: use a whole number of 1 or more ({s}), or {s}; leave it empty for the default", .{ setting.env, text, setting.unit, unlimited_word }) catch setting.env;
}

/// A megapixel count for messages: "50" for 50 000 000 pixels.
pub fn megapixels(pixels: u64) u64 {
    return pixels / 1_000_000;
}

const testing = std.testing;

test "a setting keeps the default, takes a number or is unlimited" {
    const layers = find("YOSHIDA_MAX_LAYERS").?;
    try testing.expectEqual(@as(?u64, null), try parse(layers, ""));
    try testing.expectEqual(@as(?u64, null), try parse(layers, "  "));
    try testing.expectEqual(@as(?u64, 1000), try parse(layers, "1000"));
    try testing.expectEqual(@as(?u64, 1), try parse(layers, " 1 "));
    try testing.expectEqual(@as(?u64, no_count_limit), try parse(layers, "unlimited"));
    try testing.expectEqual(@as(?u64, no_count_limit), try parse(layers, "Unlimited"));
    // Above the ceiling, and too many digits for 64 bits: unlimited.
    try testing.expectEqual(@as(?u64, no_count_limit), try parse(layers, "99999999999"));
    try testing.expectEqual(@as(?u64, no_count_limit), try parse(layers, "99999999999999999999999999"));
}

test "garbage is refused" {
    const layers = find("layers").?;
    for ([_][]const u8{ "0", "-1", "+5", "1.5", "1e3", "many", "500 layers", "infinite", "0x10" }) |bad| {
        try testing.expectError(error.Invalid, parse(layers, bad));
    }
    var buf: [256]u8 = undefined;
    const msg = invalidMessage(&buf, layers, "many");
    try testing.expect(std.mem.indexOf(u8, msg, "YOSHIDA_MAX_LAYERS=many") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "unlimited") != null);
}

test "images are set in megapixels and the canvas has a ceiling" {
    const image = find("YOSHIDA_MAX_IMAGE_MP").?;
    try testing.expectEqual(@as(?u64, 200_000_000), try parse(image, "200"));
    const canvas = find("YOSHIDA_MAX_CANVAS").?;
    try testing.expectEqual(@as(?u64, 20000), try parse(canvas, "20000"));
    try testing.expectEqual(@as(?u64, max_canvas_side), try parse(canvas, "unlimited"));
    try testing.expectEqual(@as(?u64, max_canvas_side), try parse(canvas, "100000"));
}

test "set, shown and the JSON form" {
    const saved = current;
    defer current = saved;
    set(find("layers").?, 2000);
    set(find("repeat").?, no_count_limit);
    try testing.expectEqual(@as(u64, 2000), current.layers);
    try testing.expectEqual(@as(?u64, 2000), shown(find("layers").?, current));
    try testing.expectEqual(@as(?u64, null), shown(find("repeat").?, current));
    try testing.expectEqual(@as(?u64, 50), shown(find("image_mp").?, current));
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try writeJson(&aw.writer, current);
    try testing.expectEqualStrings("{\"layers\":2000,\"repeat\":null,\"canvas\":10000,\"image_mp\":50,\"set_cards\":10000}", aw.written());
}
