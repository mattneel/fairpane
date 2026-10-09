# ADR 0005: One extension contract with equal language clients

Status: accepted.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0006`, `FP-0019`, `FP-0020`, `FP-0021`, `FP-0036`, `FP-0037`, `FP-0038`, `FP-0039`, `FP-0040`.

## Decision

> **An extension chooses its language, not its privileges or access to Fairpane's capabilities.**

The quoted rule is the owner's wording.
Fairpane has one extension contract.
Rhai and JavaScript are its first two clients, and they receive equal capabilities through idiomatic language interfaces.
Rhai is not a restricted macro language, and JavaScript receives no private privileges.

The Rust shell tests whether the engine is genuinely embeddable.
Rhai then tests whether Fairpane is genuinely extensible, rather than merely programmable in JavaScript.

## Components

| Component | Responsibility |
| --- | --- |
| Extension contract | It defines operations, data types, and lifecycle behavior. |
| Permission broker | It authorizes requests against the extension's identity and current grants. |
| Rhai adapter | It maps the contract into Rhai functions and types. |
| JavaScript adapter | It maps the contract into Fairpane JavaScript host bindings. |
| Application services | They execute authorized shell operations and route engine operations through the Rust wrapper. |

Rhai remains outside the Zig engine and the canonical Rust wrapper.
Its support ships as an optional application component.
The JavaScript adapter uses Fairpane's own JavaScript runtime through public runtime facilities.
Extension code runs in separate execution contexts, never in a page's existing context.
Both adapters call the same broker, and neither adapter implements its own permission policy.
Shell-only operations stay in Rust, so a command-palette entry needs no trip through Zig.
Engine operations cross the Rust wrapper and the C ABI.

## Parity

Parity is a published, executable contract.

| Area | Required equivalence |
| --- | --- |
| Capabilities | Both languages can perform every operation in the supported extension API. |
| Permissions | Equivalent requests receive equivalent authorization decisions. |
| Lifecycle | Both support activation, cancellation, shutdown, and recovery. |
| Errors | Both expose the same error categories and recovery information. |
| User interface | Both can contribute commands and declarative interface elements without code in the other language. |
| Developer experience | Both receive API documentation, inspection facilities, and useful source locations. |

The interfaces need identical reach, not identical spelling.
A Rhai extension never needs a JavaScript shim to create its settings page.
Both languages describe the same native controls through a declarative interface.

## Asynchronous operations

The contract uses requests, completions, and cancellation.

| JavaScript interface | Rhai interface |
| --- | --- |
| An operation returns a Promise. | An operation returns a request handle. |
| The extension awaits or attaches a continuation. | The extension registers a completion handler. |
| Cancellation follows the shared request contract. | Cancellation follows the same request contract. |

Rhai's engine is synchronous, so a Rhai handler returns control after it submits work.
The host invokes the completion handler later on the runtime's owner thread.
The JavaScript adapter settles its Promise within the extension context's normal job processing.
Neither adapter blocks the browser's interface thread.
Neither adapter invokes a script callback reentrantly from an arbitrary transport thread.
Parity applies to an operation's result and lifecycle, not to syntax or internal scheduling.

## Values

The contract does not rest on a generic conversion to JSON.
Its schema distinguishes ordinary Unicode text from lossless web strings.
Rhai strings hold valid Unicode, while ECMAScript strings can hold unpaired surrogates.
Rhai exposes lossless web strings through a dedicated host type with explicit conversions.
An adapter never silently replaces a value that its native string type cannot represent.
Integers have explicit ranges, because Rhai defaults to `i64` and JavaScript has binary64 numbers and BigInt.
Object identifiers are opaque handles, never arbitrary JavaScript numbers.
The schema distinguishes absent fields from explicit null values.
Binary data uses a byte-buffer representation.

## Containment and resources

The initial security profile runs each untrusted extension in an isolated worker process.
Its runtime receives only the facilities that the host explicitly exposes.
The broker derives extension identity from the worker's authenticated connection.
It never trusts an extension identifier supplied inside a request.
Both languages reach pages through a permission-checked document interface.
Neither language receives raw DOM pointers or ambient access to page objects.

Interpreter limits are only one control.
Rhai's operation count is unlimited by default, and one native call can consume substantial work.
Host operations therefore carry their own deadlines and resource accounting.
The supervising process keeps an independent termination mechanism.
The runtimes need no identical instruction budgets, because those units do not measure equivalent work.
Both runtimes enforce the same policy for observable resources, including storage and outstanding requests.
Development defaults never grant installed code unlimited resources.

## Qualification

The first acceptance target is a workspace extension that saves and restores application windows.
Its Rhai and JavaScript implementations share one manifest, one permission set, one command, and one persistent data format.
The test runner supplies identical initial state and controlled host responses.
It compares externally observable behavior against an independent expected result.
Agreement between the two implementations alone qualifies nothing, because both can share a defect.

- A denied permission produces no unauthorized operation.
- Cancellation during restoration prevents later unauthorized effects and cleans up pending requests.
- Shutdown removes registered commands and releases extension-owned resources.
- Additional fixtures cover lossless page strings and numeric boundaries.

The comparison covers only the event ordering that the contract guarantees.
Compatibility with existing browser extensions is a separate qualification target.
Rhai and JavaScript parity does not establish that compatibility.

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

The owner answered the release-scope question with "YES" to the recommended option.
The qualification profile therefore gains two required capability families.
`extensions` covers the contract, the broker, containment, resource policy, and parity.
`webextensions-compat` covers compatibility with existing browser extensions.

## Sources and evidence

- `engineering/evidence/extensions/owner-memo-2026-10-09.md` holds the owner's extension memo verbatim.
- `engineering/evidence/extensions/owner-answers.log` holds the owner's recorded answer.
- Rhai registered functions: <https://rhai.rs/book/rust/functions.html>.
- Rhai multithreading patterns: <https://rhai.rs/book/patterns/multi-threading.html>.
- Rhai strings and characters: <https://rhai.rs/book/language/strings-chars.html>.
- Rhai numbers: <https://rhai.rs/book/language/numbers.html>.
- Rhai operation limits: <https://rhai.rs/book/safety/max-operations.html>.
