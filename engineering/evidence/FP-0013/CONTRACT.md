# FP-0013 task contract

## Identity

Task ID: `FP-0013`, "Establish multilingual text data and font parsing".
Workstream: `text`.
Base: commit `28e2195`.
Prerequisites: `FP-0003` and `FP-0005`, accepted.
The `fairpane-spec` worker `FP0013Contract` drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-text`.
Authority: `routine-local-engineering`.

### Integrator decisions

- The owner approved Unicode data files and OFL test fonts in the public repository, as `engineering/evidence/FP-0013/owner-answers.log` and `LICENSE-DECISION.md` record.
- `engineering/dependencies.json` declares fontTools 4.66.1 as an import-time tool, so its use below is within policy.
- The Unicode Consortium's announcement of 2026-09-16 establishes that 18.0.0 is released, although the version page still carries a draft banner.
- The `zig-fmt` gate checks `tests` since commit `dcfb0fd`, so new Zig files under `tests/text` are gated.
- The integrator applies the `specs/corpora.json` pins, including any `upstream` change for `opentype-fixtures`, in a separate protected commit after review.
- Each remaining capability obligation names the plan task that owns it.
- The parser's strictness follows the specification and stays subject to review against web compatibility evidence.

## Sources

- Unicode 18.0.0 release page: <https://www.unicode.org/versions/Unicode18.0.0/>.
- Unicode 18.0 announcement, dated 2026-09-16: <https://blog.unicode.org/2026/09/announcing-unicode-standard-version-180.html>.
- Unicode 18.0.0 UCD directory and archive: <https://www.unicode.org/Public/18.0.0/ucd/> and <https://www.unicode.org/Public/18.0.0/ucd/UCD.zip>.
- UAX #44 for Unicode 18.0.0, sections 4.2.10 "@missing Conventions" and the Joining_Type note: <https://www.unicode.org/reports/tr44/tr44-38.html>.
- Unicode License v3: <https://www.unicode.org/license.txt> [S25], and the Unicode Terms of Use [S26].
- ECMAScript conformance clause, which requires the latest Unicode version: <https://tc39.es/ecma262/multipage/conformance.html> [S29].
- OpenType 1.9.1 chapters, each at <https://learn.microsoft.com/en-us/typography/opentype/spec/>: `otff` (table directory, alignment, checksums), `head`, `hhea`, `maxp`, `hmtx`, `loca`, `glyf`, `cmap`, `name`, `os2`, `post`, `cff`, `gdef`, `gsub`, `gpos`, and `chapter2` (layout common table formats).
- Adobe Technical Note #5176, "The Compact Font Format Specification": <https://adobe-type-tools.github.io/font-tech-notes/pdfs/5176.CFF.pdf>.
- SIL Open Font License 1.1: <https://openfontlicense.org/open-font-license-official-text/> [S33].
- Noto Sans 2.015 release: <https://github.com/notofonts/latin-greek-cyrillic/releases/tag/NotoSans-v2.015>.
- Noto Sans Arabic 2.013 release: <https://github.com/notofonts/arabic/releases/tag/NotoSansArabic-v2.013>.
- Noto Sans Devanagari 2.007 release: <https://github.com/notofonts/devanagari/releases/tag/NotoSansDevanagari-v2.007>.
- Noto Sans CJK 2.004 release and tag tree: <https://github.com/notofonts/noto-cjk/releases/tag/Sans2.004> and <https://github.com/notofonts/noto-cjk/tree/Sans2.004>.
- fontTools 4.66.1 release files: <https://pypi.org/pypi/fonttools/4.66.1/json>, and subsetter options: <https://fonttools.readthedocs.io/en/latest/subset/index.html>.
- Repository rules: `specs/README.md`, `specs/IMPORT_REQUIREMENTS.md`, `engineering/decisions/0003-corpus-snapshots.md`, and `docs/RENDERING_AND_TEXT.md`.

## Behavior

### Unicode version

The import uses Unicode 18.0.0.
`specs/IMPORT_REQUIREMENTS.md` requires the latest released version at import time, and ECMAScript requires the latest version. [S29]
The Unicode Consortium announced version 18.0 as available on 2026-09-16.
The numbered directory `https://www.unicode.org/Public/18.0.0/` holds the data.
Every imported UCD file states its version on line 1, for example `# ScriptExtensions-18.0.0.txt`.
The import never reads `Public/latest/`, `Public/draft/`, or `Public/UNIDATA/`.

### Unicode files imported now

The import fetches `UCD.zip` from the 18.0.0 directory and extracts exactly these members without edits.

| Member | Destination | Property | Consumer in this task |
| --- | --- | --- | --- |
| `Scripts.txt` | `src/unicode/ucd/Scripts.txt` | `Script` (`sc`) | Seed cases 10 and 11, and the exhaustive check in case 3 |
| `ScriptExtensions.txt` | `src/unicode/ucd/ScriptExtensions.txt` | `Script_Extensions` (`scx`) | Same |
| `PropertyValueAliases.txt` | `src/unicode/ucd/PropertyValueAliases.txt` | Value aliases for all six enumerated properties | Generated enums, alias case 5, and seed parsing |
| `extracted/DerivedBidiClass.txt` | `src/unicode/ucd/extracted/DerivedBidiClass.txt` | `Bidi_Class` (`bc`) | Seeds, mixed-direction seed, and default case 6 |
| `extracted/DerivedJoiningType.txt` | `src/unicode/ucd/extracted/DerivedJoiningType.txt` | `Joining_Type` (`jt`) | Arabic seed |
| `extracted/DerivedGeneralCategory.txt` | `src/unicode/ucd/extracted/DerivedGeneralCategory.txt` | `General_Category` (`gc`) | All seeds and default case 6 |
| `IndicSyllabicCategory.txt` | `src/unicode/ucd/IndicSyllabicCategory.txt` | `Indic_Syllabic_Category` (`InSC`) | Devanagari seed |
| `IndicPositionalCategory.txt` | `src/unicode/ucd/IndicPositionalCategory.txt` | `Indic_Positional_Category` (`InPC`) | Devanagari seed |

`https://www.unicode.org/license.txt` goes to `src/unicode/ucd/license.txt`.
The import takes `Joining_Type` from `DerivedJoiningType.txt` rather than `ArabicShaping.txt`, because UAX #44 calls that listing definitive.
It takes `General_Category` from `DerivedGeneralCategory.txt`, because that file lists every range explicitly, including `Cn`, and it needs no `First`/`Last` pair parsing.
`src/unicode/ucd/.gitattributes` contains `* -text`, so Git never converts these bytes.
The files live under `src` because a Zig `@embedFile` cannot read outside the module root, and the reference test in case 3 embeds them.

Every other file in the `specs/IMPORT_REQUIREMENTS.md` table remains a later import.
The capability record names that obligation.
`specs/IMPORT_REQUIREMENTS.md` gains a `DerivedGeneralCategory.txt` row with the consumers above.

### Unicode property module

`tools/ucd.mjs` follows the `tools/abi.mjs` pattern.
`node tools/fairpane.mjs ucd-generate` reads the eight files and writes `src/unicode/tables.zig`.
`node tools/fairpane.mjs ucd-check` regenerates in memory, compares byte for byte, and exits with status 1 naming the first differing line.
The parser applies each `@missing` line in order, so each later line overrides earlier defaults for its range, as UAX #44 section 4.2.10 states.
A `Script_Extensions` code point that the file does not list takes its `Script` value, as the `ScriptExtensions.txt` header states.
The parser resolves every value, including `@missing` long names such as `Left_To_Right`, through `PropertyValueAliases.txt`.
An unknown value, a range with start after end, a code point above `10FFFF`, or a data line without `;` fails generation with the file and line number.

