//! Lossless JavaScript strings stored as UTF-16 code units.
//!
//! Positions are typed: `CodeUnitIndex` counts UTF-16 code units, and
//! `Utf8ByteIndex` counts bytes of a UTF-8 encoding. The two never mix.

const std = @import("std");
const Allocator = std.mem.Allocator;
/// The engine's single UTF-8 decoder, which the Encoding Standard defines.
const utf8 = @import("encoding/utf8.zig");

/// A position in a sequence of UTF-16 code units.
pub const CodeUnitIndex = enum(usize) { _ };

/// A position in a sequence of UTF-8 bytes.
pub const Utf8ByteIndex = enum(usize) { _ };

const replacement_character: u21 = 0xFFFD;

/// A borrowed view of JavaScript code units, not Unicode scalar values.
/// The caller owns the storage and keeps it alive for this view.
pub const View = struct {
    units: []const u16,

    pub fn codeUnitLen(self: View) usize {
        return self.units.len;
    }

    pub fn codeUnitAt(self: View, index: CodeUnitIndex) ?u16 {
        const position = @backingInt(index);
        if (position >= self.units.len) return null;
        return self.units[position];
    }

    /// Compares code units exactly, without normalization.
    pub fn eql(self: View, other: View) bool {
        return std.mem.eql(u16, self.units, other.units);
    }

    /// Orders code units numerically, as ECMAScript `IsLessThan` orders strings.
    pub fn order(self: View, other: View) std.math.Order {
        return std.mem.order(u16, self.units, other.units);
    }

    /// Iterates code points as ECMAScript `CodePointAt` does, without allocating.
    /// A lone surrogate yields its own code point, so the result is not always a scalar value.
    pub fn codePoints(self: View) CodePointIterator {
        return .{ .units = self.units };
    }
};

