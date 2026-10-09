//! Checks that the build runs around `fairpane-lab`.
//!
//! `check minimal <case>` confirms for FP-0007 contract case 14 that the minimized case keeps the `fail` outcome
//! on `document_state`, keeps no resource, and has a 1-minimal document body: removing any single byte changes the outcome.
//! `check empty <directory>` confirms for FP-0007 contract case 14 that a refused minimization wrote nothing into its output directory.
//! `check same <expected> <actual>` confirms that a refused command left its input unchanged.
//! `check fresh <directory> <layout> [<fixture>]` replaces `directory` with a new directory for one case:
//! `case` holds a copy of the fixture as `case.json`, `link` adds `link.json` as a hard link to it,
//! `copy` adds `other.json` as a separate copy, `symlink` adds `link.json` as a symbolic link to `case.json`,
//! `unreadable` adds `out.json`, which the current user may write but not read, and `empty` holds no file.
//! `check readable <path>` gives the current user read access to a file that `unreadable` made.
//! `check derived <case> <minimized>` confirms that `minimized` is a version 2 case derived from the digest of `case`.
//! `check entries [<name>...]` confirms that the current directory holds exactly the named entries.
//! `check fifo <laboratory>` runs FP-0076 contract case 1 in the current directory, which holds `case.json`.
//! `check oversized <laboratory>` runs FP-0054 revision 1 case 5 in the current directory, which must be empty.

const builtin = @import("builtin");
const std = @import("std");
const lab = @import("lab");
const Io = std.Io;
const windows = std.os.windows;

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const io = init.io;
    const gpa = init.gpa;
    if (args.len == 3 and std.mem.eql(u8, args[1], "minimal")) return checkMinimal(io, gpa, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "empty")) return checkEmpty(io, args[2]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "same")) return checkSame(io, gpa, args[2], args[3]);
    if (args.len >= 4 and args.len <= 5 and std.mem.eql(u8, args[1], "fresh")) {
        const layout = std.meta.stringToEnum(Layout, args[3]) orelse return usage();
        if ((layout == .empty) != (args.len == 4)) return usage();
        return fresh(io, gpa, args[2], layout, if (args.len == 5) args[4] else "");
    }
    if (args.len == 3 and std.mem.eql(u8, args[1], "readable")) return makeReadable(io, gpa, args[2]);
    if (args.len == 4 and std.mem.eql(u8, args[1], "derived")) return checkDerived(io, gpa, args[2], args[3]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "entries")) return checkEntries(io, args[2..]);
    // A FIFO exists only on POSIX systems, so Windows builds omit the command.
    if (builtin.os.tag != .windows and args.len == 3 and std.mem.eql(u8, args[1], "fifo")) return checkFifo(io, gpa, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "oversized")) return checkOversized(io, gpa, args[2]);
    return usage();
}

