//! FP-0050 stop-rule probe for case 1. It is evidence only and is not part of the build.
//! It repeats the setup of case 1 on the base engine without the floor expectation.
//! For each combination it prints the event queue capacity and length, the free slots, the outstanding requests,
//! whether the floor `free >= requests` holds, and the result of destroying the loading document while every allocation fails.
//! Run it with `zig test --dep engine -Mroot=engineering/evidence/FP-0050/raw/case-1-capacity-probe.zig -Mengine=src/engine.zig`.

const std = @import("std");
const native = @import("engine");

test "FP-0050 probe: case 1 capacities" {
    const options: native.Options = .{ .max_outstanding_requests = 8, .max_response_body_bytes = 1024 };
    var floor_failures: usize = 0;
    var out_of_memory: usize = 0;
    for (0..49) |reloads| {
        for ([_]bool{ false, true }) |extra| {
            for ([_]bool{ false, true }) |answered| {
                var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .resize_fail_index = 0 });
                const engine = try native.Engine.create(failing.allocator(), options);
                const d = try engine.createDocument();
                const rd = try engine.load(d, "https://example.test/doomed");
                const s = try engine.createDocument();
                var spare = try engine.load(s, "https://example.test/spare");
                for (0..reloads) |_| spare = try engine.load(s, "https://example.test/spare");
                if (extra) {
                    try engine.respond(spare, 1, "spare");
                    _ = try engine.step(8);
                }
                if (answered) try engine.respond(rd, 1, "doomed");
                const capacity = engine.events.buffer.len;
                const length = engine.events.len;
                const free = capacity - length;
                const requests = engine.requests.count();
                failing.fail_index = failing.alloc_index;
                const result = engine.destroyDocument(d);
                failing.fail_index = std.math.maxInt(usize);
                const outcome: []const u8 = if (result) |_| "ok" else |err| @errorName(err);
                if (free < requests) floor_failures += 1;
                if (result) |_| {} else |_| out_of_memory += 1;
                std.debug.print("reloads={d} extra={any} answered={any} capacity={d} length={d} free={d} requests={d} floor_holds={any} destroy={s}\n", .{
                    reloads, extra, answered, capacity, length, free, requests, free >= requests, outcome,
                });
                try engine.destroy();
                try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            }
        }
    }
    std.debug.print("combinations=196 floor_failures={d} destroy_out_of_memory={d}\n", .{ floor_failures, out_of_memory });
}
