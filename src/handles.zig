//! Checked owners and generational handles for single-owner engine tables.
//!
//! Handles are internal Zig values. They never cross the C ABI or the process
//! protocol directly; each boundary maps them through its own validated
//! identifier type.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// A nonzero 64-bit owner identity.
/// Only `OwnerIdSource` creates values, so an identity never derives from an address.
pub const OwnerId = enum(u64) { _ };

pub const OwnerIdError = error{OwnerIdsExhausted};

/// Issues strictly increasing owner identities. It never wraps and never issues zero.
pub const OwnerIdSource = struct {
    /// The next identity to issue. Zero records exhaustion after `maxInt(u64)` was issued.
    next: std.atomic.Value(u64),

    /// Asserts that `first` is nonzero.
    pub fn init(first: u64) OwnerIdSource {
        assert(first != 0);
        return .{ .next = .init(first) };
    }

    /// Safe to call from any thread.
    pub fn issue(source: *OwnerIdSource) OwnerIdError!OwnerId {
        var current = source.next.load(.monotonic);
        while (current != 0) {
            // Issuing `maxInt(u64)` stores zero, which every later request reports as exhaustion.
            current = source.next.cmpxchgWeak(current, current +% 1, .monotonic, .monotonic) orelse
                return @fromBackingInt(@intCast(current));
        }
        return error.OwnerIdsExhausted;
    }
};

var engine_owner_ids: OwnerIdSource = .init(1);

/// Issues an identity from the one process-wide source for engine owners.
pub fn issueEngineOwnerId() OwnerIdError!OwnerId {
    return engine_owner_ids.issue();
}

pub const TableConfig = struct {
    Index: type = u32,
    Generation: type = u32,
};

pub const LookupError = error{ WrongOwner, InvalidHandle, StaleHandle };
pub const InsertError = error{ OutOfMemory, HandleSpaceExhausted };

fn requireUnsigned(comptime name: []const u8, comptime Int: type) void {
    const info = @typeInfo(Int);
    if (info != .int or info.int.signedness != .unsigned or info.int.bits == 0) {
        @compileError("Table " ++ name ++ " must be a nonzero-width unsigned integer type, found " ++ @typeName(Int));
    }
}

