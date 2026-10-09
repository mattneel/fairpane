# FP-0064 evidence

## Scope

Task `FP-0064` implements the text-content and CDATA tokenizer states that `CONTRACT.md` freezes.
The standard text is whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, file `source`, with SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
`raw/html-standard-text.log` records that digest.
The worker implemented the contract in an isolated working tree whose `HEAD` was `dfa6563` ("FP-0064: freeze the tokenizer states contract").
The host was Windows, x64, with the locked compiler `0.18.0-dev.120+9fe22a29b`.
Every Zig command ran with the override `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, which each `RESULT` line records.

The tokenizer now implements all 84 states of §13.2.5.1 to §13.2.5.84.
`states.branch_count` grew by 118, the branches of the 30 new states, and FP-0064 case 1 asserts that number.
`non-void-html-element-start-tag-with-trailing-solidus` is the only parse error code that the tokenizer does not raise.
Tree construction raises it, and it belongs to `FP-0010`.

## Changed files

| File | Change |
| --- | --- |
| `src/html/tokenizer.zig` | The 30 new states, `ContentState`, `SwitchError`, `switchTo`, the shared `Error` without `UnimplementedState`, the last start tag name, the appropriate end tag check, the CDATA bracket position, and the spans rules. `unimplementedState` and the `unimplemented` field are removed, and the sticky failure is the `failed` flag. The header and the `consumeMatched` comment are updated. |
| `src/html/states.zig` | The branch lists of the 30 new states. `implemented` and `owner` are removed. The header states that the tokenizer implements all 84 states. |
| `src/html/errors.zig` | `raisedByTokenizer` is false only for `non-void-html-element-start-tag-with-trailing-solidus`, and its doc comment says so. |
| `src/html/root.zig` | Exports `ContentState` and `SwitchError`. |
| `src/lab.zig` | The doc comment of `tokenize` says that the stage makes no `switchTo` call and leaves `adjusted_current_node_is_foreign` false. The stage's behavior is unchanged. |
| `src/html/tokenizer_test.zig` | `Setup`, the content driver (`contentState` and `drive`), `initWith`, `tokenizeChunks` with a final `setup` parameter, and the removal of `tokenizeChunksForeign`. The FP-0064 tables and cases 1 to 12 and 14 to 16, and the FP-0008 amendments. |
| `src/html/partition_test.zig` | The harness takes a `Setup`, and its report names the case. FP-0064 case 13 with set P, set B, and the state-coverage check. |

`build.zig` and `tests` are unchanged, because this task adds no laboratory case.

The new `consumeMatched` comment is exactly this line:

```zig
/// Consumes `count` characters that a lookahead matched. Each is an ASCII letter, an ASCII digit, `-`, `[`, or `;`, which preprocessing never reports.
```

## Records

| Log | Command | RESULT |
| --- | --- | --- |
| `raw/tests-before.log` | `git rev-parse HEAD` | `exit_code` 0: `dfa6563cff2a74d154681de99f42dce28a822f52` |
| `raw/tests-before.log` | `git status --short` | `exit_code` 0: only the two test files are modified |
| `raw/tests-before.log` | `git worktree add --detach out/fp0064-before-tests HEAD` | `exit_code` 0 |
| `raw/tests-before.log` | `cp` of both new test files into the staged tree | `exit_code` 0 |
| `raw/tests-before.log` | `git -C out/fp0064-before-tests status --short` | `exit_code` 0: only the two test files differ from `HEAD` |
| `raw/tests-before.log` | `git hash-object` of the new test files, their staged copies, and the staged base sources | `exit_code` 0 |
| `raw/tests-before.log`, run 1 | `zig build test --summary all --cache-dir out/fp0064-cache-before` in `out/fp0064-before-tests` | `exit_code` 1, 62 of 65 steps: the unit tests fail to compile |
| `raw/tests-before.log` | `git worktree add --detach out/fp0064-before-behavior HEAD` | `exit_code` 0 |
| `raw/tests-before.log` | `git hash-object` of the run 2 addition and the base `tokenizer_test.zig` | `exit_code` 0 |
| `raw/tests-before.log` | `node -e` that appends `out/fp0064-staging/run2-addition.zig` to the staged `tokenizer_test.zig` | `exit_code` 0 |
| `raw/tests-before.log` | `git -C out/fp0064-before-behavior status --short` and `diff` | `exit_code` 0, 0: the diff is the whole addition |
| `raw/tests-before.log` | `git hash-object` of every staged or tested file | `exit_code` 0 |
| `raw/tests-before.log`, run 2 | `zig build test --summary all --cache-dir out/fp0064-cache-before-behavior` in `out/fp0064-before-behavior` | `exit_code` 1, 63 of 65 steps, 272 of 274 tests |
| `raw/html-standard-text.log` | `sha256sum` of the pinned copy | `exit_code` 0: `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b` |
| `raw/html-standard-text.log` | `grep -n "<h5><dfn[^>]*>[^<]* state</dfn></h5>"` | `exit_code` 0: 84 headings |
| `raw/html-standard-text.log` | `grep -n -i -E "(switch\|leave) the tokenizer"` | `exit_code` 0: 13 lines |
| `raw/html-standard-text.log` | `grep -n -i -E` for `parser</span>'s tokenizer` and the generic algorithms | `exit_code` 0: the sentences that the previous pattern misses |
| `raw/html-standard-text.log` | `sed -n` of lines 114100 to 114106, 145798 to 145808, and 150765 to 150794 | `exit_code` 0: the wrapped sentences in full |
| `raw/tests-attempt-1.log` | `zig build test --summary all --cache-dir out/fp0064-cache-dev` | `exit_code` 1, 285 of 286 tests: Q11's frozen length. Kept as a failed attempt. |
| `raw/fmt-attempt-1.log` | `zig fmt --check build.zig src tests` | `exit_code` 0 |
| `raw/tests-attempt-2.log` | The same test command after the harness change below | `exit_code` 1, 285 of 286 tests: Q11's frozen length only. Kept as a failed attempt. |
| `raw/tests-after.log` | `zig build test --summary all --cache-dir out/fp0064-cache-after`, uncached, after amendment 1 | `exit_code` 0, 65 of 65 steps, 286 of 286 tests |
| `raw/tests-after.log` | `git hash-object` of the changed sources and `build.zig` | `exit_code` 0 |
| `raw/mutation-temp-release.log` | `cp src/html/tokenizer.zig out/fp0064-tokenizer.fixed.zig` and `git hash-object` of both | `exit_code` 0, 0: both are `b148d4a` |
| `raw/mutation-temp-release.log` | `git diff --no-index out/fp0064-tokenizer.fixed.zig src/html/tokenizer.zig` | `exit_code` 1, because the files differ |
| `raw/mutation-temp-release.log` | The same diff with `--output=engineering/evidence/FP-0064/raw/mutation-temp-release.diff` | `exit_code` 1 |
| `raw/mutation-temp-release.log` | `git hash-object src/html/tokenizer.zig` of the mutant | `exit_code` 0: `5e40285` |
| `raw/mutation-temp-release.log` | `zig build test --summary all --cache-dir out/fp0064-cache-mutation` | `exit_code` 1, 63 of 65 steps, 271 of 286 tests |
| `raw/mutation-temp-release.log` | `cp out/fp0064-tokenizer.fixed.zig src/html/tokenizer.zig` | `exit_code` 0 |
| `raw/mutation-temp-release.log` | `git diff --no-index --exit-code` of the saved and restored files | `exit_code` 0 |
| `raw/mutation-temp-release.log` | `git hash-object src/html/tokenizer.zig` after the restoration | `exit_code` 0: `b148d4a` |
| `raw/checks-after.log` | `zig fmt --check build.zig src tests` | `exit_code` 0 |
| `raw/checks-after.log` | `node tools/fairpane.mjs test` | `exit_code` 0, 192 of 192 controller tests |

