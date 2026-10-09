# Fairpane

**The whole web. Nothing in the way.**

Fairpane is an effort to build a complete, efficient browser and web engine as a gift to humanity.
The work belongs in the commons. Development happens in the open.
Completion follows demonstrated behavior, not a calendar, token budget, or convincing demonstration.
Maintenance and adoption are the intended steady state, not an afterthought.
Read the [public documentation](https://mattneel.github.io/fairpane/) for design contracts and current status.

## Repository status

This archive is a development bootstrap, not a browser release.
It contains the project contract, agent workflow, development tools, and a small candidate Zig library.
No HTML renderer, JavaScript engine, browser window, or language wrapper is implemented yet.
The candidate library exposes an experimental capability probe with zero browser capabilities.

The bootstrap checks do not establish web compatibility.
The release check deliberately fails until the qualification contract has evidence.
`engineering/BOOTSTRAP_VALIDATION.md` records the checks performed before this archive shipped.

## Start on Windows

1. Extract this archive into `C:\src\fairpane`.
2. Open a terminal in that directory.
3. Start `omp`.
4. Enter `/fairpane-start`.

The archive has no enclosing directory.
`AGENTS.md` sits directly at the repository root.
`AGENT_LAUNCH.md` supplies the same assignment when prompt discovery does not work.
`START_HERE.md` contains tool setup and diagnostic commands.

## Nonnegotiable direction

- A first-party, zero-third-party-runtime-dependency engine in Zig.
- Zig master, with an exact compiler pin and isolated upgrades.
- A first-party Zig-native JavaScript runtime with full observable JavaScript semantics.
- A C ABI at the embedding boundary, with qualified idiomatic wrappers across languages.
- One first-party wrapper language, maintained with the engine.
- A native browser with minimal chrome, an address bar, and the page.
- A browser shell written in the first-party wrapper language on the public embedding contract, so Fairpane's own browser dogfoods what every embedder uses.
- Open development, reproducible evidence, and maintainable public infrastructure.

The browser treats web applications as applications.
Minimal chrome does not remove security identity, accessibility, permissions, or diagnostics.
The engine does not hide Chromium, WebKit, or another renderer behind host callbacks.

## Map

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Standing instructions for every agent. |
| `AGENT_LAUNCH.md` | The first assignment and continuation rule. |
| `.omp/` | OMP prompts, specialists, and project settings. |
| `docs/` | Product, architecture, runtime, safety, and adoption contracts. |
| `engineering/` | Task graph, gates, qualification policy, and durable state. |
| `api/` | Experimental C surface and future ABI contract. |
| `src/` | Candidate first-party Zig source. |
| `tests/` | Bootstrap tests and first-party fixtures. |
| `tools/` | Dependency-free development tooling for Node or Bun. |
| `scripts/` | PowerShell and POSIX entry points. |
| `specs/` | External-source and corpus registries. |
| `toolchains/` | Exact Zig master artifact lock. |

## Boundaries

Node or Bun runs the development controller. Neither ships inside the portable engine.
OMP and external conformance harnesses are development tools, not renderer dependencies.
The portable engine uses the pinned Zig standard library and compiler runtime.
Host adapters can use declared operating-system facilities.

No domain, package namespace, or trademark is reserved by this archive.
The outbound license remains an owner decision before public distribution.
`LICENSE-DECISION.md` proposes Apache-2.0 without silently choosing the owner's legal policy.
Engineering can proceed while that decision remains open.

## Sources

`docs/SOURCES.md` records primary sources checked on October 8, 2026.
The compiler pin records the official artifact URLs and SHA-256 values.
The source registry is not a claim that complete standards snapshots exist in this archive.
