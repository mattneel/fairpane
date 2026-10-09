//! The Test262 frontmatter reader of the FP-0082 census.
//!
//! The frontmatter is the text from the first `/*---` to the next `---*/`. The reader handles a
//! YAML subset: top-level keys start at column 0; `flags`, `features`, and `includes` take a flow
//! list `[a, b]` or block items `  - a`; `negative` takes indented `phase:` and `type:` lines; a `#`
//! comment is stripped; other keys are skipped with their indented continuation lines.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// The flags of `INTERPRETING.md`, "Metadata".
pub const Flags = packed struct {
    only_strict: bool = false,
    no_strict: bool = false,
    module: bool = false,
    raw: bool = false,
    async: bool = false,
    generated: bool = false,
    can_block_is_false: bool = false,
    can_block_is_true: bool = false,
    non_deterministic: bool = false,
};

const flag_names = [_]struct { []const u8, []const u8 }{
    .{ "onlyStrict", "only_strict" },
    .{ "noStrict", "no_strict" },
    .{ "module", "module" },
    .{ "raw", "raw" },
    .{ "async", "async" },
    .{ "generated", "generated" },
    .{ "CanBlockIsFalse", "can_block_is_false" },
    .{ "CanBlockIsTrue", "can_block_is_true" },
    .{ "non-deterministic", "non_deterministic" },
};

pub const Phase = enum { parse, resolution, runtime };

pub const Negative = struct { phase: Phase, type: []const u8 };

pub const Metadata = struct {
    flags: Flags = .{},
    features: []const []const u8 = &.{},
    includes: []const []const u8 = &.{},
    negative: ?Negative = null,
};

/// The metadata, or the reason that it is a metadata error.
pub const Result = union(enum) { metadata: Metadata, metadata_error: []const u8 };

const List = enum { flags, features, includes };

/// Reads the frontmatter of `text`. The result refers to `text` and to memory from `arena`.
pub fn read(arena: Allocator, text: []const u8) Allocator.Error!Result {
    const open = std.mem.indexOf(u8, text, "/*---") orelse return .{ .metadata_error = "missing frontmatter" };
    const close = std.mem.indexOfPos(u8, text, open + 5, "---*/") orelse return .{ .metadata_error = "missing frontmatter" };
    var reader: Reader = .{ .arena = arena };
    var lines = std.mem.splitScalar(u8, text[open + 5 .. close], '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (try reader.readLine(line)) |reason| return .{ .metadata_error = reason };
    }
    return reader.finish();
}

const Reader = struct {
    arena: Allocator,
    metadata: Metadata = .{},
    keys: std.ArrayList([]const u8) = .empty,
    /// The key whose indented lines follow.
    mode: union(enum) { skip, list: List, negative } = .skip,
    items: std.ArrayList([]const u8) = .empty,
    phase: ?[]const u8 = null,
    negative_type: ?[]const u8 = null,
    has_negative: bool = false,

    /// Returns the reason for a metadata error in `line`, or null.
    fn readLine(reader: *Reader, line: []const u8) Allocator.Error!?[]const u8 {
        if (std.mem.trim(u8, line, " \t").len == 0) return null;
        if (line[0] != ' ' and line[0] != '\t') {
            if (line[0] == '#') return null;
            if (try reader.endList()) |reason| return reason;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse return "a top-level line without a key";
            const key = line[0..colon];
            for (reader.keys.items) |seen| {
                if (std.mem.eql(u8, seen, key)) return "a duplicate key";
            }
            try reader.keys.append(reader.arena, key);
            const value = std.mem.trim(u8, stripComment(line[colon + 1 ..]), " \t");
            const list: ?List = if (std.mem.eql(u8, key, "flags")) .flags else if (std.mem.eql(u8, key, "features")) .features else if (std.mem.eql(u8, key, "includes")) .includes else null;
            if (list) |which| {
                if (value.len == 0) {
                    reader.mode = .{ .list = which };
                    return null;
                }
                if (value[0] != '[' or value[value.len - 1] != ']') return "an unreadable list";
                const inner = std.mem.trim(u8, value[1 .. value.len - 1], " \t");
                if (inner.len != 0) {
                    var entries = std.mem.splitScalar(u8, inner, ',');
                    while (entries.next()) |entry| {
                        const item = std.mem.trim(u8, entry, " \t");
                        if (item.len == 0) return "an unreadable list";
                        try reader.items.append(reader.arena, item);
                    }
                }
                reader.mode = .{ .list = which };
                return reader.endList();
            }
            if (std.mem.eql(u8, key, "negative")) {
                if (value.len != 0) return "an unreadable negative";
                reader.has_negative = true;
                reader.mode = .negative;
                return null;
            }
            reader.mode = .skip;
            return null;
        }
        const content = std.mem.trim(u8, stripComment(line), " \t");
        switch (reader.mode) {
            .skip => {},
            .list => {
                if (content.len == 0) return null;
                if (content[0] != '-') return "an unreadable list";
                const item = std.mem.trim(u8, content[1..], " \t");
                if (item.len == 0) return "an unreadable list";
                try reader.items.append(reader.arena, item);
            },
            .negative => {
                if (content.len == 0) return null;
                const colon = std.mem.indexOfScalar(u8, content, ':') orelse return "an unreadable negative";
                const key = std.mem.trim(u8, content[0..colon], " \t");
                const value = std.mem.trim(u8, content[colon + 1 ..], " \t");
                if (std.mem.eql(u8, key, "phase")) {
                    if (reader.phase != null) return "a duplicate key";
                    reader.phase = value;
                } else if (std.mem.eql(u8, key, "type")) {
                    if (reader.negative_type != null) return "a duplicate key";
                    reader.negative_type = value;
                }
            },
        }
        return null;
    }

    /// Stores the items of a finished list.
    fn endList(reader: *Reader) Allocator.Error!?[]const u8 {
        const which = switch (reader.mode) {
            .list => |list| list,
            else => return null,
        };
        reader.mode = .skip;
        const items = try reader.items.toOwnedSlice(reader.arena);
        switch (which) {
            .features => reader.metadata.features = items,
            .includes => reader.metadata.includes = items,
            .flags => for (items) |item| {
                for (flag_names) |flag| {
                    if (std.mem.eql(u8, item, flag[0])) {
                        inline for (comptime std.meta.fieldNames(Flags)) |field_name| {
                            if (std.mem.eql(u8, field_name, flag[1])) @field(reader.metadata.flags, field_name) = true;
                        }
                        break;
                    }
                } else return "a flag outside the known set";
            },
        }
        return null;
    }

    fn finish(reader: *Reader) Allocator.Error!Result {
        if (try reader.endList()) |reason| return .{ .metadata_error = reason };
        if (reader.has_negative) {
            const phase_text = reader.phase orelse return .{ .metadata_error = "a negative without a phase" };
            const phase = std.meta.stringToEnum(Phase, phase_text) orelse return .{ .metadata_error = "a phase outside the known set" };
            reader.metadata.negative = .{ .phase = phase, .type = reader.negative_type orelse return .{ .metadata_error = "a negative without a type" } };
        }
        return .{ .metadata = reader.metadata };
    }
};

