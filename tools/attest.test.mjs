#!/usr/bin/env node
/**
 * Attestation verifier tests. They import nothing from the local receipt code, so a defect there cannot hide here.
 * Run standalone with `node tools/attest.test.mjs`, or through `node tools/fairpane.mjs test`.
 */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { AttestationError, candidateIdentity, candidateRepository, decodePublicKey, enclosingGitDirectories, loadTrustPolicy, signResult, verifyBytes, verifyResult } from './attest.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SPKI_ED25519_PREFIX = '302a300506032b6570032100';
const POLICY_DIGEST = sha256Hex('fixture acceptance policy');
const CANDIDATE = Object.freeze({ commit: '1'.repeat(40), tree: '2'.repeat(40) });

function sha256Hex(text) { return crypto.createHash('sha256').update(text).digest('hex'); }
function keyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return { privateKey, publicKey: publicKey.export({ type: 'spki', format: 'der' }).toString('base64') };
}
const runner = keyPair(), second = keyPair(), outsider = keyPair();
function trustPolicy(keys = [['runner-1', runner]]) {
  return { schema: 'fairpane-trust-policy', version: 1, acceptance_policy_sha256: POLICY_DIGEST,
    keys: keys.map(([key_id, pair]) => ({ key_id, algorithm: 'ed25519', public_key: pair.publicKey })) };
}
function record(changes = {}) {
  return { schema: 'fairpane-result', version: 1, candidate: { ...CANDIDATE }, acceptance_policy_sha256: POLICY_DIGEST,
    suite: { id: 'fixture-suite', manifest_sha256: sha256Hex('fixture manifest') },
    counts: { discovered: 10, selected: 8, pass: 5, fail: 1, unsupported: 1, excluded: 0, crash: 1, timeout: 0, harness_error: 0 },
    runner: { key_id: 'runner-1' }, issued_at: '2026-10-09T01:00:00.000Z', ...changes };
}
function withCounts(changes) { const r = record(); return { ...r, counts: { ...r.counts, ...changes } }; }
/** Sign exact payload text, which lets a test sign text that `signResult` would never produce. */
function signText(payload, privateKey, keyId = 'runner-1') {
  const value = crypto.sign(null, Buffer.from(payload, 'utf8'), privateKey).toString('base64');
  return JSON.stringify({ payload, signature: { key_id: keyId, algorithm: 'ed25519', value } });
}
function rejects(fn, code) {
  let error = null;
  try { fn(); } catch (e) { error = e; }
  assert.ok(error instanceof AttestationError, `Expected rejection ${code}, got ${error ? error.message : 'success'}`);
  assert.equal(error.code, code, error.message);
}
const temporary = [];
function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-attest-'));
  temporary.push(dir);
  return dir;
}
function runGit(dir, args) {
  const r = spawnSync('git', ['-C', dir, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.autocrlf=false', ...args], { encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 0, `git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout.trim();
}
function controller(args) {
  return spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), ...args], { cwd: root, encoding: 'utf8', windowsHide: true });
}
/** Build a two-commit repository whose commits have different trees. */
function fixtureRepository() {
  const dir = temp();
  runGit(dir, ['init', '-q']);
  fs.writeFileSync(path.join(dir, 'file.txt'), 'first\n');
  runGit(dir, ['add', 'file.txt']);
  runGit(dir, ['commit', '-q', '-m', 'first']);
  const first = runGit(dir, ['rev-parse', 'HEAD']), firstTree = runGit(dir, ['rev-parse', 'HEAD^{tree}']);
  fs.writeFileSync(path.join(dir, 'file.txt'), 'second\n');
  runGit(dir, ['commit', '-q', '-a', '-m', 'second']);
  return { dir, first, firstTree, second: runGit(dir, ['rev-parse', 'HEAD']), secondTree: runGit(dir, ['rev-parse', 'HEAD^{tree}']) };
}
/** Name the outcome of a verification, so one assertion can report every fixture's outcome. */
function codeOf(fn) {
  try { fn(); return 'verified'; } catch (e) { return e instanceof AttestationError ? e.code : `error: ${e.message}`; }
}

