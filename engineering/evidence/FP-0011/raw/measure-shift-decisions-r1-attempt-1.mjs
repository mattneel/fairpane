// FP-0011 revision 1: which level shifts decide a separability outcome.
// Run from the repository root: node engineering/evidence/FP-0011/raw/measure-shift-decisions-r1.mjs
// It reads the same six run logs and uses the same rules as measure-summary-r1.mjs.
// A level shift splits a run's 11 measured samples, in sample order, into a prefix and a suffix whose ranges do not
// overlap and whose medians differ by a factor of at least 1.5. The shift decides a comparison's outcome when keeping
// only the prefix, or only the suffix, as that run's samples changes the two-run verdict.
import fs from 'node:fs';

const dir = 'engineering/evidence/FP-0011/raw';
const reps = ['reference', 'nan_box', 'tagged_index'];
const runs = ['run1', 'run2'];
const workloads = ['add-small-int', 'add-fraction', 'get-prototype-chain', 'number-to-string', 'object-churn', 'mark-generated', 'mark-manual'];

const series = {};
for (const r of reps) for (const run of runs) {
  const samples = fs.readFileSync(`${dir}/measure-${r}-r1-${run}.log`, 'utf8').split(/\r?\n/)
    .filter(l => l.startsWith('{')).slice(1).map(l => JSON.parse(l));
  for (const w of workloads) {
    series[`${r}/${run}/${w}`] = samples.filter(s => s.workload === w && !s.warmup).sort((a, b) => a.sample - b.sample).map(s => s.ns);
  }
}

function median(xs) { const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; }
function shiftsOf(xs) {
  const found = [];
  for (let k = 1; k < xs.length; k++) {
    const a = xs.slice(0, k), b = xs.slice(k);
    const disjoint = Math.max(...a) < Math.min(...b) || Math.min(...a) > Math.max(...b);
    const ratio = Math.max(median(a), median(b)) / Math.min(median(a), median(b));
    if (disjoint && ratio >= 1.5) found.push(k);
  }
  return found;
}
const range = xs => ({ min: Math.min(...xs), max: Math.max(...xs) });
function verdict(x, y) { return x.max < y.min ? 'faster' : y.max < x.min ? 'slower' : 'overlap'; }
function combine(v) { return v[0] === v[1] && v[0] !== 'overlap' ? v[0] : `not separable (${v.join('/')})`; }
function outcome(aKey, bKey, override) {
  return combine(runs.map(run => {
    const ka = aKey(run), kb = bKey(run);
    return verdict(range(override[ka] ?? series[ka]), range(override[kb] ?? series[kb]));
  }));
}

const comparisons = [];
for (const [a, b] of [['nan_box', 'reference'], ['tagged_index', 'reference'], ['nan_box', 'tagged_index']]) {
  for (const w of workloads.slice(0, 6)) comparisons.push({ name: `PAIR ${a} vs ${b} ${w}`, a: run => `${a}/${run}/${w}`, b: run => `${b}/${run}/${w}` });
}
for (const r of reps) comparisons.push({ name: `TRACER ${r} mark-generated vs mark-manual`, a: run => `${r}/${run}/mark-generated`, b: run => `${r}/${run}/mark-manual` });

for (const [key, xs] of Object.entries(series)) {
  const ks = shiftsOf(xs);
  if (ks.length) console.log(`SERIES ${key} ${xs.join(' ')} | shifts before sample ${ks.map(k => k + 1).join(',')}`);
}
for (const c of comparisons) {
  const actual = outcome(c.a, c.b, {});
  const keys = runs.flatMap(run => [c.a(run), c.b(run)]);
  const notes = [];
  for (const key of keys) {
    for (const k of shiftsOf(series[key])) {
      const prefix = outcome(c.a, c.b, { [key]: series[key].slice(0, k) });
      const suffix = outcome(c.a, c.b, { [key]: series[key].slice(k) });
      const decides = prefix !== actual || suffix !== actual;
      notes.push(`${key} shift before sample ${k + 1}: samples 1-${k} only gives ${prefix}; samples ${k + 1}-11 only gives ${suffix}; ${decides ? 'DECIDES' : 'does not decide'}`);
    }
  }
  console.log(`${c.name}: ${actual}${notes.length ? `\n  ${notes.join('\n  ')}` : ''}`);
}
