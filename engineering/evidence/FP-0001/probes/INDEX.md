# Agent tool-grant probes

Each file is the verbatim yielded output of one OMP subagent.
The root session copied each output with `cp agent://<job> <file>`.
The task tool reported the agent type, status, and duration in each result header.
`../raw/probe-attribution.log` extracts each spawn's requested agent type and each result header from the session transcript.
Each probe received a contract that allowed only its result tool.

| File | Job | Agent type | Status | Duration | Agent file state |
| --- | --- | --- | --- | --- | --- |
| `fairpane-core-run1.json` | `ProbeCoreTools` | `fairpane-core` | completed | 4.1 s | unchanged |
| `fairpane-review-run1.json` | `ProbeReviewTools` | `fairpane-review` | completed | 9.5 s | unchanged |
| `fairpane-spec-run1-before-repair.json` | `ProbeSpecTools` | `fairpane-spec` | completed | 5.6 s | declared `browser` |
| `fairpane-compiler-run1-before-repair.json` | `ProbeCompilerTools` | `fairpane-compiler` | completed | 6.9 s | declared `browser` |
| `fairpane-adversary-run2.json` | `Probe2Adversary` | `fairpane-adversary` | completed | 6.6 s | unchanged |
| `fairpane-bindings-run2.json` | `Probe2Bindings` | `fairpane-bindings` | completed | 6.4 s | unchanged |
| `fairpane-js-run2.json` | `Probe2Js` | `fairpane-js` | completed | 6.3 s | unchanged |
| `fairpane-platform-run2.json` | `Probe2Platform` | `fairpane-platform` | completed | 7.1 s | unchanged |
| `fairpane-text-run2.json` | `Probe2Text` | `fairpane-text` | completed | 6.3 s | unchanged |
| `fairpane-security-run2.json` | `Probe2Security` | `fairpane-security` | completed | 6.1 s | unchanged |
| `fairpane-spec-run2-after-repair.json` | `Probe2Spec` | `fairpane-spec` | completed | 5.9 s | `browser` removed |
| `fairpane-compiler-run2-after-repair.json` | `Probe2Compiler` | `fairpane-compiler` | completed | 6.0 s | `browser` removed |

The callable function names carry a leading underscore in the subagent runtime.
The logical tool names match the `tools` frontmatter names without that prefix.
Some probes report their job name in the `agent` field, and two report no name.
The agent type column comes from the task tool, not from the probe output.
