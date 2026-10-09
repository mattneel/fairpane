# Fairpane’s first wrapper and browser-shell language

## Recommendation and ranked top five

**Recommend Rust for the first first-party wrapper and browser shell, with native widgets for the initial trusted browser chrome.** The shell should be a genuine external consumer of Fairpane’s public C ABI, not a second front end to internal Zig modules.

The ranked shortlist is:

1. **Rust — best overall fit.** Its ownership model can represent opaque owners, borrowed frame views, and explicit thread restrictions particularly well. `Result`, destruction, and message passing fit statuses and queued host requests. Rust’s documented `Send`/`Sync` rules provide a useful guard against accidentally moving or sharing engine owners. C calls remain unsafe and require a reviewed wrapper; Rust does not make an incorrect foreign declaration safe. Exact toolchain selection and locked dependencies are straightforward. Microsoft provides native Windows bindings, including COM, without requiring a WebView. [R1–R5]
2. **C++ — strongest direct native-platform integration and low runtime weight.** Move-only RAII owners map naturally to the ABI. Win32/COM, GTK’s C interface, and a small Objective-C++ AppKit adapter provide a credible renderer-free desktop route. There is no required managed VM or tracing GC. The substantial disadvantage is that ownership conventions and thread affinity are not generally enforced by the language: use-after-free and data races remain possible in the privileged host. [C1–C4, P1–P7]
3. **C# with .NET NativeAOT — strongest managed alternative for Windows-first development.** Source-generated P/Invoke, explicit disposal, tasks, and cancellation provide good wrapper idioms. Source-generated COM can support an AOT-friendly Windows integration. NativeAOT removes the JIT and the requirement for an installed .NET runtime; it does **not** remove the shipped runtime machinery or managed GC. This recommendation is for direct native adapters, **not WPF or Windows Forms**: Microsoft documents their trimming incompatibilities, while NativeAOT requires trimming. Cocoa and Linux adapters need substantial first-party work. [N1–N7]
4. **Swift — excellent ownership/concurrency design and Apple integration, less balanced for Windows-first chrome.** C interoperability, ARC, actors, and scoped native lifetimes make a good wrapper. AppKit and Apple mobile integration are major strengths. Windows and Linux are supported Swift platforms, and official Swift Wasm SDKs now exist; “Swift is Apple-only” is not an accurate rejection. However, AppKit does not become a portable GUI framework, and Windows COM/input/accessibility integration remains a separate engineering obligation. [S1–S6]
5. **Go — good queued host and broker-oriented application language, weaker native UI integration.** Goroutines, channels, `Close`, and context cancellation suit asynchronous request ownership. Cgo provides the required C interface, with important restrictions on retained Go pointers. UI and engine thread affinity require an explicitly locked OS thread where the relevant platform/ABI contract demands it. Go adds a GC and scheduler and still needs native UI adapters; an easy networking story is not evidence of a complete IME/accessibility story. [G1–G5]

**[INFERENCE]** This ordering favors safe ownership, a maintainable renderer-free host, Windows-first practicality, and meaningful foreign-language dogfooding. It is not a popularity ranking or a benchmark result. C++ is second because native platform integration is a major part of this particular assignment; an owner who weights privileged-host memory safety more heavily could reasonably place NativeAOT or Swift ahead of it.

## Scope and non-negotiable boundaries

The repository remains at bootstrap: it has no renderer, JavaScript engine, or native browser window. The ABI is not yet a qualified stable browser API. This report chooses a direction; it does not claim that any candidate has executed Fairpane’s lifecycle or browser qualification suite. [F1, F4]

The owner’s shell decision adds an important constraint beyond the existing generic wrapper table: **even a Zig shell must consume the public C ABI rather than native internal interfaces.** The engine and its JavaScript implementation remain first-party Zig. [F1, F3]

The relevant requirements are:

- Opaque owners, checked handles, explicit buffer lifetimes and length units, status codes, and no unwinding across the C boundary.
- Queued host requests and bounded engine steps, not reentrant foreign mutation.
- A host-owned event loop and one owner for document mutation.
- A separately versioned pointer-free process protocol and independent broker authorization.
- Minimal chrome that still exposes real origin identity, navigation, permissions, downloads, application identity, keyboard operation, IME, and accessibility.
- Windows first; Linux and macOS remain first-class execution targets. Mobile and Wasm require separate qualification.
- No external web renderer or JavaScript engine in the shipped shell or engine. Native widgets do not authorize a WebView shortcut. [F1–F5]

**Managed host runtimes are not intrinsically forbidden.** A .NET or BEAM host does not put a third-party dependency inside the portable Zig core. Its runtime still counts against the preference for minimal shipped dependencies. A third-party **JavaScript** runtime is different: Node and Bun fail the supplied hard shell constraint even if Fairpane, rather than that runtime, renders every page.

### C ABI dogfooding and out-of-process execution

A C ABI is a local calling convention, not a process transport. Do not send its native structures or pointers across IPC. [F3]

