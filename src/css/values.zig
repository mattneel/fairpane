//! Declared-value grammars and computed values for the registered properties.
//!
//! Each frozen grammar accepts a subset of its property's standard grammar.
//! A standard form outside that subset gives `unsupported`, and any other mismatch gives `invalid`;
//! both drop the declaration, as a user agent without the feature drops it.
//! Keywords and unit identifiers compare ASCII case-insensitively (Values 4 sections 4.1 and 5.4).
//! No function recurses: nested values are flat preorder lists.

const std = @import("std");
const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");
const registry = @import("registry.zig");
const substitution = @import("substitution.zig");
const ComponentValue = parser.ComponentValue;
const PropertyId = registry.PropertyId;
const PropertyKey = registry.PropertyKey;
const nextItem = parser.nextItem;
const eqlIgnoreCase = tokenizer.asciiCaseInsensitiveEql;

/// The user agent's `medium` font size in pixels.
pub const medium_font_size: f64 = 16;
/// The ratio of `larger` and `smaller`.
pub const relative_size_ratio: f64 = 1.2;

/// The CSS-wide keywords (Cascade 5 section 7.3).
pub const CssWideKeyword = enum { initial, inherit, unset, revert, revert_layer, revert_rule };

/// Returns the CSS-wide keyword when the list is one such keyword with optional whitespace.
pub fn cssWideKeyword(list: []const ComponentValue) ?CssWideKeyword {
    const trimmed = parser.trimWhitespace(list);
    if (trimmed.len != 1 or !trimmed[0].isToken(.ident)) return null;
    const name = trimmed[0].token.value;
    inline for (.{
        .{ "initial", CssWideKeyword.initial },
        .{ "inherit", CssWideKeyword.inherit },
        .{ "unset", CssWideKeyword.unset },
        .{ "revert", CssWideKeyword.revert },
        .{ "revert-layer", CssWideKeyword.revert_layer },
        .{ "revert-rule", CssWideKeyword.revert_rule },
    }) |entry| {
        if (eqlIgnoreCase(name, entry[0])) return entry[1];
    }
    return null;
}

// Display (CSS Display Level 4, sections 2 and 2.3).

pub const Outer = enum { block, @"inline", run_in };
pub const Inner = enum { flow, flow_root, table };
pub const Internal = enum {
    table_row_group,
    table_header_group,
    table_footer_group,
    table_row,
    table_cell,
    table_column_group,
    table_column,
    table_caption,
};
pub const DisplayPair = struct {
    outer: Outer,
    inner: Inner,
    list_item: bool = false,
};

/// The computed `display`.
pub const Display = union(enum) {
    none,
    contents,
    pair: DisplayPair,
    internal: Internal,
};

/// The declared `display`.
pub const SpecifiedDisplay = union(enum) {
    none,
    contents,
    pair: DisplayPair,
    internal: Internal,
};

// Color (CSS Color Level 4).

/// sRGB components and alpha. A null component is missing (`none`).
pub const Rgba = struct {
    red: ?f64,
    green: ?f64,
    blue: ?f64,
    alpha: ?f64,
};

/// The computed `color`.
pub const Color = union(enum) {
    current_color,
    srgb: Rgba,
};

/// The system colors of Color 4 section 6.2.
pub const SystemColor = enum {
    accent_color,
    accent_color_text,
    active_text,
    button_border,
    button_face,
    button_text,
    canvas,
    canvas_text,
    field,
    field_text,
    gray_text,
    highlight,
    highlight_text,
    link_text,
    mark,
    mark_text,
    selected_item,
    selected_item_text,
    visited_text,

    pub const names = [_][]const u8{
        "AccentColor",   "AccentColorText", "ActiveText", "ButtonBorder", "ButtonFace",   "ButtonText",
        "Canvas",        "CanvasText",      "Field",      "FieldText",    "GrayText",     "Highlight",
        "HighlightText", "LinkText",        "Mark",       "MarkText",     "SelectedItem", "SelectedItemText",
        "VisitedText",
    };

    /// The user agent's light palette. Every color is opaque.
    pub fn srgb(color: SystemColor) [3]u8 {
        return switch (color) {
            .accent_color => .{ 0, 96, 223 },
            .accent_color_text => .{ 255, 255, 255 },
            .active_text => .{ 238, 0, 0 },
            .button_border => .{ 118, 118, 118 },
            .button_face => .{ 239, 239, 239 },
            .button_text => .{ 0, 0, 0 },
            .canvas => .{ 255, 255, 255 },
            .canvas_text => .{ 0, 0, 0 },
            .field => .{ 255, 255, 255 },
            .field_text => .{ 0, 0, 0 },
            .gray_text => .{ 109, 109, 109 },
            .highlight => .{ 0, 96, 223 },
            .highlight_text => .{ 255, 255, 255 },
            .link_text => .{ 0, 0, 238 },
            .mark => .{ 255, 255, 0 },
            .mark_text => .{ 0, 0, 0 },
            .selected_item => .{ 0, 96, 223 },
            .selected_item_text => .{ 255, 255, 255 },
            .visited_text => .{ 85, 26, 139 },
        };
    }
};

