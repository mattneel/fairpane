//! The exact test cases of the FP-0014 contract for `src/css/`. Cases 18 to 20 live in `src/dom.zig`.
//! Every case uses `std.testing.allocator`, so a leak fails the case.

const std = @import("std");
const dom = @import("../dom.zig");
const web_string = @import("../web_string.zig");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const dump = @import("dump.zig");
const stylesheet = @import("stylesheet.zig");
const selectors = @import("selectors.zig");
const registry = @import("registry.zig");
const values = @import("values.zig");
const cascade = @import("cascade.zig");
const applicable = @import("applicable.zig");
const compute = @import("compute.zig");
const style = @import("style.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const View = web_string.View;
const NodeHandle = dom.NodeHandle;
const ComponentValue = parser.ComponentValue;
const ComputedStyle = compute.ComputedStyle;
const Stylesheet = stylesheet.Stylesheet;
const DiagnosticKind = stylesheet.DiagnosticKind;
const InvalidReason = compute.InvalidReason;

/// The UTF-16 code units of a UTF-8 literal.
fn u(comptime text: []const u8) View {
    return .{ .units = std.unicode.utf8ToUtf16LeStringLiteral(text) };
}

/// The UTF-16 code units of a runtime UTF-8 string, allocated in `arena`.
fn runtimeView(arena: Allocator, text: []const u8) !View {
    const string = try web_string.WebString.fromUtf8(arena, text);
    return string.view();
}

fn writeTokenList(_: Allocator, w: *std.Io.Writer, tokens: []const tokenizer.Token) dump.Error!void {
    try dump.writeTokens(w, tokens);
}

fn tokenize(arena: Allocator, input: View, options: tokenizer.Options) ![]const tokenizer.Token {
    const filtered = try tokenizer.filterCodePoints(arena, input);
    return tokenizer.tokenizeAll(arena, filtered, options);
}

fn expectTokens(input: View, options: tokenizer.Options, expected: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const tokens = try tokenize(arena.allocator(), input, options);
    const text = try dump.allocPrint(arena.allocator(), writeTokenList, tokens);
    try testing.expectEqualStrings(expected, text);
}

fn expectValues(expected: []const u8, list: []const ComponentValue) !void {
    const text = try dump.allocPrint(testing.allocator, dump.writeComponentValues, list);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

fn expectRule(expected: []const u8, rule: parser.Rule) !void {
    const text = try dump.allocPrint(testing.allocator, dump.writeRule, rule);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

fn expectBlockItem(expected: []const u8, item: parser.BlockItem) !void {
    const text = try dump.allocPrint(testing.allocator, dump.writeBlockItem, item);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

fn expectDeclaration(expected: []const u8, declaration: parser.Declaration) !void {
    const text = try dump.allocPrint(testing.allocator, dump.writeDeclaration, declaration);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings(expected, text);
}

/// Parses a stylesheet with `SyntaxOnly` and checks the dump of each rule.
fn expectStylesheet(comptime source: []const u8, expected: []const []const u8) !void {
    var parsed = try parser.parseStylesheet(testing.allocator, u(source), .syntax_only);
    defer parsed.deinit();
    try testing.expectEqual(expected.len, parsed.value.len);
    for (expected, parsed.value) |text, rule| try expectRule(text, rule);
}

// Tokenizer.

test "FP-0014 case 1: filtering maps CR LF, CR, FF, NUL, and lone surrogates, and pairs surrogates" {
    const input = [_]u16{ 'a', '\r', '\n', 'b', '\r', 'c', 0x0C, 'd', 0, 'e', 0xD800, 'f', 0xD83D, 0xDE00 };
    try expectTokens(.{ .units = &input }, .{}, "ident(a) ws ident(b) ws ident(c) ws ident(d\u{FFFD}e\u{FFFD}f\u{1F600})");
}

test "FP-0014 case 2: every token kind dumps in the frozen format" {
    try expectTokens(
        u("a f( @k #i #1 \"s\" 'q' url(u) 1 2% 3px , : ; [ ] ( ) { } <!-- --> ~ U+1"),
        .{},
        "ident(a) ws function(f) ws at(k) ws hash(i,id) ws hash(1,unrestricted) ws string(s) ws string(q) ws url(u) ws " ++
            "number(1,integer,none) ws percentage(2,none) ws dimension(3,integer,none,px) ws , ws : ws ; ws [ ws ] ws ( ws ) ws " ++
            "{ ws } ws <!-- ws --> ws delim(~) ws ident(U) number(1,integer,+)",
    );
}

test "FP-0014 case 3: bad tokens, URLs, and escapes" {
    const cases = [_]struct { input: View, expected: []const u8 }{
        .{ .input = u("\"a\nb"), .expected = "bad-string ws ident(b)" },
        .{ .input = u("\"abc"), .expected = "string(abc)" },
        .{ .input = u("\"a\\\nb\""), .expected = "string(ab)" },
        .{ .input = u("\"a\\"), .expected = "string(a)" },
        .{ .input = u("url(a b) x"), .expected = "bad-url ws ident(x)" },
        .{ .input = u("url(a\"b) x"), .expected = "bad-url ws ident(x)" },
        .{ .input = u("url(\\\n)"), .expected = "bad-url" },
        .{ .input = u("url( \"q\" )"), .expected = "function(url) ws string(q) ws )" },
        .{ .input = u("url(  x  )"), .expected = "url(x)" },
        .{ .input = u("url(x"), .expected = "url(x)" },
        .{ .input = u("URL(x)"), .expected = "url(x)" },
        .{ .input = u("u\\72l(x)"), .expected = "url(x)" },
        .{ .input = u("\\41 x"), .expected = "ident(Ax)" },
        .{ .input = u("a\\"), .expected = "ident(a\u{FFFD})" },
        .{ .input = u("\\0 \\D800 \\110000 \\10FFFF"), .expected = "ident(\u{FFFD}\u{FFFD}\u{FFFD}\u{10FFFF})" },
        .{ .input = u("\\\n"), .expected = "delim(\\) ws" },
    };
    for (cases) |case| try expectTokens(case.input, .{}, case.expected);
}

test "FP-0014 case 4: numbers tokenize to the nearest f64 with type and sign" {
    const cases = [_]struct { input: View, expected: []const u8 }{
        .{ .input = u("+.5"), .expected = "number(0.5,number,+)" },
        .{ .input = u("1e3"), .expected = "number(1000,number,none)" },
        .{ .input = u("1.5E-2"), .expected = "number(0.015,number,none)" },
        .{ .input = u("1e"), .expected = "dimension(1,integer,none,e)" },
        .{ .input = u("1e+"), .expected = "dimension(1,integer,none,e) delim(+)" },
        .{ .input = u(".5.5"), .expected = "number(0.5,number,none) number(0.5,number,none)" },
        .{ .input = u("12."), .expected = "number(12,integer,none) delim(.)" },
        .{ .input = u("-1px"), .expected = "dimension(-1,integer,-,px)" },
        .{ .input = u("1--x"), .expected = "dimension(1,integer,none,--x)" },
        .{ .input = u("5%%"), .expected = "percentage(5,none) delim(%)" },
    };
    for (cases) |case| try expectTokens(case.input, .{}, case.expected);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_]struct { input: View, value: f64 }{
        .{ .input = u("1e999"), .value = std.math.floatMax(f64) },
        .{ .input = u("-1e999"), .value = -std.math.floatMax(f64) },
    }) |case| {
        const tokens = try tokenize(arena.allocator(), case.input, .{});
        try testing.expectEqual(1, tokens.len);
        try testing.expectEqual(tokenizer.TokenKind.number, tokens[0].kind);
        try testing.expectEqual(case.value, tokens[0].number);
    }
}

test "FP-0014 case 5: identifiers, hashes, at-keywords, delims, and comments" {
    const cases = [_]struct { input: View, expected: []const u8 }{
        .{ .input = u("-a"), .expected = "ident(-a)" },
        .{ .input = u("--"), .expected = "ident(--)" },
        .{ .input = u("-"), .expected = "delim(-)" },
        .{ .input = u("-\\31"), .expected = "ident(-1)" },
        .{ .input = u("@-"), .expected = "delim(@) delim(-)" },
        .{ .input = u("@--x"), .expected = "at(--x)" },
        .{ .input = u("#"), .expected = "delim(#)" },
        .{ .input = u("#-"), .expected = "hash(-,unrestricted)" },
        .{ .input = u("#-a"), .expected = "hash(-a,id)" },
        .{ .input = u("\u{00B7}a"), .expected = "ident(\u{00B7}a)" },
        .{ .input = u("\u{00D7}"), .expected = "delim(\u{00D7})" },
        .{ .input = u("\u{200C}x"), .expected = "ident(\u{200C}x)" },
        .{ .input = u("/* a */b/* unterminated"), .expected = "ident(b)" },
        .{ .input = u("a/**/b"), .expected = "ident(a) ident(b)" },
    };
    for (cases) |case| try expectTokens(case.input, .{}, case.expected);
}

test "FP-0014 case 6: unicode-range tokens appear only when unicode ranges are allowed" {
    const cases = [_]struct { input: View, expected: []const u8 }{
        .{ .input = u("U+26"), .expected = "unicode-range(26,26)" },
        .{ .input = u("u+0-7F"), .expected = "unicode-range(0,7F)" },
        .{ .input = u("U+4??"), .expected = "unicode-range(400,4FF)" },
        .{ .input = u("U+??????"), .expected = "unicode-range(0,FFFFFF)" },
        .{ .input = u("u+a"), .expected = "unicode-range(A,A)" },
        .{ .input = u("U+1234567"), .expected = "unicode-range(123456,123456) number(7,integer,none)" },
        .{ .input = u("U+5-"), .expected = "unicode-range(5,5) delim(-)" },
        .{ .input = u("U+"), .expected = "ident(U) delim(+)" },
    };
    for (cases) |case| try expectTokens(case.input, .{ .unicode_ranges_allowed = true }, case.expected);
    try expectTokens(u("U+26"), .{}, "ident(U) number(26,integer,+)");
}

// Syntax parser with SyntaxOnly.

test "FP-0014 case 7: parseStylesheet gives at-rules, qualified rules, and nested rules, and skips CDO and CDC" {
    try expectStylesheet("@import \"a\"; a { b: c } @media x { d { e: f } } <!-- g{} -->", &.{
        "@import [ws string(a)] no-block",
        "qualified [ident(a) ws] decls{b = [ident(c)]} rules{}",
        "@media [ws ident(x) ws] block{qualified [ident(d) ws] decls{e = [ident(f)]} rules{}}",
        "qualified [ident(g)] decls{} rules{}",
    });
}

test "FP-0014 case 8: a block's contents recover from bad declarations and keep the trailing declaration" {
    try expectStylesheet("a { ; b: c; d e; f: g !important; : h; i: j k ; l: m }", &.{
        "qualified [ident(a) ws] decls{b = [ident(c)]; f = [ident(g)] !important; i = [ident(j) ws ident(k)]; l = [ident(m)]} rules{}",
    });
}

test "FP-0014 case 9: unclosed functions, blocks, and strings end at EOF" {
    try expectStylesheet("a { b: c(d [e", &.{
        "qualified [ident(a) ws] decls{b = [function(c)[ident(d) ws block([)[ident(e)]]]} rules{}",
    });
    try expectStylesheet("a { b: \"x", &.{"qualified [ident(a) ws] decls{b = [string(x)]} rules{}"});
}

test "FP-0014 case 10: custom-property-like rules, custom property blocks, and nested declarations" {
    try expectStylesheet("--foo:hover { color: red } b { }", &.{"qualified [ident(b) ws] decls{} rules{}"});

    var parsed = try parser.parseStylesheet(testing.allocator, u("a { --x:y {z}; w: v }"), .syntax_only);
    defer parsed.deinit();
    try testing.expectEqual(1, parsed.value.len);
    try expectRule("qualified [ident(a) ws] decls{--x = [ident(y) ws block({)[ident(z)]]; w = [ident(v)]} rules{}", parsed.value[0]);
    try testing.expectEqualSlices(u16, u("y {z}").units, parsed.value[0].qualified.declarations[0].original_text.?);

    try expectStylesheet("a { b:c {d}; e: f }", &.{
        "qualified [ident(a) ws] decls{} rules{qualified [ident(b) : ident(c) ws] decls{} rules{}; nested-decls{e = [ident(f)]}}",
    });
}

fn expectParseRule(comptime source: []const u8, expected: ?[]const u8) !void {
    var parsed = parser.parseRule(testing.allocator, u(source), .syntax_only) catch |err| switch (err) {
        error.SyntaxError => return testing.expectEqual(null, expected),
        error.OutOfMemory => return err,
    };
    defer parsed.deinit();
    try expectRule(expected orelse return error.TestExpectedSyntaxError, parsed.value);
}

fn expectParseDeclaration(comptime source: []const u8, expected: ?[]const u8) !void {
    var parsed = parser.parseDeclaration(testing.allocator, u(source), .syntax_only) catch |err| switch (err) {
        error.SyntaxError => return testing.expectEqual(null, expected),
        error.OutOfMemory => return err,
    };
    defer parsed.deinit();
    try expectDeclaration(expected orelse return error.TestExpectedSyntaxError, parsed.value);
}

fn expectParseComponentValue(comptime source: []const u8, expected: ?[]const u8) !void {
    var parsed = parser.parseComponentValue(testing.allocator, u(source)) catch |err| switch (err) {
        error.SyntaxError => return testing.expectEqual(null, expected),
        error.OutOfMemory => return err,
    };
    defer parsed.deinit();
    try expectValues(expected orelse return error.TestExpectedSyntaxError, parsed.value);
}

test "FP-0014 case 11: every parser entry point" {
    try expectParseRule("  a{}  ", "qualified [ident(a)] decls{} rules{}");
    try expectParseRule("a{} b{}", null);
    try expectParseRule("", null);
    try expectParseRule("@x;", "@x [] no-block");
    try expectParseRule(" --a:b{} ", null);

    try expectParseDeclaration("a:b", "a = [ident(b)]");
    try expectParseDeclaration("  a : b !IMPORTANT ", "a = [ident(b)] !important");
    try expectParseDeclaration("a b", null);
    try expectParseDeclaration("--x:{y}", "--x = [block({)[ident(y)]]");

    try expectParseComponentValue(" x ", "ident(x)");
    try expectParseComponentValue(" f(a) ", "function(f)[ident(a)]");
    try expectParseComponentValue("x y", null);
    try expectParseComponentValue("", null);

    {
        var parsed = try parser.parseComponentValueList(testing.allocator, u("a, b"));
        defer parsed.deinit();
        try expectValues("ident(a) , ws ident(b)", parsed.value);
    }
    {
        var parsed = try parser.parseCommaSeparatedComponentValues(testing.allocator, u("a, b c,,d"));
        defer parsed.deinit();
        try testing.expectEqual(4, parsed.value.len);
        try expectValues("ident(a)", parsed.value[0]);
        try expectValues("ws ident(b) ws ident(c)", parsed.value[1]);
        try expectValues("", parsed.value[2]);
        try expectValues("ident(d)", parsed.value[3]);
    }
    {
        var parsed = try parser.parseStylesheetContents(testing.allocator, u("<!--a{}"), .syntax_only);
        defer parsed.deinit();
        try testing.expectEqual(1, parsed.value.len);
        try expectRule("qualified [ident(a)] decls{} rules{}", parsed.value[0]);
    }
    {
        var parsed = try parser.parseBlockContents(testing.allocator, u("a:b; @c; d{} e:f"), .syntax_only);
        defer parsed.deinit();
        try testing.expectEqual(4, parsed.value.len);
        try expectBlockItem("decls{a = [ident(b)]}", parsed.value[0]);
        try expectBlockItem("@c [] no-block", parsed.value[1]);
        try expectBlockItem("qualified [ident(d)] decls{} rules{}", parsed.value[2]);
        try expectBlockItem("decls{e = [ident(f)]}", parsed.value[3]);
    }
}

fn expectOnlyDeclaration(comptime source: []const u8, expected: []const u8) !void {
    var parsed = try parser.parseStylesheet(testing.allocator, u(source), .syntax_only);
    defer parsed.deinit();
    try testing.expectEqual(1, parsed.value.len);
    const rule = parsed.value[0].qualified;
    try testing.expectEqual(1, rule.declarations.len);
    try expectDeclaration(expected, rule.declarations[0]);
}

test "FP-0014 case 12: !important is recognized only as the last two non-whitespace tokens" {
    try expectOnlyDeclaration("a{b:c!important}", "b = [ident(c)] !important");
    try expectOnlyDeclaration("a{b:c ! important}", "b = [ident(c)] !important");
    try expectOnlyDeclaration("a{b:c !ImPoRtAnT}", "b = [ident(c)] !important");
    try expectOnlyDeclaration("a{b: !important}", "b = [] !important");
    try expectOnlyDeclaration("a{b:c !important d}", "b = [ident(c) ws delim(!) ident(important) ws ident(d)]");
}

test "FP-0014 case 13: a unicode-range declaration retokenizes its original text" {
    try expectStylesheet("@font-face{unicode-range: U+0-7F, u+4??}", &.{
        "@font-face [] block{decls{unicode-range = [unicode-range(0,7F) , ws unicode-range(400,4FF)]}}",
    });
}

test "FP-0014 case 14: a custom property keeps its tokens and its original text" {
    {
        var parsed = try parser.parseStylesheet(testing.allocator, u("a{--x:  a  /* c */ B !important ;}"), .syntax_only);
        defer parsed.deinit();
        const declaration = parsed.value[0].qualified.declarations[0];
        try expectDeclaration("--x = [ident(a) ws ws ident(B)] !important", declaration);
        try testing.expectEqualSlices(u16, u("a  /* c */ B").units, declaration.original_text.?);
    }
    {
        var parsed = try parser.parseStylesheet(testing.allocator, u("a{--y:;}"), .syntax_only);
        defer parsed.deinit();
        const declaration = parsed.value[0].qualified.declarations[0];
        try expectDeclaration("--y = []", declaration);
        try testing.expectEqual(0, declaration.original_text.?.len);
    }
}

// Stylesheets.

fn parseSheet(comptime source: []const u8, origin: stylesheet.Origin) !Stylesheet {
    return Stylesheet.parse(testing.allocator, u(source), origin);
}

const ExpectedDiagnostic = struct { kind: DiagnosticKind, name: ?[]const u8 = null };

fn expectDiagnostics(sheet: *const Stylesheet, expected: []const ExpectedDiagnostic) !void {
    try testing.expectEqual(expected.len, sheet.diagnostics.len);
    for (expected, sheet.diagnostics) |wanted, actual| {
        try testing.expectEqual(wanted.kind, actual.kind);
        if (wanted.name) |name| {
            const units = try std.unicode.utf8ToUtf16LeAlloc(testing.allocator, name);
            defer testing.allocator.free(units);
            try testing.expectEqualSlices(u16, units, actual.name.?);
        }
    }
}

fn expectSelectorText(sheet: *const Stylesheet, rule: usize, comptime name: []const u8) !void {
    const compound = sheet.rules[rule].selectors.selectors[0].compounds[0];
    try testing.expectEqualSlices(u16, u(name).units, compound.type_selector.?.name.?);
}

test "FP-0014 case 15: unsupported selectors and every at-rule are dropped with diagnostics" {
    {
        var sheet = try parseSheet("a:hover { color: red } b { color: blue }", .author);
        defer sheet.deinit();
        try testing.expectEqual(1, sheet.rules.len);
        try expectSelectorText(&sheet, 0, "b");
        try expectDiagnostics(&sheet, &.{.{ .kind = .unsupported_selector }});
    }
    {
        var sheet = try parseSheet("@charset \"x\"; @import url(a); @media all { b {} } c {}", .author);
        defer sheet.deinit();
        try testing.expectEqual(1, sheet.rules.len);
        try expectSelectorText(&sheet, 0, "c");
        try expectDiagnostics(&sheet, &.{
            .{ .kind = .ignored_at_rule, .name = "charset" },
            .{ .kind = .ignored_at_rule, .name = "import" },
            .{ .kind = .ignored_at_rule, .name = "media" },
        });
    }
}

test "FP-0014 case 16: unknown properties and invalid and unsupported values are dropped in order" {
    var sheet = try parseSheet("p { colour: red; color: 12px; color: hsl(0 0% 0%); COLOR: Blue; font-size: math; --X: 1; --: 2 }", .author);
    defer sheet.deinit();
    try testing.expectEqual(1, sheet.rules.len);
    const declarations = sheet.rules[0].declarations;
    try testing.expectEqual(2, declarations.len);
    try testing.expectEqual(registry.PropertyKey{ .standard = .color }, declarations[0].property);
    try testing.expect(std.meta.eql(values.DeclaredValue{ .color = .{ .srgb = .{ .red = 0, .green = 0, .blue = 255, .alpha = 1 } } }, declarations[0].value));
    try testing.expectEqualSlices(u16, u("--X").units, declarations[1].property.custom);
    try expectValues("number(1,integer,none)", declarations[1].value.custom.tokens);
    try expectDiagnostics(&sheet, &.{
        .{ .kind = .unknown_property, .name = "colour" },
        .{ .kind = .invalid_value, .name = "color" },
        .{ .kind = .unsupported_value, .name = "color" },
        .{ .kind = .unsupported_value, .name = "font-size" },
        .{ .kind = .unknown_property, .name = "--" },
    });
}

test "FP-0014 case 17: nested rules, nested at-rules, and nested declarations are dropped" {
    var sheet = try parseSheet("p { color: red; b { color: blue } margin-top: 1px; @media x { } }", .author);
    defer sheet.deinit();
    try testing.expectEqual(1, sheet.rules.len);
    const declarations = sheet.rules[0].declarations;
    try testing.expectEqual(1, declarations.len);
    try testing.expectEqual(registry.PropertyKey{ .standard = .color }, declarations[0].property);
    try testing.expect(std.meta.eql(values.DeclaredValue{ .color = .{ .srgb = .{ .red = 255, .green = 0, .blue = 0, .alpha = 1 } } }, declarations[0].value));
    try expectDiagnostics(&sheet, &.{
        .{ .kind = .nested_rule_ignored },
        .{ .kind = .ignored_at_rule, .name = "media" },
        .{ .kind = .nested_declarations_ignored },
    });
}

// Selectors.

const SelectorParse = struct {
    arena: std.heap.ArenaAllocator,
    result: selectors.ParseResult,

    fn deinit(p: *SelectorParse) void {
        p.arena.deinit();
    }
};

fn parseSelectors(source: View) !SelectorParse {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    errdefer arena.deinit();
    var parsed = try parser.parseComponentValueList(arena.allocator(), source);
    _ = &parsed;
    const result = try selectors.parseSelectorList(arena.allocator(), parsed.value);
    return .{ .arena = arena, .result = result };
}

fn expectSpecificities(source: View, expected: []const applicable.Specificity) !void {
    var parsed = try parseSelectors(source);
    defer parsed.deinit();
    const list = switch (parsed.result) {
        .list => |list| list,
        .failure => return error.TestUnexpectedSelectorFailure,
    };
    try testing.expectEqual(expected.len, list.selectors.len);
    for (expected, list.selectors) |wanted, selector| try testing.expectEqual(wanted, selector.specificity);
}

test "FP-0014 case 21: selectors parse with their specificity, which saturates at 65535" {
    const cases = [_]struct { sources: []const View, specificity: applicable.Specificity }{
        .{ .sources = &.{ u("*"), u("*|*"), u("|*") }, .specificity = .{} },
        .{ .sources = &.{ u("div"), u("*|div"), u("|div") }, .specificity = .{ .c = 1 } },
        .{ .sources = &.{
            u(".a"),     u("[x]"),    u("[*|x]"),  u("[|x]"),   u("[x=y]"),       u("[x~=y]"),
            u("[x|=y]"), u("[x^=y]"), u("[x$=y]"), u("[x*=y]"), u("[x=\"y\" i]"), u("[ x = 'y' S ]"),
        }, .specificity = .{ .b = 1 } },
        .{ .sources = &.{ u("#a"), u("#x34y") }, .specificity = .{ .a = 1 } },
        .{ .sources = &.{u("div.a#b[x]")}, .specificity = .{ .a = 1, .b = 2, .c = 1 } },
        .{ .sources = &.{u("ul ol + li")}, .specificity = .{ .c = 3 } },
        .{ .sources = &.{u("ul > li ~ li.red")}, .specificity = .{ .b = 1, .c = 3 } },
        .{ .sources = &.{u("H1 + *[REL=up]")}, .specificity = .{ .b = 1, .c = 1 } },
        .{ .sources = &.{u("LI.red.level")}, .specificity = .{ .b = 2, .c = 1 } },
    };
    for (cases) |case| {
        for (case.sources) |source| try expectSpecificities(source, &.{case.specificity});
    }
    try expectSpecificities(u("a , #b"), &.{ .{ .c = 1 }, .{ .a = 1 } });

    const many = try testing.allocator.alloc(u16, 2 * 65536);
    defer testing.allocator.free(many);
    for (0..65536) |index| {
        many[2 * index] = '.';
        many[2 * index + 1] = 'a';
    }
    try expectSpecificities(.{ .units = many }, &.{.{ .b = 65535 }});
}

fn expectSelectorFailure(source: View, kind: selectors.FailureKind) !void {
    var parsed = try parseSelectors(source);
    defer parsed.deinit();
    switch (parsed.result) {
        .list => return error.TestExpectedSelectorFailure,
        .failure => |failure| try testing.expectEqual(kind, failure.kind),
    }
}

test "FP-0014 case 22: invalid and unsupported selectors report the first problem in token order" {
    const invalid = [_]View{
        u(""),    u("a,"),  u(",a"),  u("a,,b"), u("> a"),    u("a >"),       u("a > > b"), u("a ."),
        u(". a"), u("#1a"), u("[]"),  u("[x=]"), u("[x==y]"), u("[x = y z]"), u("[x=y j]"), u("[x=1]"),
        u("[1]"), u("a:"),  u("a!b"), u("a ~"),  u("*|"),     u("|"),
    };
    for (invalid) |source| try expectSelectorFailure(source, .invalid_selector);
    const unsupported = [_]View{ u("a:hover"), u(":root"), u("a::before"), u("a:not(b)"), u("a|b"), u("[ns|x]"), u("&"), u("& a"), u("a||b") };
    for (unsupported) |source| try expectSelectorFailure(source, .unsupported_selector);
    try expectSelectorFailure(u("a:hover, ,b"), .unsupported_selector);
}

/// A document with elements in no namespace unless stated, plus parsed stylesheets and a style map.
const Scenario = struct {
    store: dom.Store,
    document: NodeHandle,
    sheets: [8]Stylesheet = undefined,
    sheet_count: usize = 0,
    map: ?style.StyleMap = null,

    fn init(s: *Scenario) !void {
        s.* = .{ .store = try dom.Store.init(testing.allocator), .document = undefined };
        errdefer s.store.deinit();
        s.document = try s.store.createDocument();
    }

    fn deinit(s: *Scenario) void {
        if (s.map) |*map| map.deinit();
        for (s.sheets[0..s.sheet_count]) |*value| value.deinit();
        s.store.deinit();
    }

    /// Creates an element and appends it to `parent`, or to the document when `parent` is null.
    fn add(s: *Scenario, parent: ?NodeHandle, comptime name: []const u8) !NodeHandle {
        return s.addNs(parent, null, name);
    }

    fn addNs(s: *Scenario, parent: ?NodeHandle, namespace: ?View, comptime name: []const u8) !NodeHandle {
        const element = try s.store.createElement(s.document, namespace, u(name));
        try s.store.appendChild(parent orelse s.document, element);
        return element;
    }

    fn set(s: *Scenario, element: NodeHandle, comptime name: []const u8, comptime value: []const u8) !void {
        try s.store.setAttribute(element, null, u(name), u(value));
    }

    fn sheet(s: *Scenario, source: []const u8, origin: stylesheet.Origin) !*Stylesheet {
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const text = try runtimeView(arena.allocator(), source);
        s.sheets[s.sheet_count] = try Stylesheet.parse(testing.allocator, text, origin);
        s.sheet_count += 1;
        return &s.sheets[s.sheet_count - 1];
    }

    fn resolve(s: *Scenario) !*style.StyleMap {
        var pointers: [8]*const Stylesheet = undefined;
        for (s.sheets[0..s.sheet_count], 0..) |*sheet_value, index| pointers[index] = sheet_value;
        if (s.map) |*map| map.deinit();
        s.map = null;
        s.map = try style.resolve(testing.allocator, &s.store, s.document, pointers[0..s.sheet_count]);
        return &s.map.?;
    }

    fn get(s: *Scenario, element: NodeHandle) !*const ComputedStyle {
        return s.map.?.get(element);
    }
};

/// The case 23 fixture.
const Fixture23 = struct {
    root: NodeHandle,
    div: NodeHandle,
    p1: NodeHandle,
    p2: NodeHandle,
    span: NodeHandle,
    section: NodeHandle,
    p3: NodeHandle,

    fn build(s: *Scenario) !Fixture23 {
        var f: Fixture23 = undefined;
        f.root = try s.add(null, "root");
        f.div = try s.add(f.root, "div");
        try s.set(f.div, "id", "main");
        try s.set(f.div, "class", " box  big ");
        f.section = try s.add(f.root, "section");
        f.p1 = try s.add(f.div, "p");
        try s.set(f.p1, "class", "a");
        try s.set(f.p1, "lang", "en-US");
        try s.set(f.p1, "data-x", "hello world");
        try s.store.appendChild(f.div, try s.store.createText(s.document, u("t")));
        try s.store.appendChild(f.div, try s.store.createComment(s.document, u("c")));
        f.p2 = try s.add(f.div, "p");
        try s.set(f.p2, "class", "b");
        try s.set(f.p2, "title", "Hello");
        f.span = try s.addNs(f.div, u("urn:x"), "span");
        try s.store.setAttribute(f.span, u("urn:y"), u("lang"), u("fr"));
        f.p3 = try s.add(f.section, "p");
        try s.set(f.p3, "id", "last");
        return f;
    }

    fn treeOrder(f: Fixture23) [7]NodeHandle {
        return .{ f.root, f.div, f.p1, f.p2, f.span, f.section, f.p3 };
    }
};

fn expectMatches(s: *Scenario, source: View, candidates: []const NodeHandle, expected: []const NodeHandle) !void {
    var parsed = try parseSelectors(source);
    defer parsed.deinit();
    const list = switch (parsed.result) {
        .list => |list| list,
        .failure => return error.TestUnexpectedSelectorFailure,
    };
    var matcher: selectors.Matcher = .init(testing.allocator, &s.store);
    defer matcher.deinit();
    var matched: [8]NodeHandle = undefined;
    var count: usize = 0;
    for (candidates) |candidate| {
        if (try matcher.matchList(candidate, &list) != null) {
            matched[count] = candidate;
            count += 1;
        }
    }
    try testing.expectEqual(expected.len, count);
    for (expected, matched[0..count]) |wanted, actual| try testing.expect(std.meta.eql(wanted, actual));
}

test "FP-0014 case 23: selectors match the fixture document exactly, in tree order" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const f = try Fixture23.build(&s);
    const all = f.treeOrder();
    const none: []const NodeHandle = &.{};
    const cases = [_]struct { sources: []const View, expected: []const NodeHandle }{
        .{ .sources = &.{u("p")}, .expected = &.{ f.p1, f.p2, f.p3 } },
        .{ .sources = &.{u("*")}, .expected = &.{ f.root, f.div, f.p1, f.p2, f.span, f.section, f.p3 } },
        .{ .sources = &.{ u("span"), u("*|span") }, .expected = &.{f.span} },
        .{ .sources = &.{u("|span")}, .expected = none },
        .{ .sources = &.{u("|p")}, .expected = &.{ f.p1, f.p2, f.p3 } },
        .{ .sources = &.{ u(".box"), u(".big.box"), u("#main"), u("[class~=big]") }, .expected = &.{f.div} },
        .{ .sources = &.{ u(".Box"), u("#MAIN"), u("[class=box]") }, .expected = none },
        .{ .sources = &.{ u("#last"), u("section > #last"), u("section p") }, .expected = &.{f.p3} },
        .{ .sources = &.{ u("[lang]"), u("[|lang]"), u("[lang=en-US]"), u("[lang|=en]") }, .expected = &.{f.p1} },
        .{ .sources = &.{u("[*|lang]")}, .expected = &.{ f.p1, f.span } },
        .{ .sources = &.{u("[lang|=en-U]")}, .expected = none },
        .{ .sources = &.{ u("[data-x~=world]"), u("[data-x^=hel]"), u("[data-x$=rld]"), u("[data-x*=\"o w\"]") }, .expected = &.{f.p1} },
        .{ .sources = &.{ u("[data-x~=\"hello world\"]"), u("[data-x~=\"\"]"), u("[data-x^=\"\"]"), u("[data-x*=\"\"]") }, .expected = none },
        .{ .sources = &.{ u("[title=hello i]"), u("[title=Hello s]"), u("[title=HELLO I]") }, .expected = &.{f.p2} },
        .{ .sources = &.{ u("[title=hello]"), u("[title=hello s]") }, .expected = none },
        .{ .sources = &.{ u("div > p"), u("root div p") }, .expected = &.{ f.p1, f.p2 } },
        .{ .sources = &.{ u("root > p"), u("div ~ p") }, .expected = none },
        .{ .sources = &.{u("root p")}, .expected = &.{ f.p1, f.p2, f.p3 } },
        .{ .sources = &.{ u("p + p"), u("root > * > p.b"), u("#nothing, .b") }, .expected = &.{f.p2} },
        .{ .sources = &.{ u("p ~ span"), u("div p ~ span") }, .expected = &.{f.span} },
        .{ .sources = &.{u("p.a ~ *")}, .expected = &.{ f.p2, f.span } },
        .{ .sources = &.{u("div + section")}, .expected = &.{f.section} },
        .{ .sources = &.{u(".a, .b")}, .expected = &.{ f.p1, f.p2 } },
    };
    for (cases) |case| {
        for (case.sources) |source| try expectMatches(&s, source, &all, case.expected);
    }
}

test "FP-0014 case 24: a detached element matches by its own compound and not through absent ancestors" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    _ = try s.add(null, "root");
    const detached = try s.store.createElement(s.document, null, u("p"));
    try expectMatches(&s, u("p"), &.{detached}, &.{detached});
    try expectMatches(&s, u("root p"), &.{detached}, &.{});
}

