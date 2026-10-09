# FP-0013 evidence

## Scope

This record covers task `FP-0013`, "Establish multilingual text data and font parsing".
`CONTRACT.md` freezes its behavior, its 49 test cases, and its integrator decisions.
The `fairpane-text` worker `FP0013Text` wrote this patch in an isolated worktree whose `HEAD` is `97aa319`.
`raw/base-equivalence.log` shows that `src`, `tests`, `tools`, `build.zig`, and `specs` are identical at the contract base `28e2195` and at `97aa319`.
Nothing is committed, and the protected paths are unchanged, including `specs/corpora.json`.
The worker ran no repository gate; the integrator runs them.

Every corpus command ran with `FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, as each `RESULT` line's `environment_overrides` shows.
Every Zig command ran with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
fontTools ran from `.tools/python/fonttools-4.66.1/` inside the worktree, a virtual environment of Python 3.13.15.

## Files changed

Modified: `build.zig`, `src/root.zig`, `src/web_string.zig`, `tools/corpus.mjs`, `tools/fairpane.mjs`, `tools/selftest.mjs`, `tools/README.md`, `specs/README.md`, `specs/IMPORT_REQUIREMENTS.md`, and `specs/sources.json`.

Added source: `src/unicode/properties.zig`, `src/unicode/properties_test.zig`, `src/unicode/reference_test.zig`, `src/unicode/tables.zig` (generated), `src/font/opentype.zig`, `src/font/reader.zig`, `src/font/tables.zig`, `src/font/cmap.zig`, `src/font/cff.zig`, and `src/font/layout.zig`.

Added tests: `tests/text/root.zig`, `tests/text/sfnt_builder.zig`, `tests/text/seed.zig`, `tests/text/fixtures.zig`, `tests/text/seed_test.zig`, `tests/text/fixture_test.zig`, `tests/text/synthetic_test.zig`, `tests/text/malformed_test.zig`, `tests/text/README.md`, and the six `tests/text/seeds/*.json` seeds.

Added controller code: `tools/ucd.mjs`, `tools/ucd.test.mjs`, `tools/fileset.mjs`, `tools/fileset.test.mjs`, `tools/capabilities.mjs`, and `tools/fonts/font_expectations.py`.

Added records: `specs/snapshots/unicode.json`, `specs/snapshots/opentype-fixtures.json`, `specs/applicability/unicode.json`, `specs/applicability/opentype-fixtures.json`, and `specs/capabilities/text-fonts.json`.

Imported upstream bytes, unedited:

- `src/unicode/ucd/`: the eight UCD files and `license.txt`, with `.gitattributes` containing `* -text`.
- `tests/text/fonts/`: `noto-sans/`, `noto-sans-arabic/`, and `noto-sans-devanagari/`, each with its font and `OFL.txt`, and `noto-sans-cjk-jp-subset/LICENSE`, with `.gitattributes` containing `* -text`.

Derived and generated: `tests/text/fonts/noto-sans-cjk-jp-subset/cjk-subset.otf` and the four `tests/text/fonts/*/*.expect.json` files.

## Proposed `specs/corpora.json` values

`inventory_sha256` for a file-set corpus is the SHA-256 of the record's source listing, one `<sha256>\t<size>\t<source id>\n` line per source in record order.
`tools/fileset.mjs` (`fileSetPinProblems`) compares exactly these fields, and `raw/proposed-pins.log` computed them from the records.

Apply these values to the `unicode` entry.

```json
{
  "revision": "18.0.0",
  "license_record": "specs/snapshots/unicode.json",
  "inventory_sha256": "2511e5384857e35883ec38bd8c0d225d1ea7591f6ee6ba6347c572f6b47a59d7",
  "local_path": "<corpora-root>/unicode/sources",
  "status": "pinned"
}
```

Apply these values to the `opentype-fixtures` entry.

```json
{
  "revision": "fixtures-1",
  "license_record": "specs/snapshots/opentype-fixtures.json",
  "inventory_sha256": "ce84ce970775ec86b39e1045d1622f2ddc5829df0a05844fd1569595cb150e34",
  "local_path": "<corpora-root>/opentype-fixtures/sources",
  "status": "pinned"
}
```

This patch proposes no `upstream` change.
The `opentype-fixtures` record copies the current upstream, `https://learn.microsoft.com/en-us/typography/opentype/spec/`, and each source records its own URL.
If the integrator changes `upstream`, the record no longer matches, so `corpus-fetch opentype-fixtures` must run again before `corpus-verify` passes.

## Imported sources

