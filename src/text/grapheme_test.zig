//! FP-0108 cases 11, 12, 14, 15, and 16: extended grapheme cluster boundaries over UTF-16 code units.

const std = @import("std");
const testing = std.testing;
const web_string = @import("../web_string.zig");
const grapheme = @import("grapheme.zig");
const GraphemeBoundaries = grapheme.GraphemeBoundaries;

const conformance = @embedFile("../unicode/ucd/auxiliary/GraphemeBreakTest.txt");

/// The longest input of cases 11 and 12, in code units.
const max_units = 64;

const Boundaries = struct {
    buffer: [max_units + 1]usize = undefined,
    len: usize = 0,

    fn slice(self: *const Boundaries) []const usize {
        return self.buffer[0..self.len];
    }
};

fn isHighSurrogate(unit: u16) bool {
    return unit >= 0xD800 and unit <= 0xDBFF;
}

fn isLowSurrogate(unit: u16) bool {
    return unit >= 0xDC00 and unit <= 0xDFFF;
}

/// Runs the segmenter over `units`, collects every boundary, and checks that `next` stays null after the last one.
fn segment(units: []const u16) !Boundaries {
    var found: Boundaries = .{};
    var boundaries = GraphemeBoundaries.init(.{ .units = units });
    while (boundaries.next()) |index| {
        if (found.len == found.buffer.len) return error.TooManyBoundaries;
        found.buffer[found.len] = @backingInt(index);
        found.len += 1;
    }
    try testing.expectEqual(@as(?web_string.CodeUnitIndex, null), boundaries.next());
    return found;
}

/// Case 14: boundaries strictly increase, start at 0, end at the length, and never split a surrogate pair.
fn expectWellFormed(units: []const u16, found: []const usize) !void {
    if (units.len == 0) return testing.expectEqual(@as(usize, 0), found.len);
    try testing.expect(found.len >= 2);
    try testing.expectEqual(@as(usize, 0), found[0]);
    try testing.expectEqual(units.len, found[found.len - 1]);
    for (found[0 .. found.len - 1], found[1..]) |a, b| try testing.expect(a < b);
    for (found) |b| {
        if (b == 0 or b == units.len) continue;
        try testing.expect(!(isHighSurrogate(units[b - 1]) and isLowSurrogate(units[b])));
    }
}

/// Appends the UTF-16 encoding of `code_point` and returns the number of units written.
fn encode(code_point: u21, out: []u16) !usize {
    if (code_point < 0x10000) {
        if (out.len < 1) return error.InputTooLong;
        out[0] = @intCast(code_point);
        return 1;
    }
    if (out.len < 2) return error.InputTooLong;
    const offset = code_point - 0x10000;
    out[0] = @intCast(0xD800 + (offset >> 10));
    out[1] = @intCast(0xDC00 + (offset & 0x3FF));
    return 2;
}

/// One test line of `GraphemeBreakTest.txt`, encoded as UTF-16, with the code-unit index of each `÷`.
const ConformanceLine = struct {
    units_buffer: [max_units]u16 = undefined,
    units_len: usize = 0,
    expected: Boundaries = .{},

    fn units(self: *const ConformanceLine) []const u16 {
        return self.units_buffer[0..self.units_len];
    }
};

fn parseConformanceLine(body: []const u8) !ConformanceLine {
    var line: ConformanceLine = .{};
    var tokens = std.mem.tokenizeAny(u8, body, " \t");
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "÷")) {
            if (line.expected.len == line.expected.buffer.len) return error.InputTooLong;
            line.expected.buffer[line.expected.len] = line.units_len;
            line.expected.len += 1;
        } else if (!std.mem.eql(u8, token, "×")) {
            const code_point = try std.fmt.parseInt(u21, token, 16);
            line.units_len += try encode(code_point, line.units_buffer[line.units_len..]);
        }
    }
    return line;
}

const ConformanceResult = struct { lines: usize, failures: usize };

