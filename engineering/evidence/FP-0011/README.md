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

## Revision 1

Review 1 rejected the first submission, and the contract's `## Revision 1` section, frozen on commit `f95fab6`, states the corrections.
The isolated `fairpane-js` worker `FP0011R1` implemented them on that base without committing.
The worker ran no measurement executable; sections 3 through 6 of ADR 0008 still cite the first submission's runs until the integrator reruns them.

### Changes

- `src/js/runtime.zig`: `Runtime(r)` is now a struct that owns its heap, with `init`, `deinit`, and `rootContext(rt: *Runtime(r))`, the only source of a root context.
  A context stores its heap as `*SealedHeap(effects)`, an opaque type per representation and effect set, and only the file-private `unseal` converts it back.
  `Scope` and `Local` moved here from `heap.zig` and hold a pointer to another opaque type, so an open scope no longer gives its holder a `*Heap`.
  `PropertyDescriptor`'s predicates are `pub` for the kernels file.
- `src/js/kernels.zig`: the 23 kernels, the engine-thrown messages, and `accessorCell`, moved without semantic change.
- `src/js/heap.zig`: `Heap.Scope` and `Heap.Local` became `ScopeFrame`, `pushScoped`, `closeScope`, `scopedValue`, and `setScopedValue`, which hold no heap pointer; the tests construct runtimes.
- `src/js/number.zig`: `stringToNumber` saturates the ExponentPart at the literal's length plus 400 and uses saturating scale and exponent arithmetic; the case 38 test; the 25-code-unit comment.
- `src/js/number_vectors.zig`: the case 38 vectors; `selfCheck` takes the runtime.
- `src/js/measure.zig`: each sample creates and destroys a runtime instead of a bare heap.
- `src/js/value.zig`: case 20 also scans `kernels.zig`.
- `tests/compile_fail/`: `leaf_reaches_heap.zig` (case 34), `leaf_widens_context.zig` (case 35), `binding_missing_kernel.zig`, and `binding_stray_kernel.zig` (case 36).
- `build.zig`: the entries of cases 34 through 36 and the second expected text of `leaf_calls_behavior.zig` (case 37).
- `engineering/decisions/0008-javascript-values-and-heap.md`: section 1 states the boundary and its limit, the `decl_names` probe, and the number fix.

### Logs

| Log | Result |
| --- | --- |
| `raw/probe-r1.log` | The `decl_names` probe exits with status 1 by design and prints `same file: public_function public_constant; other file: public_function public_constant`. Each new or changed fixture exits with status 1, and the log holds its full diagnostic. A probe of a kernel without `pub` reports `fairpane-js: operation Number::add has no kernel`. |
| `raw/tests-before-r1.log` | The revision base `f95fab6`, extracted with `git archive` and overlaid with the new tests only, as the recorded `diff -ruN` shows. `zig build test --summary all` exits with status 1: 40 of 44 steps and 177 of 178 tests. Cases 34 and 35 fail, and their fixtures compile with exit status 0 in the two records that follow. Case 38 fails on vectors 1, 2, 4, and 5; vector 3 already held. Case 36 and the case 37 fixture pass. |
| `raw/tests-after-r1.log` | `zig build test --summary all` with the fresh cache `out/fp0011-r1-cache-after` exits with status 0: 44 of 44 steps and 178 of 178 tests, 145 in the module test binary and 33 in the text test binary. A `sha256sum` record of `build.zig`, `src/root.zig`, every file under `src/js`, and every fixture follows. |
| `raw/fmt-r1.log` | `zig fmt --check src build.zig tests` exits with status 0. |
| `raw/mutation-left-root-r1.log` and `raw/mutation-left-root-r1.diff` | `git apply` and `git apply -R` of the diff, each with exit status 0, between `sha256sum` records of `src/js/kernels.zig`: `24160216…1082` before, `ca4c9f48…bc3d` mutated, and `24160216…1082` after. The test run exits with status 1: 177 of 178 tests, and case 11 fails with `scenario AD19 under reference: dead_resolutions 4`, while case 31 passes. |
| `raw/mutation-r1.log` with `raw/mutation-r1-kernel-direction.diff` and `raw/mutation-r1-entry-direction.diff` | Each diff is applied and reversed with exit status 0 between `sha256sum` records of `src/js/runtime.zig`, which return to `3fcecbbd…23ac`. Without the kernel-to-entry loop, `binding_stray_kernel.zig` fails because its standard error lacks `kernel stub_kernel belongs to no operation`. Without the entry-to-kernel check, `binding_missing_kernel.zig` fails because the compiler reports `struct 'binding_missing_kernel.Kernels' has no member named 'number_add'` instead. Each run exits with status 1, and all 178 unit tests pass in both. |

