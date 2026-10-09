# FP-0002 task contract

## Identity

Task ID: `FP-0002`, "Design and test the protected qualification boundary".
Workstream: `laboratory`.
Base: the commit that records `FP-0001` acceptance.
Prerequisites: `FP-0001`.
Assigned role: `fairpane-core`, executed by the root integrator.

## Behavior

### Demonstration

A controller test forges a passing local receipt without running its gate.
`validateReceipt` accepts that forgery, because a workspace writer can recompute every local hash.
`engineering/decisions/0002-qualification-boundary.md` explains this limit and the boundary that replaces it.

### Protected trust policy

A trust policy is a JSON file outside the candidate workspace.

| Field | Content |
| --- | --- |
| `schema` | `fairpane-trust-policy` |
| `version` | `1` |
| `acceptance_policy_sha256` | Digest of the protected acceptance policy that results must use |
| `keys` | Trusted runner keys, each with `key_id`, `algorithm` `ed25519`, and a base64 SPKI DER `public_key` |

The verifier command rejects a trust-policy path that resolves inside the repository.
A workspace writer can edit any file in the repository, so such a file cannot be protected input.

### Candidate identity

A candidate is an immutable Git commit.
Its identity is the full commit ID and the commit's tree ID.
The verifier resolves both values from the object database and never reads the working tree for identity.

### Signed result records

A result envelope contains `payload`, the exact JSON text of the record, and one `signature`.
The signature names `key_id`, `algorithm` `ed25519`, and a base64 `value` over the UTF-8 bytes of `payload`.

| Payload field | Content |
| --- | --- |
| `schema`, `version` | `fairpane-result`, `1` |
| `candidate` | `commit` and `tree`, both 40-hex |
| `acceptance_policy_sha256` | The policy digest the runner used |
| `suite` | `id` and `manifest_sha256` |
| `counts` | `discovered`, `selected`, `pass`, `fail`, `unsupported`, `excluded`, `crash`, `timeout`, `harness_error` |
| `runner` | `key_id` |
| `issued_at` | UTC timestamp |

### Verifier

`tools/attest.mjs` exports `verifyResult(envelopeText, trustPolicy, expectedCandidate)`.
It has no dependency on the local receipt code and runs its own tests.
It returns a verified record or throws an error with one of these codes.

| Code | Condition |
| --- | --- |
| `malformed` | The envelope or payload is not valid JSON, has unknown fields, or lacks a required field. |
| `untrusted-key` | The signature names a key that the trust policy does not list. |
| `bad-signature` | The signature does not verify over the exact payload bytes. |
| `key-mismatch` | The payload runner key differs from the signature key. |
| `stale-candidate` | The payload candidate differs from the expected commit or tree. |
| `changed-policy` | The payload policy digest differs from the trust policy digest. |
| `zero-denominator` | `discovered` or `selected` is zero. |
| `inconsistent-counts` | A count is not a nonnegative safe integer, `selected` exceeds `discovered`, or the outcomes do not sum to `selected`. |

A truncated envelope fails as `malformed`.
A truncated payload fails as `bad-signature`, or as `malformed` when a trusted key signed it.

The payload must equal the `JSON.stringify` serialization of its own parsed value.
A payload with an unpaired surrogate, a duplicate key, or any other noncanonical spelling fails as `malformed`.
This rule gives each signed byte string exactly one meaning.

The controller command `attest-verify --trust-policy <path> --candidate <commit> <envelope>` runs the verifier.
It exits with status 1 and the error code on any rejection.
It adds two codes for its own inputs.
`unprotected-policy` reports a trust policy inside the repository.
`unknown-candidate` reports a candidate name that does not resolve to a commit.

### Release check

`release-check` stays fail-closed.
It reports that no protected runner, trust policy, or signed result set exists.
No metadata edit can produce release success.

## Exact test cases

1. A forged local receipt passes `validateReceipt` without gate execution.
2. A valid envelope signed by a trusted key verifies.
3. RFC 8032 test vector 1 verifies through the same key decoding path.
4. A signature from a key outside the trust policy fails as `untrusted-key`.
5. One changed payload byte fails as `bad-signature`.
6. A truncated envelope and a truncated payload each fail.
7. A trusted signature over a payload with a missing field fails as `malformed`.
8. A payload for another commit or tree fails as `stale-candidate`.
9. A payload with another policy digest fails as `changed-policy`.
10. Zero `discovered` and zero `selected` each fail as `zero-denominator`.
11. Negative, fractional, and mismatched counts fail as `inconsistent-counts`.
12. A runner key that differs from the signature key fails as `key-mismatch`.
13. `attest-verify` rejects a trust policy stored inside the repository.
14. Candidate identity resolution returns the commit and tree from a fixture repository and rejects an unknown commit.
15. `release-check` still exits with status 1.
16. A trusted signature over a noncanonical payload fails as `malformed`.
    The fixtures include an unpaired surrogate, a duplicate key, and added whitespace.

## Authority

Writable paths: `tools`, `tests`, `engineering/decisions`, and `engineering/evidence`.
Protected paths: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Required independent reviewer: `fairpane-review`.

## Acceptance

```text
node tools/fairpane.mjs run repo-check --evidence-dir engineering/evidence/FP-0002/gates
node tools/fairpane.mjs run controller-test --evidence-dir engineering/evidence/FP-0002/gates
node tools/fairpane.mjs record engineering/evidence/FP-0002/raw/release-check.log node tools/fairpane.mjs release-check
```

Required target execution: Windows x86_64 host execution.
Expected test denominator: the existing controller tests plus the sixteen cases above.

`tools/attest.test.mjs` holds the verifier's cases, and it runs both standalone and inside the controller test run.
It imports nothing from the local receipt code.

## Non-goals

- No protected runner, signing service, or key distribution exists in this task.
- The verifier does not decide release qualification; it authenticates and checks result records.
- Git object identity uses SHA-1 commit and tree IDs in this repository format.
  A SHA-256 object format or content digest is a later hardening step.

## Revisions

Revision 1 precedes the first committed implementation.
It adds the canonical payload rule and case 16.
A JavaScript string can hold an unpaired surrogate, which the UTF-8 conversion replaces with U+FFFD.
Two different payload texts could then share signed bytes and carry different meanings.
Duplicate keys create the same ambiguity across JSON parsers.
Revision 1 also names the two controller codes and the standalone test module.
