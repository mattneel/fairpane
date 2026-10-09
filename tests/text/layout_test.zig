//! FP-0111 cases 1 to 24: Coverage, ClassDef, Device, ScriptList, LangSys, FeatureList, LookupList, lookup selection,
//! and GDEF, on blobs and on synthetic fonts that `layout_builder.zig` writes into `B_TT`.

const std = @import("std");
const testing = std.testing;
const fairpane = @import("fairpane");
const font = fairpane.font;
const layout = font.layout;
const Reader = font.Reader;
const Defect = font.Defect;
const builder = @import("sfnt_builder.zig");
const lb = @import("layout_builder.zig");
const hex = lb.hex;
const Tag = lb.Tag;
const Wyhash = std.hash.Wyhash;

const gpa = testing.allocator;

fn blob(bytes: []const u8) Reader {
    return Reader.init(bytes);
}

/// Prints the active tag of a status union and its payload when the payload is an integer or an enum.
fn printStatus(status: anytype) void {
    switch (status) {
        inline else => |payload, tag| switch (@typeInfo(@TypeOf(payload))) {
            .int, .@"enum" => std.debug.print("{s} {any}\n", .{ @tagName(tag), payload }),
            else => std.debug.print("{s}\n", .{@tagName(tag)}),
        },
    }
}

fn valid(status: anytype) !@FieldType(@TypeOf(status), "valid") {
    return switch (status) {
        .valid => |v| v,
        else => {
            std.debug.print("expected valid, got ", .{});
            printStatus(status);
            return error.TestUnexpectedResult;
        },
    };
}

fn some(value: anytype) !@typeInfo(@TypeOf(value)).optional.child {
    return value orelse {
        std.debug.print("expected a value, got null\n", .{});
        return error.TestUnexpectedResult;
    };
}

fn expectRejected(expected: Defect, status: anytype) !void {
    switch (status) {
        .rejected => |d| if (d == expected) return,
        else => {},
    }
    std.debug.print("expected rejected {s}, got ", .{@tagName(expected)});
    printStatus(status);
    return error.TestUnexpectedResult;
}

fn expectUnsupportedVersion(expected: u32, status: anytype) !void {
    switch (status) {
        .unsupported_version => |v| if (v == expected) return,
        else => {},
    }
    std.debug.print("expected unsupported_version {d}, got ", .{expected});
    printStatus(status);
    return error.TestUnexpectedResult;
}

fn expectCoverage(c: layout.Coverage, format: u16, glyphs: []const u16) !void {
    try testing.expectEqual(format, c.format);
    try testing.expectEqual(@as(u32, @intCast(glyphs.len)), c.glyphCount());
    var it = c.iterator();
    for (glyphs, 0..) |g, i| {
        try testing.expectEqual(@as(?u16, g), it.next());
        try testing.expectEqual(@as(?u16, @intCast(i)), c.index(g));
    }
    try testing.expectEqual(@as(?u16, null), it.next());
}

fn expectLangSys(ls: layout.LangSys, required: ?u16, features: []const u16) !void {
    try testing.expectEqual(required, ls.required_feature);
    try testing.expectEqual(@as(u16, @intCast(features.len)), ls.feature_index_count);
    for (features, 0..) |f, k| try testing.expectEqual(@as(?u16, f), ls.featureIndex(@intCast(k)));
    try testing.expectEqual(@as(?u16, null), ls.featureIndex(@intCast(features.len)));
}

fn expectFeature(f: layout.Feature, tag: Tag, lookups: []const u16) !void {
    try testing.expectEqual(tag, f.tag);
    try testing.expectEqual(@as(u16, 0), f.params_offset);
    try testing.expectEqual(@as(u16, @intCast(lookups.len)), f.lookup_index_count);
    for (lookups, 0..) |l, k| try testing.expectEqual(@as(?u16, l), f.lookupIndex(@intCast(k)));
    try testing.expectEqual(@as(?u16, null), f.lookupIndex(@intCast(lookups.len)));
}

const LookupExpectation = struct {
    lookup_type: u16,
    extension: bool = false,
    flag: u16 = 0,
    subtables: u16 = 1,
    mark_filtering_set: ?u16 = null,
};

fn expectLookup(status: ?layout.LookupStatus, e: LookupExpectation) !layout.Lookup {
    const l = try valid(try some(status));
    try testing.expectEqual(e.lookup_type, l.lookup_type);
    try testing.expectEqual(e.extension, l.extension);
    try testing.expectEqual(e.flag, l.flag);
    try testing.expectEqual(e.subtables, l.subtable_count);
    try testing.expectEqual(e.mark_filtering_set, l.mark_filtering_set);
    return l;
}

/// Subtable `k` of `l` has `format`, and its primary coverage has `coverage_format` and `glyphs`.
fn expectSubtable(l: layout.Lookup, k: u16, format: u16, coverage_format: u16, glyphs: []const u16) !void {
    const s = try valid(try some(l.subtable(k)));
    try testing.expectEqual(format, s.format);
    try expectCoverage(try valid(s.coverage()), coverage_format, glyphs);
}

/// `B_TT` with the named tables replaced, built and parsed under `.reject`.
const Fixture = struct {
    bytes: []u8,
    f: font.Font,

    const Replacement = struct { Tag, []const u8 };

    fn init(replacements: []const Replacement) !Fixture {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        for (replacements) |r| try set.put(r[0], r[1]);
        const bytes = try set.build(&.{}, &.{});
        errdefer gpa.free(bytes);
        return .{ .bytes = bytes, .f = try font.parse(bytes, .{ .checksums = .reject }) };
    }

    fn deinit(self: *Fixture) void {
        gpa.free(self.bytes);
        self.* = undefined;
    }

    fn gsub(self: *const Fixture) !layout.Layout {
        return valid(self.f.gsub());
    }

    fn gpos(self: *const Fixture) !layout.Layout {
        return valid(self.f.gpos());
    }

    fn gdef(self: *const Fixture) !layout.Gdef {
        return valid(self.f.gdef());
    }
};

const LangSysUse = @FieldType(layout.Selection, "lang_sys");
const MaskEntry = struct { usize, u64 };
const required_bit: u64 = 1 << 63;

const SelectionExpectation = struct {
    script: ?Tag,
    lang_sys: LangSysUse,
    required: ?u16 = null,
    /// Every nonzero mask; every other mask must be zero.
    masks: []const MaskEntry = &.{},
    feature_variations: bool = false,
};

fn expectMasks(masks: []const u64, expected: []const MaskEntry) !void {
    for (masks, 0..) |m, i| {
        var want: u64 = 0;
        for (expected) |e| {
            if (e[0] == i) want = e[1];
        }
        if (m != want) {
            std.debug.print("mask {d}: expected 0x{x}, got 0x{x}\n", .{ i, want, m });
            return error.TestUnexpectedResult;
        }
    }
}

fn expectSelection(l: layout.Layout, request: layout.Request, masks: []u64, e: SelectionExpectation) !void {
    const s = try valid(try l.selectLookups(request, .{}, masks));
    try testing.expectEqual(e.script, s.script);
    try testing.expectEqual(e.lang_sys, s.lang_sys);
    try testing.expectEqual(e.required, s.required_feature);
    try testing.expectEqual(e.feature_variations, s.feature_variations);
    try expectMasks(masks[0..l.lookupCount()], e.masks);
    try testing.expectEqual(@as(u16, @intCast(e.masks.len)), s.lookup_count);
}

const s1_request: layout.Request = .{ .script = "arab".*, .features = &.{ "ccmp".*, "init".* } };
const s1_masks = [_]MaskEntry{ .{ 0, 0x1 }, .{ 1, 0x2 }, .{ 2, required_bit | 0x2 }, .{ 6, required_bit } };