| Source | Size | SHA-256 | Release and commit | Check |
| --- | --- | --- | --- | --- |
| `UCD.zip`, Unicode 18.0.0 | 5657953 | `7b3e5555…a66a0d8` | 18.0.0 | 71 file members, inventory `37761bcf…8dd8b2f4`; no published digest, so trusted on first use |
| `license.txt` | 1995 | `e7a93b00…2bc53d96` | Unicode License v3 | Beside the data and reproduced in `tables.zig`; no published digest, so trusted on first use |
| `NotoSans-v2.015.zip` | 117491253 | `0c34df07…89b958f5` (no published digest) | `NotoSans-v2.015`, peeled commit `c4a321e123e4d4ff315f57f4e0adf294fe3a95be` | Size pin and tag commit matched; the tag commit does not bind the release asset, so the bytes were trusted on first use |
| `NotoSansArabic-v2.013.zip` | 18777381 | `1301acea…da7154f1` | `NotoSansArabic-v2.013`, peeled commit `1b2b7e5c6ce3ab4d50681c854892325530084c35` | Size, published GitHub digest, and tag commit matched |
| `NotoSansDevanagari-v2.007.zip` | 18449254 | `820c7da4…f469b1` | `NotoSansDevanagari-v2.007`, peeled commit `e123d230c160ebe949d731cc19017cdb354180d1` | Size, published GitHub digest, and tag commit matched |
| `NotoSansCJKjp-Regular.otf` at `Sans2.004` | 16467736 | `68a3fc98…7f375b5` | `Sans2.004`, lightweight tag at `523d033d6cb47f4a80c58a35753646f5c3608a78` | Size and Git blob `f56224957fb13a81b4c14bac34f2f058a017f9fb` matched |
| noto-cjk `LICENSE` at `Sans2.004` | 4301 | `6a73f954…5efe2bf2` | Same tag | Size and Git blob `d952d62c065f3f35fb83a173496e90b21525aef3` matched |

`specs/snapshots/unicode.json` and `specs/snapshots/opentype-fixtures.json` hold the full digests of every source, inventory, selected file, and derived file.
The UCD files and the `noto-sans` archive were trusted on first use: TLS and, for `noto-sans`, a size pin were their only authentication at the first fetch.
The `published_url` comparison for the UCD files is same-origin with `UCD.zip`, so it checks consistency, not independent authenticity.
Every later fetch compares each source with the SHA-256 in the existing record before it parses it, and the `specs/corpora.json` pins, applied in commit `67935cc`, check the source listing independently of that record.
ADR 0003 said that only `wpt` and `test262` had fetch rules; the integrator amended it to point at the file-set kind that `specs/README.md` now describes, as "Integration" below records.
`raw/corpus-fetch-unicode.log` also shows that each `published_url` under `https://www.unicode.org/Public/18.0.0/ucd/` served bytes equal to its `UCD.zip` member.

## Observed stop-rule values

Every inferred value held, except the Reserved Font Name statement in name ID 0, which the contract does not list as a stop rule.

| Inference | Observed | Evidence |
| --- | --- | --- |
| UCD member paths | All eight members exist at the contract paths | `raw/corpus-fetch-unicode.log` |
| Line 1 of each UCD file names `-18.0.0.txt` | Holds for all eight | Controller case 3 in `raw/controller-tests-after.log` |
| Noto zip member paths | `NotoSans/unhinted/ttf/NotoSans-Regular.ttf`, `NotoSansArabic/unhinted/ttf/NotoSansArabic-Regular.ttf`, `NotoSansDevanagari/unhinted/ttf/NotoSansDevanagari-Regular.ttf`, and a top-level `OFL.txt` in each | `raw/corpus-fetch-opentype-fixtures.log` |
| Release sizes and published digests | All five pinned sizes, both GitHub digests, and both Git blob IDs matched | Same log |
| Tag commits | The three Noto tags are annotated, and their peeled commits equal the contract commits | Same log |
| U+20BB7 in the CJK source | The subset maps U+20BB7, and case 11 passes | `raw/tests-after.log`, `cjk-subset.expect.json` |
| Coverage claims of all six seeds | Hold; case 11 passes | `raw/tests-after.log` |
| Seed property values | Equal `unicode.lookup` for every seed code point; case 10 passes | `raw/tests-after.log` |
| `@missing` defaults of case 6 | Hold | `raw/tests-after.log` |
| Font sizes | Noto Sans 431364, Noto Sans Arabic 142140, Noto Sans Devanagari 184228 bytes | `specs/snapshots/opentype-fixtures.json` |
| OFL copyright lines | `Copyright 2022 The Noto Project Authors (https://github.com/notofonts/<repository>)`; no Reserved Font Name | Same record |
| CJK name ID 0 | `© 2014-2021 Adobe (http://www.adobe.com/).`, which states no Reserved Font Name | `raw/corpus-derive-opentype-fixtures.log` |
| Subset determinism | Both runs wrote 9564 bytes with SHA-256 `3f435bdd8198e124e9cbbbad75fa1fb4156dac25ba163d0d1386e3afb682a83c` | `raw/cjk-subset-1.log`, `raw/cjk-subset-2.log` |
| `unicode` applicability | 71 discovered, 8 selected, 63 unclassified; `.` 45, `auxiliary` 11, `emoji` 3, `extracted` 12 | `specs/applicability/unicode.json` |
| `opentype-fixtures` applicability | 741 discovered, 4 selected, 737 unclassified; `noto-sans` 370, `noto-sans-arabic` 185, `noto-sans-devanagari` 185, `noto-cjk-otf` 1 | `specs/applicability/opentype-fixtures.json` |

