//! FP-0081 before-run staging: the case 1 test without the budget that it tests.

const std = @import("std");
const Alignment = std.mem.Alignment;
const testing = std.testing;

/// The bytes that a recording allocator holds for its live allocations.
fn liveBytes(recording: *const testing.FailingAllocator) u64 {
    return recording.allocated_bytes - recording.freed_bytes;
}

test "FP-0081 case 1: the budget admits exactly the remaining bytes, refuses one byte more, and never refuses a shrink or a free" {
    // A fixed buffer grants every in-place resize and remap of its last allocation, so only the budget can refuse one.
    var storage: [256]u8 = undefined;
    var fixed: std.heap.FixedBufferAllocator = .init(&storage);
    var recording: testing.FailingAllocator = .init(fixed.allocator(), .{});
    var budget: MemoryBudget = .init(recording.allocator(), 64);
    const gpa = budget.allocator();
    const byte: Alignment = .of(u8);

    // An allocation of exactly the remaining bytes succeeds, and one byte more fails.
    const first = gpa.rawAlloc(16, byte, @returnAddress()).?;
    try testing.expectEqual(16, budget.allocated_bytes);
    try testing.expectEqual(null, gpa.rawAlloc(49, byte, @returnAddress()));
    try testing.expectEqual(16, budget.allocated_bytes);
    try testing.expectEqual(1, recording.allocations);
    const second = gpa.rawAlloc(48, byte, @returnAddress()).?;
    try testing.expectEqual(64, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);
    try testing.expectEqual(null, gpa.rawAlloc(1, byte, @returnAddress()));
    try testing.expectEqual(2, recording.allocations);

    // A free reduces the count by the released bytes. It frees the last allocation, so `first` can grow in place.
    gpa.rawFree(second[0..48], byte, @returnAddress());
    try testing.expectEqual(16, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);

    // A growing resize of exactly the remaining bytes succeeds, and one byte more fails.
    try testing.expect(!gpa.rawResize(first[0..16], byte, 16 + 49, @returnAddress()));
    try testing.expectEqual(16, budget.allocated_bytes);
    try testing.expectEqual(0, recording.resize_index);
    try testing.expect(gpa.rawResize(first[0..16], byte, 64, @returnAddress()));
    try testing.expectEqual(64, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);

    // A shrinking resize succeeds even under a limit below the count, and it reduces the count by the released bytes.
    budget.max_allocated_bytes = 0;
    try testing.expect(gpa.rawResize(first[0..64], byte, 16, @returnAddress()));
    try testing.expectEqual(16, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);

    // A growing remap of exactly the remaining bytes succeeds, and one byte more fails.
    budget.max_allocated_bytes = 64;
    try testing.expectEqual(null, gpa.rawRemap(first[0..16], byte, 16 + 49, @returnAddress()));
    try testing.expectEqual(16, budget.allocated_bytes);
    const remapped = gpa.rawRemap(first[0..16], byte, 64, @returnAddress()).?;
    try testing.expectEqual(64, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);

    // A shrinking remap and a free succeed even under a limit below the count.
    budget.max_allocated_bytes = 0;
    const shrunk = gpa.rawRemap(remapped[0..64], byte, 8, @returnAddress()).?;
    try testing.expectEqual(8, budget.allocated_bytes);
    try testing.expectEqual(liveBytes(&recording), budget.allocated_bytes);
    gpa.rawFree(shrunk[0..8], byte, @returnAddress());
    try testing.expectEqual(0, budget.allocated_bytes);
    try testing.expectEqual(0, liveBytes(&recording));
}
