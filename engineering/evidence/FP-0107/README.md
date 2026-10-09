# FP-0107 evidence

## Scope

Task `FP-0107` keeps the `controller-test` gate within its timeout on Windows.
The frozen contract is `engineering/evidence/FP-0107/CONTRACT.md`, frozen at `01d7e39`.
The worker implemented it in an isolated working tree whose `HEAD` was `0276268879438531745c63ab497e80c0a1e69aa5`, which holds the FP-0052, FP-0082, and FP-0098 revisions of `tools/selftest.mjs`.
The Windows host was Windows 10.0.26200 on x64 with Node v26.7.0.
The Linux host was WSL Ubuntu on `Linux 7.2.6-locietta-WSL2-xanmod1 x86_64` with Node v26.7.0 at `$HOME/fairpane-linux/node/bin/node`.
`engineering/gates.json`, `.github/workflows/gates.yml`, and every other protected path are unchanged, so the gate keeps its arguments and its 120000 ms timeout.
[INFERENCE] Other agents ran builds on the same host, so every local duration includes some contention; no log records those builds.
[INFERENCE] The worker did not commit, push, or dispatch a workflow run; no log records that.

## Changes

- `tools/test-runner.mjs` (new): `runCases(cases, { write, concurrency, cleanup })` runs a list of cases, writes TAP lines through `write`, and returns `{ tests, pass, fail }`.
  It writes the duration report that "Duration report" describes.
  Up to `concurrency` ordinary cases run at once, 4 by default, and cases start in the order of their numbers.
  A case that declares `processWide` starts only when no other case runs, and no case starts until it ends.
  `casePool(moduleUrl, size)` starts worker threads that load `moduleUrl`, and `serveCases(cases, cleanup)` answers their requests in each worker.
- `tools/selftest.mjs`: `test(name, fn, { processWide })` records the declaration, and the case-module loops pass each module case's declaration on.
  The final loop is now a call of `runCases`: ordinary cases run on four worker threads through `casePool`, and declared cases run on the main thread.
  Each thread removes its own temporary fixtures, and each cleanup problem still counts as a failure.
  Seven existing cases declare their process-wide change, and FP-0107 cases 1 and 2 are new.
- `tools/attest.test.mjs` and `tools/release.test.mjs`: one case each declares its process-wide change as the third element of its array.
- `tools/README.md`: the new section "Run the controller tests".
- `engineering/decisions/0011-concurrent-controller-tests.md`: the decision to run the cases on worker threads, with its evidence and reversal condition.
- `raw/process-probe.mjs`, `raw/names.mjs`, `raw/cost.mjs`, and `raw/mutate.mjs`: evidence scripts, described under "Records".

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| The runner is an exported function that runs a list of cases with a writer and returns the counts, and `tools/selftest.mjs` calls it with its cases. | `runCases` in `tools/test-runner.mjs`; the call at the end of `tools/selftest.mjs`; `raw/baseline-test-diff.log`. |
| `# duration_ms <n> <ms>` after each result line, measured with `performance.now()` around the case's function and rounded down. | `runCases` measures from just before it calls the function to its settlement and writes `Math.floor` of the difference. Every profile log shows the line after each result line. |
| `# slowest` lines for the ten slowest cases, ties in ascending case number, after the summary lines, then `# duration_ms total`. | Every profile log ends with them; case 1 checks the order and the tie rule. |
| Case 1. | Fails in `raw/tests-before.log`, because `tools/test-runner.mjs` does not exist. Passes in `raw/profile-after.log`, `raw/profile-linux-after.log`, `raw/controller-tests-after.log`, and `raw/bun-selftest.log`. Fails under mutation control 2. |
| Case 2. | Cannot run on the base, and fails in `raw/tests-before.log` for the same reason as case 1. Passes in the four after logs. Fails under mutation control 1. |
| Each existing case that changes process-wide state declares it, and the runner never runs it beside another case. | See "Process-wide declarations". |
| Result lines keep the order of case numbers. | `raw/names.log` checks that every result line's number is its position in each log. |
| Every case on both hosts, before and after. | `raw/profile-before.log`, `raw/profile-after.log`, `raw/profile-linux-before.log`, and `raw/profile-linux-after.log`. |
| The cases that take most of the Windows time, their causes, and a cost reduction that keeps every assertion. | See "Test cost". |
| No case is removed, skipped, narrowed, merged, moved, or renamed. | `raw/names.log` and `raw/baseline-test-diff.log`; see "Every case and assertion kept". |
| Both mutation controls. | `raw/mutation.log`, `raw/mutation-1.diff`, and `raw/mutation-2.diff`; see "Mutation controls". |
| `node tools/fairpane.mjs test` passes. | `raw/controller-tests-after.log`. |
| Criterion 3: ten dispatched `Gates` runs pass, and the slowest Windows `controller-test` step takes at most 80 seconds. | Open; see "Open items". |

## Duration report

`runCases` writes `TAP version 13`, then each case's result line followed directly by `# duration_ms <n> <ms>`.
A failure's YAML block with its message follows the duration line.
After the last case, the runner runs `cleanup`, writes `1..<tests>` and the `# tests`, `# pass`, and `# fail` lines, then `# slowest <rank> <ms> <n> <name>` for the ten slowest cases, or for every case when there are fewer.
The order is descending by the printed `<ms>`, with ties in ascending case number.
The last line is `# duration_ms total <ms>`, from the start of `runCases` to the end of the slowest list.
`tools/selftest.mjs` then writes its scope line, as before.
A case's `<ms>` includes the time that it waits for a free worker or shares the processor with the cases beside it.
`tools/mutation-harness.mjs` still reads the message of a failed case, because `parseTap` skips the duration line.

