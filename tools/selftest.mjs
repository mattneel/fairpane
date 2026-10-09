#!/usr/bin/env node
/** Controller tests only. These tests do not qualify browser behavior. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { isMainThread } from 'node:worker_threads';
import {
  readJson, writeJson, sha256, fileHash, safePath, collectFiles, hashInputs,
  validateLock, hostPlatform, verifyArchive, validatePlan, readyTasks,
  qualificationProblems, checkRepository, validateReceipt, runProcess, runGate,
  resolveExecutable, recordCommand, gateEnvironment, REQUIRED_CAPABILITIES, fingerprints,
} from './lib.mjs';
import {
  listTree, computeInventory, buildSnapshotRecord, validateSnapshotRecord, validateApplicability,
  verifyCorpus, classifyCorpus, snapshotGitDir, test262Applicability,
} from './corpus.mjs';
import * as corpus from './corpus.mjs';
// FP-0052 functions are read through the namespace, so a missing export fails only the case that uses it.
import * as lib from './lib.mjs';
import { attestationCases, removeAttestationFixtures } from './attest.test.mjs';
import { workflowCases } from './workflow-check.test.mjs';
import { abiCases, removeAbiFixtures } from './abi.test.mjs';
import { releaseCases, removeReleaseFixtures } from './release.test.mjs';
import { ucdCases, removeUcdFixtures } from './ucd.test.mjs';
import { fileSetCases, removeFileSetFixtures } from './fileset.test.mjs';
import { rustCases, removeRustFixtures } from './rust.test.mjs';
import { FILE_SET_IDS } from './fileset.mjs';
import { casePool, runCases, serveCases } from './test-runner.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cases = [], temporary = [];
/** Register a case. `processWide` names the process-wide state that the case changes, so the runner runs it alone. */
function test(name, fn, { processWide } = {}) { cases.push(processWide === undefined ? { name, fn } : { name, fn, processWide }); }
function temp() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-controller-'));
  temporary.push(dir); return dir;
}
function put(dir, relative, text) {
  const file = path.join(dir, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text);
  return file;
}
const clone = value => JSON.parse(JSON.stringify(value));
const lock = () => readJson(path.join(root, 'toolchains/zig.lock.json'));
function planFixture() {
  const make = (id, deps) => ({ id, title: id, depends_on: deps, workstream: 'core',
    acceptance: ['Run a nonempty fixture.'], allowed_paths: ['src'], required_gates: ['unit'] });
  return { plan: { schema_version: 1, tasks: [make('FP-0001', []), make('FP-0002', ['FP-0001'])] },
    state: { schema_version: 1, tasks: { 'FP-0001': { status: 'planned', evidence: [] }, 'FP-0002': { status: 'planned', evidence: [] } } } };
}
function validPlan(f) { return validatePlan(f.plan, f.state, new Set(['unit']), new Set(['core'])); }
function gateFixture(script = 'console.log("Fixture command ran.");', kind = 'controller-check') {
  const dir = temp();
  put(dir, 'input.txt', 'stable source\n');
  put(dir, 'tools/fairpane.mjs', script);
  writeJson(path.join(dir, 'engineering/policy.json'), { schema_version: 1,
    source_roots: ['input.txt', 'tools', 'engineering/gates.json', 'engineering/policy.json'],
    policy_roots: ['engineering/gates.json', 'engineering/policy.json'],
    allowed_evidence_roots: ['out/evidence', 'engineering/evidence'] });
  writeJson(path.join(dir, 'engineering/gates.json'), { schema_version: 1,
    gates: [{ id: 'fixture', kind, timeout_ms: 2000, args: ['build', 'test'] }] });
  if (kind === 'zig') writeJson(path.join(dir, 'toolchains/zig.lock.json'), lock());
  return dir;
}
async function goodReceipt() {
  const dir = gateFixture(); const receipt = await runGate(dir, 'fixture');
  assert.equal(receipt.status, 'pass');
  return { dir, receipt, file: path.join(dir, receipt.receipt_path) };
}

// Paths and inventories.
test('A normal relative file resolves within the repository', () => {
  const dir = temp(); const file = put(dir, 'src/a.txt', 'a'); assert.equal(safePath(dir, 'src/a.txt'), file);
});
test('Traversal, empty components, and dot components fail', () => {
  const dir = temp(); for (const p of ['../outside', 'a/../../b', 'a//b', './a', 'a/./b', ''])
    assert.throws(() => safePath(dir, p, { mustExist: false }));
});
test('Absolute paths, backslashes, control bytes, and alternate streams fail', () => {
  const dir = temp(); for (const p of ['/etc/passwd', 'C:/outside', 'a\\b', 'a\0b', 'a\nb', 'a:stream'])
    assert.throws(() => safePath(dir, p, { mustExist: false }));
});
test('A missing path needs explicit permission', () => {
  const dir = temp(); assert.throws(() => safePath(dir, 'absent'));
  assert.equal(safePath(dir, 'absent', { mustExist: false }), path.join(dir, 'absent'));
});
test('A symlink cannot redirect an input inventory', () => {
  const dir = temp(), outside = temp(); put(outside, 'file', 'x');
  fs.symlinkSync(outside, path.join(dir, 'link'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => safePath(dir, 'link/file'), /symlink/);
});
test('A dangling directory link is not a new output directory', () => {
  const dir = temp(), target = path.join(temp(), 'absent');
  fs.symlinkSync(target, path.join(dir, 'link'), process.platform === 'win32' ? 'junction' : 'dir');
  assert.throws(() => safePath(dir, 'link/output', { mustExist: false }), /symlink/);
});
test('An empty input inventory fails', () => {
  const dir = temp(); fs.mkdirSync(path.join(dir, 'empty'));
  assert.throws(() => collectFiles(dir, ['empty']), /empty/i);
});
test('Input hashes change with content', () => {
  const dir = temp(); put(dir, 'a', 'before'); const before = hashInputs(dir, ['a']);
  put(dir, 'a', 'after'); assert.notEqual(hashInputs(dir, ['a']).sha256, before.sha256);
});
test('Input hashes include relative names', () => {
  const dir = temp(); put(dir, 'a', 'same'); const a = hashInputs(dir, ['a']);
  fs.renameSync(path.join(dir, 'a'), path.join(dir, 'b')); assert.notEqual(hashInputs(dir, ['b']).sha256, a.sha256);
});
test('Input hashes ignore checkout location and input order', () => {
  const a = temp(), b = temp(); for (const d of [a, b]) { put(d, 'a', 'one'); put(d, 'b', 'two'); }
  assert.deepEqual(hashInputs(a, ['b', 'a']), hashInputs(b, ['a', 'b']));
});
test('Repeated roots do not duplicate files', () => {
  const dir = temp(); put(dir, 'src/a', 'a'); assert.deepEqual(collectFiles(dir, ['src', 'src/a']), ['src/a']);
});
test('File hashes match the SHA-256 content hash', () => {
  const dir = temp(); const f = put(dir, 'bytes', Buffer.from([0, 255, 1, 2]));
  assert.equal(fileHash(f), sha256(fs.readFileSync(f)));
});
test('Atomic JSON output supports replacement and BOM input', () => {
  const dir = temp(), f = path.join(dir, 'nested/value.json'); writeJson(f, { n: 1 }); writeJson(f, { n: 2 });
  assert.deepEqual(readJson(f), { n: 2 }); put(dir, 'bom.json', '\ufeff{"ok":true}');
  assert.deepEqual(readJson(path.join(dir, 'bom.json')), { ok: true });
});

// Toolchain integrity.
test('The supplied compiler lock has a valid structure', () => assert.equal(validateLock(lock()), true));
test('A stable version cannot silently replace Zig master', () => {
  const l = lock(); l.version = '0.15.1'; assert.throws(() => validateLock(l), /development/);
});
test('A floating compiler version fails', () => {
  const l = lock(); l.version = 'master'; assert.throws(() => validateLock(l));
});
test('A substituted compiler source fails', () => {
  const l = lock(); l.source = 'https://example.invalid/index.json'; assert.throws(() => validateLock(l));
});
test('A substituted artifact URL fails', () => {
  const l = lock(); Object.values(l.platforms)[0].url = 'https://example.invalid/zig.zip'; assert.throws(() => validateLock(l));
});
test('An invalid checksum or archive size fails', () => {
  for (const edit of [a => a.sha256 = '', a => a.size = 0, a => a.size = 1.5]) {
    const l = lock(); edit(Object.values(l.platforms)[0]); assert.throws(() => validateLock(l));
  }
});
test('A checksum mismatch cannot qualify an archive', () => {
  const dir = temp(), f = put(dir, 'archive', 'abc');
  assert.equal(verifyArchive(f, { size: 3, sha256: sha256('abc') }), true);
  assert.throws(() => verifyArchive(f, { size: 3, sha256: sha256('xyz') }), /SHA-256/);
});
test('A size mismatch cannot qualify an archive', () => {
  const dir = temp(), f = put(dir, 'archive', 'abc');
  assert.throws(() => verifyArchive(f, { size: 2, sha256: sha256('abc') }), /size/);
});
test('Host selection maps supported platform names explicitly', () => {
  assert.equal(hostPlatform('win32', 'x64'), 'x86_64-windows');
  assert.equal(hostPlatform('darwin', 'arm64'), 'aarch64-macos');
  assert.equal(hostPlatform('linux', 'arm64'), 'aarch64-linux');
  assert.throws(() => hostPlatform('freebsd', 'x64'));
  assert.throws(() => hostPlatform('linux', 'ia32'));
});

// Dependency graph and scope.
test('A valid task graph has one initial ready task', () => {
  const f = planFixture(); assert.equal(validPlan(f), true);
  assert.deepEqual(readyTasks(f.plan, f.state).map(t => t.id), ['FP-0001']);
});
test('An accepted prerequisite reveals the next task', () => {
  const f = planFixture(); Object.assign(f.state.tasks['FP-0001'], { status: 'accepted', evidence: ['fixture'], review: 'fixture' });
  assert.equal(validPlan(f), true); assert.deepEqual(readyTasks(f.plan, f.state).map(t => t.id), ['FP-0002']);
});
test('An active task does not become another ready task', () => {
  const f = planFixture(); f.state.tasks['FP-0001'].status = 'active'; assert.equal(readyTasks(f.plan, f.state).length, 0);
});
test('A duplicate task ID fails', () => {
  const f = planFixture(); f.plan.tasks.push(clone(f.plan.tasks[0])); assert.throws(() => validPlan(f), /duplicate/);
});
test('Unknown and duplicate prerequisites fail', () => {
  for (const deps of [['FP-9999'], ['FP-0001', 'FP-0001']]) {
    const f = planFixture(); f.plan.tasks[1].depends_on = deps; assert.throws(() => validPlan(f));
  }
});
test('A cycle in the task graph fails', () => {
  const f = planFixture(); f.plan.tasks[0].depends_on = ['FP-0002']; assert.throws(() => validPlan(f), /cycle/);
});
test('Empty acceptance criteria and unknown gates fail', () => {
  const a = planFixture(); a.plan.tasks[0].acceptance = []; assert.throws(() => validPlan(a), /acceptance/);
  const b = planFixture(); b.plan.tasks[0].required_gates = ['unknown']; assert.throws(() => validPlan(b), /gates/);
});
test('Missing state and unknown workstreams fail', () => {
  const a = planFixture(); delete a.state.tasks['FP-0001']; assert.throws(() => validPlan(a), /state/);
  const b = planFixture(); b.plan.tasks[0].workstream = 'absent'; assert.throws(() => validPlan(b), /workstream/);
});
test('Acceptance without evidence and review fails', () => {
  const f = planFixture(); f.state.tasks['FP-0001'].status = 'accepted'; assert.throws(() => validPlan(f), /evidence/);
});
test('Acceptance with an unaccepted prerequisite fails', () => {
  const f = planFixture(); Object.assign(f.state.tasks['FP-0002'], { status: 'accepted', evidence: ['fixture'], review: 'fixture' });
  assert.throws(() => validPlan(f), /unaccepted prerequisite/);
});
test('An empty release profile fails closed', () => assert.ok(qualificationProblems({}).length > 0));
test('The full set of capability families cannot disappear', () => {
  const p = readJson(path.join(root, 'engineering/qualification.json')); p.capabilities = [];
  const errors = qualificationProblems(p);
  for (const id of REQUIRED_CAPABILITIES) assert.ok(errors.some(e => e.includes(`missing: ${id}`)));
});
test('Qualified metadata alone cannot replace a release verifier', () => {
  const p = { schema_version: 1, profile_state: 'frozen', profile_revision: 1,
    capabilities: REQUIRED_CAPABILITIES.map(id => ({ id, required: true, status: 'qualified', manifest: 'fixture', evidence: ['fixture'] })),
    standards_baseline: 'fixture', target_matrix: 'fixture', performance_budgets: 'fixture',
    applicability_review: 'fixture', release_authority: 'fixture', license_decision: 'fixture' };
  assert.ok(qualificationProblems(p).some(e => e.includes('No protected runner')));
});

// The qualification boundary. A workspace writer can forge local receipts, so release evidence needs signed results.
test('1: A forged local receipt passes validateReceipt without gate execution', () => {
  const dir = gateFixture('import fs from "node:fs"; fs.writeFileSync("executed.txt", "the gate ran");');
  const gate = readJson(path.join(dir, 'engineering/gates.json')).gates[0];
  const log = put(dir, 'out/evidence/forged.log', 'No gate ran.\n');
  const inputs = fingerprints(dir);
  writeJson(path.join(dir, 'out/evidence/forged.json'), { schema_version: 1, kind: 'fairpane-local-gate',
    trust: 'unsigned-local-integrity-only', gate_id: gate.id, gate_sha256: sha256(JSON.stringify(gate)), status: 'pass',
    source_before: inputs.source, source_after: inputs.source, policy_before: inputs.policy, policy_after: inputs.policy,
    commands: [{ executable: 'never-run', arguments: [], exit_code: 0 }],
    outputs: [{ path: 'out/evidence/forged.log', size: fs.statSync(log).size, sha256: fileHash(log) }] });
  assert.equal(validateReceipt(dir, 'out/evidence/forged.json').result, 'pass');
  assert.equal(fs.existsSync(path.join(dir, 'executed.txt')), false);
});
for (const c of attestationCases) test(c.name, c.fn, c);
for (const c of workflowCases) test(c.name, c.fn, c);
for (const c of abiCases) test(c.name, c.fn, c);
for (const c of releaseCases) test(c.name, c.fn, c);
for (const c of ucdCases) test(c.name, c.fn, c);
for (const c of fileSetCases) test(c.name, c.fn, c);
for (const c of rustCases) test(c.name, c.fn, c);
test('15: release-check still exits with status 1', () => {
  const r = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'release-check'], { cwd: root, encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 1, r.stderr);
  const report = JSON.parse(r.stdout);
  assert.equal(report.result, 'not-qualified');
  assert.ok(report.problems.some(problem => problem.includes('No protected runner')));
});