test "FP-0111 case 1: Coverage formats 1 and 2, chapter2 Examples 5 and 6, and edge blobs" {
    const cv1 = hex("0001 0005 0038 003B 0041 0042 004A");
    const c1 = try valid(layout.parseCoverage(blob(&cv1), 0));
    try expectCoverage(c1, 1, &.{ 0x38, 0x3B, 0x41, 0x42, 0x4A });
    for ([_]u16{ 0x00, 0x37, 0x39, 0x4B }) |g| try testing.expectEqual(@as(?u16, null), c1.index(g));

    const cv2 = hex("0002 0001 004E 0057 0000");
    const c2 = try valid(layout.parseCoverage(blob(&cv2), 0));
    try expectCoverage(c2, 2, &.{ 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57 });
    try testing.expectEqual(@as(?u16, 0), c2.index(0x4E));
    try testing.expectEqual(@as(?u16, 5), c2.index(0x53));
    try testing.expectEqual(@as(?u16, 9), c2.index(0x57));
    for ([_]u16{ 0x4D, 0x58 }) |g| try testing.expectEqual(@as(?u16, null), c2.index(g));

    const cv3 = hex("0002 0002 0005 0007 0000 000A 000A 0003");
    const c3 = try valid(layout.parseCoverage(blob(&cv3), 0));
    try expectCoverage(c3, 2, &.{ 5, 6, 7, 10 });
    try testing.expectEqual(@as(?u16, 0), c3.index(5));
    try testing.expectEqual(@as(?u16, 2), c3.index(7));
    try testing.expectEqual(@as(?u16, 3), c3.index(10));
    for ([_]u16{ 4, 8, 9, 11 }) |g| try testing.expectEqual(@as(?u16, null), c3.index(g));

    const cv4 = hex("0001 0000");
    const c4 = try valid(layout.parseCoverage(blob(&cv4), 0));
    try expectCoverage(c4, 1, &.{});
    try testing.expectEqual(@as(?u16, null), c4.index(0));

    const cv5 = hex("0002 0001 0000 FFFF 0000");
    const c5 = try valid(layout.parseCoverage(blob(&cv5), 0));
    try testing.expectEqual(@as(u32, 65536), c5.glyphCount());
    try testing.expectEqual(@as(?u16, 0), c5.index(0));
    try testing.expectEqual(@as(?u16, 32768), c5.index(0x8000));
    try testing.expectEqual(@as(?u16, 65535), c5.index(0xFFFF));

    const cv6 = hex("0000 0001 0001 0007");
    try expectCoverage(try valid(layout.parseCoverage(blob(&cv6), 2)), 1, &.{7});
}

test "FP-0111 case 2: malformed Coverage blobs are rejected or unsupported" {
    const Bad = struct { bytes: []const u8, defect: Defect };
    const bad = [_]Bad{
        .{ .bytes = &hex("0001 0003 0005 0005 0006"), .defect = .unsorted_records },
        .{ .bytes = &hex("0001 0002 0006 0005"), .defect = .unsorted_records },
        .{ .bytes = &hex("0001 0003 0005"), .defect = .count_out_of_bounds },
        .{ .bytes = &hex("0002 0001 0007 0005 0000"), .defect = .invalid_range },
        .{ .bytes = &hex("0002 0002 0005 0007 0000 0007 0009 0003"), .defect = .unsorted_records },
        .{ .bytes = &hex("0002 0002 0005 0007 0000 000A 000A 0002"), .defect = .inconsistent_coverage_index },
        .{ .bytes = &hex("0002 0001 0005 0007 0001"), .defect = .inconsistent_coverage_index },
        .{ .bytes = &hex("0002 0002 0005 0007 0000"), .defect = .count_out_of_bounds },
        .{ .bytes = &hex("0001"), .defect = .too_short },
    };
    for (bad) |b| {
        expectRejected(b.defect, layout.parseCoverage(blob(b.bytes), 0)) catch |err| {
            std.debug.print("Coverage {any}\n", .{b.bytes});
            return err;
        };
    }
    try expectUnsupportedVersion(3, layout.parseCoverage(blob(&hex("0003 0000")), 0));
    try expectUnsupportedVersion(0, layout.parseCoverage(blob(&hex("0000 0000")), 0));
    try expectRejected(.offset_out_of_bounds, layout.parseCoverage(blob(&hex("0001 0000")), 4));
}

test "FP-0111 case 3: ClassDef formats 1 and 2, chapter2 Examples 7 and 8, gdef Example 7, and edge blobs" {
    const cd1 = hex("0001 0032 001A 0000 0001 0000 0001 0000 0001 0002 0001 0000 0002 0001 0001 0000 0000 0000 0002 0002 0000 0000 0001 0000 0000 0000 0000 0002 0000");
    const c1 = try valid(layout.parseClassDef(blob(&cd1), 0));
    try testing.expectEqual(@as(u16, 1), c1.format);
    const classes = [26]u16{ 0, 1, 0, 1, 0, 1, 2, 1, 0, 2, 1, 1, 0, 0, 0, 2, 2, 0, 0, 1, 0, 0, 0, 0, 2, 0 };
    for (classes, 0..) |class, k| try testing.expectEqual(class, c1.class(@intCast(0x32 + k)));
    for ([_]u16{ 0x31, 0x4C, 0xFFFF }) |g| try testing.expectEqual(@as(u16, 0), c1.class(g));

    const cd2 = hex("0002 0003 0030 0031 0002 0040 0041 0003 00D2 00D3 0001");
    const c2 = try valid(layout.parseClassDef(blob(&cd2), 0));
    try testing.expectEqual(@as(u16, 2), c2.format);
    for ([_][2]u16{ .{ 0x30, 2 }, .{ 0x31, 2 }, .{ 0x40, 3 }, .{ 0x41, 3 }, .{ 0xD2, 1 }, .{ 0xD3, 1 } }) |gc| try testing.expectEqual(gc[1], c2.class(gc[0]));
    for ([_]u16{ 0x2F, 0x32, 0x3F, 0x42, 0xD4 }) |g| try testing.expectEqual(@as(u16, 0), c2.class(g));

    const cd3 = hex("0002 0004 0268 026A 0001 0270 0272 0001 028C 028F 0002 0295 0295 0002");
    const c3 = try valid(layout.parseClassDef(blob(&cd3), 0));
    for ([_][2]u16{ .{ 0x269, 1 }, .{ 0x271, 1 }, .{ 0x28D, 2 }, .{ 0x295, 2 }, .{ 0x26B, 0 }, .{ 0x296, 0 } }) |gc| try testing.expectEqual(gc[1], c3.class(gc[0]));

    const cd4 = hex("0001 FFFF 0001 0005");
    const c4 = try valid(layout.parseClassDef(blob(&cd4), 0));
    try testing.expectEqual(@as(u16, 5), c4.class(0xFFFF));
    try testing.expectEqual(@as(u16, 0), c4.class(0xFFFE));

    const cd5 = hex("0002 0000");
    const c5 = try valid(layout.parseClassDef(blob(&cd5), 0));
    for ([_]u16{ 0, 1, 0x30, 0xFFFF }) |g| try testing.expectEqual(@as(u16, 0), c5.class(g));
}

test "FP-0111 case 4: malformed ClassDef blobs, including the gdef Example 2 bytes, are rejected or unsupported" {
    const Bad = struct { bytes: []const u8, defect: Defect };
    const bad = [_]Bad{
        .{ .bytes = &lb.gdef_example2, .defect = .unsorted_records },
        .{ .bytes = &hex("0001 FFFF 0002 0001 0001"), .defect = .count_out_of_bounds },
        .{ .bytes = &hex("0001 0000 0003 0001"), .defect = .count_out_of_bounds },
        .{ .bytes = &hex("0002 0001 0005 0004 0001"), .defect = .invalid_range },
        .{ .bytes = &hex("0002 0002 0001 0005 0001 0005 0006 0002"), .defect = .unsorted_records },
        .{ .bytes = &hex("0001 0000"), .defect = .too_short },
        .{ .bytes = &hex("0002"), .defect = .too_short },
    };
    for (bad) |b| {
        expectRejected(b.defect, layout.parseClassDef(blob(b.bytes), 0)) catch |err| {
            std.debug.print("ClassDef {any}\n", .{b.bytes});
            return err;
        };
    }
    try expectUnsupportedVersion(3, layout.parseClassDef(blob(&hex("0003 0000")), 0));
    try expectRejected(.offset_out_of_bounds, layout.parseClassDef(blob(&hex("0002 0000")), 4));
}

test "FP-0111 case 5: Device and VariationIndex tables are reported as unsupported with their fields" {
    const Case = struct { bytes: []const u8, expected: layout.DeviceStatus };
    const cases = [_]Case{
        .{ .bytes = &hex("000B 000F 0001 5540"), .expected = .{ .unsupported_device = .{ .start_size = 11, .end_size = 15, .delta_format = 1 } } },
        .{ .bytes = &hex("000C 0011 0002 1111 2200"), .expected = .{ .unsupported_device = .{ .start_size = 12, .end_size = 17, .delta_format = 2 } } },
        .{ .bytes = &hex("000B 000F 0003 1234 5678 9A00"), .expected = .{ .unsupported_device = .{ .start_size = 11, .end_size = 15, .delta_format = 3 } } },
        .{ .bytes = &hex("0001 0002 8000"), .expected = .{ .unsupported_variation_index = .{ .outer = 1, .inner = 2 } } },
        .{ .bytes = &hex("000B 000F 0004"), .expected = .{ .unsupported_format = 4 } },
        .{ .bytes = &hex("000B 000F 0000"), .expected = .{ .unsupported_format = 0 } },
    };
    for (cases) |c| try testing.expectEqual(c.expected, layout.parseDevice(blob(c.bytes), 0));
}

