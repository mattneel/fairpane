//! The canonical dump of tokenizer steps.
//!
//! Each step becomes one UTF-8 line followed by LF, with no spaces. Adjacent `characters` tokens with no other step
//! between them become one line, so a chunk boundary, which may split a run of characters, never changes the dump.
//! A `need_input` step writes nothing and splits nothing.
//!
//! A string is `"`, its escaped code units, and `"`. Escaping maps `"` to `\"`, `\` to `\\`, every other code unit from
//! 0x20 to 0x7E to itself, and every other code unit to `\u` and four uppercase hexadecimal digits.
//! Each unit of a surrogate pair is escaped separately.
//!
//! | Step | Line without spans |
//! | --- | --- |
//! | DOCTYPE | `["DOCTYPE",name,public,system,force_quirks]`, with `null` for a missing field |
//! | Start tag | `["StartTag",name,[[n,v],...],self_closing]` |
//! | End tag | `["EndTag",name,[[n,v],...],self_closing]` |
//! | Comment | `["Comment",data]` |
//! | Processing instruction | `["PI",target,data]` |
//! | Characters | `["Character",data]` |
//! | End of file | `["EOF"]` |
//! | Parse error | `["error",code,line,column,offset]` |
//!
//! With spans, each token array gains a final element `[start,end]` of offsets, and each attribute becomes
//! `[n,v,[ns,ne],[vs,ve]]`, or `[n,v,[ns,ne],null]` when its `value_span` is null.
//! The token dump is the dump with spans and without error lines.

const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Step = tokenizer.Step;
const Span = tokenizer.Span;
const View = tokenizer.View;

pub const Options = struct {
    /// Whether each token line ends with its span, and each attribute with its name and value spans.
    spans: bool,
    /// Whether each parse error writes a line. A parse error separates character runs either way.
    errors: bool,
};

/// The dump with spans and errors, which the partition harness compares.
pub const full: Options = .{ .spans = true, .errors = true };
/// The dump that the expected-value notation of the FP-0008 contract describes.
pub const plain: Options = .{ .spans = false, .errors = true };
/// The token dump of the laboratory's `tokenize` stage.
pub const tokens: Options = .{ .spans = true, .errors = false };

pub const Dumper = struct {
    gpa: Allocator,
    writer: *Writer,
    options: Options,
    /// The run of characters that the next line will hold, and its span.
    pending: std.ArrayList(u16) = .empty,
    pending_start: usize = 0,
    pending_end: usize = 0,
    /// The number of lines written.
    lines: usize = 0,

    pub const Error = Allocator.Error || Writer.Error;

    pub fn init(gpa: Allocator, writer: *Writer, options: Options) Dumper {
        return .{ .gpa = gpa, .writer = writer, .options = options };
    }

    pub fn deinit(d: *Dumper) void {
        d.pending.deinit(d.gpa);
        d.* = undefined;
    }

    /// Records one step. Characters wait until the next other step or `finish`, because the dump merges them.
    pub fn step(d: *Dumper, s: Step) Error!void {
        switch (s) {
            .need_input => {},
            .parse_error => |e| {
                try d.flush();
                if (!d.options.errors) return;
                try d.writer.print("[\"error\",\"{s}\",{d},{d},{d}]\n", .{
                    errors.name(e.code),
                    e.position.line,
                    e.position.column,
                    @backingInt(e.position.offset),
                });
                d.lines += 1;
            },
            .token => |token| switch (token.kind) {
                .characters => |view| {
                    if (d.pending.items.len == 0) d.pending_start = @backingInt(token.span.start.offset);
                    try d.pending.appendSlice(d.gpa, view.units);
                    d.pending_end = @backingInt(token.span.end.offset);
                },
                else => {
                    try d.flush();
                    try d.writeToken(token.kind, token.span);
                },
            },
        }
    }

    /// Writes any pending characters. Call it after the last step.
    pub fn finish(d: *Dumper) Error!void {
        try d.flush();
    }

    fn flush(d: *Dumper) Error!void {
        if (d.pending.items.len == 0) return;
        const w = d.writer;
        try w.writeAll("[\"Character\",");
        try writeString(w, d.pending.items);
        if (d.options.spans) try w.print(",[{d},{d}]", .{ d.pending_start, d.pending_end });
        try w.writeAll("]\n");
        d.lines += 1;
        d.pending.clearRetainingCapacity();
    }

    fn writeToken(d: *Dumper, kind: tokenizer.Kind, span: Span) Writer.Error!void {
        const w = d.writer;
        switch (kind) {
            .doctype => |doctype| {
                try w.writeAll("[\"DOCTYPE\",");
                try writeOptional(w, doctype.name);
                try w.writeByte(',');
                try writeOptional(w, doctype.public_identifier);
                try w.writeByte(',');
                try writeOptional(w, doctype.system_identifier);
                try w.writeAll(if (doctype.force_quirks) ",true" else ",false");
            },
            .start_tag, .end_tag => |tag| {
                try w.writeAll(if (kind == .start_tag) "[\"StartTag\"," else "[\"EndTag\",");
                try writeString(w, tag.name.units);
                try w.writeAll(",[");
                for (tag.attributes, 0..) |attribute, index| {
                    if (index != 0) try w.writeByte(',');
                    try w.writeByte('[');
                    try writeString(w, attribute.name.units);
                    try w.writeByte(',');
                    try writeString(w, attribute.value.units);
                    if (d.options.spans) {
                        try w.writeByte(',');
                        try writeSpan(w, attribute.name_span);
                        try w.writeByte(',');
                        if (attribute.value_span) |value_span| try writeSpan(w, value_span) else try w.writeAll("null");
                    }
                    try w.writeByte(']');
                }
                try w.writeAll(if (tag.self_closing) "],true" else "],false");
            },
            .comment => |data| {
                try w.writeAll("[\"Comment\",");
                try writeString(w, data.units);
            },
            .processing_instruction => |instruction| {
                try w.writeAll("[\"PI\",");
                try writeString(w, instruction.target.units);
                try w.writeByte(',');
                try writeString(w, instruction.data.units);
            },
            .end_of_file => try w.writeAll("[\"EOF\""),
            .characters => unreachable,
        }
        if (d.options.spans) {
            try w.writeByte(',');
            try writeSpan(w, span);
        }
        try w.writeAll("]\n");
        d.lines += 1;
    }
};

fn writeSpan(w: *Writer, span: Span) Writer.Error!void {
    try w.print("[{d},{d}]", .{ @backingInt(span.start.offset), @backingInt(span.end.offset) });
}

fn writeOptional(w: *Writer, view: ?View) Writer.Error!void {
    if (view) |v| try writeString(w, v.units) else try w.writeAll("null");
}

/// Writes `units` as a dump string.
pub fn writeString(w: *Writer, units: []const u16) Writer.Error!void {
    try w.writeByte('"');
    for (units) |unit| switch (unit) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        0x20...0x21, 0x23...0x5B, 0x5D...0x7E => try w.writeByte(@intCast(unit)),
        else => try w.print("\\u{X:0>4}", .{unit}),
    };
    try w.writeByte('"');
}
