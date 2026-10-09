# ADR 0004: Rust as the first-party wrapper language

Status: accepted.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0017`, `FP-0021`, `FP-0023`, `FP-0029`, `FP-0030`.

## Context

The browser shell is written in the first-party wrapper language and reaches the engine only through the public embedding contract.
That contract is the versioned C ABI, the process protocol, and the WebAssembly embedding for Wasm hosts.
The shell therefore dogfoods the same contract that every other embedder uses.
The language determines how the wrapper expresses ownership, queued host requests, threads, and native platform integration.

## Alternatives

`engineering/evidence/wrapper-language/research-report.md` compares fourteen candidates with cited primary sources.
Its scores are assessments, not measurements, and no candidate wrapper was built.

| Rank | Language | Main strength | Main risk |
| --- | --- | --- | --- |
| 1 | Rust | Safe foreign-owner model, thread-safety markers, low runtime weight, and native Windows bindings without a WebView. | A narrow unsafe perimeter and platform adapters need sustained review. |
| 2 | C++ | The most direct native platform reach and RAII owners. | No language-level protection against lifetime and race defects in the privileged host. |
| 3 | C# with .NET NativeAOT | Managed ownership, tasks, and cancellation for a Windows-first host. | Retained GC and runtime machinery, and WPF or Windows Forms do not qualify under NativeAOT. |
| 4 | Swift | ARC, actors, and direct AppKit integration. | Windows and Linux adapters and runtime packaging need deliberate work. |
| 5 | Go | Strong queued-host and cancellation idioms. | Cgo pointer rules, thread affinity, a GC, and weaker native UI reach. |

The research ranked native trusted chrome first and engine-rendered chrome as a stronger dogfooding option with a longer dependency path.

## Decision

Rust is the first-party wrapper language, and the browser shell is written in Rust.
The owner chose Rust because the browser needs as much memory safety as it can get.
Zig builds the engine, and Rust builds the application on top of it.

The Rust wrapper and the browser shell embrace the Rust ecosystem.
They use well-chosen crates for responsibilities outside the engine.
They prefer the current stable release of the best-maintained crate for each responsibility.
The engine keeps its rule of first-party Zig with no third-party runtime dependency.

Fairpane renders all browser chrome.
The chrome is a trusted document that the shell renders through the same public embedding contract as page content.

The owner's words:

> I'm good with Rust. I think it'd be a flex of using both of the best modern system's programming languages together. A browser needs as much memory safety as it can get. And because I said iodmatic wrappers, that means I'm decreeing a small exception to the no 3rd party deps thing for the Rust wrapper and the browser itself. In Rust you want to embrace the ecosystem, so a tasteful use of crates to handle things explicitly outside of the Zig core's responsibility is completely fine. Use the latest and greatest of the best of the best crates we can find. No problem there. Codify it all in the docs now please.

For the chrome, the owner selected "Fully engine-rendered chrome".
The quotations preserve the owner's original wording and spelling.

## Crate boundary

Crates can provide these responsibilities:

- Windowing, the OS event loop, and monitor and DPI information.
- Keyboard, pointer, touch, and IME event delivery from the OS.
- Bridging an accessibility tree to UI Automation, NSAccessibility, and AT-SPI.
- Presentation of engine frames to the window.
- Process spawning, IPC transport, and sandbox setup that the broker design assigns to the host.
- Clipboard transport, file dialogs, notifications, and external-link handoff under explicit host policy.
- Configuration, profile directories, logging, crash reporting, command-line parsing, error types, serialization of host messages, async execution, and tests.

Crates never provide these responsibilities, which belong to the engine:

- Parsing, styling, layout, painting, or text shaping of web content or chrome.
- JavaScript or WebAssembly execution.
- A WebView or any embedded browser engine.
- URL parsing, origin computation, or any security decision that the engine owns.
- Web-visible network semantics, such as HTTP, cookies, caching, or CORS.

`engineering/dependencies.json` records this boundary.
Each crate addition or upgrade passes a pinned lockfile, a license check, an advisory check, and review.

## Consequences

`FP-0029` pins the Rust toolchain and builds the raw and idiomatic wrapper crates.
`FP-0017` opens the first Rust window and renders the chrome document through the wrapper.
Because the engine renders the chrome, the first window waits for engine layout and paint in `FP-0016`.
`FP-0030` adds the editing, IME, focus, and accessibility that the chrome needs through the public contract.
The engine's editing, input, and accessibility work therefore serves the chrome before it serves web pages.
Every capability that the chrome needs becomes a public contract capability for every embedder.

The chrome and page content never share an authority boundary.
The chrome runs in its own engine document and owner, and process isolation remains the default direction.
Broker-validated state supplies the displayed origin.
A page cannot navigate, script, restyle, or overlay the chrome.
If the chrome renderer fails, the OS window frame keeps its title and close control, and the shell restarts the chrome.

## Reversal condition

A recorded measurement or qualification failure that Rust cannot address within the public contract.
A recorded chrome failure mode that engine rendering cannot contain.

## Sources and evidence

- `engineering/evidence/wrapper-language/research-report.md`
- `engineering/evidence/wrapper-language/research-output.json`
- `engineering/evidence/wrapper-language/research-attribution.log`
