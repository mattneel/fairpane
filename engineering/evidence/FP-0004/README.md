# FP-0004 evidence

## Scope

This record covers task `FP-0004`, "Implement checked owners and generational handles".
`CONTRACT.md` freezes its behavior and fourteen test cases.
An isolated `fairpane-core` worker wrote the patch, and the root integrator reviewed and applied it.

## Implementation

`src/handles.zig` defines `OwnerId`, `OwnerIdSource`, the process-wide engine owner source, and `Table(T, config)`.
Each table instantiation declares its own `Handle` type with owner, index, and generation fields and no pointer.
Slots hold a generation and one state: a live value, a free-list link, or retirement.
The free list is last in, first out.
`remove` retires a slot at the maximum generation, so no table issues an owner, index, and generation triple twice.
`reserveSlot` is the only allocation point, and it runs before any state change.
`api/README.md` states that internal handles never cross the C ABI or the process protocol directly.

## Worker records

`raw/failing-first.log` shows that the tests failed to compile before the implementation existed.
That run exited with status 1 and 16 undeclared-identifier errors.
The test of the process-wide owner source was added after that run.
`raw/zig-fmt.log`, `raw/zig-test.log`, and `raw/zig-build.log` hold the worker's runs, which record no working directory.

## Review

`reviews/review-1-accept.json` accepted commit `9ce3154` with low and informational findings.
`raw/accepted-commit-verification.log` rechecks every receipt in a clean worktree of `9ce3154`.
Review finding F3 moves owner uniqueness per table instance into task `FP-0006`.

## Integration gates

Every receipt in `gates/` binds source digest `6bab90ec12824f17db3abbfbab6866ba260db37133fda289f29f8d51bb21dbde` with 78 files.
Every receipt binds policy digest `0d9ebeb68c7cd21f2e2d7cec6ce68cefc1b4aec3d59be8a6a4668b69bda345e1` with 12 files.

| Gate | Result | Command exits |
| --- | --- | --- |
| `repo-check` | pass | 0 |
| `controller-test` | pass | 0 |
| `zig-fmt` | pass | 0 |
| `zig-test` | pass | 0 |
| `zig-build` | pass | 0 |
| `c-abi` | pass | 0, 0, 0 |

`raw/gate-evidence-check.log` shows each receipt passing `evidence-check`.
`raw/integrator-zig-test-summary.log` runs `zig build test --summary all` with a fresh cache directory.
It reports 22 of 22 tests passed: the 7 earlier tests, the 14 contract cases, and one test of the process-wide owner source.

## Limits

- Tables are single-thread structures; only owner issuance is thread-safe.
- No C ABI or process-protocol identifier exists yet.
  Task `FP-0006` defines the first boundary conversion.
