//! The public C ABI. It maps opaque 64-bit identifiers to the native engine and never exposes internal handles.

const std = @import("std");
const builtin = @import("builtin");
const native = @import("engine.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const abi_revision: u32 = 0;
pub const Status = enum(u32) {
    ok = 0,
    invalid_argument = 1,
    unknown_id = 2,
    invalid_state = 3,
    unsupported_version = 4,
    limit_exceeded = 5,
    out_of_memory = 6,
    wrong_thread = 7,
};

const ok = @backingInt(Status.ok);
const invalid_argument = @backingInt(Status.invalid_argument);
const unknown_id = @backingInt(Status.unknown_id);
const out_of_memory = @backingInt(Status.out_of_memory);
const wrong_thread = @backingInt(Status.wrong_thread);

pub const EventKind = enum(u32) {
    none = 0,
    request_issued = 1,
    request_cancelled = 2,
    document_state_changed = 3,
};

/// The deadline value that means no deadline exists.
pub const deadline_none: u64 = std.math.maxInt(u64);

const document_empty = @backingInt(native.DocumentState.empty);
const document_loading = @backingInt(native.DocumentState.loading);
const document_loaded = @backingInt(native.DocumentState.loaded);
const reject_unsupported_version = @backingInt(native.RejectReason.unsupported_version);

pub const Capabilities = extern struct {
    struct_size: u32,
    abi_revision: u32,
    feature_bits: u64,
};

pub const EngineOptions = extern struct {
    struct_size: u32,
    max_outstanding_requests: u32,
    max_response_body_bytes: u64,
};

pub const DocumentInfo = extern struct {
    struct_size: u32,
    state: u32,
    body: ?[*]const u8,
    body_len: usize,
};

pub const Response = extern struct {
    struct_size: u32,
    version: u32,
    request_id: u64,
    body: ?[*]const u8,
    body_len: usize,
};

pub const StepOutcome = extern struct {
    struct_size: u32,
    work_remaining: u32,
    applied: u64,
    events_ready: u64,
    next_deadline: u64,
};

pub const Event = extern struct {
    struct_size: u32,
    kind: u32,
    document_id: u64,
    request_id: u64,
    request_kind: u32,
    request_version: u32,
    document_state: u32,
    reject_reason: u32,
    url: ?[*]const u8,
    url_len: usize,
};

/// The C name of a native engine. The pointer is the native engine itself, not a handle.
pub const Engine = opaque {};

/// The allocator behind every engine that `fp_engine_create` creates.
const process_allocator: Allocator = if (builtin.single_threaded) std.heap.page_allocator else std.heap.smp_allocator;

const Failure = native.Error || error{InvalidArgument};

fn statusOf(err: Failure) u32 {
    const status: Status = switch (err) {
        error.InvalidArgument => .invalid_argument,
        error.WrongThread => .wrong_thread,
        error.UnknownId => .unknown_id,
        error.InvalidState => .invalid_state,
        error.UnsupportedVersion => .unsupported_version,
        error.LimitExceeded, error.IdentifiersExhausted => .limit_exceeded,
        error.OutOfMemory => .out_of_memory,
    };
    return @backingInt(status);
}

fn nativeEngine(handle: *Engine) *native.Engine {
    return @ptrCast(@alignCast(handle));
}

/// Resolves the engine argument and checks the calling thread before any other argument.
fn enter(handle: ?*Engine) Failure!*native.Engine {
    const resolved = nativeEngine(handle orelse return error.InvalidArgument);
    try resolved.checkThread();
    return resolved;
}

/// `fp_engine_create` with an explicit allocator, so tests can inject allocation failure.
fn createEngine(gpa: Allocator, options: ?*const EngineOptions, out_engine: ?*?*Engine) u32 {
    const input = options orelse return invalid_argument;
    const out = out_engine orelse return invalid_argument;
    if (input.struct_size < @sizeOf(EngineOptions)) return invalid_argument;
    const created = native.Engine.create(gpa, .{
        .max_outstanding_requests = input.max_outstanding_requests,
        // A bound beyond the address space admits every body that the host can present.
        .max_response_body_bytes = std.math.cast(usize, input.max_response_body_bytes) orelse std.math.maxInt(usize),
    }) catch |err| return statusOf(err);
    out.* = @ptrCast(created);
    return ok;
}

fn eventToC(event: ?native.Event) Event {
    var result: Event = .{
        .struct_size = @sizeOf(Event),
        .kind = @backingInt(EventKind.none),
        .document_id = 0,
        .request_id = 0,
        .request_kind = 0,
        .request_version = 0,
        .document_state = 0,
        .reject_reason = 0,
        .url = null,
        .url_len = 0,
    };
    switch (event orelse return result) {
        .request_issued, .request_cancelled => |notice| {
            result.document_id = @backingInt(notice.document);
            result.request_id = @backingInt(notice.request);
            result.request_kind = @backingInt(notice.kind);
            result.request_version = notice.version;
            if (notice.url) |bytes| {
                result.url = bytes.ptr;
                result.url_len = bytes.len;
            }
        },
        .document_state_changed => |change| {
            result.document_id = @backingInt(change.document);
            result.request_id = @backingInt(change.request);
            result.request_kind = @backingInt(change.kind);
            result.request_version = change.version;
            result.document_state = @backingInt(change.state);
            if (change.reject_reason) |reason| result.reject_reason = @backingInt(reason);
        },
    }
    result.kind = @backingInt(@as(EventKind, switch (event.?) {
        .request_issued => .request_issued,
        .request_cancelled => .request_cancelled,
        .document_state_changed => .document_state_changed,
    }));
    return result;
}

export fn fp_abi_revision() callconv(.c) u32 {
    return abi_revision;
}

export fn fp_query_capabilities(out: ?*Capabilities, out_size: usize) callconv(.c) u32 {
    const result = out orelse return @backingInt(Status.invalid_argument);
    if (out_size < @sizeOf(Capabilities)) return @backingInt(Status.invalid_argument);
    result.* = .{
        .struct_size = @sizeOf(Capabilities),
        .abi_revision = abi_revision,
        .feature_bits = 0,
    };
    return @backingInt(Status.ok);
}

export fn fp_engine_create(options: ?*const EngineOptions, out_engine: ?*?*Engine) callconv(.c) u32 {
    return createEngine(process_allocator, options, out_engine);
}

export fn fp_engine_destroy(handle: ?*Engine) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    engine.destroy() catch |err| return statusOf(err);
    return ok;
}

