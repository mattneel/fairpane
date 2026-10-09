**Yes. This makes the separation more useful: the Zig engine owns web behavior, the Rust wrapper owns safe integration, and the Rust shell owns the application.**

The shell becomes a demanding customer of the public API. An awkward API now hurts Fairpane itself, not only external embedders.

Your dependency exception also belongs at the right boundary. The browser application can embrace the Rust ecosystem without imposing that ecosystem on every engine consumer.

The current repository already requires an ordinary-embedder shell, but its wrapper document still leaves the language unresolved. Your decision resolves that choice. 

## 1. The revised dependency contract

I propose this explicit division:

| Layer | Dependency policy | Responsibility |
|---|---|---|
| **Zig engine** | First-party code and the pinned Zig toolchain. | Web semantics and document execution. |
| **`fairpane-sys`** | First-party bindings and Rust toolchain facilities. | Exact declarations of the public C ABI. |
| **`fairpane`** | First-party wrapper code, `fairpane-sys`, and the Rust standard library. | Safe, idiomatic Rust ownership and operations. |
| **Rust browser shell** | Qualified third-party dependencies are welcome. | User interface and application services. |

Those crate names describe the proposed structure, not reserved package names.

**Dependencies belong to the application that needs them. They do not migrate into the reusable contract.**

For example, a GPUI integration belongs under the browser application. It does not become an optional GPUI feature inside the canonical wrapper.

That leaves another Rust embedder free to choose a different interface framework. It also leaves a headless embedder free to choose none.

The distinction concerns behavior, not only linkage:

| Acceptable shell use | Outside the exception |
|---|---|
| A toolkit shapes text in the address bar. | The engine delegates webpage text layout to that toolkit. |
| A graphics library presents an engine-produced frame. | A Rust renderer supplies missing page-rendering behavior behind a callback. |
| An HTTP library supplies authorized transport. | Its defaults silently replace the engine’s Fetch semantics. |
| An accessibility adapter exposes platform objects. | The shell reconstructs page semantics from pixels. |

This preserves the existing engine boundary while allowing a substantially better application. 

## 2. Make the Rust wrapper genuinely idiomatic

The wrapper must do more than translate function names.

