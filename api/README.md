# Experimental embedding surface

`bootstrap.json` is the machine-readable contract for the candidate surface.
`include/fairpane.h` is its C declaration.
`src/c_api.zig` is its candidate implementation.
`src/engine.zig` is the native Zig API behind it.

ABI revision zero is experimental.
The capability mask is zero because no browser feature is implemented.
No native API can validate arbitrary pointer provenance from a hostile in-process caller.

The browser shell reaches the engine only through this surface and the first-party Rust wrapper.
The surface must therefore carry every capability that the browser needs.
A future schema generator replaces duplicated declarations after its own qualification.
This bootstrap does not claim that the header is generated.

## Conventions

Every function except `fp_abi_revision` returns a status code.
Every C structure starts with a `struct_size` field.
An input structure is too small when its `struct_size` is less than the size that the header declares.
An output structure is too small when the caller's size argument is less than the size that the header declares.
A too-small structure, a null required pointer, or an unknown enumeration value returns `FP_STATUS_INVALID_ARGUMENT`.
A function writes output only when it returns `FP_STATUS_OK`.
On success, a function initializes the declared output structure only.
Bytes beyond that structure remain the caller's property.
Every non-null pointer must reference a readable or writable, correctly aligned object, as its role requires.

## Status codes

| Status | Value | Meaning |
| --- | --- | --- |
| `FP_STATUS_OK` | 0 | The call succeeded. |
| `FP_STATUS_INVALID_ARGUMENT` | 1 | A required pointer is null, a structure is too small, or an enumeration value is unknown. |
| `FP_STATUS_UNKNOWN_ID` | 2 | The identifier is not live in the receiving engine. |
| `FP_STATUS_INVALID_STATE` | 3 | The request already has a queued answer. |
| `FP_STATUS_UNSUPPORTED_VERSION` | 4 | The response version differs from the request version. |
| `FP_STATUS_LIMIT_EXCEEDED` | 5 | A request bound, a body bound, or an identifier space is exhausted. |
| `FP_STATUS_OUT_OF_MEMORY` | 6 | An allocation failed. |
| `FP_STATUS_WRONG_THREAD` | 7 | The caller is not the thread that created the engine. |

A null engine pointer returns `FP_STATUS_INVALID_ARGUMENT`.
The engine checks the calling thread before it checks any other argument.
A call that returns any status other than `FP_STATUS_OK` changes no engine, document, or request.

## Engines

An engine owns its documents, host requests, queued host input, and events.
An engine belongs to the thread that created it.
A call from another thread returns `FP_STATUS_WRONG_THREAD`.
Creating an engine issues a fresh owner identity for the engine and for each handle table it creates.
The engine never calls host code, so no host callback can reenter it.

`fp_engine_create` creates an engine on the calling thread and stores its pointer in `*out_engine`.
It requires non-null `options` and `out_engine` pointers.
The `fp_engine_options` structure is borrowed for the call only.
Its `max_outstanding_requests` field bounds the number of outstanding requests.
Its `max_response_body_bytes` field bounds the size of one response body.
A body bound beyond the address space admits every body that the host can present.

`fp_engine_destroy` releases the engine and everything it owns.
That includes documents, outstanding requests, queued answers, undrained events, URLs, and bodies.
The engine pointer is invalid after a successful call.

## Identifiers

The C API identifies documents and requests by opaque 64-bit identifiers.
Zero is never a valid identifier.
Identifiers are unique within the process and never reused.
Document and request identifiers come from one sequence, so they never coincide.
An identifier that is not live in the receiving engine returns `FP_STATUS_UNKNOWN_ID`.
That includes zero and an identifier from another engine.

## Documents

A document has one of four states.

| State | Value | Meaning |
| --- | --- | --- |
| `FP_DOCUMENT_EMPTY` | 1 | No load has started. |
| `FP_DOCUMENT_LOADING` | 2 | A request for the document's resource is outstanding. |
| `FP_DOCUMENT_LOADED` | 3 | A step applied a response, and the document holds its body. |
| `FP_DOCUMENT_FAILED` | 4 | A step applied a rejection or a host cancellation. |

`fp_document_create` creates an `FP_DOCUMENT_EMPTY` document and stores its identifier in `*out_document`.

