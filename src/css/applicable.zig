//! The applicable declarations of one element, which are the input of the cascade (Cascade 5 section 6),
//! and the specificity that orders them (Selectors 4 section 15).
//!
//! This module imports no DOM and no selector code, so the cascade stage depends on neither.
//! `selectors.zig` produces applicable declarations, and `cascade.zig` sorts them.

const std = @import("std");
const registry = @import("registry.zig");
const values = @import("values.zig");
const PropertyKey = registry.PropertyKey;

/// Specificity (Selectors 4 section 15). Each component saturates at 65535, as section 15 permits.
pub const Specificity = struct {
    /// ID selectors.
    a: u16 = 0,
    /// Class selectors, attribute selectors, and pseudo-classes.
    b: u16 = 0,
    /// Type selectors and pseudo-elements.
    c: u16 = 0,

    pub fn order(x: Specificity, y: Specificity) std.math.Order {
        if (x.a != y.a) return std.math.order(x.a, y.a);
        if (x.b != y.b) return std.math.order(x.b, y.b);
        return std.math.order(x.c, y.c);
    }
};

/// The cascade origins of Cascade 5 section 6.2 that have input in this task.
pub const Origin = enum { user_agent, user, author };

/// The order of appearance: sheets as the caller passes them, then rules and declarations in source order.
pub const Order = struct {
    sheet: u32,
    rule: u32,
    declaration: u32,
};

/// The style rule that holds a declaration.
pub const RuleIdentity = struct {
    sheet: u32,
    rule: u32,

    pub fn eql(a: RuleIdentity, b: RuleIdentity) bool {
        return a.sheet == b.sheet and a.rule == b.rule;
    }
};

/// One declaration that applies to an element. It holds no computed value.
pub const ApplicableDeclaration = struct {
    property: PropertyKey,
    value: *const values.DeclaredValue,
    origin: Origin,
    important: bool,
    specificity: Specificity,
    order: Order,
    rule: RuleIdentity,
};
