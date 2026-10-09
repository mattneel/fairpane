# FP-0107 task contract

## Identity

Task ID: `FP-0107`, "Keep the controller-test gate within its timeout on Windows".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: none.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Measured inputs

- `engineering/gates.json`: the `controller-test` gate runs `tools/selftest.mjs` with Node and a 120000 ms timeout.
- `tools/selftest.mjs` collects its own cases and those of seven `tools/*.test.mjs` modules, 224 at `e42f789`, and runs them one after another in its final loop, which prints `ok <n> - <name>` or `not ok <n> - <name>` and no duration.
- `engineering/evidence/ci/runs-2026-10-09.log` records the Windows `controller-test` step at 55 to 86 seconds in the ten dispatched runs on `29a9f8e`, and at 62 to 121 seconds in the push runs from `775d988` to `a6ac7aa`.
  The Linux step took 12 to 18 seconds in the same runs.
- Attempt 1 of run 37952850522 on `a2dd9ed` timed out at 120,572 ms while the suite ran its test 223 of 224, and attempt 2 passed at 63,566 ms; `engineering/evidence/ci/run-37952850522-attempt-1/` and `engineering/evidence/ci/run-37952850522/` keep the receipts.
- On the development host, the gate took 54,358 ms at `d56bc5f`, as `engineering/evidence/FP-0076/gates/2026-10-09T15-42-32-440Z-controller-test-6d02f1a6.json` records.
- FP-0098 review 1 notes that FP-0098's cases 1 and 2 each wait for a 2-second gate timeout and a Windows PowerShell listing.

### Integrator decisions

- The gate keeps its arguments and its timeout.
  A change to either is a separate protected change with independent approval, as `AGENTS.md` requires.
- No test is removed, skipped, narrowed, merged, or moved out of `controller-test`, and every test keeps its name.
- A test may get faster only by a change that keeps everything it asserts, such as a shared read-only fixture, fewer redundant process starts, cheaper fixture construction, or concurrent execution of independent tests.
  The README shows, for each change, that the test's inputs and assertions are unchanged.
- A test that changes process-wide state, such as the working directory, `process.env`, or a module-level hook, declares it when it is registered, and the runner never runs such a test while another test runs.
  Each existing test that changes such state gets the declaration, and the README lists them.
- Result lines keep the order of test numbers, even when tests run concurrently.
- Criterion 3 applies to the runs that criterion 4 dispatches after the change, as plan review 3 notes.
- Three revisions in flight also change `tools/selftest.mjs`: FP-0052's case 2, FP-0082's case 18 tests, and FP-0098's cases.
  The integrator dispatches this task only after those revisions land, so the base holds them.

## Sources

- `tools/selftest.mjs`: its case collection, its final loop, and every case.
- `tools/*.test.mjs`: the case modules that `tools/selftest.mjs` imports.
- `tools/lib.mjs`: `runGate`, `runProcess`, and the gate log.
- `engineering/gates.json` and `.github/workflows/gates.yml`, unchanged.

## Behavior

### Duration report

The runner moves into an exported function that runs a list of cases with a writer and returns the counts, and `tools/selftest.mjs` calls it with its cases.
After each result line, the runner prints `# duration_ms <n> <ms>`, where `<n>` is the test's number and `<ms>` is the test's wall time in whole milliseconds, rounded down, measured with `performance.now()` around the test's function.
After the `# tests`, `# pass`, and `# fail` lines, it prints `# slowest <rank> <ms> <n> <name>` for the ten slowest tests, or for every test when there are fewer, in descending order of time with ties in ascending test number, and then `# duration_ms total <ms>` for the whole run.

### Test cost

The worker records each test's duration on the development host and on WSL Ubuntu, before and after its changes.
It names the tests that take most of the Windows time, states the cause of each from the records, and reduces their cost under the decisions above.

## Exact test cases

