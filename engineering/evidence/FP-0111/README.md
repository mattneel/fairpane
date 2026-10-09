# FP-0111 evidence

## Scope

This record covers task `FP-0111`, "Parse OpenType layout common tables and GDEF for shaping".
`CONTRACT.md` freezes its behavior, its 25 test cases, the amended FP-0013 cases 13 and 16, its 22 mutation controls, and its integrator decisions.
The `fairpane-text` worker `FP0111Layout` wrote this patch in an isolated worktree whose `HEAD` is `ca026e893493f61bbdf6f0f67a4ab9edd0a3aca8` (`ca026e8`), the commit that froze the contract.
Nothing is committed, and the protected paths, `engineering/plan.json`, `engineering/state.json`, `engineering/HANDOFF.md`, and `engineering/dependencies.json` are unchanged.
The worker ran `check` and the controller tests; the integrator runs the gates.

Every Zig command ran with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`, as each `RESULT` line's `environment_overrides` shows.
`node tools/fairpane.mjs record` recorded every command under `raw/`.

## Files changed

| File | Change |
| --- | --- |
| `src/font/tables.zig` | `Defect` gains `index_out_of_range`, `invalid_range`, `inconsistent_coverage_index`, `nested_extension`, `mixed_lookup_types`, `missing_default_lang_sys`, and `null_offset`. |
| `src/font/layout.zig` | `Kind`; `Layout` gains `kind`, `feature_variations`, `script`, `feature`, `lookup`, and `selectLookups`; `Script`, `LangSys`, `Feature`, `Lookup`, `LookupStatus`, `Subtable`, `SubtableStatus`, `Request`, `SelectionLimits`, `Selection`, `SelectionStatus`, `SelectError`, and the test-only counter `work`. `parseLayout` takes the kind. It re-exports every name of the two new files. |
| `src/font/layout_common.zig` | New. `Coverage`, `CoverageIterator`, `ClassDef`, `DeviceStatus`, `parseCoverage`, `parseClassDef`, and `parseDevice`. |
| `src/font/gdef.zig` | New. `Gdef` with `table` and its four methods, `parseGdef` (moved from `layout.zig`), `MarkGlyphSets`, `LigCaretList`, `CaretsStatus`, `LigGlyph`, `CaretStatus`, and `CaretValue`. |
| `src/font/opentype.zig` | `pub const layout` and `pub const Reader`. `gsub` and `gpos` pass their kind. The `gdef`, `gsub`, and `gpos` comments state each cost. The module comment still says that layout lookups are not interpreted. |
| `specs/capabilities/text-fonts.json` | The frozen `shaping.engine_behavior` text. The status stays `remaining`, and the owner stays `FP-0015`. |
| `tools/fonts/font_expectations.py` | Format version 2, the layout dumps, the `postRead` wrappers, and the warning handler. |
| `tools/README.md` | The font-expectations section names the version 2 layout fields, the wrappers, and the warning handler. |
| `tests/text/fonts/*/*.expect.json` | Regenerated only by `raw/font-expectations-write.log`. |
| `tests/text/layout_builder.zig` | New. G, G11, P, T_MFS, H(N), E1, E2, E34, F_GDEF, F_GDEF4, F_GDEF2, and the subtable byte strings. |
| `tests/text/layout_test.zig` | New. Cases 1 to 24. |
| `tests/text/layout_fixture_test.zig` | New. Case 25. |
| `tests/text/root.zig` | Imports both new test files and names FP-0111. |
| `tests/text/fixture_test.zig` | Amended FP-0013 case 13. |
| `tests/text/synthetic_test.zig` | Amended FP-0013 case 16. |
| `tests/text/README.md` | Lines 5 and 8 name FP-0111. New sections describe the layout fixtures, the dumps, and the FP-0111 stop rules. |
| `engineering/evidence/FP-0111/raw/` | The logs, `observations.mjs`, and the 22 mutation diffs listed below. |

`build.zig`, `include`, `api`, `tools/fileset.mjs`, `parse`, and the C ABI are unchanged.

## Design

Each opening call reads its structure through `Reader` and checks it in the contract's order, in time linear in its length.
The opened value copies the counts that it checked and the absolute position of its structure.
Each accessor reads the bytes again, and each index that names a record or a mask is read once and checked where it is used.
`LangSys.featureIndex` and `Feature.lookupIndex` return null for an index that is no longer below its list count, so a caller never receives an index past the list.
No function recurses, allocates, or takes an allocator.

`selectLookups` scans the script records linearly for the requested tag and then for `DFLT`.
It opens the Script, the requested LangSys or the default LangSys, and each named Feature, and it charges one work unit before each `featureIndices` and `lookupListIndices` read of steps 7 and 8.
Steps 7 and 8 for one LangSys are the private helper `addLangSys`.
It writes `masks[i]` of the caller's slice after checking `i < lookupCount`, which the `MasksTooShort` check keeps inside `masks`.

An extension lookup is opened by checking every extension header.
`Lookup.subtable` then follows the extension offset once and uses the effective type that the opening call found.
`Subtable.coverage` reads the first Coverage offset at `+2`, at `+6` for SequenceContextFormat3, and at `6 + 2b` for ChainedSequenceContextFormat3.

## Criterion mapping

| FP-0111 criterion | Cases and evidence | Result |
| --- | --- | --- |
| 1. Parse Coverage, ClassDef, LangSys, feature index lists, Lookup tables, flags, and mark filtering sets with checked offsets and bounded work | 1 to 4, 7 to 9, 13, 14, 17; M1 to M5, M13, M14, M16 to M19 | Pass in `raw/tests-after.log`. Each control fails its named case. |
| 2. Select lookups with DFLT and default LangSys fallback | 7, 8, 10, 11, 25 (selection cross-check); M7 to M11 | Pass. Each control fails its named case. |
| 3. Parse GDEF glyph classes, mark attachment classes, mark glyph sets, and ligature carets | 3, 18, 19, 25; M21, M22 | Pass. Each control fails case 18. |
| 4. Report FeatureVariations, unknown types and formats, and Device and VariationIndex data as unsupported | 2, 4 to 6, 12 to 14, 18, 20; M6, M20, M21 | Pass. Each control fails its named case. |
| 5. Reject malformed subtables without a panic, unbounded allocation, or native recursion | 2, 4, 6, 15, 16, 17, 20 to 24; M3, M5, M12, M15, M18, M19 | Pass. Each control fails its named case. |
| 6. Check the fixtures against the fontTools dumps | 25, amended case 13, `raw/digests-before.log`, `raw/font-expectations-write.log`, `raw/font-expectations-check.log`, and `raw/digests.log` | Pass. No stop rule fired. |

## Evidence logs

| Log | Command | Result |
| --- | --- | --- |
| `raw/digests-before.log` | `sha256sum` of the four fonts, before any fontTools run | Exit status 0. Each digest equals `specs/snapshots/opentype-fixtures.json` lines 111, 133, 155, and 186: `f3961a9c…`, `bd86ca02…`, `9c7d9351…`, and `3f435bdd…`. |
| `raw/tools-junction-attempt-1.log` | `mklink /J .tools …` | Failed attempt. The shell removed the backslashes from the executable path, so `record` reported "The executable is not on PATH" with no exit code. Nothing ran. |
| `raw/tools-junction.log` | `cmd /d /c mklink /J .tools C:\Users\requi\.omp\wt\t2dec3085f\m\.tools` | Exit status 0. See "Resolved ambiguities", item 1. |
| `raw/font-expectations-dry-run.log` | `node tools/fairpane.mjs font-expectations --check`, after the script change and before the write run | Exit status 1 by design: all four outputs differ from the version 1 files. It verified 350 installed files against the wheel's RECORD, and the script printed no fontTools warning. |
| `raw/font-expectations-write.log` | `node tools/fairpane.mjs font-expectations` | Exit status 0. It logs the argument vector of each font and reports all four outputs as different from the committed files. |
| `raw/font-expectations-check.log` | `node tools/fairpane.mjs font-expectations --check` | Exit status 0. All four files are byte-identical, so the dump is reproducible. |
| `raw/digests.log` | `sha256sum` of the four fonts, the script, and the four expectation files | Exit status 0. The font digests equal `raw/digests-before.log`. |
| `raw/tests-before-attempt-1.log` | `zig build test --summary all --cache-dir out/fp0111-before` | Failed attempt, exit status 1. The builder used the `**` array operator, which the locked compiler no longer parses. |
| `raw/tests-before-attempt-2.log` | The same with `--cache-dir out/fp0111-before-2` | Failed attempt, exit status 1. Besides the expected errors, `hex` returned from a `comptime` block in a runtime call, so the log did not show only the missing interface. |
| `raw/tests-before.log` | `git worktree add --detach out/fp0111-before-tree ca026e8`, `cp --parents` of the final test files, the script, and the four expectation files, `git status`, `git rev-parse HEAD`, `git hash-object`, then `zig build test --summary all --cache-dir out/fp0111-before` in that tree | Exit status 1. Lines 50 to 79: 4 compilation errors, `'layout' is not marked 'pub'` (twice) and `enum 'font.tables.Defect' has no member named 'invalid_range'` (twice). Line 102: "98/101 steps succeeded (1 failed); 333/333 tests passed". The source files are the base blobs. |
| `raw/tests-before-duration.log` | In `out/fp0111-base-tree` at `ca026e8`: the absent `out/fp0111-base` check, `git rev-parse HEAD`, `cmd /d /c ver`, and `zig build test --summary all --cache-dir out/fp0111-base` | Exit status 0. Line 42: 101 of 101 steps and 394 of 394 tests. Line 46: `run test 61 pass (61 total) 966ms`. |
| `raw/tests-after.log` | The absent `out/fp0111-after` check, `cmd /d /c ver`, and `zig build test --summary all --cache-dir out/fp0111-after` | Exit status 0. Line 32: 101 of 101 steps and 419 of 419 tests. Line 36: `run test 86 pass (86 total) 1s`. |
| `raw/fmt.log` | `zig fmt --check build.zig src tests` | Exit status 0. |
| `raw/controller-tests-base.log` | In the base tree: `git rev-parse HEAD`, `node --version`, `node tools/fairpane.mjs test` | Node v26.7.0. Exit status 0, 248 of 248. |
| `raw/controller-tests-after.log` | `cmd /d /c rmdir .tools`, `node --version`, `node tools/fairpane.mjs test` | The junction was removed first, because FP-0079 case 9 rejects a linked `.tools`. Node v26.7.0. Exit status 0, 248 of 248, the base count. |
| `raw/check.log` | `node tools/fairpane.mjs check` | Exit status 0, `"result": "pass"`. |
| `raw/profile.log` | `zig test -ODebug --test-runner tools/zig/test_profile_runner.zig --cache-dir out/test-profile --dep fairpane -Mroot=tests/text/root.zig -Mfairpane=src/root.zig` | Exit status 0. `TOTAL 86 tests, 1290.976 ms; 0 failed, 0 skipped, 0 leaked, 0 logged errors`. See "Durations". |
| `raw/mutation.log` and `raw/mutation-M1.diff` to `raw/mutation-M22.diff` | `git rev-parse HEAD` and `git diff --cached --stat`, then for each control: `sha256sum`, `git apply`, `sha256sum`, `zig build test --summary all --cache-dir out/fp0111-mutation`, `git apply -R`, and `sha256sum` | Every `git apply` and `git apply -R` exits with status 0, and every `zig build test` exits with status 1. See "Mutation controls". |
| `raw/observations.log` | `node engineering/evidence/FP-0111/raw/observations.mjs` | Exit status 0. See "Case 25 observations". |
| `raw/fonttools-lines.log` | `grep -n` of the cited lines in the installed `otBase.py` and `otTables.py` | Exit status 0. See "Resolved ambiguities", item 12. |
| `raw/cleanup.log` | `git worktree remove --force` of both temporary trees, then `git worktree prune` | Exit status 0 each. |

## Durations

The `tests/text` run step went from 966 ms (`raw/tests-before-duration.log` line 46) to 1 s (`raw/tests-after.log` line 36), far under the 10-second limit.
The build summary rounds the second value; `raw/profile.log` gives each case's own duration on the development host:

| Case | ms | Case | ms | Case | ms |
| --- | --- | --- | --- | --- | --- |
| 1 | 0.018 | 10 | 0.413 | 19 | 0.178 |
| 2 | 0.003 | 11 | 0.221 | 20 | 2.123 |
| 3 | 0.006 | 12 | 0.204 | 21 | 319.091 |
| 4 | 0.003 | 13 | 0.231 | 22 | 37.695 |
| 5 | 0.002 | 14 | 0.190 | 23 | 41.831 |
| 6 | 0.000 | 15 | 2.295 | 24 | 0.000 |
| 7 | 0.441 | 16 | 2.328 | 25 | 82.479 |
| 8 | 0.228 | 17 | 45.596 | | |
| 9 | 0.247 | 18 | 0.413 | | |

The FP-0111 cases total about 536 ms of the profile's 1291 ms for 86 tests.
No performance claim follows from these numbers.

## Mutation controls

The implementation was staged before the controls, so each diff is a real `git diff` against the staged file.
Each file's SHA-256 is the same before each control and after its `git apply -R`: `a68d1429…` for `src/font/layout_common.zig` (M1 to M6), `204051dd…` for `src/font/layout.zig` (M7 to M20), and `d3e7904d…` for `src/font/gdef.zig` (M21 and M22).
`raw/mutation.log` records each mutated hash.
`tests/text` has 86 tests, and in each control's `Build Summary` line the failed-test count equals the `tests/text` failures below, so no other artifact failed.

| Control | Mutation | `tests/text` result | Named case and the observed defect | Other failing cases | Log lines |
| --- | --- | --- | --- | --- | --- |
| M1 | Format 2 `index` ignores `startCoverageIndex` | 84 pass, 2 fail | Case 1: CV3 `index(10)` is 0, not 3. | 25 | 33 to 297 |
| M2 | Format 1 search excludes the last element | 77 pass, 9 fail | Case 1: CV1 `index(0x4A)` is null, not 4. | 8, 13, 14, 18, 19, 20, 22, 25 | 300 to 650 |
| M3 | Format 1 accepts equal adjacent glyphs | 85 pass, 1 fail | Case 2: `0001 0003 0005 0005 0006` is valid. | none | 653 to 889 |
| M4 | ClassDef format 1 uses glyph − start + 1 | 84 pass, 2 fail | Case 3: CD1 `class(0x33)` is 0. | 18 | 892 to 1141 |
| M5 | ClassDef format 2 accepts unsorted records | 84 pass, 2 fail | Case 4: the `gdef` Example 2 bytes are valid. | 20 (Y1) | 1144 to 1388 |
| M6 | `0x8000` is reported as `unsupported_device` | 84 pass, 2 fail | Case 5: the VariationIndex row. | 20 (Y8) | 1391 to 1658 |
| M7 | No DFLT fallback | 84 pass, 2 fail | Case 10: S4 gives script null, not `DFLT`. | 15 (X6) | 1661 to 1910 |
| M8 | An absent language gives `.none` | 85 pass, 1 fail | Case 10: S3 gives `.none`, not `.default`. | none | 1913 to 2154 |
| M9 | Default features are merged into a requested LangSys | 84 pass, 2 fail | Case 10: S2's mask 0 is `0x4`, not 0. | 25 (cross-check) | 2157 to 2412 |
| M10 | The required feature is skipped | 81 pass, 5 fail | Case 7: E2-b's mask 3 is 0, not bit 63. Case 10: S1's mask 2 is `0x2`. | 11, 12, 17 | 2415 to 2694 |
| M11 | DFLT fallback for a script without the language and a default | 85 pass, 1 fail | Case 10: S6 gives script `DFLT`, not `latn`. | none | 2697 to 2958 |
| M12 | Both lookup index range checks are removed | 83 pass, 1 fail, 2 crash | Case 15: X3 is valid, not `index_out_of_range`. | Crashes, recorded separately: case 21 panics with "index out of bounds: index 16, len 13", and case 22 with "index 65280, len 13". | 2961 to 3279 |
| M13 | `markFilteringSet` is not read | 83 pass, 3 fail | Case 13: L2's set is null, not 1. | 16 (Z2), 25 | 3282 to 3548 |
| M14 | Extension subtables are not unwrapped | 81 pass, 5 fail | Case 13: L3's type is 7, not 1. Case 14: P2's type is 9. | 16 (Z5), 22, 25 | 3551 to 3842 |
| M15 | Mixed extension types are accepted | 85 pass, 1 fail | Case 13: L8 is valid, not `mixed_lookup_types`. | none | 3845 to 4080 |
| M16 | The flag's high byte is dropped | 85 pass, 1 fail | Case 13: L3's flag is 0, not `0x0200`. | none | 4083 to 4324 |
| M17 | GPOS 4, 5, and 6 read their coverage at +4 | 84 pass, 2 fail | Case 14: P1's coverage is [1], not [3]. | 25 | 4327 to 4597 |
| M18 | The limit is checked after the increment | 85 pass, 1 fail | Case 17: H(100) with 10,100 is `limit_exceeded`. | none | 4600 to 4835 |
| M19 | The work limit is removed | 84 pass, 2 fail | Case 17: H(100) with 10,099 is valid, before H(30000) runs. Case 23: its first H(100) assertion fails. | none | 4838 to 5079 |
| M20 | `feature_variations` is never set | 85 pass, 1 fail | Case 12: G11's `feature_variations` is 0. | none | 5082 to 5316 |
| M21 | CaretValue format 3 drops its device | 84 pass, 2 fail | Case 18: `caret(2)`'s device is null. | 20 (Y7) | 5319 to 5589 |
| M22 | MarkGlyphSets offsets are read as Offset16 | 83 pass, 3 fail | Case 18: `set(0)` is `rejected null_offset`. | 20 (Y4), 25 | 5592 to the end |

## Case 25 observations

`raw/observations.log` records these values, and no test asserts them.
`observations.mjs` reads the version 2 expectation files and, for AttachList and `lookupOrderOffset`, the font bytes; it uses neither the Zig parser nor fontTools.

| Font | Table | Subtables by effective type and format | Extension lookups | Flag bits | Primary coverages by format |
| --- | --- | --- | --- | --- | --- |
| Noto Sans | GSUB | 1/1 11, 1/2 24, 2/1 1, 3/1 1, 4/1 7, 6/1 1, 6/3 5 | 0 | `0x0008` 1, `0x0010` 4 | 1: 36, 2: 14 |
| Noto Sans | GPOS | 1/1 1, 2/1 1, 2/2 2, 4/1 4, 5/1 4, 6/1 4, 8/3 1 | 0 | `0x0008` 2, `0x0010` 6 | 1: 13, 2: 4 |
| Noto Sans Arabic | GSUB | 1/1 10, 1/2 12, 2/1 6, 3/1 1, 4/1 4, 5/3 12, 6/1 1, 6/3 5 | 0 | `0x0008` 4, `0x0010` 7 | 1: 43, 2: 8 |
| Noto Sans Arabic | GPOS | 2/1 1, 2/2 1, 4/1 14, 5/1 2, 6/1 5 | 0 | `0x0008` 1, `0x0010` 5 | 1: 10, 2: 13 |
| Noto Sans Devanagari | GSUB | 1/1 73, 1/2 27, 2/1 3, 4/1 34, 5/1 1, 5/2 5, 5/3 79, 6/1 5, 6/2 1, 6/3 211 | 0 | `0x0008` 4, `0x0010` 10 | 1: 392, 2: 47 |
| Noto Sans Devanagari | GPOS | 1/1 5, 2/1 1, 2/2 1, 4/1 16, 6/1 4, 8/3 4 | 0 | `0x0010` 5 | 1: 16, 2: 15 |
| CJK subset | GSUB | 1/1 3, 1/2 6, 3/1 1, 6/3 1 | 3 | none | 1: 10, 2: 1 |
| CJK subset | GPOS | 1/1 5, 1/2 5, 2/1 2 | 0 | none | 1: 11, 2: 1 |

Every lookup with flag bit `0x0010` has a mark filtering set.
No fixture sets the reserved bits `0x00E0` or a mark attachment class.
Every GSUB and GPOS table has version `0x00010000` and no FeatureVariations.
No LangSys of any fixture has a nonzero `lookupOrderOffset`.
No GDEF has AttachList data, a mark attachment class definition, or an item variation store.
Every GDEF glyph class definition is format 2: 3112 classed glyphs in Noto Sans, 423 in Noto Sans Arabic, and 517 in Noto Sans Devanagari.
The mark glyph sets number 6, 9, and 6.
Noto Sans has 5 ligatures with 7 carets and Noto Sans Arabic 2 ligatures with 5 carets, all format 1; Noto Sans Devanagari has no LigCaretList.
So no fixture has caret format 2 or 3; F_GDEF covers them.

| Expectation file | Version 1 at `ca026e8` | Version 2 |
| --- | --- | --- |
| `NotoSans-Regular.expect.json` | 754044 bytes, `c29f5a4a9cac02a7d66434b9e68cec89ce34b786bf0c3a574c2088f11e825834` | 1042753 bytes, `ca7555c21dfc4a4a0ca285ce0b983fb4bfdc5409bda4eb4182d0ad16da1610de` |
| `NotoSansArabic-Regular.expect.json` | 305477 bytes, `a77355ff3aafdb72161028d67e72ab58d1bdc8c4c897571b08a883d67b0fa139` | 388897 bytes, `4e4b18e0d8ff4b5adaba6074ed7129d709a7a411aa30c34e088c29735f08570e` |
| `NotoSansDevanagari-Regular.expect.json` | 84302 bytes, `529eb3234d7b2662afa44fab7ce46a8550fe86106c3d1f4e9a71ecdf47fdd68d` | 291107 bytes, `a980b4d567be50c9f5436138e10c6ed05cbb3dec87745f28d698d561057f7502` |
| `cjk-subset.expect.json` | 13945 bytes, `09fc2123afd8115ecf450f21c626606eec8e72d93048ed1f44bd33db4469f195` | 33917 bytes, `ec2a9ec3645792cc0837e93634dc65eb390e662d1c40379aac3c7b6ee286b4b2` |

## Stop rules

- `raw/digests-before.log` matches the snapshot record for all four fonts.
- Case 25 found no difference, and every fixture lookup and subtable is valid.
- No fixture LangSys names more than 63 distinct tags; the cross-check would fail with a message if one did.
- `font_expectations.py` exited with status 0 for every font, and no fontTools warning was recorded.
- `font-expectations --check` reported all four files byte-identical after the write run.
- The `tests/text` run step grew from 966 ms to 1 s.
- The worker found no expectation that contradicts its cited text, apart from the three example inconsistencies that the contract records. The worker did not fetch the cited chapters again; it implemented the frozen byte strings and expected values as written. Items 11 and 12 below record two differences in the contract's own explanations, which change no expectation.

## Resolved ambiguities

1. fontTools installation. The worktree had no `.tools`, and the main checkout's `.tools` holds no fontTools environment.
   `font-expectations` resolves `<repository>/.tools/python/fonttools-4.66.1` and `<repository>/.tools/downloads`, so the worker linked the worktree's `.tools` to the FP-0013 worktree's `.tools` (`t2dec3085f`), whose installation FP-0013 revision 1 verified.
   No copy or package was installed. Each run verified 350 installed files against the wheel's RECORD and the wheel's SHA-256 `7234ae9e…`.
   The junction was removed before the controller tests.
2. Dry run. The worker ran `font-expectations --check` once before the write run to see whether the script ran without a warning; `raw/font-expectations-dry-run.log` keeps it.
3. Before run. Both failed attempts were test-side mistakes in a draft builder. The final log ran in a separate tree at `ca026e8` with the final test files, script, and expectation files, so its sources are the base sources and its tests are the tested ones.
4. Opened handles keep counts and positions. A Script, LangSys, Feature, Lookup, Subtable, Coverage, ClassDef, MarkGlyphSets, LigCaretList, and LigGlyph keep the counts they checked. A record that no longer fits returns `count_out_of_bounds` or `too_short`, which only changed bytes can cause.
5. Extensions after a byte change. `Lookup.subtable` follows the extension offset again but uses the effective type found when the lookup was opened; it does not check the extension format and type again.
6. Accessor indices. `LangSys.featureIndex` and `Feature.lookupIndex` return null for a stored index that is no longer below `featureCount` or `lookupCount`.
7. LigCaretList coverage. A NULL coverage offset is `null_offset` (strictness row 14). A Coverage with an unsupported format makes the list `unsupported_version` with that format.
8. Short headers. A MarkGlyphSets header shorter than 4 bytes is `too_short`, and a CaretValue whose fields do not fit, including one past the table end, is `too_short`.
9. Masks. Selection writes `masks[i]` of the caller's slice after the `i < lookupCount` check, so under M12 the write named by X3 stays in a mask array of length 16, as the contract states.
10. Case 24. The comptime check visits 39 public functions: the five parse functions and 34 methods of the 13 public struct types. The case requires exactly 39, so it cannot pass over an empty set.
11. M22's observed defect. The contract says that `set(0)` gives [0, 12] under M22. Reading Offset16 values gives `0x0000` for set 0, and the NULL check of row 14 runs before the Coverage is parsed, so `set(0)` is `rejected null_offset`. The named case 18 still fails at `set(0)`.
12. fontTools line numbers. In the installed fontTools 4.66.1 files, which match the wheel's RECORD, `BaseTable.decompile` calls `postRead(table, font)` at `otBase.py` line 1003 and `readFormat` sets `self.Format` at lines 1236 and 1237, not 989 and 1221 to 1222. `Coverage.postRead` starts at `otTables.py` line 947 and deletes `Format` at line 970, and the five other `del self.Format` lines are 1207, 1276, 1371, 1458, and 1527. The cited behavior is the same. The contract's numbers may count the source at tag `4.66.1` differently [INFERENCE: the worker did not read the tag source].
13. Temporary worktrees. `raw/tests-before.log` and `raw/tests-before-duration.log` used `git worktree add` under `out/`. `raw/cleanup.log` removed both and ran `git worktree prune`, which only removes administrative entries whose directories no longer exist.

## Remaining obligations

These belong to other tasks, as the contract states:

- `FP-0112` applies GSUB lookups, lookup flags, mark filtering sets, and GDEF classes. It must open each Coverage and ClassDef once per run or bound total validation work.
- `FP-0113` applies GPOS lookups and reports Device, VariationIndex, and contour-point anchors.
- `FP-0118` places carets from `LigCaretList`.
- `FP-0114` and `FP-0115` map Unicode scripts and languages to OpenType tags.
- `FP-0059` evaluates FeatureVariations and applies the GDEF item variation store.
- `FP-0058` compares the strictness choices with web-font practice.

## Integration

The integrator records `raw/integration-binding.log`, runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0111/gates`, and records an uncached `raw/integration-tests.log`.
