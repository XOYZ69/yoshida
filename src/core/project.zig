//! Projects (FORMAT.md sections 1 and 7): the virtual file system, the
//! manifest, card data in JSON and CSV, and how sets pair cards with designs.

const std = @import("std");
const json = @import("json.zig");
const diag = @import("diag.zig");
const value = @import("value.zig");
const design_mod = @import("design.zig");
const Allocator = std.mem.Allocator;
const Value = value.Value;
const Design = design_mod.Design;
const Node = json.Node;

/// Read-only access to project files. The core never touches the disk or the
/// network itself; the CLI, the browser and the server each provide this.
pub const Vfs = struct {
    ctx: *anyopaque,
    readFn: *const fn (ctx: *anyopaque, path: []const u8) ?[]const u8,
    listFn: *const fn (ctx: *anyopaque, arena: Allocator) Allocator.Error![]const []const u8,

    pub fn read(v: Vfs, path: []const u8) ?[]const u8 {
        return v.readFn(v.ctx, path);
    }

    pub fn list(v: Vfs, arena: Allocator) Allocator.Error![]const []const u8 {
        return v.listFn(v.ctx, arena);
    }
};

/// An in-memory file system: path to bytes. Used by the WASM build and the server.
pub const MemFs = struct {
    gpa: Allocator,
    files: std.StringArrayHashMapUnmanaged([]u8) = .empty,

    pub fn init(gpa: Allocator) MemFs {
        return .{ .gpa = gpa };
    }

    pub fn deinit(m: *MemFs) void {
        m.clear();
        m.files.deinit(m.gpa);
    }

    pub fn put(m: *MemFs, path: []const u8, bytes: []const u8) Allocator.Error!void {
        const data = try m.gpa.dupe(u8, bytes);
        errdefer m.gpa.free(data);
        if (m.files.getEntry(path)) |e| {
            m.gpa.free(e.value_ptr.*);
            e.value_ptr.* = data;
            return;
        }
        const key = try m.gpa.dupe(u8, path);
        errdefer m.gpa.free(key);
        try m.files.put(m.gpa, key, data);
    }

    pub fn remove(m: *MemFs, path: []const u8) void {
        if (m.files.fetchSwapRemove(path)) |kv| {
            m.gpa.free(kv.key);
            m.gpa.free(kv.value);
        }
    }

    pub fn clear(m: *MemFs) void {
        var it = m.files.iterator();
        while (it.next()) |e| {
            m.gpa.free(e.key_ptr.*);
            m.gpa.free(e.value_ptr.*);
        }
        m.files.clearRetainingCapacity();
    }

    pub fn vfs(m: *MemFs) Vfs {
        return .{ .ctx = m, .readFn = readImpl, .listFn = listImpl };
    }

    fn readImpl(ctx: *anyopaque, path: []const u8) ?[]const u8 {
        const m: *MemFs = @ptrCast(@alignCast(ctx));
        return m.files.get(path);
    }

    fn listImpl(ctx: *anyopaque, arena: Allocator) Allocator.Error![]const []const u8 {
        const m: *MemFs = @ptrCast(@alignCast(ctx));
        const out = try arena.alloc([]const u8, m.files.count());
        for (m.files.keys(), 0..) |k, i| out[i] = k;
        return out;
    }
};

pub fn isUrl(p: []const u8) bool {
    return std.mem.startsWith(u8, p, "https://") or std.mem.startsWith(u8, p, "http://");
}

/// Normalizes a project path ("a/./b/../c" to "a/c"). Returns null when the
/// path is absolute or escapes the project root [1203]. URLs pass unchanged.
pub fn normalize(arena: Allocator, p: []const u8) Allocator.Error!?[]const u8 {
    if (isUrl(p)) return p;
    if (p.len == 0 or p[0] == '/' or p[0] == '\\' or (p.len > 1 and p[1] == ':')) return null;
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, p, "/\\");
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) {
            if (parts.items.len == 0) return null;
            _ = parts.pop();
            continue;
        }
        try parts.append(arena, seg);
    }
    if (parts.items.len == 0) return null;
    return try std.mem.join(arena, "/", parts.items);
}

pub const Card = struct {
    id: []const u8,
    /// One entry per design param; null means "use the default".
    values: []const ?Value,
    /// Byte offset of the card in its data file.
    pos: u32,
};

pub const Set = struct {
    name: []const u8,
    design_path: []const u8,
    /// null when the design has no card data: one card with all defaults.
    cards_path: ?[]const u8,
    design: *Design,
    cards: []const Card = &.{},
    ok: bool = false,
};

