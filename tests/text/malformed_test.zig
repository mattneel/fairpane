//! FP-0013 cases 18 through 40: malformed directories, required tables, and optional tables.

const std = @import("std");
const testing = std.testing;
const font = @import("fairpane").font;
const builder = @import("sfnt_builder.zig");
const TableSet = builder.TableSet;
const Defect = font.Defect;

const gpa = testing.allocator;
const writeU16 = builder.writeU16;
const writeU32 = builder.writeU32;
const readU16 = builder.readU16;

fn build(set: *const TableSet, extras: []const builder.Extra, overrides: []const builder.Override) ![]u8 {
    return set.build(extras, overrides);
}

fn expectParseError(expected: font.ParseError, set: *const TableSet, extras: []const builder.Extra, overrides: []const builder.Override) !void {
    const bytes = try build(set, extras, overrides);
    defer gpa.free(bytes);
    try testing.expectError(expected, font.parse(bytes, .{}));
}

fn expectTtError(expected: font.ParseError, overrides: []const builder.Override) !void {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    try expectParseError(expected, &set, &.{}, overrides);
}

fn u16At(table: []u8, at: usize) *[2]u8 {
    return table[at..][0..2];
}

fn u32At(table: []u8, at: usize) *[4]u8 {
    return table[at..][0..4];
}

fn numTables(bytes: []const u8) usize {
    return readU16(bytes, 4);
}

test "FP-0013 case 18: every proper prefix of B_TT and B_CFF fails, and a cut directory is Truncated" {
    for ([_]*const fn (std.mem.Allocator) anyerror![]u8{ builder.bTt, builder.bCff }) |make| {
        const bytes = try make(gpa);
        defer gpa.free(bytes);
        _ = try font.parse(bytes, .{ .checksums = .reject });
        const directory_end = 12 + 16 * numTables(bytes);
        for (0..bytes.len) |len| {
            const result = font.parse(bytes[0..len], .{});
            if (result) |_| {
                std.debug.print("prefix of {d} bytes parsed\n", .{len});
                return error.TestUnexpectedResult;
            } else |err| if (len < directory_end) try testing.expectEqual(error.Truncated, err);
        }
    }
}

test "FP-0013 case 19: numTables 0xFFFF on B_TT returns Truncated" {
    try expectTtError(error.Truncated, &.{.{ .num_tables = 0xFFFF }});
}

test "FP-0013 case 20: collection, WOFF, WOFF2, Type 1, and unknown sfnt versions are rejected by name" {
    try expectTtError(error.UnsupportedCollection, &.{.{ .sfnt_version = 0x74746366 }});
    try expectTtError(error.UnsupportedWoff, &.{.{ .sfnt_version = 0x774F4646 }});
    try expectTtError(error.UnsupportedWoff2, &.{.{ .sfnt_version = 0x774F4632 }});
    try expectTtError(error.UnsupportedSfntVersion, &.{.{ .sfnt_version = 0x74727565 }});
    try expectTtError(error.UnsupportedSfntVersion, &.{.{ .sfnt_version = 0x74797031 }});
    try expectTtError(error.UnknownSfntVersion, &.{.{ .sfnt_version = 0x12345678 }});
}

test "FP-0013 case 21: records past the end of the font return TableOutOfBounds" {
    {
        const bytes = try builder.bTt(gpa);
        defer gpa.free(bytes);
        const offset = builder.recordOffset(bytes, "glyf".*);
        builder.setRecord(bytes, "glyf".*, .length, @intCast(bytes.len - offset + 4));
        try testing.expectError(error.TableOutOfBounds, font.parse(bytes, .{}));
    }
    try expectTtError(error.TableOutOfBounds, &.{
        .{ .record = .{ .tag = "glyf".*, .field = .offset, .value = 0xFFFFFFF0 } },
        .{ .record = .{ .tag = "glyf".*, .field = .length, .value = 0x20 } },
    });
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    try expectParseError(error.TableOutOfBounds, &set, &.{.{ .tag = "zzzz".*, .offset = .past_end, .length = 4 }}, &.{});
}

