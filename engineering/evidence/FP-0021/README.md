# FP-0021 evidence

## Scope

Task `FP-0021` establishes ABI schema generation and wrapper contracts.
The frozen contract is `engineering/evidence/FP-0021/CONTRACT.md`, based on commit `24c0c64`.
The isolated `fairpane-bindings` worker `FP0021Schema` wrote the schema, the generator, the failure scenarios, and their tests.
The root integrator applied the patch, resolved one import conflict in `tools/fairpane.mjs` by keeping both import lines, and committed it as `13372de`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Generate raw declarations from ownership-aware interface metadata. | `api/fairpane.schema.json` and `tools/abi.mjs` generate `include/fairpane.h` and `src/abi_generated.zig`; cases 1 and 3. |
| Detect stale generated files mechanically. | `abi-check`, case 2, and `raw/mutation-stale.log`, where a hand edit to `FP_STATUS_WRONG_THREAD` makes `abi-check` exit with status 1 and name line 46. |
| Qualify C and Zig lifecycle callers against the actual engine. | Cases 7 and 8: `tests/c/abi_smoke.c` through the `c-abi` gate and `src/abi_scenarios.zig` through the `zig-test` gate. |
| Define shared foreign-runtime failure scenarios before more wrappers. | `api/failure-scenarios.json` with 14 scenarios, and case 9. |
| Keep the metadata language-neutral. | Threads, lifetimes, ownership, nullability, and statuses are schema data; case 4 rejects a pointer without ownership or lifetime. |
| Give the schema distinct types for Unicode text, lossless web strings, ranged integers, opaque handles, absent versus null fields, and byte buffers. | Case 5 and the `text`, `web_string`, `integer` with `range`, `handle`, `identifier`, `optional`, and `bytes` kinds. |

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Every command exits with status 1: the controller cannot import `tools/abi.mjs`, Zig cannot find `abi_generated.zig`, and the C smoke test has 20 compile errors. |
| `raw/tests-after.log` | 127 of 127 controller tests on the worker's base. |
| `raw/zig-tests-after.log` | 77 of 77 Zig tests with a fresh cache on the worker's base. |
| `raw/c-smoke.log` | The strict C11 compile and the smoke executable exit with status 0. |
| `raw/abi-check.log` | `abi-check` reports `pass`. |
| `raw/layout-32bit.log` | The generated Zig compiles for x86-linux and arm-linux-musleabihf, and a wrong 32-bit structure size fails compilation. |

## Integration records

`raw/integration-binding.log` records `HEAD` `13372de`, a status whose only untracked file is that log, and an empty staged diff.

- `gates/2026-10-09T02-46-05-308Z-repo-check-1114babe.json`
- `gates/2026-10-09T02-46-05-488Z-controller-test-54b193bf.json`, with 138 of 138 controller tests.
- `gates/2026-10-09T02-46-26-215Z-zig-fmt-77677748.json`
- `gates/2026-10-09T02-46-26-362Z-zig-test-3f72cd3e.json`
- `gates/2026-10-09T02-46-29-740Z-c-abi-ce4fe73c.json`

| Log | Result |
| --- | --- |
| `raw/integration-zig-tests.log` | `zig build test --summary all` with the fresh cache `out/fp0021-integration-cache`: 89 of 89 tests, which include the 12 FP-0009 tests that landed after the worker's base. |
| `raw/integration-abi-check.log` | `abi-check` exits with status 0. |
| `raw/integration-tests-bun.log` | Bun runs 138 of 138 controller tests. |

## Open observations

The generated comments name functions and constants by their schema names, such as `document_get`, instead of their C names, such as `fp_document_get`.
The header therefore says less precisely what a C caller must pass than the hand-written header did.
The ABI revision stays zero, and every earlier name, value, and layout is unchanged.
