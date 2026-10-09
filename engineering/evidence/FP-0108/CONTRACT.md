# FP-0108 task contract

## Identity

Task ID: `FP-0108`, "Import grapheme cluster data and segment extended grapheme clusters".
Workstream: `text`.
Base: the commit that freezes this contract.
Prerequisite: `FP-0013`, accepted (`engineering/state.json:232-233`).
A `fairpane-spec` worker drafted this contract as the first slice of the `FP-0015` split, and the root integrator decided the questions below.
Assigned role: `fairpane-text`.
Authority: `routine-local-engineering`.

### Integrator decisions

- `FP-0015` is split into `FP-0108` to `FP-0118`, and `FP-0015` keeps its five criteria word for word as the closing task.
- `FP-0108` imports four members of the pinned `UCD.zip` that `specs/IMPORT_REQUIREMENTS.md` assigns to `FP-0055`, and generates only Grapheme_Cluster_Break, Indic_Conjunct_Break, and Extended_Pictographic from them. `FP-0055` still generates every other consumer property of `DerivedCoreProperties.txt` and `emoji/emoji-data.txt`, including `ID_Start` and `ID_Continue` for `FP-0095` and the emoji binary properties for RegExp property escapes. `FP-0055` imports every other file of the table.
- Paths are granted per task. `FP-0108` writes `src`, `tests`, `tools`, `build.zig`, `specs` except `specs/corpora.json`, and `engineering/evidence/FP-0108/`.
- A slice that implements a capability updates `specs/capabilities/text-fonts.json` and the FP-0013 cases that pin it, as a frozen part of its contract that its reviewers check. That update is not a separate acceptance-policy change. `FP-0108` therefore amends FP-0013 case 3 (`tools/ucd.test.mjs:91` asserts `UCD_FILES.length === 8`, and `emoji-data.txt` does not follow its line-1 version rule) and FP-0013 case 49 (`tools/fileset.test.mjs:402` and `tools/capabilities.mjs:11` freeze `grapheme-segmentation` as `remaining`).
- `auxiliary/GraphemeBreakTest.txt`, about 134 KB in the archive listing, is committed. The larger conformance files belong to `FP-0109` and `FP-0110`.
- UAX #29 revision 49 is normative. `GraphemeBreakTest.html` is informative, as its line 11 states. Where `GraphemeBreakTest.txt` disagrees with this contract's reading of UAX #29, the worker stops.
- The text model is UTF-16 code units through `web_string.View`. A lone surrogate is its own code point, as `CodePointIterator` already does (`src/web_string.zig:294-299`). Boundaries are code-unit indexes and never fall between the two units of a surrogate pair.
- `FP-0108` implements extended grapheme clusters (UAX29-C1-1) with no profile. `FP-0026`'s frontier decomposition owns tailoring.
- `specs/corpora.json` stays unchanged. Its `inventory_sha256` hashes the source listing (`UCD.zip` and the license), not the selected members (`sourceListingDigest`, `tools/fileset.mjs:376-379`).
- The worker may place the conformance test under `src/unicode/` if `@embedFile` cannot reach `src/unicode/ucd/` from `src/text/`.

### Observed facts that shaped the decisions

