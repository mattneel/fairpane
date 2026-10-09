//! Computed values for one element: explicit defaulting (Cascade 5 section 7.3), custom properties and
//! `var()` substitution (Values 5 Appendix A, Variables 1), and the computed value of each registered property.
//!
//! This stage reads no DOM and no selector. Its input is a cascade result, the parent's computed style,
//! the root element's computed style, and whether the element is the root.
//! Custom properties compute first, then `font-size`, then the remaining properties.
//!
//! Custom property values compute on demand: a `var()` that names an uncomputed custom property computes it,
//! and the guard stack of substitution contexts detects cycles. An explicit work stack replaces the recursion
//! of the standard's algorithms, so nesting depth is bounded only by memory.

const std = @import("std");
const parser = @import("parser.zig");
const registry = @import("registry.zig");
const values = @import("values.zig");
const cascade = @import("cascade.zig");
const substitution = @import("substitution.zig");
const Allocator = std.mem.Allocator;
const ComponentValue = parser.ComponentValue;
const PropertyId = registry.PropertyId;
const PropertyKey = registry.PropertyKey;
const CascadeResult = cascade.CascadeResult;
const ApplicableDeclaration = cascade.ApplicableDeclaration;

/// Why a property became invalid at computed-value time.
pub const InvalidReason = enum {
    /// Its substituted value contains the guaranteed-invalid value.
    guaranteed_invalid,
    /// Its substituted value does not match its grammar.
    grammar_mismatch,
    /// Its value uses a standard form outside the frozen subset.
    unsupported_value,
};

pub const PropertyDiagnostic = struct {
    property: PropertyKey,
    reason: InvalidReason,
};

/// A custom property whose computed value is not the guaranteed-invalid value.
pub const CustomEntry = struct {
    name: []const u16,
    value: []const ComponentValue,
};

/// The computed values of one element. The slices borrow the owner's arena and the stylesheets.
pub const ComputedStyle = struct {
    display: values.Display,
    color: values.Color,
    /// Pixels.
    font_size: f64,
    margin_top: values.LengthPercentageAuto,
    margin_right: values.LengthPercentageAuto,
    margin_bottom: values.LengthPercentageAuto,
    margin_left: values.LengthPercentageAuto,
    /// Sorted by code units. A custom property that is absent has the guaranteed-invalid value.
    custom: []const CustomEntry,

    /// The initial value of every property: the computed value of each registry initial text.
    pub fn initial() ComputedStyle {
        var style: ComputedStyle = undefined;
        style.custom = &.{};
        inline for (comptime std.enums.values(PropertyId)) |id| {
            style.setInitial(id);
        }
        return style;
    }

    /// The computed value of a custom property.
    pub fn customValue(style: *const ComputedStyle, name: []const u16) values.CustomValue {
        const index = findCustom(style.custom, name) orelse return .guaranteed_invalid;
        return .{ .tokens = style.custom[index].value };
    }

    /// The union of the invalidation effects of every property whose computed values differ,
    /// plus `descendants` when an inherited property differs.
    pub fn diff(a: *const ComputedStyle, b: *const ComputedStyle) registry.Effects {
        var effects: registry.Effects = .empty;
        inline for (comptime std.enums.values(PropertyId)) |id| {
            const field = @tagName(id);
            if (!std.meta.eql(@field(a, field), @field(b, field))) addEffects(&effects, registry.record(id));
        }
        if (!customEqual(a.custom, b.custom)) addEffects(&effects, &registry.custom_family);
        return effects;
    }

    fn setInitial(style: *ComputedStyle, comptime id: PropertyId) void {
        const declared = values.initialValue(id);
        switch (id) {
            .display => style.display = values.computeDisplay(declared.display, false),
            .color => style.color = values.computeColor(declared.color),
            .font_size => style.font_size = values.computeFontSize(declared.font_size, values.medium_font_size, values.medium_font_size),
            .margin_top, .margin_right, .margin_bottom, .margin_left => @field(style, @tagName(id)) =
                values.computeMargin(declared.margin, values.medium_font_size, values.medium_font_size),
        }
    }
};

fn addEffects(effects: *registry.Effects, record: *const registry.Record) void {
    effects.setUnion(record.effects());
    if (record.inherited) effects.insert(.descendants);
}

