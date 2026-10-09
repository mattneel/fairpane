/** Fairpane corpus snapshots. Inventories come from Git objects, never from a working tree. No code from a corpus runs. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { invariant, readJson, writeJson, sha256, resolveExecutable, treeStopProgram, stopProcessTree } from './lib.mjs';
import { FILE_SET_IDS, FILE_SET_RULES, classifyFileSet, commitSnapshot, deriveFileSet, fetchFileSet, verifyFileSet, withFetchLock } from './fileset.mjs';

const OID = /^[0-9a-f]{40}$/, HASH = /^[0-9a-f]{64}$/;
const COMMIT_DATE = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$/;
const UTC_TIME = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{3})?Z$/;
const BLOB_MODES = new Set(['100644', '100755', '120000']);
const LOCAL_TIMEOUT_MS = 600000, NETWORK_TIMEOUT_MS = 3600000;
/**
 * Corpora that `corpus-fetch` can pin, with the upstream license file, the pattern that reads its stated name,
 * and whether the snapshot keeps the wpt.fyi manifest.
 */
export const CORPUS_RULES = Object.freeze({
  test262: { license: 'LICENSE', licenseName: /made available under the\s+"([^"\r\n]+)"/, manifest: false },
  wpt: { license: 'LICENSE.md', licenseName: /^#[ \t]+([^\r\n]*\S)[ \t]*\r?$/m, manifest: true },
});
export const TEST262_RULE = 'Count Git tree entries of the pinned commit whose type is blob, whose raw path starts with "test/" and ends with ".js", ' +
  'and whose file name, the last path component, does not contain "_FIXTURE". ' +
  'Group the count by the second path component; a file directly under test/ counts under ".".';

export function corporaRoot(root, env = process.env) {
  return env.FAIRPANE_CORPORA_DIR ? path.resolve(env.FAIRPANE_CORPORA_DIR) : path.join(root, '.tools', 'corpora');
}
export function snapshotGitDir(corporaDir, id) { return path.join(corporaDir, id, 'repository.git'); }
export function snapshotManifest(corporaDir, id) { return path.join(corporaDir, id, 'MANIFEST.json'); }
const defaultPolicyFile = root => path.join(root, 'specs', 'corpora.json');
function corpusRule(id) {
  invariant(typeof id === 'string' && Object.hasOwn(CORPUS_RULES, id), `No snapshot rule exists for corpus ${id}. Supported: ${Object.keys(CORPUS_RULES).join(', ')}.`);
  return CORPUS_RULES[id];
}
/**
 * Corpus upstreams are HTTPS Git URLs. Controller tests pass `allowFileUpstream` to fetch from local `file://` fixture repositories;
 * no controller command sets it.
 */
const upstreamAllowed = (upstream, allowFileUpstream) => typeof upstream === 'string' &&
  (upstream.startsWith('https://') || (allowFileUpstream === true && upstream.startsWith('file://')));
function corpusPolicy(policyFile, id, allowFileUpstream = false) {
  const entry = readJson(policyFile).corpora.find(c => c.id === id);
  invariant(entry, `The corpus policy does not list corpus ${id}.`);
  invariant(upstreamAllowed(entry.upstream, allowFileUpstream), `Corpus ${id} has no HTTPS Git upstream.`);
  return entry;
}
const recordRelative = id => `specs/snapshots/${id}.json`;
const recordPath = (root, id) => path.join(root, ...recordRelative(id).split('/'));
const applicabilityPath = (root, id) => path.join(root, 'specs', 'applicability', `${id}.json`);

