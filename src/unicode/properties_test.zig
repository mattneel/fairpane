//! FP-0013 cases 5, 6, and 7: aliases, `@missing` defaults, and the code point range.
//! FP-0108 cases 8, 9, and 10: hard-coded grapheme property rows, whole-range counts, and the two new enumerations.

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

test "FP-0108 case 8: lookup gives the cited Grapheme_Cluster_Break, Indic_Conjunct_Break, and Extended_Pictographic values" {
    // Each row cites its evidence: GBP is GraphemeBreakProperty.txt, DCP is DerivedCoreProperties.txt, and GBT is GraphemeBreakTest.txt.
    const Row = struct { code_point: u21, gcb: unicode.GraphemeClusterBreak, incb: unicode.IndicConjunctBreak, ext_pict: bool };
    const rows = [_]Row{
        .{ .code_point = 0x0000, .gcb = .CN, .incb = .None, .ext_pict = false }, // GBP line 53
        .{ .code_point = 0x000A, .gcb = .LF, .incb = .None, .ext_pict = false }, // GBP line 47
        .{ .code_point = 0x000D, .gcb = .CR, .incb = .None, .ext_pict = false }, // GBP line 41
        .{ .code_point = 0x0020, .gcb = .XX, .incb = .None, .ext_pict = false }, // unlisted; GBP line 17
        .{ .code_point = 0x00A9, .gcb = .XX, .incb = .None, .ext_pict = true }, // emoji-data line 847
        .{ .code_point = 0x0300, .gcb = .EX, .incb = .Extend, .ext_pict = false }, // GBP line 84; DCP line 13439
        .{ .code_point = 0x0378, .gcb = .XX, .incb = .None, .ext_pict = false }, // unlisted
        .{ .code_point = 0x0600, .gcb = .PP, .incb = .None, .ext_pict = false }, // GBP line 21
        .{ .code_point = 0x0903, .gcb = .SM, .incb = .None, .ext_pict = false }, // GBP line 521
        .{ .code_point = 0x0915, .gcb = .XX, .incb = .Consonant, .ext_pict = false }, // DCP line 13354
        .{ .code_point = 0x094D, .gcb = .EX, .incb = .Linker, .ext_pict = false }, // GBP line 115; DCP line 13325
        .{ .code_point = 0x0C95, .gcb = .XX, .incb = .None, .ext_pict = false }, // unlisted; GBT line 874
        .{ .code_point = 0x1100, .gcb = .L, .incb = .None, .ext_pict = false }, // GBP line 684
        .{ .code_point = 0x1160, .gcb = .V, .incb = .None, .ext_pict = false }, // GBP line 691
        .{ .code_point = 0x11A8, .gcb = .T, .incb = .None, .ext_pict = false }, // GBP line 700
        .{ .code_point = 0x1CF5, .gcb = .XX, .incb = .Linker, .ext_pict = false }, // DCP line 13336
        .{ .code_point = 0x200C, .gcb = .EX, .incb = .None, .ext_pict = false }, // GBP line 275; DCP line 13319 default; GBT line 877
        .{ .code_point = 0x200D, .gcb = .ZWJ, .incb = .Extend, .ext_pict = false }, // GBP line 1515; DCP line 13625
        .{ .code_point = 0xAC00, .gcb = .LV, .incb = .None, .ext_pict = false }, // GBP line 707
        .{ .code_point = 0xAC01, .gcb = .LVT, .incb = .None, .ext_pict = false }, // GBP line 1111
        .{ .code_point = 0xD800, .gcb = .XX, .incb = .None, .ext_pict = false }, // unlisted
        .{ .code_point = 0x16D63, .gcb = .V, .incb = .None, .ext_pict = false }, // GBP line 693
        .{ .code_point = 0x1F1E6, .gcb = .RI, .incb = .None, .ext_pict = false }, // GBP line 515; emoji-data line 970 ends at 1F1E5
        .{ .code_point = 0x1F3FB, .gcb = .EX, .incb = .Extend, .ext_pict = false }, // GBP line 507; DCP line 13851; emoji-data lines 1031-1032 skip it
        .{ .code_point = 0x1F469, .gcb = .XX, .incb = .None, .ext_pict = true }, // emoji-data line 1050
        .{ .code_point = 0xE0001, .gcb = .CN, .incb = .None, .ext_pict = false }, // GBP line 75
        .{ .code_point = 0x10FFFF, .gcb = .XX, .incb = .None, .ext_pict = false }, // unlisted
    };
    for (rows) |row| {
        const p = try unicode.lookup(row.code_point);
        testing.expectEqual(row.gcb, p.gcb) catch |e| return report(row.code_point, e);
        testing.expectEqual(row.incb, p.incb) catch |e| return report(row.code_point, e);
        testing.expectEqual(row.ext_pict, p.ext_pict) catch |e| return report(row.code_point, e);
    }
}

