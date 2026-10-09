/**
 * File-set corpora: pinned upstream files and ZIP archives, such as the Unicode Character Database and the OpenType font fixtures.
 * `corpus-fetch` downloads every source, checks each pin and published digest, extracts the selected members without edits,
 * and only then writes the record. No code from a source runs, and `corpus-derive` runs only the declared import tool.
 */
import fs from 'node:fs';
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
 * Read a ZIP archive from memory. Only stored and deflate members are accepted.
 * ZIP64, encryption, absolute paths, `..` segments, backslashes, and duplicate paths are rejected.
 * `read(path)` inflates one file member and checks its size and CRC-32.
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
  const entries = [], seen = new Set();
  let at = cdOffset;
  for (let i = 0; i < count; i++) {
    invariant(at + 46 <= eocd && bytes.readUInt32LE(at) === CENTRAL, `The zip central directory is truncated at entry ${i + 1}.`);
    const flags = bytes.readUInt16LE(at + 8), method = bytes.readUInt16LE(at + 10), crc = bytes.readUInt32LE(at + 16);
    const compressedSize = bytes.readUInt32LE(at + 20), size = bytes.readUInt32LE(at + 24);
    const nameLength = bytes.readUInt16LE(at + 28), extraLength = bytes.readUInt16LE(at + 30), commentLength = bytes.readUInt16LE(at + 32);
    const localOffset = bytes.readUInt32LE(at + 42);
    const end = at + 46 + nameLength + extraLength + commentLength;
    invariant(end <= eocd, `The zip central directory is truncated at entry ${i + 1}.`);
    const rawName = bytes.subarray(at + 46, at + 46 + nameLength), name = rawName.toString('utf8');
    invariant(Buffer.from(name, 'utf8').equals(rawName), `The zip member at entry ${i + 1} has a path that is not UTF-8.`);
    invariant(compressedSize !== 0xFFFFFFFF && size !== 0xFFFFFFFF && localOffset !== 0xFFFFFFFF, `ZIP64 member ${JSON.stringify(name)} is not accepted.`);
    for (let x = at + 46 + nameLength; x + 4 <= at + 46 + nameLength + extraLength;) {
      const id = bytes.readUInt16LE(x), len = bytes.readUInt16LE(x + 2);
      invariant(id !== 0x0001, `ZIP64 member ${JSON.stringify(name)} is not accepted.`);
      x += 4 + len;
    }
    invariant((flags & 0x41) === 0, `The zip member ${JSON.stringify(name)} is encrypted.`);
    invariant(method === 0 || method === 8, `The zip member ${JSON.stringify(name)} uses unsupported compression method ${method}.`);
    checkMemberPath(name);
    invariant(!seen.has(name), `The zip has a duplicate path ${JSON.stringify(name)}.`);
    seen.add(name);
    const directory = name.endsWith('/');
    invariant(!directory || size === 0, `The zip directory member ${JSON.stringify(name)} has data.`);
    invariant(localOffset + 30 <= cdOffset && bytes.readUInt32LE(localOffset) === LOCAL, `The zip member ${JSON.stringify(name)} has no local header.`);
    const localName = bytes.readUInt16LE(localOffset + 26), localExtra = bytes.readUInt16LE(localOffset + 28);
    invariant(localName === nameLength && bytes.subarray(localOffset + 30, localOffset + 30 + localName).equals(rawName),
      `The zip member ${JSON.stringify(name)} has a local header with another path.`);
    const dataStart = localOffset + 30 + localName + localExtra;
    invariant(dataStart + compressedSize <= cdOffset, `The zip member ${JSON.stringify(name)} runs into the central directory.`);
    invariant(method !== 0 || compressedSize === size, `The stored zip member ${JSON.stringify(name)} has inconsistent sizes.`);
    entries.push({ path: name, method, size, compressedSize, crc, directory, dataStart });
    at = end;
  }
  invariant(at === eocd, 'The zip central directory has bytes after its last entry.');
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