pub const Project = struct {
    name: []const u8 = "",
    sets: []const Set = &.{},

    pub fn findSet(p: *const Project, name: []const u8) ?*const Set {
        for (p.sets) |*s| if (std.mem.eql(u8, s.name, name)) return s;
        return null;
    }
};

const SetRef = struct {
    name: []const u8,
    design: []const u8,
    cards: ?[]const u8,
    pos: u32,
    src: ?diag.Source,
};

/// Loads the whole project: manifest, every card file and every design.
pub fn load(arena: Allocator, vfs: Vfs, diags: *diag.List) Allocator.Error!Project {
    var project: Project = .{};
    var refs: std.ArrayList(SetRef) = .empty;
    const files = try vfs.list(arena);

    if (vfs.read("yoshida.json")) |text| {
        const src: diag.Source = .{ .file = "yoshida.json", .text = text };
        if (try design_mod.parseJson(arena, diags, src)) |root| {
            _ = try design_mod.checkFormat(&root, diags, src);
            for (root.data.object) |f| {
                const known = [_][]const u8{ "$schema", "format", "name", "note", "sets" };
                var ok = false;
                for (known) |k| if (std.mem.eql(u8, k, f.key)) {
                    ok = true;
                };
                if (!ok) try diags.at(.err, 1101, src, f.key_pos, try pointer(arena, &root, f.key_pos), try diags.fmt("unknown field '{s}' in the manifest", .{f.key}), diag.suggest(arena, f.key, &known));
            }
            if (root.get("name")) |n| if (n.data == .string) {
                project.name = n.data.string;
            };
            if (root.get("sets")) |sets| {
                if (sets.data == .array) {
                    for (sets.data.array, 0..) |*s, i| {
                        if (s.data != .object) {
                            try diags.at(.err, 1103, src, s.pos, try pointer(arena, &root, s.pos), "a set must be an object", null);
                            continue;
                        }
                        const dn = s.get("design");
                        const cn = s.get("cards");
                        if (dn == null or dn.?.data != .string) {
                            try diags.at(.err, 1102, src, s.pos, try pointer(arena, &root, s.pos), "a set needs \"design\": a path", null);
                            continue;
                        }
                        const nm = if (s.get("name")) |n| (if (n.data == .string) n.data.string else null) else null;
                        const dp = (try checkPath(arena, diags, src, &root, dn.?)) orelse continue;
                        var cp: ?[]const u8 = null;
                        if (cn) |c| {
                            if (c.data != .string) {
                                try diags.at(.err, 1103, src, c.pos, try pointer(arena, &root, c.pos), "\"cards\" must be a path", null);
                                continue;
                            }
                            cp = (try checkPath(arena, diags, src, &root, c)) orelse continue;
                        }
                        try refs.append(arena, .{
                            .name = nm orelse try std.fmt.allocPrint(arena, "set{d}", .{i + 1}),
                            .design = dp,
                            .cards = cp,
                            .pos = s.pos,
                            .src = src,
                        });
                    }
                } else try diags.at(.err, 1103, src, sets.pos, "/sets", "\"sets\" must be an array", null);
            }
        }
    }

    // JSON card files name their own design.
    for (files) |f| {
        if (!std.mem.endsWith(u8, f, ".cards.json")) continue;
        var listed = false;
        for (refs.items) |r| if (r.cards != null and std.mem.eql(u8, r.cards.?, f)) {
            listed = true;
        };
        if (listed) continue;
        const text = vfs.read(f) orelse continue;
        const src: diag.Source = .{ .file = f, .text = text };
        const root = (try design_mod.parseJson(arena, diags, src)) orelse continue;
        const dn = root.get("design") orelse {
            try diags.at(.err, 1102, src, root.pos, "", "card data needs \"design\" (or a set in yoshida.json)", null);
            continue;
        };
        if (dn.data != .string) {
            try diags.at(.err, 1103, src, dn.pos, "/design", "\"design\" must be a path", null);
            continue;
        }
        const dp = (try checkPath(arena, diags, src, &root, dn)) orelse continue;
        try refs.append(arena, .{ .name = setName(f), .design = dp, .cards = f, .pos = dn.pos, .src = src });
    }
    for (files) |f| {
        if (std.mem.endsWith(u8, f, ".cards.csv")) {
            var listed = false;
            for (refs.items) |r| if (r.cards != null and std.mem.eql(u8, r.cards.?, f)) {
                listed = true;
            };
            if (!listed) try diags.add(.{ .severity = .warning, .code = 1102, .file = f, .path = "", .message = "CSV card data is not used by any set", .hint = "add a set with \"design\" and \"cards\" to yoshida.json" });
        }
    }
    // Designs without card data render once with defaults.
    for (files) |f| {
        if (!std.mem.endsWith(u8, f, ".design.json")) continue;
        var used = false;
        for (refs.items) |r| if (std.mem.eql(u8, r.design, f)) {
            used = true;
        };
        if (!used) try refs.append(arena, .{ .name = setName(f), .design = f, .cards = null, .pos = 0, .src = null });
    }

    // Load each design once.
    var designs: std.StringArrayHashMapUnmanaged(*Design) = .empty;
    var sets: std.ArrayList(Set) = .empty;
    for (refs.items) |r| {
        const d = designs.get(r.design) orelse blk: {
            const text = vfs.read(r.design) orelse {
                if (r.src) |src| {
                    try diags.at(.err, 1201, src, r.pos, "", try diags.fmt("design file '{s}' not found", .{r.design}), null);
                } else {
                    try diags.add(.{ .severity = .err, .code = 1201, .file = r.design, .path = "", .message = "file not found" });
                }
                continue;
            };
            const loaded = try design_mod.load(arena, diags, r.design, text);
            try designs.put(arena, r.design, loaded);
            break :blk loaded;
        };
        var set: Set = .{ .name = r.name, .design_path = r.design, .cards_path = r.cards, .design = d };
        const before = diags.errorCount();
        if (r.cards) |cp| {
            if (vfs.read(cp)) |text| {
                const src: diag.Source = .{ .file = cp, .text = text };
                set.cards = if (std.mem.endsWith(u8, cp, ".csv"))
                    try loadCsv(arena, diags, src, d)
                else
                    try loadCardsJson(arena, diags, src, d);
            } else {
                try diags.add(.{ .severity = .err, .code = 1201, .file = cp, .path = "", .message = "card data file not found" });
            }
        } else {
            const values = try arena.alloc(?Value, d.params.len);
            @memset(values, null);
            set.cards = try arena.dupe(Card, &.{.{ .id = "preview", .values = values, .pos = 0 }});
            for (d.params) |p| if (p.required and p.default == null) {
                try diags.add(.{ .severity = .warning, .code = 2003, .file = d.file, .path = try diags.fmt("/params/{s}", .{p.name}), .message = try diags.fmt("required param '{s}' has no value in the preview", .{p.name}), .hint = "add card data for this design" });
            };
        }
        set.ok = d.ok and diags.errorCount() == before;
        try sets.append(arena, set);
    }
    project.sets = sets.items;
    return project;
}

