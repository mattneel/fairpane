//! CSS Cascading and Inheritance Level 5, section 6: the cascade sort for the origins of 6.2 and the importance of 6.3,
//! and the rollback of explicit defaulting from section 7.3.
//!
//! This stage reads no DOM and no selector: its input is the applicable declarations of one element.
//! Encapsulation contexts, element-attached styles, cascade layers, and animation and transition origins have no input,
//! so every declaration of an origin sits in that origin's implicit final layer.

const std = @import("std");
const registry = @import("registry.zig");
const values = @import("values.zig");
const selectors = @import("selectors.zig");
const Allocator = std.mem.Allocator;
const PropertyKey = registry.PropertyKey;

/// The cascade origins of section 6.2 that have input in this task.
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
    specificity: selectors.Specificity,
    order: Order,
    rule: RuleIdentity,
};

/// The precedence of origin and importance (section 6.2); a larger value wins.
/// From highest: important user agent, important user, important author, normal author, normal user, normal user agent.
pub fn originPrecedence(origin: Origin, important: bool) u3 {
    if (important) return switch (origin) {
        .user_agent => 5,
        .user => 4,
        .author => 3,
    };
    return switch (origin) {
        .author => 2,
        .user => 1,
        .user_agent => 0,
    };
}

/// Whether `a` sorts before `b`: by property, then in descending precedence of origin and importance,
/// specificity, and order of appearance.
fn sortsBefore(_: void, a: ApplicableDeclaration, b: ApplicableDeclaration) bool {
    switch (a.property.order(b.property)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    const a_rank = originPrecedence(a.origin, a.important);
    const b_rank = originPrecedence(b.origin, b.important);
    if (a_rank != b_rank) return a_rank > b_rank;
    switch (a.specificity.order(b.specificity)) {
        .gt => return true,
        .lt => return false,
        .eq => {},
    }
    if (a.order.sheet != b.order.sheet) return a.order.sheet > b.order.sheet;
    if (a.order.rule != b.order.rule) return a.order.rule > b.order.rule;
    return a.order.declaration > b.order.declaration;
}

/// One property's declarations in descending precedence. The first is the cascaded value unless explicit defaulting rolls it back.
pub const PropertyCascade = struct {
    property: PropertyKey,
    declarations: []const ApplicableDeclaration,
};

pub const CascadeResult = struct {
    /// Sorted by property: standard properties in table order, then custom properties by code units.
    entries: []const PropertyCascade,
    storage: []ApplicableDeclaration,

    pub fn deinit(result: *CascadeResult, gpa: Allocator) void {
        gpa.free(result.entries);
        gpa.free(result.storage);
        result.* = undefined;
    }

    /// The sorted declarations of `property`, or an empty list.
    pub fn get(result: *const CascadeResult, property: PropertyKey) []const ApplicableDeclaration {
        const index = result.find(property) orelse return &.{};
        return result.entries[index].declarations;
    }

    /// The index of `property` in `entries`.
    pub fn find(result: *const CascadeResult, property: PropertyKey) ?usize {
        var low: usize = 0;
        var high: usize = result.entries.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            switch (result.entries[middle].property.order(property)) {
                .eq => return middle,
                .lt => low = middle + 1,
                .gt => high = middle,
            }
        }
        return null;
    }

    /// The entries of custom properties, sorted by code units.
    pub fn customProperties(result: *const CascadeResult) []const PropertyCascade {
        var start = result.entries.len;
        while (start > 0 and result.entries[start - 1].property == .custom) start -= 1;
        return result.entries[start..];
    }
};

/// Sorts each property's declarations in descending precedence (section 6.1).
/// The result keeps every declaration, so explicit defaulting can roll back.
pub fn cascade(gpa: Allocator, declarations: []const ApplicableDeclaration) Allocator.Error!CascadeResult {
    const storage = try gpa.dupe(ApplicableDeclaration, declarations);
    errdefer gpa.free(storage);
    std.mem.sort(ApplicableDeclaration, storage, {}, sortsBefore);
    var groups: usize = 0;
    for (storage, 0..) |declaration, index| {
        if (index == 0 or !storage[index - 1].property.eql(declaration.property)) groups += 1;
    }
    const entries = try gpa.alloc(PropertyCascade, groups);
    var group: usize = 0;
    var start: usize = 0;
    for (storage, 0..) |declaration, index| {
        const last = index + 1 == storage.len or !storage[index + 1].property.eql(declaration.property);
        if (!last) continue;
        entries[group] = .{ .property = declaration.property, .declarations = storage[start .. index + 1] };
        group += 1;
        start = index + 1;
    }
    return .{ .entries = entries, .storage = storage };
}

/// The rollback state of explicit defaulting for one property (section 7.3).
/// After a rollback, the next declaration that the state does not exclude becomes the cascaded value.
pub const Rollback = struct {
    authors_excluded: bool = false,
    users_excluded: bool = false,
    /// The style rules that `revert-rule` discarded.
    rules: std.ArrayList(RuleIdentity) = .empty,

    pub fn deinit(rollback: *Rollback, gpa: Allocator) void {
        rollback.rules.deinit(gpa);
        rollback.* = undefined;
    }

    pub fn excludes(rollback: *const Rollback, declaration: ApplicableDeclaration) bool {
        switch (declaration.origin) {
            .author => if (rollback.authors_excluded) return true,
            .user => if (rollback.users_excluded) return true,
            .user_agent => {},
        }
        for (rollback.rules.items) |rule| {
            if (rule.eql(declaration.rule)) return true;
        }
        return false;
    }

    pub const Effect = enum {
        /// The next declaration that is not excluded becomes the cascaded value.
        next_declaration,
        /// The keyword acts as `unset`.
        unset,
    };

    /// Applies `revert`, `revert-layer`, or `revert-rule` from the winning declaration `declaration`.
    pub fn apply(rollback: *Rollback, gpa: Allocator, declaration: ApplicableDeclaration, keyword: values.CssWideKeyword) Allocator.Error!Effect {
        switch (keyword) {
            // `revert-layer` acts as `revert`, because every declaration of an origin sits in the implicit final layer.
            .revert, .revert_layer => switch (declaration.origin) {
                // From an author declaration: discard every author declaration.
                .author => rollback.authors_excluded = true,
                // From a user declaration: discard every author and user declaration.
                .user => {
                    rollback.authors_excluded = true;
                    rollback.users_excluded = true;
                },
                // From a user-agent declaration: act as `unset`.
                .user_agent => return .unset,
            },
            // `revert-rule` discards every declaration of the same style rule.
            .revert_rule => try rollback.rules.append(gpa, declaration.rule),
            .initial, .inherit, .unset => unreachable,
        }
        return .next_declaration;
    }
};
