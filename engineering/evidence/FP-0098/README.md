# FP-0098 evidence

## Scope

Task `FP-0098` keeps the `zig-test` gate within its timeout and makes a timeout diagnosable.
The frozen contract is `engineering/evidence/FP-0098/CONTRACT.md` with amendment 1.
The worker implemented it in an isolated working tree whose `HEAD` was `937a06bff75725bddc94306cb718894048903841`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0 and the locked Zig `0.18.0-dev.120+9fe22a29b`.
[INFERENCE] Other agents ran builds on the same host, so every local duration includes some contention; no log records those builds.
No protected path changed, and `engineering/gates.json` keeps the gate's arguments and its 600000 ms timeout.
[INFERENCE] The worker did not commit, push, or dispatch a workflow run; no log records that.

## Changes

- `tools/lib.mjs`: at a timeout, `runProcess` lists the command's live process tree before it stops the command.
  `listProcessTree` reads `Win32_Process` through Windows PowerShell, started by its full path under `%SystemRoot%\System32`, or reads `/proc/<pid>/stat` and `/proc/<pid>/cmdline` on Linux.
  The listing has a 10-second limit (`PROCESS_LISTING_LIMIT_MS`).
  A failed listing writes its reason, and the stop and the failure proceed unchanged.
  `runGate` and `runProcess` accept `processListing`, which tests use to name an absent PowerShell executable or `/proc` directory.
- `tools/selftest.mjs`: cases FP-0098 1 to 3.
- `src/dom.zig`: the inclusive-ancestor check of "ensure pre-insert validity" step 2 answers a node without children in constant time, and a new test compares that shortcut with the ancestor walk for every pair of nodes in a fixture.
- `tools/zig/test_profile_runner.zig`: a test runner that times each test, used only by the profiling commands below.
- `tools/README.md`: the timeout section under "Gate safety" and the new section "Profile the Zig tests".

## Timeout record

At the timeout, the log receives these lines before the stop.

```text
TIMEOUT after <ms> ms: the live process tree of PID <pid> follows.
PROCESS {"pid":<pid>,"ppid":<parent pid>,"command_line":<command line>}
TIMEOUT Stopping PID <pid> and its descendants.
```

The first `PROCESS` line is the command itself, and each later line is a live descendant in breadth-first order.
A process counts as a child only if it started no earlier than its parent, so a reused parent ID adds no unrelated process.
On Windows, `command_line` is the `Win32_Process.CommandLine` string; on Linux, it is the argument array from `cmdline`.
When the listing fails, the first line is `TIMEOUT after <ms> ms: the process listing failed: <reason>`, and no `PROCESS` line follows.
The section precedes the command's output in the log, because the output is copied in when the command ends.
Since revision 1, a command that ends during the listing still gets the section, and its last line is `TIMEOUT The command ended during the listing.` in place of the `Stopping` line; see "Revision 1".
The receipt's `timed_out` stays `true`, and the gate fails as before.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Case 1: a gate whose command starts a 60-second child, with a 2-second timeout, fails with `timed_out: true`, lists the child's PID and marker, and leaves nothing running. | Case FP-0098 1 fails in `raw/tests-before.log`, because the log lists no process, and passes on Windows in `raw/controller-tests-after.log` and on Linux in `raw/linux-controller-tests.log`. The case polls the child's PID for up to 5 seconds after the gate returns. |
| Case 2: when the listing cannot run, the log names the failure, the gate fails with `timed_out: true`, and the command stops. | Case FP-0098 2 fails in `raw/tests-before.log`, because the log has no listing failure, and passes on Windows in `raw/controller-tests-after.log` and on Linux in `raw/linux-controller-tests.log`. The case names an absent `powershell.exe` and an absent `/proc` directory, so it exercises the failure path on either host. |
| Case 3: ordinary pass and fail records are unchanged. | Case FP-0098 3 passes before and after: a passing and a failing gate each have one command, the expected exit status, `timed_out: false`, and no `TIMEOUT` or `PROCESS` line. The existing gate cases also pass before and after. |
| A mutation control that skips the listing fails case 1. | `raw/mutation.log`: under the control in `raw/mutation-final.diff`, cases FP-0098 1 and 2 fail, and the other 208 cases pass. |
| The run time of every test is recorded by a described method. | `raw/test-profile-before.log` and `raw/test-profile-after.log`; see "Profiling method". |
| The tests that take most of the run time are named and their cost reduced without weakening an assertion. | See "Test cost". |
| `zig fmt --check build.zig src tests` and `node tools/fairpane.mjs test` pass. | `raw/fmt.log` and `raw/controller-tests-after.log`. |
| Baseline identity. | `raw/tests-before.log` records `HEAD`, the staging command, and the blob ID of every staged file. |

