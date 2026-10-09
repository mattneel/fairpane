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
| Case 2: a `taskkill.exe` in the working directory does not keep `runProcess` from returning `timed_out: true` within 15 seconds. | Passes in `raw/tests-before.log` on Windows, so it does not fail before the change; see "Contract defect in case 2". Passes in `raw/controller-tests-after.log` and `raw/linux-controller-tests.log`. |
| Case 3: a Git corpus repin that fails at each of the four write steps changes nothing. | Fails in `raw/tests-before.log` ("Missing expected rejection: stage the record"); passes after on both hosts. The case also requires that an uninjected repin runs exactly those four steps. |
| Case 4: a failed removal of `<id>.old` after the record is replaced fails with "could not remove the old copies", and the new record and snapshot stay. | Fails in `raw/tests-before.log`, where the raw "injected removal failure" escaped before the record was written; passes after on both hosts. The case replaces `fs.rmSync` only for `<corpora>/test262.old` while it exists. |
| Case 5: with `test262.lock` present, a fetch fails with the lock error and changes nothing. | Fails in `raw/tests-before.log` ("Missing expected rejection."); passes after on both hosts. |
| Case 6: two fetches started together end with one `pass` and one lock error, only the corpus directory remains, and `corpus-verify` passes, for the Git corpus and for a file set. | Both parts fail in `raw/tests-before.log`: the Git fetches both failed (an `EPERM` on `test262.fetch` and "git init exited with status 128"), and the file-set fetches ended with one `pass` and an `ENOENT` rename of `unicode.fetch`. Both pass after on both hosts. |
| Case 7: every existing file-set write-phase case passes unchanged. | `tools/fileset.test.mjs` keeps every existing case byte for byte; `FP-0013 case 54` and the other FP-0013 cases pass in `raw/controller-tests-after.log` and `raw/linux-controller-tests.log`. |
| Case 8: `corpus-applicability wpt` regenerates the record, and the diff changes only the rule text. | `raw/applicability.log` (exit 0, `FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, no fetch) and `raw/applicability-diff.log` (one line changed: `discovery.rule`). |
| Mutation: skip the restore of the old snapshot directory. | `raw/mutation-1.diff`; cases FP-0052 3 and FP-0013 54 fail, 218 of 220 pass. |
| Mutation: remove the lock check. | `raw/mutation-2.diff` opens the lock with `w` instead of `wx`; FP-0052 case 5 and both parts of case 6 fail, 217 of 220 pass. |
| Mutation: start `taskkill.exe` by bare name. | `raw/mutation-3.diff`; the extra FP-0052 `SystemRoot` case fails, 219 of 220 pass. Case 2 passes under this mutation, as it does on the base. |
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

## Open items

- Case 2 needs a contract amendment; see "Contract defect in case 2".
- The integrator records `HEAD` and a status that includes ignored files for every source root before and after `repo-check` and `controller-test`.
- The integrator runs and records `corpus-verify test262` and `corpus-verify wpt` at the integration commit.
- The contract says that the plan criterion names all three system programs; `engineering/plan.json` is outside this task's writable paths.
