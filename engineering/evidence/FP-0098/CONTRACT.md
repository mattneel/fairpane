# FP-0098 task contract

## Identity

Task ID: `FP-0098`, "Keep the zig-test gate within its timeout and make a timeout diagnosable".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: none; amendment 1 removed `FP-0067`, whose code is already in the base.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Measured inputs

The integrator collected these facts on 2026-10-09 from `gh run view` of 52 completed `Gates` runs; `raw/ci-durations.log` records the collection.

- The Windows `zig-test` step took 85 to 155 seconds in every run created before 11:20Z.
- From 11:50Z, it took 250 to 590 seconds, with a median near 550 seconds in the latest runs.
- Runs 37931192952 (`9cc81ea`), 37934034077 (`4531b33`), and 37935108213 (`d526219`) failed when the gate stopped `zig build test` at its 600000 ms timeout.
  Each receipt has `timed_out: true` and no build output, so no record shows which step was running.
- `engineering/evidence/FP-0064/raw/integration-tests.log` shows that, on the development host, the unit-test binary's run step takes about 2 minutes for 247 tests, while its compile step takes 8 seconds.
- Amendment 1 adds two facts.
  The jump begins with `ef8ad1c`, which added the FP-0014 CSS tests: the last run before it took 119 seconds, and the first run that contains it took 573 seconds.
  Run 37936609533 of `152ed53`, the first run whose Linux job runs `zig-test`, timed out at 600004 ms on Linux and was stopped with `SIGKILL`; `engineering/evidence/FP-0067/ci/` records it.

### Integrator decisions

- The gate keeps its arguments and its timeout in this task.
  A change to either is a separate protected change with independent approval, as `AGENTS.md` requires.
- No test is removed, skipped, narrowed, or moved out of `zig-test`.
  A test may get faster only by a change that keeps everything it asserts, such as a faster implementation or harness, and the README shows that for each change.
- On a timeout, the gate runner records the command line of every live descendant of the gate command, before it stops them.
  That shows which build step was running without depending on output that `zig build` holds back.
- The cause of the timeouts of the three runs above stays [INFERENCE] unless a record decides it.

## Sources

- `tools/lib.mjs`: `runProcess`, its watchdog at lines 390 to 398, and `runGate`.
- `engineering/gates.json`: the `zig-test` gate, `["build", "test"]` with a 600000 ms timeout.
- `.github/workflows/gates.yml` after `FP-0067`: both jobs run `zig-test`.
- `engineering/evidence/FP-0014/ci/README.md`, which records the first timeout.
- `build.zig` and every Zig test that `zig build test` runs.

## Behavior

### Timeout record

When the gate runner stops a command at its timeout, it first writes a section to the gate log that lists each live descendant process of the command: its process ID, its parent process ID, and its full command line.
On Windows, it reads them through `Win32_Process` with Windows PowerShell, started by its full path under the system directory.
On Linux, it reads `/proc/<pid>/stat` and `/proc/<pid>/cmdline`.
If the listing fails, the log says why, and the gate still stops the command and fails.
The listing has its own 10-second limit, and the receipt's `timed_out` stays `true`.

### Test cost

The worker records the run time of every test that `zig build test` runs, on the development host, by a method that the README describes.
It names the tests that take most of the run time, and it reduces their cost under the rules above.

## Exact test cases

1. Controller, every host: a gate whose command starts a child process that sleeps for 60 seconds, with a 2-second timeout, fails with `timed_out: true`.
   Its log lists the child's process ID and a command line that contains the child's marker argument, and nothing of the child keeps running.
2. Controller, every host: when the listing command cannot run, the log names the failure, the gate still fails with `timed_out: true`, and the command is stopped.
3. Controller: the gate's ordinary pass and fail records are unchanged by this task, as the existing gate cases show.

