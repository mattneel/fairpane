//! The shared foreign-runtime failure scenarios of `api/failure-scenarios.json`, run in Zig.
//!
//! Every call binds an exported C symbol of the actual engine through its generated function type, as a foreign caller does.
//! Scenarios that need an allocator create the engine with `c_api.createEngine`, the allocator-taking form of `fp_engine_create`.
//! Some checks read the native engine's queue lengths to show that a failed call changed nothing.
//! The allocation-failure scenario runs twice: once with a failing allocator, and once through the engine's memory limit alone, as C runs it.

const std = @import("std");
const abi = @import("abi_generated.zig");
const c_api = @import("c_api.zig");
const native = @import("engine.zig");
const testing = std.testing;

/// Binds an exported C symbol through its generated function type.
fn bind(comptime name: []const u8) *const @field(abi.functions, name) {
    return @extern(*const @field(abi.functions, name), .{ .name = name });
}

const fp_abi_revision = bind("fp_abi_revision");
const fp_query_capabilities = bind("fp_query_capabilities");
const fp_engine_create = bind("fp_engine_create");
const fp_engine_destroy = bind("fp_engine_destroy");
const fp_engine_get_memory = bind("fp_engine_get_memory");
const fp_engine_set_memory_limit = bind("fp_engine_set_memory_limit");
const fp_document_create = bind("fp_document_create");
const fp_document_destroy = bind("fp_document_destroy");
const fp_document_get = bind("fp_document_get");
const fp_document_load = bind("fp_document_load");
const fp_request_respond = bind("fp_request_respond");
const fp_request_reject = bind("fp_request_reject");
const fp_request_cancel = bind("fp_request_cancel");
const fp_engine_step = bind("fp_engine_step");
const fp_engine_next_event = bind("fp_engine_next_event");

const ok = @backingInt(abi.Status.ok);
const invalid_argument = @backingInt(abi.Status.invalid_argument);
const unknown_id = @backingInt(abi.Status.unknown_id);
const invalid_state = @backingInt(abi.Status.invalid_state);
const limit_exceeded = @backingInt(abi.Status.limit_exceeded);
const out_of_memory = @backingInt(abi.Status.out_of_memory);
const wrong_thread = @backingInt(abi.Status.wrong_thread);
const reject_unsupported_version = @backingInt(abi.RejectReason.unsupported_version);
const never = std.math.maxInt(usize);
const unlimited = std.math.maxInt(u64);
const pattern: u8 = 0xA5;

fn options(max_outstanding_requests: u32, max_response_body_bytes: u64) abi.EngineOptions {
    return .{
        .struct_size = @sizeOf(abi.EngineOptions),
        .max_outstanding_requests = max_outstanding_requests,
        .max_response_body_bytes = max_response_body_bytes,
        .max_allocated_bytes = unlimited,
    };
}

const default_options = options(4, 16);

fn createEngine(engine_options: abi.EngineOptions) !*abi.Engine {
    var engine: ?*abi.Engine = null;
    try testing.expectEqual(ok, fp_engine_create(&engine_options, &engine));
    return engine.?;
}

/// Creates an engine whose storage comes from `gpa`, so the test allocator can detect a leak.
fn createTracked(gpa: std.mem.Allocator, engine_options: abi.EngineOptions) !*abi.Engine {
    var engine: ?*abi.Engine = null;
    try testing.expectEqual(ok, c_api.createEngine(gpa, &engine_options, &engine));
    return engine.?;
}

fn destroyEngine(engine: *abi.Engine) void {
    testing.expectEqual(ok, fp_engine_destroy(engine)) catch unreachable;
}

fn createDocument(engine: *abi.Engine) !abi.DocumentId {
    var document: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    return document;
}

fn load(engine: *abi.Engine, document: abi.DocumentId, url: []const u8) !abi.RequestId {
    var request: abi.RequestId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_load(engine, document, url.ptr, url.len, &request));
    return request;
}

fn response(request: abi.RequestId, body: []const u8) abi.Response {
    return .{ .struct_size = @sizeOf(abi.Response), .version = abi.resource_request_version, .request_id = request, .body = body.ptr, .body_len = body.len };
}

fn respond(engine: *abi.Engine, request: abi.RequestId, body: []const u8) !void {
    const answer = response(request, body);
    try testing.expectEqual(ok, fp_request_respond(engine, &answer));
}

fn info(engine: *abi.Engine, document: abi.DocumentId) !abi.DocumentInfo {
    var result: abi.DocumentInfo = undefined;
    try testing.expectEqual(ok, fp_document_get(engine, document, &result, @sizeOf(abi.DocumentInfo)));
    return result;
}

fn state(engine: *abi.Engine, document: abi.DocumentId) !abi.DocumentState {
    return std.enums.fromInt(abi.DocumentState, (try info(engine, document)).state).?;
}

fn step(engine: *abi.Engine, budget: u32) !abi.StepOutcome {
    var outcome: abi.StepOutcome = undefined;
    try testing.expectEqual(ok, fp_engine_step(engine, budget, &outcome, @sizeOf(abi.StepOutcome)));
    return outcome;
}

fn nextEvent(engine: *abi.Engine) !abi.Event {
    var event: abi.Event = undefined;
    try testing.expectEqual(ok, fp_engine_next_event(engine, &event, @sizeOf(abi.Event)));
    return event;
}

fn memory(engine: *abi.Engine) !abi.EngineMemory {
    var result: abi.EngineMemory = undefined;
    try testing.expectEqual(ok, fp_engine_get_memory(engine, &result, @sizeOf(abi.EngineMemory)));
    try testing.expectEqual(@sizeOf(abi.EngineMemory), result.struct_size);
    try testing.expectEqual(0, result.reserved);
    return result;
}

