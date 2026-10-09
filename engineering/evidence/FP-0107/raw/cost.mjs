// FP-0107: the cost summary of raw/cost.log.
// It reads the duration lines of the four profiles and the probe lines of raw/probe-process-starts.log, and prints
// the totals, the cost of the cases that start Git, and the ten slowest base cases on Windows with their probe counts.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raw = path.dirname(fileURLToPath(import.meta.url));
const lines = log => fs.readFileSync(path.join(raw, log), 'utf8').split(/\r?\n/);
function profile(log) {
  const ms = new Map(), names = new Map();
  let total = null;
  for (const line of lines(log)) {
    let m;
    if ((m = /^(?:not )?ok (\d+) - (.*)$/.exec(line))) names.set(Number(m[1]), m[2]);
    else if ((m = /^# duration_ms (\d+) (\d+)$/.exec(line))) ms.set(Number(m[1]), Number(m[2]));
    else if ((m = /^# duration_ms total (\d+)$/.exec(line))) total = Number(m[1]);
  }
  return { ms, names, total, sum: [...ms.values()].reduce((a, b) => a + b, 0) };
}
const before = profile('profile-before.log'), after = profile('profile-after.log');
const linuxBefore = profile('profile-linux-before.log'), linuxAfter = profile('profile-linux-after.log');
const probe = new Map();
for (const line of lines('probe-process-starts.log')) {
  const m = /^# probe (\d+) starts (\d+) sync_ms (\d+) programs (.*)$/.exec(line);
  if (!m) continue;
  const programs = new Map(m[4] === '-' ? [] : m[4].split(',').map(p => { const [k, v] = p.split('='); return [k, Number(v)]; }));
  probe.set(Number(m[1]), { starts: Number(m[2]), syncMs: Number(m[3]), programs, text: m[4] });
}
for (const [label, p] of [['windows before', before], ['windows after', after], ['linux before', linuxBefore], ['linux after', linuxAfter]])
  console.log(`PROFILE ${label}: ${p.ms.size} cases, total ${p.total} ms, sum of case durations ${p.sum} ms`);
if (probe.size !== before.ms.size) throw new Error(`The probe covers ${probe.size} cases, and the base profile ${before.ms.size}.`);
const sum = ns => ns.reduce((a, n) => a + before.ms.get(n), 0);
const all = [...probe.keys()], git = all.filter(n => probe.get(n).programs.has('git')), none = all.filter(n => probe.get(n).starts === 0);
const count = (ns, f) => ns.reduce((a, n) => a + f(probe.get(n)), 0);
console.log(`PROBE ${count(all, p => p.starts)} child processes, ${count(all, p => p.programs.get('git') ?? 0)} of them git, ${count(all, p => p.syncMs)} ms in synchronous calls`);
console.log(`GIT ${git.length} cases start git: ${sum(git)} of ${before.sum} ms in the Windows base profile (${(100 * sum(git) / before.sum).toFixed(1)}%)`);
console.log(`NONE ${none.length} cases start no child process: ${sum(none)} ms`);
for (const n of all.filter(n => probe.get(n).programs.has('powershell')))
  console.log(`LISTING ${n} ${before.ms.get(n)} ms ${before.names.get(n)}`);
const slowest = [...before.ms].sort((a, b) => b[1] - a[1] || a[0] - b[0]).slice(0, 10);
console.log('RANK | case | Windows before | Windows after | Linux before | Linux after | starts | sync ms | programs | name');
slowest.forEach(([n], i) => {
  const p = probe.get(n);
  console.log(`${i + 1} | ${n} | ${before.ms.get(n)} | ${after.ms.get(n)} | ${linuxBefore.ms.get(n)} | ${linuxAfter.ms.get(n)} | ${p.starts} | ${p.syncMs} | ${p.text} | ${before.names.get(n)}`);
});
