# FP-0003 evidence

## Scope

This record covers task `FP-0003`, "Pin source corpora and preserve provenance".
`CONTRACT.md` freezes its behavior, its twenty-one test cases, and its `## Revision 1` and `## Revision 2` changes.
The first patch was rejected by `fairpane-review` and `fairpane-spec`; `reviews/` keeps both verdicts.
An isolated `fairpane-core` worker wrote the revision 1 rework.
Revision 1 received `reviews/review-2-accept.json` from `fairpane-review` and `reviews/spec-review-2-reject.json` from `fairpane-spec`.
An isolated `fairpane-core` worker wrote the revision 2 rework that answers both.
The protected `specs/corpora.json` is unchanged.

## Pinned corpora

| Corpus | Commit | Tree | Entries | Blob bytes | Inventory SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Test262 | `2e0a56762801e275a9fdf96dc49d90ba0cddcf63` | `6a4268a9354a545d41c3b62efebc478ed8c521f4` | 57013 | 90245391 | `4d86002fe32f66581faa24e4843360ecd148ca44d2adacd31ef08f74d7e8acd8` |
| WPT | `b60c4b349d9d167bf354a40bc0d4cbed15174606` | `a499343a14a03239fe23fdb3b183732ddaa6cf4b` | 164551 | 505155316 | `0be4a67e0e13f7fb1f9d82324a118dd3851acbcb50752ecb3615eb1391e395ab` |

The WPT snapshot also keeps the wpt.fyi manifest: 40224677 bytes, SHA-256 `86d55bee991997a4753d0987397883249a0d6fc94e0901ed3efb84cceed53067`.
`specs/snapshots/test262.json` and `specs/snapshots/wpt.json` hold the full records.
`raw/corpus-fetch-test262.log` and `raw/corpus-fetch-wpt.log` record the original `ls-remote` and fetch commands.
`raw/corpus-fetch-wpt-manifest.log` records the revision 1 refetch of the same WPT commit into a fresh repository.
That run downloaded the manifest, checked `x-wpt-sha`, bound every manifest path and hash to the pinned tree, and reproduced the earlier inventory digest.
The snapshots live outside version control under `.tools/corpora`.

## Applicability

`specs/applicability/test262.json` counts 53616 discovered tests, with 0 selected, 0 excluded, and 53616 unclassified.
Revision 1 excludes every file name that contains `_FIXTURE`; the count did not change at the pinned commit.
`raw/rework-corpus-applicability-test262.log` records the regenerating command.

`specs/applicability/wpt.json` counts 76620 discovered tests, with 0 selected, 0 excluded, and 76620 unclassified.
The per-type counts are `aamtest` 190, `crashtest` 2030, `manual` 3047, `print-reftest` 432, `reftest` 28489, `test262` 20, `testharness` 39050, `visual` 2714, and `wdspec` 648.
The 20 counted `test262` items are WPT-authored smoke tests under `infrastructure/test262/`.
The record reports the 53640 vendored `test262` items under `third_party/test262/` separately.
They are 53597 Test262 tests under `third_party/test262/test/` and 43 Test262 harness includes under `third_party/test262/harness/`.
Only those vendored items are tied to vendored Test262 revision `7ab7fafa0003f73fc85c1b95d88094d33f7eb8bd`.
It also lists 41779 `support` items, which are not tests.
`raw/rev2-corpus-applicability-wpt.log` records the regenerating command, which exited with status 0.
Revision 1 counted 76600 discovered tests and attributed all 53660 `test262` items to the vendored copy; `raw/corpus-applicability-wpt.log` keeps that run.
Revision 2 moved the 20 `infrastructure/test262/` items into discovery, so discovery rose by 20.

### Superseded WPT manifest-tool attempt

The first patch ran the pinned WPT manifest tool and recorded no WPT count.
`raw/wpt-manifest.log` records that attempt.
The WPT manifest tool exited with status 70 after `ModuleNotFoundError: No module named 'yaml'`.
The controller command `corpus-applicability wpt` then exited with status 1.
`raw/python-modules.log` and `raw/pyyaml-6.0.1-files.log` record the missing module and the published wheel tags.
Revision 1 removed the tool run, because it executed corpus code and still produced no denominator.

## Verification

`raw/rev2-corpus-verify-test262.log` and `raw/rev2-corpus-verify-wpt.log` record revision 2 `corpus-verify` runs.
Both returned `pass` with exit status 0 and an empty `missing_denominators` list.
The WPT run recomputed 76620 discovered tests and matched the regenerated `specs/applicability/wpt.json`.

For WPT, verification covers these checks.

- `git fsck --full --strict --no-dangling` rehashes every snapshot object.
- The local ref, tree, committer date, license record, and inventory match the record.
- The stored manifest's size and SHA-256 match the record, every manifest path and hash matches the pinned tree, and the manifest has at least one test item.
- The recomputed applicability record, including every per-type count and the vendored `test262` counts, matches `specs/applicability/wpt.json`.
- The record matches every pin in `specs/corpora.json`; the current file pins nothing, so this check passes vacuously.

