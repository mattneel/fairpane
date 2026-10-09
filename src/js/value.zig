//! Value representations of the JavaScript runtime.
//!
//! `Runtime(r)` instantiates the whole runtime for one representation.
//! Each candidate file declares exactly the members that `checkInterface` lists.
//! No representation type has a C layout or an integer backing, so the compiler rejects it
//! in every C ABI signature and in every field of a C-layout struct.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

pub const Representation = enum { reference, nan_box, tagged_index };

/// The encoding class of a value. A `cell` value refers to a managed cell by its index.
pub const Class = enum { undefined, null, boolean, number, cell };

/// An index into the heap's cell table.
pub const CellRef = enum(u32) { _ };

/// Returns the candidate file of `r` after checking its interface.
pub fn Encoding(comptime r: Representation) type {
    const E = switch (r) {
        .reference => @import("value_reference.zig"),
        .nan_box => @import("value_nan_box.zig"),
        .tagged_index => @import("value_tagged_index.zig"),
    };
    comptime checkMembers(r, E);
    return E;
}

/// Stops compilation when the candidate of `r` lacks a member or declares one with another type.
pub fn checkInterface(comptime r: Representation) void {
    _ = Encoding(r);
}

const required_members = [_][]const u8{
    "Value",            "max_cell_index", "undefined_value", "null_value", "fromBoolean", "fromCell",
    "fromInlineNumber", "classify",       "asBoolean",       "asNumber",   "asCell",      "identical",
};

fn checkMembers(comptime r: Representation, comptime E: type) void {
    @setEvalBranchQuota(20_000);
    const prefix = "fairpane-js: representation " ++ @tagName(r);
    const compact = r != .reference;
    for (required_members) |member| {
        if (!@hasDecl(E, member)) @compileError(prefix ++ " lacks " ++ member);
    }
    if (compact and !@hasDecl(E, "rawBits")) @compileError(prefix ++ " lacks rawBits");
    for (@typeInfo(E).@"struct".decl_names) |member| {
        const known = for (required_members) |required| {
            if (std.mem.eql(u8, required, member)) break true;
        } else compact and std.mem.eql(u8, member, "rawBits");
        if (!known) @compileError(prefix ++ " declares unexpected member " ++ member);
    }

    const Value = E.Value;
    if (@TypeOf(Value) != type) @compileError(prefix ++ " declares Value with type " ++ @typeName(@TypeOf(Value)));
    const auto_layout = switch (@typeInfo(Value)) {
        .@"struct" => |info| info.layout == .auto,
        .@"union" => |info| info.layout == .auto and info.tag_type != null,
        else => false,
    };
    if (!auto_layout) @compileError(prefix ++ " declares Value with type " ++ @typeName(Value) ++ ", which needs an automatic-layout struct or tagged union");

    expectMemberType(prefix, "max_cell_index", @TypeOf(E.max_cell_index), u32);
    expectMemberType(prefix, "undefined_value", @TypeOf(E.undefined_value), Value);
    expectMemberType(prefix, "null_value", @TypeOf(E.null_value), Value);
    expectMemberType(prefix, "fromBoolean", @TypeOf(E.fromBoolean), fn (bool) Value);
    expectMemberType(prefix, "fromCell", @TypeOf(E.fromCell), fn (u32) Value);
    expectMemberType(prefix, "fromInlineNumber", @TypeOf(E.fromInlineNumber), fn (f64) ?Value);
    expectMemberType(prefix, "classify", @TypeOf(E.classify), fn (Value) Class);
    expectMemberType(prefix, "asBoolean", @TypeOf(E.asBoolean), fn (Value) bool);
    expectMemberType(prefix, "asNumber", @TypeOf(E.asNumber), fn (Value) f64);
    expectMemberType(prefix, "asCell", @TypeOf(E.asCell), fn (Value) u32);
    expectMemberType(prefix, "identical", @TypeOf(E.identical), fn (Value, Value) bool);
    if (compact) expectMemberType(prefix, "rawBits", @TypeOf(E.rawBits), fn (Value) u64);
}

fn expectMemberType(comptime prefix: []const u8, comptime member: []const u8, comptime Actual: type, comptime Expected: type) void {
    if (Actual != Expected) @compileError(prefix ++ " declares " ++ member ++ " with type " ++ @typeName(Actual));
}
fn expectRoundTrips(comptime r: Representation) !void {
    const E = Encoding(r);
    const immediates = [_]E.Value{ E.undefined_value, E.null_value, E.fromBoolean(false), E.fromBoolean(true) };
    const classes = [_]Class{ .undefined, .null, .boolean, .boolean };
    for (immediates, classes) |v, class| try testing.expectEqual(class, E.classify(v));
    try testing.expect(!E.asBoolean(immediates[2]));
    try testing.expect(E.asBoolean(immediates[3]));
    for (immediates, 0..) |a, i| {
        for (immediates, 0..) |b, j| try testing.expectEqual(i == j, E.identical(a, b));
    }
    const indices = [_]u32{ 0, 1, E.max_cell_index };
    for (indices) |index| {
        const v = E.fromCell(index);
        try testing.expectEqual(Class.cell, E.classify(v));
        try testing.expectEqual(index, E.asCell(v));
        for (immediates) |immediate| try testing.expect(!E.identical(v, immediate));
    }
    try testing.expect(!E.identical(E.fromCell(0), E.fromCell(1)));
}

