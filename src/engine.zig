//! The native Zig engine API: documents, bounded host requests, queued host input, and events.
//!
//! An engine owns its documents, host requests, queued host input, and events.
//! Host operations that answer a request only queue input.
//! `Engine.step` applies queued input in arrival order, up to a caller-supplied budget.
//! The engine never calls host code, so no host callback can reenter it.
//!
//! A step budget is an engine scheduling boundary only.
//! It creates no JavaScript task boundary.
//!
//! Each operation reserves its storage, including event capacity, before it changes any state.
//! An allocation failure therefore leaves every engine, document, and request unchanged.
//! An operation grows at most one container in place, as its last reservation.
//! It reserves every other growth in new storage that it installs only after every reservation succeeded.
//! A failed operation releases that new storage, so it also leaves the engine's allocated bytes unchanged.
//! A load also reserves one event slot for the eventual cancellation of its request.
//! After every operation, the event queue therefore has at least one unused slot for each outstanding request.
//! Destroying a document uses that slot, so it never allocates.
//! A step that applies a host cancellation announces two events but ends one request, so it can still need storage.
//!
//! Each engine counts the bytes of its live allocations, including its own record, and refuses an allocation beyond its limit.
//! A refused allocation is an allocation failure.
//!
//! Internal generational handles stay inside this module.
//! Callers identify documents and requests by opaque process-wide identifiers.

const std = @import("std");
const handles = @import("handles.zig");
const MemoryBudget = @import("memory_budget.zig").MemoryBudget;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const testing = std.testing;

/// An opaque document identifier.
/// It is nonzero, unique within the process, and never reused.
pub const DocumentId = enum(u64) { _ };

/// An opaque request identifier.
/// It is nonzero, unique within the process, and never reused.
/// Document and request identifiers come from one sequence, so they never coincide.
pub const RequestId = enum(u64) { _ };

pub const DocumentState = enum(u32) {
    /// No load has started.
    empty = 1,
    /// A request for the document's resource is outstanding.
    loading = 2,
    /// A step applied a response, and the document holds its body.
    loaded = 3,
    /// A step applied a rejection or a host cancellation.
    failed = 4,
};

pub const RequestKind = enum(u32) {
    /// A request for the bytes of a document's resource.
    resource = 1,
};

/// The only version of the `resource` request kind.
pub const resource_request_version: u32 = 1;

pub const RejectReason = enum(u32) {
    /// The host does not implement the request's version.
    unsupported_version = 1,
};

/// No timer exists yet, so the next deadline is always `none`.
pub const Deadline = enum { none };

pub const Options = struct {
    /// The maximum number of requests that are outstanding at once.
    max_outstanding_requests: u32,
    /// The maximum size of one response body in bytes.
    max_response_body_bytes: usize,
    /// The most bytes that the engine's allocations may hold at once, including the engine record.
    /// `std.math.maxInt(u64)` permits every allocation that the backing allocator grants.
    max_allocated_bytes: u64 = std.math.maxInt(u64),
};

/// The engine's allocated bytes and its limit.
pub const Memory = struct {
    /// The bytes that the engine's live allocations hold.
    allocated_bytes: u64,
    /// The current limit.
    max_allocated_bytes: u64,
};

/// Announces that a request was issued or cancelled.
pub const RequestNotice = struct {
    document: DocumentId,
    request: RequestId,
    kind: RequestKind,
    version: u32,
    /// For an issued request that is still live when the host drains the event, this is the request's URL.
    /// The bytes stay readable until the request ends.
    /// Otherwise it is null.
    url: ?[]const u8,
};

/// Announces a document state change and the request whose issuance or ending caused it.
pub const StateChange = struct {
    document: DocumentId,
    state: DocumentState,
    request: RequestId,
    kind: RequestKind,
    version: u32,
    /// The host's reason when an applied rejection failed the document, otherwise null.
    reject_reason: ?RejectReason,
};

pub const Event = union(enum) {
    request_issued: RequestNotice,
    request_cancelled: RequestNotice,
    document_state_changed: StateChange,
};

pub const StepOutcome = struct {
    /// The number of queued inputs that the step applied.
    applied: usize,
    /// Whether queued input remains after the step.
    work_remaining: bool,
    /// The number of events that are ready to drain.
    events_ready: usize,
    next_deadline: Deadline,
};

pub const DocumentView = struct {
    state: DocumentState,
    /// The loaded body, or empty in every other state.
    /// The bytes stay readable until the document's next load or its destruction.
    body: []const u8,
};

pub const ThreadError = error{WrongThread};
/// `IdentifiersExhausted` reports that the process-wide owner identity sequence ran out.
pub const CreateError = error{ OutOfMemory, IdentifiersExhausted };
pub const LookupError = error{ WrongThread, UnknownId };
/// `LimitExceeded` reports that the document table ran out of handles.
pub const CreateDocumentError = error{ WrongThread, OutOfMemory, LimitExceeded, IdentifiersExhausted };
pub const DestroyDocumentError = error{ WrongThread, UnknownId };
/// `LimitExceeded` reports the outstanding request bound or request table exhaustion.
pub const LoadError = error{ WrongThread, UnknownId, LimitExceeded, OutOfMemory, IdentifiersExhausted };
/// `InvalidState` reports that the request already has a queued answer.
pub const AnswerError = error{ WrongThread, UnknownId, InvalidState, OutOfMemory };
/// `LimitExceeded` reports a body beyond the size bound.
pub const RespondError = AnswerError || error{ UnsupportedVersion, LimitExceeded };
pub const StepError = error{ WrongThread, OutOfMemory };
/// Every error that an engine operation returns.
pub const Error = CreateError || CreateDocumentError || DestroyDocumentError || LoadError || RespondError || StepError;

/// Issues document and request identifiers for every engine in the process.
var identifier_source: handles.OwnerIdSource = .init(1);

fn issueIdentifier() error{IdentifiersExhausted}!u64 {
    const identity = identifier_source.issue() catch return error.IdentifiersExhausted;
    return @backingInt(identity);
}

const no_bytes: []u8 = &.{};

const Document = struct {
    id: DocumentId,
    state: DocumentState,
    /// The outstanding request while the document is loading.
    request: ?RequestTable.Handle,
    /// The owned body of a loaded document, otherwise empty.
    body: []u8,
};

const Request = struct {
    id: RequestId,
    document: DocumentId,
    kind: RequestKind,
    version: u32,
    /// An owned copy of the caller's URL bytes.
    url: []u8,
    /// Whether an answer for this request is in the input queue.
    answered: bool,
};

const DocumentTable = handles.Table(Document, .{});
const RequestTable = handles.Table(Request, .{});

const Answer = union(enum) {
    /// An owned copy of the response body.
    response: []u8,
    rejection: RejectReason,
    cancellation,
};