## Process-wide declarations

These existing cases change process-wide state and declare it.
The numbers are the case numbers in the changed suite, which equal those in the base suite.

| Case | Declared state |
| --- | --- |
| 49, `14: Candidate identity comes from Git objects, ...` in `tools/attest.test.mjs` | `GIT_DIR and PATH in process.env` |
| 106, `FP-0027 case 5: reproduce-check reports reproducible ...` in `tools/release.test.mjs` | `ZIG_GLOBAL_CACHE_DIR and ZIG_LIB_DIR in process.env` |
| 173, `A failed output copy is recorded and its capture directory is removed` | `TMPDIR, TMP, and TEMP in process.env` |
| 175, `A completed command leaves no capture directory` | `TMPDIR, TMP, and TEMP in process.env` |
| 176, `Executable resolution never searches the process working directory` | `the working directory` |
| 204, `A replace ref that substitutes the recorded commit cannot make verification pass` | `GIT_OBJECT_DIRECTORY in process.env` |
| 231, `FP-0052 case 2: a taskkill.exe in the working directory does not stop the watchdog ...` | `NODE_OPTIONS in process.env on Windows, and the working directory` |
| 233, `FP-0052: a SystemRoot that cannot locate taskkill.exe fails runProcess ...` | `SystemRoot in process.env` |
| 235, `FP-0052 case 4: a fetch that cannot remove the old snapshot ...` | `the fs.rmSync function of the node:fs module` |

The worker found them by searching `tools/selftest.mjs` and the seven case modules for assignments to `process.env`, `Object.assign(process.env, ...)`, `process.chdir`, and assignments to members of `fs`, `console`, `os`, `child_process`, `globalThis`, and prototypes.
A search of the same files for `??=` and cache variables found no fixture that one case builds and another case reuses.
A declared case runs on the main thread while no worker runs a case.
A worker thread cannot change the working directory: `raw/probe-worker-chdir.log` shows `ERR_WORKER_UNSUPPORTED_OPERATION` for `process.chdir` in a worker.
[INFERENCE] Each worker gets its own copy of `process.env` and its own module instances when it starts, before any case runs, as the Node.js `worker_threads` documentation states; no log tests it.

Revision 2 declares five more cases that change `TMPDIR`, `TMP`, and `TEMP` in `process.env` through `withPrivateTemp`, which the worker's search missed because the helper makes the assignment.
Review 1 found them, and their numbers are those of the 248-case suite in `raw/tests-after-r2.log`.

| Case | Declared state |
| --- | --- |
| 185, `A capture-start failure writes a RESULT line, closes the log, and returns an error result` | `TMPDIR, TMP, and TEMP in process.env` |
| 190, `A failed capture-directory removal appears in the command record` | `TMPDIR, TMP, and TEMP in process.env` |
| 192, `FP-0054 case 6: a capture directory that stays busy ...` | `TMPDIR, TMP, and TEMP in process.env` |
| 193, `FP-0054 case 6: a capture-directory removal error with a non-transient code gets one attempt` | `TMPDIR, TMP, and TEMP in process.env` |
| 194, `FP-0054 revision 1 case 6: a capture-directory removal error without a code gets one attempt` | `TMPDIR, TMP, and TEMP in process.env` |

Revision 2 also lets `abi.test.mjs`, `fileset.test.mjs`, `rust.test.mjs`, `ucd.test.mjs`, and `workflow-check.test.mjs` pass a case's declaration through, as `attest.test.mjs` and `release.test.mjs` already did.

## Test cost

### Before

`raw/profile-before.log` runs the base cases one at a time with only the duration report applied.
`raw/profile-before.diff` is that change: `tools/test-runner.mjs`, with the final blob `0bde36422f21261ca2ebe2f254617b6045f40669`, and a final loop that calls `runCases` with `concurrency: 1` and the base cleanup.
On Windows, the 238 cases took 79426 ms, and their durations sum to 78728 ms.
On WSL Ubuntu, they took 17690 ms in `raw/profile-linux-before.log`.
`raw/cost.log` lists the ten slowest base cases on Windows.

| Rank | Case | Windows ms | Linux ms | Child processes in the probe | Cause |
| --- | --- | ---: | ---: | --- | --- |
| 1 | 103, FP-0027 case 2 | 3274 | 284 | 110 `git` | Git fixture processes |
| 2 | 161, FP-0098 case 1 | 3154 | 2211 | `node`, `powershell`, `taskkill` | 2-second gate timeout and the process listing |
| 3 | 234, FP-0052 case 3 | 3010 | 405 | 79 `git` | Git fixture and corpus processes |
| 4 | 208, a pinned revision in a fixture `corpora.json` | 2636 | 245 | 73 `git` | Git fixture and corpus processes |
| 5 | 202, verification fails when the license digest ... differs | 2479 | 264 | 67 `git` | Git fixture and corpus processes |
| 6 | 162, FP-0098 case 2 | 2358 | 2012 | `node`, `powershell`, `taskkill` | 2-second gate timeout and the listing attempt |
| 7 | 204, a replace ref | 2277 | 222 | 66 `git` | Git fixture and corpus processes |
| 8 | 229, corpus-repin against a local fixture upstream | 2246 | 259 | 57 `git` | Git fixture and corpus processes |
| 9 | 231, FP-0052 case 2 | 2201 | 1146 | 2 `taskkill`, `node`, `powershell` | 1-second watchdog timeout and the stop |
| 10 | 199, corpus-verify fails for a missing snapshot ... | 2019 | 297 | 56 `git`, 1 `node` | Git fixture and corpus processes |