`raw/mutation-temp-release.diff` holds the exact diff of the mutation control.
`raw/integrator-switch-points.log` is the integrator's record, made before this work.

### tests-before

Both runs used a checkout of `HEAD` `dfa6563` that `git worktree add` created under `out/`.
The runs show base behavior because the `git hash-object` records in `tests-before.log` show the base sources in those checkouts, not because of when the first implementation edit happened; no log records that time.
Run 1 started at 12:43:13Z and took 7 seconds.
Run 2 started at 12:43:32Z and ended at 12:46:42Z.

1. Run 1 adds the new `tokenizer_test.zig` (blob `9097834`) and `partition_test.zig` (blob `669dc6b`) to the base sources.
   It fails to compile with three errors, as expected: `tokenizer.ContentState`, `tokenizer.SwitchError`, and `Tokenizer.switchTo` do not exist.
   The new `Setup` is declared with `ContentState`, so it cannot compile either.
2. Run 2 keeps the base sources and appends one block to the base `tokenizer_test.zig`, which the recorded `git diff` shows.
   The block runs K1, CD1 to CD6, Q9 to Q12, and the flag-true part of case 15, whole and split at offset 6, through the base helper `tokenizeChunksForeign`.
   Both added tests fail with `error.UnimplementedState`: the first reports it for each of its 11 inputs, and the second returns it from `next`.
   Every other test passes, 272 of 274.

After run 1, `tokenizer_test.zig` did not change; its final blob is still `9097834`.
`partition_test.zig` changed twice after run 1, to blob `de45539`: the harness change and amendment 1 below.

## Acceptance

