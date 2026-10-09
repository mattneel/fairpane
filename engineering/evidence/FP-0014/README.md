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

No log in `raw/` records `node tools/fairpane.mjs check` on the worker tree.
The integration receipt `gates/2026-10-09T11-43-15-320Z-repo-check-c749976d.json` records `repo-check` with status `pass` at `ef8ad1c`.

## Mutation control

`raw/mutation-cascade-origin.diff` swaps the precedence of important user declarations and important author declarations in `originPrecedence`.
`raw/mutation-cascade-origin.log` records the SHA-256 of `src/css/cascade.zig`, the mutated `zig build test --summary all --cache-dir out/fp0014-cache-mutation`, and the SHA-256 after the revert.
The mutated build exits with status 1: 226 of 227 tests pass, and the only failure is "FP-0014 case 35: origin and importance decide before specificity, in the six-level order".
Both digests are `c98a9521b39f08d2cfced231bf9ed7bc1c9f2cc580401c002692f765a2fe8f9b`, so the revert restored the file that the control started from.
The control ran in the worker tree, and no log compares that digest with `src/css/cascade.zig` at `ef8ad1c`.
Revision 1 reran the control on the revised tree; see "Revision 1".

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
- Before revision 1, rules and declarations inside an at-rule's block were still checked, so `@media x { b { colour: red } }` reported `unknown_property` before `ignored_at_rule`, as review 1 found.
  Revision 1 consumes the block of every ignored at-rule without validator calls; see "Revision 1".
  A declaration inside a nested qualified rule of a style rule is still checked, so its diagnostic precedes the rule's `nested_rule_ignored`.
- `var()` arguments drop leading and trailing whitespace, inside a `{}` wrapper too; a first argument of only whitespace fails the argument grammar.
- The spread syntax is detected when its `var()` is substituted, as "substitute early-invoked functions" would run; the reason `unsupported_value` follows nested substitutions of the same property.
- Custom properties compute on demand with memoized values; a reference to a property that is being substituted marks the guard stack from its entry, as Values 5 Appendix A requires.
  A custom property that becomes invalid at computed-value time also appears in `StyleMap.diagnostics`.
- Attribute `~=` splits on ASCII whitespace (tab, LF, FF, CR, and space), because document strings are not preprocessed.
- `[ns|*]` reports `unsupported_selector`, as the contract's rule for an ident, a `|`, and an ident or `*` states.
- The root element's blockification also applies to an initial or inherited `display`, so a root under no stylesheet computes block flow (case 34).
- `ApplicableDeclaration`, `Origin`, `Order`, and `RuleIdentity` lived in `cascade.zig` before revision 1, which moved them, with `Specificity`, into `applicable.zig`; `stylesheet.Origin` is the same type.
- `computeStyle` also takes the scratch allocator, the result arena, and the diagnostics list; a failure restores the list.
- A `StyleMap` borrows the stylesheets and the store, which must outlive it.
- `parseGrammar` takes component values and a grammar value with `Result` and `match`; `values.DeclaredGrammar` and `values.StandardGrammar` are the grammars that `stylesheet.zig` and `compute.zig` use, and `values.zig` uses `parseGrammarList` for legacy `rgb()` arguments.
- Case 48 fails every remap in its backing allocator, as commit `6771856` does for every allocation-failure check.

## Remaining obligations

