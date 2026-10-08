# FP-0001 baseline evidence

## Scope

This record covers task `FP-0001` on the first Windows development host.
It qualifies bootstrap behavior only.
It is not browser, JavaScript, or conformance qualification.
All commands ran on October 8, 2026.

## Layout

| Path | Content |
| --- | --- |
| `raw/*.log` | Command records written by `node tools/fairpane.mjs record` or by a gate. |
| `gates/` | Final gate receipts and logs for source digest `f2d2e0e6…`. |
| `probes/` | Verbatim OMP subagent outputs and their index. |
| `reviews/` | Verbatim independent review outputs. |
| `controls/assert_fail.c` | Source of the assertion negative control. |
| `install-zig-attempt1.log`, `install-zig-attempt2.log` | Installer console output captured with `tee`. |
| `superseded/` | Earlier evidence that later records replace. |
| `SHA256SUMS` | Digests of every file in this directory except this file and `SHA256SUMS`. |

Each `record` log contains a `COMMAND` line with the absolute executable path, the actual output, and a `RESULT` line.
The `RESULT` line contains the exit status, signal, watchdog outcome, duration, and any environment override.

`SHA256SUMS` uses binary-mode entries.
On this host, Git for Windows `sha256sum -c` reports the seven files that contain CRLF bytes as `FAILED`.
A Node check that reads each file as bytes matched all 90 entries.

## Host and tools

`raw/host-versions.log` and `raw/doctor.log` record these values.

| Tool | Observed value |
| --- | --- |
| Operating system | `win32`, `x64`, release `10.0.26200`, `Windows 11 Pro`, machine `x86_64` |
| Node | `v26.7.0` at `C:\nvm4w\nodejs\node.exe` |
| Bun | `1.4.2` at `C:\Users\requi\AppData\Local\Microsoft\WinGet\Links\bun.exe` |
| Git | `2.54.0.windows.1` at `C:\Program Files\Git\cmd\git.exe` |
| OMP | `omp/18.8.6` at `C:\Users\requi\AppData\Local\omp\omp.exe` |
| Windows PowerShell | `5.1.26100.9444` |
| PowerShell | `7.6.6` |
| Locked Zig | `0.18.0-dev.120+9fe22a29b` at `.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` |
| Zig on `PATH` | `0.17.0-dev.2453+zigpp.35608841b` at `C:\Users\requi\AppData\Local\zigpp\current\zig.exe` |

The `PATH` compiler is a different build and is not the pin.
Every Zig command in `raw/` and `gates/` names the locked compiler by absolute path.
`build.zig` also stops with a panic under any compiler version other than the pin.

## Archive integrity

`raw/bootstrap-baseline.log` ran in a detached worktree of commit `89109be`, the verbatim archive.
The first `sha256sum -c BOOTSTRAP_MANIFEST.sha256` record exited with status 1 and no output.
That failure came from a controller defect, which the controller repairs section describes.
The repeated check printed `OK` for all 86 manifest entries and exited with status 0.

The supplied `repo-check` and `controller-test` preparation receipts passed `evidence-check` in that worktree.
The supplied `zig-test` preparation receipt failed with "The receipt does not report a passed gate."
That receipt records the missing compiler on the preparation host, so the failure is the expected result.

## Git history

`raw/git.log` records the identity source, the default branch, the remotes, and the commit authors.
The identity `Matt Neel <m@neel.codes>` comes from `C:/Users/requi/.gitconfig`.
`init.defaultBranch` is `master` from `C:/Program Files/Git/etc/gitconfig`.
`git remote -v` printed nothing, so no remote exists.
No repository existed before this task, so no history was overwritten.
Commit `89109be156eecd356ff59bf9d6508977e76a6b2b` records the verified archive without changes.

## Compiler installation

| Attempt | Command | Result |
| --- | --- | --- |
| 1 | `node tools/fairpane.mjs install-zig` | Failed with status 1. See `install-zig-attempt1.log`. |
| 2 | `node tools/fairpane.mjs install-zig` | Passed with status 0. See `install-zig-attempt2.log`. |

Attempt 1 failed because Windows PowerShell 5.1 did not recognize `Get-FileHash`.
`raw/powershell-diagnosis.log` reproduces that failure and records its cause.
The inherited `PSModulePath` lists the PowerShell 7 module directories before the Windows PowerShell directory.
Windows PowerShell 5.1 therefore finds `Microsoft.PowerShell.Utility` version `7.0.0.0`, which supports only the Core edition.
The installer removed the unverified partial download in its `finally` block.

