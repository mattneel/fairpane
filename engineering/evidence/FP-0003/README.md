# FP-0003 evidence

## Scope

This record covers task `FP-0003`, "Pin source corpora and preserve provenance".
`CONTRACT.md` freezes its behavior and eight test cases.
An isolated `fairpane-core` worker wrote the patch, and the root integrator reviewed and applied it.
The protected `specs/corpora.json` is unchanged.

## Pinned corpora

| Corpus | Commit | Tree | Entries | Blob bytes | Inventory SHA-256 |
| --- | --- | --- | --- | --- | --- |
| Test262 | `2e0a56762801e275a9fdf96dc49d90ba0cddcf63` | `6a4268a9354a545d41c3b62efebc478ed8c521f4` | 57013 | 90245391 | `4d86002fe32f66581faa24e4843360ecd148ca44d2adacd31ef08f74d7e8acd8` |
| WPT | `b60c4b349d9d167bf354a40bc0d4cbed15174606` | `a499343a14a03239fe23fdb3b183732ddaa6cf4b` | 164551 | 505155316 | `0be4a67e0e13f7fb1f9d82324a118dd3851acbcb50752ecb3615eb1391e395ab` |

`specs/snapshots/test262.json` and `specs/snapshots/wpt.json` hold the full records, including the license path, size, digest, and stated name.
`raw/corpus-fetch-test262.log` and `raw/corpus-fetch-wpt.log` record the `ls-remote` and fetch commands.
The snapshots live outside version control under `.tools/corpora`.

## Applicability

`specs/applicability/test262.json` counts 53616 discovered tests, with 0 selected, 0 excluded, and 53616 unclassified.
`raw/corpus-applicability-test262.log` records the generating command.

`specs/applicability/wpt.json` records a blocker and no counts.
The pinned WPT manifest tool imports `yaml`, and its requirements pin `pyyaml==6.0.1`.
The local Python 3.13.15 has no `yaml` module, as `raw/python-modules.log` shows.
`raw/wpt-manifest.log` records the failed manifest run with exit status 1.

## Verification

`raw/corpus-verify.log` records the integrator's `corpus-verify test262` and `corpus-verify wpt` runs.
Both passed against the local snapshots.
The worker's own runs are in `raw/corpus-verify-test262.log` and `raw/corpus-verify-wpt.log`.
`raw/corpus-verify-missing-snapshot.log` shows `corpus-verify` failing with status 1 when the snapshot is absent.

## Gates

Both receipts in `gates/` bind source digest `95d74b67ef7b7d1b234c1cdba198af30861d9fc66b76b5ab050afc23e5ba30cf` with 86 files.
Both bind policy digest `004e50361ed3cec0b9eaea1f411cf64ac7c2e49d684a494d6c6ebfea07537436` with 17 files.
`repo-check` and `controller-test` passed, and the controller test log reports 78 of 78 tests.
`raw/gate-evidence-check.log` shows both receipts passing `evidence-check`.

## Integration

The worker patch conflicted with `FP-0028` in `tools/selftest.mjs`.
The integrator kept both test groups, and the merged suite passes.

## Open items

- WPT applicability needs a pinned Python environment with the manifest tool's requirements.
- The `specs/corpora.json` pins wait for `fairpane-review` and `fairpane-spec` approval of `engineering/decisions/0003-corpus-snapshots.md`.
