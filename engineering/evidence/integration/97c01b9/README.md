# Integration head 97c01b9

## Scope

This record checks `master` at commit `97c01b9` after `FP-0001` and the owner-directed documentation commits.
`docs/AGENT_OPERATIONS.md` requires the affected gates to run again on the integration head.
The `FP-0001` acceptance remains bound to commit `05d2d42` and its own receipts.

## Results

`raw/integration-checks.log` records the commit and tree IDs.
The same log shows an empty protected-path diff from `05d2d42` to this head and lists every changed path.
It also shows that evidence commit `4ca37a2` changed only `engineering/evidence` files and `engineering/state.json`.

Every receipt in `gates/` binds source digest `b1dff907acc7392d1163c0a3f64556e5afd343261672e8e58db6fb40b13553ed` with 77 files.
Every receipt binds policy digest `ec1505889dbe8cc3aef2fa1e6a9d9da2afd5a7f847fcbe23e1559761d35f3e91` with 12 files.
All nine gates passed, and `raw/integration-checks.log` shows each receipt passing `evidence-check`.

`src`, `build.zig`, and `include` did not change after `05d2d42`.
The Zig build system therefore reused cached results for the unchanged test and library steps.
The fresh Zig test run with 7 of 7 tests passing is in `engineering/evidence/FP-0001/raw/zig-test-summary.log`.
