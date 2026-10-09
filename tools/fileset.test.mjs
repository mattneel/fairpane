#!/usr/bin/env node
/**
 * File-set corpus, record, and capability tests for FP-0013 cases 41 through 49, revision 1 cases 53 through 55, the file-set part of FP-0052 case 6, and FP-0108 cases 5 and 6.
 * Run standalone with `node tools/fileset.test.mjs`, or through `node tools/fairpane.mjs test`.
 * Fetches read `file://` fixture sources that only these tests enable, and download cases pass an in-memory `fetch`; no case uses the network.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { readJson, writeJson } from './lib.mjs';
import { classifyCorpus, deriveCorpus, fetchCorpus, verifyCorpus } from './corpus.mjs';
import { FILE_SET_IDS, crc32, gitBlobId, readZip, sfntCopyright, validateFileSetRecord, zipInventory } from './fileset.mjs';
// Revision 1 functions are read through the namespace, so a missing export fails only the case that uses it.
import * as fileset from './fileset.mjs';
import { TEXT_FONT_OBLIGATIONS, validateCapabilityRecord } from './capabilities.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const temporary = [];
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-fileset-'));
  temporary.push(dir); return dir;
}

/** Run each named part, then fail with the message of every failing part, so one run reports each part that fails. */
async function parts(list) {
  const failures = [];
  for (const [label, fn] of list) {
    try { await fn(); } catch (e) { failures.push(`${label}: ${String(e.message).replace(/\s+/g, ' ').slice(0, 400)}`); }
  }
  if (failures.length) throw new Error(`${failures.length} of ${list.length} parts failed:\n- ${failures.join('\n- ')}`);
}

/**
 * One ZIP member: its local record (header, name, local extra field, and data) and its central directory entry.
 * `e` is `{ path, data, method }` or `{ path, directory: true }`. `crc`, `size`, `compressedSize`, `flags`, `external`, `madeBy`,
 * and `localExtra` override header fields, and `edit(central, local)` may change both headers before they are joined.
 */
export function zipMember(e, offset) {
  const name = Buffer.from(e.path, 'utf8');
  const data = e.directory ? Buffer.alloc(0) : Buffer.from(e.data);
  const method = e.method ?? 0;
  const stored = method === 8 ? zlib.deflateRawSync(data) : data;
  const crc = e.crc ?? crc32(data), localExtra = e.localExtra ?? Buffer.alloc(0);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(e.flags ?? 0, 6);
  local.writeUInt16LE(method, 8); local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(e.compressedSize ?? stored.length, 18); local.writeUInt32LE(e.size ?? data.length, 22);
  local.writeUInt16LE(name.length, 26); local.writeUInt16LE(localExtra.length, 28);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(e.madeBy ?? 20, 4); central.writeUInt16LE(20, 6);
  central.writeUInt16LE(e.flags ?? 0, 8); central.writeUInt16LE(method, 10); central.writeUInt32LE(crc, 16);
  central.writeUInt32LE(e.compressedSize ?? stored.length, 20); central.writeUInt32LE(e.size ?? data.length, 24);
  central.writeUInt16LE(name.length, 28); central.writeUInt32LE(e.external ?? (e.directory ? 0x10 : 0), 38); central.writeUInt32LE(offset, 42);
  e.edit?.(central, local);
  return { local: Buffer.concat([local, name, localExtra, stored]), central: Buffer.concat([central, name]) };
}

/**
 * Write a ZIP archive from `zipMember` entries in order. An entry with `localOffset` writes no local record of its own;
 * its central directory entry names that offset instead.
 */
export function makeZip(entries, { truncateCentral = 0 } = {}) {
  const locals = [], centrals = [];
  let offset = 0;
  for (const e of entries) {
    const m = zipMember(e, e.localOffset ?? offset);
    if (e.localOffset === undefined) { locals.push(m.local); offset += m.local.length; }
    centrals.push(m.central);
  }
  let directory = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8); eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(directory.length, 12); eocd.writeUInt32LE(offset, 16);
  if (truncateCentral) directory = directory.subarray(0, directory.length - truncateCentral);
  return Buffer.concat([...locals, directory, eocd]);
}

const UNPINNED_FIELDS = ['revision', 'license_record', 'inventory_sha256', 'manifest_sha256', 'local_path'];
function unpinnedCorpora() {
  const policy = readJson(path.join(root, 'specs/corpora.json'));
  for (const c of policy.corpora) for (const field of UNPINNED_FIELDS) if (field in c) c[field] = null;
  return policy;
}

const SCRIPTS = '# Scripts-18.0.0.txt\n0041..005A ; Latin\n';
const DERIVED = '# DerivedBidiClass-18.0.0.txt\n'.repeat(20);
const LICENSE = 'UNICODE LICENSE V3\n\nFixture license text.\n';

/** A repository root, a corpora root, and `file://` sources for a fixture `unicode` file-set corpus. */
function fileSetFixture() {
  const dir = temp(), corporaDir = temp(), upstream = temp();
  fs.mkdirSync(path.join(dir, 'specs'), { recursive: true });
  writeJson(path.join(dir, 'specs/corpora.json'), unpinnedCorpora());
  const zip = makeZip([
    { path: 'Scripts.txt', data: SCRIPTS },
    { path: 'extracted/', directory: true },
    { path: 'extracted/DerivedBidiClass.txt', data: DERIVED, method: 8 },
    { path: 'ReadMe.txt', data: 'Read me.\n' },
  ]);
  const put = (name, data) => { const file = path.join(upstream, name); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, data); return pathToFileURL(file).href; };
  const urls = { zip: put('UCD.zip', zip), license: put('license.txt', LICENSE), scripts: put('published/Scripts.txt', SCRIPTS) };
  const rule = {
    version: '18.0.0',
    discovery: 'zip-members',
    sources: [
      { id: 'ucd', url: urls.zip, kind: 'zip', local: 'sources/UCD.zip', release: { name: '18.0.0', repository: null, tag: null, commit: null },
        size: zip.length, published_digest: `sha256:${sha256(zip)}`, git_blob: null },
      { id: 'license', url: urls.license, kind: 'file', local: 'sources/license.txt', release: { name: 'Unicode License v3', repository: null, tag: null, commit: null },
        size: null, published_digest: null, git_blob: gitBlobId(Buffer.from(LICENSE)) },
    ],
    selected: [
      { source: 'ucd', member: 'Scripts.txt', path: 'src/unicode/ucd/Scripts.txt', role: 'data', published_url: urls.scripts },
      { source: 'ucd', member: 'extracted/DerivedBidiClass.txt', path: 'src/unicode/ucd/extracted/DerivedBidiClass.txt', role: 'data', published_url: null },
      { source: 'license', member: null, path: 'src/unicode/ucd/license.txt', role: 'license', published_url: null },
    ],
    derived: [],
  };
  const options = (extra = {}) => ({ corporaDir, rules: { unicode: extra.rule ?? rule }, allowFileSources: true });
  const recordFile = path.join(dir, 'specs/snapshots/unicode.json');
  return {
    dir, corporaDir, upstream, rule, urls, recordFile, zip,
    applicabilityFile: path.join(dir, 'specs/applicability/unicode.json'),
    fetch: (changed, extra = {}) => fetchCorpus(dir, 'unicode', { ...options({ rule: changed }), ...extra }),
    classify: () => classifyCorpus(dir, 'unicode', { corporaDir, allowFileSources: true }),
    verify: () => verifyCorpus(dir, 'unicode', { corporaDir, allowFileSources: true }),
  };
}

