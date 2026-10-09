# FP-0082 evidence

This directory holds the worker evidence for `FP-0082`, "Parse a bounded script grammar with sound syntax-error accounting".
The frozen contract is `CONTRACT.md` with amendment 1 (`7ffafd3`) and amendment 2 (`41aaa7e`), and revision 1 below.
The worker `FP0082Parser` produced this evidence in an isolated worktree, and the integrator commits it.

## Binding

- The red baseline ran at `HEAD` `a3e5cf9`, the commit that froze the contract.
  `raw/tests-before.log` records that `HEAD`, the `git add` staging command, and the blob ID of every staged test file.
- Amendment 1 landed as `7ffafd3` while the work was in progress.
  The worktree moved to `7ffafd3` with `git stash` and `git stash pop`, and every later log ran at that `HEAD`.
  The commits between the two bases change no file that this task changes, except `tools/selftest.mjs` and `tools/fairpane.mjs`, which merged without conflict.
- `raw/tests-after.log` records `HEAD`, an empty `git diff --stat`, and `git ls-files -s` for every changed source before the run.

## Changed files

| File | Change |
| --- | --- |
| `src/js/lexer.zig` | New. Tokenizer over UTF-16 code units. |
| `src/js/ast.zig` | New. Syntax tree, function records, declaration lists, and a dump writer with an explicit stack. |
| `src/js/parser.zig` | New. `parseScript` as an explicit-stack machine, early errors, the code tables, and cases 1 to 14. |
| `src/js/test262_metadata.zig` | New. Frontmatter reader and case 15. |
| `src/js/parse_census.zig` | New. The census. |
| `src/js/parse_main.zig` | New. The `fairpane-js-parse` executable root. |
| `src/js/runtime.zig` | Its `test` block imports the new files. |
| `src/js/value.zig` | FP-0011 case 20 lists the six new files (case 19). |
| `build.zig` | The `js-tools` step and cases 16 and 17. |
| `tests/js/parse/*`, `tests/js/census/{sound,unsound}/**` | Command-line and census fixtures. |
| `tools/corpus.mjs`, `tools/fairpane.mjs`, `tools/README.md` | `corpus-extract` and its documentation. |
| `tools/selftest.mjs` | Case 18. |

## Logs

| Log | Command | RESULT exit codes |
| --- | --- | --- |
| `raw/tests-before.log` | `git rev-parse HEAD`, `git add`, `git ls-files -s`, `zig build test --summary all --cache-dir out/fp0082-before` | 0, 0, 0, 1 (red: the implementation is absent) |
| `raw/tests-attempt-1.log` | The FP-0082 cases on the recursive-descent implementation | 0, 1 |
| `raw/stack-recursive.log` | Stack probe on the recursive-descent implementation | 0 for every command |
| `raw/stack-explicit.log` | Stack probe on the delivered implementation | 0 for every command |
| `raw/corpus-verify.log` | `node tools/fairpane.mjs corpus-verify test262` | 0 |
| `raw/extract.log` | `node tools/fairpane.mjs corpus-extract test262 out/fp0082-test262` | 0 |
| `raw/census-attempt-1.log` | Census with a development build before the mutation controls | 0 |
| `raw/oracle-v8.log` | `node --version`, `node raw/oracle-v8.mjs` | 0, 0 |
| `raw/mutation.log` | Controls M1 to M8 | See "Mutation controls" |
| `raw/tests-after-attempt-1.log`, `raw/fmt-attempt-1.log`, `raw/js-tools-build-attempt-1.log`, `raw/harness-parse-attempt-1.log`, `raw/census-attempt-2.log` | The final sequence before the last source change | Each matches its final log below |
| `raw/tests-after.log` | `cmd /d /c ver`, binding commands, removal of `out/fp0082-after`, `zig build test --summary all --cache-dir out/fp0082-after` | 0 for every command |
| `raw/fmt.log` | `zig fmt --check build.zig src tests` | 0 |
| `raw/controller-tests-after.log` | `node --version`, `node tools/fairpane.mjs test` | 0, 0 |
| `raw/js-tools-build.log` | `zig build js-tools -Doptimize=ReleaseSafe --summary all` | 0 |
| `raw/harness-parse.log` | `git hash-object` of five harness files, then `fairpane-js-parse file` on each | 0; 0, 0, 0, 0, 2 |
| `raw/census.log` | Removal of an earlier `out/fp0082-census.jsonl`, `git hash-object` of the tool and `EXTRACT.json`, the census, and `certutil -hashfile` | 0, 0, 0, 0 |