/// The deprecated system colors of Color 4 Appendix A and the system colors that they compute to.
pub const deprecated_system_colors = [_]struct { name: []const u8, color: SystemColor }{
    .{ .name = "ActiveBorder", .color = .button_border },
    .{ .name = "ActiveCaption", .color = .canvas },
    .{ .name = "AppWorkspace", .color = .canvas },
    .{ .name = "Background", .color = .canvas },
    .{ .name = "ButtonHighlight", .color = .button_face },
    .{ .name = "ButtonShadow", .color = .button_face },
    .{ .name = "CaptionText", .color = .canvas_text },
    .{ .name = "InactiveBorder", .color = .button_border },
    .{ .name = "InactiveCaption", .color = .canvas },
    .{ .name = "InactiveCaptionText", .color = .gray_text },
    .{ .name = "InfoBackground", .color = .canvas },
    .{ .name = "InfoText", .color = .canvas_text },
    .{ .name = "Menu", .color = .canvas },
    .{ .name = "MenuText", .color = .canvas_text },
    .{ .name = "Scrollbar", .color = .canvas },
    .{ .name = "ThreeDDarkShadow", .color = .button_border },
    .{ .name = "ThreeDFace", .color = .button_face },
    .{ .name = "ThreeDHighlight", .color = .button_border },
    .{ .name = "ThreeDLightShadow", .color = .button_border },
    .{ .name = "ThreeDShadow", .color = .button_border },
    .{ .name = "Window", .color = .canvas },
    .{ .name = "WindowFrame", .color = .button_border },
    .{ .name = "WindowText", .color = .canvas_text },
};

/// One row of `named_colors.zig`.
pub const NamedColor = struct {
    name: []const u8,
    red: u8,
    green: u8,
    blue: u8,
};

/// The 148 named colors of Color 4 section 6.1, in ascending name order.
pub const named_colors: []const NamedColor = &@import("named_colors.zig").rows;

comptime {
    @setEvalBranchQuota(200_000);
    if (named_colors.len != 148) @compileError("named_colors.zig must hold 148 rows");
    for (named_colors[1..], 0..) |row, index| {
        if (std.mem.order(u8, named_colors[index].name, row.name) != .lt) @compileError("named_colors.zig is not in ascending order");
    }
}

/// Looks up a named color ASCII case-insensitively.
pub fn namedColor(name: []const u16) ?NamedColor {
    var buffer: [32]u8 = undefined;
    if (name.len > buffer.len) return null;
    for (name, buffer[0..name.len]) |unit, *byte| {
        if (unit > 0x7F) return null;
        byte.* = std.ascii.toLower(@intCast(unit));
    }
    const lowered = buffer[0..name.len];
    var low: usize = 0;
    var high: usize = named_colors.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        switch (std.mem.order(u8, named_colors[middle].name, lowered)) {
            .eq => return named_colors[middle],
            .lt => low = middle + 1,
            .gt => high = middle,
        }
    }
    return null;
}

/// The declared `color`.
pub const SpecifiedColor = union(enum) {
    current_color,
    srgb: Rgba,
    /// A system color or a deprecated system color, resolved through the palette at computed-value time.
    system: SystemColor,
};

// Lengths (CSS Values and Units Level 4, sections 5, 6.1.1, and 6.2).

