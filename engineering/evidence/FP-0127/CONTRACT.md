# FP-0127 task contract

## Identity

Task ID: `FP-0127`, "Add shadow roots to the DOM store".
Workstream: `html-dom`.
Base: the commit that freezes this contract. It must contain the FP-0100 integration commit `f17b396`, because FP-0100 and FP-0127 both edit `src/dom.zig`.
The drafter read `master` `9fedf55` (`.git/logs/HEAD` line 345). For revision 3, the drafter re-read every cited repository line at `HEAD` `4266be8` (`.git/logs/HEAD` lines 346-349), and each line was unchanged.
Before the freeze, the integrator re-reads every cited line of `src/dom.zig`, `src/html/tree_dump.zig`, `src/css/css.zig`, `src/css/selectors.zig`, `src/css/style.zig`, `src/lab.zig`, `engineering/plan.json`, and `engineering/state.json` at the freeze base and corrects each citation.
Prerequisite: `FP-0009`, accepted (`engineering/state.json:166-167`). `FP-0100` is integrated at `f17b396` (`.git/logs/HEAD` line 305).
Dependents: `FP-0103` (`engineering/plan.json:3686-3709`) and `FP-0072` (`engineering/plan.json:3230-3251`).
A contract worker drafted this contract, and the root integrator freezes it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

This contract extends `engineering/evidence/FP-0009/CONTRACT.md` and `engineering/evidence/FP-0100/CONTRACT.md`. Those contracts stay in force wherever this contract does not change them.

### Integrator decisions

- D1. Sources.
  - The DOM Standard is `dom.bs` at `whatwg/dom` commit `3071e5f269448350fdea79bb284eedaf17bc431e`. Its local copy is `out/whatwg-dom-bs-3071e5f269448350fdea79bb284eedaf17bc431e`, with SHA-256 `1550b0f067278aac80c53d603495d1050ab04856d0ce8b9ad10eb23f98b9a847`. Every DOM line number is a line of that file, as `raw/standards-text.log` prints it.
  - The HTML Standard is the project's pin, `whatwg/html` `efc54f7b70858d9fcf06d1a5871ae215f448c029` (`specs/sources.json` S85). It is read from the local copy `out/whatwg-html-source-efc54f7b70858d9fcf06d1a5871ae215f448c029`, and every HTML line number is a line of that copy.
  - Evidence step 0 records both texts.
  - The `src/dom.zig` module comment moves its DOM citation (line 7, "Living Standard of 5 October 2026") to the pinned commit.
  - `src/css/css.zig` keeps its own DOM baseline sentence (line 5).
- D2. Representation.
  - `Kind` gains `shadow_root`. A shadow root is a DocumentFragment node in the standard's sense, so every step that tests for a `DocumentFragment` node treats `.document_fragment` and `.shadow_root` alike.
  - An element record gains its shadow root as `?NodeHandle`. A shadow root record holds its host and the fields below.
  - A shadow root never has a parent or siblings.
- D3. Frozen interface names. The cases cite these names, so the worker may not rename them: `Kind.shadow_root`, `ShadowRootMode` (`open`, `closed`), `SlotAssignmentMode` (`manual`, `named`), `CustomElementRegistryId`, `AttachShadowRootOptions`, `ShadowRootFields`, `attachShadowRoot`, `shadowRoot`, `shadowRootFields`, `setShadowRootDeclarative`, `setShadowRootAvailableToElementInternals`, `setShadowRootKeepCustomElementRegistryNull`, `AttachShadowRootError`, `ShadowRootError`, `error.NotAShadowRoot`, and `error.UnsupportedCustomElementRegistry`. The worker may name private helpers freely.
- D4. Custom element registries. No `CustomElementRegistry` object exists, and the FP-0026 frontier decomposition owns registries (`engineering/state.json:391`).
  - `CustomElementRegistryId` is an opaque `enum(u32) { _ }` that the store never issues.
  - A shadow root's `custom_element_registry` field holds that ID or null, and attach always stores null.
  - A non-null registry argument returns `error.UnsupportedCustomElementRegistry` after steps 1 to 4 and before step 5, so it changes nothing. The step 4 path ignores the registry and still succeeds.
  - Adopt step 3.2 runs as written. Store documents have no custom element registry, so the effective global registry is null, and the field stays null.
- D5. Custom element definitions and states.
  - The store has no definitions, no `is` value, and no custom element state.
  - Attach step 3 therefore always finds a null definition and throws nothing.
  - Attach step 9 never sets "available to element internals" to true. "Create an element" step 6 gives every element that has no definition the state "uncustomized" or "undefined" (`dom.bs` lines 7222-7237).
- D6. Parser-owned fields.
  - After attaching, the HTML parser sets "available to element internals" and "declarative" to true. It sets "keep custom element registry null" to true only when the start tag has a `shadowrootcustomelementregistry` attribute. These are HTML parsing, "in head" `template` start tag, steps 7.11.4, 7.11.5, and 7.11.7, at lines 146419-146420, 146422-146423, and 146428-146431 of the HTML copy.
  - The store exposes one setter per field for `FP-0103`. Each setter changes only its own field.
- D7. Replace step 6.
  - "Replace" step 6 (`dom.bs` 3222) adopts *node* itself into the parent's node document.
  - When *node* is a shadow root, the store follows that text literally. The shadow root and its shadow-including inclusive descendants take the parent's node document, while the host keeps its own ("adopt" step 3, `dom.bs` 6224-6226).
  - The `adoptNode()` step 2 guard (`dom.bs` 6296-6297) does not apply to "replace".
  - Case 6 row 6h pins this outcome.
  - `fairpane-spec` confirmed this reading in the pre-freeze check. The README records it as a probable editorial gap in the standard.
  - The base already adopts a plain fragment node itself at this step (`src/dom.zig:607-608`).
- D8. Roots.
  - `forEachRoot` keeps the FP-0009 set: every document and every retained node, each visited once.
  - A retained shadow root is a root. An unretained shadow root is never a root, and its host keeps it alive through `sweep`.
  - A root keeps its whole shadow-including tree alive in both directions, because script reaches a shadow root from its host and a host from its shadow root.
- D9. Ancestor check.
  - `isInclusiveAncestor` and `isInclusiveAncestorByWalk` (`src/dom.zig:893-911`) are replaced by a host-including pair with the same roles.
  - The FP-0098 leaf shortcut holds only for a node that has no child and no shadow root.
  - The FP-0098 test (`src/dom.zig:1521-1562`) keeps its name, fixture, and every assertion, including the count of 29. Only its seven calls change, each to the matching function of the new pair: the walk call at line 1549, and the shortcut calls at lines 1550 and 1557 to 1561.
  - The README records this amendment.
- D10. Unsupported shadow-tree behavior is recorded, not changed.
  - `src/css/selectors.zig`, `src/css/style.zig`, and `src/lab.zig` keep their behavior.
  - FP-0127 changes no row of `src/css/css.zig`.
  - The gaps are recorded in the `src/dom.zig` module comment and in the README, with the owners in "Records of unsupported behavior".
  - Case 14 pins the current behavior, so a later change is deliberate.
- D11. Stack.
  - Case 13 runs on a thread spawned with a 256 KiB stack in the Debug test build, as FP-0119 case 13 does (`tests/text/glyf_test.zig:555`). It records no stack measurement.
  - The task moves no helper out of `src/js/parser.zig`.
  - The frozen traversals are iterative, as "Mutation" and "Roots, sweep, iteration, and teardown" define them. Their native stack use does not grow with tree depth.
- D12. Test time. All FP-0127 cases together add at most 1 s to the `src/root.zig` profile total on the development host. The task adds no controller-test case.

### Observed facts that shaped the decisions

These facts hold at `9fedf55`, and every cited line was re-read at `4266be8`.

