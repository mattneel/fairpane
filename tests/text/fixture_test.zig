//! FP-0013 cases 12, 13, and 14: the real font fixtures against their fontTools expectation files.

const std = @import("std");
const testing = std.testing;
const fairpane = @import("fairpane");
const font = fairpane.font;
const fixtures = @import("fixtures.zig");
const Value = std.json.Value;

fn hexLower(bytes: []const u8, out: []u8) []const u8 {
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[2 * i] = digits[b >> 4];
        out[2 * i + 1] = digits[b & 15];
    }
    return out[0 .. 2 * bytes.len];
}

test "FP-0013 case 12: each embedded font's SHA-256 equals font_sha256 in its expectation file" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    for (fixtures.fonts) |f| {
        const root = try std.json.parseFromSliceLeaky(Value, arena.allocator(), f.expectation, .{});
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(f.bytes, &digest, .{});
        var hex: [64]u8 = undefined;
        try testing.expectEqualStrings(root.object.get("font_sha256").?.string, hexLower(&digest, &hex));
        const expected_path = try std.fmt.allocPrint(arena.allocator(), "{s}/{s}", .{ f.dir, f.file });
        try testing.expectEqualStrings(expected_path, root.object.get("font").?.string);
    }
}

/// One flattened scalar field of a parser value.
const Field = struct {
    name: []const u8,
    value: union(enum) { int: i64, hex: []const u8 },
};

/// Flattens integer fields, byte arrays, and nested optional groups of `value` into `out`.
fn flatten(comptime T: type, arena: std.mem.Allocator, value: T, out: *std.ArrayList(Field)) !void {
    const info = @typeInfo(T).@"struct";
    inline for (info.field_names, info.field_types) |name, FieldType| {
        const v = @field(value, name);
        switch (@typeInfo(FieldType)) {
            .int => try out.append(arena, .{ .name = name, .value = .{ .int = @intCast(v) } }),
            .array => |a| {
                comptime std.debug.assert(a.child == u8);
                const hex = try arena.alloc(u8, 2 * a.len);
                try out.append(arena, .{ .name = name, .value = .{ .hex = hexLower(&v, hex) } });
            },
            .optional => |o| if (v) |inner| try flatten(o.child, arena, inner, out),
            .@"struct" => try flatten(FieldType, arena, v, out),
            else => @compileError("unsupported field type in " ++ @typeName(T)),
        }
    }
}

/// Requires the JSON object and the parser value to have the same field names and equal values.
fn expectFields(comptime T: type, arena: std.mem.Allocator, what: []const u8, expected: Value, actual: T) !void {
    var fields: std.ArrayList(Field) = .empty;
    try flatten(T, arena, actual, &fields);
    const object = expected.object;
    if (object.count() != fields.items.len) {
        std.debug.print("{s}: the expectation has {d} fields, the parser {d}\n", .{ what, object.count(), fields.items.len });
        var it = object.iterator();
        while (it.next()) |e| std.debug.print("  expected {s}\n", .{e.key_ptr.*});
        for (fields.items) |f| std.debug.print("  parser {s}\n", .{f.name});
        return error.TestUnexpectedResult;
    }
    for (fields.items) |f| {
        const json = object.get(f.name) orelse {
            std.debug.print("{s}: the expectation lacks {s}\n", .{ what, f.name });
            return error.TestUnexpectedResult;
        };
        const same = switch (f.value) {
            .int => |i| json == .integer and json.integer == i,
            .hex => |h| json == .string and std.mem.eql(u8, json.string, h),
        };
        if (!same) {
            std.debug.print("{s}.{s}: expected {any}, parser {any}\n", .{ what, f.name, json, f.value });
            return error.TestUnexpectedResult;
        }
    }
}

fn int(v: Value) i64 {
    return v.integer;
}

fn expectLayout(what: []const u8, expected: Value, status: font.TableStatus(font.Layout)) !void {
    if (expected == .null) return testing.expect(status == .absent);
    const layout = switch (status) {
        .valid => |l| l,
        else => {
            std.debug.print("{s}: {any}\n", .{ what, status });
            return error.TestUnexpectedResult;
        },
    };
    const o = expected.object;
    try testing.expectEqual(int(o.get("version").?), layout.version);
    const scripts = o.get("scripts").?.array.items;
    try testing.expectEqual(scripts.len, layout.scriptCount());
    for (scripts, 0..) |s, i| try testing.expectEqualStrings(s.string, &layout.scriptTag(@intCast(i)));
    const features = o.get("features").?.array.items;
    try testing.expectEqual(features.len, layout.featureCount());
    for (features, 0..) |s, i| try testing.expectEqualStrings(s.string, &layout.featureTag(@intCast(i)));
    try testing.expectEqual(int(o.get("lookup_count").?), layout.lookupCount());
    try testing.expectEqual(@as(usize, 4), o.count());
}