/// An owned, immutable sequence of UTF-16 code units.
/// It stores any code unit, including zero and unpaired surrogates.
/// The caller passes the same allocator to every allocating function and to `deinit`.
/// An empty string owns no allocation.
pub const WebString = struct {
    units: []const u16,

    pub const empty: WebString = .{ .units = &.{} };

    /// Copies `units` exactly.
    pub fn fromCodeUnits(gpa: Allocator, units: []const u16) Allocator.Error!WebString {
        return joinUnits(gpa, units, &.{});
    }

    /// Decodes well-formed UTF-8, or returns `error.InvalidUtf8` at the first decoder error.
    pub fn fromUtf8(gpa: Allocator, bytes: []const u8) (Allocator.Error || error{InvalidUtf8})!WebString {
        var scalars: utf8.Scalars = .{ .bytes = bytes };
        var len: usize = 0;
        while (scalars.next()) |item| {
            switch (item) {
                .scalar => |scalar| len += utf16Len(scalar),
                .failure => return error.InvalidUtf8,
            }
        }
        return decodeUtf8(gpa, bytes, len);
    }

    /// Decodes with the WHATWG UTF-8 decoder and emits U+FFFD for each decoder error.
    pub fn fromUtf8Lossy(gpa: Allocator, bytes: []const u8) Allocator.Error!WebString {
        var scalars: utf8.Scalars = .{ .bytes = bytes };
        var len: usize = 0;
        while (scalars.next()) |item| {
            len += switch (item) {
                .scalar => |scalar| utf16Len(scalar),
                .failure => 1,
            };
        }
        return decodeUtf8(gpa, bytes, len);
    }

    /// Returns a view that stays valid until `deinit`.
    pub fn view(self: WebString) View {
        return .{ .units = self.units };
    }

    /// Returns an independent copy.
    pub fn clone(self: WebString, gpa: Allocator) Allocator.Error!WebString {
        return joinUnits(gpa, self.units, &.{});
    }

    /// Returns the code units of `a` followed by the code units of `b`.
    pub fn concat(gpa: Allocator, a: View, b: View) Allocator.Error!WebString {
        return joinUnits(gpa, a.units, b.units);
    }

    /// Copies the code units in `[start, end)`.
    /// The copy keeps a lone surrogate when the bounds split a surrogate pair.
    pub fn slice(
        self: WebString,
        gpa: Allocator,
        start: CodeUnitIndex,
        end: CodeUnitIndex,
    ) (Allocator.Error || error{OutOfBounds})!WebString {
        const first = @backingInt(start);
        const last = @backingInt(end);
        if (first > last or last > self.units.len) return error.OutOfBounds;
        return joinUnits(gpa, self.units[first..last], &.{});
    }

    /// Encodes as UTF-8, or returns `error.UnpairedSurrogate` for any unpaired surrogate.
    /// The caller frees the result with `gpa`.
    pub fn toUtf8Alloc(self: WebString, gpa: Allocator) (Allocator.Error || error{UnpairedSurrogate})![]u8 {
        var code_points: CodePointIterator = .{ .units = self.units };
        var len: usize = 0;
        while (code_points.next()) |code_point| {
            if (isSurrogate(code_point)) return error.UnpairedSurrogate;
            len = try addLength(len, utf8Len(code_point));
        }
        return encodeUtf8(gpa, self.units, len);
    }

    /// Encodes the scalar value string as UTF-8, replacing each unpaired surrogate with U+FFFD.
    /// The caller frees the result with `gpa`.
    pub fn toUtf8LossyAlloc(self: WebString, gpa: Allocator) Allocator.Error![]u8 {
        var code_points: CodePointIterator = .{ .units = self.units };
        var len: usize = 0;
        while (code_points.next()) |code_point| {
            len = try addLength(len, utf8Len(toScalar(code_point)));
        }
        return encodeUtf8(gpa, self.units, len);
    }

    pub fn deinit(self: *WebString, gpa: Allocator) void {
        if (self.units.len != 0) gpa.free(self.units);
        self.* = undefined;
    }

    fn joinUnits(gpa: Allocator, a: []const u16, b: []const u16) Allocator.Error!WebString {
        const len = a.len + b.len;
        if (len == 0) return empty;
        const units = try gpa.alloc(u16, len);
        errdefer gpa.free(units);
        @memcpy(units[0..a.len], a);
        @memcpy(units[a.len..], b);
        return .{ .units = units };
    }

    /// Decodes `bytes` into exactly `len` code units, emitting U+FFFD for each decoder error.
    fn decodeUtf8(gpa: Allocator, bytes: []const u8, len: usize) Allocator.Error!WebString {
        if (len == 0) return empty;
        const units = try gpa.alloc(u16, len);
        errdefer gpa.free(units);
        var scalars: utf8.Scalars = .{ .bytes = bytes };
        var written: usize = 0;
        while (scalars.next()) |item| {
            const scalar = switch (item) {
                .scalar => |scalar| scalar,
                .failure => replacement_character,
            };
            written += writeUtf16(units[written..], scalar);
        }
        std.debug.assert(written == len);
        return .{ .units = units };
    }

    /// Encodes `units` into exactly `len` UTF-8 bytes, replacing each unpaired surrogate with U+FFFD.
    fn encodeUtf8(gpa: Allocator, units: []const u16, len: usize) Allocator.Error![]u8 {
        if (len == 0) return &.{};
        const bytes = try gpa.alloc(u8, len);
        errdefer gpa.free(bytes);
        var code_points: CodePointIterator = .{ .units = units };
        var written: usize = 0;
        while (code_points.next()) |code_point| {
            written += writeUtf8(bytes[written..], toScalar(code_point));
        }
        std.debug.assert(written == len);
        return bytes;
    }
};

/// Maps a byte offset in well-formed UTF-8 to the code-unit index of the decoded string.
/// The end offset maps to the decoded length.
/// Ill-formed input returns `error.InvalidUtf8` for every offset.
pub fn codeUnitIndexForUtf8Offset(
    bytes: []const u8,
    offset: Utf8ByteIndex,
) error{ InvalidUtf8, NotScalarBoundary, OutOfBounds }!CodeUnitIndex {
    const target = @backingInt(offset);
    var scalars: utf8.Scalars = .{ .bytes = bytes };
    var units: usize = 0;
    var found: ?usize = null;
    while (true) {
        // Between items the decoder holds no pending byte, so `index` is a scalar boundary.
        if (scalars.index == target) found = units;
        const item = scalars.next() orelse break;
        switch (item) {
            .scalar => |scalar| units += utf16Len(scalar),
            .failure => return error.InvalidUtf8,
        }
    }
    if (target > bytes.len) return error.OutOfBounds;
    const index = found orelse return error.NotScalarBoundary;
    return @fromBackingInt(@intCast(index));
}

