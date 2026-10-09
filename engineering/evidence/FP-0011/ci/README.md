# FP-0011 continuous integration record

`ci-record.log` records `gh run view` of both attempts of `Gates` run 37926644057, and the failed-step log of attempt 1.
That run tested `a1b2d1c`, the commit that holds the revision 1 evidence and the integrator's measurement rerun.

| Attempt | Created | Windows gates | Linux gates | Conclusion |
| --- | --- | --- | --- | --- |
| 1 | 11:54:39Z | success | failure | failure |
| 2 | 12:11:28Z | success, from attempt 1 | success | success |

In attempt 1, the Linux job failed at the step `Install the locked Zig compiler` with `Fairpane: fetch failed`, before any gate ran.
Its upload step then failed with `No files were found with the provided path: out/evidence/`, as `if-no-files-found: error` requires.
Attempt 2 reran only the failed Linux job, and every Linux gate passed.

The integrator accepted FP-0011 in `837fcdd` at 12:07:29Z, after attempt 1 failed and before attempt 2 started.
That order did not follow `docs/AGENT_OPERATIONS.md`, which says that a failed run blocks acceptance.
Attempt 2 passed on the same commit, so the acceptance stands on that run.
The installer does not retry a failed download, so a transient network failure fails the job.