/** Byte snapshots of every file under each directory, keyed by path. */
function snapshot(...dirs) {
  const out = {};
  const walk = d => {
    if (!fs.existsSync(d)) return;
    for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, entry.name);
      if (entry.isDirectory()) walk(p); else out[p] = sha256(fs.readFileSync(p));
    }
  };
  for (const d of dirs) walk(d);
  return out;
}

/** Give the corpora other than `id` a counted applicability record, so every denominator exists. */
function otherApplicability(dir, id) {
  for (const other of ['test262', 'wpt']) if (other !== id) {
    writeJson(path.join(dir, 'specs/applicability', `${other}.json`), { schema_version: 1, corpus: other, commit: 'a'.repeat(40), status: 'counted',
      discovery: { rule: 'Fixture rule.' }, discovered: 1, selected: 0, excluded: [], unclassified: 1, breakdown: { by: 'fixture', counts: { fixture: 1 } } });
  }
  for (const other of FILE_SET_IDS) if (other !== id) {
    writeJson(path.join(dir, 'specs/applicability', `${other}.json`), { schema_version: 1, corpus: other, version: 'fixture', inventories: { fixture: 'a'.repeat(64) },
      status: 'counted', discovery: { rule: 'Fixture rule.' }, discovered: 1, selected: 0, excluded: [], unclassified: 1, breakdown: { by: 'fixture', counts: { fixture: 1 } } });
  }
}

/** A minimal valid file-set record with a zip source, a file source, a font, its license, and a derived font. */
function goodRecord() {
  const h = c => c.repeat(64);
  return {
    schema_version: 1, corpus: 'opentype-fixtures', kind: 'file-set', upstream: 'https://learn.microsoft.com/en-us/typography/opentype/spec/',
    version: 'fixtures-1', retrieved_at: '2026-10-09T00:00:00.000Z',
    sources: [
      { id: 'fonts', url: 'https://example.org/fonts.zip', kind: 'zip', release: { name: 'v1', repository: 'https://github.com/example/fonts', tag: 'v1', commit: 'a'.repeat(40) },
        size: 10, sha256: h('1'), published_digest: null, git_blob: null, local_path: '<corpora-root>/opentype-fixtures/sources/fonts.zip',
        inventory: { entry_count: 2, total_bytes: 9, sha256: h('2') } },
      { id: 'big', url: 'https://example.org/Big.otf', kind: 'file', release: { name: 'v2', repository: null, tag: null, commit: null },
        size: 20, sha256: h('3'), published_digest: null, git_blob: 'b'.repeat(40), local_path: '<corpora-root>/opentype-fixtures/sources/Big.otf' },
    ],
    selected: [
      { source: 'fonts', member: 'A.ttf', path: 'tests/text/fonts/a/A.ttf', size: 5, sha256: h('4'), role: 'font', published_url: null,
        license_path: 'tests/text/fonts/a/OFL.txt', license_name: 'SIL Open Font License, Version 1.1', copyright: 'Copyright 2022 Fixture', reserved_font_names: [] },
      { source: 'fonts', member: 'OFL.txt', path: 'tests/text/fonts/a/OFL.txt', size: 4, sha256: h('5'), role: 'license', published_url: null },
    ],
    derived: [
      { path: 'tests/text/fonts/b/b.otf', size: 3, sha256: h('6'), input: { source: 'big', sha256: h('3') },
        tool: { name: 'fontTools', version: '4.66.1', wheel_url: 'https://example.org/fonttools.whl', wheel_sha256: h('7'), python: '3.13.15' },
        argv: ['-m', 'fontTools.subset', '<input>'], license_path: 'tests/text/fonts/a/OFL.txt', copyright: 'Copyright Fixture',
        reserved_font_names: ['Source'], rfn_resolution: 'Fixture resolution.' },
    ],
  };
}

