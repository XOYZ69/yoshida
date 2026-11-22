//! One door to every barcode format: `encode` turns text into a `Symbol`
//! (a grid of modules) or says what is wrong with the text.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sym = @import("symbol.zig");
const linear = @import("linear.zig");
const qr = @import("qr.zig");
const datamatrix = @import("datamatrix.zig");
const aztec = @import("aztec.zig");
const pdf417 = @import("pdf417.zig");

pub const Symbol = sym.Symbol;
pub const Format = sym.Format;
pub const Check = sym.Check;
pub const Problem = sym.Problem;
pub const Error = sym.Error;

pub const Options = struct {
    check: Check = .auto,
    /// QR error correction.
    level: qr.Level = .medium,
    /// QR text segments.
    qr_mode: qr.Mode = .auto,
    /// Aztec: smallest share of check words in percent.
    ecc: u8 = 23,
};

pub fn encode(a: Allocator, prob: *Problem, format: Format, text: []const u8, o: Options) Error!Symbol {
    return switch (format) {
        .qr => encodeQr(a, prob, text, o.level, o.qr_mode),
        .code128 => linear.code128(a, prob, text),
        .ean13 => linear.ean13(a, prob, text, o.check),
        .ean8 => linear.ean8(a, prob, text, o.check),
        .upca => linear.upca(a, prob, text, o.check),
        .code39 => linear.code39(a, prob, text, o.check),
        .itf => linear.itf(a, prob, text, o.check),
        .itf14 => linear.itf14(a, prob, text, o.check),
        .codabar => linear.codabar(a, prob, text),
        .code93 => linear.code93(a, prob, text),
        .datamatrix => datamatrix.encode(a, prob, text),
        .aztec => aztec.encode(a, prob, text, .{ .ecc = o.ecc }),
        .pdf417 => pdf417.encode(a, prob, text, o.ecc),
    };
}

fn encodeQr(a: Allocator, prob: *Problem, text: []const u8, level: qr.Level, mode: qr.Mode) Error!Symbol {
    const code = try a.create(qr.Code);
    qr.encodeMode(a, code, text, level, mode, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.NotNumeric => {
            prob.* = .{ .msg = "mode \"numeric\" needs digits only", .hint = "use mode \"auto\", or remove other characters" };
            return error.Invalid;
        },
        error.NotAlphanumeric => {
            prob.* = .{ .msg = "mode \"alphanumeric\" holds digits, capital letters and space $ % * + - . / : only", .hint = "use mode \"auto\" or \"byte\"" };
            return error.Invalid;
        },
        error.TooLong => {
            prob.* = .{
                .code = 3108,
                .msg = try std.fmt.allocPrint(a, "the text is {d} bytes, but a QR code of level {s} holds at most {d}", .{ text.len, @tagName(level), qr.capacity(level) }),
                .hint = "shorten the text or use a lower level",
            };
            return error.Invalid;
        },
    };
    const n: usize = code.size;
    const cells = try a.alloc(bool, n * n);
    @memcpy(cells, code.dark[0 .. n * n]);
    return .{
        .format = .qr,
        .w = n,
        .h = n,
        .cells = cells,
        .normalized = text,
        .version = code.version,
        .capacity = qr.capacity(level),
    };
}

test {
    _ = linear;
    _ = datamatrix;
    _ = aztec;
    _ = pdf417;
}
