//! Arbitrary substitution functions: CSS Values and Units Level 5, Appendix A, and the `var()` function of
//! CSS Custom Properties for Cascading Variables Level 1, section 3.
//!
//! `var()` is the only arbitrary substitution function that this task implements. Its argument grammar is
//! `var( <declaration-value> , <declaration-value>? )`, where the first argument is a strict free-form production
//! and the fallback is a non-strict free-form production (Values 5 section 3.1.1).
//! A free-form production that starts with a {}-block is that block's contents.
//! Values 5 also defines `if()`, `inherit()`, `attr()`, `ident()`, and `random-item()` as arbitrary substitution functions.
//! A custom property value that contains one of them is invalid at computed-value time and reported as unsupported,
//! and so is a value that uses the spread syntax. Task `FP-0071` owns these functions and the spread syntax.
//!
//! "Substitute arbitrary substitution functions" recurses through "replace a var() function" in the standard.
//! Here each invocation is a resumable `Substitution` that asks its driver for nested substitutions and for
//! custom property values, so no function recurses. The driver owns the guard stack of substitution contexts.

const std = @import("std");
const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");
const registry = @import("registry.zig");
const Allocator = std.mem.Allocator;
const ComponentValue = parser.ComponentValue;
const nextItem = parser.nextItem;

/// The UA limit on one `var()` expansion, in component values, where a function or simple block counts as one plus its contents
/// (Values 5, "Safely Handling Overly-Long Substitution").
pub const expansion_limit: usize = 65536;

fn isVarFunction(value: ComponentValue) bool {
    return value.kind == .function and tokenizer.asciiCaseInsensitiveEql(value.token.value, "var");
}

/// The arbitrary substitution functions of Values 5 at the pinned commit, other than `var()`
/// (`css-values-5/Overview.bs` lines 1680, 1911, 2194, 2358, and 2741).
const unsupported_functions = [_][]const u8{ "if", "inherit", "attr", "ident", "random-item" };

fn isUnsupportedFunction(value: ComponentValue) bool {
    if (value.kind != .function) return false;
    inline for (unsupported_functions) |name| {
        if (tokenizer.asciiCaseInsensitiveEql(value.token.value, name)) return true;
    }
    return false;
}

fn isArbitrarySubstitutionFunction(value: ComponentValue) bool {
    return isVarFunction(value) or isUnsupportedFunction(value);
}

/// Whether the list contains an arbitrary substitution function other than `var()`, at any depth.
pub fn containsUnsupportedFunction(list: []const ComponentValue) bool {
    for (list) |value| {
        if (isUnsupportedFunction(value)) return true;
    }
    return false;
}

/// Whether the list contains a `var()` function at any depth.
pub fn containsVar(list: []const ComponentValue) bool {
    for (list) |value| {
        if (isVarFunction(value)) return true;
    }
    return false;
}

/// Whether every `var()` function in the list, at any depth, matches the `var()` argument grammar.
pub fn checkVarArguments(list: []const ComponentValue) bool {
    for (list, 0..) |value, index| {
        if (isVarFunction(value) and parseVarArguments(parser.contents(list, index)) == null) return false;
    }
    return true;
}

pub const VarArguments = struct {
    /// The first argument, without the {}-block wrapper and without leading and trailing whitespace.
    name: []const ComponentValue,
    /// The fallback after the comma, without a {}-block wrapper and without leading and trailing whitespace,
    /// or null when there is no comma.
    fallback: ?[]const ComponentValue,
};