/// Maps a code-unit index to the byte offset of the strict UTF-8 encoding.
/// The end index maps to the encoded length.
/// Only the code units before `index` must form a scalar value string.
pub fn utf8OffsetForCodeUnitIndex(
    string: View,
    index: CodeUnitIndex,
) error{ InsideSurrogatePair, UnpairedSurrogate, OutOfBounds }!Utf8ByteIndex {
    const target = @backingInt(index);
    if (target > string.units.len) return error.OutOfBounds;
    var code_points: CodePointIterator = .{ .units = string.units };
    var offset: usize = 0;
    while (code_points.index < target) {
        const code_point = code_points.next().?;
        if (isSurrogate(code_point)) return error.UnpairedSurrogate;
        if (code_points.index > target) return error.InsideSurrogatePair;
        offset += utf8Len(code_point);
    }
    return @fromBackingInt(@intCast(offset));
}

/// Iterates code points as ECMAScript `CodePointAt` does.
/// A high surrogate pairs only with an immediately following low surrogate.
/// Every other surrogate yields its own surrogate code point.
pub const CodePointIterator = struct {
    units: []const u16,
    index: usize = 0,

    pub fn next(self: *CodePointIterator) ?u21 {
        if (self.index == self.units.len) return null;
        const first = self.units[self.index];
        self.index += 1;
        if (first >= 0xD800 and first <= 0xDBFF and self.index < self.units.len) {
            const second = self.units[self.index];
            if (second >= 0xDC00 and second <= 0xDFFF) {
                self.index += 1;
                return 0x10000 + ((@as(u21, first) - 0xD800) << 10) + (second - 0xDC00);
            }
        }
        return first;
    }
};

fn isSurrogate(code_point: u21) bool {
    return code_point >= 0xD800 and code_point <= 0xDFFF;
}

fn toScalar(code_point: u21) u21 {
    return if (isSurrogate(code_point)) replacement_character else code_point;
}

/// Adds to an output length; a length past the address space cannot be allocated.
fn addLength(len: usize, extra: usize) Allocator.Error!usize {
    return std.math.add(usize, len, extra) catch return error.OutOfMemory;
}

fn utf16Len(scalar: u21) usize {
    return if (scalar < 0x10000) 1 else 2;
}

fn utf8Len(code_point: u21) usize {
    if (code_point < 0x80) return 1;
    if (code_point < 0x800) return 2;
    if (code_point < 0x10000) return 3;
    return 4;
}

/// Writes a scalar value as one code unit or a surrogate pair.
fn writeUtf16(out: []u16, scalar: u21) usize {
    if (scalar < 0x10000) {
        out[0] = @intCast(scalar);
        return 1;
    }
    const offset = scalar - 0x10000;
    out[0] = @intCast(0xD800 + (offset >> 10));
    out[1] = @intCast(0xDC00 + (offset & 0x3FF));
    return 2;
}

/// Writes a scalar value as one to four UTF-8 bytes.
fn writeUtf8(out: []u8, scalar: u21) usize {
    const len = utf8Len(scalar);
    switch (len) {
        1 => out[0] = @intCast(scalar),
        2 => {
            out[0] = @intCast(0xC0 | (scalar >> 6));
            out[1] = @intCast(0x80 | (scalar & 0x3F));
        },
        3 => {
            out[0] = @intCast(0xE0 | (scalar >> 12));
            out[1] = @intCast(0x80 | ((scalar >> 6) & 0x3F));
            out[2] = @intCast(0x80 | (scalar & 0x3F));
        },
        4 => {
            out[0] = @intCast(0xF0 | (scalar >> 18));
            out[1] = @intCast(0x80 | ((scalar >> 12) & 0x3F));
            out[2] = @intCast(0x80 | ((scalar >> 6) & 0x3F));
            out[3] = @intCast(0x80 | (scalar & 0x3F));
        },
        else => unreachable,
    }
    return len;
}