// Git processes. Prompts and replace objects stay disabled, inherited GIT_* variables are dropped, and every child has a watchdog.
let gitPath;
function gitExecutable() { return (gitPath ??= resolveExecutable(process.cwd(), 'git')); }
function gitEnv() {
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^GIT_/i.test(name)));
  return { ...env, GIT_TERMINAL_PROMPT: '0' };
}
const gitArgv = (gitDir, args) => ['--no-replace-objects', ...(gitDir ? [`--git-dir=${gitDir}`] : []), ...args];
function watchedGit(argv, { timeoutMs, stdio }) {
  // The watchdog's stop program is resolved first, so a resolution failure starts no git process.
  const taskkill = treeStopProgram();
  const child = spawn(gitExecutable(), argv, { stdio, env: gitEnv(), shell: false, windowsHide: true, detached: process.platform !== 'win32' });
  let timedOut = false;
  const stop = () => { if (child.exitCode === null) stopProcessTree(child, taskkill); };
  const timer = setTimeout(() => { timedOut = true; stop(); }, timeoutMs);
  const done = new Promise(resolve => {
    child.on('error', error => { clearTimeout(timer); resolve({ code: null, signal: null, timedOut, error }); });
    child.on('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, timedOut, error: null }); });
  });
  return { child, done, stop };
}
function describeExit(label, r, stderr = '') {
  if (r.timedOut) return `${label} exceeded its watchdog and was stopped.`;
  if (r.error) return `${label} could not start: ${r.error.message}`;
  return `${label} exited with status ${r.code}${r.signal ? ` (signal ${r.signal})` : ''}${stderr.trim() ? `: ${stderr.trim()}` : '.'}`;
}
/** Run git and collect its standard output. */
async function git(gitDir, args, { timeoutMs = LOCAL_TIMEOUT_MS, allowFailure = false } = {}) {
  const { child, done } = watchedGit(gitArgv(gitDir, args), { timeoutMs, stdio: ['ignore', 'pipe', 'pipe'] });
  const out = [], err = [];
  child.stdout.on('data', c => out.push(c)); child.stderr.on('data', c => err.push(c));
  const r = await done;
  if (r.code === 0 && !r.timedOut) return Buffer.concat(out);
  if (allowFailure && !r.timedOut && !r.error) return null;
  throw new Error(describeExit(`git ${args[0]}`, r, Buffer.concat(err).toString('utf8')));
}
/** Run git with inherited output so the caller's evidence log receives it. */
async function gitVisible(gitDir, args, timeoutMs) {
  const argv = gitArgv(gitDir, args);
  console.log(`Run ${JSON.stringify([gitExecutable(), ...argv])}`);
  const r = await watchedGit(argv, { timeoutMs, stdio: ['ignore', 'inherit', 'inherit'] }).done;
  invariant(r.code === 0 && !r.timedOut, describeExit(`git ${args[0]}`, r));
}

/** List every non-tree entry of a commit's tree. Paths stay raw bytes. A path with a line feed fails, because the inventory is line-based. */
export async function listTree(gitDir, commit) {
  invariant(OID.test(commit), `A 40-hex commit ID is required: ${commit}`);
  const out = await git(gitDir, ['ls-tree', '-r', '-z', '--full-tree', commit]);
  const entries = [];
  for (let start = 0; start < out.length;) {
    const end = out.indexOf(0, start);
    invariant(end !== -1, 'git ls-tree output ended without a NUL terminator.');
    const tab = out.indexOf(9, start);
    invariant(tab !== -1 && tab < end, 'git ls-tree output has an entry without a path.');
    const m = /^(\d{6}) (blob|commit) ([0-9a-f]{40})$/.exec(out.toString('latin1', start, tab));
    invariant(m, `Unexpected git ls-tree entry: ${out.toString('latin1', start, tab)}`);
    invariant(m[2] === 'commit' ? m[1] === '160000' : BLOB_MODES.has(m[1]), `Unsupported tree entry mode ${m[1]} for a ${m[2]}.`);
    const entryPath = Buffer.from(out.subarray(tab + 1, end));
    invariant(!entryPath.includes(10), `A tree path contains a line feed: ${JSON.stringify(entryPath.toString('utf8'))}`);
    entries.push({ mode: m[1], type: m[2], oid: m[3], path: entryPath });
    start = end + 1;
  }
  invariant(entries.length > 0, `Commit ${commit} has an empty tree.`);
  return entries;
}

/**
 * Stream blob contents through `git cat-file --batch`.
 * `handlers.start(oid, size)`, `handlers.data(chunk)`, and `handlers.end()` run once per requested ID, in order.
 */
export async function streamBlobs(gitDir, oids, handlers, { timeoutMs = LOCAL_TIMEOUT_MS } = {}) {
  if (oids.length === 0) return;
  const { child, done, stop } = watchedGit(gitArgv(gitDir, ['cat-file', '--batch']), { timeoutMs, stdio: ['pipe', 'pipe', 'pipe'] });
  const err = [];
  let failure = null, index = 0, state = 'header', header = [], remaining = 0;
  const fail = e => { failure ??= e; stop(); };
  child.stderr.on('data', c => err.push(c));
  child.stdin.on('error', e => fail(e));
  child.stdout.on('data', chunk => {
    if (failure) return;
    try {
      for (let i = 0; i < chunk.length;) {
        if (state === 'header') {
          const nl = chunk.indexOf(10, i);
          if (nl === -1) { header.push(chunk.subarray(i)); break; }
          header.push(chunk.subarray(i, nl)); i = nl + 1;
          const line = Buffer.concat(header).toString('latin1'); header = [];
          invariant(index < oids.length, 'git cat-file returned more objects than requested.');
          invariant(line !== `${oids[index]} missing`, `The snapshot is missing object ${oids[index]}.`);
          const m = /^([0-9a-f]{40}) (\S+) (\d+)$/.exec(line);
          invariant(m && m[1] === oids[index], `Unexpected git cat-file header: ${line}`);
          invariant(m[2] === 'blob', `Object ${m[1]} is a ${m[2]}, not a blob.`);
          remaining = Number(m[3]);
          handlers.start(m[1], remaining);
          state = remaining ? 'body' : 'trailer';
        } else if (state === 'body') {
          const n = Math.min(remaining, chunk.length - i);
          handlers.data(chunk.subarray(i, i + n)); i += n; remaining -= n;
          if (!remaining) state = 'trailer';
        } else {
          invariant(chunk[i] === 10, 'git cat-file output lost its object framing.');
          i++; index++; state = 'header'; handlers.end();
        }
      }
    } catch (e) { fail(e); }
  });
  child.stdin.end(`${oids.join('\n')}\n`);
  const r = await done;
  if (failure) throw failure;
  invariant(r.code === 0 && !r.timedOut, describeExit('git cat-file', r, Buffer.concat(err).toString('utf8')));
  invariant(index === oids.length && state === 'header', `git cat-file returned ${index} of ${oids.length} objects.`);
}

/**
 * Canonical inventory: one line per entry, sorted by raw path bytes.
 * Blob and symbolic link: `<mode>\t<sha256>\t<size>\t<path>\n`. Submodule: `160000\t<commit>\t0\t<path>\n`.
 */
export async function computeInventory(gitDir, entries, { keepLines = false } = {}) {
  const digests = new Map();
  const unique = [...new Set(entries.filter(e => e.type === 'blob').map(e => e.oid))];
  let hash, size;
  await streamBlobs(gitDir, unique, {
    start(_, n) { hash = crypto.createHash('sha256'); size = n; },
    data(chunk) { hash.update(chunk); },
    end() { digests.set(unique[digests.size], { sha256: hash.digest('hex'), size }); },
  });
  const sorted = [...entries].sort((a, b) => Buffer.compare(a.path, b.path));
  const total = crypto.createHash('sha256'), lines = keepLines ? [] : null, newline = Buffer.from('\n');
  let blobBytes = 0;
  for (let i = 0; i < sorted.length; i++) {
    const e = sorted[i];
    invariant(i === 0 || !sorted[i - 1].path.equals(e.path), `The tree repeats a path: ${e.path.toString('utf8')}`);
    const d = e.type === 'blob' ? digests.get(e.oid) : null;
    if (d) blobBytes += d.size;
    const line = Buffer.concat([Buffer.from(d ? `${e.mode}\t${d.sha256}\t${d.size}\t` : `160000\t${e.oid}\t0\t`), e.path, newline]);
    total.update(line); lines?.push(line);
  }
  const inventory = { entry_count: sorted.length, total_blob_bytes: blobBytes, sha256: total.digest('hex') };
  return keepLines ? { ...inventory, text: Buffer.concat(lines) } : inventory;
}

function formatCommitDate(rawCommit) {
  const m = /^committer .*> (\d+) ([+-])(\d\d)(\d\d)$/m.exec(rawCommit);
  invariant(m, 'The commit has no committer date.');
  const offsetMinutes = (m[2] === '-' ? -1 : 1) * (Number(m[3]) * 60 + Number(m[4]));
  const local = new Date((Number(m[1]) + offsetMinutes * 60) * 1000).toISOString().slice(0, 19);
  return `${local}${m[2]}${m[3]}:${m[4]}`;
}
async function commitObject(gitDir, commit) {
  const type = await git(gitDir, ['cat-file', '-t', commit], { allowFailure: true });
  invariant(type?.toString('latin1').trim() === 'commit', `The snapshot does not contain commit ${commit}.`);
  const raw = (await git(gitDir, ['cat-file', 'commit', commit])).toString('utf8');
  const tree = /^tree ([0-9a-f]{40})\n/.exec(raw);
  invariant(tree, `Commit ${commit} has no tree line.`);
  return { tree: tree[1], commit_date: formatCommitDate(raw) };
}
async function regularFile(gitDir, entries, file) {
  const wanted = Buffer.from(file), entry = entries.find(e => e.path.equals(wanted));
  invariant(entry && entry.mode === '100644', `The snapshot has no regular file at ${file}.`);
  return git(gitDir, ['cat-file', 'blob', entry.oid]);
}
async function licenseRecord(gitDir, id, entries) {
  const rule = corpusRule(id), text = await regularFile(gitDir, entries, rule.license);
  const name = rule.licenseName.exec(text.toString('utf8'));
  invariant(name, `The license file ${rule.license} does not state a license name in the expected form.`);
  return { path: rule.license, size: text.length, sha256: sha256(text), name: name[1].trim() };
}

// The WPT manifest. wpt.fyi publishes the manifest that upstream continuous integration built for each commit.
// The controller trusts its item types and checks that every path and hash matches the pinned tree.
export const WPT_MANIFEST_VERSION = 9;
export const wptManifestUrl = commit => `https://wpt.fyi/api/manifest?sha=${commit}`;
/** Download the manifest for `commit`. The response must name that commit in its `x-wpt-sha` header. */
export async function downloadWptManifest(commit, file, { url = wptManifestUrl(commit), timeoutMs = NETWORK_TIMEOUT_MS } = {}) {
  invariant(OID.test(commit), `A 40-hex commit ID is required: ${commit}`);
  console.log(`Download ${url}`);
  const response = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  const served = response.headers.get('x-wpt-sha');
  if (response.status !== 200 || served !== commit) {
    await response.body?.cancel();
    invariant(response.status === 200, `The manifest request returned HTTP status ${response.status}.`);
    throw new Error(`The manifest response has x-wpt-sha ${JSON.stringify(served)}, not the pinned commit ${commit}.`);
  }
  const body = Buffer.from(await response.arrayBuffer()), digest = sha256(body);
  fs.writeFileSync(file, body, { flag: 'wx' });
  console.log(`x-wpt-sha ${served}, ${body.length} bytes, SHA-256 ${digest}`);
  return { url, size: body.length, sha256: digest };
}
/** Visit every manifest file entry as `(type, path, leaf)`; upstream `TypeData.to_json` writes each leaf as `[hash, ...items]`. */
function walkManifest(manifest, visit) {
  invariant(manifest?.version === WPT_MANIFEST_VERSION, `The WPT manifest version is ${JSON.stringify(manifest?.version)}, not ${WPT_MANIFEST_VERSION}.`);
  invariant(manifest.items && typeof manifest.items === 'object' && !Array.isArray(manifest.items), 'The WPT manifest has no items object.');
  for (const type of Object.keys(manifest.items).sort()) {
    for (const stack = [[manifest.items[type], '']]; stack.length;) {
      const [node, prefix] = stack.pop();
      invariant(node && typeof node === 'object' && !Array.isArray(node), `The WPT manifest has an invalid node in ${type} at "${prefix}".`);
      for (const [name, value] of Object.entries(node)) {
        const file = prefix + name;
        if (!Array.isArray(value)) stack.push([value, `${file}/`]);
        else { invariant(value.length >= 2, `The WPT manifest entry ${file} in ${type} has no items.`); visit(type, file, value); }
      }
    }
  }
}
/**
 * Upstream gives the "test262" type to a ".js" file with a "test262" directory component only when no earlier rule of `manifest_items` applies to it,
 * its name does not end in "_FIXTURE.js", and it contains a "/*---" to "---*\/" frontmatter block; any other such file becomes a "support" item.
 * The type is not limited to the vendored copy, so only the vendored Test262 copy under third_party/test262/ stays outside WPT discovery.
 * "spec" and "support" items are not tests.
 */
const WPT_NOT_TESTS = new Set(['spec', 'support']);
const WPT_VENDORED_TEST262_DIR = 'third_party/test262/';
const isVendoredTest262 = (type, file) => type === 'test262' && file.startsWith(WPT_VENDORED_TEST262_DIR);
const isWptTest = (type, file) => !WPT_NOT_TESTS.has(type) && !isVendoredTest262(type, file);
/** Require every manifest path to exist in the pinned tree with the manifest hash as its Git blob ID, and require at least one test item. */
export function bindWptManifest(manifest, entries) {
  const tree = new Map(entries.map(e => [e.path.toString('latin1'), e])), problems = [];
  let paths = 0, tests = 0;
  walkManifest(manifest, (type, file, leaf) => {
    paths++;
    if (isWptTest(type, file)) tests += leaf.length - 1;
    const e = tree.get(Buffer.from(file, 'utf8').toString('latin1'));
    if (!e) problems.push(`${file}: the pinned tree has no such path`);
    else if (e.type !== 'blob') problems.push(`${file}: the pinned tree entry is a ${e.type}, not a blob`);
    else if (leaf[0] !== e.oid) problems.push(`${file}: the manifest hash ${JSON.stringify(leaf[0])} differs from blob ${e.oid}`);
  });
  invariant(problems.length === 0, `The WPT manifest does not match the pinned tree at ${problems.length} paths:\n- ${problems.slice(0, 20).join('\n- ')}`);
  invariant(tests > 0, `The WPT manifest has no test items in its ${paths} file entries.`);
  return { paths };
}
/** Read a stored manifest and bind it to the pinned tree. */
function loadWptManifest(file, entries) {
  invariant(fs.existsSync(file), `Missing WPT manifest: ${file}`);
  const bytes = fs.readFileSync(file);
  let manifest;
  try { manifest = JSON.parse(bytes.toString('utf8')); } catch (e) { throw new Error(`The WPT manifest is not JSON: ${e.message}`); }
  bindWptManifest(manifest, entries);
  return { manifest, size: bytes.length, sha256: sha256(bytes) };
}

export async function buildSnapshotRecord(gitDir, { corpus, upstream, ref, commit, retrieved_at }, { manifestFile, allowFileUpstream = false } = {}) {
  const rule = corpusRule(corpus), { tree, commit_date } = await commitObject(gitDir, commit);
  const entries = await listTree(gitDir, commit);
  const record = { schema_version: 1, corpus, upstream, ref, commit, tree, commit_date, retrieved_at,
    license: await licenseRecord(gitDir, corpus, entries), inventory: await computeInventory(gitDir, entries) };
  if (rule.manifest) {
    invariant(manifestFile, `A snapshot of ${corpus} needs its manifest.`);
    const m = loadWptManifest(manifestFile, entries);
    record.manifest = { url: wptManifestUrl(commit), size: m.size, sha256: m.sha256 };
  }
  validateSnapshotRecord(record, { allowFileUpstream });
  return record;
}

export function validateSnapshotRecord(r, { allowFileUpstream = false } = {}) {
  invariant(r?.schema_version === 1, 'The snapshot record schema is invalid.');
  invariant(typeof r.corpus === 'string' && /^[a-z0-9][a-z0-9-]*$/.test(r.corpus), 'The snapshot record needs a corpus ID.');
  invariant(upstreamAllowed(r.upstream, allowFileUpstream), 'The snapshot record needs an HTTPS upstream.');
  invariant(typeof r.ref === 'string' && /^refs\/heads\/[^\s~^:?*[\\]+$/.test(r.ref), 'The snapshot record needs an upstream branch ref.');
  invariant(typeof r.commit === 'string' && OID.test(r.commit), 'The snapshot commit must be 40 lowercase hex digits.');
  invariant(typeof r.tree === 'string' && OID.test(r.tree), 'The snapshot tree must be 40 lowercase hex digits.');
  invariant(typeof r.commit_date === 'string' && COMMIT_DATE.test(r.commit_date), 'The snapshot needs an ISO 8601 committer date.');
  invariant(typeof r.retrieved_at === 'string' && UTC_TIME.test(r.retrieved_at), 'The snapshot needs a UTC retrieval time.');
  const l = r.license;
  invariant(l && typeof l.path === 'string' && l.path.length > 0, 'The snapshot needs a license path.');
  invariant(Number.isSafeInteger(l.size) && l.size > 0, 'The snapshot needs a license size.');
  invariant(typeof l.sha256 === 'string' && HASH.test(l.sha256), 'The snapshot needs a license SHA-256.');
  invariant(typeof l.name === 'string' && l.name.trim().length > 0, 'The snapshot needs a stated license name.');
  const i = r.inventory;
  invariant(i && Number.isSafeInteger(i.entry_count) && i.entry_count > 0, 'The snapshot needs an inventory entry count.');
  invariant(Number.isSafeInteger(i.total_blob_bytes) && i.total_blob_bytes >= 0, 'The snapshot needs inventory blob bytes.');
  invariant(typeof i.sha256 === 'string' && HASH.test(i.sha256), 'The snapshot needs an inventory SHA-256.');
  const m = r.manifest;
  if (CORPUS_RULES[r.corpus]?.manifest) {
    invariant(m && m.url === wptManifestUrl(r.commit), 'The snapshot needs the wpt.fyi manifest URL for its commit.');
    invariant(Number.isSafeInteger(m.size) && m.size > 0, 'The snapshot needs a manifest size.');
    invariant(typeof m.sha256 === 'string' && HASH.test(m.sha256), 'The snapshot needs a manifest SHA-256.');
  } else invariant(m === undefined, `A snapshot of ${r.corpus} has no manifest.`);
  return true;
}

const isCount = n => Number.isSafeInteger(n) && n >= 0;
/**
 * A valid record has an explicit denominator: `selected + excluded + unclassified = discovered`.
 * A Git corpus names its `commit`; a file-set corpus names its `version` and the `inventories` of its sources instead.
 */
export function validateApplicability(a) {
  invariant(a?.schema_version === 1, 'The applicability schema is invalid.');
  invariant(typeof a.corpus === 'string' && a.corpus.length > 0, 'Applicability needs a corpus ID.');
  if (FILE_SET_IDS.includes(a.corpus)) {
    invariant(a.commit === undefined, 'File-set applicability names a version, not a commit.');
    invariant(typeof a.version === 'string' && a.version.trim().length > 0, 'File-set applicability needs a version.');
    const inventories = a.inventories && typeof a.inventories === 'object' ? Object.values(a.inventories) : [];
    invariant(inventories.length > 0 && inventories.every(h => typeof h === 'string' && HASH.test(h)), 'File-set applicability needs its inventory digests.');
  } else invariant(typeof a.commit === 'string' && OID.test(a.commit), 'Applicability needs a 40-hex corpus commit.');
  invariant(a.status === 'counted', 'Applicability status must be counted.');
  invariant(typeof a.discovery?.rule === 'string' && a.discovery.rule.trim(), 'Applicability needs an exact discovery rule.');
  invariant(Array.isArray(a.excluded), 'Applicability needs an exclusion list.');
  for (const x of a.excluded) {
    invariant(typeof x?.path === 'string' && x.path.length > 0, 'An exclusion needs a test path.');
    invariant(typeof x.reason === 'string' && x.reason.trim().length > 0, `The exclusion ${x.path} has no reason.`);
  }
  for (const field of ['discovered', 'selected', 'unclassified']) invariant(isCount(a[field]), `Applicability ${field} must be a nonnegative integer.`);
  invariant(a.discovered > 0, 'Applicability has zero discovered tests, so it has no denominator.');
  invariant(a.selected + a.excluded.length + a.unclassified === a.discovered, 'Applicability counts are inconsistent: selected + excluded + unclassified must equal discovered.');
  invariant(typeof a.breakdown?.by === 'string' && a.breakdown.counts && typeof a.breakdown.counts === 'object', 'Applicability needs a count breakdown.');
  const parts = Object.values(a.breakdown.counts);
  invariant(parts.every(isCount), 'Applicability breakdown counts must be nonnegative integers.');
  invariant(parts.reduce((s, n) => s + n, 0) === a.discovered, 'Applicability breakdown counts do not sum to discovered.');
  return true;
}

// Applicability discovery.
const TEST_PREFIX = Buffer.from('test/'), JS_SUFFIX = Buffer.from('.js'), FIXTURE_MARK = Buffer.from('_FIXTURE');
const endsWith = (b, s) => b.length >= s.length && b.subarray(b.length - s.length).equals(s);
const sortedKeys = object => Object.fromEntries(Object.entries(object).sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))));
export function test262Applicability(commit, entries) {
  const counts = {};
  let discovered = 0;
  for (const e of entries) {
    if (e.type !== 'blob' || !e.path.subarray(0, TEST_PREFIX.length).equals(TEST_PREFIX) || !endsWith(e.path, JS_SUFFIX)) continue;
    if (e.path.subarray(e.path.lastIndexOf(0x2f) + 1).includes(FIXTURE_MARK)) continue;
    const rest = e.path.subarray(TEST_PREFIX.length), slash = rest.indexOf(0x2f);
    const key = slash === -1 ? '.' : rest.subarray(0, slash).toString('utf8');
    counts[key] = (counts[key] ?? 0) + 1; discovered++;
  }
  return { schema_version: 1, corpus: 'test262', commit, status: 'counted',
    discovery: { rule: TEST262_RULE, command: 'node tools/fairpane.mjs corpus-applicability test262' },
    discovered, selected: 0, excluded: [], unclassified: discovered,
    breakdown: { by: 'top-level directory under test/', counts: sortedKeys(counts) } };
}

