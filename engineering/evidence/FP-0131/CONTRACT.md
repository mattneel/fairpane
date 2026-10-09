# FP-0131 task contract

## Identity

Task ID: `FP-0131`, "Close the FP-0052 review findings".
Workstream: `laboratory`.
Base: the commit that freezes this contract, at least `b9217fe`. Every line number below was re-read at `b9217fe`.
Prerequisite: `FP-0052`, accepted (`engineering/state.json:706`).
A contract worker drafted this contract, an independent pre-freeze check reviewed it, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Source findings: `engineering/evidence/FP-0052/reviews/review-1-accept.json` (the LB1 minor finding and the note at `tools/corpus.mjs:527`) and `engineering/evidence/FP-0052/reviews/spec-review-1-accept.json` (minor findings 1 to 3).

### Integrator decisions

0. Agent CheckFindings checked the draft twice: its first check (fix-first, 2 majors) led to this revision, and its re-check returned freeze with one minor and one note, which the integrator applied at the freeze.
1. Criterion 4 takes its first branch. With no policy revision, the Git corpus fetch reads `specs/snapshots/<id>.json` only while it holds `<id>.lock`, and it fetches the commit that this read names.
   A repin that finishes before the lock is therefore honored, and none can finish between the read and the lock.
   This matches `fetchFileSet`, which reads its record under the lock (`tools/fileset.mjs:607`, read at `:614`), and ADR 0003:72-73, which makes the snapshot record the fallback pin.
2. A test-only option `beforeLock()` runs once in `fetchCorpus` for a Git corpus, after the fetch resolves the upstream ref and before it takes the lock, as `onWriteStep` does for the write phase.
3. The frozen texts in "Behavior" are the new wording. They narrow the WPT clause to files that reach the test262 rule of `manifest_items`, following the plan criterion and FP-0052 spec review 1. They do not name `SourceFile.name_is_test262`, because that is the name predicate, which `S47` already cites, not the `manifest_items` branch.
4. The task changes five copies of the WPT rule and the ADR fetch procedure:
   - The `tools/corpus.mjs` comment (`:257-258`), `WPT_RULE` (`:393-394`), ADR 0003 (`engineering/decisions/0003-corpus-snapshots.md:223-224`), `S47` (`specs/sources.json:386`), and `specs/applicability/wpt.json` through regeneration.
   - ADR 0003 lines 97 and 98, the order of the lock and the commit selection.
   Evidence records, including `engineering/evidence/FP-0052/CONTRACT.md:58-59`, stay unchanged.
5. The URL names change in `specs/IMPORT_REQUIREMENTS.md:68` and `:74` and in `S41`. `docs/SOURCES.md` lists only S00 to S24, so it does not change.
6. The median, over three recorded `node tools/fairpane.mjs test` runs, of the sum of the new cases' `# duration_ms` lines is at most 5000 ms on the development host.

### Observed facts that shaped the decisions

