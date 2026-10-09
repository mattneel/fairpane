//! Number operations of ECMA-262 over binary64 values.
//!
//! `add` and `sameValue` follow ECMA-262 exactly on `f64`; the runtime never enables a relaxed
//! floating-point mode.
//! `toString` takes its shortest digits from `std.fmt.float.binaryToDecimal`, the Ryū algorithm,
//! which picks the closest of the shortest digit strings and the even one on a tie: the Note 2
//! alternative of step 5 of `Number::toString`.
//! `stringToNumber` implements the `StringNumericLiteral` grammar over code units and never allocates.

const std = @import("std");
const testing = std.testing;
const vectors = @import("number_vectors.zig");

/// `Number::add`.
pub fn add(x: f64, y: f64) f64 {
    return x + y;
}

/// `Number::sameValue`: NaN equals NaN, and +0 differs from -0.
pub fn sameValue(x: f64, y: f64) bool {
    if (std.math.isNan(x) and std.math.isNan(y)) return true;
    if (x == 0 and y == 0) return std.math.signbit(x) == std.math.signbit(y);
    return x == y;
}

/// A positive decimal `significand × 10^exponent` without trailing zeros in `significand`.
pub const Decimal = struct { significand: u64, exponent: i32 };

/// Returns the shortest decimal that rounds to the finite, nonzero `x` in magnitude, choosing the
/// closest such decimal and the even one on a tie.
pub fn shortest(x: f64) Decimal {
    std.debug.assert(std.math.isFinite(x) and x != 0);
    const bits: u64 = @bitCast(@abs(x));
    const decimal = std.fmt.float.binaryToDecimal(u64, bits, 52, 11, false, &std.fmt.float.Backend64_TablesFull);
    var significand = decimal.mantissa;
    var exponent = decimal.exponent;
    while (significand % 10 == 0) {
        significand /= 10;
        exponent += 1;
    }
    return .{ .significand = significand, .exponent = exponent };
}

/// The longest result of `toString`, `-1.7976931348623157e+308` and its kin, is 24 code units.
pub const max_string_units = 25;

/// `Number::toString(x, 10)`. Steps 6 through 12 write into `buffer`.
pub fn toString(x: f64, buffer: *[max_string_units]u16) []const u16 {
    var length: usize = 0;
    const put = struct {
        fn unit(out: *[max_string_units]u16, at: *usize, byte: u8) void {
            out[at.*] = byte;
            at.* += 1;
        }
        fn text(out: *[max_string_units]u16, at: *usize, bytes: []const u8) void {
            for (bytes) |byte| unit(out, at, byte);
        }
    };
    if (std.math.isNan(x)) {
        put.text(buffer, &length, "NaN");
        return buffer[0..length];
    }
    if (x == 0) {
        put.text(buffer, &length, "0");
        return buffer[0..length];
    }
    if (x < 0) put.unit(buffer, &length, '-');
    if (std.math.isInf(x)) {
        put.text(buffer, &length, "Infinity");
        return buffer[0..length];
    }
    const decimal = shortest(x);
    var digit_buffer: [20]u8 = undefined;
    const digits = std.fmt.bufPrint(&digit_buffer, "{d}", .{decimal.significand}) catch unreachable;
    const k: i32 = @intCast(digits.len);
    const n: i32 = decimal.exponent + k;
    if (k <= n and n <= 21) {
        // Step 6: the digits followed by n - k zeros.
        put.text(buffer, &length, digits);
        for (0..@intCast(n - k)) |_| put.unit(buffer, &length, '0');
    } else if (0 < n and n <= 21) {
        // Step 7: the first n digits, a point, and the remaining k - n digits.
        put.text(buffer, &length, digits[0..@intCast(n)]);
        put.unit(buffer, &length, '.');
        put.text(buffer, &length, digits[@intCast(n)..]);
    } else if (-6 < n and n <= 0) {
        // Step 8: "0.", -n zeros, and the digits.
        put.text(buffer, &length, "0.");
        for (0..@intCast(-n)) |_| put.unit(buffer, &length, '0');
        put.text(buffer, &length, digits);
    } else {
        // Steps 9 through 12: exponential notation.
        const e = n - 1;
        put.unit(buffer, &length, digits[0]);
        if (k != 1) {
            put.unit(buffer, &length, '.');
            put.text(buffer, &length, digits[1..]);
        }
        put.unit(buffer, &length, 'e');
        put.unit(buffer, &length, if (e < 0) '-' else '+');
        var exponent_buffer: [4]u8 = undefined;
        put.text(buffer, &length, std.fmt.bufPrint(&exponent_buffer, "{d}", .{@abs(e)}) catch unreachable);
    }
    return buffer[0..length];
}

