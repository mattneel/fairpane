//! The inspectable headless laboratory.
//!
//! The laboratory runs one case document against a new engine through the Zig API in `engine.zig`.
//! It creates one document, loads the case's document URL, and answers each issued request
//! from the case only, by exact byte equality of the URL.
//! When the document loads, the `decode` stage applies BOM sniffing, step 1 of the HTML encoding sniffing algorithm,
//! and decodes a body that starts with the UTF-8 byte order mark. The `tokenize` stage then runs `html.Tokenizer`
//! on the decoded code units in one chunk, because the engine has no parser hook before task FP-0010.
//! The engine document itself does not tokenize.
//! Its only I/O is `readInputFile`, which `lab_main.zig` calls to read the files named on the command line;
//! `lab_main.zig` also writes the documents that this module renders.
//!
//! Results, transcripts, replay results, and minimized cases are deterministic JSON documents.
//! They name documents and requests by ordinals in order of first appearance,
//! never by the engine's process-wide identifiers.

const std = @import("std");
const engine = @import("engine.zig");
const html = @import("html/root.zig");
const WebString = @import("web_string.zig").WebString;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = Io.Writer;
const Stringify = std.json.Stringify;
const Value = std.json.Value;
const ObjectMap = std.json.ObjectMap;
const Sha256 = std.crypto.hash.sha2.Sha256;
const base64 = std.base64.standard;
const testing = std.testing;

/// The largest case file in bytes.
pub const case_size_limit: usize = 64 * 1024 * 1024;

/// The largest transcript file in bytes.
/// A transcript repeats each response body in base64 and records every drained event, so it may exceed its case.
pub const transcript_size_limit: usize = 4 * case_size_limit;

/// The fixed pipeline stages, in order.
pub const Stage = enum { fetch, decode, tokenize, tree, style, layout, paint, script };

/// Whether this task implements `stage`: `fetch`, `decode`, and `tokenize` exist.
pub fn implemented(stage: Stage) bool {
    return switch (stage) {
        .fetch, .decode, .tokenize => true,
        else => false,
    };
}

pub const Status = enum {
    completed,
    failed,
    unsupported,
    not_reached,

    pub fn name(status: Status) []const u8 {
        return switch (status) {
            .not_reached => "not-reached",
            else => @tagName(status),
        };
    }
};

pub const Result = enum {
    pass,
    fail,
    unsupported,
    harness_error,
    timeout,

    pub fn name(result: Result) []const u8 {
        return switch (result) {
            .harness_error => "harness-error",
            else => @tagName(result),
        };
    }

    pub fn exitStatus(result: Result) u8 {
        return switch (result) {
            .pass => 0,
            .fail => 1,
            .unsupported => 2,
            .harness_error => 3,
            .timeout => 4,
        };
    }
};

pub const EnvironmentField = enum { time_origin_ms, random_seed, viewport, locale, time_zone };

/// Returns the stages that consume `field`.
/// `fetch` answers requests from the case bytes, and `decode` and `tokenize` read only the loaded body, so no stage reads an environment field.
pub fn environmentConsumers(field: EnvironmentField) []const Stage {
    return switch (field) {
        .time_origin_ms, .random_seed, .viewport, .locale, .time_zone => &.{},
    };
}

/// A harness message about a member or an operation.
pub const Detail = struct {
    /// The member path or engine operation that the message concerns, or null.
    subject: ?[]const u8 = null,
    message: []const u8,

    pub fn format(detail: Detail, writer: *Writer) Writer.Error!void {
        if (detail.subject) |subject| try writer.print("{s}: ", .{subject});
        try writer.writeAll(detail.message);
    }
};

const out_of_memory: Detail = .{ .message = "out of memory" };

// Input files.

/// Reads the whole file at `path`, relative to the current directory, which must hold at most `limit` bytes.
/// A longer file returns `error.FileTooLarge` before any allocation or read,
/// and the read never passes the length found first.
/// The caller frees the result with `gpa`.
pub fn readInputFile(io: Io, gpa: Allocator, path: []const u8, limit: usize) ![]u8 {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const length = try file.length(io);
    if (length > limit) return error.FileTooLarge;
    const bytes = try gpa.alloc(u8, @intCast(length));
    errdefer gpa.free(bytes);
    if (try file.readPositionalAll(io, bytes, 0) != bytes.len) return error.FileChanged;
    if (try file.length(io) != length) return error.FileChanged;
    return bytes;
}

/// Describes a failure to read or write `subject`, a file named on the command line.
pub fn fileFailure(subject: []const u8, err: anyerror) Detail {
    return .{ .subject = subject, .message = switch (err) {
        error.FileTooLarge => "exceeds the size limit",
        error.FileChanged => "changed while it was read",
        error.OutOfMemory => "out of memory",
        else => @errorName(err),
    } };
}

// Cases.

pub const Corpus = struct {
    name: []const u8,
    revision: []const u8,
    path: []const u8,
    blob: []const u8,
};

/// The origin of a derived case, such as a minimized case, whose body no longer matches its original's corpus item.
pub const DerivedFrom = struct {
    /// The SHA-256 of the original case file bytes.
    case_sha256: [32]u8,
    /// The original case's `corpus` value.
    corpus: ?Corpus,
};

pub const Viewport = struct {
    width: u16,
    height: u16,
    device_pixel_ratio_milli: u16,
};

pub const Environment = struct {
    time_origin_ms: u64,
    random_seed: []const u8,
    viewport: Viewport,
    locale: []const u8,
    time_zone: []const u8,
};

/// A URL and the bytes that answer a request for it.
pub const Input = struct {
    url: []const u8,
    /// The response body, or null when a request for the URL is cancelled as unavailable.
    body: ?[]const u8,
};

pub const Limits = struct {
    max_steps: u32,
    step_budget: u32,
    max_outstanding_requests: u32,
    max_response_body_bytes: u32,
};

pub const FinalState = enum { loaded, failed };

pub const FetchExpectation = struct {
    document_state: FinalState,
    /// The loaded body's digest, or null when the expected state is `failed`.
    body_sha256: ?[32]u8,
};

/// An encoding that BOM sniffing can select.
pub const Encoding = enum { @"UTF-8", @"UTF-16BE", @"UTF-16LE" };

pub const Confidence = enum { certain, tentative };

pub const DecodeExpectation = struct {
    encoding: Encoding,
    confidence: Confidence,
    /// The SHA-256 of the decoded code units in little-endian order.
    output_sha256: [32]u8,
};

/// A tokenizer parse error, as a result or an expectation records it.
pub const ErrorRecord = struct {
    code: html.ErrorCode,
    line: u64,
    column: u64,
    offset: u64,

    fn eql(a: ErrorRecord, b: ErrorRecord) bool {
        return a.code == b.code and a.line == b.line and a.column == b.column and a.offset == b.offset;
    }
};

fn errorsEql(a: []const ErrorRecord, b: []const ErrorRecord) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!left.eql(right)) return false;
    }
    return true;
}

pub const TokenizeExpectation = struct {
    /// The number of lines of the token dump: the canonical dump with spans and without error lines.
    token_count: u64,
    /// The SHA-256 of the token dump.
    tokens_sha256: [32]u8,
    /// Every parse error in step order.
    errors: []const ErrorRecord,
};

pub const Expectation = union(enum) {
    fetch: FetchExpectation,
    decode: DecodeExpectation,
    tokenize: TokenizeExpectation,
    /// An expectation for a stage that this task does not implement. Its other fields stay uninterpreted.
    unsupported: Stage,
};

pub const Case = struct {
    /// The corpus item, which is always null in a version 2 case.
    corpus: ?Corpus,
    /// The origin of a version 2 case, or null in a version 1 case.
    derived_from: ?DerivedFrom,
    environment: Environment,
    document: Input,
    resources: []const Input,
    limits: Limits,
    expect: Expectation,
    /// The `expect` object as parsed, which a minimized case repeats unchanged.
    expect_json: Value,

    /// Returns the body that answers a request for `url`, or null when the request is unavailable.
    pub fn answer(case: *const Case, url: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, url, case.document.url)) return case.document.body;
        for (case.resources) |resource| {
            if (std.mem.eql(u8, url, resource.url)) return resource.body;
        }
        return null;
    }
};

pub const ParseError = Allocator.Error || error{Invalid};

/// Parses a case document strictly.
/// A version 1 case may name a corpus item and has no `derived_from`.
/// A version 2 case is derived from another case: its `derived_from` names the original, and its `corpus` is null.
/// Every string and body is allocated with `arena`, so the case does not borrow `bytes`.
/// An invalid case returns `error.Invalid` and describes its first problem in `diagnostic`.
pub fn parseCase(arena: Allocator, bytes: []const u8, diagnostic: *Detail) ParseError!Case {
    var p: Parser = .{ .arena = arena, .diagnostic = diagnostic };
    const root = try p.parseJson(bytes, "case");
    const top = try p.object(root, "case", &.{
        "format",
        "version",
        "corpus",
        "derived_from",
        "environment",
        "document",
        "resources",
        "limits",
        "expect",
    });
    const version = try p.header(top, "fairpane-lab-case", &.{ 1, 2 });
    const corpus = try p.corpus(try p.field(top, "", "corpus"), "corpus");
    const derived_from: ?DerivedFrom = switch (version) {
        1 => if (top.contains("derived_from")) return p.fail("derived_from", "not allowed in version 1") else null,
        2 => derived: {
            if (corpus != null) return p.fail("corpus", "expected null in version 2");
            break :derived try p.derivedFrom(try p.field(top, "", "derived_from"));
        },
        else => unreachable,
    };
    const environment = try p.environment(try p.field(top, "", "environment"));
    const document_map = try p.object(try p.field(top, "", "document"), "document", &.{ "url", "body_base64" });
    const document: Input = .{
        .url = try p.url(try p.field(document_map, "document.", "url"), "document.url"),
        .body = try p.body(try p.field(document_map, "document.", "body_base64"), "document.body_base64"),
    };
    const resources = try p.resources(try p.field(top, "", "resources"), document.url);
    const limits = try p.limits(try p.field(top, "", "limits"));
    const expect_json = try p.field(top, "", "expect");
    const expect = try p.expectation(expect_json);
    return .{
        .corpus = corpus,
        .derived_from = derived_from,
        .environment = environment,
        .document = document,
        .resources = resources,
        .limits = limits,
        .expect = expect,
        .expect_json = expect_json,
    };
}

