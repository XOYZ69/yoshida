//! Bindings to the bundled stb libraries plus the tiny libc they need.
//! The C code is compiled without a libc (see src/c/include), so the allocator
//! and math functions it calls are provided here.

const std = @import("std");
const builtin = @import("builtin");

/// Allocator used by the C code. Thread-safe on native targets.
const c_allocator: std.mem.Allocator = if (builtin.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.smp_allocator;

const header_size = 16;

export fn ystb_malloc(size: usize) ?*anyopaque {
    const mem = c_allocator.alignedAlloc(u8, .@"16", size + header_size) catch return null;
    std.mem.writeInt(usize, mem[0..@sizeOf(usize)], size, .little);
    return mem.ptr + header_size;
}

export fn ystb_free(ptr: ?*anyopaque) void {
    const p = ptr orelse return;
    const base: [*]align(16) u8 = @alignCast(@as([*]u8, @ptrCast(p)) - header_size);
    const size = std.mem.readInt(usize, base[0..@sizeOf(usize)], .little);
    c_allocator.free(base[0 .. size + header_size]);
}

export fn ystb_realloc(ptr: ?*anyopaque, new_size: usize) ?*anyopaque {
    const p = ptr orelse return ystb_malloc(new_size);
    const base: [*]u8 = @as([*]u8, @ptrCast(p)) - header_size;
    const old_size = std.mem.readInt(usize, base[0..@sizeOf(usize)], .little);
    const fresh = ystb_malloc(new_size) orelse return null;
    const n = @min(old_size, new_size);
    @memcpy(@as([*]u8, @ptrCast(fresh))[0..n], @as([*]u8, @ptrCast(p))[0..n]);
    ystb_free(p);
    return fresh;
}

export fn ystb_strlen(s: [*:0]const u8) usize {
    return std.mem.len(s);
}

export fn ystb_strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    return switch (std.mem.orderZ(u8, a, b)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

export fn ystb_strncmp(a: [*]const u8, b: [*]const u8, n: usize) c_int {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] != b[i]) return if (a[i] < b[i]) -1 else 1;
        if (a[i] == 0) return 0;
    }
    return 0;
}

export fn ystb_pow(x: f64, y: f64) f64 {
    return std.math.pow(f64, x, y);
}

export fn ystb_fmod(x: f64, y: f64) f64 {
    return @mod(x, y);
}

export fn ystb_cos(x: f64) f64 {
    return @cos(x);
}

export fn ystb_acos(x: f64) f64 {
    return std.math.acos(x);
}

export fn ystb_ldexp(x: f64, e: c_int) f64 {
    return std.math.ldexp(x, e);
}

// ---------------------------------------------------------------- stb_image

pub extern fn stbi_load_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, channels_in_file: *c_int, desired_channels: c_int) ?[*]u8;
pub extern fn stbi_load_16_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, channels_in_file: *c_int, desired_channels: c_int) ?[*]u16;
pub extern fn stbi_is_16_bit_from_memory(buffer: [*]const u8, len: c_int) c_int;
pub extern fn stbi_image_free(data: ?*anyopaque) void;
pub extern fn stbi_failure_reason() ?[*:0]const u8;

// ---------------------------------------------------------------- stb_truetype

pub extern fn ystb_fontinfo_size() c_int;
pub extern fn stbtt_GetFontOffsetForIndex(data: [*]const u8, index: c_int) c_int;
pub extern fn stbtt_InitFont(info: *anyopaque, data: [*]const u8, offset: c_int) c_int;
pub extern fn stbtt_ScaleForMappingEmToPixels(info: *const anyopaque, pixels: f32) f32;
pub extern fn stbtt_GetFontVMetrics(info: *const anyopaque, ascent: *c_int, descent: *c_int, line_gap: *c_int) void;
pub extern fn stbtt_GetCodepointHMetrics(info: *const anyopaque, codepoint: c_int, advance: *c_int, lsb: *c_int) void;
pub extern fn stbtt_GetCodepointKernAdvance(info: *const anyopaque, ch1: c_int, ch2: c_int) c_int;
pub extern fn stbtt_FindGlyphIndex(info: *const anyopaque, codepoint: c_int) c_int;
pub extern fn stbtt_GetCodepointBitmapBoxSubpixel(info: *const anyopaque, codepoint: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, ix0: *c_int, iy0: *c_int, ix1: *c_int, iy1: *c_int) void;
pub extern fn stbtt_MakeCodepointBitmapSubpixel(info: *const anyopaque, output: [*]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, shift_x: f32, shift_y: f32, codepoint: c_int) void;

// ---------------------------------------------------------------- simplewebp

pub const simplewebp = opaque {};
pub extern fn simplewebp_load_from_memory(data: [*]u8, size: usize, allocator: ?*const anyopaque, out: *?*simplewebp) c_int;
pub extern fn simplewebp_get_dimensions(webp: *simplewebp, width: *usize, height: *usize) void;
pub extern fn simplewebp_decode(webp: *simplewebp, buffer: [*]u8, settings: ?*anyopaque) c_int;
pub extern fn simplewebp_unload(webp: *simplewebp) void;
pub extern fn simplewebp_get_error_text(err: c_int) [*:0]const u8;
