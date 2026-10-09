# Embedding and language contracts

## Current status

`api/bootstrap.json` describes a tiny experimental capability probe.
ABI revision zero has no stability promise.
The probe reports no browser capabilities.
It exists to test compilation, headers, symbol export, and foreign calls.

The complete embedding ABI is not frozen by this bootstrap.
The lifecycle task replaces the experiment with a reviewed versioned contract.

## Public boundary

The eventual C ABI uses opaque owners and checked handles.
It avoids Zig slices, error unions, C bitfields, and variadic calls.
Every buffer states its length unit and lifetime.
Every allocation states which party releases it.

Public structures carry size and version fields where appropriate.
Fixed-width integers carry statuses and flags.
Target-sized lengths use the declared target ABI.
Zig extern structures follow the target C ABI. [S05]

Recoverable failures return structured status.
Internal invariant failures follow a documented fail-stop policy.
No exception or unwinding crosses the public C boundary.
The in-process embedding profile accepts process-level failure risk.

Foreign callbacks cannot reenter mutable engine operations unless the contract explicitly permits that path.
Queued host requests are the default integration model.
Batch operations avoid a foreign call for every glyph or box.

## Process and WebAssembly boundaries

The process protocol has an independent version and encoding.
It contains no native pointers and validates every length.
A native C layout is not a portable wire format.

WebAssembly bindings use validated memory offsets and handles.
Their memory-growth rules and view lifetimes remain explicit.
A cross-compile alone does not qualify that runtime.

## Wrapper design

| Target | Public idiom |
| --- | --- |
| Zig | Explicit allocators and error unions over native internal interfaces. |
| C | Explicit owner handles, statuses, and release operations. |
| C++ | Move-only resource owners and scoped frame views. |
| Rust | Ownership types, Result, and explicit thread restrictions. |
| TypeScript | Explicit disposal, asynchronous operations, and separate native and Wasm transports. |
| Elixir and Erlang | Supervised process ownership and message-based operations. |
| Python | Context managers and runtime-appropriate asynchronous integration. |
| Go | Explicit Close and context-based cancellation. |
| Swift | Actor-owned engine state and scoped native lifetimes. |
| Java and Kotlin | Managed resource owners over a qualified native adapter. |
| .NET | Safe native ownership and task-based asynchronous operations. |
| Other languages | A published adapter protocol and the same qualification suite. |

A generator supplies raw bindings and ownership metadata.
A language-specific layer supplies idiomatic behavior.
Generated source alone does not qualify a wrapper.

The initial Elixir path favors an external renderer process.
A NIF crash can affect the entire Erlang VM. [S17]
A future NIF path requires bounded scheduler work and explicit lifetime tests.
Node native adapters can use Node-API rather than expose V8 internals. [S18]

## First-party Rust wrapper

Rust is the first-party wrapper language and the browser-shell language, as ADR 0004 records.
The project maintains the Rust wrapper with the engine and qualifies it before any other wrapper.
The browser shell is written in Rust, so Fairpane's own application is the wrapper's first and heaviest user.
Zig builds the engine, and Rust builds the application on top of it.

The shell reaches the engine only through the Rust wrapper and the public embedding contract.
It never calls internal Zig interfaces.

The public embedding contract is the versioned C ABI, the process protocol, and the WebAssembly embedding for Wasm hosts.
The direct Zig API is not part of that contract, because it sits over internal interfaces.

When the shell needs a capability that the contract lacks, the contract gains that capability through the normal review path.
Other embedders then receive the same capability.

The wrapper has two crates.
`fairpane-sys` holds the exact declarations of the public C ABI, generated from the interface schema.
`fairpane` provides safe, idiomatic ownership and operations over `fairpane-sys` and the Rust standard library.

- `fairpane` exposes owned engine and document types with explicit destruction behavior.
- It reports typed errors through `Result`, without a mandatory error-library dependency.
- It provides scoped buffer views and retained frames with documented lifetime rules.
- It accepts typed input and host-request batches.
- It states thread restrictions and cancellation behavior explicitly.
- It claims no `Send` or `Sync` bound that the C contract does not grant.
- The initial `Engine` type implements neither `Send` nor `Sync`, and a later transfer needs a qualified design.
- Its unsafe code stays inside a narrow, separately reviewed perimeter.

A borrowed CPU frame view expires at its documented boundary.
An asynchronous presentation operation retains the frame resource until its consumer completes.
A scope ending does not establish GPU completion, so presentation follows an explicit release protocol.

The canonical wrapper keeps a first-party dependency policy.
It has no third-party runtime or build dependency, so a consumer needs neither bindgen nor any GUI stack.
Generated declarations ship with their source schema, and regeneration is a separate development operation.
The wrapper implements standard-library traits and needs no async runtime.
Framework-specific integrations, such as GPUI adapters, belong to the applications that use them.

The browser application, not the wrapper, welcomes qualified third-party crates.
Ordinary shell code never handles raw engine pointers and never imports `fairpane-sys` directly.
`engineering/dependencies.json` lists the application's acceptable uses, exclusions, and required checks.

## Language support packages

Every officially supported language SDK powers a maintained first-party Fairpane integration and a useful reference extension, as ADR 0006 records.
Each language therefore delivers the idiomatic SDK, a language-support extension, and a reference extension.
Those consumers build against the same distributed SDK and public contracts that everyone else receives.
The engine embedding API and the permissioned extension API remain distinct.
An extension never receives unrestricted engine access through its language SDK.
`docs/EXTENSIONS.md` describes the extension contract and the qualification of each support package.

## Qualification

The wrapper suite covers cancellation, stale handles, teardown, and allocation failure.
It also covers foreign exceptions and callbacks from unexpected threads.

Continuous integration builds three separate consumers.
A C-only consumer builds against the public header and engine artifact.
A minimal Rust consumer builds against the distributed wrapper outside the browser workspace.
Cargo unifies dependency features in defined circumstances, so a workspace build can hide a wrapper defect.
The browser shell executes its application workflows through the same wrapper.
The dependency check covers every declared target configuration and every build dependency.
A language qualifies only after its SDK, its language integration, its reference extension, and an independent example pass their checks.
Each supported language requires real execution on its declared runtime and targets.
The phrase "every language" expresses an extensible public contract, not an unsupported list of generated files.