/// Removes the next event and checks its kind, document, and request.
fn expectEvent(engine: *abi.Engine, kind: abi.EventKind, document: abi.DocumentId, request: abi.RequestId) !abi.Event {
    const event = try nextEvent(engine);
    try testing.expectEqual(@backingInt(kind), event.kind);
    try testing.expectEqual(@as(?abi.DocumentId, document), event.document_id.get());
    try testing.expectEqual(@as(?abi.RequestId, request), event.request_id.get());
    try testing.expectEqual(@as(?abi.RequestKind, .resource), event.request_kind.get());
    try testing.expectEqual(@as(?u32, abi.resource_request_version), event.request_version.get());
    return event;
}

fn expectNoEvent(engine: *abi.Engine) !void {
    const event = try nextEvent(engine);
    try testing.expectEqual(@backingInt(abi.EventKind.none), event.kind);
    try testing.expectEqual(abi.Optional(abi.DocumentId).absent, event.document_id);
    try testing.expectEqual(null, event.url);
}

fn drain(engine: *abi.Engine) !void {
    while ((try nextEvent(engine)).kind != @backingInt(abi.EventKind.none)) {}
}

/// Fills caller storage with a byte pattern, including padding.
fn fill(storage: anytype) void {
    @memset(std.mem.asBytes(storage), pattern);
}

fn expectFilled(storage: anytype) !void {
    for (std.mem.asBytes(storage)) |byte| try testing.expectEqual(pattern, byte);
}

fn nativeOf(engine: *abi.Engine) *native.Engine {
    return @ptrCast(@alignCast(engine));
}

/// The engine's contents, which a failed call must leave unchanged.
const Snapshot = struct { documents: usize, requests: usize, inputs: usize, events: usize };

fn snapshot(engine: *abi.Engine) Snapshot {
    const inner = nativeOf(engine);
    return .{ .documents = inner.documents.count(), .requests = inner.requests.count(), .inputs = inner.inputs.len, .events = inner.events.len };
}

/// Checks that every document call with `document` returns FP_STATUS_UNKNOWN_ID and writes no output.
fn expectUnknownDocument(engine: *abi.Engine, document: abi.DocumentId) !void {
    var result: abi.DocumentInfo = undefined;
    fill(&result);
    try testing.expectEqual(unknown_id, fp_document_get(engine, document, &result, @sizeOf(abi.DocumentInfo)));
    try expectFilled(&result);
    try testing.expectEqual(unknown_id, fp_document_destroy(engine, document));
    var request: abi.RequestId = @fromBackingInt(0x5E0);
    try testing.expectEqual(unknown_id, fp_document_load(engine, document, "u", 1, &request));
    try testing.expectEqual(0x5E0, @backingInt(request));
}

/// Checks that every request call with `request` returns FP_STATUS_UNKNOWN_ID.
fn expectUnknownRequest(engine: *abi.Engine, request: abi.RequestId) !void {
    const answer = response(request, "body");
    try testing.expectEqual(unknown_id, fp_request_respond(engine, &answer));
    try testing.expectEqual(unknown_id, fp_request_reject(engine, request, reject_unsupported_version));
    try testing.expectEqual(unknown_id, fp_request_cancel(engine, request));
}

test "Scenario unknown-identifier: zero, never-issued, and other-family identifiers return FP_STATUS_UNKNOWN_ID and change nothing" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/unknown");
    try drain(engine);
    const before = snapshot(engine);

    for ([_]u64{ 0, std.math.maxInt(u64) }) |raw| {
        try expectUnknownDocument(engine, @fromBackingInt(raw));
        try expectUnknownRequest(engine, @fromBackingInt(raw));
    }
    // Document and request identifiers come from one sequence, so one family never names the other.
    try expectUnknownDocument(engine, @fromBackingInt(@backingInt(request)));
    try expectUnknownRequest(engine, @fromBackingInt(@backingInt(document)));

    try testing.expectEqual(before, snapshot(engine));
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    try respond(engine, request, "known");
}

test "Scenario foreign-identifier: identifiers from another engine return FP_STATUS_UNKNOWN_ID and change neither engine" {
    const a = try createEngine(default_options);
    defer destroyEngine(a);
    const b = try createEngine(default_options);
    defer destroyEngine(b);
    const document = try createDocument(a);
    const request = try load(a, document, "https://example.test/foreign");
    const own = try createDocument(b);
    const before_a = snapshot(a);
    const before_b = snapshot(b);

    try expectUnknownDocument(b, document);
    try expectUnknownRequest(b, request);

    try testing.expectEqual(before_a, snapshot(a));
    try testing.expectEqual(before_b, snapshot(b));
    try testing.expectEqual(abi.DocumentState.loading, try state(a, document));
    try testing.expectEqual(abi.DocumentState.empty, try state(b, own));
    try respond(a, request, "home");
}

test "Scenario retired-identifier: a destroyed document and an ended request return FP_STATUS_UNKNOWN_ID" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);

    const destroyed = try createDocument(engine);
    const orphaned = try load(engine, destroyed, "https://example.test/destroyed");
    try testing.expectEqual(ok, fp_document_destroy(engine, destroyed));
    try expectUnknownDocument(engine, destroyed);
    try expectUnknownRequest(engine, orphaned);

    const document = try createDocument(engine);
    const replaced = try load(engine, document, "https://example.test/first");
    const answered = try load(engine, document, "https://example.test/second");
    try expectUnknownRequest(engine, replaced);
    try respond(engine, answered, "done");
    try testing.expectEqual(1, (try step(engine, 8)).applied);
    try expectUnknownRequest(engine, answered);
    try testing.expectEqual(abi.DocumentState.loaded, try state(engine, document));
}

