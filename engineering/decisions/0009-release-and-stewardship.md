# ADR 0009: Reproducible releases and stewardship

Status: proposed until `fairpane-review` accepts task `FP-0027`.
Owner: the root integrator.
Date: 2026-10-09.
Related tasks: `FP-0002`, `FP-0003`, `FP-0027`, `FP-0033`, `FP-0066`.

## Problem

A public release needs a source artifact that anyone can check against a commit.
It needs a record of how each binary was built, a check that the build reproduces, and signatures from an accountable identity.
It also needs people who answer security reports and keep the project available.
The repository has none of these records yet.
Several of them are owner decisions, and the agent must not make them.

## Decision

### Source archives

`node tools/fairpane.mjs source-archive <commit> <output-dir>` writes `fairpane-<commit>.tar` and `fairpane-<commit>.manifest.json`.
The commit must be a full 40-hex commit ID of an existing commit object, as ADR 0002 requires for a candidate.
An abbreviated ID, a ref name, a missing commit, and an output directory inside the repository or its Git directory fail before any write.

The tar is the output of `git archive --format=tar --prefix=fairpane-<commit>/ <commit>`.
Git runs through the hardened calls of `tools/attest.mjs`, without replace objects, inherited `GIT_*` variables, or prompts.
The command also sets `core.autocrlf=false`, `core.eol=lf`, and `tar.umask=0002`, because user or repository configuration would otherwise change line ends or tar permissions.
`git archive` records the commit time as each entry's modification time and the commit ID in a global pax header.
The commit time serves as the archive's `SOURCE_DATE_EPOCH`, so no clock value enters the tar.
The tar therefore depends on the commit and on the Git implementation that writes it.
Configuration cannot change its bytes, but another Git version may.

The manifest has the format `fairpane-source-manifest`, version 1.
It records the commit ID, the tree ID, `git_version`, which is the first line of `git --version`, and the tar's name, size, and SHA-256.
It lists every regular file and symbolic link of the commit's tree with its path, Git mode, size, and SHA-256, sorted by UTF-8 path bytes.
Contents come from the Git object database, never from the working tree.
A submodule entry has no content in the archive, so the manifest omits it.
A tree path that is not valid UTF-8 fails, because a JSON manifest cannot name it exactly.

The command parses the tar before it writes anything.
Every tar entry must lie under the prefix and match its manifest entry in type, content, size, and executable bit, and every manifest entry must appear once.
An `export-ignore` or `export-subst` attribute, an attribute file outside the commit, or a line-end conversion therefore fails the command instead of producing a tar that the manifest does not describe.

### Build type 1

A build of type 1 starts from the extracted source archive of one commit.
It runs `zig build -Doptimize=ReleaseSafe --prefix zig-out` from the archive root with the compiler that the commit's `toolchains/zig.lock.json` names for the host platform.
The build uses fresh local and global Zig caches, set through `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR`, and no other inherited `ZIG_*` variable.
Its outputs are the files installed under `zig-out`.

A provenance statement of build type 1 has these `externalParameters`.

| Field | Value |
| --- | --- |
| `source.commit` | The full 40-hex commit ID of the source archive. |
| `source.tree` | The commit's tree ID. |
| `command` | `["zig", "build", "-Doptimize=ReleaseSafe", "--prefix", "zig-out"]`, run from the archive root. |
| `toolchain.zig_version` | The `version` of the commit's `toolchains/zig.lock.json`. |
| `toolchain.platform` | The lock's platform key for the host that records the statement, such as `x86_64-windows`. |
| `toolchain.archive_sha256` | The lock's SHA-256 of that platform's compiler archive. |

Its `internalParameters` object is empty.

The URI `https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#build-type-1` names this definition in a provenance statement.
The meaning of build type 1 never changes.
A changed build definition gets a new numbered section, such as build type 2, with its own anchor, and an existing statement keeps the anchor that it names.
The command names the procedure, and the commit's `build.zig` defines what that procedure installs.
A change to `build.zig`, such as the library rules below, therefore changes the outputs of later commits but not the meaning of build type 1.

### Library rules

`zig build` installs the static library under two rules, which `build.zig` implements in `libraryArchive`.

1. A library built in a mode other than Debug has no debug information, so no path of the build tree or of the compiler installation enters it.
   A Debug library keeps its debug information.
2. The installed library has exactly one member, the compiled object, named by its base name without a directory.
   The name is `fairpane_zcu.obj` for Windows targets and `fairpane_zcu.o` for other targets.
   The locked compiler's archiver, `zig ar`, writes the library in deterministic mode, so every member header has a zero time stamp, owner, and group.
   COFF targets get the COFF layout, Mach-O targets get the Darwin layout, and other targets get the GNU layout.
   No third-party program joins the build.

