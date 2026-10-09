//! FP-0008 contract cases 1, 2, 4 to 12, and 15 to 17, and the helpers that `partition_test.zig` shares.
//!
//! The case tables repeat the contract's inputs and expected sequences in its notation.
//! Inputs use `\0`, `\t`, `\n`, `\f`, `\r`, and `\uXXXX`; every other character is the ASCII character shown.
//! An expected sequence maps one to one to the dump without spans: `C"x"`, `S"a"[b="c"]`, `E"a"[]/`, `M"x"`, `P("t","d")`,
//! `D(n,p,s,q)`, `EOF`, and `!code@L:C`, which is `["error","code",L,C,C-1]`.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const states = @import("states.zig");
const errors = @import("errors.zig");
const dump = @import("dump.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Tokenizer = tokenizer.Tokenizer;

pub const Case = struct {
    id: []const u8,
    /// The error code that a case 4 row names.
    code: []const u8 = "",
    input: []const u8,
    expected: []const u8,
};

/// Case 4, the error catalog.
pub const catalog = [_]Case{
    .{ .id = "A1", .code = "abrupt-closing-of-empty-comment", .input = "<!-->", .expected = "!abrupt-closing-of-empty-comment@1:5 M\"\" EOF" },
    .{ .id = "A2", .code = "abrupt-doctype-public-identifier", .input = "<!DOCTYPE a PUBLIC \"x>", .expected = "!abrupt-doctype-public-identifier@1:22 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "A3", .code = "abrupt-doctype-system-identifier", .input = "<!DOCTYPE a SYSTEM 'y>", .expected = "!abrupt-doctype-system-identifier@1:22 D(\"a\",-,\"y\",on) EOF" },
    .{ .id = "A4", .code = "absence-of-digits-in-numeric-character-reference", .input = "&#z", .expected = "!absence-of-digits-in-numeric-character-reference@1:3 C\"&#z\" EOF" },
    .{ .id = "A5", .code = "cdata-in-html-content", .input = "<![CDATA[x]]>", .expected = "!cdata-in-html-content@1:9 M\"[CDATA[x]]\" EOF" },
    .{ .id = "A6", .code = "character-reference-outside-unicode-range", .input = "&#x110000;", .expected = "!character-reference-outside-unicode-range@1:10 C\"\\uFFFD\" EOF" },
    .{ .id = "A7", .code = "control-character-in-input-stream", .input = "a\\u0001", .expected = "C\"a\" !control-character-in-input-stream@1:2 C\"\\u0001\" EOF" },
    .{ .id = "A8", .code = "control-character-reference", .input = "&#x80;", .expected = "!control-character-reference@1:6 C\"\\u20AC\" EOF" },
    .{ .id = "A9", .code = "disallowed-processing-instruction-target", .input = "<?XmL?>", .expected = "!disallowed-processing-instruction-target@1:6 M\"?XmL?\" EOF" },
    .{ .id = "A10", .code = "duplicate-attribute", .input = "<a b b>", .expected = "!duplicate-attribute@1:7 S\"a\"[b=\"\"] EOF" },
    .{ .id = "A11", .code = "end-tag-with-attributes", .input = "</a b>", .expected = "!end-tag-with-attributes@1:6 E\"a\"[b=\"\"] EOF" },
    .{ .id = "A12", .code = "end-tag-with-trailing-solidus", .input = "</a/>", .expected = "!end-tag-with-trailing-solidus@1:5 E\"a\"[]/ EOF" },
    .{ .id = "A12b", .code = "both end tag errors", .input = "</a b/>", .expected = "!end-tag-with-attributes@1:7 !end-tag-with-trailing-solidus@1:7 E\"a\"[b=\"\"]/ EOF" },
    .{ .id = "A13", .code = "eof-before-tag-name", .input = "<", .expected = "!eof-before-tag-name@1:2 C\"<\" EOF" },
    .{ .id = "A13b", .code = "eof-before-tag-name", .input = "</", .expected = "!eof-before-tag-name@1:3 C\"</\" EOF" },
    .{ .id = "A14", .code = "eof-in-comment", .input = "<!--a", .expected = "!eof-in-comment@1:6 M\"a\" EOF" },
    .{ .id = "A15", .code = "eof-in-doctype", .input = "<!DOCTYPE", .expected = "!eof-in-doctype@1:10 D(-,-,-,on) EOF" },
    .{ .id = "A16", .code = "eof-in-processing-instruction", .input = "<?a b", .expected = "!eof-in-processing-instruction@1:6 EOF" },
    .{ .id = "A17", .code = "eof-in-tag", .input = "<a b='c", .expected = "!eof-in-tag@1:8 EOF" },
    .{ .id = "A18", .code = "incorrectly-closed-comment", .input = "<!--a--!>", .expected = "!incorrectly-closed-comment@1:9 M\"a\" EOF" },
    .{ .id = "A19", .code = "incorrectly-opened-comment", .input = "<!x>", .expected = "!incorrectly-opened-comment@1:2 M\"x\" EOF" },
    .{ .id = "A20", .code = "invalid-character-sequence-after-doctype-name", .input = "<!DOCTYPE a b>", .expected = "!invalid-character-sequence-after-doctype-name@1:13 D(\"a\",-,-,on) EOF" },
    .{ .id = "A21", .code = "invalid-first-character-of-processing-instruction-target", .input = "<?1>", .expected = "!invalid-first-character-of-processing-instruction-target@1:3 M\"?1\" EOF" },
    .{ .id = "A22", .code = "invalid-first-character-of-tag-name", .input = "<1", .expected = "!invalid-first-character-of-tag-name@1:2 C\"<1\" EOF" },
    .{ .id = "A22b", .code = "invalid-first-character-of-tag-name", .input = "</1>", .expected = "!invalid-first-character-of-tag-name@1:3 M\"1\" EOF" },
    .{ .id = "A23", .code = "invalid-processing-instruction-target", .input = "<?a$>", .expected = "!invalid-processing-instruction-target@1:4 M\"?a$\" EOF" },
    .{ .id = "A24", .code = "missing-attribute-value", .input = "<a b=>", .expected = "!missing-attribute-value@1:6 S\"a\"[b=\"\"] EOF" },
    .{ .id = "A25", .code = "missing-doctype-name", .input = "<!DOCTYPE>", .expected = "!missing-doctype-name@1:10 D(-,-,-,on) EOF" },
    .{ .id = "A26", .code = "missing-doctype-public-identifier", .input = "<!DOCTYPE a PUBLIC>", .expected = "!missing-doctype-public-identifier@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "A27", .code = "missing-doctype-system-identifier", .input = "<!DOCTYPE a SYSTEM>", .expected = "!missing-doctype-system-identifier@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "A28", .code = "missing-end-tag-name", .input = "</>", .expected = "!missing-end-tag-name@1:3 EOF" },
    .{ .id = "A29", .code = "missing-quote-before-doctype-public-identifier", .input = "<!DOCTYPE a PUBLIC x>", .expected = "!missing-quote-before-doctype-public-identifier@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "A30", .code = "missing-quote-before-doctype-system-identifier", .input = "<!DOCTYPE a SYSTEM x>", .expected = "!missing-quote-before-doctype-system-identifier@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "A31", .code = "missing-semicolon-after-character-reference", .input = "&not", .expected = "!missing-semicolon-after-character-reference@1:4 C\"\\u00AC\" EOF" },
    .{ .id = "A32", .code = "missing-whitespace-after-doctype-public-keyword", .input = "<!DOCTYPE a PUBLIC\"x\">", .expected = "!missing-whitespace-after-doctype-public-keyword@1:19 D(\"a\",\"x\",-,off) EOF" },
    .{ .id = "A33", .code = "missing-whitespace-after-doctype-system-keyword", .input = "<!DOCTYPE a SYSTEM\"y\">", .expected = "!missing-whitespace-after-doctype-system-keyword@1:19 D(\"a\",-,\"y\",off) EOF" },
    .{ .id = "A34", .code = "missing-whitespace-before-doctype-name", .input = "<!DOCTYPEa>", .expected = "!missing-whitespace-before-doctype-name@1:10 D(\"a\",-,-,off) EOF" },
    .{ .id = "A35", .code = "missing-whitespace-between-attributes", .input = "<a b=\"c\"d>", .expected = "!missing-whitespace-between-attributes@1:9 S\"a\"[b=\"c\" d=\"\"] EOF" },
    .{ .id = "A36", .code = "missing-whitespace-between-doctype-public-and-system-identifiers", .input = "<!DOCTYPE a PUBLIC \"x\"\"y\">", .expected = "!missing-whitespace-between-doctype-public-and-system-identifiers@1:23 D(\"a\",\"x\",\"y\",off) EOF" },
    .{ .id = "A37", .code = "nested-comment", .input = "<!--<!--x-->", .expected = "!nested-comment@1:9 M\"<!--x\" EOF" },
    .{ .id = "A38", .code = "noncharacter-character-reference", .input = "&#xFFFF;", .expected = "!noncharacter-character-reference@1:8 C\"\\uFFFF\" EOF" },
    .{ .id = "A39", .code = "noncharacter-in-input-stream", .input = "\\uFFFE", .expected = "!noncharacter-in-input-stream@1:1 C\"\\uFFFE\" EOF" },
    .{ .id = "A40", .code = "null-character-reference", .input = "&#0;", .expected = "!null-character-reference@1:4 C\"\\uFFFD\" EOF" },
    .{ .id = "A41", .code = "surrogate-character-reference", .input = "&#xD800;", .expected = "!surrogate-character-reference@1:8 C\"\\uFFFD\" EOF" },
    .{ .id = "A42", .code = "surrogate-in-input-stream", .input = "\\uDC00", .expected = "!surrogate-in-input-stream@1:1 C\"\\uDC00\" EOF" },
    .{ .id = "A43", .code = "unexpected-character-after-doctype-system-identifier", .input = "<!DOCTYPE a SYSTEM \"y\" z>", .expected = "!unexpected-character-after-doctype-system-identifier@1:24 D(\"a\",-,\"y\",off) EOF" },
    .{ .id = "A44", .code = "unexpected-character-in-attribute-name", .input = "<a b\"c>", .expected = "!unexpected-character-in-attribute-name@1:5 S\"a\"[\"b\\\"c\"=\"\"] EOF" },
    .{ .id = "A45", .code = "unexpected-character-in-unquoted-attribute-value", .input = "<a b=c'd>", .expected = "!unexpected-character-in-unquoted-attribute-value@1:7 S\"a\"[b=\"c'd\"] EOF" },
    .{ .id = "A46", .code = "unexpected-equals-sign-before-attribute-name", .input = "<a =b>", .expected = "!unexpected-equals-sign-before-attribute-name@1:4 S\"a\"[\"=b\"=\"\"] EOF" },
    .{ .id = "A47", .code = "unexpected-null-character", .input = "a\\0", .expected = "C\"a\" !unexpected-null-character@1:2 C\"\\u0000\" EOF" },
    .{ .id = "A48", .code = "unexpected-solidus-in-tag", .input = "<a / b>", .expected = "!unexpected-solidus-in-tag@1:5 S\"a\"[b=\"\"] EOF" },
    .{ .id = "A49", .code = "unknown-named-character-reference", .input = "&zz;", .expected = "C\"&zz\" !unknown-named-character-reference@1:4 C\";\" EOF" },
};

/// Case 5, tags and attributes.
pub const tags = [_]Case{
    .{ .id = "T1", .input = "a<b>c</b>d", .expected = "C\"a\" S\"b\"[] C\"c\" E\"b\"[] C\"d\" EOF" },
    .{ .id = "T2", .input = "<A></A>", .expected = "S\"a\"[] E\"a\"[] EOF" },
    .{ .id = "T3", .input = "<br/>", .expected = "S\"br\"[]/ EOF" },
    .{ .id = "T4", .input = "<a b=\"c\"/>", .expected = "S\"a\"[b=\"c\"]/ EOF" },
    .{ .id = "T5", .input = "<a  >", .expected = "S\"a\"[] EOF" },
    .{ .id = "T6a", .input = "<a", .expected = "!eof-in-tag@1:3 EOF" },
    .{ .id = "T6b", .input = "<a ", .expected = "!eof-in-tag@1:4 EOF" },
    .{ .id = "T6c", .input = "<a b", .expected = "!eof-in-tag@1:5 EOF" },
    .{ .id = "T6d", .input = "<a b ", .expected = "!eof-in-tag@1:6 EOF" },
    .{ .id = "T6e", .input = "<a b=", .expected = "!eof-in-tag@1:6 EOF" },
    .{ .id = "T6f", .input = "<a b=\"", .expected = "!eof-in-tag@1:7 EOF" },
    .{ .id = "T6g", .input = "<a b=\"c\"", .expected = "!eof-in-tag@1:9 EOF" },
    .{ .id = "T6h", .input = "<a b=c", .expected = "!eof-in-tag@1:7 EOF" },
    .{ .id = "T6i", .input = "<a/", .expected = "!eof-in-tag@1:4 EOF" },
    .{ .id = "T7", .input = "<Ab\\0>", .expected = "!unexpected-null-character@1:4 S\"ab\\uFFFD\"[] EOF" },
    .{ .id = "T8", .input = "<a\\tb\\nc\\fd e>", .expected = "S\"a\"[b=\"\" c=\"\" d=\"\" e=\"\"] EOF" },
    .{ .id = "T9", .input = "<a B=1 c\\0d=\"2\">", .expected = "!unexpected-null-character@1:9 S\"a\"[b=\"1\" \"c\\uFFFDd\"=\"2\"] EOF" },
    .{ .id = "T10", .input = "<a b =c d /e f >", .expected = "!unexpected-solidus-in-tag@1:12 S\"a\"[b=\"c\" d=\"\" e=\"\" f=\"\"] EOF" },
    .{ .id = "T11", .input = "<a b= \"c\" d= 'e' f=>", .expected = "!missing-attribute-value@1:20 S\"a\"[b=\"c\" d=\"e\" f=\"\"] EOF" },
    .{ .id = "T12", .input = "<a b=\"&amp;\\0\" c='&lt;\\0'>", .expected = "!unexpected-null-character@1:12 !unexpected-null-character@1:22 S\"a\"[b=\"&\\uFFFD\" c=\"<\\uFFFD\"] EOF" },
    .{ .id = "T13", .input = "<a b=c&amp;d\\0e\"f'g<h=i`j k=l>", .expected = "!unexpected-null-character@1:13 !unexpected-character-in-unquoted-attribute-value@1:15 !unexpected-character-in-unquoted-attribute-value@1:17 !unexpected-character-in-unquoted-attribute-value@1:19 !unexpected-character-in-unquoted-attribute-value@1:21 !unexpected-character-in-unquoted-attribute-value@1:23 S\"a\"[b=\"c&d\\uFFFDe\\\"f'g<h=i`j\" k=\"l\"] EOF" },
    .{ .id = "T14", .input = "<a b=\"c\"\\t/>", .expected = "S\"a\"[b=\"c\"]/ EOF" },
    .{ .id = "T15", .input = "<a/b>", .expected = "!unexpected-solidus-in-tag@1:4 S\"a\"[b=\"\"] EOF" },
};

/// Case 6, markup declarations and comments.
pub const comments = [_]Case{
    .{ .id = "M1", .input = "<!---->", .expected = "M\"\" EOF" },
    .{ .id = "M2", .input = "<!--->", .expected = "!abrupt-closing-of-empty-comment@1:6 M\"\" EOF" },
    .{ .id = "M3", .input = "<!---", .expected = "!eof-in-comment@1:6 M\"\" EOF" },
    .{ .id = "M4", .input = "<!---a-->", .expected = "M\"-a\" EOF" },
    .{ .id = "M5", .input = "<!--\\0-->", .expected = "!unexpected-null-character@1:5 M\"\\uFFFD\" EOF" },
    .{ .id = "M6", .input = "<!--<<-->", .expected = "M\"<<\" EOF" },
    .{ .id = "M7", .input = "<!--<a-->", .expected = "M\"<a\" EOF" },
    .{ .id = "M8", .input = "<!--<!a-->", .expected = "M\"<!a\" EOF" },
    .{ .id = "M9", .input = "<!--<!-a-->", .expected = "M\"<!-a\" EOF" },
    .{ .id = "M10", .input = "<!--<!-->", .expected = "M\"<!\" EOF" },
    .{ .id = "M11", .input = "<!--<!--", .expected = "!eof-in-comment@1:9 M\"<!\" EOF" },
    .{ .id = "M12", .input = "<!--a-", .expected = "!eof-in-comment@1:7 M\"a\" EOF" },
    .{ .id = "M13", .input = "<!--a-b-->", .expected = "M\"a-b\" EOF" },
    .{ .id = "M14", .input = "<!--a--->", .expected = "M\"a-\" EOF" },
    .{ .id = "M15", .input = "<!--a--", .expected = "!eof-in-comment@1:8 M\"a\" EOF" },
    .{ .id = "M16", .input = "<!--a--b-->", .expected = "M\"a--b\" EOF" },
    .{ .id = "M17", .input = "<!--a--!-->", .expected = "M\"a--!\" EOF" },
    .{ .id = "M18", .input = "<!--a--!", .expected = "!eof-in-comment@1:9 M\"a\" EOF" },
    .{ .id = "M19", .input = "<!--a--!b-->", .expected = "M\"a--!b\" EOF" },
    .{ .id = "M20", .input = "<!x", .expected = "!incorrectly-opened-comment@1:2 M\"x\" EOF" },
    .{ .id = "M21", .input = "</1\\0>", .expected = "!invalid-first-character-of-tag-name@1:3 !unexpected-null-character@1:4 M\"1\\uFFFD\" EOF" },
    .{ .id = "M22", .input = "<!-", .expected = "!incorrectly-opened-comment@1:2 M\"-\" EOF" },
    .{ .id = "M23", .input = "<!DOCTYP", .expected = "!incorrectly-opened-comment@1:2 M\"DOCTYP\" EOF" },
    .{ .id = "M24", .input = "<![CDATA", .expected = "!incorrectly-opened-comment@1:2 M\"[CDATA\" EOF" },
    .{ .id = "M25", .input = "<!-x>", .expected = "!incorrectly-opened-comment@1:2 M\"-x\" EOF" },
};

/// Case 7, DOCTYPE.
pub const doctypes = [_]Case{
    .{ .id = "D1", .input = "<!DOCTYPE html>", .expected = "D(\"html\",-,-,off) EOF" },
    .{ .id = "D2", .input = "<!doctype  HTML >", .expected = "D(\"html\",-,-,off) EOF" },
    .{ .id = "D3", .input = "<!DOCTYPE \\0a\\0>", .expected = "!unexpected-null-character@1:11 !unexpected-null-character@1:13 D(\"\\uFFFDa\\uFFFD\",-,-,off) EOF" },
    .{ .id = "D4", .input = "<!DOCTYPE ", .expected = "!eof-in-doctype@1:11 D(-,-,-,on) EOF" },
    .{ .id = "D5", .input = "<!DOCTYPE a", .expected = "!eof-in-doctype@1:12 D(\"a\",-,-,on) EOF" },
    .{ .id = "D6", .input = "<!DOCTYPE a  ", .expected = "!eof-in-doctype@1:14 D(\"a\",-,-,on) EOF" },
    .{ .id = "D7", .input = "<!DOCTYPE a PUBLI", .expected = "!invalid-character-sequence-after-doctype-name@1:13 D(\"a\",-,-,on) EOF" },
    .{ .id = "D8", .input = "<!DOCTYPE a public'x'>", .expected = "!missing-whitespace-after-doctype-public-keyword@1:19 D(\"a\",\"x\",-,off) EOF" },
    .{ .id = "D9", .input = "<!DOCTYPE a PUBLIC", .expected = "!eof-in-doctype@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "D10", .input = "<!DOCTYPE a PUBLICx>", .expected = "!missing-quote-before-doctype-public-identifier@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "D11", .input = "<!DOCTYPE a PUBLIC  'x'>", .expected = "D(\"a\",\"x\",-,off) EOF" },
    .{ .id = "D12", .input = "<!DOCTYPE a PUBLIC >", .expected = "!missing-doctype-public-identifier@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "D13", .input = "<!DOCTYPE a PUBLIC ", .expected = "!eof-in-doctype@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "D14", .input = "<!DOCTYPE a PUBLIC \"\\0", .expected = "!unexpected-null-character@1:21 !eof-in-doctype@1:22 D(\"a\",\"\\uFFFD\",-,on) EOF" },
    .{ .id = "D15", .input = "<!DOCTYPE a PUBLIC '\\0x", .expected = "!unexpected-null-character@1:21 !eof-in-doctype@1:23 D(\"a\",\"\\uFFFDx\",-,on) EOF" },
    .{ .id = "D16", .input = "<!DOCTYPE a PUBLIC 'x>", .expected = "!abrupt-doctype-public-identifier@1:22 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "D17", .input = "<!DOCTYPE a PUBLIC \"x\"", .expected = "!eof-in-doctype@1:23 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "D18", .input = "<!DOCTYPE a PUBLIC \"x\"'y'>", .expected = "!missing-whitespace-between-doctype-public-and-system-identifiers@1:23 D(\"a\",\"x\",\"y\",off) EOF" },
    .{ .id = "D19", .input = "<!DOCTYPE a PUBLIC \"x\"z>", .expected = "!missing-quote-before-doctype-system-identifier@1:23 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "D20", .input = "<!DOCTYPE a PUBLIC \"x\" \\t\"y\">", .expected = "D(\"a\",\"x\",\"y\",off) EOF" },
    .{ .id = "D21", .input = "<!DOCTYPE a PUBLIC \"x\" >", .expected = "D(\"a\",\"x\",-,off) EOF" },
    .{ .id = "D22", .input = "<!DOCTYPE a PUBLIC \"x\" 'y'>", .expected = "D(\"a\",\"x\",\"y\",off) EOF" },
    .{ .id = "D23", .input = "<!DOCTYPE a PUBLIC \"x\" ", .expected = "!eof-in-doctype@1:24 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "D24", .input = "<!DOCTYPE a PUBLIC \"x\" z>", .expected = "!missing-quote-before-doctype-system-identifier@1:24 D(\"a\",\"x\",-,on) EOF" },
    .{ .id = "D25", .input = "<!DOCTYPE a SYSTEM'y'>", .expected = "!missing-whitespace-after-doctype-system-keyword@1:19 D(\"a\",-,\"y\",off) EOF" },
    .{ .id = "D26", .input = "<!DOCTYPE a SYSTEM", .expected = "!eof-in-doctype@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "D27", .input = "<!DOCTYPE a SYSTEMy>", .expected = "!missing-quote-before-doctype-system-identifier@1:19 D(\"a\",-,-,on) EOF" },
    .{ .id = "D28", .input = "<!DOCTYPE a SYSTEM \\t\"y\">", .expected = "D(\"a\",-,\"y\",off) EOF" },
    .{ .id = "D29", .input = "<!DOCTYPE a SYSTEM >", .expected = "!missing-doctype-system-identifier@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "D30", .input = "<!DOCTYPE a SYSTEM ", .expected = "!eof-in-doctype@1:20 D(\"a\",-,-,on) EOF" },
    .{ .id = "D31", .input = "<!DOCTYPE a SYSTEM \"y>", .expected = "!abrupt-doctype-system-identifier@1:22 D(\"a\",-,\"y\",on) EOF" },
    .{ .id = "D32", .input = "<!DOCTYPE a SYSTEM \"\\0", .expected = "!unexpected-null-character@1:21 !eof-in-doctype@1:22 D(\"a\",-,\"\\uFFFD\",on) EOF" },
    .{ .id = "D33", .input = "<!DOCTYPE a SYSTEM '\\0", .expected = "!unexpected-null-character@1:21 !eof-in-doctype@1:22 D(\"a\",-,\"\\uFFFD\",on) EOF" },
    .{ .id = "D34", .input = "<!DOCTYPE a SYSTEM \"y\" ", .expected = "!eof-in-doctype@1:24 D(\"a\",-,\"y\",on) EOF" },
    .{ .id = "D35", .input = "<!DOCTYPE a SYSTEM \"y\">", .expected = "D(\"a\",-,\"y\",off) EOF" },
    .{ .id = "D36", .input = "<!DOCTYPE a b\\0c>", .expected = "!invalid-character-sequence-after-doctype-name@1:13 !unexpected-null-character@1:14 D(\"a\",-,-,on) EOF" },
    .{ .id = "D37", .input = "<!DOCTYPE a b", .expected = "!invalid-character-sequence-after-doctype-name@1:13 D(\"a\",-,-,on) EOF" },
};

/// Case 8, processing instructions.
pub const instructions = [_]Case{
    .{ .id = "PI1", .input = "<?a>", .expected = "P(\"a\",\"\") EOF" },
    .{ .id = "PI2", .input = "<?_x-1 b c?>", .expected = "P(\"_x-1\",\"b c\") EOF" },
    .{ .id = "PI3", .input = "<?a?b?>", .expected = "P(\"a\",\"?b\") EOF" },
    .{ .id = "PI4", .input = "<?", .expected = "!eof-in-processing-instruction@1:3 EOF" },
    .{ .id = "PI5", .input = "<?ab", .expected = "!eof-in-processing-instruction@1:5 EOF" },
    .{ .id = "PI6", .input = "<?a ?", .expected = "!eof-in-processing-instruction@1:6 EOF" },
    .{ .id = "PI7", .input = "<?a b>", .expected = "P(\"a\",\"b\") EOF" },
    .{ .id = "PI8", .input = "<?xml x?>", .expected = "!disallowed-processing-instruction-target@1:6 M\"?xml x?\" EOF" },
    .{ .id = "PI9", .input = "<?Xml-Stylesheet>", .expected = "!disallowed-processing-instruction-target@1:17 M\"?Xml-Stylesheet\" EOF" },
    .{ .id = "PI10", .input = "<?xmlx>", .expected = "P(\"xmlx\",\"\") EOF" },
};

/// Case 9, character references. R3 is `&#x7`, then 17 `F` characters, then `;&#`, then 11 `9` characters, then `;`.
pub const references = [_]Case{
    .{ .id = "R1", .input = "&amp;&AMP&#65;&#x41;&#X6a;", .expected = "C\"&\" !missing-semicolon-after-character-reference@1:9 C\"&AAj\" EOF" },
    .{ .id = "R2", .input = "&#xAbC;&#00000065;&#9;&#13;&#x81;", .expected = "C\"\\u0ABCA\\u0009\" !control-character-reference@1:27 C\"\\u000D\" !control-character-reference@1:33 C\"\\u0081\" EOF" },
    .{ .id = "R3", .input = "&#x7" ++ @as([17]u8, @splat('F')) ++ ";&#" ++ @as([11]u8, @splat('9')) ++ ";", .expected = "!character-reference-outside-unicode-range@1:22 C\"\\uFFFD\" !character-reference-outside-unicode-range@1:36 C\"\\uFFFD\" EOF" },
    .{ .id = "R4", .input = "&#xg;&#x41 &#65x&", .expected = "!absence-of-digits-in-numeric-character-reference@1:4 C\"&#xg;\" !missing-semicolon-after-character-reference@1:11 C\"A \" !missing-semicolon-after-character-reference@1:16 C\"Ax&\" EOF" },
    .{ .id = "R5", .input = "<a b=\"&ampx&amp=&amp\" c=&zz; d='&zz'>", .expected = "!missing-semicolon-after-character-reference@1:20 !unknown-named-character-reference@1:28 S\"a\"[b=\"&ampx&amp=&\" c=\"&zz;\" d=\"&zz\"] EOF" },
    .{ .id = "R6", .input = "&zz &;", .expected = "C\"&zz &;\" EOF" },
    .{ .id = "R7", .input = "&notin;&notit;&noti", .expected = "C\"\\u2209\" !missing-semicolon-after-character-reference@1:11 C\"\\u00ACit;\" !missing-semicolon-after-character-reference@1:18 C\"\\u00ACi\" EOF" },
};

/// Case 10, input stream preprocessing.
pub const preprocessing = [_]Case{
    .{ .id = "N1", .input = "a\\r\\nb\\r\\rc\\r", .expected = "C\"a\\u000Ab\\u000A\\u000Ac\\u000A\" EOF" },
    .{ .id = "N2", .input = "\\u0001\\u0008\\u000B\\u000E\\u001F\\u007F\\u0080\\u009F\\t\\n\\f ", .expected = "!control-character-in-input-stream@1:1 C\"\\u0001\" !control-character-in-input-stream@1:2 C\"\\u0008\" !control-character-in-input-stream@1:3 C\"\\u000B\" !control-character-in-input-stream@1:4 C\"\\u000E\" !control-character-in-input-stream@1:5 C\"\\u001F\" !control-character-in-input-stream@1:6 C\"\\u007F\" !control-character-in-input-stream@1:7 C\"\\u0080\" !control-character-in-input-stream@1:8 C\"\\u009F\\u0009\\u000A\\u000C \" EOF" },
    .{ .id = "N3", .input = "\\uFDCF\\uFDD0\\uFDEF\\uFDF0\\uFFFE\\uFFFF\\uD83F\\uDFFF\\uDBFF\\uDFFE\\uDBFF\\uDFFF", .expected = "C\"\\uFDCF\" !noncharacter-in-input-stream@1:2 C\"\\uFDD0\" !noncharacter-in-input-stream@1:3 C\"\\uFDEF\\uFDF0\" !noncharacter-in-input-stream@1:5 C\"\\uFFFE\" !noncharacter-in-input-stream@1:6 C\"\\uFFFF\" !noncharacter-in-input-stream@1:7 C\"\\uD83F\\uDFFF\" !noncharacter-in-input-stream@1:9 C\"\\uDBFF\\uDFFE\" !noncharacter-in-input-stream@1:11 C\"\\uDBFF\\uDFFF\" EOF" },
    .{ .id = "N4", .input = "\\uD800a\\uDC00\\uD83D\\uDE00\\uDBFF", .expected = "!surrogate-in-input-stream@1:1 C\"\\uD800a\" !surrogate-in-input-stream@1:3 C\"\\uDC00\\uD83D\\uDE00\" !surrogate-in-input-stream@1:6 C\"\\uDBFF\" EOF" },
    .{ .id = "N5", .input = "<a\\uD800 b=\"\\uDC00\"><!--\\uD800-->", .expected = "!surrogate-in-input-stream@1:3 !surrogate-in-input-stream@1:8 S\"a\\uD800\"[b=\"\\uDC00\"] !surrogate-in-input-stream@1:15 M\"\\uD800\" EOF" },
    .{ .id = "N6", .input = "<a\\rb='\\r\\n'>\\r", .expected = "S\"a\"[b=\"\\u000A\"] C\"\\u000A\" EOF" },
};

/// The tables of cases 4 to 10, in case order.
pub const tables = [_][]const Case{ &catalog, &tags, &comments, &doctypes, &instructions, &references, &preprocessing };

/// Returns the case of cases 4 to 10 named `id`.
pub fn find(id: []const u8) Case {
    for (tables) |table| {
        for (table) |case| {
            if (std.mem.eql(u8, case.id, id)) return case;
        }
    }
    std.debug.panic("no case {s}", .{id});
}

// Helpers.

/// Decodes the input notation into code units.
pub fn decodeInput(gpa: Allocator, notation: []const u8) Allocator.Error![]u16 {
    var units: std.ArrayList(u16) = .empty;
    errdefer units.deinit(gpa);
    var index: usize = 0;
    while (index < notation.len) {
        const c = notation[index];
        if (c != '\\') {
            try units.append(gpa, c);
            index += 1;
            continue;
        }
        const escape = notation[index + 1];
        index += 2;
        try units.append(gpa, switch (escape) {
            '0' => 0,
            't' => '\t',
            'n' => '\n',
            'f' => 0x0C,
            'r' => '\r',
            'u' => unit: {
                const value = std.fmt.parseInt(u16, notation[index..][0..4], 16) catch unreachable;
                index += 4;
                break :unit value;
            },
            else => std.debug.panic("unknown escape \\{c}", .{escape}),
        });
    }
    return units.toOwnedSlice(gpa);
}

/// Copies the notation string that starts at `index` and returns the index after it.
fn copyString(w: *std.Io.Writer, notation: []const u8, index: usize) !usize {
    if (notation[index] != '"') return error.TestUnexpectedResult;
    var end = index + 1;
    while (notation[end] != '"') end += if (notation[end] == '\\') 2 else 1;
    try w.writeAll(notation[index .. end + 1]);
    return end + 1;
}

fn expectChar(notation: []const u8, index: usize, c: u8) !void {
    if (index >= notation.len or notation[index] != c) return error.TestUnexpectedResult;
}

/// Converts an expected sequence into the dump without spans.
pub fn expectedDump(gpa: Allocator, notation: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    var i: usize = 0;
    while (i < notation.len) {
        if (notation[i] == ' ') {
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, notation[i..], "EOF")) {
            try w.writeAll("[\"EOF\"]\n");
            i += 3;
            continue;
        }
        switch (notation[i]) {
            'C', 'M' => {
                try w.writeAll(if (notation[i] == 'C') "[\"Character\"," else "[\"Comment\",");
                i = try copyString(w, notation, i + 1);
                try w.writeAll("]\n");
            },
            'S', 'E' => {
                try w.writeAll(if (notation[i] == 'S') "[\"StartTag\"," else "[\"EndTag\",");
                i = try copyString(w, notation, i + 1);
                try expectChar(notation, i, '[');
                i += 1;
                try w.writeAll(",[");
                var first = true;
                while (notation[i] != ']') {
                    if (notation[i] == ' ') {
                        i += 1;
                        continue;
                    }
                    if (!first) try w.writeByte(',');
                    first = false;
                    try w.writeByte('[');
                    if (notation[i] == '"') {
                        i = try copyString(w, notation, i);
                    } else {
                        const equals = std.mem.indexOfScalarPos(u8, notation, i, '=') orelse return error.TestUnexpectedResult;
                        try w.print("\"{s}\"", .{notation[i..equals]});
                        i = equals;
                    }
                    try expectChar(notation, i, '=');
                    try w.writeByte(',');
                    i = try copyString(w, notation, i + 1);
                    try w.writeByte(']');
                }
                i += 1;
                const self_closing = i < notation.len and notation[i] == '/';
                if (self_closing) i += 1;
                try w.writeAll(if (self_closing) "],true]\n" else "],false]\n");
            },
            'P' => {
                try expectChar(notation, i + 1, '(');
                try w.writeAll("[\"PI\",");
                i = try copyString(w, notation, i + 2);
                try expectChar(notation, i, ',');
                try w.writeByte(',');
                i = try copyString(w, notation, i + 1);
                try expectChar(notation, i, ')');
                i += 1;
                try w.writeAll("]\n");
            },
            'D' => {
                try expectChar(notation, i + 1, '(');
                i += 2;
                try w.writeAll("[\"DOCTYPE\"");
                for (0..3) |_| {
                    try w.writeByte(',');
                    if (notation[i] == '-') {
                        try w.writeAll("null");
                        i += 1;
                    } else {
                        i = try copyString(w, notation, i);
                    }
                    try expectChar(notation, i, ',');
                    i += 1;
                }
                if (std.mem.startsWith(u8, notation[i..], "on)")) {
                    try w.writeAll(",true]\n");
                    i += 3;
                } else if (std.mem.startsWith(u8, notation[i..], "off)")) {
                    try w.writeAll(",false]\n");
                    i += 4;
                } else return error.TestUnexpectedResult;
            },
            '!' => {
                const at = std.mem.indexOfScalarPos(u8, notation, i, '@') orelse return error.TestUnexpectedResult;
                const colon = std.mem.indexOfScalarPos(u8, notation, at, ':') orelse return error.TestUnexpectedResult;
                const end = std.mem.indexOfScalarPos(u8, notation, colon, ' ') orelse notation.len;
                const line = try std.fmt.parseInt(usize, notation[at + 1 .. colon], 10);
                const column = try std.fmt.parseInt(usize, notation[colon + 1 .. end], 10);
                try w.print("[\"error\",\"{s}\",{d},{d},{d}]\n", .{ notation[i + 1 .. at], line, column, column - 1 });
                i = end;
            },
            else => return error.TestUnexpectedResult,
        }
    }
    return out.toOwnedSlice();
}

/// Tokenizes `input` in the chunks that the sorted `boundaries` delimit, as the partition harness does:
/// after each chunk it drains `next` to `need_input` and overwrites the chunk's buffer with 0xAAAA,
/// and after the last chunk it calls `finish` and drains to null. Returns the dump with `options`.
pub fn tokenizeChunks(gpa: Allocator, input: []const u16, boundaries: []const usize, options: dump.Options) ![]u8 {
    return tokenizeChunksForeign(gpa, input, boundaries, options, false);
}

pub fn tokenizeChunksForeign(gpa: Allocator, input: []const u16, boundaries: []const usize, options: dump.Options, foreign: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var dumper: dump.Dumper = .init(gpa, &out.writer, options);
    defer dumper.deinit();
    var t: Tokenizer = .init(gpa);
    defer t.deinit();
    t.adjusted_current_node_is_foreign = foreign;
    var start: usize = 0;
    if (input.len != 0) for (0..boundaries.len + 1) |index| {
        const end = if (index < boundaries.len) boundaries[index] else input.len;
        const buffer = try gpa.dupe(u16, input[start..end]);
        defer gpa.free(buffer);
        try t.feed(buffer);
        while (true) {
            const s = (try t.next()) orelse return error.TestUnexpectedResult;
            if (s == .need_input) break;
            try dumper.step(s);
        }
        @memset(buffer, 0xAAAA);
        start = end;
    };
    try t.finish();
    while (try t.next()) |s| {
        if (s == .need_input) return error.TestUnexpectedResult;
        try dumper.step(s);
    }
    try dumper.finish();
    return out.toOwnedSlice();
}

/// Returns the boundaries of one code unit per chunk.
fn unitBoundaries(gpa: Allocator, len: usize) Allocator.Error![]usize {
    const boundaries = try gpa.alloc(usize, if (len == 0) 0 else len - 1);
    for (boundaries, 1..) |*boundary, offset| boundary.* = offset;
    return boundaries;
}

/// Checks that `case` produces its expected sequence whole and one code unit per chunk.
fn checkCase(case: Case) !void {
    const gpa = testing.allocator;
    const input = try decodeInput(gpa, case.input);
    defer gpa.free(input);
    const expected = try expectedDump(gpa, case.expected);
    defer gpa.free(expected);
    const boundaries = try unitBoundaries(gpa, input.len);
    defer gpa.free(boundaries);
    for ([_][]const usize{ &.{}, boundaries }, [_][]const u8{ "whole", "one code unit per chunk" }) |chunks, label| {
        const observed = try tokenizeChunks(gpa, input, chunks, dump.plain);
        defer gpa.free(observed);
        if (!std.mem.eql(u8, expected, observed)) {
            std.debug.print("FP-0008 case {s}, {s}:\nexpected:\n{s}observed:\n{s}", .{ case.id, label, expected, observed });
            return error.TestExpectedEqual;
        }
    }
}

fn checkTable(table: []const Case) !void {
    var failed = false;
    for (table) |case| checkCase(case) catch |err| switch (err) {
        error.TestExpectedEqual => failed = true,
        else => return err,
    };
    if (failed) return error.TestExpectedEqual;
}

fn asciiUnits(comptime text: []const u8) [text.len]u16 {
    var units: [text.len]u16 = undefined;
    for (text, &units) |c, *unit| unit.* = c;
    return units;
}

// Records.

const frozen_titles = "Data state; RCDATA state; RAWTEXT state; Script data state; PLAINTEXT state; Tag open state; End tag open state; Tag name state; RCDATA less-than sign state; RCDATA end tag open state; RCDATA end tag name state; RAWTEXT less-than sign state; RAWTEXT end tag open state; RAWTEXT end tag name state; Script data less-than sign state; Script data end tag open state; Script data end tag name state; Script data escape start state; Script data escape start dash state; Script data escaped state; Script data escaped dash state; Script data escaped dash dash state; Script data escaped less-than sign state; Script data escaped end tag open state; Script data escaped end tag name state; Script data double escape start state; Script data double escaped state; Script data double escaped dash state; Script data double escaped dash dash state; Script data double escaped less-than sign state; Script data double escape end state; Before attribute name state; Attribute name state; After attribute name state; Before attribute value state; Attribute value (double-quoted) state; Attribute value (single-quoted) state; Attribute value (unquoted) state; After attribute value (quoted) state; Self-closing start tag state; Bogus comment state; Markup declaration open state; Comment start state; Comment start dash state; Comment state; Comment less-than sign state; Comment less-than sign bang state; Comment less-than sign bang dash state; Comment less-than sign bang dash dash state; Comment end dash state; Comment end state; Comment end bang state; DOCTYPE state; Before DOCTYPE name state; DOCTYPE name state; After DOCTYPE name state; After DOCTYPE public keyword state; Before DOCTYPE public identifier state; DOCTYPE public identifier (double-quoted) state; DOCTYPE public identifier (single-quoted) state; After DOCTYPE public identifier state; Between DOCTYPE public and system identifiers state; After DOCTYPE system keyword state; Before DOCTYPE system identifier state; DOCTYPE system identifier (double-quoted) state; DOCTYPE system identifier (single-quoted) state; After DOCTYPE system identifier state; Bogus DOCTYPE state; CDATA section state; CDATA section bracket state; CDATA section end state; Processing instruction open state; Processing instruction target state; After processing instruction target state; Processing instruction data state; Processing instruction questionable state; Character reference state; Named character reference state; Ambiguous ampersand state; Numeric character reference state; Hexadecimal character reference start state; Hexadecimal character reference state; Decimal character reference state; Numeric character reference end state";

test "FP-0008 case 1: State has 84 tags in section order with the frozen headings, implementation flags, and owners" {
    const values = std.enums.values(states.State);
    try testing.expectEqual(@as(usize, 84), values.len);
    var titles = std.mem.splitSequence(u8, frozen_titles, "; ");
    var unimplemented: usize = 0;
    for (values, 1..) |state, number| {
        try testing.expectEqual(@as(u8, @intCast(number)), states.section(state));
        try testing.expectEqualStrings(titles.next().?, states.title(state));
        const expected = number == 1 or (number >= 6 and number <= 8) or (number >= 32 and number <= 68) or (number >= 72 and number <= 84);
        try testing.expectEqual(expected, states.implemented(state));
        if (expected) {
            try testing.expect(states.owner(state) == null);
            try testing.expect(states.branches(state).len != 0);
        } else {
            unimplemented += 1;
            try testing.expectEqualStrings("FP-0064", states.owner(state).?);
            try testing.expectEqual(@as(usize, 0), states.branches(state).len);
        }
    }
    try testing.expect(titles.next() == null);
    try testing.expectEqual(@as(usize, 30), unimplemented);
    try testing.expectEqualStrings("attribute_value_double_quoted", @tagName(states.State.attribute_value_double_quoted));
    try testing.expectEqualStrings("numeric_character_reference_end", @tagName(states.State.numeric_character_reference_end));
}

const frozen_codes = [_][]const u8{
    "abrupt-closing-of-empty-comment",
    "abrupt-doctype-public-identifier",
    "abrupt-doctype-system-identifier",
    "absence-of-digits-in-numeric-character-reference",
    "cdata-in-html-content",
    "character-reference-outside-unicode-range",
    "control-character-in-input-stream",
    "control-character-reference",
    "disallowed-processing-instruction-target",
    "duplicate-attribute",
    "end-tag-with-attributes",
    "end-tag-with-trailing-solidus",
    "eof-before-tag-name",
    "eof-in-cdata",
    "eof-in-comment",
    "eof-in-doctype",
    "eof-in-processing-instruction",
    "eof-in-script-html-comment-like-text",
    "eof-in-tag",
    "incorrectly-closed-comment",
    "incorrectly-opened-comment",
    "invalid-character-sequence-after-doctype-name",
    "invalid-first-character-of-processing-instruction-target",
    "invalid-first-character-of-tag-name",
    "invalid-processing-instruction-target",
    "missing-attribute-value",
    "missing-doctype-name",
    "missing-doctype-public-identifier",
    "missing-doctype-system-identifier",
    "missing-end-tag-name",
    "missing-quote-before-doctype-public-identifier",
    "missing-quote-before-doctype-system-identifier",
    "missing-semicolon-after-character-reference",
    "missing-whitespace-after-doctype-public-keyword",
    "missing-whitespace-after-doctype-system-keyword",
    "missing-whitespace-before-doctype-name",
    "missing-whitespace-between-attributes",
    "missing-whitespace-between-doctype-public-and-system-identifiers",
    "nested-comment",
    "noncharacter-character-reference",
    "noncharacter-in-input-stream",
    "non-void-html-element-start-tag-with-trailing-solidus",
    "null-character-reference",
    "surrogate-character-reference",
    "surrogate-in-input-stream",
    "unexpected-character-after-doctype-system-identifier",
    "unexpected-character-in-attribute-name",
    "unexpected-character-in-unquoted-attribute-value",
    "unexpected-equals-sign-before-attribute-name",
    "unexpected-null-character",
    "unexpected-solidus-in-tag",
    "unknown-named-character-reference",
};

test "FP-0008 case 2: ErrorCode has the 52 codes of the parse error table in order, and three are not raised by the tokenizer" {
    const values = std.enums.values(errors.ErrorCode);
    try testing.expectEqual(@as(usize, 52), values.len);
    const unraised = [_][]const u8{ "eof-in-cdata", "eof-in-script-html-comment-like-text", "non-void-html-element-start-tag-with-trailing-solidus" };
    var raised: usize = 0;
    for (values, frozen_codes) |code, text| {
        try testing.expectEqualStrings(text, errors.name(code));
        try testing.expectEqual(code, errors.fromName(text).?);
        var listed = false;
        for (unraised) |other| listed = listed or std.mem.eql(u8, other, text);
        try testing.expectEqual(!listed, errors.raisedByTokenizer(code));
        if (!listed) raised += 1;
    }
    try testing.expectEqual(@as(usize, 49), raised);
    try testing.expect(errors.fromName("eof-in-everything") == null);
}

// Error catalog and state walks.

test "FP-0008 case 4: each error catalog input produces exactly its expected sequence, whole and one code unit per chunk" {
    try checkTable(&catalog);
    // The catalog names each of the 49 codes that the tokenizer raises, and its expected sequence reports it.
    for (std.enums.values(errors.ErrorCode)) |code| {
        var named = false;
        for (catalog) |case| {
            if (!std.mem.eql(u8, case.code, errors.name(code))) continue;
            named = true;
            var marker_buffer: [96]u8 = undefined;
            const marker = try std.fmt.bufPrint(&marker_buffer, "!{s}@", .{errors.name(code)});
            try testing.expect(std.mem.indexOf(u8, case.expected, marker) != null);
        }
        try testing.expectEqual(errors.raisedByTokenizer(code), named);
    }
}

test "FP-0008 case 5: tags and attributes, whole and one code unit per chunk" {
    try checkTable(&tags);
}

test "FP-0008 case 6: markup declarations and comments, whole and one code unit per chunk" {
    try checkTable(&comments);
}

test "FP-0008 case 7: DOCTYPE, whole and one code unit per chunk" {
    try checkTable(&doctypes);
}

test "FP-0008 case 8: processing instructions, whole and one code unit per chunk" {
    try checkTable(&instructions);
}

test "FP-0008 case 9: character references, whole and one code unit per chunk" {
    try testing.expectEqual(@as(usize, 36), find("R3").input.len);
    try checkTable(&references);
}

test "FP-0008 case 10: input stream preprocessing, whole and one code unit per chunk, and N6's end-of-file position" {
    try checkTable(&preprocessing);
    const gpa = testing.allocator;
    const input = try decodeInput(gpa, find("N6").input);
    defer gpa.free(input);
    const end = (try endOfFile(gpa, input)).start;
    try testing.expectEqual(@as(usize, 11), @backingInt(end.offset));
    try testing.expectEqual(@as(usize, 4), end.line);
    try testing.expectEqual(@as(usize, 1), end.column);
}

/// Returns the span of the end-of-file token of `input` as one chunk.
fn endOfFile(gpa: Allocator, input: []const u16) !tokenizer.Span {
    return (try tokenSpan(gpa, input, .end_of_file)).?;
}

/// Returns the span of the first token of kind `kind` of `input` as one chunk.
fn tokenSpan(gpa: Allocator, input: []const u16, kind: std.meta.Tag(tokenizer.Kind)) !?tokenizer.Span {
    var t: Tokenizer = .init(gpa);
    defer t.deinit();
    try t.feed(input);
    try t.finish();
    while (try t.next()) |s| {
        if (s == .token and s.token.kind == kind) return s.token.span;
    }
    return null;
}

// Branch coverage.

test "FP-0008 case 11: cases 4 to 10 and case 16 execute every listed branch of every implemented state" {
    @memset(&tokenizer.coverage, 0);
    for (tables) |table| try checkTable(table);
    try runCase16();
    var missing: usize = 0;
    for (tokenizer.coverage, 0..) |count, index| {
        if (count != 0) continue;
        const branch = states.branchAt(index);
        std.debug.print("FP-0008 case 11: no case executes the branch \"{s}\" of the {s}\n", .{ branch.name, states.title(branch.state) });
        missing += 1;
    }
    try testing.expectEqual(@as(usize, 0), missing);
    var listed: usize = 0;
    for (std.enums.values(states.State)) |state| listed += states.branches(state).len;
    try testing.expectEqual(states.branch_count, listed);
}

// Source positions.

fn expectFullDump(notation: []const u8, expected: []const u8) !void {
    const gpa = testing.allocator;
    const input = try decodeInput(gpa, notation);
    defer gpa.free(input);
    const observed = try tokenizeChunks(gpa, input, &.{}, dump.full);
    defer gpa.free(observed);
    try testing.expectEqualStrings(expected, observed);
}

pub const s1_input = "ab<c d=\"e\">&amp;f<!--g--><?h i?>&#x41\\r\\n<!DOCTYPE j>";
pub const s1_dump =
    \\["Character","ab",[0,2]]
    \\["StartTag","c",[["d","e",[5,6],[8,9]]],false,[2,11]]
    \\["Character","&f",[11,17]]
    \\["Comment","g",[17,25]]
    \\["PI","h","i",[25,32]]
    \\["error","missing-semicolon-after-character-reference",1,38,37]
    \\["Character","A\u000A",[32,39]]
    \\["DOCTYPE","j",null,null,false,[39,51]]
    \\["EOF",[51,51]]
    \\
;

test "FP-0008 case 12: each input produces exactly its dump with spans and errors" {
    const gpa = testing.allocator;
    {
        const input = try decodeInput(gpa, s1_input);
        defer gpa.free(input);
        try testing.expectEqual(@as(usize, 51), input.len);
        try expectFullDump(s1_input, s1_dump);
        const doctype = (try tokenSpan(gpa, input, .doctype)).?.start;
        try testing.expectEqual(@as(usize, 2), doctype.line);
        try testing.expectEqual(@as(usize, 1), doctype.column);
        const end = (try endOfFile(gpa, input)).start;
        try testing.expectEqual(@as(usize, 2), end.line);
        try testing.expectEqual(@as(usize, 13), end.column);
    }
    try expectFullDump("<x a b='' c=d e = \"f\">",
        \\["StartTag","x",[["a","",[3,4],null],["b","",[5,6],[8,8]],["c","d",[10,11],[12,13]],["e","f",[14,15],[19,20]]],false,[0,22]]
        \\["EOF",[22,22]]
        \\
    );
    try expectFullDump("<!--a",
        \\["error","eof-in-comment",1,6,5]
        \\["Comment","a",[0,5]]
        \\["EOF",[5,5]]
        \\
    );
    try expectFullDump("<!DOCTYPE",
        \\["error","eof-in-doctype",1,10,9]
        \\["DOCTYPE",null,null,null,true,[0,9]]
        \\["EOF",[9,9]]
        \\
    );
    {
        try expectFullDump("\\n\\r\\n\\r<a\\0>",
            \\["Character","\u000A\u000A\u000A",[0,4]]
            \\["error","unexpected-null-character",4,3,6]
            \\["StartTag","a\uFFFD",[],false,[4,8]]
            \\["EOF",[8,8]]
            \\
        );
        const input = try decodeInput(gpa, "\\n\\r\\n\\r<a\\0>");
        defer gpa.free(input);
        const end = (try endOfFile(gpa, input)).start;
        try testing.expectEqual(@as(usize, 4), end.line);
        try testing.expectEqual(@as(usize, 5), end.column);
    }
    try expectFullDump("<a b=&lt; b=c>",
        \\["error","duplicate-attribute",1,12,11]
        \\["StartTag","a",[["b","<",[3,4],[5,9]]],false,[0,14]]
        \\["EOF",[14,14]]
        \\
    );
    try expectFullDump("<1</",
        \\["error","invalid-first-character-of-tag-name",1,2,1]
        \\["Character","<1",[0,2]]
        \\["error","eof-before-tag-name",1,5,4]
        \\["Character","</",[2,4]]
        \\["EOF",[4,4]]
        \\
    );
}

// Interface edges.

/// Drains `t` until `need_input` or null and writes each step to `dumper`. Returns whether the last step was `need_input`.
fn drain(t: *Tokenizer, dumper: *dump.Dumper) !bool {
    while (try t.next()) |s| {
        if (s == .need_input) return true;
        try dumper.step(s);
    }
    return false;
}

test "FP-0008 case 15: interface edges" {
    const gpa = testing.allocator;
    // `next` before any `feed` returns `need_input`, and again without new input.
    {
        var t: Tokenizer = .init(gpa);
        defer t.deinit();
        try testing.expect((try t.next()).? == .need_input);
        try testing.expect((try t.next()).? == .need_input);
        const input = asciiUnits("<a");
        try t.feed(&input);
        try testing.expect((try t.next()).? == .need_input);
        try testing.expect((try t.next()).? == .need_input);
    }
    // `finish` with no input yields only the end-of-file token at line 1, column 1, and then null twice.
    {
        var t: Tokenizer = .init(gpa);
        defer t.deinit();
        try t.finish();
        try t.finish();
        const s = (try t.next()).?;
        try testing.expect(s == .token and s.token.kind == .end_of_file);
        try testing.expectEqual(@as(usize, 0), @backingInt(s.token.span.start.offset));
        try testing.expectEqual(@as(usize, 0), @backingInt(s.token.span.end.offset));
        try testing.expectEqual(@as(usize, 1), s.token.span.start.line);
        try testing.expectEqual(@as(usize, 1), s.token.span.start.column);
        try testing.expect((try t.next()) == null);
        try testing.expect((try t.next()) == null);
        try testing.expectError(error.InputFinished, t.feed(&.{}));
    }
    const whole = try tokenizeChunks(gpa, &asciiUnits("<a>"), &.{}, dump.full);
    defer gpa.free(whole);
    try testing.expectEqualStrings("[\"StartTag\",\"a\",[],false,[0,3]]\n[\"EOF\",[3,3]]\n", whole);
    // An empty chunk between `<a` and `>`, a refused second `feed`, and a second `finish` change no dump.
    {
        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        var dumper: dump.Dumper = .init(gpa, &out.writer, dump.full);
        defer dumper.deinit();
        var t: Tokenizer = .init(gpa);
        defer t.deinit();
        const first = asciiUnits("<a");
        const last = asciiUnits(">");
        const refused = asciiUnits("zz");
        try t.feed(&first);
        try testing.expectError(error.ChunkPending, t.feed(&refused));
        try testing.expect(try drain(&t, &dumper));
        try t.feed(&.{});
        try testing.expectError(error.ChunkPending, t.feed(&refused));
        try testing.expect(try drain(&t, &dumper));
        try t.feed(&last);
        try t.finish();
        try t.finish();
        try testing.expectError(error.InputFinished, t.feed(&refused));
        try testing.expect(!try drain(&t, &dumper));
        try testing.expect((try t.next()) == null);
        try testing.expect((try t.next()) == null);
        try dumper.finish();
        try testing.expectEqualStrings(whole, out.written());
    }
}

// Unimplemented state.

fn runCase16() !void {
    const gpa = testing.allocator;
    const input = asciiUnits("<![CDATA[x]]>");
    // One chunk: the first `next` after `finish` fails.
    {
        var t: Tokenizer = .init(gpa);
        defer t.deinit();
        t.adjusted_current_node_is_foreign = true;
        try t.feed(&input);
        try t.finish();
        try testing.expectError(error.UnimplementedState, t.next());
        try testing.expectEqual(@as(?states.State, .cdata_section), t.unimplementedState());
        try testing.expectError(error.UnimplementedState, t.next());
        try testing.expectError(error.UnimplementedState, t.feed(&input));
        try testing.expectError(error.UnimplementedState, t.finish());
        try testing.expectEqual(@as(?states.State, .cdata_section), t.unimplementedState());
    }
    // Two chunks: the first gives `need_input`.
    {
        var t: Tokenizer = .init(gpa);
        defer t.deinit();
        t.adjusted_current_node_is_foreign = true;
        try t.feed(input[0..7]);
        try testing.expect((try t.next()).? == .need_input);
        try testing.expect(t.unimplementedState() == null);
        try t.feed(input[7..]);
        try t.finish();
        try testing.expectError(error.UnimplementedState, t.next());
        try testing.expectEqual(@as(?states.State, .cdata_section), t.unimplementedState());
        try testing.expectError(error.UnimplementedState, t.next());
        try testing.expectError(error.UnimplementedState, t.feed(&input));
        try testing.expectError(error.UnimplementedState, t.finish());
    }
    // With the flag false, the same input gives A5, whole and in the same two chunks.
    const expected = try expectedDump(gpa, find("A5").expected);
    defer gpa.free(expected);
    for ([_][]const usize{ &.{}, &.{7} }) |boundaries| {
        const observed = try tokenizeChunksForeign(gpa, &input, boundaries, dump.plain, false);
        defer gpa.free(observed);
        try testing.expectEqualStrings(expected, observed);
    }
}

test "FP-0008 case 16: entering the CDATA section state with a foreign adjusted current node reports UnimplementedState" {
    try runCase16();
}

// Allocation failure.

const allocation_input = asciiUnits("<!DOCTYPE html><a b=\"&amp;c\">x&notin;<!--d--><?e f?>");

/// Returns `err`. After `error.OutOfMemory`, first checks that every later call returns it again.
fn again(t: *Tokenizer, err: tokenizer.Error) anyerror {
    if (err != error.OutOfMemory) return err;
    testing.expectError(error.OutOfMemory, t.next()) catch |e| return e;
    testing.expectError(error.OutOfMemory, t.feed(&.{})) catch |e| return e;
    testing.expectError(error.OutOfMemory, t.finish()) catch |e| return e;
    return err;
}

fn tokenizeUnderAllocationFailure(gpa: Allocator) !void {
    var t: Tokenizer = .init(gpa);
    defer t.deinit();
    const chunks = [_][]const u16{ allocation_input[0..7], allocation_input[7..23], allocation_input[23..] };
    var tokens: usize = 0;
    for (chunks) |chunk| {
        t.feed(chunk) catch |err| return again(&t, err);
        while (t.next() catch |err| return again(&t, err)) |s| {
            if (s == .need_input) break;
            if (s == .token) tokens += 1;
        }
    }
    t.finish() catch |err| return again(&t, err);
    while (t.next() catch |err| return again(&t, err)) |s| {
        if (s == .token) tokens += 1;
    }
    // DOCTYPE, start tag, characters, comment, processing instruction, and end of file.
    try testing.expect(tokens >= 6);
}

test "FP-0008 case 17: each induced allocation failure returns OutOfMemory, every later call returns it again, and nothing leaks" {
    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_remap.allocator(), tokenizeUnderAllocationFailure, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}
