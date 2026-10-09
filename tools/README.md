# Development controller

## Scope

The controller runs on Node 22 or newer without package dependencies.
Bun uses the same entry point but needs separate runtime qualification.
Neither development runtime belongs in the shipped engine.

The controller checks local repository integrity and executes a small gate registry.
It does not schedule OMP sessions or implement browser conformance.
It does not publish code, change approval settings, or choose an account identity.

## Commands

| Command | Result |
| --- | --- |
| `doctor` | Reports actual tools and a missing compiler without a success claim. |
| `check` | Checks the task graph, required scope, compiler lock, source references, and lexical imports. |
| `test` | Runs the controller's positive and negative tests. |
| `next` | Reports active tasks and tasks with accepted prerequisites. |
| `status` | Reports task and capability state. |
| `fingerprint` | Hashes declared source and policy inventories. |
| `install-zig` | Downloads and checks the exact locked compiler in a local directory. |
| `install-rust` | Downloads and checks the exact locked Rust toolchain components in a local directory. |
| `rust-lock-verify <manifest>` | Exits with status 1 when a channel manifest file's digest or component entries differ from `toolchains/rust.lock.json`. |
| `run <gate-id> [--evidence-dir <dir>]` | Executes a gate without a command shell and writes its receipt. |
| `record [--cwd <dir>] [--env NAME=VALUE]... <log> <executable> [arguments...]` | Runs one command without a shell and appends its output and result to an evidence log. |
| `evidence-check <path>` | Checks a passed receipt against current inputs and output artifacts. |
| `corpus-fetch <id>` | Fetches the pinned corpus commit, or the frozen file-set sources, into a fresh snapshot and writes its record. |
| `corpus-repin <id>` | Moves a Git corpus snapshot to the upstream branch head and writes its record. A file-set corpus exits with status 1. |
| `corpus-applicability <id>` | Counts discovered tests or files in a local snapshot without network access or corpus code. |
| `corpus-verify <id>` | Recomputes a local snapshot and compares its records and `specs/corpora.json` pins. |
| `corpus-derive <id>` | Runs the declared import-tool derivations of a file-set corpus, requires each output to match any existing fixture byte for byte, and records it. |
| `attest-verify --repository <path> --trust-policy <path> --candidate <commit> <envelope>` | Verifies a signed result against protected trust input and a full commit ID in a candidate repository. |
| `abi-generate` | Validates the ABI schema and failure scenarios, then writes `include/fairpane.h`, `src/abi_generated.zig`, and `tests/c/abi_layout.h`. |
| `abi-check` | Regenerates the ABI files in memory and exits with status 1 when a committed file differs. |
| `abi-exports <library>` | Exits with status 1 when a static library exports an `fp_` symbol that the ABI schema does not declare, or lacks one that it declares. |
| `source-archive <commit> <output-dir>` | Writes `fairpane-<commit>.tar` and `fairpane-<commit>.manifest.json` for a full commit ID into a directory outside the repository. |
| `provenance <commit> <artifact>...` | Prints an unsigned in-toto statement with a SLSA provenance predicate for the artifacts. |
| `reproduce-check <commit>` | Builds a full commit ID twice in fresh work trees under `out/reproduce/` and exits with status 1 unless every installed file matches. |
| `ucd-generate` | Reads the imported UCD files under `src/unicode/ucd/` and writes `src/unicode/tables.zig`. |
| `ucd-check` | Regenerates `src/unicode/tables.zig` in memory and exits with status 1, naming the first differing line, when the committed file differs. |
| `release-check` | Reports unmet obligations and returns a nonzero status. |

Each command uses this repository, independent of the caller's current directory.
The exceptions are `attest-verify`, `source-archive`, and `provenance`, whose path arguments resolve from the current directory.
The Windows wrapper uses an installed Node executable, then Bun as a fallback.
The installer does not replace an existing compiler directory or weaken PowerShell policy.

## Run a gate

1. Run `node tools/fairpane.mjs check`.
2. Select a gate from `engineering/gates.json`.
3. Run `node tools/fairpane.mjs run <gate-id>`.
4. Read the reported receipt and its log.
5. Run `node tools/fairpane.mjs evidence-check <receipt-path>`.

