# FP-0006 evidence

## Scope

Task `FP-0006` implements bounded host requests and the document lifecycle.
The frozen contract is `engineering/evidence/FP-0006/CONTRACT.md`, based on commit `9e073e2`.
Its revision 1 records the clarifications that the implementation adopted.
The isolated `fairpane-core` worker `FP0006Lifecycle` wrote `src/engine.zig`, the C exports in `src/c_api.zig`, the header, the API description, and the tests.
The root integrator reviewed the change, applied it, and ran the gates.

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 1: the new tests failed to compile against the unimplemented engine. |
| `raw/mutation-reentrancy.log` | Exit status 1: with responses applied immediately instead of queued, case 5 failed, along with nine other cases. |
| `raw/tests-after.log` | Exit status 0: 57 of 57 tests passed. |
| `raw/fmt.log` | Exit status 0. |
| `raw/build.log` | Exit status 0. |
| `raw/c-smoke.log` | Exit status 0 for the library build, the C compilation, and the smoke executable. |

## Integration records

The integrator ran these gates with source digest `e63b0f6da673743fd1a8920a94dd60b0c399381c94334ab15cb7d054ec5e9565` and policy digest `366776e09af8c5f000b5f2b8f85795ca4bb8f2098e9f7bc20e34ea97cb58c425`.

- `gates/2026-10-09T01-48-50-432Z-repo-check-4d1f747f.json`
- `gates/2026-10-09T01-48-50-651Z-controller-test-ea7d80ec.json`
- `gates/2026-10-09T01-49-07-617Z-zig-fmt-f6b4d51a.json`
- `gates/2026-10-09T01-49-10-262Z-zig-test-f3886188.json`
- `gates/2026-10-09T01-49-14-302Z-zig-build-fb5105e1.json`
- `gates/2026-10-09T01-49-16-070Z-c-abi-0afa16c5.json`

The protected `zig-test` gate prints no test count.
`raw/integration-tests.log` records an uncached `zig build test --summary all` run, which reports 57 of 57 tests passed.

## Limits

These records are local, unsigned integrity records on Windows x86-64.
No parser, network transport, timer, or script execution exists yet.
The C API uses the process allocator, and a host allocator interface remains outside this task.