/// One queued host answer. Ending a request removes its queued answer, so `request` is always live.
const Input = struct {
    request: RequestTable.Handle,
    answer: Answer,
};

fn freeAnswer(gpa: Allocator, answer: Answer) void {
    switch (answer) {
        .response => |bytes| gpa.free(bytes),
        .rejection, .cancellation => {},
    }
}

/// The number of events that applying `answer` announces.
fn announcementsFor(answer: Answer) usize {
    return switch (answer) {
        .response, .rejection => 1,
        .cancellation => 2,
    };
}

/// Reserves room for `unused` more items of `deque` in new storage, without changing `deque`.
/// The result is empty when `deque` already has the room.
/// `installDeque` moves the items into the result, and `deinit` on the result instead releases it.
fn reserveDeque(comptime T: type, gpa: Allocator, deque: *const std.Deque(T), unused: usize) Allocator.Error!std.Deque(T) {
    const needed = std.math.add(usize, deque.len, unused) catch return error.OutOfMemory;
    if (deque.buffer.len >= needed) return .empty;
    return .initCapacity(gpa, std.ArrayList(T).growCapacity(needed));
}

/// Moves the items of `deque` into the storage that `reserveDeque` returned. It never allocates.
fn installDeque(comptime T: type, gpa: Allocator, deque: *std.Deque(T), reserved: std.Deque(T)) void {
    if (reserved.buffer.len == 0) return;
    var grown = reserved;
    var items = deque.iterator();
    while (items.next()) |item| grown.pushBackAssumeCapacity(item);
    deque.deinit(gpa);
    deque.* = grown;
}

/// Reserves room for `unused` more entries of `map` in a new map, without changing `map`.
/// The result is empty when `map` already has the room.
/// `installMap` moves the entries into the result, and `deinit` on the result instead releases it.
fn reserveMap(gpa: Allocator, map: anytype, unused: u32) Allocator.Error!@TypeOf(map.*) {
    // A map grows only when `unused` exceeds its `available` count, as its own `ensureUnusedCapacity` decides.
    if (map.available >= unused) return .empty;
    var reserved: @TypeOf(map.*) = .empty;
    try reserved.ensureTotalCapacity(gpa, std.math.add(u32, map.count(), unused) catch return error.OutOfMemory);
    return reserved;
}

/// Moves the entries of `map` into the map that `reserveMap` returned. It never allocates.
fn installMap(gpa: Allocator, map: anytype, reserved: @TypeOf(map.*)) void {
    if (reserved.capacity() == 0) return;
    var grown = reserved;
    var entries = map.iterator();
    while (entries.next()) |entry| grown.putAssumeCapacityNoClobber(entry.key_ptr.*, entry.value_ptr.*);
    map.deinit(gpa);
    map.* = grown;
}

