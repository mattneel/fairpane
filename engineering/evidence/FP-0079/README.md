# FP-0079 evidence

## Scope

Task `FP-0079` pins and installs the stable Rust 1.99.0 toolchain.
The frozen contract is `engineering/evidence/FP-0079/CONTRACT.md`.
The worker implemented it in an isolated working tree whose `HEAD` was `9cc81ea0714a4dcbab67c4f3333d3afa692cba0f`, the commit that freezes the contract.
The Windows host was Windows 10.0.26200 on x64 with Node v26.7.0.
The Linux host was WSL2 Ubuntu, `Linux 7.2.6-locietta-WSL2-xanmod1 x86_64`, with the integrator's Node v26.7.0 at `$HOME/fairpane-linux/node/bin/node`.
This task adds no wrapper code and makes no support claim for the Rust wrapper.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Pin stable Rust 1.99.0 with verified official artifact digests, separate from the wrapper | Cases 1, 2, and 4, control M1, `raw/gpg-verify.log`, and `raw/rust-lock-verify.log`. |
| Name the official source of every digest and record a GnuPG verification | Cases 4 and 10, `raw/provenance-fetch.log`, `raw/provenance/`, and `raw/gpg-verify.log`. |
| Install under `.tools` with size and digest checks and no global change | Cases 5, 6, and 7, controls M3 and M4, `raw/install-rust.log`, and `raw/global-state.log`. |
| Name the locked version in `rust-toolchain.toml` and check it | Case 3 and control M2. |
| Execute the installed toolchain on Windows and Linux | Case 8, `raw/toolchain-versions.log`, `raw/toolchain-smoke.log`, and the `raw/linux-*` logs. |
| Protect the lock and the selection file | Policy change P1 and the integration gates on its head. The integrator lands both. |

## Records

Every command ran through `node tools/fairpane.mjs record`.
No recorded step failed, so no log has an `-attempt-N` suffix, and no log was deleted or overwritten.

| Log | RESULT |
| --- | --- |
| `raw/controller-tests-before.log` | `exit_code` 1. The test run stops at `ERR_MODULE_NOT_FOUND` for `tools/rust.mjs`, which `tools/rust.test.mjs` imports. |
| `raw/provenance-fetch.log` | `exit_code` 0 for the `node -e` call that creates `raw/provenance/`, and `exit_code` 0 for each of the five `curl.exe` calls. |
| `raw/gpg-verify.log` | `exit_code` 0 for `gpg --version` (GnuPG 2.4.9), the directory call, both imports, both fingerprint listings, and the verification. |
| `raw/rust-cases-development.log` | Run 1: `exit_code` 1, 9 of 10 cases; case 7 failed on a wrong expected value in the test. Run 2: `exit_code` 0, 10 of 10 cases. |
| `raw/rust-lock-verify.log` | `exit_code` 0, `result` `pass`, `manifest_sha256` `ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2`, and no problems. |
| `raw/global-state.log` | `exit_code` 0 before the installation and `exit_code` 0 after it, with identical output. |
| `raw/install-clean.log` | `exit_code` 0. The toolchain directory and the five Windows archives were absent. |
| `raw/install-rust.log` | Run 1: `exit_code` 0 and `downloaded: true`. Run 2: `exit_code` 0 and `downloaded: false`. |
| `raw/toolchain-versions.log` | `exit_code` 0 for `rustc -vV`, `cargo -V`, `rustdoc -V`, `rustfmt -V`, and the receipt print. |
| `raw/toolchain-smoke.log` | `exit_code` 0 for the directory call, the `rustc` build, and the run of `out/fp0079/toolchain-smoke.exe`. |
| `raw/linux-probe.log` | `exit_code` 0 and `v26.7.0` for the probe, and `exit_code` 0 for a host listing. |
| `raw/linux-copy.log` | `exit_code` 0 for the copy, the Linux blob listing, and the Windows blob listing. |
| `raw/linux-install-rust.log` | Run 1: `exit_code` 0 and `downloaded: true`. Run 2: `exit_code` 0 and `downloaded: false`. |
| `raw/linux-toolchain-versions.log` | `exit_code` 0 for the four version commands and the receipt print. |
| `raw/linux-toolchain-smoke.log` | `exit_code` 0 for the build and for the run of `out/fp0079/toolchain-smoke-linux`. |
| `raw/mutation.log` | Each control records its mutation (`exit_code` 0), its `git diff --no-index` (`exit_code` 1, because the files differ), its command (`exit_code` 1), and its restoration (`exit_code` 0). |
| `raw/controller-tests-after.log` | `node --version` prints `v26.7.0` with `exit_code` 0, and `node tools/fairpane.mjs test` has `exit_code` 0 with 202 of 202 controller tests, including FP-0079 cases 1 to 10. |
| `raw/check-after.log` | `exit_code` 0 and `result` `pass`. |