/// `StrWhiteSpaceChar`: WhiteSpace and LineTerminator.
/// The `Zs` members come from Unicode 18.0.0 `ucd/extracted/DerivedGeneralCategory.txt`,
/// SHA-256 `d6b151d2d40ee9b1876d26f417980f45ffae47b6055ccf7203cb31f07a030f94`, lines 3553 through 3561:
/// U+0020, U+00A0, U+1680, U+2000 through U+200A, U+202F, U+205F, and U+3000.
fn isStrWhiteSpace(unit: u16) bool {
    return switch (unit) {
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680 => true,
        0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF => true,
        else => false,
    };
}

fn isDecimalDigit(unit: u16) bool {
    return unit >= '0' and unit <= '9';
}

fn matchesAscii(units: []const u16, text: []const u8) bool {
    if (units.len != text.len) return false;
    for (units, text) |unit, byte| {
        if (unit != byte) return false;
    }
    return true;
}

/// `StringToNumber`. Input that the grammar does not match yields NaN.
pub fn stringToNumber(units: []const u16) f64 {
    var start: usize = 0;
    var end = units.len;
    while (start < end and isStrWhiteSpace(units[start])) start += 1;
    while (end > start and isStrWhiteSpace(units[end - 1])) end -= 1;
    const text = units[start..end];
    if (text.len == 0) return 0;
    if (text.len > 2 and text[0] == '0') {
        switch (text[1]) {
            'x', 'X' => return nonDecimal(text[2..], 4),
            'o', 'O' => return nonDecimal(text[2..], 3),
            'b', 'B' => return nonDecimal(text[2..], 1),
            else => {},
        }
    }
    return decimalLiteral(text);
}

/// A `NonDecimalIntegerLiteral` without separators, rounded to nearest, ties to even, from its
/// leading 64 significant bits and a sticky bit.
fn nonDecimal(digits: []const u16, comptime bits_per_digit: u3) f64 {
    if (digits.len == 0) return std.math.nan(f64);
    var leading: u64 = 0;
    var significant: u32 = 0;
    var dropped: usize = 0;
    var sticky = false;
    for (digits) |unit| {
        const digit: u8 = switch (unit) {
            '0'...'9' => @intCast(unit - '0'),
            'a'...'f' => @intCast(unit - 'a' + 10),
            'A'...'F' => @intCast(unit - 'A' + 10),
            else => return std.math.nan(f64),
        };
        if (digit >= @as(u8, 1) << bits_per_digit) return std.math.nan(f64);
        var bit: u3 = bits_per_digit;
        while (bit > 0) {
            bit -= 1;
            const one = (digit >> bit) & 1;
            if (significant == 0 and one == 0) continue;
            if (significant < 64) {
                leading = (leading << 1) | one;
                significant += 1;
            } else {
                dropped += 1;
                if (one == 1) sticky = true;
            }
        }
    }
    if (significant == 0) return 0;
    // Any value with more than 1100 binary digits overflows.
    if (dropped > 1100) return std.math.inf(f64);
    if (significant <= 53) return std.math.ldexp(@as(f64, @floatFromInt(leading)), @intCast(dropped));
    const shift: u6 = @intCast(significant - 53);
    var mantissa = leading >> shift;
    const remainder = leading & ((@as(u64, 1) << shift) - 1);
    const half = @as(u64, 1) << (shift - 1);
    if (remainder > half or (remainder == half and (sticky or mantissa & 1 == 1))) mantissa += 1;
    return std.math.ldexp(@as(f64, @floatFromInt(mantissa)), @as(i32, shift) + @as(i32, @intCast(dropped)));
}

