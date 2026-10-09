# Current handoff

## Actual state

Tasks `FP-0001` through `FP-0009`, `FP-0011`, `FP-0013`, `FP-0014`, `FP-0021`, `FP-0027`, `FP-0028`, `FP-0031`, `FP-0033`, `FP-0047`, `FP-0050`, `FP-0051`, `FP-0053`, and `FP-0054` are accepted.
`specs/corpora.json` pins Test262 at `2e0a5676`, WPT at `b60c4b34`, Unicode 18.0.0, and the OpenType fixtures, and `release-check` still fails closed.
The owner approved Unicode data, OFL test fonts, the WHATWG `entities.json`, and the Encoding Standard index files in the repository, as `LICENSE-DECISION.md` records.

| Task | State | Next step |
| --- | --- | --- |
| `FP-0064` tokenizer states | Implemented in `cb8427d`; review 1 accepts; amendment 3 (`b95bef1`) gives the foreign-flag fix to `FP-0104`. | Accept once the CI ledger's `FP-0098` condition clears. |
| `FP-0066` release builds | Implemented in `81481a3`; `reproduce-check` is reproducible on Windows and WSL Ubuntu; review 1 accepts. | Accept once the ledger condition clears. |
| `FP-0067` Gates checks | Implemented in `152ed53`; review 2 accepts with acceptance run 37941660067 (`4d11e84`). | Accept once the ledger condition clears. |
| `FP-0076` guard identity | Implemented in `d56bc5f` with amendment 1; review 1 accepts. | Accept once the ledger condition clears. |
| `FP-0079` Rust toolchain | Implemented in `04342e2` with revision `d2c1e5b`; both reviews accept; P1 `9fb8d8f` and P2 `2e07f89` protect the lock and `rust-toolchain.toml`. | Bind `repo-check` and `controller-test` on a head with P2, cite P2 in the criterion 6 row, then accept. |
| `FP-0081` allocation limit | Implemented in `f40a902`; review and security review accept. | Accept once the ledger condition clears. |
| `FP-0098` zig-test timeout | Implemented in `9d5638b`; ten dispatched runs pass, the slowest at 191 s; review 1 rejects for missing CI phase durations; revision 1 (`e42f789`) sets `ZIG_BUILD_SUMMARY` on both `zig-test` steps. | Integrate worker `FP0098Revision1`, then dispatch ten runs that also serve `FP-0107`, re-review, and accept; that clears the ledger's nine conditional replacements. |
| `FP-0052` corpus fixes | Implemented in `775d988`; case 2 revised in `8bc2f91`; amendment 2 (`0954a37`) makes the stand-in work under Bun. | Integrate worker `FP0052BunHost`, bind with `corpus-verify` of `test262` and `wpt`, and request `fairpane-review` and `fairpane-spec`. |
| `FP-0082` script parser | Implemented in `5d41509`; review 1 rejects a Windows path escape and a quadratic check, spec review 1 accepts; revision 1 in `9a68167` passes 322 of 322 Zig tests. | Bind revision 1 and request both reviews. |
| `FP-0107` controller-test timeout | Contract frozen in `01d7e39`. | Dispatch after the `FP-0052` and `FP-0098` revisions land. |
| Splits of `FP-0010`, `FP-0015`, `FP-0056`, and `FP-0065` | Plan commits `36782a5`, `66ad8ad`, `c122677`, `42043a7`, and `f719aed` add `FP-0100` to `FP-0105`, `FP-0108` to `FP-0127`. | Record plan review 4; freeze `FP-0108`, `FP-0119`, and `FP-0123` after their pre-freeze checks, and `FP-0100` after `FP-0064` is accepted. |
| `FP-0083` VM | Agent `FP0083Draft` proposes a compile-and-run slice and a safepoint slice, to become `FP-0128` and `FP-0129`. | Add the plan entries, and freeze the first slice after `FP-0082` is accepted. |

`engineering/evidence/ci/README.md` records every failed `Gates` attempt since 13:00 UTC and its disposition; it must be extended to each acceptance head, including the failed `repo-check` of `66d71bd`, whose fix `f5be48f` plan review 4 reviews.
Tasks `FP-0055` through `FP-0063` own the remaining text obligations, and `FP-0099` and `FP-0106` own review follow-ups.
The candidate Zig library contains a capability probe, lossless owned web strings, checked generational handles, the engine and document lifecycle, a DOM node store with attributes, a generated C ABI, the headless laboratory `fairpane-lab`, JavaScript value and heap catalogs, a bounded Script parser with a Test262 parse census, Unicode property lookup, an OpenType parser, a resumable HTML tokenizer, and CSS syntax, selectors, cascade, and computed values.
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
3. Record plan review 4, then freeze `FP-0108`, `FP-0119`, and `FP-0123` with the fixes of agents `Check0108`, `Check0119`, and `Check0123`, and dispatch them.
4. Dispatch `FP-0107` once the `FP-0052` and `FP-0098` revisions land; one set of ten dispatched runs, at most two at a time, serves `FP-0098` and `FP-0107`.
5. After `FP-0098` is accepted, extend the CI ledger to the acceptance head and accept `FP-0064`, `FP-0066`, `FP-0067`, `FP-0076`, `FP-0079`, and `FP-0081` in `plan:` acceptance commits.
6. Ask the owner the open questions: the TN5176 tables for `FP-0120`, and the shaping reference fixtures and the fontTools boundary for `FP-0111` to `FP-0115`.
7. Remove stale worker worktrees under the OMP worktree directory, as `docs/GIT_OPERATIONS.md` requires.

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
