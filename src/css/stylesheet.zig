//! CSS Syntax Module Level 3, section 8: CSS stylesheets, with a validator for the frozen subset.
//!
//! A top-level qualified rule is a style rule whose prelude parses as a selector list.
//! Every at-rule, at any level, is dropped with `ignored_at_rule`, because this task implements no at-rule;
//! that includes `@charset`, which section 8.3 defines as no rule.
//! A qualified rule inside a style rule's block is dropped with `nested_rule_ignored`,
//! and a nested declarations rule with `nested_declarations_ignored`, because CSS Nesting is outside this task.
//! An ignored at-rule reports one diagnostic, and nothing inside its block, at any depth, reports one,
//! because the validator does not check the block of an at-rule that it drops.

const std = @import("std");
const parser = @import("parser.zig");
const registry = @import("registry.zig");
const values = @import("values.zig");
const selectors = @import("selectors.zig");
const applicable = @import("applicable.zig");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const View = web_string.View;
const Range = parser.Range;
const ComponentValue = parser.ComponentValue;
const Context = parser.Context;

/// The cascade origin of a stylesheet (Cascade 5 section 6.2).
pub const Origin = applicable.Origin;

pub const DiagnosticKind = enum {
    invalid_selector,
    unsupported_selector,
    ignored_at_rule,
    nested_rule_ignored,
    nested_declarations_ignored,
    unknown_property,
    invalid_value,
    unsupported_value,
};

pub const Diagnostic = struct {
    kind: DiagnosticKind,
    range: Range,
    /// The at-rule name for `ignored_at_rule`, and the declaration name for
    /// `unknown_property`, `invalid_value`, and `unsupported_value`.
    name: ?[]const u16 = null,
};

/// A declaration of a registered property or a custom property, with its parsed declared value.
pub const PropertyDeclaration = struct {
    property: registry.PropertyKey,
    value: values.DeclaredValue,
    important: bool,
    range: Range,
};

pub const StyleRule = struct {
    selectors: selectors.SelectorList,
    declarations: []const PropertyDeclaration,
    range: Range,
};

pub const Stylesheet = struct {
    /// Holds the validator's results: selector lists, parsed declared values, diagnostics, and the rule list.
    arena: std.heap.ArenaAllocator,
    /// The syntax tree. It owns the filtered input, the tokens, and the component values that the rules reference.
    syntax: parser.Parsed([]const parser.Rule),
    origin: Origin,
    /// The valid top-level style rules in source order.
    rules: []const StyleRule,
    /// In the order that the parser encounters them.
    diagnostics: []const Diagnostic,

    /// Runs "parse a stylesheet" and keeps the valid top-level style rules in source order.
    pub fn parse(gpa: Allocator, source: View, origin: Origin) Allocator.Error!Stylesheet {
        var sheet: Stylesheet = undefined;
        sheet.arena = .init(gpa);
        errdefer sheet.arena.deinit();
        const arena = sheet.arena.allocator();
        var validator: SheetValidator = .{ .arena = arena };
        sheet.syntax = try parser.parseStylesheet(gpa, source, validator.validator());
        errdefer sheet.syntax.deinit();
        var rules: std.ArrayList(StyleRule) = .empty;
        for (sheet.syntax.value) |rule| {
            // Every valid top-level rule is a style rule, because every at-rule is dropped.
            const qualified = switch (rule) {
                .qualified => |qualified| qualified,
                .at, .nested_declarations => unreachable,
            };
            const list = validator.selector_lists.get(qualified.range.start).?;
            const declarations = try arena.alloc(PropertyDeclaration, qualified.declarations.len);
            for (qualified.declarations, declarations) |declaration, *slot| {
                slot.* = validator.declarations.get(declaration.range.start).?;
            }
            try rules.append(arena, .{ .selectors = list, .declarations = declarations, .range = qualified.range });
        }
        sheet.origin = origin;
        sheet.rules = rules.items;
        sheet.diagnostics = validator.diagnostics.items;
        return sheet;
    }

    /// The filtered code points that every source range indexes.
    pub fn input(sheet: *const Stylesheet) []const u21 {
        return sheet.syntax.input;
    }

    pub fn deinit(sheet: *Stylesheet) void {
        sheet.syntax.deinit();
        sheet.arena.deinit();
        sheet.* = undefined;
    }
};

