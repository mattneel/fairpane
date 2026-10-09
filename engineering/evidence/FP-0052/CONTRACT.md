# FP-0052 task contract

## Identity

Task ID: `FP-0052`, "Close the FP-0003 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0003`, accepted.
The root integrator drafted and froze this contract.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0003/reviews/review-3-accept.json` and `engineering/evidence/FP-0003/reviews/spec-review-3-accept.json`.

### Integrator decisions

- The Git corpus fetch and the file-set fetch share one write phase.
  The file-set write phase in `tools/fileset.mjs`, `commitFileSet`, already stages the record, writes it before it removes the old sources, and restores every old file on failure.
  This task moves that write phase into one function that both fetches call, keeps its behavior for file sets, and keeps its `onWriteStep(label)` test hook.
- A fetch holds a lock file, `<id>.lock` in the corpora directory, from before it touches `<id>.fetch` until after it removes `<id>.old`.
  A second fetch of the same corpus fails at once instead of sharing the staging directory.
  The lock covers Git corpora and file sets, because both share the staging and swap layout.
- The same defect as the `taskkill.exe` finding exists at `tools/lib.mjs:393`, the gate runner's watchdog, and at `tools/lib.mjs:511`, which starts `powershell.exe` by bare name with the repository as its working directory.
  On Windows, libuv searches the working directory before `PATH` for a bare name.
  This task resolves all three from the Windows system directory, and the plan criterion now says so.
- `FP-0078` changes the shared write phase for crash recovery, so it now depends on this task.
- The frozen `engineering/evidence/FP-0003/CONTRACT.md` stays unchanged, because it records what FP-0003 froze.

## Sources

- `tools/corpus.mjs:60-68`, `killTree`, and `tools/corpus.mjs:485-511`, `replaceSnapshot`.
- `tools/fileset.mjs:602-772`, `fetchFileSet` and `commitFileSet`.
- `tools/lib.mjs:386-398`, `runProcess`, and `tools/lib.mjs:504-515`, `installZig`.
- `tools/selftest.mjs:1029-1101`, the local `file://` upstream fixture and its fetch cases, and `tools/selftest.mjs:409-415`, the working-directory resolution case.
- `specs/IMPORT_REQUIREMENTS.md:62`, `:65`, and `:66`; `specs/sources.json`, entries `S37`, `S41`, and `S47`; `engineering/decisions/0003-corpus-snapshots.md:210`; `tools/corpus.mjs:263` and `:397`.
- UAX #14 revision 57, Unicode 18.0.0, <https://www.unicode.org/reports/tr14/>, rules LB10, LB15a, LB15b, LB19, LB19a, LB30, and LB30b.
  The integrator's copy of 2026-10-09 has SHA-256 `296df5332aefe695…`.
- UTS #46 revision 36, <https://www.unicode.org/reports/tr46/>, section 4.1, criteria 6 and 9.
- URL Standard, <https://url.spec.whatwg.org/>, "domain to ASCII" and "domain to Unicode", which set `CheckBidi` and `CheckJoiners` to true.
- RFC 5893, section 2, <https://www.rfc-editor.org/rfc/rfc5893>.
- WPT at `b60c4b349d9d167bf354a40bc0d4cbed15174606`: `tools/manifest/sourcefile.py`, `name_is_test262` at lines 439-442 and the `manifest_items` branch at lines 1168-1196, and `tools/manifest/test262.py`, `parse` at lines 59-75.

## Behavior

### Specification records

- The `ucd/EastAsianWidth.txt` row says that UAX #14 uses `East_Asian_Width` to resolve class AI, directly in rules LB19a and LB30, and in LB10, which gives a remaining CM or ZWJ the value `Na`.
- The `ucd/extracted/DerivedGeneralCategory.txt` row adds two consumers.
  - UAX #14 uses `General_Category` in rules LB15a and LB15b (`Pi` and `Pf`), LB19 (`Pi` and `Pf`), and LB30b (`Cn`), and LB10 gives a remaining CM or ZWJ the value `Lu`.
  - UTS #46 section 4.1 criterion 6 rejects a label that begins with `General_Category=Mark`, for URL host parsing.
- The `ucd/extracted/DerivedBidiClass.txt` row adds UTS #46 `CheckBidi`, which applies RFC 5893 section 2 to the labels of a Bidi domain name, for URL host parsing.
- Each row cites its sources.
  A new `specs/sources.json` entry `S101` describes RFC 5893, and `S41` says that the URL Standard sets both `CheckBidi` and `CheckJoiners` to true.
- The `S37` purpose names the same rules as the `EastAsianWidth.txt` row.

### WPT discovery rule