test "FP-0013 case 22: a head offset moved by 2 returns MisalignedTable" {
    try expectTtError(error.MisalignedTable, &.{.{ .move_record = .{ .tag = "head".*, .delta = 2 } }});
}

test "FP-0013 case 23: unsorted and duplicate directory tags are rejected" {
    try expectTtError(error.UnsortedTableDirectory, &.{.{ .swap_records = .{ "cmap".*, "glyf".* } }});
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    const name_len: u32 = @intCast(set.get("name".*).len);
    try expectParseError(error.DuplicateTable, &set, &.{.{ .tag = "name".*, .after = "name".*, .offset = .{ .table = .{ .tag = "name".* } }, .length = name_len }}, &.{});
}

test "FP-0013 case 24: overlapping known tables are rejected, and an unknown table may overlap" {
    try expectTtError(error.OverlappingTables, &.{.{ .copy_offset = .{ .tag = "hhea".*, .from = "hmtx".* } }});
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    const bytes = try build(&set, &.{.{ .tag = "zzzz".*, .offset = .{ .table = .{ .tag = "glyf".* } }, .length = 16 }}, &.{});
    defer gpa.free(bytes);
    const f = try font.parse(bytes, .{});
    try testing.expectEqual(@as(u16, 14), f.tableCount());
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x41));
}

test "FP-0013 case 25: missing required tables and mixed outline formats are rejected" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.remove("hmtx".*);
        try expectParseError(error.MissingRequiredTable, &set, &.{}, &.{});
    }
    {
        var set = try builder.cffTables(gpa);
        defer set.deinit();
        set.remove("hmtx".*);
        try expectParseError(error.MissingRequiredTable, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.remove("loca".*);
        try expectParseError(error.MissingRequiredTable, &set, &.{}, &.{});
    }
    {
        var tt = try builder.ttTables(gpa);
        defer tt.deinit();
        var set = try builder.cffTables(gpa);
        defer set.deinit();
        try set.put("glyf".*, tt.get("glyf".*));
        try set.put("loca".*, tt.get("loca".*));
        try expectParseError(error.OutlineFormatMismatch, &set, &.{}, &.{});
    }
    {
        var set = try builder.cffTables(gpa);
        defer set.deinit();
        try set.put("CFF2".*, &.{ 2, 0, 5, 0, 0, 0, 0, 0 });
        try expectParseError(error.UnsupportedCff2, &set, &.{}, &.{});
    }
}

fn expectMismatched(integrity: font.Integrity, expected: []const font.KnownTag) !void {
    var set: std.EnumSet(font.KnownTag) = .empty;
    for (expected) |t| set.insert(t);
    try testing.expect(set.eql(integrity.mismatched));
    try testing.expectEqual(@as(u32, 0), integrity.unknown_mismatches);
}

test "FP-0013 case 26: checksum mismatches are reported or rejected" {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    {
        const bytes = try build(&set, &.{}, &.{.{ .flip_byte = .{ .tag = "name".*, .offset = 30 } }});
        defer gpa.free(bytes);
        const integrity = (try font.parse(bytes, .{})).integrity();
        try expectMismatched(integrity, &.{.name});
        try testing.expect(!integrity.head_adjustment_ok);
        try testing.expect(!integrity.clean());
        try testing.expectError(error.ChecksumMismatch, font.parse(bytes, .{ .checksums = .reject }));
    }
    {
        const bytes = try build(&set, &.{}, &.{.{ .checksum_adjustment = 0x12345678 }});
        defer gpa.free(bytes);
        const integrity = (try font.parse(bytes, .{})).integrity();
        try expectMismatched(integrity, &.{});
        try testing.expect(!integrity.head_adjustment_ok);
        try testing.expectError(error.ChecksumMismatch, font.parse(bytes, .{ .checksums = .reject }));
    }
    {
        const bytes = try build(&set, &.{}, &.{.{ .record = .{ .tag = "post".*, .field = .checksum, .value = 1 } }});
        defer gpa.free(bytes);
        const integrity = (try font.parse(bytes, .{})).integrity();
        try expectMismatched(integrity, &.{.post});
        try testing.expectError(error.ChecksumMismatch, font.parse(bytes, .{ .checksums = .reject }));
    }
}

