# FP-0082 task contract

## Identity

Task ID: `FP-0082`, "Parse a bounded script grammar with sound syntax-error accounting".
Workstream: `javascript`.
Base: the commit that freezes this contract; at drafting time, `HEAD` was `f90350b`.
Prerequisites: `FP-0011` and `FP-0003`, accepted.
The `fairpane-js` worker `FP0012Contract` drafted this contract as the first part of the `FP-0012` split, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-js`.
Authority: `routine-local-engineering`.

### Integrator decisions

- `FP-0012` is split into `FP-0082`, `FP-0083`, `FP-0084`, and `FP-0085`.
  `FP-0012` keeps its seven criteria word for word as the closing task.
  The integrator landed the plan entries in `1409e8b` and the dependency fix that plan review 1 required in `789ad50`.
  Plan review 1, `engineering/evidence/plan/reviews/review-1-reject.json`, approved `FP-0012` criteria 6 and 7 at their current text as the independent approval that `FP-0011` review 2 requested.
  Plan review 2, `engineering/evidence/plan/reviews/review-2-approve.json`, approved the dependency fix.
- The parser reads UTF-16 code units and treats them as code points, as ECMA-262 section 11.1 does.
  A host decodes a UTF-8 file with `web_string.WebString.fromUtf8`.
  Invalid UTF-8 is an input error, never a syntax error.
- The normative baseline is the ECMA-262 draft at <https://tc39.es/ecma262/>, retrieved 2026-10-09, with Annex B, because Fairpane is a web browser.
  Where a reference engine disagrees with that text, the text governs.
- Identifiers are limited to ASCII code points until `FP-0095` imports ID_Start and ID_Continue through `FP-0055`.
- The census is a parse-only soundness check.
  It executes no test and is not a Test262 result.
  `specs/applicability/test262.json` stays unchanged.
- A Test262 file that names a feature from the "Proposed language features" section of the pinned `features.txt` is a proposal test.
  Its census mismatches are reported and are not violations, because the parser targets ECMA-262, not proposals.
- Each unsupported code names the plan task that owns it: `FP-0086` through `FP-0097`.
- The depth limit is an honest `limit` outcome, and its stack use is measured, not inferred.
  The engine runs on the embedder's thread, and a Windows main thread has a 1 MiB stack, so the deepest accepted inputs must parse within 1 MiB.
  Case 10 runs on a thread that the test spawns with a 1 MiB stack.
- `corpus-extract` writes under `out/`, a declared local build directory, and `FP-0084` reuses its output.
- The integrator accepts the proposal-feature rule above, and `@` stays an `invalid_character`.

## Sources

- ECMA-262 draft, retrieved 2026-10-09, multipage edition <https://tc39.es/ecma262/multipage/>.
  This contract cites section numbers as that edition's table of contents gives them.
  - 5.1.4 The Syntactic Grammar; 6.2.5 Reference Records; 8.2 Scope Analysis; 8.3 Labels; 8.6.4 AssignmentTargetType.
  - 10.2.11 FunctionDeclarationInstantiation; 10.4.4 Arguments exotic objects.
  - 11.1 Source Text; 11.1.4 CodePointAt; 11.2.1 Directive Prologues and the Use Strict Directive; 11.2.2 Strict Mode Code.
  - 12.1 through 12.10, the lexical grammar, including 12.9.3.1 and 12.9.4.1 early errors and 12.10 automatic semicolon insertion.
  - 13.1 through 13.16, the expressions, including 13.2.5.1, 13.3.1.1, 13.4.1, 13.5.1.1, and 13.15.1 early errors.
  - 14.1 through 14.16, the statements, including 14.2, 14.3.1, 14.3.2, 14.6.1, 14.7.2.1, 14.7.3.1, 14.7.4.1, 14.8.1, 14.9.1, 14.11.1, 14.13.1, 14.13.2, and 14.15.1.
  - 15.1 Parameter Lists, 15.2 Function Definitions, and 15.3 through 15.9 as the owners of unsupported forms.
  - 16.1 Scripts, 16.1.1 Early Errors, and 16.1.7 GlobalDeclarationInstantiation.
  - Annex B.1.1 HTML-like Comments, B.3.1 through B.3.5, and B.3.9 Runtime Errors for Function Call Assignment Targets.
- Test262 at commit `2e0a56762801e275a9fdf96dc49d90ba0cddcf63`, pinned in `specs/corpora.json` and recorded in `specs/snapshots/test262.json`.
  - `INTERPRETING.md`, "Strict Mode": the strict run prefixes `"use strict";` followed by U+000A.
  - `INTERPRETING.md`, "Metadata": `negative`, `flags`, `features`, and `includes`.
  - `features.txt`: the "Proposed language features" section.
  - Harness blobs: `harness/assert.js` `55a0e2a32f2e6259a1b445a9d924f61261e2ca5f`, `harness/sta.js` `d291a94f46234908009a7ee909cf9d66034c73fe`, `harness/doneprintHandle.js` `334d19ec8ee58664502afb232bce3c1a74acfb16`, `harness/compareArray.js` `fa5eae5f4c7c60d6178ef992fe8c2e1dd0c394f3`, and `harness/propertyHelper.js` `0acccfe87f0c40c94c1d43c315c2d8f1e35d7b52`.
  - `tools/corpus.mjs`, `TEST262_RULE`: the discovery rule, which gives 53,616 discovered files.
- `src/js/number.zig` `stringToNumber` and `toString` from `FP-0011`, and `src/web_string.zig`.
- `docs/JAVASCRIPT_RUNTIME.md`, `docs/QUALIFICATION.md`, and `engineering/decisions/0008-javascript-values-and-heap.md`.

### Observed facts that shaped the decisions

These facts come from the drafter's reads and probes on 2026-10-09.
None of them is a test input.

- Section 8.6.4 returns `web-compat` for a call-expression assignment target only in non-strict code, so a strict target is invalid.
  Node v26.7.0 accepts `"use strict"; f() = 1;`, `"use strict"; f()++;`, and `"use strict"; f() += 1;`.
  This contract follows the spec text.
- Of the 231 drafted sources, Node v26.7.0 disagreed with this contract's validity only on those three and on `using x = y;`, which is an unsupported row.
  The drafter's Node run is not evidence; evidence item 5 records it.
- `harness/assert.js`, `sta.js`, `doneprintHandle.js`, and `compareArray.js` use only the supported subset.
  `harness/propertyHelper.js` uses array literals, for-in, and `arguments`.
- The pinned tree has 53,974 blobs under `test/` and `harness/`, all of mode 100644.
  It has 53,616 discovered test files.
- The drafter's regular-expression scan of the frontmatter found 843 files flagged `module`, 4,660 negative-parse files, and 181 files with block-style flags.
- `src/js/value.zig` case 20 searches a fixed list of `src/js` files for `export `, `callconv(`, `extern struct`, and `extern union`.

## Behavior

### Files

| File | Content |
| --- | --- |
| `src/js/lexer.zig` | Goal-driven tokenizer over UTF-16 code units. |
| `src/js/ast.zig` | Syntax tree nodes, function records, declaration lists, and the dump writer. |
| `src/js/parser.zig` | `parseScript`, early errors, the unsupported and syntax-error code tables, and detection order. |
| `src/js/test262_metadata.zig` | The Test262 frontmatter reader. |
| `src/js/parse_census.zig` | The census over an extracted Test262 tree. |
| `src/js/parse_main.zig` | The `fairpane-js-parse` executable root. |
| `src/js/runtime.zig` | Its `test` block references the new files. |
| `src/js/value.zig` | Case 20 lists the new files. |
| `build.zig` | The `js-tools` step installs `fairpane-js-parse`, and `zig build test` runs the command-line and census fixture cases. |
| `tests/js/parse/*` | Command-line fixtures. |
| `tests/js/census/sound/` and `tests/js/census/unsound/` | Census fixture trees. |
| `tools/corpus.mjs`, `tools/fairpane.mjs`, `tools/selftest.mjs` | The `corpus-extract` command and its controller tests. |

The executable follows the `measure` pattern of `build.zig`: its root sits beside a copy of `src`.
No new file under `src/js` contains `export `, `callconv(`, `extern struct`, or `extern union`.
Test sources that need the keyword `export` build it by concatenation, for example `"ex" ++ "port var a;"`, as `value.zig` does.
The task changes no file under `include` or `api`, and it changes neither `src/c_api.zig` nor `src/abi_generated.zig`.

### Interface

The text formats in this contract are normative.
The Zig names below are the intended shape, and the worker may refine them without changing behavior.

```zig
pub const Options = struct {
    max_depth: u32 = 1024,
    max_memory_bytes: usize = 256 * 1024 * 1024,
    max_source_units: u32 = std.math.maxInt(u32),
};
pub const Diagnostic = union(enum) {
    syntax_error: struct { code: SyntaxErrorCode, offset: u32 },
    unsupported: struct { code: UnsupportedCode, offset: u32 },
    limit: struct { code: LimitCode, offset: u32 },
};
pub const Parse = struct {
    arena: std.heap.ArenaAllocator,
    outcome: union(enum) { script: *const ast.Script, diagnostic: Diagnostic },
    pub fn deinit(parse: *Parse) void;
};
pub fn parseScript(gpa: Allocator, source: []const u16, options: Options) error{OutOfMemory}!Parse;
pub fn writeOutcome(parse: *const Parse, writer: *std.Io.Writer) std.Io.Writer.Error!void;
pub fn writeCodeTable(writer: *std.Io.Writer) std.Io.Writer.Error!void;
```

`error.OutOfMemory` means that `gpa` failed.
Exceeding `max_memory_bytes` instead produces the outcome `limit memory`.
A source longer than `max_source_units` produces `limit source_length` at offset 0.
Every offset is a code-unit index into `source`.

`writeOutcome` writes one line without a terminator:

- the syntax-tree dump for a script;
- `syntax-error <code> @<offset>`;
- `unsupported <code> @<offset>`;
- `limit <code> @<offset>`.

### Soundness rule

A `syntax-error` outcome asserts that ParseText(source, Script) under ECMA-262 with Annex B returns a list of errors.
An `unsupported` outcome asserts nothing about validity.
At every point where the full grammar admits a production outside the subset, the parser reports `unsupported` and never `syntax-error`.
When the parser cannot decide whether a construct is valid, it reports `unsupported`.

### Detection order

The outcome is the first diagnostic in detection order.

1. Token-level and grammar diagnostics are detected at the token where they arise, in source order.
2. Unsupported productions are detected at their trigger token, as the unsupported table lists.
3. Early errors that need one complete production are detected when that production completes.
   Examples are assignment targets, duplicate `__proto__`, cover-initialized names, labels, and break and continue targets.
4. A Use Strict Directive in a function body triggers the retroactive strict checks when the directive statement completes.
   These checks cover earlier directive strings, the function's name, and its parameters, and they report at the offending token.
5. `arguments_object` is detected when the function body completes.
6. A depth, memory, or source-length limit is detected as soon as it is exceeded.

### Supported grammar subset

The goal symbol is Script (16.1).
The parser accepts exactly the following.
Every other production of ECMA-262 that can begin at a token is reported through the unsupported table, or through a syntax error where that table says so.

| Area | Supported forms | Sections |
| --- | --- | --- |
| Source text | UTF-16 code units read as code points; a lone surrogate is its own code point. | 11.1, 11.1.4 |
| White space | TAB, VT, FF, ZWNBSP (U+FEFF), SP, NBSP, U+1680, U+2000 through U+200A, U+202F, U+205F, U+3000. These are the `Zs` members of Unicode 18.0.0 that `FP-0011` recorded. | 12.1, 12.2 |
| Line terminators | LF, CR, LS, PS; CR LF is one sequence. | 12.3 |
| Comments | `//` and `/* */`. A multi-line comment that contains a line terminator counts as a line terminator for 12.10. | 12.4 |
| Hashbang | `#!` at offset 0 only. | 12.5 |
| HTML-like comments | `<!--` anywhere. `-->` at the start of input, or after a line terminator sequence followed by optional white space and optional single-line delimited comments, or after a multi-line comment that contains a line terminator. | B.1.1 |
| Tokens | Every punctuator of 12.8, including those that only begin unsupported productions, so that they can be reported. `?.` is a punctuator only when no decimal digit follows. | 12.6, 12.8 |
| Identifier names | ASCII `IdentifierStart` and `IdentifierPart`, raw or written as `\uXXXX` or `\u{...}` escapes. A reserved word written with escapes is never a keyword. | 12.7.1, 12.7.2 |
| Literals | `null`, `true`, `false`. NumericLiteral as DecimalLiteral, NonDecimalIntegerLiteral (`0x`, `0o`, `0b`), LegacyOctalIntegerLiteral, NonOctalDecimalIntegerLiteral, and NumericLiteralSeparator. StringLiteral with every escape, including LegacyOctalEscapeSequence, NonOctalDecimalEscapeSequence, LineContinuation, and raw LS and PS. | 12.9.1 to 12.9.4 |
| Semicolon insertion | All three rules and every restricted production. Nothing is inserted inside a `for` header, and an empty statement is never inserted. The `do`-`while` rule applies. | 12.10 |
| Primary expressions | `this`, IdentifierReference, literals, ObjectLiteral, FunctionExpression, ParenthesizedExpression | 13.1, 13.2.1 to 13.2.3, 13.2.5, 13.2.6, 13.2.9 |
| Object literals | Shorthand IdentifierReference; `PropertyName : AssignmentExpression` with IdentifierName, StringLiteral, NumericLiteral, or ComputedPropertyName keys; trailing comma; the `__proto__` setter form. | 13.2.5 |
| Left-hand side | `.IdentifierName`, `[Expression]`, `new` with and without Arguments, calls, Arguments with a trailing comma | 13.3.2, 13.3.5, 13.3.6, 13.3.8 |
| Operators | Update, unary (`delete void typeof + - ~ !`), `**`, multiplicative, additive, shift, relational with `instanceof` and `in`, equality, bitwise, `&&`, `\|\|`, conditional, `=` and every AssignmentOperator except `&&=`, `\|\|=`, and `??=`, comma | 13.4 to 13.16 |
| Statements | Block, VariableStatement with BindingIdentifier, empty, expression, `if`, `do`-`while`, `while`, `for` with an Expression or `var` head, `continue`, `break`, `return`, `switch`, labelled statements, `throw`, `try` with a BindingIdentifier or omitted catch binding, `debugger` | 14.2, 14.3.2, 14.4 to 14.10, 14.12 to 14.16 |
| Functions | FunctionDeclaration and FunctionExpression with FormalParameters as BindingIdentifiers and an optional trailing comma. A FunctionDeclaration is allowed only as a statement-list item directly in a Script or a FunctionBody. | 15.1, 15.2 |
| Strictness | Directive prologues; `"use strict"` or `'use strict'` with exactly those code units, without escapes or line continuations | 11.2.1, 11.2.2 |
| Annex B | HTML-like comments (B.1.1); `var` names that repeat a catch parameter (B.3.4); call-expression assignment and update targets in non-strict code (B.3.9) | B.1.1, B.3.4, B.3.9 |

Contextual words follow these rules.

- An unescaped `let` at a statement start, followed by `[`, `{`, an Identifier, `yield`, `await`, or `let`, even across a line terminator, triggers `lexical_declaration`.
  Any other `let` is an IdentifierReference or a LabelIdentifier.
- An unescaped `async` followed, with no line terminator, by `function` or by an identifier triggers `async_function`.
  So does a `=>` after a call whose callee is that `async`.
- An unescaped `using` at a statement start followed, with no line terminator, by an Identifier triggers `using_declaration`.
- In an object literal, `(` after a property name triggers `method_definition`, and so does `*` at a property start.
  An unescaped `get`, `set`, or `async` followed by a property name also triggers it.
- `yield` and `await` are identifiers, except that `yield` is a strict reserved word.

The parser computes these static semantics:

- StringValue (13.1.2), SV (12.9.4.2), and NumericValue (12.9.3.3);
- PropName and PropertyNameList (13.2.5);
- IsStrict (11.2.2.1) and IsLabelledFunction (14.13.2);
- AssignmentTargetType (8.6.4);
- BoundNames, VarDeclaredNames, and TopLevelVarDeclaredNames (8.2);
- ContainsDuplicateLabels, ContainsUndefinedBreakTarget, and ContainsUndefinedContinueTarget (8.3);
- the functions-to-initialize list of 16.1.7 and 10.2.11.

NumericValue is `number.stringToNumber` of the literal's code units with every separator removed.
A LegacyOctalIntegerLiteral is first rewritten to the `0o` form.
This matches RoundMVResult for decimal literals and 𝔽(MV) for the other forms.

### Unsupported codes

The offset is the first code unit of the trigger token.

| Code | Trigger | Sections | Owner |
| --- | --- | --- | --- |
| `lexical_declaration` | `const`; `let` as above; `let` or `const` after `for (` | 14.3.1 | FP-0086 |
| `block_function_declaration` | `function` as a statement in a Block, a case or default clause, an `if` clause in non-strict code, or a LabelledItem in non-strict code | 14.2, 14.12, B.3.1, B.3.2, B.3.3 | FP-0086 |
| `using_declaration` | `using` as above | 14.3.1 | FP-0097 |
| `array_literal` | `[` where a PrimaryExpression begins | 13.2.4 | FP-0087 |
| `arguments_object` | The first IdentifierReference `arguments` in a function, not counting nested functions, when no parameter and no top-level FunctionDeclaration of that function is named `arguments` | 10.2.11, 10.4.4 | FP-0087 |
| `for_in` | `in` that ends a `for` head's first part | 14.7.5, B.3.5 | FP-0087 |
| `for_of` | `of` that ends a `for` head's first part | 14.7.5 | FP-0088 |
| `spread` | `...` in Arguments | 13.3.8 | FP-0088 |
| `object_spread` | `...` in an object literal | 13.2.5 | FP-0088 |
| `destructuring_binding` | `[` or `{` where a BindingIdentifier of `var`, a parameter, or a catch parameter is expected | 14.3.3 | FP-0088 |
| `destructuring_assignment` | `=` after an ObjectLiteral that is the left operand | 13.15.5 | FP-0088 |
| `default_parameter` | `=` after a formal parameter | 15.1 | FP-0088 |
| `rest_parameter` | `...` in FormalParameters | 15.1 | FP-0088 |
| `method_definition` | As above | 15.4 | FP-0089 |
| `class` | `class` | 15.7 | FP-0089 |
| `super` | `super` | 13.3.7 | FP-0089 |
| `new_target` | `new` followed by `.` | 13.3.12 | FP-0089 |
| `arrow_function` | `=>`; `...` inside parentheses; the `=>` after `()` | 15.3 | FP-0090 |
| `template` | `` ` `` | 12.9.6, 13.2.8, 13.3.11 | FP-0090 |
| `optional_chain` | `?.` | 13.3.9 | FP-0090 |
| `coalesce` | `??` | 13.13 | FP-0090 |
| `logical_assignment` | `&&=`, `\|\|=`, `??=` | 13.15 | FP-0090 |
| `generator` | `*` after `function` | 15.5, 15.6 | FP-0091 |
| `async_function` | As above | 15.8, 15.9 | FP-0091 |
| `for_await` | `await` after `for` | 14.7.5 | FP-0091 |
| `import` | `import` | 16.2.2, 13.3.10, 13.3.12 | FP-0092 |
| `regular_expression` | `/` or `/=` under the InputElementRegExp goal | 12.9.5, 13.2.7 | FP-0093 |
| `bigint_literal` | A numeric literal with the `n` suffix that the grammar allows | 12.9.3 | FP-0094 |
| `non_ascii_identifier` | A non-ASCII code point outside strings and comments that is not white space or a line terminator, or an identifier escape of such a code point | 12.7.1 | FP-0095 |
| `with` | `with` in non-strict code | 14.11 | FP-0096 |

### Syntax-error codes

| Code | Rule | Offset | Sections |
| --- | --- | --- | --- |
| `unexpected_token` | No production of the full grammar continues with this token, and no unsupported production begins with it. | The token | 5.1.4, 12.10 |
| `unexpected_end` | The input ends inside a production. | The source length | 5.1.4, 12.10 |
| `invalid_character` | An ASCII code point that begins no token, a `\` not followed by `u`, or a `#` not followed by an IdentifierName | The code unit | 12.6 |
| `unterminated_string` | A string literal reaches LF, CR, or the end of input. | The opening quote | 12.9.4 |
| `unterminated_comment` | `/*` without `*/` | The `/` | 12.4 |
| `invalid_escape` | A malformed `\x`, `\u`, or `\u{}` escape; a code point above U+10FFFF; an identifier escape of an ASCII code point that is not valid at its position | The backslash | 12.9.4, 12.7.1.1 |
| `invalid_numeric_literal` | A malformed literal, a misplaced separator, or an IdentifierStart or DecimalDigit immediately after the literal | The literal's first code unit | 12.9.3 |
| `strict_octal` | LegacyOctalIntegerLiteral or NonOctalDecimalIntegerLiteral in strict code | The literal | 12.9.3.1 |
| `strict_octal_escape` | LegacyOctalEscapeSequence or NonOctalDecimalEscapeSequence in strict code, including a directive string before `"use strict"` | The backslash | 12.9.4.1 |
| `reserved_word` | A ReservedWord, including one written with escapes, used as an IdentifierReference, a BindingIdentifier, or a LabelIdentifier | The identifier | 13.1.1, 12.7.2 |
| `strict_reserved_word` | `implements`, `interface`, `let`, `package`, `private`, `protected`, `public`, `static`, or `yield` used as an identifier in strict code | The identifier | 13.1.1 |
| `strict_eval_arguments` | `eval` or `arguments` as a BindingIdentifier or as an assignment or update target in strict code | The identifier | 13.1.1, 8.6.4, 15.2.1 |
| `invalid_assignment_target` | An AssignmentTargetType of `invalid` | The target's first code unit | 13.15.1, 13.4.1, 8.6.4 |
| `strict_delete_identifier` | `delete` of an IdentifierReference, parenthesized or not, in strict code | `delete` | 13.5.1.1 |
| `strict_with` | `with` in strict code | `with` | 14.11.1 |
| `function_declaration_position` | A FunctionDeclaration where only a Statement is allowed in strict code, or anywhere IsLabelledFunction applies | `function` | 14.6.1, 14.7.2.1, 14.7.3.1, 14.7.4.1, 14.13.1 |
| `duplicate_label` | ContainsDuplicateLabels | The repeated label | 8.3.1, 15.2.1, 16.1.1 |
| `undefined_break_target` | ContainsUndefinedBreakTarget | The label | 8.3.2, 15.2.1, 16.1.1 |
| `undefined_continue_target` | ContainsUndefinedContinueTarget | The label | 8.3.3, 15.2.1, 16.1.1 |
| `break_outside` | `break` without a label outside an iteration or switch statement in the same function | `break` | 14.9.1 |
| `continue_outside` | `continue` outside an iteration statement in the same function | `continue` | 14.8.1 |
| `return_outside_function` | `return` in Script code | `return` | 14.10, 16.1 |
| `duplicate_parameter` | A repeated parameter name in a strict function | The repetition | 15.1.1, 15.2.1 |
| `duplicate_proto` | Two `__proto__` definitions of the `PropertyName : AssignmentExpression` form | The second key | 13.2.5.1 |
| `cover_initialized_name` | `{ a = 1 }` that is not followed by `=` | The name | 13.2.5.1 |
| `unary_before_exponent` | A UnaryExpression other than an UpdateExpression as the left operand of `**` | `**` | 13.6 |
| `private_identifier` | A PrivateIdentifier outside a class | `#` | 16.1.1 |
| `throw_line_terminator` | A line terminator after `throw` | `throw` | 14.14, 12.10 |

Limit codes are `depth`, `memory`, and `source_length`.

`writeCodeTable` writes one line per code, in the order of the tables above.
The line forms are `syntax-error|<code>|<sections>`, `unsupported|<code>|<sections>|<owner>`, and `limit|<code>`.
Sections are written as in the tables, separated by `,` without spaces.

### Syntax tree dump

The dump is one line.
Tokens inside a group are separated by single spaces.

- Script: `(script <sloppy|strict> (var-declared-names <names>) (functions-to-initialize <name>#<k> ...) <statement>...)`.
- `var-declared-names` lists VarDeclaredNames, using TopLevelVarDeclaredNames for a Script or a FunctionBody, in source order, keeping the first occurrence of each name.
- `functions-to-initialize` follows 16.1.7 for a Script and 10.2.11 for a function: reverse iteration, the last declaration of each name, then source order.
  `#k` is the 1-based index of a FunctionDeclaration among all FunctionDeclarations of the source, ordered by their `function` token.
- Function declaration: `(function-declaration #<k> <name> (params <names>) <sloppy|strict> (var-declared-names ...) (functions-to-initialize ...) <statement>...)`.
- Function expression: `(function-expression <name or -> (params ...) <strictness> (var-declared-names ...) (functions-to-initialize ...) <statement>...)`.
- Statements:
  - `(var (<name>) (<name> <expr>) ...)`, `(expression e)`, `(block s...)`, `(empty)`, `(if e s)`, `(if e s s)`;
  - `(do-while s e)`, `(while e s)`, `(for <init> <test> <update> s)`, where an absent part is `-` and `init` is a `(var ...)` group or an expression;
  - `(continue)`, `(continue l)`, `(break)`, `(break l)`, `(return)`, `(return e)`, `(throw e)`;
  - `(switch e (case e s...) (default s...))`, `(labelled l s)`;
  - `(try <block> (catch <name or -> <block>) (finally <block>))`, with absent clauses omitted;
  - `(debugger)`.
- Expressions:
  - `(identifier n)`, `(this)`, `(null)`, `(true)`, `(false)`, `(number <Number::toString of the value>)`, `(string "<units>")`;
  - `(object p...)`, with properties `(property "<key>" e)`, `(property (computed e) e)`, `(shorthand n)`, and `(proto e)`;
  - `(paren e)`, `(member e "<name>")`, `(index e e)`, `(call e arg...)`, `(new e arg...)`, where `new X` and `new X()` print alike;
  - `(prefix <op> e)`, `(postfix <op> e)`, `(unary <op> e)`, `(binary <op> e e)`, `(logical <op> e e)`, `(conditional e e e)`, `(assign <op> e e)`;
  - `(sequence e e...)`, flattened.
- A string escapes `"` as `\"` and `\` as `\\`, writes other code units 0x20 to 0x7E as is, and writes every other code unit as `\u` followed by four uppercase hex digits.
  Names and labels are ASCII and print raw.
- A property key is PropName: the StringValue for a name or a string, and ToString of NumericValue for a number.

Node depth counts every parenthesized group except `var-declared-names`, `functions-to-initialize`, and `params`.
The script has depth 1.
A tree deeper than `max_depth` produces `limit depth`.
The parser's recursion stays within the depth bound for every input, so no input overflows the stack.
A function node also records the code-unit range of its source text, from `function` through `}`.

### Command line

`zig build js-tools` installs `fairpane-js-parse`.

- `fairpane-js-parse file <path>` decodes UTF-8, parses, and writes `writeOutcome` and a newline to standard output.
  It exits with status 0 for a script, 1 for a syntax error, 2 for unsupported, 3 for an input or usage error, and 4 for a limit.
- `fairpane-js-parse census <root> <out.jsonl>` runs the census.

### Metadata reader

The frontmatter is the text from the first `/*---` to the next `---*/`.
The reader handles this YAML subset.

- A top-level key starts at column 0.
- `flags`, `features`, and `includes` take a flow list `[a, b]` or block items of the form `  - a`.
- `negative` takes indented `phase:` and `type:` lines.
- A `#` comment is stripped.
- Other keys are skipped together with their indented continuation lines.