Every Zig command ran with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler.
Development compilations and test runs during implementation were not recorded.
The first stack measurement that the worker reported to the integrator came from such an unrecorded probe; `raw/stack-recursive.log` reproduces it with the same numbers.

## Results

- `raw/tests-after.log`: 78 of 78 build steps succeeded, and 315 of 315 tests passed: 270 in the library test binary and 45 in the text test binary.
  All 15 FP-0082 Zig cases, case 19, and the nine command-line and census run steps of cases 16 and 17 pass.
- `raw/controller-tests-after.log`: 216 of 216 controller tests passed, including the four case 18 tests.
- `raw/oracle-v8.log`: Node v26.7.0 disagrees with the contract only on E54, E55, and E56, which the contract allows.
  It checks 55 case 2 rows and 117 case 6 rows; the 75 case 7 rows are for information only.
- `raw/harness-parse.log`: the five harness blobs match the contract's blob IDs.
  `assert.js`, `sta.js`, `doneprintHandle.js`, and `compareArray.js` exit with status 0.
  `propertyHelper.js` exits with status 2 and prints `unsupported array_literal @2981`.
- `raw/extract.log`: `files` is 53,975, and `entries_sha256` is `95f65b6c7dc3617d92648f5b9fc65b2d1e6236f1eed0763a1038f8235943a1f1`.

### Census

`raw/census.log` reports this summary and exits with status 0.
The SHA-256 of `out/fp0082-census.jsonl` is `0e5277cd3bad6676e588dd11e196231c95069088f45aa5e993eb947a962148c7`.

```json
{"summary":{"discovered":53616,"module":843,"proposal_files":2450,"runs":102151,"agree_valid":28777,"agree_error":1949,"unsupported":71421,"limit":0,"proposal_mismatch":4,"false_accept":0,"false_syntax_error":0,"metadata_error":0,"input_error":0},"unsupported_by_code":{"arguments_object":1165,"array_literal":11226,"arrow_function":2547,"async_function":4436,"bigint_literal":748,"block_function_declaration":333,"class":14850,"coalesce":66,"default_parameter":129,"destructuring_assignment":210,"destructuring_binding":1226,"for_in":757,"for_of":318,"generator":3811,"import":822,"lexical_declaration":20544,"logical_assignment":130,"method_definition":4030,"new_target":62,"non_ascii_identifier":178,"object_spread":126,"optional_chain":19,"regular_expression":2731,"rest_parameter":41,"spread":78,"super":16,"template":480,"using_declaration":100,"with":242}}
```

The four proposal mismatches are the two `decorator-*-identifier-reference-yield.js` files under `test/language/expressions/class/decorator/syntax/valid/` and the two under `test/language/statements/class/decorator/syntax/valid/`, run once each, in non-strict mode, because the files are flagged `noStrict`; they are decorator proposal tests, and `@` is an `invalid_character`.
The census is a parse-only soundness check.
It executes no test, and it is not a Test262 result.

## Criterion mapping

| Plan criterion | Evidence |
| --- | --- |
| Parse UTF-16 source with the Script goal over the frozen subset into a tree with strictness, declaration lists, and source ranges | Cases 2 to 5, 9, and 16 in `raw/tests-after.log` |
| Report unsupported constructs with owners, and syntax errors only where the full grammar rejects the source | Cases 1 and 6 to 9; M2 and M3; `raw/census.log`; `raw/oracle-v8.log` |
| Bound depth, length, and memory, and survive allocation failure and random input | Cases 10 to 14; M5 and M8; `raw/stack-explicit.log` |
| Parse-only census with zero accepted negative tests and zero false syntax errors | Cases 15 and 17; `raw/census.log`; M2 and M3 |
| Extract only from the verified snapshot with blob-ID checks | Case 18; `raw/corpus-verify.log`; `raw/extract.log`; M7 |

## Mutation controls

Each control is a `raw/mutation-<control>.diff` that `git apply` applied and `git apply -R` reversed.
`raw/mutation.log` records `HEAD`, the file's blob ID before, after applying, and after reversing, and every run.
Every reversal restored the original blob ID, and no control crashed.

