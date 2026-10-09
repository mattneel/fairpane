# Text and font tests

## Scope

These tests cover task FP-0013: Unicode 18.0.0 properties and allocation-free OpenType parsing.
`build.zig` roots a test artifact at `root.zig`, which imports the library module as `fairpane`.
`zig build test` runs them.
Each test is named `FP-0013 case N: ...` after the case list in `engineering/evidence/FP-0013/CONTRACT.md`.
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
The file records the table directory, the raw fields of `head`, `hhea`, `maxp`, `OS/2`, and `post`, every `name` record,
the `cmap` subtables and selection, the glyph of every seed code point, the metrics and glyph headers of every mapped glyph,
the `GDEF`, `GSUB`, and `GPOS` versions and tags, and the CFF Name INDEX, CharStrings count, and CID keying.
Case 13 compares every field with Fairpane's parser, and case 12 compares the font's SHA-256.
Nobody edits an expectation file by hand; rerun the script instead.

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

## Stop rules

Some expected values are inferences about upstream content: zip member paths, coverage claims, U+20BB7 being in the CJK source, and release checksums.
If such a value fails, stop and report the observed value to the integrator.
Never edit an expectation file, a seed, or an upstream byte to pass a case.
