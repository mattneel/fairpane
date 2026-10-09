/** Fairpane local integrity tools. No package dependencies. */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';

export const STATES = new Set(['planned', 'active', 'blocked', 'implemented', 'accepted']);
export const REQUIRED_CAPABILITIES = Object.freeze([
  'html-dom', 'css-layout', 'text-fonts', 'javascript', 'web-idl', 'fetch-network',
  'storage-workers', 'svg-canvas-images', 'audio-video', 'guest-graphics', 'webassembly',
  'web-security', 'web-app-apis', 'input-accessibility', 'browser-product',
  'embedding-wrappers', 'extensions', 'webextensions-compat', 'cross-platform', 'performance', 'maintenance-adoption',
]);
const HASH = /^[a-f0-9]{64}$/;
const VERSION = /^\d+\.\d+\.\d+-dev\.\d+\+[a-f0-9]+$/;
export function invariant(condition, message) { if (!condition) throw new Error(message); }
export function readJson(file) { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
export function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
    fs.renameSync(tmp, file);
  } finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
}
export function sha256(data) { return crypto.createHash('sha256').update(data).digest('hex'); }
export function fileHash(file) {
  const hash = crypto.createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.alloc(128 * 1024);
  try {
    for (;;) {
      const count = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (!count) break;
      hash.update(buffer.subarray(0, count));
    }
  } finally { fs.closeSync(fd); }
  return hash.digest('hex');
}

