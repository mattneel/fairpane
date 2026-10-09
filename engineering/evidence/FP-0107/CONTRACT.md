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