// Registry.

test "FP-0014 case 25: the registry holds exactly the frozen properties, and lookup follows the name rules" {
    const expected = [_]struct {
        name: []const u8,
        initial: []const u8,
        inherited: bool,
        computed: registry.Representation,
        invalidation: []const registry.Invalidation,
    }{
        .{ .name = "display", .initial = "inline", .inherited = false, .computed = .display, .invalidation = &.{ .box_tree, .layout, .paint } },
        .{ .name = "color", .initial = "CanvasText", .inherited = true, .computed = .color, .invalidation = &.{ .paint, .element_dependents } },
        .{ .name = "font-size", .initial = "medium", .inherited = true, .computed = .pixels, .invalidation = &.{ .layout, .paint, .element_dependents, .root_dependents } },
        .{ .name = "margin-top", .initial = "0", .inherited = false, .computed = .length_percentage_auto, .invalidation = &.{ .layout, .paint } },
        .{ .name = "margin-right", .initial = "0", .inherited = false, .computed = .length_percentage_auto, .invalidation = &.{ .layout, .paint } },
        .{ .name = "margin-bottom", .initial = "0", .inherited = false, .computed = .length_percentage_auto, .invalidation = &.{ .layout, .paint } },
        .{ .name = "margin-left", .initial = "0", .inherited = false, .computed = .length_percentage_auto, .invalidation = &.{ .layout, .paint } },
    };
    try testing.expectEqual(expected.len, registry.records.len);
    for (expected, registry.records) |wanted, record| {
        try testing.expectEqualStrings(wanted.name, record.name);
        try testing.expectEqualStrings(wanted.initial, record.initial);
        try testing.expectEqual(wanted.inherited, record.inherited);
        try testing.expectEqual(wanted.computed, record.computed);
        try testing.expectEqualSlices(registry.Invalidation, wanted.invalidation, record.invalidation);
    }
    try testing.expectEqualStrings("guaranteed-invalid", registry.custom_family.initial);
    try testing.expect(registry.custom_family.inherited);
    try testing.expectEqual(registry.Representation.custom_value, registry.custom_family.computed);
    try testing.expectEqualSlices(registry.Invalidation, &.{.element_dependents}, registry.custom_family.invalidation);

    try testing.expectEqual(registry.PropertyKey{ .standard = .color }, registry.lookup(u("COLOR")).?);
    const upper = registry.lookup(u("--X")).?;
    try testing.expectEqualSlices(u16, u("--X").units, upper.custom);
    const lower = registry.lookup(u("--x")).?;
    try testing.expect(!lower.eql(upper));
    try testing.expectEqual(null, registry.lookup(u("--")));
    try testing.expectEqual(null, registry.lookup(u("colour")));
    try testing.expectEqual(null, registry.lookup(u("margin")));
}

