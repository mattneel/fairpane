# FP-0098 evidence

## Scope

Task `FP-0098` keeps the `zig-test` gate within its timeout and makes a timeout diagnosable.
The frozen contract is `engineering/evidence/FP-0098/CONTRACT.md` with amendment 1.
The worker implemented it in an isolated working tree whose `HEAD` was `937a06bff75725bddc94306cb718894048903841`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0 and the locked Zig `0.18.0-dev.120+9fe22a29b`.
Other agents ran builds on the same host, so every local duration includes some contention.
No protected path changed, and `engineering/gates.json` keeps the gate's arguments and its 600000 ms timeout.
The worker did not commit, push, or dispatch a workflow run.

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
`raw/probe-case46-parts.log` split it temporarily into three tests: the 100000 nested parentheses took 36.474 ms, the chain of 100000 elements took 177806.055 ms, and the 100000 chained `var()` references took 1246.378 ms.
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
No log was deleted or overwritten.

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

- The integrator runs the ten dispatched `Gates` runs and records each Windows and Linux `zig-test` duration in `ci/README.md`.
  The task is accepted only if the slowest is at most 400 seconds and every run passes.
- [INFERENCE] The jump at `ef8ad1c` from 119 to 573 seconds on Windows fits the 167-second local cost of case 46, but no CI record decides the cause of the three timed-out runs.
- The worker's `raw/linux-node-probe.log` listed every name in the WSL user's home directory, which the probe did not need and which included unrelated private file and project names.
  It landed in the public commit `9d5638b`, and the integrator removed it from the tree in the next evidence commit.
  It stays in Git history unless the owner chooses to rewrite history, which only the owner may authorize.

## Integration

The integrator applied the worker's patch, without the FP-0064 files that the worker's tree had copied from the integrator's uncommitted work, and committed it alone as `9d5638b`.

- `raw/integration-binding.log` records `HEAD` `9d5638b` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T14-06-03-411Z-repo-check-ec5516bd.json`, `gates/2026-10-09T14-06-03-775Z-controller-test-2e778742.json`, `gates/2026-10-09T14-06-49-061Z-zig-fmt-4639710b.json`, and `gates/2026-10-09T14-06-49-319Z-zig-test-ba3f7be3.json` pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0098-integration`: 65 of 65 build steps and 300 of 300 tests pass in about 36 seconds.
- `raw/bun-selftest.log` records Bun 1.4.2 and `tools/selftest.mjs` with 212 of 212 tests.
