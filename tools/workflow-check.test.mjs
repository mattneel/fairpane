#!/usr/bin/env node
/**
 * Workflow policy checker tests for FP-0033.
 * Run standalone with `node tools/workflow-check.test.mjs`, or through `node tools/fairpane.mjs test`.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WorkflowParseError, checkWorkflow, gateWorkflowProblems, parseWorkflow } from './workflow-check.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const readWorkflow = name => fs.readFileSync(path.join(root, '.github/workflows', name), 'utf8');
const CHECKOUT_SHA = '3d3c42e5aac5ba805825da76410c181273ba90b1';

/** A minimal workflow that satisfies every policy check. Each failure fixture changes exactly one part of it. */
const BASE = `name: Fixture

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - name: Check out the repository
        uses: actions/checkout@${CHECKOUT_SHA} # v7.0.1
        with:
          persist-credentials: false

      - name: Run a gate
        run: node tools/fairpane.mjs run repo-check
`;
function variant(from, to) {
  assert.ok(BASE.includes(from), `The base fixture lacks: ${from}`);
  return BASE.replace(from, to);
}
/** Assert that the text parses and that its problems include every pattern. */
function fails(text, ...patterns) {
  const problems = checkWorkflow(text);
  for (const pattern of patterns) assert.ok(problems.some(p => pattern.test(p)), `Expected ${pattern} in ${JSON.stringify(problems)}`);
}
function unparseable(text, pattern) {
  let error = null;
  try { parseWorkflow(text); } catch (e) { error = e; }
  assert.ok(error instanceof WorkflowParseError, `Expected a parse error, got ${error ? error.message : 'success'}`);
  assert.match(error.message, pattern);
}
const steps = (workflow, job) => workflow.entries.get('jobs').value.entries.get(job).value.entries.get('steps').value.items;
const field = (step, key) => step.entries.get(key)?.value.value;
const NOT_PINNED = /not pinned to a full 40-hex commit SHA/;
const WORKFLOW_PERMISSION = /The workflow grants a permission other than contents: read/;
const JOB_PERMISSION = /Job build grants a permission other than contents: read/;
const CONTINUE = /continue-on-error is not accepted/;
const PERSIST = /Checkout must set persist-credentials: false/;
const TARGET = /The workflow uses pull_request_target/;
const EXPRESSION = /not on the allowlist|does not accept|no closing|unterminated string literal/;
const CHARACTER = /Character U\+[0-9A-F]{4} is not accepted/;
/** The reviewed problems of each workflow file. A new workflow file needs its own reviewed entry. */
const REVIEWED = {
  'gates.yml': [],
  'pages.yml': ['Line 49: Job deploy grants a permission other than contents: read (pages: write, id-token: write).'],
};

