/**
 * File-set corpora: pinned upstream files and ZIP archives, such as the Unicode Character Database and the OpenType font fixtures.
 * `corpus-fetch` downloads every source, checks each pin and published digest, extracts the selected members without edits,
 * and only then writes the record. No code from a source runs, and `corpus-derive` runs only the declared import tool.
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { invariant, readJson, writeJson, sha256, fileHash, safePath, resolveExecutable } from './lib.mjs';

const HASH = /^[0-9a-f]{64}$/, OID = /^[0-9a-f]{40}$/;
const UTC_TIME = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d{3})?Z$/;
const NETWORK_TIMEOUT_MS = 3600000, TOOL_TIMEOUT_MS = 1800000;
const CORPORA_ROOT = '<corpora-root>';
/** Extraction writes only under these repository directories. */
export const EXTRACTION_ROOTS = Object.freeze(['src/unicode/ucd/', 'tests/text/fonts/']);
const ROLES = new Set(['data', 'font', 'license']);

const UCD = 'https://www.unicode.org/Public/18.0.0/ucd';
const ucdData = member => ({ source: 'ucd-zip', member, path: `src/unicode/ucd/${member}`, role: 'data', published_url: `${UCD}/${member}` });
const notoZip = (id, repo, tag, commit, size, digest) => ({
  id, url: `https://github.com/notofonts/${repo}/releases/download/${tag}/${tag}.zip`, kind: 'zip', local: `sources/${id}/${tag}.zip`,
  release: { name: tag, repository: `https://github.com/notofonts/${repo}`, tag, commit }, size, published_digest: digest, git_blob: null,
});
const notoFont = (source, dir, family) => [
  { source, member: `${family}/unhinted/ttf/${family}-Regular.ttf`, path: `tests/text/fonts/${dir}/${family}-Regular.ttf`, role: 'font',
    published_url: null, license: `tests/text/fonts/${dir}/OFL.txt` },
  { source, member: 'OFL.txt', path: `tests/text/fonts/${dir}/OFL.txt`, role: 'license', published_url: null },
];
const CJK_RAW = 'https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004';
const CJK_RELEASE = { name: 'Sans2.004', repository: 'https://github.com/notofonts/noto-cjk', tag: 'Sans2.004', commit: null };

/** The CJK subset's code points: exactly the distinct code points of the `cjk-greeting` seed. */
export const CJK_SUBSET_UNICODES = 'U+0020,U+3001,U+3002,U+3053,U+3055,U+3061,U+306A,U+306B,U+306E,U+306F,U+307F,U+3093,U+30AB,U+30FC,U+4E16,U+754C,U+AD6D,U+C5B4,U+D55C,U+20BB7';

/**
 * The frozen source sets of the FP-0013 contract. `size`, `published_digest`, `git_blob`, and `release.commit` are pins when not null.
 * A `selected` font names its license with `license`. A `derived` entry is written by `corpus-derive`.
 */
export const FILE_SET_RULES = Object.freeze({
  unicode: {
    version: '18.0.0',
    discovery: 'zip-members',
    sources: [
      { id: 'ucd-zip', url: `${UCD}/UCD.zip`, kind: 'zip', local: 'sources/UCD.zip',
        release: { name: 'Unicode 18.0.0', repository: null, tag: null, commit: null }, size: null, published_digest: null, git_blob: null },
      { id: 'unicode-license', url: 'https://www.unicode.org/license.txt', kind: 'file', local: 'sources/license.txt',
        release: { name: 'Unicode License v3', repository: null, tag: null, commit: null }, size: null, published_digest: null, git_blob: null },
    ],
    selected: [
      ucdData('Scripts.txt'), ucdData('ScriptExtensions.txt'), ucdData('PropertyValueAliases.txt'),
      ucdData('extracted/DerivedBidiClass.txt'), ucdData('extracted/DerivedJoiningType.txt'), ucdData('extracted/DerivedGeneralCategory.txt'),
      ucdData('IndicSyllabicCategory.txt'), ucdData('IndicPositionalCategory.txt'),
      { source: 'unicode-license', member: null, path: 'src/unicode/ucd/license.txt', role: 'license', published_url: null },
    ],
    derived: [],
  },
  'opentype-fixtures': {
    version: 'fixtures-1',
    discovery: 'font-files',
    sources: [
      notoZip('noto-sans', 'latin-greek-cyrillic', 'NotoSans-v2.015', 'c4a321e123e4d4ff315f57f4e0adf294fe3a95be', 117491253, null),
      notoZip('noto-sans-arabic', 'arabic', 'NotoSansArabic-v2.013', '1b2b7e5c6ce3ab4d50681c854892325530084c35', 18777381,
        'sha256:1301aceaea84c501cf2e6dcfb3182e2328c8eae5725817fcb239672bda7154f1'),
      notoZip('noto-sans-devanagari', 'devanagari', 'NotoSansDevanagari-v2.007', 'e123d230c160ebe949d731cc19017cdb354180d1', 18449254,
        'sha256:820c7da45b1e63562cb41c0a8cac5d9a4202312043a3a040ed1325857ef469b1'),
      { id: 'noto-cjk-otf', url: `${CJK_RAW}/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf`, kind: 'file', local: 'sources/noto-cjk/NotoSansCJKjp-Regular.otf',
        release: CJK_RELEASE, size: 16467736, published_digest: null, git_blob: 'f56224957fb13a81b4c14bac34f2f058a017f9fb' },
      { id: 'noto-cjk-license', url: `${CJK_RAW}/LICENSE`, kind: 'file', local: 'sources/noto-cjk/LICENSE',
        release: CJK_RELEASE, size: 4301, published_digest: null, git_blob: 'd952d62c065f3f35fb83a173496e90b21525aef3' },
    ],
    selected: [
      ...notoFont('noto-sans', 'noto-sans', 'NotoSans'),
      ...notoFont('noto-sans-arabic', 'noto-sans-arabic', 'NotoSansArabic'),
      ...notoFont('noto-sans-devanagari', 'noto-sans-devanagari', 'NotoSansDevanagari'),
      { source: 'noto-cjk-license', member: null, path: 'tests/text/fonts/noto-sans-cjk-jp-subset/LICENSE', role: 'license', published_url: null },
    ],
    derived: [{
      path: 'tests/text/fonts/noto-sans-cjk-jp-subset/cjk-subset.otf',
      input: 'noto-cjk-otf',
      tool: 'fontTools',
      argv: ['-m', 'fontTools.subset', `${CORPORA_ROOT}/opentype-fixtures/sources/noto-cjk/NotoSansCJKjp-Regular.otf`, `--unicodes=${CJK_SUBSET_UNICODES}`,
        '--layout-features=*', '--name-IDs=0,7,13,14', '--notdef-outline', '--output-file=<output>'],
      license_path: 'tests/text/fonts/noto-sans-cjk-jp-subset/LICENSE',
      rfn_resolution: 'The subset is an OFL Modified Version distributed only under the OFL with the upstream LICENSE beside it. ' +
        'The OFL makes a Reserved Font Name a name stated after a copyright statement. The LICENSE has no copyright line, so name ID 0 of the source font, ' +
        'recorded verbatim as copyright, carries the statement, and reserved_font_names lists every Reserved Font Name that it states. ' +
        'The contract also treats "Source" as a Reserved Font Name whether or not name ID 0 states it. ' +
        'The subset keeps only name IDs 0, 7, 13, and 14, so it carries no family, subfamily, full, unique, PostScript, typographic, or WWS name; ' +
        'its CFF Name INDEX keeps the PostScript name NotoSansCJKjp-Regular, which does not contain "Source"; and the file name cjk-subset.otf uses no upstream font name.',
    }],
  },
});
export const FILE_SET_IDS = Object.freeze(Object.keys(FILE_SET_RULES));