A failed gate retains its failure result.
A missing compiler does not count as successful execution.
Cross-compilation gates compile code without target execution.
They cannot establish native target support.

Gate receipts go to `out/evidence` by default.
`--evidence-dir` writes the receipt and log under another directory inside `out/evidence` or `engineering/evidence`.
A receipt under `engineering/evidence` keeps its log in the same tracked directory.
A clean checkout of the receipt's source commit can therefore check it.

## Record a command

1. Select a log path under `out/evidence` or `engineering/evidence`.
2. Run `node tools/fairpane.mjs record <log> <executable> [arguments...]`.
3. Read the appended `COMMAND` line, the output, and the `RESULT` line.

The command resolves a bare executable name through `PATH` only and records the absolute path.
It never searches the working directory for an executable.
A relative executable path resolves from the repository root.
The `RESULT` line keeps the working directory, UTC start time, exit status, signal, watchdog outcome, and environment overrides.
A command that cannot write its log or capture its output returns a failed result instead of an exception.
A short write to the log is a failed log write, not a truncated success.
The `record` command exits with status 1 when the recorded command fails.

## Evidence boundary

Local receipts contain actual command records and output hashes.
Source and policy digests include relative filenames and content.
A source change invalidates earlier current-source checks.
The inventory rejects traversal and symlinks but does not create an operating-system sandbox.

Task state, handoffs, and evidence sit outside the source inventory.
Those mutable records cannot serve as independent acceptance authority.
The graph check only checks the structure of evidence and review references.
It does not validate signatures or prove that a reviewer is independent.

An unsigned receipt is forgeable by anyone who can write repository files.
A passing local check is not a trusted attestation.
ADR 0002 records the protected acceptance boundary that replaces it.

## Verify a signed result

1. Run a verifier copy that the candidate workspace cannot modify.
2. Obtain the trust policy from protected storage outside the candidate repository.
3. Run `node tools/fairpane.mjs attest-verify --repository <candidate> --trust-policy <path> --candidate <commit> <envelope>`.
4. Read the verified record, or the rejection code on exit status 1.

The verifier in `tools/attest.mjs` imports nothing from the local receipt code.
It accepts only an Ed25519 signature from a key in the trust policy over the exact payload bytes.
It requires a canonical payload, the expected commit and tree, the trust policy's acceptance-policy digest, and consistent nonzero counts.
It reads the candidate identity from Git objects, never from the working tree.
Its Git calls ignore replace refs and inherited `GIT_*` variables, and they find `git` through `PATH` only.
The `--repository` path must be the top-level directory of a Git work tree, because Git searches parent directories from any other path.
The candidate must be a full 40-hex commit ID of a commit object, because a ref, a tag, or an abbreviated ID is a mutable pointer.
A candidate ID under which no object exists, or under which a readable object of another type exists, is `unknown-candidate`, as ADR 0002 states.
An unreadable repository, an object under the candidate's ID that exists but cannot be read, an unreadable tree, a Git spawn failure, a signal, or a timeout is a tool error, distinct from a rejection.
A protected runner whose account does not own the candidate checkout lists that path in `safe.directory` in its own Git configuration.
A trust policy fails as `unprotected-policy` when its path, or any directory on the way to it, resolves inside the candidate repository or its Git directory, because a workspace writer can edit it.
That location check is a guard, not a security boundary; operating-system permissions on a separate runner supply the boundary.
It compares real paths, so it cannot detect a UNC or administrative-share alias of the candidate.
A verifier that runs from inside the candidate, or from any work tree of the candidate repository, reports `verified-advisory` with exit status 3, and its result is advisory only.
The verifier finds those work trees through every `.git` entry on its own path.
It does not detect a layout that Git finds only through `GIT_DIR` or `core.worktree`, or a bare Git directory on that path, and a broken `.git` entry on that path is a tool error.
`node tools/attest.test.mjs` runs the verifier's own tests without the rest of the controller.

A verified result authenticates one record and is not release qualification.
No protected runner, trust policy, or signed result set exists yet, so `release-check` still fails closed.
A metadata edit alone cannot enable release success.

## Gate safety

