//! Selectors Level 4: `<selector-list>` (section 16) for the frozen subset, specificity (section 15),
//! and matching against the DOM store.
//!
//! The frozen subset is type and universal selectors with `*|` and `|` namespace prefixes, class, ID, and attribute
//! selectors with every matcher and the `i` and `s` modifiers, and the descendant, child, next-sibling, and
//! subsequent-sibling combinators. Pseudo-classes, pseudo-elements, declared namespace prefixes, nesting,
//! and the column combinator `||` of Selectors 5 are standard constructs outside the subset and report
//! `unsupported_selector`.
//!
//! Every store document is an XML document, so names, IDs, classes, and attribute values compare by identical
//! code units (section 3.7); the `i` modifier compares attribute values ASCII case-insensitively.
//! No default namespace is declared, so `E` and `*|E` match any namespace (section 5.3).
//!
//! Matching keeps an explicit stack of open combinators, so no function recurses. It gives up on the whole selector
//! as soon as a descendant or child combinator has no ancestor left to try, because any other candidate for the
//! compounds to its right has only a subset of those ancestors. Each descendant combinator therefore walks the
//! ancestors at most once per match. Task `FP-0070` owns a constant-time ancestor filter for deep trees.

const std = @import("std");
const builtin = @import("builtin");
const dom = @import("../dom.zig");
const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");
const applicable = @import("applicable.zig");
const stylesheet = @import("stylesheet.zig");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const ComponentValue = parser.ComponentValue;
const Range = parser.Range;
const NodeHandle = dom.NodeHandle;
const View = web_string.View;
const Specificity = applicable.Specificity;
const ApplicableDeclaration = applicable.ApplicableDeclaration;

/// Test-only instrumentation, compiled only in test builds.
/// `compound_match_attempts` counts each attempt to match a compound against an element, which case 53 of FP-0014 bounds.
pub const test_counters = if (builtin.is_test) struct {
    pub var compound_match_attempts: usize = 0;
} else struct {};

/// The namespace that a type, universal, or attribute selector requires.
pub const NamespaceConstraint = enum {
    /// Any namespace, or no namespace.
    any,
    /// No namespace.
    none,
};

pub const TypeSelector = struct {
    namespace: NamespaceConstraint,
    /// The local name, or null for the universal selector.
    name: ?[]const u16,
};

pub const AttributeOperator = enum {
    /// `=`
    equals,
    /// `~=`
    includes,
    /// `|=`
    dash_match,
    /// `^=`
    prefix,
    /// `$=`
    suffix,
    /// `*=`
    substring,
};

pub const CaseModifier = enum { none, i, s };

pub const AttributeSelector = struct {
    namespace: NamespaceConstraint,
    name: []const u16,
    /// Null for a presence selector.
    operator: ?AttributeOperator,
    value: []const u16,
    modifier: CaseModifier,
};

pub const SimpleSelector = union(enum) {
    id: []const u16,
    class: []const u16,
    attribute: AttributeSelector,
};

pub const Compound = struct {
    type_selector: ?TypeSelector,
    simples: []const SimpleSelector,
};

pub const Combinator = enum { descendant, child, next_sibling, subsequent_sibling };

pub const ComplexSelector = struct {
    /// In source order.
    compounds: []const Compound,
    /// `combinators[i]` joins `compounds[i]` and `compounds[i + 1]`.
    combinators: []const Combinator,
    specificity: Specificity,
};

pub const SelectorList = struct {
    selectors: []const ComplexSelector,
};

pub const FailureKind = enum { invalid_selector, unsupported_selector };

pub const Failure = struct {
    kind: FailureKind,
    range: Range,
};

pub const ParseResult = union(enum) {
    list: SelectorList,
    failure: Failure,
};

