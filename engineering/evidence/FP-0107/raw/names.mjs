// FP-0107: the test-name comparison of raw/names.log.
// It reads the result lines of the recorded suite runs, prints the ordered names of the base suite and of the changed
// suite, and compares them. It exits with status 1 when a comparison fails.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raw = path.dirname(fileURLToPath(import.meta.url));
const names = log => fs.readFileSync(path.join(raw, log), 'utf8').split(/\r?\n/)
  .map(line => /^(?:not )?ok (\d+) - (.*)$/.exec(line)).filter(Boolean).map((m, i) => {
    if (Number(m[1]) !== i + 1) throw new Error(`${log}: result ${i + 1} has number ${m[1]}.`);
    return m[2];
  });
const base = names('profile-before.log'), changed = names('profile-after.log');
const NEW = ['FP-0107 case 1: the runner writes a duration line after each result line, the summary, the slowest cases, and the total',
  'FP-0107 case 2: the runner runs no case that declares a process-wide change while another case runs'];
base.forEach((name, i) => console.log(`BASE ${i + 1} ${name}`));
changed.forEach((name, i) => console.log(`CHANGED ${i + 1} ${name}`));
let failed = 0;
const same = (label, a, b) => {
  const equal = a.length === b.length && a.every((name, i) => name === b[i]);
  const first = a.findIndex((name, i) => name !== b[i]);
  console.log(`${equal ? 'EQUAL' : 'DIFFERENT'} ${label}: ${a.length} and ${b.length} names${equal ? '' : `, first difference at ${first + 1}`}`);
  if (!equal) failed++;
};
console.log(`COUNT base ${base.length}, changed ${changed.length}, unique changed ${new Set(changed).size}`);
same('the base names and the first names of the changed suite', base, changed.slice(0, base.length));
same('the names that the changed suite adds and the two FP-0107 cases', changed.slice(base.length), NEW);
same('the changed suite and the red baseline of raw/tests-before.log', changed, names('tests-before.log'));
same('the base suite on Windows and on WSL Ubuntu', base, names('profile-linux-before.log'));
same('the changed suite on Windows and on WSL Ubuntu', changed, names('profile-linux-after.log'));
if (new Set(changed).size !== changed.length) { console.log('DIFFERENT the changed suite repeats a name'); failed++; }
process.exitCode = failed ? 1 : 0;
