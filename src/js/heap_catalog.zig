//! The heap catalog: cell kinds, reference kinds, payload layouts, and the generated tracer and finalizer.
//!
//! Each payload field has exactly one descriptor, and `checkLayout` checks every payload against its layout.
//! The generated tracer and the generated finalizer derive every action from the layouts at compile time.

const std = @import("std");
const testing = std.testing;
const dom = @import("../dom.zig");
const value = @import("value.zig");
const web_string = @import("../web_string.zig");
const CellRef = value.CellRef;
const Limb = std.math.big.Limb;
const WebString = web_string.WebString;

pub const Kind = enum {
    string,
    symbol,
    bigint,
    heap_number,
    ordinary_object,
    builtin_function,
    error_object,
    platform_object,
};

pub const InternalMethods = enum { none, ordinary };

pub const KindInfo = struct {
    object: bool,
    callable: bool,
    internal_methods: InternalMethods,
};

/// The metadata of each kind. `IsCallable` reads `callable`.
pub fn info(kind: Kind) KindInfo {
    return switch (kind) {
        .string, .symbol, .bigint, .heap_number => .{ .object = false, .callable = false, .internal_methods = .none },
        .ordinary_object, .error_object, .platform_object => .{ .object = true, .callable = false, .internal_methods = .ordinary },
        .builtin_function => .{ .object = true, .callable = true, .internal_methods = .ordinary },
    };
}

/// How the tracer and the finalizer treat one payload field.
pub const Descriptor = union(enum) {
    /// A type that contains no `CellRef`, `Value`, or `dom.NodeHandle`.
    plain,
    /// A `Value`; the tracer visits its cell when it holds one.
    value,
    /// A `CellRef`; the tracer visits it.
    cell,
    /// A `?CellRef`; the tracer visits it when present.
    optional_cell,
    /// A `dom.NodeHandle`; the finalizer releases the one retain that the cell holds.
    dom_node,
    /// A `WebString`; the finalizer frees its code units.
    owned_units,
    /// A `[]const std.math.big.Limb`; the finalizer frees the limbs.
    owned_limbs,
    /// A `std.ArrayList(T)`; both apply the layout to each element, and the finalizer then frees the list.
    owned_list: *const Layout,
    /// A struct; both apply the layout to each field.
    @"inline": *const Layout,
    /// A `union(enum)`; both apply the descriptor of the active variant.
    tagged_union: *const Layout,
};

pub const Field = struct { name: []const u8, descriptor: Descriptor };
pub const Layout = struct { name: []const u8, fields: []const Field };

pub const data_slot_layout: Layout = .{ .name = "DataSlot", .fields = &.{
    .{ .name = "value", .descriptor = .value },
    .{ .name = "writable", .descriptor = .plain },
} };

pub const accessor_slot_layout: Layout = .{ .name = "AccessorSlot", .fields = &.{
    .{ .name = "getter", .descriptor = .optional_cell },
    .{ .name = "setter", .descriptor = .optional_cell },
} };

const slot_layout: Layout = .{ .name = "Slot", .fields = &.{
    .{ .name = "data", .descriptor = .{ .@"inline" = &data_slot_layout } },
    .{ .name = "accessor", .descriptor = .{ .@"inline" = &accessor_slot_layout } },
} };

pub const property_layout: Layout = .{ .name = "Property", .fields = &.{
    .{ .name = "key", .descriptor = .cell },
    .{ .name = "enumerable", .descriptor = .plain },
    .{ .name = "configurable", .descriptor = .plain },
    .{ .name = "slot", .descriptor = .{ .tagged_union = &slot_layout } },
} };

pub const object_header_layout: Layout = .{ .name = "ObjectHeader", .fields = &.{
    .{ .name = "prototype", .descriptor = .optional_cell },
    .{ .name = "extensible", .descriptor = .plain },
    .{ .name = "properties", .descriptor = .{ .owned_list = &property_layout } },
} };

const object_field: Field = .{ .name = "object", .descriptor = .{ .@"inline" = &object_header_layout } };

/// Returns the layout of each kind's payload.
pub fn layout(comptime kind: Kind) []const Field {
    return switch (kind) {
        .string => &.{.{ .name = "units", .descriptor = .owned_units }},
        .symbol => &.{.{ .name = "description", .descriptor = .optional_cell }},
        .bigint => &.{
            .{ .name = "positive", .descriptor = .plain },
            .{ .name = "limbs", .descriptor = .owned_limbs },
        },
        .heap_number => &.{.{ .name = "value", .descriptor = .plain }},
        .ordinary_object => &.{object_field},
        .builtin_function => &.{
            object_field,
            .{ .name = "behavior", .descriptor = .plain },
            .{ .name = "host_data", .descriptor = .value },
            .{ .name = "host_context", .descriptor = .plain },
        },
        .error_object => &.{
            object_field,
            .{ .name = "error_kind", .descriptor = .plain },
        },
        .platform_object => &.{
            object_field,
            .{ .name = "node", .descriptor = .dom_node },
        },
    };
}