/// Validates parsed JSON values and reports the first problem with a distinct message.
const Parser = struct {
    arena: Allocator,
    diagnostic: *Detail,

    fn fail(p: *Parser, subject: []const u8, message: []const u8) error{Invalid} {
        p.diagnostic.* = .{ .subject = subject, .message = message };
        return error.Invalid;
    }

    /// Parses JSON text. A duplicate field anywhere is invalid.
    fn parseJson(p: *Parser, bytes: []const u8, subject: []const u8) ParseError!Value {
        return std.json.parseFromSliceLeaky(Value, p.arena, bytes, .{
            .duplicate_field_behavior = .@"error",
            .parse_numbers = false,
        }) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.DuplicateField => p.fail(subject, "duplicate field"),
            else => p.fail(subject, "malformed JSON"),
        };
    }

    fn object(p: *Parser, value: Value, subject: []const u8, comptime fields: []const []const u8) error{Invalid}!ObjectMap {
        if (value != .object) return p.fail(subject, "expected an object");
        for (value.object.keys()) |key| {
            if (!isOneOf(key, fields)) return p.fail(subject, "unknown field");
        }
        return value.object;
    }

    fn field(p: *Parser, map: ObjectMap, comptime prefix: []const u8, comptime name: []const u8) error{Invalid}!Value {
        return map.get(name) orelse return p.fail(prefix ++ name, "missing field");
    }

    /// Checks the document's `format` and returns its `version`, which must be one of `versions`.
    fn header(p: *Parser, map: ObjectMap, comptime format: []const u8, comptime versions: []const u8) error{Invalid}!u8 {
        const format_value = try p.field(map, "", "format");
        if (format_value != .string or !std.mem.eql(u8, format_value.string, format)) {
            return p.fail("format", "expected \"" ++ format ++ "\"");
        }
        const version = try p.field(map, "", "version");
        if (version == .number_string) {
            inline for (versions) |known| {
                if (std.mem.eql(u8, version.number_string, std.fmt.comptimePrint("{d}", .{known}))) return known;
            }
        }
        return p.fail("version", comptime versionMessage(versions));
    }

    fn string(p: *Parser, value: Value, subject: []const u8) error{Invalid}![]const u8 {
        if (value != .string) return p.fail(subject, "expected a string");
        return value.string;
    }

    fn integer(p: *Parser, value: Value, subject: []const u8, comptime min: u64, comptime max: u64) error{Invalid}!u64 {
        if (value != .number_string or std.mem.indexOfAny(u8, value.number_string, ".eE") != null) {
            return p.fail(subject, "expected an integer");
        }
        const number = std.fmt.parseInt(i128, value.number_string, 10) catch return p.fail(subject, "out of range");
        if (number < min or number > max) return p.fail(subject, "out of range");
        return @intCast(number);
    }

    fn enumeration(p: *Parser, comptime E: type, value: Value, subject: []const u8) error{Invalid}!E {
        if (value == .string) {
            if (std.meta.stringToEnum(E, value.string)) |result| return result;
        }
        return p.fail(subject, "expected a known name");
    }

    fn hex(p: *Parser, value: Value, subject: []const u8, comptime digits: usize) error{Invalid}![]const u8 {
        const message = std.fmt.comptimePrint("expected {d} lowercase hexadecimal digits", .{digits});
        if (value != .string or value.string.len != digits) return p.fail(subject, message);
        for (value.string) |c| switch (c) {
            '0'...'9', 'a'...'f' => {},
            else => return p.fail(subject, message),
        };
        return value.string;
    }

    fn digest(p: *Parser, value: Value, subject: []const u8) error{Invalid}![32]u8 {
        const text = try p.hex(value, subject, 64);
        var bytes: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&bytes, text) catch unreachable;
        return bytes;
    }

    /// Accepts ASCII text of 1 to 8192 printable bytes that starts with a URL scheme and a colon.
    fn url(p: *Parser, value: Value, subject: []const u8) error{Invalid}![]const u8 {
        const message = "expected an absolute URL of 1 to 8192 printable ASCII bytes";
        if (value != .string or value.string.len == 0 or value.string.len > 8192) return p.fail(subject, message);
        const text = value.string;
        for (text) |c| {
            if (c < 0x21 or c > 0x7e) return p.fail(subject, message);
        }
        const colon = std.mem.indexOfScalar(u8, text, ':') orelse return p.fail(subject, message);
        if (colon == 0 or !std.ascii.isAlphabetic(text[0])) return p.fail(subject, message);
        for (text[1..colon]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') return p.fail(subject, message);
        }
        return text;
    }

    /// Decodes canonical padded base64, or returns null for JSON `null`.
    fn body(p: *Parser, value: Value, subject: []const u8) ParseError!?[]const u8 {
        const message = "expected canonical padded base64";
        switch (value) {
            .null => return null,
            .string => |text| {
                const length = base64.Decoder.calcSizeForSlice(text) catch return p.fail(subject, message);
                const bytes = try p.arena.alloc(u8, length);
                base64.Decoder.decode(bytes, text) catch return p.fail(subject, message);
                if (!encodesTo(bytes, text)) return p.fail(subject, message);
                return bytes;
            },
            else => return p.fail(subject, "expected canonical padded base64 or null"),
        }
    }

    /// Parses a corpus value at member path `subject`.
    fn corpus(p: *Parser, value: Value, comptime subject: []const u8) error{Invalid}!?Corpus {
        if (value == .null) return null;
        const prefix = subject ++ ".";
        const map = try p.object(value, subject, &.{ "name", "revision", "path", "blob" });
        return .{
            .name = try p.corpusName(try p.field(map, prefix, "name"), prefix ++ "name"),
            .revision = try p.hex(try p.field(map, prefix, "revision"), prefix ++ "revision", 40),
            .path = try p.corpusPath(try p.field(map, prefix, "path"), prefix ++ "path"),
            .blob = try p.hex(try p.field(map, prefix, "blob"), prefix ++ "blob", 40),
        };
    }

    fn corpusName(p: *Parser, value: Value, subject: []const u8) error{Invalid}![]const u8 {
        const message = "expected a name that matches [a-z0-9][a-z0-9-]*";
        if (value != .string or value.string.len == 0 or value.string[0] == '-') return p.fail(subject, message);
        for (value.string) |c| switch (c) {
            'a'...'z', '0'...'9', '-' => {},
            else => return p.fail(subject, message),
        };
        return value.string;
    }

    fn corpusPath(p: *Parser, value: Value, subject: []const u8) error{Invalid}![]const u8 {
        const message = "expected a relative POSIX path without empty, \".\", or \"..\" segments";
        if (value != .string) return p.fail(subject, message);
        var segments = std.mem.splitScalar(u8, value.string, '/');
        while (segments.next()) |segment| {
            if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..") or
                std.mem.indexOfScalar(u8, segment, 0) != null)
            {
                return p.fail(subject, message);
            }
        }
        return value.string;
    }

    fn derivedFrom(p: *Parser, value: Value) error{Invalid}!DerivedFrom {
        const map = try p.object(value, "derived_from", &.{ "case_sha256", "corpus" });
        return .{
            .case_sha256 = try p.digest(try p.field(map, "derived_from.", "case_sha256"), "derived_from.case_sha256"),
            .corpus = try p.corpus(try p.field(map, "derived_from.", "corpus"), "derived_from.corpus"),
        };
    }

    fn environment(p: *Parser, value: Value) error{Invalid}!Environment {
        const map = try p.object(value, "environment", &.{ "time_origin_ms", "random_seed", "viewport", "locale", "time_zone" });
        return .{
            .time_origin_ms = try p.integer(try p.field(map, "environment.", "time_origin_ms"), "environment.time_origin_ms", 0, (1 << 53) - 1),
            .random_seed = try p.hex(try p.field(map, "environment.", "random_seed"), "environment.random_seed", 64),
            .viewport = try p.viewport(try p.field(map, "environment.", "viewport")),
            .locale = try p.token(try p.field(map, "environment.", "locale"), "environment.locale"),
            .time_zone = try p.token(try p.field(map, "environment.", "time_zone"), "environment.time_zone"),
        };
    }

    fn viewport(p: *Parser, value: Value) error{Invalid}!Viewport {
        const prefix = "environment.viewport.";
        const map = try p.object(value, "environment.viewport", &.{ "width", "height", "device_pixel_ratio_milli" });
        return .{
            .width = @intCast(try p.integer(try p.field(map, prefix, "width"), prefix ++ "width", 1, 65535)),
            .height = @intCast(try p.integer(try p.field(map, prefix, "height"), prefix ++ "height", 1, 65535)),
            .device_pixel_ratio_milli = @intCast(try p.integer(
                try p.field(map, prefix, "device_pixel_ratio_milli"),
                prefix ++ "device_pixel_ratio_milli",
                1,
                64000,
            )),
        };
    }

    fn token(p: *Parser, value: Value, subject: []const u8) error{Invalid}![]const u8 {
        const message = "expected 1 to 64 characters from [A-Za-z0-9_+/-]";
        if (value != .string or value.string.len == 0 or value.string.len > 64) return p.fail(subject, message);
        for (value.string) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '+' and c != '/' and c != '-') return p.fail(subject, message);
        }
        return value.string;
    }

    fn resources(p: *Parser, value: Value, document_url: []const u8) ParseError![]const Input {
        if (value != .array) return p.fail("resources", "expected an array");
        const items = value.array.items;
        const list = try p.arena.alloc(Input, items.len);
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        try seen.ensureTotalCapacity(p.arena, @intCast(items.len));
        for (items, list) |item, *resource| {
            const map = try p.object(item, "resources[]", &.{ "url", "body_base64" });
            resource.* = .{
                .url = try p.url(try p.field(map, "resources[].", "url"), "resources[].url"),
                .body = try p.body(try p.field(map, "resources[].", "body_base64"), "resources[].body_base64"),
            };
            if (std.mem.eql(u8, resource.url, document_url)) return p.fail("resources[].url", "equals the document URL");
            if (seen.getOrPutAssumeCapacity(resource.url).found_existing) return p.fail("resources[].url", "duplicate URL");
        }
        return list;
    }

    fn limits(p: *Parser, value: Value) error{Invalid}!Limits {
        const map = try p.object(value, "limits", &.{ "max_steps", "step_budget", "max_outstanding_requests", "max_response_body_bytes" });
        return .{
            .max_steps = @intCast(try p.integer(try p.field(map, "limits.", "max_steps"), "limits.max_steps", 0, 1_000_000)),
            .step_budget = @intCast(try p.integer(try p.field(map, "limits.", "step_budget"), "limits.step_budget", 1, 1_000_000)),
            .max_outstanding_requests = @intCast(try p.integer(
                try p.field(map, "limits.", "max_outstanding_requests"),
                "limits.max_outstanding_requests",
                1,
                1024,
            )),
            .max_response_body_bytes = @intCast(try p.integer(
                try p.field(map, "limits.", "max_response_body_bytes"),
                "limits.max_response_body_bytes",
                0,
                case_size_limit,
            )),
        };
    }

    /// Parses `expect`. An expectation for an unimplemented stage keeps its other fields uninterpreted.
    fn expectation(p: *Parser, value: Value) ParseError!Expectation {
        if (value != .object) return p.fail("expect", "expected an object");
        const stage_value = try p.field(value.object, "expect.", "stage");
        const stage = if (stage_value == .string) std.meta.stringToEnum(Stage, stage_value.string) else null;
        if (stage == null) return p.fail("expect.stage", "expected a stage name");
        if (!implemented(stage.?)) return .{ .unsupported = stage.? };
        switch (stage.?) {
            .decode => {
                const map = try p.object(value, "expect", &.{ "stage", "encoding", "confidence", "output_sha256" });
                return .{ .decode = .{
                    .encoding = try p.enumeration(Encoding, try p.field(map, "expect.", "encoding"), "expect.encoding"),
                    .confidence = try p.enumeration(Confidence, try p.field(map, "expect.", "confidence"), "expect.confidence"),
                    .output_sha256 = try p.digest(try p.field(map, "expect.", "output_sha256"), "expect.output_sha256"),
                } };
            },
            .tokenize => {
                const map = try p.object(value, "expect", &.{ "stage", "token_count", "tokens_sha256", "errors" });
                return .{ .tokenize = .{
                    .token_count = try p.integer(try p.field(map, "expect.", "token_count"), "expect.token_count", 0, (1 << 53) - 1),
                    .tokens_sha256 = try p.digest(try p.field(map, "expect.", "tokens_sha256"), "expect.tokens_sha256"),
                    .errors = try p.errorRecords(try p.field(map, "expect.", "errors")),
                } };
            },
            else => {},
        }
        const map = try p.object(value, "expect", &.{ "stage", "document_state", "body_sha256" });
        const state_value = try p.field(map, "expect.", "document_state");
        const state = if (state_value == .string) std.meta.stringToEnum(FinalState, state_value.string) else null;
        if (state == null) return p.fail("expect.document_state", "expected \"loaded\" or \"failed\"");
        const digest_value = try p.field(map, "expect.", "body_sha256");
        const body_sha256: ?[32]u8 = switch (state.?) {
            .loaded => try p.digest(digest_value, "expect.body_sha256"),
            .failed => if (digest_value == .null) null else {
                return p.fail("expect.body_sha256", "expected null when document_state is \"failed\"");
            },
        };
        return .{ .fetch = .{ .document_state = state.?, .body_sha256 = body_sha256 } };
    }

    /// Parses the `errors` array of a `tokenize` expectation.
    fn errorRecords(p: *Parser, value: Value) ParseError![]const ErrorRecord {
        const subject = "expect.errors[]";
        const prefix = subject ++ ".";
        if (value != .array) return p.fail("expect.errors", "expected an array");
        const records = try p.arena.alloc(ErrorRecord, value.array.items.len);
        for (value.array.items, records) |item, *record| {
            const map = try p.object(item, subject, &.{ "code", "line", "column", "offset" });
            const code_value = try p.field(map, prefix, "code");
            const code = if (code_value == .string) html.errors.fromName(code_value.string) else null;
            record.* = .{
                .code = code orelse return p.fail(prefix ++ "code", "expected a parse error code"),
                .line = try p.integer(try p.field(map, prefix, "line"), prefix ++ "line", 1, (1 << 53) - 1),
                .column = try p.integer(try p.field(map, prefix, "column"), prefix ++ "column", 1, (1 << 53) - 1),
                .offset = try p.integer(try p.field(map, prefix, "offset"), prefix ++ "offset", 0, (1 << 53) - 1),
            };
        }
        return records;
    }

    /// Parses a version 2 transcript, whose `action_count` must equal the number of its actions,
    /// so a transcript that lost whole actions is invalid.
    fn transcript(p: *Parser, bytes: []const u8) ParseError!Transcript {
        const root = try p.parseJson(bytes, "transcript");
        const top = try p.object(root, "transcript", &.{
            "format",
            "version",
            "case",
            "engine_options",
            "action_count",
            "actions",
            "document_states",
        });
        _ = try p.header(top, "fairpane-lab-transcript", &.{2});
        _ = try p.hex(try p.field(top, "", "case"), "case", 64);
        const options = try p.object(try p.field(top, "", "engine_options"), "engine_options", &.{
            "max_outstanding_requests",
            "max_response_body_bytes",
        });
        const engine_options: engine.Options = .{
            .max_outstanding_requests = @intCast(try p.integer(
                try p.field(options, "engine_options.", "max_outstanding_requests"),
                "engine_options.max_outstanding_requests",
                1,
                1024,
            )),
            .max_response_body_bytes = @intCast(try p.integer(
                try p.field(options, "engine_options.", "max_response_body_bytes"),
                "engine_options.max_response_body_bytes",
                0,
                case_size_limit,
            )),
        };
        const action_count = try p.integer(try p.field(top, "", "action_count"), "action_count", 0, std.math.maxInt(u32));
        const actions_value = try p.field(top, "", "actions");
        if (actions_value != .array) return p.fail("actions", "expected an array");
        if (action_count != actions_value.array.items.len) return p.fail("action_count", "differs from the number of actions");
        const actions = try p.arena.alloc(TranscriptAction, actions_value.array.items.len);
        for (actions_value.array.items, actions) |item, *action| action.* = try p.transcriptAction(item);
        const states_value = try p.field(top, "", "document_states");
        if (states_value != .array) return p.fail("document_states", "expected an array");
        const states = try p.arena.alloc(engine.DocumentState, states_value.array.items.len);
        for (states_value.array.items, states) |item, *state| {
            state.* = try p.enumeration(engine.DocumentState, item, "document_states[]");
        }
        return .{ .options = engine_options, .actions = actions, .document_states = states };
    }

    fn transcriptAction(p: *Parser, value: Value) ParseError!TranscriptAction {
        const prefix = "actions[].";
        if (value != .object) return p.fail("actions[]", "expected an object");
        const tag = try p.enumeration(std.meta.Tag(Action), try p.field(value.object, prefix, "action"), prefix ++ "action");
        const action: Action = switch (tag) {
            .create_document => create: {
                _ = try p.object(value, "actions[]", &.{ "action", "error", "events" });
                break :create .create_document;
            },
            .load => load: {
                const map = try p.object(value, "actions[]", &.{ "action", "document", "url", "error", "events" });
                break :load .{ .load = .{
                    .document = try p.ordinal(map, prefix, "document"),
                    .url = try p.string(try p.field(map, prefix, "url"), prefix ++ "url"),
                } };
            },
            .respond => respond: {
                const map = try p.object(value, "actions[]", &.{ "action", "request", "body_base64", "error", "events" });
                const body_value = try p.field(map, prefix, "body_base64");
                if (body_value == .null) return p.fail(prefix ++ "body_base64", "expected canonical padded base64");
                break :respond .{ .respond = .{
                    .request = try p.ordinal(map, prefix, "request"),
                    .body = (try p.body(body_value, prefix ++ "body_base64")).?,
                } };
            },
            .cancel => cancel: {
                const map = try p.object(value, "actions[]", &.{ "action", "request", "error", "events" });
                break :cancel .{ .cancel = .{ .request = try p.ordinal(map, prefix, "request") } };
            },
            .step => step: {
                const map = try p.object(value, "actions[]", &.{ "action", "budget", "error", "events" });
                const budget = try p.integer(try p.field(map, prefix, "budget"), prefix ++ "budget", 0, std.math.maxInt(u32));
                break :step .{ .step = .{ .budget = @intCast(budget) } };
            },
        };
        const error_name: ?[]const u8 = switch (try p.field(value.object, prefix, "error")) {
            .null => null,
            .string => |text| text,
            else => return p.fail(prefix ++ "error", "expected a string or null"),
        };
        const events_value = try p.field(value.object, prefix, "events");
        if (events_value != .array) return p.fail(prefix ++ "events", "expected an array");
        const events = try p.arena.alloc(Event, events_value.array.items.len);
        for (events_value.array.items, events) |item, *event| event.* = try p.transcriptEvent(item);
        return .{ .action = action, .@"error" = error_name, .events = events };
    }

    fn ordinal(p: *Parser, map: ObjectMap, comptime prefix: []const u8, comptime name: []const u8) error{Invalid}!usize {
        return @intCast(try p.integer(try p.field(map, prefix, name), prefix ++ name, 1, std.math.maxInt(u32)));
    }

    fn transcriptEvent(p: *Parser, value: Value) error{Invalid}!Event {
        const subject = "actions[].events[]";
        const prefix = subject ++ ".";
        if (value != .object) return p.fail(subject, "expected an object");
        const event_type = try p.enumeration(EventType, try p.field(value.object, prefix, "event"), prefix ++ "event");
        const map = switch (event_type) {
            .request_issued, .request_cancelled => try p.object(value, subject, &.{ "event", "document", "request", "kind", "version", "url" }),
            .document_state_changed => try p.object(value, subject, &.{
                "event",
                "document",
                "request",
                "kind",
                "version",
                "state",
                "reject_reason",
            }),
        };
        var event: Event = .{
            .event = event_type,
            .document = try p.ordinal(map, prefix, "document"),
            .request = try p.ordinal(map, prefix, "request"),
            .kind = try p.enumeration(engine.RequestKind, try p.field(map, prefix, "kind"), prefix ++ "kind"),
            .version = @intCast(try p.integer(try p.field(map, prefix, "version"), prefix ++ "version", 0, std.math.maxInt(u32))),
        };
        switch (event_type) {
            .request_issued, .request_cancelled => event.url = switch (try p.field(map, prefix, "url")) {
                .null => null,
                .string => |text| text,
                else => return p.fail(prefix ++ "url", "expected a string or null"),
            },
            .document_state_changed => {
                event.state = try p.enumeration(engine.DocumentState, try p.field(map, prefix, "state"), prefix ++ "state");
                const reason = try p.field(map, prefix, "reject_reason");
                event.reject_reason = if (reason == .null) null else try p.enumeration(engine.RejectReason, reason, prefix ++ "reject_reason");
            },
        }
        return event;
    }
};

fn isOneOf(key: []const u8, comptime names: []const []const u8) bool {
    inline for (names) |name| {
        if (std.mem.eql(u8, key, name)) return true;
    }
    return false;
}

/// Returns "expected 1", "expected 1 or 2", and so on, for the accepted document versions.
fn versionMessage(comptime versions: []const u8) []const u8 {
    var message: []const u8 = "expected";
    for (versions, 0..) |version, index| {
        message = message ++ (if (index == 0) " " else " or ") ++ std.fmt.comptimePrint("{d}", .{version});
    }
    return message;
}

/// Whether the canonical padded base64 encoding of `bytes` is exactly `text`.
fn encodesTo(bytes: []const u8, text: []const u8) bool {
    if (base64.Encoder.calcSize(bytes.len) != text.len) return false;
    var buffer: [1024]u8 = undefined;
    var read: usize = 0;
    var written: usize = 0;
    while (read < bytes.len) {
        const chunk = bytes[read..][0..@min(768, bytes.len - read)];
        const encoded = base64.Encoder.encode(&buffer, chunk);
        if (!std.mem.eql(u8, encoded, text[written..][0..encoded.len])) return false;
        read += chunk.len;
        written += encoded.len;
    }
    return true;
}