/// Calls every function from a thread that does not own the engine, with valid and then invalid arguments.
const ForeignThread = struct {
    engine: *abi.Engine,
    document: abi.DocumentId,
    request: abi.RequestId,
    statuses: [13]u32 = @splat(ok),
    invalid_statuses: [16]u32 = @splat(ok),
    revision: u32 = 99,
    capabilities_status: u32 = 99,
    document_out: abi.DocumentId = @fromBackingInt(77),
    request_out: abi.RequestId = @fromBackingInt(78),
    info: abi.DocumentInfo = undefined,
    outcome: abi.StepOutcome = undefined,
    event: abi.Event = undefined,
    memory: abi.EngineMemory = undefined,

    fn run(calls: *ForeignThread) void {
        const engine = calls.engine;
        const answer = response(calls.request, "foreign");
        var short_answer = response(calls.request, "short");
        short_answer.struct_size = @sizeOf(abi.Response) - 1;
        var capabilities: abi.Capabilities = undefined;
        calls.revision = fp_abi_revision();
        calls.capabilities_status = fp_query_capabilities(&capabilities, @sizeOf(abi.Capabilities));
        // The thread check precedes every other argument check, so an invalid argument also returns FP_STATUS_WRONG_THREAD.
        // fp_engine_destroy has no argument other than the engine, so only its valid call below covers it.
        calls.invalid_statuses = .{
            fp_document_create(engine, null),
            fp_document_destroy(engine, @fromBackingInt(0)),
            fp_document_get(engine, calls.document, null, @sizeOf(abi.DocumentInfo)),
            fp_document_get(engine, calls.document, &calls.info, @sizeOf(abi.DocumentInfo) - 1),
            fp_document_load(engine, calls.document, null, 1, &calls.request_out),
            fp_document_load(engine, calls.document, "u", 1, null),
            fp_request_respond(engine, null),
            fp_request_respond(engine, &short_answer),
            fp_request_reject(engine, calls.request, 0),
            fp_request_cancel(engine, @fromBackingInt(0)),
            fp_engine_step(engine, 8, null, @sizeOf(abi.StepOutcome)),
            fp_engine_step(engine, 8, &calls.outcome, @sizeOf(abi.StepOutcome) - 1),
            fp_engine_next_event(engine, null, @sizeOf(abi.Event)),
            fp_engine_next_event(engine, &calls.event, 0),
            fp_engine_get_memory(engine, null, @sizeOf(abi.EngineMemory)),
            fp_engine_get_memory(engine, &calls.memory, @sizeOf(abi.EngineMemory) - 1),
        };
        calls.statuses = .{
            fp_document_create(engine, &calls.document_out),
            fp_document_destroy(engine, calls.document),
            fp_document_get(engine, calls.document, &calls.info, @sizeOf(abi.DocumentInfo)),
            fp_document_load(engine, calls.document, "u", 1, &calls.request_out),
            fp_request_respond(engine, &answer),
            fp_request_reject(engine, calls.request, reject_unsupported_version),
            fp_request_cancel(engine, calls.request),
            fp_engine_step(engine, 8, &calls.outcome, @sizeOf(abi.StepOutcome)),
            fp_engine_next_event(engine, &calls.event, @sizeOf(abi.Event)),
            fp_engine_get_memory(engine, &calls.memory, @sizeOf(abi.EngineMemory)),
            // Every limit is valid, so the second call passes a different valid limit instead of an invalid argument.
            fp_engine_set_memory_limit(engine, 0),
            fp_engine_set_memory_limit(engine, unlimited),
            fp_engine_destroy(engine),
        };
    }
};

test "Scenario wrong-thread: every owner-thread function returns FP_STATUS_WRONG_THREAD from another thread, even with an invalid argument, and changes nothing" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/thread");
    // A limit that neither foreign limit call sets shows that neither one applied.
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited - 1));
    const before = snapshot(engine);
    const before_memory = try memory(engine);
    try testing.expectEqual(unlimited - 1, before_memory.max_allocated_bytes);

    var calls: ForeignThread = .{ .engine = engine, .document = document, .request = request };
    fill(&calls.info);
    fill(&calls.outcome);
    fill(&calls.event);
    fill(&calls.memory);
    const thread = try std.Thread.spawn(.{}, ForeignThread.run, .{&calls});
    thread.join();

    for (calls.statuses) |status| try testing.expectEqual(wrong_thread, status);
    for (calls.invalid_statuses) |status| try testing.expectEqual(wrong_thread, status);
    try testing.expectEqual(abi.abi_revision, calls.revision);
    try testing.expectEqual(ok, calls.capabilities_status);
    try testing.expectEqual(77, @backingInt(calls.document_out));
    try testing.expectEqual(78, @backingInt(calls.request_out));
    try expectFilled(&calls.info);
    try expectFilled(&calls.outcome);
    try expectFilled(&calls.event);
    try expectFilled(&calls.memory);
    try testing.expectEqual(before, snapshot(engine));
    try testing.expectEqual(before_memory, try memory(engine));
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    try respond(engine, request, "owner");
}