The repair computes SHA-256 through `System.Security.Cryptography.SHA256` in `scripts/Get-Zig.ps1`.
`raw/powershell-diagnosis.log` shows that the same .NET method gives the `sha256sum` digest in both PowerShell versions.
`raw/compiler-archive.log` records the archive size `102765659` and SHA-256 `a48ff20a7357640cf67ad7be819d3f988e9a5085362fe67dc9b94e02a42571ae`.
Both values equal the `x86_64-windows` lock entry in the same log.
The same log records the installer's `fairpane-install.json` and the compiler version.
The installer wrote only under `.tools`.

## Pinned-compiler repairs

`raw/zig-fmt-before-repair.log` records `zig fmt --check` on the base worktree.
It exited with status 1 and named `src\c_api.zig`.
The locked formatter rewrites the three `@intFromEnum` calls to `@backingInt`, as the recorded diff shows.
The formatted base file equals the committed `src/c_api.zig`, and that `git diff --no-index` exited with status 0.
The log also prints the locked `doc/langref.html` line that marks `@intFromEnum` as deprecated in favor of `@backingInt`.
`build.zig` compiled with the locked compiler without changes.

## Controller repairs

- Zig and C ABI gates set `ZIG_GLOBAL_CACHE_DIR` to `.zig-cache/global` and record that override.
- `run --evidence-dir` writes a receipt and its log under an approved evidence directory.
- `record` runs one command without a shell and resolves bare names through `PATH` only.
- The child process now writes to a fresh temporary file, which the controller appends to the log.
  MSYS2 programs exited with status 1 and no output when they received the append-only log handle.
  The first manifest record in `raw/bootstrap-baseline.log` shows that defect.
- `doctor` reports the OS release and name, installed Bun, and the `PATH` compiler.

Five new controller tests cover the evidence directory, environment overrides, executable resolution, and recorded commands.
`raw/controller-hosts.log` shows 60 of 60 tests passing under Node and under Bun.
The Bun result is informational and does not qualify Bun as a continuous integration host.
No permanent test reproduces the MSYS2 handle defect, because it needs an MSYS2 program on the test host.

## Final gate run

Every receipt in `gates/` binds source digest `f2d2e0e6d03370c93235066bb420fb81419448f05e97b7af54483579c4c46087` with 76 files.
Every receipt binds policy digest `ec1505889dbe8cc3aef2fa1e6a9d9da2afd5a7f847fcbe23e1559761d35f3e91` with 12 files.
The local Zig cache entries were deleted before this run, so the test binary compiled and ran again.
`raw/gate-evidence-check.log` shows `evidence-check` passing for each receipt with `current_source: true`.
`raw/clean-checkout-evidence-check.log` repeats that check from a detached worktree of commit `93de2e3`, which has no `out` directory.
That worktree reported the same source and policy digests, and all nine receipts passed.
Commit `93de2e3` was then amended to add only this log, README text, and `SHA256SUMS`, which lie outside the source and policy roots.

| Gate | Result | Receipt | Command exits |
| --- | --- | --- | --- |
| `repo-check` | pass | `2026-10-08T23-49-19-760Z-repo-check-cc5d8116.json` | 0 |
| `controller-test` | pass | `2026-10-08T23-49-19-928Z-controller-test-bf4e0433.json` | 0 |
| `zig-fmt` | pass | `2026-10-08T23-49-21-150Z-zig-fmt-9fc2d1a2.json` | 0 |
| `zig-test` | pass | `2026-10-08T23-49-21-267Z-zig-test-6726867a.json` | 0 |
| `zig-build` | pass | `2026-10-08T23-49-25-782Z-zig-build-c348d3be.json` | 0 |
| `c-abi` | pass | `2026-10-08T23-49-26-003Z-c-abi-b409c2bd.json` | 0, 0, 0 |
| `cross-windows-x86_64` | pass, compile only | `2026-10-08T23-49-26-317Z-cross-windows-x86_64-9bc40270.json` | 0 |
| `cross-linux-aarch64` | pass, compile only | `2026-10-08T23-49-28-238Z-cross-linux-aarch64-d78b941a.json` | 0 |
| `cross-macos-aarch64` | pass, compile only | `2026-10-08T23-49-30-111Z-cross-macos-aarch64-4ee913f4.json` | 0 |

