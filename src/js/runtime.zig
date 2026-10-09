//! The JavaScript runtime, instantiated once per value representation.
//!
//! `Runtime(r).Context(effects)` is the only way for a kernel to reach the heap.
//! Each heap primitive requires an effect set, and each kernel's first parameter is a context with
//! exactly its operation's effects. `invoke` narrows a context to an operation's effects, so a
//! context can invoke only operations whose effects it holds.
//!
//! Rooting protocol: a caller keeps every `Value` and `CellRef` argument rooted for the duration of
//! the call, a kernel returns its result unrooted, and a kernel roots each intermediate that it holds
//! across an invocation with the `allocation` effect.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const dom = @import("../dom.zig");
const heap_module = @import("heap.zig");
const number = @import("number.zig");
const number_vectors = @import("number_vectors.zig");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const Limb = std.math.big.Limb;

pub const operations = @import("operations.zig");
pub const value = @import("value.zig");
pub const heap_catalog = @import("heap_catalog.zig");
pub const Representation = value.Representation;
pub const CellRef = value.CellRef;
pub const Class = value.Class;
pub const Effects = operations.Effects;
pub const OperationId = operations.OperationId;
pub const Tracer = heap_module.Tracer;

/// The ECMAScript language types.
pub const LanguageType = enum { undefined, null, boolean, string, symbol, number, bigint, object };

pub const PreferredType = enum { string, number };

/// The messages of engine-thrown TypeErrors.
const Message = struct {
    const primitive_object = "Symbol.toPrimitive method returned an object";
    const not_callable_method = "method is not callable";
    const no_primitive = "cannot convert object to primitive value";
    const symbol_to_string = "cannot convert a Symbol value to a string";
    const symbol_to_number = "cannot convert a Symbol value to a number";
    const bigint_to_number = "cannot convert a BigInt value to a number";
    const mixed_addition = "cannot mix BigInt and other types in addition";
    const not_function = "value is not a function";
};

/// One entry of a bound kernel table.
pub const BoundKernel = struct {
    id: OperationId,
    name: []const u8,
    kernel: *const anyopaque,
};

const leaf: Effects = .none;
const allocating: Effects = .{ .allocation = true };
const throwing: Effects = .{ .allocation = true, .exception = true };
const raising: Effects = .{ .exception = true };
const mutating: Effects = .{ .heap_mutation = true };
const defining: Effects = .{ .allocation = true, .heap_mutation = true };

