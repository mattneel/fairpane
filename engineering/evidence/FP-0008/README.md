# FP-0008 evidence

## Scope

Task `FP-0008` implements the HTML tokenizer continuations that `CONTRACT.md` freezes.
The standard text is whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, file `source`, which `raw/html-standard-pin.log` binds by SHA-256.
The worker implemented the contract in an isolated working tree whose `HEAD` was `c283c70` ("FP-0008: freeze the HTML tokenizer contract").
The host was Windows, x64, with the locked compiler `0.18.0-dev.120+9fe22a29b`.

## Changed files

| File | Change |
| --- | --- |
| `src/html/states.zig` | New. `State` with 84 tags in section order, `section`, `title`, `implemented`, `owner`, and the branch list of each implemented state for the test-only counters. |
| `src/html/errors.zig` | New. `ErrorCode` with the 52 codes in table order, `name`, `fromName`, and `raisedByTokenizer`. |
| `src/html/tokenizer.zig` | New. The pull tokenizer, its input model, positions, spans, and the test-only branch counters. |
| `src/html/dump.zig` | New. The canonical dump and its three option sets: `full`, `plain`, and `tokens`. |
| `src/html/entities.zig` | New. Access to the committed table, the allocation-free incremental `Matcher`, and `lookup`. |
| `src/html/entities_gen.zig` | New. The generator of `src/html/entities_table.zig`. |
| `src/html/entities_table.zig` | New. The generated table, which `zig build entities-generate` wrote and which is committed under amendment 1. |
| `src/html/root.zig` | New. The `html` namespace. |
| `src/html/entities.json` | New. The unedited bytes of `https://html.spec.whatwg.org/entities.json`. |
| `src/html/entities.LICENSE` | New. The unedited `LICENSE` of whatwg/html at the frozen commit. |
| `src/html/entities.provenance.json` | New. The provenance record. |
| `src/html/.gitattributes` | New. `entities.json -text` and `entities.LICENSE -text`. |
| `src/html/tokenizer_test.zig` | New. Cases 1, 2, 4 to 12, and 15 to 17. |
| `src/html/partition_test.zig` | New. The partition harness and cases 13 and 14. |
| `src/html/entities_test.zig` | New. Case 3. |
| `src/root.zig` | Exports `html` and references its tests. |
| `src/lab.zig` | The `decode` and `tokenize` stages, their expectations, checks, records, and outcomes; `ddmin` generic over its element type; FP-0007 case 2's new stage assertions; cases 18 to 25. |
| `build.zig` | The `entities-generate` step, which writes the generated table into the source tree through `addUpdateSourceFiles`, the `fp0008-*` fixtures, and case 26. |
| `tests/lab/fp0008-*.json` | Twelve new fixtures for cases 18 to 26. |
| `tests/lab/README.md` | Describes the new fixtures. |

## Records