## Profiling method

`zig build test` runs two test binaries, the laboratory cases, and the 22 compile-failure fixtures.
The default test runner reports no per-test duration, so `tools/zig/test_profile_runner.zig` measures each test's wall time with the `awake` clock.
Before each test, it prepares `std.testing` exactly as the default runner's `--listen` mode does, including the `SafeAllocator` canary and write-after-free check.
It fails the run on a failed test, a leak, or an error log.

1. `zig test -ODebug --test-runner tools/zig/test_profile_runner.zig --cache-dir <fresh> src/root.zig` profiles the unit tests of the `fairpane` module.
2. The same command with `--dep fairpane -Mroot=tests/text/root.zig -Mfairpane=src/root.zig` profiles the text tests.
3. `zig build test --summary all --cache-dir <fresh>` gives the duration of every other step: the laboratory cases and the 22 compile-failure fixtures.

Both binaries run from the repository root, as the build's run steps do.
The before profiles ran on base sources: the unit profile in this tree before any source change, and the text profile and the build run in `out/fp0098-base`, a `git archive` of `HEAD`.

## Test cost

### Before

The uncached `zig build test --summary all` took 176146 ms, and its unit-test run step took 2 minutes.
The unit tests summed to 188281.739 ms over 247 tests; the 45 text tests summed to 290.680 ms.
Each laboratory case and compile-failure fixture took at most 466 ms, and the slowest compile step took 8 seconds.

| Rank | Test | ms | Share |
| --- | --- | --- | --- |
| 1 | `css.tests.test.FP-0014 case 46: nesting depth is bounded only by memory` | 167071.659 | 88.7% |
| 2 | `html.partition_test.test.FP-0064 case 13: set P compares every composition ...` | 7038.636 | 3.7% |
| 3 | `html.partition_test.test.FP-0008 case 13: set P compares every composition ...` | 5942.317 | 3.1% |
| 4 | `js.heap.test.FP-0011 case 9: the generated and manual tracers visit and free the same cells` | 4936.324 | 2.6% |
| 5 | `css.tests.test.FP-0014 case 53: selector matching exits early, and class tokens deduplicate in n log n time` | 904.239 | 0.4% |

### Cause

FP-0014 case 46, which `ef8ad1c` added, has three parts at depth 100000.
`raw/probe-case46-parts.log` split it temporarily into three tests: the test under the case's own name took 36.474 ms, `PROBE part 2` took 177806.055 ms, and `PROBE part 3` took 1246.378 ms.
[INFERENCE] Those parts are, in order, the 100000 nested parentheses, the chain of 100000 elements, and the 100000 chained `var()` references; no diff of the split was recorded, so no log shows which construct each part held.
The chain appends each new element to the previous one.
Each `appendChild` runs "ensure pre-insert validity", whose step 2 asks whether the new node is an inclusive ancestor of the parent.
`Store.isInclusiveAncestor` answered by walking from the parent to the root, so the k-th append of the chain walked about k nodes, and the chain cost about 5 × 10⁹ parent lookups.
The split was reverted before any after-run: `src/css/tests.zig` has its `HEAD` blob `96068291c3019347323452987653aeab2b48262e` in `raw/tests-after.log`.

### Change

Every ancestor has a child, so a node without children is an inclusive ancestor only of itself.
`isInclusiveAncestor` now returns `true` for the same node, returns `false` for a node without children, and otherwise runs the unchanged walk, which is now `isInclusiveAncestorByWalk`.
The answer is identical for every input, so no assertion of any test changes, and the DOM standard's semantics are preserved.
The walk remains the generic reference path.
The new test `FP-0098: the leaf shortcut of the inclusive-ancestor check agrees with the ancestor walk for every pair of nodes` checks all 144 ordered pairs of 12 nodes, including a document tree, a fragment, a detached subtree, a detached leaf, and a text leaf, and it checks the 29 related pairs by count.
FP-0009 case 2 still rejects a node inserted under itself with `HierarchyRequest`.
With the change, the probe's chain part took 2164.506 ms in `raw/probe-case46-parts-leaf-shortcut.log`.