pub fn Runtime(comptime r: Representation) type {
    return struct {
        const Rt = @This();

        pub const representation = r;
        pub const V = value.Encoding(r);
        pub const Value = V.Value;
        pub const Heap = heap_module.Heap(Rt);

        /// A built-in function's behavior. Only a context with every effect can form its first argument.
        pub const Behavior = *const fn (*Context(.all), this: Value, args: []const Value) error{ OutOfMemory, Throw }!Value;

        pub const Numeric = union(enum) { number: f64, bigint: CellRef };
        pub const Accessor = union(enum) { undefined, function: CellRef };

        /// A Property Descriptor; an absent field is null.
        pub const PropertyDescriptor = struct {
            value: ?Value = null,
            writable: ?bool = null,
            get: ?Accessor = null,
            set: ?Accessor = null,
            enumerable: ?bool = null,
            configurable: ?bool = null,

            fn isAccessor(descriptor: PropertyDescriptor) bool {
                return descriptor.get != null or descriptor.set != null;
            }

            fn isData(descriptor: PropertyDescriptor) bool {
                return descriptor.value != null or descriptor.writable != null;
            }

            fn isEmpty(descriptor: PropertyDescriptor) bool {
                return !descriptor.isAccessor() and !descriptor.isData() and
                    descriptor.enumerable == null and descriptor.configurable == null;
            }
        };

        pub const undefined_value = V.undefined_value;
        pub const null_value = V.null_value;

        pub fn boolean(b: bool) Value {
            return V.fromBoolean(b);
        }

        pub fn cellValue(ref: CellRef) Value {
            return V.fromCell(@backingInt(ref));
        }

        pub fn cellOf(v: Value) ?CellRef {
            return if (V.classify(v) == .cell) @fromBackingInt(V.asCell(v)) else null;
        }

        fn accessorOf(ref: ?CellRef) Accessor {
            return if (ref) |function| .{ .function = function } else .undefined;
        }

        fn accessorCell(accessor: ?Accessor) ?CellRef {
            return switch (accessor orelse return null) {
                .undefined => null,
                .function => |function| function,
            };
        }

        pub fn OperandType(comptime t: operations.Type) type {
            return switch (t) {
                .number => f64,
                .boolean => bool,
                .value, .primitive => Value,
                .object, .string, .bigint, .property_key => CellRef,
                .string_units => web_string.View,
                .numeric => Numeric,
                .method, .optional_object => ?CellRef,
                .property_descriptor => PropertyDescriptor,
                .optional_property_descriptor => ?PropertyDescriptor,
                .preferred_type => PreferredType,
                .optional_preferred_type => ?PreferredType,
                .arguments => []const Value,
            };
        }

        /// The result type of an operation, without its error set.
        pub fn Result(comptime id: OperationId) type {
            return OperandType(operations.entry(id).result);
        }

        /// The return type of a kernel with `effects`.
        pub fn KernelReturn(comptime effects: Effects, comptime T: type) type {
            if (effects.exception) return error{ OutOfMemory, Throw }!T;
            if (effects.allocation) return error{OutOfMemory}!T;
            return T;
        }

        /// Returns a context with every effect, for the host that owns `heap`.
        pub fn rootContext(heap: *Heap) Context(.all) {
            return .{ .heap = heap };
        }

        pub fn Context(comptime effects: Effects) type {
            return struct {
                const Self = @This();
                pub const context_effects = effects;

                heap: *Heap,

                fn require(comptime method: []const u8, comptime needed: Effects) void {
                    if (!operations.permits(effects, needed)) {
                        @compileError("fairpane-js: " ++ method ++ " requires effects " ++ operations.effectsName(needed) ++
                            "; the context has effects " ++ operations.effectsName(effects));
                    }
                }

                /// Narrows the context to the operation's effects and calls its kernel.
                pub fn invoke(self: *Self, comptime id: OperationId, args: anytype) KernelReturn(operations.entry(id).effects, Result(id)) {
                    const operation = comptime operations.entry(id);
                    comptime {
                        _ = kernel_table;
                        if (!operations.permits(effects, operation.effects)) {
                            @compileError("fairpane-js: a context with effects " ++ operations.effectsName(effects) ++ " cannot invoke " ++
                                operation.name ++ ", which has effects " ++ operations.effectsName(operation.effects));
                        }
                    }
                    const heap = self.heap;
                    if (heap.invoke_depth == 0) heap.invoke_boundary = heap.next_serial;
                    heap.invoke_depth += 1;
                    defer heap.invoke_depth -= 1;
                    const before = if (builtin.is_test) heap.stats else {};
                    defer if (builtin.is_test) heap.checkEffects(id, before);
                    var narrowed: Context(operation.effects) = .{ .heap = heap };
                    return @call(.auto, @field(Kernels, @tagName(id)), .{&narrowed} ++ args);
                }

                /// Returns a context with a subset of the effects.
                pub fn narrow(self: *const Self, comptime narrower: Effects) Context(narrower) {
                    if (comptime !operations.permits(effects, narrower)) {
                        @compileError("fairpane-js: a context with effects " ++ operations.effectsName(effects) ++
                            " cannot narrow to effects " ++ operations.effectsName(narrower));
                    }
                    return .{ .heap = self.heap };
                }

                // Reading requires no effect.

                pub fn intrinsics(self: *const Self) Heap.Intrinsics {
                    return self.heap.intrinsics;
                }

                pub fn kindOf(self: *const Self, ref: CellRef) Heap.Kind {
                    return self.heap.kindOf(ref);
                }

                pub fn typeOf(self: *const Self, v: Value) LanguageType {
                    return switch (V.classify(v)) {
                        .undefined => .undefined,
                        .null => .null,
                        .boolean => .boolean,
                        .number => .number,
                        .cell => switch (self.heap.kindOf(@fromBackingInt(V.asCell(v)))) {
                            .string => .string,
                            .symbol => .symbol,
                            .bigint => .bigint,
                            .heap_number => .number,
                            .ordinary_object, .builtin_function, .error_object, .platform_object => .object,
                        },
                    };
                }

                pub fn numberOf(self: *const Self, v: Value) f64 {
                    return self.heap.numberOf(v);
                }

                pub fn stringUnits(self: *const Self, string: CellRef) []const u16 {
                    return self.heap.stringUnits(string);
                }

                pub fn bigIntOf(self: *const Self, big: CellRef) std.math.big.int.Const {
                    return self.heap.bigIntOf(big);
                }

                pub fn isCallable(self: *const Self, v: Value) bool {
                    const ref = cellOf(v) orelse return false;
                    return heap_catalog.info(self.heap.kindOf(ref)).callable;
                }

                pub fn prototypeOf(self: *const Self, object: CellRef) ?CellRef {
                    return self.heap.header(object).prototype;
                }

                pub fn isExtensible(self: *const Self, object: CellRef) bool {
                    return self.heap.header(object).extensible;
                }

                pub fn findOwnProperty(self: *const Self, object: CellRef, key: CellRef) ?usize {
                    return self.heap.findProperty(object, key);
                }

                pub fn propertyAt(self: *const Self, object: CellRef, index: usize) Heap.Property {
                    return self.heap.header(object).properties.items[index];
                }

                pub fn ownPropertyCount(self: *const Self, object: CellRef) usize {
                    return self.heap.header(object).properties.items.len;
                }

                /// Returns the fully populated descriptor of an own property.
                pub fn ownProperty(self: *const Self, object: CellRef, key: CellRef) ?PropertyDescriptor {
                    const index = self.findOwnProperty(object, key) orelse return null;
                    const property = self.propertyAt(object, index);
                    return switch (property.slot) {
                        .data => |data| .{
                            .value = data.value,
                            .writable = data.writable,
                            .enumerable = property.enumerable,
                            .configurable = property.configurable,
                        },
                        .accessor => |accessor| .{
                            .get = accessorOf(accessor.getter),
                            .set = accessorOf(accessor.setter),
                            .enumerable = property.enumerable,
                            .configurable = property.configurable,
                        },
                    };
                }

                /// Returns the built-in function whose behavior runs.
                pub fn activeFunction(self: *const Self) CellRef {
                    return self.heap.active_function orelse std.debug.panic("fairpane-js: no built-in function is running", .{});
                }

                pub fn hostData(self: *const Self) Value {
                    return self.heap.resolve(self.activeFunction()).payload.builtin_function.host_data;
                }

                pub fn hostContext(self: *const Self) ?*anyopaque {
                    return self.hostContextOf(self.activeFunction());
                }

                pub fn hostContextOf(self: *const Self, function: CellRef) ?*anyopaque {
                    return self.heap.resolve(function).payload.builtin_function.host_context;
                }

                // Allocation.

                /// Returns the heap's allocator for buffers that a kernel frees before it returns.
                pub fn allocator(self: *const Self) Allocator {
                    comptime require("allocator", allocating);
                    return self.heap.gpa;
                }

                pub fn allocateString(self: *const Self, units: []const u16) error{OutOfMemory}!CellRef {
                    comptime require("allocateString", allocating);
                    return self.heap.allocateString(units);
                }

                pub fn allocateAsciiString(self: *const Self, bytes: []const u8) error{OutOfMemory}!CellRef {
                    comptime require("allocateAsciiString", allocating);
                    return self.heap.allocateAsciiString(bytes);
                }

                pub fn allocateConcatenation(self: *const Self, a: CellRef, b: CellRef) error{OutOfMemory}!CellRef {
                    comptime require("allocateConcatenation", allocating);
                    return self.heap.allocateConcatenation(a, b);
                }

                pub fn allocateObject(self: *const Self, prototype: ?CellRef) error{OutOfMemory}!CellRef {
                    comptime require("allocateObject", allocating);
                    return self.heap.allocateObject(prototype);
                }

                pub fn allocateErrorObject(self: *const Self, prototype: ?CellRef) error{OutOfMemory}!CellRef {
                    comptime require("allocateErrorObject", allocating);
                    return self.heap.allocateErrorObject(prototype);
                }

                pub fn allocateSymbol(self: *const Self, description: ?CellRef) error{OutOfMemory}!CellRef {
                    comptime require("allocateSymbol", allocating);
                    return self.heap.allocateSymbol(description);
                }

                pub fn allocateBigInt(self: *const Self, big: std.math.big.int.Const) error{OutOfMemory}!CellRef {
                    comptime require("allocateBigInt", allocating);
                    return self.heap.allocateBigInt(big);
                }

                pub fn allocateNumber(self: *const Self, x: f64) error{OutOfMemory}!Value {
                    comptime require("allocateNumber", allocating);
                    return self.heap.numberValue(x);
                }

                pub fn allocateFunction(self: *const Self, behavior: Behavior, host_data: Value, host_context: ?*anyopaque) error{OutOfMemory}!CellRef {
                    comptime require("allocateFunction", allocating);
                    return self.heap.allocateFunction(behavior, host_data, host_context);
                }

                pub fn allocatePlatformObject(self: *const Self, prototype: ?CellRef, node: dom.NodeHandle) Heap.PlatformObjectError!CellRef {
                    comptime require("allocatePlatformObject", allocating);
                    return self.heap.allocatePlatformObject(prototype, node);
                }

                pub fn openScope(self: *const Self) error{OutOfMemory}!Heap.Scope {
                    comptime require("openScope", allocating);
                    return self.heap.openScope();
                }

                pub fn collect(self: *const Self) void {
                    comptime require("collect", allocating);
                    self.heap.collect();
                }

                // Exceptions.

                pub fn throwTypeError(self: *const Self, message: []const u8) error{ OutOfMemory, Throw } {
                    comptime require("throwTypeError", throwing);
                    return self.heap.throwTypeError(message);
                }

                pub fn throwValue(self: *const Self, thrown: Value) error{Throw} {
                    comptime require("throwValue", raising);
                    return self.heap.throwValue(thrown);
                }

                // Mutation of existing cells.

                pub fn preventExtensions(self: *const Self, object: CellRef) void {
                    comptime require("preventExtensions", mutating);
                    self.heap.preventExtensions(object);
                }

                pub fn appendProperty(self: *const Self, object: CellRef, property: Heap.Property) error{OutOfMemory}!void {
                    comptime require("appendProperty", defining);
                    return self.heap.appendProperty(object, property);
                }

                pub fn writeProperty(self: *const Self, object: CellRef, index: usize, property: Heap.Property) void {
                    comptime require("writeProperty", defining);
                    self.heap.writeProperty(object, index, property);
                }

                // User code.

                /// Runs a built-in function's behavior. The caller keeps `function`, `this`, and `args` rooted.
                pub fn callBehavior(self: *Self, function: CellRef, this: Value, args: []const Value) error{ OutOfMemory, Throw }!Value {
                    comptime require("callBehavior", .all);
                    const heap = self.heap;
                    const behavior = heap.resolve(function).payload.builtin_function.behavior;
                    heap.stats.behaviors_invoked += 1;
                    const caller = heap.active_function;
                    heap.active_function = function;
                    defer heap.active_function = caller;
                    return behavior(self, this, args);
                }
            };
        }

        /// Checks at compile time that `Kernels` declares exactly one kernel per entry, with a context
        /// of the entry's effects, the entry's operand types, and the return type that its effects imply.
        pub fn bindKernels(comptime entries: []const operations.Operation, comptime Kernels_: type) [entries.len]BoundKernel {
            comptime {
                @setEvalBranchQuota(20_000);
                for (@typeInfo(Kernels_).@"struct".decl_names) |declared| {
                    for (entries) |operation| {
                        if (std.mem.eql(u8, @tagName(operation.id), declared)) break;
                    } else @compileError("fairpane-js: kernel " ++ declared ++ " belongs to no operation");
                }
                var table: [entries.len]BoundKernel = undefined;
                for (entries, &table) |operation, *bound| {
                    const prefix = "fairpane-js: kernel for " ++ operation.name;
                    if (!@hasDecl(Kernels_, @tagName(operation.id))) {
                        @compileError("fairpane-js: operation " ++ operation.name ++ " has no kernel");
                    }
                    const kernel = @field(Kernels_, @tagName(operation.id));
                    const info = @typeInfo(@TypeOf(kernel)).@"fn";
                    const First = if (info.param_types.len == 0) void else info.param_types[0].?;
                    if (First != *Context(operation.effects)) {
                        const Pointee = switch (@typeInfo(First)) {
                            .pointer => |pointer| pointer.child,
                            else => @compileError(prefix ++ " takes no context first"),
                        };
                        if (!@hasDecl(Pointee, "context_effects")) @compileError(prefix ++ " takes no context first");
                        @compileError(prefix ++ " takes a context with effects " ++ operations.effectsName(Pointee.context_effects) ++
                            ", but the operation has effects " ++ operations.effectsName(operation.effects));
                    }
                    if (info.param_types.len != operation.operands.len + 1) {
                        @compileError(std.fmt.comptimePrint("{s} takes {d} operands, but the operation has {d}", .{ prefix, info.param_types.len - 1, operation.operands.len }));
                    }
                    for (operation.operands, info.param_types[1..]) |operand, Parameter| {
                        if (Parameter.? != OperandType(operand.type)) {
                            @compileError(prefix ++ " takes operand " ++ operand.name ++ " as " ++ @typeName(Parameter.?) ++
                                ", but the operation requires " ++ @typeName(OperandType(operand.type)));
                        }
                    }
                    const Returned = info.return_type.?;
                    const Expected = KernelReturn(operation.effects, OperandType(operation.result));
                    if (Returned != Expected) {
                        if (!operation.effects.exception and returnsThrow(Returned)) {
                            @compileError(prefix ++ " returns error.Throw, but the operation does not have the exception effect");
                        }
                        @compileError(prefix ++ " returns " ++ @typeName(Returned) ++ ", but the operation requires " ++ @typeName(Expected));
                    }
                    bound.* = .{ .id = operation.id, .name = operation.name, .kernel = @ptrCast(&kernel) };
                }
                const frozen = table;
                return frozen;
            }
        }

        fn returnsThrow(comptime Returned: type) bool {
            const set = switch (@typeInfo(Returned)) {
                .error_union => |error_union| error_union.error_set,
                else => return false,
            };
            const names = @typeInfo(set).error_set.error_names orelse return true;
            for (names) |name| {
                if (std.mem.eql(u8, name, "Throw")) return true;
            }
            return false;
        }

        /// The bound kernel table, one entry per catalog entry in catalog order.
        pub const kernel_table = bindKernels(operations.catalog, Kernels);

        const Kernels = struct {
            pub fn number_add(_: *Context(leaf), x: f64, y: f64) f64 {
                return number.add(x, y);
            }

            pub fn number_same_value(_: *Context(leaf), x: f64, y: f64) bool {
                return number.sameValue(x, y);
            }

            pub fn same_value(ctx: *Context(leaf), x: Value, y: Value) bool {
                const kind = ctx.typeOf(x);
                if (kind != ctx.typeOf(y)) return false;
                return switch (kind) {
                    .number => number.sameValue(ctx.numberOf(x), ctx.numberOf(y)),
                    .undefined, .null => true,
                    .boolean => V.asBoolean(x) == V.asBoolean(y),
                    .string => std.mem.eql(u16, ctx.stringUnits(cellOf(x).?), ctx.stringUnits(cellOf(y).?)),
                    .bigint => ctx.bigIntOf(cellOf(x).?).eql(ctx.bigIntOf(cellOf(y).?)),
                    .symbol, .object => cellOf(x).? == cellOf(y).?,
                };
            }

            pub fn is_callable(ctx: *Context(leaf), arg: Value) bool {
                return ctx.isCallable(arg);
            }

            pub fn string_to_number(_: *Context(leaf), string: web_string.View) f64 {
                return number.stringToNumber(string.units);
            }

            pub fn ordinary_get_own_property(ctx: *Context(leaf), obj: CellRef, key: CellRef) ?PropertyDescriptor {
                return ctx.ownProperty(obj, key);
            }

            pub fn ordinary_get_prototype_of(ctx: *Context(leaf), obj: CellRef) ?CellRef {
                return ctx.prototypeOf(obj);
            }

            pub fn ordinary_prevent_extensions(ctx: *Context(mutating), obj: CellRef) bool {
                ctx.preventExtensions(obj);
                return true;
            }

            /// Allocates a new string for every input.
            pub fn number_to_string(ctx: *Context(allocating), x: f64) error{OutOfMemory}!CellRef {
                var buffer: [number.max_string_units]u16 = undefined;
                return ctx.allocateString(number.toString(x, &buffer));
            }

            pub fn bigint_add(ctx: *Context(allocating), x: CellRef, y: CellRef) error{OutOfMemory}!CellRef {
                const left = ctx.bigIntOf(x);
                const right = ctx.bigIntOf(y);
                const gpa = ctx.allocator();
                const limbs = try gpa.alloc(Limb, @max(left.limbs.len, right.limbs.len) + 1);
                defer gpa.free(limbs);
                var sum: std.math.big.int.Mutable = .{ .limbs = limbs, .len = 1, .positive = true };
                sum.add(left, right);
                return ctx.allocateBigInt(sum.toConst());
            }

            pub fn bigint_to_string(ctx: *Context(allocating), x: CellRef) error{OutOfMemory}!CellRef {
                const gpa = ctx.allocator();
                const text = try ctx.bigIntOf(x).toStringAlloc(gpa, 10, .lower);
                defer gpa.free(text);
                return ctx.allocateAsciiString(text);
            }

            pub fn string_concat(ctx: *Context(allocating), a: CellRef, b: CellRef) error{OutOfMemory}!CellRef {
                return ctx.allocateConcatenation(a, b);
            }

            /// `OrdinaryDefineOwnProperty`, with `ValidateAndApplyPropertyDescriptor` for an ordinary object.
            pub fn ordinary_define_own_property(ctx: *Context(defining), obj: CellRef, key: CellRef, desc: PropertyDescriptor) error{OutOfMemory}!bool {
                const reader = ctx.narrow(leaf);
                const index = ctx.findOwnProperty(obj, key) orelse {
                    // Step 2: current is undefined.
                    if (!ctx.isExtensible(obj)) return false;
                    const slot: Heap.catalog.Slot = if (desc.isAccessor())
                        .{ .accessor = .{ .getter = accessorCell(desc.get), .setter = accessorCell(desc.set) } }
                    else
                        .{ .data = .{ .value = desc.value orelse undefined_value, .writable = desc.writable orelse false } };
                    try ctx.appendProperty(obj, .{
                        .key = key,
                        .enumerable = desc.enumerable orelse false,
                        .configurable = desc.configurable orelse false,
                        .slot = slot,
                    });
                    return true;
                };
                const current = ctx.propertyAt(obj, index);
                // Step 4: a descriptor with no fields changes nothing.
                if (desc.isEmpty()) return true;
                // Step 5: a non-configurable property accepts only compatible changes.
                if (!current.configurable) {
                    if (desc.configurable == true) return false;
                    if (desc.enumerable) |enumerable| {
                        if (enumerable != current.enumerable) return false;
                    }
                    const generic = !desc.isAccessor() and !desc.isData();
                    if (!generic and desc.isAccessor() != (current.slot == .accessor)) return false;
                    switch (current.slot) {
                        .accessor => |accessor| {
                            if (desc.get != null and accessorCell(desc.get) != accessor.getter) return false;
                            if (desc.set != null and accessorCell(desc.set) != accessor.setter) return false;
                        },
                        .data => |data| if (!data.writable) {
                            if (desc.writable == true) return false;
                            if (desc.value) |new_value| {
                                var same = reader;
                                if (!same.invoke(.same_value, .{ new_value, data.value })) return false;
                            }
                        },
                    }
                }
                // Step 6: apply the descriptor.
                var next = current;
                if (current.slot == .data and desc.isAccessor()) {
                    next.slot = .{ .accessor = .{ .getter = accessorCell(desc.get), .setter = accessorCell(desc.set) } };
                } else if (current.slot == .accessor and desc.isData()) {
                    next.slot = .{ .data = .{ .value = desc.value orelse undefined_value, .writable = desc.writable orelse false } };
                } else switch (next.slot) {
                    .data => |*data| {
                        if (desc.value) |new_value| data.value = new_value;
                        if (desc.writable) |writable| data.writable = writable;
                    },
                    .accessor => |*accessor| {
                        if (desc.get != null) accessor.getter = accessorCell(desc.get);
                        if (desc.set != null) accessor.setter = accessorCell(desc.set);
                    },
                }
                if (desc.enumerable) |enumerable| next.enumerable = enumerable;
                if (desc.configurable) |configurable| next.configurable = configurable;
                ctx.writeProperty(obj, index, next);
                return true;
            }

            pub fn call(ctx: *Context(.all), func: Value, this: Value, args: []const Value) error{ OutOfMemory, Throw }!Value {
                if (!ctx.isCallable(func)) return ctx.throwTypeError(Message.not_function);
                return ctx.callBehavior(cellOf(func).?, this, args);
            }

            /// `GetMethod` of an Object, as `ToPrimitive` calls it.
            pub fn get_method(ctx: *Context(.all), obj: CellRef, key: CellRef) error{ OutOfMemory, Throw }!?CellRef {
                const func = try ctx.invoke(.ordinary_get, .{ obj, key, cellValue(obj) });
                switch (ctx.typeOf(func)) {
                    .undefined, .null => return null,
                    else => {},
                }
                if (!ctx.isCallable(func)) return ctx.throwTypeError(Message.not_callable_method);
                return cellOf(func).?;
            }

            pub fn ordinary_get(ctx: *Context(.all), obj: CellRef, key: CellRef, receiver: Value) error{ OutOfMemory, Throw }!Value {
                var holder = obj;
                while (true) {
                    if (ctx.findOwnProperty(holder, key)) |index| {
                        switch (ctx.propertyAt(holder, index).slot) {
                            .data => |data| return data.value,
                            .accessor => |accessor| {
                                const getter = accessor.getter orelse return undefined_value;
                                // A getter can redefine the accessor, so root it for the call.
                                var scope = try ctx.openScope();
                                defer scope.close();
                                _ = try scope.push(cellValue(getter));
                                return ctx.invoke(.call, .{ cellValue(getter), receiver, @as([]const Value, &.{}) });
                            },
                        }
                    }
                    holder = ctx.prototypeOf(holder) orelse return undefined_value;
                }
            }

            pub fn ordinary_to_primitive(ctx: *Context(.all), obj: CellRef, hint: PreferredType) error{ OutOfMemory, Throw }!Value {
                const names = ctx.intrinsics();
                const order = switch (hint) {
                    .string => [_]CellRef{ names.to_string_string, names.value_of_string },
                    .number => [_]CellRef{ names.value_of_string, names.to_string_string },
                };
                var scope = try ctx.openScope();
                defer scope.close();
                for (order) |name| {
                    const method = try ctx.invoke(.ordinary_get, .{ obj, name, cellValue(obj) });
                    if (ctx.isCallable(method)) {
                        _ = try scope.push(method);
                        const result = try ctx.invoke(.call, .{ method, cellValue(obj), @as([]const Value, &.{}) });
                        if (ctx.typeOf(result) != .object) return result;
                    }
                }
                return ctx.throwTypeError(Message.no_primitive);
            }

            pub fn to_primitive(ctx: *Context(.all), input: Value, preferred: ?PreferredType) error{ OutOfMemory, Throw }!Value {
                if (ctx.typeOf(input) != .object) return input;
                const obj = cellOf(input).?;
                const names = ctx.intrinsics();
                if (try ctx.invoke(.get_method, .{ obj, names.symbol_to_primitive })) |exotic| {
                    var scope = try ctx.openScope();
                    defer scope.close();
                    _ = try scope.push(cellValue(exotic));
                    const hint = if (preferred) |kind| switch (kind) {
                        .string => names.string_string,
                        .number => names.number_string,
                    } else names.default_string;
                    const hint_argument = [_]Value{cellValue(hint)};
                    const result = try ctx.invoke(.call, .{ cellValue(exotic), input, @as([]const Value, &hint_argument) });
                    if (ctx.typeOf(result) != .object) return result;
                    return ctx.throwTypeError(Message.primitive_object);
                }
                return ctx.invoke(.ordinary_to_primitive, .{ obj, preferred orelse .number });
            }

            pub fn to_numeric(ctx: *Context(.all), arg: Value) error{ OutOfMemory, Throw }!Numeric {
                const primitive = try ctx.invoke(.to_primitive, .{ arg, .number });
                switch (ctx.typeOf(primitive)) {
                    .bigint => return .{ .bigint = cellOf(primitive).? },
                    // ToNumber returns a Number unchanged.
                    .number => return .{ .number = ctx.numberOf(primitive) },
                    else => {},
                }
                var scope = try ctx.openScope();
                defer scope.close();
                _ = try scope.push(primitive);
                return .{ .number = try ctx.invoke(.to_number, .{primitive}) };
            }

            pub fn to_number(ctx: *Context(.all), arg: Value) error{ OutOfMemory, Throw }!f64 {
                switch (ctx.typeOf(arg)) {
                    .number => return ctx.numberOf(arg),
                    .symbol => return ctx.throwTypeError(Message.symbol_to_number),
                    .bigint => return ctx.throwTypeError(Message.bigint_to_number),
                    .undefined => return std.math.nan(f64),
                    .null => return 0,
                    .boolean => return if (V.asBoolean(arg)) 1 else 0,
                    .string => return ctx.invoke(.string_to_number, .{web_string.View{ .units = ctx.stringUnits(cellOf(arg).?) }}),
                    .object => {
                        const primitive = try ctx.invoke(.to_primitive, .{ arg, .number });
                        if (ctx.typeOf(primitive) == .number) return ctx.numberOf(primitive);
                        var scope = try ctx.openScope();
                        defer scope.close();
                        _ = try scope.push(primitive);
                        return ctx.invoke(.to_number, .{primitive});
                    },
                }
            }

            pub fn to_string(ctx: *Context(.all), arg: Value) error{ OutOfMemory, Throw }!CellRef {
                const names = ctx.intrinsics();
                switch (ctx.typeOf(arg)) {
                    .string => return cellOf(arg).?,
                    .symbol => return ctx.throwTypeError(Message.symbol_to_string),
                    .undefined => return names.undefined_string,
                    .null => return names.null_string,
                    .boolean => return if (V.asBoolean(arg)) names.true_string else names.false_string,
                    .number => return ctx.invoke(.number_to_string, .{ctx.numberOf(arg)}),
                    .bigint => return ctx.invoke(.bigint_to_string, .{cellOf(arg).?}),
                    .object => {
                        const primitive = try ctx.invoke(.to_primitive, .{ arg, .string });
                        var scope = try ctx.openScope();
                        defer scope.close();
                        _ = try scope.push(primitive);
                        return ctx.invoke(.to_string, .{primitive});
                    },
                }
            }

            pub fn to_property_key(ctx: *Context(.all), arg: Value) error{ OutOfMemory, Throw }!CellRef {
                const key = try ctx.invoke(.to_primitive, .{ arg, .string });
                switch (ctx.typeOf(key)) {
                    // ToString returns a String unchanged.
                    .symbol, .string => return cellOf(key).?,
                    else => {},
                }
                var scope = try ctx.openScope();
                defer scope.close();
                _ = try scope.push(key);
                return ctx.invoke(.to_string, .{key});
            }

            /// `ApplyStringOrNumericBinaryOperator` with the operator `+`.
            pub fn addition(ctx: *Context(.all), left: Value, right: Value) error{ OutOfMemory, Throw }!Value {
                var scope = try ctx.openScope();
                defer scope.close();
                const left_primitive = try ctx.invoke(.to_primitive, .{ left, null });
                _ = try scope.push(left_primitive);
                const right_primitive = try ctx.invoke(.to_primitive, .{ right, null });
                _ = try scope.push(right_primitive);
                if (ctx.typeOf(left_primitive) == .string or ctx.typeOf(right_primitive) == .string) {
                    const left_string = try ctx.invoke(.to_string, .{left_primitive});
                    _ = try scope.push(cellValue(left_string));
                    const right_string = try ctx.invoke(.to_string, .{right_primitive});
                    _ = try scope.push(cellValue(right_string));
                    return cellValue(try ctx.invoke(.string_concat, .{ left_string, right_string }));
                }
                // A BigInt left numeric is the rooted left primitive itself.
                const left_numeric = try ctx.invoke(.to_numeric, .{left_primitive});
                const right_numeric = try ctx.invoke(.to_numeric, .{right_primitive});
                switch (left_numeric) {
                    .number => |x| switch (right_numeric) {
                        .number => |y| return ctx.allocateNumber(ctx.invoke(.number_add, .{ x, y })),
                        .bigint => {},
                    },
                    .bigint => |x| switch (right_numeric) {
                        .bigint => |y| return cellValue(try ctx.invoke(.bigint_add, .{ x, y })),
                        .number => {},
                    },
                }
                return ctx.throwTypeError(Message.mixed_addition);
            }
        };
    };
}