| Log | Command | RESULT |
| --- | --- | --- |
| `raw/html-standard-pin.log` | The integrator's download and digest of the frozen `source` | `exit_code` 0, 0 |
| `raw/owner-answers.log` | The integrator's record of the owner's answer | Recorded before this work |
| `raw/tests-before.log`, attempt 1 | `zig build test --summary all --cache-dir out/fp0008-cache-before` | `exit_code` null, `error` "The executable is not on PATH": the shell removed the backslashes of the compiler path. Kept as a failed attempt. |
| `raw/tests-before.log`, run 1 | The same command, with the corrected path | `exit_code` 1, 1 of 67 steps |
| `raw/tests-before.log`, diff | `git diff --no-index` of the base `build.zig` and the run 2 `build.zig` | `exit_code` 1, because the files differ |
| `raw/tests-before.log`, run 2 | `zig build test --summary all --cache-dir out/fp0008-cache-before-behavior` | `exit_code` 1, 62 of 65 steps, 178 of 178 tests |
| `raw/entities-fetch.log` | `curl -sS -f -D - -o src/html/entities.json https://html.spec.whatwg.org/entities.json` | `exit_code` 0, with the response headers |
| `raw/entities-fetch.log` | `curl -sS -f -D - -o out/fp0008-multipage-index.html https://html.spec.whatwg.org/multipage/` | `exit_code` 0 |
| `raw/entities-fetch.log` | `grep -o` with a pattern that quoted `pubdate` | `exit_code` 1, no match. Kept as a failed attempt. |
| `raw/entities-fetch.log` | `grep -o "Last Updated <span class=pubdate>[^<]*</span>"` | `exit_code` 0: `9 October 2026` |
| `raw/license-fetch.log` | `git ls-remote https://github.com/whatwg/html refs/heads/main` | `exit_code` 0: `877d6146487f15b15bc8dd0e3c625063a37b456a` |
| `raw/license-fetch.log` | `curl` of `LICENSE` at `efc54f7b70858d9fcf06d1a5871ae215f448c029` into `src/html/entities.LICENSE` | `exit_code` 0 |
| `raw/license-fetch.log` | `curl` of `LICENSE` at `877d6146487f15b15bc8dd0e3c625063a37b456a` into `out/` for comparison | `exit_code` 0 |
| `raw/entities-digest.log` | GNU `sha256sum` of both files and the comparison copy | `exit_code` 0 |
| `raw/entities-digest.log` | `wc -c` of the same files | `exit_code` 0 |
| `raw/entities-digest.log` | GNU `sha256sum` and `wc -c` of `src/html/entities_table.zig` after amendment 1 | `exit_code` 0, 0 |
| `raw/tests-after.log`, run 1 | `zig build test --summary all --cache-dir out/fp0008-cache-after`, uncached | `exit_code` 0, 67 of 67 steps, 205 of 205 tests |
| `raw/tests-after.log`, run 2 | The same command after the case 14 fix below, with the cache directory deleted first | `exit_code` 0, 67 of 67 steps, 205 of 205 tests |
| `raw/mutation-pending-cr.log`, diff | `git diff --no-index` of the saved fixed tokenizer and the mutant | `exit_code` 1, because the files differ |
| `raw/mutation-pending-cr.log`, run | `zig build test --summary all --cache-dir out/fp0008-cache-mutation` | `exit_code` 1, 65 of 67 steps, 200 of 205 tests |
| `raw/mutation-pending-cr.log`, restoration | `git diff --no-index --exit-code` of the saved fixed tokenizer and the restored file | `exit_code` 0 |
| `raw/checks-attempt-1.log` | `zig fmt --check build.zig src tests` | `exit_code` 0 |
| `raw/checks-attempt-1.log` | `node tools/fairpane.mjs test`, before amendment 1 | `exit_code` 1, 180 of 181 controller tests. Kept as a failed attempt. See "Amendment 1". |
| `raw/entities-generate.log` | `zig build entities-generate --summary all --cache-dir out/fp0008-cache-generate` | `exit_code` 0, 4 of 4 steps |
| `raw/tests-after.log`, run 3 | `zig build test --summary all --cache-dir out/fp0008-cache-after` after amendment 1, with the cache directory deleted first | `exit_code` 0, 65 of 65 steps, 205 of 205 tests |
| `raw/checks-after.log` | `zig fmt --check build.zig src tests` after amendment 1 | `exit_code` 0 |
| `raw/checks-after.log` | `node tools/fairpane.mjs test` after amendment 1 | `exit_code` 0, 181 of 181 controller tests |

`raw/mutation-pending-cr.diff` holds the exact diff of the mutation control.

### tests-before

The contract asks for a failing run at the base.
Both runs used a copy of the base commit that `git archive HEAD` extracted to `out/fp0008-base`.

1. Run 1 adds the new tests, fixtures, table data, `src/root.zig`, and `build.zig`, without any implementation file.
   The generator `src/html/entities_gen.zig` and `src/html/root.zig` do not exist, so every compile fails, and the error masks every case.
2. Run 2 keeps the base sources and adds only the `fp0008-*` fixtures and the three case 26 steps to the base `build.zig`, which the recorded diff shows.
   The base laboratory treats a `tokenize` expectation as an unimplemented stage, so case 18 and the `token_count` variant of case 19 exit with status 2 and fail.
   The `<p>` case of case 21 passes at the base, because it also expects exit status 2.
   Every FP-0007 and FP-0054 case passes, 178 of 178 tests.

### Digests

