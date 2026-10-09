# FP-0014 evidence

## Scope

Task `FP-0014` implements initial CSS syntax and cascade.
The frozen contract is `engineering/evidence/FP-0014/CONTRACT.md`, based on commit `1158696`.
The integrator amended it twice during the work; see "Contract amendments".
The isolated `fairpane-core` worker `FP0014Css` wrote the patch in its own working tree and committed nothing.

## Changed files

| File | Change |
| --- | --- |
| `src/root.zig` | Exports `css` and references it in the library test block. |
| `src/dom.zig` | Attribute lists, `setAttribute`, `attribute`, `removeAttribute`, `attributes`, `elementId`, `classes`, `NotAnElement`, attribute teardown in `sweep` and `deinit`, and cases 18 to 20. |
| `src/css/css.zig` | The public module, its stage list, and the remaining obligations. |
| `src/css/tokenizer.zig` | "Filter code points" and "consume a token" with every algorithm that it calls. |
| `src/css/parser.zig` | The token stream, every entry point of Syntax 5.4, the parser algorithms of 5.5, and the validator interface. |
| `src/css/dump.zig` | The frozen dump format. |
| `src/css/stylesheet.zig` | Syntax section 8 with the frozen-subset validator and its diagnostics. |
| `src/css/selectors.zig` | Selector parsing, specificity, matching, and `matchRules`. |
| `src/css/registry.zig` | `PropertyId`, the registry table, `validate`, `lookup`, and the custom property family. |
| `src/css/properties.zig` | The property records, as data only. |
| `src/css/named_colors.zig` | The 148 named colors, as data only. |
| `src/css/values.zig` | Declared-value grammars and computed values. |
| `src/css/cascade.zig` | The cascade sort and the explicit-defaulting rollback. |
| `src/css/substitution.zig` | `var()`, its argument grammar, the spread syntax check, and the resumable substitution. |
| `src/css/compute.zig` | `computeStyle`, `ComputedStyle`, and `diff`. |
| `src/css/style.zig` | `resolve` and `StyleMap`. |
| `src/css/tests.zig` | Cases 1 to 17 and 21 to 48, and one palette contrast test. |
| `engineering/evidence/FP-0014/README.md` and `raw/` | This record and its logs. |

The laboratory, the C ABI, `include`, `api`, `tests`, `tools`, `build.zig`, and every protected path are unchanged.

## Logs

Each Zig command ran with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, which each RESULT line shows.

| Log | Exit status | Result |
| --- | --- | --- |
| `raw/tests-before-attempt-1.log` | 1 | The first tests-before run, with the test file before amendment 2. |
| `raw/tests-before.log` | 1 | `zig build test --summary all --cache-dir out/fp0014-cache-before` in `out/fp0014-before`, a `git archive` export of the base with the final `src/css/tests.zig`, the final `src/root.zig`, a `src/css/css.zig` that only imports the tests, and the base `src/dom.zig` with cases 18 to 20 appended. Compilation fails because no implementation file exists. |
| `raw/fmt-attempt-1.log` | 0 | `zig fmt --check build.zig src tests` before amendment 2. |
| `raw/fmt.log` | 0 | `zig fmt --check build.zig src tests` on the final tree. |
| `raw/tests-after-attempt-1.log` | 0 | The first uncached run, before amendment 2: 227 of 227 tests. |
| `raw/controller-tests-after-attempt-1.log` | 1 | The first `node tools/fairpane.mjs test`, before amendment 2: 180 of 181, because the repository check rejected the `.zon` imports. |
| `raw/tests-after.log` | 0 | Uncached `zig build test --summary all --cache-dir out/fp0014-cache-after` on the final tree: 58 of 58 steps, 227 of 227 tests (194 unit tests and 33 text tests). |
| `raw/controller-tests-after.log` | 0 | `node tools/fairpane.mjs test` on the final tree: 181 of 181. |
| `raw/mutation-cascade-origin-attempt-1.log` | 0, 1, 0 | The mutation control on the tree before amendment 2: digest, mutated build (226 of 227, only case 35 fails), digest. |
| `raw/mutation-cascade-origin.log` | 0, 1, 0 | The mutation control on the final tree: digest, mutated build, digest. |

`node tools/fairpane.mjs check` passes on the final tree.

## Mutation control

`raw/mutation-cascade-origin.diff` swaps the precedence of important user declarations and important author declarations in `originPrecedence`.
`raw/mutation-cascade-origin.log` records the SHA-256 of `src/css/cascade.zig`, the mutated `zig build test --summary all --cache-dir out/fp0014-cache-mutation`, and the SHA-256 after the revert.
The mutated build exits with status 1: 226 of 227 tests pass, and the only failure is "FP-0014 case 35: origin and importance decide before specificity, in the six-level order".
Both digests are `c98a9521b39f08d2cfced231bf9ed7bc1c9f2cc580401c002692f765a2fe8f9b`, so the revert restored the file that `raw/tests-after.log` tested.

## Contract amendments and stop-rule observations

1. Case 39.
   The frozen string ended `block([)[ident(y)]]]`, with one closing bracket more than four lists need.
   The worker observed `[ident(Foo) ws ws function(bar)[number(1,integer,none) , ws block({)[ident(x)]] ws block([)[ident(y)]]`, which matches the contract's dump format (`block([)[ITEMS]`) and Syntax 5.5.9, and reported it under the stop rule.
   The integrator's amendment 1 (commit `43edcec` in the integration checkout) corrected the expected value to that string, and case 39 asserts it.
   The failing observation came from an unrecorded scratch run, so no attempt log exists for it.
