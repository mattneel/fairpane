/**
 * Release records for FP-0027: source archives, unsigned build provenance, and reproducibility checks.
 * ADR 0009 records the design. Nothing here signs, publishes, or uploads an artifact.
 * Git runs through the verifier's hardened `readGit`: no replace objects, no inherited GIT_* variables, and no prompts.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { candidateIdentity, candidateRepository, passesInside, readGit } from './attest.mjs';
import { checkCompiler, fileHash, hostPlatform, invariant, sha256, validateLock } from './lib.mjs';

export const MANIFEST_FORMAT = 'fairpane-source-manifest';
export const MANIFEST_VERSION = 1;
const ADR_0009 = 'https://github.com/mattneel/fairpane/blob/master/engineering/decisions/0009-release-and-stewardship.md';
/**
 * The builder ID of a statement from an unprotected workspace, a URI as SLSA Provenance v1 requires.
 * No verifier treats it as a trusted builder, and ADR 0009 never changes the meaning of its anchor.
 */
export const BUILDER_ID = `${ADR_0009}#unsigned-local-builder-1`;
const BUILD_TYPE = `${ADR_0009}#build-type-1`;
const BUILD_ARGUMENTS = Object.freeze(['build', '-Doptimize=ReleaseSafe']);
/** The release build, run from the root of the extracted source archive with the locked compiler as `zig`. */
export const BUILD_COMMAND = Object.freeze(['zig', ...BUILD_ARGUMENTS, '--prefix', 'zig-out']);
/**
 * Configuration that `git archive` would otherwise take from the user or the repository.
 * Line-end conversion and the tar permission mask would change the bytes of the same commit on another machine.
 */
const ARCHIVE_CONFIG = Object.freeze(['-c', 'core.autocrlf=false', '-c', 'core.eol=lf', '-c', 'tar.umask=0002']);
const FILE_MODES = new Set(['100644', '100755', '120000']);
const OUTPUT_LIMIT = 1024 * 1024 * 1024;
const GIT_TIMEOUT_MS = 300000;
const strictUtf8 = new TextDecoder('utf-8', { fatal: true });

function decodePath(bytes) {
  try { return strictUtf8.decode(bytes); }
  catch { throw new Error(`A tree path is not valid UTF-8, so a manifest cannot name it: ${JSON.stringify(bytes.toString('latin1'))}`); }
}
function gitBytes(repository, args, input) {
  const r = readGit(repository, args, { raw: true, input, maxBuffer: OUTPUT_LIMIT, timeout: GIT_TIMEOUT_MS });
  invariant(r.status === 0, `git ${args.find(a => !a.startsWith('-') && !a.includes('='))} exited with status ${r.status}: ${r.stderr.toString('utf8').trim()}`);
  return r.stdout;
}
/** The first line of `git --version` from the Git that writes the tar, because the tar bytes can depend on that version. */
function gitVersion(repository) {
  const r = readGit(repository, ['--version']);
  invariant(r.status === 0, `git --version exited with status ${r.status}: ${r.stderr.trim()}`);
  return r.stdout.split(/\r?\n/)[0].trim();
}

/** The SHA-256 and size of each blob, read through one `git cat-file --batch` process. */
function blobDigests(repository, oids) {
  const digests = new Map();
  if (oids.length === 0) return digests;
  const out = gitBytes(repository, ['cat-file', '--batch'], `${oids.join('\n')}\n`);
  let offset = 0;
  for (const oid of oids) {
    const newline = out.indexOf(10, offset);
    invariant(newline !== -1, 'git cat-file output ended inside a header.');
    const header = out.toString('latin1', offset, newline), m = /^([0-9a-f]{40}) blob (\d+)$/.exec(header);
    invariant(m && m[1] === oid, `Unexpected git cat-file header for ${oid}: ${header}`);
    const size = Number(m[2]), start = newline + 1, end = start + size;
    invariant(end < out.length && out[end] === 10, 'git cat-file output lost its object framing.');
    digests.set(oid, { size, sha256: sha256(out.subarray(start, end)) });
    offset = end + 1;
  }
  invariant(offset === out.length, 'git cat-file returned more output than requested.');
  return digests;
}

/**
 * Every regular file and symbolic link of a commit's tree, sorted by path bytes.
 * A submodule entry has no content in the archive, so it has no manifest entry.
 */