const WPT_VENDORED_TEST262 = `${WPT_VENDORED_TEST262_DIR}vendored.toml`;
/** What each top-level directory of the vendored Test262 copy holds, as Test262 itself uses it. */
const WPT_VENDORED_TEST262_CONTENT = Object.freeze({
  [`${WPT_VENDORED_TEST262_DIR}harness/`]: 'Test262 harness includes, not tests',
  [`${WPT_VENDORED_TEST262_DIR}test/`]: 'Test262 tests',
});
export const WPT_RULE = 'Read the manifest that wpt.fyi publishes for the pinned commit after binding every manifest path and hash to the Git blob IDs of the pinned tree. ' +
  'Count the items of each manifest item type; each file entry contributes its array length minus one, because the first element is the file hash and each other element is one test URL. ' +
  `Discovered tests are the items of every type except "spec" and "support", minus the "test262" items whose path starts with "${WPT_VENDORED_TEST262_DIR}", the vendored Test262 copy. ` +
  'Upstream gives the "test262" type to a ".js" file with a "test262" directory component only when no earlier rule of manifest_items applies to it, ' +
  'its name does not end in "_FIXTURE.js", and it contains a "/*---" to "---*/" frontmatter block; any other such file becomes a "support" item. ' +
  'The "test262" type therefore does not identify the vendored copy, and "test262" items elsewhere, such as the WPT tests under "infrastructure/test262/", count in discovery. ' +
  `The record reports the vendored "test262" items separately, counted by their directory under "${WPT_VENDORED_TEST262_DIR}", with the vendored Test262 revision from ${WPT_VENDORED_TEST262}.`;
