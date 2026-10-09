# FP-0132 evidence: lock the i686-unknown-linux-gnu Rust standard library

The `fairpane-bindings` worker `FP0132Lock` implemented `CONTRACT.md` in an isolated worktree at `416130e`, the commit that froze the contract.
The worker `FP0132Cost` then made revision 3, which reduces the added controller case time, in an isolated worktree at `a7219f9`.
Every log with the suffix `-r3` records `a7219f9` as the worktree `HEAD`; every other log records `416130e`.
No worker made a commit.
Every log in `raw/` comes from `node tools/fairpane.mjs record`, and each `RESULT` line gives the exit status.

## Result

Criteria 1 to 6 hold on Windows and on WSL Ubuntu.
The added controller case time is 667 ms in `test-cost-r3.log`, and the bound is 1000 ms.
A repeat series on the same tree, `test-cost-r3-repeat.log`, gives 603 ms.
"Test cost" below gives each median and each change of revision 3.

## Runs

The evidence procedure ran three times.

- The first run used the first implementation. Its logs have no suffix, or the suffix `-attempt-1`.
  It ended at `test-cost.log`, which reports an added time of 1659 ms.
- The worker then reduced the cost, as the integrator directed. `test-cost-profile-*.log` and `test-cost-r1.log` record that work.
- The second run repeated the procedure on the reduced code. Its logs have the suffix `-r2`.
  It ended at `test-cost-r2.log`, which reports 1337 ms, so criterion 6 was unmet.
- Revision 3 applied the A, P1, and B patches of the second run to `a7219f9` with `git apply --3way`.
  `FP-0106` had changed `tools/lib.mjs` and `tools/README.md` since `416130e`, and every hunk applied cleanly.
  Revision 3 then made the changes in "Revision 3 changes" and repeated the procedure. Its logs have the suffix `-r3`.

The final code is the code of revision 3, and `out/fp0132-a-r3.patch`, `out/fp0132-p1-r3.patch`, and `out/fp0132-b-r3.patch` hold it.

Revision 3 order:

1. `install-base-r3.log` copied the five verified Windows host archives of the second run into `.tools/downloads`, reading the source only, and ran `install-rust` on the unmodified base. It reports `downloaded: true`.
2. `controller-tests-base-r3.log` ran three suites on the unmodified `a7219f9` with that toolchain.
3. `p1-lock-sha256-r3.log` reversed `raw/p1-rust-lock.diff`, and the other files returned to `a7219f9` for `controller-tests-before-r3.log` and `index-reset-r3.log`.
4. The A tree, A+P1, the real `install-rust`, and A+P1+B followed in the contract's order, with the mutation controls on A+P1+B. `p1-lock-sha256-r3.log` also records the reapplication of `raw/p1-rust-lock.diff` and the lock's digest after it.
5. The Linux steps ran in `$HOME/fairpane-linux/work/FP-0132-r3`.

Steps 6 and 7 (`i686-head.log` and `gpg-verify.log`) depend on no code, so they ran once, in the first run.
`raw/p1-rust-lock.diff` is unchanged, because the lock is the same at `416130e` and at `a7219f9`.

### Failed and superseded attempts

| Log | Cause |
| --- | --- |
| `toolchain-targets-attempt-1.log` | The shell gave an empty worktree path, so `record` reports the `rustc` path as absent in three commands. `toolchain-targets.log` repeats the commands with the full path. |
| `probe-after-attempt-1.log` | `rustfmt --check --edition 2024` exits with status 1 and asks for a whitespace change in the probe. |
| `commit-b-attempt-1.diff` | Commit B of the first run. Its blob IDs name the first test file. |
| Every log without a suffix except `i686-head.log` and `gpg-verify.log` | The first run, on the first implementation. Later runs supersede them. |
| `controller-tests-after-r1.log`, `test-cost-r1.log` | A measurement of the second run's code before the second run. |
| Every log with the suffix `-r2`, `commit-b.diff`, `mutation.log`, and `mutation-M1.diff` to `mutation-M9.diff` | The second run, on the code before revision 3. Revision 3 supersedes them. |

## The probe