/// A generational table of `T` values that belongs to exactly one owner.
/// A table is a single-thread structure.
///
/// Each slot stores its current generation and one state: a live value,
/// a free-list link, or retirement. New slots start at generation 1.
/// `remove` increments the generation and pushes the slot on a LIFO free
/// list, except at the maximum generation, where it retires the slot forever.
/// No table issues the same owner, index, and generation triple twice.
pub fn Table(comptime T: type, comptime config: TableConfig) type {
    comptime {
        requireUnsigned("Index", config.Index);
        requireUnsigned("Generation", config.Generation);
        if (@bitSizeOf(config.Index) > @bitSizeOf(usize)) {
            @compileError("Table Index must not be wider than usize");
        }
    }
    return struct {
        const Self = @This();

        pub const Index = config.Index;
        pub const Generation = config.Generation;

        /// A checked reference to one slot generation. It contains no pointer.
        pub const Handle = struct {
            owner: OwnerId,
            index: Index,
            generation: Generation,
        };

        pub const Entry = struct {
            handle: Handle,
            value: *T,
        };

        const Slot = struct {
            generation: Generation,
            state: union(enum) {
                live: T,
                /// The next free slot, or null at the end of the free list.
                free: ?Index,
                retired,
            },
        };

        const max_index: Index = std.math.maxInt(Index);
        const max_generation: Generation = std.math.maxInt(Generation);
        const slot_limit: usize = if (std.math.maxInt(Index) < std.math.maxInt(usize))
            std.math.maxInt(Index) + 1
        else
            std.math.maxInt(usize);

        owner: OwnerId,
        slots: std.ArrayList(Slot),
        free_head: ?Index,
        live_count: usize,

        /// Creates an empty table without allocation.
        pub fn init(owner: OwnerId) Self {
            assert(@backingInt(owner) != 0);
            return .{ .owner = owner, .slots = .empty, .free_head = null, .live_count = 0 };
        }

        /// Releases table storage. It does not destroy values.
        /// The owner removes or visits live values first.
        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.slots.deinit(gpa);
            self.* = undefined;
        }

        /// Reuses a free slot before it grows storage.
        /// On error, the table is unchanged and the caller still owns `value`.
        pub fn insert(self: *Self, gpa: Allocator, value: T) InsertError!Handle {
            if (self.free_head) |index| {
                const slot = &self.slots.items[index];
                self.free_head = slot.state.free;
                slot.state = .{ .live = value };
                self.live_count += 1;
                return .{ .owner = self.owner, .index = index, .generation = slot.generation };
            }
            const len = self.slots.items.len;
            if (len > max_index) return error.HandleSpaceExhausted;
            try self.reserveSlot(gpa);
            self.slots.appendAssumeCapacity(.{ .generation = 1, .state = .{ .live = value } });
            self.live_count += 1;
            return .{ .owner = self.owner, .index = @intCast(len), .generation = 1 };
        }

        /// The only allocation point. It changes no table state on failure.
        fn reserveSlot(self: *Self, gpa: Allocator) Allocator.Error!void {
            const len = self.slots.items.len;
            if (len < self.slots.capacity) return;
            const grown = len +| len / 2 +| 8;
            try self.slots.ensureTotalCapacityPrecise(gpa, @min(grown, slot_limit));
        }

        /// Returns a copy of the value.
        pub fn get(self: *const Self, handle: Handle) LookupError!T {
            return (try self.liveSlot(handle)).state.live;
        }

        /// The pointer stays valid until the next `insert`, `remove`, or `deinit`.
        pub fn getPtr(self: *Self, handle: Handle) LookupError!*T {
            return &(try self.liveSlot(handle)).state.live;
        }

        /// Returns the value and invalidates every handle to that slot generation.
        pub fn remove(self: *Self, handle: Handle) LookupError!T {
            const slot = try self.liveSlot(handle);
            const value = slot.state.live;
            if (slot.generation == max_generation) {
                slot.state = .retired;
            } else {
                slot.generation += 1;
                slot.state = .{ .free = self.free_head };
                self.free_head = handle.index;
            }
            self.live_count -= 1;
            return value;
        }

        pub fn validate(self: *const Self, handle: Handle) LookupError!void {
            _ = try self.liveSlot(handle);
        }

        /// Returns the number of live values.
        pub fn count(self: *const Self) usize {
            return self.live_count;
        }

        /// Visits each live value and its handle exactly once.
        /// Removing an entry that the iterator already returned is permitted.
        /// Inserting during iteration is not.
        pub fn iterator(self: *Self) Iterator {
            return .{ .table = self, .next_index = 0 };
        }

        pub const Iterator = struct {
            table: *Self,
            next_index: usize,

            pub fn next(it: *Iterator) ?Entry {
                const slots = it.table.slots.items;
                while (it.next_index < slots.len) {
                    const index = it.next_index;
                    it.next_index += 1;
                    const slot = &slots[index];
                    switch (slot.state) {
                        .live => |*value| return .{
                            .handle = .{ .owner = it.table.owner, .index = @intCast(index), .generation = slot.generation },
                            .value = value,
                        },
                        .free, .retired => {},
                    }
                }
                return null;
            }
        };

        /// Checks the owner first, then the index and generation range, then the slot state.
        fn liveSlot(self: *const Self, handle: Handle) LookupError!*Slot {
            if (handle.owner != self.owner) return error.WrongOwner;
            if (handle.generation == 0 or handle.index >= self.slots.items.len) return error.InvalidHandle;
            const slot = &self.slots.items[handle.index];
            switch (slot.state) {
                .live => {},
                .free, .retired => return error.StaleHandle,
            }
            if (slot.generation != handle.generation) return error.StaleHandle;
            return slot;
        }

        /// Test-only check of the free list, live count, generation bounds, and retired slots.
        fn expectInvariants(self: *const Self) !void {
            comptime assert(builtin.is_test);
            const slots = self.slots.items;
            try testing.expect(slots.len <= slot_limit);
            try testing.expect(slots.len <= self.slots.capacity);
            var live: usize = 0;
            var free: usize = 0;
            for (slots) |slot| {
                try testing.expect(slot.generation != 0);
                switch (slot.state) {
                    .live => live += 1,
                    .free => |next| {
                        // Only `remove` frees a slot, and it always advances the generation.
                        try testing.expect(slot.generation > 1);
                        if (next) |index| try testing.expect(index < slots.len);
                        free += 1;
                    },
                    .retired => try testing.expect(slot.generation == max_generation),
                }
            }
            try testing.expectEqual(live, self.live_count);
            // A list that reaches null within `free` steps through free slots is acyclic and covers every free slot.
            var steps: usize = 0;
            var cursor = self.free_head;
            while (cursor) |index| : (steps += 1) {
                try testing.expect(steps < free);
                try testing.expect(index < slots.len);
                switch (slots[index].state) {
                    .free => |next| cursor = next,
                    .live, .retired => return error.TestUnexpectedResult,
                }
            }
            try testing.expectEqual(free, steps);
        }
    };
}

