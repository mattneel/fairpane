# ADR 0008: JavaScript values, operations, and heap catalogs

Status: proposed by task FP-0011, experimental.
Date: 2026-10-09.
Related tasks: `FP-0011`, `FP-0012`.
Contract: `engineering/evidence/FP-0011/CONTRACT.md`.

## 1. Operation catalog, effect algebra, and rooting protocol

The operation catalog is a Zig declaration in `src/js/operations.zig`.
Each of its 23 entries names an ECMA-262 operation, its fragment identifier, its operand and result types, and an upper bound of its effects.
A Zig declaration is the format because the comptime binding check needs each kernel's function type in the same compilation.
A JSON or ZON file cannot name a Zig function, so it would need a second table that binds kernels, which would be a second convention.
The catalog is small, so no offline generator exists.

The effect set has four flags: `callback`, `allocation`, `exception`, and `heap_mutation`.
User code can do anything, so `callback` requires the other three flags.
An engine-thrown error object is a new cell, so `exception` requires `allocation`.
`validate` rejects an entry that breaks either rule, and it rejects a duplicate id or name.
`permits(context, operation)` holds exactly when the operation's flags are a subset of the context's flags.

`Runtime(r)` owns one heap, and `Runtime(r).Context(effects)` is the only way for code that does not own the runtime to reach it.
Revision 1 of the contract makes that boundary hold in the type system.

- A context stores its heap as a pointer to an opaque type, `SealedHeap(effects)`, with one type per representation and effect set.
  Only `src/js/runtime.zig` converts that pointer back to a heap pointer, and the conversion is not `pub`.
- The kernels live in `src/js/kernels.zig`, which cannot reach the conversion.
- Allocation, property mutation, throwing, collection, and calls reach the heap only through context methods, each of which requires an effect set at compile time.
- A scope or a local stores its heap as a pointer to another opaque type, which initializes no context.
- `rootContext` takes the runtime, `*Runtime(r)`, and is the only source of a root context.
  Neither a heap pointer nor a context's field can stand in for it, and the field of one context cannot initialize a context with other effects.

No context method returns a heap pointer, a runtime pointer, or a wider context.
The owner of the runtime, such as a test harness or the measurement harness, holds the heap itself and uses its roots, its pending exception, its counters, and the test-only verifier.
Data that such an owner stores in a built-in function's host context is the owner's choice.

This boundary stops accidental reach.
It does not stop code that deliberately converts integers or pointers with `@ptrFromInt` or `@ptrCast`, because Zig has no private fields.

Case 34 shows that a `{}` context cannot allocate through its stored heap: the locked compiler reports `no field or member function named 'allocateString' in 'js.runtime.Runtime(.reference).SealedHeap(@fromBackingInt(0))'`.
Case 35 shows that a `{}` context cannot obtain a root context from its stored heap, either through `rootContext` or by initializing a `Context(.all)`.
The compiler names `@fromBackingInt(0)` and `@fromBackingInt(15)` for the effect sets `{}` and every effect, because `Effects` is a packed struct.
`raw/probe-r1.log` records each diagnostic before `build.zig` froze it, and `raw/tests-before-r1.log` shows both fixtures compiling with exit status 0 on the revision base.

Each kernel's first parameter is a context with exactly its entry's effects, and `bindKernels` checks every kernel's parameters and return type at compile time.
`invoke` narrows a context to the operation's effects, so a context can invoke only operations whose effects it holds.
Each heap primitive requires an effect set, and a built-in behavior's first parameter is a context with every effect.
The compile-failure fixtures of cases 4, 5, 8, and 34 through 37 show each rejected form with its diagnostic.

