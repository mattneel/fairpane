# FP-0076 evidence

## Scope

Task `FP-0076` closes the findings of `engineering/evidence/FP-0054/reviews/review-2-accept.json` that the frozen contract `engineering/evidence/FP-0076/CONTRACT.md` names.
The worker implemented it in an isolated working tree whose `HEAD` was `775d988c75435779d4bab06b978391204d86e216`, the master head when the work began.
The Windows host was `Microsoft Windows [Version 10.0.26200.9457]`, x64.
The POSIX host was WSL Ubuntu 24.04.5 LTS, `Linux 7.2.6-locietta-WSL2-xanmod1 x86_64`, as uid 1000, with the locked `x86_64-linux` compiler that `raw/wsl-environment.log` reports as `0.18.0-dev.120+9fe22a29b`.

## Implementation

- `fileIdentity` in `src/lab_main.zig` no longer opens either file for reading.
  On Linux it calls `statx` on the path with `AT_FDCWD`, flags 0, and the `INO` mask, and it reads `stx_dev_major`, `stx_dev_minor`, and `stx_ino`.
  On other POSIX systems it calls `fstatat` on the path with `AT_FDCWD` and flags 0, and it reads `st_dev` and `st_ino`.
  On Windows it opens a handle with `NtCreateFile` whose access is `FILE_READ_ATTRIBUTES` and `SYNCHRONIZE`, with every share mode and no `FILE_OPEN_REPARSE_POINT`, and it reads `FILE_ID_INFORMATION` as before.
  Every branch follows symbolic links.
- `refuseInputAsOutput` keeps its order and messages: equal spellings first, then the output identity, where `FileNotFound` means "not the input file", then the input identity.
  Every other failure still becomes `lab.fileFailure` with the subject of the file that failed.
  The guard and `fileIdentity` no longer take an `Io` argument, because they no longer use it.
- `build.zig` runs FP-0054 case 5 in a directory that `check fresh` creates on every run, instead of the cached `WriteFiles` copy.
  The input is the absolute path of `case.json` in that directory, and the output is `case.json` relative to it.
- Revision 1 case 5 of FP-0054 is one `check oversized` step.
  The helper creates both oversized files, runs `run`, `minimize`, and `replay` as child processes, checks each exit status and detail and that `minimized.json` does not exist, removes both files, confirms that neither remains, and only then writes its report.
  The report has one `pass` or `fail` line per check, and the build compares it exactly.
- `tests/lab/check.zig` gains the layouts `symlink`, `unreadable`, and `empty` for `check fresh`, and the commands `readable`, `entries`, `fifo`, and `oversized`.
  It drops the `oversized` layout and the `absent` and `remove` commands, which no step uses any longer.
- `tests/lab/README.md` describes the helper's new duties.

## Exact test cases

| Case | Hosts | Build steps |
| --- | --- | --- |
| 1 | POSIX | `FP-0076 case 1: run writes its transcript into a FIFO that a helper reads to end of file` |
| 2 | POSIX | `FP-0076 case 2: minimize writes over an existing out.json of mode 0200`, then `restore read access to out.json` and `out.json is a version 2 case derived from the input digest` |
| 3 | Windows | `FP-0076 case 3: minimize writes over an existing out.json whose ACL denies read-data access to Everyone`, then the same two steps as case 2 |
| 4 | Both | `FP-0076 case 4: minimize reports the output path case.json/out.json, which cannot be identified` on POSIX hosts or `... out|.json ...` on Windows, then `FP-0076 case 4: the directory gains no file` |
| 5 | POSIX | `FP-0076 case 5: minimize refuses an --out path that is a symbolic link to the input file`, then `the refused minimization leaves the input unchanged` |
| 6 | Both | `FP-0054 case 5: minimize refuses an --out path that names the input file through another spelling` and `FP-0054 case 5: the refused minimization leaves the input unchanged`, in the fresh directory `fp0054-case-5` |
| 7 | Both | `FP-0054 revision 1 case 5: run, minimize, and replay report files one byte above the size limit`, `FP-0076 case 7: the revision 1 case 5 helper reports failing checks and removes both oversized files`, and `FP-0076 case 7: no file remains after the failing run` |

Case 4 asserts `"detail": "output file: NotDir"` on POSIX hosts and `"detail": "output file: BadPathName"` on Windows, which `raw/probe.log` records on each host.

## Records

Every log ends each command with a `RESULT` line.