The `c-abi` gate built `fairpane.lib`, compiled `tests/c/abi_smoke.c` with `-std=c11 -Wall -Wextra -Werror`, and executed the result on this host.
The cross gates compile code without target execution and do not qualify those targets.

The `zig-test` gate arguments do not print a test count.
`raw/zig-test-summary.log` records `zig build test --summary all` with a fresh local cache directory.
That run reported 7 of 7 tests passed.
`raw/c-assert-negative-control.log` compiles `controls/assert_fail.c` with the `c-abi` flags.
The program printed `Assertion failed` and exited with status `3221226505`, so those flags keep assertions active.
`raw/global-cache-isolation.log` scanned 364229 entries under `%LOCALAPPDATA%\zig` twice.
Neither scan found an entry changed after the gate-run marker.

## OMP checks

`raw/omp.log` records `omp --version` and `omp config get <key> --json` for each project setting.
Each key exists in the installed schema with the type shown.

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

The same log shows that the owner's configuration sets `tools.approvalMode` to `yolo`.
The project configuration does not set approval settings.
The log also lists the frontmatter of every project agent and prompt.

`raw/omp-prompt-expansion.log` records `omp -p --mode json --no-tools --no-session --thinking off --max-time 120 "/fairpane-resume"`.
OMP sent the body of `.omp/prompts/fairpane-resume.md` to the model instead of the literal command.
`raw/omp-prompt-expansion-check.log` compares that message with the template body and reports equality.
That run shows prompt discovery and expansion in the installed OMP.

`probes/INDEX.md` lists twelve tool-grant probes across all ten project agents.
OMP 18.8.6 has no `browser` tool and dropped that grant without an error.
The repair removes `browser` from `fairpane-spec` and `fairpane-compiler`.
The probes after the repair show each agent's declared tools plus the automatic `yield` tool.
Agents with `bash` also receive the `wait` tool.
The `fairpane-review` and `fairpane-security` agents have no write, edit, or shell tool.

## Protected paths

`raw/protected-paths.log` records `git diff --cached --stat 89109be` for the protected paths after staging this change.
That command printed nothing, so the staged change leaves every protected path unchanged.
The same log lists every staged path that differs from `89109be`.
That listing predates the log itself, this file's final edit, and `SHA256SUMS`.
Every listed path is inside the task's allowed paths.
The policy digest changed only because `toolchains/omp-baseline.json` now records the installed OMP version.
That file is an allowed path for this task.

## Review history

`reviews/review-1-reject.json` rejected commit `70b876a`.
The review found no code defect.
It required durable raw evidence for criteria 1, 5, 6, and 7.

| Review finding | Resolution |
| --- | --- |
| No raw OMP schema, prompt, or grant evidence | `raw/omp.log`, `raw/omp-prompt-expansion*.log`, and `probes/` |
| Host versions not preserved | `raw/host-versions.log` and `raw/doctor.log` |
| Pre-repair formatter failure not preserved | `raw/zig-fmt-before-repair.log` |
| Committed receipts not checkable from a clean checkout | `run --evidence-dir` and the receipts in `gates/` |
| Hand-written logs omit the executable | `record` logs with absolute paths and environment overrides |
| Prompt-discovery claim too strong | Replaced by the recorded expansion run |
| Unsupported claim about the `eval` tool | Removed |
| Other prose-only claims | `raw/bootstrap-baseline.log`, `raw/compiler-archive.log`, `raw/global-cache-isolation.log`, `raw/controller-hosts.log`, and `raw/protected-paths.log` |
| New gate behavior lacks tests | Five controller tests |
| Stale handoff | `engineering/HANDOFF.md` updated |

## Superseded evidence

`superseded/run-1-source-07ffd710/` holds the first gate run for commit `70b876a`.
Its receipts name logs under the ignored `out/evidence` directory.
`superseded/run-2-cached-zig-steps/` holds a run on the final source whose Zig steps reused cached results.
`superseded/hand-captured/` holds the first test-count and assertion logs, which named a bare `zig` command.

## Limits and open items

- The receipts are unsigned local integrity records, not attestations.
- The `zig-test` gate does not record a test count.
  A separate acceptance-policy change can add `--summary all` to that protected gate definition.
- No HTML, CSS, JavaScript, WPT, Test262, GPU, or application conformance suite ran.
- Linux, macOS, and AArch64 execution did not run.