export const fileSetCases = [
  ['FP-0013 case 41: a zip with two stored members, one deflated member, and one directory yields the hand-computed inventory', () => {
    const zip = readZip(makeZip([
      { path: 'b.txt', data: 'bee\n' },
      { path: 'dir/', directory: true },
      { path: 'dir/c.txt', data: 'sea sea sea sea\n', method: 8 },
      { path: 'a.txt', data: 'ay\n' },
    ]));
    const inventory = zipInventory(zip, { keepLines: true });
    // Hand-computed lines: the SHA-256 and byte count of each literal member text, sorted by path, with the directory left out.
    const lines = [
      `${sha256('ay\n')}\t3\ta.txt\n`,
      `${sha256('bee\n')}\t4\tb.txt\n`,
      `${sha256('sea sea sea sea\n')}\t16\tdir/c.txt\n`,
    ];
    assert.deepEqual(inventory.lines, lines);
    assert.equal(inventory.entry_count, 3);
    assert.equal(inventory.total_bytes, 23);
    assert.equal(inventory.sha256, sha256(lines.join('')));
    assert.equal(zip.entries.find(e => e.path === 'dir/c.txt').method, 8);
    assert.equal(zip.read('dir/c.txt').toString('utf8'), 'sea sea sea sea\n');
  }],
  ['FP-0013 case 42: the zip reader rejects ZIP64, encryption, "../x", "a\\b", duplicate paths, a truncated central directory, and method 12', () => {
    const ok = { path: 'a.txt', data: 'a' };
    const cases = [
      [makeZip([{ ...ok, size: 0xFFFFFFFF }]), /ZIP64/],
      [makeZip([{ ...ok, flags: 1 }]), /encrypted/],
      [makeZip([{ path: '../x', data: 'x' }]), /"\.\." segment/],
      [makeZip([{ path: 'a\\b', data: 'x' }]), /backslash/],
      [makeZip([ok, ok]), /duplicate path/],
      [makeZip([ok], { truncateCentral: 10 }), /central directory/],
      [makeZip([{ ...ok, method: 12 }]), /method 12/],
      [makeZip([{ path: '/abs', data: 'x' }]), /absolute path/],
    ];
    for (const [bytes, pattern] of cases) assert.throws(() => zipInventory(readZip(bytes)), pattern);
    const zip64 = makeZip([ok]);
    zip64.writeUInt16LE(0xFFFF, zip64.length - 22 + 10);
    assert.throws(() => readZip(zip64), /ZIP64/);
  }],
  ['FP-0013 case 43: corpus-fetch of file sources writes the record and extracted files, honors pins, and changes nothing on failure', async () => {
    const f = fileSetFixture();
    const first = await f.fetch();
    assert.equal(first.result, 'pass');
    const record = readJson(f.recordFile);
    assert.equal(record.kind, 'file-set');
    assert.equal(record.version, '18.0.0');
    assert.equal(record.upstream, 'https://www.unicode.org/Public/');
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'src/unicode/ucd/Scripts.txt')), Buffer.from(SCRIPTS));
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'src/unicode/ucd/extracted/DerivedBidiClass.txt')), Buffer.from(DERIVED));
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'src/unicode/ucd/license.txt')), Buffer.from(LICENSE));
    assert.equal(record.sources[0].sha256, sha256(f.zip));
    assert.equal(record.sources[0].local_path, '<corpora-root>/unicode/sources/UCD.zip');
    assert.deepEqual(fs.readFileSync(path.join(f.corporaDir, 'unicode/sources/UCD.zip')), f.zip);
    assert.equal(record.sources[0].inventory.entry_count, 3);
    assert.equal(record.selected[0].sha256, sha256(SCRIPTS));
    assert.equal(fs.readdirSync(f.corporaDir).sort().join(), 'unicode');

    const second = await f.fetch();
    assert.equal(second.result, 'pass');
    assert.deepEqual({ ...readJson(f.recordFile), retrieved_at: null }, { ...record, retrieved_at: null });

    const before = snapshot(f.corporaDir, path.join(f.dir, 'src'), path.join(f.dir, 'specs'));
    const unchanged = () => {
      assert.deepEqual(snapshot(f.corporaDir, path.join(f.dir, 'src'), path.join(f.dir, 'specs')), before);
      assert.equal(fs.readdirSync(f.corporaDir).sort().join(), 'unicode');
    };
    const upstreamZip = path.join(f.upstream, 'UCD.zip');
    const changedZip = makeZip([{ path: 'Scripts.txt', data: SCRIPTS }, { path: 'extracted/DerivedBidiClass.txt', data: `${DERIVED}x`, method: 8 }]);
    fs.writeFileSync(upstreamZip, changedZip);
    const changedRule = structuredClone(f.rule);
    changedRule.sources[0].size = changedZip.length;
    changedRule.sources[0].published_digest = `sha256:${sha256(changedZip)}`;
    await assert.rejects(() => f.fetch(changedRule), /pin sources\.ucd\.sha256/);
    unchanged();
    fs.writeFileSync(upstreamZip, f.zip);

    const wrongDigest = structuredClone(f.rule);
    wrongDigest.sources[0].published_digest = `sha256:${'0'.repeat(64)}`;
    await assert.rejects(() => f.fetch(wrongDigest), /published digest/);
    unchanged();
    const wrongBlob = structuredClone(f.rule);
    wrongBlob.sources[1].git_blob = '0'.repeat(40);
    await assert.rejects(() => f.fetch(wrongBlob), /Git blob/);
    unchanged();
    fs.writeFileSync(path.join(f.upstream, 'published/Scripts.txt'), `${SCRIPTS}# changed\n`);
    await assert.rejects(() => f.fetch(), /published_url/);
    unchanged();
  }],
  ['FP-0013 case 44: corpus-verify fails for changed extracted and derived files, a missing source, a license mismatch, a count mismatch, and an upstream mismatch', async () => {
    const f = fileSetFixture();
    await f.fetch();
    otherApplicability(f.dir, 'unicode');
    await f.classify();
    // Record a derived file the way corpus-derive does, so verification covers derived entries.
    const derivedPath = 'tests/text/fonts/fixture/derived.otf', derivedBytes = Buffer.from('derived font bytes');
    fs.mkdirSync(path.join(f.dir, path.dirname(derivedPath)), { recursive: true });
    fs.writeFileSync(path.join(f.dir, derivedPath), derivedBytes);
    const record = readJson(f.recordFile);
    record.derived.push({ path: derivedPath, size: derivedBytes.length, sha256: sha256(derivedBytes), input: { source: 'license', sha256: record.sources[1].sha256 },
      tool: { name: 'fontTools', version: '4.66.1', wheel_url: 'https://example.org/fonttools.whl', wheel_sha256: 'a'.repeat(64), python: '3.13.15' },
      argv: ['-m', 'fontTools.subset'], license_path: 'src/unicode/ucd/license.txt', copyright: 'Fixture', reserved_font_names: [], rfn_resolution: 'Fixture.' });
    writeJson(f.recordFile, record);
    assert.equal((await f.verify()).result, 'pass');

    const restoreAfter = async (file, change, pattern) => {
      const original = fs.existsSync(file) ? fs.readFileSync(file) : null;
      change(file);
      await assert.rejects(f.verify, pattern);
      if (original) fs.writeFileSync(file, original);
      assert.equal((await f.verify()).result, 'pass');
    };
    await restoreAfter(path.join(f.dir, 'src/unicode/ucd/Scripts.txt'), p => fs.appendFileSync(p, 'x'), /selected src\/unicode\/ucd\/Scripts\.txt/);
    await restoreAfter(path.join(f.dir, derivedPath), p => fs.appendFileSync(p, 'x'), /derived tests\/text\/fonts\/fixture\/derived\.otf/);
    await restoreAfter(path.join(f.corporaDir, 'unicode/sources/UCD.zip'), p => fs.rmSync(p), /source ucd: missing/);
    await restoreAfter(path.join(f.dir, 'src/unicode/ucd/license.txt'), p => fs.writeFileSync(p, 'Another license.\n'), /selected src\/unicode\/ucd\/license\.txt/);
    await restoreAfter(f.applicabilityFile, p => {
      const a = readJson(p);
      writeJson(p, { ...a, discovered: a.discovered + 1, unclassified: a.unclassified + 1, breakdown: { ...a.breakdown, counts: { ...a.breakdown.counts, extra: 1 } } });
    }, /applicability: the recorded discovery differs/);
    const policyFile = path.join(f.dir, 'specs/corpora.json');
    await restoreAfter(policyFile, p => {
      const policy = readJson(p);
      policy.corpora.find(c => c.id === 'unicode').upstream = 'https://www.unicode.org/Public/other/';
      writeJson(p, policy);
    }, /upstream: recorded/);

    // The same failure through the controller command exits with status 1. Verification never reads a URL, and the command accepts only
    // HTTPS URLs in a record, so the fixture record names HTTPS URLs for its local file sources.
    const httpsRecord = readJson(f.recordFile);
    for (const s of httpsRecord.sources) s.url = s.url.replace(/^file:\/\/\/?/, 'https://fixture.invalid/');
    for (const e of httpsRecord.selected) if (e.published_url) e.published_url = e.published_url.replace(/^file:\/\/\/?/, 'https://fixture.invalid/');
    writeJson(f.recordFile, httpsRecord);
    const copy = path.join(f.dir, 'tools');
    fs.mkdirSync(copy, { recursive: true });
    for (const name of fs.readdirSync(path.join(root, 'tools')).filter(n => n.endsWith('.mjs'))) fs.copyFileSync(path.join(root, 'tools', name), path.join(copy, name));
    for (const name of ['engineering/policy.json']) { fs.mkdirSync(path.join(f.dir, path.dirname(name)), { recursive: true }); fs.copyFileSync(path.join(root, name), path.join(f.dir, name)); }
    const cli = () => spawnSync(process.execPath, [path.join(copy, 'fairpane.mjs'), 'corpus-verify', 'unicode'],
      { cwd: f.dir, encoding: 'utf8', env: { ...process.env, FAIRPANE_CORPORA_DIR: f.corporaDir }, windowsHide: true });
    const pass = cli();
    assert.equal(pass.status, 0, pass.stdout + pass.stderr);
    fs.appendFileSync(path.join(f.dir, 'src/unicode/ucd/Scripts.txt'), 'x');
    const fail = cli();
    assert.equal(fail.status, 1, fail.stdout + fail.stderr);
    assert.match(fail.stderr, /selected src\/unicode\/ucd\/Scripts\.txt/);
  }],
  ['FP-0013 case 45: file-set applicability reports the per-directory breakdown with an explicit denominator, and a zip without file members fails', async () => {
    const f = fileSetFixture();
    await f.fetch();
    const a = await f.classify();
    assert.equal(a.discovered, 3);
    assert.equal(a.selected, 2);
    assert.equal(a.unclassified, 1);
    assert.deepEqual(a.excluded, []);
    assert.equal(a.selected + a.unclassified, a.discovered);
    assert.deepEqual(a.breakdown, { by: 'first path component of each zip file member; "." for a member at the top level', counts: { '.': 2, extracted: 1 } });
    assert.equal(a.version, '18.0.0');
    assert.deepEqual(a.inventories, { ucd: readJson(f.recordFile).sources[0].inventory.sha256 });
    assert.equal('commit' in a, false);
    assert.deepEqual(readJson(f.applicabilityFile), JSON.parse(JSON.stringify({ ...a, result: undefined, record: undefined })));
    assert.throws(() => zipInventory(readZip(makeZip([{ path: 'empty/', directory: true }]))), /no file members/);
  }],
  ['FP-0013 case 46: corpus-repin unicode exits with status 1 and names the contract decision', () => {
    for (const id of FILE_SET_IDS) {
      const r = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'corpus-repin', id],
        { cwd: root, encoding: 'utf8', env: { ...process.env, FAIRPANE_CORPORA_DIR: temp() }, windowsHide: true });
      assert.equal(r.status, 1, r.stdout + r.stderr);
      assert.match(r.stderr, /version selection is a contract decision/);
    }
  }],
  ['FP-0013 case 47: record validation rejects missing license digests, releases, tool versions, input digests, argv, and reserved font names', () => {
    assert.equal(validateFileSetRecord(goodRecord()), true);
    const variants = [
      [r => { delete r.selected[1].sha256; }, /license digest/],
      [r => { r.selected.splice(1, 1); }, /license digest/],
      [r => { delete r.sources[0].release; }, /release/],
      [r => { r.sources[1].release.name = ''; }, /release/],
      [r => { delete r.derived[0].tool.version; }, /tool version/],
      [r => { delete r.derived[0].input.sha256; }, /input digest/],
      [r => { delete r.derived[0].argv; }, /argv/],
      [r => { r.derived[0].argv = []; }, /argv/],
      [r => { delete r.derived[0].reserved_font_names; }, /reserved_font_names/],
    ];
    for (const [change, pattern] of variants) {
      const r = goodRecord();
      change(r);
      assert.throws(() => validateFileSetRecord(r), pattern);
    }
  }],
  ['FP-0013 case 48: every selected, derived, and license path of the committed unicode and opentype-fixtures records matches its size and SHA-256', () => {
    let checked = 0;
    for (const id of FILE_SET_IDS) {
      const record = readJson(path.join(root, 'specs/snapshots', `${id}.json`));
      assert.equal(validateFileSetRecord(record), true);
      const paths = new Map();
      for (const e of [...record.selected, ...record.derived]) paths.set(e.path, e);
      for (const e of [...record.selected, ...record.derived]) if (e.license_path) assert.ok(paths.has(e.license_path) || record.selected.some(s => s.path === e.license_path), e.license_path);
      for (const [p, e] of paths) {
        const bytes = fs.readFileSync(path.join(root, p));
        assert.equal(bytes.length, e.size, p);
        assert.equal(sha256(bytes), e.sha256, p);
        checked++;
      }
    }
    assert.ok(checked >= 9 + 7 + 1);
  }],
  ['FP-0013 case 49 (amended by FP-0108 case 6): the committed capability record validates with exactly the frozen obligations and existing owner tasks', () => {
    const record = readJson(path.join(root, 'specs/capabilities/text-fonts.json'));
    const plan = readJson(path.join(root, 'engineering/plan.json'));
    assert.equal(validateCapabilityRecord(record, plan), true);
    const frozen = [
      ['unicode-properties', 'implemented', 'FP-0013'], ['opentype-core-tables', 'implemented', 'FP-0013'],
      ['unicode-remaining-data', 'remaining', 'FP-0055'], ['bidi-algorithm', 'remaining', 'FP-0015'],
      ['grapheme-segmentation', 'implemented', 'FP-0108'], ['line-breaking', 'remaining', 'FP-0015'], ['shaping', 'remaining', 'FP-0015'],
      ['font-fallback', 'remaining', 'FP-0015'], ['glyph-rasterization', 'remaining', 'FP-0056'], ['truetype-hinting', 'remaining', 'FP-0057'],
      ['woff', 'remaining', 'FP-0058'], ['woff2-brotli', 'remaining', 'FP-0058'], ['font-collections', 'remaining', 'FP-0059'],
      ['cff2-and-variations', 'remaining', 'FP-0059'], ['color-fonts', 'remaining', 'FP-0060'], ['vertical-metrics', 'remaining', 'FP-0061'],
      ['cmap-variation-and-legacy-formats', 'remaining', 'FP-0061'], ['layout-auxiliary-tables', 'remaining', 'FP-0062'],
      ['platform-font-discovery', 'remaining', 'FP-0063'],
    ];
    assert.deepEqual(record.obligations.map(o => [o.id, o.status, o.owner_task]), frozen);
    assert.deepEqual(TEXT_FONT_OBLIGATIONS.map(o => [o.id, o.status, o.owner_task]), frozen);
    const taskIds = new Set(plan.tasks.map(t => t.id));
    for (const o of record.obligations) assert.ok(taskIds.has(o.owner_task), o.owner_task);
    const variants = [
      [r => { r.obligations = r.obligations.filter(o => o.id !== 'glyph-rasterization'); }, /glyph-rasterization/],
      [r => { r.obligations.find(o => o.id === 'shaping').owner_task = 'FP-9999'; }, /FP-9999/],
      [r => { r.obligations.find(o => o.id === 'woff').owner_task = null; }, /owner/],
    ];
    for (const [change, pattern] of variants) {
      const r = structuredClone(record);
      change(r);
      assert.throws(() => validateCapabilityRecord(r, plan), pattern);
    }
  }],
  ['FP-0108 case 5: the committed unicode records select 12 of 71 members, keep the source digests, and list the four FP-0108 members', () => {
    const a = readJson(path.join(root, 'specs/applicability/unicode.json'));
    assert.equal(a.discovered, 71);
    assert.equal(a.selected, 12);
    assert.equal(a.unclassified, 59);
    assert.deepEqual(a.excluded, []);
    assert.deepEqual(a.breakdown.counts, { '.': 45, auxiliary: 11, emoji: 3, extracted: 12 });
    const record = readJson(path.join(root, 'specs/snapshots/unicode.json'));
    const zip = record.sources.find(s => s.id === 'ucd-zip'), license = record.sources.find(s => s.id === 'unicode-license');
    assert.equal(zip.size, 5657953);
    assert.equal(zip.sha256, '7b3e555514060b92290d154f53655c5eb0fa62b16eb04c03434ff72d1a66a0d8');
    assert.deepEqual(zip.inventory, { entry_count: 71, total_bytes: 39580113, sha256: '37761bcf3660066413756e978f9d5ec7c7be3c187738f5d95785203c8dd8b2f4' });
    assert.equal(license.size, 1995);
    assert.equal(license.sha256, 'e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96');
    assert.equal(record.selected.filter(e => e.source === 'ucd-zip').length, 12);
    for (const member of ['auxiliary/GraphemeBreakProperty.txt', 'DerivedCoreProperties.txt', 'emoji/emoji-data.txt', 'auxiliary/GraphemeBreakTest.txt']) {
      const e = record.selected.find(x => x.member === member);
      assert.ok(e, member);
      assert.equal(e.source, 'ucd-zip', member);
      assert.equal(e.path, `src/unicode/ucd/${member}`, member);
      assert.equal(e.role, 'data', member);
      assert.equal(e.published_url, `https://www.unicode.org/Public/18.0.0/ucd/${member}`, member);
    }
    const policy = readJson(path.join(root, 'specs/corpora.json')).corpora.find(c => c.id === 'unicode');
    assert.deepEqual(policy, {
      id: 'unicode', upstream: 'https://www.unicode.org/Public/', purpose: 'Unicode properties and conformance data', revision: '18.0.0',
      license_record: 'specs/snapshots/unicode.json', inventory_sha256: '2511e5384857e35883ec38bd8c0d225d1ea7591f6ee6ba6347c572f6b47a59d7',
      local_path: '<corpora-root>/unicode/sources', status: 'pinned',
    });
  }],
  ['FP-0013 case 53: overlapping, inconsistent, symbolic-link, case-folded, oversized, corrupt, and drive-letter archives fail before any member is written', async () => {
    await parts(rejectedArchives().map(([label, bytes, pattern, structural]) => [label, async () => {
      if (structural) assert.throws(() => readZip(bytes), pattern, 'readZip, which inflates nothing, must reject it');
      else assert.throws(() => zipInventory(readZip(bytes)), pattern);
      const f = fileSetFixture();
      fs.writeFileSync(path.join(f.upstream, 'UCD.zip'), bytes);
      const rule = structuredClone(f.rule);
      rule.sources[0].size = null;
      rule.sources[0].published_digest = null;
      await assert.rejects(() => f.fetch(rule), pattern);
      assert.equal(fs.existsSync(f.recordFile), false);
      assert.equal(fs.existsSync(path.join(f.dir, 'src')), false);
      assert.deepEqual(fs.readdirSync(f.corporaDir), []);
    }]));
  }],
  ['FP-0013 case 54: a fetch compares every known digest before parsing a source', async () => {
    // The bytes are not a zip, so readZip would fail with its own message about the central directory.
    const notZip = Buffer.from('These bytes are not a zip archive.\n');
    const unpinnedRule = fixture => {
      const rule = structuredClone(fixture.rule);
      rule.sources[0].size = null;
      rule.sources[0].published_digest = null;
      return rule;
    };
    const f = fileSetFixture();
    await f.fetch();
    otherApplicability(f.dir, 'unicode');
    await f.classify();
    const failure = async run => {
      const error = await run().then(() => null, e => e);
      assert.ok(error, 'The command must fail.');
      assert.doesNotMatch(error.message, /central directory/, 'The command parsed a source whose digest differs.');
      return error;
    };
    await parts([
      ['the previous record\'s SHA-256', async () => {
        const before = snapshot(f.corporaDir, path.join(f.dir, 'src'), path.join(f.dir, 'specs'));
        fs.writeFileSync(path.join(f.upstream, 'UCD.zip'), notZip);
        assert.match((await failure(() => f.fetch(unpinnedRule(f)))).message, /pin sources\.ucd\.sha256/);
        assert.deepEqual(snapshot(f.corporaDir, path.join(f.dir, 'src'), path.join(f.dir, 'specs')), before);
      }],
      ['corpus-verify', async () => {
        fs.writeFileSync(path.join(f.corporaDir, 'unicode/sources/UCD.zip'), notZip);
        assert.match((await failure(f.verify)).message, /source ucd sha256/);
      }],
      ['corpus-applicability', async () => {
        fs.writeFileSync(path.join(f.corporaDir, 'unicode/sources/UCD.zip'), notZip);
        assert.match((await failure(f.classify)).message, /source ucd/);
      }],
      ['a specs/corpora.json pin', async () => {
        const g = fileSetFixture();
        const policyFile = path.join(g.dir, 'specs/corpora.json'), policy = readJson(policyFile);
        policy.corpora.find(c => c.id === 'unicode').inventory_sha256 = '0'.repeat(64);
        writeJson(policyFile, policy);
        fs.writeFileSync(path.join(g.upstream, 'UCD.zip'), notZip);
        assert.match((await failure(() => g.fetch(unpinnedRule(g)))).message, /inventory_sha256/);
        assert.equal(fs.existsSync(g.recordFile), false);
        assert.deepEqual(fs.readdirSync(g.corporaDir), []);
      }],
    ]);
  }],
  ['FP-0013 case 54: downloads follow redirects manually on allowlisted HTTPS hosts and stop at their size limit', async () => {
    const dir = temp(), file = path.join(dir, 'download.bin');
    const calls = [];
    const fake = routes => async (url, init) => {
      calls.push({ url: String(url), redirect: init?.redirect });
      const route = routes[String(url)];
      assert.ok(route, `unexpected request ${url}`);
      return route();
    };
    const redirect = location => () => new Response(null, { status: 302, headers: { location } });
    const download = (url, routes, limit = 1024) => fileset.downloadSource(url, file, { limit, httpFetch: fake(routes) });
    let pulls = 0;
    const endless = () => new Response(new ReadableStream({ pull(controller) { pulls++; controller.enqueue(new Uint8Array(1000)); } }));
    await parts([
      ['a manual redirect on allowlisted hosts', async () => {
        calls.length = 0;
        const ok = await download('https://github.com/a', { 'https://github.com/a': redirect('/b'), 'https://github.com/b': () => new Response('body') });
        assert.deepEqual(ok, { size: 4, sha256: sha256('body') });
        assert.deepEqual(calls.map(c => [c.url, c.redirect]), [['https://github.com/a', 'manual'], ['https://github.com/b', 'manual']]);
      }],
      ['an http: hop', async () => {
        calls.length = 0;
        await assert.rejects(() => download('https://www.unicode.org/a', { 'https://www.unicode.org/a': redirect('http://www.unicode.org/b') }), /https:/);
        assert.deepEqual(calls.map(c => c.url), ['https://www.unicode.org/a']);
      }],
      ['a hop to another host', async () => {
        calls.length = 0;
        await assert.rejects(() => download('https://github.com/a', { 'https://github.com/a': redirect('https://downloads.example.org/b') }), /downloads\.example\.org/);
        assert.deepEqual(calls.map(c => c.url), ['https://github.com/a']);
      }],
      ['a first URL on another host', async () => {
        calls.length = 0;
        await assert.rejects(() => download('https://example.org/a', {}), /example\.org/);
        assert.deepEqual(calls, []);
      }],
      ['a download over its limit', async () => {
        pulls = 0;
        await assert.rejects(() => download('https://raw.githubusercontent.com/a', { 'https://raw.githubusercontent.com/a': endless }, 4096), /exceeds its limit of 4096 bytes/);
        assert.ok(pulls <= 16, `the download read ${pulls} chunks after it passed its limit`);
        assert.equal(fs.existsSync(file), false);
        await assert.rejects(() => fileset.fetchBytes('https://www.unicode.org/a', { limit: 4096, httpFetch: fake({ 'https://www.unicode.org/a': endless }) }),
          /exceeds its limit of 4096 bytes/);
      }],
      ['the pinned size, else 256 MiB', () => {
        assert.equal(fileset.downloadLimit({ size: 10 }, null), 10);
        assert.equal(fileset.downloadLimit({ size: null }, { size: 20 }), 20);
        assert.equal(fileset.downloadLimit({ size: null }, null), 256 * 1024 * 1024);
      }],
    ]);
  }],
  ['FP-0013 case 54: a failure injected at each write step leaves every previous file, the source directory, and the record unchanged', async () => {
    const f = fileSetFixture();
    await f.fetch();
    // Local changes that a complete fetch replaces: an edited file, a missing file and directory, and an extra source file.
    fs.appendFileSync(path.join(f.dir, 'src/unicode/ucd/Scripts.txt'), '# local edit\n');
    fs.rmSync(path.join(f.dir, 'src/unicode/ucd/extracted'), { recursive: true });
    fs.writeFileSync(path.join(f.corporaDir, 'unicode/sources/marker.txt'), 'The previous source directory.\n');
    const roots = [f.corporaDir, path.join(f.dir, 'src'), path.join(f.dir, 'specs')];
    const before = snapshot(...roots);
    let steps = 0;
    for (let k = 0; ; k++) {
      let seen = 0;
      const labels = [];
      const onWriteStep = label => { labels.push(label); if (seen++ === k) throw new Error(`injected failure at ${label}`); };
      const error = await f.fetch(undefined, { onWriteStep }).then(() => null, e => e);
      if (!error) { steps = k; break; }
      assert.match(error.message, /injected failure/);
      assert.deepEqual(snapshot(...roots), before, `after a failure at ${labels.at(-1)}`);
      assert.equal(fs.existsSync(path.join(f.dir, 'src/unicode/ucd/extracted')), false, `after a failure at ${labels.at(-1)}`);
      assert.equal(fs.readdirSync(f.corporaDir).join(), 'unicode', `after a failure at ${labels.at(-1)}`);
    }
    // Staging three files and the record, replacing three files, swapping the source directory, and writing the record.
    assert.ok(steps >= 10, `only ${steps} write steps were injected`);
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'src/unicode/ucd/Scripts.txt')), Buffer.from(SCRIPTS));
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'src/unicode/ucd/extracted/DerivedBidiClass.txt')), Buffer.from(DERIVED));
    assert.equal(fs.existsSync(path.join(f.corporaDir, 'unicode/sources/marker.txt')), false);
    assert.equal(fs.readdirSync(f.corporaDir).join(), 'unicode');
  }],
  ['FP-0013 case 55: corpus-derive refuses a fontTools installation with one changed file', async () => {
    const derive = install => deriveCorpus(install.dir, 'opentype-fixtures', { corporaDir: temp() });
    await parts([
      ['an unchanged installation', async () => {
        const unchanged = fakeFontTools();
        assert.ok(fileset.verifyToolInstallation(unchanged.dir, unchanged.tool).files >= 4);
        // Verification passes, so the command stops later, at the missing snapshot record of this fixture repository.
        await assert.rejects(() => derive(unchanged), /Missing snapshot record/);
      }],
      ['a changed package file', async () => {
        const changed = fakeFontTools();
        fs.appendFileSync(path.join(changed.sitePackages, 'fontTools/subset/__init__.py'), '# changed\n');
        await assert.rejects(() => derive(changed), /fontTools\/subset\/__init__\.py.*RECORD/);
      }],
      ['a changed data file', async () => {
        const data = fakeFontTools();
        fs.appendFileSync(path.join(data.venv, 'share/man/man1/ttx.1'), 'changed\n');
        await assert.rejects(() => derive(data), /share\/man\/man1\/ttx\.1.*RECORD/);
      }],
      ['a planted package file', async () => {
        const planted = fakeFontTools();
        fs.writeFileSync(path.join(planted.sitePackages, 'fontTools/planted.py'), 'raise SystemExit(1)\n');
        await assert.rejects(() => derive(planted), /fontTools\/planted\.py.*not listed/);
      }],
      ['a changed wheel', async () => {
        const wheel = fakeFontTools();
        fs.appendFileSync(wheel.wheel, 'x');
        await assert.rejects(() => derive(wheel), /wheel/);
      }],
    ]);
  }],
  ['FP-0013 case 55: the Python child process sees PYTHONSAFEPATH=1, no other PYTHON* variable, and the staging directory', () => {
    const staging = temp();
    const script = 'console.log(JSON.stringify({ env: Object.fromEntries(Object.entries(process.env).filter(([k]) => /^python/i.test(k))), cwd: process.cwd() }))';
    const baseEnv = { ...process.env, PYTHONPATH: 'planted', PYTHONHOME: 'planted', PYTHONSTARTUP: 'planted', PYTHONSAFEPATH: '0', PythonUserBase: 'planted' };
    const r = fileset.runPython(process.execPath, ['-e', script], { cwd: staging, baseEnv });
    assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
    const seen = JSON.parse(r.stdout);
    assert.deepEqual(seen.env, { PYTHONSAFEPATH: '1' });
    assert.equal(fs.realpathSync(seen.cwd), fs.realpathSync(staging));
    assert.throws(() => fileset.runPython(process.execPath, ['-e', ''], { cwd: 'relative' }), /absolute/);
  }],
  ['FP-0013 case 55: sfntCopyright stops at the first name record and checks the name table header length', async () => {
    const records = nameTable('First');
    records.writeUInt16BE(9, 2);
    await parts([
      ['the first of two name records', () => assert.equal(sfntCopyright(sfnt([['name', nameTable('First')], ['name', nameTable('Second')]])), 'First')],
      ['a name table shorter than its header', () => assert.throws(() => sfntCopyright(sfnt([['name', Buffer.alloc(4)]])), /name table is shorter than its 6-byte header/)],
      ['name records past the table', () => assert.throws(() => sfntCopyright(sfnt([['name', records]])), /name records run past the name table/)],
      ['no name table', () => assert.throws(() => sfntCopyright(sfnt([['post', Buffer.alloc(32)]])), /no name table/)],
      ['a truncated sfnt header', () => assert.throws(() => sfntCopyright(Buffer.alloc(8)), /shorter than an sfnt header/)],
    ]);
  }],
  ['FP-0052 case 6: of two fetches of one file set started together, one passes and one fails on the lock', async () => {
    const f = fileSetFixture();
    const results = await Promise.allSettled([f.fetch(), f.fetch()]);
    const summary = JSON.stringify(results.map(r => r.status === 'fulfilled' ? r.value.result : r.reason.message));
    assert.equal(results.filter(r => r.status === 'fulfilled' && r.value.result === 'pass').length, 1, summary);
    assert.equal(results.filter(r => r.status === 'rejected' && /holds the lock file/.test(r.reason.message)).length, 1, summary);
    assert.equal(fs.readdirSync(f.corporaDir).join(), 'unicode');
    otherApplicability(f.dir, 'unicode');
    await f.classify();
    assert.equal((await f.verify()).result, 'pass');
  }],
].map(([name, fn]) => ({ name, fn }));