/** Name ID 0 of an sfnt font, decoded from the first (3, 1, 0x409) record, or else the first (1, 0, 0) record. */
export function sfntCopyright(bytes) {
  const tables = bytes.readUInt16BE(4);
  let name = null;
  for (let i = 0; i < tables; i++) {
    const at = 12 + 16 * i;
    if (bytes.toString('latin1', at, at + 4) === 'name') name = { offset: bytes.readUInt32BE(at + 8), length: bytes.readUInt32BE(at + 12) };
  }
  invariant(name && name.offset + name.length <= bytes.length, 'The font has no name table.');
  const t = bytes.subarray(name.offset, name.offset + name.length);
  const count = t.readUInt16BE(2), storage = t.readUInt16BE(4);
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
async function download(url, file, { allowFileSources }) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (url.startsWith('file://')) {
    invariant(allowFileSources === true, `Only HTTPS sources are accepted: ${url}`);
    fs.copyFileSync(fileURLToPath(url), file);
  } else {
    invariant(url.startsWith('https://'), `Only HTTPS sources are accepted: ${url}`);
    console.log(`Download ${url}`);
    const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(NETWORK_TIMEOUT_MS) });
    invariant(response.ok, `${url} returned HTTP status ${response.status}.`);
    invariant(response.url.startsWith('https://'), `${url} redirected to a non-HTTPS URL: ${response.url}`);
    const out = fs.openSync(file, 'w');
    try { for await (const chunk of response.body) fs.writeSync(out, chunk); } finally { fs.closeSync(out); }
  }
  const size = fs.statSync(file).size, digest = fileHash(file);
  console.log(`Stored ${url}: ${size} bytes, SHA-256 ${digest}`);
  return { size, sha256: digest };
}
async function downloadBytes(url, { allowFileSources }) {
  if (url.startsWith('file://')) {
    invariant(allowFileSources === true, `Only HTTPS URLs are accepted: ${url}`);
    return fs.readFileSync(fileURLToPath(url));
  }
  invariant(url.startsWith('https://'), `Only HTTPS URLs are accepted: ${url}`);
  const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(NETWORK_TIMEOUT_MS) });
  invariant(response.ok, `${url} returned HTTP status ${response.status}.`);
  invariant(response.url.startsWith('https://'), `${url} redirected to a non-HTTPS URL: ${response.url}`);
  return Buffer.from(await response.arrayBuffer());
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
 * Download every source of a file-set corpus into a staging directory, check every pin and published digest,
 * extract the selected members in memory, and only then write the extracted files, the sources, and the record.
 * A failure leaves the existing sources, record, and extracted files unchanged.
 */
