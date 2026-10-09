# FP-0008 task contract

## Identity

Task ID: `FP-0008`, "Implement HTML tokenizer continuations".
Workstream: `html-dom`.
Base: the commit that freezes this contract, after `FP-0054` was accepted.
Prerequisites: `FP-0005` and `FP-0007`, accepted.
The `fairpane-spec` worker `FP0008Contract` drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Integrator decisions

- The owner approved `entities.json` from the WHATWG and its license text in the public repository on 2026-10-09.
  `engineering/evidence/FP-0008/owner-answers.log` records the question and the answer, and `LICENSE-DECISION.md` records the decision.
- Plan task `FP-0064`, "Implement the text-content and CDATA tokenizer states", depends on `FP-0008`, and `FP-0010` depends on it.
- Plan task `FP-0065`, "Implement encoding sniffing and the Encoding Standard decoders", owns every decode behavior that this task leaves unsupported.
- `FP-0054` is accepted, so the laboratory changes below apply to case versions 1 and 2.
- This contract freezes the HTML Standard text as of "Last Updated 7 October 2026": whatwg/html commit `efc54f7b70858d9fcf06d1a5871ae215f448c029` [S85], whose `source` file has SHA-256 `8184f8d730b5a3c47bbf657c01c3021149774c9efb8e59a2183bf6857704f70b`.
  `raw/html-standard-pin.log` records that digest, and the integrator counted 84 tokenizer states and 52 parse error codes in that file.
- The laboratory `decode` stage completes only for a UTF-8 byte order mark, as "Laboratory stages" states.
- FP-0007 case 2's stage assertions change on purpose: `decode` becomes `unsupported` and `tokenize` becomes `not-reached`.
- Error positions and error order follow this contract's rules, which use the standard's "current input character" and its preprocessing-first order, where html5lib-tests differs.
  Task `FP-0077` imports html5lib-tests and records each difference.
- Test-only branch counters, compiled only when `builtin.is_test` is set, are acceptable.
- `lab.ddmin` becomes generic over its element type for mismatch minimization.
- The resolutions under "Specification ambiguities" are accepted.

## Sources

- HTML Standard [S12], parsing: <https://html.spec.whatwg.org/multipage/parsing.html>.
  - §13.2.1, the script nesting level and the parser pause flag.
  - §13.2.2, "Parse errors", and its table of 52 error codes: <https://html.spec.whatwg.org/multipage/parsing.html#parse-errors>.
  - §13.2.3, "The input byte stream", and §13.2.3.2, step 1 of the encoding sniffing algorithm: <https://html.spec.whatwg.org/multipage/parsing.html#determining-the-character-encoding>.
  - §13.2.3.5, "Preprocessing the input stream": <https://html.spec.whatwg.org/multipage/parsing.html#preprocessing-the-input-stream>.
  - §13.2.4.2, the adjusted current node: <https://html.spec.whatwg.org/multipage/parsing.html#adjusted-current-node>.
  - §13.2.5, "Tokenization", and §13.2.5.1 to §13.2.5.84: <https://html.spec.whatwg.org/multipage/parsing.html#tokenization>.
  - §13.2.6.2, "Parsing elements that contain only text": <https://html.spec.whatwg.org/multipage/parsing.html#parsing-elements-that-contain-only-text>.
- HTML Standard §13.5, "Named character references": <https://html.spec.whatwg.org/multipage/named-characters.html#named-character-references>, and its JSON form <https://html.spec.whatwg.org/entities.json>.
- HTML Standard license: <https://github.com/whatwg/html/blob/main/LICENSE>, recorded at a pinned commit, and the copyright line in <https://html.spec.whatwg.org/multipage/acknowledgements.html>.
- Infra Standard §4.6, "Code points" (surrogate, noncharacter, control, ASCII whitespace, ASCII alpha, ASCII alphanumeric, ASCII hex digit): <https://infra.spec.whatwg.org/#code-points>. §4.7, "normalize newlines": <https://infra.spec.whatwg.org/#normalize-newlines>.
- Encoding Standard §6.1, "decode" and "BOM sniff": <https://encoding.spec.whatwg.org/#decode> and <https://encoding.spec.whatwg.org/#bom-sniff>.
- WPT at the pinned commit `b60c4b349d9d167bf354a40bc0d4cbed15174606` [S48]:
  - <https://github.com/web-platform-tests/wpt/blob/b60c4b349d9d167bf354a40bc0d4cbed15174606/html/syntax/parsing/resources/README.md>.
  - <https://github.com/web-platform-tests/wpt/blob/b60c4b349d9d167bf354a40bc0d4cbed15174606/html/syntax/parsing/resources/processing-instructions.dat>.
  - <https://github.com/web-platform-tests/wpt/blob/b60c4b349d9d167bf354a40bc0d4cbed15174606/tools/third_party/html5lib/.gitmodules>.
  - The manifest at that commit [S46].
- Repository: `docs/RENDERING_AND_TEXT.md` "HTML", `docs/ARCHITECTURE.md` "Dependency boundary", `specs/IMPORT_REQUIREMENTS.md` "Common rules", `LICENSE-DECISION.md`, `src/web_string.zig`, `src/lab.zig`, and `engineering/evidence/FP-0007/CONTRACT.md`.

## Behavior

### Frozen state subset

The tokenizer implements exactly these 54 states completely, with every branch of each section.

| Sections | States |
| --- | --- |
| 13.2.5.1 | Data state |
| 13.2.5.6 to 13.2.5.8 | Tag open, End tag open, Tag name |
| 13.2.5.32 to 13.2.5.40 | Before attribute name through Self-closing start tag |
| 13.2.5.41 to 13.2.5.52 | Bogus comment, Markup declaration open, and the ten comment states |
| 13.2.5.53 to 13.2.5.68 | The sixteen DOCTYPE states |
| 13.2.5.72 to 13.2.5.76 | The five processing instruction states |
| 13.2.5.77 to 13.2.5.84 | The eight character reference states |

These are exactly the states that the machine reaches from its initial data state without any action from tree construction.

The remaining 30 states are recorded as unimplemented, with owner task `FP-0064`.

| Sections | States | Why they wait |
| --- | --- | --- |
| 13.2.5.2 to 13.2.5.5 | RCDATA, RAWTEXT, Script data, PLAINTEXT | Only tree construction switches the tokenizer into them (§13.2.6.2 and the "in body" rules). |
| 13.2.5.9 to 13.2.5.31 | The RCDATA, RAWTEXT, and script data less-than sign, end tag, escape, and double-escape states | These are reachable only from the four states above, and they need the appropriate end tag token. |
| 13.2.5.69 to 13.2.5.71 | CDATA section, CDATA section bracket, CDATA section end | These are reachable only when the adjusted current node is not in the HTML namespace (§13.2.4.2). |

`src/html/states.zig` defines `State`, an enum with one tag per section, in section order.
The tag names are snake_case forms of the headings, such as `attribute_value_double_quoted` and `numeric_character_reference_end`.
`section(state)` returns the section number from 1 to 84.
`title(state)` returns the exact heading text.
`implemented(state)` returns whether the frozen subset contains the state.
`owner(state)` returns `"FP-0064"` for an unimplemented state and `null` otherwise.
The headings, in order, are:

Data state; RCDATA state; RAWTEXT state; Script data state; PLAINTEXT state; Tag open state; End tag open state; Tag name state; RCDATA less-than sign state; RCDATA end tag open state; RCDATA end tag name state; RAWTEXT less-than sign state; RAWTEXT end tag open state; RAWTEXT end tag name state; Script data less-than sign state; Script data end tag open state; Script data end tag name state; Script data escape start state; Script data escape start dash state; Script data escaped state; Script data escaped dash state; Script data escaped dash dash state; Script data escaped less-than sign state; Script data escaped end tag open state; Script data escaped end tag name state; Script data double escape start state; Script data double escaped state; Script data double escaped dash state; Script data double escaped dash dash state; Script data double escaped less-than sign state; Script data double escape end state; Before attribute name state; Attribute name state; After attribute name state; Before attribute value state; Attribute value (double-quoted) state; Attribute value (single-quoted) state; Attribute value (unquoted) state; After attribute value (quoted) state; Self-closing start tag state; Bogus comment state; Markup declaration open state; Comment start state; Comment start dash state; Comment state; Comment less-than sign state; Comment less-than sign bang state; Comment less-than sign bang dash state; Comment less-than sign bang dash dash state; Comment end dash state; Comment end state; Comment end bang state; DOCTYPE state; Before DOCTYPE name state; DOCTYPE name state; After DOCTYPE name state; After DOCTYPE public keyword state; Before DOCTYPE public identifier state; DOCTYPE public identifier (double-quoted) state; DOCTYPE public identifier (single-quoted) state; After DOCTYPE public identifier state; Between DOCTYPE public and system identifiers state; After DOCTYPE system keyword state; Before DOCTYPE system identifier state; DOCTYPE system identifier (double-quoted) state; DOCTYPE system identifier (single-quoted) state; After DOCTYPE system identifier state; Bogus DOCTYPE state; CDATA section state; CDATA section bracket state; CDATA section end state; Processing instruction open state; Processing instruction target state; After processing instruction target state; Processing instruction data state; Processing instruction questionable state; Character reference state; Named character reference state; Ambiguous ampersand state; Numeric character reference state; Hexadecimal character reference start state; Hexadecimal character reference state; Decimal character reference state; Numeric character reference end state.

