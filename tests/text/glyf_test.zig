//! FP-0119 cases 1 to 14: TrueType simple and composite outlines, their budgets, and the contour-to-path rule.
//! F_GLYF and its variants come from `glyf_builder.zig`. Every coordinate is compared with `==`, so −0 equals 0.

const std = @import("std");
const testing = std.testing;
const font = @import("fairpane").font;
const builder = @import("sfnt_builder.zig");
const fglyf = @import("glyf_builder.zig");
const fixtures = @import("fixtures.zig");

const model = font.outline_model;
const decoder = font.glyf_decoder;
const Point = model.Point;
const Verb = model.Verb;
const Limits = model.Limits;
const OutlineError = model.OutlineError;
const TrueTypeGlyph = decoder.TrueTypeGlyph;
const Allocator = std.mem.Allocator;

const gpa = testing.allocator;
const hex = fglyf.hex;
const P = [2]f64;

const on3: [3]bool = @splat(true);
const on4: [4]bool = @splat(true);
const off4: [4]bool = @splat(false);

fn expectPoints(expected: []const P, actual: []const Point) !void {
    if (expected.len != actual.len) {
        std.debug.print("expected {d} points, found {d}\n", .{ expected.len, actual.len });
        return error.TestExpectedEqual;
    }
    for (expected, actual, 0..) |e, a, i| {
        if (e[0] != a.x or e[1] != a.y) {
            std.debug.print("point {d}: expected ({d}, {d}), found ({d}, {d})\n", .{ i, e[0], e[1], a.x, a.y });
            return error.TestExpectedEqual;
        }
    }
}

fn expectGlyph(glyph: TrueTypeGlyph, points: []const P, on_curve: []const bool, ends: []const u32) !void {
    try expectPoints(points, glyph.points);
    try testing.expectEqualSlices(bool, on_curve, glyph.on_curve);
    try testing.expectEqualSlices(u32, ends, glyph.contour_ends);
}

fn expectEmpty(glyph: TrueTypeGlyph) !void {
    try testing.expectEqual(@as(usize, 0), glyph.points.len);
    try testing.expectEqual(@as(usize, 0), glyph.on_curve.len);
    try testing.expectEqual(@as(usize, 0), glyph.contour_ends.len);
    try testing.expectEqual(@as(u8, 0), glyph.depth);
    try testing.expectEqual(@as(u32, 0), glyph.top_level_components);
}

fn expectPath(glyph: TrueTypeGlyph, verbs: []const Verb, points: []const P) !void {
    var path = try glyph.path(gpa);
    defer path.deinit(gpa);
    try testing.expectEqualSlices(Verb, verbs, path.verbs);
    try expectPoints(points, path.points);
}

/// F_GLYF, parsed with checksums rejected, owning its bytes.
const Fixture = struct {
    bytes: []u8,
    font: font.Font,

    fn init(replacements: []const fglyf.Replacement) !Fixture {
        const bytes = try fglyf.build(gpa, replacements);
        errdefer gpa.free(bytes);
        return .{ .bytes = bytes, .font = try font.parse(bytes, .{ .checksums = .reject }) };
    }

    fn deinit(self: *Fixture) void {
        gpa.free(self.bytes);
    }

    fn decode(self: *const Fixture, glyph: u16) OutlineError!TrueTypeGlyph {
        return self.font.trueTypeGlyph(gpa, glyph, .{});
    }
};

/// Decodes `glyph` of F_GLYF with `data` in place of its entry, and expects `expected`.
fn expectVariantError(expected: OutlineError, glyph: u16, data: []const u8, decoded: u16, limits: Limits) !void {
    var fixture = try Fixture.init(&.{.{ .glyph = glyph, .bytes = data }});
    defer fixture.deinit();
    try testing.expectError(expected, fixture.font.trueTypeGlyph(gpa, decoded, limits));
}

/// A copy of `base` with `patch` written at `at`.
fn patched(comptime base: []const u8, comptime at: usize, comptime patch: []const u8) [base.len]u8 {
    var out = base[0..base.len].*;
    @memcpy(out[at..][0..patch.len], patch);
    return out;
}

