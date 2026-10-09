//! CSS Syntax Module Level 3, sections 3.3 and 4: input filtering and tokenization.
//!
//! The source is the editor's draft at `w3c/csswg-drafts` commit `58354dac99cc8783a9b7b28957ece56bb48579eb`.
//! "Filter code points" converts UTF-16 code units into code points, and every position and source range
//! refers to that filtered sequence as a half-open range of code-point indexes.
//! A comment beside each branch names the algorithm step that it implements.

const std = @import("std");
const web_string = @import("../web_string.zig");
const Allocator = std.mem.Allocator;
const View = web_string.View;

/// A half-open range of indexes into the filtered code points.
pub const Range = struct {
    start: usize,
    end: usize,
};

pub const TokenKind = enum {
    ident,
    function,
    at_keyword,
    hash,
    string,
    bad_string,
    url,
    bad_url,
    delim,
    number,
    percentage,
    dimension,
    unicode_range,
    whitespace,
    cdo,
    cdc,
    colon,
    semicolon,
    comma,
    open_square,
    close_square,
    open_paren,
    close_paren,
    open_curly,
    close_curly,
};

pub const HashType = enum { id, unrestricted };
pub const NumberType = enum { integer, number };
pub const Sign = enum { none, plus, minus };

/// One token with the fields of Syntax section 4.
/// Each field other than `kind` and `range` has meaning only for the kinds that its comment names.
pub const Token = struct {
    kind: TokenKind,
    range: Range,
    /// Ident, function, at-keyword, hash, string, and url tokens: UTF-16 code units of the token's code points.
    value: []const u16 = &.{},
    /// Hash tokens.
    hash_type: HashType = .unrestricted,
    /// Delim tokens.
    delim: u21 = 0,
    /// Number, percentage, and dimension tokens.
    number: f64 = 0,
    /// Number and dimension tokens.
    number_type: NumberType = .integer,
    /// Number, percentage, and dimension tokens.
    sign: Sign = .none,
    /// Dimension tokens.
    unit: []const u16 = &.{},
    /// Unicode-range tokens.
    range_start: u32 = 0,
    /// Unicode-range tokens.
    range_end: u32 = 0,
};

pub const Options = struct {
    unicode_ranges_allowed: bool = false,
};

const replacement_character: u21 = 0xFFFD;
const maximum_allowed_code_point: u21 = 0x10FFFF;
/// The conceptual EOF code point. It lies outside the code point space.
const eof: u21 = 0x1FFFFF;

/// "Filter code points" (section 3.3) over UTF-16 code units.
/// A high surrogate followed by a low surrogate becomes one supplementary code point.
/// Every other surrogate code unit and every U+0000 becomes U+FFFD.
/// CR LF, CR, and FF each become one LF.
/// The caller frees the result with `gpa`.
pub fn filterCodePoints(gpa: Allocator, input: View) Allocator.Error![]u21 {
    var count: usize = 0;
    var iterator = input.codePoints();
    var previous_cr = false;
    while (iterator.next()) |code_point| {
        if (code_point == '\n' and previous_cr) {
            previous_cr = false;
            continue;
        }
        previous_cr = code_point == '\r';
        count += 1;
    }
    const output = try gpa.alloc(u21, count);
    iterator = input.codePoints();
    previous_cr = false;
    var index: usize = 0;
    while (iterator.next()) |code_point| {
        if (code_point == '\n' and previous_cr) {
            previous_cr = false;
            continue;
        }
        previous_cr = code_point == '\r';
        output[index] = switch (code_point) {
            '\r', 0x0C => '\n',
            0, 0xD800...0xDFFF => replacement_character,
            else => code_point,
        };
        index += 1;
    }
    std.debug.assert(index == count);
    return output;
}

/// Tokenizes `input` completely. The caller owns the result and every token string, all allocated with `gpa`.
/// An arena allocator is the intended `gpa`.
pub fn tokenizeAll(gpa: Allocator, input: []const u21, options: Options) Allocator.Error![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(gpa);
    var tokenizer: Tokenizer = .init(input, options);
    while (try tokenizer.next(gpa)) |token| try tokens.append(gpa, token);
    return tokens.toOwnedSlice(gpa);
}