1. Controller, every host: the runner function, given four fixture cases that wait 0, 60, and 120 ms and one that throws, writes each case's result line followed by its `# duration_ms` line, with each `<ms>` at least the case's wait.
   It writes the summary lines with 3 passes and 1 failure, then four `# slowest` lines with the 120 ms case first, then the `# duration_ms total` line.
   Its returned counts equal the summary.
2. Controller, every host: the runner function, given two fixture cases that declare a process-wide change and each wait 60 ms, and two ordinary cases that each wait 60 ms, runs no declared case while another case runs.
   Each fixture case records its start and end times, and the case asserts that no declared case's interval overlaps another case's interval.

Case 1 must fail before the change.
Case 2 cannot run on the base, which has no runner function or declaration, so a mutation control that ignores the declaration and runs every case concurrently must fail it.
A mutation control that omits the `# duration_ms` line must fail case 1.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0107/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `profile-before.log` and `profile-after.log` on the development host, and `profile-linux-before.log` and `profile-linux-after.log` on WSL Ubuntu, each from a run of the suite with the duration report.
   The before profiles apply only the duration report to the base.
3. `names.log`: the ordered test names of the base and of the changed suite, and a comparison that shows them equal.
4. `mutation.log` and its diffs, with the hash of each changed file before, during, and after.
5. `controller-tests-after.log` with `node tools/fairpane.mjs test`.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`.
After the push, the integrator starts the `Gates` workflow on `master` at least ten times with `gh workflow run`, records each run with `gh run view`, and downloads both jobs' receipts.
`ci/README.md` reports each run's Windows and Linux `controller-test` duration and the ten slowest tests of each job from the receipt logs.
The task is accepted only when every one of those runs passes and the slowest Windows `controller-test` step takes at most 80 seconds, two thirds of the timeout.

## Authority

Writable paths: `tools`, `tests`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged, including `engineering/gates.json`.
Required reviewer: `fairpane-review`.

## Non-goals

- No change to the gate's arguments, its timeout, or any other gate.
- No new CI job, runner, action, or cache.
- No change to which tests run or to what any test asserts.

## Revision 1

Base: the commit that freezes this revision.
Source: the `Gates` push run 37971989978 and the ten dispatched runs 37972006869 to 37974347550 on `3e7128c`.
In each, the Windows `controller-test` step failed 43 cases with "The executable is not on PATH: git" or "No git executable exists on PATH.", and the Linux job passed.
Every section above stays in force except where this revision replaces it.

### Revision 1 integrator decisions

- A worker thread receives a plain copy of `process.env`, whose names are case-sensitive, while the main thread's `process.env` reads the Windows environment without regard to case.
  The hosted Windows runner names the search path `Path`, so every case that reads `process.env.PATH` on a worker thread finds nothing.
  The development host's shell exports the name in upper case, which hid the fault from every local run.
- `casePool` starts each worker with the `worker_threads` option `env: SHARE_ENV`, so a case on a worker thread reads and writes the main thread's environment, as it did under the sequential runner.
  A case that changes `process.env` must still declare `processWide`, and the runner still runs it alone.
- No tool and no case body changes.

### Revision 1 exact test cases

3. Controller, every host: the case writes a probe module that registers one case, which reports `process.env.PATH`, and runs it through `casePool` on one worker thread, in a child process whose environment names the search path `Path` instead of `PATH`.
   The child prints the main thread's and the worker's values of `process.env.PATH`, which must be equal.
   On Windows, the main thread's value must also be present.

Case 3 must fail on Windows before the change.
On a host with case-sensitive names, both values are absent, so case 3 passes there before and after the change.

### Revision 1 mutation controls

- M3: `casePool` starts its workers without the `env` option; case 3 must fail on Windows.

### Revision 1 evidence

1. `r1-repro-before.log`: the base suite on Windows with the search path named `Path`, which must fail the cases that start `git` on worker threads, as the CI runs did.
2. `tests-before-r1.log`: the suite with case 3 and without the fix, in which case 3 fails on Windows.
3. `tests-after-r1.log` with `node tools/fairpane.mjs test`, and `r1-repro-after.log`, the suite with the search path named `Path`, which must pass.
4. `bun-selftest-r1.log`: Bun runs the suite.
5. `mutation-r1.log` and its diff for M3, with the hash of `tools/test-runner.mjs` before, during, and after.
6. The ten dispatched runs of criterion 3 repeat on a head that contains this revision, and `ci/README.md` also records the failed series on `3e7128c`.

### Revision 1 amendments

1. The integrator implemented revision 1, and `SHARE_ENV` failed in two attempts, which `raw/` keeps as `*-attempt-1.log` and `*-attempt-2.log`.
   With `SHARE_ENV`, the seven cases that point `TMPDIR`, `TMP`, and `TEMP` at a private directory through `withPrivateTemp` see the directories of concurrent cases, and three failed under Node (`tests-after-r1-attempt-1.log`).
   Declaring the five undeclared ones `processWide` fixed Node, but Bun 1.4.2 then failed four of them, because after a worker starts with `SHARE_ENV`, Bun's `os.tmpdir()` on the main thread no longer follows `process.env` (`bun-selftest-r1-attempt-2.log`).
   `raw/r1-share-env-probe.log` runs `raw/r1-share-env-probe.mjs` under Bun and Node and shows that defect only for Bun with `SHARE_ENV`.
   The revision therefore keeps each worker's own copy of the environment, and `casePool` passes the copy that `workerEnvironment` returns: on Windows, it names the search path `PATH` and the system root `SystemRoot`, the spellings that the tools read.
   No case gains a declaration, and case 3 and M3 stay as frozen.
   `bun-r1-repro-after.log` adds a Bun run of the suite with the search path named `Path`, and `tests-after-r1-repeat-1.log` to `-3.log` add three more Node runs.

## Revision 2

Base: the commit that freezes this revision.
Source: `reviews/review-1-reject.json`, which rejects revision 1 for one major finding and lists five minor findings and four notes.
Every section above stays in force except where this revision replaces it.

### Revision 2 integrator decisions

- The base decision that every case that changes process-wide state gets the declaration stays in force, and amendment 1's sentence "No case gains a declaration" is withdrawn.
  The five `withPrivateTemp` cases without a declaration gain `{ processWide: 'TMPDIR, TMP, and TEMP in process.env' }`, and the README lists them; `raw/r1-share-env-probe.log` shows that Bun's main-thread `os.tmpdir()` follows `process.env` when each worker has its own copy.
- `abi.test.mjs`, `fileset.test.mjs`, `rust.test.mjs`, `ucd.test.mjs`, and `workflow-check.test.mjs` pass a case's declaration through, as `attest.test.mjs` and `release.test.mjs` do, so a declaration in a module's case array cannot be dropped.
- ADR 0011 records the worker environment of revision 1 and why `SHARE_ENV` was rejected.
- Every revision 2 log records `HEAD` and the blob IDs of `tools/test-runner.mjs` and `tools/selftest.mjs` before its suite run.
- The README cites recorded `gh run view` logs for its claims about the runs of `3e7128c`, marks the runner's spelling `Path` as an inference that the reproduction supports, and records the SHA-256 of each withheld log.
- M3's diff is recorded against the committed fixed blob.

### Revision 2 evidence

1. `tests-after-r2.log`, `r2-repro-after.log` with the search path named `Path`, `bun-selftest-r2.log`, and `bun-r2-repro-after.log`, each passing every case.
2. `mutation-r2.log` and `mutation-r2-M3.diff`, with the hash of `tools/test-runner.mjs` before, during, and after.
3. A recorded run listing of the `3e7128c` series with each job's conclusion and each gate step's duration.

## Revision 3

Base: the commit that freezes this revision.
Source: the ten dispatched runs on `57df855`, which `engineering/evidence/ci/runs-57df855.log` lists and whose receipts lie under `engineering/evidence/ci/run-<id>/`.
Every run passes, but the Windows `controller-test` step takes 49 to 104 seconds, with receipt times from 49,004 to 103,199 ms, and run 37981495878 exceeds criterion 3's 80 seconds.
Every section above stays in force except where this revision replaces it.

### Revision 3 integrator decisions

- Criterion 3 and its 80-second bound stay as frozen.
- Across the ten Windows receipt logs, the sum of the cases' median `# duration_ms` values is about 156 seconds on four worker threads.
  The 25 slowest cases take 2.3 to 6.1 seconds each, and nearly all of them build Git fixtures: corpus snapshots, release archives, and candidate repositories.
  `raw/probe-process-starts.log` counted 1756 `git` starts in the base suite.