pub const LengthUnit = enum { px, cm, mm, q, in, pt, pc, em, rem };

pub const Length = struct {
    value: f64,
    unit: LengthUnit,
};

pub const AbsoluteSize = enum {
    xx_small,
    x_small,
    small,
    medium,
    large,
    x_large,
    xx_large,
    xxx_large,

    /// The scaling factor numerator and denominator of Fonts 4 section 2.5.1.
    pub fn factor(size: AbsoluteSize) [2]f64 {
        return switch (size) {
            .xx_small => .{ 3, 5 },
            .x_small => .{ 3, 4 },
            .small => .{ 8, 9 },
            .medium => .{ 1, 1 },
            .large => .{ 6, 5 },
            .x_large => .{ 3, 2 },
            .xx_large => .{ 2, 1 },
            .xxx_large => .{ 3, 1 },
        };
    }
};

/// The declared `font-size`.
pub const SpecifiedFontSize = union(enum) {
    absolute: AbsoluteSize,
    larger,
    smaller,
    length: Length,
    percentage: f64,
};

/// The declared `margin-*`.
pub const SpecifiedMargin = union(enum) {
    auto,
    length: Length,
    percentage: f64,
};

/// The computed `margin-*`: `auto`, a length in pixels, or a percentage.
pub const LengthPercentageAuto = union(enum) {
    auto,
    length: f64,
    percentage: f64,
};

/// The computed value of a custom property: the guaranteed-invalid value, or a token list.
pub const CustomValue = union(enum) {
    guaranteed_invalid,
    tokens: []const ComponentValue,
};

/// A custom property's declared value: its token list and its original text (Syntax 5.5.6, Variables 2.1).
pub const CustomDeclared = struct {
    tokens: []const ComponentValue,
    original_text: []const u16,
};

/// A declared value. It holds no computed value.
pub const DeclaredValue = union(enum) {
    keyword: CssWideKeyword,
    display: SpecifiedDisplay,
    color: SpecifiedColor,
    font_size: SpecifiedFontSize,
    margin: SpecifiedMargin,
    /// A standard property value that contains `var()`. Its grammar is checked after substitution.
    pending: []const ComponentValue,
    custom: CustomDeclared,
};

pub const Outcome = union(enum) {
    value: DeclaredValue,
    invalid,
    unsupported,
};

/// Parses a declared value of `property` from a declaration's value.
/// `original_text` is the declaration's original text, which a custom property keeps.
pub fn parseDeclared(property: PropertyKey, list: []const ComponentValue, original_text: []const u16) Outcome {
    if (cssWideKeyword(list)) |keyword| return .{ .value = .{ .keyword = keyword } };
    switch (property) {
        .custom => {
            // Every var() must match its argument grammar, and the value must match <declaration-value>?.
            if (!substitution.checkVarArguments(list)) return .invalid;
            if (!substitution.isDeclarationValue(list)) return .invalid;
            return .{ .value = .{ .custom = .{ .tokens = list, .original_text = original_text } } };
        },
        .standard => |id| {
            // A value with var() is assumed valid at parse time when every var() matches its argument grammar.
            if (substitution.containsVar(list)) {
                if (!substitution.checkVarArguments(list)) return .invalid;
                return .{ .value = .{ .pending = list } };
            }
            return parser.parseGrammar(list, StandardGrammar{ .id = id });
        },
    }
}

/// A property's declared-value grammar, including CSS-wide keywords and `var()`, for `parser.parseGrammar`.
/// `original_text` is the declaration's original text, which a custom property keeps.
pub const DeclaredGrammar = struct {
    property: PropertyKey,
    original_text: []const u16 = &.{},

    pub const Result = Outcome;

    pub fn match(grammar: DeclaredGrammar, list: []const ComponentValue) Outcome {
        return parseDeclared(grammar.property, list, grammar.original_text);
    }
};

/// A standard property's grammar for a value without `var()`, such as a value after substitution, for `parser.parseGrammar`.
pub const StandardGrammar = struct {
    id: PropertyId,

    pub const Result = Outcome;

    pub fn match(grammar: StandardGrammar, list: []const ComponentValue) Outcome {
        return parseStandard(grammar.id, list);
    }
};