| Obligation | Current engine behavior | Owner task |
| --- | --- | --- |
| Stylesheet byte decoding and `@charset` sniffing | No API; the entry points take decoded strings | `FP-0069` |
| HTML documents, quirks mode, and HTML case rules for selectors | Every store document is an XML document in no-quirks mode | `FP-0070` |
| Pseudo-classes, pseudo-elements, `:is()`, `:not()`, `:where()`, `:has()`, nesting, `@namespace`, and the column combinator | `unsupported_selector`, `nested_rule_ignored`, `nested_declarations_ignored`, or `ignored_at_rule` | `FP-0070` |
| A constant-time ancestor filter for selector matching in deep trees | Matching walks the ancestors, with an early exit | `FP-0070` |
| Every at-rule | `ignored_at_rule` | `FP-0069` |
| Every property outside the registry, including shorthands and logical properties | `unknown_property` | `FP-0071` |
| Excluded `color`, `display`, `font-size`, and unit forms | `unsupported_value` | `FP-0071` |
| Math functions | `unsupported_value` | `FP-0071` |
| The Values 5 spread syntax, and the arbitrary substitution functions `if()`, `inherit()`, `attr()`, `ident()`, and `random-item()` | Invalid at computed-value time with `unsupported_value` | `FP-0071` |
| Cascade layers, encapsulation contexts, style attributes, presentational hints, and animation and transition origins | No input | `FP-0072` |
| A user-agent stylesheet for HTML | None | `FP-0072` |
| CSSOM, serialization, and `getComputedStyle` | No API | `FP-0073` |
| Incremental invalidation | `diff` reports effects, and resolution always recomputes every element | `FP-0074` |
| Laboratory style wiring | `style` reports `unsupported` | `FP-0068` |

## Integrator actions

- Compare every row of `src/css/named_colors.zig` with the named-color table of `css-color-4/Overview.bs` at the pinned commit; the worker transcribed the rows from that table.
- Record `HEAD` and status, then run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0014/gates`.

## Integration

The integrator applied the patch without conflicts and committed it as `ef8ad1c`.
The merged tree also holds the FP-0008, FP-0013, and FP-0050 changes that landed after the worker's base, and case 48 already uses the remap-failing backing allocator of commit `6771856`.

`raw/named-colors-check.log` records `HEAD` `ef8ad1c`, a fresh download of `css-color-4/Overview.bs` at `58354dac99cc8783a9b7b28957ece56bb48579eb` with SHA-256 `5b0be760…`, and `raw/named-colors-check.mjs`.
The script reads the 148 rows of section 6.1, checks each row's hexadecimal form against its decimal form, and compares the rows with `src/css/named_colors.zig` by position, name, and value.
It reports 148 rows on each side and result `pass`, with exit status 0.

One uninterrupted sequence ran on `ef8ad1c`, with no commit or source edit during it.
`raw/integration-binding.log` records `HEAD` `ef8ad1c` and an empty status, including ignored files, for every source root before the gates, and both again after the last run.

- `gates/2026-10-09T11-43-15-320Z-repo-check-c749976d.json`
- `gates/2026-10-09T11-43-15-648Z-controller-test-39b1d226.json`, with 192 of 192 controller tests.
- `gates/2026-10-09T11-43-50-490Z-zig-fmt-239185c0.json`
- `gates/2026-10-09T11-43-50-779Z-zig-test-64e8acf0.json`

`raw/integration-tests.log` runs `zig build test --summary all` with the fresh local cache `out/fp0014-integration-cache` and the recorded override `ZIG_GLOBAL_CACHE_DIR`: 65 of 65 build steps and 272 of 272 tests.
`raw/integration-bun.log` records Bun 1.4.2 with 192 of 192 controller tests.

## Revision 1

### Scope

Revision 1 implements `## Revision 1` of `CONTRACT.md`, which answers `reviews/review-1-reject.json`.
The isolated `fairpane-core` worker `FP0014R1` wrote the patch in its own working tree at base `b0e8e33` and committed nothing.
`raw/base-r1.log` records `HEAD` `b0e8e33` and an empty `git diff --stat 82ba854 b0e8e33 -- src build.zig tests`, so the base has the same source as commit `82ba854`, which froze revision 1.
Every revision 1 log ran in that working tree, `C:\Users\requi\.omp\wt\t8ee29f43a\m`, which each RESULT line shows.

### Changed files