fn digestOf(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    return digest;
}

// Execution.

pub const Answer = enum {
    response,
    unavailable,
    limit_exceeded,

    pub fn name(answer: Answer) []const u8 {
        return switch (answer) {
            .limit_exceeded => "limit-exceeded",
            else => @tagName(answer),
        };
    }
};

pub const RequestRecord = struct {
    /// The request's ordinal.
    request: usize,
    /// The URL that the issuance announced, or null when the request ended before the laboratory drained it.
    url: ?[]const u8,
    /// How the laboratory answered the request, or null when it did not.
    answer: ?Answer,
};

pub const EventType = enum { request_issued, request_cancelled, document_state_changed };

/// An engine event whose identifiers are ordinals in order of first appearance.
pub const Event = struct {
    event: EventType,
    document: usize,
    request: usize,
    kind: engine.RequestKind,
    version: u32,
    /// The URL of a request notice, or null.
    url: ?[]const u8 = null,
    /// The new state of a state change, or null.
    state: ?engine.DocumentState = null,
    reject_reason: ?engine.RejectReason = null,

    pub fn eql(a: Event, b: Event) bool {
        const urls_equal = if (a.url) |left|
            b.url != null and std.mem.eql(u8, left, b.url.?)
        else
            b.url == null;
        return a.event == b.event and a.document == b.document and a.request == b.request and a.kind == b.kind and
            a.version == b.version and urls_equal and std.meta.eql(a.state, b.state) and
            std.meta.eql(a.reject_reason, b.reject_reason);
    }
};

fn eventsEql(a: []const Event, b: []const Event) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!left.eql(right)) return false;
    }
    return true;
}

/// A host action. Documents and requests are ordinals.
pub const Action = union(enum) {
    create_document,
    load: struct { document: usize, url: []const u8 },
    respond: struct { request: usize, body: []const u8 },
    cancel: struct { request: usize },
    step: struct { budget: u32 },
};

/// A host action, the engine error that it returned, and the events that the laboratory drained after it.
pub const Record = struct {
    action: Action,
    /// The engine error name, or null when the action succeeded.
    @"error": ?[]const u8,
    /// The drained events are `events[first_event..end_event]` of the execution.
    first_event: usize,
    end_event: usize,
};

pub const BodySummary = struct {
    length: usize,
    sha256: [32]u8,
};

/// What the `decode` stage recorded when it completed.
pub const Decoded = struct {
    encoding: Encoding,
    confidence: Confidence,
    /// The length of the byte order mark that BOM sniffing removed.
    bom_bytes: usize,
    /// The number of decoded UTF-16 code units.
    code_units: usize,
    /// The SHA-256 of the decoded code units in little-endian order.
    output_sha256: [32]u8,
};

/// What the `tokenize` stage recorded when it completed.
pub const Tokenized = struct {
    /// The number of lines of the token dump.
    token_count: u64,
    tokens_sha256: [32]u8,
    /// Every parse error in step order.
    errors: []const ErrorRecord,
};

/// The pipeline state of one run.
pub const Execution = struct {
    fetch: Status = .not_reached,
    requests: std.ArrayList(RequestRecord) = .empty,
    /// The document's state when the run ended, or null when no load completed.
    document_state: ?engine.DocumentState = null,
    /// The loaded body's length and digest, or null unless the document loaded.
    body: ?BodySummary = null,
    events: std.ArrayList(Event) = .empty,
    records: std.ArrayList(Record) = .empty,
    /// The number of `Engine.step` calls.
    steps: u64 = 0,
    decode: Status = .not_reached,
    /// The record of a completed `decode` stage, or null.
    decoded: ?Decoded = null,
    /// Why an `unsupported` `decode` stage could not decode the body, or null.
    decode_detail: ?[]const u8 = null,
    tokenize: Status = .not_reached,
    /// The record of a completed `tokenize` stage, or null.
    tokenized: ?Tokenized = null,
    /// The stage that a harness error interrupted.
    harness_stage: Stage = .fetch,
};

/// Drives one engine and normalizes the events that it drains.
const Session = struct {
    arena: Allocator,
    engine: *engine.Engine,
    documents: std.ArrayList(engine.DocumentId) = .empty,
    requests: std.ArrayList(engine.RequestId) = .empty,
    events: *std.ArrayList(Event),

    fn documentOrdinal(session: *Session, id: engine.DocumentId) Allocator.Error!usize {
        for (session.documents.items, 1..) |known, ordinal| {
            if (known == id) return ordinal;
        }
        try session.documents.append(session.arena, id);
        return session.documents.items.len;
    }

    fn requestOrdinal(session: *Session, id: engine.RequestId) Allocator.Error!usize {
        for (session.requests.items, 1..) |known, ordinal| {
            if (known == id) return ordinal;
        }
        try session.requests.append(session.arena, id);
        return session.requests.items.len;
    }

    fn document(session: *Session, ordinal: usize) error{UnknownOrdinal}!engine.DocumentId {
        if (ordinal == 0 or ordinal > session.documents.items.len) return error.UnknownOrdinal;
        return session.documents.items[ordinal - 1];
    }

    fn request(session: *Session, ordinal: usize) error{UnknownOrdinal}!engine.RequestId {
        if (ordinal == 0 or ordinal > session.requests.items.len) return error.UnknownOrdinal;
        return session.requests.items[ordinal - 1];
    }

    /// Drains every ready event in order.
    fn drain(session: *Session) (Allocator.Error || engine.ThreadError)!void {
        while (true) {
            try session.events.ensureUnusedCapacity(session.arena, 1);
            try session.documents.ensureUnusedCapacity(session.arena, 1);
            try session.requests.ensureUnusedCapacity(session.arena, 1);
            const event = try session.engine.nextEvent() orelse return;
            const normalized: Event = switch (event) {
                .request_issued, .request_cancelled => |notice| .{
                    .event = if (event == .request_issued) .request_issued else .request_cancelled,
                    .document = try session.documentOrdinal(notice.document),
                    .request = try session.requestOrdinal(notice.request),
                    .kind = notice.kind,
                    .version = notice.version,
                    .url = if (notice.url) |url| try session.arena.dupe(u8, url) else null,
                },
                .document_state_changed => |change| .{
                    .event = .document_state_changed,
                    .document = try session.documentOrdinal(change.document),
                    .request = try session.requestOrdinal(change.request),
                    .kind = change.kind,
                    .version = change.version,
                    .state = change.state,
                    .reject_reason = change.reject_reason,
                },
            };
            session.events.appendAssumeCapacity(normalized);
        }
    }
};

const Interrupt = error{ OutOfMemory, Harness };

const Executor = struct {
    session: Session,
    case: *const Case,
    execution: *Execution,
    failure: *Detail,

    /// Records an engine error as a harness error, or passes on `error.OutOfMemory`.
    fn engineError(x: *Executor, operation: []const u8, err: anyerror) Interrupt {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        x.failure.* = .{ .subject = operation, .message = @errorName(err) };
        return error.Harness;
    }

    /// Records a completed host action and the events that it made ready.
    fn record(x: *Executor, action: Action, error_name: ?[]const u8) Interrupt!void {
        const arena = x.session.arena;
        const first = x.execution.events.items.len;
        x.session.drain() catch |err| return x.engineError("Engine.nextEvent", err);
        try x.execution.records.append(arena, .{
            .action = action,
            .@"error" = error_name,
            .first_event = first,
            .end_event = x.execution.events.items.len,
        });
        for (x.execution.events.items[first..]) |event| {
            if (event.event != .request_issued) continue;
            try x.execution.requests.append(arena, .{ .request = event.request, .url = event.url, .answer = null });
        }
    }

    /// Answers every issued, unanswered request from the case.
    fn answerRequests(x: *Executor) Interrupt!void {
        const eng = x.session.engine;
        var index: usize = 0;
        while (index < x.execution.requests.items.len) : (index += 1) {
            const pending = x.execution.requests.items[index];
            if (pending.answer != null) continue;
            const url = pending.url orelse continue;
            const id = x.session.requests.items[pending.request - 1];
            const answer: Answer = if (x.case.answer(url)) |body| respond: {
                eng.respond(id, engine.resource_request_version, body) catch |err| switch (err) {
                    error.LimitExceeded => {
                        try x.record(.{ .respond = .{ .request = pending.request, .body = body } }, @errorName(err));
                        eng.cancel(id) catch |cancel_err| return x.engineError("Engine.cancel", cancel_err);
                        try x.record(.{ .cancel = .{ .request = pending.request } }, null);
                        break :respond .limit_exceeded;
                    },
                    else => return x.engineError("Engine.respond", err),
                };
                try x.record(.{ .respond = .{ .request = pending.request, .body = body } }, null);
                break :respond .response;
            } else cancel: {
                eng.cancel(id) catch |err| return x.engineError("Engine.cancel", err);
                try x.record(.{ .cancel = .{ .request = pending.request } }, null);
                break :cancel .unavailable;
            };
            x.execution.requests.items[index].answer = answer;
        }
    }
};

/// Runs `case` against a new engine that allocates with `gpa`. The execution allocates with `arena`.
fn execute(gpa: Allocator, arena: Allocator, case: *const Case, execution: *Execution, failure: *Detail) Interrupt!void {
    execution.fetch = .failed;
    const eng = engine.Engine.create(gpa, .{
        .max_outstanding_requests = case.limits.max_outstanding_requests,
        .max_response_body_bytes = case.limits.max_response_body_bytes,
    }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        failure.* = .{ .subject = "Engine.create", .message = @errorName(err) };
        return error.Harness;
    };
    // The laboratory calls the engine only from the thread that created it.
    defer eng.destroy() catch unreachable;
    var x: Executor = .{
        .session = .{ .arena = arena, .engine = eng, .events = &execution.events },
        .case = case,
        .execution = execution,
        .failure = failure,
    };
    const document = eng.createDocument() catch |err| return x.engineError("Engine.createDocument", err);
    const ordinal = try x.session.documentOrdinal(document);
    try x.record(.create_document, null);
    _ = eng.load(document, case.document.url) catch |err| return x.engineError("Engine.load", err);
    try x.record(.{ .load = .{ .document = ordinal, .url = case.document.url } }, null);
    try x.answerRequests();
    var view = eng.document(document) catch |err| return x.engineError("Engine.document", err);
    while (view.state == .loading and execution.steps < case.limits.max_steps) {
        _ = eng.step(case.limits.step_budget) catch |err| return x.engineError("Engine.step", err);
        execution.steps += 1;
        try x.record(.{ .step = .{ .budget = case.limits.step_budget } }, null);
        try x.answerRequests();
        view = eng.document(document) catch |err| return x.engineError("Engine.document", err);
    }
    execution.document_state = view.state;
    if (view.state != .loading) execution.fetch = .completed;
    if (view.state != .loaded) return;
    execution.body = .{ .length = view.body.len, .sha256 = digestOf(view.body) };
    // The engine's body stays valid until `eng.destroy`.
    const decoded = try decode(arena, view.body, execution) orelse return;
    try tokenize(gpa, arena, decoded, execution, failure);
}

const utf8_bom = "\xEF\xBB\xBF";

/// Runs the `decode` stage on a loaded body: step 1 of the encoding sniffing algorithm, BOM sniffing.
/// A UTF-8 byte order mark selects UTF-8 with confidence `certain`, and the stage decodes the remaining bytes
/// with the UTF-8 decoder with replacement. Every other body is `unsupported`, because task FP-0065 owns
/// the UTF-16 decoders and the encoding sniffing steps after BOM sniffing.
/// Returns the decoded code units, or null when the stage is unsupported.
fn decode(arena: Allocator, body: []const u8, execution: *Execution) Allocator.Error!?[]const u16 {
    execution.harness_stage = .decode;
    if (!std.mem.startsWith(u8, body, utf8_bom)) {
        execution.decode = .unsupported;
        execution.decode_detail = if (std.mem.startsWith(u8, body, "\xFE\xFF"))
            "UTF-16BE byte order mark; the UTF-16BE decoder is not implemented"
        else if (std.mem.startsWith(u8, body, "\xFF\xFE"))
            "UTF-16LE byte order mark; the UTF-16LE decoder is not implemented"
        else
            "no byte order mark; encoding sniffing after BOM sniffing is not implemented";
        return null;
    }
    const output = try WebString.fromUtf8Lossy(arena, body[utf8_bom.len..]);
    execution.decoded = .{
        .encoding = .@"UTF-8",
        .confidence = .certain,
        .bom_bytes = utf8_bom.len,
        .code_units = output.units.len,
        .output_sha256 = digestOfUnits(output.units),
    };
    execution.decode = .completed;
    return output.units;
}

/// Returns the SHA-256 of `units` in little-endian order.
fn digestOfUnits(units: []const u16) [32]u8 {
    var hasher: Sha256 = .init(.{});
    var buffer: [512]u8 = undefined;
    var index: usize = 0;
    while (index < units.len) {
        const count = @min(buffer.len / 2, units.len - index);
        for (units[index..][0..count], 0..) |unit, position| {
            std.mem.writeInt(u16, buffer[2 * position ..][0..2], unit, .little);
        }
        hasher.update(buffer[0 .. 2 * count]);
        index += count;
    }
    return hasher.finalResult();
}

/// Runs the `tokenize` stage: `html.Tokenizer` on the decoded code units in one chunk.
/// It records the number of lines and the SHA-256 of the token dump, and every parse error in step order.
/// The laboratory never sets `adjusted_current_node_is_foreign`, so any tokenizer error is a harness error.
fn tokenize(gpa: Allocator, arena: Allocator, units: []const u16, execution: *Execution, failure: *Detail) Interrupt!void {
    execution.harness_stage = .tokenize;
    execution.tokenize = .failed;
    var tokenizer: html.Tokenizer = .init(gpa);
    defer tokenizer.deinit();
    var buffer: [4096]u8 = undefined;
    var hashing: Writer.Hashing(Sha256) = .init(&buffer);
    var dumper: html.dump.Dumper = .init(gpa, &hashing.writer, html.dump.tokens);
    defer dumper.deinit();
    var errors: std.ArrayList(ErrorRecord) = .empty;
    tokenizer.feed(units) catch |err| return tokenizerError(failure, "Tokenizer.feed", err);
    tokenizer.finish() catch |err| return tokenizerError(failure, "Tokenizer.finish", err);
    while (tokenizer.next() catch |err| return tokenizerError(failure, "Tokenizer.next", err)) |step| {
        switch (step) {
            .need_input => {
                failure.* = .{ .subject = "Tokenizer.next", .message = "need_input after finish" };
                return error.Harness;
            },
            .parse_error => |e| try errors.append(arena, .{
                .code = e.code,
                .line = e.position.line,
                .column = e.position.column,
                .offset = @backingInt(e.position.offset),
            }),
            .token => {},
        }
        dumper.step(step) catch |err| return dumpError(err);
    }
    dumper.finish() catch |err| return dumpError(err);
    // A hashing writer never fails.
    hashing.writer.flush() catch unreachable;
    execution.tokenized = .{
        .token_count = dumper.lines,
        .tokens_sha256 = hashing.hasher.finalResult(),
        .errors = errors.items,
    };
    execution.tokenize = .completed;
}

fn tokenizerError(failure: *Detail, operation: []const u8, err: html.Error) Interrupt {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    failure.* = .{ .subject = operation, .message = @errorName(err) };
    return error.Harness;
}

fn dumpError(err: html.dump.Dumper.Error) error{OutOfMemory} {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        // A hashing writer never fails.
        error.WriteFailed => unreachable,
    };
}

// Outcomes.

pub const Check = enum { document_state, body_sha256, encoding, confidence, output_sha256, token_count, tokens_sha256, errors };