`rustfmt` required one whitespace change: the `assert!` call of the contract's probe text spans four lines in `tests/rust/pointer_width_probe.rs`.
The worker applied only that change, as the contract allows. `probe-after-attempt-1.log` shows the requested diff.
The first run's `probe-before.log` compiled the probe before that change. Its result, E0463, does not depend on the whitespace, and `probe-before-r3.log` repeats it with the final text.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| 1. Lock the i686 `rust-std` under `targets` from the signed manifest, through a separate protected change | `raw/p1-rust-lock.diff`, `i686-head.log`, `gpg-verify.log`, `rust-lock-verify-r3.log`, cases 1 and 2, and M1, M2, and M6 in `mutation-r3.log`. The integrator records `reviews/policy-p1-approve.json`. |
| 2. Install every target into every host toolchain, and check the receipt before any version check | Case 3, case 4, M3, M7, `install-rust-r3.log`, `linux-install-rust-r3.log`, `toolchain-targets-r3.log`, `linux-toolchain-targets-r3.log`, `doctor-a-r3.log`, `doctor-p1-r3.log`, and `doctor-after-r3.log` |
| 3. Replace a stale toolchain only after the new one passes | Case 3, case 6, M4, M8, M9, and `install-rust-r3.log`, which reports `replaced: true` |
| 4. Keep `rust-toolchain.toml` free of targets, and run no rustup command | `FP-0079` case 3, `FP-0132` case 1, `global-state-r3.log`, `linux-global-state-r3.log`, and `protected-paths-r3.log` |
| 5. Compile the `no_std` probe for i686 on Windows and Linux | `probe-before-r3.log`, `probe-after-r3.log`, `linux-probe-after-r3.log`, and M5 |
| 6. Amend the `FP-0079` cases and add at most one second | The amendments keep every assertion (`raw/commit-b-r3.diff` and `out/fp0132-a-r3.patch`). `test-cost-r3.log` reports 667 ms. |

## The i686 archive

| Fact | Observed | Log |
| --- | --- | --- |
| `Content-Length` | 46083412 | `i686-head.log` |
| Size of the downloaded archive | 46083412 bytes | `install-rust-r3.log`, `i686-archive-r3.log` |
| SHA-256 (GNU `sha256sum`) | `2b7db847af9888ddb249d3e1c8aeaeeb82ae529bf62426b82330a4cddac8bb38` | `i686-archive-r3.log` |
| Archive root | `rust-std-1.99.0-i686-unknown-linux-gnu`, the only top-level entry | `i686-archive-r3.log` |
| `rust-installer-version` | `3` | `i686-archive-r3.log` |
| `components` | `rust-std-i686-unknown-linux-gnu` | `i686-archive-r3.log` |
| Entries | 67 files and 7 directories, which the first-party reader of revision 3 accepted | `i686-archive-r3.log` |
| Standard library files | 27 `.rlib` files in `lib/rustlib/i686-unknown-linux-gnu/lib` | `toolchain-targets-r3.log`, `linux-toolchain-targets-r3.log` |

`install-rust-r3.log` downloaded the archive again from `static.rust-lang.org`.
The earlier runs' `i686-archive.log` and `i686-archive-r2.log` report the same values.

## Stop rules

| Rule | Outcome |
| --- | --- |
| `Content-Length` is 46083412 | Holds. |
| The archive is 46083412 bytes long | Holds. |
| Its SHA-256 is `2b7db847…8bb38` | Holds. |
| `[GNUPG:] GOODSIG 85AB96E6FA1BE5FE` | Present in `gpg-verify.log`. |
| `VALIDSIG` with `108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE` as its first and last fingerprint fields | Present. |
| No `BADSIG`, `ERRSIG`, `EXPKEYSIG`, or `REVKEYSIG` | None appears. |
| The committed manifest's SHA-256 is `ce6dddc8…16b6a2` | Holds. |
| Archive root, installer version 3, and the `components` file | Hold. |
| The reader and `installComponents` accept every entry | Hold. `install-rust-r3.log` and `linux-install-rust-r3.log` install the archive. |
| The before probe exits with a status other than 0 | Holds: status 1 with E0463 in `probe-before-r3.log`. |
| The i686 probe passes after installation | Holds on Windows and Linux. |
| A host probe fails | Holds: status 1 with `the probe needs 4-byte pointers` on both hosts. |
| Each global-state log shows equal outputs | Holds in `global-state-r3.log` and `linux-global-state-r3.log`, and in each earlier run's two logs. |
| The added controller case time is at most 1000 ms | Holds: 667 ms in `test-cost-r3.log`. The second run's 1337 ms stopped it; revision 3 continued under the integrator's direction. |
| WSL Node prints `v26.7.0` | Holds in `linux-probe-r3.log`. |

