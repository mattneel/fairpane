//! FP-0013 case 3 and FP-0108 case 7: an independent, test-only parser of the embedded UCD files.
//! It is the generic reference path for the generated tables in `tables.zig`.
//! It shares no code with `tools/ucd.mjs` or `properties.zig` and resolves values only through `std.meta.stringToEnum`.

const std = @import("std");
const testing = std.testing;
const unicode = @import("properties.zig");

const code_point_count = 0x110000;
/// Marks a code point that `ScriptExtensions.txt` does not list.
const unlisted: u16 = std.math.maxInt(u16);

const files = struct {
    const aliases = @embedFile("ucd/PropertyValueAliases.txt");
    const scripts = @embedFile("ucd/Scripts.txt");
    const script_extensions = @embedFile("ucd/ScriptExtensions.txt");
    const bidi_class = @embedFile("ucd/extracted/DerivedBidiClass.txt");
    const joining_type = @embedFile("ucd/extracted/DerivedJoiningType.txt");
    const general_category = @embedFile("ucd/extracted/DerivedGeneralCategory.txt");
    const indic_syllabic = @embedFile("ucd/IndicSyllabicCategory.txt");
    const indic_positional = @embedFile("ucd/IndicPositionalCategory.txt");
    const grapheme_break = @embedFile("ucd/auxiliary/GraphemeBreakProperty.txt");
    const derived_core = @embedFile("ucd/DerivedCoreProperties.txt");
    const emoji_data = @embedFile("ucd/emoji/emoji-data.txt");
};

/// Maps every alias of one property in `PropertyValueAliases.txt` to its short alias.
fn shortAliases(arena: std.mem.Allocator, property: []const u8) !std.StringHashMapUnmanaged([]const u8) {
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, files.aliases, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, withoutComment(raw), " \t\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ';');
        if (!std.mem.eql(u8, std.mem.trim(u8, fields.first(), " \t"), property)) continue;
        const short = std.mem.trim(u8, fields.next() orelse return error.MalformedAliases, " \t");
        try map.put(arena, short, short);
        while (fields.next()) |field| {
            const alias = std.mem.trim(u8, field, " \t");
            if (alias.len != 0) try map.put(arena, alias, short);
        }
    }
    return map;
}

fn withoutComment(line: []const u8) []const u8 {
    return line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
}

const Range = struct { first: u21, last: u21 };

fn parseRange(text: []const u8) !Range {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (std.mem.indexOf(u8, trimmed, "..")) |dots| {
        return .{
            .first = try std.fmt.parseInt(u21, trimmed[0..dots], 16),
            .last = try std.fmt.parseInt(u21, trimmed[dots + 2 ..], 16),
        };
    }
    const single = try std.fmt.parseInt(u21, trimmed, 16);
    return .{ .first = single, .last = single };
}

/// One property assignment from a data line or a `# @missing:` line.
const Assignment = struct { range: Range, value: []const u8 };

/// Calls `apply` for each `@missing` line in file order, then for each data line.
fn forEachAssignment(text: []const u8, context: anytype, comptime apply: fn (@TypeOf(context), Assignment) anyerror!void) !void {
    const missing_prefix = "# @missing:";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (!std.mem.startsWith(u8, line, missing_prefix)) continue;
        try apply(context, try assignment(line[missing_prefix.len..]));
    }
    lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, withoutComment(raw), " \t\r");
        if (line.len == 0) continue;
        try apply(context, try assignment(line));
    }
}

fn assignment(line: []const u8) !Assignment {
    const body = withoutComment(line);
    const semicolon = std.mem.indexOfScalar(u8, body, ';') orelse return error.MalformedLine;
    return .{
        .range = try parseRange(body[0..semicolon]),
        .value = std.mem.trim(u8, body[semicolon + 1 ..], " \t\r"),
    };
}

/// Marks each code point that a parsed file assigns, so a gap in a file's coverage fails instead of reading an unset value.
const Assigned = struct {
    marks: std.DynamicBitSetUnmanaged,

    fn init(arena: std.mem.Allocator) !Assigned {
        return .{ .marks = try std.DynamicBitSetUnmanaged.initEmpty(arena, code_point_count) };
    }

    fn mark(self: *Assigned, range: Range) void {
        self.marks.setRangeValue(.{ .start = range.first, .end = @as(usize, range.last) + 1 }, true);
    }

    /// Fails with `error.UnassignedCodePoint` when any code point is unassigned. The error trace names the property's call.
    fn expectComplete(self: *const Assigned) !void {
        var unset = self.marks.iterator(.{ .kind = .unset });
        if (unset.next() != null) return error.UnassignedCodePoint;
    }
};

fn Dense(comptime T: type) type {
    return struct {
        values: []T,
        aliases: std.StringHashMapUnmanaged([]const u8),
        assigned: Assigned,

        fn apply(self: *@This(), a: Assignment) anyerror!void {
            const short = self.aliases.get(a.value) orelse {
                std.debug.print("unknown value {s}\n", .{a.value});
                return error.UnknownValue;
            };
            const value = std.meta.stringToEnum(T, short) orelse return error.UnknownValue;
            if (a.range.first > a.range.last) return error.ReversedRange;
            @memset(self.values[a.range.first .. @as(usize, a.range.last) + 1], value);
            self.assigned.mark(a.range);
        }
    };
}

