# ADR 0003: Corpus snapshots

Status: proposed by task FP-0003, revised for contract revision 1.
Authority: the frozen contract in `engineering/evidence/FP-0003/CONTRACT.md`, including its `## Revision 1` section.
The `specs/corpora.json` change below needs approval from `fairpane-review` and `fairpane-spec`.
The integrator applies it in a separate commit.

## Decision

### Storage

Each snapshot lives under `<corpora-root>/<corpus-id>/`, outside version control.
`<corpora-root>` defaults to `<repository>/.tools/corpora`.
`FAIRPANE_CORPORA_DIR` overrides it.
`<corpus-id>/repository.git` is a bare Git repository with a depth-1 fetch of the pinned commit.
The fetch stores the commit at the upstream branch ref name, such as `refs/heads/main`.
The snapshot keeps no history before the pinned commit.
A WPT snapshot also keeps the wpt.fyi manifest at `<corpora-root>/wpt/MANIFEST.json`.
A fetch uses `<corpora-root>/<corpus-id>.fetch` and `<corpora-root>/<corpus-id>.old` only while it replaces a snapshot.

### Git process hardening

Every Git child process runs with `--no-replace-objects`, so a `refs/replace/` entry cannot substitute an object.
Every Git child process starts without the caller's `GIT_*` environment variables.
Variables such as `GIT_DIR`, `GIT_OBJECT_DIRECTORY`, and `GIT_CONFIG_PARAMETERS` therefore cannot redirect object reads or change configuration.
Git prompts are disabled, and every Git process has a watchdog that stops its whole process tree.

`corpus-fetch` and `corpus-repin` fetch into a fresh, empty repository.
`transfer.fsckObjects=true` therefore checks every object that the snapshot uses.
The controller replaces the snapshot only after the record validates and matches its pin.
A failed fetch removes its staging directory and leaves the existing snapshot unchanged.

`corpus-verify` runs `git fsck --full --strict --no-dangling` on the snapshot.
That command rehashes every stored object, so the recorded commit ID binds the tree, the committer date, and every blob.
The canonical inventory rejects any tree path that contains a line feed, because the inventory is line-based.

### Pins

A pin is the `revision`, `inventory_sha256`, `license_record`, and `manifest_sha256` fields of a `specs/corpora.json` entry.
A null field pins nothing.

`node tools/fairpane.mjs corpus-fetch <corpus-id>` fetches exactly the pinned commit.
When `specs/corpora.json` pins no revision, the commit, inventory SHA-256, and manifest SHA-256 of `specs/snapshots/<corpus-id>.json` act as the pin.
That fallback rebuilds a reviewed snapshot record before its pin reaches `specs/corpora.json`.
When neither file names a commit, `corpus-fetch` fails and names `corpus-repin`.
`corpus-fetch` never moves a snapshot to a new commit.

`node tools/fairpane.mjs corpus-repin <corpus-id>` moves a snapshot to the upstream branch head.
It writes a new snapshot record and reports each pin field that the new snapshot no longer matches.
The new commit needs a protected `specs/corpora.json` change before `corpus-verify` passes again.
The applicability record also needs `corpus-applicability` for the new commit.

`corpus-verify` fails when the snapshot commit differs from `revision`.
It fails when the inventory SHA-256 differs from `inventory_sha256`.
It fails when `license_record` names any file other than `specs/snapshots/<corpus-id>.json`.
It fails when the manifest SHA-256 differs from `manifest_sha256`.

Network access happens only in `corpus-fetch` and `corpus-repin`.
`corpus-applicability` and `corpus-verify` read the local snapshot and the repository records only.
The controller enforces no operating-system network policy; it simply opens no connection in those commands.

### Fetch

`corpus-fetch <corpus-id>` and `corpus-repin <corpus-id>` perform these steps.

1. Read the HTTPS upstream URL from `specs/corpora.json`.
2. Run `git ls-remote --symref <upstream> HEAD` and read the branch ref for `HEAD`.
3. Select the commit: the pin for `corpus-fetch`, or the reported head for `corpus-repin`.
4. Create a fresh bare repository at `<corpora-root>/<corpus-id>.fetch/repository.git`.
5. Run `git fetch --depth=1 --no-tags --no-write-fetch-head <upstream> +<commit>:<ref>` with `transfer.fsckObjects=true`.
6. Confirm that the local ref resolves to the selected commit.
7. For WPT, download and bind the manifest as described below.
8. Derive the tree, committer date, license record, inventory, and manifest fields from the fetched objects and the stored manifest.
9. For `corpus-fetch`, compare the record with its pin.
10. Replace `<corpora-root>/<corpus-id>` with the staging directory.
11. Write `specs/snapshots/<corpus-id>.json`.

Each network operation has a one-hour watchdog.
Only `wpt` and `test262` have fetch rules, because only they are Git corpora with known license files.

### WPT manifest trust decision