const testing = std.testing;

fn expectUnits(expected: []const u16, string: WebString) !void {
    try testing.expectEqualSlices(u16, expected, string.view().units);
}

fn expectLossyUnits(bytes: []const u8, expected: []const u16) !void {
    var string = try WebString.fromUtf8Lossy(testing.allocator, bytes);
    defer string.deinit(testing.allocator);
    try expectUnits(expected, string);
}

fn expectStrictUtf8(units: []const u16, expected: []const u8) !void {
    var string = try WebString.fromCodeUnits(testing.allocator, units);
    defer string.deinit(testing.allocator);
    const bytes = try string.toUtf8Alloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, expected, bytes);
}

fn expectStrictUtf8Error(units: []const u16) !void {
    var string = try WebString.fromCodeUnits(testing.allocator, units);
    defer string.deinit(testing.allocator);
    try testing.expectError(error.UnpairedSurrogate, string.toUtf8Alloc(testing.allocator));
}

fn cu(index: usize) CodeUnitIndex {
    return @fromBackingInt(@intCast(index));
}

fn byteOffset(index: usize) Utf8ByteIndex {
    return @fromBackingInt(@intCast(index));
}

test "1: fromCodeUnits preserves zero and unpaired surrogates exactly" {
    const units = [_]u16{ 0x0041, 0xD800, 0x0000, 0xDC00, 0xDC00, 0xD800 };
    var string = try WebString.fromCodeUnits(testing.allocator, &units);
    defer string.deinit(testing.allocator);
    try expectUnits(&units, string);
    try testing.expect(string.view().units.ptr != @as([]const u16, &units).ptr);
}

test "2: empty input succeeds without allocating" {
    const failing = testing.failing_allocator;

    var from_units = try WebString.fromCodeUnits(failing, &.{});
    defer from_units.deinit(failing);
    var from_utf8 = try WebString.fromUtf8(failing, "");
    defer from_utf8.deinit(failing);

    for ([_]WebString{ from_units, from_utf8 }) |string| {
        try testing.expectEqual(@as(usize, 0), string.view().codeUnitLen());
        try testing.expectEqual(@as(?u16, null), string.view().codeUnitAt(cu(0)));

        const strict = try string.toUtf8Alloc(failing);
        defer failing.free(strict);
        try testing.expectEqual(@as(usize, 0), strict.len);

        const lossy = try string.toUtf8LossyAlloc(failing);
        defer failing.free(lossy);
        try testing.expectEqual(@as(usize, 0), lossy.len);
    }
}

test "3: fromUtf8 preserves NUL and round-trips through toUtf8Alloc" {
    var string = try WebString.fromUtf8(testing.allocator, "a\x00b");
    defer string.deinit(testing.allocator);
    try expectUnits(&.{ 0x0061, 0x0000, 0x0062 }, string);

    const bytes = try string.toUtf8Alloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, "a\x00b", bytes);
}

test "4: fromUtf8 decodes two-, four-byte, and maximum scalars" {
    const cases = [_]struct { bytes: []const u8, units: []const u16 }{
        .{ .bytes = "\xC3\xA9", .units = &.{0x00E9} },
        .{ .bytes = "\xF0\x9F\x98\x80", .units = &.{ 0xD83D, 0xDE00 } },
        .{ .bytes = "\xF4\x8F\xBF\xBF", .units = &.{ 0xDBFF, 0xDFFF } },
    };
    for (cases) |case| {
        var string = try WebString.fromUtf8(testing.allocator, case.bytes);
        defer string.deinit(testing.allocator);
        try expectUnits(case.units, string);
    }
}

test "5: fromUtf8 rejects ill-formed input" {
    const inputs = [_][]const u8{
        "\xC0\xAF",
        "\xE0\x80\xAF",
        "\xED\xA0\x80",
        "\xF4\x90\x80\x80",
        "\xE2\x82",
        "\x80",
        "\xFF",
    };
    for (inputs) |bytes| {
        try testing.expectError(error.InvalidUtf8, WebString.fromUtf8(testing.allocator, bytes));
    }
}

