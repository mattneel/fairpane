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
| `run <gate-id> [--evidence-dir <dir>]` | Executes a gate without a command shell and writes its receipt. |
| `record [--cwd <dir>] [--env NAME=VALUE]... <log> <executable> [arguments...]` | Runs one command without a shell and appends its output and result to an evidence log. |
| `evidence-check <path>` | Checks a passed receipt against current inputs and output artifacts. |
| `corpus-fetch <id>` | Fetches the pinned corpus commit into a fresh snapshot and writes its record. |
| `corpus-repin <id>` | Moves a corpus snapshot to the upstream branch head and writes its record. |
| `corpus-applicability <id>` | Counts discovered tests in a local snapshot without network access or corpus code. |
| `corpus-verify <id>` | Recomputes a local snapshot and compares its records and `specs/corpora.json` pins. |
| `attest-verify --repository <path> --trust-policy <path> --candidate <commit> <envelope>` | Verifies a signed result against protected trust input and a full commit ID in a candidate repository. |
| `release-check` | Reports unmet obligations and returns a nonzero status. |

Each command uses this repository, independent of the caller's current directory.
The exception is `attest-verify`, whose path arguments resolve from the current directory.
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
An unreadable repository, an unreadable tree, a Git spawn failure, a signal, or a timeout is a tool error, distinct from a rejection.
A protected runner whose account does not own the candidate checkout lists that path in `safe.directory` in its own Git configuration.
A trust policy inside the candidate repository or its Git directory fails as `unprotected-policy`, because a workspace writer can edit it.
That location check is a guard, not a security boundary; operating-system permissions on a separate runner supply the boundary.
A verifier that runs from inside the candidate reports `verified-advisory` with exit status 3, and its result is advisory only.
`node tools/attest.test.mjs` runs the verifier's own tests without the rest of the controller.

A verified result authenticates one record and is not release qualification.
No protected runner, trust policy, or signed result set exists yet, so `release-check` still fails closed.
A metadata edit alone cannot enable release success.

## Gate safety

Child commands receive argument arrays without shell interpolation.
Each child writes its output to a file in a new private temporary directory, which the controller copies into the log and removes.
If the removal fails, the command record carries that error, and the command fails.
A watchdog terminates a hung process group on POSIX or a process tree on Windows.
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
The Linux job runs `repo-check`, `controller-test`, and the three cross-compilation gates.
Each job installs the locked compiler with `install-zig` and uploads `out/evidence` as an artifact, including after a failure.
Those receipts remain unsigned local integrity records, and a hosted runner is not a protected release runner.

`tools/workflow-check.mjs` checks the workflow policy without a YAML package.
It parses only block mappings, block sequences, single-line scalars, single-line flow sequences, block scalars, and comments.
It rejects anchors, aliases, tags, flow mappings, multi-line plain scalars, duplicate keys, and every other construct with a line number.
It reports a `uses:` reference without a full 40-hex commit SHA and a version comment.
It reports a workflow or job permission other than `contents: read`, any `continue-on-error`, and a `pull_request_target` trigger.
It reports a checkout without `persist-credentials: false` and an expression that reads a secret or the workflow token.
`tools/workflow-check.test.mjs` holds its cases, and `node tools/fairpane.mjs test` runs them.

To update a pinned action, follow these steps.

1. Look up the release tag through `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
2. Resolve the tag to its commit through `https://api.github.com/repos/<owner>/<repo>/git/ref/tags/<tag>`.
3. Dereference an annotated tag object through `git/tags/<sha>` until the object type is `commit`.
4. Replace the SHA and the version comment in every workflow that uses the action.
5. Run `actionlint` at a pinned release with a verified digest.
6. Run `node tools/fairpane.mjs test`.

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