The generated file begins with `//! Generated by tools/ucd.mjs from Unicode 18.0.0. Do not edit.`.
Its header lists each input path, byte size, and SHA-256.
Its header reproduces `src/unicode/ucd/license.txt` as `//` comment lines, which carries the Unicode copyright and permission notice. [S25]
The output passes `zig fmt --check`.

`src/unicode/properties.zig` is the public module, exported from `src/root.zig` as `unicode`.

- `pub const version = "18.0.0";`
- `GeneralCategory`, `Script`, `BidiClass`, `JoiningType`, `IndicSyllabicCategory`, and `IndicPositionalCategory` are generated enums.
  Their tags are the short aliases, the second field of `PropertyValueAliases.txt`, in file order.
  `GeneralCategory` has only the 30 values that occur in `DerivedGeneralCategory.txt`.
- Each enum has `pub fn fromAlias(name: []const u8) ?Self`, an exact match against any alias field of that property.
  Group aliases of `gc`, such as `L` and `Letter`, return `null`.
- `pub const Properties = struct { gc: GeneralCategory, sc: Script, scx: []const Script, bc: BidiClass, jt: JoiningType, insc: IndicSyllabicCategory, inpc: IndicPositionalCategory };`
- `pub fn lookup(code_point: u21) error{NotCodePoint}!Properties` returns `error.NotCodePoint` above `0x10FFFF`.
  `scx` lists values in ascending enum order.

Lookups allocate nothing.
`src/unicode/reference_test.zig` is a test-only, independent Zig parser of the embedded files.
It is the generic reference path for the generated tables.

### Font fixtures

| Fixture directory under `tests/text/fonts/` | Upstream | Release | Upstream artifact and member | Published identity | License |
| --- | --- | --- | --- | --- | --- |
| `noto-sans/` with `NotoSans-Regular.ttf` and `OFL.txt` | `notofonts/latin-greek-cyrillic` | `NotoSans-v2.015`, commit `c4a321e123e4d4ff315f57f4e0adf294fe3a95be` | `https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v2.015/NotoSans-v2.015.zip`, 117491253 bytes; members `NotoSans/unhinted/ttf/NotoSans-Regular.ttf` and `OFL.txt` | No published digest | OFL 1.1, "Copyright 2022 The Noto Project Authors", no Reserved Font Name |
| `noto-sans-arabic/` with `NotoSansArabic-Regular.ttf` and `OFL.txt` | `notofonts/arabic` | `NotoSansArabic-v2.013`, commit `1b2b7e5c6ce3ab4d50681c854892325530084c35` | `https://github.com/notofonts/arabic/releases/download/NotoSansArabic-v2.013/NotoSansArabic-v2.013.zip`, 18777381 bytes; members `NotoSansArabic/unhinted/ttf/NotoSansArabic-Regular.ttf` and `OFL.txt` | GitHub digest `sha256:1301aceaea84c501cf2e6dcfb3182e2328c8eae5725817fcb239672bda7154f1` | Same terms |
| `noto-sans-devanagari/` with `NotoSansDevanagari-Regular.ttf` and `OFL.txt` | `notofonts/devanagari` | `NotoSansDevanagari-v2.007`, commit `e123d230c160ebe949d731cc19017cdb354180d1` | `https://github.com/notofonts/devanagari/releases/download/NotoSansDevanagari-v2.007/NotoSansDevanagari-v2.007.zip`, 18449254 bytes; members `NotoSansDevanagari/unhinted/ttf/NotoSansDevanagari-Regular.ttf` and `OFL.txt` | GitHub digest `sha256:820c7da45b1e63562cb41c0a8cac5d9a4202312043a3a040ed1325857ef469b1` | Same terms |
| `noto-sans-cjk-jp-subset/` with `cjk-subset.otf` and `LICENSE` | `notofonts/noto-cjk` | Tag `Sans2.004`, commit from `git ls-remote` | `https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf`, 16467736 bytes, and `https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/LICENSE`, 4301 bytes | Git blob IDs `f56224957fb13a81b4c14bac34f2f058a017f9fb` and `d952d62c065f3f35fb83a173496e90b21525aef3` | OFL 1.1; the copyright notice is name ID 0; Reserved Font Name `Source` is treated as applying |

Each fixture passes the admission rule of `specs/IMPORT_REQUIREMENTS.md`.

1. Each license text names its font software and permits redistribution bundled with software. [S33]
2. The snapshot record carries the per-file provenance fields listed in that file.
3. No fixture comes from a Unicode product. [S26]
4. Each fixture directory carries its license text beside the font, and each OFL fixture keeps its own OFL text under condition 5. [S33]

The three Noto Sans fonts are small, unmodified, unhinted static TrueType files of about 142 KB, 183 KB, and 431 KB.
The CJK source is 16 MB, so the repository stores a recorded subset, and the full source stays in the local snapshot.
`tests/text/fonts/.gitattributes` contains `* -text`.

### CJK subset

The subset is an OFL "Modified Version", because it deletes components of the original. [S33]
It is distributed under the OFL only, with the upstream `LICENSE` beside it. [S33]
The OFL defines a Reserved Font Name as a name stated after a copyright statement. [S33]
The Noto CJK `LICENSE` at `Sans2.004` has no copyright line, and the font's name ID 0 carries the copyright statement.
The import records name ID 0 of the source font verbatim, and it records `Source` as a Reserved Font Name when that text names it.
The subset keeps only name IDs 0, 7, 13, and 14, so it carries no family, subfamily, full, unique, PostScript, typographic, or WWS name.
The CFF Name INDEX keeps its PostScript name, which does not contain `Source`.
The file name `cjk-subset.otf` uses no upstream font name.

The tool is fontTools 4.66.1, wheel `fonttools-4.66.1-py3-none-any.whl` from `https://files.pythonhosted.org/packages/f6/10/d45b74135d5d642cb3a4fb0a957c1613ef93de4c8548671dfc3a5bf38299/fonttools-4.66.1-py3-none-any.whl`, SHA-256 `7234ae9e28db64273fbbfa72caebd0a97e3bdba6b05064114741b9539ef339d0`.
It runs in `.tools/python/fonttools-4.66.1/`, installed with `--no-index --no-deps` from the verified wheel.
The frozen argument vector after the interpreter is:

```text
-m fontTools.subset <corpora-root>/opentype-fixtures/sources/noto-cjk/NotoSansCJKjp-Regular.otf --unicodes=U+0020,U+3001,U+3002,U+3053,U+3055,U+3061,U+306A,U+306B,U+306E,U+306F,U+307F,U+3093,U+30AB,U+30FC,U+4E16,U+754C,U+AD6D,U+C5B4,U+D55C,U+20BB7 --layout-features=* --name-IDs=0,7,13,14 --notdef-outline --output-file=<output>
```

Every other option keeps its default, so the timestamp stays unchanged.
The code points are exactly the distinct code points of the `cjk-greeting` seed.
Two runs to two output files must produce identical SHA-256 values.
The record keeps the tool, wheel digest, Python version, argument vector, input digest, and output size and digest.

### File-set snapshot records

`tools/corpus.mjs` gains the corpus kind `file-set` for `unicode` and `opentype-fixtures`.
The Git rules for `wpt` and `test262` stay unchanged.
The procedure follows `specs/README.md`: exact version, URL and license, fetch through `corpus-fetch`, complete inventory hash, unedited bytes, separate applicability, and an explicit denominator.

