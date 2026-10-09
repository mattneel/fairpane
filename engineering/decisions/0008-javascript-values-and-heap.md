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

`Runtime(r).Context(effects)` is the only way for a kernel to reach the heap.
Each kernel's first parameter is a context with exactly its entry's effects, and `bindKernels` checks every kernel's parameters and return type at compile time.
`invoke` narrows a context to the operation's effects, so a context can invoke only operations whose effects it holds.
Each heap primitive requires an effect set, and a built-in behavior's first parameter is a context with every effect.
The compile-failure fixtures of cases 4, 5, and 8 show each rejected form with its diagnostic.

The rooting protocol has three rules.
A caller keeps every `Value` and `CellRef` argument rooted for the duration of the call.
A kernel returns its result unrooted.
A kernel roots each intermediate that it holds across an invocation with the `allocation` effect.
Case 11 enforces the protocol at run time with a collection before every allocation and a quarantine of freed cells.
The mutation control `raw/mutation-left-root.diff` removes the root of the left primitive in `addition`, and `raw/mutation-left-root.log` shows case 11 failing on scenario AD19 under `reference` with `dead_resolutions 4` while every other test, including case 31, passes.

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

`raw/doctor.log` holds this output of `node tools/fairpane.mjs doctor`.

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
    "available": false,
    "error": "The locked compiler is absent. Run the local compiler installer.",
    "expected_path": "C:\\Users\\requi\\.omp\\wt\\t1d8c598d4\\m\\.tools\\zig\\0.18.0-dev.120+9fe22a29b\\x86_64-windows\\zig.exe"
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

The doctor looked for the compiler inside the worker's tree.
Every recorded build used the locked compiler at `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`, as each log's `COMMAND` line shows.
The processor is an AMD Ryzen 9 9955HX3D with 16 cores and 32 logical processors, as `raw/measure-load.log` reports.

These are the harness header lines of the six runs.

```text
reference run 1:    {"format":"fairpane-js-measure","version":1,"representation":"reference","value_size_bytes":16,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
nan_box run 1:      {"format":"fairpane-js-measure","version":1,"representation":"nan_box","value_size_bytes":8,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047040,"clock":"awake","allocator":"smp_allocator"}
tagged_index run 1: {"format":"fairpane-js-measure","version":1,"representation":"tagged_index","value_size_bytes":4,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
reference run 2:    {"format":"fairpane-js-measure","version":1,"representation":"reference","value_size_bytes":16,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
nan_box run 2:      {"format":"fairpane-js-measure","version":1,"representation":"nan_box","value_size_bytes":8,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047040,"clock":"awake","allocator":"smp_allocator"}
tagged_index run 2: {"format":"fairpane-js-measure","version":1,"representation":"tagged_index","value_size_bytes":4,"zig_version":"0.18.0-dev.120+9fe22a29b","target":"x86_64-windows-gnu","cpu_model":"znver5","optimize":"fast","logical_cpus":32,"executable_bytes":1047552,"clock":"awake","allocator":"smp_allocator"}
```

The locked compiler names the `ReleaseFast` mode `fast`.
`raw/measure-build.log` records `zig build measure -Doptimize=ReleaseFast --summary all`.
The runs followed the order `reference`, `nan_box`, `tagged_index`, `reference`, `nan_box`, `tagged_index`, and every run exited with status 0.
Before each run, `raw/measure-load.log` recorded a processor load of 1, 1, 3, 0, 7, and 0 percent.
Other agent sessions were open on the host, so those single readings are the only evidence of an idle machine.

## 4. Measurements

Each executable checked every vector of cases 21 through 23 in its own optimize mode, ran each workload once as warmup, and then ran it 11 more times.
`raw/measure-summary.log` records the summary script and its output.
The script takes the 11 measured samples of each workload, sorts their `ns` values, and reports the first, sixth, and eleventh.
Each `ns` value times only a workload's steps, not heap creation or the checksum.
Every recorded `ns` value is a multiple of 100.

