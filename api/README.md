# Experimental embedding surface

`fairpane.schema.json` is the single machine-readable description of the public C ABI.
`include/fairpane.h` is its generated C declaration.
`src/abi_generated.zig` is its generated Zig declaration.
`src/c_api.zig` is its candidate implementation, and it imports the generated Zig declarations.
`src/engine.zig` is the native Zig API behind it.
`failure-scenarios.json` defines the failure scenarios that every wrapper runs before it qualifies.

ABI revision zero is experimental.
The capability mask is zero because no browser feature is implemented.
No native API can validate arbitrary pointer provenance from a hostile in-process caller.

The browser shell reaches the engine only through this surface and the first-party Rust wrapper.
The surface must therefore carry every capability that the browser needs.
Generated declarations do not qualify a wrapper by themselves.
A wrapper qualifies only after it runs the failure scenarios against the actual engine in its own runtime.

## Schema

The schema is language-neutral data.
It contains no C or Zig syntax.
It describes every constant, status, enumeration, handle, identifier family, structure, function, parameter, and event of the ABI.
Names are lowercase snake case, and the generator derives each language's names from them and from the `fp` prefix.
Collections are arrays, so declaration order never depends on object key order.

Every value has one of these kinds.

| Kind | Meaning | C declaration | Zig declaration |
| --- | --- | --- | --- |
| `integer` | A fixed-width integer with explicit signedness and an explicit inclusive range. | `uint32_t`, `int32_t`, and so on | `u32`, `i32`, and so on |
| `enumeration` | A closed set of named integer values with an underlying integer kind. | `FP_*` macros and the underlying integer | An `enum` type, and the underlying integer in structures and parameters |
| `handle` | An opaque engine pointer whose layout no binding may inspect. | `fp_engine *` | `?*Engine` |
| `identifier` | An opaque nonzero 64-bit identifier for a named family. | `fp_document_id` | `DocumentId`, a nonexhaustive `enum(u64)` |
| `bytes` | A range of bytes with a pointer and a length. | `const uint8_t *` and `size_t` | `?[*]const u8` and `usize` |
| `text` | A range of UTF-8 bytes that holds Unicode scalar values only. | `const char *` and `size_t` | `?[*]const c_char` and `usize` |
| `web_string` | A range of UTF-16 code units that may hold unpaired surrogates. | `const uint16_t *` and `size_t` | `?[*]const u16` and `usize` |
| `structure` | A versioned record whose first field is `struct_size`. | `fp_*` structure | `extern struct` |
| `optional` | A value that may be absent, distinct from an explicit null value of a nullable kind. | `FP_OPTIONAL(type)` | `Optional(T)` |

A range field or parameter named `x` has a generated length named `x_len`.
Its unit is bytes for `bytes` and `text`, and UTF-16 code units for `web_string`.
An output structure parameter named `x` has a generated size argument named `x_size`.

An optional value encodes absence as zero, so its value kind must never be zero.
That value kind is an identifier, an enumeration without a zero member, or an integer whose range excludes zero.
`FP_OPTIONAL(type)` expands to `type`, so an optional field keeps the layout and name of its value.
The Zig `Optional(T)` type is a nonexhaustive enumeration with an `absent` member, an `of` function, and a `get` function.
Zig structures and parameters carry raw integers for enumerations, because a C caller can pass any value.
An optional enumeration carries `Optional(T)` of the enumeration type, because that wrapper accepts every raw value.

Each pointer-bearing parameter and field states its direction, its nullability, its ownership, and its lifetime.
A parameter is pointer-bearing when its direction is `out` or its kind is a handle, a range, or a structure.
A field is pointer-bearing when its kind is a handle or a range.
An output parameter that receives a pointer states the facts of that pointer in `receives`.

| Fact | Values |
| --- | --- |
| Direction | `in` or `out`. |
| Nullability | `non_null`, `null_when_empty`, or `nullable`. An input range that is `null_when_empty` may be null only when its length is zero. An output range that is `null_when_empty` is null exactly when its length is zero. |
| Ownership | `borrowed`, `owned_by_engine`, `transferred_to_caller`, or `consumed_on_success`. |
| Lifetime | A lifetime that the schema defines: `call`, `request_end`, `next_load_or_destroy`, `document_destroy`, or `engine_destroy`. Each lifetime lists the functions that end it. |

`consumed_on_success` applies only to an input handle parameter.
A call that returns `FP_STATUS_OK` takes that handle and ends its lifetime.
A call that returns any other status leaves the handle with the caller.
The validator rejects `consumed_on_success` anywhere else, and it requires that the handle's lifetime lists the consuming function.
The `engine` parameter of `fp_engine_destroy` is `consumed_on_success`.

Each identifier family names the lifetime that ends its identifiers.
A document identifier lives until `document_destroy`, which `fp_document_destroy` and `fp_engine_destroy` end.
A request identifier lives until `request_end`.

Each function states its thread rule and every status it can return.
The thread rules are `any`, `becomes_owner`, and `owner`.
Each event lists the event structure fields that it carries and whether each one is always present or optional.

### Description references

A description names another schema item only through a reference, so each generator can write that item's name in its own language.