fn setName(path: []const u8) []const u8 {
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| path[i + 1 ..] else path;
    const dot = std.mem.indexOfScalar(u8, base, '.') orelse base.len;
    return base[0..dot];
}

fn pointer(arena: Allocator, root: *const Node, pos: u32) Allocator.Error![]const u8 {
    return json.pointerTo(arena, root, pos);
}

fn checkPath(arena: Allocator, diags: *diag.List, src: diag.Source, root: *const Node, n: *const Node) Allocator.Error!?[]const u8 {
    if (try normalize(arena, n.data.string)) |p| return p;
    try diags.at(.err, 1203, src, n.pos, try pointer(arena, root, n.pos), try diags.fmt("path '{s}' is outside the project", .{n.data.string}), "paths are relative to the project folder");
    return null;
}

fn isSafeId(id: []const u8) bool {
    if (id.len == 0 or std.mem.eql(u8, id, ".") or std.mem.eql(u8, id, "..")) return false;
    for (id) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '_' or ch == '-')) return false;
    }
    return true;
}

const CardBuilder = struct {
    arena: Allocator,
    diags: *diag.List,
    src: diag.Source,
    d: *const Design,
    ids: std.StringHashMapUnmanaged(void) = .empty,
    cards: std.ArrayList(Card) = .empty,

    fn report(b: *CardBuilder, sev: diag.Severity, code: u16, pos: u32, path: []const u8, msg: []const u8, hint: ?[]const u8) Allocator.Error!void {
        try b.diags.at(sev, code, b.src, pos, path, msg, hint);
    }

    fn finish(b: *CardBuilder, n: usize, id_in: ?[]const u8, id_pos: u32, values: []?Value, card_pos: u32, base: []const u8) Allocator.Error!void {
        const id = id_in orelse try std.fmt.allocPrint(b.arena, "{d:0>3}", .{n + 1});
        if (!isSafeId(id)) {
            try b.report(.err, 2005, id_pos, try b.diags.fmt("{s}/id", .{base}), try b.diags.fmt("card id '{s}' is not safe as a file name", .{id}), "use letters, digits, '.', '_' and '-'");
        } else if (b.ids.contains(id)) {
            try b.report(.err, 2004, id_pos, try b.diags.fmt("{s}/id", .{base}), try b.diags.fmt("duplicate card id '{s}'", .{id}), null);
        } else try b.ids.put(b.arena, id, {});
        for (b.d.params, 0..) |p, i| {
            if (p.required and values[i] == null) {
                try b.report(.err, 2003, card_pos, base, try b.diags.fmt("card '{s}': required param '{s}' is missing", .{ id, p.name }), null);
            }
        }
        try b.cards.append(b.arena, .{ .id = id, .values = values, .pos = card_pos });
    }

    fn unknown(b: *CardBuilder, key: []const u8, pos: u32, path: []const u8) Allocator.Error!void {
        var names: std.ArrayList([]const u8) = .empty;
        for (b.d.params) |p| try names.append(b.arena, p.name);
        try b.report(.warning, 2001, pos, path, try b.diags.fmt("'{s}' is not a param of the design; it is ignored", .{key}), diag.suggest(b.arena, key, names.items));
    }

    fn accept(b: *CardBuilder, pi: usize, conv: design_mod.Converted, pos: u32, path: []const u8, values: []?Value) Allocator.Error!void {
        const p = &b.d.params[pi];
        switch (conv) {
            .ok => |v| {
                if (try design_mod.checkRange(b.arena, p, v)) |msg| {
                    try b.report(.err, 2002, pos, path, try b.diags.fmt("'{s}': {s}", .{ p.name, msg }), null);
                }
                values[pi] = v;
            },
            .bad => |msg| try b.report(.err, 2006, pos, path, try b.diags.fmt("'{s}': {s}", .{ p.name, msg }), null),
        }
    }
};