test "FP-0111 case 6: malformed Device tables are rejected" {
    try expectRejected(.count_out_of_bounds, layout.parseDevice(blob(&hex("000B 000F 0001")), 0));
    try expectRejected(.count_out_of_bounds, layout.parseDevice(blob(&hex("000B 000F 0003 1234 5678")), 0));
    try expectRejected(.invalid_range, layout.parseDevice(blob(&hex("000F 000B 0001 0000")), 0));
    try expectRejected(.too_short, layout.parseDevice(blob(&hex("000B 000F")), 0));
    try expectRejected(.offset_out_of_bounds, layout.parseDevice(blob(&hex("000B 000F 0001 5540")), 8));
}

test "FP-0111 case 7: the chapter2 script examples, with DFLT and default LangSys fallback" {
    var masks: [4]u64 = undefined;
    {
        var fx = try Fixture.init(&.{.{ "GSUB".*, &lb.e1 }});
        defer fx.deinit();
        const l = try fx.gsub();
        try testing.expectEqual(@as(u16, 3), l.scriptCount());
        for ([_]Tag{ "hani".*, "kana".*, "latn".* }, 0..) |tag, i| {
            const s = try valid(try some(l.script(@intCast(i))));
            try testing.expectEqual(tag, s.tag);
            try testing.expect(s.defaultLangSys() == .absent);
            try testing.expectEqual(@as(u16, 0), s.lang_sys_count);
        }
        try expectSelection(l, .{ .script = "kana".*, .features = &.{} }, &masks, .{ .script = "kana".*, .lang_sys = .none });
        try expectSelection(l, .{ .script = "cyrl".*, .features = &.{} }, &masks, .{ .script = null, .lang_sys = .none });
    }
    {
        var fx = try Fixture.init(&.{.{ "GSUB".*, &lb.e2 }});
        defer fx.deinit();
        const l = try fx.gsub();
        const s = try valid(try some(l.script(0)));
        try testing.expectEqual("arab".*, s.tag);
        try expectLangSys(try valid(s.defaultLangSys()), null, &.{ 0, 1, 2 });
        try testing.expectEqual(@as(?Tag, "URD ".*), s.langSysTag(0));
        try expectLangSys(try valid(try some(s.langSys(0))), 3, &.{ 0, 1, 2 });
        const isolated = [_]Tag{ "init".*, "fina".*, "medi".* };
        try expectSelection(l, .{ .script = "arab".*, .features = &isolated }, &masks, .{
            .script = "arab".*,
            .lang_sys = .default,
            .masks = &.{ .{ 0, 0x1 }, .{ 1, 0x2 }, .{ 2, 0x4 } },
        });
        try expectSelection(l, .{ .script = "arab".*, .language = "URD ".*, .features = &isolated }, &masks, .{
            .script = "arab".*,
            .lang_sys = .requested,
            .required = 3,
            .masks = &.{ .{ 0, 0x1 }, .{ 1, 0x2 }, .{ 2, 0x4 }, .{ 3, required_bit } },
        });
        try expectSelection(l, .{ .script = "arab".*, .language = "URD ".*, .features = &.{} }, &masks, .{
            .script = "arab".*,
            .lang_sys = .requested,
            .required = 3,
            .masks = &.{.{ 3, required_bit }},
        });
    }
}

test "FP-0111 case 8: chapter2 Examples 3 and 4, a FeatureList and a LookupList" {
    var fx = try Fixture.init(&.{.{ "GSUB".*, &lb.e34 }});
    defer fx.deinit();
    const l = try fx.gsub();
    try expectFeature(try valid(try some(l.feature(0))), "liga".*, &.{1});
    try expectFeature(try valid(try some(l.feature(1))), "liga".*, &.{ 0, 1 });
    try expectFeature(try valid(try some(l.feature(2))), "liga".*, &.{ 0, 1, 2 });
    try testing.expectEqual(@as(u16, 3), l.lookupCount());
    for (0..3) |i| {
        const lookup = try expectLookup(l.lookup(@intCast(i)), .{ .lookup_type = 4, .flag = 0x000C });
        try testing.expect(lookup.ignoreLigatures());
        try testing.expect(lookup.ignoreMarks());
        try expectSubtable(lookup, 0, 1, 1, &.{2});
    }
    var masks: [3]u64 = undefined;
    try expectSelection(l, .{ .script = "DFLT".*, .features = &.{"liga".*} }, &masks, .{
        .script = "DFLT".*,
        .lang_sys = .default,
        .masks = &.{ .{ 0, 0x1 }, .{ 1, 0x1 } },
    });
}

test "FP-0111 case 9: the G ScriptList, LangSys tables, and FeatureList" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var fx = try Fixture.init(&.{.{ "GSUB".*, g.bytes }});
    defer fx.deinit();
    const l = try fx.gsub();
    try testing.expectEqual(@as(u16, 3), l.scriptCount());
    try testing.expect(l.script(3) == null);
    for (lb.g_spec.scripts, 0..) |spec, i| {
        const s = try valid(try some(l.script(@intCast(i))));
        try testing.expectEqual(spec.tag, s.tag);
        try testing.expectEqual(@as(u16, @intCast(spec.records.len)), s.lang_sys_count);
        if (spec.default) |d| {
            try expectLangSys(try valid(s.defaultLangSys()), d.required, d.features);
        } else try testing.expect(s.defaultLangSys() == .absent);
        for (spec.records, 0..) |r, j| {
            try testing.expectEqual(@as(?Tag, r.tag), s.langSysTag(@intCast(j)));
            try expectLangSys(try valid(try some(s.langSys(@intCast(j)))), r.sys.required, r.sys.features);
        }
        try testing.expectEqual(@as(?Tag, null), s.langSysTag(@intCast(spec.records.len)));
        try testing.expect(s.langSys(@intCast(spec.records.len)) == null);
    }
    try testing.expect((try valid(try some(l.script(2)))).defaultLangSys() == .absent);
    try testing.expectEqual(@as(u16, 7), l.featureCount());
    for (lb.g_spec.features, 0..) |spec, i| try expectFeature(try valid(try some(l.feature(@intCast(i)))), spec.tag, spec.lookups);
    try testing.expect(l.feature(7) == null);
    try testing.expectEqual(@as(u16, 13), l.lookupCount());
}