// CRC-32 and Git blob IDs.
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
export function crc32(data) {
  let c = 0xFFFFFFFF;
  for (const byte of data) c = CRC_TABLE[(c ^ byte) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
/** The Git blob ID of `data`: SHA-1 of `blob <size>\0` followed by the bytes. */
export function gitBlobId(data) {
  return crypto.createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
}

// ZIP archives.
const EOCD = 0x06054b50, CENTRAL = 0x02014b50, LOCAL = 0x04034b50, ZIP64_LOCATOR = 0x07064b50;
/** The largest sum of declared uncompressed member sizes that a zip may have. */
export const ZIP_MAX_TOTAL = 2 ** 30;
/** The largest ratio of a member's declared uncompressed size to its compressed size. */
export const ZIP_MAX_RATIO = 1024;
const S_IFMT = 0o170000, S_IFLNK = 0o120000, FILE_ATTRIBUTE_REPARSE_POINT = 0x400;

/** Check one member path: relative, forward slashes, no `.` or `..` segment, and no empty segment except a directory's final slash. */
function checkMemberPath(name) {
  invariant(name.length > 0, 'The zip has a member with an empty path.');
  invariant(!name.includes('\\'), `The zip member ${JSON.stringify(name)} contains a backslash.`);
  invariant(!name.startsWith('/') && !/^[A-Za-z]:/.test(name), `The zip member ${JSON.stringify(name)} is an absolute path.`);
  invariant(!/[\x00-\x1f]/.test(name), `The zip member ${JSON.stringify(name)} contains a control character.`);
  const parts = (name.endsWith('/') ? name.slice(0, -1) : name).split('/');
  invariant(!parts.includes('..'), `The zip member ${JSON.stringify(name)} has a ".." segment.`);
  invariant(parts.every(p => p.length > 0 && p !== '.'), `The zip member ${JSON.stringify(name)} has an empty or "." segment.`);
}

/**
 * Read a ZIP archive from memory. Only stored and deflate members are accepted. Every check below runs before any member is inflated.
 * - ZIP64, encryption, flag bit 13, absolute paths, `..` segments, backslashes, and duplicate paths are rejected.
 * - Each local header must agree with its central directory entry in method, flags, CRC-32, and sizes, and carry no ZIP64 extra field,
 *   so a member that uses a data descriptor is rejected.
 * - A member whose external attributes mark a symbolic link or a reparse point is rejected.
 * - Two names that are equal after ASCII case folding are rejected.
 * - Each member's range, from its local header to the end of its compressed data, lies before the central directory,
 *   and no two ranges overlap, so no compressed byte belongs to two members.
 * - The declared uncompressed sizes sum to at most 1 GiB, and no member declares more than 1024 times its compressed size.
 * `read(path)` inflates one file member, stops at its declared size, and checks its size and CRC-32.
 */
export function readZip(bytes) {
  invariant(Buffer.isBuffer(bytes) && bytes.length >= 22, 'The zip is shorter than an end of central directory record.');
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xFFFF); i--) {
    if (bytes.readUInt32LE(i) === EOCD && i + 22 + bytes.readUInt16LE(i + 20) === bytes.length) { eocd = i; break; }
  }
  invariant(eocd >= 0, 'The zip has no end of central directory record.');
  invariant(eocd < 20 || bytes.readUInt32LE(eocd - 20) !== ZIP64_LOCATOR, 'ZIP64 archives are not accepted.');
  const disk = bytes.readUInt16LE(eocd + 4), cdDisk = bytes.readUInt16LE(eocd + 6);
  const onDisk = bytes.readUInt16LE(eocd + 8), count = bytes.readUInt16LE(eocd + 10);
  const cdSize = bytes.readUInt32LE(eocd + 12), cdOffset = bytes.readUInt32LE(eocd + 16);
  invariant(count !== 0xFFFF && onDisk !== 0xFFFF && cdSize !== 0xFFFFFFFF && cdOffset !== 0xFFFFFFFF, 'ZIP64 archives are not accepted.');
  invariant(disk === 0 && cdDisk === 0 && onDisk === count, 'Multi-disk zip archives are not accepted.');
  invariant(cdOffset + cdSize === eocd, 'The zip central directory does not end at the end of central directory record.');
  const entries = [], seen = new Set(), folded = new Map(), ranges = [];
  let total = 0;
  let at = cdOffset;
  for (let i = 0; i < count; i++) {
    invariant(at + 46 <= eocd && bytes.readUInt32LE(at) === CENTRAL, `The zip central directory is truncated at entry ${i + 1}.`);
    const flags = bytes.readUInt16LE(at + 8), method = bytes.readUInt16LE(at + 10), crc = bytes.readUInt32LE(at + 16);
    const compressedSize = bytes.readUInt32LE(at + 20), size = bytes.readUInt32LE(at + 24);
    const nameLength = bytes.readUInt16LE(at + 28), extraLength = bytes.readUInt16LE(at + 30), commentLength = bytes.readUInt16LE(at + 32);
    const external = bytes.readUInt32LE(at + 38), localOffset = bytes.readUInt32LE(at + 42);
    const end = at + 46 + nameLength + extraLength + commentLength;
    invariant(end <= eocd, `The zip central directory is truncated at entry ${i + 1}.`);
    const rawName = bytes.subarray(at + 46, at + 46 + nameLength), name = rawName.toString('utf8');
    const member = `The zip member ${JSON.stringify(name)}`;
    invariant(Buffer.from(name, 'utf8').equals(rawName), `The zip member at entry ${i + 1} has a path that is not UTF-8.`);
    invariant(compressedSize !== 0xFFFFFFFF && size !== 0xFFFFFFFF && localOffset !== 0xFFFFFFFF, `ZIP64 member ${JSON.stringify(name)} is not accepted.`);
    checkNoZip64Extra(bytes, at + 46 + nameLength, extraLength, name);
    invariant((flags & 0x41) === 0, `${member} is encrypted.`);
    invariant((flags & 0x2000) === 0, `${member} sets flag bit 13, which masks its local header.`);
    invariant(method === 0 || method === 8, `${member} uses unsupported compression method ${method}.`);
    checkMemberPath(name);
    invariant(!seen.has(name), `The zip has a duplicate path ${JSON.stringify(name)}.`);
    seen.add(name);
    const key = name.replace(/[A-Z]/g, c => c.toLowerCase());
    invariant(!folded.has(key), `The zip paths ${JSON.stringify(folded.get(key))} and ${JSON.stringify(name)} are equal under ASCII case folding.`);
    folded.set(key, name);
    invariant(((external >>> 16) & S_IFMT) !== S_IFLNK && (external & FILE_ATTRIBUTE_REPARSE_POINT) === 0, `${member} is a symbolic link.`);
    const directory = name.endsWith('/');
    invariant(!directory || size === 0, `The zip directory member ${JSON.stringify(name)} has data.`);
    invariant(method !== 0 || compressedSize === size, `The stored zip member ${JSON.stringify(name)} has inconsistent sizes.`);
    invariant(size <= ZIP_MAX_RATIO * compressedSize,
      `${member} declares ${size} uncompressed bytes from ${compressedSize} compressed bytes, a ratio over ${ZIP_MAX_RATIO}.`);
    total += size;
    invariant(total <= ZIP_MAX_TOTAL, `The zip members declare ${total} or more uncompressed bytes, more than 1 GiB.`);

    invariant(localOffset + 30 <= cdOffset && bytes.readUInt32LE(localOffset) === LOCAL, `${member} has no local header.`);
    const localName = bytes.readUInt16LE(localOffset + 26), localExtra = bytes.readUInt16LE(localOffset + 28);
    invariant(localName === nameLength && bytes.subarray(localOffset + 30, localOffset + 30 + localName).equals(rawName),
      `${member} has a local header with another path.`);
    const dataStart = localOffset + 30 + localName + localExtra;
    invariant(dataStart <= cdOffset, `${member} has a local header that runs into the central directory.`);
    const local = { method: bytes.readUInt16LE(localOffset + 8), flags: bytes.readUInt16LE(localOffset + 6), 'CRC-32': bytes.readUInt32LE(localOffset + 14),
      sizes: [bytes.readUInt32LE(localOffset + 18), bytes.readUInt32LE(localOffset + 22)] };
    const central = { method, flags, 'CRC-32': crc, sizes: [compressedSize, size] };
    for (const field of Object.keys(central)) {
      invariant(String(local[field]) === String(central[field]), `${member} has a local header that disagrees with its central directory entry in ${field}.`);
    }
    checkNoZip64Extra(bytes, localOffset + 30 + localName, localExtra, name);
    invariant(dataStart + compressedSize <= cdOffset, `${member} runs into the central directory.`);
    ranges.push({ name, start: localOffset, end: dataStart + compressedSize });
    entries.push({ path: name, method, size, compressedSize, crc, directory, dataStart });
    at = end;
  }
  invariant(at === eocd, 'The zip central directory has bytes after its last entry.');
  ranges.sort((a, b) => a.start - b.start);
  for (let k = 1; k < ranges.length; k++) {
    invariant(ranges[k - 1].end <= ranges[k].start, `The zip members ${JSON.stringify(ranges[k - 1].name)} and ${JSON.stringify(ranges[k].name)} overlap.`);
  }
  const byPath = new Map(entries.map(e => [e.path, e]));
  return {
    entries,
    read(member) {
      const e = byPath.get(member);
      invariant(e && !e.directory, `The zip has no file member ${JSON.stringify(member)}.`);
      const raw = bytes.subarray(e.dataStart, e.dataStart + e.compressedSize);
      let data;
      if (e.method === 0) data = Buffer.from(raw);
      else {
        try { data = zlib.inflateRawSync(raw, { maxOutputLength: Math.max(1, e.size) }); }
        catch (err) { throw new Error(`The zip member ${JSON.stringify(member)} does not inflate: ${err.message}`); }
      }
      invariant(data.length === e.size, `The zip member ${JSON.stringify(member)} has ${data.length} bytes, not ${e.size}.`);
      invariant(crc32(data) === e.crc, `The zip member ${JSON.stringify(member)} fails its CRC-32.`);
      return data;
    },
  };
}

/** Reject a ZIP64 extended information field (ID 0x0001) in an extra field. */
function checkNoZip64Extra(bytes, start, length, name) {
  for (let x = start; x + 4 <= start + length;) {
    const id = bytes.readUInt16LE(x), len = bytes.readUInt16LE(x + 2);
    invariant(id !== 0x0001, `ZIP64 member ${JSON.stringify(name)} is not accepted.`);
    x += 4 + len;
  }
}

/**
 * The canonical inventory of a zip: `<sha256>\t<size>\t<path>\n` for each file member, sorted by the UTF-8 bytes of the path.
 * Directory members are excluded. A zip without a file member has no inventory.
 */
export function zipInventory(zip, { keepLines = false } = {}) {
  const files = zip.entries.filter(e => !e.directory).sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)));
  invariant(files.length > 0, 'The zip has no file members.');
  const hash = crypto.createHash('sha256'), lines = [];
  let total = 0;
  for (const e of files) {
    const data = zip.read(e.path);
    const line = `${sha256(data)}\t${data.length}\t${e.path}\n`;
    hash.update(line, 'utf8'); total += data.length;
    if (keepLines) lines.push(line);
  }
  const inventory = { entry_count: files.length, total_bytes: total, sha256: hash.digest('hex') };
  if (keepLines) inventory.lines = lines;
  return inventory;
}

