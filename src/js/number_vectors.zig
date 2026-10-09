//! The frozen number vectors of FP-0011 cases 21 through 23.
//!
//! Node v26.7.0 cross-checked every vector on 2026-10-08, as the task contract records.
//! A null result means any NaN.

const std = @import("std");
const View = @import("../web_string.zig").View;

pub const AddVector = struct { x: u64, y: u64, result: ?u64 };
pub const SameValueVector = struct { x: u64, y: u64, result: bool };
pub const ToStringVector = struct { bits: u64, text: []const u8 };
pub const StringToNumberVector = struct { input: []const u16, result: ?u64 };

pub const add_vectors = [_]AddVector{
    .{ .x = 0x8000000000000000, .y = 0x8000000000000000, .result = 0x8000000000000000 },
    .{ .x = 0x0000000000000000, .y = 0x8000000000000000, .result = 0x0000000000000000 },
    .{ .x = 0x8000000000000000, .y = 0x0000000000000000, .result = 0x0000000000000000 },
    .{ .x = 0x3FF0000000000000, .y = 0xBFF0000000000000, .result = 0x0000000000000000 },
    .{ .x = 0x7FF0000000000000, .y = 0xFFF0000000000000, .result = null },
    .{ .x = 0x7FF0000000000000, .y = 0x3FF0000000000000, .result = 0x7FF0000000000000 },
    .{ .x = 0x7FEFFFFFFFFFFFFF, .y = 0x7FEFFFFFFFFFFFFF, .result = 0x7FF0000000000000 },
    .{ .x = 0x3FB999999999999A, .y = 0x3FC999999999999A, .result = 0x3FD3333333333334 },
    .{ .x = 0x0000000000000001, .y = 0x0000000000000001, .result = 0x0000000000000002 },
    .{ .x = 0x000FFFFFFFFFFFFF, .y = 0x0000000000000001, .result = 0x0010000000000000 },
    .{ .x = 0x4340000000000000, .y = 0x3FF0000000000000, .result = 0x4340000000000000 },
    .{ .x = 0x4340000000000000, .y = 0x4000000000000000, .result = 0x4340000000000001 },
    .{ .x = 0x4340000000000001, .y = 0x3FF0000000000000, .result = 0x4340000000000002 },
    .{ .x = 0x7FF0000000000001, .y = 0x3FF0000000000000, .result = null },
};

pub const same_value_vectors = [_]SameValueVector{
    .{ .x = 0x7FF8000000000000, .y = 0xFFF0000000000001, .result = true },
    .{ .x = 0x8000000000000000, .y = 0x8000000000000000, .result = true },
    .{ .x = 0x3FF0000000000000, .y = 0x3FF0000000000000, .result = true },
    .{ .x = 0x0000000000000000, .y = 0x8000000000000000, .result = false },
    .{ .x = 0x8000000000000000, .y = 0x0000000000000000, .result = false },
    .{ .x = 0x7FF0000000000000, .y = 0xFFF0000000000000, .result = false },
    .{ .x = 0x0000000000000001, .y = 0x8000000000000001, .result = false },
};

