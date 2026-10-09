# OMP development operations

## Integration model

The root session acts as integrator and durable-state owner.
Project specialists live in `.omp/agents`.
OMP discovers that directory and supports explicit tool grants. [S03]
Prompt templates live in `.omp/prompts`. [S02]

The project configuration does not select a provider or overwrite credentials.
Specialists inherit the owner's configured model unless an explicit local choice replaces it.
Concurrency starts at four to preserve review capacity and machine resources.
That value is not a token-cost optimization.

No autonomous daemon ships in this archive.
A session performs work while the user runs OMP.
Durable state permits later continuation without claims of background delivery.

## Configuration

The supplied task settings disable the soft request budget and hard task deadline.
They retain bounded recursion and controlled concurrency.
Individual tests still have watchdogs because a hang is an observable failure.
The project disables automatic application of isolated changes. [S04]

The documentation baseline is OMP's public source at package version 18.8.6.
That value is an observation, not an installed-version claim or forced dependency pin.
The first task checks the actual version and current configuration schema.
Unknown settings must not silently disable isolation or approvals.

## Delegation procedure

1. Read the selected task's frozen contract.
2. Check its prerequisites and writable paths.
3. Create an isolated workspace after a Git baseline exists.
4. Assign the exact named specialist and contract.
5. Capture the patch and full result artifacts.
6. Run independent tests against the patch.
7. Review behavior and protected-path changes.
8. Apply accepted changes through the integrator.
9. Run the affected gates again on the integration head.

## Work-unit contract

Each task identifies its base source and prerequisites.
It names its allowed paths, protected paths, behavior, tests, and required review.
A broad workstream first decomposes into concrete behavior slices.
"Implement JavaScript" is not a bounded delegation.

A worker result includes changed files and exact commands.
It includes failing cases and unresolved questions.
The result names any unmet acceptance criterion.
A prose claim of success is not an acceptance receipt.

A worker keeps each failed or abandoned attempt as its own raw log, such as `tests-before-attempt-1.log`, and never deletes it.
Every recorded Zig command names its cache override through `node tools/fairpane.mjs record --env`.
A recorded command captures only what the task needs, because the evidence is public.
It never lists a home directory, a user profile, or another unrelated user file, and it never records a credential or token.
The integrator reviews each worker's new logs for such content before committing them.
The integrator records `HEAD` and a status that includes ignored files for every source root before the gates, and records both again after the last run.

## Durable state

`engineering/plan.json` contains task contracts.
`engineering/state.json` contains task status and review references.
`engineering/HANDOFF.md` identifies the next executable action.
`engineering/decisions` contains architecture decisions.
`out/evidence` contains local receipts and logs.
`engineering/evidence` contains reviewed, tracked evidence.

The integrator alone updates shared state during concurrent work.
The local controller does not act as a distributed scheduler or lock service.
Task acceptance needs valid gate evidence and an independent review record.
The first protected-runner task strengthens that boundary beyond local files.

A change to a task's criteria, dependencies, or paths in `engineering/plan.json` lands in its own `plan:` commit, never inside a task's evidence or source commit.
An independent reviewer approves each such change, and the approval record lands under `engineering/evidence/plan/reviews/`.

## Git operations

The integrator alone commits to `master` and pushes it to `origin`.
Workers leave their changes in isolated worktrees for review.
Each checkpoint is committed as soon as its checks pass, and commits are pushed in batches at the push boundaries that `docs/GIT_OPERATIONS.md` defines, because each push runs the full `Gates` workflow.
`docs/GIT_OPERATIONS.md` defines the complete procedure and history rules.
The integrator checks the `Gates` run of each pushed head.
A failed run blocks acceptance of every task whose implementation it contains, and the failure is recorded in that task's evidence with its run ID.
The integrator accepts a task only after the runs of every pushed head from its implementation commit to the head before the acceptance commit have concluded.
Each of those runs must pass, or its failure must be recorded with its cause and a passing rerun of the same head.
When a later commit fixes the recorded cause, a passing run of a later head in that range may replace the rerun of the same head.
The replacing head contains both the task's implementation and the fix, and the failure record shows each of the following conditions.

- The record names the failed gate and step from the failed run's own receipt, log, or job record.
- It gives evidence that the cause makes that step fail on the failed head's sources, and it marks the attribution [INFERENCE] where the failed run kept no output.
- The fixing commits are the implementation and revisions of a task accepted before this acceptance, or each has its own `fairpane-review` record in `engineering/evidence` that predates this acceptance.
- The fixing task's evidence shows that the cause no longer fails the gate.
  When the cause is intermittent, that evidence has at least ten concluded runs, or the larger count that the fixing task's contract froze.
- The fixing commits remove, skip, exclude, or weaken no test, gate, timeout, or threshold.
- No commit from the failed head to the replacing head changes the failed gate's entry in `engineering/gates.json`, the workflow job that runs it, or the locked toolchain that it uses, or removes, skips, excludes, or weakens a test that the failed step runs.
  The record includes `git diff --stat <failed>..<replacing> -- engineering/gates.json .github/workflows toolchains tools/lib.mjs build.zig` and the same for the test sources of the failed step.
- The record names each change in that range to the gate runner in `tools/lib.mjs` or to the build steps in `build.zig`, and states why that change cannot make the replacing run pass; otherwise only a passing rerun of the same head is allowed.

If the cause cannot be tied to the failed step, even as an inference, only a passing rerun of the same head is allowed.
A run that a timeout stops is a failure.
A cancelled run is recorded with its reason and replaced by a concluded run of the same head.

`git apply --3way` stages the patch that it applies.
Before each commit, the integrator checks `git diff --cached --name-only`, so a commit holds only the files that its message names.

## Stop and continuation rules

The agent stops for a real permission boundary, unavailable tool, cancellation, or session limit.
It does not stop because the next task is difficult or the founding problem is large.
A blocked task names its blocker and an independent task that can proceed.
An exhausted task frontier requires decomposition of the next workstream.

Planning without implementation is not the default deliverable.
A checkpoint records code, tests, and actual remaining work.
