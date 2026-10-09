# FP-0100 evidence

## Scope

Task `FP-0100` constructs HTML document trees outside tables, templates, framesets, and foreign content, as `CONTRACT.md` freezes it.
The standard text is whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, file `source`, with SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
`raw/html-standard-text.log` records that digest.
The worker implemented the contract in an isolated working tree detached at `bd11c2b` ("FP-0100: freeze the tree construction contract").
The host was Windows, x64, with the locked compiler `0.18.0-dev.120+9fe22a29b`.
Every recorded Zig command ran with the override `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, which each `RESULT` line records.

The parser implements every branch of the ten modes, 130 in total, with the stack of open elements, the list of active formatting elements, the adoption agency algorithm, the script boundary, node retention, and the unsupported outcomes.
Case 11 shows that cases 4 to 10 execute all 130 branches.

## Changed files

| File | Change |
| --- | --- |
| `src/html/modes.zig` | New. `Mode` with the 21 modes in source order, `section`, `title`, `implemented`, `owner`, `branches`, `branch_count`, `branchIndex`, and `branchAt`, in the pattern of `states.zig`. |
| `src/html/tree.zig` | New. The parser, `Options`, `ScriptingMode`, `Unsupported`, `owner`, `Outcome`, `TreeParseError`, `ScriptState`, `Error`, and the test-only branch counters. |
| `src/html/tree_dump.zig` | New. `writeChildren` and `Error`, with no recursion and no allocation. |
| `src/html/tokenizer.zig` | `characterPosition`, one `CharacterRecord` per `appendText` call with a `shared` or `sequential` layout, the one-time reservation of 2 × (`text_flush_threshold` + 1) records, record compaction with `compactText`, the `record` field of a queued run, a layout argument for `appendText` and `flushReference`, and two header lines. No FP-0008 or FP-0064 expected step changed. |
| `src/dom.zig` | `DocumentMode`, the document, doctype, and processing-instruction payloads, `createHtmlDocument`, `isHtmlDocument`, `documentMode`, `setDocumentMode`, the new `createDocumentType` and `createProcessingInstruction` signatures, `documentTypeIds`, `processingInstructionTarget`, `appendData`, character data stored with amortized capacity, the `characterData` doc comment, the module header, and `pub fn expectInvariants`. Tests: the FP-0009 amendments and FP-0100 case 2. |
| `src/html/root.zig` | Exports `Parser`, `ParserOptions`, `ParserError`, `ScriptingMode`, `Outcome`, `Unsupported`, `TreeParseError`, `ScriptState`, `modes`, `tree_dump`, and `unsupportedOwner`. The header says that nothing in the engine's document load calls the parser yet. The `test` block imports `tree_test.zig` and `tree_partition_test.zig`. |
| `src/html/tree_test.zig` | New. Cases 1, 3 to 11, 13, and 14, the case tables, and the record helpers that case 12 reuses. |
| `src/html/tree_partition_test.zig` | New. Case 12, which reuses `partition_test.firstMismatch` and `lab.ddmin`. |
| `src/html/tokenizer_test.zig` | Case 15, which extends the FP-0064 content driver helpers. |
| `src/css/css.zig` | The obligations row for HTML documents. No behavior change. |
| `src/css/selectors.zig` | The header sentence on HTML documents. No behavior change. |

`build.zig`, `tests`, the laboratory, the C ABI, `api`, `include`, `specs`, thresholds, gates, and corpus pins are unchanged.
FP-0007 case 4 keeps its `tree` unsupported result.

## Records

| Log | Command | RESULT |
| --- | --- | --- |
| `raw/tests-before.log` | `git rev-parse HEAD` | `exit_code` 0: `bd11c2b` |
| `raw/tests-before.log` | `git status --short` | `exit_code` 0: only the test files `src/dom.zig`, `src/html/root.zig`, `src/html/tokenizer_test.zig`, `src/html/tree_test.zig`, and `src/html/tree_partition_test.zig` differ |
| `raw/tests-before.log` | `git hash-object` of those files and `src/html/tokenizer.zig` | `exit_code` 0: `tokenizer.zig` is the base blob `b148d4a` |
| `raw/tests-before.log` | `zig build test --summary all --cache-dir out/fp0100-cache-before` | `exit_code` 1, 6 of 100 steps: the unit tests and the compile fixtures fail to compile |
| `raw/html-standard-text.log` | `sha256sum` of the local copy | `exit_code` 0: `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b` |
| `raw/html-standard-text.log` | `awk 'NR>=141948 && NR<=150800 && /<h[3-6]/ {print NR": "$0}'` | `exit_code` 0 |
| `raw/html-standard-text.log` | `awk 'NR>=145851 && NR<=149306 && /<dt/ {print NR": "$0}'` | `exit_code` 0 |
| `raw/wpt-dump-format.log` | `git --git-dir=C:\src\fairpane\.tools\corpora\wpt\repository.git rev-parse` of both pinned paths | `exit_code` 0: `0f4be3b4f460437e1a1eab95fc98b9807fd177ae` and `d993273e77eed7e249fab1dfd68baf15ec401001` |
| `raw/wpt-dump-format.log` | `cat-file -p` of `README.md` and of `test.js` | `exit_code` 0, 0 |
| `raw/tests-after.log` | `git status --short` and `git hash-object` of every changed source | `exit_code` 0, 0 |
| `raw/tests-after.log` | `zig build test --summary all --cache-dir out/fp0100-cache-after`, uncached | `exit_code` 0: 100 of 100 steps, 350 of 350 tests; the unit test step runs 297 of 297 in 54 s |
| `raw/tests-base.log` | `git archive --format=tar --output=out/fp0100-base.tar bd11c2b` and `tar -xf` into `out/fp0100-base` | `exit_code` 0, 0 |
| `raw/tests-base.log` | `zig build test --summary all --cache-dir ../fp0100-cache-base` in `out/fp0100-base`, uncached | `exit_code` 0: 100 of 100 steps, 334 of 334 tests; the unit test step runs 281 of 281 in 36 s |
| `raw/test-timing.log` | `zig test -Odebug -Mroot=src/root.zig --test-filter FP-0008 --test-filter FP-0064`, twice in this tree and twice in `out/fp0100-base` | `exit_code` 0 each: 32341, 23120, 21082, and 15736 ms |
| `raw/test-timing.log` | `zig test -Odebug -Mroot=src/root.zig --test-filter FP-0100`, twice | `exit_code` 0, 0: 12912 and 10262 ms |
| `raw/mutation-noah.log` | `cp src/html/tree.zig out/fp0100-tree.fixed.zig` and `git hash-object` of both | `exit_code` 0, 0: both are `6b89be5` |
| `raw/mutation-noah.log` | `git diff --no-index out/fp0100-tree.fixed.zig src/html/tree.zig` | `exit_code` 1, because the files differ |
| `raw/mutation-noah.log` | The same diff with `--output=engineering/evidence/FP-0100/raw/mutation-noah.diff` | `exit_code` 1 |
| `raw/mutation-noah.log` | `git hash-object src/html/tree.zig` of the mutant | `exit_code` 0: `bea22a0` |
| `raw/mutation-noah.log` | `zig build test --summary all --cache-dir out/fp0100-cache-mutation` | `exit_code` 1: 98 of 100 steps, 348 of 350 tests |
| `raw/mutation-noah.log` | `cp out/fp0100-tree.fixed.zig src/html/tree.zig` | `exit_code` 0 |
| `raw/mutation-noah.log` | `git diff --no-index --exit-code` of the saved and restored files | `exit_code` 0 |
| `raw/mutation-noah.log` | `git hash-object src/html/tree.zig` after the restoration | `exit_code` 0: `6b89be5` |
| `raw/checks-after.log` | `zig fmt --check build.zig src tests` | `exit_code` 0 |
| `raw/checks-after.log` | `node tools/fairpane.mjs test` | `exit_code` 0, 244 of 244 controller tests |
| `raw/checks-after.log` | `node tools/fairpane.mjs check`, after this README | `exit_code` 0: `"result": "pass"`, 134 tasks, 9 gates |

`raw/mutation-noah.diff` holds the exact diff of the mutation control.

### tests-before

The run used the base sources with every new test added, before any non-test source changed.
`git status` and `git hash-object` in the same log show that `src/html/tokenizer.zig` was still the base blob and that only test code differed: the FP-0100 test files, the `test` block of `src/html/root.zig`, and the test code of `src/dom.zig` and `src/html/tokenizer_test.zig`.
The new `pub` on the test-only `expectInvariants` is part of that test code.
It failed to compile, as expected: `DocumentMode` is undeclared, and `modes.zig`, `tree.zig`, and `tree_dump.zig` do not exist.
The compile-fail fixtures of FP-0011 import every file of the module, so they report the same errors.

After the run, three test-file defects of the worker's transcription were fixed before `raw/tests-after.log`; no frozen value changed.

- `tree_test.zig`: two dump literals had `| ` before the continuation line of a text node that holds a line feed (B10 and Y1), which the contract's dumps do not have.
- `tree_test.zig`: case 1 called `modes.branchIndex` at run time, which must run at compile time.
- `tokenizer_test.zig`: case 15 converted its FP-0064 notation with `expectedDump`, which derives an error's offset as its column minus one.
  That holds only on line 1, and the NULL's error is at 2:13, offset 22.
  The test now states the expected dump with offset 22 and keeps the notation in a comment.

`tree_test.zig` moved from blob `3b4ee56` to `73fd495`, and `tokenizer_test.zig` from `00b4dad` to `60fa8c2`.
`tree_partition_test.zig` is `0383f5b` in both runs.
`zig fmt` also reformatted one line of `tree_test.zig`.

Development compiles and runs used the uncited cache `out/fp0100-cache-dev`; no result in this README comes from them.

### tests-after and durations

`raw/tests-after.log` ran on the blobs that its `git hash-object` record lists, and the mutation control restored `tree.zig` to the same blob `6b89be5`.

| Measure | Base `bd11c2b` | After |
| --- | --- | --- |
| `run test` step of the unit tests (`--summary all`) | 281 tests, 36 s | 297 tests, 54 s |
| `zig build test`, whole command | 54956 ms | 71556 ms |
| FP-0008 and FP-0064 tests alone, second warm `zig test` | 15736 ms | 23120 ms |
| FP-0100 tests alone, second warm `zig test` | none | 10262 ms |

- The unit test step takes 54 s, far below the 400 s limit, which is two thirds of the 600000 ms gate timeout.
- The most recent accepted zig-test receipt is `engineering/evidence/FP-0076/gates/2026-10-09T15-43-27-307Z-zig-test-db8aab34.json`.
  Its gate runs `zig build test` without `--summary all` and on a warm cache, so it reports no `run test` step duration, only a whole-command `duration_ms` of 7082.
  The comparable step duration is therefore the base run above, which ran on the same host with a fresh local cache.
- The unit test step grew by 18 s, from 36 s to 54 s.
  The FP-0008 and FP-0064 tests account for about 7.4 s of it, from 15.7 s to 23.1 s.
  That cost is the tokenizer's one-time reservation of 8194 character records, which each of the many tokenizers in their partition sets makes on its first character.
  The 16 new FP-0100 tests account for about 10.3 s, most of it case 12, whose set B parses W3 in 19307 partitions.
- The warm `zig test` durations include the compiler's cache check, so they are upper bounds on the test time.

## Acceptance

- Every case from 1 to 15 has a test whose name begins with `FP-0100 case N`, and all pass in `raw/tests-after.log`.
  Case 2 is in `src/dom.zig`, case 15 in `src/html/tokenizer_test.zig`, case 12 in `src/html/tree_partition_test.zig`, and the others in `src/html/tree_test.zig`.
- Every FP-0008, FP-0009, FP-0014, and FP-0064 test passes in `raw/tests-after.log`, with its expected values unchanged.
- The tree tests check `dom.expectInvariants` after every case, including each induced allocation failure of case 14.
- Case 11's counters are nonzero for every one of the 130 branches.
- Case 12 checks each input's units, its frozen record, and every partition of its set.
- Case 14 checks, for each induced failure, that `feed`, `finish`, and `run` return `error.OutOfMemory` again, that the invariants hold, and that the backing allocator's `allocated_bytes` equals its `freed_bytes`.
- `zig fmt --check` and `node tools/fairpane.mjs test` pass in `raw/checks-after.log`.

### Criterion mapping

| Plan criterion | Cases | Evidence |
| --- | --- | --- |
| Implement frozen tree-construction modes with standard recovery. | 1 and 4 to 11 | `raw/tests-after.log` |
| Exercise malformed nesting and chunk boundaries through the actual DOM. | 7, 8, 12, and the invariant check after every case | `raw/tests-after.log` |
| Preserve parser continuation and future script-reentrancy boundaries. | 9, 12 (Q7 and Q9), 13, and 14 | `raw/tests-after.log` |
| Emit inspectable DOM dumps from real parsing. | 3 and every dump of cases 4 to 13 | `raw/tests-after.log`, `raw/wpt-dump-format.log` |
| Implement the ten modes, the stack, the list, and the adoption agency algorithm, and execute each of their 130 branches | 1, 4 to 8, and 11 | `raw/tests-after.log`, `raw/html-standard-text.log` |
| Report unsupported tokens with their owner task | 1 and 10, including the `owner` assertions | `raw/tests-after.log` |
| Return a script outcome before any later character, and keep referenced nodes alive across a sweep | 9 and 13 | `raw/tests-after.log` |
| Compare whole-input results with every partition, including error positions | 12 and 15 | `raw/tests-after.log` |
| Extend the DOM store and keep every FP-0009 outcome | 2, 3, and the FP-0009 cases after the amendments | `raw/tests-after.log` |
| Record whether a character token can change the adjusted current node's namespace | B30 and the finding below | `raw/tests-after.log` |
| Record the non-goals owned by the FP-0026 frontier decomposition | The non-goals below | This README |

## Modes and unsupported features

The ten implemented modes are initial, before html, before head, in head, in head noscript, after head, in body, text, after body, and after after body.

| Unimplemented mode | Owner |
| --- | --- |
| in table, in table text, in caption, in column group, in table body, in row, in cell | `FP-0102` |
| in template, in frameset, after frameset, after after frameset | `FP-0103` |

| Unsupported feature | Owner |
| --- | --- |
| `.mode`: a token for an unimplemented mode | The mode's owner, `FP-0102` or `FP-0103` |
| `.template_start_tag`: the in head `template` start tag | `FP-0103` |
| `.foreign_start_tag`: the in body `math` and `svg` start tags | `FP-0104` |

## The FP-0064 amendment 2 finding

FP-0064 amendment 2 asks FP-0010 to confirm that no character token can change the adjusted current node's namespace.
The confirmation fails in general.
At a MathML text integration point, the dispatcher sends a character token to the insertion mode, and in body every character token first reconstructs the active formatting elements, which inserts HTML elements.
The tokenizer also reads `adjusted_current_node_is_foreign` while characters before the `<` are still pending.
The witness is `<math><mi><p><b></p>x<![CDATA[y]]>`: the standard gives the comment `[CDATA[y]]` after `x`, but split inside `[CDATA[` the tokenizer gives it and in one chunk it gives one text node `xy`.
FP-0064 amendment 3 records this finding, and `FP-0104` owns the fix and the witness test.
Within FP-0100 the confirmation holds, because every element that the parser creates is in the HTML namespace; B30 shows the CDATA branch with a false flag.

## FP-0009 amendment

The FP-0009 test that holds the rejected-call list is "FP-0009 case 12: a handle from another store returns WrongOwner, and a handle to a swept node returns StaleHandle".
Its `createDocumentType` row passes three empty identifiers, and its `createProcessingInstruction` row passes `"x"` as both target and data.
`newDoctype` passes three empty identifiers, `newProcessingInstruction` passes its text as both target and data, and `allocationScenario` passes three empty identifiers and `"instruction"` twice.
No FP-0009 expected outcome changed.

## Non-goals owned by the FP-0026 frontier decomposition

- Speculative parsing.
- Custom element definitions.
- Form-owner association.
- The reset algorithm of resettable elements.
- Process internal resource links.
- The steps that set the parser cannot change the mode flag.
- `iframe` `srcdoc` documents.

None of them changes a tree dump, and none of them is reported as done.

## Standard text: headings and branches

`raw/html-standard-text.log` lists every heading from line 141948 to 150800 and every `<dt` line from 145851 to 149306.
Each heading that the Sources table cites is at its cited line, except that "Other parsing state flags" is at line 142417 and the table starts that section at 142418; the cited content, from the root insertion target at 142420, is in the range.
Each in-body entry line that the contract cites is the line of its `<dt>`.

The `<dt>` groups of the ten modes map to the branch table as follows.
Lines joined by `+` are adjacent `<dt>` lines that share one `<dd>`, so they form one branch.

| Mode | `<dt>` lines, in branch order |
| --- | --- |
| initial (5) | 145863; 145870; 145875; 145881; 145991 |
| before html (8) | 146014; 146019; 146024; 146030; 146036; 146047; 146052; 146057 |
| before head (9) | 146083; 146090; 146095; 146100; 146105; 146111; 146122; 146127; 146132 |
| in head (17) | 146160; 146167; 146172; 146177; 146182; 146188; 146198; 146229; 146234+146236; 146241; 146251; 146311; 146320; 146325; 146504; 146565+146566; 146571 |
| in head noscript (7) | 146598; 146603; 146609; 146619+146621+146622+146623; 146630; 146635+146636; 146641 |
| after head (12) | 146671; 146678; 146683; 146688; 146693; 146699; 146709; 146717; 146736; 146742; 146747+146748; 146753 |
| in body (55) | 146778; 146790; 146799; 146808; 146813; 146818; 146823; 146835+146837; 146843; 146858; 146885; 146908; 146934; 146967; 146983; 146999; 147018; 147038; 147088; 147157; 147176; 147204; 147230; 147270; 147281; 147301; 147325; 147349; 147360; 147387; 147396; 147409; 147416; 147428; 147452; 147469; 147478; 147493; 147529; 147538; 147565; 147572; 147597; 147610; 147617+147618; 147624; 147658; 147683; 147705; 147715; 147725; 147748; 147771; 147787; 147798 |
| text (4) | 148045; 148053; 148067; 148176 |
| after body (8) | 149064; 149071; 149077; 149083; 149088; 149094; 149103; 149108 |
| after after body (5) | 149275; 149280; 149286+149287+149289; 149295; 149300 |

These `<dt` matches in the ten modes are not branches:

- 147773 and 147777 are commented-out `<!--<dt>` lines inside the caption group entry.
- 148103 and 148116 are nested inside the text mode's `script` end tag entry.
- 147087, 147140, and 147142 are inside HTML comments of the `dd`/`dt` and `li` entries; the contract did not name them.

The other matches, from 148194 to 148887, 148941 to 149032, and 149125 to 149258, belong to the unimplemented modes.
No branch of the ten modes is missing from the table, and the table lists no branch that does not exist.

## Mutation control

The control makes the push onto the list of active formatting elements skip the Noah's Ark removal: `if (count >= 3)` becomes `if (false and count >= 3)` in `pushFormatting`.
The run fails 2 of 297 unit tests:

- FP-0100 case 8, on A9 and A10, whose dumps keep a fourth `b` element.
- FP-0100 case 12, set B, on Q8, whose whole-input record differs from the frozen values of A10.

Case 11 also runs A9 and A10 and prints their mismatches, but it checks only the branch counters, so it passes.

The Q8 failure output, from `raw/mutation-noah.log`, compares the whole-input record with the frozen values of A10:

```text
FP-0100 case 12, input Q8 (A10):
expected:
outcomes: done
errors: !tree@1:1 !tree@1:39 !tree@1:43
offsets: 0 38 42
mode: quirks
| <html>
|   <head>
|   <body>
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="1"
|           <b>
|             c="2"
|             <b>
|               c="1"
|               <b>
|                 c="1"
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="2"
|           <b>
|             c="1"
|             <b>
|               c="1"
|               "x"
reference:
outcomes: done
errors: !tree@1:1 !tree@1:39 !tree@1:43
offsets: 0 38 42
mode: quirks
| <html>
|   <head>
|   <body>
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="1"
|           <b>
|             c="2"
|             <b>
|               c="1"
|               <b>
|                 c="1"
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="1"
|           <b>
|             c="2"
|             <b>
|               c="1"
|               <b>
|                 c="1"
|                 "x"
```

The restored file is byte-identical to the saved fixed file, and `raw/tests-after.log` ran on that same blob `6b89be5`.

## Stop-rule observations

- No frozen expected value contradicts the cited standard text; every case passes with the values as frozen.
- The `<dt>` listing matches the branch table, as the section above shows.
- Every cited line range holds its cited text. The one difference is the heading of 13.2.4.5, which is at 142417, one line before the cited 142418.
- No case needs behavior outside the subset that the contract does not freeze as unsupported.
- No DOM or tokenizer change altered an FP-0008, FP-0009, FP-0014, or FP-0064 expected outcome.
- The unit test step takes 54 s, below the 400 s limit.
- No expectation, input, or upstream byte was edited to pass a case.

## Resolved readings

- The in body `rb`/`rtc` and `rp`/`rt` entries check the current node after the conditional "generate implied end tags", whether or not a `ruby` element is in scope, as their second sentences read (147705 to 147723).
  No frozen case distinguishes this reading.
- A characters step is processed in runs: in body reconstructs the active formatting elements once per run of non-NULL characters, because a later reconstruction in the same run finds the last entry open and does nothing.
  The branch counters still count each code point.
- `Tokenizer.characterPosition` records a matched character reference as one `shared` record at its `&`, and a flushed `&`, `&#`, or `&#x`, the `]]` of a CDATA end, and the `</` and name of an abandoned end tag as `sequential` records, one source character per unit.
- The tree dump writes each code point in UTF-8 and a lone surrogate in its three-byte generalized UTF-8 form, because the dump does not escape.
- After `template_start_tag` from the after head entry, the head element stays on the stack, because the remaining steps of that entry belong to `FP-0103`; the stack is not observable after an unsupported outcome.
- A start tag that ends in an unsupported outcome raises no `non-void-html-element-start-tag-with-trailing-solidus` error, because the branch that would acknowledge its flag did not run.