These are metadata errors:

- a missing frontmatter;
- a duplicate key;
- a flag outside `onlyStrict`, `noStrict`, `module`, `raw`, `async`, `generated`, `CanBlockIsFalse`, `CanBlockIsTrue`, and `non-deterministic`;
- a phase outside `parse`, `resolution`, and `runtime`;
- an unreadable list.

### Census

The census reads `<root>/EXTRACT.json` and `<root>/features.txt`.
It discovers files under `<root>/test` by `TEST262_RULE` and visits them in order of their raw path bytes.

A file flagged `module` is counted as `module` and is not parsed.
Otherwise, the census parses the file in each mode:

- `onlyStrict`: strict only;
- `noStrict` or `raw`: non-strict only;
- otherwise, both modes.

The strict source is `"use strict";` followed by U+000A and the file.
A negative phase of `parse` expects a syntax error; anything else expects a valid file.

Each run is classified as one of the following:

- `agree_valid`: the file is expected valid, and the outcome is a script;
- `agree_error`: a syntax error is expected, and the outcome is a syntax error;
- `unsupported`;
- `limit`;
- `false_accept`: a syntax error is expected, but the outcome is a script;
- `false_syntax_error`: the file is expected valid, but the outcome is a syntax error;
- `proposal_mismatch`: a mismatch in a proposal test.