/** The vendored-copy directory of a manifest path under third_party/test262/, such as "third_party/test262/test/". */
function vendoredPrefix(file) {
  const rest = file.slice(WPT_VENDORED_TEST262_DIR.length), slash = rest.indexOf('/');
  return slash === -1 ? WPT_VENDORED_TEST262_DIR : `${WPT_VENDORED_TEST262_DIR}${rest.slice(0, slash + 1)}`;
}
/** Count manifest items by type, WPT tests by type, and vendored Test262 items by their directory under third_party/test262/. */
export function wptManifestCounts(manifest) {
  const items = {}, tests = {}, vendored = {};
  walkManifest(manifest, (type, file, leaf) => {
    const n = leaf.length - 1;
    items[type] = (items[type] ?? 0) + n;
    if (isWptTest(type, file)) tests[type] = (tests[type] ?? 0) + n;
    else if (isVendoredTest262(type, file)) { const p = vendoredPrefix(file); vendored[p] = (vendored[p] ?? 0) + n; }
  });
  return { item_counts: items, test_counts: tests, discovered: Object.values(tests).reduce((s, n) => s + n, 0), vendored_test262: sortedKeys(vendored) };
}
async function vendoredTest262(gitDir, entries) {
  const text = (await regularFile(gitDir, entries, WPT_VENDORED_TEST262)).toString('utf8');
  const source = /^source = "([^"\r\n]+)"\r?$/m.exec(text)?.[1], revision = /^rev = "([0-9a-f]{40})"\r?$/m.exec(text)?.[1];
  invariant(source && revision, `${WPT_VENDORED_TEST262} does not state a source and a 40-hex rev.`);
  return { path: WPT_VENDORED_TEST262, source, revision };
}
/** The vendored Test262 items, which stay outside WPT discovery. The vendored revision describes only these items. */
async function vendoredTest262Report(gitDir, entries, byPrefix) {
  const prefixes = Object.entries(byPrefix);
  if (prefixes.length === 0) return {};
  return { test262: { path: WPT_VENDORED_TEST262_DIR, items: prefixes.reduce((s, [, n]) => s + n, 0),
    by_prefix: Object.fromEntries(prefixes.map(([p, items]) => [p, { items, content: WPT_VENDORED_TEST262_CONTENT[p] ?? 'Other files of the vendored Test262 copy' }])),
    vendored: await vendoredTest262(gitDir, entries),
    reason: `Fairpane runs Test262 from its own pinned test262 corpus, so the vendored copy under ${WPT_VENDORED_TEST262_DIR} stays outside the WPT denominator. ` +
      'Every other "test262" item is a WPT test and counts in discovery.' } };
}
async function wptApplicability(gitDir, record, entries, loaded) {
  const counts = wptManifestCounts(loaded.manifest);
  return { schema_version: 1, corpus: 'wpt', commit: record.commit, status: 'counted',
    discovery: { rule: WPT_RULE, command: 'node tools/fairpane.mjs corpus-applicability wpt' },
    manifest: { url: record.manifest.url, size: loaded.size, sha256: loaded.sha256, version: loaded.manifest.version, item_counts: counts.item_counts },
    discovered: counts.discovered, selected: 0, excluded: [], unclassified: counts.discovered,
    breakdown: { by: 'WPT manifest item type', counts: counts.test_counts },
    reported_separately: await vendoredTest262Report(gitDir, entries, counts.vendored_test262) };
}
async function discover(id, gitDir, record, entries, manifest) {
  return id === 'test262' ? test262Applicability(record.commit, entries) : wptApplicability(gitDir, record, entries, manifest);
}

