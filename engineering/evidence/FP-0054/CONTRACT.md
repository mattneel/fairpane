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

## Revision 1

Base: the commit that freezes this revision, whose parent is `c5f7f2b`.
Source finding: `engineering/evidence/FP-0054/reviews/review-1-reject.json`.
The original "Output-path guard" section required a comparison of canonical real paths.
That requirement contradicts the plan criterion "Compare file identities, not path spellings", and the review rejected the implementation that followed it.
This revision replaces that section and adds the cases below.
Every other section stays in force.

### Output-path guard by file identity

`run --transcript` and `minimize --out` refuse an output path that names the input file.
The equal-spelling check stays as a first test.
When the output path exists, the guard opens both files and compares their identities.
A file identity is the pair of a volume or device identifier and a file identifier.

- On Windows, the identity is the `VolumeSerialNumber` and the 128-bit `FileId` of `FILE_ID_INFORMATION`, which `NtQueryInformationFile` returns for the `FileIdInformation` class.
- On other systems, the identity is the `st_dev` and `st_ino` of `fstat`.

Equal identities produce the existing detail, `command line: the output path names the input file`, with exit status 3.
An output path that does not exist is not the input file.
A failure to open or identify either file is a harness error that names that file's subject, with exit status 3.
A refused or failed command writes nothing.
Opening follows symbolic links, so a link to the input is refused.
The guard compares no path strings except in the equal-spelling check.

Windows 8.3 short names get no test, because short-name creation is a volume setting that a test cannot rely on.
The identity comparison covers them because a short name opens the same file.

### Command-line size bound

Case 1 also runs through the `fairpane-lab` executable, so its wiring is tested.

### Error without a code

A removal error without a `code` gets exactly one attempt, and the recorded error names it.

### Revision 1 test cases

Each build step below works in a directory that it creates fresh for its run.
A guard regression therefore cannot corrupt a cached copy that a later run reuses.
Each step copies `tests/lab/case-03-body-mismatch.json` into its directory as `case.json` when it needs an input.

1. Build step: with `link.json` created as a hard link to `case.json`, `fairpane-lab minimize case.json --out link.json` exits with status 3 and the refusal detail, and `case.json` still equals the fixture.
2. Build step: with the same hard link, `fairpane-lab run case.json --transcript link.json` exits with status 3 and the refusal detail, and `case.json` still equals the fixture.
3. Build step, Windows hosts only: `fairpane-lab minimize case.json --out CASE.JSON` exits with status 3 and the refusal detail, and `case.json` still equals the fixture.
   Other hosts do not add this step, and the evidence names the host that ran it.
4. Build step: with `other.json` a separate byte-identical copy of `case.json`, `fairpane-lab minimize case.json --out other.json` exits with status 0 and result `pass`, and `other.json` becomes a version 2 case whose `derived_from.case_sha256` is the digest of `case.json`.
5. Build step: a case file of `case_size_limit + 1` bytes, extended without writing data, makes `fairpane-lab run` exit with status 3 and the detail `case file: exceeds the size limit`.
   The same file makes `fairpane-lab minimize` with `--out` naming a new path exit with status 3 and the same detail, and that path still does not exist afterward.
   A transcript file of `transcript_size_limit + 1` bytes makes `fairpane-lab replay` exit with status 3 and the detail `transcript file: exceeds the size limit`.
   The step removes each oversized file afterward.
6. Controller: an injected removal error without a `code` gets exactly one attempt, and the recorded error names its message.

Cases 1 to 3 must fail before the fix.
Cases 4 to 6 test behavior that may already hold, so each needs a mutation control that it fails.

- For case 4, the guard refuses every existing output path.
- For case 5, the `run` command's case-file subject becomes `transcript file`.
- For case 6, the retry condition at `tools/lib.mjs` becomes `e.code !== undefined && !TRANSIENT_REMOVAL.has(e.code)`.

### Revision 1 evidence

Record `tests-before-r1.log` on the revision base, `mutation-r1.log` with each control and its diff, an uncached `tests-after-r1.log` with `zig build test --summary all`, and `controller-tests-after-r1.log` under `engineering/evidence/FP-0054/raw/`.
Record the host operating system and `bun --version` in the after logs.
Correct the README row for the output-path guard, and state the actual worktree base of the original work and of this revision.
The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs the four gates.
