//! The 84 tokenizer states of HTML Standard §13.2.5.1 to §13.2.5.84, at whatwg/html commit
//! `efc54f7b70858d9fcf06d1a5871ae215f448c029`, and the branches of each implemented state.
//!
//! The tokenizer implements 54 states: exactly those that the machine reaches from its initial data state
//! without any action from tree construction. The other 30 states belong to task `FP-0064`.

const std = @import("std");

/// One tag per section, in section order.
pub const State = enum(u8) {
    data,
    rcdata,
    rawtext,
    script_data,
    plaintext,
    tag_open,
    end_tag_open,
    tag_name,
    rcdata_less_than_sign,
    rcdata_end_tag_open,
    rcdata_end_tag_name,
    rawtext_less_than_sign,
    rawtext_end_tag_open,
    rawtext_end_tag_name,
    script_data_less_than_sign,
    script_data_end_tag_open,
    script_data_end_tag_name,
    script_data_escape_start,
    script_data_escape_start_dash,
    script_data_escaped,
    script_data_escaped_dash,
    script_data_escaped_dash_dash,
    script_data_escaped_less_than_sign,
    script_data_escaped_end_tag_open,
    script_data_escaped_end_tag_name,
    script_data_double_escape_start,
    script_data_double_escaped,
    script_data_double_escaped_dash,
    script_data_double_escaped_dash_dash,
    script_data_double_escaped_less_than_sign,
    script_data_double_escape_end,
    before_attribute_name,
    attribute_name,
    after_attribute_name,
    before_attribute_value,
    attribute_value_double_quoted,
    attribute_value_single_quoted,
    attribute_value_unquoted,
    after_attribute_value_quoted,
    self_closing_start_tag,
    bogus_comment,
    markup_declaration_open,
    comment_start,
    comment_start_dash,
    comment,
    comment_less_than_sign,
    comment_less_than_sign_bang,
    comment_less_than_sign_bang_dash,
    comment_less_than_sign_bang_dash_dash,
    comment_end_dash,
    comment_end,
    comment_end_bang,
    doctype,
    before_doctype_name,
    doctype_name,
    after_doctype_name,
    after_doctype_public_keyword,
    before_doctype_public_identifier,
    doctype_public_identifier_double_quoted,
    doctype_public_identifier_single_quoted,
    after_doctype_public_identifier,
    between_doctype_public_and_system_identifiers,
    after_doctype_system_keyword,
    before_doctype_system_identifier,
    doctype_system_identifier_double_quoted,
    doctype_system_identifier_single_quoted,
    after_doctype_system_identifier,
    bogus_doctype,
    cdata_section,
    cdata_section_bracket,
    cdata_section_end,
    processing_instruction_open,
    processing_instruction_target,
    after_processing_instruction_target,
    processing_instruction_data,
    processing_instruction_questionable,
    character_reference,
    named_character_reference,
    ambiguous_ampersand,
    numeric_character_reference,
    hexadecimal_character_reference_start,
    hexadecimal_character_reference,
    decimal_character_reference,
    numeric_character_reference_end,
};

/// The headings of §13.2.5.1 to §13.2.5.84, in section order.
const titles = [_][]const u8{
    "Data state",
    "RCDATA state",
    "RAWTEXT state",
    "Script data state",
    "PLAINTEXT state",
    "Tag open state",
    "End tag open state",
    "Tag name state",
    "RCDATA less-than sign state",
    "RCDATA end tag open state",
    "RCDATA end tag name state",
    "RAWTEXT less-than sign state",
    "RAWTEXT end tag open state",
    "RAWTEXT end tag name state",
    "Script data less-than sign state",
    "Script data end tag open state",
    "Script data end tag name state",
    "Script data escape start state",
    "Script data escape start dash state",
    "Script data escaped state",
    "Script data escaped dash state",
    "Script data escaped dash dash state",
    "Script data escaped less-than sign state",
    "Script data escaped end tag open state",
    "Script data escaped end tag name state",
    "Script data double escape start state",
    "Script data double escaped state",
    "Script data double escaped dash state",
    "Script data double escaped dash dash state",
    "Script data double escaped less-than sign state",
    "Script data double escape end state",
    "Before attribute name state",
    "Attribute name state",
    "After attribute name state",
    "Before attribute value state",
    "Attribute value (double-quoted) state",
    "Attribute value (single-quoted) state",
    "Attribute value (unquoted) state",
    "After attribute value (quoted) state",
    "Self-closing start tag state",
    "Bogus comment state",
    "Markup declaration open state",
    "Comment start state",
    "Comment start dash state",
    "Comment state",
    "Comment less-than sign state",
    "Comment less-than sign bang state",
    "Comment less-than sign bang dash state",
    "Comment less-than sign bang dash dash state",
    "Comment end dash state",
    "Comment end state",
    "Comment end bang state",
    "DOCTYPE state",
    "Before DOCTYPE name state",
    "DOCTYPE name state",
    "After DOCTYPE name state",
    "After DOCTYPE public keyword state",
    "Before DOCTYPE public identifier state",
    "DOCTYPE public identifier (double-quoted) state",
    "DOCTYPE public identifier (single-quoted) state",
    "After DOCTYPE public identifier state",
    "Between DOCTYPE public and system identifiers state",
    "After DOCTYPE system keyword state",
    "Before DOCTYPE system identifier state",
    "DOCTYPE system identifier (double-quoted) state",
    "DOCTYPE system identifier (single-quoted) state",
    "After DOCTYPE system identifier state",
    "Bogus DOCTYPE state",
    "CDATA section state",
    "CDATA section bracket state",
    "CDATA section end state",
    "Processing instruction open state",
    "Processing instruction target state",
    "After processing instruction target state",
    "Processing instruction data state",
    "Processing instruction questionable state",
    "Character reference state",
    "Named character reference state",
    "Ambiguous ampersand state",
    "Numeric character reference state",
    "Hexadecimal character reference start state",
    "Hexadecimal character reference state",
    "Decimal character reference state",
    "Numeric character reference end state",
};

