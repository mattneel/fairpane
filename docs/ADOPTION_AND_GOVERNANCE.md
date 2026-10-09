# Stewardship and adoption

## Public work

Design discussions and implementation work happen in the open at <https://github.com/mattneel/fairpane>.
A contribution does not require allegiance to a model provider or commercial service.
Development records preserve provenance and human accountability.

The project documents interfaces so downstream applications can remain independent.
No central service is necessary to run the browser or embed the engine.
Releases include source and the evidence needed to reproduce qualification.

## Governance needs

- Each module needs an owner and at least one independent reviewer.
- Public interfaces need a compatibility and deprecation policy.
- Security work needs a private reporting channel and release authority.
- Standards disagreements need written applicability decisions.
- Contributors need provenance rules and a clear outbound license.
- Maintainers need succession and archival procedures.

The owner appoints the initial maintainers.
The agent cannot fabricate a governing foundation or promise legal stewardship on behalf of others.

## Adoption program

The first integrations cover a native C host, the direct Zig API, and the first-party Rust wrapper.
Fairpane's own browser is the first downstream application of the Rust wrapper.
TypeScript and Elixir exercise different lifetime and process boundaries.
Other wrappers join through the same published contract suite.
A showcase integration needs a real downstream workflow, not a screenshot alone.

The project collects migration issues and documents compatibility limits.
Performance comparisons preserve the workload and environment.
Release notes distinguish supported features from experimental features.

## Remaining owner decisions

The owner established the public repository and authorized continuous pushes to `master`.
The license policy and release identities remain open.
Name availability remains provisional.
Domain registration and trademark work are outside the agent's automatic authority.
These decisions block a public release, not local implementation or public development.

The owner selected Rust as the first-party wrapper language and engine-rendered browser chrome, as ADR 0004 records.