The controller runs no code from any corpus.
It does not run the WPT manifest tool.
Instead, `corpus-fetch wpt` downloads the manifest that wpt.fyi publishes for the pinned commit from `https://wpt.fyi/api/manifest?sha=<commit>`. [S46]
The response must have HTTP status 200 and a `x-wpt-sha` header equal to the pinned commit.
The controller stores the response bytes unchanged and records the URL, byte size, and SHA-256 in the snapshot record.

Upstream continuous integration builds that manifest and classifies each file into an item type.
Fairpane trusts that classification.
Fairpane verifies the correspondence between the manifest and the pinned tree.
Every manifest path must exist in the pinned tree as a blob.
Every manifest hash must equal the Git blob ID of that path.
A missing path or a different hash fails `corpus-fetch`, `corpus-applicability`, and `corpus-verify`.
The manifest version must be 9, the version that the pinned manifest tool writes. [S47]

This binding does not prove that the item types and test URLs are the ones the pinned tool would compute.
It does not prove that the manifest lists every test file in the tree.
It proves that every listed file is the pinned file, byte for byte.

An earlier revision ran the pinned manifest tool over a working copy.
That approach executed corpus Python code with the caller's environment and unrestricted network access.
It also failed: the tool exited with status 70 because the local Python had no `yaml` module, and the pinned `pyyaml==6.0.1` publishes Windows wheels only up to CPython 3.12. [S34]
Revision 1 removed that approach, the working-copy writer, and its `checkout` and `wptcache` directories.

### Snapshot record

| Field | Content |
| --- | --- |
| `schema_version` | `1` |
| `corpus` | The corpus ID |
| `upstream` | The HTTPS URL from `specs/corpora.json` |
| `ref` | The branch ref that `git ls-remote --symref` reported for `HEAD` |
| `commit` | The fetched 40-hex commit ID, which the local ref confirmed |
| `tree` | The tree ID from the fetched commit object |
| `commit_date` | The committer time and offset from the raw commit object, in ISO 8601 form |
| `retrieved_at` | The UTC time when the Git fetch completed |
| `license.path` | `LICENSE` for Test262 and `LICENSE.md` for WPT |
| `license.size`, `license.sha256` | The blob size and SHA-256 |
| `license.name` | The name the license text states, read by a fixed pattern |
| `inventory.entry_count` | The number of tree entries |
| `inventory.total_blob_bytes` | The sum of blob sizes over blob and symbolic link entries |
| `inventory.sha256` | The SHA-256 of the canonical inventory |
| `manifest.url`, `manifest.size`, `manifest.sha256` | WPT only: the wpt.fyi URL for the commit, and the stored manifest's byte size and SHA-256 |

The Test262 license name is the quoted text after `made available under the`.
That text, "BSD License", is the license's own wording, not an SPDX identifier.
The same `LICENSE` file states that the software may be subject to third-party rights, including patent rights, and that the license grants no license under such rights.
It refers to the Ecma code of conduct in patent matters at `https://www.ecma-international.org/ipr`.
The WPT license name is the first Markdown heading.

### Canonical inventory

`git ls-tree -r -z --full-tree <commit>` lists every non-tree entry.
Paths stay raw bytes, so quoting, encoding, and `core.quotePath` cannot alter them.
`git cat-file --batch` streams each distinct blob once.
The controller hashes blob content as it arrives and holds no complete blob in memory.
Neither command reads a working tree or applies content filters.
Line-ending settings and attributes therefore cannot change the inventory.

Each blob or symbolic link entry produces `<mode>\t<sha256>\t<size>\t<path>\n`.
Each submodule entry produces `160000\t<commit ID>\t0\t<path>\n`.
Lines sort by the bytes of the path.
The inventory SHA-256 is the digest of the concatenated lines.
A repeated path, an unknown entry mode, or a path with a line feed fails the inventory.

### Applicability records

`node tools/fairpane.mjs corpus-applicability <corpus-id>` writes `specs/applicability/<corpus-id>.json`.
It uses only the local snapshot and the stored manifest.

| Field | Content |
| --- | --- |
| `schema_version` | `1` |
| `corpus`, `commit` | The corpus ID and the pinned commit |
| `status` | `counted` |
| `discovery` | The exact rule and the controller command |
| `discovered`, `selected`, `unclassified` | Nonnegative integers |
| `excluded` | Entries with a `path` and a nonempty `reason` |
| `breakdown` | Counts by group that sum to `discovered` |
| `manifest` | WPT only: the URL, size, SHA-256, version, and item count of every type |
| `reported_separately` | WPT only: `test262` items, the vendored Test262 revision, and the reason |

A record satisfies `selected + excluded + unclassified = discovered`.
A record without those counts does not validate, so it has no denominator.
This task selects and excludes nothing, so every discovered test is unclassified.

Test262 discovery counts blob entries under `test/` that end in `.js`.
It excludes every file whose name contains `_FIXTURE`, because upstream says such files must not be interpreted as standalone tests. [S45]
It groups the count by the top-level directory under `test/`.
The count is a file count, not an execution-scenario count.
The later selection task defines scenario expansion from test frontmatter.

WPT discovery reads the bound manifest.
Each manifest file entry contributes its array length minus one, because the first element is the file hash and each further element is one test URL. [S47]
Discovered WPT tests are the items of every type except `spec`, `support`, and `test262`.
The record reports counts for each item type.

