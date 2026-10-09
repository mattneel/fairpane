// FP-0107 revision 3: the child-process comparison of raw/cost-r3.log.
// It reads the `# probe <n>` lines of raw/probe-before-r3.log (the base, 253 cases) and raw/probe-after-r3.log (the
// changed suite, 254 cases), and prints the starts of the cases that both suites run, by program and by calling file,
// then case 4's starts, then every case whose count changed, with its name.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raw = path.dirname(fileURLToPath(import.meta.url));
function probe(log) {
  const cases = new Map(), names = new Map();
  for (const line of fs.readFileSync(path.join(raw, log), 'utf8').split(/\r?\n/)) {
    let m = /^(?:not )?ok (\d+) - (.*)$/.exec(line);
    if (m) { names.set(Number(m[1]), m[2]); continue; }
    m = /^# probe (\d+) starts (\d+) sync_ms (\d+) programs (\S+) callers (\S+)$/.exec(line);
    if (!m) continue;
    const map = text => new Map(text === '-' ? [] : text.split(',').map(p => { const [k, v] = p.split('='); return [k, Number(v)]; }));
    cases.set(Number(m[1]), { starts: Number(m[2]), syncMs: Number(m[3]), programs: map(m[4]), callers: map(m[5]) });
  }
  return { cases, names };
}
const before = probe('probe-before-r3.log'), after = probe('probe-after-r3.log');
const common = [...before.cases.keys()].filter(n => after.cases.has(n));
for (const n of common) if (before.names.get(n) !== after.names.get(n)) throw new Error(`Case ${n} has another name after the change.`);
const sum = (p, ns, f) => ns.reduce((a, n) => a + f(p.cases.get(n)), 0);
const keys = (field, ...ps) => [...new Set(ps.flatMap(p => [...p.cases.values()].flatMap(c => [...c[field].keys()])))].sort();
console.log(`CASES before ${before.cases.size}, after ${after.cases.size}, common ${common.length}`);
const report = (label, ns) => {
  const b = sum(before, ns, c => c.starts), a = sum(after, ns, c => c.starts);
  console.log(`STARTS ${label}: before ${b}, after ${a}, change ${a - b} (${(100 * (a - b) / b).toFixed(1)}%)`);
};
report('common cases', common);
console.log(`SYNC_MS common cases: before ${sum(before, common, c => c.syncMs)}, after ${sum(after, common, c => c.syncMs)}`);
for (const field of ['programs', 'callers'])
  for (const k of keys(field, before, after))
    console.log(`${field.toUpperCase()} ${k}: before ${sum(before, common, c => c[field].get(k) || 0)}, after ${sum(after, common, c => c[field].get(k) || 0)}`);
for (const n of [...after.cases.keys()].filter(n => !before.cases.has(n))) {
  const c = after.cases.get(n);
  console.log(`ADDED ${n} starts ${c.starts} callers ${[...c.callers].map(([k, v]) => `${k}=${v}`).join(',')} | ${after.names.get(n)}`);
}
console.log(`TOTAL all cases: before ${sum(before, [...before.cases.keys()], c => c.starts)}, after ${sum(after, [...after.cases.keys()], c => c.starts)}`);
console.log('CHANGED case | before | after | before callers | after callers | name');
for (const n of common) {
  const b = before.cases.get(n), a = after.cases.get(n);
  if (b.starts === a.starts) continue;
  const text = c => [...c.callers].map(([k, v]) => `${k}=${v}`).join(',');
  console.log(`CHANGED ${n} | ${b.starts} | ${a.starts} | ${text(b)} | ${text(a)} | ${before.names.get(n)}`);
}
