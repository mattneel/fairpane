/** Fairpane corpus snapshots. Inventories come from Git objects, never from a working tree. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { invariant, readJson, writeJson, sha256, fileHash, resolveExecutable } from './lib.mjs';

const OID = /^[0-9a-f]{40}$/, HASH = /^[0-9a-f]{64}$/;
const COMMIT_DATE = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$/;
const UTC_TIME = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{3})?Z$/;
const BLOB_MODES = new Set(['100644', '100755', '120000']);
const LOCAL_TIMEOUT_MS = 600000, NETWORK_TIMEOUT_MS = 3600000;
/** Corpora that `corpus-fetch` can pin, with the upstream license file and the pattern that reads its stated name. */
export const CORPUS_RULES = Object.freeze({
  test262: { license: 'LICENSE', licenseName: /made available under the\s+"([^"\r\n]+)"/ },
  wpt: { license: 'LICENSE.md', licenseName: /^#[ \t]+([^\r\n]*\S)[ \t]*\r?$/m },
});
export const TEST262_RULE = 'Count Git tree entries of the pinned commit whose type is blob, whose raw path starts with "test/" and ends with ".js", ' +
  'and whose path does not end with "_FIXTURE.js". Group the count by the second path component; a file directly under test/ counts under ".".';

export function corporaRoot(root, env = process.env) {
  return env.FAIRPANE_CORPORA_DIR ? path.resolve(env.FAIRPANE_CORPORA_DIR) : path.join(root, '.tools', 'corpora');
}
export function snapshotGitDir(corporaDir, id) { return path.join(corporaDir, id, 'repository.git'); }
function corpusRule(id) {
  invariant(typeof id === 'string' && Object.hasOwn(CORPUS_RULES, id), `No snapshot rule exists for corpus ${id}. Supported: ${Object.keys(CORPUS_RULES).join(', ')}.`);
  return CORPUS_RULES[id];
}
function corpusPolicy(root, id) {
  const entry = readJson(path.join(root, 'specs', 'corpora.json')).corpora.find(c => c.id === id);
  invariant(entry, `specs/corpora.json does not list corpus ${id}.`);
  return entry;
}
const recordPath = (root, id) => path.join(root, 'specs', 'snapshots', `${id}.json`);
const applicabilityPath = (root, id) => path.join(root, 'specs', 'applicability', `${id}.json`);

// Git processes. Prompts stay disabled, and every child has a watchdog.
let gitPath;
function gitExecutable() { return (gitPath ??= resolveExecutable(process.cwd(), 'git')); }
const gitEnv = () => ({ ...process.env, GIT_TERMINAL_PROMPT: '0' });
function killTree(child) {
  if (!child.pid || child.exitCode !== null) return;
  if (process.platform === 'win32') {
    const k = spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, timeout: 10000 });
    if (k.error || k.status !== 0) child.kill('SIGKILL');
  } else {
    try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
  }
}
function watched(executable, args, { timeoutMs, stdio, env = gitEnv(), cwd } = {}) {
  const child = spawn(executable, args, { stdio, env, cwd, shell: false, windowsHide: true, detached: process.platform !== 'win32' });
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; killTree(child); }, timeoutMs);
  const done = new Promise(resolve => {
    child.on('error', error => { clearTimeout(timer); resolve({ code: null, signal: null, timedOut, error }); });
    child.on('close', (code, signal) => { clearTimeout(timer); resolve({ code, signal, timedOut, error: null }); });
  });
  return { child, done };
}
function describeExit(label, r, stderr = '') {
  if (r.timedOut) return `${label} exceeded its watchdog and was stopped.`;
  if (r.error) return `${label} could not start: ${r.error.message}`;
  return `${label} exited with status ${r.code}${r.signal ? ` (signal ${r.signal})` : ''}${stderr.trim() ? `: ${stderr.trim()}` : '.'}`;
}
/** Run git and collect its standard output. */
async function git(gitDir, args, { timeoutMs = LOCAL_TIMEOUT_MS, allowFailure = false } = {}) {
  const argv = gitDir ? [`--git-dir=${gitDir}`, ...args] : args;
  const { child, done } = watched(gitExecutable(), argv, { timeoutMs, stdio: ['ignore', 'pipe', 'pipe'] });
  const out = [], err = [];
  child.stdout.on('data', c => out.push(c)); child.stderr.on('data', c => err.push(c));
  const r = await done;
  if (r.code === 0 && !r.timedOut) return Buffer.concat(out);
  if (allowFailure && !r.timedOut && !r.error) return null;
  throw new Error(describeExit(`git ${args[0]}`, r, Buffer.concat(err).toString('utf8')));
}
/** Run git with inherited output so the caller's evidence log receives it. */
async function gitVisible(gitDir, args, timeoutMs) {
  const argv = gitDir ? [`--git-dir=${gitDir}`, ...args] : args;
  console.log(`Run ${JSON.stringify([gitExecutable(), ...argv])}`);
  const r = await watched(gitExecutable(), argv, { timeoutMs, stdio: ['ignore', 'inherit', 'inherit'] }).done;
  invariant(r.code === 0 && !r.timedOut, describeExit(`git ${args[0]}`, r));
}

