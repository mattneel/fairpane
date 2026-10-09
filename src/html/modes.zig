//! The 21 insertion modes of HTML Standard §13.2.4.1, at whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`,
//! and the branches of each mode that tree construction implements.
//!
//! Tree construction implements ten modes: initial, before html, before head, in head, in head noscript, after head,
//! in body, text, after body, and after after body. `FP-0102` owns the seven table modes, and `FP-0103` owns in template,
//! in frameset, after frameset, and after after frameset.

const std = @import("std");

/// One tag per mode, in the order that the standard lists them, which is also the order of §13.2.6.4.1 to §13.2.6.4.21.
pub const Mode = enum(u8) {
    initial,
    before_html,
    before_head,
    in_head,
    in_head_noscript,
    after_head,
    in_body,
    text,
    in_table,
    in_table_text,
    in_caption,
    in_column_group,
    in_table_body,
    in_row,
    in_cell,
    in_template,
    after_body,
    in_frameset,
    after_frameset,
    after_after_body,
    after_after_frameset,
};

/// The name of each mode, in mode order.
const titles = [_][]const u8{
    "initial",
    "before html",
    "before head",
    "in head",
    "in head noscript",
    "after head",
    "in body",
    "text",
    "in table",
    "in table text",
    "in caption",
    "in column group",
    "in table body",
    "in row",
    "in cell",
    "in template",
    "after body",
    "in frameset",
    "after frameset",
    "after after body",
    "after after frameset",
};

comptime {
    std.debug.assert(titles.len == std.enums.values(Mode).len);
}

/// Returns N for the mode's section §13.2.6.4.N, from 1 to 21.
pub fn section(mode: Mode) u8 {
    return @as(u8, @backingInt(mode)) + 1;
}

/// Returns the mode's name, such as "in head noscript".
pub fn title(mode: Mode) []const u8 {
    return titles[@backingInt(mode)];
}

/// Whether tree construction implements `mode`.
pub fn implemented(mode: Mode) bool {
    return owner(mode) == null;
}

/// Returns the task that owns an unimplemented mode, or null for an implemented mode.
pub fn owner(mode: Mode) ?[]const u8 {
    return switch (mode) {
        .in_table, .in_table_text, .in_caption, .in_column_group, .in_table_body, .in_row, .in_cell => "FP-0102",
        .in_template, .in_frameset, .after_frameset, .after_after_frameset => "FP-0103",
        .initial, .before_html, .before_head, .in_head, .in_head_noscript, .after_head, .in_body, .text, .after_body, .after_after_body => null,
    };
}

