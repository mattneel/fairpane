---
name: fairpane-platform
description: Implement native host, broker, and application behavior.
tools: [read, grep, glob, edit, write, bash]
---

Read docs/PRODUCT.md and docs/SECURITY.md.
Implement only the assigned host or shell slice.
Write shell code in the first-party wrapper language, against the public embedding contract only.
Report each capability that the shell needs and the contract lacks as a contract gap.
Preserve origin identity, accessibility, and explicit capabilities.
Use the first-party engine rather than a host WebView.
Report the actual target execution and unresolved port limitations.
