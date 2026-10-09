# Unicode, CLDR, and font-fixture import requirements

## Status

This file states the requirements for every Unicode, CLDR, and font-fixture import.
Bracketed identifiers name primary sources in `specs/sources.json`.

Task FP-0013 imports Unicode 18.0.0 data and four OpenType font fixtures as the file-set corpora `unicode` and `opentype-fixtures`.
`specs/snapshots/unicode.json` and `specs/snapshots/opentype-fixtures.json` record their sources, extracted files, and derived files.
The `unicode` import takes `ucd/UCD.zip` and twelve of its members into `src/unicode/ucd/`, with `https://www.unicode.org/license.txt` beside them.
Task FP-0013 imported eight of those members: `Scripts.txt`, `ScriptExtensions.txt`, `PropertyValueAliases.txt`, `extracted/DerivedBidiClass.txt`, `extracted/DerivedJoiningType.txt`, `extracted/DerivedGeneralCategory.txt`, `IndicSyllabicCategory.txt`, and `IndicPositionalCategory.txt`.
Task FP-0108 imported the other four: `auxiliary/GraphemeBreakProperty.txt`, `DerivedCoreProperties.txt`, `emoji/emoji-data.txt`, and `auxiliary/GraphemeBreakTest.txt`.
FP-0108 generates only `Grapheme_Cluster_Break`, `Indic_Conjunct_Break`, and `Extended_Pictographic` from them.
Task FP-0055 generates the other properties of `DerivedCoreProperties.txt` and `emoji-data.txt`, such as `ID_Start`, `ID_Continue`, and the emoji binary properties.
Every other file of the table below remains a later import, which task FP-0055 owns.
The `opentype-fixtures` import takes Noto Sans, Noto Sans Arabic, and Noto Sans Devanagari unchanged, and a recorded subset of Noto Sans CJK JP, into `tests/text/fonts/`.
The `specs/corpora.json` entries keep their `not-fetched` status until a separate protected commit applies the reviewed pins.
CLDR remains unimported.

## Common rules

Every import follows the snapshot procedure in `specs/README.md`.
An import records the upstream URL, the exact version, and the retrieval time.
It records the path, byte size, and SHA-256 of every imported file.
It records the path, byte size, and SHA-256 of the governing license text.
It stores upstream bytes without edits.
A generated table records its generator and the SHA-256 of each input file.
An import with an unknown version or unknown license terms is rejected.

## Unicode Character Database

### Version selection

1. Select the latest released version of the Unicode Standard at import time.
   ECMAScript requires source text interpretation under the latest version of the Unicode Standard. [S29]
2. Take every file from the numbered version directory `https://www.unicode.org/Public/<version>/`. [S27]
3. Do not take files from `https://www.unicode.org/Public/latest/`, because that URL follows each new release. [S27]
4. Do not take files from `https://www.unicode.org/Public/draft/`, because it holds preliminary material under review. [S27]
5. Do not use `https://www.unicode.org/Public/UNIDATA/`, which UAX #44 no longer recommends. [S27]
6. Use one Unicode version for every Unicode data consumer in a release profile.

A released UCD version never changes, and its versioned URLs remain stable. [S27]
Errors in a released version are corrected only in a later version. [S27]

### Data files

Paths are relative to the numbered version directory `https://www.unicode.org/Public/<version>/`.
The directory layout below was observed in the Unicode 18.0.0 directory. [S43]

