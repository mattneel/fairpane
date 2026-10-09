# FP-0119 evidence

## Scope

This record covers task `FP-0119`, "Decode TrueType glyph outlines into a bounded outline model".
`CONTRACT.md` freezes its behavior, its 14 test cases, its 13 mutation controls, and its integrator decisions.
The `fairpane-text` worker `FP0119Glyf` wrote this patch in an isolated worktree whose `HEAD` is `507ea53c81d87406cc2a9af887db5c0be6295407`, the commit that froze the contract.
Nothing is committed, and the protected paths are unchanged.
The worker ran no repository gate; the integrator runs them.

Every Zig command ran with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`, as each `RESULT` line's `environment_overrides` shows.
`node tools/fairpane.mjs record` recorded every command under `raw/`.

## Files changed

| File | Change |
| --- | --- |
| `src/font/outline.zig` | New. `Point`, `Verb`, `Path`, `Limits`, `max_composite_depth`, and `OutlineError`. |
| `src/font/glyf.zig` | New. `TrueTypeGlyph` with `deinit` and `path`, `Source`, `decode`, and the test-only counter `work`. |
| `src/font/opentype.zig` | `Font.trueTypeGlyph`, `outline_model`, `glyf_decoder`, test references to both files, and the restated module comment. `parse` and `glyphHeader` are unchanged. |
| `tests/text/glyf_builder.zig` | New. F_GLYF, its 45 entries, and its variants. |
| `tests/text/glyf_test.zig` | New. Cases 1 to 14, each named `FP-0119 case N: ...`. |
| `tests/text/root.zig` | Imports `glyf_test.zig`. |
| `tests/text/sfnt_builder.zig` | `simpleGlyph` is public. |
| `tests/text/README.md` | Line 5 names FP-0119 outline decoding. New sections describe F_GLYF, the observations, and the FP-0119 stop rules. |
| `specs/capabilities/text-fonts.json` | The frozen `glyph-rasterization.engine_behavior` text. The status stays `remaining`, and the owner stays `FP-0056`. |
| `engineering/evidence/FP-0119/observe.mjs` | New. Prints the case 14 observations. It asserts nothing and computes no expectation. |
| `engineering/evidence/FP-0119/raw/` | The logs and the 13 mutation diffs listed below. |

Nothing under `include`, `api`, or `tools` changed, and `src/c_api.zig` is unchanged.

## Design

`Font.trueTypeGlyph(gpa, glyph, limits)` passes the `glyf` reader, the `loca` table, and numGlyphs to `glyf_decoder.decode`.
The checks run in the frozen order: `GlyphOutOfRange`, then `NotTrueType`, then a zero-length `loca` range is an empty glyph.

A simple glyph is read in two passes over the packed flags, which `nextFlagRun` reads in both passes.
The first pass checks the point budget, the strictly increasing end points, the instructions, exactly `p` logical flags, and the length of both coordinate arrays.
Only then does the decoder reserve storage.
The second pass decodes the coordinates as `i64` prefix sums and appends the points, the on-curve flags, and the renumbered contour ends.

A composite uses a fixed array of `max_composite_depth` (8) frames.
Each frame holds its glyph ID, its record cursor, its first incorporated point, and the placement of the composite child being decoded.
A simple child is appended and placed at once.
A composite child pushes a frame, and it is placed when its frame finishes.
`place` applies the matrix to the child's points, computes the offset, and adds it.
No function in `glyf.zig` calls itself, and its native stack use does not depend on the composite depth.

Every list grows to the larger of the needed size and the smaller of `max_points` and double its capacity.
While the points budget holds, no capacity exceeds `max_points`.
So a decode holds at most 16 + 16 bytes per point during a points reallocation, plus 1 byte per on-curve flag and 4 bytes per contour end, which is below `64 · max_points + 65536` bytes.

## Criterion mapping

| FP-0119 criterion | Cases and evidence | Result |
| --- | --- | --- |
| Decode simple TrueType glyphs with checked bounds | Cases 1, 2, 8, and 10; M1 and M2 | Pass in `raw/tests-after.log`. M1 and M2 fail case 2. |
| Decode composite glyphs with bounded depth, cycle detection, and constant stack | Cases 1, 4 to 6, 9, and 13; M3 to M5, M8, M9, and M12 | Pass. Each control fails its named case. |
| Convert contours to closed paths, unhinted, and report phantom point matching as unsupported | Cases 3, 4, and 9 (Y6); M7, M10, and M11 | Pass. Each control fails its named case. |
| Reject malformed glyphs within budgets, and record strictness | Cases 7 to 9 and 11 to 13; M6 and M13; the strictness table | Pass. M6 and M13 fail case 7. The strictness table is implemented as frozen. |
| Check the three TrueType fixtures | Case 14 | Pass. No stop rule fired. |
| Add at most 10 seconds of test time | `raw/tests-before-duration.log` and `raw/tests-after.log` | The `tests/text` run step went from 325 ms to 1 s. |

## Evidence logs

| Log | Command | Result |
| --- | --- | --- |
| `raw/tests-before-duration-attempt-1.log` | `cmd /d /c ver`, then `zig build test` | Failed attempt. The shell removed the backslashes from the compiler path, so `record` reported "The executable is not on PATH" with no exit code. Nothing ran. |
| `raw/tests-before-duration.log` | `cmd /d /c ver`, then `zig build test --summary all --cache-dir out/fp0119-base` at the base | Exit status 0. Lines 28 to 33: 100 of 100 steps, 322 of 322 tests, and the `tests/text` run step, `run test 45 pass (45 total) 325ms`. |
| `raw/tests-before-attempt-1.log` | `zig build test --summary all --cache-dir out/fp0119-before` | Failed attempt, exit status 1. The test file used the `**` array operator, which the locked compiler no longer parses, so the failure did not show the missing interface. |
| `raw/tests-before.log` | The same command after `**` was replaced with `@splat` | Exit status 1. Lines 11 to 41: 4 compilation errors, `no member named 'outline_model'` and `no field or member function named 'trueTypeGlyph'`. |
| `raw/ast-check.log` | `zig ast-check` of the four new Zig files | Exit status 0 for each. |
| `raw/dev-iterations.log` | Three `zig build test` runs and one `zig fmt --check` during development | Run 1, exit status 1: a comptime `return` in `hex` and an ignored decode result. Run 2, exit status 1: an untyped optional error in `expectSameResult`. Run 3, exit status 0 with 59 of 59 `tests/text` tests. `zig fmt --check`, exit status 0. |
| `raw/mutation.log` and `raw/mutation-M1.diff` to `raw/mutation-M13.diff` | `git rev-parse HEAD` and `git diff --cached --stat`, then for each control: `sha256sum`, `git apply`, `sha256sum`, `zig build test`, `git apply -R`, and `sha256sum` | Every `git apply` and `git apply -R` exits with status 0, and every `zig build test` exits with status 1. See "Mutation controls". |
| `raw/tests-after.log` | `cmd /d /c ver`, then `zig build test --summary all --cache-dir out/fp0119-after` | Exit status 0. Lines 28 to 33: 100 of 100 steps, 336 of 336 tests, and `run test 59 pass (59 total) 1s`. `out/fp0119-after` did not exist before the run. |
| `raw/fmt.log` | `zig fmt --check build.zig src tests` | Exit status 0. |
| `raw/controller-tests-after.log` | `node --version`, then `node tools/fairpane.mjs test` | Node v26.7.0. Exit status 0, with 238 of 238 controller tests passing. |
| `raw/observations.log` | `node --version`, then `node engineering/evidence/FP-0119/observe.mjs` | Exit status 0. See "Case 14 observations". |

`raw/mutation.log` is 4.5 MB.
Under M6, E8 decodes to 76800 points, and `std.testing.expectError` prints the whole unexpected value in cases 7 and 13.
Those two lines hold most of the bytes.

## Mutation controls

`src/font/glyf.zig` was staged before the controls, so each diff is a real `git diff` against the staged file, with the index line `0be55a6`.
The file's SHA-256 is `2f6436fd84a00d0913b4040587cf1fa6253334c87ebd51ad9d6c19b25b64c11a` before each control and after each `git apply -R`, and `raw/mutation.log` records each mutated hash.
All controls used `--cache-dir out/fp0119-mutation`.

| Control | Mutation | `tests/text` result | Failing cases and the observed defect | `raw/mutation.log` lines |
| --- | --- | --- | --- | --- |
| M1 | A short x delta takes the opposite sign | 55 pass, 4 fail | Cases 2, 3, 10, and 14. Case 2: point 0 is (−10, 20), not (10, 20). | 39 to 118 |
| M2 | The repeat count is read as count + 1 | 54 pass, 5 fail | Cases 2, 3, 10, 12, and 14 return `InvalidGlyph` from the flag-count check. | 338 to 445 |
| M3 | `SCALED_COMPONENT_OFFSET` is ignored | 58 pass, 1 fail | Case 4: glyph 11, C5a, gives (100, 200), not (50, 100). | 665 to 685 |
| M4 | The depth check rejects level 8 | 56 pass, 3 fail | Cases 6, 7, and 13: D8 returns `CompositeTooDeep`. | 905 to 947 |
| M5 | The 2 × 2 matrix is transposed | 58 pass, 1 fail | Case 4: glyph 10, C4, maps (100, 0) to (0, −100). | 1167 to 1187 |
| M6 | The points budget check is removed | 56 pass, 3 fail, 3 leaks | Cases 7, 8, and 13: E8 decodes to 76800 points. The leaks are the unexpected successes that `expectError` does not free. | 1407 to 1526 |
| M7 | The all-off-curve start uses `q_0` | 56 pass, 3 fail | Cases 3, 4, and 10. Case 3: T2 starts at (0, 0), not (0, 50). | 1742 to 1793 |
| M8 | The cycle check is removed | 57 pass, 2 fail | Cases 6 and 13: SELF returns `CompositeTooDeep`, not `CompositeCycle`. | 2009 to 2043 |
| M9 | The transform is applied after alignment | 58 pass, 1 fail | Case 5: C6 point 3 is (40, 90), not (45, 95). | 2259 to 2285 |
| M10 | Phantom-range indices return `InvalidGlyph` | 58 pass, 1 fail | Case 9, row Y6: `InvalidGlyph`, not `UnsupportedPhantomPoint`. | 2501 to 2536 |
| M11 | Offsets are rounded when `ROUND_XY_TO_GRID` is set | 58 pass, 1 fail | Case 4: glyph 43, C5d, gives (51, 101), not (50.5, 100.5). | 2752 to 2776 |
| M12 | Byte point numbers are read as `int8` | 58 pass, 1 fail | Case 5: C9's point number `C8` becomes −56, and `pointIndex` returns `InvalidGlyph`. | 2992 to 3023 |
| M13 | The component check rejects a count equal to `max_components` | 58 pass, 1 fail | Case 7: F3 with `max_components` 4368 returns `OutlineTooLarge`. | 3239 to 3261 |

In every control's `Build Summary` line, the failed-test count equals the `tests/text` failures above, so no other test artifact failed.
M1 counts 336 tests and the others count 330. The `library-test` run step of 6 tests reports `cached` in later controls, as in the M7 block, and a cached step adds no test count [INFERENCE].

## Case 14 observations

`raw/observations.log` records these values, and no test asserts them.
`observe.mjs` reads the font bytes directly; it uses neither the Zig decoder nor fontTools.

| Font | Simple | Composite | Empty | Component records | Point matching |
| --- | --- | --- | --- | --- | --- |
| Noto Sans | 2229 | 1621 | 34 | 3331 | 0 |
| Noto Sans Arabic | 404 | 988 | 7 | 2550 | 0 |
| Noto Sans Devanagari | 622 | 217 | 6 | 401 | 0 |

Every component record sets `ARGS_ARE_XY_VALUES` and `ROUND_XY_TO_GRID`.
The other flags appear on these records:

| Flag | Noto Sans | Noto Sans Arabic | Noto Sans Devanagari |
| --- | --- | --- | --- |
| `ARG_1_AND_2_ARE_WORDS` | 1402 | 1440 | 218 |
| `MORE_COMPONENTS` | 1710 | 1562 | 184 |
| `USE_MY_METRICS` | 1236 | 439 | 182 |

No record sets a scale, an x and y scale, a 2 × 2 matrix, `WE_HAVE_INSTRUCTIONS`, `OVERLAP_COMPOUND`, either offset-scaling flag, or a reserved bit.
So the real fonts exercise byte and word offsets, but not transforms or point matching; F_GLYF covers those.

Every `maxp` maximum is reached exactly in all three fonts: `maxPoints`, `maxContours`, `maxCompositePoints`, `maxCompositeContours`, `maxComponentElements`, and `maxComponentDepth`.
The observed values equal the contract's table: 260, 24, 102, 6, 4, and 1 for Noto Sans; 778, 38, 237, 11, 8, and 1 for Noto Sans Arabic; and 127, 8, 113, 6, 3, and 1 for Noto Sans Devanagari.

## Stop rules

- Case 14 passed for every glyph of the three fonts, so no invariant failed.
- No fixture glyph returned `UnsupportedPhantomPoint`; no fixture component uses point matching.
- The `tests/text` run step went from 325 ms to 1 s, well under the 10-second limit.
- No frozen expectation contradicts its cited source. The worker checked each F_GLYF derivation against the `glyf` chapter at source commit `810414e13e39f68adfb5f12d525e6b50c850fbbc`: the flag bits, the coordinate forms, the pseudo-code record layout, the 2 × 2 matrix, the offset-scaling default, point alignment after the transform, and the instructions after the last record.

## Resolved ambiguities

1. Order of work. The worker drafted `outline.zig` and `glyf.zig` before the cases were complete.
   For `raw/tests-before.log`, both files were moved to `out/fp0119-hold/`, and `opentype.zig` did not yet reference them, so the log ran the cases against the base sources.
2. Base duration. `raw/tests-before-duration.log` ran in this worktree at `507ea53`, not in a separate worktree, so the shared repository's worktree list stayed unchanged.
   While it ran, the worker wrote the two new source files, which nothing imported, and edited `specs/capabilities/text-fonts.json`, which the Zig build does not read [INFERENCE].
3. Record sizing before the conflict check. Contract step 1 requires the record bytes before step 2 checks the transform flags.
   The record length follows the pseudo-code's `if`/`else if` chain, so a record with conflicting flags is sized by its first matching flag, and step 2 then returns `InvalidGlyph`.
4. Point-number signedness. The two arguments are stored as `i32`, which holds both signed offsets and unsigned point numbers.
   `pointIndex` rejects a negative number with `InvalidGlyph`. Unmutated code never produces one; M12 shows the guard.
5. Point-matching check order. The parent index `k` is checked before the child index `l`.
   No case combines a bad `k` with a bad `l`.
6. Data shorter than 10 bytes. A nonempty entry shorter than 10 bytes is decoded as a simple glyph, so simple-glyph step 1 returns `InvalidGlyph` whatever its first two bytes hold.
7. Child lookup before the depth check. The decoder reads the child's `loca` range to learn whether it is a composite, so a `loca` range that no longer lies inside `glyf` returns `InvalidGlyph` before the depth check.
8. Composite instructions. Each composite checks its own instructions when its last record is processed, including a nested composite.
9. Work counter. `decode` resets `glyf_decoder.work` to 0 at its start. An empty child counts as one simple-glyph instantiation.
10. Public names. The worker added `glyf_decoder.Source` and `glyf_decoder.decode` beside the frozen names. Neither collides with a local in `parse`.
11. F_GLYF layout. The entries follow each other with no padding, because a long `loca` needs none and the contract gives exact lengths.
12. Case 11. Prefixes rebuild F_GLYF with the shortened entry. Byte changes edit one built font in place and parse it again under `.report`, because the stored checksums no longer match.
13. Case 12. The counting allocator counts `resize` and `remap` growth as well as `alloc`, and the test also checks that every byte is freed.
14. Case 14. `contour_ends.len` is compared with `numberOfContours` for every simple glyph. Both are 0 for a simple glyph without points, so this adds no expectation.
15. Observations. The contract asks the README to record them without asserting them, so `observe.mjs` prints them, and no test reads them.

## Remaining obligations

These belong to other tasks, as the contract states:

- `FP-0057` owns `ROUND_XY_TO_GRID`, `USE_MY_METRICS`, glyph instructions, and point matching against phantom points. Vertical phantom points come from `FP-0061`.
- `FP-0059` owns `gvar`.
- `FP-0120` owns CFF charstrings.
- `FP-0121` and `FP-0122` own rasterization.
- `FP-0058` compares the strictness choices with web-font practice.

## Integrator steps

The contract names these steps:

1. Record `raw/integration-binding.log`.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0119/gates`.
3. Record an uncached `integration-tests.log`.