/// Parses a value of a standard property that contains no `var()`, such as a value after substitution.
/// A CSS-wide keyword gives that keyword.
pub fn parseStandard(id: PropertyId, list: []const ComponentValue) Outcome {
    if (cssWideKeyword(list)) |keyword| return .{ .value = .{ .keyword = keyword } };
    // Any function other than var(), rgb(), and rgba() is a standard form outside the frozen subset.
    for (list) |value| {
        if (value.kind != .function) continue;
        const name = value.token.value;
        if (!eqlIgnoreCase(name, "var") and !eqlIgnoreCase(name, "rgb") and !eqlIgnoreCase(name, "rgba")) return .unsupported;
    }
    return switch (id) {
        .display => parseDisplay(list),
        .color => parseColor(list),
        .font_size => parseFontSize(list),
        .margin_top, .margin_right, .margin_bottom, .margin_left => parseMargin(list),
    };
}

/// The declared initial value of each property, which `initial_text` parses to (case 27 checks this).
pub fn initialValue(id: PropertyId) DeclaredValue {
    return switch (id) {
        .display => .{ .display = .{ .pair = .{ .outer = .@"inline", .inner = .flow } } },
        .color => .{ .color = .{ .system = .canvas_text } },
        .font_size => .{ .font_size = .{ .absolute = .medium } },
        .margin_top, .margin_right, .margin_bottom, .margin_left => .{ .margin = .{ .length = .{ .value = 0, .unit = .px } } },
    };
}

/// The non-whitespace top-level items of a list, up to a fixed count.
const Items = struct {
    indexes: [4]usize = undefined,
    len: usize = 0,
    /// Whether the list has more items than `indexes` holds.
    overflow: bool = false,

    fn of(list: []const ComponentValue) Items {
        var items: Items = .{};
        var index: usize = 0;
        while (index < list.len) : (index = nextItem(list, index)) {
            if (list[index].isToken(.whitespace)) continue;
            if (items.len == items.indexes.len) {
                items.overflow = true;
                break;
            }
            items.indexes[items.len] = index;
            items.len += 1;
        }
        return items;
    }

    fn single(list: []const ComponentValue) ?ComponentValue {
        const items = of(list);
        if (items.overflow or items.len != 1) return null;
        return list[items.indexes[0]];
    }
};

const unsupported_display_keywords = [_][]const u8{
    "flex",      "grid",      "ruby",                "inline-flex",         "inline-grid",
    "ruby-base", "ruby-text", "ruby-base-container", "ruby-text-container",
};