`specs/snapshots/<id>.json` for a file-set corpus has these fields.

| Field | Content |
| --- | --- |
| `schema_version`, `corpus`, `kind` | `1`, the corpus ID, and `"file-set"` |
| `upstream` | The `specs/corpora.json` upstream, unchanged |
| `version` | `"18.0.0"` for `unicode`, `"fixtures-1"` for `opentype-fixtures` |
| `retrieved_at` | UTC time when the last download completed |
| `sources[]` | `id`, `url`, `kind` (`zip` or `file`), `release`, `size`, `sha256`, `published_digest` or `null`, `git_blob` or `null`, `local_path` under `<corpora-root>`, and for `zip` an `inventory` with `entry_count`, `total_bytes`, and `sha256` |
| `selected[]` | `source`, `member`, `path`, `size`, `sha256`, `role` (`data`, `font`, or `license`), and `published_url` or `null`; a `font` entry also has `license_path`, `license_name`, `copyright`, and `reserved_font_names` |
| `derived[]` | `path`, `size`, `sha256`, `input` (`source`, `sha256`), `tool` (`name`, `version`, `wheel_url`, `wheel_sha256`, `python`), `argv`, `license_path`, `copyright`, `reserved_font_names`, and `rfn_resolution` |

A zip inventory line is `<sha256>\t<size>\t<path>\n` for each file member, sorted by the UTF-8 bytes of the path, and the inventory SHA-256 hashes the concatenation.
Directory members are excluded.
The zip reader accepts only stored and deflate members, and it rejects ZIP64, encryption, absolute paths, `..` segments, backslashes, and duplicate paths.
Extraction writes only under `src/unicode/ucd/` and `tests/text/fonts/`.

`corpus-fetch <id>` downloads each source.
A non-null pin in the record must match.
A published GitHub digest must match.
A `git_blob` must equal the Git blob ID of the bytes.
A `published_url` must serve bytes equal to the extracted member.
The command writes the record only after every check passes, and a failure leaves the existing sources, record, and extracted files unchanged.
`corpus-repin <id>` exits with status 1 for a file-set corpus, because version selection is a contract decision.
`corpus-verify <id>` rehashes local sources, inventories, every `selected`, `derived`, and license path, and the applicability record.
It exits with status 1 on any difference.

`specs/applicability/<id>.json` uses the FP-0003 fields.
It names `version` and the inventory digests in place of `commit`.
For `unicode`, discovered is the number of file members of `UCD.zip`, with a `breakdown` by first path component (`.`, `auxiliary`, `emoji`, `extracted`), selected is 8, excluded is empty, and the rest are unclassified later imports.
For `opentype-fixtures`, discovered counts members ending in `.ttf` or `.otf` (case-insensitive) in each zip source plus each font `file` source, with a `breakdown` by source ID, and selected is 4.

`specs/corpora.json` stays unchanged.
The worker writes the proposed pin values in `engineering/evidence/FP-0013/README.md`.
The integrator applies them in a separate protected commit after review.

### OpenType parser

`src/font/opentype.zig` is the public module, exported from `src/root.zig` as `font`.
`src/font/reader.zig`, `src/font/tables.zig`, `src/font/cmap.zig`, `src/font/cff.zig`, and `src/font/layout.zig` hold its parts.

```zig
pub fn parse(bytes: []const u8, options: ParseOptions) ParseError!Font
pub const ParseOptions = struct { checksums: enum { report, reject } = .report };
```

`parse` takes no allocator and allocates nothing.
`Font` borrows `bytes`, which the caller keeps alive.
Every read goes through a checked big-endian reader, and offset sums use 64-bit arithmetic.
No loop runs more often than a count read from the input, and every count is checked against the remaining bytes before the loop starts.
No function recurses, so stack use is constant.
Parse time is linear in the input length.

`ParseError` has exactly these members: `Truncated`, `UnknownSfntVersion`, `UnsupportedSfntVersion`, `UnsupportedCollection`, `UnsupportedWoff`, `UnsupportedWoff2`, `DuplicateTable`, `UnsortedTableDirectory`, `MisalignedTable`, `TableOutOfBounds`, `OverlappingTables`, `MissingRequiredTable`, `OutlineFormatMismatch`, `UnsupportedCff2`, `ChecksumMismatch`, `InvalidHead`, `InvalidMaxp`, `InvalidHhea`, `InvalidHmtx`, `InvalidLoca`, `InvalidCmap`, `NoUnicodeCmap`, and `InvalidCff`.

#### Table directory (`otff`)

- Fewer than 12 bytes, or a record array past the end of input, returns `Truncated`.
- `sfntVersion` `0x00010000` selects TrueType outlines, and `OTTO` selects CFF outlines.
  `ttcf` returns `UnsupportedCollection`, `wOFF` returns `UnsupportedWoff`, `wOF2` returns `UnsupportedWoff2`, `true` and `typ1` return `UnsupportedSfntVersion`, and any other value returns `UnknownSfntVersion`.
- The parser ignores `searchRange`, `entrySelector`, and `rangeShift` and derives search from `numTables`, as the specification recommends.
- Tags must strictly ascend.
  An equal adjacent tag returns `DuplicateTable`, and a smaller one returns `UnsortedTableDirectory`.
