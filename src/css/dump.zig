//! Deterministic text dumps of tokens, component values, declarations, and rules.
//! The FP-0014 contract freezes the format, and its cases compare dumps byte for byte.
//! No function recurses: nested values and rules use explicit stacks.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Token = tokenizer.Token;
const ComponentValue = parser.ComponentValue;
const Declaration = parser.Declaration;
const Rule = parser.Rule;
const BlockItem = parser.BlockItem;

pub const Error = Allocator.Error || Writer.Error;

/// Writes UTF-16 code units as UTF-8. An unpaired surrogate, which filtered input never yields, writes U+FFFD.
pub fn writeUtf16(w: *Writer, units: []const u16) Writer.Error!void {
    var index: usize = 0;
    while (index < units.len) {
        var code_point: u21 = units[index];
        index += 1;
        if (code_point >= 0xD800 and code_point <= 0xDBFF and index < units.len and units[index] >= 0xDC00 and units[index] <= 0xDFFF) {
            code_point = 0x10000 + ((code_point - 0xD800) << 10) + (units[index] - 0xDC00);
            index += 1;
        } else if (code_point >= 0xD800 and code_point <= 0xDFFF) {
            code_point = 0xFFFD;
        }
        try writeCodePoint(w, code_point);
    }
}

pub fn writeCodePoint(w: *Writer, code_point: u21) Writer.Error!void {
    var buffer: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(code_point, &buffer) catch std.unicode.utf8Encode(0xFFFD, &buffer) catch unreachable;
    try w.writeAll(buffer[0..len]);
}

fn signText(sign: tokenizer.Sign) []const u8 {
    return switch (sign) {
        .none => "none",
        .plus => "+",
        .minus => "-",
    };
}

/// Writes one token in the dump format of the FP-0014 contract.
pub fn writeToken(w: *Writer, token: Token) Writer.Error!void {
    switch (token.kind) {
        .ident => try writeWrapped(w, "ident", token.value),
        .function => try writeWrapped(w, "function", token.value),
        .at_keyword => try writeWrapped(w, "at", token.value),
        .hash => {
            try w.writeAll("hash(");
            try writeUtf16(w, token.value);
            try w.writeAll(if (token.hash_type == .id) ",id)" else ",unrestricted)");
        },
        .string => try writeWrapped(w, "string", token.value),
        .bad_string => try w.writeAll("bad-string"),
        .url => try writeWrapped(w, "url", token.value),
        .bad_url => try w.writeAll("bad-url"),
        .delim => {
            try w.writeAll("delim(");
            try writeCodePoint(w, token.delim);
            try w.writeAll(")");
        },
        .number => try w.print("number({d},{s},{s})", .{ token.number, @tagName(token.number_type), signText(token.sign) }),
        .percentage => try w.print("percentage({d},{s})", .{ token.number, signText(token.sign) }),
        .dimension => {
            try w.print("dimension({d},{s},{s},", .{ token.number, @tagName(token.number_type), signText(token.sign) });
            try writeUtf16(w, token.unit);
            try w.writeAll(")");
        },
        .unicode_range => try w.print("unicode-range({X},{X})", .{ token.range_start, token.range_end }),
        .whitespace => try w.writeAll("ws"),
        .cdo => try w.writeAll("<!--"),
        .cdc => try w.writeAll("-->"),
        .colon => try w.writeAll(":"),
        .semicolon => try w.writeAll(";"),
        .comma => try w.writeAll(","),
        .open_square => try w.writeAll("["),
        .close_square => try w.writeAll("]"),
        .open_paren => try w.writeAll("("),
        .close_paren => try w.writeAll(")"),
        .open_curly => try w.writeAll("{"),
        .close_curly => try w.writeAll("}"),
    }
}

fn writeWrapped(w: *Writer, comptime name: []const u8, value: []const u16) Writer.Error!void {
    try w.writeAll(name ++ "(");
    try writeUtf16(w, value);
    try w.writeAll(")");
}

/// Writes tokens separated by one space.
pub fn writeTokens(w: *Writer, tokens: []const Token) Writer.Error!void {
    for (tokens, 0..) |token, index| {
        if (index != 0) try w.writeAll(" ");
        try writeToken(w, token);
    }
}

