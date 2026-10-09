# FP-0047 evidence

## Scope

Task `FP-0047` closes the minor test gaps of the accepting `FP-0005` review.
The frozen contract is `engineering/evidence/FP-0047/CONTRACT.md`, based on commit `7bc9ace`.
The isolated `fairpane-core` worker `FP0047Decoder` added six tests to `src/web_string.zig` and changed no production code.

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 0 with 63 of 63 tests: no new case exposed a defect in the unchanged decoder. |
| `raw/mutation-f0-lower-boundary.log` | Exit status 1: without the F0 lower boundary, cases 1 and 2 failed. |
| `raw/mutation-four-byte-lead-range.log` | Exit status 1: with the lead range widened to F7, cases 4 and 5 failed. |
| `raw/mutation-offset-failure-unit.log` | Exit status 1: with a decoder failure counted as one unit, case 6 failed. |
| `raw/mutation-restore.log` | The source hashed to its saved copy after each revert. |
| `raw/tests-after.log` | Exit status 0 with 63 of 63 tests in an uncached run. |

Each mutation log has its exact source diff beside it.
The diffs compare a saved copy of the file with the mutated file, so their headers name both paths.

## Integration records

`raw/integration-binding.log` records `HEAD` at `0553728` and the staged file list before the gates ran.
The gates ran with source digest `9cb7896de3e485b008ad1db04c811e3dada027c335684623165bbee644c866d4`.

- `gates/2026-10-09T01-59-27-670Z-repo-check-a64a42db.json`
- `gates/2026-10-09T01-59-27-867Z-controller-test-60343cb7.json`
- `gates/2026-10-09T01-59-43-400Z-zig-fmt-9d52329a.json`
- `gates/2026-10-09T01-59-45-910Z-zig-test-16f6df5c.json`

`raw/integration-tests.log` records an uncached run with 63 of 63 tests passing.
