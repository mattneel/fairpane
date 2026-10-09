# FP-0050 task contract

## Identity

Task ID: `FP-0050`, "Close the FP-0006 review findings".
Workstream: `substrate`.
Base: commit `93dcaf0`.
Prerequisites: `FP-0006`, accepted.
Assigned role: `fairpane-core`.
Source findings: `engineering/evidence/FP-0006/reviews/review-1-accept.json`.

## Behavior

A load reserves the cancellation event that its request may later need, when it issues the request.
Destroying a document therefore never fails for lack of memory, and `fp_document_destroy` no longer returns `FP_STATUS_OUT_OF_MEMORY`.
The API documentation states that the host destroys an engine before the engine's owning thread exits.
Every borrowed byte range in the C API follows one convention: a null pointer is valid only with a zero length.
`fp_document_load` therefore accepts a null URL with a zero length.
Every other FP-0006 behavior stays unchanged.

## Exact test cases

1. Destroying a loading document succeeds under an allocator that fails every allocation after the load.
2. Case 13 sends responses in the order 2, 0, 1, and a step with a budget of two loads documents 2 and 0 and leaves document 1 loading.
3. Destroying the document whose queued answer sits in the middle of a wrapped queue of three answers leaves the other two answers, which a step applies with their exact bodies in arrival order.
4. Through the C entry points, a rejection and a cancellation each produce their event kinds, the `failed` document state, and the reject reason `FP_REJECT_UNSUPPORTED_VERSION`.
5. The C smoke test asserts `sizeof` for every C structure in the header.
6. `src/c_api.zig` asserts at compile time that every exported structure has the size and field offsets that the header declares.
7. `fp_document_load` with a null URL and a zero length succeeds, and with a null URL and a nonzero length returns `FP_STATUS_INVALID_ARGUMENT`.

## Evidence

Record `tests-before.log`, an uncached `tests-after.log`, and `c-smoke.log` under `engineering/evidence/FP-0050/raw/`.
The integrator records `HEAD`, the staged diff, and file hashes before it runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `zig-build`, and `c-abi` with `--evidence-dir engineering/evidence/FP-0050/gates`.

## Authority

Writable paths: `src`, `api`, `include`, `tests`, and `engineering/evidence`.
If FP-0021 has landed, the change goes through `api/fairpane.schema.json` and the generator instead of hand-written declarations.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.
