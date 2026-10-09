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
| The laboratory compares file identities, not path spellings, when it refuses to overwrite its input. | Corrected in revision 1: `refuseInputAsOutput` and `fileIdentity` in `src/lab_main.zig` compare file identities, and build-step case 5 and revision 1 cases 1 to 4 test them. The original canonical-path comparison did not meet this criterion, and `reviews/review-1-reject.json` rejected it. |
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

## Revision 1

Revision 1 of `CONTRACT.md` replaces the canonical-path guard with a file-identity guard and adds six cases.
The original work ran in an isolated working tree whose `HEAD` was `f53f465`, not the frozen base `ab2e2ed`.
This revision ran in an isolated working tree whose `HEAD` was `005ef1e`, the commit that freezes revision 1, whose parent is `c5f7f2b`.
The host was Windows 11 Pro, `Microsoft Windows [Version 10.0.26200.9457]`, x64, which `raw/tests-after-r1.log` records.

### Implementation

- `refuseInputAsOutput` in `src/lab_main.zig` keeps the equal-spelling check first.
  When the output path exists, `fileIdentity` opens both files with `Io.Dir.openFile`, which follows symbolic links, and the guard compares their identities.
  It compares no path strings except in the equal-spelling check.
- On Windows, the identity is the `VolumeSerialNumber` and the 128-bit `FileId` of `FILE_ID_INFORMATION`, from `NtQueryInformationFile` with the `FileIdInformation` class, `FILE.INFORMATION_CLASS.Id` in the pinned standard library.
  The pinned standard library does not define `FILE_ID_INFORMATION`, so `src/lab_main.zig` defines it locally.
- On Linux, the identity is `stx_dev_major`, `stx_dev_minor`, and `stx_ino` of `statx` on the open descriptor with `AT_EMPTY_PATH`.
- On other systems, the identity is the `st_dev` and `st_ino` of `fstat`.
- An output path that does not exist is not the input file.
  Any other failure to open or identify either file is a harness error that names that file's subject, with exit status 3.
- `tests/lab/check.zig` gains `fresh`, `derived`, `absent`, and `remove`.
  `check fresh` deletes and recreates the directory of one case on every run, and every step that uses that directory has side effects, so no run reuses an earlier run's files.
- `build.zig` adds revision 1 cases 1 to 5 in `addRevision1Cases`.
  Case 3 is added only when `b.graph.host.result.os.tag` is `windows`.
- `tools/selftest.mjs` adds revision 1 case 6.

### Records

| Log | RESULT |
| --- | --- |
| `raw/tests-before-r1.log` | `exit_code` 1, 53 of 58 steps and 177 of 177 unit tests, with the new tests and the old guard and the fresh cache `out/fp0054-r1-before`. Cases 1 and 2 fail. Case 3 passes. |
| `raw/mutation-r1.log`, control 1 | `exit_code` 1, 55 of 58 steps. Only case 4 fails. |
| `raw/mutation-r1.log`, control 2 | `exit_code` 1, 55 of 58 steps. Only the case 5 `run` step fails. |
| `raw/mutation-r1.log`, control 3 | `exit_code` 1, 180 of 181 controller tests. Only case 6 fails. |
| `raw/mutation-r1.log`, control 4 | `exit_code` 1, 49 of 58 steps. Cases 1, 2, and 3 and FP-0054 case 5 fail. |
| `raw/mutation-r1.log`, restoration | `exit_code` 0 for both `git diff --no-index --exit-code` comparisons with the saved fixed sources. |
| `raw/tests-after-r1.log` | `exit_code` 0, 58 of 58 steps and 177 of 177 unit tests, with the fresh cache `out/fp0054-r1-after`. |
| `raw/controller-tests-after-r1.log` | `bun --version` 1.4.2, `node --version` v26.7.0, `exit_code` 0 with 181 of 181 controller tests, and `zig fmt --check build.zig src tests` with `exit_code` 0. |
| `raw/cross-build-r1.log` | `exit_code` 0 for `zig build lab check` with `-Dtarget=x86_64-linux` and with `-Dtarget=aarch64-macos`. These builds compile the Linux and `fstat` paths. They do not run them. |

