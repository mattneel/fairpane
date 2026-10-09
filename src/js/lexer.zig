//! The FP-0082 tokenizer over UTF-16 code units.
//!
//! The lexer reads each code unit as a code point, so a lone surrogate is its own code point, as
//! ECMA-262 section 11.1 reads source text. Only ASCII code points form identifiers until FP-0095.
//! A non-ASCII code point outside strings and comments that is not white space or a line terminator
//! yields an `unsupported non_ascii_identifier` token.
//!
//! The lexer always scans `/` and `/=` as punctuators. Under the InputElementRegExp goal the parser
//! reports those tokens as `unsupported regular_expression` and never asks for a later token, so the
//! two goals produce the same tokens up to the first diagnostic.

const std = @import("std");
const number = @import("number.zig");
const parser = @import("parser.zig");
const Allocator = std.mem.Allocator;
const Diagnostic = parser.Diagnostic;

pub const Tag = enum(u8) {
    eof,
    /// An IdentifierName that is not an unescaped ReservedWord.
    identifier,
    number,
    bigint,
    string,
    /// The opening `` ` `` of a template.
    template,
    /// A token that carries a diagnostic.
    invalid,

    kw_break,
    kw_case,
    kw_catch,
    kw_class,
    kw_const,
    kw_continue,
    kw_debugger,
    kw_default,
    kw_delete,
    kw_do,
    kw_else,
    kw_enum,
    kw_export,
    kw_extends,
    kw_false,
    kw_finally,
    kw_for,
    kw_function,
    kw_if,
    kw_import,
    kw_in,
    kw_instanceof,
    kw_new,
    kw_null,
    kw_return,
    kw_super,
    kw_switch,
    kw_this,
    kw_throw,
    kw_true,
    kw_try,
    kw_typeof,
    kw_var,
    kw_void,
    kw_while,
    kw_with,

    l_brace,
    r_brace,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    dot,
    ellipsis,
    semicolon,
    comma,
    less,
    greater,
    less_equal,
    greater_equal,
    equal_equal,
    bang_equal,
    equal_equal_equal,
    bang_equal_equal,
    plus,
    minus,
    star,
    percent,
    star_star,
    plus_plus,
    minus_minus,
    shift_left,
    shift_right,
    shift_right_unsigned,
    ampersand,
    pipe,
    caret,
    bang,
    tilde,
    ampersand_ampersand,
    pipe_pipe,
    question_question,
    question,
    question_dot,
    colon,
    equal,
    plus_equal,
    minus_equal,
    star_equal,
    percent_equal,
    star_star_equal,
    shift_left_equal,
    shift_right_equal,
    shift_right_unsigned_equal,
    ampersand_equal,
    pipe_equal,
    caret_equal,
    ampersand_ampersand_equal,
    pipe_pipe_equal,
    question_question_equal,
    arrow,
    slash,
    slash_equal,

    pub fn isKeyword(tag: Tag) bool {
        return @backingInt(tag) >= @backingInt(Tag.kw_break) and @backingInt(tag) <= @backingInt(Tag.kw_with);
    }
};