The contract expected name ID 0 to name `Source` as a Reserved Font Name.
The observed text names none, so the derived entry records `reserved_font_names` as `[]`, as the behavior section requires.
The entry's `rfn_resolution` keeps the integrator's position that `Source` is treated as applying.
The subset carries no name record and no file name containing `Source`, and its CFF Name INDEX is `NotoSansCJKjp-Regular`.
The integrator should confirm that resolution.

## Evidence logs

Every log is under `raw/`.
Each `RESULT` line records the executable, arguments, working directory, start time, exit status, and environment overrides.

| Log | Runs and exit statuses |
| --- | --- |
| `tests-before.log` | Two runs of `zig build test --summary all --cache-dir out/fp0013-cache-before` before any implementation, both exit 1. The first, at 04:58:17Z, failed to compile on the missing `src/font/opentype.zig` and `src/unicode/properties.zig` and on two test-code errors, `**` and a shadowed name. The second, at 04:58:44Z, after those test-code fixes, failed only on the two missing modules. |
| `controller-tests-before.log` | `node tools/fairpane.mjs test` before the controller implementation, exit 1 on the missing `tools/ucd.mjs`. |
| `corpus-fetch-unicode.log` | `corpus-fetch unicode`, exit 0. |
| `fonttools-install.log` | `curl.exe` download of the recorded wheel, `sha256sum --check` (`OK`), `python -m venv`, `pip install --no-index --no-deps`, and an import check printing `4.66.1 3.13.15`; all exit 0. |
| `corpus-fetch-opentype-fixtures.log` | `corpus-fetch opentype-fixtures`, exit 0. |
| `cjk-subset-1.log`, `cjk-subset-2.log` | The frozen fontTools argument vector to `out/cjk-subset-1.otf` and `out/cjk-subset-2.otf`, each followed by `sha256sum`; all exit 0 with equal digests. |
| `corpus-derive-opentype-fixtures.log` | Two `corpus-derive opentype-fixtures` runs, exit 0. The first wrote the subset and its record; the second, after the `rfn_resolution` text changed, reproduced the same bytes and rewrote the record. |
| `font-expectations.log` | Four `tools/fonts/font_expectations.py` runs, one per fixture, exit 0. |
| `corpus-applicability-unicode.log`, `corpus-applicability-opentype-fixtures.log` | Exit 0. |
| `corpus-verify-unicode.log` | Two runs. The first exited 1 with `incomplete`, because it ran before `specs/applicability/opentype-fixtures.json` existed. The second exited 0 with `pass`. |
| `corpus-verify-opentype-fixtures.log` | Exit 0 with `pass`. |
| `ucd-generate.log`, `ucd-check.log` | Exit 0; `written`, then `pass`. |
| `mutation-directory-order.log` | Two runs of the mutation control, both exit 1 with only case 23 failing. The second run, against the final parser, matches `mutation-directory-order.diff`. |
| `tests-after.log` | Two uncached runs of `zig build test --summary all --cache-dir out/fp0013-cache-after`, both exit 0. The final run passed 142 of 142 tests: 109 in the library module and 33 in `tests/text`. |
| `controller-tests-after.log` | `node tools/fairpane.mjs test`, exit 1: 160 of 161 pass, including all 13 FP-0013 controller cases; the failure is unrelated, as described below. |
| `case-inventory.log` | Lists every `FP-0013 case N:` test name by file; all 49 cases exist; exit 0. |
| `proposed-pins.log` | Validates both records and computes the proposed pins; exit 0. |
| `base-equivalence.log` | Shows an empty diff of `src`, `tests`, `tools`, `build.zig`, and `specs` from `28e2195` to `HEAD` `97aa319`; exit 0. |
| `unrelated-workflow-check.log` | Shows that the controller failure comes from a pre-existing uncommitted change, as described below. |

