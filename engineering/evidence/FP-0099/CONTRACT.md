# FP-0099 task contract

## Identity

Task ID: `FP-0099`, "Close the FP-0067 and FP-0079 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract, at least `b9217fe`. Every line number below was re-read at `b9217fe`.
Prerequisites: `FP-0052`, `FP-0067`, `FP-0079`, and `FP-0081`, all accepted (`engineering/state.json:706`, `:844`, `:928`, and `:942`).
A contract worker drafted this contract, an independent pre-freeze check reviewed it, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings:

- `engineering/evidence/FP-0067/reviews/review-1-reject.json`: the minor finding on the Linux gate rule (`tools/workflow-check.mjs:457` at review time), the note that `repo-check` does not call the workflow checker, and the note that no mutation control targets the `JOB_GATES` order check.
- `engineering/evidence/FP-0079/reviews/security-review-2-accept.json`: the minor finding on the device-name check (`tools/rust.mjs:113` at review time), the note on component names (`tools/rust.mjs:284` at review time), and the note that `doctor` starts `bun`, `git`, `omp`, and `zig` by bare name.
- `engineering/evidence/FP-0081/reviews/security-review-1-accept.json`: the note on requested bytes and allocator granularity, and the note that the budget is in-process self-accounting, not containment.
- The FP-0065 split draft, through the plan text of criterion 7. The drafter did not read that draft.

`FP-0107` is still `active` (`engineering/state.json:974`), and its revision 2 is in the base: every case module passes a `{ processWide }` declaration through (for example `tools/workflow-check.test.mjs:387` and `tools/rust.test.mjs:586`).
If an `FP-0107` or `FP-0132` commit changes a file that this contract edits, or `toolchains/rust.lock.json`, before dispatch, the worker rebases onto it before `tests-before.log`, and evidence item 7 runs on that base.

### Integrator decisions

0. Agent CheckFindings checked the draft twice: its first check (fix-first, 1 blocker) led to this revision, and its re-check (fix-first, 1 major) supplied case 11 and M11 for the real-path refusal, which the integrator applied verbatim at the freeze with the re-check's minor and note.
1. Criterion 2 takes its first branch: `repo-check` runs the workflow checks.
   `workflow-check.mjs` exports the reviewed problem list, and `checkRepository` compares every file under `.github/workflows` with it.
   Running the checks costs milliseconds: `engineering/evidence/FP-0067/raw/mutation.log` records 57 ms for `node tools/workflow-check.test.mjs`.
2. `gateWorkflowProblems` reports a missing job for each `JOB_GATES` entry whose job ID is absent.
   The problem is `Line <L>: The Gates workflow has no job <id>. It must have a job <id> that runs <gates>, in that order.`, where `<L>` is the line of the `jobs:` key and `<gates>` is the list that the existing order problem prints.
3. The four FP-0033 assertions that expect `[]` from `gateWorkflowProblems` on `BASE` variants are amended, and no test-only argument is added.
   `BASE` has a job named `build` and no `linux` job, so `tools/workflow-check.test.mjs:201` and `:207` (case `FP-0033 9`) and `:222` and `:224` (case `FP-0033 12`) change to expect exactly the one missing-job problem at line 12.
   Each still demands an exact list, so each still detects any extra or missing problem.
   The cases are renamed `FP-0033 9 (amended by FP-0099 case 1): ...` and `FP-0033 12 (amended by FP-0099 case 1): ...`.
4. The archive path rule is `relativePathProblem` in `tools/lib.mjs`, which corpus extraction also uses (`tools/corpus.mjs:696`).
   The stricter device-name rule therefore applies to `corpus-extract` as well, and that is intended.
5. A component name keeps the existing regex check, and each name must also pass the archive path rule.
   Every name is checked before the first `manifest.in` is read, so a bad name installs nothing.
6. `doctor` resolves each probe through `resolveExecutable` with a search path that keeps only fully qualified `PATH` entries that lexically lie outside the repository.
   Before it starts a resolved file, it compares real paths with the existing `isInside` of `tools/attest.mjs:77-80`, which `tools/fairpane.mjs:11` already imports, and it refuses a file whose real path is inside the repository.
   "The repository directory" covers the whole tree, because its subdirectories hold repository and fixture content.
   An available probe reports its resolved `path`.
