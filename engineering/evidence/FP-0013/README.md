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
| `UCD.zip`, Unicode 18.0.0 | 5657953 | `7b3e5555…a66a0d8` | 18.0.0 | 71 file members, inventory `37761bcf…8dd8b2f4` |
| `license.txt` | 1995 | `e7a93b00…2bc53d96` | Unicode License v3 | Beside the data and reproduced in `tables.zig` |
| `NotoSans-v2.015.zip` | 117491253 | `0c34df07…89b958f5` (no published digest) | `NotoSans-v2.015`, peeled commit `c4a321e123e4d4ff315f57f4e0adf294fe3a95be` | Size pin and tag commit matched |
| `NotoSansArabic-v2.013.zip` | 18777381 | `1301acea…da7154f1` | `NotoSansArabic-v2.013`, peeled commit `1b2b7e5c6ce3ab4d50681c854892325530084c35` | Size, published GitHub digest, and tag commit matched |
| `NotoSansDevanagari-v2.007.zip` | 18449254 | `820c7da4…f469b1` | `NotoSansDevanagari-v2.007`, peeled commit `e123d230c160ebe949d731cc19017cdb354180d1` | Size, published GitHub digest, and tag commit matched |
| `NotoSansCJKjp-Regular.otf` at `Sans2.004` | 16467736 | `68a3fc98…7f375b5` | `Sans2.004`, lightweight tag at `523d033d6cb47f4a80c58a35753646f5c3608a78` | Size and Git blob `f56224957fb13a81b4c14bac34f2f058a017f9fb` matched |
| noto-cjk `LICENSE` at `Sans2.004` | 4301 | `6a73f954…5efe2bf2` | Same tag | Size and Git blob `d952d62c065f3f35fb83a173496e90b21525aef3` matched |

`specs/snapshots/unicode.json` and `specs/snapshots/opentype-fixtures.json` hold the full digests of every source, inventory, selected file, and derived file.
ADR 0003 still says that only `wpt` and `test262` have fetch rules; that path is outside this task's writable paths, so the integrator may amend it to point at the file-set kind that `specs/README.md` now describes.
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

`parse` allocates nothing, recurses nowhere, and checks every count against the remaining bytes before its loop.
Two inputs could have made the work grow faster than the input length, so the parser bounds them.

- Unknown tables may overlap each other and the known tables. Their checksums use prefix sums at no more than 4096 block boundaries, 16 KiB of stack, so each unknown table costs at most two partial blocks. Known tables never overlap, so their direct sums read each byte once.
- Encoding records may share a cmap subtable. A 1024-slot set of validated offsets, 4 KiB of stack, validates each shared format 4 or format 12 subtable once, for up to 512 distinct subtables.

A format 4 subtable reads at most one `glyphIdArray` entry per code point, so its validation reads at most 65536 entries.
The reviewer should check these bounds against the contract's linear-time statement.

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
