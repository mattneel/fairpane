# ADR 0006: Every language SDK powers a first-party integration

Status: the quoted rule and the recorded answers are owner decisions; the engineering decisions this record labels await an accepting independent review.
Owner: the project owner.
Date: 2026-10-09.
Related tasks: `FP-0022`, `FP-0029`, `FP-0037`, `FP-0039`, `FP-0041`, `FP-0042`, `FP-0049`.

## Decision

> **Every officially supported language SDK must power a maintained first-party Fairpane integration and a useful reference extension.**
>
> **Those consumers use the same public contracts and distributed SDKs available to everyone else.**

The quoted rule is the owner's wording.
It turns idiomatic wrappers for every language from a distribution goal into a product obligation.
Rust gets the browser shell as its flagship consumer.
Every other language gets a maintained browser integration and useful extensions that exercise its SDK.
The browser becomes the place where the entire SDK family proves itself.

## Officially supported SDKs

A language SDK becomes officially supported only through its own support package and qualification.
As an engineering decision, the planned set has four members.

| SDK | Maintained integration | Reference extension |
| --- | --- | --- |
| Rust | The browser shell, `FP-0017`, with the Rust extension worker in `FP-0037`. | The Rust workspace extension, `FP-0039`. |
| C | The C language-support extension, `FP-0049`. | The C workspace extension, `FP-0049`. |
| TypeScript | The TypeScript language-support extension, `FP-0041`. | The TypeScript workspace extension, `FP-0041`. |
| Elixir | The Elixir language-support extension, `FP-0042`. | The Elixir workspace extension, `FP-0042`. |

The C-only consumer in `FP-0034` remains the native ABI harness, not C's integration.

The direct Zig API sits over internal interfaces, so it is not a public SDK.
The other languages in `docs/ABI_AND_WRAPPERS.md` join the set only with a support package.

## The support package

| Deliverable | Purpose |
| --- | --- |
| The idiomatic SDK | It exposes the public contracts through the language's ownership and error conventions. |
| The language-support extension | It connects that language's execution environment to Fairpane's extension system. |
| A useful reference extension | It exercises the integration through actual browser workflows, not only synthetic tests. |

The language-support extension supplies the bridge.
The reference extension proves that another developer can cross it.
Neither deliverable receives a private API.
A missing capability becomes a public-contract issue, not an internal shortcut.
For a compiled language, the integration can launch a compiled extension worker.
For an interpreted language, the integration can run on Fairpane's own JavaScript runtime or supply a runtime host.
No host ships a third-party JavaScript or WebAssembly engine, a renderer, or a WebView.
TypeScript extensions therefore run on Fairpane's own JavaScript runtime through the TypeScript SDK's extension transport, as the owner decided.
The execution model can differ, while the capabilities and permission rules stay equivalent.

## Feedback before adoption

The first-party integration builds against the same SDK artifact that external developers receive.
It never uses an unreleased private wrapper fork.
An awkward cancellation API, a lifetime defect, or missing diagnostics therefore hurts Fairpane's own workflow first.
Fairpane experiences the integration costs before it asks anyone else to accept them.

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

## Qualification

One shared reference extension establishes equivalent behavior across languages.
It saves and restores an application workspace, as ADR 0005 describes.
Each language implementation runs against the same expected outcomes.
Language-specific examples then establish whether each SDK feels idiomatic.

A language qualifies only after these checks pass.

- Its SDK passes the applicable public-contract tests.
- Its language integration passes isolation and lifecycle tests.
- Its reference extension passes the shared behavioral scenarios.
- An independent example builds against its distributed SDK.

Generated bindings alone never earn a supported label.

## Embedding and extension surfaces stay distinct

The engine embedding API and the permissioned extension API remain distinct.
An extension receives no unrestricted engine access because its language SDK supports that access for trusted embedders.
The language integration exposes only the authorized extension surface.
Its requests pass through the broker with the extension's identity.
A successful remote extension does not prove native FFI correctness.
A C ABI adapter still needs local ABI and lifetime tests.
The embedding harness tests native integration, and the browser extension tests actual application behavior.

## Distribution

Every supported language gets an integration, but no installation needs every language runtime.
Language support stays optional.
Runtime-specific dependencies belong to those optional hosts.
They stay outside the Zig engine and the dependency-free canonical wrappers.
The default browser remains the address bar and the page.
Developers add the language support they need.

## Consequences

The `embedding-wrappers` capability family includes the support package for each officially supported language.
`FP-0022` builds the TypeScript and Elixir SDK slices.
`FP-0041`, `FP-0042`, and `FP-0049` deliver the TypeScript, Elixir, and C support packages after the shared scenarios in `FP-0039` exist.

## Sources and evidence

- `engineering/evidence/extensions/owner-sdk-memo-2026-10-09.md` holds the owner's memo verbatim.
- `engineering/evidence/extensions/owner-sdk-memo-extraction.log` records its extraction from the owner's answer.
- `engineering/evidence/extensions/owner-answers-2.log` records the owner's decision that TypeScript extensions run on Fairpane's own JavaScript runtime.
