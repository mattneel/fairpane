# FP-0053 evidence

## Scope

Task `FP-0053` closes the findings of `engineering/evidence/FP-0031/reviews/review-1-accept.json`.
The frozen contract is `engineering/evidence/FP-0053/CONTRACT.md`, based on commit `101ba28`.
The root integrator implemented it in commit `8af0f20`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Move the mutation-control harness into the controller source inventory. | `tools/mutation-harness.mjs`, imported by the controller test and by `engineering/evidence/FP-0028/controls/mutants.mjs`. |
| Retry a failed capture-directory removal a bounded number of times before the record reports the failure. | `removeCapture` in `tools/lib.mjs`, and the controller test "A busy capture directory is removed on a later attempt, and the last failure is recorded", which covers cases 1 through 3. |
| Add a mutant that removes the log close in `finishRecord`, killed by the log-close assertions alone. | The mutant "the log stays open after the RESULT line" in `raw/mutation-control.log`, killed by the capture-start test with the message "The log descriptor stayed open." |
| Include the command record's error in the short-write assertion message. | The short-write test in `tools/selftest.mjs`. |
| Apply each mutant's replacement text literally. | `runControl` in `tools/mutation-harness.mjs` and case 4 in the mutation-control controller test. |

## Records

`raw/tests-before.log` holds two runs of `node tools/selftest.mjs` before the implementation.
In the first, the retry test fails and the harness test cannot import `tools/mutation-harness.mjs`.
The second follows the unchanged move of the harness: the retry test still fails, and the harness test fails because `$&$&` became `X1X1`.

| Log | Result |
| --- | --- |
| `raw/binding.log` | `HEAD` `8af0f20` and a status whose only untracked file is that log. |
| `raw/tests-bun.log` | Bun runs 143 of 143 controller tests. |
| `raw/mutation-control.log` | The unmutated baseline passes 143 of 143 tests, and 15 of 15 mutants are killed. |

- `gates/2026-10-09T02-56-24-373Z-repo-check-5bca9917.json`
- `gates/2026-10-09T02-56-24-558Z-controller-test-d8c85c29.json`, with 143 of 143 controller tests.