The rule text in `WPT_RULE`, the comment at `tools/corpus.mjs:263`, ADR 0003, and `S47` state the upstream condition exactly.
A `.js` file with a `test262` directory component gets the `test262` type only when no earlier rule of `manifest_items` applies to it, its name does not end in `_FIXTURE.js`, and it contains a `/*---` to `---*/` frontmatter block.
Any other such file becomes a `support` item.
`specs/applicability/wpt.json` is regenerated, and every count in it stays the same.

### Windows system executables

One function in `tools/lib.mjs` resolves a program under the Windows system directory, `<SystemRoot>\System32`, from the `SystemRoot` environment variable.
It fails with an error that names `SystemRoot` when the variable is unset, empty, or not an absolute Windows path.
The corpus watchdog and the gate runner's watchdog start `taskkill.exe` through it, and `installZig` starts `WindowsPowerShell\v1.0\powershell.exe` through it.
Each caller resolves the program before it starts its own child process, so a resolution failure starts nothing.

### Snapshot replacement

The Git corpus fetch stages its record beside `specs/snapshots/<id>.json`, swaps the snapshot directory, replaces the record, and only then removes `<id>.old`.
A failure at any write step restores the old snapshot directory and the old record, and it removes the staged record, `<id>.fetch`, and `<id>.old`.
The fetch and repin commands accept `onWriteStep` for tests only, as the file-set fetch does.

### Fetch lock

Before it removes or creates `<id>.fetch`, a fetch creates `<id>.lock` with exclusive creation and writes its process ID and start time to it.
When that file already exists, the fetch fails with an error that names the lock file, the process ID, and the start time that it holds, and it changes nothing.
The fetch removes its lock file after success and after failure.

## Exact test cases

1. Controller, every host: the resolver returns `C:\Windows\System32\taskkill.exe` for `SystemRoot` `C:\Windows`, and fails with an error that names `SystemRoot` for an unset, empty, or relative value.
2. Controller, every host: with the process working directory set to a directory that holds a program named `taskkill.exe` that exits with status 0, `runProcess` of a Node child that sleeps for 60 seconds with a 1-second timeout returns `timed_out: true` within 15 seconds.
   On Windows, that program is a copy of `<SystemRoot>\System32\whoami.exe`.
3. Controller: for each of the write steps `stage the record`, `back up the sources`, `replace the sources`, and `replace the record`, a Git corpus repin that `onWriteStep` fails at that step rejects with the injected error.
   The snapshot directory digest, the record bytes, and the listing of `specs/snapshots/` stay as they were, and the corpora directory lists only `test262`.
4. Controller: when removing `<id>.old` fails after the record is replaced, the fetch fails with the existing "could not remove the old copies" error, and the record and the snapshot are the new ones.
5. Controller: with `test262.lock` present, a fetch fails with the lock error, and the snapshot, the record, and the lock file stay unchanged.
6. Controller: two fetches of the Git corpus started together end with exactly one `pass` and one lock error, the corpora directory lists only `test262`, and `corpus-verify` passes.
   The same holds for two fetches of one file set.
7. Controller: every existing file-set write-phase case passes unchanged.
8. `node tools/fairpane.mjs corpus-applicability wpt` regenerates `specs/applicability/wpt.json`, and the diff changes only the discovery rule text.

Cases 1 to 6 must fail before the change, except case 2 on hosts other than Windows.
If case 2 passes on the base on Windows, the worker records that run and reports that the review's inference about the search order did not hold, instead of changing the case.
Each of three mutation controls must fail at least one case: skip the restore of the old snapshot directory, remove the lock check, and start `taskkill.exe` by bare name.
A fourth mutation control removes the `check(record)` invariant from the Git corpus fetch and must fail an existing pin case, as review 3 suggested.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0052/raw/`, and keep each failed attempt as its own log.

1. `tests-before.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. `mutation.log` and its diffs, with the hash of each changed file before, during, and after.
3. `applicability.log` with the regeneration, and `applicability-diff.log` with `git diff --stat` and `git diff` of `specs/applicability/wpt.json`.
   The command reads the snapshots through `FAIRPANE_CORPORA_DIR`, set to the integrator's directory `C:\src\fairpane\.tools\corpora`, and fetches nothing.
4. `controller-tests-after.log` with `node tools/fairpane.mjs test`.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test`.
The integrator then runs `corpus-verify test262` and `corpus-verify wpt` at the integration commit and records them.

## Authority

Writable paths: `specs`, `tools`, `tests`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged, including `specs/corpora.json`.
Required reviewers: `fairpane-review` and `fairpane-spec`.

## Non-goals

- No crash recovery between rename steps; `FP-0078` owns it.
- No lock for commands that only read a snapshot.
- No change to the pins, the applicability counts, or the discovery itself.