fn writeDescriptor(writer: *std.Io.Writer, descriptor: Descriptor) std.Io.Writer.Error!void {
    switch (descriptor) {
        .owned_list => |element| try writer.print("owned_list({s})", .{element.name}),
        .@"inline" => |nested| try writer.print("inline({s})", .{nested.name}),
        .tagged_union => |variants| {
            try writer.writeAll("tagged_union(");
            try writeFields(writer, variants.fields);
            try writer.writeByte(')');
        },
        else => try writer.writeAll(@tagName(descriptor)),
    }
}

fn writeFields(writer: *std.Io.Writer, fields: []const Field) std.Io.Writer.Error!void {
    for (fields, 0..) |field, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.print("{s}:", .{field.name});
        try writeDescriptor(writer, field.descriptor);
    }
}

/// Writes `kind|object|callable|field:descriptor,...` for each kind, then `layout|field:descriptor,...`
/// for each named nested layout.
pub fn writeCatalog(writer: *std.Io.Writer) std.Io.Writer.Error!void {
    inline for (comptime std.enums.values(Kind)) |kind| {
        const metadata = info(kind);
        try writer.print("{s}|{s}|{s}|", .{
            @tagName(kind),
            if (metadata.object) "yes" else "no",
            if (metadata.callable) "yes" else "no",
        });
        try writeFields(writer, layout(kind));
        try writer.writeByte('\n');
    }
    const nested = [_]*const Layout{ &object_header_layout, &property_layout, &data_slot_layout, &accessor_slot_layout };
    for (nested) |named| {
        try writer.print("{s}|", .{named.name});
        try writeFields(writer, named.fields);
        try writer.writeByte('\n');
    }
}

/// Holds for a type that is itself a heap reference.
fn isReference(comptime T: type) bool {
    return T == CellRef or T == dom.NodeHandle or
        T == value.Encoding(.reference).Value or
        T == value.Encoding(.nan_box).Value or
        T == value.Encoding(.tagged_index).Value;
}

fn isValueType(comptime T: type) bool {
    return T == value.Encoding(.reference).Value or
        T == value.Encoding(.nan_box).Value or
        T == value.Encoding(.tagged_index).Value;
}

/// Walks struct, union, optional, pointer, slice, and array types for a heap reference.
fn holdsReference(comptime T: type, comptime seen: []const type) bool {
    if (isReference(T)) return true;
    for (seen) |earlier| {
        if (earlier == T) return false;
    }
    const next = seen ++ &[_]type{T};
    return switch (@typeInfo(T)) {
        .@"struct" => |s| for (s.field_types) |Field_| {
            if (holdsReference(Field_, next)) break true;
        } else false,
        .@"union" => |u| for (u.field_types) |Field_| {
            if (holdsReference(Field_, next)) break true;
        } else false,
        .optional => |o| holdsReference(o.child, next),
        .pointer => |p| if (@typeInfo(p.child) == .@"fn") false else holdsReference(p.child, next),
        .array => |a| holdsReference(a.child, next),
        else => false,
    };
}

fn fieldIndex(comptime names: []const [:0]const u8, comptime name: []const u8) ?usize {
    for (names, 0..) |candidate, i| {
        if (std.mem.eql(u8, candidate, name)) return i;
    }
    return null;
}

/// Stops compilation unless `layout_fields` describes every field of `Payload` exactly once
/// with a descriptor that fits the field's type.
pub fn checkLayout(comptime name: []const u8, comptime Payload: type, comptime layout_fields: []const Field) void {
    comptime {
        @setEvalBranchQuota(100_000);
        const names, const types = switch (@typeInfo(Payload)) {
            .@"struct" => |s| .{ s.field_names, s.field_types },
            .@"union" => |u| .{ u.field_names, u.field_types },
            else => @compileError("fairpane-js: layout " ++ name ++ " describes " ++ @typeName(Payload) ++ ", which is not a struct or union"),
        };
        for (names, types) |field_name, Field_| {
            const found = for (layout_fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) break field;
            } else @compileError("fairpane-js: layout " ++ name ++ " does not describe field " ++ field_name);
            checkDescriptor(name, field_name, Field_, found.descriptor);
        }
        for (layout_fields, 0..) |field, i| {
            if (fieldIndex(names, field.name) == null) {
                @compileError("fairpane-js: layout " ++ name ++ " describes field " ++ field.name ++ ", which does not exist");
            }
            for (layout_fields[0..i]) |earlier| {
                if (std.mem.eql(u8, earlier.name, field.name)) @compileError("fairpane-js: layout " ++ name ++ " describes field " ++ field.name ++ " twice");
            }
        }
    }
}

