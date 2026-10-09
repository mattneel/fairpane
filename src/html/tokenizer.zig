//! The HTML tokenizer of HTML Standard §13.2.5, at whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`.
//!
//! The tokenizer reads decoded UTF-16 code units in chunks and returns one step per call of `next`.
//! It reads the units as code points: a leading surrogate followed immediately by a trailing surrogate is one code point,
//! and every other surrogate unit is its own code point. It normalizes newlines as Infra "normalize newlines" defines,
//! and it reports the preprocessing errors of §13.2.3.5 when it first consumes each code point.
//!
//! It implements all 84 states of §13.2.5.1 to §13.2.5.84. Tree construction switches the tokenizer to the RCDATA, RAWTEXT,
//! script data, and PLAINTEXT states through `switchTo`, before the first call of `next` or right after a start tag token.
//!
//! A chunk boundary never changes the result. The tokenizer holds a CR or a leading surrogate at the end of the available input
//! until the next unit or `finish`, and its lookahead states keep their progress across calls of `next`.
//! It keeps only the input that it has not yet decided after it returns `need_input`.
//! `characterPosition` gives the source position of each code unit of the `characters` step that `next` last returned,
//! so that tree construction can report a parse error at a character's own position.

const std = @import("std");
const builtin = @import("builtin");
const web_string = @import("../web_string.zig");
const states = @import("states.zig");
const errors = @import("errors.zig");
const entities = @import("entities.zig");
const Allocator = std.mem.Allocator;

pub const View = web_string.View;
pub const CodeUnitIndex = web_string.CodeUnitIndex;
pub const State = states.State;
pub const ErrorCode = errors.ErrorCode;

/// A state that tree construction switches the tokenizer to (§13.2.6.2, §13.2.6.4.4, §13.2.6.4.7, and §13.4).
pub const ContentState = enum { rcdata, rawtext, script_data, plaintext };

pub const Error = error{ OutOfMemory, ChunkPending, InputFinished };

/// The errors of `switchTo`. `OutOfMemory` is the tokenizer's sticky failure; `SwitchNotAllowed` changes nothing.
pub const SwitchError = error{ OutOfMemory, SwitchNotAllowed };

pub const Step = union(enum) { token: Token, parse_error: ParseError, need_input };

pub const Token = struct { kind: Kind, span: Span };

pub const Kind = union(enum) {
    doctype: Doctype,
    start_tag: Tag,
    end_tag: Tag,
    comment: View,
    processing_instruction: ProcessingInstruction,
    characters: View,
    end_of_file,
};

/// A `null` field is missing, which differs from an empty view.
pub const Doctype = struct { name: ?View, public_identifier: ?View, system_identifier: ?View, force_quirks: bool };

pub const Tag = struct { name: View, attributes: []const Attribute, self_closing: bool };

/// `value_span` is null when the tokenizer never entered an attribute value state for the attribute.
pub const Attribute = struct { name: View, value: View, name_span: Span, value_span: ?Span };

pub const ProcessingInstruction = struct { target: View, data: View };

pub const ParseError = struct { code: ErrorCode, position: Position };

/// `offset` counts UTF-16 code units of the original input, before newline normalization.
/// `line` is 1 plus the number of line breaks that end at or before the offset, where a line break is CR LF, a lone CR, or LF.
/// `column` is 1 plus the number of code units between the end of the last such line break, or the input start, and the offset.
pub const Position = struct { offset: CodeUnitIndex, line: usize, column: usize };

pub const Span = struct { start: Position, end: Position };

/// Test builds count each executed branch of each state, in the flat order of `states.branchIndex`.
pub var coverage: if (builtin.is_test) [states.branch_count]u64 else void = if (builtin.is_test) @splat(0) else {};

inline fn hit(comptime state: State, comptime branch: []const u8) void {
    if (builtin.is_test) coverage[comptime states.branchIndex(state, branch)] += 1;
}

/// The end-of-file character, which is no code point.
const eof: u21 = 0x110000;

const replacement: u21 = 0xFFFD;

/// The number of pending character code units at which the tokenizer returns them as a step.
const text_flush_threshold = 4096;

/// How the code units of one `appendText` call map to source positions.
const Layout = enum {
    /// Every unit belongs to the one character at the record's position: an input character, which can be a CR LF pair
    /// or a surrogate pair, or a matched character reference, whose units all have the position of its `&`.
    shared,
    /// Each unit is an unconsumed source character of one code unit that is not a line break, re-emitted in source order
    /// from the record's position, such as a flushed `&#` or the `<`, `/`, and name of a possible end tag.
    sequential,
};

/// The source position of the units of one `appendText` call, which start at `index` in `text`.
const CharacterRecord = struct { index: usize, position: Position, layout: Layout };

/// The number of character records that the tokenizer reserves. Records exist only for the units of the runs that it has
/// queued but not yet returned, plus the step that `next` last returned. One action queues at most two characters runs,
/// and a run has at most `text_flush_threshold` + 1 records.
const character_record_capacity = 2 * (text_flush_threshold + 1);

/// The largest number of steps that one state action queues is 5: an end tag after pending characters,
/// a preprocessing error, and both end tag errors.
const queue_capacity = 8;

const Range = struct { start: usize, end: usize };

const Queued = union(enum) {
    step: Step,
    /// Characters in `text`, which become a view when the step is returned. `record` is the index of their first record.
    characters: struct { range: Range, span: Span, record: usize },
};

const AttributeRecord = struct { name: Range, value: Range, name_span: Span, value_span: ?Span };

/// The current input character.
const Char = struct { code_point: u21, position: Position };

const Peek = union(enum) { unit: u16, end, more };