`metadata_error` and `input_error` are counted per file.
The census writes every per-file record to `<out.jsonl>`, which must not already exist.
It writes these lines to standard output:

- a header line `{"format":"fairpane-js-parse-census","version":1,"commit":"<EXTRACT commit>"}`;
- one line per violation;
- a final summary line with keys in this order: `discovered`, `module`, `proposal_files`, `runs`, `agree_valid`, `agree_error`, `unsupported`, `limit`, `proposal_mismatch`, `false_accept`, `false_syntax_error`, `metadata_error`, `input_error`.

The summary line is followed by `unsupported_by_code`, with its keys sorted.
The census exits with status 0 only when `false_accept`, `false_syntax_error`, `metadata_error`, and `input_error` are all zero.

### Extraction

`node tools/fairpane.mjs corpus-extract test262 <out-dir>` works as follows.

1. It loads the snapshot record and the snapshot, and checks the recorded commit.
2. It requires `<out-dir>` to lie under `<root>/out/` and to be absent or empty.
3. It writes every blob of the pinned tree whose path starts with `test/` or `harness/`, together with `features.txt`.
4. It rejects a mode other than 100644 or 100755, and a path with an empty, `.`, or `..` component.
5. It checks the Git blob hash of each written file against its tree object ID.
6. It writes `EXTRACT.json` with `schema_version`, `corpus`, `commit`, `tree`, `files`, and `entries_sha256`.
   `entries_sha256` is the SHA-256 of the lines `<oid> <path>`, each ending with LF, sorted by path bytes.

The command runs no corpus code.

## Exact test cases

Zig tests live beside the code and run through `zig build test`.

Sources are shown as raw JavaScript.
`⏎` is U+000A, `<CR>` is U+000D, and `<U+XXXX>` is that code point.
A row ending in `statements: ...` expects `(script <strictness> (var-declared-names <names>) (functions-to-initialize <functions>) ` followed by the listed statements separated by single spaces and a final `)`.
The strictness is `sloppy` unless the row states it, and the names and functions are empty unless the row gives them.

1. `writeCodeTable` equals a frozen literal of the three code tables above, line for line.

2. Each source produces exactly this dump.