- Revision 3 reduces that work without changing what any case asserts.
  It may build a fixture with fewer `git` calls, for example through one `git fast-import`, one `git update-index --index-info`, or one `git hash-object -w --stdin-paths` call instead of one call per object.
  It may reuse a fixture that no case changes, within one worker thread, with each reusing case named in the README.
  It may change the runner's concurrency if three local runs and the dispatched runs support the change.
- Every case keeps its name, its order, its assertions, and every input that its assertions depend on.
  A changed fixture builder produces the same objects as before: the same blob, tree, and commit IDs wherever a case relies on an ID, and the same file contents otherwise.
- Revision 3 changes no gate, timeout, workflow, or set of cases, and adds no cache.
- The suite's child-process count, measured with `raw/process-probe.mjs` on the development host, falls by at least half, and the sum of the cases' median `# duration_ms` values over three local Windows runs falls by at least a third.
  These are local targets only; the dispatched runs decide criterion 3.

### Revision 3 exact test cases

4. Controller, every host: for each fixture builder that revision 3 changes, one case builds the fixture from one fixed input and asserts the object IDs that the base builder produced for that input, which `tests-before-r3.log` records.

Case 4 must fail before the change only if a builder's output changes; it passes on the base, which its before run records.

### Revision 3 mutation controls