/// A single-thread engine.
/// The thread that creates an engine owns it, and every call from another thread returns `error.WrongThread`.
/// The host must destroy an engine before the thread that created it exits, because the system can reuse the identifier of an exited thread.
pub const Engine = struct {
    /// Counts every allocation of the engine against its limit.
    /// It holds the current limit, which `setMemoryLimit` replaces, so `options.max_allocated_bytes` is only the initial limit.
    budget: MemoryBudget,
    /// The allocator of `budget`.
    gpa: Allocator,
    options: Options,
    thread: std.Thread.Id,
    owner: handles.OwnerId,
    documents: DocumentTable,
    requests: RequestTable,
    document_ids: DocumentIds,
    request_ids: RequestIds,
    inputs: std.Deque(Input),
    events: std.Deque(Event),

    const DocumentIds = std.AutoHashMapUnmanaged(DocumentId, DocumentTable.Handle);
    const RequestIds = std.AutoHashMapUnmanaged(RequestId, RequestTable.Handle);

    /// Issues fresh owner identities for the engine and for each handle table.
    /// The engine allocates from `backing` through its budget, and the engine record counts against `options.max_allocated_bytes`.
    /// `backing` must outlive the engine.
    pub fn create(backing: Allocator, options: Options) CreateError!*Engine {
        const owner = handles.issueEngineOwnerId() catch return error.IdentifiersExhausted;
        const documents_owner = handles.issueEngineOwnerId() catch return error.IdentifiersExhausted;
        const requests_owner = handles.issueEngineOwnerId() catch return error.IdentifiersExhausted;
        // The record holds the budget, so the budget counts the record before it moves into it.
        var budget: MemoryBudget = .init(backing, options.max_allocated_bytes);
        const engine = try budget.allocator().create(Engine);
        engine.* = .{
            .budget = budget,
            .gpa = undefined,
            .options = options,
            .thread = std.Thread.getCurrentId(),
            .owner = owner,
            .documents = .init(documents_owner),
            .requests = .init(requests_owner),
            .document_ids = .empty,
            .request_ids = .empty,
            .inputs = .empty,
            .events = .empty,
        };
        engine.gpa = engine.budget.allocator();
        return engine;
    }

    /// Releases the engine and everything it owns.
    /// That includes documents, outstanding requests, queued answers, and undrained events.
    /// Afterward, nothing that the engine allocated remains.
    pub fn destroy(engine: *Engine) ThreadError!void {
        try engine.checkThread();
        const gpa = engine.gpa;
        var inputs = engine.inputs.iterator();
        while (inputs.next()) |input| freeAnswer(gpa, input.answer);
        var documents = engine.documents.iterator();
        while (documents.next()) |entry| gpa.free(entry.value.body);
        var requests = engine.requests.iterator();
        while (requests.next()) |entry| gpa.free(entry.value.url);
        engine.inputs.deinit(gpa);
        engine.events.deinit(gpa);
        engine.document_ids.deinit(gpa);
        engine.request_ids.deinit(gpa);
        engine.documents.deinit(gpa);
        engine.requests.deinit(gpa);
        // The record holds the budget, so a copy of the budget releases the record.
        var budget = engine.budget;
        budget.allocator().destroy(engine);
        assert(budget.allocated_bytes == 0);
    }

    pub fn checkThread(engine: *const Engine) ThreadError!void {
        if (std.Thread.getCurrentId() != engine.thread) return error.WrongThread;
    }

    /// Reports the engine's allocated bytes and its limit. It allocates nothing.
    pub fn memory(engine: *const Engine) ThreadError!Memory {
        try engine.checkThread();
        return .{ .allocated_bytes = engine.budget.allocated_bytes, .max_allocated_bytes = engine.budget.max_allocated_bytes };
    }

    /// Replaces the limit. It allocates nothing.
    /// A limit below the allocated bytes is valid, and it refuses every later growth until enough bytes are released.
    pub fn setMemoryLimit(engine: *Engine, max_allocated_bytes: u64) ThreadError!void {
        try engine.checkThread();
        engine.budget.max_allocated_bytes = max_allocated_bytes;
    }

    /// Creates an `empty` document.
    pub fn createDocument(engine: *Engine) CreateDocumentError!DocumentId {
        try engine.checkThread();
        const gpa = engine.gpa;
        var document_ids = try reserveMap(gpa, &engine.document_ids, 1);
        errdefer document_ids.deinit(gpa);
        const id: DocumentId = @fromBackingInt(try issueIdentifier());
        const handle = engine.documents.insert(gpa, .{ .id = id, .state = .empty, .request = null, .body = no_bytes }) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.HandleSpaceExhausted => error.LimitExceeded,
        };

        // Every reservation succeeded, so nothing below can fail.
        installMap(gpa, &engine.document_ids, document_ids);
        engine.document_ids.putAssumeCapacityNoClobber(id, handle);
        return id;
    }

    /// Releases the document and its body.
    /// An outstanding request is cancelled, its queued answer is discarded, and the cancellation is announced.
    /// It never allocates, because the load that issued the request reserved the event slot of its cancellation.
    pub fn destroyDocument(engine: *Engine, id: DocumentId) DestroyDocumentError!void {
        try engine.checkThread();
        const handle = engine.document_ids.get(id) orelse return error.UnknownId;
        const record = engine.documents.get(handle) catch unreachable;
        if (record.request) |request| engine.withdrawRequest(request);
        _ = engine.documents.remove(handle) catch unreachable;
        const removed = engine.document_ids.remove(id);
        assert(removed);
        engine.gpa.free(record.body);
    }

    pub fn document(engine: *Engine, id: DocumentId) LookupError!DocumentView {
        try engine.checkThread();
        const handle = engine.document_ids.get(id) orelse return error.UnknownId;
        const record = engine.documents.get(handle) catch unreachable;
        return .{ .state = record.state, .body = record.body };
    }

    /// Issues a version 1 `resource` request for a copy of `url` and moves the document to `loading`.
    /// A load while the document is loading cancels the earlier request and announces that cancellation.
    /// A load discards the body of a loaded document.
    /// Only a load that adds an outstanding request counts against the request bound.
    /// A load reserves one event slot for the eventual cancellation of the request it issues, so `destroyDocument` never allocates.
    pub fn load(engine: *Engine, id: DocumentId, url: []const u8) LoadError!RequestId {
        try engine.checkThread();
        const gpa = engine.gpa;
        const document_handle = engine.document_ids.get(id) orelse return error.UnknownId;
        const previous = (engine.documents.get(document_handle) catch unreachable).request;
        if (previous == null and engine.requests.count() >= engine.options.max_outstanding_requests) {
            return error.LimitExceeded;
        }
        // A load announces at most two events: a cancellation or a state change, and an issuance.
        // Afterward, each outstanding request, including the one that the load issues, keeps one reserved slot.
        // A reload ends the request that it replaces, so it adds no outstanding request.
        const added: usize = @intFromBool(previous == null);
        var events = try reserveDeque(Event, gpa, &engine.events, engine.requests.count() + added + 2);
        errdefer events.deinit(gpa);
        var request_ids = try reserveMap(gpa, &engine.request_ids, 1);
        errdefer request_ids.deinit(gpa);
        const url_copy = try gpa.dupe(u8, url);
        errdefer gpa.free(url_copy);
        const request_id: RequestId = @fromBackingInt(try issueIdentifier());
        const request_handle = engine.requests.insert(gpa, .{
            .id = request_id,
            .document = id,
            .kind = .resource,
            .version = resource_request_version,
            .url = url_copy,
            .answered = false,
        }) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.HandleSpaceExhausted => error.LimitExceeded,
        };

        // Every reservation succeeded, so nothing below can fail.
        installDeque(Event, gpa, &engine.events, events);
        installMap(gpa, &engine.request_ids, request_ids);
        engine.request_ids.putAssumeCapacityNoClobber(request_id, request_handle);
        if (previous) |request| engine.withdrawRequest(request);
        engine.events.pushBackAssumeCapacity(.{ .request_issued = .{
            .document = id,
            .request = request_id,
            .kind = .resource,
            .version = resource_request_version,
            .url = null,
        } });
        const record = engine.documents.getPtr(document_handle) catch unreachable;
        gpa.free(record.body);
        record.body = no_bytes;
        record.request = request_handle;
        if (record.state != .loading) {
            record.state = .loading;
            engine.events.pushBackAssumeCapacity(.{ .document_state_changed = .{
                .document = id,
                .state = .loading,
                .request = request_id,
                .kind = .resource,
                .version = resource_request_version,
                .reject_reason = null,
            } });
        }
        return request_id;
    }

    /// Queues a response with a copy of `body`.
    /// The caller's buffer is borrowed only for this call.
    /// A version that differs from the request's version, or a body beyond the size bound, leaves the request live.
    pub fn respond(engine: *Engine, request: RequestId, version: u32, body: []const u8) RespondError!void {
        try engine.checkThread();
        const handle = try engine.unansweredRequest(request);
        if (version != (engine.requests.get(handle) catch unreachable).version) return error.UnsupportedVersion;
        if (body.len > engine.options.max_response_body_bytes) return error.LimitExceeded;
        const body_copy = try engine.gpa.dupe(u8, body);
        errdefer engine.gpa.free(body_copy);
        // The queue grows in place last, so a failed growth leaves only the copy to release.
        try engine.inputs.ensureUnusedCapacity(engine.gpa, 1);
        engine.queueAnswer(handle, .{ .response = body_copy });
    }

    /// Queues a rejection with the host's reason.
    pub fn reject(engine: *Engine, request: RequestId, reason: RejectReason) AnswerError!void {
        try engine.checkThread();
        const handle = try engine.unansweredRequest(request);
        try engine.inputs.ensureUnusedCapacity(engine.gpa, 1);
        engine.queueAnswer(handle, .{ .rejection = reason });
    }

    /// Queues the host's withdrawal of a request.
    pub fn cancel(engine: *Engine, request: RequestId) AnswerError!void {
        try engine.checkThread();
        const handle = try engine.unansweredRequest(request);
        try engine.inputs.ensureUnusedCapacity(engine.gpa, 1);
        engine.queueAnswer(handle, .cancellation);
    }

    /// Applies up to `budget` queued inputs in arrival order.
    /// The budget is an engine scheduling boundary only; it creates no JavaScript task boundary.
    pub fn step(engine: *Engine, budget: usize) StepError!StepOutcome {
        try engine.checkThread();
        const applied = @min(budget, engine.inputs.len);
        var announcements: usize = 0;
        for (0..applied) |position| announcements += announcementsFor(engine.inputs.at(position).answer);
        // Each applied answer ends its request, whose reserved slot covers one announcement.
        // The other outstanding requests keep their reserved slots, so only a host cancellation's second announcement needs storage.
        try engine.events.ensureUnusedCapacity(engine.gpa, engine.requests.count() - applied + announcements);
        for (0..applied) |_| engine.applyInput(engine.inputs.popFront().?);
        return .{
            .applied = applied,
            .work_remaining = engine.inputs.len != 0,
            .events_ready = engine.events.len,
            .next_deadline = .none,
        };
    }

    /// Removes and returns the oldest event, or returns null when no event is ready.
    pub fn nextEvent(engine: *Engine) ThreadError!?Event {
        try engine.checkThread();
        var event = engine.events.popFront() orelse return null;
        switch (event) {
            .request_issued => |*notice| notice.url = engine.liveUrl(notice.request),
            .request_cancelled, .document_state_changed => {},
        }
        return event;
    }

    fn unansweredRequest(engine: *Engine, id: RequestId) error{ UnknownId, InvalidState }!RequestTable.Handle {
        const handle = engine.request_ids.get(id) orelse return error.UnknownId;
        if ((engine.requests.get(handle) catch unreachable).answered) return error.InvalidState;
        return handle;
    }

    /// Requires one reserved input slot.
    fn queueAnswer(engine: *Engine, handle: RequestTable.Handle, answer: Answer) void {
        (engine.requests.getPtr(handle) catch unreachable).answered = true;
        engine.inputs.pushBackAssumeCapacity(.{ .request = handle, .answer = answer });
    }

    fn liveUrl(engine: *Engine, id: RequestId) ?[]const u8 {
        const handle = engine.request_ids.get(id) orelse return null;
        return (engine.requests.get(handle) catch unreachable).url;
    }

    /// Ends a request and frees its URL. The returned copy's `url` is no longer valid.
    fn releaseRequest(engine: *Engine, handle: RequestTable.Handle) Request {
        const ended = engine.requests.remove(handle) catch unreachable;
        const removed = engine.request_ids.remove(ended.id);
        assert(removed);
        engine.gpa.free(ended.url);
        return ended;
    }

    /// Cancels a request for the engine, discards its queued answer, and announces the cancellation.
    /// Uses the event slot that the load of the request reserved.
    fn withdrawRequest(engine: *Engine, handle: RequestTable.Handle) void {
        if ((engine.requests.get(handle) catch unreachable).answered) engine.discardQueuedAnswer(handle);
        const ended = engine.releaseRequest(handle);
        engine.events.pushBackAssumeCapacity(.{ .request_cancelled = .{
            .document = ended.document,
            .request = ended.id,
            .kind = ended.kind,
            .version = ended.version,
            .url = null,
        } });
    }

    /// Removes the queued answer for `handle` and keeps the order of the other inputs.
    fn discardQueuedAnswer(engine: *Engine, handle: RequestTable.Handle) void {
        var kept: usize = 0;
        for (0..engine.inputs.len) |position| {
            const input = engine.inputs.at(position);
            if (std.meta.eql(input.request, handle)) {
                freeAnswer(engine.gpa, input.answer);
            } else {
                engine.inputs.atPtr(kept).* = input;
                kept += 1;
            }
        }
        assert(kept + 1 == engine.inputs.len);
        engine.inputs.len = kept;
    }

    /// Applies one answer to its document. Requires reserved event slots for its announcements.
    fn applyInput(engine: *Engine, input: Input) void {
        const ended = engine.releaseRequest(input.request);
        const document_handle = engine.document_ids.get(ended.document).?;
        const record = engine.documents.getPtr(document_handle) catch unreachable;
        assert(record.state == .loading);
        assert(std.meta.eql(record.request.?, input.request));
        record.request = null;
        var reject_reason: ?RejectReason = null;
        switch (input.answer) {
            .response => |bytes| {
                assert(record.body.len == 0);
                record.body = bytes;
                record.state = .loaded;
            },
            .rejection => |reason| {
                reject_reason = reason;
                record.state = .failed;
            },
            .cancellation => {
                engine.events.pushBackAssumeCapacity(.{ .request_cancelled = .{
                    .document = ended.document,
                    .request = ended.id,
                    .kind = ended.kind,
                    .version = ended.version,
                    .url = null,
                } });
                record.state = .failed;
            },
        }
        engine.events.pushBackAssumeCapacity(.{ .document_state_changed = .{
            .document = ended.document,
            .state = record.state,
            .request = ended.id,
            .kind = ended.kind,
            .version = ended.version,
            .reject_reason = reject_reason,
        } });
    }
};