The appropriate end tag token and the last start tag name are used only by unimplemented states, and they belong to `FP-0064`.

### Parse error codes

`src/html/errors.zig` defines `ErrorCode`, an enum with exactly the 52 codes of the §13.2.2 table, in table order.
`name(code)` returns the exact standard text, such as `"eof-in-processing-instruction"`.
The frozen subset raises 49 codes.
It never raises these three:

| Code | Owner task |
| --- | --- |
| `eof-in-cdata` | `FP-0064` |
| `eof-in-script-html-comment-like-text` | `FP-0064` |
| `non-void-html-element-start-tag-with-trailing-solidus` | `FP-0010`, because tree construction acknowledges the self-closing flag |

`raisedByTokenizer(code)` returns `false` for exactly those three codes.

### Input model

The tokenizer consumes decoded UTF-16 code units, which `src/web_string.zig` also uses.
It reads the code units as code points.
A leading surrogate followed immediately by a trailing surrogate is one code point.
Every other surrogate code unit is its own surrogate code point.
Newlines are normalized as Infra "normalize newlines" defines.
A CR LF pair becomes one LF, and any other CR becomes LF.

A chunk boundary never changes the result.
The tokenizer holds a CR at the end of the available input until the next code unit or `finish`.
It holds a leading surrogate at the end of the available input in the same way.
The lookahead states keep their progress across `next` calls:

- the markup declaration open state, for two hyphens, `DOCTYPE`, and `[CDATA[`;
- the after DOCTYPE name state, for six characters;
- the named character reference state, for its longest match and the one character after a match without a semicolon.

The preprocessing errors of §13.2.3.5 are exact:

| Condition | Code |
| --- | --- |
| A surrogate code point | `surrogate-in-input-stream` |
| A noncharacter: U+FDD0 to U+FDEF, or the last two code points of any plane | `noncharacter-in-input-stream` |
| A control other than ASCII whitespace and U+0000, which is U+0001 to U+0008, U+000B, U+000E to U+001F, and U+007F to U+009F | `control-character-in-input-stream` |

A U+FEFF in the code units is an ordinary character, because the decode algorithm already removed any byte order mark.

### Zig interface

`src/html/root.zig` is exported from `src/root.zig` as `html`.

```zig
pub const Tokenizer = struct {
    /// Whether there is an adjusted current node that is not an element in the HTML namespace (§13.2.4.2).
    /// Tree construction sets it before `next`. It defaults to false.
    adjusted_current_node_is_foreign: bool = false,

    pub fn init(gpa: Allocator) Tokenizer;
    pub fn deinit(t: *Tokenizer) void;
    pub fn feed(t: *Tokenizer, chunk: []const u16) Error!void;
    pub fn finish(t: *Tokenizer) Error!void;
    pub fn next(t: *Tokenizer) Error!?Step;
    pub fn unimplementedState(t: *const Tokenizer) ?State;
};
pub const Error = error{ OutOfMemory, UnimplementedState, ChunkPending, InputFinished };
pub const Step = union(enum) { token: Token, parse_error: ParseError, need_input };
pub const Token = struct { kind: Kind, span: Span };
pub const Kind = union(enum) {
    doctype: Doctype,
    start_tag: Tag,
    end_tag: Tag,
    comment: View,
    processing_instruction: ProcessingInstruction,
    characters: View,
    end_of_file,
};
pub const Doctype = struct { name: ?View, public_identifier: ?View, system_identifier: ?View, force_quirks: bool };
pub const Tag = struct { name: View, attributes: []const Attribute, self_closing: bool };
pub const Attribute = struct { name: View, value: View, name_span: Span, value_span: ?Span };
pub const ProcessingInstruction = struct { target: View, data: View };
pub const ParseError = struct { code: ErrorCode, position: Position };
pub const Position = struct { offset: CodeUnitIndex, line: usize, column: usize };
pub const Span = struct { start: Position, end: Position };
```

`View` and `CodeUnitIndex` come from `src/web_string.zig`.
A `null` DOCTYPE field means missing, which differs from an empty view.

The call rules are exact.

- `feed` borrows `chunk` until `next` returns `need_input`, or until `deinit`.
  After returning `need_input`, the tokenizer never reads that chunk again, and it keeps only the input it has not yet decided.
- `feed` while a chunk is borrowed returns `error.ChunkPending`.
  `feed` after `finish` returns `error.InputFinished`.
  Neither error changes any state.
  An empty chunk is valid.
- `finish` marks the end of the input after any borrowed chunk.
  A second `finish` does nothing.
- `next` returns one step.
  It returns `need_input` only before `finish`, when no further step is possible without more input.
  It returns `null` after the end-of-file token.
- After `error.OutOfMemory` or `error.UnimplementedState`, the tokenizer is failed.
  Every later call except `deinit` returns the same error.
- A token's views stay valid until the next call of any method.
- A `characters` token holds one or more code points.
  Adjacent `characters` steps with no step between them are equivalent to their concatenation.
- No step allocates per code point.
  Named reference matching allocates nothing.

The tokenizer starts in the data state.
This task provides no way to start in, or switch to, another state.
When the markup declaration open state matches `[CDATA[` while `adjusted_current_node_is_foreign` is true, the next step would enter the CDATA section state.
In that case `next` returns `error.UnimplementedState`, and `unimplementedState()` returns `.cdata_section`.
While the flag is false, the state takes the `cdata-in-html-content` branch.

The pull interface puts the caller at the parser pause flag boundary of §13.2.1, because the tokenizer emits one token per call.

### Decisions where the standard is silent

Positions.

- An offset counts UTF-16 code units of the original input, before newline normalization.
- A line break is a CR LF pair, a CR not followed by LF, or an LF.
- `line` is 1 plus the number of line breaks that end at or before the offset.
- `column` is 1 plus the number of code units between the end of the last such line break, or the input start, and the offset.
- A code point made from a surrogate pair, or from a CR LF pair, has the offset of its first code unit.
- The end-of-file character has the offset of the input length.

Parse error positions and order.

- A tokenizer parse error has the position of the current input character when the state raises it.
  §13.2.3.5 defines the current input character as the last character consumed.
  For EOF, that is the input length.
  Examples:
  - The markup declaration open state's "anything else" consumes nothing, so its error is at the `!` that the tag open state consumed.
  - The named character reference state's error is at the last matched character.
  - The numeric character reference end state's errors are at the `;` or at the character that is being reconsumed.
- A preprocessing error has the position of its own code point.
  It is reported when the tokenizer first consumes that code point, before any action of that step, because preprocessing precedes tokenization.
- The duplicate attribute check runs when the attribute name state is left.
  Its error has the position of the character whose consumption leaves that state.
  The removed attribute does not appear in the token.
- `end-tag-with-attributes` and `end-tag-with-trailing-solidus` are reported immediately before the end tag token, in that order.
- A numeric character reference value saturates above 0x10FFFF, so it never overflows and still takes the outside-range branch.

Token spans.

- A tag or processing instruction starts at its `<` and ends after the `>` that emits it.
- A comment or DOCTYPE starts at the `<` of its `<!`, `</`, or `<?` and ends after the emitting `>`, or at the input length when EOF emits it.
- A character emitted as itself spans its own code units: two for a surrogate pair or a CR LF pair.
- A U+003C or U+002F emitted by the tag open or end tag open states spans that one source character.
- Code points flushed from a character reference span from the `&` to the offset of the next input character that the return state consumes.
- An attribute name span covers its source characters, including a leading `=` in the `unexpected-equals-sign-before-attribute-name` case.
- A quoted value span covers the text between the quotes.
  An unquoted value span covers the value's characters.
  `value_span` is `null` when the tokenizer never entered an attribute value state for that attribute.
- The end-of-file token spans from the input length to the input length.
- A coalesced run spans from its first start to its last end.

### Canonical dump

