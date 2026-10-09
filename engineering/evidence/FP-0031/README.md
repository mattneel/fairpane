# FP-0031 evidence

## Scope

This record covers task `FP-0031`, "Close the FP-0028 review findings".
`CONTRACT.md` freezes its behavior and eight test cases.
It qualifies controller behavior only.

## Changes

- `runProcess` and `recordCommand` accept a `fileSystem` option that replaces single `node:fs` operations.
  Without the option, both use `node:fs` directly.
- Every write to a command log goes through one call that treats a short count as an error.
  This covers the `COMMAND` line, the copied output, and the `RESULT` line.
  A short write becomes `Log write failed: Short write: N of M bytes.` or, during the output copy, `Output capture failed: Short write: …`.
- A failed removal of the private capture directory adds `Capture directory removal failed: …` to the command record.
  The command then fails, and a gate that ran it fails.
- `recordCommand` writes the record of an unresolvable executable through the same log path as `runProcess`.
- `runGate` validates the log path and the receipt path before it creates any file.
  It validates the receipt path again when it writes the receipt.
- `controls/harness.mjs` in `FP-0028` held the mutation-control logic; task `FP-0053` moved it to `tools/mutation-harness.mjs`.
  `controls/mutants.mjs` copies every tracked or unignored file into a template with its own one-commit Git repository.
  It runs the unmutated suite there first and stops if any test fails.
  For each killed mutant, it logs the failing test line and its message.

The watchdog block in `runProcess` is unchanged.

## Tests

`tools/selftest.mjs` adds the eight contract cases as tests 86 through 93 on the worker's 110-test base.
In the integrated 126-test suite, they run as tests 97 through 104.

| Log | Command | Result |
| --- | --- | --- |
| `raw/tests-before.log` | `node tools/selftest.mjs` against the base `tools/lib.mjs`, without `controls/harness.mjs` | 104 of 110 pass, exit 1 |
| `raw/tests-after.log` | `node tools/fairpane.mjs test` | 110 of 110 pass, exit 0 |
| `raw/tests-bun.log` | `bun tools/selftest.mjs` | 110 of 110 pass, exit 0 |
| `raw/mutation-control.log` | `node engineering/evidence/FP-0028/controls/mutants.mjs` | baseline 110 of 110, 13 of 13 mutants killed, exit 0 |

In `raw/tests-before.log`, cases 1, 2, 3, 5, 6, and 8 fail.
Cases 4 and 7 pass before the change, because the base code already validates the log path first and writes ISO 8601 UTC times.
The mutation control shows that both cases now catch those regressions.

The mutation control keeps the six FP-0028 mutants and adds seven.
Each new mutant reintroduces a regression that the FP-0028 review named: capture-start failure without a `RESULT` line, an unguarded `RESULT` write, a dropped capture error, a `runGate` log written before validation, an ignored short write, a silent removal failure, and a local-time `started_at`.

## Gates

The worker's logs come from its isolated base, where the suite had 110 tests.
The integrator applied the patch on commit `cd4f25c`, where the suite has 126 tests, and recorded `HEAD`, the staged diff, and the status in `raw/integration-binding.log`.

- `gates/2026-10-09T02-16-23-086Z-repo-check-572d0468.json`
- `gates/2026-10-09T02-16-23-259Z-controller-test-1a6c56ee.json`, with 126 of 126 tests passing.

| Log | Result |
| --- | --- |
| `raw/integration-tests-bun.log` | Bun 1.4.2, then 126 of 126 tests passing, exit 0. |
| `raw/integration-mutation-control.log` | Baseline 126 of 126, then 13 of 13 mutants killed, exit 0. |

## Limits

- On the child-exit path, a throwing `RESULT` write would surface as an uncaught exception, not as a test failure.
  Case 2 therefore checks the unresolved-name and capture-start paths first, where such a throw rejects the awaited call.
- The POSIX permission modes are not exercised on this Windows host.
