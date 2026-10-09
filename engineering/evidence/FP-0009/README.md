# FP-0009 evidence

## Scope

Task `FP-0009` implements DOM identity and mutation foundations.
The frozen contract is `engineering/evidence/FP-0009/CONTRACT.md`, based on commit `93dcaf0`.
The isolated `fairpane-core` worker `FP0009Dom` wrote `src/dom.zig` and its twelve contract cases.
The root integrator applied the patch and committed it as `8f5c2bc`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Preserve parent, child, sibling, and document ownership invariants. | `expectInvariants` checks every link, node document, and tree constraint after each mutation in cases 1 through 12. |
| Reject invalid hierarchy mutations with correct observable outcomes. | Cases 2, 3, and 4 cover every validity condition with one fixture each and check that a failure changes nothing. |
| Define trace roots for later VM integration. | `forEachRoot`, `retain`, `release`, and `sweep`, with case 8. |
| Test mutation during iteration and owner teardown. | Cases 9 and 10. |

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 1: the tests compile against no implementation, with 35 errors. |
| `raw/tests-after.log` | Exit status 0: `zig build test --summary all` with a fresh cache, 75 of 75 tests. |
| `raw/fmt.log` | Exit status 0: `zig fmt --check src build.zig`. |
| `raw/mutation-ancestor.log` | Without the inclusive-ancestor check in "ensure pre-insert validity", 2 of 75 tests fail, cases 2 and 3. The file hash before and after the control matches. `raw/mutation-ancestor.diff` holds the exact change. |

## Integration records

`raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0009-integration-cache` on the integrated tree: 75 of 75 tests pass.
`raw/integration-binding.log` records `HEAD` `8f5c2bc` and a status whose only untracked files are review records and the binding log itself, outside every source root.

- `gates/2026-10-09T02-30-45-110Z-repo-check-0b640f79.json`
- `gates/2026-10-09T02-30-45-291Z-controller-test-c60e59b0.json`
- `gates/2026-10-09T02-31-06-136Z-zig-fmt-2bd95ed7.json`
- `gates/2026-10-09T02-31-06-271Z-zig-test-1d6856f2.json`

## Interpretation notes

The worker followed the DOM Standard of 5 October 2026, where "replace" calls "ensure pre-insert validity" with « child » as the children to exclude.
Adopting a document returns `error.NotSupported`, from `adoptNode()` step 1, and a target that is not a document returns `error.NotADocument`.
A `release` without a matching `retain` returns `error.NotRetained`.
The child iterator ends when its recorded next sibling is freed or leaves the parent.

## Limits

The store is not yet connected to `Engine` or to the C ABI, as the contract's non-goals state.
