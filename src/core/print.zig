//! Print layout: cards side by side on pages of a paper size (A4, Letter or
//! any size), with gaps between them and crop marks around the grid, and for
//! duplex printing a page of backs after each page of fronts, laid out so
//! that each back lands behind its front (`yoshida render --pdf --page`, the
//! export dialog's print layout; docs: site/content/docs/command-line.md).
//!
//! Every card is written once as a PDF object (`pdf.Card`) and placed on the
//! pages, so a back repeated on every page costs one object. Lengths are PDF
//! points (1/72 inch) with y up and the origin at the bottom-left of a page.

const std = @import("std");
const pdf = @import("pdf.zig");
const raster = @import("raster.zig");
const Allocator = std.mem.Allocator;

/// Points per millimetre.
pub const mm: f64 = 72.0 / 25.4;

/// The edge the sheet is turned over on in a duplex printer.
pub const Duplex = enum { long, short };

pub const default_margin_mm = 5;
/// The largest gap and margin, in millimetres.
pub const max_gap_mm = 50;
pub const max_margin_mm = 50;
/// The smallest and largest side of a page, in millimetres.
pub const min_page_mm = 20;
pub const max_page_mm = 2000;
/// Crop marks: their distance from the bleed edge of the grid and their length.
const mark_offset = 2 * mm;
const mark_length = 5 * mm;
const mark_width = 0.25;

pub const Options = struct {
    page_w: f64 = 210 * mm,
    page_h: f64 = 297 * mm,
    /// Between the trim edges of neighbouring cards.
    gap: f64 = 0,
    /// The least room left at each edge of the page; the grid is centred.
    margin: f64 = default_margin_mm * mm,
    crop_marks: bool = false,
    duplex: Duplex = .long,
};

/// A page size in points from `a4`, `letter` (either with `-landscape`) or
/// `WxH` in millimetres such as `63.5x88.9`; null for anything else or a side
/// outside `min_page_mm` to `max_page_mm`.
pub fn parsePage(s: []const u8) ?[2]f64 {
    const sizes = [_]struct { name: []const u8, w: f64, h: f64 }{
        .{ .name = "a4", .w = 210, .h = 297 },
        .{ .name = "letter", .w = 215.9, .h = 279.4 },
    };
    for (sizes) |p| {
        if (std.ascii.eqlIgnoreCase(s, p.name)) return .{ p.w * mm, p.h * mm };
        if (s.len == p.name.len + "-landscape".len and std.ascii.startsWithIgnoreCase(s, p.name) and std.ascii.eqlIgnoreCase(s[p.name.len..], "-landscape")) return .{ p.h * mm, p.w * mm };
    }
    const x = std.mem.indexOfAny(u8, s, "xX") orelse return null;
    const w = parseMm(s[0..x], min_page_mm, max_page_mm) orelse return null;
    const h = parseMm(s[x + 1 ..], min_page_mm, max_page_mm) orelse return null;
    return .{ w * mm, h * mm };
}

/// A length in millimetres from `lo` to `hi` (a plain decimal number).
pub fn parseMm(s: []const u8, lo: f64, hi: f64) ?f64 {
    if (s.len == 0) return null;
    for (s) |ch| if (!(std.ascii.isDigit(ch) or ch == '.')) return null;
    const v = std.fmt.parseFloat(f64, s) catch return null;
    return if (v >= lo and v <= hi) v else null;
}

pub const Rect = struct { x: f64, y: f64, w: f64, h: f64 };
pub const Line = struct { x0: f64, y0: f64, x1: f64, y1: f64 };

/// Where one card goes: its trim box, the part of the page it may draw on
/// (the trim box and as much bleed as fits: all of it at the outside of the
/// grid, up to half the gap between cards), and whether it is turned 180°.
pub const Slot = struct { trim: Rect, clip: Rect, rotate: bool = false };

