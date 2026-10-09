# FP-0021 task contract

## Identity

Task ID: `FP-0021`, "Establish ABI schema generation and wrapper contracts".
Workstream: `wrappers`.
Base: commit `24c0c64`.
Prerequisites: `FP-0006`, accepted.
Assigned role: `fairpane-bindings`.

## Behavior

### Interface schema

`api/fairpane.schema.json` becomes the single machine-readable description of the public C ABI.
It replaces `api/bootstrap.json`, which this task deletes.
The schema is language-neutral data, so it contains no C or Zig syntax.
It describes every constant, status, enumeration, structure, function, parameter, and event that the ABI exposes today.

The schema has these value kinds.

| Kind | Meaning |
| --- | --- |
| `integer` | A fixed-width integer with explicit signedness and an explicit inclusive range. |
| `enumeration` | A closed set of named integer values with an underlying integer kind. |
| `handle` | An opaque engine pointer whose layout no binding may inspect. |
| `identifier` | An opaque nonzero 64-bit identifier for a document, a request, or another named family. |
| `bytes` | A borrowed or owned range of bytes with a pointer and a length. |
| `text` | A range of UTF-8 bytes that holds Unicode scalar values only. |
| `web_string` | A range of UTF-16 code units that may hold unpaired surrogates. |
| `structure` | A versioned record whose first field is `struct_size`. |
| `optional` | A value that may be absent, distinct from an explicit null value of a nullable kind. |

Each pointer-bearing parameter and field states its direction, its nullability, its ownership, and its lifetime as data.
Ownership is `borrowed`, `owned_by_engine`, or `transferred_to_caller`.
A lifetime names the event that ends it, such as `call`, `request_end`, `next_load_or_destroy`, or `engine_destroy`.
Each function states its thread rule and every status it can return.

### Generator

`tools/abi.mjs` reads the schema and generates `include/fairpane.h` and `src/abi_generated.zig`.
`src/c_api.zig` imports the generated Zig declarations instead of declaring the ABI structures by hand.
Generation is deterministic, so the same schema always produces byte-identical files.
Each generated file starts with a comment that names the schema and states that the file is generated.
The generator validates the schema first and rejects an unknown kind, a missing ownership or lifetime, an inverted range, a duplicate name, or a structure without `struct_size`.
`node tools/fairpane.mjs abi-generate` writes the files.
`node tools/fairpane.mjs abi-check` regenerates in memory and exits with status 1 when a committed file differs.

### Shared failure scenarios

`api/failure-scenarios.json` defines the foreign-runtime failure scenarios that every wrapper must run before it qualifies.
Each scenario has an identifier, a description, the C calls that produce it, and the exact expected statuses and effects.
The scenarios cover at least these situations.

- An unknown, foreign, or retired identifier.
- A call from a thread other than the engine's owner.
- Cancellation of a request before and after its answer is queued.
- Engine and document teardown with outstanding requests, queued answers, and undrained events.
- Allocation failure during each operation that allocates.
- A null required pointer and a structure shorter than its `struct_size` requires.
- A response body and a load beyond their bounds.
- A foreign exception or panic in host code, which must never unwind across the C ABI.

The C smoke test runs every scenario that C can express, and its source names each scenario identifier it covers.

### Documentation

`api/README.md` describes the schema, the generator, the staleness check, and the failure scenarios.
It keeps every ownership, lifetime, and thread rule that the FP-0006 surface already documents.

## Exact test cases

Controller tests live in `tools/selftest.mjs` or a module that it registers.
Zig and C tests run through the `zig-test` and `c-abi` gates.

1. Generating from the committed schema reproduces the committed `include/fairpane.h` and `src/abi_generated.zig` byte for byte.
2. Changing one byte of either generated file makes `abi-check` exit with status 1 and name the file.
3. Generation is deterministic across two runs and across schema key order.
4. The validator rejects an unknown kind, a pointer without ownership, a pointer without lifetime, an inverted integer range, a duplicate name, and a structure without `struct_size`.
5. The schema distinguishes `text`, `web_string`, `bytes`, `identifier`, `handle`, ranged `integer`, and `optional` values, and the generator maps each one to distinct C and Zig declarations.
6. Zig compile-time checks assert that every generated structure has the size and field offsets that the schema implies.
7. The C smoke test, compiled against the generated header, runs every C-expressible failure scenario with its expected statuses.
8. A Zig test runs the same scenarios through the generated declarations against the actual engine.
9. Every scenario in `api/failure-scenarios.json` has an identifier, calls, and expected outcomes, and the validator rejects one without them.