/// The first differing check of a `fail` outcome and both of its values.
pub const Mismatch = union(Check) {
    document_state: struct { expected: FinalState, observed: engine.DocumentState },
    body_sha256: struct { expected: ?[32]u8, observed: ?[32]u8 },
    encoding: struct { expected: Encoding, observed: Encoding },
    confidence: struct { expected: Confidence, observed: Confidence },
    output_sha256: struct { expected: [32]u8, observed: [32]u8 },
    token_count: struct { expected: u64, observed: u64 },
    tokens_sha256: struct { expected: [32]u8, observed: [32]u8 },
    errors: struct { expected: []const ErrorRecord, observed: []const ErrorRecord },
};

pub const Outcome = struct {
    result: Result,
    /// The stage that the outcome concerns, or null.
    stage: ?Stage = null,
    mismatch: ?Mismatch = null,
    detail: ?Detail = null,
};

/// The members of an outcome that the minimizer preserves.
pub const Signature = struct {
    result: Result,
    stage: ?Stage,
    check: ?Check,

    pub fn of(outcome: Outcome) Signature {
        return .{
            .result = outcome.result,
            .stage = outcome.stage,
            .check = if (outcome.mismatch) |mismatch| std.meta.activeTag(mismatch) else null,
        };
    }

    pub fn eql(a: Signature, b: Signature) bool {
        return std.meta.eql(a, b);
    }
};

/// Classifies a completed execution against the case's expectation.
///
/// The outcomes take precedence in this order: `harness-error`, then `timeout`, then `unsupported`, then `fail` or `pass`.
/// A harness error, found while parsing or executing the case, ends the run before this function.
/// A document that is still loading after `max_steps` calls to `Engine.step` is a `timeout`, even when the expectation names an
/// unimplemented stage. Otherwise an expectation for an unimplemented stage is `unsupported`, and a `fetch` expectation
/// is `fail` at its first differing check or `pass`.
/// A `decode` or `tokenize` expectation for a document that did not load is `fail` on `document_state`;
/// otherwise it is `unsupported` with the `decode` detail when the `decode` stage is unsupported,
/// and then `fail` at its first differing check or `pass`.
fn conclude(case: *const Case, execution: *const Execution) Outcome {
    const state = execution.document_state.?;
    if (state == .loading) return .{
        .result = .timeout,
        .stage = .fetch,
        .detail = .{ .subject = "fetch", .message = "the document is still loading after max_steps calls to Engine.step" },
    };
    switch (case.expect) {
        .unsupported => |stage| return .{
            .result = .unsupported,
            .stage = stage,
            .detail = .{ .subject = @tagName(stage), .message = "this stage is not implemented" },
        },
        .fetch => |expected| {
            const expected_state: engine.DocumentState = switch (expected.document_state) {
                .loaded => .loaded,
                .failed => .failed,
            };
            if (state != expected_state) return .{
                .result = .fail,
                .stage = .fetch,
                .mismatch = .{ .document_state = .{ .expected = expected.document_state, .observed = state } },
            };
            const observed: ?[32]u8 = if (execution.body) |body| body.sha256 else null;
            if (!std.meta.eql(expected.body_sha256, observed)) return .{
                .result = .fail,
                .stage = .fetch,
                .mismatch = .{ .body_sha256 = .{ .expected = expected.body_sha256, .observed = observed } },
            };
            return .{ .result = .pass, .stage = .fetch };
        },
        .decode, .tokenize => {
            const stage: Stage = if (case.expect == .decode) .decode else .tokenize;
            if (state != .loaded) return .{
                .result = .fail,
                .stage = stage,
                .mismatch = .{ .document_state = .{ .expected = .loaded, .observed = state } },
            };
            if (execution.decode == .unsupported) return .{
                .result = .unsupported,
                .stage = .decode,
                .detail = .{ .message = execution.decode_detail.? },
            };
            return switch (case.expect) {
                .decode => |expected| concludeDecode(expected, execution.decoded.?),
                .tokenize => |expected| concludeTokenize(expected, execution.tokenized.?),
                else => unreachable,
            };
        },
    }
}

fn concludeDecode(expected: DecodeExpectation, observed: Decoded) Outcome {
    const mismatch: ?Mismatch = if (expected.encoding != observed.encoding)
        .{ .encoding = .{ .expected = expected.encoding, .observed = observed.encoding } }
    else if (expected.confidence != observed.confidence)
        .{ .confidence = .{ .expected = expected.confidence, .observed = observed.confidence } }
    else if (!std.mem.eql(u8, &expected.output_sha256, &observed.output_sha256))
        .{ .output_sha256 = .{ .expected = expected.output_sha256, .observed = observed.output_sha256 } }
    else
        null;
    return .{ .result = if (mismatch == null) .pass else .fail, .stage = .decode, .mismatch = mismatch };
}

fn concludeTokenize(expected: TokenizeExpectation, observed: Tokenized) Outcome {
    const mismatch: ?Mismatch = if (expected.token_count != observed.token_count)
        .{ .token_count = .{ .expected = expected.token_count, .observed = observed.token_count } }
    else if (!std.mem.eql(u8, &expected.tokens_sha256, &observed.tokens_sha256))
        .{ .tokens_sha256 = .{ .expected = expected.tokens_sha256, .observed = observed.tokens_sha256 } }
    else if (!errorsEql(expected.errors, observed.errors))
        .{ .errors = .{ .expected = expected.errors, .observed = observed.errors } }
    else
        null;
    return .{ .result = if (mismatch == null) .pass else .fail, .stage = .tokenize, .mismatch = mismatch };
}

/// Runs `case` against a new engine and returns the signature of its outcome.
/// Only allocation failure is an error; every other failure is part of the signature.
pub fn signatureOf(gpa: Allocator, case: *const Case) Allocator.Error!Signature {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var execution: Execution = .{};
    var failure: Detail = undefined;
    execute(gpa, arena.allocator(), case, &execution, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Harness => return .{ .result = .harness_error, .stage = execution.harness_stage, .check = null },
    };
    return .of(conclude(case, &execution));
}

// Runs.

pub const Run = struct {
    arena: std.heap.ArenaAllocator,
    /// The SHA-256 of the case file bytes, or null when the file could not be read.
    case_sha256: ?[32]u8,
    case: ?Case = null,
    execution: Execution = .{},
    outcome: Outcome,

    /// Returns a run that reports a harness error found before the case ran.
    pub fn initHarnessError(gpa: Allocator, case_sha256: ?[32]u8, detail: Detail) Run {
        return .{ .arena = .init(gpa), .case_sha256 = case_sha256, .outcome = .{ .result = .harness_error, .detail = detail } };
    }

    pub fn deinit(run: *Run) void {
        run.arena.deinit();
        run.* = undefined;
    }

    /// Returns the status that the result reports for `stage`.
    ///
    /// A stage that this task does not implement is `unsupported`.
    /// The `fetch` status says whether the stage finished, not whether the document loaded:
    /// `completed` means the document reached `loaded` or `failed`, so a document that failed still has a `completed` fetch;
    /// `failed` means the stage did not finish, after a `timeout` or a harness error;
    /// `not-reached` means the case did not run.
    /// A `fetch` status of `failed` therefore differs from a `document_state` of `failed`.
    /// `decode` runs only when the document loaded, and it is `completed` or `unsupported`.
    /// `tokenize` runs only when `decode` completed, and it is `completed`, or `failed` after a harness error.
    /// Otherwise each of them is `not-reached`.
    pub fn stageStatus(run: *const Run, stage: Stage) Status {
        return switch (stage) {
            .fetch => run.execution.fetch,
            .decode => run.execution.decode,
            .tokenize => run.execution.tokenize,
            else => .unsupported,
        };
    }

    /// Whether the run has a transcript: the case ran without a harness error.
    pub fn hasTranscript(run: *const Run) bool {
        return run.case != null and run.outcome.result != .harness_error;
    }

    pub fn writeResult(run: *const Run, writer: *Writer) Writer.Error!void {
        var s: Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
        try s.beginObject();
        try s.objectField("format");
        try s.write("fairpane-lab-result");
        try s.objectField("version");
        try s.write(1);
        try s.objectField("case");
        try writeDigest(&s, run.case_sha256);
        try s.objectField("corpus");
        try writeCorpus(&s, if (run.case) |case| case.corpus else null);
        try s.objectField("inputs");
        if (run.case) |*case| try writeInputs(&s, case) else try s.write(null);
        try s.objectField("environment_consumers");
        try s.beginObject();
        for (std.enums.values(EnvironmentField)) |field| {
            try s.objectField(@tagName(field));
            try s.beginArray();
            for (environmentConsumers(field)) |stage| try s.write(@tagName(stage));
            try s.endArray();
        }
        try s.endObject();
        try s.objectField("stages");
        try s.beginArray();
        for (std.enums.values(Stage)) |stage| {
            try s.beginObject();
            try s.objectField("stage");
            try s.write(@tagName(stage));
            try s.objectField("status");
            try s.write(run.stageStatus(stage).name());
            switch (stage) {
                .fetch => try run.writeFetch(&s),
                .decode => try run.writeDecode(&s),
                .tokenize => try run.writeTokenize(&s),
                else => {},
            }
            try s.endObject();
        }
        try s.endArray();
        try s.objectField("events");
        try writeEvents(&s, run.execution.events.items);
        try s.objectField("steps");
        try s.write(run.execution.steps);
        try s.objectField("outcome");
        try writeOutcome(&s, run.outcome);
        try s.endObject();
        try writer.writeByte('\n');
    }

    fn writeFetch(run: *const Run, s: *Stringify) Writer.Error!void {
        const execution = &run.execution;
        try s.objectField("requests");
        try s.beginArray();
        for (execution.requests.items) |request| {
            try s.beginObject();
            try s.objectField("request");
            try s.write(request.request);
            try s.objectField("url");
            try s.write(request.url);
            try s.objectField("answer");
            try s.write(if (request.answer) |answer| answer.name() else null);
            try s.endObject();
        }
        try s.endArray();
        try s.objectField("document_state");
        try s.write(if (execution.document_state) |state| @tagName(state) else null);
        try s.objectField("body_length");
        try s.write(if (execution.body) |body| body.length else null);
        try s.objectField("body_sha256");
        try writeDigest(s, if (execution.body) |body| body.sha256 else null);
    }

    /// Writes the `decode` record. Each member is null unless the stage reached the state that records it.
    fn writeDecode(run: *const Run, s: *Stringify) Writer.Error!void {
        const decoded = run.execution.decoded;
        try s.objectField("encoding");
        try s.write(if (decoded) |d| @tagName(d.encoding) else null);
        try s.objectField("confidence");
        try s.write(if (decoded) |d| @tagName(d.confidence) else null);
        try s.objectField("bom_bytes");
        try s.write(if (decoded) |d| d.bom_bytes else null);
        try s.objectField("code_units");
        try s.write(if (decoded) |d| d.code_units else null);
        try s.objectField("output_sha256");
        try writeDigest(s, if (decoded) |d| d.output_sha256 else null);
        try s.objectField("detail");
        try s.write(run.execution.decode_detail);
    }

    /// Writes the `tokenize` record. Each member is null unless the stage completed.
    fn writeTokenize(run: *const Run, s: *Stringify) Writer.Error!void {
        const tokenized = run.execution.tokenized;
        try s.objectField("token_count");
        try s.write(if (tokenized) |t| t.token_count else null);
        try s.objectField("tokens_sha256");
        try writeDigest(s, if (tokenized) |t| t.tokens_sha256 else null);
        try s.objectField("errors");
        if (tokenized) |t| try writeErrors(s, t.errors) else try s.write(null);
    }

    /// Writes every host action and the normalized events drained after it.
    /// Requires `hasTranscript`.
    pub fn writeTranscript(run: *const Run, writer: *Writer) Writer.Error!void {
        std.debug.assert(run.hasTranscript());
        const case = &run.case.?;
        var s: Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
        try s.beginObject();
        try s.objectField("format");
        try s.write("fairpane-lab-transcript");
        try s.objectField("version");
        try s.write(2);
        try s.objectField("case");
        try writeDigest(&s, run.case_sha256);
        try s.objectField("engine_options");
        try s.beginObject();
        try s.objectField("max_outstanding_requests");
        try s.write(case.limits.max_outstanding_requests);
        try s.objectField("max_response_body_bytes");
        try s.write(case.limits.max_response_body_bytes);
        try s.endObject();
        try s.objectField("action_count");
        try s.write(run.execution.records.items.len);
        try s.objectField("actions");
        try s.beginArray();
        const events = run.execution.events.items;
        for (run.execution.records.items) |record| {
            try writeAction(&s, record.action, record.@"error", events[record.first_event..record.end_event]);
        }
        try s.endArray();
        try s.objectField("document_states");
        try s.beginArray();
        try s.write(@tagName(run.execution.document_state.?));
        try s.endArray();
        try s.endObject();
        try writer.writeByte('\n');
    }
};

/// Runs the case in `case_bytes`. The run owns copies of everything it reports, so it does not borrow `case_bytes`.
/// Every failure, including allocation failure, becomes a `harness-error` outcome.
pub fn runCase(gpa: Allocator, case_bytes: []const u8) Run {
    var run: Run = .{ .arena = .init(gpa), .case_sha256 = digestOf(case_bytes), .outcome = undefined };
    run.outcome = runOutcome(&run, gpa, case_bytes);
    return run;
}

fn runOutcome(run: *Run, gpa: Allocator, case_bytes: []const u8) Outcome {
    const arena = run.arena.allocator();
    var diagnostic: Detail = undefined;
    run.case = parseCase(arena, case_bytes, &diagnostic) catch |err| return .{ .result = .harness_error, .detail = switch (err) {
        error.OutOfMemory => out_of_memory,
        error.Invalid => diagnostic,
    } };
    var failure: Detail = undefined;
    execute(gpa, arena, &run.case.?, &run.execution, &failure) catch |err| return .{
        .result = .harness_error,
        .stage = run.execution.harness_stage,
        .detail = switch (err) {
            error.OutOfMemory => out_of_memory,
            error.Harness => failure,
        },
    };
    return conclude(&run.case.?, &run.execution);
}

// Replay.

const TranscriptAction = struct {
    action: Action,
    @"error": ?[]const u8,
    events: []const Event,
};

const Transcript = struct {
    options: engine.Options,
    actions: []const TranscriptAction,
    document_states: []const engine.DocumentState,
};

/// The first difference between a transcript and its replay, with both values.
pub const ReplayMismatch = union(enum) {
    events: struct { expected: []const Event, observed: []const Event },
    @"error": struct { expected: ?[]const u8, observed: ?[]const u8 },
    document_states: struct { expected: []const engine.DocumentState, observed: []const engine.DocumentState },
};

pub const ReplayOutcome = struct {
    /// `pass`, `fail`, or `harness_error`.
    result: Result,
    /// The index of the action at the first difference, or null.
    action: ?usize = null,
    mismatch: ?ReplayMismatch = null,
    detail: ?Detail = null,
};

pub const Replay = struct {
    arena: std.heap.ArenaAllocator,
    /// The SHA-256 of the transcript bytes, or null when the file could not be read.
    transcript_sha256: ?[32]u8,
    /// The number of recorded actions.
    actions: usize = 0,
    outcome: ReplayOutcome,

    /// Returns a replay that reports a harness error found before the transcript was read.
    pub fn initHarnessError(gpa: Allocator, detail: Detail) Replay {
        return .{ .arena = .init(gpa), .transcript_sha256 = null, .outcome = .{ .result = .harness_error, .detail = detail } };
    }

    pub fn deinit(r: *Replay) void {
        r.arena.deinit();
        r.* = undefined;
    }

    pub fn writeResult(r: *const Replay, writer: *Writer) Writer.Error!void {
        var s: Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
        try s.beginObject();
        try s.objectField("format");
        try s.write("fairpane-lab-replay-result");
        try s.objectField("version");
        try s.write(1);
        try s.objectField("transcript");
        try writeDigest(&s, r.transcript_sha256);
        try s.objectField("actions");
        try s.write(r.actions);
        try s.objectField("outcome");
        try s.beginObject();
        try s.objectField("result");
        try s.write(r.outcome.result.name());
        try s.objectField("action");
        try s.write(r.outcome.action);
        try s.objectField("check");
        try s.write(if (r.outcome.mismatch) |mismatch| @tagName(mismatch) else null);
        if (r.outcome.mismatch) |mismatch| switch (mismatch) {
            .events => |events| {
                try s.objectField("expected");
                try writeEvents(&s, events.expected);
                try s.objectField("observed");
                try writeEvents(&s, events.observed);
            },
            .@"error" => |names| {
                try s.objectField("expected");
                try s.write(names.expected);
                try s.objectField("observed");
                try s.write(names.observed);
            },
            .document_states => |states| {
                try s.objectField("expected");
                try writeStates(&s, states.expected);
                try s.objectField("observed");
                try writeStates(&s, states.observed);
            },
        } else {
            try s.objectField("expected");
            try s.write(null);
            try s.objectField("observed");
            try s.write(null);
        }
        try s.objectField("detail");
        try writeDetail(&s, r.outcome.detail);
        try s.endObject();
        try s.endObject();
        try writer.writeByte('\n');
    }
};