// Controller commands.
function readRecord(root, id, allowFileUpstream) {
  const file = recordPath(root, id);
  invariant(fs.existsSync(file), `Missing snapshot record: ${recordRelative(id)}`);
  const record = readJson(file);
  validateSnapshotRecord(record, { allowFileUpstream });
  invariant(record.corpus === id, `The snapshot record names corpus ${record.corpus}, not ${id}.`);
  return record;
}
async function loadSnapshot(root, id, corporaDir, allowFileUpstream) {
  corpusRule(id);
  const record = readRecord(root, id, allowFileUpstream), gitDir = snapshotGitDir(corporaDir, id);
  invariant(fs.existsSync(path.join(gitDir, 'HEAD')), `Missing snapshot: ${gitDir}`);
  return { record, gitDir };
}
/** Compare a snapshot record with the pins of its corpus policy entry. A null pin field pins nothing. */
function pinProblems(pins, id, record) {
  const problems = [];
  const check = (field, actual) => {
    if (pins[field] != null && pins[field] !== actual) problems.push(`pin ${field}: pinned ${JSON.stringify(pins[field])}, snapshot has ${JSON.stringify(actual)}`);
  };
  check('revision', record.commit);
  check('inventory_sha256', record.inventory.sha256);
  check('license_record', recordRelative(id));
  check('manifest_sha256', record.manifest?.sha256 ?? null);
  return problems;
}
async function resolveHead(upstream) {
  const args = ['ls-remote', '--symref', upstream, 'HEAD'];
  console.log(`Run ${JSON.stringify([gitExecutable(), ...gitArgv(null, args)])}`);
  const remote = (await git(null, args, { timeoutMs: NETWORK_TIMEOUT_MS })).toString('utf8');
  process.stdout.write(remote);
  const ref = /^ref: (refs\/heads\/\S+)\tHEAD$/m.exec(remote)?.[1], commit = /^([0-9a-f]{40})\tHEAD$/m.exec(remote)?.[1];
  invariant(ref && commit, 'git ls-remote did not report a branch and commit for HEAD.');
  return { ref, commit };
}
/**
 * Fetch `commit` into a fresh repository beside the snapshot, build and check its record, and only then replace the snapshot.
 * The new repository starts empty, so `fetch.fsckObjects` and `transfer.fsckObjects` check every fetched object.
 * Setting both keeps a `fetch.fsckObjects=false` from user or system configuration from disabling those checks.
 * The fetch holds `<id>.lock` throughout, and `commitSnapshot`, the write phase that file sets share, replaces the snapshot and the record.
 * `onWriteStep(label)`, which only tests pass, runs before each write step and may throw to inject a failure.
 */