- Unicode 18.0.0 changed rule GB9c to `\p{InCB=Linker} \p{InCB=Extend}* × \p{InCB=Consonant}`, with no Consonant required before the Linker (UAX #29 revision 49, Modifications, citing 187-C47). `GraphemeBreakTest.txt` line 859 (`0061 × 094D × 0924`) and line 875 (`1CF5 × 0995`) exercise the change.
- U+200C is Grapheme_Cluster_Break Extend (`GraphemeBreakProperty.txt` line 275) and has the default Indic_Conjunct_Break value None (`DerivedCoreProperties.txt` line 13319). `GraphemeBreakTest.txt` line 877 gives `1CF5 × 200C ÷ 0995`.
- U+1CF5 is InCB Linker (`DerivedCoreProperties.txt` line 13336) and is not listed in `GraphemeBreakProperty.txt` (lines 272-273 skip it), so its Grapheme_Cluster_Break value is Other.
- `emoji-data.txt` line 1 is `# emoji-data.txt`, and its version is on line 8, `# Version: 18.0.0`.
- `emoji-data.txt` has no `@missing` line; its line 845 states `# All omitted code points have Extended_Pictographic=No`.
- `DerivedCoreProperties.txt` line 13319 is `# @missing: 0000..10FFFF; InCB; None`, and InCB data lines have two value fields, which `tools/ucd.mjs:100` rejects.
- `GraphemeBreakTest.txt` line 1 is `# GraphemeBreakTest-18.0.0.txt`, and its trailer states `# Lines: 853`.
- The `FP-0108` plan entry exists (`engineering/plan.json:3713`), so `validateCapabilityRecord` (`tools/capabilities.mjs:38`) accepts the owner `FP-0108`.
- `tools/selftest.mjs:27` imports `ucdCases` statically from `tools/ucd.test.mjs`, so a named import of a missing export would fail module linking for the whole controller suite.

## Sources

- Unicode 18.0.0 `UCD.zip`, <https://www.unicode.org/Public/18.0.0/ucd/UCD.zip>: 5,657,953 bytes, SHA-256 `7b3e555514060b92290d154f53655c5eb0fa62b16eb04c03434ff72d1a66a0d8`; inventory of 71 file members and 39,580,113 bytes, SHA-256 `37761bcf3660066413756e978f9d5ec7c7be3c187738f5d95785203c8dd8b2f4` (`specs/snapshots/unicode.json:8-27`). `specs/corpora.json` pins the source listing as `2511e5384857e35883ec38bd8c0d225d1ea7591f6ee6ba6347c572f6b47a59d7`.
- Unicode License v3, <https://www.unicode.org/license.txt>: 1,995 bytes, SHA-256 `e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96` [S25].
- Members imported by `FP-0108`, each bound by the inventory digest above:
  - `auxiliary/GraphemeBreakProperty.txt`, line 1 `# GraphemeBreakProperty-18.0.0.txt`, dated 2026-06-29.
  - `DerivedCoreProperties.txt`, line 1 `# DerivedCoreProperties-18.0.0.txt`, dated 2026-08-07; InCB section on lines 13311-13855.
  - `emoji/emoji-data.txt`, `# Version: 18.0.0` on line 8, dated 2026-01-30; Extended_Pictographic section on lines 845-1303.
  - `auxiliary/GraphemeBreakTest.txt`, dated 2026-06-12, with 853 test lines on lines 27-879.
  - The drafter could not compute member SHA-256 values in a read-only session. `corpus-fetch` records each member's size and SHA-256 in `specs/snapshots/unicode.json`, and FP-0013 case 48 checks them.
- UAX #29 revision 49, Unicode 18.0.0, dated 2026-09-01: <https://www.unicode.org/reports/tr29/tr29-49.html>, retrieved 2026-10-09. Sections 1.1 (notation and rule order), 1.2, 2 (UAX29-C1-1), 3 (Table 1c), 3.1 (Table 2), 3.1.1 (GB1 to GB999), and Modifications (rule GB9c) [S36].
- `GraphemeBreakTest.html` in the same archive, informative: set definitions on lines 14-33 and the rule list on lines 67-82.
- UAX #44 revision 38, section 4.2.10, `@missing` conventions [S60].
- UTS #51 as the source of `emoji-data.txt` [S40], and the `specs/IMPORT_REQUIREMENTS.md` rows for `ucd/DerivedCoreProperties.txt` (line 54), `ucd/auxiliary/GraphemeBreakProperty.txt` (line 57), `ucd/emoji/emoji-data.txt` (line 60), and `GraphemeBreakTest.txt`.
- Repository: `tools/ucd.mjs`, `tools/fileset.mjs`, `tools/capabilities.mjs`, `tools/selftest.mjs`, `src/unicode/properties.zig`, `src/unicode/reference_test.zig`, `src/web_string.zig`, `tests/text/seeds/*.json`, and the FP-0013 contract and README.

## Behavior

### Files

| File | Change |
| --- | --- |
| `tools/fileset.mjs` | `FILE_SET_RULES.unicode.selected` adds `ucdData('auxiliary/GraphemeBreakProperty.txt')`, `ucdData('DerivedCoreProperties.txt')`, `ucdData('emoji/emoji-data.txt')`, and `ucdData('auxiliary/GraphemeBreakTest.txt')` after `ucdData('IndicPositionalCategory.txt')` and before the license entry. |
| `src/unicode/ucd/auxiliary/`, `src/unicode/ucd/emoji/`, `src/unicode/ucd/DerivedCoreProperties.txt` | Unedited bytes written by `corpus-fetch unicode`. |
| `specs/snapshots/unicode.json`, `specs/applicability/unicode.json` | Rewritten by `corpus-fetch` and `corpus-applicability`. |
| `tools/ucd.mjs` | Three inputs, two parse modes, and three generated tables. |
| `src/unicode/tables.zig` | Regenerated. |
| `src/unicode/properties.zig` | Three properties in `Properties` and `lookup`. |
| `src/unicode/reference_test.zig`, `src/unicode/properties_test.zig` | Cases 7 to 10. |
| `src/text/text.zig`, `src/text/grapheme.zig`, `src/text/grapheme_test.zig` | The segmentation module and cases 11, 12, 14, 15, and 16. |
| `src/root.zig` | Exports `text` and references the new test file. |
| `tests/text/grapheme_seed_test.zig`, `tests/text/root.zig` | Case 13. |
| `tools/ucd.test.mjs`, `tools/fileset.test.mjs`, `tools/capabilities.mjs`, `specs/capabilities/text-fonts.json` | Cases 1 to 6 and the record update. |
| `specs/IMPORT_REQUIREMENTS.md`, `tools/README.md` | Documentation. |

### Unicode files imported now

| Member | Destination | Property | Consumer |
| --- | --- | --- | --- |
| `auxiliary/GraphemeBreakProperty.txt` | `src/unicode/ucd/auxiliary/GraphemeBreakProperty.txt` | Grapheme_Cluster_Break (`GCB`) | Generator; cases 7 to 13 |
| `DerivedCoreProperties.txt` | `src/unicode/ucd/DerivedCoreProperties.txt` | Indic_Conjunct_Break (`InCB`) only | Generator; cases 7 to 13 |
| `emoji/emoji-data.txt` | `src/unicode/ucd/emoji/emoji-data.txt` | Extended_Pictographic only | Generator; cases 7 to 13 |
| `auxiliary/GraphemeBreakTest.txt` | `src/unicode/ucd/auxiliary/GraphemeBreakTest.txt` | Conformance data | Case 11 |

Each `published_url` is `https://www.unicode.org/Public/18.0.0/ucd/<member>`, as `ucdData` builds it (`tools/fileset.mjs:24`).
`corpus-fetch` downloads each `published_url` and fails with `The published_url <url> serves bytes that differ from member <member>.` when the bytes differ (`tools/fileset.mjs:673-676`). That failure is a stop rule.
The existing `src/unicode/ucd/.gitattributes` (`* -text`) covers the new subdirectories [INFERENCE: a pattern without a slash matches at every depth].

### Generator

`UCD_FILES` gains, in this order after the existing eight: `src/unicode/ucd/auxiliary/GraphemeBreakProperty.txt`, `src/unicode/ucd/DerivedCoreProperties.txt`, and `src/unicode/ucd/emoji/emoji-data.txt`.
`GraphemeBreakTest.txt` is not a generator input.

- Grapheme_Cluster_Break uses the existing single-property mode with the `GCB` aliases and `onlyOccurring: true`. The generated enum `GraphemeClusterBreak` has exactly the 14 values that the file assigns, in `PropertyValueAliases.txt` order: `CN, CR, EX, L, LF, LV, LVT, PP, RI, SM, T, V, XX, ZWJ`. Those are aliases lines 792-809 without `EB`, `EBG`, `EM`, and `GAZ`, which UAX #29 Table 2 marks obsolete and unused.
- Field-selected mode, `parseFieldProperty(text, { file, aliases, property })`, for `InCB`: a data or `@missing` line whose first field after the range is exactly `property` must have exactly one more field, the value, which resolves through `aliases`. A line whose first field names another property is skipped. The result has `valueAt(codePoint)`, which returns the short alias. The generated enum `IndicConjunctBreak` is `Consonant, Extend, Linker, None`.
- Binary mode, `parseBinaryProperty(text, { file, property })`, for `Extended_Pictographic`: a line whose only field is exactly `property` sets the property for its range. A line with another single field is skipped. A line whose first field is `property` and that has another field fails. Every unlisted code point has the value false. The result has `valueAt(codePoint)`, which returns a boolean. The generated table is `extended_pictographic_ranges: [_]Range(bool)`.
- Comments are stripped before fields are split, so `Extended_Pictographic#` (`emoji-data.txt` line 847) parses.
- Every failure names the file and line in the existing `<file> line <n>: <message>` form.
- The generated header lists all 11 inputs and the license with sizes and SHA-256 values, as it does now.

### Property module

`src/unicode/properties.zig` adds:

```zig
pub const GraphemeClusterBreak = tables.GraphemeClusterBreak;
pub const IndicConjunctBreak = tables.IndicConjunctBreak;
// Properties gains:
gcb: GraphemeClusterBreak,
incb: IndicConjunctBreak,
ext_pict: bool,
```

`lookup` is the only lookup API, and it returns ten properties. Its doc comment says "Returns the ten properties of `code_point`".
The comptime block of `properties.zig` also asserts that the three new tables start at U+0000.
Both enums have `fromAlias` with the FP-0013 semantics: an exact match against any alias field.
Lookups allocate nothing.
The names `fairpane.text.GraphemeBoundaries`, `init`, `next`, `units_read`, `GraphemeClusterBreak`, `IndicConjunctBreak` and their tags, the `Properties` fields `gcb`, `incb`, and `ext_pict`, and the controller functions `parseFieldProperty` and `parseBinaryProperty` are frozen, because the cases and the capability record cite them. The worker may rename other declarations without changing behavior.

### Segmentation module

`src/text/text.zig` is the public module, exported from `src/root.zig` as `text`.
`src/text/grapheme.zig` holds:

```zig
pub const GraphemeBoundaries = struct {
    pub fn init(string: web_string.View) GraphemeBoundaries;
    /// The next extended grapheme cluster boundary, or null after the last one.
    pub fn next(self: *GraphemeBoundaries) ?web_string.CodeUnitIndex;
};
```

- An empty string yields no boundary, because GB1 and GB2 exclude empty text.
- A nonempty string yields 0 first and its code-unit length last, with strictly increasing indexes.
- Code points follow `CodePointIterator`: a high surrogate followed by a low surrogate is one code point, and every other surrogate is its own code point with its own properties.
- Each code point's properties come from `unicode.lookup`.
- Between code points `p` and `n`, the first matching rule decides, in this order (UAX #29 section 3.1.1): GB3 `CR × LF`; GB4 `(CN|CR|LF) ÷`; GB5 `÷ (CN|CR|LF)`; GB6 `L × (L|V|LV|LVT)`; GB7 `(LV|V) × (V|T)`; GB8 `(LVT|T) × T`; GB9 `× (EX|ZWJ)`; GB9a `× SM`; GB9b `PP ×`; GB9c `InCB=Linker InCB=Extend* × InCB=Consonant`; GB11 `ExtPict EX* ZWJ × ExtPict`; GB12 and GB13 `× RI` when an odd number of consecutive RI code points ends at `p`; GB999 `÷`.
- In GB11, `EX*` means Grapheme_Cluster_Break Extend. In GB9c, `Extend*` means InCB Extend.
- The iterator keeps constant-size state: the previous code point's properties, whether a Linker followed only by InCB Extend code points ends at `p`, whether `ExtPict EX*` preceded a ZWJ that ends at `p`, and the parity of the RI run that ends at `p`.
- Every read of the string's code units goes through one accessor. In test builds only (`builtin.is_test`), that accessor increments the field `units_read`.
- No function allocates or recurses. Work is linear in the code-unit length.

### Capability record

- `grapheme-segmentation` becomes `implemented` with owner `FP-0108`. Its summary names the three properties and UAX #29 extended grapheme clusters. Its `engine_behavior` states that `fairpane.text.GraphemeBoundaries` yields UAX #29 GB1 to GB999 boundaries as UTF-16 code-unit indexes without allocation, and that legacy clusters, tailorings, and random-access boundary queries are not offered.
- `unicode-properties` keeps its status and owner. Its summary appends ", and Grapheme_Cluster_Break, Indic_Conjunct_Break, and Extended_Pictographic", and its `engine_behavior` replaces "all seven properties" with "all ten properties" (`specs/capabilities/text-fonts.json:10-11`).
- `unicode-remaining-data` keeps its status and owner. Its `engine_behavior` replaces "beyond the seven properties above" with "beyond the ten properties above". Its summary names word and sentence segmentation, the conformance files other than `GraphemeBreakTest.txt`, and the properties of `DerivedCoreProperties.txt` and `emoji-data.txt` other than Indic_Conjunct_Break and Extended_Pictographic.
- `TEXT_FONT_OBLIGATIONS` (`tools/capabilities.mjs:8-18`) and FP-0013 case 49 change only the `grapheme-segmentation` row.

### Documentation

- `specs/IMPORT_REQUIREMENTS.md` "Status" names the twelve imported members and `FP-0108`, and states that `FP-0055` generates the other properties of `DerivedCoreProperties.txt` and `emoji-data.txt`.
- `tools/README.md` describes `parseFieldProperty` and `parseBinaryProperty`.
- The `src/text/text.zig` module documentation lists the remaining obligations below.

### Stop rules

- If `GraphemeBreakTest.txt` does not have 853 test lines, or its trailer differs, stop and report.
- If a conformance line contradicts the rule reading above, stop and report the line and the UAX #29 text.
- If any row of cases 8, 9, 12, or 13 contradicts the cited file lines, stop and report the observed value. Never edit an expectation.
- If `corpus-fetch` reports that a `published_url` serves different bytes, stop and report.
- If any new test takes more than 30 s in the Debug profile, report its duration before proceeding.

## Exact test cases

Zig cases are named `FP-0108 case N: ...` and run through `zig build test`.
Controller cases run through `node tools/fairpane.mjs test`.
Cases 1 and 6 amend existing tests in place; their names become `FP-0013 case 3 (amended by FP-0108 case 1): ...` and `FP-0013 case 49 (amended by FP-0108 case 6): ...`.
`tools/ucd.test.mjs` reads the new generator functions through `import * as ucd from './ucd.mjs'`, so a missing export fails only the case that calls it.
Before the change, every Zig case fails to compile. The before log must show compile errors that name a missing FP-0108 file or declaration, such as `src/text/grapheme.zig`, `src/unicode/ucd/auxiliary/GraphemeBreakTest.txt`, or the field `gcb`.

### Controller

1. `ucd-check` exits 0. `UCD_FILES` has exactly the 11 paths above, in order. Line 1 of each file except `emoji/emoji-data.txt` equals `# <basename>-18.0.0.txt`. `emoji-data.txt` line 1 equals `# emoji-data.txt`, and its line 8 equals `# Version: 18.0.0`. The reference test embeds every input. Fails at base: `tools/ucd.mjs:14-23` lists 8 paths.
2. `ucd.parseFieldProperty(text, { file: 'Fixture.txt', aliases, property: 'InCB' })`, with the aliases `InCB; Consonant ; Consonant`, `InCB; Extend ; Extend`, `InCB; Linker ; Linker`, and `InCB; None ; None` and this file:
   ```text
   # @missing: 0000..10FFFF; InCB; None
   0041          ; Alphabetic # x
   0915..0939    ; InCB; Consonant # Lo
   094D          ; InCB; Linker
   0300..0301    ; InCB; Extend
   ```
   gives U+0041 None, U+0914 None, U+0915 Consonant, U+0939 Consonant, U+093A None, U+094D Linker, U+0300 Extend, U+0301 Extend, and U+10FFFF None. Fails at base with `TypeError: ucd.parseFieldProperty is not a function`.
3. `ucd.parseBinaryProperty(text, { file: 'Fixture.txt', property: 'Extended_Pictographic' })` with this file:
   ```text
   0041..0043    ; Extended_Pictographic# a
   0044          ; Emoji                # b
   00A9          ; Extended_Pictographic
   ```
   gives U+0040 false, U+0041 true, U+0043 true, U+0044 false, U+00A9 true, and U+10FFFF false. Fails at base with `TypeError: ucd.parseBinaryProperty is not a function`.
4. Each of these, as line 3 of a file whose lines 1 and 2 are `# header` and empty, fails with a distinct message that begins `Fixture.txt line 3:`: through `parseFieldProperty`, `0915 ; InCB` (no value), `0915 ; InCB; Nope` (unknown value "Nope"), and `0915 ; InCB; Linker; Extra` (more than one value); through `parseBinaryProperty`, `0041 ; Extended_Pictographic; Y`. Through `parseFieldProperty`, `# @missing: 0000..10FFFF; InCB` as line 1 fails and names line 1. Fails at base with `TypeError: ucd.parseFieldProperty is not a function`.
5. After `corpus-fetch unicode`, `specs/applicability/unicode.json` has `discovered` 71, `selected` 12, `unclassified` 59, and the breakdown `.` 45, `auxiliary` 11, `emoji` 3, `extracted` 12. `specs/snapshots/unicode.json` keeps the `UCD.zip` and license digests above and lists the four new members with the URLs above. The `unicode` entry of `specs/corpora.json` is unchanged. Fails at base: `specs/applicability/unicode.json:14` is 8, and `tools/fileset.mjs:54-58` selects 8 members.
6. The record validates. The frozen rows equal the rows at the base commit, except `['grapheme-segmentation', 'implemented', 'FP-0108']`. The three rejection variants still throw. Fails at base: `tools/capabilities.mjs:11` and `specs/capabilities/text-fonts.json:36-37`.

### Zig: data

7. `src/unicode/reference_test.zig`: an independent, test-only parser of the three embedded files, which shares no code with `tools/ucd.mjs` or `properties.zig` and never calls `fromAlias`, finds `lookup(cp).gcb`, `.incb`, and `.ext_pict` equal for every code point from 0 to 0x10FFFF. It marks every code point as assigned by a value or a default.
8. Hard-coded rows of `lookup`. GBP is `GraphemeBreakProperty.txt`, DCP is `DerivedCoreProperties.txt`, and GBT is `GraphemeBreakTest.txt`.

| Code point | gcb | incb | ext_pict | Evidence |
| --- | --- | --- | --- | --- |
| U+0000 | CN | None | false | GBP line 53 |
| U+000A | LF | None | false | GBP line 47 |
| U+000D | CR | None | false | GBP line 41 |
| U+0020 | XX | None | false | unlisted; GBP line 17 |
| U+00A9 | XX | None | true | emoji-data line 847 |
| U+0300 | EX | Extend | false | GBP line 84; DCP line 13439 |
| U+0378 | XX | None | false | unlisted |
| U+0600 | PP | None | false | GBP line 21 |
| U+0903 | SM | None | false | GBP line 521 |
| U+0915 | XX | Consonant | false | DCP line 13354 |
| U+094D | EX | Linker | false | GBP line 115; DCP line 13325 |
| U+0C95 | XX | None | false | unlisted; GBT line 874 |
| U+1100 | L | None | false | GBP line 684 |
| U+1160 | V | None | false | GBP line 691 |
| U+11A8 | T | None | false | GBP line 700 |
| U+1CF5 | XX | Linker | false | DCP line 13336 |
| U+200C | EX | None | false | GBP line 275; DCP line 13319 default; GBT line 877 |
| U+200D | ZWJ | Extend | false | GBP line 1515; DCP line 13625 |
| U+AC00 | LV | None | false | GBP line 707 |
| U+AC01 | LVT | None | false | GBP line 1111 |
| U+D800 | XX | None | false | unlisted |
| U+16D63 | V | None | false | GBP line 693 |
| U+1F1E6 | RI | None | false | GBP line 515; emoji-data line 970 ends at 1F1E5 |
| U+1F3FB | EX | Extend | false | GBP line 507; DCP line 13851; emoji-data lines 1031-1032 skip it |
| U+1F469 | XX | None | true | emoji-data line 1050 |
| U+E0001 | CN | None | false | GBP line 75 |
| U+10FFFF | XX | None | false | unlisted |

9. Counts over all 1,114,112 code points equal the file totals.
   - gcb: PP 27 (GBP line 37), CR 1 (line 43), LF 1 (line 49), CN 3,893 (line 80), EX 2,274 (line 511), RI 26 (line 517), SM 381 (line 680), L 125 (line 687), V 100 (line 696), T 137 (line 703), LV 399 (line 1107), LVT 10,773 (line 1511), ZWJ 1 (line 1517), and XX 1,095,974. Derivation: 27 + 1 + 1 + 3,893 + 2,274 + 26 + 381 + 125 + 100 + 137 + 399 + 10,773 + 1 = 18,138, and 1,114,112 − 18,138 = 1,095,974.
   - incb: Linker 23 (DCP line 13348), Consonant 913 (line 13433), Extend 2,254 (line 13855), and None 1,110,922 = 1,114,112 − (23 + 913 + 2,254).
   - ext_pict: true 2,830 (`emoji-data.txt` line 1303, `# Total elements: 2830`), and false 1,111,282. The file counts elements as code points: its Emoji_Component total, 146 (line 841), equals the code points of lines 830-839, 1 + 1 + 10 + 1 + 1 + 1 + 26 + 5 + 4 + 96.
10. `GraphemeClusterBreak` has exactly the tags `CN, CR, EX, L, LF, LV, LVT, PP, RI, SM, T, V, XX, ZWJ`, in that order. `fromAlias` gives CN for `Control` and `CN`, EX for `Extend`, PP for `Prepend`, RI for `Regional_Indicator`, SM for `SpacingMark`, XX for `Other`, ZWJ for `ZWJ`, and null for `E_Base`, `EB`, `Glue_After_Zwj`, and `Nope`. `IndicConjunctBreak` has exactly `Consonant, Extend, Linker, None`. `fromAlias("Linker")` is Linker, and `fromAlias("linker")` is null.

### Zig: segmentation

11. Every one of the 853 test lines of the embedded `GraphemeBreakTest.txt` gives exactly its boundaries. The runner encodes each line's code points as UTF-16, maps each `÷` to its code-unit index, and treats each `×` as no boundary. The count of test lines equals the trailer value 853, and line 1 equals `# GraphemeBreakTest-18.0.0.txt`. A failure prints the line number.
12. Rows that do not depend on the file parser. Columns are the test file line, the code points, and the expected code-unit boundaries.

```text
G1  852  0915 094D 0924                    ⇒ 0 3
G2  859  0061 094D 0924                    ⇒ 0 3
G3  877  1CF5 200C 0995                    ⇒ 0 2 3
G4  875  1CF5 0995                         ⇒ 0 2
G5  835  0061 1F1E6 1F1E7 1F1E8 0062       ⇒ 0 1 5 7 8
G6  846  1F476 1F3FF 0308 200D 1F476 1F3FF ⇒ 0 10
G7  848  0061 200D 1F6D1                   ⇒ 0 2 4
G8  827  000D 000A 0061 000A 0308          ⇒ 0 2 3 4 5
G9  833  AC01 11A8 1100                    ⇒ 0 2 3
G10 841  0061 0903 0062                    ⇒ 0 2 3
G11 842  0061 0600 0062                    ⇒ 0 1 3
G12 834  1F1E6 1F1E7 1F1E8 0062            ⇒ 0 4 6 7
```

   Derivations of nontrivial rows:
   - G2: GB9 joins U+094D, which is EX. GB9c joins U+0924, because U+094D is Linker and U+0924 is Consonant. Revision 49 requires no Consonant before the Linker.
   - G3: U+200C is EX, so GB9 joins it. Its InCB value is the default None, so GB9c does not apply before U+0995, and GB999 breaks at 2.
   - G5: the units are `a` [0,1), A [1,3), B [3,5), C [5,7), and `b` [7,8). GB13 joins B to A, after one RI. Two RI precede C, so GB999 breaks at 5.
   - G6: each supplementary code point has 2 units, so the length is 2 + 2 + 1 + 1 + 2 + 2 = 10. GB9 joins U+1F3FF, U+0308, U+200D, and the final U+1F3FF, and GB11 joins the second U+1F476.
   - G7: GB9 joins U+200D. GB11 does not apply, because U+0061 is not ExtPict, so GB999 breaks at 2.
   - G12: GB12 joins B to A at the start of text. C follows two RI, so 4 is a boundary, and U+0062 follows C at 6.

   UTF-16 rows, derived from the rules and `src/web_string.zig:294-299`:

```text
U1  units D800 0308 DC00 0061 ⇒ 0 2 3 4
U2  units D83D DE00 0308      ⇒ 0 3
U3  units DE00 D83D           ⇒ 0 1 2
U4  units D83D                ⇒ 0 1
U5  no units                  ⇒ no boundary
```

   - U1: U+D800 and U+DC00 are lone surrogates with gcb XX. GB9 joins U+0308 to U+D800, and GB999 breaks at 2 and 3.
   - U2: D83D DE00 is the single code point U+1F600, and GB9 joins U+0308.
   - U5: GB1 and GB2 exclude empty text.

13. Seeds, parsed through `tests/text/seed.zig`, give these code-unit boundaries:

```text
latin-baseline       ⇒ 0 1 2 3 4 5 6 7 8 10
arabic-greeting      ⇒ 0 1 2 3 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
devanagari-greeting  ⇒ 0 1 2 6 7 9 11 13 14 15 18 20
cjk-greeting         ⇒ 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 23
mixed-direction      ⇒ 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28
uncovered-emoji      ⇒ 0 4 6
```

   Derivations:
   - `latin-baseline`: only U+0301 at index 9 is EX (GBP line 84), so 9 is not a boundary.
   - `arabic-greeting`: only U+064B at index 4 is EX (GBP line 93). U+060C and U+0661 to U+0663 are unlisted, so they are XX.
   - `devanagari-greeting`, at indexes 0 to 19: 0928 092E 0938 094D 0924 0947 0020 0926 0941 0928 093F 092F 093E 0964 0020 0939 093F 0902 0926 0940. GB9 joins 094D at 3, 0947 at 5 (GBP line 114), 0941 at 8, and 0902 at 17 (GBP line 111). GB9c joins 0924 at 4 (DCP lines 13325 and 13354). GB9a joins 093F at 10 and 16, 093E at 12, and 0940 at 19 (GBP line 523). Index 9 is a boundary, because U+0941 follows U+0926, not a Linker.
   - `cjk-greeting`: 22 code points, the last of which, U+20BB7, occupies units 21 and 22. U+D55C, U+AD6D, and U+C5B4 are LV or LVT, and no GB6 to GB8 rule joins one syllable to the next. No other code point is EX or SM.
   - `mixed-direction`: 28 BMP code points. U+2068 and U+2069 are CN (GBP line 67), and no code point is EX, SM, or PP.
   - `uncovered-emoji`: units 1F469 [0,2), 1F3FD [2,4), and 1F4BB [4,6). GB9 joins U+1F3FD (GBP line 507). No ZWJ precedes U+1F4BB, so GB999 breaks at 4.

14. For every input of cases 11 to 13, boundaries strictly increase, start at 0, end at the length, and never fall between a high surrogate and the low surrogate that follows it.
15. Linear work, checked one boundary at a time without storing the boundaries:
    - `a` followed by 999,999 × U+0308 gives exactly 0 and 1,000,000.
    - 500,000 × U+1F1E6 gives exactly the 250,001 multiples of 4 from 0 to 1,000,000.
    - 333,333 × (U+0915 U+094D) followed by U+0924 gives exactly 0 and 666,667, by GB9 and GB9c.
    - For each input, after every call of `next` that returns index `b`, `units_read` is at most 2 × `b` + 4. After `next` returns null, `units_read` is at most 2 × the code-unit length. The bound is checked after every call, so a superlinear implementation fails within the first few boundaries instead of running for hours.
16. A comptime check finds no `std.mem.Allocator` among the parameter types of `GraphemeBoundaries.init` and `next`, and `next` returns `?web_string.CodeUnitIndex`. The case also reads `src/text/grapheme.zig` and `src/text/text.zig` through `@embedFile` and finds none of `Allocator`, `allocator`, and `std.heap`.

### Mutation controls

Each control is a `.diff` applied with `git apply`, run, and reversed with `git apply -R`.
The worker records file hashes before, during, and after each control, and records a crash separately from a failed assertion.

- M1: remove GB9c. Must fail case 12 row G1, case 13 `devanagari-greeting` (index 4 becomes a boundary), and case 11 at line 852.
- M2: require an InCB Consonant before the Linker, as Unicode 15.1 did. Must fail case 12 rows G2 and G4 and case 11 at lines 859 and 875.
- M3: join every RI pair regardless of parity. Must fail case 12 rows G5 and G12, case 11 at line 835, and the RI input of case 15.
- M4: let GB11 join any `ZWJ × ExtPict`. Must fail case 12 row G7 and case 11 at line 848.
- M5: remove GB9a. Must fail case 12 row G10 and case 13 `devanagari-greeting`.
- M6: decode each code unit as its own code point. Must fail case 12 row U2 and case 13 `uncovered-emoji` and `cjk-greeting`.
- M7: in `src/unicode/tables.zig`, change the `grapheme_cluster_break_ranges` entry that starts at `0x000903` from `.SM` to `.XX`. Must fail cases 7, 8 (row U+0903), 9 (SM becomes 380), 11 (every line containing U+0903, including line 841), and 12 row G10, and controller case 1, because `ucd-check` reports the table stale.
- M8: at each RI, recount the RI run by reading backward from `p` to the run's start through the counting accessor. Must fail case 15 on the `units_read` bound of its RI input.

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Import the four members with per-file provenance | 1, 5, FP-0013 case 48 |
| Generate the three lookups with a staleness check and an independent reference test | 1 to 4, 7 to 10; M7 |
| Segment UTF-16 text under GB1 to GB999 without allocation and in linear time | 12, 14 to 16; M1 to M6, M8 |
| Pass `GraphemeBreakTest.txt` and the six seeds | 11, 13 |
| Update the capability record and the FP-0013 cases that pin it | 1, 6 |

`FP-0108` contributes to FP-0015 criterion 4, because caret positions need grapheme boundaries, and to criterion 5 through the record.

### Remaining obligations

- Preceding and following boundary queries from any code-unit index, for caret movement: `FP-0118`.
- Word and sentence boundary data: `FP-0055`. Word movement in editing: `FP-0030`, which depends on `FP-0055`.
- `ID_Start`, `ID_Continue`, and the other properties of `DerivedCoreProperties.txt`, and the emoji binary properties of `emoji-data.txt`: `FP-0055`.
- CLDR and script-boundary tailoring: `FP-0026`'s frontier decomposition.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0108/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the executable `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
Run every corpus command with `--env FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`.
Never delete or overwrite a log. Name a failed attempt with the suffix `-attempt-N`, and list it with its cause in the README.

1. Write cases 1 to 16 first. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0108-before`. It must fail with compile errors that name a missing FP-0108 file or declaration.
2. Record `controller-tests-before.log` with `node tools/fairpane.mjs test`. It must exit with status 1 after running every controller case, and exactly cases 1 to 6 must report `not ok`. A module link error is a failed attempt, not a before log.
3. Record `corpus-fetch-unicode.log`, `corpus-applicability-unicode.log`, `corpus-verify-unicode.log`, and `corpus-verify-opentype-fixtures.log`.
4. Record `ucd-generate.log` and `ucd-check.log`.
5. Record `tests-after.log` with `cmd /d /c ver` and then `zig build test --summary all --cache-dir out/fp0108-after`, after deleting that directory. It must exit with status 0 and show the test count.
6. Record `fmt.log` with `zig fmt --check build.zig src tests`. It must exit with status 0.
7. Record `controller-tests-after.log` with `node --version` and then `node tools/fairpane.mjs test`.
8. Record `profile.log` with the test profile procedure of `tools/README.md:352-353`, for `src/root.zig` and for `tests/text/root.zig`, and report the duration of every FP-0108 case.
9. Record `mutation.log` and `mutation-M1.diff` to `mutation-M8.diff`.
10. Write `engineering/evidence/FP-0108/README.md` with `HEAD`, the observed size and SHA-256 of each new member, each control's result, every attempt, and every resolved ambiguity.

The integrator then does the following.

1. Record `HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` for every source root in `raw/integration-binding.log`, before and after the gates.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0108/gates`.
3. Record an uncached `integration-tests.log`.

## Authority

Writable paths: `src`, `tests`, `tools`, `build.zig`, `specs` except `specs/corpora.json`, and `engineering/evidence/FP-0108/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
Network access occurs only in `corpus-fetch unicode`.
The integrator alone updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Required reviewers: `fairpane-review` and `fairpane-spec`. Both check the capability record update and the amended FP-0013 cases as part of this contract.

## Non-goals

- No word, sentence, or line boundaries, and no bidi resolution.
- No legacy grapheme clusters, CLDR or script-boundary tailoring, or random-access boundary query.
- No shaping cluster formation, normalization, or caret API.
- No Unicode property beyond Grapheme_Cluster_Break, Indic_Conjunct_Break, and Extended_Pictographic, and no other property of `DerivedCoreProperties.txt` or `emoji-data.txt`.
- No change to `specs/corpora.json`, a gate, a threshold, or the C ABI.
- No third-party fixture, tool, or code.

## Amendments

1. Worker `FP0108Graphemes` showed that the M7 row overstates case 11's failures, and the README section "Contract discrepancy" records the evidence.
   `GraphemeBreakTest.txt` has 79 test lines that contain U+0903, and at 42 of them UAX #29 gives the same boundaries whether U+0903 is SpacingMark or Other.
   No rule tests SpacingMark or Other on the left of a boundary, while on the right SpacingMark joins after anything but Control, CR, or LF (GB9a), and Other joins only after Prepend (GB9b).
   A line therefore changes exactly when U+0903 follows a code point other than Control, CR, LF, or Prepend; review 1 corrected this sentence's first wording, which omitted Prepend and wrongly exempted lines that begin with U+0903.
   M7 therefore must fail case 11 at line 841 and at every other line whose expected boundaries change when U+0903 is Other instead of SpacingMark.
   The worker's `raw/mutation.log` lists 37 such lines, and the reviewers recompute that set from the rules, independently of the mutation's output.
   Every other part of the M7 row stays as frozen.