const expectation_fields = [_][]const u8{
    "format", "version", "font", "font_sha256", "generator", "sfnt_version", "tables", "head", "hhea", "maxp",
    "os2",    "post",    "name", "cmap",        "hmtx",      "glyf",         "gdef",   "gsub", "gpos", "cff",
};

fn checkFixture(arena: std.mem.Allocator, f: fixtures.Font) !void {
    const root = try std.json.parseFromSliceLeaky(Value, arena, f.expectation, .{});
    const e = root.object;
    try testing.expectEqual(expectation_fields.len, e.count());
    for (expectation_fields) |name| if (e.get(name) == null) return error.TestUnexpectedResult;
    try testing.expectEqualStrings("fairpane-font-expectation", e.get("format").?.string);
    try testing.expectEqual(@as(i64, 1), int(e.get("version").?));

    const parsed = try font.parse(f.bytes, .{ .checksums = .reject });
    try testing.expect(parsed.integrity().clean());
    try testing.expectEqual(@as(font.Outline, switch (int(e.get("sfnt_version").?)) {
        0x00010000 => .truetype,
        0x4F54544F => .cff,
        else => return error.TestUnexpectedResult,
    }), parsed.outline());

    const tables = e.get("tables").?.array.items;
    try testing.expectEqual(tables.len, parsed.tableCount());
    for (tables, 0..) |t, i| {
        const r = parsed.tableRecord(@intCast(i));
        try testing.expectEqualStrings(t.object.get("tag").?.string, &r.tag);
        try testing.expectEqual(int(t.object.get("checksum").?), r.checksum);
        try testing.expectEqual(int(t.object.get("offset").?), r.offset);
        try testing.expectEqual(int(t.object.get("length").?), r.length);
        try testing.expect(parsed.findTable(r.tag) != null);
    }

    try expectFields(font.Head, arena, "head", e.get("head").?, parsed.head());
    try expectFields(font.Hhea, arena, "hhea", e.get("hhea").?, parsed.hhea());
    try expectFields(font.Maxp, arena, "maxp", e.get("maxp").?, parsed.maxp());
    try testing.expectEqual(int(e.get("maxp").?.object.get("num_glyphs").?), parsed.glyphCount());
    switch (parsed.os2()) {
        .valid => |os2| try expectFields(font.Os2, arena, "os2", e.get("os2").?, os2),
        .absent => try testing.expect(e.get("os2").? == .null),
        else => |s| {
            std.debug.print("os2: {any}\n", .{s});
            return error.TestUnexpectedResult;
        },
    }
    switch (parsed.post()) {
        .valid => |post| try expectFields(font.Post, arena, "post", e.get("post").?, post),
        .absent => try testing.expect(e.get("post").? == .null),
        else => |s| {
            std.debug.print("post: {any}\n", .{s});
            return error.TestUnexpectedResult;
        },
    }

    const names = e.get("name").?.array.items;
    const name = parsed.name().valid;
    try testing.expectEqual(names.len, name.count());
    for (names, 0..) |n, i| {
        const r = name.record(@intCast(i));
        const o = n.object;
        try testing.expectEqual(int(o.get("platform").?), r.platform_id);
        try testing.expectEqual(int(o.get("encoding").?), r.encoding_id);
        try testing.expectEqual(int(o.get("language").?), r.language_id);
        try testing.expectEqual(int(o.get("name_id").?), r.name_id);
        const hex = try arena.alloc(u8, 2 * r.bytes.len);
        try testing.expectEqualStrings(o.get("bytes").?.string, hexLower(r.bytes, hex));
        try testing.expectEqualSlices(u8, r.bytes, name.find(r.platform_id, r.encoding_id, r.language_id, r.name_id).?);
    }

    const cmap = e.get("cmap").?.object;
    const subtables = cmap.get("subtables").?.array.items;
    try testing.expectEqual(subtables.len, parsed.cmapSubtableCount());
    for (subtables, 0..) |s, i| {
        const r = parsed.cmapSubtable(@intCast(i));
        const o = s.object;
        try testing.expectEqual(int(o.get("platform").?), r.platform_id);
        try testing.expectEqual(int(o.get("encoding").?), r.encoding_id);
        try testing.expectEqual(int(o.get("format").?), r.format);
        const language = o.get("language").?;
        if (language == .null) try testing.expectEqual(@as(?u32, null), r.language) else try testing.expectEqual(@as(?u32, @intCast(int(language))), r.language);
    }
    const selected = cmap.get("selected").?.object;
    const unicode_cmap = parsed.unicodeCmap();
    try testing.expectEqual(int(selected.get("platform").?), unicode_cmap.platform_id);
    try testing.expectEqual(int(selected.get("encoding").?), unicode_cmap.encoding_id);
    try testing.expectEqual(int(selected.get("format").?), unicode_cmap.format);
    const glyphs = cmap.get("glyphs").?.array.items;
    try testing.expect(glyphs.len > 0);
    for (glyphs) |g| {
        const cp_text = g.object.get("code_point").?.string;
        const cp = try std.fmt.parseInt(u21, cp_text[2..], 16);
        testing.expectEqual(int(g.object.get("glyph").?), parsed.glyphIndex(cp)) catch |err| {
            std.debug.print("{s} {s}\n", .{ f.dir, cp_text });
            return err;
        };
    }

    for (e.get("hmtx").?.array.items) |m| {
        const metric = try parsed.advance(@intCast(int(m.object.get("glyph").?)));
        try testing.expectEqual(int(m.object.get("advance").?), metric.advance);
        try testing.expectEqual(int(m.object.get("lsb").?), metric.lsb);
    }

    const glyf = e.get("glyf").?;
    if (glyf == .null) {
        try testing.expectEqual(font.Outline.cff, parsed.outline());
        try testing.expectError(error.NotTrueType, parsed.glyphHeader(0));
    } else for (glyf.array.items) |g| {
        const header = try parsed.glyphHeader(@intCast(int(g.object.get("glyph").?)));
        const expected = g.object.get("header").?;
        if (expected == .null) {
            try testing.expect(header == null);
        } else try expectFields(font.GlyphHeader, arena, "glyf", expected, header.?);
    }

    const gdef = e.get("gdef").?;
    switch (parsed.gdef()) {
        .absent => try testing.expect(gdef == .null),
        .valid => |g| {
            try testing.expectEqual(int(gdef.object.get("version").?), g.version);
            try testing.expectEqual(@as(usize, 1), gdef.object.count());
        },
        else => |s| {
            std.debug.print("gdef: {any}\n", .{s});
            return error.TestUnexpectedResult;
        },
    }
    try expectLayout("gsub", e.get("gsub").?, parsed.gsub());
    try expectLayout("gpos", e.get("gpos").?, parsed.gpos());

    const cff = e.get("cff").?;
    if (parsed.cff()) |c| {
        const cff_names = cff.object.get("names").?.array.items;
        try testing.expectEqual(@as(usize, 1), cff_names.len);
        try testing.expectEqualStrings(cff_names[0].string, c.name);
        try testing.expectEqual(int(cff.object.get("charstrings_count").?), c.charstrings_count);
        try testing.expectEqual(cff.object.get("cid_keyed").?.bool, c.cid_keyed);
    } else try testing.expect(cff == .null);
}

test "FP-0013 case 13: each fixture parses under .reject and equals every field of its expectation file" {
    for (fixtures.fonts) |f| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        checkFixture(arena.allocator(), f) catch |err| {
            std.debug.print("fixture {s}\n", .{f.dir});
            return err;
        };
    }
}

test "FP-0013 case 14: the CJK subset is a CFF font whose name table keeps only IDs 0, 7, 13, and 14" {
    const parsed = try font.parse(fixtures.font("noto-sans-cjk-jp-subset").?.bytes, .{ .checksums = .reject });
    try testing.expectEqual(font.Outline.cff, parsed.outline());
    try testing.expectEqual(parsed.glyphCount(), parsed.cff().?.charstrings_count);
    const name = parsed.name().valid;
    try testing.expect(name.count() > 0);
    for (0..name.count()) |i| {
        const id = name.record(@intCast(i)).name_id;
        try testing.expect(id == 0 or id == 7 or id == 13 or id == 14);
    }
}