/// Parses the contents of a `var()` function with its argument grammar, or returns null on failure.
pub fn parseVarArguments(arguments: []const ComponentValue) ?VarArguments {
    var index = skipWhitespace(arguments, 0);
    var name: []const ComponentValue = undefined;
    if (index < arguments.len and isCurlyBlock(arguments[index])) {
        // A strict free-form production that starts with a {}-block is that block's contents.
        name = parser.trimWhitespace(parser.contents(arguments, index));
        index = skipWhitespace(arguments, nextItem(arguments, index));
    } else {
        // It matches no top-level comma and no top-level {}-block.
        const start = index;
        while (index < arguments.len and !arguments[index].isToken(.comma)) : (index = nextItem(arguments, index)) {
            if (isCurlyBlock(arguments[index])) return null;
        }
        name = parser.trimWhitespace(arguments[start..index]);
    }
    if (name.len == 0 or !isDeclarationValue(name)) return null;
    if (index == arguments.len) return .{ .name = name, .fallback = null };
    if (!arguments[index].isToken(.comma)) return null;
    // A bare comma with nothing after it is an empty fallback.
    index = skipWhitespace(arguments, index + 1);
    var fallback: []const ComponentValue = undefined;
    if (index < arguments.len and isCurlyBlock(arguments[index])) {
        fallback = parser.trimWhitespace(parser.contents(arguments, index));
        if (skipWhitespace(arguments, nextItem(arguments, index)) != arguments.len) return null;
    } else {
        // The non-strict production may contain commas and {}-blocks.
        fallback = parser.trimWhitespace(arguments[index..]);
    }
    if (!isDeclarationValue(fallback)) return null;
    return .{ .name = name, .fallback = fallback };
}

fn skipWhitespace(list: []const ComponentValue, start: usize) usize {
    var index = start;
    while (index < list.len and list[index].isToken(.whitespace)) index += 1;
    return index;
}

fn isCurlyBlock(value: ComponentValue) bool {
    return value.kind == .block and value.token.kind == .open_curly;
}

/// Whether the list contains none of the values that <declaration-value> excludes (Syntax 7.2):
/// a bad string, a bad url, an unmatched closing bracket at any depth, or a top-level semicolon or "!".
/// The empty list matches `<declaration-value>?`.
pub fn isDeclarationValue(list: []const ComponentValue) bool {
    for (list) |value| {
        if (value.kind != .token) continue;
        switch (value.token.kind) {
            .bad_string, .bad_url, .close_paren, .close_square, .close_curly => return false,
            else => {},
        }
    }
    var index: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) {
        if (list[index].isToken(.semicolon) or list[index].isDelim('!')) return false;
    }
    return true;
}

/// Whether the contents of an arbitrary substitution function use the spread syntax: three adjacent "." delims
/// immediately followed by an arbitrary substitution function, at any depth outside nested arbitrary substitution functions.
pub fn usesSpread(arguments: []const ComponentValue) bool {
    if (hasSpreadAmong(arguments, 0, arguments.len)) return true;
    var index: usize = 0;
    while (index < arguments.len) {
        const value = arguments[index];
        if (isArbitrarySubstitutionFunction(value)) {
            index = nextItem(arguments, index);
            continue;
        }
        if (value.kind != .token and hasSpreadAmong(arguments, index + 1, nextItem(arguments, index))) return true;
        index += 1;
    }
    return false;
}

/// Checks the sibling items in `[start, end)`.
fn hasSpreadAmong(list: []const ComponentValue, start: usize, end: usize) bool {
    var dots: usize = 0;
    var index = start;
    while (index < end) : (index = nextItem(list, index)) {
        const value = list[index];
        if (value.isDelim('.')) {
            dots += 1;
            continue;
        }
        if (dots >= 3 and isArbitrarySubstitutionFunction(value)) return true;
        dots = 0;
    }
    return false;
}

/// "Parse it as a <custom-property-name>" for a substituted first argument.
pub fn customPropertyName(list: []const ComponentValue) ?[]const u16 {
    const trimmed = parser.trimWhitespace(list);
    if (trimmed.len != 1 or !trimmed[0].isToken(.ident)) return null;
    const name = trimmed[0].token.value;
    if (!registry.isCustomPropertyName(name)) return null;
    return name;
}