test "FP-0013 case 27: malformed head tables return InvalidHead" {
    const Patch = struct { at: usize, value: u32, width: u8 };
    const patches = [_]Patch{
        .{ .at = 12, .value = 0, .width = 4 }, // magicNumber
        .{ .at = 18, .value = 15, .width = 2 }, // unitsPerEm
        .{ .at = 18, .value = 16385, .width = 2 },
        .{ .at = 50, .value = 2, .width = 2 }, // indexToLocFormat
        .{ .at = 0, .value = 2, .width = 2 }, // majorVersion
    };
    for (patches) |p| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        const head = set.get("head".*);
        if (p.width == 4) writeU32(u32At(head, p.at), p.value) else writeU16(u16At(head, p.at), @intCast(p.value));
        try expectParseError(error.InvalidHead, &set, &.{}, &.{});
    }
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    set.truncate("head".*, 53);
    try expectParseError(error.InvalidHead, &set, &.{}, &.{});
}

test "FP-0013 case 28: malformed maxp tables return InvalidMaxp" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("maxp".*, try builder.maxpV05(gpa, 4));
        try expectParseError(error.InvalidMaxp, &set, &.{}, &.{});
    }
    {
        var set = try builder.cffTables(gpa);
        defer set.deinit();
        try set.putOwned("maxp".*, try builder.maxpV1(gpa, 2));
        try expectParseError(error.InvalidMaxp, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU32(u32At(set.get("maxp".*), 0), 0x00020000);
        try expectParseError(error.InvalidMaxp, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("maxp".*), 4), 0);
        try expectParseError(error.InvalidMaxp, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.truncate("maxp".*, 31);
        try expectParseError(error.InvalidMaxp, &set, &.{}, &.{});
    }
}

test "FP-0013 case 29: malformed hhea and hmtx tables return InvalidHhea and InvalidHmtx" {
    for ([_]u16{ 0, 5 }) |count| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("hhea".*), 34), count);
        try expectParseError(error.InvalidHhea, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.truncate("hhea".*, 35);
        try expectParseError(error.InvalidHhea, &set, &.{}, &.{});
    }
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    set.truncate("hmtx".*, 13);
    try expectParseError(error.InvalidHmtx, &set, &.{}, &.{});
}

test "FP-0013 case 30: malformed loca tables fail parsing, and malformed glyph headers fail on access" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.truncate("loca".*, 9);
        try expectParseError(error.InvalidLoca, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("loca".*), 4), 0); // entry 2 below entry 1
        try expectParseError(error.InvalidLoca, &set, &.{}, &.{});
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("loca".*), 8), 41); // 82 bytes, past the 80-byte glyf
        try expectParseError(error.InvalidLoca, &set, &.{}, &.{});
    }
    const glyph2 = builder.tt_glyph_offsets[2];
    const edits = [_]struct { table: builder.Tag, at: usize, value: u16 }{
        .{ .table = "loca".*, .at = 6, .value = (glyph2 + 6) / 2 }, // a 6-byte glyph 2
        .{ .table = "glyf".*, .at = glyph2, .value = 2 }, // two contours whose end points 2 and 0 decrease
        .{ .table = "glyf".*, .at = glyph2 + 12, .value = 1000 }, // instructionLength past the glyph
    };
    for (edits) |edit| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get(edit.table), edit.at), edit.value);
        const bytes = try build(&set, &.{}, &.{});
        defer gpa.free(bytes);
        const f = try font.parse(bytes, .{});
        try testing.expectError(error.InvalidGlyph, f.glyphHeader(2));
        _ = try f.glyphHeader(0);
    }
}

