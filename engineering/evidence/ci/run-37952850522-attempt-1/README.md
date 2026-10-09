# Run 37952850522, attempt 1

These are the Windows gate receipts of attempt 1 of `Gates` run 37952850522, for head `a2dd9ed40124bfd8997880c3631867f506dc8bfc`.
The integrator downloaded the artifact `windows-gate-receipts-unsigned-local-integrity-records-not-attestations` with `gh run download` into `out/ci-37952850522` before it requested the rerun.
That download was not recorded with `node tools/fairpane.mjs record`.
The rerun replaced the artifact, so `../run-37952850522/` holds attempt 2's receipts, which the recorded download in `../run-37952850522.log` fetched.

| File | SHA-256 |
| --- | --- |
| `2026-10-09T15-38-50-281Z-repo-check-dc0cd4f1.json` | `4829c08916b2e7d8…` |
| `2026-10-09T15-38-50-281Z-repo-check-dc0cd4f1.log` | `1418c708c6a082d2…` |
| `2026-10-09T15-38-51-214Z-controller-test-a8dcfbd8.json` | `266fff5c66ee9e7b…` |
| `2026-10-09T15-38-51-214Z-controller-test-a8dcfbd8.log` | `c37ef4f03e1a3196…` |

The controller-test receipt has `status` `fail`, and its command has `timed_out` true and `duration_ms` 120572.
Its log ends while the suite runs test 223, after `ok 222`, and its timeout section lists the live process tree before the gate stops it.