const test_options: Options = .{ .max_outstanding_requests = 8, .max_response_body_bytes = 1024 };

fn issued(document: DocumentId, request: RequestId, url: ?[]const u8) Event {
    return .{ .request_issued = .{ .document = document, .request = request, .kind = .resource, .version = 1, .url = url } };
}

fn cancelled(document: DocumentId, request: RequestId) Event {
    return .{ .request_cancelled = .{ .document = document, .request = request, .kind = .resource, .version = 1, .url = null } };
}

fn changed(document: DocumentId, request: RequestId, state: DocumentState, reason: ?RejectReason) Event {
    return .{ .document_state_changed = .{
        .document = document,
        .state = state,
        .request = request,
        .kind = .resource,
        .version = 1,
        .reject_reason = reason,
    } };
}

fn expectNextEvent(engine: *Engine, expected: Event) !void {
    try testing.expectEqualDeep(@as(?Event, expected), try engine.nextEvent());
}

fn expectNoEvent(engine: *Engine) !void {
    try testing.expect((try engine.nextEvent()) == null);
}

fn expectState(engine: *Engine, document: DocumentId, state: DocumentState) !void {
    try testing.expectEqual(state, (try engine.document(document)).state);
}

/// Test-only digest of every document, request, queued input, and event in an engine.
fn fingerprint(engine: *Engine) u64 {
    var hasher: std.hash.Wyhash = .init(0);
    const hash = std.hash.autoHashStrat;
    hash(&hasher, engine.documents.count(), .Deep);
    var documents = engine.documents.iterator();
    while (documents.next()) |entry| {
        hash(&hasher, entry.handle, .Deep);
        hash(&hasher, entry.value.*, .Deep);
    }
    hash(&hasher, engine.requests.count(), .Deep);
    var requests = engine.requests.iterator();
    while (requests.next()) |entry| {
        hash(&hasher, entry.handle, .Deep);
        hash(&hasher, entry.value.*, .Deep);
    }
    hash(&hasher, engine.document_ids.count(), .Deep);
    hash(&hasher, engine.request_ids.count(), .Deep);
    hash(&hasher, engine.inputs.len, .Deep);
    var inputs = engine.inputs.iterator();
    while (inputs.next()) |input| hash(&hasher, input, .Deep);
    hash(&hasher, engine.events.len, .Deep);
    var events = engine.events.iterator();
    while (events.next()) |event| hash(&hasher, event, .Deep);
    return hasher.final();
}

