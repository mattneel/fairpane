// Mutation control for FP-0028: each mutant must make its target controller test fail.
// Run from the repository root: node engineering/evidence/FP-0028/controls/mutants.mjs
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const source = fs.readFileSync('tools/lib.mjs', 'utf8');
const mutants = [
  ['resolution searches the working directory first',
    "  const suffixes = platform === 'win32'",
    "  pathEnv = [process.cwd(), pathEnv].join(platform === 'win32' ? ';' : ':');\n  const suffixes = platform === 'win32'",
    /never searches the process working directory/],
  ['record logs the unresolved name',
    'return runProcess(resolved, args, { cwd, logPath, timeoutMs, env });',
    'return runProcess(executable, args, { cwd, logPath, timeoutMs, env });',
    /bare executable name is logged/],
  ['copy failure is swallowed',
    'catch (e) { errors.push(`Output capture failed: ${e.message}`); }\n      removeQuietly(captureDir);',
    'catch (e) { }\n      removeQuietly(captureDir);',
    /failed output copy is recorded/],
  ['capture directory is kept',
    '      removeQuietly(captureDir);\n      resolve(',
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
];
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'fairpane-mutants-'));
let survived = 0;
try {
  for (const [name, from, to, target] of mutants) {
    if (!source.includes(from)) { console.log(`SETUP-FAILED ${name}`); survived++; continue; }
    const dir = path.join(work, name.replace(/\W+/g, '-'), 'tools');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'lib.mjs'), source.replace(from, to));
    for (const file of ['selftest.mjs', 'fairpane.mjs']) fs.copyFileSync(path.join('tools', file), path.join(dir, file));
    const run = spawnSync(process.execPath, [path.join(dir, 'selftest.mjs')], { encoding: 'utf8', timeout: 120000 });
    const line = run.stdout.split('\n').find(l => target.test(l)) ?? '(target test did not run)';
    const killed = line.startsWith('not ok');
    if (!killed) survived++;
    console.log(`${killed ? 'KILLED' : 'SURVIVED'} ${name}: ${line}`);
  }
} finally { fs.rmSync(work, { recursive: true, force: true }); }
console.log(`mutants: ${mutants.length}, survived: ${survived}`);
process.exitCode = survived ? 1 : 0;
