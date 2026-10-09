# FP-0002 evidence

## Scope

Task `FP-0002` designs and tests the protected qualification boundary.
The frozen contract is `engineering/evidence/FP-0002/CONTRACT.md`, including revision 1.
The root integrator implemented it in `tools/attest.mjs`, `tools/attest.test.mjs`, the `attest-verify` controller command, and ADR 0002.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Demonstrate why a writable local checker cannot attest its own author. | Controller case 1 forges a passing receipt that `validateReceipt` accepts without gate execution. |
| Define a separate protected policy input and immutable candidate source identity. | ADR 0002, `loadTrustPolicy`, and `candidateIdentity`, with cases 13 and 14. |
| Reject forged, stale, truncated, zero-denominator, and changed-policy result records. | Cases 4 through 12 and 16. |
| Implement an independently testable verifier before any release success path. | `tools/attest.mjs` imports nothing from the receipt code, and `raw/attest-standalone.log` runs its fourteen cases alone. |
| Keep release-check fail-closed until that verifier qualifies. | Case 15 and `raw/release-check.log`, which exits with status 1. |

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