/// Repeats the actions of a transcript against a new engine and compares every drained event and the final document states.
/// The replay does not borrow `transcript_bytes`. Every failure, including allocation failure, becomes a `harness-error` outcome.
pub fn replay(gpa: Allocator, transcript_bytes: []const u8) Replay {
    var result: Replay = .{ .arena = .init(gpa), .transcript_sha256 = digestOf(transcript_bytes), .outcome = undefined };
    result.outcome = replayOutcome(&result, gpa, transcript_bytes) catch |err| switch (err) {
        error.OutOfMemory => .{ .result = .harness_error, .detail = out_of_memory },
    };
    return result;
}

fn replayOutcome(r: *Replay, gpa: Allocator, bytes: []const u8) Allocator.Error!ReplayOutcome {
    const arena = r.arena.allocator();
    var diagnostic: Detail = undefined;
    var p: Parser = .{ .arena = arena, .diagnostic = &diagnostic };
    const transcript = p.transcript(bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return .{ .result = .harness_error, .detail = diagnostic },
    };
    r.actions = transcript.actions.len;

    const eng = engine.Engine.create(gpa, transcript.options) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .result = .harness_error, .detail = .{ .subject = "Engine.create", .message = @errorName(err) } };
    };
    // The replay calls the engine only from the thread that created it.
    defer eng.destroy() catch unreachable;
    var events: std.ArrayList(Event) = .empty;
    var session: Session = .{ .arena = arena, .engine = eng, .events = &events };
    for (transcript.actions, 0..) |recorded, index| {
        const observed_error = perform(&session, recorded.action) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnknownOrdinal => return .{
                .result = .harness_error,
                .action = index,
                .detail = .{ .subject = "actions[]", .message = "names a document or request that the replay has not observed" },
            },
        };
        if (!optionalBytesEql(recorded.@"error", observed_error)) return .{
            .result = .fail,
            .action = index,
            .mismatch = .{ .@"error" = .{ .expected = recorded.@"error", .observed = observed_error } },
        };
        const first = events.items.len;
        session.drain() catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return .{ .result = .harness_error, .action = index, .detail = .{ .subject = "Engine.nextEvent", .message = @errorName(err) } };
        };
        if (!eventsEql(recorded.events, events.items[first..])) return .{
            .result = .fail,
            .action = index,
            .mismatch = .{ .events = .{ .expected = recorded.events, .observed = events.items[first..] } },
        };
    }
    const states = try arena.alloc(engine.DocumentState, session.documents.items.len);
    for (session.documents.items, states) |id, *state| {
        const view = eng.document(id) catch |err| {
            return .{ .result = .harness_error, .detail = .{ .subject = "Engine.document", .message = @errorName(err) } };
        };
        state.* = view.state;
    }
    if (!std.mem.eql(engine.DocumentState, transcript.document_states, states)) return .{
        .result = .fail,
        .mismatch = .{ .document_states = .{ .expected = transcript.document_states, .observed = states } },
    };
    return .{ .result = .pass };
}

/// Performs one recorded action and returns the name of the engine error that it returned, or null.
fn perform(session: *Session, action: Action) error{ OutOfMemory, UnknownOrdinal }!?[]const u8 {
    const eng = session.engine;
    switch (action) {
        .create_document => {
            const id = eng.createDocument() catch |err| return errorName(err);
            _ = try session.documentOrdinal(id);
        },
        .load => |load| {
            _ = eng.load(try session.document(load.document), load.url) catch |err| return errorName(err);
        },
        .respond => |respond| {
            const id = try session.request(respond.request);
            eng.respond(id, engine.resource_request_version, respond.body) catch |err| return errorName(err);
        },
        .cancel => |cancel| {
            eng.cancel(try session.request(cancel.request)) catch |err| return errorName(err);
        },
        .step => |step| {
            _ = eng.step(step.budget) catch |err| return errorName(err);
        },
    }
    return null;
}

/// Returns the name of an engine error, or passes on `error.OutOfMemory`.
fn errorName(err: anyerror) error{OutOfMemory}!?[]const u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return @errorName(err);
}

fn optionalBytesEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |left| return b != null and std.mem.eql(u8, left, b.?);
    return b == null;
}

// Minimization.

/// Reduces `input`, a sequence of `T`, with the `ddmin` algorithm of Zeller and Hildebrandt,
/// "Simplifying and Isolating Failure-Inducing Input", IEEE TSE 28(2), 2002.
/// `predicate.holds(candidate)` must be deterministic, and it must hold for `input`;
/// otherwise this returns `error.PredicateDoesNotHold`.
/// The result is a subsequence of `input` for which the predicate holds, and it is 1-minimal:
/// removing any single element makes the predicate false.
/// The laboratory reduces bytes, so its callers pass `u8`; the HTML partition harness reduces UTF-16 code units.
/// The caller frees the result with `gpa`.
pub fn ddmin(comptime T: type, gpa: Allocator, input: []const T, predicate: anytype) ![]T {
    if (!try predicate.holds(input)) return error.PredicateDoesNotHold;
    const buffer = try gpa.alloc(T, input.len);
    errdefer gpa.free(buffer);
    @memcpy(buffer, input);
    const scratch = try gpa.alloc(T, input.len);
    defer gpa.free(scratch);
    var length = input.len;
    var granularity: usize = 2;
    reduce: while (length >= 2) {
        const current = buffer[0..length];
        const parts = @min(granularity, length);
        // Reduce to a subset: keep one part.
        for (0..parts) |part| {
            const start = part * length / parts;
            const end = (part + 1) * length / parts;
            if (try predicate.holds(current[start..end])) {
                std.mem.copyForwards(T, buffer, current[start..end]);
                length = end - start;
                granularity = 2;
                continue :reduce;
            }
        }
        // Reduce to a complement: remove one part. With two parts, each complement is a subset already tried.
        if (parts > 2) {
            for (0..parts) |part| {
                const start = part * length / parts;
                const end = (part + 1) * length / parts;
                const complement = scratch[0 .. length - (end - start)];
                @memcpy(complement[0..start], current[0..start]);
                @memcpy(complement[start..], current[end..]);
                if (try predicate.holds(complement)) {
                    @memcpy(buffer[0..complement.len], complement);
                    length = complement.len;
                    granularity = parts - 1;
                    continue :reduce;
                }
            }
        }
        // Increase the granularity, or stop when every part is a single element.
        if (parts == length) break;
        granularity = @min(length, 2 * parts);
    }
    if (length == 1 and try predicate.holds(buffer[0..0])) length = 0;
    return gpa.realloc(buffer, length);
}

/// Holds when a run of the case with a candidate document body has the target signature.
const BodyPredicate = struct {
    gpa: Allocator,
    case: Case,
    target: Signature,
    runs: *usize,

    fn holds(predicate: *BodyPredicate, body: []const u8) Allocator.Error!bool {
        var candidate = predicate.case;
        candidate.document.body = body;
        predicate.runs.* += 1;
        return (try signatureOf(predicate.gpa, &candidate)).eql(predicate.target);
    }
};

pub const Range = struct { before: usize, after: usize };

pub const MinimizeOutcome = struct {
    /// `pass` when the minimized case is ready, otherwise `harness_error`.
    result: Result,
    detail: ?Detail = null,
};

pub const Minimization = struct {
    arena: std.heap.ArenaAllocator,
    /// The SHA-256 of the case file bytes, or null when the file could not be read.
    case_sha256: ?[32]u8,
    /// The signature of the original run, or null when the case did not run.
    original: ?Signature = null,
    predicate_runs: usize = 0,
    resources: ?Range = null,
    document_body_length: ?Range = null,
    /// The minimized case document, which is complete only when the outcome is `pass`.
    output: []const u8 = "",
    outcome: MinimizeOutcome,

    /// Returns a minimization that reports a harness error found before the case was read.
    pub fn initHarnessError(gpa: Allocator, case_sha256: ?[32]u8, detail: Detail) Minimization {
        return .{ .arena = .init(gpa), .case_sha256 = case_sha256, .outcome = .{ .result = .harness_error, .detail = detail } };
    }

    pub fn deinit(m: *Minimization) void {
        m.arena.deinit();
        m.* = undefined;
    }

    pub fn writeReport(m: *const Minimization, writer: *Writer) Writer.Error!void {
        var s: Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
        try s.beginObject();
        try s.objectField("format");
        try s.write("fairpane-lab-minimize-result");
        try s.objectField("version");
        try s.write(1);
        try s.objectField("case");
        try writeDigest(&s, m.case_sha256);
        try s.objectField("original");
        if (m.original) |original| {
            try s.beginObject();
            try s.objectField("result");
            try s.write(original.result.name());
            try s.objectField("stage");
            try s.write(if (original.stage) |stage| @tagName(stage) else null);
            try s.objectField("check");
            try s.write(if (original.check) |check| @tagName(check) else null);
            try s.endObject();
        } else try s.write(null);
        try s.objectField("predicate_runs");
        try s.write(m.predicate_runs);
        try s.objectField("resources");
        try writeRange(&s, m.resources);
        try s.objectField("document_body_length");
        try writeRange(&s, m.document_body_length);
        try s.objectField("output");
        if (m.outcome.result == .pass) {
            try s.beginObject();
            try s.objectField("length");
            try s.write(m.output.len);
            try s.objectField("sha256");
            try writeDigest(&s, digestOf(m.output));
            try s.endObject();
        } else try s.write(null);
        try s.objectField("outcome");
        try s.beginObject();
        try s.objectField("result");
        try s.write(m.outcome.result.name());
        try s.objectField("detail");
        try writeDetail(&s, m.outcome.detail);
        try s.endObject();
        try s.endObject();
        try writer.writeByte('\n');
    }
};

/// Minimizes a case whose outcome is `fail` or `timeout`.
/// The predicate holds when a run of a candidate has the original run's result, stage, and check.
/// The minimizer removes whole resources one at a time while the predicate holds,
/// and then applies `ddmin` to the document body.
/// The minimized case is a version 2 case: its `corpus` is null, because its body no longer matches the corpus item,
/// and its `derived_from` names the SHA-256 of `case_bytes` and the original case's `corpus` value.
/// A case with any other outcome is a harness error.
pub fn minimize(gpa: Allocator, case_bytes: []const u8) Minimization {
    var m: Minimization = .{ .arena = .init(gpa), .case_sha256 = digestOf(case_bytes), .outcome = undefined };
    m.outcome = minimizeOutcome(&m, gpa, case_bytes) catch |err| switch (err) {
        error.OutOfMemory => .{ .result = .harness_error, .detail = out_of_memory },
    };
    return m;
}

fn minimizeOutcome(m: *Minimization, gpa: Allocator, case_bytes: []const u8) Allocator.Error!MinimizeOutcome {
    const arena = m.arena.allocator();
    var diagnostic: Detail = undefined;
    const case = parseCase(arena, case_bytes, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return .{ .result = .harness_error, .detail = diagnostic },
    };
    const original = try signatureOf(gpa, &case);
    m.original = original;
    if (original.result != .fail and original.result != .timeout) return .{
        .result = .harness_error,
        .detail = .{ .subject = "minimize", .message = "the case's outcome is neither fail nor timeout" },
    };

    var current = case;
    const kept = try arena.dupe(Input, case.resources);
    const candidate = try arena.alloc(Input, kept.len);
    var count = kept.len;
    var index: usize = 0;
    while (index < count) {
        @memcpy(candidate[0..index], kept[0..index]);
        @memcpy(candidate[index .. count - 1], kept[index + 1 .. count]);
        current.resources = candidate[0 .. count - 1];
        m.predicate_runs += 1;
        if ((try signatureOf(gpa, &current)).eql(original)) {
            @memcpy(kept[0 .. count - 1], candidate[0 .. count - 1]);
            count -= 1;
        } else {
            index += 1;
        }
    }
    current.resources = kept[0..count];
    m.resources = .{ .before = case.resources.len, .after = count };

    if (case.document.body) |body| {
        var predicate: BodyPredicate = .{ .gpa = gpa, .case = current, .target = original, .runs = &m.predicate_runs };
        const reduced = ddmin(u8, arena, body, &predicate) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PredicateDoesNotHold => return .{
                .result = .harness_error,
                .detail = .{ .subject = "minimize", .message = "the outcome changed although the case did not" },
            },
        };
        current.document.body = reduced;
        m.document_body_length = .{ .before = body.len, .after = reduced.len };
    }

    current.corpus = null;
    current.derived_from = .{ .case_sha256 = m.case_sha256.?, .corpus = case.corpus };

    var out: Writer.Allocating = .init(arena);
    writeCase(&out.writer, &current) catch return error.OutOfMemory;
    m.output = out.written();
    // The written case must reproduce the outcome that the reduction preserved.
    const written = parseCase(arena, m.output, &diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return .{ .result = .harness_error, .detail = .{ .subject = "minimize", .message = "the minimized case does not parse" } },
    };
    if (!(try signatureOf(gpa, &written)).eql(original)) return .{
        .result = .harness_error,
        .detail = .{ .subject = "minimize", .message = "the minimized case does not reproduce the outcome" },
    };
    return .{ .result = .pass };
}

/// Writes `case` as a case document: version 2 when it has `derived_from`, otherwise version 1.
/// The `expect` object is repeated as parsed.
fn writeCase(writer: *Writer, case: *const Case) Writer.Error!void {
    var s: Stringify = .{ .writer = writer, .options = .{ .whitespace = .indent_2 } };
    try s.beginObject();
    try s.objectField("format");
    try s.write("fairpane-lab-case");
    try s.objectField("version");
    try s.write(@as(u8, if (case.derived_from != null) 2 else 1));
    try s.objectField("corpus");
    try writeCorpus(&s, case.corpus);
    if (case.derived_from) |derived_from| {
        try s.objectField("derived_from");
        try s.beginObject();
        try s.objectField("case_sha256");
        try writeDigest(&s, derived_from.case_sha256);
        try s.objectField("corpus");
        try writeCorpus(&s, derived_from.corpus);
        try s.endObject();
    }
    try s.objectField("environment");
    try writeEnvironment(&s, case.environment);
    try s.objectField("document");
    try writeInput(&s, case.document);
    try s.objectField("resources");
    try s.beginArray();
    for (case.resources) |resource| try writeInput(&s, resource);
    try s.endArray();
    try s.objectField("limits");
    try s.beginObject();
    try s.objectField("max_steps");
    try s.write(case.limits.max_steps);
    try s.objectField("step_budget");
    try s.write(case.limits.step_budget);
    try s.objectField("max_outstanding_requests");
    try s.write(case.limits.max_outstanding_requests);
    try s.objectField("max_response_body_bytes");
    try s.write(case.limits.max_response_body_bytes);
    try s.endObject();
    try s.objectField("expect");
    try s.write(case.expect_json);
    try s.endObject();
    try writer.writeByte('\n');
}

// Shared JSON writers.

fn writeDigest(s: *Stringify, digest: ?[32]u8) Writer.Error!void {
    const bytes = digest orelse return s.write(null);
    const text = std.fmt.bytesToHex(bytes, .lower);
    try s.write(@as([]const u8, &text));
}

