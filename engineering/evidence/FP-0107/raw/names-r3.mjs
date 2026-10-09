// FP-0107 revision 3: the case-name comparison of raw/names-r3.log.
// The base suite is the run in raw/probe-before-r3.log, which ran the unchanged base. Each other run must list the base
// names in order, followed by revision 3's case 4 and nothing else. It prints the ordered names of the base suite and of
// the changed suite, then one line per compared run, and exits with status 1 when a comparison fails.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raw = path.dirname(fileURLToPath(import.meta.url));
const CASE_4 = 'FP-0107 revision 3 case 4: each changed Git fixture builder writes the objects of the base builder for a fixed input';
/** The ordered result names of each run in `log`, where a run starts at `TAP version 13`. */
function runs(log) {
  const found = [];
  for (const line of fs.readFileSync(path.join(raw, log), 'utf8').split(/\r?\n/)) {
    if (line === 'TAP version 13') { found.push([]); continue; }
    const m = /^(?:not )?ok (\d+) - (.*)$/.exec(line);
    if (!m || !found.length) continue;
    const names = found.at(-1);
    if (Number(m[1]) !== names.length + 1) throw new Error(`${log}: result ${names.length + 1} has number ${m[1]}.`);
    names.push(m[2]);
  }
  return found;
}
const [base] = runs('probe-before-r3.log'), changed = [...base, CASE_4];
base.forEach((name, i) => console.log(`BASE ${i + 1} ${name}`));
changed.forEach((name, i) => console.log(`CHANGED ${i + 1} ${name}`));
let failed = 0;
for (const log of ['tests-before-r3.log', 'profile-before-r3.log', 'probe-after-r3.log', 'profile-after-r3.log', 'profile-linux-after-r3.log']) {
  runs(log).forEach((names, i) => {
    const equal = names.length === changed.length && names.every((name, j) => name === changed[j]);
    const first = names.findIndex((name, j) => name !== changed[j]);
    console.log(`${equal ? 'EQUAL' : 'DIFFERENT'} ${log} run ${i + 1}: ${names.length} names${equal ? '' : `, first difference at ${first + 1}`}`);
    if (!equal) failed++;
  });
}
if (new Set(changed).size !== changed.length) { console.log('DIFFERENT the changed suite repeats a name'); failed++; }
console.log(`COUNT base ${base.length}, changed ${changed.length}; the changed suite adds only case 4`);
process.exitCode = failed ? 1 : 0;
