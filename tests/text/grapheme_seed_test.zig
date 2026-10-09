//! FP-0108 cases 13 and 14: extended grapheme cluster boundaries of the six qualification seeds.

const std = @import("std");
const testing = std.testing;
const fairpane = @import("fairpane");
const GraphemeBoundaries = fairpane.text.GraphemeBoundaries;
const WebString = fairpane.web_string.WebString;
const seed = @import("seed.zig");
const fixtures = @import("fixtures.zig");

const Expected = struct { id: []const u8, boundaries: []const usize };

/// The code-unit boundaries of each seed, which the FP-0108 contract derives from the cited property lines.
const expected = [_]Expected{
    .{ .id = "latin-baseline", .boundaries = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10 } },
    .{ .id = "arabic-greeting", .boundaries = &.{ 0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 } },
    .{ .id = "devanagari-greeting", .boundaries = &.{ 0, 1, 2, 6, 7, 9, 11, 13, 14, 15, 18, 20 } },
    .{ .id = "cjk-greeting", .boundaries = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23 } },
    .{ .id = "mixed-direction", .boundaries = &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28 } },
    .{ .id = "uncovered-emoji", .boundaries = &.{ 0, 4, 6 } },
};

fn isHighSurrogate(unit: u16) bool {
    return unit >= 0xD800 and unit <= 0xDBFF;
}

fn isLowSurrogate(unit: u16) bool {
    return unit >= 0xDC00 and unit <= 0xDFFF;
}

/// Decodes the seed's UTF-8 text and returns its code units and every boundary that the segmenter yields.
fn segmentSeed(arena: std.mem.Allocator, json: []const u8) !struct { units: []const u16, boundaries: []const usize } {
    const parsed = try seed.parse(arena, json);
    const text = try WebString.fromUtf8(arena, parsed.text_utf8);
    var found: std.ArrayList(usize) = .empty;
    var boundaries = GraphemeBoundaries.init(text.view());
    while (boundaries.next()) |index| try found.append(arena, @backingInt(index));
    try testing.expectEqual(@as(?fairpane.web_string.CodeUnitIndex, null), boundaries.next());
    return .{ .units = text.units, .boundaries = found.items };
}

fn seedJson(id: []const u8) ![]const u8 {
    for (fixtures.seeds) |s| if (std.mem.eql(u8, s.id, id)) return s.json;
    return error.UnknownSeed;
}

test "FP-0108 case 13: each seed gives its derived code-unit boundaries" {
    try testing.expectEqual(fixtures.seeds.len, expected.len);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var failures: usize = 0;
    for (expected) |e| {
        const result = try segmentSeed(arena.allocator(), try seedJson(e.id));
        if (!std.mem.eql(usize, e.boundaries, result.boundaries)) {
            std.debug.print("seed {s}: expected {any}, found {any}\n", .{ e.id, e.boundaries, result.boundaries });
            failures += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), failures);
}

test "FP-0108 case 14: boundaries of every seed strictly increase from 0 to the length and never split a surrogate pair" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (fixtures.seeds) |s| {
        const result = try segmentSeed(arena.allocator(), s.json);
        const units = result.units;
        const found = result.boundaries;
        errdefer std.debug.print("seed {s}: found {any}\n", .{ s.id, found });
        try testing.expect(units.len > 0);
        try testing.expect(found.len >= 2);
        try testing.expectEqual(@as(usize, 0), found[0]);
        try testing.expectEqual(units.len, found[found.len - 1]);
        for (found[0 .. found.len - 1], found[1..]) |a, b| try testing.expect(a < b);
        for (found) |b| {
            if (b == 0 or b == units.len) continue;
            try testing.expect(!(isHighSurrogate(units[b - 1]) and isLowSurrogate(units[b])));
        }
    }
}
