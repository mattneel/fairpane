//! The managed heap of the JavaScript runtime.
//!
//! The cell table holds one pointer per slot, and each cell is its own allocation, so a `*Cell`
//! stays valid until the cell is freed.
//! The collector is precise, non-moving mark and sweep:
//!
//! 1. Every mark bit is clear between collections.
//! 2. Marking pushes every root on a worklist, marking each cell as it pushes it.
//! 3. Marking pops cells and pushes their unmarked referents through the selected tracer.
//! 4. Sweeping finalizes and frees every unmarked cell, or quarantines it, and clears every mark.
//!
//! Allocation reserves the worklist and the free list for the whole table before it changes the heap,
//! so a collection never allocates and a failed allocation leaves the heap unchanged.
//!
//! Roots are the scope stack, the persistent roots, the pending exception, and the intrinsic record.
//! A platform object holds one `retain` of its DOM node, which its finalizer releases.
//! No DOM node references a JavaScript cell yet, so no cross-heap cycle can form.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const dom = @import("../dom.zig");
const heap_catalog = @import("heap_catalog.zig");
const operations = @import("operations.zig");
const runtime = @import("runtime.zig");
const web_string = @import("../web_string.zig");
const CellRef = @import("value.zig").CellRef;
const Allocator = std.mem.Allocator;
const WebString = web_string.WebString;

/// Selects the tracer that marking uses. Both tracers stay built and tested.
pub const Tracer = enum {
    /// Derived from the layouts in `heap_catalog.zig` at compile time.
    generated,
    /// Written by hand with one switch arm per kind; the reference of the trace generation experiment.
    manual,
};