fn findCustom(entries: []const CustomEntry, name: []const u16) ?usize {
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        switch (std.mem.order(u16, entries[middle].name, name)) {
            .eq => return middle,
            .lt => low = middle + 1,
            .gt => high = middle,
        }
    }
    return null;
}

fn customEqual(a: []const CustomEntry, b: []const CustomEntry) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!std.mem.eql(u16, left.name, right.name)) return false;
        if (!componentListsEqual(left.value, right.value)) return false;
    }
    return true;
}

/// Compares two component value lists by their tokens and structure, ignoring source ranges.
pub fn componentListsEqual(a: []const ComponentValue, b: []const ComponentValue) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left.kind != right.kind or left.descendants != right.descendants) return false;
        const x = left.token;
        const y = right.token;
        if (x.kind != y.kind or x.hash_type != y.hash_type or x.delim != y.delim) return false;
        if (x.number != y.number or x.number_type != y.number_type or x.sign != y.sign) return false;
        if (x.range_start != y.range_start or x.range_end != y.range_end) return false;
        if (!std.mem.eql(u16, x.value, y.value) or !std.mem.eql(u16, x.unit, y.unit)) return false;
    }
    return true;
}

/// Computes the style of one element.
/// `arena` holds the custom property values of the result; `gpa` holds scratch state, which is freed before the return.
/// Each property that becomes invalid at computed-value time adds one entry to `diagnostics`.
/// The result borrows `cascade_result`'s declared values, the stylesheets, and `parent`'s custom values.
pub fn computeStyle(
    gpa: Allocator,
    arena: Allocator,
    cascade_result: *const CascadeResult,
    parent: ?*const ComputedStyle,
    root: ?*const ComputedStyle,
    is_root: bool,
    diagnostics: *std.ArrayList(PropertyDiagnostic),
) Allocator.Error!ComputedStyle {
    // A failure leaves the caller's diagnostics list as it was.
    const diagnostics_start = diagnostics.items.len;
    errdefer diagnostics.shrinkRetainingCapacity(diagnostics_start);
    const customs = cascade_result.customProperties();
    const memo = try gpa.alloc(Memo, customs.len);
    defer gpa.free(memo);
    @memset(memo, .not_started);
    var engine: Engine = .{
        .gpa = gpa,
        .arena = arena,
        .cascade_result = cascade_result,
        .customs = customs,
        .memo = memo,
        .parent = parent,
        .diagnostics = diagnostics,
    };
    defer engine.deinit();

    // Custom properties first.
    for (memo, 0..) |state, group| {
        if (state != .not_started) continue;
        try engine.work.append(gpa, .{ .custom = .{ .group = group } });
        _ = try engine.drive(0);
    }
    var style: ComputedStyle = undefined;
    style.custom = try engine.customEntries();

    // Then font-size, which `em` units on other properties use.
    const parent_font_size = if (is_root or parent == null) values.medium_font_size else parent.?.font_size;
    const root_font_size = if (is_root or root == null) values.medium_font_size else root.?.font_size;
    switch (try engine.decide(.font_size)) {
        .initial => style.setInitial(.font_size),
        .inherit => if (parent) |p| {
            style.font_size = p.font_size;
        } else style.setInitial(.font_size),
        .value => |declared| style.font_size = values.computeFontSize(declared.font_size, parent_font_size, root_font_size),
    }
    // On the root element, `rem` on other properties refers to the root's own computed font size.
    const rem_basis = if (is_root) style.font_size else root_font_size;

    inline for (comptime std.enums.values(PropertyId)) |id| {
        if (id != .font_size) {
            switch (try engine.decide(id)) {
                .initial => style.setInitial(id),
                .inherit => if (parent) |p| {
                    @field(style, @tagName(id)) = @field(p, @tagName(id));
                } else style.setInitial(id),
                .value => |declared| switch (id) {
                    .display => style.display = values.computeDisplay(declared.display, is_root),
                    .color => style.color = values.computeColor(declared.color),
                    .font_size => unreachable,
                    .margin_top, .margin_right, .margin_bottom, .margin_left => @field(style, @tagName(id)) =
                        values.computeMargin(declared.margin, style.font_size, rem_basis),
                },
            }
        }
    }
    // The root element's display type is always blockified, whatever its cascaded or default value.
    if (is_root) style.display = values.blockify(style.display);
    return style;
}