fn checkDescriptor(comptime name: []const u8, comptime field: []const u8, comptime T: type, comptime descriptor: Descriptor) void {
    const mismatch = "fairpane-js: field " ++ field ++ " of layout " ++ name ++ " has type " ++ @typeName(T) ++
        ", which descriptor " ++ @tagName(descriptor) ++ " does not describe";
    switch (descriptor) {
        .plain => if (holdsReference(T, &.{})) {
            @compileError("fairpane-js: field " ++ field ++ " of layout " ++ name ++ " holds a heap reference but is declared plain");
        },
        .value => if (!isValueType(T)) @compileError(mismatch),
        .cell => if (T != CellRef) @compileError(mismatch),
        .optional_cell => if (T != ?CellRef) @compileError(mismatch),
        .dom_node => if (T != dom.NodeHandle) @compileError(mismatch),
        .owned_units => if (T != WebString) @compileError(mismatch),
        .owned_limbs => if (T != []const Limb) @compileError(mismatch),
        .owned_list => |element| {
            if (@typeInfo(T) != .@"struct" or !@hasField(T, "items")) @compileError(mismatch);
            const Element = @typeInfo(@FieldType(T, "items")).pointer.child;
            if (T != std.ArrayList(Element)) @compileError(mismatch);
            checkLayout(element.name, Element, element.fields);
        },
        .@"inline" => |nested| {
            if (@typeInfo(T) != .@"struct") @compileError(mismatch);
            checkLayout(nested.name, T, nested.fields);
        },
        .tagged_union => |variants| {
            if (@typeInfo(T) != .@"union" or @typeInfo(T).@"union".tag_type == null) @compileError(mismatch);
            checkLayout(variants.name, T, variants.fields);
        },
    }
}

