//! The operation catalog of the JavaScript runtime.
//!
//! Each entry names an ECMA-262 operation, its operand and result types, and an upper bound of its effects.
//! The catalog is a Zig declaration so that `Runtime(r).bindKernels` can check each kernel's function type
//! against its entry in the same compilation.

const std = @import("std");
const testing = std.testing;

/// The effects that an operation can have, over every input.
pub const Effects = packed struct(u4) {
    /// The operation can run user code. User code can do anything, so this flag requires the other three.
    callback: bool = false,
    /// The operation can allocate a managed cell, so a collection can run, and it can return `error.OutOfMemory`.
    allocation: bool = false,
    /// The operation can return `error.Throw` with the thrown value in the heap's pending-exception slot.
    exception: bool = false,
    /// The operation can change the script-visible state of a cell that existed before the call.
    heap_mutation: bool = false,

    pub const none: Effects = .{};
    pub const all: Effects = .{ .callback = true, .allocation = true, .exception = true, .heap_mutation = true };
};

/// The operand and result types. `Runtime(r).OperandType` maps each one to a Zig type.
pub const Type = enum {
    number,
    boolean,
    value,
    primitive,
    object,
    string,
    string_units,
    bigint,
    property_key,
    numeric,
    method,
    optional_object,
    property_descriptor,
    optional_property_descriptor,
    preferred_type,
    optional_preferred_type,
    arguments,
};

pub const Operand = struct { name: []const u8, type: Type };

pub const OperationId = enum {
    number_add,
    number_same_value,
    same_value,
    is_callable,
    string_to_number,
    ordinary_get_own_property,
    ordinary_get_prototype_of,
    ordinary_prevent_extensions,
    number_to_string,
    bigint_add,
    bigint_to_string,
    string_concat,
    ordinary_define_own_property,
    call,
    get_method,
    ordinary_get,
    ordinary_to_primitive,
    to_primitive,
    to_numeric,
    to_number,
    to_string,
    to_property_key,
    addition,
};

pub const Operation = struct {
    id: OperationId,
    /// The ECMA-262 operation name.
    name: []const u8,
    /// The ECMA-262 fragment identifier.
    anchor: []const u8,
    operands: []const Operand,
    result: Type,
    effects: Effects,
};

const leaf: Effects = .none;
const allocating: Effects = .{ .allocation = true };
const mutating: Effects = .{ .heap_mutation = true };
const defining: Effects = .{ .allocation = true, .heap_mutation = true };

fn operands(comptime list: anytype) []const Operand {
    comptime {
        var result: [list.len]Operand = undefined;
        for (list, &result) |pair, *operand| operand.* = .{ .name = pair[0], .type = pair[1] };
        const frozen = result;
        return &frozen;
    }
}

