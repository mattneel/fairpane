# Extensions and language support

## Rules

> **An extension chooses its language, not its privileges or access to Fairpane's capabilities.**

> **Every officially supported language SDK must power a maintained first-party Fairpane integration and a useful reference extension.**
>
> **Those consumers use the same public contracts and distributed SDKs available to everyone else.**

The quoted rules are the owner's wording.
ADR 0005 records the extension contract, and ADR 0006 records the language SDK obligation.
Fairpane goes polyglot the whole way down: every supported language can write extensions and frontends.
The Rust shell tests whether the engine is genuinely embeddable.
A second extension language tests whether Fairpane is genuinely extensible, rather than merely programmable in JavaScript.

## One extension system

| Component | Responsibility |
| --- | --- |
| Extension contract | It defines operations, data types, and lifecycle behavior. |
| Permission broker | It authorizes requests against the extension's identity and current grants. |
| JavaScript adapter | It maps the contract into Fairpane JavaScript host bindings. |
| Language adapters | They map the contract into each SDK language's functions and types. |
| Application services | They execute authorized shell operations and route engine operations through the Rust wrapper. |

JavaScript extension code runs on Fairpane's own JavaScript runtime, through public runtime facilities.
TypeScript extensions run on that same runtime through the TypeScript SDK's extension transport.
Extension code runs in separate execution contexts, never in a page's existing context.
A compiled language runs its extensions as compiled extension workers.
An interpreted language supplies a runtime host.
No language host ships a third-party JavaScript or WebAssembly engine, a renderer, or a WebView.

Every adapter calls the same broker.
No adapter implements its own permission policy.
Shell-only operations stay in Rust, so a command-palette entry needs no trip through Zig.
Engine operations cross the Rust wrapper and the C ABI.

## Parity

| Area | Required equivalence |
| --- | --- |
| Capabilities | Every language can perform every operation in the supported extension API. |
| Permissions | Equivalent requests receive equivalent authorization decisions. |
| Lifecycle | Every language supports activation, cancellation, shutdown, and recovery. |
| Errors | Every language exposes the same error categories and recovery information. |
| User interface | Every language can contribute commands and declarative interface elements without code in another language. |
| Developer experience | Every language receives API documentation, inspection facilities, and useful source locations. |

The interfaces need identical reach, not identical spelling.
No extension needs a shim in another language to create its settings page.
Every language describes the same native controls through a declarative interface.

## Asynchronous operations

The contract uses requests, completions, and cancellation.
Each adapter maps them into its language's idiom.
A JavaScript operation returns a Promise, which the adapter settles within the extension context's normal job processing.
A language without a native asynchronous model receives a request handle and registers a completion handler.
The host invokes each completion on the extension runtime's owner thread.
No adapter blocks the browser's interface thread.
No adapter invokes an extension callback reentrantly from an arbitrary transport thread.
Parity applies to an operation's result and lifecycle, not to syntax or internal scheduling.

## Values

The contract has a schema, not a generic conversion to JSON.

- The schema distinguishes ordinary Unicode text from lossless web strings.
- A language whose strings cannot hold every code unit exposes lossless web strings through a dedicated host type with explicit conversions.
- No adapter silently replaces a value that its native string type cannot represent.
- Integers carry explicit ranges.
- Object identifiers are opaque handles, never arbitrary JavaScript numbers.
- The schema distinguishes absent fields from explicit null values.
- Binary data uses a byte-buffer representation.

These rules matter because ECMAScript strings can hold unpaired surrogates, while many language strings hold only Unicode scalar values.
Languages also differ in integer width, and JavaScript has binary64 numbers and BigInt.
A second language exposes assumptions that a JavaScript-only interface can conceal.

## Containment and resources

The initial security profile runs each untrusted extension in an isolated worker process.
Its runtime receives only the facilities that the host explicitly exposes.
The broker derives extension identity from the worker's authenticated connection.
It never trusts an extension identifier inside a request.
Every language reaches pages through a permission-checked document interface.
No language receives raw DOM pointers or ambient access to page objects.