Rust’s FFI declarations do not establish foreign-code safety automatically. Their correctness remains part of the wrapper’s safety contract. [Rust Documentation](https://doc.rust-lang.org/nomicon/ffi.html)

My proposed wrapper exposes:

- Owned engine and document types, with explicit destruction behavior.
- Typed errors through `Result`, without a mandatory error-library dependency.
- Scoped buffer views and retained frames, with documented lifetime rules.
- Typed input and host-request batches.
- Explicit thread restrictions and cancellation behavior.

The ordinary shell code never handles raw engine pointers. It also never imports `fairpane-sys` directly.

Unsafe implementation code remains concentrated in the wrapper and narrow platform adapters. The application exercises the safe interface that other Rust consumers receive.

### Thread ownership stays explicit

My initial `Engine` type does not implement `Send` or `Sync`. A qualified design can later permit specific transfers.

Rust treats implementations of those traits as safety claims. A mutex around a foreign handle does not establish the foreign library’s thread contract. [Rust Documentation](https://doc.rust-lang.org/nomicon/send-and-sync.html)

The browser can communicate with the engine owner through messages. That arrangement does not require the wrapper to depend on Tokio.

### Frame ownership needs more than `Drop`

My frame contract distinguishes CPU access from presentation ownership.

A borrowed CPU view expires at its documented boundary. An asynchronous presentation operation retains the underlying resource until its consumer completes.

A Rust scope ending does not itself establish GPU completion. The presentation adapter must honor an explicit release protocol.

This is exactly the kind of requirement that the browser will expose through daily use.

### No convenience dependencies inside the wrapper

I keep third-party build dependencies out of the distributed wrapper too. A consumer does not need bindgen or a particular GUI stack to build it.

Generated declarations ship with their source schema. Regeneration remains a separate development operation.

The wrapper can provide standard-library traits without dependency-specific integrations. The shell can adapt those traits to its chosen ecosystem.

## 3. My lead UI candidate is GPUI

**For the application experience you described, GPUI is my first prototype choice.**

GPUI supplies a GPU-accelerated interface framework with a hybrid immediate and retained model. It is the framework behind Zed. That makes it relevant to your application-workspace direction. [GPUI](https://gpui.rs/?utm_source=chatgpt.com)

GPUI’s current documentation also describes AccessKit integration. Custom controls still require correct semantics and keyboard behavior. [gpui.rs](https://gpui.rs/examples/?utm_source=chatgpt.com)

I propose **GPUI with selected GPUI Kit facilities**, not an automatic adoption of every component.

GPUI Kit separates its reusable behavior layer from styled components. Its documentation also describes native interaction tests. Those facilities address real shell work beyond the first window. [GPUI Kit](https://gpui-kit.com/docs/)

### Select the framework through Fairpane’s actual needs

My qualification prototype includes these tests:

| Area | Required evidence |
|---|---|
| **Engine frames** | The shell displays changing pixels obtained through the Rust wrapper. |
| **Presentation** | Resize and scale changes preserve correct viewport geometry and resource lifetimes. |
| **Text input** | IME composition works in both the address bar and an engine-owned page field. |
| **Accessibility** | Focus and actions cross the chrome/page boundary correctly. |
| **Application behavior** | Multiple windows retain distinct identity and recover after a renderer failure. |
| **Efficiency** | Idle CPU use and interaction latency meet explicit budgets. |

GPUI Kit documents an input path for already-decoded frames through `RenderImage`. That supports an initial software-frame experiment. It does not establish zero-copy GPU interoperability. [GPUI Kit](https://gpui-kit.com/docs/image)

The accelerated path needs a separate experiment. Shared textures require explicit ownership and synchronization contracts.

Likewise, an accessibility-tree assertion does not prove screen-reader behavior. GPUI Kit’s own accessibility guide makes that distinction. [GPUI Kit](https://gpui-kit.com/docs/accessibility)

### Adopt a compatible stack, not unrelated maximum versions

GPUI remains pre-1.0, and its documentation warns about breaking changes. [GitHub](https://github.com/zed-industries/zed/blob/main/crates/gpui/README.md?utm_source=chatgpt.com)

GPUI Kit currently documents version **0.7.1**. It pairs that release with a specific GPUI snapshot and warns against independent snapshot upgrades. [GPUI Kit](https://gpui-kit.com/docs/installation)

That is the right interpretation of “latest and greatest”:

> **The newest qualified, compatible stack—not the independently newest version of every package.**

I do not add another window framework or graphics abstraction merely because it is popular. Each additional layer needs a concrete role.

The broader GPUI Kit workspace also contains WebView and JavaScript-extension packages. Those packages are not part of my proposed Fairpane shell. 

The resolved application graph needs an explicit exclusion check. A toolkit’s optional capabilities do not change Fairpane’s first-party engine commitment.

## 4. Embrace the ecosystem for real application services

Beyond the interface framework, these are my initial candidates:

| Concern | Candidate | Proposed boundary |
|---|---|---|
| **Asynchronous host services** | **Tokio** | A host-service runtime, not the engine’s event loop or a wrapper requirement. |
| **HTTP transport and TLS** | **reqwest with rustls** | A transport adapter under the resource broker’s control. |
| **Structured diagnostics** | **tracing** | Shell spans correlated with engine requests and frames. |
| **Dependency policy** | **cargo-deny** | Development checks for advisories and approved dependency sources. |

Tokio provides configurable runtime services for asynchronous I/O and tasks. Reqwest exposes a rustls TLS option. [Docs.rs](https://docs.rs/tokio/latest/tokio/runtime/index.html)

`tracing` supplies structured events and spans. `cargo-deny` supports dependency-graph policy checks, including licenses and advisories. [Docs.rs](https://docs.rs/tracing/latest/tracing/)

These are candidates for their stated roles, not a preapproved dependency manifest.

### Network defaults need deliberate control

Reqwest follows HTTP redirects by default. It exposes a redirect policy that can change that behavior. [Docs.rs](https://docs.rs/reqwest/latest/reqwest/redirect/index.html)

For Fairpane, the transport cannot silently consume redirects that the engine needs to evaluate.

My adapter returns those responses through the public resource contract. The engine applies web semantics, and the broker independently authorizes privileged operations.

That matches the repository’s existing separation between Fetch behavior and host transport. 

The same principle applies to cookie policy and response transformations. Application convenience does not override observable web behavior.

## 5. Keep the security boundary independent of the language boundary

The production browser can still use an isolated renderer process.

My proposed arrangement puts the Rust wrapper inside that renderer process. A small Rust renderer host calls the wrapper and services the process protocol.

The privileged browser application communicates through validated messages. The C ABI remains a local boundary inside the renderer process.

That arrangement still exercises the wrapper continuously. It does not pretend that a native pointer can cross a process boundary.

The repository already distinguishes the C ABI from the process protocol. The Rust shell decision does not require those contracts to merge. 

A direct, in-process example remains valuable for library consumers. It qualifies a different deployment profile.

## 6. Make independence a build result

I propose three separate consumers in continuous integration:

1. **A C-only consumer** builds against the public header and engine artifact.
2. **A minimal Rust consumer** builds against the distributed wrapper without the browser workspace.
3. **The browser shell** executes application workflows through that same wrapper.

The separate Rust consumer matters. Cargo unifies dependency features in defined circumstances, so a workspace build can exercise a different configuration from an independent consumer. [Rust Documentation](https://doc.rust-lang.org/cargo/reference/resolver.html)

The dependency check covers all declared target configurations. It also covers build dependencies, not only runtime packages.

A shell-only workaround cannot satisfy a wrapper test. A private export cannot satisfy a public-ABI test.

The result is measurable: another application can obtain the same engine capabilities without inheriting Fairpane’s GUI dependencies.

## 7. Use current Rust deliberately

As of October 8, 2026, the latest stable Rust release is **1.99.0**, released on October 1. [Rust Blog](https://blog.rust-lang.org/2026/10/01/Rust-1.99.0/)

My initial proposal pins that compiler for the shell. Zig master retains its separate exact pin.

Rust nightly is not necessary merely because Zig follows master. A nightly requirement needs a specific feature and qualification case.

The application commits its lockfile and upgrades dependencies through reviewed changes. Cargo’s lockfile records the resolved package versions for reproducible dependency selection. [Rust Documentation](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)

The shell also tracks its own resource costs. Minimal chrome needs measured idle behavior, not merely a small number of visible controls.

## The architectural statement

I propose this wording for the decision record:

> **Rust is Fairpane’s first-party wrapper language and browser-shell language.**
>
> The browser shell consumes the public engine contract through the idiomatic Rust wrapper. It has no private engine interface.
>
> The shell welcomes qualified third-party dependencies. The Zig engine and canonical language wrappers retain their first-party dependency policy.
>
> Shell dependencies cannot substitute for required engine behavior. Framework-specific integrations remain outside the canonical wrapper.
>
> Application requirements expose gaps in the public contract. Reviewed improvements serve every embedder, not only Fairpane’s browser.

That preserves the ambition without turning dependency minimalism into a restriction on the entire product.

**Zig gives Fairpane an independent engine. Rust gives it an ecosystem-native application. The public contract makes each one accountable to the other.**
