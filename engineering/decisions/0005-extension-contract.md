# ADR 0005: One extension contract with equal language clients

Status: decided by the owner; this record awaits an accepting independent review.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0006`, `FP-0019`, `FP-0020`, `FP-0021`, `FP-0036`, `FP-0037`, `FP-0038`, `FP-0039`, `FP-0040`.

## Decision

> **An extension chooses its language, not its privileges or access to Fairpane's capabilities.**

The quoted rule is the owner's wording.
Fairpane has one extension contract.
Its clients are JavaScript on Fairpane's own runtime and every officially supported language SDK.
Every client receives equal capabilities through an idiomatic language interface, and none receives private privileges.

The owner's first extension memo named Rhai and JavaScript as the first two clients.
The owner then clarified that Rhai stood for writing the frontend in a second language.
The frontend and shell are now Rust, so Fairpane needs no Rhai extensions.
In the owner's words, "We can just polyglot the whole way down."
ADR 0006 makes every language SDK power its own first-party extension, and ADR 0007 lets every language drive a frontend.

The Rust shell tests whether the engine is genuinely embeddable.
A second extension language tests whether Fairpane is genuinely extensible, rather than merely programmable in JavaScript.
Rust supplies that second language first, through a compiled extension worker on the Rust SDK.

## Components

| Component | Responsibility |
| --- | --- |
| Extension contract | It defines operations, data types, and lifecycle behavior. |
| Permission broker | It authorizes requests against the extension's identity and current grants. |
| JavaScript adapter | It maps the contract into Fairpane JavaScript host bindings. |
| Language adapters | They map the contract into each SDK language's functions and types. |
| Application services | They execute authorized shell operations and route engine operations through the Rust wrapper. |

The JavaScript adapter runs extension code on Fairpane's own JavaScript runtime through public runtime facilities.
JavaScript and TypeScript extension code runs in separate execution contexts, never in a page's existing context.
TypeScript extensions run on that same runtime, as the owner decided.
A compiled language runs its extensions as compiled extension workers, and an interpreted language supplies a runtime host.
No language host ships a third-party JavaScript or WebAssembly engine, a renderer, or a WebView.
Every adapter calls the same broker, and no adapter implements its own permission policy.
Shell-only operations stay in Rust, so a command-palette entry needs no trip through Zig.
Engine operations cross the Rust wrapper and the C ABI.

## Parity

Parity is a published, executable contract.

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
Languages disagree about values, so the schema states each one explicitly.

- The schema distinguishes ordinary Unicode text from lossless web strings.
- An ECMAScript string can hold unpaired surrogates, while many language strings hold only Unicode scalar values.
- A language whose strings cannot hold every code unit exposes lossless web strings through a dedicated host type with explicit conversions.
- No adapter silently replaces a value that its native string type cannot represent.
- Integers carry explicit ranges, because languages differ in integer width and JavaScript has binary64 numbers and BigInt.
- Object identifiers are opaque handles, never arbitrary JavaScript numbers.
- The schema distinguishes absent fields from explicit null values.
- Binary data uses a byte-buffer representation.

## Containment and resources

The initial security profile runs each untrusted extension in an isolated worker process.
Its runtime receives only the facilities that the host explicitly exposes.
The broker derives extension identity from the worker's authenticated connection.
It never trusts an extension identifier supplied inside a request.
Every language reaches pages through a permission-checked document interface.
No language receives raw DOM pointers or ambient access to page objects.

A language runtime's own limits are only one control.
Host operations therefore carry their own deadlines and resource accounting.
The supervising process keeps an independent termination mechanism.
The runtimes need no identical instruction budgets, because those units do not measure equivalent work.
Every runtime enforces the same policy for observable resources, including storage and outstanding requests.
Unlimited development resources do not imply unlimited resources for installed code.

## Qualification

The first acceptance target is a workspace extension that saves and restores application windows.
Its JavaScript and Rust implementations share one manifest, one permission set, one command, and one persistent data format.
The test runner supplies identical initial state and controlled host responses.
It compares externally observable behavior against an independent expected result.
Agreement between implementations alone qualifies nothing, because they can share a defect.

- A denied permission produces no unauthorized operation.
- Cancellation during restoration prevents later unauthorized effects and cleans up pending requests.
- Shutdown removes registered commands and releases extension-owned resources.
- Additional fixtures cover lossless page strings and numeric boundaries.

The comparison covers only the event ordering that the contract guarantees.
Every later language support package runs the same scenarios, as ADR 0006 requires.

## Sequencing

The extension implementation follows the first usable browser.
Extension work never becomes a prerequisite for that browser.
The baseline still needs these properties before its public interfaces stabilize.

| Requirement | Task |
| --- | --- |
| Explicit identities and cancellable operations | `FP-0004` and `FP-0006` |
| Versioned host requests | `FP-0006` |
| Requester identity from authenticated connections | `FP-0020` |
| Isolated JavaScript execution contexts | `FP-0019` |
| Schema types for text, lossless strings, ranged integers, handles, absence, and bytes | `FP-0021` |

## Release scope

The owner's SDK memo makes a first-party extension in every supported language a product obligation.
The qualification profile therefore requires the `extensions` capability family.

The extension memo also proposed compatibility with existing browser extensions as a separate qualification target.
An earlier record read the owner's reply "YES." as approval of a required `webextensions-compat` family.
That reading was wrong, because the reply was the SDK memo, not a choice among the offered options.
The family is therefore absent from the qualification profile until the owner decides its release scope.
`FP-0040` stays blocked on that decision.

## Sources and evidence

- `engineering/evidence/extensions/owner-memo-2026-10-09.md` holds the owner's extension memo verbatim.
- `engineering/evidence/extensions/release-scope-question.log` holds the first release-scope question and the owner's reply.
- `engineering/evidence/extensions/owner-answers-2.log` holds the confirmation question and the owner's clarification.
