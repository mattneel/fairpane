# FP-0098 task contract

## Identity

Task ID: `FP-0098`, "Keep the zig-test gate within its timeout and make a timeout diagnosable".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0067`, accepted.
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
