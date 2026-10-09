# FP-0051 evidence

## Scope

Task `FP-0051` closes the findings of `engineering/evidence/FP-0002/reviews/review-3-accept.json`.
The frozen contract is `engineering/evidence/FP-0051/CONTRACT.md`, based on commit `9ee1725`.
The root integrator implemented it in commit `199b279`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Report a verifier in a linked work tree of the candidate repository as advisory, with a test. | `enclosingGitDirectories` in `tools/attest.mjs`, the advisory check in `tools/fairpane.mjs`, and cases FP-0051 1 and 2. |
| Reserve `unknown-candidate` for a missing commit object, and report other Git failures as tool errors, with a corrupted-object fixture. | `candidateIdentity` and case FP-0051 3, with an invalid zlib stream, a hash mismatch, a malformed commit body, a missing object, and a tree ID. |
| Reject a policy path whose spelling or real path lies inside the candidate, and read the checked real path. | `loadTrustPolicy`, which resolves every directory on the way to the path, and case FP-0051 4, with a link inside the candidate and an alias of its root. |
| Document the UNC and administrative-share alias limit. | ADR 0002, "Protected trust input", and `tools/README.md`. |
| Make the outside-repository test independent of the temporary directory's location. | Case 14 asks Git itself, through `git rev-parse --show-toplevel` without inherited `GIT_*` variables, which tool error to expect. |

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

The verifier finds work trees of the candidate through every `.git` entry on its own path, but a layout that Git finds only through `GIT_DIR` or `core.worktree` is not detected.
Path comparison cannot detect a UNC or administrative-share alias of the candidate.

## Revision 1

`reviews/review-1-reject.json` rejected commit `199b279` for three defects.
A policy path spelled through an alias of the candidate root passed the lexical check, status 1 from the commit lookup also covered existing commits that Git cannot read, and the discovery stopped at the first `.git` entry.
Commit `9b878bc` implements contract revision 1.

`raw/revision-1-tests-before.log` records the staging of the baseline copy: `HEAD`, the blob ID of `tools/attest.mjs`, the matching `git hash-object` of the staged copy, and the stub that wraps the base function.
In that run, revision cases 2, 3, and 4 fail, and case 13 fails because the copy sits in a subdirectory of the repository.

| Log | Result |
| --- | --- |
| `raw/revision-1-binding.log` | `HEAD` `9b878bc`, and an empty status, including untracked and ignored files, for every source root. |
| `raw/revision-1-tests-after.log` | `node tools/attest.test.mjs` passes 18 of 18 cases. |
| `raw/revision-1-tests-bun.log` | Bun runs 143 of 143 controller tests. |

- `gates/2026-10-09T04-27-14-161Z-repo-check-602ded0e.json`
- `gates/2026-10-09T04-27-14-360Z-controller-test-72b7bc63.json`, with 143 of 143 controller tests.