Child commands receive argument arrays without shell interpolation.
Each child writes its output to a file in a new private temporary directory, which the controller copies into the log and removes.
If the removal fails, the command record carries that error, and the command fails.
A watchdog terminates a hung process group on POSIX or a process tree on Windows.
On Windows, it stops the tree with `taskkill.exe`, which the controller starts by its full path under `%SystemRoot%\System32`, so a program of that name in the working directory cannot replace it.
The controller resolves that path before it starts the command, and an unset, empty, or relative `SystemRoot` fails the command before it starts.
The corpus commands' Git watchdog and the Windows compiler installer, which starts Windows PowerShell, use the same system-directory path.
Before it stops a timed-out command, it writes a timeout section to the log.
The section lists the command and each live descendant as a `PROCESS` line with the process ID, the parent process ID, and the command line.
On Windows, the list comes from `Win32_Process` through Windows PowerShell, which the controller starts by its full path under `%SystemRoot%\System32`.
On Linux, it comes from `/proc/<pid>/stat` and `/proc/<pid>/cmdline`, and the command line is an argument array.
The listing has a 10-second limit.
If it fails, the section names the reason, and the watchdog still stops the command, which still fails with `timed_out: true`.
The section precedes the command's output in the log, because the output is copied in when the command ends.
The caller still needs operating-system isolation and resource quotas for hostile inputs.
The tool does not enforce disk quotas or a network policy.
Zig and C ABI gates set `ZIG_GLOBAL_CACHE_DIR` to `.zig-cache/global` inside the repository.
Each command record lists that override in `environment_overrides`.
The gates never use a `zig` executable from `PATH`.

Writable-path declarations in task files are workflow contracts.
The local controller does not enforce every write that an OMP worker makes.
Independent patch review and isolated workers enforce the integration boundary.
A protected runner supplies the separate release boundary.

## Run the gates in GitHub Actions

`.github/workflows/gates.yml` runs the gates on pushes to `master`, on pull requests that target `master`, and on manual dispatch.
The Windows job runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `zig-build`, and `c-abi`.
The Linux job runs `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, and the three cross-compilation gates.
Each job installs the locked compiler with `install-zig` and uploads `out/evidence` as an artifact, including after a failure.
Those receipts remain unsigned local integrity records, and a hosted runner is not a protected release runner.

A pull request runs its own copy of the workflow, the checker, and the controller.
A green check on a pull request therefore enforces nothing independently of that pull request.
`install-zig` also accepts an existing compiler directory after only a version check, so a pull request that adds one controls the compiler.
`install-rust` also accepts an existing toolchain directory after only a version check.

`tools/workflow-check.mjs` checks the workflow policy without a YAML package.
It accepts only printable ASCII text with LF or CRLF line ends, because YAML parsers also break lines at NEL, LS, and PS.
It parses only block mappings, block sequences, single-line scalars, single-line flow sequences, block scalars, and comments.
It rejects anchors, aliases, tags, flow mappings, multi-line plain scalars, duplicate keys, and every other construct with a line number.
It also rejects a block scalar whose leading blank line has more spaces than its first content line, as libyaml does.

`workflowProblems` checks every workflow file as follows.

- A `uses:` reference needs a full 40-hex commit SHA and a version comment.
- The only accepted triggers are `push`, `pull_request`, and `workflow_dispatch`.
- A workflow or job permission other than `contents: read` is a problem, and the problem names the exact grants in source order.
- Every `continue-on-error` key and every `secrets` mapping is a problem.
- A checkout needs `persist-credentials: false`.
- Every `${{ }}` expression and every `if:` value is an expression.
  An expression may call only `always` and `format`, and it may read only `github.event_name`, `github.run_id`, `github.event.pull_request.number`, and step outputs.
- A `run:` value may contain no `${{ }}` expression, so no expression reaches a shell.
  A run step passes a value through `env:` instead.

`gateWorkflowProblems` checks the Gates workflow against allowlists.

- The workflow may set only `name`, `on`, `permissions`, `concurrency`, and `jobs`.
- The `push` and `pull_request` triggers must each set exactly `branches: [master]` and no other key, such as `types`, `paths`, `paths-ignore`, `tags`, or `branches-ignore`.
  `workflow_dispatch` must have no value.
  No trigger filter can therefore narrow the runs, and each problem names the trigger and the key.
- A job may set only `name`, `runs-on`, `timeout-minutes`, and `steps`.
- A run step may set only `name` and `run`.
  Its command must be `node tools/fairpane.mjs install-zig` or `node tools/fairpane.mjs run <gate>`.
- An action step may set only `name`, `uses`, and `with`.
  An `actions/upload-artifact` step must also set `if: ${{ always() }}`, `path: out/evidence/`, and `if-no-files-found: error`, and no other step may set `if:`.
- The only accepted actions are `actions/checkout` with the input `persist-credentials`, `actions/setup-node` with `node-version`, and `actions/upload-artifact` with `name`, `path`, and `if-no-files-found`.
- The `linux` job must run exactly `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `cross-windows-x86_64`, `cross-linux-aarch64`, and `cross-macos-aarch64`, in that order.