pub const Layout = struct {
    page_w: f64,
    page_h: f64,
    trim_w: f64,
    trim_h: f64,
    bleed: f64,
    gap: f64,
    cols: u32,
    rows: u32,
    /// The left and top trim edges of the grid.
    left: f64,
    top: f64,

    /// The grid for cards of `card_w` x `card_h` points (with a bleed of
    /// `bleed` on every side): as many trim boxes as fit inside the margins,
    /// `gap` apart, centred on the page so that mirroring a page keeps the
    /// grid where it is.
    pub fn init(o: Options, card_w: f64, card_h: f64, bleed: f64) error{CardTooLarge}!Layout {
        var bl = @max(0, bleed);
        if (!(card_w - 2 * bl > 0 and card_h - 2 * bl > 0)) bl = 0;
        const tw = card_w - 2 * bl;
        const th = card_h - 2 * bl;
        if (!(tw > 0 and th > 0)) return error.CardTooLarge;
        const gap = @max(0, o.gap);
        const fit = struct {
            fn n(avail: f64, size: f64, g: f64) u32 {
                if (avail < size) return 0;
                // A little slack, so a card that fits exactly is not lost to rounding.
                const k = @floor((avail + g) / (size + g) + 1e-9);
                return @intFromFloat(@min(k, 100));
            }
        }.n;
        const cols = fit(o.page_w - 2 * o.margin, tw, gap);
        const rows = fit(o.page_h - 2 * o.margin, th, gap);
        if (cols == 0 or rows == 0) return error.CardTooLarge;
        const grid_w = @as(f64, @floatFromInt(cols)) * (tw + gap) - gap;
        const grid_h = @as(f64, @floatFromInt(rows)) * (th + gap) - gap;
        return .{
            .page_w = o.page_w,
            .page_h = o.page_h,
            .trim_w = tw,
            .trim_h = th,
            .bleed = bl,
            .gap = gap,
            .cols = cols,
            .rows = rows,
            .left = (o.page_w - grid_w) / 2,
            .top = (o.page_h + grid_h) / 2,
        };
    }

    pub fn capacity(l: Layout) usize {
        return @as(usize, l.cols) * l.rows;
    }

    fn cell(l: Layout, col: u32, row: u32) Slot {
        const x = l.left + @as(f64, @floatFromInt(col)) * (l.trim_w + l.gap);
        const y = l.top - @as(f64, @floatFromInt(row)) * (l.trim_h + l.gap) - l.trim_h;
        const inner = @min(l.bleed, l.gap / 2);
        const el = if (col == 0) l.bleed else inner;
        const er = if (col + 1 == l.cols) l.bleed else inner;
        const et = if (row == 0) l.bleed else inner;
        const eb = if (row + 1 == l.rows) l.bleed else inner;
        return .{
            .trim = .{ .x = x, .y = y, .w = l.trim_w, .h = l.trim_h },
            .clip = .{ .x = x - el, .y = y - eb, .w = l.trim_w + el + er, .h = l.trim_h + et + eb },
        };
    }

    /// Card `i` of a page of fronts: left to right, top to bottom.
    pub fn front(l: Layout, i: usize) Slot {
        return l.cell(@intCast(i % l.cols), @intCast(i / l.cols));
    }

    /// True when the backs mirror the fronts left to right: the sheet turns
    /// over about a vertical line, which is flip on long edge for a portrait
    /// page and flip on short edge for a landscape one.
    pub fn turnsSideways(l: Layout, duplex: Duplex) bool {
        const landscape = l.page_w > l.page_h;
        return (duplex == .long) != landscape;
    }

    /// The back of card `i` on the page after its front. Turned sideways the
    /// columns run right to left. Turned top over bottom the rows run bottom
    /// to top and each back is turned 180°, so that a cut card shows its back
    /// the right way up when it is turned over like a page of a book, as with
    /// flip on long edge.
    pub fn back(l: Layout, i: usize, duplex: Duplex) Slot {
        const col: u32 = @intCast(i % l.cols);
        const row: u32 = @intCast(i / l.cols);
        if (l.turnsSideways(duplex)) return l.cell(l.cols - 1 - col, row);
        var s = l.cell(col, l.rows - 1 - row);
        s.rotate = true;
        return s;
    }

    /// Crop marks at every trim line of the grid, outside it: short lines in
    /// the margin above and below each column edge and left and right of
    /// each row edge, cut short at the edge of the page.
    pub fn cropMarks(l: Layout, gpa: Allocator) Allocator.Error![]Line {
        var lines: std.ArrayList(Line) = .empty;
        errdefer lines.deinit(gpa);
        const right = l.left + @as(f64, @floatFromInt(l.cols)) * (l.trim_w + l.gap) - l.gap;
        const bottom = l.top - (@as(f64, @floatFromInt(l.rows)) * (l.trim_h + l.gap) - l.gap);
        const out = l.bleed + mark_offset;
        var last: f64 = -1;
        for (0..l.cols) |c| {
            const x0 = l.left + @as(f64, @floatFromInt(c)) * (l.trim_w + l.gap);
            for ([_]f64{ x0, x0 + l.trim_w }) |x| {
                // With no gap, the right edge of a card is the left edge of the next.
                if (@abs(x - last) < 1e-6) continue;
                last = x;
                if (l.top + out < l.page_h) try lines.append(gpa, .{ .x0 = x, .y0 = l.top + out, .x1 = x, .y1 = @min(l.page_h, l.top + out + mark_length) });
                if (bottom - out > 0) try lines.append(gpa, .{ .x0 = x, .y0 = bottom - out, .x1 = x, .y1 = @max(0, bottom - out - mark_length) });
            }
        }
        last = -1;
        for (0..l.rows) |r| {
            const y0 = l.top - @as(f64, @floatFromInt(r)) * (l.trim_h + l.gap);
            for ([_]f64{ y0, y0 - l.trim_h }) |y| {
                if (@abs(y - last) < 1e-6) continue;
                last = y;
                if (l.left - out > 0) try lines.append(gpa, .{ .x0 = l.left - out, .y0 = y, .x1 = @max(0, l.left - out - mark_length), .y1 = y });
                if (right + out < l.page_w) try lines.append(gpa, .{ .x0 = right + out, .y0 = y, .x1 = @min(l.page_w, right + out + mark_length), .y1 = y });
            }
        }
        return lines.toOwnedSlice(gpa);
    }
};