| Log | Content and `RESULT` |
| --- | --- |
| `raw/wsl-environment.log` | `exit_code` 0. Ubuntu 24.04.5 LTS, uid 1000, Zig `0.18.0-dev.120+9fe22a29b`, Git 2.43.0, and a starting directory that holds `build.zig`. |
| `raw/probe.log` | `exit_code` 0 for every setup command. On Windows, the base and the changed laboratory both report `output file: BadPathName` with `exit_code` 3 for `--out out|.json`, and the directory then holds only `case.json`. On WSL, both report `output file: NotDir` with exit status 3 for `--out case.json/out.json`, and the directory then holds only `case.json`. The copied trees match `af8b745` (base) and `8a8db6b` (changed). |
| `raw/tests-before.log` | `HEAD` `775d988`, the staging command `git add build.zig tests/lab/check.zig` into the temporary index `out/fp0076/before.index`, the staged blobs `c2f4222` (`build.zig`) and `e4b5e0f` (`tests/lab/check.zig`), and the tree `031f95b`. The build ran on the exported tree with `src/lab_main.zig` blob `c78c460`: `exit_code` 1, 67 of 71 steps and 300 of 300 tests. Case 3 fails with `output file: AccessDenied`. |
| `raw/tests-before-linux.log` | The same `HEAD`, staged blobs, and tree, and a WSL copy whose tree is `031f95b`: `exit_code` 1, 68 of 73 steps and 300 of 300 tests. Case 1 fails with `the laboratory did not finish within 30 seconds`, and case 2 fails with `output file: AccessDenied`. |
| `raw/mutation.log` | Two rounds of both controls, with `git hash-object src/lab_main.zig` before, during, and after each. See below. |
| `raw/tests-after.log` | `HEAD` `775d988`, the four changed blobs, the tree `973d031`, `git status` showing only those four files changed under `build.zig`, `src`, and `tests`, and `ver`. `zig build test --summary all --cache-dir out/fp0076-after`, a cache directory that did not exist before: `exit_code` 0, 71 of 71 steps and 300 of 300 tests. |
| `raw/tests-after-linux.log` | The same `HEAD`, blobs, and tree, and a WSL copy whose tree is `973d031`, with `uname`, `os-release`, and uid 1000. `zig build test --summary all --cache-dir .zig-cache-after`, which the command checks is absent first: `exit_code` 0, 73 of 73 steps and 300 of 300 tests. |
| `raw/fmt.log` | `zig fmt --check build.zig src tests`: `exit_code` 0. |
| `raw/controller-tests-after.log` | `node --version` v26.7.0 and `node tools/fairpane.mjs test`: `exit_code` 0, 220 of 220 controller tests. |
| `raw/cross-build.log` | `zig build check` with `-Dtarget=x86_64-linux` and with `-Dtarget=aarch64-macos`: `exit_code` 0 for both. The macOS build compiles the `fstatat` branch and the `mkfifo` path; it does not run them. |
| `raw/development.log` | Compile, format, and full-suite runs during development, kept as one appended log. Every entry has `exit_code` 0. |

The Windows suite has 71 steps and the WSL suite has 73.
Windows adds FP-0054 revision 1 case 3 and FP-0076 case 3; WSL adds FP-0076 cases 1, 2, and 5.

### Mutation controls

Each control saves the source under `out/fp0076/mutation/`, replaces exactly one occurrence, records the diff with `git diff --no-index --output`, runs the suite, restores the saved source, and records the hash again.
`git diff --no-index` exits with status 1 because the files differ.

| Control | Diff | Hashes before, during, after | Run | Result |
| --- | --- | --- | --- | --- |
| Case 5, round 1 | `raw/mutation-5.diff` | `ae3e3ca`, `25e9b68`, `ae3e3ca` | WSL, tree `2a142c9` | `exit_code` 1, 70 of 73 steps. Only case 5 fails: `minimize` reports `pass` and writes through `link.json`. |
| Case 7, round 1 | `raw/mutation-7.diff` | `ae3e3ca`, `ff20622`, `ae3e3ca` | Windows and WSL, tree `5e436f7` | `exit_code` 1 on both, 69 of 71 and 71 of 73 steps. Only the revision 1 case 5 helper fails, with `fail: run reports a case file one byte above the size limit: the detail is not "case file: exceeds the size limit"`. The listing of its directory after the failed build shows 0 entries on both hosts. |
| Case 5, round 2 | `raw/mutation-5-r2.diff` | `ce2657d`, `47634d7`, `ce2657d` | WSL, tree `bc6aebc` | The same result as round 1. |
| Case 7, round 2 | `raw/mutation-7-r2.diff` | `ce2657d`, `d040d9c`, `ce2657d` | Windows and WSL, tree `1f43c36` | The same result as round 1, with 0 entries on both hosts. |

The case 5 control passes flags `linux.AT.SYMLINK_NOFOLLOW` to `statx`, so the output is identified without following symbolic links.
The case 7 control changes the `run` command's case-file subject to `transcript file`.
Round 1 ran on `src/lab_main.zig` blob `ae3e3ca`.
A comment-only edit to the Windows branch of `fileIdentity` then produced the final blob `ce2657d`, so round 2 repeats both controls on the final source.

## Procedure

Each run on a tree other than the working tree stages its files in a temporary index named by `GIT_INDEX_FILE` under `out/fp0076/`, so the working tree's own index stays unchanged.
`git write-tree` names the staged tree, and `git archive` exports it.
Each WSL run extracts the archive into `$HOME/fairpane-linux/work/FP-0076`, which it deletes first, then records `git write-tree` of a new repository over the copy.
Every recorded WSL tree equals the tree that Windows staged, which shows that the copy kept every file and every file mode.
The Windows red baseline ran on the exported tree in `out/fp0076/before`.