```text
T1  (empty) ⇒ (script sloppy (var-declared-names) (functions-to-initialize))
T2  "use strict"; ⇒ strict; statements: (expression (string "use strict"))
T3  "use\x20strict"; var let; ⇒ names let; statements: (expression (string "use strict")) (var (let))
T4  "a"; "use strict"; ⇒ strict; statements: (expression (string "a")) (expression (string "use strict"))
T5  "use strict"⏎+1; var let; ⇒ names let; statements: (expression (binary + (string "use strict") (number 1))) (var (let))
T6  ("use strict"); var let; ⇒ names let; statements: (expression (paren (string "use strict"))) (var (let))
T7  var a, b = 1; var a; ⇒ names a b; statements: (var (a) (b (number 1))) (var (a))
T8  function f() {} function g() {} function f() {} ⇒ names f g; functions g#2 f#3; statements: (function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize)) (function-declaration #2 g (params) sloppy (var-declared-names) (functions-to-initialize)) (function-declaration #3 f (params) sloppy (var-declared-names) (functions-to-initialize))
T9  function f(a, b) { var c = a; function g() {} return c + b; } ⇒ names f; functions f#1; statements: (function-declaration #1 f (params a b) sloppy (var-declared-names c g) (functions-to-initialize g#2) (var (c (identifier a))) (function-declaration #2 g (params) sloppy (var-declared-names) (functions-to-initialize)) (return (binary + (identifier c) (identifier b))))
T10 function f() { "use strict"; return this; } ⇒ names f; functions f#1; statements: (function-declaration #1 f (params) strict (var-declared-names) (functions-to-initialize) (expression (string "use strict")) (return (this)))
T11 if (a) { var x; } while (b) var y; for (var z;;) {} try { var p } catch (q) { var r } finally { var s } l: var t; switch (u) { case 1: var v; default: var w; } ⇒ names x y z p r s t v w; statements: (if (identifier a) (block (var (x)))) (while (identifier b) (var (y))) (for (var (z)) - - (block)) (try (block (var (p))) (catch q (block (var (r)))) (finally (block (var (s))))) (labelled l (var (t))) (switch (identifier u) (case (number 1) (var (v))) (default (var (w))))
T12 a + b * c - d; a = b = c; a || b && c; a ? b : c ? d : e; ⇒ statements: (expression (binary - (binary + (identifier a) (binary * (identifier b) (identifier c))) (identifier d))) (expression (assign = (identifier a) (assign = (identifier b) (identifier c)))) (expression (logical || (identifier a) (logical && (identifier b) (identifier c)))) (expression (conditional (identifier a) (identifier b) (conditional (identifier c) (identifier d) (identifier e))))
T13 2 ** 3 ** 2; (-2) ** 2; ++a ** 2; a ** -b; ⇒ statements: (expression (binary ** (number 2) (binary ** (number 3) (number 2)))) (expression (binary ** (paren (unary - (number 2))) (number 2))) (expression (binary ** (prefix ++ (identifier a)) (number 2))) (expression (binary ** (identifier a) (unary - (identifier b))))
T14 a < b == c > d; a & b | c ^ d; a << b + c >>> d; a instanceof b in c; ⇒ statements: (expression (binary == (binary < (identifier a) (identifier b)) (binary > (identifier c) (identifier d)))) (expression (binary | (binary & (identifier a) (identifier b)) (binary ^ (identifier c) (identifier d)))) (expression (binary >>> (binary << (identifier a) (binary + (identifier b) (identifier c))) (identifier d))) (expression (binary in (binary instanceof (identifier a) (identifier b)) (identifier c)))
T15 typeof void delete a.b; - -a; ~!a; a+++b; a, b, c; ⇒ statements: (expression (unary typeof (unary void (unary delete (member (identifier a) "b"))))) (expression (unary - (unary - (identifier a)))) (expression (unary ~ (unary ! (identifier a)))) (expression (binary + (postfix ++ (identifier a)) (identifier b))) (expression (sequence (identifier a) (identifier b) (identifier c)))
T16 new a.b(c).d(e)[f]; new new a()(); new a; new a().b; new (a()); new a()(); ⇒ statements: (expression (index (call (member (new (member (identifier a) "b") (identifier c)) "d") (identifier e)) (identifier f))) (expression (new (new (identifier a)))) (expression (new (identifier a))) (expression (member (new (identifier a)) "b")) (expression (new (paren (call (identifier a))))) (expression (call (new (identifier a))))
T17 a.if.class[0](1, 2,); a.\u0069f; 5..a; a ? .5 : 1; ⇒ statements: (expression (call (index (member (member (identifier a) "if") "class") (number 0)) (number 1) (number 2))) (expression (member (identifier a) "if")) (expression (member (number 5) "a")) (expression (conditional (identifier a) (number 0.5) (number 1)))
T18 ({a: 1, "b": 2, 3: 3, 0x10: 4, 1.50: 5, [k]: 6, c, __proto__: null, if: 7, \u0069f: 8,}); ⇒ statements: (expression (paren (object (property "a" (number 1)) (property "b" (number 2)) (property "3" (number 3)) (property "16" (number 4)) (property "1.5" (number 5)) (property (computed (identifier k)) (number 6)) (shorthand c) (proto (null)) (property "if" (number 7)) (property "if" (number 8)))))
T19 ({"__proto__": a, ["__proto__"]: b, __proto__, get: 1, set: 2, async: 3, get}); ⇒ statements: (expression (paren (object (proto (identifier a)) (property (computed (string "__proto__")) (identifier b)) (shorthand __proto__) (property "get" (number 1)) (property "set" (number 2)) (property "async" (number 3)) (shorthand get))))
T20 (function () {}); (function g(a,) { "use strict"; }); x = function () { return 1; }; ⇒ statements: (expression (paren (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize)))) (expression (paren (function-expression g (params a) strict (var-declared-names) (functions-to-initialize) (expression (string "use strict"))))) (expression (assign = (identifier x) (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize) (return (number 1)))))
T21 "\0\b\f\n\r\t\v\x41\u0042\u{43}\u{1F600}\uD800\'\"\\a\⏎b"; ⇒ statements: (expression (string "\u0000\u0008\u000C\u000A\u000D\u0009\u000BABC\uD83D\uDE00\uD800'\"\\ab"))
T22 "\101\08\8\9\400"; ⇒ statements: (expression (string "A\u0000889 0"))
T23 "a<U+2028>b"; "a\<U+2028>b"; "\u{0000000000041}"; ⇒ statements: (expression (string "a\u2028b")) (expression (string "ab")) (expression (string "A"))
T24 0; 1.5; .5; 5.; 1e3; 1E-3; 0x1F; 0o17; 0b101; 010; 08; 09.5; 1_000; 0x1_F; 1e1_0; 9007199254740993; 1e400; 0.1; 0.0000001; ⇒ statements: (expression (number 0)) (expression (number 1.5)) (expression (number 0.5)) (expression (number 5)) (expression (number 1000)) (expression (number 0.001)) (expression (number 31)) (expression (number 15)) (expression (number 5)) (expression (number 8)) (expression (number 8)) (expression (number 9.5)) (expression (number 1000)) (expression (number 31)) (expression (number 10000000000)) (expression (number 9007199254740992)) (expression (number Infinity)) (expression (number 0.1)) (expression (number 1e-7))
T25 var \u0061b\u{63}; ⇒ names abc; statements: (var (abc))
T26 /* a */ a /* b⏎ */ b // c⏎<!-- d⏎--> e⏎ c ⇒ statements: (expression (identifier a)) (expression (identifier b)) (expression (identifier c))
T27 x = 1 <!-- y ⇒ statements: (expression (assign = (identifier x) (number 1)))
T28 a /* x */ --> b ⇒ statements: (expression (binary > (postfix -- (identifier a)) (identifier b)))
T29 each of: --> b | ␠␠--> b | /* */ --> b | a /*⏎*/ --> b ⇒ the first three give (script sloppy (var-declared-names) (functions-to-initialize)); the fourth gives statements: (expression (identifier a))
T30 #!anything⏎x ⇒ statements: (expression (identifier x))
T31 a<U+0009><U+000B><U+000C><U+0020><U+00A0><U+FEFF><U+1680><U+2000>…<U+200A><U+202F><U+205F><U+3000>= 1 ⇒ statements: (expression (assign = (identifier a) (number 1))); and each of a<U+2028>b, a<U+2029>b, a<CR>⏎b, a<CR>b ⇒ statements: (expression (identifier a)) (expression (identifier b))
T32 ASI: a⏎(b) ⇒ (expression (call (identifier a) (paren (identifier b)))); x⏎++y ⇒ (expression (identifier x)) (expression (prefix ++ (identifier y))); do ; while (0) x ⇒ (do-while (empty) (number 0)) (expression (identifier x)); var a = 1 /*⏎*/ b = 2 ⇒ names a; (var (a (number 1))) (expression (assign = (identifier b) (number 2))); a⏎/b/g ⇒ (expression (binary / (binary / (identifier a) (identifier b)) (identifier g))); l: while (1) { break⏎l } ⇒ (labelled l (while (number 1) (block (break) (expression (identifier l))))); { 1⏎2 } 3 ⇒ (block (expression (number 1)) (expression (number 2))) (expression (number 3)); function f() { return⏎1 } ⇒ names f; functions f#1; (function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize) (return) (expression (number 1)))
T33 if (a) if (b) c; else d; l1: l2: for (;;) { continue l1; } a: { b: { break a; } } switch (x) { case 1: a; case 2: default: b; case 3: } try { a } catch (e) { var e = 1; } finally { b } try {} catch {} try {} finally {} throw a; debugger; ; ⇒ names e; statements: (if (identifier a) (if (identifier b) (expression (identifier c)) (expression (identifier d)))) (labelled l1 (labelled l2 (for - - - (block (continue l1))))) (labelled a (block (labelled b (block (break a))))) (switch (identifier x) (case (number 1) (expression (identifier a))) (case (number 2)) (default (expression (identifier b))) (case (number 3))) (try (block (expression (identifier a))) (catch e (block (var (e (number 1))))) (finally (block (expression (identifier b))))) (try (block) (catch - (block))) (try (block) (finally (block))) (throw (identifier a)) (debugger) (empty)
T34 do x++; while (x < 3) for (var i = 0, j; i < 1; i++) continue; for (i = 0; ; ) break; while (a) {} ⇒ names i j; statements: (do-while (expression (postfix ++ (identifier x))) (binary < (identifier x) (number 3))) (for (var (i (number 0)) (j)) (binary < (identifier i) (number 1)) (postfix ++ (identifier i)) (continue)) (for (assign = (identifier i) (number 0)) - - (break)) (while (identifier a) (block))
T35 f() = 1; f() += 1; f()++; --f(); eval = 1; arguments = 2; delete (x); (a) = 1; ((a.b)) = 2; ⇒ statements: (expression (assign = (call (identifier f)) (number 1))) (expression (assign += (call (identifier f)) (number 1))) (expression (postfix ++ (call (identifier f)))) (expression (prefix -- (call (identifier f)))) (expression (assign = (identifier eval) (number 1))) (expression (assign = (identifier arguments) (number 2))) (expression (unary delete (paren (identifier x)))) (expression (assign = (paren (identifier a)) (number 1))) (expression (assign = (paren (paren (member (identifier a) "b"))) (number 2)))
T36 var yield, await, let, static, async, of, get, set; let = 1; let(1); yield = 1; await = 2; let: 1; l\u0065t = 1; async⏎function f() {} ⇒ names yield await let static async of get set f; functions f#1; statements: (var (yield) (await) (let) (static) (async) (of) (get) (set)) (expression (assign = (identifier let) (number 1))) (expression (call (identifier let) (number 1))) (expression (assign = (identifier yield) (number 1))) (expression (assign = (identifier await) (number 2))) (labelled let (expression (number 1))) (expression (assign = (identifier let) (number 1))) (expression (identifier async)) (function-declaration #1 f (params) sloppy (var-declared-names) (functions-to-initialize))
T37 function f(arguments) { return arguments; } function g() { function arguments() {} return arguments; } arguments; ⇒ names f g; functions f#1 g#2; statements: (function-declaration #1 f (params arguments) sloppy (var-declared-names) (functions-to-initialize) (return (identifier arguments))) (function-declaration #2 g (params) sloppy (var-declared-names arguments) (functions-to-initialize arguments#3) (function-declaration #3 arguments (params) sloppy (var-declared-names) (functions-to-initialize)) (return (identifier arguments))) (expression (identifier arguments))
T38 a: while (1) { (function () { a: ; }); break a; } ⇒ statements: (labelled a (while (number 1) (block (expression (paren (function-expression - (params) sloppy (var-declared-names) (functions-to-initialize) (labelled a (empty))))) (break a))))
T39 "use strict"; var a = function () {}; function f() {} ⇒ strict; names a f; functions f#1; statements: (expression (string "use strict")) (var (a (function-expression - (params) strict (var-declared-names) (functions-to-initialize)))) (function-declaration #1 f (params) strict (var-declared-names) (functions-to-initialize))
T40 try {} catch (e) { var e; } ⇒ names e; statements: (try (block) (catch e (block (var (e)))))
T41 debugger; ; ⇒ statements: (debugger) (empty)
```

   In T29, `|` separates the four sources and `␠` is U+0020.
   In T31, `…` stands for every code point from U+2001 through U+2009.