| File | Change |
| --- | --- |
| `src/css/applicable.zig` | New module with `Specificity`, `Origin`, `Order`, `RuleIdentity`, and `ApplicableDeclaration`; it imports no DOM and no selector code. |
| `src/css/cascade.zig` | Uses `applicable.zig` and no longer imports `selectors.zig`. |
| `src/css/selectors.zig` | The column combinator reports `unsupported_selector`; matching keeps a stack of open combinators with the early exit; class matching uses `dom.Store.hasClass`; `Specificity` and `ApplicableDeclaration` come from `applicable.zig`; a test-only compound-match counter. |
| `src/css/stylesheet.zig` | The validator silences the block of every ignored at-rule; `Origin` comes from `applicable.zig`. |
| `src/css/parser.zig` | The validator hook `atRuleBlock`, asked when the parser reaches an at-rule's block, and an at-rule's own check kept separate from its block's silence. |
| `src/css/substitution.zig` | Recognizes `if()`, `inherit()`, `attr()`, `ident()`, and `random-item()` as arbitrary substitution functions, for `containsUnsupportedFunction` and for the spread syntax. |
| `src/css/compute.zig` | `ComputedStyle.defaulted`, and a custom property that contains an unsupported arbitrary substitution function computes to the guaranteed-invalid value with `unsupported_value`. |
| `src/css/style.zig` | `StyleMap.textStyle` returns `ComputedStyle.defaulted` of the parent element's style by value. |
| `src/css/values.zig` | `grid-lanes`, `inline-grid-lanes`, and `math` join the unsupported `display` keywords. |
| `src/css/css.zig` | Exports `applicable` and lists the new obligations. |
| `src/css/tests.zig` | Case 22 moves `a\|\|b`; cases 49 to 54, where case 54 is the palette test with the `ButtonBorder` and `Canvas` pair; API migration in cases 21, 34, and 47. |
| `src/dom.zig` | `classes` takes an allocator and deduplicates in `n log n` time; `hasClass`; `ClassIterator` is removed; a test-only class-token comparison counter; case 19 and case 20 migrate to the new `classes`; one new test, "FP-0014 revision 1: classes deduplicate in order, hasClass agrees, and both reject non-elements", which also runs `checkAllAllocationFailures` over `classes`. |
| `engineering/evidence/FP-0014/README.md` and `raw/` | This section, the corrections above, and the revision 1 logs and diffs. |

`src/root.zig`, `build.zig`, `tests`, and every protected path are unchanged.

### Logs

Each Zig command ran with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, which each RESULT line shows.

| Log | Exit status | Result |
| --- | --- | --- |
| `raw/base-r1.log` | 0, 0 | `git rev-parse HEAD` and `git diff --stat 82ba854 b0e8e33 -- src build.zig tests`, which prints nothing. |
| `raw/sources-r1.log` | 0, 0, 0, 0, 0, 0 | The SHA-256 of the pinned source copies, then `sed -n` of each cited line. |
| `raw/tests-before-r1-attempt-1.log` | none | The shell removed the backslashes from the compiler path, so `record` reported "The executable is not on PATH" and ran nothing. |
| `raw/tests-before-r1.log` | 1 | `zig build test --summary all --cache-dir out/fp0014-cache-before-r1` on the before tree: 271 of 277 tests, and the failures are cases 22, 49, 50, 51, 52, and 53. |
| `raw/tests-before-r1-compare.log` | 0, 0, 0, 0, 1 | Rebuilds the before tree's `src/css/tests.zig` in `out/r1check` from `b0e8e33` and `raw/tests-before-r1.diff`, then `diff` against the revised file, which prints the differences. |
| `raw/tests-after-r1-attempt-1.log` | 0 | The first run on the revised tree, with the fresh cache `out/fp0014-cache-after-r1-attempt-1`: 65 of 65 steps and 278 of 278 tests. |
| `raw/mutation-r1.log` | 0, 0, 0, 1, 0, 0 | Digests, `git apply raw/mutation-r1.diff`, digests, the mutated build, `git apply -R`, and digests. |
| `raw/mutation-cascade-origin-r1.log` | 0, 0, 0, 1, 0, 0 | The cascade control of the original contract on the revised tree, in the same order. |
| `raw/tests-after-r1.log` | 0, 0 | The digests of `src/css/selectors.zig` and `src/css/cascade.zig`, then uncached `zig build test --summary all --cache-dir out/fp0014-cache-after-r1`: 65 of 65 steps and 278 of 278 tests (233 unit tests and 45 text tests). |
| `raw/fmt-r1.log` | 0 | `zig fmt --check build.zig src tests`. |
| `raw/controller-tests-after-r1.log` | 0 | `node tools/fairpane.mjs test`: 192 of 192. |
| `raw/check-r1.log` | 0 | `node tools/fairpane.mjs check`: result `pass`. |

