//! The tagged-index candidate: 32 bits per value.
//!
//! An integral number from -2^30 through 2^30 - 1, except -0, stores `(n << 1) | 1` in two's complement.
//! A cell stores `index << 2`, so `max_cell_index` is 2^30 - 1.
//! Undefined, null, false, and true store `0x2`, `0x6`, `0xA`, and `0xE`.
//! Every other number, including -0, NaN, infinities, and fractions, lives in a `heap_number` cell.

const std = @import("std");
const builtin = @import("builtin");
const value = @import("value.zig");
const Class = value.Class;

pub const Value = struct { bits: u32 };

pub const max_cell_index: u32 = (1 << 30) - 1;

const min_inline: f64 = -1073741824;
const max_inline: f64 = 1073741823;

pub const undefined_value: Value = .{ .bits = 0x2 };
pub const null_value: Value = .{ .bits = 0x6 };

pub fn fromBoolean(b: bool) Value {
    return .{ .bits = if (b) 0xE else 0xA };
}

pub fn fromCell(index: u32) Value {
    std.debug.assert(index <= max_cell_index);
    return .{ .bits = index << 2 };
}

/// Returns null for a number that needs a `heap_number` cell.
pub fn fromInlineNumber(n: f64) ?Value {
    // NaN fails both comparisons.
    if (!(n >= min_inline and n <= max_inline)) return null;
    if (@trunc(n) != n) return null;
    if (n == 0 and std.math.signbit(n)) return null;
    const integer: i32 = @intFromFloat(n);
    const shifted: u32 = @bitCast(integer << 1);
    return .{ .bits = shifted | 1 };
}

pub fn classify(v: Value) Class {
    if (v.bits & 1 != 0) return .number;
    if (v.bits & 3 == 0) return .cell;
    return switch (v.bits >> 2) {
        0 => .undefined,
        1 => .null,
        else => .boolean,
    };
}

pub fn asBoolean(v: Value) bool {
    return v.bits == 0xE;
}

pub fn asNumber(v: Value) f64 {
    const signed: i32 = @bitCast(v.bits);
    return @floatFromInt(signed >> 1);
}

pub fn asCell(v: Value) u32 {
    return v.bits >> 2;
}

pub fn identical(a: Value, b: Value) bool {
    return a.bits == b.bits;
}

/// Returns the encoding. Only tests may call it.
pub fn rawBits(v: Value) u64 {
    if (!builtin.is_test) @compileError("fairpane-js: rawBits is test-only");
    return v.bits;
}
