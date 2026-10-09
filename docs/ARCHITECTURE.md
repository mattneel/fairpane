# Engine architecture

## Dependency boundary

The portable engine contains first-party Zig source and the pinned Zig standard library.
Compiler-generated runtime support belongs to the toolchain inventory.
The portable engine requires no third-party runtime library.

Versioned standards data is not executable dependency concealment.
Every imported dataset needs provenance, license metadata, and a reproducible generator.
Development harnesses and reference engines stay outside the shipped renderer.

The host supplies explicit platform capabilities.
Adapters declare operating-system calls, system libraries, and security assumptions.
A callback that secretly delegates shaping or rendering to another engine violates the canonical zero-dependency profile.

The Rust wrapper and the browser shell sit outside the portable engine.
They can use pinned, audited crates for responsibilities outside the engine, such as windowing, OS input delivery, accessibility bridging, frame presentation, and IPC transport.
No crate parses, styles, lays out, paints, or scripts web content or chrome, and no crate makes a security decision that the engine owns.
`engineering/dependencies.json` records the allowed and forbidden crate responsibilities.

## Components

```text
Rust browser shell: windows, OS input, accessibility bridge, frame presentation
                  |
     Rust wrapper -> public embedding contract (C ABI and process protocol)
                  |
                  v
Host capabilities and resource broker
                  |
                  v
Document execution: parser, DOM, CSSOM, JS, tasks
                  |
                  v
Computed style -> box structure -> layout fragments
                                      |
                                      v
                              Immutable paint scene
                                /             \
                         software raster     GPU adapter
                                \             /
                                  host frame
```

The accessibility tree follows document semantics and explicit geometry references.
Hit tests and selection share the same geometric decisions as paint.
The compositor does not traverse mutable DOM objects.

## Application boundary

The browser shell is an ordinary embedder.
It is written in Rust and calls the engine through the Rust wrapper and the public embedding contract.
It has no access to internal Zig interfaces.
A capability that the shell needs becomes part of the public contract, or the shell does not have it.
The engine never depends on the shell.

The engine renders the browser chrome as a trusted document through the same contract.
The shell hosts the chrome document and each page document under separate engine owners.
It routes OS input to the focused document, presents each document's frames, and bridges each accessibility tree to the platform.
The chrome and page documents never share an authority boundary, and broker-validated state supplies the displayed origin.

## Execution model

A document execution context has one owner for script-visible mutation.
Workers return explicit results instead of mutating that state concurrently.
The host owns its application event loop.
A bounded engine step reports pending work, host requests, and the next deadline.

Internal execution budgets do not create arbitrary script-visible task boundaries.
The implementation preserves HTML task and microtask semantics. [S09]
A replay transcript records host inputs for tests.
Production entropy remains secure and nondeterministic.

## Resource boundary

The engine owns web-visible Fetch behavior and origin semantics.
A privileged broker independently authorizes network, filesystem, and platform operations.
A URL-to-bytes callback alone cannot represent the complete Fetch contract. [S10]

Requests carry identifiers and explicit metadata.
The engine validates response association and cancellation state.
The protocol limits message size and resource use.
It contains no native pointers.

## Representation boundaries

- DOM objects preserve identity and document semantics.
- Computed styles preserve cascade results and dependencies.
- Box structures represent formatting relationships.
- Fragments represent positioned and split output.
- Paint scenes contain ordered visual operations and retained resources.
- Accessibility objects expose semantic relationships and actionable state.

A DOM node is not necessarily one box or one fragment.
CSS display rules define anonymous boxes and cases without a principal box. [S11]

## Module rules

The initial source tree stays small until real implementations need more files.
New modules follow explicit dependency direction.
The DOM cannot depend on a platform window implementation.
The JavaScript runtime and DOM use internal Zig interfaces, not the public C ABI.

Shared low-level utilities require at least one real consumer.
A second standard library is not a substitute for narrow compiler-sensitive adapters.
The design favors replaceable internals over speculative abstraction layers.