test "FP-0108 case 9: value counts over all code points equal the totals that the three files state" {
    const Gcb = unicode.GraphemeClusterBreak;
    const Incb = unicode.IndicConjunctBreak;
    var gcb: [std.meta.tags(Gcb).len]usize = @splat(0);
    var incb: [std.meta.tags(Incb).len]usize = @splat(0);
    var ext_pict: [2]usize = @splat(0);
    for (0..0x110000) |i| {
        const p = try unicode.lookup(@intCast(i));
        gcb[@backingInt(p.gcb)] += 1;
        incb[@backingInt(p.incb)] += 1;
        ext_pict[@intFromBool(p.ext_pict)] += 1;
    }
    // Each total cites its `# Total code points:` line in GraphemeBreakProperty.txt; XX is the remainder.
    const gcb_totals = [_]struct { Gcb, usize }{
        .{ .PP, 27 }, // line 37
        .{ .CR, 1 }, // line 43
        .{ .LF, 1 }, // line 49
        .{ .CN, 3_893 }, // line 80
        .{ .EX, 2_274 }, // line 511
        .{ .RI, 26 }, // line 517
        .{ .SM, 381 }, // line 680
        .{ .L, 125 }, // line 687
        .{ .V, 100 }, // line 696
        .{ .T, 137 }, // line 703
        .{ .LV, 399 }, // line 1107
        .{ .LVT, 10_773 }, // line 1511
        .{ .ZWJ, 1 }, // line 1517
        .{ .XX, 1_095_974 }, // 1,114,112 - 18,138
    };
    for (gcb_totals) |total| {
        testing.expectEqual(total[1], gcb[@backingInt(total[0])]) catch |e| {
            std.debug.print("gcb {t}\n", .{total[0]});
            return e;
        };
    }
    // DerivedCoreProperties.txt totals: Linker line 13348, Consonant line 13433, Extend line 13855; None is the remainder.
    const incb_totals = [_]struct { Incb, usize }{ .{ .Linker, 23 }, .{ .Consonant, 913 }, .{ .Extend, 2_254 }, .{ .None, 1_110_922 } };
    for (incb_totals) |total| {
        testing.expectEqual(total[1], incb[@backingInt(total[0])]) catch |e| {
            std.debug.print("incb {t}\n", .{total[0]});
            return e;
        };
    }
    // emoji-data.txt line 1303: `# Total elements: 2830`.
    try testing.expectEqual(@as(usize, 2_830), ext_pict[1]);
    try testing.expectEqual(@as(usize, 1_111_282), ext_pict[0]);
}

test "FP-0108 case 10: GraphemeClusterBreak and IndicConjunctBreak have exactly the assigned values and exact alias lookup" {
    const gcb_tags = [_][]const u8{ "CN", "CR", "EX", "L", "LF", "LV", "LVT", "PP", "RI", "SM", "T", "V", "XX", "ZWJ" };
    const gcb_names = std.meta.fieldNames(unicode.GraphemeClusterBreak);
    try testing.expectEqual(gcb_tags.len, gcb_names.len);
    for (gcb_tags, gcb_names) |expected, actual| try testing.expectEqualStrings(expected, actual);
    const incb_tags = [_][]const u8{ "Consonant", "Extend", "Linker", "None" };
    const incb_names = std.meta.fieldNames(unicode.IndicConjunctBreak);
    try testing.expectEqual(incb_tags.len, incb_names.len);
    for (incb_tags, incb_names) |expected, actual| try testing.expectEqualStrings(expected, actual);

    const Gcb = ?unicode.GraphemeClusterBreak;
    try testing.expectEqual(@as(Gcb, .CN), unicode.GraphemeClusterBreak.fromAlias("Control"));
    try testing.expectEqual(@as(Gcb, .CN), unicode.GraphemeClusterBreak.fromAlias("CN"));
    try testing.expectEqual(@as(Gcb, .EX), unicode.GraphemeClusterBreak.fromAlias("Extend"));
    try testing.expectEqual(@as(Gcb, .PP), unicode.GraphemeClusterBreak.fromAlias("Prepend"));
    try testing.expectEqual(@as(Gcb, .RI), unicode.GraphemeClusterBreak.fromAlias("Regional_Indicator"));
    try testing.expectEqual(@as(Gcb, .SM), unicode.GraphemeClusterBreak.fromAlias("SpacingMark"));
    try testing.expectEqual(@as(Gcb, .XX), unicode.GraphemeClusterBreak.fromAlias("Other"));
    try testing.expectEqual(@as(Gcb, .ZWJ), unicode.GraphemeClusterBreak.fromAlias("ZWJ"));
    for ([_][]const u8{ "E_Base", "EB", "Glue_After_Zwj", "Nope" }) |name| {
        testing.expectEqual(@as(Gcb, null), unicode.GraphemeClusterBreak.fromAlias(name)) catch |e| {
            std.debug.print("alias {s}\n", .{name});
            return e;
        };
    }
    try testing.expectEqual(@as(?unicode.IndicConjunctBreak, .Linker), unicode.IndicConjunctBreak.fromAlias("Linker"));
    try testing.expectEqual(@as(?unicode.IndicConjunctBreak, null), unicode.IndicConjunctBreak.fromAlias("linker"));
}