`src/html/dump.zig` writes steps as UTF-8 lines, each followed by LF, with no spaces.
It merges adjacent `characters` tokens with no other step between them.
It writes each string as `"` + escaped code units + `"`.
Escaping maps `"` to `\"`, `\` to `\\`, every other code unit from 0x20 to 0x7E to itself, and every other code unit to `\u` followed by four uppercase hex digits.
Each code unit of a surrogate pair is escaped separately.

| Step | Line without spans |
| --- | --- |
| DOCTYPE | `["DOCTYPE",name,public,system,force_quirks]`, with `null` for missing and `true` or `false` |
| Start tag | `["StartTag",name,[[n,v],...],self_closing]` |
| End tag | `["EndTag",name,[[n,v],...],self_closing]` |
| Comment | `["Comment",data]` |
| Processing instruction | `["PI",target,data]` |
| Characters | `["Character",data]` |
| End of file | `["EOF"]` |
| Parse error | `["error",code,line,column,offset]` |

With spans, each token array gains a final element `[start,end]` of offsets.
Each attribute becomes `[n,v,[ns,ne],[vs,ve]]`, or `[n,v,[ns,ne],null]` when `value_span` is `null`.
The token dump is the dump with spans and without error lines.

### Expected-value notation

Inputs use `\0` for U+0000, `\t` for U+0009, `\n` for U+000A, `\f` for U+000C, `\r` for U+000D, and `\uXXXX` for one UTF-16 code unit.
Every other input character is the ASCII character shown.
No `\0` is followed by a digit.
Expected sequences map one to one to the dump without spans:

- `C"x"` is `["Character","x"]`.
- `S"a"[b="c" d=""]` is `["StartTag","a",[["b","c"],["d",""]],false]`, and a trailing `/` sets `true`.
- `E"a"[...]` is the same for `EndTag`.
- `M"x"` is `["Comment","x"]`.
- `P("t","d")` is `["PI","t","d"]`.
- `D(n,p,s,q)` is `["DOCTYPE",...]`, with `-` for `null` and `on` or `off` for `true` or `false`.
- `EOF` is `["EOF"]`.
- `!code@L:C` is `["error","code",L,C,C-1]`.
  Every input in the notation tables is a single line before its last error, so the offset is the column minus 1.
- Strings use the dump escaping.

### Named character references

`src/html/entities.json` holds the unedited bytes of <https://html.spec.whatwg.org/entities.json>.
`src/html/entities.LICENSE` holds the unedited bytes of `LICENSE` from `https://raw.githubusercontent.com/whatwg/html/<commit>/LICENSE`.
`<commit>` is the frozen commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, as integrator amendment 1 states.
That file states the WHATWG copyright, CC BY 4.0, and BSD-3-Clause for portions incorporated into source code.
`src/html/.gitattributes` contains `entities.json -text` and `entities.LICENSE -text`.

`src/html/entities.provenance.json` has `"format": "fairpane-data-provenance"` and `"version": 1`.
Its `data` object records:

- `path`, `url`, `retrieved_at`, `size`, and `sha256`;
- `http_last_modified` and `http_etag`, each a string or `null`;
- `standard_last_updated`, the "Last Updated" date shown by the multipage standard at retrieval.

Its `license` object records `path`, `url`, `commit`, `size`, `sha256`, the `name` `"CC-BY-4.0; BSD-3-Clause for portions incorporated into source code"`, and the `copyright` `"Copyright © WHATWG (Apple, Google, Mozilla, Microsoft)."`.
Its `derived` object names the generator `src/html/entities_gen.zig` and the generated file `src/html/entities_table.zig`.

`src/html/entities_gen.zig` is a first-party build-time program.
`zig build entities-generate` runs it on `entities.json` and writes `src/html/entities_table.zig` through the build system's source-update step, and that file is committed.
The library imports the table by the relative path `entities_table.zig`, as integrator amendment 1 states.
The output is deterministic and sorted by the UTF-16 code units of the name.
The table's observed contents are 2231 names, of which 2125 end with `;` and 106 do not.
93 names map to two code points.
The longest name after `&` is `CounterClockwiseContourIntegral;`, which is 32 code units.

### Laboratory stages

`implemented(stage)` holds for `fetch`, `decode`, and `tokenize`.
The laboratory runs `decode` only when `fetch` completed with `document_state` `loaded`.
It runs `tokenize` only when `decode` completed.
Otherwise each stage is `not-reached`.
The engine document does not tokenize.
The laboratory calls `html.Tokenizer` on the decoded body in one chunk, because no engine parser hook exists before `FP-0010`.
No stage consumes an environment field.

`decode` applies step 1 of the encoding sniffing algorithm, which is BOM sniffing.

| Body begins with | Status | Record |
| --- | --- | --- |
| EF BB BF | `completed` | `encoding` `"UTF-8"`, `confidence` `"certain"`, `bom_bytes` 3, `code_units`, and `output_sha256`. The output is the Encoding Standard decode: the UTF-8 decoder with replacement over the remaining bytes, which `WebString.fromUtf8Lossy` implements. |
| FE FF | `unsupported` | `detail` `"UTF-16BE byte order mark; the UTF-16BE decoder is not implemented"` |
| FF FE | `unsupported` | `detail` `"UTF-16LE byte order mark; the UTF-16LE decoder is not implemented"` |
| Anything else, including an empty body | `unsupported` | `detail` `"no byte order mark; encoding sniffing after BOM sniffing is not implemented"` |

`output_sha256` is the SHA-256 of the decoded code units in little-endian order.
A completed `tokenize` records `token_count`, `tokens_sha256`, and `errors`.
`token_count` is the number of token-dump lines.
`tokens_sha256` is the SHA-256 of the token dump.
`errors` is an array of objects `{code, line, column, offset}` in step order.

A `decode` expectation has `encoding` (`"UTF-8"`, `"UTF-16BE"`, or `"UTF-16LE"`), `confidence` (`"certain"` or `"tentative"`), and `output_sha256`, checked in that order.
A `tokenize` expectation has `token_count`, `tokens_sha256`, and `errors`, checked in that order.
Its `errors` must equal the observed array element by element.
Parsing stays strict.

Outcomes extend FP-0007 with this precedence: `harness-error`, `timeout`, `unsupported`, then `fail` or `pass`.

- A `decode` or `tokenize` expectation whose `decode` stage is `unsupported` reports `unsupported` with `stage` `decode`, `check` `null`, and the decode `detail`.
- A `decode` or `tokenize` expectation for a `failed` document reports `fail` with the expectation's `stage`, `check` `document_state`, `expected` `"loaded"`, and `observed` `"failed"`.
- A tokenizer error during the laboratory run reports `harness-error`.
  The laboratory never sets `adjusted_current_node_is_foreign`, so `UnimplementedState` cannot occur, and `OutOfMemory` is already a harness error.

### Partition harness

`src/html/partition_test.zig` runs each input once as one chunk, which gives the reference dump with spans and errors.
It then runs the input under each partition it receives.
After each chunk it drains `next` to `need_input`, overwrites the chunk buffer with 0xAAAA, and continues.
After the last chunk it calls `finish` and drains to `null`.
Every partition must produce a byte-identical dump.

On a mismatch, the harness reports the input, the failing partition with the fewest chunks, and both dumps.
Ties between partitions go to the lexicographically lowest list of boundary offsets.
The harness also reports the 1-minimal input that `ddmin` finds under the predicate "some partition of the candidate mismatches".
`ddmin` in `src/lab.zig` becomes generic over the element type, and its laboratory callers pass `u8`.

## Exact test cases

Zig cases are named `FP-0008 case N: ...` and run through `zig build test`.
Tokenizer cases live in `src/html/tokenizer_test.zig`, `src/html/partition_test.zig`, and `src/html/entities_test.zig`.
Laboratory cases live in `src/lab.zig`, with fixtures `tests/lab/fp0008-*.json` that `build.zig` lists.
Every expected sequence in cases 4 to 10 must also hold when the input is fed one code unit per chunk.

### Records

1. `State` has 84 tags.
   `section` returns 1 to 84 in order, and `title` equals the frozen heading list.
   `implemented` is true exactly for sections 1, 6 to 8, 32 to 68, and 72 to 84.
   `owner` is `"FP-0064"` exactly for the other 30 sections.
2. `ErrorCode` has 52 tags, and `name` gives the exact §13.2.2 codes in table order.
   `raisedByTokenizer` is false exactly for `eof-in-cdata`, `eof-in-script-html-comment-like-text`, and `non-void-html-element-start-tag-with-trailing-solidus`.
3. The size and SHA-256 of the embedded `entities.json` and `entities.LICENSE` equal the provenance record.
   A test-only `std.json` parse of the embedded `entities.json` equals the generated table, name by name and code point by code point.
   Each `characters` field equals the UTF-16 encoding of its code points.
   The table has 2231 names, 2125 ending in `;`, 106 not ending in `;`, and 93 with two code points.
   Every name matches `[A-Za-z0-9]+;?`.
   These lookups hold:

   | Name | Code points |
   | --- | --- |
   | `amp;` | U+0026 |
   | `AMP` | U+0026 |
   | `not` | U+00AC |
   | `notin;` | U+2209 |
   | `NotEqualTilde;` | U+2242 U+0338 |
   | `fjlig;` | U+0066 U+006A |
   | `ThickSpace;` | U+205F U+200A |
   | `CounterClockwiseContourIntegral;` | U+2233 |

   `notit`, `zz`, and `ampx` match no name, and no name begins with `a;`.

### Error catalog

4. Each input produces exactly the expected sequence.

