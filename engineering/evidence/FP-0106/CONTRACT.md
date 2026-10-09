# FP-0106 task contract

## Identity

Task ID: `FP-0106`, "Close the FP-0066 and FP-0076 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract, at least `b9217fe`. Every line number below was re-read at `b9217fe`, and every standard-library line in the pinned compiler `0.18.0-dev.120+9fe22a29b`.
Prerequisites: `FP-0066` and `FP-0076`, both accepted (`engineering/state.json:837` and `:907`).
A contract worker drafted this contract, an independent pre-freeze check reviewed it, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0066/reviews/review-1-accept.json`, the minor findings at `build.zig:269` and `tools/zig/library_check.zig:127` (review-time lines), and `engineering/evidence/FP-0076/reviews/review-1-accept.json`, the minor finding at `src/lab_main.zig:206` (review-time line).

### Integrator decisions

0. Agent CheckFindings checked the draft twice: its first check (fix-first, minors only) led to this revision, and its re-check returned freeze with no finding.
1. Criterion 1 runs in the `c-abi` gate, which the plan entry already requires.
   After its Debug checks, the gate builds `zig build -Doptimize=ReleaseSafe --prefix <root>/out/c-abi-release` into a directory that it first removes, and it runs `node tools/fairpane.mjs abi-exports` on the one static library there.
   `reproduce-check` stays unchanged, because no gate runs it.
2. `find` in `tools/zig/library_check.zig` compares folded bytes on the fly. It takes no allocator, allocates nothing, and copies nothing. `reportAbsent` takes no allocator.
   This reads "case-folding the whole library" as producing a folded copy, as FP-0066 review 1's recommendation "compare folded bytes on the fly without allocating" does.
3. The identification open mirrors every arm of the pinned `dirOpenFileWtf16` switch, not only the six statuses that the criterion names.
   The mapping is a pure function in `src/lab.zig`, so a table test runs on every host. `fileIdentity` applies it.
4. `refuseInputAsOutput` and `fileIdentity` take `io: Io`. Both callers already hold it: `runCommand` (`src/lab_main.zig:89`, call at `:92`) and `minimizeCommand` (`src/lab_main.zig:122`, call at `:124`).
   For `retry`, `fileIdentity` runs `try io.checkCancel()` and opens again, as the pinned `CANCELLED` arm runs `try syscall.checkCancel(); continue;`. The retry is unbounded while no cancelation is pending, and a pending cancelation returns `error.Canceled`.
   For `retry_after_backoff`, it waits with `try io.sleep(.fromMilliseconds(ms), .awake)`, as the pinned arms wait with `parking_sleep.sleep` on the `awake` clock.
5. `INVALID_PARAMETER`, `OBJECT_PATH_SYNTAX_BAD`, and `INVALID_HANDLE` go to `windows.statusBug`, as the pinned arms do through `syscall.ntstatusBug` (`Io/Threaded.zig:1453-1456`). `statusBug` panics in Debug builds and returns `error.Unexpected` otherwise (`os/windows.zig:4001-4009`).
6. The Windows case for a file pending deletion holds the deletion for the whole laboratory run. The laboratory then reports `output file: FileBusy` after 13 waits that total 4095 ms.
   No probe is recorded before the freeze, because case 5 checks its own precondition in every run.
7. New Zig tests that refer to new declarations guard them with `if (comptime @hasDecl(...)) { ... } else return error.<Name>Missing;`, so the base compiles and each test fails alone.
8. The task adds at most 10 seconds to the Windows `zig-test` run and at most 120 seconds to the `c-abi` gate on the development host.

### Observed facts that shaped the decisions

- `tools/lib.mjs:748-756`: the `c-abi` gate builds Debug into `out/c-abi-build`, runs `abi-exports` on that library, and links the C smoke test. No gate checks a ReleaseSafe library.
- `build.zig:378` says that FP-0066 case 3 "runs through the controller", and `tools/README.md:242` and `:291` say the same.
- `engineering/evidence/FP-0066/raw/release-libraries.log:3` records a 6400 ms ReleaseSafe `zig build` on the development host, and line 12 records a 53 ms `abi-exports`.
- `api/fairpane.schema.json` declares 15 functions, and `src/c_api.zig:175` exports `fp_abi_revision`.
- `tools/zig/library_check.zig:127-136`: `find` allocates a folded copy of the needle and of the whole haystack for each call. `reportAbsent` (`:110-119`) calls it once per needle, and FP-0066 case 2 passes 6 needles (`build.zig:406-416`). The `names` command calls `find` at `:56`.
- `tools/zig/library_check.zig:322-328` holds the test `FP-0066: a search ignores letter case and the path separator`.
- `src/lab_main.zig:178-268` (`fileIdentity`): the Windows open maps 9 statuses and sends every other status to `windows.unexpectedStatus` (`:212`). The `NtQueryInformationFile` switch at `:217-220` is unrelated to this task.
- The pinned `lib/std/Io/Threaded.zig`: `dirOpenFileWtf16` starts at `:5126`, and its open loop's status arms run from `:5167` to `:5224`, inside the switch that ends at `:5225`.
  - `:5177`, `:5201`, and `:5206` send `INVALID_PARAMETER`, `OBJECT_PATH_SYNTAX_BAD`, and `INVALID_HANDLE` to `syscall.ntstatusBug`.
  - `:5178-5181` is the `CANCELLED` arm, `try syscall.checkCancel(); continue;`.
  - `:5182-5197` (`SHARING_VIOLATION`) and `:5207-5222` (`DELETE_PENDING`) share one attempt counter. Each returns `error.FileBusy` when `max_windows_kernel_bug_retries - attempt == 0` (`:5189` and `:5214`), and otherwise sleeps `(1 << attempt) >> 1` ms on the `awake` clock and retries.
  - `:5223` maps `VIRUS_INFECTED` and `VIRUS_DELETED` to `AntivirusInterference`, and `:5224` sends every other status to `syscall.unexpectedNtstatus`.
  - `:1571` sets `max_windows_kernel_bug_retries = 13`.
- The pinned `lib/std/Io.zig:1485` defines `checkCancel(io)`, `:1101` defines `Duration.fromMilliseconds`, and `:2597` defines `sleep(io, duration, clock)`.
- `src/lab.zig:131-139` (`fileFailure`) renders an unnamed error by its error name, so the detail is `output file: FileBusy`.
- `src/root.zig:20-40` holds the root test block, which imports `lab.zig`.
- `tests/lab/check.zig` already declares Win32 functions itself (`:217-266`) and spawns the laboratory as a child in the FIFO helper (`:324-383`).
- `build.zig:623` defines `windows_host`, and `build.zig:636` adds FP-0076 case 3 only on Windows hosts, as the FP-0076 decision requires.
- The pinned `std/os/windows/ntstatus.zig` defines `INVALID_DEVICE_REQUEST` (`:463`), `DELETE_PENDING` (`:603`), `DISK_FULL` (`:694`), `PIPE_NOT_AVAILABLE` (`:787`), `CANCELLED` (`:1015`), `USER_MAPPED_FILE` (`:1433`), and `VIRUS_DELETED` (`:2183`).

## Sources

- `engineering/plan.json`, entry `FP-0106` (`:3756-3775`), criteria 1 to 4.
- `engineering/evidence/FP-0066/CONTRACT.md` and `engineering/evidence/FP-0076/CONTRACT.md`, with every case.
- The pinned standard library under `.tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-windows/lib/std/`: `Io/Threaded.zig:1453-1456`, `:1571`, and `:5126-5226`; `Io.zig:1101`, `:1485`, and `:2597`; `os/windows.zig:3990-4009`; and `os/windows/ntstatus.zig`.
- Repository files: `tools/lib.mjs`, `tools/README.md`, `tools/zig/library_check.zig`, `build.zig`, `src/lab_main.zig`, `src/lab.zig`, `src/root.zig`, `src/c_api.zig`, `tests/lab/check.zig`, and `api/fairpane.schema.json`.
- [INFERENCE] Windows keeps the name of a file whose delete disposition was set through the non-Ex `FileDispositionInfo` class, which has no POSIX-semantics flag, until its last handle closes, and an open of that name returns `STATUS_DELETE_PENDING`. The pinned `DELETE_PENDING` comment (`Io/Threaded.zig:5208-5212`) describes the same state. Case 5 checks this precondition before it runs the laboratory.

## Behavior

### Files

| File | Change |
| --- | --- |
| `tools/lib.mjs` | The ReleaseSafe build and `abi-exports` in the `c-abi` gate |
| `tools/README.md` | Lines 242 and 291 |
| `tools/zig/library_check.zig` | Allocation-free `find`, `reportAbsent` without an allocator, and cases 3 and 4 |
| `build.zig` | The comment at line 378 and case 5 |
| `src/lab.zig` | `WindowsIdentityError`, `WindowsIdentityStep`, `windowsIdentityStep`, and `windowsIdentityBackoffMs` |
| `src/lab_main.zig` | `refuseInputAsOutput` and `fileIdentity` take `io`, and `fileIdentity` applies the mapping |
| `src/lab_identity_test.zig` and `src/root.zig` | Case 6 and its import |
| `tests/lab/check.zig` | The `delete-pending` helper |

### ReleaseSafe exports

After the Debug smoke test, the `c-abi` gate removes `<root>/out/c-abi-release`, runs `zig build -Doptimize=ReleaseSafe --prefix <root>/out/c-abi-release` with the locked compiler, finds exactly one of `fairpane.lib`, `libfairpane.a`, and `fairpane.a` under its `lib` directory, and runs `node tools/fairpane.mjs abi-exports <that path>`.
Each is a recorded gate command, so a failure fails the gate and names the command.
`tools/README.md:242` says that the gate runs `abi-exports` on the Debug library and on a ReleaseSafe library, and `tools/README.md:291` and `build.zig:378` say that FP-0066 case 3 runs in the `c-abi` gate.

### Library search

```zig
fn find(haystack: []const u8, needle: []const u8) error{EmptyNeedle}!?usize;
fn reportAbsent(path: []const u8, bytes: []const u8, needles: []const []const u8) u8;
```

`find` returns the offset of the first position where `fold(haystack[i + j]) == fold(needle[j])` for every `j`, or `null`. It reads the bytes through `fold` and stores no folded copy.
The worker may use a skip table indexed by folded bytes.
The `names` command calls the same `find`.

### Windows identification statuses

`src/lab.zig` declares:

```zig
pub const WindowsIdentityError = error{ BadPathName, FileNotFound, NetworkNotFound, NoDevice, AccessDenied, PipeBusy, PathAlreadyExists, IsDir, NotDir, AntivirusInterference };
pub const WindowsIdentityStep = union(enum) { opened, retry, retry_after_backoff, fail: WindowsIdentityError, bug, unexpected };
pub fn windowsIdentityStep(status: std.os.windows.NTSTATUS) WindowsIdentityStep;
/// The wait in milliseconds before backoff `attempt`, or null when the open fails with `FileBusy`.
pub fn windowsIdentityBackoffMs(attempt: u5) ?u32;
```

`fileIdentity(io, path)` keeps one attempt counter that starts at 0. For each status of its `NtCreateFile` call:

- `opened` continues to `NtQueryInformationFile`, whose switch is unchanged.
- `retry` runs `try io.checkCancel()` and opens again.
- `retry_after_backoff` returns `error.FileBusy` when `windowsIdentityBackoffMs(attempt)` is null. Otherwise it runs `try io.sleep(.fromMilliseconds(ms), .awake)`, adds 1 to the counter, and opens again.
- `fail` returns its error.
- `bug` returns `windows.statusBug(status)`.
- `unexpected` returns `windows.unexpectedStatus(status)`.

`refuseInputAsOutput(io, input, output)` passes `io` to both identifications. Its order of checks is unchanged.

## Exact test cases

Zig cases are named `FP-0106 case N: ...` and run through `zig build test`. Cases 1 and 2 are gate runs.

1. On the after tree, `node tools/fairpane.mjs run c-abi` passes. Its log shows the ReleaseSafe build with exit 0 and `abi-exports` on `out/c-abi-release/lib/<library>` with `"result": "pass"` and `"exports": 15`.
2. Mutation R makes `src/c_api.zig` export `fp_abi_revision` only when `builtin.mode` is Debug, for example through a `comptime` block with a conditional `@export` [INFERENCE: the pinned `@export` syntax].
   - On the base with R, the `c-abi` gate passes. That run shows the gap.
   - On the after tree with R, the gate fails. Its receipt `error` names the `abi-exports` command on `out/c-abi-release/lib/<library>`, the log shows `"missing": ["fp_abi_revision"]` for that command, and the Debug `abi-exports` command before it exits with status 0.
3. `tools/zig/library_check.zig`, placed after both functions:
   - The test computes `const takes_allocator = comptime blk: { ... }` over the parameters of `@typeInfo(@TypeOf(find)).@"fn"` and `@typeInfo(@TypeOf(reportAbsent)).@"fn"`, true when any parameter type is `std.mem.Allocator`, and asserts `try testing.expect(!takes_allocator)` at run time.
   - It reads `@embedFile("library_check.zig")` and takes two slices: one from the first `fn find(` and one from the first `fn reportAbsent(`, each to the next line that is exactly `}`.
   - It asserts that neither slice contains `alloc`, `Allocator`, `heap`, or `dupe`. The searched words occur only in the test block, outside both slices.
4. `tools/zig/library_check.zig`, the existing search test, amended to the new signature and renamed `FP-0066 (amended by FP-0106 case 4): ...`. Let `library` be the bytes `debug info: C:\Src\Fairpane\SRC\root.zig`.
   - `find(library, "c:/src/fairpane/src")` is 12.
   - `find(library, "C:\src\FAIRPANE")` (the bytes, with one backslash) is 12.
   - `find(library, "c:/src/fairpane/lib")` is `null`.
   - `find(library, "")` returns `error.EmptyNeedle`.
   - `find(library, "ROOT.ZIG")` is 32. Derivation: `debug info: ` is 12 bytes, so `C` is at 12, `\Src\` spans 14 to 18, `Fairpane` spans 19 to 26, `\SRC\` spans 27 to 31, and `root.zig` starts at 32.
   - `find("abcabd", "abd")` is 3, `find("aaab", "aab")` is 1, `find("ab", "b")` is 1, `find("xyz", "xyzw")` is `null`, `find("Q", "q")` is 0, and `find("a\b/C", "A/B\c")` (bytes with one backslash each) is 0.
5. Windows hosts only, `build.zig` with a new `tests/lab/check.zig` command `delete-pending <lab> <dir>`, in a directory that `check fresh` creates with `case.json` copied from `tests/lab/case-03-body-mismatch.json`:
   - The helper creates `out.json` with 2 bytes, opens it with `DELETE` and `SYNCHRONIZE` access and every share mode, and sets `FileDispositionInfo` with `DeleteFile` true.
   - It confirms that an `NtCreateFile` of `out.json` with `FILE_READ_ATTRIBUTES` access and every share mode returns `STATUS_DELETE_PENDING`. Otherwise it fails with `out.json is not pending deletion: <status>`.
   - It runs `fairpane-lab minimize case.json --out out.json` as a child while it holds the handle, and measures the child's wall time.
   - The laboratory exits with status 3. Its result is `harness-error`, its detail is exactly `output file: FileBusy`, and its wall time is at least 4000 ms.
   - After the helper closes its handle, the directory holds only `case.json`.
6. `src/lab_identity_test.zig`, every host:
   - `windowsIdentityStep` gives these steps, each from `Io/Threaded.zig:5167-5224`:

| Status | Step |
| --- | --- |
| `SUCCESS` | `opened` |
| `OBJECT_NAME_INVALID` | `fail` `BadPathName` |
| `OBJECT_NAME_NOT_FOUND`, `OBJECT_PATH_NOT_FOUND` | `fail` `FileNotFound` |
| `BAD_NETWORK_PATH`, `BAD_NETWORK_NAME` | `fail` `NetworkNotFound` |
| `NO_MEDIA_IN_DEVICE`, `PIPE_NOT_AVAILABLE` | `fail` `NoDevice` |
| `INVALID_PARAMETER`, `OBJECT_PATH_SYNTAX_BAD`, `INVALID_HANDLE` | `bug` |
| `CANCELLED` | `retry` |
| `SHARING_VIOLATION`, `DELETE_PENDING` | `retry_after_backoff` |
| `ACCESS_DENIED`, `USER_MAPPED_FILE` | `fail` `AccessDenied` |
| `PIPE_BUSY` | `fail` `PipeBusy` |
| `OBJECT_NAME_COLLISION` | `fail` `PathAlreadyExists` |
| `FILE_IS_A_DIRECTORY` | `fail` `IsDir` |
| `NOT_A_DIRECTORY` | `fail` `NotDir` |
| `VIRUS_INFECTED`, `VIRUS_DELETED` | `fail` `AntivirusInterference` |
| `INVALID_DEVICE_REQUEST`, `DISK_FULL` | `unexpected` |

   - `windowsIdentityBackoffMs` gives 0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, and 2048 for attempts 0 to 12, and `null` for attempt 13. The waits sum to 4095 ms.
7. Every FP-0066 and FP-0076 case passes: the `library-test` steps and the FP-0076 steps of `zig build test --summary all` on Windows and on WSL Ubuntu, and FP-0066 case 3 through case 1.

### Base failures

- Case 2 passes on the base with R, because `tools/lib.mjs:748-756` checks only the Debug library. That run is the before record.
- Case 3 fails at run time, because `find` (`tools/zig/library_check.zig:127`) and `reportAbsent` (`:110`) take an allocator, and `find`'s body calls `gpa.alloc` (`:129`). The base compiles, because both checks run at run time.
- Case 5 fails, because `src/lab_main.zig:212` sends `DELETE_PENDING` to `windows.unexpectedStatus`, so the detail is `output file: Unexpected`.
- Case 6 fails through its `@hasDecl` guard, because `src/lab.zig` has no `windowsIdentityStep`.
- Case 4 is a regression guard. Its base form at `tools/zig/library_check.zig:322-328` passes on the base, and M5 controls the new form.

### Mutation controls

| Control | Mutation | Case that fails |
| --- | --- | --- |
| R | `fp_abi_revision` exported only in Debug builds | Case 2, after tree |
| M2 | `DELETE_PENDING` fails at once with `FileBusy` | Case 6, and case 5 on the 4000 ms bound |
| M3 | The backoff allows 12 waits | Case 6, attempt 12 |
| M4 | `VIRUS_DELETED` maps to `unexpected` | Case 6 |
| M5 | `find` compares the raw haystack byte with the folded needle byte | Case 4, `C:\src\FAIRPANE` |

Record each control as a `.diff` with the file hashes before, during, and after.

### Stop rules

- If case 5's precondition fails on the development host, stop and report the status. Never weaken the case.
- If `src/lab_identity_test.zig` cannot compile for a non-Windows host, stop and report. Never skip the case.
- If R cannot remove `fp_abi_revision` from the ReleaseSafe library alone, stop and report.
- If the ReleaseSafe build in the `c-abi` gate takes more than 300 s, or case 5 takes more than 15 s, on the development host, stop and report both durations.
- If an expectation here contradicts the pinned standard library, stop and report it.

### Criterion mapping

| FP-0106 criterion | Cases and evidence |
| --- | --- |
| 1. Check ReleaseSafe exports in a gate | Cases 1 and 2; R; the CI record |
| 2. Search without per-needle copies or folding | Cases 3 and 4; M5 |
| 3. Mirror the replaced Windows status mapping; test a pending deletion | Cases 5 and 6; M2, M3, M4 |
| 4. Keep every FP-0066 and FP-0076 case passing | Case 7 |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0106/raw/`.
Use `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler. Never overwrite a log, and name a failed attempt's log `-attempt-N`.

1. `tests-before.log`: in a base worktree with `src/lab_identity_test.zig`, its `src/root.zig` import, the case 3 test block, the case 5 build step, and the `delete-pending` helper staged, record `HEAD`, the staging command, the blob IDs, `cmd /d /c ver`, and `zig build test --summary all --cache-dir out/fp0106-before`. It must exit with status 1, with cases 3, 5, and 6 failing and no compile error.
2. `c-abi-before-R.log`: on the base with R, `node tools/fairpane.mjs run c-abi --evidence-dir out/evidence/fp0106-before`. It must pass.
3. `c-abi-after.log` and `c-abi-after-R.log`: the same on the after tree, without and with R.
4. `mutation.log` with `mutation-R.diff` and `mutation-M2.diff` to `mutation-M5.diff`.
5. `tests-after.log`: delete `out/fp0106-after`, then record `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0106-after`, which must exit with status 0.
6. `tests-after-linux.log`: on WSL Ubuntu, from a copy of the after tree, with the locked `x86_64-linux` compiler, as in FP-0076.
7. `fmt.log` with `zig fmt --check build.zig src tests`, and `controller-tests-after.log` with `node tools/fairpane.mjs test`.
8. `engineering/evidence/FP-0106/README.md`: the mapping, each control's result, the durations, and every resolved ambiguity.

The integrator records `HEAD` and a status that includes ignored files before and after it runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and `c-abi` with `--evidence-dir engineering/evidence/FP-0106/gates`.
After the push, the integrator records `gh run view` of the first `Gates` run that contains the change and the Windows `c-abi` receipt and log under `engineering/evidence/FP-0106/ci/`. The receipt must report `pass`, and the README reports the duration of the ReleaseSafe `zig build` command.

## Authority

The writable paths are `src`, `tests`, `tools`, `build.zig`, and `engineering/evidence/FP-0106/`.
These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
`api` is not writable, so `api/README.md:116` stays as it is; it remains accurate, because the gate still runs `abi-exports` on each library that it builds.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
The required reviewer is `fairpane-review`.

## Non-goals

- No change to `reproduce-check`, the gate registry, or the gate timeouts.
- No C smoke test against the ReleaseSafe library.
- No change to the laboratory's formats or to the guard's decisions apart from the status mapping.
- No test of `PIPE_BUSY`, `PIPE_NOT_AVAILABLE`, `VIRUS_*`, or `CANCELLED` through a real open; case 6 covers them.

## Resolved questions

- `INVALID_PARAMETER`, `OBJECT_PATH_SYNTAX_BAD`, and `INVALID_HANDLE` keep `statusBug`, because criterion 3 requires the mapping of the replaced open.
- `CANCELLED` runs `io.checkCancel()` and retries, exactly as the pinned arm does.
- No delete-pending probe is recorded before the freeze, because case 5 checks its precondition in every run.