| File | Size | SHA-256 |
| --- | --- | --- |
| `src/html/entities.json` | 145897 | `d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6` |
| `src/html/entities.LICENSE` | 16315 | `85dc6f5ccb57a6fe8c33d158f9fc8fc7ee5655a5d3db2cdd131c6a3d0f48a864` |
| `src/html/entities_table.zig` | 124387 | `03c7ba16a447ab59c53f467a034a1b40728318e5e5f246710616429eb0834b0e` |

The `LICENSE` at `877d6146487f15b15bc8dd0e3c625063a37b456a`, the `main` commit at retrieval, has the same size and digest.
`entities.json` had `Last-Modified: Wed, 12 Nov 2025 00:20:03 GMT` and `ETag: "6913d2b3-239e9"`.
Case 3 checks the sizes and digests of the embedded files against `entities.provenance.json`.

## Acceptance

- Every case from 1 to 26 has a test whose name carries its number.
  Case 25 is the renamed FP-0007 case 2 test, "FP-0007 case 2 and FP-0008 case 25: ...".
- Every FP-0007 and FP-0054 case passes in run 3 of `raw/tests-after.log`.
  FP-0007 case 2 now asserts `fetch` `completed`, `decode` `unsupported`, `tokenize` `not-reached`, and every other stage `unsupported`.
  FP-0007 case 11 calls `ddmin(u8, ...)`.
- Case 11's counters are nonzero for every branch of every implemented state.
- The entity table has 2231 names, 2125 with `;`, 106 without, and 93 with two code points.

## Unimplemented states

The 30 unimplemented states belong to `FP-0064`, and `owner(state)` returns `"FP-0064"` for each.

| Sections | States |
| --- | --- |
| 13.2.5.2 to 13.2.5.5 | RCDATA, RAWTEXT, Script data, PLAINTEXT |
| 13.2.5.9 to 13.2.5.11 | RCDATA less-than sign, RCDATA end tag open, RCDATA end tag name |
| 13.2.5.12 to 13.2.5.14 | RAWTEXT less-than sign, RAWTEXT end tag open, RAWTEXT end tag name |
| 13.2.5.15 to 13.2.5.17 | Script data less-than sign, Script data end tag open, Script data end tag name |
| 13.2.5.18 to 13.2.5.25 | Script data escape start, escape start dash, escaped, escaped dash, escaped dash dash, escaped less-than sign, escaped end tag open, escaped end tag name |
| 13.2.5.26 to 13.2.5.31 | Script data double escape start, double escaped, double escaped dash, double escaped dash dash, double escaped less-than sign, double escape end |
| 13.2.5.69 to 13.2.5.71 | CDATA section, CDATA section bracket, CDATA section end |

## Unraised error codes

| Code | Owner task |
| --- | --- |
| `eof-in-cdata` | `FP-0064` |
| `eof-in-script-html-comment-like-text` | `FP-0064` |
| `non-void-html-element-start-tag-with-trailing-solidus` | `FP-0010` |

## Mutation control

The control makes the preprocessor turn a CR at the end of the available input into LF at once: the `.more` branch of the CR lookahead in `Tokenizer.consume` no longer returns null.
It fails case 13 on input P1, as required.
The harness reports the partition `[0,2) [2,8)`, the reference dump `["Character","a\u000Ab\u000A\u000Ac\u000A",[0,8]]`, the partition dump `["Character","a\u000A\u000Ab\u000A\u000Ac\u000A",[0,8]]`, and the 1-minimal input `"\u000D\u000A"`.
It also fails case 10 (N1 and N6 one code unit per chunk), case 11, case 13 set B on S1, and case 13 set P on P21, and case 14, whose uninjected harness check found a mismatch.

Case 14 leaked its unexpected report in that failure path, which the run reports as 4 leaks.
The test now frees and prints the report before it fails, and runs 2 and 3 of `raw/tests-after.log` ran after that fix.
The mutation ran before amendment 1, which changed no tokenizer source; it changed only how the entity table reaches the module.

## Stop-rule observations

None.

- Every frozen expected value of cases 4 to 26 holds against the implementation of the cited state text, so no case stopped.
- The 84 `<h5>` headings between "Tokenization" and "Tree construction" in the frozen `source` equal the frozen heading list, and the §13.2.2 table has the 52 codes in the frozen order.
- The entity counts are 2231, 106, and 93.