### Provenance and GnuPG

`raw/provenance/` holds the channel manifest, its `.asc` signature, its `.sha256` file, the signing key from `static.rust-lang.org`, and the keybase copy of the key.
The `.sha256` file names the same digest as the lock, `ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2`.
Both key imports list the primary fingerprint `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE` in the first `fpr` line.
The two key files are byte-identical; each has the SHA-256 `e54b09a439647e006b4831eec9785cbaaf3e07ab371c3a6ee6a68e1bdb9fbc6b`.
The verification prints `[GNUPG:] GOODSIG 85AB96E6FA1BE5FE` and a `[GNUPG:] VALIDSIG` line whose first and last fingerprint fields are `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE`.
It reports no `BADSIG`, `ERRSIG`, `EXPKEYSIG`, or `REVKEYSIG` line.
GnuPG also reports `TRUST_UNDEFINED`, because the fresh home directory certifies no key; the fingerprint comparison replaces that trust decision.
The verification ran at 2026-10-09T12:44:30Z, so `checked_date` is `2026-10-09`.

### Installation

`install-rust` verified the size and SHA-256 of all five Windows archives and all four Linux archives against the lock.
Every archive extracted through the first-party reader with the locked `archive_root`, installer version `3`, and only regular files, directories, and GNU long names.
The installed components are `rustc`, `cargo`, `rust-std-x86_64-pc-windows-gnu`, `rust-mingw`, and `rustfmt-preview` on Windows.
On Linux, they are `rustc`, `cargo`, `rust-std-x86_64-unknown-linux-gnu`, and `rustfmt-preview`.
Each receipt, `fairpane-install.json`, is printed in the matching version log.

Both hosts report the frozen version lines.
`rustc -vV` reports `release: 1.99.0`, `commit-hash: b940084d7eb6a299eb4bfeb8e34901bc051e7ac4`, and the locked host, `x86_64-pc-windows-gnu` or `x86_64-unknown-linux-gnu`.
`cargo -V`, `rustdoc -V`, and `rustfmt -V` print the frozen lines.

### Smoke program

On Windows, `rustc --edition 2024 -C link-self-contained=yes` built `out/fp0079/toolchain-smoke.exe`.
`[INFERENCE]` The self-contained link uses the linker that the `rust-mingw` component installs, because no Windows command named another linker.
On Linux, the build ran without `-C link-self-contained`; the probe found `/usr/bin/cc` on the host.
Each run exits with status 0 and prints `fairpane rust toolchain smoke: thread 42, unwind caught`.
Each run's standard error, which the log interleaves with standard output, holds the caught panic `fairpane toolchain smoke panic`.

### Linux copy

The copy in `$HOME/fairpane-linux/work/FP-0079` came from the working tree without `.git` and `.tools`, through `tar` from `/mnt/c`.
`raw/linux-copy.log` lists the Git blob ID of every file under `tools`, `toolchains`, and `tests/rust`, and of `rust-toolchain.toml`, in the copy.
A Windows `node -e` call computes the same 28 blob IDs from the working tree, and the two listings are equal.