test "Scenario cancel-before-answer-queued: a host cancellation queues input, and the step fails the document" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/cancel-before");
    try drain(engine);

    try testing.expectEqual(ok, fp_request_cancel(engine, request));
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    const outcome = try step(engine, 8);
    try testing.expectEqual(1, outcome.applied);
    try testing.expectEqual(0, outcome.work_remaining);
    try testing.expectEqual(2, outcome.events_ready);
    try testing.expectEqual(abi.DocumentState.failed, try state(engine, document));

    _ = try expectEvent(engine, .request_cancelled, document, request);
    const change = try expectEvent(engine, .document_state_changed, document, request);
    try testing.expectEqual(@as(?abi.DocumentState, .failed), change.document_state.get());
    try testing.expectEqual(abi.Optional(abi.RejectReason).absent, change.reject_reason);
    try expectNoEvent(engine);
    try expectUnknownRequest(engine, request);
}

test "Scenario cancel-after-answer-queued: a queued answer blocks a host cancellation, and an engine cancellation discards it" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const first = try load(engine, document, "https://example.test/cancel-after");
    try drain(engine);

    try respond(engine, first, "queued");
    const again = response(first, "again");
    try testing.expectEqual(invalid_state, fp_request_cancel(engine, first));
    try testing.expectEqual(invalid_state, fp_request_reject(engine, first, reject_unsupported_version));
    try testing.expectEqual(invalid_state, fp_request_respond(engine, &again));

    const second = try load(engine, document, "https://example.test/cancel-after-reload");
    _ = try expectEvent(engine, .request_cancelled, document, first);
    _ = try expectEvent(engine, .request_issued, document, second);
    try expectNoEvent(engine);
    const outcome = try step(engine, 8);
    try testing.expectEqual(0, outcome.applied);
    try testing.expectEqual(0, outcome.work_remaining);
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    try expectUnknownRequest(engine, first);

    try respond(engine, second, "second");
    try testing.expectEqual(1, (try step(engine, 8)).applied);
    const loaded = try info(engine, document);
    try testing.expectEqual(abi.DocumentState.loaded, std.enums.fromInt(abi.DocumentState, loaded.state).?);
    try testing.expectEqualStrings("second", loaded.body.?[0..loaded.body_len]);
}

test "Scenario document-teardown-outstanding: destroying a document cancels its request, discards its answer, and keeps other documents" {
    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const doomed = try createDocument(engine);
    const doomed_request = try load(engine, doomed, "https://example.test/doomed");
    try respond(engine, doomed_request, "discarded");
    const kept = try createDocument(engine);
    const kept_request = try load(engine, kept, "https://example.test/kept");

    try testing.expectEqual(ok, fp_document_destroy(engine, doomed));
    const issued = try expectEvent(engine, .request_issued, doomed, doomed_request);
    try testing.expectEqual(null, issued.url);
    try testing.expectEqual(0, issued.url_len);
    _ = try expectEvent(engine, .document_state_changed, doomed, doomed_request);
    _ = try expectEvent(engine, .request_issued, kept, kept_request);
    _ = try expectEvent(engine, .document_state_changed, kept, kept_request);
    _ = try expectEvent(engine, .request_cancelled, doomed, doomed_request);
    try expectNoEvent(engine);

    const outcome = try step(engine, 8);
    try testing.expectEqual(0, outcome.applied);
    try testing.expectEqual(0, outcome.work_remaining);
    try expectUnknownDocument(engine, doomed);
    try expectUnknownRequest(engine, doomed_request);
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, kept));
    try respond(engine, kept_request, "kept");
}

test "Scenario engine-teardown-outstanding: destroying an engine releases outstanding requests, queued answers, bodies, and undrained events" {
    const engine = try createTracked(testing.allocator, default_options);
    const answered = try createDocument(engine);
    try respond(engine, try load(engine, answered, "https://example.test/answered"), "queued");
    const outstanding = try createDocument(engine);
    _ = try load(engine, outstanding, "https://example.test/outstanding");
    const loaded = try createDocument(engine);
    try respond(engine, try load(engine, loaded, "https://example.test/loaded"), "body");
    try testing.expectEqual(2, (try step(engine, 8)).applied);
    // The answer for `answered` applied too, so queue another answer that no step applies.
    const requeued = try load(engine, answered, "https://example.test/requeued");
    try respond(engine, requeued, "pending");
    const before = snapshot(engine);
    try testing.expect(before.inputs == 1 and before.requests == 2 and before.events > 0);

    // The test allocator reports any storage that the destruction leaks.
    try testing.expectEqual(ok, fp_engine_destroy(engine));
}

/// Fails the first allocation of an attempt, then the second, and so on, until the attempt succeeds.
/// Every failed attempt must return FP_STATUS_OUT_OF_MEMORY and leave the engine's contents unchanged.
fn failEachAllocation(failing: *testing.FailingAllocator, engine: *abi.Engine, context: anytype) !void {
    const before = snapshot(engine);
    var failures: usize = 0;
    while (true) : (failures += 1) {
        failing.fail_index = failing.alloc_index + failures;
        const result = try context.attempt(engine);
        failing.fail_index = never;
        if (result == ok) break;
        try testing.expectEqual(out_of_memory, result);
        try testing.expectEqual(before, snapshot(engine));
    }
    try testing.expect(failures > 0);
}

/// Answers requests of new documents until the input queue has no free slot, so the next answer must allocate.
fn fillInputs(engine: *abi.Engine) !void {
    const inner = nativeOf(engine);
    while (inner.inputs.buffer.len != inner.inputs.len) {
        try respond(engine, try load(engine, try createDocument(engine), "https://example.test/input"), "input");
    }
}

/// Reloads a spare document until only the event slots that the outstanding requests reserve are free.
/// A reload announces two events, so it drains one event first when exactly one slot beyond that floor is free.
fn fillEvents(engine: *abi.Engine, spare: abi.DocumentId) !void {
    const inner = nativeOf(engine);
    while (inner.events.buffer.len - inner.events.len > inner.requests.count()) {
        if (inner.events.buffer.len - inner.events.len == inner.requests.count() + 1) _ = try nextEvent(engine);
        _ = try load(engine, spare, "https://example.test/event");
    }
}