fn parseDisplay(list: []const ComponentValue) Outcome {
    // A value that contains a keyword whose computed value needs flex, grid, or ruby containment is unsupported.
    var index: usize = 0;
    while (index < list.len) : (index = nextItem(list, index)) {
        if (!list[index].isToken(.ident)) continue;
        inline for (unsupported_display_keywords) |keyword| {
            if (eqlIgnoreCase(list[index].token.value, keyword)) return .unsupported;
        }
    }
    const items = Items.of(list);
    if (items.overflow or items.len == 0) return .invalid;
    for (items.indexes[0..items.len]) |item_index| {
        if (!list[item_index].isToken(.ident)) return .invalid;
    }
    if (items.len == 1) {
        const word = list[items.indexes[0]].token.value;
        const single_keywords = .{
            .{ "none", SpecifiedDisplay.none },
            .{ "contents", SpecifiedDisplay.contents },
            .{ "inline-block", SpecifiedDisplay{ .pair = .{ .outer = .@"inline", .inner = .flow_root } } },
            .{ "inline-table", SpecifiedDisplay{ .pair = .{ .outer = .@"inline", .inner = .table } } },
            .{ "table-row-group", SpecifiedDisplay{ .internal = .table_row_group } },
            .{ "table-header-group", SpecifiedDisplay{ .internal = .table_header_group } },
            .{ "table-footer-group", SpecifiedDisplay{ .internal = .table_footer_group } },
            .{ "table-row", SpecifiedDisplay{ .internal = .table_row } },
            .{ "table-cell", SpecifiedDisplay{ .internal = .table_cell } },
            .{ "table-column-group", SpecifiedDisplay{ .internal = .table_column_group } },
            .{ "table-column", SpecifiedDisplay{ .internal = .table_column } },
            .{ "table-caption", SpecifiedDisplay{ .internal = .table_caption } },
        };
        inline for (single_keywords) |entry| {
            if (eqlIgnoreCase(word, entry[0])) return .{ .value = .{ .display = entry[1] } };
        }
    }
    // Multi-keyword values, in any order: an outer type, an inner type, and list-item.
    var outer: ?Outer = null;
    var inner: ?Inner = null;
    var list_item = false;
    for (items.indexes[0..items.len]) |item_index| {
        const word = list[item_index].token.value;
        if (eqlIgnoreCase(word, "block") or eqlIgnoreCase(word, "inline") or eqlIgnoreCase(word, "run-in")) {
            if (outer != null) return .invalid;
            outer = if (eqlIgnoreCase(word, "block")) .block else if (eqlIgnoreCase(word, "inline")) .@"inline" else .run_in;
        } else if (eqlIgnoreCase(word, "flow") or eqlIgnoreCase(word, "flow-root") or eqlIgnoreCase(word, "table")) {
            if (inner != null) return .invalid;
            inner = if (eqlIgnoreCase(word, "flow")) .flow else if (eqlIgnoreCase(word, "flow-root")) .flow_root else .table;
        } else if (eqlIgnoreCase(word, "list-item")) {
            if (list_item) return .invalid;
            list_item = true;
        } else {
            return .invalid;
        }
    }
    // list-item takes only flow or flow-root as its inner type.
    if (list_item and inner == .table) return .invalid;
    return .{ .value = .{ .display = .{ .pair = .{
        .outer = outer orelse .block,
        .inner = inner orelse .flow,
        .list_item = list_item,
    } } } };
}

fn parseColor(list: []const ComponentValue) Outcome {
    const value = Items.single(list) orelse return .invalid;
    switch (value.kind) {
        .token => switch (value.token.kind) {
            .hash => return if (hexColor(value.token.value)) |rgba| .{ .value = .{ .color = .{ .srgb = rgba } } } else .invalid,
            .ident => {
                const name = value.token.value;
                if (eqlIgnoreCase(name, "currentcolor")) return .{ .value = .{ .color = .current_color } };
                if (eqlIgnoreCase(name, "transparent")) return .{ .value = .{ .color = .{ .srgb = .{ .red = 0, .green = 0, .blue = 0, .alpha = 0 } } } };
                if (namedColor(name)) |row| return .{ .value = .{ .color = .{ .srgb = opaqueRgba(.{ row.red, row.green, row.blue }) } } };
                inline for (SystemColor.names, 0..) |system_name, index| {
                    if (eqlIgnoreCase(name, system_name)) return .{ .value = .{ .color = .{ .system = @fromBackingInt(@intCast(index)) } } };
                }
                inline for (deprecated_system_colors) |entry| {
                    if (eqlIgnoreCase(name, entry.name)) return .{ .value = .{ .color = .{ .system = entry.color } } };
                }
                return .invalid;
            },
            else => return .invalid,
        },
        .function => {
            if (!eqlIgnoreCase(value.token.value, "rgb") and !eqlIgnoreCase(value.token.value, "rgba")) return .unsupported;
            return parseRgb(list[firstItem(list) + 1 ..][0..value.descendants]);
        },
        .block => return .invalid,
    }
}

fn firstItem(list: []const ComponentValue) usize {
    var index: usize = 0;
    while (list[index].isToken(.whitespace)) index += 1;
    return index;
}

fn opaqueRgba(rgb: [3]u8) Rgba {
    return .{ .red = @floatFromInt(rgb[0]), .green = @floatFromInt(rgb[1]), .blue = @floatFromInt(rgb[2]), .alpha = 1 };
}