/// Builds B_TT whose cmap is `cmap` and expects `expected`.
fn expectCmapError(expected: font.ParseError, cmap: []const u8) !void {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    try set.put("cmap".*, cmap);
    try expectParseError(expected, &set, &.{}, &.{});
}

const CmapEdit = struct { at: usize, value: u32, width: u8 = 2 };

fn expectCmapEdit(expected: font.ParseError, edits: []const CmapEdit) !void {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    const cmap = set.get("cmap".*);
    for (edits) |e| {
        if (e.width == 4) writeU32(u32At(cmap, e.at), e.value) else writeU16(u16At(cmap, e.at), @intCast(e.value));
    }
    try expectParseError(expected, &set, &.{}, &.{});
}

test "FP-0013 case 31: malformed cmap headers return InvalidCmap, and no Unicode subtable returns NoUnicodeCmap" {
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = 0, .value = 1 }});
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = 2, .value = 0xFFFF }});
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = 4 + 8 * 2 + 4, .value = 120, .width = 4 }});
    try expectCmapEdit(error.InvalidCmap, &.{ .{ .at = 4, .value = 3 }, .{ .at = 6, .value = 1 }, .{ .at = 12, .value = 0 }, .{ .at = 14, .value = 3 } });
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = builder.tt_cmap_format12_offset + 4, .value = 0x1000, .width = 4 }});

    const f4 = try builder.ttFormat4(gpa);
    defer gpa.free(f4);
    const symbol = try builder.cmapTable(gpa, &.{.{ .platform = 3, .encoding = 0, .subtable = 0 }}, &.{f4});
    defer gpa.free(symbol);
    try expectCmapError(error.NoUnicodeCmap, symbol);

    var format0: [262]u8 = undefined;
    @memset(&format0, 0);
    writeU16(format0[2..4], 262);
    format0[6 + 0x41] = 2;
    const mac = try builder.cmapTable(gpa, &.{.{ .platform = 1, .encoding = 0, .subtable = 0 }}, &.{&format0});
    defer gpa.free(mac);
    try expectCmapError(error.NoUnicodeCmap, mac);
}

test "FP-0013 case 32: malformed format 4 subtables return InvalidCmap even when unselected" {
    const base = builder.tt_cmap_format4_offset;
    const end = base + 14;
    const start = base + 22;
    const delta = base + 28;
    const range_offset = base + 34;
    const cases = [_][]const CmapEdit{
        &.{.{ .at = base + 6, .value = 0 }}, // segCountX2 0
        &.{.{ .at = base + 6, .value = 7 }}, // segCountX2 7
        &.{ .{ .at = end + 4, .value = 0xFFFE }, .{ .at = start + 4, .value = 0xFFFE } }, // last endCode 0xFFFE
        &.{ .{ .at = end + 2, .value = 0x10 }, .{ .at = start + 2, .value = 0x10 } }, // descending endCode
        &.{.{ .at = start + 2, .value = 0x42 }}, // start after end
        &.{ .{ .at = end, .value = 0x30 }, .{ .at = start + 2, .value = 0x30 } }, // overlapping segments
        &.{.{ .at = range_offset + 2, .value = 0x100 }}, // glyphIdArray past the subtable
        &.{.{ .at = delta + 2, .value = 4 -% @as(u16, 0x41) }}, // U+0041 maps to glyph 4
    };
    for (cases) |edits| expectCmapEdit(error.InvalidCmap, edits) catch |err| {
        std.debug.print("edit at {d}\n", .{edits[0].at});
        return err;
    };
}