comptime {
    std.debug.assert(titles.len == std.enums.values(State).len);
}

/// Returns the section number of `state`, from 1 to 84.
pub fn section(state: State) u8 {
    return @as(u8, @backingInt(state)) + 1;
}

/// Returns the exact heading of `state`'s section.
pub fn title(state: State) []const u8 {
    return titles[@backingInt(state)];
}

/// Whether the tokenizer implements `state`: sections 1, 6 to 8, 32 to 68, and 72 to 84.
pub fn implemented(state: State) bool {
    return switch (section(state)) {
        1, 6...8, 32...68, 72...84 => true,
        else => false,
    };
}

/// Returns the task that owns an unimplemented state, or null for an implemented state.
pub fn owner(state: State) ?[]const u8 {
    return if (implemented(state)) null else "FP-0064";
}

/// Returns the branches of an implemented state, in the order of its section's entries.
/// "whitespace" means U+0009, U+000A, U+000C, or U+0020.
/// An unimplemented state has no branches.
pub fn branches(state: State) []const []const u8 {
    return switch (state) {
        .data => &.{ "&", "<", "NULL", "EOF", "else" },
        .tag_open => &.{ "!", "/", "ASCII alpha", "?", "EOF", "else" },
        .end_tag_open => &.{ "ASCII alpha", ">", "EOF", "else" },
        .tag_name => &.{ "whitespace", "/", ">", "ASCII upper alpha", "NULL", "EOF", "else" },
        .before_attribute_name => &.{ "whitespace", "/ or > or EOF", "=", "else" },
        .attribute_name => &.{ "whitespace or / or > or EOF", "=", "ASCII upper alpha", "NULL", "\" or ' or <", "else" },
        .after_attribute_name => &.{ "whitespace", "/", "=", ">", "EOF", "else" },
        .before_attribute_value => &.{ "whitespace", "\"", "'", ">", "else" },
        .attribute_value_double_quoted => &.{ "\"", "&", "NULL", "EOF", "else" },
        .attribute_value_single_quoted => &.{ "'", "&", "NULL", "EOF", "else" },
        .attribute_value_unquoted => &.{ "whitespace", "&", ">", "NULL", "\" or ' or < or = or `", "EOF", "else" },
        .after_attribute_value_quoted => &.{ "whitespace", "/", ">", "EOF", "else" },
        .self_closing_start_tag => &.{ ">", "EOF", "else" },
        .bogus_comment => &.{ ">", "EOF", "NULL", "else" },
        .markup_declaration_open => &.{
            "two hyphens",
            "DOCTYPE",
            "[CDATA[ with a foreign adjusted current node",
            "[CDATA[ otherwise",
            "else",
        },
        .comment_start => &.{ "-", ">", "else" },
        .comment_start_dash => &.{ "-", ">", "EOF", "else" },
        .comment => &.{ "<", "-", "NULL", "EOF", "else" },
        .comment_less_than_sign => &.{ "!", "<", "else" },
        .comment_less_than_sign_bang => &.{ "-", "else" },
        .comment_less_than_sign_bang_dash => &.{ "-", "else" },
        .comment_less_than_sign_bang_dash_dash => &.{ "> or EOF", "else" },
        .comment_end_dash => &.{ "-", "EOF", "else" },
        .comment_end => &.{ ">", "!", "-", "EOF", "else" },
        .comment_end_bang => &.{ "-", ">", "EOF", "else" },
        .doctype => &.{ "whitespace", ">", "EOF", "else" },
        .before_doctype_name => &.{ "whitespace", "ASCII upper alpha", "NULL", ">", "EOF", "else" },
        .doctype_name => &.{ "whitespace", ">", "ASCII upper alpha", "NULL", "EOF", "else" },
        .after_doctype_name => &.{ "whitespace", ">", "EOF", "else with PUBLIC", "else with SYSTEM", "else otherwise" },
        .after_doctype_public_keyword, .after_doctype_system_keyword => &.{ "whitespace", "\"", "'", ">", "EOF", "else" },
        .before_doctype_public_identifier, .before_doctype_system_identifier => &.{ "whitespace", "\"", "'", ">", "EOF", "else" },
        .doctype_public_identifier_double_quoted, .doctype_system_identifier_double_quoted => &.{ "\"", "NULL", ">", "EOF", "else" },
        .doctype_public_identifier_single_quoted, .doctype_system_identifier_single_quoted => &.{ "'", "NULL", ">", "EOF", "else" },
        .after_doctype_public_identifier, .between_doctype_public_and_system_identifiers => &.{ "whitespace", ">", "\"", "'", "EOF", "else" },
        .after_doctype_system_identifier => &.{ "whitespace", ">", "EOF", "else" },
        .bogus_doctype => &.{ ">", "NULL", "EOF", "else" },
        .processing_instruction_open => &.{ "ASCII alpha or _", "EOF", "else" },
        .processing_instruction_target => &.{
            "terminator with a disallowed target",
            "terminator with another target",
            "ASCII alphanumeric, -, or _",
            "EOF",
            "else",
        },
        .after_processing_instruction_target => &.{ "whitespace", "else" },
        .processing_instruction_data => &.{ "?", ">", "EOF", "else" },
        .processing_instruction_questionable => &.{ ">", "EOF", "else" },
        .character_reference => &.{ "ASCII alphanumeric", "#", "else" },
        .named_character_reference => &.{
            "match under the historical attribute rule",
            "match ending with ;",
            "other match without ;",
            "no match",
        },
        .ambiguous_ampersand => &.{ "ASCII alphanumeric in an attribute", "ASCII alphanumeric otherwise", ";", "else" },
        .numeric_character_reference => &.{ "x or X", "ASCII digit", "else" },
        .hexadecimal_character_reference_start => &.{ "ASCII hex digit", "else" },
        .hexadecimal_character_reference => &.{ "ASCII digit", "ASCII upper hex digit", "ASCII lower hex digit", ";", "else" },
        .decimal_character_reference => &.{ "ASCII digit", ";", "else" },
        .numeric_character_reference_end => &.{
            "0x00",
            "above 0x10FFFF",
            "surrogate",
            "noncharacter",
            "control or 0x0D found in the table",
            "control or 0x0D not in the table",
            "no error",
        },
        else => &.{},
    };
}