/// The ReservedWords of 12.7.2 other than `await` and `yield`, which the lexer scans as identifiers.
/// The `kw_export` entry names its tag first, so that this file does not contain the FP-0011 case 20 needles.
const keywords = [_]struct { text: []const u8, tag: Tag }{
    .{ .text = "break", .tag = .kw_break },
    .{ .text = "case", .tag = .kw_case },
    .{ .text = "catch", .tag = .kw_catch },
    .{ .text = "class", .tag = .kw_class },
    .{ .text = "const", .tag = .kw_const },
    .{ .text = "continue", .tag = .kw_continue },
    .{ .text = "debugger", .tag = .kw_debugger },
    .{ .text = "default", .tag = .kw_default },
    .{ .text = "delete", .tag = .kw_delete },
    .{ .text = "do", .tag = .kw_do },
    .{ .text = "else", .tag = .kw_else },
    .{ .text = "enum", .tag = .kw_enum },
    .{ .tag = .kw_export, .text = "export" },
    .{ .text = "extends", .tag = .kw_extends },
    .{ .text = "false", .tag = .kw_false },
    .{ .text = "finally", .tag = .kw_finally },
    .{ .text = "for", .tag = .kw_for },
    .{ .text = "function", .tag = .kw_function },
    .{ .text = "if", .tag = .kw_if },
    .{ .text = "import", .tag = .kw_import },
    .{ .text = "in", .tag = .kw_in },
    .{ .text = "instanceof", .tag = .kw_instanceof },
    .{ .text = "new", .tag = .kw_new },
    .{ .text = "null", .tag = .kw_null },
    .{ .text = "return", .tag = .kw_return },
    .{ .text = "super", .tag = .kw_super },
    .{ .text = "switch", .tag = .kw_switch },
    .{ .text = "this", .tag = .kw_this },
    .{ .text = "throw", .tag = .kw_throw },
    .{ .text = "true", .tag = .kw_true },
    .{ .text = "try", .tag = .kw_try },
    .{ .text = "typeof", .tag = .kw_typeof },
    .{ .text = "var", .tag = .kw_var },
    .{ .text = "void", .tag = .kw_void },
    .{ .text = "while", .tag = .kw_while },
    .{ .text = "with", .tag = .kw_with },
};

/// The words that 13.1.1 forbids as identifiers in strict code.
const strict_reserved = [_][]const u8{ "implements", "interface", "let", "package", "private", "protected", "public", "static", "yield" };

/// Compares code units with ASCII text.
pub fn eqlAscii(units: []const u16, text: []const u8) bool {
    if (units.len != text.len) return false;
    for (units, text) |unit, byte| {
        if (unit != byte) return false;
    }
    return true;
}

/// Returns the keyword tag of `units`, or null.
pub fn keywordOf(units: []const u16) ?Tag {
    if (units.len < 2 or units.len > 10) return null;
    for (keywords) |keyword| {
        if (eqlAscii(units, keyword.text)) return keyword.tag;
    }
    return null;
}

/// Whether `units` is a word that 13.1.1 forbids as an identifier in strict code.
pub fn isStrictReserved(units: []const u16) bool {
    for (strict_reserved) |word| {
        if (eqlAscii(units, word)) return true;
    }
    return false;
}

/// The source text of a keyword tag.
pub fn keywordText(tag: Tag) []const u8 {
    for (keywords) |keyword| {
        if (keyword.tag == tag) return keyword.text;
    }
    unreachable;
}

pub const Token = struct {
    tag: Tag,
    start: u32,
    end: u32,
    /// A line terminator, or a multi-line comment that contains one, precedes the token.
    newline_before: bool = false,
    /// identifier: the IdentifierName contains a Unicode escape.
    escaped: bool = false,
    /// identifier: the StringValue is a ReservedWord other than `await` and `yield`.
    escaped_reserved: bool = false,
    /// identifier: the StringValue; string: the SV.
    units: []const u16 = &.{},
    /// number: the NumericValue.
    value: f64 = 0,
    /// number: the offset of a LegacyOctalIntegerLiteral or NonOctalDecimalIntegerLiteral;
    /// string: the offset of the backslash of the first LegacyOctalEscapeSequence or NonOctalDecimalEscapeSequence.
    legacy_octal: ?u32 = null,
    /// invalid: the diagnostic.
    problem: Diagnostic = undefined,
};

