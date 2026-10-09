# ADR 0003: Corpus snapshots

Status: proposed by task FP-0003.
Authority: the frozen contract in `engineering/evidence/FP-0003/CONTRACT.md`.
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

### Fetch

`node tools/fairpane.mjs corpus-fetch <corpus-id>` performs these steps.

1. Read the HTTPS upstream URL from `specs/corpora.json`.
2. Run `git ls-remote --symref <upstream> HEAD` and read the branch and commit for `HEAD`.
3. Create the bare repository if it does not exist.
4. Run `git fetch --depth=1 --no-tags --no-write-fetch-head <upstream> +<commit>:<ref>` with `transfer.fsckObjects=true`.
5. Confirm that the local ref resolves to the reported commit.
6. Derive the tree, committer date, license record, and inventory from the fetched objects.
7. Write `specs/snapshots/<corpus-id>.json`.

Each network command has a one-hour watchdog that stops the whole process tree.
Git prompts are disabled.
Only `wpt` and `test262` have fetch rules, because only they are Git corpora with known license files.

### Snapshot record

| Field | Content |
| --- | --- |
| `schema_version` | `1` |
| `corpus` | The corpus ID |
| `upstream` | The HTTPS URL from `specs/corpora.json` |
| `ref` | The branch ref that `git ls-remote --symref` reported for `HEAD` |
| `commit` | The 40-hex commit ID that `git ls-remote` reported and the fetch confirmed |
| `tree` | The tree ID from the fetched commit object |
| `commit_date` | The committer time and offset from the raw commit object, in ISO 8601 form |
| `retrieved_at` | The UTC time when the fetch completed |
| `license.path` | `LICENSE` for Test262 and `LICENSE.md` for WPT |
| `license.size`, `license.sha256` | The blob size and SHA-256 |
| `license.name` | The name the license text states, read by a fixed pattern |
| `inventory.entry_count` | The number of tree entries |
| `inventory.total_blob_bytes` | The sum of blob sizes over blob and symbolic link entries |
| `inventory.sha256` | The SHA-256 of the canonical inventory |

The Test262 license name is the quoted text after `made available under the`.
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
A repeated path or an unknown entry mode fails the inventory.

### Applicability records

`node tools/fairpane.mjs corpus-applicability <corpus-id>` writes `specs/applicability/<corpus-id>.json`.
It uses only the local snapshot.

| Field | Content |
| --- | --- |
| `schema_version` | `1` |
| `corpus`, `commit` | The corpus ID and the pinned commit |
| `status` | `counted`, or `blocked` when the discovery tool cannot run |
| `discovery` | The exact rule, the controller command, and any tool command |
| `discovered`, `selected`, `unclassified` | Nonnegative integers, or `null` when blocked |
| `excluded` | Entries with a `path` and a nonempty `reason` |
| `breakdown` | Counts by group that sum to `discovered`, or `null` when blocked |
| `blocker` | The reason and the last tool output, only when blocked |

A counted record satisfies `selected + excluded + unclassified = discovered`.
This task selects and excludes nothing, so every discovered test is unclassified.

Test262 discovery counts blob entries under `test/` that end in `.js` but not in `_FIXTURE.js`.
It groups the count by the top-level directory under `test/`.

WPT discovery writes a working copy from Git objects to `<corpora-root>/wpt/checkout`.
Symbolic links become files that hold the link target, as Git does without symlink support.
The pinned commit has 16 symbolic links, all under `tools/third_party/websockets/`.
The controller then runs the pinned launcher with `--venv <corpora-root>/wpt/no-venv --skip-venv-setup`.
That flag pair makes the launcher skip virtual environment creation and package installation, so the run needs no network.
The manifest goes to `<corpora-root>/wpt/MANIFEST.json`, outside the working copy.
Each manifest file entry contributes its array length minus one, because the first element is the file hash.
Discovered WPT tests are the items of every manifest type except `spec` and `support`.
A counted WPT record also stores the manifest SHA-256, size, version, and the item count of every type.

### Verification

`node tools/fairpane.mjs corpus-verify <corpus-id>` uses no network.
It validates the record schema and checks `upstream` against `specs/corpora.json`.
It checks that the snapshot's local ref resolves to the recorded commit.
It recomputes the tree, committer date, license record, and inventory, and compares every field.
It validates the applicability record and checks its commit.
It recomputes the Test262 discovery and compares the whole record.
For a counted WPT record, it recomputes the manifest SHA-256 and item counts.
It exits with status 1 on any mismatch, a missing snapshot, or a missing record.
`retrieved_at` cannot be recomputed, so verification checks only its UTC format.

## Pinned values

These values come from `engineering/evidence/FP-0003/raw/corpus-fetch-test262.log` and `corpus-fetch-wpt.log`.

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
| Applicability | 53616 discovered, all unclassified | Blocked, no count |

## Proposed `specs/corpora.json` values

Apply these values to the `test262` entry.

```json
{
  "revision": "2e0a56762801e275a9fdf96dc49d90ba0cddcf63",
  "license_record": "specs/snapshots/test262.json",
  "inventory_sha256": "4d86002fe32f66581faa24e4843360ecd148ca44d2adacd31ef08f74d7e8acd8",
  "local_path": ".tools/corpora/test262/repository.git",
  "status": "pinned"
}
```

Apply these values to the `wpt` entry.

```json
{
  "revision": "b60c4b349d9d167bf354a40bc0d4cbed15174606",
  "license_record": "specs/snapshots/wpt.json",
  "inventory_sha256": "0be4a67e0e13f7fb1f9d82324a118dd3851acbcb50752ecb3615eb1391e395ab",
  "local_path": ".tools/corpora/wpt/repository.git",
  "status": "pinned"
}
```

`pinned` means that the revision, license, and inventory are recorded and verifiable.
It does not mean that applicability, expectations, or any conformance result exists.
The other corpus entries stay unchanged.

## WPT manifest blocker

The WPT manifest tool did not run with the local Python 3.13.15.
The evidence is `engineering/evidence/FP-0003/raw/wpt-manifest.log`.
The tool exited with status 70 after `ModuleNotFoundError: No module named 'yaml'`.
The pinned `tools/manifest/test262.py` imports `yaml` to parse front matter in `.js` files under directories named `test262`.
The pinned `tools/manifest/requirements.txt` requires `pyyaml==6.0.1`, `zstandard==0.25.0`, and `types-pyyaml==6.0.12.20241230`.
The local interpreter has no `yaml` module, as `raw/python-modules.log` shows, and the offline run installs nothing.
PyPI lists Windows wheels of PyYAML 6.0.1 only up to CPython 3.12, as `raw/pyyaml-6.0.1-files.log` shows. [S34]
A Python 3.13 installation of that pin would therefore need a source build.
`specs/applicability/wpt.json` records the blocker and no count.

Resolving the blocker needs a decision on how to provision the tool's pinned Python requirements.
One option is a pinned CPython 3.12 with a recorded offline wheelhouse and its digests.
That decision belongs to a later task, because it adds third-party code to the development host.

## Consequences

The corpora stay outside Git, so the repository holds only records and digests.
A depth-1 snapshot cannot answer history questions without another fetch.
A reviewer can rebuild every recorded field from a fresh fetch of the same commit.
Local records are integrity records, not signatures.