pub const to_string_vectors = [_]ToStringVector{
    .{ .bits = 0x0000000000000000, .text = "0" },
    .{ .bits = 0x8000000000000000, .text = "0" },
    .{ .bits = 0x7FF8000000000000, .text = "NaN" },
    .{ .bits = 0xFFF0000000000001, .text = "NaN" },
    .{ .bits = 0x7FF0000000000000, .text = "Infinity" },
    .{ .bits = 0xFFF0000000000000, .text = "-Infinity" },
    .{ .bits = 0x3FF0000000000000, .text = "1" },
    .{ .bits = 0xBFF0000000000000, .text = "-1" },
    .{ .bits = 0x3FB999999999999A, .text = "0.1" },
    .{ .bits = 0x3FD3333333333334, .text = "0.30000000000000004" },
    .{ .bits = 0x405EDD2F1A9FBE77, .text = "123.456" },
    .{ .bits = 0x4011666666666666, .text = "4.35" },
    .{ .bits = 0x3FD5555555555555, .text = "0.3333333333333333" },
    .{ .bits = 0x4415AF1D78B58C40, .text = "100000000000000000000" },
    .{ .bits = 0x444B1AE4D6E2EF4F, .text = "999999999999999900000" },
    .{ .bits = 0x441AC53A7E04BCDA, .text = "123456789012345680000" },
    .{ .bits = 0x444B1AE4D6E2EF50, .text = "1e+21" },
    .{ .bits = 0x54B249AD2594C37D, .text = "1e+100" },
    .{ .bits = 0x3EB0C6F7A0B5ED8D, .text = "0.000001" },
    .{ .bits = 0x3EB4B3FD5942CD96, .text = "0.000001234" },
    .{ .bits = 0x3EE92A737110E454, .text = "0.000012" },
    .{ .bits = 0x3E7AD7F29ABCAF48, .text = "1e-7" },
    .{ .bits = 0xBE7AD7F29ABCAF48, .text = "-1e-7" },
    .{ .bits = 0x3E8421F5F40D8376, .text = "1.5e-7" },
    .{ .bits = 0x3EA0C6F7A0B5ED8D, .text = "5e-7" },
    .{ .bits = 0x3C36B082C2148B8E, .text = "1.23e-18" },
    .{ .bits = 0x0000000000000001, .text = "5e-324" },
    .{ .bits = 0x8000000000000001, .text = "-5e-324" },
    .{ .bits = 0x0000000000000002, .text = "1e-323" },
    .{ .bits = 0x000FFFFFFFFFFFFF, .text = "2.225073858507201e-308" },
    .{ .bits = 0x0010000000000000, .text = "2.2250738585072014e-308" },
    .{ .bits = 0x7FEFFFFFFFFFFFFF, .text = "1.7976931348623157e+308" },
    .{ .bits = 0xFFEFFFFFFFFFFFFF, .text = "-1.7976931348623157e+308" },
    .{ .bits = 0x7FE0000000000000, .text = "8.98846567431158e+307" },
    .{ .bits = 0x433FFFFFFFFFFFFF, .text = "9007199254740991" },
    .{ .bits = 0x4340000000000000, .text = "9007199254740992" },
    .{ .bits = 0x4340000000000001, .text = "9007199254740994" },
    .{ .bits = 0xC340000000000000, .text = "-9007199254740992" },
    .{ .bits = 0x41DFFFFFFFC00000, .text = "2147483647" },
    .{ .bits = 0xC1E0000000000000, .text = "-2147483648" },
    .{ .bits = 0x4202A05F20000000, .text = "10000000000" },
};

/// Widens ASCII text to code units at compile time.
fn ascii(comptime text: []const u8) []const u16 {
    comptime {
        @setEvalBranchQuota(20_000);
        var units: [text.len]u16 = undefined;
        for (text, 0..) |byte, i| {
            std.debug.assert(byte < 0x80);
            units[i] = byte;
        }
        const frozen = units;
        return &frozen;
    }
}

/// `H` of case 23: the decimal expansion of the midpoint between 1 and the next Number.
const h = "1.00000000000000011102230246251565404236316680908203125";

/// Returns `count` copies of `byte` at compile time.
fn repeat(comptime byte: u8, comptime count: usize) []const u8 {
    comptime {
        const bytes: [count]u8 = @splat(byte);
        return &bytes;
    }
}

fn nan(comptime text: []const u8) StringToNumberVector {
    return .{ .input = ascii(text), .result = null };
}

fn exact(comptime text: []const u8, bits: u64) StringToNumberVector {
    return .{ .input = ascii(text), .result = bits };
}