test "FP-0011 case 17: every representation passes the interface check and keeps its frozen encodings" {
    inline for (.{ Representation.reference, Representation.nan_box, Representation.tagged_index }) |r| {
        comptime checkInterface(r);
        try expectRoundTrips(r);
    }
    try testing.expectEqual(16, @sizeOf(Encoding(.reference).Value));
    try testing.expectEqual(8, @sizeOf(Encoding(.nan_box).Value));
    try testing.expectEqual(4, @sizeOf(Encoding(.tagged_index).Value));

    const N = Encoding(.nan_box);
    try testing.expectEqual(0xFFFA000000000000, N.rawBits(N.undefined_value));
    try testing.expectEqual(0xFFFA000000000001, N.rawBits(N.null_value));
    try testing.expectEqual(0xFFFA000000000002, N.rawBits(N.fromBoolean(false)));
    try testing.expectEqual(0xFFFA000000000003, N.rawBits(N.fromBoolean(true)));
    try testing.expectEqual(0xFFF9000000000000, N.rawBits(N.fromCell(0)));
    try testing.expectEqual(0xFFF9000000000001, N.rawBits(N.fromCell(1)));
    try testing.expectEqual(0xFFF90000FFFFFFFF, N.rawBits(N.fromCell(N.max_cell_index)));

    const T = Encoding(.tagged_index);
    try testing.expectEqual(0x00000002, T.rawBits(T.undefined_value));
    try testing.expectEqual(0x00000006, T.rawBits(T.null_value));
    try testing.expectEqual(0x0000000A, T.rawBits(T.fromBoolean(false)));
    try testing.expectEqual(0x0000000E, T.rawBits(T.fromBoolean(true)));
    try testing.expectEqual(0x00000000, T.rawBits(T.fromCell(0)));
    try testing.expectEqual(0x00000004, T.rawBits(T.fromCell(1)));
    try testing.expectEqual(0xFFFFFFFC, T.rawBits(T.fromCell(T.max_cell_index)));
    const integers = [_]struct { f64, u64 }{
        .{ 0, 0x00000001 },
        .{ 1, 0x00000003 },
        .{ -1, 0xFFFFFFFF },
        .{ 1073741823, 0x7FFFFFFF },
        .{ -1073741824, 0x80000001 },
    };
    for (integers) |pair| {
        const v = T.fromInlineNumber(pair[0]) orelse return error.TestExpectedInline;
        try testing.expectEqual(Class.number, T.classify(v));
        try testing.expectEqual(pair[1], T.rawBits(v));
        try testing.expectEqual(pair[0], T.asNumber(v));
    }
}

test "FP-0011 case 20: no value representation or js import reaches the C ABI sources" {
    const sources = [_][]const u8{
        @embedFile("operations.zig"),
        @embedFile("value.zig"),
        @embedFile("value_reference.zig"),
        @embedFile("value_nan_box.zig"),
        @embedFile("value_tagged_index.zig"),
        @embedFile("heap_catalog.zig"),
        @embedFile("heap.zig"),
        @embedFile("kernels.zig"),
        @embedFile("number.zig"),
        @embedFile("number_vectors.zig"),
        @embedFile("runtime.zig"),
        @embedFile("measure.zig"),
        @embedFile("measure_main_reference.zig"),
        @embedFile("measure_main_nan_box.zig"),
        @embedFile("measure_main_tagged_index.zig"),
        @embedFile("lexer.zig"),
        @embedFile("ast.zig"),
        @embedFile("parser.zig"),
        @embedFile("test262_metadata.zig"),
        @embedFile("parse_census.zig"),
        @embedFile("parse_main.zig"),
    };
    // The needles are split so that this file does not contain them.
    const needles = [_][]const u8{ "ex" ++ "port ", "call" ++ "conv(", "ex" ++ "tern struct", "ex" ++ "tern union" };
    for (sources) |source| {
        for (needles) |needle| try testing.expectEqual(null, std.mem.indexOf(u8, source, needle));
    }
    const import_needle = "@imp" ++ "ort(\"js";
    try testing.expectEqual(null, std.mem.indexOf(u8, @embedFile("../c_api.zig"), import_needle));
    try testing.expectEqual(null, std.mem.indexOf(u8, @embedFile("../abi_generated.zig"), import_needle));
}