/** Archives that the zip reader must reject, each with its label, error pattern, and whether readZip rejects it without inflating. */
function rejectedArchives() {
  const inner = zipMember({ path: 'b.txt', data: 'bee\n' }, 0).local;
  const random = crypto.randomBytes(1100000);
  const zeros = Buffer.alloc(65536), kernel = zlib.deflateRawSync(zeros);
  const zip64Extra = Buffer.alloc(20);
  zip64Extra.writeUInt16LE(0x0001, 0); zip64Extra.writeUInt16LE(16, 2);
  return [
    ['overlapping members', makeZip([{ path: 'a.txt', data: inner }, { path: 'b.txt', data: 'bee\n', localOffset: 30 + 'a.txt'.length }]), /overlap/, true],
    ['a local CRC-32', makeZip([{ path: 'a.txt', data: 'a', edit: (c, l) => l.writeUInt32LE(0x12345678, 14) }]), /local header that disagrees .* in CRC-32/, true],
    ['a local compressed size', makeZip([{ path: 'a.txt', data: 'a', edit: (c, l) => l.writeUInt32LE(2, 18) }]), /local header that disagrees .* in sizes/, true],
    ['a local uncompressed size', makeZip([{ path: 'a.txt', data: 'aaaa', method: 8, edit: (c, l) => l.writeUInt32LE(3, 22) }]), /local header that disagrees .* in sizes/, true],
    ['a local method', makeZip([{ path: 'a.txt', data: 'aaaa', method: 8, edit: (c, l) => l.writeUInt16LE(0, 8) }]), /local header that disagrees .* in method/, true],
    ['local flags', makeZip([{ path: 'a.txt', data: 'a', edit: (c, l) => l.writeUInt16LE(0x0800, 6) }]), /local header that disagrees .* in flags/, true],
    ['a local ZIP64 extra field', makeZip([{ path: 'a.txt', data: 'a', localExtra: zip64Extra }]), /ZIP64/, true],
    ['flag bit 13', makeZip([{ path: 'a.txt', data: 'a', flags: 0x2000 }]), /flag bit 13/, true],
    ['a symbolic link', makeZip([{ path: 'link', data: 'target', madeBy: 0x0314, external: 0o120777 * 0x10000 }]), /symbolic link/, true],
    ['a reparse point', makeZip([{ path: 'link', data: 'target', external: 0x400 }]), /symbolic link/, true],
    ['names equal under case folding', makeZip([{ path: 'Read.txt', data: 'a' }, { path: 'read.TXT', data: 'b' }]), /case folding/, true],
    ['a declared total over 1 GiB', makeZip([{ path: 'big.bin', data: random, method: 8, size: 2 ** 30 + 1 }]), /1 GiB/, true],
    ['a ratio over 1024', makeZip([{ path: 'bomb.bin', data: zeros, method: 8, size: 1025 * kernel.length }]), /1024/, true],
    ['a CRC-32 mismatch', makeZip([{ path: 'a.txt', data: 'a', crc: 0xDEADBEEF }]), /CRC-32/, false],
    ['a larger declared size', makeZip([{ path: 'a.txt', data: 'sea sea', method: 8, size: 12 }]), /7 bytes, not 12/, false],
    ['a smaller declared size', makeZip([{ path: 'a.txt', data: 'sea sea', method: 8, size: 3 }]), /does not inflate|bytes, not 3/, false],
    ['a drive-letter name', makeZip([{ path: 'C:/x.txt', data: 'x' }]), /absolute path/, true],
    ['a drive-relative name', makeZip([{ path: 'C:x.txt', data: 'x' }]), /absolute path/, true],
  ];
}

