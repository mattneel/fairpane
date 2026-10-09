# Current handoff

## Actual state

Tasks `FP-0001`, `FP-0004`, and `FP-0028` are accepted.
Task `FP-0003` is implemented and integrated, and it awaits `fairpane-review` and `fairpane-spec` verdicts.
Its WPT applicability counts are blocked on a pinned Python environment that provides PyYAML 6.0.1.
Task `FP-0002` is in progress in the root session, with a draft verifier at `out/wip/attest.mjs`.
The candidate Zig library contains a capability probe, a lossless UTF-16 view, and checked generational handles.
No renderer, JavaScript engine, or native browser window exists yet.

The repository is public at <https://github.com/mattneel/fairpane>.
The documentation book is live at <https://mattneel.github.io/fairpane/>.
The `Pages` workflow rebuilds and deploys it on every push to `master`.

The browser is the engine's first embedder.
The Zig engine owns web behavior, the Rust wrapper owns safe integration, and the Rust shell owns the application.
The canonical wrapper crates `fairpane-sys` and `fairpane` stay free of third-party dependencies.
The shell welcomes qualified crates, and GPUI hosts the chrome that Fairpane renders as a trusted document.
`engineering/decisions/0004-first-party-wrapper-language.md` records the layers, the boundary, and the process arrangement.

## Next action

1. Obtain `fairpane-review` and `fairpane-spec` verdicts on `FP-0003`, then apply the `specs/corpora.json` pins in a separate commit.
2. Create a task that provisions the pinned Python environment for the WPT manifest.
3. Finish `FP-0002` and request its review.
4. Start the ready tasks `FP-0005`, `FP-0006`, `FP-0031`, and `FP-0033`.
5. Freeze the `FP-0029` Rust wrapper contract after `FP-0021` is accepted.

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
On October 9, 2026, the owner selected Rust as that language, as ADR 0004 records.
The owner then supplied a design memo that limits third-party crates to the browser application.
The owner selected GPUI to host engine-rendered chrome.
`engineering/evidence/wrapper-language/` preserves the memo verbatim and the recorded answers.
The outbound license remains open.
The Git history uses the owner's configured identity.