`bindKernels` checks both directions between the catalog and the kernels.
The original contract stated that `@typeInfo` gives no way to enumerate declarations, which is wrong for the locked compiler: `std.builtin.Type.Struct` has `decl_names`.
The probe in `raw/probe-r1.log` shows that `decl_names` lists only `pub` declarations, both for a struct in the same file and for one in another file.
A second probe shows that `bindKernels` reports a kernel without `pub` as `operation Number::add has no kernel`, because `@hasDecl` does not see it from `runtime.zig`.
A declaration without `pub` is therefore never bound, and `invoke` dispatches by catalog id, so no unlisted declaration runs.
The fixtures of case 36 show both messages, and `raw/mutation-r1.log` shows each fixture failing when the binding check skips its direction.
The binding check proves kernel signatures, not kernel bodies; the sealed heap is what keeps a kernel body inside its context's effects.

The rooting protocol has three rules.
A caller keeps every `Value` and `CellRef` argument rooted for the duration of the call.
A kernel returns its result unrooted.
A kernel roots each intermediate that it holds across an invocation with the `allocation` effect.
Case 11 enforces the protocol at run time with a collection before every allocation and a quarantine of freed cells.
The mutation control `raw/mutation-left-root-r1.diff` removes the root of the left primitive in `addition` in `src/js/kernels.zig`.
`raw/mutation-left-root-r1.log` records the commands that apply and reverse it and the file hash before and after, and it shows case 11 failing on scenario AD19 under `reference` with `dead_resolutions 4` while every other test, including case 31, passes.
The control `raw/mutation-left-root.diff` of the first submission showed the same result on the kernels before they moved.

`StringToNumber` returns RoundMVResult of the exact value of every StrDecimalLiteral.
The first submission saturated the ExponentPart at 1,000,000, while the scale from leading fractional zeros or integer digits had no bound, so a literal such as `"0."`, 1,000,001 zeros, and `"1e1000005"` gave 0.01 instead of 1000.
The literal's value is 0.D × 10^(scale + exponent) with 0.1 ≤ 0.D < 1, and the magnitude of the scale is at most the literal's length.
The ExponentPart therefore saturates at the literal's length plus 400, where the result is zero or infinity whatever the digits, and the scale and exponent arithmetic saturates.
Case 38 checks five such literals against values that the integrator took from Node v26.7.0, and `raw/tests-before-r1.log` shows four of them failing on the revision base; the third already held.
The comment on the longest `Number::toString` result now names 25 code units, as in `-0.0000012345678901234567`.

## 2. Heap catalog, collector baseline, and DOM bridge

`src/js/heap_catalog.zig` declares eight cell kinds with their object, callable, and internal-method metadata.
Each payload field has exactly one reference descriptor: `plain`, `value`, `cell`, `optional_cell`, `dom_node`, `owned_units`, `owned_limbs`, `owned_list(L)`, `inline(L)`, or `tagged_union(L...)`.
`checkLayout` rejects an undescribed field, a described field that does not exist, and a heap reference declared `plain`.
The generated tracer and the generated finalizer derive every action from the layouts at compile time.
A hand-written tracer in `src/js/heap.zig` is the reference of the trace generation experiment, and case 9 shows that both tracers visit and free the same cells for 64 random heaps under each representation.

The collector baseline is precise, non-moving mark and sweep.
Allocation reserves the worklist and the free list for the whole cell table, so a collection never allocates.
Roots are the scope stack, the persistent roots, the pending exception, and the intrinsic record.
A collection runs before an allocation only in stress mode or at `Options.max_cells`; no other trigger exists yet.

A platform object retains its DOM node in the FP-0009 store before the cell exists, and its finalizer releases that retain.
The FP-0009 root rules therefore keep the node's whole tree alive while the platform object lives, and a direct `store.sweep()` stays safe at any time.
No DOM node references a JavaScript cell yet, so no cross-heap cycle can form.
When a DOM node gains a reference to a JavaScript cell, this bridge leaks every cycle through the two heaps, and a unified marking pass becomes necessary.

## 3. Environment

The worker's measurement runs ran in an uncommitted worktree and record no source digest, as review 1 found.
Contract revision 1 therefore requires the runs at the integration commit, on an otherwise idle machine, with no worker building.
The root integrator ran them at `60c0c90` on 2026-10-09, and they replace the worker's runs as the basis of this record.
The worker's logs stay in `raw/` as superseded records.

