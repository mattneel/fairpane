// FP-0107 revision 3: the median case cost of a set of suite runs.
// `node r3-cost.mjs [--top <k>] <log>...` reads each log, splits it into runs at each `TAP version 13` line, and keeps
// the runs that end with a `# duration_ms total` line. For each case number, it takes the median of the case's
// `# duration_ms` values over those runs, the mean of the two middle values for an even count, rounded down.
// It prints each run's total and sum of case durations, the sum of the medians, and the <k> cases with the largest
// medians (default 30), with their names.
import fs from 'node:fs';

const args = process.argv.slice(2);
let top = 30;
if (args[0] === '--top') { top = Number(args[1]); args.splice(0, 2); }
if (!args.length || !Number.isInteger(top) || top < 0) throw new Error('Usage: r3-cost.mjs [--top <k>] <log>...');
const runs = [];
for (const log of args) {
  let run = null;
  for (const line of fs.readFileSync(log, 'utf8').split(/\r?\n/)) {
    let m;
    if (line === 'TAP version 13') run = { log, ms: new Map(), names: new Map(), total: null };
    else if (!run) continue;
    else if ((m = /^(?:not )?ok (\d+) - (.*)$/.exec(line))) run.names.set(Number(m[1]), m[2]);
    else if ((m = /^# duration_ms total (\d+)$/.exec(line))) { run.total = Number(m[1]); runs.push(run); run = null; }
    else if ((m = /^# duration_ms (\d+) (\d+)$/.exec(line))) run.ms.set(Number(m[1]), Number(m[2]));
  }
}
if (!runs.length) throw new Error('No complete run.');
const count = runs[0].ms.size;
for (const run of runs) {
  const sum = [...run.ms.values()].reduce((a, b) => a + b, 0);
  console.log(`RUN ${run.log}: ${run.ms.size} cases, total ${run.total} ms, sum of case durations ${sum} ms`);
  if (run.ms.size !== count) throw new Error(`${run.log} has ${run.ms.size} cases, and the first run ${count}.`);
}
const median = values => {
  const v = [...values].sort((a, b) => a - b), h = v.length >> 1;
  return v.length % 2 ? v[h] : Math.floor((v[h - 1] + v[h]) / 2);
};
const medians = [...runs[0].ms.keys()].map(n => ({ n, ms: median(runs.map(r => r.ms.get(n))), name: runs[0].names.get(n) }));
console.log(`MEDIAN SUM ${medians.reduce((a, c) => a + c.ms, 0)} ms over ${runs.length} runs of ${count} cases`);
console.log(`MEDIAN TOTAL ${median(runs.map(r => r.total))} ms`);
medians.sort((a, b) => b.ms - a.ms || a.n - b.n).slice(0, top)
  .forEach((c, i) => console.log(`TOP ${i + 1} | case ${c.n} | ${c.ms} ms | ${c.name}`));
