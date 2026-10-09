# FP-0064 task contract

## Identity

Task ID: `FP-0064`, "Implement the text-content and CDATA tokenizer states".
Workstream: `html-dom`.
Base: the commit that freezes this contract.
Prerequisite: `FP-0008`, accepted.
This contract extends `engineering/evidence/FP-0008/CONTRACT.md`, which stays in force wherever this contract does not change it.
The `fairpane-spec` worker `FP0064Contract-2` drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.
Required gates: `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`.
Required reviewer: `fairpane-review`.

### Integrator decisions

- The standard text is frozen at the same pin as FP-0008: whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, file `source`, SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b` (`engineering/evidence/FP-0008/raw/html-standard-pin.log`, `raw/integrator-standard-counts.log`).
- After this task, every one of the 84 states is implemented.
  `states.implemented`, `states.owner`, `Tokenizer.unimplementedState`, and `error.UnimplementedState` are removed in a clean cutover.
  They are not kept as functions that always return the same value.
- Tree construction switches states through `Tokenizer.switchTo` with a four-member `ContentState`.
  A switch at a time that tree construction can never request returns `error.SwitchNotAllowed`.
  That error changes no state, and it does not fail the tokenizer.
- `switchTo` has its own error set, `SwitchError`, so the error set of `next`, `feed`, and `finish` names no error that they cannot return.
- The integrator confirmed the tree-construction switch points at the pin.
  `raw/integrator-switch-points.log` records the source digest and every switch sentence and generic-algorithm call site: lines 114105, 145806 to 145807, 146231, 146238, 146301, 147165, 147585, 147607, 147614, 147621, and 150772 to 150793.
  Each names RCDATA, RAWTEXT, script data, or PLAINTEXT, or leaves the data state.
- Tests use a test-only "content driver", which mirrors the element-to-state table of tree construction.
  It is not tree construction.
- FP-0008 case 16 changes on purpose.
  The CDATA section state now exists, so the frozen `error.UnimplementedState` outcome becomes a CDATA token sequence.
  The two-chunk variant uses offset 6, as the FP-0008 contract froze it and the FP-0008 review requested.
- FP-0008 cases 1, 2, 4, 11, and 16 are amended as "FP-0008 amendments" states.
  Every other FP-0008 case keeps its exact expected value.
- The laboratory stages keep their behavior, and this task adds no laboratory case.
  The `tokenize` stage tokenizes only, and FP-0008 cases 18 to 26 keep their values.
- `FP-0077` depends on this task.
  It owns any conformance-harness entry point for the html5lib-tests `initialStates` and `lastStartTag` fields.

## Sources

- The pinned HTML Standard source: <https://raw.githubusercontent.com/whatwg/html/efc54f7b70858d9fcf06d1a5871ae215f448c029/source>, with a local copy at `C:\src\fairpane\out\whatwg-html-source-efc54f7b70858d9fcf06d1a5871ae215f448c029`.
  The drafter read lines 142380 to 143500, 143790 to 143830, 144640 to 144710, and 145785 to 145812 of that copy.
  - §13.2.5, "Tokenization": the definitions of *reconsume*, the *temporary buffer*, and the **appropriate end tag token** ("an end tag token whose tag name matches the tag name of the last start tag to have been emitted from this tokenizer, if any. If no start tag has been emitted from this tokenizer, then no end tag token is appropriate").
  - §13.2.5.2 to §13.2.5.5: the RCDATA, RAWTEXT, script data, and PLAINTEXT states.
  - §13.2.5.9 to §13.2.5.31: the less-than sign, end tag open, end tag name, escape, and double-escape states.
  - §13.2.5.42: the markup declaration open state, whose `[CDATA[` branch switches to the CDATA section state when an adjusted current node exists and is not in the HTML namespace.
  - §13.2.5.69 to §13.2.5.71: the CDATA section, CDATA section bracket, and CDATA section end states, and the note that tree construction handles U+0000 in CDATA sections.
  - §13.2.2: the parse error table, including `eof-in-cdata` and `eof-in-script-html-comment-like-text`.
- The places where tree construction switches the tokenizer:
  - §13.2.6.2, "Parsing elements that contain only text": the generic raw text element parsing algorithm switches to RAWTEXT, and the generic RCDATA element parsing algorithm switches to RCDATA.
  - §13.2.6.4.4, the "in head" insertion mode: a `script` start tag switches to the script data state.
  - §13.2.6.4.7, the "in body" insertion mode: `textarea` switches to RCDATA, and `plaintext` switches to PLAINTEXT. `xmp`, `iframe`, `noembed`, and `noscript`, when scripting is enabled, use the generic raw text algorithm.
  - §13.4, the HTML fragment parsing algorithm: the context element sets the initial state. `title` and `textarea` give RCDATA. `style`, `xmp`, `iframe`, `noembed`, and `noframes` give RAWTEXT. `script` gives script data. `noscript` gives RAWTEXT unless the scripting mode is Disabled. `plaintext` gives PLAINTEXT. Any other context element leaves the data state.
  - The drafter read these from <https://html.spec.whatwg.org/multipage/parsing.html>.
    Evidence item 2 records the same sentences from the pinned copy.
- Repository: `engineering/evidence/FP-0008/CONTRACT.md`, `engineering/evidence/FP-0008/reviews/review-1-accept.json`, `engineering/evidence/FP-0008/README.md`, `src/html/`, `src/lab.zig`, `build.zig`, and `tests/lab/README.md`.

## Behavior

### State set

The tokenizer implements all 84 states of §13.2.5.1 to §13.2.5.84, with every branch of each section.
This task adds these 30 states:

| Sections | States |
| --- | --- |
| 13.2.5.2 to 13.2.5.5 | RCDATA, RAWTEXT, Script data, PLAINTEXT |
| 13.2.5.9 to 13.2.5.11 | RCDATA less-than sign, RCDATA end tag open, RCDATA end tag name |
| 13.2.5.12 to 13.2.5.14 | RAWTEXT less-than sign, RAWTEXT end tag open, RAWTEXT end tag name |
| 13.2.5.15 to 13.2.5.17 | Script data less-than sign, Script data end tag open, Script data end tag name |
| 13.2.5.18 to 13.2.5.25 | Script data escape start, escape start dash, escaped, escaped dash, escaped dash dash, escaped less-than sign, escaped end tag open, escaped end tag name |
| 13.2.5.26 to 13.2.5.31 | Script data double escape start, double escaped, double escaped dash, double escaped dash dash, double escaped less-than sign, double escape end |
| 13.2.5.69 to 13.2.5.71 | CDATA section, CDATA section bracket, CDATA section end |

`src/html/states.zig` keeps `State`, `section`, `title`, `branches`, `branch_count`, `branchIndex`, and `branchAt`.
It removes `implemented` and `owner`.
`branches(state)` is nonempty for every state.
Its header comment states that the tokenizer implements all 84 states.
The branch names of the new states are exactly the following.
"Whitespace" means U+0009, U+000A, U+000C, or U+0020, after newline normalization.

| § | Branches |
| --- | --- |
| 2 | `&`; `<`; NULL; EOF; else |
| 3, 4 | `<`; NULL; EOF; else |
| 5 | NULL; EOF; else |
| 9, 12 | `/`; else |
| 10, 13, 16, 24 | ASCII alpha; else |
| 11, 14, 17, 25 | whitespace with an appropriate end tag; `/` with an appropriate end tag; `>` with an appropriate end tag; ASCII upper alpha; ASCII lower alpha; whitespace, `/`, or `>` otherwise; else |
| 15 | `/`; `!`; else |
| 18, 19 | `-`; else |
| 20, 21, 27, 28 | `-`; `<`; NULL; EOF; else |
| 22, 29 | `-`; `<`; `>`; NULL; EOF; else |
| 23 | `/`; ASCII alpha; else |
| 26, 31 | whitespace, `/`, or `>` with "script"; whitespace, `/`, or `>` otherwise; ASCII upper alpha; ASCII lower alpha; else |
| 30 | `/`; else |
| 69 | `]`; EOF; else |
| 70 | `]`; else |
| 71 | `]`; `>`; else |

That is 118 new branches.
The branches of the 54 FP-0008 states are unchanged.
The markup declaration open branch "[CDATA[ with a foreign adjusted current node" now switches to the CDATA section state.

These consequences of the state text are frozen, because they differ from the data state:

- EOF in an RCDATA, RAWTEXT, script data, or script data escaped less-than sign, end tag open, or end tag name state takes "anything else".
  That branch emits the buffered characters and reconsumes EOF in the text state.
  No `eof-before-tag-name` or `eof-in-tag` error is raised.
  The escaped states then raise `eof-in-script-html-comment-like-text` in the script data escaped state.
- The RCDATA, RAWTEXT, script data, script data escaped and double escaped states, and PLAINTEXT emit U+FFFD for U+0000 and raise `unexpected-null-character`.
- The CDATA section state emits U+0000 unchanged and raises no error.
- An appropriate `>` in the script data escaped end tag name state switches to the data state.
- `-->` in the script data escaped dash dash and double escaped dash dash states switches to the script data state.

### Parse error codes

`raisedByTokenizer(code)` returns `false` only for `non-void-html-element-start-tag-with-trailing-solidus`, which belongs to `FP-0010`.
The tokenizer raises the other 51 codes.
The doc comment of `raisedByTokenizer` says so.

### The last start tag name and the appropriate end tag token

The tokenizer records the tag name of each start tag token when it emits that token.
It keeps the name in storage that it owns, because later tags reuse the tag buffer.
Recording allocates only when that storage grows.
End tags, `switchTo`, and `finish` never change the record.
Before any start tag is emitted, the tokenizer has no last start tag name, and no end tag token is appropriate.
An end tag token is appropriate when its tag name, as built so far, equals the recorded name code unit for code unit.
Both names are lowercased in the same way by their states.

### State switches by tree construction

```zig
/// A state that tree construction switches the tokenizer to (§13.2.6.2, §13.2.6.4.4, §13.2.6.4.7, and §13.4).
pub const ContentState = enum { rcdata, rawtext, script_data, plaintext };

