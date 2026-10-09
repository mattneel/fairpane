# FP-0053 task contract

## Identity

Task ID: `FP-0053`, "Close the FP-0031 review findings".
Workstream: `laboratory`.
Base: commit `101ba28`.
Prerequisites: `FP-0031`, accepted.
Assigned role: the root integrator.
Source findings: `engineering/evidence/FP-0031/reviews/review-1-accept.json`.

## Behavior

### Harness location

The mutation-control harness moves from `engineering/evidence/FP-0028/controls/harness.mjs` to `tools/mutation-harness.mjs`.
`tools` is a source root, so a `controller-test` receipt binds the harness code that the controller test exercises.
`engineering/evidence/FP-0028/controls/mutants.mjs` imports the harness from its new location.

### Capture-directory removal

`removeCapture` in `tools/lib.mjs` makes up to three removal attempts.
It retries only after an error whose code is `EBUSY`, `EPERM`, `ENOTEMPTY`, `EMFILE`, or `ENFILE`, and it waits 50 milliseconds and then 100 milliseconds before the second and third attempts.
After a non-retryable error or the third failed attempt, the record reports `Capture directory removal failed:` with the last error message.

### Mutation control

The harness applies each mutant's replacement text literally, so `$&` and similar sequences stay unchanged.
A new mutant removes the log close from `finishRecord`, and the capture-start test kills it through its log-close assertion alone.
The short-write test includes the record's error in each assertion message.

## Exact test cases

1. An injected `rmSync` that fails twice with `EBUSY` and then succeeds leaves no error and is called three times.
2. An injected `rmSync` that always fails with `EBUSY` is called three times, and the record reports the last error.
3. An injected `rmSync` that fails with an error without a code is called once, and the record reports it.
4. A mutant whose replacement contains `$&` hands the suite runner the literal replacement text.
5. The mutation control runs its unmutated baseline and kills every mutant, including the new log-close mutant.

## Evidence

Record `tests-before.log` with cases 1 through 4 failing, `tests-after.log`, and `mutation-control.log` under `engineering/evidence/FP-0053/raw/`.
Record `HEAD` and a status with untracked files before `repo-check` and `controller-test` run with `--evidence-dir engineering/evidence/FP-0053/gates`.

## Authority

Writable paths: `tools`, `tests`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.
