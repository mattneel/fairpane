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

`raw/action-releases.log` and `raw/action-tag-refs.log` record how each action's release tag resolved to its pinned commit.
`raw/zig-archive-head.log` records the worker's check of the locked Zig archive URL that the runners download.

## Integration records

`raw/integration-binding.log` records `HEAD` and the staged file list before the gates ran.

- `gates/2026-10-09T02-07-08-831Z-repo-check-bb98454c.json`
- `gates/2026-10-09T02-07-09-019Z-controller-test-bc5b0cfe.json`

## Limits

Workflow receipts are unsigned local integrity records, as their artifact names state.
Branch protection that requires these checks remains an owner action outside the repository.