| Workload | Representation | Run | Min ns | Median ns | Max ns |
| --- | --- | --- | ---: | ---: | ---: |
| `add-small-int` | `reference` | 1 | 17379500 | 17458000 | 17689100 |
| `add-small-int` | `reference` | 2 | 17403500 | 17475500 | 17505100 |
| `add-small-int` | `nan_box` | 1 | 12083400 | 12142200 | 12247300 |
| `add-small-int` | `nan_box` | 2 | 12194700 | 12238300 | 12300700 |
| `add-small-int` | `tagged_index` | 1 | 28218500 | 28307300 | 28614800 |
| `add-small-int` | `tagged_index` | 2 | 28552500 | 28961100 | 29303600 |
| `add-fraction` | `reference` | 1 | 17447000 | 17474800 | 17508500 |
| `add-fraction` | `reference` | 2 | 17429900 | 17461500 | 17534100 |
| `add-fraction` | `nan_box` | 1 | 12128000 | 12147800 | 12190100 |
| `add-fraction` | `nan_box` | 2 | 12217700 | 12287100 | 12419400 |
| `add-fraction` | `tagged_index` | 1 | 37815800 | 38300300 | 38762900 |
| `add-fraction` | `tagged_index` | 2 | 38205700 | 38744400 | 39319200 |
| `get-prototype-chain` | `reference` | 1 | 24548900 | 24596300 | 24845800 |
| `get-prototype-chain` | `reference` | 2 | 24535900 | 24692300 | 24810300 |
| `get-prototype-chain` | `nan_box` | 1 | 23085800 | 23177200 | 23217100 |
| `get-prototype-chain` | `nan_box` | 2 | 23207300 | 23253400 | 23604200 |
| `get-prototype-chain` | `tagged_index` | 1 | 22041300 | 22912400 | 23512000 |
| `get-prototype-chain` | `tagged_index` | 2 | 22245900 | 23161700 | 24146200 |
| `number-to-string` | `reference` | 1 | 6244900 | 6307800 | 6525000 |
| `number-to-string` | `reference` | 2 | 6235700 | 6310800 | 6485100 |
| `number-to-string` | `nan_box` | 1 | 4766100 | 4825400 | 5235800 |
| `number-to-string` | `nan_box` | 2 | 4812600 | 4867600 | 4994700 |
| `number-to-string` | `tagged_index` | 1 | 6759400 | 6780300 | 8657400 |
| `number-to-string` | `tagged_index` | 2 | 7213100 | 8989200 | 9532300 |
| `object-churn` | `reference` | 1 | 13307500 | 19908800 | 26053400 |
| `object-churn` | `reference` | 2 | 12834700 | 19865200 | 25583900 |
| `object-churn` | `nan_box` | 1 | 13785300 | 17373300 | 24862700 |
| `object-churn` | `nan_box` | 2 | 13585200 | 18830300 | 28887800 |
| `object-churn` | `tagged_index` | 1 | 28679000 | 39453700 | 49401800 |
| `object-churn` | `tagged_index` | 2 | 28634500 | 41360100 | 51157900 |
| `mark-generated` | `reference` | 1 | 5336200 | 6236000 | 6670800 |
| `mark-generated` | `reference` | 2 | 5598900 | 6513500 | 6855200 |
| `mark-generated` | `nan_box` | 1 | 10120300 | 11320700 | 13294500 |
| `mark-generated` | `nan_box` | 2 | 2649700 | 14118400 | 15733500 |
| `mark-generated` | `tagged_index` | 1 | 9574300 | 10184800 | 10365400 |
| `mark-generated` | `tagged_index` | 2 | 10262700 | 15232400 | 31166200 |
| `mark-manual` | `reference` | 1 | 6480900 | 7480400 | 9440100 |
| `mark-manual` | `reference` | 2 | 1811700 | 2237700 | 7752900 |
| `mark-manual` | `nan_box` | 1 | 10709800 | 12249700 | 14064200 |
| `mark-manual` | `nan_box` | 2 | 2532600 | 2872600 | 3393500 |
| `mark-manual` | `tagged_index` | 1 | 9440500 | 9957800 | 10685700 |
| `mark-manual` | `tagged_index` | 2 | 10314700 | 15317300 | 25389100 |