| Control | Mutation | Named case | Observed |
| --- | --- | --- | --- |
| M1 | The lexer treats U+2028 as white space. | Cases 2 (T31) and 14 | Case 2 fails on row `T31 LS`. Case 14 passes. See "Unmet criteria". |
| M2 | The strict check for a LegacyOctalIntegerLiteral is removed. | E19 and a census `false_accept` | Case 6 fails on E19, E20, E21, and E22. The census reports `false_accept` 10 and exits with status 1. |
| M3 | `=>` reports `syntax-error unexpected_token`. | U16 and a census `false_syntax_error` | Case 7 fails on U16. The census reports `false_syntax_error` 195 and exits with status 1. |
| M4 | The HTML-like comment handling is removed. | T26 and T27 | Case 2 fails on T26, T27, and the four T29 rows. |
| M5 | The depth checks use `>=` instead of `>`. | Case 10 | Case 10 fails with `TestExpectedScript`: the accepted inputs give `limit depth`. |
| M6 | functions-to-initialize iterates forward. | T8 | Case 2 fails on T8. |
| M7 | `corpus-extract` skips the blob-hash check. | Case 18 | The case 18 test of an altered stored blob fails; 215 of 216 controller tests pass. |
| M8 | Amendment 1: one recursive native call per parenthesized expression. | Case 10 | Case 10 fails with `TestStackExceeded`: the run used at least 1,030,968 bytes of its 1 MiB stack. |

M7 alters a blob as the contract describes: the test overwrites a loose object file with another blob's object file after the tree lists it, and Git reads the other content under the listed ID.

## Stop rules

- Case 10 stack (amendment 1).
  The recursive-descent implementation overflowed the 1 MiB stack in the Debug test build.
  `raw/stack-recursive.log` measures it by painting the thread's stack and reading the high-water mark after a parse and a `writeOutcome`.
  It used 3,824 bytes per nested parenthesis, so the largest passing input had 262 parentheses, at depth 265.
  Other shapes used 3,856 (`a(`), 3,456 (`a[`), 1,376 (`{`), 1,152 (`if (a) `), 7,984 per three levels (`({a:`), and 10,032 per three levels (`(function(){`) bytes.
  The integrator chose option A in amendment 1.
  The delivered parser keeps every procedure's state in a heap stack of frames, and the writer walks the tree with a heap stack of one frame per tree level, which was `Parse.write_stack` before revision 1.
  `raw/stack-explicit.log` measures 20,832 to 21,968 bytes for every shape at 50 and at 100 repetitions, so native stack use does not grow with depth.
  Case 10 in `raw/tests-after.log` measures 21,232 bytes for 1,022 terms and 21,152 bytes for 1,021 parentheses.
  `max_depth` stays 1024, and the procedure frames count against `max_memory_bytes`; before revision 1, the write stack did too.
- Thread stacks on Windows: the pinned `std.Thread.spawn` passes `stack_size` to `NtCreateThreadEx` as the stack size and leaves the maximum stack size at its default (`lib/std/Thread.zig`), so the reserved stack may exceed 1 MiB.
  Cases 10 and 11 therefore also paint the stack and fail when a run reaches the last 32 KiB of the 1 MiB, so they do not depend on the reserve.
- Census: `raw/census-attempt-1.log` and `raw/census.log` report no `false_accept`, `false_syntax_error`, `metadata_error`, or `input_error`.
- Totals: `discovered` is 53,616, `module` is 843, and `files` in `EXTRACT.json` is 53,975.
- Oracle: V8 disagrees only on E54, E55, and E56.
- Contract defects: the worker reported row T32 `a⏎(b)` of case 2 and row T30 of case 9; amendment 1 corrects both.
  `raw/tests-attempt-1.log` shows both failures under the frozen text, and the delivered tests follow amendment 1.

## Attempts

- `raw/tests-before.log`: the red baseline; the build fails because the implementation is absent.
- `raw/tests-attempt-1.log`: the recursive-descent implementation at the frozen text.
  Cases 2 (T32 call) and 9 (T30 and T32 call) fail on the two contract defects, and cases 10 and 11 fail on the stack.
  Amendment 1 resolved all three causes.
- `raw/census-attempt-1.log`: a census with a development build before the mutation controls.
  It reports the same summary as `raw/census.log`.