**[INFERENCE — recommended arrangement]** Use the selected-language wrapper in the first-party renderer-host process to create and drive the engine through C exports. Let the application UI and broker exchange validated, independently versioned messages with that host. No component gets an internal Zig shortcut. The wrapper should expose remote request/lifecycle behavior while retaining real C ABI execution in the engine-owning process. This arrangement dogfoods both contracts without putting hostile document execution in the privileged UI merely to obtain a direct local function call.

The owner should record whether “the shell uses the C ABI” means this transport-aware arrangement or additionally requires a local C ABI proxy in the UI process. That is a contract decision, not something language selection resolves automatically.

## Comparison scores

**All scores in this section are [INFERENCE].** They assess suitability for the initial shell, not measured implementation quality. **5 is favorable; 1 is unfavorable.** There is deliberately no summed score: the external-engine prohibition is a veto, not a weakness that other columns can offset.

| Code | Criterion | What a high score means |
| --- | --- | --- |
| A | C ABI interop and ownership | Straightforward ABI declarations plus idiomatic, reliable resource ownership. |
| Q | Queues, threads, event loop | A bounded request pump and explicit cancellation/teardown fit naturally. |
| N | Native platform reach | Practical access to windowing, input, IME, menus, and accessibility on **all three** desktop OSes. |
| S | Memory and thread safety | Strong ordinary-code protections; foreign interfaces still need review. |
| P | Pinning and reproducibility | Toolchain/package selection is tractable; this does not establish byte-identical builds. |
| W | Runtime weight | Little additional runtime, GC, startup, and distribution machinery. No binary-size measurements were made. |
| F | Future mobile and Wasm | Credible target/tooling routes, not qualified Fairpane ports. |
| C | Contributors and longevity | Estimated maintainership and succession potential, not measured contributor counts. |
| D | Dogfooding value | Exercises a representative external embedder and its ownership/runtime failure modes. |
| H | Avoiding hidden engines | The proposed renderer-free dependency profile is clear and auditable. |
| L | Licensing | Compiler/runtime terms are workable with relatively little special handling; not release legal clearance. |

| Candidate | A | Q | N | S | P | W | F | C | D | H | L | One-line justification |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| **Rust** | 5 | 5 | 4 | 5 | 5 | 5 | 5 | 4 | 5 | 5 | 5 | Best safe foreign-owner model; native adapters, not a bundled GUI/WebView stack. [R1–R5] |
| **C++** | 5 | 4 | 5 | 2 | 4 | 5 | 5 | 5 | 5 | 5 | 5 | RAII and native APIs are an excellent fit; privileged-host lifetime/race defects remain a major risk. [C1–C4] |
| **C# / NativeAOT** | 4 | 5 | 3 | 4 | 5 | 3 | 3 | 5 | 5 | 5 | 5 | Good managed ownership and request handling; direct AOT-safe platform adapters and retained GC are the trade-off. [N1–N7] |
| **Swift** | 4 | 5 | 3 | 5 | 4 | 3 | 4 | 4 | 5 | 5 | 5 | ARC/actors and AppKit are strong; Windows/Linux GUI adapters and runtime packaging need deliberate work. [S1–S6] |
| **Go** | 4 | 5 | 3 | 4 | 5 | 3 | 3 | 4 | 5 | 5 | 5 | Strong queued-host idioms; cgo pointer rules, OS-thread affinity, and native UI bridges add friction. [G1–G5] |
| Zig as a **C ABI consumer** | 4 | 4 | 3 | 2 | 5 | 5 | 3 | 3 | 2 | 5 | 5 | Reuses the existing compiler pin and avoids another runtime, but provides less independent foreign-language pressure. [Z1, F3] |
| Kotlin/Native | 4 | 4 | 3 | 4 | 3 | 3 | 3 | 4 | 4 | 5 | 5 | Real C/platform interop and managed memory; Windows is a lower-support MinGW target and Kotlin/Wasm is a separate backend. [K1–K3] |
| Odin | 4 | 4 | 3 | 2 | 3 | 5 | 2 | 2 | 3 | 5 | 5 | Direct foreign calls and explicit allocators are attractive; safety and native-UI maintenance capacity are weaker choices here. [O1–O3] |
| Nim | 4 | 4 | 3 | 3 | 3 | 4 | 3 | 2 | 4 | 5 | 5 | Import pragmas and ARC/ORC move/destructor support are useful; generated-C and smaller-ecosystem maintenance add another layer. [M1–M3] |
| D | 4 | 4 | 3 | 3 | 4 | 3 | 2 | 2 | 4 | 5 | 5 | Strong C interop and a safe subset; normal D brings a GC, while BetterC removes useful host-language facilities. [D1–D3] |
| OCaml | 3 | 4 | 2 | 4 | 4 | 3 | 2 | 2 | 4 | 5 | 4 | Safe application logic is appealing; native UI and C-stub/GC-root integration are a less direct initial-shell path. [ML1–ML2] |
| TypeScript on Node/Bun | 3 | 5 | 2 | 4 | 4 | 1 | 3 | 5 | 5 | **1** | 3 | Useful external wrapper targets, but V8/JavaScriptCore make these shipped-shell profiles **ineligible**. [T1–T3] |
| TypeScript on future Fairpane JS | 2 | 4 | 1 | 2 | 2 | 2 | 3 | 5 | 5 | 5 | 3 | Potentially excellent self-hosted chrome dogfooding, but no runtime or qualified native-shell adapter exists today. [F4, T4] |
| Elixir | 2 | 5 | 2 | 4 | 4 | 1 | 1 | 3 | 4 | 5 | 5 | Excellent supervised process model; BEAM plus native engine/UI helpers is too much initial-shell machinery. [E1–E3] |
| Plain C baseline | 4 | 3 | 5 | 1 | 4 | 5 | 5 | 5 | 4 | 5 | 5 | Essential ABI baseline, but manual ownership and concurrency provide the least protection for the real application. [C3–C4, P1–P7] |

