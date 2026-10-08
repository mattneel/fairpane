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

## Components

```text
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