- Every record, including unknown tags, needs `offset + length <= bytes.len` (`TableOutOfBounds`) and `offset % 4 == 0` (`MisalignedTable`).
- The known tags are `CFF `, `CFF2`, `GDEF`, `GPOS`, `GSUB`, `OS/2`, `cmap`, `glyf`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name`, and `post`.
  Two nonempty known tables whose ranges intersect return `OverlappingTables`.
  Overlap with an unknown table is accepted, because the specification says only "should" and the parser never reads unknown tables.
- `cmap`, `head`, `hhea`, `hmtx`, and `maxp` are required.
  TrueType fonts need `glyf` and `loca`.
  CFF fonts need `CFF `.
  A missing table returns `MissingRequiredTable`.
  A TrueType font with `CFF ` or `CFF2`, or a CFF font with `glyf` or `loca`, returns `OutlineFormatMismatch`.
  A CFF font with `CFF2` returns `UnsupportedCff2`.
- The checksum of each table is the wrapping uint32 sum over its bytes, zero-padded to a multiple of four.
  For `head`, the sum treats `checksumAdjustment` as zero.
  The whole-file sum, zero-padded, must equal `0xB1B0AFBA`.
  Under `.report`, `Font.integrity()` lists each mismatched known tag, counts mismatched unknown tags, and sets `head_adjustment_ok`.
  Under `.reject`, any mismatch returns `ChecksumMismatch`.

#### Required tables

| Table | Checked rules | Error |
| --- | --- | --- |
| `head` | Length at least 54; `majorVersion` 1; `magicNumber` `0x5F0F3CF5`; `unitsPerEm` 16 to 16384; for TrueType, `indexToLocFormat` 0 or 1 | `InvalidHead` |
| `maxp` | TrueType needs version `0x00010000` and 32 bytes; CFF needs `0x00005000` and 6 bytes; `numGlyphs` at least 1 | `InvalidMaxp` |
| `hhea` | Length at least 36; `majorVersion` 1; `numberOfHMetrics` from 1 to `numGlyphs` | `InvalidHhea` |
| `hmtx` | Length at least `4 * numberOfHMetrics + 2 * (numGlyphs - numberOfHMetrics)` | `InvalidHmtx` |
| `loca` | `numGlyphs + 1` entries fit; short entries are doubled; offsets never decrease; the last offset is at most the `glyf` length | `InvalidLoca` |
| `cmap` | Described below | `InvalidCmap`, `NoUnicodeCmap` |
| `CFF ` | Described below | `InvalidCff` |

`glyf` headers are checked on access.
`glyphHeader(glyph)` returns `GlyphOutOfRange` at or past `numGlyphs`, `NotTrueType` for a CFF font, and `null` for zero length.
It returns `InvalidGlyph` for a length from 1 to 9, decreasing `endPtsOfContours`, or an `instructionLength` past the glyph.
Outline points, flags, and composite components are not decoded.

`cmap` needs version 0, encoding records inside the table, and records sorted by platform ID, encoding ID, and language, with no repeated combination.
Every subtable offset and its format's length field must fall inside the table.
Every format 4 and format 12 subtable is validated fully, whether or not it is selected.
Format 4 needs a nonzero even `segCountX2`, the four arrays inside the subtable, strictly ascending `endCode` with last value `0xFFFF`, `startCode <= endCode`, no overlap with the previous segment, `glyphIdArray` reads inside the subtable, and every mapped glyph below `numGlyphs`.
Format 12 needs `16 + 12 * numGroups` bytes, checked before any group is read.
Its groups need `startCharCode <= endCharCode <= 0x10FFFF`, strictly ascending and nonoverlapping order, and `startGlyphID + (endCharCode - startCharCode) < numGlyphs`.
Formats 0, 2, 6, 8, 10, 13, and 14 get only the header and length check.
Selection order is (3, 10) format 12, (0, 4) format 12, (3, 1) format 4, then (0, 3) format 4.
No candidate returns `NoUnicodeCmap`.
`glyphIndex(code_point: u21) u16` returns 0 for unmapped values and for values above `0x10FFFF`.

`CFF ` needs major version 1, `hdrSize` from 4 to the table length, and an `offSize` field from 1 to 4.
Four INDEXes follow: Name, Top DICT, String, and Global Subr.
Each INDEX has a `count`, and a nonzero count has `offSize` from 1 to 4, a first offset of 1, nondecreasing offsets, and data inside the table.
Name and Top DICT counts must be 1. [`cff`]
The Top DICT is parsed with at most 48 operands per operator, and reserved bytes 22 to 27, 31, and 255 are rejected.
A real operand must end with a nibble `0xF` inside the DICT. [TN5176]
`CharStrings` (17) is required, `CharstringType` (12 6) must be 2 when present, and the CharStrings INDEX count must equal `numGlyphs`. [`cff`]
`Font.cff()` returns the name, CharStrings count, and whether `ROS` (12 30) appears.

#### Optional tables

`name`, `OS/2`, `post`, `GDEF`, `GSUB`, and `GPOS` never reject the font, because none of them affects glyph mapping or advances.
Each accessor returns `TableStatus(T) = union(enum) { absent, rejected: Defect, unsupported_version: u32, valid: T }`.
`Defect` has exactly these values: `too_short`, `offset_out_of_bounds`, `count_out_of_bounds`, `unsorted_records`, `glyph_count_mismatch`, `invalid_string_index`, and `odd_utf16_length`.

- `name`: format 0 or 1, and any other format is `unsupported_version`.
  Records and language-tag records must fit (`count_out_of_bounds`).
  `storageOffset` and every string range must fit (`offset_out_of_bounds`).
  Records must be sorted by platform, encoding, language, and name ID (`unsorted_records`).
  A platform 0 or 3 string must have an even length (`odd_utf16_length`).
  `Name` offers `count`, `record(i)`, and `find(platform, encoding, language, name_id)`, each returning raw string bytes.
- `OS/2`: versions 0 to 5, and any other version is `unsupported_version`.
  The minimum lengths are 68 for version 0, 86 for version 1, 96 for versions 2 to 4, and 100 for version 5 (`too_short`).
  A version 0 table shorter than 78 bytes reports `typo = null`, because legacy tables end at `usLastCharIndex`.
- `post`: a 32-byte header.
  Versions 1.0, 2.0, and 3.0 are supported, and 2.5 and any other version are `unsupported_version`.
  Version 2.0 needs `numGlyphs` equal to `maxp` (`glyph_count_mismatch`), a fitting `glyphNameIndex` array, and every index of 258 or more naming an existing Pascal string inside the table (`invalid_string_index`).
- `GSUB` and `GPOS`: versions 1.0 (10-byte header) and 1.1 (14-byte header), and any other version is `unsupported_version`.
  Nonnull ScriptList, FeatureList, LookupList, and FeatureVariations offsets must fall inside the table.
  The record arrays must fit, every Script, Feature, and Lookup offset must fall inside the table, and script tags must ascend (`unsorted_records`). [`chapter2`]
  `Layout` offers script count and tags, feature count and tags in FeatureList order, and lookup count.
- `GDEF`: versions 1.0 (12 bytes), 1.2 (14), and 1.3 (18), and any other version is `unsupported_version`.
  Every nonnull offset must fall inside the table.

Every parsed value is exposed through `Font`: `outline`, `tableCount`, `tableRecord(i)`, `findTable(tag)`, `integrity`, `head`, `hhea`, `glyphCount`, `advance(glyph)`, `cmapSubtableCount`, `cmapSubtable(i)`, `unicodeCmap`, `glyphIndex`, `glyphHeader`, `name`, `os2`, `post`, `gdef`, `gsub`, `gpos`, and `cff`.

### Malformed-fixture generator

`tests/text/sfnt_builder.zig` is a first-party, deterministic, in-memory sfnt writer.
It writes the directory and computes checksums and `checksumAdjustment`.
It places tables in directory order, padded with zeros to four bytes, and it applies named overrides.
`B_TT` is TrueType with tables `GDEF`, `GPOS`, `GSUB`, `OS/2`, `cmap`, `glyf`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name`, and `post`.
It has 4 glyphs: glyph 0 is a one-contour box (50, 0, 450, 700), glyph 1 is empty, glyph 2 has one contour (10, 0, 590, 700), and glyph 3 is a composite of glyph 2.
Its `cmap` records are (0, 3) and (3, 1) sharing a format 4 subtable that maps U+0020 to 1 and U+0041 to 2, plus (3, 10) format 12 that maps U+0020 to 1, U+0041 to 2, and U+1F600 to 3.
Its `head` has `unitsPerEm` 1000, bounding box (10, 0, 590, 700), and short `loca`.
Its `hhea` has ascender 800, descender -200, line gap 0, `advanceWidthMax` 600, and `numberOfHMetrics` 3.
Its `hmtx` holds (500, 50), (250, 0), (600, 10), and the trailing lsb 10.
Its `maxp` is version 1.0.
Its `name` is format 0 with (3, 1, 0x409, 1) "FP Min" and (3, 1, 0x409, 2) "Regular".
Its `OS/2` is version 4 with weight 400, typo metrics 800, -200, and 0, and win metrics 800 and 200.
Its `post` is version 3.0 with underline -100 and 50.
Its `GSUB` has scripts `DFLT` and `latn`, no features, and no lookups.
Its `GPOS` has script `latn` only.
Its `GDEF` is version 1.0 with all-null offsets.
`B_CFF` is `OTTO` with `CFF `, `OS/2`, `cmap`, `head`, `hhea`, `hmtx`, `maxp` 0.5, `name`, and `post` 3.0, and 2 glyphs.
Its `cmap` is (3, 1) format 4 mapping U+0041 to 1.
Its `hmtx` holds (500, 0) and (600, 0).
Its CFF is header `01 00 04 01`, Name INDEX [`FPMinCFF`], a Top DICT with a 5-byte CharStrings operand, an empty String INDEX, an empty Global Subr INDEX, and a CharStrings INDEX of two `0E` charstrings.
Both fonts end with their 32-byte `post` table, so every proper prefix cuts a table.