/// A <hex-color>: 3, 4, 6, or 8 hexadecimal digits (Color 4 section 5.2).
fn hexColor(digits: []const u16) ?Rgba {
    var nibbles: [8]f64 = undefined;
    if (digits.len != 3 and digits.len != 4 and digits.len != 6 and digits.len != 8) return null;
    for (digits, nibbles[0..digits.len]) |unit, *nibble| {
        if (unit > 0x7F or !tokenizer.isHexDigit(unit)) return null;
        nibble.* = @floatFromInt(std.fmt.charToDigit(@intCast(unit), 16) catch unreachable);
    }
    return switch (digits.len) {
        3 => .{ .red = nibbles[0] * 17, .green = nibbles[1] * 17, .blue = nibbles[2] * 17, .alpha = 1 },
        4 => .{ .red = nibbles[0] * 17, .green = nibbles[1] * 17, .blue = nibbles[2] * 17, .alpha = nibbles[3] * 17 / 255 },
        6 => .{ .red = nibbles[0] * 16 + nibbles[1], .green = nibbles[2] * 16 + nibbles[3], .blue = nibbles[4] * 16 + nibbles[5], .alpha = 1 },
        8 => .{
            .red = nibbles[0] * 16 + nibbles[1],
            .green = nibbles[2] * 16 + nibbles[3],
            .blue = nibbles[4] * 16 + nibbles[5],
            .alpha = (nibbles[6] * 16 + nibbles[7]) / 255,
        },
        else => unreachable,
    };
}

const Component = union(enum) {
    number: f64,
    percentage: f64,
    none,
};

/// Replaces each "_" with "-", turning a tag name into a CSS keyword.
fn dashed(comptime name: []const u8) []const u8 {
    comptime var buffer: [name.len]u8 = undefined;
    inline for (name, 0..) |byte, index| buffer[index] = if (byte == '_') '-' else byte;
    const final = buffer;
    return &final;
}

/// A grammar for one legacy `rgb()` argument: a <number> or a <percentage>.
const LegacyComponent = struct {
    pub const Result = ?Component;

    pub fn match(_: LegacyComponent, list: []const ComponentValue) ?Component {
        const value = Items.single(list) orelse return null;
        if (value.isToken(.number)) return .{ .number = value.token.number };
        if (value.isToken(.percentage)) return .{ .percentage = value.token.number };
        return null;
    }
};

/// `rgb()` and `rgba()` in the legacy syntax (Color 4 section 4.1.2) and the modern syntax (4.1.1).
fn parseRgb(arguments: []const ComponentValue) Outcome {
    // Any function inside rgb() or rgba() is unsupported, and so is relative color syntax.
    for (arguments) |value| {
        if (value.kind == .function) return .unsupported;
    }
    const items_start = blk: {
        var index: usize = 0;
        while (index < arguments.len and arguments[index].isToken(.whitespace)) index += 1;
        break :blk index;
    };
    if (items_start < arguments.len and arguments[items_start].isToken(.ident) and eqlIgnoreCase(arguments[items_start].token.value, "from")) {
        return .unsupported;
    }
    var commas: usize = 0;
    var index: usize = 0;
    while (index < arguments.len) : (index = nextItem(arguments, index)) {
        if (arguments[index].isToken(.comma)) commas += 1;
    }
    var components: [4]Component = undefined;
    var count: usize = 0;
    if (commas != 0) {
        // The legacy syntax: three numbers or three percentages and an optional alpha, separated by commas.
        if (commas != 2 and commas != 3) return .invalid;
        // Room for every growth step of a list of at most four groups.
        var buffer: [32]?Component = undefined;
        var fixed: std.heap.FixedBufferAllocator = .init(std.mem.sliceAsBytes(&buffer));
        const groups = parser.parseGrammarList(fixed.allocator(), arguments, LegacyComponent{}) catch unreachable;
        // A trailing comma ends the comma-separated list early, so the group count shows it.
        if (groups.len != commas + 1) return .invalid;
        for (groups, 0..) |group, position| {
            components[position] = group orelse return .invalid;
        }
        count = groups.len;
        if (std.meta.activeTag(components[0]) != std.meta.activeTag(components[1]) or
            std.meta.activeTag(components[0]) != std.meta.activeTag(components[2])) return .invalid;
    } else {
        // The modern syntax: three numbers, percentages, or none, then an optional "/" and alpha.
        index = 0;
        var slash = false;
        while (index < arguments.len) : (index = nextItem(arguments, index)) {
            const value = arguments[index];
            if (value.isToken(.whitespace)) continue;
            if (value.isDelim('/')) {
                if (slash or count != 3) return .invalid;
                slash = true;
                continue;
            }
            if (count == 4 or (count == 3 and !slash)) return .invalid;
            components[count] = if (value.isToken(.number))
                .{ .number = value.token.number }
            else if (value.isToken(.percentage))
                .{ .percentage = value.token.number }
            else if (value.isToken(.ident) and eqlIgnoreCase(value.token.value, "none"))
                .none
            else
                return .invalid;
            count += 1;
        }
        if (count < 3 or (slash and count != 4)) return .invalid;
    }
    // Components clamp to [0, 255] and alpha to [0, 1] at parsed-value time; 100% is 255 or 1.
    return .{ .value = .{ .color = .{ .srgb = .{
        .red = colorComponent(components[0]),
        .green = colorComponent(components[1]),
        .blue = colorComponent(components[2]),
        .alpha = if (count == 4) alphaComponent(components[3]) else 1,
    } } } };
}

