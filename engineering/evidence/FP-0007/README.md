# FP-0007 evidence

## Scope

Task `FP-0007` builds the inspectable headless laboratory.
The frozen contract is `engineering/evidence/FP-0007/CONTRACT.md`, based on commit `c9c243f`.
The isolated `fairpane-core` worker `FP0007Lab` wrote `src/lab.zig`, `src/lab_main.zig`, the `lab` build step, the fixtures under `tests/lab/`, and the fourteen contract cases.
The root integrator applied the patch without conflicts and committed it as `39ef90a`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Accept explicit document bytes and environmental inputs without direct network access. | Cases 1, 5, and 6: strict case parsing, answers taken only from the case, and a loopback listener that accepts no connection while the case bytes load. |
| Emit structured pipeline state with source and corpus identifiers. | Cases 2, 7, and 9: the result records input digests, the corpus identifier, every stage's status, normalized events, and byte-identical output across runs. |
| Distinguish unsupported behavior from failures and harness errors. | Cases 2, 3, 4, 8, and 13: `pass`, `fail`, `unsupported`, `harness-error`, and `timeout`, with exit statuses 0 to 4 and 64 for a usage error. |
| Add replay and fixture-minimization entry points without success stubs. | Cases 10, 11, and 14: transcript replay with a detected divergence, `ddmin` with a 1-minimal result, and `minimize` on a 4096-byte failing case. |

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 1: `lab_main.zig` does not exist, and the tests name undeclared laboratory declarations. |
| `raw/tests-after.log` | Exit status 0 with a fresh cache: 17 of 17 build steps and 87 of 87 tests on the worker's base. |
| `raw/fmt.log` | `zig fmt --check src build.zig` exits with status 0. |
| `raw/mutation-stages.log` | With every stage reported as `completed`, 4 of 87 tests fail, cases 1, 2, 4, and 8, and the restored file's hash matches. `raw/mutation-stages.diff` holds the change. |

## Integration records

`raw/integration-binding.log` records `HEAD` `39ef90a` and an empty status, including ignored files, for `src`, `tools`, `tests`, `build.zig`, `include`, and `api`.
`raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0007-integration-cache`: 17 of 17 build steps and 101 of 101 tests, which include the FP-0021 tests that landed after the worker's base.

- `gates/2026-10-09T04-23-07-089Z-repo-check-67b1df59.json`
- `gates/2026-10-09T04-23-07-290Z-controller-test-769908e2.json`
- `gates/2026-10-09T04-23-30-734Z-zig-fmt-d5363388.json`
- `gates/2026-10-09T04-23-33-336Z-zig-test-05176252.json`
- `gates/2026-10-09T04-23-41-439Z-zig-build-9b49add1.json`

## Limits

Only the `fetch` stage exists, so every other stage reports `unsupported`.
Process-level crash and wall-clock timeout classification remains with the runner that executes the laboratory, as the contract's non-goals state.
`zig build test` installs `fairpane-lab` before cases 13 and 14 run it.