These measurements of the ReleaseSafe library on Windows with the locked compiler led to the rules.
`engineering/evidence/FP-0066/raw/probe.log` and `engineering/evidence/FP-0066/raw/strip-experiment.log` record them.

- The library of the FP-0027 revision 2 release build held one member, `.zig-cache\o\61c2b72ff156fe963e2d6fc2510b6176\fairpane_zcu.obj`.
  Its object contained the build directory name 5 times, in CodeView debug information that names absolute source paths.
  The same debug information names the compiler's `lib\std` directory, so the bytes also depended on where the compiler is installed.
- `zig build-lib -static -OReleaseSafe` of `src/root.zig` at two directories gave different libraries, with and without `-fstrip`.
  With `-fno-strip`, each library contained its directory name 5 times.
  With `-fstrip`, neither library contained its directory name, and the two extracted objects were byte-identical, with SHA-256 `9dccdf15a05010a18e9d52f462d6bc354aae52e87c66d216f0c235f3139f1246`.
  The stripped libraries still differed, because each member name held a cache directory, such as `cache\tmp\776c0874238e8dbc\fairpane_zcu.obj`.
- The locked compiler offers `-fstrip` and `-fno-strip` but no option that maps or removes a source path prefix.

`engineering/evidence/FP-0066/` records the effect of the rules on the same host.
Before them, the ReleaseSafe library had 3,053,734 bytes, and its member name held its cache directory.
After them, the ReleaseSafe library has 706,412 bytes, the ReleaseFast library 25,708 bytes, and the ReleaseSmall library 25,514 bytes.
Each of the three has the one member `fairpane_zcu.obj` and exports every `fp_` function of the ABI schema.
On WSL Ubuntu with the locked Linux compiler, the ReleaseSafe library has 644,396 bytes, the one member `fairpane_zcu.o`, and every `fp_` function.

A release's debug information is out of scope until a later task defines a reproducible form for it.
Such a form needs paths that depend on neither the build directory nor the compiler installation.

### Build provenance

`node tools/fairpane.mjs provenance <commit> <artifact>...` writes an in-toto Statement version 1 with the SLSA Provenance version 1 predicate to standard output.
Its subjects are the artifacts, each named by its file name with its SHA-256 digest.
Its build definition names build type 1, the commit, the tree, the build command, and the Zig version, host platform, and archive digest from the commit's own lock.
These toolchain fields come from the commit's lock and from the host that runs `provenance`, not from an observation of the build.
A protected runner must bind them to the build that it performs.
Its resolved dependencies name the source by `gitCommit` and `gitTree` digests and the compiler archive by its locked URL and SHA-256.
Its run details name unsigned local builder 1.

The statement is unsigned.
It is a record format for a later protected runner, not an attestation.
A protected runner replaces the builder ID with its own and signs the statement as the section on release signatures describes.

### Unsigned local builder 1

The URI `https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#unsigned-local-builder-1` is the builder ID of a statement that `provenance` writes in an unprotected workspace.
SLSA Provenance version 1 requires a builder ID to be a URI, and this anchor gives the ID a fixed meaning.
Any workspace writer can produce a statement with this builder ID, so no verifier trusts it.
The meaning of this anchor never changes, and a changed definition gets a new numbered section.

### Reproducibility check