/// Parses a style rule's prelude as a `<selector-list>`. A list with any invalid selector is invalid (section 3.9),
/// and the first problem in token order decides the failure. Results are allocated in `arena`.
pub fn parseSelectorList(arena: Allocator, prelude: []const ComponentValue) Allocator.Error!ParseResult {
    // The top-level items, where whitespace is significant as the descendant combinator.
    var tops: std.ArrayList(usize) = .empty;
    var index: usize = 0;
    while (index < prelude.len) : (index = parser.nextItem(prelude, index)) try tops.append(arena, index);
    var p: SelectorParser = .{ .arena = arena, .prelude = prelude, .tops = tops.items };
    return p.parse();
}

const SelectorParser = struct {
    arena: Allocator,
    prelude: []const ComponentValue,
    tops: []const usize,
    position: usize = 0,
    failure: Failure = undefined,

    const Error = Allocator.Error || error{Failed};

    fn at(p: *const SelectorParser, offset: usize) ?ComponentValue {
        const position = p.position + offset;
        return if (position < p.tops.len) p.prelude[p.tops[position]] else null;
    }

    fn atDelim(p: *const SelectorParser, offset: usize, code_point: u21) bool {
        const value = p.at(offset) orelse return false;
        return value.isDelim(code_point);
    }

    fn atToken(p: *const SelectorParser, offset: usize, kind: tokenizer.TokenKind) bool {
        const value = p.at(offset) orelse return false;
        return value.isToken(kind);
    }

    /// Whether the item at `offset` is a function, which starts with a <function-token>.
    fn atFunction(p: *const SelectorParser, offset: usize) bool {
        const value = p.at(offset) orelse return false;
        return value.kind == .function;
    }

    fn skipWhitespace(p: *SelectorParser) bool {
        var skipped = false;
        while (p.atToken(0, .whitespace)) {
            p.position += 1;
            skipped = true;
        }
        return skipped;
    }

    /// The source range of the item at `offset`, or the empty range at the end of the prelude.
    fn rangeAt(p: *const SelectorParser, offset: usize) Range {
        if (p.at(offset)) |value| return value.range();
        const end = if (p.prelude.len == 0) 0 else lastEnd(p.prelude);
        return .{ .start = end, .end = end };
    }

    fn fail(p: *SelectorParser, kind: FailureKind, offset: usize) error{Failed} {
        p.failure = .{ .kind = kind, .range = p.rangeAt(offset) };
        return error.Failed;
    }

    fn parse(p: *SelectorParser) Allocator.Error!ParseResult {
        const list = p.selectorList() catch |err| switch (err) {
            error.Failed => return .{ .failure = p.failure },
            error.OutOfMemory => return error.OutOfMemory,
        };
        return .{ .list = list };
    }

    fn selectorList(p: *SelectorParser) Error!SelectorList {
        var selectors: std.ArrayList(ComplexSelector) = .empty;
        _ = p.skipWhitespace();
        while (true) {
            try selectors.append(p.arena, try p.complexSelector());
            // complexSelector stops at the end or at a comma.
            if (p.at(0) == null) break;
            p.position += 1;
            _ = p.skipWhitespace();
        }
        return .{ .selectors = selectors.items };
    }

    fn complexSelector(p: *SelectorParser) Error!ComplexSelector {
        var compounds: std.ArrayList(Compound) = .empty;
        var combinators: std.ArrayList(Combinator) = .empty;
        var specificity: Specificity = .{};
        while (true) {
            try compounds.append(p.arena, try p.compound(&specificity));
            const whitespace = p.skipWhitespace();
            const next = p.at(0) orelse break;
            if (next.isToken(.comma)) break;
            // The column combinator `||` (`selectors-5/Overview.bs` line 462 at the pinned commit) is outside the subset.
            if (next.isDelim('|') and p.atDelim(1, '|')) return p.fail(.unsupported_selector, 0);
            const combinator: Combinator = if (next.isDelim('>'))
                .child
            else if (next.isDelim('+'))
                .next_sibling
            else if (next.isDelim('~'))
                .subsequent_sibling
            else if (whitespace)
                .descendant
            else
                return p.fail(.invalid_selector, 0);
            if (combinator != .descendant) {
                p.position += 1;
                _ = p.skipWhitespace();
            }
            try combinators.append(p.arena, combinator);
        }
        return .{ .compounds = compounds.items, .combinators = combinators.items, .specificity = specificity };
    }

    /// A `<compound-selector>`: an optional type selector, then subclass selectors without whitespace.
    fn compound(p: *SelectorParser, specificity: *Specificity) Error!Compound {
        var type_selector: ?TypeSelector = null;
        if (p.at(0)) |first| {
            if (first.isToken(.ident)) {
                // `E||F` is the type selector `E` and the column combinator.
                if (p.atDelim(1, '|') and !p.atDelim(2, '|')) {
                    // A declared namespace prefix, such as `ns|E`, needs `@namespace`.
                    if (p.atToken(2, .ident) or p.atDelim(2, '*')) return p.fail(.unsupported_selector, 0);
                    return p.fail(.invalid_selector, 1);
                }
                type_selector = .{ .namespace = .any, .name = first.token.value };
                p.position += 1;
            } else if (first.isDelim('*')) {
                if (p.atDelim(1, '|') and !p.atDelim(2, '|')) {
                    if (p.atToken(2, .ident)) {
                        type_selector = .{ .namespace = .any, .name = p.at(2).?.token.value };
                    } else if (p.atDelim(2, '*')) {
                        type_selector = .{ .namespace = .any, .name = null };
                    } else {
                        return p.fail(.invalid_selector, 2);
                    }
                    p.position += 3;
                } else {
                    type_selector = .{ .namespace = .any, .name = null };
                    p.position += 1;
                }
            } else if (first.isDelim('|')) {
                if (p.atToken(1, .ident)) {
                    type_selector = .{ .namespace = .none, .name = p.at(1).?.token.value };
                } else if (p.atDelim(1, '*')) {
                    type_selector = .{ .namespace = .none, .name = null };
                } else {
                    return p.fail(.invalid_selector, 1);
                }
                p.position += 2;
            }
        }
        if (type_selector) |selector| {
            if (selector.name != null) specificity.c +|= 1;
        }
        var simples: std.ArrayList(SimpleSelector) = .empty;
        while (p.at(0)) |value| {
            if (value.isToken(.hash)) {
                // The hash token's value must be an identifier.
                if (value.token.hash_type != .id) return p.fail(.invalid_selector, 0);
                try simples.append(p.arena, .{ .id = value.token.value });
                specificity.a +|= 1;
                p.position += 1;
            } else if (value.isDelim('.')) {
                if (!p.atToken(1, .ident)) return p.fail(.invalid_selector, 1);
                try simples.append(p.arena, .{ .class = p.at(1).?.token.value });
                specificity.b +|= 1;
                p.position += 2;
            } else if (value.kind == .block and value.token.kind == .open_square) {
                const attribute = try p.attributeSelector(parser.contents(p.prelude, p.tops[p.position]));
                try simples.append(p.arena, .{ .attribute = attribute });
                specificity.b +|= 1;
                p.position += 1;
            } else if (value.isToken(.colon)) {
                // Pseudo-classes and pseudo-elements are outside the subset.
                if (p.atToken(1, .ident) or p.atFunction(1)) return p.fail(.unsupported_selector, 0);
                if (p.atToken(1, .colon) and (p.atToken(2, .ident) or p.atFunction(2))) return p.fail(.unsupported_selector, 0);
                return p.fail(.invalid_selector, 0);
            } else if (value.isDelim('&')) {
                // The nesting selector is outside the subset.
                return p.fail(.unsupported_selector, 0);
            } else {
                break;
            }
        }
        if (type_selector == null and simples.items.len == 0) return p.fail(.invalid_selector, 0);
        return .{ .type_selector = type_selector, .simples = simples.items };
    }

    /// `[ <wq-name> ]` or `[ <wq-name> <attr-matcher> [ <string-token> | <ident-token> ] <attr-modifier>? ]`.
    fn attributeSelector(p: *SelectorParser, list: []const ComponentValue) Error!AttributeSelector {
        var items: std.ArrayList(usize) = .empty;
        var index: usize = 0;
        while (index < list.len) : (index = parser.nextItem(list, index)) try items.append(p.arena, index);
        var a: AttributeParser = .{ .list = list, .items = items.items };
        return a.parse() catch |err| switch (err) {
            error.Failed => {
                p.failure = .{ .kind = a.kind, .range = if (a.offending) |offending| list[offending].range() else p.rangeAt(0) };
                return error.Failed;
            },
        };
    }
};