fn dense(comptime T: type, arena: std.mem.Allocator, property: []const u8, text: []const u8) ![]T {
    var state: Dense(T) = .{
        .values = try arena.alloc(T, code_point_count),
        .aliases = try shortAliases(arena, property),
        .assigned = try .init(arena),
    };
    try forEachAssignment(text, &state, Dense(T).apply);
    try state.assigned.expectComplete();
    return state.values;
}

const Extensions = struct {
    arena: std.mem.Allocator,
    sets: std.ArrayListUnmanaged([]const unicode.Script) = .empty,
    index: []u16,
    aliases: std.StringHashMapUnmanaged([]const u8),
    assigned: Assigned,

    fn apply(self: *Extensions, a: Assignment) anyerror!void {
        const slot = if (std.mem.eql(u8, a.value, "<script>")) unlisted else try self.setIndex(a.value);
        if (a.range.first > a.range.last) return error.ReversedRange;
        @memset(self.index[a.range.first .. @as(usize, a.range.last) + 1], slot);
        self.assigned.mark(a.range);
    }

    fn lessThan(_: void, a: unicode.Script, b: unicode.Script) bool {
        return @backingInt(a) < @backingInt(b);
    }

    fn setIndex(self: *Extensions, value: []const u8) !u16 {
        var scripts: std.ArrayListUnmanaged(unicode.Script) = .empty;
        var names = std.mem.tokenizeAny(u8, value, " \t");
        while (names.next()) |name| {
            const short = self.aliases.get(name) orelse return error.UnknownValue;
            try scripts.append(self.arena, std.meta.stringToEnum(unicode.Script, short) orelse return error.UnknownValue);
        }
        std.mem.sort(unicode.Script, scripts.items, {}, lessThan);
        for (self.sets.items, 0..) |set, i| {
            if (std.mem.eql(unicode.Script, set, scripts.items)) return @intCast(i);
        }
        try self.sets.append(self.arena, scripts.items);
        return @intCast(self.sets.items.len - 1);
    }
};

/// One property of a file whose lines name their property in the first value field, as `InCB` lines do in
/// `DerivedCoreProperties.txt`. A line for another property is skipped, and a line for this property has exactly one value.
fn Selected(comptime T: type) type {
    return struct {
        property: []const u8,
        values: []T,
        aliases: std.StringHashMapUnmanaged([]const u8),
        assigned: Assigned,

        fn apply(self: *@This(), a: Assignment) anyerror!void {
            var fields = std.mem.splitScalar(u8, a.value, ';');
            if (!std.mem.eql(u8, std.mem.trim(u8, fields.first(), " \t"), self.property)) return;
            const name = std.mem.trim(u8, fields.next() orelse return error.MissingValue, " \t");
            if (fields.next() != null) return error.ExtraValue;
            const short = self.aliases.get(name) orelse return error.UnknownValue;
            const value = std.meta.stringToEnum(T, short) orelse return error.UnknownValue;
            if (a.range.first > a.range.last) return error.ReversedRange;
            @memset(self.values[a.range.first .. @as(usize, a.range.last) + 1], value);
            self.assigned.mark(a.range);
        }
    };
}

fn selected(comptime T: type, arena: std.mem.Allocator, property: []const u8, text: []const u8) ![]T {
    var state: Selected(T) = .{
        .property = property,
        .values = try arena.alloc(T, code_point_count),
        .aliases = try shortAliases(arena, property),
        .assigned = try .init(arena),
    };
    try forEachAssignment(text, &state, Selected(T).apply);
    try state.assigned.expectComplete();
    return state.values;
}

/// A binary property whose listed ranges are true. A line for another property is skipped.
const Binary = struct {
    property: []const u8,
    values: []bool,

    fn apply(self: *Binary, a: Assignment) anyerror!void {
        var fields = std.mem.splitScalar(u8, a.value, ';');
        if (!std.mem.eql(u8, std.mem.trim(u8, fields.first(), " \t"), self.property)) return;
        if (fields.next() != null) return error.ExtraValue;
        if (a.range.first > a.range.last) return error.ReversedRange;
        @memset(self.values[a.range.first .. @as(usize, a.range.last) + 1], true);
    }
};

/// Every code point takes the default false only when the file states that default, as `emoji-data.txt` does
/// instead of an `@missing` line. The listed ranges then become true.
fn binary(arena: std.mem.Allocator, comptime property: []const u8, text: []const u8) ![]bool {
    if (std.mem.indexOf(u8, text, "# All omitted code points have " ++ property ++ "=No") == null) return error.NoDefault;
    var assigned: Assigned = try .init(arena);
    assigned.mark(.{ .first = 0, .last = code_point_count - 1 });
    try assigned.expectComplete();
    var state: Binary = .{ .property = property, .values = try arena.alloc(bool, code_point_count) };
    @memset(state.values, false);
    try forEachAssignment(text, &state, Binary.apply);
    return state.values;
}

