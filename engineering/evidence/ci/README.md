# Gates failure ledger

## Scope and acceptance status

This ledger covers the twelve failed attempts in [runs-2026-10-09.log](runs-2026-10-09.log), starting at 2026-10-09T13:00:00Z.
Its source and window boundary is `a1b28f6ed4b061ccf983976dc6047ac2c353676c`, the worker's base and current head.
It does not name or claim an acceptance commit.

The rule is [docs/AGENT_OPERATIONS.md, lines 85–104](../../../docs/AGENT_OPERATIONS.md#git-operations).
[The operations approval record](../operations/README.md) records the independent approval of that rule.
A timeout is a failure.
An unrelated later success does not cover a failure.

The supplied inventory ends at `483a239`.
[runs-ledger-snapshot.log](runs-ledger-snapshot.log) records a read-only `gh run list` at 2026-10-09T16:41:29Z.
[task-windows-attempt-2.log](task-windows-attempt-2.log) intersects that inventory with ancestors of the boundary and selects each task's window by Git ancestry, not by a run's completion time.
There are 69 runs and 72 attempts in this snapshot since 13:00Z: the original 59 runs, ten later push runs, and three second attempts.
The twelve failed attempts are retained below, including the first attempts of runs whose second attempts pass.

Three failures have concluded passing attempts of the same run and head.
The other nine have a technically supported replacement at `29a9f8e`, **conditional on FP-0098's acceptance before each affected task's acceptance**, or on predating `fairpane-review` records for every fixing commit, as the rule permits.
At this boundary, `engineering/state.json` records FP-0098 as `active`, with `review: null`, and its evidence directory has no review record.
The ten passing dispatched runs are execution evidence, not approval of the fix or acceptance of FP-0098.
The nine replacements therefore remain blocking until that approval condition is met.

Four later runs were unconcluded at the snapshot.
All nine task windows contain them.
Their conclusions, and any additional pushed heads before acceptance, must be recorded before acceptance.
This ledger does not count an in-progress run as successful.

| Run | Head | Snapshot status |
| --- | --- | --- |
| [37959730629](https://github.com/mattneel/fairpane/actions/runs/37959730629) | `2982ab1` | `in_progress`; no conclusion |
| [37960105177](https://github.com/mattneel/fairpane/actions/runs/37960105177) | `7861102` | `in_progress`; no conclusion |
| [37960447300](https://github.com/mattneel/fairpane/actions/runs/37960447300) | `1682d32` | `in_progress`; no conclusion |
| [37960610495](https://github.com/mattneel/fairpane/actions/runs/37960610495) | `a1b28f6` | `in_progress`; no conclusion |

## Failed attempts

Each run link below opens its own recorded attempt-1 job record.
Those records contain the full head, job ID, step number, step name, conclusion, and timestamps.
The retained `run-<run>-attempt-1-console.log` files record the corresponding read-only `gh run view --attempt 1 --log-failed` commands.
Some console lines say `UNKNOWN STEP`; the step names below come from the job records, not from that console label.

`Z` means the evidenced `zig build test` timeout and the **[INFERENCE]** attribution to case 46's quadratic DOM-chain setup, described under “Zig timeout cause.”
`C` means the observed controller-suite timeout described under “Controller timeout cause.”
`R` means the proposed replacement at full head `29a9f8e1cc1dde5e249226f6b2237e8387493f88`, with the approval condition above still open.

| Failed run | Attempt | Head | Failed gate and step from that attempt | Cause and evidence | Disposition |
| --- | ---: | --- | --- | --- | --- |
| [37934034077](run-37934034077-attempt-1-jobs.log) | 1 | `4531b333e4b70fad15c39d3d051324c34da959fd` | Windows job `113831497379`; `zig-test`; step 8, `Run gate zig-test`, 601 s | Z [INFERENCE]. The frozen FP-0098 contract records a timeout with no build output; the attempt-1 console names `zig build test`. | Covered by [the same run's attempt 2](run-37934034077-attempt-2-jobs.log), which concludes `success` on this exact head. Its Windows `zig-test` step passes in 396 s. This head predates every pending task's implementation. |
| [37935108213](run-37935108213-attempt-1-jobs.log) | 1 | `d52621966e4cd1b38d43a72c8e901f88c93d6262` | Windows job `113835085155`; `zig-test`; step 8, `Run gate zig-test`, 601 s | Z [INFERENCE]. The frozen FP-0098 contract records a timeout with no build output; the attempt-1 console names `zig build test`. | Covered by [the same run's attempt 2](run-37935108213-attempt-2-jobs.log), which concludes `success` on this exact head. Its Windows `zig-test` step passes in 594 s. |
| [37936361001](run-37936361001-attempt-1-jobs.log) | 1 | `a3e5cf941688d5f045ec060e8c6b1219b6a86b23` | Windows job `113839299277`; `zig-test`; step 8, `Run gate zig-test`, 601 s | Z [INFERENCE]. The [Windows receipt](run-37936361001-attempt-1/windows/2026-10-09T13-26-42-254Z-zig-test-b738264e.json) records `timed_out: true`, 600104 ms, and no captured build output. | R, conditional. See [this replacement range](ranges/a3e5cf9-to-29a9f8e.log). The added Linux gate does not alter the failed Windows job. |
| [37936609533](run-37936609533-attempt-1-jobs.log) | 1 | `152ed53a8d2164a4cfd53099fa1962f687be6631` | Windows job `113840127307` and Linux job `113840127653`; `zig-test`; step 8, `Run gate zig-test`, in both; 601 s and 600 s | Z [INFERENCE]. The [Windows receipt](run-37936609533-attempt-1/windows/2026-10-09T13-28-38-181Z-zig-test-6f133c4f.json) records 600137 ms; the [Linux receipt](run-37936609533-attempt-1/linux/2026-10-09T13-25-06-849Z-zig-test-2a5f5d8f.json) records 600004 ms and `SIGKILL`. Both time out and keep no build output. | R, conditional, covering both failed jobs. See [this replacement range](ranges/152ed53-to-29a9f8e.log). |
| [37936849509](run-37936849509-attempt-1-jobs.log) | 1 | `f38fe6c772775a09c625b05049be6b8691b35d35` | Linux job `113840930991`; `zig-test`; step 8, `Run gate zig-test`, 600 s | Z [INFERENCE]. The [Linux receipt](run-37936849509-attempt-1/linux/2026-10-09T13-27-07-827Z-zig-test-61b8f7fd.json) times out at 600004 ms with `SIGKILL` and no build output. | R, conditional. See [this replacement range](ranges/f38fe6c-to-29a9f8e.log). |
| [37937485293](run-37937485293-attempt-1-jobs.log) | 1 | `45acde8bd09df957515b75962f29ab2f5632feb0` | Linux job `113843091014` and Windows job `113843091619`; `zig-test`; step 8, `Run gate zig-test`, in both; 600 s and 601 s | Z [INFERENCE]. The [Linux receipt](run-37937485293-attempt-1/linux/2026-10-09T13-32-27-223Z-zig-test-46a89bbd.json) records 600004 ms and `SIGKILL`; the [Windows receipt](run-37937485293-attempt-1/windows/2026-10-09T13-36-07-309Z-zig-test-8381f25d.json) records 600116 ms. Both time out and keep no build output. | R, conditional, covering both failed jobs. See [this replacement range](ranges/45acde8-to-29a9f8e.log). |
| [37937802499](run-37937802499-attempt-1-jobs.log) | 1 | `bb25dcf912de3ab4595c3329e8437da4714b28c6` | Linux job `113844169417`; `zig-test`; step 8, `Run gate zig-test`, 600 s | Z [INFERENCE]. The [Linux receipt](run-37937802499-attempt-1/linux/2026-10-09T13-35-15-118Z-zig-test-a67e3054.json) times out at 600005 ms with `SIGKILL` and no build output. | R, conditional. See [this replacement range](ranges/bb25dcf-to-29a9f8e.log). |
| [37940691005](run-37940691005-attempt-1-jobs.log) | 1 | `f40a90261a4f8ce9007c68508138b6831c787e27` | Linux job `113853993177`; `zig-test`; step 8, `Run gate zig-test`, 600 s | Z [INFERENCE]. The [Linux receipt](run-37940691005-attempt-1/linux/2026-10-09T13-58-45-138Z-zig-test-1da977e2.json) times out at 600005 ms with `SIGKILL` and no build output. | R, conditional. See [this replacement range](ranges/f40a902-to-29a9f8e.log). |
| [37941142815](run-37941142815-attempt-1-jobs.log) | 1 | `54cf4d4d21bfc9a0fd421c8e6f3ba32d2247f6fb` | Linux job `113855526840`; `zig-test`; step 8, `Run gate zig-test`, 600 s | Z [INFERENCE]. The [Linux receipt](run-37941142815-attempt-1/linux/2026-10-09T14-02-23-464Z-zig-test-07339c10.json) times out at 600004 ms with `SIGKILL` and no build output. | R, conditional. See [this replacement range](ranges/54cf4d4-to-29a9f8e.log). |
| [37941186240](run-37941186240-attempt-1-jobs.log) | 1 | `cced395e9d5b16f058ae3734c6bb28edc0183a6e` | Linux job `113855672477` and Windows job `113855672860`; `zig-test`; step 8, `Run gate zig-test`, in both; 600 s and 601 s | Z [INFERENCE]. The [Linux receipt](run-37941186240-attempt-1/linux/2026-10-09T14-02-43-633Z-zig-test-4238426d.json) records 600004 ms and `SIGKILL`; the [Windows receipt](run-37941186240-attempt-1/windows/2026-10-09T14-06-55-185Z-zig-test-521dac32.json) records 600172 ms. Both time out and keep no build output. | R, conditional, covering both failed jobs. See [this replacement range](ranges/cced395-to-29a9f8e.log). |
| [37941436385](run-37941436385-attempt-1-jobs.log) | 1 | `e84e578345c6e6a1f77cd8ef1753301f3bf100dc` | Linux job `113856530770`; `zig-test`; step 8, `Run gate zig-test`, 600 s | Z [INFERENCE]. The [Linux receipt](run-37941436385-attempt-1/linux/2026-10-09T14-04-44-812Z-zig-test-e028c916.json) times out at 600005 ms with `SIGKILL` and no build output. | R, conditional. See [this replacement range](ranges/e84e578-to-29a9f8e.log). |
| [37952850522](run-37952850522-attempt-1-jobs.log) | 1 | `a2dd9ed40124bfd8997880c3631867f506dc8bfc` | Windows job `113895812024`; `controller-test`; step 6, `Run gate controller-test`, 121 s | C. The [receipt](run-37952850522-attempt-1/2026-10-09T15-38-51-214Z-controller-test-a8dcfbd8.json) records a 120572 ms timeout while the [log](run-37952850522-attempt-1/2026-10-09T15-38-51-214Z-controller-test-a8dcfbd8.log) has completed `ok 222` and has a live Git `cat-file --batch` descendant. | Covered by [the same run's attempt 2](run-37952850522-attempt-2-jobs.log), which concludes `success` on this exact head. Its [controller receipt](run-37952850522/2026-10-09T15-58-51-294Z-controller-test-243c0687.json) passes in 63566 ms, with identical source, policy, and gate digests. |

### Zig timeout cause

[FP-0014's CI record](../FP-0014/ci/README.md) records the earlier 37931192952 timeout and explains that no captured build output distinguishes a slow runner from an intermittent hang.
That earlier run predates this ledger's 13:00Z boundary and every listed pending implementation.
It is cause history, not an omitted failure in these windows.
[FP-0098's frozen contract](../FP-0098/CONTRACT.md#measured-inputs) also records the first two failures above as stopped `zig build test` commands with `timed_out: true` and no build output.
Their attempt-1 console logs are retained here, but this directory does not contain their original attempt-1 raw receipts.
Their disposition relies on exact same-head passing attempts, not on a replacement.

The twelve newly downloaded failing `zig-test` receipts for the nine replacement attempts are summarized in [failed-receipt-summary-attempt-2.log](failed-receipt-summary-attempt-2.log).
Each receipt says `timed_out: true`, runs `build test`, and has unchanged source-before and source-after digests.
Each corresponding raw gate log contains zero build-output lines between the command and its result.
The summary recomputes each log's SHA-256 and records the receipt's matching output hash.
The receipts are unsigned local integrity records, not attestations.
Recorded read-only downloads are `run-<run>-attempt-1-download-<host>.log`.

The local profile and source evidence identifies a cost in the command that failed:

- [test-profile-before.log](../FP-0098/raw/test-profile-before.log) records FP-0014 case 46 at 167071.659 ms, 88.7% of the 247-unit-test total.
- [probe-case46-parts.log](../FP-0098/raw/probe-case46-parts.log) records its 100000-element chain at 177806.055 ms, versus 36.474 ms for nested parentheses and 1246.378 ms for chained custom-property references.
- [The source](../../../src/css/tests.zig) keeps `depth = 100000` and appends each element beneath the preceding element. The `zig build test` unit-test run includes that CSS test; [build.zig](../../../build.zig) attaches the unit-test binary to the `test` step.
- [The fixing diff](fix-history.log) shows the former `Store.isInclusiveAncestor` walk. Every new leaf's pre-insert check walked from its parent to the root. Summing those walks over 100000 appends costs about five billion parent lookups.
- [timeout-source-identity-attempt-2.log](timeout-source-identity-attempt-2.log) binds all eleven failed Zig heads to the same CSS-test blob, `96068291c3019347323452987653aeab2b48262e`, and the same pre-fix DOM blob, `37667a5f31e00f429eabbaae5eb2274642623d6d`. The build, gate definitions, and Zig lock also have identical blobs across those heads and the replacing head.

**[INFERENCE]** That quadratic chain setup consumed the failed command's timeout margin on each of the eleven Zig failures.
The source identity, measured local cost, near-limit passing attempts, and faster fixed-head runs support this attribution for the failed `zig build test` step on both hosts.
No failed-run process listing or build output establishes the particular inner build step or test that was running when those commands stopped.
The attribution is not promoted to an observed CI diagnosis.

### Controller timeout cause

Attempt 1 of 37952850522 is a separate failure, not a recurrence of the Zig cost.
Its receipt runs Node's `tools/selftest.mjs`, has `timed_out: true`, and fails at 120572 ms against the unchanged 120000 ms gate limit.
The log has `ok 222`, then the timeout result, rather than a completed suite or a test assertion failure.
Its timeout process listing records the live Node suite and Git `cat-file --batch` descendants.
**[INFERENCE]** The suite exceeded its aggregate timeout while its next corpus-fetch case was active; the record does not establish why the runner was slower or prove a deadlock.

The [attempt-1 provenance note](run-37952850522-attempt-1/README.md) states that its artifact download was not recorded and that the rerun replaced that artifact.
[run-37952850522.log](run-37952850522.log) records the second attempt and its receipt download.
The failed and passing controller receipts have the same source digest `9089b0288fc46eb06ce421b2fe402ef7175d972c9f19a70b4c12478502661514`, policy digest `ea0669104222d035a4cf5318aab1824d6fccce518ac8a6704d14965d7b99724e`, and gate digest `43baf0f82e3b5e8ecbf8985681f0a95032043886401b52f736735ca9bf3cdef2`.
Attempt 2 passes the full run on the same head and does not need a fixed-head exception.
The record does not claim that this rerun fixes the cause.

## Proposed fixed-head replacement

### Replacing head and fixing commits

The replacing head is `29a9f8e1cc1dde5e249226f6b2237e8387493f88`.
Its push run 37942079501 and its ten dispatched runs all conclude `success` in [the original inventory](runs-2026-10-09.log).
[FP-0098's dispatched-run record](../FP-0098/ci/dispatched-runs.log) records the ten full workflow conclusions and both hosts' `zig-test` steps.
It reports a maximum of 191 s on Windows and 188 s on Linux, below the unchanged 600 s timeout and the contract's 400 s ceiling.

| Dispatched run at `29a9f8e` | Attempt | Conclusion | Windows `zig-test` (s) | Linux `zig-test` (s) |
| --- | ---: | --- | ---: | ---: |
| 37942087557 | 1 | success | 105 | 129 |
| 37942091945 | 1 | success | 134 | 133 |
| 37942095716 | 1 | success | 175 | 114 |
| 37942099056 | 1 | success | 169 | 188 |
| 37942103315 | 1 | success | 143 | 186 |
| 37942106938 | 1 | success | 191 | 187 |
| 37942110608 | 1 | success | 174 | 145 |
| 37942113826 | 1 | success | 177 | 181 |
| 37942117669 | 1 | success | 131 | 146 |
| 37942121418 | 1 | success | 175 | 186 |

[fix-history.log](fix-history.log) records `git log` and the changes of these commits:

| Commit | Role and change |
| --- | --- |
| `9d5638b241f16807bf197a80db80a6eb7f635b04` | FP-0098 implementation and source fix. `isInclusiveAncestor` answers self and childless-node cases directly, keeps the ancestor walk as the reference path for all other inputs, and adds the all-pairs equivalence test. It also adds timeout process listings, controller tests, and an optional profiling runner. |
| `29a9f8e1cc1dde5e249226f6b2237e8387493f88` | FP-0098 evidence revision and replacing head. It records the integrated binding and passing gates and removes a private directory listing from evidence. It changes no `src`, `tests`, gate-runner, or build source. The speed fix is in `9d5638b`, not in that evidence deletion. |

The [leaf-shortcut probe](../FP-0098/raw/probe-case46-parts-leaf-shortcut.log) reduces the unchanged chain part to 2164.506 ms.
[The after profile](../FP-0098/raw/test-profile-after.log) records case 46 at 2786.094 ms and compares all profile names: 292 before, 293 after, none missing, one added.
[FP-0098's integration evidence](../FP-0098/README.md#integration) records a fresh-cache run with all 65 build steps and 300 tests passing at `9d5638b`.
These records support the cost fix without reducing the test denominator.
They do not supply the independent approval condition.

### Every replacement-rule condition

The following check applies to each of the nine ranges listed below, not just to the implementation head.

| Rule condition | Evidence and result |
| --- | --- |
| Every pushed-head run in the task's implementation-to-pre-acceptance window must conclude. | **Open at this snapshot.** The task-window records retain every supplied attempt and add ten later push runs through `a1b28f6`. Four later runs were still in progress. No acceptance is claimed. |
| The replacing head is later in the affected task's window and contains both its implementation and the fix. | The ancestry enumeration in `task-windows-attempt-2.log` shows that `29a9f8e` contains the implementations of FP-0079, FP-0064, FP-0067, and FP-0081, the four tasks with pre-fix failures, and is an ancestor of the boundary. The fixing history places `9d5638b` before `29a9f8e`. Later task windows do not use this earlier head to cover their controller failure. |
| Name the failed gate and step from that failed run's own record. | Each attempt-1 job record names `Run gate zig-test`, step 8, and the failed host or hosts. The failure table retains each job ID. The downloaded receipts independently name `zig-test` and `build test`. |
| Tie the cause to that step on the failed sources; mark missing-output attribution [INFERENCE]. | The common pre-fix DOM and CSS blobs are recorded for every failed Zig head. The local profiles and split probe identify the chain cost inside a test run by that build step. Every Zig attribution above is explicitly [INFERENCE], because the failed commands kept no build output. |
| Each fixing implementation and revision belongs to a task accepted earlier, or has its own predating `fairpane-review` record. | **Open.** FP-0098 is active and has no review record in this base. `9d5638b` and its evidence revision `29a9f8e` must be covered by FP-0098's earlier acceptance, or by the rule's review alternative, before a replacement covers an affected acceptance. Ten passing runs do not satisfy this condition. |
| The fixing task's evidence shows that the cause no longer fails the gate; an intermittent cause has at least ten concluded runs, or a larger frozen count. | The before/after probes preserve case 46 and reduce its setup cost. The frozen FP-0098 contract requires ten dispatched runs, all passing, with the slowest step at most 400 s. Its ten recorded runs pass at `29a9f8e`, with maxima of 191 s and 188 s. This is the required execution sample, not review approval. |
| The fixing commits remove, skip, exclude, or weaken no test, gate, timeout, or threshold. | `9d5638b` adds 55 lines to `src/dom.zig` with no deletion, including the equivalence test. It keeps case 46's source and depth unchanged and does not change `build.zig` or gate definitions. `29a9f8e` changes evidence only. The profile comparison loses no test. The runner change still marks a timeout as failure; its listing does not increase the passing deadline. |
| No intervening commit changes the failed gate entry, its workflow job, its locked toolchain, or weakens a test it runs. | Each range log includes both endpoint diffs and path history. Gate definitions, toolchains, and `build.zig` have no changes. Eight ranges have no workflow change. The earliest range has only FP-0067's added Linux `zig-fmt` and `zig-test` steps; the failed Windows job is unchanged. The source history contains only `f40a902`, when not already in the failed head, and `9d5638b`. Neither removes or skips a test; their source audit is below. |
| Include the protected-path and test-source statistics, and explain every runner or build change. | Each range log records all commands listed below. There are no deleted source/test/build files and zero removed `test "` declarations in every range. `fix-history.log` records per-commit changes as well, so an endpoint diff cannot hide an intermediate change. The only runner change is `9d5638b`, explained below; there is no build change. |
| If a runner or build change could make the replacing run pass, use only a same-head passing rerun. | The `9d5638b` runner change acts only after `timedOut` has been set, and the unchanged success predicate rejects `timed_out: true`. The ten dispatched replacing runs' `zig-test` steps finish in at most 191 s, before that new timeout-only path can run. No such confounding runner/build change was found in these ranges. |
| A cancelled run needs a concluded run of the same head. | None of the twelve failed attempts is cancelled; each concludes `failure`. The four unconcluded snapshot runs are not assigned a conclusion. |

### Required range records

Each log below records these commands with `node tools/fairpane.mjs record <log> <exe> <args...>` and preserves each command's output and exit status:

```text
git diff --stat <failed>..29a9f8e -- engineering/gates.json .github/workflows toolchains tools/lib.mjs build.zig
git log --oneline <failed>..29a9f8e -- engineering/gates.json .github/workflows toolchains tools/lib.mjs build.zig
git diff --stat --diff-filter=D <failed>..29a9f8e -- src tests build.zig
node -e <recorded script searching git diff for removed test declarations> <failed>..29a9f8e
git diff --stat <failed>..29a9f8e -- src tests build.zig
git diff <failed>..29a9f8e -- engineering/gates.json .github/workflows toolchains tools/lib.mjs build.zig
git diff <failed>..29a9f8e -- src tests build.zig
```

The search reads `git diff <range> -- src tests build.zig` and reports removed lines matching `/^-(?!-).*\btest\s+"/`, with their file headers.
Every required command exits with 0.
The full diffs are retained, not just the empty-deletion or declaration counts.

| Failed head to replacing head | Recorded log | Protected/build/runner paths changed | Test-source diff | Deleted source/test/build files; removed `test "` lines |
| --- | --- | --- | --- | --- |
| `a3e5cf9..29a9f8e` | [a3e5cf9-to-29a9f8e.log](ranges/a3e5cf9-to-29a9f8e.log) | `.github/workflows/gates.yml`: six added Linux-only lines in `152ed53`; `tools/lib.mjs`: `9d5638b` | Nine files, 1106 insertions and 27 deletions; FP-0081 source change plus FP-0098 | None; 0 |
| `152ed53..29a9f8e` | [152ed53-to-29a9f8e.log](ranges/152ed53-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Nine files, 1106 insertions and 27 deletions; FP-0081 source change plus FP-0098 | None; 0 |
| `f38fe6c..29a9f8e` | [f38fe6c-to-29a9f8e.log](ranges/f38fe6c-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Nine files, 1106 insertions and 27 deletions; FP-0081 source change plus FP-0098 | None; 0 |
| `45acde8..29a9f8e` | [45acde8-to-29a9f8e.log](ranges/45acde8-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Nine files, 1106 insertions and 27 deletions; FP-0081 source change plus FP-0098 | None; 0 |
| `bb25dcf..29a9f8e` | [bb25dcf-to-29a9f8e.log](ranges/bb25dcf-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Nine files, 1106 insertions and 27 deletions; FP-0081 source change plus FP-0098 | None; 0 |
| `f40a902..29a9f8e` | [f40a902-to-29a9f8e.log](ranges/f40a902-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Only `src/dom.zig`, 55 insertions and no deletion | None; 0 |
| `54cf4d4..29a9f8e` | [54cf4d4-to-29a9f8e.log](ranges/54cf4d4-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Only `src/dom.zig`, 55 insertions and no deletion | None; 0 |
| `cced395..29a9f8e` | [cced395-to-29a9f8e.log](ranges/cced395-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Only `src/dom.zig`, 55 insertions and no deletion | None; 0 |
| `e84e578..29a9f8e` | [e84e578-to-29a9f8e.log](ranges/e84e578-to-29a9f8e.log) | Only `tools/lib.mjs`, in `9d5638b` | Only `src/dom.zig`, 55 insertions and no deletion | None; 0 |

### Intervening source and workflow changes

`fix-history.log` records `git log -p --reverse a3e5cf9..29a9f8e -- src tests build.zig` and the protected-path per-commit history.
Only two commits change those source paths:

- `f40a902` adds FP-0081's engine-allocation budget, C ABI memory operations, and tests. It changes no CSS or DOM-chain test. Existing status arrays grow from 10 to 13 and 14 to 16; engine destruction remains exercised after the added memory calls. The generated engine-options size checks change from 16 to 24 to match the extended schema, rather than deleting the size checks. Its test additions and existing assertions are retained. It changes no build step, gate, timeout, test filter, skip, or exclusion.
- `9d5638b` adds the DOM shortcut and its all-pairs reference test. It does not delete or alter an existing test or assertion. `src/css/tests.zig` remains byte-identical, including case 46's depth and checks.

In `a3e5cf9..29a9f8e`, `152ed53` changes the Linux workflow job by adding `zig-fmt` and `zig-test` after `controller-test`.
The failed `a3e5cf9` step belongs to the Windows job.
That job, its runner, its command, and its compiler lock are unchanged.
No Linux workflow changes occur after the other eight failed heads.

### Every gate-runner or build-step change

[The recorded runner/build history](fix-history.log) names **only `9d5638b`** in the largest replacement range for `tools/lib.mjs` or `build.zig`.
Every smaller range has that same single runner commit.
No commit in any replacement range changes `build.zig`.
`04342e2` also changes `tools/lib.mjs` earlier in history, but it is an ancestor of every replacement's failed head and is not an intervening commit.

The `9d5638b` runner diff:

1. Adds `listProcessTree`, the Windows and Linux process-table readers, and the bounded timeout log section.
2. Sets `timedOut = true` at the original watchdog deadline, then awaits the listing before stopping the process tree.
3. Moves the existing tree-stop actions into `stopProcessTree` without changing their kill behavior.
4. Passes the optional test-only `processListing` argument through `runGate` to `runProcess`.

It does not change the Zig executable, build arguments, environment, output-capture mechanism, ordinary completion path, or gate success predicate.
A command that ends while the listing is awaited still has `timed_out: true`; `runGate` still requires exit code 0, no signal, no timeout, and no error.
The additional listing delay can postpone the stop, but cannot turn a deadline-crossing command into a passing gate.
All replacing Zig steps finish before the unchanged deadline, so the new listing path cannot account for those passes.
The speed change is in `src/dom.zig`, not in the gate runner.

## Pending-task windows

Every window is inclusive of its implementation head and ends at `a1b28f6`, not at a convenient later success.
The counts below include the ten dispatched runs where the implementation is an ancestor of `29a9f8e`.
Their recorded enumeration is `task-windows-attempt-2.log`.
Each window also has the four unconcluded runs listed at the start of this ledger.
`R` retains the approval condition; it does not mean already covered.

### FP-0079

Window: `04342e208c571655f92f85fd67f9c52b09f13c67` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 67 runs, including 57 push runs, and 69 attempts.
The implementation's run 37934334536 passes.
Revision `d2c1e5b113cd808be8c72251804a2748b3aa090e` has passing run 37939274821, but does not reset the window or discard its earlier failures.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37935108213/1 | `d526219` | Same run and head, passing attempt 2 |
| 37936361001/1 | `a3e5cf9` | R, conditional |
| 37936609533/1 | `152ed53` | R, conditional, both jobs |
| 37936849509/1 | `f38fe6c` | R, conditional |
| 37937485293/1 | `45acde8` | R, conditional, both jobs |
| 37937802499/1 | `bb25dcf` | R, conditional |
| 37940691005/1 | `f40a902` | R, conditional |
| 37941142815/1 | `54cf4d4` | R, conditional |
| 37941186240/1 | `cced395` | R, conditional, both jobs |
| 37941436385/1 | `e84e578` | R, conditional |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0064

Window: `cb8427dd974b096a409f88eddb9993dbaab9ba1b` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 65 runs, including 55 push runs, and 67 attempts.
The implementation's run 37935038508 passes.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37935108213/1 | `d526219` | Same run and head, passing attempt 2 |
| 37936361001/1 | `a3e5cf9` | R, conditional |
| 37936609533/1 | `152ed53` | R, conditional, both jobs |
| 37936849509/1 | `f38fe6c` | R, conditional |
| 37937485293/1 | `45acde8` | R, conditional, both jobs |
| 37937802499/1 | `bb25dcf` | R, conditional |
| 37940691005/1 | `f40a902` | R, conditional |
| 37941142815/1 | `54cf4d4` | R, conditional |
| 37941186240/1 | `cced395` | R, conditional, both jobs |
| 37941436385/1 | `e84e578` | R, conditional |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0067

Window: `152ed53a8d2164a4cfd53099fa1962f687be6631` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 57 runs, including 47 push runs, and 58 attempts.
The implementation's run 37936609533 fails in both Zig jobs and is retained here.
[The task-specific CI record](../FP-0067/README.md#acceptance-run) also preserves its failed Linux receipt and the first fixed-head passing receipt at `9d5638b`.
This general ledger prefers the ten-run head `29a9f8e` for the rule's replacement evidence.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37936609533/1 | `152ed53` | R, conditional, both jobs |
| 37936849509/1 | `f38fe6c` | R, conditional |
| 37937485293/1 | `45acde8` | R, conditional, both jobs |
| 37937802499/1 | `bb25dcf` | R, conditional |
| 37940691005/1 | `f40a902` | R, conditional |
| 37941142815/1 | `54cf4d4` | R, conditional |
| 37941186240/1 | `cced395` | R, conditional, both jobs |
| 37941436385/1 | `e84e578` | R, conditional |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0081

Window: `f40a90261a4f8ce9007c68508138b6831c787e27` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 46 runs, including 36 push runs, and 47 attempts.
The implementation's run 37940691005 fails in Linux `zig-test` and is retained here.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37940691005/1 | `f40a902` | R, conditional |
| 37941142815/1 | `54cf4d4` | R, conditional |
| 37941186240/1 | `cced395` | R, conditional, both jobs |
| 37941436385/1 | `e84e578` | R, conditional |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0098

Window: `9d5638b241f16807bf197a80db80a6eb7f635b04` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 40 runs, including 30 push runs, and 41 attempts.
The implementation's run 37941660067 passes.
Evidence revision `29a9f8e1cc1dde5e249226f6b2237e8387493f88` has passing push run 37942079501 and the ten passing dispatched runs above.
The earlier Zig failures do not fall inside this implementation window.
The later controller failure does.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2; no fixed-head exception needed |

### FP-0052

Window: `775d988c75435779d4bab06b978391204d86e216` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 21 push runs and 22 attempts.
The implementation's run 37946697623 passes.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0066

Window: `81481a373eed462a345fdd640870abd5743bb179` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 20 push runs and 21 attempts.
The implementation's run 37947113000 passes.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0082

Window: `5d415099314da59835b1ab8566b1f7b30addfdcb` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 17 push runs and 18 attempts.
The implementation's run 37948992671 passes.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| 37952850522/1 | `a2dd9ed` | Same run and head, passing attempt 2 |

### FP-0076

Window: `d56bc5fdb256a756bd7b724053d6106931c4c036` through `a1b28f6ed4b061ccf983976dc6047ac2c353676c`.
There are 14 push runs and 14 attempts.
The implementation's run 37953728033 passes.
The controller failure at `a2dd9ed` predates this implementation and is outside this window.

| Failed attempt in window | Head | Disposition |
| --- | --- | --- |
| None in the concluded snapshot attempts | Not applicable | No failed-attempt disposition is needed; the four unconcluded runs still prevent a complete acceptance-window claim. |

## Collection failures and next acceptance action

No test, gate, build, formatter, or lint command was run while writing this ledger.
The commands here inspect recorded evidence, Git history, and GitHub run records only.
No workflow was pushed, rerun, dispatched, or cancelled by the worker.

Three initial collection scripts failed before collecting their intended facts:
[task-windows.log](task-windows.log) and [timeout-source-identity.log](timeout-source-identity.log) have incorrectly escaped regular expressions, and [failed-receipt-summary.log](failed-receipt-summary.log) has an incorrectly escaped path separator.
Each failure remains recorded, with exit code 1, beside its successful `-attempt-2.log` replacement.
They are collection errors, not additional Gates failures.

Before an affected task is accepted, record FP-0098's earlier acceptance or the rule's predating-review alternative, then record the conclusions of the four snapshot-pending runs and every later pushed head through the actual pre-acceptance head.
Any newly failed or cancelled attempt needs its own cause and permitted disposition.
This record preserves the nine open replacement conditions rather than silently treating them as satisfied.

## Extension through `0276268`

The integrator extended this ledger on 2026-10-09 after the run of `0276268` concluded.
`0276268` is the latest pushed head, so it is the pre-acceptance head of every acceptance commit that the next push carries; no later commit had been pushed.

### Runs after the snapshot

[runs-2026-10-09-extension.log](runs-2026-10-09-extension.log) records every `Gates` run created from 16:30 to 17:40 UTC with `gh run view` of each attempt and each gate step's duration.
It holds 15 runs, from `4d11e84` to `0276268`, one attempt each.
The four runs that were in progress at the snapshot, 37959730629 (`2982ab1`), 37960105177 (`7861102`), 37960447300 (`1682d32`), and 37960610495 (`a1b28f6`), concluded `success`.
Every other run concluded `success` except run 37962020941 of `66d71bd`.

### Run 37962020941 of `66d71bd`

- Failed gate and step: `Run gate repo-check` failed in both jobs after about a second, and every later gate step was skipped, as the job record in the extension log shows.
- Cause: plan commit `66d71bd` replaced the third criterion of `FP-0107` without its trailing comma, so `engineering/plan.json` did not parse and `node tools/fairpane.mjs check` failed.
  The integrator's check before that commit reported `Expected ',' or ']' after array element in JSON at position 170636 (line 3512 column 9)`, but the commit command did not stop on it; that output was not recorded with the record tool, and the failed `repo-check` step of this run is the recorded evidence.
  The cause is deterministic, so no repeated runs are needed.
- Fix: `f5be48f` restores the comma and changes nothing else.
  [ranges/66d71bd-to-f5be48f.log](ranges/66d71bd-to-f5be48f.log) shows that the diff of `engineering/gates.json`, `.github/workflows`, `toolchains`, `tools/lib.mjs`, and `build.zig` over the range is empty, and that the whole range diff is that one line of `engineering/plan.json`.
- Review record: plan review 4, [../plan/reviews/review-4-reject.json](../plan/reviews/review-4-reject.json), approves `f5be48f` as only restoring the comma, and calls itself the `fairpane-review` record that the rule needs for this fixing commit.
- Disposition: the passing run 37962198818 of `f5be48f` replaces a rerun of `66d71bd`.

### The nine zig-test replacements

The condition that this ledger left open is now met by the rule's review alternative.
[../FP-0098/reviews/fix-review-approve.json](../FP-0098/reviews/fix-review-approve.json) is a `fairpane-review` verdict, `approve`, scoped to the fixing commits `9d5638b` and `29a9f8e`.
It finds that they fix the recorded cause and remove, skip, exclude, or weaken no test, gate, timeout, or threshold.
It predates every acceptance that relies on it.
[fix-commits-name-status.log](fix-commits-name-status.log) records the complete file list of both commits, as that review asked: `9d5638b` changes `src/dom.zig`, `tools/README.md`, `tools/lib.mjs`, `tools/selftest.mjs`, `tools/zig/test_profile_runner.zig`, and evidence files, and `29a9f8e` changes evidence files only.
The ten dispatched runs of `29a9f8e` remain the repeated-run evidence that the cause no longer fails the gate.
The nine replacements at `29a9f8e` therefore cover their failures for every task whose window holds them.

### Windows through `0276268`

| Task | Implementation | Failed attempts in its window | Disposition |
| --- | --- | --- | --- |
| `FP-0079` | `04342e2` | `d526219` attempt 1; the nine zig-test failures; `a2dd9ed` attempt 1; `66d71bd` | Same-head attempt 2; replacement at `29a9f8e`; same-head attempt 2; replacement at `f5be48f` |
| `FP-0064` | `cb8427d` | The same as `FP-0079` | The same |
| `FP-0067` | `152ed53` | The zig-test failures from `152ed53` on, `a2dd9ed` attempt 1, and `66d71bd` | Replacement at `29a9f8e`; same-head attempt 2; replacement at `f5be48f` |
| `FP-0081` | `f40a902` | The zig-test failures from `f40a902` on, `a2dd9ed` attempt 1, and `66d71bd` | The same |
| `FP-0052` | `775d988` | `a2dd9ed` attempt 1 and `66d71bd` | Same-head attempt 2; replacement at `f5be48f` |
| `FP-0066` | `81481a3` | The same as `FP-0052` | The same |
| `FP-0076` | `d56bc5f` | `66d71bd` | Replacement at `f5be48f` |

Every other run of every window concluded `success`.
`FP-0098` and `FP-0082` are not in this table: `FP-0098` still needs its revision's ten dispatched runs, and `FP-0082` waits for revision 2.

## Extension through `5859de7`

The integrator extended this ledger on 2026-10-09 after the push run of `5859de7` concluded.
`5859de7` is the latest pushed head, so it is the pre-acceptance head of every acceptance commit that the next push carries.

### Runs after the previous extension

[runs-2026-10-09-extension-2.log](runs-2026-10-09-extension-2.log) records `gh run view` of every `Gates` run created from 17:40 to 20:44:08 UTC, with each attempt and each gate step's duration.
It holds 27 runs, one attempt each, and all completed: the push runs of `588b5bc`, `07aa602`, `3e7128c`, `96bad1c`, `57df855`, `9df8680`, and `5859de7`, the ten dispatched runs of `3e7128c`, and the ten dispatched runs of `57df855`.
Every run concluded `success` except the eleven runs of `3e7128c`.
[runs-3e7128c.log](runs-3e7128c.log) and [runs-57df855.log](runs-57df855.log) record the same runs of those two series.
[pushes-through-5859de7.log](pushes-through-5859de7.log) lists the commits that each of the seven pushes carried.
The seven ranges hold 62 commits, as many as `0276268..5859de7` holds, so these seven heads are the only pushed heads after `0276268`.
For example, `ecdd343` reached `origin` in the push of `5859de7`.

### The eleven runs of `3e7128c`

- Failed attempts: push run 37971989978 and dispatched runs 37972006869 to 37974347550, attempt 1 each.
- Failed gate and step: in every one, `Run gate controller-test` failed in the Windows job after 31 to 47 seconds, every later Windows gate step was skipped, and the Linux job passed.
  The Windows receipts in [run-37971989978-attempt-1/](run-37971989978-attempt-1/) and [run-37972006869-attempt-1/](run-37972006869-attempt-1/) each report 43 failures of 240 cases, and each failure names the missing `git`.
- Cause: the concurrent runner of `FP-0107` (`13168dc`) gave each worker thread a case-sensitive copy of `process.env`, so a case on a worker found no search path when the environment named it `Path`.
  [INFERENCE] The hosted Windows runner names the search path `Path`.
  With that name, [../FP-0107/raw/r1-repro-before.log](../FP-0107/raw/r1-repro-before.log) fails 45 of 247 cases locally on the base of revision 1, and each failure names the missing `git`.
  [../FP-0107/raw/tests-before-r1.log](../FP-0107/raw/tests-before-r1.log) identifies that base as `9dfb13e`.
  The range log records that `3e7128c` and `9dfb13e` have the same runner blob, `0bde3642`, and that `tools/selftest.mjs` only gains 20 lines between them.
  The cause is deterministic, so one passing run of a fixed head suffices.
- Fix: FP-0107 revision 1, `d4de685`, names the search path `PATH` and the system root `SystemRoot` in each worker's copy, and adds revision 1 case 3, which reads `process.env` on a worker when the search path is named `Path`.
  Revision 2, `0cf7c95`, declares five cases that change `TMPDIR`, `TMP`, and `TEMP`, and passes each case module's declarations through.
- Range: [ranges/3e7128c-to-96bad1c.log](ranges/3e7128c-to-96bad1c.log) lists the 16 commits from the failed head to the replacing head `96bad1c`, the files of `9dfb13e`, `f585679`, and `d4de685`, and the rule's two `git diff --stat` commands.
  The commands that the fix review asked for follow them.
  - The diff of `engineering/gates.json`, `.github/workflows`, `toolchains`, `tools/lib.mjs`, and `build.zig` changes only `build.zig`, with 13 insertions and 3 deletions.
    The log's `git log -p` of `build.zig` shows that `84ffa53` (FP-0082 revision 2) passes `--replace` to the two census steps and that `b68eebf` (FP-0123) adds six laboratory fixtures and their cases.
    Neither change can make the replacing run's `controller-test` step pass.
    At `96bad1c`, the gate runs `node tools/selftest.mjs` (`tools/lib.mjs:742`), and the log's `git grep` commands find `build.zig` in no file under `tools` except `tools/README.md`.
  - The diff of the controller suite's sources, `tools/selftest.mjs`, `tools/test-runner.mjs`, and `tools/*.test.mjs`, changes four files in `d4de685`, `84ffa53`, and `6cf88af`, with 172 insertions and 10 deletions.
    The log's `git log --stat` and `git diff -U0` of those files record the attribution and every deleted line.
    One deleted line is the worker construction that `d4de685` replaces, and three are file comments.
    The other six are FP-0108's frozen amendments of FP-0013 cases 3 and 49: each name gains "(amended by FP-0108 case N)", the count of eight UCD files becomes an exact list of eleven, the version header check gains `emoji-data.txt`'s version on line 8, and grapheme segmentation moves from remaining to implemented by `FP-0108`.
  - [ranges/3e7128c-to-96bad1c-cases.log](ranges/3e7128c-to-96bad1c-cases.log) compares the case names of the failed Windows receipt with the replacing run's Windows receipt in [run-37978329724/](run-37978329724/).
    The replacing run passes all 248 of its cases.
    The only names of the failed run's 240 cases that it lacks are FP-0013 cases 3 and 49, which it runs under their amended names.
  - [ranges/96bad1c-to-0cf7c95.log](ranges/96bad1c-to-0cf7c95.log) records that the diff of the five paths is empty for revision 2, and that revision 2 changes six files of the suite by ten lines each way.
- Review record: the `fairpane-review` fix review of `d4de685` and `0cf7c95`, [../FP-0107/reviews/fix-review-approve.json](../FP-0107/reviews/fix-review-approve.json), approves both commits and predates every acceptance that relies on it.
  Its three minor findings asked for the range log's later commands, which this section now cites.
  FP-0107 review 2, [../FP-0107/reviews/review-2-accept.json](../FP-0107/reviews/review-2-accept.json), also accepts revisions 1 and 2 apart from criterion 3, the CI time bound.
- Disposition: the passing push run 37978329724 of `96bad1c`, which contains `d4de685`, replaces the reruns of `3e7128c`.
  The eleven passing runs of `57df855`, which contains `0cf7c95`, confirm the fix.
  The time bound of FP-0107 criterion 3 is a separate matter of that task: the Windows `controller-test` step of `57df855` took 49 to 104 seconds, within the gate's 120-second timeout.

### Windows through `5859de7`

| Task | Implementation, first pushed head | Failed attempts in its window | Disposition |
| --- | --- | --- | --- |
| `FP-0082` | `5d41509`, `5d41509` | `a2dd9ed` attempt 1; `66d71bd`; the eleven runs of `3e7128c` | Same-head attempt 2; replacement at `f5be48f`; replacement at `96bad1c` |
| `FP-0098` | `9d5638b`, `9d5638b` | The same as `FP-0082` | The same |
| `FP-0108` | `6cf88af`, `96bad1c` | None | — |
| `FP-0119` | `077ad63`, `96bad1c` | None | — |
| `FP-0123` | `b68eebf`, `96bad1c` | None | — |
| `FP-0100` | `f17b396`, `9df8680` | None | — |
| `FP-0131` | `9b47a37`, `5859de7` | None | — |

Every other run of every window concluded `success`.
`FP-0106` has no pushed head yet, so its window begins with the next push.