export const attestationCases = [
  ['2: A valid envelope signed by a trusted key verifies', () => {
    const verified = verifyResult(signResult(record(), runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE);
    assert.equal(verified.result, 'verified');
    assert.equal(verified.key_id, 'runner-1');
    assert.deepEqual(verified.record, record());
  }],
  ['3: RFC 8032 test vector 1 verifies through the same key decoding path', () => {
    const publicKey = Buffer.from(SPKI_ED25519_PREFIX + 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex');
    const signature = Buffer.from('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b', 'hex');
    const key = decodePublicKey(publicKey.toString('base64'));
    assert.equal(verifyBytes(key, Buffer.alloc(0), signature.toString('base64')), true);
    assert.equal(verifyBytes(key, Buffer.from([0x72]), signature.toString('base64')), false);
  }],
  ['4: A key outside the trust policy fails, whether it names itself or a trusted key', () => {
    rejects(() => verifyResult(signResult(record({ runner: { key_id: 'outsider' } }), outsider.privateKey, 'outsider'), trustPolicy(), CANDIDATE), 'untrusted-key');
    rejects(() => verifyResult(signResult(record(), outsider.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'bad-signature');
  }],
  ['5: One changed payload byte fails as bad-signature', () => {
    const envelope = JSON.parse(signResult(record(), runner.privateKey, 'runner-1'));
    const changed = envelope.payload.replace('"pass":5', '"pass":6');
    assert.notEqual(changed, envelope.payload);
    rejects(() => verifyResult(JSON.stringify({ ...envelope, payload: changed }), trustPolicy(), CANDIDATE), 'bad-signature');
  }],
  ['6: A truncated envelope and a truncated payload each fail', () => {
    const text = signResult(record(), runner.privateKey, 'runner-1'), envelope = JSON.parse(text);
    rejects(() => verifyResult(text.slice(0, -1), trustPolicy(), CANDIDATE), 'malformed');
    rejects(() => verifyResult(JSON.stringify({ ...envelope, payload: envelope.payload.slice(0, -1) }), trustPolicy(), CANDIDATE), 'bad-signature');
    rejects(() => verifyResult(signText(envelope.payload.slice(0, -1), runner.privateKey), trustPolicy(), CANDIDATE), 'malformed');
  }],
  ['7: A trusted signature over a payload with a missing, unknown, or mistyped field fails as malformed', () => {
    const { suite: _suite, ...missingSuite } = record();
    const { harness_error: _harness, ...missingCount } = record().counts;
    const payloads = [missingSuite, record({ counts: missingCount }), record({ note: 'unchecked' }),
      record({ suite: { id: 'x', manifest_sha256: [sha256Hex('fixture manifest')] } }),
      record({ candidate: { commit: [CANDIDATE.commit], tree: CANDIDATE.tree } }),
      record({ acceptance_policy_sha256: [POLICY_DIGEST] }), record({ runner: { key_id: 7 } }),
      record({ issued_at: '2026-02-30T00:00:00.000Z' })];
    for (const payload of payloads) rejects(() => verifyResult(signResult(payload, runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'malformed');
    rejects(() => verifyResult(signResult(record(), runner.privateKey, 7), trustPolicy(), CANDIDATE), 'malformed');
  }],
  ['8: A payload for another commit or tree fails as stale-candidate', () => {
    for (const candidate of [{ commit: '3'.repeat(40), tree: CANDIDATE.tree }, { commit: CANDIDATE.commit, tree: '4'.repeat(40) }]) {
      rejects(() => verifyResult(signResult(record({ candidate }), runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'stale-candidate');
    }
  }],
  ['9: A payload with another policy digest fails as changed-policy', () => {
    const changed = record({ acceptance_policy_sha256: sha256Hex('another policy') });
    rejects(() => verifyResult(signResult(changed, runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'changed-policy');
  }],
  ['10: Zero discovered and zero selected each fail as zero-denominator', () => {
    const zero = { discovered: 0, selected: 0, pass: 0, fail: 0, unsupported: 0, excluded: 0, crash: 0, timeout: 0, harness_error: 0 };
    rejects(() => verifyResult(signResult(withCounts(zero), runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'zero-denominator');
    rejects(() => verifyResult(signResult(withCounts({ ...zero, discovered: 5 }), runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'zero-denominator');
  }],
  ['11: Negative, fractional, unsafe, and mismatched counts fail as inconsistent-counts', () => {
    for (const changes of [{ pass: -1, fail: 2 }, { pass: 4.5, fail: 1.5 }, { discovered: 2 ** 53 }, { pass: 6 }, { discovered: 7 }, { pass: '5' }]) {
      rejects(() => verifyResult(signResult(withCounts(changes), runner.privateKey, 'runner-1'), trustPolicy(), CANDIDATE), 'inconsistent-counts');
    }
  }],
  ['12: A runner key that differs from the signature key fails as key-mismatch', () => {
    const policy = trustPolicy([['runner-1', runner], ['runner-2', second]]);
    rejects(() => verifyResult(signResult(record({ runner: { key_id: 'runner-2' } }), runner.privateKey, 'runner-1'), policy, CANDIDATE), 'key-mismatch');
  }],
  ['13: attest-verify checks a candidate repository from a separate verifier location and rejects a trust policy inside it', () => {
    const candidate = fixtureRepository(), dir = temp();
    const envelopeFile = path.join(dir, 'result.json'), outsidePolicy = path.join(dir, 'trust-policy.json');
    const insidePolicy = path.join(candidate.dir, 'trust-policy.json');
    const identity = { commit: candidate.first, tree: candidate.firstTree };
    fs.writeFileSync(envelopeFile, signResult(record({ candidate: identity }), runner.privateKey, 'runner-1'));
    fs.writeFileSync(outsidePolicy, JSON.stringify(trustPolicy()));
    fs.writeFileSync(insidePolicy, JSON.stringify(trustPolicy()));
    const verify = (repository, policy, commit) =>
      controller(['attest-verify', '--repository', repository, '--trust-policy', policy, '--candidate', commit, envelopeFile]);
    const inside = verify(candidate.dir, insidePolicy, candidate.first);
    assert.equal(inside.status, 1, inside.stderr);
    assert.equal(JSON.parse(inside.stdout).code, 'unprotected-policy');
    const linked = path.join(dir, 'linked'), gitDirectoryPolicy = path.join(candidate.dir, '.git', 'trust-policy.json');
    runGit(candidate.dir, ['worktree', 'add', '-q', '--detach', linked, candidate.first]);
    fs.writeFileSync(gitDirectoryPolicy, JSON.stringify(trustPolicy()));
    const shared = verify(linked, gitDirectoryPolicy, candidate.first);
    assert.equal(shared.status, 1, shared.stderr);
    assert.equal(JSON.parse(shared.stdout).code, 'unprotected-policy');
    fs.mkdirSync(path.join(candidate.dir, 'sub'));
    const subdirectory = verify(path.join(candidate.dir, 'sub'), outsidePolicy, candidate.first);
    assert.equal(subdirectory.status, 1);
    assert.equal(subdirectory.stdout, '');
    assert.match(subdirectory.stderr, /top-level directory/);
    const outside = verify(candidate.dir, outsidePolicy, candidate.first);
    assert.equal(outside.status, 0, outside.stdout + outside.stderr);
    const verified = JSON.parse(outside.stdout);
    assert.equal(verified.result, 'verified');
    assert.equal(verified.verifier, 'outside-candidate');
    assert.deepEqual(verified.candidate, identity);
    const own = runGit(root, ['rev-parse', 'HEAD']), ownTree = runGit(root, ['rev-parse', 'HEAD^{tree}']);
    fs.writeFileSync(envelopeFile, signResult(record({ candidate: { commit: own, tree: ownTree } }), runner.privateKey, 'runner-1'));
    const advisory = verify(root, outsidePolicy, own);
    assert.equal(advisory.status, 3, advisory.stdout + advisory.stderr);
    assert.equal(JSON.parse(advisory.stdout).result, 'verified-advisory');
    assert.equal(JSON.parse(advisory.stdout).verifier, 'inside-candidate');
  }],
  ['14: Candidate identity comes from Git objects, ignores replace refs and inherited Git variables, and rejects other names', () => {
    const candidate = fixtureRepository(), other = fixtureRepository();
    const expected = { commit: candidate.first, tree: candidate.firstTree };
    assert.deepEqual(candidateIdentity(candidate.dir, candidate.first), expected);
    fs.writeFileSync(path.join(candidate.dir, 'file.txt'), 'uncommitted change\n');
    assert.deepEqual(candidateIdentity(candidate.dir, candidate.first), expected);
    runGit(candidate.dir, ['replace', candidate.first, candidate.second]);
    assert.equal(runGit(candidate.dir, ['rev-parse', `${candidate.first}^{tree}`]), candidate.secondTree);
    assert.deepEqual(candidateIdentity(candidate.dir, candidate.first), expected);
    const inherited = process.env.GIT_DIR;
    process.env.GIT_DIR = path.join(other.dir, '.git');
    try { assert.deepEqual(candidateIdentity(candidate.dir, candidate.first), expected); }
    finally { if (inherited === undefined) delete process.env.GIT_DIR; else process.env.GIT_DIR = inherited; }
    for (const name of ['f'.repeat(40), candidate.first.slice(0, 12), 'HEAD', '-h', '']) rejects(() => candidateIdentity(candidate.dir, name), 'unknown-candidate');
    runGit(candidate.dir, ['tag', '-a', 'fixture-tag', '-m', 'fixture tag', candidate.first]);
    rejects(() => candidateIdentity(candidate.dir, runGit(candidate.dir, ['rev-parse', 'fixture-tag'])), 'unknown-candidate');
    fs.mkdirSync(path.join(candidate.dir, 'nested'));
    assert.match(codeOf(() => candidateRepository(path.join(candidate.dir, 'nested'))), /^error: .*top-level directory/);
    // The temporary directory can sit inside a work tree, such as a dotfiles checkout, so Git itself decides the expected tool error.
    const outside = temp(), gitless = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^GIT_/i.test(name)));
    const probe = spawnSync('git', ['-C', outside, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', env: gitless, windowsHide: true });
    assert.match(codeOf(() => candidateRepository(outside)),
      probe.status === 0 ? /^error: .*top-level directory/ : /^error: The candidate repository cannot be read/);
    const searchPath = process.env.PATH;
    process.env.PATH = '';
    try { assert.match(codeOf(() => candidateIdentity(candidate.dir, candidate.first)), /^error: No git executable exists on PATH/); }
    finally { process.env.PATH = searchPath; }
  }],
  ['16: A trusted signature over a noncanonical payload fails as malformed', () => {
    const canonical = JSON.stringify(record());
    const replacement = canonical.replace('fixture-suite', 'fixture-\uFFFDsuite');
    const unpaired = canonical.replace('fixture-suite', 'fixture-\uD800suite');
    assert.equal(Buffer.from(unpaired, 'utf8').equals(Buffer.from(replacement, 'utf8')), true);
    const signedReplacement = JSON.parse(signText(replacement, runner.privateKey));
    assert.equal(verifyResult(JSON.stringify(signedReplacement), trustPolicy(), CANDIDATE).record.suite.id, 'fixture-\uFFFDsuite');
    const envelopes = [JSON.stringify({ ...signedReplacement, payload: unpaired }),
      signText(canonical.replace('"version":1,', '"version":1,"version":1,'), runner.privateKey),
      signText(JSON.stringify(record(), null, 1), runner.privateKey)];
    assert.deepEqual(envelopes.map(text => codeOf(() => verifyResult(text, trustPolicy(), CANDIDATE))), ['malformed', 'malformed', 'malformed']);
  }],
  ['FP-0051 1: A verifier copy inside a linked work tree of the candidate reports an advisory result', () => {
    const candidate = fixtureRepository(), dir = temp(), linked = path.join(dir, 'linked');
    runGit(candidate.dir, ['worktree', 'add', '-q', '--detach', linked, candidate.first]);
    fs.cpSync(path.join(root, 'tools'), path.join(linked, 'tools'), { recursive: true });
    const envelopeFile = path.join(dir, 'result.json'), policyFile = path.join(dir, 'trust-policy.json');
    fs.writeFileSync(envelopeFile, signResult(record({ candidate: { commit: candidate.first, tree: candidate.firstTree } }), runner.privateKey, 'runner-1'));
    fs.writeFileSync(policyFile, JSON.stringify(trustPolicy()));
    const r = spawnSync(process.execPath, [path.join(linked, 'tools/fairpane.mjs'), 'attest-verify', '--repository', candidate.dir,
      '--trust-policy', policyFile, '--candidate', candidate.first, envelopeFile], { cwd: dir, encoding: 'utf8', windowsHide: true });
    assert.equal(r.status, 3, r.stdout + r.stderr);
    assert.equal(JSON.parse(r.stdout).result, 'verified-advisory');
  }],
  ['FP-0051 2: enclosingGitDirectories collects the common directory of every enclosing .git entry', () => {
    const candidate = fixtureRepository(), dir = temp(), linked = path.join(dir, 'linked');
    const common = fs.realpathSync.native(path.join(candidate.dir, '.git'));
    fs.mkdirSync(path.join(candidate.dir, 'sub', 'deeper'), { recursive: true });
    runGit(candidate.dir, ['worktree', 'add', '-q', '--detach', linked, candidate.first]);
    for (const where of [candidate.dir, path.join(candidate.dir, 'sub', 'deeper'), linked]) {
      assert.equal(enclosingGitDirectories(where)[0], common, where);
    }
    // A repository nested inside a linked work tree still lies inside a work tree of the candidate.
    const nested = path.join(linked, 'nested');
    fs.mkdirSync(nested);
    runGit(nested, ['init', '-q']);
    const found = enclosingGitDirectories(nested);
    assert.equal(found[0], fs.realpathSync.native(path.join(nested, '.git')));
    assert.ok(found.includes(common), JSON.stringify(found));
    // A .git directory whose commondir file names the candidate's directory shares it.
    const shared = temp();
    fs.mkdirSync(path.join(shared, '.git'));
    fs.writeFileSync(path.join(shared, '.git', 'commondir'), `${common}\r\n`);
    assert.equal(enclosingGitDirectories(shared)[0], common);
    const broken = temp();
    fs.writeFileSync(path.join(broken, '.git'), 'not a gitdir line\n');
    assert.match(codeOf(() => enclosingGitDirectories(broken)), /^error: .*does not name a Git directory/);
  }],
  ['FP-0051 3: An unreadable commit object is a tool error, and a missing or non-commit object is unknown-candidate', () => {
    const candidate = fixtureRepository();
    const looseOf = (repo, id) => path.join(repo.dir, '.git', 'objects', id.slice(0, 2), id.slice(2));
    fs.chmodSync(looseOf(candidate, candidate.first), 0o644);
    fs.writeFileSync(looseOf(candidate, candidate.first), 'not a zlib stream');
    assert.match(codeOf(() => candidateIdentity(candidate.dir, candidate.first)), /^error: Git could not look up the candidate commit/);
    rejects(() => candidateIdentity(candidate.dir, 'f'.repeat(40)), 'unknown-candidate');
    rejects(() => candidateIdentity(candidate.dir, candidate.secondTree), 'unknown-candidate');
    // Another commit's object under this commit's ID fails Git's hash check, so the commit exists but cannot be read.
    const mismatch = fixtureRepository();
    fs.chmodSync(looseOf(mismatch, mismatch.first), 0o644);
    fs.copyFileSync(looseOf(mismatch, mismatch.second), looseOf(mismatch, mismatch.first));
    assert.match(codeOf(() => candidateIdentity(mismatch.dir, mismatch.first)), /^error: Commit \w+ exists, but Git cannot read it/);
    const bogus = spawnSync('git', ['-C', candidate.dir, 'hash-object', '-t', 'commit', '--literally', '-w', '--stdin'],
      { input: 'not a commit\n', encoding: 'utf8', windowsHide: true });
    assert.equal(bogus.status, 0, bogus.stderr);
    assert.match(codeOf(() => candidateIdentity(candidate.dir, bogus.stdout.trim())), /^error: Commit \w+ exists, but Git cannot read it/);
  }],
  ['FP-0051 4: A policy path that passes through the candidate fails, however its root is spelled', () => {
    const candidate = fixtureRepository(), outside = temp();
    fs.writeFileSync(path.join(outside, 'trust-policy.json'), JSON.stringify(trustPolicy()));
    const linkType = process.platform === 'win32' ? 'junction' : 'dir';
    fs.symlinkSync(outside, path.join(candidate.dir, 'link'), linkType);
    const locations = [fs.realpathSync.native(candidate.dir), fs.realpathSync.native(path.join(candidate.dir, '.git'))];
    rejects(() => loadTrustPolicy(path.join(candidate.dir, 'link', 'trust-policy.json'), locations), 'unprotected-policy');
    rejects(() => loadTrustPolicy(path.join(locations[0], 'link', 'trust-policy.json'), locations), 'unprotected-policy');
    // An alias outside the candidate that resolves to its root spells the same path without the root's own name.
    const alias = path.join(temp(), 'alias');
    fs.symlinkSync(candidate.dir, alias, linkType);
    rejects(() => loadTrustPolicy(path.join(alias, 'link', 'trust-policy.json'), locations), 'unprotected-policy');
    assert.equal(loadTrustPolicy(path.join(outside, 'trust-policy.json'), locations).keys.size, 1);
  }],
].map(([name, fn]) => ({ name, fn }));

export function removeAttestationFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of attestationCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeAttestationFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${attestationCases.length}\n# tests ${attestationCases.length}\n# pass ${attestationCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