pub fn Heap(comptime Rt: type) type {
    return struct {
        const Self = @This();
        const E = Rt.V;

        pub const Value = Rt.Value;
        pub const Kind = heap_catalog.Kind;
        pub const catalog = heap_catalog.Payloads(E, Rt.Behavior);
        pub const Payload = catalog.Payload;
        pub const Property = catalog.Property;
        pub const ObjectHeader = catalog.ObjectHeader;

        pub const Cell = struct {
            payload: Payload,
            /// Set only while a collection marks.
            marked: bool = false,
            /// Set for a quarantined cell, which stays intact and whose slot is never reused.
            dead: bool = false,
            /// The allocation sequence number, which orders the cell against the outermost `invoke`.
            serial: u64,

            pub fn kind(cell: *const Cell) Kind {
                return std.meta.activeTag(cell.payload);
            }
        };

        pub const Options = struct {
            /// The live cell limit. `init` caps it at `max_cell_index + 1`.
            max_cells: usize = std.math.maxInt(usize),
            /// Runs a full collection before every managed allocation.
            collect_before_each_allocation: bool = false,
            /// Keeps each unreachable cell intact as dead and never reuses its slot.
            quarantine_freed_cells: bool = false,
            tracer: Tracer = .generated,
            /// The DOM store of platform objects, which must outlive the heap.
            dom: ?*dom.Store = null,
        };

        pub const Stats = struct {
            cells_allocated: u64 = 0,
            collections: u64 = 0,
            behaviors_invoked: u64 = 0,
            throws: u64 = 0,
            /// Writes to cells that were allocated before the outermost `invoke` began.
            existing_cell_writes: u64 = 0,
            /// Resolutions of a quarantined cell, each of which is a rooting error.
            dead_resolutions: u64 = 0,
        };

        /// Cells that are always roots. This record is not a realm and holds no constructors or methods.
        pub const Intrinsics = struct {
            object_prototype: CellRef,
            function_prototype: CellRef,
            error_prototype: CellRef,
            type_error_prototype: CellRef,
            symbol_to_primitive: CellRef,
            empty_string: CellRef,
            undefined_string: CellRef,
            null_string: CellRef,
            true_string: CellRef,
            false_string: CellRef,
            default_string: CellRef,
            string_string: CellRef,
            number_string: CellRef,
            to_string_string: CellRef,
            value_of_string: CellRef,
            message_string: CellRef,
            name_string: CellRef,
            error_string: CellRef,
            type_error_string: CellRef,
        };

        /// The number of intrinsic roots.
        pub const intrinsic_root_count = @typeInfo(Intrinsics).@"struct".field_names.len;
        /// The intrinsic roots and the description string of `%Symbol.toPrimitive%`.
        pub const intrinsic_cell_count = intrinsic_root_count + 1;

        const intrinsic_strings = .{
            .{ "empty_string", "" },
            .{ "undefined_string", "undefined" },
            .{ "null_string", "null" },
            .{ "true_string", "true" },
            .{ "false_string", "false" },
            .{ "default_string", "default" },
            .{ "string_string", "string" },
            .{ "number_string", "number" },
            .{ "to_string_string", "toString" },
            .{ "value_of_string", "valueOf" },
            .{ "message_string", "message" },
            .{ "name_string", "name" },
            .{ "error_string", "Error" },
            .{ "type_error_string", "TypeError" },
        };

        /// Test builds count, for each operation, its invocations and the counters that moved without the effect.
        pub const EffectMonitor = if (builtin.is_test) struct {
            checked: [operations.catalog.len]u64 = @splat(0),
            violations: u64 = 0,
        } else struct {};

        pub const Persistent = struct { index: u32 };

        /// A scope-stack entry.
        pub const Local = struct {
            heap: *Self,
            index: usize,

            pub fn get(local: Local) Value {
                return local.heap.scope_stack.items[local.index];
            }

            pub fn set(local: Local, v: Value) void {
                local.heap.scope_stack.items[local.index] = v;
            }
        };

        /// Roots every value pushed until `close`. Scopes close in reverse order of opening.
        pub const Scope = struct {
            heap: *Self,
            base: usize,
            depth: usize,

            pub fn push(scope: *Scope, v: Value) error{OutOfMemory}!Local {
                const heap = scope.heap;
                std.debug.assert(scope.depth == heap.scope_depth);
                try heap.scope_stack.append(heap.gpa, v);
                return .{ .heap = heap, .index = heap.scope_stack.items.len - 1 };
            }

            pub fn close(scope: *Scope) void {
                const heap = scope.heap;
                std.debug.assert(scope.depth == heap.scope_depth);
                heap.scope_stack.shrinkRetainingCapacity(scope.base);
                heap.scope_depth -= 1;
            }
        };

        gpa: Allocator,
        options: Options,
        /// Null marks a free slot.
        cells: std.ArrayList(?*Cell) = .empty,
        free_slots: std.ArrayList(u32) = .empty,
        /// The number of cells that are neither free nor quarantined.
        live: usize = 0,
        worklist: std.ArrayList(CellRef) = .empty,
        scope_stack: std.ArrayList(Value) = .empty,
        scope_depth: usize = 0,
        persistents: std.ArrayList(?Value) = .empty,
        free_persistents: std.ArrayList(u32) = .empty,
        pending_exception: ?Value = null,
        intrinsics: Intrinsics = undefined,
        stats: Stats = .{},
        next_serial: u64 = 0,
        /// True while `init` creates the intrinsics, which are not yet roots.
        initializing: bool = false,
        invoke_depth: u32 = 0,
        /// The first serial allocated after the outermost `invoke` began.
        invoke_boundary: u64 = 0,
        /// The built-in function whose behavior runs.
        active_function: ?CellRef = null,
        /// The retains that live and quarantined platform objects hold.
        platform_retains: usize = 0,
        effect_monitor: EffectMonitor = .{},

        pub fn init(gpa: Allocator, options: Options) error{OutOfMemory}!Self {
            var heap: Self = .{ .gpa = gpa, .options = options };
            const index_limit = std.math.cast(usize, @as(u64, E.max_cell_index) + 1) orelse std.math.maxInt(usize);
            heap.options.max_cells = @min(options.max_cells, index_limit);
            if (heap.options.max_cells < intrinsic_cell_count) return error.OutOfMemory;
            errdefer heap.deinit();
            heap.initializing = true;
            try heap.createIntrinsics();
            heap.initializing = false;
            return heap;
        }

        /// Finalizes every cell, including quarantined ones, and releases every retain that the heap holds.
        pub fn deinit(self: *Self) void {
            for (self.cells.items) |slot| {
                const cell = slot orelse continue;
                self.finalizeCell(cell);
                self.gpa.destroy(cell);
            }
            self.cells.deinit(self.gpa);
            self.free_slots.deinit(self.gpa);
            self.worklist.deinit(self.gpa);
            self.scope_stack.deinit(self.gpa);
            self.persistents.deinit(self.gpa);
            self.free_persistents.deinit(self.gpa);
            self.* = undefined;
        }

        fn createIntrinsics(self: *Self) error{OutOfMemory}!void {
            var intrinsics: Intrinsics = undefined;
            inline for (intrinsic_strings) |pair| {
                @field(intrinsics, pair[0]) = try self.allocateAsciiString(pair[1]);
            }
            intrinsics.object_prototype = try self.allocateObject(null);
            intrinsics.function_prototype = try self.allocateObject(intrinsics.object_prototype);
            intrinsics.error_prototype = try self.allocateObject(intrinsics.object_prototype);
            try self.appendIntrinsicProperty(intrinsics.error_prototype, intrinsics.name_string, intrinsics.error_string);
            try self.appendIntrinsicProperty(intrinsics.error_prototype, intrinsics.message_string, intrinsics.empty_string);
            intrinsics.type_error_prototype = try self.allocateObject(intrinsics.error_prototype);
            try self.appendIntrinsicProperty(intrinsics.type_error_prototype, intrinsics.name_string, intrinsics.type_error_string);
            try self.appendIntrinsicProperty(intrinsics.type_error_prototype, intrinsics.message_string, intrinsics.empty_string);
            intrinsics.symbol_to_primitive = try self.allocateSymbol(try self.allocateAsciiString("Symbol.toPrimitive"));
            self.intrinsics = intrinsics;
            std.debug.assert(self.live == intrinsic_cell_count);
        }

        fn appendIntrinsicProperty(self: *Self, object: CellRef, key: CellRef, string: CellRef) error{OutOfMemory}!void {
            try self.appendProperty(object, .{
                .key = key,
                .enumerable = false,
                .configurable = true,
                .slot = .{ .data = .{ .value = E.fromCell(@backingInt(string)), .writable = true } },
            });
        }

        // Cells.

        /// Returns the cell of `ref`. Resolving a quarantined cell counts a dead resolution.
        pub fn resolve(self: *Self, ref: CellRef) *Cell {
            const cell = self.cellAt(ref);
            if (cell.dead) self.stats.dead_resolutions += 1;
            return cell;
        }

        fn cellAt(self: *const Self, ref: CellRef) *Cell {
            const index: usize = @backingInt(ref);
            if (index >= self.cells.items.len) std.debug.panic("fairpane-js: CellRef {d} is outside the cell table", .{index});
            return self.cells.items[index] orelse std.debug.panic("fairpane-js: CellRef {d} refers to a freed cell", .{index});
        }

        pub fn kindOf(self: *Self, ref: CellRef) Kind {
            return self.resolve(ref).kind();
        }

        /// Holds when `ref` names a cell that is neither free nor quarantined.
        pub fn isLive(self: *const Self, ref: CellRef) bool {
            const index: usize = @backingInt(ref);
            if (index >= self.cells.items.len) return false;
            const cell = self.cells.items[index] orelse return false;
            return !cell.dead;
        }

        pub fn liveCount(self: *const Self) usize {
            return self.live;
        }

        pub fn slotCount(self: *const Self) usize {
            return self.cells.items.len;
        }

        /// Takes ownership of `payload` only on success.
        fn allocateCell(self: *Self, payload: Payload) error{OutOfMemory}!CellRef {
            if (!self.initializing and (self.options.collect_before_each_allocation or self.live >= self.options.max_cells)) {
                self.collect();
            }
            if (self.live >= self.options.max_cells) return error.OutOfMemory;
            const reuse = self.free_slots.items.len != 0;
            if (!reuse) {
                if (self.cells.items.len > E.max_cell_index) return error.OutOfMemory;
                try self.cells.ensureUnusedCapacity(self.gpa, 1);
                try self.free_slots.ensureTotalCapacity(self.gpa, self.cells.items.len + 1);
                try self.worklist.ensureTotalCapacity(self.gpa, self.cells.items.len + 1);
            }
            const cell = try self.gpa.create(Cell);
            cell.* = .{ .payload = payload, .serial = self.next_serial };
            self.next_serial += 1;
            const index: u32 = if (reuse) self.free_slots.pop().? else @intCast(self.cells.items.len);
            if (reuse) self.cells.items[index] = cell else self.cells.appendAssumeCapacity(cell);
            self.live += 1;
            self.stats.cells_allocated += 1;
            return @fromBackingInt(index);
        }

        fn finalizeCell(self: *Self, cell: *Cell) void {
            if (cell.kind() == .platform_object) self.platform_retains -= 1;
            catalog.finalize(&cell.payload, self.gpa, self.options.dom);
        }

        pub fn allocateString(self: *Self, units: []const u16) error{OutOfMemory}!CellRef {
            var string = try WebString.fromCodeUnits(self.gpa, units);
            errdefer string.deinit(self.gpa);
            return self.allocateCell(.{ .string = .{ .units = string } });
        }

        /// Widens ASCII `bytes` to code units.
        pub fn allocateAsciiString(self: *Self, bytes: []const u8) error{OutOfMemory}!CellRef {
            var string: WebString = .empty;
            if (bytes.len != 0) {
                const units = try self.gpa.alloc(u16, bytes.len);
                for (units, bytes) |*unit, byte| unit.* = byte;
                string = .{ .units = units };
            }
            errdefer string.deinit(self.gpa);
            return self.allocateCell(.{ .string = .{ .units = string } });
        }

        /// Returns `error.OutOfMemory` when the length overflows `usize` or an allocation fails.
        pub fn allocateConcatenation(self: *Self, a: CellRef, b: CellRef) error{OutOfMemory}!CellRef {
            const left = self.stringUnits(a);
            const right = self.stringUnits(b);
            const len = std.math.add(usize, left.len, right.len) catch return error.OutOfMemory;
            var string: WebString = .empty;
            if (len != 0) {
                const units = try self.gpa.alloc(u16, len);
                @memcpy(units[0..left.len], left);
                @memcpy(units[left.len..], right);
                string = .{ .units = units };
            }
            errdefer string.deinit(self.gpa);
            return self.allocateCell(.{ .string = .{ .units = string } });
        }

        pub fn allocateSymbol(self: *Self, description: ?CellRef) error{OutOfMemory}!CellRef {
            return self.allocateCell(.{ .symbol = .{ .description = description } });
        }

        /// Copies the normalized limbs of `big`. Zero is stored as positive.
        pub fn allocateBigInt(self: *Self, big: std.math.big.int.Const) error{OutOfMemory}!CellRef {
            const limbs = try self.gpa.dupe(std.math.big.Limb, big.limbs);
            errdefer self.gpa.free(limbs);
            return self.allocateCell(.{ .bigint = .{ .positive = big.positive or big.eqlZero(), .limbs = limbs } });
        }

        fn emptyHeader(prototype: ?CellRef) ObjectHeader {
            return .{ .prototype = prototype, .extensible = true, .properties = .empty };
        }

        pub fn allocateObject(self: *Self, prototype: ?CellRef) error{OutOfMemory}!CellRef {
            return self.allocateCell(.{ .ordinary_object = .{ .object = emptyHeader(prototype) } });
        }

        pub fn allocateErrorObject(self: *Self, prototype: ?CellRef) error{OutOfMemory}!CellRef {
            return self.allocateCell(.{ .error_object = .{ .object = emptyHeader(prototype), .error_kind = .type_error } });
        }

        /// Creates a built-in function whose prototype is `%Function.prototype%`.
        pub fn allocateFunction(self: *Self, behavior: Rt.Behavior, host_data: Value, host_context: ?*anyopaque) error{OutOfMemory}!CellRef {
            return self.allocateCell(.{ .builtin_function = .{
                .object = emptyHeader(self.intrinsics.function_prototype),
                .behavior = behavior,
                .host_data = host_data,
                .host_context = host_context,
            } });
        }

        pub const PlatformObjectError = error{ OutOfMemory, NoStore } || dom.LookupError;

        /// Retains `node` in `Options.dom` before it creates the cell, and releases it if the allocation fails.
        pub fn allocatePlatformObject(self: *Self, prototype: ?CellRef, node: dom.NodeHandle) PlatformObjectError!CellRef {
            const store = self.options.dom orelse return error.NoStore;
            try store.retain(node);
            errdefer store.release(node) catch unreachable;
            const object = try self.allocateCell(.{ .platform_object = .{ .object = emptyHeader(prototype), .node = node } });
            self.platform_retains += 1;
            return object;
        }

        /// Boxes a number. Only `tagged_index` allocates, for a number that is not inline.
        pub fn numberValue(self: *Self, x: f64) error{OutOfMemory}!Value {
            if (E.fromInlineNumber(x)) |inline_value| return inline_value;
            return E.fromCell(@backingInt(try self.allocateCell(.{ .heap_number = .{ .value = x } })));
        }

        /// Returns the number of an inline value or a `heap_number` cell.
        pub fn numberOf(self: *Self, v: Value) f64 {
            return switch (E.classify(v)) {
                .number => E.asNumber(v),
                .cell => self.resolve(@fromBackingInt(E.asCell(v))).payload.heap_number.value,
                .undefined, .null, .boolean => unreachable,
            };
        }

        pub fn stringUnits(self: *Self, string: CellRef) []const u16 {
            return self.resolve(string).payload.string.units.units;
        }

        pub fn bigIntOf(self: *Self, big: CellRef) std.math.big.int.Const {
            const payload = self.resolve(big).payload.bigint;
            return .{ .limbs = payload.limbs, .positive = payload.positive };
        }

        // Objects.

        pub fn header(self: *Self, object: CellRef) *ObjectHeader {
            const cell = self.resolve(object);
            return catalog.objectHeader(&cell.payload) orelse std.debug.panic("fairpane-js: cell {d} is not an object", .{@backingInt(object)});
        }

        /// Compares property keys: symbols by identity and strings by code units.
        pub fn sameKey(self: *Self, a: CellRef, b: CellRef) bool {
            if (a == b) return true;
            const left = self.resolve(a);
            const right = self.resolve(b);
            if (left.kind() != .string or right.kind() != .string) return false;
            return std.mem.eql(u16, left.payload.string.units.units, right.payload.string.units.units);
        }

        pub fn findProperty(self: *Self, object: CellRef, key: CellRef) ?usize {
            for (self.header(object).properties.items, 0..) |property, index| {
                if (self.sameKey(property.key, key)) return index;
            }
            return null;
        }

        fn noteWrite(self: *Self, object: CellRef) void {
            if (self.invoke_depth != 0 and self.resolve(object).serial < self.invoke_boundary) {
                self.stats.existing_cell_writes += 1;
            }
        }

        pub fn appendProperty(self: *Self, object: CellRef, property: Property) error{OutOfMemory}!void {
            try self.header(object).properties.append(self.gpa, property);
            self.noteWrite(object);
        }

        pub fn writeProperty(self: *Self, object: CellRef, index: usize, property: Property) void {
            self.header(object).properties.items[index] = property;
            self.noteWrite(object);
        }

        pub fn preventExtensions(self: *Self, object: CellRef) void {
            self.header(object).extensible = false;
            self.noteWrite(object);
        }

        // Exceptions.

        pub fn throwValue(self: *Self, thrown: Value) error{Throw} {
            self.pending_exception = thrown;
            self.stats.throws += 1;
            return error.Throw;
        }

        /// Throws a new `error_object` whose prototype is `%TypeError.prototype%` and whose own
        /// `"message"` property is `message`.
        pub fn throwTypeError(self: *Self, message: []const u8) error{ OutOfMemory, Throw } {
            var scope = try self.openScope();
            defer scope.close();
            const text = try self.allocateAsciiString(message);
            _ = try scope.push(E.fromCell(@backingInt(text)));
            const thrown = try self.allocateErrorObject(self.intrinsics.type_error_prototype);
            try self.appendProperty(thrown, .{
                .key = self.intrinsics.message_string,
                .enumerable = false,
                .configurable = true,
                .slot = .{ .data = .{ .value = E.fromCell(@backingInt(text)), .writable = true } },
            });
            return self.throwValue(E.fromCell(@backingInt(thrown)));
        }

        /// Returns the pending exception and clears the slot.
        pub fn takeException(self: *Self) ?Value {
            defer self.pending_exception = null;
            return self.pending_exception;
        }

        // Roots.

        pub fn openScope(self: *Self) error{OutOfMemory}!Scope {
            try self.scope_stack.ensureUnusedCapacity(self.gpa, 4);
            self.scope_depth += 1;
            return .{ .heap = self, .base = self.scope_stack.items.len, .depth = self.scope_depth };
        }

        pub fn addPersistent(self: *Self, v: Value) error{OutOfMemory}!Persistent {
            if (self.free_persistents.pop()) |index| {
                self.persistents.items[index] = v;
                return .{ .index = index };
            }
            try self.persistents.ensureUnusedCapacity(self.gpa, 1);
            try self.free_persistents.ensureTotalCapacity(self.gpa, self.persistents.items.len + 1);
            self.persistents.appendAssumeCapacity(v);
            return .{ .index = @intCast(self.persistents.items.len - 1) };
        }

        pub fn removePersistent(self: *Self, persistent: Persistent) void {
            std.debug.assert(self.persistents.items[persistent.index] != null);
            self.persistents.items[persistent.index] = null;
            self.free_persistents.appendAssumeCapacity(persistent.index);
        }

        /// Calls `visit` once for each root: every intrinsic, scope entry, persistent root, and the pending exception.
        pub fn forEachRoot(self: *Self, context: anytype, comptime visit: fn (@TypeOf(context), Value) void) void {
            inline for (@typeInfo(Intrinsics).@"struct".field_names) |name| {
                visit(context, E.fromCell(@backingInt(@field(self.intrinsics, name))));
            }
            for (self.scope_stack.items) |v| visit(context, v);
            for (self.persistents.items) |entry| {
                if (entry) |v| visit(context, v);
            }
            if (self.pending_exception) |v| visit(context, v);
        }

        // Collection.

        pub fn collect(self: *Self) void {
            self.stats.collections += 1;
            self.forEachRoot(self, markValue);
            while (self.worklist.pop()) |ref| {
                const cell = self.cellAt(ref);
                switch (self.options.tracer) {
                    .generated => catalog.trace(&cell.payload, self, markReference),
                    .manual => traceManual(&cell.payload, self, markReference),
                }
            }
            for (self.cells.items, 0..) |*entry, index| {
                const cell = entry.* orelse continue;
                if (cell.dead) continue;
                if (cell.marked) {
                    cell.marked = false;
                    continue;
                }
                self.live -= 1;
                if (self.options.quarantine_freed_cells) {
                    cell.dead = true;
                    continue;
                }
                self.finalizeCell(cell);
                self.gpa.destroy(cell);
                entry.* = null;
                self.free_slots.appendAssumeCapacity(@intCast(index));
            }
        }

        fn markValue(self: *Self, v: Value) void {
            if (E.classify(v) == .cell) self.markReference(@fromBackingInt(E.asCell(v)));
        }

        fn markReference(self: *Self, ref: CellRef) void {
            const cell = self.cellAt(ref);
            if (cell.dead) {
                self.stats.dead_resolutions += 1;
                return;
            }
            if (cell.marked) return;
            cell.marked = true;
            self.worklist.appendAssumeCapacity(ref);
        }

        /// Runs the selected tracer on one cell.
        pub fn traceCell(self: *Self, tracer: Tracer, ref: CellRef, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            const cell = self.cellAt(ref);
            switch (tracer) {
                .generated => catalog.trace(&cell.payload, context, visit),
                .manual => traceManual(&cell.payload, context, visit),
            }
        }

        /// The hand-written tracer, the reference of the trace generation experiment.
        fn traceManual(payload: *const Payload, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            switch (payload.*) {
                .string, .bigint, .heap_number => {},
                .symbol => |*symbol| if (symbol.description) |description| visit(context, description),
                .ordinary_object => |*object| traceHeaderManual(&object.object, context, visit),
                .builtin_function => |*function| {
                    traceHeaderManual(&function.object, context, visit);
                    if (E.classify(function.host_data) == .cell) visit(context, @fromBackingInt(E.asCell(function.host_data)));
                },
                .error_object => |*error_object| traceHeaderManual(&error_object.object, context, visit),
                .platform_object => |*platform| traceHeaderManual(&platform.object, context, visit),
            }
        }

        fn traceHeaderManual(object: *const ObjectHeader, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            if (object.prototype) |prototype| visit(context, prototype);
            for (object.properties.items) |*property| {
                visit(context, property.key);
                switch (property.slot) {
                    .data => |data| if (E.classify(data.value) == .cell) visit(context, @fromBackingInt(E.asCell(data.value))),
                    .accessor => |accessor| {
                        if (accessor.getter) |getter| visit(context, getter);
                        if (accessor.setter) |setter| visit(context, setter);
                    },
                }
            }
        }

        // Test support.

        /// Counts an operation's invocation and each counter that moved although the operation lacks its effect.
        pub fn checkEffects(self: *Self, comptime id: operations.OperationId, before: Stats) void {
            if (!builtin.is_test) @compileError("fairpane-js: checkEffects is test-only");
            const effects = comptime operations.entry(id).effects;
            self.effect_monitor.checked[@backingInt(id)] += 1;
            const moved = [_]bool{
                !effects.allocation and self.stats.cells_allocated != before.cells_allocated,
                !effects.callback and self.stats.behaviors_invoked != before.behaviors_invoked,
                !effects.exception and self.stats.throws != before.throws,
                !effects.heap_mutation and self.stats.existing_cell_writes != before.existing_cell_writes,
            };
            for (moved) |violated| {
                if (violated) {
                    self.effect_monitor.violations += 1;
                    std.debug.print("fairpane-js: {s} moved a counter of an effect that it lacks\n", .{operations.entry(id).name});
                }
            }
        }

        const Verifier = struct {
            heap: *Self,
            broken: usize = 0,

            fn visitReference(verifier: *Verifier, ref: CellRef) void {
                if (!verifier.heap.isLive(ref)) verifier.broken += 1;
            }

            fn visitRoot(verifier: *Verifier, v: Value) void {
                if (E.classify(v) == .cell) verifier.visitReference(@fromBackingInt(E.asCell(v)));
            }
        };

        fn collectNode(list: *std.ArrayList(dom.NodeHandle), node: dom.NodeHandle) void {
            list.appendAssumeCapacity(node);
        }

        /// The test-only verifier.
        pub fn expectInvariants(self: *Self) !void {
            if (!builtin.is_test) @compileError("fairpane-js: expectInvariants is test-only");
            var free = try std.DynamicBitSetUnmanaged.initEmpty(testing.allocator, self.cells.items.len);
            defer free.deinit(testing.allocator);
            for (self.free_slots.items) |index| {
                try testing.expect(index < self.cells.items.len);
                try testing.expectEqual(null, self.cells.items[index]);
                try testing.expect(!free.isSet(index));
                free.set(index);
            }
            var live: usize = 0;
            var platforms: usize = 0;
            var verifier: Verifier = .{ .heap = self };
            for (self.cells.items, 0..) |entry, index| {
                const cell = entry orelse {
                    try testing.expect(free.isSet(index));
                    try testing.expect(!self.options.quarantine_freed_cells);
                    continue;
                };
                try testing.expect(!cell.marked);
                if (cell.kind() == .platform_object) platforms += 1;
                if (cell.dead) continue;
                live += 1;
                catalog.trace(&cell.payload, &verifier, Verifier.visitReference);
            }
            try testing.expectEqual(self.live, live);
            try testing.expectEqual(0, verifier.broken);
            self.forEachRoot(&verifier, Verifier.visitRoot);
            try testing.expectEqual(0, verifier.broken);
            try testing.expectEqual(platforms, self.platform_retains);
            if (platforms != 0) {
                const store = self.options.dom orelse return error.TestExpectedStore;
                var roots: std.ArrayList(dom.NodeHandle) = .empty;
                defer roots.deinit(testing.allocator);
                try roots.ensureTotalCapacity(testing.allocator, store.nodeCount());
                store.forEachRoot(&roots, collectNode);
                for (self.cells.items) |entry| {
                    const cell = entry orelse continue;
                    if (cell.kind() != .platform_object) continue;
                    const node = cell.payload.platform_object.node;
                    _ = try store.nodeKind(node);
                    const retained = for (roots.items) |root| {
                        if (std.meta.eql(root, node)) break true;
                    } else false;
                    try testing.expect(retained);
                }
            }
        }
    };
}

