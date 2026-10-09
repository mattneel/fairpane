// Mutation-control logic for controls/mutants.mjs. It is separate so the controller tests can exercise it.

/** Parse the TAP output of tools/selftest.mjs into one entry per test name, with each failure's message. */
export function parseTap(stdout) {
  const tests = new Map();
  let last = null;
  for (const line of stdout.split(/\r?\n/)) {
    const result = /^(not ok|ok) \d+ - (.*)$/.exec(line);
    if (result) { last = { ok: result[1] === 'ok', line, message: null }; tests.set(result[2], last); continue; }
    const message = /^ {2}message: (.*)$/.exec(line);
    if (message && last && !last.ok && last.message === null) last.message = JSON.parse(message[1]);
  }
  return tests;
}

/**
 * Run the unmutated suite first, then each mutant of `source`.
 * A failed baseline stops the control, because a later failure would not be attributable to a mutation.
 * `runSuite(text)` runs the suite with `text` as the mutated module, or unmutated for `null`, and returns `{ status, stdout }`.
 * Each mutant is `[name, from, to, target]`, where `from` occurs once in `source` and `target` matches one test name.
 */
export function runControl({ source, mutants, runSuite, log }) {
  const baseline = runSuite(null), base = parseTap(baseline.stdout);
  const failing = [...base.values()].filter(t => !t.ok);
  log(`BASELINE exit ${baseline.status}: ${base.size} tests, ${failing.length} failing`);
  for (const t of failing) { log(`BASELINE-FAILED ${t.line}`); log(`  message: ${JSON.stringify(t.message)}`); }
  if (baseline.status !== 0 || base.size === 0 || failing.length) {
    log('The unmutated baseline did not pass, so no mutant ran.');
    return { baseline: false, killed: 0, survived: mutants.length };
  }
  let killed = 0, survived = 0;
  for (const [name, from, to, target] of mutants) {
    const targets = [...base.keys()].filter(n => target.test(n)), sites = source.split(from).length - 1;
    if (sites !== 1 || targets.length !== 1) {
      survived++;
      log(`SETUP-FAILED ${name}: ${sites} mutation sites, ${targets.length} target tests`);
      continue;
    }
    const run = parseTap(runSuite(source.replace(from, to)).stdout).get(targets[0]);
    if (run && !run.ok) { killed++; log(`KILLED ${name}: ${run.line}`); log(`  message: ${JSON.stringify(run.message)}`); }
    else { survived++; log(`SURVIVED ${name}: ${run?.line ?? `(target test did not run: ${targets[0]})`}`); }
  }
  log(`mutants: ${mutants.length}, killed: ${killed}, survived: ${survived}`);
  return { baseline: true, killed, survived };
}