/// Builds the pages of a print layout on a PDF writer: cards are added one
/// by one, and each full page of fronts (and the last one) is written with,
/// when there is a back, a page of backs after it.
pub const Sheets = struct {
    w: *pdf.Writer,
    opts: Options,
    /// Made from the first card.
    layout: ?Layout = null,
    /// Shown behind every card.
    back: ?pdf.Card = null,
    cards: std.ArrayList(pdf.Card) = .empty,
    /// Cards placed so far, on written and pending pages.
    count: usize = 0,

    pub fn init(w: *pdf.Writer, opts: Options) Sheets {
        return .{ .w = w, .opts = opts };
    }

    pub fn deinit(s: *Sheets) void {
        s.cards.deinit(s.w.gpa);
    }

    /// Adds a card to the page being filled. False when its trim size is not
    /// the layout's (that of the first card): it is centred on its place and
    /// cut to it.
    pub fn add(s: *Sheets, card: pdf.Card) !bool {
        if (s.layout == null) s.layout = try Layout.init(s.opts, card.w, card.h, card.bleed);
        const l = s.layout.?;
        try s.cards.append(s.w.gpa, card);
        s.count += 1;
        if (s.cards.items.len >= l.capacity()) try s.flush();
        return @abs(card.w - 2 * card.bleed - l.trim_w) < 0.01 and @abs(card.h - 2 * card.bleed - l.trim_h) < 0.01;
    }

    /// Writes the last page (and its backs) when it has cards.
    pub fn finish(s: *Sheets) !void {
        if (s.cards.items.len > 0) try s.flush();
    }

    fn flush(s: *Sheets) !void {
        const l = s.layout.?;
        try s.page(l, s.cards.items, null);
        if (s.back) |b| try s.page(l, &.{b}, s.cards.items.len);
        s.cards.clearRetainingCapacity();
    }

    /// A page of `cards` in order, or with `backs` set, that many copies of
    /// `cards[0]` at the places of the backs.
    fn page(s: *Sheets, l: Layout, cards: []const pdf.Card, backs: ?usize) !void {
        const gpa = s.w.gpa;
        var content: std.Io.Writer.Allocating = .init(gpa);
        defer content.deinit();
        const o = &content.writer;
        var ids: std.ArrayList(u32) = .empty;
        defer ids.deinit(gpa);
        const n = backs orelse cards.len;
        for (0..n) |i| {
            const card = if (backs != null) cards[0] else cards[i];
            const slot = if (backs != null) l.back(i, s.opts.duplex) else l.front(i);
            const name = std.mem.indexOfScalar(u32, ids.items, card.id) orelse blk: {
                try ids.append(gpa, card.id);
                break :blk ids.items.len - 1;
            };
            place(o, card, slot, name) catch return error.OutOfMemory;
        }
        if (s.opts.crop_marks) {
            const lines = try l.cropMarks(gpa);
            defer gpa.free(lines);
            o.print("q 0 0 0 RG {d} w 0 J\n", .{mark_width}) catch return error.OutOfMemory;
            for (lines) |ln| o.print("{d:.3} {d:.3} m {d:.3} {d:.3} l S\n", .{ ln.x0, ln.y0, ln.x1, ln.y1 }) catch return error.OutOfMemory;
            o.writeAll("Q\n") catch return error.OutOfMemory;
        }
        const z = try raster.deflate(gpa, content.written());
        defer gpa.free(z);
        const content_id = try s.w.begin();
        try s.w.stream("/Filter /FlateDecode", z);
        const page_id = try s.w.begin();
        const ow = &s.w.out.writer;
        ow.print("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {d:.4} {d:.4}] /Resources << /XObject <<", .{ l.page_w, l.page_h }) catch return error.OutOfMemory;
        for (ids.items, 0..) |id, i| ow.print(" /C{d} {d} 0 R", .{ i, id }) catch return error.OutOfMemory;
        ow.print(" >> >> /Contents {d} 0 R >>\nendobj\n", .{content_id}) catch return error.OutOfMemory;
        try s.w.pages.append(gpa, page_id);
    }
};

