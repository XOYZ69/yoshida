//! What every barcode encoder hands to the renderer: a grid of dark and
//! light modules plus what a 1D code needs for its human-readable text. The
//! encoders are pure functions of the text; they need an allocator for the
//! grid (the renderer passes its arena) and do no I/O.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Format = enum {
    qr,
    code128,
    ean13,
    ean8,
    upca,
    code39,
    itf,
    itf14,
    codabar,
    code93,
    datamatrix,
    aztec,
    pdf417,

    /// Codes drawn as bars of one height: the box height is the bar height.
    pub fn isLinear(f: Format) bool {
        return switch (f) {
            .code128, .ean13, .ean8, .upca, .code39, .itf, .itf14, .codabar, .code93 => true,
            .qr, .datamatrix, .aztec, .pdf417 => false,
        };
    }

    /// Codes whose symbol is not square (or not fixed in shape): the box is
    /// fitted by width and height separately.
    pub fn isSquare(f: Format) bool {
        return switch (f) {
            .qr, .aztec => true,
            else => false,
        };
    }

    /// The quiet zone the standard asks for, in modules, when `margin` is
    /// not given.
    pub fn quietZone(f: Format) u8 {
        return switch (f) {
            .qr => 4,
            .code128, .code39, .itf, .itf14, .codabar, .code93 => 10,
            .ean13 => 11,
            .ean8 => 7,
            .upca => 9,
            .datamatrix => 2,
            .aztec => 1,
            .pdf417 => 2,
        };
    }
};

/// What `check` does. `auto` adds the check digit of EAN, UPC and ITF-14 when
/// one digit is missing and verifies it when the code is complete; `add`
/// also appends the optional check of Code 39 (mod 43) and ITF (mod 10);
/// `none` leaves the digits as they are.
pub const Check = enum { auto, add, none };

/// A run of the human-readable text, centred between two module positions
/// counted from the first bar (negative: in the quiet zone on the left).
pub const LabelGroup = struct {
    text: []const u8,
    x0: i32,
    x1: i32,
};

pub const Symbol = struct {
    format: Format,
    /// Modules per side; a 1D code has `h` 1.
    w: usize,
    h: usize,
    cells: []const bool,
    /// The text as encoded (check digit added, spaces dropped), for the info line.
    normalized: []const u8 = "",
    /// The check digit that was added, if any.
    check_digit: ?u8 = null,
    /// Where the human-readable text goes for a 1D code; null means the whole
    /// `normalized` text under all bars.
    groups: []const LabelGroup = &.{},
    /// Bars that run on into the text row (EAN and UPC guards): module ranges.
    guards: []const [2]u16 = &.{},
    /// Bearer bars above and below (ITF-14).
    bearer: bool = false,
    /// Something the user should know that is not an error: a leading zero
    /// added, a start character supplied.
    note: []const u8 = "",
    /// Symbol version or size class (QR version, Data Matrix size, Aztec
    /// layers), 0 when the format has none.
    version: u16 = 0,
    /// How many data characters the symbol holds at most, 0 when unknown.
    capacity: usize = 0,

    pub fn get(s: *const Symbol, x: usize, y: usize) bool {
        return s.cells[y * s.w + x];
    }
};

/// Why a text cannot be encoded: a message and what to do about it.
pub const Problem = struct {
    /// Diagnostic code: 3108 text too long, 3111 text not valid for the
    /// format, 3112 wrong length or check digit.
    code: u16 = 3111,
    msg: []const u8 = "",
    hint: ?[]const u8 = null,
};

pub const Error = error{ Invalid, OutOfMemory };

/// Collects modules of a 1D code.
pub const Bars = struct {
    list: std.ArrayList(bool) = .empty,

    /// Appends a bit string such as "1011100".
    pub fn bits(b: *Bars, a: Allocator, s: []const u8) Allocator.Error!void {
        for (s) |ch| try b.list.append(a, ch == '1');
    }

    /// Appends alternating bars and spaces, the first one a bar, from a digit
    /// string of widths in modules ("212222").
    pub fn widths(b: *Bars, a: Allocator, s: []const u8) Allocator.Error!void {
        var dark = true;
        for (s) |ch| {
            var n: u8 = ch - '0';
            while (n > 0) : (n -= 1) try b.list.append(a, dark);
            dark = !dark;
        }
    }

    /// Appends alternating bars and spaces from narrow/wide letters
    /// ('n'/'w', wide being `wide` modules), starting with a bar.
    pub fn nw(b: *Bars, a: Allocator, s: []const u8, wide: u8) Allocator.Error!void {
        var dark = true;
        for (s) |ch| {
            var n: u8 = if (ch == 'w') wide else 1;
            while (n > 0) : (n -= 1) try b.list.append(a, dark);
            dark = !dark;
        }
    }
};

pub fn problem(a: Allocator, prob: *Problem, comptime fmt: []const u8, args: anytype, hint: ?[]const u8) Error {
    prob.* = .{ .msg = try std.fmt.allocPrint(a, fmt, args), .hint = hint };
    return error.Invalid;
}