function treeFiles(repository, commit) {
  const out = gitBytes(repository, ['ls-tree', '-r', '-z', '--full-tree', commit]);
  const entries = [];
  for (let start = 0; start < out.length;) {
    const end = out.indexOf(0, start), tab = out.indexOf(9, start);
    invariant(end !== -1 && tab !== -1 && tab < end, 'git ls-tree output has a malformed entry.');
    const m = /^(\d{6}) (blob|commit) ([0-9a-f]{40})$/.exec(out.toString('latin1', start, tab));
    invariant(m, `Unexpected git ls-tree entry: ${out.toString('latin1', start, tab)}`);
    const bytes = Buffer.from(out.subarray(tab + 1, end));
    start = end + 1;
    if (m[2] === 'commit') continue;
    invariant(FILE_MODES.has(m[1]), `Unsupported tree entry mode ${m[1]} at ${decodePath(bytes)}.`);
    entries.push({ bytes, path: decodePath(bytes), mode: m[1], oid: m[3] });
  }
  const digests = blobDigests(repository, [...new Set(entries.map(e => e.oid))]);
  entries.sort((a, b) => Buffer.compare(a.bytes, b.bytes));
  return entries.map(e => ({ ...e, ...digests.get(e.oid) }));
}

function octal(field, what) {
  const text = field.toString('latin1').replace(/\0[^]*$/, '').trim();
  invariant(/^[0-7]*$/.test(text), `A tar header has a malformed ${what} field.`);
  return text ? parseInt(text, 8) : 0;
}
function cString(field) { const nul = field.indexOf(0); return field.subarray(0, nul === -1 ? field.length : nul); }
/** Parse pax extended header records, `<length> <key>=<value>\n`, into raw value bytes. */
function paxFields(data) {
  const fields = {};
  for (let i = 0; i < data.length;) {
    const space = data.indexOf(0x20, i), digits = space === -1 ? '' : data.toString('latin1', i, space);
    invariant(/^[1-9]\d*$/.test(digits), 'A pax header record has no length.');
    const end = i + Number(digits);
    invariant(end <= data.length && data[end - 1] === 10, 'A pax header record has a wrong length.');
    const record = data.subarray(space + 1, end - 1), equals = record.indexOf(0x3d);
    invariant(equals > 0, 'A pax header record has no key.');
    fields[record.toString('utf8', 0, equals)] = record.subarray(equals + 1);
    i = end;
  }
  return fields;
}
/**
 * Read the POSIX ustar and pax archive that `git archive --format=tar` writes.
 * Each entry is `{ path, type, mode, data, linkname }` with raw path and link bytes. A global pax header is skipped.
 */
export function readTar(bytes) {
  const entries = [];
  let pax = {}, offset = 0;
  for (;;) {
    invariant(offset + 512 <= bytes.length, 'The tar ends before its end-of-archive blocks.');
    const header = bytes.subarray(offset, offset + 512);
    if (header.every(b => b === 0)) {
      invariant(bytes.subarray(offset).every(b => b === 0), 'The tar has data after its end-of-archive block.');
      return entries;
    }
    invariant(header.toString('latin1', 257, 262) === 'ustar', 'A tar header is not a ustar header.');
    let sum = 0;
    for (let i = 0; i < 512; i++) sum += i >= 148 && i < 156 ? 0x20 : header[i];
    invariant(sum === octal(header.subarray(148, 156), 'checksum'), 'A tar header has a wrong checksum.');
    const size = pax.size ? Number(pax.size.toString('latin1')) : octal(header.subarray(124, 136), 'size');
    invariant(Number.isSafeInteger(size) && size >= 0, 'A tar entry has an invalid size.');
    const type = header[156] === 0 ? '0' : String.fromCharCode(header[156]), start = offset + 512;
    invariant(start + size <= bytes.length, 'A tar entry extends past the end of the archive.');
    const data = bytes.subarray(start, start + size);
    offset = start + Math.ceil(size / 512) * 512;
    if (type === 'g') continue;
    if (type === 'x') { pax = paxFields(data); continue; }
    const name = cString(header.subarray(0, 100)), prefix = cString(header.subarray(345, 500));
    entries.push({ path: pax.path ?? (prefix.length ? Buffer.concat([prefix, Buffer.from('/'), name]) : Buffer.from(name)),
      type, mode: octal(header.subarray(100, 108), 'mode'), data,
      linkname: pax.linkpath ?? Buffer.from(cString(header.subarray(157, 257))) });
    pax = {};
  }
}

/**
 * Require the archive to hold exactly the tree's files under the prefix, with their content, size, and executable bit.
 * An attribute such as `export-ignore`, `export-subst`, or a line-end conversion would make the tar differ from the manifest.
 */
