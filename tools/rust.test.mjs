#!/usr/bin/env node
/**
 * Rust toolchain pin and installer tests for FP-0079 cases 1 through 10.
 * Run standalone with `node tools/rust.test.mjs`, or through `node tools/fairpane.mjs test`.
 * The cases need no network access and no installed Rust toolchain.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  RUST_SIGNING_KEY_FINGERPRINT, checkRepository, readJson, rustToolchainProblems, rustToolchainText, sha256, validateRustLock,
} from './lib.mjs';
import { extractTarGz, installComponents, installRust, rustLockProblems, toolchainVersionProblems } from './rust.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCK_PATH = 'toolchains/rust.lock.json';
const committedLock = () => readJson(path.join(root, LOCK_PATH));
const clone = value => JSON.parse(JSON.stringify(value));
const temporary = [];

function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-rust-'));
  temporary.push(dir); return dir;
}
function put(dir, relative, data) {
  const file = path.join(dir, ...relative.split('/'));
  fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, data);
  return file;
}
/** Every file and directory under `dir`, as sorted forward-slash paths; a directory ends with "/". */
function walk(dir, prefix = '') {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) out.push(`${relative}/`, ...walk(path.join(dir, entry.name), `${relative}/`));
    else out.push(relative);
  }
  return out.sort();
}
const filesUnder = dir => walk(dir).filter(p => !p.endsWith('/'));
function throwsExactly(fn, message) { assert.throws(fn, e => { assert.equal(e.message, message); return true; }); }

const COMMIT = 'b940084d7eb6a299eb4bfeb8e34901bc051e7ac4';
const FROZEN_LOCK = {
  schema_version: 1,
  channel: 'stable',
  version: '1.99.0',
  release_date: '2026-10-01',
  checked_date: '2026-10-09',
  rustc_commit_hash: COMMIT,
  manifest: {
    url: 'https://static.rust-lang.org/dist/channel-rust-1.99.0.toml',
    sha256: 'ce6dddc886364f8d786514771212cebe9b731ba82d6b859951c6b0ccc516b6a2',
    signature_url: 'https://static.rust-lang.org/dist/channel-rust-1.99.0.toml.asc',
    signing_key_url: 'https://static.rust-lang.org/rust-key.gpg.ascii',
    signing_key_fingerprint: '108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE',
  },
  platforms: {
    'x86_64-windows': {
      host: 'x86_64-pc-windows-gnu',
      components: [
        { package: 'rustc', url: 'https://static.rust-lang.org/dist/2026-10-01/rustc-1.99.0-x86_64-pc-windows-gnu.tar.gz', sha256: '3c7bad76bebfda385cc1061c1f0b625b02c212dcca5ea70b7bc6773153e6f15c', size: 161263734, archive_root: 'rustc-1.99.0-x86_64-pc-windows-gnu' },
        { package: 'cargo', url: 'https://static.rust-lang.org/dist/2026-10-01/cargo-1.99.0-x86_64-pc-windows-gnu.tar.gz', sha256: '125f4a389c765e59c94a12ec16cd668dfe7d6884b5e8edc8eaf2575f0162890d', size: 18667864, archive_root: 'cargo-1.99.0-x86_64-pc-windows-gnu' },
        { package: 'rust-std', url: 'https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-x86_64-pc-windows-gnu.tar.gz', sha256: '5d7f8eb792439b2e85afaf27497ff0f67e3ada0ef09adf81d564028e2aa1b90b', size: 44949786, archive_root: 'rust-std-1.99.0-x86_64-pc-windows-gnu' },
        { package: 'rust-mingw', url: 'https://static.rust-lang.org/dist/2026-10-01/rust-mingw-1.99.0-x86_64-pc-windows-gnu.tar.gz', sha256: '6ebe238508348b3faaabb8e259874415ce674dfcb0540392fe1a94f836e51b1b', size: 9594875, archive_root: 'rust-mingw-1.99.0-x86_64-pc-windows-gnu' },
        { package: 'rustfmt-preview', url: 'https://static.rust-lang.org/dist/2026-10-01/rustfmt-1.99.0-x86_64-pc-windows-gnu.tar.gz', sha256: 'a32c5025c2fa54f53fba92b0be6a949d3b041541917f9d33962187c06e45217a', size: 4938158, archive_root: 'rustfmt-1.99.0-x86_64-pc-windows-gnu' },
      ],
    },
    'x86_64-linux': {
      host: 'x86_64-unknown-linux-gnu',
      components: [
        { package: 'rustc', url: 'https://static.rust-lang.org/dist/2026-10-01/rustc-1.99.0-x86_64-unknown-linux-gnu.tar.gz', sha256: '238e72b8617f79bc96f27a5bfeb1a208b5755fe1a48f8bc190fe403ef6d54ab8', size: 141398713, archive_root: 'rustc-1.99.0-x86_64-unknown-linux-gnu' },
        { package: 'cargo', url: 'https://static.rust-lang.org/dist/2026-10-01/cargo-1.99.0-x86_64-unknown-linux-gnu.tar.gz', sha256: 'c2b8ba1f59e7a230aa5522684f3f7aa620b98e5ad37683a5e5cf9b41f534fa1e', size: 14521653, archive_root: 'cargo-1.99.0-x86_64-unknown-linux-gnu' },
        { package: 'rust-std', url: 'https://static.rust-lang.org/dist/2026-10-01/rust-std-1.99.0-x86_64-unknown-linux-gnu.tar.gz', sha256: '1dcaa01beb6bc78fdb13815b4f15214719167c58e3d79fbdf214591f8c195ee1', size: 50364291, archive_root: 'rust-std-1.99.0-x86_64-unknown-linux-gnu' },
        { package: 'rustfmt-preview', url: 'https://static.rust-lang.org/dist/2026-10-01/rustfmt-1.99.0-x86_64-unknown-linux-gnu.tar.gz', sha256: '9fc3a87d3d4f6e5e2bd87e6fb8779b7a95831f533cb8cc8ae1304a797c648733', size: 3133022, archive_root: 'rustfmt-1.99.0-x86_64-unknown-linux-gnu' },
      ],
    },
  },
};
const HOSTS = { 'x86_64-windows': 'x86_64-pc-windows-gnu', 'x86_64-linux': 'x86_64-unknown-linux-gnu' };