| Case | Code | Input | Expected |
| --- | --- | --- | --- |
| A1 | abrupt-closing-of-empty-comment | `<!-->` | `!abrupt-closing-of-empty-comment@1:5 M"" EOF` |
| A2 | abrupt-doctype-public-identifier | `<!DOCTYPE a PUBLIC "x>` | `!abrupt-doctype-public-identifier@1:22 D("a","x",-,on) EOF` |
| A3 | abrupt-doctype-system-identifier | `<!DOCTYPE a SYSTEM 'y>` | `!abrupt-doctype-system-identifier@1:22 D("a",-,"y",on) EOF` |
| A4 | absence-of-digits-in-numeric-character-reference | `&#z` | `!absence-of-digits-in-numeric-character-reference@1:3 C"&#z" EOF` |
| A5 | cdata-in-html-content | `<![CDATA[x]]>` | `!cdata-in-html-content@1:9 M"[CDATA[x]]" EOF` |
| A6 | character-reference-outside-unicode-range | `&#x110000;` | `!character-reference-outside-unicode-range@1:10 C"\uFFFD" EOF` |
| A7 | control-character-in-input-stream | `a\u0001` | `C"a" !control-character-in-input-stream@1:2 C"\u0001" EOF` |
| A8 | control-character-reference | `&#x80;` | `!control-character-reference@1:6 C"\u20AC" EOF` |
| A9 | disallowed-processing-instruction-target | `<?XmL?>` | `!disallowed-processing-instruction-target@1:6 M"?XmL?" EOF` |
| A10 | duplicate-attribute | `<a b b>` | `!duplicate-attribute@1:7 S"a"[b=""] EOF` |
| A11 | end-tag-with-attributes | `</a b>` | `!end-tag-with-attributes@1:6 E"a"[b=""] EOF` |
| A12 | end-tag-with-trailing-solidus | `</a/>` | `!end-tag-with-trailing-solidus@1:5 E"a"[]/ EOF` |
| A12b | both end tag errors | `</a b/>` | `!end-tag-with-attributes@1:7 !end-tag-with-trailing-solidus@1:7 E"a"[b=""]/ EOF` |
| A13 | eof-before-tag-name | `<` | `!eof-before-tag-name@1:2 C"<" EOF` |
| A13b | eof-before-tag-name | `</` | `!eof-before-tag-name@1:3 C"</" EOF` |
| A14 | eof-in-comment | `<!--a` | `!eof-in-comment@1:6 M"a" EOF` |
| A15 | eof-in-doctype | `<!DOCTYPE` | `!eof-in-doctype@1:10 D(-,-,-,on) EOF` |
| A16 | eof-in-processing-instruction | `<?a b` | `!eof-in-processing-instruction@1:6 EOF` |
| A17 | eof-in-tag | `<a b='c` | `!eof-in-tag@1:8 EOF` |
| A18 | incorrectly-closed-comment | `<!--a--!>` | `!incorrectly-closed-comment@1:9 M"a" EOF` |
| A19 | incorrectly-opened-comment | `<!x>` | `!incorrectly-opened-comment@1:2 M"x" EOF` |
| A20 | invalid-character-sequence-after-doctype-name | `<!DOCTYPE a b>` | `!invalid-character-sequence-after-doctype-name@1:13 D("a",-,-,on) EOF` |
| A21 | invalid-first-character-of-processing-instruction-target | `<?1>` | `!invalid-first-character-of-processing-instruction-target@1:3 M"?1" EOF` |
| A22 | invalid-first-character-of-tag-name | `<1` | `!invalid-first-character-of-tag-name@1:2 C"<1" EOF` |
| A22b | invalid-first-character-of-tag-name | `</1>` | `!invalid-first-character-of-tag-name@1:3 M"1" EOF` |
| A23 | invalid-processing-instruction-target | `<?a$>` | `!invalid-processing-instruction-target@1:4 M"?a$" EOF` |
| A24 | missing-attribute-value | `<a b=>` | `!missing-attribute-value@1:6 S"a"[b=""] EOF` |
| A25 | missing-doctype-name | `<!DOCTYPE>` | `!missing-doctype-name@1:10 D(-,-,-,on) EOF` |
| A26 | missing-doctype-public-identifier | `<!DOCTYPE a PUBLIC>` | `!missing-doctype-public-identifier@1:19 D("a",-,-,on) EOF` |
| A27 | missing-doctype-system-identifier | `<!DOCTYPE a SYSTEM>` | `!missing-doctype-system-identifier@1:19 D("a",-,-,on) EOF` |
| A28 | missing-end-tag-name | `</>` | `!missing-end-tag-name@1:3 EOF` |
| A29 | missing-quote-before-doctype-public-identifier | `<!DOCTYPE a PUBLIC x>` | `!missing-quote-before-doctype-public-identifier@1:20 D("a",-,-,on) EOF` |
| A30 | missing-quote-before-doctype-system-identifier | `<!DOCTYPE a SYSTEM x>` | `!missing-quote-before-doctype-system-identifier@1:20 D("a",-,-,on) EOF` |
| A31 | missing-semicolon-after-character-reference | `&not` | `!missing-semicolon-after-character-reference@1:4 C"\u00AC" EOF` |
| A32 | missing-whitespace-after-doctype-public-keyword | `<!DOCTYPE a PUBLIC"x">` | `!missing-whitespace-after-doctype-public-keyword@1:19 D("a","x",-,off) EOF` |
| A33 | missing-whitespace-after-doctype-system-keyword | `<!DOCTYPE a SYSTEM"y">` | `!missing-whitespace-after-doctype-system-keyword@1:19 D("a",-,"y",off) EOF` |
| A34 | missing-whitespace-before-doctype-name | `<!DOCTYPEa>` | `!missing-whitespace-before-doctype-name@1:10 D("a",-,-,off) EOF` |
| A35 | missing-whitespace-between-attributes | `<a b="c"d>` | `!missing-whitespace-between-attributes@1:9 S"a"[b="c" d=""] EOF` |
| A36 | missing-whitespace-between-doctype-public-and-system-identifiers | `<!DOCTYPE a PUBLIC "x""y">` | `!missing-whitespace-between-doctype-public-and-system-identifiers@1:23 D("a","x","y",off) EOF` |
| A37 | nested-comment | `<!--<!--x-->` | `!nested-comment@1:9 M"<!--x" EOF` |
| A38 | noncharacter-character-reference | `&#xFFFF;` | `!noncharacter-character-reference@1:8 C"\uFFFF" EOF` |
| A39 | noncharacter-in-input-stream | `\uFFFE` | `!noncharacter-in-input-stream@1:1 C"\uFFFE" EOF` |
| A40 | null-character-reference | `&#0;` | `!null-character-reference@1:4 C"\uFFFD" EOF` |
| A41 | surrogate-character-reference | `&#xD800;` | `!surrogate-character-reference@1:8 C"\uFFFD" EOF` |
| A42 | surrogate-in-input-stream | `\uDC00` | `!surrogate-in-input-stream@1:1 C"\uDC00" EOF` |
| A43 | unexpected-character-after-doctype-system-identifier | `<!DOCTYPE a SYSTEM "y" z>` | `!unexpected-character-after-doctype-system-identifier@1:24 D("a",-,"y",off) EOF` |
| A44 | unexpected-character-in-attribute-name | `<a b"c>` | `!unexpected-character-in-attribute-name@1:5 S"a"["b\"c"=""] EOF` |
| A45 | unexpected-character-in-unquoted-attribute-value | `<a b=c'd>` | `!unexpected-character-in-unquoted-attribute-value@1:7 S"a"[b="c'd"] EOF` |
| A46 | unexpected-equals-sign-before-attribute-name | `<a =b>` | `!unexpected-equals-sign-before-attribute-name@1:4 S"a"["=b"=""] EOF` |
| A47 | unexpected-null-character | `a\0` | `C"a" !unexpected-null-character@1:2 C"\u0000" EOF` |
| A48 | unexpected-solidus-in-tag | `<a / b>` | `!unexpected-solidus-in-tag@1:5 S"a"[b=""] EOF` |
| A49 | unknown-named-character-reference | `&zz;` | `C"&zz" !unknown-named-character-reference@1:4 C";" EOF` |

### State walks

5. Tags and attributes.