// Record validation.
const isObject = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const isSize = n => Number.isSafeInteger(n) && n >= 0;
const text = v => typeof v === 'string' && v.trim().length > 0;
function onlyKeys(value, allowed, where) {
  for (const key of Object.keys(value)) invariant(allowed.includes(key), `${where} has an unexpected field "${key}".`);
}
function checkRepoPath(p, where) {
  invariant(typeof p === 'string' && /^[A-Za-z0-9._/ -]+$/.test(p) && !p.startsWith('/') && !p.split('/').some(s => !s || s === '.' || s === '..'),
    `${where} needs a repository-relative path.`);
  invariant(EXTRACTION_ROOTS.some(r => p.startsWith(r)), `${where} path ${p} is outside ${EXTRACTION_ROOTS.join(' and ')}.`);
}
function checkRelease(release, where) {
  invariant(isObject(release) && text(release.name), `${where} needs a release.`);
  onlyKeys(release, ['name', 'repository', 'tag', 'commit'], `${where} release`);
  invariant(release.repository === null || (typeof release.repository === 'string' && release.repository.startsWith('https://')), `${where} release repository must be HTTPS or null.`);
  invariant((release.repository === null) === (release.tag === null), `${where} release needs both a repository and a tag, or neither.`);
  invariant(release.tag === null || text(release.tag), `${where} release tag must be text or null.`);
  invariant(release.commit === null || OID.test(release.commit), `${where} release commit must be 40 hex digits or null.`);
  invariant(release.repository === null || release.commit !== null, `${where} release needs the commit of its tag.`);
}

/** Validate a file-set snapshot record. Throws an Error that names the first problem. */
export function validateFileSetRecord(r, { allowFileSources = false } = {}) {
  invariant(isObject(r) && r.schema_version === 1 && r.kind === 'file-set', 'The file-set record schema is invalid.');
  onlyKeys(r, ['schema_version', 'corpus', 'kind', 'upstream', 'version', 'retrieved_at', 'sources', 'selected', 'derived'], 'The file-set record');
  invariant(typeof r.corpus === 'string' && /^[a-z0-9][a-z0-9-]*$/.test(r.corpus), 'The file-set record needs a corpus ID.');
  invariant(typeof r.upstream === 'string' && r.upstream.startsWith('https://'), 'The file-set record needs an HTTPS upstream.');
  invariant(text(r.version), 'The file-set record needs a version.');
  invariant(typeof r.retrieved_at === 'string' && UTC_TIME.test(r.retrieved_at), 'The file-set record needs a UTC retrieval time.');
  invariant(Array.isArray(r.sources) && r.sources.length > 0, 'The file-set record needs sources.');
  const sources = new Map();
  for (const s of r.sources) {
    const where = `Source ${s?.id}`;
    invariant(isObject(s) && typeof s.id === 'string' && /^[a-z0-9][a-z0-9-]*$/.test(s.id) && !sources.has(s.id), 'Each source needs a unique ID.');
    onlyKeys(s, ['id', 'url', 'kind', 'release', 'size', 'sha256', 'published_digest', 'git_blob', 'local_path', 'inventory'], where);
    invariant(typeof s.url === 'string' && (s.url.startsWith('https://') || (allowFileSources && s.url.startsWith('file://'))), `${where} needs an HTTPS URL.`);
    invariant(s.kind === 'zip' || s.kind === 'file', `${where} kind must be zip or file.`);
    checkRelease(s.release, where);
    invariant(isSize(s.size) && s.size > 0, `${where} needs a size.`);
    invariant(typeof s.sha256 === 'string' && HASH.test(s.sha256), `${where} needs a SHA-256.`);
    invariant(s.published_digest === null || (typeof s.published_digest === 'string' && /^sha256:[0-9a-f]{64}$/.test(s.published_digest)),
      `${where} published_digest must be sha256:<hex> or null.`);
    invariant(s.git_blob === null || (typeof s.git_blob === 'string' && OID.test(s.git_blob)), `${where} git_blob must be 40 hex digits or null.`);
    invariant(typeof s.local_path === 'string' && s.local_path.startsWith(`${CORPORA_ROOT}/${r.corpus}/sources/`) && !s.local_path.includes('..'),
      `${where} needs a local_path under ${CORPORA_ROOT}/${r.corpus}/sources/.`);
    if (s.kind === 'zip') {
      const i = s.inventory;
      invariant(isObject(i) && isSize(i.entry_count) && i.entry_count > 0 && isSize(i.total_bytes) && typeof i.sha256 === 'string' && HASH.test(i.sha256),
        `${where} needs an inventory with entry_count, total_bytes, and sha256.`);
    } else invariant(s.inventory === undefined, `${where} is a file and has no inventory.`);
    sources.set(s.id, s);
  }
  invariant(Array.isArray(r.selected) && r.selected.length > 0, 'The file-set record needs selected files.');
  const paths = new Set(), licenses = new Map();
  for (const e of r.selected) {
    const where = `Selected ${e?.path}`;
    invariant(isObject(e), 'Each selected entry must be an object.');
    checkRepoPath(e.path, where);
    invariant(!paths.has(e.path), `${where} is listed twice.`);
    paths.add(e.path);
    const source = sources.get(e.source);
    invariant(source, `${where} names an unknown source.`);
    invariant(source.kind === 'zip' ? text(e.member) : e.member === null, `${where} needs a member for a zip source and none for a file source.`);
    invariant(ROLES.has(e.role), `${where} role must be data, font, or license.`);
    invariant(e.published_url === null || (typeof e.published_url === 'string' && (e.published_url.startsWith('https://') || (allowFileSources && e.published_url.startsWith('file://')))),
      `${where} published_url must be HTTPS or null.`);
    const fontKeys = e.role === 'font' ? ['license_path', 'license_name', 'copyright', 'reserved_font_names'] : [];
    onlyKeys(e, ['source', 'member', 'path', 'size', 'sha256', 'role', 'published_url', ...fontKeys], where);
    if (e.role === 'license' && isSize(e.size) && typeof e.sha256 === 'string' && HASH.test(e.sha256)) licenses.set(e.path, e);
    invariant(isSize(e.size), `${where} needs a size.`);
    invariant(typeof e.sha256 === 'string' && HASH.test(e.sha256), e.role === 'license' ? `${where} has no license digest.` : `${where} needs a SHA-256.`);
  }
  const checkLicensed = (e, where) => {
    invariant(licenses.has(e.license_path), `${where} has no license digest: no selected license entry with a size and SHA-256 at ${e.license_path}.`);
    invariant(text(e.copyright), `${where} needs a copyright notice.`);
    invariant(Array.isArray(e.reserved_font_names) && e.reserved_font_names.every(text), `${where} needs reserved_font_names.`);
  };
  for (const e of r.selected) if (e.role === 'font') {
    checkLicensed(e, `Font ${e.path}`);
    invariant(text(e.license_name), `Font ${e.path} needs the license name that its license text states.`);
  }
  invariant(Array.isArray(r.derived), 'The file-set record needs a derived list.');
  for (const d of r.derived) {
    const where = `Derived ${d?.path}`;
    invariant(isObject(d), 'Each derived entry must be an object.');
    onlyKeys(d, ['path', 'size', 'sha256', 'input', 'tool', 'argv', 'license_path', 'copyright', 'reserved_font_names', 'rfn_resolution'], where);
    checkRepoPath(d.path, where);
    invariant(!paths.has(d.path), `${where} is listed twice.`);
    paths.add(d.path);
    invariant(isSize(d.size) && typeof d.sha256 === 'string' && HASH.test(d.sha256), `${where} needs a size and SHA-256.`);
    invariant(isObject(d.input) && sources.has(d.input.source), `${where} needs an input source.`);
    invariant(typeof d.input.sha256 === 'string' && HASH.test(d.input.sha256), `${where} needs an input digest.`);
    invariant(isObject(d.tool) && text(d.tool.name), `${where} needs a tool name.`);
    invariant(text(d.tool.version), `${where} needs a tool version.`);
    invariant(typeof d.tool.wheel_url === 'string' && d.tool.wheel_url.startsWith('https://') && typeof d.tool.wheel_sha256 === 'string' && HASH.test(d.tool.wheel_sha256),
      `${where} needs the tool wheel URL and SHA-256.`);
    invariant(text(d.tool.python), `${where} needs the Python version.`);
    invariant(Array.isArray(d.argv) && d.argv.length > 0 && d.argv.every(a => typeof a === 'string'), `${where} needs its argv.`);
    checkLicensed(d, where);
    invariant(text(d.rfn_resolution), `${where} needs an rfn_resolution.`);
  }
  return true;
}

/** The SHA-256 of the record's source listing, one `<sha256>\t<size>\t<source id>\n` line per source in record order. */
export function sourceListingDigest(record) {
  return sha256(record.sources.map(s => `${s.sha256}\t${s.size}\t${s.id}\n`).join(''));
}

// License texts.
/** Read the license name, the first copyright line, and any Reserved Font Names from an OFL text. */
export function oflFields(licenseText, where) {
  const name = /licensed under the (SIL Open Font License, Version 1\.1)/.exec(licenseText)?.[1];
  invariant(name, `${where}: the license text does not state the SIL Open Font License, Version 1.1.`);
  const copyright = /^(Copyright[^\r\n]*\S)/m.exec(licenseText)?.[1];
  invariant(copyright, `${where}: the license text has no copyright line.`);
  return { license_name: name, copyright, reserved_font_names: reservedFontNames(licenseText) };
}
/** The names that a text states as Reserved Font Names, such as `with Reserved Font Name 'Source'`. */
export function reservedFontNames(statement) {
  const names = [];
  for (const m of statement.matchAll(/Reserved Font Names?\s*([^.\r\n]*)/g)) {
    for (const q of m[1].matchAll(/["'\u2018\u201C]([^"'\u2019\u201D]+)["'\u2019\u201D]/g)) names.push(q[1].trim());
  }
  return [...new Set(names)];
}

