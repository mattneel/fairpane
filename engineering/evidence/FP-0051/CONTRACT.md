# FP-0051 task contract

## Identity

Task ID: `FP-0051`, "Close the FP-0002 review findings".
Workstream: `laboratory`.
Base: commit `9ee1725`.
Prerequisites: `FP-0002`, accepted.
Assigned role: the root integrator, which implemented FP-0002.
Source findings: `engineering/evidence/FP-0002/reviews/review-3-accept.json`.

## Behavior

### Verifier location

`enclosingGitDirectory(directory)` in `tools/attest.mjs` finds the Git common directory of the work tree that contains a directory.
It walks up from the directory's real path and stops at the first `.git` entry.
A `.git` directory is the common directory.
A `.git` file names a linked work tree's Git directory, and that directory's `commondir` file names the common directory.
A `.git` file that names no Git directory is a tool error, so it cannot pass as the absence of a repository.
The function returns null when no `.git` entry exists up to the file system root.
It runs no Git command, so Git's ownership checks and message language cannot change its answer.

`attest-verify` reports `verified-advisory` with exit status 3 when the verifier root lies inside the candidate's top-level directory or Git directory, or when the verifier root's enclosing Git common directory is the candidate's.

### Candidate lookup

The commit lookup reports `unknown-candidate` only when Git exits with status 1, or with status 0 for another object.
Any other status is a tool error that quotes Git's message.

### Trust-policy location

`loadTrustPolicy` resolves the policy path once, both lexically and to its real path.
It rejects the policy as `unprotected-policy` when either form lies inside the candidate's top-level directory or Git directory.
It reads the real path that it checked.

### Documentation

ADR 0002 and `tools/README.md` state that path comparison cannot detect a UNC or administrative-share alias of the candidate, such as `\\localhost\C$\...`.

## Exact test cases

The cases extend `tools/attest.test.mjs`.

1. A copy of `tools/` inside a linked work tree of a fixture candidate verifies a signed record for that candidate and reports `verified-advisory` with exit status 3.
2. `enclosingGitDirectory` returns the fixture's common directory for its top-level directory, a nested subdirectory, and a linked work tree, and it throws for a `.git` file without a `gitdir:` line.
3. A corrupted loose commit object makes `candidateIdentity` throw a tool error, while a missing commit still fails as `unknown-candidate`.
4. A policy path inside the candidate that passes through a junction, or a directory symbolic link on POSIX, to a file outside the candidate fails as `unprotected-policy`.
5. The outside-repository assertion of case 14 expects "cannot be read" when `enclosingGitDirectory` reports no repository for the directory, and otherwise expects a tool error naming the top-level directory.

## Evidence

Record `tests-before.log` with the new cases failing, `tests-after.log`, and the standalone verifier run under `engineering/evidence/FP-0051/raw/`.
Record `HEAD` and a status with untracked files before `repo-check` and `controller-test` run with `--evidence-dir engineering/evidence/FP-0051/gates`.

## Authority

Writable paths: `tools`, `tests`, `engineering/decisions`, and `engineering/evidence`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No protected runner, signing key, or file-identity comparison by volume serial number exists in this task.