/// Removes a `#` comment that starts the text or follows white space.
fn stripComment(text: []const u8) []const u8 {
    for (text, 0..) |byte, index| {
        if (byte == '#' and (index == 0 or text[index - 1] == ' ' or text[index - 1] == '\t')) return text[0..index];
    }
    return text;
}

// Tests.

fn frontmatter(comptime body: []const u8) []const u8 {
    return "// Copyright\n/*---\n" ++ body ++ "---*/\nvar a;\n";
}

fn readTest(arena: Allocator, text: []const u8) !Metadata {
    return switch (try read(arena, text)) {
        .metadata => |metadata| metadata,
        .metadata_error => |reason| {
            std.debug.print("unexpected metadata error: {s}\n", .{reason});
            return error.TestUnexpectedResult;
        },
    };
}

fn expectMetadataError(arena: Allocator, text: []const u8) !void {
    try testing.expect(try read(arena, text) == .metadata_error);
}

test "FP-0082 case 15: the metadata reader reads its YAML subset and reports metadata errors" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const flow = try readTest(arena, frontmatter("flags: [onlyStrict, raw] # x\n"));
    try testing.expectEqual(Flags{ .only_strict = true, .raw = true }, flow.flags);

    const block = try readTest(arena, frontmatter("flags:\n  - module\n"));
    try testing.expectEqual(Flags{ .module = true }, block.flags);

    const negative = try readTest(arena, frontmatter("negative:\n  type: SyntaxError\n  phase: parse\n"));
    try testing.expectEqual(Phase.parse, negative.negative.?.phase);
    try testing.expectEqualStrings("SyntaxError", negative.negative.?.type);

    const lists = try readTest(arena, frontmatter("includes: [propertyHelper.js]\nfeatures: [Symbol.toPrimitive, regexp-v-flag]\n"));
    try testing.expectEqual(@as(usize, 1), lists.includes.len);
    try testing.expectEqualStrings("propertyHelper.js", lists.includes[0]);
    try testing.expectEqual(@as(usize, 2), lists.features.len);
    try testing.expectEqualStrings("Symbol.toPrimitive", lists.features[0]);
    try testing.expectEqualStrings("regexp-v-flag", lists.features[1]);

    const description = try readTest(arena, frontmatter("description: |\n  The text names\n  flags: [raw]\n  as an example.\n"));
    try testing.expectEqual(Flags{}, description.flags);
    try testing.expectEqual(@as(?Negative, null), description.negative);

    try expectMetadataError(arena, frontmatter("flags: [bogus]\n"));
    try expectMetadataError(arena, frontmatter("flags: [raw]\nflags: [module]\n"));
    try expectMetadataError(arena, frontmatter("negative:\n  phase: compile\n"));
    try expectMetadataError(arena, "// Copyright\nvar a;\n");
}