| Reference | C rendering | Zig rendering |
| --- | --- | --- |
| `{function:document_get}` | `fp_document_get` | `` `functions.fp_document_get` `` |
| `{constant:deadline_none}` | `FP_DEADLINE_NONE` | `` `deadline_none` `` |
| `{status:ok}` | `FP_STATUS_OK` | `` `Status.ok` `` |
| `{event:request_issued}` | `FP_EVENT_REQUEST_ISSUED` | `` `EventKind.request_issued` `` |
| `{enumeration:reject_reason}` | `FP_REJECT_*` | `` `RejectReason` `` |
| `{enumeration:event_kind.none}` | `FP_EVENT_NONE` | `` `EventKind.none` `` |
| `{size:engine_options}` | `sizeof(fp_engine_options)` | `` `@sizeOf(EngineOptions)` `` |
| `{structure:engine_options}` | `fp_engine_options` | `` `EngineOptions` `` |

The validator rejects a reference to an item that does not exist.
It also rejects a description that names a function, constant, status, or event without a reference.
Each generated declaration also states its thread rule, its statuses, and the direction, nullability, ownership, and lifetime of each pointer.
The generated comments therefore use only C names in the header and only Zig names in the Zig file.

### Layout and status checks

The schema implies a C layout with natural alignment for every member.
A pointer and a target-sized length follow each other for a range.
The generated Zig file checks at compile time that every structure has the implied size and field offsets on 32-bit and 64-bit targets.
The generated `tests/c/abi_layout.h` checks the same size and member offsets with C11 `_Static_assert`, and the C smoke test includes it.
The C compiler therefore checks the layout model against its own target ABI, including 32-bit x86 Linux, whose System V ABI aligns `uint64_t` members inside structures to four bytes.
`src/c_api.zig` checks at compile time that each exported function has its generated function type.
It also checks that the native enumerations match the schema enumerations.
`src/abi_generated.zig` declares the status set of each function in `statuses`.
Each export in `src/c_api.zig` returns through `finish`, which maps success and every error of the export's error set to a status at compile time.
A status outside the function's status set, or an error without a status, fails compilation.
`node tools/fairpane.mjs abi-exports <library>` reads the symbol table of a static library.
It exits with status 1 when the library exports an `fp_` symbol that the schema does not declare or lacks one that the schema declares.
The `c-abi` gate runs it on the library that it builds.

## Generator and staleness check

`tools/abi.mjs` validates the schema and then generates `include/fairpane.h`, `src/abi_generated.zig`, and `tests/c/abi_layout.h`.
It uses no package dependencies.
The same schema always produces byte-identical files, regardless of object key order.
Each generated file starts with a comment that names the schema and states that the file is generated.

The validator rejects an unknown kind, a pointer without ownership or lifetime, an inverted integer range, and a duplicate name.
It also rejects a structure without `struct_size` as its first field and a generated C or Zig name that collides with another.
It rejects an optional value that can be zero and a function status that the status enumeration lacks.

To change the ABI, follow these steps.

1. Edit `api/fairpane.schema.json`.
2. Run `node tools/fairpane.mjs abi-generate`.
3. Update `src/c_api.zig` until `zig build test` compiles its export checks.
4. Update `api/failure-scenarios.json` and the C and Zig scenario tests when a status or an effect changes.
5. Run `node tools/fairpane.mjs abi-check`.

`abi-check` regenerates the files in memory and compares them with the committed files byte for byte.
It exits with status 1 and names each file that differs, with the first differing line.
Never edit a generated file by hand.

## Failure scenarios

`failure-scenarios.json` defines the foreign-runtime failure scenarios that every wrapper must run before it qualifies.
Each scenario has an identifier, a situation, a description, the C calls that produce it, and the exact expected statuses and effects.
Each call names a C function and its arguments in prose, and the status must be one that the schema lists for that function.
The validator requires at least one scenario for each of these situations.

- An unknown, foreign, or retired identifier.
- A call from a thread other than the engine's owner.
- Cancellation of a request before and after its answer is queued.
- Engine and document teardown with outstanding requests, queued answers, and undrained events.
- Allocation failure during each operation that allocates.
- A null required pointer and a structure shorter than its `struct_size` requires.
- A response body and a load beyond their bounds.
- A foreign exception or panic in host code, which must never unwind across the C ABI.

A scenario that C cannot express states the reason.
C has no allocator argument in this ABI and no exceptions, so the allocation and unwinding scenarios run in Zig and in later wrappers only.
`tests/c/abi_smoke.c` runs every scenario that C can express, and it names each identifier with a `Scenario <id>:` comment.
`src/abi_scenarios.zig` runs every scenario through the generated declarations against the exported C symbols of the actual engine.
Its test names start with `Scenario <id>:`.
The controller tests check that both sources name exactly the scenarios that they must run.

From a foreign thread, the C and Zig wrong-thread scenarios call each owner function with valid arguments and again with an invalid argument.
Each call returns `FP_STATUS_WRONG_THREAD` and writes no output, so the thread check precedes every other argument check.
`fp_engine_destroy` takes no argument other than the engine, so only its call with a valid engine applies.

The C and Zig foreign-unwind scenarios only establish that the boundary has no unwinding channel.
Every C function returns a plain status, and the engine never calls host code, so neither run can raise a foreign exception or panic inside a C frame.
They do not qualify unwinding safety.
Each later wrapper must inject a real panic or exception in its host code, such as a Rust panic under `panic=unwind` or a C++ exception, and show that it never crosses the C ABI.

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
A call that returns any other status leaves the engine valid and with the caller.

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
