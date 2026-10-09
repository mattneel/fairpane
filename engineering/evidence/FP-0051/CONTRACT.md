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

## Revisions

Revision 1 follows the rejecting review `reviews/review-1-reject.json` of commit `199b279`.

### Trust-policy location

`loadTrustPolicy` resolves every existing directory on the way to the policy path, from the path itself up to the file system root.
It rejects the policy as `unprotected-policy` when any of those real paths lies inside a protected location.
An alias of the candidate root, such as a short name, a junction, a symbolic link to an ancestor, or a substituted drive, therefore cannot spell a path from outside the candidate.

### Candidate lookup

When the commit lookup exits with status 1, the verifier asks `git cat-file -e` whether the object exists.
A missing object, or an existing object of another type, fails as `unknown-candidate`.
An existing commit object that Git cannot read, such as one with a hash mismatch or a malformed body, is a tool error.

### Verifier location

`enclosingGitDirectories` replaces `enclosingGitDirectory`.
It walks from the directory's real path to the file system root and collects the common directory of every `.git` entry on the way, not only the first.
A `.git` directory that contains a `commondir` file yields the directory that the file names.
It strips only trailing CR and LF characters from `.git` files and `commondir` files, as Git does.
The verifier is advisory when any collected common directory is the candidate's.
Layouts that Git finds only through `GIT_DIR` or `core.worktree` are not detected, and the documentation says so.

### Revision test cases

6. A policy path spelled through a link outside the candidate that resolves to the candidate root, followed by a link inside the candidate to an outside file, fails as `unprotected-policy`.
7. A commit object overwritten by another commit's object, and a commit object with a malformed body, are tool errors, and a tree object ID fails as `unknown-candidate`.
8. A `.git` directory with a `commondir` file, and a repository nested inside a linked work tree of the candidate, both yield the candidate's common directory among the collected directories.
9. Case 14 derives its expected outside-repository error from `git rev-parse --show-toplevel` run without inherited `GIT_*` variables.

The revision evidence records a status that includes ignored files for every source root.

Revision 2 follows `reviews/review-2-reject.json` of commit `9b878bc`.
`git cat-file -t` reads only the stored header, so a corrupt object under the candidate's ID with a tree, blob, or tag header looked like a readable non-commit object.
After `cat-file -e` finds an object, the verifier peels it with `rev-parse --verify --quiet <id>^{object}`, which parses the object and checks its hash.
Only a readable object of another type fails as `unknown-candidate`, and every unreadable object is a tool error.
The documentation states that a bare Git directory on the verifier's path is not detected, and that a broken `.git` entry above the nearest repository is a tool error.

10. A tree's object stored under a commit's ID is a tool error, and case FP-0051 3 reports the outcome of every corruption fixture in one assertion.
