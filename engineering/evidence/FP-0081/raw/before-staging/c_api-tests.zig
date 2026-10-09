
// FP-0081 before-run staging: cases 3 to 5 and their helpers.
const unlimited = std.math.maxInt(u64);

fn memoryOf(engine: *abi.Engine) !abi.EngineMemory {
    var result: abi.EngineMemory = undefined;
    try testing.expectEqual(ok, fp_engine_get_memory(engine, &result, @sizeOf(abi.EngineMemory)));
    try testing.expectEqual(@sizeOf(abi.EngineMemory), result.struct_size);
    try testing.expectEqual(0, result.reserved);
    return result;
}

/// The bytes that a recording allocator holds for its live allocations.
fn liveBytes(recording: *const testing.FailingAllocator) u64 {
    return recording.allocated_bytes - recording.freed_bytes;
}

test "FP-0081 case 3: createEngine with a limit below the bytes that creation needs returns FP_STATUS_OUT_OF_MEMORY, writes no engine, and allocates nothing" {
    // An unlimited engine reports the bytes that creation needs.
    var probe_recording: testing.FailingAllocator = .init(testing.allocator, .{});
    const probe = try createTestEngine(probe_recording.allocator());
    const needed = (try memoryOf(probe)).allocated_bytes;
    try testing.expect(needed > 0);
    try testing.expectEqual(liveBytes(&probe_recording), needed);
    try testing.expectEqual(ok, fp_engine_destroy(probe));
    try testing.expectEqual(0, liveBytes(&probe_recording));

    var options = test_options;
    for ([_]u64{ 0, needed - 1 }) |limit| {
        var recording: testing.FailingAllocator = .init(testing.allocator, .{});
        options.max_allocated_bytes = limit;
        var handle: ?*abi.Engine = @ptrFromInt(0x1000);
        try testing.expectEqual(out_of_memory, createEngine(recording.allocator(), &options, &handle));
        try testing.expectEqual(@as(?*abi.Engine, @ptrFromInt(0x1000)), handle);
        // The limit refused the engine record before any request reached the allocator.
        try testing.expectEqual(0, recording.allocations);
        try testing.expectEqual(0, recording.allocated_bytes);
    }

    var exact: testing.FailingAllocator = .init(testing.allocator, .{});
    options.max_allocated_bytes = needed;
    var handle: ?*abi.Engine = null;
    try testing.expectEqual(ok, createEngine(exact.allocator(), &options, &handle));
    const created = try memoryOf(handle.?);
    try testing.expectEqual(needed, created.allocated_bytes);
    try testing.expectEqual(needed, created.max_allocated_bytes);
    try testing.expectEqual(ok, fp_engine_destroy(handle.?));
    try testing.expectEqual(0, liveBytes(&exact));
}

/// Sets the limit one byte below the allocated bytes, checks that the engine reports it, and returns the allocated bytes.
fn limitBelowAllocated(engine: *abi.Engine) !u64 {
    const allocated = (try memoryOf(engine)).allocated_bytes;
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, allocated - 1));
    const limited = try memoryOf(engine);
    try testing.expectEqual(allocated, limited.allocated_bytes);
    try testing.expectEqual(allocated - 1, limited.max_allocated_bytes);
    return allocated;
}

/// Rejects requests of new documents until the input queue is full, then returns an unanswered request of one more document.
fn fillInputs(engine: *abi.Engine) !abi.RequestId {
    const native_engine = nativeEngine(engine);
    var document: abi.DocumentId = @fromBackingInt(0);
    while (native_engine.inputs.buffer.len != native_engine.inputs.len) {
        try testing.expectEqual(ok, fp_document_create(engine, &document));
        const request = try loadUrl(engine, document, "https://example.test/input");
        try testing.expectEqual(ok, fp_request_reject(engine, request, reject_unsupported_version));
    }
    try testing.expectEqual(ok, fp_document_create(engine, &document));
    return loadUrl(engine, document, "https://example.test/unanswered");
}

