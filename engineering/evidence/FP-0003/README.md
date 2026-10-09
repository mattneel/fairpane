# FP-0003 evidence

## Scope

This record covers task `FP-0003`, "Pin source corpora and preserve provenance".
`CONTRACT.md` freezes its behavior, its sixteen test cases, and its `## Revision 1` changes.
The first patch was rejected by `fairpane-review` and `fairpane-spec`; `reviews/` keeps both verdicts.
An isolated `fairpane-core` worker wrote the revision 1 rework.
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

`specs/applicability/wpt.json` counts 76600 discovered tests, with 0 selected, 0 excluded, and 76600 unclassified.
The per-type counts are `aamtest` 190, `crashtest` 2030, `manual` 3047, `print-reftest` 432, `reftest` 28489, `testharness` 39050, `visual` 2714, and `wdspec` 648.
The record reports 53660 `test262` items separately, from vendored Test262 revision `7ab7fafa0003f73fc85c1b95d88094d33f7eb8bd`.
It also lists 41779 `support` items, which are not tests.
`raw/corpus-applicability-wpt.log` records the generating command.

### Superseded WPT manifest-tool attempt

The first patch ran the pinned WPT manifest tool and recorded no WPT count.
`raw/wpt-manifest.log` records that attempt.
The WPT manifest tool exited with status 70 after `ModuleNotFoundError: No module named 'yaml'`.
The controller command `corpus-applicability wpt` then exited with status 1.
`raw/python-modules.log` and `raw/pyyaml-6.0.1-files.log` record the missing module and the published wheel tags.
Revision 1 removed the tool run, because it executed corpus code and still produced no denominator.

## Verification

`raw/rework-corpus-verify-test262.log` and `raw/rework-corpus-verify-wpt.log` record revision 1 `corpus-verify` runs.
Both returned `pass` with exit status 0 and an empty `missing_denominators` list.

For WPT, verification covers these checks.

- `git fsck --full --strict --no-dangling` rehashes every snapshot object.
- The local ref, tree, committer date, license record, and inventory match the record.
- The stored manifest's size and SHA-256 match the record, and every manifest path and hash matches the pinned tree.
- The recomputed applicability record, including every per-type count, matches `specs/applicability/wpt.json`.
- The record matches every pin in `specs/corpora.json`; the current file pins nothing, so this check passes vacuously.

WPT verification does not prove that wpt.fyi classified each file the way the pinned manifest tool would.
ADR 0003 records that trust decision.

`raw/corpus-verify.log`, `raw/corpus-verify-test262.log`, and `raw/corpus-verify-wpt.log` keep the first patch's runs as history.
Those runs predate revision 1, and their WPT `pass` covered only the snapshot, not applicability.
`raw/corpus-verify-missing-snapshot.log` shows `corpus-verify` failing with status 1 when the snapshot is absent.

## Tests

`raw/rework-tests-before.log` records the failing baseline after cases 9 through 16 were added: 86 tests, 79 passing, 7 failing, exit status 1.
Case 10 passed in that baseline, because the first patch already exited with status 1 on an inventory mismatch; the case adds the missing coverage.
`raw/rework-tests-after.log` records 86 tests, 86 passing, 0 failing, exit status 0.
`raw/rework-check.log` records `check` with exit status 0.

## Environment of the rework runs

The worker ran in a Git worktree, so each rework `RESULT` line records that worktree as `cwd`.
The corpus runs set `FAIRPANE_CORPORA_DIR` to the shared snapshot root, as each `RESULT` line's `environment_overrides` shows.
The acceptance commands in `CONTRACT.md` run without overrides from the repository root.

## Gates

`gates/` keeps the first patch's `repo-check` and `controller-test` receipts as history.
They bind source digest `95d74b67ef7b7d1b234c1cdba198af30861d9fc66b76b5ab050afc23e5ba30cf` and no longer match the current source.
The integrator reruns both gates and the `corpus-verify` acceptance commands after review.

## Open items

- `fairpane-review` and `fairpane-spec` review revision 1.
- `fairpane-spec` explicitly approves the policy-root additions under `specs`.
- The integrator applies the `specs/corpora.json` pins from ADR 0003 in a separate commit after both approvals.
