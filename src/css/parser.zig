//! CSS Syntax Module Level 3, section 5: the token stream, the parser entry points, and the parser algorithms.
//!
//! The source is the editor's draft at `w3c/csswg-drafts` commit `58354dac99cc8783a9b7b28957ece56bb48579eb`.
//! A comment beside each branch names the algorithm that it implements.
//!
//! "Consume a block's contents" (5.5.5) at that commit returns `rules` at a `<}-token>` or EOF
//! and drops a nonempty `decls`. This parser appends a nonempty `decls` to `rules` before that return,
//! as the algorithm's other branches do; the FP-0014 contract records this integrator decision.
//!
//! No function recurses. A component value list is a flat preorder array, and an explicit stack
//! holds the open functions and simple blocks of a nested value and the open blocks of nested rules.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const View = web_string.View;

pub const Range = tokenizer.Range;
pub const Token = tokenizer.Token;
pub const TokenKind = tokenizer.TokenKind;

/// One component value in a flat preorder list.
/// A function or simple block is followed by its contents, which span `descendants` entries.
/// A list is therefore relocatable: any slice that starts and ends at item boundaries is itself a list.
pub const ComponentValue = struct {
    kind: Kind,
    /// The preserved token, the function token, or the block's opening token.
    token: Token,
    /// The number of entries of this item's contents. Zero for a preserved token.
    descendants: usize = 0,
    /// The end of the item's source range: past its closing token, or past its last value at EOF.
    end: usize,

    pub const Kind = enum { token, function, block };

    /// The source range of the item, including any closing token.
    pub fn range(value: ComponentValue) Range {
        return .{ .start = value.token.range.start, .end = value.end };
    }

    /// Whether the item is a preserved token of `kind`.
    pub fn isToken(value: ComponentValue, kind: TokenKind) bool {
        return value.kind == .token and value.token.kind == kind;
    }

    /// Whether the item is a delim token with the code point `code_point`.
    pub fn isDelim(value: ComponentValue, code_point: u21) bool {
        return value.isToken(.delim) and value.token.delim == code_point;
    }
};

/// Returns the index of the item after the item at `index`.
pub fn nextItem(list: []const ComponentValue, index: usize) usize {
    return index + 1 + list[index].descendants;
}

/// Returns the contents of the function or simple block at `index`.
pub fn contents(list: []const ComponentValue, index: usize) []const ComponentValue {
    return list[index + 1 .. index + 1 + list[index].descendants];
}

/// Returns the item at `index` with its contents, as a one-item list.
pub fn item(list: []const ComponentValue, index: usize) []const ComponentValue {
    return list[index..nextItem(list, index)];
}

/// Returns `list` without leading and trailing whitespace items.
pub fn trimWhitespace(list: []const ComponentValue) []const ComponentValue {
    var start: usize = 0;
    while (start < list.len and list[start].isToken(.whitespace)) start += 1;
    var end = start;
    var index = start;
    while (index < list.len) : (index = nextItem(list, index)) {
        if (!list[index].isToken(.whitespace)) end = nextItem(list, index);
    }
    return list[start..end];
}

/// A declaration (5.2).
pub const Declaration = struct {
    name: []const u16,
    value: []const ComponentValue,
    important: bool = false,
    /// The source text of the value, for a custom property name (5.5.6 step 8).
    original_text: ?[]const u16 = null,
    /// From the name to the last token of the declaration.
    range: Range,
};

pub const QualifiedRule = struct {
    prelude: []const ComponentValue,
    declarations: []const Declaration,
    /// Child rules, where each later declaration list is a nested declarations rule.
    rules: []const Rule,
    range: Range,
};

pub const AtRule = struct {
    name: []const u16,
    prelude: []const ComponentValue,
    /// Null for a statement at-rule. A block at-rule holds its block's contents.
    block: ?[]const BlockItem,
    range: Range,
};

pub const Rule = union(enum) {
    qualified: *const QualifiedRule,
    at: *const AtRule,
    /// A nested declarations rule (5.5.3) with its declaration list as its sole child.
    nested_declarations: []const Declaration,
};

/// An item of a block's contents: a rule or a list of declarations.
pub const BlockItem = union(enum) {
    rule: Rule,
    declarations: []const Declaration,
};

/// The context in which the parser asks whether a rule or declaration is "valid in the current context".
pub const Context = enum { top_level, at_rule_block, qualified_rule_block };