const CreateDocument = struct {
    out: abi.DocumentId = @fromBackingInt(0xD0C),
    fn attempt(self: *CreateDocument, engine: *abi.Engine) !u32 {
        const result = fp_document_create(engine, &self.out);
        if (result != ok) try testing.expectEqual(0xD0C, @backingInt(self.out));
        return result;
    }
};

const LoadDocument = struct {
    document: abi.DocumentId,
    out: abi.RequestId = @fromBackingInt(0x5E0),
    fn attempt(self: *LoadDocument, engine: *abi.Engine) !u32 {
        const before = try state(engine, self.document);
        const url = "https://example.test/allocation";
        const result = fp_document_load(engine, self.document, url, url.len, &self.out);
        if (result != ok) {
            try testing.expectEqual(0x5E0, @backingInt(self.out));
            try testing.expectEqual(before, try state(engine, self.document));
        }
        return result;
    }
};

const Answer = struct {
    request: abi.RequestId,
    kind: enum { response, rejection, cancellation },
    fn attempt(self: *Answer, engine: *abi.Engine) !u32 {
        return switch (self.kind) {
            .response => fp_request_respond(engine, &response(self.request, "allocation")),
            .rejection => fp_request_reject(engine, self.request, reject_unsupported_version),
            .cancellation => fp_request_cancel(engine, self.request),
        };
    }
};

const Step = struct {
    fn attempt(_: *Step, engine: *abi.Engine) !u32 {
        var outcome: abi.StepOutcome = undefined;
        fill(&outcome);
        const result = fp_engine_step(engine, std.math.maxInt(u32), &outcome, @sizeOf(abi.StepOutcome));
        if (result != ok) try expectFilled(&outcome);
        return result;
    }
};

test "Scenario allocation-failure: each allocating operation returns FP_STATUS_OUT_OF_MEMORY at every allocation and changes nothing" {
    // Fail every remap, so that each growth step is an allocation that the test can induce.
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    const gpa = failing.allocator();
    const engine_options = options(1024, 64);

    var handle: ?*abi.Engine = null;
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(out_of_memory, c_api.createEngine(gpa, &engine_options, &handle));
    try testing.expectEqual(null, handle);
    failing.fail_index = never;
    const engine = try createTracked(gpa, engine_options);

    var create: CreateDocument = .{};
    try failEachAllocation(&failing, engine, &create);
    const document = create.out;

    var load_document: LoadDocument = .{ .document = document };
    try failEachAllocation(&failing, engine, &load_document);
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));

    var respond_answer: Answer = .{ .request = load_document.out, .kind = .response };
    try failEachAllocation(&failing, engine, &respond_answer);

    const rejected = try createDocument(engine);
    var reject_answer: Answer = .{ .request = try load(engine, rejected, "https://example.test/rejected"), .kind = .rejection };
    try fillInputs(engine);
    try failEachAllocation(&failing, engine, &reject_answer);

    const cancelled = try createDocument(engine);
    var cancel_answer: Answer = .{ .request = try load(engine, cancelled, "https://example.test/cancelled"), .kind = .cancellation };
    try fillInputs(engine);
    try failEachAllocation(&failing, engine, &cancel_answer);

    const spare = try createDocument(engine);
    try fillEvents(engine, spare);
    var apply: Step = .{};
    try failEachAllocation(&failing, engine, &apply);
    try testing.expectEqual(abi.DocumentState.loaded, try state(engine, document));
    try testing.expectEqual(abi.DocumentState.failed, try state(engine, rejected));
    try testing.expectEqual(abi.DocumentState.failed, try state(engine, cancelled));

    const doomed = try createDocument(engine);
    const doomed_request = try load(engine, doomed, "https://example.test/doomed");
    try fillEvents(engine, spare);
    // The load reserved the cancellation event, so the destruction succeeds while every allocation fails.
    failing.fail_index = failing.alloc_index;
    try testing.expectEqual(ok, fp_document_destroy(engine, doomed));
    failing.fail_index = never;
    var last = try nextEvent(engine);
    while (true) {
        const event = try nextEvent(engine);
        if (event.kind == @backingInt(abi.EventKind.none)) break;
        last = event;
    }
    try testing.expectEqual(@backingInt(abi.EventKind.request_cancelled), last.kind);
    try testing.expectEqual(@as(?abi.DocumentId, doomed), last.document_id.get());
    try testing.expectEqual(@as(?abi.RequestId, doomed_request), last.request_id.get());
    try expectUnknownDocument(engine, doomed);

    try testing.expectEqual(ok, fp_engine_destroy(engine));
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

