#!/usr/bin/env node
/** Controller tests only. These tests do not qualify browser behavior. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
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
import { attestationCases, removeAttestationFixtures } from './attest.test.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cases = [], temporary = [];
function test(name, fn) { cases.push({ name, fn }); }
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
for (const c of attestationCases) test(c.name, c.fn);
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
});
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
});
test('Executable resolution never searches the process working directory', () => {
  const cwd = temp(), other = temp(), name = 'fixture-cwd-tool', saved = process.cwd();
  fs.chmodSync(put(cwd, process.platform === 'win32' ? `${name}.exe` : name, 'fixture'), 0o755);
  process.chdir(cwd);
  try { assert.throws(() => resolveExecutable(other, name, { pathEnv: '' }), /not on PATH/); }
  finally { process.chdir(saved); }
});
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
/** A counted record for the corpus that a fixture does not snapshot, so every applicability record has a denominator. */
function otherApplicability(dir, id) {
  writeJson(path.join(dir, 'specs/applicability', `${id}.json`), { schema_version: 1, corpus: id, commit: 'a'.repeat(40), status: 'counted',
    discovery: { rule: 'Fixture rule.' }, discovered: 1, selected: 0, excluded: [], unclassified: 1, breakdown: { by: 'fixture', counts: { fixture: 1 } } });
}
/** A fixture repository root with a snapshot of corpus `id`, its snapshot record, and its applicability record. */
async function corpusFixture(id, files, { manifest } = {}) {
  const dir = temp(), corporaDir = temp(), g = bareRepo(snapshotGitDir(corporaDir, id));
  const policyFile = path.join(dir, 'specs/corpora.json');
  fs.mkdirSync(path.dirname(policyFile)); fs.copyFileSync(path.join(root, 'specs/corpora.json'), policyFile);
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
  otherApplicability(dir, id === 'wpt' ? 'test262' : 'wpt');
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
  for (const file of ['fairpane.mjs', 'lib.mjs', 'corpus.mjs', 'attest.mjs']) put(f.dir, `tools/${file}`, fs.readFileSync(path.join(root, 'tools', file)));
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
});
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
    const p = readJson(path.join(root, 'specs/corpora.json')), file = path.join(temp(), 'corpora.json');
    Object.assign(p.corpora.find(c => c.id === 'test262'), { upstream: url }, pins);
    writeJson(file, p); return file;
  };
  const move = () => {
    const next = fixtureCommit(upstream, [T262_LICENSE, { path: 'test/language/a.js', text: 'moved;\n' }, { path: 'test/language/b.js', text: 'b;\n' }], [first]);
    fixtureGit(upstream, ['update-ref', 'refs/heads/main', next]); return next;
  };
  const options = policyFile => ({ corporaDir, policyFile, allowFileUpstream: true });
  const recordFile = path.join(dir, 'specs/snapshots/test262.json'), snapshot = snapshotGitDir(corporaDir, 'test262');
  const classify = () => { otherApplicability(dir, 'wpt'); return classifyCorpus(dir, 'test262', { corporaDir, allowFileUpstream: true }); };
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
test('The actual bootstrap repository passes its integrity check', () => {
  const r = checkRepository(root); assert.equal(r.result, 'pass'); assert.equal(r.level, 'bootstrap-integrity-only');
});

console.log('TAP version 13');
let failures = 0;
for (let i = 0; i < cases.length; i++) {
  try { await cases[i].fn(); console.log(`ok ${i + 1} - ${cases[i].name}`); }
  catch (e) {
    failures++; console.log(`not ok ${i + 1} - ${cases[i].name}`);
    console.log(`  ---\n  message: ${JSON.stringify(e.message)}\n  ...`);
  }
}
for (const dir of temporary.reverse()) {
  try { fs.rmSync(dir, { recursive: true, force: true }); }
  catch (e) { failures++; console.error(`Temporary fixture cleanup failed: ${e.message}`); }
}
for (const problem of removeAttestationFixtures()) { failures++; console.error(`Temporary fixture cleanup failed: ${problem}`); }
console.log(`1..${cases.length}`);
console.log(`# tests ${cases.length}\n# pass ${cases.length - failures}\n# fail ${failures}`);
console.log('# Scope: controller behavior only. No renderer or JavaScript conformance claim.');
process.exitCode = failures ? 1 : 0;