test "FP-0013 case 33: malformed format 12 subtables return InvalidCmap" {
    const f4 = try builder.ttFormat4(gpa);
    defer gpa.free(f4);
    const one_group = try builder.format12(gpa, &.{.{ .start = 0x20, .end = 0x20, .glyph = 1 }});
    defer gpa.free(one_group);
    try testing.expectEqual(@as(usize, 28), one_group.len);
    writeU32(one_group[12..16], 0xFFFFFFFF);
    const huge = try builder.ttCmap(gpa, f4, one_group);
    defer gpa.free(huge);
    try expectCmapError(error.InvalidCmap, huge);

    const groups = builder.tt_cmap_format12_offset + 16;
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = groups + 12, .value = 0x20, .width = 4 }}); // group 1 overlaps group 0
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = groups + 24 + 4, .value = 0x110000, .width = 4 }});
    try expectCmapEdit(error.InvalidCmap, &.{.{ .at = groups + 24 + 4, .value = 0x1F601, .width = 4 }}); // reaches glyph 4
}

/// Builds a font from `set` and returns it; the font must keep mapping U+0041 to glyph 2.
fn parseEdited(set: *const TableSet, bytes_out: *[]u8) !font.Font {
    bytes_out.* = try build(set, &.{}, &.{});
    const f = try font.parse(bytes_out.*, .{});
    try testing.expectEqual(@as(u16, 2), f.glyphIndex(0x41));
    return f;
}

fn expectStatus(comptime T: type, expected: font.TableStatus(T), actual: font.TableStatus(T)) !void {
    switch (expected) {
        .rejected => |d| if (actual != .rejected or actual.rejected != d) return statusMismatch(expected, actual),
        .unsupported_version => |v| if (actual != .unsupported_version or actual.unsupported_version != v) return statusMismatch(expected, actual),
        .absent => if (actual != .absent) return statusMismatch(expected, actual),
        .valid => unreachable,
    }
}

fn statusMismatch(expected: anytype, actual: anytype) error{TestUnexpectedResult} {
    std.debug.print("expected {any}, found {any}\n", .{ expected, actual });
    return error.TestUnexpectedResult;
}

fn nameStatus(set: *const TableSet) !font.TableStatus(font.Name) {
    var bytes: []u8 = undefined;
    const f = try parseEdited(set, &bytes);
    defer gpa.free(bytes);
    return switch (f.name()) {
        .valid => .{ .valid = undefined },
        else => |s| s,
    };
}

test "FP-0013 case 34: malformed name tables are rejected with the matching defect without failing the font" {
    const Edit = struct { at: usize, value: u16, expected: font.TableStatus(font.Name) };
    const edits = [_]Edit{
        .{ .at = 4, .value = 0x1000, .expected = .{ .rejected = .offset_out_of_bounds } }, // storageOffset
        .{ .at = 6 + 12 + 8, .value = 0x100, .expected = .{ .rejected = .offset_out_of_bounds } }, // a string past storage
        .{ .at = 2, .value = 0xFFFF, .expected = .{ .rejected = .count_out_of_bounds } }, // count
        .{ .at = 6 + 6, .value = 3, .expected = .{ .rejected = .unsorted_records } }, // record 0 becomes name ID 3
        .{ .at = 6 + 8, .value = 11, .expected = .{ .rejected = .odd_utf16_length } }, // an odd platform 3 length
        .{ .at = 0, .value = 2, .expected = .{ .unsupported_version = 2 } }, // format 2
    };
    for (edits) |e| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("name".*), e.at), e.value);
        try expectStatus(font.Name, e.expected, try nameStatus(&set));
    }
}

fn os2Status(set: *const TableSet) !font.TableStatus(font.Os2) {
    var bytes: []u8 = undefined;
    const f = try parseEdited(set, &bytes);
    defer gpa.free(bytes);
    return f.os2();
}