- M4: one changed builder writes one file of its fixture with different content; case 4 must fail.

### Revision 3 evidence

1. `tests-before-r3.log`: `HEAD`, the blob IDs of every changed test file, `node tools/fairpane.mjs test`, and the object IDs of case 4's fixed inputs from the base builders.
2. `probe-before-r3.log` and `probe-after-r3.log`: the child-process count per case and in total.
3. `profile-before-r3.log` and `profile-after-r3.log`: three runs each of `node tools/fairpane.mjs test` on Windows, and `profile-linux-after-r3.log` on WSL Ubuntu.
4. `names-r3.log`: the ordered case names before and after, which must be equal apart from case 4.
5. `assertions-r3.log`: `git diff --stat` and `git diff` of the test files, with every changed line accounted for in the README as a fixture change, never an assertion change.
6. `mutation-r3.log` with M4, and `bun-selftest-r3.log`.
7. After integration, the ten dispatched runs of criterion 3 repeat on a head that contains revision 3.

### Revision 3 amendments

1. Worker `FP0107Revision3` showed that the local target "falls by at least half" cannot be met within the authorized scope.
   Its worker-aware probe counts 1975 child processes in the base suite: the tools under test start 987 of them, 735 in `tools/corpus.mjs`, and the test files start 988.
   Both local targets therefore become measurements without a bound; the README reports them before and after, and criterion 3's dispatched runs stay the only acceptance bound.
   Tool code may also change where the recorded probe shows a tool starting one `git` process per object or query that one batched call can serve.
   Every tool output, error message, exit status, ordering, and on-disk effect stays identical, every digest and object-ID check stays exactly as strict, and every existing case passes unchanged.
   The README lists each tool change with the cases that cover it and its effect on the process count.
   A change to corpus or attestation verification also needs a `fairpane-security` review before acceptance.
