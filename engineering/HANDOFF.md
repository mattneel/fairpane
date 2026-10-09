# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0009`, `FP-0011`, `FP-0013`, `FP-0014`, `FP-0021`, `FP-0027`, `FP-0028`, `FP-0031`, `FP-0033`, `FP-0047`, `FP-0050`, `FP-0051`, `FP-0053`, and `FP-0054` are accepted.
`specs/corpora.json` pins Test262 at `2e0a5676`, WPT at `b60c4b34`, Unicode 18.0.0, and the OpenType fixtures, and `release-check` still fails closed.
The owner approved Unicode data, OFL test fonts, the WHATWG `entities.json`, and the Encoding Standard index files in the repository, as `LICENSE-DECISION.md` records.

| Task | State | Next step |
| --- | --- | --- |
| `FP-0064` tokenizer states | Implemented in `cb8427d`; the binding in `b7369a3` passes all four gates and 292 of 292 tests. | Record the verdict of `fairpane-review` worker `FP0064Review`. |
| `FP-0067` Gates checks and Linux Zig gates | Implemented in `152ed53`; `repo-check` and `controller-test` pass at that head. | Record the first `Gates` run with the change (37936609533) and its Linux receipts under `engineering/evidence/FP-0067/ci/`, then request review. |
| `FP-0079` Rust toolchain | Implemented in `04342e2`; security review 1 accepts, review 1 rejects the PATH `rustc` probe in `doctor`. Revision 1 frozen in `e6d215c`. | Integrate worker `FP0079R1`, request both reviews, then record `rust-lock-verify`, land policy change P1, and run the gates on the P1 head. |
| `FP-0081` engine allocation limit | Contract frozen in `d17abb0`, amendment 1 in `e659254`. | Integrate worker `FP0081Budget` and request `fairpane-review` and `fairpane-security`. |
| `FP-0082` script parser | Contract frozen in `a3e5cf9`. | Integrate worker `FP0082Parser` and request `fairpane-review` and `fairpane-spec`. |
| `FP-0052`, `FP-0066`, `FP-0076` | Contracts frozen in `42c5e07`, `3640a79`, and `297f1d3`. | Dispatch `fairpane-core` for each as agent slots free. |

Tasks `FP-0064` through `FP-0098` hold the tokenizer states, encoding sniffing, release reproducibility, review follow-ups, the CSS obligations, notices, html5lib-tests, the Rust toolchain and wrapper split, the engine allocation limit, the JavaScript parser, VM, runner, and obligation tasks, and the CI timeout margin.
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

1. Integrate each worker patch as it arrives, check `git diff --cached --name-only` before each commit, run the gates with `HEAD` and status records before and after, and request review.
   Worker patches arrive as `<Name>.patch` in the session directory; `git apply --3way` stages what it applies.
2. Check the `Gates` run of each pushed head, and record any failure in the affected task's evidence before acceptance.
3. Record each pending review verdict, and route minor findings to the follow-up tasks in their own `plan:` commits.
4. Request plan review 3 for `49f2a81`'s successors: `efc3dd3` and any later `plan:` commit.
5. Dispatch the frozen contracts `FP-0052`, `FP-0066`, and `FP-0076`, at most four agents at a time.
6. After `FP-0064` is accepted, delegate the `FP-0010` split and first contract to `fairpane-spec`; tree construction has 21 insertion modes plus foreign content at the pin.
7. Freeze `FP-0078` after `FP-0052`, `FP-0075` after `FP-0066`, `FP-0077` after `FP-0052` and `FP-0064`, and `FP-0098` after `FP-0067`.

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
- WSL Ubuntu on this host runs as the non-root user `autark`, uid 1000.
  The locked `x86_64-linux` compiler is installed under `$HOME/fairpane-linux/tools` there, and `engineering/evidence/FP-0067/raw/linux-baseline.log` records its digest check and a passing suite.
  Node v26.7.0 is installed at `$HOME/fairpane-linux/node`, outside `PATH`, and `engineering/evidence/hosts/wsl-ubuntu/node-install.log` records its digest check.
  Copy a tree into a WSL-native directory before a Linux run, because the `/mnt/c` mount does not keep Linux file modes.
- The compiler installer does not retry a failed download, so a transient network failure fails a `Gates` job; rerun the failed job.
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
