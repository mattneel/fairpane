# FP-0052 evidence

## Scope

Task `FP-0052` closes the FP-0003 review findings that `engineering/evidence/FP-0052/CONTRACT.md` freezes.
The worker implemented it in an isolated working tree whose `HEAD` was `f31eb22b72588b095e3b031ecf7606665c37fd6e`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0.
No protected path changed, and `specs/corpora.json` is unchanged.
The worker did not commit or push.

## Changes

- `tools/lib.mjs`: `windowsSystemProgram(relative, env)` returns `<SystemRoot>\System32\<relative>`.
  It fails with an error that names `SystemRoot` when the variable is unset, empty, or not an absolute Windows path.
  `treeStopProgram()` returns `taskkill.exe` through it on Windows and null elsewhere, and the exported `stopProcessTree(child, taskkill)` uses that path.
  `runProcess` resolves the program before it creates its capture file or starts the command, so a resolution failure records an error and starts nothing.
  The timeout process listing and `installZig` start `WindowsPowerShell\v1.0\powershell.exe` through the same resolver, which replaces the FP-0098 `windowsPowerShellPath`.
- `tools/corpus.mjs`: the Git watchdog resolves `taskkill.exe` before it starts each Git process and stops the tree through `stopProcessTree`; the old `killTree` is gone.
  `replaceSnapshot` holds the fetch lock and calls the shared write phase.
  `fetchCorpus` and `repinCorpus` accept `onWriteStep` for tests.
  `WPT_RULE` and the comment above `WPT_NOT_TESTS` state the upstream `test262` condition exactly.
- `tools/fileset.mjs`: `commitFileSet` became the exported `commitSnapshot`, which both fetches call.
  It takes `files` as `{ label, file, bytes }`, so a Git fetch passes none, and it removes a stale `<id>.old` before it starts.
  Its step labels, order, rollback, and final error are unchanged.
  `withFetchLock` creates `<id>.lock` with exclusive creation, writes `{"pid":…,"started_at":…}`, runs the fetch, and removes the lock after success and after failure.
  A held lock fails with an error that names the lock file, the process ID, and the start time.
  `fetchFileSet` takes the lock before it reads the old record or touches `<id>.fetch`.
- `tools/selftest.mjs`: FP-0052 cases 1 to 6 for the Git corpus, and one more case that a `SystemRoot` that cannot locate `taskkill.exe` fails `runProcess` on Windows before its command starts.
- `tools/fileset.test.mjs`: the file-set part of FP-0052 case 6.
- `specs/IMPORT_REQUIREMENTS.md`: the `EastAsianWidth.txt`, `DerivedBidiClass.txt`, and `DerivedGeneralCategory.txt` rows, as the contract states them.
- `specs/sources.json`: the `S37`, `S39`, `S41`, and `S47` purposes, and the new `S101` for RFC 5893.
- `specs/applicability/wpt.json`: regenerated; only `discovery.rule` changed.
- `engineering/decisions/0003-corpus-snapshots.md`: the `test262` item-type rule, the lock, the shared write phase, the fetch steps, and the full-path `taskkill.exe`.
- `specs/README.md` and `tools/README.md`: the lock, the shared write phase, and the system-directory programs.

## Criterion mapping

