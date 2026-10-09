//! The property registry: one record per standard property, built from `properties.zig` at compile time,
//! and the record of the custom property family.
//! Each record states the initial value text, inheritance, the computed-value representation,
//! and the invalidation effects of a computed-value change.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const web_string = @import("../web_string.zig");
const View = web_string.View;

/// The computed-value representation of a property.
pub const Representation = enum {
    /// `values.Display`.
    display,
    /// `values.Color`.
    color,
    /// An `f64` number of pixels.
    pixels,
    /// `values.LengthPercentageAuto`.
    length_percentage_auto,
    /// `values.CustomValue`.
    custom_value,
};

/// What a change of a computed value can affect.
pub const Invalidation = enum {
    /// A change can alter box generation.
    box_tree,
    /// A change can alter geometry.
    layout,
    /// A change can alter painted output.
    paint,
    /// Other values on the same element can depend on this value,
    /// such as `em` units on `font-size`, `currentcolor` on `color`, and `var()` on a custom property.
    element_dependents,
    /// On the root element, `rem` units on every element depend on this value.
    root_dependents,
    /// A difference in an inherited property reaches the descendants. `ComputedStyle.diff` adds it.
    descendants,
};

pub const Effects = std.EnumSet(Invalidation);

/// A record has exactly these fields.
pub const Record = struct {
    name: []const u8,
    spec: []const u8,
    initial: []const u8,
    inherited: bool,
    computed: Representation,
    invalidation: []const Invalidation,

    pub fn effects(entry: *const Record) Effects {
        var set: Effects = .empty;
        for (entry.invalidation) |effect| set.insert(effect);
        return set;
    }
};

pub const ValidationError = error{ DuplicateProperty, NonCanonicalName, MissingInvalidation };

/// Rejects a table with a duplicate name, a name that is not lowercase ASCII, or a record without an invalidation effect.
pub fn validate(table: []const Record) ValidationError!void {
    for (table, 0..) |entry, index| {
        if (entry.name.len == 0) return error.NonCanonicalName;
        for (entry.name) |byte| {
            const canonical = (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '-';
            if (!canonical) return error.NonCanonicalName;
        }
        if (entry.invalidation.len == 0) return error.MissingInvalidation;
        for (table[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.name, entry.name)) return error.DuplicateProperty;
        }
    }
}

/// The committed table of standard properties.
pub const records: []const Record = &@import("properties.zig").records;

comptime {
    @setEvalBranchQuota(100_000);
    validate(records) catch |err| @compileError("properties.zig: " ++ @errorName(err));
}

/// The standard properties, in table order. Each tag is the property name with "-" replaced by "_".
pub const PropertyId = blk: {
    var names: [records.len][]const u8 = undefined;
    for (records, &names) |entry, *name| {
        var buffer: [entry.name.len]u8 = undefined;
        for (entry.name, &buffer) |byte, *out| out.* = if (byte == '-') '_' else byte;
        const final = buffer;
        name.* = &final;
    }
    const Tag = std.math.IntFittingRange(0, records.len - 1);
    break :blk @Enum(Tag, .exhaustive, &names, &std.simd.iota(Tag, records.len));
};

pub const property_count = records.len;

pub fn record(id: PropertyId) *const Record {
    return &records[@backingInt(id)];
}

/// The custom property family `--*` (CSS Custom Properties for Cascading Variables Level 1, section 2).
pub const custom_family: Record = .{
    .name = "--*",
    .spec = "CSS Custom Properties for Cascading Variables Level 1, section 2",
    .initial = "guaranteed-invalid",
    .inherited = true,
    .computed = .custom_value,
    .invalidation = &.{.element_dependents},
};

/// A standard property, or a custom property with the exact code units of its name.
pub const PropertyKey = union(enum) {
    standard: PropertyId,
    custom: []const u16,

    pub fn record(key: PropertyKey) *const Record {
        return switch (key) {
            .standard => |id| &records[@backingInt(id)],
            .custom => &custom_family,
        };
    }

    /// Custom property names compare by identical code units.
    pub fn eql(a: PropertyKey, b: PropertyKey) bool {
        return order(a, b) == .eq;
    }

    /// Standard properties in table order, then custom properties by code units.
    pub fn order(a: PropertyKey, b: PropertyKey) std.math.Order {
        return switch (a) {
            .standard => |left| switch (b) {
                .standard => |right| std.math.order(@backingInt(left), @backingInt(right)),
                .custom => .lt,
            },
            .custom => |left| switch (b) {
                .standard => .gt,
                .custom => |right| std.mem.order(u16, left, right),
            },
        };
    }
};

/// Whether `name` is a custom property name: two hyphen-minus characters and at least one more code point.
/// The name `--` is reserved (Variables section 2).
pub fn isCustomPropertyName(name: []const u16) bool {
    return name.len > 2 and name[0] == '-' and name[1] == '-';
}

/// Matches standard names ASCII case-insensitively, and returns a custom key with the exact code units
/// of a custom property name. The key borrows `name`.
pub fn lookup(name: View) ?PropertyKey {
    if (isCustomPropertyName(name.units)) return .{ .custom = name.units };
    inline for (records, 0..) |candidate, index| {
        if (tokenizer.asciiCaseInsensitiveEql(name.units, candidate.name)) return .{ .standard = @fromBackingInt(@intCast(index)) };
    }
    return null;
}