/// Draws `card` (resource `/C<name>`) centred on the slot's trim box, cut to
/// its clip box.
fn place(o: *std.Io.Writer, card: pdf.Card, slot: Slot, name: usize) !void {
    const t = slot.trim;
    const x = t.x + (t.w - card.w) / 2;
    const y = t.y + (t.h - card.h) / 2;
    const c = slot.clip;
    try o.print("q {d:.3} {d:.3} {d:.3} {d:.3} re W n ", .{ c.x, c.y, c.w, c.h });
    // An image fills the unit square, a form is drawn in points.
    const sx: f64 = if (card.image) card.w else 1;
    const sy: f64 = if (card.image) card.h else 1;
    if (slot.rotate)
        try o.print("{d:.4} 0 0 {d:.4} {d:.3} {d:.3} cm", .{ -sx, -sy, x + card.w, y + card.h })
    else
        try o.print("{d:.4} 0 0 {d:.4} {d:.3} {d:.3} cm", .{ sx, sy, x, y });
    try o.print(" /C{d} Do Q\n", .{name});
}

// ------------------------------------------------------------------ tests

const testing = std.testing;
const poker_w = 63.5 * mm;
const poker_h = 88.9 * mm;

fn near(a: f64, b: f64) bool {
    return @abs(a - b) < 1e-6;
}

