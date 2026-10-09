//! FP-0013 revision 1 cases 50, 51, and 52: the cmap work bound and accessors that tolerate changed bytes and bad indexes.

const std = @import("std");
const testing = std.testing;
const font = @import("fairpane").font;
const builder = @import("sfnt_builder.zig");

const gpa = testing.allocator;
const writeU16 = builder.writeU16;
const writeU32 = builder.writeU32;

/// Builds B_TT with `cmap` in place of its cmap table.
fn ttWithCmap(cmap: []const u8) ![]u8 {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    try set.put("cmap".*, cmap);
    return set.build(&.{}, &.{});
}

/// A cmap with `cheap` records (0, 0) to (0, cheap - 1), each naming its own 10-byte format 6 subtable with no entries,
/// then `shared` records (3, 1) to (3, shared) that all name one B_TT format 4 subtable.
/// The cmap has `cheap + 1` distinct subtable offsets when `shared` is nonzero.
fn distinctSubtablesCmap(cheap: usize, shared: usize) ![]u8 {
    const f4 = try builder.ttFormat4(gpa);
    defer gpa.free(f4);
    var w: builder.Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    const records = cheap + shared;
    try w.u16_(0);
    try w.u16_(@intCast(records));
    const first: u32 = @intCast(4 + 8 * records);
    for (0..cheap) |e| {
        try w.u16_(0);
        try w.u16_(@intCast(e));
        try w.u32_(first + 10 * @as(u32, @intCast(e)));
    }
    const shared_offset = first + 10 * @as(u32, @intCast(cheap));
    for (0..shared) |e| {
        try w.u16_(3);
        try w.u16_(@intCast(1 + e));
        try w.u32_(shared_offset);
    }
    for (0..cheap) |_| {
        try w.u16_(6); // format
        try w.u16_(10); // length
        try w.u16_(0); // language
        try w.u16_(0); // firstCode
        try w.u16_(0); // entryCount
    }
    try w.raw(f4);
    return w.finish();
}

test "FP-0013 case 50: a cmap with 513 distinct valid subtables returns InvalidCmap, and 512 parse" {
    {
        // 511 format 6 subtables and the format 4 subtable: 512 distinct offsets fill the validated set exactly.
        const cmap = try distinctSubtablesCmap(511, 1);
        defer gpa.free(cmap);
        const bytes = try ttWithCmap(cmap);
        defer gpa.free(bytes);
        const f = try font.parse(bytes, .{ .checksums = .reject });
        try testing.expectEqual(@as(u16, 512), f.cmapSubtableCount());
        try testing.expectEqual(font.CmapSelection{ .platform_id = 3, .encoding_id = 1, .format = 4 }, f.unicodeCmap());
        try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x41));
    }
    {
        // 512 format 6 subtables fill the set, so the 513th distinct offset, a valid format 4 subtable, is rejected.
        const cmap = try distinctSubtablesCmap(512, 1);
        defer gpa.free(cmap);
        const bytes = try ttWithCmap(cmap);
        defer gpa.free(bytes);
        try testing.expectError(error.InvalidCmap, font.parse(bytes, .{}));
    }
    {
        // The review's construction: a full set, then many records that repeat one costly subtable.
        const cmap = try distinctSubtablesCmap(512, 4096);
        defer gpa.free(cmap);
        const bytes = try ttWithCmap(cmap);
        defer gpa.free(bytes);
        try testing.expectError(error.InvalidCmap, font.parse(bytes, .{}));
    }
}

/// A cmap with `records` records (0, 0) to (0, records - 1), all naming one format 4 subtable.
/// Its 256 segments [256k, 256k + 255] each read the same 256-entry glyphIdArray, so one validation reads 65536 entries.
fn sharedFormat4Cmap(records: usize) ![]u8 {
    var segments: [256]builder.Segment = undefined;
    for (&segments, 0..) |*s, k| s.* = .{
        .start = @intCast(256 * k),
        .end = @intCast(256 * k + 255),
        .delta = 0,
        // idRangeOffset counts from its own position to the array, which starts right after the last idRangeOffset.
        .range_offset = @intCast(2 * (256 - k)),
    };
    var glyph_ids: [256]u16 = @splat(0);
    glyph_ids[0x20] = 1;
    glyph_ids[0x41] = 2;
    const f4 = try builder.format4(gpa, &segments, &glyph_ids);
    defer gpa.free(f4);
    var w: builder.Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(0);
    try w.u16_(@intCast(records));
    const offset: u32 = @intCast(4 + 8 * records);
    for (0..records) |e| {
        try w.u16_(0);
        try w.u16_(@intCast(e));
        try w.u32_(offset);
    }
    try w.raw(f4);
    return w.finish();
}

test "FP-0013 case 51: 65535 records that share one costly format 4 subtable parse with one validation" {
    const cmap = try sharedFormat4Cmap(65535);
    defer gpa.free(cmap);
    const bytes = try ttWithCmap(cmap);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    try testing.expectEqual(@as(u16, 65535), f.cmapSubtableCount());
    try testing.expectEqual(font.CmapSelection{ .platform_id = 0, .encoding_id = 3, .format = 4 }, f.unicodeCmap());
    try testing.expectEqual(@as(u16, 1), f.glyphIndex(0x20));
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x41));
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x141));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x42));
    // The counter exists only in test builds.
    try testing.expectEqual(@as(u32, 1), f.cmap_table.validations);
}