The high H scores for native candidates assume the **proposed direct native-adapter profile**, not arbitrary packages in their ecosystems. A Rust Windows binding package, for example, can expose WebView2 as an optional facility; that is not permission to use it. None of these scores is a dependency audit of a completed shell. [R5]

For TypeScript-on-Fairpane, the numbers assess present readiness and explicitly unknown implementation quality, not the safety or performance of an imaginary finished runtime. For Go and Kotlin, broad language-family mobile/Wasm support must not be confused with reusing the same native FFI adapter unchanged.

## Native chrome: what each finalist would actually need

**[INFERENCE — proposed implementation routes, not executed adapters]**

| Language | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Rust | Narrow Win32/COM bindings; UI Automation providers and TSF integration where controls are custom. | AppKit through a reviewed Objective-C bridge; NSAccessibility and NSTextInputClient integration for the page surface. | A declared C/GObject adapter to GTK for widgets, IMContext, and AT-SPI, or a larger direct-platform implementation. |
| C++ | Direct Win32/COM APIs and native standard controls. | Thin Objective-C++ AppKit adapter, with the application policy/lifecycle code remaining C++. | GTK C calls, or an explicitly chosen alternative native toolkit without web-renderer modules. |
| C# / NativeAOT | `LibraryImport` and source-generated COM; explicit UI-thread dispatch. No assumption that WinForms/WPF qualify under NativeAOT. | First-party AppKit/Objective-C native bridge callable through C declarations. | Source-generated P/Invoke over a declared GTK/GObject surface. |
| Swift | C/Windows SDK imports plus an explicit COM/input/accessibility adapter. Swift-on-Windows examples establish feasibility, not Fairpane qualification. | Direct AppKit integration, with actor/main-thread rules appropriate to the platform and ABI. | C imports over a declared GTK surface; AppKit/SwiftUI portability is not assumed. |
| Go | Native calls/cgo helpers for Win32 and COM, driven on the required OS thread. | Objective-C native shim via cgo and a correctly owned AppKit event loop. | Cgo over GTK and its event loop, with native lifetimes kept separate from retained Go pointers. |

The underlying platform obligations are not optional language features:

- Windows provides standard controls in User32/Comctl32 and standard-control UI Automation providers. Custom controls need providers of their own. TSF is a COM-based advanced text-input framework. [P1–P3]
- AppKit exposes standard text editing and native accessibility. A custom-drawn text view needs the full text-input integration, including marked/composition text; arbitrary key events are not an IME implementation. Non-view visual elements need explicit accessibility objects. [P4–P5]
- GTK’s standard controls provide accessibility information and input-method integration. Its accessibility backend reaches AT-SPI on Linux. A custom widget still has to supply semantics, state, and behavior. GTK is an explicit LGPL-licensed toolkit dependency with related text/rendering libraries, not a magically dependency-free Linux “OS widget” API. [P6–P8]

Native OS callbacks also do not disappear. Accessibility and windowing APIs may call the host synchronously. **[INFERENCE]** Keep their answers in host-owned snapshots and marshal engine-affecting actions onto the authorized owner’s queue. Do not turn a UIA, AppKit, or GTK callback into reentrant engine mutation.

### Ownership details that matter more than the language name

**[INFERENCE — wrapper design requirements derived from F3]**

- Rust: keep unsafe raw declarations private; use one non-cloneable owner, scoped frame borrows, and no `Send`/`Sync` promises unless the ABI permits them. Safe Rust cannot verify a false lifetime claim from the wrapper.
- C++: use move-only owners and non-owning scoped views; document destruction/thread affinity. Exception containment at any OS/native callback boundary is still required.
- C#: use explicit `Dispose`/asynchronous shutdown and AOT-safe signatures. `SafeHandle` is useful for permitted native releases, but a finalizer thread must not directly destroy a thread-affine engine owner. A finalizer is not a shutdown protocol.
- Swift: actor ownership serializes state, but an ordinary actor or an `async` function is not automatically an OS-thread-affinity guarantee. Scoped borrowed native data must not survive suspension. [S3]
- Go: use explicit `Close`, request cancellation, and owner-goroutine serialization. Retained cgo buffers must follow pinned/native-memory rules; context cancellation alone does not cancel an engine request. [G1–G2]

