//! The measurement harness of the value representations and tracers.
//!
//! Each executable instantiates one representation and accepts no arguments.
//! Before it measures, it checks the frozen number vectors in its own optimize mode.
//! It then runs each workload once as warmup and 11 more times, each sample on a fresh heap.
//! It writes raw samples only, one JSON object per line, and computes no summary.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const number_vectors = @import("number_vectors.zig");
const runtime = @import("runtime.zig");
const Allocator = std.mem.Allocator;
const CellRef = runtime.CellRef;

pub const Workload = enum {
    add_small_int,
    add_fraction,
    get_prototype_chain,
    number_to_string,
    object_churn,
    mark_generated,
    mark_manual,

    pub fn name(workload: Workload) []const u8 {
        return switch (workload) {
            .add_small_int => "add-small-int",
            .add_fraction => "add-fraction",
            .get_prototype_chain => "get-prototype-chain",
            .number_to_string => "number-to-string",
            .object_churn => "object-churn",
            .mark_generated => "mark-generated",
            .mark_manual => "mark-manual",
        };
    }
};

pub const Options = struct {
    /// Divides every iteration and object count; 1 is full size.
    divisor: u32 = 1,
    /// The size of the running executable, which the header reports.
    executable_bytes: u64,
    warmups: usize = 1,
    samples: usize = 11,
};

pub const Outcome = enum { passed, vector_mismatch, checksum_mismatch };

/// Counts requested bytes and peak live bytes of the backing allocator.
const CountingAllocator = struct {
    backing: Allocator,
    requested: u64 = 0,
    live: u64 = 0,
    peak: u64 = 0,

    fn allocator(self: *CountingAllocator) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn grow(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len > old_len) self.requested += new_len - old_len;
        self.live = self.live + new_len - old_len;
        self.peak = @max(self.peak, self.live);
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const memory = self.backing.vtable.alloc(self.backing.ptr, len, alignment, ret_addr) orelse return null;
        self.grow(0, len);
        return memory;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        if (!self.backing.vtable.resize(self.backing.ptr, memory, alignment, new_len, ret_addr)) return false;
        self.grow(memory.len, new_len);
        return true;
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const moved = self.backing.vtable.remap(self.backing.ptr, memory, alignment, new_len, ret_addr) orelse return null;
        self.grow(memory.len, new_len);
        return moved;
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.backing.vtable.free(self.backing.ptr, memory, alignment, ret_addr);
        self.live -= memory.len;
    }
};

const Checksum = union(enum) {
    text: []const u8,
    count: u64,

    fn eql(a: Checksum, b: Checksum) bool {
        return switch (a) {
            .text => |text| b == .text and std.mem.eql(u8, text, b.text),
            .count => |count| b == .count and b.count == count,
        };
    }
};

const Sample = struct {
    ns: u64,
    cells_allocated: u64,
    bytes_allocated: u64,
    peak_live_bytes: u64,
    collections: u64,
    checksum: Checksum,
    /// Holds the code units of a text checksum.
    text: [32]u8 = undefined,
};

fn decimalDigits(n: u64) u64 {
    var digits: u64 = 1;
    var rest = n / 10;
    while (rest != 0) : (rest /= 10) digits += 1;
    return digits;
}

/// Computes each scaled checksum of the "Measurement" table independently of the runtime.
fn expectedChecksum(workload: Workload, divisor: u32, buffer: []u8) Checksum {
    const iterations: u64 = 1_000_000 / divisor;
    const objects: u64 = 100_000 / divisor;
    return switch (workload) {
        .add_small_int => .{ .text = std.fmt.bufPrint(buffer, "{d}", .{iterations}) catch unreachable },
        .add_fraction => .{ .text = std.fmt.bufPrint(buffer, "{d}", .{iterations / 2}) catch unreachable },
        .get_prototype_chain => .{ .text = std.fmt.bufPrint(buffer, "{d}", .{iterations * 7}) catch unreachable },
        .number_to_string => blk: {
            // `i + 0.25` renders as the digits of i followed by ".25".
            var total: u64 = 0;
            for (0..objects) |i| total += decimalDigits(i) + 3;
            break :blk .{ .count = total };
        },
        .object_churn => .{ .count = (objects + 15) / 16 },
        .mark_generated, .mark_manual => .{ .count = objects },
    };
}

