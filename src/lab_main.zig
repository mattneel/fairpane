//! The `fairpane-lab` command line.
//!
//! Each command reads only the files named on its command line, opens no network connection,
//! and writes one JSON document to standard output.
//! `run --transcript` and `minimize --out` refuse an output path that names the input file.
//! The exit status is 0 for `pass`, 1 for `fail`, 2 for `unsupported`, 3 for `harness-error`, and 4 for `timeout`.
//! A usage error exits with status 64 and writes no result.

const std = @import("std");
const lab = @import("lab.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage =
    \\usage: fairpane-lab run <case> [--transcript <path>]
    \\       fairpane-lab replay <transcript>
    \\       fairpane-lab minimize <case> --out <path>
    \\
;

const usage_status: u8 = 64;

const same_file: lab.Detail = .{ .subject = "command line", .message = "the output path names the input file" };

const Command = union(enum) {
    run: struct { case: []const u8, transcript: ?[]const u8 },
    replay: struct { transcript: []const u8 },
    minimize: struct { case: []const u8, out: []const u8 },
};

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch {
        Io.File.stderr().writeStreamingAll(io, "fairpane-lab: out of memory\n") catch {};
        return lab.Result.harness_error.exitStatus();
    };
    const command = parseCommand(args) orelse {
        Io.File.stderr().writeStreamingAll(io, usage) catch {};
        return usage_status;
    };
    return switch (command) {
        .run => |run| runCommand(io, init.gpa, run.case, run.transcript),
        .replay => |replay| replayCommand(io, init.gpa, replay.transcript),
        .minimize => |minimize| minimizeCommand(io, init.gpa, minimize.case, minimize.out),
    };
}

/// Returns the command, or null for a usage error.
fn parseCommand(args: []const [:0]const u8) ?Command {
    if (args.len < 2) return null;
    const name = args[1];
    const rest = args[2..];
    if (std.mem.eql(u8, name, "replay")) {
        if (rest.len != 1 or isOption(rest[0])) return null;
        return .{ .replay = .{ .transcript = rest[0] } };
    }
    const option = if (std.mem.eql(u8, name, "run"))
        "--transcript"
    else if (std.mem.eql(u8, name, "minimize"))
        "--out"
    else
        return null;
    var case: ?[]const u8 = null;
    var value: ?[]const u8 = null;
    var index: usize = 0;
    while (index < rest.len) : (index += 1) {
        const arg = rest[index];
        if (std.mem.eql(u8, arg, option)) {
            if (value != null or index + 1 == rest.len) return null;
            index += 1;
            value = rest[index];
        } else if (isOption(arg) or case != null) {
            return null;
        } else {
            case = arg;
        }
    }
    const case_path = case orelse return null;
    if (std.mem.eql(u8, name, "run")) return .{ .run = .{ .case = case_path, .transcript = value } };
    return .{ .minimize = .{ .case = case_path, .out = value orelse return null } };
}

fn isOption(arg: []const u8) bool {
    return std.mem.startsWith(u8, arg, "--");
}

fn runCommand(io: Io, gpa: Allocator, case_path: []const u8, transcript_path: ?[]const u8) u8 {
    var run = start: {
        if (transcript_path) |path| {
            const refusal = refuseInputAsOutput(io, gpa, .{ .path = case_path, .subject = "case file" }, .{ .path = path, .subject = "transcript file" });
            if (refusal) |detail| break :start lab.Run.initHarnessError(gpa, null, detail);
        }
        const bytes = lab.readInputFile(io, gpa, case_path, lab.case_size_limit) catch |err| {
            break :start lab.Run.initHarnessError(gpa, null, lab.fileFailure("case file", err));
        };
        defer gpa.free(bytes);
        break :start lab.runCase(gpa, bytes);
    };
    defer run.deinit();
    if (transcript_path) |path| {
        if (run.hasTranscript()) writeFile(io, path, &run, lab.Run.writeTranscript) catch |err| {
            run.outcome = .{ .result = .harness_error, .detail = lab.fileFailure("transcript file", err) };
        };
    }
    return writeStdout(io, &run, lab.Run.writeResult, run.outcome.result);
}

