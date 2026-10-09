//! The kernels of the operation catalog, one per entry, for one runtime.
//!
//! This file holds no heap pointer and cannot convert a context's sealed heap back to one, because
//! that conversion is private to `runtime.zig`. Each kernel reaches the heap only through the
//! methods of its context, whose effects `bindKernels` checks against the kernel's catalog entry.
//!
//! Rooting protocol: a caller keeps every `Value` and `CellRef` argument rooted for the duration of
//! the call, a kernel returns its result unrooted, and a kernel roots each intermediate that it holds
//! across an invocation with the `allocation` effect.

const std = @import("std");
const number = @import("number.zig");
const operations = @import("operations.zig");
const web_string = @import("../web_string.zig");
const CellRef = @import("value.zig").CellRef;
const PreferredType = @import("runtime.zig").PreferredType;
const Effects = operations.Effects;
const Limb = std.math.big.Limb;

const leaf: Effects = .none;
const allocating: Effects = .{ .allocation = true };
const mutating: Effects = .{ .heap_mutation = true };
const defining: Effects = .{ .allocation = true, .heap_mutation = true };

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

/// Returns the function of an accessor field, or null for an absent field or an undefined accessor.
fn accessorCell(accessor: anytype) ?CellRef {
    return switch (accessor orelse return null) {
        .undefined => null,
        .function => |function| function,
    };
}

/// The kernels of `Rt`. Every public declaration is a kernel named by its operation's id.
pub fn Kernels(comptime Rt: type) type {
    const Context = Rt.Context;
    const Value = Rt.Value;
    const PropertyDescriptor = Rt.PropertyDescriptor;
    const Numeric = Rt.Numeric;
    const cellOf = Rt.cellOf;
    const cellValue = Rt.cellValue;
    const undefined_value = Rt.undefined_value;

    return struct {
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
                .boolean => Rt.V.asBoolean(x) == Rt.V.asBoolean(y),
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
                const slot: Rt.Heap.catalog.Slot = if (desc.isAccessor())
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
                .boolean => return if (Rt.V.asBoolean(arg)) 1 else 0,
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
                .boolean => return if (Rt.V.asBoolean(arg)) names.true_string else names.false_string,
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
}