### Font expectation files

`tools/fonts/font_expectations.py` writes `<font>.expect.json` beside each real fixture, using only fontTools 4.66.1.
The format is `"fairpane-font-expectation"`, version 1.
Its fields are `font`, `font_sha256`, `generator` (script path, script SHA-256, fontTools and Python versions), and `sfnt_version`.
`tables` lists the directory in order with tag, checksum, offset, and length.
The raw-field objects are `head`, `hhea`, `maxp`, `os2` or `null`, and `post` or `null`; Fixed values are integers scaled by 65536.
`name` lists every record in table order with platform, encoding, language, name ID, and hex bytes.
`cmap` lists the subtables, the subtable that the precedence above selects, and the glyph for every code point of all six seeds.
`hmtx` gives advance and lsb for glyph 0 and every mapped glyph, and `glyf` gives their headers or `null`.
`gdef`, `gsub`, and `gpos` give the version, the script and feature tags, and the lookup count.
`cff` gives the Name INDEX names, the CharStrings count, and `cid_keyed`.
No expectation file is edited by hand.

### Qualification seeds

Each seed is `tests/text/seeds/<id>.json` with `"format": "fairpane-text-seed"`, `"version": 1`, `id`, `unicode_version` `"18.0.0"`, `text_utf8`, `code_points`, `properties`, and `coverage`.
The format accepts no other field.
A code point string is `U+` followed by 4 to 6 uppercase hex digits without extra leading zeros.
`properties` has exactly one entry for each distinct code point, with keys `gc`, `sc`, `scx`, `bc`, `jt`, `InSC`, and `InPC` in short aliases.
`coverage` maps a fixture directory name to `covered` and `uncovered` lists.

| Seed | Text | Code points |
| --- | --- | --- |
| `latin-baseline` | `Café café`, precomposed then decomposed | 0043 0061 0066 00E9 0020 0063 0061 0066 0065 0301 |
| `arabic-greeting` | `مرحبًا، بالعالم ١٢٣` | 0645 0631 062D 0628 064B 0627 060C 0020 0628 0627 0644 0639 0627 0644 0645 0020 0661 0662 0663 |
| `devanagari-greeting` | `नमस्ते दुनिया। हिंदी` | 0928 092E 0938 094D 0924 0947 0020 0926 0941 0928 093F 092F 093E 0964 0020 0939 093F 0902 0926 0940 |
| `cjk-greeting` | `世界のみなさん、こんにちは。カー 한국어 𠮷` | 4E16 754C 306E 307F 306A 3055 3093 3001 3053 3093 306B 3061 306F 3002 30AB 30FC 0020 D55C AD6D C5B4 0020 20BB7 |
| `mixed-direction` | Arabic, then `\u2068Fairpane 123\u2069` | 0645 0631 062D 0628 0627 0020 0628 0627 0644 0639 0627 0644 0645 0020 2068 0046 0061 0069 0072 0070 0061 006E 0065 0020 0031 0032 0033 2069 |
| `uncovered-emoji` | Woman, skin tone 4, laptop, without ZWJ | 1F469 1F3FD 1F4BB |

The expected values below were read from the 18.0.0 files.

| Code points | gc | sc | scx | bc | jt | InSC | InPC |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0020 | Zs | Zyyy | Zyyy | WS | U | Other | NA |
| 0031 0032 0033 | Nd | Zyyy | Zyyy | EN | U | Number | NA |
| 0043 0046 | Lu | Latn | Latn | L | U | Other | NA |
| 0061 0063 0065 0066 0069 006E 0070 0072 00E9 | Ll | Latn | Latn | L | U | Other | NA |
| 0301 | Mn | Zinh | Cher Cyrl Grek Latn Osge Sunu Tale Todr | NSM | T | Other | NA |
| 060C | Po | Zyyy | Arab Gara Nkoo Rohg Syrc Thaa Yezi | CS | U | Other | NA |
| 0627 0631 | Lo | Arab | Arab | AL | R | Other | NA |
| 0628 062D 0639 0644 0645 | Lo | Arab | Arab | AL | D | Other | NA |
| 064B | Mn | Zinh | Arab Syrc | NSM | T | Other | NA |
| 0661 0662 0663 | Nd | Arab | Arab Thaa Yezi | AN | U | Other | NA |
| 0902 | Mn | Deva | Deva | NSM | T | Bindu | Top |
| 0924 0926 0928 092E 092F 0938 0939 | Lo | Deva | Deva | L | U | Consonant | NA |
| 093E 0940 | Mc | Deva | Deva | L | U | Vowel_Dependent | Right |
| 093F | Mc | Deva | Deva | L | U | Vowel_Dependent | Left |
| 0941 | Mn | Deva | Deva | NSM | T | Vowel_Dependent | Bottom |
| 0947 | Mn | Deva | Deva | NSM | T | Vowel_Dependent | Top |
| 094D | Mn | Deva | Deva | NSM | T | Virama | Bottom |
| 0964 | Po | Zyyy | Beng Deva Dogr Gong Gonm Gran Gujr Guru Knda Mahj Mlym Nand Onao Orya Sind Sinh Sylo Takr Taml Telu Tirh | L | U | Other | NA |
| 2068 | Cf | Zyyy | Zyyy | FSI | U | Other | NA |
| 2069 | Cf | Zyyy | Zyyy | PDI | U | Other | NA |
| 3001 | Po | Zyyy | Bopo Hang Hani Hira Kana Mong Yiii | ON | U | Other | NA |
| 3002 | Po | Zyyy | Bopo Hang Hani Hira Kana Mong Phag Yiii | ON | U | Other | NA |
| 3053 3055 3061 306A 306B 306E 306F 307F 3093 | Lo | Hira | Hira | L | U | Other | NA |
| 30AB | Lo | Kana | Kana | L | U | Other | NA |
| 30FC | Lm | Zyyy | Hira Kana | L | U | Other | NA |
| 4E16 754C 20BB7 | Lo | Hani | Hani | L | U | Other | NA |
| AD6D C5B4 D55C | Lo | Hang | Hang | L | U | Other | NA |
| 1F3FD | Sk | Zyyy | Zyyy | ON | U | Other | NA |
| 1F469 1F4BB | So | Zyyy | Zyyy | ON | U | Other | NA |

| Seed | Covered (glyph not 0) | Uncovered (glyph 0) |
| --- | --- | --- |
| `latin-baseline` | `noto-sans`: all 8 distinct | None |
| `arabic-greeting` | `noto-sans-arabic`: all 13 distinct | `noto-sans`: 0627 0628 062D 0631 0639 0644 0645 064B |
| `devanagari-greeting` | `noto-sans-devanagari`: all 16 distinct | `noto-sans`: 0902 0924 0926 0928 092E 092F 0938 0939 093E 093F 0940 0941 0947 094D |
| `cjk-greeting` | `noto-sans-cjk-jp-subset`: all 20 distinct | `noto-sans`: 3053 3055 3061 306A 306B 306E 306F 307F 3093 30AB 4E16 754C AD6D C5B4 D55C 20BB7 |
| `mixed-direction` | `noto-sans-arabic`: 0020 0627 0628 062D 0631 0639 0644 0645; `noto-sans`: 0020 0031 0032 0033 0046 0061 0065 0069 006E 0070 0072 | None; 2068 and 2069 stay unasserted |
| `uncovered-emoji` | None | All four fixtures: 1F469 1F3FD 1F4BB |