| Case | Input | Expected |
| --- | --- | --- |
| T1 | `a<b>c</b>d` | `C"a" S"b"[] C"c" E"b"[] C"d" EOF` |
| T2 | `<A></A>` | `S"a"[] E"a"[] EOF` |
| T3 | `<br/>` | `S"br"[]/ EOF` |
| T4 | `<a b="c"/>` | `S"a"[b="c"]/ EOF` |
| T5 | `<a  >` | `S"a"[] EOF` |
| T6a | `<a` | `!eof-in-tag@1:3 EOF` |
| T6b | `<a ` | `!eof-in-tag@1:4 EOF` |
| T6c | `<a b` | `!eof-in-tag@1:5 EOF` |
| T6d | `<a b ` | `!eof-in-tag@1:6 EOF` |
| T6e | `<a b=` | `!eof-in-tag@1:6 EOF` |
| T6f | `<a b="` | `!eof-in-tag@1:7 EOF` |
| T6g | `<a b="c"` | `!eof-in-tag@1:9 EOF` |
| T6h | `<a b=c` | `!eof-in-tag@1:7 EOF` |
| T6i | `<a/` | `!eof-in-tag@1:4 EOF` |
| T7 | `<Ab\0>` | `!unexpected-null-character@1:4 S"ab\uFFFD"[] EOF` |
| T8 | `<a\tb\nc\fd e>` | `S"a"[b="" c="" d="" e=""] EOF` |
| T9 | `<a B=1 c\0d="2">` | `!unexpected-null-character@1:9 S"a"[b="1" "c\uFFFDd"="2"] EOF` |
| T10 | `<a b =c d /e f >` | `!unexpected-solidus-in-tag@1:12 S"a"[b="c" d="" e="" f=""] EOF` |
| T11 | `<a b= "c" d= 'e' f=>` | `!missing-attribute-value@1:20 S"a"[b="c" d="e" f=""] EOF` |
| T12 | `<a b="&amp;\0" c='&lt;\0'>` | `!unexpected-null-character@1:12 !unexpected-null-character@1:22 S"a"[b="&\uFFFD" c="<\uFFFD"] EOF` |
| T13 | ``<a b=c&amp;d\0e"f'g<h=i`j k=l>`` | ``!unexpected-null-character@1:13 !unexpected-character-in-unquoted-attribute-value@1:15 !unexpected-character-in-unquoted-attribute-value@1:17 !unexpected-character-in-unquoted-attribute-value@1:19 !unexpected-character-in-unquoted-attribute-value@1:21 !unexpected-character-in-unquoted-attribute-value@1:23 S"a"[b="c&d\uFFFDe\"f'g<h=i`j" k="l"] EOF`` |
| T14 | `<a b="c"\t/>` | `S"a"[b="c"]/ EOF` |
| T15 | `<a/b>` | `!unexpected-solidus-in-tag@1:4 S"a"[b=""] EOF` |

6. Markup declarations and comments.

| Case | Input | Expected |
| --- | --- | --- |
| M1 | `<!---->` | `M"" EOF` |
| M2 | `<!--->` | `!abrupt-closing-of-empty-comment@1:6 M"" EOF` |
| M3 | `<!---` | `!eof-in-comment@1:6 M"" EOF` |
| M4 | `<!---a-->` | `M"-a" EOF` |
| M5 | `<!--\0-->` | `!unexpected-null-character@1:5 M"\uFFFD" EOF` |
| M6 | `<!--<<-->` | `M"<<" EOF` |
| M7 | `<!--<a-->` | `M"<a" EOF` |
| M8 | `<!--<!a-->` | `M"<!a" EOF` |
| M9 | `<!--<!-a-->` | `M"<!-a" EOF` |
| M10 | `<!--<!-->` | `M"<!" EOF` |
| M11 | `<!--<!--` | `!eof-in-comment@1:9 M"<!" EOF` |
| M12 | `<!--a-` | `!eof-in-comment@1:7 M"a" EOF` |
| M13 | `<!--a-b-->` | `M"a-b" EOF` |
| M14 | `<!--a--->` | `M"a-" EOF` |
| M15 | `<!--a--` | `!eof-in-comment@1:8 M"a" EOF` |
| M16 | `<!--a--b-->` | `M"a--b" EOF` |
| M17 | `<!--a--!-->` | `M"a--!" EOF` |
| M18 | `<!--a--!` | `!eof-in-comment@1:9 M"a" EOF` |
| M19 | `<!--a--!b-->` | `M"a--!b" EOF` |
| M20 | `<!x` | `!incorrectly-opened-comment@1:2 M"x" EOF` |
| M21 | `</1\0>` | `!invalid-first-character-of-tag-name@1:3 !unexpected-null-character@1:4 M"1\uFFFD" EOF` |
| M22 | `<!-` | `!incorrectly-opened-comment@1:2 M"-" EOF` |
| M23 | `<!DOCTYP` | `!incorrectly-opened-comment@1:2 M"DOCTYP" EOF` |
| M24 | `<![CDATA` | `!incorrectly-opened-comment@1:2 M"[CDATA" EOF` |
| M25 | `<!-x>` | `!incorrectly-opened-comment@1:2 M"-x" EOF` |

7. DOCTYPE.

| Case | Input | Expected |
| --- | --- | --- |
| D1 | `<!DOCTYPE html>` | `D("html",-,-,off) EOF` |
| D2 | `<!doctype  HTML >` | `D("html",-,-,off) EOF` |
| D3 | `<!DOCTYPE \0a\0>` | `!unexpected-null-character@1:11 !unexpected-null-character@1:13 D("\uFFFDa\uFFFD",-,-,off) EOF` |
| D4 | `<!DOCTYPE ` | `!eof-in-doctype@1:11 D(-,-,-,on) EOF` |
| D5 | `<!DOCTYPE a` | `!eof-in-doctype@1:12 D("a",-,-,on) EOF` |
| D6 | `<!DOCTYPE a  ` | `!eof-in-doctype@1:14 D("a",-,-,on) EOF` |
| D7 | `<!DOCTYPE a PUBLI` | `!invalid-character-sequence-after-doctype-name@1:13 D("a",-,-,on) EOF` |
| D8 | `<!DOCTYPE a public'x'>` | `!missing-whitespace-after-doctype-public-keyword@1:19 D("a","x",-,off) EOF` |
| D9 | `<!DOCTYPE a PUBLIC` | `!eof-in-doctype@1:19 D("a",-,-,on) EOF` |
| D10 | `<!DOCTYPE a PUBLICx>` | `!missing-quote-before-doctype-public-identifier@1:19 D("a",-,-,on) EOF` |
| D11 | `<!DOCTYPE a PUBLIC  'x'>` | `D("a","x",-,off) EOF` |
| D12 | `<!DOCTYPE a PUBLIC >` | `!missing-doctype-public-identifier@1:20 D("a",-,-,on) EOF` |
| D13 | `<!DOCTYPE a PUBLIC ` | `!eof-in-doctype@1:20 D("a",-,-,on) EOF` |
| D14 | `<!DOCTYPE a PUBLIC "\0` | `!unexpected-null-character@1:21 !eof-in-doctype@1:22 D("a","\uFFFD",-,on) EOF` |
| D15 | `<!DOCTYPE a PUBLIC '\0x` | `!unexpected-null-character@1:21 !eof-in-doctype@1:23 D("a","\uFFFDx",-,on) EOF` |
| D16 | `<!DOCTYPE a PUBLIC 'x>` | `!abrupt-doctype-public-identifier@1:22 D("a","x",-,on) EOF` |
| D17 | `<!DOCTYPE a PUBLIC "x"` | `!eof-in-doctype@1:23 D("a","x",-,on) EOF` |
| D18 | `<!DOCTYPE a PUBLIC "x"'y'>` | `!missing-whitespace-between-doctype-public-and-system-identifiers@1:23 D("a","x","y",off) EOF` |
| D19 | `<!DOCTYPE a PUBLIC "x"z>` | `!missing-quote-before-doctype-system-identifier@1:23 D("a","x",-,on) EOF` |
| D20 | `<!DOCTYPE a PUBLIC "x" \t"y">` | `D("a","x","y",off) EOF` |
| D21 | `<!DOCTYPE a PUBLIC "x" >` | `D("a","x",-,off) EOF` |
| D22 | `<!DOCTYPE a PUBLIC "x" 'y'>` | `D("a","x","y",off) EOF` |
| D23 | `<!DOCTYPE a PUBLIC "x" ` | `!eof-in-doctype@1:24 D("a","x",-,on) EOF` |
| D24 | `<!DOCTYPE a PUBLIC "x" z>` | `!missing-quote-before-doctype-system-identifier@1:24 D("a","x",-,on) EOF` |
| D25 | `<!DOCTYPE a SYSTEM'y'>` | `!missing-whitespace-after-doctype-system-keyword@1:19 D("a",-,"y",off) EOF` |
| D26 | `<!DOCTYPE a SYSTEM` | `!eof-in-doctype@1:19 D("a",-,-,on) EOF` |
| D27 | `<!DOCTYPE a SYSTEMy>` | `!missing-quote-before-doctype-system-identifier@1:19 D("a",-,-,on) EOF` |
| D28 | `<!DOCTYPE a SYSTEM \t"y">` | `D("a",-,"y",off) EOF` |
| D29 | `<!DOCTYPE a SYSTEM >` | `!missing-doctype-system-identifier@1:20 D("a",-,-,on) EOF` |
| D30 | `<!DOCTYPE a SYSTEM ` | `!eof-in-doctype@1:20 D("a",-,-,on) EOF` |
| D31 | `<!DOCTYPE a SYSTEM "y>` | `!abrupt-doctype-system-identifier@1:22 D("a",-,"y",on) EOF` |
| D32 | `<!DOCTYPE a SYSTEM "\0` | `!unexpected-null-character@1:21 !eof-in-doctype@1:22 D("a",-,"\uFFFD",on) EOF` |
| D33 | `<!DOCTYPE a SYSTEM '\0` | `!unexpected-null-character@1:21 !eof-in-doctype@1:22 D("a",-,"\uFFFD",on) EOF` |
| D34 | `<!DOCTYPE a SYSTEM "y" ` | `!eof-in-doctype@1:24 D("a",-,"y",on) EOF` |
| D35 | `<!DOCTYPE a SYSTEM "y">` | `D("a",-,"y",off) EOF` |
| D36 | `<!DOCTYPE a b\0c>` | `!invalid-character-sequence-after-doctype-name@1:13 !unexpected-null-character@1:14 D("a",-,-,on) EOF` |
| D37 | `<!DOCTYPE a b` | `!invalid-character-sequence-after-doctype-name@1:13 D("a",-,-,on) EOF` |

