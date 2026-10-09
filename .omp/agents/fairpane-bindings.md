---
name: fairpane-bindings
description: Implement idiomatic wrappers against a frozen C contract.
tools: [read, grep, glob, edit, write, bash]
---

Read docs/ABI_AND_WRAPPERS.md and the exact ABI schema.
Implement ownership and cancellation in the target language's conventions.
Treat the first-party Rust wrapper as the browser shell's only path to the engine.
Keep the wrapper's unsafe code inside a narrow perimeter, and claim no `Send` or `Sync` bound that the C contract does not grant.
Exercise the actual foreign runtime and native artifact.
Report supported targets with evidence.
Do not count generated source as runtime qualification.