/// Answers "valid in the current context" for the parser.
/// A qualified rule's prelude is checked when the parser reaches its block, so diagnostics follow source order,
/// and the rule itself is checked when its block ends, with the prelude's result.
/// When the parser reaches an at-rule's block, it asks whether the validator checks that block's contents;
/// a validator that will drop the at-rule answers no, and the block is consumed without validator calls.
pub const Validator = struct {
    ptr: ?*anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        qualifiedPrelude: *const fn (ptr: ?*anyopaque, prelude: []const ComponentValue, context: Context) Allocator.Error!bool,
        qualifiedRule: *const fn (ptr: ?*anyopaque, rule: *const QualifiedRule, context: Context, prelude_valid: bool) Allocator.Error!bool,
        /// Whether the contents of the at-rule's block are checked. The rule has its name and prelude, and no block yet.
        atRuleBlock: *const fn (ptr: ?*anyopaque, rule: *const AtRule, context: Context) Allocator.Error!bool,
        atRule: *const fn (ptr: ?*anyopaque, rule: *const AtRule, context: Context) Allocator.Error!bool,
        declaration: *const fn (ptr: ?*anyopaque, declaration: *const Declaration, context: Context) Allocator.Error!bool,
    };

    /// Accepts every rule and declaration in every context, so the result is the bare syntax.
    pub const syntax_only: Validator = .{ .ptr = null, .vtable = &.{
        .qualifiedPrelude = acceptPrelude,
        .qualifiedRule = acceptQualified,
        .atRuleBlock = acceptAt,
        .atRule = acceptAt,
        .declaration = acceptDeclaration,
    } };

    fn acceptPrelude(_: ?*anyopaque, _: []const ComponentValue, _: Context) Allocator.Error!bool {
        return true;
    }
    fn acceptQualified(_: ?*anyopaque, _: *const QualifiedRule, _: Context, _: bool) Allocator.Error!bool {
        return true;
    }
    fn acceptAt(_: ?*anyopaque, _: *const AtRule, _: Context) Allocator.Error!bool {
        return true;
    }
    fn acceptDeclaration(_: ?*anyopaque, _: *const Declaration, _: Context) Allocator.Error!bool {
        return true;
    }
};

pub const ParseError = Allocator.Error || error{SyntaxError};

/// A parse result. It owns an arena that holds the filtered input, the tokens, and every result object.
pub fn Parsed(comptime T: type) type {
    return struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        /// The filtered code points that every source range indexes.
        input: []const u21,
        value: T,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
            self.* = undefined;
        }
    };
}

/// "Parse a stylesheet" (5.4.3) from a decoded string. The stylesheet location is outside this task.
pub fn parseStylesheet(gpa: Allocator, source: View, validator: Validator) Allocator.Error!Parsed([]const Rule) {
    return parseStylesheetContents(gpa, source, validator);
}

/// "Parse a stylesheet's contents" (5.4.4).
pub fn parseStylesheetContents(gpa: Allocator, source: View, validator: Validator) Allocator.Error!Parsed([]const Rule) {
    var result: Parsed([]const Rule) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, validator);
    defer p.deinit();
    result.input = p.input;
    result.value = try p.consumeStylesheetContents();
    return result;
}

/// "Parse a block's contents" (5.4.5). Declarations and rules are checked in the `qualified_rule_block` context.
pub fn parseBlockContents(gpa: Allocator, source: View, validator: Validator) Allocator.Error!Parsed([]const BlockItem) {
    var result: Parsed([]const BlockItem) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, validator);
    defer p.deinit();
    result.input = p.input;
    try p.stack.append(gpa, .{ .block = .{ .owner = .none, .context = .qualified_rule_block, .silent = false, .start = 0 } });
    try p.run();
    result.value = p.block_contents_result;
    return result;
}

/// "Parse a rule" (5.4.6). The rule is checked in the `top_level` context.
pub fn parseRule(gpa: Allocator, source: View, validator: Validator) ParseError!Parsed(Rule) {
    var result: Parsed(Rule) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, validator);
    defer p.deinit();
    result.input = p.input;
    p.discardWhitespace();
    const first = p.nextToken() orelse return error.SyntaxError;
    try p.stack.append(gpa, .{ .single = null });
    if (first.kind == .at_keyword) {
        try p.beginAtRule(false, .top_level, false);
    } else {
        try p.beginQualifiedRule(false, false, .top_level, false);
    }
    try p.run();
    const delivered = p.stack.items[0].single orelse return error.SyntaxError;
    const rule: Rule = switch (delivered) {
        .at => |at| at orelse return error.SyntaxError,
        .qualified => |outcome| switch (outcome) {
            .nothing, .invalid => return error.SyntaxError,
            .rule => |rule| rule,
        },
    };
    p.discardWhitespace();
    if (p.nextToken() != null) return error.SyntaxError;
    result.value = rule;
    return result;
}

/// "Parse a declaration" (5.4.7). The declaration is checked in the `qualified_rule_block` context.
pub fn parseDeclaration(gpa: Allocator, source: View, validator: Validator) ParseError!Parsed(Declaration) {
    var result: Parsed(Declaration) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, validator);
    defer p.deinit();
    result.input = p.input;
    p.discardWhitespace();
    result.value = try p.consumeDeclaration(false, .qualified_rule_block, false) orelse return error.SyntaxError;
    return result;
}