/**
 * Name ID 0 of an sfnt font, decoded from the first (3, 1, 0x409) record, or else the first (1, 0, 0) record.
 * The first `name` directory record names the table, and every length is checked before the bytes behind it are read.
 */
export function sfntCopyright(bytes) {
  invariant(bytes.length >= 12, 'The font is shorter than an sfnt header.');
  const tables = bytes.readUInt16BE(4);
  invariant(12 + 16 * tables <= bytes.length, 'The font table directory runs past the end of the font.');
  let name = null;
  for (let i = 0; i < tables && !name; i++) {
    const at = 12 + 16 * i;
    if (bytes.toString('latin1', at, at + 4) === 'name') name = { offset: bytes.readUInt32BE(at + 8), length: bytes.readUInt32BE(at + 12) };
  }
  invariant(name, 'The font has no name table.');
  invariant(name.offset + name.length <= bytes.length, 'The name table runs past the end of the font.');
  const t = bytes.subarray(name.offset, name.offset + name.length);
  invariant(t.length >= 6, 'The name table is shorter than its 6-byte header.');
  const count = t.readUInt16BE(2), storage = t.readUInt16BE(4);
  invariant(6 + 12 * count <= t.length, 'The name records run past the name table.');
  const find = (platform, encoding, language) => {
    for (let i = 0; i < count; i++) {
      const at = 6 + 12 * i;
      if (t.readUInt16BE(at) === platform && t.readUInt16BE(at + 2) === encoding && t.readUInt16BE(at + 4) === language && t.readUInt16BE(at + 6) === 0) {
        const start = storage + t.readUInt16BE(at + 10), len = t.readUInt16BE(at + 8);
        invariant(start + len <= t.length, 'A name record runs past the name table.');
        return t.subarray(start, start + len);
      }
    }
    return null;
  };
  const windows = find(3, 1, 0x409);
  if (windows) return Buffer.from(windows).swap16().toString('utf16le');
  const mac = find(1, 0, 0);
  invariant(mac, 'The font has no name ID 0 record.');
  return mac.toString('latin1');
}

// Network and local sources.
/** The only hosts that a download may reach, on its first URL and on every redirect. */
export const DOWNLOAD_HOSTS = Object.freeze(['www.unicode.org', 'github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com', 'raw.githubusercontent.com']);
/** The size limit of a download without a pinned size. */
export const DEFAULT_DOWNLOAD_LIMIT = 256 * 1024 * 1024;
const MAX_REDIRECTS = 10;

/** The byte limit of a source download: its pinned size, else the previous record's size, else 256 MiB. */
export function downloadLimit(source, previous) {
  return source.size ?? previous?.size ?? DEFAULT_DOWNLOAD_LIMIT;
}

function checkHop(url) {
  const u = new URL(url);
  invariant(u.protocol === 'https:', `A download hop must use https:, not ${u.protocol}: ${url}`);
  invariant(DOWNLOAD_HOSTS.includes(u.hostname) && u.port === '' && u.username === '' && u.password === '',
    `A download hop may reach only ${DOWNLOAD_HOSTS.join(', ')}, not ${u.host}: ${url}`);
  return u.href;
}

/**
 * Request `url`, follow at most 10 redirects manually, and pass each body chunk to `onChunk`.
 * Every hop must use https: on an allowlisted host. The body stops as soon as it exceeds `limit` bytes.
 * `httpFetch` replaces `fetch` only in tests.
 */
async function streamDownload(url, { limit, httpFetch = fetch, onChunk }) {
  invariant(Number.isSafeInteger(limit) && limit >= 0, `A download needs a byte limit: ${url}`);
  let current = checkHop(url);
  const signal = AbortSignal.timeout(NETWORK_TIMEOUT_MS);
  for (let hop = 0; ; hop++) {
    const response = await httpFetch(current, { redirect: 'manual', signal });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      await response.body?.cancel();
      invariant(hop < MAX_REDIRECTS, `${url} redirected more than ${MAX_REDIRECTS} times.`);
      const location = response.headers.get('location');
      invariant(location, `${current} redirected without a Location header.`);
      current = checkHop(new URL(location, current).href);
      console.log(`Redirect to ${current}`);
      continue;
    }
    invariant(response.ok, `${current} returned HTTP status ${response.status}.`);
    const declared = Number(response.headers.get('content-length') ?? NaN);
    if (declared > limit) {
      await response.body?.cancel();
      throw new Error(`The download of ${url} exceeds its limit of ${limit} bytes: it declares ${declared} bytes.`);
    }
    let received = 0;
    if (response.body) {
      for await (const chunk of response.body) {
        received += chunk.length;
        invariant(received <= limit, `The download of ${url} exceeds its limit of ${limit} bytes.`);
        onChunk(chunk);
      }
    }
    return received;
  }
}

/**
 * Download one source into `file` and return its size and SHA-256. A `file://` URL, which only tests enable, is copied.
 * A failure removes the partial file.
 */
export async function downloadSource(url, file, { limit, allowFileSources = false, httpFetch } = {}) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  try {
    if (url.startsWith('file://')) {
      invariant(allowFileSources === true, `Only HTTPS sources are accepted: ${url}`);
      const size = fs.statSync(fileURLToPath(url)).size;
      invariant(size <= limit, `The download of ${url} exceeds its limit of ${limit} bytes.`);
      fs.copyFileSync(fileURLToPath(url), file);
    } else {
      console.log(`Download ${url}`);
      const out = fs.openSync(file, 'w');
      try { await streamDownload(url, { limit, httpFetch, onChunk: chunk => fs.writeSync(out, chunk) }); } finally { fs.closeSync(out); }
    }
  } catch (e) {
    fs.rmSync(file, { force: true });
    throw e;
  }
  const size = fs.statSync(file).size, digest = fileHash(file);
  console.log(`Stored ${url}: ${size} bytes, SHA-256 ${digest}`);
  return { size, sha256: digest };
}

/** Download `url` into memory under the same rules as `downloadSource`. */
export async function fetchBytes(url, { limit = DEFAULT_DOWNLOAD_LIMIT, allowFileSources = false, httpFetch } = {}) {
  if (url.startsWith('file://')) {
    invariant(allowFileSources === true, `Only HTTPS URLs are accepted: ${url}`);
    const bytes = fs.readFileSync(fileURLToPath(url));
    invariant(bytes.length <= limit, `The download of ${url} exceeds its limit of ${limit} bytes.`);
    return bytes;
  }
  const chunks = [];
  await streamDownload(url, { limit, httpFetch, onChunk: chunk => chunks.push(Buffer.from(chunk)) });
  return Buffer.concat(chunks);
}
/** The commit that a tag names, through `git ls-remote`, peeled when the tag is annotated. */
function tagCommit(repository, tag) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !/^GIT_/i.test(name)));
  const argv = ['--no-replace-objects', 'ls-remote', repository, `refs/tags/${tag}`, `refs/tags/${tag}^{}`];
  const git = resolveExecutable(process.cwd(), 'git');
  console.log(`Run ${JSON.stringify([git, ...argv])}`);
  const r = spawnSync(git, argv, { encoding: 'utf8', env: { ...env, GIT_TERMINAL_PROMPT: '0' }, timeout: NETWORK_TIMEOUT_MS, windowsHide: true });
  invariant(!r.error && r.status === 0, `git ls-remote ${repository} failed: ${r.error?.message ?? r.stderr.trim()}`);
  process.stdout.write(r.stdout);
  const peeled = new RegExp(`^([0-9a-f]{40})\\trefs/tags/${tag.replace(/[.^$*+?()[\]{}|\\]/g, '\\$&')}\\^\\{\\}$`, 'm').exec(r.stdout)?.[1];
  const direct = new RegExp(`^([0-9a-f]{40})\\trefs/tags/${tag.replace(/[.^$*+?()[\]{}|\\]/g, '\\$&')}$`, 'm').exec(r.stdout)?.[1];
  invariant(peeled || direct, `${repository} has no tag ${tag}.`);
  return peeled ?? direct;
}

const localFile = (corporaDir, id, local) => path.join(corporaDir, id, ...local.split('/'));
const localPathOf = (id, local) => `${CORPORA_ROOT}/${id}/${local}`;
function resolveLocal(corporaDir, localPath) {
  invariant(localPath.startsWith(`${CORPORA_ROOT}/`), `Unexpected local path ${localPath}.`);
  return path.join(corporaDir, ...localPath.slice(CORPORA_ROOT.length + 1).split('/'));
}

/** Compare a file-set record with its `specs/corpora.json` pins. A null pin field pins nothing. */
export function fileSetPinProblems(pins, id, record) {
  const problems = [];
  const check = (field, actual) => {
    if (pins[field] != null && pins[field] !== actual) problems.push(`pin ${field}: pinned ${JSON.stringify(pins[field])}, snapshot has ${JSON.stringify(actual)}`);
  };
  check('revision', record.version);
  check('inventory_sha256', sourceListingDigest(record));
  check('license_record', `specs/snapshots/${id}.json`);
  check('manifest_sha256', null);
  return problems;
}
/** Compare a new record with the existing record's per-source and per-file digests. */
function recordPinProblems(previous, record) {
  if (!previous) return [];
  const problems = [];
  const check = (what, pinned, actual) => {
    if (pinned != null && pinned !== actual) problems.push(`pin ${what}: recorded ${JSON.stringify(pinned)}, fetched ${JSON.stringify(actual)}`);
  };
  check('version', previous.version, record.version);
  for (const s of record.sources) {
    const p = previous.sources.find(x => x.id === s.id);
    if (!p) continue;
    check(`sources.${s.id}.size`, p.size, s.size);
    check(`sources.${s.id}.sha256`, p.sha256, s.sha256);
    check(`sources.${s.id}.inventory`, p.inventory?.sha256, s.inventory?.sha256);
    check(`sources.${s.id}.release.commit`, p.release?.commit, s.release.commit);
  }
  for (const e of record.selected) {
    const p = previous.selected.find(x => x.path === e.path);
    if (p) check(`selected.${e.path}.sha256`, p.sha256, e.sha256);
  }
  return problems;
}

