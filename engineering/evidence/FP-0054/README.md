# FP-0054 evidence

## Scope

Task `FP-0054` closes the findings of `engineering/evidence/FP-0007/reviews/review-1-accept.json` and `engineering/evidence/FP-0053/reviews/review-1-accept.json`.
The frozen contract is `engineering/evidence/FP-0054/CONTRACT.md`.
The worker implemented it in an isolated working tree whose `HEAD` was `f53f465`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| A case file one byte above 64 MiB is a harness error that names the size limit, with exit status 3. | `readInputFile` and `fileFailure` in `src/lab.zig`, and Zig case 1. |
| The laboratory documents the outcome precedence and the meaning of the fetch stage status. | The doc comments of `conclude` and `Run.stageStatus` in `src/lab.zig`. |
| A transcript records an action count, so a transcript with removed actions replays as a harness error. | Transcript version 2 in `Run.writeTranscript` and `Parser.transcript`, and Zig case 2. |
| A minimized case is marked as derived from the original case digest. | Case version 2, `DerivedFrom`, `minimize`, and `writeCase` in `src/lab.zig`, and Zig cases 3 and 4. |
| The laboratory compares file identities, not path spellings, when it refuses to overwrite its input. | `refuseInputAsOutput` in `src/lab_main.zig`, and build-step case 5. |
| The capture-removal retry cases are split and test the last error, a non-listed error code, and the waits. | The three `FP-0054 case 6` retry tests in `tools/selftest.mjs`. |
| A test asserts that a RESULT line exists before it parses one. | `lastResult` in `tools/selftest.mjs`, and the `FP-0054 case 6` test of that assertion. |

## Records

`raw/tests-before.log` holds three runs before the implementation.

1. `zig build test --cache-dir out/fp0054-before` fails to compile, because cases 1 and 3 name `readInputFile`, `fileFailure`, and `Case.derived_from`, which do not exist yet.
   The compile error masks every Zig case.
2. `node tools/fairpane.mjs test` fails 1 of 158 tests.
   The `lastResult` case fails with a `TypeError` instead of an `AssertionError`.
   The three retry tests pass, because they only tighten tests of the existing `removeCapture` behavior.
3. `zig build test --cache-dir out/fp0054-before-behavior` ran with case 1 and the six lines of case 3 that parse the written case through `Case.derived_from` removed, so the other cases compile.
   Cases 2, 3, and 4 fail, and 101 of 104 unit tests pass.
   Case 5 fails: `minimize` reports `pass` with exit status 0 instead of refusing, and a passing minimization writes its output over the private copy of its input.
   The `check same` step did not run, because it depends on the failed step.
   Every FP-0007 case passes.
   The removed lines were restored unchanged after the run.

| Log | RESULT |
| --- | --- |
| `raw/tests-before.log`, run 1 | `exit_code` 1 |
| `raw/tests-before.log`, run 2 | `exit_code` 1, 157 of 158 controller tests |
| `raw/tests-before.log`, run 3 | `exit_code` 1, 16 of 20 steps and 101 of 104 unit tests |
| `raw/tests-after.log` | `exit_code` 0, 20 of 20 steps and 105 of 105 unit tests, with the fresh cache `out/fp0054-after` |
| `raw/controller-tests-after.log` | `exit_code` 0, 158 of 158 controller tests |

The integrator applied the patch without conflicts and committed it as `0dda99b`.
`raw/integration-binding.log` records `HEAD` `0dda99b` and an empty status, including ignored files, for every source root.

- `gates/2026-10-09T09-30-14-403Z-repo-check-36895c39.json`
- `gates/2026-10-09T09-30-14-629Z-controller-test-3bd5fe05.json`, with 158 of 158 controller tests.
- `gates/2026-10-09T09-30-38-580Z-zig-fmt-d934cf34.json`
- `gates/2026-10-09T09-30-38-772Z-zig-test-f29ff3ec.json`

`raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0054-integration-cache`: 38 of 38 build steps and 136 of 136 tests, which include the FP-0011 tests that landed after the worker's base.
`raw/integration-bun.log` records Bun with 158 of 158 controller tests.

## Resolved ambiguities

- The size test extends a new file with `File.setLength` and writes no byte.
  The file system decides whether the file is sparse.
  The test also checks that `fileFailure` names the size limit and that the harness error has exit status 3.
- `fileFailure` keeps the name of the moved `lab_main.zig` function, because the command line also uses it for transcript and output write failures.
- A case may have version 1 or 2, so `case-01-wrong-version.json` now has version 3, and FP-0007 case 1 expects `version: expected 1 or 2`.
- A version 2 case reports `corpus: expected null in version 2` before it checks `derived_from`.
- `derived_from.corpus` uses the corpus rules of `corpus`, with subjects under `derived_from.corpus`.
- Minimizing a version 2 case writes a new version 2 case whose `derived_from` names the input case's digest and its `null` corpus, as the contract states.
  The chain of digests still leads to the original corpus item.
- The result document keeps version 1, and its `corpus` member stays the case's `corpus` value.
- The output-path guard refuses equal spellings first.
  An output path that does not exist is not the input file.
  Any other failure to resolve either real path is a harness error that names the file.
- Case 5 runs `minimize` in a private copy of `case-03-body-mismatch.json`, passing the input as an absolute path and `--out case.json` relative to the copy's directory.
  `check same` then compares the copy with the fixture.
- The first retry test keeps the phrase "busy capture directory is removed on a later attempt", so the FP-0028 mutant `a busy capture directory gets no second attempt` still selects it.
- The wait test measures the time between the first and third removal attempts, not the record's `duration_ms`, which also counts the child process.
  The 140 millisecond bound allows 10 milliseconds below the 150 milliseconds of waits.

No mutation control ran in this task.
`[INFERENCE]` The split tests would fail the mutants that the FP-0053 review named: recording the first error, retrying every coded error, and removing the waits.
