//! Checks that the build runs around `fairpane-lab`.
//!
//! `check minimal <case>` confirms for FP-0007 contract case 14 that the minimized case keeps the `fail` outcome
//! on `document_state`, keeps no resource, and has a 1-minimal document body: removing any single byte changes the outcome.
//! `check empty <directory>` confirms for FP-0007 contract case 14 that a refused minimization wrote nothing into its output directory.
//! `check same <expected> <actual>` confirms for FP-0054 contract cases 5 and revision 1 cases 1 to 3 that a refused command left its input unchanged.
//! `check fresh <directory> <layout> [<fixture>]` replaces `directory` with a new directory for one FP-0054 revision 1 case:
//! `case` holds a copy of the fixture as `case.json`, `link` adds `link.json` as a hard link to it,
//! `copy` adds `other.json` as a separate copy, and `oversized` holds `case.json` of `case_size_limit + 1` bytes
//! and `transcript.json` of `transcript_size_limit + 1` bytes, both extended without writing data.
//! `check derived <case> <minimized>` confirms for FP-0054 revision 1 case 4 that `minimized` is a version 2 case
//! derived from the digest of `case`.
//! `check absent <path>` confirms that nothing exists at `path`.
//! `check remove <path>...` removes each file.

const builtin = @import("builtin");
const std = @import("std");
const lab = @import("lab");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 3 and std.mem.eql(u8, args[1], "minimal")) return checkMinimal(init.io, init.gpa, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "empty")) return checkEmpty(init.io, args[2]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "same")) return checkSame(init.io, init.gpa, args[2], args[3]);
    if (args.len >= 4 and args.len <= 5 and std.mem.eql(u8, args[1], "fresh")) {
        const layout = std.meta.stringToEnum(Layout, args[3]) orelse return usage();
        if ((layout == .oversized) != (args.len == 4)) return usage();
        return fresh(init.io, init.gpa, args[2], layout, if (args.len == 5) args[4] else "");
    }
    if (args.len == 4 and std.mem.eql(u8, args[1], "derived")) return checkDerived(init.io, init.gpa, args[2], args[3]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "absent")) return checkAbsent(init.io, args[2]);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "remove")) return remove(init.io, args[2..]);
    return usage();
}

fn usage() u8 {
    std.debug.print(
        \\usage: check minimal <case> | check empty <directory> | check same <expected> <actual>
        \\       check fresh <directory> case|link|copy <fixture> | check fresh <directory> oversized
        \\       check derived <case> <minimized> | check absent <path> | check remove <path>...
        \\
    , .{});
    return 2;
}

fn checkMinimal(io: Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    const bytes = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(lab.case_size_limit));
    defer gpa.free(bytes);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diagnostic: lab.Detail = undefined;
    const case = lab.parseCase(arena.allocator(), bytes, &diagnostic) catch |err| {
        std.debug.print("the minimized case does not parse: {t}: {f}\n", .{ err, diagnostic });
        return 1;
    };
    const signature = try lab.signatureOf(gpa, &case);
    const expected: lab.Signature = .{ .result = .fail, .stage = .fetch, .check = .document_state };
    if (!signature.eql(expected)) {
        std.debug.print("the minimized case does not fail the document_state check\n", .{});
        return 1;
    }
    if (case.resources.len != 0) {
        std.debug.print("the minimized case keeps {d} resources that its outcome does not need\n", .{case.resources.len});
        return 1;
    }
    const body = case.document.body orelse {
        std.debug.print("the minimized case has no document body\n", .{});
        return 1;
    };
    // The outcome holds exactly while the body exceeds the response body limit.
    if (body.len != case.limits.max_response_body_bytes + 1) {
        std.debug.print("the minimized body has {d} bytes, not {d}\n", .{ body.len, case.limits.max_response_body_bytes + 1 });
        return 1;
    }
    const scratch = try arena.allocator().alloc(u8, body.len - 1);
    var candidate = case;
    for (0..body.len) |index| {
        @memcpy(scratch[0..index], body[0..index]);
        @memcpy(scratch[index..], body[index + 1 ..]);
        candidate.document.body = scratch;
        if ((try lab.signatureOf(gpa, &candidate)).eql(signature)) {
            std.debug.print("removing byte {d} keeps the outcome, so the body is not 1-minimal\n", .{index});
            return 1;
        }
    }
    var stdout_buffer: [128]u8 = undefined;
    var stdout = Io.File.stdout().writerStreaming(io, &stdout_buffer);
    try stdout.interface.print("the {d}-byte minimized body is 1-minimal\n", .{body.len});
    try stdout.interface.flush();
    return 0;
}

fn checkEmpty(io: Io, path: []const u8) !u8 {
    var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var entries = dir.iterate();
    if (try entries.next(io)) |entry| {
        std.debug.print("the refused minimization wrote {s}\n", .{entry.name});
        return 1;
    }
    return 0;
}