/// "Parse a component value" (5.4.8). The result is a one-item list.
pub fn parseComponentValue(gpa: Allocator, source: View) ParseError!Parsed([]const ComponentValue) {
    var result: Parsed([]const ComponentValue) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, .syntax_only);
    defer p.deinit();
    result.input = p.input;
    p.discardWhitespace();
    if (p.nextToken() == null) return error.SyntaxError;
    p.values.clearRetainingCapacity();
    try p.consumeComponentValue(&p.values);
    p.discardWhitespace();
    if (p.nextToken() != null) return error.SyntaxError;
    result.value = try p.arena.dupe(ComponentValue, p.values.items);
    return result;
}

/// "Parse a list of component values" (5.4.9).
pub fn parseComponentValueList(gpa: Allocator, source: View) Allocator.Error!Parsed([]const ComponentValue) {
    var result: Parsed([]const ComponentValue) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, .syntax_only);
    defer p.deinit();
    result.input = p.input;
    p.values.clearRetainingCapacity();
    try p.consumeComponentValueList(&p.values, null, false);
    result.value = try p.arena.dupe(ComponentValue, p.values.items);
    return result;
}

/// "Parse a comma-separated list of component values" (5.4.10).
pub fn parseCommaSeparatedComponentValues(gpa: Allocator, source: View) Allocator.Error!Parsed([]const []const ComponentValue) {
    var result: Parsed([]const []const ComponentValue) = undefined;
    result.arena = .init(gpa);
    errdefer result.arena.deinit();
    var p = try Parser.init(gpa, result.arena.allocator(), source, .syntax_only);
    defer p.deinit();
    result.input = p.input;
    var groups: std.ArrayList([]const ComponentValue) = .empty;
    // While input is not empty, consume a list of component values with <comma-token> as the stop token,
    // append the result to groups, and discard a token.
    while (p.nextToken() != null) {
        p.values.clearRetainingCapacity();
        try p.consumeComponentValueList(&p.values, .comma, false);
        try groups.append(p.arena, try p.arena.dupe(ComponentValue, p.values.items));
        p.discard();
    }
    result.value = try groups.toOwnedSlice(p.arena);
    return result;
}

/// "Parse something according to a CSS grammar" (5.4.1) over a list of component values.
/// Parsing a list of component values from such a list returns the list itself,
/// so the result is `grammar.match(values)`: the matched result, or the grammar's failure value.
pub fn parseGrammar(values: []const ComponentValue, grammar: anytype) @TypeOf(grammar).Result {
    return grammar.match(values);
}

/// "Parse a comma-separated list according to a CSS grammar" (5.4.2) over a list of component values.
/// A list of only whitespace gives an empty list. The caller frees the result with `gpa`.
pub fn parseGrammarList(gpa: Allocator, values: []const ComponentValue, grammar: anytype) Allocator.Error![]@TypeOf(grammar).Result {
    const Result = @TypeOf(grammar).Result;
    if (trimWhitespace(values).len == 0) return &.{};
    var results: std.ArrayList(Result) = .empty;
    errdefer results.deinit(gpa);
    // Parse a comma-separated list of component values: split at top-level commas,
    // discarding the comma after each group, so a trailing comma ends the list.
    var start: usize = 0;
    var index: usize = 0;
    while (index < values.len) : (index = nextItem(values, index)) {
        if (values[index].isToken(.comma)) {
            try results.append(gpa, grammar.match(values[start..index]));
            start = index + 1;
        }
    }
    if (start < values.len) try results.append(gpa, grammar.match(values[start..]));
    return results.toOwnedSlice(gpa);
}

/// The outcome of "consume a qualified rule".
const QualifiedOutcome = union(enum) {
    nothing,
    /// An "invalid rule error".
    invalid,
    rule: Rule,
};

/// The result that a finished rule delivers to the frame that consumed it.
const Delivered = union(enum) {
    /// "Consume an at-rule": a rule, or nothing.
    at: ?Rule,
    qualified: QualifiedOutcome,
};

/// The rule whose block a block frame consumes.
const Owner = union(enum) {
    /// "Parse a block's contents": the frame's result is the entry point's result.
    none,
    /// `silent` is whether the at-rule itself goes unchecked; its block frame is also silent when the validator
    /// does not check the block's contents.
    at_rule: struct { rule: *AtRule, context: Context, silent: bool },
    qualified: struct { rule: *QualifiedRule, context: Context, prelude_valid: bool },
    /// A rule that looks like a custom property: its block is consumed and nothing is returned.
    discard,
};