const test_representations = .{ .reference, .nan_box, .tagged_index };

fn testUnits(comptime text: []const u8) []const u16 {
    return comptime blk: {
        var units: [text.len]u16 = undefined;
        for (text, 0..) |byte, i| units[i] = byte;
        const frozen = units;
        break :blk &frozen;
    };
}

fn TestSupport(comptime Rt: type) type {
    return struct {
        const Context = Rt.Context(.all);

        fn returnUndefined(ctx: *Context, this: Rt.Value, args: []const Rt.Value) error{ OutOfMemory, Throw }!Rt.Value {
            _ = ctx;
            _ = this;
            _ = args;
            return Rt.undefined_value;
        }

        /// A valueOf behavior that allocates two cells and returns 2.
        fn allocatingValueOf(ctx: *Context, this: Rt.Value, args: []const Rt.Value) error{ OutOfMemory, Throw }!Rt.Value {
            _ = this;
            _ = args;
            _ = try ctx.allocateObject(ctx.intrinsics().object_prototype);
            _ = try ctx.allocateString(testUnits("v"));
            return ctx.allocateNumber(2);
        }

        fn data(v: Rt.Value) Rt.PropertyDescriptor {
            return .{ .value = v, .writable = true, .enumerable = true, .configurable = true };
        }

        fn define(ctx: *Context, object: CellRef, key: CellRef, v: Rt.Value) !void {
            try testing.expect(try ctx.invoke(.ordinary_define_own_property, .{ object, key, data(v) }));
        }

        fn visitInto(list: *std.ArrayList(u32), ref: CellRef) void {
            list.appendAssumeCapacity(@backingInt(ref));
        }

        fn countRoot(count: *usize, v: Rt.Value) void {
            _ = v;
            count.* += 1;
        }

        fn collectRoot(list: *std.ArrayList(Rt.Value), v: Rt.Value) void {
            list.appendAssumeCapacity(v);
        }

        /// Builds the random heap of case 9 and returns the persistent roots that it adds.
        fn buildRandomHeap(heap: *Rt.Heap, store: *dom.Store, document: dom.NodeHandle, seed: u64) !void {
            var prng = std.Random.DefaultPrng.init(seed);
            const random = prng.random();
            var ctx = Rt.rootContext(heap);
            const intrinsics = ctx.intrinsics();
            var cells: std.ArrayList(CellRef) = .empty;
            defer cells.deinit(testing.allocator);
            var keys: std.ArrayList(CellRef) = .empty;
            defer keys.deinit(testing.allocator);
            var objects: std.ArrayList(CellRef) = .empty;
            defer objects.deinit(testing.allocator);
            var functions: std.ArrayList(CellRef) = .empty;
            defer functions.deinit(testing.allocator);

            for (0..200) |i| {
                var units: [4]u16 = undefined;
                for (&units) |*unit| unit.* = random.int(u16);
                const string = try ctx.allocateString(units[0 .. i % 5]);
                try cells.append(testing.allocator, string);
                try keys.append(testing.allocator, string);
            }
            for (0..200) |_| {
                const description: ?CellRef = if (random.boolean()) cells.items[random.uintLessThan(usize, cells.items.len)] else null;
                const symbol = try ctx.allocateSymbol(description);
                try cells.append(testing.allocator, symbol);
                try keys.append(testing.allocator, symbol);
            }
            for (0..200) |_| {
                var limbs: [2]std.math.big.Limb = .{ random.int(std.math.big.Limb), random.int(std.math.big.Limb) };
                const value: std.math.big.int.Const = .{ .limbs = if (limbs[1] == 0) limbs[0..1] else &limbs, .positive = random.boolean() };
                try cells.append(testing.allocator, try ctx.allocateBigInt(value));
            }
            if (Rt.representation == .tagged_index) {
                for (0..200) |i| {
                    const number = try ctx.allocateNumber(@as(f64, @floatFromInt(i)) + 0.5);
                    try cells.append(testing.allocator, Rt.cellOf(number).?);
                }
            }
            for (0..200) |_| {
                const object = try ctx.allocateObject(if (random.boolean()) intrinsics.object_prototype else null);
                try cells.append(testing.allocator, object);
                try objects.append(testing.allocator, object);
            }
            for (0..200) |_| {
                const host_data = Rt.cellValue(cells.items[random.uintLessThan(usize, cells.items.len)]);
                const function = try ctx.allocateFunction(returnUndefined, host_data, null);
                try cells.append(testing.allocator, function);
                try objects.append(testing.allocator, function);
                try functions.append(testing.allocator, function);
            }
            for (0..200) |_| {
                const error_object = try ctx.allocateErrorObject(intrinsics.type_error_prototype);
                try cells.append(testing.allocator, error_object);
                try objects.append(testing.allocator, error_object);
            }
            for (0..200) |i| {
                const node = try store.createElement(document, null, .{ .units = testUnits("p") });
                _ = i;
                const platform = try ctx.allocatePlatformObject(intrinsics.object_prototype, node);
                try cells.append(testing.allocator, platform);
                try objects.append(testing.allocator, platform);
            }
            // Link objects to random cells through data and accessor properties, which can form cycles.
            for (0..2000) |_| {
                const object = objects.items[random.uintLessThan(usize, objects.items.len)];
                const key = keys.items[random.uintLessThan(usize, keys.items.len)];
                const descriptor: Rt.PropertyDescriptor = switch (random.uintLessThan(u8, 3)) {
                    0 => data(Rt.cellValue(cells.items[random.uintLessThan(usize, cells.items.len)])),
                    1 => data(try ctx.allocateNumber(@floatFromInt(random.int(u8)))),
                    else => .{
                        .get = if (random.boolean()) .{ .function = functions.items[random.uintLessThan(usize, functions.items.len)] } else .undefined,
                        .set = if (random.boolean()) .{ .function = functions.items[random.uintLessThan(usize, functions.items.len)] } else .undefined,
                        .enumerable = true,
                        .configurable = true,
                    },
                };
                _ = try ctx.invoke(.ordinary_define_own_property, .{ object, key, descriptor });
            }
            for (0..64) |_| {
                _ = try heap.addPersistent(Rt.cellValue(cells.items[random.uintLessThan(usize, cells.items.len)]));
            }
        }
    };
}

