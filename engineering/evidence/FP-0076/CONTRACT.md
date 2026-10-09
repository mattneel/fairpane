# FP-0076 task contract

## Identity

Task ID: `FP-0076`, "Close the FP-0054 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0054`, accepted.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0054/reviews/review-2-accept.json`.

### Integrator decisions

- The development host has WSL Ubuntu with a non-root user, uid 1000, so the POSIX cases run there with the locked `x86_64-linux` compiler.
  `engineering/evidence/FP-0067/raw/linux-baseline.log` shows the procedure: the archive's SHA-256 is checked against `toolchains/zig.lock.json` before extraction, and the whole suite passes at `8d945fe`.
- A case that needs a POSIX host is added to the build only when the host's operating system is not Windows, and a case that needs Windows is added only on Windows.
  The evidence names the host of every run, so no case counts as run on a host where it was not added.
- `FP-0067` adds the Zig gates to the Linux CI job; this task does not depend on it.

## Sources

- `src/lab_main.zig:145-218`: `refuseInputAsOutput` and `fileIdentity`, which opens both files for reading before it identifies them.
- `build.zig`: FP-0054 case 5 at the `WriteFiles` copy, and `addRevision1Cases` with revision 1 case 5's removal step.
- `tests/lab/check.zig` and its `fresh`, `same`, `absent`, and `remove` commands.
- `src/lab.zig:131-138`: `fileFailure`, which renders an error that it does not name by its error name.
- Linux `statx(2)`, POSIX `stat(2)` and `mkfifo(3)`, and Windows `NtCreateFile` with `FILE_READ_ATTRIBUTES`.

## Behavior

### Identity without reading

`fileIdentity` identifies a file without opening it for reading, following symbolic links.

- On Linux, it calls `statx` on the path with `AT_FDCWD` and no `AT_SYMLINK_NOFOLLOW`, and it reads `stx_dev_major`, `stx_dev_minor`, and `stx_ino`.
- On other POSIX systems, it calls `stat` or `fstatat` on the path and reads `st_dev` and `st_ino`.
- On Windows, it opens a handle whose only data access is `FILE_READ_ATTRIBUTES`, with every share mode, and it reads `FILE_ID_INFORMATION` as before.

A missing output path is still not the input file.
Any other failure to identify a file is still a harness error that names that file's subject, with exit status 3, and the refused or failed command writes nothing.
The guard's equal-spelling check stays first.

### Build cases

FP-0054 case 5 runs in a directory that `check fresh` creates for each run, instead of the cached `WriteFiles` copy.
Revision 1 case 5 of FP-0054 runs inside one helper invocation: the helper creates both oversized files, runs `run`, `minimize`, and `replay` as child processes, checks each exit status and detail, removes both files, and only then reports its result.
A failing check therefore never leaves an oversized file behind.

## Exact test cases

Each case works in a directory that `check fresh` creates for its run, with `case.json` copied from `tests/lab/case-03-body-mismatch.json`.

1. POSIX hosts: with `transcript.json` created as a FIFO, a helper starts `fairpane-lab run case.json --transcript transcript.json`, reads the FIFO until end of file, and waits at most 30 seconds.
   The laboratory exits with status 1, its result is `fail`, and the bytes read parse as a version 2 transcript whose `action_count` equals its number of actions.
   On timeout, the helper kills the laboratory and fails with `the laboratory did not finish within 30 seconds`.
2. POSIX hosts, run as a non-root user: with `out.json` an existing file of mode `0200`, `fairpane-lab minimize case.json --out out.json` exits with status 0 and result `pass`, and `out.json` becomes a version 2 case.
   When the effective user is root, the helper fails with `case 2 needs a non-root user`.
3. Windows hosts: with `out.json` an existing file whose ACL denies read-data access to Everyone, `fairpane-lab minimize case.json --out out.json` exits with status 0 and result `pass`.
   After the helper removes the denial, `out.json` is a version 2 case.
4. Every host: an output path that cannot be identified makes `fairpane-lab minimize` exit with status 3 and result `harness-error`, with a detail that starts with `output file: `, and the directory gains no file.
   On POSIX hosts the path is `case.json/out.json`; on Windows it is `out|.json`.
   The case asserts the exact detail for each host, which a recorded probe establishes before the case is frozen in the build.
5. POSIX hosts: with `link.json` a symbolic link to `case.json`, `fairpane-lab minimize case.json --out link.json` exits with status 3 and the detail `command line: the output path names the input file`, and `case.json` still equals the fixture.
6. Every host: FP-0054 case 5 and its unchanged-input check pass in a fresh directory.
7. Every host: the revision 1 case 5 helper reports every check, and no oversized file remains in its directory after a run in which a check fails.

Cases 1 to 3 must fail before the change, each on the hosts where it is added; amendment 1 exempts case 4.
Case 5 passes before the change, so a mutation control that identifies the output without following symbolic links must fail it.
Case 7 needs a mutation control: change the `run` command's case-file subject to `transcript file`, and record a directory listing after the failed build that shows no oversized file.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0076/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base for Windows, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `tests-before-linux.log`: the same red baseline on WSL Ubuntu, recorded through `wsl.exe`, from a copy of the staged tree.
3. `probe.log`: the exact case 4 detail on each host.
4. `mutation.log` and its diffs for both mutation controls, with the hash of each changed file before, during, and after.
5. An uncached `tests-after.log` on Windows and `tests-after-linux.log` on WSL Ubuntu, each with `zig build test --summary all`, the host's operating system, and exit status 0.
6. `controller-tests-after.log` with `node tools/fairpane.mjs test`, and `fmt.log` with `zig fmt --check build.zig src tests`.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`.
The integrator also reruns `zig build test --summary all` on WSL Ubuntu at the integration commit and records it.

## Authority

Writable paths: `src`, `tests`, `build.zig`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No change to the laboratory's case, transcript, or result formats.
- No change to the guard's decisions apart from identification without reading.
- No macOS or other non-Linux POSIX run; those targets compile in the cross-build gates only.

## Amendments

1. Worker `FP0076Guard` showed that case 4 cannot fail before the change.
   `probe.log` records that the base laboratory already reports `output file: BadPathName` on Windows and `output file: NotDir` on WSL Ubuntu, with exit status 3 and no new file.
   The base `fileIdentity` fails with the same error names when it opens these paths for reading.
   Criterion 2 asks for a test of this detail, not a change to it, so case 4 is exempt from the rule that it fail before the change.
   Case 4 instead needs a mutation control: the guard reports an output path that it cannot identify with the input's subject, `case file`.
   Case 4 must fail under that control on Windows and on WSL Ubuntu.
   A guard that treated such a failure as a missing file would still pass case 4, because the write that follows fails with the same detail.
   No case can distinguish the two while the write fails for the same reason, so this contract asks for no such control.