/** The frozen version outputs of the contract, with the platform's host on the `host:` line. */
function versionOutputs(host) {
  return {
    rustc: `rustc 1.99.0 (b940084d7 2026-09-28)\nbinary: rustc\ncommit-hash: ${COMMIT}\ncommit-date: 2026-09-28\nhost: ${host}\nrelease: 1.99.0\nLLVM version: 23.1.1\n`,
    cargo: 'cargo 1.99.0 (5f94df478 2026-08-27)\n',
    rustdoc: 'rustdoc 1.99.0 (b940084d7 2026-09-28)\n',
    rustfmt: 'rustfmt 1.10.0-stable (b940084d7e 2026-09-28)\n',
  };
}

// A GNU tar writer with valid header checksums. `magic` selects the GNU or the POSIX header form; `prefix` fills the POSIX prefix field.
const octal = (value, digits) => value.toString(8).padStart(digits, '0');
function tarHeader(name, { type = '0', size = 0, mode = 0o644, magic = 'gnu', version = '00', prefix = '' } = {}) {
  const h = Buffer.alloc(512);
  const nameBytes = Buffer.from(name, 'utf8'), prefixBytes = Buffer.from(prefix, 'utf8');
  assert.ok(nameBytes.length <= 100, `A header name needs a long-name entry: ${name}`);
  assert.ok(prefixBytes.length <= 155, `A prefix is longer than its field: ${prefix}`);
  nameBytes.copy(h, 0);
  prefixBytes.copy(h, 345);
  h.write(`${octal(mode, 7)}\0`, 100, 'latin1');
  h.write('0000000\0', 108, 'latin1');
  h.write('0000000\0', 116, 'latin1');
  h.write(`${octal(size, 11)}\0`, 124, 'latin1');
  h.write(`${octal(0, 11)}\0`, 136, 'latin1');
  h.write('        ', 148, 'latin1');
  h.write(type, 156, 'latin1');
  if (magic === 'gnu') h.write('ustar  \0', 257, 'latin1');
  else { h.write('ustar\0', 257, 'latin1'); h.write(version, 263, 'latin1'); }
  let sum = 0;
  for (const byte of h) sum += byte;
  h.write(`${octal(sum, 6)}\0 `, 148, 'latin1');
  return h;
}
const padded = data => Buffer.concat([data, Buffer.alloc((512 - (data.length % 512)) % 512)]);
/** Build an uncompressed tar from `{ name, type, data, mode, magic, version, prefix }` entries; a name over 100 bytes gets an `L` entry. */
function tar(entries) {
  const blocks = [];
  for (const { name, type = '0', data = Buffer.alloc(0), mode, magic, version, prefix } of entries) {
    const bytes = Buffer.from(data);
    let headerName = name;
    if (Buffer.byteLength(name) > 100) {
      const longName = Buffer.concat([Buffer.from(name, 'utf8'), Buffer.from([0])]);
      blocks.push(tarHeader('././@LongLink', { type: 'L', size: longName.length }), padded(longName));
      headerName = Buffer.from(name, 'utf8').subarray(0, 100).toString('utf8');
    }
    blocks.push(tarHeader(headerName, { type, size: bytes.length, mode, magic, version, prefix }), padded(bytes));
  }
  blocks.push(Buffer.alloc(1024));
  return Buffer.concat(blocks);
}
const tarGz = entries => zlib.gzipSync(tar(entries));

/** A component archive whose root and installer layout follow the real Rust archives. */
function componentArchive(pkg, host) {
  const stem = pkg.replace(/-preview$/, ''), archiveRoot = `${stem}-1.99.0-${host}`;
  const exe = host.includes('-windows-') ? '.exe' : '';
  const layouts = {
    rustc: ['rustc', [`bin/rustc${exe}`, `bin/rustdoc${exe}`, `lib/rustlib/${host}/codegen-backends/README.md`]],
    cargo: ['cargo', [`bin/cargo${exe}`, 'share/doc/cargo/README.md']],
    'rust-std': [`rust-std-${host}`, [`lib/rustlib/${host}/lib/libstd-fixture.rlib`]],
    'rust-mingw': [`rust-mingw-${host}`, [`lib/rustlib/${host}/bin/self-contained/ld.exe`, `lib/rustlib/${host}/lib/self-contained/crt2.o`]],
    'rustfmt-preview': ['rustfmt-preview', [`bin/rustfmt${exe}`, `bin/cargo-fmt${exe}`]],
  };
  const [component, files] = layouts[pkg];
  const entries = [
    { name: `${archiveRoot}/`, type: '5', mode: 0o755 },
    { name: `${archiveRoot}/rust-installer-version`, data: '3\n' },
    { name: `${archiveRoot}/components`, data: `${component}\n` },
    { name: `${archiveRoot}/install.sh`, data: '#!/bin/sh\nexit 1\n', mode: 0o755 },
    { name: `${archiveRoot}/version`, data: '1.99.0 (b940084d7 2026-09-28)\n' },
    { name: `${archiveRoot}/${component}/`, type: '5', mode: 0o755 },
    { name: `${archiveRoot}/${component}/manifest.in`, data: files.map(f => `file:${f}\n`).join('') },
    ...files.map(f => ({ name: `${archiveRoot}/${component}/${f}`, data: `${pkg} fixture ${f}\n`, mode: f.startsWith('bin/') ? 0o755 : 0o644 })),
  ];
  return { bytes: tarGz(entries), component, files };
}
/** A fixture root whose lock names fixture archives for `platform`, with a fetch that counts its calls. */
function installFixture(platform, { serve } = {}) {
  const dir = temp(), lock = committedLock(), host = HOSTS[platform], byUrl = new Map(), layouts = [];
  for (const c of lock.platforms[platform].components) {
    const archive = componentArchive(c.package, host);
    c.sha256 = sha256(archive.bytes); c.size = archive.bytes.length;
    byUrl.set(c.url, archive.bytes); layouts.push({ ...archive, package: c.package, sha256: c.sha256, url: c.url });
  }
  put(dir, LOCK_PATH, `${JSON.stringify(lock, null, 2)}\n`);
  const state = { fetches: 0, runs: [] };
  const fetch = async (url, options) => {
    state.fetches++;
    assert.equal(options.redirect, 'error');
    const bytes = (serve ?? (u => byUrl.get(u)))(url, byUrl.get(url));
    return typeof bytes === 'number' ? new Response('not found', { status: bytes }) : new Response(bytes);
  };
  const run = (outputsFor = versionOutputs(host)) => (file, args, options) => {
    const name = path.basename(file).replace(/\.exe$/, '');
    state.runs.push({ name, args, cargoHome: options.env.CARGO_HOME });
    assert.equal(options.cwd, path.dirname(file), `The ${name} version check must run in the toolchain's bin directory.`);
    const expectedArgs = { rustc: ['-vV'], cargo: ['-V'], rustdoc: ['-V'], rustfmt: ['-V'] }[name];
    assert.deepEqual(args, expectedArgs);
    return { status: 0, stdout: outputsFor[name], stderr: '' };
  };
  return { dir, lock, host, layouts, state, fetch, run };
}
function assertNoLeftovers(dir, platform) {
  assert.equal(fs.existsSync(path.join(dir, '.tools/rust/1.99.0', platform)), false);
  const everything = walk(dir);
  assert.deepEqual(everything.filter(p => p.endsWith('.partial')), []);
  assert.deepEqual(everything.filter(p => p.split('/').some(part => part.startsWith('.extract-'))), []);
}

