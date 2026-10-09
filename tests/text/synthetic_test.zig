//! FP-0013 cases 15, 16, and 17: the synthetic fonts B_TT and B_CFF.

const std = @import("std");
const testing = std.testing;
const font = @import("fairpane").font;
const builder = @import("sfnt_builder.zig");

const gpa = testing.allocator;

test "FP-0013 case 15: B_TT builds deterministically with a whole-file sum of 0xB1B0AFBA and clean integrity" {
    const first = try builder.bTt(gpa);
    defer gpa.free(first);
    const second = try builder.bTt(gpa);
    defer gpa.free(second);
    try testing.expectEqualSlices(u8, first, second);
    try testing.expectEqual(@as(u32, 0xB1B0AFBA), builder.checksum(first));
    for ([_]font.ParseOptions{ .{}, .{ .checksums = .reject } }) |options| {
        const f = try font.parse(first, options);
        const integrity = f.integrity();
        try testing.expect(integrity.clean());
        try testing.expectEqual(@as(usize, 0), integrity.mismatched.count());
        try testing.expectEqual(@as(u32, 0), integrity.unknown_mismatches);
        try testing.expect(integrity.head_adjustment_ok);
    }
}

fn utf16be(comptime ascii: []const u8) [ascii.len * 2]u8 {
    var out: [ascii.len * 2]u8 = undefined;
    for (ascii, 0..) |c, i| {
        out[2 * i] = 0;
        out[2 * i + 1] = c;
    }
    return out;
}