test "FP-0013 case 35: OS/2 versions and lengths" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("OS/2".*), 0), 5);
        try expectStatus(font.Os2, .{ .rejected = .too_short }, try os2Status(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("OS/2".*), 0), 0);
        set.truncate("OS/2".*, 68);
        const os2 = (try os2Status(&set)).valid;
        try testing.expectEqual(@as(u16, 0), os2.version);
        try testing.expect(os2.typo == null and os2.v1 == null and os2.v2 == null and os2.v5 == null);
        try testing.expectEqual(builder.os2_weight, os2.us_weight_class);
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("OS/2".*), 0), 1);
        set.truncate("OS/2".*, 85);
        try expectStatus(font.Os2, .{ .rejected = .too_short }, try os2Status(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("OS/2".*), 0), 6);
        try expectStatus(font.Os2, .{ .unsupported_version = 6 }, try os2Status(&set));
    }
}

fn postStatus(set: *const TableSet) !font.TableStatus(font.Post) {
    var bytes: []u8 = undefined;
    const f = try parseEdited(set, &bytes);
    defer gpa.free(bytes);
    return f.post();
}

/// A post 2.0 table with `indices` and Pascal `strings` appended verbatim.
fn post2(num_glyphs: u16, indices: []const u16, strings: []const u8) ![]u8 {
    var w: builder.Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    const header = try builder.postTable(gpa);
    defer gpa.free(header);
    try w.raw(header);
    w.patchU32(0, 0x00020000);
    try w.u16_(num_glyphs);
    for (indices) |i| try w.u16_(i);
    try w.raw(strings);
    return w.finish();
}

test "FP-0013 case 36: post lengths, glyph counts, string indexes, and versions" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        set.truncate("post".*, 31);
        try expectStatus(font.Post, .{ .rejected = .too_short }, try postStatus(&set));
    }
    const Case = struct { num_glyphs: u16, indices: []const u16, strings: []const u8, expected: font.TableStatus(font.Post) };
    const cases = [_]Case{
        .{ .num_glyphs = 3, .indices = &.{ 0, 1, 2 }, .strings = "", .expected = .{ .rejected = .glyph_count_mismatch } },
        .{ .num_glyphs = 4, .indices = &.{ 0, 258, 259, 3 }, .strings = "\x01a", .expected = .{ .rejected = .invalid_string_index } },
        .{ .num_glyphs = 4, .indices = &.{ 0, 258, 2, 3 }, .strings = "\x0Aab", .expected = .{ .rejected = .invalid_string_index } },
    };
    for (cases) |c| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("post".*, try post2(c.num_glyphs, c.indices, c.strings));
        try expectStatus(font.Post, c.expected, try postStatus(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("post".*, try post2(4, &.{ 0, 258, 259, 3 }, "\x01a\x02bc"));
        const post = (try postStatus(&set)).valid;
        try testing.expectEqual(@as(u32, 0x00020000), post.version);
    }
    for ([_]u32{ 0x00025000, 0x00040000 }) |version| {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU32(u32At(set.get("post".*), 0), version);
        try expectStatus(font.Post, .{ .unsupported_version = version }, try postStatus(&set));
    }
}

fn layoutStatus(set: *const TableSet, tag: builder.Tag) !font.TableStatus(font.Layout) {
    var bytes: []u8 = undefined;
    const f = try parseEdited(set, &bytes);
    defer gpa.free(bytes);
    return switch (if (std.mem.eql(u8, &tag, "GSUB")) f.gsub() else f.gpos()) {
        .valid => .{ .valid = undefined },
        else => |s| s,
    };
}

fn expectLayoutTable(tag: builder.Tag, table: []const u8, expected: font.TableStatus(font.Layout)) !void {
    var set = try builder.ttTables(gpa);
    defer set.deinit();
    try set.put(tag, table);
    expectStatus(font.Layout, expected, try layoutStatus(&set, tag)) catch |err| {
        std.debug.print("in {s}\n", .{&tag});
        return err;
    };
}

