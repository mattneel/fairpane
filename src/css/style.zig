//! Style resolution for one document: selector matching, the cascade, and computed values for every element.
//!
//! The stages stay separate. For each element, `resolve` runs `selectors.matchRules`, then `cascade.cascade`,
//! and then `compute.computeStyle`, which receives nothing from the DOM or the selectors.
//! Resolution always recomputes every element; task `FP-0074` owns incremental invalidation.

const std = @import("std");
const dom = @import("../dom.zig");
const selectors = @import("selectors.zig");
const cascade = @import("cascade.zig");
const compute = @import("compute.zig");
const registry = @import("registry.zig");
const stylesheet = @import("stylesheet.zig");
const Allocator = std.mem.Allocator;
const NodeHandle = dom.NodeHandle;

pub const ComputedStyle = compute.ComputedStyle;
pub const InvalidReason = compute.InvalidReason;

/// A property that became invalid at computed-value time on one element.
pub const StyleDiagnostic = struct {
    element: NodeHandle,
    property: registry.PropertyKey,
    reason: InvalidReason,
};

pub const ResolveError = Allocator.Error || dom.LookupError || error{ NotADocument, NotAnElement };
pub const StyleError = dom.LookupError || error{NotStyled};

/// The computed styles of the elements of one document.
/// The map borrows the stylesheets' token strings and the store, which must outlive it.
pub const StyleMap = struct {
    arena: std.heap.ArenaAllocator,
    store: *dom.Store,
    /// Each element's index in `styles`.
    indexes: std.AutoHashMapUnmanaged(NodeHandle, usize),
    styles: []const ComputedStyle,
    /// Each property that became invalid at computed-value time, in tree order.
    diagnostics: []const StyleDiagnostic,

    pub fn deinit(map: *StyleMap) void {
        map.arena.deinit();
        map.* = undefined;
    }

    /// The computed style of an element in the document's tree. Any other node returns `error.NotStyled`,
    /// because elements that are not connected have no values (Cascade 4).
    pub fn get(map: *const StyleMap, element: NodeHandle) error{NotStyled}!*const ComputedStyle {
        const index = map.indexes.get(element) orelse return error.NotStyled;
        return &map.styles[index];
    }

    /// A text node's style: the style that defaulting gives it (Cascade 5 section 1.1). Inherited properties take
    /// the parent element's computed values, and every other property takes its initial value, with no root
    /// blockification. A text node outside the document's tree returns `error.NotStyled`.
    /// The result borrows the map's custom values.
    pub fn textStyle(map: *const StyleMap, text: NodeHandle) StyleError!ComputedStyle {
        if (try map.store.nodeKind(text) != .text) return error.NotStyled;
        const parent = try map.store.parentNode(text) orelse return error.NotStyled;
        const parent_style = map.get(parent) catch return error.NotStyled;
        return ComputedStyle.defaulted(parent_style);
    }
};

/// Resolves the style of the document element and each of its descendant elements, in tree order.
pub fn resolve(
    gpa: Allocator,
    store: *dom.Store,
    document: NodeHandle,
    sheets: []const *const stylesheet.Stylesheet,
) ResolveError!StyleMap {
    if (try store.nodeKind(document) != .document) return error.NotADocument;
    var map: StyleMap = .{ .arena = .init(gpa), .store = store, .indexes = .empty, .styles = &.{}, .diagnostics = &.{} };
    errdefer map.arena.deinit();
    const arena = map.arena.allocator();

    var styles: std.ArrayList(ComputedStyle) = .empty;
    defer styles.deinit(gpa);
    var diagnostics: std.ArrayList(StyleDiagnostic) = .empty;
    defer diagnostics.deinit(gpa);
    var element_diagnostics: std.ArrayList(compute.PropertyDiagnostic) = .empty;
    defer element_diagnostics.deinit(gpa);
    var matcher: selectors.Matcher = .init(gpa, store);
    defer matcher.deinit();

    // The explicit traversal stack: each entry is an element and the index of its parent's style.
    const Entry = struct { element: NodeHandle, parent: ?usize };
    var stack: std.ArrayList(Entry) = .empty;
    defer stack.deinit(gpa);
    var child = try store.firstChild(document);
    while (child) |node| : (child = try store.nextSibling(node)) {
        if (try store.nodeKind(node) == .element) {
            try stack.append(gpa, .{ .element = node, .parent = null });
            break;
        }
    }
    while (stack.pop()) |entry| {
        const applicable = try selectors.matchRulesWith(gpa, &matcher, entry.element, sheets);
        defer gpa.free(applicable);
        var cascaded = try cascade.cascade(gpa, applicable);
        defer cascaded.deinit(gpa);
        try styles.ensureUnusedCapacity(gpa, 1);
        const parent: ?*const ComputedStyle = if (entry.parent) |index| &styles.items[index] else null;
        const root: ?*const ComputedStyle = if (styles.items.len != 0) &styles.items[0] else null;
        element_diagnostics.clearRetainingCapacity();
        const style = try compute.computeStyle(gpa, arena, &cascaded, parent, root, entry.parent == null, &element_diagnostics);
        const index = styles.items.len;
        styles.appendAssumeCapacity(style);
        try map.indexes.put(arena, entry.element, index);
        for (element_diagnostics.items) |diagnostic| {
            try diagnostics.append(gpa, .{ .element = entry.element, .property = diagnostic.property, .reason = diagnostic.reason });
        }
        // Push the element children in reverse, so they pop in tree order.
        var last = try store.lastChild(entry.element);
        while (last) |node| : (last = try store.previousSibling(node)) {
            if (try store.nodeKind(node) == .element) try stack.append(gpa, .{ .element = node, .parent = index });
        }
    }
    map.styles = try arena.dupe(ComputedStyle, styles.items);
    map.diagnostics = try arena.dupe(StyleDiagnostic, diagnostics.items);
    return map;
}