## Mutation controls

Each control saved the original file under `out/fp0079/mutation/`, mutated one exact string, and stored the diff as `raw/mutation-<control>.diff`.
Each restoration copied the saved file back and printed its SHA-256.
Every control failed through an assertion or a reported problem, not a crash.

| Control | Mutation | Outcome |
| --- | --- | --- |
| M1 | The last digit of the Windows rustc `sha256` changes from `c` to `d`. | `rust-lock-verify` exits with status 1 and reports only `The manifest hash of rustc for x86_64-pc-windows-gnu differs from the lock.` |
| M2 | The channel in `rust-toolchain.toml` becomes `1.98.1`. | `check` exits with status 1 and prints `Fairpane: rust-toolchain.toml names 1.98.1, but the lock pins 1.99.0.` |
| M3 | `invariant(checksumValid(header), ...)` becomes `invariant(true \|\| checksumValid(header), ...)`. | `node tools/rust.test.mjs` exits with status 1; only case 5 fails, with `Missing expected rejection.` |
| M4 | The unlisted-file `invariant` becomes `invariant(true \|\| ...)`. | `node tools/rust.test.mjs` exits with status 1; only case 6 fails, with `Missing expected exception.` |

## Stop rules

- Archive size or SHA-256: every downloaded archive matched the lock on both hosts.
- GnuPG: the required `GOODSIG` and `VALIDSIG` lines appear, and no rejected status appears.
- Keybase key: its primary fingerprint equals the static key's.
- Archive root, installer version, and entry types: every archive matched the contract.
- Installed `rustc -vV`: the `release`, `commit-hash`, and `host` lines match on both hosts.
- Windows smoke link: it linked with `-C link-self-contained=yes`, so no linker output needed recording.
- Global rustup and Cargo state: the listings of `%USERPROFILE%\.rustup\toolchains` and `%USERPROFILE%\.cargo\bin`, and the SHA-256 of `%USERPROFILE%\.rustup\settings.toml`, are identical before and after the installation.
- WSL Node: the probe printed `v26.7.0`.

No stop rule fired.

## Targets that ran

- `x86_64-pc-windows-gnu` on the Windows host: installation, version checks, and the smoke program.
- `x86_64-unknown-linux-gnu` on WSL2 Ubuntu: installation, version checks, and the smoke program.

## Resolved ambiguities

- The lock-validation rule lists `rust-mingw` after `rustfmt-preview`, but the frozen lock lists it before `rustfmt-preview`.
  Case 1 requires the validator to accept the frozen lock, so `validateRustLock` requires `rustc`, `cargo`, `rust-std`, `rust-mingw` for a `-windows-gnu` host, and then `rustfmt-preview`.
  The lock is unchanged.
- The contract sets `CARGO_HOME` to `C:\src\fairpane\.tools\cargo-home`.
  The worker's assignment forbids touching `C:\src\fairpane\.tools`, so every Windows Rust command used the working tree's `.tools\cargo-home`, which is also the directory that `checkRust` sets.
  On Linux, the commands used the copy's `.tools/cargo-home`.
  The Windows `.tools\cargo-home` did not exist after the after-runs.
- `curl.exe -o` does not create directories, so a recorded `node -e` call creates `raw/provenance/` first.
- On Windows, `fs.statSync` reports mode `666` for the GnuPG home directories after `mkdirSync` and `chmodSync` with `0o700`, because Windows has no POSIX modes.
  GnuPG used both directories without a warning about their permissions.
