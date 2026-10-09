# FP-0028 evidence

## Scope

This record covers task `FP-0028`, "Harden controller command records".
`CONTRACT.md` freezes its behavior and ten test cases.
It qualifies controller behavior only.

## Changes

- `runProcess` adds `cwd` and `started_at` to every command record and `RESULT` line.
- `runProcess` returns a failed result instead of throwing when the log or the output capture fails.
  It keeps every error message and closes every descriptor.
- Each child writes its output to a file in a new private temporary directory.
  On POSIX that directory has mode `0700` and the file has mode `0600`.
  The controller copies the output into the log and removes the directory.
- `recordCommand` records `cwd` and `started_at` for an unresolvable executable and accepts a `pathEnv` option.
- `gateEnvironment` names the compiler cache override, and `runGate` uses it.
- `tools/README.md` documents the new record fields and capture behavior.

## Tests

`tools/selftest.mjs` adds the ten contract cases as tests 60 through 69.
`raw/controller-hosts.log` shows 70 of 70 tests passing under Node `v26.7.0` and under Bun `1.4.2`.
The Bun result is informational.

`controls/mutants.mjs` builds six mutants of `tools/lib.mjs`.
Each mutant reintroduces one defect that a review-2 finding or the contract names.
`raw/mutation-control.log` shows that the target test fails for each of the six mutants.

## Gates

Every receipt in `gates/` binds source digest `f48dd23ed10031195dcb9fe177cb9b046b16f31e2f6074d3db4f20c9ac53d02e` with 77 files.
Every receipt binds policy digest `0d9ebeb68c7cd21f2e2d7cec6ce68cefc1b4aec3d59be8a6a4668b69bda345e1` with 12 files.

| Gate | Result | Command exits |
| --- | --- | --- |
| `repo-check` | pass | 0 |
| `controller-test` | pass | 0 |
| `zig-test` | pass | 0 |
| `c-abi` | pass | 0, 0, 0 |

`raw/gate-evidence-check.log` shows each receipt passing `evidence-check` with `current_source: true`.
The `c-abi` log shows `cwd` and `started_at` in each `RESULT` line.

## Limits

- No permanent test reproduces the original MSYS2 append-handle failure.
- The POSIX permission modes are not exercised on this Windows host.