8. Processing instructions.

| Case | Input | Expected |
| --- | --- | --- |
| PI1 | `<?a>` | `P("a","") EOF` |
| PI2 | `<?_x-1 b c?>` | `P("_x-1","b c") EOF` |
| PI3 | `<?a?b?>` | `P("a","?b") EOF` |
| PI4 | `<?` | `!eof-in-processing-instruction@1:3 EOF` |
| PI5 | `<?ab` | `!eof-in-processing-instruction@1:5 EOF` |
| PI6 | `<?a ?` | `!eof-in-processing-instruction@1:6 EOF` |
| PI7 | `<?a b>` | `P("a","b") EOF` |
| PI8 | `<?xml x?>` | `!disallowed-processing-instruction-target@1:6 M"?xml x?" EOF` |
| PI9 | `<?Xml-Stylesheet>` | `!disallowed-processing-instruction-target@1:17 M"?Xml-Stylesheet" EOF` |
| PI10 | `<?xmlx>` | `P("xmlx","") EOF` |

9. Character references.

| Case | Input | Expected |
| --- | --- | --- |
| R1 | `&amp;&AMP&#65;&#x41;&#X6a;` | `C"&" !missing-semicolon-after-character-reference@1:9 C"&AAj" EOF` |
| R2 | `&#xAbC;&#00000065;&#9;&#13;&#x81;` | `C"\u0ABCA\u0009" !control-character-reference@1:27 C"\u000D" !control-character-reference@1:33 C"\u0081" EOF` |
| R3 | `&#x7`, then 17 `F` characters, then `;&#`, then 11 `9` characters, then `;` (36 code units) | `!character-reference-outside-unicode-range@1:22 C"\uFFFD" !character-reference-outside-unicode-range@1:36 C"\uFFFD" EOF` |
| R4 | `&#xg;&#x41 &#65x&` | `!absence-of-digits-in-numeric-character-reference@1:4 C"&#xg;" !missing-semicolon-after-character-reference@1:11 C"A " !missing-semicolon-after-character-reference@1:16 C"Ax&" EOF` |
| R5 | `<a b="&ampx&amp=&amp" c=&zz; d='&zz'>` | `!missing-semicolon-after-character-reference@1:20 !unknown-named-character-reference@1:28 S"a"[b="&ampx&amp=&" c="&zz;" d="&zz"] EOF` |
| R6 | `&zz &;` | `C"&zz &;" EOF` |
| R7 | `&notin;&notit;&noti` | `C"\u2209" !missing-semicolon-after-character-reference@1:11 C"\u00ACit;" !missing-semicolon-after-character-reference@1:18 C"\u00ACi" EOF` |

10. Input stream preprocessing.

| Case | Input | Expected |
| --- | --- | --- |
| N1 | `a\r\nb\r\rc\r` | `C"a\u000Ab\u000A\u000Ac\u000A" EOF` |
| N2 | `\u0001\u0008\u000B\u000E\u001F\u007F\u0080\u009F\t\n\f ` | `!control-character-in-input-stream@1:1 C"\u0001" !control-character-in-input-stream@1:2 C"\u0008" !control-character-in-input-stream@1:3 C"\u000B" !control-character-in-input-stream@1:4 C"\u000E" !control-character-in-input-stream@1:5 C"\u001F" !control-character-in-input-stream@1:6 C"\u007F" !control-character-in-input-stream@1:7 C"\u0080" !control-character-in-input-stream@1:8 C"\u009F\u0009\u000A\u000C " EOF` |
| N3 | `\uFDCF\uFDD0\uFDEF\uFDF0\uFFFE\uFFFF\uD83F\uDFFF\uDBFF\uDFFE\uDBFF\uDFFF` | `C"\uFDCF" !noncharacter-in-input-stream@1:2 C"\uFDD0" !noncharacter-in-input-stream@1:3 C"\uFDEF\uFDF0" !noncharacter-in-input-stream@1:5 C"\uFFFE" !noncharacter-in-input-stream@1:6 C"\uFFFF" !noncharacter-in-input-stream@1:7 C"\uD83F\uDFFF" !noncharacter-in-input-stream@1:9 C"\uDBFF\uDFFE" !noncharacter-in-input-stream@1:11 C"\uDBFF\uDFFF" EOF` |
| N4 | `\uD800a\uDC00\uD83D\uDE00\uDBFF` | `!surrogate-in-input-stream@1:1 C"\uD800a" !surrogate-in-input-stream@1:3 C"\uDC00\uD83D\uDE00" !surrogate-in-input-stream@1:6 C"\uDBFF" EOF` |
| N5 | `<a\uD800 b="\uDC00"><!--\uD800-->` | `!surrogate-in-input-stream@1:3 !surrogate-in-input-stream@1:8 S"a\uD800"[b="\uDC00"] !surrogate-in-input-stream@1:15 M"\uD800" EOF` |
| N6 | `<a\rb='\r\n'>\r` | `S"a"[b="\u000A"] C"\u000A" EOF`, and the end-of-file token starts at line 4, column 1, offset 11 |

11. Branch coverage.
    In test builds only, the tokenizer counts each executed branch of each implemented state.
    `src/html/states.zig` lists the branches below.
    "Whitespace" means U+0009, U+000A, U+000C, or U+0020.
    One test runs cases 4 to 10 and case 16, and then every counter is nonzero.

| § | Branches |
| --- | --- |
| 1 | `&`; `<`; NULL; EOF; else |
| 6 | `!`; `/`; ASCII alpha; `?`; EOF; else |
| 7 | ASCII alpha; `>`; EOF; else |
| 8 | whitespace; `/`; `>`; ASCII upper alpha; NULL; EOF; else |
| 32 | whitespace; `/` or `>` or EOF; `=`; else |
| 33 | whitespace or `/` or `>` or EOF; `=`; ASCII upper alpha; NULL; `"` or `'` or `<`; else |
| 34 | whitespace; `/`; `=`; `>`; EOF; else |
| 35 | whitespace; `"`; `'`; `>`; else |
| 36 | `"`; `&`; NULL; EOF; else |
| 37 | `'`; `&`; NULL; EOF; else |
| 38 | whitespace; `&`; `>`; NULL; ``"``, `'`, `<`, `=`, or `` ` ``; EOF; else |
| 39 | whitespace; `/`; `>`; EOF; else |
| 40 | `>`; EOF; else |
| 41 | `>`; EOF; NULL; else |
| 42 | two hyphens; `DOCTYPE`; `[CDATA[` with a foreign adjusted current node; `[CDATA[` otherwise; else |
| 43 | `-`; `>`; else |
| 44 | `-`; `>`; EOF; else |
| 45 | `<`; `-`; NULL; EOF; else |
| 46 | `!`; `<`; else |
| 47 | `-`; else |
| 48 | `-`; else |
| 49 | `>` or EOF; else |
| 50 | `-`; EOF; else |
| 51 | `>`; `!`; `-`; EOF; else |
| 52 | `-`; `>`; EOF; else |
| 53 | whitespace; `>`; EOF; else |
| 54 | whitespace; ASCII upper alpha; NULL; `>`; EOF; else |
| 55 | whitespace; `>`; ASCII upper alpha; NULL; EOF; else |
| 56 | whitespace; `>`; EOF; else with `PUBLIC`; else with `SYSTEM`; else otherwise |
| 57, 63 | whitespace; `"`; `'`; `>`; EOF; else |
| 58, 64 | whitespace; `"`; `'`; `>`; EOF; else |
| 59, 65 | `"`; NULL; `>`; EOF; else |
| 60, 66 | `'`; NULL; `>`; EOF; else |
| 61, 62 | whitespace; `>`; `"`; `'`; EOF; else |
| 67 | whitespace; `>`; EOF; else |
| 68 | `>`; NULL; EOF; else |
| 72 | ASCII alpha or `_`; EOF; else |
| 73 | terminator with a disallowed target; terminator with another target; ASCII alphanumeric, `-`, or `_`; EOF; else |
| 74 | whitespace; else |
| 75 | `?`; `>`; EOF; else |
| 76 | `>`; EOF; else |
| 77 | ASCII alphanumeric; `#`; else |
| 78 | match under the historical attribute rule; match ending with `;`; other match without `;`; no match |
| 79 | ASCII alphanumeric in an attribute; ASCII alphanumeric otherwise; `;`; else |
| 80 | `x` or `X`; ASCII digit; else |
| 81 | ASCII hex digit; else |
| 82 | ASCII digit; ASCII upper hex digit; ASCII lower hex digit; `;`; else |
| 83 | ASCII digit; `;`; else |
| 84 | 0x00; above 0x10FFFF; surrogate; noncharacter; control or 0x0D found in the table; control or 0x0D not in the table; no error |