test "FP-0111 case 10: lookup selection on G, P, and B_TT" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var p = try lb.p(gpa);
    defer p.deinit(gpa);
    var fx = try Fixture.init(&.{ .{ "GSUB".*, g.bytes }, .{ "GPOS".*, p.bytes } });
    defer fx.deinit();
    const l = try fx.gsub();
    var masks: [13]u64 = undefined;
    // S1 and S1b.
    try expectSelection(l, s1_request, &masks, .{ .script = "arab".*, .lang_sys = .default, .required = 5, .masks = &s1_masks });
    try expectSelection(l, .{ .script = "arab".*, .features = &.{ "ccmp".*, "init".*, "rlig".* } }, &masks, .{
        .script = "arab".*,
        .lang_sys = .default,
        .required = 5,
        .masks = &.{ .{ 0, 0x1 }, .{ 1, 0x2 }, .{ 2, required_bit | 0x6 }, .{ 6, required_bit | 0x4 } },
    });
    // S2 and S3.
    try expectSelection(l, .{ .script = "arab".*, .language = "URD ".*, .features = &.{ "init".*, "locl".*, "ccmp".* } }, &masks, .{
        .script = "arab".*,
        .lang_sys = .requested,
        .masks = &.{ .{ 1, 0x1 }, .{ 2, 0x1 }, .{ 5, 0x2 } },
    });
    try expectSelection(l, .{ .script = "arab".*, .language = "FAR ".*, .features = s1_request.features }, &masks, .{
        .script = "arab".*,
        .lang_sys = .default,
        .required = 5,
        .masks = &s1_masks,
    });
    // S4 and S5: DFLT fallback.
    try expectSelection(l, .{ .script = "cyrl".*, .features = &.{ "ccmp".*, "smcp".* } }, &masks, .{
        .script = "DFLT".*,
        .lang_sys = .default,
        .masks = &.{.{ 0, 0x1 }},
    });
    try expectSelection(l, .{ .script = "cyrl".*, .language = "ZZZ ".*, .features = &.{ "ccmp".*, "smcp".* } }, &masks, .{
        .script = "DFLT".*,
        .lang_sys = .requested,
        .masks = &.{ .{ 0, 0x1 }, .{ 7, 0x2 } },
    });
    // S6 to S9: latn has no default LangSys.
    try expectSelection(l, .{ .script = "latn".*, .features = &.{"liga".*} }, &masks, .{ .script = "latn".*, .lang_sys = .none });
    try expectSelection(l, .{ .script = "latn".*, .language = "TRK ".*, .features = &.{"liga".*} }, &masks, .{
        .script = "latn".*,
        .lang_sys = .requested,
        .masks = &.{.{ 4, 0x1 }},
    });
    try expectSelection(l, .{ .script = "latn".*, .language = "DEU ".*, .features = &.{ "liga".*, "smcp".* } }, &masks, .{
        .script = "latn".*,
        .lang_sys = .requested,
        .masks = &.{ .{ 3, 0x1 }, .{ 7, 0x2 } },
    });
    try expectSelection(l, .{ .script = "latn".*, .language = "DEU ".*, .features = &.{} }, &masks, .{ .script = "latn".*, .lang_sys = .requested });
    // S10 on P.
    try expectSelection(try fx.gpos(), .{ .script = "latn".*, .features = &.{ "mark".*, "kern".* } }, &masks, .{
        .script = "DFLT".*,
        .lang_sys = .default,
        .masks = &.{ .{ 0, 0x2 }, .{ 1, 0x1 }, .{ 2, 0x2 } },
    });
    // S11 on B_TT.
    var plain = try Fixture.init(&.{});
    defer plain.deinit();
    try expectSelection(try plain.gpos(), .{ .script = "cyrl".*, .features = &.{} }, &masks, .{ .script = null, .lang_sys = .none });
    try expectSelection(try plain.gsub(), .{ .script = "cyrl".*, .features = &.{} }, &masks, .{ .script = "DFLT".*, .lang_sys = .default });
}

test "FP-0111 case 11: selection errors and a 63-tag request" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var fx = try Fixture.init(&.{.{ "GSUB".*, g.bytes }});
    defer fx.deinit();
    const l = try fx.gsub();
    var short: [12]u64 = undefined;
    try testing.expectError(error.MasksTooShort, l.selectLookups(s1_request, .{}, &short));
    var masks: [13]u64 = undefined;
    var too_many: [64]Tag = undefined;
    @memset(&too_many, "ccmp".*);
    try testing.expectError(error.TooManyFeatures, l.selectLookups(.{ .script = "arab".*, .features = &too_many }, .{}, &masks));
    try expectSelection(l, .{ .script = "arab".*, .features = too_many[0..63] }, &masks, .{
        .script = "arab".*,
        .lang_sys = .default,
        .required = 5,
        .masks = &.{ .{ 0, 0x7FFFFFFFFFFFFFFF }, .{ 2, required_bit }, .{ 6, required_bit } },
    });
}

test "FP-0111 case 12: a FeatureVariations table is reported, and the default lookups are selected" {
    var g11 = try lb.g11(gpa);
    defer g11.deinit(gpa);
    var fx = try Fixture.init(&.{.{ "GSUB".*, g11.bytes }});
    defer fx.deinit();
    const l = try fx.gsub();
    try testing.expectEqual(@as(u32, 0x00010001), l.version);
    try testing.expect(l.feature_variations != 0);
    var masks: [13]u64 = undefined;
    try expectSelection(l, s1_request, &masks, .{ .script = "arab".*, .lang_sys = .default, .required = 5, .masks = &s1_masks, .feature_variations = true });
}

test "FP-0111 case 13: the G lookups, flags, mark filtering sets, extensions, and subtable formats" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var fx = try Fixture.init(&.{.{ "GSUB".*, g.bytes }});
    defer fx.deinit();
    const l = try fx.gsub();

    const l0 = try expectLookup(l.lookup(0), .{ .lookup_type = 1, .subtables = 2 });
    try expectSubtable(l0, 0, 1, 1, &.{ 2, 3 });
    try expectSubtable(l0, 1, 2, 2, &.{ 1, 2, 3 });
    try testing.expect(l0.subtable(2) == null);

    const l1 = try expectLookup(l.lookup(1), .{ .lookup_type = 4, .flag = 0x0008 });
    try testing.expect(l1.ignoreMarks());
    try expectSubtable(l1, 0, 1, 1, &.{2});

    const l2 = try expectLookup(l.lookup(2), .{ .lookup_type = 6, .flag = 0x0010, .mark_filtering_set = 1 });
    try testing.expect(l2.useMarkFilteringSet());
    try expectSubtable(l2, 0, 3, 1, &.{3});

    const l3 = try expectLookup(l.lookup(3), .{ .lookup_type = 1, .extension = true, .flag = 0x0200, .subtables = 2 });
    try testing.expectEqual(@as(u8, 2), l3.markAttachmentClass());
    try expectSubtable(l3, 0, 1, 1, &.{1});
    try expectSubtable(l3, 1, 2, 1, &.{2});

    const l4 = try expectLookup(l.lookup(4), .{ .lookup_type = 5 });
    try expectSubtable(l4, 0, 3, 1, &.{1});

    try testing.expectEqual(@as(?layout.LookupStatus, .{ .unsupported_type = 9 }), l.lookup(5));
    const l6 = try expectLookup(l.lookup(6), .{ .lookup_type = 1 });
    try testing.expectEqual(@as(?layout.SubtableStatus, .{ .unsupported_format = 3 }), l6.subtable(0));
    try expectRejected(.nested_extension, try some(l.lookup(7)));
    try expectRejected(.mixed_lookup_types, try some(l.lookup(8)));
    try testing.expectEqual(@as(?layout.LookupStatus, .{ .unsupported_type = 10 }), l.lookup(9));
    try testing.expectEqual(@as(?layout.LookupStatus, .{ .unsupported_extension_format = 2 }), l.lookup(10));

    const l11 = try expectLookup(l.lookup(11), .{ .lookup_type = 1, .flag = 0x00E0 });
    try testing.expect(!l11.rightToLeft() and !l11.ignoreBaseGlyphs() and !l11.ignoreLigatures() and !l11.ignoreMarks() and !l11.useMarkFilteringSet());
    try testing.expectEqual(@as(u8, 0), l11.markAttachmentClass());

    const l12 = try expectLookup(l.lookup(12), .{ .lookup_type = 1, .flag = 0xFF1F, .mark_filtering_set = 0 });
    try testing.expect(l12.rightToLeft() and l12.ignoreBaseGlyphs() and l12.ignoreLigatures() and l12.ignoreMarks() and l12.useMarkFilteringSet());
    try testing.expectEqual(@as(u8, 255), l12.markAttachmentClass());

    try testing.expect(l.lookup(13) == null);
}

test "FP-0111 case 14: the P lookups, including mark coverages, extensions, and unknown types" {
    var p = try lb.p(gpa);
    defer p.deinit(gpa);
    var fx = try Fixture.init(&.{.{ "GPOS".*, p.bytes }});
    defer fx.deinit();
    const l = try fx.gpos();
    try expectSubtable(try expectLookup(l.lookup(0), .{ .lookup_type = 1 }), 0, 1, 1, &.{2});
    try expectSubtable(try expectLookup(l.lookup(1), .{ .lookup_type = 4 }), 0, 1, 1, &.{3});
    try expectSubtable(try expectLookup(l.lookup(2), .{ .lookup_type = 1, .extension = true }), 0, 1, 1, &.{2});
    try testing.expectEqual(@as(?layout.LookupStatus, .{ .unsupported_type = 10 }), l.lookup(3));
    try expectSubtable(try expectLookup(l.lookup(4), .{ .lookup_type = 8 }), 0, 3, 1, &.{3});
    const p5 = try expectLookup(l.lookup(5), .{ .lookup_type = 2 });
    try testing.expectEqual(@as(?layout.SubtableStatus, .{ .unsupported_format = 3 }), p5.subtable(0));
    try expectRejected(.nested_extension, try some(l.lookup(6)));
    try expectSubtable(try expectLookup(l.lookup(7), .{ .lookup_type = 4, .extension = true }), 0, 1, 1, &.{3});
    try testing.expectEqual(@as(?layout.LookupStatus, .{ .unsupported_type = 0 }), l.lookup(8));
}