/** Repository paths only. This check is not a hostile-filesystem sandbox. */
export function safePath(root, relative, { mustExist = true } = {}) {
  invariant(typeof relative === 'string' && relative.length > 0, 'A nonempty relative path is required.');
  invariant(!/[\x00-\x1f:]/.test(relative) && !relative.includes('\\'), 'Use a relative path with forward slashes.');
  invariant(!path.posix.isAbsolute(relative) && !/^[a-zA-Z]:/.test(relative), 'Absolute paths are not accepted.');
  const parts = relative.split('/');
  invariant(parts.every(p => p && p !== '.' && p !== '..'), 'Empty or traversal path components are not accepted.');
  const base = path.resolve(root);
  let cursor = base;
  for (const part of parts) {
    cursor = path.join(cursor, part);
    let stat;
    try { stat = fs.lstatSync(cursor); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    invariant(!stat?.isSymbolicLink(), `A symlink is not accepted: ${relative}`);
  }
  invariant(cursor.startsWith(`${base}${path.sep}`), 'The path escapes the repository.');
  if (mustExist) invariant(fs.existsSync(cursor), `Missing file or directory: ${relative}`);
  return cursor;
}
export function collectFiles(root, roots) {
  invariant(Array.isArray(roots) && roots.length > 0, 'A nonempty input list is required.');
  const files = new Set();
  function walk(relative) {
    const absolute = safePath(root, relative);
    const stat = fs.lstatSync(absolute);
    if (stat.isDirectory()) for (const name of fs.readdirSync(absolute).sort()) walk(`${relative}/${name}`);
    else {
      invariant(stat.isFile(), `Only regular files are accepted: ${relative}`);
      files.add(relative);
    }
  }
  roots.forEach(walk);
  const sorted = [...files].sort();
  invariant(sorted.length > 0, 'An empty file inventory cannot qualify.');
  invariant(new Set(sorted.map(s => s.toLowerCase())).size === sorted.length, 'A case-insensitive path collision exists.');
  return sorted;
}
export function hashInputs(root, roots) {
  const hash = crypto.createHash('sha256');
  const files = collectFiles(root, roots);
  for (const relative of files) {
    const file = safePath(root, relative);
    hash.update(`${relative}\0${fs.statSync(file).size}\0${fileHash(file)}\n`);
  }
  return { sha256: hash.digest('hex'), file_count: files.length };
}
export function fingerprints(root) {
  const policy = readJson(safePath(root, 'engineering/policy.json'));
  return { source: hashInputs(root, policy.source_roots), policy: hashInputs(root, policy.policy_roots) };
}
export function validateLock(lock) {
  invariant(lock?.schema_version === 1 && lock.channel === 'master', 'The compiler lock must select Zig master.');
  invariant(VERSION.test(lock.version), 'The lock needs an exact Zig development version.');
  invariant(lock.source === 'https://ziglang.org/download/index.json', 'The lock needs the official index source.');
  invariant(lock.platforms && Object.keys(lock.platforms).length > 0, 'The compiler lock has no platforms.');
  for (const [key, a] of Object.entries(lock.platforms)) {
    invariant(/^(x86_64|aarch64)-(windows|linux|macos)$/.test(key), `Unsupported lock platform: ${key}`);
    invariant(HASH.test(a.sha256), `Invalid archive SHA-256 for ${key}.`);
    invariant(Number.isSafeInteger(a.size) && a.size > 0, `Invalid archive size for ${key}.`);
    const suffix = key.endsWith('-windows') ? '.zip' : '.tar.xz';
    const archiveRoot = `zig-${key}-${lock.version}`;
    invariant(a.archive_root === archiveRoot, `Unexpected archive root for ${key}.`);
    invariant(a.url === `https://ziglang.org/builds/${archiveRoot}${suffix}`, `Unexpected artifact URL for ${key}.`);
  }
  return true;
}
export const RUST_SIGNING_KEY_FINGERPRINT = '108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE';
const RUST_HOSTS = Object.freeze({ 'x86_64-windows': 'x86_64-pc-windows-gnu', 'x86_64-linux': 'x86_64-unknown-linux-gnu' });
const RUST_KEYS = Object.freeze({
  lock: ['schema_version', 'channel', 'version', 'release_date', 'checked_date', 'rustc_commit_hash', 'manifest', 'platforms'],
  manifest: ['url', 'sha256', 'signature_url', 'signing_key_url', 'signing_key_fingerprint'],
  platform: ['host', 'components'],
  component: ['package', 'url', 'sha256', 'size', 'archive_root'],
});
const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const matches = (pattern, value) => typeof value === 'string' && pattern.test(value);
function isoDate(value) {
  return matches(/^\d{4}-\d{2}-\d{2}$/, value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`))
    && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
}
function rejectUnknownKeys(value, allowed) {
  if (isRecord(value)) for (const key of Object.keys(value)) invariant(allowed.includes(key), `Unexpected Rust lock key: ${key}`);
}
/** Check `toolchains/rust.lock.json`. Unknown keys at any level are reported first, then each field in a fixed order. */
export function validateRustLock(lock) {
  rejectUnknownKeys(lock, RUST_KEYS.lock);
  rejectUnknownKeys(lock?.manifest, RUST_KEYS.manifest);
  if (isRecord(lock?.platforms)) {
    for (const platform of Object.values(lock.platforms)) {
      rejectUnknownKeys(platform, RUST_KEYS.platform);
      if (Array.isArray(platform?.components)) for (const c of platform.components) rejectUnknownKeys(c, RUST_KEYS.component);
    }
  }
  invariant(lock?.schema_version === 1 && lock.channel === 'stable', 'The Rust lock must select a stable release.');
  invariant(matches(/^\d+\.\d+\.\d+$/, lock.version), 'The Rust lock needs an exact stable version.');
  invariant(isoDate(lock.release_date) && isoDate(lock.checked_date), 'The Rust lock needs ISO dates.');
  invariant(matches(/^[0-9a-f]{40}$/, lock.rustc_commit_hash), 'The Rust lock needs the 40-hex rustc commit.');
  const m = lock.manifest, manifestUrl = `https://static.rust-lang.org/dist/channel-rust-${lock.version}.toml`;
  invariant(isRecord(m) && m.url === manifestUrl && m.signature_url === `${manifestUrl}.asc`, 'The Rust lock needs the official channel manifest.');
  invariant(matches(HASH, m.sha256), 'The Rust lock needs a SHA-256 manifest digest.');
  invariant(m.signing_key_url === 'https://static.rust-lang.org/rust-key.gpg.ascii' && m.signing_key_fingerprint === RUST_SIGNING_KEY_FINGERPRINT,
    'The Rust lock must name the Rust signing key.');
  invariant(isRecord(lock.platforms) && Object.keys(lock.platforms).length > 0, 'The Rust lock has no platforms.');
  for (const [key, p] of Object.entries(lock.platforms)) {
    invariant(Object.hasOwn(RUST_HOSTS, key), `Unsupported Rust lock platform: ${key}`);
    invariant(isRecord(p) && p.host === RUST_HOSTS[key], `Unexpected Rust host for ${key}.`);
    // The Windows GNU host adds the self-contained MinGW linker in the lock's frozen position, before rustfmt-preview.
    const expected = ['rustc', 'cargo', 'rust-std', ...(p.host.endsWith('-windows-gnu') ? ['rust-mingw'] : []), 'rustfmt-preview'];
    invariant(Array.isArray(p.components) && p.components.length === expected.length
      && p.components.every((c, i) => isRecord(c) && c.package === expected[i]),
      `The Rust components for ${key} must be exactly ${expected.join(', ')}.`);
    for (const c of p.components) {
      const archiveRoot = `${c.package.replace(/-preview$/, '')}-${lock.version}-${p.host}`;
      invariant(c.url === `https://static.rust-lang.org/dist/${lock.release_date}/${archiveRoot}.tar.gz`, `Unexpected component URL for ${c.package} on ${key}.`);
      invariant(c.archive_root === archiveRoot, `Unexpected archive root for ${c.package} on ${key}.`);
      invariant(matches(HASH, c.sha256), `Invalid archive SHA-256 for ${c.package} on ${key}.`);
      invariant(Number.isSafeInteger(c.size) && c.size > 0, `Invalid archive size for ${c.package} on ${key}.`);
    }
  }
  return true;
}
/** The exact `rust-toolchain.toml` text that a lock implies. */
export function rustToolchainText(lock) {
  return [
    '# The repository\'s commands run the toolchain that node tools/fairpane.mjs install-rust installs, never one from PATH.',
    '# This file names the version in toolchains/rust.lock.json for a developer who uses rustup.',
    '[toolchain]', `channel = "${lock.version}"`, 'profile = "minimal"', 'components = ["rustfmt"]', '',
  ].join('\n');
}
export function rustToolchainProblems(lock, text) {
  if (text === rustToolchainText(lock)) return [];
  const channel = /^channel\s*=\s*"([^"\r\n]*)"\s*$/m.exec(text)?.[1];
  if (channel !== lock.version) return [`rust-toolchain.toml names ${channel ?? 'no channel'}, but the lock pins ${lock.version}.`];
  return ['rust-toolchain.toml differs from the text that the lock implies.'];
}
export function hostPlatform(platform = process.platform, arch = process.arch) {
  const a = { x64: 'x86_64', arm64: 'aarch64' }[arch];
  const o = { win32: 'windows', linux: 'linux', darwin: 'macos' }[platform];
  invariant(a && o, `No locked archive exists for ${platform}/${arch}.`);
  return `${a}-${o}`;
}
/** The locked compiler's path for this host. `lock` defaults to the working tree's lock, and a caller can pass a commit's lock. */
export function compilerPath(root, lock = readJson(safePath(root, 'toolchains/zig.lock.json'))) {
  validateLock(lock);
  const target = hostPlatform();
  invariant(lock.platforms[target], `No locked artifact exists for ${target}.`);
  return path.join(root, '.tools', 'zig', lock.version, target, process.platform === 'win32' ? 'zig.exe' : 'zig');
}
export function checkCompiler(root, lock = readJson(safePath(root, 'toolchains/zig.lock.json'))) {
  const compiler = compilerPath(root, lock);
  invariant(fs.existsSync(compiler), 'The locked compiler is absent. Run the local compiler installer.');
  const result = spawnSync(compiler, ['version'], { encoding: 'utf8', timeout: 30000, windowsHide: true });
  invariant(!result.error && result.status === 0, `Compiler version check failed: ${result.error?.message ?? result.stderr}`);
  invariant(result.stdout.trim() === lock.version, `Compiler mismatch: expected ${lock.version}, found ${result.stdout.trim()}.`);
  return compiler;
}
/** Check a downloaded archive against its locked size and SHA-256. `name` names the archive in the messages. */
export function verifyArchive(file, artifact, name = 'compiler') {
  invariant(fs.statSync(file).size === artifact.size, `The ${name} archive size does not match the lock.`);
  invariant(fileHash(file) === artifact.sha256, `The ${name} archive SHA-256 does not match the lock.`);
  return true;
}
/**
 * Reuse `archive` after a size and SHA-256 check, or download the locked URL into a `.partial` file beside it.
 * The download refuses redirects, stops when it exceeds the locked size, and is verified before the rename.
 * `name` names the archive in the check messages, and `title` starts the HTTP failure message.
 * Both `install-zig` and `install-rust` use it.
 */
