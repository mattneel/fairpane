//! The FP-0082 parse-only census over an extracted Test262 tree.
//!
//! The census parses each discovered file and compares the outcome with the file's metadata. It
//! executes no test, so its counts are a soundness check of the parser, not a Test262 result.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const metadata = @import("test262_metadata.zig");
const web_string = @import("../web_string.zig");

/// The exit status of a census whose inputs or output cannot be used.
pub const input_status: u8 = 3;

const strict_prefix = "\"use strict\";\n";

pub const Class = enum {
    agree_valid,
    agree_error,
    unsupported,
    limit,
    proposal_mismatch,
    false_accept,
    false_syntax_error,
};

pub const Summary = struct {
    discovered: u64 = 0,
    module: u64 = 0,
    proposal_files: u64 = 0,
    runs: u64 = 0,
    agree_valid: u64 = 0,
    agree_error: u64 = 0,
    unsupported: u64 = 0,
    limit: u64 = 0,
    proposal_mismatch: u64 = 0,
    false_accept: u64 = 0,
    false_syntax_error: u64 = 0,
    metadata_error: u64 = 0,
    input_error: u64 = 0,

    fn count(summary: *Summary, class: Class) void {
        switch (class) {
            inline else => |tag| @field(summary, @tagName(tag)) += 1,
        }
    }

    fn sound(summary: Summary) bool {
        return summary.false_accept == 0 and summary.false_syntax_error == 0 and summary.metadata_error == 0 and summary.input_error == 0;
    }
};

/// Classifies one run from whether a syntax error is expected and from the parse outcome.
pub fn classify(expect_error: bool, proposal: bool, outcome: @FieldType(parser.Parse, "outcome")) Class {
    const class: Class = switch (outcome) {
        .script => if (expect_error) .false_accept else .agree_valid,
        .diagnostic => |diagnostic| switch (diagnostic) {
            .syntax_error => if (expect_error) .agree_error else .false_syntax_error,
            .unsupported => .unsupported,
            .limit => .limit,
        },
    };
    if (proposal and (class == .false_accept or class == .false_syntax_error)) return .proposal_mismatch;
    return class;
}

/// Runs the census of `root` and writes the per-file records to `out_path`, which must not exist.
/// Returns the exit status: 0 for a sound census, 1 for a census with violations, and 3 for unusable inputs.
pub fn run(io: Io, gpa: Allocator, root: []const u8, out_path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) u8 {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    return runWithArena(io, gpa, arena, root, out_path, stdout, stderr) catch |err| {
        stderr.print("fairpane-js-parse: census: {s}\n", .{@errorName(err)}) catch {};
        return input_status;
    };
}

fn runWithArena(io: Io, gpa: Allocator, arena: Allocator, root: []const u8, out_path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) !u8 {
    var root_dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer root_dir.close(io);
    const commit = commitOf(io, arena, root_dir) catch |err| {
        try stderr.print("fairpane-js-parse: census: EXTRACT.json: {s}\n", .{@errorName(err)});
        return input_status;
    };
    const proposals = proposalFeatures(io, arena, root_dir) catch |err| {
        try stderr.print("fairpane-js-parse: census: features.txt: {s}\n", .{@errorName(err)});
        return input_status;
    };
    const paths = try discover(io, arena, root_dir);
    const out_file = Io.Dir.cwd().createFile(io, out_path, .{ .exclusive = true }) catch |err| {
        try stderr.print("fairpane-js-parse: census: cannot create {s}: {s}\n", .{ out_path, @errorName(err) });
        return input_status;
    };
    defer out_file.close(io);
    var out_buffer: [64 * 1024]u8 = undefined;
    var out_writer = out_file.writer(io, &out_buffer);
    const records = &out_writer.interface;

    try stdout.print("{{\"format\":\"fairpane-js-parse-census\",\"version\":1,\"commit\":", .{});
    try writeJsonString(stdout, commit);
    try stdout.writeAll("}\n");

    var summary: Summary = .{};
    var by_code = std.enums.EnumArray(parser.UnsupportedCode, u64).initFill(0);
    summary.discovered = paths.len;
    for (paths) |path| {
        try censusFile(io, gpa, root_dir, path, proposals, &summary, &by_code, records, stdout);
    }
    try records.flush();

    try stdout.print("{{\"summary\":{{", .{});
    inline for (comptime std.meta.fieldNames(Summary), 0..) |field_name, index| {
        if (index != 0) try stdout.writeByte(',');
        try stdout.print("\"{s}\":{d}", .{ field_name, @field(summary, field_name) });
    }
    try stdout.writeAll("},\"unsupported_by_code\":{");
    var first = true;
    // The codes are written in byte order of their names.
    var names: [std.enums.values(parser.UnsupportedCode).len]parser.UnsupportedCode = undefined;
    @memcpy(&names, std.enums.values(parser.UnsupportedCode));
    std.mem.sort(parser.UnsupportedCode, &names, {}, struct {
        fn less(_: void, a: parser.UnsupportedCode, b: parser.UnsupportedCode) bool {
            return std.mem.order(u8, @tagName(a), @tagName(b)) == .lt;
        }
    }.less);
    for (names) |code| {
        const value = by_code.get(code);
        if (value == 0) continue;
        if (!first) try stdout.writeByte(',');
        first = false;
        try stdout.print("\"{s}\":{d}", .{ @tagName(code), value });
    }
    try stdout.writeAll("}}\n");
    return if (summary.sound()) 0 else 1;
}

