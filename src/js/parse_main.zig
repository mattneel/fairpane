//! `fairpane-js-parse`: parses one UTF-8 file with the FP-0082 parser, or runs the parse census.
//!
//! `file <path>` writes the outcome line and exits with status 0 for a script, 1 for a syntax error,
//! 2 for an unsupported outcome, 3 for an input or usage error, and 4 for a limit.
//! `census <root> <out.jsonl>` runs the census of an extracted Test262 tree.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const parser = @import("parser.zig");
const census = @import("parse_census.zig");
const web_string = @import("../web_string.zig");

const usage = "usage: fairpane-js-parse file <path>\n       fairpane-js-parse census <root> <out.jsonl>\n";
const input_status: u8 = 3;

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr = Io.File.stderr().writerStreaming(io, &stderr_buffer);
    defer stderr.interface.flush() catch {};
    var stdout_buffer: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch {
        stderr.interface.writeAll("fairpane-js-parse: out of memory\n") catch {};
        return input_status;
    };
    const status = if (args.len == 3 and std.mem.eql(u8, args[1], "file"))
        parseFile(io, init.gpa, args[2], &stdout.interface, &stderr.interface)
    else if (args.len == 4 and std.mem.eql(u8, args[1], "census"))
        census.run(io, init.gpa, args[2], args[3], &stdout.interface, &stderr.interface)
    else blk: {
        stderr.interface.writeAll(usage) catch {};
        break :blk input_status;
    };
    stdout.interface.flush() catch return input_status;
    return status;
}

fn parseFile(io: Io, gpa: Allocator, path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) u8 {
    const bytes = Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited) catch |err| {
        stderr.print("fairpane-js-parse: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return input_status;
    };
    defer gpa.free(bytes);
    var source = web_string.WebString.fromUtf8(gpa, bytes) catch |err| {
        stderr.print("fairpane-js-parse: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return input_status;
    };
    defer source.deinit(gpa);
    var parse = parser.parseScript(gpa, source.units, .{}) catch {
        stderr.print("fairpane-js-parse: {s}: OutOfMemory\n", .{path}) catch {};
        return input_status;
    };
    defer parse.deinit();
    parser.writeOutcome(&parse, stdout) catch |err| {
        stderr.print("fairpane-js-parse: {s}: {s}\n", .{ path, @errorName(err) }) catch {};
        return input_status;
    };
    stdout.writeByte('\n') catch return input_status;
    return switch (parse.outcome) {
        .script => 0,
        .diagnostic => |diagnostic| switch (diagnostic) {
            .syntax_error => 1,
            .unsupported => 2,
            .limit => 4,
        },
    };
}