test "FP-0011 case 9: the generated and manual tracers visit and free the same cells" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        const S = TestSupport(Rt);
        var seed: u64 = 1;
        while (seed <= 64) : (seed += 1) {
            var store = try dom.Store.init(testing.allocator);
            defer store.deinit();
            const document = try store.createDocument();
            var generated = try Rt.Heap.init(testing.allocator, .{ .dom = &store, .tracer = .generated });
            defer generated.deinit();
            var manual = try Rt.Heap.init(testing.allocator, .{ .dom = &store, .tracer = .manual });
            defer manual.deinit();
            try S.buildRandomHeap(&generated, &store, document, seed);
            try S.buildRandomHeap(&manual, &store, document, seed);
            try generated.expectInvariants();
            try manual.expectInvariants();

            var kind_counts = std.EnumArray(Rt.Heap.Kind, usize).initFill(0);
            var by_generated: std.ArrayList(u32) = .empty;
            defer by_generated.deinit(testing.allocator);
            var by_manual: std.ArrayList(u32) = .empty;
            defer by_manual.deinit(testing.allocator);
            try testing.expectEqual(generated.slotCount(), manual.slotCount());
            for (0..generated.slotCount()) |index| {
                const ref: CellRef = @fromBackingInt(@as(u32, @intCast(index)));
                if (!generated.isLive(ref)) continue;
                kind_counts.getPtr(generated.kindOf(ref)).* += 1;
                by_generated.clearRetainingCapacity();
                by_manual.clearRetainingCapacity();
                try by_generated.ensureTotalCapacity(testing.allocator, generated.slotCount() * 8);
                try by_manual.ensureTotalCapacity(testing.allocator, generated.slotCount() * 8);
                generated.traceCell(.generated, ref, &by_generated, S.visitInto);
                generated.traceCell(.manual, ref, &by_manual, S.visitInto);
                std.mem.sortUnstable(u32, by_generated.items, {}, std.sort.asc(u32));
                std.mem.sortUnstable(u32, by_manual.items, {}, std.sort.asc(u32));
                try testing.expectEqualSlices(u32, by_generated.items, by_manual.items);
            }
            for (std.enums.values(Rt.Heap.Kind)) |kind| {
                if (kind == .heap_number and r != .tagged_index) continue;
                try testing.expect(kind_counts.get(kind) >= 200);
            }

            generated.collect();
            manual.collect();
            try generated.expectInvariants();
            try manual.expectInvariants();
            var freed: usize = 0;
            for (0..generated.slotCount()) |index| {
                const ref: CellRef = @fromBackingInt(@as(u32, @intCast(index)));
                try testing.expectEqual(generated.isLive(ref), manual.isLive(ref));
                if (!generated.isLive(ref)) freed += 1;
            }
            try testing.expect(freed > 0);
        }
    }
}