`raw/r1-measure-binding.log` records `git worktree add --detach out/fp0011-measure 60c0c90`, `HEAD` `60c0c90` and an empty status, including ignored files, for every source root before and after the runs, and the removal of the worktree.

`raw/doctor-r1.log` holds this output of `node tools/fairpane.mjs doctor`, run in the main checkout at 11:24:33Z.

```json
{
  "platform": "win32",
  "architecture": "x64",
  "os_release": "10.0.26200",
  "os_version": "Windows 11 Pro",
  "runtime": "v26.7.0",
  "controller_bun": null,
  "bun": {
    "available": true,
    "version": "1.4.2"
  },
  "git": {
    "available": true,
    "version": "git version 2.54.0.windows.1"
  },
  "omp": {
    "available": true,
    "version": "omp/18.8.6"
  },
  "compiler": {
    "available": true,
    "path": "C:\\src\\fairpane\\.tools\\zig\\0.18.0-dev.120+9fe22a29b\\x86_64-windows\\zig.exe",
    "version": "0.18.0-dev.120+9fe22a29b"
  },
  "path_zig": {
    "available": true,
    "version": "0.17.0-dev.2453+zigpp.35608841b",
    "note": "Gates never use a compiler from PATH."
  },
  "git_checkout": true,
  "note": "No conformance test ran. On Windows, check an OMP shell shim with omp --version in PowerShell."
}
```

`raw/environment-r1.log` records the active power scheme, `Balanced` (`381b4222-f694-41f0-9685-ff5bb260df2e`).
It also records a PowerShell process started through the same `record` command path, which reports 32 logical processors and the processor affinity mask `4294967295`, which selects all 32.
The measurement processes started the same way and set no affinity, so they kept that default mask [INFERENCE: the mask was read from the PowerShell process, not from the measurement processes].
The processor is an AMD Ryzen 9 9955HX3D with 16 cores and 32 logical processors, as the worker's `raw/measure-load.log` reports.

`raw/measure-build-r1.log` records `zig build measure -Doptimize=ReleaseFast --summary all` in the worktree, with the locked compiler and the recorded override `ZIG_GLOBAL_CACHE_DIR`, and 8 of 8 steps.
The locked compiler names the `ReleaseFast` mode `fast`.

These are the harness header lines of the six runs.

```text
reference run 1:    {"format":"fairpane-js-measure","version":1,"representation":"reference","value_size_bytes":16,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
nan_box run 1:      {"format":"fairpane-js-measure","version":1,"representation":"nan_box","value_size_bytes":8,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047040,"clock":"awake","allocator":"smp_allocator"}
tagged_index run 1: {"format":"fairpane-js-measure","version":1,"representation":"tagged_index","value_size_bytes":4,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
reference run 2:    {"format":"fairpane-js-measure","version":1,"representation":"reference","value_size_bytes":16,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
nan_box run 2:      {"format":"fairpane-js-measure","version":1,"representation":"nan_box","value_size_bytes":8,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047040,"clock":"awake","allocator":"smp_allocator"}
tagged_index run 2: {"format":"fairpane-js-measure","version":1,"representation":"tagged_index","value_size_bytes":4,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
```

The runs followed the order `reference`, `nan_box`, `tagged_index`, `reference`, `nan_box`, `tagged_index`.
They started at 11:24:50Z, 11:24:52Z, 11:24:53Z, 11:24:56Z, 11:24:58Z, and 11:25:00Z, and every run exited with status 0.
The integrator's session ran no other command during the runs.
Three agent sessions were open, one review and two contract drafts, each instructed to install, build, and execute nothing; no record shows their processes [INFERENCE: from the instructions, not from a process record].
The FP-0014 worker's last recorded command ran at 11:23:13Z, before the runs.
No processor-load reading was recorded.

## 4. Measurements