fn freeEventSlots(engine: *const Engine) usize {
    return engine.events.buffer.len - engine.events.len;
}

test "FP-0006 case 1: the Zig API creates and destroys an engine and a document, and a destroyed document is unknown" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    try testing.expect(@backingInt(document) != 0);
    const view = try engine.document(document);
    try testing.expectEqual(DocumentState.empty, view.state);
    try testing.expectEqual(0, view.body.len);

    try engine.destroyDocument(document);
    try testing.expectError(error.UnknownId, engine.document(document));
    try testing.expectError(error.UnknownId, engine.destroyDocument(document));
    try testing.expectError(error.UnknownId, engine.load(document, "https://example.test/"));
    try testing.expectError(error.UnknownId, engine.document(@fromBackingInt(0)));
    try expectNoEvent(engine);

    const next = try engine.createDocument();
    try testing.expect(next != document);
    try expectState(engine, next, .empty);
}

test "FP-0006 case 2: two engines and every table they create carry pairwise distinct owner identities" {
    const a = try Engine.create(testing.allocator, test_options);
    defer a.destroy() catch unreachable;
    const b = try Engine.create(testing.allocator, test_options);
    defer b.destroy() catch unreachable;

    const owners = [_]handles.OwnerId{ a.owner, a.documents.owner, a.requests.owner, b.owner, b.documents.owner, b.requests.owner };
    for (owners, 0..) |owner, index| {
        try testing.expect(@backingInt(owner) != 0);
        for (owners[index + 1 ..]) |other| try testing.expect(owner != other);
    }

    for ([_]*Engine{ a, b }) |engine| {
        const document = try engine.createDocument();
        try testing.expectEqual(engine.documents.owner, engine.document_ids.get(document).?.owner);
        const request = try engine.load(document, "https://example.test/owners");
        try testing.expectEqual(engine.requests.owner, engine.request_ids.get(request).?.owner);
    }
}

test "FP-0006 case 3: a load announces a version 1 resource request whose URL stays readable until the request ends" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    var source = "https://example.test/case-3".*;
    const request = try engine.load(document, &source);
    try testing.expect(@backingInt(request) != 0);
    try testing.expect(@backingInt(request) != @backingInt(document));
    // The engine owns a copy, so the caller's buffer is borrowed only for the call.
    @memset(&source, 'x');

    const event = (try engine.nextEvent()).?;
    try testing.expectEqual(std.meta.Tag(Event).request_issued, std.meta.activeTag(event));
    const notice = event.request_issued;
    try testing.expectEqual(document, notice.document);
    try testing.expectEqual(request, notice.request);
    try testing.expectEqual(RequestKind.resource, notice.kind);
    try testing.expectEqual(1, notice.version);
    const url = notice.url.?;
    try testing.expectEqualStrings("https://example.test/case-3", url);
    try expectNextEvent(engine, changed(document, request, .loading, null));

    // Table growth, other requests, and a queued response leave the URL bytes readable.
    for (0..6) |_| {
        const other = try engine.createDocument();
        _ = try engine.load(other, "https://example.test/other");
    }
    try engine.respond(request, 1, "body");
    try testing.expectEqualStrings("https://example.test/case-3", url);

    const outcome = try engine.step(1);
    try testing.expectEqual(1, outcome.applied);
    try expectState(engine, document, .loaded);
    try testing.expectError(error.UnknownId, engine.respond(request, 1, "body"));
}

test "FP-0006 case 4: a response and a step load exactly that body and end the request" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-4");
    var body = "<p>case 4</p>".*;
    try engine.respond(request, 1, &body);
    // The engine copied the body during the call.
    @memset(&body, 0);

    const outcome = try engine.step(1);
    try testing.expectEqual(1, outcome.applied);
    try testing.expect(!outcome.work_remaining);
    try testing.expectEqual(3, outcome.events_ready);
    try testing.expectEqual(Deadline.none, outcome.next_deadline);

    const view = try engine.document(document);
    try testing.expectEqual(DocumentState.loaded, view.state);
    try testing.expectEqualStrings("<p>case 4</p>", view.body);

    try testing.expectError(error.UnknownId, engine.respond(request, 1, "again"));
    try testing.expectError(error.UnknownId, engine.reject(request, .unsupported_version));
    try testing.expectError(error.UnknownId, engine.cancel(request));

    try expectNextEvent(engine, issued(document, request, null));
    try expectNextEvent(engine, changed(document, request, .loading, null));
    try expectNextEvent(engine, changed(document, request, .loaded, null));
    try expectNoEvent(engine);
}

test "FP-0006 case 5: a queued response leaves the document loading until a step applies it" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-5");
    try engine.respond(request, 1, "queued");

    const view = try engine.document(document);
    try testing.expectEqual(DocumentState.loading, view.state);
    try testing.expectEqual(0, view.body.len);
    try expectNextEvent(engine, issued(document, request, "https://example.test/case-5"));
    try expectNextEvent(engine, changed(document, request, .loading, null));
    try expectNoEvent(engine);
    try expectState(engine, document, .loading);

    const outcome = try engine.step(1);
    try testing.expectEqual(1, outcome.applied);
    try testing.expectEqual(1, outcome.events_ready);
    try expectState(engine, document, .loaded);
    try testing.expectEqualStrings("queued", (try engine.document(document)).body);
    try expectNextEvent(engine, changed(document, request, .loaded, null));
}

test "FP-0006 case 6: a version 2 response is unsupported and keeps the request live for a version 1 response" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-6");
    const before = fingerprint(engine);
    try testing.expectError(error.UnsupportedVersion, engine.respond(request, 2, "future"));
    try testing.expectEqual(before, fingerprint(engine));

    const idle = try engine.step(4);
    try testing.expectEqual(0, idle.applied);
    try testing.expect(!idle.work_remaining);
    try expectState(engine, document, .loading);

    try engine.respond(request, 1, "present");
    const outcome = try engine.step(4);
    try testing.expectEqual(1, outcome.applied);
    const view = try engine.document(document);
    try testing.expectEqual(DocumentState.loaded, view.state);
    try testing.expectEqualStrings("present", view.body);
}

test "FP-0006 case 7: an unsupported-version rejection and a step fail the document and end the request" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-7");
    try engine.reject(request, .unsupported_version);
    try expectState(engine, document, .loading);

    const outcome = try engine.step(1);
    try testing.expectEqual(1, outcome.applied);
    try testing.expect(!outcome.work_remaining);
    const view = try engine.document(document);
    try testing.expectEqual(DocumentState.failed, view.state);
    try testing.expectEqual(0, view.body.len);

    try testing.expectError(error.UnknownId, engine.respond(request, 1, "late"));
    try testing.expectError(error.UnknownId, engine.reject(request, .unsupported_version));
    try expectNextEvent(engine, issued(document, request, null));
    try expectNextEvent(engine, changed(document, request, .loading, null));
    try expectNextEvent(engine, changed(document, request, .failed, .unsupported_version));
    try expectNoEvent(engine);
}

