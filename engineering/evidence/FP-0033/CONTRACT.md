# FP-0033 task contract

## Identity

Task ID: `FP-0033`, "Run the repository gates in GitHub Actions".
Workstream: `laboratory`.
Base: commit `7bc9ace`.
Prerequisites: `FP-0001`, accepted.
Assigned role: `fairpane-core`.

## Behavior

`.github/workflows/gates.yml` defines a workflow named `Gates`.
It runs on every push to `master`, on every pull request that targets `master`, and on manual dispatch.
Its top-level permissions grant only `contents: read`, and no job widens them.
No step reads a secret, and no step uses `pull_request_target`.
Every action is pinned to a full commit SHA with a version comment.
Checkout never persists credentials.
Runs for the same pull request cancel superseded runs, while runs on `master` never cancel each other.

### Windows job

The job runs on a pinned Windows runner image label.
It installs the locked Zig compiler with `node tools/fairpane.mjs install-zig`, which checks the archive size and digest.
It runs these gates in order through `node tools/fairpane.mjs run <gate>`: `repo-check`, `controller-test`, `zig-fmt`, `zig-test`, `zig-build`, and `c-abi`.

### Linux job

The job runs on a pinned Ubuntu runner image label.
It installs the locked compiler the same way.
It runs `repo-check`, `controller-test`, `cross-windows-x86_64`, `cross-linux-aarch64`, and `cross-macos-aarch64`.

### Results

Each job uploads its gate receipts and logs as a workflow artifact, including after a failure.
The artifact name states that its receipts are unsigned local integrity records, not attestations.
Any failed, skipped, or timed-out gate fails its job, so no step uses `continue-on-error`.
The Node version comes from a pinned setup action and satisfies the controller's Node 22 or later requirement.

## Exact checks

1. `actionlint` at a pinned version with a verified digest reports no finding for the workflow.
2. A controller test parses `.github/workflows/gates.yml` and fails when any `uses:` reference lacks a full 40-hex commit SHA.
3. The same test fails when any job or the workflow grants a permission other than `contents: read`.
4. The same test fails when any step sets `continue-on-error`, when checkout persists credentials, or when the workflow uses `pull_request_target`.
5. After integration, the workflow runs on GitHub for the integration commit, and both jobs succeed.
   The integrator records the run identifier, conclusion, and job results with `gh run view --json`.

## Authority

Writable paths: `.github/workflows`, `tools`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewers: `fairpane-review` and `fairpane-security`.

## Non-goals

- No secret, signing key, or protected runner exists in this task.
- Branch protection settings remain an owner action outside the repository.

## Revisions

Revision 1 follows the rejecting reviews `reviews/review-1-reject.json` and `reviews/security-review-1-reject.json`.

### Checker changes

The checker accepts only printable ASCII text with LF or CRLF line ends, after an optional leading byte order mark.
Any other character, including a tab, a lone carriage return, NEL, LS, and PS, is a parse error with its line number.
Every `${{ }}` expression and every `if:` value is an expression.
An expression may call only `always` and `format`, and it may read only `github.event_name`, `github.run_id`, `github.event.pull_request.number`, and `steps.<id>.outputs.<name>`.
Any other name, index syntax, or unterminated expression or string literal is a problem.
A `workflow_run` trigger is a problem, as `pull_request_target` already is.
In the Gates workflow, no step sets `shell:`, and only an `actions/upload-artifact` step sets `if:`, with the exact value `${{ always() }}`.

### Revision checks

6. Every file under `.github/workflows` is checked, and each one's problems equal its reviewed list: none for `gates.yml`, and only the `deploy` job's permissions for `pages.yml`.
   A workflow file without a reviewed list fails the test.
7. Fixtures with NEL, LS, PS, a tab before a comment, a lone carriage return, and a non-ASCII letter each fail to parse.
8. Fixtures that read `secrets.X`, `github.token`, `github['token']`, `toJSON(github)`, `format('}}{0}', secrets.X)`, and a bare `if: secrets.X` each report a problem.
9. Fixtures with a `workflow_run` trigger, an `if:` on a gate step, a `shell:` on a gate step, and an upload step without `if: ${{ always() }}` each report a problem.
10. The test asserts the Gates workflow's concurrency group and cancellation expressions.
11. `actionlint` 1.7.12 runs on the integrated workflow, and the log records the SHA-256 of the linted file.

### Policy change

A separate `policy:` commit adds `.github` to `source_roots` in `engineering/policy.json`, so a gate receipt binds the workflow files that the controller tests read.

### Documentation

`tools/README.md` and the evidence README state that a pull request runs its own workflow, checker, and controller.
A green check on a pull request therefore enforces nothing independently of that pull request.
They also state that `install-zig` accepts an existing compiler directory after only a version check.

Revision 2 follows `reviews/review-2-reject.json` and the minor findings of `reviews/security-review-2-accept.json`.

### Revision 2 checker changes

`gateWorkflowProblems` replaces `gateStepProblems` and checks the Gates workflow against allowlists, not denylists.
The workflow may set only `name`, `on`, `permissions`, `concurrency`, and `jobs`.
A job may set only `name`, `runs-on`, `timeout-minutes`, and `steps`.
A run step may set only `name` and `run`, and its command must be `node tools/fairpane.mjs install-zig` or `node tools/fairpane.mjs run <gate>`.
An action step may set only `name`, `uses`, and `with`, and an `actions/upload-artifact` step must also set `if: ${{ always() }}`.
The only accepted actions are `actions/checkout` with the input `persist-credentials`, `actions/setup-node` with `node-version`, and `actions/upload-artifact` with `name`, `path`, and `if-no-files-found`.

For every workflow, a `run:` value may contain no `${{ }}` expression, so no expression can reach a shell.
Only the triggers `push`, `pull_request`, and `workflow_dispatch` are accepted, and any other trigger is a problem.
A permission problem names the exact grants, so a reviewed problem list binds the grants themselves.
A block scalar whose leading blank lines hold more spaces than its first content line fails to parse, as it does in libyaml.

### Revision 2 checks

12. Fixtures with `defaults.run.shell` at the workflow and job levels, `env` at each level, a step `working-directory`, a job `container`, an extra action step, a checkout `ref` input, a run step with another command, and an upload step without `if:` each report a problem from `gateWorkflowProblems`.
13. A fixture with `${{ steps.x.outputs.y }}` inside `run:` reports a problem.
14. Fixtures with the triggers `issue_comment` and `schedule` report problems.
15. Widening the `pages.yml` deploy job to `write-all` or adding `contents: write` changes its problem text, so the reviewed list fails.
16. The block scalar fixture of review 2 fails to parse.

The revision evidence records `git show --stat` of each revision commit, `git hash-object` of each workflow file, and the commands that stage the red baseline.

Revision 3 follows `reviews/review-3-reject.json`.
GitHub fetches `owner/repo@<sha>` for a commit in any fork of the repository, so a full SHA alone does not identify reviewed action code.
`workflowProblems` accepts only the reviewed commit and release tag of each accepted action, in every workflow.
`REVIEWED_ACTIONS` in `tools/workflow-check.mjs` lists them, and each SHA comes from a recorded release-tag lookup in the action's own repository.

17. Fixtures with another full SHA for an accepted action, the reviewed SHA under another version comment, and the reviewed SHA under another owner each report a problem, and owner and repository case does not matter.

The revision evidence records the GitHub run of the revision 2 evidence commit and of the revision 3 commit.