// Actual command execution and evidence integrity.
test('A successful command records its actual output', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const r = await runProcess(process.execPath, ['-e', 'console.log("actual-output")'], { cwd: dir, logPath });
  assert.equal(r.exit_code, 0); assert.equal(r.timed_out, false); assert.match(fs.readFileSync(logPath, 'utf8'), /actual-output/);
});
test('A nonzero child exit remains a failure', async () => {
  const dir = temp(); const r = await runProcess(process.execPath, ['-e', 'process.exit(7)'], { cwd: dir, logPath: path.join(dir, 'log') });
  assert.equal(r.exit_code, 7);
});
test('A missing executable produces an error record', async () => {
  const dir = temp(); const r = await runProcess(path.join(dir, 'absent-executable'), [], { cwd: dir, logPath: path.join(dir, 'log') });
  assert.equal(r.exit_code, null); assert.ok(r.error);
});
test('A hung child reaches its watchdog and cannot pass', async () => {
  const dir = temp(); const r = await runProcess(process.execPath, ['-e', 'setInterval(() => {}, 1000)'],
    { cwd: dir, logPath: path.join(dir, 'log'), timeoutMs: 250 });
  assert.equal(r.timed_out, true); assert.notEqual(r.exit_code, 0);
});
test('Command arguments do not execute through a shell', async () => {
  const dir = temp(), arg = 'literal; echo unexpected && exit 7';
  const r = await runProcess(process.execPath, ['-e', 'console.log(process.argv[1])', arg], { cwd: dir, logPath: path.join(dir, 'log') });
  assert.equal(r.exit_code, 0); assert.match(fs.readFileSync(path.join(dir, 'log'), 'utf8'), /literal; echo unexpected/);
});
test('A real local gate produces a checkable unsigned receipt', async () => {
  const { dir, receipt } = await goodReceipt(); const checked = validateReceipt(dir, receipt.receipt_path);
  assert.equal(checked.result, 'pass'); assert.equal(checked.trust, 'unsigned-local-integrity-only');
});
test('Changed source makes a previous receipt stale', async () => {
  const { dir, receipt } = await goodReceipt(); put(dir, 'input.txt', 'changed\n');
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /stale source/);
});
test('Changed evidence output invalidates a receipt', async () => {
  const { dir, receipt } = await goodReceipt(); fs.appendFileSync(path.join(dir, receipt.outputs[0].path), 'tampered');
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /Evidence output changed/);
});
test('Changed gate definitions invalidate old receipts', async () => {
  const { dir, receipt } = await goodReceipt(); const p = path.join(dir, 'engineering/gates.json'), g = readJson(p);
  g.gates[0].timeout_ms += 1; writeJson(p, g); assert.throws(() => validateReceipt(dir, receipt.receipt_path), /gate definition changed/);
});
test('A local receipt cannot upgrade its own trust label', async () => {
  const { dir, receipt, file } = await goodReceipt(); receipt.trust = 'independent'; writeJson(file, receipt);
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /independent trust/);
});
test('A receipt without command records cannot pass', async () => {
  const { dir, receipt, file } = await goodReceipt(); receipt.commands = []; writeJson(file, receipt);
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /command records/);
});
test('A receipt without output artifacts cannot pass', async () => {
  const { dir, receipt, file } = await goodReceipt(); receipt.outputs = []; writeJson(file, receipt);
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /output artifacts/);
});
test('A failed command cannot hide behind a pass label', async () => {
  const { dir, receipt, file } = await goodReceipt(); receipt.commands[0].exit_code = 1; writeJson(file, receipt);
  assert.throws(() => validateReceipt(dir, receipt.receipt_path), /successfully/);
});
test('A command failure produces a failed gate receipt', async () => {
  const dir = gateFixture('process.exit(8);'), r = await runGate(dir, 'fixture');
  assert.equal(r.status, 'fail'); assert.equal(r.commands[0].exit_code, 8);
  assert.throws(() => validateReceipt(dir, r.receipt_path), /passed gate/);
});
test('A missing compiler produces a failed gate receipt', async () => {
  const dir = gateFixture(undefined, 'zig'), r = await runGate(dir, 'fixture');
  assert.equal(r.status, 'fail'); assert.match(r.error, /compiler is absent/); assert.equal(r.commands.length, 0);
});
test('Input changes during execution produce a failed gate receipt', async () => {
  const dir = gateFixture('import fs from "node:fs"; fs.writeFileSync("input.txt", "changed");');
  const r = await runGate(dir, 'fixture'); assert.equal(r.status, 'fail'); assert.match(r.error, /changed during execution/);
});
test('A removed input still produces a failed gate receipt', async () => {
  const dir = gateFixture('import fs from "node:fs"; fs.unlinkSync("input.txt");');
  const r = await runGate(dir, 'fixture'); assert.equal(r.status, 'fail'); assert.equal(r.source_after, null);
  assert.ok(fs.existsSync(path.join(dir, r.receipt_path)));
});
test('Unknown gates fail before execution', async () => {
  const dir = gateFixture(); await assert.rejects(() => runGate(dir, 'unknown'), /Unknown gate/);
});
/** A gate command that starts a child with `marker` in its command line, records the child's PID, prints `fp0098-output <marker>`, and then hangs. */
function hungGateFixture(marker) {
  return gateFixture(`import { spawn } from 'node:child_process'; import fs from 'node:fs';
const child = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)', ${JSON.stringify(marker)}], { stdio: 'ignore', windowsHide: true });
fs.writeFileSync('child.pid', String(child.pid));
console.log(${JSON.stringify(`fp0098-output ${marker}`)});
setInterval(() => {}, 1000);`);
}
function processAlive(pid) {
  try { process.kill(pid, 0); return true; } catch (e) { if (e.code === 'ESRCH') return false; throw e; }
}
/** Wait up to five seconds for `pid` to end. A survivor is stopped so that it cannot outlive the test, and the check fails. */
async function expectStopped(pid) {
  for (let waited = 0; waited < 5000 && processAlive(pid); waited += 100) await new Promise(r => setTimeout(r, 100));
  if (!processAlive(pid)) return;
  try { process.kill(pid, 'SIGKILL'); } catch { /* It ended after the last check. */ }
  assert.fail(`Process ${pid} kept running after the gate stopped its command.`);
}
const timeoutLines = log => log.split(/\r?\n/).filter(l => l.startsWith('TIMEOUT ') || l.startsWith('PROCESS '));
/** Assert that the command's output line follows the last TIMEOUT line, so a stopped command keeps its output in the log. */
function expectOutputAfterTimeout(log, marker) {
  const lines = log.split(/\r?\n/), output = lines.indexOf(`fp0098-output ${marker}`);
  const lastTimeout = lines.findLastIndex(l => l.startsWith('TIMEOUT '));
  assert.ok(lastTimeout >= 0 && output > lastTimeout,
    `The log lacks the line "fp0098-output ${marker}" after its TIMEOUT section (line ${output}, last TIMEOUT line ${lastTimeout}).`);
}
test('FP-0098 case 1: a timed-out gate lists its live descendants before it stops them', async () => {
  const marker = `fp0098-marker-${process.pid}-${Date.now()}`, dir = hungGateFixture(marker);
  const r = await runGate(dir, 'fixture');
  const childPid = Number(fs.readFileSync(path.join(dir, 'child.pid'), 'utf8'));
  await expectStopped(childPid);
  assert.equal(r.status, 'fail'); assert.equal(r.commands.length, 1); assert.equal(r.commands[0].timed_out, true);
  const log = fs.readFileSync(path.join(dir, r.outputs[0].path), 'utf8');
  const processes = log.split(/\r?\n/).filter(l => l.startsWith('PROCESS ')).map(l => JSON.parse(l.slice('PROCESS '.length)));
  const child = processes.find(p => p.pid === childPid);
  assert.ok(child, `The log lists no process with the child's PID ${childPid}:\n${timeoutLines(log).join('\n')}`);
  assert.ok(JSON.stringify(child.command_line).includes(marker), `The child's command line lacks its marker: ${JSON.stringify(child)}`);
  assert.ok(processes.some(p => p.pid === child.ppid), 'The log lists the child\'s parent, the gate command.');
  assert.match(log, /^TIMEOUT after 2000 ms: the live process tree of PID \d+ follows\.$/m);
  assert.match(log, /^TIMEOUT Stopping PID \d+ and its descendants\.$/m);
  expectOutputAfterTimeout(log, marker);
});
test('FP-0098 case 2: a failed listing is named in the log, and the gate still stops the command and fails', async () => {
  const marker = `fp0098-marker-${process.pid}-${Date.now()}`, dir = hungGateFixture(marker);
  const absent = path.join(dir, 'absent');
  const r = await runGate(dir, 'fixture', { processListing: { powershell: path.join(absent, 'powershell.exe'), procRoot: absent } });
  const childPid = Number(fs.readFileSync(path.join(dir, 'child.pid'), 'utf8'));
  await expectStopped(childPid);
  assert.equal(r.status, 'fail'); assert.equal(r.commands.length, 1); assert.equal(r.commands[0].timed_out, true);
  const log = fs.readFileSync(path.join(dir, r.outputs[0].path), 'utf8');
  assert.match(log, /^TIMEOUT after 2000 ms: the process listing failed: .*ENOENT.*$/m);
  assert.equal(log.split(/\r?\n/).filter(l => l.startsWith('PROCESS ')).length, 0);
  assert.match(log, /^TIMEOUT Stopping PID \d+ and its descendants\.$/m);
  expectOutputAfterTimeout(log, marker);
});
test('FP-0098 case 3: an ordinary pass or fail gate record has no timeout section and is not timed out', async () => {
  for (const [script, status, code] of [['console.log("Fixture command ran.");', 'pass', 0], ['process.exit(8);', 'fail', 8]]) {
    const dir = gateFixture(script), r = await runGate(dir, 'fixture');
    assert.equal(r.status, status); assert.equal(r.commands.length, 1);
    assert.equal(r.commands[0].exit_code, code); assert.equal(r.commands[0].timed_out, false);
    assert.deepEqual(timeoutLines(fs.readFileSync(path.join(dir, r.outputs[0].path), 'utf8')), []);
  }
});
test('FP-0098 revision 1 case 2: a command that ends during the timeout listing gets a line that says so, and its descendants stop', async () => {
  const dir = temp(), marker = `fp0098-marker-${process.pid}-${Date.now()}`, pidFile = path.join(dir, 'child.pid');
  const script = put(dir, 'hung.cjs', `const { spawn } = require('node:child_process'); const fs = require('node:fs');
const child = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)', ${JSON.stringify(marker)}], { stdio: 'ignore', windowsHide: true });
fs.writeFileSync(${JSON.stringify(pidFile)}, String(child.pid));
setInterval(() => {}, 1000);`);
  const pause = ms => new Promise(r => setTimeout(r, ms));
  const childPid = async () => {
    for (let waited = 0; waited < 5000; waited += 20) {
      const pid = fs.existsSync(pidFile) ? Number(fs.readFileSync(pidFile, 'utf8')) : 0;
      if (pid > 0) return pid;
      await pause(20);
    }
    throw new Error('The command wrote no child PID within 5 seconds.');
  };
  // The stand-in lists the command and its child, then stops only the command and resolves after the command has exited.
  let listedPid = null;
  const standIn = async pid => {
    const child = await childPid();
    process.kill(pid, 'SIGKILL');
    for (let waited = 0; processAlive(pid); waited += 20) {
      if (waited >= 5000) throw new Error(`The command ${pid} did not exit within 5 seconds.`);
      await pause(20);
    }
    listedPid = pid;
    return [{ pid, ppid: process.pid, command_line: 'stand-in command' }, { pid: child, ppid: pid, command_line: ['stand-in child', marker] }];
  };
  const logPath = path.join(dir, 'command.log');
  const r = await runProcess(process.execPath, [script], { cwd: dir, logPath, timeoutMs: 400, processListing: standIn });
  await expectStopped(await childPid());
  assert.equal(r.timed_out, true);
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/);
  const ended = lines.indexOf('TIMEOUT The command ended during the listing.');
  assert.ok(ended >= 0, `The log lacks the line for a command that ended during the listing:\n${timeoutLines(lines.join('\n')).join('\n')}`);
  assert.ok(ended < lines.findIndex(l => l.startsWith('RESULT ')), 'The line comes after the RESULT line, so the log closed first.');
  assert.ok(listedPid !== null && !processAlive(listedPid), 'The stand-in did not run, or the command is still alive.');
});
test('Evidence paths cannot escape their approved roots', async () => {
  const { dir } = await goodReceipt(); assert.throws(() => validateReceipt(dir, 'input.txt'), /outside an allowed directory/);
  assert.throws(() => validateReceipt(dir, 'out/evidence/../../input.txt'), /traversal/);
});
test('A gate writes a checkable receipt under an approved evidence directory', async () => {
  const dir = gateFixture(), evidenceDir = 'engineering/evidence/FP-9999/gates';
  const r = await runGate(dir, 'fixture', { evidenceDir });
  assert.equal(r.status, 'pass');
  assert.ok(r.receipt_path.startsWith(`${evidenceDir}/`) && r.outputs[0].path.startsWith(`${evidenceDir}/`));
  assert.equal(validateReceipt(dir, r.receipt_path).result, 'pass');
  assert.equal(fs.existsSync(path.join(dir, 'out')), false);
});
test('An unapproved evidence directory fails before any gate command runs', async () => {
  for (const evidenceDir of ['tools', 'out/evidence/../tools', 'engineering/evidence-other']) {
    const dir = gateFixture('import fs from "node:fs"; fs.writeFileSync("ran.txt", "ran");');
    await assert.rejects(() => runGate(dir, 'fixture', { evidenceDir }));
    assert.equal(fs.existsSync(path.join(dir, 'ran.txt')), false, evidenceDir);
  }
});
test('Environment overrides reach the child and its command record', async () => {
  const dir = temp(), logPath = path.join(dir, 'log'), env = { FAIRPANE_FIXTURE_OVERRIDE: 'override-7f3a' };
  const r = await runProcess(process.execPath, ['-e', 'console.log(`child saw ${process.env.FAIRPANE_FIXTURE_OVERRIDE}`)'],
    { cwd: dir, logPath, env });
  assert.equal(r.exit_code, 0); assert.deepEqual(r.environment_overrides, env);
  assert.match(fs.readFileSync(logPath, 'utf8'), /child saw override-7f3a/);
  assert.equal(process.env.FAIRPANE_FIXTURE_OVERRIDE, undefined);
});
test('Executable resolution follows PATH order', () => {
  const first = temp(), second = temp(), cwd = temp(), name = 'fixture-tool';
  const make = dir => { const f = put(dir, process.platform === 'win32' ? `${name}.exe` : name, 'fixture'); fs.chmodSync(f, 0o755); return f; };
  const late = make(second); make(cwd);
  const pathEnv = [first, second].join(path.delimiter);
  assert.equal(resolveExecutable(cwd, name, { pathEnv }), late);
  const early = make(first);
  assert.equal(resolveExecutable(cwd, name, { pathEnv }), early);
  assert.throws(() => resolveExecutable(cwd, name, { pathEnv: '' }), /not on PATH/);
});
test('A recorded command keeps its output, exit status, and resolved executable', async () => {
  const dir = gateFixture(), log = 'out/evidence/record.log', argv = ['-e', 'console.log("recorded-output"); process.exit(3)'];
  const r = await recordCommand(dir, log, process.execPath, argv);
  assert.equal(r.exit_code, 3);
  const text = fs.readFileSync(path.join(dir, log), 'utf8');
  assert.match(text, /recorded-output/); assert.ok(text.includes(`COMMAND ${JSON.stringify([process.execPath, ...argv])}`));
  const missing = await recordCommand(dir, log, 'fairpane-absent-tool', []);
  assert.equal(missing.exit_code, null); assert.match(missing.error, /not on PATH/);
  assert.match(fs.readFileSync(path.join(dir, log), 'utf8'), /fairpane-absent-tool/);
  await assert.rejects(() => recordCommand(dir, 'tools/record.log', process.execPath, ['-e', '']), /outside an allowed directory/);
});
async function withPrivateTemp(fn) {
  const dir = temp(), keys = ['TMPDIR', 'TMP', 'TEMP'], saved = keys.map(k => process.env[k]);
  for (const k of keys) process.env[k] = dir;
  try { await fn(dir); }
  finally { keys.forEach((k, i) => { if (saved[i] === undefined) delete process.env[k]; else process.env[k] = saved[i]; }); }
  return dir;
}
test('Command records carry the working directory and start time', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath });
  assert.equal(r.exit_code, 0); assert.equal(r.cwd, path.resolve(dir)); assert.ok(!Number.isNaN(Date.parse(r.started_at)));
  const line = fs.readFileSync(logPath, 'utf8').split('\n').find(l => l.startsWith('RESULT '));
  const logged = JSON.parse(line.slice('RESULT '.length));
  assert.equal(logged.cwd, r.cwd); assert.equal(logged.started_at, r.started_at);
});
test('An unwritable log yields a failed result instead of an exception', async () => {
  const dir = temp(); put(dir, 'blocker', 'a regular file');
  const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath: path.join(dir, 'blocker', 'nested', 'log') });
  assert.equal(r.exit_code, null); assert.match(r.error, /Log write failed/);
});
test('A failed output copy is recorded and its capture directory is removed', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const tmp = await withPrivateTemp(async () => {
    const r = await runProcess(process.execPath, ['-e', 'console.log("ignored")'], { cwd: dir, logPath,
      copyOutput: () => { throw new Error('forced copy failure'); } });
    assert.equal(r.exit_code, 0); assert.match(r.error, /forced copy failure/);
  });
  assert.match(fs.readFileSync(logPath, 'utf8'), /^RESULT .*forced copy failure/m);
  assert.deepEqual(fs.readdirSync(tmp), []);
}, { processWide: 'TMPDIR, TMP, and TEMP in process.env' });
test('Standard error output reaches the log', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const r = await runProcess(process.execPath, ['-e', 'console.error("to-standard-error")'], { cwd: dir, logPath });
  assert.equal(r.exit_code, 0); assert.match(fs.readFileSync(logPath, 'utf8'), /to-standard-error/);
});
test('A completed command leaves no capture directory', async () => {
  const dir = temp();
  const tmp = await withPrivateTemp(async () => {
    const r = await runProcess(process.execPath, ['-e', 'console.log("captured")'], { cwd: dir, logPath: path.join(dir, 'log') });
    assert.equal(r.exit_code, 0);
  });
  assert.deepEqual(fs.readdirSync(tmp), []);
  assert.match(fs.readFileSync(path.join(dir, 'log'), 'utf8'), /captured/);
}, { processWide: 'TMPDIR, TMP, and TEMP in process.env' });
test('Executable resolution never searches the process working directory', () => {
  const cwd = temp(), other = temp(), name = 'fixture-cwd-tool', saved = process.cwd();
  fs.chmodSync(put(cwd, process.platform === 'win32' ? `${name}.exe` : name, 'fixture'), 0o755);
  process.chdir(cwd);
  try { assert.throws(() => resolveExecutable(other, name, { pathEnv: '' }), /not on PATH/); }
  finally { process.chdir(saved); }
}, { processWide: 'the working directory' });
test('A bare executable name is logged as its resolved absolute path', async () => {
  const dir = gateFixture(), log = 'out/evidence/bare.log';
  const bare = path.basename(process.execPath, process.platform === 'win32' ? '.exe' : '');
  const r = await recordCommand(dir, log, bare, ['-e', ''], { pathEnv: path.dirname(process.execPath) });
  assert.equal(r.exit_code, 0); assert.equal(r.executable, process.execPath);
  assert.ok(fs.readFileSync(path.join(dir, log), 'utf8').includes(`COMMAND ${JSON.stringify([process.execPath, '-e', ''])}`));
});
test('A rejected record path writes nothing', async () => {
  const dir = gateFixture();
  await assert.rejects(() => recordCommand(dir, 'tools/rejected.log', process.execPath, ['-e', '']), /outside an allowed directory/);
  assert.equal(fs.existsSync(path.join(dir, 'tools', 'rejected.log')), false);
});
test('The controller rejects malformed run and record arguments', () => {
  const cli = path.join(root, 'tools/fairpane.mjs');
  for (const argv of [['run'], ['run', 'repo-check', '--evidence-dir'],
    ['record', '--env', 'NOT-AN-ASSIGNMENT', 'out/evidence/x.log', process.execPath]]) {
    const r = spawnSync(process.execPath, [cli, ...argv], { encoding: 'utf8', timeout: 30000, windowsHide: true });
    assert.equal(r.status, 1, argv.join(' ')); assert.match(r.stderr, /Usage:/, argv.join(' '));
  }
});
test('Only Zig and C ABI gates receive the repository-local compiler cache', () => {
  const dir = temp(), expected = { ZIG_GLOBAL_CACHE_DIR: path.join(dir, '.zig-cache', 'global') };
  assert.deepEqual(gateEnvironment(dir, { kind: 'zig' }), expected);
  assert.deepEqual(gateEnvironment(dir, { kind: 'c-abi' }), expected);
  assert.equal(gateEnvironment(dir, { kind: 'controller-check' }), undefined);
  assert.equal(gateEnvironment(dir, { kind: 'controller-test' }), undefined);
});
// FP-0031: failure paths behind command records. The `fileSystem` seam replaces single node:fs operations.
function trackingFs(overrides = {}) {
  const opened = new Map(), closed = new Set();
  const fileSystem = {
    openSync: (file, ...rest) => { const fd = fs.openSync(file, ...rest); opened.set(fd, file); return fd; },
    closeSync: fd => { closed.add(fd); fs.closeSync(fd); },
    ...overrides,
  };
  const logClosed = logPath => [...opened].some(([fd, file]) => file === logPath && closed.has(fd));
  return { fileSystem, logClosed };
}
const lastResult = logPath => {
  const lines = fs.readFileSync(logPath, 'utf8').split('\n').filter(l => l.startsWith('RESULT '));
  assert.ok(lines.length > 0, `${logPath} has no RESULT line.`);
  return JSON.parse(lines.at(-1).slice(7));
};
const failOutputOpen = (fileSystem, message) => {
  const open = fileSystem.openSync;
  fileSystem.openSync = (file, ...rest) => { if (path.basename(file) === 'output.log') throw new Error(message); return open(file, ...rest); };
};
test('A capture-start failure writes a RESULT line, closes the log, and returns an error result', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const t = trackingFs({ mkdtempSync: () => { throw new Error('forced capture start failure'); } });
  const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath, fileSystem: t.fileSystem });
  assert.equal(r.exit_code, null); assert.equal(r.error, 'Output capture failed: forced capture start failure');
  assert.equal(lastResult(logPath).error, r.error); assert.ok(t.logClosed(logPath), 'The log descriptor stayed open.');
  const tmp = await withPrivateTemp(async () => {
    const u = trackingFs(), second = path.join(dir, 'second.log');
    failOutputOpen(u.fileSystem, 'forced capture open failure');
    const s = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath: second, fileSystem: u.fileSystem });
    assert.equal(s.exit_code, null); assert.equal(s.error, 'Output capture failed: forced capture open failure');
    assert.equal(lastResult(second).error, s.error); assert.ok(u.logClosed(second), 'The log descriptor stayed open.');
  });
  assert.deepEqual(fs.readdirSync(tmp), []);
});
test('A failed RESULT write returns an error result instead of throwing', async () => {
  const failResult = (fd, data, ...rest) => {
    if (String(data).startsWith('RESULT ')) throw new Error('forced result write failure');
    return fs.writeSync(fd, data, ...rest);
  };
  // The unresolved-name and capture-start paths write RESULT synchronously, so a throw there reaches this test.
  const gate = gateFixture(), t = trackingFs({ writeSync: failResult });
  const missing = await recordCommand(gate, 'out/evidence/result.log', 'fairpane-absent-tool', [], { fileSystem: t.fileSystem });
  assert.match(missing.error, /not on PATH: fairpane-absent-tool Log write failed: forced result write failure$/);
  assert.ok(t.logClosed(path.join(gate, 'out/evidence/result.log')), 'The log descriptor stayed open.');
  const dir = temp(), early = path.join(dir, 'early.log');
  const u = trackingFs({ writeSync: failResult, mkdtempSync: () => { throw new Error('forced capture start failure'); } });
  const e = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath: early, fileSystem: u.fileSystem });
  assert.equal(e.error, 'Output capture failed: forced capture start failure Log write failed: forced result write failure');
  assert.ok(u.logClosed(early), 'The log descriptor stayed open.');
  const logPath = path.join(dir, 'log'), v = trackingFs({ writeSync: failResult });
  const r = await runProcess(process.execPath, ['-e', 'console.log("before-result")'], { cwd: dir, logPath, fileSystem: v.fileSystem });
  assert.equal(r.exit_code, 0); assert.equal(r.error, 'Log write failed: forced result write failure');
  assert.ok(v.logClosed(logPath), 'The log descriptor stayed open.');
  const text = fs.readFileSync(logPath, 'utf8');
  assert.match(text, /before-result/); assert.doesNotMatch(text, /^RESULT /m);
});
test('A spawn error and a capture error both remain in the result', async () => {
  const dir = temp(), missing = path.join(dir, 'absent-executable');
  const plain = await runProcess(missing, [], { cwd: dir, logPath: path.join(dir, 'plain.log') });
  assert.equal(plain.exit_code, null); assert.ok(plain.error);
  const logPath = path.join(dir, 'log');
  const fileSystem = { readSync: () => { throw new Error('forced capture read failure'); } };
  const r = await runProcess(missing, [], { cwd: dir, logPath, fileSystem });
  assert.equal(r.exit_code, null); assert.equal(r.error, `${plain.error} Output capture failed: forced capture read failure`);
  assert.equal(lastResult(logPath).error, r.error);
});
test('runGate writes nothing when its evidence directory fails validation', async () => {
  const listing = dir => fs.readdirSync(dir, { recursive: true }).map(String).sort();
  for (const evidenceDir of ['tools', 'out/evidence/../tools', 'engineering/evidence-other']) {
    const dir = gateFixture(), before = listing(dir);
    await assert.rejects(() => runGate(dir, 'fixture', { evidenceDir }), /outside an allowed directory|traversal/);
    assert.deepEqual(listing(dir), before, evidenceDir);
  }
});
test('A short write to the log produces an error result', async () => {
  const shortOn = kind => ({ writeSync: (fd, data, offset = 0, length = data.length - offset) => {
    const text = Buffer.from(data).subarray(offset, offset + length).toString();
    const k = text.startsWith('\nCOMMAND ') ? 'COMMAND' : text.startsWith('RESULT ') ? 'RESULT' : 'output';
    return fs.writeSync(fd, data, offset, k === kind ? length - 1 : length);
  } });
  for (const kind of ['COMMAND', 'output', 'RESULT']) {
    const dir = temp();
    const r = await runProcess(process.execPath, ['-e', 'console.log("short-write-output")'],
      { cwd: dir, logPath: path.join(dir, 'log'), fileSystem: shortOn(kind) });
    assert.match(r.error ?? '', /Short write: \d+ of \d+ bytes/, `${kind}: ${r.error}`);
  }
  const dir = gateFixture();
  const missing = await recordCommand(dir, 'out/evidence/short.log', 'fairpane-absent-tool', [], { fileSystem: shortOn('RESULT') });
  assert.match(missing.error, /not on PATH/); assert.match(missing.error, /Log write failed: Short write: \d+ of \d+ bytes/);
});
test('A failed capture-directory removal appears in the command record', async () => {
  const dir = temp(), logPath = path.join(dir, 'log');
  const tmp = await withPrivateTemp(async () => {
    const fileSystem = { rmSync: () => { throw new Error('forced removal failure'); } };
    const r = await runProcess(process.execPath, ['-e', 'console.log("kept")'], { cwd: dir, logPath, fileSystem });
    assert.equal(r.exit_code, 0); assert.equal(r.error, 'Capture directory removal failed: forced removal failure');
    assert.equal(lastResult(logPath).error, r.error);
    const second = path.join(dir, 'second.log'), t = trackingFs({ rmSync: fileSystem.rmSync });
    failOutputOpen(t.fileSystem, 'forced capture open failure');
    const s = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath: second, fileSystem: t.fileSystem });
    assert.equal(s.error, 'Output capture failed: forced capture open failure Capture directory removal failed: forced removal failure');
    assert.equal(lastResult(second).error, s.error);
  });
  assert.equal(fs.readdirSync(tmp).length, 2, 'Both capture directories survive, as their records state.');
});
// Each injected removal failure has a distinct message, so a record that names an earlier failure is caught.
function failingRemoval(failures) {
  const times = [];
  const rmSync = (...args) => {
    times.push(performance.now());
    const failure = failures[times.length - 1];
    if (failure) throw Object.assign(new Error(failure.message), { code: failure.code });
    return fs.rmSync(...args);
  };
  return { times, fileSystem: { rmSync } };
}
test('FP-0054 case 6: A busy capture directory is removed on a later attempt', async () => {
  const dir = temp(), logPath = path.join(dir, 'recovered.log');
  const removal = failingRemoval([{ code: 'EBUSY', message: 'busy 1' }, { code: 'EBUSY', message: 'busy 2' }]);
  const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath, fileSystem: removal.fileSystem });
  assert.equal(r.error, null); assert.equal(removal.times.length, 3);
  assert.equal(lastResult(logPath).error, null);
});
test('FP-0054 case 6: a capture directory that stays busy records the last failure after waiting between attempts', async () => {
  const dir = temp(), logPath = path.join(dir, 'stuck.log');
  const removal = failingRemoval(['busy 1', 'busy 2', 'busy 3'].map(message => ({ code: 'EBUSY', message })));
  const tmp = await withPrivateTemp(async () => {
    const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath, fileSystem: removal.fileSystem });
    assert.equal(r.error, 'Capture directory removal failed: busy 3'); assert.equal(removal.times.length, 3);
    assert.equal(lastResult(logPath).error, r.error);
  });
  // removeCapture waits 50 and then 100 milliseconds; the bound leaves 10 milliseconds for timer granularity.
  const elapsed = removal.times[2] - removal.times[0];
  assert.ok(elapsed >= 140, `The three removal attempts took ${elapsed} ms.`);
  assert.equal(fs.readdirSync(tmp).length, 1, 'The failed capture directory survives, as its record states.');
});
test('FP-0054 case 6: a capture-directory removal error with a non-transient code gets one attempt', async () => {
  const dir = temp(), logPath = path.join(dir, 'denied.log');
  const removal = failingRemoval([{ code: 'EACCES', message: 'EACCES: forced access failure' }]);
  const tmp = await withPrivateTemp(async () => {
    const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath, fileSystem: removal.fileSystem });
    assert.equal(r.error, 'Capture directory removal failed: EACCES: forced access failure'); assert.equal(removal.times.length, 1);
    assert.equal(lastResult(logPath).error, r.error);
  });
  assert.equal(fs.readdirSync(tmp).length, 1, 'The failed capture directory survives, as its record states.');
});
test('FP-0054 revision 1 case 6: a capture-directory removal error without a code gets one attempt', async () => {
  const dir = temp(), logPath = path.join(dir, 'uncoded.log');
  const removal = failingRemoval([{ message: 'forced removal failure without a code' }]);
  const tmp = await withPrivateTemp(async () => {
    const r = await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath, fileSystem: removal.fileSystem });
    assert.equal(r.error, 'Capture directory removal failed: forced removal failure without a code'); assert.equal(removal.times.length, 1);
    assert.equal(lastResult(logPath).error, r.error);
  });
  assert.equal(fs.readdirSync(tmp).length, 1, 'The failed capture directory survives, as its record states.');
});
test('FP-0054 case 6: lastResult asserts that a RESULT line exists before it parses one', () => {
  const logPath = path.join(temp(), 'no-result.log');
  fs.writeFileSync(logPath, '\nCOMMAND ["absent"]\noutput without a result\n');
  assert.throws(() => lastResult(logPath), { name: 'AssertionError', message: `${logPath} has no RESULT line.` });
});
test('started_at in every command record is a canonical UTC ISO 8601 timestamp', async () => {
  const dir = gateFixture(), log = 'out/evidence/times.log', logPath = path.join(dir, log);
  put(dir, 'blocker', 'a regular file');
  const records = [
    await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath }),
    await runProcess(path.join(dir, 'absent-executable'), [], { cwd: dir, logPath }),
    await runProcess(process.execPath, ['-e', ''], { cwd: dir, logPath: path.join(dir, 'blocker', 'log') }),
    await recordCommand(dir, log, process.execPath, ['-e', '']),
    await recordCommand(dir, log, 'fairpane-absent-tool', []),
    ...(await runGate(dir, 'fixture')).commands,
  ];
  const logged = fs.readFileSync(logPath, 'utf8').split('\n').filter(l => l.startsWith('RESULT ')).map(l => JSON.parse(l.slice(7)));
  assert.equal(logged.length, 4);
  for (const r of [...records, ...logged]) {
    assert.match(r.started_at, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/, JSON.stringify(r));
    assert.equal(new Date(r.started_at).toISOString(), r.started_at);
  }
});
test('The mutation control runs an unmutated baseline first and records each killed test name and message', async () => {
  const { runControl } = await import(pathToFileURL(path.join(root, 'tools/mutation-harness.mjs')).href);
  const tap = results => ['TAP version 13', ...results.flatMap(([ok, name, message], i) => ok ? [`ok ${i + 1} - ${name}`]
    : [`not ok ${i + 1} - ${name}`, '  ---', `  message: ${JSON.stringify(message)}`, '  ...'])].join('\n');
  const mutants = [['kills first', 'A1', 'A2', /first target/], ['misses second', 'B1', 'B2', /second target/],
    ['absent text', 'C1', 'C2', /first target/], ['ambiguous target', 'B1', 'B3', /target/]];
  const calls = [], lines = [];
  const r = runControl({ source: 'A1 B1', mutants, log: l => lines.push(l), runSuite: text => {
    calls.push(text);
    return { status: text === null ? 0 : 1, stdout: tap([[!text?.includes('A2'), 'first target', 'first failed'], [true, 'second target']]) };
  } });
  assert.deepEqual(calls, [null, 'A2 B1', 'A1 B2']);
  assert.deepEqual(r, { baseline: true, killed: 1, survived: 3 });
  const out = lines.join('\n');
  assert.match(out, /^BASELINE exit 0: 2 tests, 0 failing$/m);
  assert.match(out, /^KILLED kills first: not ok 1 - first target\n {2}message: "first failed"$/m);
  assert.match(out, /^SURVIVED misses second: ok 2 - second target$/m);
  assert.match(out, /^SETUP-FAILED absent text:/m); assert.match(out, /^SETUP-FAILED ambiguous target:/m);
  const again = [], failedLines = [];
  const failed = runControl({ source: 'A1 B1', mutants, log: l => failedLines.push(l), runSuite: text => {
    again.push(text);
    return { status: 1, stdout: tap([[false, 'first target', 'broken baseline'], [true, 'second target']]) };
  } });
  assert.deepEqual(again, [null]); assert.deepEqual(failed, { baseline: false, killed: 0, survived: mutants.length });
  assert.match(failedLines.join('\n'), /^BASELINE-FAILED not ok 1 - first target\n {2}message: "broken baseline"$/m);
  const literal = [];
  runControl({ source: 'X1', mutants: [['literal', 'X1', '$&$&', /first target/]], log: () => {}, runSuite: text => {
    literal.push(text);
    return { status: text === null ? 0 : 1, stdout: tap([[text === null, 'first target', 'mutated']]) };
  } });
  assert.deepEqual(literal, [null, '$&$&']);
});
// Corpus snapshots. Fixtures use Git plumbing with no user or system configuration.
const gitConfigFile = path.join(temp(), 'empty-gitconfig');
fs.writeFileSync(gitConfigFile, '');
const fixtureEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitConfigFile, GIT_TERMINAL_PROMPT: '0',
  GIT_AUTHOR_NAME: 'Fairpane Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid', GIT_AUTHOR_DATE: '1767323045 +0130',
  GIT_COMMITTER_NAME: 'Fairpane Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid', GIT_COMMITTER_DATE: '1767323045 +0130' };