fn testOwners(comptime n: usize) [n]OwnerId {
    var source: OwnerIdSource = .init(1);
    var owners: [n]OwnerId = undefined;
    for (&owners) |*owner| owner.* = source.issue() catch unreachable;
    return owners;
}

test "inserted values round-trip through get, getPtr, and remove" {
    const gpa = testing.allocator;
    const owner = testOwners(1)[0];
    var table: Table(u64, .{}) = .init(owner);
    defer table.deinit(gpa);

    const a = try table.insert(gpa, 11);
    const b = try table.insert(gpa, 22);
    try testing.expectEqual(owner, a.owner);
    try testing.expectEqual(0, a.index);
    try testing.expectEqual(1, a.generation);
    try testing.expectEqual(1, b.index);
    try testing.expectEqual(2, table.count());

    try testing.expectEqual(11, try table.get(a));
    try testing.expectEqual(22, try table.get(b));
    const pointer = try table.getPtr(b);
    try testing.expectEqual(22, pointer.*);
    pointer.* = 23;
    try testing.expectEqual(23, try table.get(b));
    try table.validate(a);

    try testing.expectEqual(11, try table.remove(a));
    try testing.expectEqual(23, try table.remove(b));
    try testing.expectEqual(0, table.count());
    try table.expectInvariants();
}

test "a handle from another owner returns WrongOwner even when its index is out of range" {
    const gpa = testing.allocator;
    const owners = testOwners(2);
    const Values = Table(u64, .{});
    var mine: Values = .init(owners[0]);
    defer mine.deinit(gpa);
    var theirs: Values = .init(owners[1]);
    defer theirs.deinit(gpa);

    const own = try mine.insert(gpa, 1);
    const foreign = try theirs.insert(gpa, 7);
    _ = try theirs.insert(gpa, 8);
    const foreign_far = try theirs.insert(gpa, 9);
    const forged: [4]Values.Handle = .{
        foreign,
        foreign_far,
        .{ .owner = owners[1], .index = std.math.maxInt(u32), .generation = 1 },
        .{ .owner = owners[1], .index = std.math.maxInt(u32), .generation = 0 },
    };
    for (forged) |handle| {
        try testing.expectError(error.WrongOwner, mine.get(handle));
        try testing.expectError(error.WrongOwner, mine.getPtr(handle));
        try testing.expectError(error.WrongOwner, mine.validate(handle));
        try testing.expectError(error.WrongOwner, mine.remove(handle));
    }
    try testing.expectEqual(1, mine.count());
    try testing.expectEqual(1, try mine.get(own));
    try testing.expectEqual(7, try theirs.get(foreign));
    try mine.expectInvariants();
    try theirs.expectInvariants();
}