Each executable checked every vector of cases 21 through 23 in its own optimize mode, ran each workload once as warmup, and then ran it 11 more times.
`raw/measure-summary-r1.log` records the SHA-256 and the output of `raw/measure-summary-r1.mjs`, which applies the method of the original `raw/measure-summary.log`.
The script takes the 11 measured samples of each workload, sorts their `ns` values, and reports the first, sixth, and eleventh.
Each `ns` value times only a workload's steps, not heap creation or the checksum.

| Workload | Representation | Run | Min ns | Median ns | Max ns |
| --- | --- | --- | ---: | ---: | ---: |
| `add-small-int` | `reference` | 1 | 18588900 | 18648200 | 18749700 |
| `add-small-int` | `reference` | 2 | 18688000 | 18775200 | 19202000 |
| `add-small-int` | `nan_box` | 1 | 12365300 | 12385800 | 12564700 |
| `add-small-int` | `nan_box` | 2 | 12578400 | 12724400 | 12796300 |
| `add-small-int` | `tagged_index` | 1 | 28101700 | 28193200 | 28348800 |
| `add-small-int` | `tagged_index` | 2 | 28031100 | 28166500 | 28275400 |
| `add-fraction` | `reference` | 1 | 18600800 | 18632500 | 18688700 |
| `add-fraction` | `reference` | 2 | 18502000 | 18542500 | 18769200 |
| `add-fraction` | `nan_box` | 1 | 12369900 | 12419300 | 18486600 |
| `add-fraction` | `nan_box` | 2 | 12624200 | 12679100 | 12948800 |
| `add-fraction` | `tagged_index` | 1 | 38870500 | 39529300 | 40248500 |
| `add-fraction` | `tagged_index` | 2 | 38893500 | 39039100 | 39241600 |
| `get-prototype-chain` | `reference` | 1 | 24874400 | 25060900 | 26116500 |
| `get-prototype-chain` | `reference` | 2 | 25159000 | 25377500 | 26379100 |
| `get-prototype-chain` | `nan_box` | 1 | 22749100 | 22873900 | 24584000 |
| `get-prototype-chain` | `nan_box` | 2 | 23017000 | 23416800 | 24387200 |
| `get-prototype-chain` | `tagged_index` | 1 | 23181700 | 23787500 | 24230900 |
| `get-prototype-chain` | `tagged_index` | 2 | 22618300 | 22967500 | 23383700 |
| `number-to-string` | `reference` | 1 | 6466300 | 6571000 | 7100700 |
| `number-to-string` | `reference` | 2 | 6439100 | 6528200 | 7035300 |
| `number-to-string` | `nan_box` | 1 | 4976800 | 5026100 | 5331700 |
| `number-to-string` | `nan_box` | 2 | 5019200 | 5112100 | 5523300 |
| `number-to-string` | `tagged_index` | 1 | 7097500 | 7180000 | 7686300 |
| `number-to-string` | `tagged_index` | 2 | 7150100 | 7255800 | 7500200 |
| `object-churn` | `reference` | 1 | 9760300 | 19119700 | 30549700 |
| `object-churn` | `reference` | 2 | 15930300 | 27121700 | 33677100 |
| `object-churn` | `nan_box` | 1 | 17036000 | 23504700 | 33321300 |
| `object-churn` | `nan_box` | 2 | 18252800 | 25730800 | 32875700 |
| `object-churn` | `tagged_index` | 1 | 30585000 | 42606800 | 53994900 |
| `object-churn` | `tagged_index` | 2 | 32143300 | 42707200 | 57961300 |
| `mark-generated` | `reference` | 1 | 1881400 | 2110000 | 2840600 |
| `mark-generated` | `reference` | 2 | 7567000 | 7986700 | 8475400 |
| `mark-generated` | `nan_box` | 1 | 7504500 | 16586300 | 18111600 |
| `mark-generated` | `nan_box` | 2 | 16180700 | 17268400 | 17883200 |
| `mark-generated` | `tagged_index` | 1 | 9454900 | 9990200 | 10850200 |
| `mark-generated` | `tagged_index` | 2 | 10691100 | 11487900 | 12289000 |
| `mark-manual` | `reference` | 1 | 1905600 | 2263400 | 3046500 |
| `mark-manual` | `reference` | 2 | 2397000 | 8111700 | 12706400 |
| `mark-manual` | `nan_box` | 1 | 2533300 | 2629100 | 2940000 |
| `mark-manual` | `nan_box` | 2 | 2553500 | 7308700 | 18789000 |
| `mark-manual` | `tagged_index` | 1 | 10024300 | 10933900 | 11836700 |
| `mark-manual` | `tagged_index` | 2 | 10029600 | 10919400 | 11539400 |