const t1_points = [_]P{ .{ 10, 20 }, .{ 10, 300 }, .{ -245, 300 }, .{ -245, 45 }, .{ 1000, 45 }, .{ 0, 45 }, .{ -10, 45 } };
const t1_on = [_]bool{ true, true, false, true, true, true, true };

fn expectT1(glyph: TrueTypeGlyph) !void {
    try expectGlyph(glyph, &t1_points, &t1_on, &.{ 3, 6 });
    try testing.expectEqual(@as(u8, 0), glyph.depth);
    try testing.expectEqual(@as(u32, 0), glyph.top_level_components);
}

fn expectC1(glyph: TrueTypeGlyph) !void {
    try expectGlyph(glyph, &.{ .{ 10, -20 }, .{ 110, -20 }, .{ 110, 80 }, .{ 10, 80 } }, &off4, &.{3});
    try testing.expectEqual(@as(u8, 1), glyph.depth);
    try testing.expectEqual(@as(u32, 1), glyph.top_level_components);
    try expectPath(glyph, &.{ .move, .quad, .quad, .quad, .quad, .close }, &.{
        .{ 10, 30 }, .{ 10, -20 }, .{ 60, -20 }, .{ 110, -20 }, .{ 110, 30 }, .{ 110, 80 }, .{ 60, 80 }, .{ 10, 80 }, .{ 10, 30 },
    });
}

fn expectC6(glyph: TrueTypeGlyph) !void {
    try expectGlyph(glyph, &.{ .{ 0, 0 }, .{ 100, 0 }, .{ 50, 100 }, .{ 45, 95 }, .{ 50, 95 }, .{ 50, 100 }, .{ 45, 100 } }, &@as([7]bool, @splat(true)), &.{ 2, 6 });
    try testing.expectEqual(@as(u8, 1), glyph.depth);
    try testing.expectEqual(@as(u32, 2), glyph.top_level_components);
}

fn expectC7(glyph: TrueTypeGlyph) !void {
    try expectGlyph(glyph, &.{ .{ 0, 0 }, .{ 100, 0 }, .{ 50, 100 }, .{ 200, 0 }, .{ 210, 0 }, .{ 210, 10 }, .{ 200, 10 } }, &@as([7]bool, @splat(true)), &.{ 2, 6 });
    try testing.expectEqual(@as(u8, 1), glyph.depth);
    try testing.expectEqual(@as(u32, 2), glyph.top_level_components);
}

test "FP-0119 case 1: B_TT glyphs decode, a CFF font is not TrueType, and glyphs past numGlyphs are out of range" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    {
        var g = try f.trueTypeGlyph(gpa, 0, .{});
        defer g.deinit(gpa);
        try expectGlyph(g, &.{ .{ 50, 0 }, .{ 50, 700 }, .{ 450, 700 }, .{ 450, 0 } }, &on4, &.{3});
        try testing.expectEqual(@as(u8, 0), g.depth);
    }
    {
        var g = try f.trueTypeGlyph(gpa, 1, .{});
        defer g.deinit(gpa);
        try expectEmpty(g);
    }
    {
        var g = try f.trueTypeGlyph(gpa, 2, .{});
        defer g.deinit(gpa);
        try expectGlyph(g, &.{ .{ 10, 0 }, .{ 300, 700 }, .{ 590, 0 } }, &on3, &.{2});
        try testing.expectEqual(@as(u8, 0), g.depth);
        try testing.expectEqual(@as(u32, 0), g.top_level_components);
    }
    {
        var g = try f.trueTypeGlyph(gpa, 3, .{});
        defer g.deinit(gpa);
        try expectGlyph(g, &.{ .{ 10, 0 }, .{ 300, 700 }, .{ 590, 0 } }, &on3, &.{2});
        try testing.expectEqual(@as(u8, 1), g.depth);
        try testing.expectEqual(@as(u32, 1), g.top_level_components);
    }
    try testing.expectError(error.GlyphOutOfRange, f.trueTypeGlyph(gpa, 4, .{}));

    const cff_bytes = try builder.bCff(gpa);
    defer gpa.free(cff_bytes);
    const cff = try font.parse(cff_bytes, .{ .checksums = .reject });
    try testing.expectError(error.NotTrueType, cff.trueTypeGlyph(gpa, 0, .{}));
    try testing.expectError(error.GlyphOutOfRange, cff.trueTypeGlyph(gpa, 2, .{}));
}

