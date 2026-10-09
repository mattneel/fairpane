//! A byte budget over a backing allocator.
//!
//! The budget counts the byte lengths that its user requests, and it refuses any allocation or growth beyond its limit.
//! It does not count allocator overhead or alignment padding, so the count is the same on every allocator and platform.
//! A refused request never reaches the backing allocator.
//! A shrink and a free never fail on the limit, and they reduce the count by the bytes that they release.
//! A budget is not thread-safe, so only one thread may use it at a time.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const testing = std.testing;

pub const MemoryBudget = struct {
    backing: Allocator,
    /// The bytes that the live allocations hold.
    allocated_bytes: u64,
    /// The most bytes that the live allocations may hold at once.
    /// `std.math.maxInt(u64)` permits every allocation that the backing allocator grants.
    /// A limit below `allocated_bytes` is valid, and it refuses every growth until enough bytes are released.
    max_allocated_bytes: u64,

    pub fn init(backing: Allocator, max_allocated_bytes: u64) MemoryBudget {
        return .{ .backing = backing, .allocated_bytes = 0, .max_allocated_bytes = max_allocated_bytes };
    }

    /// The returned allocator refers to `budget`, so `budget` must not move while the allocator is in use.
    pub fn allocator(budget: *MemoryBudget) Allocator {
        return .{ .ptr = budget, .vtable = &vtable };
    }

    const vtable: Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    /// Whether the live allocations and `bytes` more fit within the limit.
    fn admits(budget: *const MemoryBudget, bytes: usize) bool {
        const total = std.math.add(u64, budget.allocated_bytes, bytes) catch return false;
        return total <= budget.max_allocated_bytes;
    }

    /// Whether the limit admits changing an allocation from `old_len` to `new_len` bytes.
    /// A shrink is always admitted.
    fn admitsChange(budget: *const MemoryBudget, old_len: usize, new_len: usize) bool {
        return new_len <= old_len or budget.admits(new_len - old_len);
    }

    /// Records a granted change of one allocation from `old_len` to `new_len` bytes.
    fn record(budget: *MemoryBudget, old_len: usize, new_len: usize) void {
        if (new_len >= old_len) {
            budget.allocated_bytes += new_len - old_len;
        } else {
            budget.allocated_bytes -= old_len - new_len;
        }
    }

    fn alloc(context: *anyopaque, len: usize, alignment: Alignment, return_address: usize) ?[*]u8 {
        const budget: *MemoryBudget = @ptrCast(@alignCast(context));
        if (!budget.admits(len)) return null;
        const result = budget.backing.rawAlloc(len, alignment, return_address) orelse return null;
        budget.allocated_bytes += len;
        return result;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) bool {
        const budget: *MemoryBudget = @ptrCast(@alignCast(context));
        if (!budget.admitsChange(memory.len, new_len)) return false;
        if (!budget.backing.rawResize(memory, alignment, new_len, return_address)) return false;
        budget.record(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, return_address: usize) ?[*]u8 {
        const budget: *MemoryBudget = @ptrCast(@alignCast(context));
        if (!budget.admitsChange(memory.len, new_len)) return null;
        const result = budget.backing.rawRemap(memory, alignment, new_len, return_address) orelse return null;
        budget.record(memory.len, new_len);
        return result;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: Alignment, return_address: usize) void {
        const budget: *MemoryBudget = @ptrCast(@alignCast(context));
        budget.backing.rawFree(memory, alignment, return_address);
        budget.allocated_bytes -= memory.len;
    }
};

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

test "the budget refuses a request whose count would overflow" {
    var budget: MemoryBudget = .init(testing.allocator, std.math.maxInt(u64));
    budget.allocated_bytes = std.math.maxInt(u64);
    try testing.expectEqual(null, budget.allocator().rawAlloc(1, .of(u8), @returnAddress()));
}
