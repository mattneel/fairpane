# FP-0067 evidence

## Scope

Task `FP-0067` closes the review findings of `FP-0033` and `FP-0051`.
The frozen contract is `engineering/evidence/FP-0067/CONTRACT.md`.
The worker implemented it in an isolated working tree whose `HEAD` was `ed95bc5edef54fb020797a53cf525803602a23d3`.
The Windows host was Windows 10.0.26200 on x64 with Node v26.7.0.
The verifier's behavior is unchanged: `tools/attest.mjs` keeps blob `6f9a4ae4a06cef40f0b2951a131fe32cddf89e2d` before and after.
No protected path changed.

## Changes

- `tools/workflow-check.mjs`: `gateWorkflowProblems` reports every key other than `branches` under the `push` or `pull_request` trigger, a `branches` value other than exactly `[master]`, and a `workflow_dispatch` value other than null.
  It reports an upload `path` other than `out/evidence/` and an `if-no-files-found` other than `error`, including a missing one.
  It requires the `linux` job to run exactly `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and the three cross builds, in that order.
- `.github/workflows/gates.yml`: the Linux job runs `Run gate zig-fmt` and `Run gate zig-test` after `controller-test` and before the cross builds, with the Windows job's commands.
- `tools/workflow-check.test.mjs`: cases FP-0067 1 to 5, the Linux gate list in the existing Gates case, and upload inputs in the case FP-0033 9 upload fixture, which the new upload rule requires.
- `tools/attest.test.mjs`: case FP-0051 3 joins the invalid-zlib fixture to the combined outcome assertion with its own pattern, `^error: Git could not look up the candidate commit`.
- `tools/README.md`: the tool-error wording, the `unknown-candidate` rule from ADR 0002, the Linux gate list, and the new Gates rules.
- `engineering/evidence/FP-0051/README.md`: the `raw/revision-2-tests-before.log` row describes its three runs.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Case 1: the committed `gates.yml` has no trigger, upload, or Linux-gate problem. | Case FP-0067 1 passes in `raw/controller-tests-after.log`. In `raw/tests-before.log`, its `gateWorkflowProblems` assertion already holds, and it fails on the Linux gate list. |
| Case 2: each of the four filter keys is exactly one problem that names the trigger and the key. | Case FP-0067 2 fails before with no problem, fails under control M1, and passes after. |
| Case 3: `branches: [master, dev]` and a `workflow_dispatch` mapping are each exactly one problem. | Case FP-0067 3 fails before with no problem and passes after. |
| Case 4: an upload `path` of `out/` and `if-no-files-found: warn` are each exactly one problem. | Case FP-0067 4 fails before with no problem and passes after. |
| Case 5: a Linux job without `zig-test`, or with it after the cross builds, is a problem. | Case FP-0067 5 fails before, because the base Linux job has no `zig-test` step, and passes after with exactly one problem for each fixture. |
| Case 6: case FP-0051 3 keeps passing, and a changed zlib pattern lists all four outcomes in one message. | Case FP-0051 3 passes in `raw/tests-before.log` and `raw/controller-tests-after.log`. Control M2 fails it with one message that lists four outcomes. |
| A mutation control that removes the key check fails case 2. | Control M1. |
| Documentation. | `tools/README.md` lines 112 and 113, and row 68 of `engineering/evidence/FP-0051/README.md`. |
| Baseline identity. | `raw/tests-before.log` records `HEAD`, the staging command, and the blob ID of every staged or tested file. |

## Records

Every command ran through `node tools/fairpane.mjs record`.
No log was deleted or overwritten.

| Log | RESULT |
| --- | --- |
| `raw/linux-baseline.log` | The integrator's record before this task, cited by the contract. |
| `raw/tests-before.log` | See the next section. |
| `raw/workflow-tests-attempt-1.log` | `exit_code` 0. `node tools/workflow-check.test.mjs` passes 25 of 25 cases after the change. The worker named it as an attempt before the run, and the run passed. |
| `raw/mutation.log` | For each control: `git hash-object` before (`exit_code` 0), the mutation (`exit_code` 0), `git hash-object` during (`exit_code` 0), `git diff --no-index` (`exit_code` 1, because the files differ), the test file (`exit_code` 1), the restoration (`exit_code` 0), and `git hash-object` after (`exit_code` 0). |
| `raw/mutation-M1.diff` and `raw/mutation-M2.diff` | The diff of each control. |
| `raw/check-after.log` | `exit_code` 0 for `node tools/fairpane.mjs check`. |
| `raw/controller-tests-after.log` | `exit_code` 0 for `node tools/fairpane.mjs test`, with 207 of 207 controller tests, 0 failures, including FP-0067 cases 1 to 5 and case FP-0051 3. |
| `raw/files-after.log` | `exit_code` 0 for `git status --short` and for `git hash-object` of every changed source and document. |

### Red baseline

`raw/tests-before.log` runs these commands in order.

1. `git rev-parse HEAD` and the `HEAD:` blobs, `exit_code` 0: `HEAD` `ed95bc5edef54fb020797a53cf525803602a23d3`, `tools/workflow-check.mjs` `9847774a88ee8073383f2254c6d832c78755bc89`, `.github/workflows/gates.yml` `ccbd330eb01756973b71fc9464cec7a2043d0a00`, and `tools/attest.mjs` `6f9a4ae4a06cef40f0b2951a131fe32cddf89e2d`.
2. `git status --short`, `exit_code` 0: only the two test files are modified.
3. The staging `node -e` call, `exit_code` 0, copies the base `tools/workflow-check.mjs`, the base `.github/workflows`, and the new `tools/workflow-check.test.mjs` into `out/fp0067-before`.
4. `git hash-object` of every staged and tested file, `exit_code` 0.
   Each staged copy has the blob of its source, and each base source has its `HEAD:` blob.
   The new tests are `tools/workflow-check.test.mjs` `c67790960de3b7539facd8de5fd731f83564442f` and `tools/attest.test.mjs` `0608e2f364a029d3652c456fcc7e187e5735ebe2`.
5. `node out/fp0067-before/tools/workflow-check.test.mjs`, `exit_code` 1, with 19 of 25 cases passing.
   The existing Gates case and FP-0067 cases 1 to 5 fail.
6. `node tools/attest.test.mjs` against the unchanged verifier, `exit_code` 0, with 18 of 18 cases passing.

The test blobs in `raw/files-after.log` equal those in step 4, so the after-runs use the same tests.

## Mutation controls

Each control saved the original file under `out/fp0067/mutation/`, replaced one exact string, and restored the saved file after the run.
Each restored file has its original blob again.

| Control | Mutation | Blobs before, during, and after | Outcome |
| --- | --- | --- | --- |
| M1 | In `tools/workflow-check.mjs`, `for (const e of filters.values()) {` becomes `for (const e of [].values()) {`, which removes the trigger key check. | `d997513b…`, `41525d9e…`, `d997513b…` | `node tools/workflow-check.test.mjs` exits with status 1, and only case FP-0067 2 fails, with `Expected exactly one problem matching /^Line \d+: Trigger pull_request sets types:\./ in []`. |
| M2 | In `tools/attest.test.mjs`, the zlib pattern becomes `/^error: mutated pattern, Git could not look up the candidate commit/`. | `0608e2f3…`, `bdd5e4c2…`, `0608e2f3…` | `node tools/attest.test.mjs` exits with status 1, and only case FP-0051 3 fails. Its one message lists four outcomes: the zlib lookup error, two hash-mismatch errors, and the bogus-commit error, followed by `[false, true, true, true]`. |

## Resolved ambiguities

- The contract fixes the gate list of the Linux job only, so the checker keys that rule to the job ID `linux`.
  The FP-0033 Gates case still fixes the job IDs, the Windows gate list, and the other step order.
- A missing `workflow_dispatch` is not a problem, because the minimal `BASE` fixture omits it and case FP-0033 14 adds it.
  A missing `push` or `pull_request` trigger, or one without a mapping value, is one problem, because its `branches` is not `[master]`.
- A missing upload `path` or `if-no-files-found` is a problem, because `if-no-files-found` defaults to `warn`.
  The case FP-0033 9 upload fixture therefore now sets both inputs.
- A `workflow_dispatch` mapping reports one problem for each key, so the problem names the key.
- The new problem messages are `Trigger <name> sets <key>:.`, `Trigger <name> does not set branches: [master].`, `Trigger <name> sets branches: to <value>.`, `Trigger workflow_dispatch sets <key>:.`, `Trigger workflow_dispatch is set to <value>.`, the upload `sets <input> to <value>` and `does not set <input>` messages, and `Job linux runs the gates <list>. It must run <list>, in that order.`

## Integration

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`.
After the push, the integrator records `gh run view` of the first `Gates` run that contains the change, downloads its Linux receipts with `gh run download` through `record`, and commits them under `engineering/evidence/FP-0067/ci/`.
The Linux `zig-test` receipt must report `pass`.
`fairpane-review` reviews this task.

### Integration record

The integrator applied the worker's patch and committed it alone as `152ed53`.

- `raw/integration-binding.log` records `HEAD` `152ed53` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T13-24-30-185Z-repo-check-4679bbe9.json` and `gates/2026-10-09T13-24-30-568Z-controller-test-dc888552.json` pass.
- `raw/bun-selftest.log` records Bun 1.4.2 and `tools/selftest.mjs` with 207 of 207 tests.

The first `Gates` run with the change is run 37936609533 of `152ed53`; `ci/` records it when it concludes.

### Acceptance run

Run 37936609533 of `152ed53` timed out in the Linux `zig-test` gate at 600,004 milliseconds, as `ci/ci-record.log` and `ci/run-37936609533-linux/` record.
`ci/ci-record.log` viewed the run while it was still in progress; `ci/ci-record-final.log` records its final view, which concludes `failure` with the `zig-test` step failed in both jobs.
Contract amendment 1 makes the acceptance record the first `Gates` run after `FP-0098` lands whose Linux `zig-test` receipt reports `pass`.

- `ci/acceptance-run.log` records `9d5638b`, FP-0098's implementation commit, then `gh run list` of that commit's runs and `gh run view` of run 37941660067, its push run, which is the first run that contains the fix.
  The run concludes `success`, with both jobs successful.
- The same log records the run's artifacts and `gh run download` of `linux-gate-receipts-unsigned-local-integrity-records-not-attestations` into `ci/run-37941660067-linux/`.
- The Linux receipts report `pass` for `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and the three cross-compilation gates.
  The `zig-test` receipt's command took 178,677 milliseconds.

## Review findings

Review 1 (`reviews/review-1-reject.json`) rejected for one blocker and recorded one minor finding and four notes; review 2 (`reviews/review-2-accept.json`) accepts.

- Blocker, no recorded passing Linux `zig-test`: closed by "Acceptance run" above, under contract amendment 1.
- Minor, the workflow checker applies the Linux gate rule only to a job named `linux`: FP-0099's first criterion owns it.
- Note, a missing `workflow_dispatch` trigger is not a checker problem: review 1 found the reading defensible, and no change is made.
  Review 2 adds that the rationale in "Resolved ambiguities" should cite FP-0033 cases 9 and 12, through `gates(BASE)`, rather than case 14.
- Note, `repo-check` does not run the workflow checks: FP-0099's second criterion owns it.
- Note, the red baseline of case 5 fails on a fixture precondition, and no mutation control targets the Linux gate order check: the integrator proposes a mutation control for that check in FP-0099 through a reviewed plan change.
- Note, the Windows and Node v26.7.0 claim in "Scope" for the worker's tree has no log in `raw/`: only the integrator's receipts record those values, so the claim about the worker's tree is [INFERENCE].
- Review 2's note on amendment wording: a later amendment of this kind says "the first `Gates` run that contains <commit>" and requires that run to pass.