function checkArchive(entries, prefix, files) {
  const expected = new Map(files.map(f => [f.bytes.toString('latin1'), f])), seen = new Set();
  for (const e of entries) {
    invariant(e.path.subarray(0, prefix.length).equals(prefix), `The archive entry ${JSON.stringify(e.path.toString('utf8'))} lies outside ${prefix.toString('utf8')}.`);
    if (e.type === '5') continue;
    const key = e.path.subarray(prefix.length).toString('latin1'), f = expected.get(key), shown = JSON.stringify(e.path.toString('utf8'));
    invariant(f && !seen.has(key), `The archive entry ${shown} is not a file of the tree, or it repeats.`);
    seen.add(key);
    const same = f.mode === '120000' ?
      e.type === '2' && e.linkname.length === f.size && sha256(e.linkname) === f.sha256 :
      e.type === '0' && e.data.length === f.size && sha256(e.data) === f.sha256 && ((e.mode & 0o100) !== 0) === (f.mode === '100755');
    invariant(same, `The archive entry ${shown} differs from the tree's ${f.mode} blob.`);
  }
  invariant(seen.size === expected.size, `The archive lacks ${expected.size - seen.size} files of the tree.`);
}

/**
 * Build the source tar and manifest of one commit in memory.
 * The commit must be a full commit ID of an existing commit object, as `candidateIdentity` requires.
 */