fn censusFile(
    io: Io,
    gpa: Allocator,
    root_dir: Io.Dir,
    path: []const u8,
    proposals: []const []const u8,
    summary: *Summary,
    by_code: *std.enums.EnumArray(parser.UnsupportedCode, u64),
    records: *Io.Writer,
    stdout: *Io.Writer,
) !void {
    var file_arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer file_arena_state.deinit();
    const file_arena = file_arena_state.allocator();
    const bytes = root_dir.readFileAlloc(io, path, file_arena, .unlimited) catch |err| {
        summary.input_error += 1;
        try writeFileProblem(records, stdout, path, "input_error", @errorName(err));
        return;
    };
    const read = try metadata.read(file_arena, bytes);
    const data = switch (read) {
        .metadata => |data| data,
        .metadata_error => |reason| {
            summary.metadata_error += 1;
            try writeFileProblem(records, stdout, path, "metadata_error", reason);
            return;
        },
    };
    if (data.flags.module) {
        summary.module += 1;
        try records.writeAll("{\"path\":");
        try writeJsonString(records, path);
        try records.writeAll(",\"module\":true}\n");
        return;
    }
    const proposal = for (data.features) |feature| {
        if (contains(proposals, feature)) break true;
    } else false;
    if (proposal) summary.proposal_files += 1;
    const source = web_string.WebString.fromUtf8(file_arena, bytes) catch |err| {
        summary.input_error += 1;
        try writeFileProblem(records, stdout, path, "input_error", @errorName(err));
        return;
    };
    const expect_error = if (data.negative) |negative| negative.phase == .parse else false;
    const strict_run = !data.flags.no_strict and !data.flags.raw;
    const sloppy_run = !data.flags.only_strict;
    try records.writeAll("{\"path\":");
    try writeJsonString(records, path);
    try records.print(",\"proposal\":{},\"expect\":\"{s}\",\"runs\":[", .{ proposal, if (expect_error) "syntax-error" else "valid" });
    var first = true;
    for ([_]bool{ false, true }) |strict| {
        if (strict and !strict_run) continue;
        if (!strict and !sloppy_run) continue;
        const units = if (strict) try std.mem.concat(file_arena, u16, &.{ comptime asUnits(strict_prefix), source.units }) else source.units;
        var parse = try parser.parseScript(gpa, units, .{});
        defer parse.deinit();
        const class = classify(expect_error, proposal, parse.outcome);
        summary.runs += 1;
        summary.count(class);
        if (class == .unsupported) {
            const code = parse.outcome.diagnostic.unsupported.code;
            by_code.set(code, by_code.get(code) + 1);
        }
        const mode = if (strict) "strict" else "non-strict";
        if (!first) try records.writeByte(',');
        first = false;
        try records.print("{{\"mode\":\"{s}\",\"class\":\"{s}\",\"outcome\":\"", .{ mode, @tagName(class) });
        try writeOutcomeText(records, &parse);
        try records.writeAll("\"}");
        if (class == .false_accept or class == .false_syntax_error) {
            try stdout.print("{{\"violation\":\"{s}\",\"path\":", .{@tagName(class)});
            try writeJsonString(stdout, path);
            try stdout.print(",\"mode\":\"{s}\",\"outcome\":\"", .{mode});
            try writeOutcomeText(stdout, &parse);
            try stdout.writeAll("\"}\n");
        }
    }
    try records.writeAll("]}\n");
}