### After

The uncached `zig build test --summary all` took 36501 ms, and its unit-test run step took 24 seconds.
The unit tests summed to 24987.779 ms over 248 tests; the 45 text tests summed to 291.507 ms.

| Rank | Test | ms | Share |
| --- | --- | --- | --- |
| 1 | `html.partition_test.test.FP-0064 case 13: set P compares every composition ...` | 7622.122 | 30.5% |
| 2 | `html.partition_test.test.FP-0008 case 13: set P compares every composition ...` | 6353.593 | 25.4% |
| 3 | `js.heap.test.FP-0011 case 9: the generated and manual tracers visit and free the same cells` | 4935.342 | 19.7% |
| 4 | `css.tests.test.FP-0014 case 46: nesting depth is bounded only by memory` | 2786.094 | 11.1% |
| 5 | `css.tests.test.FP-0014 case 53: selector matching exits early, and class tokens deduplicate in n log n time` | 671.654 | 2.6% |

The remaining leaders are unchanged.
Each set P case tokenizes every composition of each input, 2^(n-1) partitions of n code units, so its cost is the assertion set itself.
FP-0011 case 9 compares two tracers over its fixture heaps.
Neither showed an algorithmic defect, and a faster harness for them would need a different allocator than `std.testing.allocator`, which would drop its leak and misuse checks.

### Every test and assertion kept

- `raw/test-profile-after.log` compares the test names of both profiles: 292 before and 293 after, none missing, and one added, the FP-0098 DOM test.
- The build summary shows 292/292 tests before and 293/293 after, in 65 of 65 steps each time.
- `git diff --exit-code HEAD -- build.zig tests src/css src/html src/js src/lab.zig` exits with 0, so no other test source and no build step changed.
- `git diff --stat HEAD -- build.zig src tests` shows only `src/dom.zig`, with 55 insertions and no deletions.

## Records

Every command ran through `node tools/fairpane.mjs record`.
The worker deleted or overwrote no log during its session.
After `9d5638b`, the integrator removed `raw/linux-node-probe.log` from the tree in `29a9f8e`, as "Open items" explains.

| Log | RESULT |
| --- | --- |
| `raw/ci-durations.log` | The integrator's collection before this task, cited by the contract. |
| `raw/tests-before.log` | See "Red baseline". |
| `raw/test-profile-before.log` | `exit_code` 0 for the unit profile (247 tests, 188281.739 ms), for `git rev-parse HEAD`, `git archive`, `tar`, and `git hash-object`, for the uncached `zig build test --summary all` in `out/fp0098-base` (176146 ms, 292/292 tests), and for the text profile (45 tests). |
| `raw/probe-case46-parts.log` | `exit_code` 0 for the temporarily split case 46 on base sources. |
| `raw/probe-case46-parts-leaf-shortcut.log` | `exit_code` 0 for the split case 46 and the FP-0098 DOM test after the change. |
| `raw/controller-tests-attempt-1.log` | `exit_code` 0, 210 of 210 cases, for the first implementation. The worker then made Linux skip `EACCES` and `EPERM` processes, so `raw/controller-tests-after.log` supersedes it. |
| `raw/test-profile-after.log` | `exit_code` 0 for the unit profile (248 tests, 24987.779 ms), the text profile (45 tests), the test-name comparison, `git diff --stat`, and `git diff --exit-code`. |
| `raw/tests-after.log` | `exit_code` 0 for the uncached `zig build test --summary all --cache-dir out/fp0098-cache-after` (36501 ms, 293/293 tests), `git rev-parse HEAD`, `git status --short`, and `git hash-object` of the changed files. |
| `raw/mutation.log` | Two complete controls with the same one-line mutation. The first ran on `tools/lib.mjs` blob `53236eadfbca7ca428867d48944d2ec9ce3d1f40` with `raw/mutation.diff`; the second ran on the final blob `ef00cf6d3dfae846f97f99a9b9950d2b98a8f043` with `raw/mutation-final.diff`. Each records `git hash-object` (0), the mutation (0), `git hash-object` (0), `git diff --no-index` (1, because the files differ), `node tools/selftest.mjs` (1, with cases FP-0098 1 and 2 failing and 208 cases passing), the restoration (0), and `git hash-object` (0) showing the original blob. |
| `raw/fmt.log` | `exit_code` 0 for `zig fmt --check build.zig src tests` and for `zig fmt --check tools/zig`. |
| `raw/controller-tests-after.log` | `exit_code` 0 for `node tools/fairpane.mjs test`, with 210 of 210 cases, including FP-0098 cases 1 to 3; then `git hash-object` (0) and `node --version` (0). |
| `raw/linux-node-probe.log` | Removed by the integrator after `9d5638b`; see "Open items". The probe found no `node` on the WSL `PATH` (`exit_code` 127), which is why the Linux run below downloads its own Node. |
| `raw/linux-controller-tests.log` | `exit_code` 0 for the download, SHA-256 check, and extraction of Node v24.21.0 for Linux x64 into `out/fp0098-linux`. Then `node tools/selftest.mjs` under WSL Ubuntu (Linux 7.2.6) exits with 1: 209 of 210 cases pass, including FP-0098 cases 1 to 3 through `/proc`. The one failure is case 13 of the attestation tests, because this working tree's Git alternates file names the Windows path `C:\src\fairpane\.git\objects`, which Linux Git cannot open; it is unrelated to this task. |