fn Workloads(comptime Rt: type) type {
    return struct {
        const Context = Rt.Context(.all);
        const Error = error{ OutOfMemory, Throw };

        fn liveObjectsOutsideIntrinsics(heap: *Rt.Heap) u64 {
            var count: u64 = 0;
            for (0..heap.slotCount()) |index| {
                const ref: CellRef = @fromBackingInt(@as(u32, @intCast(index)));
                if (heap.isLive(ref) and heap.kindOf(ref) == .ordinary_object) count += 1;
            }
            // object_prototype, function_prototype, error_prototype, and type_error_prototype.
            return count - 4;
        }

        fn textChecksum(ctx: *Context, v: Rt.Value, sample: *Sample) Error!void {
            const string = try ctx.invoke(.to_string, .{v});
            const units = ctx.stringUnits(string);
            if (units.len > sample.text.len) {
                sample.checksum = .{ .text = "overflow" };
                return;
            }
            for (units, 0..) |unit, i| sample.text[i] = if (unit < 0x80) @intCast(unit) else '?';
            sample.checksum = .{ .text = sample.text[0..units.len] };
        }

        fn defineData(ctx: *Context, object: CellRef, key: CellRef, v: Rt.Value) Error!void {
            const descriptor: Rt.PropertyDescriptor = .{ .value = v, .writable = true, .enumerable = true, .configurable = true };
            if (!try ctx.invoke(.ordinary_define_own_property, .{ object, key, descriptor })) unreachable;
        }

        fn defineNumbers(ctx: *Context, object: CellRef, keys: [4]CellRef, i: u64) Error!void {
            const base: f64 = @floatFromInt(i);
            const offsets = [_]f64{ 0.25, 0.5, 0.75, 1.25 };
            for (keys, offsets) |key, offset| try defineData(ctx, object, key, try ctx.allocateNumber(base + offset));
        }

        /// Runs one workload on the heap that `rt` owns and times only its steps.
        fn runWorkload(rt: *Rt, workload: Workload, divisor: u32, io: std.Io, sample: *Sample) Error!void {
            const heap = &rt.heap;
            var ctx = rt.rootContext();
            var scope = try ctx.openScope();
            defer scope.close();
            const iterations: u64 = 1_000_000 / divisor;
            const objects: u64 = 100_000 / divisor;
            const prototype = ctx.intrinsics().object_prototype;
            var keys: [4]CellRef = undefined;
            for (&keys, [_][]const u8{ "a", "b", "c", "d" }) |*key, text| {
                key.* = try ctx.allocateAsciiString(text);
                _ = try scope.push(Rt.cellValue(key.*));
            }
            const next_key = try ctx.allocateAsciiString("next");
            _ = try scope.push(Rt.cellValue(next_key));
            const k_key = try ctx.allocateAsciiString("k");
            _ = try scope.push(Rt.cellValue(k_key));
            const slot = try scope.push(Rt.undefined_value);
            const operand = try scope.push(Rt.undefined_value);

            switch (workload) {
                .add_small_int, .add_fraction => {
                    slot.set(try ctx.allocateNumber(0));
                    operand.set(try ctx.allocateNumber(if (workload == .add_small_int) 1 else 0.5));
                    const start = std.Io.Clock.awake.now(io);
                    for (0..iterations) |_| slot.set(try ctx.invoke(.addition, .{ slot.get(), operand.get() }));
                    sample.ns = elapsed(io, start);
                    try textChecksum(&ctx, slot.get(), sample);
                },
                .get_prototype_chain => {
                    // o → p1 → ... → p8, and p8 has "k" with value 7.
                    var chain = try ctx.allocateObject(prototype);
                    slot.set(Rt.cellValue(chain));
                    try defineData(&ctx, chain, k_key, try ctx.allocateNumber(7));
                    for (0..8) |_| {
                        chain = try ctx.allocateObject(chain);
                        slot.set(Rt.cellValue(chain));
                    }
                    const receiver = slot.get();
                    var sum: f64 = 0;
                    const start = std.Io.Clock.awake.now(io);
                    for (0..iterations) |_| {
                        const found = try ctx.invoke(.ordinary_get, .{ chain, k_key, receiver });
                        operand.set(found);
                        sum = ctx.invoke(.number_add, .{ sum, try ctx.invoke(.to_number, .{found}) });
                    }
                    sample.ns = elapsed(io, start);
                    operand.set(try ctx.allocateNumber(sum));
                    try textChecksum(&ctx, operand.get(), sample);
                },
                .number_to_string => {
                    var total: u64 = 0;
                    const start = std.Io.Clock.awake.now(io);
                    for (0..objects) |i| {
                        slot.set(try ctx.allocateNumber(@as(f64, @floatFromInt(i)) + 0.25));
                        total += ctx.stringUnits(try ctx.invoke(.to_string, .{slot.get()})).len;
                    }
                    sample.ns = elapsed(io, start);
                    sample.checksum = .{ .count = total };
                },
                .object_churn => {
                    const start = std.Io.Clock.awake.now(io);
                    for (0..objects) |i| {
                        const object = try ctx.allocateObject(prototype);
                        slot.set(Rt.cellValue(object));
                        try defineNumbers(&ctx, object, keys, i);
                        if (i % 16 == 0) _ = try heap.addPersistent(slot.get());
                    }
                    slot.set(Rt.undefined_value);
                    ctx.collect();
                    sample.ns = elapsed(io, start);
                    sample.checksum = .{ .count = liveObjectsOutsideIntrinsics(heap) };
                },
                .mark_generated, .mark_manual => {
                    // slot holds the head of the chain, which a persistent root keeps after the build.
                    for (0..objects) |i| {
                        const object = try ctx.allocateObject(prototype);
                        const previous = slot.get();
                        slot.set(Rt.cellValue(object));
                        operand.set(previous);
                        try defineNumbers(&ctx, object, keys, i);
                        if (Rt.cellOf(previous) != null) try defineData(&ctx, object, next_key, previous);
                    }
                    _ = try heap.addPersistent(slot.get());
                    operand.set(Rt.undefined_value);
                    const start = std.Io.Clock.awake.now(io);
                    ctx.collect();
                    sample.ns = elapsed(io, start);
                    sample.checksum = .{ .count = liveObjectsOutsideIntrinsics(heap) };
                },
            }
        }

        /// Fills `sample` in place, because a text checksum points into it.
        fn measureOnce(workload: Workload, divisor: u32, io: std.Io, sample: *Sample) !void {
            var counting: CountingAllocator = .{ .backing = std.heap.smp_allocator };
            sample.* = .{ .ns = 0, .cells_allocated = 0, .bytes_allocated = 0, .peak_live_bytes = 0, .collections = 0, .checksum = .{ .count = 0 } };
            {
                const tracer: runtime.Tracer = if (workload == .mark_manual) .manual else .generated;
                var rt = try Rt.init(counting.allocator(), .{ .tracer = tracer });
                defer rt.deinit();
                try runWorkload(&rt, workload, divisor, io, sample);
                sample.cells_allocated = rt.heap.stats.cells_allocated;
                sample.collections = rt.heap.stats.collections;
            }
            if (counting.live != 0) return error.LeakedMemory;
            sample.bytes_allocated = counting.requested;
            sample.peak_live_bytes = counting.peak;
        }
    };
}

