/**
 * The locked Rust toolchain: channel-manifest checks, a first-party gzip and tar reader, the component installer,
 * and the version checks. No package dependencies. Nothing here runs rustup or a Rust executable from PATH.
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
import { isDeepStrictEqual } from 'node:util';
import { fetchLockedArchive, hostPlatform, invariant, readJson, relativePathProblem, safePath, sha256, validateRustLock, writeJson } from './lib.mjs';

const LOCK_PATH = 'toolchains/rust.lock.json';
const UTF8 = new TextDecoder('utf-8', { fatal: true });

// Channel manifest -------------------------------------------------------------------------------------------------

const KEY_PART = String.raw`(?:[A-Za-z0-9_-]+|"[^"\\\r\n]*")`;
const KEY_PATH = String.raw`${KEY_PART}(?:\s*\.\s*${KEY_PART})*`;
const TABLE = new RegExp(String.raw`^\[\s*(${KEY_PATH})\s*\]\s*(?:#.*)?$`);
const ARRAY_TABLE = new RegExp(String.raw`^\[\[\s*(${KEY_PATH})\s*\]\]\s*(?:#.*)?$`);
const STRING_PAIR = new RegExp(String.raw`^(${KEY_PART})\s*=\s*"([^"\\\r\n]*)"\s*(?:#.*)?$`);
const BOOLEAN_PAIR = new RegExp(String.raw`^(${KEY_PART})\s*=\s*(true|false)\s*(?:#.*)?$`);
/** The key that one `KEY_PART` names: a bare key as written, or a quoted key without its quotes. */
const keyName = part => (part.startsWith('"') ? part.slice(1, -1) : part);
const KEY_PARTS = new RegExp(KEY_PART, 'g');
const keyParts = text => [...text.matchAll(KEY_PARTS)].map(m => keyName(m[0]));
const isTable = value => value !== null && typeof value === 'object' && !Array.isArray(value);

/** Walk to a table, creating missing tables. A path through an array of tables enters its last table, as in TOML. */
function descend(node, parts, lineNumber) {
  for (const part of parts) {
    if (!Object.hasOwn(node, part)) node[part] = Object.create(null);
    const next = Array.isArray(node[part]) ? node[part].at(-1) : node[part];
    invariant(isTable(next), `The manifest line ${lineNumber} uses a value as a table.`);
    node = next;
  }
  return node;
}

/**
 * Read the subset of TOML that a Rust channel manifest uses for its signed entries:
 * `[table]` and `[[array-of-table]]` headers, and `key = "string"` and `key = true|false` lines.
 * Every other line, such as an array value or a string with an escape, is ignored.
 * Tables have no prototype, so a key such as `__proto__` stays an ordinary key.
 */
export function parseChannelManifest(text) {
  const root = Object.create(null);
  let table = root;
  const set = (key, value, lineNumber) => {
    invariant(!Object.hasOwn(table, key), `The manifest line ${lineNumber} repeats the key ${key}.`);
    table[key] = value;
  };
  for (const [index, raw] of text.split('\n').entries()) {
    const line = raw.trim(), lineNumber = index + 1;
    let m;
    // Only a table header starts with `[`, and no key does, so a line can match only the patterns of its own kind.
    if (line.startsWith('[')) {
      if ((m = ARRAY_TABLE.exec(line))) {
        const parts = keyParts(m[1]), parent = descend(root, parts.slice(0, -1), lineNumber), last = parts.at(-1);
        if (!Object.hasOwn(parent, last)) parent[last] = [];
        invariant(Array.isArray(parent[last]), `The manifest line ${lineNumber} reuses a table as an array.`);
        table = Object.create(null);
        parent[last].push(table);
      } else if ((m = TABLE.exec(line))) table = descend(root, keyParts(m[1]), lineNumber);
    } else if ((m = STRING_PAIR.exec(line))) set(keyName(m[1]), m[2], lineNumber);
    else if ((m = BOOLEAN_PAIR.exec(line))) set(keyName(m[1]), m[2] === 'true', lineNumber);
  }
  return root;
}