const test_representations = .{ .reference, .nan_box, .tagged_index };

fn ascii(comptime text: []const u8) []const u16 {
    return comptime blk: {
        var units: [text.len]u16 = undefined;
        for (text, 0..) |byte, i| units[i] = byte;
        const frozen = units;
        break :blk &frozen;
    };
}

const Mode = enum {
    return_host_data,
    return_this,
    return_new_object,
    throw_fresh_object,
    record_argument,
    echo,
    redefine_to_string,
    collect_allocate_return_g,
    return_fresh_l,
    allocate_return_r,
    return_addition,
};

/// The frozen messages M1 through M8.
const messages = [_][]const u8{
    "Symbol.toPrimitive method returned an object",
    "method is not callable",
    "cannot convert object to primitive value",
    "cannot convert a Symbol value to a string",
    "cannot convert a Symbol value to a number",
    "cannot convert a BigInt value to a number",
    "cannot mix BigInt and other types in addition",
    "value is not a function",
};

fn Harness(comptime Rt: type) type {
    return struct {
        const H = @This();
        const Value = Rt.Value;
        const Context = Rt.Context(.all);

        const Record = struct {
            harness: *H,
            name: []const u8,
            mode: Mode,
            seen_this: Value = Rt.undefined_value,
            seen_args: [4]Value = undefined,
            seen_count: usize = 0,
            thrown: ?CellRef = null,
        };

        gpa: std.mem.Allocator,
        store: dom.Store,
        document: dom.NodeHandle,
        heap: Rt.Heap,
        c: Context,
        transcript: std.ArrayList(u8) = .empty,
        calls: std.ArrayList(u8) = .empty,
        records: std.ArrayList(*Record) = .empty,

        fn init(h: *H, options: Rt.Heap.Options) !void {
            h.* = .{
                .gpa = testing.allocator,
                .store = try dom.Store.init(testing.allocator),
                .document = undefined,
                .heap = undefined,
                .c = undefined,
            };
            errdefer h.store.deinit();
            h.document = try h.store.createDocument();
            var heap_options = options;
            heap_options.dom = &h.store;
            h.heap = try Rt.Heap.init(h.gpa, heap_options);
            h.c = Rt.rootContext(&h.heap);
        }

        fn deinit(h: *H) void {
            h.heap.deinit();
            h.store.deinit();
            for (h.records.items) |record| h.gpa.destroy(record);
            h.records.deinit(h.gpa);
            h.transcript.deinit(h.gpa);
            h.calls.deinit(h.gpa);
        }

        /// Invokes an operation through the root context and then runs the verifier.
        fn op(h: *H, comptime id: OperationId, args: anytype) anyerror!Rt.Result(id) {
            const result = h.c.invoke(id, args);
            try h.heap.expectInvariants();
            return result;
        }

        fn note(h: *H, comptime format: []const u8, args: anytype) !void {
            try h.transcript.print(h.gpa, format, args);
        }

        fn noteValue(h: *H, label: []const u8, v: Value) !void {
            try h.note("{s}=", .{label});
            try h.describe(v);
            try h.note("\n", .{});
        }

        fn describe(h: *H, v: Value) !void {
            switch (h.c.typeOf(v)) {
                .undefined, .null => try h.note("{s}", .{@tagName(h.c.typeOf(v))}),
                .boolean => try h.note("{}", .{Rt.V.asBoolean(v)}),
                .number => try h.note("number:{x:0>16}", .{@as(u64, @bitCast(h.heap.numberOf(v)))}),
                .string => {
                    try h.note("string:", .{});
                    for (h.c.stringUnits(Rt.cellOf(v).?)) |unit| try h.note("{X:0>4} ", .{unit});
                },
                .bigint => try h.note("bigint:{d}", .{h.c.bigIntOf(Rt.cellOf(v).?)}),
                .symbol => try h.note("symbol", .{}),
                .object => try h.note("object:{s}", .{@tagName(h.c.kindOf(Rt.cellOf(v).?))}),
            }
        }

        fn keep(h: *H, v: Value) !Value {
            _ = try h.heap.addPersistent(v);
            return v;
        }

        fn keepCell(h: *H, ref: CellRef) !CellRef {
            _ = try h.keep(Rt.cellValue(ref));
            return ref;
        }

        fn num(h: *H, x: f64) !Value {
            return h.keep(try h.c.allocateNumber(x));
        }

        fn str(h: *H, comptime text: []const u8) !CellRef {
            return h.unitsString(ascii(text));
        }

        fn unitsString(h: *H, code_units: []const u16) !CellRef {
            return h.keepCell(try h.c.allocateString(code_units));
        }

        fn strValue(h: *H, comptime text: []const u8) !Value {
            return Rt.cellValue(try h.str(text));
        }

        fn bigint(h: *H, amount: i128) !CellRef {
            var limbs: [4]std.math.big.Limb = undefined;
            const big = std.math.big.int.Mutable.init(&limbs, amount);
            return h.keepCell(try h.c.allocateBigInt(big.toConst()));
        }

        fn symbol(h: *H) !CellRef {
            return h.keepCell(try h.c.allocateSymbol(try h.str("probe")));
        }

        fn object(h: *H) !CellRef {
            return h.objectWith(h.c.intrinsics().object_prototype);
        }

        fn objectWith(h: *H, prototype: ?CellRef) !CellRef {
            return h.keepCell(try h.c.allocateObject(prototype));
        }

        fn function(h: *H, name: []const u8, mode: Mode, host_data: Value) !CellRef {
            const record = try h.gpa.create(Record);
            errdefer h.gpa.destroy(record);
            record.* = .{ .harness = h, .name = name, .mode = mode };
            try h.records.append(h.gpa, record);
            return h.keepCell(try h.c.allocateFunction(behavior, host_data, record));
        }

        fn recordOf(h: *H, function_cell: CellRef) *Record {
            return @ptrCast(@alignCast(h.c.hostContextOf(function_cell).?));
        }

        fn data(v: Value) Rt.PropertyDescriptor {
            return .{ .value = v, .writable = true, .enumerable = true, .configurable = true };
        }

        fn define(h: *H, target: CellRef, key: CellRef, descriptor: Rt.PropertyDescriptor) !bool {
            return h.op(.ordinary_define_own_property, .{ target, key, descriptor });
        }

        fn defineData(h: *H, target: CellRef, key: CellRef, v: Value) !void {
            try testing.expect(try h.define(target, key, data(v)));
        }

        fn defineMethod(h: *H, target: CellRef, comptime name: []const u8, mode: Mode, host_data: Value) !CellRef {
            const function_cell = try h.function(name, mode, host_data);
            try h.defineData(target, try h.str(name), Rt.cellValue(function_cell));
            return function_cell;
        }

        fn units(h: *H, v: Value) []const u16 {
            return h.c.stringUnits(Rt.cellOf(v).?);
        }

        fn expectUnits(h: *H, expected: []const u16, v: Value) !void {
            try testing.expectEqual(LanguageType.string, h.c.typeOf(v));
            try testing.expectEqualSlices(u16, expected, h.units(v));
        }

        fn expectNumber(h: *H, expected: f64, v: Value) !void {
            try testing.expectEqual(LanguageType.number, h.c.typeOf(v));
            try testing.expectEqual(@as(u64, @bitCast(expected)), @as(u64, @bitCast(h.heap.numberOf(v))));
        }

        fn expectSame(h: *H, expected: Value, actual: Value) !void {
            try testing.expect(try h.op(.same_value, .{ expected, actual }));
        }

        fn expectCalls(h: *H, expected: []const u8) !void {
            try testing.expectEqualStrings(expected, h.calls.items);
            try h.note("calls={s}\n", .{h.calls.items});
            h.calls.clearRetainingCapacity();
        }

        /// Checks that the pending exception is a fresh TypeError with message `expected`.
        fn expectTypeError(h: *H, comptime index: usize) !void {
            const thrown = h.heap.takeException() orelse return error.TestExpectedException;
            try testing.expectEqual(null, h.heap.takeException());
            const error_cell = Rt.cellOf(thrown) orelse return error.TestExpectedObject;
            try testing.expectEqual(Rt.Heap.Kind.error_object, h.c.kindOf(error_cell));
            try testing.expectEqual(h.c.intrinsics().type_error_prototype, h.c.prototypeOf(error_cell).?);
            const message = h.c.ownProperty(error_cell, h.c.intrinsics().message_string) orelse return error.TestExpectedMessage;
            try testing.expectEqual(true, message.writable.?);
            try testing.expectEqual(false, message.enumerable.?);
            try testing.expectEqual(true, message.configurable.?);
            try h.expectUnits(ascii(messages[index]), message.value.?);
            try h.note("TypeError M{d}\n", .{index + 1});
        }

        fn expectThrowsTypeError(h: *H, comptime index: usize, outcome: anytype) !void {
            try testing.expectError(error.Throw, outcome);
            try h.expectTypeError(index);
        }

        fn behavior(c: *Context, this: Value, args: []const Value) error{ OutOfMemory, Throw }!Value {
            const record: *Record = @ptrCast(@alignCast(c.hostContext().?));
            const h = record.harness;
            try h.calls.appendSlice(h.gpa, record.name);
            try h.calls.append(h.gpa, ';');
            record.seen_this = this;
            record.seen_count = @min(args.len, record.seen_args.len);
            @memcpy(record.seen_args[0..record.seen_count], args[0..record.seen_count]);
            const prototype = c.intrinsics().object_prototype;
            switch (record.mode) {
                .return_host_data => return c.hostData(),
                .return_this => return this,
                .return_new_object => return Rt.cellValue(try c.allocateObject(prototype)),
                .throw_fresh_object => {
                    const thrown = try c.allocateObject(prototype);
                    record.thrown = thrown;
                    return c.throwValue(Rt.cellValue(thrown));
                },
                .record_argument => {
                    try h.calls.appendSlice(h.gpa, "arg=");
                    for (c.stringUnits(Rt.cellOf(args[0]).?)) |unit| try h.calls.append(h.gpa, @intCast(unit));
                    try h.calls.append(h.gpa, ';');
                    return c.hostData();
                },
                .echo => return if (args.len == 0) Rt.undefined_value else args[args.len - 1],
                .redefine_to_string => {
                    const descriptor = data(c.hostData());
                    if (!try c.invoke(.ordinary_define_own_property, .{ Rt.cellOf(this).?, c.intrinsics().to_string_string, descriptor })) {
                        return error.OutOfMemory;
                    }
                    return Rt.cellValue(try c.allocateObject(prototype));
                },
                .collect_allocate_return_g => {
                    c.collect();
                    for (0..1000) |_| _ = try c.allocateObject(prototype);
                    return Rt.cellValue(try c.allocateString(&.{ 'g', 0xD800 }));
                },
                .return_fresh_l => return Rt.cellValue(try c.allocateString(&.{ 'L', 0xD800 })),
                .allocate_return_r => {
                    for (0..1000) |_| _ = try c.allocateObject(prototype);
                    return Rt.cellValue(try c.allocateString(&.{'R'}));
                },
                .return_addition => {
                    const two = try c.allocateNumber(2);
                    const three = try c.allocateNumber(3);
                    return c.invoke(.addition, .{ two, three });
                },
            }
        }

        const Scenario = struct {
            name: []const u8,
            run: *const fn (*H, u32) anyerror!void,
            argument: u32 = 0,
        };

        const number_bits = [_]u64{
            0x0000000000000000, 0x8000000000000000, 0x3FF0000000000000, 0xBFF0000000000000,
            0x0000000000000001, 0x8000000000000001, 0x000FFFFFFFFFFFFF, 0x0010000000000000,
            0x7FEFFFFFFFFFFFFF, 0xFFEFFFFFFFFFFFFF, 0x7FF0000000000000, 0xFFF0000000000000,
            0x433FFFFFFFFFFFFF, 0x4340000000000000, 0x4340000000000001, 0xC340000000000000,
            0x3FB999999999999A, 0x3FE0000000000000, 0x41CFFFFFFF800000, 0xC1D0000000000000,
            0x41D0000000000000, 0xC1D0000000400000, 0x41E0000000000000,
        };

        /// The patterns that `tagged_index` stores inline: 0, 1, -1, 1073741823, and -1073741824.
        const inline_bits = [_]u64{ 0x0000000000000000, 0x3FF0000000000000, 0xBFF0000000000000, 0x41CFFFFFFF800000, 0xC1D0000000000000 };

        fn case18(h: *H, _: u32) anyerror!void {
            for (number_bits) |bits| {
                const before = h.heap.stats.cells_allocated;
                const v = try h.c.allocateNumber(@bitCast(bits));
                try h.heap.expectInvariants();
                const allocated = h.heap.stats.cells_allocated - before;
                const stored_inline = Rt.representation != .tagged_index or std.mem.indexOfScalar(u64, &inline_bits, bits) != null;
                try testing.expectEqual(@as(u64, if (stored_inline) 0 else 1), allocated);
                if (allocated == 1) try testing.expectEqual(Rt.Heap.Kind.heap_number, h.c.kindOf(Rt.cellOf(v).?));
                try testing.expectEqual(bits, @as(u64, @bitCast(h.heap.numberOf(v))));
                try h.note("{x:0>16} cells={d}\n", .{ bits, allocated });
            }
        }

        const nan_bits = [_]u64{
            0x7FF8000000000000, 0xFFF8000000000000, 0x7FF8000000000001, 0x7FFFFFFFFFFFFFFF,
            0xFFF8000000000001, 0xFFFFFFFFFFFFFFFF, 0x7FF0000000000001, 0x7FF4000000000000,
            0x7FF7FFFFFFFFFFFF, 0xFFF0000000000001, 0xFFF7FFFFFFFFFFFF, 0xFFF9000000000005,
            0xFFFA000000000001,
        };

        fn case19(h: *H, _: u32) anyerror!void {
            for (nan_bits) |bits| {
                const v = try h.c.allocateNumber(@bitCast(bits));
                try h.heap.expectInvariants();
                if (Rt.representation == .tagged_index) {
                    try testing.expectEqual(Class.cell, Rt.V.classify(v));
                    try testing.expectEqual(Rt.Heap.Kind.heap_number, h.c.kindOf(Rt.cellOf(v).?));
                } else {
                    try testing.expectEqual(Class.number, Rt.V.classify(v));
                }
                if (Rt.representation == .nan_box) try testing.expectEqual(0x7FF8000000000000, Rt.V.rawBits(v));
                try testing.expect(std.math.isNan(h.heap.numberOf(v)));
                try h.note("{x:0>16} nan\n", .{bits});
            }
            const sum = try h.op(.number_add, .{ std.math.inf(f64), -std.math.inf(f64) });
            const boxed = try h.c.allocateNumber(sum);
            try testing.expectEqual(LanguageType.number, h.c.typeOf(boxed));
            try testing.expect(std.math.isNan(h.heap.numberOf(boxed)));
            try h.note("infinity sum nan\n", .{});
        }

        fn case24(h: *H, _: u32) anyerror!void {
            const all_units = try h.gpa.alloc(u16, 65536);
            defer h.gpa.free(all_units);
            for (all_units, 0..) |*unit, i| unit.* = @intCast(i);
            const string = try h.unitsString(all_units);
            const doubled = try h.op(.string_concat, .{ string, string });
            const doubled_units = h.c.stringUnits(doubled);
            try testing.expectEqual(131072, doubled_units.len);
            try testing.expectEqualSlices(u16, all_units, doubled_units[0..65536]);
            try testing.expectEqualSlices(u16, all_units, doubled_units[65536..]);
            try testing.expectEqual(string, try h.op(.to_string, .{Rt.cellValue(string)}));
            const key = try h.op(.to_property_key, .{Rt.cellValue(string)});
            try testing.expectEqual(string, key);
            try testing.expectEqualSlices(u16, all_units, h.c.stringUnits(key));

            const holder = try h.object();
            try h.defineData(holder, key, try h.num(42));
            try h.expectNumber(42, try h.op(.ordinary_get, .{ holder, key, Rt.cellValue(holder) }));
            const copy = try h.unitsString(all_units);
            try testing.expect(try h.op(.same_value, .{ Rt.cellValue(string), Rt.cellValue(copy) }));
            try h.expectNumber(42, try h.op(.ordinary_get, .{ holder, copy, Rt.cellValue(holder) }));
            all_units[1234] = 0;
            const different = try h.unitsString(all_units);
            try testing.expect(!try h.op(.same_value, .{ Rt.cellValue(string), Rt.cellValue(different) }));
            try h.note("string of 65536 units kept\n", .{});

            const high = try h.unitsString(&.{0xD83D});
            const low = try h.unitsString(&.{0xDE00});
            try testing.expectEqualSlices(u16, &.{ 0xD83D, 0xDE00 }, h.c.stringUnits(try h.op(.string_concat, .{ high, low })));
            try testing.expectEqualSlices(u16, &.{ 0xDE00, 0xD83D }, h.c.stringUnits(try h.op(.string_concat, .{ low, high })));

            const keyed = try h.object();
            const surrogate_keys = [_]CellRef{
                try h.unitsString(&.{0xDC00}),
                try h.unitsString(&.{0xFFFD}),
                try h.unitsString(&.{ 0xDC00, 0x0000 }),
            };
            for (surrogate_keys, 0..) |surrogate_key, i| {
                try h.defineData(keyed, surrogate_key, try h.num(@floatFromInt(i + 1)));
            }
            for (surrogate_keys, 0..) |surrogate_key, i| {
                try h.expectNumber(@floatFromInt(i + 1), try h.op(.ordinary_get, .{ keyed, surrogate_key, Rt.cellValue(keyed) }));
                try h.expectNumber(@floatFromInt(i + 1), (try h.op(.ordinary_get_own_property, .{ keyed, surrogate_key })).?.value.?);
            }
            try h.note("surrogate keys distinct\n", .{});
        }

        fn case25(h: *H, _: u32) anyerror!void {
            const echo = try h.function("echo", .echo, Rt.undefined_value);
            const receiver = try h.object();
            const argument_values = [_]Value{ try h.num(1), try h.strValue("s"), Rt.cellValue(receiver) };
            const result = try h.op(.call, .{ Rt.cellValue(echo), Rt.cellValue(receiver), @as([]const Value, &argument_values) });
            try testing.expect(Rt.V.identical(Rt.cellValue(receiver), result));
            const record = h.recordOf(echo);
            try testing.expect(Rt.V.identical(Rt.cellValue(receiver), record.seen_this));
            try testing.expectEqual(3, record.seen_count);
            for (argument_values, record.seen_args[0..3]) |expected, seen| try testing.expect(Rt.V.identical(expected, seen));
            try h.expectCalls("echo;");

            const plain = try h.object();
            try h.expectThrowsTypeError(7, h.op(.call, .{ Rt.cellValue(plain), Rt.undefined_value, @as([]const Value, &.{}) }));
            try h.expectThrowsTypeError(7, h.op(.call, .{ try h.num(1), Rt.undefined_value, @as([]const Value, &.{}) }));

            const holder = try h.object();
            const undefined_key = try h.str("u");
            const null_key = try h.str("n");
            const function_key = try h.str("f");
            const one_key = try h.str("one");
            try h.defineData(holder, undefined_key, Rt.undefined_value);
            try h.defineData(holder, null_key, Rt.null_value);
            try h.defineData(holder, function_key, Rt.cellValue(echo));
            try h.defineData(holder, one_key, try h.num(1));
            try testing.expectEqual(null, try h.op(.get_method, .{ holder, undefined_key }));
            try testing.expectEqual(null, try h.op(.get_method, .{ holder, null_key }));
            try testing.expectEqual(echo, (try h.op(.get_method, .{ holder, function_key })).?);
            try h.expectThrowsTypeError(1, h.op(.get_method, .{ holder, one_key }));

            try testing.expectError(error.Throw, h.op(.call, .{ try h.num(1), Rt.undefined_value, @as([]const Value, &.{}) }));
            const error_object = try h.keep(h.heap.takeException().?);
            const element = try h.store.createElement(h.document, null, .{ .units = ascii("p") });
            const platform = try h.keepCell(try h.c.allocatePlatformObject(h.c.intrinsics().object_prototype, element));
            const candidates = [_]Value{ Rt.cellValue(echo), Rt.cellValue(plain), error_object, Rt.cellValue(platform), try h.strValue("s"), try h.num(1) };
            for (candidates, 0..) |candidate, i| {
                try testing.expectEqual(i == 0, try h.op(.is_callable, .{candidate}));
            }
            try h.note("only the function is callable\n", .{});

            const five = try h.bigint(5);
            const other_five = try h.bigint(5);
            try testing.expect(five != other_five);
            try testing.expect(try h.op(.same_value, .{ Rt.cellValue(five), Rt.cellValue(other_five) }));
            try testing.expect(try h.op(.same_value, .{ try h.num(std.math.nan(f64)), try h.num(std.math.nan(f64)) }));
            try testing.expect(!try h.op(.same_value, .{ try h.num(0.0), try h.num(-0.0) }));
            try h.note("same_value done\n", .{});
        }

        fn expectDescriptor(h: *H, expected: Rt.PropertyDescriptor, actual: ?Rt.PropertyDescriptor) !void {
            const got = actual orelse return error.TestExpectedDescriptor;
            try testing.expectEqual(expected.value == null, got.value == null);
            if (expected.value) |v| try h.expectSame(v, got.value.?);
            try testing.expectEqual(expected.writable, got.writable);
            try testing.expectEqual(expected.get, got.get);
            try testing.expectEqual(expected.set, got.set);
            try testing.expectEqual(expected.enumerable, got.enumerable);
            try testing.expectEqual(expected.configurable, got.configurable);
        }

        fn case26(h: *H, _: u32) anyerror!void {
            const o = try h.object();
            const a = try h.str("a");
            const b = try h.str("b");
            const c_key = try h.str("c");
            const z = try h.str("z");
            const n = try h.str("n");
            const one = try h.num(1);
            const two = try h.num(2);

            // OD1
            const full: Rt.PropertyDescriptor = .{ .value = one, .writable = true, .enumerable = true, .configurable = true };
            try testing.expect(try h.define(o, a, full));
            try h.expectDescriptor(full, try h.op(.ordinary_get_own_property, .{ o, a }));
            // OD2
            try testing.expect(try h.define(o, b, .{ .value = two }));
            try h.expectDescriptor(.{ .value = two, .writable = false, .enumerable = false, .configurable = false }, try h.op(.ordinary_get_own_property, .{ o, b }));
            // OD5
            const positive_zero = try h.num(0.0);
            const first_nan = try h.num(@bitCast(@as(u64, 0x7FF8000000000000)));
            try testing.expect(try h.define(o, z, .{ .value = positive_zero, .writable = false, .configurable = false }));
            try testing.expect(try h.define(o, n, .{ .value = first_nan, .writable = false, .configurable = false }));
            try testing.expect(!try h.define(o, z, .{ .value = try h.num(-0.0) }));
            try h.expectNumber(0.0, (try h.op(.ordinary_get_own_property, .{ o, z })).?.value.?);
            try testing.expect(try h.define(o, n, .{ .value = try h.num(@bitCast(@as(u64, 0xFFF0000000000001))) }));
            try testing.expect(std.math.isNan(h.heap.numberOf((try h.op(.ordinary_get_own_property, .{ o, n })).?.value.?)));
            // OD3
            try testing.expect(try h.op(.ordinary_prevent_extensions, .{o}));
            try testing.expect(!try h.define(o, c_key, .{ .value = one }));
            try testing.expectEqual(null, try h.op(.ordinary_get_own_property, .{ o, c_key }));
            try testing.expectEqual(4, h.c.ownPropertyCount(o));
            // OD4
            const getter = try h.function("getter", .return_this, Rt.undefined_value);
            try testing.expect(!try h.define(o, b, .{ .configurable = true }));
            try testing.expect(!try h.define(o, b, .{ .enumerable = true }));
            try testing.expect(!try h.define(o, b, .{ .get = .{ .function = getter } }));
            try testing.expect(!try h.define(o, b, .{ .writable = true }));
            try testing.expect(!try h.define(o, b, .{ .value = try h.num(3) }));
            try testing.expect(try h.define(o, b, .{ .value = two }));
            // OD6
            try testing.expect(try h.define(o, a, .{ .get = .{ .function = getter } }));
            try h.expectDescriptor(.{ .get = .{ .function = getter }, .set = .undefined, .enumerable = true, .configurable = true }, try h.op(.ordinary_get_own_property, .{ o, a }));
            // OD7
            const five = try h.num(5);
            try testing.expect(try h.define(o, a, .{ .value = five }));
            try h.expectDescriptor(.{ .value = five, .writable = false, .enumerable = true, .configurable = true }, try h.op(.ordinary_get_own_property, .{ o, a }));
            // OD8
            try testing.expect(try h.define(o, a, .{ .enumerable = false }));
            try h.expectDescriptor(.{ .value = five, .writable = false, .enumerable = false, .configurable = true }, try h.op(.ordinary_get_own_property, .{ o, a }));
            // OD9
            try testing.expect(try h.define(o, a, .{}));
            try h.expectDescriptor(.{ .value = five, .writable = false, .enumerable = false, .configurable = true }, try h.op(.ordinary_get_own_property, .{ o, a }));
            try h.note("OD1 through OD9 hold\n", .{});

            const intrinsics = h.c.intrinsics();
            try testing.expectEqual(intrinsics.object_prototype, (try h.op(.ordinary_get_prototype_of, .{o})).?);
            try testing.expectEqual(null, try h.op(.ordinary_get_prototype_of, .{intrinsics.object_prototype}));
            const child = try h.objectWith(o);
            try testing.expectEqual(o, (try h.op(.ordinary_get_prototype_of, .{child})).?);
        }

        fn case27(h: *H, _: u32) anyerror!void {
            const p3 = try h.object();
            const p2 = try h.objectWith(p3);
            const p1 = try h.objectWith(p2);
            const o = try h.objectWith(p1);
            const receiver = Rt.cellValue(o);
            // OG1
            const x = try h.str("x");
            try h.defineData(o, x, try h.num(11));
            try h.expectNumber(11, try h.op(.ordinary_get, .{ o, x, receiver }));
            // OG2
            const k = try h.str("k");
            try h.defineData(p3, k, try h.num(7));
            try h.expectNumber(7, try h.op(.ordinary_get, .{ o, k, receiver }));
            // OG3
            try testing.expect(Rt.V.identical(Rt.undefined_value, try h.op(.ordinary_get, .{ o, try h.str("missing"), receiver })));
            // OG4
            const self_key = try h.str("self");
            const getter = try h.function("getter", .return_this, Rt.undefined_value);
            try testing.expect(try h.define(p1, self_key, .{ .get = .{ .function = getter }, .set = .undefined, .configurable = true }));
            try testing.expect(Rt.V.identical(receiver, try h.op(.ordinary_get, .{ o, self_key, receiver })));
            try h.expectCalls("getter;");
            // OG5
            const no_getter = try h.str("noget");
            const setter = try h.function("setter", .return_this, Rt.undefined_value);
            try testing.expect(try h.define(p1, no_getter, .{ .get = .undefined, .set = .{ .function = setter } }));
            const behaviors = h.heap.stats.behaviors_invoked;
            try testing.expect(Rt.V.identical(Rt.undefined_value, try h.op(.ordinary_get, .{ o, no_getter, receiver })));
            try testing.expectEqual(behaviors, h.heap.stats.behaviors_invoked);
            // OG6
            const boom = try h.str("boom");
            const thrower = try h.function("thrower", .throw_fresh_object, Rt.undefined_value);
            try testing.expect(try h.define(o, boom, .{ .get = .{ .function = thrower } }));
            try testing.expectError(error.Throw, h.op(.ordinary_get, .{ o, boom, receiver }));
            const thrown = h.heap.takeException().?;
            try testing.expect(Rt.V.identical(Rt.cellValue(h.recordOf(thrower).thrown.?), thrown));
            try h.expectCalls("thrower;");
            // OG7
            const symbol_key = try h.symbol();
            const other_symbol = try h.symbol();
            const low = try h.unitsString(&.{0xDC00});
            const replacement = try h.unitsString(&.{0xFFFD});
            try h.defineData(o, symbol_key, try h.num(1));
            try h.defineData(o, low, try h.num(2));
            try h.defineData(o, replacement, try h.num(3));
            try h.expectNumber(1, try h.op(.ordinary_get, .{ o, symbol_key, receiver }));
            try h.expectNumber(2, try h.op(.ordinary_get, .{ o, low, receiver }));
            try h.expectNumber(3, try h.op(.ordinary_get, .{ o, replacement, receiver }));
            try testing.expect(Rt.V.identical(Rt.undefined_value, try h.op(.ordinary_get, .{ o, other_symbol, receiver })));
            // OG8
            const busy = try h.str("busy");
            const collecting = try h.function("collecting", .collect_allocate_return_g, Rt.undefined_value);
            try testing.expect(try h.define(o, busy, .{ .get = .{ .function = collecting } }));
            try h.expectUnits(&.{ 0x0067, 0xD800 }, try h.op(.ordinary_get, .{ o, busy, receiver }));
            try h.expectCalls("collecting;");
            try h.note("OG1 through OG8 hold\n", .{});
        }

        fn case28(h: *H, _: u32) anyerror!void {
            const intrinsics = h.c.intrinsics();
            const to_primitive_key = intrinsics.symbol_to_primitive;
            // TP1
            const behaviors = h.heap.stats.behaviors_invoked;
            const primitives = [_]Value{
                Rt.undefined_value,           Rt.null_value,                 Rt.boolean(true),
                try h.num(-0.0),              try h.num(std.math.nan(f64)),  try h.strValue("p"),
                Rt.cellValue(try h.symbol()), Rt.cellValue(try h.bigint(9)),
            };
            for (primitives) |primitive| {
                try testing.expect(Rt.V.identical(primitive, try h.op(.to_primitive, .{ primitive, null })));
            }
            try testing.expectEqual(behaviors, h.heap.stats.behaviors_invoked);
            // TP2
            const exotic = try h.object();
            const recorder = try h.function("exotic", .record_argument, try h.num(42));
            try h.defineData(exotic, to_primitive_key, Rt.cellValue(recorder));
            const hints = [_]?PreferredType{ null, .string, .number };
            for (hints) |hint| try h.expectNumber(42, try h.op(.to_primitive, .{ Rt.cellValue(exotic), hint }));
            try h.expectCalls("exotic;arg=default;exotic;arg=string;exotic;arg=number;");
            // TP3
            const objectifier = try h.object();
            try h.defineData(objectifier, to_primitive_key, Rt.cellValue(try h.function("objectify", .return_new_object, Rt.undefined_value)));
            try h.expectThrowsTypeError(0, h.op(.to_primitive, .{ Rt.cellValue(objectifier), null }));
            try h.expectCalls("objectify;");
            // TP4
            const not_callable = try h.object();
            try h.defineData(not_callable, to_primitive_key, try h.num(1));
            try h.expectThrowsTypeError(1, h.op(.to_primitive, .{ Rt.cellValue(not_callable), null }));
            // TP5
            const nulled = try h.object();
            try h.defineData(nulled, to_primitive_key, Rt.null_value);
            _ = try h.defineMethod(nulled, "valueOf", .return_host_data, try h.num(5));
            _ = try h.defineMethod(nulled, "toString", .return_host_data, try h.strValue("s"));
            try h.expectNumber(5, try h.op(.to_primitive, .{ Rt.cellValue(nulled), null }));
            try h.expectCalls("valueOf;");
            // TP6
            try h.expectUnits(ascii("s"), try h.op(.to_primitive, .{ Rt.cellValue(nulled), .string }));
            try h.expectCalls("toString;");
            // TP7
            const fallback = try h.object();
            _ = try h.defineMethod(fallback, "valueOf", .return_new_object, Rt.undefined_value);
            _ = try h.defineMethod(fallback, "toString", .return_host_data, try h.strValue("t"));
            try h.expectUnits(ascii("t"), try h.op(.to_primitive, .{ Rt.cellValue(fallback), .number }));
            try h.expectCalls("valueOf;toString;");
            // TP8
            const raising_object = try h.object();
            const thrower = try h.defineMethod(raising_object, "valueOf", .throw_fresh_object, Rt.undefined_value);
            _ = try h.defineMethod(raising_object, "toString", .return_host_data, try h.strValue("t"));
            try testing.expectError(error.Throw, h.op(.to_primitive, .{ Rt.cellValue(raising_object), .number }));
            try testing.expect(Rt.V.identical(Rt.cellValue(h.recordOf(thrower).thrown.?), h.heap.takeException().?));
            try h.expectCalls("valueOf;");
            // TP9
            const bare = try h.objectWith(null);
            try h.defineData(bare, intrinsics.value_of_string, try h.num(1));
            try h.expectThrowsTypeError(2, h.op(.to_primitive, .{ Rt.cellValue(bare), .number }));
            // TP10
            const redefining = try h.object();
            const replacement = try h.function("newToString", .return_host_data, try h.strValue("new"));
            _ = try h.defineMethod(redefining, "valueOf", .redefine_to_string, Rt.cellValue(replacement));
            _ = try h.defineMethod(redefining, "toString", .return_host_data, try h.strValue("old"));
            try h.expectUnits(ascii("new"), try h.op(.to_primitive, .{ Rt.cellValue(redefining), .number }));
            try h.expectCalls("valueOf;newToString;");
            // TP11
            const prototype = try h.object();
            const method = try h.function("method", .record_argument, try h.num(42));
            const getter = try h.function("getter", .return_host_data, Rt.cellValue(method));
            try testing.expect(try h.define(prototype, to_primitive_key, .{ .get = .{ .function = getter }, .set = .undefined }));
            const input = try h.objectWith(prototype);
            try h.expectNumber(42, try h.op(.to_primitive, .{ Rt.cellValue(input), null }));
            try testing.expect(Rt.V.identical(Rt.cellValue(input), h.recordOf(getter).seen_this));
            try testing.expect(Rt.V.identical(Rt.cellValue(input), h.recordOf(method).seen_this));
            try h.expectCalls("getter;method;arg=default;");
        }

        fn case29(h: *H, _: u32) anyerror!void {
            const symbol_value = Rt.cellValue(try h.symbol());
            const big = try h.bigint(5);
            const hex_object = try h.object();
            _ = try h.defineMethod(hex_object, "valueOf", .return_host_data, try h.strValue("0x10"));
            const symbol_object = try h.object();
            _ = try h.defineMethod(symbol_object, "valueOf", .return_host_data, symbol_value);
            const big_object = try h.object();
            _ = try h.defineMethod(big_object, "valueOf", .return_host_data, Rt.cellValue(big));

            const inputs = [_]Value{ Rt.undefined_value, Rt.null_value, Rt.boolean(false), Rt.boolean(true), symbol_value, Rt.cellValue(big), Rt.cellValue(hex_object), Rt.cellValue(symbol_object) };
            const expected = [_]?f64{ std.math.nan(f64), 0.0, 0.0, 1.0, null, null, 16.0, null };
            const thrown = [_]usize{ 0, 0, 0, 0, 4, 5, 0, 4 };
            for (inputs, expected, thrown) |input, expected_number, message| {
                if (expected_number) |x| {
                    const result = try h.op(.to_number, .{input});
                    if (std.math.isNan(x)) try testing.expect(std.math.isNan(result)) else try testing.expectEqual(@as(u64, @bitCast(x)), @as(u64, @bitCast(result)));
                    try h.note("to_number {x:0>16}\n", .{@as(u64, @bitCast(result))});
                } else switch (message) {
                    4 => try h.expectThrowsTypeError(4, h.op(.to_number, .{input})),
                    5 => try h.expectThrowsTypeError(5, h.op(.to_number, .{input})),
                    else => unreachable,
                }
                if (Rt.V.identical(input, Rt.cellValue(big))) continue;
                if (expected_number) |x| {
                    const numeric = try h.op(.to_numeric, .{input});
                    const result = numeric.number;
                    if (std.math.isNan(x)) try testing.expect(std.math.isNan(result)) else try testing.expectEqual(@as(u64, @bitCast(x)), @as(u64, @bitCast(result)));
                } else {
                    try h.expectThrowsTypeError(4, h.op(.to_numeric, .{input}));
                }
            }
            try testing.expectEqual(big, (try h.op(.to_numeric, .{Rt.cellValue(big)})).bigint);
            const unwrapped = (try h.op(.to_numeric, .{Rt.cellValue(big_object)})).bigint;
            try testing.expect(try h.op(.same_value, .{ Rt.cellValue(big), Rt.cellValue(unwrapped) }));
            try h.expectCalls("valueOf;valueOf;valueOf;valueOf;valueOf;");
        }

        fn case30(h: *H, _: u32) anyerror!void {
            const intrinsics = h.c.intrinsics();
            const immediates = [_]Value{ Rt.undefined_value, Rt.null_value, Rt.boolean(true), Rt.boolean(false) };
            const cells = [_]CellRef{ intrinsics.undefined_string, intrinsics.null_string, intrinsics.true_string, intrinsics.false_string };
            for (immediates, cells) |immediate, cell| {
                try testing.expectEqual(cell, try h.op(.to_string, .{immediate}));
            }
            const string = try h.str("same");
            try testing.expectEqual(string, try h.op(.to_string, .{Rt.cellValue(string)}));

            const big_inputs = [_]i128{ -5, 0, (1 << 64) + 1 };
            const big_texts = [_][]const u16{ ascii("-5"), ascii("0"), ascii("18446744073709551617") };
            for (big_inputs, big_texts) |big, text| {
                try h.expectUnits(text, Rt.cellValue(try h.op(.to_string, .{Rt.cellValue(try h.bigint(big))})));
            }
            for (number_vectors.to_string_vectors) |vector| {
                const text = try h.op(.to_string, .{try h.num(@bitCast(vector.bits))});
                const actual = h.c.stringUnits(text);
                try testing.expectEqual(vector.text.len, actual.len);
                for (vector.text, actual) |byte, unit| try testing.expectEqual(@as(u16, byte), unit);
            }
            const symbol_cell = try h.symbol();
            try h.expectThrowsTypeError(3, h.op(.to_string, .{Rt.cellValue(symbol_cell)}));
            const lone = try h.object();
            _ = try h.defineMethod(lone, "toString", .return_host_data, Rt.cellValue(try h.unitsString(&.{ 0x0078, 0xDC00 })));
            try h.expectUnits(&.{ 0x0078, 0xDC00 }, Rt.cellValue(try h.op(.to_string, .{Rt.cellValue(lone)})));

            try testing.expectEqual(symbol_cell, try h.op(.to_property_key, .{Rt.cellValue(symbol_cell)}));
            try h.expectUnits(ascii("0"), Rt.cellValue(try h.op(.to_property_key, .{try h.num(-0.0)})));
            try h.expectUnits(ascii("1.5"), Rt.cellValue(try h.op(.to_property_key, .{try h.num(1.5)})));
            try h.expectUnits(ascii("1e+21"), Rt.cellValue(try h.op(.to_property_key, .{try h.num(1e21)})));
            const symbolic = try h.object();
            _ = try h.defineMethod(symbolic, "toString", .return_host_data, Rt.cellValue(symbol_cell));
            try testing.expectEqual(symbol_cell, try h.op(.to_property_key, .{Rt.cellValue(symbolic)}));
            try h.expectThrowsTypeError(3, h.op(.to_string, .{Rt.cellValue(symbolic)}));
            try h.expectCalls("toString;toString;toString;");
        }

        fn additionRow(h: *H, row: u32) anyerror!void {
            const add = struct {
                fn run(harness: *H, left: Value, right: Value) anyerror!Value {
                    return harness.op(.addition, .{ left, right });
                }
            }.run;
            switch (row) {
                1 => try h.expectNumber(3, try add(h, try h.num(1), try h.num(2))),
                2 => try h.expectUnits(ascii("11"), try add(h, try h.strValue("1"), try h.num(1))),
                3 => try h.expectUnits(ascii("11"), try add(h, try h.num(1), try h.strValue("1"))),
                4 => try h.expectNumber(2, try add(h, Rt.boolean(true), try h.num(1))),
                5 => try h.expectNumber(1, try add(h, Rt.null_value, try h.num(1))),
                6 => try testing.expect(std.math.isNan(h.heap.numberOf(try add(h, Rt.undefined_value, try h.num(1))))),
                7 => try h.expectUnits(ascii("aundefined"), try add(h, try h.strValue("a"), Rt.undefined_value)),
                8 => try h.expectNumber(-0.0, try add(h, try h.num(-0.0), try h.num(-0.0))),
                9 => try h.expectNumber(@bitCast(@as(u64, 0x3FD3333333333334)), try add(h, try h.num(0.1), try h.num(0.2))),
                10 => try h.expectSame(Rt.cellValue(try h.bigint(3)), try add(h, Rt.cellValue(try h.bigint(1)), Rt.cellValue(try h.bigint(2)))),
                11 => {
                    const sum = try h.keep(try add(h, Rt.cellValue(try h.bigint(1 << 64)), Rt.cellValue(try h.bigint(1))));
                    try testing.expectEqual(LanguageType.bigint, h.c.typeOf(sum));
                    try h.expectUnits(ascii("18446744073709551617"), Rt.cellValue(try h.op(.to_string, .{sum})));
                },
                12 => try h.expectThrowsTypeError(6, add(h, Rt.cellValue(try h.bigint(1)), try h.num(1))),
                13 => try h.expectUnits(ascii("x1"), try add(h, try h.strValue("x"), Rt.cellValue(try h.bigint(1)))),
                14 => try h.expectThrowsTypeError(4, add(h, Rt.cellValue(try h.symbol()), try h.num(1))),
                15 => try h.expectThrowsTypeError(3, add(h, try h.strValue(""), Rt.cellValue(try h.symbol()))),
                16 => {
                    const left = try h.object();
                    _ = try h.defineMethod(left, "valueOf", .return_host_data, try h.num(1));
                    h.recordOf(try h.functionNamed(left, "valueOf")).name = "L.valueOf";
                    const right = try h.object();
                    _ = try h.defineMethod(right, "valueOf", .return_host_data, try h.num(2));
                    h.recordOf(try h.functionNamed(right, "valueOf")).name = "R.valueOf";
                    try h.expectNumber(3, try add(h, Rt.cellValue(left), Rt.cellValue(right)));
                    try h.expectCalls("L.valueOf;R.valueOf;");
                },
                17 => try h.expectUnits(&.{ 0xD83D, 0xDE00 }, try add(h, Rt.cellValue(try h.unitsString(&.{0xD83D})), Rt.cellValue(try h.unitsString(&.{0xDE00})))),
                18 => {
                    try h.expectNumber(1073741824, try add(h, try h.num(1073741823), try h.num(1)));
                    try h.expectNumber(-1073741825, try add(h, try h.num(-1073741824), try h.num(-1)));
                },
                19 => {
                    const left = try h.object();
                    _ = try h.defineMethod(left, "valueOf", .return_fresh_l, Rt.undefined_value);
                    const right = try h.object();
                    _ = try h.defineMethod(right, "valueOf", .allocate_return_r, Rt.undefined_value);
                    try h.expectUnits(&.{ 0x004C, 0xD800, 0x0052 }, try add(h, Rt.cellValue(left), Rt.cellValue(right)));
                    try h.expectCalls("valueOf;valueOf;");
                },
                20 => {
                    const nested = try h.object();
                    _ = try h.defineMethod(nested, "valueOf", .return_addition, Rt.undefined_value);
                    try h.expectNumber(6, try add(h, Rt.cellValue(nested), try h.num(1)));
                    try h.expectCalls("valueOf;");
                },
                21 => {
                    const exotic = try h.object();
                    const recorder = try h.function("exotic", .record_argument, try h.num(1));
                    try h.defineData(exotic, h.c.intrinsics().symbol_to_primitive, Rt.cellValue(recorder));
                    try h.expectNumber(2, try add(h, Rt.cellValue(exotic), try h.num(1)));
                    try h.expectCalls("exotic;arg=default;");
                },
                else => unreachable,
            }
            try h.note("AD{d} holds\n", .{row});
        }

        /// Returns the function stored in the data property `name` of `holder`.
        fn functionNamed(h: *H, holder: CellRef, comptime name: []const u8) !CellRef {
            const key = try h.str(name);
            const descriptor = (try h.op(.ordinary_get_own_property, .{ holder, key })).?;
            return Rt.cellOf(descriptor.value.?).?;
        }

        fn case32(h: *H, _: u32) anyerror!void {
            const intrinsics = h.c.intrinsics();
            const objectifier = try h.object();
            try h.defineData(objectifier, intrinsics.symbol_to_primitive, Rt.cellValue(try h.function("objectify", .return_new_object, Rt.undefined_value)));
            const holder = try h.object();
            const one_key = try h.str("one");
            try h.defineData(holder, one_key, try h.num(1));
            const bare = try h.objectWith(null);
            const symbol_value = Rt.cellValue(try h.symbol());
            const big = Rt.cellValue(try h.bigint(1));

            inline for (0..8) |index| {
                const outcome: anyerror!void = switch (index) {
                    0 => if (h.op(.to_primitive, .{ Rt.cellValue(objectifier), null })) |_| {} else |err| err,
                    1 => if (h.op(.get_method, .{ holder, one_key })) |_| {} else |err| err,
                    2 => if (h.op(.ordinary_to_primitive, .{ bare, .number })) |_| {} else |err| err,
                    3 => if (h.op(.to_string, .{symbol_value})) |_| {} else |err| err,
                    4 => if (h.op(.to_number, .{symbol_value})) |_| {} else |err| err,
                    5 => if (h.op(.to_number, .{big})) |_| {} else |err| err,
                    6 => if (h.op(.addition, .{ big, try h.num(1) })) |_| {} else |err| err,
                    7 => if (h.op(.call, .{ try h.num(1), Rt.undefined_value, @as([]const Value, &.{}) })) |_| {} else |err| err,
                    else => unreachable,
                };
                try testing.expectError(error.Throw, outcome);
                h.c.collect();
                try h.heap.expectInvariants();
                try h.expectTypeError(index);
                try testing.expectEqual(null, h.heap.takeException());
            }
            h.calls.clearRetainingCapacity();
        }

        const scenario_list: []const Scenario = blk: {
            var list: []const Scenario = &.{
                .{ .name = "case 18", .run = case18 },
                .{ .name = "case 19", .run = case19 },
                .{ .name = "case 24", .run = case24 },
                .{ .name = "case 25", .run = case25 },
                .{ .name = "case 26", .run = case26 },
                .{ .name = "case 27", .run = case27 },
                .{ .name = "case 28", .run = case28 },
                .{ .name = "case 29", .run = case29 },
                .{ .name = "case 30", .run = case30 },
            };
            for (1..22) |row| {
                list = list ++ &[_]Scenario{.{ .name = std.fmt.comptimePrint("AD{d}", .{row}), .run = additionRow, .argument = row }};
            }
            break :blk list ++ &[_]Scenario{.{ .name = "case 32", .run = case32 }};
        };

        fn scenarios() []const Scenario {
            return scenario_list;
        }

        fn findScenario(comptime name: []const u8) Scenario {
            return comptime blk: {
                for (scenario_list) |scenario| {
                    if (std.mem.eql(u8, scenario.name, name)) break :blk scenario;
                }
                @compileError("no scenario " ++ name);
            };
        }

        const Outcome = struct {
            transcript: []u8,
            stats: Rt.Heap.Stats,
        };

        /// Runs a scenario on a fresh heap and returns its transcript and the counters that it changed.
        fn runScenario(scenario: Scenario, options: Rt.Heap.Options) !Outcome {
            var h: H = undefined;
            try h.init(options);
            defer h.deinit();
            const before = h.heap.stats;
            scenario.run(&h, scenario.argument) catch |err| {
                std.debug.print("{s} under {s} failed with {t}\n", .{ scenario.name, @tagName(Rt.representation), err });
                return err;
            };
            try h.heap.expectInvariants();
            try testing.expectEqualStrings("", h.calls.items);
            var after = h.heap.stats;
            after.cells_allocated -= before.cells_allocated;
            after.collections -= before.collections;
            after.behaviors_invoked -= before.behaviors_invoked;
            after.throws -= before.throws;
            after.existing_cell_writes -= before.existing_cell_writes;
            after.dead_resolutions -= before.dead_resolutions;
            return .{ .transcript = try h.transcript.toOwnedSlice(h.gpa), .stats = after };
        }

        fn runNamed(comptime name: []const u8) !void {
            const outcome = try runScenario(findScenario(name), .{});
            testing.allocator.free(outcome.transcript);
        }
    };
}