- `src/dom.zig:32-33`: "No shadow root ... exists yet. A host-including inclusive ancestor is therefore an inclusive ancestor."
- `src/dom.zig:62-70`: `Kind` has no shadow-root member, and `Payload` is `union(Kind)` (lines 155-163).
- These switches over the payload or `Kind` are exhaustive: `src/dom.zig` lines 236-250, 338-345, 383-386, 394-398, 434-438, 443-449, 561-564, 690-693, 726-729, 741-744, and 762-766, and `src/html/tree_dump.zig:75-122`. The arm at `tree_dump.zig:121` reads `.document, .document_fragment => unreachable`.
- `src/dom.zig:732-733`: "ensure pre-insert validity" step 2 calls `isInclusiveAncestor`, and line 732 says "No fragment has a host yet".
- `src/dom.zig:900`: the FP-0098 shortcut returns false for any node without children. A childless shadow host is still a host-including inclusive ancestor of its shadow tree, so the shortcut would be wrong after this task.
- `src/dom.zig:813`: `insert` tests `kindOf(node) == .document_fragment`.
- `src/dom.zig:865-879`: `adoptInto` walks tree order with `following` (lines 881-891), and line 866 says "No shadow root ... exists yet".
- `src/dom.zig:201`: `AdoptError` has no `HierarchyRequest`.
- Roots: `src/dom.zig:258-260`, `648-653`, and `657-674` make roots the documents and retained nodes. `markTree` (lines 940-951) climbs parent links only (line 943).
- `src/dom.zig:1050-1130`: `expectInvariants` is public since FP-0100 (`engineering/evidence/FP-0100/CONTRACT.md:177`). It uses checked lookups and bounds each loop by the node count. `fingerprint` (lines 1156-1167) hashes every record deeply.
- FP-0100 amended `newDoctype` (line 1181), `newProcessingInstruction` (line 1205), `allocationScenario`, and the FP-0009 case 12 rejected-call list for the new `createDocumentType` and `createProcessingInstruction` arguments (`engineering/evidence/FP-0100/CONTRACT.md:384-389`).
- `src/dom.zig:253-256`: character data is copied with `gpa.dupe`, which allocates once for non-empty data.
- `src/web_string.zig:61-63` and `148-151`: `fromCodeUnits` returns the empty string for length 0, and otherwise allocates once.
- `src/handles.zig:151-157`: the node table grows only when it has no free slot, to `len + len/2 + 8` slots, through `ensureTotalCapacityPrecise`. From empty, the first growth gives 8 slots, and the second gives 20.
- `src/js/heap.zig:685-700`: the heap verifier collects `forEachRoot` into a list with capacity `nodeCount()`.
- `src/css/selectors.zig:292-294`: every pseudo-class and pseudo-element returns `unsupported_selector`. `parentElement` (lines 546-549) returns null for a parent that is not an element.
- `src/css/style.zig:66-121`: `resolve` walks the document element and its element descendants through child links. `StyleMap.get` (lines 46-48) returns `error.NotStyled` for every other node.
- `src/lab.zig:40-48`: `Stage` declares `tree` and `style`, and `implemented` returns true only for `fetch`, `decode`, and `tokenize`.
- `src/css/css.zig:30` gives FP-0070 the pseudo-classes and pseudo-elements, and line 37 gives FP-0072 the encapsulation contexts.
- FP-0072 criterion 5 matches `:host`, `:host()`, and `:host-context()`, and criterion 6 reports `::slotted()` as unsupported (`engineering/plan.json:3245-3246`, plan commit `b24dcab`, `engineering/state.json:885`).
- The FP-0026 frontier note routes these items to FP-0026: custom element registries, `::part()`, slots, slot assignment, `::slotted()` matching, the flat tree, and the shadow-root DOM bindings. The bindings are `attachShadow()`, the `shadowRoot` getter, closed-mode hiding, event retargeting, and composed paths (`engineering/state.json:391`).
- FP-0103 criteria 5 and 7 dump declarative shadow roots (`engineering/state.json:971`).
- `specs/applicability/wpt.json:28-31`: 76620 discovered, 0 selected, and 76620 unclassified.

## Sources

- DOM Standard `dom.bs` at `3071e5f269448350fdea79bb284eedaf17bc431e`.
  - The file was retrieved on 2026-10-09 from <https://raw.githubusercontent.com/whatwg/dom/3071e5f269448350fdea79bb284eedaf17bc431e/dom.bs> into `out/whatwg-dom-bs-3071e5f269448350fdea79bb284eedaf17bc431e`. Its SHA-256 is `1550b0f067278aac80c53d603495d1050ab04856d0ce8b9ad10eb23f98b9a847`.
  - `raw/standards-text.log` prints each line cited below. The cited lines are:

  | Lines | Text |
  | --- | --- |
  | 203-228 | "valid element local name" |
  | 2371-2446 and 2466-2481 | The node tree constraints and the shadow tree |
  | 2725-2832 | "ensure pre-insert validity" and "pre-insert" |
  | 2910-3048 | "insert", with step 7.1 at 2957 |
  | 3205-3249 | "replace", with step 6 at 3222 |
  | 3282-3376 | "pre-remove" and "remove" |
  | 6213-6287 | "adopt", with step 3 at 6224-6226 |
  | 6289-6302 | `adoptNode()`, with step 2 at 6296-6297 |
  | 6307-6319 | Global and effective global custom element registries |
  | 6680-6691 | DocumentFragment host and host-including inclusive ancestor |
  | 6733-6763 | The ShadowRoot fields and their initial values |
  | 6806-6834 | Shadow-including tree order, root, descendant, and ancestor |
  | 7017-7020 | An element's shadow root and shadow host |
  | 7222-7237 | "create an element" step 6 |
  | 7905-7927 | Valid shadow host name |
  | 7932-7956 | `attachShadow()` |
  | 7958-8039 | "attach a shadow root" steps 1 to 15 |

- HTML Standard source at `efc54f7b70858d9fcf06d1a5871ae215f448c029`, with SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b` (the FP-0100 value). The cited lines are:
  - 78624-78678: "valid custom element name".
  - 146325-146431: the "in head" `template` start tag, read only to define what `FP-0103` needs. Step 7.11.4 is at 146419-146420, step 7.11.5 at 146422-146423, step 7.11.6 at 146425-146426, and step 7.11.7 at 146428-146431.
- CSS Cascade 5, section 6.1, "encapsulation contexts": <https://drafts.csswg.org/css-cascade-5/#encapsulation-contexts>. It is read only to define what `FP-0072` needs.
- Repository:
  - `AGENTS.md`, `docs/ARCHITECTURE.md`, and the `engineering/plan.json` entries FP-0127, FP-0103, FP-0072, FP-0070, FP-0068, FP-0100, FP-0019, and FP-0026.
  - `engineering/state.json` lines 391, 885, and 971.
  - The FP-0009 contract and README. FP-0100 amended the FP-0009 helpers `newDoctype` and `newProcessingInstruction`, `allocationScenario`, and the case 12 rejected-call list. FP-0127 uses those signatures, and it makes no other FP-0009 amendment except D9.
  - The FP-0100 contract, lines 177 and 384-389.
  - `engineering/evidence/FP-0098/README.md` lines 92-104.
  - The FP-0119 contract, case 13.
  - `src/dom.zig`, `src/html/tree_dump.zig`, `src/html/tree.zig`, `src/handles.zig`, `src/web_string.zig`, `src/css/css.zig`, `src/css/selectors.zig`, `src/css/style.zig`, `src/css/tests.zig`, `src/js/heap.zig`, `src/lab.zig`, and `tests/text/glyf_test.zig`.

## Behavior

### Files

| File | Change |
| --- | --- |
| `src/dom.zig` | The shadow-root kind and record, the element's shadow root, attach, accessors, and setters. The host-including check, shadow-including adopt, and marking. The invariant checker, cases 1 to 13, and the D9 amendment. A `.shadow_root` arm in every exhaustive switch. The module comment (lines 7 and 32-33) and the comments at lines 732 and 866 are restated. |
| `src/html/tree_dump.zig`, and every other exhaustive switch over `dom.Kind` or the node payload outside `src/dom.zig` at the base | Each switch gains a `.shadow_root` arm. In `writeNode`, the arm joins `.document, .document_fragment => unreachable`, because a shadow root is never a child. Given a shadow root as `root`, `writeChildren` writes its descendants as it does for a fragment. No dump line for a shadow root exists until `FP-0103`, and no FP-0100 expected dump changes. |
| `src/css/tests.zig` | Case 14, and a header that names it. |
| `src/css/style.zig` | The `StyleMap.get` comment (lines 46-47) adds that a shadow-tree element returns `NotStyled` until `FP-0072`. Behavior does not change. |
| `engineering/evidence/FP-0127/` | The logs, diffs, and README. |

FP-0127 changes no row of `src/css/css.zig` and nothing in `src/js/parser.zig`.

### Interface

```zig
pub const Kind = enum { document, document_fragment, shadow_root, document_type, element, text, comment, processing_instruction };
pub const ShadowRootMode = enum { open, closed };
pub const SlotAssignmentMode = enum { manual, named };
pub const CustomElementRegistryId = enum(u32) { _ };
pub const AttachShadowRootOptions = struct {
    mode: ShadowRootMode,
    delegates_focus: bool,
    serializable: bool,
    slot_assignment: SlotAssignmentMode,
    clonable: bool,
    custom_element_registry: ?CustomElementRegistryId = null,
};
pub const ShadowRootFields = struct {
    host: NodeHandle,
    mode: ShadowRootMode,
    delegates_focus: bool,
    available_to_element_internals: bool,
    declarative: bool,
    serializable: bool,
    slot_assignment: SlotAssignmentMode,
    clonable: bool,
    custom_element_registry: ?CustomElementRegistryId,
    keep_custom_element_registry_null: bool,
};
pub const AttachShadowRootError = LookupError || error{ NotAnElement, NotSupported, UnsupportedCustomElementRegistry, OutOfMemory, HandleSpaceExhausted };
pub const ShadowRootError = LookupError || error{NotAShadowRoot};
pub const AdoptError = LookupError || error{ NotADocument, NotSupported, HierarchyRequest };

