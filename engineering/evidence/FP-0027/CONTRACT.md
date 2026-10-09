# FP-0027 task contract

## Identity

Task ID: `FP-0027`, "Establish reproducible releases and stewardship".
Workstream: `stewardship`.
Base: commit `97aa319`.
Prerequisites: `FP-0002` and `FP-0003`, accepted.
Assigned role: `fairpane-core`.

## Sources

- SLSA v1.0 provenance and build track: <https://slsa.dev/spec/v1.0/provenance> and <https://slsa.dev/spec/v1.0/levels>.
- in-toto attestation statement v1: <https://github.com/in-toto/attestation/blob/main/spec/v1/statement.md>.
- Reproducible Builds definitions and `SOURCE_DATE_EPOCH`: <https://reproducible-builds.org/docs/definition/> and <https://reproducible-builds.org/docs/source-date-epoch/>.
- `git archive` and its tar output: <https://git-scm.com/docs/git-archive>.
- GitHub private vulnerability reporting: <https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository>.
- Repository records: `LICENSE-DECISION.md`, `docs/ADOPTION_AND_GOVERNANCE.md`, `docs/SECURITY.md`, `SECURITY.md`, and `engineering/decisions/0002-qualification-boundary.md`.

## Behavior

### Owner decisions

`engineering/decisions/0009-release-and-stewardship.md` lists every owner decision that a public release needs, each with its status, what it blocks, and the evidence that would record it.
The list contains exactly these decisions: the outbound license, the copyright and attribution notice, the contribution provenance rule (a sign-off or an agreement), the release signing identity and key custody, the project and product names, the domain, the private security reporting channel, the initial maintainers and their appointment record, the succession and archival custodian, and the release approval authority.
The record states that no decision is made by the agent, and that each stays `open` until an owner record exists.

### Source archives

`node tools/fairpane.mjs source-archive <commit> <output-dir>` writes `fairpane-<commit>.tar` and `fairpane-<commit>.manifest.json` for one full commit ID.
The tar comes from `git archive --format=tar --prefix=fairpane-<commit>/ <commit>`, run without replace objects and without inherited `GIT_*` variables, so its content depends only on the commit.
The manifest lists every regular file and symbolic link of the commit's tree with its path, mode, size, and SHA-256, sorted by path bytes, and it records the commit ID, the tree ID, the tar's SHA-256, and the manifest format `fairpane-source-manifest` version 1.
A short or abbreviated commit name, a ref name, a missing commit, and an output directory inside the repository are rejected before any write.

### Build provenance

`node tools/fairpane.mjs provenance <commit> <artifact>...` writes an unsigned in-toto statement version 1 with the SLSA provenance predicate version 1 to standard output.
Its subjects are the artifacts with their SHA-256 digests.
Its build definition names the commit, the tree, the Zig lock's version and archive digest, and the exact build command.
Its run details name the builder as `fairpane-local-unsigned`, which no verifier treats as a trusted builder.
The statement is a record format for a later protected runner, not an attestation, and its README text says so.

### Reproducibility check

`node tools/fairpane.mjs reproduce-check <commit>` creates two fresh work trees of the commit under `out/`, runs `zig build -Doptimize=ReleaseSafe --prefix <tree>/zig-out` with the locked compiler and separate fresh cache directories in each, and compares the SHA-256 of every installed file.
It reports `reproducible` when every file matches, and `different` with the differing paths otherwise, and it exits with status 1 for `different`.
It removes both work trees afterward, and a removal failure is part of the report.

### Signatures

ADR 0009 defines release signatures as Ed25519 signatures over the source manifest and the provenance statement, verified by the ADR 0002 verifier with a trust policy outside the candidate.
No key exists in this task, because the signing identity is an owner decision.

### Security reporting and succession

`docs/SECURITY.md` and `SECURITY.md` state the requirements for a private reporting channel, triage severities, coordinated disclosure timing, and patch release, and they state that the channel stays an owner decision.
`docs/ADOPTION_AND_GOVERNANCE.md` states the maintainer succession and archival requirements: at least two maintainers with release authority before a release, a written custodian for the repository and keys, and an archive procedure that keeps the source, evidence, and decision records available.

### Downstream qualification templates

`docs/templates/downstream-integration.md` is a template for a downstream integration report: the integration and its version, the Fairpane commit, the ABI revision, the wrapper and its version, the workflow that the integration exercises, the failure scenarios from `api/failure-scenarios.json` that it ran, the evidence records, and the open limits.
`docs/templates/downstream-integration.example.md` fills the template for the C smoke test in `tests/c/abi_smoke.c`, from the recorded FP-0021 evidence only.

## Exact test cases

The controller cases live in a module that `tools/selftest.mjs` registers.

1. Two `source-archive` runs on one fixture commit produce byte-identical tar and manifest files, and the manifest's tar digest equals the tar's SHA-256.
2. A fixture commit with a changed file, an added file, a removed file, and a changed mode each changes the manifest, and the manifest lists exactly the tree's files with their sizes and digests.
3. `source-archive` rejects an abbreviated ID, a ref name, a missing commit, and an output directory inside the fixture repository, and it writes nothing for each.
4. `provenance` writes a statement whose subjects equal the given artifacts' digests, whose build definition names the commit, tree, and lock digest, and whose builder ID is `fairpane-local-unsigned`.
5. `reproduce-check` on a fixture repository whose build writes a fixed file reports `reproducible`, and on a fixture whose build writes the current time reports `different` with that path and exits with status 1.
6. `reproduce-check` removes both work trees, and a forced removal failure appears in the report.
7. ADR 0009 lists exactly the ten owner decisions, each with the status `open`.

## Evidence

Record `tests-before.log`, `tests-after.log`, and a real `reproduce-check` run on the implementation commit under `engineering/evidence/FP-0027/raw/`.
Record a `source-archive` run and a `provenance` run for the implementation commit, and keep their outputs under `engineering/evidence/FP-0027/raw/`, without signatures.
The integrator records `HEAD` and a status that includes ignored files for every source root before it runs `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0027/gates`.

## Authority

Writable paths: `tools`, `docs`, `engineering/decisions`, and `engineering/evidence`.
The root `SECURITY.md` is outside these paths, so the integrator applies its wording from the task's report.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No license, legal identity, signing key, security contact, domain, or maintainer appointment is created or invented.
- No release is published, and no artifact is uploaded.
- No protected runner exists in this task.
