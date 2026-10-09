// FP-0107: the mutation step of raw/mutation.log.
// `node mutate.mjs <file> <keep-dir> <from> <to> [<from> <to>]...` copies <file> into the absent file
// <keep-dir>/<basename>, then replaces each <from>, which must occur exactly once, with <to>.
import fs from 'node:fs';
import path from 'node:path';

const [file, keepDir, ...pairs] = process.argv.slice(2);
if (!file || !keepDir || pairs.length === 0 || pairs.length % 2) throw new Error('Usage: mutate.mjs <file> <keep-dir> <from> <to> [<from> <to>]...');
let text = fs.readFileSync(file, 'utf8');
for (let i = 0; i < pairs.length; i += 2) {
  const [from, to] = [pairs[i], pairs[i + 1]], sites = text.split(from).length - 1;
  if (sites !== 1) throw new Error(`Expected one occurrence of ${JSON.stringify(from)}, found ${sites}.`);
  text = text.replace(from, () => to);
}
const keep = path.join(keepDir, path.basename(file));
fs.mkdirSync(keepDir, { recursive: true });
fs.copyFileSync(file, keep, fs.constants.COPYFILE_EXCL);
fs.writeFileSync(file, text);
console.log(`kept ${keep}; replaced ${pairs.length / 2} site(s) in ${file}`);