fn writeDetail(s: *Stringify, detail: ?Detail) Writer.Error!void {
    const value = detail orelse return s.write(null);
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    if (value.subject) |subject| {
        try Stringify.encodeJsonStringChars(subject, s.options, s.writer);
        try s.writer.writeAll(": ");
    }
    try Stringify.encodeJsonStringChars(value.message, s.options, s.writer);
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

/// Writes `bytes` as a canonical padded base64 string without an intermediate allocation.
fn writeBase64(s: *Stringify, bytes: []const u8) Writer.Error!void {
    try s.beginWriteRaw();
    try s.writer.writeByte('"');
    var buffer: [1024]u8 = undefined;
    var read: usize = 0;
    while (read < bytes.len) {
        const chunk = bytes[read..][0..@min(768, bytes.len - read)];
        try s.writer.writeAll(base64.Encoder.encode(&buffer, chunk));
        read += chunk.len;
    }
    try s.writer.writeByte('"');
    s.endWriteRaw();
}

fn writeCorpus(s: *Stringify, corpus: ?Corpus) Writer.Error!void {
    const value = corpus orelse return s.write(null);
    try s.beginObject();
    try s.objectField("name");
    try s.write(value.name);
    try s.objectField("revision");
    try s.write(value.revision);
    try s.objectField("path");
    try s.write(value.path);
    try s.objectField("blob");
    try s.write(value.blob);
    try s.endObject();
}

fn writeEnvironment(s: *Stringify, environment: Environment) Writer.Error!void {
    try s.beginObject();
    try s.objectField("time_origin_ms");
    try s.write(environment.time_origin_ms);
    try s.objectField("random_seed");
    try s.write(environment.random_seed);
    try s.objectField("viewport");
    try s.beginObject();
    try s.objectField("width");
    try s.write(environment.viewport.width);
    try s.objectField("height");
    try s.write(environment.viewport.height);
    try s.objectField("device_pixel_ratio_milli");
    try s.write(environment.viewport.device_pixel_ratio_milli);
    try s.endObject();
    try s.objectField("locale");
    try s.write(environment.locale);
    try s.objectField("time_zone");
    try s.write(environment.time_zone);
    try s.endObject();
}

/// Writes an input as it appears in a case document.
fn writeInput(s: *Stringify, input: Input) Writer.Error!void {
    try s.beginObject();
    try s.objectField("url");
    try s.write(input.url);
    try s.objectField("body_base64");
    if (input.body) |body| try writeBase64(s, body) else try s.write(null);
    try s.endObject();
}

/// Writes the URL, byte length, and SHA-256 of an input.
fn writeInputSummary(s: *Stringify, input: Input) Writer.Error!void {
    try s.beginObject();
    try s.objectField("url");
    try s.write(input.url);
    try s.objectField("length");
    try s.write(if (input.body) |body| body.len else null);
    try s.objectField("sha256");
    try writeDigest(s, if (input.body) |body| digestOf(body) else null);
    try s.endObject();
}

fn writeInputs(s: *Stringify, case: *const Case) Writer.Error!void {
    try s.beginObject();
    try s.objectField("document");
    try writeInputSummary(s, case.document);
    try s.objectField("resources");
    try s.beginArray();
    for (case.resources) |resource| try writeInputSummary(s, resource);
    try s.endArray();
    try s.objectField("environment");
    try writeEnvironment(s, case.environment);
    try s.endObject();
}

fn writeEvents(s: *Stringify, events: []const Event) Writer.Error!void {
    try s.beginArray();
    for (events) |event| {
        try s.beginObject();
        try s.objectField("event");
        try s.write(@tagName(event.event));
        try s.objectField("document");
        try s.write(event.document);
        try s.objectField("request");
        try s.write(event.request);
        try s.objectField("kind");
        try s.write(@tagName(event.kind));
        try s.objectField("version");
        try s.write(event.version);
        switch (event.event) {
            .request_issued, .request_cancelled => {
                try s.objectField("url");
                try s.write(event.url);
            },
            .document_state_changed => {
                try s.objectField("state");
                try s.write(@tagName(event.state.?));
                try s.objectField("reject_reason");
                try s.write(if (event.reject_reason) |reason| @tagName(reason) else null);
            },
        }
        try s.endObject();
    }
    try s.endArray();
}

fn writeStates(s: *Stringify, states: []const engine.DocumentState) Writer.Error!void {
    try s.beginArray();
    for (states) |state| try s.write(@tagName(state));
    try s.endArray();
}

fn writeAction(s: *Stringify, action: Action, error_name: ?[]const u8, events: []const Event) Writer.Error!void {
    try s.beginObject();
    try s.objectField("action");
    try s.write(@tagName(action));
    switch (action) {
        .create_document => {},
        .load => |load| {
            try s.objectField("document");
            try s.write(load.document);
            try s.objectField("url");
            try s.write(load.url);
        },
        .respond => |respond| {
            try s.objectField("request");
            try s.write(respond.request);
            try s.objectField("body_base64");
            try writeBase64(s, respond.body);
        },
        .cancel => |cancel| {
            try s.objectField("request");
            try s.write(cancel.request);
        },
        .step => |step| {
            try s.objectField("budget");
            try s.write(step.budget);
        },
    }
    try s.objectField("error");
    try s.write(error_name);
    try s.objectField("events");
    try writeEvents(s, events);
    try s.endObject();
}

fn writeOutcome(s: *Stringify, outcome: Outcome) Writer.Error!void {
    try s.beginObject();
    try s.objectField("result");
    try s.write(outcome.result.name());
    try s.objectField("stage");
    try s.write(if (outcome.stage) |stage| @tagName(stage) else null);
    try s.objectField("check");
    try s.write(if (outcome.mismatch) |mismatch| @tagName(mismatch) else null);
    if (outcome.mismatch) |mismatch| switch (mismatch) {
        .document_state => |values| {
            try s.objectField("expected");
            try s.write(@tagName(values.expected));
            try s.objectField("observed");
            try s.write(@tagName(values.observed));
        },
        .body_sha256 => |values| {
            try s.objectField("expected");
            try writeDigest(s, values.expected);
            try s.objectField("observed");
            try writeDigest(s, values.observed);
        },
        .encoding => |values| {
            try s.objectField("expected");
            try s.write(@tagName(values.expected));
            try s.objectField("observed");
            try s.write(@tagName(values.observed));
        },
        .confidence => |values| {
            try s.objectField("expected");
            try s.write(@tagName(values.expected));
            try s.objectField("observed");
            try s.write(@tagName(values.observed));
        },
        .output_sha256 => |values| {
            try s.objectField("expected");
            try writeDigest(s, values.expected);
            try s.objectField("observed");
            try writeDigest(s, values.observed);
        },
        .tokens_sha256 => |values| {
            try s.objectField("expected");
            try writeDigest(s, values.expected);
            try s.objectField("observed");
            try writeDigest(s, values.observed);
        },
        .token_count => |values| {
            try s.objectField("expected");
            try s.write(values.expected);
            try s.objectField("observed");
            try s.write(values.observed);
        },
        .errors => |values| {
            try s.objectField("expected");
            try writeErrors(s, values.expected);
            try s.objectField("observed");
            try writeErrors(s, values.observed);
        },
    } else {
        try s.objectField("expected");
        try s.write(null);
        try s.objectField("observed");
        try s.write(null);
    }
    try s.objectField("detail");
    try writeDetail(s, outcome.detail);
    try s.endObject();
}

/// Writes parse error records as an array of `{code, line, column, offset}` objects.
fn writeErrors(s: *Stringify, records: []const ErrorRecord) Writer.Error!void {
    try s.beginArray();
    for (records) |record| {
        try s.beginObject();
        try s.objectField("code");
        try s.write(html.errors.name(record.code));
        try s.objectField("line");
        try s.write(record.line);
        try s.objectField("column");
        try s.write(record.column);
        try s.objectField("offset");
        try s.write(record.offset);
        try s.endObject();
    }
    try s.endArray();
}

fn writeRange(s: *Stringify, range: ?Range) Writer.Error!void {
    const value = range orelse return s.write(null);
    try s.beginObject();
    try s.objectField("before");
    try s.write(value.before);
    try s.objectField("after");
    try s.write(value.after);
    try s.endObject();
}

// Tests read their fixtures from `tests/lab`, relative to the build root.

fn readFixture(name: []const u8) ![]u8 {
    var path_buffer: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "tests/lab/{s}", .{name});
    return std.Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(case_size_limit));
}

fn runFixture(name: []const u8) !Run {
    const bytes = try readFixture(name);
    defer testing.allocator.free(bytes);
    return runCase(testing.allocator, bytes);
}

/// Renders the result document of `run` and parses it back.
fn resultJson(arena: Allocator, run: *const Run) !std.json.Value {
    var out: Writer.Allocating = .init(arena);
    try run.writeResult(&out.writer);
    return std.json.parseFromSliceLeaky(std.json.Value, arena, out.written(), .{});
}

fn member(value: std.json.Value, name: []const u8) !std.json.Value {
    if (value != .object) return error.TestUnexpectedResult;
    return value.object.get(name) orelse error.TestUnexpectedResult;
}

fn expectString(expected: []const u8, value: std.json.Value) !void {
    try testing.expect(value == .string);
    try testing.expectEqualStrings(expected, value.string);
}

fn detailText(buffer: []u8, detail: Detail) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{f}", .{detail});
}

fn hexDigest(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    return switch (a) {
        .null => b == .null,
        .bool => |x| b == .bool and b.bool == x,
        .integer => |x| b == .integer and b.integer == x,
        .float => |x| b == .float and b.float == x,
        .number_string => |x| b == .number_string and std.mem.eql(u8, x, b.number_string),
        .string => |x| b == .string and std.mem.eql(u8, x, b.string),
        .array => |x| array: {
            if (b != .array or b.array.items.len != x.items.len) break :array false;
            for (x.items, b.array.items) |left, right| {
                if (!jsonEqual(left, right)) break :array false;
            }
            break :array true;
        },
        .object => |x| object: {
            if (b != .object or b.object.count() != x.count()) break :object false;
            for (x.keys(), x.values()) |key, left| {
                const right = b.object.get(key) orelse break :object false;
                if (!jsonEqual(left, right)) break :object false;
            }
            break :object true;
        },
    };
}

test "FP-0007 case 1: a valid case parses, and each invalid fixture reports harness-error with a distinct message" {
    const bytes = try readFixture("case-01-valid.json");
    defer testing.allocator.free(bytes);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diagnostic: Detail = undefined;
    const case = try parseCase(arena.allocator(), bytes, &diagnostic);
    const corpus = case.corpus.?;
    try testing.expectEqualStrings("wpt", corpus.name);
    try testing.expectEqualStrings("0123456789abcdef0123456789abcdef01234567", corpus.revision);
    try testing.expectEqualStrings("html/syntax/parsing/basic.html", corpus.path);
    try testing.expectEqualStrings("89abcdef0123456789abcdef0123456789abcdef", corpus.blob);
    try testing.expectEqual(@as(u64, 1700000000000), case.environment.time_origin_ms);
    try testing.expectEqualStrings("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", case.environment.random_seed);
    try testing.expectEqual(Viewport{ .width = 1280, .height = 720, .device_pixel_ratio_milli = 2000 }, case.environment.viewport);
    try testing.expectEqualStrings("en-US", case.environment.locale);
    try testing.expectEqualStrings("America/New_York", case.environment.time_zone);
    try testing.expectEqualStrings("https://example.test/index.html", case.document.url);
    try testing.expectEqualStrings("<!doctype html><title>FP-0007 valid</title><p>Fairpane</p>\n", case.document.body.?);
    try testing.expectEqual(@as(usize, 2), case.resources.len);
    try testing.expectEqualStrings("https://example.test/style.css", case.resources[0].url);
    try testing.expectEqualStrings("p { color: green }\n", case.resources[0].body.?);
    try testing.expectEqualStrings("https://example.test/missing.png", case.resources[1].url);
    try testing.expect(case.resources[1].body == null);
    try testing.expectEqual(Limits{ .max_steps = 16, .step_budget = 1, .max_outstanding_requests = 4, .max_response_body_bytes = 65536 }, case.limits);
    const expectation = case.expect.fetch;
    try testing.expectEqual(FinalState.loaded, expectation.document_state);
    try testing.expectEqualStrings(
        "773daa5b8a762c2fc847254d79908f3b5a57da6cd8b7c96f70c136f4029fc9bc",
        &std.fmt.bytesToHex(expectation.body_sha256.?, .lower),
    );
    var valid_run = runCase(testing.allocator, bytes);
    defer valid_run.deinit();
    try testing.expectEqual(Result.pass, valid_run.outcome.result);

    const invalid = [_]struct { file: []const u8, detail: []const u8 }{
        .{ .file = "case-01-unknown-field.json", .detail = "environment: unknown field" },
        .{ .file = "case-01-duplicate-field.json", .detail = "case: duplicate field" },
        .{ .file = "case-01-wrong-format.json", .detail = "format: expected \"fairpane-lab-case\"" },
        .{ .file = "case-01-wrong-version.json", .detail = "version: expected 1 or 2" },
        .{ .file = "case-01-invalid-base64.json", .detail = "document.body_base64: expected canonical padded base64" },
        .{ .file = "case-01-uppercase-revision.json", .detail = "corpus.revision: expected 40 lowercase hexadecimal digits" },
        .{ .file = "case-01-dotdot-path.json", .detail = "corpus.path: expected a relative POSIX path without empty, \".\", or \"..\" segments" },
        .{ .file = "case-01-missing-environment-field.json", .detail = "environment.time_zone: missing field" },
        .{ .file = "case-01-duplicate-resource-url.json", .detail = "resources[].url: duplicate URL" },
        .{ .file = "case-01-zero-step-budget.json", .detail = "limits.step_budget: out of range" },
    };
    for (invalid, 0..) |fixture, index| {
        for (invalid[0..index]) |earlier| try testing.expect(!std.mem.eql(u8, earlier.detail, fixture.detail));
        var run = try runFixture(fixture.file);
        defer run.deinit();
        try testing.expectEqual(Result.harness_error, run.outcome.result);
        try testing.expectEqual(@as(u8, 3), run.outcome.result.exitStatus());
        var buffer: [256]u8 = undefined;
        try testing.expectEqualStrings(fixture.detail, try detailText(&buffer, run.outcome.detail.?));

        var result_arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer result_arena.deinit();
        const result = try resultJson(result_arena.allocator(), &run);
        const outcome = try member(result, "outcome");
        try expectString("harness-error", try member(outcome, "result"));
        try expectString(fixture.detail, try member(outcome, "detail"));
        try expectString("not-reached", try member((try member(result, "stages")).array.items[0], "status"));
        try testing.expect((try member(result, "corpus")) == .null);
        try testing.expectEqual(@as(usize, 0), (try member(result, "events")).array.items.len);
    }
}

test "FP-0007 case 2 and FP-0008 case 25: a matching fetch expectation passes, fetch completes, decode is unsupported without a byte order mark, tokenize is not reached, and every other stage is unsupported" {
    var run = try runFixture("case-02-pass.json");
    defer run.deinit();
    try testing.expectEqual(Result.pass, run.outcome.result);
    try testing.expectEqual(@as(?Stage, .fetch), run.outcome.stage);
    try testing.expectEqual(@as(u8, 0), run.outcome.result.exitStatus());

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try resultJson(arena.allocator(), &run);
    const body = "<!doctype html><title>FP-0007</title><p>Hello from the laboratory.</p>\n";
    const stages = (try member(result, "stages")).array.items;
    try testing.expectEqual(@as(usize, 8), stages.len);
    for (stages, std.enums.values(Stage)) |entry, stage| {
        try expectString(@tagName(stage), try member(entry, "stage"));
        const status = switch (stage) {
            .fetch => "completed",
            .tokenize => "not-reached",
            else => "unsupported",
        };
        try expectString(status, try member(entry, "status"));
    }
    try testing.expectEqual(Status.unsupported, run.stageStatus(.decode));
    try testing.expectEqual(Status.not_reached, run.stageStatus(.tokenize));
    {
        const decode_stage = stages[@backingInt(Stage.decode)];
        try expectString("no byte order mark; encoding sniffing after BOM sniffing is not implemented", try member(decode_stage, "detail"));
        try testing.expect((try member(decode_stage, "encoding")) == .null);
    }
    const fetch = stages[0];
    try expectString("loaded", try member(fetch, "document_state"));
    try testing.expectEqual(@as(i64, body.len), (try member(fetch, "body_length")).integer);
    try expectString(&hexDigest(body), try member(fetch, "body_sha256"));
    const requests = (try member(fetch, "requests")).array.items;
    try testing.expectEqual(@as(usize, 1), requests.len);
    try expectString("https://example.test/hello.html", try member(requests[0], "url"));
    try expectString("response", try member(requests[0], "answer"));

    const consumers = try member(result, "environment_consumers");
    try testing.expectEqual(@as(usize, std.enums.values(EnvironmentField).len), consumers.object.count());
    try testing.expectEqual(@as(usize, 5), consumers.object.count());
    for (std.enums.values(EnvironmentField)) |field| {
        try testing.expectEqual(@as(usize, 0), (try member(consumers, @tagName(field))).array.items.len);
        try testing.expectEqual(@as(usize, 0), environmentConsumers(field).len);
    }

    const outcome = try member(result, "outcome");
    try expectString("pass", try member(outcome, "result"));
    try expectString("fetch", try member(outcome, "stage"));
    try testing.expect((try member(outcome, "check")) == .null);
}