/// The allocation-failure scenario through the memory limit alone, as a C caller runs it.
/// With `recording` under the engine, a check after every call compares the engine's reported bytes with the bytes live in that allocator.
const LimitRun = struct {
    recording: ?*testing.FailingAllocator,
    engine: *abi.Engine = undefined,
    /// The scenario's documents, whose reported state a refused call leaves unchanged.
    documents: [3]abi.DocumentId = undefined,
    tracked: usize = 0,

    /// What a refused call leaves unchanged.
    const Observation = struct {
        allocated_bytes: u64,
        events_ready: u64,
        work_remaining: u32,
        documents: [3]abi.DocumentInfo,
        native: Snapshot,
    };

    /// Checks that the engine reports exactly the bytes live in the recording allocator.
    fn audit(run: *const LimitRun) !void {
        const recording = run.recording orelse return;
        try testing.expectEqual(@as(u64, recording.allocated_bytes - recording.freed_bytes), (try memory(run.engine)).allocated_bytes);
    }

    fn createEngine(run: *LimitRun, engine_options: abi.EngineOptions, out: *?*abi.Engine) u32 {
        if (run.recording) |recording| return c_api.createEngine(recording.allocator(), &engine_options, out);
        return fp_engine_create(&engine_options, out);
    }

    fn setLimit(run: *LimitRun, limit: u64) !void {
        try testing.expectEqual(ok, fp_engine_set_memory_limit(run.engine, limit));
        try run.audit();
    }

    /// Sets the limit to the allocated bytes that the engine reports.
    fn limitToAllocated(run: *LimitRun) !void {
        const allocated = (try memory(run.engine)).allocated_bytes;
        try run.audit();
        try run.setLimit(allocated);
    }

    fn newDocument(run: *LimitRun) !abi.DocumentId {
        const document = try createDocument(run.engine);
        try run.audit();
        return document;
    }

    fn issue(run: *LimitRun, document: abi.DocumentId, url: []const u8) !abi.RequestId {
        const request = try load(run.engine, document, url);
        try run.audit();
        return request;
    }

    fn expectState(run: *LimitRun, expected: abi.DocumentState, document: abi.DocumentId) !void {
        try testing.expectEqual(expected, try state(run.engine, document));
        try run.audit();
    }

    fn drainOne(run: *LimitRun) !abi.Event {
        const event = try nextEvent(run.engine);
        try run.audit();
        return event;
    }

    fn track(run: *LimitRun, document: abi.DocumentId) void {
        run.documents[run.tracked] = document;
        run.tracked += 1;
    }

    fn observe(run: *LimitRun) !Observation {
        var result: Observation = .{
            .allocated_bytes = (try memory(run.engine)).allocated_bytes,
            .events_ready = 0,
            .work_remaining = 0,
            .documents = std.mem.zeroes([3]abi.DocumentInfo),
            .native = snapshot(run.engine),
        };
        try run.audit();
        // A zero-budget step applies nothing and allocates nothing.
        const outcome = try step(run.engine, 0);
        try run.audit();
        result.events_ready = outcome.events_ready;
        result.work_remaining = outcome.work_remaining;
        for (run.documents[0..run.tracked], result.documents[0..run.tracked]) |document, *slot| {
            slot.* = try info(run.engine, document);
            try run.audit();
        }
        return result;
    }

    /// Sets the limit to the allocated bytes, then one byte higher, and so on, until `context.attempt` succeeds.
    /// Every earlier attempt must return FP_STATUS_OUT_OF_MEMORY and change nothing that the engine reports.
    /// The limit is unlimited again afterward.
    fn untilAllowed(run: *LimitRun, context: anytype) !void {
        const before = try run.observe();
        var extra: u64 = 0;
        while (true) : (extra += 1) {
            try run.setLimit(before.allocated_bytes + extra);
            const result = try context.attempt(run.engine);
            try run.audit();
            if (result == ok) break;
            try testing.expectEqual(out_of_memory, result);
            try testing.expectEqual(before, try run.observe());
        }
        try testing.expect(extra > 0);
        try run.setLimit(unlimited);
    }

    /// Rejects requests of new documents until a rejection at the limit fails, so the input queue is full.
    /// A rejection allocates only when the input queue must grow.
    fn fillInputs(run: *LimitRun) !void {
        while (true) {
            const request = try run.issue(try run.newDocument(), "https://example.test/input");
            try run.limitToAllocated();
            const result = fp_request_reject(run.engine, request, reject_unsupported_version);
            try run.audit();
            try run.setLimit(unlimited);
            if (result == out_of_memory) return;
            try testing.expectEqual(ok, result);
        }
    }

    /// Reloads `spare` with an empty URL at the limit and reports whether the reload succeeded.
    fn reloadAtLimit(run: *LimitRun, spare: abi.DocumentId) !bool {
        try run.limitToAllocated();
        var request: abi.RequestId = @fromBackingInt(0);
        const result = fp_document_load(run.engine, spare, null, 0, &request);
        try run.audit();
        try run.setLimit(unlimited);
        if (result == out_of_memory) return false;
        try testing.expectEqual(ok, result);
        return true;
    }

    /// Reloads `spare` until only the event slots that the outstanding requests reserve are free.
    /// After two unlimited loads, the request table and map have a free entry, so a reload with an empty URL allocates only when the event queue must grow.
    /// A reload announces two events, so a reload at the limit fails exactly when fewer than two slots beyond that floor are free.
    fn fillEvents(run: *LimitRun, spare: abi.DocumentId) !void {
        _ = try run.issue(spare, "");
        _ = try run.issue(spare, "");
        while (try run.reloadAtLimit(spare)) {}
        // One slot or none beyond the floor is free, and draining an event frees one more.
        try testing.expect((try run.drainOne()).kind != @backingInt(abi.EventKind.none));
        if (!try run.reloadAtLimit(spare)) {
            try testing.expect((try run.drainOne()).kind != @backingInt(abi.EventKind.none));
            try testing.expect(try run.reloadAtLimit(spare));
        }
    }
};