/// Runs "attach a shadow root" and returns the element's shadow root afterward, as attachShadow() step 5 does.
pub fn attachShadowRoot(store: *Store, element: NodeHandle, options: AttachShadowRootOptions) AttachShadowRootError!NodeHandle;
/// The element's shadow root concept in either mode, or null. Closed-mode hiding belongs to the binding.
pub fn shadowRoot(store: *Store, element: NodeHandle) AttributeError!?NodeHandle;
pub fn shadowRootFields(store: *Store, shadow: NodeHandle) ShadowRootError!ShadowRootFields;
pub fn setShadowRootDeclarative(store: *Store, shadow: NodeHandle, value: bool) ShadowRootError!void;
pub fn setShadowRootAvailableToElementInternals(store: *Store, shadow: NodeHandle, value: bool) ShadowRootError!void;
pub fn setShadowRootKeepCustomElementRegistryNull(store: *Store, shadow: NodeHandle, value: bool) ShadowRootError!void;
```

For a shadow root, these accessors return these results:

- `parentNode`, `previousSibling`, and `nextSibling` return null.
- `characterData`, `elementName`, `documentTypeIds`, and `processingInstructionTarget` return null.
- `attributes`, `setAttribute`, `attribute`, and `removeAttribute` return `error.NotAnElement`.
- `appendData` returns `error.NotCharacterData`.
- `isHtmlDocument`, `documentMode`, and `setDocumentMode` return `error.NotADocument`.

`shadowRoot` returns `error.NotAnElement` for every node that is not an element.

### Attach a shadow root

`attachShadowRoot` performs these checks and steps in this order (`dom.bs` 7958-8039):

1. It checks the handle and returns `WrongOwner` or `StaleHandle`, as FP-0009 does. A node that is not an element returns `error.NotAnElement`.
2. Step 1: a namespace other than exactly `http://www.w3.org/1999/xhtml` returns `error.NotSupported`.
3. Step 2: a local name that is not a valid shadow host name returns `error.NotSupported`. A valid shadow host name is a valid custom element name or one of exactly these 18 strings: `article`, `aside`, `blockquote`, `body`, `div`, `footer`, `h1`, `h2`, `h3`, `h4`, `h5`, `h6`, `header`, `main`, `nav`, `p`, `section`, and `span` (`dom.bs` 7905-7927). Names compare by code units.
4. A valid custom element name (HTML lines 78624-78678) meets all of these conditions:
   - It has at least 1 unit, and unit 0 is in `a`..`z`.
   - No unit is in `A`..`Z`.
   - Some unit is U+002D.
   - No unit is U+0009, U+000A, U+000C, U+000D, U+0020, U+0000, U+002F, or U+003E. This is "valid element local name" step 2 (`dom.bs` 203-228), which applies because unit 0 is an ASCII alpha.
   - It is none of `annotation-xml`, `color-profile`, `font-face`, `font-face-src`, `font-face-uri`, `font-face-format`, `font-face-name`, and `missing-glyph`.

   Every condition tests ASCII units, so a check by code units gives the same result as the standard's check by code points. A lone surrogate is allowed.
5. Step 3 finds no definition, under D5, and throws nothing.
6. Step 4 applies when the element already has a shadow root, *current*:
   - If *current*'s declarative field is false, or its mode differs from `options.mode`, the call returns `error.NotSupported`.
   - Otherwise, the store removes every child of *current* in tree order, sets declarative to false, and returns *current*.
   - The step 4 path keeps every other field, ignores every other option, and allocates nothing.
7. A non-null `options.custom_element_registry` returns `error.UnsupportedCustomElementRegistry` (D4).
8. Steps 5 to 15: the store reserves the node slot and creates the shadow root in the element's node document. It sets these fields:
   - The host, `mode`, `delegates_focus`, `serializable`, `slot_assignment`, and `clonable`, from the arguments.
   - `available_to_element_internals = false` (D5) and `declarative = false`.
   - `custom_element_registry = null` and `keep_custom_element_registry_null = false`.

   Then it sets the element's shadow root.

Every error leaves the store unchanged, including `OutOfMemory` and `HandleSpaceExhausted` from step 5.
The element's shadow root changes only after the node insertion succeeds.

### Mutation

- "Ensure pre-insert validity" step 2 uses host-including inclusive ancestors (`dom.bs` 6680-6691). In this task, only a shadow root has a non-null host. The check follows "root's host", so a template-contents host from `FP-0103` needs no change to the check.
- The check is iterative:
  1. It returns true when *A* is *B*.
  2. It returns false when *A* has no child and no shadow root.
  3. Otherwise, it sets a cursor to *B* and repeats these steps:
     - If the cursor is *A*, return true.
     - If the cursor has a parent, move to the parent.
     - Otherwise, if the cursor is a shadow root, move to its host.
     - Otherwise, return false.

  The walk-only reference function runs step 3 alone, and the shortcut must agree with it.
- Each step that tests for a `DocumentFragment` node treats a shadow root as one. These are "ensure pre-insert validity" steps 1, 4, 8, and 9, and "insert" steps 1, 4, and 7. Inserting a shadow root therefore moves its children and leaves the shadow root attached and empty.
- "Adopt" step 3 visits shadow-including inclusive descendants in shadow-including tree order (`dom.bs` 6806-6812). The traversal is iterative. Its next-node step works like this:
  - From an element with a shadow root, go to the shadow root.
  - Otherwise, go to the first child.
  - Otherwise, climb, and stop at the traversal root. At each node, go to its next sibling if it has one.
  - At a parentless shadow root, return to its host. Go to the host's first child if it has one. Otherwise, continue climbing from the host.

  Step 3.2 applies D4. No attribute node, adopting step, or callback exists.
- `adopt` keeps the FP-0009 order:
  1. The node lookup.
  2. `NotADocument` for a target that is not a document.
  3. `NotSupported` for a document node (`adoptNode()` step 1).
  4. `HierarchyRequest` for a shadow root (`adoptNode()` step 2).
