# FP-0014 continuous integration record

`docs/AGENT_OPERATIONS.md` requires that a failed `Gates` run be recorded in the evidence of each task that awaits acceptance and whose implementation the run's head contains.
FP-0014 awaited acceptance when `Gates` run 37931192952 failed on `9cc81ea`, which contains its first implementation, `ef8ad1c`.

`ci-record.log` records `gh run view` of that run and of four nearby runs, and it downloads the failed run's Windows receipts into `run-37931192952/`.
These receipts are unsigned local integrity records from the runner, not attestations.

| Run | Head | Windows `zig-test` step | Conclusion |
| --- | --- | --- | --- |
| 37930649863 | `dfa6563` | 12:34:35Z to 12:38:49Z | success |
| 37931192952 | `9cc81ea` | 12:41:05Z to 12:51:06Z | failure |
| 37931504508 | `d17abb0` | 12:43:55Z to 12:51:31Z | success |
| 37932243183 | `1409e8b` | 12:49:53Z to 12:56:29Z | success |
| 37933043253 | `ba759f7` | 12:56:32Z to 13:01:15Z | success |

In run 37931192952, the Windows `zig-test` receipt reports `timed_out: true` after 600164 ms, the gate's 600000 ms limit, and the gate captured no build output.
Its Linux job and every other Windows gate passed.
`9cc81ea` changes only plan, state, handoff, and evidence files, so its Zig sources equal those of `dfa6563`, whose run passed in 4 minutes 14 seconds.
The passing Windows `zig-test` steps above took between 4 minutes 14 seconds and 7 minutes 36 seconds.

The record cannot tell a slow runner from an intermittent hang, because the gate kept no output from the stopped build.
`1409e8b` and `ba759f7` contain FP-0014 revision 1, and their runs passed.
`FP-0098` owns the timeout margin and the missing output.