### Source positions

12. Each input produces exactly this dump with spans and errors.

- S1, input `ab<c d="e">&amp;f<!--g--><?h i?>&#x41\r\n<!DOCTYPE j>` (51 code units):

  ```text
  ["Character","ab",[0,2]]
  ["StartTag","c",[["d","e",[5,6],[8,9]]],false,[2,11]]
  ["Character","&f",[11,17]]
  ["Comment","g",[17,25]]
  ["PI","h","i",[25,32]]
  ["error","missing-semicolon-after-character-reference",1,38,37]
  ["Character","A\u000A",[32,39]]
  ["DOCTYPE","j",null,null,false,[39,51]]
  ["EOF",[51,51]]
  ```

  The DOCTYPE token starts at line 2, column 1, and the end-of-file token is at line 2, column 13.

- S2, input `<x a b='' c=d e = "f">`:

  ```text
  ["StartTag","x",[["a","",[3,4],null],["b","",[5,6],[8,8]],["c","d",[10,11],[12,13]],["e","f",[14,15],[19,20]]],false,[0,22]]
  ["EOF",[22,22]]
  ```

- S3: input `<!--a` gives `["error","eof-in-comment",1,6,5]`, `["Comment","a",[0,5]]`, and `["EOF",[5,5]]`.
  Input `<!DOCTYPE` gives `["error","eof-in-doctype",1,10,9]`, `["DOCTYPE",null,null,null,true,[0,9]]`, and `["EOF",[9,9]]`.

- S4, input `\n\r\n\r<a\0>`:

  ```text
  ["Character","\u000A\u000A\u000A",[0,4]]
  ["error","unexpected-null-character",4,3,6]
  ["StartTag","a\uFFFD",[],false,[4,8]]
  ["EOF",[8,8]]
  ```

  The end-of-file token is at line 4, column 5.

- S5, input `<a b=&lt; b=c>`:

  ```text
  ["error","duplicate-attribute",1,12,11]
  ["StartTag","a",[["b","<",[3,4],[5,9]]],false,[0,14]]
  ["EOF",[14,14]]
  ```

- S6, input `<1</`:

  ```text
  ["error","invalid-first-character-of-tag-name",1,2,1]
  ["Character","<1",[0,2]]
  ["error","eof-before-tag-name",1,5,4]
  ["Character","</",[2,4]]
  ["EOF",[4,4]]
  ```

### Partitions and continuation

13. Partition comparison through the harness.
    Set P uses every composition into nonempty chunks, which is 2^(n-1) partitions for n code units.

| Case | Input | Units | Expected |
| --- | --- | --- | --- |
| P1 | `a\r\nb\r\rc\r` | 8 | N1 |
| P2 | `\uD800a\uDC00\uD83D\uDE00\uDBFF` | 6 | N4 |
| P3 | `\uFDD0\uD83F\uDFFE\u0001\u007F\u0000` | 6 | `!noncharacter-in-input-stream@1:1 C"\uFDD0" !noncharacter-in-input-stream@1:2 C"\uD83F\uDFFE" !control-character-in-input-stream@1:4 C"\u0001" !control-character-in-input-stream@1:5 C"\u007F" !unexpected-null-character@1:6 C"\u0000" EOF` |
| P4 | `<!DOCTYPE html>` | 15 | D1 |
| P5 | `<!--a--!>` | 9 | A18 |
| P6 | `<!-x>` | 5 | M25 |
| P7 | `&notin;&notit;` | 14 | `C"\u2209" !missing-semicolon-after-character-reference@1:11 C"\u00ACit;" EOF` |
| P8 | `<a b="&ampx&lt">` | 16 | `!missing-semicolon-after-character-reference@1:14 S"a"[b="&ampx<"] EOF` |
| P9 | `&#x110000;&#0;` | 14 | `!character-reference-outside-unicode-range@1:10 C"\uFFFD" !null-character-reference@1:14 C"\uFFFD" EOF` |
| P10 | `<?xml x?><?a?b>` | 15 | `!disallowed-processing-instruction-target@1:6 M"?xml x?" P("a","?b") EOF` |
| P11 | `<a b c=d b=e/>` | 14 | `!duplicate-attribute@1:11 S"a"[b="" c="d"] EOF` |
| P12 | `</a b></a/>` | 11 | `!end-tag-with-attributes@1:6 E"a"[b=""] !end-tag-with-trailing-solidus@1:11 E"a"[]/ EOF` |
| P13 | `<a b='c` | 7 | A17 |
| P14 | `&;&#;&#x;&a;` | 12 | `C"&;" !absence-of-digits-in-numeric-character-reference@1:5 C"&#;" !absence-of-digits-in-numeric-character-reference@1:9 C"&#x;&a" !unknown-named-character-reference@1:12 C";" EOF` |
| P15 | `x&notin` | 7 | `C"x" !missing-semicolon-after-character-reference@1:5 C"\u00ACin" EOF` |
| P16 | `&#X41;&#65` | 10 | `C"A" !missing-semicolon-after-character-reference@1:11 C"A" EOF` |
| P17 | `&#x80;&#xFFFE;` | 14 | `!control-character-reference@1:6 C"\u20AC" !noncharacter-character-reference@1:14 C"\uFFFE" EOF` |
| P18 | `&#xD800;&#13;` | 13 | `!surrogate-character-reference@1:8 C"\uFFFD" !control-character-reference@1:13 C"\u000D" EOF` |
| P19 | `<!--<!-- -->` | 12 | `!nested-comment@1:9 M"<!-- " EOF` |
| P20 | `<A B=C>&lt` | 10 | `S"a"[b="C"] !missing-semicolon-after-character-reference@1:10 C"<" EOF` |
| P21 | `<a\rb='\r\n'>\r` | 11 | N6 |
| P22 | `<!DOCTYP` | 8 | M23 |

    Set B uses every partition into one, two, or three nonempty chunks.
    It covers D7, D20, T13, R3, R5, N2, N3, S1, and these inputs:

| Case | Input | Expected |
| --- | --- | --- |
| B1 | `<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">` | `D("html","-//W3C//DTD HTML 4.01//EN","http://www.w3.org/TR/html4/strict.dtd",off) EOF` |
| B2 | `&NotEqualTilde;&CounterClockwiseContourIntegral;&CounterClockwiseContourIntegralx` | `C"\u2242\u0338\u2233&CounterClockwiseContourIntegralx" EOF` |
| B3 | `<p title="a&amp;b" data-x=1 hidden>text&copy 2026</p>` | `S"p"[title="a&b" data-x="1" hidden=""] C"text" !missing-semicolon-after-character-reference@1:44 C"\u00A9 2026" E"p"[] EOF` |
| B4 | `<!--a--><!--b--!><!----><?pi d?><x y='z'/>` | `M"a" !incorrectly-closed-comment@1:17 M"b" M"" P("pi","d") S"x"[y="z"]/ EOF` |

14. Mismatch report.
    On input `a\r\nb\r\n` with the injected predicate "the candidate contains U+000D followed by U+000A", the reported minimal input is `\r\n`.
    On a six-unit input with the injected partition predicate "a boundary at offset 4", the reported partition is the two chunks `[0,4)` and `[4,6)`.
    The laboratory's FP-0007 case 11 still passes through the generic `ddmin`.

15. Interface edges.
    - `next` before any `feed` returns `need_input`.
    - `finish` with no input yields only `["EOF",[0,0]]` at line 1, column 1.
    - Feeding an empty chunk between the chunks `<a` and `>` changes no dump.
    - A second `feed` before `need_input` returns `error.ChunkPending`, and the dump is unchanged.
    - `feed` after `finish` returns `error.InputFinished`.
    - A second `finish` does nothing.
    - `next` after the end-of-file token returns `null` twice.
    - `next` after `need_input`, without new input, returns `need_input` again.

16. Unimplemented state.
    With `adjusted_current_node_is_foreign` true, input `<![CDATA[x]]>` makes the first `next` after `finish` return `error.UnimplementedState`, and `unimplementedState()` returns `.cdata_section`.
    The same holds when the input arrives as `<![CDA` and `TA[x]]>`, where the first chunk gives `need_input`.
    Later `next`, `feed`, and `finish` calls return `error.UnimplementedState`.
    With the flag false, the same input gives A5.