- "Remove" and "pre-remove" keep their FP-0009 steps. A shadow root has no parent, so it is never a removable child.
- Insertion and removal still allocate nothing.

### Roots, sweep, iteration, and teardown

- `forEachRoot` follows D8.
- For each root, `sweep` marks every node of the root's shadow-including tree:
  - It climbs parents, and hosts at shadow roots, to the shadow-including root.
  - It then visits shadow-including descendants with the iterative next-node step above.
  - The rule "a marked root means a marked tree" holds at the shadow-including root.
  - A freed set is always a whole shadow-including tree, so no live node links to a freed node.
- `ChildIterator` works unchanged on a shadow root. The step 4 path of attach ends an iteration over the cleared shadow root, because the recorded next sibling no longer has that parent.
- `deinit` frees every node, including every shadow root.
- No traversal recurses, so native stack use does not grow with tree depth.

### Invariant checker

`expectInvariants` keeps every FP-0009 and FP-0100 check and adds these checks:

- A shadow root has no parent and no siblings.
- A shadow root's host is a live element in the HTML namespace whose shadow root is that shadow root.
- An element's shadow root is a live shadow root whose host is that element.
- The shadow-including ancestor chain of each node ends within the node count.
- `expectAllowedChild` treats a shadow-root parent as a fragment parent and rejects a shadow-root child.

It uses checked lookups only. It never calls `at`, so a mutation fails a named case instead of panicking.
It does not require a shadow root to share its host's node document (D7).

### Records of unsupported behavior

The `src/dom.zig` module comment and the README list each item below with its owner.

| Behavior | Current engine behavior | Owner |
| --- | --- | --- |
| `:host`, `:host()`, `:host-context()` | `unsupported_selector` (`selectors.zig:292-294`) | `FP-0072` criterion 5 |
| `::slotted()` | `unsupported_selector` | `FP-0072` criterion 6 keeps it unsupported. Its matching belongs to the FP-0026 frontier decomposition. |
| `::part()` | `unsupported_selector` | FP-0026 frontier decomposition |
| Tree-scoped stylesheets and encapsulation contexts | `resolve` applies the given sheets to the document tree only | `FP-0072` criterion 1 |
| Computed style of a shadow-tree element, with the host as the flat-tree parent of the shadow root's children | `StyleMap.get` returns `NotStyled` | `FP-0072` |
| Slots, slot assignment, "assign slottables", "signal a slot change", the flat tree, and inheritance of slotted nodes through their slot | No slot exists. Insert steps 7.4 to 7.6 and remove steps 8 to 10 have no effect | FP-0026 frontier decomposition |
| Laboratory tree and style stages | `Stage` declares them, and `implemented` returns false for them (`lab.zig:40-48`) | `FP-0068` |
| Dump lines for shadow roots | `tree_dump.writeChildren` writes no shadow-root line | `FP-0103` criteria 5 and 7 |
| Declarative shadow roots and template contents hosts | No parser support | `FP-0103` |
| `attachShadow()`, the `shadowRoot` getter, closed-mode hiding, retargeting, "get the parent", and composed event paths | No binding | FP-0026 frontier decomposition |
| Custom element definitions, registries, states, the `is` value, `disable shadow`, and element internals | The definition and the registry are null | FP-0026 frontier decomposition |
| Cloning with `clonable`, `getHTML()` with `serializable`, focus delegation, "move", mutation observers, live ranges, and node iterators | No API | FP-0026 frontier decomposition |

### Interface for later tasks

- `FP-0103`:
  - It calls `shadowRoot` for its "is a shadow host" test.
  - It calls `attachShadowRoot` with a null registry and handles `NotSupported` as the parser's caught exception.
  - Then it calls `setShadowRootAvailableToElementInternals` and `setShadowRootDeclarative`.
  - It calls `setShadowRootKeepCustomElementRegistryNull` only when the start tag has a `shadowrootcustomelementregistry` attribute.
- `FP-0072` derives tree contexts from parent links, the host in `shadowRootFields`, and `shadowRoot`. It owns any public shadow-including-order query that it needs.

## Exact test cases

Cases 1 to 13 live in `src/dom.zig`, and case 14 lives in `src/css/tests.zig`. All cases run through `zig build test`.
Each case is named `FP-0127 case N: ...`.
These abbreviations apply:

- `H` is the HTML namespace, `http://www.w3.org/1999/xhtml`.
- `SVG` is `http://www.w3.org/2000/svg`.
- `MathML` is `http://www.w3.org/1998/Math/MathML`.

Unless a case says otherwise, every fixture node is created in a document `D` from `createDocument`.
Doctypes come from the FP-0100 `newDoctype` helper, which passes empty identifiers.
Cases 1 to 12 call `expectInvariants` after each mutation through the existing checked helpers.
Each rejection uses `expectRejected`, which compares the error and the store `fingerprint`.
Options are written as (mode, delegates_focus, serializable, slot_assignment, clonable).

1. Fields.
   - Setup:
     - `D`.
     - `Hd` = element(H, `div`), appended to `D`.
     - Text `light`, appended to `Hd`.
     - `C` = element(H, `x-foo`), detached.

     The node count is 4.
   - `S = attachShadowRoot(Hd, (open, true, false, named, true))`. The node count becomes 5.
   - `nodeKind(S)` is `.shadow_root`, and `shadowRoot(Hd)` is `S`.
   - The parent, first child, last child, previous sibling, and next sibling of `S` are null.
   - `nodeDocument(S)` is `D`. `characterData(S)` and `elementName(S)` are null.
   - `Hd`'s children are [`light`], and its parent is `D`.
   - `shadowRootFields(S)` is {host `Hd`, open, delegates_focus true, available false, declarative false, serializable false, named, clonable true, registry null, keep false}.
   - `SC = attachShadowRoot(C, (closed, false, true, manual, false))` gives {host `C`, closed, false, false, false, true, manual, false, null, false}. The node count becomes 6.
   - Call `setShadowRootAvailableToElementInternals(SC, true)`, then `setShadowRootKeepCustomElementRegistryNull(SC, true)`, then `setShadowRootDeclarative(SC, true)`. After each call, exactly that field has changed.
   - `shadowRoot` of a new element(H, `span`) is null.
   - With `Dh = createHtmlDocument()` and `Hh` = element(H, `div`) in `Dh`, attach succeeds. `nodeDocument` of the result is `Dh`, and `isHtmlDocument(Dh)` is true.
2. Accepted host names. Each name below, on a detached element(H, name), returns a shadow root whose fields match the options (open, false, false, named, false):
   - The 18 listed names.
   - `x-foo`, `a-`, `x-a=b`, and `a-b:c`.
   - `math-` followed by U+03B1.
   - `emotion-` followed by the units `D83D DE0D`.
   - `a-` followed by the lone unit `D800`.

   After the 25 elements exist, the 25 attach calls grow the node count by exactly 25.
3. Attach rejections. Each row changes nothing.

   | Element | Call | Expected | Basis |
   | --- | --- | --- | --- |
   | no namespace, `div` | (open, ...) | `NotSupported` | step 1 |
   | SVG `div` | (open, ...) | `NotSupported` | step 1 |
   | MathML `x-foo` | (open, ...) | `NotSupported` | step 1 |
   | namespace `http://www.w3.org/1999/xhtml/` (trailing slash), `div` | (open, ...) | `NotSupported` | step 1, exact match |
   | H, empty name | (open, ...) | `NotSupported` | step 2 |
   | H `img`, `template`, `slot`, `DIV`, `xfoo`, `-x`, `1-x`, `X-foo`, `x-Foo` | (open, ...) | `NotSupported` | step 2 |
   | H `x-a b`, `x-a` U+0009 `b`, `x-a` U+0000 `b`, `x-a/b`, `x-a>b` | (open, ...) | `NotSupported` | step 2, valid element local name |
   | H `annotation-xml`, `color-profile`, `font-face`, `font-face-src`, `font-face-uri`, `font-face-format`, `font-face-name`, `missing-glyph` | (open, ...) | `NotSupported` | step 2, reserved names |
   | H `div` with a non-declarative open shadow root | (open, ...) | `NotSupported` | step 4.2 |
   | H `div` with a declarative open shadow root that has one child | (closed, ...) | `NotSupported`. Declarative stays true, and the child stays. | step 4.2 |
   | SVG `div`, registry `@enumFromInt(1)` | (open, ...) | `NotSupported` | step 1 precedes D4 |
   | H `div`, registry `@enumFromInt(1)` | (open, ...) | `UnsupportedCustomElementRegistry` | D4 |
   | text, comment, document, document fragment, doctype, shadow root | (open, ...) | `NotAnElement` | store argument check |