test "FP-0011 case 10: a collection frees unreachable cells and keeps every root" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        const S = TestSupport(Rt);
        var heap = try Rt.Heap.init(testing.allocator, .{});
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        const intrinsics = ctx.intrinsics();
        const key = intrinsics.name_string;

        const unrooted = try ctx.allocateString(testUnits("gone"));
        const first = try ctx.allocateObject(intrinsics.object_prototype);
        const second = try ctx.allocateObject(intrinsics.object_prototype);
        try S.define(&ctx, first, key, Rt.cellValue(second));
        try S.define(&ctx, second, key, Rt.cellValue(first));

        var scope = try ctx.openScope();
        defer scope.close();
        const scoped = try ctx.allocateObject(null);
        _ = try scope.push(Rt.cellValue(scoped));
        const persistent_cell = try ctx.allocateObject(null);
        const persistent = try heap.addPersistent(Rt.cellValue(persistent_cell));
        defer heap.removePersistent(persistent);
        const thrown = try ctx.allocateObject(null);
        try testing.expectEqual(error.Throw, ctx.throwValue(Rt.cellValue(thrown)));

        const held = try ctx.allocateObject(intrinsics.object_prototype);
        _ = try scope.push(Rt.cellValue(held));
        try S.define(&ctx, held, intrinsics.message_string, try ctx.allocateNumber(0.5));
        const half = ctx.ownProperty(held, intrinsics.message_string).?.value.?;

        heap.collect();
        try heap.expectInvariants();
        try testing.expect(!heap.isLive(unrooted));
        try testing.expect(!heap.isLive(first));
        try testing.expect(!heap.isLive(second));
        try testing.expect(heap.isLive(scoped));
        try testing.expect(heap.isLive(persistent_cell));
        try testing.expect(heap.isLive(thrown));
        try testing.expect(heap.isLive(intrinsics.object_prototype));
        try testing.expect(heap.isLive(intrinsics.symbol_to_primitive));
        try testing.expect(heap.isLive(intrinsics.type_error_string));
        try testing.expectEqual(0.5, heap.numberOf(half));
        if (r == .tagged_index) {
            const cell = Rt.cellOf(half).?;
            try testing.expect(heap.isLive(cell));
            try testing.expectEqual(Rt.Heap.Kind.heap_number, heap.kindOf(cell));
        }

        var count: usize = 0;
        heap.forEachRoot(&count, S.countRoot);
        try testing.expectEqual(Rt.Heap.intrinsic_root_count + 2 + 1 + 1, count);
        var roots: std.ArrayList(Rt.Value) = .empty;
        defer roots.deinit(testing.allocator);
        try roots.ensureTotalCapacity(testing.allocator, count);
        heap.forEachRoot(&roots, S.collectRoot);
        const expected = [_]Rt.Value{ Rt.cellValue(scoped), Rt.cellValue(held), Rt.cellValue(persistent_cell), Rt.cellValue(thrown) };
        for (expected) |root| {
            var seen: usize = 0;
            for (roots.items) |item| {
                if (Rt.V.identical(item, root)) seen += 1;
            }
            try testing.expectEqual(1, seen);
        }
        try testing.expect(Rt.V.identical(Rt.cellValue(thrown), heap.takeException().?));
    }
}