- `tools/corpus.mjs:517-538` (`fetchCorpus`): with no policy revision, the fetch reads the record at `:525-529`, resolves `HEAD` at `:534`, and only then calls `replaceSnapshot`, which takes the lock at `:488`.
- ADR 0003 lines 96-98: step 2 runs `git ls-remote`, step 3 selects the commit, and step 4 creates the lock file. Line 20 states that the lock is held from before `<corpus-id>.fetch` is touched until `<corpus-id>.old` is removed.
- `tools/selftest.mjs:1283-1303` (`upstreamFixture`) gives a local `file://` upstream with `move()`, and `:1320-1322` shows that a fetch with no policy revision is pinned by `specs/snapshots/test262.json`.
- `specs/applicability/wpt.json` records `discovered` 76620, `selected` 0, `unclassified` 76620, `manifest.sha256` `86d55bee991997a4753d0987397883249a0d6fc94e0901ed3efb84cceed53067`, and `manifest.item_counts` `{ aamtest: 190, crashtest: 2030, manual: 3047, print-reftest: 432, reftest: 28489, support: 41779, test262: 53660, testharness: 39050, visual: 2714, wdspec: 648 }`.
- `specs/IMPORT_REQUIREMENTS.md` has one `ucd/extracted/DerivedBidiClass.txt` row (`:68`), one `ucd/extracted/DerivedGeneralCategory.txt` row (`:69`), and two `ucd/extracted/DerivedJoiningType.txt` rows (`:74`, which names `ContextJ`, and `:75`).
- `specs/sources.json` holds `S37` at `:303-306`, `S41` at `:335-338`, and `S47` at `:383-386`.
- No controller test pins the texts of `specs/IMPORT_REQUIREMENTS.md`, `S37`, `S41`, or `S47`.
- The local snapshots exist under `C:\src\fairpane\.tools\corpora\` (`test262`, `wpt`, `unicode`, and `opentype-fixtures`).
- `engineering/evidence/FP-0107/raw/bun-selftest-zig-test-2.log` records 2896 ms for the comparable case "corpus-fetch against a local fixture upstream fetches the pinned commit after the upstream branch moves".

## Sources

- `engineering/plan.json`, entry `FP-0131` (`:4318-4337`), criteria 1 to 4.
- UAX #14 revision 57, <https://www.unicode.org/reports/tr14/tr14-57.html>, retrieved 2026-10-09: rule LB1 and its table, which resolves SA to CM for General_Category "Only Mn or Mc" and to AL for "Any except Mn and Mc".
- URL Standard at `whatwg/url` `fde3f74f063341a28d437216f75735b8b40128f5` (the latest commit to `url.bs`, 2026-10-07), <https://url.spec.whatwg.org/>, retrieved 2026-10-09, section 3.3:
  - "The domain parser ToASCII algorithm ... returns the result of running Unicode ToASCII ... CheckBidi set to true, CheckJoiners set to true".
  - "The domain to Unicode algorithm ... Unicode ToUnicode ... CheckBidi set to true, CheckJoiners set to true".
  - `domain-to-ASCII` appears only as a validation error.
- WPT at `b60c4b349d9d167bf354a40bc0d4cbed15174606`: `tools/manifest/sourcefile.py` lines 428-431 (`name_is_test262`) and 1155-1162 (a `None` record becomes `support`), and `tools/manifest/test262.py` `parse`, which returns `None` for a name that ends in `_FIXTURE.js` or for a file without a `/*---` to `---*/` block.
- Repository files: `specs/IMPORT_REQUIREMENTS.md`, `specs/sources.json`, `specs/applicability/wpt.json`, `engineering/decisions/0003-corpus-snapshots.md`, `tools/corpus.mjs`, `tools/fileset.mjs`, and `tools/selftest.mjs`.

## Behavior

### General_Category consumers

The `ucd/extracted/DerivedGeneralCategory.txt` row of `specs/IMPORT_REQUIREMENTS.md` becomes exactly:

```text
| `ucd/extracted/DerivedGeneralCategory.txt` | `General_Category`, listed explicitly for every range including `Cn`; the qualification seeds and the Universal Shaping Engine categories; UAX #14 rule LB1, which resolves SA to CM for `Mn` and `Mc` and to AL otherwise, rules LB15a and LB15b (`Pi` and `Pf`), LB19 (`Pi` and `Pf`), and LB30b (`Cn`), and rule LB10, which gives a remaining CM or ZWJ the value `Lu`; UTS #46 section 4.1 criterion 6, which rejects a label that begins with `General_Category=Mark`, for URL host parsing; imported by FP-0013 | [S27], [S50], [S37], [S39], [S41] |
```

The `S37` purpose becomes exactly: `LineBreak.txt; East_Asian_Width use in class AI resolution, directly in rules LB19a and LB30, and in rule LB10, which gives a remaining CM or ZWJ the value Na; General_Category use in rule LB1, which resolves SA to CM for Mn and Mc and to AL otherwise, in rules LB15a, LB15b, LB19, and LB30b, and in rule LB10, which gives a remaining CM or ZWJ the value Lu; Extended_Pictographic use; and line breaking rules.`

### WPT support-item clause

- `WPT_RULE`: `frontmatter block; any other such file becomes a "support" item. ` becomes `frontmatter block. A file that reaches the test262 rule of manifest_items but fails its "_FIXTURE.js" or frontmatter condition becomes a "support" item. `
- The comment at `tools/corpus.mjs:257-258`: `; any other such file becomes a "support" item.` becomes `. A file that reaches the test262 rule of `manifest_items` but fails its "_FIXTURE.js" or frontmatter condition becomes a "support" item.` The worker may rewrap the comment lines.
- ADR 0003 line 224 becomes exactly `  A file that reaches the `test262` rule of `manifest_items` but fails its `_FIXTURE.js` or frontmatter condition becomes a `support` item.`
- The `S47` purpose ends `; a file that reaches the test262 rule of manifest_items but fails its _FIXTURE.js or frontmatter condition becomes a support item.` instead of `; any other such file becomes a support item.`
- `node tools/fairpane.mjs corpus-applicability wpt` regenerates `specs/applicability/wpt.json`, and only `discovery.rule` changes.

### URL Standard names

- The `ucd/extracted/DerivedBidiClass.txt` row ends `because the URL Standard sets `CheckBidi` to true for domain parser ToASCII and domain to Unicode | [S14], [S27], [S39], [S101], [S41] |`.
- The `ucd/extracted/DerivedJoiningType.txt` row that contains `ContextJ` ends `and the URL Standard sets `CheckJoiners` to true for domain parser ToASCII and domain to Unicode | [S49], [S39], [S41], [S27] |`.
- The `S41` purpose becomes exactly `Host parsing through Unicode ToASCII and ToUnicode from UTS #46, with CheckBidi and CheckJoiners set to true in domain parser ToASCII and domain to Unicode.`
- Every other part of both rows stays.