/// The payload types of one representation, checked against their layouts.
pub fn Payloads(comptime E: type, comptime Behavior: type) type {
    return struct {
        pub const Value = E.Value;
        pub const DataSlot = struct { value: Value, writable: bool };
        pub const AccessorSlot = struct { getter: ?CellRef, setter: ?CellRef };
        pub const Slot = union(enum) { data: DataSlot, accessor: AccessorSlot };
        pub const Property = struct { key: CellRef, enumerable: bool, configurable: bool, slot: Slot };
        pub const ObjectHeader = struct {
            prototype: ?CellRef,
            extensible: bool,
            properties: std.ArrayList(Property),
        };
        pub const ErrorKind = enum { type_error };

        pub const String = struct { units: WebString };
        pub const Symbol = struct { description: ?CellRef };
        /// The limbs are normalized, and zero is positive.
        pub const BigInt = struct { positive: bool, limbs: []const Limb };
        pub const HeapNumber = struct { value: f64 };
        pub const OrdinaryObject = struct { object: ObjectHeader };
        pub const BuiltinFunction = struct {
            object: ObjectHeader,
            behavior: Behavior,
            host_data: Value,
            /// Host memory, never a managed cell. A host that stores values there roots them itself.
            host_context: ?*anyopaque,
        };
        pub const ErrorObject = struct { object: ObjectHeader, error_kind: ErrorKind };
        pub const PlatformObject = struct { object: ObjectHeader, node: dom.NodeHandle };

        pub const Payload = union(Kind) {
            string: String,
            symbol: Symbol,
            bigint: BigInt,
            heap_number: HeapNumber,
            ordinary_object: OrdinaryObject,
            builtin_function: BuiltinFunction,
            error_object: ErrorObject,
            platform_object: PlatformObject,
        };

        comptime {
            for (std.enums.values(Kind)) |kind| {
                checkLayout(@tagName(kind), @FieldType(Payload, @tagName(kind)), layout(kind));
            }
        }

        /// Returns the object header of an object kind, or null for a primitive kind.
        pub fn objectHeader(payload: *Payload) ?*ObjectHeader {
            return switch (payload.*) {
                .string, .symbol, .bigint, .heap_number => null,
                inline .ordinary_object, .builtin_function, .error_object, .platform_object => |*object| &object.object,
            };
        }

        /// Visits every cell that the payload references, as its layout describes.
        pub fn trace(payload: *const Payload, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            switch (payload.*) {
                inline else => |*fields, kind| traceFields(layout(kind), fields, context, visit),
            }
        }

        fn traceFields(comptime fields: []const Field, target: anytype, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            inline for (fields) |field| traceDescriptor(field.descriptor, &@field(target.*, field.name), context, visit);
        }

        fn traceDescriptor(comptime descriptor: Descriptor, target: anytype, context: anytype, comptime visit: fn (@TypeOf(context), CellRef) void) void {
            switch (descriptor) {
                .plain, .dom_node, .owned_units, .owned_limbs => {},
                .value => if (E.classify(target.*) == .cell) visit(context, @fromBackingInt(E.asCell(target.*))),
                .cell => visit(context, target.*),
                .optional_cell => if (target.*) |ref| visit(context, ref),
                .owned_list => |element| for (target.items) |*item| traceFields(element.fields, item, context, visit),
                .@"inline" => |nested| traceFields(nested.fields, target, context, visit),
                .tagged_union => |variants| switch (target.*) {
                    inline else => |*active, tag| traceDescriptor(variantDescriptor(variants, @tagName(tag)), active, context, visit),
                },
            }
        }

        /// Releases every resource that the payload owns, as its layout describes.
        /// `store` is the DOM store whose nodes the payload retains.
        pub fn finalize(payload: *Payload, gpa: std.mem.Allocator, store: ?*dom.Store) void {
            switch (payload.*) {
                inline else => |*fields, kind| finalizeFields(layout(kind), fields, gpa, store),
            }
        }

        fn finalizeFields(comptime fields: []const Field, target: anytype, gpa: std.mem.Allocator, store: ?*dom.Store) void {
            inline for (fields) |field| finalizeDescriptor(field.descriptor, &@field(target.*, field.name), gpa, store);
        }

        fn finalizeDescriptor(comptime descriptor: Descriptor, target: anytype, gpa: std.mem.Allocator, store: ?*dom.Store) void {
            switch (descriptor) {
                .plain, .value, .cell, .optional_cell => {},
                .dom_node => {
                    const owner = store orelse std.debug.panic("fairpane-js: a platform object outlived its DOM store", .{});
                    owner.release(target.*) catch |err| std.debug.panic("fairpane-js: releasing a platform object's node failed with {t}", .{err});
                },
                .owned_units => target.deinit(gpa),
                .owned_limbs => gpa.free(target.*),
                .owned_list => |element| {
                    for (target.items) |*item| finalizeFields(element.fields, item, gpa, store);
                    target.deinit(gpa);
                },
                .@"inline" => |nested| finalizeFields(nested.fields, target, gpa, store),
                .tagged_union => |variants| switch (target.*) {
                    inline else => |*active, tag| finalizeDescriptor(variantDescriptor(variants, @tagName(tag)), active, gpa, store),
                },
            }
        }
    };
}

fn variantDescriptor(comptime variants: *const Layout, comptime tag: []const u8) Descriptor {
    comptime {
        for (variants.fields) |variant| {
            if (std.mem.eql(u8, variant.name, tag)) return variant.descriptor;
        }
        @compileError("fairpane-js: layout " ++ variants.name ++ " does not describe variant " ++ tag);
    }
}

const frozen_catalog =
    \\string|no|no|units:owned_units
    \\symbol|no|no|description:optional_cell
    \\bigint|no|no|positive:plain,limbs:owned_limbs
    \\heap_number|no|no|value:plain
    \\ordinary_object|yes|no|object:inline(ObjectHeader)
    \\builtin_function|yes|yes|object:inline(ObjectHeader),behavior:plain,host_data:value,host_context:plain
    \\error_object|yes|no|object:inline(ObjectHeader),error_kind:plain
    \\platform_object|yes|no|object:inline(ObjectHeader),node:dom_node
    \\ObjectHeader|prototype:optional_cell,extensible:plain,properties:owned_list(Property)
    \\Property|key:cell,enumerable:plain,configurable:plain,slot:tagged_union(data:inline(DataSlot),accessor:inline(AccessorSlot))
    \\DataSlot|value:value,writable:plain
    \\AccessorSlot|getter:optional_cell,setter:optional_cell
    \\
;

test "FP-0011 case 7: kind metadata and layouts render as the frozen catalog" {
    var output: std.Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try writeCatalog(&output.writer);
    try testing.expectEqualStrings(frozen_catalog, output.written());
    try testing.expectEqual(InternalMethods.none, info(.string).internal_methods);
    try testing.expectEqual(InternalMethods.ordinary, info(.platform_object).internal_methods);
}