/// Why a substitution produced the guaranteed-invalid value.
pub const InvalidReason = enum {
    guaranteed_invalid,
    /// The value uses the spread syntax, which task `FP-0071` owns.
    unsupported,
};

/// The result of one substitution. Tokens are owned by the driver's allocator.
pub const Result = union(enum) {
    tokens: []const ComponentValue,
    invalid: InvalidReason,
};

/// What a substitution needs from its driver.
pub const Need = union(enum) {
    /// Substitute this list without a substitution context, and answer with `substituted`.
    substitute: []const ComponentValue,
    /// Answer with `property`: the computed value of this custom property on the element, or null for the guaranteed-invalid value.
    property: []const u16,
    /// The substitution finished. The driver owns the tokens, and it applies the cyclic check of step 3.
    done: Result,
};

pub const Answer = union(enum) {
    substituted: Result,
    property: ?[]const ComponentValue,
};

const Stage = enum { name, property, fallback };

const Pending = struct {
    stage: Stage,
    arguments: VarArguments,
    /// The input index after the `var()` function.
    resume_at: usize,
};

const Open = struct {
    /// The function or block in the output.
    output: usize,
    /// The input index where its contents end.
    end: usize,
};

/// One invocation of "substitute arbitrary substitution functions" (Values 5, Appendix A) on `input`.
/// It visits `var()` functions in depth-first preorder, outside other `var()` functions, and copies every other value.
pub const Substitution = struct {
    input: []const ComponentValue,
    cursor: usize = 0,
    output: std.ArrayList(ComponentValue) = .empty,
    open: std.ArrayList(Open) = .empty,
    /// Whether some `var()` was replaced with the guaranteed-invalid value.
    invalid: bool = false,
    /// Whether some invalid replacement came from the unsupported spread syntax.
    unsupported: bool = false,
    pending: ?Pending = null,
    /// A copy of a substituted custom property name, kept until the driver answers.
    name_copy: ?[]const u16 = null,

    pub fn init(input: []const ComponentValue) Substitution {
        return .{ .input = input };
    }

    /// Frees every buffer. A finished substitution's tokens already belong to the caller.
    pub fn deinit(s: *Substitution, gpa: Allocator) void {
        s.freeNameCopy(gpa);
        s.output.deinit(gpa);
        s.open.deinit(gpa);
        s.* = undefined;
    }

    /// Runs until the substitution needs something or finishes. The first call passes a null answer,
    /// and each later call answers the previous need. A `done` result's tokens belong to the caller.
    pub fn step(s: *Substitution, gpa: Allocator, answer: ?Answer) Allocator.Error!Need {
        if (s.pending) |pending| {
            if (try s.resumeVar(gpa, pending, answer.?)) |need| return need;
        }
        while (true) {
            while (s.open.items.len != 0 and s.open.items[s.open.items.len - 1].end <= s.cursor) {
                const open = s.open.pop().?;
                s.output.items[open.output].descendants = s.output.items.len - open.output - 1;
            }
            if (s.cursor == s.input.len) {
                if (s.invalid) return .{ .done = .{ .invalid = if (s.unsupported) .unsupported else .guaranteed_invalid } };
                return .{ .done = .{ .tokens = try s.output.toOwnedSlice(gpa) } };
            }
            const value = s.input[s.cursor];
            if (isVarFunction(value)) {
                const after = nextItem(s.input, s.cursor);
                const arguments_list = parser.contents(s.input, s.cursor);
                // Substitute early-invoked functions: the spread syntax is unsupported.
                if (usesSpread(arguments_list)) {
                    s.invalid = true;
                    s.unsupported = true;
                    s.cursor = after;
                    continue;
                }
                // Parse the early result according to the argument grammar; a failure is the guaranteed-invalid value.
                const arguments = parseVarArguments(arguments_list) orelse {
                    s.invalid = true;
                    s.cursor = after;
                    continue;
                };
                // "Replace a var() function" step 2: substitute in the first argument.
                if (containsVar(arguments.name)) {
                    s.pending = .{ .stage = .name, .arguments = arguments, .resume_at = after };
                    return .{ .substitute = arguments.name };
                }
                s.pending = .{ .stage = .property, .arguments = arguments, .resume_at = after };
                if (customPropertyName(arguments.name)) |name| return .{ .property = name };
                if (try s.useFallback(gpa)) |need| return need;
                continue;
            }
            try s.output.ensureUnusedCapacity(gpa, 1);
            if (value.kind != .token) {
                try s.open.append(gpa, .{ .output = s.output.items.len, .end = nextItem(s.input, s.cursor) });
                var copy = value;
                copy.descendants = 0;
                s.output.appendAssumeCapacity(copy);
            } else {
                s.output.appendAssumeCapacity(value);
            }
            s.cursor += 1;
        }
    }

    /// Continues a pending `var()` with the driver's answer. Returns a need, or null when the `var()` is replaced.
    fn resumeVar(s: *Substitution, gpa: Allocator, pending: Pending, answer: Answer) Allocator.Error!?Need {
        switch (pending.stage) {
            .name => {
                const result = answer.substituted;
                switch (result) {
                    .invalid => |reason| {
                        if (reason == .unsupported) s.unsupported = true;
                        s.pending.?.stage = .property;
                        return s.useFallback(gpa);
                    },
                    .tokens => |tokens| {
                        defer gpa.free(tokens);
                        s.pending.?.stage = .property;
                        // Parse it as a <custom-property-name>; on failure the result is the guaranteed-invalid value.
                        if (customPropertyName(tokens)) |name| {
                            // The name borrows the substituted tokens, so keep a copy for the driver's answer.
                            const owned = try gpa.dupe(u16, name);
                            s.name_copy = owned;
                            return .{ .property = owned };
                        }
                        return s.useFallback(gpa);
                    },
                }
            },
            .property => {
                s.freeNameCopy(gpa);
                // Step 3: if the result is the guaranteed-invalid value and a fallback was provided, substitute the fallback.
                const tokens = answer.property orelse return s.useFallback(gpa);
                try s.replaceVar(gpa, tokens);
                return null;
            },
            .fallback => {
                switch (answer.substituted) {
                    .invalid => |reason| {
                        if (reason == .unsupported) s.unsupported = true;
                        s.invalid = true;
                        s.finishVar();
                    },
                    .tokens => |tokens| {
                        defer gpa.free(tokens);
                        try s.replaceVar(gpa, tokens);
                    },
                }
                return null;
            },
        }
    }

    /// The pending `var()` has the guaranteed-invalid value: use its fallback, or replace it with the guaranteed-invalid value.
    fn useFallback(s: *Substitution, gpa: Allocator) Allocator.Error!?Need {
        const fallback = s.pending.?.arguments.fallback orelse {
            s.invalid = true;
            s.finishVar();
            return null;
        };
        if (containsVar(fallback)) {
            s.pending.?.stage = .fallback;
            return .{ .substitute = fallback };
        }
        try s.replaceVar(gpa, fallback);
        return null;
    }

    /// Replaces the pending `var()` with `tokens`, or with the guaranteed-invalid value when they exceed the expansion limit.
    fn replaceVar(s: *Substitution, gpa: Allocator, tokens: []const ComponentValue) Allocator.Error!void {
        if (tokens.len > expansion_limit) {
            s.invalid = true;
        } else {
            try s.output.appendSlice(gpa, tokens);
        }
        s.finishVar();
    }

    fn finishVar(s: *Substitution) void {
        s.cursor = s.pending.?.resume_at;
        s.pending = null;
    }

    fn freeNameCopy(s: *Substitution, gpa: Allocator) void {
        if (s.name_copy) |copy| gpa.free(copy);
        s.name_copy = null;
    }
};