### Pin record under the lock

For a Git corpus, `fetchCorpus` resolves the upstream ref, runs `beforeLock` once when it is given, and takes `<id>.lock`.
Only then does it read the pins: from `specs/corpora.json` when the policy has a revision, and otherwise from `specs/snapshots/<id>.json`.
The missing-record error keeps its text, and the lock is released after it.
The fetch, check, and write phase run under the same lock.
`repinCorpus` keeps its behavior. If the lock moves out of `replaceSnapshot`, `repinCorpus` takes it around the same steps.
The doc comments of `fetchCorpus` and `replaceSnapshot` state the lock order and the option.

ADR 0003 lines 97 and 98 become exactly:

```text
3. Create the lock file `<corpora-root>/<corpus-id>.lock`, or fail when it exists.
4. Select the commit while holding the lock: for `corpus-fetch`, the `specs/corpora.json` revision, or else the commit of `specs/snapshots/<corpus-id>.json`; for `corpus-repin`, the reported head.
```

## Exact test cases

Controllers in `tools/selftest.mjs`, named `FP-0131 case N: ...`. They read `specs` and `engineering/decisions` files directly and never scan a test file. No case changes process-wide state, so none declares `processWide`.

1. The only row of `specs/IMPORT_REQUIREMENTS.md`, split on LF or CRLF, whose first cell is `ucd/extracted/DerivedGeneralCategory.txt` equals the frozen row, and the `S37` purpose equals the frozen text.
2. WPT clause:
   - `corpus.WPT_RULE` includes `A file that reaches the test262 rule of manifest_items but fails its "_FIXTURE.js" or frontmatter condition becomes a "support" item.`
   - `tools/corpus.mjs`, with every match of `/\r?\n\s*\* ?/g` replaced by one space, includes `A file that reaches the test262 rule of `manifest_items` but fails its "_FIXTURE.js" or frontmatter condition becomes a "support" item.`
   - ADR 0003, split on LF or CRLF, contains the frozen line exactly once, after the line that starts `- Upstream gives the `test262` type`.
   - The `S47` purpose equals the frozen text.
   - None of `tools/corpus.mjs`, ADR 0003, `specs/sources.json`, and `specs/applicability/wpt.json` matches `/other such file/i`.
   - `specs/applicability/wpt.json` has `discovery.rule` equal to `corpus.WPT_RULE`, and the counts and digest listed under "Observed facts".
