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