/// "Consume a token" (section 4.3.1) over a filtered code-point sequence.
pub const Tokenizer = struct {
    input: []const u21,
    options: Options,
    /// The index of the next input code point.
    position: usize = 0,

    pub fn init(input: []const u21, options: Options) Tokenizer {
        return .{ .input = input, .options = options };
    }

    /// Returns one token, or null at EOF. Token strings are allocated with `gpa`.
    /// An allocation failure leaves the tokenizer at the start of the token that it was consuming.
    pub fn next(t: *Tokenizer, gpa: Allocator) Allocator.Error!?Token {
        const restart = t.position;
        errdefer t.position = restart;
        // Consume comments.
        t.consumeComments();
        const start = t.position;
        // Consume the next input code point.
        const c = t.consume();
        var token: Token = switch (c) {
            eof => return null,
            '\n', '\t', ' ' => blk: {
                // Consume as much whitespace as possible. Return a <whitespace-token>.
                while (isWhitespace(t.peek(0))) t.position += 1;
                break :blk .{ .kind = .whitespace, .range = undefined };
            },
            '"', '\'' => try t.consumeString(gpa, c),
            '#' => blk: {
                // If the next input code point is an ident code point or the next two input code points are a valid escape:
                if (isIdentCodePoint(t.peek(0)) or isValidEscape(t.peek(0), t.peek(1))) {
                    // If the next 3 input code points would start an ident sequence, set the type flag to "id".
                    const hash_type: HashType = if (wouldStartIdent(t.peek(0), t.peek(1), t.peek(2))) .id else .unrestricted;
                    // Consume an ident sequence, and set the <hash-token>'s value to the returned string.
                    const value = try t.consumeIdentSequence(gpa);
                    break :blk .{ .kind = .hash, .range = undefined, .value = value, .hash_type = hash_type };
                }
                break :blk delim(c);
            },
            '(' => .{ .kind = .open_paren, .range = undefined },
            ')' => .{ .kind = .close_paren, .range = undefined },
            '+', '.' => blk: {
                // If the input stream starts with a number, reconsume the current input code point and consume a numeric token.
                if (wouldStartNumber(c, t.peek(0), t.peek(1))) {
                    t.position -= 1;
                    break :blk try t.consumeNumeric(gpa);
                }
                break :blk delim(c);
            },
            ',' => .{ .kind = .comma, .range = undefined },
            '-' => blk: {
                if (wouldStartNumber(c, t.peek(0), t.peek(1))) {
                    t.position -= 1;
                    break :blk try t.consumeNumeric(gpa);
                }
                // If the next 2 input code points are "->", consume them and return a <CDC-token>.
                if (t.peek(0) == '-' and t.peek(1) == '>') {
                    t.position += 2;
                    break :blk .{ .kind = .cdc, .range = undefined };
                }
                // If the input stream starts with an ident sequence, reconsume and consume an ident-like token.
                if (wouldStartIdent(c, t.peek(0), t.peek(1))) {
                    t.position -= 1;
                    break :blk try t.consumeIdentLike(gpa);
                }
                break :blk delim(c);
            },
            ':' => .{ .kind = .colon, .range = undefined },
            ';' => .{ .kind = .semicolon, .range = undefined },
            '<' => blk: {
                // If the next 3 input code points are "!--", consume them and return a <CDO-token>.
                if (t.peek(0) == '!' and t.peek(1) == '-' and t.peek(2) == '-') {
                    t.position += 3;
                    break :blk .{ .kind = .cdo, .range = undefined };
                }
                break :blk delim(c);
            },
            '@' => blk: {
                // If the next 3 input code points would start an ident sequence, return an <at-keyword-token>.
                if (wouldStartIdent(t.peek(0), t.peek(1), t.peek(2))) {
                    const value = try t.consumeIdentSequence(gpa);
                    break :blk .{ .kind = .at_keyword, .range = undefined, .value = value };
                }
                break :blk delim(c);
            },
            '[' => .{ .kind = .open_square, .range = undefined },
            '\\' => blk: {
                // If the input stream starts with a valid escape, reconsume and consume an ident-like token.
                if (isValidEscape(c, t.peek(0))) {
                    t.position -= 1;
                    break :blk try t.consumeIdentLike(gpa);
                }
                // Otherwise, this is a parse error. Return a <delim-token> with the current input code point.
                break :blk delim(c);
            },
            ']' => .{ .kind = .close_square, .range = undefined },
            '{' => .{ .kind = .open_curly, .range = undefined },
            '}' => .{ .kind = .close_curly, .range = undefined },
            '0'...'9' => blk: {
                t.position -= 1;
                break :blk try t.consumeNumeric(gpa);
            },
            'U', 'u' => blk: {
                t.position -= 1;
                // If unicode ranges allowed is true and the input stream would start a unicode-range,
                // consume a unicode-range token.
                if (t.options.unicode_ranges_allowed and wouldStartUnicodeRange(c, t.peek(1), t.peek(2))) {
                    break :blk t.consumeUnicodeRange();
                }
                break :blk try t.consumeIdentLike(gpa);
            },
            else => blk: {
                if (isIdentStart(c)) {
                    t.position -= 1;
                    break :blk try t.consumeIdentLike(gpa);
                }
                break :blk delim(c);
            },
        };
        token.range = .{ .start = start, .end = t.position };
        return token;
    }

    /// Returns the code point `offset` positions after the next input code point, or EOF.
    fn peek(t: *const Tokenizer, offset: usize) u21 {
        const index = t.position + offset;
        return if (index < t.input.len) t.input[index] else eof;
    }

    /// Consumes and returns the next input code point. At EOF it returns EOF and consumes nothing.
    fn consume(t: *Tokenizer) u21 {
        if (t.position == t.input.len) return eof;
        defer t.position += 1;
        return t.input[t.position];
    }

    /// "Consume comments" (4.3.2).
    fn consumeComments(t: *Tokenizer) void {
        while (t.peek(0) == '/' and t.peek(1) == '*') {
            t.position += 2;
            while (true) {
                if (t.position == t.input.len) return;
                if (t.peek(0) == '*' and t.peek(1) == '/') {
                    t.position += 2;
                    break;
                }
                t.position += 1;
            }
        }
    }

    /// "Consume a numeric token" (4.3.3).
    fn consumeNumeric(t: *Tokenizer, gpa: Allocator) Allocator.Error!Token {
        const number = try t.consumeNumber(gpa);
        // If the next 3 input code points would start an ident sequence, create a <dimension-token>.
        if (wouldStartIdent(t.peek(0), t.peek(1), t.peek(2))) {
            const unit = try t.consumeIdentSequence(gpa);
            return .{
                .kind = .dimension,
                .range = undefined,
                .number = number.value,
                .number_type = number.type,
                .sign = number.sign,
                .unit = unit,
            };
        }
        // If the next input code point is "%", consume it and create a <percentage-token>.
        if (t.peek(0) == '%') {
            t.position += 1;
            return .{ .kind = .percentage, .range = undefined, .number = number.value, .sign = number.sign };
        }
        return .{ .kind = .number, .range = undefined, .number = number.value, .number_type = number.type, .sign = number.sign };
    }

    /// "Consume an ident-like token" (4.3.4).
    fn consumeIdentLike(t: *Tokenizer, gpa: Allocator) Allocator.Error!Token {
        const string = try t.consumeIdentSequence(gpa);
        errdefer gpa.free(string);
        // If string is an ASCII case-insensitive match for "url" and the next input code point is "(", consume it.
        if (asciiCaseInsensitiveEql(string, "url") and t.peek(0) == '(') {
            t.position += 1;
            // While the next two input code points are whitespace, consume the next input code point.
            while (isWhitespace(t.peek(0)) and isWhitespace(t.peek(1))) t.position += 1;
            // If the next one or two input code points are a quotation mark, or whitespace followed by one,
            // create a <function-token>.
            const first = t.peek(0);
            const second = t.peek(1);
            if (isQuote(first) or (isWhitespace(first) and isQuote(second))) {
                return .{ .kind = .function, .range = undefined, .value = string };
            }
            gpa.free(string);
            return t.consumeUrl(gpa);
        }
        // If the next input code point is "(", consume it and create a <function-token>.
        if (t.peek(0) == '(') {
            t.position += 1;
            return .{ .kind = .function, .range = undefined, .value = string };
        }
        return .{ .kind = .ident, .range = undefined, .value = string };
    }

    /// "Consume a string token" (4.3.5) with the ending code point `ending`.
    fn consumeString(t: *Tokenizer, gpa: Allocator, ending: u21) Allocator.Error!Token {
        var value: std.ArrayList(u16) = .empty;
        defer value.deinit(gpa);
        while (true) {
            const c = t.consume();
            if (c == ending) break;
            switch (c) {
                // EOF: this is a parse error. Return the <string-token>.
                eof => break,
                // Newline: this is a parse error. Reconsume the current input code point and return a <bad-string-token>.
                '\n' => {
                    t.position -= 1;
                    return .{ .kind = .bad_string, .range = undefined };
                },
                '\\' => {
                    // If the next input code point is EOF, do nothing.
                    // Otherwise, if the next input code point is a newline, consume it.
                    // Otherwise, consume an escaped code point and append it.
                    switch (t.peek(0)) {
                        eof => {},
                        '\n' => t.position += 1,
                        else => try appendCodePoint(gpa, &value, t.consumeEscape()),
                    }
                },
                else => try appendCodePoint(gpa, &value, c),
            }
        }
        return .{ .kind = .string, .range = undefined, .value = try value.toOwnedSlice(gpa) };
    }

    /// "Consume a url token" (4.3.6). The caller has consumed "url(" and the whitespace pairs before the value.
    fn consumeUrl(t: *Tokenizer, gpa: Allocator) Allocator.Error!Token {
        var value: std.ArrayList(u16) = .empty;
        defer value.deinit(gpa);
        // Consume as much whitespace as possible.
        while (isWhitespace(t.peek(0))) t.position += 1;
        while (true) {
            const c = t.consume();
            switch (c) {
                ')', eof => break,
                '\n', '\t', ' ' => {
                    // Consume as much whitespace as possible. If the next input code point is ")" or EOF,
                    // consume it and return the <url-token>. Otherwise, consume the remnants of a bad url.
                    while (isWhitespace(t.peek(0))) t.position += 1;
                    switch (t.peek(0)) {
                        ')' => {
                            t.position += 1;
                            break;
                        },
                        eof => break,
                        else => {
                            t.consumeBadUrlRemnants();
                            return .{ .kind = .bad_url, .range = undefined };
                        },
                    }
                },
                '"', '\'', '(' => {
                    t.consumeBadUrlRemnants();
                    return .{ .kind = .bad_url, .range = undefined };
                },
                '\\' => {
                    if (isValidEscape(c, t.peek(0))) {
                        try appendCodePoint(gpa, &value, t.consumeEscape());
                    } else {
                        t.consumeBadUrlRemnants();
                        return .{ .kind = .bad_url, .range = undefined };
                    }
                },
                else => {
                    if (isNonPrintable(c)) {
                        t.consumeBadUrlRemnants();
                        return .{ .kind = .bad_url, .range = undefined };
                    }
                    try appendCodePoint(gpa, &value, c);
                },
            }
        }
        return .{ .kind = .url, .range = undefined, .value = try value.toOwnedSlice(gpa) };
    }

    /// "Consume an escaped code point" (4.3.7). The caller has consumed the reverse solidus.
    fn consumeEscape(t: *Tokenizer) u21 {
        const c = t.consume();
        if (isHexDigit(c)) {
            // Consume as many hex digits as possible, but no more than 5 more.
            var value: u32 = hexValue(c);
            var digits: usize = 1;
            while (digits < 6 and isHexDigit(t.peek(0))) : (digits += 1) {
                value = value * 16 + hexValue(t.consume());
            }
            // If the next input code point is whitespace, consume it as well.
            if (isWhitespace(t.peek(0))) t.position += 1;
            // Zero, a surrogate, or a value above the maximum allowed code point is U+FFFD.
            if (value == 0 or (value >= 0xD800 and value <= 0xDFFF) or value > maximum_allowed_code_point) {
                return replacement_character;
            }
            return @intCast(value);
        }
        // EOF: this is a parse error. Return U+FFFD.
        if (c == eof) return replacement_character;
        return c;
    }

    /// "Consume an ident sequence" (4.3.12).
    fn consumeIdentSequence(t: *Tokenizer, gpa: Allocator) Allocator.Error![]const u16 {
        var result: std.ArrayList(u16) = .empty;
        defer result.deinit(gpa);
        while (true) {
            const c = t.peek(0);
            if (isIdentCodePoint(c)) {
                t.position += 1;
                try appendCodePoint(gpa, &result, c);
            } else if (isValidEscape(c, t.peek(1))) {
                t.position += 1;
                try appendCodePoint(gpa, &result, t.consumeEscape());
            } else {
                break;
            }
        }
        return result.toOwnedSlice(gpa);
    }

    const Number = struct { value: f64, type: NumberType, sign: Sign };

    /// "Consume a number" (4.3.13). The value is the `f64` nearest to the exact decimal value of the number text,
    /// and a magnitude past the largest finite `f64` becomes that largest value with the number's sign.
    fn consumeNumber(t: *Tokenizer, gpa: Allocator) Allocator.Error!Number {
        var number_type: NumberType = .integer;
        var sign: Sign = .none;
        const start = t.position;
        errdefer t.position = start;
        // If the next input code point is "+" or "-", consume it and set the sign character to it.
        switch (t.peek(0)) {
            '+' => {
                sign = .plus;
                t.position += 1;
            },
            '-' => {
                sign = .minus;
                t.position += 1;
            },
            else => {},
        }
        // While the next input code point is a digit, consume it.
        while (isDigit(t.peek(0))) t.position += 1;
        // If the next 2 input code points are "." followed by a digit, consume the fraction.
        if (t.peek(0) == '.' and isDigit(t.peek(1))) {
            t.position += 1;
            while (isDigit(t.peek(0))) t.position += 1;
            number_type = .number;
        }
        // If the next 2 or 3 input code points are "E" or "e", optionally followed by a sign, followed by a digit,
        // consume the exponent.
        const e = t.peek(0);
        if (e == 'E' or e == 'e') {
            const after = t.peek(1);
            const signed = after == '+' or after == '-';
            if (isDigit(if (signed) t.peek(2) else after)) {
                t.position += if (signed) 2 else 1;
                while (isDigit(t.peek(0))) t.position += 1;
                number_type = .number;
            }
        }
        return .{ .value = try decimalValue(gpa, t.input[start..t.position]), .type = number_type, .sign = sign };
    }

    /// "Consume a unicode-range token" (4.3.14).
    fn consumeUnicodeRange(t: *Tokenizer) Token {
        // Consume the next two input code points and discard them.
        t.position += 2;
        // Consume as many hex digits as possible, but no more than 6,
        // then question marks up to a total of 6 code points.
        var digits: usize = 0;
        var start_value: u32 = 0;
        var end_value: u32 = 0;
        while (digits < 6 and isHexDigit(t.peek(0))) : (digits += 1) {
            const digit = hexValue(t.consume());
            start_value = start_value * 16 + digit;
            end_value = end_value * 16 + digit;
        }
        var questions: usize = 0;
        while (digits + questions < 6 and t.peek(0) == '?') : (questions += 1) {
            t.position += 1;
            start_value = start_value * 16;
            end_value = end_value * 16 + 0xF;
        }
        // If the first segment contains question marks, replace them with 0 for the start and F for the end.
        if (questions != 0) return unicodeRange(start_value, end_value);
        // If the next 2 input code points are "-" followed by a hex digit, consume the end of the range.
        if (t.peek(0) == '-' and isHexDigit(t.peek(1))) {
            t.position += 1;
            var end_digits: usize = 0;
            end_value = 0;
            while (end_digits < 6 and isHexDigit(t.peek(0))) : (end_digits += 1) {
                end_value = end_value * 16 + hexValue(t.consume());
            }
            return unicodeRange(start_value, end_value);
        }
        return unicodeRange(start_value, start_value);
    }

    /// "Consume the remnants of a bad url" (4.3.15).
    fn consumeBadUrlRemnants(t: *Tokenizer) void {
        while (true) {
            const c = t.consume();
            switch (c) {
                ')', eof => return,
                else => {
                    // The input stream starts with a valid escape: consume an escaped code point.
                    if (isValidEscape(c, t.peek(0))) _ = t.consumeEscape();
                },
            }
        }
    }
};