`node tools/fairpane.mjs reproduce-check <commit>` builds the source archive of a full commit ID in memory.
It extracts the archive into two fresh work trees under `out/reproduce/`.
In each tree, it runs `zig build -Doptimize=ReleaseSafe --prefix <tree>/zig-out` with the locked compiler.
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` name fresh cache directories inside that tree, because the locked compiler's build runner rejects a `--global-cache-dir` argument.
It then compares the SHA-256 of every installed file.
The report's `build_type_command` is the canonical command of build type 1, and each entry of `builds` keeps the exact arguments of its tree.

The result is `reproducible` when the trees installed the same paths with the same digests, and the command exits with status 0 only then.
The result is `different`, with the differing paths, when any path or digest differs, and the command exits with status 1.
The result is `error` when an extraction or a build fails or when the build installs no file, and the command exits with status 1.
The command removes both work trees afterward.
A removal failure appears in the report's `removal` field and makes the command exit with status 1.

The work trees use different paths on purpose.
A build output that embeds its build path is a reproducibility defect that this check must detect, not hide.
The check uses the extracted source archive, not a Git checkout, so it builds exactly the bytes that a release publishes and runs no repository hook.

### Release signatures

A release signature is an Ed25519 signature over the exact bytes of one release record: the source manifest file or the provenance statement file.
Each signature record names the key ID, the algorithm `ed25519`, the signed file name, its SHA-256, and the base64 signature value.
The ADR 0002 verifier checks it with `decodePublicKey` and `verifyBytes` from `tools/attest.mjs`.
The verifier reads the keys from a release trust policy with the ADR 0002 trust-policy schema, loaded through `loadTrustPolicy` from outside the candidate repository and its Git directory.
The release trust policy is a separate file from the runner trust policy, so a runner key cannot sign a release and a release key cannot sign a test result.

No key exists in this task, because the release signing identity and its custody are owner decisions.
No command signs a record, and no signature file exists in the repository.

## Owner decisions

A public release needs each of these decisions.
The agent makes none of these decisions.
Each decision stays `open` until an owner record exists.
An owner record is a committed record of the owner's own answer, such as an owner-answers log in the task's evidence directory, that the integrator cites when it changes a row.

| Decision | Status | Blocks | Evidence that records it |
| --- | --- | --- | --- |
| Outbound license | `open` | Every public release, the `LICENSE` file, and the license decision in the qualification policy. | The owner's selection in `LICENSE-DECISION.md`, with the exact official license text committed as `LICENSE`. |
| Copyright and attribution notice | `open` | The copyright and attribution text in source archives, binaries, and release notes. | An owner record of the copyright holders and the attribution wording, without inferred ownership. |
| Contribution provenance rule | `open` | Accepting outside contributions under a recorded rule, either a sign-off such as the Developer Certificate of Origin or a contributor agreement. | The owner's rule in `CONTRIBUTING.md` and a check that enforces it on each contribution. |
| Release signing identity and key custody | `open` | Signed source manifests and provenance statements, and the release trust policy. | An owner record of the signing identity, the key holders, the custody and rotation procedure, and the public keys in a release trust policy stored outside the repository. |
| Project and product names | `open` | Use of the project and product names in release artifacts, packages, and announcements. | An owner record of the chosen names and their clearance result. |
| Domain | `open` | A project website, project email addresses, and project URLs in release metadata. | An owner record of the registered domain and the account that controls it. |
| Private security reporting channel | `open` | The contact in `SECURITY.md` and every browser release. | An owner record that enables the channel, such as GitHub private vulnerability reporting, and names who receives reports. |
| Initial maintainers and appointment record | `open` | Release authority, module ownership, and independent review assignments. | An owner appointment record that names each maintainer and the scope of their authority. |
| Succession and archival custodian | `open` | Continuity of the repository, the release keys, the evidence, and the decision records. | A written designation of the custodian, with the custodian's acceptance and the archive procedure of `docs/ADOPTION_AND_GOVERNANCE.md`. |
| Release approval authority | `open` | Publishing any release. | An owner record that names who approves a release and which approvals a release needs. |

## Consequences

`release-check` stays fail-closed.
Source archives, manifests, provenance statements, and reproducibility reports are local records, not release qualification.
A release still needs the frozen profile, the signed result set, the approvals that `docs/QUALIFICATION.md` lists, and every owner decision above.
A protected runner, which `FP-0033` or a later task establishes, can produce the same records under its own builder ID and sign them.

## Rejected alternatives

- A hosted archive download comes from a service outside the project's control, so its bytes cannot be checked against a recorded procedure.
- Building twice in one directory would hide an output that embeds its build path.
- A Git checkout for the reproducibility check would apply checkout configuration and run hooks, and it would not build the published archive bytes.
- A key stored in the repository gives every workspace writer the key, as ADR 0002 records.
- A placeholder license, contact, domain, or maintainer would present an owner decision as made.
- Rewriting the paths in a release library's debug information would need a tool that edits CodeView and DWARF records, because the locked compiler cannot map a path prefix, and the result would still not be a defined reproducible form.
- Installing the compiler's own static library would keep a cache directory in its member name.

## Sources

- SLSA v1.0 provenance: <https://slsa.dev/spec/v1.0/provenance>.
- SLSA v1.0 levels: <https://slsa.dev/spec/v1.0/levels>.
- in-toto attestation Statement v1: <https://github.com/in-toto/attestation/blob/main/spec/v1/statement.md>.
- Reproducible Builds definition: <https://reproducible-builds.org/docs/definition/>.
- `SOURCE_DATE_EPOCH`: <https://reproducible-builds.org/docs/source-date-epoch/>.
- `git archive`: <https://git-scm.com/docs/git-archive>.
- GitHub private vulnerability reporting: <https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository>.
- Contract and evidence: `engineering/evidence/FP-0027/`.
- Library rules: `engineering/evidence/FP-0066/`.