### Red baseline

`raw/tests-before.log` runs these commands in order.

1. `git rev-parse HEAD HEAD:tools/lib.mjs HEAD:tools/selftest.mjs`, `exit_code` 0: `HEAD` `937a06bff75725bddc94306cb718894048903841`, `tools/lib.mjs` `7a3478ce002cd8072e888648a8f64d5e4ba0c8fb`, and `tools/selftest.mjs` `67c9b5324cdf1ada2bed86bb14e5246647a1443f`.
2. `git status --short`, `exit_code` 0: of this task's files, only `tools/selftest.mjs` is modified, and `tools/zig/` is new; the `FP-0064` entries predate this task.
3. The staging command `git add -- tools/selftest.mjs`, `exit_code` 0.
4. `git ls-files --stage`, `exit_code` 0: `tools/lib.mjs` keeps its `HEAD` blob, and the staged `tools/selftest.mjs` is `3735e387a9adc453c8c74caf3a3a3d1312db528e`, the blob that the final tree also has.
5. `git diff --cached --stat`, `exit_code` 0: 53 insertions in `tools/selftest.mjs`.
6. `node tools/selftest.mjs`, `exit_code` 1, with 208 of 210 cases passing.
   Case FP-0098 1 fails with "The log lists no process with the child's PID 58032".
   Case FP-0098 2 fails because the log has no `TIMEOUT ... the process listing failed` line.
   Case FP-0098 3 passes.
7. `git reset -q -- tools/selftest.mjs` and `git diff --cached --stat`, `exit_code` 0 each, which leave the index at `HEAD`.

## Open items

- `ci/README.md` records the ten dispatched `Gates` runs of `29a9f8e`: all ten pass, and the slowest `zig-test` step takes 191 seconds on Windows and 188 seconds on Linux, both at most 400 seconds.
  Revision 1 adds the compile and run phase durations, which the integrator reports in `ci/README.md` from runs dispatched after revision 1 lands.
- [INFERENCE] The jump at `ef8ad1c` from 119 to 573 seconds on Windows fits the 167-second local cost of case 46, but no CI record decides the cause of the three timed-out runs.
- The worker's `raw/linux-node-probe.log` listed every name in the WSL user's home directory, which the probe did not need and which included unrelated private file and project names.
  It landed in the public commit `9d5638b`, and the integrator removed it from the tree in the next evidence commit.
  It stays in Git history: on 2026-10-09 the owner chose to leave history as is, and `owner-answers.log` records the question and the answer.

## Integration

The integrator applied the worker's patch, without the FP-0064 files that the worker's tree had copied from the integrator's uncommitted work, and committed it alone as `9d5638b`.

