# Start here

## What this archive does

This archive gives OMP a durable project contract and a concrete first work queue.
It does not install an agent, reserve a name, publish code, or start unattended work.
No credential belongs in this repository.

The easiest entry point is an existing OMP installation.
OMP supports root `AGENTS.md` files and project prompt templates. [S01, S02]

## Launch the agent

1. Extract the archive into `C:\src\fairpane`.
2. Open PowerShell in that directory.
3. Run `omp`.
4. Enter `/fairpane-start`.

## Recover a missing prompt

1. Open `AGENT_LAUNCH.md`.
2. Paste its assignment into the OMP composer.
3. Ask OMP to check the loaded context through `/extensions`.

## Optional local preparation

The following commands use PowerShell.
The compiler installer changes only `.tools` under this repository.
It checks the downloaded archive against the lock before extraction.
It does not update the global PATH or install a compiler globally.

```powershell
Set-Location C:\src\fairpane
.\scripts\Get-Zig.ps1
.\scripts\fp.ps1 doctor
.\scripts\fp.ps1 check
.\scripts\fp.ps1 test
.\scripts\fp.ps1 run zig-test
.\scripts\fp.ps1 next
omp
```

`Get-Zig.ps1` requires PowerShell 5.1 or newer on Windows.
`fp.ps1` uses Node 22 or newer when available, then Bun as a fallback.
The development controller contains no package dependencies.
The agent can start before these tools exist and resolve the local setup as its first task.

PowerShell can block unsigned local scripts under an existing execution policy.
This archive does not change that policy.
An agent can use an approved shell or the equivalent commands instead.

## Equivalent controller commands

```text
node tools/fairpane.mjs doctor
node tools/fairpane.mjs check
node tools/fairpane.mjs test
node tools/fairpane.mjs status
node tools/fairpane.mjs next
node tools/fairpane.mjs run zig-test
node tools/fairpane.mjs release-check
```

Bun can run the same entry point with `bun tools/fairpane.mjs`.
Node execution is the locally tested path for this bootstrap.
`release-check` returns a nonzero exit status for this archive by design.

## Git setup

A new directory has no Git history.
OMP's isolated tasks require a supported Git checkout. [S03]
The first task establishes the checkout and records a baseline.

The agent must not invent the owner's identity.
An absent Git identity blocks the initial commit, not independent implementation work.
The agent can work sequentially until the owner supplies an identity.
No remote repository or automatic push is authorized by this bootstrap.

## Session continuation

`engineering/state.json` records task status.
`engineering/HANDOFF.md` records the next executable action.
Evidence receipts live under `out/evidence` until reviewed records move into the durable evidence archive.

A new session starts with `/fairpane-resume`.
A handoff is a continuation record, not a completion claim.
The agent must not stop after a plan when an authorized implementation task remains available.

## Source references

See `docs/SOURCES.md` for [S01], [S02], and [S03].