test "FP-0011 case 12: a quarantined cell resolves intact and counts one dead resolution" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var heap = try Rt.Heap.init(testing.allocator, .{ .quarantine_freed_cells = true });
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        const object = try ctx.allocateObject(ctx.intrinsics().object_prototype);
        heap.collect();
        try heap.expectInvariants();
        try testing.expectEqual(0, heap.stats.dead_resolutions);
        try testing.expect(!heap.isLive(object));
        try testing.expectEqual(Rt.Heap.Kind.ordinary_object, heap.resolve(object).kind());
        try testing.expectEqual(1, heap.stats.dead_resolutions);
    }
}

test "FP-0011 case 13: a platform object keeps its DOM tree until the heap collects it" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var store = try dom.Store.init(testing.allocator);
        defer store.deinit();
        const document = try store.createDocument();
        const element = try store.createElement(document, null, .{ .units = testUnits("div") });
        const text = try store.createText(document, .{ .units = testUnits("t") });
        try store.appendChild(element, text);

        var heap = try Rt.Heap.init(testing.allocator, .{ .dom = &store });
        defer heap.deinit();
        var ctx = Rt.rootContext(&heap);
        const platform = try ctx.allocatePlatformObject(ctx.intrinsics().object_prototype, element);
        try heap.expectInvariants();
        const root = try heap.addPersistent(Rt.cellValue(platform));
        try testing.expectEqual(0, store.sweep());
        heap.collect();
        try heap.expectInvariants();
        try testing.expectEqual(0, store.sweep());
        try testing.expectEqual(dom.Kind.element, try store.nodeKind(element));
        try testing.expectEqual(dom.Kind.text, try store.nodeKind(text));

        heap.removePersistent(root);
        heap.collect();
        try heap.expectInvariants();
        try testing.expectEqual(2, store.sweep());
        try testing.expectError(error.StaleHandle, store.release(element));
        try testing.expectEqual(dom.Kind.document, try store.nodeKind(document));
    }
}