17. `std.testing.checkAllAllocationFailures` tokenizes `<!DOCTYPE html><a b="&amp;c">x&notin;<!--d--><?e f?>` in three chunks split at offsets 7 and 23.
    Each induced failure returns `error.OutOfMemory`, every later call returns it again, and nothing leaks.

### Laboratory

The UTF-8 bytes `<!DOCTYPE html><p class=x>a&amp;b</p>` form `L_BODY`.

18. `fp0008-tokenize-pass.json` has the body EF BB BF + `L_BODY` and a matching `tokenize` expectation.
    The result is `pass`.
    `decode` is `completed` with `"UTF-8"`, `"certain"`, `bom_bytes` 3, `code_units` 37, and the SHA-256 of the 74-byte UTF-16LE encoding.
    `tokenize` is `completed` with `token_count` 5, empty `errors`, and the SHA-256 of exactly this token dump:

    ```text
    ["DOCTYPE","html",null,null,false,[0,15]]
    ["StartTag","p",[["class","x",[18,23],[24,25]]],false,[15,26]]
    ["Character","a&b",[26,33]]
    ["EndTag","p",[],false,[33,37]]
    ["EOF",[37,37]]
    ```

19. Variants of case 18 report `fail`:
    - `token_count` 4 reports `check` `token_count` with 4 and 5.
    - A `tokens_sha256` of 64 zeros reports `check` `tokens_sha256`.
    - An `errors` value of `[{"code":"eof-in-tag","line":1,"column":1,"offset":0}]` reports `check` `errors`.
20. `fp0008-tokenize-errors.json` has the body EF BB BF + `<a b=c'd>&notit;` and reports `pass`.
    `errors` is `[{"code":"unexpected-character-in-unquoted-attribute-value","line":1,"column":7,"offset":6},{"code":"missing-semicolon-after-character-reference","line":1,"column":13,"offset":12}]`.
    `token_count` is 3, and the token dump is:

    ```text
    ["StartTag","a",[["b","c'd",[3,4],[5,8]]],false,[0,9]]
    ["Character","\u00ACit;",[9,16]]
    ["EOF",[16,16]]
    ```

21. The `tokenize` expectation of case 18 with the body `<p>` reports `unsupported`, `stage` `decode`, and the "no byte order mark" detail.
    `decode` is `unsupported`, and `tokenize` is `not-reached`.
    A `decode` expectation with the body FF FE 3C 00 reports the UTF-16LE detail.
    The body FE FF 00 3C reports the UTF-16BE detail.
22. A `null` document body with a `tokenize` expectation reports `fail` with `stage` `tokenize`, `check` `document_state`, `"loaded"`, and `"failed"`.
    Both new stages are `not-reached`.
23. A `decode` expectation for the case 18 body reports `pass`.
    The same expectation with `encoding` `"UTF-16LE"` reports `fail` with `check` `encoding`.
24. The body EF BB BF 61 FF 62 with `token_count` 2 and the token dump `["Character","a\uFFFDb",[0,3]]` followed by `["EOF",[3,3]]` reports `pass`, and `decode` records `code_units` 3.
25. FP-0007 case 2 now asserts:
    - `fetch` is `completed`, because its body has no BOM;
    - `decode` is `unsupported`;
    - `tokenize` is `not-reached`;
    - every other stage is `unsupported`.

    FP-0007 cases 4 and 7 pass unchanged.
26. `fairpane-lab run` exits with status 0 for case 18, 1 for the `token_count` variant of case 19, and 2 for the `<p>` case of case 21.

### Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Implement a frozen subset of specified tokenizer states completely | 1, 3 to 11, and 16 |
| Compare whole-input results with every partition of small adversarial inputs | 13 and 14, and the one-unit chunking of cases 4 to 10 |
| Preserve source positions and recovery outcomes | 4 to 10, 12, and 18 to 24 |
| Record every unimplemented tokenizer state for subsequent tasks | 1, 2, and 16, and the evidence README |

### Stop rules

If a frozen expected value contradicts the cited state text, stop and report the input, the expected and observed values, and the spec branch to the integrator.
If the entity counts differ from 2231, 106, and 93, stop and report the observed counts.
If the published standard's tokenization headings differ from the frozen list, stop and report the difference.
Never edit an expectation, an input, or an upstream byte to pass a case.

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0008/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, and keep each failed attempt as its own log.

1. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0008-cache-before` at the base.
2. Record `entities-fetch.log`, with the download of `entities.json`, its response headers, and its exit status.
3. Record `license-fetch.log`, with the `LICENSE` download from whatwg/html at the frozen commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`.
4. Record `entities-digest.log`, with GNU `sha256sum` and the byte sizes of both files.
5. Record an uncached `tests-after.log` with `zig build test --summary all --cache-dir out/fp0008-cache-after`.
6. Write `engineering/evidence/FP-0008/README.md`.
   It lists the recorded digests, the 30 unimplemented states, and the three unraised codes, each with its owner task, and every stop-rule observation.

The mutation control makes the preprocessor turn a CR at the end of the available input into LF immediately, without waiting for the next code unit.
Store its exact diff in `mutation-pending-cr.diff` beside its log.
The control must fail case 13 on input P1.
The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0008/gates`.

## Authority

Writable paths: `src`, `tests`, `build.zig`, and `engineering/evidence/FP-0008/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
Network access occurs only in the recorded fetches of evidence items 2 and 3.
Required reviewer: `fairpane-review`.

## Non-goals

- The 30 unimplemented states, the appropriate end tag token, the last start tag name, and state switches by tree construction belong to `FP-0064`.
- Tree construction, self-closing acknowledgement, DOM node creation through `src/dom.zig`, and parsing in the engine's document load belong to `FP-0010`.
- The insertion point, `document.write`, the script-created parser's explicit EOF, the script nesting level, and the parser pause flag belong to `FP-0019`.
- Encoding sniffing after BOM sniffing belongs to `FP-0065`. That includes the prescan, transport-layer encodings, defaults, UTF-16 and legacy decoders, and changing the encoding.
- No fragment parsing, speculative parsing, SIMD path, C ABI change, `api` change, or `include` change exists in this task.
- No WPT item runs.
  The pinned tree contains no html5lib tokenizer test files.
  Its html5lib material is the following:
  - tree-construction `.dat` files under `html/syntax/parsing/resources/`, run by the testharness tests `html5lib_url.html` (61 variants), `html5lib_write.html`, and `html5lib_write_single.html`;
  - the vendored Python library `tools/third_party/html5lib/`, whose `html5lib/tests/testdata` submodule has no files in the tree;
  - two Sanitizer API files.

  The `.dat` files need tree construction, a DOM, and script, and they record only error counts.
  The testharness tests under `html/syntax/parsing/` that observe tokenization need `FP-0010` and `FP-0019`.
- No `specs` file, threshold, gate, or corpus pin changes in this task.

## Specification ambiguities

- The §13.2.5 introduction lists the token types as DOCTYPE, start tag, end tag, comment, character, and end-of-file. It omits the processing-instruction token, although states 13.2.5.73 to 13.2.5.76 create and emit one and §13.2.6 handles it. This contract adds a `processing_instruction` token kind.
- At EOF, the processing instruction open state (13.2.5.72) emits no `<` or `?` characters, unlike the tag open state. This contract follows the text as written.
- The standard defines no source position for a parse error. This contract uses the current input character from §13.2.3.5: the last character consumed, with EOF at the end of the input.
- The standard does not say when an input-stream error is reported. This contract reports it when the character is first consumed, before any tokenizer action on that character, because preprocessing comes before tokenization.
- The order is unspecified when an end tag has both attributes and a trailing solidus. This contract reports `end-tag-with-attributes` first.
- Numeric character reference arithmetic is unbounded in the standard. This contract saturates above 0x10FFFF, which gives the same outcome.
- In the named character reference state, a temporary buffer holds the characters consumed while searching for a match. When nothing matches, this contract treats only `&` as consumed. The observable outcome is identical either way.

## Integrator amendment 1

On 2026-10-09 the worker `FP0008Html` reported that the frozen build import `html_entities` fails `repo-check`.
The repository's import lint admits only `std`, `builtin`, and `root` as named imports under `src` (`engineering/dependencies.json` and `tools/lib.mjs`), and changing that list is a policy change outside this task.
The integrator therefore replaces the build import with a committed generated file, as `src/unicode/tables.zig` already is.

- `src/html/entities_gen.zig` generates `src/html/entities_table.zig`, and `zig build entities-generate` writes it into the source tree.
- The committed file is imported by its relative path, and no build step adds a named import for it.
- Case 3's test-only `std.json` parse of the embedded `entities.json` must equal the committed table, so a stale table fails the tests.
- The provenance record's `derived` object names the generated file instead of a build import.
- `entities.LICENSE` comes from the frozen commit `efc54f7b70858d9fcf06d1a5871ae215f448c029`, which evidence item 3 already names; the behavior text that named the `main` commit at import time contradicted it.