3. For T20, the source range of the third function is exactly `function () { return 1; }`.
   For T9, the range of `f` is the whole source.

4. For 100,000 bit patterns from `std.Random.DefaultPrng` seed `0x4650303132000001`, each a positive finite non-zero Number, the source `Number::toString(x)` produces `(number <same text>)`.
   The parsed value has the bits of `x`.

5. One string literal of the 65,536 escapes `\u0000` through `\uFFFF` in order produces exactly the code units 0x0000 through 0xFFFF.

6. Each source produces exactly this syntax error.
   Sources that begin `"use strict"; ` include that 14-unit prefix in their offsets.

```text
E1  var 1; ⇒ syntax-error unexpected_token @4
E2  a b ⇒ syntax-error unexpected_token @2
E3  if (a ⇒ syntax-error unexpected_end @5
E4  a @ b ⇒ syntax-error invalid_character @2
E5  a <U+0001> b ⇒ syntax-error invalid_character @2
E6  a \ b ⇒ syntax-error invalid_character @2
E7  "abc ⇒ syntax-error unterminated_string @0
E8  "a⏎b" ⇒ syntax-error unterminated_string @0
E9  "a<CR>b" ⇒ syntax-error unterminated_string @0
E10 /* a ⇒ syntax-error unterminated_comment @0
E11 "\x4" ⇒ syntax-error invalid_escape @1
E12 "\u12" ⇒ syntax-error invalid_escape @1
E13 "\u{110000}" ⇒ syntax-error invalid_escape @1
E14 "\u{}" ⇒ syntax-error invalid_escape @1
E15 \u0030abc ⇒ syntax-error invalid_escape @0
E16 a\u002Db ⇒ syntax-error invalid_escape @1
E17 each of: 3in [] | 0x | 0b12 | 1__0 | 1_ | 0_1 | 08_1 | 1e | 1e_1 | 0x_1 | 1.a | 1._5 | 1_.5 | 1.5n | 01n | 0x1g ⇒ syntax-error invalid_numeric_literal @0
E18 07.5 ⇒ syntax-error unexpected_token @2
E19 "use strict"; 010; ⇒ syntax-error strict_octal @14
E20 "use strict"; 08; ⇒ syntax-error strict_octal @14
E21 "use strict"; 09.5 ⇒ syntax-error strict_octal @14
E22 function f(a) { "use strict"; 010 } ⇒ syntax-error strict_octal @30
E23 "use strict"; "\08"; ⇒ syntax-error strict_octal_escape @15
E24 "use strict"; "\8"; ⇒ syntax-error strict_octal_escape @15
E25 function f() { "\07"; "use strict"; } ⇒ syntax-error strict_octal_escape @16
E26 "\07"; "use strict"; ⇒ syntax-error strict_octal_escape @1
E27 var if; ⇒ syntax-error reserved_word @4
E28 var enum; ⇒ syntax-error reserved_word @4
E29 var v\u0061r; ⇒ syntax-error reserved_word @4
E30 \u0074his ⇒ syntax-error reserved_word @0
E31 ({if}) ⇒ syntax-error reserved_word @2
E32 ({\u0069f}) ⇒ syntax-error reserved_word @2
E33 "use strict"; var let; ⇒ syntax-error strict_reserved_word @18
E34 "use strict"; var yield; ⇒ syntax-error strict_reserved_word @18
E35 "use strict"; implements = 1; ⇒ syntax-error strict_reserved_word @14
E36 "use strict"; l\u0065t = 1; ⇒ syntax-error strict_reserved_word @14
E37 "use strict"; let: 1 ⇒ syntax-error strict_reserved_word @14
E38 function yield() { "use strict"; } ⇒ syntax-error strict_reserved_word @9
E39 "use strict"; var eval; ⇒ syntax-error strict_eval_arguments @18
E40 "use strict"; arguments = 1; ⇒ syntax-error strict_eval_arguments @14
E41 "use strict"; eval++; ⇒ syntax-error strict_eval_arguments @14
E42 "use strict"; function arguments() {} ⇒ syntax-error strict_eval_arguments @23
E43 function eval() { "use strict"; } ⇒ syntax-error strict_eval_arguments @9
E44 "use strict"; try {} catch (eval) {} ⇒ syntax-error strict_eval_arguments @28
E45 "use strict"; function f(eval) {} ⇒ syntax-error strict_eval_arguments @25
E46 1 = 2 ⇒ syntax-error invalid_assignment_target @0
E47 a + 1 = 2 ⇒ syntax-error invalid_assignment_target @0
E48 this = 1 ⇒ syntax-error invalid_assignment_target @0
E49 (a, b) = 1 ⇒ syntax-error invalid_assignment_target @0
E50 ++1 ⇒ syntax-error invalid_assignment_target @2
E51 1++ ⇒ syntax-error invalid_assignment_target @0
E52 new f() = 1 ⇒ syntax-error invalid_assignment_target @0
E53 typeof a = 1 ⇒ syntax-error invalid_assignment_target @0
E54 "use strict"; f() = 1; ⇒ syntax-error invalid_assignment_target @14
E55 "use strict"; f()++; ⇒ syntax-error invalid_assignment_target @14
E56 "use strict"; f() += 1; ⇒ syntax-error invalid_assignment_target @14
E57 "use strict"; delete x; ⇒ syntax-error strict_delete_identifier @14
E58 "use strict"; delete (x); ⇒ syntax-error strict_delete_identifier @14
E59 "use strict"; delete ((x)); ⇒ syntax-error strict_delete_identifier @14
E60 function f() { "use strict"; delete x; } ⇒ syntax-error strict_delete_identifier @29
E61 "use strict"; with (a) {} ⇒ syntax-error strict_with @14
E62 "use strict"; if (a) function f() {} ⇒ syntax-error function_declaration_position @21
E63 "use strict"; l: function f() {} ⇒ syntax-error function_declaration_position @17
E64 while (a) function f() {} ⇒ syntax-error function_declaration_position @10
E65 while (0) l: function f() {} ⇒ syntax-error function_declaration_position @13
E66 do function f() {} while (0) ⇒ syntax-error function_declaration_position @3
E67 if (a) l: function f() {} ⇒ syntax-error function_declaration_position @10
E68 a: a: ; ⇒ syntax-error duplicate_label @3
E69 a: { a: ; } ⇒ syntax-error duplicate_label @5
E70 a: { break b; } ⇒ syntax-error undefined_break_target @11
E71 break a; ⇒ syntax-error undefined_break_target @6
E72 a: { while (1) { continue a; } } ⇒ syntax-error undefined_continue_target @26
E73 a: while (1) { continue b; } ⇒ syntax-error undefined_continue_target @24
E74 break; ⇒ syntax-error break_outside @0
E75 while (1) { (function () { break; }); } ⇒ syntax-error break_outside @27
E76 continue; ⇒ syntax-error continue_outside @0
E77 switch (1) { case 1: continue; } ⇒ syntax-error continue_outside @21
E78 return; ⇒ syntax-error return_outside_function @0
E79 "use strict"; function f(a, a) {} ⇒ syntax-error duplicate_parameter @28
E80 function f(a, a) { "use strict"; } ⇒ syntax-error duplicate_parameter @14
E81 ({__proto__: 1, __proto__: 2}) ⇒ syntax-error duplicate_proto @16
E82 ({__proto__: 1, "__proto__": 2}) ⇒ syntax-error duplicate_proto @16
E83 ({a = 1}) ⇒ syntax-error cover_initialized_name @2
E84 -a ** 2 ⇒ syntax-error unary_before_exponent @3
E85 typeof a ** 2 ⇒ syntax-error unary_before_exponent @9
E86 !a ** 2 ⇒ syntax-error unary_before_exponent @3
E87 #x ⇒ syntax-error private_identifier @0
E88 a.#x ⇒ syntax-error private_identifier @2
E89 ␠#!x ⇒ syntax-error invalid_character @1
E90 throw⏎1 ⇒ syntax-error throw_line_terminator @0
E91 { 1 2 } 3 ⇒ syntax-error unexpected_token @4
E92 for (a; b⏎) c ⇒ syntax-error unexpected_token @10
E93 if (a)⏎else b ⇒ syntax-error unexpected_token @7
E94 a⏎++ ⇒ syntax-error unexpected_end @4
E95 function () {} ⇒ syntax-error unexpected_token @9
E96 () ⇒ syntax-error unexpected_token @1 (superseded by revision 1, case 1: unexpected_end @2)
E97 function f(,) {} ⇒ syntax-error unexpected_token @11
E98 try {} ⇒ syntax-error unexpected_end @6
E99 switch (a) { default: default: } ⇒ syntax-error unexpected_token @22
E100 export var a; ⇒ syntax-error unexpected_token @0
E101 x = 1; --> y ⇒ syntax-error unexpected_token @9
E102 @dec class A {} ⇒ syntax-error invalid_character @0
```

   In E17, `|` separates the 16 sources.
   `␠` is U+0020.
   The Zig source of E100 builds its text by concatenation.

7. Each source produces exactly this unsupported outcome.