function fixtureGit(cwd, args, input) {
  const r = spawnSync('git', args, { cwd, input, env: fixtureEnv, windowsHide: true });
  assert.equal(r.status, 0, `git ${args.join(' ')} failed: ${r.error?.message ?? r.stderr}`);
  return r.stdout.toString('latin1').trim();
}
function bareRepo(dir = temp()) { fs.mkdirSync(dir, { recursive: true }); fixtureGit(dir, ['init', '--bare', '--quiet', '.']); return dir; }
function splitPath(bytes) {
  const parts = [];
  for (let i = 0, start = 0; i <= bytes.length; i++) if (i === bytes.length || bytes[i] === 0x2f) { parts.push(bytes.subarray(start, i)); start = i + 1; }
  return parts;
}
function fixtureTree(gitDir, entries) {
  const lines = [], dirs = new Map(), nul = Buffer.from([0]);
  for (const e of entries) {
    if (e.parts.length === 1) { lines.push(Buffer.concat([Buffer.from(`${e.mode} ${e.type} ${e.oid}\t`), e.parts[0], nul])); continue; }
    const name = e.parts[0].toString('latin1');
    if (!dirs.has(name)) dirs.set(name, []);
    dirs.get(name).push({ ...e, parts: e.parts.slice(1) });
  }
  for (const [name, sub] of dirs) lines.push(Buffer.concat([Buffer.from(`040000 tree ${fixtureTree(gitDir, sub)}\t`), Buffer.from(name, 'latin1'), nul]));
  const missing = entries.some(e => e.parts.length === 1 && e.type === 'commit') ? ['--missing'] : [];
  return fixtureGit(gitDir, ['mktree', '-z', ...missing], Buffer.concat(lines));
}
/** Files: `{ path, text, mode }` for blobs and symbolic links, or `{ path, submodule }` for a submodule commit. */
function fixtureCommit(gitDir, files, parents = []) {
  const tree = fixtureTree(gitDir, files.map(f => ({ parts: splitPath(Buffer.from(f.path)),
    mode: f.submodule ? '160000' : f.mode ?? '100644', type: f.submodule ? 'commit' : 'blob',
    oid: f.submodule ?? fixtureGit(gitDir, ['hash-object', '-w', '--stdin'], Buffer.from(f.text)) })));
  return fixtureGit(gitDir, ['-c', 'user.name=Fairpane Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
    'commit-tree', tree, '-m', 'fixture', ...parents.flatMap(p => ['-p', p])]);
}
const inventoryLine = (mode, text, p) =>
  Buffer.concat([Buffer.from(`${mode}\t${sha256(Buffer.from(text))}\t${Buffer.byteLength(text)}\t`), Buffer.from(p), Buffer.from('\n')]);