export fn fp_document_create(handle: ?*Engine, out_document: ?*u64) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const out = out_document orelse return invalid_argument;
    const id = engine.createDocument() catch |err| return statusOf(err);
    out.* = @backingInt(id);
    return ok;
}

export fn fp_document_destroy(handle: ?*Engine, document: u64) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    engine.destroyDocument(@fromBackingInt(document)) catch |err| return statusOf(err);
    return ok;
}

export fn fp_document_get(handle: ?*Engine, document: u64, out: ?*DocumentInfo, out_size: usize) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const result = out orelse return invalid_argument;
    if (out_size < @sizeOf(DocumentInfo)) return invalid_argument;
    const view = engine.document(@fromBackingInt(document)) catch |err| return statusOf(err);
    result.* = .{
        .struct_size = @sizeOf(DocumentInfo),
        .state = @backingInt(view.state),
        .body = if (view.body.len == 0) null else view.body.ptr,
        .body_len = view.body.len,
    };
    return ok;
}

export fn fp_document_load(handle: ?*Engine, document: u64, url: ?[*]const u8, url_len: usize, out_request: ?*u64) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const bytes = url orelse return invalid_argument;
    const out = out_request orelse return invalid_argument;
    const request = engine.load(@fromBackingInt(document), bytes[0..url_len]) catch |err| return statusOf(err);
    out.* = @backingInt(request);
    return ok;
}

export fn fp_request_respond(handle: ?*Engine, response: ?*const Response) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const input = response orelse return invalid_argument;
    if (input.struct_size < @sizeOf(Response)) return invalid_argument;
    const body: []const u8 = if (input.body) |bytes|
        bytes[0..input.body_len]
    else if (input.body_len == 0)
        &.{}
    else
        return invalid_argument;
    engine.respond(@fromBackingInt(input.request_id), input.version, body) catch |err| return statusOf(err);
    return ok;
}

export fn fp_request_reject(handle: ?*Engine, request: u64, reason: u32) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const known_reason = std.enums.fromInt(native.RejectReason, reason) orelse return invalid_argument;
    engine.reject(@fromBackingInt(request), known_reason) catch |err| return statusOf(err);
    return ok;
}

export fn fp_request_cancel(handle: ?*Engine, request: u64) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    engine.cancel(@fromBackingInt(request)) catch |err| return statusOf(err);
    return ok;
}

export fn fp_engine_step(handle: ?*Engine, budget: u32, out: ?*StepOutcome, out_size: usize) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const result = out orelse return invalid_argument;
    if (out_size < @sizeOf(StepOutcome)) return invalid_argument;
    const outcome = engine.step(budget) catch |err| return statusOf(err);
    result.* = .{
        .struct_size = @sizeOf(StepOutcome),
        .work_remaining = @intFromBool(outcome.work_remaining),
        .applied = outcome.applied,
        .events_ready = outcome.events_ready,
        .next_deadline = switch (outcome.next_deadline) {
            .none => deadline_none,
        },
    };
    return ok;
}