fn elapsed(io: std.Io, start: std.Io.Timestamp) u64 {
    const duration = start.durationTo(std.Io.Clock.awake.now(io));
    return @intCast(duration.nanoseconds);
}

fn writeChecksum(writer: *std.Io.Writer, checksum: Checksum) std.Io.Writer.Error!void {
    switch (checksum) {
        .text => |text| try writer.print("\"{s}\"", .{text}),
        .count => |count| try writer.print("{d}", .{count}),
    }
}

/// Checks the vectors, then writes the header line and one line per sample.
/// Returns `.checksum_mismatch` after it writes every line when a checksum differs.
pub fn run(comptime r: runtime.Representation, io: std.Io, writer: *std.Io.Writer, options: Options) !Outcome {
    const Rt = runtime.Runtime(r);
    {
        var rt = try Rt.init(std.heap.smp_allocator, .{});
        defer rt.deinit();
        if (try number_vectors.selfCheck(Rt, &rt) != 0) return .vector_mismatch;
    }
    const target = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.abi);
    try std.json.Stringify.value(.{
        .format = "fairpane-js-measure",
        .version = 1,
        .representation = @tagName(r),
        .value_size_bytes = @sizeOf(Rt.Value),
        .zig_version = builtin.zig_version_string,
        .target = target,
        .cpu_model = builtin.cpu.model.name,
        .optimize = @tagName(builtin.mode),
        .logical_cpus = std.Thread.getCpuCount() catch 0,
        .executable_bytes = options.executable_bytes,
        .clock = "awake",
        .allocator = "smp_allocator",
    }, .{}, writer);
    try writer.writeByte('\n');

    const W = Workloads(Rt);
    var outcome: Outcome = .passed;
    for (std.enums.values(Workload)) |workload| {
        var expected_buffer: [32]u8 = undefined;
        const expected = expectedChecksum(workload, options.divisor, &expected_buffer);
        for (0..options.warmups + options.samples) |index| {
            var sample: Sample = undefined;
            try W.measureOnce(workload, options.divisor, io, &sample);
            try writer.print(
                "{{\"workload\":\"{s}\",\"sample\":{d},\"warmup\":{},\"ns\":{d},\"cells_allocated\":{d},\"bytes_allocated\":{d},\"peak_live_bytes\":{d},\"collections\":{d},\"checksum\":",
                .{ workload.name(), index, index < options.warmups, sample.ns, sample.cells_allocated, sample.bytes_allocated, sample.peak_live_bytes, sample.collections },
            );
            try writeChecksum(writer, sample.checksum);
            try writer.writeAll("}\n");
            if (!sample.checksum.eql(expected)) outcome = .checksum_mismatch;
        }
        try writer.flush();
    }
    return outcome;
}