4. Declarative re-attach.
   - Setup:
     - `Hd` = element(H, `div`), appended to `D`.
     - `S = attachShadowRoot(Hd, (open, true, true, named, true))`.
     - Append `p`, text `t`, and `span` to `S`, where `span` has the text child `inner`.
     - Call `setShadowRootDeclarative(S, true)`.
   - `attachShadowRoot(Hd, (open, false, false, manual, false))` returns `S`, and the node count does not change.
   - `S` has no children. `p`, `t`, and `span` are detached, and `span` keeps `inner`. Each of them keeps node document `D`.
   - The fields are {`Hd`, open, true, false, declarative false, true, named, true, null, false}.
   - Call `setShadowRootDeclarative(S, true)`, then `attachShadowRoot(Hd, (open, ...), registry @enumFromInt(1))`. The attach returns `S`, because the step 4 path ignores the registry.
   - A final attach with (open, ...) on the now non-declarative root returns `NotSupported` and changes nothing.
5. Invalid mutations that involve a shadow root.
   - Fixture:
     - `D` → `html` → `body` → `Hd`(`div`) → `L`(`p`).
     - `S` = attach(`Hd`). `S` → `E`(`section`) → `F`(`span`).
     - `S2` = attach(`E`), and `S2` → `G`(`p`).
     - `K`(`div`), detached and childless. `SK` = attach(`K`), and `SK` → `M`(`p`).
     - `K2`(`div`), with `SK2` = attach(`K2`) holding `N1`(`a`) and `N2`(`b`).
     - Also detached: `X`(`em`), doctype `T` in `D`, text `Tx`, and an empty document `D2`.

   | # | Operation | Expected | Basis |
   | --- | --- | --- | --- |
   | 1 | `appendChild(S, Hd)` | `HierarchyRequest` | validity 2: `S`'s root has host `Hd` |
   | 2 | `appendChild(E, Hd)` | `HierarchyRequest` | validity 2 |
   | 3 | `appendChild(F, body)` | `HierarchyRequest` | validity 2 |
   | 4 | `appendChild(G, Hd)` | `HierarchyRequest` | validity 2, two hosts |
   | 5 | `appendChild(G, E)` | `HierarchyRequest` | validity 2 |
   | 6 | `appendChild(G, S)` | `HierarchyRequest` | validity 2 |
   | 7 | `appendChild(G, S2)` | `HierarchyRequest` | validity 2 |
   | 8 | `appendChild(S, S)` | `HierarchyRequest` | validity 2 |
   | 9 | `appendChild(M, K)` | `HierarchyRequest` | validity 2, childless host |
   | 10 | `appendChild(G, D)` | `HierarchyRequest` | validity 2 |
   | 11 | `appendChild(S, D2)` | `HierarchyRequest` | validity 4 |
   | 12 | `appendChild(S, T)` | `HierarchyRequest` | validity 5.1 |
   | 13 | `appendChild(Tx, S)` | `HierarchyRequest` | validity 1 |
   | 14 | `appendChild(D2, SK2)` | `HierarchyRequest` | validity 8.1 |
   | 15 | `insertBefore(Hd, X, S)` | `NotFound` | validity 3 |
   | 16 | `insertBefore(S, X, L)` | `NotFound` | validity 3 |
   | 17 | `replaceChild(S, Hd, E)` | `HierarchyRequest` | replace 1, validity 2 |
   | 18 | `replaceChild(S2, Hd, G)` | `HierarchyRequest` | replace 1, validity 2 |
   | 19 | `replaceChild(S, T, E)` | `HierarchyRequest` | validity 5.1 |
   | 20 | `replaceChild(Hd, X, S)` | `NotFound` | validity 3 |
   | 21 | `removeChild(Hd, S)` | `NotFound` | pre-remove 1 |
   | 22 | `removeChild(S, L)` | `NotFound` | pre-remove 1 |
   | 23 | `adopt(S, D2)` | `HierarchyRequest` | `adoptNode()` 2 |
   | 24 | `adopt(S2, D)` | `HierarchyRequest` | `adoptNode()` 2 |
   | 25 | `appendChild(D, SK)` | `HierarchyRequest` | validity 9.1: `SK` has one element child, and `D` has the element child `html` |
   | 26 | `adopt(S, Tx)` | `NotADocument` | the FP-0009 argument check precedes `adoptNode()` 2 |
6. Valid mutations.
   - Fixture: `D` → `html` → `body` → `Hd`(`div`) → `L1`(`p`). `S` = attach(`Hd`) holds `A`(`b`) and `B`(`i`). `D2` → `P`(`div`) → `C`(`p`).
   - The rows run in order.

   | Row | Operation | Expected |
   | --- | --- | --- |
   | 6a | `appendChild(S, X)`, with `X`(`em`) | `S` holds [`A`, `B`, `X`]. `X` has node document `D`. |
   | 6b | `appendChild(S, L1)` | `Hd` has no children. `S` holds [`A`, `B`, `X`, `L1`]. |
   | 6c | `removeChild(S, X)` | `S` holds [`A`, `B`, `L1`]. `X` is detached. |
   | 6d | `replaceChild(S, X, B)` | `S` holds [`A`, `X`, `L1`]. `B` is detached. |
   | 6e | `appendChild(Hd, S)` | `Hd` holds [`A`, `X`, `L1`], and `S` is empty. `shadowRoot(Hd)` is still `S`, and `S` has no parent. |
   | 6f | `appendChild(S, A)`, then `appendChild(S, X)` | `S` holds [`A`, `X`]. `Hd` holds [`L1`]. |
   | 6g | `insertBefore(P, S, C)` | `P` holds [`A`, `X`, `C`]. `A` and `X` have node document `D2`. `S` keeps `D`, because insert step 7.1 adopts only the children. |
   | 6h (D7) | `appendChild(S, Y)` with `Y`(`u`), then `replaceChild(P, S, C)` | `P` holds [`A`, `X`, `Y`], and `C` is detached. `Y` and `S` have node document `D2`. `Hd` keeps `D`. |
   | 6i | Fixture: `Hd3`(`section`) in `body`, with light child `L3`. `S3` = attach(`Hd3`), and `S3` → `E3`(`div`). `S4` = attach(`E3`), and `S4` → `G4`(`p`). Then `adopt(Hd3, D2)`. | `Hd3` is detached. `Hd3`, `L3`, `S3`, `E3`, `S4`, and `G4` have node document `D2`. `html` and `body` keep `D`. |
   | 6j | Fixture: `Hd5`(`span`) in `body`. `S5` = attach(`Hd5`), and `S5` → `Z5`(`p`). Then `appendChild(P, Hd5)`. | `Hd5`, `S5`, and `Z5` have node document `D2`. `shadowRoot(Hd5)` is `S5`. |
   | 6k | `adopt(E3, D)` | `S3` is empty. `E3`, `S4`, and `G4` have node document `D`. `Hd3`, `L3`, and `S3` keep `D2`. |
   | 6l | Fixture: `K`(`div`), detached. `SK` = attach(`K`), and `SK` → `M`(`p`). Then `appendChild(K, SK)`. | `K` holds [`M`], and `SK` is empty. |