test "a removed handle is stale and the next insert reuses its index with a new generation" {
    const gpa = testing.allocator;
    const owner = testOwners(1)[0];
    var table: Table(u64, .{}) = .init(owner);
    defer table.deinit(gpa);

    const first = try table.insert(gpa, 1);
    const kept = try table.insert(gpa, 2);
    try testing.expectEqual(1, try table.remove(first));
    try testing.expectError(error.StaleHandle, table.get(first));
    try testing.expectError(error.StaleHandle, table.getPtr(first));
    try testing.expectError(error.StaleHandle, table.validate(first));
    try testing.expectError(error.StaleHandle, table.remove(first));
    try table.expectInvariants();

    const second = try table.insert(gpa, 3);
    try testing.expectEqual(first.index, second.index);
    try testing.expectEqual(first.generation + 1, second.generation);
    try testing.expectError(error.StaleHandle, table.get(first));
    try testing.expectEqual(3, try table.get(second));
    try testing.expectEqual(2, try table.get(kept));
    try testing.expectEqual(2, table.count());
    try table.expectInvariants();
}

test "forged handles with an out-of-range index or generation zero return InvalidHandle" {
    const gpa = testing.allocator;
    const owner = testOwners(1)[0];
    const Values = Table(u64, .{});
    var table: Values = .init(owner);
    defer table.deinit(gpa);

    const empty_probe: Values.Handle = .{ .owner = owner, .index = 0, .generation = 1 };
    try testing.expectError(error.InvalidHandle, table.get(empty_probe));

    const live = try table.insert(gpa, 5);
    _ = try table.insert(gpa, 6);
    const forged: [4]Values.Handle = .{
        .{ .owner = owner, .index = 2, .generation = 1 },
        .{ .owner = owner, .index = std.math.maxInt(u32), .generation = 1 },
        .{ .owner = owner, .index = live.index, .generation = 0 },
        .{ .owner = owner, .index = std.math.maxInt(u32), .generation = 0 },
    };
    for (forged) |handle| {
        try testing.expectError(error.InvalidHandle, table.get(handle));
        try testing.expectError(error.InvalidHandle, table.getPtr(handle));
        try testing.expectError(error.InvalidHandle, table.validate(handle));
        try testing.expectError(error.InvalidHandle, table.remove(handle));
    }
    try testing.expectEqual(2, table.count());
    try testing.expectEqual(5, try table.get(live));
    try table.expectInvariants();
}

test "a two-bit generation retires its slot after generation three" {
    const gpa = testing.allocator;
    const owner = testOwners(1)[0];
    const Small = Table(u32, .{ .Generation = u2 });
    var table: Small = .init(owner);
    defer table.deinit(gpa);

    var issued: [3]Small.Handle = undefined;
    for (&issued, 1..) |*handle, generation| {
        handle.* = try table.insert(gpa, @intCast(generation));
        try testing.expectEqual(0, handle.index);
        try testing.expectEqual(generation, handle.generation);
        try testing.expectEqual(generation, try table.remove(handle.*));
        try table.expectInvariants();
    }
    try testing.expect(table.slots.items[0].state == .retired);
    try testing.expectEqual(null, table.free_head);

    const next = try table.insert(gpa, 99);
    try testing.expectEqual(1, next.index);
    try testing.expectEqual(1, next.generation);
    for (issued) |handle| {
        try testing.expectError(error.StaleHandle, table.get(handle));
        try testing.expectError(error.StaleHandle, table.getPtr(handle));
        try testing.expectError(error.StaleHandle, table.validate(handle));
        try testing.expectError(error.StaleHandle, table.remove(handle));
    }
    try testing.expectEqual(1, table.count());
    try testing.expectEqual(99, try table.get(next));
    try table.expectInvariants();
}

