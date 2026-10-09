# Founding charter

## Purpose

Fairpane is an attempt to solve the foundational browser problem for good, in the commons.
It is a donation to humanity, not a mechanism to capture users, impose a platform tax, or control distribution.
The project aims to replace repeated architectural resets with a foundation that people can sustain and improve.

Open development includes design decisions and failed experiments.
The public record excludes credentials, private user data, and uncoordinated vulnerability details.

## Commitments

The project owns its portable engine and JavaScript implementation.
The canonical implementation uses Zig master with reproducible pins.
Applications integrate through a stable C ABI after that ABI qualifies.
Language wrappers express their host language's ownership and concurrency conventions.
One wrapper language is first-party, and the project maintains it with the engine.

The public browser is the engine's first embedder.
Its shell is written in the first-party wrapper language and reaches the engine only through the public embedding contract.
Every capability the browser needs therefore exists in that contract for every other embedder.
The browser presents the page with minimal chrome.
It treats web applications as applications without hiding origin identity or browser security decisions.
The engine also remains useful independently of the browser application.

No calendar deadline or token budget justifies false completeness.
Compute availability permits stronger experiments and independent review.
It does not remove the need for bounded tests, cancellation, or controlled worker concurrency.

## Meaning of completion

Completion applies to a named release profile and frozen standards baseline.
That profile retains the broad browser capability obligations in `engineering/qualification.json`.
Every obligation requires concrete tests and reviewed applicability decisions.

Mechanical qualification is evidence, not a proof that no bug exists.
New standards and newly discovered defects belong to maintenance.
The project cannot call an omitted required feature complete by relabeling it as maintenance.

A browser release also requires a usable application and operational support.
Adoption, security response, and contributor continuity are part of the deliverable.

## Decision classes

| Class | Decision authority |
| --- | --- |
| Founding commitments | Owner approval with a public decision record. |
| Public API compatibility | Designated interface owner and independent reviewer. |
| Acceptance-policy changes | Independent qualification review, separate from implementation. |
| Internal design | Module owner through measured evidence and an architecture decision. |
| Experiment disposal | Module owner after preservation of results. |
| Publication and legal policy | Owner or a later explicitly delegated maintainer body. |

Agents can propose changes to any class.
An implementation agent cannot authorize its own exception to a founding commitment.
