//! FP-0106 contract case 6: the laboratory's Windows identification open maps each status
//! as the pinned standard library's `dirOpenFileWtf16` does (`Io/Threaded.zig:5167-5224`).
//! The mapping is a pure function in `lab.zig`, so the case runs on every host.

const std = @import("std");
const lab = @import("lab.zig");
const testing = std.testing;

test "FP-0106 case 6: windowsIdentityStep maps each status as the pinned dirOpenFileWtf16 does" {
    if (comptime @hasDecl(lab, "windowsIdentityStep")) {
        const cases = [_]struct { std.os.windows.NTSTATUS, lab.WindowsIdentityStep }{
            .{ .SUCCESS, .opened },
            .{ .OBJECT_NAME_INVALID, .{ .fail = error.BadPathName } },
            .{ .OBJECT_NAME_NOT_FOUND, .{ .fail = error.FileNotFound } },
            .{ .OBJECT_PATH_NOT_FOUND, .{ .fail = error.FileNotFound } },
            .{ .BAD_NETWORK_PATH, .{ .fail = error.NetworkNotFound } },
            .{ .BAD_NETWORK_NAME, .{ .fail = error.NetworkNotFound } },
            .{ .NO_MEDIA_IN_DEVICE, .{ .fail = error.NoDevice } },
            .{ .PIPE_NOT_AVAILABLE, .{ .fail = error.NoDevice } },
            .{ .INVALID_PARAMETER, .bug },
            .{ .OBJECT_PATH_SYNTAX_BAD, .bug },
            .{ .INVALID_HANDLE, .bug },
            .{ .CANCELLED, .retry },
            .{ .SHARING_VIOLATION, .retry_after_backoff },
            .{ .DELETE_PENDING, .retry_after_backoff },
            .{ .ACCESS_DENIED, .{ .fail = error.AccessDenied } },
            .{ .USER_MAPPED_FILE, .{ .fail = error.AccessDenied } },
            .{ .PIPE_BUSY, .{ .fail = error.PipeBusy } },
            .{ .OBJECT_NAME_COLLISION, .{ .fail = error.PathAlreadyExists } },
            .{ .FILE_IS_A_DIRECTORY, .{ .fail = error.IsDir } },
            .{ .NOT_A_DIRECTORY, .{ .fail = error.NotDir } },
            .{ .VIRUS_INFECTED, .{ .fail = error.AntivirusInterference } },
            .{ .VIRUS_DELETED, .{ .fail = error.AntivirusInterference } },
            .{ .INVALID_DEVICE_REQUEST, .unexpected },
            .{ .DISK_FULL, .unexpected },
        };
        for (cases) |case| {
            const status, const expected = case;
            testing.expectEqual(expected, lab.windowsIdentityStep(status)) catch |err| {
                std.debug.print("the step for {s} differs\n", .{@tagName(status)});
                return err;
            };
        }
    } else return error.WindowsIdentityStepMissing;
}

test "FP-0106 case 6: windowsIdentityBackoffMs gives 13 waits from 0 ms to 2048 ms that sum to 4095 ms, then null" {
    if (comptime @hasDecl(lab, "windowsIdentityBackoffMs")) {
        const waits = [_]u32{ 0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048 };
        var total: u32 = 0;
        for (waits, 0..) |expected, attempt| {
            const actual = lab.windowsIdentityBackoffMs(@intCast(attempt));
            testing.expectEqual(@as(?u32, expected), actual) catch |err| {
                std.debug.print("the wait before backoff {d} differs\n", .{attempt});
                return err;
            };
            total += actual.?;
        }
        try testing.expectEqual(@as(?u32, null), lab.windowsIdentityBackoffMs(waits.len));
        try testing.expectEqual(@as(u32, 4095), total);
    } else return error.WindowsIdentityBackoffMsMissing;
}
