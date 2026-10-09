//! The NaN-boxing candidate: 64 bits per value.
//!
//! A number stores its IEEE 754 binary64 bits, except that every NaN stores `0x7FF8000000000000`.
//! Because every NaN is canonical, no number encoding reaches `0xFFF8000000000000` or above.
//! A cell stores `0xFFF9000000000000 | index`.
//! Undefined, null, false, and true store `0xFFFA000000000000` through `0xFFFA000000000003`.

const std = @import("std");
const builtin = @import("builtin");
const value = @import("value.zig");
const Class = value.Class;

pub const Value = struct { bits: u64 };

const canonical_nan: u64 = 0x7FF8000000000000;
const cell_tag: u64 = 0xFFF9000000000000;
const immediate_tag: u64 = 0xFFFA000000000000;
const tag_mask: u64 = 0xFFFF000000000000;

pub const max_cell_index: u32 = std.math.maxInt(u32);

pub const undefined_value: Value = .{ .bits = immediate_tag | 0 };
pub const null_value: Value = .{ .bits = immediate_tag | 1 };

pub fn fromBoolean(b: bool) Value {
    return .{ .bits = immediate_tag | 2 | @as(u64, @intFromBool(b)) };
}

pub fn fromCell(index: u32) Value {
    return .{ .bits = cell_tag | index };
}

/// Every number is inline; every NaN becomes the canonical NaN.
pub fn fromInlineNumber(n: f64) ?Value {
    if (std.math.isNan(n)) return .{ .bits = canonical_nan };
    return .{ .bits = @bitCast(n) };
}

pub fn classify(v: Value) Class {
    return switch (v.bits & tag_mask) {
        cell_tag => .cell,
        immediate_tag => switch (v.bits & 3) {
            0 => .undefined,
            1 => .null,
            else => .boolean,
        },
        else => .number,
    };
}

pub fn asBoolean(v: Value) bool {
    return v.bits & 1 != 0;
}

pub fn asNumber(v: Value) f64 {
    return @bitCast(v.bits);
}

pub fn asCell(v: Value) u32 {
    return @truncate(v.bits);
}

pub fn identical(a: Value, b: Value) bool {
    return a.bits == b.bits;
}

/// Returns the encoding. Only tests may call it.
pub fn rawBits(v: Value) u64 {
    if (!builtin.is_test) @compileError("fairpane-js: rawBits is test-only");
    return v.bits;
}