/// "Consume a block's contents" in progress.
const BlockFrame = struct {
    items: std.ArrayList(BlockItem) = .empty,
    decls: std.ArrayList(Declaration) = .empty,
    owner: Owner,
    /// The context of every rule and declaration in the block.
    context: Context,
    /// Whether the validator is not asked about the block's rules and declarations, because the block's result
    /// is discarded or the validator does not check this at-rule's block.
    silent: bool,
    /// The start of the owning rule's source range.
    start: usize,
};

const Frame = union(enum) {
    /// "Consume a stylesheet's contents".
    stylesheet: std.ArrayList(Rule),
    /// "Parse a rule": the single delivered result.
    single: ?Delivered,
    block: BlockFrame,
};

const Parser = struct {
    gpa: Allocator,
    arena: Allocator,
    input: []const u21,
    tokens: []const Token,
    index: usize = 0,
    validator: Validator,
    /// The explicit stack of rule frames. It never holds a pointer into itself.
    stack: std.ArrayList(Frame) = .empty,
    /// The scratch list for a prelude or a declaration value. Only one is built at a time.
    values: std.ArrayList(ComponentValue) = .empty,
    /// The scratch list for component values that are consumed and discarded.
    skipped: std.ArrayList(ComponentValue) = .empty,
    /// The open functions and simple blocks of the component value being consumed, by index in the output list.
    open: std.ArrayList(usize) = .empty,
    block_contents_result: []const BlockItem = &.{},

    fn init(gpa: Allocator, arena: Allocator, source: View, validator: Validator) Allocator.Error!Parser {
        // Normalize: filter code points from the string and tokenize the result.
        const input = try tokenizer.filterCodePoints(arena, source);
        const tokens = try tokenizer.tokenizeAll(arena, input, .{});
        return .{ .gpa = gpa, .arena = arena, .input = input, .tokens = tokens, .validator = validator };
    }

    fn deinit(p: *Parser) void {
        p.stack.deinit(p.gpa);
        p.values.deinit(p.gpa);
        p.skipped.deinit(p.gpa);
        p.open.deinit(p.gpa);
    }

    /// The token stream's next token, or null for the <EOF-token>.
    fn nextToken(p: *const Parser) ?Token {
        return if (p.index < p.tokens.len) p.tokens[p.index] else null;
    }

    fn nextIs(p: *const Parser, kind: TokenKind) bool {
        const token = p.nextToken() orelse return false;
        return token.kind == kind;
    }

    /// "Discard a token": if the token stream is not empty, increment the index.
    fn discard(p: *Parser) void {
        if (p.index < p.tokens.len) p.index += 1;
    }

    /// "Discard whitespace".
    fn discardWhitespace(p: *Parser) void {
        while (p.nextIs(.whitespace)) p.index += 1;
    }

    /// The end of the last consumed token, or `fallback` when nothing was consumed.
    fn consumedEnd(p: *const Parser, fallback: usize) usize {
        return if (p.index > 0) p.tokens[p.index - 1].range.end else fallback;
    }

    /// "Consume a stylesheet's contents" (5.5.1).
    fn consumeStylesheetContents(p: *Parser) Allocator.Error![]const Rule {
        try p.stack.append(p.gpa, .{ .stylesheet = .empty });
        while (true) {
            const token = p.nextToken() orelse break;
            switch (token.kind) {
                .whitespace, .cdo, .cdc => p.discard(),
                .at_keyword => try p.beginAtRule(false, .top_level, false),
                else => try p.beginQualifiedRule(false, false, .top_level, false),
            }
            try p.run();
        }
        return p.stack.items[0].stylesheet.toOwnedSlice(p.arena);
    }

    /// Runs block frames until the top frame is not a block frame.
    fn run(p: *Parser) Allocator.Error!void {
        while (p.stack.items.len != 0 and p.stack.items[p.stack.items.len - 1] == .block) {
            try p.stepBlock();
        }
    }

    /// "Consume a block's contents" (5.5.5) for the top frame, until the block ends or a nested block starts.
    fn stepBlock(p: *Parser) Allocator.Error!void {
        while (true) {
            const frame = &p.stack.items[p.stack.items.len - 1].block;
            const token = p.nextToken() orelse return p.finishBlock();
            switch (token.kind) {
                .whitespace, .semicolon => p.discard(),
                .close_curly => return p.finishBlock(),
                .at_keyword => {
                    // If decls is not empty, append it to rules and set decls to a fresh empty list.
                    try flushDeclarations(p.arena, frame);
                    // Consume an at-rule with nested set to true.
                    const depth = p.stack.items.len;
                    try p.beginAtRule(true, frame.context, frame.silent);
                    if (p.stack.items.len != depth) return;
                },
                else => {
                    // Mark, then consume a declaration with nested set to true.
                    const mark = p.index;
                    if (try p.consumeDeclaration(true, frame.context, frame.silent)) |declaration| {
                        const current = &p.stack.items[p.stack.items.len - 1].block;
                        try current.decls.append(p.arena, declaration);
                        continue;
                    }
                    // Otherwise, restore the mark and consume a qualified rule with nested set to true
                    // and <semicolon-token> as the stop token.
                    p.index = mark;
                    const current = &p.stack.items[p.stack.items.len - 1].block;
                    const depth = p.stack.items.len;
                    try p.beginQualifiedRule(true, true, current.context, current.silent);
                    if (p.stack.items.len != depth) return;
                },
            }
        }
    }

    /// Ends the top block frame at a <}-token> or EOF, then finishes its owner.
    fn finishBlock(p: *Parser) Allocator.Error!void {
        var frame = p.stack.pop().?.block;
        // The FP-0014 decision: append a nonempty decls to rules before the return.
        try flushDeclarations(p.arena, &frame);
        const items = try frame.items.toOwnedSlice(p.arena);
        if (frame.owner == .none) {
            p.block_contents_result = items;
            return;
        }
        // "Consume a block": discard the closing token.
        p.discard();
        const end = p.consumedEnd(frame.start);
        const delivered: Delivered = switch (frame.owner) {
            .none => unreachable,
            .discard => .{ .qualified = .nothing },
            .at_rule => |owner| blk: {
                owner.rule.block = items;
                owner.rule.range.end = end;
                const valid = owner.silent or try p.validator.vtable.atRule(p.validator.ptr, owner.rule, owner.context);
                break :blk .{ .at = if (valid) .{ .at = owner.rule } else null };
            },
            .qualified => |owner| blk: {
                try fillQualifiedRule(p.arena, owner.rule, items);
                owner.rule.range.end = end;
                const valid = frame.silent or
                    try p.validator.vtable.qualifiedRule(p.validator.ptr, owner.rule, owner.context, owner.prelude_valid);
                break :blk .{ .qualified = if (valid) .{ .rule = .{ .qualified = owner.rule } } else .invalid };
            },
        };
        try p.deliver(delivered);
    }

    /// Gives a finished rule to the frame that consumed it.
    fn deliver(p: *Parser, delivered: Delivered) Allocator.Error!void {
        const top = &p.stack.items[p.stack.items.len - 1];
        switch (top.*) {
            .single => |*single| single.* = delivered,
            .stylesheet => |*rules| switch (delivered) {
                // If anything is returned, append it to rules.
                .at => |at| if (at) |rule| try rules.append(p.arena, rule),
                // If a rule is returned, append it to rules.
                .qualified => |outcome| switch (outcome) {
                    .nothing, .invalid => {},
                    .rule => |rule| try rules.append(p.arena, rule),
                },
            },
            .block => |*frame| switch (delivered) {
                // If a rule was returned, append it to rules.
                .at => |at| if (at) |rule| try frame.items.append(p.arena, .{ .rule = rule }),
                .qualified => |outcome| switch (outcome) {
                    // If nothing was returned, do nothing.
                    .nothing => {},
                    // If an invalid rule error was returned, flush decls.
                    .invalid => try flushDeclarations(p.arena, frame),
                    // If a rule was returned, flush decls and append the rule.
                    .rule => |rule| {
                        try flushDeclarations(p.arena, frame);
                        try frame.items.append(p.arena, .{ .rule = rule });
                    },
                },
            },
        }
    }

    /// "Consume an at-rule" (5.5.2). It delivers the rule, or pushes a block frame for its block.
    fn beginAtRule(p: *Parser, nested: bool, context: Context, silent: bool) Allocator.Error!void {
        // Consume a token and let rule be a new at-rule with its name set to the token's value.
        const keyword = p.tokens[p.index];
        p.index += 1;
        p.values.clearRetainingCapacity();
        while (true) {
            const token = p.nextToken() orelse break;
            switch (token.kind) {
                .semicolon => break,
                .close_curly => {
                    // If nested is true, return the rule if it is valid. Otherwise, append the token to the prelude.
                    if (nested) break;
                    try p.appendToken(&p.values);
                },
                .open_curly => {
                    // Consume a block and assign the result to the rule's child rules.
                    const rule = try p.arena.create(AtRule);
                    rule.* = .{
                        .name = keyword.value,
                        .prelude = try p.arena.dupe(ComponentValue, p.values.items),
                        .block = null,
                        .range = .{ .start = keyword.range.start, .end = token.range.end },
                    };
                    p.discard();
                    const block_silent = silent or !(try p.validator.vtable.atRuleBlock(p.validator.ptr, rule, context));
                    try p.stack.append(p.gpa, .{ .block = .{
                        .owner = .{ .at_rule = .{ .rule = rule, .context = context, .silent = silent } },
                        .context = .at_rule_block,
                        .silent = block_silent,
                        .start = keyword.range.start,
                    } });
                    return;
                },
                else => try p.consumeComponentValue(&p.values),
            }
        }
        // <semicolon-token> or <EOF-token>: discard a token, and return the rule if it is valid.
        const at_semicolon = p.nextIs(.semicolon);
        if (at_semicolon) p.discard();
        const rule = try p.arena.create(AtRule);
        rule.* = .{
            .name = keyword.value,
            .prelude = try p.arena.dupe(ComponentValue, p.values.items),
            .block = null,
            .range = .{ .start = keyword.range.start, .end = p.consumedEnd(keyword.range.end) },
        };
        const valid = silent or try p.validator.vtable.atRule(p.validator.ptr, rule, context);
        try p.deliver(.{ .at = if (valid) .{ .at = rule } else null });
    }

    /// "Consume a qualified rule" (5.5.3), with <semicolon-token> as the stop token when `stop_at_semicolon`.
    /// It delivers the outcome, or pushes a block frame for the rule's block.
    fn beginQualifiedRule(p: *Parser, stop_at_semicolon: bool, nested: bool, context: Context, silent: bool) Allocator.Error!void {
        const start = p.tokens[p.index].range.start;
        p.values.clearRetainingCapacity();
        while (true) {
            // <EOF-token>: this is a parse error. Return nothing.
            const token = p.nextToken() orelse return p.deliver(.{ .qualified = .nothing });
            switch (token.kind) {
                // The stop token: this is a parse error. Return nothing.
                .semicolon => if (stop_at_semicolon) {
                    return p.deliver(.{ .qualified = .nothing });
                } else {
                    try p.consumeComponentValue(&p.values);
                },
                .close_curly => {
                    // This is a parse error. If nested is true, return nothing.
                    // Otherwise, consume a token and append the result to the prelude.
                    if (nested) return p.deliver(.{ .qualified = .nothing });
                    try p.appendToken(&p.values);
                },
                .open_curly => {
                    if (looksLikeCustomProperty(p.values.items)) {
                        if (nested) {
                            // Consume the remnants of a bad declaration with nested set to true, and return nothing.
                            try p.consumeBadDeclarationRemnants(true);
                            return p.deliver(.{ .qualified = .nothing });
                        }
                        // Consume a block and return nothing.
                        p.discard();
                        try p.stack.append(p.gpa, .{ .block = .{
                            .owner = .discard,
                            .context = .qualified_rule_block,
                            .silent = true,
                            .start = start,
                        } });
                        return;
                    }
                    const prelude = try p.arena.dupe(ComponentValue, p.values.items);
                    const prelude_valid = silent or try p.validator.vtable.qualifiedPrelude(p.validator.ptr, prelude, context);
                    const rule = try p.arena.create(QualifiedRule);
                    rule.* = .{
                        .prelude = prelude,
                        .declarations = &.{},
                        .rules = &.{},
                        .range = .{ .start = start, .end = token.range.end },
                    };
                    p.discard();
                    try p.stack.append(p.gpa, .{ .block = .{
                        .owner = .{ .qualified = .{ .rule = rule, .context = context, .prelude_valid = prelude_valid } },
                        .context = .qualified_rule_block,
                        .silent = silent,
                        .start = start,
                    } });
                    return;
                },
                else => try p.consumeComponentValue(&p.values),
            }
        }
    }

    /// "Consume a declaration" (5.5.6).
    fn consumeDeclaration(p: *Parser, nested: bool, context: Context, silent: bool) Allocator.Error!?Declaration {
        // Step 1: if the next token is an <ident-token>, consume it and set the name.
        const name_token = p.nextToken() orelse {
            try p.consumeBadDeclarationRemnants(nested);
            return null;
        };
        if (name_token.kind != .ident) {
            try p.consumeBadDeclarationRemnants(nested);
            return null;
        }
        p.index += 1;
        // Step 2: discard whitespace.
        p.discardWhitespace();
        // Step 3: if the next token is a <colon-token>, discard it.
        if (!p.nextIs(.colon)) {
            try p.consumeBadDeclarationRemnants(nested);
            return null;
        }
        p.discard();
        // Step 4: discard whitespace.
        p.discardWhitespace();
        // Step 5: consume a list of component values with nested and <semicolon-token> as the stop token.
        p.values.clearRetainingCapacity();
        try p.consumeComponentValueList(&p.values, .semicolon, nested);
        var value: []const ComponentValue = p.values.items;
        const raw: Range = if (value.len == 0)
            .{ .start = p.consumedEnd(name_token.range.end), .end = p.consumedEnd(name_token.range.end) }
        else
            .{ .start = value[0].token.range.start, .end = lastItemEnd(value) };
        var declaration: Declaration = .{
            .name = name_token.value,
            .value = &.{},
            .range = .{ .start = name_token.range.start, .end = p.consumedEnd(name_token.range.end) },
        };
        // Step 6: if the last two non-whitespace tokens are "!" and an ident matching "important",
        // remove them and set the important flag.
        if (importantStart(value)) |bang| {
            value = value[0..bang];
            declaration.important = true;
        }
        // Step 7: while the last item is a <whitespace-token>, remove it.
        value = trimTrailingWhitespace(value);
        // Step 8.
        if (isCustomPropertyNameString(declaration.name)) {
            const text: Range = if (value.len == 0)
                .{ .start = raw.start, .end = raw.start }
            else
                .{ .start = value[0].token.range.start, .end = lastItemEnd(value) };
            declaration.original_text = try utf16(p.arena, p.input[text.start..text.end]);
            declaration.value = try p.arena.dupe(ComponentValue, value);
        } else if (hasCurlyBlockWithOtherValues(value)) {
            return null;
        } else if (tokenizer.asciiCaseInsensitiveEql(declaration.name, "unicode-range")) {
            declaration.value = try p.consumeUnicodeRangeValue(raw);
        } else {
            declaration.value = try p.arena.dupe(ComponentValue, value);
        }
        // Step 9: if decl is valid in the current context, return it; otherwise return nothing.
        if (!silent and !try p.validator.vtable.declaration(p.validator.ptr, &declaration, context)) return null;
        return declaration;
    }

    /// "Consume the remnants of a bad declaration" (5.5.6).
    fn consumeBadDeclarationRemnants(p: *Parser, nested: bool) Allocator.Error!void {
        while (true) {
            const token = p.nextToken() orelse return;
            switch (token.kind) {
                .semicolon => {
                    p.discard();
                    return;
                },
                .close_curly => {
                    if (nested) return;
                    p.discard();
                },
                else => {
                    p.skipped.clearRetainingCapacity();
                    try p.consumeComponentValue(&p.skipped);
                },
            }
        }
    }

    /// "Consume the value of a unicode-range descriptor" (5.5.11) from the source text of `raw`.
    fn consumeUnicodeRangeValue(p: *Parser, raw: Range) Allocator.Error![]const ComponentValue {
        const tokens = try tokenizer.tokenizeAll(p.arena, p.input[raw.start..raw.end], .{ .unicode_ranges_allowed = true });
        for (tokens) |*token| {
            token.range.start += raw.start;
            token.range.end += raw.start;
        }
        var sub: Parser = .{ .gpa = p.gpa, .arena = p.arena, .input = p.input, .tokens = tokens, .validator = p.validator };
        defer sub.deinit();
        try sub.consumeComponentValueList(&sub.values, null, false);
        return p.arena.dupe(ComponentValue, sub.values.items);
    }

    /// "Consume a list of component values" (5.5.7) into `out`.
    fn consumeComponentValueList(p: *Parser, out: *std.ArrayList(ComponentValue), stop: ?TokenKind, nested: bool) Allocator.Error!void {
        while (true) {
            const token = p.nextToken() orelse return;
            if (stop != null and token.kind == stop.?) return;
            if (token.kind == .close_curly) {
                // If nested is true, return values. Otherwise, this is a parse error: consume a token and append it.
                if (nested) return;
                try p.appendToken(out);
                continue;
            }
            try p.consumeComponentValue(out);
        }
    }

    fn appendToken(p: *Parser, out: *std.ArrayList(ComponentValue)) Allocator.Error!void {
        const token = p.tokens[p.index];
        try out.append(p.gpa, .{ .kind = .token, .token = token, .end = token.range.end });
        p.index += 1;
    }

    /// "Consume a component value" (5.5.8), with "consume a simple block" (5.5.9) and "consume a function" (5.5.10),
    /// appending the value and its contents to `out` in preorder. The token stream must not be empty.
    fn consumeComponentValue(p: *Parser, out: *std.ArrayList(ComponentValue)) Allocator.Error!void {
        const base = p.open.items.len;
        defer p.open.shrinkRetainingCapacity(base);
        while (true) {
            const token = p.nextToken() orelse {
                // <eof-token>: discard a token and return each open function or block.
                const end = p.consumedEnd(0);
                while (p.open.items.len > base) close(out, p.open.pop().?, end);
                return;
            };
            if (p.open.items.len > base) {
                const open_index = p.open.items[p.open.items.len - 1];
                if (token.kind == endingToken(out.items[open_index])) {
                    // The ending token: discard a token and return the function or block.
                    p.index += 1;
                    close(out, p.open.pop().?, token.range.end);
                    if (p.open.items.len == base) return;
                    continue;
                }
            }
            switch (token.kind) {
                .open_curly, .open_square, .open_paren, .function => {
                    try p.open.ensureUnusedCapacity(p.gpa, 1);
                    try out.append(p.gpa, .{
                        .kind = if (token.kind == .function) .function else .block,
                        .token = token,
                        .end = token.range.end,
                    });
                    p.open.appendAssumeCapacity(out.items.len - 1);
                    p.index += 1;
                },
                else => {
                    try p.appendToken(out);
                    if (p.open.items.len == base) return;
                },
            }
        }
    }
};

