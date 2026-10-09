//! The public C ABI. It maps opaque 64-bit identifiers to the native engine and never exposes internal handles.
//! `abi_generated.zig` declares every ABI type and C function type from `api/fairpane.schema.json`.
//! Each export returns through `finish`, which checks at compile time that every status it can return is in its generated status set.

const std = @import("std");
const builtin = @import("builtin");
const abi = @import("abi_generated.zig");
const native = @import("engine.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const abi_revision = abi.abi_revision;

const ok = @backingInt(abi.Status.ok);
const invalid_argument = @backingInt(abi.Status.invalid_argument);
const unknown_id = @backingInt(abi.Status.unknown_id);
const out_of_memory = @backingInt(abi.Status.out_of_memory);
const wrong_thread = @backingInt(abi.Status.wrong_thread);

const document_empty = @backingInt(abi.DocumentState.empty);
const document_loading = @backingInt(abi.DocumentState.loading);
const document_loaded = @backingInt(abi.DocumentState.loaded);
const document_failed = @backingInt(abi.DocumentState.failed);
const reject_unsupported_version = @backingInt(abi.RejectReason.unsupported_version);

/// Checks that a native enumeration has exactly the members and values of its schema enumeration.
fn expectSameEnum(comptime Native: type, comptime Abi: type) void {
    const native_names = @typeInfo(Native).@"enum".field_names;
    const abi_info = @typeInfo(Abi).@"enum";
    if (native_names.len != abi_info.field_names.len) @compileError(@typeName(Native) ++ " and the schema have different members.");
    for (abi_info.field_names, abi_info.field_values) |name, value| {
        if (!@hasField(Native, name) or @backingInt(@field(Native, name)) != value) @compileError(@typeName(Native) ++ "." ++ name ++ " differs from the schema.");
    }
}

// The native engine and the schema agree on every value that crosses the ABI,
// and every exported function has exactly its generated C function type.
comptime {
    expectSameEnum(native.DocumentState, abi.DocumentState);
    expectSameEnum(native.RequestKind, abi.RequestKind);
    expectSameEnum(native.RejectReason, abi.RejectReason);
    if (native.resource_request_version != abi.resource_request_version) @compileError("The native resource request version differs from the schema.");
    for (@typeInfo(abi.functions).@"struct".decl_names) |name| {
        if (@TypeOf(@field(@This(), name)) != @field(abi.functions, name)) @compileError(name ++ " differs from its generated function type.");
    }
}

/// Converts between a schema identifier or enumeration and its native counterpart, which share their values.
fn convert(comptime T: type, value: anytype) T {
    return @fromBackingInt(@backingInt(value));
}

/// The allocator behind every engine that `fp_engine_create` creates.
const process_allocator: Allocator = if (builtin.single_threaded) std.heap.page_allocator else std.heap.smp_allocator;

/// The status that represents an error of an export.
/// An error without a status fails compilation, so a new native error cannot surface silently.
fn statusOf(comptime err: anyerror) abi.Status {
    return switch (err) {
        error.InvalidArgument => .invalid_argument,
        error.WrongThread => .wrong_thread,
        error.UnknownId => .unknown_id,
        error.InvalidState => .invalid_state,
        error.UnsupportedVersion => .unsupported_version,
        error.LimitExceeded, error.IdentifiersExhausted => .limit_exceeded,
        error.OutOfMemory => .out_of_memory,
        else => @compileError("No status represents error." ++ @errorName(err) ++ "."),
    };
}

/// Checks at compile time that the schema's status set for the export `symbol` contains `status`.
fn expectAllowed(comptime symbol: []const u8, comptime status: abi.Status) void {
    for (@field(abi.statuses, symbol)) |allowed| {
        if (allowed == status) return;
    }
    @compileError(symbol ++ " can return " ++ @tagName(status) ++ ", which its schema status set lacks.");
}

/// Converts the result of the export `symbol` to its status.
/// Success and every error in the result's error set must map into the schema's status set for `symbol` at compile time.
fn finish(comptime symbol: []const u8, result: anytype) u32 {
    comptime expectAllowed(symbol, .ok);
    result catch |err| switch (err) {
        inline else => |known| {
            const status = comptime statusOf(known);
            comptime expectAllowed(symbol, status);
            return @backingInt(status);
        },
    };
    return ok;
}

fn nativeEngine(handle: *abi.Engine) *native.Engine {
    return @ptrCast(@alignCast(handle));
}

/// Resolves the engine argument and checks the calling thread before any other argument.
fn enter(handle: ?*abi.Engine) error{ InvalidArgument, WrongThread }!*native.Engine {
    const resolved = nativeEngine(handle orelse return error.InvalidArgument);
    try resolved.checkThread();
    return resolved;
}

/// Converts an input byte range, which may be null only when its length is zero.
/// Every range of the ABI is `null_when_empty`, so every input range converts through this function.
fn inputRange(bytes: ?[*]const u8, len: usize) error{InvalidArgument}![]const u8 {
    if (bytes) |pointer| return pointer[0..len];
    if (len == 0) return &.{};
    return error.InvalidArgument;
}

/// `fp_engine_create` with an explicit allocator.
/// Zig tests use it to inject allocation failure and to detect leaked engine storage.
pub fn createEngine(gpa: Allocator, options: ?*const abi.EngineOptions, out_engine: ?*?*abi.Engine) u32 {
    return finish("fp_engine_create", engineCreate(gpa, options, out_engine));
}

fn engineCreate(gpa: Allocator, options: ?*const abi.EngineOptions, out_engine: ?*?*abi.Engine) !void {
    const input = options orelse return error.InvalidArgument;
    const out = out_engine orelse return error.InvalidArgument;
    if (input.struct_size < @sizeOf(abi.EngineOptions)) return error.InvalidArgument;
    const created = try native.Engine.create(gpa, .{
        .max_outstanding_requests = input.max_outstanding_requests,
        // A bound beyond the address space admits every body that the host can present.
        .max_response_body_bytes = std.math.cast(usize, input.max_response_body_bytes) orelse std.math.maxInt(usize),
    });
    out.* = @ptrCast(created);
}

fn eventToC(event: ?native.Event) abi.Event {
    var result: abi.Event = .{
        .struct_size = @sizeOf(abi.Event),
        .kind = @backingInt(abi.EventKind.none),
        .document_id = .absent,
        .request_id = .absent,
        .request_kind = .absent,
        .request_version = .absent,
        .document_state = .absent,
        .reject_reason = .absent,
        .url = null,
        .url_len = 0,
    };
    switch (event orelse return result) {
        .request_issued, .request_cancelled => |notice| {
            result.document_id = .of(convert(abi.DocumentId, notice.document));
            result.request_id = .of(convert(abi.RequestId, notice.request));
            result.request_kind = .of(convert(abi.RequestKind, notice.kind));
            result.request_version = .of(notice.version);
            // Every range of the ABI is null exactly when it is empty, including an empty live URL.
            if (notice.url) |bytes| {
                if (bytes.len != 0) {
                    result.url = bytes.ptr;
                    result.url_len = bytes.len;
                }
            }
        },
        .document_state_changed => |change| {
            result.document_id = .of(convert(abi.DocumentId, change.document));
            result.request_id = .of(convert(abi.RequestId, change.request));
            result.request_kind = .of(convert(abi.RequestKind, change.kind));
            result.request_version = .of(change.version);
            result.document_state = .of(convert(abi.DocumentState, change.state));
            if (change.reject_reason) |reason| result.reject_reason = .of(convert(abi.RejectReason, reason));
        },
    }
    result.kind = @backingInt(@as(abi.EventKind, switch (event.?) {
        .request_issued => .request_issued,
        .request_cancelled => .request_cancelled,
        .document_state_changed => .document_state_changed,
    }));
    return result;
}

export fn fp_abi_revision() callconv(.c) u32 {
    return abi_revision;
}

export fn fp_query_capabilities(out: ?*abi.Capabilities, out_size: usize) callconv(.c) u32 {
    return finish("fp_query_capabilities", queryCapabilities(out, out_size));
}

fn queryCapabilities(out: ?*abi.Capabilities, out_size: usize) !void {
    const result = out orelse return error.InvalidArgument;
    if (out_size < @sizeOf(abi.Capabilities)) return error.InvalidArgument;
    result.* = .{
        .struct_size = @sizeOf(abi.Capabilities),
        .abi_revision = abi_revision,
        .feature_bits = 0,
    };
}

export fn fp_engine_create(options: ?*const abi.EngineOptions, out_engine: ?*?*abi.Engine) callconv(.c) u32 {
    return createEngine(process_allocator, options, out_engine);
}

export fn fp_engine_destroy(handle: ?*abi.Engine) callconv(.c) u32 {
    return finish("fp_engine_destroy", engineDestroy(handle));
}

fn engineDestroy(handle: ?*abi.Engine) !void {
    const engine = try enter(handle);
    try engine.destroy();
}

export fn fp_document_create(handle: ?*abi.Engine, out_document: ?*abi.DocumentId) callconv(.c) u32 {
    return finish("fp_document_create", documentCreate(handle, out_document));
}

fn documentCreate(handle: ?*abi.Engine, out_document: ?*abi.DocumentId) !void {
    const engine = try enter(handle);
    const out = out_document orelse return error.InvalidArgument;
    out.* = convert(abi.DocumentId, try engine.createDocument());
}

export fn fp_document_destroy(handle: ?*abi.Engine, document: abi.DocumentId) callconv(.c) u32 {
    return finish("fp_document_destroy", documentDestroy(handle, document));
}

fn documentDestroy(handle: ?*abi.Engine, document: abi.DocumentId) !void {
    const engine = try enter(handle);
    try engine.destroyDocument(convert(native.DocumentId, document));
}

export fn fp_document_get(handle: ?*abi.Engine, document: abi.DocumentId, out: ?*abi.DocumentInfo, out_size: usize) callconv(.c) u32 {
    return finish("fp_document_get", documentGet(handle, document, out, out_size));
}

fn documentGet(handle: ?*abi.Engine, document: abi.DocumentId, out: ?*abi.DocumentInfo, out_size: usize) !void {
    const engine = try enter(handle);
    const result = out orelse return error.InvalidArgument;
    if (out_size < @sizeOf(abi.DocumentInfo)) return error.InvalidArgument;
    const view = try engine.document(convert(native.DocumentId, document));
    result.* = .{
        .struct_size = @sizeOf(abi.DocumentInfo),
        .state = @backingInt(view.state),
        .body = if (view.body.len == 0) null else view.body.ptr,
        .body_len = view.body.len,
    };
}

export fn fp_document_load(handle: ?*abi.Engine, document: abi.DocumentId, url: ?[*]const u8, url_len: usize, out_request: ?*abi.RequestId) callconv(.c) u32 {
    return finish("fp_document_load", documentLoad(handle, document, url, url_len, out_request));
}

fn documentLoad(handle: ?*abi.Engine, document: abi.DocumentId, url: ?[*]const u8, url_len: usize, out_request: ?*abi.RequestId) !void {
    const engine = try enter(handle);
    const bytes = try inputRange(url, url_len);
    const out = out_request orelse return error.InvalidArgument;
    const request = try engine.load(convert(native.DocumentId, document), bytes);
    out.* = convert(abi.RequestId, request);
}

export fn fp_request_respond(handle: ?*abi.Engine, response: ?*const abi.Response) callconv(.c) u32 {
    return finish("fp_request_respond", requestRespond(handle, response));
}

fn requestRespond(handle: ?*abi.Engine, response: ?*const abi.Response) !void {
    const engine = try enter(handle);
    const input = response orelse return error.InvalidArgument;
    if (input.struct_size < @sizeOf(abi.Response)) return error.InvalidArgument;
    const body = try inputRange(input.body, input.body_len);
    try engine.respond(convert(native.RequestId, input.request_id), input.version, body);
}

export fn fp_request_reject(handle: ?*abi.Engine, request: abi.RequestId, reason: u32) callconv(.c) u32 {
    return finish("fp_request_reject", requestReject(handle, request, reason));
}

fn requestReject(handle: ?*abi.Engine, request: abi.RequestId, reason: u32) !void {
    const engine = try enter(handle);
    const known_reason = std.enums.fromInt(native.RejectReason, reason) orelse return error.InvalidArgument;
    try engine.reject(convert(native.RequestId, request), known_reason);
}

export fn fp_request_cancel(handle: ?*abi.Engine, request: abi.RequestId) callconv(.c) u32 {
    return finish("fp_request_cancel", requestCancel(handle, request));
}

fn requestCancel(handle: ?*abi.Engine, request: abi.RequestId) !void {
    const engine = try enter(handle);
    try engine.cancel(convert(native.RequestId, request));
}

export fn fp_engine_step(handle: ?*abi.Engine, budget: u32, out: ?*abi.StepOutcome, out_size: usize) callconv(.c) u32 {
    return finish("fp_engine_step", engineStep(handle, budget, out, out_size));
}

fn engineStep(handle: ?*abi.Engine, budget: u32, out: ?*abi.StepOutcome, out_size: usize) !void {
    const engine = try enter(handle);
    const result = out orelse return error.InvalidArgument;
    if (out_size < @sizeOf(abi.StepOutcome)) return error.InvalidArgument;
    const outcome = try engine.step(budget);
    result.* = .{
        .struct_size = @sizeOf(abi.StepOutcome),
        .work_remaining = @intFromBool(outcome.work_remaining),
        .applied = outcome.applied,
        .events_ready = outcome.events_ready,
        .next_deadline = switch (outcome.next_deadline) {
            .none => abi.deadline_none,
        },
    };
}

export fn fp_engine_next_event(handle: ?*abi.Engine, out: ?*abi.Event, out_size: usize) callconv(.c) u32 {
    return finish("fp_engine_next_event", engineNextEvent(handle, out, out_size));
}

fn engineNextEvent(handle: ?*abi.Engine, out: ?*abi.Event, out_size: usize) !void {
    const engine = try enter(handle);
    const result = out orelse return error.InvalidArgument;
    if (out_size < @sizeOf(abi.Event)) return error.InvalidArgument;
    result.* = eventToC(try engine.nextEvent());
}

test "the bootstrap reports no browser features" {
    var result: abi.Capabilities = undefined;
    try std.testing.expectEqual(@as(u32, 0), fp_query_capabilities(&result, @sizeOf(abi.Capabilities)));
    try std.testing.expectEqual(@as(u64, 0), result.feature_bits);
    try std.testing.expectEqual(abi_revision, result.abi_revision);
}

test "invalid output leaves caller storage unchanged" {
    var result: abi.Capabilities = .{ .struct_size = 19, .abi_revision = 23, .feature_bits = 42 };
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(null, @sizeOf(abi.Capabilities)));
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(&result, @sizeOf(abi.Capabilities) - 1));
    try std.testing.expectEqual(@as(u32, 19), result.struct_size);
    try std.testing.expectEqual(@as(u32, 23), result.abi_revision);
    try std.testing.expectEqual(@as(u64, 42), result.feature_bits);
}