For all candidates, request IDs, cancellation acknowledgment, stale-handle errors, outstanding-request teardown, buffer units, and allocation failure need the shared executable wrapper suite. A generated declaration file or a window-opening demo does not establish support. [F3, F5]

## The chrome-rendering decision

### Option A: native widgets around a Fairpane page surface

Use native widgets for the address bar, navigation commands, permission/download surfaces, menus, and application-window identity. Fairpane alone renders the page surface.

**Advantages [INFERENCE]:**

- The initial browser can expose real origin identity and error states before Fairpane implements sophisticated editable chrome, DOM events, and accessibility.
- Native text fields and controls bring platform input/accessibility machinery that otherwise must be implemented in Fairpane and its adapters.
- A content renderer crash need not erase the trusted address bar or the user’s ability to close the window.
- The shell remains a demanding C ABI consumer: resource requests, frame lifetimes, input, focus, resize, cancellation, and teardown still pass through the public contract.

**Costs [INFERENCE]:**

- Three genuine platform implementations need maintenance and execution lanes.
- Native widget behavior and visual layout differ across OSes.
- Linux needs an explicit toolkit/dependency policy; Windows/macOS native APIs do not provide a universal Linux widget implementation.

**Ranking for this option:** **Rust, C++, C# NativeAOT, Swift, Go.** Native integration gives C++ its strongest argument; Swift would rise substantially for an Apple-first product, but that is not Fairpane’s declared sequence.

### Option B: Fairpane renders browser chrome through the same embedding API

Render a trusted chrome document or surface using Fairpane. The wrapper-language host still owns windows, policy, process control, native input/accessibility bridges, and presentation. It must use public APIs for chrome and page rendering, not internal Zig functions.

**Advantages [INFERENCE]:**

- Exercises the actual engine on the project’s own interface: text, editing, focus, style/layout, events, paint, and accessibility.
- Reduces duplicated widget layout logic and may allow a more consistent chrome implementation across desktops.
- Makes safe asynchronous host logic more important than the richness of a language’s widget bindings.

**Costs and security conditions [INFERENCE]:**

- It does not eliminate OS integration: window/application identity, menus where required, IME composition, platform accessibility, file dialogs, permissions, and downloads remain host work.
- The first window acquires dependencies on engine editing, input, accessibility, and possibly script/DOM features. Current FP-0017 depends on the lifecycle foundation; requiring fully engine-rendered chrome substantially lengthens that dependency path. The existing roadmap intentionally introduces the shell early. [F4–F5]
- Trusted chrome and hostile page content must not share an authority boundary merely because both use the same engine. Separate owners/context policy are necessary, and process isolation remains the default security direction.
- Broker-validated origin and permission data must remain authoritative. A page cannot supply the displayed browser identity, navigate the chrome context, inject chrome scripts, or acquire native host capabilities by possessing ordinary document handles.
- Sharing the renderer’s failure mode with all security UI is dangerous. Preserve independently operable trusted identity/crash/close behavior or demonstrate an equivalent containment design.
- Every required chrome capability must exist in the public embedding contract. “Just call the DOM internals” would defeat the owner’s dogfooding decision.

**Ranking if this option is deliberately selected:** **Rust, C# NativeAOT, Go, C++, Swift. [INFERENCE]** Rust stays first; C# and Go rise because the workload shifts toward safe host state, queues, and protocol/lifecycle management. C++ loses some of its widget-access advantage. Swift loses part of the value of direct AppKit chrome. Zig remains a plausible low-runtime alternative but still weakens independent-language dogfooding and does not gain Rust-like ownership/thread safety merely because fewer widgets are native.

TypeScript on **Fairpane’s own future runtime** could eventually become a strong self-hosting option for this design. It is **not an initial-shell finalist today**. TypeScript still needs to become executable JavaScript, a qualified first-party runtime, a public native/remote adapter, native platform integration, and a distinct trusted-chrome capability model. Running a script inside the engine is not automatically a foreign C ABI consumer. A native launcher/adapter would remain necessary unless an appropriate public host interface is designed and qualified. Node or Bun as that launcher’s application runtime would still violate the supplied constraint. [F3–F4, T1–T4]

**Recommended practical choice [INFERENCE]:** start with a native trusted address bar and security/crash surfaces. Consider engine-rendered secondary chrome only as the relevant public APIs and behavior qualify. This is real native application behavior, not a screenshot or unsupported-feature success fallback.

## Leading recommendation: Rust’s main risks

