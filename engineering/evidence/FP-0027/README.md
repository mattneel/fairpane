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
| `raw/reproduce-diagnosis.log` | A second extraction and build in the existing path `out/fp0027-build/a` produces the same `fairpane.lib` digest, and the library contains the build directory name 8 times. The log records no removal of the earlier tree or its caches, so it does not show a fresh build. |

## Open result

The release build of commit `ba3a352` is not reproducible across build paths.
Two builds at one path, the second in the existing work tree, produce identical bytes, and builds at different paths produce different static libraries that embed their build path.
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
| `raw/fairpane-ea3433abcc09ef22dec71b4e03e697e61f21cb16.manifest.json` | A copy of that manifest, whose `git_version` is `git version 2.54.0.windows.1`. No revision 1 log records the copy's digest. The tar is not stored, as revision 1 states. |
| `raw/r1-release-build.log` | A non-recursive creation of the new directory `out/fp0027-r1-release`, the tar's SHA-256 before extraction, the extraction, and `zig build -Doptimize=ReleaseSafe` with fresh caches inside that directory, each with exit status 0. |
| `raw/r1-provenance.log` | `provenance ea3433a` for `include/fairpane.h` and `lib/fairpane.lib` exits with status 0. No revision 1 log records the installed file set or the installed files' digests. |
| `raw/provenance-ea3433abcc09ef22dec71b4e03e697e61f21cb16.json` | The statement from that log, reformatted with two-space indentation and not signed. |
| `raw/r1-reproduce-check.log` | `reproduce-check ea3433a` exits with status 1 with result `different`: only `lib/fairpane.lib` differs between the two work trees, and both trees were removed. Task `FP-0066` owns path-independent builds. |

The first attempt ran every step in one background shell job.
The release build in that job ended at 09:51:55Z, and the job then stopped responding while a bash process substitution, which was not a recorded command, listed the installed files.
The integrator cancelled the job through the harness shortly before 10:10:32Z and ran `provenance`, `reproduce-check`, and the final status from a checkout at `60c0c90`, with an empty diff of the release tools from `ea3433a`.
Review 2 rejected these records because of the unrecorded claims above, and revision 2 supersedes them.

## Revision 2

Review 2 rejected the revision 1 records because the README claimed the installed file set and several digest matches without recorded output, and because `provenance` and `reproduce-check` ran from a later checkout.
The root integrator implemented contract revision 2 in `c0cbf85`.

- ADR 0009 lists the `externalParameters` of a build type 1 statement.
- Step 4 of the release procedure in `tools/README.md` states the tar digest check, the removal of inherited `ZIG_*` variables, and the fresh caches.
- Case 5 asserts the report's `build_type_command`.
- The worker record above no longer calls the diagnosis build fresh.

Every revision 2 record ran in one uninterrupted sequence from the main checkout at `c0cbf85`, with no commit or source edit during it.
No step stopped responding.

| Log | RESULT |
| --- | --- |
| `raw/tests-r2.log` | Before the commit, `HEAD` `3f45a3b`, the diff of the revision 2 edits, and `node tools/release.test.mjs` with 9 of 9 passing. |
| `raw/r2-binding.log` | `HEAD` `c0cbf85`, an empty status including ignored files for every source root, Git 2.54.0.windows.1, Node v26.7.0, Zig 0.18.0-dev.120+9fe22a29b, and an empty list `[]` of inherited `ZIG_*` variables. After the last step, `HEAD` is still `c0cbf85` and the status is still empty. |
| `gates/2026-10-09T10-24-25-369Z-repo-check-203be9dd.json` | `pass` on `c0cbf85`. |
| `gates/2026-10-09T10-24-25-657Z-controller-test-ccd6d13d.json` | `pass` on `c0cbf85`. |
| `raw/r2-source-archive.log` | A new directory outside the repository, then `source-archive c0cbf85` with exit status 0: tree `c7ed6f8`, 966 files, an 11253760-byte tar with SHA-256 `cf304d8cd797413c79caaf40f53b9788d6f44a91e7eef7bcbb9db5914b445a81`, and a manifest with SHA-256 `7e6b2b1dd0548e4e66435077757fc700b1c73450e49bfe5fecc07c95a086bf8a`. GNU `sha256sum` agrees with both. |
| `raw/r2-release-build.log` | A non-recursive creation of the new directory `out/fp0027-r2-release`, the tar's SHA-256 `cf304d8c…` before extraction, the extraction, the build with only the two cache overrides inside that directory, a recursive listing that names exactly `include/fairpane.h` and `lib/fairpane.lib`, and their SHA-256 values `845b602f10c46a62bc29897a649200bcef8e57a477cff23bb91bc170d216b410` and `ba9a5ba9fef4bfcdad94dcf9a66c043d304f6dbd34b10b69d997a1872858e6e7`, all with exit status 0. |
| `raw/r2-provenance.log` | `provenance c0cbf85` for both listed files, with subjects equal to the recorded digests; a check that `raw/provenance-c0cbf85c65a51892318c7f4076d3a9b3e8842907.json` holds the same statement, which prints `equal`; and `sha256sum` of the manifest and its copy `raw/fairpane-c0cbf85c65a51892318c7f4076d3a9b3e8842907.manifest.json`, both `7e6b2b1d…`. |
| `raw/r2-reproduce-check.log` | `reproduce-check c0cbf85` exits with status 1 with result `different`: only `lib/fairpane.lib` differs between the two work trees, and both trees were removed. Task `FP-0066` owns path-independent builds. |