/// Writes a component value list: preserved tokens as tokens, a function as `function(NAME)[ITEMS]`,
/// and a simple block as `block({)[ITEMS]`, with items separated by one space.
pub fn writeComponentValues(gpa: Allocator, w: *Writer, list: []const ComponentValue) Error!void {
    // The end index of each open function or block.
    var ends: std.ArrayList(usize) = .empty;
    defer ends.deinit(gpa);
    var first = true;
    var index: usize = 0;
    while (true) {
        while (ends.items.len != 0 and ends.items[ends.items.len - 1] == index) {
            _ = ends.pop();
            try w.writeAll("]");
            first = false;
        }
        if (index == list.len) break;
        if (!first) try w.writeAll(" ");
        const value = list[index];
        switch (value.kind) {
            .token => {
                try writeToken(w, value.token);
                first = false;
            },
            .function => {
                try writeWrapped(w, "function", value.token.value);
                try w.writeAll("[");
                try ends.append(gpa, index + 1 + value.descendants);
                first = true;
            },
            .block => {
                try w.writeAll(switch (value.token.kind) {
                    .open_curly => "block({)[",
                    .open_square => "block([)[",
                    else => "block(()[",
                });
                try ends.append(gpa, index + 1 + value.descendants);
                first = true;
            },
        }
        index += 1;
    }
}

/// Writes `NAME = [ITEMS]`, followed by ` !important` when the important flag is set.
pub fn writeDeclaration(gpa: Allocator, w: *Writer, declaration: Declaration) Error!void {
    try writeUtf16(w, declaration.name);
    try w.writeAll(" = [");
    try writeComponentValues(gpa, w, declaration.value);
    try w.writeAll("]");
    if (declaration.important) try w.writeAll(" !important");
}

fn writeDeclarations(gpa: Allocator, w: *Writer, comptime label: []const u8, declarations: []const Declaration) Error!void {
    try w.writeAll(label ++ "{");
    for (declarations, 0..) |declaration, index| {
        if (index != 0) try w.writeAll("; ");
        try writeDeclaration(gpa, w, declaration);
    }
    try w.writeAll("}");
}

const Task = union(enum) {
    text: []const u8,
    rule: Rule,
    item: BlockItem,
};

/// Writes a rule: `qualified [PRELUDE] decls{D; D} rules{R; R}`, `@NAME [PRELUDE] no-block`,
/// `@NAME [PRELUDE] block{ITEM; ITEM}`, or `nested-decls{D; D}`.
pub fn writeRule(gpa: Allocator, w: *Writer, rule: Rule) Error!void {
    return writeTasks(gpa, w, .{ .rule = rule });
}

/// Writes an item of a block's contents: a rule, or a declaration list as `decls{D; D}`.
pub fn writeBlockItem(gpa: Allocator, w: *Writer, block_item: BlockItem) Error!void {
    return writeTasks(gpa, w, .{ .item = block_item });
}

fn writeTasks(gpa: Allocator, w: *Writer, first: Task) Error!void {
    var stack: std.ArrayList(Task) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, first);
    while (stack.pop()) |task| switch (task) {
        .text => |text| try w.writeAll(text),
        .item => |block_item| switch (block_item) {
            .declarations => |declarations| try writeDeclarations(gpa, w, "decls", declarations),
            .rule => |rule| try stack.append(gpa, .{ .rule = rule }),
        },
        .rule => |rule| switch (rule) {
            .nested_declarations => |declarations| try writeDeclarations(gpa, w, "nested-decls", declarations),
            .qualified => |qualified| {
                try w.writeAll("qualified [");
                try writeComponentValues(gpa, w, qualified.prelude);
                try w.writeAll("] ");
                try writeDeclarations(gpa, w, "decls", qualified.declarations);
                try w.writeAll(" rules{");
                try stack.append(gpa, .{ .text = "}" });
                var index = qualified.rules.len;
                while (index > 0) {
                    index -= 1;
                    try stack.append(gpa, .{ .rule = qualified.rules[index] });
                    if (index != 0) try stack.append(gpa, .{ .text = "; " });
                }
            },
            .at => |at| {
                try w.writeAll("@");
                try writeUtf16(w, at.name);
                try w.writeAll(" [");
                try writeComponentValues(gpa, w, at.prelude);
                try w.writeAll("] ");
                const items = at.block orelse {
                    try w.writeAll("no-block");
                    continue;
                };
                try w.writeAll("block{");
                try stack.append(gpa, .{ .text = "}" });
                var index = items.len;
                while (index > 0) {
                    index -= 1;
                    try stack.append(gpa, .{ .item = items[index] });
                    if (index != 0) try stack.append(gpa, .{ .text = "; " });
                }
            },
        },
    };
}

/// Returns a dump made by `write`, which receives `gpa`, the writer, and `value`. The caller frees it with `gpa`.
pub fn allocPrint(gpa: Allocator, comptime write: anytype, value: anytype) Error![]u8 {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();
    try write(gpa, &output.writer, value);
    return output.toOwnedSlice();
}