- Step 7 recorded its removal check in `raw/install-clean.log`, so `raw/install-rust.log` holds only the two `install-rust` runs.
- The Linux steps ran through `wsl.exe` from the Windows `record` command, so their logs sit in this directory.
- Controls M3 and M4 ran `node tools/rust.test.mjs`, which runs FP-0079 cases 1 to 10 alone.
- The contract does not freeze messages for every failure.
  The implementation adds `The Rust lock has no platforms.`, `The archive entry size is invalid at offset <n>.`, `<component>/manifest.in has an unknown line: <line>`, `The <tool> version check failed: <detail>`, and three manifest-parser messages for a repeated key, a value used as a table, and a table reused as an array.
  A value that is absent from a manifest or a `rustc -vV` output appears as `none` in its message.
- A lone zero block where a header belongs fails with the header checksum message at that block's offset, because it is not a valid header.
- `release_date` and `checked_date` must also be calendar dates, not only `YYYY-MM-DD` text.
- `installComponents` compares installed paths without regard to case, as the archive reader does, so the shared `installed` set holds lower-case paths.
- `installRust` extracts every archive before it installs any component, as steps 5 and 6 order them.
- `rust-lock-verify` with more than one argument also prints the usage line and exits with status 1.
- The first run in `raw/rust-cases-development.log` exposed a defect in case 7 itself: it expected `.tools/rust/1.99.0` to list the platform directory after a filter that removed it.
  The corrected case asserts the exact listings of `.tools`, `.tools/rust`, and `.tools/rust/1.99.0`, which is stricter.
  `raw/controller-tests-before.log` ran before that correction.
- `[INFERENCE]` Case 9 runs `doctor`, whose `path_rustc` field runs `rustc -V` from `PATH`.
  On the Windows host, that executable is the rustup proxy, which reads `rust-toolchain.toml` in the working tree and selects the existing global toolchain `1.99.0-x86_64-pc-windows-msvc`.
  That toolchain already contains `rustfmt`, so the proxy has nothing to install.
  `raw/global-state.log` brackets the installation, not the test runs.

## Integration

The integrator lands P1, runs the `repo-check` and `controller-test` gates with `--evidence-dir engineering/evidence/FP-0079/gates` on its head, and records `raw/integration-binding.log`.
`fairpane-review` and `fairpane-security` review this task.

## Revision 1

### Base and rebase

The first implementation's worktree was based on `9cc81ea`.
The integrator committed it as `04342e2` on top of `789ad50`.
`raw/base-binding-r1.log` shows that `04342e2` has the parent `789ad50`, and it lists the six commits from `9cc81ea` to `789ad50`.
Every log in the sections above ran on the pre-rebase tree.

Revision 1 ran in an isolated worktree whose `HEAD` was `e6d215c11021036ae0a97ed768578687eb831fe3`, the commit that freezes revision 1.
The same log shows that `tools`, `tests/rust`, `toolchains`, `rust-toolchain.toml`, `docs/TOOLCHAIN.md`, `engineering/dependencies.json`, and ADR 0010 are identical at `04342e2` and `e6d215c`.
The before-run on `e6d215c` therefore runs the `04342e2` implementation.
The Windows host was Windows 11 Pro, release 10.0.26200, build 10.0.26200.9457, on x64 with Node v26.7.0, as `raw/claims-r1.log` records.

### Changes

- `doctor` has no `path_rustc` field.
  It starts no `rustc`, `cargo`, `rustdoc`, `rustfmt`, or `rustup` from `PATH` or the working directory.
  Its `rust` field runs only the locked toolchain by path, through `checkRust`.
- `acceptedArchivePath` also rejects a code unit from U+0000 to U+001F, a `:` anywhere, a component that ends in `.` or a space, and a component whose name before its first `.` is a reserved Windows device name, compared without regard to case.
  The message stays `The archive path is not accepted: <name>`.
- A GNU `L` header whose size exceeds 4096 bytes fails with `The archive long name is longer than 4096 bytes.` before the reader buffers any payload byte.
- `checkRust` and the staged check in `installRust` start each version check with its working directory set to the toolchain's `bin` directory.
- Case 9 puts a directory first on `PATH` that holds a marker program named `rustc.exe` on Windows and `rustc` elsewhere.
  It requires that `doctor`, run from the repository root, leaves no marker and has no `path_rustc` key.
  It then starts the program directly with `-V` and requires the marker.