/// Calls `check` with each test line of the embedded `GraphemeBreakTest.txt` and its line number.
/// A failing line does not stop the run, so the output names every failing line.
fn checkConformance(comptime check: fn (*const ConformanceLine, usize) anyerror!void) !ConformanceResult {
    var lines = std.mem.splitScalar(u8, conformance, '\n');
    var number: usize = 0;
    var result: ConformanceResult = .{ .lines = 0, .failures = 0 };
    while (lines.next()) |raw| {
        number += 1;
        const body = std.mem.trim(u8, raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len], " \t\r");
        if (body.len == 0) continue;
        result.lines += 1;
        const line = parseConformanceLine(body) catch |e| {
            std.debug.print("GraphemeBreakTest.txt line {d}: {t}\n", .{ number, e });
            return e;
        };
        check(&line, number) catch {
            result.failures += 1;
        };
    }
    return result;
}

fn expectConformanceBoundaries(line: *const ConformanceLine, number: usize) !void {
    const found = try segment(line.units());
    if (!std.mem.eql(usize, line.expected.slice(), found.slice())) {
        std.debug.print("GraphemeBreakTest.txt line {d}: expected {any}, found {any}\n", .{ number, line.expected.slice(), found.slice() });
        return error.TestUnexpectedResult;
    }
}

fn expectConformanceWellFormed(line: *const ConformanceLine, number: usize) !void {
    const found = try segment(line.units());
    expectWellFormed(line.units(), found.slice()) catch |e| {
        std.debug.print("GraphemeBreakTest.txt line {d}: malformed boundaries {any}\n", .{ number, found.slice() });
        return e;
    };
}

/// The value of the trailer line `# Lines: <n>`.
fn trailerLineCount() !usize {
    const prefix = "# Lines: ";
    var lines = std.mem.splitScalar(u8, conformance, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (std.mem.startsWith(u8, line, prefix)) return std.fmt.parseInt(usize, line[prefix.len..], 10);
    }
    return error.NoTrailer;
}

test "FP-0108 case 11: every test line of GraphemeBreakTest.txt gives exactly its boundaries" {
    var lines = std.mem.splitScalar(u8, conformance, '\n');
    try testing.expectEqualStrings("# GraphemeBreakTest-18.0.0.txt", std.mem.trimEnd(u8, lines.first(), "\r"));
    try testing.expectEqual(@as(usize, 853), try trailerLineCount());
    const result = try checkConformance(expectConformanceBoundaries);
    try testing.expectEqual(@as(usize, 853), result.lines);
    try testing.expectEqual(@as(usize, 0), result.failures);
}

/// A case 12 row: either code points, which the row encodes as UTF-16, or raw code units.
const Row = struct {
    name: []const u8,
    code_points: []const u21 = &.{},
    units: ?[]const u16 = null,
    expected: []const usize,
};