test "FP-0013 case 52: accessors given an index out of range return null or an error" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    try testing.expect(f.tableRecord(12) != null);
    try testing.expectEqual(@as(?font.TableRecord, null), f.tableRecord(13));
    try testing.expectEqual(@as(?font.TableRecord, null), f.tableRecord(0xFFFF));
    try testing.expect(f.cmapSubtable(2) != null);
    try testing.expectEqual(@as(?font.CmapSubtable, null), f.cmapSubtable(3));
    try testing.expectEqual(@as(?font.CmapSubtable, null), f.cmapSubtable(0xFFFF));
    try testing.expectError(error.GlyphOutOfRange, f.advance(4));
    try testing.expectError(error.GlyphOutOfRange, f.glyphHeader(0xFFFF));
    const name = f.name().valid;
    try testing.expect(name.record(1) != null);
    try testing.expectEqual(@as(?font.NameRecord, null), name.record(2));
    try testing.expectEqual(@as(?font.NameRecord, null), name.record(0xFFFF));
    const gsub = f.gsub().valid;
    try testing.expectEqualStrings("latn", &gsub.scriptTag(1).?);
    try testing.expectEqual(@as(?[4]u8, null), gsub.scriptTag(2));
    try testing.expectEqual(@as(?[4]u8, null), gsub.featureTag(0));
    try testing.expectEqual(@as(?[4]u8, null), gsub.featureTag(0xFFFF));
}

/// The table offset of `tag` in a built font.
fn tableOffset(bytes: []const u8, tag: *const [4]u8) usize {
    return builder.recordOffset(bytes, tag.*);
}

fn putU16(bytes: []u8, at: usize, value: u16) void {
    writeU16(bytes[at..][0..2], value);
}

fn putU32(bytes: []u8, at: usize, value: u32) void {
    writeU32(bytes[at..][0..4], value);
}

test "FP-0013 case 52: a changed directory record length makes findTable return null" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    builder.setRecord(bytes, "glyf".*, .length, 0xFFFFFFF0);
    try testing.expectEqual(@as(?[]const u8, null), f.findTable("glyf".*));
    try testing.expect(f.findTable("head".*) != null);
    try testing.expectEqual(@as(u32, 0xFFFFFFF0), f.tableRecord(5).?.length);
    // Parsed tables keep the ranges that parse checked.
    try testing.expectEqual(@as(i16, 1), (try f.glyphHeader(0)).?.number_of_contours);
}

test "FP-0013 case 52: a changed cmap encoding record offset makes cmapSubtable return null" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    putU32(bytes, tableOffset(bytes, "cmap") + 4 + 4, 0xFFFFFFF0);
    try testing.expectEqual(@as(?font.CmapSubtable, null), f.cmapSubtable(0));
    try testing.expectEqual(font.CmapSubtable{ .platform_id = 3, .encoding_id = 1, .format = 4, .language = 0 }, f.cmapSubtable(1).?);
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x41));
}

test "FP-0013 case 52: a changed format 12 group count makes glyphIndex return glyph 0" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    putU32(bytes, tableOffset(bytes, "cmap") + builder.tt_cmap_format12_offset + 12, 0xFFFFFFFF);
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x41));
    try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x1F600));
}

test "FP-0013 case 52: a changed format 12 start glyph past numGlyphs makes glyphIndex return glyph 0" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    const group2_glyph = tableOffset(bytes, "cmap") + builder.tt_cmap_format12_offset + 16 + 12 * 2 + 8;
    for ([_]u32{ 0xFFFFFFFF, 0x10000, 4 }) |glyph| {
        putU32(bytes, group2_glyph, glyph);
        try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x1F600));
    }
    putU32(bytes, group2_glyph, 3);
    try testing.expectEqual(@as(u16, 3), f.glyphIndex(0x1F600));
}

test "FP-0013 case 52: a changed format 4 segment count or idRangeOffset makes glyphIndex return glyph 0" {
    // B_CFF selects its only subtable, a (3, 1) format 4 subtable at cmap offset 12 with two segments.
    const subtable = 12;
    {
        const bytes = try builder.bCff(gpa);
        defer gpa.free(bytes);
        const f = try font.parse(bytes, .{ .checksums = .reject });
        try testing.expectEqual(@as(u16, 1), f.glyphIndex(0x41));
        putU16(bytes, tableOffset(bytes, "cmap") + subtable + 6, 0xFFFE); // segCountX2
        try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x41));
        try testing.expectEqual(@as(u16, 0), f.glyphIndex(0xFFFF));
    }
    {
        const bytes = try builder.bCff(gpa);
        defer gpa.free(bytes);
        const f = try font.parse(bytes, .{ .checksums = .reject });
        putU16(bytes, tableOffset(bytes, "cmap") + subtable + 16 + 6 * 2, 0xFFFE); // idRangeOffset of segment 0
        try testing.expectEqual(@as(u16, 0), f.glyphIndex(0x41));
    }
}

