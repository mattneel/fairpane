//! The generic reference representation: a tagged union, 16 bytes on 64-bit targets.
//! Every comparison of FP-0011 measures a candidate against this representation.

const std = @import("std");
const value = @import("value.zig");
const Class = value.Class;

pub const Value = union(enum) {
    undefined,
    null,
    boolean: bool,
    number: f64,
    cell: u32,
};

pub const max_cell_index: u32 = std.math.maxInt(u32);

pub const undefined_value: Value = .undefined;
pub const null_value: Value = .null;

pub fn fromBoolean(b: bool) Value {
    return .{ .boolean = b };
}

pub fn fromCell(index: u32) Value {
    std.debug.assert(index <= max_cell_index);
    return .{ .cell = index };
}

/// Every number is inline.
pub fn fromInlineNumber(n: f64) ?Value {
    return .{ .number = n };
}

pub fn classify(v: Value) Class {
    return switch (v) {
        .undefined => .undefined,
        .null => .null,
        .boolean => .boolean,
        .number => .number,
        .cell => .cell,
    };
}

pub fn asBoolean(v: Value) bool {
    return v.boolean;
}

pub fn asNumber(v: Value) f64 {
    return v.number;
}

pub fn asCell(v: Value) u32 {
    return v.cell;
}

/// Compares encodings: numbers by their bits, so +0 and -0 differ and equal NaN bits match.
pub fn identical(a: Value, b: Value) bool {
    return switch (a) {
        .undefined => b == .undefined,
        .null => b == .null,
        .boolean => |x| b == .boolean and b.boolean == x,
        .number => |x| b == .number and @as(u64, @bitCast(b.number)) == @as(u64, @bitCast(x)),
        .cell => |x| b == .cell and b.cell == x,
    };
}