7. The `api/README.md` text is the four frozen lines in "Behavior".
8. Citation validation accepts any number of digits after `S`. The scanned files stay `docs`, `README.md`, `START_HERE.md`, and `LICENSE-DECISION.md` (`tools/lib.mjs:346`). The scan is not extended to `specs/*.md`; a separate plan entry would have to propose that.
9. The case fixtures for `checkRepository` write their own `specs/sources.json`, so no source that a later task adds can make an "unknown source" row known.
10. New cases that call new exports read them through a namespace import, so the base suite links and each such case fails alone with a `TypeError`.
11. The worker records `install-rust` on Windows and on WSL Ubuntu after the change, because the stricter rule narrows the reader that `install-rust` uses and no gate runs `install-rust`.
12. The median, over three recorded `node tools/fairpane.mjs test` runs, of the sum of the new cases' `# duration_ms` lines is at most 3000 ms on the development host.

### Observed facts that shaped the decisions

- `tools/workflow-check.mjs:364-366` defines `JOB_GATES` with the single entry `linux`.
  `tools/workflow-check.mjs:473-474` reads `const gates = JOB_GATES.get(id); if (!gates) continue;`, so a renamed or removed `linux` job yields no problem.
  `tools/workflow-check.mjs:480-482` holds the order check: `if (ran.join('\n') !== gates.join('\n'))`.
- `tools/workflow-check.mjs:372` defines `series`, which joins three or more items with commas and a final `and`.
- The parser numbers physical lines from 1 (`tools/workflow-check.mjs:124`) and records the line of each mapping key (`:204`).
  In `.github/workflows/gates.yml`, `jobs:` is line 19. In `BASE` (`tools/workflow-check.test.mjs:17-39`), `jobs:` is line 12.
- `tools/lib.mjs:314-369` (`checkRepository`) reads no workflow file. The only importer of `workflow-check.mjs` is its test module.
- `tools/lib.mjs:67` is `/^(?:CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])$/i`, and `tools/lib.mjs:82` tests `part.split('.')[0]` without removing spaces.
  A component that ends in a space is already rejected at `tools/lib.mjs:81`, so only a space before the first `.` reaches the device-name check.
- `tools/rust.mjs:99-101` makes `acceptedArchivePath` the shared rule. `tools/rust.mjs:271` checks component names only with `/^[a-z0-9][a-z0-9_.-]*$/`, which accepts `a.`, `nul`, and `com1.tool`.
- `tools/fairpane.mjs:21-25` starts each probe with `spawnSync(executable, ...)` by bare name, and `tools/fairpane.mjs:99-101` probes `bun`, `git`, `omp.exe` or `omp`, and `zig`.
- `tools/lib.mjs:677-696` (`resolveExecutable`) searches only `PATH` entries, skips empty entries, and tries `.com` and `.exe` on Windows. It resolves a relative entry against the process working directory.
- `tools/attest.mjs:77-80` (`isInside`) compares `fs.realpathSync.native` of both paths, which resolves links, case, and short names.
- libuv `src/win/process.c` (`search_path`) searches the working directory before `PATH` when `NeedCurrentDirectoryForExePathW(L"")` is true, which is the default unless `NoDefaultCurrentDirectoryInExePath` is set.
- `tools/lib.mjs:348-349` matches only `/\[S\d{2}(?:,\s*S\d{2})*\]/g`. `specs/sources.json` defines `S100` (`:807`), `S101` (`:815`), and, since `b68eebf` (FP-0123), `S102` (`:823`). The case fixtures write their own source list.
  No scanned file cites a source with other than two digits at `b9217fe`, so the wider pattern changes no current result.
- `api/README.md:226-237` describes the engine memory limit. It says that the count excludes allocator overhead (`:229`), but not that resident memory can exceed the limit or that the limit is not containment.
- `src/c_api.zig:54` sets the process allocator to `std.heap.page_allocator` when single-threaded and `std.heap.smp_allocator` otherwise.
- `engineering/evidence/FP-0079/raw/tests-before-r1.log:33` shows that the base reader wrote the `CON`, `nul.txt`, and `COM1` fixtures as named-case failures, without a hang or a cleanup failure.
- `tools/README.md:17` and `:18` are the `doctor` and `check` rows, `:205` states the Linux gate rule, and `:208-209` say that only the test module checks the workflow files.
- `engineering/evidence/FP-0079/raw/install-rust-r1.log` records an `install-rust` run that exited with status 0 in 8749 ms. `.tools/downloads` on the development host holds only the Zig archive.

## Sources