export async function fetchLockedArchive(archive, artifact, { name, title = name, fetch = globalThis.fetch }) {
  if (fs.existsSync(archive)) return verifyArchive(archive, artifact, name);
  const tmp = `${archive}.${crypto.randomUUID()}.partial`; let fd;
  try {
    const response = await fetch(artifact.url, { redirect: 'error', signal: AbortSignal.timeout(600000) });
    invariant(response.ok && response.body, `${title} download failed with HTTP ${response.status}.`);
    fd = fs.openSync(tmp, 'wx'); let bytes = 0;
    for await (const chunk of response.body) {
      bytes += chunk.length; invariant(bytes <= artifact.size, 'The download exceeded the locked archive size.');
      let offset = 0;
      while (offset < chunk.length) offset += fs.writeSync(fd, chunk, offset, chunk.length - offset);
    }
    fs.closeSync(fd); fd = undefined; verifyArchive(tmp, artifact, name); fs.renameSync(tmp, archive);
  } finally { if (fd !== undefined) fs.closeSync(fd); if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
  return true;
}
export function validatePlan(plan, state, gateIds, workstreamIds) {
  invariant(plan?.schema_version === 1 && Array.isArray(plan.tasks) && plan.tasks.length > 0, 'A nonempty task plan is required.');
  invariant(state?.schema_version === 1 && state.tasks, 'A valid task state is required.');
  const ids = new Set();
  for (const t of plan.tasks) {
    invariant(/^FP-\d{4}$/.test(t.id) && !ids.has(t.id), `Invalid or duplicate task ID: ${t.id}`);
    ids.add(t.id);
    invariant(typeof t.title === 'string' && t.title.trim(), `${t.id} needs a title.`);
    invariant(Array.isArray(t.depends_on), `${t.id} needs explicit prerequisites.`);
    invariant(Array.isArray(t.acceptance) && t.acceptance.length > 0 && t.acceptance.every(c => typeof c === 'string' && c.trim()), `${t.id} needs nonempty acceptance criteria.`);
    invariant(Array.isArray(t.allowed_paths) && t.allowed_paths.length > 0, `${t.id} needs writable paths.`);
    invariant(Array.isArray(t.required_gates) && t.required_gates.length > 0 && t.required_gates.every(g => gateIds.has(g)), `${t.id} needs known gates.`);
    invariant(workstreamIds.has(t.workstream), `${t.id} names an unknown workstream.`);
    const s = state.tasks[t.id];
    invariant(s && STATES.has(s.status) && Array.isArray(s.evidence), `${t.id} has invalid or missing state.`);
    if (s.status === 'accepted') invariant(s.evidence.length > 0 && s.review, `${t.id} cannot be accepted without evidence and review.`);
  }
  for (const id of Object.keys(state.tasks)) invariant(ids.has(id), `State names an unknown task: ${id}`);
  const map = new Map(plan.tasks.map(t => [t.id, t]));
  const visiting = new Set(), visited = new Set();
  function visit(id) {
    invariant(!visiting.has(id), `The task graph contains a cycle at ${id}.`);
    if (visited.has(id)) return;
    visiting.add(id);
    const t = map.get(id);
    invariant(new Set(t.depends_on).size === t.depends_on.length, `${id} has duplicate prerequisites.`);
    for (const d of t.depends_on) {
      invariant(ids.has(d), `${id} names an unknown prerequisite: ${d}`);
      visit(d);
      if (state.tasks[id].status === 'accepted') invariant(state.tasks[d].status === 'accepted', `${id} has an unaccepted prerequisite.`);
    }
    visiting.delete(id); visited.add(id);
  }
  ids.forEach(visit);
  return true;
}
export function readyTasks(plan, state) {
  return plan.tasks.filter(t => state.tasks[t.id]?.status === 'planned' && t.depends_on.every(d => state.tasks[d]?.status === 'accepted'));
}
export function qualificationProblems(profile) {
  if (profile?.schema_version !== 1) return ['The qualification profile schema is invalid.'];
  const problems = [];
  if (profile.profile_state !== 'frozen') problems.push('The full-browser qualification profile is not frozen.');
  if (!Number.isInteger(profile.profile_revision) || profile.profile_revision < 1) problems.push('No release-profile revision is ratified.');
  const caps = Array.isArray(profile.capabilities) ? profile.capabilities : [];
  const ids = new Set();
  for (const c of caps) {
    if (ids.has(c.id)) problems.push(`Duplicate capability: ${c.id}.`);
    ids.add(c.id);
    if (!c.required) problems.push(`Capability ${c.id} is not marked required.`);
    if (c.status !== 'qualified') problems.push(`Capability ${c.id} is not qualified.`);
    if (!c.manifest) problems.push(`Capability ${c.id} has no exact applicability manifest.`);
    if (!Array.isArray(c.evidence) || !c.evidence.length) problems.push(`Capability ${c.id} has no evidence.`);
  }
  for (const id of REQUIRED_CAPABILITIES) if (!ids.has(id)) problems.push(`Required capability family is missing: ${id}.`);
  for (const field of ['standards_baseline', 'target_matrix', 'performance_budgets', 'applicability_review', 'release_authority']) {
    if (!profile[field]) problems.push(`Release field ${field} is unset.`);
  }
  if (!profile.license_decision || profile.license_decision === 'pending-owner') problems.push('The owner did not ratify an outbound license.');
  // No metadata edit can satisfy this: release evidence needs signed results from a protected runner that tools/attest.mjs verifies.
  problems.push('No protected runner, trust policy, or signed result set exists. Release qualification needs signed results that tools/attest.mjs verifies against protected trust input.');
  return problems;
}
export function checkRepository(root) {
  const load = relative => readJson(safePath(root, relative));
  const policy = load('engineering/policy.json');
  invariant(policy.schema_version === 1, 'Unsupported repository policy.');
  policy.required_files.forEach(file => safePath(root, file));
  const gates = load('engineering/gates.json');
  invariant(gates.schema_version === 1 && gates.gates.length > 0, 'A nonempty gate registry is required.');
  const ids = new Set(), kinds = new Set(['controller-check', 'controller-test', 'zig', 'c-abi']);
  for (const g of gates.gates) {
    invariant(/^[a-z][a-z0-9_-]+$/.test(g.id) && !ids.has(g.id), `Invalid or duplicate gate: ${g.id}`);
    ids.add(g.id);
    invariant(kinds.has(g.kind), `Unknown gate implementation: ${g.kind}`);
    invariant(Number.isSafeInteger(g.timeout_ms) && g.timeout_ms > 0, `Invalid gate watchdog: ${g.id}`);
    if (g.kind === 'zig') invariant(Array.isArray(g.args) && g.args.length > 0 && g.args.every(a => typeof a === 'string'), 'Zig gate arguments are invalid.');
  }
  const plan = load('engineering/plan.json'), state = load('engineering/state.json');
  const workstreams = load('engineering/workstreams.json');
  validatePlan(plan, state, ids, new Set(workstreams.workstreams.map(w => w.id)));
  const lock = load('toolchains/zig.lock.json'); validateLock(lock);
  invariant(fs.readFileSync(safePath(root, 'toolchains/zig-version.txt'), 'utf8').trim() === lock.version, 'The compiler version files disagree.');
  // Read the Rust pin without running any Rust executable.
  const rustLock = load('toolchains/rust.lock.json'); validateRustLock(rustLock);
  const [toolchainProblem] = rustToolchainProblems(rustLock, fs.readFileSync(safePath(root, 'rust-toolchain.toml'), 'utf8'));
  invariant(!toolchainProblem, toolchainProblem);
  const profile = load('engineering/qualification.json');
  invariant(profile.schema_version === 1 && Array.isArray(profile.capabilities), 'The qualification capability schema is invalid.');
  for (const id of REQUIRED_CAPABILITIES) {
    const matching = profile.capabilities.filter(c => c.id === id);
    invariant(matching.length === 1 && matching[0].required === true, `Required capability is missing, duplicated, or weakened: ${id}`);
  }
  const sources = load('specs/sources.json'), sourceIds = new Set(sources.sources.map(s => s.id));
  invariant(sourceIds.size === sources.sources.length, 'Source identifiers must be unique.');
  for (const file of collectFiles(root, ['docs', 'README.md', 'START_HERE.md', 'LICENSE-DECISION.md'])) {
    const text = fs.readFileSync(safePath(root, file), 'utf8');
    for (const match of text.matchAll(/\[S\d{2}(?:,\s*S\d{2})*\]/g)) {
      for (const id of match[0].match(/S\d{2}/g)) invariant(sourceIds.has(id), `${file} names an unknown source ${id}.`);
    }
  }
  const deps = load('engineering/dependencies.json');
  invariant(deps.portable_core.external_runtime_dependencies.length === 0, 'The core has an external runtime dependency.');
  const allowed = new Set(deps.portable_core.allowed_builtin_modules);
  for (const file of collectFiles(root, deps.portable_core.source_roots).filter(p => p.endsWith('.zig'))) {
    const text = fs.readFileSync(safePath(root, file), 'utf8');
    for (const m of text.matchAll(/@import\("([^"\n]+)"\)/g)) {
      if (allowed.has(m[1])) continue;
      invariant(m[1].endsWith('.zig'), `Unapproved module import in ${file}: ${m[1]}`);
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(file), m[1]));
      invariant(deps.portable_core.source_roots.some(p => target.startsWith(`${p}/`)), `The import escapes the portable core: ${file}`);
      safePath(root, target);
    }
    invariant(!/@cImport\s*\(/.test(text), `A C import needs a reviewed platform boundary: ${file}`);
  }
  return { result: 'pass', level: 'bootstrap-integrity-only', tasks: plan.tasks.length,
    gates: ids.size, capability_families: profile.capabilities.length, fingerprints: fingerprints(root),
    note: 'This check is not browser conformance or an independent security attestation.' };
}
export function evidencePath(root, relative, options = {}) {
  invariant(typeof relative === 'string', 'An evidence path is required.');
  const p = readJson(safePath(root, 'engineering/policy.json'));
  invariant(p.allowed_evidence_roots.some(prefix => relative.startsWith(`${prefix}/`)), 'The evidence path is outside an allowed directory.');
  return safePath(root, relative, options);
}
export function validateReceipt(root, relative, { current = true } = {}) {
  const r = readJson(evidencePath(root, relative));
  invariant(r.schema_version === 1 && r.kind === 'fairpane-local-gate', 'The evidence receipt schema is invalid.');
  invariant(r.trust === 'unsigned-local-integrity-only', 'A local receipt cannot claim independent trust.');
  invariant(r.status === 'pass', 'The receipt does not report a passed gate.');
  invariant(HASH.test(r.source_before?.sha256) && HASH.test(r.policy_before?.sha256), 'The receipt has invalid input hashes.');
  invariant(r.source_before.sha256 === r.source_after?.sha256, 'Source changed during the gate.');
  invariant(r.policy_before.sha256 === r.policy_after?.sha256, 'Policy changed during the gate.');
  const gate = readJson(safePath(root, 'engineering/gates.json')).gates.find(g => g.id === r.gate_id);
  invariant(gate, 'The receipt names an unknown gate.');
  invariant(r.gate_sha256 === sha256(JSON.stringify(gate)), 'The gate definition changed.');
  invariant(Array.isArray(r.commands) && r.commands.length > 0, 'A passed receipt needs actual command records.');
  for (const c of r.commands) {
    invariant(c.exit_code === 0 && !c.signal && !c.timed_out && !c.error, 'A command did not complete successfully.');
    invariant(typeof c.executable === 'string' && Array.isArray(c.arguments), 'A command record is incomplete.');
  }
  invariant(Array.isArray(r.outputs) && r.outputs.length > 0, 'A passed receipt needs output artifacts.');
  for (const o of r.outputs) {
    invariant(HASH.test(o.sha256) && Number.isSafeInteger(o.size) && o.size >= 0, 'An output record is invalid.');
    const file = evidencePath(root, o.path);
    invariant(fs.statSync(file).size === o.size && fileHash(file) === o.sha256, `Evidence output changed: ${o.path}`);
  }
  if (current) {
    const now = fingerprints(root);
    invariant(now.source.sha256 === r.source_before.sha256, 'The receipt refers to stale source.');
    invariant(now.policy.sha256 === r.policy_before.sha256, 'The receipt refers to stale policy.');
  }
  return { result: 'pass', gate: r.gate_id, trust: r.trust, current_source: current };
}
/** The node:fs operations behind a command record. Tests replace single members through `fileSystem` to force failures. */
const RECORD_FS = Object.freeze({ mkdirSync: fs.mkdirSync, openSync: fs.openSync, writeSync: fs.writeSync, readSync: fs.readSync,
  closeSync: fs.closeSync, mkdtempSync: fs.mkdtempSync, rmSync: fs.rmSync });