function checkExtractionPath(root, p) {
  invariant(EXTRACTION_ROOTS.some(r => p.startsWith(r)), `Extraction may write only under ${EXTRACTION_ROOTS.join(' and ')}: ${p}`);
  return safePath(root, p, { mustExist: false });
}

/**
 * Download every source of a file-set corpus into a staging directory and compare each with every known digest:
 * its pinned size, published digest, and Git blob ID, the previous record's size and SHA-256, and the `specs/corpora.json` pins.
 * Only then parse the archives, extract the selected members in memory, and check the remaining pins.
 * The fetch holds `<id>.lock` throughout, and `commitSnapshot` writes the extracted files, the sources, and the record or restores the old ones.
 * A failure leaves the existing sources, record, and extracted files unchanged and no staged or temporary file behind.
 * `onWriteStep(label)`, which only tests pass, runs before each write step and may throw to inject a failure.
 */
export async function fetchFileSet(root, id, options) {
  invariant(options.rule, `No file-set rule exists for corpus ${id}.`);
  return withFetchLock(options.corporaDir, id, () => fetchFileSetLocked(root, id, options));
}
/** The body of `fetchFileSet`, which runs while the fetch holds the lock of corpus `id`. */
async function fetchFileSetLocked(root, id, { corporaDir, policy, rule, allowFileSources = false, onWriteStep }) {
  const recordFile = path.join(root, 'specs', 'snapshots', `${id}.json`);
  let previous = null;
  if (fs.existsSync(recordFile)) {
    previous = readJson(recordFile);
    validateFileSetRecord(previous, { allowFileSources });
    invariant(previous.corpus === id, `The record names corpus ${previous.corpus}, not ${id}.`);
  }
  const target = path.join(corporaDir, id), staging = path.join(corporaDir, `${id}.fetch`), old = path.join(corporaDir, `${id}.old`);
  const pinFailure = problems => `The fetched file set ${id} does not match its pins, so the existing sources, record, and files stay:\n- ${problems.join('\n- ')}`;
  fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  fs.mkdirSync(staging, { recursive: true });
  try {
    // Download every source and compare it with every known digest. Nothing parses a source in this loop.
    const downloaded = [];
    for (const s of rule.sources) {
      const file = path.join(staging, ...s.local.split('/'));
      const prior = previous?.sources.find(x => x.id === s.id) ?? null;
      const got = await downloadSource(s.url, file, { limit: downloadLimit(s, prior), allowFileSources });
      const problems = [];
      if (s.size !== null && s.size !== got.size) problems.push(`Source ${s.id} has ${got.size} bytes, not the expected ${s.size}.`);
      if (s.published_digest !== null && s.published_digest !== `sha256:${got.sha256}`) {
        problems.push(`Source ${s.id} does not match its published digest ${s.published_digest}: SHA-256 ${got.sha256}.`);
      }
      if (prior && prior.size !== got.size) problems.push(`pin sources.${s.id}.size: recorded ${prior.size}, fetched ${got.size}`);
      if (prior && prior.sha256 !== got.sha256) problems.push(`pin sources.${s.id}.sha256: recorded ${JSON.stringify(prior.sha256)}, fetched ${JSON.stringify(got.sha256)}`);
      if (s.git_blob !== null) {
        const blob = gitBlobId(fs.readFileSync(file));
        if (blob !== s.git_blob) problems.push(`Source ${s.id} has Git blob ID ${blob}, not ${s.git_blob}.`);
      }
      invariant(problems.length === 0, pinFailure(problems));
      downloaded.push({ s, file, got });
    }
    const listing = { version: rule.version, sources: downloaded.map(({ s, got }) => ({ id: s.id, size: got.size, sha256: got.sha256 })) };
    const corporaProblems = fileSetPinProblems(policy, id, listing);
    invariant(corporaProblems.length === 0, pinFailure(corporaProblems));

    // Every source matches every known digest, so the archives may be parsed.
    const sources = [], data = new Map();
    for (const { s, file, got } of downloaded) {
      const release = { ...s.release };
      if (release.repository !== null) {
        const commit = tagCommit(release.repository, release.tag);
        invariant(release.commit === null || release.commit === commit, `Tag ${release.tag} of ${release.repository} names ${commit}, not ${release.commit}.`);
        release.commit = commit;
      }
      const entry = { id: s.id, url: s.url, kind: s.kind, release, size: got.size, sha256: got.sha256, published_digest: s.published_digest,
        git_blob: s.git_blob, local_path: localPathOf(id, s.local) };
      const bytes = fs.readFileSync(file);
      if (s.kind === 'zip') {
        const zip = readZip(bytes);
        const inventory = zipInventory(zip);
        entry.inventory = inventory;
        data.set(s.id, { zip });
        console.log(`Inventory of ${s.id}: ${inventory.entry_count} file members, ${inventory.total_bytes} bytes, SHA-256 ${inventory.sha256}`);
      } else data.set(s.id, { bytes });
      sources.push(entry);
    }

    const extracted = new Map(), selected = [];
    for (const e of rule.selected) {
      checkExtractionPath(root, e.path);
      const source = data.get(e.source);
      invariant(source, `Selected ${e.path} names an unknown source ${e.source}.`);
      const bytes = e.member === null ? source.bytes : source.zip.read(e.member);
      invariant(bytes, `Selected ${e.path} has no bytes.`);
      if (e.published_url !== null) {
        const published = await fetchBytes(e.published_url, { allowFileSources });
        invariant(published.equals(bytes), `The published_url ${e.published_url} serves bytes that differ from member ${e.member}.`);
        console.log(`Published ${e.published_url} equals member ${e.member}.`);
      }
      extracted.set(e.path, bytes);
      selected.push({ source: e.source, member: e.member, path: e.path, size: bytes.length, sha256: sha256(bytes), role: e.role, published_url: e.published_url });
    }
    for (const [i, e] of rule.selected.entries()) {
      if (e.role !== 'font') continue;
      const license = extracted.get(e.license);
      invariant(license && rule.selected.some(x => x.path === e.license && x.role === 'license'), `Font ${e.path} needs a selected license at ${e.license}.`);
      Object.assign(selected[i], { license_path: e.license, ...oflFields(license.toString('utf8'), e.license) });
    }
    const record = { schema_version: 1, corpus: id, kind: 'file-set', upstream: policy.upstream, version: rule.version,
      retrieved_at: new Date().toISOString(), sources, selected, derived: previous?.derived ?? [] };
    validateFileSetRecord(record, { allowFileSources });
    const problems = [...recordPinProblems(previous, record), ...fileSetPinProblems(policy, id, record)];
    invariant(problems.length === 0, pinFailure(problems));

    // Every check passed. Replace the extracted files, then the sources, then the record, or restore all of them.
    const files = [...extracted].map(([p, bytes]) => ({ label: p, file: checkExtractionPath(root, p), bytes }));
    commitSnapshot({ files, target, staging, old, recordFile, record, onWriteStep });
    return { result: 'pass', corpus: id, kind: 'file-set', record: `specs/snapshots/${id}.json`, version: record.version,
      sources: sources.map(s => ({ id: s.id, size: s.size, sha256: s.sha256, release: s.release, inventory: s.inventory })),
      selected: selected.map(e => ({ path: e.path, size: e.size, sha256: e.sha256 })), source_listing_sha256: sourceListingDigest(record) };
  } catch (e) {
    fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
    throw e;
  }
}

/**
 * Run `fn` while holding the fetch lock of corpus `id`, the file `<id>.lock` in `corporaDir`, created exclusively with this process's ID and start time.
 * A fetch takes the lock before it touches `<id>.fetch` and releases it after it removes `<id>.old`, so two fetches never share a staging directory.
 * A held lock fails at once and changes nothing. The lock is removed after success and after failure.
 */
export async function withFetchLock(corporaDir, id, fn) {
  const lock = path.join(corporaDir, `${id}.lock`);
  fs.mkdirSync(corporaDir, { recursive: true });
  let fd;
  try { fd = fs.openSync(lock, 'wx'); }
  catch (e) {
    if (e.code !== 'EEXIST') throw e;
    throw new Error(`Another fetch of ${id} holds the lock file ${lock}: ${lockHolder(lock)}. This fetch changed nothing. ` +
      'If that process no longer runs, remove the lock file and fetch again.');
  }
  try {
    try { fs.writeFileSync(fd, `${JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })}\n`); }
    finally { fs.closeSync(fd); }
  } catch (e) {
    fs.rmSync(lock, { force: true });
    throw e;
  }
  let result, failure = null;
  try { result = await fn(); } catch (e) { failure = e; }
  try { fs.rmSync(lock, { force: true, maxRetries: 3 }); }
  catch (e) {
    const message = `The fetch could not remove its lock file ${lock}: ${e.message}`;
    if (failure) failure.message += `\n${message}`; else failure = new Error(message);
  }
  if (failure) throw failure;
  return result;
}
/** The process ID and start time that a lock file names, or why they cannot be read. */
function lockHolder(lock) {
  let text;
  try { text = fs.readFileSync(lock, 'utf8'); } catch (e) { return `the lock file could not be read: ${e.message}`; }
  try {
    const { pid, started_at } = JSON.parse(text);
    if (Number.isSafeInteger(pid) && typeof started_at === 'string') return `process ${pid}, started at ${started_at}`;
  } catch { /* Reported below. */ }
  return `the lock file holds no process ID and start time: ${JSON.stringify(text.slice(0, 200))}`;
}