/// The index of each state's first branch in a flat list of every branch, followed by the total.
const branch_offsets = offsets: {
    @setEvalBranchQuota(10_000);
    var result: [titles.len + 1]usize = undefined;
    var total: usize = 0;
    for (std.enums.values(State), 0..) |state, index| {
        result[index] = total;
        total += branches(state).len;
    }
    result[titles.len] = total;
    break :offsets result;
};

/// The number of branches of all implemented states.
pub const branch_count: usize = branch_offsets[titles.len];

/// Returns the flat index of the branch named `name` of `state`, or a compile error for an unknown name.
pub fn branchIndex(comptime state: State, comptime name: []const u8) usize {
    comptime {
        @setEvalBranchQuota(10_000);
        for (branches(state), 0..) |branch, index| {
            if (std.mem.eql(u8, branch, name)) return branch_offsets[@backingInt(state)] + index;
        }
        @compileError("state " ++ @tagName(state) ++ " has no branch named \"" ++ name ++ "\"");
    }
}

/// Returns the state and branch name of a flat branch index.
pub fn branchAt(index: usize) struct { state: State, name: []const u8 } {
    for (std.enums.values(State), 0..) |state, position| {
        if (index < branch_offsets[position + 1]) return .{ .state = state, .name = branches(state)[index - branch_offsets[position]] };
    }
    unreachable;
}
