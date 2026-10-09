# FP-0081 task contract

## Identity

Task ID: `FP-0081`, "Let a host bound engine allocation through the public contract".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0050`, accepted.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Integrator decisions

- The C ABI takes no allocator, so `api/failure-scenarios.json` marks `allocation-failure` as not expressible in C, and no foreign wrapper can run it.
  The scenario needs "the next allocation fails" at a chosen point.
  A limit fixed at creation cannot place that point, so the engine also reports its allocated bytes and accepts a new limit.
  With both, a host sets the limit to the allocated bytes, and the next allocation fails.
- The limit is a product feature, not a test hook: an embedder bounds the memory of each engine.
  The engine never calls host code for it.
- The engine counts the byte lengths that it requests from its allocator.
  It does not count allocator overhead or alignment padding, so the count is the same on every allocator and platform.
- `UINT64_MAX` permits every allocation that the process allocator grants.
  No value is a sentinel.
- `abi_revision` stays 0, because revision zero makes no stability promise (`api/fairpane.schema.json:8`).
  A caller compiled against the older `fp_engine_options` passes a smaller `struct_size`, and the engine rejects it with `FP_STATUS_INVALID_ARGUMENT`.

## Sources

- `api/fairpane.schema.json`, `api/README.md`, and `api/failure-scenarios.json:168-190`, the `allocation-failure` scenario.
- `src/c_api.zig`: `process_allocator` at line 54, `createEngine` at lines 112-120, and `fp_engine_create` at line 193.
- `src/engine.zig`: `Engine.create` at line 211, which takes the allocator that the engine keeps, and `Engine.destroy`.
- `src/abi_scenarios.zig` and `tests/c/abi_smoke.c`, which run every scenario that each language can express.
- `tools/abi.mjs`, the generator and the layout model, and its tests.
- `engineering/evidence/FP-0050/CONTRACT.md`, which requires that a failed call change nothing.

## Behavior

### Interface

The schema changes through the existing generator, and `include/fairpane.h` and `src/abi_generated.zig` are regenerated.

- `engine_options` gains a final field `max_allocated_bytes`, a 64-bit unsigned integer with range 0 to 18446744073709551615.
  Its description is "The most bytes that the engine's allocations may hold at once. 18446744073709551615 permits every allocation that the process allocator grants."
- A new output structure `engine_memory` has the fields `struct_size`, `reserved`, `allocated_bytes`, and `max_allocated_bytes`.
  `reserved` is a 32-bit unsigned integer with range 0 to 0, described as "Always zero."
  `allocated_bytes` is "The bytes that the engine's live allocations hold."
  `max_allocated_bytes` is "The current limit."
- A new function `engine_get_memory(engine, out)` initializes `engine_memory`.
  Its statuses are `ok`, `invalid_argument`, and `wrong_thread`, and it allocates nothing.
- A new function `engine_set_memory_limit(engine, max_allocated_bytes)` replaces the limit.
  Its statuses are `ok`, `invalid_argument`, and `wrong_thread`, and it allocates nothing.
  A limit below `allocated_bytes` is accepted.
- Both functions run on the owner thread and check the thread first, like every other owner function.

### Accounting

Each engine counts the bytes of its live allocations.

- An allocation of `n` bytes succeeds only when `allocated_bytes + n` is at most the limit and the process allocator grants it.
  Then `allocated_bytes` grows by `n`.
- A resize or remap that grows an allocation by `d` bytes succeeds only when `allocated_bytes + d` is at most the limit and the process allocator grants it.
- A shrinking resize or remap and a free never fail on the limit, and they reduce `allocated_bytes` by the bytes that they release.
- Every allocation that the engine makes counts, including the engine record and the accounting state.
  `fp_engine_create` checks each allocation against `options.max_allocated_bytes` before it makes it.
- After `fp_engine_destroy`, nothing that the engine allocated remains.

A refused allocation is an allocation failure.
The operation returns `FP_STATUS_OUT_OF_MEMORY` and changes nothing, as FP-0050 requires.
The engine and every handle stay usable, and the same call succeeds once a higher limit allows its allocations.

### Scenario

`api/failure-scenarios.json` marks `allocation-failure` as expressible in C and removes its `reason`.
Its calls induce each failure through the limit alone:

- `fp_engine_create` with `max_allocated_bytes` 0 returns `out_of_memory` and writes no engine.
- `fp_document_create` after `fp_engine_set_memory_limit` to the reported `allocated_bytes` returns `out_of_memory`.
- `fp_document_load` is called with the limit at `allocated_bytes`, then one byte higher, and so on, until it succeeds.
  Every earlier call returns `out_of_memory` and changes nothing that `fp_document_get` and `fp_engine_get_memory` report.
- The input-queue and event-queue calls of the existing scenario fail in the same way when their queue must grow.
- `fp_document_destroy` succeeds with the limit at `allocated_bytes`, because it allocates nothing.

`api/README.md` states that the limit makes the scenario expressible in C, and its Engines section describes the limit and the two functions.

## Exact test cases

1. Zig: a budget unit test over a recording allocator shows that an allocation of exactly the remaining bytes succeeds and one byte more fails, that a growing resize and remap of exactly the remaining bytes succeeds and one byte more fails, and that a shrink and a free always succeed and reduce the count by the released bytes.
2. Zig: across the whole call sequence of the `allocation-failure` scenario, after every call, `fp_engine_get_memory` reports `allocated_bytes` equal to the bytes live in a recording allocator under the engine.
3. Zig: `createEngine` with a limit below the bytes that creation needs returns `out_of_memory`, leaves the output engine unwritten, and leaves nothing allocated in the recording allocator.
4. Zig: `fp_engine_set_memory_limit` below `allocated_bytes` succeeds, every allocating call then returns `out_of_memory`, and raising the limit again lets the same calls succeed.
5. Zig and C: `fp_engine_get_memory` with a too-small `out_size`, a null `out`, or a null engine returns `invalid_argument` and writes nothing, and both functions return `wrong_thread` from a foreign thread before any other check.
6. C: `tests/c/abi_smoke.c` runs `Scenario allocation-failure:` through the limit, with every call and effect of the scenario.
7. Zig: `src/abi_scenarios.zig` keeps its existing `FailingAllocator` run of every allocation point, the `failEachAllocation` loop with `.resize_fail_index = 0`, unchanged, and adds the same scenario through the limit.
8. Controller: the generated header, the generated Zig declarations, and the layout model agree on the sizes and offsets of `engine_options` and `engine_memory` on 32-bit and 64-bit targets, and the scenario checks require the C smoke test to name `allocation-failure`.
9. Controller: the schema checker rejects a fixture structure with a 32-bit field followed by a 64-bit field, and one with a 64-bit field followed by a single 32-bit field, each with a message that names the structure and the member that needs padding; the committed schema passes.

Cases 1 to 6 and 8 must fail before the change.
Two mutation controls must each fail a case: one counts no growth of a resize, and one leaves the engine record uncounted.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0081/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `generate.log` with the generator run and a second run that changes nothing.
3. `mutation.log` and its diffs, with the hash of each changed file before, during, and after.
4. An uncached `tests-after.log` with `zig build test --summary all`, `c-abi-after.log` with `node tools/fairpane.mjs run c-abi` output, `controller-tests-after.log`, and `fmt.log`.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and `c-abi`.

## Authority

Writable paths: `api`, `include`, `src`, `tests`, `tools`, `build.zig`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewers: `fairpane-review` and `fairpane-security`.

## Non-goals

- No limit on the host's memory, on stack use, or on allocations outside an engine.
- No peak or history statistics.
- No change to `max_outstanding_requests`, `max_response_body_bytes`, or `FP_STATUS_LIMIT_EXCEEDED`.
- No Rust code; `FP-0029` runs the scenario through the Rust wrapper.

## Amendments

1. Case 7 named the wrong enumerator.
   The existing run in `src/abi_scenarios.zig` enumerates allocation points with its own `failEachAllocation` loop over a `testing.FailingAllocator` with `.resize_fail_index = 0`, not with `testing.checkAllAllocationFailures`.
   Worker `FP0081Budget` found the difference, and the case now names that loop; the requirement to keep the run and add the limit run is unchanged.
2. `engine_memory` gains `reserved` after `struct_size`, and the schema checker forbids implicit padding.
   Worker `FP0081Budget` found that the frozen fields put a 64-bit member after a lone 32-bit member.
   The 32-bit x86 System V ABI aligns a 64-bit member to four bytes, while 64-bit targets and 32-bit Windows align it to eight, so the offsets would differ by target and the layout model would be wrong for one of them.
   With `reserved`, every member falls at a multiple of its size, and the layout is the same on every target of one pointer width.
   The schema checker in `tools/abi.mjs` now rejects a structure in which, at either pointer width, a member's offset is not the sum of the earlier members' sizes or not a multiple of its own size, or the structure's size is not a multiple of its largest member's size.
   Every structure of the committed schema already meets that rule.
   Case 9 covers the rule.
