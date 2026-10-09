# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0007`, `FP-0009`, `FP-0021`, `FP-0028`, `FP-0031`, `FP-0033`, `FP-0047`, `FP-0051`, and `FP-0053` are accepted.
`specs/corpora.json` pins Test262 at `2e0a5676` and WPT at `b60c4b34`, and `release-check` still fails closed.
The owner approved Unicode data, OFL test fonts, and the WHATWG `entities.json` in the repository, as `LICENSE-DECISION.md` records.

Four implemented tasks are in revision after a rejected review.

| Task | Implementation | Review 1 finding | Revision 1 |
| --- | --- | --- | --- |
| `FP-0011` JavaScript catalogs | `84b7b14` | A leaf context reaches the heap, and long numeric literals round wrongly. | Frozen in `f95fab6`; isolated worker `FP0011R1`. |
| `FP-0013` Unicode data and fonts | `b1fdb8c` | `fairpane-security`: cmap validation work is not linear, and the corpus tools need hardening. `fairpane-review` is pending. | Not yet frozen. |
| `FP-0027` releases and stewardship | `493edb6` | The real release records ran on an older commit. | Implemented by the integrator in `ea3433a`; its release records are being recorded. |
| `FP-0054` laboratory findings | `0dda99b` | The output guard compares path strings, not file identities. | Frozen in `005ef1e`; isolated worker `FP0054R1`. |

Tasks `FP-0064` through `FP-0067` hold the deferred tokenizer states, encoding sniffing, path-independent release builds, and the remaining `FP-0033` and `FP-0051` findings.
Tasks `FP-0055` through `FP-0063` own the remaining text obligations.
The candidate Zig library contains a capability probe, lossless owned web strings, checked generational handles, the engine and document lifecycle, a DOM node store, a generated C ABI, the headless laboratory `fairpane-lab`, JavaScript value and heap catalogs, Unicode property lookup, and an OpenType parser.
No renderer, JavaScript interpreter, or native browser window exists yet.

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

1. Integrate each revision patch as it arrives, run the four gates with a binding status, and request `fairpane-review`.
   Worker patches arrive as `<Name>.patch` in the session directory; apply them with `git apply --3way` on a committed tree.
2. After `FP0011R1` lands, rerun `doctor`, `measure-build`, and the six measurement runs at the integration commit on an idle machine, then update ADR 0008 sections 3 through 6 as revision 1 requires.
3. Finish the `FP-0027` revision 1 release records on `ea3433a`, update its README and state, and request `fairpane-review`.
4. Record the `FP-0013` `fairpane-review` verdict, freeze one revision for both reviews, and dispatch `fairpane-text`.
   Apply the `unicode` and `opentype-fixtures` pins in a separate protected commit after acceptance.
5. After `FP-0054` lands, freeze `FP-0008` from `engineering/evidence/FP-0008/CONTRACT-DRAFT.md` on the new base.
   Apply these decisions: `entities.json` is approved; `FP-0064` and `FP-0065` own the deferred states and encodings; the laboratory decode stage completes only for a UTF-8 byte order mark; the change to the `FP-0007` case 2 stage assertions is accepted.
6. Freeze `FP-0014` from `engineering/evidence/FP-0014/CONTRACT-DRAFT.md`, possibly as two tasks.
   Accept the draft's correction that appends declarations in CSS Syntax section 5.5.5, keep the laboratory style stage unsupported, give each remaining obligation an owner task, confirm the user-agent constants, and consider deferring the Values 5 spread syntax.
7. Start `FP-0050` through the ABI schema and generator, and freeze the `FP-0029` Rust wrapper contract.
8. Then start `FP-0052` after `FP-0013` lands, `FP-0067`, `FP-0066`, and `FP-0012` after `FP-0011` is accepted.

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
