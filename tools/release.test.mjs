#!/usr/bin/env node
/**
 * Release tests for FP-0027: source archives, unsigned provenance, reproducibility checks, and the owner decisions of ADR 0009.
 * Run standalone with `node tools/release.test.mjs`, or through `node tools/fairpane.mjs test`.
 * Each case imports `tools/release.mjs` itself, so a missing implementation fails each case instead of the whole suite.
 */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const release = () => import('./release.mjs');
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const temporary = [];

function temp() {
  const dir = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-release-')));
  temporary.push(dir);
  return dir;
}
const emptyConfig = path.join(temp(), 'empty-gitconfig');
fs.writeFileSync(emptyConfig, '');
const fixtureEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: emptyConfig, GIT_TERMINAL_PROMPT: '0',
  GIT_AUTHOR_NAME: 'Fairpane Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid', GIT_AUTHOR_DATE: '1767323045 +0000',
  GIT_COMMITTER_NAME: 'Fairpane Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid', GIT_COMMITTER_DATE: '1767323045 +0000' };
function git(dir, args, input) {
  const r = spawnSync('git', ['-C', dir, ...args], { input, env: fixtureEnv, windowsHide: true });
  assert.equal(r.status, 0, `git ${args.join(' ')} failed: ${r.error?.message ?? r.stderr}`);
  return r.stdout.toString('latin1').trim();
}
/** A fresh non-bare repository with no commits. */
function repository() {
  const dir = temp();
  git(dir, ['init', '--quiet', '.']);
  return dir;
}
/** Write one tree level through `git mktree`. Entries: `{ parts, mode, oid }` with path components as buffers. */
function tree(dir, entries) {
  const lines = [], dirs = new Map(), nul = Buffer.from([0]);
  for (const e of entries) {
    if (e.parts.length === 1) { lines.push(Buffer.concat([Buffer.from(`${e.mode} blob ${e.oid}\t`), e.parts[0], nul])); continue; }
    const name = e.parts[0].toString('latin1');
    if (!dirs.has(name)) dirs.set(name, []);
    dirs.get(name).push({ ...e, parts: e.parts.slice(1) });
  }
  for (const [name, sub] of dirs) lines.push(Buffer.concat([Buffer.from(`040000 tree ${tree(dir, sub)}\t`), Buffer.from(name, 'latin1'), nul]));
  return git(dir, ['mktree', '-z'], Buffer.concat(lines));
}
/** Commit `files` (`{ path, text, mode }`) through plumbing, so modes and links do not depend on the host file system. */
function commit(dir, files) {
  const entries = files.map(f => ({ parts: Buffer.from(f.path).toString('latin1').split('/').map(p => Buffer.from(p, 'latin1')),
    mode: f.mode ?? '100644', oid: git(dir, ['hash-object', '-w', '--stdin'], Buffer.from(f.text)) }));
  return git(dir, ['-c', 'commit.gpgsign=false', 'commit-tree', tree(dir, entries), '-m', 'fixture']);
}
/** The manifest file list that a fixture commit must produce: sorted by UTF-8 path bytes. */
function expectedFiles(files) {
  return [...files].sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)))
    .map(f => ({ path: f.path, mode: f.mode ?? '100644', size: Buffer.byteLength(f.text), sha256: sha256(Buffer.from(f.text)) }));
}
function readManifest(dir, id) { return JSON.parse(fs.readFileSync(path.join(dir, `fairpane-${id}.manifest.json`), 'utf8')); }
function rejects(fn, pattern) {
  let error = null;
  try { fn(); } catch (e) { error = e; }
  assert.ok(error, 'Expected a rejection, got success.');
  assert.match(error.message, pattern);
}