/// The operations of FP-0011, in catalog order.
/// `Number::toString` and `BigInt::toString` take radix 10 only, and `addition` is
/// `ApplyStringOrNumericBinaryOperator` with the operator `+`.
pub const catalog: []const Operation = &.{
    .{ .id = .number_add, .name = "Number::add", .anchor = "sec-numeric-types-number-add", .operands = operands(.{ .{ "x", .number }, .{ "y", .number } }), .result = .number, .effects = leaf },
    .{ .id = .number_same_value, .name = "Number::sameValue", .anchor = "sec-numeric-types-number-sameValue", .operands = operands(.{ .{ "x", .number }, .{ "y", .number } }), .result = .boolean, .effects = leaf },
    .{ .id = .same_value, .name = "SameValue", .anchor = "sec-samevalue", .operands = operands(.{ .{ "x", .value }, .{ "y", .value } }), .result = .boolean, .effects = leaf },
    .{ .id = .is_callable, .name = "IsCallable", .anchor = "sec-iscallable", .operands = operands(.{.{ "arg", .value }}), .result = .boolean, .effects = leaf },
    .{ .id = .string_to_number, .name = "StringToNumber", .anchor = "sec-stringtonumber", .operands = operands(.{.{ "string", .string_units }}), .result = .number, .effects = leaf },
    .{ .id = .ordinary_get_own_property, .name = "OrdinaryGetOwnProperty", .anchor = "sec-ordinarygetownproperty", .operands = operands(.{ .{ "obj", .object }, .{ "key", .property_key } }), .result = .optional_property_descriptor, .effects = leaf },
    .{ .id = .ordinary_get_prototype_of, .name = "OrdinaryGetPrototypeOf", .anchor = "sec-ordinarygetprototypeof", .operands = operands(.{.{ "obj", .object }}), .result = .optional_object, .effects = leaf },
    .{ .id = .ordinary_prevent_extensions, .name = "OrdinaryPreventExtensions", .anchor = "sec-ordinarypreventextensions", .operands = operands(.{.{ "obj", .object }}), .result = .boolean, .effects = mutating },
    .{ .id = .number_to_string, .name = "Number::toString", .anchor = "sec-numeric-types-number-tostring", .operands = operands(.{.{ "x", .number }}), .result = .string, .effects = allocating },
    .{ .id = .bigint_add, .name = "BigInt::add", .anchor = "sec-numeric-types-bigint-add", .operands = operands(.{ .{ "x", .bigint }, .{ "y", .bigint } }), .result = .bigint, .effects = allocating },
    .{ .id = .bigint_to_string, .name = "BigInt::toString", .anchor = "sec-numeric-types-bigint-tostring", .operands = operands(.{.{ "x", .bigint }}), .result = .string, .effects = allocating },
    .{ .id = .string_concat, .name = "string-concatenation", .anchor = "string-concatenation", .operands = operands(.{ .{ "a", .string }, .{ "b", .string } }), .result = .string, .effects = allocating },
    .{ .id = .ordinary_define_own_property, .name = "OrdinaryDefineOwnProperty", .anchor = "sec-ordinarydefineownproperty", .operands = operands(.{ .{ "obj", .object }, .{ "key", .property_key }, .{ "desc", .property_descriptor } }), .result = .boolean, .effects = defining },
    .{ .id = .call, .name = "Call", .anchor = "sec-call", .operands = operands(.{ .{ "func", .value }, .{ "this", .value }, .{ "args", .arguments } }), .result = .value, .effects = .all },
    .{ .id = .get_method, .name = "GetMethod", .anchor = "sec-getmethod", .operands = operands(.{ .{ "obj", .object }, .{ "key", .property_key } }), .result = .method, .effects = .all },
    .{ .id = .ordinary_get, .name = "OrdinaryGet", .anchor = "sec-ordinaryget", .operands = operands(.{ .{ "obj", .object }, .{ "key", .property_key }, .{ "receiver", .value } }), .result = .value, .effects = .all },
    .{ .id = .ordinary_to_primitive, .name = "OrdinaryToPrimitive", .anchor = "sec-ordinarytoprimitive", .operands = operands(.{ .{ "obj", .object }, .{ "hint", .preferred_type } }), .result = .primitive, .effects = .all },
    .{ .id = .to_primitive, .name = "ToPrimitive", .anchor = "sec-toprimitive", .operands = operands(.{ .{ "input", .value }, .{ "preferred", .optional_preferred_type } }), .result = .primitive, .effects = .all },
    .{ .id = .to_numeric, .name = "ToNumeric", .anchor = "sec-tonumeric", .operands = operands(.{.{ "arg", .value }}), .result = .numeric, .effects = .all },
    .{ .id = .to_number, .name = "ToNumber", .anchor = "sec-tonumber", .operands = operands(.{.{ "arg", .value }}), .result = .number, .effects = .all },
    .{ .id = .to_string, .name = "ToString", .anchor = "sec-tostring", .operands = operands(.{.{ "arg", .value }}), .result = .string, .effects = .all },
    .{ .id = .to_property_key, .name = "ToPropertyKey", .anchor = "sec-topropertykey", .operands = operands(.{.{ "arg", .value }}), .result = .property_key, .effects = .all },
    .{ .id = .addition, .name = "ApplyStringOrNumericBinaryOperator", .anchor = "sec-applystringornumericbinaryoperator", .operands = operands(.{ .{ "left", .value }, .{ "right", .value } }), .result = .value, .effects = .all },
};