fn delim(code_point: u21) Token {
    return .{ .kind = .delim, .range = undefined, .delim = code_point };
}

fn unicodeRange(start: u32, end: u32) Token {
    return .{ .kind = .unicode_range, .range = undefined, .range_start = start, .range_end = end };
}

/// The nearest `f64` to the exact decimal value of `text`, which matches the number grammar of 4.3.13.
/// A magnitude past the largest finite `f64` becomes that largest value with the number's sign.
fn decimalValue(gpa: Allocator, text: []const u21) Allocator.Error!f64 {
    // The text is ASCII. `std.fmt.parseFloat` rounds correctly for any digit count and any exponent.
    var buffer: [256]u8 = undefined;
    const bytes = if (text.len <= buffer.len) buffer[0..text.len] else try gpa.alloc(u8, text.len);
    defer if (text.len > buffer.len) gpa.free(bytes);
    for (text, bytes) |code_point, *byte| byte.* = @intCast(code_point);
    const value = std.fmt.parseFloat(f64, bytes) catch unreachable;
    if (std.math.isInf(value)) return std.math.copysign(std.math.floatMax(f64), value);
    return value;
}

fn appendCodePoint(gpa: Allocator, list: *std.ArrayList(u16), code_point: u21) Allocator.Error!void {
    if (code_point < 0x10000) return list.append(gpa, @intCast(code_point));
    const offset = code_point - 0x10000;
    try list.appendSlice(gpa, &.{ @intCast(0xD800 + (offset >> 10)), @intCast(0xDC00 + (offset & 0x3FF)) });
}