Each control in `raw/mutation-r1.log` first records `git diff --no-index` between a saved copy of the fixed source and the mutated source.
That command exits with status 1 because the files differ.

1. Control 1, for case 4: the guard refuses every existing output path.
2. Control 2, for case 5: the `run` command's case-file subject becomes `transcript file`.
3. Control 3, for case 6: the retry condition at `tools/lib.mjs:316` becomes `e.code !== undefined && !TRANSIENT_REMOVAL.has(e.code)`.
4. Control 4, which the contract does not list: the guard compares no identities, so only equal spellings are refused.

### Resolved ambiguities

- Case 3 passes before the fix on this host.
  The old guard's canonical path of `CASE.JSON` equaled that of `case.json`, so the reviewer's inference about letter case does not hold here.
  The contract requires cases 1 to 3 to fail before the fix, which holds only for cases 1 and 2.
  Control 4 shows that case 3 fails a guard without the identity comparison.
- The pinned standard library binds no `fstat` on Linux: `std.posix.Stat` and `std.c.fstat` are `void` there.
  The Linux identity therefore comes from `statx`, whose device and inode fields are the values that `fstat` reports as `st_dev` and `st_ino`.
- The pinned `Io.Dir.hardLink` returns `error.OperationUnsupported` on Windows.
  `check fresh` therefore creates the hard link with `CreateHardLinkW`, which `tests/lab/check.zig` declares locally.
  The first attempt at `raw/tests-before-r1.log` failed in the fresh-directory step for that reason, and an earlier attempt failed because the shell removed the backslashes of the compiler path.
  The log was deleted after each attempt, and the recorded run used the corrected helper and a cache directory that was deleted before the run.
- A `NtQueryInformationFile` status other than `STATUS_SUCCESS` and `STATUS_ACCESS_DENIED` becomes `error.Unexpected`, so its detail is `<subject>: Unexpected`.
- Case 5's `minimize` names the new path `minimized.json`, and `check absent` confirms afterward that it does not exist.
- The removal step of case 5 depends on every step that reads the oversized files.
  When one of them fails, the build skips the removal step, and the next run's `check fresh` deletes the directory.
  Control 2 left both oversized files in `out/fp0054-r1-mutation-2`, and they were removed by hand after the run.
- FP-0054 case 5 keeps its `WriteFiles` copy unchanged, because revision 1 changes only the cases that it adds.
- The contract states that opening follows symbolic links, but no revision 1 case creates a symbolic link, so no test covers that path.

### Integration

The integrator applied the patch without conflicts and committed it as `78c8f7d`.
The integrator accepts the case 3 resolution: the requirement exists to show that case 3 detects a guard without identities, and control 4 shows that.
The deleted failed attempts at `raw/tests-before-r1.log` were harness setup failures that the worker disclosed above; no test result was replaced.

`raw/r1-integration-binding.log` records `HEAD` `78c8f7d` and an empty status, including ignored files, for every source root before the gates, and the status alone again after the last run.
Review 2 notes that `HEAD` was not recorded again; the reflog shows `HEAD` at `78c8f7d` until 10:05:39Z, after the last run.

- `gates/2026-10-09T10-02-10-701Z-repo-check-d21465f7.json`
- `gates/2026-10-09T10-02-11-009Z-controller-test-964bb3a4.json`, with 181 of 181 controller tests.
- `gates/2026-10-09T10-02-48-555Z-zig-fmt-521f1a7c.json`
- `gates/2026-10-09T10-02-48-799Z-zig-test-2c060ba1.json`

`raw/r1-integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0054-r1-integration-cache` and the recorded override `ZIG_GLOBAL_CACHE_DIR`: 58 of 58 build steps and 177 of 177 tests.
`raw/r1-integration-bun.log` records Bun 1.4.2 with 181 of 181 controller tests.