No default shell, environment variable, working directory, container, or other action can therefore change what a gate step runs.
`tools/workflow-check.test.mjs` fixes the Gates step order, runner labels, Windows gate list, and concurrency expressions, and it checks the Linux gate list too.
It also checks every workflow file against its reviewed problem list, and `node tools/fairpane.mjs test` runs its cases.
The `pages.yml` list names the deploy job's `pages: write` and `id-token: write` grants, so any other grant fails it.

To update a pinned action, follow these steps.

1. Look up the release tag through `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
2. Resolve the tag to its commit through `https://api.github.com/repos/<owner>/<repo>/git/ref/tags/<tag>`.
3. Dereference an annotated tag object through `git/tags/<sha>` until the object type is `commit`.
4. Record the lookups with `node tools/fairpane.mjs record` under the task's evidence directory.
5. Replace the SHA and the version tag in `REVIEWED_ACTIONS` in `tools/workflow-check.mjs`, because the checker accepts only reviewed action commits.
6. Replace the SHA and the version comment in every workflow that uses the action.
7. Run `actionlint` at a pinned release with a verified digest.
8. Run `node tools/fairpane.mjs test`.

The checker binds each action to a reviewed commit because GitHub also fetches a commit from any fork of the action's repository.

## Generate the ABI declarations

`tools/abi.mjs` reads `api/fairpane.schema.json` and generates `include/fairpane.h`, `src/abi_generated.zig`, and `tests/c/abi_layout.h`.
It validates the schema and `api/failure-scenarios.json` before it writes or compares any file.
Generation reads only arrays for ordered collections, so the output never depends on object key order.
`api/README.md` describes the schema, the value kinds, and the failure scenarios.

1. Edit `api/fairpane.schema.json`.
2. Run `node tools/fairpane.mjs abi-generate`.
3. Run `node tools/fairpane.mjs abi-check`.
4. Read the reported files and lines on exit status 1.

`abi-check` compares the committed files byte for byte and names each stale file with its first differing line.
`tools/abi.test.mjs` holds the FP-0021 cases, and `node tools/fairpane.mjs test` runs them.
`node tools/abi.test.mjs` runs those cases without the rest of the controller.

`abi-exports` reads the archive symbol table of a static library in the GNU, System V, COFF, or BSD layout.
The `c-abi` gate runs it on the library that it builds, before it compiles the C smoke test.

## Produce release records

ADR 0009 defines the release records and the owner decisions that a public release still needs.
These commands write local records only, and none of them signs, publishes, or uploads anything.

1. Select a full 40-hex commit ID.
2. Run `node tools/fairpane.mjs source-archive <commit> <output-dir>` with an output directory outside the repository.
3. Run `node tools/fairpane.mjs reproduce-check <commit>`.
4. Check the tar's SHA-256 against its manifest.
5. Extract the tar into a new directory.
6. Remove every inherited `ZIG_*` variable.
7. Set `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` to fresh directories inside the new directory.
8. Run `zig build -Doptimize=ReleaseSafe --prefix zig-out` in the new directory.
9. Run `node tools/fairpane.mjs provenance <commit> <artifact>...` and save its standard output.

