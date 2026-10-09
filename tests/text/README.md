# Text and font tests

## Scope

These tests cover task FP-0013, Unicode 18.0.0 properties and allocation-free OpenType parsing, task FP-0111, the OpenType layout common tables and GDEF, and task FP-0119, TrueType outline decoding.
`build.zig` roots a test artifact at `root.zig`, which imports the library module as `fairpane`.
`zig build test` runs them.
Each test is named `FP-0013 case N: ...`, `FP-0111 case N: ...`, or `FP-0119 case N: ...` after the case list in `engineering/evidence/FP-0013/CONTRACT.md`, `engineering/evidence/FP-0111/CONTRACT.md`, or `engineering/evidence/FP-0119/CONTRACT.md`.
No test here shapes, segments, rasterizes, or selects a fallback font; `specs/capabilities/text-fonts.json` names the tasks that own that work.

## Font fixtures

| Directory | Font | Source | License |
| --- | --- | --- | --- |
| `fonts/noto-sans/` | `NotoSans-Regular.ttf`, unhinted, unmodified | `NotoSans-v2.015.zip` member `NotoSans/unhinted/ttf/NotoSans-Regular.ttf` | `OFL.txt` from the same archive |
| `fonts/noto-sans-arabic/` | `NotoSansArabic-Regular.ttf`, unhinted, unmodified | `NotoSansArabic-v2.013.zip` member `NotoSansArabic/unhinted/ttf/NotoSansArabic-Regular.ttf` | `OFL.txt` from the same archive |
| `fonts/noto-sans-devanagari/` | `NotoSansDevanagari-Regular.ttf`, unhinted, unmodified | `NotoSansDevanagari-v2.007.zip` member `NotoSansDevanagari/unhinted/ttf/NotoSansDevanagari-Regular.ttf` | `OFL.txt` from the same archive |
| `fonts/noto-sans-cjk-jp-subset/` | `cjk-subset.otf`, a fontTools subset | `NotoSansCJKjp-Regular.otf` at noto-cjk tag `Sans2.004` | `LICENSE` from the same tag |

Every font is distributed under the SIL Open Font License 1.1 with its own license text beside it.
`specs/snapshots/opentype-fixtures.json` records each file's upstream URL, release, commit, size, SHA-256, license, copyright notice, and Reserved Font Names.
`node tools/fairpane.mjs corpus-fetch opentype-fixtures` extracts the three unmodified fonts and every license file.
`node tools/fairpane.mjs corpus-derive opentype-fixtures` reproduces the CJK subset with fontTools 4.66.1 and its frozen argument vector.
The subset is an OFL Modified Version: it keeps the 20 distinct code points of the `cjk-greeting` seed and only name IDs 0, 7, 13, and 14.
`fonts/.gitattributes` keeps Git from converting any fixture byte.

## Expectation files

Each font has a `<stem>.expect.json` file beside it, such as `NotoSans-Regular.expect.json`.
`tools/fonts/font_expectations.py` writes it, reading the font only through fontTools 4.66.1.
The file has format version 2.
It records the table directory, the raw fields of `head`, `hhea`, `maxp`, `OS/2`, and `post`, every `name` record,
the `cmap` subtables and selection, the glyph of every seed code point, the metrics and glyph headers of every mapped glyph,
the `GDEF`, `GSUB`, and `GPOS` layout dumps that `tools/README.md` describes, and the CFF Name INDEX, CharStrings count, and CID keying.
FP-0013 case 13 compares every field except the layout dumps with Fairpane's parser, and it compares the layout versions, tags, and lookup counts.
FP-0111 case 25 compares the rest of each layout dump.
FP-0013 case 12 compares the font's SHA-256, the generator's script SHA-256 with the committed `tools/fonts/font_expectations.py`,
and the generator's fontTools version with `engineering/dependencies.json`.
The `tests/text` run step therefore runs in the build root and lists both files as inputs.
Nobody edits an expectation file by hand.
Run `node tools/fairpane.mjs font-expectations --check` to rerun the script under the hardened invocation that `tools/README.md` describes.

## Bounds and changed bytes

`bounds_test.zig` holds the revision 1 cases.
Case 50 builds cmaps with 512 and 513 distinct subtables, and case 51 builds 65535 encoding records that share one costly format 4 subtable.
Case 51 reads `Font.cmap_table.validations`, a counter that exists only in test builds.
Case 52 calls every index accessor past its count, and it changes font bytes after `parse` to check that no accessor panics or reads outside the font.
It changes each field that an accessor used to trust, then every single byte of `B_TT` and `B_CFF` in turn.

## Seeds

Each `seeds/<id>.json` file uses the `fairpane-text-seed` format, version 1, which `seed.zig` parses and validates.

| Seed | Content |
| --- | --- |
| `latin-baseline` | `Café café`, precomposed then decomposed |
| `arabic-greeting` | Arabic with a tanwin mark, an Arabic comma, and Arabic-Indic digits |
| `devanagari-greeting` | Devanagari with a virama conjunct, dependent vowels, a danda, and an anusvara |
| `cjk-greeting` | Han, Hiragana, Katakana, Hangul, and the supplementary-plane U+20BB7 |
| `mixed-direction` | Arabic followed by an isolated Latin run, `\u2068Fairpane 123\u2069` |
| `uncovered-emoji` | A woman, a skin-tone modifier, and a laptop that no fixture covers |

