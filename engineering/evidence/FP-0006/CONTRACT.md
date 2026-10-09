# FP-0006 task contract

## Identity

Task ID: `FP-0006`, "Implement bounded host requests and document lifecycle".
Workstream: `substrate`.
Base: commit `9e073e2`.
Prerequisites: `FP-0004`, accepted.
Assigned role: `fairpane-core`.

## Behavior

### Engine and documents

`src/engine.zig` defines the native Zig API, and `src/c_api.zig` exports the C API.
An engine owns its documents, host requests, queued host input, and events.
Creating an engine issues a fresh owner identity for the engine and for each handle table it creates.
No two live tables share an owner identity.

A document has one of four states: `empty`, `loading`, `loaded`, or `failed`.
A new document starts `empty`.
Destroying a document or an engine releases everything it owns, including outstanding requests, queued responses, and undrained events.

### Identifiers

The C API identifies documents and requests by opaque 64-bit identifiers.
Zero is never a valid identifier.
Identifiers are unique within the process and never reused.
An identifier that is not live in the receiving engine returns `FP_STATUS_UNKNOWN_ID`, including an identifier from another engine.
Internal generational handles never cross the C ABI.

### Host requests

Loading a document issues a `resource` host request with version 1.
Every request kind carries an explicit version, and every event that announces a request names its kind and version.
The request's URL bytes stay readable until the request ends.
A request ends when the engine applies its response, applies its rejection or cancellation, or cancels it.

The host answers a request in one of three ways.

| Operation | Contract |
| --- | --- |
| Respond | The response names its version. A version that differs from the request's version returns `FP_STATUS_UNSUPPORTED_VERSION`, and the request stays live. |
| Reject | The host gives a reason. `FP_REJECT_UNSUPPORTED_VERSION` reports a request version that the host does not implement. |
| Cancel | The host withdraws a request. |

A second answer to the same request returns `FP_STATUS_INVALID_STATE`.
An answer to an ended request returns `FP_STATUS_UNKNOWN_ID`.
A new load while a document is loading cancels the earlier request and announces that cancellation.
Destroying a document cancels its outstanding request and announces that cancellation.

### Steps and events

Host operations only queue input; they never mutate document state directly.
`step` applies queued input in arrival order, up to a caller-supplied budget.
Its outcome reports whether queued work remains, how many events are ready, and the next deadline.
No timer exists yet, so the next deadline is always "none".
The engine never calls host code, so no host callback can reenter it.
The host drains events one at a time.
Events announce issued requests, cancelled requests, and document state changes.

A step budget is an engine scheduling boundary only.
It creates no JavaScript task boundary, and no API or document may claim otherwise.

### Bounds and ownership

Engine options bound the number of outstanding requests and the size of a response body.
A load beyond the request bound returns `FP_STATUS_LIMIT_EXCEEDED` and changes nothing.
A response body beyond the size bound returns `FP_STATUS_LIMIT_EXCEEDED`, and the request stays live.
The engine copies each response body during the respond call, so the host's buffer is borrowed only for that call.
Each operation reserves its storage, including event capacity, before it changes any state.
Allocation failure therefore leaves every engine, document, and request unchanged.

### Threads

An engine belongs to the thread that created it.
A call from another thread returns `FP_STATUS_WRONG_THREAD` and changes nothing.

### C conventions

Every C structure starts with a `struct_size` field.
An input structure that is too small, a null required pointer, or a short output size returns `FP_STATUS_INVALID_ARGUMENT` without writing output.
Allocation failure returns `FP_STATUS_OUT_OF_MEMORY`.
The ABI revision stays zero and experimental, and the capability mask stays zero.
`include/fairpane.h`, `api/bootstrap.json`, and `api/README.md` describe every new function, structure, constant, ownership rule, and lifetime.

## Exact test cases

Zig tests live in `src/engine.zig` and `src/c_api.zig` and run through `zig build test`.
The C test extends `tests/c/abi_smoke.c` and runs through the `c-abi` gate.