const test_options: abi.EngineOptions = .{
    .struct_size = @sizeOf(abi.EngineOptions),
    .max_outstanding_requests = 64,
    .max_response_body_bytes = 1024,
};

fn createTestEngine(gpa: std.mem.Allocator) !*abi.Engine {
    var handle: ?*abi.Engine = null;
    try testing.expectEqual(ok, createEngine(gpa, &test_options, &handle));
    return handle.?;
}

fn documentState(engine: *abi.Engine, document: abi.DocumentId) !u32 {
    var info: abi.DocumentInfo = undefined;
    try testing.expectEqual(ok, fp_document_get(engine, document, &info, @sizeOf(abi.DocumentInfo)));
    return info.state;
}

fn stepOnce(engine: *abi.Engine, budget: u32) !abi.StepOutcome {
    var outcome: abi.StepOutcome = undefined;
    try testing.expectEqual(ok, fp_engine_step(engine, budget, &outcome, @sizeOf(abi.StepOutcome)));
    return outcome;
}

fn loadUrl(engine: *abi.Engine, document: abi.DocumentId, url: []const u8) !abi.RequestId {
    var request: abi.RequestId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_load(engine, document, url.ptr, url.len, &request));
    return request;
}

test "FP-0006 case 1: the C API creates and destroys an engine and a document, and a destroyed document is unknown" {
    var handle: ?*abi.Engine = null;
    try testing.expectEqual(ok, fp_engine_create(&test_options, &handle));
    const engine = handle.?;

    var document: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    try testing.expect(@backingInt(document) != 0);
    try testing.expectEqual(document_empty, try documentState(engine, document));

    try testing.expectEqual(ok, fp_document_destroy(engine, document));
    var info: abi.DocumentInfo = .{ .struct_size = 7, .state = 9, .body = null, .body_len = 11 };
    try testing.expectEqual(unknown_id, fp_document_get(engine, document, &info, @sizeOf(abi.DocumentInfo)));
    try testing.expectEqual(9, info.state);
    try testing.expectEqual(unknown_id, fp_document_destroy(engine, document));
    var request: abi.RequestId = @fromBackingInt(5);
    try testing.expectEqual(unknown_id, fp_document_load(engine, document, "u", 1, &request));
    try testing.expectEqual(5, @backingInt(request));
    try testing.expectEqual(unknown_id, fp_document_destroy(engine, @fromBackingInt(0)));
    try testing.expectEqual(ok, fp_engine_destroy(engine));
}

