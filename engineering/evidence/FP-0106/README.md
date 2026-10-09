# FP-0106 evidence

## Scope

Task `FP-0106` closes the minor findings of FP-0066 review 1 and FP-0076 review 1 that the frozen contract `engineering/evidence/FP-0106/CONTRACT.md` names.
The worker implemented it in an isolated working tree whose `HEAD` was `b8313e622326ba6ba8438455d947a487c8ac3add`, the commit that froze the contract.
The Windows host was `Microsoft Windows [Version 10.0.26200.9457]`, x64.
The POSIX host was WSL Ubuntu 24.04.5 LTS, `Linux 7.2.6-locietta-WSL2-xanmod1 x86_64`, as uid 1000, with the locked `x86_64-linux` compiler that `raw/wsl-environment.log` reports as `0.18.0-dev.120+9fe22a29b`.
Every Windows Zig command used `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
The `c-abi` gate resolves the locked compiler through the work tree's `.tools` directory, so the worker created the ignored junction `.tools` to `C:\src\fairpane\.tools` in each tree that ran the gate, as FP-0050 and FP-0081 did.

## Implementation

- `tools/lib.mjs`: after the Debug smoke test, the `c-abi` gate removes `<root>/out/c-abi-release`, runs `zig build -Doptimize=ReleaseSafe --prefix <root>/out/c-abi-release`, finds exactly one of `fairpane.lib`, `libfairpane.a`, and `fairpane.a` under its `lib` directory, and runs `node tools/fairpane.mjs abi-exports` on it.
  Both are recorded gate commands, so a failure fails the gate and names the command.
  One helper finds the static library for both builds, and one helper runs `abi-exports` for both.
- `tools/README.md:242` says that the gate runs `abi-exports` on the Debug library and on a ReleaseSafe library, and `tools/README.md:291` and `build.zig:378` say that FP-0066 case 3 runs in the `c-abi` gate.
- `tools/zig/library_check.zig`: `find(haystack, needle) error{EmptyNeedle}!?usize` takes no allocator and stores no folded copy.
  It compares `fold(haystack[i + j])` with `fold(needle[j])` as it reads each byte, and it moves the window by Horspool's rule with a 256-entry skip table indexed by folded bytes, which the contract allows.
  `reportAbsent(path, bytes, needles) u8` takes no allocator; an empty needle prints a message and returns the usage status 2.
  The `names` command calls the same `find`.
- `src/lab.zig` declares `WindowsIdentityError`, `WindowsIdentityStep`, `windowsIdentityStep`, and `windowsIdentityBackoffMs` exactly as the contract states.
  `windowsIdentityStep` has one arm for each arm of the pinned `dirOpenFileWtf16` switch (`Io/Threaded.zig:5167-5224`), and every other status maps to `unexpected`.
  `windowsIdentityBackoffMs(attempt)` returns `(1 << attempt) >> 1` for attempts 0 to 12 and null from attempt 13, the pinned `max_windows_kernel_bug_retries`.
- `src/lab_main.zig`: `refuseInputAsOutput(io, input, output)` and `fileIdentity(io, path)` take `io`, and both callers pass theirs.
  The order of checks is unchanged.
  On Windows, `fileIdentity` keeps one attempt counter and applies the step of each `NtCreateFile` status: `opened` continues to the unchanged `NtQueryInformationFile` switch, `retry` runs `try io.checkCancel()` and opens again, `retry_after_backoff` returns `error.FileBusy` when the backoff is null and otherwise runs `try io.sleep(.fromMilliseconds(ms), .awake)`, adds 1, and opens again, `fail` returns its error, `bug` returns `windows.statusBug(status)`, and `unexpected` returns `windows.unexpectedStatus(status)`.
- `src/lab_identity_test.zig` holds case 6, and `src/root.zig` imports it in its test block.
- `tests/lab/check.zig` gains `check delete-pending <laboratory> <directory>` on Windows, and `build.zig` adds case 5 on Windows hosts in `addFp0106Cases`.
  `tests/lab/README.md` describes the new helper duty.

## Exact test cases

| Case | Where | Evidence |
| --- | --- | --- |
| 1 | `c-abi` gate | `raw/c-abi-after.log` and `raw/gates-after/2026-10-09T20-19-18-491Z-c-abi-c7d92f07.*`: status `pass`. The ReleaseSafe `zig build` exits 0 in 4688 ms, and `abi-exports` on `out/c-abi-release/lib/fairpane.lib` reports `"result": "pass"` and `"exports": 15`. |
| 2 | `c-abi` gate with R | Base: `raw/c-abi-before-R.log` and `raw/gates-before-R/2026-10-09T20-17-09-214Z-c-abi-273eb330.*`, status `pass` with 15 Debug exports. After: `raw/c-abi-after-R.log` and `raw/gates-after-R/2026-10-09T20-21-19-482Z-c-abi-b493555c.*`, status `fail`. The receipt `error` is `Gate command failed: [...,"abi-exports","out/c-abi-release/lib/fairpane.lib"]`, that command reports `"result": "fail"` and `"missing": ["fp_abi_revision"]` with exit 1, and the Debug `abi-exports` before it exits 0 with 15 exports. |
| 3 | `library-test`, `tools/zig/library_check.zig` | `FP-0106 case 3: find and reportAbsent take no allocator and neither allocates nor copies` |
| 4 | `library-test`, `tools/zig/library_check.zig` | `FP-0066 (amended by FP-0106 case 4): a search ignores letter case and the path separator` |
| 5 | Windows `zig build test` | `FP-0106 case 5: minimize reports output file: FileBusy for an --out file that stays pending deletion through every retry`, then `FP-0106 case 5: after the helper closes its handle, the directory holds only case.json` |
| 6 | `zig build test` on every host | `FP-0106 case 6: windowsIdentityStep maps each status as the pinned dirOpenFileWtf16 does` and `FP-0106 case 6: windowsIdentityBackoffMs gives 13 waits from 0 ms to 2048 ms that sum to 4095 ms, then null` |
| 7 | Both hosts and the gate | Every `library-test` step, every FP-0076 step, and FP-0066 case 3 through case 1 pass in `raw/tests-after.log`, `raw/tests-after-linux.log`, and `raw/c-abi-after.log`. |

## Criterion mapping

| FP-0106 criterion | Cases and evidence | Result |
| --- | --- | --- |
| 1. Check ReleaseSafe exports in a gate | Cases 1 and 2; R | Met on the development host. The integrator records the CI run. |
| 2. Search without per-needle copies or folding | Cases 3 and 4; M5 | Met. |
| 3. Mirror the replaced Windows status mapping; test a pending deletion | Cases 5 and 6; M2, M3, M4 | Met. |
| 4. Keep every FP-0066 and FP-0076 case passing | Case 7 | Met on Windows and on WSL Ubuntu. |

## Records

Every log ends each command with a `RESULT` line.

| Log | Content and `RESULT` |
| --- | --- |
| `raw/tests-before.log` | Evidence step 1. `HEAD` `b8313e6`, `git worktree add --detach out/fp0106-before b8313e6`, the `node -e` staging command that copies the final `src/lab_identity_test.zig`, `src/root.zig`, `build.zig`, and `tests/lab/check.zig` and appends `out/fp0106/case-3-block.zig` (the case 3 test and its `functionSource` helper) to the base `tools/zig/library_check.zig`, `git add`, the status, and the staged blobs `9d87326` (`build.zig`), `fa0fef1` (`src/lab_identity_test.zig`), `d783605` (`src/root.zig`), `8daf326` (`tests/lab/check.zig`), and `9e32964` (`tools/zig/library_check.zig`), then `ver`. `zig build test --summary all --cache-dir out/fp0106-before` in that tree: `exit_code` 1, 98 of 104 steps and 394 of 397 tests, with no compile error. Case 3 fails at `try testing.expect(!takes_allocator)`. Case 5 fails with `the detail is not "output file: FileBusy"` and `the laboratory ran for 55 ms, less than 4000 ms`, and the laboratory reports `output file: Unexpected` after `error.Unexpected NTSTATUS=0xc0000056 (DELETE_PENDING)` at `src/lab_main.zig:212`. Both case 6 tests fail through their guards with `WindowsIdentityStepMissing` and `WindowsIdentityBackoffMsMissing`. |
| `raw/c-abi-before-R.log` | Evidence step 2. `git worktree add --detach out/fp0106-base-r b8313e6`, the copy of `out/fp0106/mutation/c_api-R.zig` over `src/c_api.zig`, `HEAD` `b8313e6`, `git hash-object` of `src/c_api.zig` (`72642bd`, R) and `tools/lib.mjs` (`7a2bd74`, base), the junction, and `node tools/fairpane.mjs run c-abi --evidence-dir out/evidence/fp0106-before`: `exit_code` 0 and gate status `pass`. The copied receipt and log are under `raw/gates-before-R/`. |
| `raw/c-abi-after.log` | Evidence step 3. `HEAD`, status, `git hash-object` of `src/c_api.zig` (`0f0c3cb`) and `tools/lib.mjs` (`0c1ff89`), the junction, and the gate: `exit_code` 0 and status `pass`. The copied receipt and log are under `raw/gates-after/`. |
| `raw/c-abi-after-R.log` | Evidence step 3. `src/c_api.zig` hashes to `0f0c3cb` before, `72642bd` during, and `0f0c3cb` after. The gate exits 1 with status `fail`, as case 2 requires. The copied receipt and log are under `raw/gates-after-R/`. |
| `raw/mutation.log` | Evidence step 4. The copies, the five diffs, their hashes, and the runs of M2 to M5. See "Mutation controls". |
| `raw/tests-after.log` | Evidence step 5. `HEAD` `b8313e6`, the status, the blobs of the ten changed files, the removal of `out/fp0106-after` with `out/fp0106-after exists: false`, and `ver`. `zig build test --summary all --cache-dir out/fp0106-after`: `exit_code` 0, 104 of 104 steps and 397 of 397 tests, in 75682 ms. |
| `raw/tests-after-linux.log` | Evidence step 6. The same `HEAD`, the staged blobs in the temporary index `out/fp0106/after-linux.index`, the tree `588ad47`, `git archive`, and a WSL copy whose tree is `588ad47`, with `uname`, `os-release`, and uid 1000. `zig build test --summary all --cache-dir .zig-cache-after`, which the command checks is absent first: `exit_code` 0, 103 of 103 steps and 397 of 397 tests. Case 6 compiles and passes on Linux. |
| `raw/wsl-environment.log` | `exit_code` 0. Ubuntu 24.04.5 LTS, uid 1000, Zig `0.18.0-dev.120+9fe22a29b`, and Git 2.43.0. |
| `raw/repo-check.log` | `node tools/fairpane.mjs check` on the final tree: `exit_code` 0. |
| `raw/fmt.log` | Evidence step 7. `zig fmt --check build.zig src tests tools/zig` and then the contract's `zig fmt --check build.zig src tests`: `exit_code` 0 for both. |
| `raw/controller-tests-after.log` | Evidence step 7. `node --version` v26.7.0 and `node tools/fairpane.mjs test`: `exit_code` 0, 248 of 248 controller tests. The `.tools` junction was removed first, because FP-0079 case 9 rejects a symlinked `.tools`. |
| `raw/case-5-duration.log` | A direct run of the built helper on a fresh directory: `the laboratory reported output file: FileBusy after 4257 ms`, `exit_code` 0, and `check entries case.json` then exits 0. |
| `raw/case-5-duration-attempt-1.log` | The first direct run, which passed relative paths. The helper runs the laboratory with the case directory as its working directory, so the relative laboratory path did not resolve: `FileNotFound` from `std.process.run`, `exit_code` 1. The worker renamed the log by hand; the rename is not a recorded command. |
| `raw/cleanup.log` | `rmdir` of the base tree's junction, `git worktree remove --force` of both staged trees, `git worktree prune`, and `rmdir` of the working tree's junction: `exit_code` 0 each. |
| `raw/development.log` | Development runs. The first entry failed with `exit_code` null, because the shell stripped the backslashes from the compiler path, and it is kept as a record. The later `zig fmt --check` and `zig build test --summary all --cache-dir out/fp0106-dev` each exit 0, the latter with 104 of 104 steps and 397 of 397 tests. |

## Mutation controls

Each control saves the source under `out/fp0106/mutation/`, writes a mutated copy there, records the diff with `git diff --no-index --output`, copies the mutated file over the source, runs the suite, copies the saved source back, and records the hash before, during, and after.
`git diff --no-index` exits with status 1 because the files differ.
Each Windows run used `zig build test --summary all --cache-dir out/fp0106-mutation`.

| Control | Diff | Hashes before, during, after | Result |
| --- | --- | --- | --- |
| R | `raw/mutation-R.diff` | `0f0c3cb`, `72642bd`, `0f0c3cb` | `fp_abi_revision` loses `export`, and a `comptime` block exports it with `@export` only when `builtin.mode == .debug`. The base gate passes, and the after gate fails on the ReleaseSafe `abi-exports` with `"missing": ["fp_abi_revision"]`. See case 2. |
| M2 | `raw/mutation-M2.diff` | `e37e93e`, `d213e61`, `e37e93e` | `exit_code` 1, 100 of 104 steps. Case 6 fails with `expected .retry_after_backoff, found .fail` and `the step for DELETE_PENDING differs`. Case 5 fails with `the laboratory ran for 22 ms, less than 4000 ms`; its detail is `output file: FileBusy`. No other step fails. |
| M3 | `raw/mutation-M3.diff` | `e37e93e`, `9067fa0`, `e37e93e` | `exit_code` 1, 100 of 104 steps. Case 6 fails with `expected 2048, found null` and `the wait before backoff 12 differs`. Case 5 also fails with `the laboratory ran for 2237 ms, less than 4000 ms`, because 12 waits total 2047 ms. |
| M4 | `raw/mutation-M4.diff` | `e37e93e`, `225277d`, `e37e93e` | `exit_code` 1, 102 of 104 steps. Case 6 fails with `expected .fail, found .unexpected` and `the step for VIRUS_DELETED differs`. No other step fails. |
| M5 | `raw/mutation-M5.diff` | `ce6da85`, `4f6fb1e`, `ce6da85` | `exit_code` 1, 100 of 104 steps. Case 4 fails and names `find("debug info: C:\Src\Fairpane\SRC\root.zig", "C:\src\FAIRPANE") is null, not 12`, together with the searches for `c:/src/fairpane/src`, `q` in `Q`, and `A/B\c`. FP-0066 case 4 also fails with `does not name`, because the `names` command calls the same `find` and the mutation no longer folds the uppercase letters and backslashes of the library's spelling of `src`. |

M2 adds `FileBusy` to `WindowsIdentityError` in the mutated copy, so that `DELETE_PENDING` can fail at once with `FileBusy` and the mutated tree compiles.
M3 sets the backoff count to 12, and M4 removes `VIRUS_DELETED` from the `AntivirusInterference` arm, so it reaches `else => .unexpected`.
The M3 and M4 runs report 390 tests in total instead of 397, because the build reused the cached results of the unchanged `library-test` test binary.

## Durations

| Measurement | Value | Source |
| --- | --- | --- |
| ReleaseSafe `zig build` in the `c-abi` gate | 4688 ms, and 4055 ms with R | `raw/gates-after/…c7d92f07.log`, `raw/gates-after-R/…b493555c.log` |
| ReleaseSafe `abi-exports` in the `c-abi` gate | 162 ms, and 93 ms with R | the same logs |
| Time added to the `c-abi` gate | About 4.9 s, under the 120 s bound of decision 8 | the two commands above |
| Whole `c-abi` gate on the after tree | 102953 ms, of which 81778 ms is the Debug `zig build` with a new work-tree global cache | `raw/c-abi-after.log`, `raw/gates-after/…c7d92f07.log` |
| Case 5, laboratory wall time | 4257 ms | `raw/case-5-duration.log` |
| Case 5, build step | 4 s | `raw/tests-after.log` |
| Time added to the Windows `zig-test` run | About 4.3 s for case 5; cases 3, 4, and 6 are unit tests | the rows above, under the 10 s bound of decision 8 |

No stop rule fired: the ReleaseSafe build took less than 300 s, case 5 took less than 15 s, case 5's precondition held on every run, case 6 compiled for Linux, and R removed `fp_abi_revision` from the ReleaseSafe library alone.

## Resolved ambiguities

- The contract's case 4 lists its searches in order, and the first search, `c:/src/fairpane/src`, also fails under M5.
  The test therefore runs every search and prints each mismatch before it fails, so the M5 failure names `C:\src\FAIRPANE` as the contract's control table requires.
- `reportAbsent` returns `u8`, so it cannot propagate `error.EmptyNeedle`.
  It prints `cannot search <library> for an empty needle` and returns the usage status 2.
- Case 3 takes each slice with a test helper, `functionSource`, which ends the slice after the first line that is exactly `}`, ignoring a trailing carriage return.
- The case 5 helper opens `out.json` with `DELETE` and `SYNCHRONIZE` access, every share mode, and `FILE_NON_DIRECTORY_FILE`, and sets the disposition through `SetFileInformationByHandle` with the class `FileDispositionInfo` (4) and a `FILE_DISPOSITION_INFO` whose `DeleteFile` is true.
  Its precondition open uses `FILE_READ_ATTRIBUTES` and `SYNCHRONIZE`, the same access as the laboratory's open, because synchronous I/O needs `SYNCHRONIZE`.
- The case 5 helper runs the laboratory with `<directory>` as its working directory, so `build.zig` passes absolute paths for both arguments.
- The contract's last case 5 bullet runs as a separate build step, `check entries case.json` in the case directory, after the helper has closed its handle, as FP-0076 case 4 checks its directory.
- Case 6 is two tests, one for the status table and one for the backoff, each with its own `@hasDecl` guard.
- The staged base tree used the final `build.zig`, which also carries the comment changes at lines 378 and 442.
  Those comments change no behavior.
- `abi-exports` prints `"missing"` as a JSON array over three lines; the content is `["fp_abi_revision"]`.
- `tests/lab/README.md` is not in the contract's file table, but `tests` is writable and the file documents the helper's duties.
- The working tree also held the untracked directory `engineering/evidence/ci/dispatch-57df855/`, which this task did not create and does not include.
- `RESULT` lines record each command's working directory and resolved executable, and the controller suite prints temporary paths under the user profile, as earlier evidence does.
  No recorded command lists the contents of a home directory or a user profile.

## Integrator steps

The integrator records `HEAD` and a status that includes ignored files before and after it runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and `c-abi` with `--evidence-dir engineering/evidence/FP-0106/gates`.
After the push, the integrator records `gh run view` of the first `Gates` run that contains the change and the Windows `c-abi` receipt and log under `engineering/evidence/FP-0106/ci/`, and reports the duration of the ReleaseSafe `zig build` command here.