```text
U1  let x; ⇒ unsupported lexical_declaration @0
U2  const x = 1; ⇒ unsupported lexical_declaration @0
U3  let [a] = b; ⇒ unsupported lexical_declaration @0
U4  let⏎x ⇒ unsupported lexical_declaration @0
U5  for (let i;;) {} ⇒ unsupported lexical_declaration @5
U6  if (a) { let x; } ⇒ unsupported lexical_declaration @9
U7  using x = y; ⇒ unsupported using_declaration @0
U8  class A {} ⇒ unsupported class @0
U9  (class {}) ⇒ unsupported class @1
U10 function* g() {} ⇒ unsupported generator @8
U11 (function* () {}) ⇒ unsupported generator @9
U12 async function f() {} ⇒ unsupported async_function @0
U13 async x => x ⇒ unsupported async_function @0
U14 async (x) => x ⇒ unsupported async_function @0
U15 (async function () {}) ⇒ unsupported async_function @1
U16 x => x ⇒ unsupported arrow_function @2
U17 (a, b) => a ⇒ unsupported arrow_function @7
U18 () => 1 ⇒ unsupported arrow_function @3
U19 (a, ...b) => 1 ⇒ unsupported arrow_function @4
U20 `a` ⇒ unsupported template @0
U21 f`a` ⇒ unsupported template @1
U22 /a/ ⇒ unsupported regular_expression @0
U23 a = /b/g ⇒ unsupported regular_expression @4
U24 if (a) /x/.test(b) ⇒ unsupported regular_expression @7
U25 [1] ⇒ unsupported array_literal @0
U26 a = [] ⇒ unsupported array_literal @4
U27 1n ⇒ unsupported bigint_literal @0
U28 0x1Fn ⇒ unsupported bigint_literal @0
U29 f(...a) ⇒ unsupported spread @2
U30 new F(...a) ⇒ unsupported spread @6
U31 ({a() {}}) ⇒ unsupported method_definition @3
U32 each of: ({get a() {}}) | ({set a(v) {}}) | ({*g() {}}) | ({async f() {}}) ⇒ unsupported method_definition @2
U33 ({...a}) ⇒ unsupported object_spread @2
U34 var {a} = b; ⇒ unsupported destructuring_binding @4
U35 var [a] = b; ⇒ unsupported destructuring_binding @4
U36 function f({a}) {} ⇒ unsupported destructuring_binding @11
U37 try {} catch ([e]) {} ⇒ unsupported destructuring_binding @14
U38 ({a} = b) ⇒ unsupported destructuring_assignment @5
U39 ({a = 1} = b) ⇒ unsupported destructuring_assignment @9
U40 function f(a = 1) {} ⇒ unsupported default_parameter @13
U41 function f(...a) {} ⇒ unsupported rest_parameter @11
U42 each of: a?.b | a?.[0] | a?.() ⇒ unsupported optional_chain @1
U43 a ?? b ⇒ unsupported coalesce @2
U44 each of: a &&= b | a ??= b, and a ||= b ⇒ unsupported logical_assignment @2
U45 function f() { new.target } ⇒ unsupported new_target @15
U46 super.x ⇒ unsupported super @0
U47 each of: import x from "y" | import("y") | import.meta ⇒ unsupported import @0
U48 for (a in b) {} ⇒ unsupported for_in @7; for (var a in b) {} ⇒ @11; for (var a = 1 in b) {} ⇒ @15
U49 for (a of b) {} ⇒ unsupported for_of @7; for (var a of b) {} ⇒ @11
U50 for await (x of y) {} ⇒ unsupported for_await @4
U51 with (a) {} ⇒ unsupported with @0
U52 { function f() {} } ⇒ unsupported block_function_declaration @2; if (a) function f() {} ⇒ @7; l: function f() {} ⇒ @3; switch (a) { case 1: function f() {} } ⇒ @21; "use strict"; { function f() {} } ⇒ @16
U53 var é; ⇒ unsupported non_ascii_identifier @4; var \u00e9; ⇒ @4; var a\u200C; ⇒ @5; var<U+180E>a; ⇒ @3
U54 function f() { return arguments; } ⇒ unsupported arguments_object @22; function f() { var arguments; return arguments; } ⇒ @37; function f() { return function () { return arguments; }; } ⇒ @43
```

8. Detection order:
   - `1 = 2; class A {}` gives `syntax-error invalid_assignment_target @0`.
   - `class A {}; 1 = 2` gives `unsupported class @0`.
   - `function f() { return arguments; 1 = 2; }` gives `syntax-error invalid_assignment_target @33`.
   - `function f(a = 1, a) { "use strict"; }` gives `unsupported default_parameter @13`.

9. Strict-prefix property: for each source T1 through T41, parse `"use strict";`, then U+000A, then the source.
   Each outcome is one of the following:
   - a strict script whose statements are `(expression (string "use strict"))` followed by the original statements, with every function `strict`;
   - a syntax error with one of the codes `strict_octal`, `strict_octal_escape`, `strict_reserved_word`, `strict_eval_arguments`, `strict_delete_identifier`, `strict_with`, `function_declaration_position`, `duplicate_parameter`, or `invalid_assignment_target`;
   - an `unsupported` outcome.

10. Depth boundaries hold under the default options.
    - `a` joined by `+`, with 1022 terms, is a script; with 1023 terms, it gives `limit depth`.
    - `a` inside 1021 parentheses is a script; inside 1022 parentheses, it gives `limit depth`.
    - The test runs both accepted inputs and both limit inputs, and `writeOutcome` of each accepted tree, on a thread that it spawns with `std.Thread.SpawnConfig.stack_size` set to 1 MiB, in the Debug test build.
      Each finishes with the outcome above.

11. Each of these inputs, nested 100,000 times around `a` and closed where a closer exists, gives `limit depth` and does not crash:
    - `(`;
    - `!`;
    - `typeof `;
    - `{`;
    - `if (a) `;
    - `(function(){` with its closing `})`;
    - `a(`;
    - `a[`;
    - `a?a:`;
    - `a=`;
    - `a**`;
    - `new `;
    - `({a:` with its closing `})`;
    - `l<n>:` with distinct labels.

    Every input of this case also runs on a 1 MiB thread, as case 10 does.

12. With `max_memory_bytes = 4096`, 10,000 repetitions of `a;` give `limit memory`.
    With `max_source_units = 10`, `var abcdefgh;` gives `limit source_length @0`.
    With the defaults, 1,000,000 repetitions of `a;` give a script.

13. `std.testing.checkAllAllocationFailures` runs the parse of T9, T11, T18, T21, and T33 concatenated.
    Every induced failure returns `error.OutOfMemory`, and nothing leaks.

14. 50,000 random sources run under seed `0x4650303132000002`.
    Each has a length from 0 to 64 code units, drawn from: ASCII letters, digits, punctuation, quotes, and `\`; U+000A, U+000D, U+2028, U+00A0, U+FEFF, U+D800, U+DC00, U+00E9, and U+180E.
    Every source yields an outcome, and `writeOutcome` succeeds without a panic or a leak.
    Every prefix of every source in cases 2, 6, and 7, and every one-unit deletion from it, does the same.

15. Metadata reader:
    - `flags: [onlyStrict, raw] # x` gives those two flags.
    - `flags:⏎  - module⏎` gives `module`.
    - `negative:⏎  type: SyntaxError⏎  phase: parse⏎` gives `parse` and `SyntaxError`.
    - `includes: [propertyHelper.js]` and `features: [Symbol.toPrimitive, regexp-v-flag]` read as written.
    - A `description: |` block followed by indented lines that contain `flags: [raw]` reads no flags.
    - `flags: [bogus]`, a duplicate `flags`, `negative:⏎  phase: compile⏎`, and a file without frontmatter are metadata errors.

16. Through `build.zig` run steps on the installed Debug `fairpane-js-parse`:
    - `file tests/js/parse/valid.js`, containing the T9 source, exits with status 0, and standard output is the T9 dump and a newline.
    - `syntax.js` (`var 1;`) exits with 1 and prints `syntax-error unexpected_token @4`.
    - `unsupported.js` (`x => x`) exits with 2 and prints `unsupported arrow_function @2`.
    - `invalid-utf8.js` (bytes `76 61 72 20 FF`) exits with 3.
    - A missing path exits with 3.
    - No arguments exits with 3, and standard error contains `usage: fairpane-js-parse`.

17. The census on `tests/js/census/sound` exits with status 0.
    The tree holds:
    - `EXTRACT.json` with commit `0000000000000000000000000000000000000000`;
    - a `features.txt` whose proposal section lists `decorators` and whose standard section lists `let`;
    - `test/a.js`, valid `var a = 1;`;
    - `test/b.js`, a negative parse SyntaxError of `var 1;`;
    - `test/c.js`, `onlyStrict`, a negative parse SyntaxError of `with (a) {}`;
    - `test/d.js`, `noStrict`, `with (a) {}`;
    - `test/e.js`, `module`, `export var a;`;
    - `test/f_FIXTURE.js`;
    - `test/g.js`, features `decorators`, `@dec class A {}`;
    - `test/h.js`, block flags `raw`, `x => x`.

    The summary line is exactly `{"summary":{"discovered":7,"module":1,"proposal_files":1,"runs":9,"agree_valid":2,"agree_error":3,"unsupported":2,"limit":0,"proposal_mismatch":2,"false_accept":0,"false_syntax_error":0,"metadata_error":0,"input_error":0},"unsupported_by_code":{"arrow_function":1,"with":1}}`.

    The census on `tests/js/census/unsound` exits with status 1.
    That tree holds:
    - `test/i.js`, valid `"\07";`, which gives a `false_syntax_error` in strict mode;
    - `test/j.js`, a negative parse test of `var a;`, which gives a `false_accept` in both modes;
    - `test/k.js`, `flags: [bogus]`, which gives a `metadata_error`.

    Its summary reports `false_syntax_error` 1, `false_accept` 2, and `metadata_error` 1.
    The census refuses an existing output file and exits with status 3.

18. Controller tests in `tools/selftest.mjs` use the existing corpus fixture.
    - `corpus-extract` writes exactly the fixture blobs under `test/` and `harness/`, plus `features.txt`, with their contents.
    - It writes `EXTRACT.json` with the fixture commit, the tree, the file count, and `entries_sha256`.
    - It refuses a non-empty output directory and a directory outside `out/`.
    - It refuses a snapshot record whose commit is absent from the snapshot.
    - Its path check rejects `test/../x`, `test//x`, and `test/./x`.

19. FP-0011 case 20 lists every new `src/js` file and still passes.

### Mutation controls

Each control is recorded as a `.diff`, applied with `git apply`, run, and reversed with `git apply -R`.
The file hashes are recorded before and after each control.
A crash is recorded separately from a failed assertion.

- M1: the lexer treats U+2028 as white space.
  Case 2 (T31) must fail; amendment 2 removes case 14 from this control.
- M2: the strict check for LegacyOctalIntegerLiteral is removed.
  E19 must fail, and a census run must report `false_accept` greater than 0.
- M3: `=>` reports `syntax-error unexpected_token`.
  U16 must fail, and a census run must report `false_syntax_error` greater than 0.
- M4: the HTML-like comment handling is removed.
  T26 and T27 must fail.
- M5: the depth check uses `>=` instead of `>`.
  Case 10 must fail.
- M6: functions-to-initialize iterates forward.
  T8 must fail.
- M7: `corpus-extract` skips the blob-hash check, and a fixture blob is altered after listing.
  Case 18 must fail.
  The worker may instead show this with a direct unit test of the hash check, recorded the same way.

### Stop rules

- If a Debug test build overflows the 1 MiB stack of case 10 before depth 1024, stop.
  Report the largest depth that passes on that stack and the stack bytes per nesting level, and do not lower the bound without an integrator decision.
- If the census reports any `false_accept` or `false_syntax_error`, stop.
  Fix the parser within this contract, or report the file, the mode, and the ECMA-262 text if the case seems to be a Test262 or draft divergence.
  Never reclassify the case.
- If `discovered` differs from 53,616, `module` differs from 843, or `files` in `EXTRACT.json` differs from 53,975, stop and report.
- If the V8 oracle disagrees with any row of cases 2 or 6 other than E54, E55, and E56, stop and report the row.
- If any expected dump or offset in this contract contradicts the cited text, stop and report it.
  Never edit an expectation silently.

### Criterion mapping

| Plan criterion | Cases and evidence |
| --- | --- |
| Parse UTF-16 source with the Script goal over the frozen subset into a tree with strictness, declaration lists, and source ranges | 2 to 5, 9, 16 |
| Report unsupported constructs with owners, and syntax errors only where the full grammar rejects the source | 1, 6 to 9; M2, M3; census and oracle logs |
| Bound depth, length, and memory, and survive allocation failure and random input | 10 to 14; M5 |
| Parse-only census with zero accepted negative tests and zero false syntax errors | 15, 17; census logs; M2, M3 |
| Extract only from the verified snapshot with blob-ID checks | 18; extraction log; M7 |