- Every FP-0064 case from 1 to 16 has a test whose name carries its number.
  FP-0008 cases 1, 2, 11, and 16 are renamed "FP-0008 case 1 and FP-0064 case 1", "FP-0008 case 2 and FP-0064 case 2", "FP-0008 case 11 and FP-0064 case 11", and "FP-0008 case 16 and FP-0064 case 15".
  FP-0008 case 4 keeps its table and its whole and one-unit checks, and its "names every raised code" assertion moved to FP-0064 case 3 over both catalogs.
- Every other FP-0008 case, every FP-0007 case, and every FP-0054 case passes unchanged in `raw/tests-after.log`, including FP-0008 cases 18 to 26 and the FP-0007 and FP-0054 laboratory steps.
- Case 11's counters are nonzero for every branch of all 84 states.
  Case 13's coverage test shows that the set P inputs, each run once as one chunk, execute all 30 new states.
- `branch_count` equals the sum of the branch list lengths, and the 30 new states have 118 branches.
- Case 16 checks, for each induced failure, that `next`, `feed`, `finish`, and `switchTo` return `error.OutOfMemory` again, and that the backing allocator's `allocated_bytes` equals its `freed_bytes`.

## Tree-construction switch points

`raw/html-standard-text.log` and `raw/integrator-switch-points.log` record each switch point at the pin.
Each one names RCDATA, RAWTEXT, script data, or PLAINTEXT, or leaves the data state, so `ContentState` covers all of them.

| Line | Sentence | State |
| --- | --- | --- |
| 114105 to 114106 | Loading a `text/plain` document: "switch the HTML parser's tokenizer to the PLAINTEXT state" | PLAINTEXT, before the first token |
| 145805 to 145808 | The generic raw text and generic RCDATA element parsing algorithms | RAWTEXT or RCDATA |
| 146231 | "in head": a `title` start tag follows the generic RCDATA algorithm | RCDATA |
| 146238 | "in head": `noscript` with scripting enabled, `noframes`, and `style` follow the generic raw text algorithm | RAWTEXT |
| 146301 | "in head": a `script` start tag | script data |
| 147165 | "in body": a `plaintext` start tag | PLAINTEXT |
| 147585 | "in body": a `textarea` start tag | RCDATA |
| 147607 | "in body": an `xmp` start tag follows the generic raw text algorithm | RAWTEXT |
| 147614 | "in body": an `iframe` start tag follows the generic raw text algorithm | RAWTEXT |
| 147621 | "in body": `noembed`, and `noscript` with scripting enabled, follow the generic raw text algorithm | RAWTEXT |
| 150772 to 150793 | The fragment parsing algorithm: the context element sets the state, or leaves the data state | RCDATA, RAWTEXT, script data, PLAINTEXT, or data |

The pattern `(switch|leave) the tokenizer` misses these sentences:

- Line 114105 says "switch the `<span>HTML parser</span>`'s tokenizer", so markup separates the words.
- The seven call sites of the generic algorithms say "Follow the generic … element parsing algorithm".
  The integrator's log and the third command of `raw/html-standard-text.log` record them.
- The pattern finds lines 145806, 145807, 150786, and 150787, but their sentences wrap: "switch the tokenizer to" ends line 145807, and its state, "the RCDATA state", is on line 145808.
  The `sed` record shows each wrapped sentence in full.

Line 147169 matches the pattern, but it is a note: "there is no way to switch the tokenizer out of the PLAINTEXT state".

## Mutation control

The control makes `t.temp.clearRetainingCapacity();` the first statement of `Tokenizer.release`, so the temporary buffer is lost whenever `next` returns `need_input`.
It fails FP-0064 case 13 on input Q2, as required.

- Partition: `[0,8) [8,12)`, which splits `<xmp></x` from `mpa>`.
- Reference dump: `["StartTag","xmp",[],false,[0,5]]`, `["Character","</xmpa>",[5,12]]`, and `["EOF",[12,12]]`.
- Partition dump: `["StartTag","xmp",[],false,[0,5]]`, `["Character","</mpa>",[5,12]]`, and `["EOF",[12,12]]`.
- 1-minimal input: `"<xmp></a>"`.

The run fails 15 of 286 tests:

- FP-0008 case 4 (A4, A9, and A23 one code unit per chunk), case 8 (PI1, PI2, PI3, PI7, PI8, PI9, and PI10 one code unit per chunk), and case 9 (R4 one code unit per chunk).
  The processing instruction states and the numeric character reference states also keep progress in `temp`.
- FP-0064 case 4 (RC10, RC11, RC12, and RC14 one code unit per chunk, and RC13 whole), case 5 (RW3, RW4, and RW7 one code unit per chunk, and RW8 whole), case 6 (SD3 and SD4), case 7 (SE4 and SE5, and SE10 whole), case 8 (DE1, DE7, DE8, and DE11), and case 10 (L1, L2, L3, and L6).
  An input that ends inside an end tag name fails even whole, because the harness drains to `need_input` before it calls `finish`.
