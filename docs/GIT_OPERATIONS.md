# Git and GitHub operations

## Standard

Fairpane is built in public at <https://github.com/mattneel/fairpane>.
The history is part of the public record, so every commit must be clean, truthful, and reproducible.
Every agent and maintainer keeps Git and GitHub operations immaculate.
A careless commit, a rewritten public commit, or a leaked credential is a defect.

## Owner decisions

On October 8, 2026, the owner authorized public development on the remote `origin`.
The owner's instruction was to always commit and push.
On October 9, 2026, the owner reported that pushing every commit floods CI and asked that batched pushes be codified here, as "Push rules" states.
The remote URL is `git@github.com:mattneel/fairpane.git`.
The integration branch is `master`.
Do not create, rename to, or push a branch named `main`.
The outbound license remains open in `LICENSE-DECISION.md`.
Public visibility does not select a license.

## Commit and push procedure

1. Run `git status --short` and confirm that every change belongs to the current checkpoint.
2. Stage the intended paths.
3. Run `git diff --cached --stat` and read the staged diff.
4. Check the staged diff for credentials, tokens, private data, and machine-local configuration dumps.
5. Run `node tools/fairpane.mjs check` and `node tools/fairpane.mjs test`.
6. Run the gates that the change affects.
7. Commit with a message that follows the message rules.
8. Run `git status --short` and confirm a clean working tree.
9. At a push boundary, run `git push origin master`; otherwise keep the commit local and continue with the next checkpoint.
10. After a push, run `git status -sb` and confirm that `master` matches `origin/master`.

## Commit rules

- Commit each coherent checkpoint as soon as its checks pass, and push it at the next push boundary.
- Keep one logical change in each commit.
- Keep acceptance-policy changes, compiler upgrades, and implementation changes in separate commits.
- Leave the repository check and controller tests passing at every commit on `master`.
- Never commit credentials, tokens, private user data, or full tool configuration dumps.
- Never commit compiler binaries, build output, downloaded corpora, or other third-party bulk data.
- Commit generated or downloaded files only when a task requires them and records their provenance.
- Keep evidence byte-exact.
  `engineering/evidence/.gitattributes` disables line-ending conversion there.
- After an evidence commit, check each committed blob against the recorded digests.
- Change line-ending normalization only in a dedicated commit.

## Push rules

Each push runs the full `Gates` workflow on Windows and on Linux for the pushed head, however many commits the push carries.
One push for each commit floods CI, so commits are pushed in batches.

- Push only at a push boundary:
  - before a review request that names a commit, because reviewers read commits from `origin`;
  - before an acceptance that needs the `Gates` run of a head that is still local;
  - before dispatching the `Gates` workflow, which runs on the pushed head;
  - before a session ends, and before the handoff names a head.
- Push again only after the previous push's `Gates` run has concluded, unless a session is ending.
- Dispatch the `Gates` workflow only when a contract requires dispatched runs.
  One set of dispatched runs on a head serves every contract that asks for runs on that head.
  Keep at most two dispatched runs queued or in progress at once.
- Never cancel a run to make room: the acceptance rule in `docs/AGENT_OPERATIONS.md` requires a concluded run of the same head to replace a cancelled one.
- Run the checks of the commit procedure before every commit, because a batch's run tests only its head.

## Message rules

- Write the subject as `<scope>: <imperative summary>` in at most 72 characters.
- Use a task ID such as `FP-0004` as the scope for task work.
- Use `repo`, `docs`, `tools`, `engineering`, or `ci` as the scope for other work.
- Leave one blank line after the subject.
- Wrap the body at 72 columns.
- State what changed, why it changed, which evidence supports it, and which failures remain.
- Make no claim that the recorded evidence does not support.
- End agent-made commits with the trailer `Assisted-by: OMP <version>`.

## History rules

- Keep `master` linear.
- Integrate reviewed worker patches with `git apply --index` instead of merge commits.
- Never force push.
- Never amend, rebase, reset, or delete a pushed commit.
  Correct a pushed mistake with a follow-up commit.
- Never amend a local commit after its ID appears in evidence, a review request, or the handoff.
- Never move or delete a pushed branch or tag.
- Never bypass hooks with `--no-verify`.
- Never invent an identity or change global Git configuration.
  Commits use the owner's configured identity.

## Worktrees and session boundaries

- Run concurrent writers in isolated worktrees and review each patch before it reaches `master`.
- Remove temporary worktrees after use.
- Keep `git worktree list` limited to the main checkout and active isolated workers at a checkpoint.
- Leave no stash entries.
- Commit and push all completed work before a session ends.
- Record the pushed head commit and any intentional uncommitted state in `engineering/HANDOFF.md`.

## GitHub rules

- Do not create repositories, organizations, deploy keys, tokens, webhooks, or apps without owner authorization.
- Do not change repository settings without owner authorization.
- Keep credentials, private data, and uncoordinated vulnerability details out of issues, pull requests, and discussions.
- Give each pull request one task or decision.
- List acceptance status, evidence paths, protected-path changes, and unresolved failures in each pull request.
- Pin each third-party action in a workflow to a full commit SHA with a version comment.
- Grant each workflow job only the permissions it needs.
- Never expose secrets to untrusted pull requests.
- Never run untrusted pull request code from a `pull_request_target` workflow.
- Create release tags as annotated tags only with owner authorization.
- Never move a release tag.

## Recommended repository settings

The owner controls these settings.

- Block force pushes to `master` and deletion of `master`.
- Require the controller and Zig checks once continuous integration runs them.
- Enable secret scanning and push protection.