The GnuPG verification ran on 2026-10-09 UTC, so `checked_date` stays `2026-10-09`, and P1 changes only the three lines and the one comma that the contract names.
The lock's SHA-256 is `95221244b4d8c2394c2e2b3fc5bf0cf913eddfd8f521f67a4486bf0995543ab7` before P1 and `05588f0c6905ddaae099323b63eec742ffca309e78e4dd9204017feed2a86926` after it (`p1-lock-sha256-r3.log`, and M6 in `mutation-r3.log`).

## Recorded Rust checks

| Check | Windows | Linux |
| --- | --- | --- |
| Before (base toolchain, i686) | Status 1, E0463 (`probe-before-r3.log`) | Not required |
| After (i686) | Status 0, `out/fp0132/pointer-width-i686.rmeta` exists (`probe-after-r3.log`) | Status 0, the file exists (`linux-probe-after-r3.log`) |
| Host | `x86_64-pc-windows-gnu`: status 1, `the probe needs 4-byte pointers` | `x86_64-unknown-linux-gnu`: status 1, the same message |
| Target library | `equal: true`, 27 `.rlib` files (`toolchain-targets-r3.log`) | `equal: true`, 27 `.rlib` files (`linux-toolchain-targets-r3.log`) |
| Pointer width | `target_pointer_width="32"` | `target_pointer_width="32"` |
| Format | Status 0 | Status 0 |
| Doctor, A | `rust.available: true` (`doctor-a-r3.log`) | Not required |
| Doctor, P1 | `rust.available: false`, with the exact receipt message (`doctor-p1-r3.log`) | Not required |
| Doctor, after | `rust.available: true` (`doctor-after-r3.log`) | Not required |

`install-rust-r3.log` lists `.tools/downloads` before and after the replacement. The run added only `rust-std-1.99.0-i686-unknown-linux-gnu.tar.gz`, reported `downloaded: true` and `replaced: true`, and left only `x86_64-windows` in `.tools/rust/1.99.0`.
The second `install-rust` reported `downloaded: false`.
On Linux, `linux-copy-r3.log` shows equal blob IDs in the WSL copy and the worktree for the 32 files under `tools`, `toolchains`, and `tests/rust`, and `docs/TOOLCHAIN.md`.
The copy received the four Linux archives of `FP-0079-r1` and the verified i686 archive, and `linux-install-rust-r3.log` installed a fresh toolchain with the i686 entry.
`linux-tests-r3.log` passes all 16 cases of `tools/rust.test.mjs` with the WSL Node v26.7.0.
`bun-rust-tests-r3.log` passes all 16 cases with Bun 1.4.2 on Windows.

## Base failures

`controller-tests-before-r3.log` exits with status 1 after 259 cases.
Exactly `FP-0079` case 9 and `FP-0132` cases 1 to 6 report `not ok`, as the contract predicts.
The staged test file has blob `cbb6937ba1013e8fc7731ba0757f1164fb475a61`, which is the test file of `out/fp0132-a-r3.patch`.

## Gates at each commit

| Tree | `test` | `check` |
| --- | --- | --- |
| A | Status 0, 259 of 259 (`controller-tests-after-a-r3.log`) | Status 0 (`check-after-a-r3.log`) |
| A+P1 | Status 0, 259 of 259 (`controller-tests-after-p1-r3.log`) | Status 0 (`check-after-p1-r3.log`) |
| A+P1+B | Status 0 in each of three runs, 259 of 259 (`controller-tests-after-r3.log`), and in each of three more (`controller-tests-after-r3-repeat.log`) | Status 0 (`check-after-r3.log`) |