// The UTF-16 order of U+FF61 and U+1F600 is the reverse of their UTF-8 byte order, so the fixture detects a string sort.
const BASE = Object.freeze([
  { path: 'a.txt', text: 'alpha\n' },
  { path: 'B.txt', text: 'upper\n' },
  { path: 'dir/b.txt', text: 'bravo\n' },
  { path: 'run.sh', text: '#!/bin/sh\necho run\n' },
  { path: 'link', text: 'a.txt', mode: '120000' },
  { path: '\uFF61.txt', text: 'halfwidth\n' },
  { path: '\u{1F600}.txt', text: 'emoji\n' },
  { path: `long/${'d'.repeat(90)}/${'n'.repeat(120)}.txt`, text: 'a long path needs a pax header\n' },
]);
const LOCK_TEXT = fs.readFileSync(path.join(root, 'toolchains/zig.lock.json'), 'utf8');

// Reproducibility fixtures. The stand-in compiler records its arguments and runs the fixture commit's own `build.mjs`,
// so the build behavior comes from the archived commit, as it does for `zig build`.
const FIXED_BUILD = `import fs from 'node:fs';
import path from 'node:path';
const prefix = process.argv[2];
fs.mkdirSync(path.join(prefix, 'lib'), { recursive: true });
fs.writeFileSync(path.join(prefix, 'lib', 'fixed.txt'), 'fixed\\n');
`;
const CLOCK_BUILD = `${FIXED_BUILD}fs.mkdirSync(path.join(prefix, 'bin'), { recursive: true });
fs.writeFileSync(path.join(prefix, 'bin', 'stamp.txt'), \`\${Date.now()} \${process.hrtime.bigint()}\\n\`);
`;
const STAND_IN = `import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
const [log, ...args] = process.argv.slice(2);
const at = name => args[args.indexOf(name) + 1];
const caches = [process.env.ZIG_LOCAL_CACHE_DIR, process.env.ZIG_GLOBAL_CACHE_DIR];
const zig = Object.keys(process.env).filter(name => /^ZIG_/i.test(name)).sort();
fs.appendFileSync(log, JSON.stringify({ cwd: process.cwd(), args, caches, zig, fresh: caches.map(dir => !!dir && !fs.existsSync(dir)) }) + '\\n');
const r = spawnSync(process.execPath, ['build.mjs', at('--prefix')], { stdio: 'inherit' });
process.exit(r.status ?? 1);
`;
function standIn() {
  const dir = temp(), script = path.join(dir, 'zig-stand-in.mjs'), log = path.join(dir, 'invocations.jsonl');
  fs.writeFileSync(script, STAND_IN);
  return { compiler: { executable: process.execPath, args: [script, log] },
    invocations: () => fs.readFileSync(log, 'utf8').trim().split('\n').map(line => JSON.parse(line)) };
}
function buildFixture(buildText) {
  const dir = repository();
  return { dir, id: commit(dir, [{ path: 'build.mjs', text: buildText }, { path: 'README.md', text: 'fixture\n' }]) };
}
const isInside = (child, parent) => { const r = path.relative(parent, child); return !!r && !r.startsWith('..') && !path.isAbsolute(r); };

/** The ten owner decisions that the contract names, in the wording that ADR 0009 must use. */
const OWNER_DECISIONS = Object.freeze([
  'Outbound license',
  'Copyright and attribution notice',
  'Contribution provenance rule',
  'Release signing identity and key custody',
  'Project and product names',
  'Domain',
  'Private security reporting channel',
  'Initial maintainers and appointment record',
  'Succession and archival custodian',
  'Release approval authority',
]);
/** Rows of the first table in the ADR section `heading`, as arrays of trimmed cells. */
function tableRows(text, heading) {
  const lines = text.replace(/\r\n/g, '\n').split('\n'), start = lines.indexOf(heading);
  assert.ok(start !== -1, `The ADR has no section ${JSON.stringify(heading)}.`);
  const rows = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith('## ')) break;
    if (line.startsWith('|')) rows.push(line.slice(1, line.endsWith('|') ? -1 : undefined).split('|').map(cell => cell.trim()));
    else if (rows.length) break;
  }
  return rows;
}