- `engineering/plan.json`, entry `FP-0099` (`:3577-3600`), criteria 1 to 7.
- The three review records listed in "Identity".
- Microsoft, "Naming Files, Paths, and Namespaces", <https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file>, retrieved 2026-10-09.
  Its reserved list is CON, PRN, AUX, NUL, COM1 to COM9, COM¹, COM², COM³, LPT1 to LPT9, LPT¹, LPT², and LPT³, and it does not list CONIN$ or CONOUT$.
- CPython `Lib/ntpath.py` at `e48b1eb949daacaa84c87da57732866ab1894a86`, the latest commit to that file on 2026-10-09, retrieved 2026-10-09.
  `_reserved_names` includes `CONIN$` and `CONOUT$`, and `_isreservedname` returns `name.partition('.')[0].rstrip(' ').upper() in _reserved_names`, with the comment `DOS device names are reserved (e.g. "nul" or "nul .txt")`.
- libuv `src/win/process.c`, branch `v1.x`, function `search_path`, retrieved 2026-10-09. [INFERENCE] The libuv in Node 24.21.0 has the same search order.
- Repository files: `tools/workflow-check.mjs`, `tools/workflow-check.test.mjs`, `tools/lib.mjs`, `tools/attest.mjs`, `tools/rust.mjs`, `tools/rust.test.mjs`, `tools/fairpane.mjs`, `tools/selftest.mjs`, `tools/abi.test.mjs`, `tools/README.md`, `api/README.md`, `.github/workflows/gates.yml`, `.github/workflows/pages.yml`, and `specs/sources.json`.

## Behavior

### Files

| File | Change |
| --- | --- |
| `tools/workflow-check.mjs` | The missing-job problem, `REVIEWED_WORKFLOW_PROBLEMS`, and `workflowFileProblems` |
| `tools/lib.mjs` | Workflow checks and wider citations in `checkRepository`, the device-name rule, and `probeSearchPath` |
| `tools/rust.mjs` | The component-name path check |
| `tools/fairpane.mjs` | `doctor` probes by resolved absolute path, with the real-path refusal |
| `api/README.md` | Four lines in "Engines" |
| `tools/README.md` | The `check` and `doctor` rows, line 205, and the paragraph at lines 207-209 |
| `tools/workflow-check.test.mjs` | Cases 1 and 2 and the amended FP-0033 cases 9 and 12 |
| `tools/selftest.mjs` | Cases 3, 4, 7, and 10 |
| `tools/rust.test.mjs` | Cases 5, 6, and 8 |
| `tools/abi.test.mjs` | Case 9 |

### Workflow checker

After `gateWorkflowProblems` checks every job, it adds one problem for each `JOB_GATES` entry, in `JOB_GATES` order, whose job ID is not a key of the `jobs` mapping.
For `linux`, the problem is `Line <L>: The Gates workflow has no job linux. It must have a job linux that runs repo-check, controller-test, zig-fmt, zig-test, cross-windows-x86_64, cross-linux-aarch64, and cross-macos-aarch64, in that order.`, where `<L>` is the line of the `jobs:` key.
The doc comment of `gateWorkflowProblems` (`tools/workflow-check.mjs:387-388`) states the rule.

`workflow-check.mjs` also exports:

- `REVIEWED_WORKFLOW_PROBLEMS`, a frozen object: `gates.yml` maps to `[]`, and `pages.yml` maps to `['Line 49: Job deploy grants a permission other than contents: read (pages: write, id-token: write).']`. These are the values of `REVIEWED` at `tools/workflow-check.test.mjs:66-69`.
- `workflowFileProblems(files)`, where `files` is a `Map` from a file name to its text. It returns problems for the sorted union of the reviewed names and the given names:
  - A given name that is not reviewed gives `.github/workflows/<name> is not a reviewed workflow file.`
  - A reviewed name that is not given gives `.github/workflows/<name> is missing.`
  - Otherwise the file's problems are `checkWorkflow(text)`, followed for `gates.yml` by `gateWorkflowProblems(parseWorkflow(text))`. A `WorkflowParseError` becomes the single problem `<its message>`.
    Each problem that is not in the reviewed list gives `.github/workflows/<name>: <problem>`, in order. Then each reviewed problem that did not occur gives `.github/workflows/<name>: the reviewed problem is absent: <problem>`.

`workflow-check.mjs` keeps no imports. `tools/lib.mjs` reads the files.

### Workflow checks in repo-check

After the source citation check, `checkRepository` reads every entry of `.github/workflows` through `safePath` as UTF-8 and calls `workflowFileProblems`.
When the result is not empty, it throws an error whose message is `The workflow files have unreviewed problems:` followed, for each problem, by an LF and `- <problem>`.