test "retiring every two-bit index yields HandleSpaceExhausted without allocation" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{});
    const gpa = failing.allocator();
    const owner = testOwners(1)[0];
    const Tiny = Table(u8, .{ .Index = u2, .Generation = u2 });
    var table: Tiny = .init(owner);
    defer table.deinit(gpa);

    var handles: [4]Tiny.Handle = undefined;
    for (&handles, 0..) |*handle, index| {
        handle.* = try table.insert(gpa, @intCast(index));
        try testing.expectEqual(index, handle.index);
    }
    try testing.expectError(error.HandleSpaceExhausted, table.insert(gpa, 4));
    try table.expectInvariants();

    for (0..3) |round| {
        for (handles) |handle| _ = try table.remove(handle);
        try table.expectInvariants();
        if (round == 2) break;
        for (&handles) |*handle| {
            handle.* = try table.insert(gpa, 0);
            try testing.expectEqual(round + 2, handle.generation);
        }
    }
    try testing.expectEqual(0, table.count());
    try testing.expectEqual(null, table.free_head);
    for (table.slots.items) |slot| try testing.expect(slot.state == .retired);

    const allocations = failing.allocations;
    failing.fail_index = failing.alloc_index;
    for (0..2) |_| {
        try testing.expectError(error.HandleSpaceExhausted, table.insert(gpa, 5));
        try table.expectInvariants();
    }
    try testing.expectEqual(allocations, failing.allocations);
    try testing.expect(!failing.has_induced_failure);
    for (handles) |handle| try testing.expectError(error.StaleHandle, table.get(handle));
}

test "failed growth returns OutOfMemory and leaves the table unchanged" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    const gpa = failing.allocator();
    const owner = testOwners(1)[0];
    const Values = Table(u64, .{ .Generation = u1 });
    var table: Values = .init(owner);
    defer table.deinit(gpa);

    const retired = try table.insert(gpa, 100);
    _ = try table.remove(retired);
    var live: [64]Values.Handle = undefined;
    var live_len: usize = 0;
    while (table.slots.items.len < table.slots.capacity) : (live_len += 1) {
        live[live_len] = try table.insert(gpa, live_len);
    }
    try testing.expect(live_len > 0);

    const count = table.count();
    const slot_len = table.slots.items.len;
    const capacity = table.slots.capacity;
    const free_head = table.free_head;
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, table.insert(gpa, 999));
    try testing.expect(failing.has_induced_failure);

    try testing.expectEqual(count, table.count());
    try testing.expectEqual(slot_len, table.slots.items.len);
    try testing.expectEqual(capacity, table.slots.capacity);
    try testing.expectEqual(free_head, table.free_head);
    for (live[0..live_len], 0..) |handle, value| try testing.expectEqual(value, try table.get(handle));
    try testing.expectError(error.StaleHandle, table.get(retired));
    try table.expectInvariants();

    failing.fail_index = std.math.maxInt(usize);
    const recovered = try table.insert(gpa, 999);
    try testing.expectEqual(slot_len, recovered.index);
    try testing.expectEqual(999, try table.get(recovered));
    try table.expectInvariants();
}

fn insertChecked(table: anytype, gpa: Allocator, value: u64) !@TypeOf(table.*).Handle {
    const count = table.count();
    const slot_len = table.slots.items.len;
    const capacity = table.slots.capacity;
    const free_head = table.free_head;
    return table.insert(gpa, value) catch |err| {
        try testing.expectEqual(error.OutOfMemory, err);
        try testing.expectEqual(count, table.count());
        try testing.expectEqual(slot_len, table.slots.items.len);
        try testing.expectEqual(capacity, table.slots.capacity);
        try testing.expectEqual(free_head, table.free_head);
        try table.expectInvariants();
        return err;
    };
}

fn allocationScenario(gpa: Allocator, owner: OwnerId) !void {
    const Values = Table(u64, .{});
    var table: Values = .init(owner);
    defer table.deinit(gpa);

    var handles: [36]Values.Handle = undefined;
    for (handles[0..20], 0..) |*handle, value| handle.* = try insertChecked(&table, gpa, value);
    var removed: usize = 0;
    var index: usize = 0;
    while (index < 20) : (index += 3) {
        try testing.expectEqual(index, try table.remove(handles[index]));
        removed += 1;
    }
    try table.expectInvariants();

    for (handles[20..], 20..) |*handle, value| {
        handle.* = try insertChecked(&table, gpa, value);
        if (value < 20 + removed) try testing.expect(handle.generation == 2);
    }
    try testing.expectEqual(36 - removed, table.count());

    var visited: usize = 0;
    var iterator = table.iterator();
    while (iterator.next()) |entry| {
        visited += 1;
        try testing.expectEqual(entry.value.*, try table.get(entry.handle));
    }
    try testing.expectEqual(table.count(), visited);
    try table.expectInvariants();
}

