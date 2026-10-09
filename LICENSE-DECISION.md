# Outbound license decision

## Status

The owner did not select a license in the founding request.
This bootstrap does not infer a binding legal decision from the phrase "in the commons."
No public release is authorized until the owner records the outbound license.

Apache-2.0 is the proposed default for first-party code.
Its official text includes patent and redistribution provisions. [S20]
A copyleft policy is a distinct alternative with different goals and obligations.
This document is a decision placeholder, not legal advice or an executed contributor agreement.

## Required decision

1. Select the outbound license before public distribution.
2. Add its exact official text as `LICENSE`.
3. Record applicable copyright and attribution information without inventing ownership.
4. Define contribution and provenance rules.
5. Update the license decision in the qualification policy.

## Development boundary

Local engineering tasks continue while the decision remains open.
Agents cannot import third-party source without a compatible, recorded basis.
Standards data and test corpora retain their own license records.
External conformance corpora stay outside the repository as pinned snapshots.

On 2026-10-09, the owner approved third-party data in the public repository.
Unicode data files under the Unicode License v3 and test fonts under the SIL Open Font License 1.1 may enter it.
Each such file keeps its license text beside it and a per-file provenance record, as `specs/IMPORT_REQUIREMENTS.md` requires.
`engineering/evidence/FP-0013/owner-answers.log` records the question and the answer.

See `docs/SOURCES.md` for [S20].