test "FP-0119 case 2: T1 expands repeated flags and decodes short, same, and 16-bit coordinates" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    var g = try fixture.decode(fglyf.t1);
    defer g.deinit(gpa);
    try expectT1(g);
}

test "FP-0119 case 3: contours become closed paths with the frozen start-point rule" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    {
        var g = try fixture.decode(fglyf.t1);
        defer g.deinit(gpa);
        try expectPath(g, &.{ .move, .line, .quad, .close, .move, .line, .line, .close }, &.{
            .{ 10, 20 }, .{ 10, 300 }, .{ -245, 300 }, .{ -245, 45 }, .{ 1000, 45 }, .{ 0, 45 }, .{ -10, 45 },
        });
    }
    {
        var g = try fixture.decode(fglyf.t2);
        defer g.deinit(gpa);
        try expectPath(g, &.{ .move, .quad, .quad, .quad, .quad, .close }, &.{
            .{ 0, 50 }, .{ 0, 0 }, .{ 50, 0 }, .{ 100, 0 }, .{ 100, 50 }, .{ 100, 100 }, .{ 50, 100 }, .{ 0, 100 }, .{ 0, 50 },
        });
    }
    {
        var g = try fixture.decode(fglyf.t3);
        defer g.deinit(gpa);
        try expectPath(g, &.{ .move, .quad, .close }, &.{ .{ 0, 0 }, .{ 50, 100 }, .{ 100, 0 } });
    }
    {
        var g = try fixture.decode(fglyf.t4);
        defer g.deinit(gpa);
        try expectPath(g, &.{ .move, .close, .move, .quad, .close }, &.{ .{ 5, 5 }, .{ 7, 9 }, .{ 7, 9 }, .{ 7, 9 } });
    }
    {
        var g = try fixture.decode(fglyf.box);
        defer g.deinit(gpa);
        try expectPath(g, &.{ .move, .line, .line, .line, .close }, &.{ .{ 50, 0 }, .{ 50, 700 }, .{ 450, 700 }, .{ 450, 0 } });
    }
}

test "FP-0119 case 4: component offsets, scales, and the 2 by 2 matrix transform the child" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    {
        var g = try fixture.decode(fglyf.c1);
        defer g.deinit(gpa);
        try expectC1(g);
    }
    const Row = struct { glyph: u16, points: [3]P };
    const rows = [_]Row{
        .{ .glyph = fglyf.c2, .points = .{ .{ 300, -300 }, .{ 350, -300 }, .{ 325, -250 } } },
        .{ .glyph = fglyf.c3, .points = .{ .{ 10, 0 }, .{ -90, 0 }, .{ -40, 150 } } },
        .{ .glyph = fglyf.c4, .points = .{ .{ 0, 0 }, .{ 0, 100 }, .{ -100, 50 } } },
        .{ .glyph = fglyf.c5a, .points = .{ .{ 50, 100 }, .{ 100, 100 }, .{ 75, 150 } } },
        .{ .glyph = fglyf.c5b, .points = .{ .{ 100, 200 }, .{ 150, 200 }, .{ 125, 250 } } },
        .{ .glyph = fglyf.c5c, .points = .{ .{ 100, 200 }, .{ 150, 200 }, .{ 125, 250 } } },
        .{ .glyph = fglyf.c5d, .points = .{ .{ 50.5, 100.5 }, .{ 100.5, 100.5 }, .{ 75.5, 150.5 } } },
    };
    for (rows) |row| {
        var g = try fixture.decode(row.glyph);
        defer g.deinit(gpa);
        expectGlyph(g, &row.points, &on3, &.{2}) catch |err| {
            std.debug.print("glyph {d}\n", .{row.glyph});
            return err;
        };
        try testing.expectEqual(@as(u8, 1), g.depth);
        try testing.expectEqual(@as(u32, 1), g.top_level_components);
    }
}