- `raw/tests-after-attempt-1.log`, `raw/fmt-attempt-1.log`, `raw/js-tools-build-attempt-1.log`, `raw/harness-parse-attempt-1.log`, and `raw/census-attempt-2.log`: the final sequence at an earlier `src/js/parser.zig`, blob `a6246a6`.
  Every command exited as its final log does, and the census output had the same SHA-256.
  The worker abandoned them after replacing the module comment of `src/js/parser.zig`, which still described recursion, and removing an unused `Locals` variant.
  The final logs ran at the changed blob that `raw/tests-after.log` records.
  `raw/mutation.log` ran its controls at blob `a6246a6`; every diff still applies to the final files (`git apply --check`).

## Resolved ambiguities

- Before revision 1, E96 expected `()` to report `unexpected_token` at `)`, and the parser reported that offset when no `=>` followed.
  Revision 1 replaces this: after `( )` or `( Expression , )`, a token other than `=>` reports `unexpected_token` at that token, the end of the input reports `unexpected_end` at the source length, and `=>` reports `unsupported arrow_function` at `=>`.
- Assignment-target and update-target errors are detected when the assignment or update expression completes, after its right operand.
- A duplicate label is detected when the inner labelled statement completes; an undefined `break` or `continue` target when that statement completes.
- A Use Strict Directive in a function body reports the first error in source order among the function's name, its parameters, and the earlier directives.
- A duplicate `__proto__` is a cover-grammar error, like a CoverInitializedName, because both are valid in an ObjectAssignmentPattern (13.2.5.1).
  The error waits through parentheses that `=>` may follow, through a `for` head that `in` or `of` may follow, and through the Arguments of a call of `async`.
- Every `=>` that is not after `async (...)` reports `arrow_function`.
  `async (...) =>` reports `async_function` at `async`.
- Template, `?.`, `??`, `&&=`, `||=`, and `??=` tokens report their unsupported code when they become the current token.
- After `let` at a statement start, an IdentifierName written with escapes counts as an Identifier, so `let \u0069f` is unsupported.
- A non-ASCII code point after a numeric literal or after `#` reports `unsupported non_ascii_identifier` at that code point.
- `limit memory` and `limit depth` report the offset of the current token.
  `max_memory_bytes` bounds the bytes outstanding from `gpa` during the parse: the arena's buffers, the procedure frames, the scratch lists, and the duplicate-parameter set.
- Since revision 1, `writeOutcome` allocates its write stack, one frame per tree level, from the allocator that `parseScript` received, and frees it before it returns; `Parse` records only the tree height.
  The write stack therefore no longer counts against `max_memory_bytes`, and `writeOutcome` can return `error.OutOfMemory`.
- Case 13 joins the five sources with LF.
  Case 14's alphabet is the printable ASCII characters other than the space, plus the nine listed code units.
- The census reads the proposal section of `features.txt` between the exact headings `## Proposed language features` and `## Standard language features`, because `##` lines also occur inside the section.
  It counts `proposal_files` among non-module files with readable metadata.
  Violation lines on standard output cover `false_accept`, `false_syntax_error`, `metadata_error`, and `input_error`.
- `lexer.zig` writes the `kw_export` table entry with its tag first, because the FP-0011 case 20 needle `export ` would otherwise match `.kw_export }`.

## Criteria resolved by amendment

- M1 does not fail case 14.
  Case 14 asserts only that every source yields an outcome and that `writeOutcome` succeeds without a panic or a leak.
  Treating U+2028 as white space changes outcomes but causes no panic and no leak, so no implementation of case 14 as frozen can fail under M1.
  M1 does fail case 2 on row `T31 LS`.
  Contract amendment 2 (`41aaa7e`) names only case 2 for M1, so this control now meets the contract.

## Remaining obligations

Each unsupported code names its owner in the contract.
`FP-0083` owns function name inference, the B.3.9 ReferenceError, and Function.prototype.toString from the recorded source ranges.

## Integration

The integrator applied the worker's own patch `out/fp0082.patch` (blob `71da06ed`, base `7ffafd3`) from the worker's worktree.
It applied without conflicts and changed no contract text.
An earlier attempt applied the harness's captured patch instead.
That patch also carried changes from commits after the worker's base, so the integrator reset the uncommitted index and work tree to `41aaa7e` before applying the worker's patch.
The implementation is commit `5d41509`.

