# FP-0067 task contract

## Identity

Task ID: `FP-0067`, "Close the FP-0033 and FP-0051 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0033` and `FP-0051`, accepted.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0033/reviews/review-4-accept.json`, `engineering/evidence/FP-0051/reviews/review-3-accept.json`, and the Linux baseline `engineering/evidence/FP-0067/raw/linux-baseline.log`.

### Integrator decisions

- The trigger rule belongs in the workflow checker, not only in its test, so `repo-check` and `controller-test` reject a narrowing filter in any later edit.
- The Linux job of the `Gates` workflow runs the existing gates `zig-fmt` and `zig-test` with the same commands as the Windows job.
  `engineering/gates.json` defines both gates without a platform, so no protected file changes.
- `raw/linux-baseline.log` shows that `zig build test --summary all` passes 62 of 62 steps and 272 of 272 tests at `8d945fe` on WSL Ubuntu with the locked `x86_64-linux` compiler, after the compiler archive matched the lock's SHA-256.
- A transient download failure of the locked compiler in CI is re-run, not retried inside the installer; the installer stays unchanged in this task.

## Sources

- `tools/workflow-check.mjs` and `tools/workflow-check.test.mjs`, especially the Gates trigger assertions at `tools/workflow-check.test.mjs:87-90` and the job gate lists after them.
- `.github/workflows/gates.yml`, whose Linux job runs `repo-check`, `controller-test`, and the three cross builds.
- `tools/attest.test.mjs`, case `FP-0051 3`, whose invalid-zlib fixture has its own assertion before the combined outcome assertion.
- `tools/README.md:110` and ADR 0002, lines 77 to 79.
- `engineering/evidence/FP-0051/README.md:68` and `engineering/evidence/FP-0051/raw/revision-2-tests-before.log`.
- GitHub Actions workflow syntax for `on.push` and `on.pull_request` filters: <https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions>.

## Behavior

### Gates triggers

`gateWorkflowProblems` reports a problem for every key under `on.push` or `on.pull_request` of the `Gates` workflow other than `branches`.
That covers `branches-ignore`, `tags`, `tags-ignore`, `paths`, `paths-ignore`, and `types`, and any other key.
It reports a problem when `branches` is not exactly the list `[master]`, and when `on.workflow_dispatch` is not null.
Each problem names the trigger and the key.

### Upload inputs

`gateWorkflowProblems` reports a problem when an upload step of the `Gates` workflow has a `path` other than `out/evidence/` or an `if-no-files-found` other than `error`.

### Linux gates

The Linux job runs, after `controller-test` and before the cross builds, the steps `Run gate zig-fmt` with `node tools/fairpane.mjs run zig-fmt` and `Run gate zig-test` with `node tools/fairpane.mjs run zig-test`.
The workflow checker and its test require that list of gates for the Linux job.

### Verifier case FP-0051 3

The invalid-zlib fixture joins the combined outcome assertion with its own expected pattern, `^error: Git could not look up the candidate commit`.
One assertion therefore reports the outcome of all four fixtures.

### Documentation

`tools/README.md` says that an object under the candidate's ID that exists but cannot be read is a tool error.
It also says that a readable object of another type under the candidate's ID is `unknown-candidate`, as ADR 0002 states.
The row for `raw/revision-2-tests-before.log` in `engineering/evidence/FP-0051/README.md` describes its three runs, and states that only the third shows the base defect.

### Baseline identity

Every red baseline log of this task records `HEAD`, the staging command, and the blob ID of every staged or tested file before the run.

## Exact test cases

1. Controller: the committed `gates.yml` has no trigger, upload, or Linux-gate problem.
2. Controller: workflow fixtures that add each of `types: [closed]` under `pull_request`, `paths-ignore: ['**']` under `push`, `tags: ['v*']` under `push`, and `branches-ignore: [dev]` under `pull_request` each produce exactly one problem that names the trigger and the key.
3. Controller: fixtures with `branches: [master, dev]` under `push`, and with a mapping value for `workflow_dispatch`, each produce exactly one problem.
4. Controller: fixtures with an upload `path` of `out/` and with `if-no-files-found: warn` each produce exactly one problem.
5. Controller: a fixture whose Linux job lacks `Run gate zig-test` produces a problem, and so does one whose Linux job places it after the cross builds.
6. Controller: case `FP-0051 3` keeps passing, and under a mutation that changes the zlib fixture's expected pattern, its one assertion message lists all four outcomes.

Cases 1 to 5 must fail before the change, except the parts of case 1 that already hold.
A mutation control that removes the key check from `gateWorkflowProblems` must fail case 2.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0067/raw/`.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob IDs of every staged file.
2. `mutation.log` and its diff for each mutation control, with the hash of each changed file before, during, and after.
3. `controller-tests-after.log` with `node tools/fairpane.mjs test`.
4. Keep each failed attempt as its own log.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`.
After the push, the integrator records `gh run view` of the first `Gates` run that contains the change, downloads its Linux receipts with `gh run download` through `record`, and commits them under `engineering/evidence/FP-0067/ci/`.
The Linux `zig-test` receipt must report `pass`.

## Authority

Writable paths: `tools`, `tests`, `.github`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No new gate, threshold, runner, or action, and no change to `REVIEWED_ACTIONS`.
- No retry inside the compiler installer.
- No change to the verifier's behavior.

## Amendments

1. The first `Gates` run with the change, run 37936609533 of `152ed53`, timed out in `zig-test` on the Linux job after 600004 ms, so its Linux receipt cannot report `pass`.
   `ci/` records that run.
   The suite's cost, not this task's change, exceeds the gate's timeout, and `FP-0098` owns it.
   The acceptance record becomes the first `Gates` run after `FP-0098` lands whose Linux `zig-test` receipt reports `pass`; the integrator records it under `ci/` with `gh run view` and the Linux receipts, and the review re-checks that record.
   Review 1's other findings are handled as `reviews/review-1-reject.json` and the README record.
