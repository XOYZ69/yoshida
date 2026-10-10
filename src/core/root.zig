//! yoshida core: loads projects, checks them and renders cards. It does no
//! file or network I/O; every front end (CLI, browser, server) passes files
//! in through a `project.Vfs`.

const std = @import("std");
pub const c = @import("c.zig");
pub const json = @import("json.zig");
pub const diag = @import("diag.zig");
pub const value = @import("value.zig");
pub const expr = @import("expr.zig");
pub const design = @import("design.zig");
pub const project = @import("project.zig");
pub const raster = @import("raster.zig");
pub const text = @import("text.zig");
pub const render = @import("render.zig");
pub const api = @import("api.zig");
pub const fmt = @import("fmt.zig");
pub const pdf = @import("pdf.zig");

pub const version = "0.4.0";
pub const format_version = 1;
pub const default_font = render.default_font_data;

comptime {
    // The C allocator and math shims are exported from c.zig; make sure they
    // are always linked.
    _ = c;
}

test {
    std.testing.refAllDecls(@This());
}
