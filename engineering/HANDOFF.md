# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0009`, `FP-0013`, `FP-0021`, `FP-0027`, `FP-0028`, `FP-0031`, `FP-0033`, `FP-0047`, `FP-0050`, `FP-0051`, `FP-0053`, and `FP-0054` are accepted; the `FP-0050` acceptance record lands with its reproduction log.
`specs/corpora.json` pins Test262 at `2e0a5676`, WPT at `b60c4b34`, Unicode 18.0.0, and the OpenType fixtures, and `release-check` still fails closed.
The owner approved Unicode data, OFL test fonts, and the WHATWG `entities.json` in the repository, as `LICENSE-DECISION.md` records.

| Task | State | Next step |
| --- | --- | --- |
| `FP-0011` JavaScript catalogs | Revision 1 in `60c0c90`; measurements rerun at that commit and ADR 0008 rewritten in `a1b2d1c`. `reference` stays the default representation. | Record the verdict of `fairpane-review` worker `FP0011R1Review`. |
| `FP-0014` CSS syntax and cascade | Implemented in `ef8ad1c`, with evidence and the named-color check in `639ec81`. | Record the verdict of `fairpane-review` worker `FP0014Review`. |
| `FP-0029` Rust wrapper | Contract and task split being drafted by `FP0029Contract`. | Freeze the first task, then make its protected toolchain and policy changes in separate `policy:` commits. |
| `FP-0064` tokenizer states | Contract being drafted by `FP0064Contract`. | Freeze it and dispatch `fairpane-core`. |

Tasks `FP-0064` through `FP-0078` hold the deferred tokenizer states, encoding sniffing, path-independent release builds, the review findings of `FP-0013`, `FP-0033`, `FP-0051`, and `FP-0054`, the CSS obligations, binary notices, and html5lib-tests.
Tasks `FP-0055` through `FP-0063` own the remaining text obligations.
The candidate Zig library contains a capability probe, lossless owned web strings, checked generational handles, the engine and document lifecycle, a DOM node store with attributes, a generated C ABI, the headless laboratory `fairpane-lab`, JavaScript value and heap catalogs, Unicode property lookup, an OpenType parser, a resumable HTML tokenizer, and CSS syntax, selectors, cascade, and computed values.
No renderer, JavaScript interpreter, tree constructor, or native browser window exists yet.

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

1. Integrate each worker patch as it arrives, run the gates with `HEAD` and status records before and after, and request review.
   Worker patches arrive as `<Name>.patch` in the session directory; apply them with `git apply --3way` on a committed tree.
2. Record each pending review verdict, and route minor findings to the follow-up tasks.
3. Dispatch the ready follow-up tasks `FP-0052`, `FP-0076`, `FP-0067`, `FP-0066`, and `FP-0078`, and then `FP-0064` and `FP-0065` for the tokenizer and encodings.
4. Start `FP-0012` after `FP-0011` is accepted, from `reference` and the generated tracer, as ADR 0008 decides.
5. Start `FP-0010` tree construction after `FP-0064` is accepted.

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
- Workers base on the latest pushed `master`, and the integrator commits before each dispatch, because a worktree copies uncommitted edits.
- The recorded tool versions are Node v26.7.0, Bun 1.4.2, and Git 2.54.0.windows.1.
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