fn colorComponent(component: Component) ?f64 {
    return switch (component) {
        .number => |number| std.math.clamp(number, 0, 255),
        .percentage => |percentage| std.math.clamp(percentage * 255 / 100, 0, 255),
        .none => null,
    };
}

fn alphaComponent(component: Component) ?f64 {
    return switch (component) {
        .number => |number| std.math.clamp(number, 0, 1),
        .percentage => |percentage| std.math.clamp(percentage / 100, 0, 1),
        .none => null,
    };
}

const UnitClass = union(enum) {
    supported: LengthUnit,
    unsupported,
    unknown,
};

const unsupported_units = [_][]const u8{
    "ex",    "rex",   "cap",   "rcap",  "ch",   "rch",  "ic",    "ric",   "lh",    "rlh",
    "vw",    "vh",    "vi",    "vb",    "vmin", "vmax", "svw",   "svh",   "svi",   "svb",
    "svmin", "svmax", "lvw",   "lvh",   "lvi",  "lvb",  "lvmin", "lvmax", "dvw",   "dvh",
    "dvi",   "dvb",   "dvmin", "dvmax", "cqw",  "cqh",  "cqi",   "cqb",   "cqmin", "cqmax",
};

fn classifyUnit(unit: []const u16) UnitClass {
    inline for (comptime std.enums.values(LengthUnit)) |tag| {
        if (eqlIgnoreCase(unit, @tagName(tag))) return .{ .supported = tag };
    }
    inline for (unsupported_units) |name| {
        if (eqlIgnoreCase(unit, name)) return .unsupported;
    }
    return .unknown;
}

const LengthParse = union(enum) {
    length: Length,
    percentage: f64,
    unsupported,
    none,
};

/// A <length-percentage>: a dimension with a frozen unit, a percentage, or a unitless 0.
fn lengthPercentage(value: ComponentValue) LengthParse {
    if (value.isToken(.dimension)) {
        return switch (classifyUnit(value.token.unit)) {
            .supported => |unit| .{ .length = .{ .value = value.token.number, .unit = unit } },
            .unsupported => .unsupported,
            .unknown => .none,
        };
    }
    if (value.isToken(.percentage)) return .{ .percentage = value.token.number };
    if (value.isToken(.number) and value.token.number == 0) return .{ .length = .{ .value = 0, .unit = .px } };
    return .none;
}

fn parseFontSize(list: []const ComponentValue) Outcome {
    const value = Items.single(list) orelse return .invalid;
    if (value.isToken(.ident)) {
        const word = value.token.value;
        inline for (comptime std.enums.values(AbsoluteSize)) |tag| {
            if (eqlIgnoreCase(word, comptime dashed(@tagName(tag)))) return .{ .value = .{ .font_size = .{ .absolute = tag } } };
        }
        if (eqlIgnoreCase(word, "larger")) return .{ .value = .{ .font_size = .larger } };
        if (eqlIgnoreCase(word, "smaller")) return .{ .value = .{ .font_size = .smaller } };
        if (eqlIgnoreCase(word, "math")) return .unsupported;
        return .invalid;
    }
    // A nonnegative <length> or <percentage>.
    return switch (lengthPercentage(value)) {
        .length => |length| if (length.value < 0) .invalid else .{ .value = .{ .font_size = .{ .length = length } } },
        .percentage => |percentage| if (percentage < 0) .invalid else .{ .value = .{ .font_size = .{ .percentage = percentage } } },
        .unsupported => .unsupported,
        .none => .invalid,
    };
}

