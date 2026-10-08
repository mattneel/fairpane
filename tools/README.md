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
| `run <gate-id>` | Executes a gate without a command shell and writes its receipt. |
| `evidence-check <path>` | Checks a passed receipt against current inputs and output artifacts. |
| `release-check` | Reports unmet obligations and returns a nonzero status. |

Each command uses this repository, independent of the caller's current directory.
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
Task `FP-0002` defines and tests the protected acceptance boundary.
The release command has no success path until that implementation qualifies.
A metadata edit alone cannot enable release success.

## Gate safety

Child commands receive argument arrays without shell interpolation.
A watchdog terminates a hung process group on POSIX or a process tree on Windows.
The caller still needs operating-system isolation and resource quotas for hostile inputs.
The tool does not enforce disk quotas or a network policy.

Writable-path declarations in task files are workflow contracts.
The local controller does not enforce every write that an OMP worker makes.
Independent patch review and isolated workers enforce the integration boundary.
A protected runner supplies the separate release boundary.

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