2. Data files.
   The first controller run failed test 181 with "Unapproved module import in src/css/registry.zig: properties.zon", because `checkRepository` accepts only `.zig` imports.
   The worker reported it and changed no gate rule.
   Amendment 2 (commit `1323095`) replaced `properties.zon` and `named_colors.zon` with the data-only `properties.zig` and `named_colors.zig`, imported by relative path, as `src/unicode/tables.zig` does.
   Case 30 reads `named_colors.zig` directly.

No cited source contradicted any other expected value.

## Resolved ambiguities

- `Tokenizer.next` takes the allocator for token strings, because the contract's `init` takes none and every allocating function takes the caller's allocator.
- Case 32 writes the contract's expressions with `f64` operands, such as `10.0 * 96.0 / 25.4` evaluated in `f64` from left to right, as the contract requires of the engine; Zig would otherwise evaluate a literal expression exactly at compile time.
  No expected value changed.
- The parser asks the validator about a qualified rule's prelude when it reaches the rule's block, and about the rule when the block ends, so diagnostics follow source order.
  `parseRule` checks in the `top_level` context, and `parseBlockContents` and `parseDeclaration` check in the `qualified_rule_block` context.
- The block of a rule that looks like a custom property (Syntax 5.5.3) is consumed without validator calls, because its result is discarded.
- A `unicode-range` declaration retokenizes the source of every token that "consume a list of component values" returned, as 5.5.6 step 8 states, including trailing whitespace.
- A custom property name string (Syntax 5.5.6) is any name that starts with two hyphen-minus characters; a custom property name (Variables 2) excludes `--`.
- Rules and declarations inside an at-rule's block are dropped with the at-rule, without their own diagnostics.
  A declaration inside a nested qualified rule is still checked, so its diagnostic precedes the rule's `nested_rule_ignored`.
- `var()` arguments drop leading and trailing whitespace, inside a `{}` wrapper too; a first argument of only whitespace fails the argument grammar.
- The spread syntax is detected when its `var()` is substituted, as "substitute early-invoked functions" would run; the reason `unsupported_value` follows nested substitutions of the same property.
- Custom properties compute on demand with memoized values; a reference to a property that is being substituted marks the guard stack from its entry, as Values 5 Appendix A requires.
  A custom property that becomes invalid at computed-value time also appears in `StyleMap.diagnostics`.
- Attribute `~=` splits on ASCII whitespace (tab, LF, FF, CR, and space), because document strings are not preprocessed.
- `[ns|*]` reports `unsupported_selector`, as the contract's rule for an ident, a `|`, and an ident or `*` states.
- The root element's blockification also applies to an initial or inherited `display`, so a root under no stylesheet computes block flow (case 34).
- `ApplicableDeclaration`, `Origin`, `Order`, and `RuleIdentity` live in `cascade.zig`; `stylesheet.Origin` is the same type.
- `computeStyle` also takes the scratch allocator, the result arena, and the diagnostics list; a failure restores the list.
- A `StyleMap` borrows the stylesheets and the store, which must outlive it.
- `parseGrammar` takes component values and a grammar value with `Result` and `match`; `values.DeclaredGrammar` and `values.StandardGrammar` are the grammars that `stylesheet.zig` and `compute.zig` use, and `values.zig` uses `parseGrammarList` for legacy `rgb()` arguments.
- Case 48 fails every remap in its backing allocator, as commit `6771856` does for every allocation-failure check.

## Remaining obligations

| Obligation | Current engine behavior | Owner task |
| --- | --- | --- |
| Stylesheet byte decoding and `@charset` sniffing | No API; the entry points take decoded strings | `FP-0069` |
| HTML documents, quirks mode, and HTML case rules for selectors | Every store document is an XML document in no-quirks mode | `FP-0070` |
| Pseudo-classes, pseudo-elements, `:is()`, `:not()`, `:where()`, `:has()`, nesting, and `@namespace` | `unsupported_selector`, `nested_rule_ignored`, `nested_declarations_ignored`, or `ignored_at_rule` | `FP-0070` |
| Every at-rule | `ignored_at_rule` | `FP-0069` |
| Every property outside the registry, including shorthands and logical properties | `unknown_property` | `FP-0071` |
| Excluded `color`, `display`, `font-size`, and unit forms | `unsupported_value` | `FP-0071` |
| Math functions | `unsupported_value` | `FP-0071` |
| The Values 5 spread syntax | Invalid at computed-value time with `unsupported_value` | `FP-0071` |
| Cascade layers, encapsulation contexts, style attributes, presentational hints, and animation and transition origins | No input | `FP-0072` |
| A user-agent stylesheet for HTML | None | `FP-0072` |
| CSSOM, serialization, and `getComputedStyle` | No API | `FP-0073` |
| Incremental invalidation | `diff` reports effects, and resolution always recomputes every element | `FP-0074` |
| Laboratory style wiring | `style` reports `unsupported` | `FP-0068` |

## Integrator actions

- Compare every row of `src/css/named_colors.zig` with the named-color table of `css-color-4/Overview.bs` at the pinned commit; the worker transcribed the rows from that table.
- Record `HEAD` and status, then run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0014/gates`.