test "every induced allocation failure returns OutOfMemory, keeps invariants, and leaks nothing" {
    // Fail every remap so each growth step is an allocation that the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    const owner = testOwners(1)[0];
    // The scenario grows storage at least three times, so the checker induces at least three failures.
    var probe: testing.FailingAllocator = .init(no_remap.allocator(), .{});
    try allocationScenario(probe.allocator(), owner);
    try testing.expect(probe.allocations >= 3);
    try testing.checkAllAllocationFailures(no_remap.allocator(), allocationScenario, .{owner});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

test "every table error leaves a valid table that deinit releases completely" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 0, .resize_fail_index = 0 });
    const gpa = failing.allocator();
    const owners = testOwners(2);
    const Tiny = Table(u16, .{ .Index = u2, .Generation = u1 });
    {
        var table: Tiny = .init(owners[0]);
        defer table.deinit(gpa);

        try testing.expectError(error.OutOfMemory, table.insert(gpa, 1));
        try testing.expectEqual(0, table.count());
        try table.expectInvariants();
        failing.fail_index = std.math.maxInt(usize);

        var handles: [4]Tiny.Handle = undefined;
        for (&handles, 0..) |*handle, value| handle.* = try table.insert(gpa, @intCast(value));

        const foreign: Tiny.Handle = .{ .owner = owners[1], .index = 0, .generation = 1 };
        try testing.expectError(error.WrongOwner, table.remove(foreign));
        try table.expectInvariants();

        const forged: Tiny.Handle = .{ .owner = owners[0], .index = 0, .generation = 0 };
        try testing.expectError(error.InvalidHandle, table.remove(forged));
        try table.expectInvariants();

        for (handles) |handle| _ = try table.remove(handle);
        try testing.expectError(error.StaleHandle, table.remove(handles[0]));
        try table.expectInvariants();

        try testing.expectError(error.HandleSpaceExhausted, table.insert(gpa, 9));
        try table.expectInvariants();
    }
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    try testing.expectEqual(failing.allocations, failing.deallocations);
}

test "the process-wide source issues increasing nonzero engine owner identities" {
    const first = try issueEngineOwnerId();
    const second = try issueEngineOwnerId();
    try testing.expect(@backingInt(first) != 0);
    try testing.expect(@backingInt(first) < @backingInt(second));
}

test "an owner source started near the maximum issues two identities and then stays exhausted" {
    const max = std.math.maxInt(u64);
    var source: OwnerIdSource = .init(max - 1);
    try testing.expectEqual(max - 1, @backingInt(try source.issue()));
    try testing.expectEqual(max, @backingInt(try source.issue()));
    for (0..3) |_| try testing.expectError(error.OwnerIdsExhausted, source.issue());
}

fn issueMany(source: *OwnerIdSource, out: *[1000]u64) void {
    for (out) |*id| id.* = if (source.issue()) |owner| @backingInt(owner) else |_| 0;
}

test "four threads that share one source receive four thousand distinct identities" {
    var source: OwnerIdSource = .init(1);
    var ids: [4][1000]u64 = undefined;
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    defer for (threads[0..spawned]) |thread| thread.join();
    for (&threads, &ids) |*thread, *out| {
        thread.* = try std.Thread.spawn(.{}, issueMany, .{ &source, out });
        spawned += 1;
    }
    for (threads[0..spawned]) |thread| thread.join();
    spawned = 0;

    for (ids) |sequence| {
        for (sequence[1..], sequence[0 .. sequence.len - 1]) |later, earlier| {
            try testing.expect(earlier != 0);
            try testing.expect(earlier < later);
        }
    }
    const all: *[4000]u64 = @ptrCast(&ids);
    std.mem.sort(u64, all, {}, std.sort.asc(u64));
    for (all, 1..) |id, expected| try testing.expectEqual(expected, id);
}