### Cause

`raw/probe-process-starts.log` runs the same base tree with `raw/process-probe.mjs`, which counts each case's child processes through `node:child_process` and the time that synchronous calls block the thread.
The probe counted 1857 child processes, 1756 of them `git`, and 49295 ms in synchronous calls.
The 51 cases that start `git` took 63984 of the 78728 ms in the Windows base profile, or 81.3%; the 137 cases that start no child process took 971 ms.
On Linux, the seven Git cases of the table take 9% to 15% of their Windows time.
[INFERENCE] Their Windows cost is therefore mostly the start of each Git process, times the fixture's process count; no log times a single Git start.
The four cases with a process listing wait for a watchdog timeout of 250 ms, 1 second, or 2 seconds, and then for Windows PowerShell or `taskkill.exe`; their cost is the wait that they assert.
Synchronous calls, such as `spawnSync`, block the thread until the process ends.
[INFERENCE] Asynchronous concurrency within one thread therefore cannot overlap that time, so the change uses worker threads; no run measured concurrency within one thread.

### Change

The change runs independent cases concurrently, which the contract allows, and changes no case's function, fixture, or assertion.
Ordinary cases run on four worker threads, so a case that waits for a child process or a timeout no longer delays the cases on the other threads.
The nine declared cases run alone on the main thread, which keeps their process-wide changes from reaching other cases.

### After

On Windows, the 240 cases took 37968 ms in `raw/profile-after.log`, 48% of the 79426 ms before; their durations sum to 91755 ms, because the cases overlap.
`node tools/fairpane.mjs test` took 47936 ms in `raw/controller-tests-after.log`.
On WSL Ubuntu, the 240 cases took 11414 ms in `raw/profile-linux-after.log`, 65% of the 17690 ms before.
The slowest single case on Windows is case 208, at 3834 ms, so no single case approaches the timeout.
Eight of the ten slowest base cases took longer on their own than before, and cases 162 and 204 took about 3% less, as `raw/cost.log` shows.
[INFERENCE] The rise comes from sharing the processor with up to three other cases.

### Every case and assertion kept

- `raw/names.log` prints the ordered names of the base suite (238) and the changed suite (240).
  The first 238 names of the changed suite equal the base names in order, and the two added names are FP-0107 cases 1 and 2.
  The changed suite also equals the red baseline of `raw/tests-before.log`, and each suite has the same names on Windows and on WSL Ubuntu.
- `raw/baseline-test-diff.log` compares the staged red-baseline `tools/selftest.mjs`, `ebc67a1f`, with the final one, `5a12bf80`.
  The only changes are the runner import, the `test` signature, the third argument of the module loops, a declaration on the closing line of each of seven cases, and the final loop.
  No case function, fixture function, or assertion changed, and FP-0107 cases 1 and 2 are byte for byte those of the red baseline.
- In `tools/attest.test.mjs` and `tools/release.test.mjs`, only the closing line of the declared case and the `map` that builds the case objects changed.

## Mutation controls

`raw/mutation.log` records each control on `tools/test-runner.mjs`: `git hash-object` before, the mutation through `raw/mutate.mjs`, `git hash-object` during, `git diff --no-index` into the diff file, `node tools/selftest.mjs`, the restoration, and `git hash-object` after.

| Control | Diff | Blob before, during, after | Result |
| --- | --- | --- | --- |
| 1: ignore the declaration and run every case concurrently. The launch loop drops its limit and its exclusive check, and the declaration test becomes `if (false)`. | `raw/mutation-1.diff` | `0bde3642`, `af0aac90`, `0bde3642` | `node tools/selftest.mjs` exits with 1: 236 of 240 pass. FP-0107 case 2 fails with ""declared 1" ran from 26630.4578 to 26705.1017 ms while "ordinary 1" ran from 26630.4293 to 26705.0582 ms." Cases 173 and 175 fail, because other cases' fixture directories appear in their private temporary directory, and case 235 fails with the SystemRoot error of case 233. |
| 2: omit the `# duration_ms` line. | `raw/mutation-2.diff` | `0bde3642`, `fd27726e`, `0bde3642` | `node tools/selftest.mjs` exits with 1: 239 of 240 pass, and FP-0107 case 1 fails with "Result line 1 lacks its duration line". |

The `git diff --no-index` commands exit with 1, because the files differ, and each restoration exits with 0.

## Records

Every listed command ran through `node tools/fairpane.mjs record`, and the worker deleted or overwrote no log.

