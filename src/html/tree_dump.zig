//! The tree dump: the `#document` format of the tree construction tests in
//! `html/syntax/parsing/resources/README.md` of WPT commit `b60c4b349d9d167bf354a40bc0d4cbed15174606`.
//!
//! Each descendant of the root, in tree order, becomes one line: `| `, two spaces for each ancestor between the node and
//! the root, the node text, and LF. An element is `<` + its tag name string + `>`, and its attributes follow it one level
//! deeper as `name="value"`, sorted by the attribute name string in UTF-16 code unit order. Text is `"` + data + `"`,
//! a comment is `<!-- ` + data + ` -->`, a doctype is `<!DOCTYPE ` + name + `>`, or, when its public or system ID is not
//! empty, `<!DOCTYPE ` + name + ` "` + public ID + `" "` + system ID + `">`, and a processing instruction is
//! `<?` + target + ` ` + data + `?>`.
//!
//! Unlike `serializeTree` in that directory's `test.js`, the dump does not normalize the tree first, so adjacent text
//! nodes are written separately. Nothing is escaped, so a line break in data starts a new line without the `| ` prefix.
//! Each code point is written in UTF-8, and a lone surrogate in its three-byte generalized UTF-8 form.
//! An element in no namespace or another namespace, or an attribute in a namespace other than XLink, XML, or XMLNS,
//! has no tag or attribute name string, so it makes the dump fail with `error.UndumpableNamespace`.
//! The traversal uses the tree links and no recursion, and the dump allocates nothing.

const std = @import("std");
const dom = @import("../dom.zig");
const web_string = @import("../web_string.zig");
const Writer = std.Io.Writer;
const View = web_string.View;
const NodeHandle = dom.NodeHandle;

pub const Error = Writer.Error || dom.LookupError || error{UndumpableNamespace};

fn ascii(comptime text: []const u8) []const u16 {
    const units = comptime blk: {
        var buffer: [text.len]u16 = undefined;
        for (text, &buffer) |byte, *unit| unit.* = byte;
        break :blk buffer;
    };
    return &units;
}

const html_namespace = ascii("http://www.w3.org/1999/xhtml");
const svg_namespace = ascii("http://www.w3.org/2000/svg");
const mathml_namespace = ascii("http://www.w3.org/1998/Math/MathML");
const xlink_namespace = ascii("http://www.w3.org/1999/xlink");
const xml_namespace = ascii("http://www.w3.org/XML/1998/namespace");
const xmlns_namespace = ascii("http://www.w3.org/2000/xmlns/");

/// Writes one line for each descendant of `root`, in tree order.
pub fn writeChildren(store: *dom.Store, root: NodeHandle, w: *Writer) Error!void {
    var depth: usize = 0;
    var cursor = try store.firstChild(root);
    while (cursor) |node| {
        try writeNode(store, node, depth, w);
        if (try store.firstChild(node)) |child| {
            depth += 1;
            cursor = child;
            continue;
        }
        // Climb until a node has a next sibling, stopping at the root.
        var current = node;
        cursor = null;
        while (true) {
            if (try store.nextSibling(current)) |sibling| {
                cursor = sibling;
                break;
            }
            if (depth == 0) break;
            depth -= 1;
            current = (try store.parentNode(current)).?;
        }
    }
}

fn writePrefix(w: *Writer, depth: usize) Writer.Error!void {
    try w.writeAll("| ");
    try w.splatByteAll(' ', 2 * depth);
}

fn writeNode(store: *dom.Store, node: NodeHandle, depth: usize, w: *Writer) Error!void {
    switch (try store.nodeKind(node)) {
        .element => {
            const name = (try store.elementName(node)).?;
            const prefix = try elementPrefix(name.namespace);
            try writePrefix(w, depth);
            try w.writeByte('<');
            try w.writeAll(prefix);
            try writeUnits(w, name.local_name.units);
            try w.writeAll(">\n");
            try writeAttributes(store, node, depth + 1, w);
        },
        .text => {
            try writePrefix(w, depth);
            try w.writeByte('"');
            try writeUnits(w, (try store.characterData(node)).?.units);
            try w.writeAll("\"\n");
        },
        .comment => {
            try writePrefix(w, depth);
            try w.writeAll("<!-- ");
            try writeUnits(w, (try store.characterData(node)).?.units);
            try w.writeAll(" -->\n");
        },
        .processing_instruction => {
            try writePrefix(w, depth);
            try w.writeAll("<?");
            try writeUnits(w, (try store.processingInstructionTarget(node)).?.units);
            try w.writeByte(' ');
            try writeUnits(w, (try store.characterData(node)).?.units);
            try w.writeAll("?>\n");
        },
        .document_type => {
            const ids = (try store.documentTypeIds(node)).?;
            try writePrefix(w, depth);
            try w.writeAll("<!DOCTYPE ");
            try writeUnits(w, ids.name.units);
            if (ids.public_id.units.len != 0 or ids.system_id.units.len != 0) {
                try w.writeAll(" \"");
                try writeUnits(w, ids.public_id.units);
                try w.writeAll("\" \"");
                try writeUnits(w, ids.system_id.units);
                try w.writeByte('"');
            }
            try w.writeAll(">\n");
        },
        // A document or a fragment is never a child.
        .document, .document_fragment => unreachable,
    }
}