test "the field and binary reference parsers skip other properties and reject extra values" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const incb = try selected(unicode.IndicConjunctBreak, arena, "InCB", "# @missing: 0000..10FFFF; InCB; None\n0041; Alphabetic\n094D; InCB; Linker\n");
    try testing.expectEqual(unicode.IndicConjunctBreak.None, incb[0x41]);
    try testing.expectEqual(unicode.IndicConjunctBreak.Linker, incb[0x94D]);
    try testing.expectError(error.ExtraValue, selected(unicode.IndicConjunctBreak, arena, "InCB", "0000..10FFFF; InCB; None; Linker\n"));
    try testing.expectError(error.UnassignedCodePoint, selected(unicode.IndicConjunctBreak, arena, "InCB", "0000..10FFFE; InCB; None\n"));
    const stated = "# All omitted code points have Extended_Pictographic=No\n";
    const pict = try binary(arena, "Extended_Pictographic", stated ++ "00A9; Extended_Pictographic\n0023; Emoji\n");
    try testing.expect(pict[0xA9] and !pict[0x23] and !pict[0xAA]);
    try testing.expectError(error.ExtraValue, binary(arena, "Extended_Pictographic", stated ++ "00A9; Extended_Pictographic; Y\n"));
    try testing.expectError(error.NoDefault, binary(arena, "Extended_Pictographic", "00A9; Extended_Pictographic\n"));
}

test "the reference parser fails when a file leaves a code point unassigned" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    _ = try dense(unicode.BidiClass, arena, "bc", "0000..10FFFF; L\n");
    try testing.expectError(error.UnassignedCodePoint, dense(unicode.BidiClass, arena, "bc", "0000..0040; L\n0042..10FFFF; L\n"));
    try testing.expectError(error.UnassignedCodePoint, dense(unicode.BidiClass, arena, "bc", "# @missing: 0000..10FFFE; L\n"));
}

test "FP-0013 case 3: lookup equals an independent parse of the embedded UCD files for every code point" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const gc = try dense(unicode.GeneralCategory, arena, "gc", files.general_category);
    const sc = try dense(unicode.Script, arena, "sc", files.scripts);
    const bc = try dense(unicode.BidiClass, arena, "bc", files.bidi_class);
    const jt = try dense(unicode.JoiningType, arena, "jt", files.joining_type);
    const insc = try dense(unicode.IndicSyllabicCategory, arena, "InSC", files.indic_syllabic);
    const inpc = try dense(unicode.IndicPositionalCategory, arena, "InPC", files.indic_positional);
    var scx: Extensions = .{
        .arena = arena,
        .index = try arena.alloc(u16, code_point_count),
        .aliases = try shortAliases(arena, "sc"),
        .assigned = try .init(arena),
    };
    try forEachAssignment(files.script_extensions, &scx, Extensions.apply);
    try scx.assigned.expectComplete();

    for (0..code_point_count) |i| {
        const code_point: u21 = @intCast(i);
        const p = try unicode.lookup(code_point);
        const expected_scx: []const unicode.Script = if (scx.index[i] == unlisted) sc[i .. i + 1] else scx.sets.items[scx.index[i]];
        if (p.gc != gc[i] or p.sc != sc[i] or p.bc != bc[i] or p.jt != jt[i] or p.insc != insc[i] or p.inpc != inpc[i] or
            !std.mem.eql(unicode.Script, p.scx, expected_scx))
        {
            std.debug.print("U+{X:0>4}: lookup {any}, reference gc={t} sc={t} scx={any} bc={t} jt={t} InSC={t} InPC={t}\n", .{
                code_point, p, gc[i], sc[i], expected_scx, bc[i], jt[i], insc[i], inpc[i],
            });
            return error.TestUnexpectedResult;
        }
    }
}

test "FP-0108 case 7: lookup equals an independent parse of the embedded grapheme property files for every code point" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const gcb = try dense(unicode.GraphemeClusterBreak, arena, "GCB", files.grapheme_break);
    const incb = try selected(unicode.IndicConjunctBreak, arena, "InCB", files.derived_core);
    const ext_pict = try binary(arena, "Extended_Pictographic", files.emoji_data);

    for (0..code_point_count) |i| {
        const code_point: u21 = @intCast(i);
        const p = try unicode.lookup(code_point);
        if (p.gcb != gcb[i] or p.incb != incb[i] or p.ext_pict != ext_pict[i]) {
            std.debug.print("U+{X:0>4}: lookup GCB={t} InCB={t} ExtPict={}, reference GCB={t} InCB={t} ExtPict={}\n", .{
                code_point, p.gcb, p.incb, p.ext_pict, gcb[i], incb[i], ext_pict[i],
            });
            return error.TestUnexpectedResult;
        }
    }
}