fn allocationFailureBody(comptime Rt: type, heap: *Rt.Heap, element: dom.NodeHandle) !void {
    const S = TestSupport(Rt);
    var ctx = Rt.rootContext(heap);
    const intrinsics = ctx.intrinsics();
    var scope = try ctx.openScope();
    defer scope.close();

    const object = try ctx.allocateObject(intrinsics.object_prototype);
    _ = try scope.push(Rt.cellValue(object));
    const key = try ctx.allocateString(testUnits("key"));
    _ = try scope.push(Rt.cellValue(key));
    try S.define(&ctx, object, key, try ctx.allocateNumber(1.5));
    try heap.expectInvariants();

    const text = try ctx.invoke(.number_to_string, .{0.25});
    _ = try scope.push(Rt.cellValue(text));
    try heap.expectInvariants();
    const joined = try ctx.invoke(.string_concat, .{ text, key });
    _ = try scope.push(Rt.cellValue(joined));
    try heap.expectInvariants();

    var limbs: [1]std.math.big.Limb = .{std.math.maxInt(std.math.big.Limb)};
    const big = try ctx.allocateBigInt(.{ .limbs = &limbs, .positive = true });
    _ = try scope.push(Rt.cellValue(big));
    const sum = try ctx.invoke(.bigint_add, .{ big, big });
    _ = try scope.push(Rt.cellValue(sum));
    try heap.expectInvariants();

    const value_of = try ctx.allocateFunction(S.allocatingValueOf, Rt.undefined_value, null);
    _ = try scope.push(Rt.cellValue(value_of));
    const left = try ctx.allocateObject(intrinsics.object_prototype);
    _ = try scope.push(Rt.cellValue(left));
    try S.define(&ctx, left, intrinsics.value_of_string, Rt.cellValue(value_of));
    const added = ctx.invoke(.addition, .{ Rt.cellValue(left), Rt.cellValue(left) }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Throw => return error.TestUnexpectedThrow,
    };
    try heap.expectInvariants();
    try testing.expectEqual(4, heap.numberOf(added));

    const platform = try ctx.allocatePlatformObject(intrinsics.object_prototype, element);
    _ = try scope.push(Rt.cellValue(platform));
    try heap.expectInvariants();
    ctx.collect();
    try heap.expectInvariants();
}

