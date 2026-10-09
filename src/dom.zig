//! The DOM node store: node identity, node tree links, tree mutation, and trace roots.
//!
//! A store owns every node of one engine.
//! Each node has a generational handle from `handles.zig`, and each store has its own owner identity.
//! A handle from another store returns `error.WrongOwner`, and a handle to a freed node returns `error.StaleHandle`.
//!
//! The store implements these algorithms of the DOM Standard, <https://dom.spec.whatwg.org/>, Living Standard of 5 October 2026:
//! "ensure pre-insert validity", "pre-insert", "insert", "append", "replace", "pre-remove", and "remove" from section 4.2.3,
//! and "adopt" from section 4.5.
//! A comment beside each validity check names the step that it implements.
//! A validity failure returns `error.HierarchyRequest` or `error.NotFound` and changes nothing.
//!
//! Tree mutation only follows and rewrites links, so it never allocates and cannot fail for lack of memory.
//! Node creation copies its strings and reserves its table slot before it changes the store.
//! An allocation failure therefore leaves the store unchanged.
//!
//! Elements have attribute lists, as far as selectors need them, from section 4.9:
//! "get an attribute by namespace and local name", "set an attribute value",
//! "remove an attribute by namespace and local name", the ID attribute change steps, and the classes of `classList`.
//! An attribute has a namespace, a local name, and a value; attribute namespace prefixes do not exist yet.
//! Setting an attribute copies its strings and reserves list capacity before it changes the store,
//! so an allocation failure leaves the store unchanged.
//!
//! Every document of a store is an XML document in no-quirks mode,
//! because section 4.5 makes `xml` and `no-quirks` the defaults and the store creates no other kind.
//!
//! No shadow root, template contents, attribute node, live range, node iterator, mutation observer, or custom element exists yet.
//! A host-including inclusive ancestor is therefore an inclusive ancestor.
//! The insertion, removing, adopting, and attribute change steps have no effect beyond those above, and no mutation record is queued.
//!
//! Every document is a trace root, and so is every node that the host retains.
//! A root keeps every node of its tree alive, because script can reach any node of a tree through parent and child links.
//! `sweep` frees each tree that no root reaches.

