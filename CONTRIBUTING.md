# Contribution contract

## Current status

The project develops in public at <https://github.com/mattneel/fairpane> on the `master` branch.
External contributions wait until the owner ratifies the outbound license.
The following engineering rules apply to local agent work now.
Every commit and push follows `docs/GIT_OPERATIONS.md`.

## Contribution procedure

1. Select a task with accepted prerequisites.
2. Preserve its behavior contract and relevant specification references.
3. Add a failing test or benchmark baseline.
4. Implement the behavior inside the approved paths.
5. Run the applicable gates.
6. Preserve the actual evidence and unresolved failures.
7. Request independent review.
8. Update the durable task record after integration.

## Provenance

First-party implementations can follow standards and published algorithm descriptions.
A reference implementation is not permission to copy its source without license review.
Generated code records the generator and input revision.
Imported datasets record their source, exact revision, and license.

## Review

A change to acceptance policy travels separately from an implementation that benefits from that change.
A compiler upgrade travels separately from a feature change unless an explicit dependency requires both.
A public API change needs the interface owner and wrapper impact review.
