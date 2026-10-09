/**
 * Signed result verification for the protected qualification boundary.
 * This module depends only on Node built-ins, not on the local receipt code.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';

export const ERROR_CODES = Object.freeze(['malformed', 'untrusted-key', 'bad-signature', 'key-mismatch',
  'stale-candidate', 'changed-policy', 'zero-denominator', 'inconsistent-counts', 'unprotected-policy', 'unknown-candidate']);
export class AttestationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AttestationError';
    this.code = code;
  }
}
const fail = (code, message) => { throw new AttestationError(code, message); };
const HEX40 = /^[0-9a-f]{40}$/, HEX64 = /^[0-9a-f]{64}$/;
const OUTCOMES = Object.freeze(['pass', 'fail', 'unsupported', 'excluded', 'crash', 'timeout', 'harness_error']);
const COUNT_FIELDS = Object.freeze(['discovered', 'selected', ...OUTCOMES]);
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

function isObject(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
/** Require exactly these keys, so a record cannot carry fields that no verifier checks. */
function exactKeys(value, keys, where) {
  if (!isObject(value)) fail('malformed', `${where} must be an object.`);
  const actual = Object.keys(value).sort(), expected = [...keys].sort();
  for (const key of expected) if (!Object.hasOwn(value, key)) fail('malformed', `${where} lacks ${key}.`);
  for (const key of actual) if (!expected.includes(key)) fail('malformed', `${where} has an unknown field ${key}.`);
}
function parseJson(text, where) {
  if (typeof text !== 'string') fail('malformed', `${where} must be JSON text.`);
  try { return JSON.parse(text); } catch (e) { fail('malformed', `${where} is not valid JSON: ${e.message}`); }
}
/** Decode strict base64 so that equivalent spellings cannot hide a different byte string. */
function strictBase64(text, where) {
  if (typeof text !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(text) || text.length % 4 !== 0) fail('malformed', `${where} is not canonical base64.`);
  const bytes = Buffer.from(text, 'base64');
  if (bytes.toString('base64') !== text) fail('malformed', `${where} is not canonical base64.`);
  return bytes;
}
/** Decode a base64 SPKI DER Ed25519 public key. */
export function decodePublicKey(base64) {
  const der = strictBase64(base64, 'The public key');
  if (der.length !== 44 || !der.subarray(0, 12).equals(ED25519_SPKI_PREFIX)) fail('malformed', 'The public key is not an Ed25519 SPKI key.');
  const key = crypto.createPublicKey({ key: der, format: 'der', type: 'spki' });
  if (key.asymmetricKeyType !== 'ed25519') fail('malformed', 'The public key is not an Ed25519 key.');
  return key;
}
/** Verify an Ed25519 signature over exact bytes. */
export function verifyBytes(publicKey, bytes, signatureBase64) {
  const signature = strictBase64(signatureBase64, 'The signature');
  if (signature.length !== 64) fail('malformed', 'An Ed25519 signature has 64 bytes.');
  return crypto.verify(null, bytes, publicKey, signature);
}
/** Validate a trust policy object and index its keys. */
export function parseTrustPolicy(policy) {
  exactKeys(policy, ['schema', 'version', 'acceptance_policy_sha256', 'keys'], 'The trust policy');
  if (policy.schema !== 'fairpane-trust-policy' || policy.version !== 1) fail('malformed', 'The trust policy schema is unsupported.');
  if (!HEX64.test(policy.acceptance_policy_sha256)) fail('malformed', 'The trust policy needs a SHA-256 acceptance policy digest.');
  if (!Array.isArray(policy.keys) || policy.keys.length === 0) fail('malformed', 'The trust policy needs at least one key.');
  const keys = new Map();
  for (const entry of policy.keys) {
    exactKeys(entry, ['key_id', 'algorithm', 'public_key'], 'A trust policy key');
    if (typeof entry.key_id !== 'string' || !/^[A-Za-z0-9._-]{1,64}$/.test(entry.key_id)) fail('malformed', 'A key ID is invalid.');
    if (entry.algorithm !== 'ed25519') fail('malformed', `Key ${entry.key_id} uses an unsupported algorithm.`);
    if (keys.has(entry.key_id)) fail('malformed', `Key ${entry.key_id} appears twice.`);
    keys.set(entry.key_id, decodePublicKey(entry.public_key));
  }
  return { acceptance_policy_sha256: policy.acceptance_policy_sha256, keys };
}
/**
 * Load a trust policy that lies outside the candidate workspace.
 * A workspace writer can edit any file inside the workspace, so such a file cannot be protected input.
 */
