//! Minimal ZIP writer (stored entries, no compression; PNG is already compressed).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Entry = struct {
    name: []const u8,
    data: []const u8,
};

pub fn store(gpa: Allocator, entries: []const Entry) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    const w = &aw.writer;
    const offsets = try gpa.alloc(u32, entries.len);
    defer gpa.free(offsets);
    const crcs = try gpa.alloc(u32, entries.len);
    defer gpa.free(crcs);
    // DOS date 2026-01-01 00:00 keeps archives reproducible.
    const dos_time: u16 = 0;
    const dos_date: u16 = ((2026 - 1980) << 9) | (1 << 5) | 1;
    for (entries, 0..) |e, i| {
        offsets[i] = @intCast(aw.written().len);
        crcs[i] = std.hash.Crc32.hash(e.data);
        try w.writeInt(u32, 0x04034b50, .little);
        try w.writeInt(u16, 20, .little); // version needed
        try w.writeInt(u16, 0x0800, .little); // UTF-8 names
        try w.writeInt(u16, 0, .little); // stored
        try w.writeInt(u16, dos_time, .little);
        try w.writeInt(u16, dos_date, .little);
        try w.writeInt(u32, crcs[i], .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u16, @intCast(e.name.len), .little);
        try w.writeInt(u16, 0, .little);
        try w.writeAll(e.name);
        try w.writeAll(e.data);
    }
    const cd_start: u32 = @intCast(aw.written().len);
    for (entries, 0..) |e, i| {
        try w.writeInt(u32, 0x02014b50, .little);
        try w.writeInt(u16, 20, .little); // version made by
        try w.writeInt(u16, 20, .little);
        try w.writeInt(u16, 0x0800, .little);
        try w.writeInt(u16, 0, .little);
        try w.writeInt(u16, dos_time, .little);
        try w.writeInt(u16, dos_date, .little);
        try w.writeInt(u32, crcs[i], .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u32, @intCast(e.data.len), .little);
        try w.writeInt(u16, @intCast(e.name.len), .little);
        try w.writeInt(u16, 0, .little); // extra
        try w.writeInt(u16, 0, .little); // comment
        try w.writeInt(u16, 0, .little); // disk
        try w.writeInt(u16, 0, .little); // internal attributes
        try w.writeInt(u32, 0, .little); // external attributes
        try w.writeInt(u32, offsets[i], .little);
        try w.writeAll(e.name);
    }
    const cd_size: u32 = @as(u32, @intCast(aw.written().len)) - cd_start;
    try w.writeInt(u32, 0x06054b50, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, @intCast(entries.len), .little);
    try w.writeInt(u16, @intCast(entries.len), .little);
    try w.writeInt(u32, cd_size, .little);
    try w.writeInt(u32, cd_start, .little);
    try w.writeInt(u16, 0, .little);
    return aw.toOwnedSlice();
}