fn limitScenario(recording: ?*testing.FailingAllocator) !void {
    var run: LimitRun = .{ .recording = recording };
    var refused = options(1024, 64);
    refused.max_allocated_bytes = 0;
    var handle: ?*abi.Engine = null;
    try testing.expectEqual(out_of_memory, run.createEngine(refused, &handle));
    try testing.expectEqual(null, handle);
    if (recording) |live| try testing.expectEqual(0, live.allocations);
    try testing.expectEqual(ok, run.createEngine(options(1024, 64), &handle));
    run.engine = handle.?;
    try run.audit();

    var create: CreateDocument = .{};
    try run.untilAllowed(&create);
    const document = create.out;
    run.track(document);

    var load_document: LoadDocument = .{ .document = document };
    try run.untilAllowed(&load_document);
    try run.expectState(.loading, document);

    var respond_answer: Answer = .{ .request = load_document.out, .kind = .response };
    try run.untilAllowed(&respond_answer);

    const rejected = try run.newDocument();
    run.track(rejected);
    var reject_answer: Answer = .{ .request = try run.issue(rejected, "https://example.test/rejected"), .kind = .rejection };
    try run.fillInputs();
    try run.untilAllowed(&reject_answer);

    const cancelled = try run.newDocument();
    run.track(cancelled);
    var cancel_answer: Answer = .{ .request = try run.issue(cancelled, "https://example.test/cancelled"), .kind = .cancellation };
    try run.fillInputs();
    try run.untilAllowed(&cancel_answer);

    const spare = try run.newDocument();
    try run.fillEvents(spare);
    var apply: Step = .{};
    try run.untilAllowed(&apply);
    try run.expectState(.loaded, document);
    try run.expectState(.failed, rejected);
    try run.expectState(.failed, cancelled);

    const doomed = try run.newDocument();
    const doomed_request = try run.issue(doomed, "https://example.test/doomed");
    try run.fillEvents(spare);
    // The load reserved the cancellation event, so the destruction succeeds with the limit at the allocated bytes.
    try run.limitToAllocated();
    try testing.expectEqual(ok, fp_document_destroy(run.engine, doomed));
    try run.audit();
    try run.setLimit(unlimited);
    var last = try run.drainOne();
    while (true) {
        const event = try run.drainOne();
        if (event.kind == @backingInt(abi.EventKind.none)) break;
        last = event;
    }
    try testing.expectEqual(@backingInt(abi.EventKind.request_cancelled), last.kind);
    try testing.expectEqual(@as(?abi.DocumentId, doomed), last.document_id.get());
    try testing.expectEqual(@as(?abi.RequestId, doomed_request), last.request_id.get());
    try expectUnknownDocument(run.engine, doomed);
    try run.audit();

    try testing.expectEqual(ok, fp_engine_destroy(run.engine));
    if (recording) |live| try testing.expectEqual(live.allocated_bytes, live.freed_bytes);
}

test "Scenario allocation-failure: through the memory limit alone, each allocating operation returns FP_STATUS_OUT_OF_MEMORY until the limit admits it, and changes nothing" {
    try limitScenario(null);
}

test "FP-0081 case 2: across the allocation-failure scenario through the limit, fp_engine_get_memory reports the bytes live in a recording allocator after every call" {
    var recording: testing.FailingAllocator = .init(testing.allocator, .{});
    try limitScenario(&recording);
    try testing.expect(recording.allocations > 0);
}

test "Scenario null-required-pointer: a null required pointer returns FP_STATUS_INVALID_ARGUMENT and writes nothing" {
    try testing.expectEqual(invalid_argument, fp_query_capabilities(null, @sizeOf(abi.Capabilities)));
    var untouched: ?*abi.Engine = @ptrFromInt(0x1000);
    try testing.expectEqual(invalid_argument, fp_engine_create(null, &untouched));
    try testing.expectEqual(@as(?*abi.Engine, @ptrFromInt(0x1000)), untouched);
    try testing.expectEqual(invalid_argument, fp_engine_create(&default_options, null));

    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/null");
    try respond(engine, try load(engine, try createDocument(engine), "https://example.test/queued"), "queued");
    const before = snapshot(engine);

    var document_out: abi.DocumentId = @fromBackingInt(0xD0C);
    var request_out: abi.RequestId = @fromBackingInt(0x5E0);
    var document_info: abi.DocumentInfo = undefined;
    var outcome: abi.StepOutcome = undefined;
    var event: abi.Event = undefined;
    fill(&document_info);
    fill(&outcome);
    fill(&event);
    const answer = response(request, "null");
    const statuses = [_]u32{
        fp_engine_destroy(null),
        fp_document_create(null, &document_out),
        fp_document_destroy(null, document),
        fp_document_get(null, document, &document_info, @sizeOf(abi.DocumentInfo)),
        fp_document_load(null, document, "u", 1, &request_out),
        fp_request_respond(null, &answer),
        fp_request_reject(null, request, reject_unsupported_version),
        fp_request_cancel(null, request),
        fp_engine_step(null, 8, &outcome, @sizeOf(abi.StepOutcome)),
        fp_engine_next_event(null, &event, @sizeOf(abi.Event)),
        fp_document_create(engine, null),
        fp_document_get(engine, document, null, @sizeOf(abi.DocumentInfo)),
        fp_document_load(engine, document, null, 1, &request_out),
        fp_document_load(engine, document, "u", 1, null),
        fp_request_respond(engine, null),
        fp_request_respond(engine, &.{ .struct_size = @sizeOf(abi.Response), .version = abi.resource_request_version, .request_id = request, .body = null, .body_len = 1 }),
        fp_engine_step(engine, 8, null, @sizeOf(abi.StepOutcome)),
        fp_engine_next_event(engine, null, @sizeOf(abi.Event)),
    };
    for (statuses) |status| try testing.expectEqual(invalid_argument, status);

    try testing.expectEqual(0xD0C, @backingInt(document_out));
    try testing.expectEqual(0x5E0, @backingInt(request_out));
    try expectFilled(&document_info);
    try expectFilled(&outcome);
    try expectFilled(&event);
    try testing.expectEqual(before, snapshot(engine));
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    try respond(engine, request, "valid");
}