fn runCase(comptime names: []const []const u8) !void {
    inline for (test_representations) |r| {
        const H = Harness(Runtime(r));
        inline for (names) |name| try H.runNamed(name);
    }
}

test "FP-0011 case 6: every invocation leaves the counters of its missing effects unchanged" {
    inline for (test_representations) |r| {
        const Rt = Runtime(r);
        const H = Harness(Rt);
        var checked: [operations.catalog.len]u64 = @splat(0);
        for (H.scenarios()) |scenario| {
            var h: H = undefined;
            try h.init(.{});
            defer h.deinit();
            try scenario.run(&h, scenario.argument);
            try testing.expectEqual(0, h.heap.effect_monitor.violations);
            for (&checked, h.heap.effect_monitor.checked) |*total, count| total.* += count;
        }
        var heap = try Rt.Heap.init(testing.allocator, .{});
        defer heap.deinit();
        try testing.expectEqual(0, try number_vectors.selfCheck(Rt, &heap));
        try testing.expectEqual(0, heap.effect_monitor.violations);
        for (&checked, heap.effect_monitor.checked) |*total, count| total.* += count;
        for (checked, operations.catalog) |count, entry| {
            if (count == 0) std.debug.print("{s} was never invoked\n", .{entry.name});
            try testing.expect(count > 0);
        }
    }
}

