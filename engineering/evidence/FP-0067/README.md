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