export const workflowCases = [
  ['FP-0033 2-4, 6: Every workflow file has exactly its reviewed policy problems', () => {
    assert.deepEqual(checkWorkflow(BASE), []);
    const names = fs.readdirSync(path.join(root, '.github/workflows')).sort();
    assert.deepEqual(names, Object.keys(REVIEWED).sort());
    for (const name of names) assert.deepEqual(checkWorkflow(readWorkflow(name)), REVIEWED[name], name);
  }],
  ['FP-0033: The Gates workflow runs the contract gates in order on pinned runner images', () => {
    const workflow = parseWorkflow(readWorkflow('gates.yml'));
    assert.equal(workflow.entries.get('name').value.value, 'Gates');
    assert.deepEqual(gateWorkflowProblems(workflow), []);
    const concurrency = workflow.entries.get('concurrency').value.entries;
    assert.equal(concurrency.get('group').value.value,
      "gates-${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.pull_request.number) || github.run_id }}");
    assert.equal(concurrency.get('cancel-in-progress').value.value, "${{ github.event_name == 'pull_request' }}");
    const triggers = workflow.entries.get('on').value;
    assert.deepEqual([...triggers.entries.keys()], ['push', 'pull_request', 'workflow_dispatch']);
    for (const event of ['push', 'pull_request']) {
      assert.deepEqual(triggers.entries.get(event).value.entries.get('branches').value.items.map(i => i.value), ['master']);
    }
    const expected = {
      windows: ['windows-2025', ['repo-check', 'controller-test', 'zig-fmt', 'zig-test', 'zig-build', 'c-abi']],
      linux: ['ubuntu-24.04', ['repo-check', 'controller-test', 'cross-windows-x86_64', 'cross-linux-aarch64', 'cross-macos-aarch64']],
    };
    const jobs = workflow.entries.get('jobs').value.entries;
    assert.deepEqual([...jobs.keys()], Object.keys(expected));
    for (const [job, [runner, gates]] of Object.entries(expected)) {
      assert.equal(jobs.get(job).value.entries.get('runs-on').value.value, runner);
      const sequence = steps(workflow, job).map(s => [field(s, 'uses')?.split('@')[0] ?? null, field(s, 'run') ?? null]);
      assert.deepEqual(sequence, [['actions/checkout', null], ['actions/setup-node', null], [null, 'node tools/fairpane.mjs install-zig'],
        ...gates.map(g => [null, `node tools/fairpane.mjs run ${g}`]), ['actions/upload-artifact', null]]);
      const upload = steps(workflow, job).at(-1);
      assert.match(field(upload, 'uses'), /^actions\/upload-artifact@/);
      assert.equal(field(upload, 'if'), '${{ always() }}');
      const name = upload.entries.get('with').value.entries.get('name').value.value;
      assert.match(name, /unsigned-local-integrity-records-not-attestations$/);
    }
  }],
  ['FP-0033 2: A uses reference without a full 40-hex commit SHA fails', () => {
    fails(variant(`actions/checkout@${CHECKOUT_SHA} # v7.0.1`, 'actions/checkout@v7.0.1'), NOT_PINNED);
    fails(variant(`actions/checkout@${CHECKOUT_SHA} # v7.0.1`, 'actions/checkout@3d3c42e # v7.0.1'), NOT_PINNED);
    fails(variant(`actions/checkout@${CHECKOUT_SHA} # v7.0.1`, `actions/checkout@${CHECKOUT_SHA.toUpperCase()} # v7.0.1`), NOT_PINNED);
    fails(variant(`actions/checkout@${CHECKOUT_SHA} # v7.0.1`, './.github/actions/local'), NOT_PINNED);
    fails(variant('        run: node tools/fairpane.mjs run repo-check\n', '        uses: docker://alpine:3\n'), NOT_PINNED);
    fails(variant(`actions/checkout@${CHECKOUT_SHA} # v7.0.1`, `actions/checkout@${CHECKOUT_SHA}`), /has no version comment/);
  }],
  ['FP-0033 17: An action commit outside the reviewed set fails, even with a full SHA and a version comment', () => {
    const reviewed = /is not a reviewed action commit/;
    const pin = `actions/checkout@${CHECKOUT_SHA} # v7.0.1`;
    // A commit pushed to a fork of the action's repository has a full SHA that GitHub also fetches.
    fails(variant(pin, `actions/checkout@${'a'.repeat(40)} # v7.0.1`), reviewed);
    fails(variant(pin, `actions/checkout@${CHECKOUT_SHA} # v7.0.2`), reviewed);
    fails(variant(pin, `someone/checkout@${CHECKOUT_SHA} # v7.0.1`), reviewed);
    assert.deepEqual(checkWorkflow(variant(pin, `Actions/Checkout@${CHECKOUT_SHA} # v7.0.1`)), []);
  }],
  ['FP-0033 3: A workflow permission other than contents: read fails', () => {
    fails(variant('permissions:\n  contents: read\n', 'permissions:\n  contents: write\n'), WORKFLOW_PERMISSION);
    fails(variant('permissions:\n  contents: read\n', 'permissions:\n  contents: read\n  id-token: write\n'), WORKFLOW_PERMISSION);
    fails(variant('permissions:\n  contents: read\n', 'permissions: write-all\n'), WORKFLOW_PERMISSION);
    fails(variant('permissions:\n  contents: read\n', 'permissions: read-all\n'), WORKFLOW_PERMISSION);
    fails(variant('permissions:\n  contents: read\n\n', ''), /does not declare permissions: contents: read/);
  }],
  ['FP-0033 3: A job permission other than contents: read fails', () => {
    const job = '    runs-on: ubuntu-24.04\n';
    fails(variant(job, `${job}    permissions:\n      contents: write\n`), JOB_PERMISSION);
    fails(variant(job, `${job}    permissions:\n      pull-requests: write\n`), JOB_PERMISSION);
    fails(variant(job, `${job}    permissions: write-all\n`), JOB_PERMISSION);
    assert.deepEqual(checkWorkflow(variant(job, `${job}    permissions:\n      contents: read\n`)), []);
  }],
  ['FP-0033 4: continue-on-error on a step or a job fails', () => {
    fails(variant('        run: node tools/fairpane.mjs run repo-check\n',
      '        run: node tools/fairpane.mjs run repo-check\n        continue-on-error: true\n'), CONTINUE);
    fails(variant('        run: node tools/fairpane.mjs run repo-check\n',
      '        run: node tools/fairpane.mjs run repo-check\n        continue-on-error: false\n'), CONTINUE);
    fails(variant('    runs-on: ubuntu-24.04\n', '    runs-on: ubuntu-24.04\n    continue-on-error: true\n'), CONTINUE);
  }],
  ['FP-0033 4: Checkout that persists credentials or omits persist-credentials fails', () => {
    fails(variant('persist-credentials: false', 'persist-credentials: true'), PERSIST);
    fails(variant('persist-credentials: false', "persist-credentials: 'true'"), PERSIST);
    fails(variant('persist-credentials: false', 'fetch-depth: 1'), PERSIST);
    fails(variant('        with:\n          persist-credentials: false\n', ''), PERSIST);
  }],
  ['FP-0033 4: A pull_request_target trigger fails in mapping, list, and scalar form', () => {
    fails(variant('  pull_request:\n', '  pull_request_target:\n'), TARGET);
    const on = 'on:\n  push:\n    branches: [master]\n  pull_request:\n    branches: [master]\n';
    fails(variant(on, 'on: [push, pull_request_target]\n'), TARGET);
    fails(variant(on, 'on:\n  - push\n  - pull_request_target\n'), TARGET);
    fails(variant(on, 'on: pull_request_target\n'), TARGET);
  }],
  ['FP-0033 4: A workflow_run trigger fails', () => {
    fails(variant('  pull_request:\n', '  workflow_run:\n'), /The workflow uses workflow_run/);
  }],
  ['FP-0033 8: An expression outside the allowlist fails', () => {
    const run = '        run: node tools/fairpane.mjs run repo-check\n';
    const env = value => variant(run, `${run}        env:\n          VALUE: ${value}\n`);
    fails(env('${{ secrets.TOKEN }}'), /reads secrets\.TOKEN/);
    fails(env('${{ github.token }}'), /reads github\.token/);
    fails(env("${{ github['token'] }}"), /uses \[/);
    fails(env('${{ toJSON(github) }}'), /calls toJSON/);
    fails(env("${{ format('}}{0}', secrets.X) }}"), /reads secrets\.X/);
    fails(variant(run, '        run: |\n          echo "${{ secrets[\'TOKEN\'] }}"\n'), EXPRESSION);
    fails(variant(run, `${run}        if: secrets.X != ''\n`), /reads secrets\.X/);
    fails(env('${{ github.run_id'), /no closing/);
    fails(env("${{ format('x) }}"), EXPRESSION);
    assert.deepEqual(checkWorkflow(env("${{ format('{0}-{1}', github.run_id, steps.build.outputs.path) }}")), []);
  }],
  ['FP-0033 9: A gate step that can be skipped or rerouted fails', () => {
    const run = '        run: node tools/fairpane.mjs run repo-check\n';
    const gates = text => gateWorkflowProblems(parseWorkflow(text));
    assert.deepEqual(gates(BASE), []);
    assert.match(gates(variant(run, `${run}        if: always()\n`)).join('\n'), /Only an upload-artifact step may set if:/);
    assert.match(gates(variant(run, `${run}        shell: bash\n`)).join('\n'), /sets shell:/);
    assert.match(gates(variant('    runs-on: ubuntu-24.04\n', "    runs-on: ubuntu-24.04\n    if: github.event_name == 'push'\n")).join('\n'), /Job build sets if:/);
    const upload = condition => `${run}\n      - name: Upload\n        uses: actions/upload-artifact@cf430e0 # v7.0.2\n${condition}`;
    assert.deepEqual(gates(variant(run, upload('        if: ${{ always() }}\n'))), []);
    assert.match(gates(variant(run, upload('        if: ${{ success() }}\n'))).join('\n'), /Only an upload-artifact step may set if:/);
  }],
  ['FP-0033 12: The Gates workflow allowlists report every other key, action, input, command, and upload condition', () => {
    const run = '        run: node tools/fairpane.mjs run repo-check\n', job = '    runs-on: ubuntu-24.04\n';
    const gates = text => gateWorkflowProblems(parseWorkflow(text));
    const reports = (text, pattern) => {
      const problems = gates(text);
      assert.ok(problems.some(p => pattern.test(p)), `Expected ${pattern} in ${JSON.stringify(problems)}`);
    };
    const setup = '      - name: Set up Node\n        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0\n' +
      '        with:\n          node-version: 24.21.0\n\n';
    const upload = condition => `${run}\n      - name: Upload\n${condition}        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2\n` +
      '        with:\n          name: receipts\n          path: out/evidence/\n          if-no-files-found: error\n';
    const accepted = variant(run, upload('        if: ${{ always() }}\n')).replace('      - name: Run a gate\n', `${setup}      - name: Run a gate\n`);
    assert.deepEqual(gates(accepted), []);
    assert.deepEqual(checkWorkflow(accepted), []);
    assert.deepEqual(gates(variant(run, '        run: node tools/fairpane.mjs install-zig\n')), []);
    reports(variant('jobs:\n', "defaults:\n  run:\n    shell: 'true {0}'\n\njobs:\n"), /The Gates workflow sets defaults:/);
    reports(variant(job, `${job}    defaults:\n      run:\n        shell: 'true {0}'\n`), /Job build sets defaults:/);
    reports(variant('jobs:\n', 'env:\n  NODE_OPTIONS: --require=./x.js\n\njobs:\n'), /The Gates workflow sets env:/);
    reports(variant(job, `${job}    env:\n      NODE_OPTIONS: --require=./x.js\n`), /Job build sets env:/);
    reports(variant(run, `${run}        env:\n          NODE_OPTIONS: --require=./x.js\n`), /A run step of job build sets env:/);
    reports(variant(run, `${run}        working-directory: elsewhere\n`), /A run step of job build sets working-directory:/);
    reports(variant(job, `${job}    container: node:24\n`), /Job build sets container:/);
    reports(variant('      - name: Run a gate\n', `      - name: Write the environment\n        uses: actions/github-script@${'a'.repeat(40)} # v8.0.0\n\n      - name: Run a gate\n`),
      /Job build uses actions\/github-script, which is not an accepted action/);
    reports(variant('          persist-credentials: false\n', '          persist-credentials: false\n          ref: refs/heads/other\n'),
      /The actions\/checkout step of job build sets the input ref\./);
    reports(variant('          persist-credentials: false\n', '          persist-credentials: false\n        env:\n          NODE_OPTIONS: --require=./x.js\n'),
      /The actions\/checkout step of job build sets env:/);
    reports(accepted.replace('          node-version: 24.21.0\n', '          node-version: 24.21.0\n          cache: npm\n'),
      /The actions\/setup-node step of job build sets the input cache\./);
    for (const command of ['node tools/fairpane.mjs run repo-check || true', 'echo skipped', 'node tools/fairpane.mjs run repo-check --evidence-dir out/evidence/x']) {
      reports(variant(run, `        run: ${command}\n`), new RegExp(`Job build runs ${JSON.stringify(command).replace(/[|.]/g, '\\$&')}, which is not`));
    }
    reports(variant(run, upload('')), /An upload-artifact step of job build must set if: \$\{\{ always\(\) \}\}/);
  }],
  ['FP-0033 13: A run: value with a ${{ }} expression fails in every workflow', () => {
    const run = '        run: node tools/fairpane.mjs run repo-check\n';
    const sink = /A run: value contains a \$\{\{ \}\} expression/;
    fails(variant(run, '        run: echo "${{ steps.x.outputs.y }}"\n'), sink);
    fails(variant(run, '        run: |\n          echo ${{ github.run_id }}\n'), sink);
    assert.deepEqual(checkWorkflow(variant(run, run + '        env:\n          VALUE: ${{ steps.x.outputs.y }}\n')), []);
  }],
  ['FP-0033 14: A trigger other than push, pull_request, and workflow_dispatch fails', () => {
    const unaccepted = name => new RegExp(`The workflow uses ${name}, which is not an accepted trigger`);
    fails(variant('  pull_request:\n', '  issue_comment:\n'), unaccepted('issue_comment'));
    fails(variant('  pull_request:\n    branches: [master]\n', "  schedule:\n    - cron: '0 0 * * *'\n"), unaccepted('schedule'));
    const on = 'on:\n  push:\n    branches: [master]\n  pull_request:\n    branches: [master]\n';
    fails(variant(on, 'on: [push, issue_comment]\n'), unaccepted('issue_comment'));
    fails(variant(on, 'on: schedule\n'), unaccepted('schedule'));
    assert.deepEqual(checkWorkflow(variant('\npermissions:\n', '  workflow_dispatch:\n\npermissions:\n')), []);
  }],
  ['FP-0033 15: A permission problem names the exact grants, so widening pages.yml fails its reviewed list', () => {
    const pages = readWorkflow('pages.yml').replaceAll('\r\n', '\n');
    const grants = '    permissions:\n      pages: write\n      id-token: write\n';
    assert.ok(pages.includes(grants), 'pages.yml lacks the reviewed deploy grants.');
    assert.deepEqual(checkWorkflow(pages), REVIEWED['pages.yml']);
    const widened = [['    permissions: write-all\n', 'write-all'], [`${grants}      contents: write\n`, 'pages: write, id-token: write, contents: write']];
    for (const [text, granted] of widened) {
      const problems = checkWorkflow(pages.replace(grants, text));
      assert.notDeepEqual(problems, REVIEWED['pages.yml']);
      assert.deepEqual(problems, [`Line 49: Job deploy grants a permission other than contents: read (${granted}).`]);
    }
    fails(variant('permissions:\n  contents: read\n', 'permissions:\n  contents: read\n  actions: write\n'),
      /^Line 9: The workflow grants a permission other than contents: read \(contents: read, actions: write\)\.$/);
  }],
  ['FP-0033 16: A block scalar whose leading blank line has more spaces than its first content line fails to parse', () => {
    const run = '        run: node tools/fairpane.mjs run repo-check\n';
    unparseable(variant(run, '        run: |\n            \n          echo hi\n'),
      /^Line 23: A leading blank line of a block scalar has more spaces than its first content line\.$/);
    for (const blank of ['          ', '   ', '']) {
      assert.equal(field(steps(parseWorkflow(variant(run, `        run: |\n${blank}\n          echo hi\n`)), 'build')[1], 'run'), '\necho hi');
    }
  }],
  ['FP-0033: The parser reads the accepted subset and its block scalars exactly', () => {
    const text = variant('        run: node tools/fairpane.mjs run repo-check\n',
      '        run: |\n          first line\n\n          # not a comment\n        shell: "bash"\n');
    const step = steps(parseWorkflow(text), 'build')[1];
    assert.equal(field(step, 'run'), 'first line\n\n# not a comment');
    assert.equal(field(step, 'shell'), 'bash');
    // A sequence may sit at the same column as its parent key.
    const flush = variant('    steps:\n      - name: Check out the repository\n        uses:',
      '    steps:\n    - name: Check out the repository\n      uses:').replace('        with:\n          persist-credentials: false\n\n      - name: Run a gate\n        run:',
      '      with:\n        persist-credentials: false\n    - name: Run a gate\n      run:');
    assert.equal(steps(parseWorkflow(flush), 'build').length, 2);
    assert.deepEqual(checkWorkflow(flush), []);
    assert.deepEqual(checkWorkflow(BASE.replaceAll('\n', '\r\n')), []);
  }],
  ['FP-0033: The parser rejects syntax outside its subset instead of guessing', () => {
    unparseable(variant('permissions:\n  contents: read\n', 'permissions: &p\n  contents: read\n'), /Unsupported YAML syntax/);
    unparseable(variant('    runs-on: ubuntu-24.04\n', '    runs-on: *runner\n'), /Unsupported YAML syntax/);
    unparseable(variant('    runs-on: ubuntu-24.04\n', '    runs-on: !!str ubuntu-24.04\n'), /Unsupported YAML syntax/);
    unparseable(variant('permissions:\n  contents: read\n', 'permissions: { contents: read }\n'), /Unsupported YAML syntax/);
    unparseable(variant('    runs-on: ubuntu-24.04\n', '\truns-on: ubuntu-24.04\n'), CHARACTER);
    unparseable(variant('    runs-on: ubuntu-24.04\n', '    runs-on: ubuntu-24.04\n    runs-on: windows-2025\n'), /Duplicate key: runs-on/);
    unparseable(variant('      - name: Run a gate\n', '      - name: Run\n          a gate\n'), /Unexpected indentation|Expected a mapping key/);
    unparseable(variant('name: Fixture\n', '---\nname: Fixture\n'), /Expected a mapping key/);
    unparseable(variant('name: Fixture\n', 'name: "Fixture\n'), /quoted scalar must end/);
    unparseable(variant('name: Fixture\n', '"name": Fixture\n'), /Expected a mapping key/);
    unparseable(variant('name: Fixture\n', '? name\n: Fixture\n'), /Expected a mapping key/);
    unparseable(variant('name: Fixture\n', 'name: a: b\n'), /cannot contain ": "/);
    unparseable(variant('    branches: [master]\n', '    branches: [master,\n      develop]\n'), /flow sequence must close/);
    unparseable(variant('    branches: [master]\n', '    branches: [[master]]\n'), /Unsupported flow sequence item/);
    unparseable(variant('name: Fixture\n', 'name: "Fix\\qture"\n'), /Unsupported escape/);
    unparseable('', /The workflow is empty/);
  }],
  ['FP-0033 7: Characters that a YAML parser reads as line breaks or separators fail to parse', () => {
    const hidden = separator => variant('    runs-on: ubuntu-24.04\n', `    runs-on: ubuntu-24.04 # note${separator}    continue-on-error: true\n`);
    for (const separator of ['\u0085', '\u2028', '\u2029', '\r']) unparseable(hidden(separator), CHARACTER);
    unparseable(variant('  pull_request:\n', '  pull_request_target:\t# note\n'), CHARACTER);
    unparseable(variant('name: Fixture\n', 'name: Fixtur\u00e9\n'), CHARACTER);
    assert.deepEqual(checkWorkflow(`\uFEFF${BASE}`), []);
  }],
].map(([name, fn]) => ({ name, fn }));

if (process.argv[1] && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  console.log('TAP version 13');
  let failures = 0;
  for (const [i, c] of workflowCases.entries()) {
    try { await c.fn(); console.log(`ok ${i + 1} - ${c.name}`); }
    catch (e) { failures++; console.log(`not ok ${i + 1} - ${c.name}\n  ---\n  message: ${JSON.stringify(e.message)}\n  ...`); }
  }
  console.log(`1..${workflowCases.length}\n# tests ${workflowCases.length}\n# pass ${workflowCases.length - failures}\n# fail ${failures}`);
  process.exitCode = failures ? 1 : 0;
}