### Remaining obligations

Each unsupported code names its owner in the table above.
The parser also leaves these runtime obligations to `FP-0083`:
- function name inference;
- the B.3.9 ReferenceError, which is thrown after the target is evaluated;
- Function.prototype.toString from the recorded source ranges.

## Evidence

Record every command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0082/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`.
Use `C:\src\fairpane\.tools\zig\0.18.0-dev.120+9fe22a29b\x86_64-windows\zig.exe` as the Zig executable.
Never delete or overwrite a log.
Name a log of a failed attempt with the suffix `-attempt-N`, and list it with its cause in the README.

1. Write cases 1 to 19 before the implementation.
   Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0082-before`.
   It must fail.
2. Record `tests-after.log` with `cmd /d /c ver` and then `zig build test --summary all --cache-dir out/fp0082-after`, after deleting that directory.
   It must exit with status 0 and show the test count.
3. Record `fmt.log` with `zig fmt --check build.zig src tests`.
   It must exit with status 0.
4. Record `controller-tests-after.log` with `node --version` and then `node tools/fairpane.mjs test`.
5. Write `raw/oracle-v8.mjs`, which lists every source of cases 2, 6, and 7 with this contract's expected validity.
   It parses each source with `vm.Script`.
   Record `oracle-v8.log` with `node --version` and the script.
   The only disagreements allowed among cases 2 and 6 are E54, E55, and E56.
   Case 7 rows are recorded for information only.
6. Record `js-tools-build.log` with `zig build js-tools -Doptimize=ReleaseSafe --summary all`.
7. Record `corpus-verify.log` with `node tools/fairpane.mjs corpus-verify test262`.
   It must exit with status 0.
8. Record `extract.log` with `node tools/fairpane.mjs corpus-extract test262 out/fp0082-test262`.
   It must report `files` 53,975.
9. Record `harness-parse.log` by running `zig-out/bin/fairpane-js-parse file` on `harness/assert.js`, `sta.js`, `doneprintHandle.js`, and `compareArray.js` in the extraction, and on `propertyHelper.js`.
   The first four must exit with status 0.
   `propertyHelper.js` must exit with status 2 and report `unsupported array_literal`.
10. Record `census.log` with `zig-out/bin/fairpane-js-parse census out/fp0082-test262 out/fp0082-census.jsonl`.
    Then record `cmd /d /c certutil -hashfile out\fp0082-census.jsonl SHA256`.
    The census must exit with status 0.
11. Record `mutation.log` and `mutation-<control>.diff` for M1 to M7.
    Each census-dependent control reruns the census into a new output file.
12. Write `engineering/evidence/FP-0082/README.md`.
    It gives the worktree `HEAD`, the criterion mapping, each control's result, the census summary with `unsupported_by_code`, every attempt, and every resolved ambiguity.

The integrator then does the following.

1. Record `HEAD` and `git status --porcelain=v1 --ignored --untracked-files=all` for every source root in `raw/integration-binding.log`, before and after the gates.
2. Run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0082/gates`.
3. Record an uncached `integration-tests.log`.
4. Rerun steps 6 to 10 at the integration commit.
5. Record `integrator-metadata-counts.log` with an independent script that counts discovered files, module-flagged files, and negative-parse files at the pinned commit.
   Those counts must equal the census's counts.

## Authority

Writable paths are `src`, `tests`, `tools`, `build.zig`, and `engineering/evidence/FP-0082/`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
`specs/applicability/test262.json` stays unchanged.
The integrator alone updates `engineering/plan.json`, `engineering/state.json`, and `engineering/HANDOFF.md`.
Required reviewers are `fairpane-review` and `fairpane-spec`.

## Non-goals

- No bytecode, interpreter, realm, or evaluation exists, and no Test262 test executes.
- No census result is reported as Test262 conformance.
- No Module goal, `eval`, Function constructor, or `ParseScript` host hook exists.
- No Unicode data is imported, and no non-ASCII identifier is accepted.
- No proposal syntax is accepted.
- No change is made to the C ABI, `include`, `api`, `specs`, or the gates.
- No parse-speed measurement is made, and no performance claim results.
- No Test262 file is copied into the repository.

## Amendments

1. Worker `FP0082Parser` reported two stop rules and two contract defects, and the integrator decides them as follows.
   - Stack: a recursive-descent parser in the Debug build uses about 3.8 KB of native stack per nested parenthesis, so it overflows a 1 MiB stack near depth 265.
     `parseScript` and `writeOutcome` therefore use native stack that does not grow with nesting depth.
     Nesting state lives in heap storage that `max_depth` and `max_memory_bytes` bound.
     Cases 10 and 11 stay as frozen, including the 1 MiB thread in the Debug test build, and `max_depth` stays 1024.
     A mutation control that restores one recursive call per parenthesized expression must fail case 10.
   - Case 2, row T32: the first source `a⏎(b)` is a call whose argument list holds `b` itself (ECMA-262 13.3.1 and 13.3.8; 12.10 inserts no semicolon), so its expected dump is `(expression (call (identifier a) (identifier b)))`.
   - Case 9 covers T1 to T41 except T30, because a HashbangComment is allowed only at the start of a Script (12.5), and the prefix moves it away from offset 0.
     For T30, the prefixed source gives `syntax-error invalid_character @14`, which case 9 asserts as its own row.
   - Every other expectation stays as frozen.
2. Control M1 cannot fail case 14 as frozen, as worker `FP0082Parser` reported.
   Case 14 asserts only that each random source yields an outcome and that `writeOutcome` succeeds without a panic or a leak, and treating U+2028 as white space changes outcomes without either.
   M1 must fail case 2 on row T31, which it does; case 14 stays a robustness property, and no requirement of the parser changes.

## Revision 1

Base: the commit that freezes this revision.
Source findings: `reviews/review-1-reject.json` and `reviews/spec-review-1-accept.json`.
Every section above stays in force except where this revision replaces it.
Writable paths stay as above.

### Integrator decisions

- Review 1 rejected `5d41509` for two major findings.
  `corpus-extract` checks path components only between `/` separators, while `path.join` on Windows also splits on `\`, so a hostile tree path such as `test/..\..\..\x.js` can write outside `out/`.
  `duplicateParameter` compares every parameter with every earlier one, so a strict function with many parameters takes quadratic time.
- Extraction and the Rust archive reader share one path rule.
  The rule moves from `acceptedArchivePath` in `tools/rust.mjs` into one function in `tools` that returns the reason a path is rejected, or null.
  `acceptedArchivePath` keeps its exact results and its message `The archive path is not accepted: <name>`, so FP-0079's cases pass unchanged.
  FP-0099's later fix of the reserved-name comparison then applies to both readers.
- Row E96 changes, as spec review 1 recommends.
  The full grammar continues `( )` and `( Expression , )` only with `=>`, through CoverParenthesizedExpressionAndArrowParameterList (13.2).
  The source therefore fails at the first token after the closing `)` that is not `=>`, with `unexpected_token`, or at the end of the input, with `unexpected_end` at the source length.
  An `=>` there keeps reporting `unsupported arrow_function` at `=>`, as the `arrow_function` trigger states.
- The note on `enum = 1` is decided by the code table, not by new behavior.
  Rows E93 and E100 freeze `unexpected_token` for a ReservedWord at the start of a statement, so a ReservedWord where no production continues with it keeps `unexpected_token`.
  The `unexpected_token` definition applies there, and `reserved_word` applies where a production expects an IdentifierReference, a BindingIdentifier, or a LabelIdentifier and finds a ReservedWord.
- The census `agree_error` class stays as frozen.
  Each census record already keeps the code and offset of every run, so a later audit can compare them with each test's intended error.
- Spec review 1's citation findings correct the text above as follows; behavior is unchanged.
  - Line 20: the parser reads UTF-16 code units, which matches 11.1 at every position where the subset accepts non-ASCII input, because a surrogate outside strings and comments yields `unsupported non_ascii_identifier`; FP-0095 pairs surrogates as 11.1.4 requires.
  - PropName is 8.6.5, and PropertyNameList is 13.2.5.4.
  - `function_declaration_position` also rests on 14.5, whose lookahead excludes `function` from an ExpressionStatement, and on B.3.3, which applies to non-strict code only; 14.7.5.1 and 14.11.1 join it when FP-0087, FP-0088, or FP-0096 make those statements supported.
  - The `async_function` trigger reports the `async (...) =>` form at the `async` token, as row U14 freezes.
  - `invalid_assignment_target` also covers an operand of an assignment or update operator that is not a LeftHandSideExpression, as rows E47 and E53 freeze.

### Behavior

- The shared path rule rejects, in this order, with these reasons:
  1. a code unit from U+0000 to U+001F: `a control character`;
  2. a `\` anywhere: `a backslash`;
  3. a `:` anywhere: `a colon`;
  4. then, for each `/`-separated component in order, an empty component: `an empty path component`; a `.` or `..` component: `a "." path component` or `a ".." path component`; a component that ends in `.` or a space: `a path component that ends in "." or a space`; and a component whose text before its first `.` is a reserved Windows device name, compared without regard to case: `a reserved Windows device name`.
  A rejected extraction entry fails with `<path> has <reason>.` before any directory or file is created.
- Before it writes a file, extraction also checks that the resolved file path starts with the resolved output directory followed by the path separator, and fails with `<path> resolves outside the output directory.` otherwise.
- Before it writes anything, extraction compares the pinned commit's tree with `tree` in the snapshot record and recomputes the inventory with the function that `corpus-verify` uses.
  A difference fails with `Corpus test262 failed extraction checks:` followed by one line per difference in the `corpus-verify` form, such as `- tree: recorded "<a>", found "<b>"` and `- inventory.sha256: recorded "<a>", found "<b>"`.
- Duplicate parameters are found in time linear in the number of parameters, through a hashed set, and the reported offset stays the first parameter that repeats an earlier name.
  A counter that only test builds compile counts the name comparisons of the duplicate check.
- After `( )` or `( Expression , )`, a token other than `=>` reports `syntax-error unexpected_token` at that token, and the end of the input reports `syntax-error unexpected_end` at the source length.
- `parse` allocates no write stack; the stack is allocated when a caller writes the tree.
  `keywordOf` selects candidates by length and first code unit instead of scanning every keyword.
  `scanNumber` passes the source slice to the numeric conversion when the literal has no separator and needs no rewriting.
- The comment at `src/js/parser.zig` line 769 cites the third condition of rule 1 in 12.10.1, and the module comment of `src/js/lexer.zig` states the code-unit reading as the first decision above does.

### Exact test cases

1. Case 6, row E96, becomes `E96 () ⇒ syntax-error unexpected_end @2`.
   Case 6 gains `E96a () + 1 ⇒ syntax-error unexpected_token @3`, `E96b (a,) ⇒ syntax-error unexpected_end @4`, and `E96c (a,) + 1 ⇒ syntax-error unexpected_token @5`.
   Row U18, `() => 1 ⇒ unsupported arrow_function @3`, already freezes the `=>` form and stays.
   If any other frozen row would change, stop and report it.
2. Case 18 gains these controller tests.
   Each builds a fixture repository whose tree holds the named path with `git mktree`, runs `corpus-extract` in the temporary root that the controller tests create, and asserts the exact message, that the output directory stays absent or empty, and that no file appears at the path that an escape would reach:
   `test/..\..\..\x.js` (`a backslash`), `test/a:b.js` (`a colon`), `test/a<U+0001>b.js` (`a control character`), `test/dir./x.js` and `test/x.js ` (`a path component that ends in "." or a space`), and `test/CON.js`, `test/aux/x.js`, and `test/Com1.txt.js` (`a reserved Windows device name`).
   A unit test of the shared rule gives each listed reason for one path and null for `test/a/b.js` and `harness/assert.js`.
   FP-0079 case 5 keeps passing unchanged.
3. Case 18 gains an altered-tree test.
   It replaces the loose object file of the `test/` subtree of the fixture commit's tree with a valid zlib stream of a different tree under the same object ID, runs `corpus-extract`, and asserts the `inventory.sha256` line and an absent or empty output directory; revision amendment 1 replaced the root tree with the subtree.
   A second test edits `tree` in the fixture snapshot record and asserts the `tree` line.
4. A new parser case: a function `function f(a0, a1, ..., a9999) { "use strict"; }` and a script that begins `"use strict";` and declares `function g(a0, ..., a9999) {}` each parse, and the duplicate check counts at most 20,000 comparisons for each.
   With `a0` added as a last parameter, each reports `syntax-error duplicate_parameter` at that parameter's offset.
5. The metadata case's invalid-phase row becomes `negative:⏎  phase: compile⏎  type: SyntaxError⏎`, and it asserts the reason `a phase outside the known set`.

Cases 1 to 3 must fail on `5d41509` before the change; the README names any part that the old code already meets.
Case 4's bound needs the comparison counter, which the base lacks, so control M11 shows that the bound fails for a quadratic check.
Case 5 passes on the base, which checks the phase before the type, so control M12 shows that it fails without the phase check.
The worker records every row of case 1 on `5d41509` as it is.

### Mutation controls

- M9: the shared rule stops rejecting `\`.
  Case 2's backslash row must fail.
- M10: extraction skips the inventory recomputation.
  Case 3's altered-tree test must fail.
- M11: the duplicate check compares every pair again.
  Case 4 must fail on its comparison bound.
- M12: the metadata reader stops checking the phase.
  Case 5 must fail.
- Controls M1 to M8 are rerun on the revised sources, each after a recorded `git apply --check` of its diff against them.
  A diff that no longer applies is regenerated against the revised file and recorded with its new hash.

### Revision 1 evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0082/raw/`, with the suffix `-r1`, and keep each failed attempt as its own log.