/** A fontTools installation from a fixture wheel: a repository root with the wheel, its `dependencies.json` digest, and the installed files. */
function fakeFontTools() {
  const dir = temp();
  const files = {
    'fontTools/__init__.py': 'version = "4.66.1"\n',
    'fontTools/subset/__init__.py': 'def main():\n    pass\n',
    'fonttools-4.66.1.dist-info/METADATA': 'Name: fonttools\nVersion: 4.66.1\n',
    'fonttools-4.66.1.data/data/share/man/man1/ttx.1': '.TH TTX 1\n',
  };
  const digest = data => crypto.createHash('sha256').update(data).digest('base64url');
  const record = [...Object.entries(files).map(([p, text]) => `${p},sha256=${digest(text)},${Buffer.byteLength(text)}`), 'fonttools-4.66.1.dist-info/RECORD,,'].join('\r\n');
  const wheelBytes = makeZip([...Object.entries(files).map(([p, data]) => ({ path: p, data, method: 8 })), { path: 'fonttools-4.66.1.dist-info/RECORD', data: `${record}\r\n` }]);
  const dependencies = readJson(path.join(root, 'engineering/dependencies.json'));
  const tool = dependencies.development.import_tools.find(t => t.name === 'fontTools');
  tool.wheel_sha256 = sha256(wheelBytes);
  writeJson(path.join(dir, 'engineering/dependencies.json'), dependencies);
  const wheel = path.join(dir, '.tools/downloads', path.posix.basename(new URL(tool.wheel_url).pathname));
  fs.mkdirSync(path.dirname(wheel), { recursive: true });
  fs.writeFileSync(wheel, wheelBytes);
  const venv = path.join(dir, '.tools/python/fonttools-4.66.1');
  const sitePackages = process.platform === 'win32' ? path.join(venv, 'Lib/site-packages') : path.join(venv, 'lib/python3.13/site-packages');
  const put = (file, data) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, data); };
  for (const [p, text] of Object.entries(files)) {
    put(p.startsWith('fonttools-4.66.1.data/data/') ? path.join(venv, p.slice('fonttools-4.66.1.data/data/'.length)) : path.join(sitePackages, p), text);
  }
  // Files that pip writes: bytecode, its own RECORD, and the installer marker.
  put(path.join(sitePackages, 'fontTools/__pycache__/__init__.cpython-313.pyc'), 'bytecode');
  put(path.join(sitePackages, 'fonttools-4.66.1.dist-info/RECORD'), 'installed record\n');
  put(path.join(sitePackages, 'fonttools-4.66.1.dist-info/INSTALLER'), 'pip\n');
  put(process.platform === 'win32' ? path.join(venv, 'Scripts/python.exe') : path.join(venv, 'bin/python'), '');
  return { dir, tool, venv, sitePackages, wheel };
}