test "FP-0006 case 8: a cancellation and a step fail the document, and a later response is unknown" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-8");
    try engine.cancel(request);

    // A second answer to the same request is an invalid state while the first is queued.
    const before = fingerprint(engine);
    try testing.expectError(error.InvalidState, engine.respond(request, 1, "second"));
    try testing.expectError(error.InvalidState, engine.reject(request, .unsupported_version));
    try testing.expectError(error.InvalidState, engine.cancel(request));
    try testing.expectEqual(before, fingerprint(engine));
    try expectState(engine, document, .loading);

    const outcome = try engine.step(1);
    try testing.expectEqual(1, outcome.applied);
    try expectState(engine, document, .failed);
    try testing.expectError(error.UnknownId, engine.respond(request, 1, "late"));

    try expectNextEvent(engine, issued(document, request, null));
    try expectNextEvent(engine, changed(document, request, .loading, null));
    try expectNextEvent(engine, cancelled(document, request));
    try expectNextEvent(engine, changed(document, request, .failed, null));
    try expectNoEvent(engine);
}

test "FP-0006 case 9: a second load cancels the first request and issues a second one" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const first = try engine.load(document, "https://example.test/first");
    try engine.respond(first, 1, "stale");
    const second = try engine.load(document, "https://example.test/second");
    try testing.expect(first != second);
    try testing.expectEqual(1, engine.requests.count());
    try testing.expectEqual(0, engine.inputs.len);

    // The first request ended before its issuance was drained, so its URL is gone.
    try expectNextEvent(engine, issued(document, first, null));
    try expectNextEvent(engine, changed(document, first, .loading, null));
    try expectNextEvent(engine, cancelled(document, first));
    try expectNextEvent(engine, issued(document, second, "https://example.test/second"));
    try expectNoEvent(engine);

    const idle = try engine.step(4);
    try testing.expectEqual(0, idle.applied);
    try expectState(engine, document, .loading);
    try testing.expectError(error.UnknownId, engine.respond(first, 1, "stale"));

    try engine.respond(second, 1, "fresh");
    _ = try engine.step(4);
    try testing.expectEqualStrings("fresh", (try engine.document(document)).body);
}

fn destroyLoadingDocument(engine: *Engine) !void {
    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-10");
    try engine.respond(request, 1, "queued body");
    try testing.expectEqual(1, engine.inputs.len);

    try engine.destroyDocument(document);
    try testing.expectEqual(0, engine.inputs.len);
    try testing.expectEqual(0, engine.requests.count());
    try testing.expectEqual(0, engine.request_ids.count());
    try expectNextEvent(engine, issued(document, request, null));
    try expectNextEvent(engine, changed(document, request, .loading, null));
    try expectNextEvent(engine, cancelled(document, request));
    try expectNoEvent(engine);

    const outcome = try engine.step(8);
    try testing.expectEqual(0, outcome.applied);
    try testing.expect(!outcome.work_remaining);
    try testing.expectEqual(0, outcome.events_ready);
    try testing.expectError(error.UnknownId, engine.respond(request, 1, "late"));
    try testing.expectError(error.UnknownId, engine.document(document));
}

test "FP-0006 case 10: destroying a loading document with a queued response cancels it, applies nothing, and leaks nothing" {
    var counting: testing.FailingAllocator = .init(testing.allocator, .{});
    const engine = try Engine.create(counting.allocator(), test_options);
    defer engine.destroy() catch unreachable;

    // The first cycle grows the tables, maps, and queues to their steady capacity.
    try destroyLoadingDocument(engine);
    const bytes = counting.allocated_bytes - counting.freed_bytes;
    const allocations = counting.allocations - counting.deallocations;
    try destroyLoadingDocument(engine);
    try testing.expectEqual(bytes, counting.allocated_bytes - counting.freed_bytes);
    try testing.expectEqual(allocations, counting.allocations - counting.deallocations);
}

test "FP-0006 case 11: destroying an engine with outstanding requests, queued answers, and undrained events leaks nothing" {
    var counting: testing.FailingAllocator = .init(testing.allocator, .{});
    const engine = try Engine.create(counting.allocator(), test_options);

    var documents: [5]DocumentId = undefined;
    var requests: [5]RequestId = undefined;
    for (&documents, &requests) |*document, *request| {
        document.* = try engine.createDocument();
        request.* = try engine.load(document.*, "https://example.test/case-11");
    }
    try engine.respond(requests[0], 1, "loaded body");
    _ = try engine.step(1);
    try expectState(engine, documents[0], .loaded);
    try engine.respond(requests[1], 1, "queued body");
    try engine.reject(requests[2], .unsupported_version);
    try engine.cancel(requests[3]);

    try testing.expectEqual(4, engine.requests.count());
    try testing.expectEqual(3, engine.inputs.len);
    try testing.expect(engine.events.len > 0);
    try engine.destroy();
    try testing.expectEqual(counting.allocated_bytes, counting.freed_bytes);
    try testing.expectEqual(counting.allocations, counting.deallocations);
}

test "FP-0006 case 12: the request bound and the body bound return LimitExceeded and change nothing" {
    const engine = try Engine.create(testing.allocator, .{ .max_outstanding_requests = 2, .max_response_body_bytes = 4 });
    defer engine.destroy() catch unreachable;

    const a = try engine.createDocument();
    const b = try engine.createDocument();
    const c = try engine.createDocument();
    _ = try engine.load(a, "https://example.test/a");
    _ = try engine.load(b, "https://example.test/b");

    const before_load = fingerprint(engine);
    try testing.expectError(error.LimitExceeded, engine.load(c, "https://example.test/c"));
    try testing.expectEqual(before_load, fingerprint(engine));
    try expectState(engine, c, .empty);
    try testing.expectEqual(2, engine.requests.count());

    // A reload replaces the document's outstanding request, so it stays within the bound.
    const reloaded = try engine.load(a, "https://example.test/a2");
    try testing.expectEqual(2, engine.requests.count());

    const before_body = fingerprint(engine);
    try testing.expectError(error.LimitExceeded, engine.respond(reloaded, 1, "12345"));
    try testing.expectEqual(before_body, fingerprint(engine));
    try engine.respond(reloaded, 1, "1234");
    _ = try engine.step(1);
    try testing.expectEqualStrings("1234", (try engine.document(a)).body);

    _ = try engine.load(c, "https://example.test/c");
    try testing.expectEqual(2, engine.requests.count());
}