const std = @import("std");
const builtin = @import("builtin");
const handles = @import("handles.zig");
const web_string = @import("web_string.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;
const View = web_string.View;
const WebString = web_string.WebString;

/// Test-only instrumentation, compiled only in test builds.
/// `class_token_comparisons` counts each comparison of two class tokens, which case 53 of FP-0014 bounds.
pub const test_counters = if (builtin.is_test) struct {
    pub var class_token_comparisons: usize = 0;
} else struct {};

/// Counts one class-token comparison in test builds.
fn countClassTokenComparison() void {
    if (builtin.is_test) test_counters.class_token_comparisons += 1;
}

/// The node types that a store holds.
pub const Kind = enum {
    document,
    document_fragment,
    document_type,
    element,
    text,
    comment,
    processing_instruction,
};

const Element = struct {
    /// Null for an element in no namespace.
    namespace: ?WebString,
    local_name: WebString,
    /// The attribute list in order. The store owns every string.
    attributes: std.ArrayList(Attribute),
};

const Attribute = struct {
    /// Null for an attribute in no namespace.
    namespace: ?WebString,
    local_name: WebString,
    value: WebString,

    fn deinit(attribute: *Attribute, gpa: Allocator) void {
        if (attribute.namespace) |*namespace| namespace.deinit(gpa);
        attribute.local_name.deinit(gpa);
        attribute.value.deinit(gpa);
    }

    fn view(attribute: *const Attribute) AttributeView {
        return .{
            .namespace = if (attribute.namespace) |namespace| namespace.view() else null,
            .local_name = attribute.local_name.view(),
            .value = attribute.value.view(),
        };
    }

    /// Whether the attribute has `namespace` and `local_name`, where `namespace` is already null for no namespace.
    fn named(attribute: *const Attribute, namespace: ?View, local_name: View) bool {
        if (!attribute.local_name.view().eql(local_name)) return false;
        const own = attribute.namespace orelse return namespace == null;
        const wanted = namespace orelse return false;
        return own.view().eql(wanted);
    }
};

/// One attribute of an element. The views stay valid until the attribute changes or the element is freed.
pub const AttributeView = struct {
    namespace: ?View,
    local_name: View,
    value: View,
};

/// The data that depends on the node type. The store owns every string.
const Payload = union(Kind) {
    document,
    document_fragment,
    document_type,
    element: Element,
    text: WebString,
    comment: WebString,
    processing_instruction: WebString,
};

const NodeRecord = struct {
    payload: Payload,
    /// The node document. A document is its own node document.
    document: NodeHandle,
    parent: ?NodeHandle,
    first_child: ?NodeHandle,
    last_child: ?NodeHandle,
    previous_sibling: ?NodeHandle,
    next_sibling: ?NodeHandle,
    /// The number of `retain` calls that no `release` has matched.
    retains: usize,
    /// True only while `sweep` runs.
    marked: bool,
};

const NodeTable = handles.Table(NodeRecord, .{});

/// A checked node identity. It contains no pointer.
pub const NodeHandle = NodeTable.Handle;

/// The views stay valid until the element is freed.
pub const ElementName = struct {
    namespace: ?View,
    local_name: View,
};

/// `IdentifiersExhausted` reports that the process-wide owner identity sequence ran out.
pub const InitError = error{IdentifiersExhausted};
pub const LookupError = handles.LookupError;
/// `HandleSpaceExhausted` reports that the node table ran out of handles.
pub const CreateDocumentError = error{ OutOfMemory, HandleSpaceExhausted };
/// `NotADocument` reports a `document` argument that is not a document node.
pub const CreateError = LookupError || CreateDocumentError || error{NotADocument};
/// `HierarchyRequest` is the standard's "HierarchyRequestError", and `NotFound` is its "NotFoundError".
pub const MutationError = LookupError || ValidityError;
/// `NotSupported` is the "NotSupportedError" that `adoptNode()` throws for a document.
pub const AdoptError = LookupError || error{ NotADocument, NotSupported };
/// `NotRetained` reports a `release` without a matching `retain`.
pub const ReleaseError = LookupError || error{NotRetained};
/// `NotAnElement` reports a node argument that is not an element.
pub const AttributeError = LookupError || error{NotAnElement};
pub const SetAttributeError = AttributeError || error{OutOfMemory};

const ValidityError = error{ HierarchyRequest, NotFound };

/// Compares two optional handles by owner, index, and generation.
fn sameNode(a: ?NodeHandle, b: ?NodeHandle) bool {
    const left = a orelse return b == null;
    const right = b orelse return false;
    return std.meta.eql(left, right);
}

fn detachedRecord(payload: Payload, document: NodeHandle) NodeRecord {
    return .{
        .payload = payload,
        .document = document,
        .parent = null,
        .first_child = null,
        .last_child = null,
        .previous_sibling = null,
        .next_sibling = null,
        .retains = 0,
        .marked = false,
    };
}

fn freePayload(gpa: Allocator, payload: *Payload) void {
    switch (payload.*) {
        .document, .document_fragment, .document_type => {},
        .element => |*element| {
            if (element.namespace) |*namespace| namespace.deinit(gpa);
            element.local_name.deinit(gpa);
            for (element.attributes.items) |*attribute| attribute.deinit(gpa);
            element.attributes.deinit(gpa);
        },
        .text, .comment, .processing_instruction => |*string| string.deinit(gpa),
    }
}

fn isRoot(record: *const NodeRecord) bool {
    return record.payload == .document or record.retains != 0;
}

/// A single-thread store of DOM nodes.
pub const Store = struct {
    gpa: Allocator,
    nodes: NodeTable,

    /// Issues a fresh owner identity for the store's handles and allocates nothing.
    /// `gpa` must outlive the store.
    pub fn init(gpa: Allocator) InitError!Store {
        const owner = handles.issueEngineOwnerId() catch return error.IdentifiersExhausted;
        return .{ .gpa = gpa, .nodes = .init(owner) };
    }

    /// Frees every node, including documents, retained nodes, and detached subtrees.
    pub fn deinit(store: *Store) void {
        var entries = store.nodes.iterator();
        while (entries.next()) |entry| freePayload(store.gpa, &entry.value.payload);
        store.nodes.deinit(store.gpa);
        store.* = undefined;
    }

    /// Returns the number of live nodes.
    pub fn nodeCount(store: *const Store) usize {
        return store.nodes.count();
    }

    pub fn createDocument(store: *Store) CreateDocumentError!NodeHandle {
        // A document is its own node document, so its record names the handle that the insertion issues.
        const node = try store.nodes.insert(store.gpa, detachedRecord(.document, undefined));
        store.at(node).document = node;
        return node;
    }

    pub fn createDocumentFragment(store: *Store, document: NodeHandle) CreateError!NodeHandle {
        try store.requireDocument(document);
        return store.nodes.insert(store.gpa, detachedRecord(.document_fragment, document));
    }

    pub fn createDocumentType(store: *Store, document: NodeHandle) CreateError!NodeHandle {
        try store.requireDocument(document);
        return store.nodes.insert(store.gpa, detachedRecord(.document_type, document));
    }

    /// Copies `namespace` and `local_name` exactly. A null `namespace` means no namespace.
    pub fn createElement(store: *Store, document: NodeHandle, namespace: ?View, local_name: View) CreateError!NodeHandle {
        try store.requireDocument(document);
        var namespace_copy: ?WebString = null;
        if (namespace) |name| namespace_copy = try WebString.fromCodeUnits(store.gpa, name.units);
        errdefer if (namespace_copy) |*copy| copy.deinit(store.gpa);
        var name_copy = try WebString.fromCodeUnits(store.gpa, local_name.units);
        errdefer name_copy.deinit(store.gpa);
        const element: Element = .{ .namespace = namespace_copy, .local_name = name_copy, .attributes = .empty };
        return store.nodes.insert(store.gpa, detachedRecord(.{ .element = element }, document));
    }

    /// Copies the code units of `data` exactly, including unpaired surrogates.
    pub fn createText(store: *Store, document: NodeHandle, data: View) CreateError!NodeHandle {
        return store.createCharacterData(document, .text, data);
    }

    pub fn createComment(store: *Store, document: NodeHandle, data: View) CreateError!NodeHandle {
        return store.createCharacterData(document, .comment, data);
    }

    pub fn createProcessingInstruction(store: *Store, document: NodeHandle, data: View) CreateError!NodeHandle {
        return store.createCharacterData(document, .processing_instruction, data);
    }

    pub fn nodeKind(store: *Store, node: NodeHandle) LookupError!Kind {
        return std.meta.activeTag((try store.nodes.getPtr(node)).payload);
    }

    pub fn nodeDocument(store: *Store, node: NodeHandle) LookupError!NodeHandle {
        return (try store.nodes.getPtr(node)).document;
    }

    pub fn parentNode(store: *Store, node: NodeHandle) LookupError!?NodeHandle {
        return (try store.nodes.getPtr(node)).parent;
    }

    pub fn firstChild(store: *Store, node: NodeHandle) LookupError!?NodeHandle {
        return (try store.nodes.getPtr(node)).first_child;
    }

    pub fn lastChild(store: *Store, node: NodeHandle) LookupError!?NodeHandle {
        return (try store.nodes.getPtr(node)).last_child;
    }

    pub fn previousSibling(store: *Store, node: NodeHandle) LookupError!?NodeHandle {
        return (try store.nodes.getPtr(node)).previous_sibling;
    }

    pub fn nextSibling(store: *Store, node: NodeHandle) LookupError!?NodeHandle {
        return (try store.nodes.getPtr(node)).next_sibling;
    }

    /// Returns the data of a text, comment, or processing-instruction node, or null for another node.
    /// The view stays valid until the node is freed.
    pub fn characterData(store: *Store, node: NodeHandle) LookupError!?View {
        return switch ((try store.nodes.getPtr(node)).payload) {
            .text, .comment, .processing_instruction => |string| string.view(),
            .document, .document_fragment, .document_type, .element => null,
        };
    }

    /// Returns the namespace and local name of an element, or null for another node.
    pub fn elementName(store: *Store, node: NodeHandle) LookupError!?ElementName {
        return switch ((try store.nodes.getPtr(node)).payload) {
            .element => |element| .{
                .namespace = if (element.namespace) |namespace| namespace.view() else null,
                .local_name = element.local_name.view(),
            },
            .document, .document_fragment, .document_type, .text, .comment, .processing_instruction => null,
        };
    }

    pub fn children(store: *Store, parent: NodeHandle) LookupError!ChildIterator {
        return .{ .store = store, .parent = parent, .pending = (try store.nodes.getPtr(parent)).first_child };
    }

    /// "Set an attribute value": sets the value of the attribute with `namespace` and `local_name`,
    /// or appends a new attribute when the element has none. An existing attribute keeps its list position.
    /// An empty `namespace` means no namespace. The store copies every string exactly.
    pub fn setAttribute(store: *Store, element: NodeHandle, namespace: ?View, local_name: View, value: View) SetAttributeError!void {
        const record = try store.elementRecord(element);
        const wanted = nullIfEmpty(namespace);
        var value_copy = try WebString.fromCodeUnits(store.gpa, value.units);
        errdefer value_copy.deinit(store.gpa);
        // Step 1: let attribute be the result of getting an attribute given namespace, localName, and element.
        if (findAttribute(record, wanted, local_name)) |index| {
            // Step 3: change attribute to value.
            const existing = &record.attributes.items[index];
            existing.value.deinit(store.gpa);
            existing.value = value_copy;
            return;
        }
        // Step 2: if attribute is null, create an attribute and append it to element.
        var namespace_copy: ?WebString = null;
        if (wanted) |name| namespace_copy = try WebString.fromCodeUnits(store.gpa, name.units);
        errdefer if (namespace_copy) |*copy| copy.deinit(store.gpa);
        var name_copy = try WebString.fromCodeUnits(store.gpa, local_name.units);
        errdefer name_copy.deinit(store.gpa);
        try record.attributes.ensureUnusedCapacity(store.gpa, 1);
        record.attributes.appendAssumeCapacity(.{ .namespace = namespace_copy, .local_name = name_copy, .value = value_copy });
    }

    /// "Get an attribute by namespace and local name", returning the attribute's value.
    /// An empty `namespace` means no namespace. The view stays valid until the attribute changes.
    pub fn attribute(store: *Store, element: NodeHandle, namespace: ?View, local_name: View) AttributeError!?View {
        const record = try store.elementRecord(element);
        const index = findAttribute(record, nullIfEmpty(namespace), local_name) orelse return null;
        return record.attributes.items[index].value.view();
    }

    /// "Remove an attribute by namespace and local name". Returns whether it removed an attribute.
    /// An empty `namespace` means no namespace.
    pub fn removeAttribute(store: *Store, element: NodeHandle, namespace: ?View, local_name: View) AttributeError!bool {
        const record = try store.elementRecord(element);
        const index = findAttribute(record, nullIfEmpty(namespace), local_name) orelse return false;
        var removed = record.attributes.orderedRemove(index);
        removed.deinit(store.gpa);
        return true;
    }

    /// Iterates the attribute list in order. Any attribute change ends the iterator's validity.
    pub fn attributes(store: *Store, element: NodeHandle) AttributeError!AttributeIterator {
        return .{ .items = (try store.elementRecord(element)).attributes.items };
    }

    /// The element's ID under the ID attribute change steps: the value of its `id` attribute in no namespace,
    /// or null when that attribute is absent or empty.
    pub fn elementId(store: *Store, element: NodeHandle) AttributeError!?View {
        const value = try store.attribute(element, null, ascii("id")) orelse return null;
        if (value.units.len == 0) return null;
        return value;
    }

    /// The element's classes: the ordered set parser over its `class` attribute in no namespace (DOM section 1.2),
    /// with each token once, at its first occurrence. Duplicates are removed in time proportional to `n log n`
    /// for `n` tokens. The views borrow the attribute value, so any attribute change ends their validity.
    /// The caller frees the result with `gpa`.
    pub fn classes(store: *Store, gpa: Allocator, element: NodeHandle) (AttributeError || Allocator.Error)![]View {
        const value = try store.attribute(element, null, ascii("class")) orelse return gpa.alloc(View, 0);
        const units = value.units;
        var tokens: std.ArrayList(ClassToken) = .empty;
        defer tokens.deinit(gpa);
        var index: usize = 0;
        while (nextClassToken(units, &index)) |token| try tokens.append(gpa, token);
        // Sort the token positions by code units, then by position, so each run of identical tokens starts with
        // the first occurrence, which the ordered set keeps.
        const order = try gpa.alloc(usize, tokens.items.len);
        defer gpa.free(order);
        for (order, 0..) |*slot, position| slot.* = position;
        const by_units: ClassOrder = .{ .units = units, .tokens = tokens.items };
        std.mem.sortUnstable(usize, order, by_units, ClassOrder.lessThan);
        const keep = try gpa.alloc(bool, tokens.items.len);
        defer gpa.free(keep);
        var kept: usize = 0;
        for (order, 0..) |position, rank| {
            keep[position] = rank == 0 or !by_units.eql(order[rank - 1], position);
            if (keep[position]) kept += 1;
        }
        const result = try gpa.alloc(View, kept);
        var written: usize = 0;
        for (tokens.items, keep) |token, first| {
            if (!first) continue;
            result[written] = .{ .units = units[token.start..token.end] };
            written += 1;
        }
        return result;
    }

    /// Whether `class` is one of the element's classes. Duplicate tokens do not change the answer,
    /// so the scan needs no deduplication and takes time proportional to the attribute value's length.
    pub fn hasClass(store: *Store, element: NodeHandle, class: View) AttributeError!bool {
        const value = try store.attribute(element, null, ascii("class")) orelse return false;
        var index: usize = 0;
        while (nextClassToken(value.units, &index)) |token| {
            countClassTokenComparison();
            if (std.mem.eql(u16, value.units[token.start..token.end], class.units)) return true;
        }
        return false;
    }

    fn elementRecord(store: *Store, node: NodeHandle) AttributeError!*Element {
        return switch ((try store.nodes.getPtr(node)).payload) {
            .element => |*element| element,
            .document, .document_fragment, .document_type, .text, .comment, .processing_instruction => error.NotAnElement,
        };
    }

    fn findAttribute(element: *const Element, namespace: ?View, local_name: View) ?usize {
        for (element.attributes.items, 0..) |*candidate, index| {
            if (candidate.named(namespace, local_name)) return index;
        }
        return null;
    }

    /// "Get an attribute by namespace and local name" step 1, and "validate and extract" step 1:
    /// an empty namespace is null.
    fn nullIfEmpty(namespace: ?View) ?View {
        const name = namespace orelse return null;
        return if (name.units.len == 0) null else name;
    }

    /// Pre-inserts `node` into `parent` before `child`, or after the last child when `child` is null.
    pub fn insertBefore(store: *Store, parent: NodeHandle, node: NodeHandle, child: ?NodeHandle) MutationError!void {
        try store.nodes.validate(parent);
        try store.nodes.validate(node);
        if (child) |reference| try store.nodes.validate(reference);
        try store.preInsert(node, parent, child);
    }

    /// Appends `node` to `parent`.
    pub fn appendChild(store: *Store, parent: NodeHandle, node: NodeHandle) MutationError!void {
        try store.nodes.validate(parent);
        try store.nodes.validate(node);
        // "append": pre-insert node into parent before null.
        try store.preInsert(node, parent, null);
    }

    /// Replaces `child` with `node` within `parent`.
    pub fn replaceChild(store: *Store, parent: NodeHandle, node: NodeHandle, child: NodeHandle) MutationError!void {
        try store.nodes.validate(parent);
        try store.nodes.validate(node);
        try store.nodes.validate(child);
        // "replace" step 1: ensure pre-insert validity given node, parent, child, and « child ».
        try store.ensurePreInsertValidity(node, parent, child, child);
        // Steps 2 and 3: let referenceChild be child's next sibling, or node's next sibling if that is node.
        var reference = store.at(child).next_sibling;
        if (sameNode(reference, node)) reference = store.at(node).next_sibling;
        // Step 6: adopt node into parent's node document.
        store.adoptInto(node, store.at(parent).document);
        // Step 7: if child's parent is non-null, remove child. It is null only when child is node.
        if (store.at(child).parent != null) store.remove(child);
        // Step 9: insert node into parent before referenceChild.
        store.insert(node, parent, reference);
    }

    /// Pre-removes `child` from `parent`.
    pub fn removeChild(store: *Store, parent: NodeHandle, child: NodeHandle) MutationError!void {
        try store.nodes.validate(parent);
        try store.nodes.validate(child);
        // "pre-remove" step 1: if child's parent is not parent, then throw a "NotFoundError" DOMException.
        if (!sameNode(store.at(child).parent, parent)) return error.NotFound;
        // Step 2: remove child.
        store.remove(child);
    }

    /// Adopts `node` into `document`.
    pub fn adopt(store: *Store, node: NodeHandle, document: NodeHandle) AdoptError!void {
        const node_kind = try store.nodeKind(node);
        try store.requireDocument(document);
        // `adoptNode()` step 1: if node is a document, then throw a "NotSupportedError" DOMException.
        // The adopt algorithm relies on this check, because a document is its own node document.
        if (node_kind == .document) return error.NotSupported;
        store.adoptInto(node, document);
    }

    /// Makes `node` a root until a matching `release`.
    pub fn retain(store: *Store, node: NodeHandle) LookupError!void {
        (try store.nodes.getPtr(node)).retains += 1;
    }

    pub fn release(store: *Store, node: NodeHandle) ReleaseError!void {
        const record = try store.nodes.getPtr(node);
        if (record.retains == 0) return error.NotRetained;
        record.retains -= 1;
    }

    /// Calls `visit` once for each document and each retained node.
    /// `visit` must not create or free nodes.
    pub fn forEachRoot(store: *Store, context: anytype, comptime visit: fn (@TypeOf(context), NodeHandle) void) void {
        var entries = store.nodes.iterator();
        while (entries.next()) |entry| {
            if (isRoot(entry.value)) visit(context, entry.handle);
        }
    }

    /// Frees every node whose tree contains no root, and returns the number of nodes it freed.
    /// A freed tree is whole, so no live node links to a freed node.
    pub fn sweep(store: *Store) usize {
        var entries = store.nodes.iterator();
        while (entries.next()) |entry| {
            if (isRoot(entry.value)) store.markTree(entry.handle);
        }
        var freed: usize = 0;
        entries = store.nodes.iterator();
        while (entries.next()) |entry| {
            if (entry.value.marked) {
                entry.value.marked = false;
                continue;
            }
            var removed = store.nodes.remove(entry.handle) catch unreachable;
            freePayload(store.gpa, &removed.payload);
            freed += 1;
        }
        return freed;
    }

    /// Returns the record of a handle that the store's own links hold. Such a handle is always live.
    fn at(store: *Store, node: NodeHandle) *NodeRecord {
        return store.nodes.getPtr(node) catch unreachable;
    }

    fn kindOf(store: *Store, node: NodeHandle) Kind {
        return std.meta.activeTag(store.at(node).payload);
    }

    fn requireDocument(store: *Store, node: NodeHandle) (LookupError || error{NotADocument})!void {
        if ((try store.nodes.getPtr(node)).payload != .document) return error.NotADocument;
    }

    fn createCharacterData(store: *Store, document: NodeHandle, comptime kind: Kind, data: View) CreateError!NodeHandle {
        try store.requireDocument(document);
        var copy = try WebString.fromCodeUnits(store.gpa, data.units);
        errdefer copy.deinit(store.gpa);
        return store.nodes.insert(store.gpa, detachedRecord(@unionInit(Payload, @tagName(kind), copy), document));
    }

    /// "pre-insert" a node into a parent before null or a child.
    fn preInsert(store: *Store, node: NodeHandle, parent: NodeHandle, child: ?NodeHandle) ValidityError!void {
        // Step 1: ensure pre-insert validity given node, parent, child, and « ».
        try store.ensurePreInsertValidity(node, parent, child, null);
        // Steps 2 and 3: let referenceChild be child, or node's next sibling if child is node.
        var reference = child;
        if (sameNode(reference, node)) reference = store.at(node).next_sibling;
        // Step 4: insert node into parent before referenceChild.
        store.insert(node, parent, reference);
    }

    /// "ensure pre-insert validity", where `exclude` holds the zero or one node of childrenToExclude.
    /// It only reads the tree, so a failure changes nothing.
    fn ensurePreInsertValidity(
        store: *Store,
        node: NodeHandle,
        parent: NodeHandle,
        child: ?NodeHandle,
        exclude: ?NodeHandle,
    ) ValidityError!void {
        const parent_kind = store.kindOf(parent);
        // Step 1: if parent is not a Document, DocumentFragment, or Element node,
        // then throw a "HierarchyRequestError" DOMException.
        switch (parent_kind) {
            .document, .document_fragment, .element => {},
            .document_type, .text, .comment, .processing_instruction => return error.HierarchyRequest,
        }
        // Step 2: if node is a host-including inclusive ancestor of parent,
        // then throw a "HierarchyRequestError" DOMException.
        // No fragment has a host yet, so the host-including inclusive ancestors are the inclusive ancestors.
        if (store.isInclusiveAncestor(node, parent)) return error.HierarchyRequest;
        // Step 3: if child is non-null and its parent is not parent, then throw a "NotFoundError" DOMException.
        if (child) |reference| {
            if (!sameNode(store.at(reference).parent, parent)) return error.NotFound;
        }
        const node_kind = store.kindOf(node);
        // Step 4: if node is not a DocumentFragment, DocumentType, Element, or CharacterData node,
        // then throw a "HierarchyRequestError" DOMException.
        switch (node_kind) {
            .document_fragment, .document_type, .element, .text, .comment, .processing_instruction => {},
            .document => return error.HierarchyRequest,
        }
        // Step 5: if parent is not a document, then:
        if (parent_kind != .document) {
            // Step 5.1: if node is a doctype, then throw a "HierarchyRequestError" DOMException.
            if (node_kind == .document_type) return error.HierarchyRequest;
            // Step 5.2: return.
            return;
        }
        // Step 6: if node is a Text node, then throw a "HierarchyRequestError" DOMException.
        if (node_kind == .text) return error.HierarchyRequest;
        // Step 7: if node is a CharacterData node, then return.
        if (node_kind == .comment or node_kind == .processing_instruction) return;
        // Step 8: if node is a DocumentFragment node, then:
        if (node_kind == .document_fragment) {
            var elements: usize = 0;
            var text_child = false;
            var cursor = store.at(node).first_child;
            while (cursor) |current| : (cursor = store.at(current).next_sibling) {
                switch (store.kindOf(current)) {
                    .element => elements += 1,
                    .text => text_child = true,
                    .document, .document_fragment, .document_type, .comment, .processing_instruction => {},
                }
            }
            // Step 8.1: if node has more than one element child or has a Text node child,
            // then throw a "HierarchyRequestError" DOMException.
            if (elements > 1 or text_child) return error.HierarchyRequest;
            // Step 8.2: if node has no element child, then return.
            if (elements == 0) return;
        }
        // Step 9: if node is a DocumentFragment or Element node, then:
        if (node_kind == .document_fragment or node_kind == .element) {
            // Step 9.1: throw a "HierarchyRequestError" DOMException if any of the following are true.
            // Parent has an element child that childrenToExclude does not contain.
            if (store.hasChildExcept(parent, .element, exclude)) return error.HierarchyRequest;
            if (child) |reference| {
                // Child is non-null and a doctype is following child.
                // The node tree constraints admit a doctype only as a document child,
                // so every doctype that follows child is a following sibling of child.
                if (store.hasSiblingOfKind(reference, .next, .document_type)) return error.HierarchyRequest;
                // Child is a doctype that childrenToExclude does not contain.
                if (store.kindOf(reference) == .document_type and !sameNode(reference, exclude)) {
                    return error.HierarchyRequest;
                }
            }
            // Step 9.2: return.
            return;
        }
        // Step 10: assert: node is a doctype.
        assert(node_kind == .document_type);
        // Step 11: throw a "HierarchyRequestError" DOMException if any of the following are true.
        // Parent has a doctype child that childrenToExclude does not contain.
        if (store.hasChildExcept(parent, .document_type, exclude)) return error.HierarchyRequest;
        if (child) |reference| {
            // Child is non-null and an element is preceding child.
            // Child's ancestor is the document, so a preceding element is a previous sibling of child
            // or a descendant of one, and such a descendant has an element ancestor among those siblings.
            if (store.hasSiblingOfKind(reference, .previous, .element)) return error.HierarchyRequest;
        } else {
            // Child is null and parent has an element child that childrenToExclude does not contain.
            if (store.hasChildExcept(parent, .element, exclude)) return error.HierarchyRequest;
        }
    }

    /// "insert" a node into a parent before null or a child.
    /// The steps for live ranges, slots, custom elements, observers, and the
    /// insertion and post-connection steps have no effect yet.
    fn insert(store: *Store, node: NodeHandle, parent: NodeHandle, child: ?NodeHandle) void {
        const document = store.at(parent).document;
        if (store.kindOf(node) == .document_fragment) {
            // Steps 1, 4.1, and 7: remove each child of the fragment in tree order,
            // adopt it into parent's node document, and insert it before child.
            // Removing every child first gives the same tree, because no step observes the intermediate state.
            while (store.at(node).first_child) |moved| {
                store.adoptInto(moved, document);
                store.link(moved, parent, child);
            }
            return;
        }
        // Step 7.1: adopt node into parent's node document, which removes it from its old parent.
        store.adoptInto(node, document);
        // Steps 7.2 and 7.3: append node to parent's children, or insert it before child.
        store.link(node, parent, child);
    }

    /// Links a node without a parent into `parent`'s children before `child`, or last when `child` is null.
    fn link(store: *Store, node: NodeHandle, parent: NodeHandle, child: ?NodeHandle) void {
        const record = store.at(node);
        assert(record.parent == null);
        const parent_record = store.at(parent);
        const previous = if (child) |reference| store.at(reference).previous_sibling else parent_record.last_child;
        record.parent = parent;
        record.previous_sibling = previous;
        record.next_sibling = child;
        if (previous) |before| store.at(before).next_sibling = node else parent_record.first_child = node;
        if (child) |after| store.at(after).previous_sibling = node else parent_record.last_child = node;
    }

    /// "remove" a node from its parent.
    /// The steps for live ranges, node iterators, slots, custom elements, observers,
    /// and the removing steps have no effect yet.
    fn remove(store: *Store, node: NodeHandle) void {
        const record = store.at(node);
        // Steps 1 and 2: let parent be node's parent, and assert that it is non-null.
        const parent_record = store.at(record.parent.?);
        // Step 7: remove node from its parent's children.
        if (record.previous_sibling) |before| {
            store.at(before).next_sibling = record.next_sibling;
        } else {
            parent_record.first_child = record.next_sibling;
        }
        if (record.next_sibling) |after| {
            store.at(after).previous_sibling = record.previous_sibling;
        } else {
            parent_record.last_child = record.previous_sibling;
        }
        record.parent = null;
        record.previous_sibling = null;
        record.next_sibling = null;
    }

    /// "adopt" a node into a document.
    /// No shadow root, attribute, or custom element registry exists yet, so only the node document changes.
    fn adoptInto(store: *Store, node: NodeHandle, document: NodeHandle) void {
        // Step 1: let oldDocument be node's node document.
        const old_document = store.at(node).document;
        // Step 2: if node's parent is non-null, then remove node.
        if (store.at(node).parent != null) store.remove(node);
        // Step 3: if document is not oldDocument, then set the node document
        // of each inclusive descendant of node, in tree order, to document.
        if (sameNode(document, old_document)) return;
        var cursor: ?NodeHandle = node;
        while (cursor) |current| : (cursor = store.following(current, node)) {
            store.at(current).document = document;
        }
    }

    /// Returns the node after `current` in tree order within the subtree rooted at `root`, or null at its end.
    fn following(store: *Store, current: NodeHandle, root: NodeHandle) ?NodeHandle {
        if (store.at(current).first_child) |first| return first;
        var cursor = current;
        while (!sameNode(cursor, root)) {
            const record = store.at(cursor);
            if (record.next_sibling) |next| return next;
            cursor = record.parent.?;
        }
        return null;
    }

    fn isInclusiveAncestor(store: *Store, ancestor: NodeHandle, node: NodeHandle) bool {
        var cursor: ?NodeHandle = node;
        while (cursor) |current| : (cursor = store.at(current).parent) {
            if (sameNode(current, ancestor)) return true;
        }
        return false;
    }

    /// Whether `parent` has a child of type `kind` other than `exclude`.
    fn hasChildExcept(store: *Store, parent: NodeHandle, kind: Kind, exclude: ?NodeHandle) bool {
        var cursor = store.at(parent).first_child;
        while (cursor) |current| : (cursor = store.at(current).next_sibling) {
            if (store.kindOf(current) == kind and !sameNode(current, exclude)) return true;
        }
        return false;
    }

    const Direction = enum { previous, next };

    /// Whether a sibling of `node` in `direction` has type `kind`.
    fn hasSiblingOfKind(store: *Store, node: NodeHandle, comptime direction: Direction, kind: Kind) bool {
        var cursor = sibling(store.at(node), direction);
        while (cursor) |current| : (cursor = sibling(store.at(current), direction)) {
            if (store.kindOf(current) == kind) return true;
        }
        return false;
    }

    fn sibling(record: *const NodeRecord, comptime direction: Direction) ?NodeHandle {
        return switch (direction) {
            .previous => record.previous_sibling,
            .next => record.next_sibling,
        };
    }

    /// Marks every node of the tree that contains `node`.
    fn markTree(store: *Store, node: NodeHandle) void {
        var root = node;
        while (store.at(root).parent) |parent| root = parent;
        // Marking always covers a whole tree, so a marked root means a marked tree.
        if (store.at(root).marked) return;
        var cursor: ?NodeHandle = root;
        while (cursor) |current| : (cursor = store.following(current, root)) {
            store.at(current).marked = true;
        }
    }
};

/// Iterates the children of one parent.
/// It records each child's next sibling before it yields the child.
/// Removing or moving the yielded child therefore neither skips nor repeats another original child,
/// and a child inserted before the recorded next sibling is not visited.
/// A move that places the yielded child after the recorded sibling in the same parent visits it again.
/// A move of the recorded sibling to an earlier position visits the children between again.
/// Iteration ends early if the recorded sibling no longer is a child of the parent.
pub const ChildIterator = struct {
    store: *Store,
    parent: NodeHandle,
    /// The recorded next sibling, which the next call yields.
    pending: ?NodeHandle,

    pub fn next(iterator: *ChildIterator) ?NodeHandle {
        const current = iterator.pending orelse return null;
        const record = iterator.store.nodes.getPtr(current) catch {
            iterator.pending = null;
            return null;
        };
        if (!sameNode(record.parent, iterator.parent)) {
            iterator.pending = null;
            return null;
        }
        iterator.pending = record.next_sibling;
        return current;
    }
};

/// Iterates one element's attribute list in order.
pub const AttributeIterator = struct {
    items: []const Attribute,
    index: usize = 0,

    pub fn next(iterator: *AttributeIterator) ?AttributeView {
        if (iterator.index == iterator.items.len) return null;
        defer iterator.index += 1;
        return iterator.items[iterator.index].view();
    }
};

/// One token of a `class` attribute value, as a range of code units.
const ClassToken = struct { start: usize, end: usize };

/// The ordered set parser's split on ASCII whitespace (DOM section 1.2): the next token at or after `index`.
fn nextClassToken(units: []const u16, index: *usize) ?ClassToken {
    while (index.* < units.len and isAsciiWhitespace(units[index.*])) index.* += 1;
    if (index.* == units.len) return null;
    const start = index.*;
    while (index.* < units.len and !isAsciiWhitespace(units[index.*])) index.* += 1;
    return .{ .start = start, .end = index.* };
}

/// Orders the positions of class tokens by code units, then by position.
const ClassOrder = struct {
    units: []const u16,
    tokens: []const ClassToken,

    fn text(order: ClassOrder, position: usize) []const u16 {
        const token = order.tokens[position];
        return order.units[token.start..token.end];
    }

    fn lessThan(order: ClassOrder, a: usize, b: usize) bool {
        countClassTokenComparison();
        return switch (std.mem.order(u16, order.text(a), order.text(b))) {
            .lt => true,
            .gt => false,
            .eq => a < b,
        };
    }

    fn eql(order: ClassOrder, a: usize, b: usize) bool {
        countClassTokenComparison();
        return std.mem.eql(u16, order.text(a), order.text(b));
    }
};

/// Infra's ASCII whitespace: U+0009 TAB, U+000A LF, U+000C FF, U+000D CR, and U+0020 SPACE.
fn isAsciiWhitespace(unit: u16) bool {
    return switch (unit) {
        0x09, 0x0A, 0x0C, 0x0D, 0x20 => true,
        else => false,
    };
}

/// Returns the UTF-16 code units of an ASCII literal.
fn ascii(comptime text: []const u8) View {
    const units = comptime blk: {
        var buffer: [text.len]u16 = undefined;
        for (text, &buffer) |byte, *unit| unit.* = byte;
        break :blk buffer;
    };
    return .{ .units = &units };
}

const html_namespace = ascii("http://www.w3.org/1999/xhtml");

/// Test-only validation of every link, node document, and node tree constraint in the store.
/// Every loop is bounded by the node count, so a cycle fails the check instead of hanging it.
fn expectInvariants(store: *Store) !void {
    comptime assert(builtin.is_test);
    const total = store.nodes.count();
    var visited: usize = 0;
    var with_parent: usize = 0;
    var listed_children: usize = 0;
    var entries = store.nodes.iterator();
    while (entries.next()) |entry| : (visited += 1) {
        const node = entry.handle;
        const record = entry.value;
        try testing.expect(!record.marked);

        // The node document is a live document, and a document is its own node document.
        const document = try store.nodes.getPtr(record.document);
        try testing.expectEqual(Kind.document, std.meta.activeTag(document.payload));
        if (record.payload == .document) {
            try testing.expect(sameNode(record.document, node));
            try testing.expectEqual(null, record.parent);
        }

        // The ancestor chain ends within `total` steps, so it has no cycle.
        var steps: usize = 0;
        var ancestor = record.parent;
        while (ancestor) |up| : (steps += 1) {
            try testing.expect(steps < total);
            ancestor = (try store.nodes.getPtr(up)).parent;
        }

        if (record.parent) |parent| {
            with_parent += 1;
            const parent_record = try store.nodes.getPtr(parent);
            // Insertion adopts a node into its parent's node document.
            try testing.expect(sameNode(record.document, parent_record.document));
            if (record.previous_sibling) |previous| {
                const previous_record = try store.nodes.getPtr(previous);
                try testing.expect(sameNode(previous_record.parent, parent));
                try testing.expect(sameNode(previous_record.next_sibling, node));
            } else {
                try testing.expect(sameNode(parent_record.first_child, node));
            }
            if (record.next_sibling) |next| {
                const next_record = try store.nodes.getPtr(next);
                try testing.expect(sameNode(next_record.parent, parent));
                try testing.expect(sameNode(next_record.previous_sibling, node));
            } else {
                try testing.expect(sameNode(parent_record.last_child, node));
            }
        } else {
            try testing.expectEqual(null, record.previous_sibling);
            try testing.expectEqual(null, record.next_sibling);
        }

        if (record.first_child == null or record.last_child == null) {
            try testing.expectEqual(null, record.first_child);
            try testing.expectEqual(null, record.last_child);
            continue;
        }
        var doctypes: usize = 0;
        var elements: usize = 0;
        var previous: ?NodeHandle = null;
        var cursor = record.first_child;
        var length: usize = 0;
        while (cursor) |child| : (length += 1) {
            try testing.expect(length < total);
            const child_record = try store.nodes.getPtr(child);
            try testing.expect(sameNode(child_record.parent, node));
            try testing.expect(sameNode(child_record.previous_sibling, previous));
            try expectAllowedChild(record.payload, child_record.payload, &doctypes, &elements);
            previous = child;
            cursor = child_record.next_sibling;
        }
        try testing.expect(sameNode(previous, record.last_child));
        listed_children += length;
    }
    try testing.expectEqual(total, visited);
    // Each node with a parent appears in exactly one child list.
    try testing.expectEqual(with_parent, listed_children);
}

/// Checks the node tree constraints of the DOM Standard, section 4.2 "Node tree".
fn expectAllowedChild(parent: Kind, child: Kind, doctypes: *usize, elements: *usize) !void {
    switch (parent) {
        // Comments and processing instructions, an optional doctype, then an optional element.
        .document => switch (child) {
            .comment, .processing_instruction => {},
            .document_type => {
                try testing.expect(doctypes.* == 0 and elements.* == 0);
                doctypes.* += 1;
            },
            .element => {
                try testing.expect(elements.* == 0);
                elements.* += 1;
            },
            .document, .document_fragment, .text => return error.TestUnexpectedResult,
        },
        .document_fragment, .element => switch (child) {
            .element, .text, .comment, .processing_instruction => {},
            .document, .document_fragment, .document_type => return error.TestUnexpectedResult,
        },
        .document_type, .text, .comment, .processing_instruction => return error.TestUnexpectedResult,
    }
}

/// Test-only digest of every node handle and record in the store, including string contents.
fn fingerprint(store: *Store) u64 {
    var hasher: std.hash.Wyhash = .init(0);
    const hash = std.hash.autoHashStrat;
    hash(&hasher, store.nodes.count(), .Deep);
    var entries = store.nodes.iterator();
    while (entries.next()) |entry| {
        hash(&hasher, entry.handle, .Deep);
        hash(&hasher, entry.value.*, .Deep);
    }
    return hasher.final();
}

fn newDocument(store: *Store) !NodeHandle {
    const node = try store.createDocument();
    try expectInvariants(store);
    return node;
}

fn newFragment(store: *Store, document: NodeHandle) !NodeHandle {
    const node = try store.createDocumentFragment(document);
    try expectInvariants(store);
    return node;
}

fn newDoctype(store: *Store, document: NodeHandle) !NodeHandle {
    const node = try store.createDocumentType(document);
    try expectInvariants(store);
    return node;
}

fn newElement(store: *Store, document: NodeHandle, comptime local_name: []const u8) !NodeHandle {
    const node = try store.createElement(document, html_namespace, ascii(local_name));
    try expectInvariants(store);
    return node;
}

fn newText(store: *Store, document: NodeHandle, comptime text: []const u8) !NodeHandle {
    const node = try store.createText(document, ascii(text));
    try expectInvariants(store);
    return node;
}

fn newComment(store: *Store, document: NodeHandle, comptime text: []const u8) !NodeHandle {
    const node = try store.createComment(document, ascii(text));
    try expectInvariants(store);
    return node;
}

fn newProcessingInstruction(store: *Store, document: NodeHandle, comptime text: []const u8) !NodeHandle {
    const node = try store.createProcessingInstruction(document, ascii(text));
    try expectInvariants(store);
    return node;
}

fn appendChecked(store: *Store, parent: NodeHandle, node: NodeHandle) !void {
    try store.appendChild(parent, node);
    try expectInvariants(store);
}

fn insertChecked(store: *Store, parent: NodeHandle, node: NodeHandle, child: ?NodeHandle) !void {
    try store.insertBefore(parent, node, child);
    try expectInvariants(store);
}

fn replaceChecked(store: *Store, parent: NodeHandle, node: NodeHandle, child: NodeHandle) !void {
    try store.replaceChild(parent, node, child);
    try expectInvariants(store);
}

fn removeChecked(store: *Store, parent: NodeHandle, child: NodeHandle) !void {
    try store.removeChild(parent, child);
    try expectInvariants(store);
}

fn adoptChecked(store: *Store, node: NodeHandle, document: NodeHandle) !void {
    try store.adopt(node, document);
    try expectInvariants(store);
}

fn retainChecked(store: *Store, node: NodeHandle) !void {
    try store.retain(node);
    try expectInvariants(store);
}

fn releaseChecked(store: *Store, node: NodeHandle) !void {
    try store.release(node);
    try expectInvariants(store);
}

fn sweepChecked(store: *Store) !usize {
    const freed = store.sweep();
    try expectInvariants(store);
    return freed;
}

/// Runs one operation that must fail with `expected`, and checks that it changed nothing.
fn expectRejected(store: *Store, expected: anyerror, comptime operation: anytype, args: anytype) !void {
    const before = fingerprint(store);
    try testing.expectError(expected, @call(.auto, operation, args));
    try testing.expectEqual(before, fingerprint(store));
    try expectInvariants(store);
}

/// Checks the child list of `parent` in both directions through the public accessors.
fn expectChildren(store: *Store, parent: NodeHandle, expected: []const NodeHandle) !void {
    var forward = try store.firstChild(parent);
    for (expected, 0..) |child, index| {
        try testing.expect(sameNode(forward, child));
        try testing.expect(sameNode(try store.parentNode(child), parent));
        const previous: ?NodeHandle = if (index == 0) null else expected[index - 1];
        try testing.expect(sameNode(try store.previousSibling(child), previous));
        forward = try store.nextSibling(child);
    }
    try testing.expectEqual(null, forward);
    var backward = try store.lastChild(parent);
    var index = expected.len;
    while (index > 0) {
        index -= 1;
        try testing.expect(sameNode(backward, expected[index]));
        backward = try store.previousSibling(expected[index]);
    }
    try testing.expectEqual(null, backward);
}

/// Checks that `node` has no parent and no siblings.
fn expectDetached(store: *Store, node: NodeHandle) !void {
    try testing.expectEqual(null, try store.parentNode(node));
    try testing.expectEqual(null, try store.previousSibling(node));
    try testing.expectEqual(null, try store.nextSibling(node));
}

test "FP-0009 case 1: appendChild and insertBefore maintain parent, child, and sibling links for first, middle, and last positions" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;

    const document = try newDocument(s);
    const parent = try newElement(s, document, "div");
    const a = try newElement(s, document, "a");
    const b = try newText(s, document, "b");
    const c = try newComment(s, document, "c");
    const d = try newElement(s, document, "d");
    const e = try newProcessingInstruction(s, document, "e");
    try expectChildren(s, parent, &.{});

    // The only child is both first and last.
    try appendChecked(s, parent, b);
    try expectChildren(s, parent, &.{b});
    // appendChild adds the last child.
    try appendChecked(s, parent, d);
    try expectChildren(s, parent, &.{ b, d });
    // insertBefore the first child adds a new first child.
    try insertChecked(s, parent, a, b);
    try expectChildren(s, parent, &.{ a, b, d });
    // insertBefore a middle or last child adds a middle child.
    try insertChecked(s, parent, c, d);
    try expectChildren(s, parent, &.{ a, b, c, d });
    // insertBefore a null child adds the last child.
    try insertChecked(s, parent, e, null);
    try expectChildren(s, parent, &.{ a, b, c, d, e });

    try testing.expect(sameNode(try s.firstChild(parent), a));
    try testing.expect(sameNode(try s.lastChild(parent), e));
    try testing.expectEqual(null, try s.parentNode(parent));
    for ([_]NodeHandle{ a, b, c, d, e }) |child| {
        try testing.expect(sameNode(try s.nodeDocument(child), document));
        try testing.expectEqual(null, try s.firstChild(child));
        try testing.expectEqual(null, try s.lastChild(child));
    }
    try testing.expectEqual(Kind.element, try s.nodeKind(a));
    try testing.expectEqual(Kind.text, try s.nodeKind(b));
    try testing.expectEqual(Kind.comment, try s.nodeKind(c));
    try testing.expectEqual(Kind.processing_instruction, try s.nodeKind(e));
    try testing.expect((try s.characterData(b)).?.eql(ascii("b")));
    try testing.expect((try s.characterData(e)).?.eql(ascii("e")));
    try testing.expectEqual(null, try s.characterData(a));
    const name = (try s.elementName(d)).?;
    try testing.expect(name.namespace.?.eql(html_namespace));
    try testing.expect(name.local_name.eql(ascii("d")));
    try testing.expectEqual(null, try s.elementName(b));
}

