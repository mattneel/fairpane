# FP-0131 evidence

## Scope

Task `FP-0131` closes the FP-0052 review findings that `engineering/evidence/FP-0131/CONTRACT.md` freezes.
The worker implemented it in an isolated working tree whose `HEAD` was `b8313e622326ba6ba8438455d947a487c8ac3add`, the commit that freezes the contract.
The host was Windows 10.0.26200 on x64 with Node v26.7.0 (`raw/tests-before.log`).
No protected path changed, and `specs/corpora.json` is unchanged (`raw/protected-paths.log`).
The worker did not commit or push.

## Changes

- `tools/corpus.mjs`: `fetchCorpus` resolves the upstream ref, runs the test-only `beforeLock()` once when it is given, and takes `<id>.lock` through `withFetchLock`.
  Only under the lock does it select the pins, through the new `selectPins`: the `specs/corpora.json` entry when it has a revision, and otherwise `specs/snapshots/<id>.json`.
  The missing-record error keeps its text, and `withFetchLock` releases the lock after it.
  The fetch, the check, and the write phase run under the same lock.
  `replaceSnapshot` no longer takes the lock; its caller holds it.
  `repinCorpus` resolves the head and then holds the lock around `replaceSnapshot`, the same steps as before.
  The doc comments of `fetchCorpus`, `replaceSnapshot`, and `repinCorpus` state the lock order and the option.
  `WPT_RULE` and the comment above `WPT_NOT_TESTS` carry the narrowed support-item sentence.
- `tools/selftest.mjs`: FP-0131 cases 1 to 5. None declares `processWide`.
- `specs/IMPORT_REQUIREMENTS.md`: the `DerivedBidiClass.txt` row, the `DerivedGeneralCategory.txt` row, and the `DerivedJoiningType.txt` row that names `ContextJ`, as the contract states them.
- `specs/sources.json`: the `S37`, `S41`, and `S47` purposes, as the contract states them.
- `specs/applicability/wpt.json`: regenerated; only `discovery.rule` changed.
- `engineering/decisions/0003-corpus-snapshots.md`: fetch steps 3 and 4 and the support-item line, as the contract states them.

## Criterion mapping

| FP-0131 criterion | Cases and evidence |
| --- | --- |
| 1. LB1 in the General_Category row and S37 | Case 1 fails in `raw/tests-before.log` (the base row lacks rule LB1) and passes in the three `raw/controller-tests-after*.log` runs. |
| 2. Narrow the support-item clause everywhere; regenerate wpt.json | Case 2 fails in `raw/tests-before.log` ("WPT_RULE lacks the narrowed support-item sentence.") and passes after. M2 fails it. `raw/applicability.log` exits with status 0, and `raw/applicability-diff.log` shows one changed line, `discovery.rule`. |
| 3. Current URL algorithm names in the rows and S41 | Case 3 fails in `raw/tests-before.log` (the base Bidi row says "domain to ASCII") and passes after. |
| 4. Read the pin record under the lock; test the repin race | Case 4 fails in `raw/tests-before.log` with `calls: 0`, `repinned: undefined`, and `fetched`, `recorded`, and `snapshot_head` equal to `u.first` (`cc0f937…`). It passes after. Case 5 passes before and after. M1 fails case 4. |

`raw/tests-before.log` records `HEAD`, the base blob IDs, the staging command `git add -- tools/selftest.mjs`, the staged blob ID, `node --version`, and `node tools/fairpane.mjs test`.
That run exits with status 1: 249 of 253 cases pass, cases 1 to 4 fail, and case 5 passes.
The staged `tools/selftest.mjs` blob is the after-tree blob: `raw/review-1-records.log` records `git rev-parse 9b47a37:tools/selftest.mjs`, which prints the staged `51ca83329bcadd8516a7263c32d72a24cdf08520` of `raw/tests-before.log`.

## Mutation controls

`raw/mutation.log` records, for each control, `git hash-object tools/corpus.mjs` before, the mutation, the hash during, `git diff --no-index` into the `.diff` file (status 1, because the files differ), `node tools/fairpane.mjs test`, the restoration, and the hash after.

| Control | Diff | Hash before, during, after | Result |
| --- | --- | --- | --- |
| M1: read the pins before `beforeLock` | `raw/mutation-M1.diff` | `a6ed746b`, `206b8bf3`, `a6ed746b` | Exit status 1; 252 of 253 pass. Only case 4 fails: `calls: 1` and `repinned` is the new head, but `fetched`, `recorded`, and `snapshot_head` are `u.first`, so the fetch reinstalls `u.first`. |
| M2: restore the old clause in `WPT_RULE` only | `raw/mutation-M2.diff` | `a6ed746b`, `4c05748c`, `a6ed746b` | Exit status 1; 252 of 253 pass. Only case 2 fails, at its first assertion, "WPT_RULE lacks the narrowed support-item sentence." |

Case 2 stops at its first failing assertion, so the M2 test run reports only the sentence.
The same log then records a probe under M2 that prints `{"wpt_json_rule_equals_WPT_RULE":false}`, so the `wpt.json` equality of case 2 also fails under M2.

## Durations

Each value is the case's `# duration_ms` line in milliseconds.

