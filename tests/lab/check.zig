//! Checks for contract case 14 that the build runs after `fairpane-lab minimize`.
//!
//! `check minimal <case>` confirms that the minimized case keeps the `fail` outcome on `document_state`,
//! keeps no resource, and has a 1-minimal document body: removing any single byte changes the outcome.
//! `check empty <directory>` confirms that a refused minimization wrote nothing into its output directory.

const std = @import("std");
const lab = @import("lab");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 3 and std.mem.eql(u8, args[1], "minimal")) return checkMinimal(init.io, init.gpa, args[2]);
    if (args.len == 3 and std.mem.eql(u8, args[1], "empty")) return checkEmpty(init.io, args[2]);
    std.debug.print("usage: check minimal <case> | check empty <directory>\n", .{});
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
