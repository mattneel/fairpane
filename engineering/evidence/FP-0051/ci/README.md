# FP-0051 continuous integration record

Review 1 inferred that FP-0051 case 4 would fail on the project's `windows-2025` GitHub Actions job, because that runner's `TEMP` path uses the short name `RUNNER~1`.
It also noted that no CI run of the implementation was recorded.
The `Gates` workflow did fail that case on every push from the first FP-0051 implementation until revision 1, and the integrator recorded the runs on 2026-10-09.

`ci-record.log` records `gh run view` of each run below.
`run-37876621365/` and `run-37884049814/` hold the Windows gate receipts of the first failing run and the first passing run, downloaded with `gh run download` in the same log.
These receipts are unsigned local integrity records from the runner, not attestations.

| Run | Head commit | Created | Conclusion |
| --- | --- | --- | --- |
| 37876621365 | `71e0ad1` | 02:52:24Z | failure |
| 37876656755 | `101ba28` | 02:52:51Z | failure |
| 37883434686 | `18a21b3` | 04:20:42Z | failure |
| 37883549893 | `acd7a5a` | 04:22:09Z | failure |
| 37883713897 | `a033de3` | 04:24:15Z | failure |
| 37884049814 | `5f807f2` | 04:28:36Z | success |

In run 37876621365, the Windows `controller-test` receipt log reports `not ok 54 - FP-0051 4: A policy path inside the candidate fails even when a link leads outside`, with 141 of 142 tests passing.
The record keeps no receipts of the other four failing runs, so it shows only their conclusions, not their failing test.
In run 37884049814, the Windows `controller-test` receipt log reports 143 of 143 tests passing.

Revision 1, commit `9b878bc`, made the verifier resolve every policy ancestor, and `5f807f2` records its evidence.
CI runs only on each pushed head, and every pushed head from `71e0ad1` through `a033de3` failed.
The unpushed commits between `199b279` and `a033de3` contain the same case and verifier, so they would fail the same way [INFERENCE: CI did not run them].
Each of these commits passed the local gates on the development host, whose temporary directory has no short name.
History on `master` stays unchanged, as `docs/GIT_OPERATIONS.md` requires.
