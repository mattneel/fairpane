// FP-0082 revision 2 case 3: deletes the cache manifests of the two census steps of case 17 in `<cache>/h/` and keeps
// their outputs, as an interrupted run that wrote census.jsonl but no manifest leaves the cache.
// A manifest belongs to a census step when its bytes name the sound fixture's EXTRACT.json and not the refusal step's
// existing.jsonl. Exactly two manifests must match.
import fs from 'node:fs';
import path from 'node:path';

const [cache] = process.argv.slice(2);
if (!cache) throw new Error('Usage: node delete-census-manifests-r2.mjs <cache-dir>');
const sound = path.join('tests', 'js', 'census', 'sound', 'EXTRACT.json');
const manifests = path.join(cache, 'h');
let removed = 0;
for (const name of fs.readdirSync(manifests).sort()) {
  const file = path.join(manifests, name);
  if (!fs.statSync(file).isFile()) continue;
  const text = fs.readFileSync(file).toString('latin1');
  if (!text.includes(sound) || text.includes('existing.jsonl')) continue;
  fs.rmSync(file);
  console.log(`removed manifest ${name}`);
  removed += 1;
}
for (const name of fs.readdirSync(path.join(cache, 'o')).sort()) {
  for (const step of ['census-sound', 'census-unsound']) {
    const output = path.join(cache, 'o', name, step, 'census.jsonl');
    if (fs.existsSync(output)) console.log(`kept output o/${name}/${step}/census.jsonl, ${fs.statSync(output).size} bytes`);
  }
}
console.log(`removed ${removed} manifests`);
if (removed !== 2) process.exitCode = 1;