/// One big-endian field write: 2 or 4 bytes.
const Edit = struct { at: usize, value: u32, width: u8 = 2 };

fn tagValue(tag: *const [4]u8) u32 {
    return std.mem.readInt(u32, tag, .big);
}

/// `B_TT` whose `tag` table is `table` with `edits` applied.
fn edited(tag: Tag, table: []const u8, edits: []const Edit) !Fixture {
    const copy = try gpa.dupe(u8, table);
    defer gpa.free(copy);
    for (edits) |e| switch (e.width) {
        2 => builder.writeU16(copy[e.at..][0..2], @intCast(e.value)),
        4 => builder.writeU32(copy[e.at..][0..4], e.value),
        else => unreachable,
    };
    return Fixture.init(&.{.{ tag, copy }});
}

fn selectS1(l: layout.Layout, masks: []u64) !layout.SelectionStatus {
    return l.selectLookups(s1_request, .{}, masks);
}

test "FP-0111 case 15: malformed Script, LangSys, and Feature fields reject the selection" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    const at = g.at;
    var masks: [16]u64 = undefined;
    const s2_request: layout.Request = .{ .script = "arab".*, .language = "URD ".*, .features = &.{ "init".*, "locl".*, "ccmp".* } };
    const s4_request: layout.Request = .{ .script = "cyrl".*, .features = &.{ "ccmp".*, "smcp".* } };
    const s5_request: layout.Request = .{ .script = "cyrl".*, .language = "ZZZ ".*, .features = &.{ "ccmp".*, "smcp".* } };
    const s7_request: layout.Request = .{ .script = "latn".*, .language = "TRK ".*, .features = &.{"liga".*} };
    { // X1
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.default_lang_sys[1].? + 6, .value = 7 }});
        defer fx.deinit();
        try expectRejected(.index_out_of_range, try selectS1(try fx.gsub(), &masks));
    }
    { // X2
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.default_lang_sys[1].? + 2, .value = 7 }});
        defer fx.deinit();
        try expectRejected(.index_out_of_range, try selectS1(try fx.gsub(), &masks));
    }
    { // X3
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.features[1] + 4, .value = 13 }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.index_out_of_range, try selectS1(l, &masks));
        try expectRejected(.index_out_of_range, try some(l.feature(1)));
    }
    { // X4
        var fx = try edited("GSUB".*, g.bytes, &.{
            .{ .at = at.scripts[2] + 4, .value = tagValue("TRK "), .width = 4 },
            .{ .at = at.scripts[2] + 10, .value = tagValue("DEU "), .width = 4 },
        });
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.unsorted_records, try some(l.script(2)));
        try expectRejected(.unsorted_records, try l.selectLookups(s7_request, .{}, &masks));
    }
    { // X5
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.scripts[2] + 10, .value = tagValue("DEU "), .width = 4 }});
        defer fx.deinit();
        try expectRejected(.unsorted_records, try some((try fx.gsub()).script(2)));
    }
    { // X6
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.scripts[0], .value = 0 }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.missing_default_lang_sys, try some(l.script(0)));
        try expectRejected(.missing_default_lang_sys, try l.selectLookups(s4_request, .{}, &masks));
        try expectRejected(.missing_default_lang_sys, try l.selectLookups(s5_request, .{}, &masks));
    }
    { // X7
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.default_lang_sys[1].? + 4, .value = 0xFFFF }});
        defer fx.deinit();
        try expectRejected(.count_out_of_bounds, try selectS1(try fx.gsub(), &masks));
    }
    { // X8
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.features[1] + 2, .value = 0xFFFF }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.count_out_of_bounds, try selectS1(l, &masks));
        try expectRejected(.count_out_of_bounds, try some(l.feature(1)));
    }
    { // X9
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.scripts[1] + 2, .value = 0xFFFF }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.count_out_of_bounds, try some(l.script(1)));
        try expectRejected(.count_out_of_bounds, try selectS1(l, &masks));
    }
    { // X10
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.scripts[1] + 4 + 4, .value = 0xFFFF }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.offset_out_of_bounds, try some(l.script(1)));
        try expectRejected(.offset_out_of_bounds, try l.selectLookups(s2_request, .{}, &masks));
    }
    { // X11
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.feature_records[1] + 4, .value = 0 }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.null_offset, try some(l.feature(1)));
        try expectRejected(.null_offset, try selectS1(l, &masks));
    }
    { // X12
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.script_records[1] + 4, .value = 0 }});
        defer fx.deinit();
        const l = try fx.gsub();
        try expectRejected(.null_offset, try some(l.script(1)));
        try expectRejected(.null_offset, try selectS1(l, &masks));
    }
}

test "FP-0111 case 16: malformed Lookup tables and subtables are rejected" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    const at = g.at;
    { // Z1
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.lookups[0] + 4, .value = 0xFFFF }});
        defer fx.deinit();
        try expectRejected(.count_out_of_bounds, try some((try fx.gsub()).lookup(0)));
    }
    { // Z2
        var t = try lb.tMfs(gpa);
        defer t.deinit(gpa);
        try testing.expectEqualSlices(u8, &hex("0001 0010 0000"), t.bytes[t.bytes.len - 6 ..]);
        var fx = try Fixture.init(&.{.{ "GSUB".*, t.bytes }});
        defer fx.deinit();
        try expectRejected(.too_short, try some((try fx.gsub()).lookup(0)));
    }
    { // Z3
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.lookups[0] + 6, .value = 0 }});
        defer fx.deinit();
        try expectRejected(.null_offset, try some((try fx.gsub()).lookup(0)));
    }
    { // Z4
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.lookups[0] + 6, .value = 0xFFFF }});
        defer fx.deinit();
        try expectRejected(.offset_out_of_bounds, try some((try fx.gsub()).lookup(0)));
    }
    { // Z5
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.subtables[3][0] + 4, .value = 0x00010000, .width = 4 }});
        defer fx.deinit();
        try expectRejected(.offset_out_of_bounds, try some((try fx.gsub()).lookup(3)));
    }
    { // Z6
        for ([_]struct { u16, Defect }{ .{ 0xFFFF, .offset_out_of_bounds }, .{ 0, .null_offset } }) |row| {
            var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.subtables[0][0] + 2, .value = row[0] }});
            defer fx.deinit();
            const l0 = try valid(try some((try fx.gsub()).lookup(0)));
            try expectRejected(row[1], (try valid(try some(l0.subtable(0)))).coverage());
        }
    }
    { // Z7
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.subtables[2][0] + 6, .value = 0 }});
        defer fx.deinit();
        const l2 = try valid(try some((try fx.gsub()).lookup(2)));
        try expectRejected(.count_out_of_bounds, (try valid(try some(l2.subtable(0)))).coverage());
    }
    { // Z8
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.subtables[4][0] + 2, .value = 0 }});
        defer fx.deinit();
        const l4 = try valid(try some((try fx.gsub()).lookup(4)));
        try expectRejected(.count_out_of_bounds, (try valid(try some(l4.subtable(0)))).coverage());
    }
    { // Z9
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.lookups[0] + 6, .value = @intCast(g.bytes.len - 1 - at.lookups[0]) }});
        defer fx.deinit();
        const l0 = try valid(try some((try fx.gsub()).lookup(0)));
        try expectRejected(.too_short, try some(l0.subtable(0)));
    }
    { // Z10
        var fx = try edited("GSUB".*, g.bytes, &.{.{ .at = at.lookup_list + 2, .value = 0 }});
        defer fx.deinit();
        try expectRejected(.null_offset, try some((try fx.gsub()).lookup(0)));
    }
}

const liga_request: layout.Request = .{ .script = "DFLT".*, .features = &.{"liga".*} };

