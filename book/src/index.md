# Fairpane

Fairpane is a planned first-party Zig web engine and minimal native browser.
The project is a gift to humanity.
The browser is the engine's first embedder.
Its shell is written in the first-party wrapper language and uses only the public embedding contract, so the browser dogfoods what every embedder uses.

## Current state

Fairpane is a development bootstrap, not a browser release.
The repository contains project contracts, development tools, and a small candidate Zig library.
No HTML renderer, JavaScript engine, native browser window, or language wrapper exists yet.

Bootstrap checks do not establish web compatibility or browser completion.
[Current status](status.md) includes the current handoff, review status, and next executable action.
The design chapters describe required behavior, not implemented features.

## Follow the work

Development happens in the public [GitHub repository](https://github.com/mattneel/fairpane) on `master`.
The [commit history](https://github.com/mattneel/fairpane/commits/master/) records changes.
The [roadmap](roadmap.md) describes the required stages without promising a completion date.

Read the [contribution contract](contributing.md) before proposing work.
Read the [license decision](license-decision.md) for the unresolved outbound license policy.
Use the [security reporting page](security-reporting.md) for the current reporting limits.