pub const Error = error{ OutOfMemory, ChunkPending, InputFinished };

/// The errors of `switchTo`. `OutOfMemory` is the tokenizer's sticky failure; `SwitchNotAllowed` changes nothing.
pub const SwitchError = error{ OutOfMemory, SwitchNotAllowed };

pub const Tokenizer = struct {
    /// Unchanged from FP-0008. The markup declaration open state reads it when it decides its `[CDATA[` branch.
    adjusted_current_node_is_foreign: bool = false,

    pub fn init(gpa: Allocator) Tokenizer;
    pub fn deinit(t: *Tokenizer) void;
    pub fn feed(t: *Tokenizer, chunk: []const u16) Error!void;
    pub fn finish(t: *Tokenizer) Error!void;
    pub fn next(t: *Tokenizer) Error!?Step;
    pub fn switchTo(t: *Tokenizer, state: ContentState) SwitchError!void;
};
```

`src/html/root.zig` exports `ContentState`.
`Tokenizer.unimplementedState`, the `unimplemented` field, and `error.UnimplementedState` are removed.
The documentation of `next` names only `error.OutOfMemory` as sticky.

The call rules are exact.

- `switchTo` succeeds before the first call of `next`, even after `feed` and `finish`.
- `switchTo` also succeeds when the last step that `next` returned was a start tag token.
- When `next` returns a start tag token, the tokenizer has queued no later step and consumed no later character.
  The switch therefore applies to the next input character.
- In both cases, the tokenizer is in the data state, with no queued step and no character to reconsume.
  `switchTo` sets the state to the requested state.
- Further `switchTo` calls in the same window also succeed, and the last call decides.
- At any other time, `switchTo` returns `error.SwitchNotAllowed` and changes no state.
  That includes after a `characters` token, a parse error, an end tag, a comment, a DOCTYPE, a processing instruction, `need_input`, the end-of-file token, or `null`.
- After `error.OutOfMemory`, `switchTo` returns `error.OutOfMemory`, like every other method.
- Tree construction never switches to the data state, the CDATA section state, or any other state.
  `ContentState` has no other member.
- `switchTo` allocates nothing.

The markup declaration open state reads `adjusted_current_node_is_foreign` when the available input decides its branch.
No token is emitted between the `!` and that decision, so tree construction cannot change the adjusted current node in between.

### Chunk independence

Every new state consumes one character per action and has no lookahead.
Its progress lives in tokenizer fields: the temporary buffer `temp`, the current tag token, the last start tag name, the position of the `<` that starts a possible end tag, and the position of the first pending `]`.
A chunk boundary never changes the result.
The new states reuse the existing `temp` field for the standard's temporary buffer.
They reuse the existing `markup_start` field for the `<` position.

The documentation comment of `Tokenizer.consumeMatched` becomes exactly this line:

```zig
/// Consumes `count` characters that a lookahead matched. Each is an ASCII letter, an ASCII digit, `-`, `[`, or `;`, which preprocessing never reports.
```

The header comment of `src/html/tokenizer.zig` states that the tokenizer implements all 84 states.
It also states that tree construction switches the text states through `switchTo`.

### Positions and spans

The FP-0008 rules stay in force.
These rules extend them:

- `eof-in-cdata` and `eof-in-script-html-comment-like-text` are at the end-of-file character, which is at the input length.
- An `unexpected-null-character` error is at the U+0000 that raised it, including after a reconsume.
- A U+FFFD emitted for a U+0000 spans that U+0000.
- A `<` or `/` that a less-than sign, end tag open, or end tag name state emits for an earlier source character spans that source character.
  The same holds for a character of the temporary buffer that such a state emits.
  These characters are single code units in one line, so a `</` with its temporary buffer spans from the `<` to the current input character.
  At EOF, that is the input length.
- The `<` and `!` that the script data less-than sign state emits span their own source characters.
- The `<` that the script data escaped less-than sign state emits before the double escape start state spans its source `<`.
- Each `]` that the CDATA section bracket or end states emit spans the source `]` that it stands for.
  The bracket state's `]` is the one that the CDATA section state consumed.
  The end state's `]` branch emits the earlier of its two pending `]`, and its "anything else" branch emits both.
- A preprocessing error is still reported when its code point is first consumed, before the state action.
  It therefore precedes characters that the same action emits for earlier source characters, as Q15 shows.

### Test driver

`tokenizeChunks` in `src/html/tokenizer_test.zig` gains a final parameter `setup: Setup`.
`Setup` is `struct { start: ?ContentState = null, foreign: bool = false }`.
`tokenizeChunksForeign` is removed, and its callers pass `.{ .foreign = true }`.
`tokenizeChunks` sets `adjusted_current_node_is_foreign` to `setup.foreign`.
It calls `switchTo(setup.start)` before the first `next` when `start` is not null.
It applies the content driver after every start tag token that `next` returns.

The content driver calls `switchTo` before its next call of `next` when the start tag's name is in this table.
The self-closing flag and the attributes do not matter.

| Start tag name | State |
| --- | --- |
| `title`, `textarea` | `rcdata` |
| `style`, `xmp`, `iframe`, `noembed`, `noframes`, `noscript` | `rawtext` |
| `script` | `script_data` |
| `plaintext` | `plaintext` |

The driver ignores namespaces, insertion modes, and the scripting mode.
No FP-0008 case input contains a start tag in the table, so the driver changes no FP-0008 result.

### Expected-value notation

The FP-0008 notation applies.
Each new table has a `Start` column:

- `-` starts in the data state.
- `rcdata`, `rawtext`, `script`, and `plaintext` call `switchTo` with `.rcdata`, `.rawtext`, `.script_data`, or `.plaintext` before the first `next`.
- `foreign` starts in the data state with `adjusted_current_node_is_foreign` true.

The content driver is active in every new case.

### Laboratory stages

No laboratory stage changes behavior.
The `tokenize` stage still runs `html.Tokenizer` on the decoded code units in one chunk, from the data state.
It makes no `switchTo` call and leaves `adjusted_current_node_is_foreign` false, because only tree construction (`FP-0010`) decides switches.
The doc comment of `tokenize` in `src/lab.zig` says this.
FP-0008 cases 18 to 26, FP-0007 cases 2, 4, 7, and 11, and every FP-0054 case keep their exact expected values.

## FP-0008 amendments

- FP-0008 case 1 becomes "FP-0008 case 1 and FP-0064 case 1".
- FP-0008 case 2 becomes "FP-0008 case 2 and FP-0064 case 2".
- FP-0008 case 4 keeps its table and its whole and one-unit checks.
  Its assertion that the catalog names every raised code moves to FP-0064 case 3, over both catalogs.
- FP-0008 case 11 becomes "FP-0008 case 11 and FP-0064 case 11".
- FP-0008 case 16 becomes "FP-0008 case 16 and FP-0064 case 15".
- The FP-0008 helpers `tokenizeChunks`, `checkCase`, and the partition harness take a `Setup`.
  FP-0008 cases pass the default `Setup`.

## Exact test cases

Zig cases are named `FP-0064 case N: ...` and run through `zig build test`.
Tokenizer cases live in `src/html/tokenizer_test.zig` and `src/html/partition_test.zig`, which extend the FP-0008 helpers instead of adding a second convention.
Every expected sequence in cases 3 to 10 must also hold when the input is fed one code unit per chunk.

### Records

1. `State` has 84 tags.
   `section` returns 1 to 84 in order, and `title` equals the frozen heading list.
   `branches(state)` is nonempty for all 84 states.
   `branch_count` equals the sum of the branch list lengths.
   `states.implemented` and `states.owner` do not exist.
2. `ErrorCode` has 52 tags in table order.
   `raisedByTokenizer` is false exactly for `non-void-html-element-start-tag-with-trailing-solidus`, so 51 codes are raised.

### Error catalog

3. Each input produces exactly the expected sequence.
   The union of the FP-0008 case 4 table and this table names each of the 51 raised codes.
   Each named code appears in its row's expected sequence.

| Case | Code | Start | Input | Expected |
| --- | --- | --- | --- | --- |
| K1 | eof-in-cdata | foreign | `<![CDATA[x` | `C"x" !eof-in-cdata@1:11 EOF` |
| K2 | eof-in-script-html-comment-like-text | - | `<script><!--` | `S"script"[] C"<!--" !eof-in-script-html-comment-like-text@1:13 EOF` |

### State walks

4. RCDATA.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| RC1 | - | `<title>a&amp;b\0</title>c` | `S"title"[] C"a&b" !unexpected-null-character@1:15 C"\uFFFD" E"title"[] C"c" EOF` |
| RC2 | - | `<title>&not</title>` | `S"title"[] !missing-semicolon-after-character-reference@1:11 C"\u00AC" E"title"[] EOF` |
| RC3 | - | `<title>a<b` | `S"title"[] C"a<b" EOF` |
| RC4 | - | `<title><` | `S"title"[] C"<" EOF` |
| RC5 | - | `<title></1` | `S"title"[] C"</1" EOF` |
| RC6 | - | `<title></` | `S"title"[] C"</" EOF` |
| RC7 | - | `<title></TITLE>` | `S"title"[] E"title"[] EOF` |
| RC8 | - | `<title></title x=1>` | `S"title"[] !end-tag-with-attributes@1:19 E"title"[x="1"] EOF` |
| RC9 | - | `<title></title/>` | `S"title"[] !end-tag-with-trailing-solidus@1:16 E"title"[]/ EOF` |
| RC10 | - | `<title></b>x</title>` | `S"title"[] C"</b>x" E"title"[] EOF` |
| RC11 | - | `<textarea></t a></t/b>` | `S"textarea"[] C"</t a></t/b>" EOF` |
| RC12 | - | `<title></TiTx>` | `S"title"[] C"</TiTx>" EOF` |
| RC13 | - | `<title></tit` | `S"title"[] C"</tit" EOF` |
| RC14 | - | `<title></tit1e>` | `S"title"[] C"</tit1e>" EOF` |
| RC15 | - | `<title></title\t>` | `S"title"[] E"title"[] EOF` |

5. RAWTEXT.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| RW1 | - | `<style>a&amp;\0<b></style>c` | `S"style"[] C"a&amp;" !unexpected-null-character@1:14 C"\uFFFD<b>" E"style"[] C"c" EOF` |
| RW2 | - | `<xmp></1</XMP/>` | `S"xmp"[] C"</1" !end-tag-with-trailing-solidus@1:15 E"xmp"[]/ EOF` |
| RW3 | - | `<iframe></ifram></iframe\t>` | `S"iframe"[] C"</ifram>" E"iframe"[] EOF` |
| RW4 | - | `<noframes>a</n-` | `S"noframes"[] C"a</n-" EOF` |
| RW5 | - | `<noscript><` | `S"noscript"[] C"<" EOF` |
| RW6 | - | `<style></style x>` | `S"style"[] !end-tag-with-attributes@1:17 E"style"[x=""] EOF` |
| RW7 | - | `<noembed></no/>` | `S"noembed"[] C"</no/>" EOF` |
| RW8 | - | `<xmp></X` | `S"xmp"[] C"</X" EOF` |

6. Script data and its escape states.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| SD1 | - | `<script>a<b\0</script>c` | `S"script"[] C"a<b" !unexpected-null-character@1:12 C"\uFFFD" E"script"[] C"c" EOF` |
| SD2 | - | `<script></1</SCRIPT/>` | `S"script"[] C"</1" !end-tag-with-trailing-solidus@1:21 E"script"[]/ EOF` |
| SD3 | - | `<script></scrip></script x>` | `S"script"[] C"</scrip>" !end-tag-with-attributes@1:27 E"script"[x=""] EOF` |
| SD4 | - | `<script></s1` | `S"script"[] C"</s1" EOF` |
| SD5 | - | `<script><!a` | `S"script"[] C"<!a" EOF` |
| SD6 | - | `<script><!-a` | `S"script"[] C"<!-a" EOF` |
| SD7 | - | `<script><!` | `S"script"[] C"<!" EOF` |
| SD8 | - | `<script><!-` | `S"script"[] C"<!-" EOF` |
| SD9 | - | `<script><` | `S"script"[] C"<" EOF` |
| SD10 | - | `<script></` | `S"script"[] C"</" EOF` |
| SD11 | - | `<script><!-a</script>` | `S"script"[] C"<!-a" E"script"[] EOF` |

7. Script data escaped states.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| SE1 | - | `<script><!--x\0-y--z-->` | `S"script"[] C"<!--x" !unexpected-null-character@1:14 C"\uFFFD-y--z-->" EOF` |
| SE2 | - | `<script><!---\0-\0` | `S"script"[] C"<!---" !unexpected-null-character@1:14 C"\uFFFD-" !unexpected-null-character@1:16 C"\uFFFD" !eof-in-script-html-comment-like-text@1:17 EOF` |
| SE3 | - | `<script><!--a-` | `S"script"[] C"<!--a-" !eof-in-script-html-comment-like-text@1:15 EOF` |
| SE4 | - | `<script><!--<a-<1--</b></script>` | `S"script"[] C"<!--<a-<1--</b>" E"script"[] EOF` |
| SE5 | - | `<script><!--</1</Scr1` | `S"script"[] C"<!--</1</Scr1" !eof-in-script-html-comment-like-text@1:22 EOF` |
| SE6 | - | `<script><!--</script x>` | `S"script"[] C"<!--" !end-tag-with-attributes@1:23 E"script"[x=""] EOF` |
| SE7 | - | `<script><!--</SCRIPT/>` | `S"script"[] C"<!--" !end-tag-with-trailing-solidus@1:22 E"script"[]/ EOF` |
| SE8 | - | `<script><!--<` | `S"script"[] C"<!--<" !eof-in-script-html-comment-like-text@1:14 EOF` |
| SE9 | - | `<script><!--</` | `S"script"[] C"<!--</" !eof-in-script-html-comment-like-text@1:15 EOF` |
| SE10 | - | `<script><!--</sc` | `S"script"[] C"<!--</sc" !eof-in-script-html-comment-like-text@1:17 EOF` |

8. Script data double escape states.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| DE1 | - | `<script><!--<script>a-b--c<d</e</script>-->` | `S"script"[] C"<!--<script>a-b--c<d</e</script>-->" EOF` |
| DE2 | - | `<script><!--<SCRIPTx>` | `S"script"[] C"<!--<SCRIPTx>" !eof-in-script-html-comment-like-text@1:22 EOF` |
| DE3 | - | `<script><!--<script>\0` | `S"script"[] C"<!--<script>" !unexpected-null-character@1:21 C"\uFFFD" !eof-in-script-html-comment-like-text@1:22 EOF` |
| DE4 | - | `<script><!--<script>-\0-` | `S"script"[] C"<!--<script>-" !unexpected-null-character@1:22 C"\uFFFD-" !eof-in-script-html-comment-like-text@1:24 EOF` |
| DE5 | - | `<script><!--<script>---\0--<--` | `S"script"[] C"<!--<script>---" !unexpected-null-character@1:24 C"\uFFFD--<--" !eof-in-script-html-comment-like-text@1:30 EOF` |
| DE6 | - | `<script><!--<script>-<-->x` | `S"script"[] C"<!--<script>-<-->x" EOF` |
| DE7 | - | `<script><!--<script></SCRIPTS>` | `S"script"[] C"<!--<script></SCRIPTS>" !eof-in-script-html-comment-like-text@1:31 EOF` |
| DE8 | - | `<script><!--<script/x</script\tx-->` | `S"script"[] C"<!--<script/x</script\u0009x-->" EOF` |
| DE9 | - | `<script><!--<script><` | `S"script"[] C"<!--<script><" !eof-in-script-html-comment-like-text@1:22 EOF` |
| DE10 | - | `<script><!--<scr` | `S"script"[] C"<!--<scr" !eof-in-script-html-comment-like-text@1:17 EOF` |
| DE11 | - | `<script><!--<script></scr` | `S"script"[] C"<!--<script></scr" !eof-in-script-html-comment-like-text@1:26 EOF` |

9. PLAINTEXT and CDATA sections.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| PT1 | - | `<plaintext>a</plaintext>\0&amp;<b>` | `S"plaintext"[] C"a</plaintext>" !unexpected-null-character@1:25 C"\uFFFD&amp;<b>" EOF` |
| CD1 | foreign | `<![CDATA[a]b]]c]]]>d` | `C"a]b]]c]d" EOF` |
| CD2 | foreign | `<![CDATA[\0\u0001]` | `C"\u0000" !control-character-in-input-stream@1:11 C"\u0001]" !eof-in-cdata@1:13 EOF` |
| CD3 | foreign | `<![CDATA[]]` | `C"]]" !eof-in-cdata@1:12 EOF` |
| CD4 | foreign | `<![CDATA[]]>` | `EOF` |
| CD5 | foreign | `<![CDATA[<a>&amp;</a>]]><b>` | `C"<a>&amp;</a>" S"b"[] EOF` |
| CD6 | foreign | `<!--a--><![CDATA[` | `M"a" !eof-in-cdata@1:18 EOF` |

10. The last start tag name.

| Case | Start | Input | Expected |
| --- | --- | --- | --- |
| L1 | - | `<title>x</title><b><textarea></title></textarea>` | `S"title"[] C"x" E"title"[] S"b"[] S"textarea"[] C"</title>" E"textarea"[] EOF` |
| L2 | rcdata | `</title>a` | `C"</title>a" EOF` |
| L3 | rawtext | `</xmp>` | `C"</xmp>" EOF` |
| L4 | - | `<title/></title>` | `S"title"[]/ E"title"[] EOF` |
| L5 | - | `<TITLE></title>` | `S"title"[] E"title"[] EOF` |
| L6 | - | `<script></script><style></script></style>` | `S"script"[] E"script"[] S"style"[] C"</script>" E"style"[] EOF` |

11. Branch coverage.
    In test builds only, the tokenizer counts each executed branch of each of the 84 states.
    One test resets every counter and runs FP-0008 cases 4 to 10 and 16 and FP-0064 cases 3 to 10 and 15.
    After that, every counter is nonzero.
    `branch_count` equals the sum of the lengths of all 84 branch lists.

### Source positions

12. Each input produces exactly this dump with spans and errors.

- SP1, Start `-`, input `<title></b\0`:

  ```text
  ["StartTag","title",[],false,[0,7]]
  ["Character","</b",[7,10]]
  ["error","unexpected-null-character",1,11,10]
  ["Character","\uFFFD",[10,11]]
  ["EOF",[11,11]]
  ```

- SP2, Start `foreign`, input `<![CDATA[]]]\u0001`:

  ```text
  ["Character","]",[9,10]]
  ["error","control-character-in-input-stream",1,13,12]
  ["Character","]]\u0001",[10,13]]
  ["error","eof-in-cdata",1,14,13]
  ["EOF",[13,13]]
  ```

- SP3, Start `-`, input `<script><!--<s\0`:

  ```text
  ["StartTag","script",[],false,[0,8]]
  ["Character","<!--<s",[8,14]]
  ["error","unexpected-null-character",1,15,14]
  ["Character","\uFFFD",[14,15]]
  ["error","eof-in-script-html-comment-like-text",1,16,15]
  ["EOF",[15,15]]
  ```

- SP4, Start `-`, input `<xmp>\r\n</xmp\n>` (14 code units):

  ```text
  ["StartTag","xmp",[],false,[0,5]]
  ["Character","\u000A",[5,7]]
  ["EndTag","xmp",[],false,[7,14]]
  ["EOF",[14,14]]
  ```

  The end tag starts at line 2, column 1, and the end-of-file token is at line 3, column 2.

- SP5, Start `-`, input `<script></scrip`:

  ```text
  ["StartTag","script",[],false,[0,8]]
  ["Character","</scrip",[8,15]]
  ["EOF",[15,15]]
  ```

### Partitions and continuation

13. Partition comparison through the FP-0008 harness, with a `Setup` per input.
    Set P uses every composition into nonempty chunks.
    `=X` means the expected sequence of case X.
    For an SP input, it means the full dump of case 12.

| Case | Start | Input | Units | Expected |
| --- | --- | --- | --- | --- |
| Q1 | - | `<xmp>a</xmp>b` | 13 | `S"xmp"[] C"a" E"xmp"[] C"b" EOF` |
| Q2 | - | `<xmp></xmpa>` | 12 | `S"xmp"[] C"</xmpa>" EOF` |
| Q3 | - | `<xmp></XMP\r\n>` | 13 | `S"xmp"[] E"xmp"[] EOF` |
| Q4 | rcdata | `&lt</a>\r\n` | 9 | `!missing-semicolon-after-character-reference@1:3 C"<</a>\u000A" EOF` |
| Q5 | script | `<!--<script>-->` | 15 | `C"<!--<script>-->" EOF` |
| Q6 | script | `<!-x<!--\0-` | 10 | `C"<!-x<!--" !unexpected-null-character@1:9 C"\uFFFD-" !eof-in-script-html-comment-like-text@1:11 EOF` |
| Q7 | script | `<!--<SCRIPT>-\0` | 14 | `C"<!--<SCRIPT>-" !unexpected-null-character@1:14 C"\uFFFD" !eof-in-script-html-comment-like-text@1:15 EOF` |
| Q8 | script | `<!--</script>` | 13 | `C"<!--</script>" !eof-in-script-html-comment-like-text@1:14 EOF` |
| Q9 | foreign | `<![CDATA[a]]]>` | 14 | `C"a]" EOF` |
| Q10 | foreign | `<![CDATA[]\0]` | 12 | `C"]\u0000]" !eof-in-cdata@1:13 EOF` |
| Q11 | foreign | `<![CDATA[\uD83D\uDE00]]>` | 14 | `C"\uD83D\uDE00" EOF` |
| Q12 | foreign | `<![CDATA[x]]>` | 13 | `C"x" EOF` |
| Q13 | - | `<![CDATA[x]]>` | 13 | `=A5` of FP-0008 |
| Q14 | plaintext | `a\r</plaintext>` | 14 | `C"a\u000A</plaintext>" EOF` |
| Q15 | rawtext | `\uD800</\uDC00` | 4 | `!surrogate-in-input-stream@1:1 C"\uD800" !surrogate-in-input-stream@1:4 C"</\uDC00" EOF` |
| Q16 | script | `<!--<script></s` | 15 | `C"<!--<script></s" !eof-in-script-html-comment-like-text@1:16 EOF` |
| SP1 to SP5 | as case 12 | as case 12 | 11, 13, 15, 14, 15 | `=SP1` to `=SP5` |

A test resets the branch counters and runs each set P input of this case once as one chunk.
Then every one of the 30 new states has a nonzero counter, so each new state is under every-partition comparison.

Set B uses every partition into one, two, or three nonempty chunks.
It covers RC1, RC8, RC11, RW1, RW3, SD3, SD11, SE1, SE4, SE5, DE1, DE5, DE7, DE8, PT1, CD1, CD2, CD5, L1, and L6, each with its own `Start`.

The mismatch report keeps the FP-0008 format.
It names the case and input ID.

14. Interface edges of `switchTo`.
    - E1: For each row, the test feeds `&amp;<!--\0`, calls `finish`, calls `switchTo` with the row's state, and drains.
      Each row gives exactly the expected sequence:

      | State | Expected |
      | --- | --- |
      | none | `C"&" !unexpected-null-character@1:10 !eof-in-comment@1:11 M"\uFFFD" EOF` |
      | `.rcdata` | `C"&<!--" !unexpected-null-character@1:10 C"\uFFFD" EOF` |
      | `.rawtext` | `C"&amp;<!--" !unexpected-null-character@1:10 C"\uFFFD" EOF` |
      | `.script_data` | `C"&amp;<!--" !unexpected-null-character@1:10 C"\uFFFD" !eof-in-script-html-comment-like-text@1:11 EOF` |
      | `.plaintext` | `C"&amp;<!--" !unexpected-null-character@1:10 C"\uFFFD" EOF` |

    - E2: Before the first `next`, `switchTo(.rcdata)` and then `switchTo(.plaintext)` both succeed.
      Input `&amp;` gives `C"&amp;" EOF`.
    - E3: The input is `a<b>&amp;</b>`, without the content driver.
      The first `next` returns `C"a"`, and `switchTo(.rawtext)` then returns `error.SwitchNotAllowed`.
      The next `next` returns `S"b"[]`, and `switchTo(.rawtext)` then succeeds.
      The whole sequence is `C"a" S"b"[] C"&amp;" E"b"[] EOF`.
    - E4: The test feeds `<b>` without `finish`.
      `next` returns `S"b"[]` and then `need_input`, and `switchTo(.rawtext)` then returns `error.SwitchNotAllowed`.
      Feeding `&amp;`, calling `finish`, and draining gives `C"&" EOF`.
    - E5: For input `\0<b>`, `switchTo` after the first step, which is a parse error, returns `error.SwitchNotAllowed`.
    - E6: For input `<b></b>&amp;`, `switchTo` after the end tag returns `error.SwitchNotAllowed`.
      The whole sequence is `S"b"[] E"b"[] C"&" EOF`.
    - E7: `switchTo` after the end-of-file token returns `error.SwitchNotAllowed`.
      It does so again after `next` returns `null`.
    - E8: For input `<b></b>`, `switchTo(.rcdata)` and then `switchTo(.plaintext)` after `S"b"[]` both succeed.
      The whole sequence is `S"b"[] C"</b>" EOF`.
    - E9: A rejected `switchTo` changes no dump, as E3, E4, and E6 show by their exact sequences.
15. FP-0008 case 16, split at offset 6.
    - With `adjusted_current_node_is_foreign` true, `<![CDATA[x]]>` in one chunk gives `C"x" EOF`.
      Its full dump is `["Character","x",[9,10]]` and `["EOF",[13,13]]`.
    - With the flag true, the test feeds the chunk `<![CDA` (boundary 6), and the first `next` returns `need_input`.
      The test then feeds `TA[x]]>` and calls `finish`, and draining completes the same full dump.
    - With the flag false, the same input gives FP-0008 A5, whole and with the single boundary 6.
16. `std.testing.checkAllAllocationFailures` tokenizes `<title>&lt;</ti</title><script><!--<script></script>--></script>` with the content driver, in three chunks split at offsets 9 and 30.
    Without an induced failure, the sequence is `S"title"[] C"<</ti" E"title"[] S"script"[] C"<!--<script></script>-->" E"script"[] EOF`.
    Each induced failure returns `error.OutOfMemory`.
    Every later `next`, `feed`, `finish`, and `switchTo` returns it again, and nothing leaks.
    Like FP-0008 case 17, the checker's backing allocator is a `testing.FailingAllocator` with `.resize_fail_index = 0`, and the test asserts that its `allocated_bytes` equals its `freed_bytes`.

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Implement the RCDATA, RAWTEXT, script data, PLAINTEXT, and CDATA section tokenizer states completely, with every parse error they raise | 2 to 12 and 15 |
| Expose the state switches that tree construction makes, without implementing tree construction | 10, 14, 16, and the content driver of cases 4 to 13 |
| Compare whole-input results with every partition of small adversarial inputs for each new state | 13, its state-coverage check, and the one-unit chunking of cases 3 to 10 |
| Record that no tokenizer state remains unimplemented | 1 and 11, and the evidence README |
| Split FP-0008 case 16 at offset 6, and correct the consumeMatched documentation | 15, and the frozen comment line, which the README quotes |

### Stop rules

If a frozen expected value contradicts the cited state text, stop.
Report the input, the expected and observed values, and the spec branch to the integrator.
If the pinned source's text of any of the 30 states has a branch that the branch table above omits, stop and report the difference.
Stop in the same way if a listed branch does not exist in that text.
If the pinned source names a tree-construction switch to a state outside `ContentState`, stop and report it.
Never edit an expectation, an input, or an upstream byte to pass a case.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0064/raw/`.
Run every Zig command with the locked compiler `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` and `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Never use a `zig` from `PATH`.
Quote the compiler path in a POSIX shell, because FP-0008's first attempt lost its backslashes.
Keep each failed or abandoned attempt as its own log or its own record in a log, and never delete one.
The form of each Zig command is:

```text
node tools/fairpane.mjs record --env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global engineering/evidence/FP-0064/raw/<log> C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe build test --summary all --cache-dir out/<cache>
```

1. Record `tests-before.log` before you edit any implementation file.
   - Run 1 adds every new test and fixture and runs with `--cache-dir out/fp0064-cache-before`.
     It is expected to fail to compile, because `switchTo`, `ContentState`, and `Setup` do not exist.
   - Run 2 keeps the base sources and adds only cases K1, CD1 to CD6, Q9 to Q12, and the flag-true part of case 15, through the base helper `tokenizeChunksForeign`.
     It runs with `--cache-dir out/fp0064-cache-before-behavior`.
     It must fail with `error.UnimplementedState`.
   - The README states the time of each run relative to the first implementation edit.
2. Record `html-standard-text.log`.
   - Record `sha256sum` of `C:\src\fairpane\out\whatwg-html-source-efc54f7b70858d9fcf06d1a5871ae215f448c029`, which must print `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
   - Record `grep -n "<h5><dfn[^>]*>[^<]* state</dfn></h5>"` over that file.
   - Record `grep -n -i -E "(switch|leave) the tokenizer"` over that file.
   - The README lists each tree-construction switch point with its line number.
     It names any sentence that the second pattern misses because a line wraps.
   - If the local copy is absent, record a `curl -sfL` fetch of the pinned raw URL into `out/` first.
     That is the only permitted network access.
3. Record an uncached `tests-after.log` with `--cache-dir out/fp0064-cache-after`.
4. Run the mutation control.
   - Save the fixed `src/html/tokenizer.zig` as `out/fp0064-tokenizer.fixed.zig`.
   - Make `t.temp.clearRetainingCapacity();` the first statement of `Tokenizer.release`.
   - In `mutation-temp-release.log`, record `git diff --no-index out/fp0064-tokenizer.fixed.zig src/html/tokenizer.zig`, which exits with status 1.
   - Store its exact output in `mutation-temp-release.diff`.
   - Record the test run with `--cache-dir out/fp0064-cache-mutation`.
     It must fail case 13 on input Q2.
     The README records the reported partition, both dumps, the 1-minimal input, and every other failing case.
   - Restore the file.
   - Record `git diff --no-index --exit-code` of the saved and restored files, which exits with status 0.
5. Record `checks-after.log` with `zig fmt --check build.zig src tests` and `node tools/fairpane.mjs test`.
6. Write `engineering/evidence/FP-0064/README.md`.
   - It lists the changed files and every record with its command and `RESULT`.
   - It states that all 84 states are implemented and that `branch_count` grew by 118.
   - It states that `non-void-html-element-start-tag-with-trailing-solidus` is the only unraised code, owned by `FP-0010`.
   - It quotes the new `consumeMatched` comment.
   - It lists the switch points from item 2, the mutation result, and every stop-rule observation.

The integrator records `HEAD` and a status that includes ignored files for every source root, before and after the gate sequence.
The gates are `repo-check`, `controller-test`, `zig-fmt`, and `zig-test`, each run with `--evidence-dir engineering/evidence/FP-0064/gates`.
No command that writes into a source root runs after the final status check.

## Authority

Writable paths: `src`, `tests`, `build.zig`, and `engineering/evidence/FP-0064/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
The only permitted network access is the fallback fetch of the pinned source in evidence item 2.
Required reviewer: `fairpane-review`.

## Non-goals

- Tree construction, the insertion modes, self-closing acknowledgement, and `non-void-html-element-start-tag-with-trailing-solidus` belong to `FP-0010`.
  So do the decision when to call `switchTo` and the computation of the adjusted current node.
- The insertion point, `document.write`, the script nesting level, and the parser pause flag belong to `FP-0019`.
- Encoding sniffing and decoders belong to `FP-0065`.
- The html5lib-tests tokenizer files belong to `FP-0077`.
  That includes their `initialStates`, among them "CDATA section state", and their `lastStartTag` field, which this interface does not expose because tree construction never sets them.
- No WPT item runs.
  The pinned WPT tree has no tokenizer-level tests, and its `html/syntax/parsing/` tests need `FP-0010` and `FP-0019`, as FP-0008 recorded.
- This task makes no change to the C ABI, `api`, `include`, `specs`, a threshold, a gate, or a corpus pin.
- The fragment algorithm notes that PLAINTEXT could stand in for RAWTEXT and script data as an optimization.
  This task does not apply it.
  It adds no fast path.
- The remaining FP-0008 review notes belong to the tasks that the integrator routed them to: the README path, the timing of the regeneration, and the entity table notice (`FP-0075`).

## Specification ambiguities

- "The last start tag to have been emitted from this tokenizer": with the pull interface, a start tag is emitted when the tokenizer queues it.
  It is always the last step of its action, so the caller receives it before the tokenizer consumes another character.
- The standard lets tree construction change the tokenizer state while it handles a token.
  Tree construction does so only for start tags and before parsing begins (the fragment case).
  This contract allows `switchTo` exactly then and reports `error.SwitchNotAllowed` otherwise.
- The fragment parsing algorithm sets the tokenizer state but emits no start tag.
  So no end tag is appropriate until a start tag is emitted, as L2 and L3 show.
  This contract follows the text as written.
  html5lib-tests supplies a `lastStartTag` instead, and `FP-0077` records that difference.
- The standard emits `<`, `/`, temporary buffer characters, and `]` without source positions.
  This contract assigns each one the span of the source character that it stands for.
- When an end tag name state's "anything else" branch consumes a character that has a preprocessing error, the error precedes the replayed `</` characters in step order.
  That follows from the FP-0008 rule that preprocessing errors are reported first, as Q15 shows.
- The standard compares the temporary buffer with "script" in the double escape states, and it builds the buffer in lowercase.
  This contract compares it code unit for code unit.

## Amendments

1. Case 13, row Q11: the Units value is 14, not 13.
   The input is `<![CDATA[` (9 code units), the surrogate pair (2), and `]]>` (3).
   Worker `FP0064States` found the frozen value wrong when the units assertion reported "expected 13, found 14", and kept that run as `raw/tests-attempt-1.log`.
   The expected token sequence is unchanged.
2. Two sentences of this contract were imprecise, and review 1 found both; no requirement changes.
   Section "State switches by tree construction" says that no token is emitted between the `!` and the `[CDATA[` decision.
   When the markup declaration open state waits for more input, the tokenizer first returns the pending characters from before the `<`, so a `characters` step can come between them.
   The integrator decision on `SwitchError` says that the error set of `next`, `feed`, and `finish` names no error that they cannot return.
   The frozen signatures keep the shared `Error` set for all three, and `next` and `finish` never return `ChunkPending` or `InputFinished`; only `switchTo` has its own set.
   `FP-0010` must confirm that no character token can change the adjusted current node's namespace before it relies on `adjusted_current_node_is_foreign` across `need_input`.
3. The confirmation that amendment 2 asks of `FP-0010` fails in general, as the FP-0010 split draft by agent `FP0010Contract` found.
   A character token can change the adjusted current node from a foreign element to an HTML element.
   At a MathML text integration point or an HTML integration point, tree construction processes a character in the in body insertion mode, which reconstructs the active formatting elements and so can push an HTML element.
   The tokenizer also reads `adjusted_current_node_is_foreign` in the markup declaration open state while characters from before the `<` are still pending.
   With the input `<math><mi><p><b></p>x<![CDATA[y]]>`, one chunk then gives the text `xy` in the new `b` element, while a split inside `[CDATA[` gives the text `x` and the comment `[CDATA[y]]`; the HTML standard gives the second result [INFERENCE: from the draft's reading of the pinned standard, not yet run].
   No FP-0064 case can reach this, because tree construction, which alone sets the flag from the stack, does not exist yet.
   `FP-0104` owns the fix: the markup declaration open state returns the pending characters to tree construction before it reads the flag, and a chunk-partition case runs the witness.
   `FP-0100` never sets the flag, because it constructs no foreign content.

