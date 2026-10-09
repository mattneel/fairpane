# Current handoff

## Actual state

Task `FP-0001` is accepted.
Tasks `FP-0004` and `FP-0028` are implemented and await `fairpane-review`.
Task `FP-0003` is in progress in an isolated `fairpane-core` worker.
Task `FP-0002` is in progress in the root session.
The candidate Zig library contains a capability probe, a lossless UTF-16 view, and checked generational handles.
No renderer, JavaScript engine, or native browser window exists yet.

The repository is public at <https://github.com/mattneel/fairpane>.
The documentation book is live at <https://mattneel.github.io/fairpane/>.
The `Pages` workflow rebuilds and deploys it on every push to `master`.

The browser is the engine's first embedder.
Its shell is written in the first-party wrapper language and uses only the public embedding contract.
`engineering/decisions/0004-first-party-wrapper-language.md` proposes a ranked language shortlist and awaits the owner's selection.

## Next action

1. Record the owner's wrapper-language selection in ADR 0004 and freeze the `FP-0029` contract.
2. Record the `fairpane-review` verdicts for `FP-0004` and `FP-0028`.
3. Finish `FP-0002` and request its review.
4. Review and integrate the `FP-0003` worker patch, then obtain `fairpane-review` and `fairpane-spec` verdicts.

```text
node tools/fairpane.mjs check
node tools/fairpane.mjs test
node tools/fairpane.mjs next
```

## Environment facts

- A different compiler, `0.17.0-dev.2453+zigpp.35608841b`, is first on `PATH`.
  Gates use only the locked compiler under `.tools`.
- Isolated OMP worktrees do not contain `.tools`.
  Workers run the locked compiler at `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
- Workers base on commit `1eae1f0` or later, which carries the current founding policy.
- Windows PowerShell 5.1 inherits a PowerShell 7 module path on this host.
  `scripts/Get-Zig.ps1` therefore hashes through .NET instead of `Get-FileHash`.
- The OMP shell's builtin `sha256sum` mistranslates CRLF in check mode.
  Use `node tools/fairpane.mjs record` with GNU `sha256sum` for recorded checks.
- The owner's OMP configuration uses approval mode `yolo`.

## Unresolved items

- The protected `zig-test` gate prints no test count.
  An acceptance-policy change would need separate independent approval.
- Local receipts are unsigned.
  Task `FP-0002` owns the protected attestation boundary.

## Owner decisions

The owner made the repository public at <https://github.com/mattneel/fairpane> on October 8, 2026.
The owner authorized continuous commits and pushes to `master` on `origin`.
`docs/GIT_OPERATIONS.md` records the Git and GitHub rules.
The owner requested public documentation as an mdBook site on GitHub Pages, deployed by GitHub Actions.
The owner made the browser the engine's first embedder, written in a first-party wrapper language.
The first-party wrapper language remains open.
Task `FP-0029` needs the owner's selection from a recorded comparison, and `FP-0017` waits on `FP-0029`.
The outbound license remains open.
The Git history uses the owner's configured identity.