test "FP-0013 case 37: malformed GSUB and GPOS tables are rejected with the matching defect" {
    for ([_]builder.Tag{ "GSUB".*, "GPOS".* }) |tag| {
        const scripts = [_]builder.Tag{ "DFLT".*, "latn".* };
        const base = try builder.layoutTable(gpa, .{ .scripts = &scripts, .features = &.{ "kern".*, "liga".* }, .lookups = 1 });
        defer gpa.free(base);
        {
            var set = try builder.ttTables(gpa);
            defer set.deinit();
            try set.put(tag, base);
            try testing.expect(try layoutStatus(&set, tag) == .valid);
        }
        const offsets = builder.layoutOffsets(base);

        const Edit = struct { at: usize, value: u16, expected: font.TableStatus(font.Layout) };
        const edits = [_]Edit{
            .{ .at = 2, .value = 2, .expected = .{ .unsupported_version = 0x00010002 } },
            .{ .at = 4, .value = 0xFFF0, .expected = .{ .rejected = .offset_out_of_bounds } }, // ScriptList offset
            .{ .at = offsets.script_list, .value = 0xFFFF, .expected = .{ .rejected = .count_out_of_bounds } }, // script count
            .{ .at = offsets.script_list + 2 + 4, .value = 0xFFF0, .expected = .{ .rejected = .offset_out_of_bounds } }, // script offset
            .{ .at = offsets.feature_list, .value = 0xFFFF, .expected = .{ .rejected = .count_out_of_bounds } }, // feature count
            .{ .at = offsets.lookup_list + 2, .value = 0xFFF0, .expected = .{ .rejected = .offset_out_of_bounds } }, // lookup offset
        };
        for (edits) |e| {
            const table = try gpa.dupe(u8, base);
            defer gpa.free(table);
            writeU16(u16At(table, e.at), e.value);
            try expectLayoutTable(tag, table, e.expected);
        }

        const unsorted = try builder.layoutTable(gpa, .{ .scripts = &.{ "latn".*, "DFLT".* } });
        defer gpa.free(unsorted);
        try expectLayoutTable(tag, unsorted, .{ .rejected = .unsorted_records });
        const variations = try builder.layoutTable(gpa, .{ .minor = 1, .scripts = &scripts, .feature_variations = 0xFFF0 });
        defer gpa.free(variations);
        try expectLayoutTable(tag, variations, .{ .rejected = .offset_out_of_bounds });
    }
}

fn gdefStatus(set: *const TableSet) !font.TableStatus(font.Gdef) {
    var bytes: []u8 = undefined;
    const f = try parseEdited(set, &bytes);
    defer gpa.free(bytes);
    return f.gdef();
}