1. `tests-before-r1.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. An uncached `tests-after-r1.log`, `fmt-r1.log`, and `controller-tests-after-r1.log`.
3. `mutation-r1.log` and its diffs for M1 to M12, with the hash of each changed file before, during, and after.
4. `census-r1.log` with a fresh extraction and census at the revised commit; every summary count must equal the counts in "Integration" of the README.
5. The README gains a `## Revision 1` section and corrects review 1's two README findings: the four proposal mismatches are four `noStrict` files, run once each in non-strict mode, and the opening line names amendments 1 and 2.

The integrator records `git diff --stat a3e5cf9 <revision commit> -- AGENTS.md docs/CHARTER.md engineering/qualification.json engineering/policy.json engineering/gates.json toolchains specs` and confirms that it is empty.

### Revision 1 amendments

1. Worker `FP0082Revision1` showed that case 3 as frozen cannot reach the inventory comparison.
   Git rehashes the root tree object when `git ls-tree -r` reads it, so a replaced root tree makes Git exit with status 128 and `hash mismatch`, which `raw/tests-before-r1.log` records.
   Git does not rehash the subtrees that it reads during the recursion, so a replaced subtree changes the listing without an error.
   Case 3 therefore replaces the `test/` subtree, and its assertions stay as frozen.
   The worker records that probe as `raw/probe-subtree-r1.log`, and the README states both behaviors.
   M10 must still fail case 3.
2. Spec review 2 corrects the basis of the E96 rows; their behavior and every frozen row stay as they are.
   The context-free grammar accepts `( )` and `( Expression , )` as a PrimaryExpression through CoverParenthesizedExpressionAndArrowParameterList (13.2).
   The rejection is the 13.2.9.1 early error, which requires the cover to cover a ParenthesizedExpression, and 5.1.4 step 4 makes a failed reparse an early Syntax Error.
   `unexpected_token` and `unexpected_end` therefore also report such a cover, at the first token after `)` that is not `=>`, or at the end of the input.
   The two code comments that call it a grammar failure, at the E96 rows and `arrowParametersOnly` in `src/js/parser.zig`, are corrected by `FP-0090` when it implements arrow functions.
   The emitted code table of case 1 stays frozen and is not authoritative for citations; this contract's code table is.

## Revision 2

Base: the commit that freezes this revision.
Source findings: `reviews/review-2-reject.json`.
Every section above stays in force except where this revision replaces it.
Writable paths stay as above.

### Integrator decisions

- Review 2 rejected `9a68167` for two major findings, which share one cause: a parser-wide hash set sized for the largest earlier body.
  `params_seen` and `seen` are emptied with `remove`, which leaves tombstones in the pinned standard library, so after one large body every later lookup can probe up to the large capacity.
  `function_names` is emptied with `clearRetainingCapacity`, which writes metadata over the whole retained capacity for every body.
  In both cases the work of a small body depends on the largest earlier body, so a hostile script of a few megabytes can cost far more than the limits imply.
- Every set that the parser fills per function or per body costs work in proportion to that body's own names, whatever came before, and a nested body never drops entries that an enclosing body still needs.
  For example, a set may be released and rebuilt when its capacity exceeds four times `@max(n, 8)` for the current count `n`, or kept per body and dropped at the body's end; no set is emptied with `remove`.
- Hash flooding of parser-internal sets with crafted names is a separate hardening question, because the sets use a fixed seed.
  It is recorded as an obligation of `FP-0026`'s frontier decomposition, together with the engine's other internal hash maps.
- Review 2's minor and notes are folded in: the README sentence about `git apply --check` is annotated in place, the path rule gains rows with several defects, extraction rejects paths that differ only in letter case before it creates anything, as the Rust archive reader does, and the `writeOutcome` doc comment states the write stack's bound.
  `FP-0099` confirms the reserved device names against Microsoft's page and updates the one shared rule.

### Exact test cases

1. A new parser case parses one strict script holding, in order, a function with 10,000 distinct parameters and 10,000 distinct `var` declarations and 10,000 function declarations in its body, and then 2,000 functions with five distinct parameters, five `var` declarations, and five function declarations each.
   After each function's checks, the capacity of each per-body set is at most four times `@max(n, 8)`, where `n` is that function's own count; a test-only accessor reads the capacities.
   The case also checks every outcome: the script parses, and the same script with a repeated parameter in the 2,000th small function reports `syntax-error duplicate_parameter` at that parameter.
2. Case 18 gains a row for each adjacent pair of path rules, each with both defects, such as `test\a:b.js`, which gives `a backslash`, and a row with two tree paths that differ only in letter case, which extraction rejects with `<path> differs from <other path> only in letter case.` before it creates the output directory.

Case 1 must fail before the change, on the capacity bound.
Case 2's case-collision row must fail before the change; its order rows pass before the change, which the README records.

### Mutation controls

- M14: `params_seen` is emptied with `remove` again; case 1 must fail on the capacity bound or its work.
- M15: `function_names` keeps its largest capacity; case 1 must fail on the capacity bound.
- M16: extraction skips the letter-case check; case 2's collision row must fail.

### Revision 2 evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0082/raw/`, with the suffix `-r2`, and keep each failed attempt as its own log.

1. `tests-before-r2.log` on the base, with `HEAD`, the staging command, and the blob ID of every staged file.
2. An uncached `tests-after-r2.log`, `fmt-r2.log`, `controller-tests-after-r2.log`, and `census-r2.log` with a fresh extraction and census whose summary counts equal the README's.
3. `mutation-r2.log` and its diffs for M14 to M16, with the hash of each changed file before, during, and after, and a recorded `git apply --check` of M1 to M13 against the revised sources.
4. The README gains a `## Revision 2` section.

### Revision 2 amendments

1. The integrator's FP-0107 binding found that case 17's sound and unsound census steps fail on a rerun in a local cache that holds their earlier output.
   The census refuses an existing `<out.jsonl>`, as "Census" requires, and both steps name `census.jsonl` in an output directory that the pinned build runner reuses for the same inputs and never empties.
   When a run writes that file but does not finalize the step's cache manifest, as an interrupted run does, every later `zig build test` in that cache fails both steps with `PathAlreadyExists`, until someone deletes the directory.
   `raw/census-rerun-5-lost-manifest.log` deletes the two steps' manifests and keeps their outputs, and `raw/census-rerun-6.log` then fails with `Build Summary: 97/100 steps succeeded (2 failed)`.
   The integrator's gate run at 18:02 UTC failed the same way (`engineering/evidence/FP-0107/gates/2026-10-09T18-02-06-479Z-zig-test-9b503199.json`) without a known interruption, and `raw/census-rerun-1.log` to `raw/census-rerun-4.log` show that an immediate rerun and a run after an install from another cache directory both pass, so that run's trigger is unknown.
   Revision 2 therefore adds this rule: both census steps pass in a cache whose output directories already hold `census.jsonl` from a run without a manifest.
   The census keeps refusing an existing `<out.jsonl>` that a caller names, and the refusal row of case 17 stays as frozen.
   The worker chooses the mechanism, such as a census option that replaces the file and that only these two steps pass, or a step whose output path cannot exist before it runs, and the README states why the mechanism cannot hide a census failure.
   Case 3 of revision 2 repeats the reproduction with recorded commands: a passing `zig build test --summary all` with a fresh `--cache-dir`, a recorded deletion of both census steps' manifests in that cache that keeps their outputs, and a second run in that cache, which must pass with both census steps executed rather than cached.
   It must fail before the change, as `raw/census-rerun-6.log` shows, and its logs are `census-rerun-before-r2.log` and `census-rerun-after-r2.log`.
2. Worker `FP0082Revision2` found that case 13 failed with `NondeterministicMemoryUsage` after the set rework.
   `raw/probe-allocations-r2.log` shows that the base's allocation count already varied from 29 to 31 across twelve perturbed runs, so the base passed case 13 only because its runs happened to get the same placement.
   The integrator accepts the worker's change outside the list above: the parser's `Limiter` refuses every resize and remap, so that its allocation count does not depend on the backing allocator's state.
   A new test asserts that determinism, and control M17, which restores resize and remap, must fail case 13 and that test.
   Evidence item 3 names M1 to M13, but this contract defines no M13; the recorded `git apply --check` covers M1 to M12 and M7-r1, and M6-r2 and M11-r2 replace the two controls that no longer apply to the revised parser.