/// Returns the branches of `mode`, in the order of its section's entries, or none for an unimplemented mode.
/// "whitespace" means U+0009, U+000A, U+000C, U+000D, or U+0020. The address group is the 25 start tag names at
/// lines 146967 to 146969 of the pinned source, the address end group is the 28 end tag names at lines 147204 to 147207,
/// the b group is the 12 start tag names at lines 147387 to 147388, and the formatting end group is the 14 end tag names
/// at lines 147409 to 147411.
pub fn branches(mode: Mode) []const []const u8 {
    return switch (mode) {
        .initial => &.{ "whitespace", "comment", "processing instruction", "DOCTYPE", "else" },
        .before_html => &.{
            "DOCTYPE",
            "comment",
            "processing instruction",
            "whitespace",
            "start html",
            "end head, body, html, or br",
            "other end tag",
            "else",
        },
        .before_head => &.{
            "whitespace",
            "comment",
            "processing instruction",
            "DOCTYPE",
            "start html",
            "start head",
            "end head, body, html, or br",
            "other end tag",
            "else",
        },
        .in_head => &.{
            "whitespace",
            "comment",
            "processing instruction",
            "DOCTYPE",
            "start html",
            "start base, basefont, bgsound, or link",
            "start meta",
            "start title",
            "start noscript when scripting is not Disabled, noframes, or style",
            "start noscript when scripting is Disabled",
            "start script",
            "end head",
            "end body, html, or br",
            "start template",
            "end template",
            "start head or other end tag",
            "else",
        },
        .in_head_noscript => &.{
            "DOCTYPE",
            "start html",
            "end noscript",
            "whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style",
            "end br",
            "start head or noscript, or other end tag",
            "else",
        },
        .after_head => &.{
            "whitespace",
            "comment",
            "processing instruction",
            "DOCTYPE",
            "start html",
            "start body",
            "start frameset",
            "start base, basefont, bgsound, link, meta, noframes, script, style, template, or title",
            "end template",
            "end body, html, or br",
            "start head or other end tag",
            "else",
        },
        .in_body => &.{
            "NULL",
            "whitespace",
            "other character",
            "comment",
            "processing instruction",
            "DOCTYPE",
            "start html",
            "start base, basefont, bgsound, link, meta, noframes, script, style, template, or title, or end template",
            "start body",
            "start frameset",
            "EOF",
            "end body",
            "end html",
            "start address group",
            "start h1 to h6",
            "start pre or listing",
            "start form",
            "start li",
            "start dd or dt",
            "start plaintext",
            "start button",
            "end address group",
            "end form",
            "end p",
            "end li",
            "end dd or dt",
            "end h1 to h6",
            "end sarcasm",
            "start a",
            "start b group",
            "start nobr",
            "end formatting group",
            "start applet, marquee, or object",
            "end applet, marquee, or object",
            "start table",
            "end br",
            "start area, br, embed, img, keygen, or wbr",
            "start input",
            "start param, source, or track",
            "start hr",
            "start image",
            "start textarea",
            "start xmp",
            "start iframe",
            "start noembed, or noscript when scripting is not Disabled",
            "start select",
            "start option",
            "start optgroup",
            "start rb or rtc",
            "start rp or rt",
            "start math",
            "start svg",
            "start caption, col, colgroup, frame, head, tbody, td, tfoot, th, thead, or tr",
            "other start tag",
            "other end tag",
        },
        .text => &.{ "character", "EOF", "end script", "other end tag" },
        .after_body => &.{
            "whitespace",
            "comment",
            "processing instruction",
            "DOCTYPE",
            "start html",
            "end html",
            "EOF",
            "else",
        },
        .after_after_body => &.{ "comment", "processing instruction", "DOCTYPE, whitespace, or start html", "EOF", "else" },
        .in_table,
        .in_table_text,
        .in_caption,
        .in_column_group,
        .in_table_body,
        .in_row,
        .in_cell,
        .in_template,
        .in_frameset,
        .after_frameset,
        .after_after_frameset,
        => &.{},
    };
}

/// The index of each mode's first branch in a flat list of every branch, followed by the total.
const branch_offsets = offsets: {
    @setEvalBranchQuota(10_000);
    var result: [titles.len + 1]usize = undefined;
    var total: usize = 0;
    for (std.enums.values(Mode), 0..) |mode, index| {
        result[index] = total;
        total += branches(mode).len;
    }
    result[titles.len] = total;
    break :offsets result;
};

/// The number of branches of all modes.
pub const branch_count: usize = branch_offsets[titles.len];

/// Returns the flat index of the branch named `name` of `mode`, or a compile error for an unknown name.
pub fn branchIndex(comptime mode: Mode, comptime name: []const u8) usize {
    comptime {
        @setEvalBranchQuota(10_000);
        for (branches(mode), 0..) |branch, index| {
            if (std.mem.eql(u8, branch, name)) return branch_offsets[@backingInt(mode)] + index;
        }
        @compileError("mode " ++ @tagName(mode) ++ " has no branch named \"" ++ name ++ "\"");
    }
}

/// Returns the mode and branch name of a flat branch index.
pub fn branchAt(index: usize) struct { mode: Mode, name: []const u8 } {
    for (std.enums.values(Mode), 0..) |mode, position| {
        if (index < branch_offsets[position + 1]) return .{ .mode = mode, .name = branches(mode)[index - branch_offsets[position]] };
    }
    unreachable;
}
