# FP-0050 task contract

## Identity

Task ID: `FP-0050`, "Close the FP-0006 review findings".
Workstream: `substrate`.
Base: the commit that freezes this contract; the drafter read the tree at `c0cbf85`, and no later commit before the freeze changes a source root.
Prerequisites: `FP-0006`, accepted, as `engineering/state.json:103-104` records.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0006/reviews/review-1-accept.json`, findings at lines 90-159.
The `fairpane-spec` worker `FP0050Contract` drafted this contract, and the root integrator froze it on 2026-10-09 with the decisions below, each confirmed by the integrator.

### Integrator decisions

- Plan criterion 1 follows the review's first recommendation at `review-1-accept.json:102`: a load reserves the event slot for its request's cancellation, so destroying a document never allocates.
  This supersedes `engineering/evidence/FP-0006/CONTRACT.md:150`.
  That frozen contract stays unedited.
- Plan criteria 5 and 6 are already met by the generated assertions of FP-0021.
  `tests/c/abi_layout.h:15-55` asserts `sizeof` and every member `offsetof` for all six structures, and `tests/c/abi_smoke.c:23` includes it.
  `src/abi_generated.zig:288-326` asserts `@sizeOf` and every `@offsetOf` for the same six structures on 32-bit and 64-bit targets.
  Both files are generated from one layout model, `layoutOf` at `tools/abi.mjs:494-506`, so the C and Zig assertions match by construction.
  `src/c_api.zig` declares no `extern struct`, and it takes every ABI type from `abi_generated.zig` (`src/c_api.zig:7`).
  `src/root.zig:12-14` analyzes `c_api` in every library build.
  FP-0021 case 12 requires that `tests/c/abi_smoke.c` contain no `_Static_assert(` (`tools/abi.test.mjs:373-374`), and `api/README.md:135` forbids hand edits of generated files.
  This task therefore adds no hand-written layout assertion, because one would create a second layout convention.
  Case 11 is a mechanical check of the existing coverage, with mutation controls.
- Plan criterion 8 adopts one convention for every byte range of the C API: `null_when_empty`.
  The convention also covers the engine-owned output `fp_event.url`.
  A live request with an empty URL currently gives `fp_event.url` a non-null placeholder pointer with length zero.
  A zero-length Zig allocation returns `alignBackward(maxInt(usize))` without calling the allocator (`lib/std/mem/Allocator.zig:319-323` in the pinned toolchain), and `eventToC` copies that pointer (`src/c_api.zig:140-143`).
  The validator enforces the convention, so a later schema edit cannot add a second one.
- The cancellation success path at the C boundary is already tested since FP-0021 (`tests/c/abi_smoke.c:411-429` and `src/abi_scenarios.zig:322-343`).
  The rejection success path and a nonzero `reject_reason` are not, so case 6 tests both answers in one step.
- The review's first minor finding, about `FP-0006/CONTRACT.md:144`, is already closed by the restated bullet at `FP-0006/CONTRACT.md:142-146`.
  This task does no work for it.
- The review's note about the unbound `raw/integration-tests.log` (`review-1-accept.json:147-152`) is not a plan criterion.
  This task changes no gate, and its Evidence section records counted runs with `record`.
- Writable paths add `tools/abi.mjs` and `tools/abi.test.mjs`.
  The validator rule for criterion 8 lives in `tools/abi.mjs`, and the controller cases live in `tools/abi.test.mjs`.
  The plan entry's `allowed_paths` (`engineering/plan.json:2521-2527`) does not list `tools`, so the integrator records this extension.
- New Zig tests are named `FP-0050 case N: ...`.
  The edited FP-0006 case 13 keeps its name.
- The ABI revision stays zero and experimental.
- The event queue keeps exactly one unused slot for each outstanding request.
  `fp_engine_step` therefore keeps `FP_STATUS_OUT_OF_MEMORY`, because a host cancellation announces two events but ends only one request; no plan criterion asks for an infallible step.
- The required gates add `zig-fmt`, because this task changes Zig sources.
  The integrator records that change in the plan entry with the writable-path extension.
- The `zig-test` gate's missing test count stays an acceptance-policy item that `engineering/HANDOFF.md` lists, because changing a protected gate needs separate approval.

## Sources

- Review findings: `engineering/evidence/FP-0006/reviews/review-1-accept.json:90-159`.
- FP-0006 contract and revision 1: `engineering/evidence/FP-0006/CONTRACT.md:137-151`.
- FP-0021 contract and revision 1: `engineering/evidence/FP-0021/CONTRACT.md`, sections "Checks" and "Revision test cases".
- Schema: `api/fairpane.schema.json`; the threads at lines 9-23, the `engine` handle at 124-126, identifiers at 130-139, the `event.url` field at 219-226, `document_destroy` at 290-299, `document_load` at 313-324, and the `request_issued` event at 385-395.
- Scenarios: `api/failure-scenarios.json`; `wrong-thread` at 65-101, `allocation-failure` at 169-190, and `null-required-pointer` at 191-215.
- Generator: `tools/abi.mjs`; `NULLABILITIES` at 29, `validatePointer` at 149-158, `validateDescriptions` at 228-243, `layoutOf` at 494-506, Zig layout checks at 716-732, C layout checks at 737-765, and `validateScenarios` at 776-812.
- Controller tests: `tools/abi.test.mjs`; FP-0021 case 5 at 191-226, case 6 at 227-243, case 12 at 358-375, and case 13 at 376-394.
- Documentation: `api/README.md`; nullability at 60, validator rules at 121-123, the change procedure at 125-135, conventions at 170-180, engines at 198-216, identifiers at 218-225, documents at 240-256, events at 300-316, and storage at 318-321.
- Engine: `src/engine.zig`; error sets at 112-126, `createDocument` at 251-262, `destroyDocument` at 265-277, `load` at 290-344, `step` at 375-388, `discardQueuedAnswer` at 442-455, `freeEventSlots` at 558-560, case 13 at 893-922, `fillEventQueue` at 985-990, and `lifecycleScenario` at 992-1025.
- C API: `src/c_api.zig`; `finish` at 79-89, `eventToC` at 121-160, `documentLoad` at 233-239, `requestRespond` at 245-256, and case 16 at 424-506.
- Scenario tests: `src/abi_scenarios.zig`; the wrong-thread calls at 260-292, `fillEvents` at 446-452, `DestroyDocument` at 501-507, the allocation-failure test at 510-561, and the null-pointer test at 563-616.
- C smoke test: `tests/c/abi_smoke.c`; the foreign calls at 318-352, the null-pointer scenario at 503-560, and `main` at 644-660.
- Gate: the `c-abi` gate in `tools/lib.mjs:468-482` builds the library, runs `abi-exports`, compiles `tests/c/abi_smoke.c` with `-std=c11 -Wall -Wextra -Werror`, and runs it.
- Pinned Zig standard library at `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\lib\std\`: `deque.zig` `popFront` at 307-313 advances `head` without a reset, `at` and `atPtr` at 291-304 index logically, and growth at 65-99 relinearizes; `mem/Allocator.zig:319-323` returns a placeholder pointer for a zero-length allocation.

## Behavior

### Cancellation event reservation (plan criterion 1)

Normative requirements:

- After every engine operation returns, the event queue has at least one unused slot for each outstanding request.
- `Engine.load` reserves, before it changes any state, the capacity for its own announcements and for the reserved slot of the request it issues.
- `Engine.destroyDocument` never allocates.
  `DestroyDocumentError` becomes `error{ WrongThread, UnknownId }`.
- `Engine.step` reserves capacity only for the announcements that the slots of the requests it ends do not cover.
  A step that applies only responses and rejections never allocates.
  A step that applies a host cancellation can still return `error.OutOfMemory`, because that answer announces two events and ends one request.
- Every other reservation and failure rule of `FP-0006` stays in force.

Observable C behavior:

- `fp_document_load` returns `FP_STATUS_OUT_OF_MEMORY` when it cannot reserve its storage, which includes the reserved slot.
  After that status, it writes no request identifier, leaves the document state unchanged, queues no event, and adds no outstanding request.
- `fp_document_destroy` never returns `FP_STATUS_OUT_OF_MEMORY`.
  It destroys a loading document even when every allocation fails, announces `FP_EVENT_REQUEST_CANCELLED`, and discards the queued answer.
- `fp_engine_step` keeps `FP_STATUS_OUT_OF_MEMORY` in its status set.

Schema and scenario changes:

- `document_destroy.statuses` becomes `["ok", "invalid_argument", "wrong_thread", "unknown_id"]`.
- `document_destroy.description` becomes "Releases the document. An outstanding request is cancelled and announced, and its queued answer is discarded. The call never allocates, because the load that issued the request reserved its cancellation event."
- `document_load.description` appends "The load reserves the storage of the request's cancellation event, so {function:document_destroy} never allocates."
- In the `allocation-failure` scenario, the `fp_document_destroy` call at `api/failure-scenarios.json:182` becomes the arguments "a loading document in an engine whose every later allocation fails" with status `ok`.
- The `fp_engine_step` call at line 181 becomes the arguments "an engine whose event queue must grow to announce an applied host cancellation".
- The scenario gains the effect "fp_document_destroy allocates nothing, so it succeeds and announces the cancellation while every allocation fails."

Documentation:

- After `api/README.md:242`, add "It never allocates, so it never returns `FP_STATUS_OUT_OF_MEMORY`."
- After `api/README.md:321`, add "A load also reserves one event slot for the eventual cancellation of its request.", "Destroying a document uses that slot, so it never allocates.", and "A step that applies a host cancellation announces two events but ends one request, so it can still need storage."
- Extend the module comment at `src/engine.zig:11-12` and the doc comments of `load` and `destroyDocument` with the same rule.

Implementation hypothesis, not normative: `load` calls `events.ensureUnusedCapacity(requests.count() + added + announcements)`, where `added` is 1 for a new request and 0 for a reload. `step` calls `events.ensureUnusedCapacity(requests.count() - applied + announcements)`. `destroyDocument` calls `pushBackAssumeCapacity` through `withdrawRequest`.

### Tests that the reservation changes

These tests assume that destroy can fail or that the event queue can fill completely.
Each becomes a loop that stops at the reservation floor, so it terminates both before and after the change.

- A1: `fillEventQueue` at `src/engine.zig:985-990` reloads while `freeEventSlots(engine) > engine.requests.count()`.
  It drains one event first whenever exactly one slot beyond that floor is free.
  The assertion at line 1011 becomes `freeEventSlots(engine) == engine.requests.count()`, and its comment states that the step's cancellation needs one slot beyond the floor.
- A2: In `src/c_api.zig` case 16, the loop at 485-492 uses the same floor rule and keeps the last spare request.
  After the loop, `fp_request_cancel` of that spare request returns `FP_STATUS_OK`.
  The failing step then returns `FP_STATUS_OUT_OF_MEMORY`, `outcome.applied` stays 3, `inputs.len` is 2, the event count is unchanged, and the document stays loading.
  The next step returns `FP_STATUS_OK` with `applied` 2, the document is loaded, and the spare document is failed.
- A3: `fillEvents` at `src/abi_scenarios.zig:446-452` uses the same floor rule.
  At lines 551-557, the test loads `doomed`, fills events, sets `failing.fail_index = failing.alloc_index`, and expects `fp_document_destroy` to return `FP_STATUS_OK`.
  It then restores allocation, drains events until the last one is `FP_EVENT_REQUEST_CANCELLED` for the doomed request, and expects `doomed` to be unknown.
  The `DestroyDocument` helper at 501-507 is deleted.
- A4: The FP-0021 case 5 fixture at `tools/abi.test.mjs:193-201` gives `payload`, `label`, and `title` the nullability `null_when_empty`.
  Its handle field keeps `nullable`, and its assertions stay unchanged.

### Arrival order (plan criterion 2)

FP-0006 case 13 at `src/engine.zig:893-922` sends the responses in the order 2, 0, 1.
It checks which documents a budget of two loads, and it checks the order of the state-change events.

### Removal from a wrapped queue (plan criterion 3)

`discardQueuedAnswer` keeps the logical order of the other inputs when it removes an answer from the middle of a wrapped queue of three answers.
No source change is expected.
Case 5 tests the behavior.

### Reject and cancel at the C boundary (plan criterion 4)

`fp_request_reject` and `fp_request_cancel` succeed for a live, unanswered request.
The applied answers produce the event kinds, document states, and reject reasons that case 6 lists.
No source change is expected.

### Layout assertions (plan criteria 5 and 6)

The generated assertions stay the only layout assertions.
Case 11 checks their coverage mechanically, and its mutation controls show that each side's compiler evaluates them.

### Thread lifetime (plan criterion 7)

- `handles[engine].description` becomes "An engine. It belongs to the thread that created it. The host must destroy it before that thread exits, because the system can reuse the identifier of an exited thread."
- `threads[becomes_owner].description` becomes "The calling thread becomes the owner of the engine that the call creates. The host must destroy the engine before that thread exits."
- After `api/README.md:202`, add these three sentences:
  - "The host must destroy an engine before the thread that created it exits."
  - "The engine identifies its owner by the operating system's thread identifier, which the system can reuse after the thread exits."
  - "A call from a thread that receives a reused identifier would pass the thread check."
- The doc comment of `Engine` in `src/engine.zig` gains "The host must destroy an engine before the thread that created it exits, because the system can reuse the identifier of an exited thread."

The generator renders the handle description above the `fp_engine` typedef and the thread description in the comment of `fp_engine_create`.

### Empty byte ranges (plan criterion 8)

Convention: every byte, text, and web string range is `null_when_empty`.
An input range may be null only when its length is zero, and a null input with length zero means an empty range.
An output range is null exactly when its length is zero.
A null input with a nonzero length returns `FP_STATUS_INVALID_ARGUMENT`.

| Range | Direction and ownership | Before | After |
| --- | --- | --- | --- |
| `fp_document_load` parameter `url` | in, borrowed | `non_null`; a null `url` returns `FP_STATUS_INVALID_ARGUMENT` even with `url_len` zero (`src/c_api.zig:235`) | `null_when_empty` |
| `fp_response.body` | in, borrowed | `null_when_empty` (`src/c_api.zig:249-254`) | Unchanged |
| `fp_document_info.body` | out, owned by the engine | `null_when_empty` | Unchanged |
| `fp_event.url` | out, owned by the engine | `nullable`; an empty live URL gives a non-null placeholder | `null_when_empty`; null when the URL is empty, when the request has ended, and for every other kind |

Schema changes:

- `document_load` parameter `url` gets `"nullability": "null_when_empty"`.
- In `document_load.description`, "The url buffer is borrowed for the call only and must not be null." becomes "The url may be null when url_len is zero, and the engine copies it during the call."
- The `event.url` field gets `"nullability": "null_when_empty"` and the description "For a {event:request_issued} event, the request URL while the request is live. It is null when the URL is empty, when the request has ended, and for every other kind."
- The `request_issued` event description becomes "A load issued a request. The URL is present while the request is live and the URL is not empty, and null otherwise."

Validator: `validatePointer` rejects a byte, text, or web string range whose nullability is not `null_when_empty`, with the message `<where>: a byte, text, or web string range must be null_when_empty.`

C API: one helper converts every input range, and both `documentLoad` and `requestRespond` use it.
`eventToC` sets `url` only when the live URL is not empty.

Scenario and test edits:

- `api/failure-scenarios.json:203` reads "a null engine, then a null URL with a nonzero length, then a null output".
- `api/failure-scenarios.json:83` reads "the engine, a live document, and a null URL with a nonzero length, then a null output, from another thread".
- `src/abi_scenarios.zig:268` and `:599` and `tests/c/abi_smoke.c:332` and `:541` pass `url_len` 1 with the null URL.

Documentation:

- `api/README.md:60` gains "Every byte, text, and web string range in the ABI is `null_when_empty`."
- `api/README.md:123` gains "It rejects a byte, text, or web string range that is not `null_when_empty`."
- The conventions section after line 179 gains "An input range may be null only when its length is zero, and an output range is null exactly when its length is zero."
- Line 250 becomes "The `url` pointer may be null only when `url_len` is zero."
- Line 316 becomes "An issuance event has a null `url` when the URL is empty or when its request has ended."

### Identifier gaps (review note)

`createDocument` and `load` take a process-wide identifier before a fallible table insertion (`src/engine.zig:254-258` and 303-313).
A failed call therefore consumes an identifier.
No behavior changes.

- After `api/README.md:222`, add "A call that fails after it takes an identifier skips that identifier." and "The sequence can therefore have gaps, but no identifier is ever reused."
- The `document` and `request` identifier descriptions in the schema append "A call that fails after it takes an identifier skips that identifier."

### Generation

Run `node tools/fairpane.mjs abi-generate` after each schema edit.
Commit the regenerated `include/fairpane.h`, `src/abi_generated.zig`, and `tests/c/abi_layout.h` without hand edits.
`node tools/fairpane.mjs abi-check` exits with status 0 on the final tree.
The `c-abi` gate's `abi-exports` step passes, because this task adds and removes no function.

### Stop rules

- If case 1 does not fail with `error.OutOfMemory` on the base, stop and report the observed capacities to the integrator.
- If `engine.inputs.buffer.len` changes during the pump loop of case 5, stop and report it.
- If mutation control 11c or 11d compiles, stop and report it, because the generated Zig checks would then not run through `c_api.zig`.

## Exact test cases

Zig cases run through `zig build test`.
C cases run in `tests/c/abi_smoke.c` through the `c-abi` gate, and `main` calls `check_reject_and_cancel()` and then `check_empty_ranges()` right after `check_document_lifecycle()`, before every scenario.
Neither C function carries a `Scenario` marker.
Controller cases go in `abiCases` in `tools/abi.test.mjs`.

1. Zig, `src/engine.zig`, "FP-0050 case 1: destroying a loading document allocates nothing".
   For each `reloads` from 0 to 48, each `extra` in {false, true}, and each `answered` in {false, true}, the test creates a fresh engine.
   The engine uses a `testing.FailingAllocator` over `testing.allocator` with `.resize_fail_index = 0`, and `test_options`.
   It creates document `d` and loads it with `https://example.test/doomed` as request `rd`.
   It creates document `s`, loads it with `https://example.test/spare`, and then reloads `s` `reloads` times.
   When `extra` is true, it responds to the last spare request with `spare` and calls `step(8)`.
   When `answered` is true, it then responds to `rd` with `doomed`.
   It expects `freeEventSlots(engine) >= engine.requests.count()`.
   It sets `failing.fail_index = failing.alloc_index`, and `destroyDocument(d)` succeeds.
   The newest event is `cancelled(d, rd)`, `document(d)` and `respond(rd, 1, "x")` return `error.UnknownId`, and `inputs.len` is 0.
   `s` is `loaded` with body `spare` when `extra` is true and `loading` otherwise.
   After allocation is restored and the engine is destroyed, `failing.allocated_bytes` equals `failing.freed_bytes`.
   This case must fail before the change.
2. Zig, `src/engine.zig`, "FP-0050 case 2: a load that cannot reserve its cancellation slot returns OutOfMemory and changes nothing".
   The engine uses the allocator of case 1 and `test_options`.
   The test creates empty document `t` and document `s`, and it loads `s` with `https://example.test/spare`.
   It reloads `s` until `engine.events.buffer.len >= 8`.
   While `freeEventSlots(engine) != engine.requests.count() + 2`, it drains one event when the free count is lower, and otherwise it reloads `s`.
   It records `fingerprint(engine)` and sets `failing.fail_index = failing.alloc_index`.
   `load(t, "")` returns `error.OutOfMemory`, the fingerprint is unchanged, and `t` is `empty`.
   After allocation is restored, `load(t, "")` succeeds, `t` is `loading`, and `freeEventSlots(engine) >= engine.requests.count()`.
   No byte leaks.
   This case must fail before the change.
3. Zig, `src/c_api.zig`, "FP-0050 case 3: fp_document_destroy cannot return FP_STATUS_OUT_OF_MEMORY".
   At run time, `abi.statuses.fp_document_destroy` equals `.{ .ok, .invalid_argument, .wrong_thread, .unknown_id }`.
   The error names of `native.DestroyDocumentError` are exactly `WrongThread` and `UnknownId`.
   This case must fail before the change.
4. Zig, `src/engine.zig`, FP-0006 case 13, edited in place.
   Three documents `d0`, `d1`, and `d2` load `https://example.test/case-13` as `r0`, `r1`, and `r2`.
   The test responds to `r2` with `two`, to `r0` with `zero`, and to `r1` with `one`, in that order.
   `step(2)` reports `applied` 2, `work_remaining` true, `events_ready` 8, and `next_deadline` `none`.
   `d2` has body `two`, `d0` has body `zero`, and `d1` is `loading` with an empty body.
   The events are `issued(d0, r0, null)`, `changed(d0, r0, .loading, null)`, `issued(d1, r1, "https://example.test/case-13")`, `changed(d1, r1, .loading, null)`, `issued(d2, r2, null)`, `changed(d2, r2, .loading, null)`, `changed(d2, r2, .loaded, null)`, and `changed(d0, r0, .loaded, null)`, and then none.
   A second `step(2)` reports `applied` 1, `work_remaining` false, and `events_ready` 1.
   `d1` then has body `one`, and the next event is `changed(d1, r1, .loaded, null)`.
   Control 4 must fail this case.
5. Zig, `src/engine.zig`, "FP-0050 case 5: removing the middle answer of a wrapped queue keeps the other answers in order".
   The test runs for each `offset` in {1, 2}, with a fresh engine over `testing.allocator` and `test_options`.
   It creates `w0`, `w1`, and `w2`, loads each, responds to each with `warm`, and calls `step(3)`.
   It sets `cap = engine.inputs.buffer.len` and expects `cap >= 3`.
   It creates `a`, `b`, `c`, and `p`, and it loads `a`, `b`, and `c` with `https://example.test/first`, `/middle`, and `/last` as `ra`, `rb`, and `rc`.
   Until `engine.inputs.head == cap - offset`, it loads `p` with `https://example.test/pump`, responds with `pump`, and calls `step(1)`.
   After each repetition, it expects `engine.inputs.buffer.len == cap`.
   It drains every event.
   It responds to `ra` with `first`, to `rb` with `middle`, and to `rc` with `last`.
   It expects `inputs.len == 3`, `inputs.head == cap - offset`, and `inputs.head + inputs.len > cap`.
   `destroyDocument(b)` succeeds.
   Then `inputs.len` is 2, `inputs.head` is still `cap - offset`, the only event is `cancelled(b, rb)`, and `document(b)` and `respond(rb, 1, "x")` return `error.UnknownId`.
   `step(8)` reports `applied` 2, `work_remaining` false, and `events_ready` 2.
   `a` has body `first`, `c` has body `last`, and the events are `changed(a, ra, .loaded, null)` and then `changed(c, rc, .loaded, null)`.
   `testing.allocator` reports no leak and no double free.
   Controls 5a and 5b must fail this case.
6. C, `tests/c/abi_smoke.c`, `check_reject_and_cancel`, "FP-0050 case 6".
   The test creates an engine with bounds 4 and 16 and two documents, `rejected_doc` and `cancelled_doc`.
   It loads them with `https://example.test/rejected` and `https://example.test/cancelled` as `rejected` and `cancelled`, and it drains every event.
   `fp_request_reject(engine, rejected, FP_REJECT_UNSUPPORTED_VERSION)` and `fp_request_cancel(engine, cancelled)` each return `FP_STATUS_OK`.
   Both documents stay `FP_DOCUMENT_LOADING`, and `expect_queues(engine, 0, 1)` holds.
   `step(engine, 8)` reports `applied` 2, `work_remaining` 0, and `events_ready` 3.
   The first event is `FP_EVENT_DOCUMENT_STATE_CHANGED` for `rejected_doc` and `rejected`, with `FP_DOCUMENT_FAILED`, `reject_reason` `FP_REJECT_UNSUPPORTED_VERSION`, a null `url`, and `url_len` 0.
   The second is `FP_EVENT_REQUEST_CANCELLED` for `cancelled_doc` and `cancelled`, with `document_state` 0, `reject_reason` 0, a null `url`, and `url_len` 0.
   The third is `FP_EVENT_DOCUMENT_STATE_CHANGED` for `cancelled_doc` and `cancelled`, with `FP_DOCUMENT_FAILED` and `reject_reason` 0.
   No event follows.
   `fp_document_get` reports `FP_DOCUMENT_FAILED`, a null `body`, and `body_len` 0 for both documents, and both requests are unknown through `expect_unknown_request`.
   Controls 6a and 6b must fail this case.
7. C, `tests/c/abi_smoke.c`, `check_empty_ranges`, "FP-0050 case 7".
   The test creates an engine with bounds 4 and 16 and documents `null_url` and `empty_url`.
   `fp_document_load(engine, null_url, NULL, 1, &out)` with `out = 0x5E0` returns `FP_STATUS_INVALID_ARGUMENT`.
   `out` stays `0x5E0`, `null_url` stays `FP_DOCUMENT_EMPTY`, and `expect_queues(engine, 0, 0)` holds.
   `fp_document_load(engine, null_url, NULL, 0, &out)` returns `FP_STATUS_OK` with a nonzero request `first`.
   Its `FP_EVENT_REQUEST_ISSUED` event has a null `url` and `url_len` 0, and a loading state change follows.
   `fp_document_load(engine, empty_url, (const uint8_t *)"", 0, &second)` returns `FP_STATUS_OK`.
   Its issuance event also has a null `url` and `url_len` 0, and a loading state change and no other event follow.
   A response for `first` with a null `body`, `body_len` 0, and version `FP_RESOURCE_REQUEST_VERSION` returns `FP_STATUS_OK`.
   A step applies 1, and `null_url` is `FP_DOCUMENT_LOADED` with a null `body` and `body_len` 0.
   This case must fail before the change.
8. Controller, `tools/abi.test.mjs`, "FP-0050 case 8: every byte range is null_when_empty, and the validator rejects any other nullability".
   Every parameter and field of kind `bytes`, `text`, or `web_string` in the committed schema has the nullability `null_when_empty`.
   Copies of the schema with `document_load.url` `non_null`, `event.url` `nullable`, and `response.body` `non_null` are rejected.
   The rejections match `/document_load\.url.*null_when_empty/`, `/event\.url.*null_when_empty/`, and `/response\.body.*null_when_empty/`.
   The generated header comment of `fp_document_load` contains ` * url: input, null when empty, borrowed.`.
   This case must fail before the change.
9. Controller, `tools/abi.test.mjs`, "FP-0050 case 9: fp_document_destroy never returns out_of_memory".
   The committed `document_destroy.statuses` equals `['ok', 'invalid_argument', 'wrong_thread', 'unknown_id']`.
   The generated header comment of `fp_document_destroy` contains ` * Statuses: FP_STATUS_OK, FP_STATUS_INVALID_ARGUMENT, FP_STATUS_WRONG_THREAD, FP_STATUS_UNKNOWN_ID.`.
   The `allocation-failure` scenario has an `fp_document_destroy` call with status `ok`, and none with status `out_of_memory`.
   A copy of the committed scenarios with that status set to `out_of_memory` is rejected with `/fp_document_destroy cannot return status "out_of_memory"/`.
   This case must fail before the change.
10. Controller, `tools/abi.test.mjs`, "FP-0050 case 10: the thread lifetime and identifier gaps are documented".
    The generated header contains `/* An engine. It belongs to the thread that created it. The host must destroy it before that thread exits, because the system can reuse the identifier of an exited thread. */` immediately followed by `typedef struct fp_engine fp_engine;`.
    The comment of `fp_engine_create` contains ` * Thread: The calling thread becomes the owner of the engine that the call creates. The host must destroy the engine before that thread exits.`.
    The Zig file's `Engine` doc comment contains the same handle sentence.
    The comments of `fp_document_id` and `fp_request_id` contain "A call that fails after it takes an identifier skips that identifier.".
    `api/README.md` contains each of the five frozen README sentences of the thread-lifetime and identifier sections as its own line.
    This case must fail before the change.
11. Controller, `tools/abi.test.mjs`, "FP-0050 case 11: the generated layout assertions cover both sides of the ABI".
    FP-0021 cases 6 and 12 run unchanged and pass.
    `src/c_api.zig` matches `/@import\("abi_generated\.zig"\)/` and does not match `/extern struct/`.
    `src/root.zig` contains `comptime {\n    _ = c_api;\n}`.
    For every schema structure, the generated `tests/c/abi_layout.h` has one `sizeof` assertion and the generated Zig file has one `@sizeOf` check.
    Controls 11a to 11d apply to this case.

### Mutation controls

Each control edits the final tree, runs the named command, and records its diff, output, and exit status.
After each control, restore the tree.
After controls 11b to 11d, run `abi-check` and confirm exit status 0.
Record a crash separately from a failed assertion.

- Control 4: in `Engine.step`, each application moves the queued input with the smallest request identifier to the front and then pops it.
  Case 4 must fail.
  The base version of case 13, with responses in the order 1, 0, 2, runs under the same control and passes, which shows the gap.
- Control 5a: `discardQueuedAnswer` frees the matching answer and decrements `inputs.len` without moving any input.
  Case 5 must fail or crash.
- Control 5b: `discardQueuedAnswer` reads `engine.inputs.buffer[position]` and writes `engine.inputs.buffer[kept]` instead of the logical `at` and `atPtr`.
  Case 5 must fail or crash.
- Control 6a: delete the `reject_reason` assignment at `src/c_api.zig:151`.
  The `c-abi` run must fail in `check_reject_and_cancel`.
- Control 6b: map `.request_cancelled` to `.request_issued` at `src/c_api.zig:156`.
  The `c-abi` run must fail in `check_reject_and_cancel`.
- Control 11a: add `const Shadow = extern struct { struct_size: u32 };` to `src/c_api.zig`.
  Case 11 must fail.
- Control 11b: change the `sizeof(fp_event)` assertion in `tests/c/abi_layout.h` from 56 to 64.
  The `c-abi` run must fail to compile with "fp_event differs from the size that the schema implies.".
  `abi-check` must exit with status 1 and name `tests/c/abi_layout.h`.
- Control 11c: change `@sizeOf(Event) != layout(56, 48)` in `src/abi_generated.zig` to `layout(64, 48)`.
  `zig build` must fail with "Event differs from the size that the schema implies.".
  `[INFERENCE]` The library build evaluates this check through `src/root.zig:12-14` and `src/c_api.zig:7`, and this control confirms it.
- Control 11d: change `@offsetOf(Event, "url_len") != layout(48, 44)` to `layout(52, 44)`.
  `zig build` must fail with "Event.url_len differs from the offset that the schema implies.".

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Reserve each request's cancellation event when the request is issued | 1, 2, 3, 9, and adjustments A1 to A3 |
| Check arrival order in case 13 with the order 2, 0, 1 | 4 |
| Remove a queued answer from the middle of a wrapped queue of three | 5 |
| Test the reject and cancel success paths at the C boundary | 6 |
| Assert the size of every C structure in the C smoke test | 11 and controls 11b |
| Assert matching sizes and offsets at compile time in `src/c_api.zig` | 11 and controls 11a, 11c, and 11d |
| Document the engine destruction before its owning thread exits | 10 |
| Use one convention for empty borrowed byte ranges | 7, 8, and adjustment A4 |
| Review note: identifiers can be skipped | 10 |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0050/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Use `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` as the Zig executable.
Never delete or overwrite a log.
Name a log of a failed attempt with the suffix `-attempt-N`, and list each one with its cause in the README.

1. Write cases 1 to 11 on the base before any implementation change.
2. Delete `out/fp0050-before` if it exists.
3. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0050-before`.
   Cases 1, 2, and 3 must fail, and cases 4 and 5 must pass.
4. Record `controller-tests-before.log` with `node tools/fairpane.mjs test`.
   Cases 8, 9, and 10 must fail, and case 11 must pass.
5. Record `c-smoke-before.log` with `node tools/fairpane.mjs run c-abi --evidence-dir out/fp0050-before-gates`.
   Case 6 must pass, and case 7 must stop the executable with a failed assertion.
6. Record `abi-generate.log` with `node tools/fairpane.mjs abi-generate` after the schema change.
7. Record `abi-check.log` with `node tools/fairpane.mjs abi-check` on the final tree, with exit status 0.
8. Record `mutation.log` with every control, and store each diff as `mutation-<control>.diff`.
9. Delete `out/fp0050-after` if it exists.
10. Record `tests-after.log` with `cmd /d /c ver` and then `zig build test --summary all --cache-dir out/fp0050-after`.
11. Record `controller-tests-after.log` with `node --version` and then `node tools/fairpane.mjs test`.
12. Record `c-smoke-after.log` with `node tools/fairpane.mjs run c-abi --evidence-dir out/fp0050-after-gates`.
13. Write `engineering/evidence/FP-0050/README.md` with the worktree `HEAD`, the criterion mapping, each control's result, and every resolved ambiguity.

The integrator records `git rev-parse HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` for every source root in `raw/integration-binding.log` before the gates.
The integrator runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and `c-abi` with `--evidence-dir engineering/evidence/FP-0050/gates`.
The integrator records `integration-abi-check.log` with `node tools/fairpane.mjs abi-check`.
The integrator records `integration-tests.log` with an uncached `zig build test --summary all --cache-dir out/fp0050-integration`.
The integrator appends `HEAD` and the same status to `raw/integration-binding.log` after the last run.

## Authority

Writable paths: `src`, `api`, `include`, `tests`, `tools/abi.mjs`, `tools/abi.test.mjs`, and `engineering/evidence/FP-0050/`.
`include/fairpane.h`, `src/abi_generated.zig`, and `tests/c/abi_layout.h` change only through `abi-generate`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
The integrator alone updates `engineering/state.json`, `engineering/HANDOFF.md`, and `engineering/plan.json`.
Required reviewer: `fairpane-review`.

## Non-goals

- No function, structure, status, enumeration member, or event kind is added or removed.
- No hand-written layout assertion is added to `tests/c/abi_smoke.c` or `src/c_api.zig`.
- No change makes `fp_engine_step` infallible.
- No host allocator enters the C ABI, so C still cannot induce allocation failure.
- No new thread-identity mechanism replaces the operating-system thread identifier.
- No identifier-issuance change removes the gaps that failed calls leave.
- No gate changes, including a `zig-test` gate that prints a test count.
- `engineering/evidence/FP-0006/CONTRACT.md` and `docs/ABI_AND_WRAPPERS.md` stay unchanged.
- The ABI revision stays zero and experimental.
