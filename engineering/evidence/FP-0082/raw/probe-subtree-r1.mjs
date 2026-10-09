// FP-0082 revision 1: which tree objects Git rehashes when `git ls-tree -r` reads them.
// The probe builds a bare repository under out/, so its output names no path outside the worktree.
// It replaces the loose object of a commit's `test/` subtree, and then of the commit's root tree, with another tree's object file.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const dir = path.resolve('out', 'fp0082-probe-subtree-r1');
if (fs.existsSync(dir)) throw new Error('The probe directory exists already; choose a new one.');
fs.mkdirSync(dir, { recursive: true });
const config = path.join(dir, 'empty-gitconfig');
fs.writeFileSync(config, '');
const env = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: config, GIT_TERMINAL_PROMPT: '0',
  GIT_AUTHOR_NAME: 'Fairpane Probe', GIT_AUTHOR_EMAIL: 'probe@example.invalid', GIT_AUTHOR_DATE: '1767323045 +0130',
  GIT_COMMITTER_NAME: 'Fairpane Probe', GIT_COMMITTER_EMAIL: 'probe@example.invalid', GIT_COMMITTER_DATE: '1767323045 +0130' };
const gitDir = path.join(dir, 'repo.git');
function git(args, input) {
  const r = spawnSync('git', args, { cwd: gitDir, input, env, windowsHide: true });
  return { status: r.status, stdout: r.stdout.toString('latin1').trim(), stderr: r.stderr.toString('latin1').trim() };
}
function must(args, input) {
  const r = git(args, input);
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
}
fs.mkdirSync(gitDir);
must(['init', '--bare', '--quiet', '.']);
console.log(`git version: ${must(['--version'])}`);
const a = must(['hash-object', '-w', '--stdin'], 'a;\n'), b = must(['hash-object', '-w', '--stdin'], 'b;\n');
const mktree = lines => must(['mktree'], `${lines.join('\n')}\n`);
const test = mktree([`100644 blob ${a}\ta.js`]), otherTest = mktree([`100644 blob ${a}\ta.js`, `100644 blob ${b}\tb.js`]);
const rootTree = mktree([`040000 tree ${test}\ttest`]), otherRoot = mktree([`040000 tree ${otherTest}\ttest`]);
const commit = must(['commit-tree', rootTree, '-m', 'probe']);
const objectFile = id => path.join(gitDir, 'objects', id.slice(0, 2), id.slice(2));
const listing = label => {
  const r = git(['ls-tree', '-r', '-z', '--full-tree', commit]);
  console.log(`${label}: exit status ${r.status}`);
  for (const line of r.stdout.split('\0').filter(Boolean)) console.log(`  ${line}`);
  if (r.stderr) console.log(`  stderr: ${r.stderr.replace(/\n/g, '\n  stderr: ')}`);
};
console.log(`commit ${commit}, root tree ${rootTree}, test/ subtree ${test}, other test/ subtree ${otherTest}, other root tree ${otherRoot}`);
listing('Unaltered');
fs.chmodSync(objectFile(test), 0o644);
fs.copyFileSync(objectFile(otherTest), objectFile(test));
listing(`After the object file of the test/ subtree ${test} holds the other test/ subtree`);
fs.chmodSync(objectFile(rootTree), 0o644);
fs.copyFileSync(objectFile(otherRoot), objectFile(rootTree));
listing(`After the object file of the root tree ${rootTree} also holds the other root tree`);