async function inventoryOf(gitDir, commit) { return computeInventory(gitDir, await listTree(gitDir, commit), { keepLines: true }); }

test('The inventory of a fixture commit equals a hand-computed canonical listing digest', async () => {
  const g = bareRepo();
  const c = fixtureCommit(g, [{ path: 'b/run.sh', text: '#!/bin/sh\n', mode: '100755' }, { path: 'b.txt', text: '' }, { path: 'a.txt', text: 'alpha\n' }]);
  const inv = await inventoryOf(g, c);
  assert.equal(inv.text.toString('latin1'),
    '100644\tb6a98d9ce9a2d9149288fa3df42d377c3e42737afdcdaf714e33c0a100b51060\t6\ta.txt\n' +
    '100644\te3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\t0\tb.txt\n' +
    '100755\ta8076d3d28d21e02012b20eaf7dbf75409a6277134439025f282e368e3305abf\t10\tb/run.sh\n');
  // Computed outside the controller with printf and sha256sum.
  assert.equal(inv.sha256, 'a26efd6729b275058dbac0d0ec198b1b962a94450e80fcc2f59ba81166fd085f');
  assert.equal(inv.entry_count, 3); assert.equal(inv.total_blob_bytes, 16);
});
test('The inventory ignores working-tree files and core.autocrlf', async () => {
  const dir = temp(), gitDir = path.join(dir, '.git');
  fixtureGit(dir, ['init', '--quiet', '.']);
  const c = fixtureCommit(gitDir, [{ path: 'text.txt', text: 'one\ntwo\n' }, { path: 'crlf.txt', text: 'three\r\n' }]);
  const expected = Buffer.concat([inventoryLine('100644', 'three\r\n', 'crlf.txt'), inventoryLine('100644', 'one\ntwo\n', 'text.txt')]);
  const before = await inventoryOf(gitDir, c);
  assert.deepEqual(before.text, expected);
  fixtureGit(dir, ['config', 'core.autocrlf', 'true']);
  fixtureGit(dir, ['read-tree', c]); fixtureGit(dir, ['checkout-index', '--all', '--force']);
  assert.equal(fs.readFileSync(path.join(dir, 'text.txt'), 'latin1'), 'one\r\ntwo\r\n', 'The fixture must exercise conversion.');
  put(dir, 'crlf.txt', 'edited in the working tree\n'); put(dir, 'untracked.txt', 'untracked\n');
  assert.deepEqual(await inventoryOf(gitDir, c), before);
});
test('A changed blob, an added file, a removed file, and a renamed file each change the inventory digest', async () => {
  const g = bareRepo(), base = [{ path: 'a.txt', text: 'a\n' }, { path: 'd/b.txt', text: 'b\n' }];
  const digest = async files => (await inventoryOf(g, fixtureCommit(g, files))).sha256;
  const original = await digest(base), seen = new Set([original]);
  assert.equal(await digest([...base].reverse()), original);
  for (const [change, files] of Object.entries({ changed: [{ path: 'a.txt', text: 'A\n' }, base[1]],
    added: [...base, { path: 'c.txt', text: 'c\n' }], removed: [base[0]], renamed: [{ path: 'renamed.txt', text: 'a\n' }, base[1]] })) {
    const d = await digest(files);
    assert.ok(!seen.has(d), `The ${change} file did not produce a new digest.`); seen.add(d);
  }
});
test('Paths with spaces, non-ASCII bytes, and tabs keep their exact bytes through NUL-separated parsing', async () => {
  const g = bareRepo(), names = [Buffer.from('dir with space/file name.txt'), Buffer.from('caf\u00e9/na\u00efve.txt'),
    Buffer.from('\u{1F600}.txt'), Buffer.from('\uFF61.txt'), Buffer.from([0x72, 0x61, 0x77, 0xff, 0xfe, 0x2e, 0x62]), Buffer.from('tab\there.txt')];
  const c = fixtureCommit(g, names.map((p, i) => ({ path: p, text: `${i}\n` })));
  const entries = await listTree(g, c);
  assert.deepEqual(entries.map(e => e.path).sort(Buffer.compare), [...names].sort(Buffer.compare));
  const inv = await computeInventory(g, entries, { keepLines: true });
  const byBytes = names.map((p, i) => [p, inventoryLine('100644', `${i}\n`, p)]).sort((a, b) => Buffer.compare(a[0], b[0]));
  assert.deepEqual(inv.text, Buffer.concat(byBytes.map(x => x[1])));
  // UTF-16 order puts U+1F600 first; UTF-8 byte order puts U+FF61 first.
  assert.ok(inv.text.indexOf(Buffer.from('\uFF61.txt')) < inv.text.indexOf(Buffer.from('\u{1F600}.txt')));
});
test('A symbolic link entry hashes its target text, and a submodule entry records its commit ID', async () => {
  const g = bareRepo(), sub = '0123456789abcdef0123456789abcdef01234567';
  const c = fixtureCommit(g, [{ path: 'link', text: 'target/file.txt', mode: '120000' }, { path: 'vendor/lib', submodule: sub }]);
  const inv = await inventoryOf(g, c);
  assert.equal(inv.text.toString('latin1'), `120000\t${sha256('target/file.txt')}\t15\tlink\n160000\t${sub}\t0\tvendor/lib\n`);
  assert.equal(inv.entry_count, 2); assert.equal(inv.total_blob_bytes, 15);
});
const T262_LICENSE = { path: 'LICENSE', text: 'Fixture ("Software") is being made available under the  "BSD License", included below.\n' };
const T262_FILES = [T262_LICENSE, { path: 'test/language/a.js', text: 'a;\n' }, { path: 'test/harness/h_FIXTURE.js', text: 'h;\n' }];
const WPT_FILES = [{ path: 'LICENSE.md', text: '# The 3-Clause BSD License\n\nFixture text.\n' },
  { path: 'dom/a.html', text: 'a\n' }, { path: 'dom/b.any.js', text: 'b\n' }, { path: 'dom/r.html', text: 'r\n' },
  { path: 'dom/r-ref.html', text: 'ref\n' }, { path: 'dom/m-manual.html', text: 'm\n' }, { path: 'dom/s.html', text: 's\n' },
  { path: 'third_party/test262/vendored.toml', text: '[test262]\nsource = "https://github.com/tc39/test262"\nrev = "7ab7fafa0003f73fc85c1b95d88094d33f7eb8bd"\n' },
  { path: 'third_party/test262/test/t.js', text: 't\n' }];