| Criterion | Evidence |
| --- | --- |
| Case 1: the resolver returns `C:\Windows\System32\taskkill.exe` and names `SystemRoot` for an unset, empty, or relative value. | Fails in `raw/tests-before.log` ("lib.windowsSystemProgram is not a function"); passes in `raw/controller-tests-after.log` and `raw/linux-controller-tests.log`. |
| Case 2: a `taskkill.exe` in the working directory does not keep `runProcess` from returning `timed_out: true` within 15 seconds. | Passes in `raw/tests-before.log` on Windows, so it does not fail before the change; see "Contract defect in case 2". Passes in `raw/controller-tests-after.log` and `raw/linux-controller-tests.log`. The case that amendment 1 revises fails in `raw/tests-before-a1.log` and passes in `raw/controller-tests-after-a1.log`; see "Amendment 1". |
| Case 3: a Git corpus repin that fails at each of the four write steps changes nothing. | Fails in `raw/tests-before.log` ("Missing expected rejection: stage the record"); passes after on both hosts. The case also requires that an uninjected repin runs exactly those four steps. |
| Case 4: a failed removal of `<id>.old` after the record is replaced fails with "could not remove the old copies", and the new record and snapshot stay. | Fails in `raw/tests-before.log`, where the raw "injected removal failure" escaped before the record was written; passes after on both hosts. The case replaces `fs.rmSync` only for `<corpora>/test262.old` while it exists. |
| Case 5: with `test262.lock` present, a fetch fails with the lock error and changes nothing. | Fails in `raw/tests-before.log` ("Missing expected rejection."); passes after on both hosts. |
| Case 6: two fetches started together end with one `pass` and one lock error, only the corpus directory remains, and `corpus-verify` passes, for the Git corpus and for a file set. | Both parts fail in `raw/tests-before.log`: the Git fetches both failed (an `EPERM` on `test262.fetch` and "git init exited with status 128"), and the file-set fetches ended with one `pass` and an `ENOENT` rename of `unicode.fetch`. Both pass after on both hosts. |
| Case 7: every existing file-set write-phase case passes unchanged. | `tools/fileset.test.mjs` keeps every existing case byte for byte; `FP-0013 case 54` and the other FP-0013 cases pass in `raw/controller-tests-after.log` and `raw/linux-controller-tests.log`. |
| Case 8: `corpus-applicability wpt` regenerates the record, and the diff changes only the rule text. | `raw/applicability.log` (exit 0, `FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, no fetch) and `raw/applicability-diff.log` (one line changed: `discovery.rule`). |
| Mutation: skip the restore of the old snapshot directory. | `raw/mutation-1.diff`; cases FP-0052 3 and FP-0013 54 fail, 218 of 220 pass. |
| Mutation: remove the lock check. | `raw/mutation-2.diff` opens the lock with `w` instead of `wx`; FP-0052 case 5 and both parts of case 6 fail, 217 of 220 pass. |
| Mutation: start `taskkill.exe` by bare name. | `raw/mutation-3.diff`; the extra FP-0052 `SystemRoot` case fails, 219 of 220 pass. Case 2 passes under this mutation, as it does on the base. The revised case 2 fails under the same mutation in `raw/mutation-a1.log`; see "Amendment 1". |
| Mutation: remove the `check(record)` invariant from the Git corpus fetch. | `raw/mutation-4.diff`; the existing case "A fetched snapshot whose record differs from its pin leaves the existing snapshot and record unchanged" fails, 219 of 220 pass. |
| `node tools/fairpane.mjs test` and `check` pass. | `raw/controller-tests-after.log` (exit 0, 220 of 220) and `raw/check.log` (exit 0). |

## Contract defect in case 2

Case 2 passes on the base on Windows, but the review's inference about the search order holds.
`raw/probe-search-order-2.log` shows the cause.

- `System32\taskkill.exe /PID 1 /T /F` exits with status 128 and "ERROR: The process "1" not found."
- A bare `taskkill.exe` with a copy of `node.exe` named `taskkill.exe` in the process working directory prints a Node module-loader error, so Windows ran the copy in the working directory.
- A bare `taskkill.exe` with a copy of `whoami.exe` there exits with status 1, not 0, because `whoami.exe` rejects `/PID`.

The base watchdog falls back to `child.kill('SIGKILL')` when `taskkill.exe` exits with a nonzero status, so the whoami copy never hides the hang.
The frozen case says that the program "exits with status 0" and that on Windows it "is a copy of `<SystemRoot>\System32\whoami.exe`", and those two statements contradict each other for taskkill's arguments.
The worker kept the case as frozen and corrected only its comment, which had repeated the status-0 claim.
`raw/probe-search-order.log` is the first probe attempt; the whoami copy printed nothing there and exited with status 1, so that attempt could not show which program ran.
[INFERENCE] The renamed copy finds no `taskkill.exe.mui` message resource, which would explain its empty output.

A fixture that exits with status 0 for any arguments would make case 2 fail on the base, for example a copy of `node.exe` named `taskkill.exe` with a `NODE_OPTIONS` preload that exits with status 0 when its executable is named `taskkill.exe`.
That change needs a contract amendment.
Until then, the bare-name mutation is caught only by the extra `SystemRoot` case, which checks that `runProcess` resolves `taskkill.exe` through `windowsSystemProgram` before it starts a command.

## Records

Every command ran through `node tools/fairpane.mjs record`.
No log was deleted or overwritten.

| Log | RESULT |
| --- | --- |
| `raw/tests-before.log` | See "Red baseline". |
| `raw/probe-search-order.log` | `exit_code` 0; the first probe attempt, superseded by the next log. |
| `raw/probe-search-order-2.log` | `exit_code` 0; the search-order probe above. |
| `raw/controller-tests-attempt-1.log` | `exit_code` 0, 220 of 220, on the implementation before the mutation controls; `raw/controller-tests-after.log` supersedes it. |
| `raw/applicability.log` | `exit_code` 0 for `node tools/fairpane.mjs corpus-applicability wpt` with the `FAIRPANE_CORPORA_DIR` override. |
| `raw/applicability-diff.log` | `exit_code` 0 for `git diff --stat` (1 insertion, 1 deletion) and for `git diff` of `specs/applicability/wpt.json`. |
| `raw/check.log` | `exit_code` 0 for `node tools/fairpane.mjs check`. |
| `raw/mutation.log` | Four controls. Each records `git hash-object` (0), the mutation (0), `git hash-object` (0), `git diff --no-index` (1, because the files differ), `node tools/selftest.mjs` (1), the restoration (0), and `git hash-object` (0). See "Mutation hashes". |
| `raw/linux-copy.log` | `exit_code` 0 for the copy into `$HOME/fairpane-linux/work/FP-0052` without `.git`, `.tools`, and `out`, with the blob IDs of the five changed tool files, which equal the final Windows files. |
| `raw/linux-controller-tests.log` | `exit_code` 1 under WSL Ubuntu (Linux 7.2.6) with Node v26.7.0: 219 of 220 pass, including every FP-0052 case. The one failure is attestation case 13, "git rev-parse HEAD failed: fatal: not a git repository", because the copy has no `.git`; it is unrelated to this task. |
| `raw/controller-tests-after.log` | `exit_code` 0 for `node tools/fairpane.mjs test` with 220 of 220, then `git hash-object` of every changed file (0) and `node --version` (0). |
| `raw/baseline-test-diff.log` | `exit_code` 0; the staged baseline test files and the final test files differ only in two comments. |

### Red baseline

`raw/tests-before.log` runs these commands in order.

1. `git rev-parse`, `exit_code` 0: `HEAD` `f31eb22b72588b095e3b031ecf7606665c37fd6e`, `tools/lib.mjs` `ef00cf6d3dfae846f97f99a9b9950d2b98a8f043`, `tools/corpus.mjs` `0eb3ae5e27a25f451795b4860e9b4f5a29ec30c8`, `tools/fileset.mjs` `bab5d684a45e3b5b2ff69b1e0fa956b533f02ac6`, `tools/selftest.mjs` `3735e387a9adc453c8c74caf3a3a3d1312db528e`, and `tools/fileset.test.mjs` `10075c1287b102f90a318404ade343f59ef6db51`.
2. `git status --short`, `exit_code` 0: only the two test files are modified.
3. The staging command `git add -- tools/selftest.mjs tools/fileset.test.mjs`, `exit_code` 0.
4. `git ls-files --stage`, `exit_code` 0: the three implementation files keep their `HEAD` blobs; the staged `tools/selftest.mjs` is `1df33e88e198882b4b881394f56aed60099ebe3a`, and the staged `tools/fileset.test.mjs` is `7a3ec9a3dcfc650b6e54a0540ede99a2508ddaa1`.
5. `git diff --cached --stat`, `exit_code` 0: 122 insertions in the two test files.
6. `node tools/fairpane.mjs test`, `exit_code` 1, with 213 of 220 passing.
   FP-0052 cases 1, 3, 4, 5, both parts of 6, and the `SystemRoot` case fail as "Criterion mapping" describes.
   The `SystemRoot` case fails because the command started and exited with status 134 instead of being refused.
   Case 2 passes.
7. `git reset -q -- tools/selftest.mjs tools/fileset.test.mjs` and `git diff --cached --stat`, `exit_code` 0 each, which leave the index at `HEAD`.

### Mutation hashes

| Control | File | Before | During | After |
| --- | --- | --- | --- | --- |
| 1 | `tools/fileset.mjs` | `5aab6c1f23c49e4a057a470a379d2783683ee0c8` | `172dd749071260c9a9fa8a6f1f9fcda25c48ecd9` | `5aab6c1f23c49e4a057a470a379d2783683ee0c8` |
| 2 | `tools/fileset.mjs` | `5aab6c1f23c49e4a057a470a379d2783683ee0c8` | `5296a4aba9561de7db7073c59d6c7427b386ee6f` | `5aab6c1f23c49e4a057a470a379d2783683ee0c8` |
| 3 | `tools/lib.mjs` | `b037dcc632eab9b3c60f83f8d2d28554e7001dfc` | `589ac2797df5a042ccf049da6b0760e3af08cc93` | `b037dcc632eab9b3c60f83f8d2d28554e7001dfc` |
| 4 | `tools/corpus.mjs` | `0c6b76b52e935d4cb1eb6345266d6e73d76ca1a4` | `f9aec6c2b40ae445de2be4775f4bd23318d71c69` | `0c6b76b52e935d4cb1eb6345266d6e73d76ca1a4` |

Each "before" and "after" blob equals the final file in `raw/controller-tests-after.log`.

## Amendment 1

Contract amendment 1, frozen at `7861102`, replaces the Windows stand-in of case 2.
The worker revised case 2 in an isolated working tree whose `HEAD` was `7861102755784a4dddfc18fff9c8b5cb84c2961d`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0.

### Revised case 2

- On Windows, `taskkill.exe` in the case's directory is a hard link to `process.execPath`, or a copy of it when `fs.linkSync` fails.
- The case writes `preload.cjs` in its directory.
  The preload does nothing unless the lowercase base name of `process.execPath` is `taskkill.exe`.
  Then it writes the marker `taskkill.ran` in the case's directory and calls `process.exit(0)`, which runs before Node loads its script argument.
- Inside its `try` block, the case sets `NODE_OPTIONS` to `--require` and the JSON-quoted path of the preload.
  Node's `NODE_OPTIONS` parser removes the backslash escapes inside double quotes, so the quoted Windows path reaches `--require` unchanged.
  The `finally` block restores the previous value, or deletes the variable when it was unset.
- Before it starts `runProcess`, the case runs the stand-in by its full path with `/PID 1 /T /F`, asserts exit status 0 and the marker, and removes the marker.
- The case then asserts that `runProcess` returns `timed_out: true` within 15 seconds and that no marker exists.
- The `finally` block also stops the sleeping command through its process ID file, as the frozen case did.
- The case prints the TAP comment `# FP-0052 case 2 took <ms> ms.`, so each log records its duration.
- Other hosts keep the frozen case: a `#!/bin/sh` script that exits with status 0, and no preload or marker.
  This revision did not run on Linux.

### Amendment 1 records

| Log | RESULT |
| --- | --- |
| `raw/tests-before-a1.log` | Red baseline: case 2 fails on the base watchdog. See "Amendment 1 red baseline". |
| `raw/mutation-a1.log` and `raw/mutation-a1.diff` | The bare-name control: `node tools/selftest.mjs` exits with status 1, 222 of 224 pass, and case 2 fails with "runProcess did not return within 15 seconds, so the watchdog did not stop its command." after 15065 ms. The `SystemRoot` case also fails ("134 !== null"). See "Amendment 1 mutation hashes". |
| `raw/controller-tests-after-a1.log` | `git rev-parse HEAD` (0) prints `7861102755784a4dddfc18fff9c8b5cb84c2961d`. `node tools/fairpane.mjs test` exits with status 0, 224 of 224 pass, and case 2 prints "took 2401 ms" and passes. `git hash-object` (0) prints `tools/lib.mjs` `b037dcc632eab9b3c60f83f8d2d28554e7001dfc` and `tools/selftest.mjs` `572d5ae9d4e8b99ce7ab559ff4ac0ee6f44c9129`, and `node --version` (0) prints `v26.7.0`. |

### Amendment 1 red baseline

The base before `775d988` is `44b083c8f5fc367bb9843bd588bd7ba886d6857a`; only a state commit separates it from the `f31eb22` base of `raw/tests-before.log`.
`raw/tests-before-a1.log` stages the test files on that base in a scratch clone, as `raw/tests-before.log` did in its working tree, and runs these commands in order.

1. `git rev-parse HEAD 775d988^`, `exit_code` 0: `7861102755784a4dddfc18fff9c8b5cb84c2961d` and `44b083c8f5fc367bb9843bd588bd7ba886d6857a`.
2. The scratch command `git clone --shared --no-checkout --quiet . out/fp0052-a1-base`, `exit_code` 0.
3. `git -C out/fp0052-a1-base checkout --quiet --detach 44b083c8f5fc367bb9843bd588bd7ba886d6857a`, `exit_code` 0.
4. `git -C out/fp0052-a1-base checkout 775d988 -- tools/selftest.mjs tools/fileset.test.mjs`, `exit_code` 0.
   This takes the FP-0052 test files of `775d988`, which `raw/baseline-test-diff.log` shows differ from the staged files of `raw/tests-before.log` only in two comments.
   The worker then replaced case 2 in the scratch `tools/selftest.mjs` with the revised case; no command records that edit, and step 10 shows its result.
5. The staging command `git -C out/fp0052-a1-base add -- tools/selftest.mjs tools/fileset.test.mjs`, `exit_code` 0.
6. `git -C out/fp0052-a1-base rev-parse HEAD`, `exit_code` 0: `44b083c8f5fc367bb9843bd588bd7ba886d6857a`.
7. `git -C out/fp0052-a1-base status --short`, `exit_code` 0: only the two staged test files are modified.
8. `git -C out/fp0052-a1-base ls-files --stage`, `exit_code` 0: `tools/lib.mjs` `ef00cf6d3dfae846f97f99a9b9950d2b98a8f043`, `tools/corpus.mjs` `0eb3ae5e27a25f451795b4860e9b4f5a29ec30c8`, and `tools/fileset.mjs` `bab5d684a45e3b5b2ff69b1e0fa956b533f02ac6`, the same base blobs as `raw/tests-before.log`; the staged `tools/selftest.mjs` is `18e44ba3d6671632de44fecaac5995a99a072d1e`, and the staged `tools/fileset.test.mjs` is `04cc975ae2d07c8a99e6407e1e7fb07b1e863c0d`.
9. `git -C out/fp0052-a1-base diff --cached --stat`, `exit_code` 0, and `git -C out/fp0052-a1-base grep -n -e taskkill -- tools/lib.mjs`, `exit_code` 0, which shows that the base watchdog runs `spawnSync('taskkill.exe', …)` at `tools/lib.mjs:530`.
10. `git diff --no-index --stat` and `git diff --no-index` of the staged `tools/selftest.mjs` against the revised `tools/selftest.mjs`, `exit_code` 1 each because the files differ.
    The only hunk adds the FP-0082 case 18 block that `7861102` has and `775d988` lacks, so the staged case 2 equals the revised case 2.
11. `node tools/fairpane.mjs test` with `--cwd out/fp0052-a1-base`, `exit_code` 1, with 212 of 220 passing.
    Case 2 fails with "runProcess did not return within 15 seconds, so the watchdog did not stop its command." after 15052 ms, so the stand-in's direct check passed first.
    The other seven failures are the ones that `raw/tests-before.log` records: cases 1, 3, 4, 5, both parts of 6, and the `SystemRoot` case.

### Amendment 1 mutation hashes

| Control | File | Before | During | After |
| --- | --- | --- | --- | --- |
| Bare name | `tools/lib.mjs` | `b037dcc632eab9b3c60f83f8d2d28554e7001dfc` | `0f4ec2b61b1221a17ffc4f4798d5c14ecf4cf486` | `b037dcc632eab9b3c60f83f8d2d28554e7001dfc` |

The mutation keeps the original at `out/fp0052-a1/mutation/lib.mjs`, and the restoration compares the bytes.
The "before" and "after" blobs equal `tools/lib.mjs` in `raw/controller-tests-after-a1.log`.

## Amendment 2

Contract amendment 2, frozen at `0954a37`, makes the Windows stand-in of case 2 follow the host that runs the suite.
The worker implemented it in an isolated working tree whose `HEAD` was `0954a372771219d7ba124ffd41c705cc87be2c76`.
The host was Windows 10.0.26200 on x64 with Node v26.7.0 and Bun 1.4.2.

### Bun preload probe

`raw/probe-bun-preload-a2.log` runs these commands in order.

1. `bun --version`, `exit_code` 0: `1.4.2`.
2. A `bun -e` setup, `exit_code` 0.
   It creates `out/fp0052-a2/probe-bun-preload`, hard-links Bun's `process.execPath` there as `taskkill.exe` (link count 2), and writes `preload.cjs` and `bunfig.toml`.
   The preload writes the marker `taskkill.ran` with the base name of `process.execPath` and calls `process.exit(0)`.
   `bunfig.toml` holds `preload = ["<absolute path of preload.cjs>"]`.
3. `taskkill.exe /PID 1 /T /F` with that directory as its working directory, `exit_code` 1, with the output `error: Module not found "/PID"`.
4. A `node -e` check, `exit_code` 0: "Marker exists after the run: false."

Bun does not run the `bunfig.toml` preload before it resolves `/PID`, so case 2 does not use one.

### Revised case 2 under amendment 2

- `taskkillStandInSource` in `tools/selftest.mjs` names the program that case 2 hard-links or copies as `taskkill.exe`.
  Under Node, which it detects by the absence of `process.versions.bun` and `process.versions.deno`, it returns `process.execPath`, so amendment 1's stand-in is unchanged.
  Under any other host, it resolves `node` through `PATH` with `resolveExecutable` and returns its real path, so the hard link names the file and not a symbolic link.
  Without a Node executable on `PATH`, it throws `FP-0052 case 2 needs Node on PATH to build its stand-in.`
- Case 2 calls it before it creates the stand-in, so a failure changes no process-wide state.
  The preload, `NODE_OPTIONS`, the direct check of the stand-in, the marker checks, and the `finally` block that restores `NODE_OPTIONS` and the working directory and stops the sleeping command are as amendment 1 defines them.
  The case directory comes from `temp()`, which the suite removes at the end, as before.
- A new case, "FP-0052 case 2, amendment 2", checks the three outcomes of `taskkillStandInSource`: `process.execPath` under Node, the real path of a `node` file on a fixture `PATH` under another host, and the exact error with an empty `PATH`.

### Amendment 2 records

| Log | RESULT |
| --- | --- |
| `raw/probe-bun-preload-a2.log` | The probe above: the stand-in exits with status 1, and no marker exists. |
| `raw/bun-selftest-after-a2.log` | `bun --version` (0) prints `1.4.2`. `bun tools/selftest.mjs` exits with status 0, 236 of 236 pass, and case 2 prints "took 2417 ms" and passes. `git hash-object` (0) prints `tools/selftest.mjs` `6a70718ebc26e7d61edc9697ab4ab80562aa5b42` and `tools/lib.mjs` `921c9cfd3c460bb02ab0638e51c03086b2235002`. |
| `raw/controller-tests-after-a2.log` | `git rev-parse HEAD` (0) prints `0954a372771219d7ba124ffd41c705cc87be2c76`. `node tools/fairpane.mjs test` exits with status 0, 236 of 236 pass, and case 2 prints "took 2050 ms" and passes. `git hash-object` (0) prints the same two blobs as the Bun log, and `node --version` (0) prints `v26.7.0`. |
| `raw/mutation-a2.log` | The bare-name control under both hosts; see "Amendment 2 mutation". |
| `raw/check-a2.log` | `node tools/fairpane.mjs check` exits with status 0 on the final `tools/selftest.mjs`; it ran before this table row was added. |

`raw/bun-selftest.log` is the failure that amendment 2 cites; the contract places it at `a342961`, and the log does not record `HEAD`.
It records `bun tools/selftest.mjs` with `exit_code` 1: 234 of 235 pass, and case 2 fails with "error: Module not found "/PID"" after 23 ms.

### Amendment 2 mutation

`raw/mutation-a2.log` runs these commands in order.

1. `git hash-object tools/lib.mjs`, `exit_code` 0: `921c9cfd3c460bb02ab0638e51c03086b2235002`.
2. The mutation, `exit_code` 0.
   It keeps the original at `out/fp0052-a2/mutation/lib.mjs` and makes `treeStopProgram` return the bare name `taskkill.exe` on Windows.
3. `git hash-object tools/lib.mjs`, `exit_code` 0: `35da1e1f4285835d2e6a133c692db727cd63a75b`.
4. `git diff --no-index` of the original against the mutated file, `exit_code` 1 because the files differ; the log holds the one-line hunk.
5. `node tools/selftest.mjs`, `exit_code` 1, with 234 of 236 passing.
   Case 2 fails with "runProcess did not return within 15 seconds, so the watchdog did not stop its command." after 15070 ms, and the `SystemRoot` case fails with "134 !== null".
6. `bun tools/selftest.mjs`, `exit_code` 1, with 234 of 236 passing.
   Case 2 fails with the same message after 15054 ms, and the `SystemRoot` case fails with "0 !== null".
7. The restoration, `exit_code` 0, which compares the restored bytes with the original.
8. `git hash-object tools/lib.mjs`, `exit_code` 0: `921c9cfd3c460bb02ab0638e51c03086b2235002`.

| Control | File | Before | During | After |
| --- | --- | --- | --- | --- |
| Bare name | `tools/lib.mjs` | `921c9cfd3c460bb02ab0638e51c03086b2235002` | `35da1e1f4285835d2e6a133c692db727cd63a75b` | `921c9cfd3c460bb02ab0638e51c03086b2235002` |

The "before" and "after" blobs equal `tools/lib.mjs` in both "after" logs.

## Open items

- Amendment 1 resolves the case 2 defect on Windows under Node, and amendment 2 under Bun; see "Amendment 1" and "Amendment 2".
  The revised case has not run on Linux.
- The integrator records `HEAD` and a status that includes ignored files for every source root before and after `repo-check` and `controller-test`.
- The integrator runs and records `corpus-verify test262` and `corpus-verify wpt` at the integration commit.
- The contract says that the plan criterion names all three system programs; `engineering/plan.json` is outside this task's writable paths.