/**
 * The write phase of a corpus fetch, which the Git corpus fetch and the file-set fetch share.
 * It removes a stale `old`, stages each file of `files` (`{ label, file, bytes }`) and the record beside its target, moves each old file aside,
 * installs the staged files, moves the old `target` directory to `old`, renames `staging` to `target`, and renames the staged record last.
 * On any failure it restores every old file, the old directory, and the old record, and it removes every staged file and every directory that it created.
 * After success it removes the old files and `old`. `onWriteStep(label)`, which only tests pass, runs before each write step and may throw.
 */
export function commitSnapshot({ files = [], target, staging, old, recordFile, record, onWriteStep }) {
  fs.rmSync(old, { recursive: true, force: true, maxRetries: 3 });
  const tag = crypto.randomUUID();
  const step = label => onWriteStep?.(label);
  const staged = [], replaced = [], created = [], dirs = [];
  let sources = 'unchanged';
  const ensureDir = dir => {
    // Record each missing ancestor, outermost first, so a rollback can remove exactly the directories that this phase created.
    const missing = [];
    for (let d = path.resolve(dir); !fs.existsSync(d) && path.dirname(d) !== d; d = path.dirname(d)) missing.unshift(d);
    for (const d of missing) {
      fs.mkdirSync(d);
      dirs.push(d);
    }
  };
  const stage = (label, file, bytes) => {
    ensureDir(path.dirname(file));
    const temporary = `${file}.${tag}.new`;
    step(label);
    staged.push(temporary);
    fs.writeFileSync(temporary, bytes, { flag: 'wx' });
    return temporary;
  };
  try {
    const stagedFiles = files.map(f => ({ ...f, temporary: stage(`stage ${f.label}`, f.file, f.bytes) }));
    const recordTemporary = stage('stage the record', recordFile, `${JSON.stringify(record, null, 2)}\n`);
    for (const f of stagedFiles) {
      if (fs.existsSync(f.file)) {
        step(`back up ${f.label}`);
        const backup = `${f.file}.${tag}.old`;
        fs.renameSync(f.file, backup);
        replaced.push({ file: f.file, backup });
      } else created.push(f.file);
      step(`replace ${f.label}`);
      fs.renameSync(f.temporary, f.file);
    }
    if (fs.existsSync(target)) {
      step('back up the sources');
      fs.renameSync(target, old);
      sources = 'backed-up';
    }
    step('replace the sources');
    fs.renameSync(staging, target);
    sources = sources === 'backed-up' ? 'replaced' : 'created';
    step('replace the record');
    fs.renameSync(recordTemporary, recordFile);
  } catch (e) {
    const problems = [];
    const attempt = (what, fn) => { try { fn(); } catch (err) { problems.push(`${what}: ${err.message}`); } };
    if (sources === 'replaced' || sources === 'created') attempt('move the new sources back to staging', () => fs.renameSync(target, staging));
    if (sources === 'replaced' || sources === 'backed-up') attempt('restore the old sources', () => fs.renameSync(old, target));
    for (const r of replaced.reverse()) attempt(`restore ${r.file}`, () => fs.renameSync(r.backup, r.file));
    for (const file of created.reverse()) attempt(`remove ${file}`, () => fs.rmSync(file, { force: true }));
    for (const file of staged) attempt(`remove ${file}`, () => fs.rmSync(file, { force: true }));
    for (const dir of dirs.reverse()) attempt(`remove ${dir}`, () => fs.rmdirSync(dir));
    if (problems.length) e.message += `\nThe rollback also failed:\n- ${problems.join('\n- ')}`;
    throw e;
  }
  const problems = [];
  for (const r of replaced) {
    try { fs.rmSync(r.backup, { force: true, maxRetries: 3 }); } catch (err) { problems.push(`${r.backup}: ${err.message}`); }
  }
  try { fs.rmSync(old, { recursive: true, force: true, maxRetries: 3 }); } catch (err) { problems.push(`${old}: ${err.message}`); }
  invariant(problems.length === 0, `The fetch wrote every file and the record, but could not remove the old copies:\n- ${problems.join('\n- ')}`);
}

// Applicability.
const FONT_FILE = /\.(ttf|otf)$/i;
const sortedKeys = object => Object.fromEntries(Object.entries(object).sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b))));
const DISCOVERY = {
  'zip-members': {
    rule: 'Count the file members of each zip source; directory members are not counted. ' +
      'A member is selected when the record extracts it. Every other member is an unclassified later import.',
    by: 'first path component of each zip file member; "." for a member at the top level',
  },
  'font-files': {
    rule: 'Count the members of each zip source whose path ends in ".ttf" or ".otf", compared case-insensitively, and each file source whose URL ends in ".ttf" or ".otf". ' +
      'A font is selected when the record extracts it or derives a fixture from it. Every other font is unclassified.',
    by: 'source ID',
  },
};
/** Count discovered and selected items of a file-set record from its local sources. */
export function fileSetApplicability(record, zips, discoveryKind) {
  const discovery = DISCOVERY[discoveryKind];
  invariant(discovery, `Unknown file-set discovery ${discoveryKind}.`);
  const counts = {}, inventories = {};
  let discovered = 0, selected = 0;
  const derivedInputs = new Set(record.derived.map(d => d.input.source));
  for (const s of record.sources) {
    if (s.kind === 'zip') {
      inventories[s.id] = s.inventory.sha256;
      for (const e of zips.get(s.id).entries) {
        if (e.directory || (discoveryKind === 'font-files' && !FONT_FILE.test(e.path))) continue;
        const key = discoveryKind === 'font-files' ? s.id : (e.path.includes('/') ? e.path.slice(0, e.path.indexOf('/')) : '.');
        counts[key] = (counts[key] ?? 0) + 1; discovered++;
        if (record.selected.some(x => x.source === s.id && x.member === e.path)) selected++;
      }
    } else if (discoveryKind === 'font-files' && FONT_FILE.test(new URL(s.url).pathname)) {
      inventories[s.id] = s.sha256;
      counts[s.id] = (counts[s.id] ?? 0) + 1; discovered++;
      if (derivedInputs.has(s.id) || record.selected.some(x => x.source === s.id && x.role === 'font')) selected++;
    }
  }
  return { schema_version: 1, corpus: record.corpus, version: record.version, inventories: sortedKeys(inventories), status: 'counted',
    discovery: { rule: discovery.rule, command: `node tools/fairpane.mjs corpus-applicability ${record.corpus}` },
    discovered, selected, excluded: [], unclassified: discovered - selected,
    breakdown: { by: discovery.by, counts: sortedKeys(counts) } };
}

/** Read every zip source of a record from the local sources. A source whose size or SHA-256 differs from the record is not parsed. */
function loadZips(record, corporaDir, problems) {
  const zips = new Map();
  for (const s of record.sources.filter(x => x.kind === 'zip')) {
    const file = resolveLocal(corporaDir, s.local_path);
    if (!fs.existsSync(file)) { problems.push(`source ${s.id}: missing ${file}`); continue; }
    const bytes = fs.readFileSync(file);
    if (bytes.length !== s.size || sha256(bytes) !== s.sha256) {
      problems.push(`source ${s.id}: the local file has ${bytes.length} bytes with SHA-256 ${sha256(bytes)}, not the recorded ${s.size} bytes with SHA-256 ${s.sha256}`);
      continue;
    }
    try { zips.set(s.id, readZip(bytes)); } catch (e) { problems.push(`source ${s.id}: ${e.message}`); }
  }
  return zips;
}

export function readFileSetRecord(root, id, { allowFileSources = false } = {}) {
  const file = path.join(root, 'specs', 'snapshots', `${id}.json`);
  invariant(fs.existsSync(file), `Missing snapshot record: specs/snapshots/${id}.json`);
  const record = readJson(file);
  validateFileSetRecord(record, { allowFileSources });
  invariant(record.corpus === id, `The snapshot record names corpus ${record.corpus}, not ${id}.`);
  return record;
}

/** Write `specs/applicability/<id>.json` from the local sources. No network access is used. */
export function classifyFileSet(root, id, { corporaDir, discoveryKind, allowFileSources = false }) {
  const record = readFileSetRecord(root, id, { allowFileSources }), problems = [];
  const zips = loadZips(record, corporaDir, problems);
  invariant(problems.length === 0, `Corpus ${id} has missing or unreadable sources:\n- ${problems.join('\n- ')}`);
  for (const s of record.sources.filter(x => x.kind === 'zip')) {
    const inventory = zipInventory(zips.get(s.id));
    invariant(inventory.sha256 === s.inventory.sha256, `The local source ${s.id} differs from specs/snapshots/${id}.json. Run corpus-fetch ${id}.`);
  }
  return fileSetApplicability(record, zips, discoveryKind);
}