| Representation | `value_size_bytes` | `executable_bytes` | `object-churn` peak live bytes, both runs |
| --- | ---: | ---: | ---: |
| `reference` | 16 | 1047552 | 27923892 |
| `nan_box` | 8 | 1047040 | 27058908 |
| `tagged_index` | 4 | 1047552 | 70279372 |

`cells_allocated`, `bytes_allocated`, and `peak_live_bytes` cover a whole sample, including the 20 intrinsic cells that `Heap.init` creates.
Under `tagged_index`, `add-fraction` allocated 500028 cells and `object-churn` allocated 500026, because each fraction lives in a `heap_number` cell.
The other two representations allocated 27 and 100026 cells for those workloads.
`add-fraction` ran no collection, because the only collection trigger is the cell limit.

## 5. Separability

A difference is separable only when the two sample ranges do not overlap in both runs.
"Faster" means that the first range lies wholly below the second range in both runs.

| Workload | `nan_box` against `reference` | `tagged_index` against `reference` | `nan_box` against `tagged_index` |
| --- | --- | --- | --- |
| `add-small-int` | faster | slower | faster |
| `add-fraction` | faster | slower | faster |
| `get-prototype-chain` | faster | faster | not separable; both runs overlap |
| `number-to-string` | faster | slower | faster |
| `object-churn` | not separable; both runs overlap | slower | not separable; faster in run 1, overlap in run 2 |
| `mark-generated` | not separable; slower in run 1, overlap in run 2 | slower | not separable; both runs overlap |

| Representation | `mark-generated` against `mark-manual` |
| --- | --- |
| `reference` | not separable; both runs overlap |
| `nan_box` | not separable; both runs overlap |
| `tagged_index` | not separable; both runs overlap |

## 6. Application of the pre-registered rules

Every sample of every run reported its table checksum, and every run exited with status 0.

`nan_box` is separably faster than `reference` on four of the six workloads: `add-small-int`, `add-fraction`, `get-prototype-chain`, and `number-to-string`.
It is separably slower on none.
`nan_box` therefore qualifies.

`tagged_index` is separably faster than `reference` on one workload, `get-prototype-chain`.
It is separably slower on `add-small-int`, `add-fraction`, `number-to-string`, `object-churn`, and `mark-generated`.
`tagged_index` therefore does not qualify.

Only one candidate qualifies, so the tie rule does not apply.
Under the pre-registered rule, `nan_box` becomes `FP-0012`'s default representation.

Case 9 passes in `raw/tests-after.log`.
`mark-generated` is not separably slower than `mark-manual` under any representation.
Under the pre-registered rule, the generated tracer becomes `FP-0012`'s default tracer.

## 7. Limits

The measurements come from one machine and one target, `x86_64-windows-gnu`.
The workloads are microbenchmarks over the generic kernels, without an integrated workload.
`docs/QUALIFICATION.md` requires an integrated workload check before any microbenchmark win counts, so this record makes no speed claim beyond the recorded samples.
The `mark-*` and `object-churn` samples spread widely within each run; for example, `mark-manual` under `reference` ranged from 1811700 to 7752900 ns in run 2.
The recorded load readings are single instants, so concurrent activity between them is unmeasured.
The kernels are the generic reference, so each sample includes their scope and invocation overhead, which is the same code for every representation.

## 8. Consequences

`reference`, `nan_box`, and `tagged_index` remain built and tested, and `reference` remains the generic reference for every later comparison.
The generated tracer and the manual tracer both remain built, and case 9 keeps testing their equivalence.
`FP-0012` starts from `nan_box` and the generated tracer, and it repeats these comparisons on an integrated workload before any speed claim.
No value representation reaches the C ABI: the fixtures of case 20 fail to compile, and no file under `src/js` declares an exported or C-calling-convention function.