function manifestText(lock, { date = lock.release_date, version = '1.99.0 (b940084d7 2026-09-28)', commit = lock.rustc_commit_hash, edit } = {}) {
  const lines = ['manifest-version = "2"', `date = "${date}"`, '', '[pkg.rustc]', `version = "${version}"`, `git_commit_hash = "${commit}"`, ''];
  for (const { host, components } of Object.values(lock.platforms)) {
    for (const c of components) {
      const table = { available: true, url: c.url, hash: c.sha256, xz_url: c.url.replace(/\.tar\.gz$/, '.tar.xz'), xz_hash: 'e'.repeat(64) };
      const changed = edit ? edit(c.package, host, table) : table;
      if (!changed) continue;
      lines.push(`[pkg.${c.package}.target.${host}]`, `available = ${changed.available}`, `url = "${changed.url}"`, `hash = "${changed.hash}"`,
        `xz_url = "${changed.xz_url}"`, `xz_hash = "${changed.xz_hash}"`, '');
    }
  }
  lines.push('[pkg.miri.target.x86_64-pc-windows-gnu]', 'available = false', '');
  return Buffer.from(lines.join('\n'));
}
function manifestProblems(options) {
  const lock = committedLock(), bytes = manifestText(lock, options);
  lock.manifest.sha256 = sha256(bytes);
  return rustLockProblems(lock, bytes);
}

/**
 * A minimal x64 PE image whose entry point ignores its arguments, calls
 * CreateFileW(marker, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL), and then calls ExitProcess(0).
 * Its one section starts at RVA 0x1000 and holds the code, the KERNEL32.dll import table, and the UTF-16 marker path.
 * The code addresses everything relative to RIP, so the image needs no relocations.
 */
function markerImage(marker) {
  const RVA = 0x1000, IMPORTS = 0x40, ILT = 0x68, IAT = 0x80, CREATE = 0x98, EXIT = 0xa6, DLL = 0xb4, PATH = 0xc2;
  const pathBytes = Buffer.from(`${marker}\0`, 'utf16le'), body = Buffer.alloc(PATH + pathBytes.length);
  Buffer.from([
    0x48, 0x83, 0xec, 0x48, // sub rsp, 0x48
    0x48, 0x8d, 0x0d, 0, 0, 0, 0, // lea rcx, [rip + marker]
    0xba, 0x00, 0x00, 0x00, 0x40, // mov edx, GENERIC_WRITE
    0x45, 0x33, 0xc0, // xor r8d, r8d
    0x45, 0x33, 0xc9, // xor r9d, r9d
    0xc7, 0x44, 0x24, 0x20, 0x02, 0x00, 0x00, 0x00, // mov dword [rsp + 0x20], CREATE_ALWAYS
    0xc7, 0x44, 0x24, 0x28, 0x80, 0x00, 0x00, 0x00, // mov dword [rsp + 0x28], FILE_ATTRIBUTE_NORMAL
    0x48, 0xc7, 0x44, 0x24, 0x30, 0x00, 0x00, 0x00, 0x00, // mov qword [rsp + 0x30], 0
    0xff, 0x15, 0, 0, 0, 0, // call [rip + CreateFileW]
    0x33, 0xc9, // xor ecx, ecx
    0xff, 0x15, 0, 0, 0, 0, // call [rip + ExitProcess]
  ]).copy(body, 0);
  // Each displacement counts from the end of its instruction.
  body.writeInt32LE(PATH - 11, 7);
  body.writeInt32LE(IAT - 53, 49);
  body.writeInt32LE(IAT + 8 - 61, 57);
  body.writeUInt32LE(RVA + ILT, IMPORTS);
  body.writeUInt32LE(RVA + DLL, IMPORTS + 12);
  body.writeUInt32LE(RVA + IAT, IMPORTS + 16);
  for (const table of [ILT, IAT]) {
    body.writeBigUInt64LE(BigInt(RVA + CREATE), table);
    body.writeBigUInt64LE(BigInt(RVA + EXIT), table + 8);
  }
  body.write('CreateFileW\0', CREATE + 2, 'latin1');
  body.write('ExitProcess\0', EXIT + 2, 'latin1');
  body.write('KERNEL32.dll\0', DLL, 'latin1');
  pathBytes.copy(body, PATH);

  const align = (n, to) => Math.ceil(n / to) * to, raw = align(body.length, 0x200);
  const h = Buffer.alloc(0x200);
  h.write('MZ', 0, 'latin1'); h.writeUInt32LE(0x40, 0x3c); h.write('PE\0\0', 0x40, 'latin1');
  // COFF header: x64, one section, an optional header of 0xf0 bytes, and an executable image without relocations.
  h.writeUInt16LE(0x8664, 0x44); h.writeUInt16LE(1, 0x46); h.writeUInt16LE(0xf0, 0x54); h.writeUInt16LE(0x0023, 0x56);
  // PE32+ optional header.
  h.writeUInt16LE(0x20b, 0x58); h.writeUInt32LE(raw, 0x5c); h.writeUInt32LE(RVA, 0x68); h.writeUInt32LE(RVA, 0x6c);
  h.writeBigUInt64LE(0x140000000n, 0x70); h.writeUInt32LE(0x1000, 0x78); h.writeUInt32LE(0x200, 0x7c);
  h.writeUInt16LE(6, 0x80); h.writeUInt16LE(6, 0x88);
  h.writeUInt32LE(RVA + align(body.length, 0x1000), 0x90); h.writeUInt32LE(0x200, 0x94);
  h.writeUInt16LE(3, 0x9c); h.writeUInt16LE(0x8100, 0x9e);
  h.writeBigUInt64LE(0x100000n, 0xa0); h.writeBigUInt64LE(0x1000n, 0xa8); h.writeBigUInt64LE(0x100000n, 0xb0); h.writeBigUInt64LE(0x1000n, 0xb8);
  h.writeUInt32LE(16, 0xc4);
  h.writeUInt32LE(RVA + IMPORTS, 0xd0); h.writeUInt32LE(40, 0xd4);
  h.writeUInt32LE(RVA + IAT, 0x128); h.writeUInt32LE(24, 0x12c);
  // The section header: readable, writable, and executable code.
  h.write('.text', 0x148, 'latin1'); h.writeUInt32LE(body.length, 0x150); h.writeUInt32LE(RVA, 0x154);
  h.writeUInt32LE(raw, 0x158); h.writeUInt32LE(0x200, 0x15c); h.writeUInt32LE(0xe0000060, 0x16c);
  return Buffer.concat([h, body, Buffer.alloc(raw - body.length)]);
}
/** Write a program at `file` that creates `marker` whenever it starts: a shell script, or on Windows the PE image above. */
function markerProgram(file, marker) {
  if (process.platform === 'win32') fs.writeFileSync(file, markerImage(marker));
  else { fs.writeFileSync(file, `#!/bin/sh\n: > '${marker.replaceAll('\'', '\'\\\'\'')}'\n`); fs.chmodSync(file, 0o755); }
  return file;
}