const rows = [_]Row{
    .{ .name = "G1 line 852", .code_points = &.{ 0x0915, 0x094D, 0x0924 }, .expected = &.{ 0, 3 } },
    .{ .name = "G2 line 859", .code_points = &.{ 0x0061, 0x094D, 0x0924 }, .expected = &.{ 0, 3 } },
    .{ .name = "G3 line 877", .code_points = &.{ 0x1CF5, 0x200C, 0x0995 }, .expected = &.{ 0, 2, 3 } },
    .{ .name = "G4 line 875", .code_points = &.{ 0x1CF5, 0x0995 }, .expected = &.{ 0, 2 } },
    .{ .name = "G5 line 835", .code_points = &.{ 0x0061, 0x1F1E6, 0x1F1E7, 0x1F1E8, 0x0062 }, .expected = &.{ 0, 1, 5, 7, 8 } },
    .{ .name = "G6 line 846", .code_points = &.{ 0x1F476, 0x1F3FF, 0x0308, 0x200D, 0x1F476, 0x1F3FF }, .expected = &.{ 0, 10 } },
    .{ .name = "G7 line 848", .code_points = &.{ 0x0061, 0x200D, 0x1F6D1 }, .expected = &.{ 0, 2, 4 } },
    .{ .name = "G8 line 827", .code_points = &.{ 0x000D, 0x000A, 0x0061, 0x000A, 0x0308 }, .expected = &.{ 0, 2, 3, 4, 5 } },
    .{ .name = "G9 line 833", .code_points = &.{ 0xAC01, 0x11A8, 0x1100 }, .expected = &.{ 0, 2, 3 } },
    .{ .name = "G10 line 841", .code_points = &.{ 0x0061, 0x0903, 0x0062 }, .expected = &.{ 0, 2, 3 } },
    .{ .name = "G11 line 842", .code_points = &.{ 0x0061, 0x0600, 0x0062 }, .expected = &.{ 0, 1, 3 } },
    .{ .name = "G12 line 834", .code_points = &.{ 0x1F1E6, 0x1F1E7, 0x1F1E8, 0x0062 }, .expected = &.{ 0, 4, 6, 7 } },
    .{ .name = "U1", .units = &.{ 0xD800, 0x0308, 0xDC00, 0x0061 }, .expected = &.{ 0, 2, 3, 4 } },
    .{ .name = "U2", .units = &.{ 0xD83D, 0xDE00, 0x0308 }, .expected = &.{ 0, 3 } },
    .{ .name = "U3", .units = &.{ 0xDE00, 0xD83D }, .expected = &.{ 0, 1, 2 } },
    .{ .name = "U4", .units = &.{0xD83D}, .expected = &.{ 0, 1 } },
    .{ .name = "U5", .units = &.{}, .expected = &.{} },
};

/// The code units of `row`, encoded into `buffer` when the row lists code points.
fn rowUnits(row: Row, buffer: *[max_units]u16) ![]const u16 {
    if (row.units) |units| return units;
    var len: usize = 0;
    for (row.code_points) |code_point| len += try encode(code_point, buffer[len..]);
    return buffer[0..len];
}

test "FP-0108 case 12: hard-coded rows give their boundaries independently of the file parser" {
    var failures: usize = 0;
    for (rows) |row| {
        var buffer: [max_units]u16 = undefined;
        const units = try rowUnits(row, &buffer);
        const found = try segment(units);
        if (!std.mem.eql(usize, row.expected, found.slice())) {
            std.debug.print("row {s}: expected {any}, found {any}\n", .{ row.name, row.expected, found.slice() });
            failures += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), failures);
}

test "FP-0108 case 14: boundaries of every case 11 and 12 input strictly increase from 0 to the length and never split a surrogate pair" {
    const result = try checkConformance(expectConformanceWellFormed);
    try testing.expectEqual(@as(usize, 853), result.lines);
    var failures = result.failures;
    for (rows) |row| {
        var buffer: [max_units]u16 = undefined;
        const units = try rowUnits(row, &buffer);
        const found = try segment(units);
        expectWellFormed(units, found.slice()) catch {
            std.debug.print("row {s}: malformed boundaries {any}\n", .{ row.name, found.slice() });
            failures += 1;
        };
    }
    try testing.expectEqual(@as(usize, 0), failures);
}

/// Checks the case 15 work bound after one call of `next`: at most 2 × `b` + 4 units for a boundary `b`,
/// and at most 2 × the length after the last boundary.
fn expectBounded(boundaries: *const GraphemeBoundaries, result: ?web_string.CodeUnitIndex, len: usize) !void {
    const limit = if (result) |index| 2 * @backingInt(index) + 4 else 2 * len;
    if (boundaries.units_read > limit) {
        std.debug.print("after next returned {?d}: {d} code units read, limit {d}\n", .{
            if (result) |index| @backingInt(index) else null, boundaries.units_read, limit,
        });
        return error.TestUnexpectedResult;
    }
}