| File | Consumer | Source |
| --- | --- | --- |
| `ucd/UnicodeData.txt` | String case mapping; decomposition mappings and canonical combining classes for `String.prototype.normalize` (UAX #15); `Canonical_Combining_Class` Virama for the ContextJ rules of RFC 5892 Appendix A | [S30], [S35], [S49] |
| `ucd/SpecialCasing.txt` | String case mapping, locale-insensitive entries | [S30] |
| `ucd/CaseFolding.txt` | Case-insensitive RegExp matching with the `u` or `v` flag | [S30] |
| `ucd/PropertyAliases.txt` | RegExp property names | [S30] |
| `ucd/PropertyValueAliases.txt` | RegExp property values and value aliases | [S30] |
| `ucd/DerivedCoreProperties.txt` | `ID_Start` and `ID_Continue` for identifiers; `Indic_Conjunct_Break` for UAX #29 rule GB9c in extended grapheme clusters | [S31], [S27], [S36] |
| `ucd/CompositionExclusions.txt` | Composition exclusions for `String.prototype.normalize` (UAX #15) | [S35], [S27] |
| `ucd/DerivedNormalizationProps.txt` | `Full_Composition_Exclusion` and the Quick_Check properties for `String.prototype.normalize` (UAX #15) | [S35], [S27] |
| `ucd/auxiliary/GraphemeBreakProperty.txt` | Grapheme cluster boundaries (UAX #29) for `Intl.Segmenter` and text editing | [S36], [S27], [S32] |
| `ucd/auxiliary/WordBreakProperty.txt` | Word boundaries (UAX #29) for `Intl.Segmenter` | [S36], [S27], [S32] |
| `ucd/auxiliary/SentenceBreakProperty.txt` | Sentence boundaries (UAX #29) for `Intl.Segmenter` | [S36], [S27], [S32] |
| `ucd/emoji/emoji-data.txt` | `Extended_Pictographic` for UAX #29 and UAX #14; emoji binary properties for RegExp property escapes | [S27], [S36], [S37], [S40] |
| `ucd/LineBreak.txt` | Line breaking classes (UAX #14) | [S37], [S27] |
| `ucd/EastAsianWidth.txt` | `East_Asian_Width`, which UAX #14 uses to resolve class AI, uses directly in rules LB19a and LB30, and uses in rule LB10, which gives a remaining CM or ZWJ the value `Na` | [S37], [S27] |
| `ucd/BidiBrackets.txt` | Paired bracket properties for the Unicode Bidirectional Algorithm (UAX #9) | [S14], [S27] |
| `ucd/BidiMirroring.txt` | `Bidi_Mirroring_Glyph` for bidirectional mirroring (UAX #9) | [S14], [S27] |
| `ucd/extracted/DerivedBidiClass.txt` | `Bidi_Class` values, including defaults for unassigned code points (UAX #9); UTS #46 `CheckBidi`, which applies RFC 5893 section 2 to the labels of a Bidi domain name, for URL host parsing, because the URL Standard sets `CheckBidi` to true for domain to ASCII and domain to Unicode | [S14], [S27], [S39], [S101], [S41] |
| `ucd/extracted/DerivedGeneralCategory.txt` | `General_Category`, listed explicitly for every range including `Cn`; the qualification seeds and the Universal Shaping Engine categories; UAX #14 rules LB15a and LB15b (`Pi` and `Pf`), LB19 (`Pi` and `Pf`), and LB30b (`Cn`), and rule LB10, which gives a remaining CM or ZWJ the value `Lu`; UTS #46 section 4.1 criterion 6, which rejects a label that begins with `General_Category=Mark`, for URL host parsing; imported by FP-0013 | [S27], [S50], [S37], [S39], [S41] |
| `ucd/Scripts.txt` | `Script` (UAX #24) and RegExp `Script` property escapes | [S38], [S30] |
| `ucd/ScriptExtensions.txt` | `Script_Extensions` (UAX #24) and RegExp `Script_Extensions` property escapes | [S38], [S30] |
| `ucd/VerticalOrientation.txt` | `Vertical_Orientation` (UAX #50) for CSS `text-orientation: mixed` | [S42], [S27] |
| `idna/IdnaMappingTable.txt` | UTS #46 mapping, which the URL Standard host parser uses through Unicode ToASCII and ToUnicode | [S39], [S41] |
| `ucd/extracted/DerivedJoiningType.txt` | `Joining_Type` for the ContextJ rules of RFC 5892 Appendix A, which UTS #46 section 4.1 applies when `CheckJoiners` is true, and the URL Standard sets `CheckJoiners` to true for domain to ASCII and domain to Unicode | [S49], [S39], [S41], [S27] |
| `ucd/extracted/DerivedJoiningType.txt` | `Joining_Type` for cursive joining in shaping, such as Arabic, and for Universal Shaping Engine joining features | [S27], [S50] |
| `ucd/IndicSyllabicCategory.txt` | `Indic_Syllabic_Category` for Universal Shaping Engine character categories in Indic and other complex scripts | [S50], [S27] |
| `ucd/IndicPositionalCategory.txt` | `Indic_Positional_Category` for Universal Shaping Engine positional subclasses of marks | [S50], [S27] |
| `emoji/emoji-sequences.txt` | `Basic_Emoji`, `Emoji_Keycap_Sequence`, `RGI_Emoji_Modifier_Sequence`, `RGI_Emoji_Flag_Sequence`, and `RGI_Emoji_Tag_Sequence` in ECMA-262 Table 67 | [S40], [S30] |
| `emoji/emoji-zwj-sequences.txt` | `RGI_Emoji_ZWJ_Sequence` in ECMA-262 Table 67; `RGI_Emoji` is the union of the UTS #51 sets | [S40], [S30] |
| `ucd/BidiTest.txt` and `ucd/BidiCharacterTest.txt` | Unicode Bidirectional Algorithm tests (UAX #9) | [S14], [S43] |
| `ucd/NormalizationTest.txt` | Unicode Normalization tests (UAX #15) | [S35], [S43] |
| `ucd/auxiliary/LineBreakTest.txt` | Unicode Line Breaking tests (UAX #14) | [S37], [S43] |
| `ucd/auxiliary/GraphemeBreakTest.txt`, `WordBreakTest.txt`, and `SentenceBreakTest.txt` | Text segmentation tests (UAX #29) | [S36], [S43] |
| `idna/IdnaTestV2.txt` | UTS #46 conformance tests | [S39], [S43] |

RegExp property escapes also need the property file for each property in the ECMAScript property tables. [S30]
The importing task locates each UCD property file through the UAX #44 property table for the selected version. [S27]
The emoji sequence files under `emoji/` are not formally part of the UCD, so that table does not list them. [S27]
UTS #51 documents those files, and the importing task takes them by name from the table above. [S40]
Since Unicode 17.0, the IDNA files sit in the numbered version directory; earlier versions kept them under `https://www.unicode.org/Public/idna/`. [S39]
ECMA-402 leaves `Intl.Segmenter` boundaries implementation-dependent and names the UAX #29 default algorithms. [S32]

`Joining_Type` is defined in `ucd/ArabicShaping.txt`, but that file omits many characters whose value derives by rule. [S27]
UAX #44 says implementations should rely on the explicit listing in `ucd/extracted/DerivedJoiningType.txt` instead. [S27]
The import therefore takes `Joining_Type` from `DerivedJoiningType.txt`, and takes `ArabicShaping.txt` only if a consumer needs another field of that file.
The ContextJ rules accept U+200C ZERO WIDTH NON-JOINER and U+200D ZERO WIDTH JOINER after a character whose canonical combining class is Virama. [S49]
They also accept U+200C in a context that they define with `Joining_Type` values L, D, T, and R. [S49]
The Universal Shaping Engine classifies characters by `Joining_Type`, `Indic_Syllabic_Category`, `Indic_Positional_Category`, and `General_Category`. [S50]
For scripts that the UCD category files do not cover, it uses supplementary files from Microsoft's USE repository. [S50]
Those supplementary files are not Unicode Data Files, so their import records their own license and provenance.

### License terms

Unicode Data Files include all computer data files under `https://www.unicode.org/Public/`. [S26]
Unicode Data Files are subject to the Unicode License v3 unless a specific restriction or license states otherwise. [S26]
The license permits use, copying, modification, and distribution. [S25]
The copyright and permission notice must appear with every copy or in associated documentation. [S25]
An import from `https://www.unicode.org/Public/` keeps `https://www.unicode.org/license.txt` beside the data and records its digest.
A generated table carries the same notice.

## Unicode CLDR

### Version selection

1. Select a numbered release from the CLDR releases table. [S28]
2. Do not select the development version or the `main` branch. [S28]
3. Pin the release's Git tag in `https://github.com/unicode-org/cldr` and record the tag's commit ID. [S28]
4. Alternatively, pin the versioned data directory `https://unicode.org/Public/cldr/<version>/` and record each file digest.
   Use this alternative only when the releases table links a data directory for that release. [S28]
   Several dot releases, such as 46.1, 44.1, and 43.1, list no data directory, so only their Git tags can pin them. [S28]
5. Record the Unicode version that the selected release targets, as its release note states. [S28]
6. Resolve any mismatch between that Unicode version and the UCD import before qualification.
7. Apply no CLDR corrigendum unless the import records it as a separate input. [S28]

Each CLDR release is stable and never changes after publication. [S28]

### Data files

ECMA-402 does not require CLDR data, but it recommends CLDR data in several places. [S32]
Fairpane selects CLDR as its locale data source, so these requirements apply.

| File or data | Consumer | Source |
| --- | --- | --- |
| Unit display names and patterns | `Intl.NumberFormat` unit formatting | [S32] |
| `common/bcp47/timezone.xml` | Primary and non-primary time zone identifiers | [S32] |
| UTS #35 key and type definitions | Unicode locale extension keys and value canonicalization | [S32] |
| UTS #35 LocaleId canonicalization data | `CanonicalizeUnicodeLocaleId` | [S32] |
| UTS #35 likely subtags | `Intl.Locale` text direction and related operations | [S32] |
| UTS #35 calendar preference, time, and week data | `Intl.Locale` calendars, hour cycles, and week information | [S32] |
| Locale display strings for dates, numbers, and names | Formatters, with CLDR strings recommended for `DateTimeFormat` | [S32] |
| `common/uca/FractionalUCA.txt` and `common/collation/root.xml` | The CLDR root collation, the base of `Intl.Collator` CompareStrings | [S32], [S52], [S54] |
| `common/collation/<language>.xml` | CLDR collation tailorings for the effective locale and collation options of `Intl.Collator` | [S32], [S52], [S54] |
| `common/supplemental/plurals.xml` | Cardinal plural rules for `Intl.PluralRules` with type `"cardinal"` | [S32], [S53], [S54] |
| `common/supplemental/ordinals.xml` | Ordinal plural rules for `Intl.PluralRules` with type `"ordinal"` | [S32], [S53], [S54] |
| `common/supplemental/pluralRanges.xml` | Plural categories of number ranges for `PluralRuleSelectRange` | [S32], [S53], [S54] |

ECMA-402 Table 2 defines the sanctioned single unit identifiers, a subset of the CLDR release 38 unit validity data. [S32]
The pinned CLDR release supplies unit display data only, and its unit validity data never changes the sanctioned set.
The importing task maps each UTS #35 data category to exact files in the pinned release.
The paths in the table above were observed at tag `release-48-2`. [S54]

### Collation source

ECMA-402 recommends that CompareStrings follow UTS #10 with tailorings for the effective locale and collation options. [S32]
It recommends the tailorings that CLDR provides. [S32]
CLDR tailorings are rules relative to the CLDR root collation, which is based on the DUCET but is not identical to it. [S52]
The collation source is therefore the CLDR root collation plus CLDR tailorings from the pinned CLDR release.
The DUCET in `uca/allkeys.txt` of the UCD version directory is not combined with CLDR tailorings. [S51], [S43]
`common/collation/root.xml` has a `standard` collation with an empty tailoring, which equals the CLDR root collation. [S52]
`common/uca/allkeys_CLDR.txt` holds the same root order in DUCET-style weights, and `common/uca/UCA_Rules.txt` approximates it as rules. [S52]

The root collation has its own UCA version.
At tag `release-48-2`, `common/uca/FractionalUCA.txt` states UCA version 17.0.0, and `common/uca/allkeys_CLDR.txt` states version 17.0.0. [S54]
The UCD version selection rule above selects Unicode 18.0.0 at the time of writing. [S43]
Rule 6 of the version selection applies to that difference: the import resolves it before qualification.
One resolution is a CLDR release whose root collation targets the selected UCD version.
The import records the UCA version that the root collation files state.

### License terms

The CLDR releases page refers to the Unicode Terms of Use for license information. [S28]
The Terms of Use classify `https://www.unicode.org/Public/cldr/` and `https://github.com/unicode-org/` content as Unicode products under the Unicode License v3. [S26]
A Git-tag import records the repository's `LICENSE` file at the pinned tag as the governing license text, with its path, byte size, and SHA-256.
For example, `LICENSE` at tag `release-48-2` states the Unicode License V3. [S44]
A data-directory import records `https://www.unicode.org/license.txt` instead.
The CLDR import follows the Unicode notice rules above. [S25]

## Font fixtures

### Admission rule

A font file enters the repository or a snapshot only when all of these conditions hold.

1. A license text that names the file's font software explicitly permits redistribution.
2. The import records per-file provenance as listed below.
3. The file is not a font or font data copied or extracted from a Unicode product, including the code charts. [S26]
4. The license notice travels with every copy.

The SIL Open Font License 1.1 is one acceptable license.
It permits redistribution bundled with software when each copy contains the copyright notice and the license. [S33]
It forbids selling the font software by itself. [S33]
It forbids a modified version from using a Reserved Font Name without written permission. [S33]
Its condition 5 requires the font software, modified or unmodified, in part or in whole, to be distributed entirely under the OFL and under no other license. [S33]
A subset or other modified fixture therefore drops any Reserved Font Name or records that permission.
An OFL fixture keeps its own OFL text and notice and never takes the repository's license.
The Apache License 2.0 is another candidate redistribution license. [S20]
A font with no license text, a personal-use license, or an evaluation license is rejected.

### Per-file provenance

Each font fixture record contains these fields.

- The upstream URL and the exact upstream revision or release version.
- The upstream path.
- The byte size and SHA-256 of the file.
- The license name as the license text states it.
- The path, byte size, and SHA-256 of the license text.
- The copyright notice and any Reserved Font Names.
- Every local transformation, with the tool, version, and input digest.

A corpus snapshot record covers only local use of the corpus, without redistribution.
Its license record names only the corpus's top-level license file.
Files inside a corpus can carry their own licenses.
For example, the pinned WPT tree contains third-party fonts under `fonts/`, such as `Lato-Bold.ttf`, `GentiumPlus-R.woff`, and the `adobe-fonts/` directory, and third-party code under `tools/third_party/`. [S48]
Before any such file is copied out of its corpus or used as a fixture, the import records that file's own license and applies the admission rule and per-file record above.

### Formats

Fixtures cover OpenType [S15] and WOFF2 [S16].
WOFF2 fixtures also exercise the Brotli decoder that WOFF2 requires. [S16]