async function replaceSnapshot(root, id, { upstream, ref, commit, corporaDir, check, allowFileUpstream, onWriteStep }) {
  const target = path.join(corporaDir, id), staging = path.join(corporaDir, `${id}.fetch`), old = path.join(corporaDir, `${id}.old`);
  const gitDir = path.join(staging, 'repository.git');
  return withFetchLock(corporaDir, id, async () => {
    fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
    fs.mkdirSync(gitDir, { recursive: true });
    try {
      await gitVisible(null, ['init', '--bare', '--quiet', gitDir], LOCAL_TIMEOUT_MS);
      await gitVisible(gitDir, ['-c', 'fetch.fsckObjects=true', '-c', 'transfer.fsckObjects=true', '-c', 'protocol.version=2', 'fetch', '--depth=1', '--no-tags',
        '--no-write-fetch-head', upstream, `+${commit}:${ref}`], NETWORK_TIMEOUT_MS);
      const retrieved_at = new Date().toISOString();
      const fetched = (await git(gitDir, ['rev-parse', '--verify', `${ref}^{commit}`])).toString('latin1').trim();
      invariant(fetched === commit, `The fetch produced ${fetched}, not the requested commit ${commit}.`);
      let manifestFile;
      if (corpusRule(id).manifest) await downloadWptManifest(commit, (manifestFile = path.join(staging, 'MANIFEST.json')));
      const record = await buildSnapshotRecord(gitDir, { corpus: id, upstream, ref, commit, retrieved_at }, { manifestFile, allowFileUpstream });
      const problems = check(record);
      invariant(problems.length === 0, `The fetched snapshot of ${id} does not match its pin, so the existing snapshot stays:\n- ${problems.join('\n- ')}`);
      commitSnapshot({ target, staging, old, recordFile: recordPath(root, id), record, onWriteStep });
      return { snapshot: snapshotGitDir(corporaDir, id), record };
    } catch (e) {
      fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
      throw e;
    }
  });
}

/**
 * Fetch the pinned commit: the `specs/corpora.json` revision, or else the commit of the existing snapshot record.
 * A file-set corpus downloads its frozen sources instead; controller tests pass `rules` and `allowFileSources` for `file://` fixture sources.
 * Tests also pass `onWriteStep` to inject a failure into the write phase of either kind of corpus.
 */
export async function fetchCorpus(root, id, { corporaDir = corporaRoot(root), policyFile = defaultPolicyFile(root), allowFileUpstream = false,
  rules = FILE_SET_RULES, allowFileSources = false, onWriteStep } = {}) {
  if (Object.hasOwn(rules, id)) {
    return fetchFileSet(root, id, { corporaDir, policy: corpusPolicy(policyFile, id, allowFileUpstream), rule: rules[id], allowFileSources, onWriteStep });
  }
  corpusRule(id);
  const policy = corpusPolicy(policyFile, id, allowFileUpstream), recordFile = recordPath(root, id);
  let pins = policy, pinSource = 'specs/corpora.json';
  if (policy.revision == null) {
    invariant(fs.existsSync(recordFile), `Corpus ${id} has no pinned revision and no snapshot record. Run corpus-repin ${id}.`);
    const recorded = readJson(recordFile);
    pins = { revision: recorded.commit, inventory_sha256: recorded.inventory?.sha256 ?? null, manifest_sha256: recorded.manifest?.sha256 ?? null };
    pinSource = recordRelative(id);
  }
  invariant(typeof pins.revision === 'string' && OID.test(pins.revision), `The pinned revision of ${id} is not a 40-hex commit ID: ${pins.revision}`);
  console.log(`Git: ${gitExecutable()} (${(await git(null, ['--version'])).toString('utf8').trim()})`);
  console.log(`Pinned commit ${pins.revision} from ${pinSource}.`);
  const { ref } = await resolveHead(policy.upstream);
  const { snapshot, record } = await replaceSnapshot(root, id, { upstream: policy.upstream, ref, commit: pins.revision, corporaDir,
    check: r => pinProblems(pins, id, r), allowFileUpstream, onWriteStep });
  return { result: 'pass', corpus: id, snapshot, pinned_by: pinSource, record: recordRelative(id), ...record };
}

/**
 * Move a snapshot to the upstream branch head. The new commit needs a protected `specs/corpora.json` change before verification passes.
 * Tests pass `onWriteStep` to inject a failure into the write phase.
 */