pub const Tokenizer = struct {
    /// Whether there is an adjusted current node that is not an element in the HTML namespace (§13.2.4.2).
    /// Tree construction sets it before `next`. It defaults to false.
    /// The markup declaration open state reads it when the available input decides its `[CDATA[` branch.
    adjusted_current_node_is_foreign: bool = false,

    gpa: Allocator,

    // Input. The undecided units are `carry.items[carry_index..]` followed by `chunk[chunk_index..]`.
    carry: std.ArrayList(u16) = .empty,
    carry_index: usize = 0,
    chunk: []const u16 = &.{},
    chunk_index: usize = 0,
    borrowed: bool = false,
    finished: bool = false,
    /// The offset, line, and line start of the next unit to decode.
    offset: usize = 0,
    line: usize = 1,
    line_start: usize = 0,
    current: Char = .{ .code_point = eof, .position = .{ .offset = @fromBackingInt(0), .line = 1, .column = 1 } },
    reconsume: bool = false,

    // Machine.
    state: State = .data,
    return_state: State = .data,
    /// Whether an allocation failed. The tokenizer then returns `error.OutOfMemory` from every method except `deinit`.
    failed: bool = false,
    /// Whether `switchTo` may switch: before the first call of `next`, and after `next` returned a start tag token.
    switch_allowed: bool = true,
    eof_queued: bool = false,
    queue: [queue_capacity]Queued = undefined,
    queue_head: usize = 0,
    queue_len: usize = 0,

    // Character tokens. `text.items[text_flushed..]` is pending, and it spans `run_start` to `run_end`.
    text: std.ArrayList(u16) = .empty,
    text_flushed: usize = 0,
    run_start: Position = undefined,
    run_end: Position = undefined,
    /// One record per `appendText` call, in `text` order. The first call reserves the storage, and no later call allocates.
    /// `character_records.items[pending_record..]` are the records of the pending characters.
    character_records: std.ArrayList(CharacterRecord) = .empty,
    pending_record: usize = 0,
    /// The index in `text` of the first unit, and the index of the first record, of the `characters` step that `next`
    /// last returned.
    returned_characters: usize = 0,
    returned_record: usize = 0,

    /// The `<` that starts the current tag, comment, DOCTYPE, or processing instruction, or a possible end tag in a text state.
    markup_start: Position = undefined,

    /// The tag name of the last start tag token that the tokenizer emitted. It is empty before the first one,
    /// because a tag name is never empty. It has its own storage, because later tags reuse `tag_buffer`.
    last_start_tag: std.ArrayList(u16) = .empty,

    /// The first of the `]` characters that the CDATA section bracket and end states hold.
    bracket_start: Position = undefined,

    // The current tag token. `tag_buffer` holds its name and then each attribute's name and value.
    tag_buffer: std.ArrayList(u16) = .empty,
    tag_name_end: usize = 0,
    tag_is_end: bool = false,
    self_closing: bool = false,
    attributes: std.ArrayList(AttributeRecord) = .empty,
    /// Whether the duplicate attribute check removed the current attribute, which is the last record.
    attribute_removed: bool = false,
    attribute_views: std.ArrayList(Attribute) = .empty,

    comment: std.ArrayList(u16) = .empty,

    // The current DOCTYPE token, whose name, public identifier, and system identifier are built in that order.
    doctype_buffer: std.ArrayList(u16) = .empty,
    doctype_name: ?Range = null,
    public_identifier: ?Range = null,
    system_identifier: ?Range = null,
    force_quirks: bool = false,

    // The current processing instruction token: its target and then its data.
    instruction: std.ArrayList(u16) = .empty,
    target_end: usize = 0,

    // The temporary buffer, the character reference code, and the named character reference state's progress.
    temp: std.ArrayList(u16) = .empty,
    reference_start: Position = undefined,
    reference_code: u32 = 0,
    matcher: entities.Matcher = .{},
    matching: bool = false,
    scanning: bool = false,

    pub fn init(gpa: Allocator) Tokenizer {
        return .{ .gpa = gpa };
    }

    pub fn deinit(t: *Tokenizer) void {
        const gpa = t.gpa;
        t.carry.deinit(gpa);
        t.text.deinit(gpa);
        t.character_records.deinit(gpa);
        t.tag_buffer.deinit(gpa);
        t.attributes.deinit(gpa);
        t.attribute_views.deinit(gpa);
        t.comment.deinit(gpa);
        t.doctype_buffer.deinit(gpa);
        t.instruction.deinit(gpa);
        t.temp.deinit(gpa);
        t.last_start_tag.deinit(gpa);
        t.* = undefined;
    }

    /// Borrows `chunk` until `next` returns `need_input`, or until `deinit`. An empty chunk is valid.
    /// Neither `error.InputFinished` nor `error.ChunkPending` changes any state.
    pub fn feed(t: *Tokenizer, chunk: []const u16) Error!void {
        if (t.failed) return error.OutOfMemory;
        if (t.finished) return error.InputFinished;
        if (t.borrowed) return error.ChunkPending;
        t.chunk = chunk;
        t.chunk_index = 0;
        t.borrowed = true;
    }

    /// Marks the end of the input after any borrowed chunk. A second call does nothing.
    pub fn finish(t: *Tokenizer) Error!void {
        if (t.failed) return error.OutOfMemory;
        t.finished = true;
    }

    /// Returns one step. It returns `need_input` only before `finish`, when no further step is possible without more input,
    /// and null after the end-of-file token. A token's views stay valid until the next call of any method.
    /// After `error.OutOfMemory`, every later call except `deinit` returns it again.
    pub fn next(t: *Tokenizer) Error!?Step {
        if (t.failed) return error.OutOfMemory;
        t.switch_allowed = false;
        if (t.queue_len == 0) {
            if (t.eof_queued) return null;
            t.run() catch |err| return t.fail(err);
            if (t.queue_len == 0) {
                t.release() catch |err| return t.fail(err);
                return .need_input;
            }
        }
        const s = t.pop();
        // A start tag token is the last step of its action, so the tokenizer has queued no later step and consumed
        // no later character. A switch therefore applies to the next input character.
        t.switch_allowed = s == .token and s.token.kind == .start_tag;
        return s;
    }

    /// Switches the tokenizer to `state`, as tree construction does (§13.2.6.2, §13.2.6.4.4, §13.2.6.4.7, and §13.4).
    /// It succeeds before the first call of `next`, even after `feed` and `finish`, and after `next` returned a start tag
    /// token, until the next call of `next`. In that window, the last call decides. At any other time it returns
    /// `error.SwitchNotAllowed` and changes nothing. It allocates nothing.
    pub fn switchTo(t: *Tokenizer, state: ContentState) SwitchError!void {
        if (t.failed) return error.OutOfMemory;
        if (!t.switch_allowed) return error.SwitchNotAllowed;
        std.debug.assert(t.queue_len == 0 and !t.reconsume);
        t.state = switch (state) {
            .rcdata => .rcdata,
            .rawtext => .rawtext,
            .script_data => .script_data,
            .plaintext => .plaintext,
        };
    }

    fn fail(t: *Tokenizer, err: Allocator.Error) Allocator.Error {
        t.failed = true;
        return err;
    }

    // Steps.

    fn run(t: *Tokenizer) Allocator.Error!void {
        t.compactText();
        while (t.queue_len == 0) {
            if (!try t.step()) {
                t.flushText();
                return;
            }
        }
    }

    fn push(t: *Tokenizer, item: Queued) void {
        std.debug.assert(t.queue_len < queue_capacity);
        t.queue[(t.queue_head + t.queue_len) % queue_capacity] = item;
        t.queue_len += 1;
    }

    fn pop(t: *Tokenizer) Step {
        const item = t.queue[t.queue_head];
        t.queue_head = (t.queue_head + 1) % queue_capacity;
        t.queue_len -= 1;
        return switch (item) {
            .step => |s| s,
            .characters => |c| characters: {
                t.returned_characters = c.range.start;
                t.returned_record = c.record;
                break :characters .{ .token = .{
                    .kind = .{ .characters = .{ .units = t.text.items[c.range.start..c.range.end] } },
                    .span = c.span,
                } };
            },
        };
    }

    /// Returns the source position of the code unit at `index` of the `characters` step that `next` last returned,
    /// which must still be the last step that `next` returned. `index` must be less than the step's length.
    /// Each unit has the position of the character that it belongs to: the character itself, the CR of a CR LF pair,
    /// or the `&` of a matched character reference. A unit that stands for an unconsumed source character, such as a
    /// flushed `&#` or the `<`, `/`, and name of a possible end tag, has the position of that source character.
    /// It allocates nothing, and its binary search takes time logarithmic in the step's length.
    pub fn characterPosition(t: *const Tokenizer, index: usize) Position {
        const target = t.returned_characters + index;
        const records = t.character_records.items;
        // Each record holds at least one unit, so the step's records are among the `index + 1` from its first one.
        var low = t.returned_record;
        var high = @min(records.len, t.returned_record + index + 1);
        std.debug.assert(low < high and records[low].index <= target);
        while (high - low > 1) {
            const middle = low + (high - low) / 2;
            if (records[middle].index <= target) low = middle else high = middle;
        }
        const record = records[low];
        return switch (record.layout) {
            .shared => record.position,
            .sequential => sequential: {
                const delta = target - record.index;
                break :sequential .{
                    .offset = @fromBackingInt(@backingInt(record.position.offset) + delta),
                    .line = record.position.line,
                    .column = record.position.column + delta,
                };
            },
        };
    }

    /// Queues a step after any pending characters.
    fn queueStep(t: *Tokenizer, s: Step) void {
        t.flushText();
        t.push(.{ .step = s });
    }

    fn parseError(t: *Tokenizer, code: ErrorCode, position: Position) void {
        t.queueStep(.{ .parse_error = .{ .code = code, .position = position } });
    }

    /// Reports `code` at the current input character.
    fn raise(t: *Tokenizer, code: ErrorCode) void {
        t.parseError(code, t.current.position);
    }

    fn queueToken(t: *Tokenizer, kind: Kind, start: Position, end: Position) void {
        t.queueStep(.{ .token = .{ .kind = kind, .span = .{ .start = start, .end = end } } });
    }

    fn emitEof(t: *Tokenizer) void {
        t.queueToken(.end_of_file, t.current.position, t.current.position);
        t.eof_queued = true;
    }

    /// Queues the pending characters as one step.
    fn flushText(t: *Tokenizer) void {
        if (t.text.items.len == t.text_flushed) return;
        t.push(.{ .characters = .{
            .range = .{ .start = t.text_flushed, .end = t.text.items.len },
            .span = .{ .start = t.run_start, .end = t.run_end },
            .record = t.pending_record,
        } });
        t.text_flushed = t.text.items.len;
        t.pending_record = t.character_records.items.len;
    }

    /// Discards returned characters and their records, and keeps pending ones. Every queued step has been returned.
    fn compactText(t: *Tokenizer) void {
        const pending = t.text.items.len - t.text_flushed;
        std.mem.copyForwards(u16, t.text.items[0..pending], t.text.items[t.text_flushed..]);
        t.text.shrinkRetainingCapacity(pending);
        const records = t.character_records.items;
        const kept = records.len - t.pending_record;
        std.mem.copyForwards(CharacterRecord, records[0..kept], records[t.pending_record..]);
        for (records[0..kept]) |*record| record.index -= t.text_flushed;
        t.character_records.shrinkRetainingCapacity(kept);
        t.pending_record = 0;
        t.text_flushed = 0;
    }

    /// Appends the units of character tokens that span `start` to `end`, and records their source positions.
    fn appendText(t: *Tokenizer, units: []const u16, start: Position, end: Position, layout: Layout) Allocator.Error!void {
        std.debug.assert(units.len != 0);
        if (t.character_records.capacity == 0) {
            try t.character_records.ensureTotalCapacityPrecise(t.gpa, character_record_capacity);
        }
        if (t.text.items.len == t.text_flushed) t.run_start = start;
        const index = t.text.items.len;
        try t.text.appendSlice(t.gpa, units);
        t.character_records.appendAssumeCapacity(.{ .index = index, .position = start, .layout = layout });
        t.run_end = end;
        if (t.text.items.len - t.text_flushed >= text_flush_threshold) t.flushText();
    }

    /// Emits a character token for `code_point` that spans `start` to `end`.
    fn emitCharacter(t: *Tokenizer, code_point: u21, start: Position, end: Position) Allocator.Error!void {
        var units: [2]u16 = undefined;
        try t.appendText(units[0..encode(code_point, &units)], start, end, .shared);
    }

    /// Emits the current input character as a character token that spans its own code units.
    fn emitCurrent(t: *Tokenizer) Allocator.Error!void {
        try t.emitCharacter(t.current.code_point, t.current.position, t.cursor());
    }

    /// Emits a U+003C or U+002F character token that spans the one source character at `position`.
    fn emitSource(t: *Tokenizer, code_point: u21, position: Position) Allocator.Error!void {
        try t.emitCharacter(code_point, position, after(position));
    }

    // Input.

    /// Returns the unit `index` places after the next unit to decode.
    fn peek(t: *const Tokenizer, index: usize) Peek {
        const carried = t.carry.items.len - t.carry_index;
        if (index < carried) return .{ .unit = t.carry.items[t.carry_index + index] };
        const position = t.chunk_index + (index - carried);
        if (position < t.chunk.len) return .{ .unit = t.chunk[position] };
        return if (t.finished) .end else .more;
    }

    fn advance(t: *Tokenizer, count: usize) void {
        for (0..count) |_| {
            if (t.carry_index < t.carry.items.len) {
                t.carry_index += 1;
                if (t.carry_index == t.carry.items.len) {
                    t.carry.clearRetainingCapacity();
                    t.carry_index = 0;
                }
            } else {
                t.chunk_index += 1;
            }
        }
        t.offset += count;
    }

    /// The position of the next unit to decode.
    fn cursor(t: *const Tokenizer) Position {
        return .{ .offset = @fromBackingInt(t.offset), .line = t.line, .column = t.offset - t.line_start + 1 };
    }

    /// Consumes the next input character and returns it, or returns null when the available input does not decide it.
    /// A code point is decoded and checked by preprocessing once: a reconsumed character returns without either.
    fn consume(t: *Tokenizer) ?u21 {
        if (t.reconsume) {
            t.reconsume = false;
            return t.current.code_point;
        }
        const first = switch (t.peek(0)) {
            .more => return null,
            .end => {
                t.current = .{ .code_point = eof, .position = t.cursor() };
                return eof;
            },
            .unit => |unit| unit,
        };
        var code_point: u21 = first;
        var len: usize = 1;
        switch (first) {
            '\r' => {
                switch (t.peek(1)) {
                    .more => return null,
                    .end => {},
                    .unit => |unit| if (unit == '\n') {
                        len = 2;
                    },
                }
                code_point = '\n';
            },
            0xD800...0xDBFF => switch (t.peek(1)) {
                .more => return null,
                .end => {},
                .unit => |unit| if (unit >= 0xDC00 and unit <= 0xDFFF) {
                    code_point = 0x10000 + ((@as(u21, first) - 0xD800) << 10) + (@as(u21, unit) - 0xDC00);
                    len = 2;
                },
            },
            else => {},
        }
        t.current = .{ .code_point = code_point, .position = t.cursor() };
        t.advance(len);
        if (code_point == '\n') {
            t.line += 1;
            t.line_start = t.offset;
        }
        if (preprocessingError(code_point)) |code| t.parseError(code, t.current.position);
        return code_point;
    }

    /// Consumes `count` characters that a lookahead matched. Each is an ASCII letter, an ASCII digit, `-`, `[`, or `;`, which preprocessing never reports.
    fn consumeMatched(t: *Tokenizer, count: usize) void {
        for (0..count) |_| _ = t.consume().?;
    }

    /// Stops borrowing the chunk and keeps its undecided units.
    fn release(t: *Tokenizer) Allocator.Error!void {
        if (!t.borrowed) return;
        const rest = t.chunk[t.chunk_index..];
        if (rest.len != 0) {
            const kept = t.carry.items.len - t.carry_index;
            std.mem.copyForwards(u16, t.carry.items[0..kept], t.carry.items[t.carry_index..]);
            t.carry.shrinkRetainingCapacity(kept);
            t.carry_index = 0;
            try t.carry.appendSlice(t.gpa, rest);
        }
        t.chunk = &.{};
        t.chunk_index = 0;
        t.borrowed = false;
    }

    // Tokens.

    fn createTag(t: *Tokenizer, is_end: bool) void {
        t.tag_buffer.clearRetainingCapacity();
        t.tag_name_end = 0;
        t.tag_is_end = is_end;
        t.self_closing = false;
        t.attributes.clearRetainingCapacity();
        t.attribute_removed = false;
    }

    fn appendTagName(t: *Tokenizer, code_point: u21) Allocator.Error!void {
        try appendCodePoint(&t.tag_buffer, t.gpa, code_point);
        t.tag_name_end = t.tag_buffer.items.len;
    }

    /// Drops the current attribute when the duplicate attribute check removed it.
    fn finishAttribute(t: *Tokenizer) void {
        if (!t.attribute_removed) return;
        const removed = t.attributes.pop().?;
        t.tag_buffer.shrinkRetainingCapacity(removed.name.start);
        t.attribute_removed = false;
    }

    /// Starts a new attribute in the current tag token, whose name begins with the current input character.
    fn startAttribute(t: *Tokenizer) Allocator.Error!void {
        t.finishAttribute();
        const here = t.tag_buffer.items.len;
        try t.attributes.append(t.gpa, .{
            .name = .{ .start = here, .end = here },
            .value = .{ .start = here, .end = here },
            .name_span = .{ .start = t.current.position, .end = t.current.position },
            .value_span = null,
        });
    }

    fn currentAttribute(t: *Tokenizer) *AttributeRecord {
        return &t.attributes.items[t.attributes.items.len - 1];
    }

    fn appendAttributeName(t: *Tokenizer, code_point: u21) Allocator.Error!void {
        try appendCodePoint(&t.tag_buffer, t.gpa, code_point);
        t.currentAttribute().name.end = t.tag_buffer.items.len;
    }

    fn appendAttributeValue(t: *Tokenizer, units: []const u16) Allocator.Error!void {
        try t.tag_buffer.appendSlice(t.gpa, units);
        t.currentAttribute().value.end = t.tag_buffer.items.len;
    }

    fn appendAttributeValueCodePoint(t: *Tokenizer, code_point: u21) Allocator.Error!void {
        var units: [2]u16 = undefined;
        try t.appendAttributeValue(units[0..encode(code_point, &units)]);
    }

    /// Completes the attribute name when the attribute name state is left, and runs the duplicate attribute check.
    /// The current input character is the character whose consumption leaves the state.
    fn leaveAttributeName(t: *Tokenizer) void {
        const record = t.currentAttribute();
        const here = t.tag_buffer.items.len;
        record.name_span.end = t.current.position;
        record.value = .{ .start = here, .end = here };
        const name = t.tag_buffer.items[record.name.start..record.name.end];
        for (t.attributes.items[0 .. t.attributes.items.len - 1]) |other| {
            if (std.mem.eql(u16, t.tag_buffer.items[other.name.start..other.name.end], name)) {
                t.raise(.duplicate_attribute);
                t.attribute_removed = true;
                return;
            }
        }
    }

    fn startValue(t: *Tokenizer, start: Position) void {
        t.currentAttribute().value_span = .{ .start = start, .end = start };
    }

    fn endValue(t: *Tokenizer) void {
        t.currentAttribute().value_span.?.end = t.current.position;
    }

    /// Emits the current tag token, which ends after the current input character.
    /// A start tag's name becomes the last start tag name, which decides whether a later end tag token is appropriate.
    fn emitTag(t: *Tokenizer) Allocator.Error!void {
        t.finishAttribute();
        const buffer = t.tag_buffer.items;
        if (t.tag_is_end) {
            if (t.attributes.items.len != 0) t.raise(.end_tag_with_attributes);
            if (t.self_closing) t.raise(.end_tag_with_trailing_solidus);
        } else {
            // The record allocates only when it grows.
            t.last_start_tag.clearRetainingCapacity();
            try t.last_start_tag.appendSlice(t.gpa, buffer[0..t.tag_name_end]);
        }
        t.attribute_views.clearRetainingCapacity();
        try t.attribute_views.ensureTotalCapacity(t.gpa, t.attributes.items.len);
        for (t.attributes.items) |record| t.attribute_views.appendAssumeCapacity(.{
            .name = .{ .units = buffer[record.name.start..record.name.end] },
            .value = .{ .units = buffer[record.value.start..record.value.end] },
            .name_span = record.name_span,
            .value_span = record.value_span,
        });
        const tag: Tag = .{
            .name = .{ .units = buffer[0..t.tag_name_end] },
            .attributes = t.attribute_views.items,
            .self_closing = t.self_closing,
        };
        t.queueToken(if (t.tag_is_end) .{ .end_tag = tag } else .{ .start_tag = tag }, t.markup_start, t.cursor());
    }

    fn createComment(t: *Tokenizer) void {
        t.comment.clearRetainingCapacity();
    }

    fn appendComment(t: *Tokenizer, code_point: u21) Allocator.Error!void {
        try appendCodePoint(&t.comment, t.gpa, code_point);
    }

    fn appendCommentText(t: *Tokenizer, text: []const u8) Allocator.Error!void {
        for (text) |c| try t.comment.append(t.gpa, c);
    }

    /// Emits the current comment token after the current input character, or at the input length for EOF.
    fn emitComment(t: *Tokenizer) void {
        const end = if (t.current.code_point == eof) t.current.position else t.cursor();
        t.queueToken(.{ .comment = .{ .units = t.comment.items } }, t.markup_start, end);
    }

    /// Converts the temporary buffer to a comment.
    fn temporaryBufferToComment(t: *Tokenizer) Allocator.Error!void {
        t.createComment();
        try t.comment.append(t.gpa, '?');
        try t.comment.appendSlice(t.gpa, t.temp.items);
    }

    fn createDoctype(t: *Tokenizer) void {
        t.doctype_buffer.clearRetainingCapacity();
        t.doctype_name = null;
        t.public_identifier = null;
        t.system_identifier = null;
        t.force_quirks = false;
    }

    /// Sets a DOCTYPE field to the empty string, not missing.
    fn startDoctypeField(t: *Tokenizer, field: *?Range) void {
        const here = t.doctype_buffer.items.len;
        field.* = .{ .start = here, .end = here };
    }

    fn appendDoctypeField(t: *Tokenizer, field: *?Range, code_point: u21) Allocator.Error!void {
        try appendCodePoint(&t.doctype_buffer, t.gpa, code_point);
        field.*.?.end = t.doctype_buffer.items.len;
    }

    fn doctypeView(t: *Tokenizer, field: ?Range) ?View {
        const range = field orelse return null;
        return .{ .units = t.doctype_buffer.items[range.start..range.end] };
    }

    /// Emits the current DOCTYPE token after the current input character, or at the input length for EOF.
    fn emitDoctype(t: *Tokenizer) void {
        const end = if (t.current.code_point == eof) t.current.position else t.cursor();
        t.queueToken(.{ .doctype = .{
            .name = t.doctypeView(t.doctype_name),
            .public_identifier = t.doctypeView(t.public_identifier),
            .system_identifier = t.doctypeView(t.system_identifier),
            .force_quirks = t.force_quirks,
        } }, t.markup_start, end);
    }

    /// Sets the force-quirks flag, emits the current DOCTYPE token, and emits an end-of-file token.
    fn eofInDoctype(t: *Tokenizer) void {
        t.raise(.eof_in_doctype);
        t.force_quirks = true;
        t.emitDoctype();
        t.emitEof();
    }

    fn emitInstruction(t: *Tokenizer) void {
        const units = t.instruction.items;
        t.queueToken(.{ .processing_instruction = .{
            .target = .{ .units = units[0..t.target_end] },
            .data = .{ .units = units[t.target_end..] },
        } }, t.markup_start, t.cursor());
    }

    /// Flushes code points consumed as a character reference: the temporary buffer. `layout` is `.shared` for the code
    /// points of a matched reference and `.sequential` for unconsumed source characters, such as `&#`.
    fn flushReference(t: *Tokenizer, layout: Layout) Allocator.Error!void {
        if (inAttribute(t.return_state)) return t.appendAttributeValue(t.temp.items);
        // The code points span from the `&` to the next input character that the return state consumes.
        const end = if (t.reconsume) t.current.position else t.cursor();
        try t.appendText(t.temp.items, t.reference_start, end, layout);
    }

    fn setTemp(t: *Tokenizer, units: []const u16) Allocator.Error!void {
        t.temp.clearRetainingCapacity();
        try t.temp.appendSlice(t.gpa, units);
    }

    /// Switches to the character reference state from the state `from`, whose `&` is the current input character.
    fn startReference(t: *Tokenizer, from: State) void {
        t.return_state = from;
        t.reference_start = t.current.position;
        t.state = .character_reference;
    }

    fn reconsumeIn(t: *Tokenizer, state: State) void {
        t.reconsume = true;
        t.state = state;
    }

    // The state machine.

    /// Runs one action of the current state. Returns false, with no effect, when the action needs more input.
    fn step(t: *Tokenizer) Allocator.Error!bool {
        switch (t.state) {
            .markup_declaration_open => return t.markupDeclarationOpen(),
            .named_character_reference => return t.namedCharacterReference(),
            .numeric_character_reference_end => {
                try t.numericCharacterReferenceEnd();
                return true;
            },
            .character_reference => try t.setTemp(&.{'&'}),
            .numeric_character_reference => t.reference_code = 0,
            else => {},
        }
        const c = t.consume() orelse return false;
        switch (t.state) {
            .data => switch (c) {
                '&' => {
                    hit(.data, "&");
                    t.startReference(.data);
                },
                '<' => {
                    hit(.data, "<");
                    t.markup_start = t.current.position;
                    t.state = .tag_open;
                },
                0 => {
                    hit(.data, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.emitCurrent();
                },
                eof => {
                    hit(.data, "EOF");
                    t.emitEof();
                },
                else => {
                    hit(.data, "else");
                    try t.emitCurrent();
                },
            },
            .rcdata => switch (c) {
                '&' => {
                    hit(.rcdata, "&");
                    t.startReference(.rcdata);
                },
                '<' => {
                    hit(.rcdata, "<");
                    t.markup_start = t.current.position;
                    t.state = .rcdata_less_than_sign;
                },
                0 => {
                    hit(.rcdata, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.rcdata, "EOF");
                    t.emitEof();
                },
                else => {
                    hit(.rcdata, "else");
                    try t.emitCurrent();
                },
            },
            .rawtext => switch (c) {
                '<' => {
                    hit(.rawtext, "<");
                    t.markup_start = t.current.position;
                    t.state = .rawtext_less_than_sign;
                },
                0 => {
                    hit(.rawtext, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.rawtext, "EOF");
                    t.emitEof();
                },
                else => {
                    hit(.rawtext, "else");
                    try t.emitCurrent();
                },
            },
            .script_data => switch (c) {
                '<' => {
                    hit(.script_data, "<");
                    t.markup_start = t.current.position;
                    t.state = .script_data_less_than_sign;
                },
                0 => {
                    hit(.script_data, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data, "EOF");
                    t.emitEof();
                },
                else => {
                    hit(.script_data, "else");
                    try t.emitCurrent();
                },
            },
            .plaintext => switch (c) {
                0 => {
                    hit(.plaintext, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.plaintext, "EOF");
                    t.emitEof();
                },
                else => {
                    hit(.plaintext, "else");
                    try t.emitCurrent();
                },
            },
            .tag_open => switch (c) {
                '!' => {
                    hit(.tag_open, "!");
                    t.state = .markup_declaration_open;
                },
                '/' => {
                    hit(.tag_open, "/");
                    t.state = .end_tag_open;
                },
                'A'...'Z', 'a'...'z' => {
                    hit(.tag_open, "ASCII alpha");
                    t.createTag(false);
                    t.reconsumeIn(.tag_name);
                },
                '?' => {
                    hit(.tag_open, "?");
                    t.temp.clearRetainingCapacity();
                    t.state = .processing_instruction_open;
                },
                eof => {
                    hit(.tag_open, "EOF");
                    t.raise(.eof_before_tag_name);
                    try t.emitSource('<', t.markup_start);
                    t.emitEof();
                },
                else => {
                    hit(.tag_open, "else");
                    t.raise(.invalid_first_character_of_tag_name);
                    try t.emitSource('<', t.markup_start);
                    t.reconsumeIn(.data);
                },
            },
            .end_tag_open => switch (c) {
                'A'...'Z', 'a'...'z' => {
                    hit(.end_tag_open, "ASCII alpha");
                    t.createTag(true);
                    t.reconsumeIn(.tag_name);
                },
                '>' => {
                    hit(.end_tag_open, ">");
                    t.raise(.missing_end_tag_name);
                    t.state = .data;
                },
                eof => {
                    hit(.end_tag_open, "EOF");
                    t.raise(.eof_before_tag_name);
                    try t.emitSource('<', t.markup_start);
                    try t.emitSource('/', after(t.markup_start));
                    t.emitEof();
                },
                else => {
                    hit(.end_tag_open, "else");
                    t.raise(.invalid_first_character_of_tag_name);
                    t.createComment();
                    t.reconsumeIn(.bogus_comment);
                },
            },
            .tag_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.tag_name, "whitespace");
                    t.state = .before_attribute_name;
                },
                '/' => {
                    hit(.tag_name, "/");
                    t.state = .self_closing_start_tag;
                },
                '>' => {
                    hit(.tag_name, ">");
                    t.state = .data;
                    try t.emitTag();
                },
                'A'...'Z' => {
                    hit(.tag_name, "ASCII upper alpha");
                    try t.appendTagName(c + 0x20);
                },
                0 => {
                    hit(.tag_name, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendTagName(replacement);
                },
                eof => {
                    hit(.tag_name, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.tag_name, "else");
                    try t.appendTagName(c);
                },
            },
            .rcdata_less_than_sign => try t.textLessThanSign(.rcdata_less_than_sign, .rcdata, .rcdata_end_tag_open, c),
            .rcdata_end_tag_open => try t.textEndTagOpen(.rcdata_end_tag_open, .rcdata, .rcdata_end_tag_name, c),
            .rcdata_end_tag_name => try t.textEndTagName(.rcdata_end_tag_name, .rcdata, c),
            .rawtext_less_than_sign => try t.textLessThanSign(.rawtext_less_than_sign, .rawtext, .rawtext_end_tag_open, c),
            .rawtext_end_tag_open => try t.textEndTagOpen(.rawtext_end_tag_open, .rawtext, .rawtext_end_tag_name, c),
            .rawtext_end_tag_name => try t.textEndTagName(.rawtext_end_tag_name, .rawtext, c),
            .script_data_less_than_sign => switch (c) {
                '/' => {
                    hit(.script_data_less_than_sign, "/");
                    t.temp.clearRetainingCapacity();
                    t.state = .script_data_end_tag_open;
                },
                '!' => {
                    hit(.script_data_less_than_sign, "!");
                    t.state = .script_data_escape_start;
                    try t.emitSource('<', t.markup_start);
                    try t.emitCurrent();
                },
                else => {
                    hit(.script_data_less_than_sign, "else");
                    try t.emitSource('<', t.markup_start);
                    t.reconsumeIn(.script_data);
                },
            },
            .script_data_end_tag_open => try t.textEndTagOpen(.script_data_end_tag_open, .script_data, .script_data_end_tag_name, c),
            .script_data_end_tag_name => try t.textEndTagName(.script_data_end_tag_name, .script_data, c),
            .script_data_escape_start => switch (c) {
                '-' => {
                    hit(.script_data_escape_start, "-");
                    t.state = .script_data_escape_start_dash;
                    try t.emitCurrent();
                },
                else => {
                    hit(.script_data_escape_start, "else");
                    t.reconsumeIn(.script_data);
                },
            },
            .script_data_escape_start_dash => switch (c) {
                '-' => {
                    hit(.script_data_escape_start_dash, "-");
                    t.state = .script_data_escaped_dash_dash;
                    try t.emitCurrent();
                },
                else => {
                    hit(.script_data_escape_start_dash, "else");
                    t.reconsumeIn(.script_data);
                },
            },
            .script_data_escaped => switch (c) {
                '-' => {
                    hit(.script_data_escaped, "-");
                    t.state = .script_data_escaped_dash;
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_escaped, "<");
                    t.markup_start = t.current.position;
                    t.state = .script_data_escaped_less_than_sign;
                },
                0 => {
                    hit(.script_data_escaped, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_escaped, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_escaped, "else");
                    try t.emitCurrent();
                },
            },
            .script_data_escaped_dash => switch (c) {
                '-' => {
                    hit(.script_data_escaped_dash, "-");
                    t.state = .script_data_escaped_dash_dash;
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_escaped_dash, "<");
                    t.markup_start = t.current.position;
                    t.state = .script_data_escaped_less_than_sign;
                },
                0 => {
                    hit(.script_data_escaped_dash, "NULL");
                    t.state = .script_data_escaped;
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_escaped_dash, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_escaped_dash, "else");
                    t.state = .script_data_escaped;
                    try t.emitCurrent();
                },
            },
            .script_data_escaped_dash_dash => switch (c) {
                '-' => {
                    hit(.script_data_escaped_dash_dash, "-");
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_escaped_dash_dash, "<");
                    t.markup_start = t.current.position;
                    t.state = .script_data_escaped_less_than_sign;
                },
                '>' => {
                    hit(.script_data_escaped_dash_dash, ">");
                    t.state = .script_data;
                    try t.emitCurrent();
                },
                0 => {
                    hit(.script_data_escaped_dash_dash, "NULL");
                    t.state = .script_data_escaped;
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_escaped_dash_dash, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_escaped_dash_dash, "else");
                    t.state = .script_data_escaped;
                    try t.emitCurrent();
                },
            },
            .script_data_escaped_less_than_sign => switch (c) {
                '/' => {
                    hit(.script_data_escaped_less_than_sign, "/");
                    t.temp.clearRetainingCapacity();
                    t.state = .script_data_escaped_end_tag_open;
                },
                'A'...'Z', 'a'...'z' => {
                    hit(.script_data_escaped_less_than_sign, "ASCII alpha");
                    t.temp.clearRetainingCapacity();
                    try t.emitSource('<', t.markup_start);
                    t.reconsumeIn(.script_data_double_escape_start);
                },
                else => {
                    hit(.script_data_escaped_less_than_sign, "else");
                    try t.emitSource('<', t.markup_start);
                    t.reconsumeIn(.script_data_escaped);
                },
            },
            .script_data_escaped_end_tag_open => try t.textEndTagOpen(
                .script_data_escaped_end_tag_open,
                .script_data_escaped,
                .script_data_escaped_end_tag_name,
                c,
            ),
            .script_data_escaped_end_tag_name => try t.textEndTagName(.script_data_escaped_end_tag_name, .script_data_escaped, c),
            .script_data_double_escape_start => try t.doubleEscapeBoundary(
                .script_data_double_escape_start,
                .script_data_double_escaped,
                .script_data_escaped,
                c,
            ),
            .script_data_double_escaped => switch (c) {
                '-' => {
                    hit(.script_data_double_escaped, "-");
                    t.state = .script_data_double_escaped_dash;
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_double_escaped, "<");
                    t.state = .script_data_double_escaped_less_than_sign;
                    try t.emitCurrent();
                },
                0 => {
                    hit(.script_data_double_escaped, "NULL");
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_double_escaped, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_double_escaped, "else");
                    try t.emitCurrent();
                },
            },
            .script_data_double_escaped_dash => switch (c) {
                '-' => {
                    hit(.script_data_double_escaped_dash, "-");
                    t.state = .script_data_double_escaped_dash_dash;
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_double_escaped_dash, "<");
                    t.state = .script_data_double_escaped_less_than_sign;
                    try t.emitCurrent();
                },
                0 => {
                    hit(.script_data_double_escaped_dash, "NULL");
                    t.state = .script_data_double_escaped;
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_double_escaped_dash, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_double_escaped_dash, "else");
                    t.state = .script_data_double_escaped;
                    try t.emitCurrent();
                },
            },
            .script_data_double_escaped_dash_dash => switch (c) {
                '-' => {
                    hit(.script_data_double_escaped_dash_dash, "-");
                    try t.emitCurrent();
                },
                '<' => {
                    hit(.script_data_double_escaped_dash_dash, "<");
                    t.state = .script_data_double_escaped_less_than_sign;
                    try t.emitCurrent();
                },
                '>' => {
                    hit(.script_data_double_escaped_dash_dash, ">");
                    t.state = .script_data;
                    try t.emitCurrent();
                },
                0 => {
                    hit(.script_data_double_escaped_dash_dash, "NULL");
                    t.state = .script_data_double_escaped;
                    try t.emitReplacement();
                },
                eof => {
                    hit(.script_data_double_escaped_dash_dash, "EOF");
                    t.eofInScriptComment();
                },
                else => {
                    hit(.script_data_double_escaped_dash_dash, "else");
                    t.state = .script_data_double_escaped;
                    try t.emitCurrent();
                },
            },
            .script_data_double_escaped_less_than_sign => switch (c) {
                '/' => {
                    hit(.script_data_double_escaped_less_than_sign, "/");
                    t.temp.clearRetainingCapacity();
                    t.state = .script_data_double_escape_end;
                    try t.emitCurrent();
                },
                else => {
                    hit(.script_data_double_escaped_less_than_sign, "else");
                    t.reconsumeIn(.script_data_double_escaped);
                },
            },
            .script_data_double_escape_end => try t.doubleEscapeBoundary(
                .script_data_double_escape_end,
                .script_data_escaped,
                .script_data_double_escaped,
                c,
            ),
            .before_attribute_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.before_attribute_name, "whitespace"),
                '/', '>', eof => {
                    hit(.before_attribute_name, "/ or > or EOF");
                    t.reconsumeIn(.after_attribute_name);
                },
                '=' => {
                    hit(.before_attribute_name, "=");
                    t.raise(.unexpected_equals_sign_before_attribute_name);
                    try t.startAttribute();
                    try t.appendAttributeName(c);
                    t.state = .attribute_name;
                },
                else => {
                    hit(.before_attribute_name, "else");
                    try t.startAttribute();
                    t.reconsumeIn(.attribute_name);
                },
            },
            .attribute_name => switch (c) {
                '\t', '\n', 0x0C, ' ', '/', '>', eof => {
                    hit(.attribute_name, "whitespace or / or > or EOF");
                    t.leaveAttributeName();
                    t.reconsumeIn(.after_attribute_name);
                },
                '=' => {
                    hit(.attribute_name, "=");
                    t.leaveAttributeName();
                    t.state = .before_attribute_value;
                },
                'A'...'Z' => {
                    hit(.attribute_name, "ASCII upper alpha");
                    try t.appendAttributeName(c + 0x20);
                },
                0 => {
                    hit(.attribute_name, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendAttributeName(replacement);
                },
                '"', '\'', '<' => {
                    hit(.attribute_name, "\" or ' or <");
                    t.raise(.unexpected_character_in_attribute_name);
                    try t.appendAttributeName(c);
                },
                else => {
                    hit(.attribute_name, "else");
                    try t.appendAttributeName(c);
                },
            },
            .after_attribute_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.after_attribute_name, "whitespace"),
                '/' => {
                    hit(.after_attribute_name, "/");
                    t.state = .self_closing_start_tag;
                },
                '=' => {
                    hit(.after_attribute_name, "=");
                    t.state = .before_attribute_value;
                },
                '>' => {
                    hit(.after_attribute_name, ">");
                    t.state = .data;
                    try t.emitTag();
                },
                eof => {
                    hit(.after_attribute_name, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.after_attribute_name, "else");
                    try t.startAttribute();
                    t.reconsumeIn(.attribute_name);
                },
            },
            .before_attribute_value => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.before_attribute_value, "whitespace"),
                '"' => {
                    hit(.before_attribute_value, "\"");
                    t.startValue(t.cursor());
                    t.state = .attribute_value_double_quoted;
                },
                '\'' => {
                    hit(.before_attribute_value, "'");
                    t.startValue(t.cursor());
                    t.state = .attribute_value_single_quoted;
                },
                '>' => {
                    hit(.before_attribute_value, ">");
                    t.raise(.missing_attribute_value);
                    t.state = .data;
                    try t.emitTag();
                },
                else => {
                    hit(.before_attribute_value, "else");
                    t.startValue(t.current.position);
                    t.reconsumeIn(.attribute_value_unquoted);
                },
            },
            .attribute_value_double_quoted => switch (c) {
                '"' => {
                    hit(.attribute_value_double_quoted, "\"");
                    t.endValue();
                    t.state = .after_attribute_value_quoted;
                },
                '&' => {
                    hit(.attribute_value_double_quoted, "&");
                    t.startReference(.attribute_value_double_quoted);
                },
                0 => {
                    hit(.attribute_value_double_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendAttributeValueCodePoint(replacement);
                },
                eof => {
                    hit(.attribute_value_double_quoted, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.attribute_value_double_quoted, "else");
                    try t.appendAttributeValueCodePoint(c);
                },
            },
            .attribute_value_single_quoted => switch (c) {
                '\'' => {
                    hit(.attribute_value_single_quoted, "'");
                    t.endValue();
                    t.state = .after_attribute_value_quoted;
                },
                '&' => {
                    hit(.attribute_value_single_quoted, "&");
                    t.startReference(.attribute_value_single_quoted);
                },
                0 => {
                    hit(.attribute_value_single_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendAttributeValueCodePoint(replacement);
                },
                eof => {
                    hit(.attribute_value_single_quoted, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.attribute_value_single_quoted, "else");
                    try t.appendAttributeValueCodePoint(c);
                },
            },
            .attribute_value_unquoted => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.attribute_value_unquoted, "whitespace");
                    t.endValue();
                    t.state = .before_attribute_name;
                },
                '&' => {
                    hit(.attribute_value_unquoted, "&");
                    t.startReference(.attribute_value_unquoted);
                },
                '>' => {
                    hit(.attribute_value_unquoted, ">");
                    t.endValue();
                    t.state = .data;
                    try t.emitTag();
                },
                0 => {
                    hit(.attribute_value_unquoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendAttributeValueCodePoint(replacement);
                },
                '"', '\'', '<', '=', '`' => {
                    hit(.attribute_value_unquoted, "\" or ' or < or = or `");
                    t.raise(.unexpected_character_in_unquoted_attribute_value);
                    try t.appendAttributeValueCodePoint(c);
                },
                eof => {
                    hit(.attribute_value_unquoted, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.attribute_value_unquoted, "else");
                    try t.appendAttributeValueCodePoint(c);
                },
            },
            .after_attribute_value_quoted => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.after_attribute_value_quoted, "whitespace");
                    t.state = .before_attribute_name;
                },
                '/' => {
                    hit(.after_attribute_value_quoted, "/");
                    t.state = .self_closing_start_tag;
                },
                '>' => {
                    hit(.after_attribute_value_quoted, ">");
                    t.state = .data;
                    try t.emitTag();
                },
                eof => {
                    hit(.after_attribute_value_quoted, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.after_attribute_value_quoted, "else");
                    t.raise(.missing_whitespace_between_attributes);
                    t.reconsumeIn(.before_attribute_name);
                },
            },
            .self_closing_start_tag => switch (c) {
                '>' => {
                    hit(.self_closing_start_tag, ">");
                    t.self_closing = true;
                    t.state = .data;
                    try t.emitTag();
                },
                eof => {
                    hit(.self_closing_start_tag, "EOF");
                    t.raise(.eof_in_tag);
                    t.emitEof();
                },
                else => {
                    hit(.self_closing_start_tag, "else");
                    t.raise(.unexpected_solidus_in_tag);
                    t.reconsumeIn(.before_attribute_name);
                },
            },
            .bogus_comment => switch (c) {
                '>' => {
                    hit(.bogus_comment, ">");
                    t.state = .data;
                    t.emitComment();
                },
                eof => {
                    hit(.bogus_comment, "EOF");
                    t.emitComment();
                    t.emitEof();
                },
                0 => {
                    hit(.bogus_comment, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendComment(replacement);
                },
                else => {
                    hit(.bogus_comment, "else");
                    try t.appendComment(c);
                },
            },
            .comment_start => switch (c) {
                '-' => {
                    hit(.comment_start, "-");
                    t.state = .comment_start_dash;
                },
                '>' => {
                    hit(.comment_start, ">");
                    t.raise(.abrupt_closing_of_empty_comment);
                    t.state = .data;
                    t.emitComment();
                },
                else => {
                    hit(.comment_start, "else");
                    t.reconsumeIn(.comment);
                },
            },
            .comment_start_dash => switch (c) {
                '-' => {
                    hit(.comment_start_dash, "-");
                    t.state = .comment_end;
                },
                '>' => {
                    hit(.comment_start_dash, ">");
                    t.raise(.abrupt_closing_of_empty_comment);
                    t.state = .data;
                    t.emitComment();
                },
                eof => {
                    hit(.comment_start_dash, "EOF");
                    t.eofInComment();
                },
                else => {
                    hit(.comment_start_dash, "else");
                    try t.appendComment('-');
                    t.reconsumeIn(.comment);
                },
            },
            .comment => switch (c) {
                '<' => {
                    hit(.comment, "<");
                    try t.appendComment(c);
                    t.state = .comment_less_than_sign;
                },
                '-' => {
                    hit(.comment, "-");
                    t.state = .comment_end_dash;
                },
                0 => {
                    hit(.comment, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendComment(replacement);
                },
                eof => {
                    hit(.comment, "EOF");
                    t.eofInComment();
                },
                else => {
                    hit(.comment, "else");
                    try t.appendComment(c);
                },
            },
            .comment_less_than_sign => switch (c) {
                '!' => {
                    hit(.comment_less_than_sign, "!");
                    try t.appendComment(c);
                    t.state = .comment_less_than_sign_bang;
                },
                '<' => {
                    hit(.comment_less_than_sign, "<");
                    try t.appendComment(c);
                },
                else => {
                    hit(.comment_less_than_sign, "else");
                    t.reconsumeIn(.comment);
                },
            },
            .comment_less_than_sign_bang => switch (c) {
                '-' => {
                    hit(.comment_less_than_sign_bang, "-");
                    t.state = .comment_less_than_sign_bang_dash;
                },
                else => {
                    hit(.comment_less_than_sign_bang, "else");
                    t.reconsumeIn(.comment);
                },
            },
            .comment_less_than_sign_bang_dash => switch (c) {
                '-' => {
                    hit(.comment_less_than_sign_bang_dash, "-");
                    t.state = .comment_less_than_sign_bang_dash_dash;
                },
                else => {
                    hit(.comment_less_than_sign_bang_dash, "else");
                    t.reconsumeIn(.comment_end_dash);
                },
            },
            .comment_less_than_sign_bang_dash_dash => switch (c) {
                '>', eof => {
                    hit(.comment_less_than_sign_bang_dash_dash, "> or EOF");
                    t.reconsumeIn(.comment_end);
                },
                else => {
                    hit(.comment_less_than_sign_bang_dash_dash, "else");
                    t.raise(.nested_comment);
                    t.reconsumeIn(.comment_end);
                },
            },
            .comment_end_dash => switch (c) {
                '-' => {
                    hit(.comment_end_dash, "-");
                    t.state = .comment_end;
                },
                eof => {
                    hit(.comment_end_dash, "EOF");
                    t.eofInComment();
                },
                else => {
                    hit(.comment_end_dash, "else");
                    try t.appendComment('-');
                    t.reconsumeIn(.comment);
                },
            },
            .comment_end => switch (c) {
                '>' => {
                    hit(.comment_end, ">");
                    t.state = .data;
                    t.emitComment();
                },
                '!' => {
                    hit(.comment_end, "!");
                    t.state = .comment_end_bang;
                },
                '-' => {
                    hit(.comment_end, "-");
                    try t.appendComment('-');
                },
                eof => {
                    hit(.comment_end, "EOF");
                    t.eofInComment();
                },
                else => {
                    hit(.comment_end, "else");
                    try t.appendCommentText("--");
                    t.reconsumeIn(.comment);
                },
            },
            .comment_end_bang => switch (c) {
                '-' => {
                    hit(.comment_end_bang, "-");
                    try t.appendCommentText("--!");
                    t.state = .comment_end_dash;
                },
                '>' => {
                    hit(.comment_end_bang, ">");
                    t.raise(.incorrectly_closed_comment);
                    t.state = .data;
                    t.emitComment();
                },
                eof => {
                    hit(.comment_end_bang, "EOF");
                    t.eofInComment();
                },
                else => {
                    hit(.comment_end_bang, "else");
                    try t.appendCommentText("--!");
                    t.reconsumeIn(.comment);
                },
            },
            .doctype => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.doctype, "whitespace");
                    t.state = .before_doctype_name;
                },
                '>' => {
                    hit(.doctype, ">");
                    t.reconsumeIn(.before_doctype_name);
                },
                eof => {
                    hit(.doctype, "EOF");
                    t.createDoctype();
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype, "else");
                    t.raise(.missing_whitespace_before_doctype_name);
                    t.reconsumeIn(.before_doctype_name);
                },
            },
            .before_doctype_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.before_doctype_name, "whitespace"),
                'A'...'Z' => {
                    hit(.before_doctype_name, "ASCII upper alpha");
                    try t.startDoctypeName(c + 0x20);
                },
                0 => {
                    hit(.before_doctype_name, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.startDoctypeName(replacement);
                },
                '>' => {
                    hit(.before_doctype_name, ">");
                    t.raise(.missing_doctype_name);
                    t.createDoctype();
                    t.force_quirks = true;
                    t.state = .data;
                    t.emitDoctype();
                },
                eof => {
                    hit(.before_doctype_name, "EOF");
                    t.createDoctype();
                    t.eofInDoctype();
                },
                else => {
                    hit(.before_doctype_name, "else");
                    try t.startDoctypeName(c);
                },
            },
            .doctype_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.doctype_name, "whitespace");
                    t.state = .after_doctype_name;
                },
                '>' => {
                    hit(.doctype_name, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                'A'...'Z' => {
                    hit(.doctype_name, "ASCII upper alpha");
                    try t.appendDoctypeField(&t.doctype_name, c + 0x20);
                },
                0 => {
                    hit(.doctype_name, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendDoctypeField(&t.doctype_name, replacement);
                },
                eof => {
                    hit(.doctype_name, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype_name, "else");
                    try t.appendDoctypeField(&t.doctype_name, c);
                },
            },
            .after_doctype_name => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.after_doctype_name, "whitespace"),
                '>' => {
                    hit(.after_doctype_name, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                eof => {
                    hit(.after_doctype_name, "EOF");
                    t.eofInDoctype();
                },
                else => return t.afterDoctypeNameKeyword(c),
            },
            .after_doctype_public_keyword => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.after_doctype_public_keyword, "whitespace");
                    t.state = .before_doctype_public_identifier;
                },
                '"' => {
                    hit(.after_doctype_public_keyword, "\"");
                    t.raise(.missing_whitespace_after_doctype_public_keyword);
                    t.startDoctypeField(&t.public_identifier);
                    t.state = .doctype_public_identifier_double_quoted;
                },
                '\'' => {
                    hit(.after_doctype_public_keyword, "'");
                    t.raise(.missing_whitespace_after_doctype_public_keyword);
                    t.startDoctypeField(&t.public_identifier);
                    t.state = .doctype_public_identifier_single_quoted;
                },
                '>' => {
                    hit(.after_doctype_public_keyword, ">");
                    t.quirksAtGreaterThan(.missing_doctype_public_identifier);
                },
                eof => {
                    hit(.after_doctype_public_keyword, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.after_doctype_public_keyword, "else");
                    t.missingQuote(.missing_quote_before_doctype_public_identifier);
                },
            },
            .before_doctype_public_identifier => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.before_doctype_public_identifier, "whitespace"),
                '"' => {
                    hit(.before_doctype_public_identifier, "\"");
                    t.startDoctypeField(&t.public_identifier);
                    t.state = .doctype_public_identifier_double_quoted;
                },
                '\'' => {
                    hit(.before_doctype_public_identifier, "'");
                    t.startDoctypeField(&t.public_identifier);
                    t.state = .doctype_public_identifier_single_quoted;
                },
                '>' => {
                    hit(.before_doctype_public_identifier, ">");
                    t.quirksAtGreaterThan(.missing_doctype_public_identifier);
                },
                eof => {
                    hit(.before_doctype_public_identifier, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.before_doctype_public_identifier, "else");
                    t.missingQuote(.missing_quote_before_doctype_public_identifier);
                },
            },
            .doctype_public_identifier_double_quoted => switch (c) {
                '"' => {
                    hit(.doctype_public_identifier_double_quoted, "\"");
                    t.state = .after_doctype_public_identifier;
                },
                0 => {
                    hit(.doctype_public_identifier_double_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendDoctypeField(&t.public_identifier, replacement);
                },
                '>' => {
                    hit(.doctype_public_identifier_double_quoted, ">");
                    t.quirksAtGreaterThan(.abrupt_doctype_public_identifier);
                },
                eof => {
                    hit(.doctype_public_identifier_double_quoted, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype_public_identifier_double_quoted, "else");
                    try t.appendDoctypeField(&t.public_identifier, c);
                },
            },
            .doctype_public_identifier_single_quoted => switch (c) {
                '\'' => {
                    hit(.doctype_public_identifier_single_quoted, "'");
                    t.state = .after_doctype_public_identifier;
                },
                0 => {
                    hit(.doctype_public_identifier_single_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendDoctypeField(&t.public_identifier, replacement);
                },
                '>' => {
                    hit(.doctype_public_identifier_single_quoted, ">");
                    t.quirksAtGreaterThan(.abrupt_doctype_public_identifier);
                },
                eof => {
                    hit(.doctype_public_identifier_single_quoted, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype_public_identifier_single_quoted, "else");
                    try t.appendDoctypeField(&t.public_identifier, c);
                },
            },
            .after_doctype_public_identifier => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.after_doctype_public_identifier, "whitespace");
                    t.state = .between_doctype_public_and_system_identifiers;
                },
                '>' => {
                    hit(.after_doctype_public_identifier, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                '"' => {
                    hit(.after_doctype_public_identifier, "\"");
                    t.raise(.missing_whitespace_between_doctype_public_and_system_identifiers);
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_double_quoted;
                },
                '\'' => {
                    hit(.after_doctype_public_identifier, "'");
                    t.raise(.missing_whitespace_between_doctype_public_and_system_identifiers);
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_single_quoted;
                },
                eof => {
                    hit(.after_doctype_public_identifier, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.after_doctype_public_identifier, "else");
                    t.missingQuote(.missing_quote_before_doctype_system_identifier);
                },
            },
            .between_doctype_public_and_system_identifiers => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.between_doctype_public_and_system_identifiers, "whitespace"),
                '>' => {
                    hit(.between_doctype_public_and_system_identifiers, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                '"' => {
                    hit(.between_doctype_public_and_system_identifiers, "\"");
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_double_quoted;
                },
                '\'' => {
                    hit(.between_doctype_public_and_system_identifiers, "'");
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_single_quoted;
                },
                eof => {
                    hit(.between_doctype_public_and_system_identifiers, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.between_doctype_public_and_system_identifiers, "else");
                    t.missingQuote(.missing_quote_before_doctype_system_identifier);
                },
            },
            .after_doctype_system_keyword => switch (c) {
                '\t', '\n', 0x0C, ' ' => {
                    hit(.after_doctype_system_keyword, "whitespace");
                    t.state = .before_doctype_system_identifier;
                },
                '"' => {
                    hit(.after_doctype_system_keyword, "\"");
                    t.raise(.missing_whitespace_after_doctype_system_keyword);
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_double_quoted;
                },
                '\'' => {
                    hit(.after_doctype_system_keyword, "'");
                    t.raise(.missing_whitespace_after_doctype_system_keyword);
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_single_quoted;
                },
                '>' => {
                    hit(.after_doctype_system_keyword, ">");
                    t.quirksAtGreaterThan(.missing_doctype_system_identifier);
                },
                eof => {
                    hit(.after_doctype_system_keyword, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.after_doctype_system_keyword, "else");
                    t.missingQuote(.missing_quote_before_doctype_system_identifier);
                },
            },
            .before_doctype_system_identifier => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.before_doctype_system_identifier, "whitespace"),
                '"' => {
                    hit(.before_doctype_system_identifier, "\"");
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_double_quoted;
                },
                '\'' => {
                    hit(.before_doctype_system_identifier, "'");
                    t.startDoctypeField(&t.system_identifier);
                    t.state = .doctype_system_identifier_single_quoted;
                },
                '>' => {
                    hit(.before_doctype_system_identifier, ">");
                    t.quirksAtGreaterThan(.missing_doctype_system_identifier);
                },
                eof => {
                    hit(.before_doctype_system_identifier, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.before_doctype_system_identifier, "else");
                    t.missingQuote(.missing_quote_before_doctype_system_identifier);
                },
            },
            .doctype_system_identifier_double_quoted => switch (c) {
                '"' => {
                    hit(.doctype_system_identifier_double_quoted, "\"");
                    t.state = .after_doctype_system_identifier;
                },
                0 => {
                    hit(.doctype_system_identifier_double_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendDoctypeField(&t.system_identifier, replacement);
                },
                '>' => {
                    hit(.doctype_system_identifier_double_quoted, ">");
                    t.quirksAtGreaterThan(.abrupt_doctype_system_identifier);
                },
                eof => {
                    hit(.doctype_system_identifier_double_quoted, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype_system_identifier_double_quoted, "else");
                    try t.appendDoctypeField(&t.system_identifier, c);
                },
            },
            .doctype_system_identifier_single_quoted => switch (c) {
                '\'' => {
                    hit(.doctype_system_identifier_single_quoted, "'");
                    t.state = .after_doctype_system_identifier;
                },
                0 => {
                    hit(.doctype_system_identifier_single_quoted, "NULL");
                    t.raise(.unexpected_null_character);
                    try t.appendDoctypeField(&t.system_identifier, replacement);
                },
                '>' => {
                    hit(.doctype_system_identifier_single_quoted, ">");
                    t.quirksAtGreaterThan(.abrupt_doctype_system_identifier);
                },
                eof => {
                    hit(.doctype_system_identifier_single_quoted, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.doctype_system_identifier_single_quoted, "else");
                    try t.appendDoctypeField(&t.system_identifier, c);
                },
            },
            .after_doctype_system_identifier => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.after_doctype_system_identifier, "whitespace"),
                '>' => {
                    hit(.after_doctype_system_identifier, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                eof => {
                    hit(.after_doctype_system_identifier, "EOF");
                    t.eofInDoctype();
                },
                else => {
                    hit(.after_doctype_system_identifier, "else");
                    // This does not set the force-quirks flag.
                    t.raise(.unexpected_character_after_doctype_system_identifier);
                    t.reconsumeIn(.bogus_doctype);
                },
            },
            .bogus_doctype => switch (c) {
                '>' => {
                    hit(.bogus_doctype, ">");
                    t.state = .data;
                    t.emitDoctype();
                },
                0 => {
                    hit(.bogus_doctype, "NULL");
                    t.raise(.unexpected_null_character);
                },
                eof => {
                    hit(.bogus_doctype, "EOF");
                    t.emitDoctype();
                    t.emitEof();
                },
                else => hit(.bogus_doctype, "else"),
            },
            .cdata_section => switch (c) {
                ']' => {
                    hit(.cdata_section, "]");
                    t.bracket_start = t.current.position;
                    t.state = .cdata_section_bracket;
                },
                eof => {
                    hit(.cdata_section, "EOF");
                    t.raise(.eof_in_cdata);
                    t.emitEof();
                },
                // Tree construction handles U+0000 in a CDATA section, so the state emits it unchanged.
                else => {
                    hit(.cdata_section, "else");
                    try t.emitCurrent();
                },
            },
            .cdata_section_bracket => switch (c) {
                ']' => {
                    hit(.cdata_section_bracket, "]");
                    t.state = .cdata_section_end;
                },
                else => {
                    hit(.cdata_section_bracket, "else");
                    try t.emitSource(']', t.bracket_start);
                    t.reconsumeIn(.cdata_section);
                },
            },
            .cdata_section_end => switch (c) {
                ']' => {
                    // The earlier of the two held `]` characters is emitted, and the current one is now held.
                    hit(.cdata_section_end, "]");
                    try t.emitSource(']', t.bracket_start);
                    t.bracket_start = after(t.bracket_start);
                },
                '>' => {
                    hit(.cdata_section_end, ">");
                    t.state = .data;
                },
                else => {
                    hit(.cdata_section_end, "else");
                    try t.appendText(&.{ ']', ']' }, t.bracket_start, after(after(t.bracket_start)), .sequential);
                    t.reconsumeIn(.cdata_section);
                },
            },
            .processing_instruction_open => switch (c) {
                'A'...'Z', 'a'...'z', '_' => {
                    hit(.processing_instruction_open, "ASCII alpha or _");
                    t.reconsumeIn(.processing_instruction_target);
                },
                eof => {
                    hit(.processing_instruction_open, "EOF");
                    t.raise(.eof_in_processing_instruction);
                    t.emitEof();
                },
                else => {
                    hit(.processing_instruction_open, "else");
                    t.raise(.invalid_first_character_of_processing_instruction_target);
                    try t.temporaryBufferToComment();
                    t.reconsumeIn(.bogus_comment);
                },
            },
            .processing_instruction_target => switch (c) {
                '\t', '\n', 0x0C, ' ', '?', '>' => {
                    if (disallowedTarget(t.temp.items)) {
                        hit(.processing_instruction_target, "terminator with a disallowed target");
                        t.raise(.disallowed_processing_instruction_target);
                        try t.temporaryBufferToComment();
                        t.reconsumeIn(.bogus_comment);
                    } else {
                        hit(.processing_instruction_target, "terminator with another target");
                        t.instruction.clearRetainingCapacity();
                        try t.instruction.appendSlice(t.gpa, t.temp.items);
                        t.target_end = t.instruction.items.len;
                        t.reconsumeIn(.after_processing_instruction_target);
                    }
                },
                'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => {
                    hit(.processing_instruction_target, "ASCII alphanumeric, -, or _");
                    try t.temp.append(t.gpa, @intCast(c));
                },
                eof => {
                    hit(.processing_instruction_target, "EOF");
                    t.raise(.eof_in_processing_instruction);
                    t.emitEof();
                },
                else => {
                    hit(.processing_instruction_target, "else");
                    t.raise(.invalid_processing_instruction_target);
                    try t.temporaryBufferToComment();
                    t.reconsumeIn(.bogus_comment);
                },
            },
            .after_processing_instruction_target => switch (c) {
                '\t', '\n', 0x0C, ' ' => hit(.after_processing_instruction_target, "whitespace"),
                else => {
                    hit(.after_processing_instruction_target, "else");
                    t.reconsumeIn(.processing_instruction_data);
                },
            },
            .processing_instruction_data => switch (c) {
                '?' => {
                    hit(.processing_instruction_data, "?");
                    t.state = .processing_instruction_questionable;
                },
                '>' => {
                    hit(.processing_instruction_data, ">");
                    t.state = .data;
                    t.emitInstruction();
                },
                eof => {
                    hit(.processing_instruction_data, "EOF");
                    t.raise(.eof_in_processing_instruction);
                    t.emitEof();
                },
                else => {
                    hit(.processing_instruction_data, "else");
                    try appendCodePoint(&t.instruction, t.gpa, c);
                },
            },
            .processing_instruction_questionable => switch (c) {
                '>' => {
                    hit(.processing_instruction_questionable, ">");
                    t.state = .data;
                    t.emitInstruction();
                },
                eof => {
                    hit(.processing_instruction_questionable, "EOF");
                    t.raise(.eof_in_processing_instruction);
                    t.emitEof();
                },
                else => {
                    hit(.processing_instruction_questionable, "else");
                    try t.instruction.append(t.gpa, '?');
                    t.reconsumeIn(.processing_instruction_data);
                },
            },
            .character_reference => switch (c) {
                'A'...'Z', 'a'...'z', '0'...'9' => {
                    hit(.character_reference, "ASCII alphanumeric");
                    t.reconsumeIn(.named_character_reference);
                },
                '#' => {
                    hit(.character_reference, "#");
                    try t.temp.append(t.gpa, '#');
                    t.state = .numeric_character_reference;
                },
                else => {
                    hit(.character_reference, "else");
                    t.reconsume = true;
                    try t.flushReference(.sequential);
                    t.state = t.return_state;
                },
            },
            .ambiguous_ampersand => switch (c) {
                'A'...'Z', 'a'...'z', '0'...'9' => if (inAttribute(t.return_state)) {
                    hit(.ambiguous_ampersand, "ASCII alphanumeric in an attribute");
                    try t.appendAttributeValueCodePoint(c);
                } else {
                    hit(.ambiguous_ampersand, "ASCII alphanumeric otherwise");
                    try t.emitCurrent();
                },
                ';' => {
                    hit(.ambiguous_ampersand, ";");
                    t.raise(.unknown_named_character_reference);
                    t.reconsumeIn(t.return_state);
                },
                else => {
                    hit(.ambiguous_ampersand, "else");
                    t.reconsumeIn(t.return_state);
                },
            },
            .numeric_character_reference => switch (c) {
                'x', 'X' => {
                    hit(.numeric_character_reference, "x or X");
                    try t.temp.append(t.gpa, @intCast(c));
                    t.state = .hexadecimal_character_reference_start;
                },
                '0'...'9' => {
                    hit(.numeric_character_reference, "ASCII digit");
                    t.reconsumeIn(.decimal_character_reference);
                },
                else => {
                    hit(.numeric_character_reference, "else");
                    t.raise(.absence_of_digits_in_numeric_character_reference);
                    t.reconsume = true;
                    try t.flushReference(.sequential);
                    t.state = t.return_state;
                },
            },
            .hexadecimal_character_reference_start => switch (c) {
                '0'...'9', 'A'...'F', 'a'...'f' => {
                    hit(.hexadecimal_character_reference_start, "ASCII hex digit");
                    t.reconsumeIn(.hexadecimal_character_reference);
                },
                else => {
                    hit(.hexadecimal_character_reference_start, "else");
                    t.raise(.absence_of_digits_in_numeric_character_reference);
                    t.reconsume = true;
                    try t.flushReference(.sequential);
                    t.state = t.return_state;
                },
            },
            .hexadecimal_character_reference => switch (c) {
                '0'...'9' => {
                    hit(.hexadecimal_character_reference, "ASCII digit");
                    t.accumulate(16, c - 0x30);
                },
                'A'...'F' => {
                    hit(.hexadecimal_character_reference, "ASCII upper hex digit");
                    t.accumulate(16, c - 0x37);
                },
                'a'...'f' => {
                    hit(.hexadecimal_character_reference, "ASCII lower hex digit");
                    t.accumulate(16, c - 0x57);
                },
                ';' => {
                    hit(.hexadecimal_character_reference, ";");
                    t.state = .numeric_character_reference_end;
                },
                else => {
                    hit(.hexadecimal_character_reference, "else");
                    t.raise(.missing_semicolon_after_character_reference);
                    t.reconsumeIn(.numeric_character_reference_end);
                },
            },
            .decimal_character_reference => switch (c) {
                '0'...'9' => {
                    hit(.decimal_character_reference, "ASCII digit");
                    t.accumulate(10, c - 0x30);
                },
                ';' => {
                    hit(.decimal_character_reference, ";");
                    t.state = .numeric_character_reference_end;
                },
                else => {
                    hit(.decimal_character_reference, "else");
                    t.raise(.missing_semicolon_after_character_reference);
                    t.reconsumeIn(.numeric_character_reference_end);
                },
            },
            // These states consume nothing, so `step` runs them before it consumes a character.
            .markup_declaration_open, .named_character_reference, .numeric_character_reference_end => unreachable,
        }
        return true;
    }

    /// Emits a U+FFFD REPLACEMENT CHARACTER for the current U+0000, which spans that U+0000, after an
    /// unexpected-null-character parse error.
    fn emitReplacement(t: *Tokenizer) Allocator.Error!void {
        t.raise(.unexpected_null_character);
        try t.emitCharacter(replacement, t.current.position, t.cursor());
    }

    /// The EOF branch of the script data escaped and double escaped states.
    fn eofInScriptComment(t: *Tokenizer) void {
        t.raise(.eof_in_script_html_comment_like_text);
        t.emitEof();
    }

    /// Whether the current end tag token is an appropriate end tag token: a start tag was emitted, and the end tag's name
    /// so far equals the last start tag name code unit for code unit.
    fn appropriateEndTag(t: *const Tokenizer) bool {
        const name = t.tag_buffer.items[0..t.tag_name_end];
        return t.last_start_tag.items.len != 0 and std.mem.eql(u16, name, t.last_start_tag.items);
    }

    /// The RCDATA and RAWTEXT less-than sign states (§13.2.5.9 and §13.2.5.12). `markup_start` is the `<`.
    fn textLessThanSign(t: *Tokenizer, comptime state: State, comptime text: State, comptime end_tag_open: State, c: u21) Allocator.Error!void {
        if (c == '/') {
            hit(state, "/");
            t.temp.clearRetainingCapacity();
            t.state = end_tag_open;
        } else {
            hit(state, "else");
            try t.emitSource('<', t.markup_start);
            t.reconsumeIn(text);
        }
    }

    /// The RCDATA, RAWTEXT, script data, and script data escaped end tag open states (§13.2.5.10, §13.2.5.13, §13.2.5.16,
    /// and §13.2.5.24). `markup_start` is the `<`, and the `/` follows it.
    fn textEndTagOpen(t: *Tokenizer, comptime state: State, comptime text: State, comptime end_tag_name: State, c: u21) Allocator.Error!void {
        switch (c) {
            'A'...'Z', 'a'...'z' => {
                hit(state, "ASCII alpha");
                t.createTag(true);
                t.reconsumeIn(end_tag_name);
            },
            else => {
                hit(state, "else");
                try t.emitSource('<', t.markup_start);
                try t.emitSource('/', after(t.markup_start));
                t.reconsumeIn(text);
            },
        }
    }

    /// The RCDATA, RAWTEXT, script data, and script data escaped end tag name states (§13.2.5.11, §13.2.5.14, §13.2.5.17,
    /// and §13.2.5.25). The temporary buffer holds the name's source characters.
    fn textEndTagName(t: *Tokenizer, comptime state: State, comptime text: State, c: u21) Allocator.Error!void {
        switch (c) {
            '\t', '\n', 0x0C, ' ', '/', '>' => if (t.appropriateEndTag()) switch (c) {
                '/' => {
                    hit(state, "/ with an appropriate end tag");
                    t.state = .self_closing_start_tag;
                },
                '>' => {
                    hit(state, "> with an appropriate end tag");
                    t.state = .data;
                    try t.emitTag();
                },
                else => {
                    hit(state, "whitespace with an appropriate end tag");
                    t.state = .before_attribute_name;
                },
            } else {
                hit(state, "whitespace, /, or > otherwise");
                try t.abandonEndTag(text);
            },
            'A'...'Z' => {
                hit(state, "ASCII upper alpha");
                try t.appendTagName(c + 0x20);
                try t.temp.append(t.gpa, @intCast(c));
            },
            'a'...'z' => {
                hit(state, "ASCII lower alpha");
                try t.appendTagName(c);
                try t.temp.append(t.gpa, @intCast(c));
            },
            else => {
                hit(state, "else");
                try t.abandonEndTag(text);
            },
        }
    }

    /// The "anything else" branch of an end tag name state. It emits `<`, `/`, and the temporary buffer, each of which spans
    /// its source character, so together they span from the `<` to the current input character. It reconsumes in `text`.
    fn abandonEndTag(t: *Tokenizer, comptime text: State) Allocator.Error!void {
        const name_start = after(after(t.markup_start));
        try t.appendText(&.{ '<', '/' }, t.markup_start, name_start, .sequential);
        try t.appendText(t.temp.items, name_start, t.current.position, .sequential);
        t.reconsumeIn(text);
    }

    /// The script data double escape start and end states (§13.2.5.26 and §13.2.5.31). Each switches to `with_script` when
    /// the temporary buffer is "script" and to `otherwise` when it is not, and reconsumes "anything else" in `otherwise`.
    fn doubleEscapeBoundary(t: *Tokenizer, comptime state: State, comptime with_script: State, comptime otherwise: State, c: u21) Allocator.Error!void {
        switch (c) {
            '\t', '\n', 0x0C, ' ', '/', '>' => {
                const script = [_]u16{ 's', 'c', 'r', 'i', 'p', 't' };
                if (std.mem.eql(u16, t.temp.items, &script)) {
                    hit(state, "whitespace, /, or > with \"script\"");
                    t.state = with_script;
                } else {
                    hit(state, "whitespace, /, or > otherwise");
                    t.state = otherwise;
                }
                try t.emitCurrent();
            },
            'A'...'Z' => {
                hit(state, "ASCII upper alpha");
                try t.temp.append(t.gpa, @intCast(c + 0x20));
                try t.emitCurrent();
            },
            'a'...'z' => {
                hit(state, "ASCII lower alpha");
                try t.temp.append(t.gpa, @intCast(c));
                try t.emitCurrent();
            },
            else => {
                hit(state, "else");
                t.reconsumeIn(otherwise);
            },
        }
    }

    fn startDoctypeName(t: *Tokenizer, code_point: u21) Allocator.Error!void {
        t.createDoctype();
        t.startDoctypeField(&t.doctype_name);
        try t.appendDoctypeField(&t.doctype_name, code_point);
        t.state = .doctype_name;
    }

    /// A `>` branch that reports `code`, sets the force-quirks flag, switches to the data state, and emits the DOCTYPE token.
    fn quirksAtGreaterThan(t: *Tokenizer, code: ErrorCode) void {
        t.raise(code);
        t.force_quirks = true;
        t.state = .data;
        t.emitDoctype();
    }

    /// The "anything else" branch that reports a missing quote and reconsumes in the bogus DOCTYPE state.
    fn missingQuote(t: *Tokenizer, code: ErrorCode) void {
        t.raise(code);
        t.force_quirks = true;
        t.reconsumeIn(.bogus_doctype);
    }

    fn eofInComment(t: *Tokenizer) void {
        t.raise(.eof_in_comment);
        t.emitComment();
        t.emitEof();
    }

    /// The "anything else" branch of the after DOCTYPE name state, which looks at the six characters starting from
    /// the current input character `c`. When the available input does not decide them, it returns false and reconsumes `c` later.
    fn afterDoctypeNameKeyword(t: *Tokenizer, c: u21) bool {
        const keywords = [_][]const u8{ "PUBLIC", "SYSTEM" };
        var matched: ?usize = null;
        for (keywords, 0..) |keyword, index| {
            if (c != keyword[0] and c != keyword[0] + 0x20) continue;
            var all = true;
            for (keyword[1..], 0..) |letter, position| {
                switch (t.peek(position)) {
                    .more => {
                        t.reconsume = true;
                        return false;
                    },
                    .end => all = false,
                    .unit => |unit| all = unit == letter or unit == letter + 0x20,
                }
                if (!all) break;
            }
            if (all) matched = index;
        }
        if (matched) |index| {
            t.consumeMatched(5);
            if (index == 0) {
                hit(.after_doctype_name, "else with PUBLIC");
                t.state = .after_doctype_public_keyword;
            } else {
                hit(.after_doctype_name, "else with SYSTEM");
                t.state = .after_doctype_system_keyword;
            }
        } else {
            hit(.after_doctype_name, "else otherwise");
            t.raise(.invalid_character_sequence_after_doctype_name);
            t.force_quirks = true;
            t.reconsumeIn(.bogus_doctype);
        }
        return true;
    }

    /// The markup declaration open state, which consumes nothing until the next few characters decide its branch.
    fn markupDeclarationOpen(t: *Tokenizer) Allocator.Error!bool {
        const Branch = enum { hyphens, doctype, cdata, other };
        const Pattern = struct { text: []const u8, branch: Branch, fold: bool };
        const branch: Branch = branch: {
            const first = switch (t.peek(0)) {
                .more => return false,
                .end => break :branch .other,
                .unit => |unit| unit,
            };
            const pattern: Pattern = switch (first) {
                '-' => .{ .text = "--", .branch = .hyphens, .fold = false },
                'D', 'd' => .{ .text = "DOCTYPE", .branch = .doctype, .fold = true },
                '[' => .{ .text = "[CDATA[", .branch = .cdata, .fold = false },
                else => break :branch .other,
            };
            for (pattern.text[1..], 1..) |letter, index| {
                const unit = switch (t.peek(index)) {
                    .more => return false,
                    .end => break :branch .other,
                    .unit => |unit| unit,
                };
                const matches = unit == letter or (pattern.fold and unit == letter + 0x20);
                if (!matches) break :branch .other;
            }
            break :branch pattern.branch;
        };
        switch (branch) {
            .hyphens => {
                hit(.markup_declaration_open, "two hyphens");
                t.consumeMatched(2);
                t.createComment();
                t.state = .comment_start;
            },
            .doctype => {
                hit(.markup_declaration_open, "DOCTYPE");
                t.consumeMatched(7);
                t.state = .doctype;
            },
            .cdata => if (t.adjusted_current_node_is_foreign) {
                hit(.markup_declaration_open, "[CDATA[ with a foreign adjusted current node");
                t.consumeMatched(7);
                t.state = .cdata_section;
            } else {
                hit(.markup_declaration_open, "[CDATA[ otherwise");
                t.consumeMatched(7);
                t.raise(.cdata_in_html_content);
                t.createComment();
                try t.appendCommentText("[CDATA[");
                t.state = .bogus_comment;
            },
            .other => {
                hit(.markup_declaration_open, "else");
                // The current input character is still the `!` that the tag open state consumed.
                t.raise(.incorrectly_opened_comment);
                t.createComment();
                t.state = .bogus_comment;
            },
        }
        return true;
    }

    /// The named character reference state. The character reference state reconsumed the first ASCII alphanumeric character,
    /// which is the current input character; the state then looks ahead for its longest match and keeps its progress in `matcher`.
    fn namedCharacterReference(t: *Tokenizer) Allocator.Error!bool {
        if (!t.matching) {
            t.reconsume = false;
            t.matcher = .{};
            t.matching = true;
            t.scanning = t.matcher.feed(@intCast(t.current.code_point));
        }
        // The name's unit `len` follows the current input character, so it is `len - 1` units after the next unit.
        while (t.scanning and t.matcher.len < entities.max_name_len) {
            switch (t.peek(t.matcher.len - 1)) {
                .more => return false,
                .end => t.scanning = false,
                .unit => |unit| t.scanning = t.matcher.feed(unit),
            }
        }
        const best = t.matcher.best orelse {
            hit(.named_character_reference, "no match");
            // Only the `&` is consumed, so the ambiguous ampersand state consumes the current input character again.
            t.matching = false;
            t.reconsume = true;
            try t.setTemp(&.{'&'});
            try t.flushReference(.sequential);
            t.state = .ambiguous_ampersand;
            return true;
        };
        const entity = &entities.table[best];
        const length = entity.name.len;
        const semicolon = entity.name[length - 1] == ';';
        if (inAttribute(t.return_state) and !semicolon) {
            const following: ?u16 = switch (t.peek(length - 1)) {
                .more => return false,
                .end => null,
                .unit => |unit| unit,
            };
            const historical = if (following) |unit| unit == '=' or isAsciiAlphanumeric(unit) else false;
            if (historical) {
                hit(.named_character_reference, "match under the historical attribute rule");
                t.matching = false;
                t.consumeMatched(length - 1);
                t.temp.clearRetainingCapacity();
                try t.temp.ensureTotalCapacity(t.gpa, length + 1);
                t.temp.appendAssumeCapacity('&');
                for (entity.name) |letter| t.temp.appendAssumeCapacity(letter);
                try t.flushReference(.sequential);
                t.state = t.return_state;
                return true;
            }
        }
        t.matching = false;
        t.consumeMatched(length - 1);
        if (semicolon) {
            hit(.named_character_reference, "match ending with ;");
        } else {
            hit(.named_character_reference, "other match without ;");
            t.raise(.missing_semicolon_after_character_reference);
        }
        t.temp.clearRetainingCapacity();
        for (entity.code_points) |code_point| {
            var units: [2]u16 = undefined;
            try t.temp.appendSlice(t.gpa, units[0..encode(code_point, &units)]);
        }
        try t.flushReference(.shared);
        t.state = t.return_state;
        return true;
    }

    fn accumulate(t: *Tokenizer, comptime base: u32, digit: u21) void {
        // The code saturates above 0x10FFFF, so it never overflows and still takes the outside-range branch.
        t.reference_code = @min(t.reference_code * base + digit, 0x110000);
    }

    /// The numeric character reference end state, which consumes nothing.
    fn numericCharacterReferenceEnd(t: *Tokenizer) Allocator.Error!void {
        var code = t.reference_code;
        if (code == 0) {
            hit(.numeric_character_reference_end, "0x00");
            t.raise(.null_character_reference);
            code = replacement;
        } else if (code > 0x10FFFF) {
            hit(.numeric_character_reference_end, "above 0x10FFFF");
            t.raise(.character_reference_outside_unicode_range);
            code = replacement;
        } else if (code >= 0xD800 and code <= 0xDFFF) {
            hit(.numeric_character_reference_end, "surrogate");
            t.raise(.surrogate_character_reference);
            code = replacement;
        } else if (isNoncharacter(code)) {
            hit(.numeric_character_reference_end, "noncharacter");
            t.raise(.noncharacter_character_reference);
        } else if (code == 0x0D or (isControl(code) and !isAsciiWhitespace(code))) {
            t.raise(.control_character_reference);
            if (overrides.get(code)) |override| {
                hit(.numeric_character_reference_end, "control or 0x0D found in the table");
                code = override;
            } else {
                hit(.numeric_character_reference_end, "control or 0x0D not in the table");
            }
        } else {
            hit(.numeric_character_reference_end, "no error");
        }
        t.temp.clearRetainingCapacity();
        var units: [2]u16 = undefined;
        try t.temp.appendSlice(t.gpa, units[0..encode(@intCast(code), &units)]);
        try t.flushReference(.shared);
        t.state = t.return_state;
    }
};

