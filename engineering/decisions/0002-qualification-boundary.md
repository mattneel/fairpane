# ADR 0002: The protected qualification boundary

Status: proposed until `fairpane-review` accepts task `FP-0002`.
Owner: the root integrator.
Date: 2026-10-09.
Related tasks: `FP-0002`, `FP-0027`, `FP-0033`.

## Problem

A writable local checker cannot attest its own author.
Any process that can write the repository can also recompute every hash that a local receipt contains.
Controller test case 1 demonstrates the limit: it forges a passing receipt for a gate that never ran, and `validateReceipt` accepts it.
Local receipts therefore remain integrity records, and they can never qualify a release.

## Decision

Release evidence consists of signed result records that a protected runner produces.
`tools/attest.mjs` verifies those records against protected trust input and an immutable candidate identity.

### Protected trust input

A trust policy is a JSON file with the schema `fairpane-trust-policy`, version 1.
It names the digest of the acceptance policy that results must use.
It lists trusted runner keys, each an Ed25519 public key in base64 SPKI DER form with a key ID.
The trust policy lives outside the candidate repository.
`attest-verify` rejects a trust-policy path that resolves inside the repository as `unprotected-policy`.
That check is a guard against an obvious mistake, not a security boundary.
Operating-system permissions on a separate runner account supply the actual boundary.

### Candidate identity

A candidate is an immutable Git commit.
Its identity is the full commit ID and the commit's tree ID, read from the object database.
The working tree never contributes to the identity.
This repository uses SHA-1 object IDs, so a SHA-256 object format or content digest remains a later hardening step.

### Signed result records

An envelope holds the exact payload text and one Ed25519 signature over its UTF-8 bytes.
The payload names the candidate, the acceptance-policy digest, the suite and its manifest digest, the runner key, the issue time, and the counts.
The counts are `discovered`, `selected`, `pass`, `fail`, `unsupported`, `excluded`, `crash`, `timeout`, and `harness_error`.

The payload must equal the `JSON.stringify` serialization of its own parsed value.
A JavaScript string can hold an unpaired surrogate, which the UTF-8 conversion replaces with U+FFFD.
Without the canonical rule, two payload texts could share signed bytes and carry different meanings.
Duplicate keys would create the same ambiguity across JSON parsers.
Controller test case 16 demonstrates the substitution, and the recorded mutation control shows that the canonical rule catches it.

### Verifier results

| Code | Condition |
| --- | --- |
| `malformed` | The envelope or payload is not valid, canonical, complete JSON, or it carries an unknown field. |
| `untrusted-key` | The trust policy does not list the signing key. |
| `bad-signature` | The signature does not verify over the exact payload bytes. |
| `key-mismatch` | The payload names another runner key than the signature. |
| `stale-candidate` | The payload names another commit or tree. |
| `changed-policy` | The payload names another acceptance-policy digest. |
| `zero-denominator` | `discovered` or `selected` is zero. |
| `inconsistent-counts` | A count is not a nonnegative safe integer, `selected` exceeds `discovered`, or the outcomes do not sum to `selected`. |
| `unprotected-policy` | The trust policy lies inside the repository. |
| `unknown-candidate` | The candidate name does not resolve to a commit. |

The verifier imports nothing from the local receipt code, and `tools/attest.test.mjs` runs its tests standalone.

## Consequences

`release-check` stays fail-closed.
It reports that no protected runner, trust policy, or signed result set exists.
A verified result authenticates one record, and release qualification still needs the frozen profile, the complete required result set, and the approvals that `docs/QUALIFICATION.md` lists.
Task `FP-0027` establishes the protected runner, key custody, and release procedure.
Continuous integration from `FP-0033` can later run a protected runner, but repository write access must never reach its signing key.

## Rejected alternatives

- Signing local receipts with a key stored in the repository gives every workspace writer the key.
- Trusting the working tree for candidate identity lets an uncommitted change pass as the candidate.
- Accepting any JSON spelling of a signed payload allows two meanings for one signature.

## Sources

- RFC 8032, Edwards-Curve Digital Signature Algorithm: <https://www.rfc-editor.org/rfc/rfc8032>.
- Contract and evidence: `engineering/evidence/FP-0002/`.
