#!/usr/bin/env node
/** Controller tests only. These tests do not qualify browser behavior. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  readJson, writeJson, sha256, fileHash, safePath, collectFiles, hashInputs,
  validateLock, hostPlatform, verifyArchive, validatePlan, readyTasks,
  qualificationProblems, checkRepository, validateReceipt, runProcess, runGate,
  resolveExecutable, recordCommand, REQUIRED_CAPABILITIES,
} from './lib.mjs';

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
  assert.ok(qualificationProblems(p).some(e => e.includes('not implemented')));
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
test('Executable resolution follows PATH order and ignores the working directory', () => {
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
console.log(`1..${cases.length}`);
console.log(`# tests ${cases.length}\n# pass ${cases.length - failures}\n# fail ${failures}`);
console.log('# Scope: controller behavior only. No renderer or JavaScript conformance claim.');
process.exitCode = failures ? 1 : 0;