/** Compare a channel manifest's bytes with the lock. Packages and targets that the lock does not name are ignored. */
export function rustLockProblems(lock, manifestBytes) {
  validateRustLock(lock);
  const problems = [], actual = sha256(manifestBytes);
  if (actual !== lock.manifest.sha256) problems.push(`The manifest SHA-256 ${actual} differs from the lock.`);
  const manifest = parseChannelManifest(UTF8.decode(manifestBytes));
  if (manifest.date !== lock.release_date) problems.push(`The manifest date ${manifest.date ?? 'none'} differs from the release date.`);
  const rustc = isTable(manifest.pkg) && isTable(manifest.pkg.rustc) ? manifest.pkg.rustc : Object.create(null);
  if (typeof rustc.version !== 'string' || !rustc.version.startsWith(`${lock.version} (`)) {
    problems.push(`The manifest rustc version ${rustc.version ?? 'none'} is not ${lock.version}.`);
  }
  if (rustc.git_commit_hash !== lock.rustc_commit_hash) problems.push(`The manifest rustc commit ${rustc.git_commit_hash ?? 'none'} differs from the lock.`);
  // Each platform component, and then each target's standard library, is looked up under its own triple.
  const entries = [...Object.values(lock.platforms).flatMap(({ host, components }) => components.map(c => [host, c])), ...Object.entries(lock.targets ?? {})];
  for (const [host, c] of entries) {
    const pkg = isTable(manifest.pkg) ? manifest.pkg[c.package] : undefined;
    const target = isTable(pkg) && isTable(pkg.target) ? pkg.target[host] : undefined;
    if (!isTable(target) || target.available !== true) { problems.push(`The manifest has no available ${c.package} for ${host}.`); continue; }
    if (target.url !== c.url) problems.push(`The manifest URL of ${c.package} for ${host} differs from the lock.`);
    if (target.hash !== c.sha256) problems.push(`The manifest hash of ${c.package} for ${host} differs from the lock.`);
  }
  return problems;
}

// Archive reader ---------------------------------------------------------------------------------------------------

const BLOCK = 512;
const padding = size => (BLOCK - (size % BLOCK)) % BLOCK;
const pathRejected = name => new Error(`The archive path is not accepted: ${name}`);
const LONG_NAME_LIMIT = 4096;

/** An archive path passes the path rule that corpus extraction shares (`relativePathProblem`). */
export function acceptedArchivePath(name) {
  return relativePathProblem(name) === null;
}
function isZeroBlock(block) {
  for (let i = 0; i < block.length; i++) if (block[i] !== 0) return false;
  return true;
}
/** A NUL-terminated header field. */
function field(header, start, length) {
  const bytes = header.subarray(start, start + length), end = bytes.indexOf(0);
  return end === -1 ? bytes : bytes.subarray(0, end);
}
/** An octal header number, which may be padded with leading spaces and trailing NUL or space bytes. */
function octal(header, start, length) {
  const text = header.toString('latin1', start, start + length).replace(/[\0 ]+$/, '').replace(/^ +/, '');
  return /^[0-7]+$/.test(text) ? Number.parseInt(text, 8) : null;
}
function checksumValid(header) {
  let sum = 0;
  for (let i = 0; i < BLOCK; i++) sum += i >= 148 && i < 156 ? 0x20 : header[i];
  return octal(header, 148, 8) === sum;
}
function headerFormat(header) {
  const magic = header.toString('latin1', 257, 265);
  if (magic === 'ustar  \0') return 'gnu';
  if (magic === 'ustar\u000000') return 'posix';
  return null;
}
function decodePath(bytes) {
  try { return UTF8.decode(bytes); } catch { throw pathRejected(bytes.toString('latin1')); }
}
/** Read `file` in 64 KiB chunks on the calling thread. */
function* readChunks(file) {
  const fd = fs.openSync(file, 'r');
  try {
    for (;;) {
      const chunk = Buffer.allocUnsafe(65536), n = fs.readSync(fd, chunk, 0, chunk.length, null);
      if (n === 0) return;
      yield n === chunk.length ? chunk : chunk.subarray(0, n);
    }
  } finally { fs.closeSync(fd); }
}
function writeAll(fd, data) {
  let offset = 0;
  while (offset < data.length) offset += fs.writeSync(fd, data, offset, data.length - offset);
}

/**
 * Stream a `.tar.gz` archive through `zlib.createGunzip` into a new `destination` directory.
 * It accepts only regular files, directories, and GNU long names, all inside `archiveRoot`.
 * Outside Windows, a file gets mode 0o755 when its header sets any execute bit, and 0o644 otherwise.
 */