/// The table of §13.2.5.84. Its source comments out the rows for 0x0D and 0x81, 0x8D, 0x8F, 0x90, and 0x9D,
/// which map to themselves, so those numbers are not in the table.
const overrides: struct {
    const rows = [_][2]u32{
        .{ 0x80, 0x20AC }, .{ 0x82, 0x201A }, .{ 0x83, 0x0192 }, .{ 0x84, 0x201E }, .{ 0x85, 0x2026 }, .{ 0x86, 0x2020 },
        .{ 0x87, 0x2021 }, .{ 0x88, 0x02C6 }, .{ 0x89, 0x2030 }, .{ 0x8A, 0x0160 }, .{ 0x8B, 0x2039 }, .{ 0x8C, 0x0152 },
        .{ 0x8E, 0x017D }, .{ 0x91, 0x2018 }, .{ 0x92, 0x2019 }, .{ 0x93, 0x201C }, .{ 0x94, 0x201D }, .{ 0x95, 0x2022 },
        .{ 0x96, 0x2013 }, .{ 0x97, 0x2014 }, .{ 0x98, 0x02DC }, .{ 0x99, 0x2122 }, .{ 0x9A, 0x0161 }, .{ 0x9B, 0x203A },
        .{ 0x9C, 0x0153 }, .{ 0x9E, 0x017E }, .{ 0x9F, 0x0178 },
    };

    fn get(_: @This(), number: u32) ?u32 {
        for (rows) |row| {
            if (row[0] == number) return row[1];
        }
        return null;
    }
} = .{};