pub fn isDigit(c: u21) bool {
    return c >= '0' and c <= '9';
}

pub fn isHexDigit(c: u21) bool {
    return isDigit(c) or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f');
}

fn hexValue(c: u21) u32 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => unreachable,
    };
}

fn isLetter(c: u21) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

/// The non-ASCII ident code points of section 4.2.
fn isNonAsciiIdent(c: u21) bool {
    return switch (c) {
        0x00B7,
        0x00C0...0x00D6,
        0x00D8...0x00F6,
        0x00F8...0x037D,
        0x037F...0x1FFF,
        0x200C,
        0x200D,
        0x203F,
        0x2040,
        0x2070...0x218F,
        0x2C00...0x2FEF,
        0x3001...0xD7FF,
        0xF900...0xFDCF,
        0xFDF0...0xFFFD,
        0x10000...0x10FFFF,
        => true,
        else => false,
    };
}

fn isIdentStart(c: u21) bool {
    return isLetter(c) or isNonAsciiIdent(c) or c == '_';
}

fn isIdentCodePoint(c: u21) bool {
    return isIdentStart(c) or isDigit(c) or c == '-';
}

fn isNonPrintable(c: u21) bool {
    return c <= 0x08 or c == 0x0B or (c >= 0x0E and c <= 0x1F) or c == 0x7F;
}

