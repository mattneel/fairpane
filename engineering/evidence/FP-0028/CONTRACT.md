# FP-0028 task contract

## Identity

Task ID: `FP-0028`, "Harden controller command records".
Workstream: `laboratory`.
Base: the commit that records `FP-0001` acceptance.
Prerequisites: `FP-0001`.
Assigned role: `fairpane-core`, executed by the root integrator.
Origin: the minor controller findings in `engineering/evidence/FP-0001/reviews/review-2-reject.json`.

## Behavior

### Command records

Every `RESULT` line and every receipt command record adds two fields.
`cwd` is the absolute working directory of the child process.
`started_at` is the UTC start time in ISO 8601 form.
The `COMMAND` line keeps its current JSON array form.

### Failure paths

`runProcess` never throws after its arguments pass validation.
When the log cannot be opened, it returns a failed result with an `error` and writes no log.
When the output capture cannot be created, it writes a `RESULT` line with an `error` and closes the log.
When the capture copy or a log write fails, the result carries an `error`, and every descriptor closes.
A capture error is kept even when a spawn error already exists.

### Output capture

Each command writes its output to a file in a new private temporary directory.
On POSIX, the directory has mode `0700` and the file has mode `0600`.
The controller removes that directory after it copies the output into the log.

### Testable seams

`gateEnvironment(root, gate)` returns the environment overrides for a gate.
Zig and C ABI gates receive `ZIG_GLOBAL_CACHE_DIR` under `<root>/.zig-cache/global`.
Other gates receive no override.
`runProcess` accepts a `copyOutput` option so a test can force a copy failure.
`recordCommand` accepts a `pathEnv` option that it passes to `resolveExecutable`.

## Exact test cases

1. A recorded command's `RESULT` line and returned record contain `cwd` and a parseable `started_at`.
2. A log path whose parent is a regular file yields a failed result instead of an exception.
3. A forced copy failure yields an `error`, a `RESULT` line, and no remaining capture directory.
4. Output written to standard error reaches the log.
5. A completed command leaves no `fairpane-capture-` directory in the temporary directory.
6. Executable resolution fails when the tool exists only in `process.cwd()` and not on `PATH`.
7. A bare executable name resolved through `pathEnv` appears in the `COMMAND` line as its absolute path.
8. A rejected log path outside the evidence roots creates no file.
9. The CLI rejects `run` without a gate, `run --evidence-dir` without a value, and `record --env` without `NAME=VALUE`.
10. `gateEnvironment` returns the repository-local cache only for `zig` and `c-abi` gates.

## Authority

Writable paths: `tools`, `tests`, and `engineering/evidence`.
Protected paths: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Required independent reviewer: `fairpane-review`.

## Acceptance

```text
node tools/fairpane.mjs run repo-check --evidence-dir engineering/evidence/FP-0028/gates
node tools/fairpane.mjs run controller-test --evidence-dir engineering/evidence/FP-0028/gates
node tools/fairpane.mjs run zig-test --evidence-dir engineering/evidence/FP-0028/gates
node tools/fairpane.mjs run c-abi --evidence-dir engineering/evidence/FP-0028/gates
```

Required target execution: Windows x86_64 host execution under Node, plus the controller tests under Bun for information.
Expected test denominator: the existing controller tests plus the ten cases above.

## Non-goals

- No change to receipt validation rules or gate definitions.
- No operating-system sandbox or disk quota.