Cases 1 and 2 must fail before the change.
A mutation control that skips the listing must fail case 1.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0098/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `test-profile-before.log` and `test-profile-after.log`: the run time of every test, before and after the cost changes.
3. `mutation.log` and its diff.
4. An uncached `tests-after.log` with `zig build test --summary all`, `controller-tests-after.log`, and `fmt.log`.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`.
After the push, the integrator starts the `Gates` workflow on `master` at least ten times with `gh workflow run`, records each run with `gh run view`, and reports each Windows and Linux `zig-test` step's duration in `ci/README.md`.
The task is accepted only when the slowest of those durations is at most 400 seconds, two thirds of the timeout, and every run passes; otherwise it needs a separate reviewed change to the timeout.

## Authority

Writable paths: `src`, `tests`, `tools`, `build.zig`, `.github`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged, including `engineering/gates.json`.
Required reviewer: `fairpane-review`.

## Non-goals

- No change to the gate's arguments, its timeout, or any other gate.
- No new CI job, runner, action, or cache.
- No conclusion about the three timed-out runs beyond what the records show.

## Amendments

1. Before dispatch, the integrator removed the prerequisite `FP-0067` in plan commit `1600761`.
   `FP-0067`'s first `Gates` run timed out in `zig-test`, so `FP-0067` cannot be accepted until this task lands, and its code is already in the base.
   The two facts that this amendment adds to "Measured inputs" narrow the search: the cost arrived with the FP-0014 CSS tests, and both runners exceed the timeout.

## Revision 1

Base: the commit that freezes this revision.
Source findings: `reviews/review-1-reject.json`.
Every section above stays in force except where this revision replaces it.
Writable paths stay as above.

### Integrator decisions

- Review 1 rejected `9d5638b` for one major finding: plan criteria 1 and 3 ask for the compile and run phase durations of `zig-test` on both CI jobs, and the contract recorded only whole-step durations without an approved change.
  The locked build runner reads `ZIG_BUILD_SUMMARY` from the environment (`lib/compiler/Maker.zig`, lines 296 to 300), and the gate runner passes the job's environment to the gate's command.
  Setting `ZIG_BUILD_SUMMARY: all` on the `zig-test` step of both jobs therefore puts each build step's result and duration into the gate log, which the uploaded receipts keep.
  That changes neither the gate's arguments nor its timeout and adds no job, runner, action, or cache, so criteria 1 and 3 stay as written.
- Criterion 4 applies to the runs that criterion 3 dispatches after the change, as `ci/README.md` already applied it.
- Review 1's minor finding on criterion 2 is a real gap: the fixture of cases 1 and 2 prints nothing, so no case shows that a timed-out gate keeps its command's output.
- Review 1's note on a command that ends during the listing is folded in, because a log without a timeout section does not explain itself, and this task makes timeouts diagnosable.

### Behavior

- When the command ends while the timeout listing runs, the log still gets the line `TIMEOUT The command ended during the listing.` before the gate closes it, and the receipt keeps `timed_out: true`.
  The gate stops any descendant that is still alive, as it does after a listing.
- Both `Run gate zig-test` steps of `.github/workflows/gates.yml` set `ZIG_BUILD_SUMMARY: all` in their `env`, and no other step or gate changes.
  The workflow checker accepts that key on those steps, and only there.

### Exact test cases

1. Cases 1 and 2: the hung fixture prints the line `fp0098-output <marker>` before it waits, and each case asserts that the gate log holds that line after the `TIMEOUT` section.
2. A new controller case, every host: `runProcess` of a sleeping command with a timeout of at most 500 ms and a `processListing` stand-in that stops the command itself and resolves only after the command has exited.
   The result has `timed_out: true`, the log holds `TIMEOUT The command ended during the listing.`, and no descendant of the command keeps running.
3. A workflow checker case: the committed workflow passes, a `zig-test` step without the key fails with a message that names the step, and the key on any other step fails.

Cases 2 and 3 must fail before the change.
Case 1 passes before the change, because `finish` already copies the output after a stop, so a mutation control that skips that copy for a stopped command must fail it.
A mutation control that drops the new line must fail case 2.

### README corrections

- The part-to-construct mapping of the case 46 split in `raw/probe-case46-parts.log` is marked [INFERENCE], because no diff of the split was recorded.
- "No log was deleted or overwritten" is limited to the worker's session, and the integrator's removal of `raw/linux-node-probe.log` in `29a9f8e` is stated there.
- The open item about the dispatched runs points to `ci/README.md` and its result.
- One sentence explains that the integration run has 300 tests and the worker's tree 293, because commits between the worker's base `937a06b` and `9d5638b` added tests.
- The statements that other agents ran builds on the same host and that the worker did not commit, push, or dispatch a run are marked [INFERENCE].

### Revision 1 evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0098/raw/`, with the suffix `-r1`, and keep each failed attempt as its own log.

1. `tests-before-r1.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `mutation-r1.log` and its diffs for both controls, with the hash of each changed file before, during, and after.
3. `controller-tests-after-r1.log` with `node tools/fairpane.mjs test`, which reports the duration of each new or changed case.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`, and re-records `ci/dispatched-runs.log` with each run's `headBranch`.
After the push, the integrator starts the `Gates` workflow on `master` at least ten times with `gh workflow run`, records each run with `gh run view`, downloads both jobs' receipts, and reports in `ci/README.md` each run's `zig-test` duration and the duration that the build summary gives for each compile step and each run step.
The task is accepted only when every one of those runs passes and its slowest `zig-test` duration is at most 400 seconds.