const AttributeParser = struct {
    list: []const ComponentValue,
    items: []const usize,
    position: usize = 0,
    kind: FailureKind = .invalid_selector,
    /// The list index of the offending item, or null for the attribute selector itself.
    offending: ?usize = null,

    fn at(a: *const AttributeParser, offset: usize) ?ComponentValue {
        const position = a.position + offset;
        return if (position < a.items.len) a.list[a.items[position]] else null;
    }

    fn atDelim(a: *const AttributeParser, offset: usize, code_point: u21) bool {
        const value = a.at(offset) orelse return false;
        return value.isDelim(code_point);
    }

    fn atToken(a: *const AttributeParser, offset: usize, kind: tokenizer.TokenKind) bool {
        const value = a.at(offset) orelse return false;
        return value.isToken(kind);
    }

    fn skipWhitespace(a: *AttributeParser) void {
        while (a.atToken(0, .whitespace)) a.position += 1;
    }

    fn fail(a: *AttributeParser, kind: FailureKind, offset: usize) error{Failed} {
        a.kind = kind;
        const position = a.position + offset;
        a.offending = if (position < a.items.len) a.items[position] else null;
        return error.Failed;
    }

    fn parse(a: *AttributeParser) error{Failed}!AttributeSelector {
        a.skipWhitespace();
        var selector: AttributeSelector = .{ .namespace = .none, .name = &.{}, .operator = null, .value = &.{}, .modifier = .none };
        // <wq-name>, with no whitespace between its components.
        const first = a.at(0) orelse return a.fail(.invalid_selector, 0);
        if (first.isToken(.ident)) {
            if (a.atDelim(1, '|') and (a.atToken(2, .ident) or a.atDelim(2, '*'))) return a.fail(.unsupported_selector, 0);
            selector.name = first.token.value;
            a.position += 1;
        } else if (first.isDelim('*')) {
            if (!a.atDelim(1, '|') or !a.atToken(2, .ident)) return a.fail(.invalid_selector, 0);
            selector.namespace = .any;
            selector.name = a.at(2).?.token.value;
            a.position += 3;
        } else if (first.isDelim('|')) {
            if (!a.atToken(1, .ident)) return a.fail(.invalid_selector, 0);
            selector.name = a.at(1).?.token.value;
            a.position += 2;
        } else {
            return a.fail(.invalid_selector, 0);
        }
        a.skipWhitespace();
        const matcher = a.at(0) orelse return selector;
        // <attr-matcher>, with no whitespace between its components.
        if (matcher.isDelim('=')) {
            selector.operator = .equals;
            a.position += 1;
        } else if (matcher.isToken(.delim) and a.atDelim(1, '=')) {
            selector.operator = switch (matcher.token.delim) {
                '~' => .includes,
                '|' => .dash_match,
                '^' => .prefix,
                '$' => .suffix,
                '*' => .substring,
                else => return a.fail(.invalid_selector, 0),
            };
            a.position += 2;
        } else {
            return a.fail(.invalid_selector, 0);
        }
        a.skipWhitespace();
        const value = a.at(0) orelse return a.fail(.invalid_selector, 0);
        if (!value.isToken(.ident) and !value.isToken(.string)) return a.fail(.invalid_selector, 0);
        selector.value = value.token.value;
        a.position += 1;
        a.skipWhitespace();
        const modifier = a.at(0) orelse return selector;
        if (!modifier.isToken(.ident)) return a.fail(.invalid_selector, 0);
        if (tokenizer.asciiCaseInsensitiveEql(modifier.token.value, "i")) {
            selector.modifier = .i;
        } else if (tokenizer.asciiCaseInsensitiveEql(modifier.token.value, "s")) {
            selector.modifier = .s;
        } else {
            return a.fail(.invalid_selector, 0);
        }
        a.position += 1;
        a.skipWhitespace();
        if (a.at(0) != null) return a.fail(.invalid_selector, 0);
        return selector;
    }
};

