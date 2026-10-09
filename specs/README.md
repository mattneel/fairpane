# Standards and corpus registry

`sources.json` lists primary references used in the bootstrap.
`corpora.json` lists required external corpus families.
Neither file claims that a complete standards snapshot exists locally.

`snapshots/<corpus>.json` records a pinned corpus revision, its license file, and its canonical inventory.
`applicability/<corpus>.json` records local test discovery for a pinned corpus.
`IMPORT_REQUIREMENTS.md` states the rules for later Unicode, CLDR, and font-fixture imports.
`engineering/decisions/0003-corpus-snapshots.md` defines the record formats.

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
```

`corpus-fetch` fetches only the pinned commit.
`corpus-repin` moves a snapshot to the upstream branch head, which then needs a protected `corpora.json` change.
`corpus-fetch` and `corpus-repin` are the only commands that use the network.
No command runs code from a corpus.
`corpus-verify` exits with status 1 on any mismatch, a pin difference, a missing snapshot, or a missing record.
It also exits with status 1 and reports `incomplete` when an applicability record lacks a denominator.
