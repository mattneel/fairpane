# FP-0027 evidence

## Scope

Task `FP-0027` establishes reproducible release records and stewardship requirements.
The frozen contract is `engineering/evidence/FP-0027/CONTRACT.md`, based on commit `97aa319`.
The isolated `fairpane-core` worker `FP0027Releases` wrote the patch on a work tree at commit `ba3a352bbc5123599d3183fd7e4306540636bea5`.
The worker did not commit, so every real run below names that commit, not the implementation commit.

## Acceptance criteria

| Contract item | Evidence |
| --- | --- |
| Owner decisions in ADR 0009 | `engineering/decisions/0009-release-and-stewardship.md`; case 7. |
| `source-archive` | `tools/release.mjs`; cases 1, 2, and 3, and `raw/source-archive.log`. |
| `provenance` | `tools/release.mjs`; case 4, and `raw/provenance.log`. |
| `reproduce-check` | `tools/release.mjs`; cases 5 and 6, and `raw/reproduce-check.log`. |
| Release signatures | The "Release signatures" section of ADR 0009. No key, signature, or signing command exists. |
| Security reporting and succession | `docs/SECURITY.md` and the "Succession and archival" section of `docs/ADOPTION_AND_GOVERNANCE.md`. The root `SECURITY.md` wording is in the worker's report for the integrator. |
| Downstream qualification templates | `docs/templates/downstream-integration.md` and `docs/templates/downstream-integration.example.md`. |

## Worker records

| Log | Result |
| --- | --- |
| `raw/tests-before.log` | Exit status 1 with 155 of 162 controller tests passing. Cases 1 through 6 fail because `tools/release.mjs` does not exist, and case 7 fails because ADR 0009 does not exist. |
| `raw/tests-after-attempt-1.log` | Exit status 1 with 163 of 164 passing. The corpus-verify controller fixture copied the controller modules without `release.mjs`, which `tools/fairpane.mjs` now imports. |
| `raw/tests-after.log` | Exit status 0 with 164 of 164 passing, including the seven contract cases and two added failure-path cases. |
| `raw/source-archive.log` | `source-archive` exits with status 0 for commit `ba3a352`, tree `dd445a3`, 771 files, and a 5611520-byte tar with SHA-256 `8a75c1c66e63ee333999fb035b1d6ec1ad90c30dcf58f832a467e8c740db9213`. |
| `raw/fairpane-ba3a352bbc5123599d3183fd7e4306540636bea5.manifest.json` | The manifest of that run, copied from the temporary output directory outside the repository, and not signed. The integrator kept the 5611520-byte tar out of Git, because it duplicates the repository and `source-archive ba3a352` reproduces it; the manifest and the log record its SHA-256. |
| `raw/reproduce-check-attempt-1.log` | Exit status 1 with result `error`. The locked compiler's build runner rejected the `--global-cache-dir` argument of the first implementation, which now passes the fresh caches through `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR`. |
| `raw/reproduce-check.log` | Exit status 1 with result `different`. Both builds exit with status 0. `include/fairpane.h` matches, and `lib/fairpane.lib` differs between the two work trees. Both work trees were removed. |
| `raw/release-build.log` | The source tar extracted into `out/fp0027-build/a` and built there with `zig build -Doptimize=ReleaseSafe` and fresh caches, with exit status 0. |
| `raw/provenance.log` | `provenance` exits with status 0 for that build's `fairpane.lib`, SHA-256 `6682cffca19ad0109ca8303940a4ff98e7aedbab4fbed76f0d45ed0ff3678895`, and `fairpane.h`, with the builder `fairpane-local-unsigned`. |
| `raw/reproduce-diagnosis.log` | A second fresh extraction and build at the same path `out/fp0027-build/a` produces the same `fairpane.lib` digest, and the library contains the build directory name 8 times. |

## Open result

The release build of commit `ba3a352` is not reproducible across build paths.
Two fresh builds at one path produce identical bytes, and builds at different paths produce different static libraries that embed their build path.
`reproduce-check` reports this as `different` by design.
A fix belongs in the build configuration, such as debug-information path mapping, which is outside this task's writable paths.
Task `FP-0066` owns that fix.

## Integration