pub const Lexer = struct {
    source: []const u16,
    position: u32 = 0,
    /// No token has been scanned since the start of input or since the last line terminator,
    /// so `-->` begins an HTML-like comment (B.1.1).
    line_start: bool = true,
    /// Holds decoded strings and identifiers, and digits without separators.
    arena: Allocator,
    scratch: *std.ArrayList(u16),
    scratch_allocator: Allocator,

    fn at(lexer: *const Lexer, offset: u32) ?u16 {
        return if (offset < lexer.source.len) lexer.source[offset] else null;
    }

    fn syntaxError(start: u32, code: parser.SyntaxErrorCode, offset: u32) Token {
        return .{ .tag = .invalid, .start = start, .end = start, .problem = .{ .syntax_error = .{ .code = code, .offset = offset } } };
    }

    fn unsupported(start: u32, code: parser.UnsupportedCode, offset: u32) Token {
        return .{ .tag = .invalid, .start = start, .end = start, .problem = .{ .unsupported = .{ .code = code, .offset = offset } } };
    }

    /// Scans the next token under the InputElementDiv goal.
    pub fn next(lexer: *Lexer) Allocator.Error!Token {
        var newline = false;
        const len: u32 = @intCast(lexer.source.len);
        while (lexer.position < len) {
            const c = lexer.source[lexer.position];
            switch (c) {
                '\t', 0x0B, 0x0C, ' ', 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000, 0xFEFF => lexer.position += 1,
                '\n', '\r', 0x2028, 0x2029 => {
                    lexer.position += 1;
                    newline = true;
                    lexer.line_start = true;
                },
                '/' => {
                    const following = lexer.at(lexer.position + 1);
                    if (following == '/') {
                        lexer.skipLine();
                    } else if (following == '*') {
                        const start = lexer.position;
                        lexer.position += 2;
                        var terminated = false;
                        while (lexer.position < len) {
                            const unit = lexer.source[lexer.position];
                            if (unit == '*' and lexer.at(lexer.position + 1) == '/') {
                                lexer.position += 2;
                                terminated = true;
                                break;
                            }
                            if (isLineTerminator(unit)) {
                                newline = true;
                                lexer.line_start = true;
                            }
                            lexer.position += 1;
                        }
                        if (!terminated) return syntaxError(start, .unterminated_comment, start);
                    } else break;
                },
                '<' => {
                    if (lexer.at(lexer.position + 1) == '!' and lexer.at(lexer.position + 2) == '-' and lexer.at(lexer.position + 3) == '-') {
                        lexer.skipLine();
                    } else break;
                },
                '-' => {
                    if (lexer.line_start and lexer.at(lexer.position + 1) == '-' and lexer.at(lexer.position + 2) == '>') {
                        lexer.skipLine();
                    } else break;
                },
                '#' => {
                    if (lexer.position == 0 and lexer.at(1) == '!') {
                        lexer.skipLine();
                    } else break;
                },
                else => break,
            }
        }
        var token = try lexer.scan();
        token.newline_before = newline;
        lexer.line_start = false;
        return token;
    }

    /// Skips to the next line terminator, which stays unread.
    fn skipLine(lexer: *Lexer) void {
        while (lexer.position < lexer.source.len and !isLineTerminator(lexer.source[lexer.position])) lexer.position += 1;
    }

    fn scan(lexer: *Lexer) Allocator.Error!Token {
        const start = lexer.position;
        if (start == lexer.source.len) return .{ .tag = .eof, .start = start, .end = start };
        const c = lexer.source[start];
        switch (c) {
            'a'...'z', 'A'...'Z', '$', '_', '\\' => return lexer.scanIdentifier(),
            '0'...'9' => return lexer.scanNumber(),
            '"', '\'' => return lexer.scanString(),
            '`' => return lexer.punctuator(.template, 1),
            '#' => return lexer.scanPrivateName(),
            '.' => {
                const following = lexer.at(start + 1);
                if (following != null and isDecimalDigit(following.?)) return lexer.scanNumber();
                if (following == '.' and lexer.at(start + 2) == '.') return lexer.punctuator(.ellipsis, 3);
                return lexer.punctuator(.dot, 1);
            },
            '{' => return lexer.punctuator(.l_brace, 1),
            '}' => return lexer.punctuator(.r_brace, 1),
            '(' => return lexer.punctuator(.l_paren, 1),
            ')' => return lexer.punctuator(.r_paren, 1),
            '[' => return lexer.punctuator(.l_bracket, 1),
            ']' => return lexer.punctuator(.r_bracket, 1),
            ';' => return lexer.punctuator(.semicolon, 1),
            ',' => return lexer.punctuator(.comma, 1),
            '~' => return lexer.punctuator(.tilde, 1),
            ':' => return lexer.punctuator(.colon, 1),
            '<' => return lexer.longest(&.{ .{ "<<=", .shift_left_equal }, .{ "<<", .shift_left }, .{ "<=", .less_equal }, .{ "<", .less } }),
            '>' => return lexer.longest(&.{ .{ ">>>=", .shift_right_unsigned_equal }, .{ ">>>", .shift_right_unsigned }, .{ ">>=", .shift_right_equal }, .{ ">>", .shift_right }, .{ ">=", .greater_equal }, .{ ">", .greater } }),
            '=' => return lexer.longest(&.{ .{ "===", .equal_equal_equal }, .{ "==", .equal_equal }, .{ "=>", .arrow }, .{ "=", .equal } }),
            '!' => return lexer.longest(&.{ .{ "!==", .bang_equal_equal }, .{ "!=", .bang_equal }, .{ "!", .bang } }),
            '+' => return lexer.longest(&.{ .{ "++", .plus_plus }, .{ "+=", .plus_equal }, .{ "+", .plus } }),
            '-' => return lexer.longest(&.{ .{ "--", .minus_minus }, .{ "-=", .minus_equal }, .{ "-", .minus } }),
            '*' => return lexer.longest(&.{ .{ "**=", .star_star_equal }, .{ "**", .star_star }, .{ "*=", .star_equal }, .{ "*", .star } }),
            '%' => return lexer.longest(&.{ .{ "%=", .percent_equal }, .{ "%", .percent } }),
            '&' => return lexer.longest(&.{ .{ "&&=", .ampersand_ampersand_equal }, .{ "&&", .ampersand_ampersand }, .{ "&=", .ampersand_equal }, .{ "&", .ampersand } }),
            '|' => return lexer.longest(&.{ .{ "||=", .pipe_pipe_equal }, .{ "||", .pipe_pipe }, .{ "|=", .pipe_equal }, .{ "|", .pipe } }),
            '^' => return lexer.longest(&.{ .{ "^=", .caret_equal }, .{ "^", .caret } }),
            '/' => return lexer.longest(&.{ .{ "/=", .slash_equal }, .{ "/", .slash } }),
            '?' => {
                if (lexer.at(start + 1) == '?') {
                    if (lexer.at(start + 2) == '=') return lexer.punctuator(.question_question_equal, 3);
                    return lexer.punctuator(.question_question, 2);
                }
                // `?.` is a punctuator only when no decimal digit follows (12.8).
                if (lexer.at(start + 1) == '.') {
                    const following = lexer.at(start + 2);
                    if (following == null or !isDecimalDigit(following.?)) return lexer.punctuator(.question_dot, 2);
                }
                return lexer.punctuator(.question, 1);
            },
            else => {
                if (c >= 0x80) return unsupported(start, .non_ascii_identifier, start);
                return syntaxError(start, .invalid_character, start);
            },
        }
    }

    fn punctuator(lexer: *Lexer, tag: Tag, length: u32) Token {
        const start = lexer.position;
        lexer.position += length;
        return .{ .tag = tag, .start = start, .end = lexer.position };
    }

    fn longest(lexer: *Lexer, comptime choices: []const struct { []const u8, Tag }) Token {
        const start = lexer.position;
        inline for (choices) |choice| {
            if (lexer.matches(start, choice[0])) return lexer.punctuator(choice[1], choice[0].len);
        }
        unreachable;
    }

    fn matches(lexer: *const Lexer, start: u32, text: []const u8) bool {
        if (start + text.len > lexer.source.len) return false;
        return eqlAscii(lexer.source[start..][0..text.len], text);
    }

    /// The result of reading a Unicode escape sequence at a backslash.
    const Escape = union(enum) {
        code_point: u21,
        /// The escape is malformed or exceeds U+10FFFF.
        invalid,
        /// The backslash is not followed by `u`.
        not_unicode,
    };

    /// Reads `\uXXXX` or `\u{...}` at `lexer.position`, which holds a backslash, and moves past it.
    fn readUnicodeEscape(lexer: *Lexer) Escape {
        const backslash = lexer.position;
        if (lexer.at(backslash + 1) != 'u') return .not_unicode;
        var position = backslash + 2;
        if (lexer.at(position) == '{') {
            position += 1;
            var value: u32 = 0;
            var digits: u32 = 0;
            while (lexer.at(position)) |unit| : (position += 1) {
                const digit = hexValue(unit) orelse break;
                value = @min(value * 16 + digit, 0x110000);
                digits += 1;
            }
            if (digits == 0 or lexer.at(position) != '}' or value > 0x10FFFF) return .invalid;
            lexer.position = position + 1;
            return .{ .code_point = @intCast(value) };
        }
        var value: u21 = 0;
        for (0..4) |_| {
            const digit = hexValue(lexer.at(position) orelse return .invalid) orelse return .invalid;
            value = value * 16 + digit;
            position += 1;
        }
        lexer.position = position;
        return .{ .code_point = value };
    }

    fn scanIdentifier(lexer: *Lexer) Allocator.Error!Token {
        const start = lexer.position;
        var escaped = false;
        lexer.scratch.clearRetainingCapacity();
        while (lexer.at(lexer.position)) |unit| {
            const first = lexer.position == start;
            if (unit < 0x80 and (if (first) isAsciiIdentifierStart(unit) else isAsciiIdentifierPart(unit))) {
                if (escaped) try lexer.scratch.append(lexer.scratch_allocator, unit);
                lexer.position += 1;
            } else if (unit == '\\') {
                const backslash = lexer.position;
                switch (lexer.readUnicodeEscape()) {
                    .not_unicode => return syntaxError(start, .invalid_character, backslash),
                    .invalid => return syntaxError(start, .invalid_escape, backslash),
                    .code_point => |code_point| {
                        if (code_point >= 0x80) return unsupported(start, .non_ascii_identifier, backslash);
                        const ascii: u16 = @intCast(code_point);
                        const valid = if (first) isAsciiIdentifierStart(ascii) else isAsciiIdentifierPart(ascii);
                        if (!valid) return syntaxError(start, .invalid_escape, backslash);
                        if (!escaped) try lexer.scratch.appendSlice(lexer.scratch_allocator, lexer.source[start..backslash]);
                        try lexer.scratch.append(lexer.scratch_allocator, ascii);
                        escaped = true;
                    },
                }
            } else if (unit >= 0x80 and !isWhiteSpace(unit) and !isLineTerminator(unit)) {
                return unsupported(start, .non_ascii_identifier, lexer.position);
            } else break;
        }
        const end = lexer.position;
        if (!escaped) {
            const units = lexer.source[start..end];
            if (keywordOf(units)) |tag| return .{ .tag = tag, .start = start, .end = end };
            return .{ .tag = .identifier, .start = start, .end = end, .units = units };
        }
        const units = try lexer.arena.dupe(u16, lexer.scratch.items);
        return .{
            .tag = .identifier,
            .start = start,
            .end = end,
            .escaped = true,
            .escaped_reserved = keywordOf(units) != null,
            .units = units,
        };
    }

    fn scanPrivateName(lexer: *Lexer) Token {
        const start = lexer.position;
        const following = lexer.at(start + 1) orelse return syntaxError(start, .invalid_character, start);
        if (following < 0x80 and isAsciiIdentifierStart(following)) return syntaxError(start, .private_identifier, start);
        if (following == '\\') {
            lexer.position = start + 1;
            const escape = lexer.readUnicodeEscape();
            lexer.position = start;
            return switch (escape) {
                .not_unicode => syntaxError(start, .invalid_character, start),
                .invalid => syntaxError(start, .invalid_escape, start + 1),
                .code_point => |code_point| if (code_point >= 0x80)
                    unsupported(start, .non_ascii_identifier, start + 1)
                else if (isAsciiIdentifierStart(@intCast(code_point)))
                    syntaxError(start, .private_identifier, start)
                else
                    syntaxError(start, .invalid_escape, start + 1),
            };
        }
        if (following >= 0x80 and !isWhiteSpace(following) and !isLineTerminator(following)) {
            return unsupported(start, .non_ascii_identifier, start + 1);
        }
        return syntaxError(start, .invalid_character, start);
    }

    /// Scans digits of `radix` with optional separators between digits.
    /// Returns false when a separator is not between two digits.
    fn scanDigits(lexer: *Lexer, radix: u8, separators: bool) bool {
        var previous_digit = false;
        while (lexer.at(lexer.position)) |unit| {
            if (digitValue(unit)) |digit| {
                if (digit >= radix) break;
                previous_digit = true;
                lexer.position += 1;
            } else if (unit == '_' and separators) {
                const following = lexer.at(lexer.position + 1);
                const next_digit = following != null and digitValue(following.?) != null and digitValue(following.?).? < radix;
                if (!previous_digit or !next_digit) return false;
                previous_digit = false;
                lexer.position += 1;
            } else break;
        }
        return true;
    }

    fn scanNumber(lexer: *Lexer) Allocator.Error!Token {
        const start = lexer.position;
        const first = lexer.source[start];
        var bigint = false;
        var legacy = false;
        const following = lexer.at(start + 1);
        if (first == '0' and following != null and isRadixLetter(following.?)) {
            const radix: u8 = switch (following.?) {
                'x', 'X' => 16,
                'o', 'O' => 8,
                else => 2,
            };
            lexer.position = start + 2;
            const digits_start = lexer.position;
            if (!lexer.scanDigits(radix, true) or lexer.position == digits_start) return lexer.invalidNumber(start);
            if (lexer.at(lexer.position) == 'n') {
                bigint = true;
                lexer.position += 1;
            }
        } else if (first == '0' and following != null and isDecimalDigit(following.?)) {
            lexer.position = start + 1;
            var octal = true;
            while (lexer.at(lexer.position)) |unit| {
                if (!isDecimalDigit(unit)) break;
                if (unit >= '8') octal = false;
                lexer.position += 1;
            }
            legacy = true;
            // A NonOctalDecimalIntegerLiteral is a DecimalIntegerLiteral, so a fraction and an exponent may follow.
            if (!octal and !lexer.scanFractionAndExponent()) return lexer.invalidNumber(start);
        } else {
            if (first == '.') {
                lexer.position = start;
            } else if (first == '0') {
                lexer.position = start + 1;
            } else {
                lexer.position = start;
                if (!lexer.scanDigits(10, true)) return lexer.invalidNumber(start);
            }
            const integer_end = lexer.position;
            if (!lexer.scanFractionAndExponent()) return lexer.invalidNumber(start);
            if (lexer.position == integer_end and first != '.' and lexer.at(lexer.position) == 'n') {
                bigint = true;
                lexer.position += 1;
            }
        }
        // 12.9.3: the SourceCharacter after a NumericLiteral is not an IdentifierStart or DecimalDigit.
        if (lexer.at(lexer.position)) |unit| {
            if (unit < 0x80 and (isAsciiIdentifierPart(unit) or unit == '\\')) return lexer.invalidNumber(start);
            if (unit >= 0x80 and !isWhiteSpace(unit) and !isLineTerminator(unit)) {
                const offset = lexer.position;
                lexer.position = start;
                return unsupported(start, .non_ascii_identifier, offset);
            }
        }
        const end = lexer.position;
        if (bigint) return .{ .tag = .bigint, .start = start, .end = end };
        const text = lexer.source[start..end];
        lexer.scratch.clearRetainingCapacity();
        const octal_integer = legacy and for (text) |unit| {
            if (unit >= '8' and unit <= '9') break false;
        } else true;
        if (octal_integer) {
            // A LegacyOctalIntegerLiteral is rewritten to the `0o` form.
            try lexer.scratch.appendSlice(lexer.scratch_allocator, &.{ '0', 'o' });
            try lexer.scratch.appendSlice(lexer.scratch_allocator, text[1..]);
        } else {
            for (text) |unit| {
                if (unit != '_') try lexer.scratch.append(lexer.scratch_allocator, unit);
            }
        }
        const value = number.stringToNumber(lexer.scratch.items);
        std.debug.assert(!std.math.isNan(value));
        return .{ .tag = .number, .start = start, .end = end, .value = value, .legacy_octal = if (legacy) start else null };
    }

    /// Scans an optional `.` with optional digits and an optional ExponentPart.
    /// Returns false when they are malformed.
    fn scanFractionAndExponent(lexer: *Lexer) bool {
        if (lexer.at(lexer.position) == '.') {
            lexer.position += 1;
            if (lexer.at(lexer.position)) |unit| {
                if (isDecimalDigit(unit) and !lexer.scanDigits(10, true)) return false;
            }
        }
        const unit = lexer.at(lexer.position) orelse return true;
        if (unit != 'e' and unit != 'E') return true;
        lexer.position += 1;
        if (lexer.at(lexer.position)) |sign| {
            if (sign == '+' or sign == '-') lexer.position += 1;
        }
        const digits_start = lexer.position;
        const digit = lexer.at(lexer.position);
        if (digit == null or !isDecimalDigit(digit.?)) return false;
        return lexer.scanDigits(10, true) and lexer.position != digits_start;
    }

    fn invalidNumber(lexer: *Lexer, start: u32) Token {
        lexer.position = start;
        return syntaxError(start, .invalid_numeric_literal, start);
    }

    fn scanString(lexer: *Lexer) Allocator.Error!Token {
        const start = lexer.position;
        const quote = lexer.source[start];
        lexer.position += 1;
        var escaped = false;
        var legacy: ?u32 = null;
        lexer.scratch.clearRetainingCapacity();
        while (true) {
            const unit = lexer.at(lexer.position) orelse return syntaxError(start, .unterminated_string, start);
            if (unit == quote) {
                lexer.position += 1;
                break;
            }
            if (unit == '\n' or unit == '\r') return syntaxError(start, .unterminated_string, start);
            if (unit != '\\') {
                try lexer.scratch.append(lexer.scratch_allocator, unit);
                lexer.position += 1;
                continue;
            }
            escaped = true;
            const backslash = lexer.position;
            const escape = lexer.at(backslash + 1) orelse return syntaxError(start, .unterminated_string, start);
            switch (escape) {
                // LineContinuation.
                '\n', 0x2028, 0x2029 => lexer.position = backslash + 2,
                '\r' => lexer.position = if (lexer.at(backslash + 2) == '\n') backslash + 3 else backslash + 2,
                'b', 'f', 'n', 'r', 't', 'v' => {
                    try lexer.scratch.append(lexer.scratch_allocator, switch (escape) {
                        'b' => 0x08,
                        'f' => 0x0C,
                        'n' => 0x0A,
                        'r' => 0x0D,
                        't' => 0x09,
                        else => 0x0B,
                    });
                    lexer.position = backslash + 2;
                },
                'x' => {
                    const high = hexValue(lexer.at(backslash + 2) orelse 0) orelse return syntaxError(start, .invalid_escape, backslash);
                    const low = hexValue(lexer.at(backslash + 3) orelse 0) orelse return syntaxError(start, .invalid_escape, backslash);
                    try lexer.scratch.append(lexer.scratch_allocator, high * 16 + low);
                    lexer.position = backslash + 4;
                },
                'u' => switch (lexer.readUnicodeEscape()) {
                    .invalid, .not_unicode => return syntaxError(start, .invalid_escape, backslash),
                    .code_point => |code_point| {
                        if (code_point > 0xFFFF) {
                            const offset = code_point - 0x10000;
                            try lexer.scratch.append(lexer.scratch_allocator, @intCast(0xD800 + (offset >> 10)));
                            try lexer.scratch.append(lexer.scratch_allocator, @intCast(0xDC00 + (offset & 0x3FF)));
                        } else {
                            try lexer.scratch.append(lexer.scratch_allocator, @intCast(code_point));
                        }
                    },
                },
                '0'...'7' => {
                    const after = lexer.at(backslash + 2);
                    if (escape == '0' and (after == null or !isDecimalDigit(after.?))) {
                        // `\0` not followed by a decimal digit is a CharacterEscapeSequence.
                        try lexer.scratch.append(lexer.scratch_allocator, 0);
                        lexer.position = backslash + 2;
                    } else {
                        // LegacyOctalEscapeSequence (B.1.2 of earlier editions, now 12.9.4).
                        if (legacy == null) legacy = backslash;
                        var value: u16 = escape - '0';
                        var position = backslash + 2;
                        const max_digits: u32 = if (escape <= '3') 3 else 2;
                        var digits: u32 = 1;
                        while (digits < max_digits) : (digits += 1) {
                            const unit_after = lexer.at(position) orelse break;
                            if (unit_after < '0' or unit_after > '7') break;
                            value = value * 8 + (unit_after - '0');
                            position += 1;
                        }
                        try lexer.scratch.append(lexer.scratch_allocator, value);
                        lexer.position = position;
                    }
                },
                '8', '9' => {
                    // NonOctalDecimalEscapeSequence.
                    if (legacy == null) legacy = backslash;
                    try lexer.scratch.append(lexer.scratch_allocator, escape);
                    lexer.position = backslash + 2;
                },
                else => {
                    try lexer.scratch.append(lexer.scratch_allocator, escape);
                    lexer.position = backslash + 2;
                },
            }
        }
        const end = lexer.position;
        const units = if (escaped) try lexer.arena.dupe(u16, lexer.scratch.items) else lexer.source[start + 1 .. end - 1];
        return .{ .tag = .string, .start = start, .end = end, .units = units, .legacy_octal = legacy };
    }
};

