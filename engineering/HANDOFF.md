# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0007`, `FP-0009`, `FP-0028`, `FP-0031`, `FP-0047`, and `FP-0053` are accepted.
`specs/corpora.json` pins Test262 at `2e0a5676` and WPT at `b60c4b34`, and `release-check` still fails closed.
The owner approved Unicode data and OFL test fonts in the repository, as `LICENSE-DECISION.md` records.
Task `FP-0033` implements contract revision 2 in commit `98fa147`, and it awaits `fairpane-review` and `fairpane-security`.
Task `FP-0051` implements contract revision 1 in commit `9b878bc`, and it awaits `fairpane-review`.
Task `FP-0021` revision 1 is active in the isolated worker `FP0021Revision`, after review 1 rejected `13372de`.
Tasks `FP-0011` (JavaScript catalogs) and `FP-0013` (Unicode data and font parsing) are active in the isolated workers `FP0011Js` and `FP0013Text`.
Tasks `FP-0052` and `FP-0054` carry review findings; `FP-0052` waits for `FP-0013`, because both change `tools/corpus.mjs`.
Tasks `FP-0055` through `FP-0063` own the remaining text obligations.
The candidate Zig library contains a capability probe, lossless owned web strings, checked generational handles, the engine and document lifecycle, a DOM node store, a generated C ABI, and the headless laboratory `fairpane-lab`.
No renderer, JavaScript engine, or native browser window exists yet.

The repository is public at <https://github.com/mattneel/fairpane>.
The documentation book is live at <https://mattneel.github.io/fairpane/>.
The `Pages` workflow deploys it, and the `Gates` workflow runs the gates on every push to `master`.

The browser is the engine's first embedder.
The Zig engine owns web behavior, the Rust wrapper owns safe integration, and the Rust shell owns the application.
The canonical wrapper crates `fairpane-sys` and `fairpane` stay free of third-party dependencies.
The shell welcomes qualified crates, and GPUI hosts the chrome that Fairpane renders as a trusted document.
ADR 0004 records the layers, the boundary, and the process arrangement.
ADR 0005 records one extension contract with JavaScript and every officially supported language SDK as equal clients.
ADR 0006 makes every language SDK power a first-party integration and a reference extension.
ADR 0007 makes the frontend language independent of the renderer and reserves the surface interface.

## Next action

1. Record the review verdicts of `FP-0033` and `FP-0051`, and fix any finding.
2. Integrate the `FP-0021` revision, `FP-0011`, and `FP-0013` worker patches, run their gates, and request reviews.
3. Apply the `unicode` and `opentype-fixtures` pins in a separate protected commit after the FP-0013 reviews.
4. Draft and freeze contracts for the ready tasks `FP-0008` (HTML tokenizer), `FP-0014` (CSS syntax and cascade), `FP-0027`, and `FP-0054`, and start them.
5. Start `FP-0050` after the `FP-0021` revision lands, through the schema and the generator.
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
The owner's extension memo proposed one extension contract, and the owner later withdrew Rhai extensions: "We can just polyglot the whole way down."
The owner decided that TypeScript extensions run on Fairpane's own JavaScript runtime.
The owner made the `extensions` family and compatibility with existing browser extensions release-blocking.
The owner's SDK memo made a first-party integration and a reference extension mandatory for every supported language SDK.
The owner's frontend memo made every SDK expose document and custom graphics frontends over one renderer.
`engineering/evidence/extensions/` and `engineering/evidence/frontends/` preserve those memos and answers verbatim.
The outbound license remains open.
The Git history uses the owner's configured identity.
