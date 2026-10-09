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