/** A minimal sfnt with the given tables, laid out after the directory without checksums. */
function sfnt(tables) {
  const header = Buffer.alloc(12 + 16 * tables.length);
  header.writeUInt32BE(0x00010000, 0); header.writeUInt16BE(tables.length, 4);
  let offset = header.length;
  tables.forEach(([tag, data], i) => {
    header.write(tag, 12 + 16 * i, 'latin1');
    header.writeUInt32BE(offset, 12 + 16 * i + 8); header.writeUInt32BE(data.length, 12 + 16 * i + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...tables.map(([, data]) => data)]);
}

/** A format 0 name table with one (3, 1, 0x409, 0) record. */
function nameTable(copyright) {
  const text = Buffer.from(copyright, 'utf16le').swap16();
  const t = Buffer.alloc(6 + 12);
  t.writeUInt16BE(0, 0); t.writeUInt16BE(1, 2); t.writeUInt16BE(18, 4);
  t.writeUInt16BE(3, 6); t.writeUInt16BE(1, 8); t.writeUInt16BE(0x409, 10); t.writeUInt16BE(0, 12);
  t.writeUInt16BE(text.length, 14); t.writeUInt16BE(0, 16);
  return Buffer.concat([t, text]);
}

export function removeFileSetFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of fileSetCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeFileSetFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${fileSetCases.length}\n# tests ${fileSetCases.length}\n# pass ${fileSetCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