pub const string_to_number_vectors = [_]StringToNumberVector{
    exact("", 0x0000000000000000),
    exact(" ", 0x0000000000000000),
    .{
        .input = &[_]u16{
            0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680,
            0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
            '4',    '2',    0x3000,
        },
        .result = 0x4045000000000000,
    },
    exact("+0", 0x0000000000000000),
    exact("-0", 0x8000000000000000),
    nan("-"),
    nan("+"),
    nan("."),
    nan("1e"),
    nan("1e+"),
    nan("1_000"),
    nan("12abc"),
    nan("0x"),
    nan("-0x1F"),
    nan("0b"),
    nan("0x1p3"),
    nan("infinity"),
    nan("INFINITY"),
    nan("NaN"),
    exact("0.", 0x0000000000000000),
    exact(".5", 0x3FE0000000000000),
    exact("5.", 0x4014000000000000),
    exact("00012", 0x4028000000000000),
    exact("0x1F", 0x403F000000000000),
    exact("0X1f", 0x403F000000000000),
    exact("0o17", 0x402E000000000000),
    exact("0b101", 0x4014000000000000),
    exact("Infinity", 0x7FF0000000000000),
    exact("+Infinity", 0x7FF0000000000000),
    exact("-Infinity", 0xFFF0000000000000),
    exact("0.1", 0x3FB999999999999A),
    exact("9007199254740993", 0x4340000000000000),
    exact("9007199254740995", 0x4340000000000002),
    exact("18014398509481985", 0x4350000000000000),
    exact("0x1fffffffffffff", 0x433FFFFFFFFFFFFF),
    exact("0x20000000000001", 0x4340000000000000),
    exact("0x20000000000003", 0x4340000000000002),
    exact("0x10000000000000000000", 0x44B0000000000000),
    exact("0b" ++ repeat('1', 54), 0x4350000000000000),
    exact("1e1000", 0x7FF0000000000000),
    exact("-1e1000", 0xFFF0000000000000),
    exact("1e-400", 0x0000000000000000),
    exact("-1e-400", 0x8000000000000000),
    exact("4.9406564584124654e-324", 0x0000000000000001),
    exact("2.4703282292062328e-324", 0x0000000000000001),
    exact("2.4703282292062327e-324", 0x0000000000000000),
    exact("1.7976931348623158e308", 0x7FEFFFFFFFFFFFFF),
    exact("1.7976931348623159e308", 0x7FF0000000000000),
    exact("123456789012345678901234567890", 0x45F8EE90FF6C373E),
    exact(h, 0x3FF0000000000000),
    exact(h ++ "1", 0x3FF0000000000001),
    exact(h ++ repeat('0', 950) ++ "1", 0x3FF0000000000001),
    exact(h ++ repeat('0', 951), 0x3FF0000000000000),
    exact("1" ++ repeat('0', 999), 0x7FF0000000000000),
    exact("0." ++ repeat('0', 400) ++ "1", 0x0000000000000000),
    .{ .input = &[_]u16{ 0x180E, '1' }, .result = null },
    .{ .input = &[_]u16{ '1', 0x0085 }, .result = null },
    .{ .input = &[_]u16{0xD800}, .result = null },
    .{ .input = &[_]u16{ '1', 0xDC00 }, .result = null },
    .{ .input = &[_]u16{ '1', 0x0000 }, .result = null },
};

fn matches(expected: ?u64, actual: f64) bool {
    const bits = expected orelse return std.math.isNan(actual);
    return bits == @as(u64, @bitCast(actual));
}

fn sameText(expected: []const u8, actual: []const u16) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |byte, unit| {
        if (unit != byte) return false;
    }
    return true;
}

/// Runs every vector through the kernels of `Rt` and returns the number of differences.
/// A measurement executable runs it in its own optimize mode before it measures.
pub fn selfCheck(comptime Rt: type, heap: *Rt.Heap) error{OutOfMemory}!usize {
    var ctx = Rt.rootContext(heap);
    var differences: usize = 0;
    for (add_vectors) |v| {
        const sum = ctx.invoke(.number_add, .{ @as(f64, @bitCast(v.x)), @as(f64, @bitCast(v.y)) });
        if (!matches(v.result, sum)) differences += 1;
    }
    for (same_value_vectors) |v| {
        const same = ctx.invoke(.number_same_value, .{ @as(f64, @bitCast(v.x)), @as(f64, @bitCast(v.y)) });
        if (same != v.result) differences += 1;
    }
    for (to_string_vectors) |v| {
        const string = try ctx.invoke(.number_to_string, .{@as(f64, @bitCast(v.bits))});
        if (!sameText(v.text, ctx.stringUnits(string))) differences += 1;
    }
    for (string_to_number_vectors) |v| {
        const result = ctx.invoke(.string_to_number, .{View{ .units = v.input }});
        if (!matches(v.result, result)) differences += 1;
    }
    ctx.collect();
    return differences;
}
