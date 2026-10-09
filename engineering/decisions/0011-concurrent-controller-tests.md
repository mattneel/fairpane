# ADR 0011: Concurrent controller tests

Status: proposed until `fairpane-review` accepts task `FP-0107`.
Owner: the root integrator.
Date: 2026-10-09.
Related tasks: `FP-0098`, `FP-0107`.

## Decision

`tools/selftest.mjs` runs its ordinary cases on four worker threads through `runCases` and `casePool` in `tools/test-runner.mjs`.
A case that changes process-wide state declares it when it is registered, and it runs on the main thread while no other case runs.
The runner prints each case's duration, the ten slowest cases, and the total duration.
The `controller-test` gate keeps its arguments and its 120000 ms timeout.
Each worker thread gets its own copy of the environment from `workerEnvironment`, which on Windows names the search path `PATH` and the system root `SystemRoot`, the spellings that the tools read.
A worker's copy matches names with regard to letter case, while the main thread's `process.env` on Windows does not, and the hosted Windows runner's search path reaches a worker as `Path` [INFERENCE: the runs of `3e7128c` failed as a local run with that spelling fails].
The runner does not share the main thread's environment through `SHARE_ENV`: with it, an undeclared worker case that changes `TMP` reaches the cases on other workers, and Bun 1.4.2's main-thread `os.tmpdir()` stops following `process.env`.

## Evidence

`engineering/evidence/FP-0107/` records the suite before and after the change on Windows and on WSL Ubuntu.
On the development host, the 238 base cases took 79426 ms one at a time, and the 240 cases took 37968 ms on four threads.
A child-process probe of the base suite counted 1857 child processes, 1756 of them `git`, and 49 seconds in which a synchronous child-process call blocked the thread.
[INFERENCE] A synchronous child-process call blocks every case that shares its thread, so concurrency within one thread would not remove that wait, and worker threads do; no run measured concurrency within one thread.
On WSL Ubuntu, the suite took 17690 ms before and 11414 ms after, and the base case with 110 `git` starts took 284 ms there and 3274 ms on Windows.
A mutation control that ignores the declaration fails three existing cases besides `FP-0107` case 2.
FP-0107 revision 1 reproduces the hosted-runner failure locally with the search path named `Path` and records the `SHARE_ENV` probe, and revision 2 declares the five `withPrivateTemp` cases that revision 1 left undeclared.

## Consequences

- A new case that changes the working directory, a `process.env` variable, or a module-level function must declare it, or it can break cases that run beside it.
- A worker thread cannot change the working directory, so such a case fails loudly when it lacks the declaration.
- Output that a case prints can appear between the result lines of other cases; the result lines keep the order of case numbers.
- A per-case duration includes the contention of the cases that run beside it.

## Reversal condition

Revisit this decision when the suite no longer needs concurrency to stay well within its timeout, or when a case cannot be made independent of the cases beside it.
A reversal passes `concurrency: 1` to `runCases` and runs every case on the main thread, which keeps the duration report.