| Log | RESULT |
| --- | --- |
| `raw/tests-before.log` | See "Red baseline". |
| `raw/profile-before.log` | `git rev-parse HEAD` (0); `git archive` of `0276268` into `out/fp0107/base.tar` and `out/fp0107/before.tar` (0 each); `tar -xf` of both (0 each); the copy of `tools/test-runner.mjs` into the before tree (0); `git hash-object` (0): `0bde3642` for both runner copies, `56855970` for the base `tools/selftest.mjs`, and `07e4a243` for the before tree's; `git diff --no-index --output=raw/profile-before.diff` (1, because the trees differ); `git diff --no-index --stat` (1): 2 files, 196 insertions, 21 deletions; `git init`, `git add -A`, `git commit`, and `git rev-parse` in the before tree (0 each), with tree `d11ba662`; `node --version` (0), v26.7.0; `node tools/selftest.mjs` in the before tree (0): 238 of 238 pass in 79426 ms. |
| `raw/probe-process-starts.log` | `node --import=.../process-probe.mjs tools/selftest.mjs` in the before tree (0): 238 of 238 pass, with a `# probe` line after each duration line. |
| `raw/profile-linux-before.log` | `git archive HEAD` of the before tree into `out/fp0107/before-linux.tar` (0); under WSL, the extraction into `$HOME/fairpane-linux/work/FP-0107/before`, `git init`, `git add -A`, and `git commit` (0), with the copied tree `d11ba662`, which equals the Windows before tree, and the same two blobs; then `node tools/selftest.mjs` (0): 238 of 238 pass in 17690 ms. |
| `raw/profile-after.log` | `git rev-parse HEAD` (0), `0276268`; `git hash-object` (0): `tools/test-runner.mjs` `0bde3642`, `tools/selftest.mjs` `5a12bf80`, `tools/attest.test.mjs` `e92b75db`, `tools/release.test.mjs` `9f0d0882`; `node --version` (0); `node tools/selftest.mjs` (0): 240 of 240 pass in 37968 ms. |
| `raw/profile-linux-after.log` | `git add -A -- tools engineering/evidence/FP-0107` (0); `git write-tree` (0), `a0e2d041`; `git archive` of that tree (0); under WSL, the extraction into `$HOME/fairpane-linux/work/FP-0107/after` and a commit whose tree is `a0e2d041`, with the same four tool blobs (0); then `node tools/selftest.mjs` (0): 240 of 240 pass in 11414 ms. |
| `raw/names.log` | `node raw/names.mjs` (0); see "Every case and assertion kept". |
| `raw/mutation.log` | See "Mutation controls". |
| `raw/controller-tests-after.log` | `git rev-parse HEAD` (0); `git hash-object` (0) of the four tool files and `tools/README.md` `f6c2f8d3`; `node --version` (0); `node tools/fairpane.mjs test` (0): 240 of 240 pass in 47936 ms; `node tools/fairpane.mjs check` (0, `pass`). |
| `raw/bun-selftest.log` | `bun --version` (0), 1.4.2; `bun tools/selftest.mjs` (0): 240 of 240 pass in 45811 ms, so the worker threads also run under Bun. |
| `raw/baseline-test-diff.log` | `git diff --stat` and `git diff` of the two `tools/selftest.mjs` blobs (0 each). |
| `raw/cost.log` | `node raw/cost.mjs` (0): the profile totals, the probe totals, and the slowest base cases. |
| `raw/probe-worker-chdir.log` | `node -e` (0): a worker's `process.chdir` throws `ERR_WORKER_UNSUPPORTED_OPERATION`. |

Two runs of the changed suite were not recorded, because they preceded the profiles and served only to check the implementation.
The first stopped before any case with `ERR_WORKER_PATH`, because `new Worker` needs a `URL` object, not a URL string; `casePool` now passes `new URL(moduleUrl)`.
The second passed 240 of 240 cases.
Neither run supports a claim in this README.

### Red baseline

`raw/tests-before.log` runs these commands in order, after FP-0107 cases 1 and 2 were added to `tools/selftest.mjs` and before any other change.

1. `git rev-parse HEAD HEAD:tools/selftest.mjs HEAD:tools/lib.mjs`, `exit_code` 0: `HEAD` `0276268879438531745c63ab497e80c0a1e69aa5`, `tools/selftest.mjs` `56855970669e245ef1bd9dc71f746da4cc768f5d`, and `tools/lib.mjs` `7a2bd74a9c1e7477d769d5ed82d4dea26c3d04cd`.
2. `git status --short`, `exit_code` 0: only `tools/selftest.mjs` is modified, and `raw/` is new.
3. The staging command `git add -- tools/selftest.mjs`, `exit_code` 0.
4. `git ls-files --stage -- tools`, `exit_code` 0: the blob ID of every staged file under `tools`, with `tools/selftest.mjs` at `ebc67a1f083f11f6239d598970f5cacb5da55bd0`; the status of step 2 shows no other changed file under `tools`.
5. `git diff --cached --stat`, `exit_code` 0: 50 insertions in `tools/selftest.mjs`.
6. `node --version`, `exit_code` 0, v26.7.0.
7. `node tools/selftest.mjs`, `exit_code` 1: 238 of 240 pass, and FP-0107 cases 1 and 2 fail with "Cannot find module ...\tools\test-runner.mjs".
8. `git reset -q -- tools/selftest.mjs` and `git diff --cached --stat`, `exit_code` 0 each, which leave the index at `HEAD`.

## Integration

Commit `13168dc` applies the worker's `out/fp0107.patch`, blob `322cee895ab048d6d6f7edc22de7484116b79be1`, on `194739e`, and all 27 files apply cleanly.
No file under `src`, `tests`, or `build.zig` changes.

`raw/integration-binding.log` records `HEAD` `13168dc` and a status that includes ignored files before and after these gates:

| Gate | Receipt | Status | Duration |
| --- | --- | --- | --- |
| `repo-check` | `gates/2026-10-09T18-01-12-691Z-repo-check-17a98035.json` | pass | 840 ms |
| `controller-test` | `gates/2026-10-09T18-01-14-088Z-controller-test-7a9ee339.json` | pass, 240 of 240 | 51,743 ms |
| `zig-fmt` | `gates/2026-10-09T18-02-06-104Z-zig-fmt-954b51cf.json` | pass | 74 ms |
| `zig-test` | `gates/2026-10-09T18-02-06-479Z-zig-test-9b503199.json` | fail | 1,191 ms |