- `raw/integration-binding.log` records `HEAD` `5d41509` and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T15-05-28-163Z-repo-check-bcee3391.json`, `gates/2026-10-09T15-05-28-539Z-controller-test-6a1da2e8.json`, `gates/2026-10-09T15-06-23-120Z-zig-fmt-ff858d4c.json`, and `gates/2026-10-09T15-06-23-420Z-zig-test-b22cbcf7.json` pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0082-integration`: 94 of 94 build steps and 321 of 321 tests pass.
- `raw/bun-selftest.log` records Bun and `tools/selftest.mjs` with 224 of 224 tests.
- `raw/integration-steps.log` records `HEAD` `5d41509` before evidence steps 6 to 10 are rerun.
- `raw/integration-js-tools-build.log` builds `js-tools` in ReleaseSafe with exit status 0.
- `raw/integration-corpus-verify.log` verifies the Test262 snapshot with exit status 0.
- `raw/integration-extract.log` extracts 53,975 files at `2e0a56762801e275a9fdf96dc49d90ba0cddcf63` with `entries_sha256` `95f65b6c…`, the same as `raw/extract.log`.
- `raw/integration-harness-parse.log` parses `assert.js`, `sta.js`, `doneprintHandle.js`, and `compareArray.js` with exit status 0, and `propertyHelper.js` exits with status 2 and `unsupported array_literal @2981`.
- `raw/integration-census.log` reproduces the worker's summary exactly: 53,616 discovered, 843 module, 102,151 runs, 28,777 `agree_valid`, 1,949 `agree_error`, 71,421 `unsupported`, 4 `proposal_mismatch`, and 0 `limit`, `false_accept`, `false_syntax_error`, `metadata_error`, and `input_error`.
  The census file's SHA-256 is `0e5277cd…`, the same as in `raw/census.log`.
- `raw/integrator-metadata-counts.log` counts the pinned commit's metadata with a Node script that shares no code with the Zig census.
  The script lists `test/` files that end in `.js` and whose names lack `_FIXTURE`, reads each blob from the snapshot repository, and parses the frontmatter `flags` and `negative` keys itself.
  It counts 53,616 discovered files, 843 module files, and 4,455 files outside modules with `negative.phase` `parse`.
  A second script counts the census file's records: 53,616 records, 843 with `module` true, and 4,455 with `expect` `syntax-error`.
  The counts are equal.

## Revision 1

The worker `FP0082Revision1` produced this revision in an isolated worktree at `HEAD` `a695d51`, the commit that froze revision 1.
`raw/binding-r1.log` shows that `a695d51` differs from `5d41509` under `src`, `tools`, `build.zig`, and `tests` only in `build.zig`, `src/lab_main.zig`, and `tests/lab`, so every FP-0082 file under `src`, `tools`, and `tests` at the base equals its `5d41509` blob.
[INFERENCE] The `build.zig` changes touch only the laboratory steps; the worker read that diff without recording it.
The integrator decided during the work that case 3 alters the `test/` subtree instead of the root tree; see "Case 3 fixture".

### Changes

| File | Change |
| --- | --- |
| `tools/lib.mjs` | New `relativePathProblem`, the one path rule, with the reasons and the order of revision 1, and the reserved device names that moved from `tools/rust.mjs`. |
| `tools/rust.mjs` | `acceptedArchivePath` returns whether `relativePathProblem` gives null; its results and the message `The archive path is not accepted: <name>` are unchanged. |
| `tools/corpus.mjs` | `extractPathProblem` is removed. Before it creates anything, `extractCorpus` compares the commit's tree with `tree` in the record, recomputes the inventory with `computeInventory` and compares its three fields, applies `relativePathProblem` to each written path, and checks that each resolved file path starts with the output directory and a separator. `corpus-verify` and extraction share `expectRecorded`, which writes the `<field>: recorded <a>, found <b>` lines. |
| `tools/selftest.mjs` | Cases 2 and 3: a unit test of the rule, eight hostile-path tests, and the altered-tree and record-tree tests. The existing path-rule test calls `lib.relativePathProblem`. The blob-hash test (M7) also writes the altered objects' inventory into the record, so that only the blob-hash check can find the alteration. |
| `tools/README.md` | `corpus-extract` names its checks. |
| `src/js/parser.zig` | E96 and E96a to E96c; the linear duplicate-parameter check with `ParamSet` and the test-only counter `Parser.duplicate_comparisons`; `arrowParametersOnly`; `writeOutcome` allocates the write stack; the 12.10.1 comment; the new case 4. |
| `src/js/lexer.zig` | The module comment; `keywordOf` through buckets by length and first letter, built at compile time; `scanNumber` passes the source slice unless the literal is a LegacyOctalIntegerLiteral or has a separator, which `scanDigits` now records. |
| `src/js/parse_main.zig` | A failed `writeOutcome` prints its error name and exits with status 3. |
| `src/js/test262_metadata.zig` | The case 5 row and its reason. |