fn lastEnd(list: []const ComponentValue) usize {
    var index: usize = 0;
    var last: usize = 0;
    while (index < list.len) : (index = parser.nextItem(list, index)) last = index;
    return list[last].end;
}

pub const MatchError = dom.AttributeError || Allocator.Error;

/// The outcome of matching a compound and every compound to its left at one candidate element,
/// as in Servo's `SelectorMatchingResult`.
const Outcome = enum {
    matched,
    /// The compound failed at its candidate: the nearest descendant or subsequent-sibling combinator to the right
    /// tries its next candidate.
    restart_from_sibling,
    /// The nearest descendant combinator to the right tries its next candidate.
    restart_from_descendant,
    /// No candidate of any combinator to the right can match, so the selector does not match.
    not_matched_globally,
};

/// A combinator whose left side is being tried.
const Frame = struct {
    /// The compound to the combinator's left, which is `compounds[compound]`; the combinator is `combinators[compound]`.
    compound: usize,
    /// The element where that compound is being tried.
    candidate: NodeHandle,
};

/// The outcome when a combinator has no first or next candidate.
fn noCandidate(combinator: Combinator) Outcome {
    return switch (combinator) {
        // An ancestor further up may still have an element sibling.
        .next_sibling, .subsequent_sibling => .restart_from_descendant,
        // No ancestor is left, and every other candidate for the compounds to the right has a subset of these ancestors.
        .child, .descendant => .not_matched_globally,
    };
}