export function buildSourceArchive(repository, commit) {
  const { tree } = candidateIdentity(repository, commit);
  const prefix = `fairpane-${commit}/`;
  const tar = gitBytes(repository, [...ARCHIVE_CONFIG, 'archive', '--format=tar', `--prefix=${prefix}`, commit]);
  const files = treeFiles(repository, commit), entries = readTar(tar);
  checkArchive(entries, Buffer.from(prefix), files);
  const manifest = { format: MANIFEST_FORMAT, version: MANIFEST_VERSION, commit, tree, git_version: gitVersion(repository),
    tar: { name: `fairpane-${commit}.tar`, size: tar.length, sha256: sha256(tar) },
    files: files.map(f => ({ path: f.path, mode: f.mode, size: f.size, sha256: f.sha256 })) };
  return { tar, entries, prefix, manifest };
}
function writeAtomic(file, data) {
  const tmp = `${file}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(tmp, data, { flag: 'wx' });
    fs.renameSync(tmp, file);
  } finally { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); }
}
/**
 * Write `fairpane-<commit>.tar` and `fairpane-<commit>.manifest.json` into an output directory outside the repository.
 * Every rejection happens before the first write.
 */
export function sourceArchive(repositoryPath, commit, outputDir) {
  const repository = candidateRepository(path.resolve(repositoryPath));
  const output = path.resolve(outputDir);
  for (const location of [repository.root, repository.gitDirectory]) {
    invariant(!passesInside(output, location), `The output directory ${output} lies inside the repository or its Git directory.`);
  }
  const { tar, manifest } = buildSourceArchive(repository.root, commit);
  const manifestText = `${JSON.stringify(manifest, null, 2)}\n`;
  const tarFile = path.join(output, manifest.tar.name), manifestFile = path.join(output, `fairpane-${commit}.manifest.json`);
  fs.mkdirSync(output, { recursive: true });
  writeAtomic(tarFile, tar);
  writeAtomic(manifestFile, manifestText);
  return { result: 'pass', commit, tree: manifest.tree, files: manifest.files.length,
    tar: { path: tarFile, size: manifest.tar.size, sha256: manifest.tar.sha256 },
    manifest: { path: manifestFile, sha256: sha256(manifestText) } };
}

/** The validated Zig lock that a commit carries, read from its tree rather than the working tree. */
export function commitLock(repository, commit) {
  const r = readGit(repository, ['cat-file', 'blob', `${commit}:toolchains/zig.lock.json`]);
  invariant(r.status === 0, `Commit ${commit} has no readable toolchains/zig.lock.json: ${r.stderr.trim()}`);
  const lock = JSON.parse(r.stdout.replace(/^\uFEFF/, ''));
  validateLock(lock);
  return lock;
}
/**
 * An unsigned in-toto Statement v1 with a SLSA Provenance v1 predicate for artifacts built from a commit.
 * It is a record format for a later protected runner, not an attestation, and its builder ID is untrusted by design.
 */
export function provenanceStatement(repositoryPath, commit, artifacts) {
  const repository = candidateRepository(path.resolve(repositoryPath));
  const { tree } = candidateIdentity(repository.root, commit);
  invariant(Array.isArray(artifacts) && artifacts.length > 0, 'provenance needs at least one artifact.');
  const subject = artifacts.map(file => {
    const resolved = path.resolve(file);
    let stat = null;
    try { stat = fs.statSync(resolved); } catch (e) { if (e.code !== 'ENOENT' && e.code !== 'ENOTDIR') throw e; }
    invariant(stat?.isFile(), `The artifact ${resolved} is not a regular file.`);
    return { name: path.basename(resolved), digest: { sha256: fileHash(resolved) } };
  });
  invariant(new Set(subject.map(s => s.name)).size === subject.length, 'Two artifacts share a file name, so their subjects would be ambiguous.');
  const lock = commitLock(repository.root, commit), platform = hostPlatform(), locked = lock.platforms[platform];
  invariant(locked, `The lock of commit ${commit} has no compiler artifact for ${platform}.`);
  return {
    _type: 'https://in-toto.io/Statement/v1',
    subject,
    predicateType: 'https://slsa.dev/provenance/v1',
    predicate: {
      buildDefinition: {
        buildType: BUILD_TYPE,
        externalParameters: {
          source: { commit, tree },
          command: [...BUILD_COMMAND],
          toolchain: { zig_version: lock.version, platform, archive_sha256: locked.sha256 },
        },
        internalParameters: {},
        resolvedDependencies: [
          { name: `fairpane-${commit}`, digest: { gitCommit: commit, gitTree: tree } },
          { name: `zig-${platform}-${lock.version}`, uri: locked.url, digest: { sha256: locked.sha256 } },
        ],
      },
      runDetails: { builder: { id: BUILDER_ID } },
    },
  };
}

/** The locked compiler of a commit's own Zig lock, after its version check. */
export function lockedCompiler(root, commit) {
  const repository = candidateRepository(path.resolve(root));
  candidateIdentity(repository.root, commit);
  return { executable: checkCompiler(root, commitLock(repository.root, commit)), args: [] };
}
/** Write the verified archive entries under `target`, refusing any path that a host could resolve outside it. */
function extractTree(entries, prefix, target) {
  fs.mkdirSync(target);
  for (const e of entries) {
    const relative = decodePath(e.path.subarray(Buffer.byteLength(prefix))).replace(/\/$/, '');
    if (!relative) continue;
    const parts = relative.split('/');
    for (const part of parts) {
      invariant(part && part !== '.' && part !== '..' && !part.includes('\\') &&
        !(process.platform === 'win32' && /[\x00-\x1f:<>"|?*]/.test(part)), `The archive path ${relative} cannot be extracted on this host.`);
    }
    let cursor = target;
    for (const part of parts.slice(0, -1)) {
      cursor = path.join(cursor, part);
      let stat = null;
      try { stat = fs.lstatSync(cursor); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      invariant(stat === null || stat.isDirectory(), `The archive path ${relative} passes through a non-directory.`);
    }
    const destination = path.join(target, ...parts);
    if (e.type === '5') { fs.mkdirSync(destination, { recursive: true }); continue; }
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    if (e.type === '2') fs.symlinkSync(e.linkname.toString('utf8'), destination);
    else fs.writeFileSync(destination, e.data, { flag: 'wx', mode: e.mode & 0o100 ? 0o755 : 0o644 });
  }
}
/**
 * Run the release build in one work tree with no inherited ZIG_* variable.
 * The fresh caches inside the tree reach Zig through ZIG_LOCAL_CACHE_DIR and ZIG_GLOBAL_CACHE_DIR, because the build
 * runner of the locked compiler rejects a `--global-cache-dir` argument.
 */
function runBuild(compiler, tree, timeout) {
  const args = [...compiler.args, ...BUILD_ARGUMENTS, '--prefix', path.join(tree, 'zig-out')];
  const caches = { ZIG_LOCAL_CACHE_DIR: path.join(tree, '.zig-cache'), ZIG_GLOBAL_CACHE_DIR: path.join(tree, '.zig-global-cache') };
  const env = { ...Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^ZIG_/i.test(name))), ...caches };
  const started = Date.now();
  const r = spawnSync(compiler.executable, args, { cwd: tree, env, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024, windowsHide: true });
  return { work_tree: tree, executable: compiler.executable, arguments: args, environment: caches, exit_code: r.status, signal: r.signal,
    timed_out: r.error?.code === 'ETIMEDOUT', error: r.error ? r.error.message : null, duration_ms: Date.now() - started,
    stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}
/** Map each installed path, relative and with forward slashes, to its SHA-256, or to its target for a symbolic link. */
function installedFiles(dir) {
  const files = new Map();
  const walk = (absolute, relative) => {
    for (const name of fs.readdirSync(absolute).sort()) {
      const full = path.join(absolute, name), rel = relative ? `${relative}/${name}` : name, stat = fs.lstatSync(full);
      if (stat.isDirectory()) walk(full, rel);
      else if (stat.isFile()) files.set(rel, fileHash(full));
      else if (stat.isSymbolicLink()) files.set(rel, `symlink:${fs.readlinkSync(full)}`);
      else throw new Error(`The installed entry ${rel} is not a file, a directory, or a symbolic link.`);
    }
  };
  if (fs.existsSync(dir)) walk(dir, '');
  return files;
}
/** Error codes after which a removal can succeed later, such as a file that a scanner holds open briefly. */
const TRANSIENT_REMOVAL = new Set(['EBUSY', 'EPERM', 'ENOTEMPTY', 'EMFILE', 'ENFILE']);
function pause(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
function attemptRemoval(remove) {
  let last = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt) pause(50 * attempt);
    try { remove(); return null; } catch (e) { last = e; if (!TRANSIENT_REMOVAL.has(e.code)) break; }
  }
  return last;
}
/** Remove both work trees, then their run directory. A failure stays in the report, and a surviving tree keeps the run directory. */
function removeTrees(io, runDir, trees) {
  const errors = [];
  const record = (target, e) => errors.push({ path: target, code: e.code ?? null, message: e.message });
  for (const tree of trees) {
    const e = attemptRemoval(() => io.rmSync(tree, { recursive: true, force: true }));
    if (e) record(tree, e);
  }
  if (!errors.length) {
    const e = attemptRemoval(() => io.rmdirSync(runDir));
    if (e) record(runDir, e);
  }
  return { removed: errors.length === 0, errors };
}
/**
 * Build a commit twice from its source archive, in two fresh work trees under `out/reproduce/`, and compare every installed file.
 * `compiler` is `{ executable, args }`; the controller passes the locked compiler, and tests pass a stand-in.
 * `fileSystem` replaces `rmSync` or `rmdirSync`, so a test can force a removal failure.
 */
export function reproduceCheck(repositoryPath, commit, { compiler, fileSystem, timeoutMs = 3600000 } = {}) {
  invariant(compiler && typeof compiler.executable === 'string' && Array.isArray(compiler.args), 'reproduce-check needs a compiler.');
  const repository = candidateRepository(path.resolve(repositoryPath));
  const source = buildSourceArchive(repository.root, commit);
  const io = { rmSync: fs.rmSync, rmdirSync: fs.rmdirSync, ...fileSystem };
  const parent = path.join(repository.root, 'out', 'reproduce');
  fs.mkdirSync(parent, { recursive: true });
  const runDir = fs.mkdtempSync(path.join(parent, `${commit.slice(0, 12)}-`));
  const trees = ['a', 'b'].map(name => path.join(runDir, name));
  const report = { result: 'error', commit, tree: source.manifest.tree, source_tar_sha256: source.manifest.tar.sha256,
    build_type_command: [...BUILD_COMMAND], work_trees: trees, builds: [], files: [], differing: [], error: null, removal: null };
  try {
    const installed = trees.map(tree => {
      extractTree(source.entries, source.prefix, tree);
      const build = runBuild(compiler, tree, timeoutMs);
      report.builds.push(build);
      invariant(build.exit_code === 0 && !build.signal && !build.error,
        `The build in ${tree} failed: ${build.error ?? (build.signal ? `signal ${build.signal}` : `exit status ${build.exit_code}`)}.`);
      return installedFiles(path.join(tree, 'zig-out'));
    });
    const paths = [...new Set([...installed[0].keys(), ...installed[1].keys()])].sort((x, y) => Buffer.compare(Buffer.from(x), Buffer.from(y)));
    report.files = paths.map(p => ({ path: p, a: installed[0].get(p) ?? null, b: installed[1].get(p) ?? null }));
    report.differing = report.files.filter(f => f.a !== f.b).map(f => f.path);
    invariant(paths.length > 0, 'The build installed no files, so the check has nothing to compare.');
    report.result = report.differing.length ? 'different' : 'reproducible';
  } catch (e) {
    report.result = 'error';
    report.error = e.message;
  }
  report.removal = removeTrees(io, runDir, trees);
  return report;
}
/** Exit status 0 only for a reproducible result whose work trees were removed. */
export function reproduceExitCode(report) { return report.result === 'reproducible' && report.removal?.removed === true ? 0 : 1; }