7. The host-including relation.
   - Fixture of 15 nodes:
     - `D` → `html` → `body` → `Hd`(`div`) → `L`(`p`).
     - `S` = attach(`Hd`) → `E`(`section`) → `F`(`span`).
     - `S2` = attach(`E`) → `G`(`p`).
     - `K`(`div`), detached and childless. `SK` = attach(`K`) → `M`(`p`).
     - Fragment `Fr` → `N`(`b`).
   - For all 225 ordered pairs, the shortcut function equals the walk-only reference.
   - Exactly 57 pairs are related. Per node, in the order `D`, `html`, `body`, `Hd`, `L`, `S`, `E`, `F`, `S2`, `G`, `K`, `SK`, `M`, `Fr`, `N`, the host-including inclusive ancestors number 1, 2, 3, 4, 5, 5, 6, 7, 7, 8, 1, 2, 3, 1, and 2.
   - Explicit rows (ancestor, node):
     - True: (`K`, `M`), (`K`, `SK`), (`Hd`, `G`), (`D`, `G`), and (`Fr`, `N`).
     - False: (`G`, `Hd`), (`L`, `E`), (`S`, `L`), (`S2`, `F`), (`SK`, `K`), and (`N`, `Fr`).
   - The FP-0098 test keeps its name, fixture, and count of 29 under D9.
8. Roots, retention, and sweep. The calls run in order.
   - Fixture:
     - `D` → `html` → `Hd`(`div`). `S` = attach(`Hd`) → `E`(`p`) → text `T`.
     - Detached: `X`(`div`), with `SX` → `Y`(`span`).
     - Detached: `Z`(`x-z`), with `SZ` → `W`(`p`).
     - Detached: `Q`(`div`), with light child `R`(`p`) and `SQ` → `V`(`p`).

     The total is 16 nodes.
   - Call `retain(W)` and `retain(SQ)`. `forEachRoot` visits exactly {`D`, `W`, `SQ`}, each once.
   - `sweep` returns 3 and frees `X`, `SX`, and `Y`, which then return `StaleHandle`. The node count becomes 13.
   - Call `release(W)`. `forEachRoot` visits exactly {`D`, `SQ`}. `sweep` returns 3 (`Z`, `SZ`, `W`), and the node count becomes 10.
   - Call `release(SQ)`. `sweep` returns 4 (`Q`, `R`, `SQ`, `V`), and the node count becomes 6.
   - Until this point, `Hd`, `S`, `E`, and `T` stay live, and `shadowRoot(Hd)` is `S`.
   - Call `removeChild(html, Hd)`. `sweep` returns 4 (`Hd`, `S`, `E`, `T`), and the node count becomes 2.
9. Iteration.
   - (a) Repeat FP-0009 case 9 with shadow root `S` of `Hd`(`div`) as the parent and `Hd` as `elsewhere`. `S` holds the `li` children `o0` to `o5`. While iterating:
     - At `o1`, remove it.
     - At `o2`, insert `inserted` before `o3`.
     - At `o3`, append it to `Hd`.
     - At `o5`, append `appended` to `S`.

     The iteration visits exactly `o0` to `o5`. `S` holds [`o0`, `o2`, `inserted`, `o4`, `o5`, `appended`], and `Hd` holds [`o3`].
   - (b) A declarative open shadow root `S'` of `Hd'`(`div`) holds `d0` to `d3`. While iterating over `S'`, at `d1`, call `attachShadowRoot(Hd', (open, ...))`. The iteration visits exactly [`d0`, `d1`]. `S'` is empty, and `d0` to `d3` are detached.
   - (c) `Hd''`(`div`) has children `l0`, `l1`, and `l2`. At `l0`, attach a shadow root to `Hd''`. The iteration visits all three, and the children are unchanged.
10. Teardown. A store with a counting `FailingAllocator` holds these nodes:
    - A connected host with a nested shadow tree.
    - A detached, unretained host with a shadow tree.
    - A retained shadow root.
    - A re-attached declarative shadow root whose former children are detached.
    - A fragment.

    `deinit` gives `allocated_bytes == freed_bytes` and `allocations == deallocations`.
11. Allocation.
    - (a) Deterministic.
      - Use a `FailingAllocator` with `resize_fail_index = 0`.
      - Create `D` and seven detached element(H, `div`) nodes. These 8 live nodes fill the first table capacity exactly (`handles.zig:155-156`: 0 + 0/2 + 8).
      - Set `fail_index = alloc_index`. `attachShadowRoot(div1, (open, ...))` returns `OutOfMemory`, and `has_induced_failure` is true.
      - The fingerprint is unchanged, `shadowRoot(div1)` is null, and the node count is 8.
      - With `fail_index = maxInt(usize)`, the same call succeeds, and the node count is 9.
    - (b) `std.testing.checkAllAllocationFailures` over this scenario. Each allocating call is `guarded`, so each induced failure returns `OutOfMemory`, changes nothing, and leaks nothing.
      - Create `D`, then `D2`.
      - `Hd` = element(H, `div`), appended to `D`. `S` = attach(`Hd`, (open, false, false, named, false)).
      - `A` = element(H, `section`), appended to `S`. `S2` = attach(`A`, (closed, true, true, manual, true)).
      - Text `x`, appended to `S2`. Call `setShadowRootDeclarative(S2, true)`. `attachShadowRoot(A, (closed, ...))` returns `S2`.
      - `K` = element(H, `x-k`). `SK` = attach(`K`). Call `retain(SK)`.
      - Call `adopt(Hd, D2)`, then `appendChild(D2, Hd)`.
      - `sweep` returns 1 (the text). Call `release(SK)`. `sweep` returns 2.
    - A probe run without failures records at least 9 allocations:
      - 2 table growths, at the 1st insertion and at the 9th insertion, which is `SK`'s attach (8 to 20 slots).
      - 6 copies of namespaces and names for the three elements (`web_string.zig:148-151`).
      - 1 copy of the text (`dom.zig:253-256`).

      The 9th insertion is an attach, so the checker necessarily induces a failure inside `attachShadowRoot`.
12. Handles and kinds.
    - A handle from another store returns `WrongOwner` from `attachShadowRoot`, `shadowRoot`, `shadowRootFields`, and the three setters. A swept handle returns `StaleHandle` from each. Nothing changes.
    - `shadowRoot` of a text node returns `NotAnElement`.
    - `shadowRootFields` and each setter return `NotAShadowRoot` for an element, a fragment, and a document.
    - For a shadow root `S`, these calls give these results:
      - `attributes(S)` returns `NotAnElement`.
      - `appendData(S, "x")` returns `NotCharacterData`.
      - `isHtmlDocument(S)` returns `NotADocument`.
      - `documentTypeIds(S)` and `processingInstructionTarget(S)` return null.
13. Constant stack.
    - The case spawns a thread with a 256 KiB stack in the Debug test build and joins it. The thread stores any error, and the case returns that error after the join. The allocator is an arena over the page allocator.
    - On that thread, with n = 32768:
      - Create `D` and `H1`(H `div`). Append `H1` to `D`, and attach `S1`.
      - For k = 2 to n, append a new element(H, `div`) `Hk` to `S(k-1)`, and attach `Sk`.
      - Append `E`(`p`) to `Sn`.
    - The expected results:
      - `appendChild(E, H1)` returns `HierarchyRequest`.
      - With a new `D2`, `adopt(H1, D2)` gives `E` and `Sn` the node document `D2`.
      - `sweep` returns 2n + 1 = 65537, and the node count is 2.
    - Depth derivation:
      - The chain nests n = 32768 shadow trees.
      - Any recursive host-including walk, shadow-including traversal, or marking makes at least one nested call per shadow tree, so at least 32768 nested calls.
      - Each x86-64 call pushes an 8-byte return address. The Debug build also saves an 8-byte frame pointer. [INFERENCE] Zig keeps frame pointers in Debug builds.
      - With frame pointers, the calls need at least 16 × 32768 = 524288 bytes, which is 512 KiB.
      - Without frame pointers, they need at least 8 × 32768 = 262144 bytes, before the thread's own frames.
      - Either way, they need more than the 262144-byte (256 KiB) stack.
    - The case does not call `expectInvariants`, whose per-node ancestor walk is quadratic on a chain. The case's work is linear in n.
    - This is a robustness property, and no mutation control targets it. The reviewers also read the source for recursion.