- FP-0008 case 11 and FP-0064 case 11, through the same table checks.
- FP-0064 case 12 on SP5.
- FP-0008 case 13: set P on P10 and P14, and set B on S1 and B4.
- FP-0064 case 13: set P on Q2, Q4, Q8, Q16, and SP1, and the expected dump of SP5; set B on RC11, RW3, SD3, SE4, SE5, DE1, DE7, DE8, L1, and L6.

The restored file is byte-identical to the saved fixed file, and `raw/tests-after.log` ran on that same blob `b148d4a`.

## Stop-rule observations

- Contract defect, FP-0064 case 13, input Q11: the frozen `Units` value was 13, but `<![CDATA[\uD83D\uDE00]]>` has 9 + 2 + 3 = 14 code units.
  `raw/tests-attempt-1.log` and `raw/tests-attempt-2.log` record the failure, and the expected tokens held.
  The worker reported it to the integrator and did not change the value on its own.
  Contract amendment 1, in integrator commit `ba759f7`, changes only Q11's `Units` to 14.
  The test applies amendment 1 and cites it in a comment.
- Every other frozen expected value holds against the implementation of the cited state text.
  No expected value contradicts the state text.
- The branch table of the 30 new states matches the pinned text: every listed branch exists, and no branch of the text is missing.
  The table's "otherwise" branches are the end tag name and double escape entries that say "treat it as per the anything else entry" or that compare the temporary buffer with "script".
- No switch point names a state outside `ContentState`.

## Resolved ambiguities

- After the Q11 failure, the harness reports a wrong input length and still runs that input's dump and partition checks.
  The wrong length still fails the test.
  Before, the length assertion stopped the whole set P test at the first wrong length, which hid the rest of the inputs.
- The harness report now begins with the case, such as "FP-0064 case 13 partition mismatch on input Q2", and otherwise keeps the FP-0008 format.
- `checkCase` takes a `Setup` through the `setup` field of `Case`, which holds a table's `Start` column, and FP-0008 rows use the default.
- The content driver calls `switchTo` after the dumper records the start tag, because a token's views stay valid only until the next call of any method.
- FP-0064 case 14 E9 also checks that a switch after a DOCTYPE, a comment, or a processing instruction is refused and changes no dump, as the call rules state.
- The last start tag name is empty before the first start tag, because a tag name is never empty, so no separate flag is needed.
- The sticky `OutOfMemory` failure is a `failed` flag, because it is the only error that fails the tokenizer.
- `git worktree add` registered the two baseline trees under `out/` in the working tree's own repository, not in `C:\src\fairpane`.

## Integration

The integrator applied the worker's patch to `493143b` and committed it alone as `cb8427d`, after checking that the index held only this task's files.
The binding ran at `HEAD` `ed95bc5`; `raw/integration-head-diff.log` shows that it adds only plan, state, and FP-0014 evidence changes to `cb8427d`.

- `raw/integration-binding.log` records `HEAD` and a status that includes ignored files for every source root, before and after the runs below; `HEAD` is `ed95bc5` both times, and both statuses are empty.
- `gates/2026-10-09T13-12-29-122Z-repo-check-f57f5dcd.json`, `gates/2026-10-09T13-12-29-520Z-controller-test-4fc456f4.json`, `gates/2026-10-09T13-13-10-018Z-zig-fmt-825ad6f2.json`, and `gates/2026-10-09T13-13-10-278Z-zig-test-261a8ecf.json` all pass.
- `raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0064-integration`: 65 of 65 build steps and 292 of 292 tests pass, which adds this task's 14 tests to the 278 of the integrated tree.
- `raw/bun-selftest.log` records Bun 1.4.2 and `tools/selftest.mjs` with 202 of 202 tests.

## Review 1

`reviews/review-1-accept.json` accepts the task with six notes.

- The integrator replaced the README's unlogged edit time with the recorded checkout hashes, and added `raw/integration-commit.log`, which records the files and blob IDs of `cb8427d` and an empty diff of the protected paths against `493143b`.
  The committed blobs equal the tested ones: `tokenizer.zig` `b148d4a`, `tokenizer_test.zig` `9097834`, and `partition_test.zig` `de45539`.
- Contract amendment 2 corrects two sentences: a pending characters step can come between the `!` and the `[CDATA[` decision, and `next` and `finish` keep the shared `Error` set as frozen.
  `FP-0010` must confirm that no character token can change the adjusted current node's namespace before it relies on that flag across `need_input`.
- Later workers record source hashes before and after an after-run, as review 1 asks; `checkCase` takes its `Setup` from a field, as the resolved ambiguities record.