test "FP-0013 case 16: B_TT maps, measures, and describes its glyphs and optional tables" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    try testing.expectEqual(font.Outline.truetype, f.outline());
    try testing.expectEqual(@as(u16, 13), f.tableCount());
    try testing.expectEqual(@as(u16, 4), f.glyphCount());

    try testing.expectEqual(@as(u16, 1), f.glyphIndex(0x0020));
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x0041));
    try testing.expectEqual(@as(u16, 3), f.glyphIndex(0x1F600));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x0042));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0xD800));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x110000));
    try testing.expectEqual(font.CmapSelection{ .platform_id = 3, .encoding_id = 10, .format = 12 }, f.unicodeCmap());
    try testing.expectEqual(@as(u16, 3), f.cmapSubtableCount());
    try testing.expectEqual(font.CmapSubtable{ .platform_id = 0, .encoding_id = 3, .format = 4, .language = 0 }, f.cmapSubtable(0).?);
    try testing.expectEqual(font.CmapSubtable{ .platform_id = 3, .encoding_id = 1, .format = 4, .language = 0 }, f.cmapSubtable(1).?);
    try testing.expectEqual(font.CmapSubtable{ .platform_id = 3, .encoding_id = 10, .format = 12, .language = 0 }, f.cmapSubtable(2).?);

    const metrics = [_]font.HMetric{ .{ .advance = 500, .lsb = 50 }, .{ .advance = 250, .lsb = 0 }, .{ .advance = 600, .lsb = 10 }, .{ .advance = 600, .lsb = 10 } };
    for (metrics, 0..) |m, glyph| try testing.expectEqual(m, try f.advance(@intCast(glyph)));
    try testing.expectError(error.GlyphOutOfRange, f.advance(4));

    try testing.expectEqual(font.GlyphHeader{ .number_of_contours = 1, .x_min = 50, .y_min = 0, .x_max = 450, .y_max = 700 }, (try f.glyphHeader(0)).?);
    try testing.expectEqual(@as(?font.GlyphHeader, null), try f.glyphHeader(1));
    try testing.expectEqual(font.GlyphHeader{ .number_of_contours = 1, .x_min = 10, .y_min = 0, .x_max = 590, .y_max = 700 }, (try f.glyphHeader(2)).?);
    try testing.expectEqual(@as(i16, -1), (try f.glyphHeader(3)).?.number_of_contours);
    try testing.expectError(error.GlyphOutOfRange, f.glyphHeader(4));

    const head = f.head();
    try testing.expectEqual(builder.units_per_em, head.units_per_em);
    try testing.expectEqual([4]i16{ head.x_min, head.y_min, head.x_max, head.y_max }, builder.tt_bbox);
    try testing.expectEqual(@as(i16, 0), head.index_to_loc_format);
    const hhea = f.hhea();
    try testing.expectEqual(builder.ascender, hhea.ascender);
    try testing.expectEqual(builder.descender, hhea.descender);
    try testing.expectEqual(builder.line_gap, hhea.line_gap);
    try testing.expectEqual(builder.advance_width_max, hhea.advance_width_max);
    try testing.expectEqual(@as(u16, 3), hhea.number_of_h_metrics);
    try testing.expectEqual(@as(u32, 0x00010000), f.maxp().version);

    const name = f.name().valid;
    try testing.expectEqual(@as(u16, 2), name.count());
    try testing.expectEqualSlices(u8, &utf16be(builder.name_family), name.find(3, 1, 0x409, 1).?);
    try testing.expectEqualSlices(u8, &utf16be(builder.name_subfamily), name.find(3, 1, 0x409, 2).?);
    try testing.expectEqual(@as(?[]const u8, null), name.find(3, 1, 0x409, 3));

    const os2 = f.os2().valid;
    try testing.expectEqual(builder.os2_version, os2.version);
    try testing.expectEqual(builder.os2_weight, os2.us_weight_class);
    const typo = os2.typo.?;
    try testing.expectEqual(builder.os2_typo, [3]i16{ typo.s_typo_ascender, typo.s_typo_descender, typo.s_typo_line_gap });
    try testing.expectEqual(builder.os2_win, [2]u16{ typo.us_win_ascent, typo.us_win_descent });
    try testing.expect(os2.v1 != null and os2.v2 != null and os2.v5 == null);

    const post = f.post().valid;
    try testing.expectEqual(@as(u32, 0x00030000), post.version);
    try testing.expectEqual(builder.post_underline_position, post.underline_position);
    try testing.expectEqual(builder.post_underline_thickness, post.underline_thickness);

    const gsub = f.gsub().valid;
    try testing.expectEqual(@as(u32, 0x00010000), gsub.version);
    try testing.expectEqual(@as(u16, 2), gsub.scriptCount());
    try testing.expectEqualStrings("DFLT", &gsub.scriptTag(0).?);
    try testing.expectEqualStrings("latn", &gsub.scriptTag(1).?);
    try testing.expectEqual(@as(u16, 0), gsub.featureCount());
    try testing.expectEqual(@as(u16, 0), gsub.lookupCount());
    const gpos = f.gpos().valid;
    try testing.expectEqual(@as(u16, 1), gpos.scriptCount());
    try testing.expectEqualStrings("latn", &gpos.scriptTag(0).?);
    try testing.expectEqual(@as(u16, 0), gpos.featureCount());
    try testing.expectEqual(@as(u16, 0), gpos.lookupCount());
    const gdef = f.gdef().valid;
    try testing.expectEqual(@as(u32, 0x00010000), gdef.version);
    try testing.expectEqual(font.Gdef{ .version = 0x00010000, .glyph_class_def = 0, .attach_list = 0, .lig_caret_list = 0, .mark_attach_class_def = 0, .mark_glyph_sets_def = null, .item_var_store = null }, gdef);
    try testing.expectEqual(@as(?font.Cff, null), f.cff());
}

test "FP-0013 case 17: B_CFF exposes its CFF table and maps U+0041" {
    const bytes = try builder.bCff(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    try testing.expectEqual(font.Outline.cff, f.outline());
    const cff = f.cff().?;
    try testing.expectEqualStrings(builder.cff_font_name, cff.name);
    try testing.expectEqual(@as(u16, 2), cff.charstrings_count);
    try testing.expect(!cff.cid_keyed);
    try testing.expectEqual(font.CmapSelection{ .platform_id = 3, .encoding_id = 1, .format = 4 }, f.unicodeCmap());
    try testing.expectEqual(@as(u16, 1), f.glyphIndex(0x41));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x42));
    try testing.expectError(error.NotTrueType, f.glyphHeader(0));
    try testing.expectEqual(font.HMetric{ .advance = 600, .lsb = 0 }, try f.advance(1));
    try testing.expectEqual(@as(u32, 0x00005000), f.maxp().version);
    try testing.expect(f.integrity().clean());
}