test "FP-0009 case 2: every condition of ensure pre-insert validity returns its standard error and changes nothing" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);

    // Step 1: parent is not a Document, DocumentFragment, or Element node.
    {
        const node = try newElement(s, document, "span");
        const parents = [_]NodeHandle{
            try newDoctype(s, document),
            try newText(s, document, "text"),
            try newComment(s, document, "comment"),
            try newProcessingInstruction(s, document, "instruction"),
        };
        for (parents) |parent| {
            try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, parent, node });
            try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, parent, node, null });
        }
    }

    // Step 2: node is a host-including inclusive ancestor of parent.
    {
        const outer = try newElement(s, document, "div");
        const middle = try newElement(s, document, "section");
        const inner = try newElement(s, document, "p");
        try appendChecked(s, outer, middle);
        try appendChecked(s, middle, inner);
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, outer, outer });
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, inner, outer });
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, middle, outer, inner });
        const fragment = try newFragment(s, document);
        const held = try newElement(s, document, "b");
        try appendChecked(s, fragment, held);
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, held, fragment });
    }

    // Step 3: child is non-null and its parent is not parent.
    {
        const parent = try newElement(s, document, "ul");
        const other = try newElement(s, document, "ol");
        const own = try newElement(s, document, "li");
        const foreign = try newElement(s, document, "li");
        const detached = try newElement(s, document, "li");
        try appendChecked(s, parent, own);
        try appendChecked(s, other, foreign);
        const node = try newElement(s, document, "li");
        try expectRejected(s, error.NotFound, Store.insertBefore, .{ s, parent, node, foreign });
        try expectRejected(s, error.NotFound, Store.insertBefore, .{ s, parent, node, detached });
        try expectRejected(s, error.NotFound, Store.insertBefore, .{ s, parent, node, parent });
    }

    // Step 4: node is not a DocumentFragment, DocumentType, Element, or CharacterData node.
    {
        const parent = try newElement(s, document, "div");
        const fragment = try newFragment(s, document);
        const other_document = try newDocument(s);
        for ([_]NodeHandle{ parent, fragment, document }) |target| {
            try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, other_document });
        }
    }

    // Step 5.1: parent is not a document and node is a doctype.
    {
        const doctype = try newDoctype(s, document);
        const element = try newElement(s, document, "div");
        const fragment = try newFragment(s, document);
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, element, doctype });
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, fragment, doctype });
    }

    // Step 6: parent is a document and node is a Text node.
    {
        const target = try newDocument(s);
        const text = try newText(s, target, "text");
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, text });
        // Step 7 accepts every other CharacterData node.
        try appendChecked(s, target, try newComment(s, target, "comment"));
        try appendChecked(s, target, try newProcessingInstruction(s, target, "instruction"));
    }

    // Step 8.1: node is a fragment with more than one element child or with a Text node child.
    {
        const target = try newDocument(s);
        const two_elements = try newFragment(s, target);
        try appendChecked(s, two_elements, try newElement(s, target, "a"));
        try appendChecked(s, two_elements, try newElement(s, target, "b"));
        const only_text = try newFragment(s, target);
        try appendChecked(s, only_text, try newText(s, target, "text"));
        const element_and_text = try newFragment(s, target);
        try appendChecked(s, element_and_text, try newElement(s, target, "c"));
        try appendChecked(s, element_and_text, try newText(s, target, "text"));
        for ([_]NodeHandle{ two_elements, only_text, element_and_text }) |fragment| {
            try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, fragment });
        }
    }

    // Step 9.1: node is an element or a fragment with one element child, and parent has an element child.
    {
        const target = try newDocument(s);
        try appendChecked(s, target, try newElement(s, target, "html"));
        const element = try newElement(s, target, "body");
        const fragment = try newFragment(s, target);
        try appendChecked(s, fragment, try newElement(s, target, "head"));
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, element });
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, fragment });
    }

    // Step 9.1: child is non-null and a doctype is following child.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "before");
        try appendChecked(s, target, comment);
        try appendChecked(s, target, try newDoctype(s, target));
        const element = try newElement(s, target, "html");
        const fragment = try newFragment(s, target);
        try appendChecked(s, fragment, try newElement(s, target, "html"));
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, element, comment });
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, fragment, comment });
    }

    // Step 9.1: child is a doctype.
    {
        const target = try newDocument(s);
        const doctype = try newDoctype(s, target);
        try appendChecked(s, target, doctype);
        const element = try newElement(s, target, "html");
        const fragment = try newFragment(s, target);
        try appendChecked(s, fragment, try newElement(s, target, "html"));
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, element, doctype });
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, fragment, doctype });
    }

    // Step 11: node is a doctype and parent has a doctype child.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "after");
        try appendChecked(s, target, try newDoctype(s, target));
        try appendChecked(s, target, comment);
        const doctype = try newDoctype(s, target);
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, doctype });
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, doctype, comment });
    }

    // Step 11: node is a doctype, child is non-null, and an element is preceding child.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "after");
        try appendChecked(s, target, try newElement(s, target, "html"));
        try appendChecked(s, target, comment);
        const doctype = try newDoctype(s, target);
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, target, doctype, comment });
    }

    // Step 11: node is a doctype, child is null, and parent has an element child.
    {
        const target = try newDocument(s);
        try appendChecked(s, target, try newComment(s, target, "before"));
        try appendChecked(s, target, try newElement(s, target, "html"));
        const doctype = try newDoctype(s, target);
        try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, doctype });
    }

    // The steps run in order, so an earlier condition decides the error.
    {
        const text = try newText(s, document, "text");
        const detached = try newElement(s, document, "i");
        const node = try newElement(s, document, "em");
        const parent = try newElement(s, document, "div");
        const other_document = try newDocument(s);
        // Step 1 precedes step 3.
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, text, node, detached });
        // Step 2 precedes step 3.
        try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, node, node, detached });
        // Step 3 precedes step 4.
        try expectRejected(s, error.NotFound, Store.insertBefore, .{ s, parent, other_document, detached });
        // Step 3 precedes step 6.
        const target = try newDocument(s);
        try expectRejected(s, error.NotFound, Store.insertBefore, .{ s, target, try newText(s, target, "t"), detached });
    }
}