export async function extractTarGz(archive, archiveRoot, destination) {
  fs.mkdirSync(destination);
  // `made` holds each directory that this extraction created, so a file in a known directory needs no mkdir call.
  const seen = new Set(), made = new Set([destination]), counts = { files: 0, directories: 0 };
  let offset = 0, pending = Buffer.alloc(0), entry = null, longName = null, ended = false;

  function begin(header, at) {
    invariant(checksumValid(header), `The archive header checksum is invalid at offset ${at}.`);
    const format = headerFormat(header);
    invariant(format, 'The archive is not a ustar or GNU tar file.');
    const size = octal(header, 124, 12);
    invariant(size !== null, `The archive entry size is invalid at offset ${at}.`);
    const type = String.fromCharCode(header[156]);
    if (type === 'L') {
      invariant(size <= LONG_NAME_LIMIT, `The archive long name is longer than ${LONG_NAME_LIMIT} bytes.`);
      return { kind: 'long', remaining: size, padding: padding(size), chunks: [] };
    }
    let nameBytes = field(header, 0, 100);
    if (format === 'posix') {
      const prefix = field(header, 345, 155);
      if (prefix.length) nameBytes = Buffer.concat([prefix, Buffer.from('/'), nameBytes]);
    }
    const name = longName ?? decodePath(nameBytes);
    longName = null;
    if (type !== '0' && type !== '\0' && type !== '5') throw new Error(`Unsupported tar entry type "${type}" for ${name}.`);
    const directory = type === '5';
    const relative = directory && name.endsWith('/') ? name.slice(0, -1) : name;
    if (!acceptedArchivePath(relative)) throw pathRejected(name);
    invariant(relative === archiveRoot || relative.startsWith(`${archiveRoot}/`), `The archive path is outside ${archiveRoot}: ${name}`);
    const key = relative.toLowerCase();
    invariant(!seen.has(key), `The archive repeats a path: ${name}`);
    seen.add(key);
    const target = path.join(destination, ...relative.split('/'));
    if (directory) {
      fs.mkdirSync(target, { recursive: true });
      made.add(target);
      counts.directories++;
      return { kind: 'skip', remaining: size, padding: padding(size) };
    }
    const parent = path.dirname(target);
    if (!made.has(parent)) { fs.mkdirSync(parent, { recursive: true }); made.add(parent); }
    const mode = (octal(header, 100, 8) ?? 0) & 0o111 ? 0o755 : 0o644;
    const fd = fs.openSync(target, 'wx', mode);
    counts.files++;
    // The umask cannot narrow the mode, because fchmod sets it exactly.
    if (process.platform !== 'win32') {
      try { fs.fchmodSync(fd, mode); } catch (e) { fs.closeSync(fd); throw e; }
    }
    return { kind: 'file', fd, remaining: size, padding: padding(size) };
  }
  function finish(done) {
    if (done.kind === 'file') { const { fd } = done; done.fd = undefined; fs.closeSync(fd); }
    else if (done.kind === 'long') {
      const bytes = Buffer.concat(done.chunks);
      let end = bytes.length;
      while (end > 0 && bytes[end - 1] === 0) end--;
      longName = decodePath(bytes.subarray(0, end));
    }
  }
  function consume(chunk) {
    if (ended) return;
    const data = pending.length ? Buffer.concat([pending, chunk]) : chunk;
    let at = 0;
    while (!ended) {
      if (entry) {
        if (entry.remaining === 0 && entry.padding === 0) { finish(entry); entry = null; continue; }
        if (at === data.length) break;
        if (entry.remaining > 0) {
          const n = Math.min(entry.remaining, data.length - at), part = data.subarray(at, at + n);
          if (entry.kind === 'file') writeAll(entry.fd, part);
          else if (entry.kind === 'long') entry.chunks.push(Buffer.from(part));
          entry.remaining -= n; at += n; offset += n;
        } else {
          const n = Math.min(entry.padding, data.length - at);
          entry.padding -= n; at += n; offset += n;
        }
        continue;
      }
      if (data.length - at < BLOCK) break;
      const header = data.subarray(at, at + BLOCK);
      if (isZeroBlock(header)) {
        // The archive ends with two zero blocks. A lone zero block is not a valid header.
        if (data.length - at < 2 * BLOCK) break;
        invariant(isZeroBlock(data.subarray(at + BLOCK, at + 2 * BLOCK)), `The archive header checksum is invalid at offset ${offset}.`);
        ended = true; at += 2 * BLOCK; offset += 2 * BLOCK;
        break;
      }
      entry = begin(header, offset);
      at += BLOCK; offset += BLOCK;
    }
    pending = ended || at === data.length ? Buffer.alloc(0) : Buffer.from(data.subarray(at));
  }

  try {
    // Reading continues after the end blocks, so gunzip checks the whole stream's CRC and length.
    await pipeline(readChunks(archive), zlib.createGunzip(), async source => {
      for await (const chunk of source) consume(chunk);
    });
    invariant(ended && entry === null && longName === null, 'The archive ends early.');
  } finally {
    if (entry?.kind === 'file' && entry.fd !== undefined) fs.closeSync(entry.fd);
  }
  return counts;
}

