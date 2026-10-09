# Current handoff

## Actual state

Task `FP-0001` is accepted.
Review 3 accepted implementation commit `05d2d42`, and every gate passed again on integration head `97c01b9`.
The candidate Zig library still contains only a capability probe and a lossless UTF-16 view.
No renderer, JavaScript engine, or native browser window exists yet.

The repository is public at <https://github.com/mattneel/fairpane>.
The documentation book is live at <https://mattneel.github.io/fairpane/>.
The `Pages` workflow rebuilds and deploys it on every push to `master`.

Tasks `FP-0002`, `FP-0003`, `FP-0004`, and `FP-0028` are ready.
Each has a frozen contract in `engineering/evidence/<task>/CONTRACT.md`.

## Next action

1. Implement `FP-0028` in the root session, because later controller work builds on its record format.
2. Implement `FP-0002` in the root session after `FP-0028`.
3. Delegate `FP-0004` to an isolated `fairpane-core` worker.
4. Delegate `FP-0003` to an isolated `fairpane-core` worker.
5. Review each worker patch before it reaches `master`.

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
- Command records lack the working directory and start time.
  Task `FP-0028` owns that and the other controller findings from review 2.

## Owner decisions

The owner made the repository public at <https://github.com/mattneel/fairpane> on October 8, 2026.
The owner authorized continuous commits and pushes to `master` on `origin`.
`docs/GIT_OPERATIONS.md` records the Git and GitHub rules.
The owner requested public documentation as an mdBook site on GitHub Pages, deployed by GitHub Actions.
The outbound license remains open.
The Git history uses the owner's configured identity.