test "page sizes" {
    const a4 = parsePage("a4").?;
    try testing.expect(near(a4[0], 595.2755905511812) and near(a4[1], 841.8897637795276));
    const letter = parsePage("Letter").?;
    try testing.expect(near(letter[0], 612) and near(letter[1], 792));
    const land = parsePage("letter-landscape").?;
    try testing.expect(near(land[0], 792) and near(land[1], 612));
    const custom = parsePage("63.5x88.9").?;
    try testing.expect(near(custom[0], poker_w) and near(custom[1], poker_h));
    for ([_][]const u8{ "a5", "", "x", "10x297", "210x", "-210x297", "210x297mm", "a4-portrait", "3000x100" }) |bad|
        try testing.expect(parsePage(bad) == null);
    try testing.expect(parseMm("2.5", 0, 50).? == 2.5);
    try testing.expect(parseMm("51", 0, 50) == null);
    try testing.expect(parseMm("-1", 0, 50) == null);
}

test "grid: as many cards as fit, centred" {
    const l = try Layout.init(.{}, poker_w, poker_h, 0);
    try testing.expectEqual(@as(u32, 3), l.cols);
    try testing.expectEqual(@as(u32, 3), l.rows);
    try testing.expectEqual(@as(usize, 9), l.capacity());
    // Centred: as much room left as right, above as below.
    const last = l.front(8).trim;
    try testing.expect(near(l.left, l.page_w - (last.x + last.w)));
    try testing.expect(near(l.page_h - l.top, last.y));
    try testing.expect(near(l.left, (210.0 - 3 * 63.5) / 2.0 * mm));
    // Left to right, top to bottom.
    try testing.expect(l.front(1).trim.x > l.front(0).trim.x and near(l.front(1).trim.y, l.front(0).trim.y));
    try testing.expect(l.front(3).trim.y < l.front(0).trim.y and near(l.front(3).trim.x, l.front(0).trim.x));
    // A gap: 3 mm between cards still fits 3 x 3; the cards are 3 mm apart.
    const g = try Layout.init(.{ .gap = 3 * mm }, poker_w, poker_h, 0);
    try testing.expectEqual(@as(u32, 3), g.cols);
    try testing.expect(near(g.front(1).trim.x - (g.front(0).trim.x + g.trim_w), 3 * mm));
    try testing.expect(near(g.front(0).trim.y - (g.front(3).trim.y + g.trim_h), 3 * mm));
    // Letter in landscape: 4 x 2.
    const land = parsePage("letter-landscape").?;
    const ll = try Layout.init(.{ .page_w = land[0], .page_h = land[1] }, poker_w, poker_h, 0);
    try testing.expectEqual(@as(u32, 4), ll.cols);
    try testing.expectEqual(@as(u32, 2), ll.rows);
    // A card that just fits, and one that does not.
    const exact = try Layout.init(.{ .page_w = 100, .page_h = 100, .margin = 0 }, 50, 100, 0);
    try testing.expectEqual(@as(u32, 2), exact.cols);
    try testing.expectError(error.CardTooLarge, Layout.init(.{ .page_w = 100, .page_h = 100, .margin = 10 }, 50, 100, 0));
}

test "grid: the bleed is outside the trim box and cut at half the gap" {
    const bleed = 3 * mm;
    const l = try Layout.init(.{ .gap = 4 * mm }, poker_w + 2 * bleed, poker_h + 2 * bleed, bleed);
    try testing.expect(near(l.trim_w, poker_w) and near(l.trim_h, poker_h));
    const s = l.front(4); // the middle card
    try testing.expect(near(s.clip.x, s.trim.x - 2 * mm) and near(s.clip.w, s.trim.w + 4 * mm));
    const corner = l.front(0); // top left: all of the bleed at the outside
    try testing.expect(near(corner.clip.x, corner.trim.x - bleed));
    try testing.expect(near(corner.clip.y + corner.clip.h, corner.trim.y + corner.trim.h + bleed));
    try testing.expect(near(corner.clip.x + corner.clip.w, corner.trim.x + corner.trim.w + 2 * mm));
}