test "FP-0119 case 5: point matching, composite instructions, nested composites, and word point numbers" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    {
        var g = try fixture.decode(fglyf.c6);
        defer g.deinit(gpa);
        try expectC6(g);
    }
    {
        var g = try fixture.decode(fglyf.c7);
        defer g.deinit(gpa);
        try expectC7(g);
    }
    {
        var g = try fixture.decode(fglyf.c8);
        defer g.deinit(gpa);
        try expectGlyph(g, &.{ .{ 15, -15 }, .{ 115, -15 }, .{ 115, 85 }, .{ 15, 85 } }, &off4, &.{3});
        try testing.expectEqual(@as(u8, 2), g.depth);
        try testing.expectEqual(@as(u32, 1), g.top_level_components);
    }
    {
        var g = try fixture.decode(fglyf.c9);
        defer g.deinit(gpa);
        var expected: [308]P = undefined;
        for (expected[0..300], 0..) |*p, i| {
            const q = fglyf.l300Point(i);
            p.* = .{ @floatFromInt(q[0]), @floatFromInt(q[1]) };
        }
        expected[300..].* = .{ .{ 0, 200 }, .{ 10, 200 }, .{ 10, 210 }, .{ 0, 210 }, .{ 0, 247 }, .{ 10, 247 }, .{ 10, 257 }, .{ 0, 257 } };
        try expectGlyph(g, &expected, &@as([308]bool, @splat(true)), &.{ 299, 303, 307 });
        try testing.expectEqual(@as(u8, 1), g.depth);
        try testing.expectEqual(@as(u32, 3), g.top_level_components);
    }
}

test "FP-0119 case 6: depth 8 decodes, depth 9 is too deep, and cycles are refused" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    {
        var g = try fixture.decode(fglyf.d(8));
        defer g.deinit(gpa);
        try expectGlyph(g, &.{ .{ 0, 0 }, .{ 100, 0 }, .{ 50, 100 } }, &on3, &.{2});
        try testing.expectEqual(@as(u8, 8), g.depth);
    }
    try testing.expectError(error.CompositeTooDeep, fixture.decode(fglyf.d(9)));
    try testing.expectError(error.CompositeCycle, fixture.decode(fglyf.self_reference));
    try testing.expectError(error.CompositeCycle, fixture.decode(fglyf.ping));
    try testing.expectError(error.CompositeCycle, fixture.decode(fglyf.pong));
}

test "FP-0119 case 7: the points and component budgets bound every decode" {
    const defaults: Limits = .{};
    try testing.expectEqual(@as(u32, 65536), defaults.max_points);
    try testing.expectEqual(@as(u32, 65536), defaults.max_components);
    try testing.expectEqual(8, model.max_composite_depth);

    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    const f = &fixture.font;
    {
        var g = try fixture.decode(fglyf.e(7));
        defer g.deinit(gpa);
        try testing.expectEqual(@as(usize, 38400), g.points.len);
        try testing.expectEqual(@as(usize, 128), g.contour_ends.len);
        try testing.expectEqual(@as(u8, 7), g.depth);
    }
    try testing.expectError(error.OutlineTooLarge, fixture.decode(fglyf.e(8)));
    try testing.expect(decoder.work <= 196610);
    {
        var g = try f.trueTypeGlyph(gpa, fglyf.f(3), .{ .max_components = 4368 });
        defer g.deinit(gpa);
        try testing.expectEqual(@as(usize, 0), g.points.len);
        try testing.expectEqual(@as(usize, 0), g.contour_ends.len);
        try testing.expectEqual(@as(u8, 3), g.depth);
        try testing.expectEqual(@as(u32, 16), g.top_level_components);
    }
    try testing.expectError(error.OutlineTooLarge, f.trueTypeGlyph(gpa, fglyf.f(3), .{ .max_components = 4367 }));
    try testing.expectError(error.OutlineTooLarge, fixture.decode(fglyf.f(4)));
    try testing.expect(decoder.work <= 196610);
    try testing.expectError(error.OutlineTooLarge, f.trueTypeGlyph(gpa, fglyf.l300, .{ .max_points = 299 }));
    {
        var g = try f.trueTypeGlyph(gpa, fglyf.l300, .{ .max_points = 300 });
        defer g.deinit(gpa);
        try testing.expectEqual(@as(usize, 300), g.points.len);
    }
    try testing.expectError(error.OutlineTooLarge, f.trueTypeGlyph(gpa, fglyf.c6, .{ .max_components = 1 }));
}