fn inAttribute(state: State) bool {
    return switch (state) {
        .attribute_value_double_quoted, .attribute_value_single_quoted, .attribute_value_unquoted => true,
        else => false,
    };
}

/// Whether `target` is an ASCII case-insensitive match for "xml" or "xml-stylesheet".
fn disallowedTarget(target: []const u16) bool {
    for ([_][]const u8{ "xml", "xml-stylesheet" }) |name| {
        if (target.len != name.len) continue;
        var equal = true;
        for (target, name) |unit, letter| {
            const lower = if (unit >= 'A' and unit <= 'Z') unit + 0x20 else unit;
            if (lower != letter) equal = false;
        }
        if (equal) return true;
    }
    return false;
}

/// Returns the preprocessing error of §13.2.3.5 for a code point of the input stream, or null.
fn preprocessingError(code_point: u21) ?ErrorCode {
    if (code_point >= 0xD800 and code_point <= 0xDFFF) return .surrogate_in_input_stream;
    if (isNoncharacter(code_point)) return .noncharacter_in_input_stream;
    if (code_point != 0 and isControl(code_point) and !isAsciiWhitespace(code_point)) return .control_character_in_input_stream;
    return null;
}

/// Infra: U+FDD0 to U+FDEF, or the last two code points of any plane.
fn isNoncharacter(code_point: u32) bool {
    return (code_point >= 0xFDD0 and code_point <= 0xFDEF) or (code_point <= 0x10FFFF and code_point & 0xFFFE == 0xFFFE);
}

