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

## Git operations

The integrator alone commits to `master` and pushes it to `origin`.
Workers leave their changes in isolated worktrees for review.
Each checkpoint is committed and pushed as soon as its checks pass.
`docs/GIT_OPERATIONS.md` defines the complete procedure and history rules.

## Stop and continuation rules

The agent stops for a real permission boundary, unavailable tool, cancellation, or session limit.
It does not stop because the next task is difficult or the founding problem is large.
A blocked task names its blocker and an independent task that can proceed.
An exhausted task frontier requires decomposition of the next workstream.

Planning without implementation is not the default deliverable.
A checkpoint records code, tests, and actual remaining work.