### Capability record

`specs/capabilities/text-fonts.json` has `schema_version` 1, `family` `"text-fonts"`, `unicode_version` `"18.0.0"`, and `obligations`.
Each obligation has `id`, `status` (`implemented` or `remaining`), `owner_task` (a plan task ID, never `null`), `summary`, and `engine_behavior`.
The `engine_behavior` field states what the engine does now, such as an exact error or "no API".
The frozen set is exactly the following.

| ID | Status | Owner task |
| --- | --- | --- |
| `unicode-properties` | implemented | `FP-0013` |
| `opentype-core-tables` | implemented | `FP-0013` |
| `unicode-remaining-data` | remaining | `FP-0055` |
| `bidi-algorithm` | remaining | `FP-0015` |
| `grapheme-segmentation` | remaining | `FP-0015` |
| `line-breaking` | remaining | `FP-0015` |
| `shaping` | remaining | `FP-0015` |
| `font-fallback` | remaining | `FP-0015` |
| `glyph-rasterization` | remaining | `FP-0056` |
| `truetype-hinting` | remaining | `FP-0057` |
| `woff` | remaining | `FP-0058` |
| `woff2-brotli` | remaining | `FP-0058` |
| `font-collections` | remaining | `FP-0059` |
| `cff2-and-variations` | remaining | `FP-0059` |
| `color-fonts` | remaining | `FP-0060` |
| `vertical-metrics` | remaining | `FP-0061` |
| `cmap-variation-and-legacy-formats` | remaining | `FP-0061` |
| `layout-auxiliary-tables` | remaining | `FP-0062` |
| `platform-font-discovery` | remaining | `FP-0063` |

`glyph-rasterization` covers `glyf` outline and composite decoding, CFF Type 2 charstrings, and scan conversion.
`shaping` covers GSUB and GPOS lookups, Arabic joining, and Indic and USE reordering.
`font-fallback` covers per-code-point font selection, including the `uncovered-emoji` seed.

### Stop rules

Some expected values are inferences about upstream content: zip member paths, coverage claims, U+20BB7 being in the CJK source, and valid release checksums.
If any such value fails, stop and report the observed value to the integrator.
Never edit an expectation, a seed, or an upstream byte to pass a case.

### Documentation

Update `specs/README.md` with the file-set kind and the capability record.
Update `specs/IMPORT_REQUIREMENTS.md` with the import status and the `DerivedGeneralCategory.txt` row.
Update `tools/README.md` with `ucd-generate`, `ucd-check`, and the file-set commands.
Add `tests/text/README.md` describing the fixtures, seeds, expectation files, and stop rules.
Add `specs/sources.json` entries for each source above that has no identifier.

## Exact test cases

Zig cases are named `FP-0013 case N: ...` and run through `zig build test`.
`build.zig` adds a test artifact rooted at `tests/text/root.zig` that imports the library module as `fairpane`.
Controller cases are named the same way and run through `node tools/fairpane.mjs test`.

### Unicode data

1. `tools/ucd.test.mjs`: a frozen input with `# @missing: 0000..10FFFF; Left_To_Right`, then `# @missing: 0590..05FF; Right_To_Left`, a range line, a single line, a trailing comment, and a blank line yields the exact value of 8 probe code points.
   The probes include one inside each `@missing` range and one in each listed line.
2. `tools/ucd.test.mjs`: a line without `;`, a reversed range, `110000`, and an unknown value each fail with a distinct message naming the line number.
3. `tools/ucd.test.mjs`: `ucd-check` exits with status 0 on the committed files.
   Line 1 of each file names `-18.0.0.txt`.
   `src/unicode/reference_test.zig` independently parses the embedded files and finds `lookup` equal for every code point from 0 to `0x10FFFF` and all seven properties.
4. `tools/ucd.test.mjs`: changing one byte of `src/unicode/tables.zig` in a controller copy makes `ucd-check` exit with status 1 and name the file and line.
   Changing one UCD byte does the same through the header digest.
5. Zig: every short and long alias of `gc`, `sc`, `bc`, `jt`, `InSC`, and `InPC` in `PropertyValueAliases.txt` resolves to one value through `fromAlias`.
   `Qaai` returns `Zinh`, `Qaac` returns `Copt`, `L` and `Letter` return `null`, and `Nope` returns `null`.
6. Zig, hard-coded: U+0378 gives Cn, Zzzz, {Zzzz}, L; U+05EB gives Cn, Zzzz, {Zzzz}, R; U+070E gives Cn, Zzzz, {Zzzz}, AL; U+20C5 gives Cn, Zzzz, {Zzzz}, ET; U+D800 gives Cs, Zzzz, {Zzzz}, L; U+E000 gives Co, Zzzz, {Zzzz}, L; and U+FDD0 gives Cn, Zzzz, {Zzzz}, BN.
   Each has `jt` U, `InSC` Other, and `InPC` NA.
7. Zig: `lookup(0x110000)` returns `error.NotCodePoint`, and `unicode.version` equals `"18.0.0"`.
8. Zig in `src/web_string.zig`: `View.codePoints()` over 0041, D800, D83D, DE00, DC00 yields 0x41, 0xD800, 0x1F600, and 0xDC00.

### Seeds

9. A seed with an unknown field, a missing field, a noncanonical code point string, a missing property entry, or an extra entry fails with a distinct error.
   Each committed seed's `text_utf8`, decoded with `WebString.fromUtf8` and iterated with `codePoints`, equals its `code_points`.
10. Every property of every seed equals `unicode.lookup`, with `scx` compared as a set.
11. Every coverage entry of every seed matches `glyphIndex` on the embedded fixture.

### Real fixtures

12. Each embedded font's SHA-256 equals `font_sha256` in its expectation file.
13. Each fixture parses under `.reject`, and every field of its expectation file equals the parser's value.
14. The CJK subset has `outline == .cff`, `cff().charstrings_count == glyphCount()`, and name IDs only from {0, 7, 13, 14}.

### Synthetic fonts

15. Building `B_TT` twice yields identical bytes, its whole-file sum is `0xB1B0AFBA`, and `integrity()` is clean.
16. `B_TT` gives `glyphIndex` 1, 2, 3, 0, and 0 for U+0020, U+0041, U+1F600, U+0042, and U+D800.
    The selected subtable is (3, 10, 12).
    `advance` gives (500, 50), (250, 0), (600, 10), and (600, 10) for glyphs 0 to 3, and `GlyphOutOfRange` for 4.
    `glyphHeader` gives a box, `null`, a simple header, and `numberOfContours` -1.
    `name.find(3, 1, 0x409, 1)` is UTF-16BE "FP Min".
    The OS/2, post, GSUB, GPOS, and GDEF values equal the builder definition.
17. `B_CFF` gives `cff()` name `FPMinCFF`, 2 CharStrings, `cid_keyed` false, the (3, 1, 4) selection, `glyphIndex(0x41) == 1`, and `glyphHeader(0)` equal to `error.NotTrueType`.

### Malformed directory

18. Every proper prefix of `B_TT` and of `B_CFF` returns an error and never panics.
    Lengths below `12 + 16 * numTables` return `Truncated`.