fn AllocationFailure(comptime Rt: type) type {
    return struct {
        /// The element lives in the document, so a sweep keeps it once the heap releases it.
        fn run(gpa: std.mem.Allocator) !void {
            var store = try dom.Store.init(gpa);
            defer store.deinit();
            const document = try store.createDocument();
            const element = try store.createElement(document, null, .{ .units = testUnits("p") });
            try store.appendChild(document, element);
            const nodes = store.nodeCount();
            var heap = try Rt.Heap.init(gpa, .{ .dom = &store });
            const outcome = allocationFailureBody(Rt, &heap, element);
            const verified = heap.expectInvariants();
            heap.deinit();
            try testing.expectError(error.NotRetained, store.release(element));
            try testing.expectEqual(0, store.sweep());
            try testing.expectEqual(nodes, store.nodeCount());
            try verified;
            return outcome;
        }
    };
}

test "FP-0011 case 14: every induced allocation failure returns OutOfMemory and leaks nothing" {
    inline for (test_representations) |r| {
        try testing.checkAllAllocationFailures(testing.allocator, AllocationFailure(runtime.Runtime(r)).run, .{});
    }
}

test "FP-0011 case 15: the cell limit collects first and then returns OutOfMemory" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var heap = try Rt.Heap.init(testing.allocator, .{ .max_cells = Rt.Heap.intrinsic_cell_count + 8 });
        defer heap.deinit();
        try testing.expectEqual(Rt.Heap.intrinsic_cell_count, heap.liveCount());
        var ctx = Rt.rootContext(&heap);
        {
            var scope = try ctx.openScope();
            defer scope.close();
            for (0..8) |_| _ = try scope.push(Rt.cellValue(try ctx.allocateObject(null)));
            const collections = heap.stats.collections;
            try testing.expectError(error.OutOfMemory, ctx.allocateObject(null));
            try testing.expectEqual(collections + 1, heap.stats.collections);
            try heap.expectInvariants();
        }
        _ = try ctx.allocateObject(null);
        try heap.expectInvariants();
        try testing.expectEqual(Rt.Heap.intrinsic_cell_count + 1, heap.liveCount());

        var capped = try Rt.Heap.init(testing.allocator, .{ .max_cells = std.math.maxInt(usize) });
        defer capped.deinit();
        try testing.expectEqual(@as(usize, Rt.V.max_cell_index) + 1, capped.options.max_cells);
    }
    try testing.expectEqual(4294967295, runtime.Runtime(.reference).V.max_cell_index);
    try testing.expectEqual(4294967295, runtime.Runtime(.nan_box).V.max_cell_index);
    try testing.expectEqual(1073741823, runtime.Runtime(.tagged_index).V.max_cell_index);
}

test "FP-0011 case 16: deinit frees every cell and releases every retain" {
    inline for (test_representations) |r| {
        const Rt = runtime.Runtime(r);
        var store = try dom.Store.init(testing.allocator);
        defer store.deinit();
        const document = try store.createDocument();
        var nodes: [3]dom.NodeHandle = undefined;
        for (&nodes) |*node| node.* = try store.createElement(document, null, .{ .units = testUnits("span") });

        var heap = try Rt.Heap.init(testing.allocator, .{ .dom = &store, .quarantine_freed_cells = true });
        var ctx = Rt.rootContext(&heap);
        const proto = ctx.intrinsics().object_prototype;
        var scope = try ctx.openScope();
        _ = try scope.push(Rt.cellValue(try ctx.allocatePlatformObject(proto, nodes[0])));
        _ = try scope.push(Rt.cellValue(try ctx.allocateString(testUnits("scoped"))));
        _ = try heap.addPersistent(Rt.cellValue(try ctx.allocatePlatformObject(proto, nodes[1])));
        _ = try heap.addPersistent(try ctx.allocateNumber(-0.0));
        _ = try ctx.allocatePlatformObject(proto, nodes[2]);
        _ = try ctx.allocateObject(proto);
        heap.collect();
        try heap.expectInvariants();
        _ = try ctx.allocateString(testUnits("unrooted"));
        _ = try ctx.allocateObject(proto);
        try heap.expectInvariants();
        heap.deinit();
        for (nodes) |node| try testing.expectError(error.NotRetained, store.release(node));
    }
}