export async function fetchFileSet(root, id, { corporaDir, policy, rule, allowFileSources = false }) {
  invariant(rule, `No file-set rule exists for corpus ${id}.`);
  const recordFile = path.join(root, 'specs', 'snapshots', `${id}.json`);
  let previous = null;
  if (fs.existsSync(recordFile)) {
    previous = readJson(recordFile);
    validateFileSetRecord(previous, { allowFileSources });
    invariant(previous.corpus === id, `The record names corpus ${previous.corpus}, not ${id}.`);
  }
  const target = path.join(corporaDir, id), staging = path.join(corporaDir, `${id}.fetch`), old = path.join(corporaDir, `${id}.old`);
  fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  fs.mkdirSync(staging, { recursive: true });
  try {
    const sources = [], data = new Map();
    for (const s of rule.sources) {
      const file = path.join(staging, ...s.local.split('/'));
      const got = await download(s.url, file, { allowFileSources });
      invariant(s.size === null || s.size === got.size, `Source ${s.id} has ${got.size} bytes, not the expected ${s.size}.`);
      invariant(s.published_digest === null || s.published_digest === `sha256:${got.sha256}`,
        `Source ${s.id} does not match its published digest ${s.published_digest}: SHA-256 ${got.sha256}.`);
      const bytes = fs.readFileSync(file);
      if (s.git_blob !== null) {
        const blob = gitBlobId(bytes);
        invariant(blob === s.git_blob, `Source ${s.id} has Git blob ID ${blob}, not ${s.git_blob}.`);
      }
      const release = { ...s.release };
      if (release.repository !== null) {
        const commit = tagCommit(release.repository, release.tag);
        invariant(release.commit === null || release.commit === commit, `Tag ${release.tag} of ${release.repository} names ${commit}, not ${release.commit}.`);
        release.commit = commit;
      }
      const entry = { id: s.id, url: s.url, kind: s.kind, release, size: got.size, sha256: got.sha256, published_digest: s.published_digest,
        git_blob: s.git_blob, local_path: localPathOf(id, s.local) };
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
        const published = await downloadBytes(e.published_url, { allowFileSources });
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
    invariant(problems.length === 0, `The fetched file set ${id} does not match its pins, so the existing sources, record, and files stay:\n- ${problems.join('\n- ')}`);

    // Every check passed. Write the extracted files, then replace the sources, then write the record.
    for (const [p, bytes] of extracted) {
      const file = checkExtractionPath(root, p);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const tmp = `${file}.${crypto.randomUUID()}.tmp`;
      fs.writeFileSync(tmp, bytes, { flag: 'wx' });
      fs.renameSync(tmp, file);
    }
    fs.rmSync(old, { recursive: true, force: true, maxRetries: 3 });
    if (fs.existsSync(target)) fs.renameSync(target, old);
    try { fs.renameSync(staging, target); } catch (e) { if (fs.existsSync(old)) fs.renameSync(old, target); throw e; }
    fs.rmSync(old, { recursive: true, force: true, maxRetries: 3 });
    writeJson(recordFile, record);
    return { result: 'pass', corpus: id, kind: 'file-set', record: `specs/snapshots/${id}.json`, version: record.version,
      sources: sources.map(s => ({ id: s.id, size: s.size, sha256: s.sha256, release: s.release, inventory: s.inventory })),
      selected: selected.map(e => ({ path: e.path, size: e.size, sha256: e.sha256 })), source_listing_sha256: sourceListingDigest(record) };
  } catch (e) {
    fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
    throw e;
  }
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

/** Read every zip source of a record from the local sources. */
function loadZips(record, corporaDir, problems) {
  const zips = new Map();
  for (const s of record.sources.filter(x => x.kind === 'zip')) {
    const file = resolveLocal(corporaDir, s.local_path);
    if (!fs.existsSync(file)) { problems.push(`source ${s.id}: missing ${file}`); continue; }
    try { zips.set(s.id, readZip(fs.readFileSync(file))); } catch (e) { problems.push(`source ${s.id}: ${e.message}`); }
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
  const sourceBytes = new Map();
  for (const s of record.sources) {
    const file = resolveLocal(corporaDir, s.local_path);
    if (!fs.existsSync(file)) { problems.push(`source ${s.id}: missing ${file}`); continue; }
    const bytes = fs.readFileSync(file);
    expect(`source ${s.id} size`, s.size, bytes.length);
    expect(`source ${s.id} sha256`, s.sha256, sha256(bytes));
    if (s.git_blob !== null) expect(`source ${s.id} git_blob`, s.git_blob, gitBlobId(bytes));
    if (s.published_digest !== null) expect(`source ${s.id} published_digest`, s.published_digest, `sha256:${sha256(bytes)}`);
    sourceBytes.set(s.id, bytes);
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
/** The interpreter of the local fontTools environment under `.tools/python/`. */
export function toolPython(root, tool) {
  const dir = path.join(root, '.tools', 'python', `${tool.name.toLowerCase()}-${tool.version}`);
  return path.join(dir, ...(process.platform === 'win32' ? ['Scripts', 'python.exe'] : ['bin', 'python']));
}

/**
 * Run each declared derivation of a file-set corpus with its import tool, and record the result.
 * The output must equal any existing fixture byte for byte, so a rerun proves the derivation reproducible.
 */
export function deriveFileSet(root, id, { corporaDir, rule }) {
  invariant(rule && rule.derived.length > 0, `Corpus ${id} declares no derived files.`);
  const record = readFileSetRecord(root, id);
  const staging = path.join(corporaDir, `${id}.derive`);
  fs.rmSync(staging, { recursive: true, force: true, maxRetries: 3 });
  fs.mkdirSync(staging, { recursive: true });
  try {
    for (const spec of rule.derived) {
      const tool = importTool(root, spec.tool), python = toolPython(root, tool);
      invariant(fs.existsSync(python), `The ${tool.name} environment is missing: ${python}. Install it from the verified wheel.`);
      const probe = spawnSync(python, ['-c', 'import sys, fontTools; print(fontTools.version); print(sys.version.split()[0])'],
        { encoding: 'utf8', timeout: 60000, windowsHide: true });
      invariant(probe.status === 0, `${python} could not import ${tool.name}: ${probe.stderr}`);
      const [toolVersion, pythonVersion] = probe.stdout.trim().split(/\r?\n/);
      invariant(toolVersion === tool.version, `${python} has ${tool.name} ${toolVersion}, not ${tool.version}.`);
      const input = record.sources.find(s => s.id === spec.input);
      invariant(input, `Derived ${spec.path} names an unknown input source ${spec.input}.`);
      const inputFile = resolveLocal(corporaDir, input.local_path);
      const inputBytes = fs.readFileSync(inputFile);
      invariant(sha256(inputBytes) === input.sha256, `The local source ${input.id} differs from its record. Run corpus-fetch ${id}.`);
      const output = path.join(staging, path.posix.basename(spec.path));
      const argv = spec.argv.map(a => a.replaceAll(`${CORPORA_ROOT}/`, `${corporaDir}${path.sep}`.replaceAll('\\', '/')).replace('<output>', output));
      console.log(`Run ${JSON.stringify([python, ...argv])}`);
      const run = spawnSync(python, argv, { stdio: 'inherit', timeout: TOOL_TIMEOUT_MS, windowsHide: true });
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