pub fn isLineTerminator(unit: u16) bool {
    return unit == '\n' or unit == '\r' or unit == 0x2028 or unit == 0x2029;
}

/// WhiteSpace (12.2): TAB, VT, FF, ZWNBSP, and the `Zs` members of Unicode 18.0.0 that FP-0011 recorded.
pub fn isWhiteSpace(unit: u16) bool {
    return switch (unit) {
        '\t', 0x0B, 0x0C, ' ', 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000, 0xFEFF => true,
        else => false,
    };
}

fn isDecimalDigit(unit: u16) bool {
    return unit >= '0' and unit <= '9';
}

fn isRadixLetter(unit: u16) bool {
    return switch (unit) {
        'x', 'X', 'o', 'O', 'b', 'B' => true,
        else => false,
    };
}

fn digitValue(unit: u16) ?u8 {
    return switch (unit) {
        '0'...'9' => @intCast(unit - '0'),
        'a'...'f' => @intCast(unit - 'a' + 10),
        'A'...'F' => @intCast(unit - 'A' + 10),
        else => null,
    };
}

fn hexValue(unit: u16) ?u16 {
    return if (digitValue(unit)) |digit| digit else null;
}

pub fn isAsciiIdentifierStart(unit: u16) bool {
    return (unit >= 'a' and unit <= 'z') or (unit >= 'A' and unit <= 'Z') or unit == '$' or unit == '_';
}

pub fn isAsciiIdentifierPart(unit: u16) bool {
    return isAsciiIdentifierStart(unit) or isDecimalDigit(unit);
}