export const releaseCases = [
  ['FP-0027 case 1: two source-archive runs on one commit write byte-identical tar and manifest files, and the manifest names the tar digest', async () => {
    const { sourceArchive } = await release();
    const dir = repository(), id = commit(dir, BASE), first = temp(), second = path.join(temp(), 'nested', 'output');
    const a = sourceArchive(dir, id, first), b = sourceArchive(dir, id, second);
    const tar = name => fs.readFileSync(path.join(name, `fairpane-${id}.tar`));
    const manifest = name => fs.readFileSync(path.join(name, `fairpane-${id}.manifest.json`));
    assert.deepEqual(fs.readdirSync(first).sort(), [`fairpane-${id}.manifest.json`, `fairpane-${id}.tar`]);
    assert.ok(tar(first).equals(tar(second)), 'The two tar files differ.');
    assert.ok(manifest(first).equals(manifest(second)), 'The two manifests differ.');
    const m = readManifest(first, id);
    assert.equal(m.format, 'fairpane-source-manifest');
    assert.equal(m.version, 1);
    assert.match(m.git_version, /^git version /, 'The manifest does not record the Git version that wrote the tar.');
    assert.equal(m.commit, id);
    assert.equal(m.tree, git(dir, ['rev-parse', `${id}^{tree}`]));
    assert.equal(m.tar.sha256, sha256(tar(first)));
    assert.equal(m.tar.size, tar(first).length);
    assert.equal(a.tar.sha256, m.tar.sha256);
    assert.equal(b.tar.sha256, m.tar.sha256);
    // The tar is git archive's own output for the commit and prefix.
    const direct = spawnSync('git', ['-C', dir, '--no-replace-objects', 'archive', '--format=tar', `--prefix=fairpane-${id}/`, id],
      { env: fixtureEnv, windowsHide: true, maxBuffer: 64 * 1024 * 1024 });
    assert.equal(direct.status, 0, String(direct.stderr));
    assert.ok(direct.stdout.equals(tar(first)), 'The tar differs from git archive output.');
  }],
  ['FP-0027 case 2: a changed file, an added file, a removed file, and a changed mode each change the manifest, which lists exactly the tree files', async () => {
    const { sourceArchive } = await release();
    const dir = repository();
    const variants = {
      base: BASE,
      changed: BASE.map(f => f.path === 'a.txt' ? { ...f, text: 'alpha, changed\n' } : f),
      added: [...BASE, { path: 'dir/c.txt', text: 'charlie\n' }],
      removed: BASE.filter(f => f.path !== 'dir/b.txt'),
      mode: BASE.map(f => f.path === 'run.sh' ? { ...f, mode: '100755' } : f),
    };
    const manifests = {};
    for (const [name, files] of Object.entries(variants)) {
      const id = commit(dir, files), out = temp();
      sourceArchive(dir, id, out);
      manifests[name] = readManifest(out, id);
      assert.deepEqual(manifests[name].files, expectedFiles(files), `The ${name} manifest does not list exactly the tree's files.`);
      assert.equal(manifests[name].tree, git(dir, ['rev-parse', `${id}^{tree}`]));
    }
    for (const name of ['changed', 'added', 'removed', 'mode']) {
      assert.notDeepEqual(manifests[name].files, manifests.base.files, `The ${name} commit did not change the file list.`);
      assert.notEqual(manifests[name].tree, manifests.base.tree);
      assert.notEqual(manifests[name].tar.sha256, manifests.base.tar.sha256);
    }
  }],
  ['FP-0027 case 3: source-archive rejects an abbreviated ID, a ref name, a missing commit, and an output directory inside the repository, and writes nothing', async () => {
    const { sourceArchive } = await release();
    const dir = repository(), id = commit(dir, BASE);
    git(dir, ['update-ref', 'refs/heads/main', id]);
    const before = fs.readdirSync(dir).sort();
    const outside = () => path.join(temp(), 'archive');
    for (const name of [id.slice(0, 12), id.slice(0, 39), 'main', 'refs/heads/main', 'HEAD', id.toUpperCase()]) {
      const out = outside();
      rejects(() => sourceArchive(dir, name, out), /full 40-hex commit ID/);
      assert.equal(fs.existsSync(out), false, `A rejected name ${name} created its output directory.`);
    }
    const missing = id.startsWith('0') ? '1'.repeat(40) : '0'.repeat(40), out = outside();
    rejects(() => sourceArchive(dir, missing, out), /No object/);
    assert.equal(fs.existsSync(out), false, 'A missing commit created its output directory.');
    for (const inside of [path.join(dir, 'out', 'archive'), dir, path.join(dir, '.git', 'archive'), path.join(dir, 'dir', '..', 'escape')]) {
      rejects(() => sourceArchive(dir, id, inside), /inside the repository/);
    }
    assert.deepEqual(fs.readdirSync(dir).sort(), before, 'A rejected output directory wrote into the repository.');
    assert.equal(fs.existsSync(path.join(dir, '.git', 'archive')), false);
  }],
  ['FP-0027 case 4: provenance subjects equal the artifact digests, and the build definition names the commit, tree, lock digest, and builder', async () => {
    const { provenanceStatement, BUILD_COMMAND } = await release();
    const { hostPlatform } = await import('./lib.mjs');
    const dir = repository(), id = commit(dir, [...BASE, { path: 'toolchains/zig.lock.json', text: LOCK_TEXT }]);
    const out = temp(), first = path.join(out, 'first.tar'), second = path.join(out, 'second.json');
    fs.writeFileSync(first, 'first artifact\n'); fs.writeFileSync(second, '{"second":true}\n');
    const statement = provenanceStatement(dir, id, [first, second]);
    const lock = JSON.parse(LOCK_TEXT), locked = lock.platforms[hostPlatform()], tree = git(dir, ['rev-parse', `${id}^{tree}`]);
    assert.equal(statement._type, 'https://in-toto.io/Statement/v1');
    assert.equal(statement.predicateType, 'https://slsa.dev/provenance/v1');
    assert.deepEqual(statement.subject, [
      { name: 'first.tar', digest: { sha256: sha256('first artifact\n') } },
      { name: 'second.json', digest: { sha256: sha256('{"second":true}\n') } },
    ]);
    const definition = statement.predicate.buildDefinition;
    assert.deepEqual(definition.externalParameters.source, { commit: id, tree });
    assert.deepEqual(definition.externalParameters.command, BUILD_COMMAND);
    assert.deepEqual(BUILD_COMMAND, ['zig', 'build', '-Doptimize=ReleaseSafe', '--prefix', 'zig-out']);
    assert.deepEqual(definition.externalParameters.toolchain,
      { zig_version: lock.version, platform: hostPlatform(), archive_sha256: locked.sha256 });
    assert.ok(definition.resolvedDependencies.some(d => d.digest.gitCommit === id && d.digest.gitTree === tree));
    assert.ok(definition.resolvedDependencies.some(d => d.uri === locked.url && d.digest.sha256 === locked.sha256));
    assert.equal(statement.predicate.runDetails.builder.id,
      'https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md#unsigned-local-builder-1');
    const httpsUrl = uri => { try { return new URL(uri).protocol === 'https:'; } catch { return false; } };
    for (const uri of [definition.buildType, statement.predicate.runDetails.builder.id]) {
      assert.ok(httpsUrl(uri), `${uri} is not an absolute https URL, which SLSA requires.`);
    }
    assert.equal(JSON.stringify(statement).includes('signature'), false, 'An unsigned statement carries a signature field.');
    rejects(() => provenanceStatement(dir, id, []), /at least one artifact/);
    rejects(() => provenanceStatement(dir, id, [path.join(out, 'absent.bin')]), /regular file/);
    rejects(() => provenanceStatement(dir, id.slice(0, 12), [first]), /full 40-hex commit ID/);
  }],
  ['FP-0027 case 5: reproduce-check reports reproducible for a fixed build, and different with the path and exit status 1 for a clock build', async () => {
    const { reproduceCheck, reproduceExitCode, BUILD_COMMAND } = await release();
    const fixed = buildFixture(FIXED_BUILD), stand = standIn();
    // An inherited ZIG_* variable must not reach the build, because it could select a shared cache or another library.
    const inherited = { ZIG_GLOBAL_CACHE_DIR: process.env.ZIG_GLOBAL_CACHE_DIR, ZIG_LIB_DIR: process.env.ZIG_LIB_DIR };
    Object.assign(process.env, { ZIG_GLOBAL_CACHE_DIR: path.join(temp(), 'shared-cache'), ZIG_LIB_DIR: path.join(temp(), 'other-lib') });
    let same;
    try { same = reproduceCheck(fixed.dir, fixed.id, { compiler: stand.compiler }); }
    finally {
      for (const [name, value] of Object.entries(inherited)) { if (value === undefined) delete process.env[name]; else process.env[name] = value; }
    }
    assert.equal(same.result, 'reproducible', JSON.stringify(same, null, 2));
    assert.deepEqual(same.differing, []);
    assert.deepEqual(same.files.map(f => f.path), ['lib/fixed.txt']);
    assert.equal(same.files[0].a, sha256('fixed\n'));
    assert.equal(reproduceExitCode(same), 0);
    assert.deepEqual(same.build_type_command, [...BUILD_COMMAND], 'The report does not name the canonical command of build type 1.');
    const calls = stand.invocations();
    assert.equal(calls.length, 2, 'The build did not run once in each work tree.');
    assert.notEqual(calls[0].cwd, calls[1].cwd);
    for (const call of calls) {
      assert.ok(isInside(call.cwd, path.join(fixed.dir, 'out')), `The work tree ${call.cwd} is not under out/.`);
      assert.deepEqual(call.args, ['build', '-Doptimize=ReleaseSafe', '--prefix', path.join(call.cwd, 'zig-out')]);
      assert.deepEqual(call.zig, ['ZIG_GLOBAL_CACHE_DIR', 'ZIG_LOCAL_CACHE_DIR']);
      assert.deepEqual(call.fresh, [true, true], 'A cache directory existed before the build.');
      for (const cache of call.caches) assert.ok(isInside(cache, call.cwd), `The cache ${cache} is not inside its work tree.`);
    }
    assert.equal(new Set(calls.flatMap(call => call.caches)).size, 4, 'The work trees share a cache directory.');

    const clock = buildFixture(CLOCK_BUILD);
    const differs = reproduceCheck(clock.dir, clock.id, { compiler: standIn().compiler });
    assert.equal(differs.result, 'different', JSON.stringify(differs, null, 2));
    assert.deepEqual(differs.differing, ['bin/stamp.txt']);
    assert.equal(reproduceExitCode(differs), 1);
  }],
  ['FP-0027 case 6: reproduce-check removes both work trees, and a forced removal failure appears in the report', async () => {
    const { reproduceCheck, reproduceExitCode } = await release();
    const fixed = buildFixture(FIXED_BUILD);
    const clean = reproduceCheck(fixed.dir, fixed.id, { compiler: standIn().compiler });
    assert.equal(clean.result, 'reproducible');
    assert.equal(clean.work_trees.length, 2);
    for (const tree of clean.work_trees) assert.equal(fs.existsSync(tree), false, `${tree} remains after the check.`);
    assert.deepEqual(clean.removal, { removed: true, errors: [] });

    let forced = null;
    const fileSystem = { rmSync(target, options) {
      if (forced === null && path.basename(target) === 'a' && isInside(target, path.join(fixed.dir, 'out'))) {
        forced = target;
        throw Object.assign(new Error('forced removal failure'), { code: 'EACCES' });
      }
      return fs.rmSync(target, options);
    } };
    const report = reproduceCheck(fixed.dir, fixed.id, { compiler: standIn().compiler, fileSystem });
    assert.ok(forced, 'The forced failure never ran.');
    assert.equal(report.result, 'reproducible');
    assert.equal(report.removal.removed, false);
    assert.deepEqual(report.removal.errors.map(e => [e.path, e.code]), [[forced, 'EACCES']]);
    assert.match(report.removal.errors[0].message, /forced removal failure/);
    assert.equal(reproduceExitCode(report), 1, 'A removal failure must not exit with status 0.');
    assert.equal(fs.existsSync(forced), true);
    assert.equal(fs.existsSync(report.work_trees[1]), false);
    fs.rmSync(path.join(fixed.dir, 'out'), { recursive: true, force: true });
  }],
  ['FP-0027 case 7: ADR 0009 lists exactly the ten owner decisions, each with the status open', () => {
    const file = path.join(root, 'engineering/decisions/0009-release-and-stewardship.md');
    assert.ok(fs.existsSync(file), 'ADR 0009 does not exist.');
    const text = fs.readFileSync(file, 'utf8');
    const [header, separator, ...rows] = tableRows(text, '## Owner decisions');
    assert.deepEqual(header, ['Decision', 'Status', 'Blocks', 'Evidence that records it']);
    assert.ok(separator.every(cell => /^-+$/.test(cell)));
    assert.deepEqual(rows.map(r => r[0]), OWNER_DECISIONS);
    for (const row of rows) {
      assert.equal(row.length, 4, `${row[0]} does not have four cells.`);
      assert.equal(row[1], '`open`', `${row[0]} is not open.`);
      assert.ok(row[2].length > 0 && row[3].length > 0, `${row[0]} lacks what it blocks or its evidence.`);
    }
    assert.match(text, /The agent makes none of these decisions\./);
    assert.match(text, /Each decision stays `open` until an owner record exists\./);
  }],
  ['FP-0027: source-archive fails before any write when an export attribute makes the tar differ from the tree', async () => {
    const { sourceArchive } = await release();
    const dir = repository();
    for (const attributes of ['secret.txt export-ignore\n', 'subst.txt export-subst\n']) {
      const id = commit(dir, [...BASE, { path: '.gitattributes', text: attributes }, { path: 'secret.txt', text: 'kept\n' },
        { path: 'subst.txt', text: '$Format:%H$\n' }]);
      const out = path.join(temp(), 'archive');
      rejects(() => sourceArchive(dir, id, out), /archive (lacks 1 files of the tree|entry .* differs)/);
      assert.equal(fs.existsSync(out), false, `${attributes.trim()} wrote an output directory.`);
    }
  }],
  ['FP-0027: reproduce-check reports a failed build as an error with exit status 1 and still removes both work trees', async () => {
    const { reproduceCheck, reproduceExitCode } = await release();
    const broken = buildFixture('process.exit(7);\n');
    const report = reproduceCheck(broken.dir, broken.id, { compiler: standIn().compiler });
    assert.equal(report.result, 'error');
    assert.match(report.error, /exit status 7/);
    assert.equal(report.builds.length, 1, 'The second tree built after the first build failed.');
    assert.equal(reproduceExitCode(report), 1);
    assert.deepEqual(report.removal, { removed: true, errors: [] });
    for (const tree of report.work_trees) assert.equal(fs.existsSync(tree), false);
    const empty = buildFixture('// This build installs nothing.\n');
    const nothing = reproduceCheck(empty.dir, empty.id, { compiler: standIn().compiler });
    assert.equal(nothing.result, 'error');
    assert.match(nothing.error, /installed no files/);
    assert.equal(reproduceExitCode(nothing), 1);
  }],
].map(([name, fn]) => ({ name, fn }));

export function removeReleaseFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of releaseCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeReleaseFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${releaseCases.length}\n# tests ${releaseCases.length}\n# pass ${releaseCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
