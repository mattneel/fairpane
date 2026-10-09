# FP-0033 evidence

## Scope

Task `FP-0033` runs the repository gates in GitHub Actions.
The frozen contract is `engineering/evidence/FP-0033/CONTRACT.md`, based on commit `7bc9ace`.
The isolated `fairpane-core` worker `FP0033Actions` wrote `.github/workflows/gates.yml`, the package-free checker `tools/workflow-check.mjs`, and its eleven cases.
The root integrator applied the patch, ran the gates, pushed commit `24c0c64`, and observed the first GitHub run.

## Contract checks

| Check | Evidence |
| --- | --- |
| 1. `actionlint` at a pinned version with a verified digest reports no finding. | `raw/actionlint-download.log`, `raw/actionlint-digest.log`, and `raw/actionlint.log`: actionlint 1.7.12, digest `6e7241b5…f6e9` from the release checksum file, and zero errors. The first `findstr` attempt in the digest log failed on a path separator, and the second succeeded. |
| 2-4. The checker rejects unpinned actions, wider permissions, `continue-on-error`, persisted checkout credentials, and `pull_request_target`. | The eleven `workflow-check` cases in the controller suite, which passes 118 of 118 in the integration gate. |
| 5. Both jobs succeed on GitHub for the integration commit. | `raw/github-run-37873082602.log`: run 37873082602 for `24c0c648`, conclusion `success`, with the Windows job's 14 steps and the Linux job's 13 steps all successful. |

The worker's `raw/tests-after.log` exited with status 1, because two FP-0002 cases failed in the worker's work tree with "The candidate must be a full 40-hex commit ID."
Those failures came from that work tree's Git state, not from FP-0033, and the integration receipt is the authoritative run.
`raw/tests-before.log` is a baseline without the new cases, not a failing run of them.

`raw/action-releases.log` and `raw/action-tag-refs.log` record how each action's release tag resolved to its pinned commit.
`raw/zig-archive-head.log` records the worker's check of the locked Zig archive URL that the runners download.

## Integration records

`raw/integration-binding.log` records `HEAD` and the staged file list before the gates ran.

- `gates/2026-10-09T02-07-08-831Z-repo-check-bb98454c.json`
- `gates/2026-10-09T02-07-09-019Z-controller-test-bc5b0cfe.json`

## Revision 1

`reviews/review-1-reject.json` found that the checker split lines only at LF, so NEL, LS, or PS after a comment could hide a key that YAML parsers read.
`reviews/security-review-1-reject.json` found that gate receipts did not bind `.github`, which the controller tests read.
Commit `7bbe196` implements contract revision 1, and policy commit `29f2135` adds `.github` to `source_roots`.

| Check | Evidence |
| --- | --- |
| Red baseline | `raw/revision-1-tests-before.log` runs the new test file against the old checker, with a stub `gateStepProblems` that reports nothing: 9 of 14 pass, and the workflow_run, expression, gate-step, tab, and line-break cases fail. |
| 6-10 | The fourteen `workflow-check` cases pass in the controller suite: 129 of 129 on Node in the receipts below, and 129 of 129 on Bun in `raw/revision-1-tests-bun.log`. |
| 11 | `raw/revision-1-actionlint.log` downloads actionlint 1.7.12, matches digest `6e7241b5…f6e9` to the release checksum file, records `HEAD` `29f2135` and the SHA-256 of both workflow files, and reports 0 errors in 2 files. The shellcheck and pyflakes rules were disabled, because those tools are absent. |

`raw/revision-1-binding.log` records `HEAD` `29f2135` and a status whose untracked files lie outside every source root.

- `gates/2026-10-09T02-41-12-231Z-repo-check-cde06900.json`
- `gates/2026-10-09T02-41-12-409Z-controller-test-574028d3.json`

## Revision 2

`reviews/review-2-reject.json` found that `gateStepProblems` checked only `shell:` and `if:`.
A workflow or job `defaults.run.shell`, an `env` such as `NODE_OPTIONS`, a `working-directory`, a `container`, or an extra action could still let a gate step exit 0 without running.
`reviews/security-review-2-accept.json` reported the same gap and further minor and note findings.
A step output could reach a shell through `run:`, unreviewed triggers were accepted, the `pages.yml` problem text did not name its grants, and an upload step without `if:` reported nothing.
Review 2 also noted a block scalar form that the checker accepted and libyaml rejects.

The `fairpane-core` worker `FP0033Revision2` implemented contract revision 2 on base `acd7a5a` in `tools/workflow-check.mjs`, `tools/workflow-check.test.mjs`, and `tools/README.md`.
`gateWorkflowProblems` replaces `gateStepProblems` with allowlists.
Neither workflow file changed.
`gates.yml` still has no problem, and the `pages.yml` list now reads `Line 49: Job deploy grants a permission other than contents: read (pages: write, id-token: write).`
The Gates test now also asserts each job's full step sequence, including the `uses:` actions.

| Check | Evidence |
| --- | --- |
| Red baseline | `raw/revision-2-tests-before.log` records `HEAD` `acd7a5a` and the old checker blob `ef953b17`. It records the `node -e` command that stages the old checker, the new tests, and both workflows under `out/fp0033-rev2-before`, and that appends the stub `export { gateStepProblems as gateWorkflowProblems };`. It records the staged blob IDs and the run, which passes 13 of 19 cases and fails 6. Cases 12 through 16 fail on the new checks. Case 1 and case 15 fail at their reviewed-list assertion, because the old `pages.yml` problem did not name its grants. |
| 12-16 | `raw/revision-2-tests-after.log` records `git hash-object` of both workflows and the changed checker files. `node tools/workflow-check.test.mjs` passes 19 of 19, and `node tools/fairpane.mjs test` passes 148 of 148, both with exit status 0. |

The integrator still records `git show --stat` of the revision 2 commit, `git hash-object` of each workflow file at that commit, the gate receipts, `actionlint`, and the GitHub run.

## Limits

Workflow receipts are unsigned local integrity records, as their artifact names state.
A pull request runs its own workflow, checker, and controller, so its green check enforces nothing independently of that pull request.
`install-zig` accepts an existing compiler directory after only a version check.
Receipts do not record the runner image version, so later runs on the same commit can use different host tools.
Branch protection that requires these checks remains an owner action outside the repository.