pub fn isWhitespace(c: u21) bool {
    return c == '\n' or c == '\t' or c == ' ';
}

fn isQuote(c: u21) bool {
    return c == '"' or c == '\'';
}

/// "Check if two code points are a valid escape" (4.3.8).
fn isValidEscape(first: u21, second: u21) bool {
    return first == '\\' and second != '\n';
}

/// "Check if three code points would start an ident sequence" (4.3.9).
fn wouldStartIdent(first: u21, second: u21, third: u21) bool {
    return switch (first) {
        '-' => isIdentStart(second) or second == '-' or isValidEscape(second, third),
        '\\' => isValidEscape(first, second),
        else => isIdentStart(first),
    };
}

/// "Check if three code points would start a number" (4.3.10).
fn wouldStartNumber(first: u21, second: u21, third: u21) bool {
    return switch (first) {
        '+', '-' => isDigit(second) or (second == '.' and isDigit(third)),
        '.' => isDigit(second),
        else => isDigit(first),
    };
}

/// "Check if three code points would start a unicode-range" (4.3.11).
fn wouldStartUnicodeRange(first: u21, second: u21, third: u21) bool {
    return (first == 'U' or first == 'u') and second == '+' and (third == '?' or isHexDigit(third));
}

/// Compares UTF-16 code units with an ASCII literal, ASCII case-insensitively.
pub fn asciiCaseInsensitiveEql(units: []const u16, comptime literal: []const u8) bool {
    if (units.len != literal.len) return false;
    for (units, literal) |unit, byte| {
        if (unit > 0x7F) return false;
        if (std.ascii.toLower(@intCast(unit)) != std.ascii.toLower(byte)) return false;
    }
    return true;
}
