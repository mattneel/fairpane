//! FP-0008 contract case 3: the embedded named character reference table, its provenance, and its generated form.

const std = @import("std");
const entities = @import("entities.zig");
const WebString = @import("../web_string.zig").WebString;
const testing = std.testing;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Value = std.json.Value;

const entities_json = @embedFile("entities.json");
const entities_license = @embedFile("entities.LICENSE");
const provenance_json = @embedFile("entities.provenance.json");

fn member(value: Value, name: []const u8) !Value {
    if (value != .object) return error.TestUnexpectedResult;
    return value.object.get(name) orelse error.TestUnexpectedResult;
}

fn expectString(expected: []const u8, value: Value) !void {
    try testing.expect(value == .string);
    try testing.expectEqualStrings(expected, value.string);
}

/// Checks that `record` names `bytes` by size and SHA-256.
fn expectRecorded(record: Value, path: []const u8, bytes: []const u8) !void {
    try expectString(path, try member(record, "path"));
    const size = try member(record, "size");
    try testing.expect(size == .integer);
    try testing.expectEqual(@as(i64, @intCast(bytes.len)), size.integer);
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    try expectString(&std.fmt.bytesToHex(digest, .lower), try member(record, "sha256"));
}

fn units(comptime text: []const u8) [text.len]u16 {
    var result: [text.len]u16 = undefined;
    for (text, &result) |c, *unit| unit.* = c;
    return result;
}

fn expectLookup(comptime name: []const u8, expected: []const u21) !void {
    const entity = entities.lookup(&units(name)) orelse {
        std.debug.print("no entity named {s}\n", .{name});
        return error.TestUnexpectedResult;
    };
    try testing.expectEqualStrings(name, entity.name);
    try testing.expectEqualSlices(u21, expected, entity.code_points);
}

const Entry = struct {
    name: []const u8,
    value: Value,

    fn lessThan(_: void, a: Entry, b: Entry) bool {
        const length = @min(a.name.len, b.name.len);
        for (a.name[0..length], b.name[0..length]) |x, y| {
            if (x != y) return @as(u16, x) < @as(u16, y);
        }
        return a.name.len < b.name.len;
    }
};

test "FP-0008 case 3: the embedded table matches its provenance, its generated form, and the frozen counts and lookups" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const provenance = try std.json.parseFromSliceLeaky(Value, allocator, provenance_json, .{});
    try expectString("fairpane-data-provenance", try member(provenance, "format"));
    try testing.expectEqual(@as(i64, 1), (try member(provenance, "version")).integer);
    const data = try member(provenance, "data");
    try expectRecorded(data, "src/html/entities.json", entities_json);
    try expectString("https://html.spec.whatwg.org/entities.json", try member(data, "url"));
    for ([_][]const u8{ "http_last_modified", "http_etag" }) |name| {
        const value = try member(data, name);
        try testing.expect(value == .string or value == .null);
    }
    try testing.expect((try member(data, "retrieved_at")) == .string);
    try testing.expect((try member(data, "standard_last_updated")) == .string);
    const license = try member(provenance, "license");
    try expectRecorded(license, "src/html/entities.LICENSE", entities_license);
    try expectString("CC-BY-4.0; BSD-3-Clause for portions incorporated into source code", try member(license, "name"));
    try expectString("Copyright © WHATWG (Apple, Google, Mozilla, Microsoft).", try member(license, "copyright"));
    const commit = (try member(license, "commit")).string;
    try testing.expectEqual(@as(usize, 40), commit.len);
    try testing.expect(std.mem.indexOf(u8, (try member(license, "url")).string, commit) != null);
    try testing.expect(std.mem.startsWith(u8, entities_license, "Copyright © WHATWG (Apple, Google, Mozilla, Microsoft)."));
    const derived = try member(provenance, "derived");
    try expectString("src/html/entities_gen.zig", try member(derived, "generator"));
    try expectString("src/html/entities_table.zig", try member(derived, "generated"));

    // The committed table equals a parse of the embedded JSON, name by name and code point by code point, in UTF-16 order,
    // so a stale `entities_table.zig` fails this case.
    const root = try std.json.parseFromSliceLeaky(Value, allocator, entities_json, .{});
    try testing.expect(root == .object);
    const entries = try allocator.alloc(Entry, root.object.count());
    for (root.object.keys(), root.object.values(), entries) |key, value, *entry| {
        try testing.expect(key.len > 1 and key[0] == '&');
        entry.* = .{ .name = key[1..], .value = value };
    }
    std.mem.sort(Entry, entries, {}, Entry.lessThan);
    try testing.expectEqual(entries.len, entities.table.len);
    var semicolon: usize = 0;
    var pairs: usize = 0;
    var longest: usize = 0;
    for (entries, entities.table) |entry, entity| {
        try testing.expectEqualStrings(entry.name, entity.name);
        const code_points = (try member(entry.value, "codepoints")).array.items;
        try testing.expectEqual(code_points.len, entity.code_points.len);
        var encoded: [4]u16 = undefined;
        var encoded_len: usize = 0;
        for (code_points, entity.code_points) |json, code_point| {
            try testing.expectEqual(json.integer, @as(i64, code_point));
            if (code_point < 0x10000) {
                encoded[encoded_len] = @intCast(code_point);
                encoded_len += 1;
            } else {
                const offset = code_point - 0x10000;
                encoded[encoded_len] = @intCast(0xD800 + (offset >> 10));
                encoded[encoded_len + 1] = @intCast(0xDC00 + (offset & 0x3FF));
                encoded_len += 2;
            }
        }
        var characters = try WebString.fromUtf8(allocator, (try member(entry.value, "characters")).string);
        defer characters.deinit(allocator);
        try testing.expectEqualSlices(u16, encoded[0..encoded_len], characters.units);

        const body = if (std.mem.endsWith(u8, entity.name, ";")) body: {
            semicolon += 1;
            break :body entity.name[0 .. entity.name.len - 1];
        } else entity.name;
        try testing.expect(body.len != 0);
        for (body) |c| try testing.expect(std.ascii.isAlphanumeric(c));
        if (entity.code_points.len == 2) pairs += 1;
        longest = @max(longest, entity.name.len);
        try testing.expect(!std.mem.startsWith(u8, entity.name, "a;"));
    }
    try testing.expectEqual(@as(usize, 2231), entities.table.len);
    try testing.expectEqual(@as(usize, 2125), semicolon);
    try testing.expectEqual(@as(usize, 106), entities.table.len - semicolon);
    try testing.expectEqual(@as(usize, 93), pairs);
    try testing.expectEqual(@as(usize, 32), longest);
    try testing.expectEqual(@as(usize, 32), entities.max_name_len);

    try expectLookup("amp;", &.{0x26});
    try expectLookup("AMP", &.{0x26});
    try expectLookup("not", &.{0xAC});
    try expectLookup("notin;", &.{0x2209});
    try expectLookup("NotEqualTilde;", &.{ 0x2242, 0x338 });
    try expectLookup("fjlig;", &.{ 0x66, 0x6A });
    try expectLookup("ThickSpace;", &.{ 0x205F, 0x200A });
    try expectLookup("CounterClockwiseContourIntegral;", &.{0x2233});
    try testing.expectEqual(@as(usize, 32), "CounterClockwiseContourIntegral;".len);
    for ([_][]const u8{ "notit", "zz", "ampx" }) |name| {
        var buffer: [8]u16 = undefined;
        for (name, buffer[0..name.len]) |c, *unit| unit.* = c;
        try testing.expect(entities.lookup(buffer[0..name.len]) == null);
    }
}
