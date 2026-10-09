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
The chrome document runs under its own engine owner, separate from every page document.
Process isolation between chrome and page renderers remains the default direction.
Broker-validated state supplies the displayed origin, permission requests, and download identity.
A page cannot navigate, script, restyle, overlay, or inject content into the chrome.
If the chrome renderer fails, the OS window frame keeps its title and close control, and the shell restarts the chrome.

## Rust shell dependencies

The Rust wrapper and the browser shell can use crates for responsibilities outside the engine.
Each crate is pinned, license-checked, advisory-checked, and reviewed on addition and upgrade.
No crate parses, styles, lays out, paints, or scripts web content or chrome.
No crate makes an origin, URL, or permission decision that the engine or broker owns.

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
