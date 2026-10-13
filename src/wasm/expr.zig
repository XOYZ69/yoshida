//! A small WebAssembly module for expression editing in the browser: no
//! project, no rendering, just the expression syntax. Small and fast enough
//! to call on the page's main thread on every keystroke.
//!
//!   {"op":"parse","src":"a + 1","template":false}
//!     -> {"tokens":[[start,end,kind],...],"problems":[...],"truncated":b,"root":node}
//!        (templates give "holes":[{"span":[s,e],"root":node|null}] instead of "root")
//!   {"op":"format","src":"a+1","width":72}
//!     -> {"text":"a + 1","problems":[]}, or {"text":null,"problems":[...]}
//!   {"op":"catalog"}
//!     -> built-in functions with signatures, built-in names, layer fields
//!
//! Spans are UTF-16 offsets. The page writes the request into memory from
//! `alloc`, calls `request`, and reads the JSON result through result_*.

const std = @import("std");
const exprjson = @import("exprjson");
const json = exprjson.json;

const gpa = std.heap.wasm_allocator;

var result: std.ArrayList(u8) = .empty;

export fn alloc(len: usize) ?[*]u8 {
    const m = gpa.alloc(u8, @max(len, 1)) catch return null;
    return m.ptr;
}

export fn free(ptr: [*]u8, len: usize) void {
    gpa.free(ptr[0..@max(len, 1)]);
}

export fn result_ptr() [*]const u8 {
    return result.items.ptr;
}

export fn result_len() usize {
    return result.items.len;
}

/// Returns 0 on success, 1 for an invalid request ({"error": ...}), -1
/// when out of memory.
export fn request(ptr: [*]const u8, len: usize) i32 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var aw: std.Io.Writer.Allocating = .init(arena);
    const code = handle(arena, &aw.writer, ptr[0..len]) catch return -1;
    result.clearRetainingCapacity();
    result.appendSlice(gpa, aw.written()) catch return -1;
    return code;
}

fn handle(arena: std.mem.Allocator, w: *std.Io.Writer, text: []const u8) !i32 {
    const req = switch (try json.parse(arena, text)) {
        .ok => |n| n,
        .err => |e| {
            try w.print("{{\"error\":\"invalid request JSON: {s}\"}}", .{e.message});
            return 1;
        },
    };
    const op = str(&req, "op") orelse "";
    if (std.mem.eql(u8, op, "catalog")) {
        try exprjson.writeCatalog(w);
        return 0;
    }
    const src = str(&req, "src") orelse {
        try w.writeAll("{\"error\":\"missing src\"}");
        return 1;
    };
    if (std.mem.eql(u8, op, "parse")) {
        const template = if (req.get("template")) |t| t.data == .bool and t.data.bool else false;
        try exprjson.writeParse(arena, w, src, template);
        return 0;
    }
    if (std.mem.eql(u8, op, "format")) {
        const width: usize = if (req.get("width")) |v| (if (v.data == .number and v.data.number >= 8) @intFromFloat(@min(v.data.number, 10000)) else 72) else 72;
        try exprjson.writeFormat(arena, w, src, width);
        return 0;
    }
    try w.writeAll("{\"error\":\"unknown op\"}");
    return 1;
}

fn str(n: *const json.Node, key: []const u8) ?[]const u8 {
    const v = n.get(key) orelse return null;
    return if (v.data == .string) v.data.string else null;
}