### The run before the fix

The before tree is base `b0e8e33` with `raw/tests-before-r1.diff` applied.
That diff adds cases 49 to 54, moves `a||b` in case 22, and adds the two test-only counters to the base code without changing its behavior.
At the base, the class-token counter counts the comparisons in `ClassIterator.occursBefore` and in the matcher's class loop.
Between that run and the revised tree, `src/css/tests.zig` changed only to follow the revised APIs, as `raw/tests-before-r1-compare.log` shows: case 49 reads `textStyle` by value instead of through a pointer, the `classCount` helper of case 53 uses the allocating `classes`, and cases 21, 34, and 47 use `applicable.zig` and the by-value `textStyle`.

Each revision 1 case runs every part and, when it fails, names each failing part and each passing part.
`raw/tests-before-r1.log` shows the following:
- Case 49 fails "display is inline flow" and "every margin is 0px"; its parts for `color`, `font-size`, and `--k` already pass.
- Case 50 fails "one ignored_at_rule diagnostic for media", with 4 diagnostics instead of 1; "only the rule for d is kept" already passes.
- Case 51 fails for each of `--a` to `--f`; the part for `--g` already passes.
- Case 52 fails every part: the six `display` values and `a||b`.
- Case 53 fails both parts: 16244657 compound-match attempts after the element at depth 140 exceed the bound 16008000, and matching `.c19999` makes 200010000 class-token comparisons, which exceed the bound 640000.
- Case 22 fails, because `a||b` reported `invalid_selector`.
- Case 54 already passes at the base, which the contract permits, because only cases 49 to 53 must fail.

### Mutation controls

`raw/mutation-r1.diff` makes `noCandidate` return `restart_from_descendant` instead of `not_matched_globally` for the child and descendant combinators, which removes the early exit.
The mutated build exits with status 1: 277 of 278 tests pass, and the only failure is case 53, whose chain part reports 16244657 compound-match attempts after the element at depth 140, over the bound 16008000; its class part passes.
The digests of `src/css/selectors.zig` are `fc630040…7088` before, `33bb64aa…4005` during, and `fc630040…7088` after.
The digest of `src/css/cascade.zig` is `830b398d…5b05` at all three points.

`raw/mutation-cascade-origin-r1.diff` is the original control, which swaps the precedence of important user and important author declarations, at the line numbers of the revised file.
The mutated build exits with status 1: 277 of 278 tests pass, and the only failure is case 35, "expected 5, found 4".
The digests of `src/css/cascade.zig` are `830b398d…5b05` before, `14a457bd…7778` during, and `830b398d…5b05` after.
`raw/tests-after-r1.log` records `fc630040…7088` for `src/css/selectors.zig` and `830b398d…5b05` for `src/css/cascade.zig` before its build, so both controls started from the same two files that it tested.

### Stop-rule observations

