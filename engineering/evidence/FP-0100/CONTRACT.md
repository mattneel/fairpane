# FP-0100 task contract

## Identity

Task ID: `FP-0100`, "Construct HTML document trees outside tables, templates, framesets, and foreign content".
Workstream: `html-dom`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0008`, `FP-0009`, and `FP-0064`, accepted.
This task is the first slice of `FP-0010`, "Implement initial HTML tree construction", which stays open as the closing task.
This contract extends `engineering/evidence/FP-0008/CONTRACT.md`, `engineering/evidence/FP-0064/CONTRACT.md` with its amendments, and `engineering/evidence/FP-0009/CONTRACT.md`.
Those contracts stay in force wherever this contract does not change them.
A `fairpane-spec` worker drafted this contract read-only, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Required gates: `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`.
Required reviewers: `fairpane-review` and `fairpane-spec`.

### Plan criteria

FP-0100 carries these four FP-0010 criteria word for word:

- "Implement frozen tree-construction modes with standard recovery."
- "Exercise malformed nesting and chunk boundaries through the actual DOM."
- "Preserve parser continuation and future script-reentrancy boundaries."
- "Emit inspectable DOM dumps from real parsing."

`FP-0101` carries the fifth FP-0010 criterion, the WPT `.dat` run.
`FP-0010` closes all five.
FP-0100 adds the other criteria of its plan entry, and the criterion mapping below covers each one.

### Integrator decisions

- The standard text is frozen at the FP-0008 pin: whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, file `source`, SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`, with a local copy at `C:\src\fairpane\out\whatwg-html-source-efc54f7b70858d9fcf06d1a5871ae215f448c029`.
  Every line number in this contract is a line of that copy, unless it names another file.
- At the pin there are 21 insertion modes, listed at lines 141960 to 141977.
  "In select" does not exist, and `select` is a boundary of the "has an element in scope" list (142213 to 142239).
  Processing instruction tokens exist, and every implemented mode that can receive one handles it.
- The frozen subset is ten modes: initial, before html, before head, in head, in head noscript, after head, in body, text, after body, and after after body.
  The other eleven modes belong to `FP-0102` (the seven table modes) and `FP-0103` (in template, in frameset, after frameset, and after after frameset).
- The parser reports `unsupported` exactly where the standard would apply behavior outside the subset, as "Unsupported features" defines.
  It never skips such behavior or substitutes something else.
- FP-0064 amendment 2 asks FP-0010 to confirm that no character token can change the adjusted current node's namespace.
  The confirmation fails in general.
  At a MathML text integration point or an HTML integration point, the dispatcher sends a character token to the insertion mode (145193 to 145197).
  In body, every character token first runs "reconstruct the active formatting elements" (146790 to 146806).
  That algorithm inserts HTML elements (142331 to 142377), so the adjusted current node becomes an HTML element.
  The tokenizer also reads `adjusted_current_node_is_foreign` while characters before the `<` are still pending, when the input decides the `[CDATA[` branch (`src/html/tokenizer.zig` lines 264 to 272 and 2378 to 2437).
  The witness `<math><mi><p><b></p>x<![CDATA[y]]>` therefore gives the comment `[CDATA[y]]` after `x` when the input splits inside `[CDATA[`, and one text node `xy` when the input arrives in one chunk.
  The standard gives the comment.
  The integrator records this finding as FP-0064 amendment 3, and `FP-0104` owns the fix and the witness test.
  Within FP-0100 the confirmation holds: every element that FP-0100 creates is in the HTML namespace, so the adjusted current node is never foreign.
- At a `script` end tag in the text insertion mode, the parser returns a script boundary to its caller, as "Scripts" defines.
  `FP-0019` owns script preparation, the insertion point, the script nesting level, and the parser pause flag.
- Among the tasks that depend on FP-0100, `FP-0019` uses the script boundary and node retention, `FP-0068` adds the laboratory tree stage, `FP-0070` and `FP-0072` use HTML documents, and `FP-0126` calls the change-the-encoding hook from the `meta` branch.
- The standard gives no source position for a tree-construction parse error.
  This contract uses the source position of the token that the parser is processing, as "Parse errors" defines.
- The parser takes decoded UTF-16 code units, so the encoding confidence is irrelevant to it.
  The `meta` branch's encoding steps (146198 to 146227) apply only when the confidence is tentative, so they change nothing here.
  `FP-0126`, under `FP-0065`, owns tentative confidence, changing the encoding, and the hook that the `meta` branch calls.
- The DOM store gains HTML documents, document modes, doctype identifiers, processing-instruction targets, and text appends.
  "FP-0009 amendments" lists each changed FP-0009 call site; every FP-0009 expected outcome stays.
- Speculative parsing, custom element definitions, form-owner association, the reset algorithm of resettable elements, process internal resource links, the steps that set the parser cannot change the mode flag, and `iframe` `srcdoc` documents are non-goals.
  Their owner is the FP-0026 frontier decomposition, and FP-0100 never reports them as done.
- FP-0100 runs no `.dat` file.
  `FP-0101` owns the WPT harness and its denominator rule.
  The laboratory `tree` stage belongs to `FP-0068`.
- The parser interface is frozen in this contract, and no architecture decision record is needed.
- The pre-freeze check (agent Check0100) returned "fix-first", with 1 blocker, 2 majors, 13 minors, and 4 notes.
  It recomputed every expected value of cases 3 to 10 and 13 and reported them correct; the drafter's recount then found B12 wrong.
  This contract applies the fix text of every finding, with these decisions:
  - A tree-construction error raised for a character carries that character's own source position.
    A new tokenizer accessor supplies it, so neither a chunk boundary nor the tokenizer's grouping of characters into runs changes a position.
    Its storage, allocation, and time bounds are in "Modules", and case 15 checks it (check finding 2).
  - `owner(feature)` reports the owner task of every unsupported feature, and case 10 asserts it (check finding 3).
  - `appendData` reserves amortized capacity, and X4 bounds its allocations (check finding 14).
  - `error.HierarchyRequest` from a store operation that the standard performs without a guard is sticky like `error.OutOfMemory`, and case 13 row R2 exercises it (check finding 15).
    No step of the subset can fail with `error.NotFound`, so `Error` omits it until `FP-0102`'s foster parenting inserts before a non-null reference child.
  - The drafter recounted every position for this revision and corrected B12's end-of-file error from `1:13` to `2:2`, because the input's LF starts line 2; the check did not report it.
- The re-check (agent Check0100) returned "freeze" with four minors and two notes, and this contract applies all six.
  It confirmed B31, B32, Q13, case 15, case 10's owners, and X4's bound, and found that a copy-per-append `appendData` fails X4.

## Sources

- The pinned HTML Standard source, at the local copy named above.
  The drafter read lines 141900 to 142520, 145140 to 148260, 148880 to 149420, 149564 to 149700, and 150640 to 150800, and checked each heading and branch start cited below with an exact single-line read.
  The pre-freeze check corrected eleven citations, and the drafter re-read each corrected line with a single-line read.

