// Mutation control for FP-0028 and FP-0031: each mutant must make its target controller test fail.
// The unmutated suite runs first in an identical copy of the repository and must pass completely.
// Run from the repository root: node engineering/evidence/FP-0028/controls/mutants.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { runControl } from './harness.mjs';

const source = fs.readFileSync('tools/lib.mjs', 'utf8');
const mutants = [
  ['resolution searches the working directory first',
    "  const suffixes = platform === 'win32'",
    "  pathEnv = [process.cwd(), pathEnv].join(platform === 'win32' ? ';' : ':');\n  const suffixes = platform === 'win32'",
    /never searches the process working directory/],
  ['record logs the unresolved name',
    'return runProcess(resolved, args, { cwd, logPath, timeoutMs, env, fileSystem });',
    'return runProcess(executable, args, { cwd, logPath, timeoutMs, env, fileSystem });',
    /bare executable name is logged/],
  ['copy failure is swallowed',
    'catch (e) { errors.push(`Output capture failed: ${e.message}`); }\n      removeCapture(',
    'catch (e) { }\n      removeCapture(',
    /failed output copy is recorded/],
  ['capture directory is kept',
    '      removeCapture(io, captureDir, errors);\n      resolve(',
    '      resolve(',
    /leaves no capture directory/],
  ['record omits the working directory',
    'return { executable, arguments: args, cwd: path.resolve(cwd ?? process.cwd()), started_at',
    'return { executable, arguments: args, started_at',
    /working directory and start time/],
  ['every gate receives the cache override',
    "return gate.kind === 'zig' || gate.kind === 'c-abi' ?",
    'return true ?',
    /Only Zig and C ABI gates/],
  ['capture-start failure skips the RESULT line and leaves the log open',
    'return Promise.resolve(finishRecord(io, fd, result(null, null, false)));',
    'return Promise.resolve(result(null, null, false));',
    /capture-start failure writes a RESULT line/],
  ['a failed RESULT write throws',
    "  catch (e) { result.error = [result.error, `Log write failed: ${e.message}`].filter(Boolean).join(' '); }\n  finally { closeQuietly(io, fd); }",
    '  finally { closeQuietly(io, fd); }',
    /failed RESULT write returns an error result/],
  ['a spawn error drops the capture error',
    'catch (e) { errors.push(`Output capture failed: ${e.message}`); }\n      removeCapture(',
    'catch (e) { if (!errors.length) errors.push(`Output capture failed: ${e.message}`); }\n      removeCapture(',
    /spawn error and a capture error both remain/],
  ['runGate writes its log before path validation',
    '  const logRelative = `${prefix}.log`, logPath = evidencePath(root, logRelative, { mustExist: false });',
    '  const logRelative = `${prefix}.log`, early = path.join(root, logRelative);\n' +
    "  fs.mkdirSync(path.dirname(early), { recursive: true }); fs.writeFileSync(early, '');\n" +
    '  const logPath = evidencePath(root, logRelative, { mustExist: false });',
    /runGate writes nothing when its evidence directory fails validation/],
  ['a short log write is ignored',
    '  if (written !== length) throw new Error(`Short write: ${written} of ${length} bytes.`);\n',
    '',
    /short write to the log produces an error result/],
  ['a failed capture-directory removal is silent',
    '  catch (e) { errors.push(`Capture directory removal failed: ${e.message}`); }',
    '  catch { /* Mutant: the failure is dropped. */ }',
    /failed capture-directory removal appears in the command record/],
  ['started_at uses local time text',
    'started_at: new Date(started).toISOString() }',
    'started_at: new Date(started).toString() }',
    /canonical UTC ISO 8601 timestamp/],
];

// Copy every tracked or unignored file into a template, so root-dependent tests see a complete repository.
// The template gets its own one-commit Git repository, because some tests resolve HEAD at the repository root.
function git(args, cwd, env = process.env) {
  const r = spawnSync('git', args, { cwd, env, encoding: 'utf8', windowsHide: true, maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.error?.message ?? r.stderr}`);
  return r.stdout;
}
const files = git(['ls-files', '-z', '--cached', '--others', '--exclude-standard'], process.cwd()).split('\0')
  .filter(f => f && fs.existsSync(f) && fs.statSync(f).isFile());
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-mutants-'));
let outcome;
try {
  const template = path.join(work, 'template'), emptyConfig = path.join(work, 'empty-gitconfig');
  for (const file of files) {
    fs.mkdirSync(path.dirname(path.join(template, file)), { recursive: true });
    fs.copyFileSync(file, path.join(template, file));
  }
  fs.writeFileSync(emptyConfig, '');
  const gitEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: emptyConfig, GIT_TERMINAL_PROMPT: '0',
    GIT_AUTHOR_NAME: 'Fairpane Mutation Control', GIT_AUTHOR_EMAIL: 'control@example.invalid',
    GIT_COMMITTER_NAME: 'Fairpane Mutation Control', GIT_COMMITTER_EMAIL: 'control@example.invalid' };
  git(['init', '--quiet', '.'], template, gitEnv);
  git(['add', '--all'], template, gitEnv);
  git(['commit', '--quiet', '--no-verify', '-m', 'Mutation control template'], template, gitEnv);
  let runs = 0;
  const runSuite = lib => {
    const dir = path.join(work, String(runs++));
    try {
      fs.cpSync(template, dir, { recursive: true });
      if (lib !== null) fs.writeFileSync(path.join(dir, 'tools', 'lib.mjs'), lib);
      const run = spawnSync(process.execPath, [path.join(dir, 'tools', 'selftest.mjs')],
        { cwd: dir, encoding: 'utf8', timeout: 600000, windowsHide: true, maxBuffer: 64 * 1024 * 1024 });
      if (run.error) console.log(`Suite process error: ${run.error.message}`);
      return { status: run.status, stdout: run.stdout ?? '' };
    } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  };
  console.log(`template files: ${files.length}`);
  outcome = runControl({ source, mutants, runSuite, log: line => console.log(line) });
} finally { fs.rmSync(work, { recursive: true, force: true }); }
process.exitCode = outcome.baseline && outcome.survived === 0 ? 0 : 1;