The failed `zig-test` run failed only the two FP-0082 case 17 census steps, with `PathAlreadyExists` for a `census.jsonl` that a run at 17:23 UTC had left in the local cache.
`engineering/evidence/FP-0082/raw/census-rerun-5-lost-manifest.log` and `census-rerun-6.log` reproduce that failure on purpose, and FP-0082 revision 2 amendment 1 owns the fix.
The integrator then removed the two stale output directories with an unrecorded `rm -rf`.
`raw/integration-binding-zig-test-2.log` records `HEAD` `13168dc` and the status before and after a second `zig-test` run, `gates/2026-10-09T18-11-24-103Z-zig-test-4c9ac18a.json`, which passes.
Bun 1.4.2 passes 240 of 240 cases in `raw/bun-selftest-integration.log` and `raw/bun-selftest-zig-test-2.log`.
The local `controller-test` total is 51,573 ms, against 37,968 ms in `raw/profile-after.log`.
[INFERENCE] Workers' builds were running on the host at the same time; the dispatched runs decide criterion 3.

## Open items

- The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`.
- After the push, the integrator starts the `Gates` workflow on `master` at least ten times, records each run, and downloads both jobs' receipts.
  `ci/README.md` then reports each run's Windows and Linux `controller-test` duration and the ten slowest cases of each job from the `# slowest` lines of the receipt logs.
  The task is accepted only when every run passes and the slowest Windows `controller-test` step takes at most 80 seconds.
- [INFERENCE] The hosted Windows runner has fewer processors than the development host, so its gain from four worker threads may be smaller than the 52% measured here; the dispatched runs decide criterion 3.

## Revision 1

The `Gates` push run 37971989978 and the ten dispatched runs 37972006869 to 37974347550 on `3e7128c` failed the Windows `controller-test` step, while every Linux job passed.
In run 37972006869, 43 Windows cases failed with "The executable is not on PATH: git" or "No git executable exists on PATH.".
A worker thread receives a copy of `process.env` whose names match with regard to letter case, and the development host's shell exports `PATH`, which hid the fault; [INFERENCE] the hosted Windows runner names the search path `Path`, as "Revision 2" explains.
The integrator implemented revision 1 and its amendment 1, as `CONTRACT.md` records.
`casePool` now passes each worker the copy that `workerEnvironment` returns, which on Windows names the search path `PATH` and the system root `SystemRoot`.

| Log | Command | Exit status and result |
| --- | --- | --- |
| `raw/r1-repro-before.log` | The suite at `9dfb13e` with the search path named `Path` | 1; 202 of 247 pass, and the failures name the missing `git`, as in CI |
| `raw/tests-before-r1.log` | `HEAD` `9dfb13e`, the staged `tools/selftest.mjs` with case 3, and the suite | 1; 247 of 248 pass, and only case 3 fails: "The worker read nothing as PATH, and the main thread read a value of 2709 characters." |
| `raw/tests-after-r1-attempt-1.log`, `raw/r1-repro-after-attempt-1.log`, `raw/bun-selftest-r1-attempt-1.log` | First attempt, `SHARE_ENV` | 1 each; `withPrivateTemp` cases see concurrent cases' directories |
| `raw/*-attempt-2.log` | Second attempt, `SHARE_ENV` and five more declarations | Node passes, and Bun fails four `withPrivateTemp` cases |
| `raw/r1-share-env-probe.log` | `raw/r1-share-env-probe.mjs` under Bun and Node | 0 each; only Bun with `SHARE_ENV` stops following `process.env` in `os.tmpdir()` |
| `raw/tests-after-r1.log` | `node tools/fairpane.mjs test` | 0; 248 of 248 |
| `raw/r1-repro-after.log`, `raw/bun-r1-repro-after.log` | Node and Bun with the search path named `Path` | 0 each; 248 of 248 |
| `raw/bun-selftest-r1.log` | Bun 1.4.2 | 0; 248 of 248 |
| `raw/tests-after-r1-repeat-1.log` to `-3.log` | Three more Node runs | 0 each; 248 of 248 |
| `raw/mutation-r1.log`, `raw/mutation-r1-M3.diff` | M3 removes the worker `env` option | 1; only case 3 fails, and `tools/test-runner.mjs` is `02fc9919` before and after and `81adfe43` during |

Two earlier recordings of `tests-before-r1.log` printed the host's whole search path in case 3's failure message, first through the message and then through `assert.equal`'s value diff.
They are withheld from the repository, and case 3 now reports only whether each value is present and its length, through `assert.ok`.

`raw/integration-binding-r1-binding.log` records `HEAD` `d4de685` and a status that includes ignored files before and after the four gates: `gates/2026-10-09T19-07-24-699Z-repo-check-e98f573b.json`, `gates/2026-10-09T19-07-25-511Z-controller-test-4c916c75.json` (248 of 248 in 61,330 ms), `gates/2026-10-09T19-08-27-291Z-zig-fmt-bbe5c452.json`, and `gates/2026-10-09T19-08-27-841Z-zig-test-5e6b3d66.json` pass.
[INFERENCE] Worker builds ran on the host during that gate, which explains its slower time.
`raw/bun-selftest-r1-binding.log` records Bun 1.4.2 with 248 of 248 cases.

## Revision 2