test "FP-0014 case 26: registry validation rejects malformed tables and accepts the committed table" {
    const record = registry.records[0];
    var duplicate = [_]registry.Record{ record, record };
    try testing.expectError(error.DuplicateProperty, registry.validate(&duplicate));
    var non_canonical = [_]registry.Record{record};
    non_canonical[0].name = "Display";
    try testing.expectError(error.NonCanonicalName, registry.validate(&non_canonical));
    var missing = [_]registry.Record{record};
    missing[0].invalidation = &.{};
    try testing.expectError(error.MissingInvalidation, registry.validate(&missing));
    try registry.validate(registry.records);
}

fn expectRgba(color: values.Color, red: ?f64, green: ?f64, blue: ?f64, alpha: ?f64) !void {
    const rgba = switch (color) {
        .srgb => |rgba| rgba,
        .current_color => return error.TestExpectedSrgb,
    };
    try testing.expectEqual(red, rgba.red);
    try testing.expectEqual(green, rgba.green);
    try testing.expectEqual(blue, rgba.blue);
    try testing.expectEqual(alpha, rgba.alpha);
}

fn pair(outer: values.Outer, inner: values.Inner, list_item: bool) values.Display {
    return .{ .pair = .{ .outer = outer, .inner = inner, .list_item = list_item } };
}