| Section | Lines | Content |
| --- | --- | --- |
| 13.2.4 | 141948 | Parse state |
| 13.2.4.1 | 141950 to 142095 | The insertion mode: the 21 modes (141960 to 141977), "using the rules for" (141979 to 141988), the original insertion mode, the stack of template insertion modes (to 142001), and reset the insertion mode appropriately (142005 to 142095) |
| 13.2.4.2 | 142097 to 142289 | The stack of open elements: current node (142118 to 142119), adjusted current node (142123 to 142126), process internal resource links (142130 to 142132), the special, formatting, and ordinary categories (142134 to 142189), specific scope (142191 to 142211), in scope (142213 to 142239), list item scope (142241 to 142252), button scope (142254 to 142264), table scope (142266 to 142279), and nothing happens when stack elements move (142281 to 142284) |
| 13.2.4.3 | 142290 to 142397 | The list of active formatting elements: markers, push with the Noah's Ark clause (142306 to 142329), reconstruct (142331 to 142377), and clear to the last marker (142379 to 142395) |
| 13.2.4.4 | 142399 to 142415 | The head and form element pointers, and parsing template contents (142413 to 142415) |
| 13.2.4.5 | 142418 to 142465 | Root insertion target (142420 to 142421), fragment context element, allow declarative shadow roots, the scripting mode and its four values (142427 to 142461), and the frameset-ok flag (142463 to 142465) |
| 13.2.5 | 142468, 142510 to 142516 | Tokenization, and acknowledging the self-closing flag with the `non-void-html-element-start-tag-with-trailing-solidus` error |
| 13.2.6 | 145172 to 145259 | Tree construction: the dispatcher (145185 to 145208), the next token (145210 to 145213), MathML text integration points (145215 to 145226), and HTML integration points (145228 to 145242) |
| 13.2.6.1 | 145262 to 145793 | Insertion locations (145264 to 145270), the appropriate place for inserting a node (145272 to 145338), create an element for a token (145342 to 145462), the adjusted insertion location (145464 to 145484), insert an element at the adjusted insertion location (145488 to 145527), insert a foreign element (145533 to 145556), insert an HTML element (145558 to 145561), insert a character (145672 to 145704), insert a comment (145750 to 145769), and insert a processing instruction (145771 to 145793) |
| 13.2.6.2 | 145795 to 145816 | The generic raw text and RCDATA element parsing algorithms |
| 13.2.6.3 | 145819 to 145844 | Generate implied end tags, and generate all implied end tags thoroughly |
| 13.2.6.4.1 | 145851 to 146002 | The initial insertion mode, the parser cannot change the mode flag (145853 to 145854), the DOCTYPE branch (145881 to 145989), the quirks list (145899 to 145968), the limited-quirks list (145970 to 145980), and the case-insensitive comparison (145982 to 145985) |
| 13.2.6.4.2 | 146005 to 146071 | before html |
| 13.2.6.4.3 | 146074 to 146149 | before head |
| 13.2.6.4.4 | 146152 to 146586 | in head: script (146251 to 146309), template start (146325 to 146502), template end (146504 to 146563), and anything else (146571 to 146584) |
| 13.2.6.4.5 | 146589 to 146659 | in head noscript |
| 13.2.6.4.6 | 146662 to 146767 | after head: the head element pointer push (146717 to 146734) |
| 13.2.6.4.7 | 146770 to 147831 | in body; close a `p` element (147833 to 147847); the adoption agency algorithm (147849 to 148025) |
| 13.2.6.4.8 | 148036 to 148183 | text: character (148045 to 148051), EOF (148053 to 148065), `script` end tag (148067 to 148174), and any other end tag (148176 to 148181) |
| 13.2.6.4.9 to 13.2.6.4.15 | 148186 to 148922 | The table modes, owned by `FP-0102` |
| 13.2.6.4.16 | 148923 to 149056 | in template, owned by `FP-0103` |
| 13.2.6.4.17 | 149057 to 149114 | after body |
| 13.2.6.4.18 and 13.2.6.4.19 | 149117 to 149263 | in frameset and after frameset, owned by `FP-0103` |
| 13.2.6.4.20 | 149266 to 149306 | after after body |
| 13.2.6.4.21 | 149309 to 149354 | after after frameset, owned by `FP-0103` |
| 13.2.6.5 | 149358 to 149573 | foreign content, owned by `FP-0104` |
| 13.2.7 | 149578 to 149595 | The end: stop parsing, and its step 4, which pops all nodes (149595) |
| 13.4 | 150711 onward | Parsing HTML fragments, owned by `FP-0105` |

  The source file carries no section numbers.
  The numbers above follow the heading order at the pin, with "in select" absent; numbers after 13.2.6.4.8 are [INFERENCE] from that order.

- In-body entry lines, which the branch table and the cases cite: NULL 146778; whitespace 146790; other character 146799; html 146823; base group and template end 146835; body 146843; frameset 146858; EOF 146885; end body 146908; end html 146934; address group 146967; h1 to h6 146983; pre and listing 146999; form 147018; li 147038; dd and dt 147088; plaintext 147157; button 147176; end address group 147204; end form 147230; end p 147270; end li 147281; end dd and dt 147301; end h1 to h6 147325; end sarcasm 147349; a 147360; b group 147387; nobr 147396; end formatting group 147409; applet group 147416; end applet group 147428; table 147452; end br 147469; area group 147478; input 147493; param group 147529; hr 147538; image 147565; textarea 147572; xmp 147597; iframe 147610; noembed and noscript 147617; select 147624; option 147658; optgroup 147683; rb and rtc 147705; rp and rt 147715; math 147725; svg 147748; caption group 147771; any other start tag 147787; any other end tag 147798 to 147829.
- Tokenizer switch points that this task calls, as FP-0064 recorded: 145806 to 145807, 146231, 146238, 146301, 147165, 147585, 147607, 147614, and 147621.
- `src/html/tokenizer.zig`: `text_flush_threshold` (line 82), `run` (lines 264 to 272), and `markupDeclarationOpen` (lines 2378 to 2437, which reads the flag at line 2416).
- WPT at `b60c4b349d9d167bf354a40bc0d4cbed15174606`: `html/syntax/parsing/resources/README.md`, blob `0f4be3b4f460437e1a1eab95fc98b9807fd177ae`, and `html/syntax/parsing/resources/test.js`, blob `d993273e77eed7e249fab1dfd68baf15ec401001`, function `serializeTree`.
  The README defines the tree dump format, and "Tree dump" states where this dump differs from `serializeTree`.
  The drafter read them through GitHub at the pinned commit; evidence item 3 records them from the verified snapshot.