Review 1 (`reviews/review-1-reject.json`) rejects revision 1, because five `withPrivateTemp` cases change `process.env` without a declaration; revision 2 declares them, as "Process-wide declarations" lists, and closes the minor findings.

`engineering/evidence/ci/runs-3e7128c.log` records `gh run view` of every run created from 18:10 to 18:40 UTC: the push run 37971989978 and the ten dispatched runs of `3e7128c`.
In each of the 11, the Linux job passed, and the Windows job failed in `controller-test` after 31 to 47 seconds.
`engineering/evidence/ci/run-37971989978-attempt-1/` and `run-37972006869-attempt-1/` hold the Windows receipts, each with 43 failures of 240 cases that name the missing `git`.
[INFERENCE] The hosted Windows runner gives a worker its search path as `Path`: a local run with that spelling fails the same cases, and the fix that names it `PATH` passes on the runner in push run 37978329724 of `96bad1c`.

Each revision 2 log first records `HEAD` `0f187af` and the blob IDs of `tools/test-runner.mjs`, `tools/selftest.mjs`, and the five changed case modules.

| Log | Command | Exit status and result |
| --- | --- | --- |
| `raw/tests-after-r2.log` | `node tools/fairpane.mjs test` | 0; 248 of 248 |
| `raw/r2-repro-after.log` | Node with the search path named `Path` | 0; 248 of 248 |
| `raw/bun-selftest-r2.log` | Bun 1.4.2 | 0; 248 of 248 |
| `raw/bun-r2-repro-after.log` | Bun with the search path named `Path` | 0; 248 of 248 |
| `raw/mutation-r2.log`, `raw/mutation-r2-M3.diff` | M3 against the committed blob `02fc9919` | 1; only case 3 fails, and the file is `02fc9919` before and after and `81adfe43` during |

The two withheld recordings of `tests-before-r1.log` are kept outside the repository; their SHA-256 values are `289ee96ba12288c058f8bc340e97552f7948e167b0441386db20f7df9ac0f872` (80,932 bytes) and `4bc612e3fc717ec6ed3f567fc558fc0e99fbdfce1bc68ad23444902d78019b05` (77,349 bytes).
The "Test cost" figures predate revision 1; the dispatched runs decide criterion 3.

`raw/integration-binding-r2-binding.log` records `HEAD` `0cf7c95` and a status that includes ignored files before and after the four gates: `gates/2026-10-09T19-25-13-723Z-repo-check-c959d987.json`, `gates/2026-10-09T19-25-14-189Z-controller-test-0fd69255.json` (248 of 248), `gates/2026-10-09T19-26-01-852Z-zig-fmt-b7f6edc6.json`, and `gates/2026-10-09T19-26-02-233Z-zig-test-4d4218dc.json` pass.
`raw/bun-selftest-r2-binding.log` records Bun 1.4.2 with 248 of 248 cases.

## Revision 3

Revision 3 reduces the Git work of the controller-test fixture builders.
The base is `9307a36`, and the worker's patch is `out/fp0107-r3.patch` in its work tree.
The integrator's revision 3 amendment 1 turns the two local targets, half the child processes and a third less case time, into measurements without a bound, and it allows a tool change only where a tool starts one Git process per object or per query that one batched call can serve.
The dispatched runs of criterion 3 stay the only bound.

### Cost on the hosted Windows runner

`raw/cost-r3.log` runs `raw/r3-cost.mjs` over the ten Windows `controller-test` receipt logs of the `57df855` series that `engineering/evidence/ci/runs-57df855.log` lists.
The cases' median `# duration_ms` values sum to 155,881 ms, and the median step total is 61,522 ms.
The costliest medians are FP-0027 case 2 (case 103, 6,059 ms), the pinned-revision WPT case (212, 5,698 ms), FP-0052 case 3 (241, 4,436 ms), and the license-digest case (206, 4,293 ms).
Of the 25 costliest cases, 24 build Git fixtures: corpus snapshots, local upstreams, release commits, and, in FP-0051 case 3 (53), three attestation candidates.
The other one is FP-0098 case 1 (165), which waits for a gate timeout.

### Child processes by case and caller

`raw/process-probe.mjs` counts per case only under a runner that runs one case at a time, as its header states, and the suite now runs ordinary cases on four worker threads.
`raw/process-probe-r3.mjs` counts the same starts on every thread.
A worker writes its counts for a case into a shared buffer before it posts the case's result, and the main thread prints them after the case's duration line.
It also names the file of each start's first stack frame outside Node.js and the probe, so a start from a test file is told apart from a start by a tool under test.

`raw/probe-before-r3.log` runs the unchanged base, 253 of 253 cases passing, and counts 1,975 starts.
The tools under test start 987 of them: `corpus.mjs` 735, `attest.mjs` 186 (which includes the `git` calls of `release.mjs` through `readGit`), `lib.mjs` 54, `release.mjs` 11, and `fileset.mjs` 1.
The test files start 988: `selftest.mjs` 702, `release.test.mjs` 176, `attest.test.mjs` 90, and 20 in four other modules.
So no change to the test files alone can halve the count, which is why the integrator made the local targets measurements.

No tool changes.
The probe shows no tool that starts one Git process per object: `computeInventory` and `streamBlobs` in `tools/corpus.mjs` read every blob through one `git cat-file --batch`, `listTree` lists a commit with one `git ls-tree -r -z`, and `tools/release.mjs` hashes the tree's blobs with one `git cat-file --batch`.
The remaining tool calls are separate queries whose distinct failures the corpus and attestation checks report, such as `cat-file -t` before `cat-file commit` in `commitObject` and the `rev-parse` and `cat-file -e` sequence of `candidateIdentity`.
Folding them into one batched call would change which Git failure each check reports, so revision 3 keeps them.