test "FP-0119 case 8: malformed simple glyphs return InvalidGlyph" {
    const t1 = fglyf.t1_bytes;
    const defaults: Limits = .{};
    {
        // X1: equal end points, which glyphHeader still accepts.
        const x1 = patched(t1, 12, hex("0003"));
        var fixture = try Fixture.init(&.{.{ .glyph = fglyf.t1, .bytes = &x1 }});
        defer fixture.deinit();
        try testing.expectError(error.InvalidGlyph, fixture.decode(fglyf.t1));
        try testing.expect((try fixture.font.glyphHeader(fglyf.t1)) != null);
    }
    try expectVariantError(error.InvalidGlyph, fglyf.t1, &patched(t1, 12, hex("0002")), fglyf.t1, defaults); // X2
    try expectVariantError(error.InvalidGlyph, fglyf.t1, t1[0..12], fglyf.t1, defaults); // X3
    try expectVariantError(error.InvalidGlyph, fglyf.t1, &patched(t1, 14, hex("00FF")), fglyf.t1, defaults); // X4
    try expectVariantError(error.InvalidGlyph, fglyf.t1, t1[0..22], fglyf.t1, defaults); // X5
    try expectVariantError(error.InvalidGlyph, fglyf.t1, &patched(t1, 24, hex("03")), fglyf.t1, defaults); // X6
    try expectVariantError(error.InvalidGlyph, fglyf.t1, t1[0..24], fglyf.t1, defaults); // X7
    try expectVariantError(error.InvalidGlyph, fglyf.t1, t1[0..30], fglyf.t1, defaults); // X8
    try expectVariantError(error.InvalidGlyph, fglyf.t1, t1[0..36], fglyf.t1, defaults); // X9
    const x10 = hex("0001 00000000 00000000 FFFF 0000");
    try expectVariantError(error.InvalidGlyph, fglyf.t1, x10, fglyf.t1, defaults);
    try expectVariantError(error.OutlineTooLarge, fglyf.t1, x10, fglyf.t1, .{ .max_points = 65535 });
    try expectVariantError(error.InvalidGlyph, fglyf.t1, hex("0001 0000 0000"), fglyf.t1, defaults); // X11
    try expectVariantError(error.InvalidGlyph, fglyf.t1, hex("7FFF 0000 0000 0000 0000 0000"), fglyf.t1, defaults); // X12
}