### Archive path rule

The reserved-name pattern adds `CONIN$` and `CONOUT$`: `/^(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])$/i`.
The compared text is the component's text before its first `.`, with trailing U+0020 SPACE characters removed.
The checks keep their order and their reason strings.
The doc comment at `tools/lib.mjs:61-73` names both additions, says that Microsoft's page does not list `CONIN$` and `CONOUT$`, and cites CPython's `isreserved` for them and for the space removal.

### Component names

`installComponents` keeps the check at `tools/rust.mjs:271`.
Then, before it reads any `manifest.in` or copies any file, it checks each name in order with `acceptedArchivePath` and throws `The archive path is not accepted: <name>` for the first name that fails.

### Doctor probes

`tools/lib.mjs` exports `probeSearchPath(root, pathEnv = process.env.PATH ?? '', platform = process.platform)`.

- It uses `path.win32` when `platform` is `win32` and `path.posix` otherwise, and that API's delimiter.
- It keeps an entry when the entry is not empty, is fully qualified, and resolves to neither the resolved `root` nor a path inside it.
  On `win32`, a fully qualified entry is a drive letter followed by `:` and `\` or `/`, or a path that starts with `\\`. Otherwise, it is a path that starts with `/`.
- On `win32`, the comparison with `root` ignores letter case.
- It returns the kept entries joined with the delimiter, in their order.

`doctor` resolves each probe with `resolveExecutable(root, name, { pathEnv: probeSearchPath(root) })`.
Before it starts a resolved file, it calls `isInside(file, root)` from `tools/attest.mjs`.

- A name that does not resolve gives `{ available: false, error: 'The executable is not on PATH: <name>' }`, the resolver's message.
- A resolved file whose real path is inside the repository gives `{ available: false, path, error: 'The executable is inside the repository: <path>' }`, where `<path>` is the resolved path, and doctor does not start it.
- If `isInside` throws, the probe gives `{ available: false, path, error: <its message> }`, and doctor does not start the file.
- Otherwise doctor starts the resolved file with the same arguments, 15000 ms timeout, and `windowsHide`.
  A file that exits with status 0 gives `{ available: true, path, version }`, and a file that fails gives `{ available: false, path, error }`, where `error` is the spawn error code or `exit <status>`, as now.
- `path_zig` keeps its note.

### Engine memory limit documentation

`api/README.md` gains these four lines, in this order, directly after line 237 (`The limit does not bound the host's memory, stack use, or allocations outside an engine.`):

```text
The limit bounds the bytes that the engine requests, not the resident memory of the process.
The resident memory of the process can exceed the limit by allocator granularity, because the process allocator can hold more memory for an allocation than the engine requested.
A host that needs a hard cap on memory combines the limit with operating-system limits, such as a job object on Windows or a cgroup on Linux.
The limit is a local integrity bound that the engine keeps on its own allocations, not containment: code that corrupts the engine's memory can also change its count and its limit.
```

### Source citations

`checkRepository` matches `/\[S\d+(?:,\s*S\d+)*\]/g` and, inside each match, `/S\d+/g`.
An unknown identifier keeps the message `<file> names an unknown source <id>.`

### Documentation

`tools/README.md` changes exactly as follows:

- Line 17 becomes ``| `doctor` | Reports actual tools and a missing compiler without a success claim. It starts each probe by the absolute path that a fully qualified `PATH` entry outside the repository names, and never a program whose real path is inside the repository. |``.
- Line 18 becomes ``| `check` | Checks the task graph, required scope, compiler lock, source references, lexical imports, and every workflow file against its reviewed problem list. |``.
- Line 205 becomes ``- The workflow must have a `linux` job, and that job must run exactly `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `cross-windows-x86_64`, `cross-linux-aarch64`, and `cross-macos-aarch64`, in that order. A missing `linux` job is one problem at the line of `jobs:`.``
- Line 209 is followed by the new line ```node tools/fairpane.mjs check` compares every file under `.github/workflows` with the same list, `REVIEWED_WORKFLOW_PROBLEMS` in `tools/workflow-check.mjs`, and fails on any difference.``

## Exact test cases

Controllers run through `node tools/fairpane.mjs test`. Each new case is named `FP-0099 case N: ...`. No new case changes the working directory, `process.env`, or a module-level function, so none declares `processWide`.

1. `tools/workflow-check.test.mjs`. Let `GATES` be the committed `gates.yml` with LF line ends, as at line 71.
   - `onlyProblem(GATES.replace('  linux:\n', '  ubuntu:\n'), M19)` passes, where `M19` matches exactly `Line 19: The Gates workflow has no job linux. It must have a job linux that runs repo-check, controller-test, zig-fmt, zig-test, cross-windows-x86_64, cross-linux-aarch64, and cross-macos-aarch64, in that order.` The case first asserts that the replacement changed the text.
   - `onlyProblem(GATES.split('  linux:\n')[0], M19)` passes. That text holds only the `windows` job.
   - Amended `FP-0033 9`: `gates(BASE)` and `gates(variant(run, upload('        if: ${{ always() }}\n')))` each deep-equal `[B12]`, where `B12` is the same text as `M19` with `Line 12`.
   - Amended `FP-0033 12`: `gates(accepted)` and `gates(variant(run, '        run: node tools/fairpane.mjs install-zig\n'))` each deep-equal `[B12]`. Every other assertion of both cases stays.
2. `tools/workflow-check.test.mjs`, through `import * as workflowCheck from './workflow-check.mjs'`. Let `PAGES` be the committed `pages.yml` with LF line ends.
   - `workflowCheck.REVIEWED_WORKFLOW_PROBLEMS` deep-equals the test's own `REVIEWED`.
   - `workflowFileProblems(new Map([['gates.yml', GATES], ['pages.yml', PAGES]]))` is `[]`.
   - With `gates.yml` renamed as in case 1: `['.github/workflows/gates.yml: Line 19: The Gates workflow has no job linux. It must have a job linux that runs repo-check, controller-test, zig-fmt, zig-test, cross-windows-x86_64, cross-linux-aarch64, and cross-macos-aarch64, in that order.']`.
   - With the committed files and `['extra.yml', BASE]`: `['.github/workflows/extra.yml is not a reviewed workflow file.']`.
   - With only `pages.yml`: `['.github/workflows/gates.yml is missing.']`.
   - With `PAGES.replace('    permissions:\n      pages: write\n      id-token: write\n', '    permissions:\n      contents: read\n')`: `['.github/workflows/pages.yml: the reviewed problem is absent: Line 49: Job deploy grants a permission other than contents: read (pages: write, id-token: write).']`. The case first asserts that the replacement changed the text.
3. `tools/selftest.mjs`. A helper `repoCheckFixture()` builds a temporary repository that holds exactly the files that `checkRepository` reads:
   - Copied unchanged from the repository: `engineering/gates.json`, `engineering/plan.json`, `engineering/state.json`, `engineering/workstreams.json`, `engineering/qualification.json`, `engineering/dependencies.json`, `toolchains/zig.lock.json`, `toolchains/zig-version.txt`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, `.github/workflows/gates.yml`, and `.github/workflows/pages.yml`.
   - Written:
     - `engineering/policy.json` as `{ schema_version: 1, source_roots: ['README.md', 'docs', '.github'], policy_roots: ['engineering/policy.json'], protected_paths: [], allowed_evidence_roots: ['out/evidence'], required_files: ['README.md'] }`.
     - `specs/sources.json` as `{ "sources": [{ "id": "S00" }, { "id": "S36" }, { "id": "S99" }, { "id": "S100" }, { "id": "S101" }] }`.
     - `README.md`, `START_HERE.md`, and `LICENSE-DECISION.md`, each `Fixture.` and an LF.
     - `docs/CITE.md` as `See [S00], [S99], [S100], and [S36, S101].` and an LF.
     - `src/root.zig` as `const std = @import("std");` and an LF.
   - `checkRepository(fixture).result` is `pass`.
   - After `.github/workflows/gates.yml` has its line `  linux:` renamed to `  ubuntu:` (the case keeps the file's line ends and asserts that the text changed), `checkRepository(fixture)` throws exactly `The workflow files have unreviewed problems:` + LF + `- .github/workflows/gates.yml: Line 19: The Gates workflow has no job linux. It must have a job linux that runs repo-check, controller-test, zig-fmt, zig-test, cross-windows-x86_64, cross-linux-aarch64, and cross-macos-aarch64, in that order.`
4. `tools/selftest.mjs`, through `lib.relativePathProblem`:
   - `test/CON .txt`, `test/nul  .x`, `test/CONIN$`, `test/conout$.log`, `test/Conin$/x.js`, and `test/AUX .tar.gz` each give `a reserved Windows device name`.
   - `test/CONSOLE.txt`, `test/conin.txt`, `test/a CON.txt`, and `test/CONIN$x.js` each give `null`.
5. `tools/rust.test.mjs`, with `R = 'fx-1.0.0-x86_64-pc-windows-gnu'`: `extractTarGz` of an archive that holds the entry `${R}/ok` and then one of `${R}/CON .txt`, `${R}/nul  .x`, `${R}/CONIN$`, and `${R}/conout$.log`, as a regular file with data `x`, rejects with exactly `The archive path is not accepted: <that name>`. The case reports every fixture that is not rejected with its exact message, as FP-0079 case 5 does.
6. `tools/rust.test.mjs`, with the component fixture of FP-0079 case 6 (`tools/rust.test.mjs:434-464`) moved to module scope unchanged:
   - Components `a.` give `The archive path is not accepted: a.`.
   - Components `nul` give `The archive path is not accepted: nul`.
   - Components `com1.tool` give `The archive path is not accepted: com1.tool`.
   - Components `fx-tool` and `nul`, on two lines, give `The archive path is not accepted: nul`, and the toolchain directory does not exist afterward.
   - FP-0079 case 6 keeps every row, including `a/b`, which still gives `The component list is invalid.`
7. `tools/selftest.mjs`, through `lib.probeSearchPath` and `isInside` from `tools/attest.mjs`. The strings below are values, not source literals.
   - Root `C:\repo`, `PATH` `C:\bin;;.;tools;C:\repo;c:\REPO\tools;C:\repo\;C:\repository;D:\x`, platform `win32`: `C:\bin;C:\repository;D:\x`.
   - Root `C:\repo`, `PATH` `\bin;C:\bin`, platform `win32`: `C:\bin`.
   - Root `/repo`, `PATH` `/usr/bin::.:bin:/repo:/repo/tools:/repo/:/repository:/x`, platform `linux`: `/usr/bin:/repository:/x`.
   - Root `/repo`, `PATH` empty, platform `linux`: the empty string.
   - With a temporary root `R` that holds a file `x`, and a junction on Windows, or a symbolic link elsewhere, `L` to `R` in another temporary directory, `isInside(path.join(L, 'x'), R)` is `true`, and `isInside` of a file in a third temporary directory and `R` is `false`.
8. `tools/rust.test.mjs`, with the existing `markerProgram` helper (`tools/rust.test.mjs:274-278`):
   - `cwd` is a new temporary directory. It holds marker programs named `bun`, `git`, `omp`, and `zig`, each with the suffix `.exe` on Windows, and each creates its own marker `cwd-<name>-started` in a separate marker directory.
   - `binDir` is another new temporary directory with a marker program `git` (`git.exe` on Windows) that creates `path-git-started`.
   - `emptyDir` is an empty temporary directory.
   - The child environment copies `process.env`, deletes every key whose upper-case form is `NODEFAULTCURRENTDIRECTORYINEXEPATH`, and sets the existing `PATH` key, found without regard to case, to `['', '.', binDir, emptyDir].join(path.delimiter)`.
   - `doctor` runs as `spawnSync(process.execPath, [<root>/tools/fairpane.mjs, 'doctor'], { cwd, env, encoding: 'utf8', windowsHide: true })` and exits with status 0.
   - Its report gives `{ bun: false, git: true, git_path: <binDir>/git[.exe], omp: false, path_zig: false, started: ['path-git-started'] }`, where `started` lists the marker files that exist, sorted.
   - `report.bun.error` is `The executable is not on PATH: bun`, `report.omp.error` names `omp.exe` on Windows and `omp` elsewhere, and `report.path_zig.error` names `zig`.
   - The case then starts each of the four `cwd` markers directly by absolute path with `--version`. Each exits with status 0 and creates its marker.
9. `tools/abi.test.mjs`: `api/README.md` holds the four frozen lines, each as a whole line, in that order, after the line `## Engines` and before the line `## Identifiers`.
10. `tools/selftest.mjs`, with `repoCheckFixture()`:
    - `docs/CITE.md` as in case 3 passes.
    - With `docs/CITE.md` replaced by each of these lines, `checkRepository` throws exactly the given message:
      - `See [S102].` gives `docs/CITE.md names an unknown source S102.`
      - `See [S5].` gives `docs/CITE.md names an unknown source S5.`
      - `See [S36, S102].` gives `docs/CITE.md names an unknown source S102.`
      - `See [S1000].` gives `docs/CITE.md names an unknown source S1000.`