### Changes

- `tools/git-fixture.mjs` (new): `writeFixtureTree(git, files)` writes the blobs of a fixture commit with one `git hash-object -w --no-filters --stdin-paths` and its trees with one `git mktree -z --batch`, where the base builders started one `git hash-object -w --stdin` per blob and one `git mktree -z` per tree.
  It writes each blob's bytes to a scratch file under the system temporary directory and removes the directory after `hash-object` returns.
  `--no-filters` keeps the bytes as `--stdin` did, which applies no filter.
  It computes each tree ID in Git's tree format and order and feeds the trees to `mktree` with each subtree first; `mktree` must print exactly those IDs, or the builder throws.
  It passes `--missing` when a file is a submodule, as the base did for the level that held the submodule.
  It returns the root tree and a lookup of each path's blob or submodule ID.
- `tools/selftest.mjs`:
  - `fixtureObjects` (new) calls `writeFixtureTree` and then `git commit-tree` with the base's arguments, and `fixtureCommit` returns its commit; `splitPath` moves into `tools/git-fixture.mjs`, and `addTree` there takes the place of `fixtureTree`.
  - `corpusFixture` builds the WPT manifest from the builder's blob IDs instead of one `git rev-parse <commit>:<path>` per manifest path; both give the blob ID of the path in the commit, and a missing path fails the fixture.
  - `bareRepo` takes `{ initialBranch }`, and `upstreamFixture` initializes its upstream with `--initial-branch=main` instead of a following `git symbolic-ref HEAD refs/heads/main`; both write `ref: refs/heads/main` into `HEAD`, which case 4 checks.
  - Revision 3 case 4 follows FP-0107 revision 1 case 3, so no existing case changes its number.
- `tools/release.test.mjs`: `commit` calls `writeFixtureTree` and then `git commit-tree` with the base's arguments, and `tree` moves into `tools/git-fixture.mjs`.
  `releaseFixtureBuilder` exports `repository` and `commit` for case 4.
- `tools/README.md`: "Run the controller tests" describes the shared builder.
- `raw/process-probe-r3.mjs`, `raw/r3-cost.mjs`, `raw/r3-probe.mjs`, and `raw/names-r3.mjs`: evidence scripts.

`attest.test.mjs`'s `fixtureRepository` is unchanged.
It commits through porcelain `git commit` with the host's clock, so its commit IDs differ on every run and case 4 could not hold them, and it starts eight processes per candidate.

### Changed builders and the cases that use them

Case numbers are those of the changed suite, which equal the base's for cases 1 to 253.
`raw/cost-r3.log` lists every case whose count changed; each one uses a builder below, and no other case changed its count.

| Builder | Cases |
| --- | --- |
| `writeFixtureTree` through `fixtureCommit` in `tools/selftest.mjs` | 198, 199, 200, 201, 202, 203, 208, 209, 213, 215, 232, 254 |
| `corpusFixture`, through `fixtureObjects`, with the manifest change | 203, 206, 207, 208, 210, 211, 212, 214, 215, 216, 217, 218, 219, 222 to 233, 254 |
| `upstreamFixture`, through `bareRepo` with `initialBranch` and `fixtureCommit` | 234, 235, 236, 241, 242, 243, 244, 248, 249, 254 |
| `commit` in `tools/release.test.mjs` | 102, 103, 104, 105, 109, and through `buildFixture` 106, 107, 110; 254 |

### Every changed line

`raw/assertions-r3.log` records `git add -N tools/git-fixture.mjs`, then `git diff --stat` and `git diff` of the three test files against `9307a36`: 3 files, 138 insertions, and 43 deletions.

- `tools/git-fixture.mjs`: all 69 lines are the new builder.
- `tools/release.test.mjs`: the import, the removed `tree`, the two-line body of `commit`, and the `releaseFixtureBuilder` export.
- `tools/selftest.mjs`: the two imports; `bareRepo`, `fixtureObjects`, and `fixtureCommit` in place of `bareRepo`, `splitPath`, `fixtureTree`, and `fixtureCommit`; the two changed lines and one added line of `corpusFixture`; the first line of `upstreamFixture` in place of its first two; and case 4 with its inputs, expected IDs, and `assertLoose`.

No other line changes, so every existing case keeps its name, its order, and every assertion; only the fixture builders that the cases call change.

### Case 4 and M4

Case 4 builds, from fixed inputs, a `fixtureCommit` commit with modes 100755 and 120000, a submodule, an empty blob, two equal blobs, non-ASCII and raw-byte paths, a tab, the hostile names of the extraction cases, and names that sort differently as trees and files, and a child commit of it.
It also builds `corpusFixture('wpt', WPT_FILES, { manifest: wptManifest })`, `upstreamFixture()` with one `move()`, and a release `commit` of the same files without the submodule.
It prints the IDs and asserts the commit and tree IDs, the WPT record's inventory digest, the manifest file's SHA-256, the upstream's `HEAD` text and `refs/heads/main`, and that every object that each commit reaches is a loose object file, which cases 208, 219, and 232 rely on.