export fn fp_engine_next_event(handle: ?*Engine, out: ?*Event, out_size: usize) callconv(.c) u32 {
    const engine = enter(handle) catch |err| return statusOf(err);
    const result = out orelse return invalid_argument;
    if (out_size < @sizeOf(Event)) return invalid_argument;
    const event = engine.nextEvent() catch |err| return statusOf(err);
    result.* = eventToC(event);
    return ok;
}

test "the bootstrap reports no browser features" {
    var result: Capabilities = undefined;
    try std.testing.expectEqual(@as(u32, 0), fp_query_capabilities(&result, @sizeOf(Capabilities)));
    try std.testing.expectEqual(@as(u64, 0), result.feature_bits);
    try std.testing.expectEqual(abi_revision, result.abi_revision);
}

test "invalid output leaves caller storage unchanged" {
    var result: Capabilities = .{ .struct_size = 19, .abi_revision = 23, .feature_bits = 42 };
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(null, @sizeOf(Capabilities)));
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(&result, @sizeOf(Capabilities) - 1));
    try std.testing.expectEqual(@as(u32, 19), result.struct_size);
    try std.testing.expectEqual(@as(u32, 23), result.abi_revision);
    try std.testing.expectEqual(@as(u64, 42), result.feature_bits);
}

const test_options: EngineOptions = .{
    .struct_size = @sizeOf(EngineOptions),
    .max_outstanding_requests = 64,
    .max_response_body_bytes = 1024,
};

fn createTestEngine(gpa: std.mem.Allocator) !*Engine {
    var handle: ?*Engine = null;
    try testing.expectEqual(ok, createEngine(gpa, &test_options, &handle));
    return handle.?;
}

fn documentState(engine: *Engine, document: u64) !u32 {
    var info: DocumentInfo = undefined;
    try testing.expectEqual(ok, fp_document_get(engine, document, &info, @sizeOf(DocumentInfo)));
    return info.state;
}

fn stepOnce(engine: *Engine, budget: u32) !StepOutcome {
    var outcome: StepOutcome = undefined;
    try testing.expectEqual(ok, fp_engine_step(engine, budget, &outcome, @sizeOf(StepOutcome)));
    return outcome;
}

fn loadUrl(engine: *Engine, document: u64, url: []const u8) !u64 {
    var request: u64 = 0;
    try testing.expectEqual(ok, fp_document_load(engine, document, url.ptr, url.len, &request));
    return request;
}

test "FP-0006 case 1: the C API creates and destroys an engine and a document, and a destroyed document is unknown" {
    var handle: ?*Engine = null;
    try testing.expectEqual(ok, fp_engine_create(&test_options, &handle));
    const engine = handle.?;

    var document: u64 = 0;
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    try testing.expect(document != 0);
    try testing.expectEqual(document_empty, try documentState(engine, document));

    try testing.expectEqual(ok, fp_document_destroy(engine, document));
    var info: DocumentInfo = .{ .struct_size = 7, .state = 9, .body = null, .body_len = 11 };
    try testing.expectEqual(unknown_id, fp_document_get(engine, document, &info, @sizeOf(DocumentInfo)));
    try testing.expectEqual(9, info.state);
    try testing.expectEqual(unknown_id, fp_document_destroy(engine, document));
    var request: u64 = 5;
    try testing.expectEqual(unknown_id, fp_document_load(engine, document, "u", 1, &request));
    try testing.expectEqual(5, request);
    try testing.expectEqual(unknown_id, fp_document_destroy(engine, 0));
    try testing.expectEqual(ok, fp_engine_destroy(engine));
}

const ForeignCalls = struct {
    engine: *Engine,
    document: u64,
    request: u64,
    statuses: [10]u32 = @splat(ok),
    document_out: u64 = 77,
    outcome: StepOutcome = .{ .struct_size = 1, .work_remaining = 2, .applied = 3, .events_ready = 4, .next_deadline = 5 },

    fn run(calls: *ForeignCalls) void {
        const engine = calls.engine;
        const response: Response = .{
            .struct_size = @sizeOf(Response),
            .version = 1,
            .request_id = calls.request,
            .body = "foreign",
            .body_len = 7,
        };
        var info: DocumentInfo = undefined;
        var event: Event = undefined;
        var request: u64 = 0;
        calls.statuses = .{
            fp_document_create(engine, &calls.document_out),
            fp_document_destroy(engine, calls.document),
            fp_document_get(engine, calls.document, &info, @sizeOf(DocumentInfo)),
            fp_document_load(engine, calls.document, "u", 1, &request),
            fp_request_respond(engine, &response),
            fp_request_reject(engine, calls.request, reject_unsupported_version),
            fp_request_cancel(engine, calls.request),
            fp_engine_step(engine, 8, &calls.outcome, @sizeOf(StepOutcome)),
            fp_engine_next_event(engine, &event, @sizeOf(Event)),
            fp_engine_destroy(engine),
        };
    }
};

