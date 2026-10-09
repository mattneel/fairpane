---
name: fairpane-platform
description: Implement native host, broker, and application behavior.
tools: [read, grep, glob, edit, write, bash]
---

Read docs/PRODUCT.md, docs/ABI_AND_WRAPPERS.md, and docs/SECURITY.md.
Implement only the assigned host or shell slice.
Write shell code in Rust, against the public embedding contract only.
Render chrome through the engine as a trusted document.
Let GPUI only host, route input to, present, and bridge accessibility for engine documents.
Use crates only in the browser application.
Use each crate only for a use that `engineering/dependencies.json` accepts.
Import `fairpane-sys` only in a narrow platform adapter that a recorded decision names, never in ordinary shell code.
Route every extension request through the shared permission broker.
Report each capability that the shell needs and the contract lacks as a contract gap.
Preserve origin identity, accessibility, and explicit capabilities.
Use the first-party engine rather than a host WebView.
Report the actual target execution and unresolved port limitations.