fn loadCardsJson(arena: Allocator, diags: *diag.List, src: diag.Source, d: *const Design) Allocator.Error![]const Card {
    const root = (try design_mod.parseJson(arena, diags, src)) orelse return &.{};
    _ = try design_mod.checkFormat(&root, diags, src);
    var b: CardBuilder = .{ .arena = arena, .diags = diags, .src = src, .d = d };
    const known = [_][]const u8{ "$schema", "format", "name", "note", "design", "cards" };
    for (root.data.object) |f| {
        var ok = false;
        for (known) |k| if (std.mem.eql(u8, k, f.key)) {
            ok = true;
        };
        if (!ok) try b.report(.err, 1101, f.key_pos, try pointer(arena, &root, f.key_pos), try diags.fmt("unknown field '{s}' in card data", .{f.key}), diag.suggest(arena, f.key, &known));
    }
    const cards = root.get("cards") orelse {
        try b.report(.err, 1102, root.pos, "", "card data needs \"cards\"", null);
        return &.{};
    };
    if (cards.data != .array) {
        try b.report(.err, 1103, cards.pos, "/cards", "\"cards\" must be an array", null);
        return &.{};
    }
    if (cards.data.array.len > 10000) {
        try b.report(.err, 5001, cards.pos, "/cards", "more than 10000 cards in one set", null);
        return &.{};
    }
    for (cards.data.array, 0..) |*c, n| {
        const base = try diags.fmt("/cards/{d}", .{n});
        if (c.data != .object) {
            try b.report(.err, 1103, c.pos, base, "a card must be an object", null);
            continue;
        }
        const values = try arena.alloc(?Value, d.params.len);
        @memset(values, null);
        var id: ?[]const u8 = null;
        var id_pos = c.pos;
        for (c.data.object) |*f| {
            const path = try diags.fmt("{s}/{s}", .{ base, f.key });
            if (std.mem.eql(u8, f.key, "id")) {
                id_pos = f.value.pos;
                switch (f.value.data) {
                    .string => |s| id = s,
                    else => try b.report(.err, 2006, f.value.pos, path, "card id must be a string", null),
                }
                continue;
            }
            const pi = d.findParam(f.key) orelse {
                try b.unknown(f.key, f.key_pos, path);
                continue;
            };
            try b.accept(pi, try design_mod.convertJson(arena, &d.params[pi], &f.value), f.value.pos, path, values);
        }
        try b.finish(n, id, id_pos, values, c.pos, base);
    }
    return b.cards.items;
}

const CsvCell = struct { text: []const u8, pos: u32 };