test "FP-0119 case 9: malformed composite glyphs return InvalidGlyph, and phantom point matching is unsupported" {
    const defaults: Limits = .{};
    try expectVariantError(error.InvalidGlyph, fglyf.c6, fglyf.c6_bytes[0..20], fglyf.c6, defaults); // Y1
    try expectVariantError(error.InvalidGlyph, fglyf.c2, fglyf.c2_bytes[0..18], fglyf.c2, defaults); // Y2
    // Y3
    try expectVariantError(error.InvalidGlyph, fglyf.c2, &patched(fglyf.c2_bytes, 10, hex("008B")), fglyf.c2, defaults);
    try expectVariantError(error.InvalidGlyph, fglyf.c2, &patched(fglyf.c2_bytes, 10, hex("004B")), fglyf.c2, defaults);
    try expectVariantError(error.InvalidGlyph, fglyf.c2, &patched(fglyf.c2_bytes, 10, hex("00CB")), fglyf.c2, defaults);
    // Y4
    try expectVariantError(error.InvalidGlyph, fglyf.c1, &patched(fglyf.c1_bytes, 12, hex("002D")), fglyf.c1, defaults);
    try expectVariantError(error.InvalidGlyph, fglyf.c1, &patched(fglyf.c1_bytes, 12, hex("FFFF")), fglyf.c1, defaults);
    // Y5
    try expectVariantError(error.InvalidGlyph, fglyf.c7, &patched(fglyf.c7_bytes, 24, hex("0010")), fglyf.c7, defaults);
    // Y6: the parent holds 3 points and the child 4, so 3 to 6 and 4 to 7 name phantom points.
    const Y6 = struct { args: *const [2]u8, expected: OutlineError };
    for ([_]Y6{
        .{ .args = hex("03 02"), .expected = error.UnsupportedPhantomPoint },
        .{ .args = hex("06 02"), .expected = error.UnsupportedPhantomPoint },
        .{ .args = hex("07 02"), .expected = error.InvalidGlyph },
        .{ .args = hex("02 04"), .expected = error.UnsupportedPhantomPoint },
        .{ .args = hex("02 07"), .expected = error.UnsupportedPhantomPoint },
        .{ .args = hex("02 08"), .expected = error.InvalidGlyph },
    }) |row| {
        var y6 = fglyf.c6_bytes.*;
        @memcpy(y6[20..22], row.args);
        try expectVariantError(row.expected, fglyf.c6, &y6, fglyf.c6, defaults);
    }
    // Y7
    try expectVariantError(error.InvalidGlyph, fglyf.c6, &patched(fglyf.c6_bytes, 10, hex("0020")), fglyf.c6, defaults);
    // Y8
    try expectVariantError(error.InvalidGlyph, fglyf.c6, fglyf.c6_bytes[0..16] ++ hex("0009 0006 FFFF 0002 2000"), fglyf.c6, defaults);
    // Y9
    try expectVariantError(error.InvalidGlyph, fglyf.t2, hex("0001 0000 0000"), fglyf.c1, defaults);
    try expectVariantError(error.InvalidGlyph, fglyf.t2, hex("0001 0000 0000"), fglyf.c8, defaults);
}

test "FP-0119 case 10: reserved bits, overlap flags, other negative contour counts, and trailing bytes are ignored" {
    {
        var fixture = try Fixture.init(&.{.{ .glyph = fglyf.t1, .bytes = &patched(fglyf.t1_bytes, 20, hex("91")) }});
        defer fixture.deinit();
        var g = try fixture.decode(fglyf.t1);
        defer g.deinit(gpa);
        try expectT1(g);
    }
    for ([_][]const u8{
        &patched(fglyf.c1_bytes, 10, hex("E012")),
        &patched(fglyf.c1_bytes, 10, hex("0402")),
        &patched(fglyf.c1_bytes, 0, hex("FFFE")),
    }) |c1| {
        var fixture = try Fixture.init(&.{.{ .glyph = fglyf.c1, .bytes = c1 }});
        defer fixture.deinit();
        var g = try fixture.decode(fglyf.c1);
        defer g.deinit(gpa);
        try expectC1(g);
    }
    {
        var fixture = try Fixture.init(&.{.{ .glyph = fglyf.t1, .bytes = fglyf.t1_bytes ++ hex("0000") }});
        defer fixture.deinit();
        var g = try fixture.decode(fglyf.t1);
        defer g.deinit(gpa);
        try expectT1(g);
    }
    {
        var fixture = try Fixture.init(&.{.{ .glyph = fglyf.c7, .bytes = fglyf.c7_bytes ++ hex("0000") }});
        defer fixture.deinit();
        var g = try fixture.decode(fglyf.c7);
        defer g.deinit(gpa);
        try expectC7(g);
    }
}

fn expectSameResult(a: OutlineError!TrueTypeGlyph, b: OutlineError!TrueTypeGlyph) !void {
    const ga = a catch |ea| {
        const eb: ?OutlineError = if (b) |_| null else |e| e;
        try testing.expectEqual(@as(?OutlineError, ea), eb);
        return;
    };
    const gb = b catch |eb| {
        std.debug.print("first decode succeeded, second returned {s}\n", .{@errorName(eb)});
        return error.TestExpectedEqual;
    };
    try testing.expectEqualSlices(Point, ga.points, gb.points);
    try testing.expectEqualSlices(bool, ga.on_curve, gb.on_curve);
    try testing.expectEqualSlices(u32, ga.contour_ends, gb.contour_ends);
    try testing.expectEqual(ga.depth, gb.depth);
    try testing.expectEqual(ga.top_level_components, gb.top_level_components);
}