export function loadTrustPolicy(policyPath, workspaceRoot) {
  const real = fs.realpathSync.native(policyPath), workspace = fs.realpathSync.native(workspaceRoot);
  const relative = path.relative(workspace, real);
  const outside = path.isAbsolute(relative) || relative === '..' || relative.startsWith(`..${path.sep}`);
  if (!outside) fail('unprotected-policy', 'The trust policy must come from outside the candidate workspace.');
  return parseTrustPolicy(parseJson(fs.readFileSync(real, 'utf8'), 'The trust policy'));
}
/** Read an envelope file as strict UTF-8 text, so ill-formed bytes cannot pass as replacement characters. */
export function readEnvelope(file) {
  const bytes = fs.readFileSync(file);
  try { return new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  catch { return fail('malformed', 'The envelope file is not well-formed UTF-8.'); }
}
/** Resolve an immutable candidate identity from the Git object database, never from the working tree. */
export function candidateIdentity(repository, commitish) {
  if (typeof commitish !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$/.test(commitish)) fail('unknown-candidate', 'The candidate name is invalid.');
  const git = args => spawnSync('git', ['-C', repository, ...args], { encoding: 'utf8', timeout: 30000, windowsHide: true });
  const commit = git(['rev-parse', '--verify', '--quiet', `${commitish}^{commit}`]);
  if (commit.error || commit.status !== 0 || !HEX40.test(commit.stdout.trim())) fail('unknown-candidate', `No commit resolves from ${commitish}.`);
  const id = commit.stdout.trim();
  const tree = git(['rev-parse', '--verify', '--quiet', `${id}^{tree}`]);
  if (tree.error || tree.status !== 0 || !HEX40.test(tree.stdout.trim())) fail('unknown-candidate', `Commit ${id} has no readable tree.`);
  return { commit: id, tree: tree.stdout.trim() };
}
function checkCounts(counts) {
  exactKeys(counts, COUNT_FIELDS, 'The counts');
  for (const field of COUNT_FIELDS) {
    if (!Number.isSafeInteger(counts[field]) || counts[field] < 0) fail('inconsistent-counts', `Count ${field} is not a nonnegative safe integer.`);
  }
  if (counts.discovered === 0 || counts.selected === 0) fail('zero-denominator', 'A result needs nonzero discovered and selected counts.');
  if (counts.selected > counts.discovered) fail('inconsistent-counts', 'More tests are selected than discovered.');
  const outcomes = OUTCOMES.reduce((sum, field) => sum + counts[field], 0);
  if (outcomes !== counts.selected) fail('inconsistent-counts', `Outcomes sum to ${outcomes}, but ${counts.selected} tests are selected.`);
}
/**
 * Verify a signed result envelope against protected trust input and the expected candidate.
 * Returns the verified record or throws an AttestationError with a stable code.
 */
export function verifyResult(envelopeText, trustPolicy, expectedCandidate) {
  const policy = trustPolicy?.keys instanceof Map ? trustPolicy : parseTrustPolicy(trustPolicy);
  const envelope = parseJson(envelopeText, 'The envelope');
  exactKeys(envelope, ['payload', 'signature'], 'The envelope');
  if (typeof envelope.payload !== 'string') fail('malformed', 'The payload must be JSON text.');
  exactKeys(envelope.signature, ['key_id', 'algorithm', 'value'], 'The signature');
  if (envelope.signature.algorithm !== 'ed25519') fail('malformed', 'The signature algorithm is unsupported.');
  const key = policy.keys.get(envelope.signature.key_id);
  if (!key) fail('untrusted-key', 'The trust policy does not list the signing key.');
  if (!verifyBytes(key, Buffer.from(envelope.payload, 'utf8'), envelope.signature.value)) fail('bad-signature', 'The signature does not match the payload bytes.');

  const record = parseJson(envelope.payload, 'The payload');
  // Re-serialization rejects unpaired surrogates, duplicate keys, and other spellings, so signed bytes carry one meaning.
  if (JSON.stringify(record) !== envelope.payload) fail('malformed', 'The payload is not in canonical JSON form.');
  exactKeys(record, ['schema', 'version', 'candidate', 'acceptance_policy_sha256', 'suite', 'counts', 'runner', 'issued_at'], 'The payload');
  if (record.schema !== 'fairpane-result' || record.version !== 1) fail('malformed', 'The payload schema is unsupported.');
  exactKeys(record.candidate, ['commit', 'tree'], 'The candidate');
  if (!HEX40.test(record.candidate.commit) || !HEX40.test(record.candidate.tree)) fail('malformed', 'The candidate needs full commit and tree IDs.');
  if (!HEX64.test(record.acceptance_policy_sha256)) fail('malformed', 'The payload needs a SHA-256 policy digest.');
  exactKeys(record.suite, ['id', 'manifest_sha256'], 'The suite');
  if (typeof record.suite.id !== 'string' || !record.suite.id || !HEX64.test(record.suite.manifest_sha256)) fail('malformed', 'The suite identity is invalid.');
  exactKeys(record.runner, ['key_id'], 'The runner');
  if (typeof record.issued_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(record.issued_at) || Number.isNaN(Date.parse(record.issued_at))) {
    fail('malformed', 'The issue time must be a UTC timestamp.');
  }
  if (record.runner.key_id !== envelope.signature.key_id) fail('key-mismatch', 'The payload names a different runner key than the signature.');
  if (record.candidate.commit !== expectedCandidate?.commit || record.candidate.tree !== expectedCandidate?.tree) {
    fail('stale-candidate', 'The result belongs to a different commit or tree.');
  }
  if (record.acceptance_policy_sha256 !== policy.acceptance_policy_sha256) fail('changed-policy', 'The result used a different acceptance policy.');
  checkCounts(record.counts);
  return { result: 'verified', key_id: envelope.signature.key_id, record };
}
/** Produce an envelope. Only a protected runner holds a trusted private key. */
export function signResult(record, privateKey, keyId) {
  const payload = JSON.stringify(record);
  const value = crypto.sign(null, Buffer.from(payload, 'utf8'), privateKey).toString('base64');
  return JSON.stringify({ payload, signature: { key_id: keyId, algorithm: 'ed25519', value } });
}