/** List every non-tree entry of a commit's tree. Paths stay raw bytes. */
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
    entries.push({ mode: m[1], type: m[2], oid: m[3], path: Buffer.from(out.subarray(tab + 1, end)) });
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
  const { child, done } = watched(gitExecutable(), [`--git-dir=${gitDir}`, 'cat-file', '--batch'],
    { timeoutMs, stdio: ['pipe', 'pipe', 'pipe'] });
  const err = [];
  let failure = null, index = 0, state = 'header', header = [], remaining = 0;
  const fail = e => { failure ??= e; killTree(child); };
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
async function licenseRecord(gitDir, id, entries) {
  const rule = corpusRule(id), wanted = Buffer.from(rule.license);
  const entry = entries.find(e => e.path.equals(wanted));
  invariant(entry && entry.mode === '100644', `The snapshot has no regular license file at ${rule.license}.`);
  const text = await git(gitDir, ['cat-file', 'blob', entry.oid]);
  const name = rule.licenseName.exec(text.toString('utf8'));
  invariant(name, `The license file ${rule.license} does not state a license name in the expected form.`);
  return { path: rule.license, size: text.length, sha256: sha256(text), name: name[1].trim() };
}
/** Read every derived snapshot field from Git objects. */
export async function describeSnapshot(gitDir, id, commit, entries) {
  const commitFields = await commitObject(gitDir, commit);
  entries ??= await listTree(gitDir, commit);
  return { ...commitFields, license: await licenseRecord(gitDir, id, entries), inventory: await computeInventory(gitDir, entries) };
}
export async function buildSnapshotRecord(gitDir, { corpus, upstream, ref, commit, retrieved_at }) {
  const d = await describeSnapshot(gitDir, corpus, commit);
  const record = { schema_version: 1, corpus, upstream, ref, commit, tree: d.tree, commit_date: d.commit_date,
    retrieved_at, license: d.license, inventory: d.inventory };
  validateSnapshotRecord(record);
  return record;
}

export function validateSnapshotRecord(r) {
  invariant(r?.schema_version === 1, 'The snapshot record schema is invalid.');
  invariant(typeof r.corpus === 'string' && /^[a-z0-9][a-z0-9-]*$/.test(r.corpus), 'The snapshot record needs a corpus ID.');
  invariant(typeof r.upstream === 'string' && r.upstream.startsWith('https://'), 'The snapshot record needs an HTTPS upstream.');
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
  return true;
}

