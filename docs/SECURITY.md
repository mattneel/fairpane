# Security and trust boundaries

## Product model

Web content is hostile input.
The renderer cannot authorize privileged host operations by assertion alone.
A broker enforces origin and capability policy independently.
Out-of-process isolation is the default full-browser direction.

The headless in-process profile has a different risk envelope.
Its documentation must not imply that a library creates an operating-system sandbox.
Input validation and memory safety remain required in both profiles.

## Trusted chrome

The engine renders the browser chrome as a trusted document.
The chrome document runs in its own renderer process, separate from every page renderer.
Each renderer process runs a Rust renderer host that calls the Rust wrapper and services the process protocol.
The privileged shell exchanges only validated messages with renderer hosts, and no native pointer crosses a process boundary.
Broker-validated state supplies the displayed origin, permission requests, and download identity.
A page cannot navigate, script, restyle, overlay, or inject content into the chrome.
If the chrome renderer fails, the OS window frame keeps its title and close control, and the shell restarts the chrome.

## Rust shell dependencies

The canonical Rust wrapper has no third-party runtime or build dependency.
The browser shell can use qualified crates for user interface and application services.
Each shell crate is pinned, license-checked, advisory-checked, source-checked, and reviewed on addition and upgrade.
No crate parses, styles, lays out, shapes, paints, or scripts web content or chrome.
No crate implements web-visible network semantics, such as redirect handling, cookies, caching, or CORS.
No crate makes an origin, URL, or permission decision that the engine or broker owns.

A transport crate serves only as the broker's authorized transport.
It returns redirect responses unconsumed, so the engine evaluates every redirect.
The same principle applies to cookie policy and response transformations.
Application convenience never overrides observable web behavior.
The engine applies web semantics, and the broker independently authorizes privileged operations.

## Extension containment

The initial security profile runs each untrusted extension in an isolated worker process.
Its runtime receives only the facilities that the host explicitly exposes.
The broker derives extension identity from the worker's authenticated connection, never from a request field.
Rhai and JavaScript adapters call the same broker, and neither adapter implements its own permission policy.
Extensions reach pages through a permission-checked document interface, never through raw DOM pointers.
Host operations carry their own deadlines and resource accounting, beyond any interpreter limit.
The supervising process keeps an independent termination mechanism.
Installed extensions never receive unlimited resources.

## Engine requirements

- Parsers and decoders enforce checked sizes and arithmetic.
- Resource policies bound decoded memory, recursion, work queues, and live handles.
- Allocation failure leaves owners destructible and documented mutation outcomes intact.
- Remote content never justifies an unreachable assertion.
- Cross-origin state follows explicit security tests.
- Production randomness comes from a qualified secure source.
- Renderer crashes do not grant broker privileges.
- JIT pages follow platform execution and write policies.

The agent must preserve safety checks in security-sensitive code unless a reviewed proof supports a narrower alternative.
Performance measurements include the production safety configuration.

## Agent model

OMP filesystem isolation separates workspaces, not all privileges. [S03]
The current task implementation also changes child approval behavior for headless execution. [S04]
Shell-capable workers therefore require restricted credentials and operating-system controls.
A worktree alone is not a sandbox.

Workers receive no release credentials.
Untrusted tests run without general host credentials or unrestricted network access.
Read-only review roles do not receive a shell merely for convenience.

## Qualification trust

Local checks can detect stale evidence and accidental changes.
An agent with write access can modify both the checker and its inputs.
The bootstrap cannot enforce independent acceptance inside that same trust boundary.

A later qualification runner uses protected policy and immutable inputs outside implementation workspaces.
Signed results identify the worker source, policy revision, and test corpus.
The public repository is <https://github.com/mattneel/fairpane>.
Branch protections remain owner-controlled repository settings, as `docs/GIT_OPERATIONS.md` records.

## Vulnerability operations

The project needs a private reporting channel before a public browser release.
The owner selects that channel without a fabricated email address.
A release requires severity triage, coordinated disclosure, and a reproducible patch process.
The public issue tracker must not expose user secrets or live exploit credentials.
