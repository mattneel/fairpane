// FP-0011 revision 1 measurement summary. Run from the repository root: node engineering/evidence/FP-0011/raw/measure-summary-r1.mjs
// The statistics and separability rules repeat raw/measure-summary.log, the method of the original runs.
// The level-shift report is new: contract revision 1 requires section 5 of ADR 0008 to state any shift of
// sample level within a run that decides a separability outcome.
import fs from 'node:fs';

const dir = 'engineering/evidence/FP-0011/raw';
const reps = ['reference', 'nan_box', 'tagged_index'];
const runs = ['run1', 'run2'];
const workloads = ['add-small-int', 'add-fraction', 'get-prototype-chain', 'number-to-string', 'object-churn', 'mark-generated', 'mark-manual'];
const expected = { 'add-small-int': '"1000000"', 'add-fraction': '"500000"', 'get-prototype-chain': '"7000000"', 'number-to-string': '788890', 'object-churn': '6250', 'mark-generated': '100000', 'mark-manual': '100000' };

const data = {};
for (const r of reps) for (const run of runs) {
  const text = fs.readFileSync(`${dir}/measure-${r}-r1-${run}.log`, 'utf8');
  const lines = text.split(/\r?\n/).filter(l => l.startsWith('{'));
  const header = JSON.parse(lines[0]);
  const samples = lines.slice(1).map(l => JSON.parse(l));
  const result = JSON.parse(text.split(/\r?\n/).find(l => l.startsWith('RESULT ')).slice(7));
  data[`${r}/${run}`] = { header, samples, exit: result.exit_code, started: result.started_at };
}

const stats = {}, series = {};
for (const key of Object.keys(data)) {
  const d = data[key];
  console.log(`HEADER ${key} exit=${d.exit} started=${d.started} ${JSON.stringify(d.header)}`);
  for (const w of workloads) {
    const measured = d.samples.filter(s => s.workload === w && !s.warmup).sort((a, b) => a.sample - b.sample);
    const ns = measured.map(s => s.ns).sort((a, b) => a - b);
    const checksums = [...new Set(d.samples.filter(s => s.workload === w).map(s => JSON.stringify(s.checksum)))];
    const peak = [...new Set(measured.map(s => s.peak_live_bytes))];
    const cells = [...new Set(measured.map(s => s.cells_allocated))];
    const collections = [...new Set(measured.map(s => s.collections))];
    stats[`${key}/${w}`] = { min: ns[0], median: ns[5], max: ns[10] };
    series[`${key}/${w}`] = measured.map(s => s.ns);
    const ok = checksums.length === 1 && checksums[0] === expected[w];
    console.log(`STATS ${key} ${w} n=${ns.length} min=${ns[0]} median=${ns[5]} max=${ns[10]} checksums=${checksums.join(',')} checksum_ok=${ok} peak_live_bytes=${peak.join(',')} cells_allocated=${cells.join(',')} collections=${collections.join(',')}`);
  }
}

// A level shift is a split of a run's 11 measured samples, in sample order, into a nonempty prefix and suffix
// whose ranges do not overlap and whose medians differ by a factor of at least 1.5.
function median(xs) { const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; }
const shifts = {};
for (const [key, xs] of Object.entries(series)) {
  console.log(`SERIES ${key} ${xs.join(' ')}`);
  for (let k = 1; k < xs.length; k++) {
    const a = xs.slice(0, k), b = xs.slice(k);
    const disjoint = Math.max(...a) < Math.min(...b) || Math.min(...a) > Math.max(...b);
    const ratio = Math.max(median(a), median(b)) / Math.min(median(a), median(b));
    if (disjoint && ratio >= 1.5) {
      (shifts[key] ??= []).push({ at: k, before: median(a), after: median(b), ratio: Number(ratio.toFixed(2)) });
    }
  }
}
for (const [key, list] of Object.entries(shifts)) for (const s of list) console.log(`SHIFT ${key} before sample ${s.at + 1}: median ${s.before} then ${s.after}, ratio ${s.ratio}`);
if (!Object.keys(shifts).length) console.log('SHIFT none');

function verdictOf(x, y) { return x.max < y.min ? 'faster' : y.max < x.min ? 'slower' : 'overlap'; }
function combine(v) { return v[0] === v[1] && v[0] !== 'overlap' ? v[0] : `not separable (${v.join('/')})`; }
function involvedShifts(keys) { return keys.filter(k => shifts[k]).map(k => `${k} at sample ${shifts[k].map(s => s.at + 1).join(',')}`); }
const six = workloads.slice(0, 6);
for (const [a, b] of [['nan_box', 'reference'], ['tagged_index', 'reference'], ['nan_box', 'tagged_index']]) {
  for (const w of six) {
    const v = runs.map(run => verdictOf(stats[`${a}/${run}/${w}`], stats[`${b}/${run}/${w}`]));
    const involved = involvedShifts(runs.flatMap(run => [`${a}/${run}/${w}`, `${b}/${run}/${w}`]));
    console.log(`PAIR ${a} vs ${b} ${w}: ${a} ${combine(v)}${involved.length ? ` | shifts: ${involved.join('; ')}` : ''}`);
  }
}
for (const r of reps) {
  const v = runs.map(run => verdictOf(stats[`${r}/${run}/mark-generated`], stats[`${r}/${run}/mark-manual`]));
  const involved = involvedShifts(runs.flatMap(run => [`${r}/${run}/mark-generated`, `${r}/${run}/mark-manual`]));
  console.log(`TRACER ${r} mark-generated vs mark-manual: generated ${combine(v)}${involved.length ? ` | shifts: ${involved.join('; ')}` : ''}`);
}