test "FP-0009 case 3: every condition of the replace validity checks returns its standard error and changes nothing" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);

    // Step 1: parent is not a Document, DocumentFragment, or Element node.
    {
        const node = try newElement(s, document, "span");
        const child = try newElement(s, document, "b");
        const parents = [_]NodeHandle{
            try newDoctype(s, document),
            try newText(s, document, "text"),
            try newComment(s, document, "comment"),
            try newProcessingInstruction(s, document, "instruction"),
        };
        for (parents) |parent| {
            try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, parent, node, child });
        }
    }

    // Step 2: node is a host-including inclusive ancestor of parent.
    {
        const outer = try newElement(s, document, "div");
        const middle = try newElement(s, document, "section");
        const inner = try newElement(s, document, "p");
        try appendChecked(s, outer, middle);
        try appendChecked(s, middle, inner);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, middle, outer, inner });
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, outer, outer, middle });
    }

    // Step 3: child's parent is not parent.
    {
        const parent = try newElement(s, document, "ul");
        const other = try newElement(s, document, "ol");
        const own = try newElement(s, document, "li");
        const foreign = try newElement(s, document, "li");
        const detached = try newElement(s, document, "li");
        try appendChecked(s, parent, own);
        try appendChecked(s, other, foreign);
        const node = try newElement(s, document, "li");
        try expectRejected(s, error.NotFound, Store.replaceChild, .{ s, parent, node, foreign });
        try expectRejected(s, error.NotFound, Store.replaceChild, .{ s, parent, node, detached });
    }

    // Step 4: node is a document.
    {
        const parent = try newElement(s, document, "div");
        const own = try newElement(s, document, "p");
        try appendChecked(s, parent, own);
        const other_document = try newDocument(s);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, parent, other_document, own });
    }

    // Step 5.1: parent is not a document and node is a doctype.
    {
        const element = try newElement(s, document, "div");
        const element_child = try newElement(s, document, "p");
        try appendChecked(s, element, element_child);
        const fragment = try newFragment(s, document);
        const fragment_child = try newText(s, document, "text");
        try appendChecked(s, fragment, fragment_child);
        const doctype = try newDoctype(s, document);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, element, doctype, element_child });
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, fragment, doctype, fragment_child });
    }

    // Step 6: parent is a document and node is a Text node.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, comment);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, try newText(s, target, "text"), comment });
    }

    // Step 8.1: node is a fragment with more than one element child or with a Text node child.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, comment);
        const two_elements = try newFragment(s, target);
        try appendChecked(s, two_elements, try newElement(s, target, "a"));
        try appendChecked(s, two_elements, try newElement(s, target, "b"));
        const with_text = try newFragment(s, target);
        try appendChecked(s, with_text, try newText(s, target, "text"));
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, two_elements, comment });
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, with_text, comment });
    }

    // Step 9.1: parent has an element child that childrenToExclude does not contain.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "comment");
        const html = try newElement(s, target, "html");
        try appendChecked(s, target, comment);
        try appendChecked(s, target, html);
        const element = try newElement(s, target, "body");
        const fragment = try newFragment(s, target);
        try appendChecked(s, fragment, try newElement(s, target, "head"));
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, element, comment });
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, fragment, comment });
        // childrenToExclude contains child, so replacing the element child itself is valid.
        try replaceChecked(s, target, element, html);
        try expectChildren(s, target, &.{ comment, element });
        try expectDetached(s, html);
    }

    // Step 9.1: child is non-null and a doctype is following child.
    {
        const target = try newDocument(s);
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, comment);
        try appendChecked(s, target, try newDoctype(s, target));
        const element = try newElement(s, target, "html");
        const fragment = try newFragment(s, target);
        try appendChecked(s, fragment, try newElement(s, target, "html"));
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, element, comment });
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, fragment, comment });
    }

    // Step 9.1: a doctype child is in childrenToExclude, so an element may replace it.
    {
        const target = try newDocument(s);
        const doctype = try newDoctype(s, target);
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, doctype);
        try appendChecked(s, target, comment);
        const element = try newElement(s, target, "html");
        try replaceChecked(s, target, element, doctype);
        try expectChildren(s, target, &.{ element, comment });
        try expectDetached(s, doctype);
    }

    // Step 11: parent has a doctype child that childrenToExclude does not contain.
    {
        const target = try newDocument(s);
        const doctype = try newDoctype(s, target);
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, doctype);
        try appendChecked(s, target, comment);
        const replacement = try newDoctype(s, target);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, replacement, comment });
        try replaceChecked(s, target, replacement, doctype);
        try expectChildren(s, target, &.{ replacement, comment });
        try expectDetached(s, doctype);
    }

    // Step 11: child is non-null and an element is preceding child.
    {
        const target = try newDocument(s);
        const html = try newElement(s, target, "html");
        const comment = try newComment(s, target, "comment");
        try appendChecked(s, target, html);
        try appendChecked(s, target, comment);
        const doctype = try newDoctype(s, target);
        try expectRejected(s, error.HierarchyRequest, Store.replaceChild, .{ s, target, doctype, comment });
        // No element precedes the element child itself.
        try replaceChecked(s, target, doctype, html);
        try expectChildren(s, target, &.{ doctype, comment });
    }

    // Valid replacements, including a node that is child or child's next sibling.
    {
        const parent = try newElement(s, document, "div");
        const a = try newElement(s, document, "a");
        const b = try newElement(s, document, "b");
        const c = try newElement(s, document, "c");
        const x = try newElement(s, document, "x");
        for ([_]NodeHandle{ a, b, c }) |child| try appendChecked(s, parent, child);
        try replaceChecked(s, parent, x, b);
        try expectChildren(s, parent, &.{ a, x, c });
        try expectDetached(s, b);
        try replaceChecked(s, parent, c, a);
        try expectChildren(s, parent, &.{ c, x });
        try expectDetached(s, a);
        try replaceChecked(s, parent, x, c);
        try expectChildren(s, parent, &.{x});
        try replaceChecked(s, parent, x, x);
        try expectChildren(s, parent, &.{x});
        const fragment = try newFragment(s, document);
        const f1 = try newText(s, document, "f1");
        const f2 = try newElement(s, document, "f2");
        try appendChecked(s, fragment, f1);
        try appendChecked(s, fragment, f2);
        try replaceChecked(s, parent, fragment, x);
        try expectChildren(s, parent, &.{ f1, f2 });
        try expectChildren(s, fragment, &.{});
        try expectDetached(s, x);
    }
}