/// The significant digits that reach `parseFloat`. With a final sticky digit, they decide the
/// correctly rounded value of any decimal literal.
const max_significant_digits = 768;

/// A `StrDecimalLiteral`. Only grammar-checked digits reach `std.fmt.parseFloat`.
fn decimalLiteral(text: []const u16) f64 {
    var index: usize = 0;
    var negative = false;
    if (text[0] == '+' or text[0] == '-') {
        negative = text[0] == '-';
        index = 1;
    }
    if (matchesAscii(text[index..], "Infinity")) {
        return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    }
    // The literal's value is 0.D × 10^scale, where D holds its significant digits.
    var digits: [max_significant_digits + 1]u8 = undefined;
    var count: usize = 0;
    var sticky = false;
    var scale: i64 = 0;
    var saw_digit = false;
    var after_point = false;
    while (index < text.len) : (index += 1) {
        const unit = text[index];
        if (unit == '.' and !after_point) {
            after_point = true;
            continue;
        }
        if (!isDecimalDigit(unit)) break;
        saw_digit = true;
        const digit: u8 = @intCast(unit);
        if (count == 0 and !sticky and digit == '0') {
            // A leading zero after the point lowers the scale; one before it changes nothing.
            if (after_point) scale -= 1;
            continue;
        }
        if (count < max_significant_digits) {
            digits[count] = digit;
            count += 1;
        } else if (digit != '0') {
            sticky = true;
        }
        if (!after_point) scale += 1;
    }
    if (!saw_digit) return std.math.nan(f64);
    var exponent: i64 = 0;
    if (index < text.len and (text[index] == 'e' or text[index] == 'E')) {
        index += 1;
        var exponent_negative = false;
        if (index < text.len and (text[index] == '+' or text[index] == '-')) {
            exponent_negative = text[index] == '-';
            index += 1;
        }
        const exponent_start = index;
        while (index < text.len and isDecimalDigit(text[index])) : (index += 1) {
            // Saturate: any exponent beyond this bound already gives zero or infinity.
            exponent = @min(exponent * 10 + (text[index] - '0'), 1_000_000);
        }
        if (index == exponent_start) return std.math.nan(f64);
        if (exponent_negative) exponent = -exponent;
    }
    if (index != text.len) return std.math.nan(f64);
    if (count == 0) return if (negative) -0.0 else 0.0;
    if (sticky) {
        digits[count] = '1';
        count += 1;
    }
    const clamped = std.math.clamp(scale + exponent, -2000, 2000);
    var literal: [max_significant_digits + 16]u8 = undefined;
    const rendered = std.fmt.bufPrint(&literal, "0.{s}e{d}", .{ digits[0..count], clamped }) catch unreachable;
    const magnitude = std.fmt.parseFloat(f64, rendered) catch unreachable;
    return if (negative) -magnitude else magnitude;
}

const test_representations = .{ .reference, .nan_box, .tagged_index };

fn expectNumberBits(expected: ?u64, actual: f64) !void {
    if (expected) |bits| {
        try testing.expectEqual(bits, @as(u64, @bitCast(actual)));
    } else {
        try testing.expect(std.math.isNan(actual));
    }
}

fn expectAsciiUnits(expected: []const u8, actual: []const u16) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |byte, unit| try testing.expectEqual(@as(u16, byte), unit);
}