1. **The unsafe perimeter is real.** Incorrect layout, lifetime, destruction order, or thread promises can invalidate the safe wrapper. Keep it narrow and independently reviewed. [R1–R2]
2. **There is no free complete cross-platform browser GUI.** Win32 bindings are useful, but Cocoa and Linux integration need sustained ownership. A drawing window alone does not qualify keyboard, IME, accessibility, permissions, or application identity. [P1–P7]
3. **Dependency growth can erase the advantage.** Favor narrow generated/raw bindings, pinned audited source, and first-party platform adapters. Do not select a convenience stack whose window is actually a WebView. Microsoft’s binding repository itself distinguishes raw/native facilities from optional WebView facilities. [R5]
4. **Async code can obscure owner affinity.** A general task executor must not move a thread-affine owner or hold a borrowed native view across an await. The engine’s bounded step/deadline must integrate with the actual OS event loop, not a busy polling loop. [R2, F2–F3]
5. **Reproducibility includes more than Cargo.** Pin the Rust compiler, dependency graph, Zig compiler, native SDKs, linker/sysroot, generators, and build environment. Toolchain/lock files constrain inputs; they do not establish repeatable output without evidence. [R3–R4]
6. **Contributor capacity is unmeasured.** The inferred ecosystem advantage does not establish that Fairpane currently has Rust/COM/AppKit/AT-SPI maintainers. No staffing survey or implementation comparison was performed.

These risks do not justify an internal-Zig escape hatch. If Rust cannot express a necessary ownership operation safely, fix or explicitly document the public contract rather than secretly bypassing it.

## Licensing and runtime inventory

Compiler licenses are not licenses on a language, and a compiler’s headline license does not cover every packaged SDK, dependency, or runtime component.

| Candidate/tooling profile | Primary licensing facts |
| --- | --- |
| Rust | Rust is MIT/Apache-2.0 dual-licensed; its COPYRIGHT inventory explicitly directs distributors to component-level release notices. [L1] |
| C / C++ using LLVM/Clang | LLVM’s Apache-2.0-with-LLVM-exception framework includes compiler/runtime subprojects and documents remaining exceptions and third-party code. OS SDK/runtime terms remain separate. [C3, L2] |
| C# NativeAOT | .NET runtime is MIT-licensed. NativeAOT’s shipped runtime libraries and native prerequisites still need an inventory. [N1, L3] |
| Swift | Apache-2.0 with a Runtime Library Exception; Apple SDK/framework distribution terms remain separate. [S1] |
| Go | BSD three-clause-style license for Go; native helper/toolkit dependencies remain separate. [L4] |
| Kotlin/Native | JetBrains-owned repository code is Apache-2.0; the repository explicitly inventories third-party exceptions. [L5] |
| Odin | Compiler and libraries are zlib-licensed; vendor libraries must be checked individually. [O1] |
| Nim | Compiler documentation states MIT licensing. C compiler/runtime and imported libraries require their own inventory. [M1] |
| D | DMD compiler sources state Boost Software License 1.0, with per-file overrides. Runtime/standard-library and any alternate compiler distributions need component review. [L6] |
| OCaml | LGPL-2.1 with a specific linking exception permitting executable distribution under other terms in the described circumstances; modifications and third-party libraries still have their own obligations. [L7] |
| Zig | Zig’s source license is MIT; its packaged compiler components still require inventory. [L8] |
| TypeScript | Compiler is Apache-2.0. Node/Bun have separate runtime inventories; Bun explicitly documents statically linked JavaScriptCore/WebKit and LGPL obligations. Fairpane’s outbound license is still unset. [T2, L9, F1] |
| Elixir | Elixir and current Erlang/OTP are Apache-2.0; BEAM distribution, native helpers, and libraries still need inventory. [L10–L11] |

A shared Linux GTK route adds LGPL-2.1-or-later obligations regardless of the wrapper language. It also adds a native UI rendering/text stack for **chrome**; it must never become concealed page shaping/rendering behind Fairpane’s engine API. [P8, F2]

**[INFERENCE]** None of the five finalists has an obvious compiler/runtime license obstacle to the commons mission. This is not legal clearance, a selected Fairpane outbound license, or a claim that all potential GUI libraries are compatible.

## Candidates rejected from the initial top five

“Rejected” here means **not recommended as the first browser-shell wrapper**, not prohibited from becoming a qualified downstream wrapper.

- **Zig as a C ABI consumer:** saves a toolchain/runtime but offers less independent-language dogfooding and does not enforce owner lifetimes/thread safety; it remains a serious reserve option. [Z1, F3]
- **Kotlin/Native:** useful C and Apple interop, but its documented Windows MinGW target is lower-tier and its GC/Gradle/native toolchain stack is a less balanced Windows-first choice. [K1–K3]
- **Odin:** excellent explicit low-level control, but weaker lifetime/race protections and inferred smaller native-application maintainer capacity than the shortlist. [O1–O3]
- **Nim:** credible ARC/ORC and foreign bindings, but the generated-C/toolchain layer and inferred smaller native UI ecosystem add risk without a decisive advantage here. [M1–M3]
- **D:** capable C bindings and safe-subset features, but normal-runtime GC or BetterC’s loss of built-in threading/classes/exceptions is an awkward initial-shell trade-off. [D1–D3]
- **OCaml:** strong safe application logic, but C-stub/root management and inferred native UI adapter burden outweigh its value for this first desktop shell. [ML1–ML2]
- **TypeScript on Node:** hard veto because the shipped shell would depend on V8, even if it renders pages only with Fairpane. [T1]
- **TypeScript on Bun:** hard veto because Bun statically links JavaScriptCore/WebKit; writing substantial Bun code in Zig does not make that engine first-party Fairpane. [T2]
- **TypeScript on future Fairpane JavaScript:** promising later self-hosting candidate, but depends on an unimplemented runtime and a not-yet-qualified public native host adapter. [F3–F4]
- **Elixir:** supervised ports are compelling for an external renderer service, but BEAM and native GUI/C ABI helpers make it a heavy, indirect first browser shell. [E1–E3]
- **Plain C:** keep it as the mandatory ABI/lifecycle reference, but do not prefer manual application ownership/concurrency over the safer shortlist without a compelling measured reason. [F5]