/// Infra: a C0 control, U+0000 to U+001F, or U+007F to U+009F.
fn isControl(code_point: u32) bool {
    return code_point <= 0x1F or (code_point >= 0x7F and code_point <= 0x9F);
}

fn isAsciiWhitespace(code_point: u32) bool {
    return switch (code_point) {
        '\t', '\n', 0x0C, '\r', ' ' => true,
        else => false,
    };
}

fn isAsciiAlphanumeric(unit: u16) bool {
    return switch (unit) {
        '0'...'9', 'A'...'Z', 'a'...'z' => true,
        else => false,
    };
}

/// The position after a single code unit at `position` that is not a line break.
fn after(position: Position) Position {
    return .{ .offset = @fromBackingInt(@backingInt(position.offset) + 1), .line = position.line, .column = position.column + 1 };
}

/// Writes the UTF-16 encoding of `code_point`, which may be a lone surrogate, and returns its length.
fn encode(code_point: u21, units: *[2]u16) usize {
    if (code_point < 0x10000) {
        units[0] = @intCast(code_point);
        return 1;
    }
    const value = code_point - 0x10000;
    units[0] = @intCast(0xD800 + (value >> 10));
    units[1] = @intCast(0xDC00 + (value & 0x3FF));
    return 2;
}

fn appendCodePoint(list: *std.ArrayList(u16), gpa: Allocator, code_point: u21) Allocator.Error!void {
    var units: [2]u16 = undefined;
    try list.appendSlice(gpa, units[0..encode(code_point, &units)]);
}