test "6: fromUtf8Lossy restores the offending byte after each error" {
    try expectLossyUnits(
        "\x61\xF1\x80\x80\xE1\x80\xC2\x62\x80\x63\x80\xBF\x64",
        &.{ 0x0061, 0xFFFD, 0xFFFD, 0xFFFD, 0x0062, 0xFFFD, 0x0063, 0xFFFD, 0xFFFD, 0x0064 },
    );
}

test "7: fromUtf8Lossy substitutes maximal subparts" {
    try expectLossyUnits("\xED\xA0\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD });
    try expectLossyUnits("\xF4\x90\x80\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD });
    try expectLossyUnits("\xC0\xAF", &.{ 0xFFFD, 0xFFFD });
    try expectLossyUnits("\xE2\x82", &.{0xFFFD});
}

test "8: toUtf8Alloc rejects unpaired surrogates and encodes pairs" {
    try expectStrictUtf8Error(&.{0xD800});
    try expectStrictUtf8Error(&.{0xDC00});
    try expectStrictUtf8Error(&.{ 0xDC00, 0xD800 });
    try expectStrictUtf8(&.{ 0xD83D, 0xDE00 }, "\xF0\x9F\x98\x80");
}

test "9: toUtf8LossyAlloc replaces each unpaired surrogate" {
    var string = try WebString.fromCodeUnits(testing.allocator, &.{ 0x0061, 0xD800, 0x0062, 0xDC00, 0xD83D, 0xDE00 });
    defer string.deinit(testing.allocator);
    const bytes = try string.toUtf8LossyAlloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, "\x61\xEF\xBF\xBD\x62\xEF\xBF\xBD\xF0\x9F\x98\x80", bytes);
}

test "10: eql and order do not normalize" {
    const composed: View = .{ .units = &.{0x00E9} };
    const decomposed: View = .{ .units = &.{ 0x0065, 0x0301 } };
    try testing.expect(!composed.eql(decomposed));
    try testing.expect(composed.eql(composed));
    try testing.expectEqual(std.math.Order.gt, composed.order(decomposed));
}

test "11: order compares code units, not code points" {
    const halfwidth: View = .{ .units = &.{0xFF61} };
    const emoji: View = .{ .units = &.{ 0xD83D, 0xDE00 } };
    try testing.expectEqual(std.math.Order.gt, halfwidth.order(emoji));
    try testing.expectEqual(std.math.Order.lt, emoji.order(halfwidth));
}

test "12: slice splits a pair and concat rejoins it" {
    var pair = try WebString.fromCodeUnits(testing.allocator, &.{ 0xD83D, 0xDE00 });
    defer pair.deinit(testing.allocator);
    var high = try pair.slice(testing.allocator, cu(0), cu(1));
    defer high.deinit(testing.allocator);
    try expectUnits(&.{0xD83D}, high);

    const low: View = .{ .units = &.{0xDE00} };
    var joined = try WebString.concat(testing.allocator, high.view(), low);
    defer joined.deinit(testing.allocator);
    const bytes = try joined.toUtf8Alloc(testing.allocator);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, "\xF0\x9F\x98\x80", bytes);
}

test "13: slice rejects reversed and out-of-range bounds" {
    var string = try WebString.fromCodeUnits(testing.allocator, &.{ 0x0061, 0x0062, 0x0063 });
    defer string.deinit(testing.allocator);
    try testing.expectError(error.OutOfBounds, string.slice(testing.allocator, cu(2), cu(1)));
    try testing.expectError(error.OutOfBounds, string.slice(testing.allocator, cu(0), cu(4)));
}

const case_14_text = "a\xC3\xA9\xF0\x9F\x98\x80b";

