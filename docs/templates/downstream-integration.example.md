# Downstream integration report: the C smoke test

## About this example

This report fills `docs/templates/downstream-integration.md` for the C smoke test in `tests/c/abi_smoke.c`.
Every value comes from the recorded FP-0021 evidence under `engineering/evidence/FP-0021/` and the commit that it names.
The smoke test is a first-party test, not an independent downstream application, so it demonstrates the report format rather than adoption.

## Integration

| Field | Value | Evidence |
| --- | --- | --- |
| Integration | C smoke test, `tests/c/abi_smoke.c` | `gates/2026-10-09T04-44-39-526Z-c-abi-e553f902.json` |
| Integration version | The file at the Fairpane commit below; it has no separate version. | `raw/revision-1-binding.log` |
| Fairpane commit | `574c2242d10821b45e2dd412f2b39e0187b371f5` | `raw/revision-1-binding.log` records this `HEAD` and an empty status for every source root. |
| ABI revision | `0`. The test asserts `fp_abi_revision() == 0` and `FP_ABI_REVISION` from the generated header, and the smoke executable exits with status 0. | `gates/2026-10-09T04-44-39-526Z-c-abi-e553f902.log` |
| Wrapper | `none`. The test calls the C ABI directly through `include/fairpane.h`. | `gates/2026-10-09T04-44-39-526Z-c-abi-e553f902.log` |
| Wrapper version | `none` | Not applicable. |

## Workflow

The `check_capabilities` and `check_document_lifecycle` functions of `tests/c/abi_smoke.c` exercise this workflow.

1. `fp_abi_revision` returns 0, and `fp_query_capabilities` fills `fp_capabilities` with revision 0 and no feature bits.
2. `fp_engine_create` creates an engine from `fp_engine_options`.
3. `fp_document_create` returns a nonzero document identifier, and `fp_document_get` reports the `FP_DOCUMENT_EMPTY` state.
4. `fp_document_load` returns a request identifier, and `fp_engine_next_event` reports `FP_EVENT_REQUEST_ISSUED` with the URL and then `FP_EVENT_DOCUMENT_STATE_CHANGED` to `FP_DOCUMENT_LOADING`.
5. `fp_request_respond` refuses an unsupported response version and then queues the answer.
6. `fp_engine_step` applies the answer, and `fp_document_get` reports `FP_DOCUMENT_LOADED` with the response body.
7. `fp_engine_next_event` reports the loaded state and then `FP_EVENT_NONE`.
8. `fp_document_destroy` and `fp_engine_destroy` release the document and the engine, and a later `fp_document_get` returns `FP_STATUS_UNKNOWN_ID`.

Each step also checks the invalid-argument results of its call with null pointers and short structures.

## Failure scenarios

The `c-abi` receipt shows the smoke executable exiting with status 0, so every assertion in each scenario function held.
`raw/revision-1-mutation-thread.log` shows that an assertion failure in this build stops the executable with a nonzero status, so the assertions are active.

| Scenario | Result | Evidence or reason |
| --- | --- | --- |
| `unknown-identifier` | `pass` | `scenario_unknown_identifier`; c-abi receipt. |
| `foreign-identifier` | `pass` | `scenario_foreign_identifier`; c-abi receipt. |
| `retired-identifier` | `pass` | `scenario_retired_identifier`; c-abi receipt. |
| `wrong-thread` | `pass` | `scenario_wrong_thread`; c-abi receipt and `raw/revision-1-mutation-thread.log`. |
| `cancel-before-answer-queued` | `pass` | `scenario_cancel_before_answer_queued`; c-abi receipt. |
| `cancel-after-answer-queued` | `pass` | `scenario_cancel_after_answer_queued`; c-abi receipt. |
| `document-teardown-outstanding` | `pass` | `scenario_document_teardown_outstanding`; c-abi receipt. |
| `engine-teardown-outstanding` | `pass` | `scenario_engine_teardown_outstanding`; c-abi receipt. |
| `allocation-failure` | `not run` | `api/failure-scenarios.json` marks it as not expressible in C; the Zig scenarios in `src/abi_scenarios.zig` cover it through the `zig-test` gate. |
| `null-required-pointer` | `pass` | `scenario_null_required_pointer`; c-abi receipt. |
| `short-structure` | `pass` | `scenario_short_structure`; c-abi receipt. |
| `response-body-bound` | `pass` | `scenario_response_body_bound`; c-abi receipt. |
| `load-bound` | `pass` | `scenario_load_bound`; c-abi receipt. |
| `foreign-unwind` | `not run` | `api/failure-scenarios.json` marks it as not expressible in C; the Zig test in `src/abi_scenarios.zig` runs through the `zig-test` gate. |

## Evidence records

All paths are relative to `engineering/evidence/FP-0021/`.

| Record | What it shows |
| --- | --- |
| `gates/2026-10-09T04-44-39-526Z-c-abi-e553f902.json` and its `.log` | The `c-abi` gate at commit `574c224` on a Windows x64 host with Zig `0.18.0-dev.120+9fe22a29b`: `zig build`, `abi-exports` with 13 exports, the strict C11 compile with `-Wall -Wextra -Werror`, and the smoke executable, each with exit status 0. |
| `raw/revision-1-binding.log` | `HEAD` `574c2242d10821b45e2dd412f2b39e0187b371f5` and an empty status, including ignored files, for every source root. |
| `raw/revision-1-c-smoke.log` | The worker's run of the same four commands, each with exit status 0. |
| `raw/revision-1-layout-32bit.log` | The smoke test with its generated layout assertions compiles for `x86-linux-musl`, `x86-windows-gnu`, and `x86_64-linux-musl`, and a copy of `abi_layout.h` with a wrong 32-bit `fp_document_info` size fails for `x86-linux-musl`. |
| `raw/revision-1-mutation-thread.log` | Removing the thread check makes the smoke executable stop at its assertion with exit status 3221226505. |

## Open limits

- The receipt is an unsigned local integrity record, not an attestation.
- The smoke executable ran only on a Windows x64 host; the 32-bit and Linux targets were compiled, not executed.
- `allocation-failure` and `foreign-unwind` did not run in C.
- The foreign-unwind scenario establishes only that the boundary has no unwinding channel, not unwinding safety.
- The smoke test is a first-party test, so it does not demonstrate adoption by an independent downstream application.
- No wrapper took part, so the report says nothing about wrapper ownership or threading behavior.