- Case 5 adds the 17 rejection fixtures of the revision, each with its exact message.
- `docs/TOOLCHAIN.md` gains three lines that describe `doctor`, the added path rules, and the long-name limit.
  Every frozen line stays unchanged.

### Reserved device names

The list comes from Microsoft's "Naming Files, Paths, and Namespaces", <https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file>.
It is `CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9`, `COM¹`, `COM²`, `COM³`, `LPT1` to `LPT9`, `LPT¹`, `LPT²`, and `LPT³`.
The page also reserves each name followed by an extension, such as `NUL.txt`.
`raw/reserved-names-r1.log` fetches the page with `curl.exe` into the scratch file `out/fp0079/naming-a-file.html`.
It prints the page's SHA-256, `ed4159b1883ecea8437b180597c0cef239ca7584244f1bf3e91d7294729d3aa0`, its title, and the quoted list.
The repository does not keep the page.
`tools/rust.mjs` records the list and the URL beside `RESERVED_DEVICE_NAME`.

### Records

Every revision 1 command ran through `node tools/fairpane.mjs record`.
No recorded step was abandoned, so no revision 1 log has an `-attempt-N` suffix, and no log was deleted or overwritten.

| Log | RESULT |
| --- | --- |
| `raw/tests-before-r1.log` | `exit_code` 0 for `git rev-parse HEAD`, which prints `e6d215c11021036ae0a97ed768578687eb831fe3`. `exit_code` 0 for `git status`, which lists only `tools/rust.test.mjs` and the log itself. `exit_code` 0 for the staging command `git add -- tools/rust.test.mjs`. `exit_code` 0 for `git diff --cached --raw`, which lists the base blob `e47c4859c548febe70e5997741f38c73277226f4` and the staged blob `2b70906cc5525140e76243a39f1a8bb27205e3da`. `exit_code` 0 for `git hash-object` of the four controller files. `exit_code` 1 for `node tools/rust.test.mjs`: 7 of 10 cases pass, and cases 5, 7, and 9 fail. |
| `raw/base-binding-r1.log` | `exit_code` 0 for both `git log` calls, and `exit_code` 0 for `git diff --exit-code --stat 04342e2 e6d215c` over the Rust paths, which prints nothing. |
| `raw/rust-cases-development-r1.log` | `exit_code` 0, 10 of 10 cases, after the implementation change. |
| `raw/install-rust-r1.log` | `exit_code` 0 for the copy of the five Windows archives. Run 1 of `install-rust`: `exit_code` 0 and `downloaded: true`. Run 2: `exit_code` 0 and `downloaded: false`. |
| `raw/mutation-r1.log` | For M5 and M6: the mutation `exit_code` 0, `git diff --no-index` `exit_code` 1 because the files differ, `node tools/rust.test.mjs` `exit_code` 1, and the restoration `exit_code` 0. |
| `raw/mutation-M5.diff`, `raw/mutation-M6.diff` | The exact diff of each control. |
| `raw/global-state-r1.log` | `exit_code` 0 before and `exit_code` 0 after `node tools/fairpane.mjs test`, with identical output. |
| `raw/controller-tests-after-r1.log` | `node --version` prints `v26.7.0` with `exit_code` 0. `node tools/fairpane.mjs test` has `exit_code` 0 with 202 of 202 controller tests, including FP-0079 cases 1 to 10. |
| `raw/global-state-compare-r1.log` | `exit_code` 0. It reads `raw/global-state-r1.log` and prints `outputs: 2; equal: true`. |
| `raw/check-after-r1.log` | `exit_code` 0 and `result` `pass` for each run. |
| `raw/claims-r1.log` | `exit_code` 0 for the key-file hashes, the `cargo-home` probe, the Node `os` probe, and `cmd.exe /d /c ver`. |
| `raw/reserved-names-r1.log` | `exit_code` 0 for the `curl.exe` fetch and for the extraction. |
| `raw/linux-copy-r1.log` | `exit_code` 0 for the copy into `$HOME/fairpane-linux/work/FP-0079-r1`, for the Linux blob listing, and for the Windows blob listing. The two listings name the same 28 blob IDs. |
| `raw/linux-tests-r1.log` | `exit_code` 0. The WSL Node prints `v26.7.0`, and `node tools/rust.test.mjs` passes 10 of 10 cases on Linux. |
| `raw/linux-install-rust-r1.log` | `exit_code` 0 for the copy of the four Linux archives, whose `cp -n` warnings the log keeps. Run 1 of `install-rust`: `exit_code` 0 and `downloaded: true`. Run 2: `exit_code` 0 and `downloaded: false`. |
| `raw/index-reset-r1.log` | `exit_code` 0 for `git restore --staged -- tools/rust.test.mjs` and `exit_code` 0 for the `git status` after it. |