11. `tools/rust.test.mjs`: `T` is a new temporary directory that holds copies of every `tools/*.mjs` under `T/tools`, `toolchains/zig.lock.json`, and `toolchains/rust.lock.json`, and a marker program `T/bin/git` (`git.exe` on Windows) that creates `inside-git-started` in a separate marker directory. `L` is a junction on Windows, or a symbolic link elsewhere, to `T`, in another temporary directory. The child environment is built as in case 8, with `PATH` set to `path.join(L, 'bin')`. `spawnSync(process.execPath, [path.join(T, 'tools/fairpane.mjs'), 'doctor'], { cwd: <a new empty temporary directory>, env, encoding: 'utf8', windowsHide: true })` exits with status 0. `report.git` deep-equals `{ available: false, path: <L>/bin/git[.exe], error: 'The executable is inside the repository: <L>/bin/git[.exe]' }`, and the marker does not exist. The case then starts `T/bin/git[.exe]` directly by absolute path with `--version`; it exits with status 0 and creates the marker.

### Base failures

Each case below fails on the base as a named case. None makes the suite fail to load.

- Case 1 and the amended FP-0033 cases 9 and 12: `gateWorkflowProblems` returns `[]` for these inputs, because of `tools/workflow-check.mjs:473-474`.
- Case 2: `workflowCheck.workflowFileProblems` is `undefined`, so the call throws `TypeError`.
- Case 3: `checkRepository` reads no workflow file (`tools/lib.mjs:314-369`), so it does not throw.
- Case 4: `tools/lib.mjs:67` and `:82` return `null` for every reserved row.
- Case 5: the base reader extracts each fixture, so each row reports a missing rejection.
- Case 6: the base reads `a./manifest.in` and the other paths, so it throws an `ENOENT` error with another message. For `fx-tool` and `nul`, it installs `fx-tool` first.
- Case 7: `lib.probeSearchPath` is `undefined`.
- Case 8: on Windows, libuv runs the `cwd` markers before `PATH`, so `started` holds the `cwd` markers and `bun`, `omp`, and `path_zig` are `true`. On Linux, [INFERENCE] the `.` entry makes the base start the `cwd` markers.
- Case 9: `api/README.md:226-237` has none of the four lines.
- Case 10: the base pattern at `tools/lib.mjs:348` matches none of the four lines, so `checkRepository` does not throw.
- Case 11: the base starts `git` by bare name, libuv finds it through `L`, and the marker exists.