const ForeignCalls = struct {
    engine: *abi.Engine,
    document: abi.DocumentId,
    request: abi.RequestId,
    statuses: [10]u32 = @splat(ok),
    document_out: abi.DocumentId = @fromBackingInt(77),
    outcome: abi.StepOutcome = .{ .struct_size = 1, .work_remaining = 2, .applied = 3, .events_ready = 4, .next_deadline = 5 },

    fn run(calls: *ForeignCalls) void {
        const engine = calls.engine;
        const response: abi.Response = .{
            .struct_size = @sizeOf(abi.Response),
            .version = 1,
            .request_id = calls.request,
            .body = "foreign",
            .body_len = 7,
        };
        var info: abi.DocumentInfo = undefined;
        var event: abi.Event = undefined;
        var request: abi.RequestId = @fromBackingInt(0);
        calls.statuses = .{
            fp_document_create(engine, &calls.document_out),
            fp_document_destroy(engine, calls.document),
            fp_document_get(engine, calls.document, &info, @sizeOf(abi.DocumentInfo)),
            fp_document_load(engine, calls.document, "u", 1, &request),
            fp_request_respond(engine, &response),
            fp_request_reject(engine, calls.request, reject_unsupported_version),
            fp_request_cancel(engine, calls.request),
            fp_engine_step(engine, 8, &calls.outcome, @sizeOf(abi.StepOutcome)),
            fp_engine_next_event(engine, &event, @sizeOf(abi.Event)),
            fp_engine_destroy(engine),
        };
    }
};