test "FP-0009 case 4: removeChild with a child of another parent returns NotFound, and a valid removal unlinks the child completely" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);

    const parent = try newElement(s, document, "div");
    const other = try newElement(s, document, "span");
    const a = try newElement(s, document, "a");
    const b = try newElement(s, document, "b");
    const c = try newText(s, document, "c");
    const d = try newComment(s, document, "d");
    const grandchild = try newText(s, document, "under b");
    const foreign = try newElement(s, document, "e");
    const detached = try newElement(s, document, "f");
    for ([_]NodeHandle{ a, b, c, d }) |child| try appendChecked(s, parent, child);
    try appendChecked(s, b, grandchild);
    try appendChecked(s, other, foreign);

    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, parent, foreign });
    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, parent, detached });
    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, parent, parent });
    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, a, b });
    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, parent, grandchild });

    // A middle child.
    try removeChecked(s, parent, b);
    try expectChildren(s, parent, &.{ a, c, d });
    try expectDetached(s, b);
    // A removed node keeps its own subtree and node document.
    try expectChildren(s, b, &.{grandchild});
    try testing.expect(sameNode(try s.nodeDocument(b), document));
    // The first child.
    try removeChecked(s, parent, a);
    try expectChildren(s, parent, &.{ c, d });
    try expectDetached(s, a);
    // The last child.
    try removeChecked(s, parent, d);
    try expectChildren(s, parent, &.{c});
    try expectDetached(s, d);
    // The only child.
    try removeChecked(s, parent, c);
    try expectChildren(s, parent, &.{});
    try expectDetached(s, c);

    try expectRejected(s, error.NotFound, Store.removeChild, .{ s, parent, b });
    try expectChildren(s, other, &.{foreign});
}