### Probe results

- `decl_names` of the locked compiler lists only `pub` declarations, in the same file and from another file.
- `bindKernels` reports a kernel without `pub` as missing, because `@hasDecl` does not see it from `runtime.zig`.
- The compiler prints an `Effects` value in a type name as `@fromBackingInt(N)`, so `{}` is `@fromBackingInt(0)` and every effect is `@fromBackingInt(15)`.
- Case 34: `no field or member function named 'allocateString' in 'js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'`.
- Case 35: `expected type '*js.runtime.Runtime(.reference)', found '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'` and `expected type '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(15))', found '*js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'`.
- Case 36: `fairpane-js: operation StubOperation has no kernel` and `fairpane-js: kernel stub_kernel belongs to no operation`.
- Case 37: `expected type '*js.runtime.Runtime(.reference).Context(@fromBackingInt(15))', found '*js.runtime.Runtime(.reference).Context(@fromBackingInt(0))'`.

### Resolved ambiguities

- "The runtime that owns the heap" had no value before, because `Runtime(r)` was a namespace. It is now an instantiable struct with a `heap` field, and a host that owns it keeps direct use of the heap's roots, pending exception, counters, and test-only verifier. The boundary covers every holder of a context.
- An open `Heap.Scope` and each `Heap.Local` held a `*Heap`, a second path to the heap that the review did not name. They now hold a sealed pointer of a type that initializes no context.
- A context's field is visible in Zig, so the sealed type differs per effect set. A `{}` context's field therefore cannot initialize `Context(.all)`, which case 35 shows.
- Case 35 tests both routes from what a context exposes: `rootContext(ctx.heap)` and the initialization `.{ .heap = ctx.heap }`.
- Case 36 names its stubs `StubOperation`, an entry whose id is `number_add` because ids form an enumeration, and `stub_kernel`.
- The case 38 test calls `stringToNumber` directly, so it compiles on the revision base, whose runtime API differs. The measurement self-check still covers cases 21 through 23 only, as the contract states.
- The new tests could not run on the base tree with the new runtime API, so `tests-before-r1.log` appends the case 38 vectors and test to the base's number files and copies `build.zig` and the four new fixtures. The appending script lives in the ignored `out/fp0011-r1-overlay/make-overlay.mjs`, and the log records its full text before running it.
- The ExponentPart bound is the literal's length plus 400: the scale's magnitude is at most the length, so a saturated exponent leaves a magnitude of at least 400 in the decimal exponent, which gives zero or infinity for any digits.
- The contract names `raw/mutation-r1.log` only. The two diffs that it applies are kept beside it so the recorded commands can be replayed.

### Integration

The integrator applied the patch without conflicts and committed it as `60c0c90`.
The integrator accepts the worker's resolved ambiguities.
A host that owns a `Runtime` keeps direct use of its heap, because revision 1 limits only what a context holder can reach.

One uninterrupted sequence ran on `60c0c90`, with no commit or source edit during it.
`raw/r1-integration-binding.log` records `HEAD` `60c0c90` and an empty status, including ignored files, for every source root at 10:08:09Z, and the empty status again at 10:09:43Z, after the last run.
It does not record `HEAD` again; `engineering/evidence/FP-0027/raw/r1-binding.log` records `HEAD` `60c0c90` in the same checkout at 10:10:32Z.

- `gates/2026-10-09T10-08-09-873Z-repo-check-0f1d1adf.json`
- `gates/2026-10-09T10-08-10-220Z-controller-test-2c171a81.json`, with 181 of 181 controller tests.
- `gates/2026-10-09T10-08-45-669Z-zig-fmt-3e7dd269.json`
- `gates/2026-10-09T10-08-45-923Z-zig-test-8f4b2ba1.json`

`raw/r1-integration-tests.log` runs `zig build test --summary all` with the fresh local cache `out/fp0011-r1-integration-cache` and the recorded override `ZIG_GLOBAL_CACHE_DIR`: 62 of 62 build steps and 178 of 178 tests.
`raw/r1-integration-bun.log` records Bun 1.4.2 with 181 of 181 controller tests.