fn checkSame(io: Io, gpa: std.mem.Allocator, expected_path: []const u8, actual_path: []const u8) !u8 {
    const expected = try Io.Dir.cwd().readFileAlloc(io, expected_path, gpa, .limited(lab.case_size_limit));
    defer gpa.free(expected);
    const actual = try Io.Dir.cwd().readFileAlloc(io, actual_path, gpa, .limited(lab.case_size_limit));
    defer gpa.free(actual);
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("{s} changed: {d} bytes, expected {d} bytes\n", .{ actual_path, actual.len, expected.len });
        return 1;
    }
    return 0;
}

const Layout = enum { case, link, copy, oversized };

/// Replaces `directory` with a new directory that holds the files of `layout`, so a run never reuses an earlier run's files.
fn fresh(io: Io, gpa: std.mem.Allocator, directory: []const u8, layout: Layout, fixture: []const u8) !u8 {
    const cwd = Io.Dir.cwd();
    try cwd.deleteTree(io, directory);
    try cwd.createDirPath(io, directory);
    var dir = try cwd.openDir(io, directory, .{});
    defer dir.close(io);
    switch (layout) {
        .case => try cwd.copyFile(fixture, dir, "case.json", io, .{}),
        .link => {
            try cwd.copyFile(fixture, dir, "case.json", io, .{});
            try hardLink(io, gpa, directory, "case.json", "link.json");
        },
        .copy => {
            try cwd.copyFile(fixture, dir, "case.json", io, .{});
            try cwd.copyFile(fixture, dir, "other.json", io, .{});
        },
        .oversized => {
            try extend(io, dir, "case.json", lab.case_size_limit + 1);
            try extend(io, dir, "transcript.json", lab.transcript_size_limit + 1);
        },
    }
    return 0;
}

/// Creates `link` in `directory` as a second name of the existing file `target` in `directory`.
/// The pinned `Io.Dir.hardLink` returns `error.OperationUnsupported` on Windows, so Windows calls `CreateHardLinkW`,
/// which resolves both paths against the current directory, as `directory` is.
fn hardLink(io: Io, gpa: std.mem.Allocator, directory: []const u8, target: []const u8, link: []const u8) !void {
    const target_path = try Io.Dir.path.join(gpa, &.{ directory, target });
    defer gpa.free(target_path);
    const link_path = try Io.Dir.path.join(gpa, &.{ directory, link });
    defer gpa.free(link_path);
    if (builtin.os.tag != .windows) return Io.Dir.cwd().hardLink(target_path, .cwd(), link_path, io, .{});
    const target_wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, target_path);
    defer gpa.free(target_wide);
    const link_wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, link_path);
    defer gpa.free(link_wide);
    if (!CreateHardLinkW(link_wide, target_wide, null).toBool()) {
        std.debug.print("CreateHardLinkW failed with Win32 error {d}\n", .{@backingInt(std.os.windows.GetLastError())});
        return error.HardLinkFailed;
    }
}

extern "kernel32" fn CreateHardLinkW(
    lpFileName: [*:0]const u16,
    lpExistingFileName: [*:0]const u16,
    lpSecurityAttributes: ?*std.os.windows.SECURITY_ATTRIBUTES,
) callconv(.winapi) std.os.windows.BOOL;

/// Creates the file `name` with `length` bytes without writing any data.
fn extend(io: Io, dir: Io.Dir, name: []const u8, length: u64) !void {
    const file = try dir.createFile(io, name, .{});
    defer file.close(io);
    try file.setLength(io, length);
}

fn checkDerived(io: Io, gpa: std.mem.Allocator, case_path: []const u8, minimized_path: []const u8) !u8 {
    const original = try Io.Dir.cwd().readFileAlloc(io, case_path, gpa, .limited(lab.case_size_limit));
    defer gpa.free(original);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(original, &digest, .{});
    const bytes = try Io.Dir.cwd().readFileAlloc(io, minimized_path, gpa, .limited(lab.case_size_limit));
    defer gpa.free(bytes);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diagnostic: lab.Detail = undefined;
    const case = lab.parseCase(arena.allocator(), bytes, &diagnostic) catch |err| {
        std.debug.print("{s} does not parse: {t}: {f}\n", .{ minimized_path, err, diagnostic });
        return 1;
    };
    const derived = case.derived_from orelse {
        std.debug.print("{s} is not a version 2 case\n", .{minimized_path});
        return 1;
    };
    if (!std.mem.eql(u8, &derived.case_sha256, &digest)) {
        std.debug.print("{s} names a derived_from.case_sha256 other than the digest of {s}\n", .{ minimized_path, case_path });
        return 1;
    }
    return 0;
}

fn checkAbsent(io: Io, path: []const u8) !u8 {
    _ = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => |e| return e,
    };
    std.debug.print("{s} exists\n", .{path});
    return 1;
}

fn remove(io: Io, paths: []const [:0]const u8) !u8 {
    for (paths) |path| try Io.Dir.cwd().deleteFile(io, path);
    return 0;
}
