# FP-0004 task contract

## Identity

Task ID: `FP-0004`, "Implement checked owners and generational handles".
Workstream: `substrate`.
Base: the commit that records `FP-0001` acceptance, with source digest `f2d2e0e6d03370c93235066bb420fb81419448f05e97b7af54483579c4c46087` before that state change.
Prerequisites: `FP-0001`.
Assigned role: `fairpane-core`.

## Behavior

### Owner identity

`src/handles.zig` defines `OwnerId` as a nonzero 64-bit identity type.
`OwnerIdSource` issues strictly increasing identities with an atomic operation.
A source never wraps and never issues zero.
After it issues `maxInt(u64)`, every later request returns `error.OwnerIdsExhausted`.
A source can start at any nonzero value, so tests can reach exhaustion directly.
The module provides one process-wide source for engine owners.
An identity never derives from an address.

### Generational table

`Table(T, config)` stores values of type `T` for exactly one `OwnerId`.
`config.Index` and `config.Generation` are unsigned integer types with defaults `u32` and `u32`.
Each instantiation declares its own `Handle` type with `owner`, `index`, and `generation` fields.
A handle contains no pointer, and no API converts between handles and addresses.

| Operation | Contract |
| --- | --- |
| `init(owner)` | Creates an empty table without allocation. |
| `deinit(gpa)` | Releases table storage. It does not destroy values; the owner removes or visits them first. |
| `insert(gpa, value)` | Returns a new handle. It reuses a free slot before it grows storage. |
| `get(handle)` | Returns a copy of the value. |
| `getPtr(handle)` | Returns a pointer that stays valid until the next `insert`, `remove`, or `deinit`. |
| `remove(handle)` | Returns the value and invalidates every handle to that slot generation. |
| `validate(handle)` | Checks a handle without returning the value. |
| `count()` | Returns the number of live values. |
| `iterator()` | Visits each live value and its handle exactly once. |

Every lookup checks the owner first.
A different owner returns `error.WrongOwner`, even when the index is out of range.
An index outside the table or generation zero returns `error.InvalidHandle`.
A free slot, a retired slot, or a generation mismatch returns `error.StaleHandle`.

New slots start at generation 1.
`remove` increments the slot generation and places the slot on the free list.
When the slot generation is already the maximum value, `remove` retires the slot permanently.
A retired slot never returns to the free list.
No table issues the same owner, index, and generation triple twice.

Growth is the only allocation point.
`insert` reserves capacity before it changes any state.
On `error.OutOfMemory`, the table is unchanged and the caller still owns the value.
When no free slot exists and the next index exceeds `config.Index`, `insert` returns `error.HandleSpaceExhausted` without allocation.
The table remains valid and destructible after every error in this contract.

### Boundary rule

`api/README.md` states that internal handles never cross the C ABI or the process protocol directly.
A later boundary maps handles through explicit, validated conversion to its own identifier type.
Those boundaries are outside this task.

## Exact test cases

Each test lives in `src/handles.zig` and runs through `zig build test`.

1. Inserted values round-trip through `get`, `getPtr`, and `remove`.
2. A handle presented to a table with another owner returns `error.WrongOwner`, including an out-of-range index.
3. After `remove`, the old handle returns `error.StaleHandle`, and the next insert reuses the index with a new generation.
4. Forged handles with an out-of-range index or generation zero return `error.InvalidHandle`.
5. With `Generation = u2`, repeated insert and remove cycles retire the slot after generation 3.
   The next insert uses a new index, and every earlier handle stays stale.
6. With `Index = u2` and `Generation = u2`, filling and retiring every index yields `error.HandleSpaceExhausted` without allocation.
7. When growth fails, `insert` returns `error.OutOfMemory` and leaves count, handles, and free slots unchanged.
8. `std.testing.checkAllAllocationFailures` runs a scenario with growth, removal, reuse, and iteration.
   Each induced failure returns `error.OutOfMemory`, keeps the invariants, and leaks nothing after `deinit`.
9. After each of `WrongOwner`, `InvalidHandle`, `StaleHandle`, `HandleSpaceExhausted`, and `OutOfMemory`, the invariant check passes and `deinit` leaks nothing.
10. An owner source started at `maxInt(u64) - 1` issues two identities and then returns `error.OwnerIdsExhausted` repeatedly.
11. Four threads that each request 1000 identities from one source receive 4000 distinct identities.
12. Compile-time checks show that two table instantiations have different handle types and that a handle is not a pointer type.
13. Iteration visits each live value exactly once and skips free and retired slots.
14. Fixed-seed randomized operation sequences agree with a simple reference model of live, stale, and retired handles.

A test-only invariant function checks the free list, live count, generation bounds, and retired slots.

## Authority

Writable paths: `src`, `tests`, `api`, `include`, and `build.zig`.
Protected paths: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Required independent reviewer: `fairpane-review`.

## Acceptance

Failing tests first: each case above fails or does not compile before the implementation exists.
Exact gate commands, run by the integrator after review:

```text
node tools/fairpane.mjs run repo-check --evidence-dir engineering/evidence/FP-0004/gates
node tools/fairpane.mjs run controller-test --evidence-dir engineering/evidence/FP-0004/gates
node tools/fairpane.mjs run zig-fmt --evidence-dir engineering/evidence/FP-0004/gates
node tools/fairpane.mjs run zig-test --evidence-dir engineering/evidence/FP-0004/gates
node tools/fairpane.mjs run zig-build --evidence-dir engineering/evidence/FP-0004/gates
node tools/fairpane.mjs run c-abi --evidence-dir engineering/evidence/FP-0004/gates
```

The integrator also records `zig build test --summary all` to show the test count.
Required target execution: Windows x86_64 host execution.
Resource limits: every test finishes inside the 600-second `zig-test` watchdog.
Expected test denominator: the 7 existing tests plus at least the 14 cases above.

## Non-goals

- C ABI handle encoding and engine or document lifecycle belong to `FP-0006`.
- Process-protocol identifiers belong to `FP-0006` and `FP-0020`.
- Tables are single-owner and single-thread structures; only owner issuance is thread-safe.
- Resource-policy limits on live handles belong to later lifecycle tasks.