test "table instantiations declare distinct handle types that contain no pointers" {
    const A = Table(u32, .{});
    const B = Table(u64, .{});
    const C = Table(u32, .{ .Index = u16, .Generation = u8 });
    comptime {
        assert(A.Handle != B.Handle);
        assert(A.Handle != C.Handle);
        assert(B.Handle != C.Handle);
        assert(@typeInfo(OwnerId).@"enum".tag_type == u64);
        for ([_]type{ A.Handle, B.Handle, C.Handle }) |Handle| {
            assert(@typeInfo(Handle) != .pointer);
            assert(@hasField(Handle, "owner"));
            assert(@hasField(Handle, "index"));
            assert(@hasField(Handle, "generation"));
            for (@typeInfo(Handle).@"struct".field_types) |Field| switch (@typeInfo(Field)) {
                .int, .@"enum" => {},
                else => @compileError("a handle field is not an integer identity"),
            };
        }
        assert(@FieldType(C.Handle, "index") == u16);
        assert(@FieldType(C.Handle, "generation") == u8);
    }
}

test "iteration visits each live value once and skips free and retired slots" {
    const gpa = testing.allocator;
    const owner = testOwners(1)[0];
    const Values = Table(u32, .{ .Generation = u2 });
    var table: Values = .init(owner);
    defer table.deinit(gpa);

    var handles: [6]Values.Handle = undefined;
    for (&handles, 0..) |*handle, index| handle.* = try table.insert(gpa, @intCast(100 + index));
    _ = try table.remove(handles[0]);
    for (0..2) |_| _ = try table.remove(try table.insert(gpa, 0));
    try testing.expect(table.slots.items[0].state == .retired);
    _ = try table.remove(handles[2]);
    _ = try table.remove(handles[4]);
    try table.expectInvariants();

    var seen: [6]u8 = @splat(0);
    var iterator = table.iterator();
    while (iterator.next()) |entry| {
        seen[entry.handle.index] += 1;
        try testing.expectEqual(handles[entry.handle.index], entry.handle);
        try testing.expectEqual(100 + entry.handle.index, entry.value.*);
        entry.value.* += 1;
    }
    try testing.expectEqualSlices(u8, &.{ 0, 1, 0, 1, 0, 1 }, &seen);
    for ([_]usize{ 1, 3, 5 }) |index| try testing.expectEqual(101 + index, try table.get(handles[index]));

    var drained: usize = 0;
    iterator = table.iterator();
    while (iterator.next()) |entry| {
        _ = try table.remove(entry.handle);
        drained += 1;
    }
    try testing.expectEqual(3, drained);
    try testing.expectEqual(0, table.count());
    iterator = table.iterator();
    try testing.expectEqual(null, iterator.next());
    try table.expectInvariants();
}