### Before-run

`raw/tests-before-r1.log` ran the revised cases on `e6d215c` with only `tools/rust.test.mjs` changed.
Case 9 fails with `path_rustc: true` and `marker: true`.
The marker shows that the base `doctor` started the marker program from `PATH`.

Case 5 runs every fixture and reports each fixture that is not rejected with its exact message.
On the base, it reports eight fixtures:

- the `L` payload of 4097 bytes, which the base reader buffers and then fails to open with `ENOENT`;
- the paths `…/a:b`, `…/CON`, `…/nul.txt`, `…/COM1`, `…/dot.`, and `…/space `, which the base reader accepts;
- the path `…/a\u0001b`, which the base reader accepts and Windows then fails to open with `ENOENT`.

The old rules already reject the other nine revision 1 fixtures with their exact messages.
They are the GNU long names with a `..` component, a leading `/`, a drive letter, an embedded NUL, and a path outside the root; the POSIX prefix `<root>/..`; the prefix that makes an empty component; the directory `D` and the file `d`; and the `L` entry at the end of the archive.

Case 7 also fails on the base, because its injected `run` now requires each version check's working directory to be the toolchain's `bin` directory.
The base passes no `cwd`, so the message names `undefined`.

### Mutation controls

Each control saved the original file under `out/fp0079/mutation/`, changed one exact string, and stored the diff.
Each restoration copied the saved file back and printed its SHA-256.
Each control failed through an assertion, not a crash.

| Control | Mutation | Outcome |
| --- | --- | --- |
| M5 | `doctor` regains `path_rustc: { ...versionOf('rustc', ['-V']), note: 'Gates never use a Rust toolchain from PATH.' }`, the `04342e2` probe. | `node tools/rust.test.mjs` exits with status 1; only case 9 fails, with `path_rustc: true` and `marker: true`. |
| M6 | `if (name.includes(':')) return false;` becomes a comment. | `node tools/rust.test.mjs` exits with status 1; only case 5 fails, and it reports only `the path "fx-1.0.0-x86_64-pc-windows-gnu/a:b": Missing expected rejection.` |

### Global state

`raw/global-state-r1.log` lists `%USERPROFILE%\.rustup\toolchains`, each toolchain's `lib\rustlib\components` file, the SHA-256 of `%USERPROFILE%\.rustup\settings.toml`, and `%USERPROFILE%\.cargo\bin`.
It ran directly before and directly after the `node tools/fairpane.mjs test` run in `raw/controller-tests-after-r1.log`.
Both outputs are byte-identical, as `raw/global-state-compare-r1.log` confirms.
The components of each toolchain, including `1.99.0-x86_64-pc-windows-msvc`, did not change.
The bracket replaces the `[INFERENCE]` note about case 9 in the first implementation's resolved ambiguities.

