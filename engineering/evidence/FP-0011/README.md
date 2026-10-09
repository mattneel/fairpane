# FP-0011 evidence

## Scope

Task `FP-0011` establishes the JavaScript semantic and heap catalogs.
The frozen contract is `engineering/evidence/FP-0011/CONTRACT.md`, drafted by worker `FP0011Contract` and frozen on commit `8af0f20`.
The isolated `fairpane-js` worker `FP0011Js` wrote `src/js/`, the compile-failure fixtures under `tests/compile_fail/`, the `measure` build step, and ADR 0008.
The root integrator applied the patch, merged its `build.zig` additions with the laboratory steps of `FP-0007`, and committed it as `84b7b14`.

## Acceptance criteria

| Criterion | Evidence |
| --- | --- |
| Define operation effects with callback, allocation, exception, and mutation boundaries. | Cases 1 through 6: the catalog table, its validation, kernel binding, the compile-failure fixtures, and the effect counters. |
| Define explicit heap-reference metadata and trace generation experiments. | Cases 7 through 16, including the generated and manual tracers over 64 seeded heaps and the stress and quarantine modes. |
| Compare compact-value candidates without exposing their layout through the C ABI. | Cases 17 through 20 and the measurement runs; the case 20 fixtures show that the C ABI rejects each representation. |
| Preserve numerical edge cases and arbitrary string code units in tests. | Cases 21 through 24 with the frozen vectors and all 65,536 code units. |
| Record measured design choices rather than claims of free speed. | `engineering/decisions/0008-javascript-values-and-heap.md`, which applies the pre-registered rules to the recorded samples and makes no speed claim beyond them. |

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Two runs, both with exit status 1: a syntax error in the new test code, then undeclared identifiers before the implementation. |
| `raw/tests-after.log` | Exit status 0 with a fresh cache: 120 of 120 tests on the worker's base. |
| `raw/fmt.log` | `zig fmt --check src build.zig` exits with status 0. |
| `raw/mutation-left-root.log` | Without the root of the left primitive in the `addition` kernel, 119 of 120 tests pass, and case 11 fails under the stress mode. The file hash before and after the control matches. |
| `raw/measure-*.log` and `raw/measure-summary.log` | Two interleaved runs per representation, 504 samples with the expected checksums, processor-load readings, and the separability summary. |

## Integration records

`raw/integration-binding.log` records `HEAD` `84b7b14` and an empty status, including ignored files, for every source root.
`raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0011-integration-cache`: 35 of 35 build steps and 132 of 132 tests, which include the laboratory and ABI tests that landed after the worker's base.

- `gates/2026-10-09T05-07-25-099Z-repo-check-407bab9b.json`
- `gates/2026-10-09T05-07-25-326Z-controller-test-a34cd7af.json`
- `gates/2026-10-09T05-07-49-589Z-zig-fmt-eb9c23ca.json`, which also checks `tests/compile_fail/`.
- `gates/2026-10-09T05-07-49-773Z-zig-test-6695a235.json`
- `gates/2026-10-09T05-08-01-799Z-zig-build-a3ac6c56.json`

## Interpretation notes

The locked compiler exposes `@typeInfo(...).decl_names`, which the contract's observed facts said was absent, so `bindKernels` lists kernels through it.
A module may import only files under its root's directory, so the `measure` step copies `src` beside a one-line generated root for each representation.
The compile-failure steps run the contract's exact `zig build-obj` command, so their compilers use the default cache.

## Limits

The measurements come from one machine and one target, with microbenchmarks and no integrated workload.
`FP-0012` repeats the comparisons on an integrated workload before any speed claim.