test "FP-0011 case 21: Number::add and Number::sameValue follow the frozen vectors" {
    for (vectors.add_vectors) |v| {
        try expectNumberBits(v.result, add(@bitCast(v.x), @bitCast(v.y)));
    }
    for (vectors.same_value_vectors) |v| {
        try testing.expectEqual(v.result, sameValue(@bitCast(v.x), @bitCast(v.y)));
    }
    const runtime = @import("runtime.zig");
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var heap = try Rt.Heap.init(testing.allocator, .{});
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        for (vectors.add_vectors) |v| {
            const sum = ctx.invoke(.number_add, .{ @as(f64, @bitCast(v.x)), @as(f64, @bitCast(v.y)) });
            try heap.expectInvariants();
            try expectNumberBits(v.result, sum);
        }
        for (vectors.same_value_vectors) |v| {
            const same = ctx.invoke(.number_same_value, .{ @as(f64, @bitCast(v.x)), @as(f64, @bitCast(v.y)) });
            try heap.expectInvariants();
            try testing.expectEqual(v.result, same);
        }
        try testing.expectEqual(0, try vectors.selfCheck(Rt, &heap));
        try heap.expectInvariants();
    }
}

test "FP-0011 case 22: Number::toString gives the frozen texts and shortest round trips" {
    var buffer: [max_string_units]u16 = undefined;
    for (vectors.to_string_vectors) |v| {
        try expectAsciiUnits(v.text, toString(@bitCast(v.bits), &buffer));
    }
    const runtime = @import("runtime.zig");
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var heap = try Rt.Heap.init(testing.allocator, .{});
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        for (vectors.to_string_vectors) |v| {
            const before = heap.stats.cells_allocated;
            const string = try ctx.invoke(.number_to_string, .{@as(f64, @bitCast(v.bits))});
            try heap.expectInvariants();
            try testing.expectEqual(before + 1, heap.stats.cells_allocated);
            try expectAsciiUnits(v.text, ctx.stringUnits(string));
            heap.collect();
            try heap.expectInvariants();
        }
    }

    var prng = std.Random.DefaultPrng.init(0x4650303131000001);
    const random = prng.random();
    var checked: usize = 0;
    var text: [64]u8 = undefined;
    var units: [64]u16 = undefined;
    while (checked < 100_000) {
        const bits = random.int(u64);
        const x: f64 = @bitCast(bits);
        if (std.math.isNan(x) or std.math.isInf(x) or x == 0) continue;
        checked += 1;
        const rendered = toString(x, &buffer);
        try testing.expectEqual(bits, @as(u64, @bitCast(stringToNumber(rendered))));

        const decimal = shortest(@abs(x));
        const digits = std.fmt.printInt(&text, decimal.significand, 10, .lower, .{});
        if (digits <= 1) continue;
        const neighbors = [_]u64{ decimal.significand / 10, (decimal.significand + 9) / 10 };
        for (neighbors) |neighbor| {
            const sign: []const u8 = if (x < 0) "-" else "";
            const candidate = try std.fmt.bufPrint(&text, "{s}{d}e{d}", .{ sign, neighbor, decimal.exponent + 1 });
            for (candidate, 0..) |byte, i| units[i] = byte;
            try testing.expect(@as(u64, @bitCast(stringToNumber(units[0..candidate.len]))) != bits);
        }
    }
}

test "FP-0011 case 23: StringToNumber follows the frozen vectors without allocating" {
    for (vectors.string_to_number_vectors) |v| {
        try expectNumberBits(v.result, stringToNumber(v.input));
    }
    const runtime = @import("runtime.zig");
    const View = @import("../web_string.zig").View;
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var heap = try Rt.Heap.init(testing.allocator, .{});
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        const before = heap.stats.cells_allocated;
        for (vectors.string_to_number_vectors) |v| {
            const result = ctx.invoke(.string_to_number, .{View{ .units = v.input }});
            try heap.expectInvariants();
            try expectNumberBits(v.result, result);
        }
        try testing.expectEqual(before, heap.stats.cells_allocated);
    }
}