/// A reusable stack of open combinators for matching.
pub const Matcher = struct {
    gpa: Allocator,
    store: *dom.Store,
    stack: std.ArrayList(Frame) = .empty,

    pub fn init(gpa: Allocator, store: *dom.Store) Matcher {
        return .{ .gpa = gpa, .store = store };
    }

    pub fn deinit(m: *Matcher) void {
        m.stack.deinit(m.gpa);
        m.* = undefined;
    }

    /// Whether `selector` matches `element`. Combinators consider element parents and element siblings only.
    /// Each compound is tried from right to left; a failure returns through the open combinators until one of them
    /// tries its next candidate, or until the outcome decides the whole selector.
    pub fn matches(m: *Matcher, element: NodeHandle, selector: *const ComplexSelector) MatchError!bool {
        m.stack.clearRetainingCapacity();
        var compound = selector.compounds.len - 1;
        var candidate = element;
        attempt: while (true) {
            var outcome: Outcome = undefined;
            if (!try m.matchesCompound(candidate, &selector.compounds[compound])) {
                outcome = .restart_from_sibling;
            } else if (compound == 0) {
                outcome = .matched;
            } else {
                const combinator = selector.combinators[compound - 1];
                if (try m.nextCandidate(candidate, combinator)) |first| {
                    try m.stack.append(m.gpa, .{ .compound = compound - 1, .candidate = first });
                    compound -= 1;
                    candidate = first;
                    continue :attempt;
                }
                outcome = noCandidate(combinator);
            }
            // Return the outcome through the open combinators.
            while (m.stack.pop()) |frame| {
                const combinator = selector.combinators[frame.compound];
                switch (outcome) {
                    .matched, .not_matched_globally => continue,
                    .restart_from_sibling, .restart_from_descendant => {},
                }
                switch (combinator) {
                    // These combinators have one candidate.
                    .next_sibling => continue,
                    .child => {
                        outcome = .restart_from_descendant;
                        continue;
                    },
                    // An earlier sibling has the same ancestors, so it cannot repair an ancestor failure.
                    .subsequent_sibling => if (outcome == .restart_from_descendant) continue,
                    .descendant => {},
                }
                if (try m.nextCandidate(frame.candidate, combinator)) |next| {
                    // The popped frame's slot is still allocated.
                    m.stack.appendAssumeCapacity(.{ .compound = frame.compound, .candidate = next });
                    compound = frame.compound;
                    candidate = next;
                    continue :attempt;
                }
                outcome = noCandidate(combinator);
            }
            return outcome == .matched;
        }
    }

    /// The specificity of the most specific selector of `list` that matches `element`, or null when none matches.
    pub fn matchList(m: *Matcher, element: NodeHandle, list: *const SelectorList) MatchError!?Specificity {
        var best: ?Specificity = null;
        for (list.selectors) |*selector| {
            if (!try m.matches(element, selector)) continue;
            if (best == null or selector.specificity.order(best.?) == .gt) best = selector.specificity;
        }
        return best;
    }

    /// The candidate after `element` for the compound left of `combinator`: the parent element for the child and
    /// descendant combinators, and the previous element sibling for the sibling combinators.
    fn nextCandidate(m: *Matcher, element: NodeHandle, combinator: Combinator) MatchError!?NodeHandle {
        return switch (combinator) {
            .child, .descendant => m.parentElement(element),
            .next_sibling, .subsequent_sibling => m.previousElementSibling(element),
        };
    }

    fn parentElement(m: *Matcher, element: NodeHandle) MatchError!?NodeHandle {
        const parent = try m.store.parentNode(element) orelse return null;
        return if (try m.store.nodeKind(parent) == .element) parent else null;
    }

    fn previousElementSibling(m: *Matcher, element: NodeHandle) MatchError!?NodeHandle {
        var cursor = try m.store.previousSibling(element);
        while (cursor) |node| : (cursor = try m.store.previousSibling(node)) {
            if (try m.store.nodeKind(node) == .element) return node;
        }
        return null;
    }

    fn matchesCompound(m: *Matcher, element: NodeHandle, compound: *const Compound) MatchError!bool {
        if (builtin.is_test) test_counters.compound_match_attempts += 1;
        const name = try m.store.elementName(element) orelse return error.NotAnElement;
        if (compound.type_selector) |selector| {
            if (selector.namespace == .none and name.namespace != null) return false;
            if (selector.name) |local_name| {
                if (!std.mem.eql(u16, local_name, name.local_name.units)) return false;
            }
        }
        for (compound.simples) |simple| {
            const matched = switch (simple) {
                .id => |id| if (try m.store.elementId(element)) |own| std.mem.eql(u16, own.units, id) else false,
                .class => |class| try m.store.hasClass(element, .{ .units = class }),
                .attribute => |*attribute| try m.matchesAttribute(element, attribute),
            };
            if (!matched) return false;
        }
        return true;
    }

    fn matchesAttribute(m: *Matcher, element: NodeHandle, selector: *const AttributeSelector) MatchError!bool {
        var attributes = try m.store.attributes(element);
        while (attributes.next()) |attribute| {
            if (selector.namespace == .none and attribute.namespace != null) continue;
            if (!std.mem.eql(u16, attribute.local_name.units, selector.name)) continue;
            const operator = selector.operator orelse return true;
            if (matchesValue(operator, selector.modifier == .i, attribute.value.units, selector.value)) return true;
        }
        return false;
    }
};

