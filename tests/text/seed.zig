//! The `fairpane-text-seed` format, version 1, for FP-0013 qualification seeds.
//! The format accepts no field beyond the frozen set, and every code point string is canonical.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const format_name = "fairpane-text-seed";
pub const unicode_version = "18.0.0";

pub const Error = error{
    InvalidJson,
    WrongType,
    UnknownField,
    MissingField,
    WrongFormat,
    WrongVersion,
    WrongUnicodeVersion,
    NoncanonicalCodePoint,
    MissingPropertyEntry,
    ExtraPropertyEntry,
    UnknownPropertyKey,
    MissingPropertyKey,
    UnknownFixture,
    CoverageOutsideSeed,
} || Allocator.Error;

pub const property_keys = [_][]const u8{ "gc", "sc", "scx", "bc", "jt", "InSC", "InPC" };
const seed_fields = [_][]const u8{ "format", "version", "id", "unicode_version", "text_utf8", "code_points", "properties", "coverage" };
const coverage_fields = [_][]const u8{ "covered", "uncovered" };
pub const fixture_dirs = [_][]const u8{ "noto-sans", "noto-sans-arabic", "noto-sans-devanagari", "noto-sans-cjk-jp-subset" };

pub const Properties = struct {
    code_point: u21,
    gc: []const u8,
    sc: []const u8,
    scx: []const []const u8,
    bc: []const u8,
    jt: []const u8,
    insc: []const u8,
    inpc: []const u8,
};

pub const Coverage = struct {
    fixture: []const u8,
    covered: []const u21,
    uncovered: []const u21,
};

pub const Seed = struct {
    id: []const u8,
    text_utf8: []const u8,
    code_points: []const u21,
    properties: []const Properties,
    coverage: []const Coverage,
};

/// Parses `U+` followed by 4 to 6 uppercase hex digits without extra leading zeros.
pub fn parseCodePoint(text: []const u8) Error!u21 {
    if (text.len < 6 or text.len > 8 or !std.mem.startsWith(u8, text, "U+")) return error.NoncanonicalCodePoint;
    const digits = text[2..];
    for (digits) |c| if (!((c >= '0' and c <= '9') or (c >= 'A' and c <= 'F'))) return error.NoncanonicalCodePoint;
    if (digits.len > 4 and digits[0] == '0') return error.NoncanonicalCodePoint;
    const value = std.fmt.parseInt(u32, digits, 16) catch return error.NoncanonicalCodePoint;
    if (value > 0x10FFFF) return error.NoncanonicalCodePoint;
    return @intCast(value);
}

fn requireFields(map: std.json.ObjectMap, comptime allowed: []const []const u8) Error!void {
    var it = map.iterator();
    while (it.next()) |entry| {
        for (allowed) |name| {
            if (std.mem.eql(u8, name, entry.key_ptr.*)) break;
        } else return error.UnknownField;
    }
    for (allowed) |name| if (map.get(name) == null) return error.MissingField;
}

fn string(value: std.json.Value) Error![]const u8 {
    return switch (value) {
        .string => |s| s,
        else => error.WrongType,
    };
}

fn array(value: std.json.Value) Error![]const std.json.Value {
    return switch (value) {
        .array => |a| a.items,
        else => error.WrongType,
    };
}

fn object(value: std.json.Value) Error!std.json.ObjectMap {
    return switch (value) {
        .object => |o| o,
        else => error.WrongType,
    };
}

fn codePointList(arena: Allocator, value: std.json.Value) Error![]u21 {
    const items = try array(value);
    const out = try arena.alloc(u21, items.len);
    for (items, out) |item, *cp| cp.* = try parseCodePoint(try string(item));
    return out;
}

fn contains(list: []const u21, cp: u21) bool {
    return std.mem.indexOfScalar(u21, list, cp) != null;
}

/// Parses and validates one seed. Every allocation comes from `arena`.
pub fn parse(arena: Allocator, json: []const u8) Error!Seed {
    const root = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    const top = try object(root);
    try requireFields(top, &seed_fields);
    if (!std.mem.eql(u8, try string(top.get("format").?), format_name)) return error.WrongFormat;
    switch (top.get("version").?) {
        .integer => |v| if (v != 1) return error.WrongVersion,
        else => return error.WrongType,
    }
    if (!std.mem.eql(u8, try string(top.get("unicode_version").?), unicode_version)) return error.WrongUnicodeVersion;
    const code_points = try codePointList(arena, top.get("code_points").?);

    // Exactly one property entry for each distinct code point.
    const props = try object(top.get("properties").?);
    var distinct: std.ArrayList(u21) = .empty;
    for (code_points) |cp| if (!contains(distinct.items, cp)) try distinct.append(arena, cp);
    const properties = try arena.alloc(Properties, distinct.items.len);
    for (distinct.items, properties) |cp, *out| {
        var key_buffer: [8]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buffer, "U+{X:0>4}", .{cp}) catch unreachable;
        const entry = try object(props.get(key) orelse return error.MissingPropertyEntry);
        var it = entry.iterator();
        while (it.next()) |field| {
            for (property_keys) |name| {
                if (std.mem.eql(u8, name, field.key_ptr.*)) break;
            } else return error.UnknownPropertyKey;
        }
        for (property_keys) |name| if (entry.get(name) == null) return error.MissingPropertyKey;
        const scx_items = try array(entry.get("scx").?);
        const scx = try arena.alloc([]const u8, scx_items.len);
        for (scx_items, scx) |item, *s| s.* = try string(item);
        out.* = .{
            .code_point = cp,
            .gc = try string(entry.get("gc").?),
            .sc = try string(entry.get("sc").?),
            .scx = scx,
            .bc = try string(entry.get("bc").?),
            .jt = try string(entry.get("jt").?),
            .insc = try string(entry.get("InSC").?),
            .inpc = try string(entry.get("InPC").?),
        };
    }
    var keys = props.iterator();
    while (keys.next()) |entry| {
        if (!contains(distinct.items, try parseCodePoint(entry.key_ptr.*))) return error.ExtraPropertyEntry;
    }

    const coverage_object = try object(top.get("coverage").?);
    const coverage = try arena.alloc(Coverage, coverage_object.count());
    var it = coverage_object.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        for (fixture_dirs) |dir| {
            if (std.mem.eql(u8, dir, entry.key_ptr.*)) break;
        } else return error.UnknownFixture;
        const lists = try object(entry.value_ptr.*);
        try requireFields(lists, &coverage_fields);
        coverage[i] = .{
            .fixture = entry.key_ptr.*,
            .covered = try codePointList(arena, lists.get("covered").?),
            .uncovered = try codePointList(arena, lists.get("uncovered").?),
        };
        for (coverage[i].covered) |cp| if (!contains(code_points, cp)) return error.CoverageOutsideSeed;
        for (coverage[i].uncovered) |cp| if (!contains(code_points, cp)) return error.CoverageOutsideSeed;
    }

    return .{
        .id = try string(top.get("id").?),
        .text_utf8 = try string(top.get("text_utf8").?),
        .code_points = code_points,
        .properties = properties,
        .coverage = coverage,
    };
}