| Representation | `value_size_bytes` | `executable_bytes` | `object-churn` peak live bytes, both runs |
| --- | ---: | ---: | ---: |
| `reference` | 16 | 1047552 | 27923892 |
| `nan_box` | 8 | 1047040 | 27058908 |
| `tagged_index` | 4 | 1047552 | 70279372 |

`cells_allocated`, `bytes_allocated`, and `peak_live_bytes` cover a whole sample, including the 20 intrinsic cells that `Heap.init` creates.
Under `tagged_index`, `add-fraction` allocated 500028 cells, `number-to-string` 200026, and `object-churn`, `mark-generated`, and `mark-manual` 500026 each, because each fraction lives in a `heap_number` cell.
The other two representations allocated 27 cells for `add-fraction` and 100026 for each of the other four.
`add-fraction` ran no collection, because the only collection trigger is the cell limit.

## 5. Separability

`raw/measure-summary-r1.log` applies the separability rule to the revision 1 runs.
A difference is separable only when the two sample ranges do not overlap in both runs.
"Faster" means that the first range lies wholly below the second range in both runs.

| Workload | `nan_box` against `reference` | `tagged_index` against `reference` | `nan_box` against `tagged_index` |
| --- | --- | --- | --- |
| `add-small-int` | faster | slower | faster |
| `add-fraction` | faster | slower | faster |
| `get-prototype-chain` | faster | faster | not separable; both runs overlap |
| `number-to-string` | faster | not separable; overlap in run 1, slower in run 2 | faster |
| `object-churn` | not separable; both runs overlap | not separable; slower in run 1, overlap in run 2 | not separable; both runs overlap |
| `mark-generated` | slower | slower | not separable; overlap in run 1, slower in run 2 |

| Representation | `mark-generated` against `mark-manual` |
| --- | --- |
| `reference` | not separable; both runs overlap |
| `nan_box` | not separable; slower in run 1, overlap in run 2 |
| `tagged_index` | not separable; both runs overlap |

### Level shifts

Contract revision 1 requires this section to state any shift of sample level within a run that decides a separability outcome.
`raw/measure-shift-decisions-r1.log` records the SHA-256 and the output of `raw/measure-shift-decisions-r1.mjs`.
A level shift splits a run's 11 measured samples, in sample order, into a prefix and a suffix whose ranges do not overlap and whose medians differ by a factor of at least 1.5.
A shift decides an outcome when keeping only the prefix, or only the suffix, as that run's samples changes the outcome between separably faster, separably slower, and not separable.
Five series have shifts, and three of the shifts decide an outcome.

| Series | Samples in order, ns | Outcome that the shift decides |
| --- | --- | --- |
| `reference` run 1 `object-churn` | 23106900 15911900 25023200 19119700 27356300 22394900 30549700 17333000 13302800 9760300 10167500 | None |
| `reference` run 2 `mark-manual` | 8118000 12305800 7871100 11571500 7962300 12034800 8111700 12706400 4757800 3497800 2397000 | None |
| `nan_box` run 1 `mark-generated` | 16338200 17471900 16273800 17560300 16199900 17003900 16586300 18111600 16370500 17794100 7504500 | `nan_box` against `tagged_index` on `mark-generated` is not separable; samples 1 to 10 alone would make `nan_box` separably slower. |
| `nan_box` run 2 `mark-manual` | 16464900 18789000 15947400 18355200 16256600 7308700 2553500 2810400 2609800 2867200 2558300 | The tracer comparison under `nan_box` is not separable; samples 6 to 11, or 7 to 11, alone would make `mark-generated` separably slower than `mark-manual`. |
| `tagged_index` run 2 `object-churn` | 32730100 32143300 36170600 40555500 42347400 42707200 50872500 49328700 54636000 55321500 57961300 | `tagged_index` against `reference` on `object-churn` is not separable; samples 3 to 11, or 4 to 11, alone would make `tagged_index` separably slower. |