test "FP-0014 case 27: initial texts parse with their grammars, and an undeclared child computes initial values" {
    inline for (comptime std.enums.values(registry.PropertyId)) |id| {
        var parsed = try parser.parseComponentValueList(testing.allocator, u(registry.record(id).initial));
        defer parsed.deinit();
        const outcome = values.parseStandard(id, parsed.value);
        try testing.expect(outcome == .value);
        try testing.expect(std.meta.eql(values.initialValue(id), outcome.value));
    }

    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const child = try s.add(root, "c");
    _ = try s.resolve();
    const computed = try s.get(child);
    try testing.expect(std.meta.eql(pair(.@"inline", .flow, false), computed.display));
    try expectRgba(computed.color, 0, 0, 0, 1);
    try testing.expectEqual(16, computed.font_size);
    inline for (.{ "margin_top", "margin_right", "margin_bottom", "margin_left" }) |field| {
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, @field(computed, field));
    }
    try testing.expectEqual(0, computed.custom.len);
    try testing.expectEqual(values.CustomValue.guaranteed_invalid, computed.customValue(u("--anything").units));
}

fn effects(list: []const registry.Invalidation) registry.Effects {
    var set: registry.Effects = .empty;
    for (list) |effect| set.insert(effect);
    return set;
}

test "FP-0014 case 28: diff reports the invalidation effects of each changed property" {
    const base = ComputedStyle.initial();
    var changed = base;
    changed.display = pair(.block, .flow, false);
    try testing.expectEqual(effects(&.{ .box_tree, .layout, .paint }), base.diff(&changed));
    changed = base;
    changed.color = .{ .srgb = .{ .red = 1, .green = 0, .blue = 0, .alpha = 1 } };
    try testing.expectEqual(effects(&.{ .paint, .element_dependents, .descendants }), base.diff(&changed));
    changed = base;
    changed.font_size = 20;
    try testing.expectEqual(effects(&.{ .layout, .paint, .element_dependents, .root_dependents, .descendants }), base.diff(&changed));
    changed = base;
    changed.margin_top = .{ .length = 1 };
    try testing.expectEqual(effects(&.{ .layout, .paint }), base.diff(&changed));

    var parsed = try parser.parseComponentValueList(testing.allocator, u("v"));
    defer parsed.deinit();
    const entries = [_]compute.CustomEntry{.{ .name = u("--x").units, .value = parsed.value }};
    changed = base;
    changed.custom = &entries;
    try testing.expectEqual(effects(&.{ .element_dependents, .descendants }), base.diff(&changed));
    try testing.expectEqual(registry.Effects.empty, base.diff(&base));
}

// Computed values.

/// What one resolution observed for its target element.
const Observed = struct {
    style: ComputedStyle,
    sheet_diagnostics: [8]DiagnosticKind = undefined,
    sheet_diagnostic_count: usize = 0,
    reasons: [8]InvalidReason = undefined,
    reason_count: usize = 0,

    fn expectSheetDiagnostics(o: *const Observed, expected: []const DiagnosticKind) !void {
        try testing.expectEqualSlices(DiagnosticKind, expected, o.sheet_diagnostics[0..o.sheet_diagnostic_count]);
    }

    fn expectReasons(o: *const Observed, expected: []const InvalidReason) !void {
        try testing.expectEqualSlices(InvalidReason, expected, o.reasons[0..o.reason_count]);
    }
};

/// Resolves `rules` over the chain `r`, `r > p`, or `r > p > c`, with `depth` 0, 1, or 2, and observes the last element.
/// The observed style's custom values are not kept.
fn observe(rules: []const u8, depth: usize) !Observed {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    var target = try s.add(null, "r");
    if (depth >= 1) target = try s.add(target, "p");
    if (depth >= 2) target = try s.add(target, "c");
    const sheet = try s.sheet(rules, .author);
    const map = try s.resolve();
    var observed: Observed = .{ .style = (try map.get(target)).* };
    observed.style.custom = &.{};
    for (sheet.diagnostics) |diagnostic| {
        observed.sheet_diagnostics[observed.sheet_diagnostic_count] = diagnostic.kind;
        observed.sheet_diagnostic_count += 1;
    }
    for (map.diagnostics) |diagnostic| {
        if (!std.meta.eql(diagnostic.element, target)) continue;
        observed.reasons[observed.reason_count] = diagnostic.reason;
        observed.reason_count += 1;
    }
    return observed;
}

fn observeProperty(comptime selector: []const u8, comptime property: []const u8, value: []const u8, depth: usize) !Observed {
    var buffer: [256]u8 = undefined;
    const rules = try std.fmt.bufPrint(&buffer, selector ++ " {{ " ++ property ++ ": {s} }}", .{value});
    return observe(rules, depth);
}

test "FP-0014 case 29: display values compute, blockify on the root, and reject invalid and unsupported forms" {
    const computed = [_]struct { value: []const u8, display: values.Display }{
        .{ .value = "block", .display = pair(.block, .flow, false) },
        .{ .value = "inline", .display = pair(.@"inline", .flow, false) },
        .{ .value = "run-in", .display = pair(.run_in, .flow, false) },
        .{ .value = "flow", .display = pair(.block, .flow, false) },
        .{ .value = "flow-root", .display = pair(.block, .flow_root, false) },
        .{ .value = "table", .display = pair(.block, .table, false) },
        .{ .value = "inline table", .display = pair(.@"inline", .table, false) },
        .{ .value = "table inline", .display = pair(.@"inline", .table, false) },
        .{ .value = "block flow-root", .display = pair(.block, .flow_root, false) },
        .{ .value = "list-item", .display = pair(.block, .flow, true) },
        .{ .value = "inline list-item", .display = pair(.@"inline", .flow, true) },
        .{ .value = "list-item flow-root inline", .display = pair(.@"inline", .flow_root, true) },
        .{ .value = "inline-block", .display = pair(.@"inline", .flow_root, false) },
        .{ .value = "inline-table", .display = pair(.@"inline", .table, false) },
        .{ .value = "table-cell", .display = .{ .internal = .table_cell } },
        .{ .value = "none", .display = .none },
        .{ .value = "contents", .display = .contents },
    };
    for (computed) |case| {
        const observed = try observeProperty("p", "display", case.value, 1);
        try observed.expectSheetDiagnostics(&.{});
        try testing.expect(std.meta.eql(case.display, observed.style.display));
    }
    for ([_][]const u8{ "block block", "list-item list-item", "table list-item", "inline-block list-item", "foo", "block,inline" }) |value| {
        const observed = try observeProperty("p", "display", value, 1);
        try observed.expectSheetDiagnostics(&.{.invalid_value});
    }
    for ([_][]const u8{ "flex", "inline-grid", "block ruby", "ruby-text" }) |value| {
        const observed = try observeProperty("p", "display", value, 1);
        try observed.expectSheetDiagnostics(&.{.unsupported_value});
    }
    const root_cases = [_]struct { value: []const u8, display: values.Display }{
        .{ .value = "inline", .display = pair(.block, .flow, false) },
        .{ .value = "inline-block", .display = pair(.block, .flow, false) },
        .{ .value = "run-in flow-root", .display = pair(.block, .flow, false) },
        .{ .value = "table-cell", .display = pair(.block, .flow, false) },
        .{ .value = "contents", .display = pair(.block, .flow, false) },
        .{ .value = "inline list-item", .display = pair(.block, .flow, true) },
        .{ .value = "inline table", .display = pair(.block, .table, false) },
        .{ .value = "none", .display = .none },
    };
    for (root_cases) |case| {
        const observed = try observeProperty("r", "display", case.value, 0);
        try testing.expect(std.meta.eql(case.display, observed.style.display));
    }
}

test "FP-0014 case 30: hex, named, system, transparent, and currentcolor values compute" {
    const cases = [_]struct { value: []const u8, rgba: [4]f64 }{
        .{ .value = "#FFF", .rgba = .{ 255, 255, 255, 1 } },
        .{ .value = "#0000ffcc", .rgba = .{ 0, 0, 255, 204.0 / 255.0 } },
        .{ .value = "#1234", .rgba = .{ 17, 34, 51, 68.0 / 255.0 } },
        .{ .value = "#AbCdEf", .rgba = .{ 171, 205, 239, 1 } },
        .{ .value = "RebeccaPurple", .rgba = .{ 102, 51, 153, 1 } },
        .{ .value = "transparent", .rgba = .{ 0, 0, 0, 0 } },
        .{ .value = "CanvasText", .rgba = .{ 0, 0, 0, 1 } },
        .{ .value = "canvas", .rgba = .{ 255, 255, 255, 1 } },
        .{ .value = "InfoText", .rgba = .{ 0, 0, 0, 1 } },
        .{ .value = "ButtonHighlight", .rgba = .{ 239, 239, 239, 1 } },
    };
    for (cases) |case| {
        const observed = try observeProperty("p", "color", case.value, 1);
        try observed.expectSheetDiagnostics(&.{});
        try expectRgba(observed.style.color, case.rgba[0], case.rgba[1], case.rgba[2], case.rgba[3]);
    }
    const current = try observeProperty("p", "color", "currentColor", 1);
    try testing.expectEqual(values.Color.current_color, current.style.color);

    // `named_colors.zig` holds 148 rows in ascending name order, and the color lookup reads that table.
    const rows = &@import("named_colors.zig").rows;
    try testing.expectEqual(148, rows.len);
    try testing.expectEqual(@intFromPtr(rows), @intFromPtr(values.named_colors.ptr));
    for (rows[1..], 0..) |row, index| {
        try testing.expectEqual(std.math.Order.lt, std.mem.order(u8, rows[index].name, row.name));
    }
    for ([_]struct { name: View, rgb: [3]u8 }{
        .{ .name = u("aliceblue"), .rgb = .{ 240, 248, 255 } },
        .{ .name = u("darkgray"), .rgb = .{ 169, 169, 169 } },
        .{ .name = u("grey"), .rgb = .{ 128, 128, 128 } },
        .{ .name = u("rebeccapurple"), .rgb = .{ 102, 51, 153 } },
        .{ .name = u("yellowgreen"), .rgb = .{ 154, 205, 50 } },
    }) |case| {
        const row = values.namedColor(case.name.units).?;
        try testing.expectEqual(case.rgb, [3]u8{ row.red, row.green, row.blue });
    }
    for ([_][]const u8{ "#12345", "#ggg", "#1234567", "blurple", "red blue", "rgb", "currentcolor red" }) |value| {
        const observed = try observeProperty("p", "color", value, 1);
        try observed.expectSheetDiagnostics(&.{.invalid_value});
    }
}

test "FP-0014 case 31: rgb() and rgba() parse in the legacy and modern syntaxes and clamp at parse time" {
    const cases = [_]struct { value: []const u8, rgba: [4]?f64 }{
        .{ .value = "rgb(255, 0, 0)", .rgba = .{ 255, 0, 0, 1 } },
        .{ .value = "rgba(255,0,0,0.5)", .rgba = .{ 255, 0, 0, 0.5 } },
        .{ .value = "rgb(255 0 0 / 50%)", .rgba = .{ 255, 0, 0, 0.5 } },
        .{ .value = "rgb(100% 50% 0%)", .rgba = .{ 255, 127.5, 0, 1 } },
        .{ .value = "rgb(10% 20 30)", .rgba = .{ 25.5, 20, 30, 1 } },
        .{ .value = "rgb(300 -5 0)", .rgba = .{ 255, 0, 0, 1 } },
        .{ .value = "rgb(0 0 0 / 2)", .rgba = .{ 0, 0, 0, 1 } },
        .{ .value = "rgb(none 0 0)", .rgba = .{ null, 0, 0, 1 } },
        .{ .value = "rgb(0 0 0 / none)", .rgba = .{ 0, 0, 0, null } },
        .{ .value = "rgba(1 2 3)", .rgba = .{ 1, 2, 3, 1 } },
        .{ .value = "RGB(1,2,3)", .rgba = .{ 1, 2, 3, 1 } },
        .{ .value = "rgb(1.5, 2, 3)", .rgba = .{ 1.5, 2, 3, 1 } },
    };
    for (cases) |case| {
        const observed = try observeProperty("p", "color", case.value, 1);
        try observed.expectSheetDiagnostics(&.{});
        try expectRgba(observed.style.color, case.rgba[0], case.rgba[1], case.rgba[2], case.rgba[3]);
    }
    for ([_][]const u8{ "rgb(1, 2)", "rgb(1 2)", "rgb(1, 2, none)", "rgb(10%, 20, 30)", "rgb(1, 2, 3,)", "rgb(1 2 3 4)", "rgb(1 2 3 /)", "rgb(1px 2 3)" }) |value| {
        const observed = try observeProperty("p", "color", value, 1);
        try observed.expectSheetDiagnostics(&.{.invalid_value});
    }
    for ([_][]const u8{ "hsl(0 0% 0%)", "rgb(calc(1) 2 3)", "lab(50% 0 0)", "color-mix(in srgb, red, blue)", "rgb(from red r g b)" }) |value| {
        const observed = try observeProperty("p", "color", value, 1);
        try observed.expectSheetDiagnostics(&.{.unsupported_value});
    }
}