test "FP-0111 case 17: selection work is counted and limited" {
    {
        const h100 = try lb.h(gpa, 100);
        defer gpa.free(h100);
        var fx = try Fixture.init(&.{.{ "GSUB".*, h100 }});
        defer fx.deinit();
        const l = try fx.gsub();
        var masks: [1]u64 = undefined;
        _ = try valid(try l.selectLookups(liga_request, .{ .max_work = 10_100 }, &masks));
        try testing.expectEqual(@as(u64, 0x1), masks[0]);
        try testing.expectEqual(@as(u32, 10_100), layout.work);
        try testing.expect(try l.selectLookups(liga_request, .{ .max_work = 10_099 }, &masks) == .limit_exceeded);
        try testing.expectEqual(@as(u32, 10_099), layout.work);
    }
    {
        var g = try lb.g(gpa);
        defer g.deinit(gpa);
        var fx = try Fixture.init(&.{.{ "GSUB".*, g.bytes }});
        defer fx.deinit();
        const l = try fx.gsub();
        var masks: [13]u64 = undefined;
        _ = try valid(try l.selectLookups(s1_request, .{ .max_work = 7 }, &masks));
        try expectMasks(&masks, &s1_masks);
        try testing.expect(try l.selectLookups(s1_request, .{ .max_work = 6 }, &masks) == .limit_exceeded);
    }
    {
        const h30000 = try lb.h(gpa, 30000);
        defer gpa.free(h30000);
        var fx = try Fixture.init(&.{.{ "GSUB".*, h30000 }});
        defer fx.deinit();
        var masks: [1]u64 = undefined;
        try testing.expect(try (try fx.gsub()).selectLookups(liga_request, .{}, &masks) == .limit_exceeded);
        try testing.expectEqual(@as(u32, 1 << 20), layout.work);
    }
}

test "FP-0111 case 18: GDEF glyph classes, mark attachment classes, mark glyph sets, and ligature carets" {
    var fx = try Fixture.init(&.{.{ "GDEF".*, &lb.f_gdef }});
    defer fx.deinit();
    const gdef = try fx.gdef();
    const classes = try valid(gdef.glyphClasses());
    for (0..4) |g| try testing.expectEqual(@as(u16, @intCast(g)), classes.class(@intCast(g)));
    try testing.expectEqual(@as(u16, 0), classes.class(0xFFFF));
    const marks = try valid(gdef.markAttachClasses());
    try testing.expectEqual(@as(u16, 2), marks.class(3));
    for (0..3) |g| try testing.expectEqual(@as(u16, 0), marks.class(@intCast(g)));
    const sets = try valid(gdef.markGlyphSets());
    try testing.expectEqual(@as(u16, 2), sets.count);
    try expectCoverage(try valid(try some(sets.set(0))), 1, &.{3});
    try expectCoverage(try valid(try some(sets.set(1))), 1, &.{});
    try testing.expect(sets.set(2) == null);
    const carets = try valid(gdef.ligatureCaretList());
    const lig = try valid(carets.carets(2));
    try testing.expectEqual(@as(u16, 3), lig.caret_count);
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .coordinate = 603 } }), lig.caret(0));
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .point = 13 } }), lig.caret(1));
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .coordinate_device = .{
        .coordinate = 1206,
        .device = .{ .unsupported_device = .{ .start_size = 12, .end_size = 17, .delta_format = 2 } },
    } } }), lig.caret(2));
    try testing.expect(lig.caret(3) == null);
    try testing.expect(carets.carets(1) == .not_covered);

    var plain = try Fixture.init(&.{});
    defer plain.deinit();
    const header = try plain.gdef();
    try testing.expect(header.glyphClasses() == .absent);
    try testing.expect(header.markAttachClasses() == .absent);
    try testing.expect(header.markGlyphSets() == .absent);
    try testing.expect(header.ligatureCaretList() == .absent);
}

test "FP-0111 case 19: the gdef Example 4 ligature carets follow the bytes" {
    var fx = try Fixture.init(&.{.{ "GDEF".*, &lb.f_gdef4 }});
    defer fx.deinit();
    const carets = try valid((try fx.gdef()).ligatureCaretList());
    const one = try valid(carets.carets(0x9F));
    try testing.expectEqual(@as(u16, 1), one.caret_count);
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .coordinate = 603 } }), one.caret(0));
    const two = try valid(carets.carets(0xA5));
    try testing.expectEqual(@as(u16, 2), two.caret_count);
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .coordinate = 603 } }), two.caret(0));
    try testing.expectEqual(@as(?layout.CaretStatus, .{ .valid = .{ .coordinate = 1206 } }), two.caret(1));
    try testing.expect(carets.carets(0xA0) == .not_covered);
}

fn editedGdef(edits: []const Edit) !Fixture {
    return edited("GDEF".*, &lb.f_gdef, edits);
}

fn caret2Device(fx: *const Fixture) !?layout.DeviceStatus {
    const lig = try valid((try valid((try fx.gdef()).ligatureCaretList())).carets(2));
    return switch (try valid(try some(lig.caret(2)))) {
        .coordinate_device => |cd| cd.device,
        else => error.TestUnexpectedResult,
    };
}

test "FP-0111 case 20: malformed GDEF subtables are rejected or unsupported" {
    { // Y1
        var fx = try Fixture.init(&.{.{ "GDEF".*, &lb.f_gdef2 }});
        defer fx.deinit();
        try expectRejected(.unsorted_records, (try fx.gdef()).glyphClasses());
    }
    { // Y2
        var fx = try editedGdef(&.{.{ .at = 44, .value = 2 }});
        defer fx.deinit();
        try expectUnsupportedVersion(2, (try fx.gdef()).markGlyphSets());
    }
    { // Y3
        var fx = try editedGdef(&.{.{ .at = 46, .value = 0x0100 }});
        defer fx.deinit();
        try expectRejected(.count_out_of_bounds, (try fx.gdef()).markGlyphSets());
    }
    { // Y4
        var fx = try editedGdef(&.{.{ .at = 48, .value = 0x00000100, .width = 4 }});
        defer fx.deinit();
        try expectRejected(.offset_out_of_bounds, try some((try valid((try fx.gdef()).markGlyphSets())).set(0)));
    }
    { // Y5
        var fx = try editedGdef(&.{.{ .at = 86, .value = 4 }});
        defer fx.deinit();
        const lig = try valid((try valid((try fx.gdef()).ligatureCaretList())).carets(2));
        try testing.expectEqual(@as(?layout.CaretStatus, .{ .unsupported_format = 4 }), lig.caret(0));
    }
    { // Y6
        var fx = try editedGdef(&.{.{ .at = 78, .value = 0x0100 }});
        defer fx.deinit();
        try expectRejected(.count_out_of_bounds, (try valid((try fx.gdef()).ligatureCaretList())).carets(2));
    }
    { // Y7
        var fx = try editedGdef(&.{ .{ .at = 100, .value = 0x0011 }, .{ .at = 102, .value = 0x000C } });
        defer fx.deinit();
        try expectRejected(.invalid_range, try some(try caret2Device(&fx)));
    }
    { // Y8
        var fx = try editedGdef(&.{.{ .at = 104, .value = 0x8000 }});
        defer fx.deinit();
        try testing.expectEqual(@as(?layout.DeviceStatus, .{ .unsupported_variation_index = .{ .outer = 12, .inner = 17 } }), try caret2Device(&fx));
    }
    { // Y9
        var fx = try editedGdef(&.{.{ .at = 68, .value = 0 }});
        defer fx.deinit();
        try expectRejected(.index_out_of_range, (try valid((try fx.gdef()).ligatureCaretList())).carets(2));
    }
    { // Y10
        var fx = try editedGdef(&.{.{ .at = 14, .value = 3 }});
        defer fx.deinit();
        try expectUnsupportedVersion(3, (try fx.gdef()).glyphClasses());
    }
    { // Y11
        var fx = try editedGdef(&.{.{ .at = 48, .value = 0, .width = 4 }});
        defer fx.deinit();
        try expectRejected(.null_offset, try some((try valid((try fx.gdef()).markGlyphSets())).set(0)));
    }
}

fn mix(h: *Wyhash, value: anytype) void {
    std.hash.autoHash(h, value);
}

/// Hashes the active tag of a status union and an integer or enum payload.
fn mixStatus(h: *Wyhash, status: anytype) void {
    mix(h, std.meta.activeTag(status));
    switch (status) {
        inline else => |payload| switch (@typeInfo(@TypeOf(payload))) {
            .int, .@"enum" => mix(h, payload),
            else => {},
        },
    }
}

/// The indices from 0 to `count` inclusive, so each walk also calls an accessor one past its count.
fn through(count: u32) u32 {
    return @min(count, 0xFFFF) + 1;
}

fn walkCoverage(h: *Wyhash, c: layout.Coverage) !void {
    mix(h, c.format);
    const count = c.glyphCount();
    mix(h, count);
    for (0..9) |g| {
        const i = c.index(@intCast(g));
        mix(h, i);
        if (i) |index| try testing.expect(index < count);
    }
    var it = c.iterator();
    var n: u32 = 0;
    while (it.next()) |g| {
        mix(h, g);
        n += 1;
        try testing.expect(n <= count);
    }
}