const DOC_LINES = [
  '`rust-toolchain.toml` names that exact version, so a rustup user\'s Cargo commands select it.',
  'The repository\'s commands run the locked toolchain by path, never a Rust toolchain from `PATH`.',
  '`node tools/fairpane.mjs install-rust` installs the locked toolchain under `.tools/rust/<version>/<platform>`.',
  'It downloads each locked component archive from `static.rust-lang.org` and checks its size and SHA-256 before extraction.',
  'It reads each archive with a first-party gzip and tar reader, which accepts only regular files, directories, and GNU long names inside the archive root.',
  'It installs exactly the files that each component\'s `manifest.in` lists.',
  'It checks the version, commit, and host of the staged `rustc` before it moves the toolchain into place.',
  'It never runs rustup, changes `PATH`, or writes outside `.tools`.',
  'On Windows, the locked host is `x86_64-pc-windows-gnu`, as ADR 0010 records.',
  'The lock records the SHA-256 of the official channel manifest, `https://static.rust-lang.org/dist/channel-rust-<version>.toml`.',
  'Each component digest in the lock equals that component\'s `hash` value in the manifest.',
  'The Rust build infrastructure signs the manifest with the Rust signing key, whose primary fingerprint is `108F 6620 5EAE B0AA A8DD 5E1C 85AB 96E6 FA1B E5FE`.',
  'A lock change records a GnuPG verification of that signature and a `rust-lock-verify` run in its evidence.',
  'The installer checks the locked digests, not the signature, so it trusts the reviewed lock as `install-zig` trusts the Zig lock.',
];