/// RFC 4180 parser. Returns rows of cells, or reports [1202].
fn parseCsv(arena: Allocator, diags: *diag.List, src: diag.Source) Allocator.Error!?[]const []const CsvCell {
    var rows: std.ArrayList([]const CsvCell) = .empty;
    var row: std.ArrayList(CsvCell) = .empty;
    const s = src.text;
    var i: usize = if (std.mem.startsWith(u8, s, "\xEF\xBB\xBF")) 3 else 0;
    if (i >= s.len) return rows.items;
    while (true) {
        const start = i;
        var cell: std.ArrayList(u8) = .empty;
        if (i < s.len and s[i] == '"') {
            i += 1;
            while (true) {
                if (i >= s.len) {
                    try diags.at(.err, 1202, src, @intCast(start), "", "unterminated quoted field", null);
                    return null;
                }
                if (s[i] == '"') {
                    if (i + 1 < s.len and s[i + 1] == '"') {
                        try cell.append(arena, '"');
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                try cell.append(arena, s[i]);
                i += 1;
            }
            if (i < s.len and s[i] != ',' and s[i] != '\n' and s[i] != '\r') {
                try diags.at(.err, 1202, src, @intCast(i), "", "unexpected character after a quoted field", "quote the whole field and double inner quotes");
                return null;
            }
        } else {
            while (i < s.len and s[i] != ',' and s[i] != '\n' and s[i] != '\r') : (i += 1) {
                if (s[i] == '"') {
                    try diags.at(.err, 1202, src, @intCast(i), "", "quote inside an unquoted field", "quote the whole field and double inner quotes");
                    return null;
                }
            }
            try cell.appendSlice(arena, s[start..i]);
        }
        try row.append(arena, .{ .text = cell.items, .pos = @intCast(start) });
        if (i < s.len and s[i] == ',') {
            i += 1;
            continue;
        }
        // End of record.
        if (i < s.len and s[i] == '\r') i += 1;
        if (i < s.len and s[i] == '\n') i += 1;
        if (!(row.items.len == 1 and row.items[0].text.len == 0)) try rows.append(arena, row.items);
        row = .empty;
        if (i >= s.len) break;
    }
    return rows.items;
}

fn loadCsv(arena: Allocator, diags: *diag.List, src: diag.Source, d: *const Design) Allocator.Error![]const Card {
    const rows = (try parseCsv(arena, diags, src)) orelse return &.{};
    if (rows.len == 0) {
        try diags.at(.err, 1202, src, 0, "", "the CSV file needs a header row", null);
        return &.{};
    }
    if (rows.len - 1 > 10000) {
        try diags.at(.err, 5001, src, 0, "", "more than 10000 cards in one set", null);
        return &.{};
    }
    var b: CardBuilder = .{ .arena = arena, .diags = diags, .src = src, .d = d };
    const header = rows[0];
    const col_param = try arena.alloc(?usize, header.len);
    var id_col: ?usize = null;
    for (header, 0..) |h, ci| {
        col_param[ci] = null;
        const name = std.mem.trim(u8, h.text, " ");
        if (std.mem.eql(u8, name, "id")) {
            id_col = ci;
            continue;
        }
        col_param[ci] = d.findParam(name);
        if (col_param[ci] == null) try b.unknown(name, h.pos, try diags.fmt("/0/{d}", .{ci}));
    }
    for (rows[1..], 0..) |r, n| {
        if (r.len != header.len) {
            try diags.at(.err, 1202, src, r[0].pos, try diags.fmt("/{d}", .{n + 1}), try diags.fmt("row has {d} fields, the header has {d}", .{ r.len, header.len }), null);
            continue;
        }
        const values = try arena.alloc(?Value, d.params.len);
        @memset(values, null);
        var id: ?[]const u8 = null;
        var id_pos = r[0].pos;
        for (r, 0..) |cell, ci| {
            if (id_col != null and ci == id_col.?) {
                if (cell.text.len > 0) id = cell.text;
                id_pos = cell.pos;
                continue;
            }
            const pi = col_param[ci] orelse continue;
            if (cell.text.len == 0) continue;
            const path = try diags.fmt("/{d}/{s}", .{ n + 1, d.params[pi].name });
            try b.accept(pi, try design_mod.convertText(arena, &d.params[pi], cell.text), cell.pos, path, values);
        }
        try b.finish(n, id, id_pos, values, r[0].pos, try diags.fmt("/{d}", .{n + 1}));
    }
    return b.cards.items;
}

test "normalize" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("a/c", (try normalize(a, "a/./b/../c")).?);
    try std.testing.expect((try normalize(a, "../x")) == null);
    try std.testing.expect((try normalize(a, "/etc/passwd")) == null);
}

test "csv" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var diags = diag.List.init(a);
    const rows = (try parseCsv(a, &diags, .{ .file = "x.csv", .text = "id,t\r\n1,\"a, \"\"b\"\"\"\n2,c\n" })).?;
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("a, \"b\"", rows[1][1].text);
}