## Contract defect

The contract requires cases 1 to 4 to fail before the change.
Case 4 cannot fail before the change with the frozen paths and the guard's unchanged messages.
`raw/probe.log` shows that the base laboratory already reports exactly `output file: BadPathName` on Windows and `output file: NotDir` on WSL, with exit status 3 and no new file.
The base laboratory's `openFile` maps `STATUS_OBJECT_NAME_INVALID` to `BadPathName` and `ENOTDIR` to `NotDir`, the same error names that the new identification returns.
Both baselines record case 4 as passing.
Cases 1, 2, and 3 fail before the change on their hosts.
Case 4 still tests the failure path that the change rewrote: an unidentifiable output is a harness error that names `output file`, and it writes nothing.
Contract amendment 1 (`3bea7a6`) exempts case 4 from the red baseline and requires it to fail under a control that reports an unidentified output path with the input's subject; see "Integration".

## Resolved ambiguities

- The contract allows `stat` or `fstatat` on other POSIX systems.
  The implementation uses `fstatat` with `AT_FDCWD` through `std.posix.system`, the binding that the pinned standard library's own `statFile` uses, and the `aarch64-macos` cross-build compiles it.
- The Windows handle also requests `SYNCHRONIZE`, which the synchronous I/O mode requires; it requests no data access other than `FILE_READ_ATTRIBUTES`.
- The case 1 helper opens the FIFO with `O_RDONLY | O_NONBLOCK` before it starts the laboratory and reads standard output, standard error, and the FIFO through one `MultiReader` with a 30-second deadline.
  On Linux, `poll` reports neither data nor hang-up on that descriptor until a writer has opened the FIFO, so the helper never mistakes an unopened FIFO for end of file.
  The transcript check parses the bytes as JSON, requires `version` 2 and `action_count` equal to the number of `actions`, and requires the laboratory's own `replay` to report `pass`, which parses it with the canonical transcript parser.
- Cases 2 and 3 share the `unreadable` layout.
  `check fresh` confirms that opening `out.json` for reading fails with `AccessDenied` before the laboratory runs, so the case cannot pass vacuously.
  On POSIX hosts the layout first fails with `case 2 needs a non-root user` when the effective user is root.
  On Windows it adds one explicit ACE, `D:(D;;0x1;;;WD)`, with `SetNamedSecurityInfoW` and an unprotected DACL, so the file keeps the ACEs it inherits.
  `check readable` sets the DACL to `D:` the same way, which removes the denial and keeps the inherited ACEs.
- Case 7's failing run uses the check executable in place of the laboratory, so every laboratory check fails with the usage status 2 on every host and the helper's removal path runs in every build.
  The mutation controls show the same removal with the real laboratory.
- `RESULT` lines record each command's working directory and resolved executable, and the controller suite prints temporary paths under the user profile, as earlier evidence does.
  No recorded command lists a home directory or a user profile.

## Integration

The integrator applied the worker's patch on `3bea7a6` with `git apply --3way`.
It applied without conflicts, merged with the FP-0066 and FP-0082 changes to `build.zig`, and changed no contract text.
The implementation is commit `d56bc5f`.

- `raw/integration-binding.log` records `HEAD` `d56bc5f` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T15-42-32-017Z-repo-check-2d0c24b7.json`, `gates/2026-10-09T15-42-32-440Z-controller-test-6d02f1a6.json`, `gates/2026-10-09T15-43-27-009Z-zig-fmt-1e374c06.json`, and `gates/2026-10-09T15-43-27-307Z-zig-test-db8aab34.json` pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0076-integration`: 100 of 100 build steps and 321 of 321 tests pass.
- `raw/bun-selftest.log` records Bun and `tools/selftest.mjs` with 224 of 224 tests.
- `raw/integration-tests-linux.log` clones the repository at `d56bc5f` in WSL Ubuntu with no status lines and runs the suite as uid 1000 with the fresh cache `out/fp0076-integration-linux`: 102 of 102 build steps and 321 of 321 tests pass.
- `raw/integration-mutation-4.log` and `raw/integration-mutation-4.diff` run amendment 1's control.
  The control changes the guard's detail for an unidentified output path from the output's subject to the input's subject.
  `src/lab_main.zig` hashes to `ce2657d` before, `a6b1a07` during, and `ce2657d` after; the WSL clone records the same hashes.
  On Windows, 97 of 100 steps succeed: `FP-0076 case 4: minimize reports the output path out|.json, which cannot be identified` fails with the detail `case file: BadPathName`, and its dependent "the directory gains no file" step does not run.
  On WSL Ubuntu, 99 of 102 steps succeed, and the same case fails for `case.json/out.json` with `case file: NotDir`.
  No other step fails on either host.