3. URL names: the only row whose first cell is `ucd/extracted/DerivedBidiClass.txt`, and the only `ucd/extracted/DerivedJoiningType.txt` row that contains `ContextJ`, each equal their frozen rows. The `S41` purpose equals the frozen text, and neither `specs/IMPORT_REQUIREMENTS.md` nor `specs/sources.json` contains `domain to ASCII`.
4. A repin that finishes between the first read and the lock:
   - `u = upstreamFixture()`. Fetch with `u.policy({ revision: u.first })`.
   - `head = u.move()`, and `unpinned = u.policy({})`.
   - Run `corpus.fetchCorpus(u.dir, 'test262', { ...u.options(unpinned), beforeLock })`, where `beforeLock` adds 1 to `calls` and awaits `corpus.repinCorpus(u.dir, 'test262', u.options(unpinned))`, keeping its `commit` as `repinned`.
   - The case asserts `{ calls, repinned, fetched: r.commit, pinned_by: r.pinned_by, recorded: readJson(u.recordFile).commit, snapshot_head: <rev-parse refs/heads/main of u.snapshot>, corpora: fs.readdirSync(u.corporaDir) }` deep-equals `{ calls: 1, repinned: head, fetched: head, pinned_by: 'specs/snapshots/test262.json', recorded: head, snapshot_head: head, corpora: ['test262'] }`.
   - ADR 0003, split on LF or CRLF, contains the two frozen lines 97 and 98, in that order, after the line `### Fetch`.
5. A fetch with `u.policy({})` and no record rejects with exactly `Corpus test262 has no pinned revision and no snapshot record. Run corpus-repin test262.`, and `fs.readdirSync(u.corporaDir)` is `[]` afterward.

### Base failures

- Cases 1 to 3 fail, because the base texts are the ones at `specs/IMPORT_REQUIREMENTS.md:68`, `:69`, and `:74`, `specs/sources.json:306`, `:338`, and `:386`, `tools/corpus.mjs:258` and `:394`, and ADR 0003 line 224.
- Case 4 fails with `calls: 0`, `fetched` and `recorded` equal to `u.first`, because the base ignores `beforeLock` and reads the record before the lock (`tools/corpus.mjs:525-536`). Its ADR assertion also fails on the base lines 97 and 98.
- Case 5 passes on the base. It guards the lock release on the new path.

### Mutation controls

| Control | Mutation | Case that fails |
| --- | --- | --- |
| M1 | Read the pins before `beforeLock`, as the base does | Case 4: the fetch reinstalls `u.first` |
| M2 | Restore the old clause in `WPT_RULE` only | Case 2: the sentence and the `wpt.json` equality |

Record each control as a `.diff` with the file hashes before, during, and after.

### Stop rules

- If the regenerated `specs/applicability/wpt.json` differs from the base in anything except `discovery.rule`, stop and report the diff.
- If the local WPT snapshot or its manifest is missing, stop. Never fetch it.
- If the retrieved UAX #14 or URL Standard text differs from the quotations above, stop and report it.
- If the median over three recorded `node tools/fairpane.mjs test` runs of the sum of the new cases' `# duration_ms` lines exceeds 5000 ms on the development host, stop and report each case's duration in every run.

### Criterion mapping