/// Returns the prefix of an element's tag name string.
fn elementPrefix(namespace: ?View) error{UndumpableNamespace}![]const u8 {
    const units = (namespace orelse return error.UndumpableNamespace).units;
    if (std.mem.eql(u16, units, html_namespace)) return "";
    if (std.mem.eql(u16, units, svg_namespace)) return "svg ";
    if (std.mem.eql(u16, units, mathml_namespace)) return "math ";
    return error.UndumpableNamespace;
}

/// Returns the prefix of an attribute's name string.
fn attributePrefix(namespace: ?View) error{UndumpableNamespace}![]const u8 {
    const units = (namespace orelse return "").units;
    if (std.mem.eql(u16, units, xlink_namespace)) return "xlink ";
    if (std.mem.eql(u16, units, xml_namespace)) return "xml ";
    if (std.mem.eql(u16, units, xmlns_namespace)) return "xmlns ";
    return error.UndumpableNamespace;
}

/// An attribute's name string, as its prefix and its local name, with its list position, which breaks ties.
const SortKey = struct {
    prefix: []const u8,
    local_name: []const u16,
    position: usize,

    /// Returns the code unit at `index` of the name string, or null after its end.
    fn unit(key: SortKey, index: usize) ?u16 {
        if (index < key.prefix.len) return key.prefix[index];
        const rest = index - key.prefix.len;
        return if (rest < key.local_name.len) key.local_name[rest] else null;
    }

    /// Orders by the name string in UTF-16 code unit order, and then by list position.
    fn lessThan(a: SortKey, b: SortKey) bool {
        var index: usize = 0;
        while (true) : (index += 1) {
            const left = a.unit(index);
            const right = b.unit(index);
            if (left == null and right == null) return a.position < b.position;
            const l = left orelse return true;
            const r = right orelse return false;
            if (l != r) return l < r;
        }
    }
};

fn attributesOf(store: *dom.Store, element: NodeHandle) Error!dom.AttributeIterator {
    return store.attributes(element) catch |err| switch (err) {
        error.NotAnElement => unreachable,
        else => |lookup| lookup,
    };
}

/// Writes the attributes of `element` in the order of their name strings. Each step selects the least key after
/// the previous one, so the order needs no storage; an element with n attributes takes time proportional to n².
fn writeAttributes(store: *dom.Store, element: NodeHandle, depth: usize, w: *Writer) Error!void {
    var previous: ?SortKey = null;
    while (true) {
        var best: ?SortKey = null;
        var best_value: View = undefined;
        var iterator = try attributesOf(store, element);
        var position: usize = 0;
        while (iterator.next()) |attribute| : (position += 1) {
            const key: SortKey = .{ .prefix = try attributePrefix(attribute.namespace), .local_name = attribute.local_name.units, .position = position };
            if (previous) |last| {
                if (!last.lessThan(key)) continue;
            }
            if (best == null or key.lessThan(best.?)) {
                best = key;
                best_value = attribute.value;
            }
        }
        const chosen = best orelse return;
        try writePrefix(w, depth);
        try w.writeAll(chosen.prefix);
        try writeUnits(w, chosen.local_name);
        try w.writeAll("=\"");
        try writeUnits(w, best_value.units);
        try w.writeAll("\"\n");
        previous = chosen;
    }
}

/// Writes each code point of `units` in UTF-8, and a lone surrogate in its generalized UTF-8 form.
fn writeUnits(w: *Writer, units: []const u16) Writer.Error!void {
    var code_points: web_string.CodePointIterator = .{ .units = units };
    while (code_points.next()) |code_point| {
        var bytes: [4]u8 = undefined;
        const length = std.unicode.wtf8Encode(code_point, &bytes) catch unreachable;
        try w.writeAll(bytes[0..length]);
    }
}