/** Rehash every local source, inventory, selected file, derived file, and license, and recompute the applicability record. */
export function verifyFileSet(root, id, { corporaDir, policy, discoveryKind, validateApplicability, allowFileSources = false }) {
  const record = readFileSetRecord(root, id, { allowFileSources }), problems = [];
  const expect = (field, recorded, actual) => {
    if (recorded !== actual) problems.push(`${field}: recorded ${JSON.stringify(recorded)}, found ${JSON.stringify(actual)}`);
  };
  expect('upstream', record.upstream, policy.upstream);
  // A source is parsed only when its size and SHA-256 equal the record.
  const sourceBytes = new Map();
  for (const s of record.sources) {
    const file = resolveLocal(corporaDir, s.local_path);
    if (!fs.existsSync(file)) { problems.push(`source ${s.id}: missing ${file}`); continue; }
    const bytes = fs.readFileSync(file), digest = sha256(bytes);
    expect(`source ${s.id} size`, s.size, bytes.length);
    expect(`source ${s.id} sha256`, s.sha256, digest);
    if (s.git_blob !== null) expect(`source ${s.id} git_blob`, s.git_blob, gitBlobId(bytes));
    if (s.published_digest !== null) expect(`source ${s.id} published_digest`, s.published_digest, `sha256:${digest}`);
    if (bytes.length === s.size && digest === s.sha256) sourceBytes.set(s.id, bytes);
  }
  const zips = new Map();
  for (const s of record.sources.filter(x => x.kind === 'zip' && sourceBytes.has(x.id))) {
    try {
      const zip = readZip(sourceBytes.get(s.id)), inventory = zipInventory(zip);
      for (const k of ['entry_count', 'total_bytes', 'sha256']) expect(`source ${s.id} inventory.${k}`, s.inventory[k], inventory[k]);
      zips.set(s.id, zip);
    } catch (e) { problems.push(`source ${s.id}: ${e.message}`); }
  }
  const repoFile = (kind, e) => {
    const file = safePath(root, e.path, { mustExist: false });
    if (!fs.existsSync(file)) { problems.push(`${kind} ${e.path}: missing`); return null; }
    const bytes = fs.readFileSync(file);
    if (bytes.length !== e.size || sha256(bytes) !== e.sha256) {
      problems.push(`${kind} ${e.path}: recorded ${e.size} bytes with SHA-256 ${e.sha256}, found ${bytes.length} bytes with SHA-256 ${sha256(bytes)}`);
    }
    return bytes;
  };
  for (const e of record.selected) {
    repoFile('selected', e);
    let upstream = null;
    if (e.member === null) upstream = sourceBytes.get(e.source) ?? null;
    else if (zips.has(e.source)) {
      try { upstream = zips.get(e.source).read(e.member); } catch (err) { problems.push(`selected ${e.path}: ${err.message}`); }
    }
    if (upstream && sha256(upstream) !== e.sha256) problems.push(`selected ${e.path}: the source member differs from the record`);
  }
  for (const d of record.derived) {
    repoFile('derived', d);
    const input = record.sources.find(s => s.id === d.input.source);
    expect(`derived ${d.path} input`, d.input.sha256, input?.sha256);
  }
  problems.push(...fileSetPinProblems(policy, id, record));
  const file = path.join(root, 'specs', 'applicability', `${id}.json`);
  let applicability = null;
  if (!fs.existsSync(file)) problems.push(`Missing applicability record: specs/applicability/${id}.json`);
  else {
    const a = readJson(file);
    try {
      validateApplicability(a);
      applicability = { discovered: a.discovered, selected: a.selected, excluded: a.excluded.length, unclassified: a.unclassified };
      if (zips.size === record.sources.filter(s => s.kind === 'zip').length) {
        const fresh = fileSetApplicability(record, zips, discoveryKind);
        if (JSON.stringify(fresh) !== JSON.stringify(a)) problems.push('applicability: the recorded discovery differs from the local sources.');
      }
    } catch (e) { problems.push(`applicability: ${e.message}`); }
  }
  invariant(problems.length === 0, `Corpus ${id} failed verification:\n- ${problems.join('\n- ')}`);
  return { record, applicability };
}

/** The import-tool record of fontTools from `engineering/dependencies.json`. */
function importTool(root, name) {
  const tool = readJson(path.join(root, 'engineering', 'dependencies.json')).development.import_tools.find(t => t.name === name);
  invariant(tool, `engineering/dependencies.json declares no import tool ${name}.`);
  return tool;
}
/** The local environment of an import tool under `.tools/python/`. */
function toolEnvironment(root, tool) {
  return path.join(root, '.tools', 'python', `${tool.name.toLowerCase()}-${tool.version}`);
}
/** The interpreter of the local fontTools environment under `.tools/python/`. */
export function toolPython(root, tool) {
  return path.join(toolEnvironment(root, tool), ...(process.platform === 'win32' ? ['Scripts', 'python.exe'] : ['bin', 'python']));
}
/** The site-packages directory of a virtual environment. */
function toolSitePackages(venv) {
  if (process.platform === 'win32') return path.join(venv, 'Lib', 'site-packages');
  const lib = path.join(venv, 'lib');
  const versions = fs.existsSync(lib) ? fs.readdirSync(lib).filter(n => /^python3\.\d+$/.test(n)) : [];
  invariant(versions.length === 1, `${venv} needs exactly one lib/python3.N directory.`);
  return path.join(lib, versions[0], 'site-packages');
}

/**
 * The environment of a Python import tool: the parent environment without any variable whose name starts with PYTHON,
 * plus PYTHONSAFEPATH=1, so neither the working directory nor a script's directory joins `sys.path`.
 */
export function pythonEnvironment(base = process.env) {
  const env = Object.fromEntries(Object.entries(base).filter(([name]) => !/^PYTHON/i.test(name)));
  env.PYTHONSAFEPATH = '1';
  return env;
}

/**
 * Run a Python import tool without a shell, with `pythonEnvironment`, in the absolute working directory `cwd`, which is a staging directory.
 * The tool runs without an operating-system sandbox, on inputs pinned by Git blob or SHA-256 only.
 */
export function runPython(python, argv, { cwd, baseEnv = process.env, timeout = TOOL_TIMEOUT_MS, stdio = 'pipe' } = {}) {
  invariant(typeof cwd === 'string' && path.isAbsolute(cwd), 'A Python import tool runs only in an absolute staging directory.');
  return spawnSync(python, argv, { cwd, env: pythonEnvironment(baseEnv), encoding: 'utf8', stdio, timeout, windowsHide: true });
}

/** The three fields of one wheel RECORD line, a CSV row of path, hash, and size. */
function recordFields(line) {
  const fields = [];
  let i = 0;
  while (i <= line.length) {
    if (line[i] === '"') {
      let value = '';
      for (i += 1; ;) {
        const quote = line.indexOf('"', i);
        invariant(quote >= 0, `A wheel RECORD line has an unterminated quote: ${line}`);
        value += line.slice(i, quote);
        if (line[quote + 1] === '"') { value += '"'; i = quote + 2; } else { i = quote + 1; break; }
      }
      invariant(i === line.length || line[i] === ',', `A wheel RECORD line has text after a quoted field: ${line}`);
      fields.push(value);
      i += 1;
    } else {
      const comma = line.indexOf(',', i), end = comma < 0 ? line.length : comma;
      fields.push(line.slice(i, end));
      i = end + 1;
    }
  }
  invariant(fields.length === 3, `A wheel RECORD line does not have three fields: ${line}`);
  return fields;
}

/**
 * Check an installed import tool against its verified wheel: the wheel's SHA-256 must equal `engineering/dependencies.json`,
 * every file that the wheel's RECORD lists must be installed with that SHA-256 and size, and every file in the tool's packages
 * must be listed, except bytecode that the installer compiled into `__pycache__`.
 */
export function verifyToolInstallation(root, tool) {
  const wheelFile = path.join(root, '.tools', 'downloads', path.posix.basename(new URL(tool.wheel_url).pathname));
  invariant(fs.existsSync(wheelFile), `The ${tool.name} wheel is missing: ${wheelFile}. Download it as tools/README.md describes.`);
  const wheel = fs.readFileSync(wheelFile), wheelDigest = sha256(wheel);
  invariant(wheelDigest === tool.wheel_sha256, `The ${tool.name} wheel ${wheelFile} has SHA-256 ${wheelDigest}, not ${tool.wheel_sha256}.`);
  const zip = readZip(wheel);
  const records = zip.entries.filter(e => /^[^/]+\.dist-info\/RECORD$/.test(e.path));
  invariant(records.length === 1, `The ${tool.name} wheel has ${records.length} RECORD files, not 1.`);
  const recordPath = records[0].path;
  const dataPrefix = `${recordPath.slice(0, -'.dist-info/RECORD'.length)}.data/`;
  const venv = toolEnvironment(root, tool), site = toolSitePackages(venv);
  const listed = new Set(), packages = new Set();
  let files = 0;
  for (const line of zip.read(recordPath).toString('utf8').split(/\r?\n/)) {
    if (!line) continue;
    const [file, hash, size] = recordFields(line);
    if (file === recordPath) continue;
    checkMemberPath(file);
    const digest = /^sha256=([A-Za-z0-9_-]{43})$/.exec(hash)?.[1];
    invariant(digest && /^\d+$/.test(size), `The ${tool.name} wheel RECORD has no SHA-256 and size for ${file}.`);
    let installed;
    if (file.startsWith(dataPrefix)) {
      const [scheme, ...rest] = file.slice(dataPrefix.length).split('/');
      invariant(['data', 'purelib', 'platlib'].includes(scheme) && rest.length > 0, `The ${tool.name} wheel installs ${file}, which this check does not support.`);
      installed = scheme === 'data' ? path.join(venv, ...rest) : path.join(site, ...rest);
    } else {
      installed = path.join(site, ...file.split('/'));
      if (!file.split('/')[0].endsWith('.dist-info') && file.includes('/')) packages.add(file.split('/')[0]);
    }
    listed.add(path.resolve(installed));
    invariant(fs.existsSync(installed), `The installed file ${file} is missing, so ${tool.name} does not match its wheel's RECORD.`);
    const bytes = fs.readFileSync(installed);
    invariant(bytes.length === Number(size) && crypto.createHash('sha256').update(bytes).digest('base64url') === digest,
      `The installed file ${file} differs from its wheel's RECORD, so ${tool.name} is refused.`);
    files++;
  }
  const pending = [...packages].map(name => path.join(site, name));
  while (pending.length > 0) {
    const dir = pending.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) { pending.push(file); continue; }
      const relative = path.relative(site, file).split(path.sep).join('/');
      if (listed.has(path.resolve(file)) || (/(^|\/)__pycache__\/[^/]+\.pyc$/.test(relative) && entry.isFile())) continue;
      throw new Error(`The installed file ${relative} is not listed in the ${tool.name} wheel's RECORD, so ${tool.name} is refused.`);
    }
  }
  return { wheel: wheelFile, wheel_sha256: wheelDigest, files, site_packages: site };
}

