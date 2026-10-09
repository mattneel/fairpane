# FP-0098 CI record

The contract requires the integrator to start the `Gates` workflow on `master` at least ten times after the push, record each run with `gh run view`, and report each Windows and Linux `zig-test` step's duration.
The task is accepted only when every run passes and the slowest of those durations is at most 400 seconds, two thirds of the 600-second timeout.

## Runs

The integrator started ten runs with `gh workflow run Gates --ref master` while `master` was at `29a9f8e1cc1dde5e249226f6b2237e8387493f88`, which contains the implementation commit `9d5638b`.
`dispatched-runs.log` records a Node script that lists the `workflow_dispatch` runs of that head with `gh run list` and reads each with `gh run view`.
It prints one JSON line for each run, with each job's conclusion and each gate step's duration in seconds, and a summary line.

| Run | Conclusion | Windows `zig-test` (s) | Linux `zig-test` (s) | Windows `controller-test` (s) | Linux `controller-test` (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| 37942087557 | success | 105 | 129 | 55 | 15 |
| 37942091945 | success | 134 | 133 | 86 | 12 |
| 37942095716 | success | 175 | 114 | 73 | 12 |
| 37942099056 | success | 169 | 188 | 71 | 14 |
| 37942103315 | success | 143 | 186 | 79 | 15 |
| 37942106938 | success | 191 | 187 | 79 | 14 |
| 37942110608 | success | 174 | 145 | 78 | 12 |
| 37942113826 | success | 177 | 181 | 78 | 13 |
| 37942117669 | success | 131 | 146 | 59 | 12 |
| 37942121418 | success | 175 | 186 | 75 | 14 |

All ten runs conclude with `success`.
The slowest `zig-test` step takes 191 seconds on Windows and 188 seconds on Linux, both at most 400 seconds.
The push run of the same head, 37942079501, also passes.

## Controller-test duration

The `controller-test` gate has a 120-second timeout.
In these runs its Windows step takes 55 to 86 seconds, and its Linux step takes 12 to 15 seconds.
After later tasks added controller tests, the Windows step took 62 to 121 seconds on the push runs of the heads from `775d988` to `a6ac7aa`; `engineering/evidence/ci/runs-2026-10-09.log` records every run and attempt since 13:00 UTC with each gate step's duration.
Run 37952850522 of `a2dd9ed` timed out at 120,572 milliseconds while the suite was at its test 222 of 224.
`engineering/evidence/ci/run-37952850522-attempt-1/` keeps that attempt's Windows receipts; the integrator downloaded them with `gh run download` before the rerun but did not record that command, so the directory lists them with their SHA-256 values.
Attempt 2 of the same head passed, with the controller-test step at 63,566 milliseconds, as `engineering/evidence/ci/run-37952850522.log` and `engineering/evidence/ci/run-37952850522/` record.
That gate is outside this task's criteria, which cover `zig-test`; the integrator proposes a separate task for it in a reviewed plan change.