test "FP-0013 case 52: changed loca entries make glyphHeader return InvalidGlyph" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    const loca = tableOffset(bytes, "loca");
    putU16(bytes, loca + 2 * 3, 10); // entry 3 below entry 2, so glyph 2 ends before it starts
    try testing.expectError(error.InvalidGlyph, f.glyphHeader(2));
    putU16(bytes, loca + 2 * 4, 0xFFFF); // entry 4 past the glyf table
    try testing.expectError(error.InvalidGlyph, f.glyphHeader(3));
    try testing.expectEqual(@as(i16, 1), (try f.glyphHeader(0)).?.number_of_contours);
}

test "FP-0013 case 52: a changed name record makes record and find return null" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    const name = f.name().valid;
    putU16(bytes, tableOffset(bytes, "name") + 6 + 8, 0xFFFF); // length of record 0
    try testing.expectEqual(@as(?font.NameRecord, null), name.record(0));
    try testing.expectEqual(@as(?[]const u8, null), name.find(3, 1, 0x409, 1));
    try testing.expectEqual(@as(u16, 2), name.record(1).?.name_id);
    try testing.expectEqual(@as(u16, 2), name.count());
}

test "FP-0013 case 52: a changed GSUB script count leaves the parsed counts and returns null past them" {
    const bytes = try builder.bTt(gpa);
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{ .checksums = .reject });
    const gsub = f.gsub().valid;
    const at = tableOffset(bytes, "GSUB");
    putU16(bytes, at + builder.layoutOffsets(bytes[at..]).script_list, 0xFFFF);
    try testing.expectEqual(@as(u16, 2), gsub.scriptCount());
    try testing.expectEqual(@as(?[4]u8, null), gsub.scriptTag(0x100));
    try testing.expectEqualStrings("DFLT", &gsub.scriptTag(0).?);
}

/// Calls every accessor with every index, plus indexes past each count, and checks the documented result ranges.
fn exercise(f: *const font.Font, before: anytype) !void {
    _ = f.outline();
    _ = f.integrity();
    _ = f.head();
    _ = f.hhea();
    _ = f.maxp();
    _ = f.cff();
    _ = f.unicodeCmap();
    var i: u32 = 0;
    while (i <= @as(u32, f.tableCount()) + 1) : (i += 1) _ = f.tableRecord(@intCast(i));
    for (std.meta.tags(font.KnownTag)) |tag| _ = f.findTable(@tagName(tag)[0..4].*);
    i = 0;
    while (i <= @as(u32, f.cmapSubtableCount()) + 1) : (i += 1) _ = f.cmapSubtable(@intCast(i));
    for ([_]u21{ 0, 0x20, 0x41, 0x42, 0xFFFF, 0x1F600, 0x10FFFF }) |cp| {
        const glyph = f.glyphIndex(cp);
        try testing.expect(glyph == 0 or glyph < f.glyphCount());
    }
    i = 0;
    while (i <= @as(u32, f.glyphCount()) + 1) : (i += 1) {
        _ = f.advance(@intCast(i)) catch {};
        _ = f.glyphHeader(@intCast(i)) catch {};
    }
    _ = f.os2();
    _ = f.post();
    _ = f.gdef();
    try names(f.name());
    try layouts(f.gsub());
    try layouts(f.gpos());
    try names(before.name);
    try layouts(before.gsub);
    try layouts(before.gpos);
}

fn names(status: font.TableStatus(font.Name)) !void {
    const name = switch (status) {
        .valid => |n| n,
        else => return,
    };
    var i: u32 = 0;
    while (i <= @as(u32, name.count()) + 1) : (i += 1) _ = name.record(@intCast(i));
    _ = name.find(3, 1, 0x409, 1);
}

fn layouts(status: font.TableStatus(font.Layout)) !void {
    const layout = switch (status) {
        .valid => |l| l,
        else => return,
    };
    var i: u32 = 0;
    while (i <= @as(u32, layout.scriptCount()) + 1) : (i += 1) _ = layout.scriptTag(@intCast(i));
    i = 0;
    while (i <= @as(u32, layout.featureCount()) + 1) : (i += 1) _ = layout.featureTag(@intCast(i));
    _ = layout.lookupCount();
}

test "FP-0013 case 52: every single-byte change after parse leaves every accessor in range" {
    for ([_]*const fn (std.mem.Allocator) anyerror![]u8{ builder.bTt, builder.bCff }) |make| {
        const bytes = try make(gpa);
        defer gpa.free(bytes);
        const f = try font.parse(bytes, .{ .checksums = .reject });
        const before = .{ .name = f.name(), .gsub = f.gsub(), .gpos = f.gpos() };
        for (bytes, 0..) |original, at| {
            for ([_]u8{ 0x00, 0x80, 0xFF, original ^ 0x01 }) |value| {
                bytes[at] = value;
                try exercise(&f, before);
            }
            bytes[at] = original;
        }
    }
}
