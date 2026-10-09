# ADR 0004: Rust for the wrapper and the browser shell

Status: accepted by the owner; this revision awaits an accepting independent review.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0017`, `FP-0020`, `FP-0021`, `FP-0023`, `FP-0029`, `FP-0030`, `FP-0032`, `FP-0033`, `FP-0034`, `FP-0035`.

## Decision

> **Rust is Fairpane's first-party wrapper language and browser-shell language.**
>
> The browser shell consumes the public engine contract through the idiomatic Rust wrapper. It has no private engine interface.
>
> The shell welcomes qualified third-party dependencies. The Zig engine and canonical language wrappers retain their first-party dependency policy.
>
> Shell dependencies cannot substitute for required engine behavior. Framework-specific integrations remain outside the canonical wrapper.
>
> Application requirements expose gaps in the public contract. Reviewed improvements serve every embedder, not only Fairpane's browser.

The quoted statement is the owner's wording for this record.
Zig gives Fairpane an independent engine.
Rust gives it an ecosystem-native application.
The public contract makes each one accountable to the other.

The owner's first answer extended the dependency exception to the Rust wrapper.
The owner's memo then placed the exception at the browser application, and this record follows the memo.

Fairpane renders all browser chrome as a trusted document.
GPUI hosts that engine-rendered chrome and the page documents in the shell's windows.

## Layers and dependency policy

| Layer | Dependency policy | Responsibility |
| --- | --- | --- |
| Zig engine | First-party code and the pinned Zig toolchain. | Web semantics and document execution. |
| `fairpane-sys` | First-party bindings and Rust toolchain facilities. | Exact declarations of the public C ABI. |
| `fairpane` | First-party wrapper code, `fairpane-sys`, and the Rust standard library. | Safe, idiomatic Rust ownership and operations. |
| Rust browser application | Qualified third-party dependencies are welcome. | It provides the shell's user interface and application services. |

The crate names describe the structure, not reserved package names.
Dependencies belong to the application that needs them.
They do not migrate into the reusable contract.
A GPUI integration therefore belongs to the browser application, not to an optional feature of the canonical wrapper.
Another Rust embedder stays free to choose a different interface framework, or none.

The boundary concerns behavior, not only linkage.

| Acceptable shell use | Outside the exception |
| --- | --- |
| A UI framework hosts windows, routes input and IME events, and presents engine-produced frames. | The engine delegates page or chrome layout, text shaping, or painting to that framework. |
| A graphics library presents an engine-produced frame. | A Rust renderer supplies missing page-rendering behavior behind a callback. |
| An HTTP library supplies authorized transport. | Its defaults silently replace the engine's Fetch semantics. |
| An accessibility adapter exposes platform objects. | The shell reconstructs page semantics from pixels. |

The memo's first example let a toolkit shape text in the address bar.
The owner's later selection, "GPUI hosts engine-rendered chrome", replaces that example with the first row above.

## The canonical wrapper

The wrapper does more than translate function names.
FFI declarations do not establish foreign-code safety, so their correctness is part of the wrapper's safety contract.

- `fairpane` exposes owned engine and document types with explicit destruction behavior.
- It reports typed errors through `Result`, without a mandatory error-library dependency.
- It provides scoped buffer views and retained frames with documented lifetime rules.
- It accepts typed input and host-request batches.
- It states thread restrictions and cancellation behavior explicitly.
- Ordinary shell code never handles raw engine pointers and never imports `fairpane-sys` directly.
- Unsafe code stays inside the wrapper and narrow platform adapters.

A narrow platform adapter is a shell module that a recorded decision names.
It may handle raw engine pointers only for an interoperation that the wrapper cannot yet express safely.
Each such use also becomes a wrapper task, so the safe interface eventually absorbs it.
Every other shell module is ordinary shell code.

The initial `Engine` type implements neither `Send` nor `Sync`.
Those traits are safety claims, and a mutex around a foreign handle does not establish the library's thread contract.
A qualified design can later permit specific transfers.
The browser communicates with the engine owner through messages, so the wrapper needs no async runtime.

The frame contract separates CPU access from presentation ownership.
A borrowed CPU view expires at its documented boundary.
An asynchronous presentation operation retains the resource until its consumer completes.
A Rust scope ending does not establish GPU completion, so the presentation adapter follows an explicit release protocol.

The distributed wrapper carries no third-party build dependency either.
A consumer needs neither bindgen nor any GUI stack to build it.
Generated declarations ship with their source schema, and regeneration is a separate development operation.
The wrapper implements standard-library traits and leaves ecosystem adapters to applications.

## The shell stack

GPUI is the lead interface framework for the shell, with selected GPUI Kit facilities.
GPUI hosts windows, input, IME delivery, accessibility through AccessKit, and presentation of engine frames.
It does not render the chrome; Fairpane renders the chrome as a trusted document.
GPUI's documentation describes AccessKit integration, and custom controls still require correct semantics and keyboard behavior.

A qualification prototype selects the framework through Fairpane's actual needs.

| Area | Required evidence |
| --- | --- |
| Engine frames | The shell displays changing pixels obtained through the Rust wrapper. |
| Presentation | Resize and scale changes preserve correct viewport geometry and resource lifetimes. |
| Text input | IME composition works in the engine-rendered address bar and in an engine-owned page field. |
| Accessibility | Focus and actions cross the chrome and page boundary correctly. |
| Application behavior | Multiple windows keep distinct identity and recover after a renderer failure. |
| Efficiency | Idle CPU use and interaction latency meet explicit budgets. |

`FP-0032` produces the evidence for engine frames, presentation, window identity, and efficiency, and it confirms IME event delivery.
The text input and accessibility areas need engine editing and accessibility, so `FP-0030` produces their evidence.
Renderer-failure recovery needs renderer processes, so `FP-0020` produces that part of the application behavior evidence.
The GPUI selection stays provisional until all three tasks pass.

The first frame path uploads already-decoded software frames through GPUI's `RenderImage` input.
That path does not establish zero-copy GPU interoperability.
Shared textures need a separate experiment with explicit ownership and synchronization contracts.
An accessibility-tree assertion does not prove screen-reader behavior.

GPUI is pre-1.0, and GPUI Kit pairs each release with a specific GPUI snapshot.
GPUI Kit documented version 0.7.1 on October 9, 2026, and it warns against independent snapshot upgrades.
The shell adopts the newest qualified, compatible stack, not the independently newest version of every package.
It adds no other window framework or graphics abstraction without a concrete role.
The GPUI Kit WebView and JavaScript-extension packages are not part of the shell.
A check of the resolved dependency graph enforces that exclusion.

The following crates are candidates for their stated roles, not a preapproved manifest.

| Concern | Candidate | Boundary |
| --- | --- | --- |
| Asynchronous host services | Tokio | A host-service runtime, not the engine's event loop or a wrapper requirement. |
| HTTP transport and TLS | reqwest with rustls | A transport adapter under the resource broker's control. |
| Structured diagnostics | tracing | Shell spans correlated with engine requests and frames. |
| Dependency policy | cargo-deny | Development checks for licenses, advisories, and approved dependency sources. |

The transport adapter never consumes a redirect that the engine needs to evaluate.
It returns redirect responses through the public resource contract.
The same principle applies to cookie policy and response transformations.
Application convenience never overrides observable web behavior.
The engine applies web semantics, and the broker independently authorizes privileged operations.

## Process arrangement

The production browser isolates renderers in separate processes.
The Rust wrapper runs inside each renderer process.
A small Rust renderer host calls the wrapper and services the process protocol.
The privileged browser application communicates with renderer hosts through validated messages.
The C ABI stays a local boundary inside the renderer process, and no native pointer crosses a process boundary.
A direct in-process example remains valuable for library consumers, and it qualifies a separate deployment profile.

Fairpane adds one design choice beyond the memo.
The trusted chrome document runs in its own renderer, separate from every page renderer.
A compromised page renderer then cannot reach the chrome's authority.
This choice continues the default direction that `docs/SECURITY.md` recorded before this decision.

## Independence as a build result

Continuous integration builds three separate consumers.

1. A C-only consumer builds against the public header and engine artifact.
2. A minimal Rust consumer builds against the distributed wrapper outside the browser workspace.
3. The browser shell executes application workflows through the same wrapper.

The separate Rust consumer matters because Cargo unifies dependency features in defined circumstances.
A workspace build can therefore exercise a different configuration from an independent consumer.
The dependency check covers every declared target configuration and every build dependency.
A shell-only workaround cannot satisfy a wrapper test, and a private export cannot satisfy a public-ABI test.

## Toolchain

The initial Rust pin is stable 1.99.0, released on October 1, 2026.
Zig master keeps its own exact pin.
Rust nightly needs a specific feature and its own qualification case.
The shell commits its `Cargo.lock` and upgrades dependencies through reviewed changes.
The shell tracks its own resource costs, including measured idle behavior.

## Alternatives

`engineering/evidence/wrapper-language/research-report.md` compared fourteen candidate languages with cited sources.
It ranked Rust first, then C++, C# with NativeAOT, Swift, and Go.
TypeScript on Node or Bun was ineligible because the shell would carry V8 or JavaScriptCore.

## Consequences

`FP-0029` builds and qualifies `fairpane-sys` and `fairpane`.
`FP-0035` exposes frames and input, including IME composition, through the public contract.
`FP-0032` qualifies GPUI through the prototype evidence above.
`FP-0017` opens the first Rust window, hosted in GPUI, with engine-rendered chrome.
`FP-0030` adds the editing, IME, focus, and accessibility that the chrome needs through the public contract.
`FP-0020` runs renderers as Rust renderer hosts behind the broker and the process protocol.
`FP-0033` runs the repository gates in continuous integration.
`FP-0034` builds the three consumers in continuous integration.

## Reversal condition

A recorded measurement or qualification failure that Rust cannot address within the public contract reopens this decision.
A recorded GPUI prototype failure leads to another framework through the same qualification, without changing the wrapper.

## Sources and evidence

- `engineering/evidence/wrapper-language/owner-memo-2026-10-09.md` holds the owner's design memo verbatim.
- `engineering/evidence/wrapper-language/owner-answers.log` holds the owner's recorded answers.
- `engineering/evidence/wrapper-language/research-report.md` holds the language comparison.
- The Rust 1.99.0 release announcement: <https://blog.rust-lang.org/2026/10/01/Rust-1.99.0/>.