19. `numTables` `0xFFFF` on `B_TT` returns `Truncated`.
20. `sfntVersion` `ttcf`, `wOFF`, `wOF2`, `true`, and `0x12345678` return `UnsupportedCollection`, `UnsupportedWoff`, `UnsupportedWoff2`, `UnsupportedSfntVersion`, and `UnknownSfntVersion`.
21. A `glyf` length extended 4 bytes past the end, an offset of `0xFFFFFFF0` with length `0x20`, and an appended `zzzz` record past the end each return `TableOutOfBounds`.
22. A `head` offset moved by 2 returns `MisalignedTable`.
23. Swapped `cmap` and `glyf` records return `UnsortedTableDirectory`, and two `name` records return `DuplicateTable`.
24. An `hhea` record moved into the `hmtx` range returns `OverlappingTables`.
    An appended `zzzz` record inside the `glyf` range parses.
25. Removing `hmtx` returns `MissingRequiredTable`.
    Removing `loca` from `B_TT` returns `MissingRequiredTable`.
    Adding `glyf` and `loca` to `B_CFF` returns `OutlineFormatMismatch`.
    Adding `CFF2` to `B_CFF` returns `UnsupportedCff2`.
26. A flipped `name` string byte under `.report` lists exactly `name` and sets `head_adjustment_ok` false, and under `.reject` returns `ChecksumMismatch`.
    A wrong `checksumAdjustment` alone lists no table, sets the flag false, and fails under `.reject`.
    A wrong `post` record checksum lists exactly `post`.

### Malformed required tables

27. `head` with length 53, magic 0, `unitsPerEm` 15, `unitsPerEm` 16385, `indexToLocFormat` 2, or `majorVersion` 2 returns `InvalidHead`.
28. `maxp` 0.5 in `B_TT`, 1.0 in `B_CFF`, version `0x00020000`, `numGlyphs` 0, or a 31-byte 1.0 table returns `InvalidMaxp`.
29. `numberOfHMetrics` 0, `numberOfHMetrics` 5, or a 35-byte `hhea` returns `InvalidHhea`, and an `hmtx` one byte short returns `InvalidHmtx`.
30. A `loca` one byte short, a decreasing entry, or a last entry past `glyf` returns `InvalidLoca`.
    A 6-byte glyph 2, decreasing `endPtsOfContours`, or an overlong `instructionLength` parses, but `glyphHeader(2)` returns `InvalidGlyph`.
31. `cmap` version 1, records past the table, a subtable offset at the table length, unsorted records, or a subtable length past the table returns `InvalidCmap`.
    Only a (3, 0) subtable, or only a (1, 0) format 0 subtable, returns `NoUnicodeCmap`.
32. Format 4 with `segCountX2` 0 or 7, last `endCode` `0xFFFE`, descending `endCode`, start after end, overlapping segments, `glyphIdArray` past the subtable, or a mapped glyph of 4 returns `InvalidCmap`.
    Each failure holds in the unselected (3, 1) subtable of `B_TT`.
33. Format 12 with `numGroups` `0xFFFFFFFF` in a 28-byte subtable, overlapping groups, `endCharCode` `0x110000`, or a span reaching glyph 4 returns `InvalidCmap`.

### Malformed optional tables

In every case below, the font parses, and `glyphIndex(0x41)` still equals 2.

34. `name` with `storageOffset` past the table, a string past storage, a count past the table, unsorted records, or an odd platform 3 length reports `rejected` with `offset_out_of_bounds`, `offset_out_of_bounds`, `count_out_of_bounds`, `unsorted_records`, and `odd_utf16_length`.
    Format 2 reports `unsupported_version`.
35. `OS/2` version 5 at 96 bytes reports `too_short`.
    Version 0 at 68 bytes is `valid` with `typo == null`.
    Version 1 at 85 bytes reports `too_short`, and version 6 reports `unsupported_version`.
36. `post` at 31 bytes reports `too_short`.
    A 2.0 table with `numGlyphs` 3 reports `glyph_count_mismatch`.
    Index 259 with one string, or a string past the table, reports `invalid_string_index`.
    Versions 2.5 and 4.0 report `unsupported_version`.
37. `GSUB` 1.2 reports `unsupported_version`.
    A ScriptList offset past the table, a script count past the table, a script offset past the table, a feature count past the table, or a lookup offset past the table reports the matching defect.
    Scripts `latn` before `DFLT` report `unsorted_records`.
    A 1.1 FeatureVariations offset past the table reports `offset_out_of_bounds`.
    The same cases hold for `GPOS`.
38. `GDEF` 1.1 reports `unsupported_version`, a 12-byte 1.2 table reports `too_short`, and a class definition offset past the table reports `offset_out_of_bounds`.
39. `B_CFF` returns `InvalidCff` for each of these: major 2, `hdrSize` 3, Name count 2, Name count `0xFFFF` in a short table, `offSize` 0, `offSize` 5, first offset 2, decreasing offsets, an INDEX past the table, a missing CharStrings, CharStrings count 3, `CharstringType` 1, 49 operands, an unterminated real, reserved byte 22, and a CharStrings offset past the table.
40. A comptime check finds no `std.mem.Allocator` among the parameter types of `font.parse`.

### Controller

41. An in-test zip with two stored members, one deflated member, and one directory entry yields the hand-computed inventory lines and SHA-256.
42. The zip reader rejects ZIP64, an encrypted member, `../x`, `a\\b`, a duplicate path, a truncated central directory, and method 12.
43. `corpus-fetch` from `file://` fixture sources, which only tests enable, writes the record and byte-identical extracted files.
    A second fetch honors the pins.
    A changed source, a wrong published digest, a wrong `git_blob`, or a different `published_url` body fails and leaves the sources, record, and files unchanged.
44. `corpus-verify` exits with status 1 for a changed extracted file, a changed derived file, a missing source, a license digest mismatch, an applicability count mismatch, and an `upstream` that differs from `specs/corpora.json`.
45. File-set applicability reports the per-directory breakdown, and `selected + unclassified = discovered`.
    A zip without file members fails validation.
46. `corpus-repin unicode` exits with status 1 and names the contract decision.
47. Record validation rejects a font entry without a license digest, a source without a release, a derived entry without a tool version, input digest, or `argv`, and a derived entry without `reserved_font_names`.
48. Every `selected`, `derived`, and license path in the committed `unicode` and `opentype-fixtures` records matches its recorded size and SHA-256.
49. The committed capability record validates, contains exactly the frozen IDs, statuses, and owner tasks, and names only owner tasks that exist in `engineering/plan.json`.
    A variant without `glyph-rasterization`, with owner `FP-9999`, or with a `null` owner fails.

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Import only provenance-recorded Unicode data and redistributable fixtures | 1 to 4, 12, 14, 41 to 48 |
| Parse a frozen OpenType table set with checked offsets and sizes | 13, 15 to 17, 19 to 39 |
| Reject malformed tables without unbounded allocation | 18 to 40 |
| Create Arabic, Indic, CJK, and mixed-direction qualification seeds | 5 to 11 |
| Keep shaping, fallback, and rasterization as explicit remaining obligations | 20, 25, 49, and the `uncovered-emoji` seed in case 11 |

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0013/raw/`.

1. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0013-cache-before` at the base.
2. Record `corpus-fetch-unicode.log`, `corpus-applicability-unicode.log`, and `corpus-verify-unicode.log`.
3. Record `fonttools-install.log` with the wheel digest check and the `pip install --no-index --no-deps` run.
4. Record `corpus-fetch-opentype-fixtures.log`.
5. Record `cjk-subset-1.log` and `cjk-subset-2.log`, each followed by `sha256sum` of its output.
6. Record `font-expectations.log` with each expectation run.
7. Record `corpus-applicability-opentype-fixtures.log` and `corpus-verify-opentype-fixtures.log`.
8. Record `ucd-generate.log` and `ucd-check.log`.
9. Record an uncached `tests-after.log` with `zig build test --summary all --cache-dir out/fp0013-cache-after`.
10. Record `controller-tests-after.log` with `node tools/fairpane.mjs test`.
11. Write `engineering/evidence/FP-0013/README.md` with the proposed `specs/corpora.json` values and every observed stop-rule value.