test "FP-0009 case 5: inserting a document fragment moves its children in order and empties it, and a document parent counts its element children" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const other_document = try newDocument(s);

    const parent = try newElement(s, document, "div");
    const x = try newElement(s, document, "x");
    const y = try newElement(s, document, "y");
    try appendChecked(s, parent, x);
    try appendChecked(s, parent, y);
    const fragment = try newFragment(s, other_document);
    const a = try newElement(s, other_document, "a");
    const a1 = try newText(s, other_document, "a1");
    const t = try newText(s, other_document, "t");
    const c = try newComment(s, other_document, "c");
    try appendChecked(s, a, a1);
    for ([_]NodeHandle{ a, t, c }) |child| try appendChecked(s, fragment, child);

    try insertChecked(s, parent, fragment, y);
    try expectChildren(s, parent, &.{ x, a, t, c, y });
    try expectChildren(s, fragment, &.{});
    try expectDetached(s, fragment);
    try expectChildren(s, a, &.{a1});
    // Insertion adopts each moved child and its descendants, but not the fragment.
    for ([_]NodeHandle{ a, a1, t, c }) |node| try testing.expect(sameNode(try s.nodeDocument(node), document));
    try testing.expect(sameNode(try s.nodeDocument(fragment), other_document));

    // An empty fragment inserts nothing.
    try appendChecked(s, parent, fragment);
    try expectChildren(s, parent, &.{ x, a, t, c, y });

    // A document accepts a fragment with one element child and no Text node child.
    const target = try newDocument(s);
    const first = try newFragment(s, target);
    const comment = try newComment(s, target, "comment");
    const html = try newElement(s, target, "html");
    const instruction = try newProcessingInstruction(s, target, "instruction");
    for ([_]NodeHandle{ comment, html, instruction }) |child| try appendChecked(s, first, child);
    try appendChecked(s, target, first);
    try expectChildren(s, target, &.{ comment, html, instruction });
    try expectChildren(s, first, &.{});

    // The fragment's element child counts against the document's existing element child.
    const second = try newFragment(s, target);
    const body = try newElement(s, target, "body");
    try appendChecked(s, second, body);
    try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, target, second });
    try expectChildren(s, second, &.{body});

    // Two element children in one fragment count as two.
    const empty = try newDocument(s);
    const pair = try newFragment(s, empty);
    const p1 = try newElement(s, empty, "p1");
    const p2 = try newElement(s, empty, "p2");
    try appendChecked(s, pair, p1);
    try appendChecked(s, pair, p2);
    try expectRejected(s, error.HierarchyRequest, Store.appendChild, .{ s, empty, pair });
    try expectChildren(s, pair, &.{ p1, p2 });
    try expectChildren(s, empty, &.{});

    // A fragment with one element child cannot precede a doctype, but can follow it.
    const typed = try newDocument(s);
    const doctype = try newDoctype(s, typed);
    try appendChecked(s, typed, doctype);
    const single = try newFragment(s, typed);
    const root = try newElement(s, typed, "html");
    try appendChecked(s, single, root);
    try expectRejected(s, error.HierarchyRequest, Store.insertBefore, .{ s, typed, single, doctype });
    try appendChecked(s, typed, single);
    try expectChildren(s, typed, &.{ doctype, root });
}

test "FP-0009 case 6: adopt removes the node from its old parent and changes the node document of every inclusive descendant" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const old_document = try newDocument(s);
    const new_document = try newDocument(s);

    const html = try newElement(s, old_document, "html");
    const head = try newElement(s, old_document, "head");
    const body = try newElement(s, old_document, "body");
    const div = try newElement(s, old_document, "div");
    const text = try newText(s, old_document, "text");
    const comment = try newComment(s, old_document, "comment");
    const span = try newElement(s, old_document, "span");
    try appendChecked(s, old_document, html);
    try appendChecked(s, html, head);
    try appendChecked(s, html, body);
    try appendChecked(s, body, div);
    try appendChecked(s, div, text);
    try appendChecked(s, div, comment);
    try appendChecked(s, body, span);
    const subtree = [_]NodeHandle{ body, div, text, comment, span };

    try adoptChecked(s, body, new_document);
    try expectDetached(s, body);
    try expectChildren(s, html, &.{head});
    try expectChildren(s, body, &.{ div, span });
    try expectChildren(s, div, &.{ text, comment });
    for (subtree) |node| try testing.expect(sameNode(try s.nodeDocument(node), new_document));
    for ([_]NodeHandle{ html, head }) |node| try testing.expect(sameNode(try s.nodeDocument(node), old_document));

    // Adopting a detached node into its own node document changes nothing.
    const before = fingerprint(s);
    try adoptChecked(s, body, new_document);
    try testing.expectEqual(before, fingerprint(s));

    // Adopting a child into its own node document still removes it.
    try adoptChecked(s, div, new_document);
    try expectDetached(s, div);
    try expectChildren(s, body, &.{span});
    try expectChildren(s, div, &.{ text, comment });

    // Insertion adopts the node into the parent's node document.
    try appendChecked(s, html, body);
    try expectChildren(s, html, &.{ head, body });
    for ([_]NodeHandle{ body, span }) |node| try testing.expect(sameNode(try s.nodeDocument(node), old_document));
    for ([_]NodeHandle{ div, text, comment }) |node| try testing.expect(sameNode(try s.nodeDocument(node), new_document));

    // adoptNode rejects a document, and a target that is not a document is not a document.
    try expectRejected(s, error.NotSupported, Store.adopt, .{ s, old_document, new_document });
    try expectRejected(s, error.NotADocument, Store.adopt, .{ s, div, html });
}

test "FP-0009 case 7: inserting a node that already has a parent moves it and leaves the old parent consistent" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const other_document = try newDocument(s);

    const p = try newElement(s, document, "p");
    const q = try newElement(s, document, "q");
    const a = try newElement(s, document, "a");
    const b = try newElement(s, document, "b");
    const c = try newElement(s, document, "c");
    const d = try newElement(s, document, "d");
    for ([_]NodeHandle{ a, b, c }) |child| try appendChecked(s, p, child);
    try appendChecked(s, q, d);

    try appendChecked(s, q, b);
    try expectChildren(s, p, &.{ a, c });
    try expectChildren(s, q, &.{ d, b });
    try insertChecked(s, q, a, d);
    try expectChildren(s, p, &.{c});
    try expectChildren(s, q, &.{ a, d, b });

    // A node inserted before itself keeps its position.
    try insertChecked(s, q, d, d);
    try expectChildren(s, q, &.{ a, d, b });
    // Moves within one parent.
    try insertChecked(s, q, b, a);
    try expectChildren(s, q, &.{ b, a, d });
    try insertChecked(s, q, b, null);
    try expectChildren(s, q, &.{ a, d, b });
    try insertChecked(s, q, a, b);
    try expectChildren(s, q, &.{ d, a, b });
    try appendChecked(s, p, c);
    try expectChildren(s, p, &.{c});

    // A move into another document adopts the node and its descendants.
    const r = try newElement(s, other_document, "r");
    const under_d = try newText(s, document, "under d");
    try appendChecked(s, d, under_d);
    try appendChecked(s, r, d);
    try expectChildren(s, q, &.{ a, b });
    try expectChildren(s, r, &.{d});
    try testing.expect(sameNode(try s.nodeDocument(d), other_document));
    try testing.expect(sameNode(try s.nodeDocument(under_d), other_document));
}

const RootLog = struct {
    seen: [16]NodeHandle = undefined,
    len: usize = 0,
    overflow: bool = false,

    fn visit(log: *RootLog, node: NodeHandle) void {
        if (log.len == log.seen.len) {
            log.overflow = true;
            return;
        }
        log.seen[log.len] = node;
        log.len += 1;
    }

    fn expectExactly(log: *const RootLog, expected: []const NodeHandle) !void {
        try testing.expect(!log.overflow);
        try testing.expectEqual(expected.len, log.len);
        for (expected) |root| {
            var hits: usize = 0;
            for (log.seen[0..log.len]) |seen| {
                if (sameNode(seen, root)) hits += 1;
            }
            try testing.expectEqual(1, hits);
        }
    }
};