`protected-paths-r3.log` shows that `git diff --exit-code a7219f9` over the protected paths exits with status 0.
Its `git status --short` lists the untracked probe file, which `git diff --stat` omits.

## Mutation controls

Each control ran `git apply`, its command, and `git apply -R` on the A+P1+B tree. `mutation-r3.log` records the changed file's SHA-256 before, during, and after; each "after" digest equals its "before" digest.
`mutation-M1-r3.diff` to `mutation-M9-r3.diff` make the same changes as the second run's diffs, at the line numbers of revision 3.
No control crashed.

| Control | Result |
| --- | --- |
| M1 | `FP-0132` case 1 fails: rows d and e report `Unexpected component URL for rust-std on x86_64-unknown-linux-musl.` and `…x86_64-unknown-linux-gnu.` |
| M2 | `FP-0132` case 2 fails: the real-manifest call with the changed digit returns `[]`. |
| M3 | `FP-0132` case 3 fails, because its second run on F1 reinstalls. `FP-0132` case 4 fails with the receipt message on the unchanged fixture. `FP-0079` case 7 and `FP-0132` case 6 also fail. |
| M4 | `FP-0132` case 3 fails in the digest row, because the listing of `dest` is empty. `FP-0132` case 6 also fails. |
| M5 | The i686 build exits with status 1 and prints `the probe needs 4-byte pointers`. The Windows host build exits with status 0. |
| M6 | `FP-0132` case 1 fails on its commit B assertion. `FP-0079` cases 1 and 7 pass. |
| M7 | `FP-0132` case 4 fails, because row a records version-check calls. |
| M8 | `FP-0132` case 6 fails in row a, because `dest` is absent. |
| M9 | `FP-0132` case 6 fails in row b, because the run rejects with `injected removal failure`. |

## Test cost

The medians below come from `test-cost-r3.log`, which applies the formula of `test-cost-r2.log` to `controller-tests-base-r3.log` and `controller-tests-after-r3.log`.

| Case | Base runs (ms) | Base median | After runs (ms) | After median | Added |
| --- | --- | --- | --- | --- | --- |
| `FP-0132` case 1 | | | 1, 1, 1 | 1 | 1 |
| `FP-0132` case 2 | | | 41, 36, 42 | 41 | 41 |
| `FP-0132` case 3 | | | 325, 392, 343 | 343 | 343 |
| `FP-0132` case 4 | | | 84, 118, 94 | 94 | 94 |
| `FP-0132` case 5 | | | 0, 0, 1 | 0 | 0 |
| `FP-0132` case 6 | | | 251, 264, 257 | 257 | 257 |
| `FP-0079` case 1 | 1, 0, 0 | 0 | 0, 1, 0 | 0 | 0 |
| `FP-0079` case 4 | 81, 69, 70 | 70 | 78, 91, 74 | 78 | 8 |
| `FP-0079` case 7 | 235, 216, 283 | 235 | 225, 193, 182 | 193 | -42 |
| `FP-0079` case 9 | 653, 542, 421 | 542 | 478, 724, 507 | 507 | -35 |
| Added time | | | | | 667 |

The median `# duration_ms total` is 48680 ms in `controller-tests-base-r3.log` and 53269 ms in `controller-tests-after-r3.log`.

`controller-tests-after-r3-repeat.log` repeats the three runs on the same tree, and `test-cost-r3-repeat.log` applies the same formula to it and the same base log.
Its medians are 1, 45, 356, 96, 0, and 200 ms for `FP-0132` cases 1 to 6, and its `FP-0079` differences are 1, 6, -89, and -13 ms, so its added time is 603 ms.
Its median `# duration_ms total` is 50493 ms.

The `FP-0079` differences come from two series that ran at different times, so each one varies by tens to hundreds of milliseconds; case 9's base values alone span 421 to 653 ms.
[INFERENCE] `FP-0079` case 7 is faster after revision 3 than on the base in both series because changes 1 and 3 below also apply to its installs.
The base log is new in revision 3: `controller-tests-base.log` ran on `416130e` at another time, and this host's total suite time was 54582 ms then and 48680 ms now.
The second run's 1337 ms and revision 3's 667 ms therefore do not measure only the code change.
`test-cost-ops-r3.log` counts the filesystem calls of one pass of `FP-0132` cases 1 to 6 and `FP-0079` case 7, which do not depend on the host's load.
It loads the second run's code from that run's worktree and revision 3's code from this one; `parse-equivalence-r3.log` loads the second run's parser the same way.