The mutation control makes the directory validator accept a tag equal to or below its predecessor.
Store its exact diff in `mutation-directory-order.diff` beside its log.
The control must fail case 23.
The integrator records `HEAD`, the staged diff, and file hashes.
The integrator then runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0013/gates`.

## Authority

Writable paths: `src`, `tests`, `tools`, `build.zig`, and `specs` except `specs/corpora.json`, plus `engineering/evidence/FP-0013/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Network access occurs only in `corpus-fetch` and in the recorded fontTools wheel download.
Required reviewer: `fairpane-review`.

## Non-goals

- No shaping, bidi resolution, segmentation, line breaking, fallback selection, outline decoding, hinting, or rasterization exists in this task.
- No WOFF, WOFF2, Brotli, collection, CFF2, variable, color, bitmap, or vertical-metric support exists in this task.
- No cmap format 14 lookup, symbol cmap, or legacy cmap format lookup exists in this task.
- No C ABI, platform font discovery, or CLDR import exists in this task.
- No Unicode file outside the eight listed files is imported.
- No acceptance threshold, gate, or protected corpus pin changes in this task.

## Revision 1

Base: the commit that freezes this revision.
Source findings: `engineering/evidence/FP-0013/reviews/review-1-reject.json` and `engineering/evidence/FP-0013/reviews/security-review-1-reject.json`.
Every section above stays in force except where this revision replaces it.
Writable paths stay as above.

### cmap work bound

The set of validated cmap subtable offsets keeps its capacity of 512.
An encoding record that names an offset outside a full set makes `parse` return `InvalidCmap` instead of validating that subtable again.
Each distinct subtable offset is therefore validated at most once.
The README states the validation cost of each subtable format, the total bound across all encoding records, and the bound when distinct subtables overlap, and it cites the regression cases.

### Accessors after parse

The `Font` documentation states that the bytes must stay unchanged for the lifetime of the `Font`, so a loader of script-visible memory must copy them first.
No accessor may reach illegal behavior when that rule is broken.
Each `.?`, `unreachable`, and unchecked `@intCast` that depends on an invariant from `parse` becomes a checked path with a documented result: `null`, glyph 0, zero, or an error, as each accessor's documentation states.
A public accessor that takes an index returns `null` or an error for an index out of range, instead of asserting.
The documentation of `gsub`, `gpos`, `post`, and `name` states that each call parses its table again in time linear in the table length.

### ZIP reading

`tools/fileset.mjs` rejects an archive in these cases before it inflates any member.

- Two members' ranges from local header to the end of compressed data overlap, or a range lies outside the central directory's region rules.
- A local header disagrees with its central directory entry in method, flags, CRC-32, or sizes, or it carries a ZIP64 extra field or flag bit 13.
- An entry's external attributes mark a symbolic link.
- Two entry names are equal after ASCII case folding.
- The sum of declared uncompressed sizes exceeds 1 GiB, or one member's declared uncompressed size exceeds 1024 times its compressed size.

Inflation still stops at each member's declared size, and a CRC-32 or size mismatch still fails.

### Fetch order

`corpus-fetch` compares each downloaded source with every known digest before it parses it.
The known digests are the published digest, the previous record's SHA-256, and any `specs/corpora.json` pin.
A mismatch fails before `readZip`, and `corpus-verify` stops before parsing a source whose digest does not match its record.

### Network

Each download follows redirects manually.
Every hop must use `https:` on one of the hosts `www.unicode.org`, `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`, and `raw.githubusercontent.com`.
A download stops when it exceeds the source's pinned size or, without a pinned size, 256 MiB.

### Atomic replacement

The write phase of `corpus-fetch` stages every new file beside its target, keeps the old files, and restores every replaced file and the source directory when any step fails.
The record is written last.
A failure leaves no staged or temporary file behind.

### fontTools invocation

`corpus-derive` and the documented `font_expectations.py` procedure run Python with the staging directory as the working directory, `PYTHONSAFEPATH=1`, and an environment without any other `PYTHON*` variable.
Before it runs, `corpus-derive` checks every installed fontTools file against the wheel's `RECORD` digests.
The README states that fontTools runs without an operating-system sandbox, on inputs pinned by Git blob or SHA-256 only.
`sfntCopyright` stops at the first `name` record and checks the `name` table header length before it reads.

### Evidence integrity

Case 12 also compares `generator.script_sha256` with the SHA-256 of the committed `tools/fonts/font_expectations.py`, and the recorded fontTools version with `engineering/dependencies.json`.
The reference test marks every code point that a parsed file assigns, and it fails when any code point stays unassigned.
The README and `specs/README.md` state that the UCD files and the `noto-sans` archive were trusted on first use, and that the `specs/corpora.json` pins check later fetches.

### Revision 1 test cases

50. A font with 513 encoding records that name 513 distinct valid subtables returns `InvalidCmap`.
51. A font with 65535 encoding records that all name one format 4 subtable, whose 256 segments share one glyph ID array, parses, and a validation counter that exists only in test builds shows one validation.
52. Accessors given an index out of range return `null` or an error, and accessors over a `Font` whose bytes were changed after `parse` neither panic nor read out of bounds, for each changed field that a `.?`, `unreachable`, or `@intCast` used to trust.
53. Controller: archives with overlapping members, a local and central header mismatch, a symbolic-link member, names equal under case folding, a declared total over 1 GiB, a ratio over 1024, a CRC-32 mismatch, an inflated-size mismatch, and a drive-letter name each fail before any member is written.
54. Controller: a fetch whose downloaded bytes mismatch a known digest fails without calling `readZip`; an `http:` hop and a hop to another host each fail; a download over its size limit stops; and a failure injected during the write phase leaves every previous file, the source directory, and the record unchanged.
55. Controller: `corpus-derive` refuses a fontTools installation with one changed file, and its child process sees `PYTHONSAFEPATH=1` and no other `PYTHON*` variable.

Cases 50 to 52 must fail before the fix, and so must every part of cases 53 to 55 that the current code does not already meet.
A mutation control that removes the full-set rejection must fail case 50 or 51.

### Revision 1 evidence

Record `tests-before-r1.log`, `mutation-cmap-r1.log` with its diff, an uncached `tests-after-r1.log`, `controller-tests-after-r1.log`, `ucd-check-r1.log`, and `corpus-verify-r1.log` for both corpora under `engineering/evidence/FP-0013/raw/`.
Run every Zig command through `node tools/fairpane.mjs record --env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Record `font-expectations-r1.log`, which reruns `font_expectations.py` under the hardened invocation for all four fixtures and shows byte equality with the committed expectation files.
The README gains a `## Revision 1` section and the rewritten bounded-work argument.
The integrator records a search of the CJK subset's bytes for `Source` in ASCII and in UTF-16BE.