test "FP-0009 case 8: forEachRoot visits every document and retained node once, and sweep keeps exactly what the roots reach" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const other_document = try newDocument(s);

    // A tree connected to a document.
    const html = try newElement(s, document, "html");
    const body = try newElement(s, document, "body");
    try appendChecked(s, document, html);
    try appendChecked(s, html, body);
    // A retained detached subtree. Two retains need two releases.
    const retained = try newElement(s, document, "retained");
    const retained_child = try newText(s, document, "kept");
    try appendChecked(s, retained, retained_child);
    try retainChecked(s, retained);
    try retainChecked(s, retained);
    // An unreachable detached subtree.
    const lost = try newElement(s, document, "lost");
    const lost_child = try newText(s, document, "lost");
    try appendChecked(s, lost, lost_child);
    // A detached tree whose retained descendant keeps the whole tree alive.
    const tree = try newElement(s, other_document, "tree");
    const branch = try newElement(s, other_document, "branch");
    const leaf = try newElement(s, other_document, "leaf");
    const sibling = try newComment(s, other_document, "sibling");
    try appendChecked(s, tree, branch);
    try appendChecked(s, branch, leaf);
    try appendChecked(s, tree, sibling);
    try retainChecked(s, leaf);
    // A retained document is still visited once.
    try retainChecked(s, other_document);

    var log: RootLog = .{};
    s.forEachRoot(&log, RootLog.visit);
    try log.expectExactly(&.{ document, other_document, retained, leaf });

    const live = s.nodeCount();
    try testing.expectEqual(2, try sweepChecked(s));
    try testing.expectEqual(live - 2, s.nodeCount());
    try testing.expectError(error.StaleHandle, s.nodeKind(lost));
    try testing.expectError(error.StaleHandle, s.nodeKind(lost_child));
    for ([_]NodeHandle{ document, other_document, html, body, retained, retained_child, tree, branch, leaf, sibling }) |node| {
        _ = try s.nodeKind(node);
    }
    try expectChildren(s, tree, &.{ branch, sibling });
    try expectChildren(s, branch, &.{leaf});

    // One release leaves one retain, so the subtree stays.
    try releaseChecked(s, retained);
    try testing.expectEqual(0, try sweepChecked(s));
    try releaseChecked(s, retained);
    log = .{};
    s.forEachRoot(&log, RootLog.visit);
    try log.expectExactly(&.{ document, other_document, leaf });
    try testing.expectEqual(2, try sweepChecked(s));
    try testing.expectError(error.StaleHandle, s.nodeKind(retained));
    try testing.expectError(error.StaleHandle, s.nodeKind(retained_child));

    try releaseChecked(s, leaf);
    try testing.expectEqual(4, try sweepChecked(s));
    for ([_]NodeHandle{ tree, branch, leaf, sibling }) |node| try testing.expectError(error.StaleHandle, s.nodeKind(node));

    // Documents stay roots without a retain.
    try releaseChecked(s, other_document);
    try expectRejected(s, error.NotRetained, Store.release, .{ s, other_document });
    try testing.expectEqual(0, try sweepChecked(s));
    try expectChildren(s, document, &.{html});
    try expectChildren(s, html, &.{body});
    try testing.expectEqual(4, s.nodeCount());
}

test "FP-0009 case 9: removing the yielded child keeps iteration exact, and a child inserted before the recorded next sibling is not visited" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const parent = try newElement(s, document, "ul");
    const elsewhere = try newElement(s, document, "ol");
    var originals: [6]NodeHandle = undefined;
    for (&originals) |*child| {
        child.* = try newElement(s, document, "li");
        try appendChecked(s, parent, child.*);
    }
    const inserted = try newElement(s, document, "inserted");
    const appended = try newElement(s, document, "appended");

    var visits: [8]NodeHandle = undefined;
    var visit_count: usize = 0;
    var iterator = try s.children(parent);
    while (iterator.next()) |child| {
        try testing.expect(visit_count < visits.len);
        visits[visit_count] = child;
        visit_count += 1;
        if (sameNode(child, originals[1])) {
            // Remove the yielded child.
            try removeChecked(s, parent, child);
        } else if (sameNode(child, originals[2])) {
            // Insert before the recorded next sibling.
            try insertChecked(s, parent, inserted, originals[3]);
        } else if (sameNode(child, originals[3])) {
            // Move the yielded child to another parent.
            try appendChecked(s, elsewhere, child);
        } else if (sameNode(child, originals[5])) {
            // The recorded next sibling of the last child is null.
            try appendChecked(s, parent, appended);
        }
    }
    try testing.expectEqual(originals.len, visit_count);
    for (originals, visits[0..visit_count]) |original, visit| try testing.expect(sameNode(original, visit));
    try expectChildren(s, parent, &.{ originals[0], originals[2], inserted, originals[4], originals[5], appended });
    try expectChildren(s, elsewhere, &.{originals[3]});

    // Removing every yielded child empties the parent and visits each child once.
    visit_count = 0;
    iterator = try s.children(parent);
    while (iterator.next()) |child| {
        try testing.expect(visit_count < visits.len);
        visits[visit_count] = child;
        visit_count += 1;
        try removeChecked(s, parent, child);
    }
    try testing.expectEqual(6, visit_count);
    try expectChildren(s, parent, &.{});
}

test "FP-0009 case 10: destroying a store with documents, retained nodes, and detached subtrees leaks nothing" {
    var counting: testing.FailingAllocator = .init(testing.allocator, .{});
    var store = try Store.init(counting.allocator());
    const s = &store;

    const document = try newDocument(s);
    const other_document = try newDocument(s);
    const html = try newElement(s, document, "html");
    try appendChecked(s, document, html);
    try appendChecked(s, html, try newText(s, document, "connected text"));
    const retained = try newElement(s, document, "retained");
    try appendChecked(s, retained, try newComment(s, document, "retained comment"));
    try retainChecked(s, retained);
    try retainChecked(s, retained);
    const detached = try newElement(s, other_document, "detached");
    try appendChecked(s, detached, try newProcessingInstruction(s, other_document, "detached instruction"));
    try appendChecked(s, detached, try s.createElement(other_document, null, ascii("no-namespace")));
    const fragment = try newFragment(s, other_document);
    try appendChecked(s, fragment, try newText(s, other_document, "fragment text"));
    try retainChecked(s, document);
    _ = try newDoctype(s, document);
    _ = try newText(s, document, "");

    try testing.expect(counting.allocations > 0);
    try testing.expect(s.nodeCount() > 10);
    store.deinit();
    try testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);
    try testing.expectEqual(counting.allocations, counting.deallocations);
}

fn OperationPayload(comptime operation: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(operation)).@"fn".return_type.?).error_union.payload;
}

/// Runs one store operation and checks that a failure is `OutOfMemory` and leaves the store unchanged.
fn guarded(store: *Store, comptime operation: anytype, args: anytype) !OperationPayload(operation) {
    const before = fingerprint(store);
    const result = @call(.auto, operation, args) catch |err| {
        try testing.expectEqual(error.OutOfMemory, err);
        try testing.expectEqual(before, fingerprint(store));
        try expectInvariants(store);
        return err;
    };
    try expectInvariants(store);
    return result;
}

fn allocationScenario(gpa: Allocator) !void {
    var store = try Store.init(gpa);
    defer store.deinit();
    const s = &store;

    const document = try guarded(s, Store.createDocument, .{s});
    const other_document = try guarded(s, Store.createDocument, .{s});
    const html = try guarded(s, Store.createElement, .{ s, document, html_namespace, ascii("html") });
    try appendChecked(s, document, html);
    try appendChecked(s, document, try guarded(s, Store.createComment, .{ s, document, ascii("after html") }));

    var sections: [6]NodeHandle = undefined;
    for (&sections, 0..) |*section, index| {
        section.* = try guarded(s, Store.createElement, .{ s, document, null, ascii("section") });
        const units = [_]u16{ 0x0061, 0xD800, @intCast(index) };
        const text = try guarded(s, Store.createText, .{ s, document, View{ .units = &units } });
        try appendChecked(s, section.*, text);
        try appendChecked(s, html, section.*);
    }
    const fragment = try guarded(s, Store.createDocumentFragment, .{ s, document });
    try appendChecked(s, fragment, try guarded(s, Store.createProcessingInstruction, .{ s, document, ascii("instruction") }));
    try appendChecked(s, fragment, try guarded(s, Store.createText, .{ s, document, ascii("") }));
    try insertChecked(s, html, fragment, sections[1]);
    const doctype = try guarded(s, Store.createDocumentType, .{ s, other_document });

    try adoptChecked(s, sections[2], other_document);
    try appendChecked(s, other_document, sections[2]);
    try insertChecked(s, other_document, doctype, sections[2]);
    try removeChecked(s, html, sections[4]);
    try retainChecked(s, sections[4]);
    try removeChecked(s, html, sections[5]);
    // The sweep frees the emptied fragment and the unretained detached section with its text.
    try testing.expectEqual(3, try sweepChecked(s));
    try testing.expectError(error.StaleHandle, s.nodeKind(fragment));
    try testing.expectError(error.StaleHandle, s.nodeKind(sections[5]));
    try releaseChecked(s, sections[4]);
    try testing.expectEqual(2, try sweepChecked(s));
    try testing.expectError(error.StaleHandle, s.nodeKind(sections[4]));
    try expectChildren(s, other_document, &.{ doctype, sections[2] });
    const section_text = (try s.firstChild(sections[2])).?;
    try testing.expect(sameNode(try s.nodeDocument(section_text), other_document));
}

