# Operations rule reviews

This directory records the independent approval of changes to acceptance policy in `docs/AGENT_OPERATIONS.md`.
`AGENTS.md` requires each such change to be separate and independently approved.

## Fixed-head replacement of a failed Gates run

The rule in "Git operations" required every failed `Gates` run between a task's implementation commit and its acceptance to have a passing rerun of the same head.
Linux `zig-test` timed out on several heads before `9d5638b` fixed the cause, so the integrator proposed that a passing run of a later head containing the fix may replace that rerun under stated conditions.

| Commit | Change | Review | Verdict |
| --- | --- | --- | --- |
| `483a239` | First proposal | `reviews/review-1-reject.json` | reject: one major and four minor findings |
| `c315be1` | Bounds the replacing head to the acceptance range, ties the cause to the failed step, requires a predating acceptance or review of the fix, and forbids gate, workflow, toolchain, and test changes in the range | `reviews/review-2-approve.json` | approve, with one minor finding and two notes |
| `3bab256` | Names the diffed paths, including `tools/lib.mjs` and `build.zig`, requires at least ten concluded runs for an intermittent cause, and covers fixes that span several commits | `reviews/review-3-approve.json` | approve: the change only tightens `c315be1` |

The reviewer was agent `PlanReview1` (`fairpane-review`), which did not author the change.
Each record is the reviewer's returned output, copied from the session transcript without change.
Review 3's two notes ask for optional wording and would only make the rule stricter, so the text stays as approved.