test "FP-0006 case 13: a budget of two applies two of three queued responses in arrival order" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    var documents: [3]DocumentId = undefined;
    var requests: [3]RequestId = undefined;
    for (&documents, &requests) |*document, *request| {
        document.* = try engine.createDocument();
        request.* = try engine.load(document.*, "https://example.test/case-13");
    }
    try engine.respond(requests[2], 1, "two");
    try engine.respond(requests[0], 1, "zero");
    try engine.respond(requests[1], 1, "one");

    const first = try engine.step(2);
    try testing.expectEqual(2, first.applied);
    try testing.expect(first.work_remaining);
    try testing.expectEqual(8, first.events_ready);
    try testing.expectEqual(Deadline.none, first.next_deadline);
    try testing.expectEqualStrings("two", (try engine.document(documents[2])).body);
    try testing.expectEqualStrings("zero", (try engine.document(documents[0])).body);
    const waiting = try engine.document(documents[1]);
    try testing.expectEqual(DocumentState.loading, waiting.state);
    try testing.expectEqual(0, waiting.body.len);
    // Only the request of documents[1] is still live, so only its issuance keeps its URL.
    try expectNextEvent(engine, issued(documents[0], requests[0], null));
    try expectNextEvent(engine, changed(documents[0], requests[0], .loading, null));
    try expectNextEvent(engine, issued(documents[1], requests[1], "https://example.test/case-13"));
    try expectNextEvent(engine, changed(documents[1], requests[1], .loading, null));
    try expectNextEvent(engine, issued(documents[2], requests[2], null));
    try expectNextEvent(engine, changed(documents[2], requests[2], .loading, null));
    try expectNextEvent(engine, changed(documents[2], requests[2], .loaded, null));
    try expectNextEvent(engine, changed(documents[0], requests[0], .loaded, null));
    try expectNoEvent(engine);

    const second = try engine.step(2);
    try testing.expectEqual(1, second.applied);
    try testing.expect(!second.work_remaining);
    try testing.expectEqual(1, second.events_ready);
    try testing.expectEqualStrings("one", (try engine.document(documents[1])).body);
    try expectNextEvent(engine, changed(documents[1], requests[1], .loaded, null));
}

fn errorOf(result: anytype) ?anyerror {
    if (result) |_| return null else |err| return err;
}

const ForeignCalls = struct {
    engine: *Engine,
    document: DocumentId,
    request: RequestId,
    results: [10]?anyerror = @splat(null),

    fn run(calls: *ForeignCalls) void {
        const engine = calls.engine;
        calls.results = .{
            errorOf(engine.createDocument()),
            errorOf(engine.destroyDocument(calls.document)),
            errorOf(engine.document(calls.document)),
            errorOf(engine.load(calls.document, "https://example.test/foreign")),
            errorOf(engine.respond(calls.request, 1, "foreign")),
            errorOf(engine.reject(calls.request, .unsupported_version)),
            errorOf(engine.cancel(calls.request)),
            errorOf(engine.step(8)),
            errorOf(engine.nextEvent()),
            errorOf(engine.destroy()),
        };
    }
};

test "FP-0006 case 14: a Zig call from another thread returns WrongThread and changes nothing" {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    const document = try engine.createDocument();
    const request = try engine.load(document, "https://example.test/case-14");
    const before = fingerprint(engine);

    var calls: ForeignCalls = .{ .engine = engine, .document = document, .request = request };
    const thread = try std.Thread.spawn(.{}, ForeignCalls.run, .{&calls});
    thread.join();
    for (calls.results) |result| try testing.expectEqual(@as(?anyerror, error.WrongThread), result);
    try testing.expectEqual(before, fingerprint(engine));

    try engine.respond(request, 1, "owner thread");
    _ = try engine.step(1);
    try expectState(engine, document, .loaded);
}

fn OperationPayload(comptime operation: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(operation)).@"fn".return_type.?).error_union.payload;
}

/// Runs one engine operation and checks that a failure is `OutOfMemory` and leaves the engine unchanged.
fn guarded(engine: *Engine, comptime operation: anytype, args: anytype) !OperationPayload(operation) {
    const before = fingerprint(engine);
    return @call(.auto, operation, args) catch |err| {
        try testing.expectEqual(error.OutOfMemory, err);
        try testing.expectEqual(before, fingerprint(engine));
        return err;
    };
}

/// Reloads `document` until the event queue has no free slot beyond the slots that the outstanding requests reserve.
/// A reload announces two events, so it drains one event first when exactly one slot beyond that floor is free.
fn fillEventQueue(engine: *Engine, document: DocumentId) !void {
    while (freeEventSlots(engine) > engine.requests.count()) {
        if (freeEventSlots(engine) == engine.requests.count() + 1) _ = (try engine.nextEvent()).?;
        _ = try guarded(engine, Engine.load, .{ engine, document, "https://example.test/fill" });
    }
}

fn lifecycleScenario(gpa: Allocator) !void {
    const engine = try Engine.create(gpa, .{ .max_outstanding_requests = 4, .max_response_body_bytes = 64 });
    defer engine.destroy() catch unreachable;

    var documents: [3]DocumentId = undefined;
    var requests: [3]RequestId = undefined;
    for (&documents) |*document| document.* = try guarded(engine, Engine.createDocument, .{engine});
    for (documents, &requests) |document, *request| {
        request.* = try guarded(engine, Engine.load, .{ engine, document, "https://example.test/case-15" });
    }
    const spare = try guarded(engine, Engine.createDocument, .{engine});
    _ = try guarded(engine, Engine.load, .{ engine, spare, "https://example.test/spare" });
    _ = (try engine.nextEvent()).?;

    try fillEventQueue(engine, spare);
    try guarded(engine, Engine.respond, .{ engine, requests[0], 1, "<p>case 15</p>" });
    try guarded(engine, Engine.reject, .{ engine, requests[1], .unsupported_version });
    try guarded(engine, Engine.cancel, .{ engine, requests[2] });
    // Only the reserved slots are free, and the step's host cancellation needs one slot beyond that floor, so it must reserve new storage.
    try testing.expectEqual(engine.requests.count(), freeEventSlots(engine));
    const outcome = try guarded(engine, Engine.step, .{ engine, 8 });
    try testing.expectEqual(3, outcome.applied);
    try testing.expectEqualStrings("<p>case 15</p>", (try engine.document(documents[0])).body);
    try expectState(engine, documents[1], .failed);
    try expectState(engine, documents[2], .failed);

    try fillEventQueue(engine, spare);
    try guarded(engine, Engine.destroyDocument, .{ engine, spare });
    _ = try guarded(engine, Engine.load, .{ engine, documents[0], "https://example.test/reload" });
    while (try engine.nextEvent()) |_| {}
    for (documents) |document| try guarded(engine, Engine.destroyDocument, .{ engine, document });
    try testing.expectEqual(0, engine.documents.count());
    try testing.expectEqual(0, engine.requests.count());
}