| FP-0131 criterion | Cases and evidence |
| --- | --- |
| 1. LB1 in the General_Category row and S37 | Case 1 |
| 2. Narrow the support-item clause everywhere; regenerate wpt.json | Case 2; M2; `applicability.log`, `applicability-diff.log` |
| 3. Current URL algorithm names in the rows and S41 | Case 3 |
| 4. Read the pin record under the lock; test the repin race | Cases 4 and 5; M1 |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0131/raw/`. Never overwrite a log, and name a failed attempt's log `-attempt-N`.

1. `tests-before.log`: in a base worktree with the after-tree `tools/selftest.mjs` staged, record `HEAD`, the staging command, the blob ID, `node --version`, and `node tools/fairpane.mjs test`. It must exit with status 1, with cases 1 to 4 failing and case 5 passing.
2. `applicability.log`: `node tools/fairpane.mjs corpus-applicability wpt` with `--env FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`.
3. `applicability-diff.log`: `git diff --stat -- specs/applicability/wpt.json` and `git diff -- specs/applicability/wpt.json`, which must show one changed line, `discovery.rule`.
4. `mutation.log` with `mutation-M1.diff` and `mutation-M2.diff`.
5. `controller-tests-after.log`, `controller-tests-after-2.log`, and `controller-tests-after-3.log` with `node tools/fairpane.mjs test`, each of which must exit with status 0, and `check-after.log` with `node tools/fairpane.mjs check`. Report each new case's `# duration_ms` line from each run and the median of the sums.
6. `protected-paths.log`: `git diff --name-status <base> <after> -- AGENTS.md docs/CHARTER.md engineering/qualification.json engineering/policy.json engineering/gates.json toolchains/zig.lock.json toolchains/rust.lock.json rust-toolchain.toml specs/corpora.json`, which must print nothing, and `node tools/fairpane.mjs fingerprint` at the base and at the after tree, and `git diff --name-status <base> <after> -- AGENTS.md docs/CHARTER.md engineering/qualification.json engineering/policy.json engineering/gates.json engineering/dependencies.json toolchains rust-toolchain.toml specs`, which must print exactly `M specs/IMPORT_REQUIREMENTS.md`, `M specs/applicability/wpt.json`, and `M specs/sources.json`.
7. `engineering/evidence/FP-0131/README.md`: the criterion mapping, each control's result, the durations, and every resolved ambiguity.

The integrator records `HEAD` and a status that includes ignored files before and after it runs `repo-check` and `controller-test` with `--evidence-dir engineering/evidence/FP-0131/gates`.
The integrator then runs `corpus-verify test262` and `corpus-verify wpt` at the integration commit and records both. Each must exit with status 0.

## Authority

The writable paths are `specs`, `tools`, `tests`, `engineering/decisions`, and `engineering/evidence/FP-0131/`.
These protected paths stay unchanged, including `specs/corpora.json`: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
The policy digest changes only through `specs/IMPORT_REQUIREMENTS.md`, `specs/sources.json`, and `specs/applicability/wpt.json`; the required `fairpane-spec` review is the independent approval of those texts. `protected-paths.log` shows that no protected path changes.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
The required reviewers are `fairpane-review` and `fairpane-spec`.

## Non-goals

- No change to the pins, the discovery, or any count.
- No lock for commands that only read a snapshot, and no change to the file-set fetch.
- No change to frozen evidence records.
- No other UAX #14 or URL Standard citation update.

## Resolved questions

- The fetch reads its pins under the lock, so it removes the race instead of detecting it. A fetch that failed on a changed record would add an error path that protects nothing.
- The WPT clause wording follows the plan criterion and FP-0052 spec review 1, so no pre-freeze confirmation is needed. `fairpane-spec` reviews the result.

## Amendments

1. Review 1 (`reviews/review-1-accept.json`) found that `fetchCorpus` reads `specs/corpora.json` before `git ls-remote` and the lock, while "Pin record under the lock" says that only after the lock does it read the pins.
   The worker disclosed the order as a resolved ambiguity: the upstream URL comes from that file, and the pins are selected from that read or from the snapshot record only under the lock.
   The integrator accepts that order and narrows the sentence to the snapshot record: under the lock, the fetch reads `specs/snapshots/<id>.json` and selects the pins.
   `specs/corpora.json` is a protected policy file that changes only in a reviewed `policy:` commit, and no fetch or repin writes it.
   The race that this task removes is a repin that rewrites the snapshot record, and case 4 still covers it.