/// Writes the outcome line, or `script` for a script, which contains no character that JSON escapes.
fn writeOutcomeText(writer: *Io.Writer, parse: *const parser.Parse) !void {
    switch (parse.outcome) {
        .script => try writer.writeAll("script"),
        .diagnostic => |diagnostic| try parser.writeDiagnostic(diagnostic, writer),
    }
}

/// Writes the record and the violation line of a file that has a metadata error or an input error.
fn writeFileProblem(records: *Io.Writer, stdout: *Io.Writer, path: []const u8, kind: []const u8, reason: []const u8) !void {
    try records.writeAll("{\"path\":");
    try writeJsonString(records, path);
    try records.print(",\"{s}\":", .{kind});
    try writeJsonString(records, reason);
    try records.writeAll("}\n");
    try stdout.print("{{\"violation\":\"{s}\",\"path\":", .{kind});
    try writeJsonString(stdout, path);
    try stdout.writeAll(",\"reason\":");
    try writeJsonString(stdout, reason);
    try stdout.writeAll("}\n");
}

fn asUnits(comptime text: []const u8) []const u16 {
    comptime {
        var units: [text.len]u16 = undefined;
        for (text, 0..) |byte, index| units[index] = byte;
        const final = units;
        return &final;
    }
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

pub fn writeJsonString(writer: *Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0...0x1F => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

/// Reads the `commit` of `EXTRACT.json`.
fn commitOf(io: Io, arena: Allocator, root_dir: Io.Dir) ![]const u8 {
    const text = try root_dir.readFileAlloc(io, "EXTRACT.json", arena, .limited(1024 * 1024));
    const record = try std.json.parseFromSliceLeaky(struct { commit: []const u8 }, arena, text, .{ .ignore_unknown_fields = true });
    if (record.commit.len != 40) return error.InvalidCommit;
    for (record.commit) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) return error.InvalidCommit;
    }
    return record.commit;
}

/// The features that the "Proposed language features" section of `features.txt` lists.
fn proposalFeatures(io: Io, arena: Allocator, root_dir: Io.Dir) ![]const []const u8 {
    const text = try root_dir.readFileAlloc(io, "features.txt", arena, .limited(1024 * 1024));
    var features: std.ArrayList([]const u8) = .empty;
    var section: enum { before, proposals, after } = .before;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.eql(u8, line, "## Proposed language features")) {
            if (section != .before) return error.InvalidFeatures;
            section = .proposals;
            continue;
        }
        if (std.mem.eql(u8, line, "## Standard language features")) {
            if (section != .proposals) return error.InvalidFeatures;
            section = .after;
            continue;
        }
        if (section != .proposals or line.len == 0 or line[0] == '#') continue;
        try features.append(arena, line);
    }
    if (section != .after) return error.InvalidFeatures;
    return features.toOwnedSlice(arena);
}

/// The files under `test/` that `TEST262_RULE` of `tools/corpus.mjs` discovers, as paths with `/`
/// relative to the root, in order of their bytes.
fn discover(io: Io, arena: Allocator, root_dir: Io.Dir) ![]const []const u8 {
    var test_dir = try root_dir.openDir(io, "test", .{ .iterate = true });
    defer test_dir.close(io);
    var walker = try test_dir.walk(arena);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".js")) continue;
        if (std.mem.indexOf(u8, entry.basename, "_FIXTURE") != null) continue;
        const path = try std.mem.concat(arena, u8, &.{ "test/", entry.path });
        std.mem.replaceScalar(u8, path, '\\', '/');
        try paths.append(arena, path);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return paths.toOwnedSlice(arena);
}