const isCount = n => Number.isSafeInteger(n) && n >= 0;
export function validateApplicability(a) {
  invariant(a?.schema_version === 1, 'The applicability schema is invalid.');
  invariant(typeof a.corpus === 'string' && a.corpus.length > 0, 'Applicability needs a corpus ID.');
  invariant(typeof a.commit === 'string' && OID.test(a.commit), 'Applicability needs a 40-hex corpus commit.');
  invariant(typeof a.discovery?.rule === 'string' && a.discovery.rule.trim(), 'Applicability needs an exact discovery rule.');
  invariant(Array.isArray(a.excluded), 'Applicability needs an exclusion list.');
  for (const x of a.excluded) {
    invariant(typeof x?.path === 'string' && x.path.length > 0, 'An exclusion needs a test path.');
    invariant(typeof x.reason === 'string' && x.reason.trim().length > 0, `The exclusion ${x.path} has no reason.`);
  }
  if (a.status === 'blocked') {
    invariant(typeof a.blocker?.reason === 'string' && a.blocker.reason.trim(), 'A blocked applicability record needs a blocker.');
    invariant(a.discovered === null && a.selected === null && a.unclassified === null && a.breakdown === null && a.excluded.length === 0,
      'A blocked applicability record cannot record counts.');
    return true;
  }
  invariant(a.status === 'counted', 'Applicability status must be counted or blocked.');
  for (const field of ['discovered', 'selected', 'unclassified']) invariant(isCount(a[field]), `Applicability ${field} must be a nonnegative integer.`);
  invariant(a.selected + a.excluded.length + a.unclassified === a.discovered, 'Applicability counts are inconsistent: selected + excluded + unclassified must equal discovered.');
  invariant(typeof a.breakdown?.by === 'string' && a.breakdown.counts && typeof a.breakdown.counts === 'object', 'Applicability needs a count breakdown.');
  const parts = Object.values(a.breakdown.counts);
  invariant(parts.every(isCount), 'Applicability breakdown counts must be nonnegative integers.');
  invariant(parts.reduce((s, n) => s + n, 0) === a.discovered, 'Applicability breakdown counts do not sum to discovered.');
  return true;
}

// Applicability discovery.
const TEST_PREFIX = Buffer.from('test/'), JS_SUFFIX = Buffer.from('.js'), FIXTURE_SUFFIX = Buffer.from('_FIXTURE.js');
const endsWith = (b, s) => b.length >= s.length && b.subarray(b.length - s.length).equals(s);
export function test262Applicability(commit, entries) {
  const counts = {};
  let discovered = 0;
  for (const e of entries) {
    if (e.type !== 'blob' || !e.path.subarray(0, TEST_PREFIX.length).equals(TEST_PREFIX)) continue;
    if (!endsWith(e.path, JS_SUFFIX) || endsWith(e.path, FIXTURE_SUFFIX)) continue;
    const rest = e.path.subarray(TEST_PREFIX.length), slash = rest.indexOf(0x2f);
    const key = slash === -1 ? '.' : rest.subarray(0, slash).toString('utf8');
    counts[key] = (counts[key] ?? 0) + 1; discovered++;
  }
  const sorted = Object.fromEntries(Object.entries(counts).sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))));
  return { schema_version: 1, corpus: 'test262', commit, status: 'counted',
    discovery: { rule: TEST262_RULE, command: 'node tools/fairpane.mjs corpus-applicability test262' },
    discovered, selected: 0, excluded: [], unclassified: discovered,
    breakdown: { by: 'top-level directory under test/', counts: sorted } };
}