/// Records the contents length and source end of the function or block at `index`.
fn close(out: *std.ArrayList(ComponentValue), index: usize, end: usize) void {
    out.items[index].descendants = out.items.len - index - 1;
    out.items[index].end = end;
}

/// The token that ends a function or simple block: the mirror variant of a block's opening token.
fn endingToken(value: ComponentValue) TokenKind {
    return switch (value.token.kind) {
        .function, .open_paren => .close_paren,
        .open_square => .close_square,
        .open_curly => .close_curly,
        else => unreachable,
    };
}

/// Appends a nonempty decls list to the block's items and starts a fresh one.
fn flushDeclarations(arena: Allocator, frame: *BlockFrame) Allocator.Error!void {
    if (frame.decls.items.len == 0) return;
    const decls = try frame.decls.toOwnedSlice(arena);
    try frame.items.append(arena, .{ .declarations = decls });
}

/// "Consume a qualified rule", <{-token> branch: the first declaration list becomes the rule's declarations,
/// and each remaining declaration list becomes a nested declarations rule.
fn fillQualifiedRule(arena: Allocator, rule: *QualifiedRule, items: []const BlockItem) Allocator.Error!void {
    var rest = items;
    if (rest.len != 0 and rest[0] == .declarations) {
        rule.declarations = rest[0].declarations;
        rest = rest[1..];
    }
    const rules = try arena.alloc(Rule, rest.len);
    for (rest, rules) |child, *slot| {
        slot.* = switch (child) {
            .rule => |nested_rule| nested_rule,
            .declarations => |declarations| .{ .nested_declarations = declarations },
        };
    }
    rule.rules = rules;
}