`fp_document_destroy` releases the document and its body.
It cancels the document's outstanding request and announces that cancellation.
It discards the request's queued answer, so a later step applies nothing for it.

`fp_document_get` writes an `fp_document_info` structure with the document state and body.
The `body` field is null when `body_len` is zero.
The body bytes stay readable until the document's next load or its destruction.

`fp_document_load` issues a version 1 `FP_REQUEST_RESOURCE` request and stores its identifier in `*out_request`.
It moves the document to `FP_DOCUMENT_LOADING`.
It requires a non-null `url` pointer, even when `url_len` is zero.
The engine copies the URL bytes, so the caller's buffer is borrowed only for the call.
A load discards the body of a loaded document.
A load while the document is loading cancels the earlier request and announces that cancellation.
A load that would add a request beyond `max_outstanding_requests` returns `FP_STATUS_LIMIT_EXCEEDED`.
A load while the document is loading replaces its request, so it stays within the bound.

## Host requests

Every request kind carries an explicit version.
The only kind is `FP_REQUEST_RESOURCE`, and its only version is `FP_RESOURCE_REQUEST_VERSION`, which is 1.
A request ends when a step applies its response, rejection, or cancellation.
A request also ends when the engine cancels it because of a new load, a document destruction, or an engine destruction.

The host answers a live request once.
Each answer only queues input.
A second answer before a step applies the first returns `FP_STATUS_INVALID_STATE`.
An answer to an ended request returns `FP_STATUS_UNKNOWN_ID`.

`fp_request_respond` queues a response that the `fp_response` structure describes.
The structure names the response version.
A version that differs from the request version returns `FP_STATUS_UNSUPPORTED_VERSION`, and the request stays live.
A body beyond `max_response_body_bytes` returns `FP_STATUS_LIMIT_EXCEEDED`, and the request stays live.
The `body` field may be null only when `body_len` is zero.
The engine copies the body during the call, so the host's buffer is borrowed only for that call.

`fp_request_reject` queues a rejection with a reason.
`FP_REJECT_UNSUPPORTED_VERSION` reports a request version that the host does not implement.
Any other reason value returns `FP_STATUS_INVALID_ARGUMENT`.

`fp_request_cancel` queues the host's withdrawal of a request.

## Steps

Host answers only queue input; they never mutate document state directly.
`fp_engine_step` applies queued input in arrival order, up to the caller's `budget`.
A response moves the document to `FP_DOCUMENT_LOADED` with exactly the response body.
A rejection or a host cancellation moves the document to `FP_DOCUMENT_FAILED`.
The step writes an `fp_step_outcome` structure.
Its `applied` field counts the inputs that the step applied.
Its `work_remaining` field is one when queued input remains and zero otherwise.
Its `events_ready` field counts the events that are ready to drain.
Its `next_deadline` field is always `FP_DEADLINE_NONE`, because no timer exists yet.

A step budget is an engine scheduling boundary only.
It creates no JavaScript task boundary, and no API or document may claim otherwise.

## Events

`fp_engine_next_event` removes the oldest event and writes it to an `fp_event` structure.
The host drains events one at a time.
When no event is ready, the call succeeds with kind `FP_EVENT_NONE` and zero fields.
Fields that do not apply to an event kind are zero or null.

| Event | Value | Meaning |
| --- | --- | --- |
| `FP_EVENT_REQUEST_ISSUED` | 1 | A load issued a request. |
| `FP_EVENT_REQUEST_CANCELLED` | 2 | A request ended by cancellation. |
| `FP_EVENT_DOCUMENT_STATE_CHANGED` | 3 | A document moved to a new state. |

Every event names the document, the request, and the request's kind and version.
A state change names the request whose issuance or ending caused it.
A state change names the new state in `document_state`.
A state change caused by a rejection names the reason in `reject_reason`.
An issuance event carries the request URL in `url` and `url_len` while the request is live.
The URL bytes stay readable until the request ends.
An issuance event drained after its request ended has a null `url`.

## Storage and failure

Each operation reserves its storage, including event capacity, before it changes any state.
Allocation failure returns `FP_STATUS_OUT_OF_MEMORY` and leaves every engine, document, and request unchanged.

## Internal handles

`src/handles.zig` defines internal owner identities and generational handles.
Internal handles never cross the C ABI or the process protocol directly.
The C API maps its opaque identifiers to internal handles inside the engine.