| Call | Second run | Revision 3 |
| --- | --- | --- |
| `openSync` | 962 | 854 |
| `readdirSync` | 913 | 844 |
| `mkdirSync` | 758 | 738 |
| `writeFileSync` | 74 | 64 |
| `renameSync`, `rmSync`, `lstatSync`, `existsSync`, `readFileSync`, `statSync`, `mkdtempSync`, `unlinkSync` | 300, 24, 570, 481, 450, 123, 40, 6 | Unchanged |

The pass extracts 108 archives.
Each extraction now opens its archive with `openSync`, which adds 108 calls, and creates two files fewer, which removes 216 file creations and the 216 removals of those files from the stage.
In `test-cost-ops-r3.log`, each command also runs the module's own 16 cases once before the count, because the command passes the module path as `process.argv[1]`, which starts the module's standalone runner. Those runs are not counted.

### Earlier reductions

The integrator allowed reductions that no frozen behavior requires. The second run made three.

1. `installComponents` moves each listed file from the extracted archive into the staged toolchain with `renameSync` instead of copying it.
   Both directories are in the same stage, so a move copies no data, and the stage holds fewer files to remove.
   The `installed` set and the per-component key check still reject a second file at the same path, and the staged toolchain holds no other file, so no move replaces a file.
2. `extractTarGz` and `installComponents` remember each directory that they created, so a file in a known directory needs no `mkdir` call.
3. The fixture builder builds each component archive once per package and host, and later fixtures reuse the same bytes.

The second run also measured a directory-level move, which renames a whole subtree when the toolchain lacks it, and found no consistent gain (`test-cost-profile-after-2.log`).

### Revision 3 changes

The second run's profiles (`test-cost-profile-*.log`) show that almost all case time is synchronous filesystem work: the removal of stages and replaced toolchains, directory creation, and file creation, across about 16 full fixture installs.
The frozen cases fix the number of installs, and the frozen installer fixes their steps, so revision 3 removes filesystem work and event-loop waits that no frozen behavior requires.

1. `extractTarGz` (`tools/rust.mjs`) reads the archive with `readChunks`, a generator that reads 64 KiB chunks with `fs.readSync` on the calling thread, in place of `fs.createReadStream`.
   The bytes still stream through `zlib.createGunzip` into the same consumer, in 64 KiB chunks, the default read size of `createReadStream`, so every header check, path rule, message, and the end-of-stream check are unchanged.
   The extraction no longer waits for the thread pool to open, read, and close each archive.
   When the pipeline stops early, it ends the generator, whose `finally` block closes the file. `extract-descriptors-r3.log` shows that no archive descriptor stays open after a valid archive, a rejected path, a path outside the root after 300000 bytes, a truncated gzip stream, a tar that ends early, and an absent archive.
   `FP-0079` case 5, `i686-archive-r3.log`, `install-rust-r3.log`, and `linux-install-rust-r3.log` exercise the reader on fixtures and on the real archives.
2. `parseChannelManifest` (`tools/rust.mjs`) tries the two table patterns only on a line that starts with `[`, and the two pair patterns only on another line.
   Each pattern is anchored at the line start, a table header starts with `[`, and a key part starts with a letter, digit, `_`, `-`, or `"`, so a line can match only the patterns of its own kind.
   A pair line's key is its single key part without quotes, which is what `keyParts` returned for it, and `keyParts` reuses one global pattern.
   The parser creates the `set` function once, not once per line.
   `parse-equivalence-r3.log` compares the second run's parser, which is the parser of `a7219f9`, with the new one on the real manifest, on ten edge-case texts, and on 1287 texts that remove one character from one of the manifest's first 3000 lines. Every result and every thrown message is equal, and one parse of the real manifest takes about 9 ms instead of 15 ms.
   `FP-0132` case 2 parses the real manifest twice.