Only the `nan_box` run 2 `mark-manual` shift decides an outcome that a pre-registered rule uses: the tracer rule in section 6.
The other two deciding shifts change no rule outcome, because `tagged_index` does not qualify and the comparison between the candidates applies only when both qualify.
An earlier version of the script compared the whole verdict text, so it also counted a change inside "not separable" as a decision.
Its run is kept as `raw/measure-shift-decisions-r1-attempt-1.log`, that version as `raw/measure-shift-decisions-r1-attempt-1.mjs`, and an accidental repeat of the same run as `raw/measure-shift-decisions-r1-attempt-2.log`.

## 6. Application of the pre-registered rules

These rules apply to the revision 1 runs.
Every sample of every run reported its table checksum, and every run exited with status 0.

`nan_box` is separably faster than `reference` on four of the six workloads: `add-small-int`, `add-fraction`, `get-prototype-chain`, and `number-to-string`.
It is separably slower on `mark-generated`, and no level shift decides that outcome.
`nan_box` therefore does not qualify.

`tagged_index` is separably faster than `reference` on one workload, `get-prototype-chain`.
It is separably slower on `add-small-int`, `add-fraction`, and `mark-generated`.
`tagged_index` therefore does not qualify.

No candidate qualifies, so `reference` stays `FP-0012`'s default representation.
The worker's runs had made `nan_box` the default, and this record withdraws that outcome.

Case 9 passes in `raw/r1-integration-tests.log`, the uncached test run at `60c0c90`.
`mark-generated` is not separably slower than `mark-manual` under any representation.
Under the pre-registered rule, the generated tracer becomes `FP-0012`'s default tracer.
Under `nan_box`, that outcome depends on the level shift in run 2 of `mark-manual`, as section 5 states.
Under `reference`, which `FP-0012` uses, the two tracers do not separate in either run, and no shift decides that outcome.

## 7. Limits

The measurements come from one machine and one target, `x86_64-windows-gnu`.
The workloads are microbenchmarks over the generic kernels, without an integrated workload.
`docs/QUALIFICATION.md` requires an integrated workload check before any microbenchmark win counts, so this record makes no speed claim beyond the recorded samples.
The `mark-*` and `object-churn` samples fall into separate levels, within runs as section 5 lists and between runs.
For example, `reference` `mark-generated` ranged from 1881400 to 2840600 ns in run 1 and from 7567000 to 8475400 ns in run 2 for the same work.
No record shows which logical processor ran each sample, so the cause of the levels is unmeasured.
[INFERENCE] The processor has two core complexes with different cache sizes, and the heaps of these workloads, about 27 to 70 MB at their peak, exceed the smaller cache, so a thread that moves between the complexes would change their timing.
The kernels are the generic reference, so each sample includes their scope and invocation overhead, which is the same code for every representation.

## 8. Consequences

`reference`, `nan_box`, and `tagged_index` remain built and tested, and `reference` remains the generic reference for every later comparison.
The generated tracer and the manual tracer both remain built, and case 9 keeps testing their equivalence.
`FP-0012` starts from `reference` and the generated tracer.
Before any speed claim, it repeats these comparisons on an integrated workload, interleaves the representations and tracers within one process, and records the logical processor of each sample, as its plan entry requires.
No value representation reaches the C ABI: the fixtures of case 20 fail to compile, and no file under `src/js` declares an exported or C-calling-convention function.
