//! The Encoding Standard at whatwg/encoding commit `a985b62a9b45c17da3e17a9f0a0b4e30c34c4a8a`:
//! encoding names and labels (§4.2), output encodings (§4.3), the decoders of UTF-8, UTF-16BE, UTF-16LE,
//! replacement, and x-user-defined, and the decode hooks of §6 and §6.1.
//!
//! Decoders are push-based. Each call takes the next chunk of input and writes UTF-16 code units into a buffer that
//! the caller supplies, and no decoder allocates. A scalar value at or above U+10000 becomes a surrogate pair, and
//! no decoder writes an unpaired surrogate. The standard defines no error position, so a call counts its errors.
//! The decoders of the 35 index-based encodings belong to later tasks, and `unsupportedOwner` names each one's task.

const std = @import("std");
const label_table = @import("labels.zig");
const utf8 = @import("utf8.zig");
const utf16 = @import("utf16.zig");

/// The 40 encodings, in the table order of §4.2.
pub const Encoding = enum {
    utf_8,
    ibm866,
    iso_8859_2,
    iso_8859_3,
    iso_8859_4,
    iso_8859_5,
    iso_8859_6,
    iso_8859_7,
    iso_8859_8,
    iso_8859_8_i,
    iso_8859_10,
    iso_8859_13,
    iso_8859_14,
    iso_8859_15,
    iso_8859_16,
    koi8_r,
    koi8_u,
    macintosh,
    windows_874,
    windows_1250,
    windows_1251,
    windows_1252,
    windows_1253,
    windows_1254,
    windows_1255,
    windows_1256,
    windows_1257,
    windows_1258,
    x_mac_cyrillic,
    gbk,
    gb18030,
    big5,
    euc_jp,
    iso_2022_jp,
    shift_jis,
    euc_kr,
    replacement,
    utf_16be,
    utf_16le,
    x_user_defined,
};

// Each tag is its table row's name, lowercased, with `_` for `-`, so the enum and the table cannot drift apart.
comptime {
    @setEvalBranchQuota(10_000);
    const all = std.enums.values(Encoding);
    if (all.len != label_table.table.len) @compileError("Encoding and the label table differ in length");
    for (all, label_table.table) |e, entry| {
        const tag = @tagName(e);
        if (tag.len != entry.name.len) @compileError("Encoding tag " ++ tag ++ " does not match " ++ entry.name);
        for (tag, entry.name) |t, n| {
            const expected = if (n == '-') '_' else std.ascii.toLower(n);
            if (t != expected) @compileError("Encoding tag " ++ tag ++ " does not match " ++ entry.name);
        }
    }
}

/// The encoding's name, exactly as §4.2 writes it.
pub fn name(e: Encoding) []const u8 {
    return label_table.table[@backingInt(e)].name;
}

/// The encoding whose name is exactly `text`, compared case-sensitively, or null.
/// This does not match labels; `getEncoding` does.
pub fn fromName(text: []const u8) ?Encoding {
    for (label_table.table, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.name, text)) return @fromBackingInt(@intCast(index));
    }
    return null;
}

/// The encoding's labels in table order.
pub fn labels(e: Encoding) []const []const u8 {
    return label_table.table[@backingInt(e)].labels;
}

/// "Get an encoding" (§4.2): removes leading and trailing ASCII whitespace from `label`,
/// then matches it ASCII case-insensitively against every label. Returns null for failure.
/// `Unit` is `u8` or `u16`. A unit above 0x7F never matches, because every label is ASCII.
pub fn getEncoding(comptime Unit: type, label: []const Unit) ?Encoding {
    comptime std.debug.assert(Unit == u8 or Unit == u16);
    const trimmed = trimAsciiWhitespace(Unit, label);
    for (label_table.table, 0..) |entry, index| {
        for (entry.labels) |candidate| {
            if (matchesLabel(Unit, trimmed, candidate)) return @fromBackingInt(@intCast(index));
        }
    }
    return null;
}

/// Infra's ASCII whitespace: U+0009, U+000A, U+000C, U+000D, and U+0020.
fn isAsciiWhitespace(unit: u16) bool {
    return switch (unit) {
        0x09, 0x0A, 0x0C, 0x0D, 0x20 => true,
        else => false,
    };
}

fn trimAsciiWhitespace(comptime Unit: type, text: []const Unit) []const Unit {
    var start: usize = 0;
    var end = text.len;
    while (start < end and isAsciiWhitespace(text[start])) start += 1;
    while (end > start and isAsciiWhitespace(text[end - 1])) end -= 1;
    return text[start..end];
}