3. `componentArchive` (`tools/rust.test.mjs`) no longer adds `install.sh` and `version` to the fixture archives.
   No frozen case text names those files: `FP-0079` case 7 requires a fixture "whose root and component layout match the real archive", and `FP-0132` requires `componentArchive('rust-std', <triple>)` for each target.
   The archive root, the component directory, `manifest.in`, and every component file are unchanged, and the fixture already omitted the real archives' other top-level files, such as `README.md` and the licenses.
   The installer never reads either file. `components` and `rust-installer-version` stay as top-level files that the installer reads and must not install, so `FP-0079` case 7 and `FP-0132` case 3 still show that no top-level file reaches the toolchain, and `FP-0079` case 6 still names `install.sh`, `README.md`, and `version` in its own fixture.
   Each extraction creates two files fewer, and each stage removal removes two files fewer.
4. `FP-0132` case 3 and row a of `FP-0132` case 6 walk the fixture root once per row and derive both the listing of `dest` and the staging entries from that walk, through `below` and a `stagingEntries` that takes a listing.
   `below` keeps the entries under `.tools/rust/1.99.0/<platform>/`, without the directory itself, and removes that prefix. A walk sorts its whole result, and the prefix is common to every kept entry, so the result equals the walk of `dest` in content and order.
   Every assertion and its row label are unchanged.
5. `FP-0132` case 4 restores only the file that each row changed: the receipt in rows a, b, d, and e, and the lock in row c. The case still restores the fixture after each row, in a `finally` block.
6. `installFixture` creates the lock's directory with its first write, and `writeLock` then rewrites only the file, without a recursive `mkdir`.

## Resolved ambiguities

- The receipt check reads `fairpane-install.json` as JSON. A missing file or a JSON syntax error is a mismatch; any other read error propagates, so a permission failure is not reported as a stale toolchain.
- "`target` when present" means an own `target` property of a receipt entry.
- A target's archive file name is the base name of its URL, as for platform components, so the i686 archive and the host `rust-std` archive have different names.
- The `.replaced-` directory takes a random UUID suffix, as the downloader's `.partial` file does.
- `FP-0132` case 1 reports every row that fails, not only the first, so a control shows each affected row.
- `installFixture` keeps its `serve` option and adds `state.serve`, so the failed-replacement rows of case 3 change the served bytes between runs of one fixture.
- The protected-paths log appends a listing that includes untracked files, because `git diff --stat` omits the untracked probe file.
- The WSL copies exclude `out` as well as `.git` and `.tools`, as `FP-0079` did.
- "Fixture work that the frozen case text does not require" covers top-level fixture files that no case names and the installer never reads, but not the component layouts, which `FP-0079` case 7 ties to the real archives.
- "Streams the archive through `zlib.createGunzip`" (`FP-0079`) holds for a source that reads chunks on the calling thread, because the gunzip stream still receives the archive in bounded chunks, and no step reads the whole archive into memory.
- "One walk per row" applies to the rows that compare the listing of `dest` and search for staging entries. The case 3 listing before the rows, and the fresh-install listing of F1, stay single walks of their own directories.
- The test cost uses a new base log, `controller-tests-base-r3.log`, on `a7219f9`, because the formula subtracts base medians from after medians, and both series must run the same suite on the same host.

## Receipts

`fairpane-install.json` is a forgeable local integrity record.
Because of this change, it now decides whether `install-rust` reuses an existing toolchain: anyone who can write `.tools` can make a toolchain look current.

## Targets that ran

- Windows 11, x86_64, Node v26.7.0, host `x86_64-pc-windows-gnu`: every Windows step, the controller tests, and the mutation controls.
- Windows 11, x86_64, Bun 1.4.2: `tools/rust.test.mjs` (`bun-rust-tests-r3.log`).
- WSL Ubuntu, x86_64, Node v26.7.0 at `$HOME/fairpane-linux/node`, host `x86_64-unknown-linux-gnu`: the Linux install, the toolchain checks, the probe, and `tools/rust.test.mjs`.
- The cross target `i686-unknown-linux-gnu`: metadata builds of the probe only. Nothing linked or ran i686 code.