fn usage() u8 {
    std.debug.print(
        \\usage: check minimal <case> | check empty <directory> | check same <expected> <actual>
        \\       check fresh <directory> case|link|copy|symlink|unreadable <fixture> | check fresh <directory> empty
        \\       check readable <path> | check derived <case> <minimized> | check entries [<name>...]
        \\       check fifo <laboratory> | check oversized <laboratory>
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

const Layout = enum { case, link, copy, symlink, unreadable, empty };

/// Replaces `directory` with a new directory that holds the files of `layout`, so a run never reuses an earlier run's files.
fn fresh(io: Io, gpa: std.mem.Allocator, directory: []const u8, layout: Layout, fixture: []const u8) !u8 {
    const cwd = Io.Dir.cwd();
    try cwd.deleteTree(io, directory);
    try cwd.createDirPath(io, directory);
    var dir = try cwd.openDir(io, directory, .{});
    defer dir.close(io);
    if (layout != .empty) try cwd.copyFile(fixture, dir, "case.json", io, .{});
    switch (layout) {
        .case, .empty => {},
        .link => try hardLink(io, gpa, directory, "case.json", "link.json"),
        .copy => try cwd.copyFile(fixture, dir, "other.json", io, .{}),
        .symlink => try dir.symLink(io, "case.json", "link.json", .{}),
        .unreadable => return makeUnreadable(io, gpa, directory, dir),
    }
    return 0;
}

/// Creates `out.json` in `dir`, which is `directory`, so that the current user may write it but not read it.
/// On POSIX systems its mode is 0200, which does not stop the root user, and on Windows its ACL denies read-data access to Everyone.
fn makeUnreadable(io: Io, gpa: std.mem.Allocator, directory: []const u8, dir: Io.Dir) !u8 {
    if (builtin.os.tag != .windows and std.posix.system.geteuid() == 0) {
        std.debug.print("case 2 needs a non-root user\n", .{});
        return 1;
    }
    const file = try dir.createFile(io, "out.json", .{});
    file.close(io);
    if (builtin.os.tag == .windows) {
        const path = try Io.Dir.path.join(gpa, &.{ directory, "out.json" });
        defer gpa.free(path);
        try setDacl(gpa, path, deny_read_data);
    } else {
        try dir.setFilePermissions(io, "out.json", .fromMode(0o200), .{});
    }
    // The case tests nothing unless reading the file actually fails.
    if (dir.openFile(io, "out.json", .{})) |readable| {
        readable.close(io);
        std.debug.print("out.json is still readable\n", .{});
        return 1;
    } else |err| switch (err) {
        error.AccessDenied => return 0,
        else => |e| return e,
    }
}

/// Gives the current user read access to `path` again: mode 0600 on POSIX systems, and the inherited ACL alone on Windows.
fn makeReadable(io: Io, gpa: std.mem.Allocator, path: []const u8) !u8 {
    if (builtin.os.tag == .windows) {
        try setDacl(gpa, path, inherited_only);
    } else {
        try Io.Dir.cwd().setFilePermissions(io, path, .fromMode(0o600), .{});
    }
    return 0;
}

/// An explicit ACE that denies `FILE_READ_DATA` to Everyone.
const deny_read_data = std.unicode.utf8ToUtf16LeStringLiteral("D:(D;;0x1;;;WD)");
/// No explicit ACE.
const inherited_only = std.unicode.utf8ToUtf16LeStringLiteral("D:");

/// Replaces the explicit ACEs of the file at `path` with those of the SDDL string `sddl`.
/// The DACL stays unprotected, so the file keeps the ACEs that it inherits from its directory.
fn setDacl(gpa: std.mem.Allocator, path: []const u8, sddl: [*:0]const u16) !void {
    var descriptor: ?*anyopaque = null;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, sddl_revision_1, &descriptor, null).toBool()) {
        return win32Failure("ConvertStringSecurityDescriptorToSecurityDescriptorW", @backingInt(windows.GetLastError()));
    }
    defer _ = LocalFree(descriptor);
    var present: windows.BOOL = .FALSE;
    var defaulted: windows.BOOL = .FALSE;
    var dacl: ?*anyopaque = null;
    if (!GetSecurityDescriptorDacl(descriptor.?, &present, &dacl, &defaulted).toBool()) {
        return win32Failure("GetSecurityDescriptorDacl", @backingInt(windows.GetLastError()));
    }
    const path_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
    defer gpa.free(path_w);
    const status = SetNamedSecurityInfoW(path_w, se_file_object, dacl_security_information | unprotected_dacl_security_information, null, null, dacl, null);
    if (status != 0) return win32Failure("SetNamedSecurityInfoW", status);
}

fn win32Failure(function: []const u8, code: u32) error{Win32Failed} {
    std.debug.print("{s} failed with Win32 error {d}\n", .{ function, code });
    return error.Win32Failed;
}

