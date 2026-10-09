# FP-0082 evidence

This directory holds the worker evidence for `FP-0082`, "Parse a bounded script grammar with sound syntax-error accounting".
The frozen contract is `CONTRACT.md` with amendment 1 (`7ffafd3`).
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

The four proposal mismatches are the two `decorator-*-identifier-reference-yield.js` files under `test/language/expressions/class/decorator/syntax/valid/` and the two under `test/language/statements/class/decorator/syntax/valid/`, in both modes; they are decorator proposal tests, and `@` is an `invalid_character`.
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
  The delivered parser keeps every procedure's state in a heap stack of frames, and the writer walks the tree with `Parse.write_stack`, one frame per tree level.
  `raw/stack-explicit.log` measures 20,832 to 21,968 bytes for every shape at 50 and at 100 repetitions, so native stack use does not grow with depth.
  Case 10 in `raw/tests-after.log` measures 21,232 bytes for 1,022 terms and 21,152 bytes for 1,021 parentheses.
  `max_depth` stays 1024, and the procedure frames and the write stack count against `max_memory_bytes`.
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

- E96 expects `()` to report `unexpected_token` at `)`.
  The parser reports that offset when no `=>` follows, and `unsupported arrow_function` at the `=>` when one does.
  A trailing comma inside parentheses works the same way.
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
  `max_memory_bytes` bounds the bytes outstanding from `gpa`: the arena's buffers, the procedure frames, and the scratch lists.
- `Parse` has a `write_stack` field, the scratch storage of `writeOutcome`; one thread at a time writes a Parse.
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
