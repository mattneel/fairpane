#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { readJson, checkRepository, readyTasks, qualificationProblems, fingerprints,
  validateReceipt, runGate, installZig, compilerPath, checkCompiler } from './lib.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [command = 'help', ...args] = process.argv.slice(2);
const output = value => console.log(JSON.stringify(value, null, 2));
const load = name => readJson(path.join(root, name));
function versionOf(executable, argv = ['--version']) {
  const r = spawnSync(executable, argv, { encoding: 'utf8', timeout: 15000, windowsHide: true });
  return r.error || r.status !== 0 ? { available: false, error: r.error?.code ?? `exit ${r.status}` } :
    { available: true, version: (r.stdout || r.stderr).trim().split(/\r?\n/)[0] };
}
function help() {
  console.log(`Fairpane development controller

  doctor                      Report the actual local environment.
  check                       Check bootstrap repository integrity.
  test                        Run the controller tests.
  status                      Report task and capability status.
  next                        Print ready task contracts.
  fingerprint                 Hash current source and policy inputs.
  install-zig                 Install the exact locked compiler locally.
  run <gate-id>               Execute a gate and write a local receipt.
  evidence-check <path>       Check a receipt against current inputs.
  release-check               Check release prerequisites and fail closed.
  help                        Print these commands.

No command publishes, purchases, pushes, or grants tool approvals.
Local receipts are unsigned integrity records, not release attestations.`);
}
try {
  if (command === 'help') help();
  else if (command === 'doctor') {
    let compiler;
    try { compiler = { available: true, path: checkCompiler(root), version: load('toolchains/zig.lock.json').version }; }
    catch (e) { compiler = { available: false, error: e.message, expected_path: compilerPath(root) }; }
    output({ platform: process.platform, architecture: process.arch, runtime: process.version,
      bun: process.versions.bun ?? null, git: versionOf('git'),
      omp: versionOf(process.platform === 'win32' ? 'omp.exe' : 'omp'), compiler,
      git_checkout: fs.existsSync(path.join(root, '.git')),
      note: 'No conformance test ran. On Windows, check an OMP shell shim with omp --version in PowerShell.' });
  } else if (command === 'check') output(checkRepository(root));
  else if (command === 'test') {
    const r = spawnSync(process.execPath, [path.join(root, 'tools/selftest.mjs')], { cwd: root, stdio: 'inherit' });
    if (r.error) throw r.error; process.exitCode = r.status ?? 1;
  } else if (command === 'status') {
    const plan = load('engineering/plan.json'), state = load('engineering/state.json'), profile = load('engineering/qualification.json');
    output({ stage: state.stage, profile_state: profile.profile_state,
      tasks: plan.tasks.map(t => ({ id: t.id, title: t.title, status: state.tasks[t.id]?.status ?? 'missing' })),
      capabilities: profile.capabilities.map(c => ({ id: c.id, status: c.status })),
      browser_complete: false, note: 'The bootstrap has no independent release verifier.' });
  } else if (command === 'next') {
    checkRepository(root);
    const plan = load('engineering/plan.json'), state = load('engineering/state.json');
    const active = plan.tasks.filter(t => state.tasks[t.id].status === 'active'), ready = readyTasks(plan, state);
    output({ active, ready, instruction: ready.length || active.length ?
      'Complete or resume an authorized task. Freeze exact tests before implementation.' :
      'Resolve blockers or decompose the next workstream. An empty frontier does not mean completion.' });
  } else if (command === 'fingerprint') output(fingerprints(root));
  else if (command === 'install-zig') output(await installZig(root));
  else if (command === 'run') {
    if (args.length !== 1) throw new Error('Usage: run <gate-id>');
    console.log(`Execute gate ${args[0]}.`);
    const r = await runGate(root, args[0]);
    output({ gate: r.gate_id, status: r.status, receipt: r.receipt_path, error: r.error });
    process.exitCode = r.status === 'pass' ? 0 : 1;
  } else if (command === 'evidence-check') {
    if (args.length !== 1) throw new Error('Usage: evidence-check <repository-relative-path>');
    output(validateReceipt(root, args[0]));
  } else if (command === 'release-check') {
    output({ result: 'not-qualified', problems: qualificationProblems(load('engineering/qualification.json')), browser_complete: false });
    process.exitCode = 1;
  } else throw new Error(`Unknown command: ${command}. Run help for supported commands.`);
} catch (e) { console.error(`Fairpane: ${e.message}`); process.exitCode = 1; }