const sddl_revision_1: windows.DWORD = 1;
const se_file_object: c_int = 1;
const dacl_security_information: windows.DWORD = 0x4;
const unprotected_dacl_security_information: windows.DWORD = 0x20000000;

extern "advapi32" fn ConvertStringSecurityDescriptorToSecurityDescriptorW(
    StringSecurityDescriptor: [*:0]const u16,
    StringSDRevision: windows.DWORD,
    SecurityDescriptor: *?*anyopaque,
    SecurityDescriptorSize: ?*windows.ULONG,
) callconv(.winapi) windows.BOOL;

extern "advapi32" fn GetSecurityDescriptorDacl(
    pSecurityDescriptor: *anyopaque,
    lpbDaclPresent: *windows.BOOL,
    pDacl: *?*anyopaque,
    lpbDaclDefaulted: *windows.BOOL,
) callconv(.winapi) windows.BOOL;

extern "advapi32" fn SetNamedSecurityInfoW(
    pObjectName: [*:0]const u16,
    ObjectType: c_int,
    SecurityInfo: windows.DWORD,
    psidOwner: ?*anyopaque,
    psidGroup: ?*anyopaque,
    pDacl: ?*anyopaque,
    pSacl: ?*anyopaque,
) callconv(.winapi) windows.DWORD;

extern "kernel32" fn LocalFree(hMem: ?*anyopaque) callconv(.winapi) ?*anyopaque;

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
        std.debug.print("CreateHardLinkW failed with Win32 error {d}\n", .{@backingInt(windows.GetLastError())});
        return error.HardLinkFailed;
    }
}

extern "kernel32" fn CreateHardLinkW(
    lpFileName: [*:0]const u16,
    lpExistingFileName: [*:0]const u16,
    lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
) callconv(.winapi) windows.BOOL;

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

/// Confirms that the current directory holds exactly the entries in `names`, which are distinct.
fn checkEntries(io: Io, names: []const [:0]const u8) !u8 {
    var dir = try Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);
    var entries = dir.iterate();
    var found: usize = 0;
    var unexpected = false;
    while (try entries.next(io)) |entry| {
        for (names) |name| {
            if (std.mem.eql(u8, entry.name, name)) {
                found += 1;
                break;
            }
        } else {
            std.debug.print("the directory holds the unexpected entry {s}\n", .{entry.name});
            unexpected = true;
        }
    }
    if (found != names.len) std.debug.print("the directory lacks {d} of its {d} expected entries\n", .{ names.len - found, names.len });
    return if (unexpected or found != names.len) 1 else 0;
}