/// The state of one custom property that the element declares.
const Memo = union(enum) {
    not_started,
    /// Its substitution is guarded at this index of the guard stack.
    in_progress: usize,
    /// Its computed value, or null for the guaranteed-invalid value.
    done: ?[]const ComponentValue,
};

/// A guarded substitution context «"property", name».
const Guard = struct {
    group: usize,
    cyclic: bool = false,
};

/// Computing one declared custom property.
const CustomWork = struct {
    group: usize,
    /// The declaration being examined.
    cursor: usize = 0,
    rollback: cascade.Rollback = .{},
    /// The guard of the substitution that this work awaits.
    guard: ?usize = null,
};

const Work = union(enum) {
    custom: CustomWork,
    substitution: substitution.Substitution,
};

/// What a finished work item gives to the item below it.
const Finished = union(enum) {
    /// A substitution result. The tokens belong to `gpa`.
    substituted: substitution.Result,
    /// A custom property's computed value, or null for the guaranteed-invalid value.
    custom: ?[]const ComponentValue,
};

/// The outcome of the cascade and explicit defaulting for one standard property.
const Decision = union(enum) {
    initial,
    inherit,
    value: values.DeclaredValue,
};

const Engine = struct {
    gpa: Allocator,
    arena: Allocator,
    cascade_result: *const CascadeResult,
    customs: []const cascade.PropertyCascade,
    memo: []Memo,
    parent: ?*const ComputedStyle,
    diagnostics: *std.ArrayList(PropertyDiagnostic),
    guards: std.ArrayList(Guard) = .empty,
    work: std.ArrayList(Work) = .empty,

    fn deinit(e: *Engine) void {
        for (e.work.items) |*item| switch (item.*) {
            .custom => |*custom| custom.rollback.deinit(e.gpa),
            .substitution => |*s| s.deinit(e.gpa),
        };
        e.work.deinit(e.gpa);
        e.guards.deinit(e.gpa);
    }

    fn diagnose(e: *Engine, property: PropertyKey, reason: InvalidReason) Allocator.Error!void {
        try e.diagnostics.append(e.gpa, .{ .property = property, .reason = reason });
    }

    fn findGroup(e: *const Engine, name: []const u16) ?usize {
        var low: usize = 0;
        var high: usize = e.customs.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            switch (std.mem.order(u16, e.customs[middle].property.custom, name)) {
                .eq => return middle,
                .lt => low = middle + 1,
                .gt => high = middle,
            }
        }
        return null;
    }

    fn inherited(e: *const Engine, name: []const u16) ?[]const ComponentValue {
        const parent = e.parent orelse return null;
        return switch (parent.customValue(name)) {
            .guaranteed_invalid => null,
            .tokens => |tokens| tokens,
        };
    }

    /// Runs work items until the stack returns to `base` items, and returns the last finished result.
    fn drive(e: *Engine, base: usize) Allocator.Error!Finished {
        var answer: ?Finished = null;
        while (true) {
            const top = &e.work.items[e.work.items.len - 1];
            const finished: Finished = switch (top.*) {
                .substitution => |*s| blk: {
                    const given: ?substitution.Answer = if (answer) |value| switch (value) {
                        .substituted => |result| .{ .substituted = result },
                        .custom => |tokens| .{ .property = tokens },
                    } else null;
                    answer = null;
                    switch (try s.step(e.gpa, given)) {
                        .substitute => |list| {
                            try e.work.append(e.gpa, .{ .substitution = .init(list) });
                            continue;
                        },
                        .property => |name| {
                            answer = try e.resolveProperty(name);
                            continue;
                        },
                        .done => |result| break :blk .{ .substituted = result },
                    }
                },
                .custom => blk: {
                    const given = answer;
                    answer = null;
                    const value = try e.stepCustom(given) orelse continue;
                    break :blk .{ .custom = value.tokens };
                },
            };
            var item = e.work.pop().?;
            switch (item) {
                .custom => |*custom| {
                    e.memo[custom.group] = .{ .done = finished.custom };
                    custom.rollback.deinit(e.gpa);
                },
                .substitution => |*s| s.deinit(e.gpa),
            }
            if (e.work.items.len == base) return finished;
            answer = finished;
        }
    }

    /// Answers a substitution's request for a custom property value, or starts computing it.
    fn resolveProperty(e: *Engine, name: []const u16) Allocator.Error!?Finished {
        const group = e.findGroup(name) orelse return .{ .custom = e.inherited(name) };
        switch (e.memo[group]) {
            .done => |value| return .{ .custom = value },
            .in_progress => |guard| {
                // Guarding a context that is already guarded marks every context from that entry to the top as cyclic.
                for (e.guards.items[guard..]) |*entry| entry.cyclic = true;
                return .{ .custom = null };
            },
            .not_started => {
                try e.work.append(e.gpa, .{ .custom = .{ .group = group } });
                return null;
            },
        }
    }

    const CustomValue = struct { tokens: ?[]const ComponentValue };

    /// Advances the top custom work item. Returns its value when it finishes, or null when it pushed a substitution.
    fn stepCustom(e: *Engine, answer: ?Finished) Allocator.Error!?CustomValue {
        const work = &e.work.items[e.work.items.len - 1].custom;
        const group = work.group;
        const name = e.customs[group].property.custom;
        const declarations = e.customs[group].declarations;
        if (answer) |finished| {
            const guard = work.guard.?;
            const cyclic = e.guards.items[guard].cyclic;
            std.debug.assert(e.guards.items.len == guard + 1);
            _ = e.guards.pop();
            work.guard = null;
            e.memo[group] = .not_started;
            const result = finished.substituted;
            if (cyclic) {
                // A cyclic custom property computes to the guaranteed-invalid value.
                if (result == .tokens) e.gpa.free(result.tokens);
                try e.diagnose(.{ .custom = name }, .guaranteed_invalid);
                return .{ .tokens = null };
            }
            switch (result) {
                .invalid => |reason| {
                    try e.diagnose(.{ .custom = name }, if (reason == .unsupported) .unsupported_value else .guaranteed_invalid);
                    return .{ .tokens = null };
                },
                .tokens => |tokens| {
                    defer e.gpa.free(tokens);
                    // A value that is one CSS-wide keyword after substitution acts as that keyword.
                    if (values.cssWideKeyword(tokens)) |keyword| {
                        if (try e.customKeyword(work, declarations[work.cursor], keyword, name)) |value| return value;
                        work.cursor += 1;
                    } else if (!substitution.isDeclarationValue(tokens)) {
                        try e.diagnose(.{ .custom = name }, .grammar_mismatch);
                        return .{ .tokens = null };
                    } else {
                        return .{ .tokens = try e.arena.dupe(ComponentValue, tokens) };
                    }
                },
            }
        }
        while (work.cursor < declarations.len) : (work.cursor += 1) {
            const declaration = declarations[work.cursor];
            if (work.rollback.excludes(declaration)) continue;
            switch (declaration.value.*) {
                .keyword => |keyword| {
                    if (try e.customKeyword(work, declaration, keyword, name)) |value| return value;
                },
                .custom => |custom| {
                    if (!substitution.containsVar(custom.tokens)) return .{ .tokens = custom.tokens };
                    // Replace substitution functions in the property, with «"property", name» as the context.
                    const guard = e.guards.items.len;
                    try e.guards.append(e.gpa, .{ .group = group });
                    work.guard = guard;
                    e.memo[group] = .{ .in_progress = guard };
                    e.work.append(e.gpa, .{ .substitution = .init(custom.tokens) }) catch |err| {
                        _ = e.guards.pop();
                        work.guard = null;
                        e.memo[group] = .not_started;
                        return err;
                    };
                    return null;
                },
                else => unreachable,
            }
        }
        // No cascaded value: a custom property inherits.
        return .{ .tokens = e.inherited(name) };
    }

    /// Applies a CSS-wide keyword to a custom property. Returns the value, or null when the next declaration decides.
    fn customKeyword(
        e: *Engine,
        work: *CustomWork,
        declaration: ApplicableDeclaration,
        keyword: values.CssWideKeyword,
        name: []const u16,
    ) Allocator.Error!?CustomValue {
        switch (keyword) {
            // The initial value of a custom property is the guaranteed-invalid value.
            .initial => return .{ .tokens = null },
            // Custom properties are inherited, so `unset` acts as `inherit`.
            .inherit, .unset => return .{ .tokens = e.inherited(name) },
            .revert, .revert_layer, .revert_rule => switch (try work.rollback.apply(e.gpa, declaration, keyword)) {
                .unset => return .{ .tokens = e.inherited(name) },
                .next_declaration => return null,
            },
        }
    }

    /// Substitutes `list` without a substitution context.
    fn substitute(e: *Engine, list: []const ComponentValue) Allocator.Error!substitution.Result {
        const base = e.work.items.len;
        try e.work.append(e.gpa, .{ .substitution = .init(list) });
        return (try e.drive(base)).substituted;
    }

    /// The cascade and explicit defaulting for one standard property, with property replacement for `var()`.
    fn decide(e: *Engine, id: PropertyId) Allocator.Error!Decision {
        const property: PropertyKey = .{ .standard = id };
        const inherits = registry.record(id).inherited;
        const unset: Decision = if (inherits) .inherit else .initial;
        const declarations = e.cascade_result.get(property);
        var rollback: cascade.Rollback = .{};
        defer rollback.deinit(e.gpa);
        for (declarations) |declaration| {
            if (rollback.excludes(declaration)) continue;
            var declared = declaration.value.*;
            if (declared == .pending) {
                switch (try e.substitute(declared.pending)) {
                    // Invalid at computed-value time: the property computes as if its value were `unset`.
                    .invalid => |reason| {
                        try e.diagnose(property, if (reason == .unsupported) .unsupported_value else .guaranteed_invalid);
                        return unset;
                    },
                    .tokens => |tokens| {
                        defer e.gpa.free(tokens);
                        // Parse the result according to the property's grammar.
                        switch (parser.parseGrammar(tokens, values.StandardGrammar{ .id = id })) {
                            .invalid => {
                                try e.diagnose(property, .grammar_mismatch);
                                return unset;
                            },
                            .unsupported => {
                                try e.diagnose(property, .unsupported_value);
                                return unset;
                            },
                            .value => |value| declared = value,
                        }
                    },
                }
            }
            switch (declared) {
                .keyword => |keyword| switch (keyword) {
                    .initial => return .initial,
                    .inherit => return .inherit,
                    .unset => return unset,
                    .revert, .revert_layer, .revert_rule => switch (try rollback.apply(e.gpa, declaration, keyword)) {
                        .unset => return unset,
                        .next_declaration => continue,
                    },
                },
                .pending, .custom => unreachable,
                else => return .{ .value = declared },
            }
        }
        // No cascaded value: inherited properties inherit, and others take their initial value.
        return unset;
    }

    /// The element's custom property values: its declared ones, then the inherited rest, sorted by name.
    fn customEntries(e: *Engine) Allocator.Error![]const CustomEntry {
        const inherited_entries: []const CustomEntry = if (e.parent) |p| p.custom else &.{};
        if (e.customs.len == 0) return inherited_entries;
        var count: usize = 0;
        for (e.memo) |state| {
            if (doneValue(state) != null) count += 1;
        }
        for (inherited_entries) |entry| {
            if (e.findGroup(entry.name) == null) count += 1;
        }
        const entries = try e.arena.alloc(CustomEntry, count);
        var written: usize = 0;
        var inherited_index: usize = 0;
        for (e.customs, e.memo) |group, state| {
            const name = group.property.custom;
            while (inherited_index < inherited_entries.len and std.mem.order(u16, inherited_entries[inherited_index].name, name) == .lt) {
                entries[written] = inherited_entries[inherited_index];
                written += 1;
                inherited_index += 1;
            }
            if (inherited_index < inherited_entries.len and std.mem.eql(u16, inherited_entries[inherited_index].name, name)) inherited_index += 1;
            if (doneValue(state)) |tokens| {
                entries[written] = .{ .name = name, .value = tokens };
                written += 1;
            }
        }
        for (inherited_entries[inherited_index..]) |entry| {
            entries[written] = entry;
            written += 1;
        }
        std.debug.assert(written == count);
        return entries;
    }

    /// Every declared custom property is done when the entries are built.
    fn doneValue(state: Memo) ?[]const ComponentValue {
        return switch (state) {
            .done => |value| value,
            .not_started, .in_progress => unreachable,
        };
    }
};