/// The validator for the frozen subset. Its results live in the stylesheet's arena,
/// and they reference the component values of the syntax tree.
const SheetValidator = struct {
    arena: Allocator,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    /// Valid declarations of style rule blocks, by the start of the declaration's source range.
    declarations: std.AutoHashMapUnmanaged(usize, PropertyDeclaration) = .empty,
    /// The selector lists of top-level qualified rules, by the start of the rule's source range.
    selector_lists: std.AutoHashMapUnmanaged(usize, selectors.SelectorList) = .empty,

    fn validator(v: *SheetValidator) parser.Validator {
        return .{ .ptr = v, .vtable = &.{
            .qualifiedPrelude = qualifiedPrelude,
            .qualifiedRule = qualifiedRule,
            .atRuleBlock = atRuleBlock,
            .atRule = atRule,
            .declaration = declaration,
        } };
    }

    fn diagnose(v: *SheetValidator, diagnostic: Diagnostic) Allocator.Error!void {
        try v.diagnostics.append(v.arena, diagnostic);
    }

    fn qualifiedPrelude(ptr: ?*anyopaque, prelude: []const ComponentValue, context: Context) Allocator.Error!bool {
        const v: *SheetValidator = @ptrCast(@alignCast(ptr.?));
        // Only a top-level qualified rule is a style rule; the rule check drops the others.
        if (context != .top_level) return true;
        switch (try selectors.parseSelectorList(v.arena, prelude)) {
            .failure => |failure| {
                try v.diagnose(.{
                    .kind = switch (failure.kind) {
                        .invalid_selector => .invalid_selector,
                        .unsupported_selector => .unsupported_selector,
                    },
                    .range = failure.range,
                });
                return false;
            },
            .list => |list| {
                // A valid selector list is nonempty, and its first token starts the rule's source range.
                try v.selector_lists.put(v.arena, prelude[0].token.range.start, list);
                return true;
            },
        }
    }

    fn qualifiedRule(ptr: ?*anyopaque, rule: *const parser.QualifiedRule, context: Context, prelude_valid: bool) Allocator.Error!bool {
        const v: *SheetValidator = @ptrCast(@alignCast(ptr.?));
        switch (context) {
            .top_level => {
                for (rule.rules) |child| switch (child) {
                    .nested_declarations => |list| try v.diagnose(.{
                        .kind = .nested_declarations_ignored,
                        .range = .{ .start = list[0].range.start, .end = list[list.len - 1].range.end },
                    }),
                    // Nested rules were already dropped by their own checks.
                    .qualified, .at => unreachable,
                };
                return prelude_valid;
            },
            .qualified_rule_block => {
                try v.diagnose(.{ .kind = .nested_rule_ignored, .range = rule.range });
                return false;
            },
            // `atRuleBlock` silences the block of every at-rule.
            .at_rule_block => unreachable,
        }
    }

    /// Every at-rule is dropped, so the contents of its block are not checked.
    fn atRuleBlock(_: ?*anyopaque, _: *const parser.AtRule, _: Context) Allocator.Error!bool {
        return false;
    }

    fn atRule(ptr: ?*anyopaque, rule: *const parser.AtRule, _: Context) Allocator.Error!bool {
        const v: *SheetValidator = @ptrCast(@alignCast(ptr.?));
        try v.diagnose(.{ .kind = .ignored_at_rule, .range = rule.range, .name = rule.name });
        return false;
    }

    fn declaration(ptr: ?*anyopaque, decl: *const parser.Declaration, context: Context) Allocator.Error!bool {
        const v: *SheetValidator = @ptrCast(@alignCast(ptr.?));
        if (context != .qualified_rule_block) return false;
        const property = registry.lookup(.{ .units = decl.name }) orelse {
            try v.diagnose(.{ .kind = .unknown_property, .range = decl.range, .name = decl.name });
            return false;
        };
        const grammar: values.DeclaredGrammar = .{ .property = property, .original_text = decl.original_text orelse &.{} };
        switch (parser.parseGrammar(decl.value, grammar)) {
            .invalid => {
                try v.diagnose(.{ .kind = .invalid_value, .range = decl.range, .name = decl.name });
                return false;
            },
            .unsupported => {
                try v.diagnose(.{ .kind = .unsupported_value, .range = decl.range, .name = decl.name });
                return false;
            },
            .value => |value| {
                try v.declarations.put(v.arena, decl.range.start, .{
                    .property = property,
                    .value = value,
                    .important = decl.important,
                    .range = decl.range,
                });
                return true;
            },
        }
    }
};