/// FP-0076 contract case 1: `run` writes its transcript into a FIFO that this helper reads to end of file within 30 seconds.
/// The helper opens the FIFO without blocking before it starts the laboratory, so the laboratory's write end finds a reader.
fn checkFifo(io: Io, gpa: std.mem.Allocator, laboratory: []const u8) !u8 {
    const posix = std.posix;
    const fifo_rc = if (builtin.os.tag == .linux)
        std.os.linux.mknodat(posix.AT.FDCWD, "transcript.json", std.os.linux.S.IFIFO | 0o600, 0)
    else
        mkfifo("transcript.json", 0o600);
    switch (posix.errno(fifo_rc)) {
        .SUCCESS => {},
        else => |err| return posix.unexpectedErrno(err),
    }
    const open_rc = posix.system.openat(posix.AT.FDCWD, "transcript.json", .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, @as(posix.mode_t, 0));
    switch (posix.errno(open_rc)) {
        .SUCCESS => {},
        else => |err| return posix.unexpectedErrno(err),
    }
    // `poll` reports neither data nor hang-up on this descriptor until a writer has opened the FIFO.
    const fifo: Io.File = .{ .handle = @intCast(open_rc), .flags = .{ .nonblocking = true } };
    defer fifo.close(io);

    var child = try std.process.spawn(io, .{
        .argv = &.{ laboratory, "run", "case.json", "--transcript", "transcript.json" },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    // On every early return this kills the laboratory, after `streams.deinit` below.
    defer child.kill(io);
    var buffer: Io.File.MultiReader.Buffer(3) = undefined;
    var streams: Io.File.MultiReader = undefined;
    streams.init(gpa, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.?, fifo });
    defer streams.deinit();
    const deadline = (Io.Timeout{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } }).toDeadline(io);
    while (streams.fill(64, deadline)) |_| {} else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => {
            std.debug.print("the laboratory did not finish within 30 seconds\n", .{});
            return 1;
        },
        else => |e| return e,
    }
    try streams.checkAnyError();
    const term = try child.wait(io);
    const stdout = streams.reader(0).buffered();
    const transcript = streams.reader(2).buffered();

    var failed = false;
    if (!exitedWith(term, 1)) {
        std.debug.print("the laboratory {f}; expected exit status 1\nstderr: {s}\n", .{ term, streams.reader(1).buffered() });
        failed = true;
    }
    if (std.mem.indexOf(u8, stdout, "\"result\": \"fail\"") == null) {
        std.debug.print("the result is not \"fail\":\n{s}\n", .{stdout});
        failed = true;
    }
    if (!try isVersion2Transcript(gpa, transcript)) failed = true;
    if (failed) return 1;
    try Io.File.stdout().writeStreamingAll(io, "the laboratory wrote a version 2 transcript through the FIFO\n");
    return 0;
}

extern "c" fn mkfifo(path: [*:0]const u8, mode: std.posix.mode_t) c_int;

/// Whether `bytes` is a version 2 transcript whose `action_count` equals its number of actions and that replays as `pass`.
fn isVersion2Transcript(gpa: std.mem.Allocator, bytes: []const u8) !bool {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, bytes, .{}) catch |err| {
        std.debug.print("the {d} bytes read from the FIFO are not JSON: {t}\n", .{ bytes.len, err });
        return false;
    };
    defer parsed.deinit();
    const top = switch (parsed.value) {
        .object => |object| object,
        else => {
            std.debug.print("the transcript is not a JSON object\n", .{});
            return false;
        },
    };
    const version = top.get("version") orelse std.json.Value.null;
    if (version != .integer or version.integer != 2) {
        std.debug.print("the transcript does not have version 2\n", .{});
        return false;
    }
    const action_count = top.get("action_count") orelse std.json.Value.null;
    const actions = top.get("actions") orelse std.json.Value.null;
    if (action_count != .integer or actions != .array or action_count.integer != actions.array.items.len) {
        std.debug.print("the transcript's action_count does not equal its number of actions\n", .{});
        return false;
    }
    var replayed = lab.replay(gpa, bytes);
    defer replayed.deinit();
    if (replayed.outcome.result != .pass) {
        std.debug.print("the transcript replays as {s}\n", .{replayed.outcome.result.name()});
        return false;
    }
    return true;
}

fn exitedWith(term: std.process.Child.Term, status: u8) bool {
    return switch (term) {
        .exited => |code| code == status,
        else => false,
    };
}

const oversized_files = [_]struct { name: []const u8, length: u64 }{
    .{ .name = "case.json", .length = lab.case_size_limit + 1 },
    .{ .name = "transcript.json", .length = lab.transcript_size_limit + 1 },
};

const OversizedCheck = struct { name: []const u8, args: []const []const u8, detail: []const u8 };

const oversized_checks = [_]OversizedCheck{
    .{ .name = "run reports a case file one byte above the size limit", .args = &.{ "run", "case.json" }, .detail = "case file: exceeds the size limit" },
    .{ .name = "minimize reports a case file one byte above the size limit", .args = &.{ "minimize", "case.json", "--out", "minimized.json" }, .detail = "case file: exceeds the size limit" },
    .{ .name = "replay reports a transcript file one byte above the size limit", .args = &.{ "replay", "transcript.json" }, .detail = "transcript file: exceeds the size limit" },
};