/// Types a literal as `f64`, so an expected expression is evaluated in `f64` from left to right, as the engine evaluates it,
/// instead of as an exact comptime float.
fn f64Of(value: f64) f64 {
    return value;
}

fn observeFontSize(value: []const u8) !Observed {
    var buffer: [256]u8 = undefined;
    return observe(try std.fmt.bufPrint(&buffer, "p {{ font-size: 20px }} c {{ font-size: {s} }}", .{value}), 2);
}

test "FP-0014 case 32: font-size keywords, lengths, and percentages compute against the parent and the root" {
    const cases = [_]struct { value: []const u8, pixels: f64 }{
        .{ .value = "2em", .pixels = 40 },
        .{ .value = "50%", .pixels = 10 },
        .{ .value = "larger", .pixels = f64Of(20.0) * 1.2 },
        .{ .value = "smaller", .pixels = f64Of(20.0) / 1.2 },
        .{ .value = "1rem", .pixels = 16 },
        .{ .value = "xx-small", .pixels = f64Of(16.0) * 3.0 / 5.0 },
        .{ .value = "x-small", .pixels = 12 },
        .{ .value = "small", .pixels = f64Of(16.0) * 8.0 / 9.0 },
        .{ .value = "medium", .pixels = 16 },
        .{ .value = "large", .pixels = f64Of(16.0) * 6.0 / 5.0 },
        .{ .value = "x-large", .pixels = 24 },
        .{ .value = "xx-large", .pixels = 32 },
        .{ .value = "xxx-large", .pixels = 48 },
        .{ .value = "12pt", .pixels = f64Of(12.0) * 96.0 / 72.0 },
        .{ .value = "1in", .pixels = 96 },
        .{ .value = "2.54cm", .pixels = f64Of(2.54) * 96.0 / 2.54 },
        .{ .value = "10mm", .pixels = f64Of(10.0) * 96.0 / 25.4 },
        .{ .value = "40Q", .pixels = f64Of(40.0) * 96.0 / 101.6 },
        .{ .value = "1pc", .pixels = f64Of(96.0) / 6.0 },
        .{ .value = "0", .pixels = 0 },
        .{ .value = "0.5PX", .pixels = 0.5 },
    };
    for (cases) |case| {
        const observed = try observeFontSize(case.value);
        try observed.expectSheetDiagnostics(&.{});
        try testing.expectEqual(case.pixels, observed.style.font_size);
    }
    for ([_][]const u8{ "-1px", "5", "-10%", "1foo", "auto" }) |value| {
        const observed = try observeFontSize(value);
        try observed.expectSheetDiagnostics(&.{.invalid_value});
        try testing.expectEqual(20, observed.style.font_size);
    }
    for ([_][]const u8{ "math", "1ex", "1vw", "1dvmin", "1cqw", "calc(1px)" }) |value| {
        const observed = try observeFontSize(value);
        try observed.expectSheetDiagnostics(&.{.unsupported_value});
        try testing.expectEqual(20, observed.style.font_size);
    }
    for ([_]struct { value: []const u8, pixels: f64 }{
        .{ .value = "2em", .pixels = 32 },
        .{ .value = "2rem", .pixels = 32 },
        .{ .value = "50%", .pixels = 8 },
    }) |case| {
        const observed = try observeProperty("r", "font-size", case.value, 0);
        try testing.expectEqual(case.pixels, observed.style.font_size);
    }
}

fn observeMargins(comptime declarations: []const u8) !Observed {
    return observe("r { font-size: 10px } p { font-size: 20px; " ++ declarations ++ " }", 1);
}

test "FP-0014 case 33: margins compute lengths against the element's font size and the root's" {
    {
        const observed = try observeMargins("margin-top: 10px; margin-right: 5%; margin-bottom: auto; margin-left: -2em");
        try observed.expectSheetDiagnostics(&.{});
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 10 }, observed.style.margin_top);
        try testing.expectEqual(values.LengthPercentageAuto{ .percentage = 5 }, observed.style.margin_right);
        try testing.expectEqual(values.LengthPercentageAuto.auto, observed.style.margin_bottom);
        try testing.expectEqual(values.LengthPercentageAuto{ .length = -40 }, observed.style.margin_left);
    }
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 10 }, (try observeMargins("margin-top: 1rem")).style.margin_top);
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, (try observeMargins("margin-top: 0")).style.margin_top);
    inline for (.{ .{ "margin-top: 1", DiagnosticKind.invalid_value }, .{ "margin-top: 10px 5px", DiagnosticKind.invalid_value }, .{ "margin-top: 1ch", DiagnosticKind.unsupported_value }, .{ "margin-top: calc(1px)", DiagnosticKind.unsupported_value } }) |case| {
        const observed = try observeMargins(case[0]);
        try observed.expectSheetDiagnostics(&.{case[1]});
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, observed.style.margin_top);
    }
    {
        const observed = try observeMargins("margin-top: 3px; margin-top: 1");
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 3 }, observed.style.margin_top);
    }
}

test "FP-0014 case 34: inheritance reaches descendants and text nodes, and unconnected nodes are not styled" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const div = try s.add(root, "div");
    const p = try s.add(div, "p");
    const text = try s.store.createText(s.document, u("text"));
    try s.store.appendChild(div, text);
    // Unconnected elements: a detached subtree, an element in a fragment, and an element of another document.
    const detached = try s.store.createElement(s.document, null, u("d"));
    const detached_child = try s.store.createElement(s.document, null, u("e"));
    try s.store.appendChild(detached, detached_child);
    const fragment = try s.store.createDocumentFragment(s.document);
    const in_fragment = try s.store.createElement(s.document, null, u("f"));
    try s.store.appendChild(fragment, in_fragment);
    const other_document = try s.store.createDocument();
    const other_root = try s.store.createElement(other_document, null, u("r"));
    try s.store.appendChild(other_document, other_root);
    _ = try s.sheet("r { color: rgb(1 2 3); font-size: 20px; margin-top: 5px; display: block; --k: v }", .author);
    const map = try s.resolve();
    const text_style = try map.textStyle(text);
    for ([_]*const ComputedStyle{ try map.get(div), try map.get(p), &text_style }) |computed| {
        try expectRgba(computed.color, 1, 2, 3, 1);
        try testing.expectEqual(20, computed.font_size);
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, computed.margin_top);
        try testing.expect(std.meta.eql(pair(.@"inline", .flow, false), computed.display));
        try expectValues("ident(v)", computed.customValue(u("--k").units).tokens);
    }
    for ([_]NodeHandle{ detached, detached_child, in_fragment, other_root }) |node| {
        try testing.expectError(error.NotStyled, map.get(node));
    }
    const detached_text = try s.store.createText(s.document, u("loose"));
    try testing.expectError(error.NotStyled, map.textStyle(detached_text));

    var bare: Scenario = undefined;
    try bare.init();
    defer bare.deinit();
    const bare_root = try bare.add(null, "r");
    _ = try bare.resolve();
    try testing.expect(std.meta.eql(pair(.block, .flow, false), (try bare.get(bare_root)).display));
}

// Cascade.

fn levelSheets(s: *Scenario, k: usize) !void {
    var author: std.ArrayList(u8) = .empty;
    defer author.deinit(testing.allocator);
    var user: std.ArrayList(u8) = .empty;
    defer user.deinit(testing.allocator);
    var agent: std.ArrayList(u8) = .empty;
    defer agent.deinit(testing.allocator);
    for (1..k + 1) |level| {
        const target = switch (level) {
            1, 6 => &agent,
            2, 5 => &user,
            else => &author,
        };
        const selector = if (level <= 3) "#p" else "p";
        const important = if (level >= 4) " !important" else "";
        try target.print(testing.allocator, "{s} {{ color: rgb({d} 0 0){s} }} ", .{ selector, level, important });
    }
    _ = try s.sheet(author.items, .author);
    _ = try s.sheet(user.items, .user);
    _ = try s.sheet(agent.items, .user_agent);
}

test "FP-0014 case 35: origin and importance decide before specificity, in the six-level order" {
    for (1..7) |k| {
        var s: Scenario = undefined;
        try s.init();
        defer s.deinit();
        const root = try s.add(null, "r");
        const p = try s.add(root, "p");
        try s.set(p, "id", "p");
        try levelSheets(&s, k);
        _ = try s.resolve();
        try expectRgba((try s.get(p)).color, @floatFromInt(k), 0, 0, 1);
    }
}

/// Resolves the author sheets over `r > p` with `id` and `class` set as given, and returns p's color.
fn colorWith(comptime id: ?[]const u8, comptime class: ?[]const u8, sheets: []const []const u8) !values.Color {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const p = try s.add(root, "p");
    if (id) |value| try s.set(p, "id", value);
    if (class) |value| try s.set(p, "class", value);
    for (sheets) |source| _ = try s.sheet(source, .author);
    _ = try s.resolve();
    return (try s.get(p)).color;
}

test "FP-0014 case 36: specificity, then order of appearance, decide within an origin" {
    try expectRgba(try colorWith("a", "b", &.{"#a { color: rgb(1 0 0) } p.b { color: rgb(2 0 0) } p { color: rgb(3 0 0) }"}), 1, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{".b { color: rgb(1 0 0) } .b { color: rgb(2 0 0) }"}), 2, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{ ".b { color: rgb(1 0 0) }", ".b { color: rgb(2 0 0) }" }), 2, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{ ".b { color: rgb(2 0 0) }", ".b { color: rgb(1 0 0) }" }), 1, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{".b { color: rgb(1 0 0); color: rgb(2 0 0) }"}), 2, 0, 0, 1);
    try expectRgba(try colorWith(null, "b", &.{"#x, p { color: rgb(1 0 0) } .b { color: rgb(2 0 0) }"}), 2, 0, 0, 1);
    try expectRgba(try colorWith("x", "b", &.{"#x, p { color: rgb(1 0 0) } .b { color: rgb(2 0 0) }"}), 1, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{".b { color: rgb(1 0 0) } .b { color: nonsense }"}), 1, 0, 0, 1);
    try expectRgba(try colorWith("a", "b", &.{".b { color: rgb(1 0 0); color: hsl(0 0% 0%) }"}), 1, 0, 0, 1);
}

test "FP-0014 case 37: initial, inherit, and unset follow explicit defaulting" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const div = try s.add(root, "div");
    const p = try s.add(div, "p");
    _ = try s.sheet("r { color: rgb(10 0 0); margin-top: 5px } div { color: initial; margin-top: inherit } p { color: unset; margin-top: unset }", .author);
    _ = try s.resolve();
    const div_style = try s.get(div);
    try expectRgba(div_style.color, 0, 0, 0, 1);
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 5 }, div_style.margin_top);
    const p_style = try s.get(p);
    try expectRgba(p_style.color, 0, 0, 0, 1);
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, p_style.margin_top);
}

const Sheet = struct { source: []const u8, origin: stylesheet.Origin };

fn rollbackStyle(sheets: []const Sheet) !ComputedStyle {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const p = try s.add(root, "p");
    try s.set(p, "class", "b");
    try s.set(p, "id", "i");
    _ = try s.sheet("r { color: rgb(1 2 3) }", .author);
    for (sheets) |sheet| _ = try s.sheet(sheet.source, sheet.origin);
    _ = try s.resolve();
    var computed = (try s.get(p)).*;
    computed.custom = &.{};
    return computed;
}

