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
Run 37952850522 of `a2dd9ed` timed out at 120,572 milliseconds while the suite was running its test 223 of 224: the last result line of the receipt log is `ok 222`.
`engineering/evidence/ci/run-37952850522-attempt-1/` keeps that attempt's Windows receipts; the integrator downloaded them with `gh run download` before the rerun but did not record that command, so the directory lists them with their SHA-256 values.
Attempt 2 of the same head passed, with the controller-test step at 63,566 milliseconds, as `engineering/evidence/ci/run-37952850522.log` and `engineering/evidence/ci/run-37952850522/` record.
That gate is outside this task's criteria, which cover `zig-test`; plan commit `a1b28f6` gives it to FP-0107.

## Revision 1 series on `57df855`

Review 2 (`../reviews/review-2-reject.json`) asks for a new series on a head that contains revision 1 (`0276268`), with the build summary's phase durations.
The integrator started ten runs with `gh workflow run Gates --ref master` while `master` was at `57df855cb9b99b0e557f4e4e4462963248219300`, at most two at a time.
`../../ci/dispatch-57df855/dispatch-01.log` to `dispatch-10.log` record each `gh workflow run` with its exit status.
`../../ci/runs-57df855.log` records `gh run view` of every `Gates` run created from 18:40 UTC to 20:18:17 UTC, each with `headBranch`, `event`, `headSha`, `attempt`, its conclusion, and each gate step's duration in seconds: the push runs 37978329724 of `96bad1c` and 37980317371 of `57df855`, and the ten dispatched runs.
All twelve concluded `success` on both jobs, and none has a second attempt.
`../../ci/run-<id>-download.log` records the `gh run download` of both jobs' receipts for each dispatched run into `../../ci/run-<id>/`.

Each dispatched run has `headBranch` `master`, event `workflow_dispatch`, `headSha` `57df855…9300`, and attempt 1.
The step times come from the run view and the receipt times from each `zig-test` receipt's `duration_ms`.
The phase times are copied verbatim from the build summary in each `zig-test` receipt log: the unit-test binary is `run test 311 pass (311 total)` with its `compile test debug native` step, and the text-test binary is `run test 61 pass (61 total)` with its compile step.

| Run | Event, attempt | Conclusion | Windows `zig-test` step (s) / receipt (ms) | Linux `zig-test` step (s) / receipt (ms) | Windows unit-test run / compile | Windows text-test run / compile | Linux unit-test run / compile | Linux text-test run / compile |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 37980331388 | `workflow_dispatch`, 1 | `success` | 210 / 209,420 | 141 / 141,639 | 1m / 16s | 2s / 7s | 1m / 1s | 1s / 961ms |
| 37980365447 | `workflow_dispatch`, 1 | `success` | 185 / 184,430 | 182 / 181,441 | 1m / 24s | 1s / 6s | 1m / 4s | 2s / 1s |
| 37981462017 | `workflow_dispatch`, 1 | `success` | 213 / 212,204 | 253 / 253,458 | 1m / 26s | 3s / 8s | 2m / 4s | 3s / 2s |
| 37981495878 | `workflow_dispatch`, 1 | `success` | 175 / 173,917 | 254 / 254,122 | 56s / 15s | 1s / 7s | 2m / 3s | 3s / 1s |
| 37982663784 | `workflow_dispatch`, 1 | `success` | 162 / 160,857 | 260 / 260,127 | 50s / 12s | 1s / 6s | 2m / 4s | 3s / 2s |
| 37982698002 | `workflow_dispatch`, 1 | `success` | 207 / 206,646 | 254 / 254,267 | 1m / 17s | 3s / 8s | 2m / 3s | 3s / 1s |
| 37983552427 | `workflow_dispatch`, 1 | `success` | 221 / 219,600 | 261 / 260,391 | 1m / 17s | 2s / 7s | 2m / 2s | 3s / 1s |
| 37983811379 | `workflow_dispatch`, 1 | `success` | 203 / 201,886 | 256 / 256,461 | 59s / 16s | 2s / 5s | 2m / 5s | 3s / 2s |
| 37984731953 | `workflow_dispatch`, 1 | `success` | 191 / 190,133 | 135 / 134,742 | 59s / 21s | 1s / 8s | 1m / 2s | 1s / 655ms |
| 37984880613 | `workflow_dispatch`, 1 | `success` | 207 / 206,981 | 185 / 184,688 | 1m / 16s | 1s / 9s | 1m / 2s | 1s / 1s |

- Item 2: the slowest `zig-test` step is 221 s on Windows and 261 s on Linux, both at most 400 s.
- Item 4: every Windows receipt log has `Build Summary: 101/101 steps succeeded; 378/378 tests passed`, and every Linux receipt log has `Build Summary: 103/103 steps succeeded; 378/378 tests passed`.
  The summary in both jobs shows that `ZIG_BUILD_SUMMARY: all` reached `zig build` on CI.
- Item 5: the locked runner prints whole minutes at or above 60 s and whole seconds at or above 1 s (`Maker.zig:3028-3031`), so `1m` means 60 to 119 s, `2m` means 120 to 179 s, and `56s` means 56.0 to 56.9 s.
  The Windows unit-test run takes 50 s to 119 s across the series, and the Linux unit-test run takes 60 s to 179 s.
- Item 6: the step and test counts are the same in every run of each host.
  Linux has two more steps than Windows in every run.
  [INFERENCE] The difference comes from host-specific steps of `build.zig`, and the 378 tests are the same on both hosts.
- Every receipt has the `zig-test` gate digest `277b10a2…`.
- Item 7: `../raw/integration-binding-r1.log` records `HEAD` `0276268` and a status that includes ignored files for every source root, before and after `repo-check` (`../gates/2026-10-09T20-28-29-695Z-repo-check-6cd567d7.json`, pass) and `controller-test` (`../gates/2026-10-09T20-28-30-159Z-controller-test-b81afd46.json`, pass, 238 of 238).
  The integrator recorded it after the fact, in a temporary detached worktree of `0276268` that it removed afterward.
  `../raw/integration-binding-r1-attempt-1.log` and its receipts record the first attempt, whose `controller-test` failed only FP-0079 case 9, because the integrator had linked the worktree's `.tools` to the main checkout's and the Rust check rejects a symbolic link; attempt 2 used no `.tools`.
- Item 8: `../../ci/README.md` "Extension through `9df8680`" records the run ledger.
