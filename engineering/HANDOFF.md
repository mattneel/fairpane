# Current handoff

## Actual state

Tasks `FP-0001`, `FP-0004`, and `FP-0028` are accepted.
Task `FP-0003` is active again after `fairpane-review` and `fairpane-spec` rejected commit `ce34ffc`.
Contract revision 1 requires an explicit WPT denominator from the wpt.fyi manifest bound to the pinned tree.
An isolated `fairpane-core` worker, `FP0003Rework`, implements that revision.
Task `FP-0005` has a worker patch with 38 passing Zig tests that awaits integration and review.
Task `FP-0002` is active in the root session, with an uncommitted verifier draft and contract revision 1.
The candidate Zig library contains a capability probe, a lossless UTF-16 view, and checked generational handles.
No renderer, JavaScript engine, or native browser window exists yet.

The repository is public at <https://github.com/mattneel/fairpane>.
The documentation book is live at <https://mattneel.github.io/fairpane/>.
The `Pages` workflow rebuilds and deploys it on every push to `master`.

The browser is the engine's first embedder.
The Zig engine owns web behavior, the Rust wrapper owns safe integration, and the Rust shell owns the application.
The canonical wrapper crates `fairpane-sys` and `fairpane` stay free of third-party dependencies.
The shell welcomes qualified crates, and GPUI hosts the chrome that Fairpane renders as a trusted document.
ADR 0004 records the layers, the boundary, and the process arrangement.
ADR 0005 records one extension contract with Rhai and JavaScript as equal clients.
ADR 0006 makes every language SDK power a first-party integration and a reference extension.
ADR 0007 makes the frontend language independent of the renderer and reserves the surface interface.

## Next action

1. Obtain an independent review of the policy and plan changes for ADRs 0004 through 0007.
2. Integrate the `FP-0005` worker patch, run its gates, and request `fairpane-review`.
3. Finish `FP-0002` and request its review.
4. Integrate the `FP0003Rework` patch, then request both FP-0003 reviewers again.
5. Start the ready tasks `FP-0006`, `FP-0031`, and `FP-0033`.
6. Freeze the `FP-0029` Rust wrapper contract after `FP-0021` is accepted.

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
The owner's extension memo made Rhai and JavaScript equal clients of one extension contract.
The owner answered "YES" to two required capability families, `extensions` and `webextensions-compat`.
The owner's SDK memo made a first-party integration and a reference extension mandatory for every supported language SDK.
The owner's frontend memo made every SDK expose document and custom graphics frontends over one renderer.
`engineering/evidence/extensions/` and `engineering/evidence/frontends/` preserve those memos verbatim.
The outbound license remains open.
The Git history uses the owner's configured identity.