test "FP-0011 case 11: every scenario gives the same results under collection stress and quarantine" {
    inline for (test_representations) |r| {
        const Rt = Runtime(r);
        const H = Harness(Rt);
        for (H.scenarios()) |scenario| {
            const normal = try H.runScenario(scenario, .{});
            defer testing.allocator.free(normal.transcript);
            const stressed = try H.runScenario(scenario, .{ .collect_before_each_allocation = true, .quarantine_freed_cells = true });
            defer testing.allocator.free(stressed.transcript);
            try testing.expectEqualStrings(normal.transcript, stressed.transcript);
            if (stressed.stats.dead_resolutions != 0) {
                std.debug.print("scenario {s} under {s}: dead_resolutions {d}\n", .{ scenario.name, @tagName(r), stressed.stats.dead_resolutions });
                return error.TestUnexpectedDeadResolution;
            }
            try testing.expect(stressed.stats.collections >= stressed.stats.cells_allocated);
        }
    }
}

test "FP-0011 case 18: numbers round-trip bit for bit through numberValue and numberOf" {
    try runCase(&.{"case 18"});
}

test "FP-0011 case 19: every NaN pattern boxes to a NaN number" {
    try runCase(&.{"case 19"});
}

test "FP-0011 case 24: strings keep every code unit through concatenation, conversion, and keys" {
    try runCase(&.{"case 24"});
}

