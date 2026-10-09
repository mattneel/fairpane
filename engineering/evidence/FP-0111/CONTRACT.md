# FP-0111 task contract

## Identity

Task ID: `FP-0111`, "Parse OpenType layout common tables and GDEF for shaping".
Workstream: `text`.
Base: the commit that freezes this contract, which is local `HEAD` `b9217fe` or later.
`b9217fe` ("plan: route the FP-0111 handoffs and give open tasks evidence paths") contains `194739e`, so the plan entry has six criteria.
Prerequisite: `FP-0013`, accepted.
This is the fourth slice of the `FP-0015` split, after `FP-0108`, `FP-0109`, and `FP-0110`. `FP-0112` and `FP-0113` build on it, and `FP-0118` reads its ligature carets.
A contract worker drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-text`.
Authority: `routine-local-engineering`.
Required reviewers: `fairpane-review` and `fairpane-security`. The security reviewer reviews it because it parses hostile font data.

### Plan entry read

At `b9217fe`, the plan entry is at `engineering/plan.json:3865-3887`, and its six criteria are at lines 3876 to 3882.
Commit `194739e` ("plan: route the text-rendering-tests import and the layout dumps") added criterion 6 and the `tools` path, as the `FP-0111` note in `engineering/state.json:978` states.
This contract covers all six criteria.

1. Parse Coverage formats 1 and 2, ClassDef formats 1 and 2, LangSys tables, feature index lists, Lookup tables, lookup flags, and mark filtering sets with checked offsets and bounded work.
2. Select the lookups for a script tag, a language tag, and a feature set, with DFLT and default LangSys fallback as the OpenType common table formats chapter specifies.
3. Parse GDEF glyph classes, mark attachment classes, mark glyph sets, and ligature caret lists.
4. Report FeatureVariations, unknown lookup types and formats, and Device and VariationIndex data as unsupported, never as empty results.
5. Reject malformed subtables without a panic, unbounded allocation, or native recursion, tested with synthetic fonts from the first-party builder.
6. Check each fixture font's parsed GDEF classes and its GSUB and GPOS script, feature, and lookup lists, including each lookup's type, flags, subtable formats, and coverage, against dumps that `tools/fonts/font_expectations.py` writes with fontTools under the font-expectations command's hardened invocation, as the owner approved on 2026-10-09.

### Integrator decisions

- Agent Check0111 checked the draft twice: its first check (fix-first, 3 majors) led to this revision and to plan commit `b9217fe`, and its re-check returned freeze with five minor edits, which the integrator applied at the freeze.
- The fontTools dumps extend the existing `<stem>.expect.json` files, whose format version becomes 2. The `gdef`, `gsub`, and `gpos` objects gain the layout data. The `font-expectations` command in `tools/fileset.mjs:1183-1225` already writes and checks exactly these files, so the hardened invocation needs no change. `tools/fileset.mjs:1204` maps each font to exactly one `.expect.json`.
- The dumps run only through `node tools/fairpane.mjs font-expectations`. fontTools never writes shaping output, and no build, gate, test, or engine path runs it, as `engineering/dependencies.json:131-135` states.
- The in-process `postRead` wrappers in "Expectation dumps" are accepted. They are installed once at import, before any `TTFont` is opened. They call the original method with identical arguments and catch no exception. They change no installed file, so the installation check still holds.
- `FP-0111` does not wait for `FP-0078`. Evidence step 0 records the font digests before the first fontTools run and compares them with `specs/snapshots/opentype-fixtures.json`. The pre-read check inside the command stays with `FP-0078` criterion 1.
- `FP-0013` cases 13 and 16 are amended as "Amended FP-0013 cases" states. No other FP-0013 case changes.
- `Defect` gains exactly seven members: `index_out_of_range`, `invalid_range`, `inconsistent_coverage_index`, `nested_extension`, `mixed_lookup_types`, `missing_default_lang_sys`, and `null_offset`. This amends the FP-0013 sentence "`Defect` has exactly these values".
- The strictness choices in "Strictness choices for FP-0058" are frozen. The integrator confirmed four of them: rejecting the `gdef` Example 2 ClassDef, rejecting a `DFLT` script with a NULL default LangSys, no DFLT fallback once a script record matched, and accepting glyph IDs at or past `numGlyphs`. `FP-0058` compares every row with web-font practice under its criterion "Compare the OpenType layout strictness choices that the FP-0111 contract lists with web-font practice, and record each kept or changed choice." (`engineering/plan.json:2938` at `b9217fe`).
- Selection work counts only the reads in steps 7 and 8 of "Selection". The limit defaults to 1,048,576 units.
- A selection request names at most 63 feature tags. Bit 63 of each mask marks the required feature. A caller with more tags splits the request across calls and combines the masks, because lookup indices do not change between calls.
- When a GSUB or GPOS table has a FeatureVariations table, selection returns the default lookups and sets `feature_variations = true`. `chapter2` "Feature variations" states that the defaults "will also be used under all conditions in implementations that do not support the feature variations table". The flag reports the unsupported data. `FP-0059` replaces the report under its criterion "Evaluate GSUB and GPOS FeatureVariations condition sets for the selected instance, and apply the GDEF item variation store through VariationIndex tables in GDEF and GPOS, replacing the FP-0111 and FP-0113 unsupported reports." (`engineering/plan.json:2963` at `b9217fe`).
- Criterion 6's "coverage" means each subtable's primary Coverage, as `chapter2` defines it: "Each subtable (except for an Extension LookupType subtable) includes a Coverage table". `FP-0112` and `FP-0113` test the other coverages and ClassDefs inside lookups with synthetic fonts.
- The dumps list glyph IDs one by one. They do not compress ranges, so the test stays independent of the dump code.
- `specs/capabilities/text-fonts.json` is writable. `engineering/plan.json:3871` at `b9217fe` lists it in `FP-0111`'s `allowed_paths`. The FP-0108 rule (`engineering/evidence/FP-0108/CONTRACT.md:18`) makes the record update a frozen part of each slice that implements a capability. The `shaping.engine_behavior` text in "Capability record" is frozen.
- The task adds at most 10 seconds to the `tests/text` run step on the development host. It adds no controller case, so the Windows controller-test gate is unaffected.
- No HarfBuzz output is an expectation. fontTools supplies only table-structure dumps. Every other expectation is hand-derived from the cited chapters.

## Sources

All sources were retrieved on 2026-10-09.

- OpenType 1.9.1, "OpenType layout common table formats" (`chapter2`), source commit `54f34ea45cd132f2739b100b600b6f2cac540708`: <https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2>. These sections apply:
  - "Scripts and languages": the ScriptList table ("stored in alphabetic order of the script tags"), the DFLT paragraphs ("An application should use a DFLT script table if there is not a script table associated with the specific script ..."; "If there is a DFLT script table, it must have a default language system table"; "applications should support use of a non-default language system table that is associated with DFLT script"), the Script table ("The LangSysRecord array must be sorted alphabetically by language system tag"), and the LangSys table (`requiredFeatureIndex`, `0xFFFF`, featureIndices "in arbitrary order").
  - "Overview": "When doing layout for a run of text, it uses features specified by one or the other, but not both."
  - "FeatureList table" ("should be sorted alphabetically by feature tag"), "Feature table" ("the client arranges the indices numerically into their LookupList order"), "LookupList table", "Lookup table", and the "LookupFlag bit enumeration".
  - "Coverage table": format 1 ("must be in numerical order") and format 2 ("Ranges must be in startGlyphID order, and they must be distinct, with no overlapping"; "startCoverageIndex for each non-initial range must equal ...").
  - "Class definition table": formats 1 and 2 ("The glyph ranges must not overlap"; "The records must be sorted by the first glyph ID in each range").
  - "Common formats for contextual lookup subtables": the SequenceContextFormat3 and ChainedSequenceContextFormat3 layouts.
  - "Device and VariationIndex tables" and "Feature variations".
  - Examples 1 to 9.
- OpenType 1.9.1 `gdef`, source commit `810414e13e39f68adfb5f12d525e6b50c850fbbc`: <https://learn.microsoft.com/en-us/typography/opentype/spec/gdef>. The header versions 1.0, 1.2, and 1.3, the GlyphClassDef enumeration, LigCaretList, LigGlyph, CaretValue formats 1 to 3, MarkGlyphSets ("The array of offsets for the Coverage tables uses Offset32"), and Examples 1 to 7.
- OpenType 1.9.1 `gsub` and `gpos`, source commit `810414e13e39f68adfb5f12d525e6b50c850fbbc`: the lookup type enumerations (GSUB 1 to 8, GPOS 1 to 9), each subtable's format field and first offset, and the extension rules ("The extensionLookupType field must be set to any lookup type other than 7" or 9; "all of the extension subtables must have the same extensionLookupType").
- fontTools 4.66.1, wheel SHA-256 `7234ae9e28db64273fbbfa72caebd0a97e3bdba6b05064114741b9539ef339d0` (`engineering/dependencies.json:124-125`). Source at tag `4.66.1`:
  - `Lib/fontTools/ttLib/tables/otBase.py:953-991`: `BaseTable.decompile` calls `readFormat` and then `postRead(table, font)` at line 989. Lines 1221-1222 set `self.Format`. These numbers count the file's first line, `from fontTools.config import OPTIONS`, as line 1.
  - `Lib/fontTools/ttLib/tables/otTables.py`: `Coverage.postRead` (from line 927) sorts format 2 ranges by `StartCoverageIndex`, logs "GSUB/GPOS Coverage is not sorted by glyph ids.", and runs `del self.Format` at line 950. `SingleSubst`, `MultipleSubst`, `ClassDef`, `AlternateSubst`, and `LigatureSubst` run `del self.Format` at lines 1182, 1250, 1344, 1430, and 1498. `ClassDef.postRead` stores only nonzero classes.
  - `Lib/fontTools/ttLib/tables/otData.py`: `Lookup.MarkFilteringSet` with `aux="LookupFlag & 0x0010"`, `Script.DefaultLangSys`, `LangSys.ReqFeatureIndex`, `ContextSubstFormat3.Coverage`, `ChainContextSubstFormat3.InputCoverage`, `MarkBasePosFormat1.MarkCoverage`, `MarkMarkPosFormat1.Mark1Coverage`, `ExtensionSubstFormat1.ExtensionLookupType` and `ExtSubTable`, the GSUB and GPOS `FeatureVariations` with `aux="Version >= 0x00010001"`, the GDEF fields, `MarkGlyphSetsDef`, `LigCaretList`, `LigGlyph`, `CaretValueFormat1` to `3`, and `Device`.
- `docs/RENDERING_AND_TEXT.md:40-44`, which the plan entry requires: the engine owns shaping, and "Contextual substitutions and mark positioning need script-specific OpenType fixtures."
- `engineering/evidence/FP-0013/CONTRACT.md`, including its revision 1 "Accessors after parse" and "fontTools invocation" rules.
- `engineering/evidence/FP-0108/CONTRACT.md:18`, the capability-record rule.
- `engineering/evidence/text/owner-answers-1.log`, which records the owner answer `fonttools: Extend`.
- `engineering/plan.json` at `b9217fe`: lines 3865-3887 (`FP-0111`), 2938 (`FP-0058`'s layout strictness criterion), and 2963 (`FP-0059`'s FeatureVariations and item variation store criterion).
- Repository files: `src/font/layout.zig`, `src/font/opentype.zig`, `src/font/tables.zig`, `src/font/reader.zig`, `tests/text/sfnt_builder.zig`, `tests/text/fixture_test.zig`, `tests/text/synthetic_test.zig`, `tests/text/malformed_test.zig`, the four fixture fonts and their `.expect.json` files, `specs/snapshots/opentype-fixtures.json`, `tools/fonts/font_expectations.py`, `tools/fileset.mjs`, and `tools/README.md`.

### Observed facts that shaped the decisions

- `src/font/opentype.zig:14` declares `const layout = @import("layout.zig");` without `pub`, and line 18 declares `const Reader = reader.Reader;` without `pub`. `opentype.zig:332-344` define `gdef`, `gsub`, and `gpos`, which call `layout.parseGdef` and `layout.parseLayout`.
- `src/font/layout.zig:11-46` define `Layout` with only `scriptCount`, `scriptTag`, `featureCount`, `featureTag`, and `lookupCount`. `layout.zig:113-124` define `Gdef` as header offsets with no methods. No Coverage, ClassDef, LangSys, Feature, Lookup, or Device type exists in `src/font`.
- `layout.zig:52-69` check each Script, Feature, and Lookup offset only for `list + offset < len`, so a NULL offset passes, and `layout.zig:73-110` reject unsorted script tags.
- `src/font/tables.zig:11-19` define `Defect` with seven members, and `tables.zig:22-30` define `TableStatus`, whose `unsupported_version` is "The table's version or format, as stored."
- `src/font/glyf.zig:23` declares the test-only counter `pub var work: if (builtin.is_test) u64 else void = if (builtin.is_test) 0 else {};`.
- `tests/text/fixture_test.zig:126` requires 4 keys in each `gsub` and `gpos` object, line 140 requires expectation version 1, and line 248 requires 1 key in `gdef`.
- `tests/text/synthetic_test.zig:111` compares `font.Gdef` with a struct literal of its seven fields.
- `tests/text/malformed_test.zig:676` (FP-0013 case 40) rejects both `std.mem.Allocator` and `?std.mem.Allocator` parameters.
- `tools/fonts/font_expectations.py:207-220` write only the version, tags, and lookup count of GSUB and GPOS, and only the version of GDEF.
- The expectation files record these values:

| Fixture | GDEF version | GSUB scripts, features, lookups | GPOS scripts, features, lookups | Table lengths (GDEF, GPOS, GSUB) |
| --- | --- | --- | --- | --- |
| `noto-sans` | `0x00010002` | 4, 37, 48 | 4, 3, 16 | 1124, 86636, 11960 |
| `noto-sans-arabic` | `0x00010002` | 2, 16, 41 | 2, 3, 22 | 352, 7564, 5518 |
| `noto-sans-devanagari` | `0x00010002` | 3, 30, 171 | 3, 5, 28 | 482, 14220, 62980 |
| `noto-sans-cjk-jp-subset` | absent | 7, 11, 11 | 7, 6, 6 | none, 692, 658 |

  Every GSUB and GPOS fixture table has version `0x00010000`, so no fixture has FeatureVariations.
- `specs/snapshots/opentype-fixtures.json:111`, `133`, `155`, and `186` record the SHA-256 of the four fonts.
- `chapter2` Example 7 lists glyph `i` with data `0000` and the comment "Ascender Class 1". This contract follows the data column.
- `gdef` Example 2 lists class ranges starting at `0x0024`, `0x009F`, `0x0058`, and `0x018F`, which are not sorted by start glyph, although `chapter2` requires sorted records.
- `gdef` Example 4 names `ffi` and `fi` in the opposite order from its coverage array. Its bytes give glyph `0x009F` one caret and glyph `0x00A5` two carets. This contract follows the bytes.
- `FP-0119`'s `tests/text` run step took 1 s after that task (`engineering/evidence/FP-0119/README.md:62`). The slowest `zig-test` CI run of `FP-0098` took 191 s against a 400 s ceiling (`engineering/evidence/FP-0119/CONTRACT.md`, "Observed facts").
- No controller test reads an expectation file's contents. `tools/fileset.mjs:1207` only compares bytes.
- `specs/capabilities/text-fonts.json:53` states for `shaping`: "No API. GSUB and GPOS expose only their script tags, feature tags, and lookup counts; no lookup runs." After this task, that text is false.
- `engineering/state.json:921-924` show `FP-0078` as planned. Its criterion 1, a font SHA-256 check before fontTools reads a fixture in `font-expectations`, is not implemented yet.

## Behavior

### Files

| File | Content |
| --- | --- |
| `src/font/layout.zig` | `const builtin = @import("builtin");` is added. `Layout` gains `kind` and `feature_variations`, plus `script`, `feature`, `lookup`, and `selectLookups`. The file also gains `Script`, `LangSys`, `Feature`, `Lookup`, `LookupStatus`, `Subtable`, `SubtableStatus`, `Request`, `SelectionLimits`, `Selection`, `SelectionStatus`, `SelectError`, and the test-only counter `work` |
| `src/font/layout.zig`, or new files under `src/font` that it re-exports | `Coverage`, `CoverageIterator`, `ClassDef`, `DeviceStatus`, `parseCoverage`, `parseClassDef`, `parseDevice`, and the GDEF types `MarkGlyphSets`, `LigCaretList`, `LigGlyph`, `CaretsStatus`, `CaretStatus`, and `CaretValue`. `Gdef` gains `table` and four methods |
| `src/font/tables.zig` | `Defect` gains the seven members above |
| `src/font/opentype.zig` | `pub const layout = @import("layout.zig");` replaces line 14. Line 18, `const Reader = reader.Reader;`, becomes `pub const Reader = reader.Reader;`. `gsub` and `gpos` pass their kind. The `gdef`, `gsub`, and `gpos` documentation states each method's cost. The module comment keeps "layout lookups are not interpreted", because no lookup is applied |
| `specs/capabilities/text-fonts.json` | The frozen `shaping.engine_behavior` text below |
| `tests/text/layout_builder.zig` | New. The builder of G, P, T_MFS, H(N), and the hex fixtures below |
| `tests/text/layout_test.zig` | New. Cases 1 to 24, each named `FP-0111 case N: ...` |
| `tests/text/layout_fixture_test.zig` | New. Case 25 |
| `tests/text/root.zig` | Imports both new test files and names FP-0111 in its header |
| `tests/text/fixture_test.zig` | Amended FP-0013 case 13 |
| `tests/text/synthetic_test.zig` | Amended FP-0013 case 16 |
| `tests/text/fonts/*/*.expect.json` | Regenerated only by `node tools/fairpane.mjs font-expectations`. Never edited by hand |
| `tools/fonts/font_expectations.py` | Format version 2, the layout dumps, and the warning handler below |
| `tools/README.md` | The font-expectations section names the version 2 layout fields and the warning handler |
| `tests/text/README.md` | Lines 5 and 8 name FP-0111 and `engineering/evidence/FP-0111/CONTRACT.md`. New sections describe the layout fixtures, the dumps, and the FP-0111 stop rules |

A file-scope declaration named `layout` does not collide with any local in `parse` (`opentype.zig:352-453`).
The worker may split files and refine names without changing behavior. `font.layout` must re-export every type and function named here.

### Interface

```zig
// tables.zig
pub const Defect = enum { too_short, offset_out_of_bounds, count_out_of_bounds, unsorted_records, glyph_count_mismatch, invalid_string_index, odd_utf16_length,
    index_out_of_range, invalid_range, inconsistent_coverage_index, nested_extension, mixed_lookup_types, missing_default_lang_sys, null_offset };

// layout.zig
const builtin = @import("builtin");

pub const Kind = enum { gsub, gpos };
pub const Layout = struct {
    // existing fields, plus:
    kind: Kind,
    feature_variations: u32, // the stored offset; 0 for version 1.0 or a NULL offset
    pub fn script(self: Layout, i: u16) ?TableStatus(Script);   // null when i >= scriptCount
    pub fn feature(self: Layout, i: u16) ?TableStatus(Feature); // null when i >= featureCount
    pub fn lookup(self: Layout, i: u16) ?LookupStatus;          // null when i >= lookupCount
    pub fn selectLookups(self: Layout, request: Request, limits: SelectionLimits, masks: []u64) SelectError!SelectionStatus;
};
pub fn parseLayout(t: Reader, kind: Kind) TableStatus(Layout);

pub const Script = struct {
    tag: Tag,
    lang_sys_count: u16,
    pub fn defaultLangSys(self: Script) TableStatus(LangSys); // .absent for a NULL offset
    pub fn langSysTag(self: Script, j: u16) ?Tag;
    pub fn langSys(self: Script, j: u16) ?TableStatus(LangSys);
};
pub const LangSys = struct {
    required_feature: ?u16, // null for 0xFFFF
    feature_index_count: u16,
    pub fn featureIndex(self: LangSys, k: u16) ?u16;
};
pub const Feature = struct {
    tag: Tag,
    params_offset: u16, // as stored; never followed
    lookup_index_count: u16,
    pub fn lookupIndex(self: Feature, k: u16) ?u16;
};
pub const Lookup = struct {
    lookup_type: u16,   // the effective type: extensionLookupType for an extension lookup
    extension: bool,    // true when the stored type is 7 (GSUB) or 9 (GPOS)
    flag: u16,          // as stored
    subtable_count: u16,
    mark_filtering_set: ?u16,
    pub fn rightToLeft(self: Lookup) bool;           // 0x0001
    pub fn ignoreBaseGlyphs(self: Lookup) bool;      // 0x0002
    pub fn ignoreLigatures(self: Lookup) bool;       // 0x0004
    pub fn ignoreMarks(self: Lookup) bool;           // 0x0008
    pub fn useMarkFilteringSet(self: Lookup) bool;   // 0x0010
    pub fn markAttachmentClass(self: Lookup) u8;     // flag >> 8
    pub fn subtable(self: Lookup, k: u16) ?SubtableStatus;
};
pub const LookupStatus = union(enum) { rejected: Defect, unsupported_type: u16, unsupported_extension_format: u16, valid: Lookup };
pub const Subtable = struct {
    format: u16,
    pub fn coverage(self: Subtable) TableStatus(Coverage); // the primary coverage, defined below
};
pub const SubtableStatus = union(enum) { rejected: Defect, unsupported_format: u16, valid: Subtable };

pub const Request = struct { script: Tag, language: ?Tag = null, features: []const Tag };
pub const SelectionLimits = struct { max_work: u32 = 1 << 20 };
pub const Selection = struct {
    script: ?Tag,        // the script record used: the requested tag, DFLT, or null
    lang_sys: enum { requested, default, none },
    required_feature: ?u16,
    lookup_count: u16,   // the number of nonzero masks
    feature_variations: bool,
};
pub const SelectionStatus = union(enum) { rejected: Defect, limit_exceeded, valid: Selection };
pub const SelectError = error{ TooManyFeatures, MasksTooShort };

pub const Coverage = struct {
    format: u16,
    pub fn glyphCount(self: Coverage) u32;
    pub fn index(self: Coverage, glyph: u16) ?u16;
    pub fn iterator(self: Coverage) CoverageIterator; // next() ?u16, at most glyphCount() values
};
pub fn parseCoverage(t: Reader, offset: u64) TableStatus(Coverage);
pub const ClassDef = struct {
    format: u16,
    pub fn class(self: ClassDef, glyph: u16) u16;
};
pub fn parseClassDef(t: Reader, offset: u64) TableStatus(ClassDef);
pub const DeviceStatus = union(enum) {
    rejected: Defect,
    unsupported_device: struct { start_size: u16, end_size: u16, delta_format: u16 },
    unsupported_variation_index: struct { outer: u16, inner: u16 },
    unsupported_format: u16,
};
pub fn parseDevice(t: Reader, offset: u64) DeviceStatus;

pub const Gdef = struct {
    table: Reader,
    // the seven existing fields, unchanged
    pub fn glyphClasses(self: Gdef) TableStatus(ClassDef);       // .absent for a NULL offset
    pub fn markAttachClasses(self: Gdef) TableStatus(ClassDef);  // .absent for a NULL offset
    pub fn markGlyphSets(self: Gdef) TableStatus(MarkGlyphSets); // .absent for version 1.0 or a NULL offset
    pub fn ligatureCaretList(self: Gdef) TableStatus(LigCaretList); // .absent for a NULL offset
};
pub const MarkGlyphSets = struct { count: u16, pub fn set(self: MarkGlyphSets, i: u16) ?TableStatus(Coverage) };
pub const LigCaretList = struct { pub fn carets(self: LigCaretList, glyph: u16) CaretsStatus };
pub const CaretsStatus = union(enum) { not_covered, rejected: Defect, valid: LigGlyph };
pub const LigGlyph = struct { caret_count: u16, pub fn caret(self: LigGlyph, k: u16) ?CaretStatus };
pub const CaretStatus = union(enum) { rejected: Defect, unsupported_format: u16, valid: CaretValue };
pub const CaretValue = union(enum) {
    coordinate: i16,
    point: u16,
    coordinate_device: struct { coordinate: i16, device: ?DeviceStatus }, // device is null for a NULL offset
};

/// Selection work in test builds: one for each featureIndices and lookupListIndices entry that steps 7 and 8 of "Selection" read.
/// Validation inside an opening call is not counted. Each selectLookups call resets it.
/// Concurrent selections in a test build race on this counter.
pub var work: if (builtin.is_test) u32 else void = if (builtin.is_test) 0 else {};
```

### Common rules

- Every read goes through `Reader`. Offset sums use 64-bit arithmetic.
- Every count is checked against the remaining bytes before a loop over it starts.
- No function allocates, and none takes an allocator. `selectLookups` writes only into the caller's `masks`.
- No function recurses. Extension subtables are followed one level. A nested extension is rejected.
- Each opened structure keeps the counts it validated. An accessor never reads past those counts.
- If the font bytes change after a check, no accessor reaches illegal behavior, as FP-0013 revision 1 requires. Every value that indexes `masks` or a record array is read once, checked at its point of use, and then used. A check made by an earlier call is never trusted for memory safety.
- A structure-opening call costs time linear in the bytes of that structure. `Script` checks its LangSysRecords. `LangSys` and `Feature` check their index arrays. `Lookup` checks its offsets and, for an extension lookup, each extension header. `Coverage` and `ClassDef` check every record.
- Offsets are relative to the structure that the cited table definition names. An offset is "inside" when its absolute position is below the table length.

### Structures

A NULL `scriptOffset`, `featureOffset`, or `lookupOffset` makes `script(i)`, `feature(i)`, or `lookup(i)` return `rejected = null_offset`.

`Layout.script(i)` opens the Script table of ScriptRecord `i`:

1. Four header bytes must fit, or `too_short`.
2. `langSysCount` records of 6 bytes must fit, or `count_out_of_bounds`.
3. LangSys tags must strictly ascend, or `unsorted_records`.
4. A nonnull `defaultLangSysOffset` and every `langSysOffset` must be inside the table, or `offset_out_of_bounds`. A NULL `langSysOffset` is `null_offset`.
5. The script tag `DFLT` with a NULL `defaultLangSysOffset` is `missing_default_lang_sys`.

A LangSys table opens in this order:

1. Six header bytes must fit, or `too_short`.
2. `featureIndexCount` entries must fit, or `count_out_of_bounds`.
3. `requiredFeatureIndex` must be `0xFFFF` or below `featureCount`, or `index_out_of_range`.
4. Every feature index must be below `featureCount`, or `index_out_of_range`.
5. `lookupOrderOffset` is ignored.

A Feature table needs 4 header bytes (`too_short`), then `lookupIndexCount` entries (`count_out_of_bounds`), then every index below `lookupCount` (`index_out_of_range`).

`Layout.lookup(i)` opens a Lookup table with these checks, in this order:

1. Six header bytes must fit, or `too_short`.
2. `subTableCount` offsets must fit, or `count_out_of_bounds`.
3. With flag bit `0x0010`, the `markFilteringSet` field must fit, or `too_short`.
4. Each subtable offset must be nonnull (`null_offset`) and inside the table (`offset_out_of_bounds`).
5. A stored type of 0 or above 8 in GSUB, or 0 or above 9 in GPOS, is `unsupported_type` with that type.
6. For a stored type of 7 in GSUB or 9 in GPOS, each subtable is an extension header:
   - Eight bytes must fit, or `too_short`.
   - A format other than 1 is `unsupported_extension_format`.
   - An `extensionLookupType` of 7 in GSUB or 9 in GPOS is `nested_extension`.
   - An `extensionLookupType` that the table kind does not define is `unsupported_type`.
   - A type that differs from the first subtable's type is `mixed_lookup_types`.
   - The `extensionOffset` target must be inside the table, or `offset_out_of_bounds`.
   - The lookup's `lookup_type` is the shared `extensionLookupType`, and `extension` is true.
   - An extension lookup with no subtables keeps the stored type, 7 or 9, with `extension` true.

`Lookup.subtable(k)` reads the format of the subtable, or of the extension target.
Two bytes must fit, or `too_short`.
A format outside this table is `unsupported_format`.

| Kind | Type | Formats |
| --- | --- | --- |
| GSUB | 1 | 1, 2 |
| GSUB | 2, 3, 4, 8 | 1 |
| GSUB | 5, 6 | 1, 2, 3 |
| GPOS | 1, 2 | 1, 2 |
| GPOS | 3, 4, 5, 6 | 1 |
| GPOS | 7, 8 | 1, 2, 3 |

`Subtable.coverage()` opens the primary coverage, at an offset relative to the subtable:

- GSUB 5 and GPOS 7 format 3: `glyphCount` is at +2 and must be at least 1, or `count_out_of_bounds`. The coverage offset is at +6.
- GSUB 6 and GPOS 8 format 3: with `backtrackGlyphCount` b at +2, `inputGlyphCount` is at 4 + 2b and must be at least 1, or `count_out_of_bounds`. The coverage offset is at 6 + 2b.
- Every other type and format, including GPOS 4, 5, and 6, whose first coverage is the mark coverage: the coverage offset is at +2.
- Fields that do not fit are `too_short`. A NULL coverage offset is `null_offset`. An offset that is not inside the table is `offset_out_of_bounds`.

`parseCoverage(t, offset)` checks these rules:

1. `offset >= t.len()` is `offset_out_of_bounds`. Fewer than 4 bytes is `too_short`.
2. A format other than 1 or 2 is `unsupported_version` with that format.
3. Format 1 needs `glyphCount` glyphs (`count_out_of_bounds`) in strictly ascending order (`unsorted_records`).
4. Format 2 needs `rangeCount` records of 6 bytes (`count_out_of_bounds`). Each record needs `start <= end` (`invalid_range`). Each start must exceed the previous end (`unsorted_records`). Each `startCoverageIndex` must equal the number of glyphs in the earlier ranges (`inconsistent_coverage_index`).
5. `index` uses binary search, so a query costs O(log n). `glyphCount` may be 65536, and the largest index is 65535.

`parseClassDef(t, offset)` checks these rules:

0. `offset >= t.len()` is `offset_out_of_bounds`. Format 2 needs 4 header bytes, or `too_short`.
1. Format 1 needs 6 header bytes (`too_short`), `glyphCount` values (`count_out_of_bounds`), and `startGlyphID + glyphCount <= 65536` (`count_out_of_bounds`).
2. Format 2 needs its records (`count_out_of_bounds`), `start <= end` (`invalid_range`), and each start above the previous end (`unsorted_records`).
3. Any other format is `unsupported_version`.
4. `class` returns 0 for an uncovered glyph, in O(1) for format 1 and O(log n) for format 2.

`parseDevice(t, offset)` returns, in this order:

0. `rejected = offset_out_of_bounds` when `offset >= t.len()`.
1. `rejected = too_short` when 6 bytes do not fit.
2. `unsupported_variation_index` with the first two fields when `deltaFormat` is `0x8000`.
3. `unsupported_format` for any `deltaFormat` other than 1, 2, 3, or `0x8000`.
4. For formats 1 to 3: `invalid_range` when `startSize > endSize`. `count_out_of_bounds` when ⌈(endSize − startSize + 1) × bits / 16⌉ words do not fit, with bits 2, 4, or 8.
5. Otherwise `unsupported_device`.

No Device or VariationIndex value is ever applied.

### GDEF

- `glyphClasses` and `markAttachClasses` parse the ClassDef at their header offsets.
- `markGlyphSets` needs version 1.2 or 1.3 and a nonnull offset, or it is `.absent`. A format other than 1 is `unsupported_version`. `markGlyphSetCount` Offset32 entries must fit, or `count_out_of_bounds`. `set(i)` returns null for `i >= count`. Otherwise it parses the Coverage at the MarkGlyphSets start plus `coverageOffsets[i]`, and a NULL coverage offset is `null_offset`.
- `ligatureCaretList` needs its 4 header bytes (`too_short`), its LigGlyph offsets (`count_out_of_bounds`), a valid Coverage (that Coverage's defect), every LigGlyph offset nonnull (`null_offset`), and every LigGlyph offset inside the table (`offset_out_of_bounds`).
- `carets(glyph)` returns `not_covered` for an uncovered glyph. A coverage index at or past `ligGlyphCount` is `index_out_of_range`. Otherwise it opens the LigGlyph: 2 bytes (`too_short`), then `caretCount` offsets (`count_out_of_bounds`).
- `caret(k)` reads the CaretValue at the LigGlyph start plus its offset:
  - A NULL `caretValueOffset` is `null_offset`.
  - Format 1 gives `coordinate`, and format 2 gives `point`.
  - Format 3 gives `coordinate_device`, with `device` from `parseDevice` at the CaretValue start plus `deviceOffset`, or null for a NULL offset.
  - Any other format is `unsupported_format`.
  - A value that does not fit is `too_short`.
- `item_var_store` stays a header field. A nonnull value means variation data that this task does not apply.

### Selection

`selectLookups` follows `chapter2` "Scripts and languages" and "Feature table":

1. It returns `error.TooManyFeatures` when `request.features.len > 63`, and `error.MasksTooShort` when `masks.len < lookupCount`. Both checks happen before any read.
2. It sets `masks[0..lookupCount]` to 0 and resets `work`.
3. It finds the ScriptRecord whose tag equals `request.script`. If none exists, it finds `DFLT`. If neither exists, it returns `valid` with `script = null`, `lang_sys = .none`, and no masks.
4. It opens that Script. A defect returns `rejected`.
5. If `request.language` names a LangSysRecord of that Script, it uses that LangSys (`.requested`). Otherwise it uses the default LangSys (`.default`). If the default is NULL, it returns `valid` with `lang_sys = .none`. It never falls back to DFLT once a script record matched.
6. It never merges the default LangSys into a requested LangSys.
7. For each featureIndices entry f, it reads the FeatureRecord tag. For each position p where `request.features[p]` equals that tag, it ORs bit p into `masks[i]` for every lookup index i in Feature f.
8. For a required feature r, it ORs bit 63, plus bit p for each p whose tag equals r's tag, into `masks[i]` for every lookup index i in Feature r.
9. Work counts only the reads that steps 7 and 8 make: one unit for each featureIndices entry read in step 7, and one unit for each lookupListIndices entry read in step 7 or step 8. Opening the Script, the LangSys, or a Feature for selection validates its arrays without charging work. Before each counted read, if `work == limits.max_work`, it returns `limit_exceeded`; otherwise it adds 1. The lookup lists of features that the request does not name, other than the required feature, are not read. Uncounted validation in one call is therefore at most the ScriptList and Script records, the LangSys indices, the counted work, and one Feature of at most 65,535 indices.
10. Any structural defect returns `rejected`. After `rejected` or `limit_exceeded`, the contents of `masks[0..lookupCount]` are unspecified.
11. `feature_variations` is true when the Layout's `feature_variations` offset is nonzero. The masks then hold the default features only.
12. The caller applies lookups in ascending index order, which is LookupList order.

### Strictness choices for FP-0058

`FP-0058` compares each row with web-font practice under `engineering/plan.json:2938`.

| # | Input | FP-0111 result | Basis |
| --- | --- | --- | --- |
| 1 | Script records not strictly ascending | The table is rejected (FP-0013, unchanged) | "stored in alphabetic order" |
| 2 | LangSys records not strictly ascending | Script `unsorted_records` | "must be sorted alphabetically" |
| 3 | FeatureRecords not sorted | Accepted | "should be sorted" |
| 4 | `DFLT` with a NULL default LangSys | Script `missing_default_lang_sys` | "must not equal NULL" |
| 5 | Nonzero `lookupOrderOffset` | Ignored | "Reserved" |
| 6 | A feature, required feature, or lookup index past its list | `index_out_of_range` | The indices name list records |
| 7 | Coverage format 1 not strictly ascending, including duplicates | `unsorted_records` | "must be in numerical order"; a duplicate makes the Coverage Index ambiguous |
| 8 | Coverage format 2 with start after end, out-of-order or overlapping ranges, or a wrong `startCoverageIndex` | `invalid_range`, `unsorted_records`, or `inconsistent_coverage_index` | "must be distinct, with no overlapping"; "must equal". fontTools instead sorts by `startCoverageIndex` and warns |
| 9 | ClassDef format 2 unsorted or overlapping, including the `gdef` Example 2 bytes | `unsorted_records` | "must be sorted"; "must not overlap" |
| 10 | Glyph IDs at or past `numGlyphs` in a Coverage or ClassDef | Accepted | No rule; such glyphs never enter a buffer |
| 11 | Reserved lookup flag bits `0x00E0` | Kept in `flag`; no helper reports them | "For future use" |
| 12 | Mixed extension types; an extension of an extension; an extension format other than 1 | `mixed_lookup_types`; `nested_extension`; `unsupported_extension_format` | The GSUB and GPOS extension rules |
| 13 | An extension lookup with no subtables | Valid; the type stays 7 or 9 | No effective type exists |
| 14 | A NULL Script, Feature, Lookup, LangSysRecord, subtable, coverage, LigGlyph, CaretValue, or mark glyph set offset (a NULL defaultLangSysOffset is `.absent`, except for `DFLT`, row 4) | `null_offset` | Each offset names a required structure; a NULL offset would name the parent's start |
| 15 | A format 3 context with zero input glyphs | `count_out_of_bounds` from `coverage()` | No primary coverage exists |
| 16 | A LigCaretList coverage glyph past `ligGlyphCount` | That glyph is `index_out_of_range`; others stay valid | "one for each ligature in the Coverage table" |
| 17 | FeatureVariations present | Defaults, with `feature_variations = true` | "Those defaults will also be used under all conditions in implementations that do not support the feature variations table" |
| 18 | Device `startSize > endSize`, or a short delta array | `invalid_range`, or `count_out_of_bounds` | The Device table definition |
| 19 | A script record without a default LangSys or the requested language | `lang_sys = .none`, with no DFLT fallback | DFLT applies only "if there is not a script table" for the script |
| 20 | The legacy tag `dflt`, and fallback to `latn` | Not used | Neither appears in `chapter2` |

### Expectation dumps

`tools/fonts/font_expectations.py` changes in these ways:

1. At module level, before any `TTFont` is opened, it wraps `postRead` of `otTables.Coverage` and `otTables.ClassDef`. Each wrapper sets `self.fairpane_format = self.Format` and then calls the original with identical arguments. It catches no exception.
2. It wraps `postRead` of `otTables.SingleSubst`, `MultipleSubst`, `AlternateSubst`, and `LigatureSubst` in the same way. Each wrapper also sets `self.fairpane_coverage = rawTable["Coverage"]` before it calls the original. fontTools deletes `Format` in each of these `postRead` methods, so the wrapper records the value that fontTools itself read.
3. `"version"` becomes 2. The docstring names FP-0013 case 13 and FP-0111 case 25. Every other field keeps its version 1 content.
4. A coverage dump is `{"format": cov.fairpane_format, "glyphs": font.getGlyphIDMany(cov.glyphs)}` in coverage order.
5. `gsub` and `gpos` are null when the table is absent. Otherwise each has exactly these keys, with lists in table order:
   - `version`.
   - `feature_variations`: whether `getattr(table, "FeatureVariations", None)` is not None.
   - `scripts`: one `{"tag", "default_lang_sys", "lang_sys"}` per ScriptRecord. `default_lang_sys` is null or `{"required_feature", "features"}`. `lang_sys` is a list of `{"tag", "required_feature", "features"}`. `required_feature` is null for `0xFFFF`.
   - `features`: one `{"tag", "lookups"}` per FeatureRecord.
   - `lookups`: one `{"type", "flag", "mark_filtering_set", "subtables"}` per Lookup. `type` is the stored `LookupType`. `mark_filtering_set` is `getattr(lookup, "MarkFilteringSet", None)`.
   - Each subtable is `{"extension", "type", "format", "coverage"}`. For an extension, `extension` is true, `type` is `ExtensionLookupType`, and the other fields describe `ExtSubTable`. For a non-extension subtable, `extension` is false and `type` is the lookup's `LookupType`. `format` is `fairpane_format` when present, else `Format`.
6. `coverage` is the primary coverage:
   - GSUB 1 to 4: `fairpane_coverage`.
   - GSUB 5 and GPOS 7 format 3: `Coverage[0]`.
   - GSUB 6 and GPOS 8 format 3: `InputCoverage[0]`.
   - GPOS 4 and 5: `MarkCoverage`. GPOS 6: `Mark1Coverage`.
   - Every other case: `Coverage`.
   - A subtable that matches none of these raises an error, and no file is written.
7. `gdef` is null when absent. Otherwise it has exactly these keys:
   - `version`.
   - `glyph_class_def` and `mark_attach_class_def`: null, or `{"format", "classes"}`, where `classes` lists `[glyph_id, class]` for each nonzero class in ascending glyph ID.
   - `mark_glyph_sets`: null, or `{"format": MarkSetTableFormat, "sets": [coverage dump, ...]}`.
   - `lig_caret_list`: null, or a list in coverage order of `{"glyph", "carets"}`. Each caret is `{"format": 1, "coordinate"}`, `{"format": 2, "point"}`, or `{"format": 3, "coordinate", "device"}`. `device` is null or `{"delta_format", "start_size", "end_size"}` from `DeltaFormat`, `StartSize`, and `EndSize`.
   - `item_var_store`: whether `getattr(gdef, "VarStore", None)` is not None.
8. Before it opens the font, the script attaches a `logging.Handler` to the `fontTools` logger that records every record at level WARNING or above. If any record was recorded, the script prints each message and exits with status 1 without writing the file.

The script writes no shaping output and computes no selection.
The owner decision of 2026-10-09 requires the argument vector and the input and output digests. `tools/fileset.mjs:1201` logs the argument vector `[python, "tools/fonts/font_expectations.py", <font>]`. Line 1210 logs each output's size and SHA-256, and line 1209 records them in the result. The digest logs in "Evidence" record the inputs before and after the run.

### Capability record

`shaping.engine_behavior` in `specs/capabilities/text-fonts.json:53` becomes: "No lookup is applied. fairpane.font.layout parses ScriptList, FeatureList, LookupList, Lookup headers, Coverage, ClassDef, and the GDEF classes, mark glyph sets, and ligature carets, and selects lookups by script, language, and feature tags. FeatureVariations, Device, and VariationIndex data, and unknown lookup types and formats, are reported as unsupported."
The status stays `remaining`, and the owner stays `FP-0015`.
FP-0013 case 49 checks only obligation IDs, statuses, and owner tasks, so no controller case changes.

## Exact test cases

Zig cases are named `FP-0111 case N: ...` and run through `zig build test`.
Each hex string below is big-endian 16-bit words unless it says otherwise.
"In B_TT" means `builder.ttTables` with the named table replaced through `TableSet.put`, then built and parsed under `.reject`.
A "blob" case calls the parse function on `font.Reader.init(bytes)` at offset 0, unless it names another offset.

### Layout fixtures

**E1**, GSUB from `chapter2` Example 1, 46 bytes:
`0001 0000 000A 002A 002C`, then `0003 68616E69 0014 6B616E61 0018 6C61746E 001C`, then three Script tables `0000 0000`, then `0000` (FeatureList) and `0000` (LookupList).

**E2**, GSUB from `chapter2` Example 2, 136 bytes:

- Header `0001 0000 000A 0034 0066`.
- ScriptList `0001 61726162 0008`.
- Script, Example 2: `000A 0001 55524420 0016 0000 FFFF 0003 0000 0001 0002 0000 0003 0003 0000 0001 0002`.
- FeatureList: `0004 696E6974 001A 66696E61 0020 6D656469 0026 6C6F636C 002C 0000 0001 0000 0000 0001 0001 0000 0001 0002 0000 0001 0003`, which is init, fina, medi, and locl, each with one lookup i. The list is not alphabetical, as strictness row 3 allows.
- LookupList: `0004 000A 0010 0016 001C`, then four Lookup tables `0001 0000 0000`.

**E34**, GSUB from `chapter2` Examples 3 and 4, 178 bytes:

- Header `0001 0000 000A 001E 004A`.
- ScriptList `0001 44464C54 0008`, Script `0004 0000`, and LangSys `0000 FFFF 0001 0001`.
- FeatureList, Example 3: `0003 6C696761 0014 6C696761 001A 6C696761 0022 0000 0001 0001 0000 0002 0000 0001 0000 0003 0000 0001 0002`.
- LookupList, Example 4: `0003 0008 0010 0018 0004 000C 0001 0018 0004 000C 0001 0028 0004 000C 0001 0038`, followed by LS three times.
- The Example 4 subtable offsets land at LookupList+32, +56, and +80, exactly where the three LS copies start.

Subtable byte strings, each self-contained with offsets relative to its own start:

| Name | Bytes | Meaning |
| --- | --- | --- |
| SS1 | `0001 0006 000A 0001 0002 0002 0003` | SingleSubst 1, coverage format 1 [2, 3] |
| SS2 | `0002 000C 0003 0004 0005 0006 0002 0001 0001 0003 0000` | SingleSubst 2, coverage format 2 [1, 2, 3] |
| LS | `0001 0008 0001 000E 0001 0001 0002 0001 0004 0005 0002 0003` | LigatureSubst 1, coverage [2], ligature 5 from 2 + 3 |
| CC3 | `0003 0001 000E 0001 0014 0000 0000 0001 0001 0001 0001 0001 0003` | ChainedSequenceContext 3: backtrack [1], input [3] |
| CX3 | `0003 0002 0000 000A 0010 0001 0001 0001 0001 0001 0002` | SequenceContext 3: input [1], [2] |
| E1x | `0001 0001 0000 0008 0001 0006 0003 0001 0001 0001` | Extension to type 1: SingleSubst 1, coverage [1] |
| E2x | `0001 0001 0000 0008 0002 0008 0001 0007 0001 0001 0002` | Extension to type 1: SingleSubst 2, coverage [2] |
| E3x | `0001 0004 0000 0008`, then LS | Extension to type 4 |
| SP1 | `0001 0008 0004 FFF6 0001 0001 0002` | SinglePos 1, X_ADVANCE −10, coverage [2] |
| MB | `0001 000C 0012 0001 0018 0024 0001 0001 0003 0001 0001 0001 0001 0000 0006 0001 0000 0000 0001 0004 0001 0064 01F4` | MarkBasePos 1: mark coverage [3], base coverage [1] |

**G**, GSUB 1.0 written by `layout_builder.zig` in this order: header, ScriptList, each Script followed by its default LangSys and its LangSys tables, FeatureList, LookupList, each Lookup followed by its subtables, then the Feature tables.
The builder returns the position of every named field below.

| Script | Default LangSys | LangSys records |
| --- | --- | --- |
| `DFLT` | required none, features [0] | `ZZZ `: required none, [0, 6] |
| `arab` | required 5, features [1, 0] | `URD `: required none, [1, 4] |
| `latn` | NULL | `DEU `: required none, [2, 6]; `TRK `: required none, [3] |

Features: 0 `ccmp` [0]; 1 `init` [2, 1]; 2 `liga` [3]; 3 `liga` [4]; 4 `locl` [5]; 5 `rlig` [6, 2]; 6 `smcp` [7].

| Lookup | Type | Flag | Mark filtering set | Subtables |
| --- | --- | --- | --- | --- |
| L0 | 1 | `0x0000` | none | SS1, SS2 |
| L1 | 4 | `0x0008` | none | LS |
| L2 | 6 | `0x0010` | 1 | CC3 |
| L3 | 7 | `0x0200` | none | E1x, E2x |
| L4 | 5 | `0x0000` | none | CX3 |
| L5 | 9 | `0x0000` | none | SS1 |
| L6 | 1 | `0x0000` | none | `0003 0006 0000 0001 0000` |
| L7 | 7 | `0x0000` | none | `0001 0007 0000 0008`, then SS1 |
| L8 | 7 | `0x0000` | none | E1x, E3x |
| L9 | 7 | `0x0000` | none | `0001 000A 0000 0008`, then SS1 |
| L10 | 7 | `0x0000` | none | `0002 0001 0000 0008`, then SS1 |
| L11 | 1 | `0x00E0` | none | SS1 |
| L12 | 1 | `0xFF1F` | 0 | SS1 |

**G11** is G as version 1.1, with a 14-byte header whose FeatureVariations offset names 8 bytes `0001 0000 0000 0000` appended at the end.

**P**, GPOS 1.0 from the same builder:

- Script `DFLT`, with a default LangSys that has required none and features [0, 1], and no LangSys records.
- Features: 0 `kern` [0, 2]; 1 `mark` [1].
- Lookups:
  - P0: type 1 [SP1].
  - P1: type 4 [MB].
  - P2: type 9 [`0001 0001 0000 0008` + SP1].
  - P3: type 10 [SP1].
  - P4: type 8 [CC3].
  - P5: type 2 [`0003 0000`].
  - P6: type 9 [`0001 0009 0000 0008` + SP1].
  - P7: type 9 [`0001 0004 0000 0008` + MB].
  - P8: type 0 [SP1].

**T_MFS** is a GSUB with script `DFLT` (default LangSys, no features), no features, and one lookup, so the table ends with `0001 0010 0000`. The lookup has flag `0x0010` and no subtables or `markFilteringSet` field.

**H(N)** is a GSUB with this layout:

- Header `0001 0000 000A`, then the FeatureList offset 28 + 2N and the LookupList offset 36 + 2N.
- ScriptList `0001 44464C54 0008`, then Script `0004 0000`.
- A default LangSys `0000 FFFF`, then N as a uint16, then N copies of `0000`.
- FeatureList `0001 6C696761 0012`.
- LookupList `0001 0004 0001 0000 0000`.
- The Feature table `0000`, then N as a uint16, then N copies of `0000`.

For N = 30000, the LangSys spans bytes 22 to 60028, the FeatureList starts at 60028, the LookupList at 60036, and the Feature table at FeatureList + 18. Every 16-bit offset fits.

**F_GDEF**, GDEF 1.2, 110 bytes:

| Bytes | Content |
| --- | --- |
| 0-13 | `0001 0002 000E 0000 0042 0024 002C` |
| 14-35 | GlyphClassDef `0002 0003 0001 0001 0001 0002 0002 0002 0003 0003 0003` |
| 36-43 | MarkAttachClassDef `0001 0003 0001 0002` |
| 44-65 | MarkGlyphSets `0001 0002 0000 000C 0000 0012 0001 0001 0003 0001 0000` |
| 66-109 | LigCaretList `0006 0001 000C 0001 0001 0002 0003 0008 000C 0010 0001 025B 0002 000D 0003 04B6 0006 000C 0011 0002 1111 2200` |

The carets are `gdef` Examples 4 (603), 5 (point 13), and 6 (1206 with its Device table).

**F_GDEF4**, GDEF 1.0, 50 bytes: `0001 0000 0000 0000 000C 0000`, then the `gdef` Example 4 bytes `0008 0002 0010 0014 0001 0002 009F 00A5 0001 000E 0002 0006 000E 0001 025B 0001 025B 0001 04B6`.

**F_GDEF2**, GDEF 1.0, 40 bytes: `0001 0000 000C 0000 0000 0000`, then the `gdef` Example 2 bytes `0002 0004 0024 0024 0001 009F 009F 0002 0058 0058 0003 018F 018F 0004`.

### Cases

1. Coverage blobs:
   - CV1, `chapter2` Example 5, `0001 0005 0038 003B 0041 0042 004A`: format 1 and `glyphCount` 5. The iterator gives 0x38, 0x3B, 0x41, 0x42, 0x4A. `index` gives 0 to 4 for those glyphs and null for 0x00, 0x37, 0x39, and 0x4B.
   - CV2, Example 6, `0002 0001 004E 0057 0000`: `glyphCount` 10, and the iterator gives 0x4E to 0x57. `index` gives 0x4E → 0, 0x53 → 5, and 0x57 → 9, and null for 0x4D and 0x58.
   - CV3, `0002 0002 0005 0007 0000 000A 000A 0003`: the iterator gives 5, 6, 7, 10. `index` gives 5 → 0, 7 → 2, and 10 → 3, and null for 4, 8, 9, and 11.
   - CV4, `0001 0000`: valid, `glyphCount` 0, an empty iterator, and `index(0)` null.
   - CV5, `0002 0001 0000 FFFF 0000`: `glyphCount` 65536. `index` gives 0 → 0, 0x8000 → 32768, and 0xFFFF → 65535.
   - CV6: the bytes `0000 0001 0001 0007` at offset 2 give [7].
2. Malformed Coverage blobs:
   - `0001 0003 0005 0005 0006` → `unsorted_records`.
   - `0001 0002 0006 0005` → `unsorted_records`.
   - `0001 0003 0005` → `count_out_of_bounds`.
   - `0002 0001 0007 0005 0000` → `invalid_range`.
   - `0002 0002 0005 0007 0000 0007 0009 0003` → `unsorted_records`.
   - `0002 0002 0005 0007 0000 000A 000A 0002` → `inconsistent_coverage_index`.
   - `0002 0001 0005 0007 0001` → `inconsistent_coverage_index`.
   - `0002 0002 0005 0007 0000` → `count_out_of_bounds`.
   - `0003 0000` → `unsupported_version` 3, and `0000 0000` → `unsupported_version` 0.
   - `0001` → `too_short`.
   - The 4-byte `0001 0000` at offset 4 → `offset_out_of_bounds`.
3. ClassDef blobs:
   - CD1, `chapter2` Example 7: `0001 0032 001A 0000 0001 0000 0001 0000 0001 0002 0001 0000 0002 0001 0001 0000 0000 0000 0002 0002 0000 0000 0001 0000 0000 0000 0000 0002 0000`. `class(0x32 + k)` for k = 0 to 25 gives 0 1 0 1 0 1 2 1 0 2 1 1 0 0 0 2 2 0 0 1 0 0 0 0 2 0. Glyphs 0x31, 0x4C, and 0xFFFF give 0.
   - CD2, Example 8: `0002 0003 0030 0031 0002 0040 0041 0003 00D2 00D3 0001`. Glyphs 0x30 and 0x31 give 2, 0x40 and 0x41 give 3, and 0xD2 and 0xD3 give 1. Glyphs 0x2F, 0x32, 0x3F, 0x42, and 0xD4 give 0.
   - CD3, `gdef` Example 7: `0002 0004 0268 026A 0001 0270 0272 0001 028C 028F 0002 0295 0295 0002`. Glyphs 0x269 and 0x271 give 1, 0x28D and 0x295 give 2, and 0x26B and 0x296 give 0.
   - CD4, `0001 FFFF 0001 0005`: 0xFFFF gives 5, and 0xFFFE gives 0.
   - CD5, `0002 0000`: valid, and every glyph gives 0.
4. Malformed ClassDef blobs:
   - The `gdef` Example 2 bytes → `unsorted_records`.
   - `0001 FFFF 0002 0001 0001` → `count_out_of_bounds`.
   - `0001 0000 0003 0001` → `count_out_of_bounds`.
   - `0002 0001 0005 0004 0001` → `invalid_range`.
   - `0002 0002 0001 0005 0001 0005 0006 0002` → `unsorted_records`.
   - `0003 0000` → `unsupported_version` 3.
   - `0001 0000` → `too_short`.
   - `0002` → `too_short`.
   - The 4-byte `0002 0000` at offset 4 → `offset_out_of_bounds`.
5. Device blobs:
   - `chapter2` Example 9, `000B 000F 0001 5540` → `unsupported_device` {11, 15, 1}.
   - `gdef` Example 6's Device, `000C 0011 0002 1111 2200` → `unsupported_device` {12, 17, 2}.
   - `000B 000F 0003 1234 5678 9A00` → `unsupported_device` {11, 15, 3}.
   - `0001 0002 8000` → `unsupported_variation_index` {outer 1, inner 2}.
   - `000B 000F 0004` → `unsupported_format` 4, and `000B 000F 0000` → `unsupported_format` 0.
6. Malformed Device blobs:
   - `000B 000F 0001` → `count_out_of_bounds`.
   - `000B 000F 0003 1234 5678` → `count_out_of_bounds`, because 5 × 8 bits need 3 words.
   - `000F 000B 0001 0000` → `invalid_range`.
   - `000B 000F` → `too_short`.
   - The 8-byte `000B 000F 0001 5540` at offset 8 → `offset_out_of_bounds`.
7. The `chapter2` script examples, in B_TT:
   - E1: three scripts, `hani`, `kana`, and `latn`. Each has `defaultLangSys()` `.absent` and `lang_sys_count` 0.
   - E1 selection: `kana`, no language, [] → `script = kana`, `lang_sys = .none`, and `lookup_count` 0. `cyrl` → `script = null`, `lang_sys = .none`.
   - E2 `script(0)`: tag `arab`, default {required null, [0, 1, 2]}, and `langSysTag(0) = "URD "` with {required 3, [0, 1, 2]}.
   - E2-a: `arab`, no language, [init, fina, medi] → `.default`, masks 0:`0x1`, 1:`0x2`, 2:`0x4`, 3:0, required null.
   - E2-b: `arab`, `URD `, [init, fina, medi] → `.requested`, required 3, masks 0:`0x1`, 1:`0x2`, 2:`0x4`, 3:`0x8000000000000000`.
   - E2-c: `arab`, `URD `, [] → masks 0, 0, 0, `0x8000000000000000`, and `lookup_count` 1.
8. E34, in B_TT:
   - `feature(0)` is `liga` [1], `feature(1)` is `liga` [0, 1], and `feature(2)` is `liga` [0, 1, 2].
   - Each of the 3 lookups is {type 4, flag `0x000C`, 1 subtable, no mark filtering set, `ignoreLigatures` and `ignoreMarks` true}. Its subtable has format 1 and coverage format 1 [2].
   - Selection `DFLT`, no language, [liga] → masks 0:`0x1`, 1:`0x1`, 2:0.
9. G structure, in B_TT:
   - `scriptCount` 3, and `script(3)` is null.
   - Each Script, default LangSys, LangSys tag, and LangSys equals the G table above. `latn`'s default is `.absent`.
   - `featureCount` 7. Each `feature(i)` tag and lookup list equals the G table above, and `feature(7)` is null.
   - `lookupCount` 13.
10. Selection on G (masks of length 13), on P, and on B_TT. Each line lists the nonzero masks, and every other mask is 0.
    - S1: `arab`, none, [ccmp, init] → script `arab`, `.default`, required 5, `lookup_count` 4, masks 0:`0x1`, 1:`0x2`, 2:`0x8000000000000002`, 6:`0x8000000000000000`.
    - S1b: `arab`, none, [ccmp, init, rlig] → masks 0:`0x1`, 1:`0x2`, 2:`0x8000000000000006`, 6:`0x8000000000000004`.
    - S2: `arab`, `URD `, [init, locl, ccmp] → `.requested`, required null, masks 1:`0x1`, 2:`0x1`, 5:`0x2`.
    - S3: `arab`, `FAR `, [ccmp, init] → `.default`, with the masks of S1.
    - S4: `cyrl`, none, [ccmp, smcp] → script `DFLT`, `.default`, masks 0:`0x1`.
    - S5: `cyrl`, `ZZZ `, [ccmp, smcp] → script `DFLT`, `.requested`, masks 0:`0x1`, 7:`0x2`.
    - S6: `latn`, none, [liga] → script `latn`, `.none`, no masks.
    - S7: `latn`, `TRK `, [liga] → masks 4:`0x1`.
    - S8: `latn`, `DEU `, [liga, smcp] → masks 3:`0x1`, 7:`0x2`.
    - S9: `latn`, `DEU `, [] → `.requested`, no masks.
    - S10: P, `latn`, none, [mark, kern] → script `DFLT`, masks 0:`0x2`, 1:`0x1`, 2:`0x2`.
    - S11: B_TT GPOS, `cyrl` → script null, `.none`. B_TT GSUB, `cyrl` → script `DFLT`, `.default`, no masks.
    - Every S1 to S11 result has `feature_variations` false.
11. Selection errors on G:
    - Masks of length 12 → `error.MasksTooShort`.
    - 64 tags → `error.TooManyFeatures`.
    - 63 copies of `ccmp` with S1's script and language → masks 0:`0x7FFFFFFFFFFFFFFF`, 2:`0x8000000000000000`, 6:`0x8000000000000000`.
12. FeatureVariations: G11, in B_TT, has `feature_variations` nonzero. S1 on G11 gives S1's masks with `feature_variations` true.
13. G lookups, in B_TT:
    - L0: type 1, flag 0, 2 subtables, mark filtering set null. Subtable 0 has format 1 and coverage format 1 [2, 3]. Subtable 1 has format 2 and coverage format 2 [1, 2, 3].
    - L1: type 4, flag `0x0008`, `ignoreMarks` true, format 1, coverage [2].
    - L2: type 6, flag `0x0010`, mark filtering set 1, format 3, coverage [3].
    - L3: type 1, extension true, flag `0x0200`, `markAttachmentClass` 2. Subtable 0 has format 1 and coverage [1]. Subtable 1 has format 2 and coverage [2].
    - L4: type 5, format 3, coverage [1].
    - L5 → `unsupported_type` 9.
    - L6 is valid with type 1, and `subtable(0)` → `unsupported_format` 3.
    - L7 → `rejected` `nested_extension`.
    - L8 → `rejected` `mixed_lookup_types`.
    - L9 → `unsupported_type` 10.
    - L10 → `unsupported_extension_format` 2.
    - L11: flag `0x00E0`. All five predicates are false, and `markAttachmentClass` is 0.
    - L12: flag `0xFF1F`. All five predicates are true, `markAttachmentClass` is 255, and the mark filtering set is 0.
    - `lookup(13)` is null, and `L0.subtable(2)` is null.
14. P lookups, in B_TT:
    - P0: type 1, format 1, coverage [2].
    - P1: type 4, format 1, coverage [3], which is the mark coverage.
    - P2: type 1, extension true, coverage [2].
    - P3 → `unsupported_type` 10.
    - P4: type 8, format 3, coverage [3].
    - P5 is valid with type 2, and `subtable(0)` → `unsupported_format` 3.
    - P6 → `nested_extension`.
    - P7: type 4, extension true, coverage [3].
    - P8 → `unsupported_type` 0.
15. Malformed selection. Each row edits one field of G. Each selection uses masks of length 16.
    - X1: arab default `featureIndices[0]` = 7 → S1 `rejected` `index_out_of_range`.
    - X2: arab default `requiredFeatureIndex` = 7 → S1 `index_out_of_range`.
    - X3: Feature 1 `lookupListIndices[0]` = 13 → S1 `index_out_of_range`, and `feature(1)` `index_out_of_range`.
    - X4: latn records written as [`TRK `, `DEU `] → `script(2)` and S7 `unsorted_records`.
    - X5: latn records [`DEU `, `DEU `] → `unsorted_records`.
    - X6: DFLT `defaultLangSysOffset` = 0 → `script(0)`, S4, and S5 `missing_default_lang_sys`.
    - X7: arab default `featureIndexCount` = `0xFFFF` → S1 `count_out_of_bounds`.
    - X8: Feature 1 `lookupIndexCount` = `0xFFFF` → S1 and `feature(1)` `count_out_of_bounds`.
    - X9: arab `langSysCount` = `0xFFFF` → `script(1)` and S1 `count_out_of_bounds`.
    - X10: arab `langSysRecords[0].langSysOffset` = `0xFFFF` → `script(1)` and S2 `offset_out_of_bounds`.
    - X11: FeatureRecord 1 `featureOffset` = 0 → `feature(1)` and S1 `null_offset`.
    - X12: ScriptRecord 1 `scriptOffset` = 0 → `script(1)` and S1 `null_offset`.
16. Malformed lookups. Each row edits G, unless it names T_MFS.
    - Z1: L0 `subTableCount` = `0xFFFF` → `count_out_of_bounds`.
    - Z2: T_MFS `lookup(0)` → `too_short`.
    - Z3: L0 `subtableOffsets[0]` = 0 → `null_offset`.
    - Z4: L0 `subtableOffsets[0]` = `0xFFFF` → `offset_out_of_bounds`.
    - Z5: L3 E1x `extensionOffset` = `0x00010000` → `offset_out_of_bounds`.
    - Z6: SS1 in L0, bytes 2-3 = `0xFFFF` → L0 is valid, and `subtable(0).coverage()` is `offset_out_of_bounds`. Bytes 2-3 = 0 → `null_offset`.
    - Z7: CC3 in L2, bytes 6-7 = 0 → `coverage()` `count_out_of_bounds`.
    - Z8: CX3 in L4, bytes 2-3 = 0 → `coverage()` `count_out_of_bounds`.
    - Z9: L0 `subtableOffsets[0]` set to name the last byte of G → L0 is valid, and `subtable(0)` is `too_short`.
    - Z10: LookupList `lookupOffsets[0]` = 0 → `lookup(0)` `null_offset`.
17. Work limit:
    - H(100), `DFLT`, [liga]: with `max_work` 10,100 → valid, mask 0:`0x1`, and `work` 10,100. With 10,099 → `limit_exceeded` and `work` 10,099.
    - S1 on G with `max_work` 7 → valid. With 6 → `limit_exceeded`.
    - H(30000) with the default limits → `limit_exceeded`, and `work` equals 1,048,576.
    - The H(100) and S1 assertions run before the H(30000) selection.
18. F_GDEF, in B_TT:
    - `glyphClasses` gives glyphs 0 to 3 → 0, 1, 2, 3, and glyph `0xFFFF` → 0.
    - `markAttachClasses` gives glyph 3 → 2 and glyphs 0 to 2 → 0.
    - `markGlyphSets` has count 2. `set(0)` is format 1 [3]. `set(1)` is valid and empty. `set(2)` is null.
    - `carets(2)` is valid with `caret_count` 3. `caret(0)` = `coordinate` 603, `caret(1)` = `point` 13, and `caret(2)` = `coordinate_device` {1206, `unsupported_device` {12, 17, 2}}. `caret(3)` is null.
    - `carets(1)` is `not_covered`.
    - B_TT's own GDEF 1.0 gives `.absent` for all four methods.
19. F_GDEF4, in B_TT: `carets(0x9F)` has 1 caret, `coordinate` 603. `carets(0xA5)` has 2 carets, `coordinate` 603 and `coordinate` 1206. `carets(0xA0)` is `not_covered`.
20. Malformed GDEF. Each row edits F_GDEF, unless it names F_GDEF2.
    - Y1: F_GDEF2 `glyphClasses` → `unsorted_records`, and the font still parses.
    - Y2: bytes 44-45 = 2 → `markGlyphSets` `unsupported_version` 2.
    - Y3: bytes 46-47 = `0x0100` → `count_out_of_bounds`.
    - Y4: bytes 48-51 = `0x00000100` → `set(0)` `offset_out_of_bounds`.
    - Y5: bytes 86-87 = 4 → `caret(0)` `unsupported_format` 4.
    - Y6: bytes 78-79 = `0x0100` → `carets(2)` `count_out_of_bounds`.
    - Y7: bytes 100-101 = `0x0011` and 102-103 = `0x000C` → `caret(2)` device `rejected` `invalid_range`.
    - Y8: bytes 104-105 = `0x8000` → `caret(2)` device `unsupported_variation_index` {12, 17}.
    - Y9: bytes 68-69 = 0 → `carets(2)` `index_out_of_range`.
    - Y10: bytes 14-15 = 3 → `glyphClasses` `unsupported_version` 3.
    - Y11: bytes 48-51 = 0 → `set(0)` `null_offset`.
21. Robustness. For each table T of G, P, and F_GDEF in B_TT:
    - Each prefix length L from 0 to len(T) − 1 is applied by setting T's directory length to L in a copy of the built font.
    - Each byte of T is set in turn to `00`, `FF`, and its value XOR `80`.
    - After each change, the font parses under `.report`, and `walk` runs twice.
    - `walk` visits every script, LangSys, feature, lookup, subtable, and primary coverage, and every GDEF method above. It calls `class(g)` on both ClassDefs and `carets(g)` for g from 0 to 8, and `index(g)` for g from 0 to 8 on every opened Coverage, besides its iterator. It runs selections R1 (`arab`, none, [ccmp, init, rlig, liga]), R2 (`latn`, `TRK `, [liga]), and R3 (`cyrl`, `ZZZ `, [ccmp, smcp]) with masks of length `lookupCount`.
    - Both walks give equal Wyhash digests of all results. Nothing panics or leaks.
22. Bytes changed after parse. Take handles from pristine G and F_GDEF in B_TT: the Layout, `script(1)`, its default LangSys, `feature(1)`, `lookup(3)` and its `subtable(0)` and Coverage, the Gdef, its ClassDefs, MarkGlyphSets, LigCaretList, and LigGlyph.
    - Set each byte of the table to `FF` in turn, and also once all bytes together.
    - After each change, call every method of every handle, `index(g)` for g from 0 to 8, the whole iterator, `class(g)` for g from 0 to 8, and S1 with masks of length 13.
    - Each `index` is null or below the captured `glyphCount`. Each iterator yields at most `glyphCount` values. Nothing panics or reads outside the font.
    - Restore each byte afterward.
23. Stack: case 23 first runs H(100) with `max_work` 10,099 on a thread spawned with a 256 KiB stack in the Debug test build, and requires `limit_exceeded`. It then runs case 21's `walk` of pristine G, P, and F_GDEF and the H(30000) selection on that thread. They give the case 17 and case 21 outcomes. No mutation control targets this property. The reviewers read the source to confirm that no function recurses.
24. Allocation: a comptime check visits every public function of `font.layout` and of each public struct type that it declares. No parameter type equals `std.mem.Allocator`, `?std.mem.Allocator`, `*std.mem.Allocator`, or `*const std.mem.Allocator`. The check reflects over types and scans no source text.
25. Fixtures, against the version 2 expectation files:
    - For each fixture and each of `gsub` and `gpos`, compare against the dump: the version, `feature_variations`, and each script's tag, default LangSys, LangSys tags, and LangSys contents.
    - Also compare each feature's tag and lookup list.
    - For each lookup, compare the stored type, flag, mark filtering set, and subtable count. Each subtable's `extension`, effective type, and format must equal the dump.
    - Each coverage format and iterator sequence must equal the dump. `index(glyphs[i]) == i` for each listed glyph.
    - Every lookup and subtable must be `valid`.
    - Dumped lookup counts must equal 48 and 16 (`noto-sans`), 41 and 22 (`noto-sans-arabic`), 171 and 28 (`noto-sans-devanagari`), and 11 and 6 (`noto-sans-cjk-jp-subset`), for GSUB and GPOS. This guards against an empty comparison.
    - Selection cross-check: for each script and each of its LangSys tables, request the distinct tags of that LangSys's features in first-occurrence order, with the record's tag as the language, or none for the default. The test computes the expected masks from the dump under the selection rules and compares every mask. Requests use default limits.
    - For GDEF: the version and `item_var_store` must equal the dump. `glyphClasses` and `markAttachClasses` must give the dumped format, the dumped class for each listed glyph, and 0 for every other glyph below `numGlyphs`. Each mark glyph set must equal its dumped coverage. Each `lig_caret_list` entry's carets must equal the dump, with format 3 devices compared as `unsupported_device` {start_size, end_size, delta_format}, or as `unsupported_variation_index` {start_size, end_size} for `0x8000` [INFERENCE: fontTools stores the VariationIndex outer and inner indices in `StartSize` and `EndSize`]. For each glyph below `numGlyphs` that `lig_caret_list` does not list, `carets(glyph)` is `not_covered`.
    - The CJK subset's `gdef` is null, and `font.gdef()` is `.absent`.

### Amended FP-0013 cases

- Case 13 requires `version` 2. For `gsub` and `gpos`, it requires exactly the 5 keys above and compares `version`, `scripts[i].tag` with `scriptTag(i)`, `features[i].tag` with `featureTag(i)`, and `lookups.len` with `lookupCount()`. For `gdef`, it requires exactly the 6 keys above and compares `version`. Case 25 checks everything else.
- Case 16 compares each of the seven `Gdef` header fields with its unchanged value, instead of a struct literal, because `Gdef` gains `table`.
- Neither amended case is claimed to fail at the base on its own.

## Base failures

Cases 1 to 25 reference `font.layout`, `font.Reader`, or methods that the base lacks.
`src/font/opentype.zig:14` declares `layout` without `pub`, and `opentype.zig:18` declares `Reader` without `pub`.
`src/font/layout.zig:11-46` and `113-124` define no `script`, `feature`, `lookup`, `selectLookups`, Coverage, ClassDef, Device, or GDEF method.
`src/font/tables.zig:11-19` lack the seven new `Defect` members.
So `tests-before.log` must fail to compile the `tests/text` artifact, with errors that name `layout`, `Reader`, or a missing member.
No case fails by name, as in the FP-0108 and FP-0119 before runs, and no stub stands in for named failures.
A runtime crash is a failed attempt, not a before log.

## Mutation controls

Record each control as a `.diff`.
Apply it with `git apply`, run the tests, and reverse it with `git apply -R`.
Record file hashes before, during, and after each control.
Record a crash separately from a failed assertion.

| Control | Mutation | Case that fails, and why |
| --- | --- | --- |
| M1 | Coverage format 2 `index` ignores `startCoverageIndex` | Case 1: CV3 `index(10)` becomes 0 |
| M2 | Coverage format 1 binary search excludes the last element | Case 1: CV1 `index(0x4A)` becomes null |
| M3 | Coverage format 1 accepts equal adjacent glyphs | Case 2: `0001 0003 0005 0005 0006` becomes valid |
| M4 | ClassDef format 1 uses glyph − start + 1 | Case 3: CD1 `class(0x33)` becomes 0 |
| M5 | ClassDef format 2 accepts unsorted records | Case 4: the `gdef` Example 2 bytes become valid |
| M6 | `deltaFormat` `0x8000` is reported as `unsupported_device` | Case 5: the VariationIndex row |
| M7 | No DFLT fallback | Case 10: S4 gives script null |
| M8 | An absent language gives `.none` instead of the default | Case 10: S3 |
| M9 | Default LangSys features are merged into a requested LangSys | Case 10: S2 gains lookup 0 with `0x4` and lookup 6 |
| M10 | The required feature is skipped | Case 7: E2-b and E2-c; case 10: S1 |
| M11 | DFLT fallback also applies when the script record lacks the language and a default | Case 10: S6 gives script `DFLT` |
| M12 | The lookup index range check is removed | Case 15: X3 becomes valid; masks of length 16 keep that write in bounds. M12 removes both the Feature-open check and the point-of-use check. A crash in case 21 or 22 is recorded separately; the named failure is case 15 X3 |
| M13 | `markFilteringSet` is not read | Case 13: L2 gives null |
| M14 | Extension subtables are not unwrapped | Case 13: L3 type 7; case 14: P2 |
| M15 | Mixed extension types are accepted | Case 13: L8 becomes valid |
| M16 | The lookup flag's high byte is dropped | Case 13: L3 flag `0x0000` and class 0 |
| M17 | GPOS types 4, 5, and 6 read their coverage at +4 | Case 14: P1 gives [1] |
| M18 | `limit_exceeded` is returned when `work` reaches the limit after an increment | Case 17: H(100) with 10,100 and S1 with 7 |
| M19 | The work limit is removed | Case 17: H(100) with 10,099 becomes valid, before H(30000) runs; case 23: its first H(100) assertion fails before H(30000) runs |
| M20 | `feature_variations` is never set | Case 12 |
| M21 | CaretValue format 3 drops its device | Case 18: `caret(2)` |
| M22 | MarkGlyphSets offsets are read as Offset16 | Case 18: `set(0)` gives [0, 12] |

## Stop rules

- If `digests-before.log` shows a font digest that differs from `specs/snapshots/opentype-fixtures.json`, stop before any fontTools run and report both values.
- If case 25 finds any difference, stop. Report the font, the table, the JSON path, and both values. Never edit a fixture, an expectation file, or the dump code to pass a case.
- If a fixture lookup or subtable is `rejected` or unsupported, or a fixture LangSys names more than 63 distinct tags, stop and report it.
- If `font_expectations.py` exits with status 1, stop and report its messages.
- If `font-expectations --check` reports any difference after the write run, stop, because the dump is not reproducible.
- If the `tests/text` run step grows by more than 10 seconds over the base on the development host, stop and report both durations.
- If any expectation here contradicts the cited text, apart from the three example inconsistencies recorded above, stop and report it. Never change an expectation silently.

## Criterion mapping

| FP-0111 criterion | Cases and evidence |
| --- | --- |
| 1. Parse Coverage, ClassDef, LangSys, feature index lists, Lookup tables, flags, and mark filtering sets with checked offsets and bounded work | 1 to 4, 7 to 9, 13, 14, 17; M1 to M5, M13, M14, M16 to M19 |
| 2. Select lookups with DFLT and default LangSys fallback | 7, 8, 10, 11, 25 (selection cross-check); M7 to M11 |
| 3. Parse GDEF glyph classes, mark attachment classes, mark glyph sets, and ligature carets | 3, 18, 19, 25; M21, M22 |
| 4. Report FeatureVariations, unknown types and formats, and Device and VariationIndex data as unsupported | 2, 4 to 6, 12 to 14, 18, 20; M6, M20, M21 |
| 5. Reject malformed subtables without a panic, unbounded allocation, or native recursion | 2, 4, 6, 15, 16, 17, 20 to 24; M3, M5, M12, M15, M18, M19 |
| 6. Check the fixtures against the fontTools dumps | 25, amended case 13, `digests-before.log`, `font-expectations-write.log`, `font-expectations-check.log`, and `digests.log` |

## Remaining obligations

These obligations belong to other tasks:

- `FP-0112` applies GSUB lookups and their nested lookups, the lookup flags, mark filtering sets, and GDEF classes. It must open each Coverage and ClassDef once per run, or bound total validation work, because each open costs time linear in that structure.
- `FP-0113` applies GPOS lookups and reports Device, VariationIndex, and contour-point anchors in ValueRecords and Anchors.
- `FP-0118` places carets from `LigCaretList`, including the policy for CaretValue format 2 points.
- `FP-0114` and `FP-0115` map Unicode scripts and languages to OpenType script and language tags, including `dev2` and `deva` [INFERENCE: their criteria imply this mapping].
- `FP-0059` owns FeatureVariations evaluation and the GDEF item variation store, under its criterion "Evaluate GSUB and GPOS FeatureVariations condition sets for the selected instance, and apply the GDEF item variation store through VariationIndex tables in GDEF and GPOS, replacing the FP-0111 and FP-0113 unsupported reports." (`engineering/plan.json:2963` at `b9217fe`).
- `FP-0058` compares the strictness choices with web-font practice, under its criterion at `engineering/plan.json:2938` at `b9217fe`.
- FeatureParams and AttachList have no consumer. `chapter2` defines FeatureParams only for `cv01`-`cv99`, `size`, and `ss01`-`ss20`, and the `gdef` chapter says that AttachList "may be used to cache attachment point coordinates". Neither is an obligation.

The README records these observations without asserting them:

- For each fixture, the counts of lookups by type and format, of extension lookups, of lookups with each flag bit, and of coverages by format.
- The size and SHA-256 of each version 1 and version 2 expectation file.
- Whether any fixture has caret format 2 or 3, AttachList data, or a nonzero `lookupOrderOffset`.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0111/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
Never overwrite a log. Name a failed attempt with the suffix `-attempt-N`, and list it with its cause in the README.

0. Record `digests-before.log` with `sha256sum` of the four fonts, each named by path. Compare each digest with its entry in `specs/snapshots/opentype-fixtures.json`. If any digest differs, stop.
1. Change `tools/fonts/font_expectations.py`. Record `font-expectations-write.log` with `node tools/fairpane.mjs font-expectations`. It must exit with status 0, show the argument vector for each of the four fonts, and report each output as different from the committed file.
2. Record `font-expectations-check.log` with `node tools/fairpane.mjs font-expectations --check`. It must exit with status 0 and report all four files as byte-identical.
3. Record `digests.log` with `sha256sum` of the four fonts, `tools/fonts/font_expectations.py`, and the four expectation files, each named by path.
4. Write cases 1 to 25 and the amended cases. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0111-before`. It must fail to compile, as "Base failures" states.
5. In a worktree at the base commit, delete `out/fp0111-base`. Record `tests-before-duration.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0111-base`. It must exit with status 0 and show the `tests/text` run-step duration.
6. Delete `out/fp0111-after`. Record `tests-after.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0111-after`. It must exit with status 0 and show every step's duration.
7. Record `fmt.log` with `zig fmt --check build.zig src tests`.
8. Record `controller-tests-after.log` with `node --version` and `node tools/fairpane.mjs test`. Its case count must equal the base count.
9. Record `profile.log` with the `tests/text` procedure of `tools/README.md` "Profile the Zig tests", and report each FP-0111 case's duration.
10. Record `mutation.log`, and record `mutation-M1.diff` to `mutation-M22.diff`.
11. Write `engineering/evidence/FP-0111/README.md`. It gives `HEAD`, the criterion mapping, each control's result, the case 25 observations, the expectation file sizes, the time delta, and every resolved ambiguity.

The integrator then does the following:

1. Record `raw/integration-binding.log`.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0111/gates`.
3. Record an uncached `integration-tests.log`.

## Authority

The writable paths are `src`, `tests`, `tools`, `build.zig`, `specs/capabilities/text-fonts.json`, and `engineering/evidence/FP-0111/`, as `engineering/plan.json:3871` at `b9217fe` allows.
These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
`engineering/dependencies.json` stays unchanged. It already lists the dump use.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Network access occurs only if the fontTools wheel must be downloaded under `tools/README.md` "Import a file-set corpus".
The required reviewers are `fairpane-review` and `fairpane-security`. Both check the capability record update and the amended FP-0013 cases as part of this contract.

## Non-goals

This task does none of the following:

- Applying any GSUB or GPOS lookup, or parsing lookup bodies beyond the format and the primary coverage.
- Applying Device, VariationIndex, or item variation store data, or evaluating FeatureVariations conditions.
- Parsing FeatureParams, AttachList, BASE, JSTF, MATH, or `kern`.
- Mapping Unicode scripts or BCP 47 languages to OpenType tags.
- Changing `parse`, the C ABI, `include`, `api`, `tools/fileset.mjs`, or any gate.
- Making performance claims.

## Errata

Review 1 (`reviews/review-1-accept.json`) found two errors in this contract's text; neither changes a test, an expectation, or a criterion.

1. The M22 row's expected value is wrong. Read as Offset16, the first MarkGlyphSets offset is `0x0000`, so `set(0)` is rejected with `null_offset` (`raw/mutation.log` lines 5615-5636), not `[0, 12]`. Case 18 still fails at `set(0)`, so M22 still fails its named case, as README item 11 reports.
2. The fontTools 4.66.1 line citations in "Sources" count another source tree. In the installed files, which `raw/fonttools-lines.log` prints, `otBase.py` lines 989 and 1221-1222 are 1003 and 1237, and `otTables.py` lines 927, 950, 1182, 1250, 1344, 1430, and 1498 are 947, 970, 1207, 1276, 1371, 1458, and 1527. The cited behavior is the same at those lines.