/// Whether `text` is an ASCII case-insensitive match for `label`, which is lowercase ASCII.
fn matchesLabel(comptime Unit: type, text: []const Unit, label: []const u8) bool {
    if (text.len != label.len) return false;
    for (text, label) |unit, expected| {
        const lowered: Unit = if (unit >= 'A' and unit <= 'Z') unit + ('a' - 'A') else unit;
        if (lowered != expected) return false;
    }
    return true;
}

/// "Get an output encoding" (§4.3).
pub fn outputEncoding(e: Encoding) Encoding {
    return switch (e) {
        .replacement, .utf_16be, .utf_16le => .utf_8,
        else => e,
    };
}

/// The task that owns the encoding's decoder, or null when this module implements it.
pub fn unsupportedOwner(e: Encoding) ?[]const u8 {
    return switch (e) {
        .utf_8, .replacement, .utf_16be, .utf_16le, .x_user_defined => null,
        .ibm866,
        .iso_8859_2,
        .iso_8859_3,
        .iso_8859_4,
        .iso_8859_5,
        .iso_8859_6,
        .iso_8859_7,
        .iso_8859_8,
        .iso_8859_8_i,
        .iso_8859_10,
        .iso_8859_13,
        .iso_8859_14,
        .iso_8859_15,
        .iso_8859_16,
        .koi8_r,
        .koi8_u,
        .macintosh,
        .windows_874,
        .windows_1250,
        .windows_1251,
        .windows_1252,
        .windows_1253,
        .windows_1254,
        .windows_1255,
        .windows_1256,
        .windows_1257,
        .windows_1258,
        .x_mac_cyrillic,
        => "FP-0124",
        .gbk, .gb18030, .big5, .euc_jp, .iso_2022_jp, .shift_jis, .euc_kr => "FP-0125",
    };
}

/// A byte order mark that "BOM sniff" found.
pub const Bom = struct {
    encoding: Encoding,
    /// The bytes that "decode" reads for this mark: 3 for UTF-8, otherwise 2.
    length: u2,
};

/// "BOM sniff" (§6.1). `peeked` is the result of peeking 3 bytes: the first 3 bytes of the queue,
/// or fewer only when the queue ends sooner. Returns the byte order mark's encoding and length, or null.
pub fn bomSniff(peeked: []const u8) ?Bom {
    if (std.mem.startsWith(u8, peeked, "\xEF\xBB\xBF")) return .{ .encoding = .utf_8, .length = 3 };
    if (std.mem.startsWith(u8, peeked, "\xFE\xFF")) return .{ .encoding = .utf_16be, .length = 2 };
    if (std.mem.startsWith(u8, peeked, "\xFF\xFE")) return .{ .encoding = .utf_16le, .length = 2 };
    return null;
}

/// A decoder's error mode (§4.1).
pub const ErrorMode = enum {
    /// Each error writes U+FFFD and decoding continues.
    replacement,
    /// The first error stops decoding.
    fatal,
};

pub const Status = enum {
    /// The call consumed its input, and `last` was false.
    input_empty,
    /// The output buffer had fewer than 2 free units before a step.
    output_full,
    /// The decoder processed end-of-queue, or the replacement decoder finished.
    finished,
    /// An error stopped a decoder in "fatal" mode.
    malformed,
};

/// The outcome of one call.
pub const Result = struct {
    /// The bytes of `input` that the call took.
    read: usize,
    /// The code units written at the start of `output`.
    written: usize,
    /// The errors of this call.
    errors: usize,
    status: Status,
};

const replacement_character: u16 = 0xFFFD;

/// The most code units that one step writes: U+FFFD and a code unit, or a surrogate pair.
const max_step_units = 2;

/// Writes a scalar value as one code unit or a surrogate pair, and returns the number of units.
fn writeUtf16(out: []u16, scalar: u21) usize {
    if (scalar < 0x10000) {
        out[0] = @intCast(scalar);
        return 1;
    }
    const offset = scalar - 0x10000;
    out[0] = @intCast(0xD800 + (offset >> 10));
    out[1] = @intCast(0xDC00 + (offset & 0x3FF));
    return 2;
}