test "FP-0081 case 4: a limit below the allocated bytes is accepted, every allocating call then returns FP_STATUS_OUT_OF_MEMORY, and a higher limit lets the same calls succeed" {
    var options = test_options;
    options.max_outstanding_requests = 1024;
    var handle: ?*abi.Engine = null;
    try testing.expectEqual(ok, createEngine(testing.allocator, &options, &handle));
    const engine = handle.?;
    defer testing.expectEqual(ok, fp_engine_destroy(engine)) catch unreachable;
    const native_engine = nativeEngine(engine);

    // The first document grows the empty identifier map and document table.
    var allocated = try limitBelowAllocated(engine);
    var document: abi.DocumentId = @fromBackingInt(0xD0C);
    try testing.expectEqual(out_of_memory, fp_document_create(engine, &document));
    try testing.expectEqual(0xD0C, @backingInt(document));
    try testing.expectEqual(0, native_engine.documents.count());
    try testing.expectEqual(allocated, (try memoryOf(engine)).allocated_bytes);
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited));
    try testing.expectEqual(ok, fp_document_create(engine, &document));

    // A load copies its URL.
    const url = "https://example.test/fp-0081-case-4";
    var request: abi.RequestId = @fromBackingInt(0x5E0);
    allocated = try limitBelowAllocated(engine);
    try testing.expectEqual(out_of_memory, fp_document_load(engine, document, url, url.len, &request));
    try testing.expectEqual(0x5E0, @backingInt(request));
    try testing.expectEqual(document_empty, try documentState(engine, document));
    try testing.expectEqual(0, native_engine.requests.count());
    try testing.expectEqual(allocated, (try memoryOf(engine)).allocated_bytes);
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited));
    request = try loadUrl(engine, document, url);

    // A response copies its body.
    const response: abi.Response = .{ .struct_size = @sizeOf(abi.Response), .version = 1, .request_id = request, .body = "body", .body_len = 4 };
    allocated = try limitBelowAllocated(engine);
    try testing.expectEqual(out_of_memory, fp_request_respond(engine, &response));
    try testing.expectEqual(0, native_engine.inputs.len);
    try testing.expectEqual(allocated, (try memoryOf(engine)).allocated_bytes);
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited));
    try testing.expectEqual(ok, fp_request_respond(engine, &response));

    // A rejection and a host cancellation grow a full input queue.
    var cancelled = request;
    for ([_]bool{ false, true }) |cancel| {
        const unanswered = try fillInputs(engine);
        const inputs = native_engine.inputs.len;
        allocated = try limitBelowAllocated(engine);
        const refused = if (cancel) fp_request_cancel(engine, unanswered) else fp_request_reject(engine, unanswered, reject_unsupported_version);
        try testing.expectEqual(out_of_memory, refused);
        try testing.expectEqual(inputs, native_engine.inputs.len);
        try testing.expectEqual(allocated, (try memoryOf(engine)).allocated_bytes);
        try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited));
        const accepted = if (cancel) fp_request_cancel(engine, unanswered) else fp_request_reject(engine, unanswered, reject_unsupported_version);
        try testing.expectEqual(ok, accepted);
        cancelled = unanswered;
    }

    // A step that applies the host cancellation grows an event queue whose only free slots are the reserved ones.
    var spare: abi.DocumentId = @fromBackingInt(0);
    try testing.expectEqual(ok, fp_document_create(engine, &spare));
    _ = try loadUrl(engine, spare, "https://example.test/spare");
    while (native_engine.events.buffer.len - native_engine.events.len > native_engine.requests.count()) {
        if (native_engine.events.buffer.len - native_engine.events.len == native_engine.requests.count() + 1) {
            var event: abi.Event = undefined;
            try testing.expectEqual(ok, fp_engine_next_event(engine, &event, @sizeOf(abi.Event)));
        }
        _ = try loadUrl(engine, spare, "https://example.test/spare");
    }
    const inputs = native_engine.inputs.len;
    const events = native_engine.events.len;
    var outcome: abi.StepOutcome = .{ .struct_size = 1, .work_remaining = 2, .applied = 3, .events_ready = 4, .next_deadline = 5 };
    allocated = try limitBelowAllocated(engine);
    try testing.expectEqual(out_of_memory, fp_engine_step(engine, std.math.maxInt(u32), &outcome, @sizeOf(abi.StepOutcome)));
    try testing.expectEqual(3, outcome.applied);
    try testing.expectEqual(inputs, native_engine.inputs.len);
    try testing.expectEqual(events, native_engine.events.len);
    try testing.expectEqual(allocated, (try memoryOf(engine)).allocated_bytes);
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, unlimited));
    try testing.expectEqual(ok, fp_engine_step(engine, std.math.maxInt(u32), &outcome, @sizeOf(abi.StepOutcome)));
    try testing.expectEqual(inputs, outcome.applied);
    try testing.expectEqual(document_loaded, try documentState(engine, document));
    try testing.expectEqual(unknown_id, fp_request_cancel(engine, cancelled));
}