/// Takes the next boundary, checks the work bound, and requires `expected`.
fn expectNext(boundaries: *GraphemeBoundaries, expected: ?usize, len: usize) !void {
    const result = boundaries.next();
    try expectBounded(boundaries, result, len);
    const actual: ?usize = if (result) |index| @backingInt(index) else null;
    try testing.expectEqual(expected, actual);
}

/// `a` followed by 999,999 combining diaereses is one cluster.
fn checkCombiningMarks(units: []u16) !void {
    units[0] = 'a';
    @memset(units[1..], 0x0308);
    var boundaries = GraphemeBoundaries.init(.{ .units = units });
    try expectNext(&boundaries, 0, units.len);
    try expectNext(&boundaries, units.len, units.len);
    try expectNext(&boundaries, null, units.len);
}

/// 500,000 regional indicators pair up into 250,000 clusters of 4 code units.
fn checkRegionalIndicators(units: []u16) !void {
    for (0..units.len / 2) |i| {
        units[2 * i] = 0xD83C;
        units[2 * i + 1] = 0xDDE6;
    }
    var boundaries = GraphemeBoundaries.init(.{ .units = units });
    for (0..units.len / 4 + 1) |k| try expectNext(&boundaries, 4 * k, units.len);
    try expectNext(&boundaries, null, units.len);
}

/// 333,333 pairs of KA and VIRAMA followed by TA form one cluster by GB9 and GB9c.
fn checkConjuncts(units: []u16) !void {
    const conjunct = units[0 .. 2 * 333_333 + 1];
    for (0..333_333) |i| {
        conjunct[2 * i] = 0x0915;
        conjunct[2 * i + 1] = 0x094D;
    }
    conjunct[conjunct.len - 1] = 0x0924;
    var boundaries = GraphemeBoundaries.init(.{ .units = conjunct });
    try expectNext(&boundaries, 0, conjunct.len);
    try expectNext(&boundaries, 666_667, conjunct.len);
    try expectNext(&boundaries, null, conjunct.len);
}

test "FP-0108 case 15: segmentation work is linear in the code-unit length" {
    const units = try testing.allocator.alloc(u16, 1_000_000);
    defer testing.allocator.free(units);
    const inputs = .{
        .{ "combining marks", checkCombiningMarks },
        .{ "regional indicators", checkRegionalIndicators },
        .{ "conjuncts", checkConjuncts },
    };
    var failures: usize = 0;
    inline for (inputs) |input| {
        input[1](units) catch |e| {
            std.debug.print("case 15 input {s}: {t}\n", .{ input[0], e });
            failures += 1;
        };
    }
    try testing.expectEqual(@as(usize, 0), failures);
}

fn takesAllocator(comptime function: anytype) bool {
    for (@typeInfo(@TypeOf(function)).@"fn".param_types) |param_type| {
        if (param_type.? == std.mem.Allocator) return true;
    }
    return false;
}

test "FP-0108 case 16: the segmenter takes no allocator and its sources name none" {
    comptime {
        if (takesAllocator(GraphemeBoundaries.init)) @compileError("GraphemeBoundaries.init takes an allocator");
        if (takesAllocator(GraphemeBoundaries.next)) @compileError("GraphemeBoundaries.next takes an allocator");
    }
    try testing.expect(@typeInfo(@TypeOf(GraphemeBoundaries.next)).@"fn".return_type.? == ?web_string.CodeUnitIndex);
    const sources = [_]struct { []const u8, []const u8 }{
        .{ "src/text/grapheme.zig", @embedFile("grapheme.zig") },
        .{ "src/text/text.zig", @embedFile("text.zig") },
    };
    for (sources) |source| {
        for ([_][]const u8{ "Allocator", "allocator", "std.heap" }) |forbidden| {
            if (std.mem.indexOf(u8, source[1], forbidden) != null) {
                std.debug.print("{s} names {s}\n", .{ source[0], forbidden });
                return error.TestUnexpectedResult;
            }
        }
    }
}