`source-archive` takes the tar from `git archive --format=tar --prefix=fairpane-<commit>/ <commit>` through the verifier's hardened Git calls.
It also pins `core.autocrlf`, `core.eol`, and `tar.umask`, so user configuration cannot change the bytes.
The bytes still depend on the Git implementation, so the manifest records `git_version`, the first line of `git --version`.
The manifest lists every regular file and symbolic link of the commit's tree with its path, mode, size, and SHA-256, sorted by path bytes.
It records the commit, the tree, the Git version, and the tar's SHA-256 in the format `fairpane-source-manifest`, version 1.
The command parses the tar and fails before any write when the tar does not hold exactly the manifest's files, as an `export-ignore` or `export-subst` attribute would cause.
An abbreviated ID, a ref name, a missing commit, and an output directory inside the repository or its Git directory also fail before any write.

`provenance` reads the Zig lock from the commit's tree, not from the working tree, and names the host platform's compiler archive digest.
Each subject is an artifact's file name with its SHA-256, so two artifacts with the same file name fail.
The statement names the builder ID `https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#unsigned-local-builder-1`, a URI as SLSA requires.
Its toolchain fields come from the commit's lock and from the host that runs `provenance`, not from an observation of the build.
It is a record format for a later protected runner, not an attestation, and no verifier may trust that builder.

`reproduce-check` extracts the source archive into two fresh work trees and builds each with the commit's locked compiler.
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` name fresh caches inside each tree, and no other inherited `ZIG_*` variable reaches the build.
It compares the SHA-256 of every file under each tree's `zig-out`.
It reports `reproducible` with exit status 0, `different` with the differing paths, or `error` for a failed extraction, a failed build, or an empty installation.
The report's `build_type_command` is the canonical command of build type 1, and each entry of `builds` keeps the exact arguments of its tree.
It removes both work trees afterward, and a removal failure appears in the report's `removal` field and makes the exit status 1.
The two trees have different paths, so an output that embeds its build path reports `different`.
`tools/release.test.mjs` holds the FP-0027 cases, and `node tools/fairpane.mjs test` runs them.
`node tools/release.test.mjs` runs those cases without the rest of the controller.
They run `reproduce-check` with a stand-in compiler that runs the fixture commit's own `build.mjs`, so they need no Zig installation.

`build.zig` installs the static library under the library rules of ADR 0009.
A mode other than Debug builds the object without debug information, and `zig ar` writes the library in deterministic mode with one member named by the object's base name.
`zig build library-test`, which `zig build test` runs, holds FP-0066 cases 1, 2, 4, and 5.
It builds a ReleaseSafe library from each of two copies of `src` in different directories, and a Debug library from `src`.
`tools/zig/library_check.zig` then compares the two ReleaseSafe libraries byte for byte, searches one for the paths of its build directory and of the compiler installation, and lists its members.
It also confirms that the Debug library's object names the absolute path of `src`.
The search ignores ASCII letter case and treats `/` and `\` as the same byte.
FP-0066 case 3 is `node tools/fairpane.mjs abi-exports` on the installed ReleaseSafe library.

## Generate the Unicode property tables

`tools/ucd.mjs` reads the eight Unicode 18.0.0 files under `src/unicode/ucd/` and generates `src/unicode/tables.zig`.
It applies each `# @missing:` line in file order and then each data line, so a later line overrides earlier defaults for its range.
It resolves every value, including a long `@missing` value such as `Left_To_Right`, through `PropertyValueAliases.txt`.
A `ScriptExtensions.txt` value of `<script>` means that the code point's Script value is its Script_Extensions value.
An unknown value, a reversed range, a code point above `10FFFF`, or a data line without `;` fails generation with the file and line number.
The generated header lists each input's path, byte size, and SHA-256, and it reproduces `src/unicode/ucd/license.txt`.

1. Run `node tools/fairpane.mjs corpus-fetch unicode` to replace the inputs from the pinned sources.
2. Run `node tools/fairpane.mjs ucd-generate`.
3. Run `node tools/fairpane.mjs ucd-check`.
4. Read the reported line on exit status 1.

`tools/ucd.test.mjs` holds FP-0013 cases 1 through 4.
`src/unicode/reference_test.zig` holds the Zig part of case 3, which parses the embedded files independently and compares every code point.
The reference parser marks each code point that a file assigns, and it fails when any code point stays unassigned.

## Import a file-set corpus