## Evidence

Record these under `engineering/evidence/FP-0021/raw/`:

- `tests-before.log`: the new cases failing before the change.
- `abi-check.log`: `node tools/fairpane.mjs abi-check` on the final tree.
- `tests-after.log`: `node tools/fairpane.mjs test`.
- `zig-tests-after.log`: an uncached `zig build test --summary all`.
- `c-smoke.log`: the C smoke test built and run as the `c-abi` gate does.
- `mutation-stale.log`: a hand edit of the generated header that `abi-check` reports.

The integrator runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `zig-build`, and `c-abi` with `--evidence-dir engineering/evidence/FP-0021/gates`.

## Authority

Writable paths: `api`, `include`, `src`, `tools`, `bindings`, `tests`, and `build.zig`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No language wrapper beyond C and Zig exists in this task.
- The ABI revision stays zero and experimental.

## Revisions

Revision 1 follows the rejecting review `reviews/review-1-reject.json` of commit `13372de`.

### Ownership

The ownership vocabulary gains `consumed_on_success`.
It means that a call returning `ok` takes the handle and ends its lifetime, and a call returning any other status leaves the handle with the caller.
The validator accepts it only for an input handle parameter.
`engine_destroy` declares its `engine` parameter `consumed_on_success`.
Each identifier family names the lifetime that ends its identifiers, using the existing lifetime names.

### Language-specific names in generated text

Schema descriptions refer to schema items through references, such as `{function:document_get}`, `{constant:deadline_none}`, `{status:ok}`, `{event:request_issued}`, `{enumeration:reject_reason}`, and `{size:engine_options}`.
The validator rejects a reference to an item that does not exist and a description that names a function, constant, status, or event without a reference.
The C generator renders each reference as the C name, such as `fp_document_get`, `FP_DEADLINE_NONE`, `FP_STATUS_OK`, `FP_EVENT_REQUEST_ISSUED`, `FP_REJECT_*`, and `sizeof(fp_engine_options)`.
The Zig generator renders the Zig name of each item.

### Checks

The generator emits C `_Static_assert` checks of `sizeof` and `offsetof` for every structure from the same layout model, and the C smoke test compiles them.
The `cross` gates or a recorded `zig cc` run compile those checks for a 32-bit x86 target.
`abi_generated.zig` carries each function's allowed status set, and `src/c_api.zig` asserts at compile time that every native error of each export maps into that set.
A test fails when the library exports an `fp_` symbol that the schema does not declare.
From a foreign thread, the C and Zig scenarios also call each owner function with an invalid argument and expect `wrong_thread` with no output written.
`api/README.md` states that the C and Zig scenarios only establish that the boundary has no unwinding channel, and that each later wrapper must inject a real panic or exception.

### Revision test cases

10. The validator rejects `consumed_on_success` on an output parameter, and the generated C and Zig text states the consumption rule for `fp_engine_destroy`.
11. The validator rejects an unknown reference and an unreferenced function name, and the generated header contains no schema-only name such as `document_get` outside a C name.
12. The generated C static assertions compile for x86_64 and for a 32-bit x86 target.
13. A wrong-thread call with an invalid argument returns `wrong_thread` and writes no output, in C and in Zig.
14. A mutation that skips the thread check in `src/c_api.zig` fails both the C and the Zig scenarios, and its diff and logs are recorded.

### Evidence

The integrator also runs the `zig-build` gate on the revision commit.
The evidence README says "at least 20 errors" for the baseline compile.
`docs/ABI_AND_WRAPPERS.md` is outside this task's paths, so the integrator corrects its stale reference separately.