14. Recorded unsupported behavior, in `src/css/tests.zig`.
    - Each of `:host`, `:host(div)`, `:host-context(div)`, `::slotted(span)`, and `::part(label)` fails with `unsupported_selector` through the case 22 helper `expectSelectorFailure` (`tests.zig:483`).
    - Fixture: document element `Hd`(H `div`) with light child `L`(H `p`). `S` = attach(`Hd`) → `P`(H `span`) → text `t`.
    - `style.resolve` with no stylesheets returns a map in which `get(Hd)` and `get(L)` succeed, `get(P)` returns `NotStyled`, and `textStyle(t)` returns `NotStyled`.

### Base failures

Every case except the case 14 selector rows calls a name that the base lacks, such as `attachShadowRoot` or `Kind.shadow_root`.
At the base, `Kind` (`src/dom.zig:62-70`) has no `shadow_root` member, and the file declares no `attachShadowRoot`.
So `tests-before.log` must fail to compile, with errors that name a missing FP-0127 declaration.
Shadow roots cannot be built at the base, so no runtime before-failure is possible. FP-0100 sets the same precedent.
The case 14 selector rows already hold at the base (`selectors.zig:292-294`). They are pins, not before-failures.
The base has these behavioral gaps:

- `src/dom.zig:733`: step 2 does not follow hosts.
- `:900`: the leaf shortcut.
- `:813`: the fragment test.
- `:874-878`: adopt walks tree order only.
- `:201`: `AdoptError` has no `HierarchyRequest`.
- `:943`: `markTree` climbs parents only.

### Mutation controls

Record each control as a `.diff`.
Apply it with `git apply`, run the tests, and reverse it with `git apply -R`.
Record file hashes before, during, and after each control.
Record a crash separately from a failed assertion.

| Control | Mutation | Case that fails, and why |
| --- | --- | --- |
| M1 | The host-including walk stops at the root and never continues from a host | Case 5 row 1 succeeds. Case 7 counts 31 related pairs, not 57. Case 13 `appendChild(E, H1)` succeeds. |
| M2 | The leaf shortcut returns false for any childless node, ignoring shadow roots | Case 7 pair (`K`, `M`): the shortcut gives false, and the walk gives true. Case 5 row 9 succeeds. |
| M3 | "Adopt" walks tree order only | Case 6 rows 6i and 6j: `S3` and `S5` keep `D`. |
| M4 | `markTree` marks only the tree that contains the root | Case 8: the first sweep frees `S`, `E`, and `T`, so the checker finds `Hd`'s stale shadow root. |
| M5 | The step 4 path leaves declarative true | Case 4: declarative is true, and the final attach succeeds. |
| M6 | The step 4 path keeps the children | Cases 4 and 9b. |
| M7 | The reserved-name exclusion is removed | The case 3 reserved-name rows succeed. |
| M8 | The namespace check is removed | Case 3 rows 1 to 4 succeed. |
| M9 | `insert` treats a shadow root as a non-fragment | Case 6 row 6e: `S` becomes a child of `Hd`, so `expectAllowedChild` fails. |
| M10 | `adopt` omits `adoptNode()` step 2 | Case 5 rows 23 and 24 succeed. |
| M11 | `forEachRoot` skips shadow roots | Case 8: the visit set lacks `SQ`. |
| M12 | Step 5 node creation moves before steps 1 to 4 and stays on error | Case 3: the fingerprint changes. |
| M13 | `OutOfMemory` from step 5 is returned as `NotSupported` | Case 11a expects `OutOfMemory`. |

Under M1 and M2, the failing row returns before any traversal, and `deinit` walks only the table, so no control hangs.

### Criterion mapping

| FP-0127 criterion | Cases and controls |
| --- | --- |
| 1. Attach with every field and its exact errors | 1 to 4, 12; M5 to M8, M12 |
| 2. Host-including checks, and every invalid shadow-root mutation rejected with its standard error and no change | 5 to 7, 13; M1 to M3, M9, M10 |
| 3. Liveness through the host, `forEachRoot`, `sweep`, teardown, retention, and iteration | 8 to 10; M4, M11 |
| 4. `checkAllAllocationFailures` over creation and attachment | 11; M13 |
| 5. Every FP-0009 and FP-0014 outcome kept, and unsupported behavior recorded with owners | Every base test name passes after the change, with assertions unchanged except under D9. Also case 14, the `dom.zig` comment, and the README. |

### Stop rules

- If any expectation here contradicts the pinned DOM or HTML text, stop and report the text. Never edit an expectation silently.
- If the pinned DOM text of an FP-0009 or FP-0100 algorithm differs from a step comment in `src/dom.zig` at the base, stop and report it.
- If an FP-0009, FP-0014, FP-0098, FP-0100, or FP-0011 assertion would need a change other than D9, stop.
- If an FP-0100 expected tree dump would change, stop.
- If case 13 overflows its 256 KiB stack, stop and report the recursive function. Never enlarge the stack.
- If the FP-0127 cases add more than 1 s to the `src/root.zig` profile total, stop and report each case's duration.
- If the task would change the behavior of `selectors.zig`, `style.zig`, `tree_dump.zig`, or `lab.zig`, or would change any row of `css.zig`, stop.
- If the worker's base does not contain `f17b396`, or if `src/dom.zig` at the worker's base differs from the frozen base, stop and report the difference.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0127/raw/`.
Use `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global` and `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe`.
Never overwrite a log, and name a failed attempt `-attempt-N`.

0. Keep `raw/standards-text.log`, which the integrator commits with the freeze, unchanged. Do not re-run it. The freeze commits two logs:
   - `raw/standards-text-attempt-1.log` is the first attempt, kept as a failed attempt. It records:
     - The `sha256sum` of the HTML copy.
     - `awk` over HTML lines 78624-78678 and 146326-146431.
     - The `curl.exe` retrieval of `dom.bs` into `out/whatwg-dom-bs-3071e5f269448350fdea79bb284eedaf17bc431e`.
     - The `sha256sum` of that file, which prints `1550b0f067278aac80c53d603495d1050ab04856d0ce8b9ad10eb23f98b9a847`.
     - `awk` over 15 `dom.bs` ranges that the r2 re-check found misplaced.

     Its HTML range omits line 146325, and its `dom.bs` ranges miss most of the cited text.
   - `raw/standards-text.log` is the authority. It records:
     - The `sha256sum` of the HTML copy, which prints `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
     - `awk` over HTML lines 78624-78678 and 146325-146431.
     - The `sha256sum` of the `dom.bs` copy, which prints `1550b0f067278aac80c53d603495d1050ab04856d0ce8b9ad10eb23f98b9a847`.
     - `awk` over the `dom.bs` ranges 197-228, 2346-2481, 2695-2832, 2880-3048, 3175-3249, 3252-3376, 6167-6319, 6631-6834, 6966-7020, 7172-7237, and 7854-8039. Every `dom.bs` range cited in "Sources" lies inside one of them.

   The README names both logs and lists every cited line that differs from this contract.
1. Write cases 1 to 14 first. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0127-before`. It must fail with compile errors that name a missing FP-0127 declaration.
2. In a worktree at the base, record `profile-before.log` with the `tools/README.md:375` profile command and `--cache-dir out/fp0127-profile-base`.
3. Delete `out/fp0127-after`. Record `tests-after.log` with `cmd /d /c ver` and `zig build test --summary all --cache-dir out/fp0127-after`. It must exit with status 0 and show the test count.
4. Record `profile-after.log`. Then record `names.log`, which shows that no base test name is missing and that the added names are exactly the FP-0127 cases. Store the comparison script under `raw/`.
5. Record `fmt.log` with `zig fmt --check build.zig src tests`.
6. Record `controller-tests-after.log` with `node --version` and `node tools/fairpane.mjs test`.
7. Record `mutation.log` and `mutation-M1.diff` to `mutation-M13.diff`.
8. Write `README.md`. It includes `HEAD`, the criterion mapping, each control result, the time delta, the D9 amendment, the D7 editorial-gap note, the unsupported table, and every resolved ambiguity.

The integrator then does the following:

1. Record `raw/integration-binding.log` with `HEAD`, `git diff --cached`, and file hashes.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0127/gates`.
3. Record an uncached `integration-tests.log`.