test "backs: mirrored for flip on long and short edge" {
    const l = try Layout.init(.{}, poker_w, poker_h, 0);
    // Portrait, long edge: the columns run right to left, upright.
    try testing.expect(l.turnsSideways(.long));
    for (0..9) |i| {
        const f = l.front(i).trim;
        const b = l.back(i, .long);
        try testing.expect(!b.rotate);
        try testing.expect(near(b.trim.x, l.page_w - f.x - f.w));
        try testing.expect(near(b.trim.y, f.y));
    }
    try testing.expect(near(l.back(0, .long).trim.x, l.front(2).trim.x));
    // Portrait, short edge: the rows run bottom to top, turned 180°.
    try testing.expect(!l.turnsSideways(.short));
    for (0..9) |i| {
        const f = l.front(i).trim;
        const b = l.back(i, .short);
        try testing.expect(b.rotate);
        try testing.expect(near(b.trim.x, f.x));
        try testing.expect(near(b.trim.y, l.page_h - f.y - f.h));
    }
    try testing.expect(near(l.back(0, .short).trim.y, l.front(6).trim.y));
    // Landscape: long edge turns top over bottom, short edge sideways.
    const land = parsePage("a4-landscape").?;
    const ll = try Layout.init(.{ .page_w = land[0], .page_h = land[1] }, poker_w, poker_h, 0);
    try testing.expect(!ll.turnsSideways(.long) and ll.turnsSideways(.short));
    try testing.expect(ll.back(0, .long).rotate);
    // An uneven grid with a gap and bleed: still a mirror image of the fronts, clip boxes too.
    const bleed = 2 * mm;
    const g = try Layout.init(.{ .gap = 5 * mm, .page_w = 300 * mm, .page_h = 250 * mm }, poker_w + 2 * bleed, poker_h + 2 * bleed, bleed);
    for (0..g.capacity()) |i| {
        const f = g.front(i);
        const b = g.back(i, .short); // landscape: sideways
        try testing.expect(near(b.trim.x, g.page_w - f.trim.x - f.trim.w));
        try testing.expect(near(b.clip.x, g.page_w - f.clip.x - f.clip.w));
        try testing.expect(near(b.clip.w, f.clip.w));
    }
}

test "crop marks: at every trim line, outside the grid, on the page" {
    const gpa = testing.allocator;
    const l = try Layout.init(.{}, poker_w, poker_h, 0);
    const lines = try l.cropMarks(gpa);
    defer gpa.free(lines);
    // No gap: 4 column edges and 4 row edges, each marked on both sides.
    try testing.expectEqual(@as(usize, 16), lines.len);
    const bottom = l.front(8).trim.y;
    const right = l.front(8).trim.x + l.trim_w;
    for (lines) |ln| {
        for ([_]f64{ ln.x0, ln.x1 }) |x| try testing.expect(x >= 0 and x <= l.page_w);
        for ([_]f64{ ln.y0, ln.y1 }) |y| try testing.expect(y >= 0 and y <= l.page_h);
        if (ln.x0 == ln.x1) {
            // A column edge: above or below the grid.
            try testing.expect(@min(ln.y0, ln.y1) >= l.top + mark_offset - 1e-9 or @max(ln.y0, ln.y1) <= bottom - mark_offset + 1e-9);
            var on_edge = false;
            for (0..3) |c| {
                const t = l.front(c).trim;
                if (near(ln.x0, t.x) or near(ln.x0, t.x + t.w)) on_edge = true;
            }
            try testing.expect(on_edge);
        } else {
            try testing.expect(ln.y0 == ln.y1);
            try testing.expect(@max(ln.x0, ln.x1) <= l.left - mark_offset + 1e-9 or @min(ln.x0, ln.x1) >= right + mark_offset - 1e-9);
        }
    }
    try testing.expect(near(lines[0].x0, l.left) and near(lines[0].y0, l.top + mark_offset) and near(lines[0].y1, l.top + mark_offset + mark_length));
    // With a gap every card edge is its own line: 6 and 6.
    const g = try Layout.init(.{ .gap = 2 * mm }, poker_w, poker_h, 0);
    const gl = try g.cropMarks(gpa);
    defer gpa.free(gl);
    try testing.expectEqual(@as(usize, 24), gl.len);
    // Without room in the margin there are no marks.
    const tight = try Layout.init(.{ .page_w = 127 * mm, .page_h = 88.9 * mm, .margin = 0 }, poker_w, poker_h, 0);
    const tl = try tight.cropMarks(gpa);
    defer gpa.free(tl);
    try testing.expectEqual(@as(usize, 0), tl.len);
}

