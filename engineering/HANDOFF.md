# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0009`, `FP-0011`, `FP-0013`, `FP-0014`, `FP-0021`, `FP-0027`, `FP-0028`, `FP-0031`, `FP-0033`, `FP-0047`, `FP-0050` through `FP-0054`, `FP-0064`, `FP-0066`, `FP-0067`, `FP-0076`, `FP-0079`, and `FP-0081` are accepted.
`specs/corpora.json` pins Test262 at `2e0a5676`, WPT at `b60c4b34`, Unicode 18.0.0, and the OpenType fixtures, and `release-check` still fails closed.
The owner approved Unicode data, OFL test fonts, the WHATWG `entities.json`, the Encoding Standard index files, the TN5176 seac tables, and the Unicode text-rendering-tests files whose licenses permit redistribution, as `LICENSE-DECISION.md` records, and extended fontTools to GSUB, GPOS, and GDEF dumps in `engineering/dependencies.json`.

| Task | State | Next step |
| --- | --- | --- |
| `FP-0098` zig-test timeout | Revision 1 in `0276268`; ten dispatched runs on `29a9f8e` passed, the slowest at 191 s. | Record ten dispatched runs on one head together with `FP-0107`, re-review, and accept. |
| `FP-0107` controller-test timeout | Implemented in `13168dc`. Every Windows run on `3e7128c` failed, because a worker thread reads a case-sensitive copy of the environment and the hosted runner names the search path `Path`. Revision 1 (`d4de685`) names it `PATH` in each worker. | Ten dispatched runs on a head with revision 1, review by `FP0107Review`, and acceptance. |
| `FP-0082` script parser | Revision 2 in `84ffa53` with amendments 1 (`c28afb0`) and 2 (`f397d8d`); binding at `f397d8d`. | Review 3 by `FP0082Review`, the ledger, and acceptance. |
| `FP-0108` graphemes | Implemented in `6cf88af`; M7 amendment `7f2a7e7`; binding `1d6508e`. | Review and spec review, then acceptance. |
| `FP-0119` glyf outlines | Implemented in `077ad63`; binding `246e6de`. | Review and security review, then acceptance. |
| `FP-0123` encodings | Implemented in `b68eebf`; binding `45f5da1`. | Review and spec review, then acceptance. |
| `FP-0100` tree construction | Contract frozen in `bd11c2b`; worker `FP0100Tree` implements it. | Integrate, bind, and request review and spec review. |
| `FP-0080` split | `d945fa7` adds `FP-0132` to `FP-0134`; plan review 8 approves. | Freeze `FP-0132` after its revision and re-check, then seek the P1 lock approval. |
| Contract drafts | `out/drafts` holds `FP-0099`, `FP-0106`, `FP-0111`, `FP-0127`, `FP-0128`, and `FP-0131` drafts with their checks. | Freeze each after its check; `FP-0127` re-bases after `FP-0100`, and `FP-0128` after `FP-0082` is accepted, with a new ADR number because `FP-0107` took `0011`. |

`engineering/evidence/ci/README.md` records every failed `Gates` attempt through `0276268`.
The push run and the ten dispatched runs of `3e7128c` failed in Windows `controller-test`, and the ledger must record them, with `FP-0107` revision 1 as the fix, before the next acceptance.
The pinned build runner reruns a cached step into its old output directory after a lost manifest, so a tool that refuses an existing output must not write there; FP-0082 revision 2 amendment 1 records the census case.
Tasks `FP-0055` through `FP-0063` own the remaining text obligations, and `FP-0099`, `FP-0106`, and `FP-0131` own review follow-ups.
The candidate Zig library contains a capability probe, lossless owned web strings, checked generational handles, the engine and document lifecycle, a DOM node store with attributes, a generated C ABI, the headless laboratory `fairpane-lab`, JavaScript value and heap catalogs, a bounded Script parser with a Test262 parse census, Unicode property lookup with grapheme cluster segmentation, an OpenType parser with TrueType outline decoding, Encoding Standard labels with UTF decoders, a resumable HTML tokenizer, and CSS syntax, selectors, cascade, and computed values.
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