test "FP-0006 case 14: a C call from another thread returns FP_STATUS_WRONG_THREAD and changes nothing" {
    const engine = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(engine)) catch unreachable;

    var document: u64 = 0;
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    const request = try loadUrl(engine, document, "https://example.test/c-case-14");
    const native_engine = nativeEngine(engine);
    const events = native_engine.events.len;

    var calls: ForeignCalls = .{ .engine = engine, .document = document, .request = request };
    const thread = try std.Thread.spawn(.{}, ForeignCalls.run, .{&calls});
    thread.join();
    for (calls.statuses) |status| try testing.expectEqual(wrong_thread, status);
    try testing.expectEqual(77, calls.document_out);
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

    var handle: ?*Engine = null;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, createEngine(gpa, &test_options, &handle));
    try testing.expectEqual(null, handle);
    failing.fail_index = never;
    const engine = try createTestEngine(gpa);
    const native_engine = nativeEngine(engine);

    var document: u64 = 0xD0C;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_document_create(engine, &document));
    try testing.expectEqual(0xD0C, document);
    try testing.expectEqual(0, native_engine.documents.count());
    failing.fail_index = never;
    try testing.expectEqual(ok, fp_document_create(engine, &document));

    const url = "https://example.test/c-case-16";
    var request: u64 = 0x5E0;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_document_load(engine, document, url, url.len, &request));
    try testing.expectEqual(0x5E0, request);
    try testing.expectEqual(document_empty, try documentState(engine, document));
    try testing.expectEqual(0, native_engine.requests.count());
    try testing.expectEqual(0, (try stepOnce(engine, 0)).events_ready);
    failing.fail_index = never;
    request = try loadUrl(engine, document, url);

    const response: Response = .{
        .struct_size = @sizeOf(Response),
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

    // Reload a second document until no event slot is free, so the step must grow the event queue.
    var spare: u64 = 0;
    try testing.expectEqual(ok, fp_document_create(engine, &spare));
    while (native_engine.events.buffer.len - native_engine.events.len != 0) {
        if (native_engine.events.buffer.len - native_engine.events.len == 1) {
            var event: Event = undefined;
            try testing.expectEqual(ok, fp_engine_next_event(engine, &event, @sizeOf(Event)));
        }
        _ = try loadUrl(engine, spare, "https://example.test/spare");
    }
    const events = native_engine.events.len;
    var outcome: StepOutcome = .{ .struct_size = 1, .work_remaining = 2, .applied = 3, .events_ready = 4, .next_deadline = 5 };
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, fp_engine_step(engine, 8, &outcome, @sizeOf(StepOutcome)));
    try testing.expectEqual(3, outcome.applied);
    try testing.expectEqual(1, native_engine.inputs.len);
    try testing.expectEqual(events, native_engine.events.len);
    try testing.expectEqual(document_loading, try documentState(engine, document));
    failing.fail_index = never;
    try testing.expectEqual(ok, fp_engine_step(engine, 8, &outcome, @sizeOf(StepOutcome)));
    try testing.expectEqual(1, outcome.applied);
    try testing.expectEqual(document_loaded, try documentState(engine, document));

    try testing.expectEqual(ok, fp_engine_destroy(engine));
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "FP-0006 case 17: a document identifier from one engine is unknown in another engine" {
    const a = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(a)) catch unreachable;
    const b = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(b)) catch unreachable;

    var document: u64 = 0;
    try testing.expectEqual(ok, fp_document_create(a, &document));
    const request = try loadUrl(a, document, "https://example.test/c-case-17");

    var info: DocumentInfo = .{ .struct_size = 7, .state = 9, .body = null, .body_len = 11 };
    try testing.expectEqual(unknown_id, fp_document_get(b, document, &info, @sizeOf(DocumentInfo)));
    try testing.expectEqual(9, info.state);
    try testing.expectEqual(unknown_id, fp_document_destroy(b, document));
    var foreign_request: u64 = 3;
    try testing.expectEqual(unknown_id, fp_document_load(b, document, "u", 1, &foreign_request));
    try testing.expectEqual(3, foreign_request);
    const response: Response = .{ .struct_size = @sizeOf(Response), .version = 1, .request_id = request, .body = null, .body_len = 0 };
    try testing.expectEqual(unknown_id, fp_request_respond(b, &response));
    try testing.expectEqual(unknown_id, fp_request_reject(b, request, reject_unsupported_version));
    try testing.expectEqual(unknown_id, fp_request_cancel(b, request));

    try testing.expectEqual(document_loading, try documentState(a, document));
    try testing.expectEqual(ok, fp_request_respond(a, &response));
}