/// An instance of an encoding's decoder (§4.1) that processes its queue in chunks.
///
/// A call takes bytes in order. The decoder keeps the bytes that it has read but not yet decided, and it gives a
/// restored byte to its handler again, so no later call needs earlier input. Before each step, including
/// end-of-queue, the call needs 2 free units of `output`; with fewer, it returns `output_full`.
pub const Decoder = struct {
    handler: Handler,
    mode: ErrorMode,
    state: enum { running, finished, malformed } = .running,

    const Handler = union(enum) {
        utf_8: utf8.Handler,
        utf_16: utf16.Handler,
        /// "Replacement error returned" (§14.1.1).
        replacement: bool,
        x_user_defined,
    };

    /// One handler result: an optional error, followed by an optional scalar value, or "finished".
    const Step = struct {
        /// False when the handler restored the byte, which it then reads again.
        consumed: bool = true,
        failure: bool = false,
        scalar: ?u21 = null,
        finished: bool = false,
    };

    pub fn init(e: Encoding, mode: ErrorMode) error{UnsupportedEncoding}!Decoder {
        const handler: Handler = switch (e) {
            .utf_8 => .{ .utf_8 = .{} },
            .utf_16be => .{ .utf_16 = .{ .big_endian = true } },
            .utf_16le => .{ .utf_16 = .{ .big_endian = false } },
            .replacement => .{ .replacement = false },
            .x_user_defined => .x_user_defined,
            else => return error.UnsupportedEncoding,
        };
        return .{ .handler = handler, .mode = mode };
    }

    fn initUtf8(mode: ErrorMode) Decoder {
        return .{ .handler = .{ .utf_8 = .{} }, .mode = mode };
    }

    /// Decodes the next chunk of the queue. With `last` true, `input` ends the queue.
    pub fn decode(d: *Decoder, input: []const u8, output: []u16, last: bool) Result {
        switch (d.state) {
            .finished => return .{ .read = input.len, .written = 0, .errors = 0, .status = .finished },
            .malformed => return .{ .read = 0, .written = 0, .errors = 0, .status = .malformed },
            .running => {},
        }
        var result: Result = .{ .read = 0, .written = 0, .errors = 0, .status = .input_empty };
        while (result.read < input.len) {
            if (output.len - result.written < max_step_units) {
                result.status = .output_full;
                return result;
            }
            const step = d.handle(input[result.read]);
            if (step.failure) {
                // In "fatal" mode, the call reads the erroring byte even when the handler restored it.
                if (d.fail(&result, output, result.read + 1)) |malformed| return malformed;
            }
            if (step.finished) {
                d.state = .finished;
                result.read = input.len;
                result.status = .finished;
                return result;
            }
            if (step.scalar) |scalar| result.written += writeUtf16(output[result.written..], scalar);
            if (step.consumed) result.read += 1;
        }
        if (!last) return result;
        if (output.len - result.written < max_step_units) {
            result.status = .output_full;
            return result;
        }
        for (0..d.end()) |_| {
            if (d.fail(&result, output, result.read)) |malformed| return malformed;
        }
        d.state = .finished;
        result.status = .finished;
        return result;
    }

    /// Applies one error. In "fatal" mode, returns the `malformed` result; otherwise writes U+FFFD.
    fn fail(d: *Decoder, result: *Result, output: []u16, read: usize) ?Result {
        if (d.mode == .fatal) {
            d.state = .malformed;
            return .{ .read = read, .written = result.written, .errors = 1, .status = .malformed };
        }
        output[result.written] = replacement_character;
        result.written += 1;
        result.errors += 1;
        return null;
    }

    fn handle(d: *Decoder, byte: u8) Step {
        switch (d.handler) {
            .utf_8 => |*h| return switch (h.byte(byte)) {
                .pending => .{},
                .scalar => |scalar| .{ .scalar = scalar },
                .failure => .{ .failure = true },
                .failure_restore => .{ .consumed = false, .failure = true },
            },
            .utf_16 => |*h| return switch (h.byte(byte)) {
                .pending => .{},
                .scalar => |scalar| .{ .scalar = scalar },
                .failure => .{ .failure = true },
                .failure_then_scalar => |scalar| .{ .failure = true, .scalar = scalar },
            },
            // §14.1.1: the first byte is an error, and any later byte finishes the decoder.
            .replacement => |*error_returned| {
                if (error_returned.*) return .{ .finished = true };
                error_returned.* = true;
                return .{ .failure = true };
            },
            // §14.5.1.
            .x_user_defined => return .{ .scalar = if (byte < 0x80) byte else 0xF780 + @as(u21, byte) - 0x80 },
        }
    }

    /// Processes end-of-queue and returns the number of errors.
    fn end(d: *Decoder) u2 {
        return switch (d.handler) {
            .utf_8 => |*h| @intFromBool(h.end()),
            .utf_16 => |*h| h.end(),
            .replacement, .x_user_defined => 0,
        };
    }
};