1. Integrate each worker patch from the worker's own `out/*.patch`, check `git diff --cached --name-only` before each commit, run the gates with `HEAD` and status records before and after, and commit locally.
2. Push only at the push boundaries of `docs/GIT_OPERATIONS.md`, and only after the previous push's `Gates` run concludes.
3. Dispatch the ten runs of `FP-0098` and `FP-0107` with `gh workflow run Gates --ref master` on one head that holds `d4de685`, at most two at a time, and stop at the first run that does not succeed; push nothing until the series ends.
4. Record the series and the failed runs of `3e7128c` in both tasks' `ci/README.md` and in the ledger, then accept `FP-0098` and `FP-0107` after their reviews.
5. Accept `FP-0082`, `FP-0108`, `FP-0119`, and `FP-0123` after their reviews, each after the ledger reaches its pre-acceptance head.
6. Request plan review 9 for `cf67a28` and `9982925` after they are pushed.
7. Keep `git worktree list` limited to the main checkout; the OMP harness keeps its isolated worker directories outside the repository, so they are not repository worktrees.

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
- Isolated worktrees can start at an older commit, so each dispatch names its base commit, and the worker checks it out first; worktrees share the repository's objects, so a local commit is enough.
- The recorded tool versions are Node v26.7.0, Bun 1.4.2, and Git 2.54.0.windows.1.
- Windows PowerShell 5.1 inherits a PowerShell 7 module path on this host.
  `scripts/Get-Zig.ps1` therefore hashes through .NET instead of `Get-FileHash`.
- The OMP shell's builtin `sha256sum` mistranslates CRLF in check mode.
  Use `node tools/fairpane.mjs record` with GNU `sha256sum` for recorded checks.
- WSL Ubuntu on this host runs as the non-root user `autark`, uid 1000.
  The locked `x86_64-linux` compiler is `$HOME/fairpane-linux/tools/zig-x86_64-linux-0.18.0-dev.120+9fe22a29b/zig`; a clone links that directory as `.tools/zig/0.18.0-dev.120+9fe22a29b/x86_64-linux`, and `engineering/evidence/FP-0067/raw/linux-baseline.log` records its digest check and a passing suite.
  Node v26.7.0 is installed at `$HOME/fairpane-linux/node`, outside `PATH`, and `engineering/evidence/hosts/wsl-ubuntu/node-install.log` records its digest check.
  Copy a tree into a WSL-native directory before a Linux run, because the `/mnt/c` mount does not keep Linux file modes.
- The compiler installer does not retry a failed download, so a transient network failure fails a `Gates` job; rerun the failed job.
- The local shell exports the search path as `PATH`, while the hosted Windows runner names it `Path`; a local pass therefore does not prove that a worker thread reads the search path on the runner.
- Bun 1.4.2 stops the main thread's `os.tmpdir()` from following `process.env` once a worker starts with `SHARE_ENV`, as `engineering/evidence/FP-0107/raw/r1-share-env-probe.log` shows.
- The OMP harness runs at most four subagents and queues the rest; a queued agent cannot receive messages until it starts.
- The owner's OMP configuration uses approval mode `yolo`.

## Unresolved items

- The protected `zig-test` gate prints no test count.
  An acceptance-policy change would need separate independent approval.
- Local receipts are unsigned.
  Task `FP-0002` owns the protected attestation boundary.

## Owner decisions

The owner made the repository public at <https://github.com/mattneel/fairpane> on October 8, 2026.
The owner authorized continuous commits and pushes to `master` on `origin`.
On October 9, 2026, the owner reported that pushing every commit floods CI, so commits are now pushed in batches under the push rules of `docs/GIT_OPERATIONS.md`.
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