test "FP-0011 case 25: call, get_method, is_callable, and same_value follow ECMA-262" {
    try runCase(&.{"case 25"});
}

test "FP-0011 case 26: ordinary_define_own_property follows ValidateAndApplyPropertyDescriptor" {
    try runCase(&.{"case 26"});
}

test "FP-0011 case 27: ordinary_get follows OrdinaryGet" {
    try runCase(&.{"case 27"});
}

test "FP-0011 case 28: to_primitive follows ToPrimitive and OrdinaryToPrimitive" {
    try runCase(&.{"case 28"});
}

test "FP-0011 case 29: to_number and to_numeric follow ECMA-262" {
    try runCase(&.{"case 29"});
}

test "FP-0011 case 30: to_string and to_property_key follow ECMA-262" {
    try runCase(&.{"case 30"});
}

test "FP-0011 case 31: addition follows ApplyStringOrNumericBinaryOperator" {
    try runCase(&.{ "AD1", "AD2", "AD3", "AD4", "AD5", "AD6", "AD7", "AD8", "AD9", "AD10", "AD11", "AD12", "AD13", "AD14", "AD15", "AD16", "AD17", "AD18", "AD19", "AD20", "AD21" });
}

test "FP-0011 case 32: engine-thrown errors are TypeError objects with the frozen messages" {
    try runCase(&.{"case 32"});
}

test {
    _ = @import("operations.zig");
    _ = @import("value.zig");
    _ = @import("heap_catalog.zig");
    _ = @import("heap.zig");
    _ = @import("number.zig");
    _ = @import("number_vectors.zig");
    _ = @import("measure.zig");
}