The seed properties are the short aliases of seven Unicode 18.0.0 properties, read from the UCD files.
Each coverage entry lists code points that a fixture maps (`covered`) and does not map (`uncovered`).
U+2068 and U+2069 stay unasserted in the `mixed-direction` coverage.

## Synthetic fonts

`sfnt_builder.zig` writes the frozen fonts `B_TT` and `B_CFF` in memory, deterministically, with correct checksums.
Named overrides change directory fields after layout and checksumming, so malformed variants stay small and exact.
Cases 15 through 40 build every malformed font from these two definitions.

## TrueType outlines

`glyf_test.zig` holds the FP-0119 cases, and `glyf_builder.zig` writes their fixture font, F_GLYF.
F_GLYF is `B_TT` with `indexToLocFormat` 1, a long `loca`, `maxp` 1.0 with 45 glyphs, one long horizontal metric, and 45 `glyf` entries.
The entries are the contract's hex strings and `simpleGlyph` calls, laid out in glyph order with no padding.
They cover flag repetition, every coordinate form, all-off-curve contours, every component transform, both offset-scaling flags,
point matching with byte and word point numbers, composite instructions, depth 8 and 9 chains, cycles, and the points and component budgets.
Variants replace one entry with changed or truncated bytes, and case 11 also changes single bytes of a built font in place.
Case 7 reads `glyf_decoder.work`, a counter that exists only in test builds.
Case 13 decodes on a thread with a 256 KiB stack.

Case 14 decodes every glyph of the three TrueType fixtures and compares the points with each glyph header and the `maxp` maxima.
The composite header bounds are compared with the rounded point bounds, an [INFERENCE] about how fontTools wrote them.
`engineering/evidence/FP-0119/raw/observations.log` records, without asserting them, the counts of simple, composite, and empty glyphs,
how many component records set each flag, and whether each `maxp` maximum is reached.
Every component of the three fixtures uses `ARGS_ARE_XY_VALUES` and `ROUND_XY_TO_GRID`, so none uses point matching.

## Stop rules

Some expected values are inferences about upstream content: zip member paths, coverage claims, U+20BB7 being in the CJK source, and release checksums.
If such a value fails, stop and report the observed value to the integrator.
Never edit an expectation file, a seed, or an upstream byte to pass a case.
If a case 14 invariant fails, stop and report the font, the glyph ID, and both values.
If any fixture glyph returns `UnsupportedPhantomPoint`, stop and report it.
If an F_GLYF expectation contradicts the OpenType `glyf` chapter, stop and report it instead of changing it.
If the `tests/text` run step grows by more than 10 seconds over its base on the development host, stop and report both durations.

## Layout fixtures

`layout_test.zig` holds FP-0111 cases 1 to 24, and `layout_builder.zig` writes their fixtures from the contract's byte strings.
Blob cases call `parseCoverage`, `parseClassDef`, and `parseDevice` on bytes from `chapter2` Examples 5 to 9, the `gdef` examples, and edge values.
The `chapter2` script examples E1, E2, and E34 and the `gdef` tables F_GDEF, F_GDEF4, and F_GDEF2 are fixed byte strings.
The builder writes G, a GSUB table with three scripts, seven features, and thirteen lookups of every kind that the contract names,
G11, which is G as version 1.1 with a FeatureVariations table, P, a GPOS table with nine lookups, T_MFS, and H(N), whose LangSys and Feature list index 0 N times.
It returns the position of every field that a case edits, so each malformed variant changes exactly one field.
Each case puts its table into `B_TT` and parses the font under `.reject`.
Case 17 reads `layout.work`, a selection counter that exists only in test builds.
Case 21 truncates and changes every byte of G, P, and F_GDEF, and case 22 changes the bytes after the handles were taken.
Case 23 selects and walks on a thread with a 256 KiB stack.

`layout_fixture_test.zig` holds FP-0111 case 25.
It compares every script, LangSys, feature, lookup, subtable, primary coverage, GDEF class, mark glyph set, and ligature caret of each fixture with its expectation file.
For each LangSys, it also requests that LangSys's distinct feature tags and compares every mask with the masks that the dumped lists give.

## FP-0111 stop rules

If a font digest differs from `specs/snapshots/opentype-fixtures.json` before a fontTools run, stop and report both values.
If case 25 finds a difference, stop and report the font, the table, the JSON path, and both values, which the case prints.
Never edit a fixture, an expectation file, or `tools/fonts/font_expectations.py` to pass a case.
If a fixture lookup or subtable is rejected or unsupported, or a fixture LangSys names more than 63 distinct tags, stop and report it.
If `font_expectations.py` exits with status 1, or `font-expectations --check` differs after a write run, stop and report it.
If an expectation contradicts the cited OpenType text, stop and report it instead of changing it.