The integrator applied the patch without conflicts, removed the reproducible tar from the change, applied the root `SECURITY.md` wording that the worker reported, and stated in both security documents that the owner approves the response targets with the reporting channel.
The integration commit is `493edb6`.
`raw/integration-binding.log` records `HEAD` `493edb6` and an empty status, including ignored files, for every source root.

- `gates/2026-10-09T09-33-31-406Z-repo-check-fea293bf.json`
- `gates/2026-10-09T09-33-31-671Z-controller-test-41678707.json`, with 167 of 167 controller tests.

`raw/integration-bun.log` records Bun with 167 of 167 controller tests.

## Revision 1

Review 1 rejected `493edb6` because the real release records ran on `ba3a352`, which predates the implementation.
The root integrator implemented contract revision 1 in `ea3433a`, as the revision assigns.

- `tools/release.mjs` names the builder `https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#unsigned-local-builder-1`, a URI as SLSA Provenance version 1 requires.
- The manifest records `git_version`, because the tar depends on the Git implementation as well as the commit.
- The reproducibility report names its canonical command `build_type_command`.
- ADR 0009 states that the meanings of build type 1 and unsigned local builder 1 never change, that the toolchain fields come from the lock and the recording host, and what the tar depends on; `tools/README.md` repeats the user-facing parts.

| Log | RESULT |
| --- | --- |
| `raw/tests-before-r1.log` | On `3531b1a` with the new expectations, `node tools/release.test.mjs` exits with status 1: cases 1 and 4 fail and the other seven pass. |
| `raw/tests-after-r1.log` | On the implementation, the same command exits with status 0 with 9 of 9 passing. |
| `raw/r1-binding.log` | `HEAD` `ea3433a`, an empty status including ignored files for every source root, Git 2.54.0.windows.1, Node v26.7.0, and Zig 0.18.0-dev.120+9fe22a29b. Later records show `HEAD` `60c0c90`, an empty diff of `tools/release.mjs`, `tools/attest.mjs`, `tools/lib.mjs`, and `tools/fairpane.mjs` from `ea3433a`, and an empty status after the last run. |
| `gates/2026-10-09T09-50-13-341Z-repo-check-20faffbf.json` | `pass` on `ea3433a`. |
| `gates/2026-10-09T09-50-13-648Z-controller-test-fc421308.json` | `pass` on `ea3433a`. |
| `raw/r1-source-archive.log` | `source-archive ea3433a` into a directory outside the repository exits with status 0: tree `25e56b0`, 917 files, a 10373120-byte tar with SHA-256 `d5514c5e05f37527b8438459f0bc3e48d8e12cae5bb6e2e9d39888d64a5c4635`, and a manifest with SHA-256 `9fa150fb7b35f428f83cfbcd35c67bac2aeb0bdc2413962d3cf7005a062f0475`. GNU `sha256sum` agrees with both. |
| `raw/fairpane-ea3433abcc09ef22dec71b4e03e697e61f21cb16.manifest.json` | A copy of that manifest, with the same SHA-256. Its `git_version` is `git version 2.54.0.windows.1`. The tar is not stored, as revision 1 states. |
| `raw/r1-release-build.log` | A non-recursive creation of the new directory `out/fp0027-r1-release`, the tar's SHA-256 before extraction, the extraction, and `zig build -Doptimize=ReleaseSafe` with fresh caches inside that directory, each with exit status 0. |
| `raw/r1-provenance.log` | `provenance ea3433a` for `include/fairpane.h` and `lib/fairpane.lib`, the only installed files, exits with status 0. The subjects' SHA-256 values, `845b602f…` and `45afa4da…`, equal `sha256sum` of the installed files. |
| `raw/provenance-ea3433abcc09ef22dec71b4e03e697e61f21cb16.json` | The statement from that log, reformatted with two-space indentation and not signed. |
| `raw/r1-reproduce-check.log` | `reproduce-check ea3433a` exits with status 1 with result `different`: only `lib/fairpane.lib` differs between the two work trees, and both trees were removed. Task `FP-0066` owns path-independent builds. |

The first attempt ran every step in one shell job, which stopped responding after the release build while it listed the installed files.
The integrator stopped that job and ran `provenance`, `reproduce-check`, and the final status as separate commands; the logs contain only completed commands.
Commits after `ea3433a` changed no release tool, and every release command takes the commit ID as an argument.