fn walkCoverageStatus(h: *Wyhash, status: font.TableStatus(layout.Coverage)) !void {
    mixStatus(h, status);
    if (status == .valid) try walkCoverage(h, status.valid);
}

fn walkLangSys(h: *Wyhash, status: font.TableStatus(layout.LangSys)) void {
    mixStatus(h, status);
    const ls = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, ls.required_feature);
    mix(h, ls.feature_index_count);
    for (0..through(ls.feature_index_count)) |k| mix(h, ls.featureIndex(@intCast(k)));
}

fn walkScript(h: *Wyhash, status: font.TableStatus(layout.Script)) void {
    mixStatus(h, status);
    const s = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, s.tag);
    mix(h, s.lang_sys_count);
    walkLangSys(h, s.defaultLangSys());
    for (0..through(s.lang_sys_count)) |j| {
        mix(h, s.langSysTag(@intCast(j)));
        if (s.langSys(@intCast(j))) |ls| walkLangSys(h, ls) else mix(h, @as(u8, 0xAA));
    }
}

fn walkFeature(h: *Wyhash, status: font.TableStatus(layout.Feature)) void {
    mixStatus(h, status);
    const f = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, f.tag);
    mix(h, f.params_offset);
    mix(h, f.lookup_index_count);
    for (0..through(f.lookup_index_count)) |k| mix(h, f.lookupIndex(@intCast(k)));
}

fn walkLookup(h: *Wyhash, status: layout.LookupStatus) !void {
    mixStatus(h, status);
    const l = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, l.lookup_type);
    mix(h, l.extension);
    mix(h, l.flag);
    mix(h, l.subtable_count);
    mix(h, l.mark_filtering_set);
    mix(h, [_]bool{ l.rightToLeft(), l.ignoreBaseGlyphs(), l.ignoreLigatures(), l.ignoreMarks(), l.useMarkFilteringSet() });
    mix(h, l.markAttachmentClass());
    for (0..through(l.subtable_count)) |k| {
        const s = l.subtable(@intCast(k)) orelse {
            mix(h, @as(u8, 0xAA));
            continue;
        };
        mixStatus(h, s);
        if (s == .valid) {
            mix(h, s.valid.format);
            try walkCoverageStatus(h, s.valid.coverage());
        }
    }
}

fn walkSelection(h: *Wyhash, l: layout.Layout, request: layout.Request) !void {
    const masks = try gpa.alloc(u64, l.lookupCount());
    defer gpa.free(masks);
    const status = l.selectLookups(request, .{}, masks) catch |err| {
        mix(h, @intFromError(err));
        return;
    };
    mixStatus(h, status);
    if (status == .valid) {
        const s = status.valid;
        mix(h, s.script);
        mix(h, s.lang_sys);
        mix(h, s.required_feature);
        mix(h, s.lookup_count);
        mix(h, s.feature_variations);
        var nonzero: u16 = 0;
        for (masks) |m| {
            mix(h, m);
            if (m != 0) nonzero += 1;
        }
        try testing.expectEqual(nonzero, s.lookup_count);
    }
}

const walk_requests = [_]layout.Request{
    .{ .script = "arab".*, .features = &.{ "ccmp".*, "init".*, "rlig".*, "liga".* } },
    .{ .script = "latn".*, .language = "TRK ".*, .features = &.{"liga".*} },
    .{ .script = "cyrl".*, .language = "ZZZ ".*, .features = &.{ "ccmp".*, "smcp".* } },
};

fn walkLayout(h: *Wyhash, l: layout.Layout) !void {
    mix(h, l.version);
    mix(h, l.kind);
    mix(h, l.feature_variations);
    mix(h, l.scriptCount());
    mix(h, l.featureCount());
    mix(h, l.lookupCount());
    for (0..through(l.scriptCount())) |i| {
        mix(h, l.scriptTag(@intCast(i)));
        if (l.script(@intCast(i))) |s| walkScript(h, s) else mix(h, @as(u8, 0xAA));
    }
    for (0..through(l.featureCount())) |i| {
        mix(h, l.featureTag(@intCast(i)));
        if (l.feature(@intCast(i))) |f| walkFeature(h, f) else mix(h, @as(u8, 0xAA));
    }
    for (0..through(l.lookupCount())) |i| {
        if (l.lookup(@intCast(i))) |s| try walkLookup(h, s) else mix(h, @as(u8, 0xAA));
    }
    for (walk_requests) |request| try walkSelection(h, l, request);
}

fn walkLayoutStatus(h: *Wyhash, status: font.TableStatus(layout.Layout)) !void {
    mixStatus(h, status);
    if (status == .valid) try walkLayout(h, status.valid);
}

fn mixDevice(h: *Wyhash, d: layout.DeviceStatus) void {
    mix(h, std.meta.activeTag(d));
    switch (d) {
        .rejected => |defect| mix(h, defect),
        .unsupported_device => |v| mix(h, [3]u16{ v.start_size, v.end_size, v.delta_format }),
        .unsupported_variation_index => |v| mix(h, [2]u16{ v.outer, v.inner }),
        .unsupported_format => |v| mix(h, v),
    }
}

fn walkCaret(h: *Wyhash, status: layout.CaretStatus) void {
    mixStatus(h, status);
    const v = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, std.meta.activeTag(v));
    switch (v) {
        .coordinate => |c| mix(h, c),
        .point => |p| mix(h, p),
        .coordinate_device => |cd| {
            mix(h, cd.coordinate);
            if (cd.device) |d| mixDevice(h, d) else mix(h, @as(u8, 0xAA));
        },
    }
}

fn walkLigGlyph(h: *Wyhash, lig: layout.LigGlyph) void {
    mix(h, lig.caret_count);
    for (0..through(lig.caret_count)) |k| {
        if (lig.caret(@intCast(k))) |c| walkCaret(h, c) else mix(h, @as(u8, 0xAA));
    }
}

fn walkClassDef(h: *Wyhash, status: font.TableStatus(layout.ClassDef)) void {
    mixStatus(h, status);
    if (status != .valid) return;
    mix(h, status.valid.format);
    for (0..9) |g| mix(h, status.valid.class(@intCast(g)));
}

fn walkMarkGlyphSets(h: *Wyhash, sets: layout.MarkGlyphSets) !void {
    mix(h, sets.count);
    for (0..through(sets.count)) |i| {
        if (sets.set(@intCast(i))) |s| try walkCoverageStatus(h, s) else mix(h, @as(u8, 0xAA));
    }
}

fn walkCarets(h: *Wyhash, list: layout.LigCaretList) void {
    for (0..9) |g| {
        const status = list.carets(@intCast(g));
        mixStatus(h, status);
        if (status == .valid) walkLigGlyph(h, status.valid);
    }
}

fn walkGdef(h: *Wyhash, status: font.TableStatus(layout.Gdef)) !void {
    mixStatus(h, status);
    const gdef = switch (status) {
        .valid => |v| v,
        else => return,
    };
    mix(h, gdef.version);
    mix(h, [4]u16{ gdef.glyph_class_def, gdef.attach_list, gdef.lig_caret_list, gdef.mark_attach_class_def });
    mix(h, gdef.mark_glyph_sets_def);
    mix(h, gdef.item_var_store);
    walkClassDef(h, gdef.glyphClasses());
    walkClassDef(h, gdef.markAttachClasses());
    const sets = gdef.markGlyphSets();
    mixStatus(h, sets);
    if (sets == .valid) try walkMarkGlyphSets(h, sets.valid);
    const carets = gdef.ligatureCaretList();
    mixStatus(h, carets);
    if (carets == .valid) walkCarets(h, carets.valid);
}

/// Visits every structure and method of the font's GSUB, GPOS, and GDEF tables and returns a digest of all results.
fn walk(f: *const font.Font) !u64 {
    var h = Wyhash.init(0);
    try walkLayoutStatus(&h, f.gsub());
    try walkLayoutStatus(&h, f.gpos());
    try walkGdef(&h, f.gdef());
    return h.final();
}

fn walkTwice(bytes: []const u8) !void {
    const f = try font.parse(bytes, .{ .checksums = .report });
    try testing.expectEqual(try walk(&f), try walk(&f));
}

fn tableLength(bytes: []const u8, tag: Tag) u32 {
    return builder.readU32(bytes, builder.recordPosition(bytes, tag) + 12);
}