## Authority

Writable paths: `src`, `tests`, `build.zig`, and `engineering/evidence/FP-0127/`.
These protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
Only the integrator updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Required reviewers: `fairpane-review` and `fairpane-spec`.

## Non-goals

- Slots, slot assignment, the flat tree, custom elements, element internals, and registries beyond the null field.
- Bindings, events, retargeting, closed-mode hiding, cloning, serialization, focus delegation, and "move".
- The HTML parser, declarative shadow roots, template contents, and shadow-root dump lines.
- Selector, cascade, style, dump, or laboratory behavior changes, and any `css.zig` row change.
- Running or classifying WPT tests.
- C ABI changes and performance claims.

## Pre-freeze findings and resolutions

### Check 1 (`out/drafts/FP-0127-check.json`)

1. Blocker, base and FP-0100.
   - The Base sentence now requires `f17b396` and a re-read of every citation at the freeze base.
   - Every `src/dom.zig` line is rebased on `9fedf55`.
   - The FP-0100 amendments are stated: `newDoctype`, `newProcessingInstruction`, `allocationScenario`, the case 12 list, and the public `expectInvariants`.
   - The `tree_dump.zig` Files row and the other exhaustive-switch rows are added.
   - The stop rules are replaced with the base-containment rule, the same-`dom.zig` rule, and the FP-0100 dump rule.
   - The records table now says that `tree_dump.writeChildren` writes no shadow-root line.
   - Cases 1 and 12 gain HTML-document and FP-0100 accessor rows.
2. Major, D11 stack.
   - Under integrator decision 2, D11 and case 13 use a 256 KiB thread. They have no stack measurement, no painted stack, no margin, and no helper move.
   - n = 32768, and the depth derivation is stated.
   - The parser helper rows, the measurement stop rule, and the README measurements are removed.
3. Major, owners.
   - `:host`, `:host()`, and `:host-context()` go to FP-0072 criterion 5.
   - `::slotted()` stays unsupported under FP-0072 criterion 6, and its matching goes to FP-0026.
   - The computed-style row names the host as the flat-tree parent of the shadow root's children.
   - The slots row covers the flat tree and slotted inheritance, with owner FP-0026.
   - Under integrator decision 3, no `css.zig` row changes.
4. Major, HTML pin. D1 and Sources cite `efc54f7b` (S85) and the local copy, at lines 78624-78678 and 146325-146431, with steps 7.11.4 to 7.11.7 located.
5. Major, recorded standard text.
   - Evidence step 0 names `raw/standards-text.log` and the failed `raw/standards-text-attempt-1.log`.
   - `raw/standards-text.log` records both texts, and the integrator commits it with the freeze.
6. Minor, DOM line numbers. D5 cites `dom.bs` 7222-7237, and "valid element local name" is cited at 203-228. Every DOM citation is a `dom.bs` line at `3071e5f`, as `raw/standards-text.log` prints it.
7. Minor, `web_string.zig`. The citations are lines 61-63 and 148-151.
8. Minor, D9. The seven call sites are named: 1549 (walk), and 1550 and 1557-1561 (shortcut).
9. Minor, D6. Step 7.11.7 is conditional on `shadowrootcustomelementregistry`, and "Interface for later tasks" follows that condition.
10. Minor, dangling references.
    - D7 states the confirmed ruling with `dom.bs` 3222, 6224-6226, and 6296-6297.
    - "(proposed; open question 4)" is deleted.
    - D11 is replaced.
11. Minor, laboratory wording. The text reads: `Stage` declares `tree` and `style`, and `implemented` returns true only for `fetch`, `decode`, and `tokenize` (`lab.zig:40-48`).
12. Minor, coverage. Case 5 gains row 25, `appendChild(D, SK)` with validity 9.1, and row 26, `adopt(S, Tx)` with `NotADocument`.
13. Minor, case 2 count. The text reads "After the 25 elements exist, the 25 attach calls grow the node count by exactly 25".
14. Note, FP-0019 owner. Under integrator decision 3, the bindings, retargeting, and composed paths go to the FP-0026 frontier note (`engineering/state.json:391`).
15. Note, base failures. No change. The compile-failure precedent and the case 14 pins are stated.
16. Note, row naming. Row 6m is renamed 6l.

### Check 2 (`out/drafts/FP-0127-check-r2.json`)

1. Blocker, DOM line numbers.
   - Every DOM citation is replaced with the line that `raw/standards-text.log` prints: D5, D7, attach item 3, attach item 4, the two Mutation bullets, and every Sources range.
   - Sources adds the `dom.bs` SHA-256 `1550b0f067278aac80c53d603495d1050ab04856d0ce8b9ad10eb23f98b9a847` and the local copy path.
   - The attach section cites 7958-8039, and Sources separates `attachShadow()` (7932-7956) from "attach a shadow root".
   - Evidence step 0 keeps `raw/standards-text.log` unchanged as the authority, and it lists `raw/standards-text-attempt-1.log` as the failed attempt.
   - Check 1 resolutions 6 and 10 now cite the corrected lines.
   - The drafter checked each cited anchor against the numbered lines of the log: 203-228, 2371, 2446, 2466-2481, 2725-2832, 2910-3048, 2957, 3205-3249, 3222, 3282-3376, 6213-6287, 6224-6226, 6289-6302, 6296-6297, 6307-6319, 6680-6691, 6733-6763, 6806-6812, 6834, 7017-7020, 7222-7237, 7905-7927, 7932-7956, and 7958-8039.
2. Minor, HTML range. The `template` start tag range is 146325-146431 in Sources, in step 0, and in check 1 resolution 4. Line 146325 is the `<dt>` line.
3. Minor, module comment lines. The citations read `src/dom.zig:32-33`, and the Files row reads "(lines 7 and 32-33)".
4. Minor, FP-0072 criteria. The citation reads `engineering/plan.json:3245-3246`.
5. Minor, stale text.
   - Check 1 resolution 5's second bullet reads: "`raw/standards-text.log` records both texts, and the integrator commits it with the freeze."
   - Step 0 begins: "Keep `raw/standards-text.log`, which the integrator commits with the freeze, unchanged."
6. Note, `css.zig` row 30. No change to FP-0127. The FP-0072 contract narrows the owner of row 30.
7. Drafter corrections found while re-reading at `4266be8`:
   - `following` spans `src/dom.zig:881-891`, not 881-892.
   - D7's base reference is narrowed from the whole `replaceChild` function to its step 6 lines, `src/dom.zig:607-608`.
   - Every other cited repository line was re-read at `4266be8` and is unchanged: `src/dom.zig`, `tree_dump.zig`, `plan.json`, `state.json`, `css.zig`, `selectors.zig`, `style.zig`, `lab.zig`, `handles.zig`, `web_string.zig`, `heap.zig`, `tests.zig`, and `glyf_test.zig`.

### Third check and freeze

Agent Check0127 checked revision 3 (`out/drafts/FP-0127-CONTRACT-r3.md`) and returned fix-first with one minor finding: three `engineering/state.json` citations went stale when plan commit `9f1096d` added a line to the FP-0026 notes.
The integrator applied its replacements at the freeze: lines 885 and 971 replace 884 and 970, and the base sentence also names `engineering/plan.json` and `engineering/state.json` among the files whose cited lines the integrator re-reads.
Check0127 found every DOM and HTML citation correct against `raw/standards-text.log` and every other citation unchanged at `9f1096d`, and asked for no further check.
The integrator re-read the cited `engineering/state.json` lines 166-167, 391, 885, and 971 and `engineering/plan.json` lines 3230-3251, 3245-3246, and 3686-3709 at the freeze base, and no source file changed after `9f1096d`.