### Claims of review 1

`raw/claims-r1.log` records the three claims that review 1 found without a log.

- Both key files have the SHA-256 `e54b09a439647e006b4831eec9785cbaaf3e07ab371c3a6ee6a68e1bdb9fbc6b` and 5326 bytes, and they are byte-identical.
- The first implementation's `C:/Users/requi/.omp/wt/ta23d1da82/m/.tools/cargo-home` does not exist when the probe runs, and neither does this worktree's `.tools/cargo-home`.
  The probe ran after both `install-rust` runs, both controls, and the Windows controller tests.
- The Node `os` probe reports `Windows_NT`, release `10.0.26200`, and `Windows 11 Pro`, and `ver` reports `Microsoft Windows [Version 10.0.26200.9457]`.

### Targets that ran

- `x86_64-pc-windows-gnu` on the Windows host: the before-run, both controls, the controller tests, and `install-rust` with the five real Windows archives.
- `x86_64-unknown-linux-gnu` on WSL2 Ubuntu: FP-0079 cases 1 to 10, including the shell-script marker program of case 9, and `install-rust` with the four real Linux archives.

On each host, the first `install-rust` run passes every entry of the real archives through the revised path rules and runs every version check in the toolchain's `bin` directory.
Revision 1 did not repeat the version logs or the smoke programs, because it does not change the installed toolchains or the smoke program.
Controls M5 and M6 ran on Windows only.

### Resolved ambiguities in revision 1

- The staging command is `git add -- tools/rust.test.mjs` in the worktree, because the worktree already holds the whole base tree.
  `raw/index-reset-r1.log` unstages the file after the evidence runs, so the patch is an unstaged working-tree change.
- On Windows, case 9's marker program is a minimal x64 PE image that the test writes itself.
  Its entry point calls `CreateFileW` on the marker path and then `ExitProcess(0)`, whatever its arguments.
  The test needs no compiler, Rust toolchain, or network access for it.
  Outside Windows, the program is a `#!/bin/sh` script that creates the marker.
  The before-run and M5 show that `doctor` creates the marker through it when `doctor` starts `rustc`, and every passing run shows that a direct start creates it.
- Case 5 collects the outcome of every fixture before it asserts, so one run names every fixture that a defect lets through.
  The 14 fixtures of the first implementation keep their messages.
- Case 7 gains one assertion in its injected `run`: each version check's `cwd` equals the directory of the executable.
  The revision states the behavior but names no case for it.
- The `:` rule is its own statement, so M6 removes exactly that rule.
  The drive-letter rule still rejects `C:/x` and the long name with a drive letter without it.
- The superscript digits appear as `\u00b9`, `\u00b2`, and `\u00b3` escapes in the pattern.
- `raw/install-rust-r1.log` copied the five verified Windows archives from the first implementation's worktree into this worktree's `.tools/downloads`, reading the source only.
  `raw/linux-install-rust-r1.log` copied the four Linux archives from `$HOME/fairpane-linux/work/FP-0079/.tools/downloads` in the same way.
  `installRust` reuses an archive only after its size and SHA-256 check, and it fetches only when that check fails.
  `[INFERENCE]` Neither run downloaded an archive, because the Windows run took 8.7 seconds for 239 MB of archives and the Linux run took 4.3 seconds for 209 MB.
  `downloaded: true` reports a new installation, not a download.
- `doctor` still reports `path_zig` through a `PATH` lookup, which the revision leaves in place.

### Stop rules and integration

No stop rule fired in revision 1.
Every reused archive matched the lock, and every installed `rustc -vV` matched the frozen lines.
The WSL Node printed `v26.7.0`, and the global rustup and Cargo state did not change across the controller tests.
`toolchains/rust.lock.json` is unchanged.
After both reviews accept this revision, the integrator records `rust-lock-verify` on the committed manifest, lands P1, and runs the gates on the P1 head, as the contract's revision 1 states.