test "14: UTF-8 byte offsets map to code-unit indexes" {
    const mapped = [_][2]usize{ .{ 0, 0 }, .{ 1, 1 }, .{ 3, 2 }, .{ 7, 4 }, .{ 8, 5 } };
    for (mapped) |pair| {
        try testing.expectEqual(cu(pair[1]), try codeUnitIndexForUtf8Offset(case_14_text, byteOffset(pair[0])));
    }
    for ([_]usize{ 2, 4, 5, 6 }) |offset| {
        try testing.expectError(error.NotScalarBoundary, codeUnitIndexForUtf8Offset(case_14_text, byteOffset(offset)));
    }
    try testing.expectError(error.OutOfBounds, codeUnitIndexForUtf8Offset(case_14_text, byteOffset(9)));
}

test "15: code-unit indexes reject pair interiors, unpaired prefixes, and overruns" {
    var decoded = try WebString.fromUtf8(testing.allocator, case_14_text);
    defer decoded.deinit(testing.allocator);
    try testing.expectError(error.InsideSurrogatePair, utf8OffsetForCodeUnitIndex(decoded.view(), cu(3)));
    try testing.expectError(error.OutOfBounds, utf8OffsetForCodeUnitIndex(decoded.view(), cu(6)));

    const unpaired: View = .{ .units = &.{ 0xD800, 0x0061 } };
    try testing.expectError(error.UnpairedSurrogate, utf8OffsetForCodeUnitIndex(unpaired, cu(2)));
}

fn allocationFailureScenario(gpa: std.mem.Allocator) !void {
    var units = try WebString.fromCodeUnits(gpa, &.{ 0x0061, 0xD83D });
    defer units.deinit(gpa);
    var strict = try WebString.fromUtf8(gpa, "\xC3\xA9\xF0\x9F\x98\x80");
    defer strict.deinit(gpa);
    var lossy = try WebString.fromUtf8Lossy(gpa, "\xDE\x00\xFF");
    defer lossy.deinit(gpa);
    var copy = try strict.clone(gpa);
    defer copy.deinit(gpa);
    var joined = try WebString.concat(gpa, units.view(), copy.view());
    defer joined.deinit(gpa);
    var part = try joined.slice(gpa, cu(2), cu(5));
    defer part.deinit(gpa);
    const strict_bytes = try part.toUtf8Alloc(gpa);
    defer gpa.free(strict_bytes);
    const lossy_bytes = try lossy.toUtf8LossyAlloc(gpa);
    defer gpa.free(lossy_bytes);

    try expectUnits(&.{ 0x0061, 0xD83D, 0x00E9, 0xD83D, 0xDE00 }, joined);
    try testing.expectEqualSlices(u8, "\xC3\xA9\xF0\x9F\x98\x80", strict_bytes);
    try testing.expectEqualSlices(u8, "\xEF\xBF\xBD\x00\xEF\xBF\xBD", lossy_bytes);
}