`raw/tests-before-r3-attempt-1.log` added case 4 to the base with an empty expectation, so case 4 failed, 253 of 254 passed, and the base builders printed their IDs.
`raw/tests-before-r3.log` records `HEAD` `9307a36`, the blobs of `tools/selftest.mjs` (`2f1d729c`) and `tools/release.test.mjs` (`523d897a`) with those IDs filled in and no builder changed, and `node tools/fairpane.mjs test` with 254 of 254 passing and the base builders' IDs printed.
Every later run prints the same IDs and passes case 4.

`raw/mutation-r3.log` records M4: `git hash-object tools/git-fixture.mjs` `cdf29df2` before, `raw/mutate.mjs` makes the builder write `alpha, mutated` for any file named `a.txt` (`raw/mutation-r3-M4.diff`), `9eccb612` during, `node tools/fairpane.mjs test` with exit status 1, the restoration, and `cdf29df2` after.
Case 4 fails, and so do cases 103, 198, and 200, whose fixtures contain an `a.txt`; 250 of 254 pass.

### Measurements

Child processes, from `raw/cost-r3.log`:

| Count | Before | After | Change |
| --- | ---: | ---: | ---: |
| Starts in cases 1 to 253 | 1,975 | 1,448 | -527 (-26.7%) |
| `git` starts in cases 1 to 253 | 1,874 | 1,346 | -528 |
| Starts from `selftest.mjs` | 702 | 286 | -416 |
| Starts from `release.test.mjs` | 176 | 64 | -112 |
| Starts by the tools under test | 987 | 988 | +1 |
| Thread time blocked in synchronous starts | 68,496 ms | 38,935 ms | -43.2% |
| Case 4 | - | 42 | |

The one added tool start is a `taskkill` that `lib.mjs` starts in case 219, where the watchdog stops `git cat-file` after the extraction fails; `raw/probe-process-starts.log` shows the same start for that case, then numbered 215, in an earlier base.

Three runs each of `node tools/fairpane.mjs test` on Windows, from `raw/profile-before-r3.log` (the base with case 4) and `raw/profile-after-r3.log`:

| Run | Before total | Before case sum | After total | After case sum |
| --- | ---: | ---: | ---: | ---: |
| 1 | 50,539 ms | 124,017 ms | 39,945 ms | 93,411 ms |
| 2 | 49,713 ms | 122,147 ms | 40,548 ms | 96,233 ms |
| 3 | 56,239 ms | 139,894 ms | 37,177 ms | 87,359 ms |
| Median | 50,539 ms | 127,290 ms (sum of case medians) | 39,945 ms | 90,635 ms (sum of case medians) |

The sum of the case medians falls by 36,655 ms, or 28.8%, short of the third that the frozen revision named and that amendment 1 turns into a measurement.
The runs share the host with other work, which the spread of the before runs shows.
`raw/profile-linux-after-r3.log` runs the changed suite on WSL Ubuntu: 254 of 254 pass in 9,512 ms, and the case durations sum to 22,152 ms.

### Records

| Log | Commands and result |
| --- | --- |
| `raw/probe-before-r3.log` | `node --import=./engineering/evidence/FP-0107/raw/process-probe-r3.mjs tools/selftest.mjs` on the unchanged base (0): 253 of 253, 1,975 starts. |
| `raw/tests-before-r3-attempt-1.log` | `git rev-parse HEAD`, `git hash-object` of the two test files, and `node tools/fairpane.mjs test` (1): case 4 fails on its empty expectation and prints the base IDs. |
| `raw/tests-before-r3.log` | The same commands with the expected IDs (0): 254 of 254. |
| `raw/profile-before-r3.log` | `git rev-parse HEAD`, `git hash-object`, and three runs of `node tools/fairpane.mjs test` on the base with case 4 (0 each): 254 of 254 each. |
| `raw/probe-after-r3.log` | `git hash-object` of the three test files (`1157318e`, `3390b2a8`, `cdf29df2`) and the probe run on the changed suite (0): 254 of 254, 1,490 starts. |
| `raw/profile-after-r3.log` | `git rev-parse HEAD`, `git hash-object`, and three runs of `node tools/fairpane.mjs test` (0 each): 254 of 254 each. |
| `raw/profile-linux-after-r3.log` | With `GIT_INDEX_FILE=out/r3/index`: `git read-tree HEAD`, `git add -A -- tools engineering/evidence/FP-0107`, and `git write-tree` (0 each), tree `5c3d8625`; `git archive` of that tree (0); under WSL, the extraction into `$HOME/fairpane-linux/work/FP-0107-r3/after`, a commit whose tree is `5c3d8625`, the same three blobs, Git 2.43.0, Node.js v26.7.0, and `node tools/selftest.mjs` (0): 254 of 254. |
| `raw/names-r3.log` | `node raw/names-r3.mjs` (0): every run of the five logs above lists the 253 base names of `raw/probe-before-r3.log` in order, then case 4, and nothing else. |
| `raw/assertions-r3.log` | See "Every changed line". |
| `raw/mutation-r3.log`, `raw/mutation-r3-M4.diff` | See "Case 4 and M4". |
| `raw/bun-selftest-r3.log` | `git rev-parse HEAD`, `git hash-object` of the three test files, `bun --version` (1.4.2), and `bun tools/selftest.mjs` (0): 254 of 254. |
| `raw/cost-r3.log` | `raw/r3-cost.mjs` over the ten CI receipt logs, the two Windows profiles, and the Linux profile, then `raw/r3-probe.mjs` (0 each). |

### Open items

- The integrator dispatches the ten runs of criterion 3 on a head that contains revision 3 and records them with their receipts.
- The integrator records `HEAD` and a status that includes ignored files before and after it runs `repo-check` and `controller-test`.