test "FP-0007 case 3: a mismatching body hash or document state fails at the first differing check with both values" {
    const body = "<!doctype html><title>FP-0007</title><p>Hello from the laboratory.</p>\n";
    {
        var run = try runFixture("case-03-body-mismatch.json");
        defer run.deinit();
        try testing.expectEqual(Result.fail, run.outcome.result);
        try testing.expectEqual(@as(u8, 1), run.outcome.result.exitStatus());
        const mismatch = run.outcome.mismatch.?.body_sha256;
        try testing.expect(std.mem.allEqual(u8, &mismatch.expected.?, 0));
        try testing.expectEqualStrings(&hexDigest(body), &std.fmt.bytesToHex(mismatch.observed.?, .lower));

        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const outcome = try member(try resultJson(arena.allocator(), &run), "outcome");
        try expectString("fail", try member(outcome, "result"));
        try expectString("fetch", try member(outcome, "stage"));
        try expectString("body_sha256", try member(outcome, "check"));
        try expectString("0000000000000000000000000000000000000000000000000000000000000000", try member(outcome, "expected"));
        try expectString(&hexDigest(body), try member(outcome, "observed"));
    }
    {
        var run = try runFixture("case-03-state-mismatch.json");
        defer run.deinit();
        try testing.expectEqual(Result.fail, run.outcome.result);
        const mismatch = run.outcome.mismatch.?.document_state;
        try testing.expectEqual(FinalState.failed, mismatch.expected);
        try testing.expectEqual(engine.DocumentState.loaded, mismatch.observed);

        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const outcome = try member(try resultJson(arena.allocator(), &run), "outcome");
        try expectString("document_state", try member(outcome, "check"));
        try expectString("failed", try member(outcome, "expected"));
        try expectString("loaded", try member(outcome, "observed"));
    }
}

test "FP-0007 case 4: an expectation for the tree stage reports unsupported with stage tree" {
    var run = try runFixture("case-04-tree-unsupported.json");
    defer run.deinit();
    try testing.expectEqual(Result.unsupported, run.outcome.result);
    try testing.expectEqual(@as(?Stage, .tree), run.outcome.stage);
    try testing.expect(run.outcome.mismatch == null);
    try testing.expectEqual(@as(u8, 2), run.outcome.result.exitStatus());

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try resultJson(arena.allocator(), &run);
    const outcome = try member(result, "outcome");
    try expectString("unsupported", try member(outcome, "result"));
    try expectString("tree", try member(outcome, "stage"));
    try testing.expect((try member(outcome, "check")) == .null);
    const stages = (try member(result, "stages")).array.items;
    try expectString("tree", try member(stages[@backingInt(Stage.tree)], "stage"));
    try expectString("unsupported", try member(stages[@backingInt(Stage.tree)], "status"));
}

test "FP-0007 case 5: a null document body cancels the request as unavailable, fails the document, and a failed expectation passes" {
    var run = try runFixture("case-05-null-body.json");
    defer run.deinit();
    try testing.expectEqual(Result.pass, run.outcome.result);
    try testing.expectEqual(@as(?engine.DocumentState, .failed), run.execution.document_state);
    try testing.expectEqual(@as(usize, 1), run.execution.requests.items.len);
    try testing.expectEqual(@as(?Answer, .unavailable), run.execution.requests.items[0].answer);

    const actions = run.execution.records.items;
    try testing.expectEqual(@as(usize, 4), actions.len);
    try testing.expect(actions[0].action == .create_document);
    try testing.expect(actions[1].action == .load);
    try testing.expect(actions[2].action == .cancel);
    try testing.expect(actions[3].action == .step);

    const events = run.execution.events.items;
    try testing.expectEqual(@as(usize, 4), events.len);
    try testing.expectEqual(EventType.request_issued, events[0].event);
    try testing.expectEqualStrings("https://example.test/absent.html", events[0].url.?);
    try testing.expectEqual(EventType.document_state_changed, events[1].event);
    try testing.expectEqual(@as(?engine.DocumentState, .loading), events[1].state);
    try testing.expectEqual(EventType.request_cancelled, events[2].event);
    try testing.expectEqual(EventType.document_state_changed, events[3].event);
    try testing.expectEqual(@as(?engine.DocumentState, .failed), events[3].state);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const fetch = (try member(try resultJson(arena.allocator(), &run), "stages")).array.items[0];
    try expectString("completed", try member(fetch, "status"));
    try expectString("failed", try member(fetch, "document_state"));
    try expectString("unavailable", try member((try member(fetch, "requests")).array.items[0], "answer"));
    try testing.expect((try member(fetch, "body_sha256")) == .null);
}

test "FP-0007 case 6: a document URL that names a loopback listener loads the case bytes, and the listener accepts no connection" {
    const io = testing.io;
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    var server = try address.listen(io, .{});
    defer server.deinit(io);
    const port = server.socket.address.getPort();

    const body = "bytes from the case, not from the listener\n";
    var encoded: [std.base64.standard.Encoder.calcSize(body.len)]u8 = undefined;
    const case_bytes = try std.fmt.allocPrint(testing.allocator,
        \\{{"format":"fairpane-lab-case","version":1,"corpus":null,
        \\"environment":{{"time_origin_ms":0,"random_seed":"{s}","viewport":{{"width":640,"height":480,"device_pixel_ratio_milli":1000}},"locale":"en-US","time_zone":"UTC"}},
        \\"document":{{"url":"http://127.0.0.1:{d}/","body_base64":"{s}"}},"resources":[],
        \\"limits":{{"max_steps":8,"step_budget":1,"max_outstanding_requests":1,"max_response_body_bytes":1024}},
        \\"expect":{{"stage":"fetch","document_state":"loaded","body_sha256":"{s}"}}}}
    , .{ "0000000000000000000000000000000000000000000000000000000000000000", port, std.base64.standard.Encoder.encode(&encoded, body), &hexDigest(body) });
    defer testing.allocator.free(case_bytes);

    var run = runCase(testing.allocator, case_bytes);
    defer run.deinit();
    try testing.expectEqual(Result.pass, run.outcome.result);
    try testing.expectEqual(@as(usize, body.len), run.execution.body.?.length);

    // The listener's first queued connection is this sentinel, so the laboratory made none.
    const marker: u8 = 0x5a;
    const sentinel = try server.socket.address.connect(io, .{ .mode = .stream });
    defer sentinel.close(io);
    var send_buffer: [1]u8 = undefined;
    var sender = sentinel.writer(io, &send_buffer);
    try sender.interface.writeByte(marker);
    try sender.interface.flush();
    const accepted = try server.accept(io);
    defer accepted.close(io);
    var receive_buffer: [1]u8 = undefined;
    var receiver = accepted.reader(io, &receive_buffer);
    try testing.expectEqual(marker, try receiver.interface.takeByte());
}

test "FP-0007 case 7: two runs of one case produce byte-identical results without process-wide identifiers" {
    const bytes = try readFixture("case-01-valid.json");
    defer testing.allocator.free(bytes);

    var first = runCase(testing.allocator, bytes);
    defer first.deinit();
    // Advance the process-wide identifier sequence between the runs.
    const probe = try engine.Engine.create(testing.allocator, .{ .max_outstanding_requests = 1, .max_response_body_bytes = 0 });
    defer probe.destroy() catch unreachable;
    _ = try probe.createDocument();
    var second = runCase(testing.allocator, bytes);
    defer second.deinit();

    var first_out: Writer.Allocating = .init(testing.allocator);
    defer first_out.deinit();
    try first.writeResult(&first_out.writer);
    var second_out: Writer.Allocating = .init(testing.allocator);
    defer second_out.deinit();
    try second.writeResult(&second_out.writer);
    try testing.expectEqualStrings(first_out.written(), second_out.written());

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), first_out.written(), .{});
    const events = (try member(result, "events")).array.items;
    try testing.expectEqual(@as(usize, 3), events.len);
    for (events) |event| {
        try testing.expectEqual(@as(i64, 1), (try member(event, "document")).integer);
        try testing.expectEqual(@as(i64, 1), (try member(event, "request")).integer);
    }
}

test "FP-0007 case 8: max_steps 0 reports timeout" {
    var run = try runFixture("case-08-timeout.json");
    defer run.deinit();
    try testing.expectEqual(Result.timeout, run.outcome.result);
    try testing.expectEqual(@as(?Stage, .fetch), run.outcome.stage);
    try testing.expectEqual(@as(u8, 4), run.outcome.result.exitStatus());
    try testing.expectEqual(@as(u64, 0), run.execution.steps);
    try testing.expectEqual(@as(?engine.DocumentState, .loading), run.execution.document_state);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const result = try resultJson(arena.allocator(), &run);
    try testing.expectEqual(@as(i64, 0), (try member(result, "steps")).integer);
    try expectString("timeout", try member(try member(result, "outcome"), "result"));
    try expectString("failed", try member((try member(result, "stages")).array.items[0], "status"));
}

test "FP-0007 case 9: the result's case is the SHA-256 of the case bytes and its corpus equals the case's corpus" {
    for ([_][]const u8{ "case-01-valid.json", "case-02-pass.json" }) |name| {
        const bytes = try readFixture(name);
        defer testing.allocator.free(bytes);
        var run = runCase(testing.allocator, bytes);
        defer run.deinit();

        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const result = try resultJson(arena.allocator(), &run);
        try expectString(&hexDigest(bytes), try member(result, "case"));
        const case = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{});
        try testing.expect(jsonEqual(try member(case, "corpus"), try member(result, "corpus")));
    }
}

test "FP-0007 case 10: a replay passes, a changed event fails at its action, and a truncated transcript is a harness error" {
    var run = try runFixture("case-02-pass.json");
    defer run.deinit();
    try testing.expectEqual(Result.pass, run.outcome.result);
    var transcript: Writer.Allocating = .init(testing.allocator);
    defer transcript.deinit();
    try run.writeTranscript(&transcript.writer);
    const recorded = transcript.written();
    {
        var replayed = replay(testing.allocator, recorded);
        defer replayed.deinit();
        try testing.expectEqual(Result.pass, replayed.outcome.result);
        try testing.expectEqual(@as(usize, 4), replayed.actions);
    }

    // Change the one recorded `loaded` event, which the step at action index 3 drained.
    try testing.expect(run.execution.records.items[3].action == .step);
    const needle = "\"state\": \"loaded\"";
    const at = std.mem.indexOf(u8, recorded, needle).?;
    try testing.expect(std.mem.indexOfPos(u8, recorded, at + 1, needle) == null);
    const changed = try std.mem.concat(testing.allocator, u8, &.{ recorded[0..at], "\"state\": \"failed\"", recorded[at + needle.len ..] });
    defer testing.allocator.free(changed);
    {
        var replayed = replay(testing.allocator, changed);
        defer replayed.deinit();
        try testing.expectEqual(Result.fail, replayed.outcome.result);
        try testing.expectEqual(@as(u8, 1), replayed.outcome.result.exitStatus());
        try testing.expectEqual(@as(?usize, 3), replayed.outcome.action);
        const mismatch = replayed.outcome.mismatch.?.events;
        try testing.expectEqual(@as(?engine.DocumentState, .failed), mismatch.expected[0].state);
        try testing.expectEqual(@as(?engine.DocumentState, .loaded), mismatch.observed[0].state);

        var out: Writer.Allocating = .init(testing.allocator);
        defer out.deinit();
        try replayed.writeResult(&out.writer);
        try testing.expect(std.mem.indexOf(u8, out.written(), "\"action\": 3") != null);
    }
    {
        var replayed = replay(testing.allocator, recorded[0 .. recorded.len / 2]);
        defer replayed.deinit();
        try testing.expectEqual(Result.harness_error, replayed.outcome.result);
        try testing.expectEqual(@as(u8, 3), replayed.outcome.result.exitStatus());
    }
}

/// Holds when the candidate contains an `a` before a `b`.
const ABeforeB = struct {
    fn holds(_: *ABeforeB, candidate: []const u8) error{}!bool {
        const a = std.mem.indexOfScalar(u8, candidate, 'a') orelse return false;
        return std.mem.indexOfScalarPos(u8, candidate, a + 1, 'b') != null;
    }
};

test "FP-0007 case 11: ddmin reduces xxaxxbxx to ab, its result is 1-minimal, and a false input is an error" {
    var predicate: ABeforeB = .{};
    const reduced = try ddmin(u8, testing.allocator, "xxaxxbxx", &predicate);
    defer testing.allocator.free(reduced);
    try testing.expectEqualStrings("ab", reduced);
    var scratch: [8]u8 = undefined;
    for (0..reduced.len) |index| {
        @memcpy(scratch[0..index], reduced[0..index]);
        @memcpy(scratch[index .. reduced.len - 1], reduced[index + 1 ..]);
        try testing.expect(!try predicate.holds(scratch[0 .. reduced.len - 1]));
    }
    try testing.expectError(error.PredicateDoesNotHold, ddmin(u8, testing.allocator, "xxbxxaxx", &predicate));
}

fn runUnderAllocationFailure(gpa: Allocator, bytes: []const u8) !void {
    var run = runCase(gpa, bytes);
    defer run.deinit();
    var buffer: [16 * 1024]u8 = undefined;
    var out: Writer = .fixed(&buffer);
    try run.writeResult(&out);
    switch (run.outcome.result) {
        .pass => {},
        .harness_error => {
            var text: [64]u8 = undefined;
            try testing.expectEqualStrings("out of memory", try detailText(&text, run.outcome.detail.?));
            try testing.expect(std.mem.indexOf(u8, out.buffered(), "\"result\": \"harness-error\"") != null);
            return error.OutOfMemory;
        },
        else => return error.TestUnexpectedResult,
    }
}

test "FP-0007 case 12: each induced allocation failure in parsing and a complete run reports harness-error and leaks nothing" {
    for ([_][]const u8{ "case-01-valid.json", "case-05-null-body.json" }) |name| {
        const bytes = try readFixture(name);
        defer testing.allocator.free(bytes);
        // Fail every remap so that each growth step is an allocation the checker can induce.
        var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
        try testing.checkAllAllocationFailures(no_remap.allocator(), runUnderAllocationFailure, .{bytes});
        try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
    }
}

test "FP-0054 case 1: a sparse case file of 64 MiB + 1 bytes fails with FileTooLarge before any allocation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const name = "oversized.json";
    {
        // Setting the length writes no byte, so the file system may leave the file sparse.
        const file = try tmp.dir.createFile(testing.io, name, .{});
        defer file.close(testing.io);
        try file.setLength(testing.io, case_size_limit + 1);
    }
    var path_buffer: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, ".zig-cache/tmp/{s}/{s}", .{ &tmp.sub_path, name });
    var counting: testing.FailingAllocator = .init(testing.allocator, .{});
    try testing.expectError(error.FileTooLarge, readInputFile(testing.io, counting.allocator(), path, case_size_limit));
    try testing.expectEqual(@as(usize, 0), counting.allocations);

    // The command line reports the error as a harness error that names the size limit, with exit status 3.
    var run = Run.initHarnessError(testing.allocator, null, fileFailure("case file", error.FileTooLarge));
    defer run.deinit();
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("case file: exceeds the size limit", try detailText(&buffer, run.outcome.detail.?));
    try testing.expectEqual(@as(u8, 3), run.outcome.result.exitStatus());
}