const TOOL_PROBE = 'import sys, fontTools; print(fontTools.version); print(sys.version.split()[0]); print(sys.flags.safe_path); print(fontTools.__file__)';

/** Run the interpreter once in `cwd` and require the declared fontTools version, safe-path mode, and the verified package. Returns the Python version. */
function probeTool(python, tool, site, cwd) {
  const probe = runPython(python, ['-c', TOOL_PROBE], { cwd, timeout: 60000 });
  invariant(!probe.error && probe.status === 0, `${python} could not import ${tool.name}: ${probe.error?.message ?? probe.stderr}`);
  const [toolVersion, pythonVersion, safePathFlag, imported] = probe.stdout.trim().split(/\r?\n/);
  invariant(toolVersion === tool.version, `${python} has ${tool.name} ${toolVersion}, not ${tool.version}.`);
  invariant(safePathFlag === 'True', `${python} did not run with PYTHONSAFEPATH=1.`);
  const canonical = file => {
    const real = fs.realpathSync.native(file);
    return process.platform === 'win32' ? real.toLowerCase() : real;
  };
  invariant(fs.existsSync(imported ?? '') && canonical(imported) === canonical(path.join(site, 'fontTools', '__init__.py')),
    `${python} imported ${tool.name} from ${imported}, not from the verified ${site}.`);
  return pythonVersion;
}

/**
 * Run each declared derivation of a file-set corpus with its import tool, and record the result.
 * The installation is checked against its wheel's RECORD before anything runs, and the tool runs in the staging directory under `runPython`.
 * The output must equal any existing fixture byte for byte, so a rerun proves the derivation reproducible.
 */
export function deriveFileSet(root, id, { corporaDir, rule }) {
  invariant(rule && rule.derived.length > 0, `Corpus ${id} declares no derived files.`);
  const tools = rule.derived.map(spec => {
    const tool = importTool(root, spec.tool), python = toolPython(root, tool);
    invariant(fs.existsSync(python), `The ${tool.name} environment is missing: ${python}. Install it from the verified wheel.`);
    const verified = verifyToolInstallation(root, tool);
    console.log(`Verified ${verified.files} installed ${tool.name} files against the RECORD of ${verified.wheel}.`);
    return { tool, python, site: verified.site_packages };
  });
  const record = readFileSetRecord(root, id);
  const staging = path.join(corporaDir, `${id}.derive`);
  fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  fs.mkdirSync(staging, { recursive: true });
  try {
    for (const [i, spec] of rule.derived.entries()) {
      const { tool, python, site } = tools[i];
      const pythonVersion = probeTool(python, tool, site, staging);
      const input = record.sources.find(s => s.id === spec.input);
      invariant(input, `Derived ${spec.path} names an unknown input source ${spec.input}.`);
      const inputFile = resolveLocal(corporaDir, input.local_path);
      const inputBytes = fs.readFileSync(inputFile);
      invariant(sha256(inputBytes) === input.sha256, `The local source ${input.id} differs from its record. Run corpus-fetch ${id}.`);
      const output = path.join(staging, path.posix.basename(spec.path));
      const argv = spec.argv.map(a => a.replaceAll(`${CORPORA_ROOT}/`, `${corporaDir}${path.sep}`.replaceAll('\\', '/')).replace('<output>', output));
      console.log(`Run ${JSON.stringify([python, ...argv])} in ${staging}`);
      const run = runPython(python, argv, { cwd: staging, stdio: 'inherit' });
      invariant(!run.error && run.status === 0, `${tool.name} exited with status ${run.status}${run.error ? `: ${run.error.message}` : ''}.`);
      const bytes = fs.readFileSync(output), digest = sha256(bytes);
      console.log(`Derived ${spec.path}: ${bytes.length} bytes, SHA-256 ${digest}`);
      const target = checkExtractionPath(root, spec.path);
      if (fs.existsSync(target)) {
        const existing = fs.readFileSync(target);
        invariant(existing.equals(bytes), `The derivation of ${spec.path} is not reproducible: the existing file has SHA-256 ${sha256(existing)}, the new run ${digest}.`);
      } else {
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, bytes, { flag: 'wx' });
      }
      const copyright = sfntCopyright(inputBytes);
      const entry = { path: spec.path, size: bytes.length, sha256: digest, input: { source: input.id, sha256: input.sha256 },
        tool: { name: tool.name, version: tool.version, wheel_url: tool.wheel_url, wheel_sha256: tool.wheel_sha256, python: pythonVersion },
        argv: spec.argv, license_path: spec.license_path, copyright, reserved_font_names: reservedFontNames(copyright), rfn_resolution: spec.rfn_resolution };
      record.derived = [...record.derived.filter(d => d.path !== spec.path), entry];
    }
    validateFileSetRecord(record);
    writeJson(path.join(root, 'specs', 'snapshots', `${id}.json`), record);
    return { result: 'pass', corpus: id, derived: record.derived };
  } finally {
    fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  }
}

/** The script that writes the font expectation files, and the fonts that it describes: every selected and derived font of `opentype-fixtures`. */
export const EXPECTATION_SCRIPT = 'tools/fonts/font_expectations.py';
export const EXPECTATION_FONTS = Object.freeze([
  ...FILE_SET_RULES['opentype-fixtures'].selected.filter(e => e.role === 'font').map(e => e.path),
  ...FILE_SET_RULES['opentype-fixtures'].derived.map(d => d.path),
]);

/**
 * Run `tools/fonts/font_expectations.py` for every fixture font under `runPython`, after the installation check.
 * A fresh staging directory holds copies of the script, the seeds, and the fonts, and it is the working directory, so the run
 * reads and writes nothing in the repository. With `check`, the result fails when any output differs from the committed file;
 * otherwise each differing committed file is replaced.
 */
export function fontExpectations(root, { check = false } = {}) {
  const tool = importTool(root, 'fontTools'), python = toolPython(root, tool);
  invariant(fs.existsSync(python), `The ${tool.name} environment is missing: ${python}. Install it from the verified wheel.`);
  const verified = verifyToolInstallation(root, tool);
  console.log(`Verified ${verified.files} installed ${tool.name} files against the RECORD of ${verified.wheel}.`);
  const staging = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-font-expectations-'));
  try {
    const copy = relative => {
      const to = path.join(staging, ...relative.split('/'));
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(safePath(root, relative), to);
    };
    copy(EXPECTATION_SCRIPT);
    for (const name of fs.readdirSync(path.join(root, 'tests', 'text', 'seeds')).filter(n => n.endsWith('.json')).sort()) copy(`tests/text/seeds/${name}`);
    const pythonVersion = probeTool(python, tool, verified.site_packages, staging);
    const expectations = [];
    for (const font of EXPECTATION_FONTS) {
      copy(font);
      console.log(`Run ${JSON.stringify([python, EXPECTATION_SCRIPT, font])} in ${staging}`);
      const run = runPython(python, [EXPECTATION_SCRIPT, font], { cwd: staging, stdio: 'inherit' });
      invariant(!run.error && run.status === 0, `${EXPECTATION_SCRIPT} exited with status ${run.status}${run.error ? `: ${run.error.message}` : ''}.`);
      const relative = font.replace(/\.[^./]+$/, '.expect.json');
      const produced = fs.readFileSync(path.join(staging, ...relative.split('/')));
      const committedFile = safePath(root, relative, { mustExist: false });
      const equal = fs.existsSync(committedFile) && fs.readFileSync(committedFile).equals(produced);
      if (!check && !equal) writeBytes(committedFile, produced);
      expectations.push({ path: relative, size: produced.length, sha256: sha256(produced), equals_committed: equal });
      console.log(`${relative}: ${produced.length} bytes, SHA-256 ${sha256(produced)}, ${equal ? 'byte-identical to' : 'different from'} the committed file`);
    }
    const differ = expectations.filter(e => !e.equals_committed).map(e => e.path);
    return { result: check && differ.length ? 'fail' : 'pass', mode: check ? 'check' : 'write', tool: { name: tool.name, version: tool.version,
      wheel_sha256: verified.wheel_sha256, verified_files: verified.files, python: pythonVersion }, environment: { PYTHONSAFEPATH: '1', other_python_variables: 'removed' },
    expectations, differing: differ };
  } finally {
    fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  }
}

function writeBytes(file, bytes) {
  const temporary = `${file}.${crypto.randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, bytes, { flag: 'wx' });
    fs.renameSync(temporary, file);
  } finally { fs.rmSync(temporary, { force: true }); }
}
