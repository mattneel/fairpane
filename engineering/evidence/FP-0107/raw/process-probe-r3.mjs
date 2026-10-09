// FP-0107 revision 3: the child-process probe of raw/probe-before-r3.log and raw/probe-after-r3.log.
// It counts what raw/process-probe.mjs counts, the child processes that each case starts through node:child_process by
// program name and the time that synchronous starts block their thread, for the runner of revision 1, which runs
// ordinary cases on worker threads. `node --import=<this file> tools/selftest.mjs` loads it on the main thread and,
// through the inherited execArgv, on each worker thread before the suite module.
//
// A worker resets its counts when the main thread asks it to run a case, and writes them into the case's slot of a
// SharedArrayBuffer before it posts the case's result, so the main thread can read them when it prints the case's
// `# duration_ms <n> <ms>` line. A case that declares `processWide` runs alone on the main thread, so the main thread's
// counts since the previous duration line belong to the case on the line. After each duration line, the probe prints
// `# probe <n> starts <count> sync_ms <ms> programs <name>=<count>,... callers <file>=<count>,...`, where a caller is
// the file of the first stack frame outside node: internals and this probe. After the total line, it prints the
// starts outside any case and the totals. The probe changes no case.
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getEnvironmentData, isMainThread, parentPort, setEnvironmentData } from 'node:worker_threads';

const SLOTS = 4096, SLOT_BYTES = 4096, KEY = 'fairpane-fp0107-r3-probe';
const self = fileURLToPath(import.meta.url);
delete process.env.NODE_OPTIONS;
let shared;
if (isMainThread) { shared = new SharedArrayBuffer(SLOTS * SLOT_BYTES + 8); setEnvironmentData(KEY, shared); }
else shared = getEnvironmentData(KEY);
const lengths = new Int32Array(shared, 0, SLOTS), unassigned = new Int32Array(shared, SLOTS * 4, 1);
const bytes = new Uint8Array(shared, SLOTS * 4 + 8);
const PAYLOAD = SLOT_BYTES - 4;

let counts = fresh();
function fresh() { return { starts: 0, syncMs: 0, programs: new Map(), callers: new Map() }; }
const bump = (map, key, n = 1) => map.set(key, (map.get(key) ?? 0) + n);
function caller() {
  for (const line of String(new Error().stack).split('\n').slice(1)) {
    const m = /\(?((?:file:\/\/)?[^\s()]+?):\d+:\d+\)?$/.exec(line.trim());
    if (!m || m[1].startsWith('node:')) continue;
    const file = m[1].startsWith('file://') ? fileURLToPath(m[1]) : m[1];
    if (path.resolve(file) !== self) return path.basename(file);
  }
  return '-';
}
const note = file => {
  counts.starts++;
  bump(counts.programs, path.basename(String(file)).toLowerCase().replace(/\.(exe|cmd|bat)$/, ''));
  bump(counts.callers, caller());
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
    try { return original.call(this, file, ...rest); } finally { counts.syncMs += performance.now() - started; }
  };
}
syncBuiltinESMExports();

const encode = c => JSON.stringify({ starts: c.starts, syncMs: c.syncMs, programs: [...c.programs], callers: [...c.callers] });
const merge = (into, c) => {
  into.starts += c.starts; into.syncMs += c.syncMs;
  for (const [k, v] of c.programs) bump(into.programs, k, v);
  for (const [k, v] of c.callers) bump(into.callers, k, v);
};
const list = map => [...map].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([k, v]) => `${k}=${v}`).join(',') || '-';
const line = (label, c) => `# probe ${label} starts ${c.starts} sync_ms ${Math.floor(c.syncMs)} programs ${list(c.programs)} callers ${list(c.callers)}`;

if (!isMainThread && parentPort) {
  let current = null;
  // Registered before the suite's own listener, so the counts restart before the case runs.
  parentPort.on('message', message => {
    if (message?.type !== 'run') return;
    if (current === null && counts.starts) Atomics.add(unassigned, 0, counts.starts);
    current = message.index; counts = fresh();
  });
  const post = parentPort.postMessage.bind(parentPort);
  parentPort.postMessage = message => {
    if (current !== null && message && 'failed' in message) {
      const data = Buffer.from(encode(counts));
      if (current >= SLOTS || data.length > PAYLOAD) throw new Error(`The probe cannot store case ${current + 1}.`);
      bytes.set(data, current * SLOT_BYTES);
      Atomics.store(lengths, current, data.length);
      counts = fresh();
    }
    return post(message);
  };
} else {
  const print = console.log, total = fresh();
  let outside = 0;
  console.log = (...args) => {
    print(...args);
    const text = String(args[0]);
    if (text === 'TAP version 13') { outside += counts.starts; counts = fresh(); return; }
    let m = /^# duration_ms (\d+) \d+$/.exec(text);
    if (m) {
      const n = Number(m[1]), stored = Atomics.load(lengths, n - 1);
      if (stored > 0) {
        const c = JSON.parse(Buffer.from(bytes.subarray((n - 1) * SLOT_BYTES, (n - 1) * SLOT_BYTES + stored)).toString('utf8'));
        merge(counts, { ...c, programs: new Map(c.programs), callers: new Map(c.callers) });
      }
      print(line(n, counts)); merge(total, counts); counts = fresh();
      return;
    }
    if (/^# duration_ms total \d+$/.test(text)) {
      print(`# probe outside starts ${outside + Atomics.load(unassigned, 0)}`);
      print(line('total', total));
    }
  };
}