### Unrelated controller failure

The worktree held an uncommitted 19-line change to `tools/workflow-check.mjs` before this task started; this patch does not touch that file.
With that change, controller test 66, `FP-0033 12`, fails.
`raw/unrelated-workflow-check.log` records `git diff --stat HEAD -- tools/workflow-check.mjs`, the FP-0033 cases passing 19 of 19 against the `HEAD` version of the file, and failing 1 of 19 against the worktree version.
The integrator should run `controller-test` without that change.

## Tests

`build.zig` adds a test artifact rooted at `tests/text/root.zig` that imports the library module as `fairpane`, and the `check` step compiles it.
Zig cases 3 and 5 to 40 run through `zig build test`; controller cases 1 to 4 and 41 to 49 run through `node tools/fairpane.mjs test`.
Case 3 has both parts: the controller part runs `ucd-check`, and `src/unicode/reference_test.zig` compares `lookup` with an independent parse for all 1114112 code points and seven properties.
A manual check during development changed one generated range from `Lu` to `Ll`; cases 3 and 10 both failed, and `ucd-generate` restored the table.

The mutation control in `mutation-directory-order.diff` makes the directory validator accept a tag equal to or below its predecessor.
Only case 23 failed under it.

The library module also gained a reference test for the bounded checksum path: block word sums must equal the direct checksum for every tested range.

## Ambiguities resolved

- Expectation files are named `<stem>.expect.json`, such as `NotoSans-Regular.expect.json`.
- "Every mapped glyph" means glyph 0 and every glyph that the selected cmap subtable maps; Noto Sans has 2966 such glyphs.
- The expectation `tables` list follows the font's directory order. fontTools orders its reader's tables by offset, so the script rereads the directory records with fontTools' `SFNTDirectoryEntry`.
- `gdef` gives only its version, because GDEF has no script, feature, or lookup lists.
- A source `release` is an object with `name`, `repository`, `tag`, and `commit`. `corpus-fetch` resolves each tag with `git ls-remote` and requires any frozen commit to match.
- `corpus-derive <id>` is a new controller command that writes the `derived` entry. It runs the frozen argument vector and requires the output to equal any existing fixture byte for byte. It reads the copyright from name ID 0 of the input font with a small JavaScript sfnt reader, and it takes the tool record from `engineering/dependencies.json`.
- `Font` also exposes `maxp()`, because the expectation file compares the `maxp` raw fields.
- `OS/2` groups the version-dependent fields as `typo`, `v1`, `v2`, and `v5`; `typo` holds the typographic and Windows metrics and is null for a version 0 table shorter than 78 bytes.
- `name` records must be sorted in nondecreasing order of platform, encoding, language, and name ID; equal adjacent records are accepted.
- GSUB and GPOS script tags must strictly ascend.
- A nonnull list offset is inside the table when the list's count fits. A Script, Feature, Lookup, FeatureVariations, or GDEF offset is inside the table when it is below the table length.
- A cmap subtable format outside 0, 2, 4, 6, 8, 10, 12, 13, and 14 returns `InvalidCmap`, because no length check is defined for it.
- Case 39's `offSize 0` and `offSize 5` are tested both in the CFF header and in the Name INDEX.
- A CFF real operand with the reserved nibble `0xD` is rejected.
- File-set records use `"<corpora-root>/<id>/sources/..."` as `local_path`.
- The new source registry entries are `S56` to `S84`. If a concurrent task claimed those identifiers, the integrator renumbers them; no checked document cites them.

## Bounded work

Revision 1 replaced this section, because its cmap argument covered only fonts with at most 512 distinct subtables, and its format 4 bound implied a cost proportional to subtable size.

`parse` allocates nothing, recurses nowhere, and checks every count against the remaining bytes before its loop.
A read below is one checked `Reader` access of at most 16 bytes, and `L` is the length of the table that the bound describes.

### Table directory and checksums

The directory loop reads each of `numTables` 16-byte records once, after `12 + 16 * numTables` is checked against the input.
The overlap check compares the at most 15 known tables pairwise.
Known tables never overlap, so their direct checksums read each byte at most once.
Unknown tables may overlap each other and the known tables.
Their checksums use prefix sums at no more than 4096 block boundaries, 16 KiB of stack, so each unknown table costs at most two partial blocks, which is at most `2 * input length / 4096` words.

### cmap