/// The entry point of each measurement executable.
pub fn main(init: std.process.Init, comptime r: runtime.Representation) !void {
    const io = init.io;
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len > 1) {
        std.debug.print("fairpane-js-measure-{s} accepts no arguments\n", .{@tagName(r)});
        std.process.exit(1);
    }
    const path = try std.process.executablePathAlloc(io, init.gpa);
    defer init.gpa.free(path);
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buffer);
    const outcome = try run(r, io, &stdout.interface, .{ .executable_bytes = stat.size });
    try stdout.interface.flush();
    switch (outcome) {
        .passed => {},
        .vector_mismatch => {
            std.debug.print("fairpane-js-measure-{s}: a number vector differs in this optimize mode\n", .{@tagName(r)});
            std.process.exit(1);
        },
        .checksum_mismatch => {
            std.debug.print("fairpane-js-measure-{s}: a checksum differs\n", .{@tagName(r)});
            std.process.exit(1);
        },
    }
}

const expected_checksums = [_]struct { []const u8, []const u8 }{
    .{ "add-small-int", "\"1000\"" },
    .{ "add-fraction", "\"500\"" },
    .{ "get-prototype-chain", "\"7000\"" },
    .{ "number-to-string", "490" },
    .{ "object-churn", "7" },
    .{ "mark-generated", "100" },
    .{ "mark-manual", "100" },
};

test "FP-0011 case 33: every workload runs at divisor 1000 with the scaled checksums" {
    const sizes = [_]i64{ 16, 8, 4 };
    inline for (.{ .reference, .nan_box, .tagged_index }, sizes) |r, size| {
        var output: std.Io.Writer.Allocating = .init(testing.allocator);
        defer output.deinit();
        const outcome = try run(r, testing.io, &output.writer, .{ .divisor = 1000, .executable_bytes = 0 });

        var lines = std.mem.splitScalar(u8, output.written(), '\n');
        const header_line = lines.next().?;
        const header = try std.json.parseFromSlice(std.json.Value, testing.allocator, header_line, .{});
        defer header.deinit();
        const header_fields = [_][]const u8{ "format", "version", "representation", "value_size_bytes", "zig_version", "target", "cpu_model", "optimize", "logical_cpus", "executable_bytes", "clock", "allocator" };
        for (header_fields) |field| try testing.expect(header.value.object.get(field) != null);
        try testing.expectEqualStrings("fairpane-js-measure", header.value.object.get("format").?.string);
        try testing.expectEqual(1, header.value.object.get("version").?.integer);
        try testing.expectEqualStrings(@tagName(r), header.value.object.get("representation").?.string);
        try testing.expectEqual(size, header.value.object.get("value_size_bytes").?.integer);
        try testing.expectEqualStrings("awake", header.value.object.get("clock").?.string);
        try testing.expectEqualStrings("smp_allocator", header.value.object.get("allocator").?.string);

        const sample_fields = [_][]const u8{ "workload", "sample", "warmup", "ns", "cells_allocated", "bytes_allocated", "peak_live_bytes", "collections", "checksum" };
        var samples: usize = 0;
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const sample = try std.json.parseFromSlice(std.json.Value, testing.allocator, line, .{});
            defer sample.deinit();
            for (sample_fields) |field| try testing.expect(sample.value.object.get(field) != null);
            const workload = sample.value.object.get("workload").?.string;
            var checksum: std.Io.Writer.Allocating = .init(testing.allocator);
            defer checksum.deinit();
            try std.json.Stringify.value(sample.value.object.get("checksum").?, .{}, &checksum.writer);
            var matched = false;
            for (expected_checksums) |pair| {
                if (!std.mem.eql(u8, pair[0], workload)) continue;
                try testing.expectEqualStrings(pair[1], checksum.written());
                matched = true;
            }
            try testing.expect(matched);
            samples += 1;
        }
        try testing.expectEqual(expected_checksums.len * 12, samples);
        try testing.expectEqual(Outcome.passed, outcome);
    }
}
