# FP-0001 baseline evidence

## Scope

This record covers task `FP-0001` on the first Windows development host.
It qualifies bootstrap behavior only.
It is not browser, JavaScript, or conformance qualification.
All results below come from commands executed on October 8, 2026.

## Host and tools

| Tool | Observed version | Source of the observation |
| --- | --- | --- |
| Operating system | Windows 11 Pro, release `10.0.26200`, x86_64 | `node tools/fairpane.mjs doctor`, `uname -a` |
| Node | `v26.7.0` at `C:\nvm4w\nodejs\node.exe` | `node --version`, doctor |
| Bun | `1.4.2` | `bun --version`, doctor |
| Git | `2.54.0.windows.1` | `git --version`, doctor |
| OMP | `18.8.6` at `C:\Users\requi\AppData\Local\omp\omp.exe` | `omp --version`, doctor |
| Windows PowerShell | `5.1.26100.9444` | `$PSVersionTable.PSVersion` |
| PowerShell | `7.6.6` | `$PSVersionTable.PSVersion` |
| Locked Zig | `0.18.0-dev.120+9fe22a29b` | `.tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-windows/zig.exe version` |
| Zig on `PATH` | `0.17.0-dev.2453+zigpp.35608841b` | `zig version`, doctor `path_zig` |

The `PATH` compiler is a different build and is not the pin.
No gate or evidence command in this record used it.

## Archive integrity

`sha256sum -c --quiet BOOTSTRAP_MANIFEST.sha256` exited with status 0 for all 86 entries.
The supplied `repo-check` and `controller-test` preparation receipts passed `evidence-check` against the extracted source.
The supplied `zig-test` preparation receipt failed `evidence-check` because it records a missing compiler.
That failure is the expected preparation result.

## Git history

No repository existed in `C:\src\fairpane` or any parent directory.
The global Git configuration in `C:/Users/requi/.gitconfig` supplies the owner identity `Matt Neel <m@neel.codes>`.
`git init` created the repository on the system default branch `master`.
Commit `89109be156eecd356ff59bf9d6508977e76a6b2b` records the verified archive without changes.
No remote exists, and no push occurred.

## Compiler installation

| Attempt | Command | Result |
| --- | --- | --- |
| 1 | `node tools/fairpane.mjs install-zig` | Failed with exit status 1. See `install-zig-attempt1.log`. |
| 2 | `node tools/fairpane.mjs install-zig` | Passed with exit status 0. See `install-zig-attempt2.log`. |

Attempt 1 downloaded the archive and passed the size check.
`Get-Zig.ps1` then failed because Windows PowerShell 5.1 did not recognize `Get-FileHash`.
The inherited `PSModulePath` listed PowerShell 7 module directories before the Windows PowerShell directory.
Windows PowerShell 5.1 therefore resolved `Microsoft.PowerShell.Utility` version `7.0.0.0`, which supports only the Core edition.
The installer deleted the unverified partial download, as designed.

The repair computes SHA-256 through `System.Security.Cryptography.SHA256` in `scripts/Get-Zig.ps1`.
That method produced the same digest as `sha256sum` in Windows PowerShell 5.1 and PowerShell 7.6.6.
Attempt 2 installed the archive with size `102765659` and SHA-256 `a48ff20a7357640cf67ad7be819d3f988e9a5085362fe67dc9b94e02a42571ae`.
An independent `sha256sum` of `.tools/downloads/zig-x86_64-windows-0.18.0-dev.120+9fe22a29b.zip` produced the same digest.
The installer changed only `.tools` and did not change any global configuration.

## Pinned-compiler repairs

`zig fmt --check build.zig src` failed on `src/c_api.zig` with the locked compiler.
This master build's formatter rewrites the deprecated `@intFromEnum` builtin to `@backingInt`.
The locked `doc/langref.html` states that `@intFromEnum` is deprecated and names `@backingInt` as a replacement.
The repair replaces three `@intFromEnum` calls with `@backingInt`.
`build.zig` compiled with the locked compiler without changes.

The gates now set `ZIG_GLOBAL_CACHE_DIR` to `.zig-cache/global` inside the repository.
After the final gate run, `find "$LOCALAPPDATA/zig" -newer out/fp0001-gate-marker` listed zero entries.

## Final gate run

All receipts bind source digest `07ffd710165c580f937cb56005484f963e753e903c6896a8889bb7530342fc62` with 76 files.
All receipts bind policy digest `ec1505889dbe8cc3aef2fa1e6a9d9da2afd5a7f847fcbe23e1559761d35f3e91` with 12 files.
Each receipt passed `node tools/fairpane.mjs evidence-check` with `current_source: true` before this record was written.