/// The up to 3 bytes that a hook peeks at before it decides on a byte order mark.
const Peek = struct {
    bytes: [3]u8 = undefined,
    len: u2 = 0,
    /// The held bytes from this index on are not part of the byte order mark and still go to the decoder.
    next: u2 = 0,

    /// Holds bytes from the start of `input` until 3 are held, and returns the number taken.
    fn take(p: *Peek, input: []const u8) usize {
        const count: usize = @min(3 - @as(usize, p.len), input.len);
        @memcpy(p.bytes[p.len..][0..count], input[0..count]);
        p.len += @intCast(count);
        return count;
    }

    /// Whether peeking can return: it returns 3 bytes, or fewer only at end-of-queue.
    fn ready(p: *const Peek, last: bool) bool {
        return p.len == 3 or last;
    }

    fn held(p: *const Peek) []const u8 {
        return p.bytes[0..p.len];
    }

    /// Gives `decoder` the held bytes after the byte order mark, then `rest`, the input after the `taken` bytes.
    fn run(p: *Peek, decoder: *Decoder, taken: usize, rest: []const u8, output: []u16, last: bool) Result {
        var result: Result = .{ .read = taken, .written = 0, .errors = 0, .status = .input_empty };
        if (p.next < p.len) {
            const replay = decoder.decode(p.bytes[p.next..p.len], output, false);
            p.next += @intCast(replay.read);
            result.written = replay.written;
            result.errors = replay.errors;
            switch (replay.status) {
                // A finished decoder reads `rest` whole in the call below.
                .input_empty, .finished => {},
                .output_full, .malformed => {
                    result.status = replay.status;
                    return result;
                },
            }
        }
        const r = decoder.decode(rest, output[result.written..], last);
        result.read += r.read;
        result.written += r.written;
        result.errors += r.errors;
        result.status = r.status;
        return result;
    }
};

/// The "decode" hook (§6.1): "BOM sniff", then the decoder of the byte order mark's encoding, or of the fallback
/// encoding when there is none, in "replacement" mode.
/// The byte order mark is decided only when 3 bytes are available or `last` is true, as "peek" requires.
pub const Decode = struct {
    fallback: Encoding,
    peek: Peek = .{},
    decided: ?struct { encoding: Encoding, bom_length: u2 } = null,
    /// The decided encoding's decoder, or null while undecided or when that encoding is unsupported.
    decoder: ?Decoder = null,

    pub fn init(fallback: Encoding) Decode {
        return .{ .fallback = fallback };
    }

    /// Decodes the next chunk. Returns `error.UnsupportedEncoding` from the call that decides on an encoding whose
    /// decoder belongs to a later task, and from every later call.
    pub fn decode(d: *Decode, input: []const u8, output: []u16, last: bool) error{UnsupportedEncoding}!Result {
        var taken: usize = 0;
        if (d.decided == null) {
            taken = d.peek.take(input);
            if (!d.peek.ready(last)) return .{ .read = taken, .written = 0, .errors = 0, .status = .input_empty };
            const sniffed = bomSniff(d.peek.held());
            const e = if (sniffed) |bom| bom.encoding else d.fallback;
            const bom_length: u2 = if (sniffed) |bom| bom.length else 0;
            d.decided = .{ .encoding = e, .bom_length = bom_length };
            d.peek.next = bom_length;
            d.decoder = Decoder.init(e, .replacement) catch null;
        }
        const decoder = if (d.decoder) |*active| active else return error.UnsupportedEncoding;
        return d.peek.run(decoder, taken, input[taken..], output, last);
    }

    /// The encoding in use, or null until decided.
    pub fn encoding(d: *const Decode) ?Encoding {
        return if (d.decided) |decided| decided.encoding else null;
    }

    /// The length of the byte order mark that was read, 0 when there was none, or null until decided.
    pub fn bomLength(d: *const Decode) ?u2 {
        return if (d.decided) |decided| decided.bom_length else null;
    }
};

/// The UTF-8 hooks of §6: "UTF-8 decode", "UTF-8 decode without BOM", and "UTF-8 decode without BOM or fail".
/// For "UTF-8 decode without BOM or fail", a `malformed` status is failure.
pub const Utf8Decode = struct {
    peek: Peek = .{},
    /// Whether the hook has decided on the byte order mark; the hooks without one start decided.
    decided: bool,
    decoder: Decoder,

    pub const Kind = enum { utf8_decode, without_bom, without_bom_or_fail };

    pub fn init(kind: Kind) Utf8Decode {
        return .{
            .decided = kind != .utf8_decode,
            .decoder = .initUtf8(if (kind == .without_bom_or_fail) .fatal else .replacement),
        };
    }

    /// Decodes the next chunk. "UTF-8 decode" decides on its byte order mark only when 3 bytes are available
    /// or `last` is true, as "peek" requires.
    pub fn decode(d: *Utf8Decode, input: []const u8, output: []u16, last: bool) Result {
        var taken: usize = 0;
        if (!d.decided) {
            taken = d.peek.take(input);
            if (!d.peek.ready(last)) return .{ .read = taken, .written = 0, .errors = 0, .status = .input_empty };
            if (std.mem.eql(u8, d.peek.held(), "\xEF\xBB\xBF")) d.peek.next = 3;
            d.decided = true;
        }
        return d.peek.run(&d.decoder, taken, input[taken..], output, last);
    }
};

test {
    _ = @import("tests.zig");
}