- DOM Standard, the FP-0009 baseline of 5 October 2026: document type and mode (<https://dom.spec.whatwg.org/#concept-document-type>, <https://dom.spec.whatwg.org/#concept-document-mode>), doctype name, public ID, and system ID (<https://dom.spec.whatwg.org/#concept-doctype-name>), processing instruction target (<https://dom.spec.whatwg.org/#concept-pi-target>), and replace data (<https://dom.spec.whatwg.org/#concept-cd-replace>).
- Infra Standard, namespaces: <https://infra.spec.whatwg.org/#namespaces>.
- Repository: `src/dom.zig`, `src/html/`, `src/lab.zig`, `src/css/css.zig`, `src/css/selectors.zig`, `docs/RENDERING_AND_TEXT.md`, and the FP-0008, FP-0009, and FP-0064 contracts.
- The pre-freeze check: `out/drafts/FP-0100-check.json`, by agent Check0100.

## Behavior

### Modules

- `src/html/modes.zig` defines `Mode`, an enum of the 21 insertion modes in the order of lines 141960 to 141977, with snake_case tags such as `in_head_noscript` and `after_after_body`.
  It defines `section(mode)` (1 to 21, for 13.2.6.4.N), `title(mode)` (the quoted mode name, such as `"in head noscript"`), `implemented(mode)`, `owner(mode)`, `branches(mode)`, `branch_count`, and `branchIndex`, in the pattern that `src/html/states.zig` used for FP-0008.
  `implemented` is true exactly for the ten modes of the subset.
  `owner` returns `"FP-0102"` for in table, in table text, in caption, in column group, in table body, in row, and in cell.
  It returns `"FP-0103"` for in template, in frameset, after frameset, and after after frameset, and `null` otherwise.
  `branches(mode)` is empty for an unimplemented mode.
- `src/html/tree.zig` defines the parser and `owner(feature)`.
- `src/html/tree_dump.zig` defines the tree dump.
- `src/html/tokenizer.zig` gains a read-only accessor that gives the source position of each code unit of the `characters` step that `next` last returned.
  It changes no FP-0008 or FP-0064 expected step.
  The accessor is `pub fn characterPosition(t: *const Tokenizer, index: usize) Position`, and `index` must be less than the length of that step.
  It gives each code unit the position of the character that the unit belongs to, as "Parse errors" defines.
  The tokenizer keeps one record per `appendText` call of the runs that it has queued but not yet returned, plus the step that `next` last returned.
  One action queues at most two characters runs, so at most 2 × (`text_flush_threshold` + 1) records exist (src/html/tokenizer.zig line 82).
  The tokenizer reserves that storage at most once per tokenizer, on the first characters step.
  Recording positions allocates nothing after that reservation, and the accessor allocates nothing and runs in at most logarithmic time in the step length.
  Every FP-0008 and FP-0064 test passes unchanged.
- `src/html/root.zig` exports `Parser`, `ParserOptions` (the `Options` struct), `ParserError` (the parser's `Error` set), `ScriptingMode`, `Outcome`, `Unsupported`, `TreeParseError`, `ScriptState`, `modes`, and `tree_dump`.
  It also exports `owner(feature)` from `src/html/tree.zig` as `unsupportedOwner`.
  Its `test` block imports `tree_test.zig` and `tree_partition_test.zig`.
  Its header no longer says that tree construction does not exist.
  It says that nothing in the engine's document load calls the parser yet.

### DOM store extensions

`src/dom.zig` gains these operations.
Each validates its handles like the existing accessors, copies its strings before it changes the store, and leaves the store unchanged on `error.OutOfMemory`.

- `pub const DocumentMode = enum { no_quirks, quirks, limited_quirks };`.
- `createHtmlDocument(store)` creates a document whose type is "html" and whose mode is no-quirks.
  `createDocument(store)` keeps creating an XML document in no-quirks mode.
- `isHtmlDocument(store, document)`, `documentMode(store, document)`, and `setDocumentMode(store, document, mode)` return `error.NotADocument` for another node.
- `createDocumentType(store, document, name, public_id, system_id)` stores three exact strings, and `documentTypeIds(store, node)` returns them, or null for another node.
- `createProcessingInstruction(store, document, target, data)` stores the target, and `processingInstructionTarget(store, node)` returns it, or null for another node.
- `appendData(store, node, data)` appends code units to the data of a text, comment, or processing-instruction node, as replace data with the offset at the length and a count of 0 does.
  It returns `error.NotCharacterData` for another node.
  `appendData` reserves amortized capacity before it changes the node, so n appends of total length L allocate O(log L) times.
  A failed reservation leaves the store unchanged.
  The doc comment of `characterData` states that the view stays valid until the node is freed or `appendData` changes its data.
- The module header states that the store holds XML and HTML documents and that a document's mode is no-quirks until `setDocumentMode` changes it.
- The existing test-only invariant checker becomes `pub fn expectInvariants(store: *Store) !void`, compiled only in test builds, so that tree tests can call it.
- The obligations row of `src/css/css.zig` for HTML documents, and the header of `src/css/selectors.zig`, state that the store can hold HTML documents in any mode.
  They also state that selector matching treats every document with XML rules and no quirks until `FP-0070`.
  No CSS behavior changes.

### Parser interface

```zig
pub const ScriptingMode = enum { normal, disabled };
pub const Options = struct { scripting: ScriptingMode };

pub const Unsupported = union(enum) {
    /// The token must be processed by the rules of a mode that `modes.implemented` reports false for.
    mode: modes.Mode,
    /// The in head rules reached a `template` start tag (146325), which FP-0103 owns.
    template_start_tag,
    /// The in body rules reached a `math` or `svg` start tag (147725, 147748), which FP-0104 owns.
    foreign_start_tag,
};

/// The owner task of an unsupported feature.
pub fn owner(feature: Unsupported) []const u8;

pub const Outcome = union(enum) {
    need_input,
    script: struct { element: dom.NodeHandle, offset: html.CodeUnitIndex },
    done,
    unsupported: struct { feature: Unsupported, offset: html.CodeUnitIndex },
};

/// `code` is null for a tree-construction error that the standard names no code for.
pub const TreeParseError = struct { code: ?html.ErrorCode, position: html.Position };

pub const ScriptState = struct { parser_document: ?dom.NodeHandle, force_async: bool, already_started: bool };

pub const Error = error{ OutOfMemory, HandleSpaceExhausted, HierarchyRequest, ChunkPending, InputFinished };

pub const Parser = struct {
    pub fn init(gpa: Allocator, store: *dom.Store, options: Options) Error!Parser;
    pub fn deinit(p: *Parser) void;
    pub fn document(p: *const Parser) dom.NodeHandle;
    pub fn feed(p: *Parser, chunk: []const u16) Error!void;
    pub fn finish(p: *Parser) Error!void;
    pub fn run(p: *Parser) Error!Outcome;
    pub fn errors(p: *const Parser) []const TreeParseError;
    pub fn scriptState(p: *const Parser, element: dom.NodeHandle) ?ScriptState;
};
```

- `owner(feature)` returns `modes.owner(mode).?` for `.mode`, `"FP-0103"` for `.template_start_tag`, and `"FP-0104"` for `.foreign_start_tag`.
- `init` creates an HTML document in no-quirks mode with `createHtmlDocument`, a tokenizer, and an empty stack, list, and error list.
  The insertion mode is initial (141960), and the frameset-ok flag is "ok" (142463).
- `feed` and `finish` pass their chunk to the tokenizer under the FP-0008 rules.
  A chunk stays borrowed until `run` returns `need_input`, or until `deinit`.
- `run` processes tokens until one of four outcomes:
  - `need_input`: the tokenizer returned `need_input`.
  - `script`: a `script` end tag was processed in the text mode.
  - `done`: the parser stopped parsing.
  - `unsupported`: the next step needs behavior outside the subset.
- After `done` or `unsupported`, `run` returns the same outcome again and reads no input.
- `error.OutOfMemory` and `error.HandleSpaceExhausted` are sticky: every later call except `deinit` returns the same error.
  `error.ChunkPending` and `error.InputFinished` come from the tokenizer and change nothing.
- If a store operation that the standard performs without a guard fails with `error.HierarchyRequest` because the caller changed the tree, `run` returns that error, and it is sticky like `error.OutOfMemory`.
- `errors` returns every parse error in step order: tokenizer errors with their codes and positions, and tree-construction errors.
- `deinit` releases every node that the parser retains and frees the parser's memory.
  It does not free the document.

### Token processing

- The parser passes each token to the tree construction dispatcher (145185 to 145208).
  Within the subset the adjusted current node is always null or an HTML element, so the dispatcher always selects the current insertion mode.
- A `characters` step holds a run of characters.
  The parser's result must equal processing each code point as its own character token, because each token is handled when it is emitted (142499 to 142503).
  When a branch reprocesses a character in another mode, the rest of the run continues in the mode that the branch leaves.
  Whitespace means U+0009, U+000A, U+000C, U+000D, and U+0020, as each mode's whitespace branch lists them.
- "Using the rules for" a mode applies that mode's rules and leaves the insertion mode unchanged unless those rules change it (141979 to 141988).
- After a start tag token, the parser calls `Tokenizer.switchTo` exactly where the standard switches the tokenizer.
  `title` and `textarea` use `.rcdata`.
  `style`, `noframes`, `xmp`, `iframe`, `noembed`, and `noscript` when the scripting mode is not Disabled use `.rawtext`.
  `script` uses `.script_data`, and `plaintext` uses `.plaintext`.
  The parser never calls `switchTo` at another time, so `error.SwitchNotAllowed` cannot occur.
- The parser sets `Tokenizer.adjusted_current_node_is_foreign` before each call of `Tokenizer.next`.
  It computes the value from the adjusted current node (142123 to 142126) after it has processed every earlier token, including every character token.
  Within the subset the value is always false.
  Setting the flag to false before each `next` is equivalent to FP-0064 amendment 3's statement that FP-0100 never sets it.
- For `pre`, `listing` (146999 to 147015), and `textarea` (147572 to 147595), the parser ignores the next token when it is a U+000A character token.
  A parse error step is not a token, so it does not end the wait.
  Neither does `need_input`.
  Only the first code unit of the next `characters` step is dropped, and only when it is U+000A.
- A start tag with the self-closing flag set raises `non-void-html-element-start-tag-with-trailing-solidus` unless a branch that processes it acknowledges the flag (142510 to 142516).
  A branch that reprocesses the token in another mode does not end its processing.
  The error follows every other tree-construction error that the same token raises.
- Stop parsing pops all nodes off the stack (149595), and `run` returns `done`.
  Steps 1 to 3 and 5 onward of the end (149581 onward) belong to `FP-0019` and the document lifecycle, and this parser does not run them.

### Insertion modes and branches

The parser implements every branch of the ten modes, at the lines that the Sources table gives.
The branch names are exactly these, in source order, 130 in total.
The address group is the 25 names at lines 146967 to 146969, and the address end group is the 28 names at lines 147204 to 147207.
The b group is `b`, `big`, `code`, `em`, `font`, `i`, `s`, `small`, `strike`, `strong`, `tt`, and `u` (147387 to 147388), and the formatting end group is the 14 names at lines 147409 to 147411.

| Mode | Count | Branches |
| --- | --- | --- |
| initial | 5 | whitespace; comment; processing instruction; DOCTYPE; else |
| before html | 8 | DOCTYPE; comment; processing instruction; whitespace; start html; end head, body, html, or br; other end tag; else |
| before head | 9 | whitespace; comment; processing instruction; DOCTYPE; start html; start head; end head, body, html, or br; other end tag; else |
| in head | 17 | whitespace; comment; processing instruction; DOCTYPE; start html; start base, basefont, bgsound, or link; start meta; start title; start noscript when scripting is not Disabled, noframes, or style; start noscript when scripting is Disabled; start script; end head; end body, html, or br; start template; end template; start head or other end tag; else |
| in head noscript | 7 | DOCTYPE; start html; end noscript; whitespace, comment, processing instruction, or start basefont, bgsound, link, meta, noframes, or style; end br; start head or noscript, or other end tag; else |
| after head | 12 | whitespace; comment; processing instruction; DOCTYPE; start html; start body; start frameset; start base, basefont, bgsound, link, meta, noframes, script, style, template, or title; end template; end body, html, or br; start head or other end tag; else |
| in body | 55 | NULL; whitespace; other character; comment; processing instruction; DOCTYPE; start html; start base, basefont, bgsound, link, meta, noframes, script, style, template, or title, or end template; start body; start frameset; EOF; end body; end html; start address group; start h1 to h6; start pre or listing; start form; start li; start dd or dt; start plaintext; start button; end address group; end form; end p; end li; end dd or dt; end h1 to h6; end sarcasm; start a; start b group; start nobr; end formatting group; start applet, marquee, or object; end applet, marquee, or object; start table; end br; start area, br, embed, img, keygen, or wbr; start input; start param, source, or track; start hr; start image; start textarea; start xmp; start iframe; start noembed, or noscript when scripting is not Disabled; start select; start option; start optgroup; start rb or rtc; start rp or rt; start math; start svg; start caption, col, colgroup, frame, head, tbody, td, tfoot, th, thead, or tr; other start tag; other end tag |
| text | 4 | character; EOF; end script; other end tag |
| after body | 8 | whitespace; comment; processing instruction; DOCTYPE; start html; end html; EOF; else |
| after after body | 5 | comment; processing instruction; DOCTYPE, whitespace, or start html; EOF; else |

A branch that says to act as another entry also executes that entry, so both of their counters increase.
These consequences of the pinned text are frozen, because older parsers differ:

- `select` is a boundary of the in scope algorithm (142213 to 142239).
  So a formatting element above a `select` is not in scope.
- A `select` start tag with a `select` in scope is a parse error, and the parser pops until a `select` is popped (147624 to 147656).
  `option`, `optgroup`, `hr`, and `input` have the select-aware steps at lines 147658 to 147703, 147538 to 147563, and 147493 to 147527.
- `search` is in the address group, and `select` is in the address end group.
- In the adoption agency algorithm, the parser computes `(target, refNode)` as the adjusted insertion location given `(commonAncestor, null)`.
  It removes `lastNode` from its parent if it has one, and inserts it only when the four conditions at lines 147984 to 147994 hold, in the step at lines 147981 to 148005.
- In the initial mode, the parser cannot change the mode flag (145853 to 145854) is false for every document the parser creates, and no document is an `iframe` `srcdoc` document.
  The FP-0026 frontier decomposition owns the steps that would set them.
  A DOCTYPE is appended only when the document has neither a doctype child nor an element child (145887 to 145893).

### Stack, scopes, formatting list, and the adoption agency algorithm

- The categories, the five scope algorithms, the formatting list, the Noah's Ark clause, reconstruct, clear to the last marker, and close a `p` element follow lines 142134 to 142397 and 147833 to 147847 exactly.
- The Noah's Ark clause compares the attributes with which each element was created, by name, namespace, and value, in any order (142314 to 142322).
- Each formatting list entry keeps the attributes of the token that created its element.
  Reconstruct and the adoption agency algorithm create new elements from those attributes.
- The adoption agency algorithm follows lines 147849 to 148025 exactly, including both loop counters and the bookmark.

### Unsupported features

- When the dispatcher would process a token by the rules of a mode that `modes.implemented` reports false for, `run` returns `unsupported` with `.{ .mode = mode }`.
  The offset is the start of that token's span; for the end-of-file token it is the input length.
  Within the subset only in table (from 147452) and in frameset (from 146709 and 146858) are reachable.
- When the in head rules reach the `template` start tag branch, `run` returns `unsupported` with `.template_start_tag` before any step of that branch runs.
- When the in body rules reach the `math` or `svg` start tag branch, `run` returns `unsupported` with `.foreign_start_tag` before any step of that branch runs.
- In each case the document keeps the tree built so far, and `errors` keeps every error raised so far.
  For `.template_start_tag` and `.foreign_start_tag`, the counter of the reached branch increases; a `.mode` outcome increases no counter.
- The in head `template` end tag branch is implemented.
  No `template` element is ever on the stack, so it is always the parse error that ignores the token (146504 onward).

### Scripts

- A `script` start tag follows lines 146251 to 146309.
  The parser records a `ScriptState` for the element.
  `parser_document` is the document, because the scripting mode is never Fragment.
  `force_async` is false, and `already_started` is false.
- The end-of-file token in the text mode sets `already_started` to true when the current node is a `script` element (148053 to 148065).
- A `script` end tag in the text mode pops the current node and switches to the original insertion mode (148067 to 148090).
  Then `run` returns `.script` with that element.
  `offset` is the end of the end tag's span, and the tokenizer has consumed exactly `offset` code units.
  This happens in both scripting modes.
- The next call of `run` continues with the next input character.
  The parser does not prepare or execute the script, and it does not keep an insertion point, a script nesting level, or a parser pause flag; `FP-0019` owns them.
- `scriptState` returns null for an element that no `script` start tag created.

### Node retention

- The parser retains, through `dom.Store.retain`, every node that its stack of open elements, its list of active formatting elements, its head and form element pointers, or its script states reference.
  It releases a node when the last such reference goes away.
- A caller may change the tree between calls of `run`.
  Nothing happens to the stack in that case (142281 to 142284), and a `sweep` frees no retained node.

### Parse errors

- A tokenizer parse error keeps its code and position.
- A tree-construction parse error has a null code, except `non-void-html-element-start-tag-with-trailing-solidus`.
  Its position is the start of the token being processed.
  For a character token, that is the position at which the tokenizer began consuming the input for that character: the character itself, the CR of a CR LF pair, or the `&` of a character reference.
  A matched character reference's code units all have the position of its `&`.
  A code unit that the tokenizer re-emits as an unconsumed source character, such as a flushed `&#` or the `<`, `/`, and name of `</tit1e`, has the position of the source character that it stands for, as the FP-0064 ambiguity decision assigns.
  For the end-of-file token, it is the input length.
  A chunk boundary never changes a position.
- `html.errors.raisedByTokenizer` stays unchanged, and the tree builder raises `non-void-html-element-start-tag-with-trailing-solidus`.

### Tree dump

`tree_dump.writeChildren(store, root, writer)` writes one line for each descendant of `root` in tree order, in the `#document` format of the pinned WPT README; unlike `serializeTree`, it does not normalize the tree first, and it rejects null-namespace elements.

- Each line is `| ` followed by two spaces for each ancestor between the node and `root`, then the node text, then LF.
- An element is `<` + the tag name string + `>`.
  The tag name string is the local name for the HTML namespace, `svg ` plus the local name for the SVG namespace, and `math ` plus the local name for the MathML namespace.
- An element's attributes follow it, one level deeper, as `name="value"`, sorted by the attribute name string in UTF-16 code unit order.
  The attribute name string is the local name for no namespace, and `xlink `, `xml `, or `xmlns ` plus the local name for the XLink, XML, or XMLNS namespace.
- Text is `"` + data + `"`, and a comment is `<!-- ` + data + ` -->`.
- A doctype is `<!DOCTYPE ` + name + `>`.
  When the public or system identifier is not empty, it is `<!DOCTYPE ` + name + ` "` + public + `" "` + system + `">`.
- A processing instruction is `<?` + target + ` ` + data + `?>`.
- Nothing is escaped, so a newline in data starts a new line without the `| ` prefix.
- An element in no namespace or another namespace, or an attribute in a namespace other than XLink, XML, or XMLNS, makes the function return `error.UndumpableNamespace`.
- Adjacent text nodes are written separately and never merged.

### Laboratory and engine

No laboratory stage changes, and FP-0007 case 4 keeps its `tree` unsupported result.
`FP-0068` owns the laboratory tree stage.
No engine document load calls the parser yet.
The C ABI, `api`, `include`, `specs`, thresholds, gates, and corpus pins do not change.

## FP-0009 amendments

- The FP-0009 test helpers `newDoctype` and `newProcessingInstruction`, `allocationScenario`, and the rejected-call list at `src/dom.zig` lines 2131 to 2136 pass the new `name`, `public_id`, `system_id`, and `target` arguments.
  They pass empty strings for the identifiers and `"instruction"`, or `"x"`, as both target and data, so every FP-0009 expected outcome stays.
  The README names the FP-0009 test that holds the rejected-call list.
- No other FP-0009 case changes.

## Exact test cases

Zig cases are named `FP-0100 case N: ...` and run through `zig build test`.
DOM cases live in `src/dom.zig`.
Tree cases live in `src/html/tree_test.zig`, and partition cases in `src/html/tree_partition_test.zig`, which reuses `partition_test.firstMismatch`.
Case 15 lives in `src/html/tokenizer_test.zig` and extends the FP-0064 helpers.
After every tree case, `dom.expectInvariants` must pass.

### Expected-value notation

- An input is a Zig string literal in backticks: `\n` is U+000A, `\r` is U+000D, and `\x00` is U+0000.
- Mode `off` is Disabled and `on` is Normal, and the default is `off`.
- The default outcome sequence is `done` with no script boundary.
  `script@N` is a `.script` outcome with offset N, `unsupported(mode X)@N`, `unsupported(template)@N`, and `unsupported(foreign)@N` are the unsupported outcomes.
- Errors are listed in order: `!code@L:C` is an error with a code, and `!tree@L:C` is a tree-construction error with a null code.
  `none` means no error.
  The offset of each error is C − 1 for an input without line breaks, and the test asserts it.
  For a multi-line input, the case states the offset.
- Unless a case says otherwise, the document mode is quirks when the input has no DOCTYPE token, and no-quirks when the first DOCTYPE token is `<!DOCTYPE html>` and the initial insertion mode processes it.
- A dump block is the exact output of `tree_dump.writeChildren` for the document; for an unsupported outcome, it is the dump when `run` returned.

### Records

1. `modes.Mode` has 21 tags in the order of lines 141960 to 141977.
   `section` returns 1 to 21 in order, `title` returns the 21 mode names, and `implemented` is true exactly for the ten modes of the subset.
   `owner` follows "Modules", `branches` equals the branch table, and `branch_count` is 130.

### DOM store extensions

2. Each step calls `expectInvariants` after each change.
   - X1: `createHtmlDocument` gives `isHtmlDocument` true and `documentMode` `.no_quirks`, and `createDocument` gives `isHtmlDocument` false.
     `setDocumentMode` with `.quirks` and then `.limited_quirks` round-trips, and each of `isHtmlDocument`, `documentMode`, and `setDocumentMode` returns `error.NotADocument` for an element.
   - X2: `createDocumentType(doc, "html", "", "x")` gives exactly those three views from `documentTypeIds`, which returns null for an element.
   - X3: `createProcessingInstruction(doc, "t", "d")` gives target `"t"` and `characterData` `"d"`.
   - X4: `appendData` of `"bc"` to text `"a"` gives `"abc"`, and on an element it returns `error.NotCharacterData`.
     `appendData` of "y" to comment "x" and to processing instruction ("t", "x") gives "xy" and keeps target "t".
     Appending 1,000 one-unit strings performs at most 32 allocations.
     Under `std.testing.checkAllAllocationFailures`, each induced failure in `appendData`, `createDocumentType`, and `createProcessingInstruction` returns `error.OutOfMemory` and leaves the store's fingerprint unchanged.

### Tree dump

3. Y1: the test builds a tree with the store API only.
   The tree is an HTML document with a doctype (`"html"`, `"p"`, `""`) and an HTML `html` element.
   The `html` element has attributes `b="2"` and then `a="1"`.
   Its children are an SVG `svg` element, a MathML `mi` element, text `"a\nb"`, comment `" c "`, and processing instruction target `"t"` with data `""`.
   The `svg` element has attributes `(XLink, "href", "x")`, `(none, "viewBox", "0")`, `(XML, "lang", "en")`, and `(XMLNS, "xmlns", "y")`.
   The dump is:

```text
| <!DOCTYPE html "p" "">
| <html>
|   a="1"
|   b="2"
|   <svg svg>
|     viewBox="0"
|     xlink href="x"
|     xml lang="en"
|     xmlns xmlns="y"
|   <math mi>
|   "a
b"
|   <!--  c  -->
|   <?t ?>
```

   Y2: an element in no namespace, and an attribute in namespace `urn:x`, each make `writeChildren` return `error.UndumpableNamespace`.
   An empty document writes nothing.

### Doctypes and document modes

4. Each input below is followed only by EOF.
   Each dump is the given doctype line, when there is one, followed by these lines:

```text
| <html>
|   <head>
|   <body>
```

| Case | Input | Doctype line | Mode | Errors |
| --- | --- | --- | --- | --- |
| D1 | `<!DOCTYPE html>` | `\| <!DOCTYPE html>` | no-quirks | none |
| D2 | `<!DOCTYPE html SYSTEM "about:legacy-compat">` | `\| <!DOCTYPE html "" "about:legacy-compat">` | no-quirks | none |
| D3 | `<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">` | `\| <!DOCTYPE html "-//W3C//DTD HTML 4.01 Transitional//EN" "">` | quirks | `!tree@1:1` |
| D4 | `<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">` | `\| <!DOCTYPE html "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">` | limited-quirks | `!tree@1:1` |
| D5 | `<!DOCTYPE html PUBLIC "-//w3c//dtd xhtml 1.0 transitional//en" "x">` | `\| <!DOCTYPE html "-//w3c//dtd xhtml 1.0 transitional//en" "x">` | limited-quirks | `!tree@1:1` |
| D6 | `<!DOCTYPE svg>` | `\| <!DOCTYPE svg>` | quirks | `!tree@1:1` |
| D7 | `<!DOCTYPE>` | `\| <!DOCTYPE >` | quirks | `!missing-doctype-name@1:10 !tree@1:1` |
| D8 | `<!DOCTYPE html PUBLIC "HTML">` | `\| <!DOCTYPE html "HTML" "">` | quirks | `!tree@1:1` |
| D9 | `<!DOCTYPE html SYSTEM "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd">` | `\| <!DOCTYPE html "" "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd">` | quirks | `!tree@1:1` |
| D10 | `<html><!DOCTYPE html>` | none | quirks | `!tree@1:1 !tree@1:7` |
| D11 | `<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "">` | `\| <!DOCTYPE html "-//W3C//DTD HTML 4.01 Frameset//EN" "">` | quirks | `!tree@1:1` |

### Whole documents

5. T1: `<!DOCTYPE html><html><head><title>T</title></head><body><p>x</p></body></html>`.
   Errors: none.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|     <title>
|       "T"
|   <body>
|     <p>
|       "x"
```

   T2: `` (empty input).
   Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
```

   T3: ` <!--a--><?t d?><!DOCTYPE html> <!--b-->x`.
   Errors: none.

```text
| <!-- a -->
| <?t d?>
| <!DOCTYPE html>
| <!-- b -->
| <html>
|   <head>
|   <body>
|     "x"
```

### Mode walks

6. Each walk covers the branches of one or more modes.
   W1: ` <!--a--><?t d?><!DOCTYPE html> <!--b--><?u v?><!DOCTYPE html></x><html> <!--c--><?w?><!DOCTYPE html><html k=v></y><head>` (121 units).
   Errors: `!tree@1:48 !tree@1:63 !tree@1:87 !tree@1:102 !tree@1:112`.

```text
| <!-- a -->
| <?t d?>
| <!DOCTYPE html>
| <!-- b -->
| <?u v?>
| <html>
|   k="v"
|   <!-- c -->
|   <?w ?>
|   <head>
|   <body>
```

   W2: `<!DOCTYPE html></head></br>`.
   Errors: `!tree@1:23`.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|   <body>
|     <br>
```

   W3, mode `off`: `<!DOCTYPE html><head> <!--c--><?p?><!DOCTYPE html><html a=b><base><basefont><bgsound><link/><meta/><title>t</title><noframes>n</noframes><style>s</style><script>j</script></template><head></p></br>` (197 units).
   Outcomes: `script@171 done`.
   Errors: `!tree@1:36 !tree@1:51 !tree@1:172 !tree@1:183 !tree@1:189 !tree@1:193`.
   The script's state is `parser_document` = the document, `force_async` false, and `already_started` false.

```text
| <!DOCTYPE html>
| <html>
|   a="b"
|   <head>
|     " "
|     <!-- c -->
|     <?p ?>
|     <base>
|     <basefont>
|     <bgsound>
|     <link>
|     <meta>
|     <title>
|       "t"
|     <noframes>
|       "n"
|     <style>
|       "s"
|     <script>
|       "j"
|   <body>
|     <br>
```

   W4, mode `off`: `<!DOCTYPE html><head><noscript><!DOCTYPE html><html c=d> <!--x--><?y?><basefont><bgsound><link><meta><noframes>f</noframes><style>g</style><head><noscript></q></noscript><noscript></br>` (185 units).
   Errors: `!tree@1:32 !tree@1:47 !tree@1:140 !tree@1:146 !tree@1:156 !tree@1:181 !tree@1:181`.

```text
| <!DOCTYPE html>
| <html>
|   c="d"
|   <head>
|     <noscript>
|       " "
|       <!-- x -->
|       <?y ?>
|       <basefont>
|       <bgsound>
|       <link>
|       <meta>
|       <noframes>
|         "f"
|       <style>
|         "g"
|     <noscript>
|   <body>
|     <br>
```

   W5: `<!DOCTYPE html><head></head> <!--a--><?b?><!DOCTYPE html><html e=f><meta></template><head></p></html>` (101 units).
   Errors: `!tree@1:43 !tree@1:58 !tree@1:68 !tree@1:74 !tree@1:85 !tree@1:91`.

```text
| <!DOCTYPE html>
| <html>
|   e="f"
|   <head>
|     <meta>
|   " "
|   <!-- a -->
|   <?b ?>
|   <body>
```

   W6: `<!DOCTYPE html><body></body> <!--a--><?b?><!DOCTYPE html><html g=h></html> <!--c--><?d?><!DOCTYPE html><html i=j>x` (114 units).
   Errors: `!tree@1:43 !tree@1:58 !tree@1:89 !tree@1:104 !tree@1:114`.

```text
| <!DOCTYPE html>
| <html>
|   g="h"
|   i="j"
|   <head>
|   <body>
|     "  x"
|   <!-- a -->
|   <?b ?>
| <!-- c -->
| <?d ?>
```

   W7: `<!DOCTYPE html><body a=1><!--c--><?p?><!DOCTYPE html><body a=2 b=3>x`.
   Errors: `!tree@1:39 !tree@1:54`.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|   <body>
|     a="1"
|     b="3"
|     <!-- c -->
|     <?p ?>
|     "x"
```

   W8, mode `on`: `<dl><dd>a</dd><dt>b</dt></dd></sarcasm><param><source><track><xmp><p></xmp><iframe><b></iframe><noembed><i></noembed><noscript><u></noscript>` (141 units).
   Errors: `!tree@1:1 !tree@1:25 !tree@1:30 !tree@1:142`.

```text
| <html>
|   <head>
|   <body>
|     <dl>
|       <dd>
|         "a"
|       <dt>
|         "b"
|       <param>
|       <source>
|       <track>
|       <xmp>
|         "<p>"
|       <iframe>
|         "<b>"
|       <noembed>
|         "<i>"
|       <noscript>
|         "<u>"
```

### In body and the head modes

7. Each case gives its input, mode, errors, and dump.

- B1: `a\x00 b` (4 units).
  Errors: `!tree@1:1 !unexpected-null-character@1:2 !tree@1:2`.

```text
| <html>
|   <head>
|   <body>
|     "a b"
```

- B2: `<head></head>  x` (16 units).
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   "  "
|   <body>
|     "x"
```

- B3: `<head></head><style>x</style><body>`.
  Errors: `!tree@1:1 !tree@1:14`.

```text
| <html>
|   <head>
|     <style>
|       "x"
|   <body>
```

- B4, mode `off`: `<!DOCTYPE html><noscript><link><style>s</style><!--c--> </noscript><noscript>x` (78 units).
  Errors: `!tree@1:78`.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|     <noscript>
|       <link>
|       <style>
|         "s"
|       <!-- c -->
|       " "
|     <noscript>
|   <body>
|     "x"
```

- B5, mode `on`, same input as B4.
  Errors: `!tree@1:79`.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|     <noscript>
|       "<link><style>s</style><!--c--> "
|     <noscript>
|       "x"
|   <body>
```

- B6: `<p>a<div>b</p>c`.
  Errors: `!tree@1:1 !tree@1:11 !tree@1:16`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       "a"
|     <div>
|       "b"
|       <p>
|       "c"
```

- B7: `<h1>a<h2>b</h3>c</h1>d`.
  Errors: `!tree@1:1 !tree@1:6 !tree@1:11 !tree@1:17`.

```text
| <html>
|   <head>
|   <body>
|     <h1>
|       "a"
|     <h2>
|       "b"
|     "cd"
```

- B8: `<ul><li>a<li>b<div><li>c</ul>d</li>`.
  Errors: `!tree@1:1 !tree@1:20 !tree@1:31`.

```text
| <html>
|   <head>
|   <body>
|     <ul>
|       <li>
|         "a"
|       <li>
|         "b"
|         <div>
|       <li>
|         "c"
|     "d"
```

- B9: `<dl><dt>a<dd>b<dt>c</dl>`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <dl>
|       <dt>
|         "a"
|       <dd>
|         "b"
|       <dt>
|         "c"
```

- B10: `<pre>\nA</pre><listing>\n\nB</listing><textarea>\nC</textarea>` (58 units).
  Errors: `!tree@1:1`, at offset 0.

```text
| <html>
|   <head>
|   <body>
|     <pre>
|       "A"
|     <listing>
|       "
B"
|     <textarea>
|       "C"
```

- B11: `<pre>&#10x` (10 units).
  The LF from the character reference follows a parse error step and is still the next token.
  Errors: `!tree@1:1 !missing-semicolon-after-character-reference@1:10 !tree@1:11`.

```text
| <html>
|   <head>
|   <body>
|     <pre>
|       "x"
```

- B12: `<textarea>\nx` (12 units).
  The LF at offset 10 starts line 2, so the end-of-file token at offset 12 is at line 2, column 2.
  Errors: `!tree@1:1 !tree@2:2`, at offsets 0 and 12.

```text
| <html>
|   <head>
|   <body>
|     <textarea>
|       "x"
```

- B13: `<pre>\r\nA</pre>` (14 units).
  Errors: `!tree@1:1`, at offset 0.

```text
| <html>
|   <head>
|   <body>
|     <pre>
|       "A"
```

- B14: `<b><plaintext>a</b><p>`.
  Errors: `!tree@1:1 !tree@1:23`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <plaintext>
|         "a</b><p>"
```

- B15: `<button>a<button>b`.
  Errors: `!tree@1:1 !tree@1:10 !tree@1:19`.

```text
| <html>
|   <head>
|   <body>
|     <button>
|       "a"
|     <button>
|       "b"
```

- B16: `<form><form><div></form>x</div></form>`.
  Errors: `!tree@1:1 !tree@1:7 !tree@1:18 !tree@1:32`.

```text
| <html>
|   <head>
|   <body>
|     <form>
|       <div>
|         "x"
```

- B17: `<html a=1><body b=2><html a=3 c=4><body b=5 d=6>`.
  Errors: `!tree@1:1 !tree@1:21 !tree@1:35`.

```text
| <html>
|   a="1"
|   c="4"
|   <head>
|   <body>
|     b="2"
|     d="6"
```

- B18: `<body></body> <!--x--></html> <!--y-->z`.
  Errors: `!tree@1:1 !tree@1:39`.

```text
| <html>
|   <head>
|   <body>
|     "  z"
|   <!-- x -->
| <!-- y -->
```

- B19: `<!DOCTYPE html></body>`.
  The input ends in the after body mode.
  Errors: none.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|   <body>
```

- B20: `<select><option>a<option>b<optgroup><option>c</select><select><hr><input>`.
  Errors: `!tree@1:1 !tree@1:67`.

```text
| <html>
|   <head>
|   <body>
|     <select>
|       <option>
|         "a"
|       <option>
|         "b"
|       <optgroup>
|         <option>
|           "c"
|     <select>
|       <hr>
|     <input>
```

- B21: `<select>a<select>b`.
  Errors: `!tree@1:1 !tree@1:10`.

```text
| <html>
|   <head>
|   <body>
|     <select>
|       "a"
|     "b"
```

- B22: `<ruby>a<rb>b<rt>c<rtc>d<rp>e</ruby>`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <ruby>
|       "a"
|       <rb>
|         "b"
|       <rt>
|         "c"
|       <rtc>
|         "d"
|         <rp>
|           "e"
```

- B23: `<image src=a>`.
  Errors: `!tree@1:1 !tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <img>
|       src="a"
```

- B24: `<b><object><i>x</object>y`.
  Errors: `!tree@1:1 !tree@1:16 !tree@1:26`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <object>
|         <i>
|           "x"
|       "y"
```

- B25: `<td>x<tr>y</td>`.
  Errors: `!tree@1:1 !tree@1:1 !tree@1:6 !tree@1:11`.

```text
| <html>
|   <head>
|   <body>
|     "xy"
```

- B26: `<span><div></span>x</div>`.
  Errors: `!tree@1:1 !tree@1:12 !tree@1:26`.

```text
| <html>
|   <head>
|   <body>
|     <span>
|       <div>
|         "x"
```

- B27: `a</br x=1>b`.
  Errors: `!tree@1:1 !end-tag-with-attributes@1:10 !tree@1:2`.

```text
| <html>
|   <head>
|   <body>
|     "a"
|     <br>
|     "b"
```

- B28: `<br/><div/>x`.
  Errors: `!tree@1:1 !non-void-html-element-start-tag-with-trailing-solidus@1:6 !tree@1:13`.

```text
| <html>
|   <head>
|   <body>
|     <br>
|     <div>
|       "x"
```

- B29: `<body><title>&amp;</title><meta>`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <title>
|       "&"
|     <meta>
```

- B30: `<p><![CDATA[x]]>` (16 units).
  `adjusted_current_node_is_foreign` is false, so FP-0008 A5 applies.
  Errors: `!tree@1:1 !cdata-in-html-content@1:12`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       <!-- [CDATA[x]] -->
```

- B31: `<!DOCTYPE html></body><p>x` (26 units).
  The `p` start tag takes the after body "anything else" branch.
  Errors: `!tree@1:23`.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|   <body>
|     <p>
|       "x"
```

- B32: ` \r\nx` (4 units).
  The `x` that takes the initial "anything else" branch is inside one run with the whitespace before it, and its own position is used.
  Errors: `!tree@2:1`, at offset 3.

```text
| <html>
|   <head>
|   <body>
|     "x"
```

### Formatting elements and the adoption agency algorithm

8. Each case gives its input, errors, and dump.

- A1: `<b>1<p>2</b>3</p>` (17 units).
  Errors: `!tree@1:1 !tree@1:9`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       "1"
|     <p>
|       <b>
|         "2"
|       "3"
```

- A2: `<a>1<b>2<p>3</a>4` (17 units).
  Errors: `!tree@1:1 !tree@1:13 !tree@1:18`.

```text
| <html>
|   <head>
|   <body>
|     <a>
|       "1"
|       <b>
|         "2"
|     <b>
|       <p>
|         <a>
|           "3"
|         "4"
```

- A3: `<a><b><i><u><s><div>x</a>y`.
  The inner loop removes `b` from the list when its counter passes 3.
  Errors: `!tree@1:1 !tree@1:22 !tree@1:27`.

```text
| <html>
|   <head>
|   <body>
|     <a>
|       <b>
|         <i>
|           <u>
|             <s>
|     <i>
|       <u>
|         <s>
|           <div>
|             <a>
|               "x"
|             "y"
```

- A4: `<b><i></b>x`.
  The case has no furthest block.
  Errors: `!tree@1:1 !tree@1:7 !tree@1:12`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <i>
|     <i>
|       "x"
```

- A5: `<b><object></b>x`.
  No formatting element follows the marker.
  Errors: `!tree@1:1 !tree@1:12 !tree@1:17`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <object>
|         "x"
```

- A6: `<b><select></b>x`.
  The formatting element is not in scope, because of `select`.
  Errors: `!tree@1:1 !tree@1:12 !tree@1:17`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <select>
|         "x"
```

- A7: `<a>1<p>2<a>3` (12 units).
  Errors: `!tree@1:1 !tree@1:9 !tree@1:9 !tree@1:13`.

```text
| <html>
|   <head>
|   <body>
|     <a>
|       "1"
|     <p>
|       <a>
|         "2"
|       <a>
|         "3"
```

- A8: `<p><b></p></b>x`.
  The formatting element is not on the stack.
  Errors: `!tree@1:1 !tree@1:7 !tree@1:11`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       <b>
|     "x"
```

- A9: `<p><b><b><b><b><p>x`.
  The Noah's Ark clause leaves three entries.
  Errors: `!tree@1:1 !tree@1:16 !tree@1:20`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       <b>
|         <b>
|           <b>
|             <b>
|     <p>
|       <b>
|         <b>
|           <b>
|             "x"
```

- A10: `<p><b c=1><b c=1><b c=2><b c=1><b c=1><p>x` (42 units).
  Only equal attributes count toward the clause.
  Errors: `!tree@1:1 !tree@1:39 !tree@1:43`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="1"
|           <b>
|             c="2"
|             <b>
|               c="1"
|               <b>
|                 c="1"
|     <p>
|       <b>
|         c="1"
|         <b>
|           c="2"
|           <b>
|             c="1"
|             <b>
|               c="1"
|               "x"
```

- A11: `<nobr>a<nobr>b`.
  Errors: `!tree@1:1 !tree@1:8 !tree@1:15`.

```text
| <html>
|   <head>
|   <body>
|     <nobr>
|       "a"
|     <nobr>
|       "b"
```

- A12: `<b><b><b><b>x</b></b></b></b>y`.
  The last end tag takes step 2 of the algorithm.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <b>
|       <b>
|         <b>
|           <b>
|             "x"
|     "y"
```

### Scripts

9. S1, mode `on`: `<p>a<script>b</script>c` (23 units).
   Outcomes: `script@22 done`.
   Errors: `!tree@1:1`.
   At the boundary, before the next `run`, the dump is the following, with no `"c"`:

```text
| <html>
|   <head>
|   <body>
|     <p>
|       "a"
|       <script>
|         "b"
```

   After `done`:

```text
| <html>
|   <head>
|   <body>
|     <p>
|       "a"
|       <script>
|         "b"
|       "c"
```

   S2, mode `on`: `<script>x` (9 units).
   Errors: `!tree@1:1 !tree@1:10`.
   The script's state is `parser_document` = the document, `force_async` false, and `already_started` true.

```text
| <html>
|   <head>
|     <script>
|       "x"
|   <body>
```

   W3 covers the boundary in mode `off`.

### Unsupported features and the frameset-ok flag

10. Each unsupported outcome repeats on a second `run`.
    `owner` of its feature is `FP-0102` for U1 and U2, `FP-0103` for U3, U4, and F2, and `FP-0104` for U5 and U6.

- U1: `<p><table>`.
  In quirks mode the table does not close the `p`.
  Outcome: `unsupported(mode in_table)@10`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       <table>
```

- U2: `<!DOCTYPE html><p><table>`.
  Outcome: `unsupported(mode in_table)@25`.
  Errors: none.

```text
| <!DOCTYPE html>
| <html>
|   <head>
|   <body>
|     <p>
|     <table>
```

- U3: `<template>`.
  Outcome: `unsupported(template)@0`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
```

- U4: `<frameset><frame>`.
  Outcome: `unsupported(mode in_frameset)@10`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <frameset>
```

- U5: `<svg>` and U6: `<math>`.
  Outcome: `unsupported(foreign)@0`.
  Errors: `!tree@1:1`.

```text
| <html>
|   <head>
|   <body>
```

- F1: `<p>x</p><frameset>y`.
  The character sets frameset-ok to "not ok", so the frameset is ignored.
  Outcome: `done`.
  Errors: `!tree@1:1 !tree@1:9`.

```text
| <html>
|   <head>
|   <body>
|     <p>
|       "x"
|     "y"
```

- F2: `<p> </p><frameset>`.
  Whitespace leaves frameset-ok at "ok", so the body is removed.
  Outcome: `unsupported(mode in_frameset)@18`.
  Errors: `!tree@1:1 !tree@1:9`.

```text
| <html>
|   <head>
|   <frameset>
```

### Branch coverage

11. In test builds only, the parser counts each executed branch of the ten modes, in the flat order of `modes.branchIndex`.
    One test resets every counter and runs cases 4 to 10.
    After that, every one of the 130 counters is nonzero.

### Partitions

12. The partition harness parses each input once as one chunk, which gives the reference.
    The reference is the document dump, the error list with positions, and the outcome sequence.
    The compared outcome sequence lists only `script`, `done`, and `unsupported` outcomes, with their offsets.
    `need_input` is a driver signal and is not part of it.
    The reference run calls `feed` with the whole input and then `finish` before its first `run`.
    The harness then parses the input under each partition of the set.
    A `script` outcome is followed by another `run`, and `need_input` by the next chunk or `finish`.
    Every partition must give a byte-identical reference, which must also equal the case's frozen values.
    Set P uses every composition into nonempty chunks, and set B uses every partition into one, two, or three nonempty chunks.
    The mismatch report follows the FP-0008 harness: the case, the failing partition with the fewest chunks, both results, and the 1-minimal input that `lab.ddmin` finds.

| Input | Case | Units | Set | Mode |
| --- | --- | --- | --- | --- |
| Q1 | B13 | 14 | P | off |
| Q2 | B12 | 12 | P | off |
| Q3 | B1 | 4 | P | off |
| Q4 | B11 | 10 | P | off |
| Q5 | A7 | 12 | P | off |
| Q6 | B2 | 16 | B | off |
| Q7 | S1 | 23 | B | on |
| Q8 | A10 | 42 | B | off |
| Q9 | W3 | 197 | B | off |
| Q10 | A2 | 17 | B | off |
| Q11 | B30 | 16 | B | off |
| Q12 | B10 | 58 | B | off |
| Q13 | B32 | 4 | P | off |

### Node retention

13. R1, mode `on`, input of S1.
    At `script@22`, the test removes the `p` element from the body with `removeChild`, and `sweep` returns 0.
    The next `run` returns `done`, the document dump is the first block below, and `writeChildren` of the detached `p` writes the second block:

```text
| <html>
|   <head>
|   <body>
```

```text
| "a"
| <script>
|   "b"
| "c"
```

    After `Parser.deinit`, `sweep` returns 5.

    R2, mode `off`: after `init`, the test appends an HTML `div` element to `document()`, feeds `x`, and calls `finish`.
    `run` returns `error.HierarchyRequest`, and a second `run` returns it again.
    `errors` is `!tree@1:1`, the document mode is quirks, and the dump is `| <div>`.

### Allocation failures

14. `std.testing.checkAllAllocationFailures` creates a store and a parser, feeds A2 in two chunks split at offset 8, and runs to `done`.
    Without an induced failure, the dump and errors equal A2.
    Each induced failure returns `error.OutOfMemory`, and every later `feed`, `finish`, and `run` returns it again.
    `expectInvariants` passes, and nothing leaks.
    The checker's backing allocator is a `testing.FailingAllocator` with `.resize_fail_index = 0`, and the test asserts that its `allocated_bytes` equals its `freed_bytes`.

### Tokenizer character positions

15. The test uses the FP-0064 content driver, which switches to RCDATA after the `title` start tag.
    The input is `<title>a\r\nb&#x1F600;<c\x00d</title>` (32 units).
    In one chunk it gives `S"title"[] C"a\u000Ab\uD83D\uDE00<c" !unexpected-null-character@2:13 C"\uFFFDd" E"title"[] EOF`, in the FP-0064 notation.
    The first run holds a CR LF pair, a character reference that expands to two code units, and a `<` that the RCDATA less-than sign state re-emits.
    The NULL's error starts a new step, so the U+FFFD that stands for the NULL begins the second run.
    A NULL in the data or RCDATA state always starts a run, because its error step flushes the pending characters.
    For each `characters` step that `next` returns, the test reads `characterPosition` for every code unit and appends the positions to one list.
    The list must be exactly the following, on one chunk and on each of the 31 two-chunk partitions:

| Unit | Character | Offset | Line:column |
| --- | --- | --- | --- |
| 1 | `a` | 7 | 1:8 |
| 2 | U+000A from the CR LF pair | 8 | 1:9 |
| 3 | `b` | 10 | 2:1 |
| 4 | U+D83D from `&#x1F600;` | 11 | 2:2 |
| 5 | U+DE00 from `&#x1F600;` | 11 | 2:2 |
| 6 | `<` | 20 | 2:11 |
| 7 | `c` | 21 | 2:12 |
| 8 | U+FFFD for the NULL | 22 | 2:13 |
| 9 | `d` | 23 | 2:14 |

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Implement frozen tree-construction modes with standard recovery. | 1 and 4 to 11 |
| Exercise malformed nesting and chunk boundaries through the actual DOM. | 7, 8, 12, and the invariant check after every case |
| Preserve parser continuation and future script-reentrancy boundaries. | 9, 12 (Q7 and Q9), 13, and 14 |
| Emit inspectable DOM dumps from real parsing. | 3 and every dump of cases 4 to 13 |
| Implement the ten modes, the stack, the list, and the adoption agency algorithm, and execute each of their 130 branches | 1, 4 to 8, and 11 |
| Report unsupported tokens with their owner task | 1 and 10, including the `owner` assertions |
| Return a script outcome before any later character, and keep referenced nodes alive across a sweep | 9 and 13 |
| Compare whole-input results with every partition, including error positions | 12 and 15 |
| Extend the DOM store and keep every FP-0009 outcome | 2, 3, and the FP-0009 cases after the amendments |
| Record whether a character token can change the adjusted current node's namespace | B30 and the README finding |
| Record the non-goals owned by the FP-0026 frontier decomposition | the Non-goals section and the README |

## Stop rules

- If a frozen expected value contradicts the cited standard text, stop.
  Report the case, the expected and observed values, and the line range to the integrator.
- If the `<dt>` listing of evidence item 2 shows a branch of the ten modes that the branch table omits, or the table lists a branch that does not exist, stop and report the difference.
- If a cited line range does not hold the cited text in the local copy, stop and report it.
- If any case needs behavior outside the subset that this contract does not freeze as unsupported, stop and report it.
- If a DOM or tokenizer change would alter an FP-0008, FP-0009, FP-0014, or FP-0064 expected outcome, stop and report it.
- If the partition tests make a `zig build test` run take more than two thirds of the zig-test gate timeout on the recording machine, stop and report the durations, because `FP-0098` owns that budget.
- Never edit an expectation, an input, or an upstream byte to pass a case.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0100/raw/`.
Run every Zig command with the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` and `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Never use a `zig` from `PATH`, and quote the compiler path in a POSIX shell.
Keep each failed or abandoned attempt as its own log, and never delete one.
The form of each Zig command is:

```text
node tools/fairpane.mjs record --env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global engineering/evidence/FP-0100/raw/<log> C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe build test --summary all --cache-dir out/<cache>
```

1. Record `tests-before.log` before you change any non-test code.
   It adds every new test and runs with `--cache-dir out/fp0100-cache-before`.
   It is expected to fail to compile, because `html.Parser`, `modes`, `tree_dump`, the DOM extensions, and `Tokenizer.characterPosition` do not exist.
2. Record `html-standard-text.log`.
   - Record `sha256sum` of the local copy, which must print `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
   - Record `awk 'NR>=141948 && NR<=150800 && /<h[3-6]/ {print NR": "$0}'` over the copy.
   - Record `awk 'NR>=145851 && NR<=149306 && /<dt/ {print NR": "$0}'` over the copy.
   - The README maps each `<dt>` group of the ten modes to a branch of the table, and it lists every cited line that differs.
   - The README marks the commented-out `<!--<dt>` lines 147773 and 147777, and the two `<dt>` lines nested inside the text mode's `script` end tag branch, as not branches.
     It also maps each run of adjacent `<dt>` lines that share one `<dd>` to one branch.
3. Record `wpt-dump-format.log` with `git --git-dir=C:\src\fairpane\.tools\corpora\wpt\repository.git rev-parse` and `cat-file -p` of `b60c4b349d9d167bf354a40bc0d4cbed15174606:html/syntax/parsing/resources/README.md` and `b60c4b349d9d167bf354a40bc0d4cbed15174606:html/syntax/parsing/resources/test.js`.
   The blob IDs must be `0f4be3b4f460437e1a1eab95fc98b9807fd177ae` and `d993273e77eed7e249fab1dfd68baf15ec401001`.
   This command reads the verified snapshot only and opens no network connection.
4. Record an uncached `tests-after.log` with `--cache-dir out/fp0100-cache-after`.
   The README states the run-step duration of the `zig build test` step that `tests-after.log` reports.
   It compares that duration with the same step in the most recent accepted zig-test receipt and with the 400 s limit, which is two thirds of the 600000 ms gate timeout.
   The README states the change in the `zig build test` run-step duration against the base, and how much of it comes from FP-0008 and FP-0064 tests.
5. Run the mutation control.
   - Save the fixed `src/html/tree.zig` as `out/fp0100-tree.fixed.zig`.
   - Make the push onto the list of active formatting elements skip the Noah's Ark removal.
   - Record `git diff --no-index out/fp0100-tree.fixed.zig src/html/tree.zig` in `mutation-noah.log`, which exits with status 1, and store its exact output in `mutation-noah.diff`.
   - Record the test run with `--cache-dir out/fp0100-cache-mutation`.
     It must fail case A9.
     The README records every failing case and the Q8 failure output, which compares the whole-input result with the frozen values of A10.
   - Restore the file, and record `git diff --no-index --exit-code` of the saved and restored files, which exits with status 0.
6. Record `checks-after.log` with `zig fmt --check build.zig src tests` and `node tools/fairpane.mjs test`.
7. Write `engineering/evidence/FP-0100/README.md`.
   - It lists the changed files and every record with its command and `RESULT`.
   - It lists the ten implemented modes, the eleven unimplemented modes with their owners, and the three unsupported features with their owners.
   - It records the FP-0064 amendment 2 finding with the witness input and names FP-0064 amendment 3 and FP-0104 as its owners.
   - It names the FP-0009 test whose rejected-call list changed.
   - It lists each non-goal owned by the FP-0026 frontier decomposition.
   - It lists every stop-rule observation.

The integrator records `HEAD` and a status that includes ignored files for every source root, before and after the gate sequence.
The gates are `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`, each run with `--evidence-dir engineering/evidence/FP-0100/gates`.
No command that writes into a source root runs after the final status check.

## Authority

Writable paths: `src`, `tests`, `build.zig`, and `engineering/evidence/FP-0100/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, `toolchains/rust.lock.json`, `rust-toolchain.toml`, and `specs/corpora.json`.
No network access is permitted.
Evidence item 3 reads the local WPT snapshot through Git.
Required reviewers: `fairpane-review` and `fairpane-spec`.

## Non-goals

- The seven table modes, foster parenting, and reset the insertion mode appropriately belong to `FP-0102`.
- Templates, template contents, content patching, declarative shadow roots, and the frameset modes belong to `FP-0103`, and DOM shadow roots belong to `FP-0127`.
- Foreign content, the `math` and `svg` branches, attribute and tag-name adjustment, integration points, and the tokenizer change that FP-0064 amendment 3 records belong to `FP-0104`.
- The fragment parsing algorithm and the Inert and Fragment scripting modes belong to `FP-0105`.
- The WPT `.dat` harness and its denominator belong to `FP-0101`, and the laboratory tree stage belongs to `FP-0068`.
- Script preparation and execution, the insertion point, the script nesting level, the parser pause flag, `document.write`, and the explicit EOF belong to `FP-0019`.
- `FP-0126`, under `FP-0065`, owns tentative confidence, changing the encoding, and the hook that the `meta` branch calls.
- Selector matching for HTML documents and quirks mode belongs to `FP-0070`.
- Speculative parsing, custom element definitions, form-owner association, the reset algorithm of resettable elements, process internal resource links, the steps that set the parser cannot change the mode flag, and `iframe` `srcdoc` documents belong to the FP-0026 frontier decomposition.
  None of them changes a tree dump, and none of them is reported as done.

## Specification ambiguities

- The standard gives no position for a tree-construction parse error.
  This contract uses the start of the token being processed, and for a character token the source position of that character, so that neither a chunk boundary nor the tokenizer's grouping of characters into runs changes a position.
- "The next token" in the `pre`, `listing`, and `textarea` branches skips parse error steps, because they are not tokens.
  B11 freezes that reading.
- The standard emits one token per character.
  The tokenizer emits runs, and this contract requires the result that per-character processing gives.
- At a `script` end tag the standard prepares the script inline.
  This contract stops at that point with a `script` outcome in both scripting modes, and leaves preparation to the caller.
- The text-mode EOF branch sets a `script` element's already started flag, which the DOM store does not model.
  The parser keeps it in `ScriptState` until `FP-0019` moves it into element state.
- The `non-void-html-element-start-tag-with-trailing-solidus` error has no stated order among a token's other errors.
  This contract places it last.
