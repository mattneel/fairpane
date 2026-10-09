//! The 52 parse error codes of the table in HTML Standard §13.2.2, at whatwg/html commit
//! `efc54f7b70858d9fcf06d1a5871ae215f448c029`, in table order.

const std = @import("std");

/// One tag per code. Each tag is its code with every hyphen replaced by an underscore.
pub const ErrorCode = enum(u8) {
    abrupt_closing_of_empty_comment,
    abrupt_doctype_public_identifier,
    abrupt_doctype_system_identifier,
    absence_of_digits_in_numeric_character_reference,
    cdata_in_html_content,
    character_reference_outside_unicode_range,
    control_character_in_input_stream,
    control_character_reference,
    disallowed_processing_instruction_target,
    duplicate_attribute,
    end_tag_with_attributes,
    end_tag_with_trailing_solidus,
    eof_before_tag_name,
    eof_in_cdata,
    eof_in_comment,
    eof_in_doctype,
    eof_in_processing_instruction,
    eof_in_script_html_comment_like_text,
    eof_in_tag,
    incorrectly_closed_comment,
    incorrectly_opened_comment,
    invalid_character_sequence_after_doctype_name,
    invalid_first_character_of_processing_instruction_target,
    invalid_first_character_of_tag_name,
    invalid_processing_instruction_target,
    missing_attribute_value,
    missing_doctype_name,
    missing_doctype_public_identifier,
    missing_doctype_system_identifier,
    missing_end_tag_name,
    missing_quote_before_doctype_public_identifier,
    missing_quote_before_doctype_system_identifier,
    missing_semicolon_after_character_reference,
    missing_whitespace_after_doctype_public_keyword,
    missing_whitespace_after_doctype_system_keyword,
    missing_whitespace_before_doctype_name,
    missing_whitespace_between_attributes,
    missing_whitespace_between_doctype_public_and_system_identifiers,
    nested_comment,
    noncharacter_character_reference,
    noncharacter_in_input_stream,
    non_void_html_element_start_tag_with_trailing_solidus,
    null_character_reference,
    surrogate_character_reference,
    surrogate_in_input_stream,
    unexpected_character_after_doctype_system_identifier,
    unexpected_character_in_attribute_name,
    unexpected_character_in_unquoted_attribute_value,
    unexpected_equals_sign_before_attribute_name,
    unexpected_null_character,
    unexpected_solidus_in_tag,
    unknown_named_character_reference,
};

const names = names: {
    @setEvalBranchQuota(10_000);
    const codes = std.enums.values(ErrorCode);
    var result: [codes.len][]const u8 = undefined;
    for (codes, &result) |code, *text| {
        var buffer: [@tagName(code).len]u8 = @tagName(code)[0..].*;
        std.mem.replaceScalar(u8, &buffer, '_', '-');
        const final = buffer;
        text.* = &final;
    }
    break :names result;
};

/// Returns the exact code text of the standard, such as `"eof-in-processing-instruction"`.
pub fn name(code: ErrorCode) []const u8 {
    return names[@backingInt(code)];
}

/// Returns the code whose text is `text`, or null.
pub fn fromName(text: []const u8) ?ErrorCode {
    for (std.enums.values(ErrorCode)) |code| {
        if (std.mem.eql(u8, name(code), text)) return code;
    }
    return null;
}

/// Whether the tokenizer of task FP-0008 raises `code`.
/// It never raises `eof-in-cdata` and `eof-in-script-html-comment-like-text`, which belong to unimplemented states of task FP-0064,
/// or `non-void-html-element-start-tag-with-trailing-solidus`, which tree construction raises in task FP-0010.
pub fn raisedByTokenizer(code: ErrorCode) bool {
    return switch (code) {
        .eof_in_cdata, .eof_in_script_html_comment_like_text, .non_void_html_element_start_tag_with_trailing_solidus => false,
        else => true,
    };
}