| Gate | Result | Receipt in `receipts/` | Command exits |
| --- | --- | --- | --- |
| `repo-check` | pass | `2026-10-08T23-30-10-192Z-repo-check-fd2dba69.json` | 0 |
| `controller-test` | pass, 55 of 55 tests | `2026-10-08T23-30-10-347Z-controller-test-bd356877.json` | 0 |
| `zig-fmt` | pass | `2026-10-08T23-30-11-524Z-zig-fmt-82c82da5.json` | 0 |
| `zig-test` | pass | `2026-10-08T23-30-11-648Z-zig-test-75dc9a2d.json` | 0 |
| `zig-build` | pass | `2026-10-08T23-31-07-519Z-zig-build-37ecf4f3.json` | 0 |
| `c-abi` | pass | `2026-10-08T23-31-07-738Z-c-abi-586855dc.json` | 0, 0, 0 |
| `cross-windows-x86_64` | pass, compile only | `2026-10-08T23-31-16-657Z-cross-windows-x86_64-dd0b8d2f.json` | 0 |
| `cross-linux-aarch64` | pass, compile only | `2026-10-08T23-31-20-404Z-cross-linux-aarch64-1ced7d72.json` | 0 |
| `cross-macos-aarch64` | pass, compile only | `2026-10-08T23-31-24-531Z-cross-macos-aarch64-aed54ede.json` | 0 |

The `c-abi` gate built `fairpane.lib`, compiled `tests/c/abi_smoke.c` with `-std=c11 -Wall -Wextra -Werror`, and executed the result on this host.
The cross gates compile code without target execution and do not qualify those targets.

The `zig-test` gate arguments do not print a test count.
`zig-test-summary.log` records `zig build test --summary all` with a fresh local cache.
That run reported 7 of 7 tests passed.
`c-assert-negative-control.log` shows that `assert(0)` aborts with a nonzero status under the `c-abi` compiler flags.
That control shows that the smoke test assertions are active.

The receipts and logs in `receipts/` are verbatim copies of the files under `out/evidence`.
Their internal output paths name the original `out/evidence` location.
`SHA256SUMS` lists the digests of every copied file and log in this directory.

## Controller hosts

`node tools/fairpane.mjs check` and `node tools/fairpane.mjs test` passed under Node `v26.7.0`.
`bun tools/fairpane.mjs check` and `bun tools/fairpane.mjs test` also passed under Bun `1.4.2`, with 55 of 55 tests.
The Bun result is informational and does not qualify Bun as a continuous integration host.

## OMP checks

`omp config list --json` and `omp config get` report every key in `.omp/config.yml` with a matching type.

| Key | Type | Effective value |
| --- | --- | --- |
| `task.maxConcurrency` | number | 4 |
| `task.maxRuntimeMs` | number | 0 |
| `task.softRequestBudget` | number | 0 |
| `task.maxRecursionDepth` | number | 2 |
| `task.prewalk` | boolean | false |
| `task.isolation.enabled` | boolean | true |
| `task.isolation.apply` | boolean | false |
| `task.isolation.merge` | enum | `patch` |

The owner's user configuration sets `tools.approvalMode` to `yolo`.
The project configuration does not set or change approval settings.

The first user message of this session matched the body of `.omp/prompts/fairpane-start.md` exactly.
That match shows that OMP discovered and expanded the project prompt.
The installed binary also contains the `prompts` capability for `/prompts:` templates.
The session's task tool listed all ten project agents from `.omp/agents`.

Four probe subagents reported their actual tool grants.
Each probe called only its result tool.

| Agent | Declared tools before repair | Granted tools |
| --- | --- | --- |
| `fairpane-core` | read, grep, glob, edit, write, bash | bash, edit, glob, grep, read, wait, write, yield |
| `fairpane-review` | read, grep, glob | glob, grep, read, yield |
| `fairpane-spec` | read, grep, glob, web_search, browser | glob, grep, read, web_search, yield |
| `fairpane-compiler` | read, grep, glob, edit, write, bash, web_search, browser | bash, edit, glob, grep, read, wait, web_search, write, yield |

OMP 18.8.6 has no `browser` tool and silently dropped that grant.
Browser automation in this version is part of the `eval` tool, which also grants code execution.
The repair removes `browser` from `fairpane-spec` and `fairpane-compiler`, so each declaration matches its actual grant.
The `read` tool still fetches URLs for primary-source reading.
OMP adds `yield` to every agent and `wait` to agents with `bash`.
The review agents have no write, edit, or shell tool.

## Protected paths

`git diff --stat 89109be156eecd356ff59bf9d6508977e76a6b2b` reported no change to these paths:
`AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/zig-version.txt`, and `specs/corpora.json`.
The policy digest changed only because `toolchains/omp-baseline.json` now records the installed OMP version.
That file is an allowed path for this task.

## Limits and open items

- The receipts are unsigned local integrity records, not attestations.
- The `zig-test` gate does not record a test count.
  A separate acceptance-policy change can add `--summary all` to that protected gate definition.
- No HTML, CSS, JavaScript, WPT, Test262, GPU, or application conformance suite ran.
- Linux, macOS, and AArch64 execution did not run.
