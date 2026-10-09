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
| `raw/tests-before.log` | Every command exits with status 1: the controller cannot import `tools/abi.mjs`, Zig cannot find `abi_generated.zig`, and the C smoke test has at least 20 errors before clang stops at its error limit. |
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

## Open observations of the first submission

The first submission's generated comments named functions and constants by their schema names, such as `document_get`, instead of their C names, such as `fp_document_get`.
Revision 1 resolves that observation.
The ABI revision stays zero, and every earlier name, value, and layout is unchanged.

## Revision 1

Revision 1 answers `reviews/review-1-reject.json` under the "Revisions" section of `CONTRACT.md`.
The isolated `fairpane-bindings` worker `FP0021Revision` wrote it.

| Change | Evidence |
| --- | --- |
| `consumed_on_success` ownership, accepted only for an input handle parameter, on `fp_engine_destroy`'s `engine`. | Case 10. |
| Each identifier family names its lifetime. Documents use the new `document_destroy` lifetime, and requests use `request_end`. | Case 10. |
| Description references render as C names in the header and as Zig names in the Zig file. | Case 11. |
| Generated C `_Static_assert` layout checks in `tests/c/abi_layout.h`, which the C smoke test includes. | Case 12, `raw/revision-1-c-smoke.log`, and `raw/revision-1-layout-32bit.log`. |
| Generated status sets in `abi_generated.zig`, and the compile-time check in `src/c_api.zig`. | The status-set controller case and `raw/revision-1-check-controls.log`. |
| `abi-exports` fails when the library exports an undeclared `fp_` symbol, and the `c-abi` gate runs it. | The export-check controller case, `raw/revision-1-c-smoke.log`, and `raw/revision-1-check-controls.log`. |
| Foreign-thread calls with an invalid argument in C and Zig. | Case 13 and `raw/revision-1-mutation-thread.log`. |
| The unwinding limitation in `api/README.md`. | The "Failure scenarios" section of `api/README.md`. |

| Log | Result |
| --- | --- |
| `raw/revision-1-tests-before.log` | The controller run exits with status 1. Cases 1 through 9 pass, and cases 10 through 13 and the status-set and export-check cases fail: 143 of 149 pass. The uncached Zig run passes 89 of 89, because the new foreign-thread calls test behavior that already existed. The C smoke compile exits with status 1, because the generated `abi_layout.h` does not exist yet. |
| `raw/revision-1-tests-after.log` | 149 of 149 controller tests pass, including cases 10 through 13. |
| `raw/revision-1-zig-tests.log` | `zig build test --summary all` with the fresh cache `out/zig-cache-fp0021-r1-after`: 89 of 89 tests pass. |
| `raw/revision-1-c-smoke.log` | The library builds, `abi-exports` reports `pass` with 13 exports, and the strict C11 compile and the smoke executable exit with status 0. |
| `raw/revision-1-abi-check.log` | `abi-check` reports `pass` for all three generated files. |
| `raw/revision-1-layout-32bit.log` | The C smoke test, with its generated static assertions, compiles for `x86-linux-musl`, `x86-windows-gnu`, and `x86_64-linux-musl`. A copy of `abi_layout.h` with a wrong 32-bit `fp_document_info` size fails for `x86-linux-musl` and compiles for `x86_64-linux-musl`. |
| `raw/revision-1-mutation-thread.log` and `raw/revision-1-mutation-thread.diff` | Case 14. Removing the thread check from `enter` in `src/c_api.zig` fails the Zig wrong-thread scenario (88 of 89 pass, `expected 7, found 1`). The C smoke test stops at its invalid-argument assertion with exit status 3221226505, which is `0xC0000409`, the Windows fast-fail status that `abort` raises. Both `git diff --no-index` commands exit with status 1 because the files differ. The restored file has the same SHA-256 as before the mutation. |
| `raw/revision-1-check-controls.log` | Removing `out_of_memory` from the generated `fp_document_create` status set fails compilation of `src/c_api.zig`. An added `fp_unexpected` export makes `abi-exports` exit with status 1 and name it. Both files are restored with matching SHA-256 hashes. |

The C and Zig foreign-unwind scenarios only establish that the boundary has no unwinding channel.
They do not qualify unwinding safety, and each later wrapper must inject a real panic or exception.

The integrator runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `zig-build`, and `c-abi` on the revision commit.
`docs/ABI_AND_WRAPPERS.md` is outside this task's paths, so the integrator corrects its stale reference separately.