// Component installation -------------------------------------------------------------------------------------------

/** Every regular file under `dir`, as sorted forward-slash paths relative to it. */
function filesBelow(dir, prefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) out.push(...filesBelow(path.join(dir, entry.name), `${relative}/`));
    else {
      invariant(entry.isFile(), `Only regular files are accepted: ${relative}`);
      out.push(relative);
    }
  }
  return out.sort();
}
function statOrNull(file) {
  try { return fs.lstatSync(file); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
}

/**
 * Install one extracted rust-installer archive into `toolchain` by moving each listed file out of `extracted`.
 * Each component installs exactly the files that its `manifest.in` lists, and no top-level archive file.
 * `installed` holds every path, in lower case, that an earlier component installed into the same toolchain.
 * `toolchain` holds no other file, so no move replaces a file.
 */
export function installComponents(extracted, archiveRoot, toolchain, installed) {
  const base = path.join(extracted, archiveRoot);
  const version = fs.readFileSync(path.join(base, 'rust-installer-version'), 'utf8').trim();
  invariant(version === '3', `Unexpected installer version ${version}.`);
  const names = fs.readFileSync(path.join(base, 'components'), 'utf8').split('\n').map(line => line.trim()).filter(Boolean);
  invariant(names.length > 0 && names.every(name => /^[a-z0-9][a-z0-9_.-]*$/.test(name)), 'The component list is invalid.');
  for (const component of names) {
    const dir = path.join(base, component), listed = [];
    for (const raw of fs.readFileSync(path.join(dir, 'manifest.in'), 'utf8').split('\n')) {
      const line = raw.replace(/\r$/, '');
      if (!line) continue;
      const m = /^(file|dir):(.*)$/.exec(line);
      invariant(m, `${component}/manifest.in has an unknown line: ${line}`);
      const [, kind, relative] = m;
      if (!acceptedArchivePath(relative)) throw pathRejected(relative);
      const stat = statOrNull(path.join(dir, ...relative.split('/')));
      if (kind === 'file') {
        invariant(stat?.isFile(), `${component}/manifest.in names an absent file: ${relative}`);
        listed.push(relative);
      } else {
        invariant(stat?.isDirectory(), `${component}/manifest.in names an absent file: ${relative}`);
        listed.push(...filesBelow(path.join(dir, ...relative.split('/')), `${relative}/`));
      }
    }
    const covered = new Set(listed);
    for (const file of filesBelow(dir)) {
      invariant(file === 'manifest.in' || covered.has(file), `${component} holds a file that manifest.in does not list: ${file}`);
    }
    const keys = new Set();
    for (const file of listed) {
      const key = file.toLowerCase();
      invariant(!installed.has(key) && !keys.has(key), `Two components install ${file}.`);
      keys.add(key);
    }
    const made = new Set();
    for (const file of listed) {
      const target = path.join(toolchain, ...file.split('/')), parent = path.dirname(target);
      if (!made.has(parent)) { fs.mkdirSync(parent, { recursive: true }); made.add(parent); }
      fs.renameSync(path.join(dir, ...file.split('/')), target);
    }
    for (const key of keys) installed.add(key);
  }
  return names;
}

// Version checks ---------------------------------------------------------------------------------------------------

const TOOLS = Object.freeze([['rustc', ['-vV']], ['cargo', ['-V']], ['rustdoc', ['-V']], ['rustfmt', ['-V']]]);
const firstLine = text => String(text ?? '').trim().split(/\r?\n/)[0];

/** Compare the outputs of `rustc -vV`, `cargo -V`, `rustdoc -V`, and `rustfmt -V` with the lock. */
export function toolchainVersionProblems(lock, platform, outputs) {
  const host = lock.platforms[platform]?.host, commit = lock.rustc_commit_hash, problems = [];
  const fields = new Map();
  for (const line of String(outputs.rustc ?? '').split(/\r?\n/)) {
    const m = /^([a-z-]+): (.*)$/.exec(line);
    if (m && !fields.has(m[1])) fields.set(m[1], m[2].trim());
  }
  const [release, hash, found] = ['release', 'commit-hash', 'host'].map(key => fields.get(key));
  if (release !== lock.version || hash !== commit || found !== host) {
    problems.push(`Rust toolchain mismatch: expected release ${lock.version}, commit ${commit}, and host ${host}; `
      + `found ${release ?? 'none'}, ${hash ?? 'none'}, and ${found ?? 'none'}.`);
  }
  const version = lock.version.replaceAll('.', '\\.');
  const cargo = firstLine(outputs.cargo);
  if (!new RegExp(String.raw`^cargo ${version} \([0-9a-f]{9,} \d{4}-\d{2}-\d{2}\)$`).test(cargo)) problems.push(`cargo version mismatch: ${cargo}`);
  const fromCommit = m => m !== null && commit.startsWith(m[1]);
  const rustdoc = firstLine(outputs.rustdoc);
  if (!fromCommit(new RegExp(String.raw`^rustdoc ${version} \(([0-9a-f]{9,}) `).exec(rustdoc))) problems.push(`rustdoc version mismatch: ${rustdoc}`);
  const rustfmt = firstLine(outputs.rustfmt);
  if (!fromCommit(/^rustfmt \d+\.\d+\.\d+-stable \(([0-9a-f]{9,}) /.exec(rustfmt))) problems.push(`rustfmt version mismatch: ${rustfmt}`);
  return problems;
}

function defaultRun(file, args, options) { return spawnSync(file, args, { ...options, encoding: 'utf8' }); }
function loadLock(root) {
  const lock = readJson(safePath(root, LOCK_PATH));
  validateRustLock(lock);
  return lock;
}
const toolPath = (dir, platform, name) => path.join(dir, 'bin', platform.endsWith('-windows') ? `${name}.exe` : name);
const toolchainDir = (root, lock, platform) => safePath(root, `.tools/rust/${lock.version}/${platform}`, { mustExist: false });
const RECEIPT = 'fairpane-install.json';

/**
 * The components of a toolchain for `platform`: the platform's components in lock order, and then each locked target's standard library.
 * `name` names the archive in messages, and `entry` is the component's receipt entry without its installer components.
 */
function lockedComponents(lock, platform) {
  return [
    ...lock.platforms[platform].components.map(c => ({ artifact: c, name: c.package, entry: { package: c.package, sha256: c.sha256 } })),
    ...Object.entries(lock.targets ?? {}).map(([target, c]) => ({ artifact: c, name: `${c.package} (${target})`,
      entry: { package: c.package, target, sha256: c.sha256 } })),
  ];
}
/**
 * Whether the receipt in `dir` records the lock's toolchain for `platform`: its identity fields, and its components reduced to
 * `package`, `target` when present, and `sha256`, in lock order. The receipt is a local integrity record, not a signature.
 */
function receiptMatches(lock, platform, dir) {
  let receipt;
  try { receipt = JSON.parse(fs.readFileSync(path.join(dir, RECEIPT), 'utf8')); }
  catch (e) { if (e.code === 'ENOENT' || e instanceof SyntaxError) return false; throw e; }
  if (!isTable(receipt) || !Array.isArray(receipt.components)) return false;
  const components = receipt.components.map(c => (isTable(c)
    ? { package: c.package, ...(Object.hasOwn(c, 'target') && { target: c.target }), sha256: c.sha256 } : c));
  return receipt.version === lock.version && receipt.platform === platform && receipt.host === lock.platforms[platform].host
    && receipt.rustc_commit_hash === lock.rustc_commit_hash && receipt.manifest_sha256 === lock.manifest.sha256
    && isDeepStrictEqual(components, lockedComponents(lock, platform).map(c => c.entry));
}

/** The path at which the locked toolchain's `rustc` belongs for `platform`. */
export function rustcPath(root, platform = hostPlatform()) {
  const lock = loadLock(root);
  return toolPath(toolchainDir(root, lock, platform), platform, 'rustc');
}
/** The four executables of the toolchain in `dir`, which must exist. */
function toolFiles(dir, platform) {
  const files = TOOLS.map(([name]) => toolPath(dir, platform, name));
  invariant(files.every(file => fs.existsSync(file)), 'The locked Rust toolchain is absent. Run node tools/fairpane.mjs install-rust.');
  return files;
}
/** Run the four version checks on the toolchain in `dir`, each in the toolchain's `bin` directory, and return its `rustc` path. */
function verifyToolchain(root, dir, lock, platform, run, files = toolFiles(dir, platform)) {
  const env = { ...process.env, CARGO_HOME: path.join(root, '.tools', 'cargo-home') }, cwd = path.join(dir, 'bin');
  const outputs = {};
  for (const [i, [name, args]] of TOOLS.entries()) {
    const r = run(files[i], args, { cwd, env, windowsHide: true, timeout: 30000 });
    invariant(!r.error && r.status === 0, `The ${name} version check failed: ${r.error?.message ?? (String(r.stderr ?? '').trim() || `exit ${r.status}`)}`);
    outputs[name] = r.stdout;
  }
  const problems = toolchainVersionProblems(lock, platform, outputs);
  invariant(problems.length === 0, problems.join(' '));
  return files[0];
}
/**
 * Check the installed toolchain for `platform` and return its `rustc` path.
 * A toolchain whose receipt differs from the lock is rejected before any version check runs.
 */
export function checkRust(root, { platform = hostPlatform(), run = defaultRun } = {}) {
  const lock = loadLock(root);
  invariant(lock.platforms[platform], `No locked Rust toolchain exists for ${platform}.`);
  const dir = toolchainDir(root, lock, platform), files = toolFiles(dir, platform);
  invariant(receiptMatches(lock, platform, dir), 'The installed Rust toolchain differs from the lock. Run node tools/fairpane.mjs install-rust.');
  return verifyToolchain(root, dir, lock, platform, run, files);
}

/**
 * Install the locked toolchain, with each locked target's standard library, under `.tools/rust/<version>/<platform>`.
 * It writes only to `.tools/downloads`, `.tools/rust/<version>`, and, through the version checks, `.tools/cargo-home`.
 * It accepts an existing toolchain directory whose receipt matches the lock after only a version check.
 * It replaces a toolchain whose receipt differs, and it keeps that toolchain in place until the new one passes its checks.
 */
export async function installRust(root, { platform = hostPlatform(), fetch = globalThis.fetch, run = defaultRun } = {}) {
  const lock = loadLock(root), entry = lock.platforms[platform];
  invariant(entry, `No locked Rust toolchain exists for ${platform}.`);
  const dest = toolchainDir(root, lock, platform);
  if (fs.existsSync(dest) && receiptMatches(lock, platform, dest)) return { toolchain: checkRust(root, { platform, run }), downloaded: false };
  const parts = lockedComponents(lock, platform);
  const downloads = safePath(root, '.tools/downloads', { mustExist: false });
  fs.mkdirSync(downloads, { recursive: true });
  const archives = [];
  for (const { artifact, name } of parts) {
    const archive = path.join(downloads, path.posix.basename(new URL(artifact.url).pathname));
    await fetchLockedArchive(archive, artifact, { name, fetch });
    archives.push(archive);
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const stage = fs.mkdtempSync(path.join(path.dirname(dest), '.extract-'));
  try {
    const toolchain = path.join(stage, 'toolchain'), installed = new Set();
    for (const [i, { artifact }] of parts.entries()) await extractTarGz(archives[i], artifact.archive_root, path.join(stage, String(i)));
    fs.mkdirSync(toolchain);
    const components = parts.map(({ artifact, entry: receiptEntry }, i) => ({ ...receiptEntry,
      installer_components: installComponents(path.join(stage, String(i)), artifact.archive_root, toolchain, installed) }));
    verifyToolchain(root, toolchain, lock, platform, run);
    writeJson(path.join(toolchain, RECEIPT), { version: lock.version, platform, host: entry.host,
      rustc_commit_hash: lock.rustc_commit_hash, manifest_sha256: lock.manifest.sha256, components, source: lock.manifest.url });
    const rustc = toolPath(dest, platform, 'rustc');
    if (!fs.existsSync(dest)) {
      fs.renameSync(toolchain, dest);
      return { toolchain: rustc, downloaded: true, components };
    }
    // The earlier toolchain moves aside, and it moves back if the new one cannot take its place.
    const replaced = path.join(path.dirname(dest), `.replaced-${crypto.randomUUID()}`);
    fs.renameSync(dest, replaced);
    try { fs.renameSync(toolchain, dest); } catch (e) { fs.renameSync(replaced, dest); throw e; }
    const result = { toolchain: rustc, downloaded: true, replaced: true, components };
    try { fs.rmSync(replaced, { recursive: true, force: true, maxRetries: 3 }); } catch (e) { result.replaced_cleanup_error = e.message; }
    return result;
  } finally {
    fs.rmSync(stage, { recursive: true, force: true, maxRetries: 3 });
  }
}