export async function repinCorpus(root, id, { corporaDir = corporaRoot(root), policyFile = defaultPolicyFile(root), allowFileUpstream = false,
  onWriteStep } = {}) {
  invariant(!FILE_SET_IDS.includes(id), `corpus-repin does not apply to the file-set corpus ${id}: version selection is a contract decision. ` +
    'A task contract freezes the sources in tools/fileset.mjs, and corpus-fetch downloads exactly those sources.');
  corpusRule(id);
  const policy = corpusPolicy(policyFile, id, allowFileUpstream);
  console.log(`Git: ${gitExecutable()} (${(await git(null, ['--version'])).toString('utf8').trim()})`);
  const head = await resolveHead(policy.upstream);
  const { snapshot, record } = await replaceSnapshot(root, id, { upstream: policy.upstream, ...head, corporaDir, check: () => [], allowFileUpstream,
    onWriteStep });
  const pending = pinProblems(policy, id, record);
  return { result: 'pass', corpus: id, snapshot, record: recordRelative(id), ...record, pin_differences: pending,
    note: `Run corpus-applicability ${id}. ` + (pending.length ? 'corpus-verify fails until a protected change to specs/corpora.json records the new pin.' :
      'specs/corpora.json pins nothing that differs from this snapshot.') };
}

/** List each pinnable corpus whose applicability record is missing or has no valid denominator. */
function missingDenominators(root) {
  const missing = [];
  for (const id of [...Object.keys(CORPUS_RULES), ...FILE_SET_IDS]) {
    const file = applicabilityPath(root, id);
    if (!fs.existsSync(file)) { missing.push({ corpus: id, reason: `Missing specs/applicability/${id}.json` }); continue; }
    try { validateApplicability(readJson(file)); } catch (e) { missing.push({ corpus: id, reason: e.message }); }
  }
  return missing;
}

export async function verifyCorpus(root, id, { corporaDir = corporaRoot(root), policyFile = defaultPolicyFile(root), allowFileUpstream = false,
  allowFileSources = false } = {}) {
  if (FILE_SET_IDS.includes(id)) {
    const policy = corpusPolicy(policyFile, id, allowFileUpstream);
    const { record, applicability } = verifyFileSet(root, id, { corporaDir, policy, discoveryKind: FILE_SET_RULES[id].discovery,
      validateApplicability, allowFileSources });
    const missing = missingDenominators(root);
    return { result: missing.length ? 'incomplete' : 'pass', corpus: id, kind: 'file-set', version: record.version,
      sources: record.sources.map(s => ({ id: s.id, size: s.size, sha256: s.sha256, inventory: s.inventory })),
      selected: record.selected.length, derived: record.derived.length, applicability, missing_denominators: missing,
      note: 'Verification rehashed the local sources, their inventories, and every selected, derived, and license file. It does not qualify any engine behavior.' };
  }
  const { record, gitDir } = await loadSnapshot(root, id, corporaDir, allowFileUpstream);
  const policy = corpusPolicy(policyFile, id, allowFileUpstream), problems = [];
  const expect = (field, recorded, actual) => {
    if (recorded !== actual) problems.push(`${field}: recorded ${JSON.stringify(recorded)}, found ${JSON.stringify(actual)}`);
  };
  expect('upstream', record.upstream, policy.upstream);
  // Every object must hash to its ID, so the recorded commit ID binds the tree, the committer date, and every blob.
  try { await git(gitDir, ['fsck', '--full', '--strict', '--no-dangling', '--no-progress']); } catch (e) { problems.push(`fsck: ${e.message}`); }
  const local = await git(gitDir, ['rev-parse', '--verify', '--quiet', `${record.ref}^{commit}`], { allowFailure: true });
  expect(`commit at ${record.ref}`, record.commit, local ? local.toString('latin1').trim() : null);
  const commitFields = await commitObject(gitDir, record.commit);
  const entries = await listTree(gitDir, record.commit);
  const license = await licenseRecord(gitDir, id, entries), inventory = await computeInventory(gitDir, entries);
  expect('tree', record.tree, commitFields.tree);
  expect('commit_date', record.commit_date, commitFields.commit_date);
  for (const k of ['path', 'size', 'sha256', 'name']) expect(`license.${k}`, record.license[k], license[k]);
  for (const k of ['entry_count', 'total_blob_bytes', 'sha256']) expect(`inventory.${k}`, record.inventory[k], inventory[k]);
  let manifest = null;
  if (corpusRule(id).manifest) {
    try { manifest = loadWptManifest(snapshotManifest(corporaDir, id), entries); } catch (e) { problems.push(`manifest: ${e.message}`); }
    if (manifest) for (const k of ['size', 'sha256']) expect(`manifest.${k}`, record.manifest[k], manifest[k]);
  }
  problems.push(...pinProblems(policy, id, record));
  const applicability = await checkApplicability(root, id, gitDir, record, entries, manifest, problems);
  invariant(problems.length === 0, `Corpus ${id} failed verification:\n- ${problems.join('\n- ')}`);
  const missing = missingDenominators(root);
  return { result: missing.length ? 'incomplete' : 'pass', corpus: id, snapshot: gitDir, commit: record.commit, tree: commitFields.tree,
    inventory, license, manifest: manifest && { url: record.manifest.url, size: manifest.size, sha256: manifest.sha256 }, applicability,
    missing_denominators: missing,
    note: 'Verification read Git objects and the stored manifest only. It does not qualify any engine behavior.' };
}

async function checkApplicability(root, id, gitDir, record, entries, manifest, problems) {
  const file = applicabilityPath(root, id);
  if (!fs.existsSync(file)) { problems.push(`Missing applicability record: specs/applicability/${id}.json`); return null; }
  const a = readJson(file);
  try { validateApplicability(a); } catch (e) { problems.push(`applicability: ${e.message}`); return null; }
  if (a.corpus !== id) problems.push(`applicability.corpus: recorded ${JSON.stringify(a.corpus)}, expected ${JSON.stringify(id)}`);
  if (a.commit !== record.commit) problems.push(`applicability.commit: recorded ${a.commit}, snapshot ${record.commit}`);
  if (id === 'test262' || manifest) {
    const fresh = await discover(id, gitDir, record, entries, manifest);
    if (JSON.stringify(fresh) !== JSON.stringify(a)) problems.push('applicability: the recorded discovery differs from the snapshot.');
  }
  return { discovered: a.discovered, selected: a.selected, excluded: a.excluded.length, unclassified: a.unclassified };
}