/// Calls both memory functions from a thread that does not own the engine, with valid and then invalid arguments.
const MemoryCalls = struct {
    engine: *abi.Engine,
    memory: abi.EngineMemory = .{ .struct_size = 7, .reserved = 10, .allocated_bytes = 8, .max_allocated_bytes = 9 },
    statuses: [5]u32 = @splat(ok),

    fn run(calls: *MemoryCalls) void {
        calls.statuses = .{
            fp_engine_get_memory(calls.engine, &calls.memory, @sizeOf(abi.EngineMemory)),
            fp_engine_get_memory(calls.engine, null, @sizeOf(abi.EngineMemory)),
            fp_engine_get_memory(calls.engine, &calls.memory, @sizeOf(abi.EngineMemory) - 1),
            fp_engine_set_memory_limit(calls.engine, 0),
            fp_engine_set_memory_limit(calls.engine, unlimited),
        };
    }
};

test "FP-0081 case 5: invalid memory calls return FP_STATUS_INVALID_ARGUMENT and write nothing, and foreign calls return FP_STATUS_WRONG_THREAD first" {
    const engine = try createTestEngine(testing.allocator);
    defer testing.expectEqual(ok, fp_engine_destroy(engine)) catch unreachable;
    const untouched: abi.EngineMemory = .{ .struct_size = 7, .reserved = 10, .allocated_bytes = 8, .max_allocated_bytes = 9 };

    var memory = untouched;
    const statuses = [_]u32{
        fp_engine_get_memory(engine, &memory, @sizeOf(abi.EngineMemory) - 1),
        fp_engine_get_memory(engine, &memory, 0),
        fp_engine_get_memory(engine, null, @sizeOf(abi.EngineMemory)),
        fp_engine_get_memory(null, &memory, @sizeOf(abi.EngineMemory)),
        fp_engine_set_memory_limit(null, 0),
    };
    for (statuses) |status| try testing.expectEqual(invalid_argument, status);
    try testing.expectEqual(untouched, memory);
    try testing.expectEqual(unlimited, (try memoryOf(engine)).max_allocated_bytes);

    // A limit that neither foreign call sets shows that neither one applied.
    const before = try memoryOf(engine);
    const limit = before.allocated_bytes + 4096;
    try testing.expectEqual(ok, fp_engine_set_memory_limit(engine, limit));
    var calls: MemoryCalls = .{ .engine = engine };
    const thread = try std.Thread.spawn(.{}, MemoryCalls.run, .{&calls});
    thread.join();
    for (calls.statuses) |status| try testing.expectEqual(wrong_thread, status);
    try testing.expectEqual(untouched, calls.memory);
    const after = try memoryOf(engine);
    try testing.expectEqual(before.allocated_bytes, after.allocated_bytes);
    try testing.expectEqual(limit, after.max_allocated_bytes);
}