WPT verification does not prove that wpt.fyi classified each file the way the pinned manifest tool would.
ADR 0003 records that trust decision.

`raw/corpus-verify.log` keeps the first patch's runs and the integration acceptance runs.
Its last two runs are the exact acceptance commands from `CONTRACT.md`, run from `C:\src\fairpane` without environment overrides after the revision 1 integration.
`corpus-verify test262` started at 2026-10-09T01:30:55.818Z and exited with status 0, as line 84 records.
`corpus-verify wpt` started at 2026-10-09T01:30:57.870Z and exited with status 0, as line 118 records.
Those runs verified the revision 1 records, with WPT at 76600 discovered tests, so they predate revision 2.
`raw/rework-corpus-verify-test262.log` and `raw/rework-corpus-verify-wpt.log` record the revision 1 worker's runs.
`raw/corpus-verify-test262.log` and `raw/corpus-verify-wpt.log` keep the first patch's runs as history; their WPT `pass` covered only the snapshot, not applicability.
`raw/corpus-verify-missing-snapshot.log` shows `corpus-verify` failing with status 1 when the snapshot is absent.

## Tests

`raw/rework-tests-before.log` records the revision 1 failing baseline after cases 9 through 16 were added: 86 tests, 79 passing, 7 failing, exit status 1.
Case 10 passed in that baseline, because the first patch already exited with status 1 on an inventory mismatch; the case adds the missing coverage.
`raw/rework-tests-after.log` records 86 tests, 86 passing, 0 failing, exit status 0.
`raw/rework-check.log` records `check` with exit status 0.

`raw/rev2-tests-before.log` records the revision 2 baseline after cases 17 through 21 were added.
Its first run, at 2026-10-09T01:52:08.231Z, exited with status 1 on a syntax error in the new test code, before any test ran.
Its second run, at 2026-10-09T01:52:26.478Z, ran 107 tests: 102 passed, and cases 17 through 21 failed, with exit status 1.
Case 17 failed because discovery did not count the `infrastructure/test262/` item.
Case 18 failed because an empty manifest still bound.
Cases 19 through 21 failed because the controller rejected the local `file://` fixture upstream.
`raw/rev2-tests-after.log` records 107 tests, 107 passing, 0 failing, exit status 0.
The base tree of the revision 2 worktree held 102 controller tests, which include FP-0002 attestation cases that the 01:30 gate run did not have.
`raw/rev2-check.log` records `check` with exit status 0 after the revision 2 changes.

### Revision 2 test cases

- Case 17 counts a fixture `infrastructure/test262/` item in discovery and reports the vendored test and harness items by path.
- Case 18 rejects an empty manifest, a manifest with only `spec`, `support`, and vendored `test262` items, and an applicability record with zero discovered tests.
- Case 19 fetches the pinned commit from a local `file://` upstream after its branch moves, verifies the snapshot, and refetches through the snapshot-record pin.
- Case 20 rejects a fetch whose record differs from an `inventory_sha256` or `license_record` pin, and leaves the snapshot files, the record bytes, and no staging directory behind.
- Case 21 repins to the moved branch head, reports the `revision` and `inventory_sha256` differences, and then fails verification against the old pin.

## Environment of the worker runs

The workers ran in Git worktrees, so each rework and `rev2-` `RESULT` line records that worktree as `cwd`.
The corpus runs set `FAIRPANE_CORPORA_DIR` to the shared snapshot root, as each `RESULT` line's `environment_overrides` shows.
The acceptance commands in `CONTRACT.md` run without overrides from the repository root.

## Gates

`gates/` keeps the first patch's `repo-check` and `controller-test` receipts from 2026-10-09T00:48:44 as history.
They bind source digest `95d74b67ef7b7d1b234c1cdba198af30861d9fc66b76b5ab050afc23e5ba30cf`.
The revision 1 integration receipts are `gates/2026-10-09T01-30-40-258Z-repo-check-77f92948.json` and `gates/2026-10-09T01-30-40-501Z-controller-test-0964454f.json`.
Both have status `pass` and bind source digest `9aedf581e65e9966043b8c09faf008e88d8a18171df196252012260e75e487d5`.
The controller-test log for that receipt records 86 tests, 86 passing, and 0 failing.
Those receipts predate revision 2 and no longer match its source.
The integrator reruns both gates and the acceptance commands at the revision 2 commit.

## Open items

- `fairpane-review` and `fairpane-spec` review revision 2.
- `fairpane-spec` approves `specs/applicability/wpt.json` and the new `specs/IMPORT_REQUIREMENTS.md` and `specs/sources.json` entries.
- The integrator applies the `specs/corpora.json` pins from ADR 0003 in a separate commit after both approvals.