test "FP-0119 case 11: every prefix and every changed byte of T1, C6, and C7 decodes without a panic or a leak" {
    for ([_]u16{ fglyf.t1, fglyf.c6, fglyf.c7 }) |id| {
        const full = try fglyf.glyphBytes(gpa, id);
        defer gpa.free(full);
        for (0..full.len) |len| {
            var fixture = try Fixture.init(&.{.{ .glyph = id, .bytes = full[0..len] }});
            defer fixture.deinit();
            if (len == 0) {
                var g = try fixture.decode(id);
                defer g.deinit(gpa);
                try expectEmpty(g);
            } else if (fixture.font.trueTypeGlyph(gpa, id, .{})) |decoded| {
                var g = decoded;
                g.deinit(gpa);
                std.debug.print("glyph {d} prefix {d} decoded\n", .{ id, len });
                return error.TestUnexpectedResult;
            } else |err| {
                try testing.expectEqual(@as(OutlineError, error.InvalidGlyph), err);
            }
        }

        const bytes = try fglyf.build(gpa, &.{});
        defer gpa.free(bytes);
        const at = fglyf.glyphOffset(bytes, id);
        try testing.expectEqualSlices(u8, full, bytes[at..][0..full.len]);
        for (0..full.len) |i| {
            const original = bytes[at + i];
            defer bytes[at + i] = original;
            for ([_]u8{ 0x00, 0xFF, original ^ 0x80 }) |value| {
                bytes[at + i] = value;
                const f = try font.parse(bytes, .{ .checksums = .report });
                var first = f.trueTypeGlyph(gpa, id, .{});
                defer if (first) |*g| g.deinit(gpa) else |_| {};
                var second = f.trueTypeGlyph(gpa, id, .{});
                defer if (second) |*g| g.deinit(gpa) else |_| {};
                try expectSameResult(first, second);
            }
        }
    }
}

fn decodeAndPath(allocator: Allocator, f: *const font.Font, glyph: u16) !void {
    var g = try f.trueTypeGlyph(allocator, glyph, .{});
    defer g.deinit(allocator);
    var path = try g.path(allocator);
    defer path.deinit(allocator);
}

/// Tracks the live and peak bytes of every allocation that passes through it.
const PeakAllocator = struct {
    backing: Allocator,
    live: usize = 0,
    peak: usize = 0,

    fn allocator(self: *PeakAllocator) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn grow(self: *PeakAllocator, old: usize, new: usize) void {
        self.live = self.live - old + new;
        self.peak = @max(self.peak, self.live);
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *PeakAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.grow(0, len);
        return result;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *PeakAllocator = @ptrCast(@alignCast(ctx));
        if (!self.backing.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.grow(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *PeakAllocator = @ptrCast(@alignCast(ctx));
        const result = self.backing.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.grow(memory.len, new_len);
        return result;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *PeakAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, ret_addr);
        self.grow(memory.len, 0);
    }
};

test "FP-0119 case 12: every induced allocation failure returns OutOfMemory without a leak, and E7 stays within its peak" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    for ([_]u16{ fglyf.t1, fglyf.c6, fglyf.c7, fglyf.c8 }) |id| {
        try testing.checkAllAllocationFailures(gpa, decodeAndPath, .{ &fixture.font, id });
    }
    var counting: PeakAllocator = .{ .backing = gpa };
    {
        var g = try fixture.font.trueTypeGlyph(counting.allocator(), fglyf.e(7), .{});
        defer g.deinit(counting.allocator());
        try testing.expectEqual(@as(usize, 38400), g.points.len);
    }
    try testing.expectEqual(@as(usize, 0), counting.live);
    try testing.expect(counting.peak <= 64 * 65536 + 65536);
}

const stack_glyphs = [_]u16{ fglyf.d(8), fglyf.d(9), fglyf.self_reference, fglyf.e(8), fglyf.f(4) };

fn decodeOnThread(f: *const font.Font, results: *[stack_glyphs.len]OutlineError!TrueTypeGlyph) void {
    for (stack_glyphs, results) |id, *result| result.* = f.trueTypeGlyph(gpa, id, .{});
}

