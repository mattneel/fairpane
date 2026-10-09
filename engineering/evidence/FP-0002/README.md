# FP-0002 evidence

## Scope

Task `FP-0002` designs and tests the protected qualification boundary.
The frozen contract is `engineering/evidence/FP-0002/CONTRACT.md`, including revisions 1, 2, and 3.
The root integrator implemented it in `tools/attest.mjs`, `tools/attest.test.mjs`, the `attest-verify` controller command, and ADR 0002.
The current implementation is commit `617d2cd`, and the section "Revision 3 records" holds its evidence.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Demonstrate why a writable local checker cannot attest its own author. | Controller case 1 forges a passing receipt that `validateReceipt` accepts without gate execution. |
| Define a separate protected policy input and immutable candidate source identity. | ADR 0002, `candidateRepository`, `loadTrustPolicy`, and `candidateIdentity`, with cases 13 and 14. |
| Reject forged, stale, truncated, zero-denominator, and changed-policy result records. | Cases 4 through 12 and 16. |
| Implement an independently testable verifier before any release success path. | `tools/attest.mjs` imports nothing from the receipt code, and `raw/revision-3-attest-standalone.log` runs its fourteen cases alone. |
| Keep release-check fail-closed until that verifier qualifies. | Case 15 and `raw/revision-3-release-check.log`, which exits with status 1. |

## Records

The integrator ran these gates with source digest `87eaa6b9ec4e02668b5aad1989e3e9a613dbf19ff2f1e7bdb0de8c9319df23aa` and policy digest `90a4c70111629ebd7d9bbbdb67c851878a432c6dff8be998342b07498df09e83`.

- `gates/2026-10-09T01-35-57-060Z-repo-check-621359f3.json`
- `gates/2026-10-09T01-35-57-244Z-controller-test-a22f024b.json`, with 102 of 102 controller tests passing on Node.

| Log | Result |
| --- | --- |
| `raw/release-check.log` | Exit status 1, with the problem that no protected runner, trust policy, or signed result set exists. |
| `raw/attest-standalone.log` | Exit status 0, with 14 of 14 verifier cases passing. |
| `raw/controller-test-bun.log` | Exit status 0, with 102 of 102 controller tests passing on Bun. |
| `raw/mutation-canonical.log` | Exit status 1: without the canonical payload rule, case 16 fails. `raw/mutation-canonical.diff` holds the mutation. |

The expected denominator is the 86 controller tests that existed at integration plus the sixteen contract cases.

## Limits

No protected runner, signing service, or key distribution exists in this task.
The repository-location check on the trust policy is a guard, not a security boundary.
Git object identity uses SHA-1 commit and tree IDs.
These records are local, unsigned integrity records.

## Revision 2 records

Review 1 rejected commit `e2eaace`, and commit `9e9a0bf` implements contract revision 2.
`raw/revision-2-binding.log` records `HEAD` at `9e9a0bf` and a clean tracked working tree before the gates ran.
The gates ran with source digest `3f673fd7598a670284882bf8efc263ff7ffec565e00af1e92ab6a73a13b12c0a` and policy digest `366776e09af8c5f000b5f2b8f85795ca4bb8f2098e9f7bc20e34ea97cb58c425`.

- `gates/2026-10-09T01-58-00-035Z-repo-check-2a910fe0.json`
- `gates/2026-10-09T01-58-00-226Z-controller-test-f88b9b11.json`, with 102 of 102 controller tests passing on Node.

| Log | Result |
| --- | --- |
| `raw/revision-2-release-check.log` | Exit status 1, with the problem that no protected runner, trust policy, or signed result set exists. |
| `raw/revision-2-attest-standalone.log` | Exit status 0, with 14 of 14 verifier cases passing. |
| `raw/revision-2-controller-test-bun.log` | Bun 1.4.2, then exit status 0 with 102 of 102 controller tests passing. |
| `raw/mutation-canonical-2.log` | Against `HEAD` `9e9a0bf`, without the canonical payload rule, case 16 reports `verified` for all three noncanonical fixtures and fails. |
| `raw/mutation-canonical-2.diff` | The exact `git diff` of that mutation. |

## Revision 3 records

Review 2 rejected commit `9e9a0bf`, and commit `617d2cd` implements contract revision 3.
`raw/revision-3-binding.log` records a fresh `git worktree add` of `617d2cd`, its `HEAD`, and an empty status that included untracked and ignored files, before the gates ran there.
The gate receipts were copied from that work tree into commit `a90597a`.
`raw/revision-3-evidence-check.log` checks both receipts with `evidence-check` inside a fresh work tree of `a90597a`, whose source files equal those of `617d2cd`.
Its first four attempts failed because they named the receipts by absolute paths, and its last two report `pass` with `current_source` true.
The gates ran with source digest `0f7e082d17ef228f5a2340e490421618f6b78da55d75cbd66531c9c61db334f0` and policy digest `782bc4031600ed76e12e503135470bfd71c6b65e6fdf3fafc00880989f5f6d53`.
That policy digest comes from the separate `policy:` commits before `617d2cd`, and `617d2cd` changes no protected file.
The suite has 118 tests: the 102 that revision 2 counted, plus the `FP-0003` corpus cases and the `FP-0033` workflow cases that landed in between.

- `gates/2026-10-09T02-12-59-099Z-repo-check-8287c88c.json`
- `gates/2026-10-09T02-12-59-289Z-controller-test-a135c7e3.json`, with 118 of 118 controller tests passing on Node.

| Log | Result |
| --- | --- |
| `raw/revision-3-release-check.log` | Exit status 1, with the problem that no protected runner, trust policy, or signed result set exists. |
| `raw/revision-3-attest-standalone.log` | Exit status 0, with 14 of 14 verifier cases passing. |
| `raw/revision-3-controller-test-bun.log` | Bun 1.4.2, then exit status 0 with 118 of 118 controller tests passing. |

The canonical payload rule did not change in revision 3, so `raw/mutation-canonical-2.log` remains its mutation control.

## Review 3

`reviews/review-3-accept.json` accepts commits `617d2cd` and `a90597a` with four minor findings and three notes.
This section answers the minor finding about the unrecorded `evidence-check` run.
Task `FP-0051` carries the remaining findings.