1. An engine and a document are created and destroyed through the Zig API and through the C API, and a destroyed document identifier returns `FP_STATUS_UNKNOWN_ID`.
2. Two engines and every table they create carry pairwise distinct owner identities.
3. A load emits a request event with kind `resource`, version 1, and the document identifier, and the URL bytes stay readable until the request ends.
4. A response with a body, followed by a step, moves the document to `loaded` with exactly that body, and the request identifier then returns `FP_STATUS_UNKNOWN_ID`.
5. A queued response leaves the document `loading` until a step applies it.
6. A response with version 2 returns `FP_STATUS_UNSUPPORTED_VERSION` and keeps the request live, and a version 1 response then succeeds.
7. A rejection with `FP_REJECT_UNSUPPORTED_VERSION`, followed by a step, moves the document to `failed` and ends the request.
8. A cancellation, followed by a step, moves the document to `failed`, and a later response returns `FP_STATUS_UNKNOWN_ID`.
9. A second load while loading announces cancellation of the first request and issuance of the second, and a response to the first returns `FP_STATUS_UNKNOWN_ID`.
10. Destroying a document with an outstanding request and a queued response announces the cancellation, applies nothing for it, and leaks nothing.
11. Destroying an engine with outstanding requests, queued responses, and undrained events leaks nothing.
12. With a bound of two outstanding requests, a third load returns `FP_STATUS_LIMIT_EXCEEDED` and changes nothing.
    A body over the size bound returns `FP_STATUS_LIMIT_EXCEEDED` and keeps the request live.
13. With three queued responses and a budget of two, a step applies two and reports remaining work, and the next step applies the third and reports none.
14. A call from another thread returns `FP_STATUS_WRONG_THREAD` and changes nothing.
15. `std.testing.checkAllAllocationFailures` runs a scenario with engine creation, documents, loads, responses, steps, events, and destruction.
    Each induced failure returns `error.OutOfMemory`, leaves state unchanged, and leaks nothing.
16. A Zig test injects allocation failure through the C entry points and observes `FP_STATUS_OUT_OF_MEMORY` with unchanged state.
17. A document identifier from one engine returns `FP_STATUS_UNKNOWN_ID` in another engine.
18. The C test creates an engine, loads a document, reads the request event and URL, responds, steps, observes `loaded`, and destroys everything through the header.
    It also checks null pointers and short structure sizes, which return `FP_STATUS_INVALID_ARGUMENT` without writing output.

## Gates

```text
node tools/fairpane.mjs run repo-check --evidence-dir engineering/evidence/FP-0006/gates
node tools/fairpane.mjs run controller-test --evidence-dir engineering/evidence/FP-0006/gates
node tools/fairpane.mjs run zig-fmt --evidence-dir engineering/evidence/FP-0006/gates
node tools/fairpane.mjs run zig-test --evidence-dir engineering/evidence/FP-0006/gates
node tools/fairpane.mjs run zig-build --evidence-dir engineering/evidence/FP-0006/gates
node tools/fairpane.mjs run c-abi --evidence-dir engineering/evidence/FP-0006/gates
```

The integrator also records an uncached `zig build test --summary all` run, because the `zig-test` gate prints no count.

## Non-goals

- No parser, network transport, timer, or script execution exists in this task.
- A host allocator interface is outside this task.
- Process isolation and the process protocol belong to `FP-0020`.

## Review

`fairpane-review` reviews the integrated change.

## Revision 1

Revision 1 records clarifications that the implementation adopted after the contract froze.
The reviewer judges each one against the base text and the exact test cases.

- As a design decision, document operations take effect during the call: creation, destruction, and load.
  Only request answers, which are responses, rejections, and cancellations, queue until a step applies them.
  The base sentence "Host operations only queue input" therefore covers request answers only.
  Plan criterion 3 still holds, because the engine never calls host code, so no host operation can run during a step.
  Review 1 found that the cases do not force this choice, and an earlier wording that cases 3 and 9 required it was wrong.
- A load of a loading document replaces its outstanding request, so it does not count against the request bound.
- An empty event queue returns `FP_STATUS_OK` with the event kind `FP_EVENT_NONE`.
- Exhaustion of process-wide identifiers, owner identities, or table handles returns `FP_STATUS_LIMIT_EXCEEDED` through the C API.
- Destroying a loading document can return `FP_STATUS_OUT_OF_MEMORY`, because it reserves its cancellation event first.
- The URL in a request event is readable only while the request is live; after the request ends, the event carries no URL.
