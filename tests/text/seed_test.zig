//! FP-0013 cases 9, 10, and 11: the seed format, seed properties, and seed coverage.

const std = @import("std");
const testing = std.testing;
const fairpane = @import("fairpane");
const unicode = fairpane.unicode;
const font = fairpane.font;
const WebString = fairpane.web_string.WebString;
const seed = @import("seed.zig");
const fixtures = @import("fixtures.zig");

const valid_seed =
    \\{"format": "fairpane-text-seed", "version": 1, "id": "probe", "unicode_version": "18.0.0",
    \\ "text_utf8": "AA\u00e9", "code_points": ["U+0041", "U+0041", "U+00E9"],
    \\ "properties": {
    \\  "U+0041": {"gc": "Lu", "sc": "Latn", "scx": ["Latn"], "bc": "L", "jt": "U", "InSC": "Other", "InPC": "NA"},
    \\  "U+00E9": {"gc": "Ll", "sc": "Latn", "scx": ["Latn"], "bc": "L", "jt": "U", "InSC": "Other", "InPC": "NA"}},
    \\ "coverage": {"noto-sans": {"covered": ["U+0041"], "uncovered": []}}}
;

/// Parses `valid_seed` with one text replacement; only the error matters.
fn parseWith(original: []const u8, replacement: []const u8) seed.Error!void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const json = try std.mem.replaceOwned(u8, arena.allocator(), valid_seed, original, replacement);
    if (std.mem.eql(u8, json, valid_seed)) @panic("the seed mutation changed nothing");
    _ = try seed.parse(arena.allocator(), json);
}

test "FP-0013 case 9: the seed format rejects malformed seeds, and each committed seed decodes to its code points" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const valid = try seed.parse(arena.allocator(), valid_seed);
    try testing.expectEqualSlices(u21, &.{ 0x41, 0x41, 0xE9 }, valid.code_points);
    try testing.expectEqual(@as(usize, 2), valid.properties.len);

    try testing.expectError(error.UnknownField, parseWith("\"version\": 1,", "\"version\": 1, \"note\": \"x\","));
    try testing.expectError(error.MissingField, parseWith("\"id\": \"probe\",", ""));
    try testing.expectError(error.NoncanonicalCodePoint, parseWith("[\"U+0041\", \"U+0041\"", "[\"U+0041\", \"U+00041\""));
    try testing.expectError(error.NoncanonicalCodePoint, parseWith("[\"U+0041\", \"U+0041\"", "[\"U+0041\", \"U+41\""));
    try testing.expectError(error.NoncanonicalCodePoint, parseWith("\"U+00E9\"]", "\"U+00e9\"]"));
    try testing.expectError(error.MissingPropertyEntry, parseWith(
        ",\n  \"U+00E9\": {\"gc\": \"Ll\", \"sc\": \"Latn\", \"scx\": [\"Latn\"], \"bc\": \"L\", \"jt\": \"U\", \"InSC\": \"Other\", \"InPC\": \"NA\"}",
        "",
    ));
    try testing.expectError(error.ExtraPropertyEntry, parseWith(
        "\"properties\": {",
        "\"properties\": {\"U+0042\": {\"gc\": \"Lu\", \"sc\": \"Latn\", \"scx\": [\"Latn\"], \"bc\": \"L\", \"jt\": \"U\", \"InSC\": \"Other\", \"InPC\": \"NA\"},",
    ));

    for (fixtures.seeds) |s| {
        const parsed = try seed.parse(arena.allocator(), s.json);
        try testing.expectEqualStrings(s.id, parsed.id);
        var text = try WebString.fromUtf8(testing.allocator, parsed.text_utf8);
        defer text.deinit(testing.allocator);
        var decoded: std.ArrayList(u21) = .empty;
        defer decoded.deinit(testing.allocator);
        var it = text.view().codePoints();
        while (it.next()) |cp| try decoded.append(testing.allocator, cp);
        testing.expectEqualSlices(u21, parsed.code_points, decoded.items) catch |e| {
            std.debug.print("seed {s}\n", .{s.id});
            return e;
        };
    }
}

fn scxEqual(expected: []const []const u8, actual: []const unicode.Script) bool {
    if (expected.len != actual.len) return false;
    for (expected) |name| {
        for (actual) |script| {
            if (std.mem.eql(u8, name, @tagName(script))) break;
        } else return false;
    }
    return true;
}

test "FP-0013 case 10: every property of every seed equals unicode.lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (fixtures.seeds) |s| {
        const parsed = try seed.parse(arena.allocator(), s.json);
        for (parsed.properties) |e| {
            const p = try unicode.lookup(e.code_point);
            const same = std.mem.eql(u8, e.gc, @tagName(p.gc)) and std.mem.eql(u8, e.sc, @tagName(p.sc)) and
                scxEqual(e.scx, p.scx) and std.mem.eql(u8, e.bc, @tagName(p.bc)) and std.mem.eql(u8, e.jt, @tagName(p.jt)) and
                std.mem.eql(u8, e.insc, @tagName(p.insc)) and std.mem.eql(u8, e.inpc, @tagName(p.inpc));
            if (!same) {
                std.debug.print("seed {s} U+{X:0>4}: seed {any}, lookup {any}\n", .{ s.id, e.code_point, e, p });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "FP-0013 case 11: every coverage entry of every seed matches glyphIndex on the embedded fixture" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var checked: usize = 0;
    for (fixtures.seeds) |s| {
        const parsed = try seed.parse(arena.allocator(), s.json);
        try testing.expect(parsed.coverage.len > 0);
        for (parsed.coverage) |c| {
            const f = try font.parse(fixtures.font(c.fixture).?.bytes, .{});
            for (c.covered) |cp| {
                if (f.glyphIndex(cp) == 0) {
                    std.debug.print("seed {s}: {s} does not cover U+{X:0>4}\n", .{ s.id, c.fixture, cp });
                    return error.TestUnexpectedResult;
                }
                checked += 1;
            }
            for (c.uncovered) |cp| {
                if (f.glyphIndex(cp) != 0) {
                    std.debug.print("seed {s}: {s} covers U+{X:0>4}\n", .{ s.id, c.fixture, cp });
                    return error.TestUnexpectedResult;
                }
                checked += 1;
            }
        }
    }
    try testing.expect(checked > 0);
}
