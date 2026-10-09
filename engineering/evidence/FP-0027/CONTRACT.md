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

## Revision 1

Base: the commit that freezes this revision, whose parent is `f95fab6`.
Source finding: `engineering/evidence/FP-0027/reviews/review-1-reject.json`.
Every section above stays in force except where this revision replaces it.
The root integrator implements this revision.

### Identifiers

SLSA Provenance version 1 requires `runDetails.builder.id` to be a URI.
The builder ID becomes `https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#unsigned-local-builder-1`.
ADR 0009 gains the section "Unsigned local builder 1", which states that no verifier trusts this builder.
ADR 0009 states that the meaning of build type 1 and of unsigned local builder 1 never changes.
A changed definition gets a new numbered section and anchor, and an existing statement keeps the anchor that it names.

### Source archive inputs

The manifest records `git_version`, the first line of `git --version` from the same hardened Git calls.
ADR 0009 and `tools/README.md` state that the tar depends on the commit and on the Git implementation that wrote it.
Configuration cannot change the bytes, but another Git version may.
The tar itself is not committed as evidence, because `source-archive` regenerates it and the manifest and the log record its size and SHA-256.

### Provenance toolchain fields

ADR 0009 states that the toolchain fields come from the commit's lock and from the host that runs `provenance`, not from an observation of the build.
A protected runner must bind them to the build that it performs.

### Reproducibility report

The report's top-level `build_command` becomes `build_type_command`, the canonical command of build type 1.
Each entry of `builds` keeps the exact arguments of its tree.

### Revision 1 test cases

- Case 1 also expects the manifest's `git_version` to start with `git version `.
- Case 4 expects the URI builder ID, and both `buildType` and `builder.id` parse as absolute `https:` URLs.

### Revision 1 evidence

The integrator records these runs under `engineering/evidence/FP-0027/raw/` on the commit that implements this revision.

1. `HEAD`, a status that includes ignored files for every source root, `git --version`, `node --version`, and the locked compiler's version.
2. `source-archive` with an output directory outside the repository, and a copy of the manifest that it writes.
3. A release build in a directory that did not exist before.
   The log records the tar's SHA-256 before extraction, the extraction, and the build with fresh local and global caches inside that directory.
4. `provenance` for every file that the release build installs, and a copy of the statement.
5. `reproduce-check`, whatever its result.
6. `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0027/gates`.

## Revision 2

Base: the commit that freezes this revision.
Source finding: `engineering/evidence/FP-0027/reviews/review-2-reject.json`.
Every section above stays in force except where this revision replaces it.
The root integrator implements this revision.

### Changes

- ADR 0009's "Build type 1" section documents the `externalParameters` schema: `source.commit`, `source.tree`, `command`, `toolchain.zig_version`, `toolchain.platform`, and `toolchain.archive_sha256`.
- Step 4 of the release procedure in `tools/README.md` states the fresh caches, the removal of inherited `ZIG_*` variables, and the tar digest check before extraction.
- Case 5 also asserts that the report's `build_type_command` equals `BUILD_COMMAND`.
- The README row for `raw/reproduce-diagnosis.log` states what the log shows, without claiming a fresh build.

### Revision 2 evidence

The integrator replaces the revision 1 release records with one uninterrupted sequence on the commit that implements this revision, from the main checkout, with no commit or source edit during the sequence.
The revision 1 records stay in place as superseded records.

1. `HEAD`, a status that includes ignored files for every source root, `git --version`, `node --version`, the locked compiler's version, and the list of inherited `ZIG_*` variables, which must be empty.
2. `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0027/gates`.
3. `source-archive` into a new directory outside the repository, with `sha256sum` of its tar and manifest.
4. The release build in a directory that did not exist before: the tar's SHA-256 before extraction, the extraction, the build with only the two cache overrides added, a recursive listing of the installed files, and `sha256sum` of each installed file, all recorded before any later step.
5. `provenance` for every listed file, and the copies of the statement and the manifest with `sha256sum` of each copy beside its source.
6. `reproduce-check`.
7. `HEAD` and the status again after the last step.

A step that stops responding stays in the record as its own log with the time and the way it was stopped.
