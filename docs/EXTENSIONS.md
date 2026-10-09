# Extensions and language support

## Rules

> **An extension chooses its language, not its privileges or access to Fairpane's capabilities.**

> **Every officially supported language SDK must power a maintained first-party Fairpane integration and a useful reference extension.**
>
> **Those consumers use the same public contracts and distributed SDKs available to everyone else.**

The quoted rules are the owner's wording.
ADR 0005 records the extension contract, and ADR 0006 records the language SDK obligation.
The Rust shell tests whether the engine is genuinely embeddable.
Rhai then tests whether Fairpane is genuinely extensible, rather than merely programmable in JavaScript.

## One extension system

| Component | Responsibility |
| --- | --- |
| Extension contract | It defines operations, data types, and lifecycle behavior. |
| Permission broker | It authorizes requests against the extension's identity and current grants. |
| Rhai adapter | It maps the contract into Rhai functions and types. |
| JavaScript adapter | It maps the contract into Fairpane JavaScript host bindings. |
| Application services | They execute authorized shell operations and route engine operations through the Rust wrapper. |

Rhai and JavaScript are the first two clients of the contract.
Rhai is not a restricted macro language, and JavaScript receives no private privileges.
Rhai support ships as an optional application component, outside the Zig engine and the canonical Rust wrapper.
The JavaScript adapter runs extension code on Fairpane's own JavaScript runtime, through public runtime facilities.
Extension code runs in separate execution contexts, never in a page's existing context.

Both adapters call the same broker.
Neither adapter implements its own permission policy.
Shell-only operations stay in Rust, so a command-palette entry needs no trip through Zig.
Engine operations cross the Rust wrapper and the C ABI.

## Parity

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

A Rhai handler returns control after it submits work.
The host invokes the completion handler later on the runtime's owner thread.
The JavaScript adapter settles its Promise within the extension context's normal job processing.
Neither adapter blocks the browser's interface thread.
Neither adapter invokes a script callback reentrantly from an arbitrary transport thread.
Parity applies to an operation's result and lifecycle, not to syntax or internal scheduling.

## Values

The contract has a schema, not a generic conversion to JSON.

- The schema distinguishes ordinary Unicode text from lossless web strings.
- Rhai exposes lossless web strings through a dedicated host type with explicit conversions.
- No adapter silently replaces a value that its native string type cannot represent.
- Integers carry explicit ranges.
- Object identifiers are opaque handles, never arbitrary JavaScript numbers.
- The schema distinguishes absent fields from explicit null values.
- Binary data uses a byte-buffer representation.

These rules matter because Rhai strings hold valid Unicode, while ECMAScript strings can hold unpaired surrogates.
Rhai also defaults to `i64` integers, while JavaScript has binary64 numbers and BigInt.
A second language exposes assumptions that a JavaScript-only interface can conceal.

## Containment and resources

The initial security profile runs each untrusted extension in an isolated worker process.
Its runtime receives only the facilities that the host explicitly exposes.
The broker derives extension identity from the worker's authenticated connection.
It never trusts an extension identifier inside a request.
Both languages reach pages through a permission-checked document interface.
Neither language receives raw DOM pointers or ambient access to page objects.

Interpreter limits are only one control.
Host operations carry their own deadlines and resource accounting.
The supervising process keeps an independent termination mechanism.
The runtimes need no identical instruction budgets, because those units do not measure equivalent work.
Both runtimes enforce the same policy for observable resources, including storage and outstanding requests.
Development defaults never grant installed code unlimited resources.

## Language support packages

Each officially supported language receives three connected deliverables.

| Deliverable | Purpose |
| --- | --- |
| The idiomatic SDK | It exposes the public contracts through the language's ownership and error conventions. |
| The language-support extension | It connects that language's execution environment to Fairpane's extension system. |
| A useful reference extension | It exercises the integration through actual browser workflows, not only synthetic tests. |

Rust gets the browser shell as its flagship consumer.
Every other language gets a maintained browser integration and useful extensions that exercise its SDK.
A compiled language can launch a compiled extension worker.
An interpreted language can supply a runtime host.
The execution model can differ, while the capabilities and permission rules stay equivalent.
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
Every language implementation shares its manifest, permissions, command, and persistent data format.
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
Compatibility with existing browser extensions is a separate required capability family, `webextensions-compat`.
Language parity does not establish that compatibility.

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
`FP-0037` and `FP-0038` build the Rhai and JavaScript adapters.
`FP-0039` qualifies parity through the shared reference extension.
`FP-0040` qualifies compatibility with existing browser extensions.
`FP-0041` and `FP-0042` deliver the TypeScript and Elixir support packages.