## Resolved ambiguities

- The contract says that `<commit>` of the license is the `main` commit at import time, and evidence item 3 says the frozen commit.
  `git ls-remote` reported `877d614`, not `efc54f7`.
  The provenance records the frozen commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, and the comparison fetch shows the `LICENSE` at `877d614` is byte-identical.
- `standard_last_updated` is `9 October 2026`, the date that the multipage standard showed at retrieval.
  It is later than the frozen text of 7 October 2026; the tokenizer follows the frozen commit, and `entities.json` was last modified on 12 November 2025.
- Network access: besides `entities.json` and `LICENSE`, the worker fetched the multipage index for `standard_last_updated`, ran `git ls-remote` for `<commit>`, and fetched `LICENSE` at `877d614` for the comparison above.
  All of these are recorded in `raw/entities-fetch.log` and `raw/license-fetch.log`.
- The spec source comments out the rows of the §13.2.5.84 table for 0x0D, 0x81, 0x8D, 0x8F, 0x90, and 0x9D, which map to themselves.
  The table therefore has 27 rows, and those numbers take the branch "control or 0x0D not in the table", which R2 executes.
- The token dump merges characters before it drops error lines, so a parse error between two character runs leaves two `Character` lines.
- `feed` after `finish` returns `error.InputFinished` even while a chunk is borrowed.
- Lookahead peeks raw code units and never reports preprocessing errors.
  Every character that a lookahead matches is an ASCII letter, digit, `-`, `[`, or `;`, so a CR or surrogate at the end of the available input ends a match either way.
- The after DOCTYPE name state consumes the current input character, with any preprocessing error, before it looks ahead.
  When the input does not decide the six characters, it returns `need_input` and later reconsumes that character, so the error is reported once.
- With a foreign adjusted current node, the markup declaration open state consumes `[CDATA[` and then returns `error.UnimplementedState`. This is not observable.
- The tokenizer returns pending characters as a step once they reach 4096 code units, which bounds its character buffer. The dump merges such runs.
- Before amendment 1, the FP-0011 compile-fail commands needed the generated import, because `zig build-obj` loads every file that `src/root.zig` imports. After amendment 1 they are unchanged from the base.
- Each `decode` and `tokenize` stage record writes every member, with `null` for members that the stage did not reach.
  An `unsupported` outcome at `decode` has a detail without a subject, so it equals the stage's `detail`.
- A harness error reports the stage that it interrupted: `fetch`, `decode`, or `tokenize`.
- The pinned compiler has no `**` operator, so the tests build repeated characters with `@splat`.
- `node tools/fairpane.mjs test` in `raw/checks-attempt-1.log` ran concurrently with run 2 of `raw/tests-after.log`.
  The final `raw/checks-after.log` ran after run 3 finished.

## Amendment 1

The original contract required the anonymous build import `html_entities`.
`node tools/fairpane.mjs test` then failed "The actual bootstrap repository passes its integrity check" with `Unapproved module import in src/html/entities.zig: html_entities`, because `engineering/dependencies.json` allows only `std`, `builtin`, and `root`.
`raw/checks-attempt-1.log` keeps that failed run.

The integrator's amendment 1 (commit `bcbe5a4` on `master`) resolved it without changing the lint:

1. `src/html/entities_gen.zig` generates `src/html/entities_table.zig`, and `zig build entities-generate` writes it into the source tree through `addUpdateSourceFiles`.
   `raw/entities-generate.log` records the run, and the output is committed with this patch.
2. `src/html/entities.zig` imports `entities_table.zig` by relative path, and `build.zig` has no `html_entities` import.
3. Case 3 parses the embedded `entities.json` and compares it with the committed table, so a stale table fails the tests.
   The generator writes its output already in `zig fmt` form, so `zig fmt --check` covers the committed file unchanged.
4. The `derived` object of `entities.provenance.json` names the generator and the generated file `src/html/entities_table.zig`.
5. `entities.LICENSE` already came from the frozen commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, so no refetch was needed.
   The fetch at `877d614` only wrote a comparison copy under `out/`, and both digests are recorded in `raw/entities-digest.log`.