export const rustCases = [
  ['FP-0079 case 1: the committed Rust lock pins the frozen 1.99.0 artifacts', () => {
    const lock = committedLock();
    assert.equal(validateRustLock(lock), true);
    assert.match(lock.checked_date, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(lock.checked_date >= '2026-10-09', lock.checked_date);
    assert.deepEqual({ ...lock, checked_date: FROZEN_LOCK.checked_date }, FROZEN_LOCK);
    assert.equal(RUST_SIGNING_KEY_FINGERPRINT, '108F66205EAEB0AAA8DD5E1C85AB96E6FA1BE5FE');
  }],
  ['FP-0079 case 2: the Rust lock validator rejects every malformed field', () => {
    const mutations = [
      [l => { l.schema_version = 2; }, /stable release/],
      [l => { l.channel = 'beta'; }, /stable release/],
      [l => { l.version = '1.99'; }, /exact stable version/],
      [l => { l.release_date = '2026-10-1'; }, /ISO dates/],
      [l => { l.rustc_commit_hash = l.rustc_commit_hash.slice(1); }, /40-hex rustc commit/],
      [l => { l.manifest.url = 'https://static.rust-lang.org/dist/channel-rust-stable.toml'; }, /official channel manifest/],
      [l => { l.manifest.signature_url = l.manifest.url; }, /official channel manifest/],
      [l => { l.manifest.sha256 = l.manifest.sha256.toUpperCase(); }, /SHA-256 manifest digest/],
      [l => { l.manifest.signing_key_fingerprint = `${l.manifest.signing_key_fingerprint.slice(0, -1)}F`; }, /Rust signing key/],
      [l => { l.mirror = 'https://example.invalid/'; }, /Unexpected Rust lock key: mirror/],
      [l => { l.platforms['x86_64-freebsd'] = clone(l.platforms['x86_64-linux']); }, /Unsupported Rust lock platform: x86_64-freebsd/],
      [l => { l.platforms['x86_64-windows'].host = 'x86_64-pc-windows-msvc'; }, /Unexpected Rust host for x86_64-windows/],
      [l => { l.platforms['x86_64-windows'].components.splice(3, 1); }, /The Rust components for x86_64-(windows|linux) must be exactly/],
      [l => { const c = l.platforms['x86_64-linux'].components; c.splice(2, 0, clone(c[1])); }, /The Rust components for x86_64-(windows|linux) must be exactly/],
      [l => { l.platforms['x86_64-linux'].components.push(clone(l.platforms['x86_64-windows'].components[3])); }, /The Rust components for x86_64-(windows|linux) must be exactly/],
      [l => { const c = l.platforms['x86_64-windows'].components[0]; c.url = c.url.replace('https:', 'http:'); }, /Unexpected component URL for rustc on x86_64-windows/],
      [l => { const c = l.platforms['x86_64-windows'].components[0]; c.url = c.url.replace(/\.tar\.gz$/, '.tar.xz'); }, /Unexpected component URL for rustc on x86_64-windows/],
      [l => { l.platforms['x86_64-windows'].components[1].archive_root = 'cargo-1.99.0'; }, /Unexpected archive root for cargo/],
      [l => { const c = l.platforms['x86_64-windows'].components[2]; c.sha256 = c.sha256.slice(1); }, /Invalid archive SHA-256 for rust-std/],
      [l => { l.platforms['x86_64-linux'].components[3].size = 0; }, /Invalid archive size for rustfmt-preview/],
      [l => { l.platforms['x86_64-linux'].components[3].size = 1.5; }, /Invalid archive size for rustfmt-preview/],
    ];
    for (const [mutate, pattern] of mutations) {
      const lock = clone(committedLock());
      mutate(lock);
      assert.throws(() => validateRustLock(lock), pattern, String(mutate));
    }
  }],
  ['FP-0079 case 3: rust-toolchain.toml names the locked version', () => {
    const lock = committedLock(), text = fs.readFileSync(path.join(root, 'rust-toolchain.toml'), 'utf8');
    assert.equal(text, rustToolchainText(lock));
    assert.equal(text, '# The repository\'s commands run the toolchain that node tools/fairpane.mjs install-rust installs, never one from PATH.\n'
      + '# This file names the version in toolchains/rust.lock.json for a developer who uses rustup.\n'
      + '[toolchain]\nchannel = "1.99.0"\nprofile = "minimal"\ncomponents = ["rustfmt"]\n');
    assert.deepEqual(rustToolchainProblems(lock, text), []);
    assert.deepEqual(rustToolchainProblems(lock, text.replace('channel = "1.99.0"', 'channel = "1.98.1"')),
      ['rust-toolchain.toml names 1.98.1, but the lock pins 1.99.0.']);
    assert.deepEqual(rustToolchainProblems(lock, text.replace('profile = "minimal"\n', '')),
      ['rust-toolchain.toml differs from the text that the lock implies.']);
    assert.equal(checkRepository(root).result, 'pass');
  }],
  ['FP-0079 case 4: rust-lock-verify compares the lock with the manifest\'s signed entries', () => {
    assert.deepEqual(manifestProblems(), []);
    assert.deepEqual(manifestProblems({ date: '2026-09-30' }), ['The manifest date 2026-09-30 differs from the release date.']);
    assert.deepEqual(manifestProblems({ version: '1.98.1 (aaaaaaaaa 2026-08-01)' }),
      ['The manifest rustc version 1.98.1 (aaaaaaaaa 2026-08-01) is not 1.99.0.']);
    assert.deepEqual(manifestProblems({ commit: 'c'.repeat(40) }), [`The manifest rustc commit ${'c'.repeat(40)} differs from the lock.`]);
    assert.deepEqual(manifestProblems({ edit: (pkg, host, t) => pkg === 'rustc' && host === 'x86_64-pc-windows-gnu' ? { ...t, hash: 'd'.repeat(64) } : t }),
      ['The manifest hash of rustc for x86_64-pc-windows-gnu differs from the lock.']);
    assert.deepEqual(manifestProblems({ edit: (pkg, host, t) => pkg === 'cargo' && host === 'x86_64-unknown-linux-gnu' ? { ...t, url: t.url.replace('2026-10-01', '2026-10-02') } : t }),
      ['The manifest URL of cargo for x86_64-unknown-linux-gnu differs from the lock.']);
    assert.deepEqual(manifestProblems({ edit: (pkg, host, t) => pkg === 'rust-mingw' ? { ...t, available: false } : t }),
      ['The manifest has no available rust-mingw for x86_64-pc-windows-gnu.']);
    assert.deepEqual(manifestProblems({ edit: (pkg, host, t) => pkg === 'rustfmt-preview' && host === 'x86_64-unknown-linux-gnu' ? null : t }),
      ['The manifest has no available rustfmt-preview for x86_64-unknown-linux-gnu.']);
    const lock = committedLock(), bytes = manifestText(lock);
    assert.deepEqual(rustLockProblems(lock, bytes), [`The manifest SHA-256 ${sha256(bytes)} differs from the lock.`]);
    const r = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'rust-lock-verify'], { cwd: root, encoding: 'utf8', windowsHide: true });
    assert.equal(r.status, 1, r.stdout + r.stderr);
    assert.ok((r.stdout + r.stderr).includes('Usage: rust-lock-verify <repository-relative manifest path>'), r.stdout + r.stderr);
  }],
  ['FP-0079 case 5: the archive reader accepts only regular files, directories, and GNU long names inside the root', async () => {
    const R = 'fx-1.0.0-x86_64-pc-windows-gnu', dir = temp();
    const longPath = `${R}/dir/${'n'.repeat(140 - `${R}/dir/`.length)}`;
    assert.equal(Buffer.byteLength(longPath), 140);
    const contents = { [longPath]: 'long name\n', [`${R}/dir/run.sh`]: '#!/bin/sh\necho fixture\n', [`${R}/empty`]: '' };
    const accepted = put(dir, 'accepted.tar.gz', tarGz([
      { name: `${R}/`, type: '5', mode: 0o755 },
      { name: `${R}/dir/`, type: '5', mode: 0o755 },
      { name: longPath, data: contents[longPath] },
      { name: `${R}/dir/run.sh`, data: contents[`${R}/dir/run.sh`], mode: 0o755 },
      { name: `${R}/empty`, data: '' },
    ]));
    const out = path.join(dir, 'accepted');
    assert.deepEqual(await extractTarGz(accepted, R, out), { files: 3, directories: 2 });
    assert.deepEqual(filesUnder(out), Object.keys(contents).sort());
    for (const [name, text] of Object.entries(contents)) assert.equal(fs.readFileSync(path.join(out, ...name.split('/')), 'utf8'), text, name);
    if (process.platform !== 'win32') {
      assert.equal(fs.statSync(path.join(out, R, 'dir/run.sh')).mode & 0o777, 0o755);
      assert.equal(fs.statSync(path.join(out, longPath)).mode & 0o777, 0o644);
      assert.equal(fs.statSync(path.join(out, R, 'empty')).mode & 0o777, 0o644);
    }

    // Every fixture runs, and the case reports each one that is not rejected with its exact message.
    const ok = { name: `${R}/ok`, data: 'ok\n' }, longX = 'x'.repeat(120);
    const long = name => { assert.ok(Buffer.byteLength(name) > 100, `Not a long name: ${name}`); return { name, data: 'x' }; };
    const longLink = payload => [tarHeader('././@LongLink', { type: 'L', size: payload.length }), padded(payload)];
    const raw = tar([ok]), okBlocks = raw.subarray(0, raw.length - 1024), endBlocks = Buffer.alloc(1024);
    const badChecksum = Buffer.from(raw);
    badChecksum[148] = badChecksum[148] === 0x30 ? 0x31 : 0x30;
    const plain = tar([ok, { name: `${R}/more`, data: 'x'.repeat(700) }]);
    const oversized = Buffer.from(`${R}/${'n'.repeat(4097 - R.length - 2)}\0`);
    assert.equal(oversized.length, 4097);
    const notAccepted = (label, name, entry = { name, data: 'x' }) => [label, tarGz([ok, entry]), `The archive path is not accepted: ${name}`];
    const fixtures = [
      ...[['2', 'symlink'], ['1', 'hardlink'], ['x', 'pax'], ['3', 'device']].map(([type, name]) =>
        [`entry type ${type}`, tarGz([ok, { name: `${R}/${name}`, type }]), `Unsupported tar entry type "${type}" for ${R}/${name}.`]),
      ...['/etc/x', 'C:/x', `${R}\\x`, `${R}/../x`, `${R}/./x`].map(name => notAccepted(`the path ${JSON.stringify(name)}`, name)),
      ['a path under other/', tarGz([ok, { name: 'other/x', data: 'x' }]), `The archive path is outside ${R}: other/x`],
      ['the files A and a', tarGz([{ name: `${R}/A`, data: 'A' }, { name: `${R}/a`, data: 'a' }]), `The archive repeats a path: ${R}/a`],
      ['one changed checksum byte', zlib.gzipSync(badChecksum), 'The archive header checksum is invalid at offset 0.'],
      ['a tar cut by 600 bytes', zlib.gzipSync(plain.subarray(0, plain.length - 600)), 'The archive ends early.'],
      ['the POSIX magic with version 99', tarGz([{ ...ok, magic: 'posix', version: '99' }]), 'The archive is not a ustar or GNU tar file.'],
      ...[`${R}/${'d'.repeat(60)}/../${longX}`, `/${R}/${longX}`, `C:/${R}/${longX}`, `${R}/${'a'.repeat(60)}\0${'b'.repeat(60)}`]
        .map(name => notAccepted(`the long name ${JSON.stringify(name)}`, name, long(name))),
      ['a long name under other/', tarGz([ok, long(`other/${longX}`)]), `The archive path is outside ${R}: other/${longX}`],
      notAccepted('the POSIX prefix <root>/..', `${R}/../x`, { name: 'x', prefix: `${R}/..`, magic: 'posix', data: 'x' }),
      notAccepted('a POSIX prefix that makes an empty component', `${R}//x`, { name: 'x', prefix: `${R}/`, magic: 'posix', data: 'x' }),
      ['the directory D and the file d', tarGz([{ name: `${R}/D/`, type: '5', mode: 0o755 }, { name: `${R}/d`, data: 'd' }]), `The archive repeats a path: ${R}/d`],
      ['an L entry at the end of the archive', zlib.gzipSync(Buffer.concat([okBlocks, ...longLink(Buffer.from(`${R}/${longX}\0`)), endBlocks])),
        'The archive ends early.'],
      ['an L payload of 4097 bytes', zlib.gzipSync(Buffer.concat([...longLink(oversized), tarHeader(`${R}/long`, { size: 1 }), padded(Buffer.from('x')), endBlocks])),
        'The archive long name is longer than 4096 bytes.'],
      ...[`${R}/a:b`, `${R}/a\u0001b`, `${R}/CON`, `${R}/nul.txt`, `${R}/COM1`, `${R}/dot.`, `${R}/space `]
        .map(name => notAccepted(`the path ${JSON.stringify(name)}`, name)),
    ];
    const problems = [];
    for (const [i, [label, bytes, message]] of fixtures.entries()) {
      const file = put(dir, `rejected-${i + 1}.tar.gz`, bytes);
      try {
        await extractTarGz(file, R, path.join(dir, `rejected-${i + 1}`));
        problems.push(`${label}: Missing expected rejection.`);
      } catch (e) { if (e.message !== message) problems.push(`${label}: ${e.message}`); }
    }
    assert.deepEqual(problems, []);
  }],
  ['FP-0079 case 6: a component installs exactly what its manifest.in lists', () => {
    const R = 'fx-1.0.0-x86_64-pc-windows-gnu';
    const fixture = ({ version = '3', components = 'fx-tool', manifest = 'file:bin/fx-tool.exe\ndir:share/doc/fx\n', extra = {} } = {}) => {
      const dir = temp(), base = `extracted/${R}`;
      const files = {
        'rust-installer-version': `${version}\n`, components: `${components}\n`, 'install.sh': '#!/bin/sh\n', 'README.md': 'readme\n',
        version: '1.0.0\n', 'fx-tool/manifest.in': manifest, 'fx-tool/bin/fx-tool.exe': 'tool\n',
        'fx-tool/share/doc/fx/guide.txt': 'guide\n', 'fx-tool/share/doc/fx/more/notes.txt': 'notes\n', ...extra,
      };
      for (const [name, text] of Object.entries(files)) put(dir, `${base}/${name}`, text);
      return { extracted: path.join(dir, 'extracted'), toolchain: path.join(dir, 'toolchain') };
    };
    const good = fixture(), installed = new Set();
    assert.deepEqual(installComponents(good.extracted, R, good.toolchain, installed), ['fx-tool']);
    assert.deepEqual(filesUnder(good.toolchain), ['bin/fx-tool.exe', 'share/doc/fx/guide.txt', 'share/doc/fx/more/notes.txt']);
    assert.equal(fs.readFileSync(path.join(good.toolchain, 'bin/fx-tool.exe'), 'utf8'), 'tool\n');
    assert.equal(fs.readFileSync(path.join(good.toolchain, 'share/doc/fx/more/notes.txt'), 'utf8'), 'notes\n');

    const failing = (options, message) => {
      const f = fixture(options);
      throwsExactly(() => installComponents(f.extracted, R, f.toolchain, new Set()), message);
    };
    failing({ manifest: 'file:bin/fx-tool.exe\nfile:bin/absent.exe\ndir:share/doc/fx\n' }, 'fx-tool/manifest.in names an absent file: bin/absent.exe');
    failing({ extra: { 'fx-tool/bin/stray.exe': 'stray\n' } }, 'fx-tool holds a file that manifest.in does not list: bin/stray.exe');
    failing({ manifest: 'file:bin/fx-tool.exe\ndir:share/doc/fx\nfile:../x\n' }, 'The archive path is not accepted: ../x');
    failing({ components: 'a/b' }, 'The component list is invalid.');
    failing({ version: '4' }, 'Unexpected installer version 4.');

    const second = fixture();
    throwsExactly(() => installComponents(second.extracted, R, good.toolchain, installed), 'Two components install bin/fx-tool.exe.');
  }],
  ['FP-0079 case 7: install-rust verifies, stages, checks, and then installs, and leaves nothing behind on failure', async () => {
    for (const platform of Object.keys(HOSTS)) {
      const f = installFixture(platform), exe = platform.endsWith('-windows') ? '.exe' : '';
      const dest = path.join(f.dir, '.tools', 'rust', '1.99.0', platform);
      const components = f.layouts.map(l => ({ package: l.package, sha256: l.sha256, installer_components: [l.component] }));
      const first = await installRust(f.dir, { platform, fetch: f.fetch, run: f.run() });
      assert.deepEqual(first, { toolchain: path.join(dest, 'bin', `rustc${exe}`), downloaded: true, components });
      assert.equal(f.state.fetches, f.layouts.length);
      assert.deepEqual([...new Set(f.state.runs.map(r => r.cargoHome))], [path.join(f.dir, '.tools', 'cargo-home')]);
      const expected = [
        LOCK_PATH,
        ...f.layouts.map(l => `.tools/downloads/${path.posix.basename(new URL(l.url).pathname)}`),
        ...f.layouts.flatMap(l => l.files).map(p => `.tools/rust/1.99.0/${platform}/${p}`),
        `.tools/rust/1.99.0/${platform}/fairpane-install.json`,
      ].sort();
      assert.deepEqual(filesUnder(f.dir), expected);
      assert.deepEqual(fs.readdirSync(path.join(f.dir, '.tools')).sort(), ['downloads', 'rust']);
      assert.deepEqual(fs.readdirSync(path.join(f.dir, '.tools/rust')), ['1.99.0']);
      assert.deepEqual(fs.readdirSync(path.join(f.dir, '.tools/rust/1.99.0')), [platform]);
      assert.deepEqual(readJson(path.join(dest, 'fairpane-install.json')), {
        version: '1.99.0', platform, host: f.host, rustc_commit_hash: COMMIT, manifest_sha256: f.lock.manifest.sha256,
        components, source: 'https://static.rust-lang.org/dist/channel-rust-1.99.0.toml',
      });
      const second = await installRust(f.dir, { platform, fetch: f.fetch, run: f.run() });
      assert.deepEqual(second, { toolchain: path.join(dest, 'bin', `rustc${exe}`), downloaded: false });
      assert.equal(f.state.fetches, f.layouts.length);

      const exceeded = installFixture(platform, { serve: (url, bytes) => url.includes('/rustc-') ? Buffer.concat([bytes, Buffer.from([0])]) : bytes });
      await assert.rejects(installRust(exceeded.dir, { platform, fetch: exceeded.fetch, run: exceeded.run() }), /exceeded the locked archive size/);
      assertNoLeftovers(exceeded.dir, platform);

      const wrong = installFixture(platform, {
        serve: (url, bytes) => {
          if (!url.includes('/rustc-')) return bytes;
          const changed = Buffer.from(bytes); changed[changed.length - 1] ^= 0xff; return changed;
        },
      });
      await assert.rejects(installRust(wrong.dir, { platform, fetch: wrong.fetch, run: wrong.run() }), /rustc archive SHA-256 does not match the lock/);
      assertNoLeftovers(wrong.dir, platform);
      assert.deepEqual(filesUnder(path.join(wrong.dir, '.tools/downloads')), []);

      const corrupt = installFixture(platform), rustc = corrupt.layouts[0];
      put(corrupt.dir, `.tools/downloads/${path.posix.basename(new URL(rustc.url).pathname)}`, Buffer.alloc(rustc.bytes.length, 0x41));
      await assert.rejects(installRust(corrupt.dir, { platform, fetch: corrupt.fetch, run: corrupt.run() }), /rustc archive SHA-256 does not match the lock/);
      assert.equal(corrupt.state.fetches, 0);
      assertNoLeftovers(corrupt.dir, platform);

      const missing = installFixture(platform, { serve: (url, bytes) => url.includes('/rustc-') ? 404 : bytes });
      await assert.rejects(installRust(missing.dir, { platform, fetch: missing.fetch, run: missing.run() }), /rustc download failed with HTTP 404/);
      assertNoLeftovers(missing.dir, platform);

      const msvc = installFixture(platform);
      await assert.rejects(installRust(msvc.dir, { platform, fetch: msvc.fetch, run: msvc.run(versionOutputs('x86_64-pc-windows-msvc')) }), /Rust toolchain mismatch/);
      assertNoLeftovers(msvc.dir, platform);
    }
  }],
  ['FP-0079 case 8: the version checks accept only the locked release, commit, and host', () => {
    const lock = committedLock();
    for (const [platform, host] of Object.entries(HOSTS)) assert.deepEqual(toolchainVersionProblems(lock, platform, versionOutputs(host)), []);
    const outputs = versionOutputs(HOSTS['x86_64-windows']);
    const variant = (key, from, to) => toolchainVersionProblems(lock, 'x86_64-windows', { ...outputs, [key]: outputs[key].replace(from, to) });
    const mismatch = (release, commit, host) => [`Rust toolchain mismatch: expected release 1.99.0, commit ${COMMIT}, and host x86_64-pc-windows-gnu; found ${release}, ${commit}, and ${host}.`];
    assert.deepEqual(variant('rustc', 'release: 1.99.0', 'release: 1.98.1'), mismatch('1.98.1', COMMIT, 'x86_64-pc-windows-gnu'));
    assert.deepEqual(variant('rustc', `commit-hash: ${COMMIT}`, `commit-hash: ${'f'.repeat(40)}`), mismatch('1.99.0', 'f'.repeat(40), 'x86_64-pc-windows-gnu'));
    assert.deepEqual(variant('rustc', 'host: x86_64-pc-windows-gnu', 'host: x86_64-pc-windows-msvc'), mismatch('1.99.0', COMMIT, 'x86_64-pc-windows-msvc'));
    assert.deepEqual(variant('cargo', 'cargo 1.99.0', 'cargo 1.98.0'), ['cargo version mismatch: cargo 1.98.0 (5f94df478 2026-08-27)']);
    assert.deepEqual(variant('rustdoc', 'b940084d7', 'aaaaaaaaa'), ['rustdoc version mismatch: rustdoc 1.99.0 (aaaaaaaaa 2026-09-28)']);
    assert.deepEqual(variant('rustfmt', 'b940084d7e', 'aaaaaaaaaa'), ['rustfmt version mismatch: rustfmt 1.10.0-stable (aaaaaaaaaa 2026-09-28)']);
    assert.deepEqual(variant('rustc', 'LLVM version: 23.1.1\n', ''), []);
  }],
  ['FP-0079 case 9: the controller documents and exposes the Rust commands', () => {
    const controller = command => spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), command], { cwd: root, encoding: 'utf8', windowsHide: true });
    const help = controller('help');
    assert.equal(help.status, 0, help.stderr);
    const helpLines = help.stdout.split(/\r?\n/);
    const zigLine = helpLines.indexOf('  install-zig                 Install the exact locked compiler locally.');
    assert.ok(zigLine >= 0);
    assert.deepEqual(helpLines.slice(zigLine + 1, zigLine + 3), [
      '  install-rust                Install the exact locked Rust toolchain locally.',
      '  rust-lock-verify <manifest> Compare the Rust lock with a channel manifest file.',
    ]);
    const readme = fs.readFileSync(path.join(root, 'tools/README.md'), 'utf8').split('\n');
    for (const line of [
      '| `install-rust` | Downloads and checks the exact locked Rust toolchain components in a local directory. |',
      '| `rust-lock-verify <manifest>` | Exits with status 1 when a channel manifest file\'s digest or component entries differ from `toolchains/rust.lock.json`. |',
      '`install-rust` also accepts an existing toolchain directory after only a version check.',
    ]) assert.ok(readme.includes(line), line);
    // A program named rustc, first on PATH, creates a marker whenever it starts. doctor must not start it.
    const fakeBin = temp(), marker = path.join(temp(), 'rustc-started');
    const fakeRustc = markerProgram(path.join(fakeBin, process.platform === 'win32' ? 'rustc.exe' : 'rustc'), marker);
    const pathKey = Object.keys(process.env).find(key => key.toUpperCase() === 'PATH') ?? 'PATH';
    const env = { ...process.env, [pathKey]: [fakeBin, process.env[pathKey]].filter(Boolean).join(path.delimiter) };
    const doctor = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'doctor'], { cwd: root, env, encoding: 'utf8', windowsHide: true });
    assert.equal(doctor.status, 0, doctor.stderr);
    const report = JSON.parse(doctor.stdout);
    assert.deepEqual({ rust_available: typeof report.rust.available, path_rustc: Object.hasOwn(report, 'path_rustc'), marker: fs.existsSync(marker) },
      { rust_available: 'boolean', path_rustc: false, marker: false });
    const direct = spawnSync(fakeRustc, ['-V'], { encoding: 'utf8', windowsHide: true, timeout: 15000 });
    assert.equal(direct.error, undefined);
    assert.equal(direct.status, 0, direct.stderr);
    assert.equal(fs.existsSync(marker), true, 'The program on PATH did not create its marker when the test started it.');
  }],
  ['FP-0079 case 10: the toolchain documents and declarations record the pin', () => {
    const deps = readJson(path.join(root, 'engineering/dependencies.json'));
    assert.ok(deps.development.required_hosts.includes('Rust from toolchains/rust.lock.json, installed with node tools/fairpane.mjs install-rust'));
    const keys = Object.keys(deps.development);
    assert.equal(keys.indexOf('verification_tools'), keys.indexOf('package_dependencies') + 1);
    assert.deepEqual(deps.development.verification_tools, [{
      name: 'GnuPG',
      host: 'A GnuPG executable supplied by the host, whose exact version each verification records.',
      uses: ['Verifying the OpenPGP signature of an official Rust channel manifest against the Rust signing key when a reviewed change creates or updates toolchains/rust.lock.json.'],
      boundary: 'A review-time tool only. No build, gate, test, installation, or runtime path runs it.',
    }]);
    const toolchain = fs.readFileSync(path.join(root, 'docs/TOOLCHAIN.md'), 'utf8').split('\n');
    for (const line of DOC_LINES) assert.ok(toolchain.includes(line), line);
    assert.ok(toolchain.indexOf('## Rust installation') >= 0 && toolchain.indexOf('## Rust installation') < toolchain.indexOf('## Upgrade procedure'));
    const adr = fs.readFileSync(path.join(root, 'engineering/decisions/0010-rust-toolchain-host.md'), 'utf8').split('\n');
    const decision = adr.indexOf('## Decision'), next = adr.findIndex((line, i) => i > decision && line.startsWith('## '));
    assert.ok(decision >= 0 && next > decision);
    assert.ok(adr.slice(decision, next).includes('On Windows, Fairpane\'s Rust toolchain uses the `x86_64-pc-windows-gnu` host.'));
  }],
].map(([name, fn, declaration]) => ({ name, fn, ...declaration }));

export function removeRustFixtures() {
  const failures = [];
  for (const dir of temporary.splice(0).reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { failures.push(`${dir}: ${e.message}`); }
  }
  return failures;
}

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of rustCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  for (const problem of removeRustFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
  console.log(`1..${rustCases.length}\n# tests ${rustCases.length}\n# pass ${rustCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