Each encoding record costs a constant: one 8-byte record read, at most three header reads, one key comparison, one probe sequence in a 1024-slot set that holds at most 512 offsets, and four candidate comparisons.
There are at most 65535 records, and `4 + 8 * count` is checked against `L` first.

The set of validated offsets holds at most 512 distinct subtable offsets.
A record that names an offset outside a full set makes `parse` return `InvalidCmap` before any further validation, as revision 1 requires.
So each distinct offset is validated at most once, and at most 512 offsets are validated.

The validation cost of one subtable depends on its format.

| Format | Reads for one validation |
| --- | --- |
| 4 | `1 + 4 * segCount` reads for `segCountX2` and the four segment arrays, plus at most 65536 `glyphIdArray` reads, because the segments are disjoint and ascending inside U+0000 to U+FFFF and each code point of a segment with a nonzero `idRangeOffset` reads one entry. The 16-bit length field limits `segCount` to `(65535 - 16) / 8 = 8189`, so one validation reads at most `1 + 4 * 8189 + 65536 = 98293` entries, whatever its length. |
| 12 | `1 + numGroups`, and `16 + 12 * numGroups` is checked against the subtable length before the loop, so at most `1 + L / 12`. |
| 0, 2, 6, 8, 10, 13, 14 | The header and length check only: at most three reads. |

A format 4 subtable's cost is bounded by a constant, not by its size: 256 segments that share one 256-entry `glyphIdArray` reach 65536 reads from a 2576-byte subtable.
Case 51 builds exactly that subtable and names it from 65535 encoding records.
It parses, and the test-build counter `Font.cmap_table.validations` shows one validation.

The total across all encoding records is therefore at most `65535 * C + 512 * 98293` reads for format 4, where `C` is the constant per-record cost, plus the format 12 cost.
When distinct subtables do not overlap, the format 12 lengths sum to at most `L`, so all format 12 validations read at most `512 + L / 12` groups.
When distinct subtables overlap, each format 12 subtable can still span almost the whole table, so the format 12 bound becomes `512 * (1 + L / 12)` reads.
That bound is linear in `L` with a factor of at most 43, and the format 4 term stays the constant `512 * 98293`, about 5.0 * 10^7 reads.
Case 50 shows the capacity: 512 distinct subtables parse, a 513th distinct valid subtable returns `InvalidCmap`, and so does the reviewers' construction of 512 cheap subtables followed by 4096 records that repeat one format 4 subtable.
`raw/mutation-cmap-r1.log` shows that removing the full-set rejection fails case 50.

### Other tables and accessors

`loca` validation reads `numGlyphs + 1` entries, the CFF INDEX checks read each offset once, and the Top DICT loop advances at least one byte per iteration.
`glyphIndex` is a binary search, so it reads `O(log segCount)` or `O(log numGroups)` entries.
`name`, `post`, `gsub`, and `gpos` parse their table again on each call, in time linear in the table length; `os2` and `gdef` read a fixed-size header on each call.
A caller that needs these values for every glyph must keep the returned value instead of calling the accessor again.

## Checks for the integrator

