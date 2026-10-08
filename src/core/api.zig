//! JSON summaries shared by the WASM module and the server, so the editor sees
//! the same shapes from both.

const std = @import("std");
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const design_mod = @import("design.zig");
const project = @import("project.zig");
const render = @import("render.zig");
const Writer = std.Io.Writer;
const Value = value.Value;

pub fn writeValue(w: *Writer, v: Value) Writer.Error!void {
    switch (v) {
        .number => |x| try value.writeNumber(w, x),
        .bool => |b| try w.writeAll(if (b) "true" else "false"),
        .text, .image => |s| try json.writeString(w, s),
        .color => |c| {
            var buf: [9]u8 = undefined;
            try json.writeString(w, c.hex8String(&buf));
        },
        .list => |items| {
            try w.writeByte('[');
            for (items, 0..) |it, i| {
                if (i > 0) try w.writeByte(',');
                try writeValue(w, .{ .item = it });
            }
            try w.writeByte(']');
        },
        .item => |fields| {
            // Items are written as arrays; writeProject pairs them with field names.
            try w.writeByte('[');
            for (fields, 0..) |f, i| {
                if (i > 0) try w.writeByte(',');
                try writeValue(w, f);
            }
            try w.writeByte(']');
        },
    }
}

fn writeItemValue(w: *Writer, def: *const value.ItemDef, v: Value) Writer.Error!void {
    if (v != .list) return writeValue(w, v);
    try w.writeByte('[');
    for (v.list, 0..) |item, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeByte('{');
        for (def.names, 0..) |n, j| {
            if (j > 0) try w.writeByte(',');
            try json.writeString(w, n);
            try w.writeByte(':');
            try writeValue(w, item[j]);
        }
        try w.writeByte('}');
    }
    try w.writeByte(']');
}

fn writeParamValue(w: *Writer, p: *const design_mod.Param, v: Value) Writer.Error!void {
    if (p.item) |def| return writeItemValue(w, def, v);
    return writeValue(w, v);
}

/// `{"name", "sets": [{name, design, cards_file, ok, params, cards}]}`.
pub fn writeProject(w: *Writer, proj: *const project.Project) Writer.Error!void {
    try w.writeAll("{\"name\":");
    try json.writeString(w, proj.name);
    try w.writeAll(",\"sets\":[");
    for (proj.sets, 0..) |*s, si| {
        if (si > 0) try w.writeByte(',');
        const d = s.design;
        try w.writeAll("{\"name\":");
        try json.writeString(w, s.name);
        try w.writeAll(",\"design\":");
        try json.writeString(w, s.design_path);
        try w.writeAll(",\"design_name\":");
        try json.writeString(w, d.name);
        try w.writeAll(",\"cards_file\":");
        if (s.cards_path) |cp| try json.writeString(w, cp) else try w.writeAll("null");
        try w.print(",\"ok\":{}", .{s.ok});
        try w.writeAll(",\"params\":[");
        for (d.params, 0..) |*p, pi| {
            if (pi > 0) try w.writeByte(',');
            try w.writeAll("{\"name\":");
            try json.writeString(w, p.name);
            try w.print(",\"type\":\"{s}\",\"required\":{}", .{ @tagName(p.kind), p.required });
            if (p.default) |v| {
                try w.writeAll(",\"default\":");
                try writeParamValue(w, p, v);
            }
            if (p.min) |m| try w.print(",\"min\":{d}", .{m});
            if (p.max) |m| try w.print(",\"max\":{d}", .{m});
            if (p.max_length) |m| try w.print(",\"max_length\":{d}", .{m});
            if (p.label) |l| {
                try w.writeAll(",\"label\":");
                try json.writeString(w, l);
            }
            if (p.note) |n| {
                try w.writeAll(",\"note\":");
                try json.writeString(w, n);
            }
            if (p.group) |g| {
                try w.writeAll(",\"group\":");
                try json.writeString(w, g);
            }
            if (p.options.len > 0) {
                try w.writeAll(",\"options\":[");
                for (p.options, 0..) |o, oi| {
                    if (oi > 0) try w.writeByte(',');
                    try json.writeString(w, o);
                }
                try w.writeByte(']');
            }
            if (p.item) |def| {
                try w.writeAll(",\"item\":{");
                for (def.names, 0..) |n, j| {
                    if (j > 0) try w.writeByte(',');
                    try json.writeString(w, n);
                    try w.print(":\"{s}\"", .{@tagName(def.types[j])});
                }
                try w.writeByte('}');
            }
            try w.writeByte('}');
        }
        try w.writeAll("],\"cards\":[");
        for (s.cards, 0..) |*card, ci| {
            if (ci > 0) try w.writeByte(',');
            try w.writeAll("{\"id\":");
            try json.writeString(w, card.id);
            try w.writeAll(",\"values\":{");
            var first = true;
            for (d.params, 0..) |*p, pi| {
                const v = if (pi < card.values.len) card.values[pi] else null;
                if (v == null) continue;
                if (!first) try w.writeByte(',');
                first = false;
                try json.writeString(w, p.name);
                try w.writeByte(':');
                try writeParamValue(w, p, v.?);
            }
            try w.writeAll("}}");
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]}");
}

pub fn writeMissingUrls(w: *Writer, assets: *const render.Assets) Writer.Error!void {
    try w.writeByte('[');
    for (assets.missing_urls.items, 0..) |u, i| {
        if (i > 0) try w.writeByte(',');
        try json.writeString(w, u);
    }
    try w.writeByte(']');
}

/// `[{id, instance?, visible, x, y, w, h, rotate?, px?, py?, size?, points?}]` for the editor's canvas overlay.
pub fn writeOutline(w: *Writer, items: []const render.Placed) Writer.Error!void {
    try w.writeByte('[');
    for (items, 0..) |p, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"id\":");
        try json.writeString(w, p.id);
        if (p.instance) |n| try w.print(",\"instance\":{d}", .{n});
        try w.print(",\"visible\":{},\"x\":", .{p.visible});
        try value.writeNumber(w, p.left);
        try w.writeAll(",\"y\":");
        try value.writeNumber(w, p.top);
        try w.writeAll(",\"w\":");
        try value.writeNumber(w, p.w);
        try w.writeAll(",\"h\":");
        try value.writeNumber(w, p.h);
        if (p.rotate != 0) {
            try w.writeAll(",\"rotate\":");
            try value.writeNumber(w, p.rotate);
            try w.writeAll(",\"px\":");
            try value.writeNumber(w, p.px);
            try w.writeAll(",\"py\":");
            try value.writeNumber(w, p.py);
        }
        if (p.size) |sz| {
            try w.writeAll(",\"size\":");
            try value.writeNumber(w, sz);
        }
        if (p.points.len > 0) {
            try w.writeAll(",\"points\":[");
            for (p.points, 0..) |pt, j| {
                if (j > 0) try w.writeByte(',');
                try w.writeByte('[');
                try value.writeNumber(w, pt[0]);
                try w.writeByte(',');
                try value.writeNumber(w, pt[1]);
                try w.writeByte(']');
            }
            try w.writeByte(']');
        }
        try w.writeByte('}');
    }
    try w.writeByte(']');
}
