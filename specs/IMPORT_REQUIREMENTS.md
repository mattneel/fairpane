# Unicode, CLDR, and font-fixture import requirements

## Status

This file states requirements for later imports.
Task FP-0003 imports no font, Unicode data, or CLDR data.
The `unicode`, `cldr`, and `opentype-fixtures` entries in `specs/corpora.json` remain `not-fetched`.
Bracketed identifiers name primary sources in `specs/sources.json`.

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

| File | Consumer | Source |
| --- | --- | --- |
| `ucd/UnicodeData.txt` | String case mapping | [S30] |
| `ucd/SpecialCasing.txt` | String case mapping, locale-insensitive entries | [S30] |
| `ucd/CaseFolding.txt` | Case-insensitive RegExp matching with the `u` or `v` flag | [S30] |
| `ucd/PropertyAliases.txt` | RegExp property names | [S30] |
| `ucd/PropertyValueAliases.txt` | RegExp property values and value aliases | [S30] |
| `ucd/DerivedCoreProperties.txt` | `ID_Start` and `ID_Continue` for identifiers | [S31], [S27] |
| `BidiTest.txt` and `BidiCharacterTest.txt` | Unicode Bidirectional Algorithm tests (UAX #9) | [S27], [S14] |
| `NormalizationTest.txt` | Unicode Normalization tests (UAX #15) | [S27] |
| `LineBreakTest.txt` | Unicode Line Breaking tests (UAX #14) | [S27] |
| `GraphemeBreakTest.txt` and `WordBreakTest.txt` | Text segmentation tests (UAX #29) | [S27] |

RegExp property escapes also need the property file for each property in the ECMAScript property tables. [S30]
The importing task locates each such file through the UAX #44 property table for the selected version. [S27]
The importing task records the directory path of each test file within the selected version.

### License terms

Unicode Data Files include all computer data files under `https://www.unicode.org/Public/`. [S26]
Unicode Data Files are subject to the Unicode License v3 unless a specific restriction or license states otherwise. [S26]
The license permits use, copying, modification, and distribution. [S25]
The copyright and permission notice must appear with every copy or in associated documentation. [S25]
An import keeps `https://www.unicode.org/license.txt` beside the data and records its digest.
A generated table carries the same notice.

## Unicode CLDR

### Version selection

1. Select a numbered release from the CLDR releases table. [S28]
2. Do not select the development version or the `main` branch. [S28]
3. Pin the release's Git tag in `https://github.com/unicode-org/cldr` and record the tag's commit ID. [S28]
4. Alternatively, pin the versioned data directory `https://unicode.org/Public/cldr/<version>/` and record each file digest. [S28]
5. Record the Unicode version that the selected release targets, as its release note states. [S28]
6. Resolve any mismatch between that Unicode version and the UCD import before qualification.
7. Apply no CLDR corrigendum unless the import records it as a separate input. [S28]

Each CLDR release is stable and never changes after publication. [S28]

### Data files

ECMA-402 does not require CLDR data, but it recommends CLDR data in several places. [S32]
Fairpane selects CLDR as its locale data source, so these requirements apply.

| File or data | Consumer | Source |
| --- | --- | --- |
| `common/validity/unit.xml` | Sanctioned unit identifiers, defined against CLDR release 38 | [S32] |
| `common/bcp47/timezone.xml` | Primary and non-primary time zone identifiers | [S32] |
| UTS #35 key and type definitions | Unicode locale extension keys and value canonicalization | [S32] |
| UTS #35 LocaleId canonicalization data | `CanonicalizeUnicodeLocaleId` | [S32] |
| UTS #35 likely subtags | `Intl.Locale` text direction and related operations | [S32] |
| UTS #35 calendar preference, time, and week data | `Intl.Locale` calendars, hour cycles, and week information | [S32] |
| Locale display strings for dates, numbers, and names | Formatters, with CLDR strings recommended for `DateTimeFormat` | [S32] |

The importing task maps each UTS #35 data category to exact files in the pinned release.

### License terms

The CLDR releases page refers to the Unicode Terms of Use for license information. [S28]
The Terms of Use classify `https://www.unicode.org/Public/cldr/` and `https://github.com/unicode-org/` content as Unicode products under the Unicode License v3. [S26]
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
A subset or other modified fixture therefore drops any Reserved Font Name or records that permission.
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

Files inside a pinned corpus snapshot, such as WPT, stay under that corpus's record.
Copying such a file out of its corpus requires the same admission rule and per-file record.

### Formats

Fixtures cover OpenType [S15] and WOFF2 [S16].
WOFF2 fixtures also exercise the Brotli decoder that WOFF2 requires. [S16]
