#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { readJson, checkRepository, readyTasks, qualificationProblems, fingerprints,
  validateReceipt, runGate, recordCommand, installZig, compilerPath, checkCompiler, safePath } from './lib.mjs';
import { corpusCommand } from './corpus.mjs';
import { AttestationError, candidateIdentity, candidateRepository, enclosingGitDirectories, isInside, loadTrustPolicy, readEnvelope, verifyResult } from './attest.mjs';
import { abiCheck, abiExports, abiGenerate } from './abi.mjs';
import { lockedCompiler, provenanceStatement, reproduceCheck, reproduceExitCode, sourceArchive } from './release.mjs';
import { ucdCheck, ucdGenerate } from './ucd.mjs';
import { fontExpectations } from './fileset.mjs';

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
  run <gate-id> [--evidence-dir <dir>]
                              Execute a gate and write a local receipt.
  record [--cwd <dir>] [--env NAME=VALUE]... <log> <executable> [arguments...]
                              Run one command without a shell and append its
                              output and exit status to an evidence log.
  evidence-check <path>       Check a receipt against current inputs.
  corpus-fetch <id>           Fetch the pinned commit, or the frozen file-set sources, into a fresh snapshot and write its record.
  corpus-repin <id>           Move a Git snapshot to the upstream branch head and write its record. File sets refuse.
  corpus-applicability <id>   Count discovered tests or files in a local snapshot.
  corpus-verify <id>          Recompute a local snapshot and compare its records and pins.
  corpus-derive <id>          Run the declared import-tool derivations of a file-set corpus and record them.
  font-expectations [--check] Run tools/fonts/font_expectations.py for every fixture font in a staging
                              directory after checking fontTools against its wheel's RECORD. --check exits
                              with status 1 when an output differs from the committed file; otherwise the
                              command replaces each differing file.
  attest-verify --repository <path> --trust-policy <path> --candidate <commit> <envelope>
                              Verify a signed result against protected trust
                              input and a full commit ID in a candidate
                              repository. Paths resolve from the current
                              directory.
  abi-generate                Validate the ABI schema and failure scenarios, then
                              write include/fairpane.h, src/abi_generated.zig,
                              and tests/c/abi_layout.h.
  abi-check                   Regenerate the ABI files in memory and exit with
                              status 1 when a committed file differs.
  abi-exports <library>       Exit with status 1 when a static library exports
                              an fp_ symbol that the schema does not declare or
                              lacks one that it declares.
  source-archive <commit> <output-dir>
                              Write fairpane-<commit>.tar and its manifest for a
                              full commit ID into a directory outside the
                              repository. The path resolves from the current
                              directory.
  provenance <commit> <artifact>...
                              Print an unsigned in-toto statement with a SLSA
                              provenance predicate. It is not an attestation.
  reproduce-check <commit>    Build a full commit ID twice in fresh work trees
                              under out/ and exit with status 1 unless every
                              installed file matches.
  ucd-generate                Read the imported UCD files and write src/unicode/tables.zig.
  ucd-check                   Regenerate src/unicode/tables.zig in memory and exit with
                              status 1 when the committed file differs.
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
    output({ platform: process.platform, architecture: process.arch, os_release: os.release(), os_version: os.version(),
      runtime: process.version, controller_bun: process.versions.bun ?? null, bun: versionOf('bun'),
      git: versionOf('git'), omp: versionOf(process.platform === 'win32' ? 'omp.exe' : 'omp'), compiler,
      path_zig: { ...versionOf('zig', ['version']), note: 'Gates never use a compiler from PATH.' },
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
  else if (command === 'abi-generate') output(abiGenerate(root));
  else if (command === 'abi-check') {
    const r = abiCheck(root); output(r); process.exitCode = r.result === 'pass' ? 0 : 1;
  } else if (command === 'abi-exports') {
    if (args.length !== 1) throw new Error('Usage: abi-exports <repository-relative static library path>');
    const r = abiExports(root, args[0]); output(r); process.exitCode = r.result === 'pass' ? 0 : 1;
  } else if (command === 'ucd-generate') output(ucdGenerate(root));
  else if (command === 'ucd-check') {
    const r = ucdCheck(root); output(r); process.exitCode = r.result === 'pass' ? 0 : 1;
  } else if (command === 'install-zig') output(await installZig(root));
  else if (command === 'run') {
    const rest = [...args], at = rest.indexOf('--evidence-dir');
    const evidenceDir = at === -1 ? undefined : rest.splice(at, 2)[1];
    if (rest.length !== 1 || (at !== -1 && !evidenceDir)) throw new Error('Usage: run <gate-id> [--evidence-dir <approved-relative-dir>]');
    console.log(`Execute gate ${rest[0]}.`);
    const r = await runGate(root, rest[0], evidenceDir ? { evidenceDir } : undefined);
    output({ gate: r.gate_id, status: r.status, receipt: r.receipt_path, error: r.error });
    process.exitCode = r.status === 'pass' ? 0 : 1;
  } else if (command === 'record') {
    const usage = 'Usage: record [--cwd <dir>] [--env NAME=VALUE]... <evidence-log> <executable> [arguments...]';
    const env = {}; let cwd = root, i = 0;
    for (;; i += 2) {
      if (args[i] === '--env') {
        const m = /^([A-Za-z_][A-Za-z0-9_]*)=([^]*)$/.exec(args[i + 1] ?? '');
        if (!m) throw new Error(usage);
        env[m[1]] = m[2];
      } else if (args[i] === '--cwd') cwd = safePath(root, args[i + 1] ?? '');
      else break;
    }
    const [log, executable, ...argv] = args.slice(i);
    if (!log || !executable) throw new Error(usage);
    const r = await recordCommand(root, log, executable, argv, { cwd, env: Object.keys(env).length ? env : undefined });
    output(r);
    process.exitCode = r.exit_code === 0 && !r.signal && !r.timed_out && !r.error ? 0 : 1;
  } else if (command === 'evidence-check') {
    if (args.length !== 1) throw new Error('Usage: evidence-check <repository-relative-path>');
    output(validateReceipt(root, args[0]));
  } else if (command.startsWith('corpus-')) {
    const r = await corpusCommand(root, command, args); output(r); process.exitCode = r.result === 'pass' ? 0 : 1;
  } else if (command === 'font-expectations') {
    if (args.some(a => a !== '--check')) throw new Error('Usage: font-expectations [--check]');
    const r = fontExpectations(root, { check: args.includes('--check') }); output(r); process.exitCode = r.result === 'pass' ? 0 : 1;
  } else if (command === 'attest-verify') {
    const usage = 'Usage: attest-verify --repository <path> --trust-policy <path> --candidate <commit> <envelope>';
    const options = {}, files = [];
    for (let i = 0; i < args.length; i++) {
      const flag = { '--repository': 'repository', '--trust-policy': 'policy', '--candidate': 'candidate' }[args[i]];
      if (!flag) { files.push(args[i]); continue; }
      if (options[flag] !== undefined || args[i + 1] === undefined) throw new Error(usage);
      options[flag] = args[++i];
    }
    if (!options.repository || !options.policy || !options.candidate || files.length !== 1) throw new Error(usage);
    try {
      const repository = candidateRepository(path.resolve(options.repository));
      const trust = loadTrustPolicy(path.resolve(options.policy), [repository.root, repository.gitDirectory]);
      const candidate = candidateIdentity(repository.root, options.candidate);
      // A verifier in another work tree of the candidate repository shares its Git directory, which a workspace writer controls.
      const advisory = isInside(root, repository.root) || isInside(root, repository.gitDirectory) ||
        enclosingGitDirectories(root).includes(repository.gitDirectory);
      const verified = verifyResult(readEnvelope(path.resolve(files[0])), trust, candidate);
      output({ ...verified, result: advisory ? 'verified-advisory' : 'verified', candidate,
        verifier: advisory ? 'inside-candidate' : 'outside-candidate',
        note: advisory ? 'The verifier runs from inside the candidate repository, so this result is advisory only.' :
          'A verified result authenticates one record. It is not release qualification.' });
      // An advisory result exits with status 3, so automation that reads only the status cannot mistake it for authority.
      if (advisory) process.exitCode = 3;
    } catch (e) {
      if (!(e instanceof AttestationError)) throw e;
      output({ result: 'rejected', code: e.code, message: e.message });
      process.exitCode = 1;
    }
  } else if (command === 'source-archive') {
    if (args.length !== 2) throw new Error('Usage: source-archive <commit> <output-dir>');
    output(sourceArchive(root, args[0], args[1]));
  } else if (command === 'provenance') {
    if (args.length < 2) throw new Error('Usage: provenance <commit> <artifact>...');
    output(provenanceStatement(root, args[0], args.slice(1)));
  } else if (command === 'reproduce-check') {
    if (args.length !== 1) throw new Error('Usage: reproduce-check <commit>');
    const r = reproduceCheck(root, args[0], { compiler: lockedCompiler(root, args[0]) });
    output(r); process.exitCode = reproduceExitCode(r);
  } else if (command === 'release-check') {
    output({ result: 'not-qualified', problems: qualificationProblems(load('engineering/qualification.json')), browser_complete: false });
    process.exitCode = 1;
  } else throw new Error(`Unknown command: ${command}. Run help for supported commands.`);
} catch (e) { console.error(`Fairpane: ${e.message}`); process.exitCode = 1; }