## Decisions for the owner

1. **Choose the language and record the ordering priorities.** Rust is the default recommendation. Decide how much native-UI implementation cost should outweigh privileged-host memory/thread safety and runtime weight.
2. **Choose the initial chrome model.** Native security/origin/input widgets, fully Fairpane-rendered chrome, or a clearly specified hybrid imply different dependencies and failure boundaries.
3. **Define the allowed host dependency profile.** Decide whether a declared Linux GTK dependency and small platform bindings/shims are acceptable, how they are pinned, and whether the shell must avoid a managed GC. Do not conflate host dependencies with portable-core dependencies.
4. **Record C ABI dogfooding across processes.** Specify where the selected-language wrapper calls C exports, where the process protocol runs, and whether the UI requires a local ABI proxy. Prohibit direct imports of internal Zig engine modules for every candidate.
5. **Define trusted chrome authority and crash behavior.** Origin identity, permission decisions, page-surface bounds, keyboard escape/close behavior, and renderer failure recovery need an explicit authority boundary regardless of rendering method.
6. **Decide the thin-native-glue rule.** C++, Go, C#, Elixir, and future TypeScript may need Objective-C/C/native helper code. State whether this is permitted platform adaptation or whether essentially all application logic and adapters must be written in the chosen language.
7. **Select reproducibility and licensing profiles before release.** Pick exact compiler/SDK/package artifacts only after qualification; keep the unresolved Fairpane outbound license an explicit owner/legal decision.
8. **Set mobile distribution expectations without an engine substitution.** Apple’s documented EU alternative-browser-engine route requires entitlements, conformance, security, and ongoing operational commitments. Native language support alone does not establish permission to ship Fairpane on iOS/iPadOS. Do not substitute WKWebView where the first-party engine cannot yet be distributed. [P9]

After the owner chooses, the next implementation contract should connect FP-0006 and FP-0021 to the selected-language lifecycle and FP-0017 shell acceptance: actual owners/statuses, bounded host requests, cancellation and teardown, a real Windows window/address bar, renderer-free dependencies, and recorded target execution. FP-0020 supplies the broker boundary; FP-0018/0019 connect real frames and interaction; FP-0023 requires native Linux/macOS input/focus/teardown execution. Existing FP-0022 TypeScript/Elixir integration obligations remain external wrapper obligations, not evidence that either must be the browser-shell language. [F5]

## Primary-source citations

### Fairpane contract and task sources