- `raw/integration-binding.log` records `HEAD` `9d5638b` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T14-06-03-411Z-repo-check-ec5516bd.json`, `gates/2026-10-09T14-06-03-775Z-controller-test-2e778742.json`, `gates/2026-10-09T14-06-49-061Z-zig-fmt-4639710b.json`, and `gates/2026-10-09T14-06-49-319Z-zig-test-ba3f7be3.json` pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0098-integration`: 65 of 65 build steps and 300 of 300 tests pass in about 36 seconds.
  The worker's tree had 293 tests, because the commits between the worker's base `937a06b` and `9d5638b` added tests.
  `raw/test-count-r1.log` counts the top-level `test "` declarations at `937a06b` and at `9d5638b~1`: `src/abi_scenarios.zig` gains 2, `src/c_api.zig` 3, and the new `src/memory_budget.zig` 2, which is the difference of 7.
- `raw/bun-selftest.log` records Bun 1.4.2 and `tools/selftest.mjs` with 212 of 212 tests.

## Revision 1

Revision 1 of `CONTRACT.md`, frozen at `e42f789`, answers `reviews/review-1-reject.json`.
The worker implemented it in an isolated working tree whose `HEAD` was `f5be48fdce1fd7720d17ce6d30f8a3f62f23f38d`.
That commit descends from `e42f789` and changes no file under `tools` or `.github`, as `git diff --stat --exit-code e42f789 HEAD -- tools .github` shows with `exit_code` 0 in `raw/tests-before-r1.log`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0 and the locked Zig `0.18.0-dev.120+9fe22a29b`.
No protected path changed, and `engineering/gates.json` keeps the `zig-test` gate's arguments and its 600000 ms timeout.

### Changes

- `tools/lib.mjs`: when the command ends while the timeout listing runs, `runProcess` waits for the listing and writes the timeout section before it copies the output and closes the log.
  The section then ends with `TIMEOUT The command ended during the listing.` in place of `TIMEOUT Stopping PID <pid> and its descendants.`, and the receipt keeps `timed_out: true`.
  The command counts as ended when its exit event arrived during the listing or when a signal-0 probe finds no such process, because on Windows the probe sees the exit before the event arrives.
  `stopDescendants` then stops each listed descendant: on Windows, with one `taskkill.exe /PID <pid>... /T /F`, because the ended command's PID no longer reaches its tree; on Linux, by signaling the command's process group and each listed PID.
  `processListing` may now also be a function that replaces the listing, which the new case uses.
- `.github/workflows/gates.yml`: both `Run gate zig-test` steps set `env:` to `ZIG_BUILD_SUMMARY: all`, and nothing else changed.
- `tools/workflow-check.mjs`: `gateWorkflowProblems` requires exactly `ZIG_BUILD_SUMMARY: all` in the `env:` of each step that runs `node tools/fairpane.mjs run zig-test`, names the step in each problem, and still rejects `env:` on every other step, job, and workflow.
- `tools/selftest.mjs`: `hungGateFixture` prints `fp0098-output <marker>` before it waits, cases FP-0098 1 and 2 assert that line after the last `TIMEOUT` line, and the new case is "FP-0098 revision 1 case 2".
- `tools/workflow-check.test.mjs`: the new case "FP-0098 revision 1 case 3".
  FP-0067 case 5 removes and moves the `zig-test` step text, which now includes its `env:` lines, so its expected text gained those lines; its assertions are unchanged.
- `tools/README.md`: the timeout section and the workflow allowlist describe the new behavior.
- `raw/case-durations-r1.mjs`: the preload that reports each case's duration in `raw/controller-tests-after-r1.log`, described under "Case durations".

A known limit remains.
If the listing fails on Windows and the command ends during it, no descendant is known, so the watchdog stops none; the failure line and the ended line say what happened.
[INFERENCE] A PID that the system reuses between the listing and the stop could name an unrelated process, as it already could for the stop of a live command; the window is the few milliseconds after the listing.

### Build summary probe

The stop rule asks whether `ZIG_BUILD_SUMMARY` reaches `zig build test` through the gate runner and whether the locked build runner then prints step durations.
`raw/probe-build-summary-r1.log` runs `node tools/fairpane.mjs run zig-test` with the override `ZIG_BUILD_SUMMARY=all`, and then prints the gate log and the receipt.
The gate passes, `exit_code` 0, in 113328 ms for `zig build test`.
The gate log, which received no `--summary` argument, holds `Build Summary: 100/100 steps succeeded; 321/321 tests passed` and a duration for each step, such as `run test 270 pass (270 total) 30s` and its `compile test debug native success 13s`.
So the probe does not meet the stop rule, and the workflow change proceeds.
The locked runner reads the variable in `lib/compiler/Maker.zig`, lines 296 to 300.
The receipt's `environment_overrides` lists only `ZIG_GLOBAL_CACHE_DIR`, because the gate runner passes `ZIG_BUILD_SUMMARY` through the inherited environment; the summary in the gate log shows that it applied.
[INFERENCE] A `zig build` that the watchdog stops prints no summary, so for a timed-out run the timeout section remains the record of the running steps.

### Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Cases 1 and 2: the hung fixture prints `fp0098-output <marker>`, and each case asserts the line after the `TIMEOUT` section. | Both pass in `raw/tests-before-r1.log`, as the revision expects, and in `raw/controller-tests-after-r1.log`. Under mutation control 1, which skips the output copy for a stopped command, both fail with "The log lacks the line "fp0098-output ..." after its TIMEOUT section". |
| Case 2: `runProcess` with a 400 ms timeout and a stand-in listing that stops the command and resolves after it exits gives `timed_out: true` and the ended line, and no descendant keeps running. | "FP-0098 revision 1 case 2" fails in `raw/tests-before-r1.log`, where the log has a full listing and no ended line, and passes in `raw/controller-tests-after-r1.log`. The stand-in lists the command and its 60-second child, stops only the command, and waits until it exits; the case then waits up to 5 seconds for the child to end and checks that the line precedes the `RESULT` line. Under mutation control 2, which drops the line, it fails. |
| Case 3: the committed workflow passes, a `zig-test` step without the key fails with a message that names the step, and the key on any other step fails. | "FP-0098 revision 1 case 3" fails in `raw/tests-before-r1.log` because `gates.yml` lacks the key, and passes in `raw/controller-tests-after-r1.log`. It checks both jobs without the key, a wrong value, an extra variable, the key on each of the other 19 steps, on a job, and on the workflow, each as exactly one problem. |
| Cases 2 and 3 fail before the change. | `raw/tests-before-r1.log`: 224 of 226 cases pass, and the two failures are these cases. |
| Mutation controls. | `raw/mutation-r1.log`, `raw/mutation-r1-1.diff`, and `raw/mutation-r1-2.diff`; see "Revision 1 records". |
| Both `Run gate zig-test` steps set `ZIG_BUILD_SUMMARY: all`, and the checker accepts the key there only. | `.github/workflows/gates.yml` and case 3. |
| Duration of each new or changed case. | See "Case durations". |

### Case durations

The suite's runner prints no duration before FP-0107, so `raw/controller-tests-after-r1.log` runs `node tools/fairpane.mjs test` with `NODE_OPTIONS=--import=./engineering/evidence/FP-0098/raw/case-durations-r1.mjs`.
That preload changes no test and no result line.
In the `tools/selftest.mjs` process only, it removes `NODE_OPTIONS` again, so no command that a test starts loads it, and it prints `# elapsed_ms <ms>` after each result line: the whole milliseconds since the previous result line, which is the time of the case on that line.

| Case | Status | ms | ms in attempt 1 |
| --- | --- | ---: | ---: |
| FP-0098 case 1 (changed) | ok | 3020 | 3161 |
| FP-0098 case 2 (changed) | ok | 2215 | 2295 |
| FP-0098 revision 1 case 2 (new) | ok | 643 | 680 |
| FP-0098 revision 1 case 3 (new) | ok | 3 | 3 |
| FP-0067 case 5 (changed fixture text) | ok | 0 | 0 |

The whole suite took 59741 ms, and 64567 ms in attempt 1.
The new cases add about 0.65 seconds on this host.
[INFERENCE] The changes to cases 1 and 2 add one printed line and one assertion each, so their cost is still the 2-second gate timeout and the listing.

### Revision 1 records

Every command ran through `node tools/fairpane.mjs record`, and the worker deleted or overwrote no log.