`writeOutcome` keeps its parameters and now returns `WriteError`, which adds `error.OutOfMemory`.
Case 13 therefore also induces the failure of the write-stack allocation.

### Revision 1 logs

| Log | Commands | RESULT exit codes |
| --- | --- | --- |
| `raw/tests-before-r1.log` | `git rev-parse HEAD`, `git add`, `git ls-files -s`, a mistyped `zig build test`, `zig build test --summary all --cache-dir out/fp0082-before-r1`, `zig test` filtered to case 6, case 15, and revision 1 case 4, `node --version`, `node tools/fairpane.mjs test` | 0, 0, 0, none (see below), 1, 1, 0, 1, 0, 1 |
| `raw/tests-before-subtree-r1.log` | `git rev-parse HEAD`, `git archive` of `a695d51`, `mkdir`, `tar -xf`, the copy of the revised `tools/selftest.mjs` into that tree, `git hash-object`, `git rev-parse`, and the controller suite there | 0, 0, 0, 0, 0, 0, 0, 1 |
| `raw/probe-subtree-r1.log` | `git rev-parse HEAD`, `git hash-object` of `raw/probe-subtree-r1.mjs`, the probe | 0, 0, 0 |
| `raw/binding-r1.log` | `git diff --stat 5d41509 a695d51 -- src tools build.zig tests` | 0 |
| `raw/census-r1.log` | Binding commands, `zig build js-tools -Doptimize=ReleaseSafe`, an extraction without the corpora directory, then `git rev-parse HEAD`, the extraction with `FAIRPANE_CORPORA_DIR`, `git hash-object` of the tool and `EXTRACT.json`, the census, and `certutil -hashfile` | 0, 0, 0, 1, 128, 3, 2147942402 (see below); then 0, 0, 0, 0, 0 |
| `raw/mutation-r1.log` | `git apply --check` of M1 to M12 and of the regenerated M7, then each control | See "Revision 1 mutation controls" |
| `raw/tests-after-r1.log` | `cmd /d /c ver`, `git rev-parse HEAD`, `git diff --stat`, `git ls-files -s`, removal of `out/fp0082-after-r1`, `zig build test --summary all --cache-dir out/fp0082-after-r1` | 0 for every command |
| `raw/fmt-r1.log` | `zig fmt --check build.zig src tests` | 0 |
| `raw/controller-tests-after-r1.log` | `node --version`, `node tools/fairpane.mjs test` | 0, 0 |

Two logs hold a failed command that ran nothing useful, and they are kept as recorded, because no log is deleted or overwritten:

- `raw/tests-before-r1.log`: the fourth command passed the compiler path and the `ZIG_GLOBAL_CACHE_DIR` value without their backslashes, because the shell removed them. The record tool found no such executable, so no process ran and RESULT has no exit code. The next command is the intended run.
- `raw/census-r1.log`: the first `corpus-extract` ran without `FAIRPANE_CORPORA_DIR`, so it found no snapshot in the worktree and exited with status 1 before it created anything. The `git hash-object`, census, and `certutil` commands after it failed because the extraction was absent. The log then records `HEAD` again and the complete sequence with `FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, as `raw/extract.log` used. Only that second sequence is evidence.

### Red baseline

- `raw/tests-before-r1.log` stages `src/js/parser.zig`, `src/js/test262_metadata.zig`, and `tools/selftest.mjs` with cases 1 to 5 and records their blob IDs.
- `zig build test` fails to compile, because revision 1 case 4 names `Parser.duplicate_comparisons`, which the base lacks; 97 of 100 steps succeed.
- Case 1 fails on the base, and the filtered case 6 run records every row as it is: `()` gives `syntax-error unexpected_token @1`, `() + 1` gives `syntax-error unexpected_token @1`, `(a,)` gives `syntax-error unexpected_token @3`, and `(a,) + 1` gives `syntax-error unexpected_token @3`. No other case 6 row fails.
- Case 5 passes on the base, as the revision states.
- Case 4 does not compile on the base, because the counter is absent; M11 shows that the bound fails for a quadratic check.
- The controller suite fails 12 of 235 tests, all of them FP-0082 case 18 tests of this revision: both path-rule tests (`lib.relativePathProblem is not a function`), all eight hostile-path tests, the root-tree version of the altered-tree test, and the record-tree test.
  The old code already rejects none of the eight hostile paths: seven extractions succeed (`Missing expected rejection.`), and the control-character path fails while writing with `ENOENT`.
- `raw/tests-before-subtree-r1.log` runs the revised `tools/selftest.mjs` against a copy of the base tree under `out/fp0082-base-r1`, because case 3 changed after the red run.
  The subtree version of case 3 fails there with `Missing expected rejection.`: the base extracts the altered listing.
  13 of 235 tests fail: the same 12 FP-0082 tests, and attest-verify test 48, which requires the repository path to be the top level of a Git work tree and fails only because the copy is not one.

### Case 3 fixture

Revision 1 case 3 first replaced the loose object file of the commit's root tree.
Git 2.54.0.windows.1 rehashes that object when it reads it: in `raw/tests-before-r1.log`, extraction fails with `git ls-tree exited with status 128: error: hash mismatch …` and `fatal: not a tree object`, before any inventory comparison could run.
The worker reported this stop rule, and the integrator decided that case 3 alters the commit tree's `test/` subtree instead, with the same assertions.
`raw/probe-subtree-r1.log` shows both behaviors on a probe repository under `out/`: after the `test/` subtree's object file holds another tree, `git ls-tree -r` exits with status 0 and lists `test/a.js` and `test/b.js`; after the root tree's object file also holds another tree, it exits with status 128 with `error: hash mismatch` and `fatal: not a tree object`.

### Revision 1 results

- `raw/tests-after-r1.log`: 100 of 100 build steps succeed, and 322 of 322 tests pass; the integration run had 321 at `5d41509`, and revision 1 case 4 is the added test. Case 10 measures 21,120 bytes for 1,022 terms and 20,992 bytes for 1,021 parentheses.
- `raw/fmt-r1.log`: exit status 0.
- `raw/controller-tests-after-r1.log`: 235 of 235 controller tests pass, including FP-0079 case 5 unchanged and the 15 FP-0082 case 18 tests.
- `raw/census-r1.log`: the fresh extraction writes 53,975 files at `2e0a56762801e275a9fdf96dc49d90ba0cddcf63` with tree `6a4268a9354a545d41c3b62efebc478ed8c521f4` and `entries_sha256` `95f65b6c7dc3617d92648f5b9fc65b2d1e6236f1eed0763a1038f8235943a1f1`.
  The census summary equals the counts in "Integration": 53,616 discovered, 843 module, 2,450 proposal files, 102,151 runs, 28,777 `agree_valid`, 1,949 `agree_error`, 71,421 `unsupported`, 4 `proposal_mismatch`, and 0 `limit`, `false_accept`, `false_syntax_error`, `metadata_error`, and `input_error`.
  The census file's SHA-256 is `0e5277cd3bad6676e588dd11e196231c95069088f45aa5e993eb947a962148c7`, the same as in `raw/census.log`, so no census record changed.
- Case 4: both 10,000-parameter sources parse, both sources with `a0` repeated report `duplicate_parameter` at that `a0`, and each run stays within 20,000 comparisons.

### Revision 1 mutation controls

`raw/mutation-r1.log` first records `HEAD`, the blob IDs of the revised files, and `git apply --check` of every diff.
M1 to M6 and M8 apply to the revised files, so they are rerun unchanged.
`raw/mutation-M7.diff` no longer applies (`patch failed: tools/corpus.mjs:703`), so `raw/mutation-M7-r1.diff`, blob `8b44dfb5a238841c30eaa3f286cce2d94236c538`, removes the same two lines from the revised file; its `git apply --check` passes.
Each control then records `HEAD`, the file's blob ID before, after applying, and after reversing, and its runs.
Every reversal restored the revised blob ID, and no control crashed.

| Control | Mutation | Named case | Observed |
| --- | --- | --- | --- |
| M1 | U+2028 is white space. | Case 2 (T31) | Case 2 fails on `T31 LS`. |
| M2 | No strict check of a LegacyOctalIntegerLiteral. | E19, census `false_accept` | Case 6 fails on E19 to E22; the census reports `false_accept` 10 and exits with status 1. |
| M3 | `=>` reports `unexpected_token`. | U16, census `false_syntax_error` | Case 7 fails on U16; the census reports `false_syntax_error` 195 and exits with status 1. |
| M4 | No HTML-like comments. | T26, T27 | Case 2 fails on T26, T27, and the four T29 rows. |
| M5 | `>=` depth checks. | Case 10 | `TestExpectedScript`. |
| M6 | functions-to-initialize iterates forward. | T8 | Case 2 fails on T8. |
| M7 (`mutation-M7-r1.diff`) | No blob-hash check. | Case 18 | Only the blob-hash test fails; 234 of 235 pass. |
| M8 | One recursive native call per parenthesized element. | Case 10 | `TestStackExceeded`: at least 1,032,192 bytes of the 1 MiB stack. |
| M9 | The rule stops rejecting `\`. | Case 2, backslash row | The backslash row fails, because extraction then reports `test/..\..\..\x.js resolves outside the output directory.`; the unit test of the rule and FP-0079 case 5, which share the rule, also fail. |
| M10 | No inventory recomputation. | Case 3 | Only the altered-tree test fails; 234 of 235 pass. |
| M11 | Every pair is compared again. | Case 4 | `TestTooManyComparisons`: 49,995,000 comparisons for the first source. |
| M12 | An unknown phase reads as `parse`. | Case 5 | Case 15 fails with `TestExpectedMetadataError`. |

The census-dependent controls rebuilt `js-tools` in ReleaseSafe and wrote `out/fp0082-census-M2-r1.jsonl` and `out/fp0082-census-M3-r1.jsonl` from `out/fp0082-test262-r1`.
Review 1 found that `raw/mutation.log` had no recorded `git apply --check`, so the claim in "Attempts" that every diff still applied to the final files was never recorded at `5d41509`.
`raw/mutation-r1.log` records the check at the revised files, where M1 to M6 and M8 apply and M7 does not.

### Revision 1 notes

- [INFERENCE] The resolved-path check cannot fire while the path rule holds, because a path that passes the rule has no `..` component, no `\`, and no `:`; M9 shows that it stops the backslash escape when the rule is weakened.
- The hashed parameter set is emptied by removing the names that a check inserted, so a later check never pays for the capacity that an earlier, larger function left.
  [INFERENCE] Each removal compares about one name, and case 4's bound counts those comparisons too.
- The census file's SHA-256 equals the one in `raw/census.log`, so the E96 change altered no census run.

### Revision 1 integration

The integrator applied the worker's own patch `out/fp0082-r1.patch` (blob `aa77e387`, base `a695d51`) without conflicts and committed it as `9a68167`.

- `raw/integration-binding-r1.log` records `HEAD` `1a15063`, which contains `9a68167`, and a status that includes ignored files for every source root, before and after the runs below; both statuses are empty.
- `gates/2026-10-09T17-22-04-124Z-repo-check-c8cd2194.json`, `gates/2026-10-09T17-22-04-499Z-controller-test-6ac0f68c.json`, `gates/2026-10-09T17-23-21-279Z-zig-fmt-8c4aa033.json`, and `gates/2026-10-09T17-23-21-639Z-zig-test-51499c4c.json` pass.
- `raw/integration-tests-r1.log` runs `zig build test --summary all` with the fresh cache `out/fp0082-r1-integration`: 100 of 100 build steps and 322 of 322 tests pass.
- `raw/bun-selftest-r1.log` records Bun and `tools/selftest.mjs` with 236 of 236 tests.
- `raw/integration-protected-diff-r1.log` first records the diff of the protected paths and `specs` from `a3e5cf9` to `9a68167`, as the revision asks.
  It is not empty, because the range holds other tasks' commits: P1 `9fb8d8f`, P2 `2e07f89`, and FP-0052's `775d988`, as the log's `git log` lists.
  The same log shows that neither FP-0082 commit, `5d41509` or `9a68167`, changes a protected path or `specs`, and that `specs/applicability/test262.json` is unchanged across the range.