test "FP-0006 case 14: a C call from another thread returns FP_STATUS_WRONG_THREAD and changes nothing" {
    const engine = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(engine)) catch unreachable;

    var document: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    const request = try loadUrl(engine, document, "https://example.test/c-case-14");
    const native_engine = nativeEngine(engine);
    const events = native_engine.events.len;

    var calls: ForeignCalls = .{ .engine = engine, .document = document, .request = request };
    const thread = try std.Thread.spawn(.{}, ForeignCalls.run, .{&calls});
    thread.join();
    for (calls.statuses) |status| try testing.expectEqual(wrong_thread, status);
    try testing.expectEqual(77, @backingInt(calls.document_out));
    try testing.expectEqual(1, calls.outcome.struct_size);
    try testing.expectEqual(document_loading, try documentState(engine, document));
    try testing.expectEqual(1, native_engine.documents.count());
    try testing.expectEqual(1, native_engine.requests.count());
    try testing.expectEqual(0, native_engine.inputs.len);
    try testing.expectEqual(events, native_engine.events.len);
}

test "FP-0006 case 16: injected allocation failure through the C entry points returns FP_STATUS_OUT_OF_MEMORY with unchanged state" {
    // Fail every remap so that each growth step is an allocation that the test can induce.
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    const gpa = failing.allocator();
    const never = std.math.maxInt(usize);

    var handle: ?*abi.Engine = null;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, createEngine(gpa, &test_options, &handle));
    try testing.expectEqual(null, handle);
    failing.fail_index = never;
    const engine = try createTestEngine(gpa);
    const native_engine = nativeEngine(engine);

    var document: abi.DocumentId = @fromBackingInt(0xD0C);
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_document_create(engine, &document));
    try testing.expectEqual(0xD0C, @backingInt(document));
    try testing.expectEqual(0, native_engine.documents.count());
    failing.fail_index = never;
    try testing.expectEqual(ok, fp_document_create(engine, &document));

    const url = "https://example.test/c-case-16";
    var request: abi.RequestId = @fromBackingInt(0x5E0);
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_document_load(engine, document, url, url.len, &request));
    try testing.expectEqual(0x5E0, @backingInt(request));
    try testing.expectEqual(document_empty, try documentState(engine, document));
    try testing.expectEqual(0, native_engine.requests.count());
    try testing.expectEqual(0, (try stepOnce(engine, 0)).events_ready);
    failing.fail_index = never;
    request = try loadUrl(engine, document, url);

    const response: abi.Response = .{
        .struct_size = @sizeOf(abi.Response),
        .version = 1,
        .request_id = request,
        .body = "<p>c case 16</p>",
        .body_len = 16,
    };
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_request_respond(engine, &response));
    try testing.expectEqual(0, (try stepOnce(engine, 0)).work_remaining);
    try testing.expectEqual(0, native_engine.inputs.len);
    try testing.expectEqual(document_loading, try documentState(engine, document));
    failing.fail_index = never;
    try testing.expectEqual(ok, fp_request_respond(engine, &response));

    // Reload a second document until only the slots that the outstanding requests reserve are free.
    // A response ends its request and uses that request's slot, so only the spare's host cancellation, which announces two events, needs storage.
    var spare: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(engine, &spare));
    var spare_request = try loadUrl(engine, spare, "https://example.test/spare");
    while (native_engine.events.buffer.len - native_engine.events.len > native_engine.requests.count()) {
        if (native_engine.events.buffer.len - native_engine.events.len == native_engine.requests.count() + 1) {
            var event: abi.Event = undefined;
            try testing.expectEqual(ok, fp_engine_next_event(engine, &event, @sizeOf(abi.Event)));
        }
        spare_request = try loadUrl(engine, spare, "https://example.test/spare");
    }
    try testing.expectEqual(ok, fp_request_cancel(engine, spare_request));
    const events = native_engine.events.len;
    var outcome: abi.StepOutcome = .{ .struct_size = 1, .work_remaining = 2, .applied = 3, .events_ready = 4, .next_deadline = 5 };
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_engine_step(engine, 8, &outcome, @sizeOf(abi.StepOutcome)));
    try testing.expectEqual(3, outcome.applied);
    try testing.expectEqual(2, native_engine.inputs.len);
    try testing.expectEqual(events, native_engine.events.len);
    try testing.expectEqual(document_loading, try documentState(engine, document));
    failing.fail_index = never;
    try testing.expectEqual(ok, fp_engine_step(engine, 8, &outcome, @sizeOf(abi.StepOutcome)));
    try testing.expectEqual(2, outcome.applied);
    try testing.expectEqual(document_loaded, try documentState(engine, document));
    try testing.expectEqual(document_failed, try documentState(engine, spare));

    try testing.expectEqual(ok, fp_engine_destroy(engine));
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "FP-0006 case 17: a document identifier from one engine is unknown in another engine" {
    const a = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(a)) catch unreachable;
    const b = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(b)) catch unreachable;

    var document: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(a, &document));
    const request = try loadUrl(a, document, "https://example.test/c-case-17");

    var info: abi.DocumentInfo = .{ .struct_size = 7, .state = 9, .body = null, .body_len = 11 };
    try testing.expectEqual(unknown_id, fp_document_get(b, document, &info, @sizeOf(abi.DocumentInfo)));
    try testing.expectEqual(9, info.state);
    try testing.expectEqual(unknown_id, fp_document_destroy(b, document));
    var foreign_request: abi.RequestId = @fromBackingInt(3);
    try testing.expectEqual(unknown_id, fp_document_load(b, document, "u", 1, &foreign_request));
    try testing.expectEqual(3, @backingInt(foreign_request));
    const response: abi.Response = .{ .struct_size = @sizeOf(abi.Response), .version = 1, .request_id = request, .body = null, .body_len = 0 };
    try testing.expectEqual(unknown_id, fp_request_respond(b, &response));
    try testing.expectEqual(unknown_id, fp_request_reject(b, request, reject_unsupported_version));
    try testing.expectEqual(unknown_id, fp_request_cancel(b, request));

    try testing.expectEqual(document_loading, try documentState(a, document));
    try testing.expectEqual(ok, fp_request_respond(a, &response));
}

test "FP-0050 case 3: fp_document_destroy cannot return FP_STATUS_OUT_OF_MEMORY" {
    const expected = [_]abi.Status{ .ok, .invalid_argument, .wrong_thread, .unknown_id };
    try testing.expectEqualSlices(abi.Status, &expected, abi.statuses.fp_document_destroy);
    const names = @typeInfo(native.DestroyDocumentError).error_set.error_names.?;
    try testing.expectEqual(2, names.len);
    for ([_][]const u8{ "WrongThread", "UnknownId" }) |wanted| {
        var found = false;
        for (names) |name| found = found or std.mem.eql(u8, name, wanted);
        try testing.expect(found);
    }
}