A language runtime's own limits are only one control.
Host operations carry their own deadlines and resource accounting.
The supervising process keeps an independent termination mechanism.
The runtimes need no identical instruction budgets, because those units do not measure equivalent work.
Every runtime enforces the same policy for observable resources, including storage and outstanding requests.
Unlimited development resources do not imply unlimited resources for installed code.

## Language support packages

Each officially supported language receives three connected deliverables.

| Deliverable | Purpose |
| --- | --- |
| The idiomatic SDK | It exposes the public contracts through the language's ownership and error conventions. |
| The language-support extension | It connects that language's execution environment to Fairpane's extension system. |
| A useful reference extension | It exercises the integration through actual browser workflows, not only synthetic tests. |

Rust gets the browser shell as its flagship consumer.
Every other language gets a maintained browser integration and useful extensions that exercise its SDK.
ADR 0006 names the officially supported SDKs: Rust, C, TypeScript, and Elixir.
No deliverable receives a private API, and a missing capability becomes a public-contract issue.
The first-party integration builds against the same SDK artifact that external developers receive.
Each SDK also exposes the frontend platform, so a frontend in that language needs no hidden JavaScript application.
`docs/FRONTENDS.md` describes document frontends, custom graphics frontends, and the surface interface.

The engine embedding API and the permissioned extension API remain distinct.
An extension receives no unrestricted engine access because its SDK supports that access for trusted embedders.
Extension requests pass through the broker with the extension's identity.
A successful remote extension does not prove native FFI correctness, so a C ABI adapter keeps its own local ABI and lifetime tests.

Language support stays optional.
Runtime-specific dependencies belong to those optional hosts, outside the Zig engine and the canonical wrappers.
The default browser remains the address bar and the page.

## Qualification

The shared reference extension saves and restores an application workspace.
It exercises persistent state, asynchronous operations, permissions, and lifecycle behavior.
Its first implementations are in JavaScript and in Rust.
Every implementation shares its manifest, permissions, command, and persistent data format.
The test runner supplies identical initial state and controlled host responses.
It compares externally observable behavior against an independent expected result.
Agreement between implementations alone qualifies nothing, because they can share a defect.
The comparison covers only the event ordering that the contract guarantees.

- A denied permission produces no unauthorized operation.
- Cancellation during restoration prevents later unauthorized effects and cleans up pending requests.
- Shutdown removes registered commands and releases extension-owned resources.
- Additional fixtures cover lossless page strings and numeric boundaries.

A language qualifies only after these checks pass.

- Its SDK passes the applicable public-contract tests.
- Its language integration passes isolation and lifecycle tests.
- Its reference extension passes the shared behavioral scenarios.
- An independent example builds against its distributed SDK.

Generated bindings alone never earn a supported label.
Compatibility with existing browser extensions is a separate qualification target.
Its release scope awaits an owner decision, so the qualification profile does not include it yet.

## Sequencing

The extension implementation follows the first usable browser, so it never delays that browser.
The baseline still records these requirements before its public interfaces stabilize.

| Requirement | Task |
| --- | --- |
| Explicit identities and cancellable operations | `FP-0004` and `FP-0006` |
| Versioned host requests | `FP-0006` |
| Requester identity from authenticated connections | `FP-0020` |
| Isolated JavaScript execution contexts | `FP-0019` |
| Schema types for text, lossless strings, ranged integers, handles, absence, and bytes | `FP-0021` |

`FP-0036` defines the extension contract and broker.
`FP-0037` builds the Rust extension worker, and `FP-0038` builds the JavaScript adapter.
`FP-0039` qualifies parity through the shared reference extension.
`FP-0040` holds the compatibility target until the owner decides its scope.
`FP-0041`, `FP-0042`, and `FP-0049` deliver the TypeScript, Elixir, and C support packages.