/// Holds exactly when every flag of `operation` is also a flag of `context`.
pub fn permits(context: Effects, operation: Effects) bool {
    const granted: u4 = @backingInt(context);
    const required: u4 = @backingInt(operation);
    return required & ~granted == 0;
}

const effect_names = @typeInfo(Effects).@"struct".field_names;

/// Renders an effect set as `{a, b}` in declaration order, or `{}` when it is empty.
pub fn effectsName(comptime effects: Effects) []const u8 {
    comptime {
        var text: []const u8 = "{";
        var first = true;
        for (effect_names) |name| {
            if (!@field(effects, name)) continue;
            if (!first) text = text ++ ", ";
            text = text ++ name;
            first = false;
        }
        return text ++ "}";
    }
}

fn writeEffects(writer: *std.Io.Writer, effects: Effects) std.Io.Writer.Error!void {
    try writer.writeByte('{');
    var first = true;
    inline for (effect_names) |name| {
        if (@field(effects, name)) {
            if (!first) try writer.writeAll(", ");
            try writer.writeAll(name);
            first = false;
        }
    }
    try writer.writeByte('}');
}

/// Returns the catalog entry of `id`. The catalog lists the entries in the order of `OperationId`.
pub fn entry(comptime id: OperationId) Operation {
    return comptime catalog[@backingInt(id)];
}

/// Stops compilation for an entry whose effects break the algebra, and for a duplicate id or name.
pub fn validate(comptime entries: []const Operation) void {
    comptime {
        for (entries, 0..) |operation, index| {
            const effects = operation.effects;
            if (effects.callback and !(effects.allocation and effects.exception and effects.heap_mutation)) {
                @compileError("fairpane-js: operation " ++ operation.name ++ " declares callback without allocation, exception, and heap_mutation");
            }
            if (effects.exception and !effects.allocation) {
                @compileError("fairpane-js: operation " ++ operation.name ++ " declares exception without allocation");
            }
            for (entries[0..index]) |earlier| {
                if (earlier.id == operation.id) @compileError("fairpane-js: duplicate operation id " ++ @tagName(operation.id));
                if (std.mem.eql(u8, earlier.name, operation.name)) @compileError("fairpane-js: duplicate operation name " ++ operation.name);
            }
        }
    }
}

comptime {
    validate(catalog);
    for (catalog, 0..) |operation, index| {
        if (@backingInt(operation.id) != index) @compileError("fairpane-js: the catalog does not follow the order of OperationId");
    }
}