### Mutation controls

Record each control as a `.diff`. Apply it, run the named test module, and restore the file, recording the file hash before, during, and after, as `engineering/evidence/FP-0067/raw/mutation.log` does.

| Control | Mutation | Case that fails |
| --- | --- | --- |
| M1 | Remove the missing-job loop from `gateWorkflowProblems` | Case 1, amended FP-0033 9 and 12, the renamed row of case 2, and case 3 |
| M2 | Replace `ran.join('\n') !== gates.join('\n')` with `false` in the Linux job's gate order check (criterion 6) | `FP-0067 5`, which gets 0 problems instead of 1 |
| M3 | Drop the `gateWorkflowProblems` call from `workflowFileProblems` | Case 2, the renamed row, and case 3 |
| M4 | Remove the workflow check from `checkRepository` | Case 3 |
| M5 | Remove the trailing-space removal | Case 4, row `test/CON .txt` |
| M6 | Remove `CONIN\$` from the reserved pattern | Case 4, row `test/CONIN$` |
| M7 | Remove the component-name path check | Case 6 |
| M8 | Keep relative entries in `probeSearchPath` | Case 7, and case 8 through the `.` entry |
| M9 | Start each `doctor` probe by its bare name | Case 8 |
| M10 | Restore `\d{2}` in both citation patterns | Case 10 |
| M11 | Remove the `isInside` refusal from `doctor` | Case 11 |

### Stop rules

- If the Windows base run of case 8 starts no `cwd` marker, stop. Record the run and report that the search-order observation did not hold. Never change the case to make it fail.
- If a direct start of a marker program fails, for example because antivirus quarantined it, stop and report.
- If `corpus-extract test262` rejects a path under the new rule, stop and report the path. Never relax the rule.
- If `install-rust` rejects a locked archive path or component name under the new rule, stop and report the path. Never relax the rule.
- If the median over three recorded `node tools/fairpane.mjs test` runs of the sum of the new cases' `# duration_ms` lines exceeds 3000 ms on the development host, stop and report each case's duration in every run.
- If any expectation here contradicts the cited source or the base code, stop and report it. Never edit an expectation silently.