test "FP-0006 case 15: every induced allocation failure returns OutOfMemory, changes nothing, and leaks nothing" {
    // Fail every remap so that each growth step is an allocation the checker can induce.
    var no_remap: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    var probe: testing.FailingAllocator = .init(no_remap.allocator(), .{});
    try lifecycleScenario(probe.allocator());
    try testing.expect(probe.allocations >= 10);
    try testing.checkAllAllocationFailures(no_remap.allocator(), lifecycleScenario, .{});
    try testing.expectEqual(no_remap.allocated_bytes, no_remap.freed_bytes);
}

/// Runs `body` with an engine whose allocator fails every remap, so each growth step is an allocation that the body can fail.
/// It then restores allocation, destroys the engine, and checks that no byte leaked.
fn withFailingAllocator(comptime body: anytype, args: anytype) !void {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .resize_fail_index = 0 });
    const engine = try Engine.create(failing.allocator(), test_options);
    const result = @call(.auto, body, .{ engine, &failing } ++ args);
    failing.fail_index = std.math.maxInt(usize);
    try engine.destroy();
    try result;
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

fn destroyWhileAllocationFails(engine: *Engine, failing: *testing.FailingAllocator, reloads: usize, extra: bool, answered: bool) !void {
    const d = try engine.createDocument();
    const rd = try engine.load(d, "https://example.test/doomed");
    const s = try engine.createDocument();
    var spare = try engine.load(s, "https://example.test/spare");
    for (0..reloads) |_| spare = try engine.load(s, "https://example.test/spare");
    if (extra) {
        try engine.respond(spare, 1, "spare");
        _ = try engine.step(8);
    }
    if (answered) try engine.respond(rd, 1, "doomed");
    try testing.expect(freeEventSlots(engine) >= engine.requests.count());

    failing.fail_index = failing.alloc_index;
    try engine.destroyDocument(d);
    try testing.expectEqualDeep(@as(?Event, cancelled(d, rd)), engine.events.back());
    try testing.expectError(error.UnknownId, engine.document(d));
    try testing.expectError(error.UnknownId, engine.respond(rd, 1, "x"));
    try testing.expectEqual(0, engine.inputs.len);
    const view = try engine.document(s);
    if (extra) {
        try testing.expectEqual(DocumentState.loaded, view.state);
        try testing.expectEqualStrings("spare", view.body);
    } else {
        try testing.expectEqual(DocumentState.loading, view.state);
    }
}

test "FP-0050 case 1: destroying a loading document allocates nothing" {
    for (0..49) |reloads| {
        for ([_]bool{ false, true }) |extra| {
            for ([_]bool{ false, true }) |answered| try withFailingAllocator(destroyWhileAllocationFails, .{ reloads, extra, answered });
        }
    }
}

fn loadWithoutCancellationSlot(engine: *Engine, failing: *testing.FailingAllocator) !void {
    const t = try engine.createDocument();
    const s = try engine.createDocument();
    _ = try engine.load(s, "https://example.test/spare");
    while (engine.events.buffer.len < 8) _ = try engine.load(s, "https://example.test/spare");
    // Leave free exactly the reserved slots and the two announcements of a load, so only the new request's slot is missing.
    while (freeEventSlots(engine) != engine.requests.count() + 2) {
        if (freeEventSlots(engine) < engine.requests.count() + 2) {
            _ = (try engine.nextEvent()).?;
        } else {
            _ = try engine.load(s, "https://example.test/spare");
        }
    }

    const before = fingerprint(engine);
    failing.fail_index = failing.alloc_index;
    try testing.expectError(error.OutOfMemory, engine.load(t, ""));
    try testing.expectEqual(before, fingerprint(engine));
    try expectState(engine, t, .empty);

    failing.fail_index = std.math.maxInt(usize);
    _ = try engine.load(t, "");
    try expectState(engine, t, .loading);
    try testing.expect(freeEventSlots(engine) >= engine.requests.count());
}

test "FP-0050 case 2: a load that cannot reserve its cancellation slot returns OutOfMemory and changes nothing" {
    try withFailingAllocator(loadWithoutCancellationSlot, .{});
}

fn removeMiddleOfWrappedQueue(offset: usize) !void {
    const engine = try Engine.create(testing.allocator, test_options);
    defer engine.destroy() catch unreachable;

    var warm: [3]DocumentId = undefined;
    for (&warm) |*document| document.* = try engine.createDocument();
    for (warm) |document| try engine.respond(try engine.load(document, "https://example.test/warm"), 1, "warm");
    _ = try engine.step(3);
    const cap = engine.inputs.buffer.len;
    try testing.expect(cap >= 3);

    const a = try engine.createDocument();
    const b = try engine.createDocument();
    const c = try engine.createDocument();
    const p = try engine.createDocument();
    const ra = try engine.load(a, "https://example.test/first");
    const rb = try engine.load(b, "https://example.test/middle");
    const rc = try engine.load(c, "https://example.test/last");
    // Each applied pump answer advances the head of the input queue by one slot.
    while (engine.inputs.head != cap - offset) {
        try engine.respond(try engine.load(p, "https://example.test/pump"), 1, "pump");
        _ = try engine.step(1);
        try testing.expectEqual(cap, engine.inputs.buffer.len);
    }
    while (try engine.nextEvent()) |_| {}

    try engine.respond(ra, 1, "first");
    try engine.respond(rb, 1, "middle");
    try engine.respond(rc, 1, "last");
    try testing.expectEqual(3, engine.inputs.len);
    try testing.expectEqual(cap - offset, engine.inputs.head);
    try testing.expect(engine.inputs.head + engine.inputs.len > cap);

    try engine.destroyDocument(b);
    try testing.expectEqual(2, engine.inputs.len);
    try testing.expectEqual(cap - offset, engine.inputs.head);
    try expectNextEvent(engine, cancelled(b, rb));
    try expectNoEvent(engine);
    try testing.expectError(error.UnknownId, engine.document(b));
    try testing.expectError(error.UnknownId, engine.respond(rb, 1, "x"));

    const outcome = try engine.step(8);
    try testing.expectEqual(2, outcome.applied);
    try testing.expect(!outcome.work_remaining);
    try testing.expectEqual(2, outcome.events_ready);
    try testing.expectEqualStrings("first", (try engine.document(a)).body);
    try testing.expectEqualStrings("last", (try engine.document(c)).body);
    try expectNextEvent(engine, changed(a, ra, .loaded, null));
    try expectNextEvent(engine, changed(c, rc, .loaded, null));
}

test "FP-0050 case 5: removing the middle answer of a wrapped queue keeps the other answers in order" {
    for ([_]usize{ 1, 2 }) |offset| try removeMiddleOfWrappedQueue(offset);
}