/** Write `specs/applicability/<id>.json` from the local snapshot. No network access and no corpus code are used. */
export async function classifyCorpus(root, id, { corporaDir = corporaRoot(root), allowFileUpstream = false, allowFileSources = false } = {}) {
  if (FILE_SET_IDS.includes(id)) {
    const a = classifyFileSet(root, id, { corporaDir, discoveryKind: FILE_SET_RULES[id].discovery, allowFileSources });
    validateApplicability(a);
    writeJson(applicabilityPath(root, id), a);
    return { result: 'pass', record: `specs/applicability/${id}.json`, ...a };
  }
  const { record, gitDir } = await loadSnapshot(root, id, corporaDir, allowFileUpstream);
  await commitObject(gitDir, record.commit);
  const entries = await listTree(gitDir, record.commit);
  let manifest = null;
  if (corpusRule(id).manifest) {
    manifest = loadWptManifest(snapshotManifest(corporaDir, id), entries);
    invariant(manifest.size === record.manifest.size && manifest.sha256 === record.manifest.sha256,
      `The stored manifest differs from ${recordRelative(id)}. Run corpus-fetch ${id}.`);
  }
  const a = await discover(id, gitDir, record, entries, manifest);
  validateApplicability(a);
  writeJson(applicabilityPath(root, id), a);
  return { result: 'pass', record: `specs/applicability/${id}.json`, ...a };
}

/** Run each declared import-tool derivation of a file-set corpus and record it. */
export async function deriveCorpus(root, id, { corporaDir = corporaRoot(root) } = {}) {
  invariant(FILE_SET_IDS.includes(id), `corpus-derive applies only to the file-set corpora: ${FILE_SET_IDS.join(', ')}.`);
  return deriveFileSet(root, id, { corporaDir, rule: FILE_SET_RULES[id] });
}

// Extraction. FP-0082 and later tasks read an extracted Test262 tree; no corpus code runs.
const EXTRACT_PREFIXES = [Buffer.from('test/'), Buffer.from('harness/')], EXTRACT_FEATURES = Buffer.from('features.txt');
const EXTRACT_MODES = new Set(['100644', '100755']);
/** Returns why a tree path cannot be written under the output directory, or null. */
export function extractPathProblem(entryPath) {
  let start = 0;
  for (let i = 0; i <= entryPath.length; i++) {
    if (i < entryPath.length && entryPath[i] !== 0x2f) continue;
    const component = entryPath.subarray(start, i).toString('latin1');
    if (component === '') return 'an empty path component';
    if (component === '.' || component === '..') return `a "${component}" path component`;
    start = i + 1;
  }
  return null;
}
/** The Git blob object ID of `bytes`. */
function blobId(bytes) {
  return crypto.createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
}
/**
 * Write every blob of the pinned tree whose path starts with "test/" or "harness/", and "features.txt", to `outDir`,
 * which must lie under `<root>/out/` and be absent or empty. Each written file must hash to its tree object ID.
 * `EXTRACT.json` records the commit, the tree, the file count, and the SHA-256 of the sorted lines `<oid> <path>\n`.
 */
export async function extractCorpus(root, id, outDir, { corporaDir = corporaRoot(root), allowFileUpstream = false } = {}) {
  invariant(id === 'test262', `corpus-extract applies only to test262, not ${id}.`);
  const outRoot = path.resolve(root, 'out'), target = path.resolve(root, outDir);
  invariant(target.startsWith(`${outRoot}${path.sep}`), `The output directory must lie under ${outRoot}${path.sep}: ${target}`);
  invariant(!fs.existsSync(target) || (fs.statSync(target).isDirectory() && fs.readdirSync(target).length === 0),
    `The output directory must be absent or empty: ${target}`);
  const { record, gitDir } = await loadSnapshot(root, id, corporaDir, allowFileUpstream);
  const { tree } = await commitObject(gitDir, record.commit);
  const entries = (await listTree(gitDir, record.commit))
    .filter(e => e.path.equals(EXTRACT_FEATURES) || EXTRACT_PREFIXES.some(p => e.path.subarray(0, p.length).equals(p)))
    .sort((a, b) => Buffer.compare(a.path, b.path));
  for (const e of entries) {
    const shown = e.path.toString('utf8');
    invariant(e.type === 'blob' && EXTRACT_MODES.has(e.mode), `${shown} has mode ${e.mode}, not 100644 or 100755.`);
    const problem = extractPathProblem(e.path);
    invariant(problem === null, `${shown} has ${problem}.`);
  }
  invariant(entries.some(e => e.path.equals(EXTRACT_FEATURES)), 'The pinned tree has no features.txt.');
  fs.mkdirSync(target, { recursive: true });
  let index = 0, chunks = [];
  await streamBlobs(gitDir, entries.map(e => e.oid), {
    start() { chunks = []; },
    data(chunk) { chunks.push(Buffer.from(chunk)); },
    end() {
      const e = entries[index++], file = path.join(target, ...e.path.toString('utf8').split('/'));
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, Buffer.concat(chunks), { flag: 'wx' });
      const written = blobId(fs.readFileSync(file));
      invariant(written === e.oid, `${e.path.toString('utf8')}: the written file hashes to ${written}, not to its tree object ID ${e.oid}.`);
    },
  });
  const lines = entries.map(e => Buffer.concat([Buffer.from(`${e.oid} `), e.path, Buffer.from('\n')]));
  const extract = { schema_version: 1, corpus: id, commit: record.commit, tree, files: entries.length, entries_sha256: sha256(Buffer.concat(lines)) };
  writeJson(path.join(target, 'EXTRACT.json'), extract);
  return { result: 'pass', out: target, ...extract,
    note: 'Extraction wrote Git blobs whose content hashes to their tree object IDs. No corpus code ran.' };
}

export async function corpusCommand(root, command, args) {
  if (command === 'corpus-extract') {
    invariant(args.length === 2, `Usage: ${command} <corpus-id> <out-dir>`);
    return extractCorpus(root, args[0], args[1]);
  }
  invariant(args.length === 1, `Usage: ${command} <corpus-id>`);
  const run = { 'corpus-fetch': fetchCorpus, 'corpus-repin': repinCorpus, 'corpus-verify': verifyCorpus, 'corpus-applicability': classifyCorpus,
    'corpus-derive': deriveCorpus }[command];
  invariant(run, `Unknown corpus command: ${command}`);
  return run(root, args[0]);
}
