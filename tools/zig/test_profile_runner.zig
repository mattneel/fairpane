//! A test runner that measures the wall time of each test.
//! FP-0098 uses it to profile the tests that `zig build test` runs; see `engineering/evidence/FP-0098/README.md`.
//! Before each test, it prepares `std.testing` exactly as the default runner's `--listen` mode does:
//! a fresh `SafeAllocator` over the page allocator with the same canary and write-after-free check, and a fresh `Io.Threaded`.
//! A failed test, a leak, or an error log makes the run fail, as with the default runner.
const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub const std_options: std.Options = .{ .logFn = log };

var log_err_count: usize = 0;

const Sample = struct { index: usize, ns: u64 };

fn slower(_: void, a: Sample, b: Sample) bool {
    return a.ns > b.ns;
}

pub fn main(init: std.process.Init.Minimal) void {
    const clock_io = std.Io.Threaded.global_single_threaded.io();
    const tests = builtin.test_functions;
    const samples = std.heap.page_allocator.alloc(Sample, tests.len) catch @panic("out of memory");
    defer std.heap.page_allocator.free(samples);

    var failed: usize = 0;
    var skipped: usize = 0;
    var leaked: usize = 0;
    var logged: usize = 0;
    var total_ns: u64 = 0;
    for (tests, samples, 0..) |test_fn, *sample, i| {
        testing.allocator_instance = .init(std.heap.page_allocator, .{
            .canary = 0xc3a701ba,
            .check_write_after_free = true,
        });
        testing.io_instance = .init(testing.allocator, .{
            .argv0 = .init(init.args),
            .environ = init.environ,
        });
        testing.log_level = .warn;
        testing.environ = init.environ;
        log_err_count = 0;

        const start = std.Io.Clock.awake.now(clock_io);
        const outcome: []const u8 = if (test_fn.func()) |_| "pass" else |err| switch (err) {
            error.SkipZigTest => o: {
                skipped += 1;
                break :o "skip";
            },
            else => o: {
                failed += 1;
                std.debug.print("FAIL {s}: {t}\n", .{ test_fn.name, err });
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
                break :o "fail";
            },
        };
        const ns: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(clock_io)).toNanoseconds());

        testing.io_instance.deinit();
        if (testing.allocator_instance.deinit() != 0) leaked += 1;
        if (log_err_count != 0) logged += 1;

        sample.* = .{ .index = i, .ns = ns };
        total_ns += ns;
        std.debug.print("TEST {d}/{d} {d}.{d:0>3} ms {s} {s}\n", .{ i + 1, tests.len, ns / std.time.ns_per_ms, ns / std.time.ns_per_us % 1000, outcome, test_fn.name });
    }

    std.mem.sort(Sample, samples, {}, slower);
    std.debug.print("SLOWEST (rank, ms, share of the total, test)\n", .{});
    for (samples[0..@min(samples.len, 25)], 1..) |sample, rank| {
        const permille = if (total_ns == 0) 0 else sample.ns * 1000 / total_ns;
        std.debug.print("RANK {d} {d}.{d:0>3} ms {d}.{d}% {s}\n", .{ rank, sample.ns / std.time.ns_per_ms, sample.ns / std.time.ns_per_us % 1000, permille / 10, permille % 10, tests[sample.index].name });
    }
    std.debug.print("TOTAL {d} tests, {d}.{d:0>3} ms; {d} failed, {d} skipped, {d} leaked, {d} logged errors\n", .{ tests.len, total_ns / std.time.ns_per_ms, total_ns / std.time.ns_per_us % 1000, failed, skipped, leaked, logged });
    if (failed != 0 or leaked != 0 or logged != 0) std.process.exit(1);
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@backingInt(message_level) <= @backingInt(std.log.Level.err)) log_err_count +|= 1;
    if (@backingInt(message_level) <= @backingInt(testing.log_level)) {
        std.debug.print("[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n", args);
    }
}