fn runModel(comptime config: TableConfig, seed: u64, steps: usize) !void {
    const Subject = Table(u32, config);
    const Handle = Subject.Handle;
    const slot_total = 1 << @bitSizeOf(config.Index);
    const generation_max = std.math.maxInt(config.Generation);
    comptime assert(slot_total * generation_max <= 256);
    const ModelSlot = struct {
        generation: config.Generation,
        live: bool,
        retired: bool,
        value: u32,
    };
    const Model = struct {
        owner: OwnerId,
        slots: [slot_total]ModelSlot = undefined,
        len: usize = 0,
        live: usize = 0,

        fn expectation(model: *const @This(), handle: Handle) LookupError!void {
            if (handle.owner != model.owner) return error.WrongOwner;
            if (handle.generation == 0 or handle.index >= model.len) return error.InvalidHandle;
            const slot = model.slots[handle.index];
            if (!slot.live or slot.generation != handle.generation) return error.StaleHandle;
        }

        fn hasFree(model: *const @This()) bool {
            for (model.slots[0..model.len]) |slot| {
                if (!slot.live and !slot.retired) return true;
            }
            return false;
        }
    };

    const gpa = testing.allocator;
    const owners = testOwners(2);
    var table: Subject = .init(owners[0]);
    defer table.deinit(gpa);
    var model: Model = .{ .owner = owners[0] };
    var issued: [slot_total][generation_max + 1]bool = @splat(@splat(false));
    var known: [slot_total * generation_max]Handle = undefined;
    var known_len: usize = 0;
    var prng: std.Random.DefaultPrng = .init(seed);
    const random = prng.random();

    for (0..steps) |_| {
        const operation = random.uintLessThan(u8, 10);
        if (operation < 4) {
            const value = random.int(u32);
            const had_free = model.hasFree();
            const can_grow = model.len < slot_total;
            if (table.insert(gpa, value)) |handle| {
                try testing.expectEqual(owners[0], handle.owner);
                try testing.expect(!issued[handle.index][handle.generation]);
                issued[handle.index][handle.generation] = true;
                if (had_free) {
                    try testing.expect(handle.index < model.len);
                    const slot = model.slots[handle.index];
                    try testing.expect(!slot.live and !slot.retired);
                    try testing.expectEqual(slot.generation, handle.generation);
                } else {
                    try testing.expect(can_grow);
                    try testing.expectEqual(model.len, handle.index);
                    try testing.expectEqual(1, handle.generation);
                    model.len += 1;
                }
                model.slots[handle.index] = .{ .generation = handle.generation, .live = true, .retired = false, .value = value };
                model.live += 1;
                known[known_len] = handle;
                known_len += 1;
            } else |err| {
                try testing.expectEqual(error.HandleSpaceExhausted, err);
                try testing.expect(!had_free and !can_grow);
            }
        } else {
            const pick = random.uintLessThan(u8, 20);
            const handle: Handle = if (known_len == 0 or pick < 3) .{
                .owner = owners[0],
                .index = random.int(config.Index),
                .generation = random.int(config.Generation),
            } else if (pick < 6) .{
                .owner = owners[1],
                .index = known[random.uintLessThan(usize, known_len)].index,
                .generation = known[random.uintLessThan(usize, known_len)].generation,
            } else known[random.uintLessThan(usize, known_len)];
            const expected = model.expectation(handle);
            switch (operation) {
                4, 5 => if (expected) {
                    const slot = &model.slots[handle.index];
                    try testing.expectEqual(slot.value, try table.remove(handle));
                    slot.live = false;
                    if (slot.generation == generation_max) {
                        slot.retired = true;
                    } else {
                        slot.generation += 1;
                    }
                    model.live -= 1;
                } else |err| try testing.expectError(err, table.remove(handle)),
                6 => if (expected) {
                    try testing.expectEqual(model.slots[handle.index].value, try table.get(handle));
                } else |err| try testing.expectError(err, table.get(handle)),
                7 => if (expected) {
                    const value = random.int(u32);
                    (try table.getPtr(handle)).* = value;
                    model.slots[handle.index].value = value;
                } else |err| try testing.expectError(err, table.getPtr(handle)),
                8 => if (expected) {
                    try table.validate(handle);
                } else |err| try testing.expectError(err, table.validate(handle)),
                9 => {
                    var visited: usize = 0;
                    var iterator = table.iterator();
                    while (iterator.next()) |entry| {
                        visited += 1;
                        try model.expectation(entry.handle);
                        try testing.expectEqual(model.slots[entry.handle.index].value, entry.value.*);
                    }
                    try testing.expectEqual(model.live, visited);
                },
                else => unreachable,
            }
        }
        try testing.expectEqual(model.live, table.count());
        try table.expectInvariants();
    }

    var iterator = table.iterator();
    while (iterator.next()) |entry| _ = try table.remove(entry.handle);
    try testing.expectEqual(0, table.count());
    try table.expectInvariants();
}

test "fixed-seed random operations agree with a reference model of live, stale, and retired handles" {
    const seeds = [_]u64{ 0x0000_0000_0000_0001, 0x5EED_F00D_CAFE_0004, 0xFA1E_9A4E_0000_2026 };
    for (seeds) |seed| {
        try runModel(.{ .Index = u2, .Generation = u1 }, seed, 2000);
        try runModel(.{ .Index = u3, .Generation = u2 }, seed, 4000);
        try runModel(.{ .Index = u4, .Generation = u3 }, seed, 4000);
    }
}