test "FP-0013 case 38: GDEF versions, lengths, and offsets" {
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("GDEF".*, try builder.gdefTable(gpa, 1, 12));
        try expectStatus(font.Gdef, .{ .unsupported_version = 0x00010001 }, try gdefStatus(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("GDEF".*, try builder.gdefTable(gpa, 2, 12));
        try expectStatus(font.Gdef, .{ .rejected = .too_short }, try gdefStatus(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        writeU16(u16At(set.get("GDEF".*), 4), 0x100);
        try expectStatus(font.Gdef, .{ .rejected = .offset_out_of_bounds }, try gdefStatus(&set));
    }
    {
        var set = try builder.ttTables(gpa);
        defer set.deinit();
        try set.putOwned("GDEF".*, try builder.gdefTable(gpa, 3, 18));
        const gdef = (try gdefStatus(&set)).valid;
        try testing.expectEqual(@as(u32, 0x00010003), gdef.version);
        try testing.expectEqual(@as(?u32, 0), gdef.item_var_store);
    }
}

fn expectCffError(table: []const u8) !void {
    var set = try builder.cffTables(gpa);
    defer set.deinit();
    try set.put("CFF ".*, table);
    expectParseError(error.InvalidCff, &set, &.{}, &.{}) catch |err| {
        std.debug.print("CFF table {any}\n", .{table});
        return err;
    };
}

fn expectCffSpecError(spec: builder.CffSpec) !void {
    const table = try builder.cffTable(gpa, spec);
    defer gpa.free(table);
    try expectCffError(table);
}

test "FP-0013 case 39: malformed CFF tables return InvalidCff" {
    const base = try builder.cffTable(gpa, .{});
    defer gpa.free(base);
    const name = builder.cff_name_index;
    const Edit = struct { at: usize, value: u8 };
    const edits = [_][]const Edit{
        &.{.{ .at = 0, .value = 2 }}, // major 2
        &.{.{ .at = 2, .value = 3 }}, // hdrSize 3
        &.{.{ .at = 3, .value = 0 }}, // header offSize 0
        &.{.{ .at = 3, .value = 5 }}, // header offSize 5
        &.{.{ .at = name + 1, .value = 2 }}, // Name count 2
        &.{ .{ .at = name, .value = 0xFF }, .{ .at = name + 1, .value = 0xFF } }, // Name count 0xFFFF
        &.{.{ .at = name + 2, .value = 0 }}, // INDEX offSize 0
        &.{.{ .at = name + 2, .value = 5 }}, // INDEX offSize 5
        &.{.{ .at = name + 3, .value = 2 }}, // first offset 2
        &.{.{ .at = name + 4, .value = 0 }}, // decreasing offsets
        &.{.{ .at = name + 4, .value = 0xF0 }}, // an INDEX past the table
        &.{.{ .at = builder.cff_charstrings_operand + 4, .value = 16 }}, // operator 16 replaces CharStrings
        &.{ .{ .at = builder.cff_charstrings_operand + 2, .value = 0x10 }, .{ .at = builder.cff_charstrings_operand + 3, .value = 0 } }, // CharStrings offset past the table
    };
    for (edits) |list| {
        const table = try gpa.dupe(u8, base);
        defer gpa.free(table);
        for (list) |e| table[e.at] = e.value;
        try expectCffError(table);
    }
    try expectCffSpecError(.{ .charstrings = 3 });
    try expectCffSpecError(.{ .prefix = &.{ 0x8C, 0x0C, 0x06 } }); // CharstringType 1
    try expectCffSpecError(.{ .prefix = &(@as([49]u8, @splat(0x8B)) ++ [_]u8{ 0x0C, 0x07 }) }); // 49 operands
    try expectCffSpecError(.{ .suffix = &.{ 0x1E, 0x12, 0x34 } }); // an unterminated real
    try expectCffSpecError(.{ .suffix = &.{22} }); // reserved byte 22

    // The same DICT forms are accepted when well formed.
    const fine = try builder.cffTable(gpa, .{ .prefix = &.{ 0x8D, 0x0C, 0x06 }, .suffix = &(@as([47]u8, @splat(0x8B)) ++ [_]u8{ 0x1E, 0x12, 0x3F, 0x0C, 0x07 }) });
    defer gpa.free(fine);
    var set = try builder.cffTables(gpa);
    defer set.deinit();
    try set.put("CFF ".*, fine);
    const bytes = try build(&set, &.{}, &.{});
    defer gpa.free(bytes);
    try testing.expectEqual(@as(u16, 2), (try font.parse(bytes, .{})).cff().?.charstrings_count);
}

test "FP-0013 case 40: font.parse takes no allocator" {
    comptime {
        for (@typeInfo(@TypeOf(font.parse)).@"fn".param_types) |param| {
            if (param == std.mem.Allocator or param == ?std.mem.Allocator) @compileError("font.parse takes an allocator");
        }
    }
    try testing.expectEqual(@as(usize, 2), @typeInfo(@TypeOf(font.parse)).@"fn".param_types.len);
}