/// Records the transcript of `fixture`, applies `edit` to its parsed JSON, and replays the edited transcript.
fn replayEdited(fixture: []const u8, comptime edit: fn (*std.json.ObjectMap) anyerror!void) !Replay {
    var run = try runFixture(fixture);
    defer run.deinit();
    var transcript: Writer.Allocating = .init(testing.allocator);
    defer transcript.deinit();
    try run.writeTranscript(&transcript.writer);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var root = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), transcript.written(), .{});
    try testing.expect(root == .object);
    try edit(&root.object);
    const edited = try Stringify.valueAlloc(arena.allocator(), root, .{ .whitespace = .indent_2 });
    return replay(testing.allocator, edited);
}

fn removeLastAction(top: *std.json.ObjectMap) !void {
    const actions = top.getPtr("actions") orelse return error.TestUnexpectedResult;
    try testing.expect(actions.* == .array and actions.array.items.len > 1);
    _ = actions.array.pop();
}

fn setVersion1(top: *std.json.ObjectMap) !void {
    const version = top.getPtr("version") orelse return error.TestUnexpectedResult;
    version.* = .{ .integer = 1 };
}

test "FP-0054 case 2: a transcript with a removed action or with version 1 reports harness-error" {
    {
        var run = try runFixture("case-02-pass.json");
        defer run.deinit();
        var transcript: Writer.Allocating = .init(testing.allocator);
        defer transcript.deinit();
        try run.writeTranscript(&transcript.writer);
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const recorded = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), transcript.written(), .{});
        try testing.expectEqual(@as(i64, 2), (try member(recorded, "version")).integer);
        try testing.expectEqual(@as(i64, 4), (try member(recorded, "action_count")).integer);
        var replayed = replay(testing.allocator, transcript.written());
        defer replayed.deinit();
        try testing.expectEqual(Result.pass, replayed.outcome.result);
    }
    var buffer: [128]u8 = undefined;
    {
        var replayed = try replayEdited("case-02-pass.json", removeLastAction);
        defer replayed.deinit();
        try testing.expectEqual(Result.harness_error, replayed.outcome.result);
        try testing.expectEqual(@as(u8, 3), replayed.outcome.result.exitStatus());
        try testing.expectEqualStrings("action_count: differs from the number of actions", try detailText(&buffer, replayed.outcome.detail.?));
    }
    {
        var replayed = try replayEdited("case-02-pass.json", setVersion1);
        defer replayed.deinit();
        try testing.expectEqual(Result.harness_error, replayed.outcome.result);
        try testing.expectEqualStrings("version: expected 2", try detailText(&buffer, replayed.outcome.detail.?));
    }
}

test "FP-0054 case 3: minimize writes a version 2 case derived from the original digest and corpus, with a null corpus" {
    const bytes = try readFixture("fp0054-case-03-minimize-corpus.json");
    defer testing.allocator.free(bytes);
    var m = minimize(testing.allocator, bytes);
    defer m.deinit();
    try testing.expectEqual(Result.pass, m.outcome.result);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const original = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), bytes, .{});
    const written = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), m.output, .{});
    try testing.expectEqual(@as(i64, 2), (try member(written, "version")).integer);
    try testing.expect((try member(written, "corpus")) == .null);
    const derived_from = try member(written, "derived_from");
    try expectString(&hexDigest(bytes), try member(derived_from, "case_sha256"));
    try testing.expect((try member(original, "corpus")) == .object);
    try testing.expect(jsonEqual(try member(original, "corpus"), try member(derived_from, "corpus")));

    // The written case parses as a derived case and reproduces the original outcome.
    var diagnostic: Detail = undefined;
    const case = try parseCase(arena.allocator(), m.output, &diagnostic);
    try testing.expect(case.corpus == null);
    try testing.expectEqualStrings(&hexDigest(bytes), &std.fmt.bytesToHex(case.derived_from.?.case_sha256, .lower));
    try testing.expectEqualStrings("html/syntax/parsing/derived.html", case.derived_from.?.corpus.?.path);
    var rerun = runCase(testing.allocator, m.output);
    defer rerun.deinit();
    try testing.expectEqual(Result.fail, rerun.outcome.result);
    try testing.expectEqual(Check.body_sha256, std.meta.activeTag(rerun.outcome.mismatch.?));
}

test "FP-0054 case 4: derived_from in version 1, its absence in version 2, and a version 2 corpus each report harness-error" {
    const invalid = [_]struct { file: []const u8, detail: []const u8 }{
        .{ .file = "fp0054-case-04-v1-derived.json", .detail = "derived_from: not allowed in version 1" },
        .{ .file = "fp0054-case-04-v2-missing-derived.json", .detail = "derived_from: missing field" },
        .{ .file = "fp0054-case-04-v2-corpus.json", .detail = "corpus: expected null in version 2" },
    };
    for (invalid, 0..) |fixture, index| {
        for (invalid[0..index]) |earlier| try testing.expect(!std.mem.eql(u8, earlier.detail, fixture.detail));
        var run = try runFixture(fixture.file);
        defer run.deinit();
        try testing.expectEqual(Result.harness_error, run.outcome.result);
        try testing.expectEqual(@as(u8, 3), run.outcome.result.exitStatus());
        var buffer: [128]u8 = undefined;
        try testing.expectEqualStrings(fixture.detail, try detailText(&buffer, run.outcome.detail.?));
    }
}

/// `L_BODY` of the FP-0008 contract.
const l_body = "<!DOCTYPE html><p class=x>a&amp;b</p>";

/// The token dump of case 18.
const l_body_tokens =
    \\["DOCTYPE","html",null,null,false,[0,15]]
    \\["StartTag","p",[["class","x",[18,23],[24,25]]],false,[15,26]]
    \\["Character","a&b",[26,33]]
    \\["EndTag","p",[],false,[33,37]]
    \\["EOF",[37,37]]
    \\
;

/// Returns the hexadecimal SHA-256 of the UTF-16LE encoding of ASCII `text`.
fn utf16LeDigest(comptime text: []const u8) [64]u8 {
    var bytes: [2 * text.len]u8 = undefined;
    for (text, 0..) |c, index| {
        bytes[2 * index] = c;
        bytes[2 * index + 1] = 0;
    }
    return hexDigest(&bytes);
}

/// Runs a fixture and returns its parsed result document, the outcome, and the decode and tokenize stage records.
const StageResult = struct {
    arena: std.heap.ArenaAllocator,
    run: Run,
    outcome: std.json.Value,
    decode: std.json.Value,
    tokenize: std.json.Value,

    fn init(fixture: []const u8) !StageResult {
        var result: StageResult = .{ .arena = .init(testing.allocator), .run = try runFixture(fixture), .outcome = undefined, .decode = undefined, .tokenize = undefined };
        errdefer result.deinit();
        const json = try resultJson(result.arena.allocator(), &result.run);
        const stages = (try member(json, "stages")).array.items;
        result.outcome = try member(json, "outcome");
        result.decode = stages[@backingInt(Stage.decode)];
        result.tokenize = stages[@backingInt(Stage.tokenize)];
        try expectString("decode", try member(result.decode, "stage"));
        try expectString("tokenize", try member(result.tokenize, "stage"));
        return result;
    }

    fn deinit(r: *StageResult) void {
        r.run.deinit();
        r.arena.deinit();
    }
};

fn expectInteger(expected: i64, value: std.json.Value) !void {
    try testing.expect(value == .integer);
    try testing.expectEqual(expected, value.integer);
}

test "FP-0008 case 18: a UTF-8 byte order mark body with a matching tokenize expectation passes, and both stages record their results" {
    var r = try StageResult.init("fp0008-tokenize-pass.json");
    defer r.deinit();
    try testing.expectEqual(Result.pass, r.run.outcome.result);
    try testing.expectEqual(@as(?Stage, .tokenize), r.run.outcome.stage);
    try expectString("pass", try member(r.outcome, "result"));
    try expectString("tokenize", try member(r.outcome, "stage"));

    try expectString("completed", try member(r.decode, "status"));
    try expectString("UTF-8", try member(r.decode, "encoding"));
    try expectString("certain", try member(r.decode, "confidence"));
    try expectInteger(3, try member(r.decode, "bom_bytes"));
    try expectInteger(37, try member(r.decode, "code_units"));
    try testing.expectEqual(@as(usize, 37), l_body.len);
    try expectString(&utf16LeDigest(l_body), try member(r.decode, "output_sha256"));
    try testing.expect((try member(r.decode, "detail")) == .null);

    try expectString("completed", try member(r.tokenize, "status"));
    try expectInteger(5, try member(r.tokenize, "token_count"));
    try expectString(&hexDigest(l_body_tokens), try member(r.tokenize, "tokens_sha256"));
    try testing.expectEqual(@as(usize, 0), (try member(r.tokenize, "errors")).array.items.len);
}

test "FP-0008 case 18: each induced allocation failure in a run that decodes and tokenizes reports harness-error and leaks nothing" {
    for ([_][]const u8{ "fp0008-tokenize-pass.json", "fp0008-tokenize-errors.json" }) |name| {
        const bytes = try readFixture(name);
        defer testing.allocator.free(bytes);
        // Fail every remap so that each growth step is an allocation the checker can induce.
        var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
        try testing.checkAllAllocationFailures(no_remap.allocator(), runUnderAllocationFailure, .{bytes});
        try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
    }
}

test "FP-0008 case 19: a tokenize expectation fails at its first differing check with both values" {
    {
        var r = try StageResult.init("fp0008-tokenize-token-count.json");
        defer r.deinit();
        try testing.expectEqual(Result.fail, r.run.outcome.result);
        try testing.expectEqual(@as(u8, 1), r.run.outcome.result.exitStatus());
        try expectString("tokenize", try member(r.outcome, "stage"));
        try expectString("token_count", try member(r.outcome, "check"));
        try expectInteger(4, try member(r.outcome, "expected"));
        try expectInteger(5, try member(r.outcome, "observed"));
    }
    {
        var r = try StageResult.init("fp0008-tokenize-zero-digest.json");
        defer r.deinit();
        try testing.expectEqual(Result.fail, r.run.outcome.result);
        try expectString("tokens_sha256", try member(r.outcome, "check"));
        try expectString(&@as([64]u8, @splat('0')), try member(r.outcome, "expected"));
        try expectString(&hexDigest(l_body_tokens), try member(r.outcome, "observed"));
    }
    {
        var r = try StageResult.init("fp0008-tokenize-wrong-errors.json");
        defer r.deinit();
        try testing.expectEqual(Result.fail, r.run.outcome.result);
        try expectString("errors", try member(r.outcome, "check"));
        const expected = (try member(r.outcome, "expected")).array.items;
        try testing.expectEqual(@as(usize, 1), expected.len);
        try expectString("eof-in-tag", try member(expected[0], "code"));
        try expectInteger(1, try member(expected[0], "line"));
        try expectInteger(1, try member(expected[0], "column"));
        try expectInteger(0, try member(expected[0], "offset"));
        try testing.expectEqual(@as(usize, 0), (try member(r.outcome, "observed")).array.items.len);
    }
}

test "FP-0008 case 20: a body with tokenizer parse errors records them in step order and passes" {
    var r = try StageResult.init("fp0008-tokenize-errors.json");
    defer r.deinit();
    try testing.expectEqual(Result.pass, r.run.outcome.result);
    try expectInteger(3, try member(r.tokenize, "token_count"));
    try expectString(&hexDigest(
        \\["StartTag","a",[["b","c'd",[3,4],[5,8]]],false,[0,9]]
        \\["Character","\u00ACit;",[9,16]]
        \\["EOF",[16,16]]
        \\
    ), try member(r.tokenize, "tokens_sha256"));
    const errors = (try member(r.tokenize, "errors")).array.items;
    try testing.expectEqual(@as(usize, 2), errors.len);
    const expected = [_]struct { code: []const u8, line: i64, column: i64, offset: i64 }{
        .{ .code = "unexpected-character-in-unquoted-attribute-value", .line = 1, .column = 7, .offset = 6 },
        .{ .code = "missing-semicolon-after-character-reference", .line = 1, .column = 13, .offset = 12 },
    };
    for (errors, expected) |observed, record| {
        try testing.expectEqual(@as(usize, 4), observed.object.count());
        try expectString(record.code, try member(observed, "code"));
        try expectInteger(record.line, try member(observed, "line"));
        try expectInteger(record.column, try member(observed, "column"));
        try expectInteger(record.offset, try member(observed, "offset"));
    }
}

test "FP-0008 case 21: a body without a UTF-8 byte order mark makes decode and tokenize expectations unsupported at decode" {
    const cases = [_]struct { fixture: []const u8, detail: []const u8 }{
        .{ .fixture = "fp0008-tokenize-no-bom.json", .detail = "no byte order mark; encoding sniffing after BOM sniffing is not implemented" },
        .{ .fixture = "fp0008-decode-utf16le-bom.json", .detail = "UTF-16LE byte order mark; the UTF-16LE decoder is not implemented" },
        .{ .fixture = "fp0008-decode-utf16be-bom.json", .detail = "UTF-16BE byte order mark; the UTF-16BE decoder is not implemented" },
    };
    for (cases) |case| {
        var r = try StageResult.init(case.fixture);
        defer r.deinit();
        try testing.expectEqual(Result.unsupported, r.run.outcome.result);
        try testing.expectEqual(@as(u8, 2), r.run.outcome.result.exitStatus());
        try expectString("unsupported", try member(r.outcome, "result"));
        try expectString("decode", try member(r.outcome, "stage"));
        try testing.expect((try member(r.outcome, "check")) == .null);
        try expectString(case.detail, try member(r.outcome, "detail"));
        try expectString("unsupported", try member(r.decode, "status"));
        try expectString(case.detail, try member(r.decode, "detail"));
        try expectString("not-reached", try member(r.tokenize, "status"));
    }
}

test "FP-0008 case 22: a tokenize expectation for a failed document fails on document_state, and neither new stage is reached" {
    var r = try StageResult.init("fp0008-tokenize-null-body.json");
    defer r.deinit();
    try testing.expectEqual(Result.fail, r.run.outcome.result);
    try expectString("tokenize", try member(r.outcome, "stage"));
    try expectString("document_state", try member(r.outcome, "check"));
    try expectString("loaded", try member(r.outcome, "expected"));
    try expectString("failed", try member(r.outcome, "observed"));
    try expectString("not-reached", try member(r.decode, "status"));
    try expectString("not-reached", try member(r.tokenize, "status"));
}

test "FP-0008 case 23: a decode expectation passes for the case 18 body and fails on encoding when it names UTF-16LE" {
    {
        var r = try StageResult.init("fp0008-decode-pass.json");
        defer r.deinit();
        try testing.expectEqual(Result.pass, r.run.outcome.result);
        try expectString("decode", try member(r.outcome, "stage"));
    }
    {
        var r = try StageResult.init("fp0008-decode-wrong-encoding.json");
        defer r.deinit();
        try testing.expectEqual(Result.fail, r.run.outcome.result);
        try expectString("decode", try member(r.outcome, "stage"));
        try expectString("encoding", try member(r.outcome, "check"));
        try expectString("UTF-16LE", try member(r.outcome, "expected"));
        try expectString("UTF-8", try member(r.outcome, "observed"));
    }
}

test "FP-0008 case 24: the UTF-8 decoder with replacement turns an invalid byte into U+FFFD" {
    var r = try StageResult.init("fp0008-tokenize-replacement.json");
    defer r.deinit();
    try testing.expectEqual(Result.pass, r.run.outcome.result);
    try expectInteger(3, try member(r.decode, "code_units"));
    try expectInteger(2, try member(r.tokenize, "token_count"));
    try expectString(&hexDigest("[\"Character\",\"a\\uFFFDb\",[0,3]]\n[\"EOF\",[3,3]]\n"), try member(r.tokenize, "tokens_sha256"));
}