/// The attribute value matchers of sections 6.1 and 6.2.
fn matchesValue(operator: AttributeOperator, fold: bool, value: []const u16, wanted: []const u16) bool {
    switch (operator) {
        .equals => return unitsEql(value, wanted, fold),
        .includes => {
            // If val contains whitespace or is the empty string, it represents nothing.
            if (wanted.len == 0) return false;
            for (wanted) |unit| {
                if (isWhitespace(unit)) return false;
            }
            var index: usize = 0;
            while (index < value.len) {
                while (index < value.len and isWhitespace(value[index])) index += 1;
                const start = index;
                while (index < value.len and !isWhitespace(value[index])) index += 1;
                if (index > start and unitsEql(value[start..index], wanted, fold)) return true;
            }
            return false;
        },
        .dash_match => {
            if (unitsEql(value, wanted, fold)) return true;
            return value.len > wanted.len and value[wanted.len] == '-' and unitsEql(value[0..wanted.len], wanted, fold);
        },
        // If val is the empty string, the selector represents nothing.
        .prefix => return wanted.len != 0 and value.len >= wanted.len and unitsEql(value[0..wanted.len], wanted, fold),
        .suffix => return wanted.len != 0 and value.len >= wanted.len and unitsEql(value[value.len - wanted.len ..], wanted, fold),
        .substring => {
            if (wanted.len == 0 or value.len < wanted.len) return false;
            var start: usize = 0;
            while (start + wanted.len <= value.len) : (start += 1) {
                if (unitsEql(value[start .. start + wanted.len], wanted, fold)) return true;
            }
            return false;
        },
    }
}