- **F1:** [CHARTER](https://github.com/mattneel/fairpane/blob/master/docs/CHARTER.md), [PRODUCT](https://github.com/mattneel/fairpane/blob/master/docs/PRODUCT.md), and [HANDOFF](https://github.com/mattneel/fairpane/blob/master/engineering/HANDOFF.md): mission, engine ownership, product scope, current bootstrap state, and unresolved outbound license.
- **F2:** [ARCHITECTURE](https://github.com/mattneel/fairpane/blob/master/docs/ARCHITECTURE.md): portable-core dependency boundary, host loop, bounded steps, broker and pointer-free messages.
- **F3:** [ABI_AND_WRAPPERS](https://github.com/mattneel/fairpane/blob/master/docs/ABI_AND_WRAPPERS.md): opaque ownership, statuses, queued requests, process/Wasm boundaries, and wrapper idioms.
- **F4:** [SECURITY](https://github.com/mattneel/fairpane/blob/master/docs/SECURITY.md), [ROADMAP](https://github.com/mattneel/fairpane/blob/master/docs/ROADMAP.md), and [JAVASCRIPT_RUNTIME](https://github.com/mattneel/fairpane/blob/master/docs/JAVASCRIPT_RUNTIME.md): isolation, early shell sequence, first-party JavaScript, and qualification boundaries.
- **F5:** [workstreams.json](https://github.com/mattneel/fairpane/blob/master/engineering/workstreams.json) and [plan.json](https://github.com/mattneel/fairpane/blob/master/engineering/plan.json): read the full workstream obligations and FP-0006, FP-0017–FP-0023 acceptance criteria.

### Finalist language and toolchain sources

- **R1:** [Rustonomicon: FFI](https://doc.rust-lang.org/nomicon/ffi.html): unsafe foreign declarations, safe wrappers, destruction, and boundary obligations.
- **R2:** [Rust Book: Send and Sync](https://doc.rust-lang.org/book/ch16-04-extensible-concurrency-sync-and-send.html): ownership transfer and sharing restrictions.
- **R3:** [rustup toolchain file](https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file): exact version/date selection.
- **R4:** [Cargo build options](https://doc.rust-lang.org/cargo/commands/cargo-build.html): locked, offline, and frozen dependency behavior.
- **R5:** [Microsoft windows-rs](https://github.com/microsoft/windows-rs): native/raw/COM binding facilities and separately identified optional WebView facilities.
- **R6:** [Rust target support](https://doc.rust-lang.org/rustc/platform-support.html) and [wasm32 limitations](https://doc.rust-lang.org/rustc/platform-support/wasm32-unknown-unknown.html): desktop/mobile target tiers and distinct Wasm runtime limits.
- **C1:** [C++ Core Guidelines, RAII](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines#Rr-raii): paired-resource ownership and move-only handle example.
- **C2:** [C++ working-draft language linkage](https://eel.is/c++draft/dcl.link): required C linkage and implementation-specific ABI details; this is a hosted rendering of working-draft text, not a purchased final ISO standard.
- **C3:** [Clang](https://clang.llvm.org/): C/C++/Objective-C/Objective-C++ front ends and native toolchain profile.
- **C4:** [WASI SDK](https://github.com/WebAssembly/wasi-sdk) and [Android NDK native APIs](https://developer.android.com/ndk/guides/stable_apis): C/C++ Wasm and mobile routes, not Fairpane port qualification.
- **N1:** [NativeAOT deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot): self-contained native compilation, retained runtime libraries, target support, and restrictions.
- **N2:** [P/Invoke source generation](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/pinvoke-source-generation): compile-time marshalling and AOT-oriented interop.
- **N3:** [ComWrappers source generation](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/comwrappers-source-generation): AOT-friendly COM and its restrictions.
- **N4:** [Native interoperability best practices](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices): native ownership, blittable types, and signatures.
- **N5:** [global.json](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json): exact SDK selection and disabled roll-forward.
- **N6:** [Known trimming incompatibilities](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/incompatibilities): WPF/WinForms and built-in COM constraints.
- **N7:** [.NET GC configuration](https://learn.microsoft.com/en-us/dotnet/core/runtime-config/garbage-collector): managed GC/runtime machinery; read together with N1’s retained-runtime description.
- **S1:** [About Swift](https://www.swift.org/about/): language safety, platform framework distinctions, and Apache license/runtime exception.
- **S2:** [Swift platform support](https://www.swift.org/platform-support/) and [Swift on Windows](https://www.swift.org/blog/swift-on-windows/): real Windows/Linux platforms and native Windows interoperability example.
- **S3:** [Swift book concurrency source](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/Concurrency.md): actors, isolation, suspension, main actor, and cancellation.
- **S4:** [Swift book ARC source](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/AutomaticReferenceCounting.md): ARC lifetime model and cycle considerations.
- **S5:** [Official Swift Wasm SDK guide](https://www.swift.org/documentation/articles/wasm-getting-started.html): matching compiler/SDK versions and current Windows-host cross-compilation limitation.
- **S6:** [Apple AppKit input/accessibility sources P4–P5 below]: native Apple UI route.
- **G1:** [Authoritative cgo documentation source](https://go.dev/src/cmd/cgo/doc.go): C calls and pinned/retained pointer restrictions.
- **G2:** [Go runtime LockOSThread](https://go.dev/pkg/runtime/?m=old#LockOSThread): native-thread ownership and per-thread OS state.
- **G3:** [Go toolchains](https://go.dev/doc/toolchain): exact selection, automatic switching, and disabling that switching.
- **G4:** [Go mobile](https://go.dev/wiki/Mobile): Android/iOS routes and the limited native application API set; this wiki includes historical examples and is not a current Fairpane execution result.
- **G5:** [Go WebAssembly](https://go.dev/wiki/WebAssembly): separate js/Wasm and WASI routes and matching support files.

### Other candidate sources

- **Z1:** [Zig overview](https://ziglang.org/learn/overview/): explicit allocation/control, C integration, and safety-build distinctions; its examples are not evidence for Fairpane’s pinned compiler.
- **K1:** [Kotlin/Native C interoperability](https://kotlinlang.org/docs/native-c-interop.html): generated headers, platform bindings, scopes, and unsafe pointers.
- **K2:** [Kotlin/Native target support](https://kotlinlang.org/docs/native-target-support.html): Windows MinGW and target tiers.
- **K3:** [Kotlin/Native memory manager](https://kotlinlang.org/docs/native-memory-manager.html): shared managed heap and tracing GC.
- **O1:** [Odin FAQ](https://odin-lang.org/docs/faq/): allocators, design, and compiler/library license.
- **O2:** [Odin foreign system](https://odin-lang.org/docs/overview/#foreign-system): C calling conventions and foreign imports.
- **O3:** [Odin installation](https://odin-lang.org/docs/install/): supported hosts, native SDK/linker prerequisites, and Wasm linker route.
- **M1:** [Nim compiler guide](https://nim-lang.org/docs/nimc.html): generated C/C++/Objective-C backends, cross-compilation, checks, and MIT license.
- **M2:** [Nim foreign interface](https://nim-lang.org/docs/manual.html#foreign-function-interface): import pragmas and threading model.
- **M3:** [Nim destructors/moves](https://nim-lang.org/docs/destructors.html): ARC/ORC, scope destruction, forbidden copies, and cycle collection.
- **D1:** [D C interface](https://dlang.org/spec/interfaceToC.html): direct C calls, layout, and native/GC lifetime rules.
- **D2:** [Memory-safe D](https://dlang.org/spec/memory-safe-d.html): safe/trusted/system boundaries and scope limitations.
- **D3:** [BetterC](https://dlang.org/spec/betterc.html): removed runtime and unavailable language/library features.
- **ML1:** [OCaml C interface manual](https://ocaml.org/manual/5.3/intfc.html): C stubs, runtime representations, GC integration, and native linking.
- **ML2:** [OCaml installation](https://ocaml.org/docs/installing-ocaml): actual Windows/Linux/macOS installation support; rejection is not a claim that Windows is unsupported.
- **T1:** [Node documentation](https://nodejs.org/api/documentation.html): explicit V8 dependency.
- **T2:** [Bun licensing/runtime inventory](https://bun.sh/docs/project/license): explicit static JavaScriptCore/WebKit linkage and linked-library licenses.
- **T3:** [Node-API](https://nodejs.org/api/n-api.html): C-based ABI-stable native adapters; ABI stability does not remove the JavaScript-engine dependency.
- **T4:** [TypeScript for JavaScript programmers](https://www.typescriptlang.org/docs/handbook/typescript-in-5-minutes.html): TypeScript’s relationship to JavaScript; future Fairpane execution is a project proposal, not an existing capability.
- **E1:** [Elixir Port](https://hexdocs.pm/elixir/Port.html): external OS processes, message ownership, and orphan-process caveats.
- **E2:** [Elixir Supervisor](https://hexdocs.pm/elixir/Supervisor.html): supervised lifecycle and restart semantics.
- **E3:** [Erlang NIF tutorial](https://www.erlang.org/doc/system/nif.html): synchronous native calls and whole-VM crash risk.

### Platform and licensing sources

- **P1:** [Windows controls](https://learn.microsoft.com/en-us/windows/win32/controls/window-controls): OS controls, native APIs, User32/Comctl32.
- **P2:** [UI Automation providers](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-providersoverview): standard providers and custom-control obligations.
- **P3:** [Windows Text Services Framework](https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework): advanced input and COM interface.
- **P4:** [Apple custom-control accessibility](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/ImplementingAccessibilityforCustomControls.html): NSAccessibility roles, actions, notifications, and non-view elements. Archived guide; current target behavior still requires execution.
- **P5:** [Apple text editing/input architecture](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html): standard text fields and custom NSTextInputClient/composition behavior. Archived guide; not current qualification evidence.
- **P6:** [GTK IMContext](https://docs.gtk.org/gtk4/class.IMContext.html): preedit, commit, focus, surrounding text, and input methods.
- **P7:** [GTK accessibility](https://docs.gtk.org/gtk4/section-accessibility.html): standard/custom controls and AT-SPI backend.
- **P8:** [GTK library inventory](https://docs.gtk.org/gtk4/index.html): LGPL-2.1-or-later license, C headers, and related rendering/text libraries.
- **P9:** [Apple alternative browser engines in the EU](https://developer.apple.com/support/alternative-browser-engines/): entitlement, conformance, isolation, security, and distribution conditions; not a claim about every jurisdiction.
- **L1:** [Rust COPYRIGHT](https://github.com/rust-lang/rust/blob/main/COPYRIGHT).
- **L2:** [LLVM licensing policy](https://llvm.org/docs/DeveloperPolicy.html#copyright-license-and-patents).
- **L3:** [.NET runtime MIT license](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT).
- **L4:** [Go license](https://go.dev/LICENSE).
- **L5:** [Kotlin license inventory](https://github.com/JetBrains/kotlin/blob/master/license/README.md).
- **L6:** [DMD compiler source license statement](https://github.com/dlang/dmd/blob/master/compiler/src/dmd/README.md).
- **L7:** [OCaml license and linking exception](https://github.com/ocaml/ocaml/blob/trunk/LICENSE).
- **L8:** [Zig MIT license](https://github.com/ziglang/zig/blob/master/LICENSE).
- **L9:** [TypeScript Apache license](https://github.com/microsoft/TypeScript/blob/main/LICENSE.txt).
- **L10:** [Elixir Apache license](https://github.com/elixir-lang/elixir/blob/main/LICENSE).
- **L11:** [Erlang/OTP licensing](https://www.erlang.org/about).

### Evidence limitations

Repository documents and the listed official sources were read; no repository file was changed. No candidate wrapper was compiled, no native GUI or accessibility integration was executed, and no runtime-weight measurement was made. Several modern documentation pages exposed only JavaScript shells, so the corresponding official source text was read instead. The pkg.go.dev reader returned missing standard-library documentation; authoritative go.dev source/runtime pages were used instead. Four unavailable documentation URLs were replaced by the cited official sources. There is no unmet report criterion, but **language/runtime/platform qualification remains implementation work rather than an output of this research**.