/// Writes one line per entry: `id|name|anchor|operand:type,...|result|effects`.
pub fn writeTable(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (catalog) |operation| {
        try writer.print("{s}|{s}|{s}|", .{ @tagName(operation.id), operation.name, operation.anchor });
        for (operation.operands, 0..) |operand, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("{s}:{s}", .{ operand.name, @tagName(operand.type) });
        }
        try writer.print("|{s}|", .{@tagName(operation.result)});
        try writeEffects(writer, operation.effects);
        try writer.writeByte('\n');
    }
}
const frozen_table =
    \\number_add|Number::add|sec-numeric-types-number-add|x:number,y:number|number|{}
    \\number_same_value|Number::sameValue|sec-numeric-types-number-sameValue|x:number,y:number|boolean|{}
    \\same_value|SameValue|sec-samevalue|x:value,y:value|boolean|{}
    \\is_callable|IsCallable|sec-iscallable|arg:value|boolean|{}
    \\string_to_number|StringToNumber|sec-stringtonumber|string:string_units|number|{}
    \\ordinary_get_own_property|OrdinaryGetOwnProperty|sec-ordinarygetownproperty|obj:object,key:property_key|optional_property_descriptor|{}
    \\ordinary_get_prototype_of|OrdinaryGetPrototypeOf|sec-ordinarygetprototypeof|obj:object|optional_object|{}
    \\ordinary_prevent_extensions|OrdinaryPreventExtensions|sec-ordinarypreventextensions|obj:object|boolean|{heap_mutation}
    \\number_to_string|Number::toString|sec-numeric-types-number-tostring|x:number|string|{allocation}
    \\bigint_add|BigInt::add|sec-numeric-types-bigint-add|x:bigint,y:bigint|bigint|{allocation}
    \\bigint_to_string|BigInt::toString|sec-numeric-types-bigint-tostring|x:bigint|string|{allocation}
    \\string_concat|string-concatenation|string-concatenation|a:string,b:string|string|{allocation}
    \\ordinary_define_own_property|OrdinaryDefineOwnProperty|sec-ordinarydefineownproperty|obj:object,key:property_key,desc:property_descriptor|boolean|{allocation, heap_mutation}
    \\call|Call|sec-call|func:value,this:value,args:arguments|value|{callback, allocation, exception, heap_mutation}
    \\get_method|GetMethod|sec-getmethod|obj:object,key:property_key|method|{callback, allocation, exception, heap_mutation}
    \\ordinary_get|OrdinaryGet|sec-ordinaryget|obj:object,key:property_key,receiver:value|value|{callback, allocation, exception, heap_mutation}
    \\ordinary_to_primitive|OrdinaryToPrimitive|sec-ordinarytoprimitive|obj:object,hint:preferred_type|primitive|{callback, allocation, exception, heap_mutation}
    \\to_primitive|ToPrimitive|sec-toprimitive|input:value,preferred:optional_preferred_type|primitive|{callback, allocation, exception, heap_mutation}
    \\to_numeric|ToNumeric|sec-tonumeric|arg:value|numeric|{callback, allocation, exception, heap_mutation}
    \\to_number|ToNumber|sec-tonumber|arg:value|number|{callback, allocation, exception, heap_mutation}
    \\to_string|ToString|sec-tostring|arg:value|string|{callback, allocation, exception, heap_mutation}
    \\to_property_key|ToPropertyKey|sec-topropertykey|arg:value|property_key|{callback, allocation, exception, heap_mutation}
    \\addition|ApplyStringOrNumericBinaryOperator|sec-applystringornumericbinaryoperator|left:value,right:value|value|{callback, allocation, exception, heap_mutation}
    \\
;

test "FP-0011 case 1: writeTable renders the frozen catalog line for line" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try writeTable(&output.writer);
    var actual = std.mem.splitScalar(u8, output.written(), '\n');
    var expected = std.mem.splitScalar(u8, frozen_table, '\n');
    var lines: usize = 0;
    while (expected.next()) |line| : (lines += 1) {
        try testing.expectEqualStrings(line, actual.next() orelse return error.TestMissingLine);
    }
    try testing.expectEqual(null, actual.next());
    try testing.expectEqual(24, lines);
    try testing.expectEqual(23, catalog.len);
}

test "FP-0011 case 2: the catalog validates and permits is the subset relation" {
    comptime validate(catalog);
    var context_bits: u5 = 0;
    while (context_bits < 16) : (context_bits += 1) {
        var operation_bits: u5 = 0;
        while (operation_bits < 16) : (operation_bits += 1) {
            const context: Effects = @fromBackingInt(@as(u4, @intCast(context_bits)));
            const operation: Effects = @fromBackingInt(@as(u4, @intCast(operation_bits)));
            const subset = (!operation.callback or context.callback) and
                (!operation.allocation or context.allocation) and
                (!operation.exception or context.exception) and
                (!operation.heap_mutation or context.heap_mutation);
            try testing.expectEqual(subset, permits(context, operation));
        }
    }
}

test "FP-0011 case 3: bindKernels binds 23 kernels in catalog order for every representation" {
    const runtime = @import("runtime.zig");
    inline for (.{ runtime.Runtime(.reference), runtime.Runtime(.nan_box), runtime.Runtime(.tagged_index) }) |Rt| {
        const table = Rt.kernel_table;
        try testing.expectEqual(23, table.len);
        for (table, catalog) |bound, operation| {
            try testing.expectEqual(operation.id, bound.id);
        }
    }
}
