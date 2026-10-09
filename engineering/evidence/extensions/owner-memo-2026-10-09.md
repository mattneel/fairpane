**That is a strong first extension milestone: Rhai and JavaScript as equal clients of one Fairpane extension contract.**

It repeats the architectural test behind your Rust shell decision. The browser exercises the engine’s public interface. A second extension language tests whether the extension interface actually stands independent of JavaScript.

My target is **equal capabilities, with idiomatic language interfaces**. Rhai is not a restricted macro language, and JavaScript does not receive private privileges.

## One extension system, two runtime adapters

I propose this separation:

| Component | Responsibility |
|---|---|
| **Extension contract** | It defines operations, data types, and lifecycle behavior. |
| **Permission broker** | It authorizes requests against the extension’s identity and current grants. |
| **Rhai adapter** | It maps the contract into Rhai functions and types. |
| **JavaScript adapter** | It maps the contract into Fairpane JS host bindings. |
| **Application services** | They execute authorized shell operations and route engine operations through the Rust wrapper. |

Rhai supports registered Rust functions and custom host interactions. That makes it a natural adapter for the Rust-side extension host. [Rhai](https://rhai.rs/book/rust/functions.html)

Rhai remains outside the Zig engine and canonical Rust wrapper. Its support can ship as an optional application component.

The JavaScript adapter uses **Fairpane’s own JavaScript runtime through public runtime facilities**. Extension code gets separate execution contexts, not the page’s existing context.

Both adapters call the same broker. Neither adapter implements its own permission policy.

Shell-only operations stay in Rust. Engine operations cross the Rust wrapper and C ABI. A command-palette entry does not require a trip through Zig.

## What “parity” promises

I make parity a published, executable contract:

| Area | Required equivalence |
|---|---|
| **Capabilities** | Both languages can perform every operation in the supported extension API. |
| **Permissions** | Equivalent requests receive equivalent authorization decisions. |
| **Lifecycle** | Both support activation, cancellation, shutdown, and recovery. |
| **Errors** | Both expose the same error categories and recovery information. |
| **User interface** | Both can contribute commands and declarative interface elements without code in the other language. |
| **Developer experience** | Both receive API documentation, inspection facilities, and useful source locations. |

The interface does not need identical spelling. It needs identical reach.

For example, a Rhai extension must not need a JavaScript shim just to create its settings page. Both languages can describe the same native controls through a declarative interface.

I also keep compatibility with existing browser extensions as a separate qualification target. Rhai/JavaScript parity does not establish that compatibility by itself.

## The first real difference: asynchronous operations

Rhai’s current engine is synchronous and does not provide a native async API. Its documentation describes host-thread patterns for access to asynchronous services. [Rhai](https://rhai.rs/book/patterns/multi-threading.html?utm_source=chatgpt.com)

That makes the underlying extension contract important.

My contract uses **requests, completions, and cancellation**. The language adapters provide their own interfaces:

| JavaScript interface | Rhai interface |
|---|---|
| An operation returns a Promise. | An operation returns a request handle. |
| The extension awaits or attaches a continuation. | The extension registers a completion handler. |
| Cancellation follows the shared request contract. | Cancellation follows the same request contract. |

The Rhai handler returns control after it submits work. The host invokes its completion handler later on the runtime’s owner thread.

The JavaScript adapter settles its Promise within the extension context’s normal job processing.

Neither adapter blocks the browser’s interface thread. Neither adapter invokes a script callback reentrantly from an arbitrary transport thread.

**Parity applies to the operation’s result and lifecycle, not to the language’s syntax or internal scheduling.**

## The second difference: values are not interchangeable

A generic “convert everything to JSON” bridge is not my foundation.

Rhai strings contain valid Unicode text and use UTF-8 storage. ECMAScript strings contain 16-bit code units and can contain unpaired surrogates. [Rhai](https://rhai.rs/book/language/strings-chars.html?utm_source=chatgpt.com)

That distinction matters when an extension reads page text. A Rhai adapter cannot silently replace a value that its native string cannot represent.

My schema distinguishes ordinary Unicode text from lossless web strings. Rhai can expose the latter through a dedicated host type with explicit conversion operations.

Numeric values need similar care. Rhai defaults to `i64` integers. JavaScript provides binary64 Number values and a separate BigInt type. [Rhai](https://rhai.rs/book/language/numbers.html?utm_source=chatgpt.com)

My extension contract therefore gives integers explicit ranges. Object identifiers use opaque handles rather than arbitrary JavaScript numbers.

The schema also distinguishes absent fields from explicit null values. Binary data receives a byte-buffer representation.

This is where the second language earns its place. It exposes assumptions that a JavaScript-only interface can conceal.

## Shared privileges, separate containment

I propose an isolated worker process for each untrusted extension in the initial security profile. Its runtime receives only the facilities that the host explicitly exposes.

The broker derives extension identity from the worker’s authenticated connection. It does not trust an extension identifier supplied inside a request.

The same rule applies to page access. Both languages use a permission-checked document interface. Neither receives raw DOM pointers or ambient access to page objects.

Rhai provides configurable execution limits, but its operation count defaults to unlimited. Its documentation also states that one native function call can consume substantial work. [Rhai](https://rhai.rs/book/safety/max-operations.html)

Consequently, interpreter limits are only one control. Host operations need their own deadlines and resource accounting. The supervising process also needs an independent termination mechanism.

The two runtimes do not need identical instruction budgets. Those units do not represent equivalent work.

They do need the same enforceable policy for observable resources, including storage and outstanding requests.

Unlimited development resources do not imply unlimited resources for installed code.

## The first extension gets written twice

After the baseline, I propose one useful acceptance target: **a workspace extension that saves and restores application windows**.

Its Rhai and JavaScript implementations exercise the same manifest and permissions. Both contribute the same command and use the same persistent data format.

The test runner supplies identical initial state and controlled host responses. It compares externally observable behavior against an independent expected result.

The important cases extend beyond success:

- A denied permission produces no unauthorized operation.
- Cancellation during restoration prevents later unauthorized effects and cleans up pending requests.
- Shutdown removes registered commands and releases extension-owned resources.

Additional fixtures cover lossless page strings and numeric boundaries.

The two implementations do not qualify merely because they agree. Both can share the same defect. The contract supplies the expected outcome.

I also compare only the event ordering that the contract guarantees. Internal Promise jobs and Rhai callbacks do not need identical traces.

## What belongs before the baseline

I keep the actual extension implementation after the baseline, as you propose.

Before public interfaces stabilize, I record the architectural requirements. The baseline needs explicit identities and cancellable operations. It also needs versioned host requests and isolated JavaScript contexts.

That preserves the extension path without turning extension development into another prerequisite for the first usable browser.

The governing rule is:

> **An extension chooses its language, not its privileges or access to Fairpane’s capabilities.**

The Rust shell tests whether the engine is genuinely embeddable. **Rhai then tests whether Fairpane is genuinely extensible, rather than merely programmable in JavaScript.**