test "FP-0014 case 38: revert, revert-layer, and revert-rule roll back the cascade" {
    const rows = [_]struct { sheets: []const Sheet, rgb: [3]f64 }{
        .{ .sheets = &.{ .{ .source = "p{color:rgb(0 0 20)}", .origin = .user }, .{ .source = "p{color:revert}", .origin = .author } }, .rgb = .{ 0, 0, 20 } },
        .{ .sheets = &.{ .{ .source = "p{color:rgb(0 20 0)}", .origin = .user_agent }, .{ .source = "p{color:revert}", .origin = .user } }, .rgb = .{ 0, 20, 0 } },
        .{ .sheets = &.{.{ .source = "p{color:revert}", .origin = .user_agent }}, .rgb = .{ 1, 2, 3 } },
        .{ .sheets = &.{ .{ .source = "p{color:rgb(0 0 20)}", .origin = .user }, .{ .source = "p{color:revert-layer}", .origin = .author } }, .rgb = .{ 0, 0, 20 } },
        .{ .sheets = &.{.{ .source = "p{color:rgb(1 0 0)} .b{color:revert-rule}", .origin = .author }}, .rgb = .{ 1, 0, 0 } },
        .{ .sheets = &.{ .{ .source = "p{color:rgb(0 0 20)}", .origin = .user }, .{ .source = ".b{color:revert-rule}", .origin = .author } }, .rgb = .{ 0, 0, 20 } },
        .{ .sheets = &.{.{ .source = "p{color:rgb(1 0 0)} .b{color:revert-rule} #i{color:revert-rule}", .origin = .author }}, .rgb = .{ 1, 0, 0 } },
        .{ .sheets = &.{ .{ .source = "p{color:rgb(0 0 20)}", .origin = .user }, .{ .source = "p{color:revert !important}", .origin = .author } }, .rgb = .{ 0, 0, 20 } },
        .{ .sheets = &.{.{ .source = "p{color:rgb(1 0 0); color:revert-rule}", .origin = .author }}, .rgb = .{ 1, 2, 3 } },
    };
    for (rows) |row| {
        const computed = try rollbackStyle(row.sheets);
        try expectRgba(computed.color, row.rgb[0], row.rgb[1], row.rgb[2], 1);
    }
    const margin = try rollbackStyle(&.{.{ .source = "p{margin-top:revert}", .origin = .user_agent }});
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, margin.margin_top);
}

// Custom properties.

/// Checks a custom property's computed value in the contract's notation: `[ITEMS]`, or null for the guaranteed-invalid value.
fn expectCustom(computed: *const ComputedStyle, comptime name: []const u8, expected: ?[]const u8) !void {
    switch (computed.customValue(u(name).units)) {
        .guaranteed_invalid => if (expected != null) return error.TestExpectedTokens,
        .tokens => |tokens| {
            const items = try dump.allocPrint(testing.allocator, dump.writeComponentValues, tokens);
            defer testing.allocator.free(items);
            const text = try std.fmt.allocPrint(testing.allocator, "[{s}]", .{items});
            defer testing.allocator.free(text);
            try testing.expectEqualStrings(expected orelse return error.TestExpectedGuaranteedInvalid, text);
        },
    }
}

test "FP-0014 case 39: custom properties keep tokens, case, and original text, and empty values are valid" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const sheet = try s.sheet("r { --Brand: Foo  /*c*/ bar(1, {x}) [y] ; --brand: other; --e:; --sp:   ; --case: FoO }", .author);
    _ = try s.resolve();
    const computed = try s.get(root);
    try expectCustom(computed, "--Brand", "[ident(Foo) ws ws function(bar)[number(1,integer,none) , ws block({)[ident(x)]] ws block([)[ident(y)]]");
    try testing.expectEqualSlices(u16, u("Foo  /*c*/ bar(1, {x}) [y]").units, sheet.rules[0].declarations[0].value.custom.original_text);
    try expectCustom(computed, "--brand", "[ident(other)]");
    try expectCustom(computed, "--e", "[]");
    try expectCustom(computed, "--sp", "[]");
    try expectCustom(computed, "--case", "[ident(FoO)]");
}

const Resolved = struct {
    scenario: Scenario,
    target: NodeHandle,

    fn deinit(r: *Resolved) void {
        r.scenario.deinit();
    }

    fn get(r: *Resolved) !*const ComputedStyle {
        return r.scenario.get(r.target);
    }

    fn reasons(r: *Resolved, buffer: []InvalidReason) []const InvalidReason {
        var count: usize = 0;
        for (r.scenario.map.?.diagnostics) |diagnostic| {
            if (!std.meta.eql(diagnostic.element, r.target)) continue;
            buffer[count] = diagnostic.reason;
            count += 1;
        }
        return buffer[0..count];
    }
};

/// Resolves `r { root_rules } p { child_rules }` over `r > p` and keeps the scenario for inspection.
fn resolveChild(r: *Resolved, root_rules: []const u8, child_rules: []const u8) !void {
    try r.scenario.init();
    errdefer r.scenario.deinit();
    const root = try r.scenario.add(null, "r");
    r.target = try r.scenario.add(root, "p");
    var buffer: [512]u8 = undefined;
    _ = try r.scenario.sheet(try std.fmt.bufPrint(&buffer, "r {{ {s} }} p {{ {s} }}", .{ root_rules, child_rules }), .author);
    _ = try r.scenario.resolve();
}

test "FP-0014 case 40: var() substitutes values, names, and fallbacks, and invalid substitutions unset properties" {
    const root_rules = "--c: rgb(0 0 255); --m: 7px; --n: 20; --other: 10px; --myvar: --other; --x: 5px; --args: --x, 9px; --args2: --none, 9px";
    var buffer: [4]InvalidReason = undefined;
    {
        var r: Resolved = undefined;
        try resolveChild(&r, root_rules, "color: var(--c)");
        defer r.deinit();
        try expectRgba((try r.get()).color, 0, 0, 255, 1);
    }
    {
        var r: Resolved = undefined;
        try resolveChild(&r, root_rules, "color: var(--missing, {rgb(1 2 3)})");
        defer r.deinit();
        try expectRgba((try r.get()).color, 1, 2, 3, 1);
    }
    const margins = [_]struct { declaration: []const u8, field: []const u8, value: values.LengthPercentageAuto, reasons: []const InvalidReason }{
        .{ .declaration = "margin-top: var(--m)", .field = "margin_top", .value = .{ .length = 7 }, .reasons = &.{} },
        .{ .declaration = "margin-top: var(var(--myvar))", .field = "margin_top", .value = .{ .length = 10 }, .reasons = &.{} },
        .{ .declaration = "margin-right: var(--missing, 3px)", .field = "margin_right", .value = .{ .length = 3 }, .reasons = &.{} },
        .{ .declaration = "margin-bottom: var(...var(--args))", .field = "margin_bottom", .value = .{ .length = 0 }, .reasons = &.{.unsupported_value} },
        .{ .declaration = "margin-left: var(--n)px", .field = "margin_left", .value = .{ .length = 0 }, .reasons = &.{.grammar_mismatch} },
        .{ .declaration = "margin-left: var(--missing,)", .field = "margin_left", .value = .{ .length = 0 }, .reasons = &.{.grammar_mismatch} },
        .{ .declaration = "margin-left: var(var(--args))", .field = "margin_left", .value = .{ .length = 0 }, .reasons = &.{.guaranteed_invalid} },
    };
    for (margins) |case| {
        var r: Resolved = undefined;
        try resolveChild(&r, root_rules, case.declaration);
        defer r.deinit();
        const computed = try r.get();
        const actual = if (std.mem.eql(u8, case.field, "margin_top"))
            computed.margin_top
        else if (std.mem.eql(u8, case.field, "margin_right"))
            computed.margin_right
        else if (std.mem.eql(u8, case.field, "margin_bottom"))
            computed.margin_bottom
        else
            computed.margin_left;
        try testing.expectEqual(case.value, actual);
        try testing.expectEqualSlices(InvalidReason, case.reasons, r.reasons(&buffer));
    }
    {
        var r: Resolved = undefined;
        try resolveChild(&r, root_rules, "font-size: var(--zz, var(--f, 30px))");
        defer r.deinit();
        try testing.expectEqual(30, (try r.get()).font_size);
    }
    {
        var r: Resolved = undefined;
        try resolveChild(&r, root_rules, "--s: var(...var(--args))");
        defer r.deinit();
        try expectCustom(try r.get(), "--s", null);
        try testing.expectEqualSlices(InvalidReason, &.{.unsupported_value}, r.reasons(&buffer));
    }
}

test "FP-0014 case 41: a substituted value that fails its grammar makes the property unset, not an earlier declaration" {
    var r: Resolved = undefined;
    try resolveChild(&r, "color: rgb(1 2 3); --not-a-color: 20px; --nc2: blue", "color: red; color: var(--not-a-color); margin-top: 9px; margin-top: var(--nc2)");
    defer r.deinit();
    const computed = try r.get();
    try expectRgba(computed.color, 1, 2, 3, 1);
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, computed.margin_top);
    var buffer: [4]InvalidReason = undefined;
    try testing.expectEqualSlices(InvalidReason, &.{ .grammar_mismatch, .grammar_mismatch }, r.reasons(&buffer));
}

const case_42_declarations = [_][]const u8{
    "--one: calc(var(--two) + 20px)",  "--two: calc(var(--one) - 20px)", "--self: var(--self)",
    "--p: var(--q)",                   "--q: var(--r, baz)",             "--r: var(--p)",
    "--outside: var(--p, ok)",         "--d0: x",                        "--d1: var(--d0) var(--d0)",
    "color: var(--one, rgb(0 128 0))",
};

fn expectCase42(computed: *const ComputedStyle) !void {
    inline for (.{ "--one", "--two", "--self", "--p", "--q", "--r" }) |name| try expectCustom(computed, name, null);
    try expectCustom(computed, "--outside", "[ident(ok)]");
    try expectCustom(computed, "--d1", "[ident(x) ws ident(x)]");
    try expectRgba(computed.color, 0, 128, 0, 1);
}

test "FP-0014 case 42: cycles make every participant guaranteed-invalid, in either declaration order" {
    for ([_]bool{ false, true }) |reversed| {
        var rules: std.ArrayList(u8) = .empty;
        defer rules.deinit(testing.allocator);
        try rules.appendSlice(testing.allocator, "r { ");
        for (0..case_42_declarations.len) |position| {
            const index = if (reversed) case_42_declarations.len - 1 - position else position;
            try rules.print(testing.allocator, "{s}; ", .{case_42_declarations[index]});
        }
        try rules.appendSlice(testing.allocator, "}");
        var s: Scenario = undefined;
        try s.init();
        defer s.deinit();
        const root = try s.add(null, "r");
        _ = try s.sheet(rules.items, .author);
        _ = try s.resolve();
        try expectCase42(try s.get(root));
    }
}

test "FP-0014 case 43: custom properties inherit computed values, and keywords in fallbacks act as keywords" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const parent = try s.add(null, "r");
    const children = [_]NodeHandle{ try s.add(parent, "a"), try s.add(parent, "b"), try s.add(parent, "c"), try s.add(parent, "d") };
    _ = try s.sheet("r { --x: P; --b: 1; --a: var(--b); color: rgb(1 2 3) } a { --b: 2; --c: var(--a) } b { --x: initial; color: var(--x, inherit) } c { --x: inherit } d { --x: unset }", .author);
    _ = try s.resolve();
    const first = try s.get(children[0]);
    try expectCustom(first, "--a", "[number(1,integer,none)]");
    try expectCustom(first, "--c", "[number(1,integer,none)]");
    const second = try s.get(children[1]);
    try expectCustom(second, "--x", null);
    try expectRgba(second.color, 1, 2, 3, 1);
    try expectCustom(try s.get(children[2]), "--x", "[ident(P)]");
    try expectCustom(try s.get(children[3]), "--x", "[ident(P)]");

    var t: Scenario = undefined;
    try t.init();
    defer t.deinit();
    const element = try t.add(null, "e");
    try t.set(element, "class", "r");
    _ = try t.sheet(".r { color: rgb(0 0 20) }", .user);
    _ = try t.sheet(".r { color: var(--missing, revert) }", .author);
    _ = try t.resolve();
    try expectRgba((try t.get(element)).color, 0, 0, 20, 1);
}

fn rootStyle(s: *Scenario, source: []const u8) !*const ComputedStyle {
    try s.init();
    errdefer s.deinit();
    const root = try s.add(null, "r");
    _ = try s.sheet(source, .author);
    _ = try s.resolve();
    return s.get(root);
}