/// FP-0054 revision 1 case 5: creates `case.json` and `transcript.json` one byte above their size limits,
/// runs `run`, `minimize`, and `replay` on them, and checks each exit status and detail and that the failed minimization wrote nothing.
/// It removes both files before it reports, so a failing check never leaves an oversized file behind.
/// The report has one `pass` or `fail` line per check, and the exit status is 1 when any check fails.
fn checkOversized(io: Io, gpa: std.mem.Allocator, laboratory: []const u8) !u8 {
    const cwd = Io.Dir.cwd();
    var report: Io.Writer.Allocating = .init(gpa);
    defer report.deinit();
    const out = &report.writer;
    var failed = false;
    var created: usize = 0;
    // An unexpected error still removes every file created so far.
    errdefer for (oversized_files[0..created]) |file| cwd.deleteFile(io, file.name) catch {};
    for (oversized_files) |file| {
        extend(io, cwd, file.name, file.length) catch |err| {
            try out.print("fail: create {s}: {t}\n", .{ file.name, err });
            failed = true;
            break;
        };
        created += 1;
    }
    if (created == oversized_files.len) {
        for (oversized_checks, 0..) |check, index| {
            if (!try runOversizedCheck(io, gpa, laboratory, check, out)) failed = true;
            if (index == 1) {
                const name = "the failed minimization creates no output file";
                if (try exists(io, "minimized.json")) {
                    try out.print("fail: {s}: minimized.json exists\n", .{name});
                    failed = true;
                } else try out.print("pass: {s}\n", .{name});
            }
        }
    }
    // Remove the files, confirm that none remains, and only then report.
    var remaining: usize = 0;
    for (oversized_files[0..created]) |file| {
        cwd.deleteFile(io, file.name) catch |err| try out.print("fail: remove {s}: {t}\n", .{ file.name, err });
    }
    created = 0;
    for (oversized_files) |file| {
        if (try exists(io, file.name)) remaining += 1;
    }
    if (remaining == 0) {
        try out.print("pass: the helper removed both oversized files\n", .{});
    } else {
        try out.print("fail: {d} oversized files remain\n", .{remaining});
        failed = true;
    }
    try Io.File.stdout().writeStreamingAll(io, report.written());
    return if (failed) 1 else 0;
}

/// Runs one laboratory command of `checkOversized` and writes its report line. Returns whether the check passed.
fn runOversizedCheck(io: Io, gpa: std.mem.Allocator, laboratory: []const u8, check: OversizedCheck, out: *Io.Writer) !bool {
    var argv: [5][]const u8 = undefined;
    argv[0] = laboratory;
    @memcpy(argv[1..][0..check.args.len], check.args);
    const result = std.process.run(gpa, io, .{ .argv = argv[0 .. check.args.len + 1] }) catch |err| {
        try out.print("fail: {s}: the laboratory did not run: {t}\n", .{ check.name, err });
        return false;
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    if (!exitedWith(result.term, 3)) {
        try out.print("fail: {s}: the laboratory {f}; expected exit status 3\n", .{ check.name, result.term });
        return false;
    }
    if (std.mem.indexOf(u8, result.stdout, "\"result\": \"harness-error\"") == null) {
        try out.print("fail: {s}: the result is not \"harness-error\"\n", .{check.name});
        return false;
    }
    var expected: [64]u8 = undefined;
    const detail = try std.fmt.bufPrint(&expected, "\"detail\": \"{s}\"", .{check.detail});
    if (std.mem.indexOf(u8, result.stdout, detail) == null) {
        try out.print("fail: {s}: the detail is not \"{s}\"\n", .{ check.name, check.detail });
        return false;
    }
    try out.print("pass: {s}\n", .{check.name});
    return true;
}

fn exists(io: Io, path: []const u8) !bool {
    _ = Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => |e| return e,
    };
    return true;
}
