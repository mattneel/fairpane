# FP-0005 evidence

## Scope

Task `FP-0005` implements lossless owned web strings in `src/web_string.zig`.
The frozen contract is `engineering/evidence/FP-0005/CONTRACT.md`, based on commit `475cb0e`.
The isolated `fairpane-core` worker `FP0005Strings` wrote the implementation and the sixteen contract tests.
The root integrator reviewed the change, applied it, and ran the gates.

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 1: the contract tests failed to compile against the unimplemented module. |
| `raw/mutation-restore.log` | Exit status 1: with the offending byte consumed instead of restored, cases 6, 7, and 16 failed, and 35 of 38 tests passed. |
| `raw/tests-after.log` | Exit status 0: 38 of 38 tests passed. |
| `raw/fmt.log` | Exit status 0. |
| `raw/build.log` | Exit status 0. |
| `raw/controller-test.log` | Exit status 0. |

## Integration records

The integrator ran these gates with source digest `236167df5e6347b70e81ba835fffbfcf42e40382479df49c69a6d02d4db89af4` and policy digest `a62931e5769ceee40c268530445a7e0ac967bcd254d638b3b44b665bce355a8f`.

- `gates/2026-10-09T01-26-51-066Z-repo-check-10800b2b.json`
- `gates/2026-10-09T01-26-51-284Z-controller-test-fef6b2c1.json`
- `gates/2026-10-09T01-26-55-678Z-zig-fmt-05f62a54.json`
- `gates/2026-10-09T01-26-55-837Z-zig-test-89870b9c.json`
- `gates/2026-10-09T01-26-58-376Z-zig-build-16e8778d.json`

The protected `zig-test` gate prints no test count.
`raw/integration-tests.log` therefore records an uncached `zig build test --summary all` run, which reports 38 of 38 tests passed.

## Limits

These records are local, unsigned integrity records.
They establish the contract cases on Windows x86-64 only.
A one-byte string representation remains an unmeasured hypothesis outside this task.