### Criterion mapping

| FP-0099 criterion | Cases and evidence |
| --- | --- |
| 1. Report a missing job; test a renamed linux job | Case 1, amended FP-0033 9 and 12; M1 |
| 2. Run the workflow checks in repo-check | Cases 2 and 3; M3, M4; `check-after.log` |
| 3. Device names with trailing spaces, CONIN$ and CONOUT$, component names | Cases 4, 5, 6; M5, M6, M7; `corpus-extract-after.log`, `install-rust-after.log`, `linux-install-rust-after.log` |
| 4. doctor probes never run a program from the repository directory | Cases 7, 8, and 11; M8, M9, M11 |
| 5. api/README.md memory-limit statements | Case 9 |
| 6. Mutation control for the Linux gate order check | M2 |
| 7. Citations of every length | Case 10; M10 |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0099/raw/`. Never overwrite a log. Name a failed attempt's log with the suffix `-attempt-N`.

1. `tests-before.log`: in a worktree at the base, record `git rev-parse HEAD`, the staging command, and the blob IDs of the after-tree `tools/workflow-check.test.mjs`, `tools/selftest.mjs`, `tools/rust.test.mjs`, and `tools/abi.test.mjs` staged onto it. Then record `cmd /d /c ver`, `node --version`, and `node tools/fairpane.mjs test`. It must exit with status 1, and exactly the cases under "Base failures" must fail.
2. `tests-before-linux.log` and `tests-after-linux.log`: on WSL Ubuntu, from copies of the staged base tree and of the after tree, record `uname -a`, the WSL Node version, and `node tools/rust.test.mjs`, with the Node of `engineering/evidence/hosts/wsl-ubuntu/node-install.log`. Report the case 8 result on each.
3. `mutation.log` with `mutation-M1.diff` to `mutation-M11.diff`.
4. `controller-tests-after.log`, `controller-tests-after-2.log`, and `controller-tests-after-3.log`: `node --version` and `node tools/fairpane.mjs test`, each of which must exit with status 0. Report each new case's `# duration_ms` line from each run and the median of the sums.
5. `check-after.log`: `node tools/fairpane.mjs check`, which must exit with status 0.
6. `corpus-extract-after.log`: `node tools/fairpane.mjs corpus-extract test262 out/fp0099-extract` with `--env FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, which must exit with status 0.
7. `install-rust-after.log` and `linux-install-rust-after.log`: from a fresh worktree of the after tree on Windows, and from the WSL copy of the after tree, `node tools/fairpane.mjs install-rust`, each of which must exit with status 0.
8. `engineering/evidence/FP-0099/README.md`: the worktree `HEAD`, the criterion mapping, each control's result, each case's durations, and every resolved ambiguity.

The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0099/gates`.
After the push, the integrator records `gh run view` of the first `Gates` run that contains the change and the Windows and Linux `repo-check` and `controller-test` receipts under `engineering/evidence/FP-0099/ci/`. Each must report `pass`.

## Authority

The writable paths are `tools`, `tests`, `api/README.md`, and `engineering/evidence/FP-0099/`.
These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
`.github` and `docs` are not writable, so `docs/TOOLCHAIN.md:46` and `:61` stay as they are; both remain accurate.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
The required reviewers are `fairpane-review` and `fairpane-security`.

## Non-goals

- No change to `.github/workflows`, the gate list, any action, or `REVIEWED_ACTIONS`.
- No new citation roots. `specs/IMPORT_REQUIREMENTS.md`, which cites `[S101]`, stays outside the scan.
- No change to `record`, `resolveExecutable`, or `isInside`.
- No containment of engine memory and no change to the memory budget code.
- No other Windows path rule, such as leading spaces, wildcards, or names longer than a component limit.

## Resolved questions

- The four FP-0033 assertions are amended. A test-only `jobGates` argument would test a checker configuration that never ships, and the amended assertions still require exact lists.
- The citation scan stays on its current files. Criterion 7 concerns the pattern at `tools/lib.mjs:348-349`, not the roots at `:346`.
- `install-rust` runs after the change on Windows and on WSL Ubuntu, because the stricter rule narrows the reader that it uses and no gate runs it.
- The doctor probe skips every path inside the repository, compared by real path, so a junction, a symbolic link, a `subst` drive, or an 8.3 alias of the repository cannot bypass the rule.