/** A manifest in the upstream format: each file maps to its blob ID followed by one entry per test URL. */
const wptManifest = oid => ({ items: {
  manual: { dom: { 'm-manual.html': [oid('dom/m-manual.html'), [null, {}]] } },
  reftest: { dom: { 'r.html': [oid('dom/r.html'), [null, [['/dom/r-ref.html', '==']], {}]] } },
  spec: { dom: { 's.html': [oid('dom/s.html'), ['https://example.invalid/spec', {}]] } },
  support: { dom: { 'r-ref.html': [oid('dom/r-ref.html'), [null, {}]] } },
  test262: { third_party: { test262: { test: { 't.js': [oid('third_party/test262/test/t.js'),
    ['third_party/test262/test/t.test262.html', {}], ['third_party/test262/test/t.test262-strict.html', {}]] } } } },
  testharness: { dom: { 'a.html': [oid('dom/a.html'), [null, {}]],
    'b.any.js': [oid('dom/b.any.js'), ['dom/b.any.html', {}], ['dom/b.any.worker.html', {}]] } },
}, url_base: '/', version: 9 });
/** A counted record for a corpus that a fixture does not snapshot, so every applicability record has a denominator. */
function otherApplicability(dir, id) {
  const location = FILE_SET_IDS.includes(id) ? { version: 'fixture', inventories: { fixture: 'a'.repeat(64) } } : { commit: 'a'.repeat(40) };
  writeJson(path.join(dir, 'specs/applicability', `${id}.json`), { schema_version: 1, corpus: id, ...location, status: 'counted',
    discovery: { rule: 'Fixture rule.' }, discovered: 1, selected: 0, excluded: [], unclassified: 1, breakdown: { by: 'fixture', counts: { fixture: 1 } } });
}
/** Counted records for every pinnable corpus except `id`. */
function otherApplicabilities(dir, id) {
  for (const other of ['test262', 'wpt', ...FILE_SET_IDS]) if (other !== id) otherApplicability(dir, other);
}
/** The repository's corpus policy with every pin removed, so a fixture snapshot meets only the pins that its test sets. */
function unpinnedCorpora() {
  const policy = readJson(path.join(root, 'specs/corpora.json'));
  for (const corpus of policy.corpora) {
    for (const field of ['revision', 'license_record', 'inventory_sha256', 'manifest_sha256', 'local_path']) if (field in corpus) corpus[field] = null;
    corpus.status = 'not-fetched';
  }
  return policy;
}
/** A fixture repository root with a snapshot of corpus `id`, its snapshot record, and its applicability record. */
async function corpusFixture(id, files, { manifest } = {}) {
  const dir = temp(), corporaDir = temp(), g = bareRepo(snapshotGitDir(corporaDir, id));
  const policyFile = path.join(dir, 'specs/corpora.json');
  fs.mkdirSync(path.dirname(policyFile)); writeJson(policyFile, unpinnedCorpora());
  const commit = fixtureCommit(g, files), ref = id === 'wpt' ? 'refs/heads/master' : 'refs/heads/main';
  fixtureGit(g, ['update-ref', ref, commit]);
  let manifestFile;
  if (manifest) {
    manifestFile = corpus.snapshotManifest(corporaDir, id);
    fs.writeFileSync(manifestFile, JSON.stringify(manifest(p => fixtureGit(g, ['rev-parse', `${commit}:${p}`]))));
  }
  const upstream = readJson(policyFile).corpora.find(c => c.id === id).upstream;
  const record = await buildSnapshotRecord(g, { corpus: id, upstream, ref, commit, retrieved_at: '2026-10-08T00:00:00.000Z' }, { manifestFile });
  const recordFile = path.join(dir, 'specs/snapshots', `${id}.json`); writeJson(recordFile, record);
  otherApplicabilities(dir, id);
  const applicability = await classifyCorpus(dir, id, { corporaDir });
  return { dir, corporaDir, g, commit, record, recordFile, policyFile, manifestFile, applicability,
    applicabilityFile: path.join(dir, 'specs/applicability', `${id}.json`),
    verify: (options = {}) => verifyCorpus(dir, id, { corporaDir, ...options }) };
}
test('corpus-verify fails for a missing snapshot, a missing record, a wrong commit, a wrong tree, and a wrong inventory digest', async () => {
  const f = await corpusFixture('test262', T262_FILES), { record } = f;
  const second = fixtureCommit(f.g, [T262_LICENSE, { path: 'test/language/a.js', text: 'changed;\n' }], [f.commit]);
  assert.equal(record.commit_date, '2026-01-02T04:34:05+01:30'); assert.equal(record.license.name, 'BSD License');
  assert.equal(f.applicability.discovered, 1);
  assert.equal((await f.verify()).result, 'pass');
  await assert.rejects(() => f.verify({ corporaDir: temp() }), /Missing snapshot:/);
  const wrong = [[{ commit: second }, /commit at refs\/heads\/main: recorded/], [{ commit: 'f'.repeat(40) }, /does not contain commit/],
    [{ tree: fixtureGit(f.g, ['rev-parse', `${second}^{tree}`]) }, /tree: recorded/],
    [{ inventory: { ...record.inventory, sha256: '0'.repeat(64) } }, /inventory\.sha256: recorded/]];
  for (const [change, message] of wrong) {
    writeJson(f.recordFile, { ...record, ...change }); await assert.rejects(f.verify, message);
  }
  fs.rmSync(f.recordFile); await assert.rejects(f.verify, /Missing snapshot record/);
  const cli = spawnSync(process.execPath, [path.join(root, 'tools/fairpane.mjs'), 'corpus-verify', 'test262'],
    { cwd: root, encoding: 'utf8', env: { ...process.env, FAIRPANE_CORPORA_DIR: temp() }, windowsHide: true });
  assert.equal(cli.status, 1); assert.match(cli.stderr, /Missing snapshot/);
});
test('Applicability validation rejects negative counts, non-integer counts, inconsistent sums, and exclusions without reasons', () => {
  const good = { schema_version: 1, corpus: 'test262', commit: 'a'.repeat(40), status: 'counted', discovery: { rule: 'Fixture rule.' },
    discovered: 3, selected: 1, excluded: [{ path: 'test/x.js', reason: 'Fixture reason.' }], unclassified: 1,
    breakdown: { by: 'directory', counts: { a: 2, b: 1 } } };
  assert.equal(validateApplicability(good), true);
  for (const [change, message] of [[{ selected: -1, unclassified: 3 }, /nonnegative integer/], [{ unclassified: 0.5 }, /nonnegative integer/],
    [{ discovered: '3' }, /nonnegative integer/], [{ unclassified: 2 }, /inconsistent/],
    [{ excluded: [{ path: 'test/x.js', reason: ' ' }] }, /no reason/], [{ excluded: [{ path: 'test/x.js' }] }, /no reason/]])
    assert.throws(() => validateApplicability({ ...good, ...change }), message);
});
test('Snapshot record validation rejects a non-40-hex commit, a missing license digest, and a missing inventory digest', () => {
  const good = { schema_version: 1, corpus: 'test262', upstream: 'https://github.com/tc39/test262', ref: 'refs/heads/main',
    commit: 'a'.repeat(40), tree: 'b'.repeat(40), commit_date: '2026-10-08T13:50:06+02:00', retrieved_at: '2026-10-09T00:31:30.626Z',
    license: { path: 'LICENSE', size: 1, sha256: 'c'.repeat(64), name: 'BSD License' },
    inventory: { entry_count: 1, total_blob_bytes: 1, sha256: 'd'.repeat(64) } };
  assert.equal(validateSnapshotRecord(good), true);
  for (const commit of ['a'.repeat(39), 'a'.repeat(41), 'A'.repeat(40), 'g'.repeat(40), 'HEAD'])
    assert.throws(() => validateSnapshotRecord({ ...good, commit }), /commit must be 40/);
  const { sha256: _license, ...license } = good.license, { sha256: _inventory, ...inventory } = good.inventory;
  assert.throws(() => validateSnapshotRecord({ ...good, license }), /license SHA-256/);
  assert.throws(() => validateSnapshotRecord({ ...good, inventory }), /inventory SHA-256/);
});
test('Verification fails when the license digest, the commit date, or an applicability count differs from its record', async () => {
  const f = await corpusFixture('test262', T262_FILES);
  assert.equal((await f.verify()).result, 'pass');
  for (const [change, message] of [[{ license: { ...f.record.license, sha256: '0'.repeat(64) } }, /license\.sha256: recorded/],
    [{ commit_date: '2026-01-02T04:34:06+01:30' }, /commit_date: recorded/]]) {
    writeJson(f.recordFile, { ...f.record, ...change }); await assert.rejects(f.verify, message);
  }
  writeJson(f.recordFile, f.record);
  const a = readJson(f.applicabilityFile);
  writeJson(f.applicabilityFile, { ...a, discovered: a.discovered + 1, unclassified: a.unclassified + 1,
    breakdown: { ...a.breakdown, counts: { ...a.breakdown.counts, extra: 1 } } });
  await assert.rejects(f.verify, /applicability: the recorded discovery differs from the snapshot/);
  writeJson(f.applicabilityFile, a);
  assert.equal((await f.verify()).result, 'pass');
  // A record without a denominator, here the other corpus's record, keeps the top-level result from passing.
  const wptFile = path.join(f.dir, 'specs/applicability/wpt.json');
  writeJson(wptFile, { ...readJson(wptFile), discovered: null, unclassified: null });
  const incomplete = await f.verify();
  assert.equal(incomplete.result, 'incomplete'); assert.deepEqual(incomplete.missing_denominators.map(m => m.corpus), ['wpt']);
  fs.rmSync(wptFile);
  assert.equal((await f.verify()).result, 'incomplete');
});
test('corpus-verify exits with status 1 through the controller command on an inventory digest mismatch', async () => {
  const f = await corpusFixture('test262', T262_FILES);
  for (const file of fs.readdirSync(path.join(root, 'tools')).filter(name => name.endsWith('.mjs'))) put(f.dir, `tools/${file}`, fs.readFileSync(path.join(root, 'tools', file)));
  const cli = () => spawnSync(process.execPath, [path.join(f.dir, 'tools/fairpane.mjs'), 'corpus-verify', 'test262'],
    { cwd: f.dir, encoding: 'utf8', env: { ...process.env, FAIRPANE_CORPORA_DIR: f.corporaDir }, windowsHide: true });
  const pass = cli();
  assert.equal(pass.status, 0, pass.stderr); assert.equal(JSON.parse(pass.stdout).result, 'pass');
  writeJson(f.recordFile, { ...f.record, inventory: { ...f.record.inventory, sha256: '0'.repeat(64) } });
  const fail = cli();
  assert.equal(fail.status, 1); assert.match(fail.stderr, /inventory\.sha256: recorded "0{64}"/);
});
test('A replace ref that substitutes the recorded commit cannot make verification pass', async () => {
  const f = await corpusFixture('test262', T262_FILES);
  // An inherited Git variable must not reach the controller's Git processes.
  const saved = process.env.GIT_OBJECT_DIRECTORY;
  process.env.GIT_OBJECT_DIRECTORY = temp();
  try { assert.equal((await f.verify()).result, 'pass'); }
  finally { if (saved === undefined) delete process.env.GIT_OBJECT_DIRECTORY; else process.env.GIT_OBJECT_DIRECTORY = saved; }
  const fake = fixtureCommit(f.g, [T262_LICENSE, { path: 'test/language/b.js', text: 'b;\n' }]);
  fixtureGit(f.g, ['replace', '-f', fake, f.commit]);
  assert.equal(fixtureGit(f.g, ['rev-parse', `${fake}^{tree}`]), f.record.tree, 'Git that honors replace refs must read the fake ID as the recorded commit.');
  fixtureGit(f.g, ['update-ref', 'refs/heads/main', fake]);
  writeJson(f.recordFile, { ...f.record, commit: fake });
  writeJson(f.applicabilityFile, { ...readJson(f.applicabilityFile), commit: fake });
  await assert.rejects(f.verify, /tree: recorded/);
  // Verification rehashes every stored object, so an object whose content does not match its ID fails even when nothing references it.
  const g = await corpusFixture('test262', T262_FILES), forged = 'f'.repeat(40);
  const objectFile = id => path.join(g.g, 'objects', id.slice(0, 2), id.slice(2));
  fs.mkdirSync(path.dirname(objectFile(forged)), { recursive: true }); fs.copyFileSync(objectFile(g.commit), objectFile(forged));
  await assert.rejects(g.verify, e => /fsck: git fsck exited with status/.test(e.message) && !/tree:|commit_date:|inventory\.|applicability/.test(e.message));
}, { processWide: 'GIT_OBJECT_DIRECTORY in process.env' });
test('A tree path that contains a line feed fails the inventory', async () => {
  const g = bareRepo(), c = fixtureCommit(g, [{ path: 'a\nb.txt', text: 'x\n' }, { path: 'ok.txt', text: 'y\n' }]);
  await assert.rejects(() => inventoryOf(g, c), /line feed/);
});
test('WPT counting of a fixture manifest reports per-type counts, excludes support, spec, and test262 from discovery, and reports test262 separately', async () => {
  const f = await corpusFixture('wpt', WPT_FILES, { manifest: wptManifest }), a = f.applicability;
  assert.deepEqual(a.manifest.item_counts, { manual: 1, reftest: 1, spec: 1, support: 1, test262: 2, testharness: 3 });
  assert.deepEqual(a.breakdown.counts, { manual: 1, reftest: 1, testharness: 3 });
  assert.equal(a.discovered, 5); assert.equal(a.selected, 0); assert.deepEqual(a.excluded, []); assert.equal(a.unclassified, 5);
  assert.equal(a.reported_separately.test262.items, 2);
  assert.deepEqual(a.reported_separately.test262.vendored,
    { path: 'third_party/test262/vendored.toml', source: 'https://github.com/tc39/test262', revision: '7ab7fafa0003f73fc85c1b95d88094d33f7eb8bd' });
  assert.deepEqual(f.record.manifest, { url: `https://wpt.fyi/api/manifest?sha=${f.commit}`,
    size: fs.statSync(f.manifestFile).size, sha256: fileHash(f.manifestFile) });
  assert.equal(a.manifest.sha256, f.record.manifest.sha256);
  assert.equal((await f.verify()).result, 'pass');
  const { manifest: _manifest, ...unbound } = f.record;
  assert.throws(() => validateSnapshotRecord(unbound), /manifest/);
});
test('A fixture manifest with a path that the tree lacks, or with a hash that differs from the blob ID, fails binding', async () => {
  const f = await corpusFixture('wpt', WPT_FILES, { manifest: wptManifest });
  const entries = await listTree(f.g, f.commit), good = readJson(f.manifestFile);
  assert.deepEqual(corpus.bindWptManifest(good, entries), { paths: 7 });
  const missing = clone(good);
  missing.items.testharness.dom['gone.html'] = ['a'.repeat(40), [null, {}]];
  assert.throws(() => corpus.bindWptManifest(missing, entries), /dom\/gone\.html: the pinned tree has no such path/);
  const changed = clone(good);
  changed.items.support.dom['r-ref.html'][0] = good.items.testharness.dom['a.html'][0];
  assert.throws(() => corpus.bindWptManifest(changed, entries), /dom\/r-ref\.html: the manifest hash .* differs from blob/);
  // Verification rebinds the stored manifest even when the record carries the altered manifest's digest.
  fs.writeFileSync(f.manifestFile, JSON.stringify(changed));
  writeJson(f.recordFile, { ...f.record, manifest: { ...f.record.manifest, size: fs.statSync(f.manifestFile).size, sha256: fileHash(f.manifestFile) } });
  await assert.rejects(f.verify, /dom\/r-ref\.html: the manifest hash .* differs from blob/);
  // The download accepts only a response whose x-wpt-sha header names the pinned commit.
  const body = Buffer.from('{"items":{},"url_base":"/","version":9}');
  let served = f.commit;
  const server = http.createServer((_, res) => { res.writeHead(200, { 'content-type': 'application/json', 'x-wpt-sha': served }); res.end(body); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}/api/manifest?sha=${f.commit}`, file = path.join(temp(), 'MANIFEST.json');
    assert.deepEqual(await corpus.downloadWptManifest(f.commit, file, { url }), { url, size: body.length, sha256: sha256(body) });
    assert.deepEqual(fs.readFileSync(file), body);
    served = 'b'.repeat(40);
    const rejected = path.join(temp(), 'MANIFEST.json');
    await assert.rejects(() => corpus.downloadWptManifest(f.commit, rejected, { url }), /x-wpt-sha/);
    assert.equal(fs.existsSync(rejected), false);
  } finally { server.close(); server.closeAllConnections(); }
});
test('A pinned revision in a fixture corpora.json makes verification fail for a snapshot at another commit, inventory digest, or manifest digest', async () => {
  const f = await corpusFixture('wpt', WPT_FILES, { manifest: wptManifest }), policy = readJson(f.policyFile);
  const pin = change => {
    const p = clone(policy), file = path.join(temp(), 'corpora.json');
    Object.assign(p.corpora.find(c => c.id === 'wpt'), { revision: f.commit, license_record: 'specs/snapshots/wpt.json',
      inventory_sha256: f.record.inventory.sha256, manifest_sha256: f.record.manifest.sha256 }, change);
    writeJson(file, p); return file;
  };
  assert.equal((await f.verify({ policyFile: pin({}) })).result, 'pass');
  for (const [change, message] of [[{ revision: 'c'.repeat(40) }, /pin revision: pinned "c{40}"/],
    [{ inventory_sha256: '0'.repeat(64) }, /pin inventory_sha256: pinned "0{64}"/],
    [{ manifest_sha256: '0'.repeat(64) }, /pin manifest_sha256: pinned "0{64}"/],
    [{ license_record: 'specs/snapshots/other.json' }, /pin license_record: pinned "specs\/snapshots\/other\.json"/]])
    await assert.rejects(() => f.verify({ policyFile: pin(change) }), message);
});
test('Test262 discovery excludes a file named a_FIXTURE_b.js and a file named x_FIXTURE.js', async () => {
  const g = bareRepo(), c = fixtureCommit(g, [{ path: 'test/language/a_FIXTURE_b.js', text: 'a;\n' },
    { path: 'test/language/x_FIXTURE.js', text: 'x;\n' }, { path: 'test/language/y.js', text: 'y;\n' }]);
  const a = test262Applicability(c, await listTree(g, c));
  assert.equal(a.discovered, 1); assert.deepEqual(a.breakdown.counts, { language: 1 });
});
/** WPT fixture files with `test262` items in the vendored copy's tests, its harness includes, and WPT's own `infrastructure/test262/`. */
const WPT_TEST262_FILES = [...WPT_FILES, { path: 'third_party/test262/harness/assert.js', text: 'assert\n' },
  { path: 'infrastructure/test262/basic.js', text: 'basic\n' }];
function wptTest262Manifest(oid) {
  const m = wptManifest(oid);
  m.items.test262.third_party.test262.harness = { 'assert.js': [oid('third_party/test262/harness/assert.js'), ['third_party/test262/harness/assert.test262.html', {}]] };
  m.items.test262.infrastructure = { test262: { 'basic.js': [oid('infrastructure/test262/basic.js'), ['infrastructure/test262/basic.test262.html', {}]] } };
  return m;
}
test('A fixture manifest with test262 items under the vendored tests, the vendored harness, and infrastructure/test262/ counts only the infrastructure item and reports the others by path', async () => {
  const f = await corpusFixture('wpt', WPT_TEST262_FILES, { manifest: wptTest262Manifest }), a = f.applicability;
  assert.deepEqual(a.manifest.item_counts, { manual: 1, reftest: 1, spec: 1, support: 1, test262: 4, testharness: 3 });
  assert.deepEqual(a.breakdown.counts, { manual: 1, reftest: 1, test262: 1, testharness: 3 });
  assert.equal(a.discovered, 6); assert.equal(a.unclassified, 6); assert.deepEqual(a.excluded, []);
  assert.deepEqual(a.reported_separately.test262, {
    path: 'third_party/test262/', items: 3,
    by_prefix: {
      'third_party/test262/harness/': { items: 1, content: 'Test262 harness includes, not tests' },
      'third_party/test262/test/': { items: 2, content: 'Test262 tests' },
    },
    vendored: { path: 'third_party/test262/vendored.toml', source: 'https://github.com/tc39/test262', revision: '7ab7fafa0003f73fc85c1b95d88094d33f7eb8bd' },
    reason: a.reported_separately.test262.reason,
  });
  assert.match(a.reported_separately.test262.reason, /third_party\/test262\//);
  assert.ok(!JSON.stringify(a.reported_separately).includes('infrastructure'), 'The WPT-authored test262 item is not attributed to the vendored copy.');
  assert.match(a.discovery.rule, /infrastructure\/test262\//);
  assert.equal((await f.verify()).result, 'pass');
});
test('A manifest without test items fails binding, and an applicability record with zero discovered tests fails validation', async () => {
  const f = await corpusFixture('wpt', WPT_FILES, { manifest: wptManifest });
  const entries = await listTree(f.g, f.commit), good = readJson(f.manifestFile);
  // Support, spec, and vendored test262 items are not tests, so a manifest with only those items has no denominator.
  const notTests = { ...good, items: { spec: good.items.spec, support: good.items.support, test262: good.items.test262 } };
  for (const m of [{ items: {}, url_base: '/', version: 9 }, notTests])
    assert.throws(() => corpus.bindWptManifest(m, entries), /The WPT manifest has no test items/);
  fs.writeFileSync(f.manifestFile, JSON.stringify(notTests));
  writeJson(f.recordFile, { ...f.record, manifest: { ...f.record.manifest, size: fs.statSync(f.manifestFile).size, sha256: fileHash(f.manifestFile) } });
  await assert.rejects(f.verify, /manifest: The WPT manifest has no test items/);
  await assert.rejects(() => classifyCorpus(f.dir, 'wpt', { corporaDir: f.corporaDir }), /The WPT manifest has no test items/);
  const zero = { schema_version: 1, corpus: 'test262', commit: 'a'.repeat(40), status: 'counted', discovery: { rule: 'Fixture rule.' },
    discovered: 0, selected: 0, excluded: [], unclassified: 0, breakdown: { by: 'directory', counts: {} } };
  assert.throws(() => validateApplicability(zero), /zero discovered tests/);
  const g = bareRepo(), c = fixtureCommit(g, [T262_LICENSE, { path: 'test/harness/only_FIXTURE.js', text: 'x;\n' }]);
  const noTests = test262Applicability(c, await listTree(g, c));
  assert.equal(noTests.discovered, 0); assert.throws(() => validateApplicability(noTests), /zero discovered tests/);
});
// FP-0082 case 18: corpus-extract.
const T262_EXTRACT_FILES = [...T262_FILES, { path: 'harness/assert.js', text: 'assert;\n' },
  { path: 'features.txt', text: '## Proposed language features\n\n## Standard language features\n' }, { path: 'README.md', text: 'Not extracted.\n' }];
/** Every file under `dir` as a sorted list of `[relative path with "/", contents]`. */
function extractedFiles(dir) {
  const files = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else files.push([path.relative(dir, p).split(path.sep).join('/'), fs.readFileSync(p, 'utf8')]);
    }
  };
  walk(dir);
  return files.sort(([a], [b]) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}
test('FP-0082 case 18: corpus-extract writes exactly the test/ and harness/ blobs and features.txt, and an EXTRACT.json record', async () => {
  const f = await corpusFixture('test262', T262_EXTRACT_FILES);
  const out = path.join(f.dir, 'out', 'extract');
  const r = await corpus.extractCorpus(f.dir, 'test262', out, { corporaDir: f.corporaDir });
  const written = ['features.txt', 'harness/assert.js', 'test/harness/h_FIXTURE.js', 'test/language/a.js'];
  const text = p => T262_EXTRACT_FILES.find(x => x.path === p).text;
  const files = extractedFiles(out);
  assert.deepEqual(files.map(([p]) => p), ['EXTRACT.json', ...written]);
  for (const [p, contents] of files) if (p !== 'EXTRACT.json') assert.equal(contents, text(p), `${p} differs from its blob.`);
  const lines = written.map(p => `${fixtureGit(f.g, ['rev-parse', `${f.commit}:${p}`])} ${p}\n`).join('');
  const expected = { schema_version: 1, corpus: 'test262', commit: f.commit, tree: f.record.tree, files: 4, entries_sha256: sha256(lines) };
  assert.deepEqual(readJson(path.join(out, 'EXTRACT.json')), expected);
  assert.equal(r.result, 'pass'); assert.equal(r.files, 4); assert.equal(r.entries_sha256, expected.entries_sha256);
});
test('FP-0082 case 18: corpus-extract refuses a non-empty output directory, a directory outside out/, and an absent commit', async () => {
  const f = await corpusFixture('test262', T262_EXTRACT_FILES), options = { corporaDir: f.corporaDir };
  const full = path.join(f.dir, 'out', 'full');
  put(full, 'stale.txt', 'A file from an earlier run.\n');
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', full, options), /must be absent or empty/);
  assert.deepEqual(fs.readdirSync(full), ['stale.txt']);
  for (const outside of [path.join(f.dir, 'extract'), path.join(f.dir, 'out'), temp(), path.join(f.dir, 'out', '..', 'x')])
    await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', outside, options), /must lie under/);
  writeJson(f.recordFile, { ...f.record, commit: 'f'.repeat(40) });
  const absent = path.join(f.dir, 'out', 'absent');
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', absent, options), /does not contain commit/);
  assert.equal(fs.existsSync(absent), false);
});
test('FP-0082 case 18: the shared path rule rejects empty, ".", and ".." components, and extraction rejects other modes', async () => {
  for (const bad of ['test/../x', 'test//x', 'test/./x', '/test/x', 'test/x/', '..', '.'])
    assert.equal(lib.relativePathProblem(bad) !== null, true, `${bad} passed the path rule.`);
  for (const good of ['test/x.js', 'harness/a.b.js', 'test/..x/y'])
    assert.equal(lib.relativePathProblem(good), null, `${good} failed the path rule.`);
  const f = await corpusFixture('test262', [...T262_EXTRACT_FILES, { path: 'test/link.js', text: 'test/language/a.js', mode: '120000' }]);
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', path.join(f.dir, 'out', 'x'), { corporaDir: f.corporaDir }),
    /test\/link\.js has mode 120000/);
  const g = await corpusFixture('test262', [...T262_EXTRACT_FILES, { path: 'test/run.sh', text: 'true\n', mode: '100755' }]);
  const r = await corpus.extractCorpus(g.dir, 'test262', path.join(g.dir, 'out', 'x'), { corporaDir: g.corporaDir });
  assert.equal(r.files, 5);
});
test('FP-0082 case 18: corpus-extract rejects a stored blob whose content does not hash to its tree object ID', async () => {
  const f = await corpusFixture('test262', T262_EXTRACT_FILES);
  const blob = p => fixtureGit(f.g, ['rev-parse', `${f.commit}:${p}`]);
  const objectFile = id => path.join(f.g, 'objects', id.slice(0, 2), id.slice(2));
  // Git reads a loose object without rehashing it, so the altered file yields other content under the listed ID.
  const target = objectFile(blob('test/language/a.js'));
  fs.chmodSync(target, 0o644); fs.copyFileSync(objectFile(blob('harness/assert.js')), target);
  // The snapshot record agrees with the altered objects, so only the blob-hash check can find the alteration.
  writeJson(f.recordFile, { ...f.record, inventory: await computeInventory(f.g, await listTree(f.g, f.commit)) });
  const out = path.join(f.dir, 'out', 'altered');
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', out, { corporaDir: f.corporaDir }),
    /test\/language\/a\.js: the written file hashes to [0-9a-f]{40}, not to its tree object ID/);
  assert.equal(fs.existsSync(path.join(out, 'EXTRACT.json')), false);
});
// FP-0082 revision 1, case 2: one shared path rule, with the tree path, the reason, and the path that the write would reach.
test('FP-0082 case 18: the shared path rule gives each reason, and null for ordinary paths', () => {
  for (const [bad, reason] of [['test/a\u0000b.js', 'a control character'], ['test\\a.js', 'a backslash'], ['test/a:b.js', 'a colon'],
    ['test//a.js', 'an empty path component'], ['test/./a.js', 'a "." path component'], ['test/../a.js', 'a ".." path component'],
    ['test/a./b.js', 'a path component that ends in "." or a space'], ['test/nul.txt', 'a reserved Windows device name']])
    assert.equal(lib.relativePathProblem(bad), reason, JSON.stringify(bad));
  for (const good of ['test/a/b.js', 'harness/assert.js']) assert.equal(lib.relativePathProblem(good), null, good);
});
const HOSTILE_EXTRACT_PATHS = [
  ['test/..\\..\\..\\x.js', 'a backslash', '../../x.js'],
  ['test/a:b.js', 'a colon', 'test/a'],
  ['test/a\u0001b.js', 'a control character', 'test/a\u0001b.js'],
  ['test/dir./x.js', 'a path component that ends in "." or a space', 'test/dir/x.js'],
  ['test/x.js ', 'a path component that ends in "." or a space', 'test/x.js'],
  ['test/CON.js', 'a reserved Windows device name', 'test/CON.js'],
  ['test/aux/x.js', 'a reserved Windows device name', 'test/aux/x.js'],
  ['test/Com1.txt.js', 'a reserved Windows device name', 'test/Com1.txt.js'],
];
for (const [entry, reason, reach] of HOSTILE_EXTRACT_PATHS) {
  test(`FP-0082 case 18: corpus-extract refuses the tree path ${JSON.stringify(entry)}, which has ${reason}, and writes nothing`, async () => {
    const f = await corpusFixture('test262', [...T262_EXTRACT_FILES, { path: entry, text: 'escape;\n' }]);
    const out = path.join(f.dir, 'out', 'hostile');
    await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', out, { corporaDir: f.corporaDir }), { message: `${entry} has ${reason}.` });
    assert.equal(!fs.existsSync(out) || fs.readdirSync(out).length === 0, true, 'The output directory is not absent or empty.');
    // A directory listing finds the name without opening it, so a device name is never opened.
    const target = path.resolve(out, ...reach.split('/')), parent = path.dirname(target);
    assert.equal(fs.existsSync(parent) && fs.readdirSync(parent).includes(path.basename(target)), false, `${target} exists.`);
  });
}
// FP-0082 revision 1, case 3: the commit's tree and the inventory must match the snapshot record before extraction writes.
// Git rehashes the root tree of a commit when it reads it, but not a subtree that `git ls-tree -r` reaches, so the fixture
// alters the commit tree's `test/` subtree, as the integrator decided for revision 1.
test('FP-0082 case 18: corpus-extract refuses an altered tree object through the inventory and writes nothing', async () => {
  const f = await corpusFixture('test262', T262_EXTRACT_FILES);
  const other = fixtureCommit(f.g, [...T262_EXTRACT_FILES, { path: 'test/language/b.js', text: 'b;\n' }]);
  const objectFile = id => path.join(f.g, 'objects', id.slice(0, 2), id.slice(2));
  // The loose object file of the `test/` subtree becomes the valid zlib stream of another tree under the same object ID.
  const target = objectFile(fixtureGit(f.g, ['rev-parse', `${f.commit}:test`]));
  fs.chmodSync(target, 0o644); fs.copyFileSync(objectFile(fixtureGit(f.g, ['rev-parse', `${other}:test`])), target);
  const out = path.join(f.dir, 'out', 'altered-tree');
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', out, { corporaDir: f.corporaDir }), e => {
    assert.match(e.message, /^Corpus test262 failed extraction checks:\n/);
    assert.match(e.message, new RegExp(`^- inventory\\.sha256: recorded "${f.record.inventory.sha256}", found "[0-9a-f]{64}"$`, 'm'));
    return true;
  });
  assert.equal(!fs.existsSync(out) || fs.readdirSync(out).length === 0, true, 'The output directory is not absent or empty.');
});
test('FP-0082 case 18: corpus-extract refuses a snapshot record whose tree differs from the commit and writes nothing', async () => {
  const f = await corpusFixture('test262', T262_EXTRACT_FILES);
  writeJson(f.recordFile, { ...f.record, tree: 'f'.repeat(40) });
  const out = path.join(f.dir, 'out', 'other-tree');
  await assert.rejects(() => corpus.extractCorpus(f.dir, 'test262', out, { corporaDir: f.corporaDir }), e => {
    assert.match(e.message, /^Corpus test262 failed extraction checks:\n/);
    assert.match(e.message, new RegExp(`^- tree: recorded "${'f'.repeat(40)}", found "${f.record.tree}"$`, 'm'));
    return true;
  });
  assert.equal(!fs.existsSync(out) || fs.readdirSync(out).length === 0, true, 'The output directory is not absent or empty.');
});
/** Paths and SHA-256 digests of every file under `dir`, sorted. */
function directoryDigest(dir) {
  const lines = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else lines.push(`${path.relative(dir, p)}\t${fileHash(p)}`);
    }
  };
  walk(dir);
  return lines.sort().join('\n');
}
/** A local `file://` Test262 upstream whose HEAD is refs/heads/main, with an empty fixture repository root and corpora root. */
function upstreamFixture() {
  const upstream = bareRepo(), url = pathToFileURL(upstream).href, dir = temp(), corporaDir = temp();
  fixtureGit(upstream, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
  const first = fixtureCommit(upstream, T262_FILES);
  fixtureGit(upstream, ['update-ref', 'refs/heads/main', first]);
  const policy = pins => {
    const p = unpinnedCorpora(), file = path.join(temp(), 'corpora.json');
    Object.assign(p.corpora.find(c => c.id === 'test262'), { upstream: url }, pins);
    writeJson(file, p); return file;
  };
  const move = () => {
    const next = fixtureCommit(upstream, [T262_LICENSE, { path: 'test/language/a.js', text: 'moved;\n' }, { path: 'test/language/b.js', text: 'b;\n' }], [first]);
    fixtureGit(upstream, ['update-ref', 'refs/heads/main', next]); return next;
  };
  const options = policyFile => ({ corporaDir, policyFile, allowFileUpstream: true });
  const recordFile = path.join(dir, 'specs/snapshots/test262.json'), snapshot = snapshotGitDir(corporaDir, 'test262');
  const classify = () => { otherApplicabilities(dir, 'test262'); return classifyCorpus(dir, 'test262', { corporaDir, allowFileUpstream: true }); };
  return { upstream, url, dir, corporaDir, first, policy, move, options, recordFile, snapshot, classify,
    fetch: policyFile => corpus.fetchCorpus(dir, 'test262', options(policyFile)),
    verify: policyFile => verifyCorpus(dir, 'test262', options(policyFile)) };
}
test('corpus-fetch against a local fixture upstream fetches the pinned commit after the upstream branch moves', async () => {
  const u = upstreamFixture(), moved = u.move(), policyFile = u.policy({ revision: u.first });
  assert.notEqual(moved, u.first);
  const r = await u.fetch(policyFile);
  assert.equal(r.result, 'pass'); assert.equal(r.pinned_by, 'specs/corpora.json');
  assert.equal(r.commit, u.first); assert.equal(r.ref, 'refs/heads/main'); assert.equal(r.upstream, u.url);
  assert.equal(fixtureGit(u.snapshot, ['rev-parse', 'refs/heads/main']), u.first);
  const has = spawnSync('git', ['--git-dir', u.snapshot, 'cat-file', '-e', `${moved}^{commit}`], { env: fixtureEnv, windowsHide: true });
  assert.notEqual(has.status, 0, 'The snapshot must not contain the moved branch head.');
  const record = readJson(u.recordFile);
  assert.equal(record.commit, u.first); assert.equal(record.tree, fixtureGit(u.upstream, ['rev-parse', `${u.first}^{tree}`]));
  for (const [k, v] of Object.entries(record)) assert.deepEqual(r[k], v, `The command result and the record differ at ${k}.`);
  assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262']);
  await u.classify();
  assert.equal((await u.verify(policyFile)).result, 'pass');
  // Without a policy revision, the snapshot record pins the commit, so a refetch still ignores the moved branch.
  const fallback = await u.fetch(u.policy({}));
  assert.equal(fallback.pinned_by, 'specs/snapshots/test262.json'); assert.equal(fallback.commit, u.first);
  assert.equal(fallback.inventory.sha256, record.inventory.sha256);
});
test('A fetched snapshot whose record differs from its pin leaves the existing snapshot and record unchanged', async () => {
  const u = upstreamFixture();
  await u.fetch(u.policy({ revision: u.first }));
  const recordBytes = fs.readFileSync(u.recordFile), before = directoryDigest(path.join(u.corporaDir, 'test262'));
  put(u.corporaDir, 'test262.fetch/stale.txt', 'A stale staging directory from an interrupted fetch.\n');
  for (const [pins, message] of [[{ inventory_sha256: '0'.repeat(64) }, /pin inventory_sha256: pinned "0{64}"/],
    [{ license_record: 'specs/snapshots/other.json' }, /pin license_record: pinned "specs\/snapshots\/other\.json"/]]) {
    await assert.rejects(() => u.fetch(u.policy({ revision: u.first, ...pins })),
      e => /does not match its pin, so the existing snapshot stays/.test(e.message) && message.test(e.message));
    assert.deepEqual(fs.readFileSync(u.recordFile), recordBytes);
    assert.equal(directoryDigest(path.join(u.corporaDir, 'test262')), before);
    assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262']);
  }
});
test('corpus-repin against a local fixture upstream moves the snapshot to the new head and reports the pin differences', async () => {
  const u = upstreamFixture(), first = await u.fetch(u.policy({ revision: u.first }));
  const policyFile = u.policy({ revision: u.first, inventory_sha256: first.inventory.sha256, license_record: 'specs/snapshots/test262.json' });
  const head = u.move();
  const r = await corpus.repinCorpus(u.dir, 'test262', u.options(policyFile));
  assert.equal(r.result, 'pass'); assert.equal(r.commit, head); assert.equal(r.ref, 'refs/heads/main');
  assert.notEqual(r.inventory.sha256, first.inventory.sha256);
  assert.deepEqual(r.pin_differences, [`pin revision: pinned "${u.first}", snapshot has "${head}"`,
    `pin inventory_sha256: pinned "${first.inventory.sha256}", snapshot has "${r.inventory.sha256}"`]);
  assert.match(r.note, /corpus-verify fails until a protected change to specs\/corpora\.json records the new pin/);
  assert.equal(fixtureGit(u.snapshot, ['rev-parse', 'refs/heads/main']), head);
  assert.equal(readJson(u.recordFile).commit, head);
  assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262']);
  assert.equal((await u.classify()).discovered, 2);
  await assert.rejects(() => u.verify(policyFile), e => /pin revision: pinned/.test(e.message) && /pin inventory_sha256: pinned/.test(e.message));
  assert.equal((await u.verify(u.policy({ revision: head, inventory_sha256: r.inventory.sha256 }))).result, 'pass');
});
// FP-0052: system programs by full path, the shared write phase of the Git corpus fetch, and the fetch lock.
test('FP-0052 case 1: the system-directory resolver returns the System32 path and names SystemRoot when it cannot', () => {
  assert.equal(lib.windowsSystemProgram('taskkill.exe', { SystemRoot: 'C:\\Windows' }), 'C:\\Windows\\System32\\taskkill.exe');
  for (const env of [{}, { SystemRoot: '' }, { SystemRoot: 'Windows' }])
    assert.throws(() => lib.windowsSystemProgram('taskkill.exe', env), /SystemRoot/, JSON.stringify(env));
});
/**
 * The program that case 2 hard-links or copies as its Windows stand-in for taskkill.exe, under contract amendments 1 and 2.
 * The stand-in needs a host that honors NODE_OPTIONS, so under Node it is the running executable.
 * Bun ignores NODE_OPTIONS, and `raw/probe-bun-preload-a2.log` shows that a bunfig.toml preload does not run before Bun
 * fails on "/PID", so any other host uses the Node executable that PATH resolves.
 */
function taskkillStandInSource({ nodeHost = process.versions.bun === undefined && process.versions.deno === undefined,
  pathEnv = process.env.PATH ?? '' } = {}) {
  if (nodeHost) return process.execPath;
  let node;
  try { node = resolveExecutable(root, 'node', { pathEnv }); }
  catch { throw new Error('FP-0052 case 2 needs Node on PATH to build its stand-in.'); }
  // A hard link to a symbolic link would link the link itself, so link the file that it names.
  return fs.realpathSync(node);
}
test('FP-0052 case 2: a taskkill.exe in the working directory does not stop the watchdog from stopping a command', async () => {
  const dir = temp(), saved = process.cwd(), fake = path.join(dir, 'taskkill.exe'), pidFile = path.join(dir, 'child.pid');
  const windows = process.platform === 'win32', preload = path.join(dir, 'preload.cjs'), marker = path.join(dir, 'taskkill.ran');
  const savedOptions = process.env.NODE_OPTIONS, started = Date.now();
  if (windows) {
    // Contract amendments 1 and 2: the stand-in must exit with status 0 for taskkill's arguments, or the watchdog's
    // direct-child fallback hides a watchdog that runs it. It is a Node executable under the name taskkill.exe, and the
    // preload makes it write the marker and exit with status 0 before Node reads its script argument.
    const source = taskkillStandInSource();
    try { fs.linkSync(source, fake); } catch { fs.copyFileSync(source, fake); }
    fs.writeFileSync(preload, `if (require('node:path').basename(process.execPath).toLowerCase() === 'taskkill.exe') {\n`
      + `  require('node:fs').writeFileSync(${JSON.stringify(marker)}, 'ran');\n  process.exit(0);\n}\n`);
  } else { fs.writeFileSync(fake, '#!/bin/sh\nexit 0\n'); fs.chmodSync(fake, 0o755); }
  const script = `require('node:fs').writeFileSync(${JSON.stringify(pidFile)}, String(process.pid)); setTimeout(() => {}, 60000);`;
  let timer;
  try {
    if (windows) {
      process.env.NODE_OPTIONS = `--require ${JSON.stringify(preload)}`;
      const direct = spawnSync(fake, ['/PID', '1', '/T', '/F'], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
      assert.equal(direct.status, 0, `The stand-in taskkill.exe did not exit with status 0: ${direct.error?.message ?? direct.stderr}`);
      assert.ok(fs.existsSync(marker), 'The stand-in taskkill.exe exited without running its preload.');
      fs.rmSync(marker);
    }
    process.chdir(dir);
    const run = runProcess(process.execPath, ['-e', script], { cwd: dir, logPath: path.join(dir, 'log'), timeoutMs: 1000 });
    const limit = new Promise(resolve => { timer = setTimeout(() => resolve(null), 15000); });
    const r = await Promise.race([run, limit]);
    assert.ok(r, 'runProcess did not return within 15 seconds, so the watchdog did not stop its command.');
    assert.equal(r.timed_out, true);
    if (windows) assert.equal(fs.existsSync(marker), false, 'The watchdog ran the taskkill.exe in the working directory.');
  } finally {
    clearTimeout(timer);
    process.chdir(saved);
    if (windows) {
      if (savedOptions === undefined) delete process.env.NODE_OPTIONS;
      else process.env.NODE_OPTIONS = savedOptions;
    }
    // A command that the watchdog failed to stop must not outlive the test.
    if (fs.existsSync(pidFile)) try { process.kill(Number(fs.readFileSync(pidFile, 'utf8')), 'SIGKILL'); } catch { /* It has ended. */ }
    console.log(`# FP-0052 case 2 took ${Date.now() - started} ms.`);
  }
}, { processWide: 'NODE_OPTIONS in process.env on Windows, and the working directory' });
test('FP-0052 case 2, amendment 2: a host other than Node builds the stand-in from the Node on PATH and fails without one', () => {
  assert.equal(taskkillStandInSource({ nodeHost: true, pathEnv: '' }), process.execPath);
  const dir = temp(), node = path.join(dir, process.platform === 'win32' ? 'node.exe' : 'node');
  fs.writeFileSync(node, ''); fs.chmodSync(node, 0o755);
  assert.equal(taskkillStandInSource({ nodeHost: false, pathEnv: dir }), fs.realpathSync(node));
  assert.throws(() => taskkillStandInSource({ nodeHost: false, pathEnv: '' }),
    e => e.message === 'FP-0052 case 2 needs Node on PATH to build its stand-in.');
});
test('FP-0052: a SystemRoot that cannot locate taskkill.exe fails runProcess on Windows before its command starts', async () => {
  const dir = temp(), marker = path.join(dir, 'started'), saved = process.env.SystemRoot;
  process.env.SystemRoot = 'Windows';
  let r;
  try {
    r = await runProcess(process.execPath, ['-e', `require('node:fs').writeFileSync(${JSON.stringify(marker)}, 'started')`],
      { cwd: dir, logPath: path.join(dir, 'log') });
  } finally { if (saved === undefined) delete process.env.SystemRoot; else process.env.SystemRoot = saved; }
  if (process.platform === 'win32') {
    assert.equal(r.exit_code, null); assert.match(r.error, /SystemRoot/);
    assert.equal(fs.existsSync(marker), false, 'The command started although its watchdog had no taskkill.exe.');
  } else {
    // Only Windows needs a system program to stop a process tree.
    assert.equal(r.exit_code, 0); assert.equal(r.error, null); assert.equal(fs.existsSync(marker), true);
  }
}, { processWide: 'SystemRoot in process.env' });
const GIT_WRITE_STEPS = ['stage the record', 'back up the sources', 'replace the sources', 'replace the record'];
test('FP-0052 case 3: a Git corpus repin that fails at any write step leaves the snapshot and the record unchanged', async () => {
  const u = upstreamFixture(), policyFile = u.policy({ revision: u.first });
  await u.fetch(policyFile);
  u.move();
  const snapshots = path.dirname(u.recordFile), recordBytes = fs.readFileSync(u.recordFile);
  const before = directoryDigest(path.join(u.corporaDir, 'test262')), listing = fs.readdirSync(snapshots);
  for (const label of GIT_WRITE_STEPS) {
    const seen = [];
    const onWriteStep = step => { seen.push(step); if (step === label) throw new Error(`injected failure at ${step}`); };
    await assert.rejects(() => corpus.repinCorpus(u.dir, 'test262', { ...u.options(policyFile), onWriteStep }),
      e => e.message === `injected failure at ${label}`, label);
    assert.equal(seen.at(-1), label);
    assert.equal(directoryDigest(path.join(u.corporaDir, 'test262')), before, `snapshot after a failure at ${label}`);
    assert.deepEqual(fs.readFileSync(u.recordFile), recordBytes, `record after a failure at ${label}`);
    assert.deepEqual(fs.readdirSync(snapshots), listing, `specs/snapshots after a failure at ${label}`);
    assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262'], `corpora directory after a failure at ${label}`);
  }
  const steps = [];
  const r = await corpus.repinCorpus(u.dir, 'test262', { ...u.options(policyFile), onWriteStep: step => steps.push(step) });
  assert.deepEqual(steps, GIT_WRITE_STEPS);
  assert.equal(readJson(u.recordFile).commit, r.commit); assert.notEqual(r.commit, u.first);
  assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262']);
});
test('FP-0052 case 4: a fetch that cannot remove the old snapshot after it replaces the record fails, and the new snapshot and record stay', async () => {
  const u = upstreamFixture();
  await u.fetch(u.policy({ revision: u.first }));
  const moved = u.move(), old = path.join(u.corporaDir, 'test262.old'), rmSync = fs.rmSync;
  // The removal of the previous snapshot fails; every other removal runs.
  fs.rmSync = function rmSyncExceptOld(target, ...rest) {
    if (path.resolve(String(target)) === old && fs.existsSync(old)) throw Object.assign(new Error('injected removal failure'), { code: 'EPERM' });
    return rmSync.call(this, target, ...rest);
  };
  try {
    await assert.rejects(() => u.fetch(u.policy({ revision: moved })),
      e => /could not remove the old copies/.test(e.message) && e.message.includes('injected removal failure'));
  } finally { fs.rmSync = rmSync; }
  assert.equal(readJson(u.recordFile).commit, moved);
  assert.equal(fixtureGit(u.snapshot, ['rev-parse', 'refs/heads/main']), moved);
  assert.equal(fs.existsSync(path.join(u.corporaDir, 'test262.lock')), false);
}, { processWide: 'the fs.rmSync function of the node:fs module' });
test('FP-0052 case 5: a fetch fails while test262.lock exists and changes nothing', async () => {
  const u = upstreamFixture(), policyFile = u.policy({ revision: u.first });
  await u.fetch(policyFile);
  const lockFile = path.join(u.corporaDir, 'test262.lock');
  const lockText = `${JSON.stringify({ pid: 4242, started_at: '2026-10-09T01:02:03.004Z' })}\n`;
  fs.writeFileSync(lockFile, lockText);
  const recordBytes = fs.readFileSync(u.recordFile), before = directoryDigest(path.join(u.corporaDir, 'test262'));
  await assert.rejects(() => u.fetch(policyFile),
    e => e.message.includes(lockFile) && /\b4242\b/.test(e.message) && e.message.includes('2026-10-09T01:02:03.004Z'));
  assert.equal(directoryDigest(path.join(u.corporaDir, 'test262')), before);
  assert.deepEqual(fs.readFileSync(u.recordFile), recordBytes);
  assert.equal(fs.readFileSync(lockFile, 'utf8'), lockText);
  assert.deepEqual(fs.readdirSync(u.corporaDir).sort(), ['test262', 'test262.lock']);
});
test('FP-0052 case 6: of two Git corpus fetches started together, one passes and one fails on the lock', async () => {
  const u = upstreamFixture(), policyFile = u.policy({ revision: u.first });
  const results = await Promise.allSettled([u.fetch(policyFile), u.fetch(policyFile)]);
  const passed = results.filter(r => r.status === 'fulfilled' && r.value.result === 'pass');
  const locked = results.filter(r => r.status === 'rejected' && /holds the lock file/.test(r.reason.message));
  assert.equal(passed.length, 1, JSON.stringify(results.map(r => r.status === 'fulfilled' ? r.value.result : r.reason.message)));
  assert.equal(locked.length, 1, JSON.stringify(results.map(r => r.status === 'fulfilled' ? r.value.result : r.reason.message)));
  assert.deepEqual(fs.readdirSync(u.corporaDir), ['test262']);
  await u.classify();
  assert.equal((await u.verify(policyFile)).result, 'pass');
});
test('The actual bootstrap repository passes its integrity check', () => {
  const r = checkRepository(root); assert.equal(r.result, 'pass'); assert.equal(r.level, 'bootstrap-integrity-only');
});
/** Wait until at least `ms` milliseconds of `performance.now()` time have passed, since a timer may fire slightly early on that clock. */
async function waitAtLeast(ms) {
  const until = performance.now() + ms;
  while (performance.now() < until) await new Promise(r => setTimeout(r, Math.max(1, Math.ceil(until - performance.now()))));
}
test('FP-0107 case 1: the runner writes a duration line after each result line, the summary, the slowest cases, and the total', async () => {
  const { runCases } = await import('./test-runner.mjs');
  const waits = [0, 60, 120], lines = [];
  const fixtures = [...waits.map(ms => ({ name: `waits ${ms} ms`, fn: () => waitAtLeast(ms) })),
    { name: 'throws', fn: () => { throw new Error('fixture failure'); } }];
  const counts = await runCases(fixtures, { write: line => lines.push(line) });
  const text = lines.join('\n'), durations = new Map();
  let at = 0;
  const next = () => { assert.ok(at < lines.length, `The output ended early:\n${text}`); return lines[at++]; };
  assert.equal(next(), 'TAP version 13', text);
  fixtures.forEach((c, i) => {
    assert.equal(next(), `${i < 3 ? 'ok' : 'not ok'} ${i + 1} - ${c.name}`, text);
    const m = /^# duration_ms (\d+) (\d+)$/.exec(next());
    assert.ok(m && Number(m[1]) === i + 1, `Result line ${i + 1} lacks its duration line:\n${text}`);
    const ms = Number(m[2]); durations.set(i + 1, ms);
    if (i < 3) assert.ok(ms >= waits[i], `Case ${i + 1} waited ${waits[i]} ms but reports ${ms} ms.`);
    else {
      assert.deepEqual([next(), next(), next()], ['  ---', `  message: ${JSON.stringify('fixture failure')}`, '  ...'], text);
    }
  });
  assert.deepEqual([next(), next(), next(), next()], ['1..4', '# tests 4', '# pass 3', '# fail 1'], text);
  const ranked = [...durations].sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  assert.equal(ranked[0][0], 3, text);
  ranked.forEach(([n, ms], i) => assert.equal(next(), `# slowest ${i + 1} ${ms} ${n} ${fixtures[n - 1].name}`, text));
  assert.match(next(), /^# duration_ms total \d+$/, text);
  assert.equal(at, lines.length, text);
  assert.deepEqual(counts, { tests: 4, pass: 3, fail: 1 });
});
test('FP-0107 case 2: the runner runs no case that declares a process-wide change while another case runs', async () => {
  const { runCases } = await import('./test-runner.mjs');
  const intervals = [], lines = [];
  const fixture = (name, processWide) => ({ name, ...(processWide ? { processWide } : {}), fn: async () => {
    const start = performance.now(); await waitAtLeast(60); intervals.push({ name, processWide: !!processWide, start, end: performance.now() });
  } });
  const fixtures = [fixture('ordinary 1'), fixture('declared 1', 'a fixture change'), fixture('ordinary 2'), fixture('declared 2', 'a fixture change')];
  const counts = await runCases(fixtures, { write: line => lines.push(line) });
  assert.deepEqual(counts, { tests: 4, pass: 4, fail: 0 }, lines.join('\n'));
  assert.equal(intervals.length, 4);
  for (const declared of intervals.filter(i => i.processWide)) {
    for (const other of intervals.filter(i => i !== declared)) {
      assert.ok(declared.end <= other.start || other.end <= declared.start,
        `"${declared.name}" ran from ${declared.start} to ${declared.end} ms while "${other.name}" ran from ${other.start} to ${other.end} ms.`);
    }
  }
});

/** Remove this thread's temporary fixtures and return the problems. */
function removeFixtures() {
  const problems = [];
  for (const dir of temporary.reverse()) {
    try { fs.rmSync(dir, { recursive: true, force: true }); }
    catch (e) { problems.push(e.message); }
  }
  for (const remove of [removeAttestationFixtures, removeAbiFixtures, removeReleaseFixtures, removeUcdFixtures, removeFileSetFixtures, removeRustFixtures])
    problems.push(...remove());
  return problems;
}
// Ordinary cases run on worker threads that load this module, so a case that blocks its thread on a child process
// does not delay the others. A case that declares a process-wide change runs alone on the main thread.
if (isMainThread) {
  const pool = casePool(import.meta.url);
  const counts = await runCases(cases.map((c, i) => c.processWide === undefined ? { ...c, fn: () => pool.run(i, c.name) } : c), {
    concurrency: pool.size,
    cleanup: async () => {
      const problems = [...await pool.close(), ...removeFixtures()];
      for (const problem of problems) console.error(`Temporary fixture cleanup failed: ${problem}`);
      return problems.length;
    },
  });
  console.log('# Scope: controller behavior only. No renderer or JavaScript conformance claim.');
  process.exitCode = counts.fail ? 1 : 0;
} else serveCases(cases, removeFixtures);