/// Whether the first two non-whitespace values are an <ident-token> starting with "--" and a <colon-token>.
fn looksLikeCustomProperty(prelude: []const ComponentValue) bool {
    var seen: usize = 0;
    var index: usize = 0;
    while (index < prelude.len) : (index = nextItem(prelude, index)) {
        const value = prelude[index];
        if (value.isToken(.whitespace)) continue;
        switch (seen) {
            0 => {
                if (!value.isToken(.ident) or !std.mem.startsWith(u16, value.token.value, &.{ '-', '-' })) return false;
                seen = 1;
            },
            else => return value.isToken(.colon),
        }
    }
    return false;
}

/// A custom property name string starts with two hyphen-minus characters.
pub fn isCustomPropertyNameString(name: []const u16) bool {
    return std.mem.startsWith(u16, name, &.{ '-', '-' });
}

/// The end of the last top-level item of a nonempty list.
fn lastItemEnd(list: []const ComponentValue) usize {
    var index: usize = 0;
    var last: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) last = index;
    return list[last].end;
}

/// The index of the "!" when the last two non-whitespace top-level items are "!" and "important".
fn importantStart(list: []const ComponentValue) ?usize {
    var previous: ?usize = null;
    var last: ?usize = null;
    var index: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) {
        if (list[index].isToken(.whitespace)) continue;
        previous = last;
        last = index;
    }
    const bang = previous orelse return null;
    const word = list[last.?];
    if (!list[bang].isDelim('!')) return null;
    if (!word.isToken(.ident) or !tokenizer.asciiCaseInsensitiveEql(word.token.value, "important")) return null;
    return bang;
}