Commit `6771856` later changed the test block of FP-0011 case 14 in `src/js/heap.zig`, which now runs `checkAllAllocationFailures` over a backing allocator that fails every remap.
No measurement executable compiles a test block.

### Measurements at the integration commit

Contract revision 1 requires the integrator to rerun `doctor`, `measure-build`, and the six measurement runs at the integration commit.
The integrator ran them in a detached worktree at `60c0c90`, and ADR 0008 sections 3 through 6 now cite only these runs.

| Log | RESULT |
| --- | --- |
| `raw/r1-measure-binding.log` | `git worktree add --detach out/fp0011-measure 60c0c90`; `HEAD` `60c0c90` and an empty status for every source root before and after the runs; the removal of the worktree. Each exits with status 0. |
| `raw/doctor-r1.log` | `doctor` with exit status 0, showing the locked compiler available. |
| `raw/environment-r1.log` | The active power scheme `Balanced`, and a process started through `record` that reports 32 logical processors and the affinity mask `4294967295`. |
| `raw/measure-build-r1.log` | `zig build measure -Doptimize=ReleaseFast --summary all` in the worktree, exit status 0, 8 of 8 steps. |
| `raw/measure-<representation>-r1-run<n>.log` | The six runs in the frozen order, each exit status 0, with every one of the 72 samples per workload carrying its table checksum. |
| `raw/measure-summary-r1.log` | The SHA-256 and output of `raw/measure-summary-r1.mjs`, which repeats the method of `raw/measure-summary.log`. |
| `raw/measure-shift-decisions-r1.log` | The SHA-256 and output of `raw/measure-shift-decisions-r1.mjs`, which finds which level shifts decide a separability outcome. |
| `raw/measure-shift-decisions-r1-attempt-1.log` and `-attempt-2.log` | Two runs of an earlier version, kept as `raw/measure-shift-decisions-r1-attempt-1.mjs`, that compared whole verdict text; the second is an accidental repeat. |

The rerun changes the representation decision.
`nan_box` is separably faster than `reference` on the same four workloads as before, but it is now separably slower on `mark-generated` in both runs, so it no longer qualifies.
`tagged_index` does not qualify either, so `reference` stays `FP-0012`'s default representation.
The generated tracer still becomes the default tracer under the pre-registered rule, and ADR 0008 section 5 states that a level shift in `nan_box` run 2 of `mark-manual` decides that outcome.
Review 1's minor finding about the mid-run regime shift is answered by that statement and by the per-series sample lists in the ADR.
The plan entry of `FP-0012` now requires interleaved comparisons that record the logical processor of each sample.

### Review 2 follow-up

Review 2 accepted revision 1 with three minor findings and five notes.

- `raw/node-vectors-r1.log` records Node v26.7.0 computing the five case 38 vectors after the review, with the bit patterns that the contract froze; the integrator's earlier check before the freeze was not recorded.
- `raw/measure-shift-decisions-r1-attempt-1.log` now ends with a SHA-256 of the kept copy `raw/measure-shift-decisions-r1-attempt-1.mjs`, `69ccad58…`, which equals the hash that the attempt recorded for the script before it changed.
- `raw/doctor-r1.log` ran in the main checkout, because the measurement worktree holds no `.tools` compiler; the main checkout's `HEAD` at that time was not recorded, and `doctor` reports only the environment.
- ADR 0008 section 3 now marks the statement about the open agent sessions as unrecorded and names the last recorded command of the FP-0014 worker, at 11:23:13Z in `engineering/evidence/FP-0014/raw/fmt.log`.
- The affinity of each measurement process was not recorded, and the ADR keeps that claim marked as inference; `FP-0012` must record it.
- `engineering/plan.json` is a source root, not a policy root: `engineering/policy.json` lists the policy roots, and the plan is not among them. The `FP-0012` criterion in `a1b2d1c` only adds requirements, and the `FP-0012` contract freeze confirms it.

### Continuous integration

`ci/README.md` records `Gates` run 37926644057 of `a1b2d1c`.
Its first attempt failed when the Linux job could not download the locked compiler, and its second attempt passed.
The integrator accepted the task before the second attempt, and `ci/README.md` records that order.