| Log | RESULT |
| --- | --- |
| `raw/tests-before-r1.log` | `git rev-parse` (0): `HEAD` `f5be48f`, `e42f789`, and the base blobs of `tools/lib.mjs` `b037dcc6`, `tools/selftest.mjs` `9bb8dd96`, `tools/workflow-check.mjs` `d997513b`, `tools/workflow-check.test.mjs` `c6779096`, and `gates.yml` `20081873`. `git diff --stat --exit-code e42f789 HEAD -- tools .github` (0). `git status --short` (0). The staging command `git add -- tools/selftest.mjs tools/workflow-check.test.mjs` (0). `git ls-files --stage` (0): staged `tools/selftest.mjs` `de364790`, which the final tree keeps, and `tools/workflow-check.test.mjs` `3c8068fe`; the other files keep their base blobs. `git diff --cached --stat` (0): 69 insertions and 1 deletion. `node tools/selftest.mjs` (1): 224 of 226 pass, and "FP-0098 revision 1 case 3" and "FP-0098 revision 1 case 2" fail. `git reset -q` and `git diff --cached --stat` (0 each) leave the index at `HEAD`. |
| `raw/probe-build-summary-r1.log` | `exit_code` 0 for the gate run and for the command that prints its log and receipt; see "Build summary probe". |
| `raw/test-count-r1.log` | `exit_code` 0 for the two `git grep -c` counts and `git diff --stat 937a06b 9d5638b~1 -- src tests build.zig`; see "Integration". |
| `raw/controller-tests-after-r1-attempt-1.log` | `exit_code` 0, 226 of 226 cases, before the mutation controls. `raw/controller-tests-after-r1.log` repeats it after the controls with the final files. |
| `raw/mutation-r1.log` | Control 1 replaces `try { copy(capture, fd); }` with `try { if (!timedOut) copy(capture, fd); }` (`raw/mutation-r1-1.diff`): `tools/lib.mjs` is `22e78868` before, `c716ab8d` during, and `22e78868` after; `git diff --no-index` exits with 1 because the files differ; `node tools/selftest.mjs` exits with 1, with FP-0098 cases 1 and 2 failing and 224 cases passing. Control 2 replaces `lines.push(ended ? ` with `if (!ended) lines.push(ended ? ` (`raw/mutation-r1-2.diff`): `22e78868` before, `d12a7a74` during, and `22e78868` after; `node tools/selftest.mjs` exits with 1, with "FP-0098 revision 1 case 2" failing and 225 cases passing. Each restoration exits with 0. |
| `raw/controller-tests-after-r1.log` | `node tools/fairpane.mjs test` (0) with 226 of 226 cases and the case durations; `node tools/fairpane.mjs check` (0, `pass`); `git hash-object` (0) of `tools/lib.mjs` `22e78868`, `tools/selftest.mjs` `de364790`, `tools/workflow-check.mjs` `ed08ed4e`, `tools/workflow-check.test.mjs` `35eaf083`, `gates.yml` `55410895`, `tools/README.md` `69c30a0f`, and `raw/case-durations-r1.mjs` `27580270`; and `node --version` (0), v26.7.0. |
| `raw/linux-controller-tests-r1.log` | `exit_code` 0 for the download, SHA-256 check, and extraction of Node v24.21.0 for Linux x64 into `out/fp0098-r1-linux` under WSL Ubuntu. Then `node tools/selftest.mjs` on Linux 7.2.6 exits with 1: 225 of 226 cases pass, including FP-0098 cases 1 to 3 and revision 1 cases 2 and 3. The one failure is case 13 of the attestation tests, because this working tree's Git alternates file names a Windows path that Linux Git cannot open, as in `raw/linux-controller-tests.log`; it is unrelated to this task. |

### Corrections to this README

- "Cause" marks the mapping of the split parts of case 46 to their constructs [INFERENCE], because no diff of the split was recorded.
- "Records" limits "no log was deleted or overwritten" to the worker's session and states the integrator's removal of `raw/linux-node-probe.log` in `29a9f8e`.
- "Open items" points to `ci/README.md` and its result for the dispatched runs.
- "Integration" explains the 300 tests of the integration run and the 293 of the worker's tree.
- "Scope" marks the statements about other agents' builds and about the worker's commits, pushes, and dispatches [INFERENCE].

### Open items for revision 1

- The integrator records `HEAD` and a status that includes ignored files for every source root around `repo-check` and `controller-test`, and re-records `ci/dispatched-runs.log` with each run's `headBranch`.
- After the push, the integrator dispatches at least ten `Gates` runs on `master`, downloads both jobs' receipts, and reports in `ci/README.md` each run's `zig-test` duration and the build summary's duration for each compile step and each run step.
- The integrator's CI runs exercise both hosts again; `raw/linux-controller-tests-r1.log` is the worker's only Linux run of the new controller case.
