// FP-0098 revision 1: the case-duration method of raw/controller-tests-after-r1.log.
// `node tools/fairpane.mjs record --env NODE_OPTIONS=--import=./engineering/evidence/FP-0098/raw/case-durations-r1.mjs`
// preloads this module into `node tools/fairpane.mjs test` and the `tools/selftest.mjs` process that it starts.
// It changes no test and no runner line. In the controller-test process only, it removes NODE_OPTIONS again,
// so no command that a test starts loads it, and after each `ok` or `not ok` line it prints `# elapsed_ms <ms>`.
// `<ms>` is the whole milliseconds since the previous result line, or since `TAP version 13` for the first case.
// The runner does nothing between two result lines except run the next case, so `<ms>` is that case's run time.
if (/[\\/]tools[\\/]selftest\.mjs$/.test(process.argv[1] ?? '')) {
  delete process.env.NODE_OPTIONS;
  const print = console.log;
  let last = null;
  console.log = (...args) => {
    print(...args);
    const line = String(args[0]);
    if (line === 'TAP version 13') last = performance.now();
    else if (last !== null && /^(?:not )?ok \d+ - /.test(line)) {
      const now = performance.now();
      print(`# elapsed_ms ${Math.floor(now - last)}`);
      last = now;
    }
  };
}