fn trimTrailingWhitespace(list: []const ComponentValue) []const ComponentValue {
    var end: usize = 0;
    var index: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) {
        if (!list[index].isToken(.whitespace)) end = nextItem(list, index);
    }
    return list[0..end];
}

/// Whether the list holds a top-level {}-block and any other non-whitespace value.
fn hasCurlyBlockWithOtherValues(list: []const ComponentValue) bool {
    var curly = false;
    var non_whitespace: usize = 0;
    var index: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) {
        const value = list[index];
        if (value.isToken(.whitespace)) continue;
        non_whitespace += 1;
        if (value.kind == .block and value.token.kind == .open_curly) curly = true;
    }
    return curly and non_whitespace > 1;
}

/// Encodes code points as UTF-16 code units in `arena`.
pub fn utf16(arena: Allocator, code_points: []const u21) Allocator.Error![]const u16 {
    var len: usize = 0;
    for (code_points) |code_point| len += if (code_point < 0x10000) 1 else 2;
    const units = try arena.alloc(u16, len);
    var index: usize = 0;
    for (code_points) |code_point| {
        if (code_point < 0x10000) {
            units[index] = @intCast(code_point);
            index += 1;
        } else {
            const offset = code_point - 0x10000;
            units[index] = @intCast(0xD800 + (offset >> 10));
            units[index + 1] = @intCast(0xDC00 + (offset & 0x3FF));
            index += 2;
        }
    }
    return units;
}