These item-type decisions apply.

- `test262` items come from the WPT copy of Test262 under `third_party/test262`.
  The record reports them separately, with the revision from `third_party/test262/vendored.toml`.
  Fairpane runs Test262 from its own pinned `test262` corpus.
- `conformancechecker` items test HTML validators, not browsers.
  They stay in the discovered count, and the later selection task excludes them with that reason.
- `manual` items need human interaction.
  They stay in the discovered count, and the later selection task decides how to classify them.

The pinned manifest has no `spec` or `conformancechecker` items, as `specs/applicability/wpt.json` shows.

### Verification

`node tools/fairpane.mjs corpus-verify <corpus-id>` performs these checks.

1. Validate the snapshot record and check `upstream` against `specs/corpora.json`.
2. Run `git fsck --full --strict --no-dangling` on the snapshot.
3. Check that the snapshot's local ref resolves to the recorded commit.
4. Recompute the tree, committer date, license record, and inventory, and compare every field.
5. For WPT, rehash the stored manifest, compare its size and SHA-256, and bind it to the tree again.
6. Compare the record with every pin in `specs/corpora.json`.
7. Recompute the applicability record and compare the whole record.
8. Check that every pinnable corpus has an applicability record with a valid denominator.

Any failure in steps 1 through 7 exits with status 1.
A missing snapshot or a missing record also exits with status 1.
When step 8 finds a missing denominator, the result is `incomplete`, the command lists the corpus, and it exits with status 1.
Otherwise the result is `pass`.
`retrieved_at` cannot be recomputed, so verification checks only its UTC format.

## Pinned values

These values come from `engineering/evidence/FP-0003/raw/corpus-fetch-test262.log`, `corpus-fetch-wpt.log`, and `corpus-fetch-wpt-manifest.log`.

| Field | Test262 | WPT |
| --- | --- | --- |
| `ref` | `refs/heads/main` | `refs/heads/master` |
| `commit` | `2e0a56762801e275a9fdf96dc49d90ba0cddcf63` | `b60c4b349d9d167bf354a40bc0d4cbed15174606` |
| `tree` | `6a4268a9354a545d41c3b62efebc478ed8c521f4` | `a499343a14a03239fe23fdb3b183732ddaa6cf4b` |
| `commit_date` | `2026-10-08T13:50:06+02:00` | `2026-10-08T23:14:40+02:00` |
| `license` | `LICENSE`, 2213 bytes, "BSD License" | `LICENSE.md`, 1500 bytes, "The 3-Clause BSD License" |
| `inventory.entry_count` | 57013 | 164551 |
| `inventory.total_blob_bytes` | 90245391 | 505155316 |
| `inventory.sha256` | `4d86002fe32f66581faa24e4843360ecd148ca44d2adacd31ef08f74d7e8acd8` | `0be4a67e0e13f7fb1f9d82324a118dd3851acbcb50752ecb3615eb1391e395ab` |
| `manifest` | None | 40224677 bytes, SHA-256 `86d55bee991997a4753d0987397883249a0d6fc94e0901ed3efb84cceed53067` |
| Applicability | 53616 discovered, all unclassified | 76600 discovered, all unclassified; 53660 `test262` items reported separately |

## Proposed `specs/corpora.json` values

`local_path` is relative to `<corpora-root>`, because `FAIRPANE_CORPORA_DIR` can move that root.

Apply these values to the `test262` entry.

```json
{
  "revision": "2e0a56762801e275a9fdf96dc49d90ba0cddcf63",
  "license_record": "specs/snapshots/test262.json",
  "inventory_sha256": "4d86002fe32f66581faa24e4843360ecd148ca44d2adacd31ef08f74d7e8acd8",
  "local_path": "<corpora-root>/test262/repository.git",
  "status": "pinned"
}
```

Apply these values to the `wpt` entry.

```json
{
  "revision": "b60c4b349d9d167bf354a40bc0d4cbed15174606",
  "license_record": "specs/snapshots/wpt.json",
  "inventory_sha256": "0be4a67e0e13f7fb1f9d82324a118dd3851acbcb50752ecb3615eb1391e395ab",
  "manifest_sha256": "86d55bee991997a4753d0987397883249a0d6fc94e0901ed3efb84cceed53067",
  "local_path": "<corpora-root>/wpt/repository.git",
  "status": "pinned"
}
```

`pinned` means that the revision, license, inventory, and, for WPT, the manifest are recorded and verifiable.
It does not mean that expectations or any conformance result exist.
The other corpus entries stay unchanged.

## Consequences

The corpora stay outside Git, so the repository holds only records and digests.
A depth-1 snapshot cannot answer history questions without another fetch.
`corpus-fetch` can rebuild every recorded field, except `retrieved_at`, from a fresh fetch of the pinned commit.
The WPT denominator depends on wpt.fyi continuing to serve the manifest for the pinned commit.
If wpt.fyi stops serving it, the existing snapshot stays valid, but a fresh fetch fails until a repin.
Local records are integrity records, not signatures.