fn replayCommand(io: Io, gpa: Allocator, transcript_path: []const u8) u8 {
    var replay = start: {
        const bytes = lab.readInputFile(io, gpa, transcript_path, lab.transcript_size_limit) catch |err| {
            break :start lab.Replay.initHarnessError(gpa, lab.fileFailure("transcript file", err));
        };
        defer gpa.free(bytes);
        break :start lab.replay(gpa, bytes);
    };
    defer replay.deinit();
    return writeStdout(io, &replay, lab.Replay.writeResult, replay.outcome.result);
}

fn minimizeCommand(io: Io, gpa: Allocator, case_path: []const u8, out_path: []const u8) u8 {
    var minimization = start: {
        const refusal = refuseInputAsOutput(io, gpa, .{ .path = case_path, .subject = "case file" }, .{ .path = out_path, .subject = "output file" });
        if (refusal) |detail| break :start lab.Minimization.initHarnessError(gpa, null, detail);
        const bytes = lab.readInputFile(io, gpa, case_path, lab.case_size_limit) catch |err| {
            break :start lab.Minimization.initHarnessError(gpa, null, lab.fileFailure("case file", err));
        };
        defer gpa.free(bytes);
        break :start lab.minimize(gpa, bytes);
    };
    defer minimization.deinit();
    // A refused minimization writes nothing.
    if (minimization.outcome.result == .pass) {
        writeFile(io, out_path, minimization.output, writeBytes) catch |err| {
            minimization.outcome = .{ .result = .harness_error, .detail = lab.fileFailure("output file", err) };
        };
    }
    return writeStdout(io, &minimization, lab.Minimization.writeReport, minimization.outcome.result);
}

/// A file named on the command line and the subject that names it in a harness message.
const NamedFile = struct { path: []const u8, subject: []const u8 };

/// Returns the detail of a harness error when `output` names the `input` file or when that cannot be decided, and null otherwise.
/// Equal spellings name one file. When the output file exists, the canonical real paths of both files decide,
/// so different spellings of one file are refused. An output file that does not exist is not the input file.
fn refuseInputAsOutput(io: Io, gpa: Allocator, input: NamedFile, output: NamedFile) ?lab.Detail {
    if (std.mem.eql(u8, input.path, output.path)) return same_file;
    const cwd = Io.Dir.cwd();
    const output_real = cwd.realPathFileAlloc(io, output.path, gpa) catch |err| return switch (err) {
        error.FileNotFound => null,
        else => lab.fileFailure(output.subject, err),
    };
    defer gpa.free(output_real);
    const input_real = cwd.realPathFileAlloc(io, input.path, gpa) catch |err| return lab.fileFailure(input.subject, err);
    defer gpa.free(input_real);
    return if (std.mem.eql(u8, input_real, output_real)) same_file else null;
}

fn writeBytes(bytes: []const u8, writer: *Io.Writer) Io.Writer.Error!void {
    return writer.writeAll(bytes);
}

fn writeFile(io: Io, path: []const u8, context: anytype, comptime write: anytype) !void {
    const file = try Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [64 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    write(context, &file_writer.interface) catch return file_writer.err orelse error.WriteFailed;
    file_writer.interface.flush() catch return file_writer.err orelse error.WriteFailed;
}

/// Writes one result document to standard output and returns the exit status for `result`.
fn writeStdout(io: Io, context: anytype, comptime write: anytype, result: lab.Result) u8 {
    var buffer: [64 * 1024]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &buffer);
    write(context, &stdout.interface) catch return lab.Result.harness_error.exitStatus();
    stdout.interface.flush() catch return lab.Result.harness_error.exitStatus();
    return result.exitStatus();
}