1. Run `node tools/fairpane.mjs ucd-check`.
2. Run `node tools/fairpane.mjs corpus-verify unicode` and `node tools/fairpane.mjs corpus-verify opentype-fixtures` with the shared corpora root.
3. Record `HEAD`, the staged diff, and file hashes.
4. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0013/gates`.
5. Apply the proposed `specs/corpora.json` values in a separate protected commit, and run `corpus-verify` for both corpora again.

## Integration

The integrator applied the patch with `git apply --3way` and committed it as `b1fdb8c`.
The patch contains no change to `tools/workflow-check.mjs`, and the integrated controller suite passes the FP-0033 cases.

- `src/root.zig`, `tools/fairpane.mjs`, and `tools/README.md` conflicted only where FP-0011, FP-0021, and FP-0027 had added lines beside this patch's lines, so the integrator kept both sides.
- In `tools/selftest.mjs`, the `corpus-verify` fixture keeps this patch's version, which copies every `tools/*.mjs` file, including FP-0027's `release.mjs`.
  The other three conflicts there kept both sides.
- ADR 0003 now points at the file-set kind, as the worker suggested.
- The integrator confirms the reserved font name resolution.
  The subset uses no name that contains `Source`, so it meets OFL condition 3 whether or not `Source` is reserved.
- The source registry has 85 entries with no duplicate identifier.

`raw/integration-binding.log` records `HEAD` `b1fdb8c` and an empty status, including ignored files, for every source root before the gates, and an empty status again after the last run.

- `gates/2026-10-09T09-37-48-986Z-repo-check-61f657c7.json`
- `gates/2026-10-09T09-37-49-271Z-controller-test-24f7f361.json`, with 180 of 180 controller tests.
- `gates/2026-10-09T09-38-20-142Z-zig-fmt-17d5dcdb.json`
- `gates/2026-10-09T09-38-20-365Z-zig-test-5556126d.json`

`raw/integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0013-integration-cache`: 40 of 40 build steps and 177 of 177 tests.
`raw/integration-bun.log` records Bun 1.4.2 with 180 of 180 controller tests.
`raw/integration-corpus.log` records `ucd-check`, `corpus-verify unicode`, and `corpus-verify opentype-fixtures`, each with exit status 0 and result `pass`, against the unpinned `specs/corpora.json` entries.
The proposed pins wait for review acceptance and a separate protected commit.

## Revision 1

### Scope

This section covers `## Revision 1` of `CONTRACT.md`, which answers `reviews/review-1-reject.json` and `reviews/security-review-1-reject.json`.
The `fairpane-text` worker `FP0013R1` wrote the patch in an isolated worktree whose `HEAD` is `bdcc84c`, the commit that froze the revision.
Nothing is committed, and the protected paths, `engineering/state.json`, and `engineering/HANDOFF.md` are unchanged.
The patch changes no snapshot record, no applicability record, no expectation file, no expectation format, and no proposed pin.
The section "Bounded work" above is the rewritten bounded-work argument.

Every Zig command ran with `ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and the locked compiler, and every corpus command ran with `FAIRPANE_CORPORA_DIR=C:\src\fairpane\.tools\corpora`, as each `RESULT` line's `environment_overrides` shows.
The fontTools environment was missing from this worktree, so `raw/fonttools-install-r1.log` installed it from the wheel that `engineering/dependencies.json` names.

### Files changed

Modified: `build.zig`, `src/font/reader.zig`, `src/font/cmap.zig`, `src/font/tables.zig`, `src/font/layout.zig`, `src/font/cff.zig`, `src/font/opentype.zig`, `src/unicode/reference_test.zig`, `tests/text/root.zig`, `tests/text/fixture_test.zig`, `tests/text/synthetic_test.zig`, `tests/text/README.md`, `tools/fileset.mjs`, `tools/fileset.test.mjs`, `tools/corpus.mjs`, `tools/fairpane.mjs`, `tools/README.md`, `specs/README.md`, `specs/capabilities/text-fonts.json`, and this README.

Added: `tests/text/bounds_test.zig`, `mutation-cmap-r1.diff`, and the `raw/*-r1.log` files below.

### Changes

- cmap: the validated-offset set keeps its capacity of 512, and a record that names a new offset when the set is full makes `parse` return `InvalidCmap` before it validates anything more.
  `Cmap.validations`, which exists only when `builtin.is_test` is true, counts validations.
- Accessors: the `Font` documentation states that the bytes must stay unchanged for the lifetime of the `Font`, so a loader of script-visible memory must copy them first.
  `src/font` now contains no `.?` and no `unreachable`; each remaining `@intCast` follows a range check in the same function.
  Fixed-size records are copied with `Reader.fixed`, whose field reads check their range at compile time.
  `tableRecord`, `cmapSubtable`, `Name.record`, `Layout.scriptTag`, and `Layout.featureTag` now return `null` for an index out of range, or when changed bytes no longer describe a readable record.
  `findTable` returns `null` for a record that no longer lies inside the font.
  `glyphIndex` returns glyph 0 for an unreadable mapping or a glyph at or past numGlyphs, so its result is always below numGlyphs.
  `glyphHeader` returns `InvalidGlyph` when the `loca` entries no longer describe a range inside `glyf`, and `advance` returns `GlyphOutOfRange` if `hmtx` cannot hold the metric, which `parse` rules out.
  `Layout` keeps the script, feature, and lookup counts that its check read, and `Name` keeps its record count and storage offset.
  The `name`, `post`, `gsub`, and `gpos` documentation states that each call parses the table again in time linear in its length.
  `parse` copies each directory record and table header before it checks the copy, and its integrity pass, which reads the directory again, counts a record that no longer fits as a mismatch.
- ZIP reading: `readZip` checks the whole archive before any inflation, as `specs/README.md` lists, and inflation still stops at each declared size.
- Fetch order: `corpus-fetch` compares each source with the pinned size, published digest, Git blob ID, previous record size and SHA-256, and `specs/corpora.json` pins before it parses any archive.
  `corpus-verify` and `corpus-applicability` parse no local source whose size or SHA-256 differs from the record.
- Network: downloads follow at most 10 redirects manually, every hop must use `https:` on the five allowlisted hosts, and the body stops at its pinned size, the previous record's size, or 256 MiB.
- Atomic replacement: the write phase stages every file and the record beside its target, moves old files aside, swaps the source directory, writes the record last, and restores everything on any failure.
- fontTools: `corpus-derive` and the new `font-expectations [--check]` command check every installed fontTools file against the verified wheel's `RECORD`, then run Python in a staging directory with `PYTHONSAFEPATH=1` and no other `PYTHON*` variable.
  A probe also requires `sys.flags.safe_path` and an import of fontTools from the verified site-packages directory.
  fontTools runs without an operating-system sandbox, on inputs pinned by Git blob or SHA-256 only.
  `sfntCopyright` stops at the first `name` record and checks the sfnt header, the table range, the 6-byte `name` header, and the record array before it reads them.
- Evidence integrity: case 12 compares `generator.script` and `generator.script_sha256` with the committed `tools/fonts/font_expectations.py`, and `generator.fonttools` with `engineering/dependencies.json`.
  The `tests/text` run step now runs in the build root and lists both files as inputs.
  The reference test marks every code point that a parsed file assigns and fails when any stays unassigned, and a new unit test shows that check failing for a one-code-point gap.
- Trust on first use: the "Imported sources" section above and `specs/README.md` state that the UCD files and the `noto-sans` archive were trusted on first use.
- The `opentype-core-tables` capability record now states the 512-subtable `InvalidCmap` limit.

### Revision 1 cases

| Case | Where | Before the fix | After the fix |
| --- | --- | --- | --- |
| 50 | `tests/text/bounds_test.zig` | Fails: 513 distinct subtables parse instead of returning `InvalidCmap` | Passes |
| 51 | Same | Fails to compile: no validation counter. The old set also validated one shared offset once, so only the counter was missing | Passes with one validation |
| 52 | Same, ten tests | Fails to compile on the optional index results; the four tests that compile against the old API panic: `attempt to use null value` for a changed format 12 group count and a changed format 4 segment count, `integer does not fit in destination type` for a format 12 start glyph, and `integer overflow` for decreasing `loca` entries | Passes, including a sweep that changes every single byte of `B_TT` and `B_CFF` after `parse` |
| 53 | `tools/fileset.test.mjs` | 13 of 18 parts fail: overlap, five local-header mismatches, a local ZIP64 extra field, flag bit 13, a symbolic link, a reparse point, case folding, a total over 1 GiB, and a ratio over 1024. The old code already rejected a CRC-32 mismatch, both inflated-size mismatches, and both drive-letter names before writing anything | Passes |
| 54 | Same, three tests | All parts fail: 4 of 4 digest-order parts, 6 of 6 network parts, and the write-phase injection, which injected no failure | Passes; the injection test requires at least 10 write steps and checks the state after a failure at each one |
| 55 | Same, three tests | All parts fail except that a font without a `name` table was already rejected | Passes |

Each controller case runs its parts and reports every failing part, so `raw/tests-before-r1.log` shows each part that the old code did not meet.
After the before runs, five case 53 patterns changed from `local header disagrees` to `local header that disagrees`, to match the new message.
The old code threw no error for those archives, so their before results do not depend on the pattern.

### Evidence logs

| Log | Runs and exit statuses |
| --- | --- |
| `raw/fonttools-install-r1.log` | `curl.exe` download of the wheel, `sha256sum --check` (`OK`), `python -m venv`, `pip install --no-index --no-deps`, and an import check printing `4.66.1 3.13.15`; all exit 0. |
| `raw/tests-before-r1.log` | Nine runs at the revision base with the new tests, all exit 1. Run 1, `zig build test`, failed to compile on a test-code error, the removed `**` operator. Run 2, after that fix, failed to compile on the missing counter and optional accessors of cases 51 and 52. Runs 3 to 7 use `zig test --test-filter` on `tests/text/root.zig`: case 50 fails, and the four case 52 tests above panic. Runs 8 and 9 run `node tools/fileset.test.mjs`: 9 of 16 pass and cases 53 to 55 fail; run 9 follows only the split of the `sfntCopyright` case into reported parts. |
| `raw/mutation-cmap-r1.log` | Two `zig build test` runs with `mutation-cmap-r1.diff` applied, both exit 1 with only case 50 failing: 189 of 190 tests. The first ran on an intermediate tree whose reference test printed two diagnostic lines; the second ran on the final tree. The diff was then reverted. |
| `raw/tests-after-r1.log` | Uncached `zig build test --summary all --cache-dir out/fp0013-cache-after-r1`, exit 0: 40 of 40 steps and 190 of 190 tests, 145 in the library module and 45 in `tests/text`. |
| `raw/controller-tests-after-r1.log` | Two runs of `node tools/fairpane.mjs test`, both exit 0 with 187 of 187. The second run follows the last change to `tools/fileset.mjs`, which replaced a recursive `readdirSync` in the installation check with a portable walk. |
| `raw/ucd-check-r1.log` | Two runs of `ucd-check`, both exit 0 with `pass`; the second is on the final tree. |
| `raw/corpus-verify-r1.log` | `corpus-verify unicode` and `corpus-verify opentype-fixtures`, twice each, all exit 0 with `pass`; the second pair is on the final tree. |
| `raw/font-expectations-r1.log` | Three `font-expectations --check` runs and one `sha256sum` run, all exit 0. Each `font-expectations` run verified 350 installed files against the wheel's `RECORD`, ran the script for all four fixtures in a staging directory, and found every output byte-identical to the committed file. The `sha256sum` run shows the committed files and the script, `ea1ee96f…c350c51b`. The last run is on the final tree. |
| `raw/corpus-derive-r1.log` | Two `corpus-derive opentype-fixtures` runs under the hardened invocation, both exit 0; the second is on the final tree. Each reproduced `cjk-subset.otf` byte for byte, 9564 bytes with SHA-256 `3f435bdd…afb682a83c`, and rewrote `specs/snapshots/opentype-fixtures.json` with identical bytes. |

The mutation control `mutation-directory-order.diff` describes the parser before this revision; its context lines no longer match `src/font/opentype.zig`, which now reads directory records with `Reader.fixed`.

### Open questions

- Case 55 observes the child environment by running Node through `runPython`, the only function that starts an import tool, rather than through a full `corpus-derive` run, because controller tests cannot assume Python.
  The real `corpus-derive` and `font-expectations` runs above confirm `sys.flags.safe_path` and the verified import path through the probe.
- The installation check does not verify bytecode under `__pycache__`, and it does not inspect `.pth` files in site-packages.
- The usage line inside `tools/fonts/font_expectations.py` still shows a direct run from the repository root; changing it would change the script digest that every expectation file records.
- The integrator records the search of the CJK subset's bytes for `Source` in ASCII and in UTF-16BE, as the contract assigns.

### Integration

The integrator applied the patch without conflicts and committed it as `4a09ed5`.
The patch changes no expectation file, snapshot record, or proposed pin.
The integrator accepts the worker's open questions as follows.

- Case 55 observes the child environment through `runPython`, because controller tests cannot assume Python, and the recorded real runs cover the Python side.
- The installation check covers every file that the wheel's `RECORD` lists, but not `__pycache__` bytecode or `.pth` files.
  Changing either needs write access to the local virtual environment, which is the same trust level as the repository itself, so the integrator accepts this limit.
- The usage line of `tools/fonts/font_expectations.py` stays unchanged, because the script's digest is part of every expectation file.

`raw/integrator-rfn-search-r1.log` records the integrator's search of `cjk-subset.otf` with GNU `grep -c -a -i`.
`Source` occurs zero times in ASCII and zero times in UTF-16BE, and the control string `NotoSans` occurs, which shows that the search reads the file's strings.

One uninterrupted sequence ran on `4a09ed5`, with no commit or source edit during it.
`raw/r1-integration-binding.log` records `HEAD` `4a09ed5` and an empty status, including ignored files, for every source root before the gates, and both again after the last run.

- `gates/2026-10-09T10-43-59-332Z-repo-check-60c437dd.json`
- `gates/2026-10-09T10-43-59-654Z-controller-test-6f36fc75.json`, with 188 of 188 controller tests.
- `gates/2026-10-09T10-44-36-961Z-zig-fmt-eaabfe34.json`
- `gates/2026-10-09T10-44-37-233Z-zig-test-c96aa096.json`

`raw/r1-integration-tests.log` runs `zig build test --summary all` with the fresh cache `out/fp0013-r1-integration-cache` and the recorded override `ZIG_GLOBAL_CACHE_DIR`: 62 of 62 build steps and 191 of 191 tests, which include the FP-0011 revision 1 tests that landed after the worker's base.
`raw/r1-integration-bun.log` records Bun 1.4.2 with 188 of 188 controller tests.
`raw/r1-integration-corpus.log` records `ucd-check`, `corpus-verify unicode`, and `corpus-verify opentype-fixtures`, each with exit status 0 and result `pass`.