test "FP-0009 case 11: every induced allocation failure returns OutOfMemory, changes nothing, and leaks nothing" {
    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    var probe: testing.FailingAllocator = .init(no_remap.allocator(), .{});
    try allocationScenario(probe.allocator());
    try testing.expect(probe.allocations >= 15);
    try testing.checkAllAllocationFailures(no_remap.allocator(), allocationScenario, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

test "FP-0009 case 12: a handle from another store returns WrongOwner, and a handle to a swept node returns StaleHandle" {
    var mine = try Store.init(testing.allocator);
    defer mine.deinit();
    var theirs = try Store.init(testing.allocator);
    defer theirs.deinit();
    const s = &mine;
    try testing.expect(mine.nodes.owner != theirs.nodes.owner);

    const document = try newDocument(s);
    const parent = try newElement(s, document, "div");
    const child = try newElement(s, document, "p");
    try appendChecked(s, document, parent);
    try appendChecked(s, parent, child);
    const foreign_document = try newDocument(&theirs);
    const foreign_element = try newElement(&theirs, foreign_document, "div");

    // Only the detached node is unreachable, so the sweep frees exactly it.
    const swept = try newElement(s, document, "swept");
    try testing.expectEqual(1, try sweepChecked(s));

    const cases = [_]struct { node: NodeHandle, expected: anyerror }{
        .{ .node = foreign_document, .expected = error.WrongOwner },
        .{ .node = foreign_element, .expected = error.WrongOwner },
        .{ .node = swept, .expected = error.StaleHandle },
    };
    for (cases) |case| {
        const node = case.node;
        const expected = case.expected;
        try expectRejected(s, expected, Store.nodeKind, .{ s, node });
        try expectRejected(s, expected, Store.nodeDocument, .{ s, node });
        try expectRejected(s, expected, Store.parentNode, .{ s, node });
        try expectRejected(s, expected, Store.firstChild, .{ s, node });
        try expectRejected(s, expected, Store.lastChild, .{ s, node });
        try expectRejected(s, expected, Store.previousSibling, .{ s, node });
        try expectRejected(s, expected, Store.nextSibling, .{ s, node });
        try expectRejected(s, expected, Store.characterData, .{ s, node });
        try expectRejected(s, expected, Store.elementName, .{ s, node });
        try expectRejected(s, expected, Store.children, .{ s, node });
        try expectRejected(s, expected, Store.createDocumentFragment, .{ s, node });
        try expectRejected(s, expected, Store.createDocumentType, .{ s, node });
        try expectRejected(s, expected, Store.createElement, .{ s, node, html_namespace, ascii("x") });
        try expectRejected(s, expected, Store.createText, .{ s, node, ascii("x") });
        try expectRejected(s, expected, Store.createComment, .{ s, node, ascii("x") });
        try expectRejected(s, expected, Store.createProcessingInstruction, .{ s, node, ascii("x") });
        try expectRejected(s, expected, Store.appendChild, .{ s, node, child });
        try expectRejected(s, expected, Store.appendChild, .{ s, parent, node });
        try expectRejected(s, expected, Store.insertBefore, .{ s, node, child, null });
        try expectRejected(s, expected, Store.insertBefore, .{ s, parent, node, child });
        try expectRejected(s, expected, Store.insertBefore, .{ s, parent, child, node });
        try expectRejected(s, expected, Store.replaceChild, .{ s, node, child, child });
        try expectRejected(s, expected, Store.replaceChild, .{ s, parent, node, child });
        try expectRejected(s, expected, Store.replaceChild, .{ s, parent, child, node });
        try expectRejected(s, expected, Store.removeChild, .{ s, node, child });
        try expectRejected(s, expected, Store.removeChild, .{ s, parent, node });
        try expectRejected(s, expected, Store.adopt, .{ s, node, document });
        try expectRejected(s, expected, Store.adopt, .{ s, child, node });
        try expectRejected(s, expected, Store.retain, .{ s, node });
        try expectRejected(s, expected, Store.release, .{ s, node });
    }
    try expectChildren(s, parent, &.{child});
    try testing.expectEqual(2, theirs.nodeCount());
}

const ExpectedAttribute = struct { namespace: ?View, local_name: View, value: View };

/// Checks the attribute list of `element` in order through `attributes`.
fn expectAttributes(store: *Store, element: NodeHandle, expected: []const ExpectedAttribute) !void {
    var iterator = try store.attributes(element);
    for (expected) |wanted| {
        const actual = iterator.next() orelse return error.TestExpectedAttribute;
        if (wanted.namespace) |namespace| {
            try testing.expect(actual.namespace.?.eql(namespace));
        } else {
            try testing.expectEqual(null, actual.namespace);
        }
        try testing.expect(actual.local_name.eql(wanted.local_name));
        try testing.expect(actual.value.eql(wanted.value));
    }
    try testing.expectEqual(null, iterator.next());
}

fn expectClasses(store: *Store, element: NodeHandle, expected: []const View) !void {
    const set = try store.classes(testing.allocator, element);
    defer testing.allocator.free(set);
    try testing.expectEqual(expected.len, set.len);
    for (expected, set) |wanted, actual| try testing.expect(actual.eql(wanted));
}

test "FP-0014 case 18: setAttribute keeps list order, replaces in place, and honors namespaces, and removal reports its result" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const element = try newElement(s, document, "e");
    const urn = ascii("urn:x");

    try s.setAttribute(element, null, ascii("b"), ascii("1"));
    try s.setAttribute(element, null, ascii("a"), ascii("2"));
    try s.setAttribute(element, urn, ascii("b"), ascii("3"));
    try expectAttributes(s, element, &.{
        .{ .namespace = null, .local_name = ascii("b"), .value = ascii("1") },
        .{ .namespace = null, .local_name = ascii("a"), .value = ascii("2") },
        .{ .namespace = urn, .local_name = ascii("b"), .value = ascii("3") },
    });

    // Setting an existing attribute keeps its list position.
    try s.setAttribute(element, null, ascii("b"), ascii("4"));
    try expectAttributes(s, element, &.{
        .{ .namespace = null, .local_name = ascii("b"), .value = ascii("4") },
        .{ .namespace = null, .local_name = ascii("a"), .value = ascii("2") },
        .{ .namespace = urn, .local_name = ascii("b"), .value = ascii("3") },
    });
    try testing.expect((try s.attribute(element, null, ascii("b"))).?.eql(ascii("4")));
    try testing.expect((try s.attribute(element, ascii(""), ascii("b"))).?.eql(ascii("4")));
    try testing.expect((try s.attribute(element, urn, ascii("b"))).?.eql(ascii("3")));
    try testing.expectEqual(null, try s.attribute(element, null, ascii("B")));

    // An empty namespace means no namespace.
    try s.setAttribute(element, ascii(""), ascii("c"), ascii("5"));
    try testing.expect((try s.attribute(element, null, ascii("c"))).?.eql(ascii("5")));

    try testing.expect(try s.removeAttribute(element, null, ascii("a")));
    try testing.expect(!try s.removeAttribute(element, null, ascii("a")));
    try expectAttributes(s, element, &.{
        .{ .namespace = null, .local_name = ascii("b"), .value = ascii("4") },
        .{ .namespace = urn, .local_name = ascii("b"), .value = ascii("3") },
        .{ .namespace = null, .local_name = ascii("c"), .value = ascii("5") },
    });

    // A lone surrogate round-trips.
    const lone = [_]u16{ 'x', 0xD800 };
    try s.setAttribute(element, null, ascii("d"), .{ .units = &lone });
    try testing.expectEqualSlices(u16, &lone, (try s.attribute(element, null, ascii("d"))).?.units);
    try expectInvariants(s);
}

test "FP-0014 case 19: the ID follows the ID attribute change steps, and classes follow the ordered set parser" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const element = try newElement(s, document, "e");

    try testing.expectEqual(null, try s.elementId(element));
    try s.setAttribute(element, null, ascii("id"), ascii(""));
    try testing.expectEqual(null, try s.elementId(element));
    try s.setAttribute(element, null, ascii("id"), ascii("x y"));
    try testing.expect((try s.elementId(element)).?.eql(ascii("x y")));
    const namespaced = try newElement(s, document, "n");
    try s.setAttribute(namespaced, ascii("urn:x"), ascii("id"), ascii("z"));
    try testing.expectEqual(null, try s.elementId(namespaced));

    try expectClasses(s, element, &.{});
    try s.setAttribute(element, null, ascii("class"), ascii(" a\tb\na  c\x0c"));
    try expectClasses(s, element, &.{ ascii("a"), ascii("b"), ascii("c") });
    const nbsp = [_]u16{ 'a', 0x00A0, 'b' };
    try s.setAttribute(element, null, ascii("class"), .{ .units = &nbsp });
    try expectClasses(s, element, &.{.{ .units = &nbsp }});
    try s.setAttribute(namespaced, ascii("urn:x"), ascii("class"), ascii("q"));
    try expectClasses(s, namespaced, &.{});
}

fn attributeAllocationScenario(gpa: Allocator) !void {
    var store = try Store.init(gpa);
    defer store.deinit();
    const s = &store;
    const document = try guarded(s, Store.createDocument, .{s});
    const element = try guarded(s, Store.createElement, .{ s, document, null, ascii("e") });
    try guarded(s, Store.setAttribute, .{ s, element, null, ascii("a"), ascii("1") });
    try guarded(s, Store.setAttribute, .{ s, element, ascii("urn:x"), ascii("a"), ascii("2") });
    try guarded(s, Store.setAttribute, .{ s, element, null, ascii("b"), ascii("3") });
    // A replacement copies the new value before it changes the store.
    try guarded(s, Store.setAttribute, .{ s, element, null, ascii("a"), ascii("4") });
    try testing.expect(try s.removeAttribute(element, ascii("urn:x"), ascii("a")));
    try expectAttributes(s, element, &.{
        .{ .namespace = null, .local_name = ascii("a"), .value = ascii("4") },
        .{ .namespace = null, .local_name = ascii("b"), .value = ascii("3") },
    });
}

test "FP-0014 case 20: attribute operations reject bad handles, and each induced allocation failure changes nothing and leaks nothing" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    var other = try Store.init(testing.allocator);
    defer other.deinit();
    const s = &store;
    const document = try newDocument(s);
    const text = try newText(s, document, "t");
    try expectRejected(s, error.NotAnElement, Store.setAttribute, .{ s, text, null, ascii("a"), ascii("1") });
    try expectRejected(s, error.NotAnElement, Store.attribute, .{ s, document, null, ascii("a") });
    try expectRejected(s, error.NotAnElement, Store.removeAttribute, .{ s, text, null, ascii("a") });
    try expectRejected(s, error.NotAnElement, Store.attributes, .{ s, text });
    try expectRejected(s, error.NotAnElement, Store.elementId, .{ s, text });
    try expectRejected(s, error.NotAnElement, Store.classes, .{ s, testing.allocator, text });

    // A detached element with attributes is swept without a leak.
    const swept = try newElement(s, document, "swept");
    try s.setAttribute(swept, null, ascii("class"), ascii("a b"));
    try s.setAttribute(swept, ascii("urn:x"), ascii("id"), ascii("i"));
    try testing.expectEqual(2, try sweepChecked(s));
    try expectRejected(s, error.StaleHandle, Store.setAttribute, .{ s, swept, null, ascii("a"), ascii("1") });
    try expectRejected(s, error.StaleHandle, Store.attribute, .{ s, swept, null, ascii("a") });

    const foreign_document = try newDocument(&other);
    const foreign = try newElement(&other, foreign_document, "f");
    try expectRejected(s, error.WrongOwner, Store.setAttribute, .{ s, foreign, null, ascii("a"), ascii("1") });
    try expectRejected(s, error.WrongOwner, Store.removeAttribute, .{ s, foreign, null, ascii("a") });

    // Store teardown frees the attributes of a connected element.
    const kept = try newElement(s, document, "kept");
    try appendChecked(s, document, kept);
    try s.setAttribute(kept, null, ascii("a"), ascii("1"));

    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    var probe: testing.FailingAllocator = .init(no_remap.allocator(), .{});
    try attributeAllocationScenario(probe.allocator());
    try testing.expect(probe.allocations >= 10);
    try testing.checkAllAllocationFailures(no_remap.allocator(), attributeAllocationScenario, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

/// The FP-0014 revision 1 class scenario: `classes` deduplicates in order, `hasClass` agrees with it,
/// and an induced allocation failure in `classes` leaves the store unchanged.
fn classAllocationScenario(gpa: Allocator) !void {
    var store = try Store.init(gpa);
    defer store.deinit();
    const s = &store;
    const document = try guarded(s, Store.createDocument, .{s});
    const element = try guarded(s, Store.createElement, .{ s, document, null, ascii("e") });
    try guarded(s, Store.setAttribute, .{ s, element, null, ascii("class"), ascii("b a\tb c a\x0cd b") });
    const set = try guarded(s, Store.classes, .{ s, gpa, element });
    defer gpa.free(set);
    const expected = [_]View{ ascii("b"), ascii("a"), ascii("c"), ascii("d") };
    try testing.expectEqual(expected.len, set.len);
    for (expected, set) |wanted, actual| try testing.expect(actual.eql(wanted));
    for (expected) |class| try testing.expect(try s.hasClass(element, class));
    try testing.expect(!try s.hasClass(element, ascii("e")));
    try testing.expect(!try s.hasClass(element, ascii("")));
}

test "FP-0014 revision 1: classes deduplicate in order, hasClass agrees, and both reject non-elements" {
    var store = try Store.init(testing.allocator);
    defer store.deinit();
    const s = &store;
    const document = try newDocument(s);
    const text = try newText(s, document, "t");
    try expectRejected(s, error.NotAnElement, Store.hasClass, .{ s, text, ascii("a") });
    try expectRejected(s, error.NotAnElement, Store.classes, .{ s, testing.allocator, text });
    const plain = try newElement(s, document, "p");
    try testing.expect(!try s.hasClass(plain, ascii("a")));
    try expectClasses(s, plain, &.{});

    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_remap.allocator(), classAllocationScenario, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}