| Run | Case 1 | Case 2 | Case 3 | Case 4 | Case 5 | Sum |
| --- | --- | --- | --- | --- | --- | --- |
| `raw/controller-tests-after.log` | 1 | 2 | 1 | 4528 | 1603 | 6135 |
| `raw/controller-tests-after-2.log` | 0 | 2 | 0 | 3137 | 969 | 4108 |
| `raw/controller-tests-after-3.log` | 1 | 2 | 1 | 3035 | 779 | 3818 |

The median of the sums is 4108 ms, which is within the 5000 ms limit.
Each run exits with status 0 with 253 of 253 cases.
`raw/check-after.log` records `node tools/fairpane.mjs check`, which exits with status 0.

## Protected paths

`raw/protected-paths.log` stages the six changed files and records `git write-tree`, which gives the after tree `6caecf3f38916abf8cedb4ee870e37f41736c4d6`.
The diff of the protected list between `b8313e6` and that tree prints nothing.
`node tools/fairpane.mjs fingerprint` gives the policy digest `29d3333e…` at the base and `428949ab…` at the after tree.
The base fingerprint ran with the six files restored to `b8313e6` in the working tree, and the after fingerprint ran with them restored from the index.
The wider diff prints exactly `M specs/IMPORT_REQUIREMENTS.md`, `M specs/applicability/wpt.json`, and `M specs/sources.json`.
The evidence files that the patch adds later lie outside both path lists, so the patch gives the same two diffs.

## Stop rules

- The regenerated `specs/applicability/wpt.json` differs from the base only in `discovery.rule` (`raw/applicability-diff.log`).
- The local WPT snapshot and its manifest exist under `C:\src\fairpane\.tools\corpora\wpt`, and nothing was fetched.
- `raw/source-check.log` retrieves UAX #14 revision 57 and the URL Standard.
  It finds "Only Mn or Mc" and "Any except Mn and Mc" once each in UAX #14, the quoted domain parser ToASCII and domain to Unicode sentences in the URL Standard, `domain-to-ASCII` only in its validation-error table, the validation-error step, the index, and the definition data, and no "domain to ASCII".
  [INFERENCE] The URL Standard check fetched the live page, not the commit snapshot, so its tie to `fde3f74f` rests on spec review 1, which found the same sentences in a local copy of that snapshot.
- The median duration is 4108 ms, within the limit.

## Resolved ambiguities

- The first `corpus-applicability` attempt lost the backslashes of `FAIRPANE_CORPORA_DIR` in the shell and failed with status 1.
  Its log is `raw/applicability-attempt-1.log`; `raw/applicability.log` is the run with the quoted path.
- Contract criterion 4 says that `fetchCorpus` reads the pins under the lock.
  The worker reads `specs/corpora.json` before the lock, because the upstream URL comes from it, and selects the pins from it or from the snapshot record only under the lock.
  `specs/corpora.json` is a protected file that no fetch or repin writes, so only the snapshot record can change between the two reads.
- The revision-format check and the "Pinned commit" log line moved under the lock with the pin selection, so a fetch now logs the pin after `git ls-remote`.
- The base check of `tests-before.log` ran in this working tree with the four other changed files restored to `b8313e6` and only `tools/selftest.mjs` staged; `git status --short` in that log shows the state.
- The untracked `engineering/evidence/ci/dispatch-57df855/` directory was present in the working tree before this task and is not part of the patch.

## Integration

Commit `9b47a37` integrates the worker's patch, and the push of `5859de7` carried it to `origin`.
The integrator recorded the binding after that push, in a temporary detached worktree of `9b47a37` without `.tools`, and removed the worktree afterward.
The worktree's creation and removal are not recorded; `raw/review-1-records.log` records `git worktree list`, which lists only the main tree.
`raw/integration-binding.log` records `HEAD` `9b47a3707910a0791ad784da260f81a954faee30` and a status of the whole worktree, ignored files included, before and after both gates.
The only entries are this log and the new receipts.

| Run | Record | Result |
| --- | --- | --- |
| `repo-check` | `gates/2026-10-09T20-52-57-087Z-repo-check-8029ca73.json` | pass, 208 ms |
| `controller-test` | `gates/2026-10-09T20-52-57-543Z-controller-test-7dbe35f0.json` | pass, 253 of 253, 52,044 ms |
| `corpus-verify test262` at `9b47a37` | `raw/corpus-verify-test262.log` | exit 0, no missing denominator |
| `corpus-verify wpt` at `9b47a37` | `raw/corpus-verify-wpt.log` | exit 0, no missing denominator |

Both `corpus-verify` runs set `FAIRPANE_CORPORA_DIR` to the local snapshots through the record tool's `--env` option.
They ran after the binding's last `HEAD` and status records, so the binding does not cover them; their logs record the worktree as their working directory.
The receipts and logs were copied from the worktree into this tree unchanged.

## Review dispositions

- Review 1's minor on the early read of `specs/corpora.json`: contract amendment 1 accepts the order and states why.
- Review 1's minors on the after-tree blob, the worktree's removal, the `corpus-verify` timing, and the live URL page: answered above, with `raw/review-1-records.log`.
- Criterion 4 took its first branch: the fetch removes the window between the pin read and the lock, as integrator decision 1 and the resolved questions state, instead of detecting a change in it.
- Spec review 1's minor on S41: the URL Standard calls "domain to Unicode" from URL rendering (§4.8), not from host parsing, so S41 and rows 68, 73, and 74 of `specs/IMPORT_REQUIREMENTS.md` attribute it too widely; the contract's non-goals forbid that change here, so a plan change gives it an owner.