test "Scenario short-structure: a structure or output size below the declared size returns FP_STATUS_INVALID_ARGUMENT and writes nothing" {
    var short_options = default_options;
    short_options.struct_size = @sizeOf(abi.EngineOptions) - 1;
    var untouched: ?*abi.Engine = @ptrFromInt(0x1000);
    try testing.expectEqual(invalid_argument, fp_engine_create(&short_options, &untouched));
    try testing.expectEqual(@as(?*abi.Engine, @ptrFromInt(0x1000)), untouched);

    var capabilities: abi.Capabilities = undefined;
    fill(&capabilities);
    try testing.expectEqual(invalid_argument, fp_query_capabilities(&capabilities, @sizeOf(abi.Capabilities) - 1));
    try testing.expectEqual(invalid_argument, fp_query_capabilities(&capabilities, 0));
    try expectFilled(&capabilities);

    const engine = try createEngine(default_options);
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/short");
    const queued = try load(engine, try createDocument(engine), "https://example.test/short-queued");
    try respond(engine, queued, "queued");
    const before = snapshot(engine);

    var short_answer = response(request, "short");
    short_answer.struct_size = @sizeOf(abi.Response) - 1;
    try testing.expectEqual(invalid_argument, fp_request_respond(engine, &short_answer));

    var document_info: abi.DocumentInfo = undefined;
    var outcome: abi.StepOutcome = undefined;
    var event: abi.Event = undefined;
    fill(&document_info);
    fill(&outcome);
    fill(&event);
    try testing.expectEqual(invalid_argument, fp_document_get(engine, document, &document_info, @sizeOf(abi.DocumentInfo) - 1));
    try testing.expectEqual(invalid_argument, fp_engine_step(engine, 8, &outcome, @sizeOf(abi.StepOutcome) - 1));
    try testing.expectEqual(invalid_argument, fp_engine_next_event(engine, &event, @sizeOf(abi.Event) - 1));
    try testing.expectEqual(invalid_argument, fp_engine_next_event(engine, &event, 0));
    try expectFilled(&document_info);
    try expectFilled(&outcome);
    try expectFilled(&event);

    try testing.expectEqual(before, snapshot(engine));
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, document));
    try respond(engine, request, "full");
}

test "Scenario response-body-bound: a body beyond max_response_body_bytes returns FP_STATUS_LIMIT_EXCEEDED and the request stays live" {
    const engine = try createEngine(options(4, 16));
    defer destroyEngine(engine);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/body");
    const before = snapshot(engine);

    const oversized = response(request, "seventeen bytes!!");
    try testing.expectEqual(17, oversized.body_len);
    try testing.expectEqual(limit_exceeded, fp_request_respond(engine, &oversized));
    try testing.expectEqual(before, snapshot(engine));

    try respond(engine, request, "sixteen bytes!!!");
    try testing.expectEqual(1, (try step(engine, 8)).applied);
    const loaded = try info(engine, document);
    try testing.expectEqual(@backingInt(abi.DocumentState.loaded), loaded.state);
    try testing.expectEqualStrings("sixteen bytes!!!", loaded.body.?[0..loaded.body_len]);
}

test "Scenario load-bound: a load beyond max_outstanding_requests returns FP_STATUS_LIMIT_EXCEEDED, and a reload stays within the bound" {
    const engine = try createEngine(options(2, 16));
    defer destroyEngine(engine);
    const a = try createDocument(engine);
    const b = try createDocument(engine);
    const c = try createDocument(engine);
    _ = try load(engine, a, "https://example.test/a");
    const b_request = try load(engine, b, "https://example.test/b");
    const before = snapshot(engine);

    var out: abi.RequestId = @fromBackingInt(0x5E0);
    const url = "https://example.test/c";
    try testing.expectEqual(limit_exceeded, fp_document_load(engine, c, url, url.len, &out));
    try testing.expectEqual(0x5E0, @backingInt(out));
    try testing.expectEqual(before, snapshot(engine));
    try testing.expectEqual(abi.DocumentState.empty, try state(engine, c));

    _ = try load(engine, a, "https://example.test/a-again");
    try respond(engine, b_request, "b");
    try testing.expectEqual(1, (try step(engine, 8)).applied);
    _ = try load(engine, c, url);
    try testing.expectEqual(abi.DocumentState.loading, try state(engine, c));
}

/// Host code that fails after it drains an event, as a foreign exception or panic interrupts a host.
fn failingHost(engine: *abi.Engine) !void {
    _ = try nextEvent(engine);
    return error.HostFailure;
}

test "Scenario foreign-unwind: a host failure between calls never crosses the C ABI and leaves the engine usable" {
    // Every generated function returns a plain integer, so no error union or unwinding can cross the boundary.
    inline for (@typeInfo(abi.functions).@"struct".decl_names) |name| {
        const info_of = @typeInfo(@field(abi.functions, name)).@"fn";
        try testing.expectEqual(u32, info_of.return_type.?);
    }

    const engine = try createTracked(testing.allocator, default_options);
    const document = try createDocument(engine);
    const request = try load(engine, document, "https://example.test/host");
    try testing.expectError(error.HostFailure, failingHost(engine));

    try respond(engine, request, "after");
    try testing.expectEqual(1, (try step(engine, 8)).applied);
    try testing.expectEqual(abi.DocumentState.loaded, try state(engine, document));
    try testing.expectEqual(ok, fp_engine_destroy(engine));
}