/** Write a working copy from Git objects only. Symbolic links become files that hold the target text, as Git does without symlink support. */
async function materialize(gitDir, entries, dir) {
  const decoder = new TextDecoder('utf-8', { fatal: true }), folded = new Set();
  const windows = process.platform === 'win32', foldCase = windows || process.platform === 'darwin';
  const files = entries.map(e => {
    let relative;
    try { relative = decoder.decode(e.path); } catch { throw new Error(`A tree path is not UTF-8: ${e.path.toString('hex')}`); }
    const parts = relative.split('/');
    for (const p of parts) {
      invariant(p && p !== '.' && p !== '..' && p.toLowerCase() !== '.git' && !p.includes('\\') && !/[\x00-\x1f]/.test(p), `Unsafe tree path: ${relative}`);
      if (windows) invariant(!/[<>:"|?*]|[. ]$|^(con|prn|aux|nul|com\d|lpt\d)(\..*)?$/i.test(p), `The tree path cannot exist on Windows: ${relative}`);
    }
    if (foldCase) {
      invariant(!folded.has(relative.toLowerCase()), `The tree has a case-insensitive path collision: ${relative}`);
      folded.add(relative.toLowerCase());
    }
    return { entry: e, file: path.join(dir, ...parts) };
  });
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  for (const f of files) if (f.entry.type === 'commit') fs.mkdirSync(f.file, { recursive: true });
  const blobs = files.filter(f => f.entry.type === 'blob');
  let index = 0, fd = null;
  try {
    await streamBlobs(gitDir, blobs.map(f => f.entry.oid), {
      start() {
        const f = blobs[index];
        fs.mkdirSync(path.dirname(f.file), { recursive: true });
        fd = fs.openSync(f.file, 'wx', f.entry.mode === '100755' ? 0o755 : 0o644);
      },
      data(chunk) { for (let o = 0; o < chunk.length;) o += fs.writeSync(fd, chunk, o, chunk.length - o); },
      end() { fs.closeSync(fd); fd = null; index++; },
    });
  } finally { if (fd !== null) fs.closeSync(fd); }
  return { files: blobs.length, submodule_directories: files.length - blobs.length };
}

const WPT_NON_TEST_TYPES = new Set(['spec', 'support']);
export const WPT_RULE = 'Run the WPT manifest tool from the pinned commit over a working copy written from the pinned Git objects. ' +
  'Count the items of each manifest item type; each file entry contributes its array length minus one, because the first element is the file hash. ' +
  'Discovered tests are the items of every type except "spec" and "support".';
/** Count manifest items without trusting the manifest's own metadata. */
export function wptManifestCounts(manifestFile) {
  const manifest = readJson(manifestFile);
  invariant(manifest?.items && typeof manifest.items === 'object', 'The WPT manifest has no items object.');
  const items = {};
  for (const type of Object.keys(manifest.items).sort()) {
    let n = 0;
    for (const stack = [manifest.items[type]]; stack.length;) {
      for (const v of Object.values(stack.pop())) {
        if (Array.isArray(v)) { invariant(v.length >= 2, `A WPT manifest file entry has no items in ${type}.`); n += v.length - 1; }
        else { invariant(v && typeof v === 'object', `The WPT manifest has an invalid node in ${type}.`); stack.push(v); }
      }
    }
    items[type] = n;
  }
  const tests = Object.fromEntries(Object.entries(items).filter(([t]) => !WPT_NON_TEST_TYPES.has(t)));
  return { version: manifest.version, item_counts: items, test_counts: tests,
    discovered: Object.values(tests).reduce((s, n) => s + n, 0) };
}
async function wptApplicability(root, record, gitDir, entries, corporaDir) {
  const base = path.join(corporaDir, 'wpt'), checkout = path.join(base, 'checkout'), manifest = path.join(base, 'MANIFEST.json');
  console.log(`Write the working copy ${checkout} from Git objects.`);
  console.log(JSON.stringify(await materialize(gitDir, entries, checkout)));
  const python = resolveExecutable(root, 'python');
  const version = spawnSync(python, ['--version'], { encoding: 'utf8', timeout: 30000, windowsHide: true });
  invariant(!version.error && version.status === 0, `python --version failed: ${version.error?.message ?? version.stderr}`);
  const pythonVersion = (version.stdout || version.stderr).trim();
  // `--skip-venv-setup` stops the launcher from creating a virtual environment and installing packages, so the run needs no network.
  // The launcher requires `--venv` with that flag; the named directory is never created.
  const template = ['python', '<checkout>/wpt', '--venv', '<corpora-root>/wpt/no-venv', '--skip-venv-setup', 'manifest', '--no-download', '--rebuild',
    '--path', '<corpora-root>/wpt/MANIFEST.json', '--tests-root', '<checkout>', '--cache-root', '<corpora-root>/wpt/wptcache'];
  const expand = a => {
    const m = /^<(checkout|corpora-root)>(.*)$/.exec(a);
    return m ? path.join(m[1] === 'checkout' ? checkout : corporaDir, ...m[2].split('/').filter(Boolean)) : a;
  };
  const args = template.slice(1).map(expand);
  fs.rmSync(manifest, { force: true });
  console.log(`Run ${JSON.stringify([python, ...args])} (${pythonVersion})`);
  const { child, done } = watched(python, args, { timeoutMs: NETWORK_TIMEOUT_MS, stdio: ['ignore', 'pipe', 'pipe'], cwd: checkout,
    env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' } });
  let tail = '';
  const keep = (stream, sink) => stream.on('data', c => { sink.write(c); tail = (tail + c.toString('utf8')).slice(-8000); });
  keep(child.stdout, process.stdout); keep(child.stderr, process.stderr);
  const r = await done;
  const tool = { revision: record.commit, command: template, python: pythonVersion,
    note: 'Placeholders name the local snapshot directories. The evidence log keeps the absolute command.' };
  const common = { schema_version: 1, corpus: 'wpt', commit: record.commit };
  if (r.code !== 0 || r.timedOut || !fs.existsSync(manifest)) {
    return { ...common, status: 'blocked', discovery: { rule: WPT_RULE, command: 'node tools/fairpane.mjs corpus-applicability wpt', tool },
      blocker: { reason: describeExit('The WPT manifest tool', r), output_tail: tail },
      discovered: null, selected: null, excluded: [], unclassified: null, breakdown: null };
  }
  const counts = wptManifestCounts(manifest);
  return { ...common, status: 'counted', discovery: { rule: WPT_RULE, command: 'node tools/fairpane.mjs corpus-applicability wpt', tool },
    manifest: { sha256: fileHash(manifest), size: fs.statSync(manifest).size, version: counts.version, item_counts: counts.item_counts },
    discovered: counts.discovered, selected: 0, excluded: [], unclassified: counts.discovered,
    breakdown: { by: 'WPT manifest item type', counts: counts.test_counts } };
}

// Controller commands.
async function loadSnapshot(root, id, corporaDir) {
  corpusRule(id);
  const file = recordPath(root, id);
  invariant(fs.existsSync(file), `Missing snapshot record: specs/snapshots/${id}.json`);
  const record = readJson(file);
  validateSnapshotRecord(record);
  invariant(record.corpus === id, `The snapshot record names corpus ${record.corpus}, not ${id}.`);
  const gitDir = snapshotGitDir(corporaDir, id);
  invariant(fs.existsSync(path.join(gitDir, 'HEAD')), `Missing snapshot: ${gitDir}`);
  return { record, gitDir };
}

export async function fetchCorpus(root, id, { corporaDir = corporaRoot(root) } = {}) {
  corpusRule(id);
  const { upstream } = corpusPolicy(root, id);
  invariant(typeof upstream === 'string' && upstream.startsWith('https://'), `Corpus ${id} has no HTTPS Git upstream.`);
  console.log(`Git: ${gitExecutable()} (${(await git(null, ['--version'])).toString('utf8').trim()})`);
  console.log(`Run ${JSON.stringify([gitExecutable(), 'ls-remote', '--symref', upstream, 'HEAD'])}`);
  const remote = (await git(null, ['ls-remote', '--symref', upstream, 'HEAD'], { timeoutMs: NETWORK_TIMEOUT_MS })).toString('utf8');
  process.stdout.write(remote);
  const ref = /^ref: (refs\/heads\/\S+)\tHEAD$/m.exec(remote)?.[1], commit = /^([0-9a-f]{40})\tHEAD$/m.exec(remote)?.[1];
  invariant(ref && commit, 'git ls-remote did not report a branch and commit for HEAD.');
  const gitDir = snapshotGitDir(corporaDir, id);
  if (!fs.existsSync(path.join(gitDir, 'HEAD'))) {
    fs.mkdirSync(gitDir, { recursive: true });
    await gitVisible(null, ['init', '--bare', '--quiet', gitDir], LOCAL_TIMEOUT_MS);
  }
  await gitVisible(gitDir, ['-c', 'transfer.fsckObjects=true', '-c', 'protocol.version=2', 'fetch', '--depth=1', '--no-tags',
    '--no-write-fetch-head', upstream, `+${commit}:${ref}`], NETWORK_TIMEOUT_MS);
  const retrieved_at = new Date().toISOString();
  const fetched = (await git(gitDir, ['rev-parse', '--verify', `${ref}^{commit}`])).toString('latin1').trim();
  invariant(fetched === commit, `The fetch produced ${fetched}, not the reported commit ${commit}.`);
  const record = await buildSnapshotRecord(gitDir, { corpus: id, upstream, ref, commit, retrieved_at });
  writeJson(recordPath(root, id), record);
  return { result: 'pass', corpus: id, snapshot: gitDir, record: `specs/snapshots/${id}.json`, ...record };
}

export async function verifyCorpus(root, id, { corporaDir = corporaRoot(root) } = {}) {
  const { record, gitDir } = await loadSnapshot(root, id, corporaDir);
  const problems = [];
  const expect = (field, recorded, actual) => {
    if (recorded !== actual) problems.push(`${field}: recorded ${JSON.stringify(recorded)}, found ${JSON.stringify(actual)}`);
  };
  expect('upstream', record.upstream, corpusPolicy(root, id).upstream);
  const local = await git(gitDir, ['rev-parse', '--verify', '--quiet', `${record.ref}^{commit}`], { allowFailure: true });
  expect(`commit at ${record.ref}`, record.commit, local ? local.toString('latin1').trim() : null);
  const commitFields = await commitObject(gitDir, record.commit);
  const entries = await listTree(gitDir, record.commit);
  const license = await licenseRecord(gitDir, id, entries), inventory = await computeInventory(gitDir, entries);
  expect('tree', record.tree, commitFields.tree);
  expect('commit_date', record.commit_date, commitFields.commit_date);
  for (const k of ['path', 'size', 'sha256', 'name']) expect(`license.${k}`, record.license[k], license[k]);
  for (const k of ['entry_count', 'total_blob_bytes', 'sha256']) expect(`inventory.${k}`, record.inventory[k], inventory[k]);
  const applicability = await checkApplicability(root, id, record, entries, corporaDir, problems);
  invariant(problems.length === 0, `Corpus ${id} failed verification:\n- ${problems.join('\n- ')}`);
  return { result: 'pass', corpus: id, snapshot: gitDir, commit: record.commit, tree: commitFields.tree, inventory,
    license, applicability, note: 'Verification read Git objects only. It does not qualify any engine behavior.' };
}

async function checkApplicability(root, id, record, entries, corporaDir, problems) {
  const file = applicabilityPath(root, id);
  if (!fs.existsSync(file)) { problems.push(`Missing applicability record: specs/applicability/${id}.json`); return null; }
  const a = readJson(file);
  try { validateApplicability(a); } catch (e) { problems.push(`applicability: ${e.message}`); return null; }
  if (a.corpus !== id) problems.push(`applicability.corpus: recorded ${JSON.stringify(a.corpus)}, expected ${JSON.stringify(id)}`);
  if (a.commit !== record.commit) problems.push(`applicability.commit: recorded ${a.commit}, snapshot ${record.commit}`);
  if (id === 'test262') {
    const fresh = test262Applicability(record.commit, entries);
    if (JSON.stringify(fresh) !== JSON.stringify(a)) problems.push('applicability: the recorded Test262 discovery differs from the snapshot.');
  } else if (id === 'wpt' && a.status === 'counted') {
    const manifest = path.join(corporaDir, id, 'MANIFEST.json');
    if (!fs.existsSync(manifest)) problems.push(`applicability: the WPT manifest is missing: ${manifest}`);
    else {
      const digest = fileHash(manifest);
      if (digest !== a.manifest.sha256) problems.push(`applicability.manifest.sha256: recorded ${a.manifest.sha256}, found ${digest}`);
      else {
        const c = wptManifestCounts(manifest);
        if (JSON.stringify([c.item_counts, c.test_counts, c.discovered]) !== JSON.stringify([a.manifest.item_counts, a.breakdown.counts, a.discovered]))
          problems.push('applicability: the WPT manifest counts differ from the record.');
      }
    }
  }
  return { status: a.status, discovered: a.discovered, unclassified: a.unclassified };
}

/** Write `specs/applicability/<id>.json` from the local snapshot. Only the WPT manifest tool runs here, without network access. */
export async function classifyCorpus(root, id, { corporaDir = corporaRoot(root) } = {}) {
  const { record, gitDir } = await loadSnapshot(root, id, corporaDir);
  await commitObject(gitDir, record.commit);
  const entries = await listTree(gitDir, record.commit);
  const a = id === 'test262' ? test262Applicability(record.commit, entries) : await wptApplicability(root, record, gitDir, entries, corporaDir);
  validateApplicability(a);
  writeJson(applicabilityPath(root, id), a);
  return { result: a.status === 'counted' ? 'pass' : 'blocked', record: `specs/applicability/${id}.json`, ...a };
}

export async function corpusCommand(root, command, args) {
  invariant(args.length === 1, `Usage: ${command} <corpus-id>`);
  const run = { 'corpus-fetch': fetchCorpus, 'corpus-verify': verifyCorpus, 'corpus-applicability': classifyCorpus }[command];
  invariant(run, `Unknown corpus command: ${command}`);
  return run(root, args[0]);
}