`tools/fileset.mjs` freezes the sources of the `unicode` and `opentype-fixtures` corpora.
A change to those sources needs a frozen task contract, so `corpus-repin` refuses a file-set corpus.

1. Run `node tools/fairpane.mjs corpus-fetch <id>`.
2. For `opentype-fixtures`, install fontTools as `engineering/dependencies.json` describes.
3. For `opentype-fixtures`, run `node tools/fairpane.mjs corpus-derive opentype-fixtures`.
4. Run `node tools/fairpane.mjs corpus-applicability <id>`.
5. Run `node tools/fairpane.mjs corpus-verify <id>`.

Install fontTools with these steps.

1. Download the wheel that `engineering/dependencies.json` names into `.tools/downloads/`, under its file name from the wheel URL.
2. Check its SHA-256 against the recorded digest.
3. Run `python -m venv .tools/python/fonttools-4.66.1`.
4. Run `.tools/python/fonttools-4.66.1/Scripts/python -m pip install --no-index --no-deps` with the verified wheel.

Keep the wheel in `.tools/downloads/`, because every fontTools run checks the installation against it.
That check requires the wheel's SHA-256 to equal `engineering/dependencies.json`.
It requires every file that the wheel's `RECORD` lists to be installed with that SHA-256 and size.
It also requires every file in the installed packages to appear in `RECORD`, except bytecode under `__pycache__`, which it does not verify.
Each run then uses the staging directory as its working directory, sets `PYTHONSAFEPATH=1`, and removes every other `PYTHON*` variable.
A probe confirms the fontTools version, the safe-path flag, and that the verified package is the one imported.
fontTools runs without an operating-system sandbox, on inputs pinned by Git blob or SHA-256 only.

`corpus-derive` runs only the frozen argument vector of each derived file and never changes an existing fixture.
A different output fails the command, because the derivation is not reproducible.

Write or check the font expectation files with these steps.

1. Install fontTools as above.
2. Run `node tools/fairpane.mjs font-expectations --check` to rerun `tools/fonts/font_expectations.py` for every fixture font and compare its output with the committed files.
3. Run `node tools/fairpane.mjs font-expectations` to replace each differing expectation file.

The command copies the script, the seeds, and the fonts into a fresh staging directory and runs the script there, so the run itself changes nothing in the repository.
Do not run `font_expectations.py` directly, because a direct run keeps the inherited `PYTHON*` environment and the repository as its working directory.
The script's own usage line, which runs it from the repository root, predates this procedure.
It stays unchanged, because each expectation file records the script's SHA-256 and case 12 compares that digest with the committed script.
`tools/fileset.test.mjs` holds FP-0013 cases 41 through 49 and 53 through 55, which read `file://` or in-memory fixture sources and never use the network.

## Profile the Zig tests

`tools/zig/test_profile_runner.zig` is a test runner that prints the wall time of each test.
Before each test, it prepares `std.testing` as the default runner does: a fresh `SafeAllocator` over the page allocator with the same canary and write-after-free check, and a fresh `Io.Threaded`.
A failed test, a leak, or an error log fails the run.
It is not part of `zig build test`, which keeps the default runner.

1. Run `node tools/fairpane.mjs record --env ZIG_GLOBAL_CACHE_DIR=<repository>\.zig-cache\global <log> <locked zig> test -ODebug --test-runner tools/zig/test_profile_runner.zig --cache-dir out/test-profile src/root.zig` from the repository root.
2. Run the same command with `--dep fairpane -Mroot=tests/text/root.zig -Mfairpane=src/root.zig` in place of `src/root.zig` to profile the text tests.
3. Read the `TEST` line of each test, the `RANK` lines of the 25 slowest tests, and the `TOTAL` line.
4. Run `zig build test --summary all` with a fresh `--cache-dir` for the duration of every other step.

## Extend the controller

1. Add failing tests for the new gate behavior.
2. Add the gate implementation without a shell-string interface.
3. Preserve failed execution records and input identities.
4. Add the gate to the registry through independent review.
5. Document the exact qualification scope.
6. Run the complete controller test suite.

The first gates qualify only bootstrap behavior.
Feature tasks require feature-specific tests before acceptance.
A build gate never substitutes for the task's observable behavior.