test "16: every allocating operation survives each induced allocation failure" {
    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_remap.allocator(), allocationFailureScenario, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

test "FP-0047 case 1: fromUtf8 rejects an F0 lead followed by a byte below 0x90" {
    for ([_][]const u8{ "\xF0\x80\x80\x80", "\xF0\x8F\xBF\xBF" }) |bytes| {
        try testing.expectError(error.InvalidUtf8, WebString.fromUtf8(testing.allocator, bytes));
    }
}

test "FP-0047 case 2: fromUtf8Lossy emits four U+FFFD for an F0 lead followed by a byte below 0x90" {
    try expectLossyUnits("\xF0\x80\x80\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD });
    try expectLossyUnits("\xF0\x8F\xBF\xBF", &.{ 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD });
}

test "FP-0047 case 3: fromUtf8 decodes the scalars at the E0, ED, and F0 boundaries" {
    const cases = [_]struct { bytes: []const u8, units: []const u16 }{
        .{ .bytes = "\xE0\xA0\x80", .units = &.{0x0800} },
        .{ .bytes = "\xED\x9F\xBF", .units = &.{0xD7FF} },
        .{ .bytes = "\xF0\x90\x80\x80", .units = &.{ 0xD800, 0xDC00 } },
    };
    for (cases) |case| {
        var string = try WebString.fromUtf8(testing.allocator, case.bytes);
        defer string.deinit(testing.allocator);
        try expectUnits(case.units, string);
    }
}

test "FP-0047 case 4: fromUtf8 rejects the F5 and C1 lead bytes" {
    for ([_][]const u8{ "\xF5\x80\x80\x80", "\xC1\xBF" }) |bytes| {
        try testing.expectError(error.InvalidUtf8, WebString.fromUtf8(testing.allocator, bytes));
    }
}

test "FP-0047 case 5: fromUtf8Lossy replaces each byte after an F5 or C1 lead byte" {
    try expectLossyUnits("\xF5\x80\x80\x80", &.{ 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD });
    try expectLossyUnits("\xC1\xBF", &.{ 0xFFFD, 0xFFFD });
}

test "FP-0047 case 6: codeUnitIndexForUtf8Offset reports ill-formed input before an out-of-range offset" {
    try testing.expectError(error.InvalidUtf8, codeUnitIndexForUtf8Offset("a\x80", byteOffset(1)));
    try testing.expectError(error.InvalidUtf8, codeUnitIndexForUtf8Offset("a\x80", byteOffset(5)));
}

test "FP-0123 case 14: fromUtf8 and fromUtf8Lossy keep a leading U+FEFF, and offsets reject an encoded surrogate" {
    var strict = try WebString.fromUtf8(testing.allocator, "\xEF\xBB\xBF\x41");
    defer strict.deinit(testing.allocator);
    try expectUnits(&.{ 0xFEFF, 0x0041 }, strict);
    try expectLossyUnits("\xEF\xBB\xBF\x41", &.{ 0xFEFF, 0x0041 });
    try testing.expectError(error.InvalidUtf8, codeUnitIndexForUtf8Offset("\xED\xA0\x80", byteOffset(0)));
}

test "code-unit indexes map back to UTF-8 byte offsets" {
    var decoded = try WebString.fromUtf8(testing.allocator, case_14_text);
    defer decoded.deinit(testing.allocator);
    const mapped = [_][2]usize{ .{ 0, 0 }, .{ 1, 1 }, .{ 2, 3 }, .{ 4, 7 }, .{ 5, 8 } };
    for (mapped) |pair| {
        try testing.expectEqual(byteOffset(pair[1]), try utf8OffsetForCodeUnitIndex(decoded.view(), cu(pair[0])));
    }
}

test "a view preserves isolated surrogate code units" {
    const units = [_]u16{ 0x0041, 0xD800, 0x0062, 0xDC00 };
    const view: View = .{ .units = &units };
    try testing.expectEqual(@as(usize, 4), view.codeUnitLen());
    try testing.expectEqual(@as(?u16, 0xD800), view.codeUnitAt(cu(1)));
    try testing.expectEqual(@as(?u16, 0xDC00), view.codeUnitAt(cu(3)));
    try testing.expectEqual(@as(?u16, null), view.codeUnitAt(cu(4)));
}

test "surrogate pairs occupy two indexed code units" {
    const pair = [_]u16{ 0xD83D, 0xDE00 };
    const view: View = .{ .units = &pair };
    try testing.expectEqual(@as(usize, 2), view.codeUnitLen());
    try testing.expectEqual(@as(?u16, 0xDE00), view.codeUnitAt(cu(1)));
}

test "an empty view rejects every index" {
    const empty: View = .{ .units = &.{} };
    try testing.expectEqual(@as(usize, 0), empty.codeUnitLen());
    try testing.expectEqual(@as(?u16, null), empty.codeUnitAt(cu(0)));
    try testing.expectEqual(@as(?u16, null), empty.codeUnitAt(cu(std.math.maxInt(usize))));
}

test "FP-0013 case 8: View.codePoints pairs surrogates and keeps lone surrogates" {
    const units = [_]u16{ 0x0041, 0xD800, 0xD83D, 0xDE00, 0xDC00 };
    const view: View = .{ .units = &units };
    var code_points = view.codePoints();
    var seen: [8]u21 = undefined;
    var count: usize = 0;
    while (code_points.next()) |code_point| : (count += 1) seen[count] = code_point;
    try testing.expectEqualSlices(u21, &.{ 0x41, 0xD800, 0x1F600, 0xDC00 }, seen[0..count]);
}