test "FP-0014 case 44: malformed custom property values are dropped at parse time or become guaranteed-invalid" {
    {
        var s: Scenario = undefined;
        const computed = try rootStyle(&s, "r { --a: one; --a: ); --b: one; --b: var(b); --c: one; --c: x ! y; --e: one; --e: url(a b); --f: one; --f: var(); --k: a {b} c; --m: 2; margin-top: calc(var(--m) * 1px); color: var(1) }");
        defer s.deinit();
        inline for (.{ "--a", "--c", "--e", "--f" }) |name| try expectCustom(computed, name, "[ident(one)]");
        try expectCustom(computed, "--b", null);
        try expectCustom(computed, "--k", "[ident(a) ws block({)[ident(b)] ws ident(c)]");
        try expectDiagnostics(&s.sheets[0], &.{
            .{ .kind = .invalid_value, .name = "--a" },
            .{ .kind = .invalid_value, .name = "--c" },
            .{ .kind = .invalid_value, .name = "--e" },
            .{ .kind = .invalid_value, .name = "--f" },
        });
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, computed.margin_top);
        try expectRgba(computed.color, 0, 0, 0, 1);
        var reasons: [8]compute.PropertyDiagnostic = undefined;
        var count: usize = 0;
        for (s.map.?.diagnostics) |diagnostic| {
            if (diagnostic.property != .standard) continue;
            reasons[count] = .{ .property = diagnostic.property, .reason = diagnostic.reason };
            count += 1;
        }
        try testing.expectEqual(2, count);
        try testing.expectEqual(registry.PropertyKey{ .standard = .color }, reasons[0].property);
        try testing.expectEqual(InvalidReason.guaranteed_invalid, reasons[0].reason);
        try testing.expectEqual(registry.PropertyKey{ .standard = .margin_top }, reasons[1].property);
        try testing.expectEqual(InvalidReason.unsupported_value, reasons[1].reason);
    }
    {
        var s: Scenario = undefined;
        const computed = try rootStyle(&s, "r{--d:one}r{--d:\"x\n}");
        defer s.deinit();
        try expectCustom(computed, "--d", "[ident(one)]");
    }
    {
        var s: Scenario = undefined;
        const computed = try rootStyle(&s, "r{--g:var(--missing,");
        defer s.deinit();
        try expectCustom(computed, "--g", "[]");
    }
}

test "FP-0014 case 45: an expansion past 65536 component values is guaranteed-invalid" {
    var rules: std.ArrayList(u8) = .empty;
    defer rules.deinit(testing.allocator);
    try rules.appendSlice(testing.allocator, "r { --p1: lol; ");
    for (2..31) |n| try rules.print(testing.allocator, "--p{d}: var(--p{d}) var(--p{d}); ", .{ n, n - 1, n - 1 });
    try rules.appendSlice(testing.allocator, "margin-top: var(--p18, 4px) }");
    var s: Scenario = undefined;
    const computed = try rootStyle(&s, rules.items);
    defer s.deinit();
    try testing.expectEqual(65535, computed.customValue(u("--p16").units).tokens.len);
    try testing.expectEqual(131071, computed.customValue(u("--p17").units).tokens.len);
    for (18..31) |n| {
        var name_buffer: [8]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "--p{d}", .{n});
        var units: [8]u16 = undefined;
        for (name, units[0..name.len]) |byte, *unit| unit.* = byte;
        try testing.expectEqual(values.CustomValue.guaranteed_invalid, computed.customValue(units[0..name.len]));
    }
    try testing.expectEqual(values.LengthPercentageAuto{ .length = 4 }, computed.margin_top);
}

test "FP-0014 case 46: nesting depth is bounded only by memory" {
    const depth = 100000;
    {
        var rules: std.ArrayList(u8) = .empty;
        defer rules.deinit(testing.allocator);
        try rules.appendSlice(testing.allocator, "p{--x:");
        try rules.ensureUnusedCapacity(testing.allocator, depth);
        for (0..depth) |_| rules.appendAssumeCapacity('(');
        var s: Scenario = undefined;
        try s.init();
        defer s.deinit();
        const p = try s.add(null, "p");
        _ = try s.sheet(rules.items, .author);
        _ = try s.resolve();
        const tokens = (try s.get(p)).customValue(u("--x").units).tokens;
        try testing.expectEqual(depth, tokens.len);
        for (tokens, 0..) |value, index| {
            try testing.expectEqual(ComponentValue.Kind.block, value.kind);
            try testing.expectEqual(tokenizer.TokenKind.open_paren, value.token.kind);
            try testing.expectEqual(depth - index - 1, value.descendants);
        }
    }
    {
        var s: Scenario = undefined;
        try s.init();
        defer s.deinit();
        const root = try s.add(null, "root");
        var first: NodeHandle = undefined;
        var deepest = root;
        for (0..depth) |index| {
            deepest = try s.add(deepest, "e");
            if (index == 0) first = deepest;
        }
        _ = try s.sheet("root { color: rgb(1 2 3) } e { margin-top: 1px } root > e { margin-top: 2px }", .author);
        _ = try s.resolve();
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 2 }, (try s.get(first)).margin_top);
        const last = try s.get(deepest);
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 1 }, last.margin_top);
        try expectRgba(last.color, 1, 2, 3, 1);
    }
    {
        var rules: std.ArrayList(u8) = .empty;
        defer rules.deinit(testing.allocator);
        try rules.appendSlice(testing.allocator, "r { ");
        var n: usize = depth;
        while (n >= 1) : (n -= 1) try rules.print(testing.allocator, "--v{d}: var(--v{d}); ", .{ n, n - 1 });
        try rules.appendSlice(testing.allocator, "--v0: z }");
        var s: Scenario = undefined;
        const computed = try rootStyle(&s, rules.items);
        defer s.deinit();
        try expectCustom(computed, "--v100000", "[ident(z)]");
    }
}

// Stage separation and allocation failures.

/// Checks at compile time that no type in `forbidden` appears among `T`'s fields, at any depth.
fn expectNoFieldOfTypes(comptime T: type, comptime forbidden: []const type) void {
    comptime {
        @setEvalBranchQuota(100_000);
        var pending: []const type = &.{T};
        var seen: []const type = &.{};
        while (pending.len != 0) {
            const current = pending[0];
            pending = pending[1..];
            var known = false;
            for (seen) |other| known = known or other == current;
            if (known) continue;
            seen = seen ++ .{current};
            for (forbidden) |bad| {
                if (current == bad) @compileError(@typeName(T) ++ " holds the computed-value type " ++ @typeName(bad));
            }
            switch (@typeInfo(current)) {
                .@"struct" => |info| for (info.field_types) |field_type| {
                    pending = pending ++ .{field_type};
                },
                .@"union" => |info| for (info.field_types) |field_type| {
                    pending = pending ++ .{field_type};
                },
                .optional => |info| pending = pending ++ .{info.child},
                .pointer => |info| pending = pending ++ .{info.child},
                .array => |info| pending = pending ++ .{info.child},
                else => {},
            }
        }
    }
}

fn expectNoParameterOfTypes(comptime function: anytype, comptime forbidden: []const type) void {
    comptime {
        for (@typeInfo(@TypeOf(function)).@"fn".param_types) |param_type| {
            for (forbidden) |bad| {
                if (param_type.? == bad) @compileError("a stage parameter has the type " ++ @typeName(bad));
            }
        }
    }
}

fn levelDeclaration(level: u8, value: *const values.DeclaredValue) applicable.ApplicableDeclaration {
    const origin: applicable.Origin = switch (level) {
        1, 6 => .user_agent,
        2, 5 => .user,
        else => .author,
    };
    const specificity: applicable.Specificity = if (level <= 3) .{ .a = 1 } else .{ .c = 1 };
    return .{
        .property = .{ .standard = .color },
        .value = value,
        .origin = origin,
        .important = level >= 4,
        .specificity = specificity,
        .order = .{ .sheet = 0, .rule = level, .declaration = 0 },
        .rule = .{ .sheet = 0, .rule = level },
    };
}

test "FP-0014 case 47: the cascade and computed values take no DOM or selector input" {
    const dom_and_selector_types = [_]type{
        dom.Store,                 *dom.Store,                    *const dom.Store, dom.NodeHandle,
        selectors.SelectorList,    *const selectors.SelectorList, Stylesheet,       *const Stylesheet,
        []const *const Stylesheet,
    };
    comptime expectNoParameterOfTypes(cascade.cascade, &dom_and_selector_types);
    comptime expectNoParameterOfTypes(compute.computeStyle, &dom_and_selector_types);
    comptime {
        for (@typeInfo(applicable.ApplicableDeclaration).@"struct".field_types) |field_type| {
            if (field_type == f64) @compileError("ApplicableDeclaration holds a computed font size");
        }
    }
    comptime expectNoFieldOfTypes(applicable.ApplicableDeclaration, &.{
        values.Display, values.Color, values.LengthPercentageAuto, values.CustomValue, ComputedStyle,
    });

    var declared: [6]values.DeclaredValue = undefined;
    var declarations: [6]applicable.ApplicableDeclaration = undefined;
    for (&declared, &declarations, 1..) |*value, *declaration, level| {
        value.* = .{ .color = .{ .srgb = .{ .red = @floatFromInt(level), .green = 0, .blue = 0, .alpha = 1 } } };
        declaration.* = levelDeclaration(@intCast(level), value);
    }
    var result = try cascade.cascade(testing.allocator, &declarations);
    defer result.deinit(testing.allocator);
    const winner = result.get(.{ .standard = .color })[0];
    try testing.expect(std.meta.eql(declared[5], winner.value.*));

    var parent = ComputedStyle.initial();
    parent.color = .{ .srgb = .{ .red = 9, .green = 9, .blue = 9, .alpha = 1 } };
    parent.margin_top = .{ .length = 7 };
    const font: values.DeclaredValue = .{ .font_size = .{ .length = .{ .value = 30, .unit = .px } } };
    const single = [_]applicable.ApplicableDeclaration{.{
        .property = .{ .standard = .font_size },
        .value = &font,
        .origin = .author,
        .important = false,
        .specificity = .{},
        .order = .{ .sheet = 0, .rule = 0, .declaration = 0 },
        .rule = .{ .sheet = 0, .rule = 0 },
    }};
    var hand_built = try cascade.cascade(testing.allocator, &single);
    defer hand_built.deinit(testing.allocator);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostics: std.ArrayList(compute.PropertyDiagnostic) = .empty;
    defer diagnostics.deinit(testing.allocator);
    const computed = try compute.computeStyle(testing.allocator, arena.allocator(), &hand_built, &parent, &parent, false, &diagnostics);
    try expectRgba(computed.color, 9, 9, 9, 1);
    try testing.expectEqual(30, computed.font_size);
    inline for (.{ "margin_top", "margin_right", "margin_bottom", "margin_left" }) |field| {
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, @field(computed, field));
    }
    try testing.expectEqual(0, diagnostics.items.len);
}

/// A digest of every element name, attribute, and character data reachable from `node`, in tree order.
fn storeDigest(store: *dom.Store, node: NodeHandle) !u64 {
    var hasher: std.hash.Wyhash = .init(0);
    var stack: [64]NodeHandle = undefined;
    var depth: usize = 1;
    stack[0] = node;
    while (depth != 0) {
        depth -= 1;
        const current = stack[depth];
        std.hash.autoHash(&hasher, try store.nodeKind(current));
        if (try store.elementName(current)) |name| {
            hasher.update(std.mem.sliceAsBytes(name.local_name.units));
            if (name.namespace) |namespace| hasher.update(std.mem.sliceAsBytes(namespace.units));
            var attributes = try store.attributes(current);
            while (attributes.next()) |attribute| {
                hasher.update(std.mem.sliceAsBytes(attribute.local_name.units));
                hasher.update(std.mem.sliceAsBytes(attribute.value.units));
            }
        }
        if (try store.characterData(current)) |data| hasher.update(std.mem.sliceAsBytes(data.units));
        var child = try store.lastChild(current);
        while (child) |next| : (child = try store.previousSibling(next)) {
            stack[depth] = next;
            depth += 1;
        }
    }
    std.hash.autoHash(&hasher, store.nodeCount());
    return hasher.final();
}

const every_diagnostic_sheet = "a:hover{} #1{} @media x{} p{color:blue; q{} colour:red; color:12px; color:hsl(0 0% 0%); color:red}";

fn case48Scenario(gpa: Allocator, store: *dom.Store, document: NodeHandle, case_42_sheet: []const u8, digest: u64) !void {
    run(gpa, store, document, case_42_sheet) catch |err| {
        try testing.expectEqual(error.OutOfMemory, err);
        try testing.expectEqual(digest, try storeDigest(store, document));
        return err;
    };
    try testing.expectEqual(digest, try storeDigest(store, document));
}

