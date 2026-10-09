**YES. Every language SDK gets its own first-party Fairpane extension—and that extension must use the SDK.**

Rust gets the browser shell as its flagship consumer. Every other language gets a maintained browser integration and useful extensions that exercise its SDK.

That changes “idiomatic wrappers for every language” from a distribution goal into **a product obligation**.

The browser becomes the place where the entire SDK family proves itself.

## Each language gets a complete support package

I propose three connected deliverables:

| Deliverable | Purpose |
|---|---|
| **The idiomatic SDK** | It exposes the public contracts through the language’s ownership and error conventions. |
| **The language-support extension** | It connects that language’s execution environment to Fairpane’s extension system. |
| **A useful reference extension** | It exercises the integration through actual browser workflows, not only synthetic tests. |

The language-support extension supplies the bridge. The reference extension proves that another developer can cross it.

**Neither receives private APIs.** A missing capability becomes a public-contract issue, not an internal shortcut.

For compiled languages, the integration can launch a compiled extension worker. For interpreted languages, it can supply a runtime host.

The execution model can differ. The available capabilities and permission rules remain equivalent.

## The SDK now has users before it has outside adopters

An awkward cancellation API hurts our own extension. A lifetime defect breaks our own workflow. Missing diagnostics obstruct our own development.

That creates a direct feedback cycle:

```text
Public contract
      ↓
Idiomatic language SDK
      ↓
First-party browser integration
      ↓
Useful extension behavior
      ↓
Reproducible failures and API feedback
      ↓
Public-contract improvements
```

The first-party integration cannot use an unreleased private wrapper fork. It must build against the same SDK artifact that external developers receive.

That is the important part: **we experience the integration costs before we ask anyone else to accept them.**

## Parity becomes something we can execute

One shared reference extension establishes equivalent behavior across languages. Language-specific examples then establish whether each SDK feels idiomatic.

The shared extension can save and restore an application workspace. It exercises persistent state and asynchronous operations. It also exercises permissions and lifecycle behavior.

Each language implementation runs against the same expected outcomes.

A language qualifies only after these checks pass:

- Its SDK passes the applicable public-contract tests.
- Its language integration passes isolation and lifecycle tests.
- Its reference extension passes the shared behavioral scenarios.
- An independent example builds against its distributed SDK.

Generated bindings alone never earn a supported label.

## One distinction keeps this honest

**The engine embedding API and the permissioned extension API remain distinct.**

An extension does not receive unrestricted engine access merely because its language SDK supports that access for trusted embedders.

The language integration exposes the authorized extension surface. Requests pass through the broker with the extension’s identity.

A successful remote extension also does not prove native FFI correctness. A C ABI adapter still needs local ABI and lifetime tests.

That gives us two complementary consumers: the embedding harness tests native integration, and the browser extension tests actual application behavior.

## This does not require a bloated browser

Every supported language gets an integration. Every browser installation does not need every language runtime.

My proposed distribution keeps language support optional. Runtime-specific dependencies belong to those optional hosts, outside the Zig engine and dependency-free core wrappers.

The default browser remains the address bar and the page. Developers add the language support they need.

The project rule becomes:

> **Every officially supported language SDK must power a maintained first-party Fairpane integration and a useful reference extension.**
>
> **Those consumers use the same public contracts and distributed SDKs available to everyone else.**

**Rust proves that Fairpane can host its own browser. Every additional language proves that the public architecture belongs to everyone—not just its original implementers.**