/// Whitespace in attribute values: the ASCII whitespace of a document string, which the CSS preprocessing never touches.
fn isWhitespace(unit: u16) bool {
    return switch (unit) {
        0x09, 0x0A, 0x0C, 0x0D, 0x20 => true,
        else => false,
    };
}

fn unitsEql(a: []const u16, b: []const u16, fold: bool) bool {
    if (a.len != b.len) return false;
    if (!fold) return std.mem.eql(u16, a, b);
    for (a, b) |x, y| {
        if (lowerAscii(x) != lowerAscii(y)) return false;
    }
    return true;
}

fn lowerAscii(unit: u16) u16 {
    return if (unit >= 'A' and unit <= 'Z') unit + 0x20 else unit;
}

/// Returns the element's applicable declarations from the style rules of `sheets`, in sheet, rule, and declaration order.
/// A style rule's declarations take the specificity of its most specific selector that matches.
/// The caller frees the result with `gpa`.
pub fn matchRules(
    gpa: Allocator,
    store: *dom.Store,
    element: NodeHandle,
    sheets: []const *const stylesheet.Stylesheet,
) MatchError![]ApplicableDeclaration {
    var matcher: Matcher = .init(gpa, store);
    defer matcher.deinit();
    return matchRulesWith(gpa, &matcher, element, sheets);
}

/// `matchRules` with a caller-owned matcher, so a traversal reuses one combinator stack.
pub fn matchRulesWith(
    gpa: Allocator,
    matcher: *Matcher,
    element: NodeHandle,
    sheets: []const *const stylesheet.Stylesheet,
) MatchError![]ApplicableDeclaration {
    var output: std.ArrayList(ApplicableDeclaration) = .empty;
    errdefer output.deinit(gpa);
    for (sheets, 0..) |sheet, sheet_index| {
        for (sheet.rules, 0..) |*rule, rule_index| {
            const specificity = try matcher.matchList(element, &rule.selectors) orelse continue;
            for (rule.declarations, 0..) |*declaration, declaration_index| {
                try output.append(gpa, .{
                    .property = declaration.property,
                    .value = &declaration.value,
                    .origin = sheet.origin,
                    .important = declaration.important,
                    .specificity = specificity,
                    .order = .{ .sheet = @intCast(sheet_index), .rule = @intCast(rule_index), .declaration = @intCast(declaration_index) },
                    .rule = .{ .sheet = @intCast(sheet_index), .rule = @intCast(rule_index) },
                });
            }
        }
    }
    return output.toOwnedSlice(gpa);
}
