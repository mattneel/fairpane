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

## Rust browser application dependencies

The canonical Rust wrapper has no third-party runtime or build dependency.
The browser application can use qualified crates for user interface and application services.
Each application crate is pinned and reviewed on addition and upgrade.
Each one passes license, advisory, source, ban, and duplicate checks across every declared target configuration, including build dependencies.
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
Every language adapter calls the same broker, and no adapter implements its own permission policy.
No language host ships a third-party JavaScript or WebAssembly engine, a renderer, or a WebView.
Extensions reach pages through a permission-checked document interface, never through raw DOM pointers.
Host operations carry their own deadlines and resource accounting, beyond any limit of a language runtime.
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
The channel stays an owner decision, and ADR 0009 records it as `open` until an owner record exists.
The agent does not create, choose, or announce a channel, and it never fabricates an email address.
The public issue tracker must not expose user secrets, exploit details, or live exploit credentials.

### Reporting channel requirements

A channel qualifies when it meets every one of these requirements.

- It keeps each report private between the reporter and the security responders until disclosure.
- It reaches at least two maintainers with release authority, so one absence cannot stall a report.
- It records when each report arrives, so the response deadlines below are measurable.
- It lets responders share a fix privately with the reporter before release.
- It supports a published advisory and a vulnerability identifier after disclosure.

GitHub private vulnerability reporting can meet these requirements when the owner enables it for the repository.
Enabling it remains the owner's decision.

### Triage severities

These response targets are proposals that the owner approves together with the reporting channel.
Responders acknowledge each report within 3 business days.
They assign a severity within 7 days of the report and record the reason.
The target is the latest date for a patch release after the report.

| Severity | Condition | Target |
| --- | --- | --- |
| Critical | Web content escapes the renderer, runs code in a privileged process, or reads another origin's data without user action. | 7 days |
| High | Web content runs code in a renderer, bypasses an origin or permission check, or corrupts memory, with limited preconditions. | 30 days |
| Medium | A security boundary weakens only with user interaction, an unusual configuration, or a local attacker. | 90 days |
| Low | A defense-in-depth gap or a minor information leak. | The next scheduled release |

### Coordinated disclosure

Responders publish an advisory when a fixed release is available or 90 days after the report, whichever comes first.
They extend the 90-day limit only with the reporter's agreement and a recorded reason.
They publish within 7 days when an issue is exploited in the wild, with mitigations if no fix exists yet.
They credit the reporter in the advisory unless the reporter declines.

### Patch release

A security fix follows the normal release procedure in private until disclosure.

1. Develop the fix in a private workspace, such as a temporary private fork of a repository security advisory.
2. Add a regression test that fails before the fix.
3. Run every applicable gate on the fix commit.
4. Run `source-archive`, `provenance`, and `reproduce-check` for the fix commit, as ADR 0009 describes.
5. Obtain approval from the release approval authority.
6. Sign the source manifest and the provenance statement with the release signing key.
7. Publish the fixed release, its evidence, and the advisory together.

No patch release is possible until the owner records the release decisions that ADR 0009 lists.