fn parseMargin(list: []const ComponentValue) Outcome {
    const value = Items.single(list) orelse return .invalid;
    if (value.isToken(.ident)) {
        if (eqlIgnoreCase(value.token.value, "auto")) return .{ .value = .{ .margin = .auto } };
        return .invalid;
    }
    return switch (lengthPercentage(value)) {
        .length => |length| .{ .value = .{ .margin = .{ .length = length } } },
        .percentage => |percentage| .{ .value = .{ .margin = .{ .percentage = percentage } } },
        .unsupported => .unsupported,
        .none => .invalid,
    };
}

// Computed values.

/// Computes `display`. The root element's value is blockified (Display 4 sections 2.7 and 2.8).
pub fn computeDisplay(specified: SpecifiedDisplay, is_root: bool) Display {
    const display: Display = switch (specified) {
        .none => .none,
        .contents => .contents,
        .pair => |pair| .{ .pair = pair },
        .internal => |internal| .{ .internal = internal },
    };
    return if (is_root) blockify(display) else display;
}

/// The root element's blockification (Display 4 sections 2.7 and 2.8). It applies to any computed `display`,
/// including an initial or inherited value.
pub fn blockify(display: Display) Display {
    return switch (display) {
        .none => .none,
        // The root element's `contents` computes to block flow, and so does a blockified internal value.
        .contents, .internal => .{ .pair = .{ .outer = .block, .inner = .flow } },
        .pair => |pair| .{
            .pair = .{
                .outer = .block,
                // An inline or run-in flow-root box blockifies to a block box, losing its flow-root nature.
                .inner = if (pair.inner == .flow_root and pair.outer != .block) .flow else pair.inner,
                .list_item = pair.list_item,
            },
        },
    };
}

/// Computes `color`: a named, hex, `rgb()`, `transparent`, or system color computes to its sRGB color,
/// and `currentcolor` computes to itself (Color 4 sections 15.1 and 15.5).
pub fn computeColor(specified: SpecifiedColor) Color {
    return switch (specified) {
        .current_color => .current_color,
        .srgb => |rgba| .{ .srgb = rgba },
        .system => |system| .{ .srgb = opaqueRgba(system.srgb()) },
    };
}

/// Converts a length to pixels, evaluated in `f64` from left to right.
/// `em_basis` is the font size that `em` refers to, and `rem_basis` the one that `rem` refers to.
pub fn lengthToPixels(length: Length, em_basis: f64, rem_basis: f64) f64 {
    const v = length.value;
    return switch (length.unit) {
        .px => v,
        .cm => v * 96 / 2.54,
        .mm => v * 96 / 25.4,
        .q => v * 96 / 101.6,
        .in => v * 96,
        .pt => v * 96 / 72,
        .pc => v * 96 / 6,
        .em => v * em_basis,
        .rem => v * rem_basis,
    };
}

/// Computes `font-size` in pixels. `parent_size` is the parent's computed size, and `root_size` the root element's;
/// on the root element both are `medium_font_size` (Values 4 section 6.1.1).
pub fn computeFontSize(specified: SpecifiedFontSize, parent_size: f64, root_size: f64) f64 {
    return switch (specified) {
        .absolute => |size| medium_font_size * size.factor()[0] / size.factor()[1],
        .larger => parent_size * relative_size_ratio,
        .smaller => parent_size / relative_size_ratio,
        .length => |length| lengthToPixels(length, parent_size, root_size),
        .percentage => |percentage| parent_size * percentage / 100,
    };
}

/// Computes `margin-*`: `em` uses the element's own computed font size, and `rem` the root element's.
pub fn computeMargin(specified: SpecifiedMargin, font_size: f64, root_size: f64) LengthPercentageAuto {
    return switch (specified) {
        .auto => .auto,
        .length => |length| .{ .length = lengthToPixels(length, font_size, root_size) },
        .percentage => |percentage| .{ .percentage = percentage },
    };
}
