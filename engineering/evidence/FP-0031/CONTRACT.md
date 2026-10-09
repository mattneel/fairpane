# FP-0031 task contract

## Identity

Task ID: `FP-0031`, "Close the FP-0028 review findings".
Workstream: `laboratory`.
Base: commit `7bc9ace`.
Prerequisites: `FP-0028`, accepted.
Assigned role: `fairpane-core`.
Source findings: `engineering/evidence/FP-0028/reviews/review-1-accept.json`.

## Behavior

`runProcess`, `recordCommand`, and `runGate` in `tools/lib.mjs` keep every behavior that FP-0028 accepted.
A short write to an evidence log is an error, and the command record reports it.
A failed removal of the private capture directory appears in the command record as an error.
`runGate` validates its evidence directory before it writes any file.
An injectable file-system seam lets tests force capture, write, and removal failures without changing production behavior.

## Exact test cases

Each case lives in `tools/selftest.mjs` and runs on Node and on Bun.

1. A capture-start failure writes a RESULT line, closes the log, and returns an error result.
2. A failed RESULT write returns an error result instead of throwing.
3. A spawn error and a capture error both remain in the result.
4. `runGate` writes nothing when its evidence directory fails validation.
5. A short write to the log produces an error result.
6. A failed capture-directory removal appears in the command record.
7. `started_at` in every command record is a canonical UTC ISO 8601 timestamp that round-trips through `Date`.
8. The mutation control in `engineering/evidence/FP-0028/controls/mutants.mjs` runs an unmutated baseline first, then records the failing test name and message for each killed mutant.

## Evidence

Record these under `engineering/evidence/FP-0031/raw/`:

- `tests-before.log`: the new cases failing before the change.
- `tests-after.log`: `node tools/fairpane.mjs test` on Node.
- `tests-bun.log`: `bun tools/selftest.mjs`.
- `mutation-control.log`: the extended mutation control with its baseline.

The integrator runs `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0031/gates`.

## Authority

Writable paths: `tools`, `tests`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.