fn testCard(w: *pdf.Writer, gpa: Allocator, color: [4]f32, dpi: f64) !pdf.Card {
    var b = try raster.Bitmap.init(gpa, 0, 0, 750, 1050);
    defer b.deinit(gpa);
    b.fill(color);
    b.dpi = dpi;
    return w.imageCard(&b);
}

test "sheets: pages of fronts, each followed by its backs" {
    const gpa = testing.allocator;
    const vec = @import("pdf_vector.zig");
    inline for (.{ true, false }) |with_back| {
        var w = try pdf.Writer.init(gpa);
        defer w.deinit();
        var s = Sheets.init(&w, .{ .crop_marks = true });
        defer s.deinit();
        if (with_back) s.back = try testCard(&w, gpa, .{ 0, 0, 65535, 65535 }, 300);
        const front = try testCard(&w, gpa, .{ 65535, 0, 0, 65535 }, 300);
        for (0..10) |_| try testing.expect(try s.add(front));
        try s.finish();
        try testing.expectEqual(@as(usize, 10), s.count);
        // 10 cards at 9 a page: 2 pages of fronts, and as many of backs.
        try testing.expectEqual(@as(usize, if (with_back) 4 else 2), w.pages.items.len);
        const bytes = try w.finish();
        defer gpa.free(bytes);
        _ = try vec.expectWellFormed(gpa, bytes);
        try testing.expect(std.mem.indexOf(u8, bytes, if (with_back) "/Count 4" else "/Count 2") != null);
        try testing.expect(std.mem.indexOf(u8, bytes, "/MediaBox [0 0 595.2756 841.8898]") != null);
        // The back is one image, however many pages show it.
        try testing.expectEqual(@as(usize, if (with_back) 2 else 1), std.mem.count(u8, bytes, "/Subtype /Image"));
    }
    // A card larger than the page.
    var w = try pdf.Writer.init(gpa);
    defer w.deinit();
    var s = Sheets.init(&w, .{});
    defer s.deinit();
    const big = try testCard(&w, gpa, .{ 0, 0, 0, 65535 }, 10);
    try testing.expectError(error.CardTooLarge, s.add(big));
    // A card of another size is reported.
    var s2 = Sheets.init(&w, .{});
    defer s2.deinit();
    try testing.expect(try s2.add(try testCard(&w, gpa, .{ 0, 0, 0, 65535 }, 300)));
    try testing.expect(!try s2.add(try testCard(&w, gpa, .{ 0, 0, 0, 65535 }, 600)));
}

test "sheets: vector cards are forms placed on the page, backs turned for short edge" {
    const gpa = testing.allocator;
    const vector = @import("vector.zig");
    var sc = vector.Scene.init(gpa);
    defer sc.deinit();
    sc.width = 750;
    sc.height = 1050;
    sc.dpi = 300;
    sc.background = @import("value.zig").Color.white;
    var w = try pdf.Writer.init(gpa);
    defer w.deinit();
    const card = try w.vectorCard(&sc);
    try testing.expect(!card.image and near(card.w, poker_w) and near(card.h, poker_h));
    var s = Sheets.init(&w, .{ .duplex = .short });
    defer s.deinit();
    s.back = card;
    for (0..3) |_| _ = try s.add(card);
    try s.finish();
    try testing.expectEqual(@as(usize, 2), w.pages.items.len);
    const bytes = try w.finish();
    defer gpa.free(bytes);
    _ = try @import("pdf_vector.zig").expectWellFormed(gpa, bytes);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "/Subtype /Form"));
}