test "FP-0119 case 13: deep, cyclic, and over-budget composites decode on a 256 KiB stack" {
    var fixture = try Fixture.init(&.{});
    defer fixture.deinit();
    var results: [stack_glyphs.len]OutlineError!TrueTypeGlyph = undefined;
    const thread = try std.Thread.spawn(.{ .stack_size = 256 * 1024 }, decodeOnThread, .{ &fixture.font, &results });
    thread.join();
    defer for (&results) |*result| {
        if (result.*) |*g| g.deinit(gpa) else |_| {}
    };
    const d8 = try results[0];
    try expectGlyph(d8, &.{ .{ 0, 0 }, .{ 100, 0 }, .{ 50, 100 } }, &on3, &.{2});
    try testing.expectEqual(@as(u8, 8), d8.depth);
    try testing.expectError(error.CompositeTooDeep, results[1]);
    try testing.expectError(error.CompositeCycle, results[2]);
    try testing.expectError(error.OutlineTooLarge, results[3]);
    try testing.expectError(error.OutlineTooLarge, results[4]);
}

fn roundHalfUp(v: f64) f64 {
    return @floor(v + 0.5);
}

test "FP-0119 case 14: every glyph of the three TrueType fixtures decodes within its header bounds and maxp maxima" {
    for (fixtures.fonts[0..3]) |fixture| {
        const f = try font.parse(fixture.bytes, .{});
        try testing.expectEqual(font.Outline.truetype, f.outline());
        const maxp = f.maxp().v1.?;
        var glyph: u16 = 0;
        while (glyph < f.glyphCount()) : (glyph += 1) {
            errdefer std.debug.print("{s} glyph {d}\n", .{ fixture.file, glyph });
            var g = try f.trueTypeGlyph(gpa, glyph, .{});
            defer g.deinit(gpa);
            const points = g.points.len;
            const contours = g.contour_ends.len;
            const header = try f.glyphHeader(glyph) orelse {
                try testing.expectEqual(@as(usize, 0), points);
                continue;
            };
            var bounds = [4]f64{ 0, 0, 0, 0 };
            if (points > 0) {
                bounds = .{ g.points[0].x, g.points[0].y, g.points[0].x, g.points[0].y };
                for (g.points) |p| {
                    bounds[0] = @min(bounds[0], p.x);
                    bounds[1] = @min(bounds[1], p.y);
                    bounds[2] = @max(bounds[2], p.x);
                    bounds[3] = @max(bounds[3], p.y);
                }
            }
            const header_bounds = [4]f64{ @floatFromInt(header.x_min), @floatFromInt(header.y_min), @floatFromInt(header.x_max), @floatFromInt(header.y_max) };
            if (header.number_of_contours >= 0) {
                if (points > 0) try testing.expectEqual(header_bounds, bounds);
                try testing.expectEqual(@as(usize, @intCast(header.number_of_contours)), contours);
                try testing.expect(points <= maxp.max_points);
                try testing.expect(contours <= maxp.max_contours);
            } else {
                const rounded = [4]f64{ roundHalfUp(bounds[0]), roundHalfUp(bounds[1]), roundHalfUp(bounds[2]), roundHalfUp(bounds[3]) };
                try testing.expectEqual(header_bounds, rounded);
                try testing.expect(points <= maxp.max_composite_points);
                try testing.expect(contours <= maxp.max_composite_contours);
                try testing.expect(g.top_level_components <= maxp.max_component_elements);
                try testing.expect(g.depth <= maxp.max_component_depth);
            }

            var path = try g.path(gpa);
            defer path.deinit(gpa);
            var moves: usize = 0;
            for (path.verbs, 0..) |verb, i| {
                if (verb != .move) continue;
                moves += 1;
                if (i > 0) try testing.expectEqual(Verb.close, path.verbs[i - 1]);
            }
            try testing.expectEqual(contours, moves);
            if (path.verbs.len > 0) try testing.expectEqual(Verb.close, path.verbs[path.verbs.len - 1]);
        }
    }
}
