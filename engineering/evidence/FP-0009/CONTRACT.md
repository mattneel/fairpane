# FP-0009 task contract

## Identity

Task ID: `FP-0009`, "Implement DOM identity and mutation foundations".
Workstream: `html-dom`.
Base: commit `93dcaf0`.
Prerequisites: `FP-0005` and `FP-0006`, accepted.
Assigned role: `fairpane-core`.

## Sources

- DOM Standard, node tree, "ensure pre-insert validity", "pre-insert", "insert", "append", "replace", "remove", "pre-remove", and "adopt": <https://dom.spec.whatwg.org/>.

## Behavior

### Node store

`src/dom.zig` defines a node store that owns every node of one engine.
A node is a document, a document fragment, a document type, an element, a text node, a comment, or a processing instruction.
Each node has a stable identity: a generational handle from `src/handles.zig` with a fresh owner per store.
A handle from another store returns `error.WrongOwner`, and a handle to a freed node returns `error.StaleHandle`.

Each node records its node document, its parent, its first and last child, and its previous and next sibling.
A text, comment, or processing-instruction node stores its data as a lossless `WebString` from `src/web_string.zig`.
An element stores its namespace and local name.

### Tree mutation

The store implements these DOM Standard algorithms with their exact validity checks and error kinds.

| Operation | Algorithm |
| --- | --- |
| `insertBefore(parent, node, child)` | Pre-insert, including "ensure pre-insert validity". |
| `appendChild(parent, node)` | Append. |
| `replaceChild(parent, node, child)` | Replace, with its own validity checks. |
| `removeChild(parent, child)` | Pre-remove, then remove. |
| `adopt(node, document)` | Adopt, which removes the node from its parent and changes the node document of its inclusive descendants. |

A validity failure returns `error.HierarchyRequest` or `error.NotFound` as the standard names them, and it changes nothing.
Inserting a node that already has a parent removes it from that parent first.
Inserting a document fragment moves its children, in order, and leaves the fragment empty.
Insertion and removal do not allocate, so they cannot fail for lack of memory.

### Trace roots

The store defines the roots that keep nodes alive for later VM integration.
Every document node is a root.
A node that the host retains through `retain` is a root until a matching `release`.
A root keeps its whole connected tree alive, because a script can reach any node of a tree through parent and child links.
`sweep` frees every node that no root reaches, and it reports how many nodes it freed.
`forEachRoot` visits each root exactly once, so a collector can later mark from the same set.

### Iteration

The child iterator records the next sibling before it yields a child.
Removing the yielded child neither skips nor repeats another original child.
A child inserted before the recorded next sibling is not visited.

### Teardown

Destroying the store frees every node, including retained nodes, detached subtrees, and documents, and it leaks nothing.

## Exact test cases

Each case lives in `src/dom.zig` and runs through `zig build test`.
After every mutation in every case, an invariant checker validates every link of the whole store.

1. `appendChild` and `insertBefore` maintain parent, child, and sibling links for first, middle, and last positions.
2. Every condition of "ensure pre-insert validity" returns its standard error and changes nothing, with one fixture per condition.
3. Every condition of the replace algorithm's validity checks returns its standard error and changes nothing.
4. `removeChild` with a child of another parent returns `error.NotFound`, and a valid removal unlinks the child completely.
5. Inserting a document fragment moves its children in order and empties it, and a document parent counts the fragment's element children against its single-element rule.
6. `adopt` removes the node from its old parent and changes the node document of every inclusive descendant.
7. Inserting a node that already has a parent moves it and leaves the old parent consistent.
8. `forEachRoot` visits every document and every retained node once.
   `sweep` frees an unreachable detached subtree, keeps a retained one, and keeps the whole tree of a retained descendant.
9. Removing the yielded child during iteration visits every other original child exactly once, and a child inserted before the recorded next sibling is not visited.
10. Destroying a store with documents, retained nodes, and detached subtrees leaks nothing.
11. `std.testing.checkAllAllocationFailures` runs a scenario with node creation, text data, insertion, adoption, retention, and sweeping.
    Each induced failure returns `error.OutOfMemory`, changes nothing, and leaks nothing.
12. A handle from another store returns `error.WrongOwner`, and a handle to a swept node returns `error.StaleHandle`.

## Evidence

Record `tests-before.log`, an uncached `tests-after.log`, and a mutation control under `engineering/evidence/FP-0009/raw/`.
The mutation control skips the inclusive-ancestor check in "ensure pre-insert validity", stores its exact diff beside its log, and fails case 2.
The integrator records `HEAD`, the staged diff, and file hashes before it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0009/gates`.

## Authority

Writable paths: `src`, `tests`, `api`, `include`, and `build.zig`.
Protected paths stay unchanged.
Required reviewer: `fairpane-review`.

## Non-goals

- No HTML parser, script binding, event dispatch, attribute storage, or C ABI exposure exists in this task.
- Shadow trees, slots, and custom elements belong to later tasks.
