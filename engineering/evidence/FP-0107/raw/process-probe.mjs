// FP-0107: the child-process probe of raw/probe-process-starts.log.
// `node --import=<this file> tools/selftest.mjs` runs the before tree, whose runner runs one case at a time.
// The probe changes no case. It counts the child processes that each case starts through node:child_process,
// by program name, and sums the time that synchronous starts block the thread. After each `# duration_ms <n> <ms>`
// line, it prints `# probe <n> starts <count> sync_ms <ms> programs <name>=<count>,...` for the case on that line.
// The runner prints nothing between two result lines except while it runs the next case, so the counts belong to that case.
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import path from 'node:path';

delete process.env.NODE_OPTIONS;
let starts = 0, syncMs = 0, programs = new Map();
const note = file => {
  starts++;
  const name = path.basename(String(file)).toLowerCase().replace(/\.(exe|cmd|bat)$/, '');
  programs.set(name, (programs.get(name) ?? 0) + 1);
};
for (const name of ['spawn', 'execFile', 'exec', 'fork']) {
  const original = childProcess[name];
  childProcess[name] = function probed(file, ...rest) { note(name === 'fork' ? process.execPath : name === 'exec' ? String(file).split(' ')[0] : file); return original.call(this, file, ...rest); };
}
for (const name of ['spawnSync', 'execFileSync', 'execSync']) {
  const original = childProcess[name];
  childProcess[name] = function probed(file, ...rest) {
    note(name === 'execSync' ? String(file).split(' ')[0] : file);
    const started = performance.now();
    try { return original.call(this, file, ...rest); } finally { syncMs += performance.now() - started; }
  };
}
syncBuiltinESMExports();
const print = console.log;
console.log = (...args) => {
  print(...args);
  const m = /^# duration_ms (\d+) \d+$/.exec(String(args[0]));
  if (!m) return;
  const list = [...programs].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([k, v]) => `${k}=${v}`).join(',');
  print(`# probe ${m[1]} starts ${starts} sync_ms ${Math.floor(syncMs)} programs ${list || '-'}`);
  starts = 0; syncMs = 0; programs = new Map();
};
