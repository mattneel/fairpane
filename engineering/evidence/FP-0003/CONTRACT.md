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

## Revision 1

Revision 1 follows the rejecting reviews in `engineering/evidence/FP-0003/reviews/review-1-reject.json` and `engineering/evidence/FP-0003/reviews/spec-review-1-reject.json`.
It supersedes each earlier statement that it contradicts.
Every earlier exact test case still applies.

### WPT denominator

Plan criterion 3 requires an explicit WPT denominator, so a blocked WPT record no longer satisfies this task.
The controller no longer runs the WPT manifest tool or any other code from a corpus.
It obtains the official manifest that wpt.fyi publishes for the pinned commit from `https://wpt.fyi/api/manifest?sha=<commit>`.
`corpus-fetch wpt` stores that manifest beside the snapshot and records its URL, byte size, and SHA-256 in the snapshot record.
The fetch requires the response header `x-wpt-sha` to equal the pinned commit.

The controller binds the manifest to the pinned tree.
For every manifest path, the manifest hash must equal the Git blob ID of that path in the pinned tree.
A manifest path that the tree lacks, or a hash mismatch, fails the fetch and the verification.
`engineering/decisions/0003-corpus-snapshots.md` records the trust decision: upstream continuous integration classifies item types, and the controller verifies path and content correspondence.

WPT discovery counts manifest items of every type except `support`, `spec`, and `test262`.
Each item is one test URL, as upstream `TypeData.to_json` writes it.
The record reports `test262` items separately, with the vendored Test262 revision from `third_party/test262/vendored.toml`, because Fairpane runs Test262 from its own pinned corpus.
The record reports counts for each item type.
This task selects and excludes no tests, so every discovered WPT test stays unclassified.
The ADR records that `conformancechecker` items test HTML validators and that `manual` items need human interaction, for the later selection task.

### Pins and verification

When `specs/corpora.json` pins a revision, `corpus-fetch` fetches exactly that commit.
Moving a snapshot to a new upstream head needs a separate `corpus-repin <id>` command and a protected policy change.
`corpus-verify` fails when the snapshot commit, inventory SHA-256, license record, or manifest SHA-256 differs from a pin in `specs/corpora.json`.
`corpus-verify` returns a top-level result other than `pass` whenever any applicability record lacks a denominator.

Every Git child process runs with replace objects disabled and without inherited `GIT_*` variables.
`corpus-verify` binds the recorded commit ID to content, by rehashing objects or by `git fsck --full --strict --no-dangling`.
`corpus-fetch` fetches into a fresh repository and replaces the snapshot only after the record validates.
The inventory rejects any tree path that contains a line feed.

Test262 discovery excludes every file whose name contains `_FIXTURE`, as upstream `INTERPRETING.md` states.

### Import requirements

`specs/IMPORT_REQUIREMENTS.md` names every data file in the spec review's findings.
These include normalization, segmentation, line breaking, bidirectional, script, IDNA, and emoji data, with the consuming specifications.
It states that ECMA-402 defines the sanctioned unit identifiers.
It allows the CLDR `Public` directory alternative only where that directory exists.
It records the license file at a pinned tag as the governing text.
It states that a corpus record covers only local use of third-party files inside the corpus.
It requires each such file's own license before any copy or fixture use.
It adds condition 5 of the SIL Open Font License 1.1.

### Additional exact test cases

9. Verification fails when the license digest, the commit date, or an applicability count differs from its record.
10. `corpus-verify` exits with status 1 through the controller command on an inventory digest mismatch.
11. A replace ref that substitutes the recorded commit cannot make verification pass.
12. A tree path that contains a line feed fails the inventory.
13. WPT counting of a fixture manifest reports per-type counts, excludes `support`, `spec`, and `test262` from discovery, and reports `test262` separately.
14. A fixture manifest with a path that the tree lacks, or with a hash that differs from the blob ID, fails binding.
15. A pinned revision in a fixture `corpora.json` makes verification fail for a snapshot at another commit, inventory digest, or manifest digest.
16. Test262 discovery excludes a file named `a_FIXTURE_b.js` and a file named `x_FIXTURE.js`.

Expected test denominator: the existing controller tests plus the sixteen FP-0003 cases.

### Evidence corrections

`engineering/evidence/FP-0003/README.md` states that the WPT manifest tool exited with status 70 and that the controller exited with status 1.
ADR 0003 keeps the symbolic-link count only with a recorded listing command, or drops it.
No committed record contains a local user path.
The acceptance commands run exactly as the Acceptance section lists them, without environment overrides.
Both reviewers review the revision, and `fairpane-spec` explicitly approves the policy-root additions under `specs`.
