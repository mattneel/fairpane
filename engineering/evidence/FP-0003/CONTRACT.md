# FP-0003 task contract

## Identity

Task ID: `FP-0003`, "Pin source corpora and preserve provenance".
Workstream: `laboratory`.
Base: the commit that records `FP-0001` acceptance.
Prerequisites: `FP-0001`.
Assigned role: `fairpane-core`.
Authority: `protected-corpus-change-needs-independent-review`.

## Behavior

### Snapshot storage

Corpus snapshots live outside version control under `<corpora-root>/<corpus-id>/`.
`<corpora-root>` defaults to `<repository>/.tools/corpora` and can be overridden by `FAIRPANE_CORPORA_DIR`.
Each snapshot keeps a bare Git repository that contains the pinned commit and its objects.
Upstream files are never edited.

### Revision records

`specs/snapshots/wpt.json` and `specs/snapshots/test262.json` record each pinned corpus.

| Field | Content |
| --- | --- |
| `corpus` | `wpt` or `test262` |
| `upstream` | The repository URL from `specs/corpora.json` |
| `ref` | The upstream branch name that `git ls-remote` reported |
| `commit` | The 40-hex commit ID that `git ls-remote` reported and the fetch confirmed |
| `tree` | The commit's tree ID from the fetched objects |
| `commit_date` | The committer date from the fetched commit |
| `retrieved_at` | The UTC fetch time |
| `license` | Path, byte size, SHA-256, and the license name as the upstream text states it |
| `inventory` | Entry count, total blob bytes, and inventory SHA-256 |

Every value comes from command output that the task preserves.
No field is guessed or copied from memory.

### Canonical inventory

The inventory covers every entry of the pinned commit's tree, read from Git objects rather than a working tree.
Line-ending conversion and local Git configuration therefore cannot change it.
Each blob and symbolic link produces this line: `<mode>\t<sha256 of the object content>\t<byte size>\t<path>\n`.
Each submodule entry produces this line: `160000\t<commit ID>\t0\t<path>\n`.
Paths are raw tree paths, read with NUL-separated output.
Lines sort by the UTF-8 bytes of the path.
The inventory SHA-256 is the digest of the concatenated lines.

### Applicability metadata

`specs/applicability/test262.json` and `specs/applicability/wpt.json` record local test applicability.
Each file names its corpus commit and an exact discovery rule.
It records the discovered count, the selected count, excluded entries with reasons, and the unclassified count.
The counts must satisfy `selected + excluded + unclassified = discovered`.
This task selects and excludes no tests, so every discovered test is unclassified.

Test262 discovery counts `.js` files under `test/`, except names that end in `_FIXTURE.js`.
The file also records counts for each top-level directory under `test/`.
WPT discovery uses the WPT manifest tool at the pinned revision.
The file records the manifest command, the manifest digest, and test counts for each manifest item type.
If the WPT manifest tool cannot run, the task records that failure as a blocker and records no WPT count.

### Controller commands

| Command | Behavior |
| --- | --- |
| `corpus-fetch <id>` | Resolves the branch head, fetches that commit, and writes the snapshot record. |
| `corpus-verify <id>` | Recomputes the inventory from the local snapshot and compares every recorded field. |

`corpus-verify` exits with status 1 on any mismatch, a missing snapshot, or a missing record.
Network access happens only in `corpus-fetch`.

### Import requirements

`specs/IMPORT_REQUIREMENTS.md` records the Unicode, CLDR, and font-fixture import requirements.
It names the data files that later tasks need, their license terms, and the version selection rule.
Each version or license statement cites a primary source in `specs/sources.json`.
It permits font fixtures only with an explicit redistribution license and per-file provenance.
This task imports no font, Unicode data, or CLDR data.

### Protected corpus policy

`specs/corpora.json` is a protected path, and this task does not edit it.
`engineering/decisions/0003-corpus-snapshots.md` records the snapshot format and the proposed `corpora.json` values.
The integrator applies that policy change in a separate commit after `fairpane-review` and `fairpane-spec` approve it.

## Exact test cases

Controller tests in `tools/selftest.mjs` build small Git repositories in temporary directories.

1. The inventory of a fixture commit equals a hand-computed canonical listing digest.
2. The inventory ignores working-tree files and `core.autocrlf`.
3. A changed blob, an added file, a removed file, and a renamed file each change the inventory digest.
4. Paths with spaces, non-ASCII bytes, and tabs keep their exact bytes through NUL-separated parsing.
5. A symbolic link entry hashes its target text, and a submodule entry records its commit ID.
6. `corpus-verify` fails for a missing snapshot, a missing record, a wrong commit, a wrong tree, and a wrong inventory digest.
7. Applicability validation rejects negative counts, non-integer counts, inconsistent sums, and exclusions without reasons.
8. Snapshot record validation rejects a non-40-hex commit, a missing license digest, and a missing inventory digest.

## Authority

Writable paths: `specs` except `specs/corpora.json`, plus `tools`, `tests`, and `engineering/decisions`.
Protected paths: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Required independent reviewers: `fairpane-review` and `fairpane-spec`.

## Acceptance

Exact gate commands, run by the integrator after review:

```text
node tools/fairpane.mjs run repo-check --evidence-dir engineering/evidence/FP-0003/gates
node tools/fairpane.mjs run controller-test --evidence-dir engineering/evidence/FP-0003/gates
node tools/fairpane.mjs record engineering/evidence/FP-0003/raw/corpus-verify.log node tools/fairpane.mjs corpus-verify test262
node tools/fairpane.mjs record engineering/evidence/FP-0003/raw/corpus-verify.log node tools/fairpane.mjs corpus-verify wpt
```

Required target execution: Windows x86_64 host execution with network access for the fetch.
Resource limits: the fetch has a watchdog, and the verification streams objects without loading the corpus into memory at once.
Expected test denominator: the existing controller tests plus the eight cases above.

## Non-goals

- No test runner, expectation file, or conformance result exists in this task.
- Unicode, CLDR, font, WebAssembly, WebGPU, and WebGL corpora stay unfetched.
- This task does not change acceptance thresholds or required capability families.
