//! FP-0013 cases 5, 6, and 7: aliases, `@missing` defaults, and the code point range.

const std = @import("std");
const testing = std.testing;
const unicode = @import("properties.zig");

const property_value_aliases = @embedFile("ucd/PropertyValueAliases.txt");

/// Checks every alias line of property `name` against `T.fromAlias`.
/// Returns the number of lines that named a value of `T`.
fn checkAliases(comptime T: type, name: []const u8) !usize {
    var matched: usize = 0;
    var lines = std.mem.splitScalar(u8, property_value_aliases, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len], " \t\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        const property = std.mem.trim(u8, fields.first(), " \t");
        if (!std.mem.eql(u8, property, name)) continue;
        const rest = fields.rest();
        var aliases = std.mem.splitScalar(u8, rest, ';');
        const short = std.mem.trim(u8, aliases.first(), " \t");
        const expected = std.meta.stringToEnum(T, short);
        if (expected != null) matched += 1;
        aliases = std.mem.splitScalar(u8, rest, ';');
        while (aliases.next()) |field| {
            const alias = std.mem.trim(u8, field, " \t");
            if (alias.len == 0) continue;
            const actual = T.fromAlias(alias);
            if (actual != expected) {
                std.debug.print("{s} alias {s}: expected {any}, found {any}\n", .{ name, alias, expected, actual });
                return error.TestUnexpectedResult;
            }
        }
    }
    return matched;
}

test "FP-0013 case 5: every alias of the six enumerated properties resolves through fromAlias" {
    try testing.expectEqual(@as(usize, 30), std.meta.fieldNames(unicode.GeneralCategory).len);
    try testing.expectEqual(std.meta.fieldNames(unicode.GeneralCategory).len, try checkAliases(unicode.GeneralCategory, "gc"));
    try testing.expectEqual(std.meta.fieldNames(unicode.Script).len, try checkAliases(unicode.Script, "sc"));
    try testing.expectEqual(std.meta.fieldNames(unicode.BidiClass).len, try checkAliases(unicode.BidiClass, "bc"));
    try testing.expectEqual(std.meta.fieldNames(unicode.JoiningType).len, try checkAliases(unicode.JoiningType, "jt"));
    try testing.expectEqual(std.meta.fieldNames(unicode.IndicSyllabicCategory).len, try checkAliases(unicode.IndicSyllabicCategory, "InSC"));
    try testing.expectEqual(std.meta.fieldNames(unicode.IndicPositionalCategory).len, try checkAliases(unicode.IndicPositionalCategory, "InPC"));

    try testing.expectEqual(@as(?unicode.Script, .Zinh), unicode.Script.fromAlias("Qaai"));
    try testing.expectEqual(@as(?unicode.Script, .Copt), unicode.Script.fromAlias("Qaac"));
    try testing.expectEqual(@as(?unicode.GeneralCategory, null), unicode.GeneralCategory.fromAlias("L"));
    try testing.expectEqual(@as(?unicode.GeneralCategory, null), unicode.GeneralCategory.fromAlias("Letter"));
    try testing.expectEqual(@as(?unicode.GeneralCategory, null), unicode.GeneralCategory.fromAlias("Nope"));
    try testing.expectEqual(@as(?unicode.Script, null), unicode.Script.fromAlias("Nope"));
}

test "FP-0013 case 6: unlisted code points take the @missing defaults" {
    const Case = struct { code_point: u21, gc: unicode.GeneralCategory, bc: unicode.BidiClass };
    const cases = [_]Case{
        .{ .code_point = 0x0378, .gc = .Cn, .bc = .L },
        .{ .code_point = 0x05EB, .gc = .Cn, .bc = .R },
        .{ .code_point = 0x070E, .gc = .Cn, .bc = .AL },
        .{ .code_point = 0x20C5, .gc = .Cn, .bc = .ET },
        .{ .code_point = 0xD800, .gc = .Cs, .bc = .L },
        .{ .code_point = 0xE000, .gc = .Co, .bc = .L },
        .{ .code_point = 0xFDD0, .gc = .Cn, .bc = .BN },
    };
    for (cases) |case| {
        const p = try unicode.lookup(case.code_point);
        testing.expectEqual(case.gc, p.gc) catch |e| return report(case.code_point, e);
        testing.expectEqual(unicode.Script.Zzzz, p.sc) catch |e| return report(case.code_point, e);
        testing.expectEqualSlices(unicode.Script, &.{.Zzzz}, p.scx) catch |e| return report(case.code_point, e);
        testing.expectEqual(case.bc, p.bc) catch |e| return report(case.code_point, e);
        testing.expectEqual(unicode.JoiningType.U, p.jt) catch |e| return report(case.code_point, e);
        testing.expectEqual(unicode.IndicSyllabicCategory.Other, p.insc) catch |e| return report(case.code_point, e);
        testing.expectEqual(unicode.IndicPositionalCategory.NA, p.inpc) catch |e| return report(case.code_point, e);
    }
}

fn report(code_point: u21, e: anyerror) anyerror {
    std.debug.print("at U+{X:0>4}\n", .{code_point});
    return e;
}

test "FP-0013 case 7: lookup rejects values above U+10FFFF and states version 18.0.0" {
    try testing.expectError(error.NotCodePoint, unicode.lookup(0x110000));
    try testing.expectError(error.NotCodePoint, unicode.lookup(std.math.maxInt(u21)));
    _ = try unicode.lookup(0x10FFFF);
    try testing.expectEqualStrings("18.0.0", unicode.version);
}