const recordFs = overrides => overrides ? { ...RECORD_FS, ...overrides } : RECORD_FS;
/** Write a byte range to a log in one call. A short count is an error, never a silent truncation. */
function writeLog(io, fd, data, length = data.length) {
  const written = io.writeSync(fd, data, 0, length);
  if (written !== length) throw new Error(`Short write: ${written} of ${length} bytes.`);
}
function copyFileToDescriptor(io, file, fd) {
  const source = io.openSync(file, 'r'), buffer = Buffer.alloc(128 * 1024);
  try {
    for (;;) {
      const count = io.readSync(source, buffer, 0, buffer.length, null);
      if (!count) break;
      writeLog(io, fd, buffer, count);
    }
  } finally { io.closeSync(source); }
}
function closeQuietly(io, fd) { try { io.closeSync(fd); } catch { /* The descriptor is already unusable. */ } }
/** Error codes after which a removal can succeed later, such as a file that a scanner or indexer holds open briefly. */
const TRANSIENT_REMOVAL = new Set(['EBUSY', 'EPERM', 'ENOTEMPTY', 'EMFILE', 'ENFILE']);
/** Wait synchronously, because a command record finishes in one synchronous step. */
function pause(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
/**
 * Remove a private capture directory in up to three attempts, waiting 50 and then 100 milliseconds after a transient error.
 * A surviving directory still holds child output, so the record names the last failure.
 */
function removeCapture(io, dir, errors) {
  for (let attempt = 1; ; attempt++) {
    try { io.rmSync(dir, { recursive: true, force: true }); return; }
    catch (e) {
      if (attempt === 3 || !TRANSIENT_REMOVAL.has(e.code)) { errors.push(`Capture directory removal failed: ${e.message}`); return; }
      pause(50 * attempt);
    }
  }
}
function commandRecord(executable, args, cwd, started) {
  return { executable, arguments: args, cwd: path.resolve(cwd ?? process.cwd()), started_at: new Date(started).toISOString() };
}
/** Open a log for appending and write its COMMAND line. On failure, close the log and rethrow. */
function openLog(io, logPath, executable, args) {
  let fd;
  try {
    io.mkdirSync(path.dirname(logPath), { recursive: true });
    fd = io.openSync(logPath, 'a');
    writeLog(io, fd, Buffer.from(`\nCOMMAND ${JSON.stringify([executable, ...args])}\n`));
    return fd;
  } catch (e) {
    if (fd !== undefined) closeQuietly(io, fd);
    throw e;
  }
}
/** Append the RESULT line and close the log. A failed write becomes part of the result instead of an exception. */
function finishRecord(io, fd, result) {
  try { writeLog(io, fd, Buffer.from(`RESULT ${JSON.stringify(result)}\n`)); }
  catch (e) { result.error = [result.error, `Log write failed: ${e.message}`].filter(Boolean).join(' '); }
  finally { closeQuietly(io, fd); }
  return result;
}
/** Execute without a shell. OS sandboxing and disk quotas remain separate. Never rejects after argument validation. */
export function runProcess(executable, args, { cwd, logPath, timeoutMs = 60000, env, copyOutput, fileSystem } = {}) {
  invariant(typeof executable === 'string' && Array.isArray(args), 'An executable and argument array are required.');
  invariant(typeof logPath === 'string' && logPath.length > 0, 'A log path is required.');
  const io = recordFs(fileSystem), copy = copyOutput ?? ((file, out) => copyFileToDescriptor(io, file, out));
  const started = Date.now(), base = commandRecord(executable, args, cwd, started), errors = [];
  const result = (code, signal, timedOut) => {
    const r = { ...base, exit_code: code, signal, timed_out: timedOut, error: errors.length ? errors.join(' ') : null,
      duration_ms: Date.now() - started };
    if (env) r.environment_overrides = env;
    return r;
  };
  let fd;
  try { fd = openLog(io, logPath, executable, args); }
  catch (e) {
    errors.push(`Log write failed: ${e.message}`);
    return Promise.resolve(result(null, null, false));
  }
  // The child writes to a fresh file in a private directory, not to the append-only log handle.
  // MSYS2 programs on Windows exit with status 1 and no output when given an append-only handle.
  let captureDir, capture, outFd;
  try {
    captureDir = io.mkdtempSync(path.join(os.tmpdir(), 'fairpane-capture-'));
    capture = path.join(captureDir, 'output.log');
    outFd = io.openSync(capture, 'wx', 0o600);
  } catch (e) {
    errors.push(`Output capture failed: ${e.message}`);
    if (captureDir) removeCapture(io, captureDir, errors);
    return Promise.resolve(finishRecord(io, fd, result(null, null, false)));
  }
  return new Promise(resolve => {
    let child, timer, timedOut = false, settled = false;
    const finish = (code, signal) => {
      if (settled) return;
      settled = true; clearTimeout(timer);
      closeQuietly(io, outFd);
      try { copy(capture, fd); }
      catch (e) { errors.push(`Output capture failed: ${e.message}`); }
      removeCapture(io, captureDir, errors);
      resolve(finishRecord(io, fd, result(code, signal, timedOut)));
    };
    try {
      child = spawn(executable, args, { cwd, stdio: ['ignore', outFd, outFd], shell: false,
        env: env ? { ...process.env, ...env } : process.env, windowsHide: true, detached: process.platform !== 'win32' });
      child.on('error', error => { errors.push(error.message); finish(null, null); });
      child.on('close', (code, signal) => finish(code, signal));
      timer = setTimeout(() => {
        timedOut = true;
        if (process.platform === 'win32' && child.pid) {
          const k = spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, timeout: 10000 });
          if (k.error || k.status !== 0) child.kill('SIGKILL');
        } else if (child.pid) {
          try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
        }
      }, timeoutMs);
    } catch (e) { errors.push(e.message); finish(null, null); }
  });
}
/** Resolve a command name through PATH only, so a record names the executable that actually ran. */
export function resolveExecutable(root, name, { pathEnv = process.env.PATH ?? '', platform = process.platform } = {}) {
  invariant(typeof name === 'string' && name.length > 0, 'An executable name is required.');
  if (name.includes('/') || name.includes('\\')) {
    const file = path.resolve(root, name);
    invariant(fs.existsSync(file) && fs.statSync(file).isFile(), `The executable is absent: ${name}`);
    return file;
  }
  const suffixes = platform === 'win32' ? (path.extname(name) ? [''] : ['.com', '.exe']) : [''];
  for (const dir of pathEnv.split(platform === 'win32' ? ';' : ':').filter(Boolean)) {
    for (const suffix of suffixes) {
      const file = path.resolve(dir, name + suffix);
      try {
        if (!fs.statSync(file).isFile()) continue;
        if (platform !== 'win32') fs.accessSync(file, fs.constants.X_OK);
        return file;
      } catch { /* Try the next PATH entry. */ }
    }
  }
  throw new Error(`The executable is not on PATH: ${name}`);
}
/** Run one command without a shell and append its actual output and result to an evidence log. */
export async function recordCommand(root, logRelative, executable, args, { cwd = root, env, timeoutMs = 600000, pathEnv, fileSystem } = {}) {
  const logPath = evidencePath(root, logRelative, { mustExist: false });
  let resolved;
  try { resolved = resolveExecutable(root, executable, pathEnv === undefined ? {} : { pathEnv }); }
  catch (e) {
    const io = recordFs(fileSystem), started = Date.now();
    const result = { ...commandRecord(executable, args, cwd, started), exit_code: null, signal: null, timed_out: false,
      error: e.message, duration_ms: 0 };
    if (env) result.environment_overrides = env;
    let fd;
    try { fd = openLog(io, logPath, executable, args); }
    catch (w) { result.error = `${result.error} Log write failed: ${w.message}`; return result; }
    return finishRecord(io, fd, result);
  }
  return runProcess(resolved, args, { cwd, logPath, timeoutMs, env, fileSystem });
}
/** Environment overrides for a gate's child commands. */
export function gateEnvironment(root, gate) {
  // Keep compiler caches inside the repository's ignored build directory, not the user's global cache.
  return gate.kind === 'zig' || gate.kind === 'c-abi' ? { ZIG_GLOBAL_CACHE_DIR: path.join(root, '.zig-cache', 'global') } : undefined;
}
export async function runGate(root, id, { evidenceDir = 'out/evidence' } = {}) {
  const gate = readJson(safePath(root, 'engineering/gates.json')).gates.find(g => g.id === id);
  invariant(gate, `Unknown gate: ${id}`);
  const before = fingerprints(root);
  const prefix = `${evidenceDir}/${new Date().toISOString().replace(/[:.]/g, '-')}-${id}-${crypto.randomUUID().slice(0, 8)}`;
  // Validate both evidence paths before the first write, so a rejected directory receives no file.
  // The receipt path is checked again when it is written, after the gate's commands have run.
  const logRelative = `${prefix}.log`, logPath = evidencePath(root, logRelative, { mustExist: false });
  const receiptRelative = `${prefix}.json`;
  evidencePath(root, receiptRelative, { mustExist: false });
  fs.mkdirSync(path.dirname(logPath), { recursive: true });
  fs.writeFileSync(logPath, `Fairpane local gate: ${id}\nTrust: unsigned-local-integrity-only\n`);
  const commands = [], started = new Date().toISOString();
  let error = null, zigVersion = null;
  const env = gateEnvironment(root, gate);
  async function run(exe, argv) {
    const r = await runProcess(exe, argv, { cwd: root, logPath, timeoutMs: gate.timeout_ms, env });
    commands.push(r);
    invariant(r.exit_code === 0 && !r.signal && !r.timed_out && !r.error, `Gate command failed: ${JSON.stringify([exe, ...argv])}`);
  }
  try {
    if (gate.kind === 'controller-check') await run(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'check']);
    else if (gate.kind === 'controller-test') await run(process.execPath, [path.join(root, 'tools/selftest.mjs')]);
    else if (gate.kind === 'zig' || gate.kind === 'c-abi') {
      const zig = checkCompiler(root);
      zigVersion = readJson(safePath(root, 'toolchains/zig.lock.json')).version;
      if (gate.kind === 'zig') await run(zig, gate.args);
      else {
        const buildDir = path.join(root, 'out', 'c-abi-build');
        await run(zig, ['build', '--prefix', buildDir]);
        const libs = ['fairpane.lib', 'libfairpane.a', 'fairpane.a'].map(f => path.join(buildDir, 'lib', f)).filter(f => fs.existsSync(f));
        invariant(libs.length === 1, 'The C smoke test needs exactly one candidate static library.');
        // The library must export exactly the functions that the ABI schema declares.
        await run(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'abi-exports', path.relative(root, libs[0]).split(path.sep).join('/')]);
        const exe = path.join(root, 'out', process.platform === 'win32' ? 'c-abi-smoke.exe' : 'c-abi-smoke');
        await run(zig, ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', 'tests/c/abi_smoke.c', '-Iinclude', libs[0], '-o', exe]);
        await run(exe, []);
      }
    } else throw new Error(`No implementation exists for gate kind ${gate.kind}.`);
  } catch (e) { error = e.message; fs.appendFileSync(logPath, `GATE ERROR ${error}\n`); }
  let after = { source: null, policy: null };
  try { after = fingerprints(root); } catch (e) {
    error = `${error ?? ''} Input inventory failed after execution: ${e.message}`.trim();
    fs.appendFileSync(logPath, `GATE ERROR ${error}\n`);
  }
  if (before.source.sha256 !== after.source?.sha256 || before.policy.sha256 !== after.policy?.sha256) {
    error = `${error ?? ''} Source or policy changed during execution.`.trim();
    fs.appendFileSync(logPath, `GATE ERROR ${error}\n`);
  }
  const receipt = { schema_version: 1, kind: 'fairpane-local-gate', trust: 'unsigned-local-integrity-only',
    gate_id: id, gate_sha256: sha256(JSON.stringify(gate)), status: error ? 'fail' : 'pass',
    started_at: started, finished_at: new Date().toISOString(),
    host: { platform: process.platform, architecture: process.arch, os_release: os.release(),
      runtime: process.version, bun_version: process.versions.bun ?? null, zig_version: zigVersion },
    source_before: before.source, source_after: after.source, policy_before: before.policy, policy_after: after.policy,
    commands, error, outputs: [{ path: logRelative, size: fs.statSync(logPath).size, sha256: fileHash(logPath) }] };
  writeJson(evidencePath(root, receiptRelative, { mustExist: false }), receipt);
  return { ...receipt, receipt_path: receiptRelative };
}
export async function installZig(root) {
  const lock = readJson(safePath(root, 'toolchains/zig.lock.json')); validateLock(lock);
  const key = hostPlatform(), a = lock.platforms[key];
  invariant(a, `No locked archive exists for ${key}.`);
  const dest = safePath(root, `.tools/zig/${lock.version}/${key}`, { mustExist: false });
  if (fs.existsSync(dest)) return { compiler: checkCompiler(root), downloaded: false };
  if (process.platform === 'win32') {
    const r = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-File', path.join(root, 'scripts/Get-Zig.ps1')],
      { cwd: root, stdio: 'inherit', timeout: 900000 });
    invariant(!r.error && r.status === 0, 'The Windows compiler installer failed.');
    return { compiler: checkCompiler(root), downloaded: true };
  }
  const downloads = safePath(root, '.tools/downloads', { mustExist: false }); fs.mkdirSync(downloads, { recursive: true });
  const archive = path.join(downloads, path.basename(new URL(a.url).pathname));
  await fetchLockedArchive(archive, a, { name: 'compiler', title: 'Compiler' });
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const stage = fs.mkdtempSync(path.join(path.dirname(dest), '.extract-'));
  try {
    const list = spawnSync('tar', ['-tf', archive], { encoding: 'utf8', timeout: 60000, maxBuffer: 32 * 1024 * 1024 });
    invariant(!list.error && list.status === 0, 'The compiler archive inventory failed.');
    const members = list.stdout.split(/\r?\n/).filter(Boolean);
    invariant(members.length > 0 && members.every(name => {
      const n = name.replace(/\/$/, '');
      return (n === a.archive_root || n.startsWith(`${a.archive_root}/`)) && !n.startsWith('/') && !n.split('/').includes('..');
    }), 'The compiler archive contains an unexpected path.');
    const r = spawnSync('tar', ['-xf', archive, '-C', stage], { timeout: 600000, stdio: 'inherit' });
    invariant(!r.error && r.status === 0, 'Compiler extraction failed.');
    const extracted = path.join(stage, a.archive_root);
    invariant(fs.existsSync(path.join(extracted, 'zig')), 'The extracted compiler is absent.');
    fs.renameSync(extracted, dest);
  } finally { fs.rmSync(stage, { recursive: true, force: true }); }
  writeJson(path.join(dest, 'fairpane-install.json'), { version: lock.version, platform: key, archive_sha256: a.sha256, source: a.url });
  return { compiler: checkCompiler(root), downloaded: true };
}
