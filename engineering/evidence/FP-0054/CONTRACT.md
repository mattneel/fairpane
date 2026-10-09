# FP-0054 task contract

## Identity

Task ID: `FP-0054`, "Close the FP-0007 and FP-0053 review findings".
Workstream: `laboratory`.
Base: commit `ab2e2ed`.
Prerequisites: `FP-0007` and `FP-0053`, accepted.
Assigned role: `fairpane-core`.
Source findings: `engineering/evidence/FP-0007/reviews/review-1-accept.json` and `engineering/evidence/FP-0053/reviews/review-1-accept.json`.

## Behavior

### Laboratory input bound

`readBounded` and its failure messages move from `src/lab_main.zig` into `src/lab.zig` as `pub fn readInputFile(io, gpa, path, limit)`, so the library tests reach them.
A file longer than its limit fails with `error.FileTooLarge` before any allocation or read.
`lab_main.zig` calls the moved function and keeps its exit statuses and messages.

### Outcome documentation

The doc comment of the outcome logic in `src/lab.zig` states the precedence: `harness-error`, then `timeout`, then `unsupported`, then `fail` or `pass`.
The doc comment of the stage status states that a `fetch` status of `failed` means the stage did not finish, which differs from a `document_state` of `failed`.

### Transcript format version 2

A transcript has `"version": 2` and a top-level `action_count` equal to the number of its actions.
`replay` reports `harness-error` for a version other than 2 and for an `action_count` that differs from the number of actions.

### Derived cases

A case may have `"version": 2`.
A version 2 case requires `derived_from`, an object with `case_sha256` (64 lowercase hex digits) and `corpus` (the original case's corpus value), and its own `corpus` must be `null`.
A version 1 case may not have `derived_from`.
`minimize` writes a version 2 case whose `derived_from` names the original case's SHA-256 and corpus value.

### Output-path guard

`run --transcript` and `minimize --out` refuse an output path that names the input file.
They compare the canonical real paths of both files when the output file exists, so different spellings of the same file are refused.

### Controller tests

The capture-removal retry test becomes three tests.
The first injects `EBUSY` errors with the distinct messages `busy 1` and `busy 2` and then succeeds.
The second injects `EBUSY` errors `busy 1`, `busy 2`, and `busy 3`, expects the recorded error to name `busy 3`, and expects the elapsed time to be at least 140 milliseconds.
The third injects an `EACCES` error, expects one call, and expects the recorded error to name it.
The `lastResult` helper asserts that a `RESULT` line exists before it parses one.

## Exact test cases

1. Zig: a sparse file of 64 MiB + 1 bytes makes `readInputFile` fail with `error.FileTooLarge`, and a counting allocator records no allocation.
2. Zig: a transcript with one action removed but the original `action_count` reports `harness-error`, and a version 1 transcript reports `harness-error`.
3. Zig: `minimize` writes a version 2 case whose `derived_from.case_sha256` equals the original case digest, whose `derived_from.corpus` equals the original corpus value, and whose `corpus` is `null`.
4. Zig: a version 1 case with `derived_from`, a version 2 case without it, and a version 2 case with a non-null `corpus` each report `harness-error` with a distinct message.
5. Build step: `fairpane-lab minimize` with `--out` naming the input file through a different spelling exits with status 3 and leaves the input unchanged.
6. Controller: the three retry tests and the `lastResult` assertion described above.

## Evidence

Record `tests-before.log` with the new cases failing, an uncached `tests-after.log` with `zig build test --summary all`, and `controller-tests-after.log` under `engineering/evidence/FP-0054/raw/`.
The integrator records `HEAD` and a status that includes ignored files for every source root before it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0054/gates`.

## Authority

Writable paths: `src`, `tools`, `tests`, `build.zig`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No new pipeline stage, corpus runner, or result category exists in this task.
