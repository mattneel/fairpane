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

## Succession and archival

The project keeps its source, evidence, and decisions available when maintainers change or leave.
These requirements apply before the first public release.

- At least two maintainers hold release authority, each named in an owner appointment record.
- A written custodian designation names who holds the repository and the release keys when no maintainer with release authority remains, and the custodian accepts it in writing.
- The archive procedure below keeps the source, the evidence, and the decision records available.

A departing maintainer hands over every credential through the custody procedure, and the remaining maintainers rotate any shared key.
A release cannot proceed while fewer than two maintainers hold release authority.

To archive the project, the custodian follows these steps.

1. Record the final commit ID of the default branch.
2. Run `node tools/fairpane.mjs source-archive <commit> <output-dir>` for that commit.
3. Copy the tar, the manifest, and a full clone of the Git history to at least two independent storage locations.
4. Confirm that each copy includes `engineering/evidence` and `engineering/decisions`.
5. Record each location and the manifest's tar SHA-256 in a final decision record.
6. Mark the public repository read-only, without deleting it.
7. Retire or hand over the release keys as the custody record directs.

No maintainer, custodian, or storage location exists yet.
ADR 0009 tracks the maintainer appointment and the custodian as `open` owner decisions.

## Adoption program

The first integrations cover a native C host, the direct Zig API, and the first-party Rust wrapper.
Fairpane's own browser is the first downstream application of the Rust wrapper.
TypeScript and Elixir exercise different lifetime and process boundaries.
Other wrappers join through the same published contract suite.
A showcase integration needs a real downstream workflow, not a screenshot alone.
Each integration records its qualification in a report from `docs/templates/downstream-integration.md`.
`docs/templates/downstream-integration.example.md` fills that template for the C smoke test.

The project collects migration issues and documents compatibility limits.
Performance comparisons preserve the workload and environment.
Release notes distinguish supported features from experimental features.

## Remaining owner decisions

The owner established the public repository and authorized continuous pushes to `master`.
The license policy and release identities remain open.
Name availability remains provisional.
Domain registration and trademark work are outside the agent's automatic authority.
These decisions block a public release, not local implementation or public development.
ADR 0009 lists every owner decision that a public release needs, with its status, what it blocks, and the evidence that would record it.

The owner selected Rust as the first-party wrapper language and engine-rendered browser chrome, as ADR 0004 records.
