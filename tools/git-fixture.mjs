/**
 * The Git object builder of the controller-test fixtures. `writeFixtureTree` writes the blobs and trees of a fixture commit
 * with two Git processes: one `git hash-object --stdin-paths` for every blob and one `git mktree --batch` for every tree.
 * Both write loose objects, so a case can still read or replace an object file under `objects/`.
 */
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const NUL = Buffer.from([0]);

/** The components of the raw path `bytes`, split at each `/`. */
function splitPath(bytes) {
  const parts = [];
  for (let i = 0, start = 0; i <= bytes.length; i++) if (i === bytes.length || bytes[i] === 0x2f) { parts.push(bytes.subarray(start, i)); start = i + 1; }
  return parts;
}

/**
 * Add the trees of `entries` to `trees` with each subtree before its parent, and return the ID of the top tree.
 * An entry is `{ parts, mode, type, oid }` with its path components as buffers.
 * Each tree is `{ id, input }`: its object ID, computed here, and its `git mktree -z` input lines.
 * Git orders tree entries by name bytes, with a tree compared as if its name ended in `/`.
 */
function addTree(entries, trees) {
  const own = [], dirs = new Map();
  for (const e of entries) {
    if (e.parts.length === 1) { own.push({ name: e.parts[0], mode: e.mode, type: e.type, oid: e.oid }); continue; }
    const name = e.parts[0].toString('latin1');
    if (!dirs.has(name)) dirs.set(name, []);
    dirs.get(name).push({ ...e, parts: e.parts.slice(1) });
  }
  for (const [name, sub] of dirs) own.push({ name: Buffer.from(name, 'latin1'), mode: '040000', type: 'tree', oid: addTree(sub, trees) });
  const key = e => Buffer.concat([e.name, e.type === 'tree' ? Buffer.from('/') : NUL]);
  const body = Buffer.concat([...own].sort((a, b) => Buffer.compare(key(a), key(b)))
    .flatMap(e => [Buffer.from(`${Number.parseInt(e.mode, 8).toString(8)} `), e.name, NUL, Buffer.from(e.oid, 'hex')]));
  const id = crypto.createHash('sha1').update(`tree ${body.length}\0`).update(body).digest('hex');
  trees.push({ id, input: Buffer.concat(own.map(e => Buffer.concat([Buffer.from(`${e.mode} ${e.type} ${e.oid}\t`), e.name, NUL]))) });
  return id;
}

/**
 * Write the blobs and trees of `files` into the repository in which `git(args, input)` runs Git, and return
 * `{ tree, blob }`: the root tree ID and a function that returns the blob or submodule commit ID of a file path.
 * `git` returns Git's standard output as a latin1 string without surrounding white space, and throws when Git fails.
 * Files: `{ path, text, mode }` for blobs and symbolic links, or `{ path, submodule }` for a submodule commit, where a path
 * is a string or a buffer of raw bytes. `git mktree` must report the tree IDs computed here, so Git checks each one.
 */
export function writeFixtureTree(git, files) {
  const blobs = files.filter(f => f.submodule === undefined);
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-blobs-'));
  let ids;
  try {
    const paths = blobs.map((f, i) => { const file = path.join(scratch, String(i)); fs.writeFileSync(file, Buffer.from(f.text)); return file; });
    ids = paths.length ? git(['hash-object', '-w', '--no-filters', '--stdin-paths'], `${paths.join('\n')}\n`).split('\n') : [];
  } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
  if (ids.length !== blobs.length) throw new Error(`git hash-object wrote ${ids.length} blobs, not ${blobs.length}.`);
  const oids = new Map(blobs.map((f, i) => [f, ids[i]]));
  const entries = files.map(f => ({ parts: splitPath(Buffer.from(f.path)), mode: f.submodule ? '160000' : f.mode ?? '100644',
    type: f.submodule ? 'commit' : 'blob', oid: f.submodule ?? oids.get(f) }));
  const trees = [], tree = addTree(entries, trees);
  const missing = files.some(f => f.submodule) ? ['--missing'] : [];
  const written = git(['mktree', '-z', '--batch', ...missing], Buffer.concat(trees.flatMap(t => [t.input, NUL]))).split('\n');
  const expected = trees.map(t => t.id);
  if (written.join(' ') !== expected.join(' ')) throw new Error(`git mktree wrote ${written.join(' ')}, not ${expected.join(' ')}.`);
  const byPath = new Map(files.map((f, i) => [Buffer.from(f.path).toString('latin1'), entries[i].oid]));
  return { tree, blob: p => byPath.get(Buffer.from(p).toString('latin1')) };
}