fn run(gpa: Allocator, store: *dom.Store, document: NodeHandle, case_42_sheet: []const u8) !void {
    var source_arena: std.heap.ArenaAllocator = .init(gpa);
    defer source_arena.deinit();
    var diagnosed = try Stylesheet.parse(gpa, try runtimeView(source_arena.allocator(), every_diagnostic_sheet), .author);
    defer diagnosed.deinit();
    var seen: std.EnumSet(DiagnosticKind) = .empty;
    for (diagnosed.diagnostics) |diagnostic| seen.insert(diagnostic.kind);
    try testing.expectEqual(std.EnumSet(DiagnosticKind).full, seen);
    var customs = try Stylesheet.parse(gpa, try runtimeView(source_arena.allocator(), case_42_sheet), .author);
    defer customs.deinit();
    const sheets = [_]*const Stylesheet{ &diagnosed, &customs };
    var map = try style.resolve(gpa, store, document, &sheets);
    defer map.deinit();
    const root = (try store.firstChild(document)).?;
    try expectCase42(try map.get(root));
}

test "FP-0014 case 48: every induced allocation failure returns OutOfMemory, leaves the store unchanged, and leaks nothing" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    _ = try Fixture23.build(&s);
    var rules: std.ArrayList(u8) = .empty;
    defer rules.deinit(testing.allocator);
    try rules.appendSlice(testing.allocator, "root { ");
    for (case_42_declarations) |declaration| try rules.print(testing.allocator, "{s}; ", .{declaration});
    try rules.appendSlice(testing.allocator, "}");
    const digest = try storeDigest(&s.store, s.document);
    // Fail every remap, so that each growth step is an allocation the checker can induce
    // and the count does not depend on whether the backing allocator can grow a block in place.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_remap.allocator(), case48Scenario, .{ &s.store, s.document, rules.items, digest });
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

// Revision 1.

/// The parts of one revision 1 case. Every part runs, and a failing case names each part that fails and each that passes,
/// so that a run before the fix shows which parts already pass.
const Parts = struct {
    case: []const u8,
    passed: [16][]const u8 = undefined,
    passed_count: usize = 0,
    failed: usize = 0,

    fn check(p: *Parts, part: []const u8, result: anyerror!void) void {
        if (result) |_| {
            p.passed[p.passed_count] = part;
            p.passed_count += 1;
        } else |err| {
            p.failed += 1;
            std.debug.print("{s}: part \"{s}\" fails with {s}\n", .{ p.case, part, @errorName(err) });
        }
    }

    fn finish(p: *const Parts) !void {
        if (p.failed == 0) return;
        for (p.passed[0..p.passed_count]) |part| std.debug.print("{s}: part \"{s}\" passes\n", .{ p.case, part });
        return error.TestCasePartsFailed;
    }
};

fn expectDisplay(computed: *const ComputedStyle, expected: values.Display) !void {
    try testing.expect(std.meta.eql(expected, computed.display));
}

fn expectZeroMargins(computed: *const ComputedStyle) !void {
    inline for (.{ "margin_top", "margin_right", "margin_bottom", "margin_left" }) |field| {
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 0 }, @field(computed, field));
    }
}

fn expectFontSize(computed: *const ComputedStyle, expected: f64) !void {
    try testing.expectEqual(expected, computed.font_size);
}

test "FP-0014 case 49: a text node's style comes from defaulting, not from the parent's whole style" {
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const root = try s.add(null, "r");
    const text = try s.store.createText(s.document, u("text"));
    try s.store.appendChild(root, text);
    _ = try s.sheet("r { display: block; margin-top: 5px; margin-left: 2px; color: rgb(1 2 3); font-size: 20px; --k: v }", .author);
    const map = try s.resolve();
    const computed: ComputedStyle = try map.textStyle(text);
    var parts: Parts = .{ .case = "case 49" };
    parts.check("display is inline flow", expectDisplay(&computed, pair(.@"inline", .flow, false)));
    parts.check("every margin is 0px", expectZeroMargins(&computed));
    parts.check("color is 1 2 3", expectRgba(computed.color, 1, 2, 3, 1));
    parts.check("font-size is 20", expectFontSize(&computed, 20));
    parts.check("--k is [ident(v)]", expectCustom(&computed, "--k", "[ident(v)]"));
    try parts.finish();
}

fn expectOnlyRule(sheet: *const Stylesheet, comptime name: []const u8) !void {
    try testing.expectEqual(1, sheet.rules.len);
    try expectSelectorText(sheet, 0, name);
}

test "FP-0014 case 50: nothing inside an ignored at-rule's block reports a diagnostic" {
    var sheet = try parseSheet("@media x { b { colour: red } a { b {} } @media y { c { color: blue } } } d { color: red }", .author);
    defer sheet.deinit();
    var parts: Parts = .{ .case = "case 50" };
    parts.check("only the rule for d is kept", expectOnlyRule(&sheet, "d"));
    parts.check("one ignored_at_rule diagnostic for media", expectDiagnostics(&sheet, &.{.{ .kind = .ignored_at_rule, .name = "media" }}));
    try parts.finish();
}

/// Checks that the custom property `name` has exactly the diagnostics `expected` among the style map's diagnostics.
fn expectCustomReasons(map: *const style.StyleMap, comptime name: []const u8, expected: []const InvalidReason) !void {
    var reasons: [4]InvalidReason = undefined;
    var count: usize = 0;
    for (map.diagnostics) |diagnostic| {
        if (diagnostic.property != .custom or !std.mem.eql(u16, diagnostic.property.custom, u(name).units)) continue;
        if (count == reasons.len) return error.TestTooManyDiagnostics;
        reasons[count] = diagnostic.reason;
        count += 1;
    }
    try testing.expectEqualSlices(InvalidReason, expected, reasons[0..count]);
}

fn expectUnsupportedCustom(map: *const style.StyleMap, computed: *const ComputedStyle, comptime name: []const u8) !void {
    try expectCustom(computed, name, null);
    try expectCustomReasons(map, name, &.{.unsupported_value});
}

test "FP-0014 case 51: the other arbitrary substitution functions make a custom property unsupported" {
    var s: Scenario = undefined;
    const computed = try rootStyle(&s, "r { --a: attr(data-x); --b: if(else: 2); --c: inherit(--k); --d: ident(a); --e: random-item(--x, a, b); --f: if(...var(--args); else: x); --g: foo(1); --args: 1 }");
    defer s.deinit();
    const map = &s.map.?;
    var parts: Parts = .{ .case = "case 51" };
    inline for (.{ "--a", "--b", "--c", "--d", "--e", "--f" }) |name| {
        parts.check(name ++ " is guaranteed-invalid with unsupported_value", expectUnsupportedCustom(map, computed, name));
    }
    parts.check("--g is [function(foo)[number(1,integer,none)]]", expectCustom(computed, "--g", "[function(foo)[number(1,integer,none)]]"));
    try parts.finish();
}

fn expectUnsupportedDisplay(value: []const u8) !void {
    const observed = try observeProperty("p", "display", value, 1);
    try observed.expectSheetDiagnostics(&.{.unsupported_value});
}

test "FP-0014 case 52: grid-lanes, the math inner type, and the column combinator are unsupported standard forms" {
    var parts: Parts = .{ .case = "case 52" };
    inline for (.{ "grid-lanes", "inline-grid-lanes", "block grid-lanes", "math", "block math", "inline math" }) |value| {
        parts.check("display: " ++ value, expectUnsupportedDisplay(value));
    }
    parts.check("a||b", expectSelectorFailure(u("a||b"), .unsupported_selector));
    try parts.finish();
}

/// Case 53's chain: `root` and `depth` nested `e` elements under the sheet `x e e e { margin-top: 3px } e { margin-top: 1px }`.
fn expectChainWithinBound(depth: usize) !void {
    const bound = 4 * depth * (depth + 1);
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    var elements: std.ArrayList(NodeHandle) = .empty;
    defer elements.deinit(testing.allocator);
    try elements.append(testing.allocator, try s.add(null, "root"));
    for (0..depth) |_| try elements.append(testing.allocator, try s.add(elements.getLast(), "e"));
    const sheets = [_]*const Stylesheet{try s.sheet("x e e e { margin-top: 3px } e { margin-top: 1px }", .author)};
    // First match each element in tree order, as `resolve` does, and stop as soon as the count exceeds the bound,
    // so that a matcher without the early exit fails quickly instead of running for hours.
    {
        var matcher: selectors.Matcher = .init(testing.allocator, &s.store);
        defer matcher.deinit();
        selectors.test_counters.compound_match_attempts = 0;
        for (elements.items, 0..) |element, element_depth| {
            testing.allocator.free(try selectors.matchRulesWith(testing.allocator, &matcher, element, &sheets));
            const attempts = selectors.test_counters.compound_match_attempts;
            if (attempts > bound) {
                std.debug.print("case 53: {d} compound-match attempts after the element at depth {d} exceed the bound {d}\n", .{ attempts, element_depth, bound });
                return error.TestBoundExceeded;
            }
        }
    }
    selectors.test_counters.compound_match_attempts = 0;
    _ = try s.resolve();
    const attempts = selectors.test_counters.compound_match_attempts;
    if (attempts > bound) {
        std.debug.print("case 53: resolution makes {d} compound-match attempts, which exceed the bound {d}\n", .{ attempts, bound });
        return error.TestBoundExceeded;
    }
    for (elements.items[1..]) |element| {
        try testing.expectEqual(values.LengthPercentageAuto{ .length = 1 }, (try s.get(element)).margin_top);
    }
}

/// The number of the element's classes, from the ordered set parser.
fn classCount(store: *dom.Store, element: NodeHandle) !usize {
    const classes = try store.classes(testing.allocator, element);
    defer testing.allocator.free(classes);
    return classes.len;
}

/// Case 53's element with `tokens` distinct class tokens, `c0` to `c{tokens - 1}`.
fn expectClassesWithinBound(tokens: usize) !void {
    const bound = 32 * tokens;
    var s: Scenario = undefined;
    try s.init();
    defer s.deinit();
    const element = try s.add(null, "r");
    var value: std.ArrayList(u8) = .empty;
    defer value.deinit(testing.allocator);
    for (0..tokens) |index| try value.print(testing.allocator, "c{d} ", .{index});
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try s.store.setAttribute(element, null, u("class"), try runtimeView(arena.allocator(), value.items));
    const selector = try std.fmt.allocPrint(arena.allocator(), ".c{d}", .{tokens - 1});
    var parsed = try parseSelectors(try runtimeView(arena.allocator(), selector));
    defer parsed.deinit();
    var matcher: selectors.Matcher = .init(testing.allocator, &s.store);
    defer matcher.deinit();
    dom.test_counters.class_token_comparisons = 0;
    const matched = try matcher.matchList(element, &parsed.result.list) != null;
    if (dom.test_counters.class_token_comparisons > bound) {
        std.debug.print("case 53: matching makes {d} class-token comparisons, which exceed the bound {d}\n", .{ dom.test_counters.class_token_comparisons, bound });
        return error.TestBoundExceeded;
    }
    try testing.expect(matched);
    try testing.expectEqual(tokens, try classCount(&s.store, element));
    if (dom.test_counters.class_token_comparisons > bound) {
        std.debug.print("case 53: matching and the ordered set make {d} class-token comparisons, which exceed the bound {d}\n", .{ dom.test_counters.class_token_comparisons, bound });
        return error.TestBoundExceeded;
    }
}

test "FP-0014 case 53: selector matching exits early, and class tokens deduplicate in n log n time" {
    var parts: Parts = .{ .case = "case 53" };
    parts.check("a 2000-deep chain stays within 4 * 2000 * 2001 compound-match attempts", expectChainWithinBound(2000));
    parts.check("20000 class tokens stay within 32 * 20000 class-token comparisons", expectClassesWithinBound(20000));
    try parts.finish();
}

test "FP-0014 case 54: the system color palette is opaque and each legible pair has a contrast ratio of at least 4.5" {
    const pairs = [_][2]values.SystemColor{
        .{ .canvas, .canvas_text },             .{ .canvas, .link_text },         .{ .canvas, .visited_text },
        .{ .canvas, .active_text },             .{ .button_face, .button_text },  .{ .field, .field_text },
        .{ .mark, .mark_text },                 .{ .highlight, .highlight_text }, .{ .selected_item, .selected_item_text },
        .{ .accent_color, .accent_color_text }, .{ .canvas, .button_border },
    };
    for (pairs) |entry| {
        const background = luminance(entry[0].srgb());
        const foreground = luminance(entry[1].srgb());
        const ratio = (@max(background, foreground) + 0.05) / (@min(background, foreground) + 0.05);
        try testing.expect(ratio >= 4.5);
    }
    try testing.expectEqual(19, values.SystemColor.names.len);
    try testing.expectEqual(23, values.deprecated_system_colors.len);
}

/// The WCAG relative luminance of an sRGB color.
fn luminance(rgb: [3]u8) f64 {
    var linear: [3]f64 = undefined;
    for (rgb, &linear) |channel, *out| {
        const c = @as(f64, @floatFromInt(channel)) / 255;
        out.* = if (c <= 0.04045) c / 12.92 else std.math.pow(f64, (c + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}