/// Every truncation and every single-byte change to `tag` in `B_TT` with `table`.
fn robustness(tag: Tag, table: []const u8) !void {
    var fx = try Fixture.init(&.{.{ tag, table }});
    defer fx.deinit();
    try walkTwice(fx.bytes);
    const copy = try gpa.dupe(u8, fx.bytes);
    defer gpa.free(copy);
    for (0..table.len) |len| {
        builder.setRecord(copy, tag, .length, @intCast(len));
        try walkTwice(copy);
    }
    builder.setRecord(copy, tag, .length, @intCast(table.len));
    const start = builder.recordOffset(copy, tag);
    for (start..start + table.len) |at| {
        const original = copy[at];
        for ([_]u8{ 0x00, 0xFF, original ^ 0x80 }) |value| {
            copy[at] = value;
            try walkTwice(copy);
        }
        copy[at] = original;
    }
}

test "FP-0111 case 21: every truncation and byte change of G, P, and F_GDEF parses and walks deterministically" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var p = try lb.p(gpa);
    defer p.deinit(gpa);
    try robustness("GSUB".*, g.bytes);
    try robustness("GPOS".*, p.bytes);
    try robustness("GDEF".*, &lb.f_gdef);
}

/// The handles that case 22 takes from pristine G and F_GDEF before it changes the font bytes.
const Handles = struct {
    gsub: layout.Layout,
    script: layout.Script,
    lang_sys: layout.LangSys,
    feature: layout.Feature,
    lookup: layout.Lookup,
    subtable: layout.Subtable,
    coverage: layout.Coverage,
    gdef: layout.Gdef,
    glyph_classes: layout.ClassDef,
    mark_classes: layout.ClassDef,
    sets: layout.MarkGlyphSets,
    carets: layout.LigCaretList,
    lig: layout.LigGlyph,

    fn take(f: *const font.Font) !Handles {
        const gsub = try valid(f.gsub());
        const script = try valid(try some(gsub.script(1)));
        const lookup = try valid(try some(gsub.lookup(3)));
        const subtable = try valid(try some(lookup.subtable(0)));
        const gdef = try valid(f.gdef());
        const carets = try valid(gdef.ligatureCaretList());
        return .{
            .gsub = gsub,
            .script = script,
            .lang_sys = try valid(script.defaultLangSys()),
            .feature = try valid(try some(gsub.feature(1))),
            .lookup = lookup,
            .subtable = subtable,
            .coverage = try valid(subtable.coverage()),
            .gdef = gdef,
            .glyph_classes = try valid(gdef.glyphClasses()),
            .mark_classes = try valid(gdef.markAttachClasses()),
            .sets = try valid(gdef.markGlyphSets()),
            .carets = carets,
            .lig = try valid(carets.carets(2)),
        };
    }

    fn exercise(self: *const Handles) !void {
        var h = Wyhash.init(0);
        try walkLayout(&h, self.gsub);
        var masks: [13]u64 = undefined;
        mixStatus(&h, try selectS1(self.gsub, &masks));
        walkScript(&h, .{ .valid = self.script });
        walkLangSys(&h, .{ .valid = self.lang_sys });
        walkFeature(&h, .{ .valid = self.feature });
        try walkLookup(&h, .{ .valid = self.lookup });
        try walkCoverageStatus(&h, self.subtable.coverage());
        try walkCoverage(&h, self.coverage);
        try walkGdef(&h, .{ .valid = self.gdef });
        walkClassDef(&h, .{ .valid = self.glyph_classes });
        walkClassDef(&h, .{ .valid = self.mark_classes });
        try walkMarkGlyphSets(&h, self.sets);
        walkCarets(&h, self.carets);
        walkLigGlyph(&h, self.lig);
        _ = h.final();
    }
};

test "FP-0111 case 22: handles taken before the font bytes change never panic or read outside the font" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var fx = try Fixture.init(&.{ .{ "GSUB".*, g.bytes }, .{ "GDEF".*, &lb.f_gdef } });
    defer fx.deinit();
    const handles = try Handles.take(&fx.f);
    try handles.exercise();
    for ([_]Tag{ "GSUB".*, "GDEF".* }) |tag| {
        const start = builder.recordOffset(fx.bytes, tag);
        const table = fx.bytes[start..][0..tableLength(fx.bytes, tag)];
        for (table) |*byte| {
            const original = byte.*;
            byte.* = 0xFF;
            try handles.exercise();
            byte.* = original;
        }
        const saved = try gpa.dupe(u8, table);
        defer gpa.free(saved);
        @memset(table, 0xFF);
        try handles.exercise();
        @memcpy(table, saved);
    }
}

const StackRun = struct {
    h100: layout.SelectionStatus = .limit_exceeded,
    digests: [3]u64 = @splat(0),
    h30000: layout.SelectionStatus = .{ .rejected = .too_short },
    work: u32 = 0,
    failure: ?anyerror = null,
};

fn walkFixture(tag: Tag, table: []const u8) !u64 {
    var fx = try Fixture.init(&.{.{ tag, table }});
    defer fx.deinit();
    return walk(&fx.f);
}

fn selectH(n: u16, limits: layout.SelectionLimits) !layout.SelectionStatus {
    const table = try lb.h(gpa, n);
    defer gpa.free(table);
    var fx = try Fixture.init(&.{.{ "GSUB".*, table }});
    defer fx.deinit();
    var masks: [1]u64 = undefined;
    return (try fx.gsub()).selectLookups(liga_request, limits, &masks);
}

fn stackRun(run: *StackRun, g: []const u8, p: []const u8) !void {
    run.h100 = try selectH(100, .{ .max_work = 10_099 });
    if (run.h100 != .limit_exceeded) return;
    run.digests = .{ try walkFixture("GSUB".*, g), try walkFixture("GPOS".*, p), try walkFixture("GDEF".*, &lb.f_gdef) };
    run.h30000 = try selectH(30000, .{});
    run.work = layout.work;
}

fn onSmallStack(run: *StackRun, g: []const u8, p: []const u8) void {
    stackRun(run, g, p) catch |err| {
        run.failure = err;
    };
}

test "FP-0111 case 23: selection and the walk run on a 256 KiB stack" {
    var g = try lb.g(gpa);
    defer g.deinit(gpa);
    var p = try lb.p(gpa);
    defer p.deinit(gpa);
    var run: StackRun = .{};
    const thread = try std.Thread.spawn(.{ .stack_size = 256 * 1024 }, onSmallStack, .{ &run, g.bytes, p.bytes });
    thread.join();
    if (run.failure) |err| return err;
    try testing.expect(run.h100 == .limit_exceeded);
    const expected = [3]u64{ try walkFixture("GSUB".*, g.bytes), try walkFixture("GPOS".*, p.bytes), try walkFixture("GDEF".*, &lb.f_gdef) };
    try testing.expectEqual(expected, run.digests);
    try testing.expect(run.h30000 == .limit_exceeded);
    try testing.expectEqual(@as(u32, 1 << 20), run.work);
}

fn isAllocator(comptime T: type) bool {
    const A = std.mem.Allocator;
    return T == A or T == ?A or T == *A or T == *const A;
}

/// The number of public functions of `C`, and of each public container type that `C` declares when `nested`,
/// after checking that none of them takes an allocator.
fn checkFunctions(comptime C: type, comptime nested: bool) usize {
    const names = switch (@typeInfo(C)) {
        .@"struct" => |s| s.decl_names,
        .@"union" => |u| u.decl_names,
        .@"enum" => |e| e.decl_names,
        else => return 0,
    };
    var count: usize = 0;
    for (names) |name| {
        const T = @TypeOf(@field(C, name));
        if (@typeInfo(T) == .@"fn") {
            for (@typeInfo(T).@"fn".param_types) |param| {
                if (param) |P| {
                    if (isAllocator(P)) @compileError(@typeName(C) ++ "." ++ name ++ " takes an allocator");
                }
            }
            count += 1;
        } else if (T == type and nested) {
            count += checkFunctions(@field(C, name), false);
        }
    }
    return count;
}

test "FP-0111 case 24: no function of font.layout or of its public types takes an allocator" {
    const count = comptime checkFunctions(layout, true);
    // The five parse functions and the 34 public methods of Layout, Script, LangSys, Feature, Lookup, Subtable, Coverage,
    // CoverageIterator, ClassDef, Gdef, MarkGlyphSets, LigCaretList, and LigGlyph, so the check never visits an empty set.
    try testing.expectEqual(@as(usize, 39), count);
}
