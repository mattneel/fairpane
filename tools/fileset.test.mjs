#!/usr/bin/env node
/**
 * File-set corpus, record, and capability tests for FP-0013 cases 41 through 49.
 * Run standalone with `node tools/fileset.test.mjs`, or through `node tools/fairpane.mjs test`.
 * Fetches read `file://` fixture sources that only these tests enable; no case uses the network.
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
import { classifyCorpus, fetchCorpus, verifyCorpus } from './corpus.mjs';
import { FILE_SET_IDS, crc32, gitBlobId, readZip, validateFileSetRecord, zipInventory } from './fileset.mjs';
import { TEXT_FONT_OBLIGATIONS, validateCapabilityRecord } from './capabilities.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const temporary = [];
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-fileset-'));
  temporary.push(dir); return dir;
}

/**
 * Write a ZIP archive. Each entry is `{ path, data, method }` or `{ path, directory: true }`.
 * `edit(central, local)` may change the header buffers of an entry before they are written.
 */
export function makeZip(entries, { truncateCentral = 0 } = {}) {
  const locals = [], centrals = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.path, 'utf8');
    const data = e.directory ? Buffer.alloc(0) : Buffer.from(e.data);
    const method = e.method ?? 0;
    const stored = method === 8 ? zlib.deflateRawSync(data) : data;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(e.flags ?? 0, 6);
    local.writeUInt16LE(method, 8); local.writeUInt32LE(crc32(data), 14);
    local.writeUInt32LE(e.compressedSize ?? stored.length, 18); local.writeUInt32LE(e.size ?? data.length, 22);
    local.writeUInt16LE(name.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(e.flags ?? 0, 8); central.writeUInt16LE(method, 10); central.writeUInt32LE(crc32(data), 16);
    central.writeUInt32LE(e.compressedSize ?? stored.length, 20); central.writeUInt32LE(e.size ?? data.length, 24);
    central.writeUInt16LE(name.length, 28); central.writeUInt32LE(e.directory ? 0x10 : 0, 38); central.writeUInt32LE(offset, 42);
    locals.push(local, name, stored);
    centrals.push(central, name);
    offset += local.length + name.length + stored.length;
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
    fetch: (changed) => fetchCorpus(dir, 'unicode', options({ rule: changed })),
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
  ['FP-0013 case 49: the committed capability record validates with exactly the frozen obligations and existing owner tasks', () => {
    const record = readJson(path.join(root, 'specs/capabilities/text-fonts.json'));
    const plan = readJson(path.join(root, 'engineering/plan.json'));
    assert.equal(validateCapabilityRecord(record, plan), true);
    const frozen = [
      ['unicode-properties', 'implemented', 'FP-0013'], ['opentype-core-tables', 'implemented', 'FP-0013'],
      ['unicode-remaining-data', 'remaining', 'FP-0055'], ['bidi-algorithm', 'remaining', 'FP-0015'],
      ['grapheme-segmentation', 'remaining', 'FP-0015'], ['line-breaking', 'remaining', 'FP-0015'], ['shaping', 'remaining', 'FP-0015'],
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
].map(([name, fn]) => ({ name, fn }));

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