No cited source contradicted an expected value of cases 22 or 49 to 54.
`raw/sources-r1.log` records the SHA-256 of the source copies in the main checkout's `out/` directory, where each CSSWG copy's name carries the pinned commit, and prints the cited lines.
They show `if()`, `inherit()`, `attr()`, `ident()`, and `random-item()` as arbitrary substitution functions at `css-values-5/Overview.bs` lines 1680, 1911, 2194, 2358, and 2741; `New values: grid-lanes | inline-grid-lanes` at `css-grid-3/Overview.bs` line 348; the column combinator at `selectors-5/Overview.bs` line 462; and "Moved the column combinator to Selectors 5" at `selectors-4/Overview.bs` line 5232.
The MathML Core copy, `out/mathml-core.html`, gives the new `display` values of section 4.1 as `<display-outside> || [ <display-inside> | math ]`.
No revision 1 log records the download of those copies.

### Resolved ambiguities

- The contract says that matching gives up on the whole selector when a combinator's left side fails for every candidate that the combinator allows.
  Read literally for the child and sibling combinators, that rule would miss matches: in `x > a b`, a parent that is not `x` does not rule out a higher `a`.
  The implementation follows the standard early exit of Servo's `SelectorMatchingResult`.
  A child or descendant combinator without an ancestor left ends the whole selector, a failed child or sibling combinator resumes the nearest descendant combinator to its right, and a failed compound resumes the nearest descendant or subsequent-sibling combinator.
  Each descendant combinator therefore walks the ancestors at most once per match.
- `||` reports `unsupported_selector` wherever a combinator can start, including `a||` with nothing after it, as `a:hover` does for pseudo-classes.
  `E||F` and `*||F` parse `E` and `*` as type selectors instead of namespace prefixes, and a leading `||b` stays `invalid_selector`, because a complex selector cannot start with a combinator.
- `math` reports `unsupported_value` wherever it appears in a `display` value, like the other unsupported keywords.
- The parser asks the new validator hook `atRuleBlock` when it reaches an at-rule's block; the stylesheet validator answers no, so the block is consumed without validator calls, and the at-rule itself is still checked when its block ends.
- A custom property is checked for the unsupported arbitrary substitution functions in the declared tokens of its cascaded declaration, at any depth, before any substitution.
  Substitution cannot introduce such a function from elsewhere, because every custom property and inherited value that it reads was checked in the same way.
- The spread syntax now ends in any arbitrary substitution function, as Values 5 defines it, and the spread check skips every nested arbitrary substitution function.
- `classes` returns an owned, deduplicated slice; `hasClass` scans the tokens without deduplication, because duplicates cannot change whether a class is present.
  The class-token counter counts each comparator call of the sort, each adjacent-run check, and each `hasClass` comparison.
- Case 53 first matches each element of the chain in tree order with `matchRulesWith`, as `resolve` does, and stops at the first element after which the count exceeds the bound; it then resets the counter, resolves, and checks the count and the margins.
  Without the early check, a matcher without the early exit would run for hours instead of failing.
- `StyleMap.textStyle` returns a `ComputedStyle` by value, because a defaulted style is not stored in the map; it borrows the map's custom values.

### Open questions

- The contract's cost sentence, "at most proportional to the selector's compound count times the element's depth plus its preceding sibling count", holds for selectors without a subsequent-sibling combinator to the left of a descendant combinator.
  For `a ~ b c`, each ancestor that matches `b` scans its own preceding siblings, so the work grows with the sibling counts of every ancestor.
  A bound for every selector needs memoized failures or the ancestor filter of `FP-0070`.
- Review 1's notes on over-approximations, where an invalid or nonstandard form reports `unsupported_value` or `unsupported_selector`, and on properties outside the registry reporting `unknown_property`, remain for `FP-0070` and `FP-0071`.

### Integrator actions

- Record `HEAD` and a status that includes ignored files for every source root, then run `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0014/gates`, and record `HEAD` and status again.
- Request review from `fairpane-review`.
