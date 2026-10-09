# Standards and corpus registry

`sources.json` lists primary references used in the bootstrap.
`corpora.json` lists required external corpus families.
Neither file claims that a complete standards snapshot exists locally.

`snapshots/<corpus>.json` records a pinned corpus revision, its license file, and its canonical inventory.
`applicability/<corpus>.json` records local test discovery for a pinned corpus.
`capabilities/<family>.json` records what the engine does now for each obligation of a capability family.
`IMPORT_REQUIREMENTS.md` states the rules for Unicode, CLDR, and font-fixture imports.
`engineering/decisions/0003-corpus-snapshots.md` defines the Git record formats.
`engineering/evidence/FP-0013/CONTRACT.md` defines the file-set record formats.

## Snapshot procedure

1. Select an exact upstream revision or version.
2. Record the source URL and license terms.
3. Fetch through an approved development network path.
4. Hash the complete corpus inventory.
5. Preserve upstream files without local edits.
6. Store local applicability and expectation metadata separately.
7. Record each selected manifest and its denominator.

Unknown provenance blocks import, not unrelated first-party implementation.
The owner controls publication and license policy.

## Corpus commands

Snapshots live under `.tools/corpora/<corpus>/` unless `FAIRPANE_CORPORA_DIR` names another root.

```text
node tools/fairpane.mjs corpus-fetch <corpus>
node tools/fairpane.mjs corpus-repin <corpus>
node tools/fairpane.mjs corpus-applicability <corpus>
node tools/fairpane.mjs corpus-verify <corpus>
node tools/fairpane.mjs corpus-derive <corpus>
```

`corpus-fetch` fetches only the pinned commit or the frozen file-set sources.
`corpus-repin` moves a Git snapshot to the upstream branch head, which then needs a protected `corpora.json` change.
`corpus-fetch` and `corpus-repin` are the only commands that use the network.
No command runs code from a corpus.
`corpus-derive` runs only a declared import-time tool from `engineering/dependencies.json`.
`corpus-verify` exits with status 1 on any mismatch, a pin difference, a missing snapshot, or a missing record.
It also exits with status 1 and reports `incomplete` when an applicability record lacks a denominator.

## Corpus kinds

`wpt` and `test262` are Git corpora.
A Git snapshot is a bare repository at one commit, and ADR 0003 defines its record.

`unicode` and `opentype-fixtures` are file-set corpora.
A file-set corpus is a frozen list of upstream files and ZIP archives in `tools/fileset.mjs`.
A task contract freezes that list, so `corpus-repin` exits with status 1 for a file-set corpus.
`corpus-fetch` downloads every source into `<corpora-root>/<corpus>/sources/`.
It checks each pinned size, published digest, Git blob ID, and release tag commit.
It also checks that each `published_url` serves the same bytes as the extracted member.
It extracts the selected members unedited, only under `src/unicode/ucd/` and `tests/text/fonts/`.
It writes the record only after every check passes.
A failure leaves the existing sources, record, and extracted files unchanged.
An existing record acts as a pin for each source and file digest.

A file-set record has `kind` `"file-set"`, a `version`, `sources`, `selected`, and `derived`.
Each zip source records an inventory: one `<sha256>\t<size>\t<path>\n` line per file member, sorted by the UTF-8 bytes of the path.
The zip reader accepts only stored and deflate members.
It rejects ZIP64, encryption, absolute paths, `..` segments, backslashes, and duplicate paths.
A `font` entry names its license file, the license name, the copyright notice, and its Reserved Font Names.
A `derived` entry names its input source digest, its tool, the tool's wheel and Python version, and its argument vector.

A file-set applicability record names `version` and the `inventories` of its sources in place of `commit`.
`unicode` discovery counts the file members of `UCD.zip` by first path component.
`opentype-fixtures` discovery counts `.ttf` and `.otf` files by source.

For a file-set corpus, the `specs/corpora.json` pin fields mean the following.

- `revision` is the record `version`.
- `inventory_sha256` is the SHA-256 of the record's source listing, one `<sha256>\t<size>\t<source id>\n` line per source in record order.
- `license_record` is `specs/snapshots/<corpus>.json`.

## Capability records

`capabilities/text-fonts.json` lists the frozen obligations of the `text-fonts` family.
Each obligation has a status, an owner task from `engineering/plan.json`, a summary, and the engine's current behavior.
A remaining obligation states the exact error or the absence of an API, so the record never reports unsupported behavior as success.
`tools/capabilities.mjs` validates the record, and controller case FP-0013 case 49 checks it.
