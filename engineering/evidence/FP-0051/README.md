# FP-0051 evidence

## Scope

Task `FP-0051` closes the findings of `engineering/evidence/FP-0002/reviews/review-3-accept.json`.
The frozen contract is `engineering/evidence/FP-0051/CONTRACT.md`, based on commit `9ee1725`.
The root integrator implemented it in commit `199b279`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Report a verifier in a linked work tree of the candidate repository as advisory, with a test. | `enclosingGitDirectory` in `tools/attest.mjs`, the advisory check in `tools/fairpane.mjs`, and cases FP-0051 1 and 2. |
| Reserve `unknown-candidate` for a missing commit object, and report other Git failures as tool errors, with a corrupted-object fixture. | `candidateIdentity` and case FP-0051 3. |
| Reject a policy path whose spelling or real path lies inside the candidate, and read the checked real path. | `loadTrustPolicy` and case FP-0051 4, which uses a junction on Windows. |
| Document the UNC and administrative-share alias limit. | ADR 0002, "Protected trust input", and `tools/README.md`. |
| Make the outside-repository test independent of the temporary directory's location. | Case 14 chooses its expected tool error from `enclosingGitDirectory`. |

## Records

`raw/tests-before.log` holds two runs against the base verifier.
The first exits with status 1, because the test file imports `enclosingGitDirectory`, which the base verifier lacks.
The second runs a copy of `tools/` with the base `attest.mjs` and a stub `enclosingGitDirectory` that returns null.
In it, 13 of 18 cases pass, and cases FP-0051 1 through 4 fail.
Case 13 also fails there, because that copy sits in a subdirectory of the repository, so the advisory check of the repository's own root names a path below the top level.

| Log | Result |
| --- | --- |
| `raw/tests-after.log` | `node tools/attest.test.mjs` exits with status 0, with 18 of 18 cases. |
| `raw/tests-bun.log` | Bun runs 142 of 142 controller tests. |
| `raw/binding.log` | `HEAD` `199b279` and a status whose untracked files lie outside every source root. |

- `gates/2026-10-09T02-51-13-291Z-repo-check-2fd50991.json`
- `gates/2026-10-09T02-51-13-483Z-controller-test-357278b3.json`, with 142 of 142 controller tests.

## Limits

`enclosingGitDirectory` follows Git's `.git` discovery without its ceiling directories and file system boundaries, so it can report a repository that Git itself would not search.
That error direction only makes a result advisory.
