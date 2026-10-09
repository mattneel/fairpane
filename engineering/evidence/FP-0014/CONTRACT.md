# FP-0014 task contract

## Identity

Task ID: `FP-0014`, "Implement initial CSS syntax and cascade".
Workstream: `css-layout`.
Base: the commit that freezes this contract.
Prerequisites: `FP-0009` and `FP-0007`, accepted.
The `fairpane-spec` worker `FP0014Contract` drafted this contract, and the root integrator froze it with the decisions below.
Assigned role: `fairpane-core`.
Authority: `routine-local-engineering`.

### Integrator decisions

- The CSS baseline is the set of CSSWG editor's drafts at `w3c/csswg-drafts` commit `58354dac99cc8783a9b7b28957ece56bb48579eb`, which every cited CSS draft names as its revision.
  The DOM baseline is the DOM Standard at commit `b76da7af5fe35a2a368127cc9ec22449ac8fd559`, dated 5 October 2026.
- CSS Syntax at that commit has a defect in "consume a block's contents" (section 5.5.5).
  Its `<EOF-token>` and `<}-token>` branch returns `rules` and drops a nonempty `decls`, so `a { color: red }` would have no declaration.
  The integrator confirmed the text in `css-syntax-3/Overview.bs` at the pinned commit.
  This task appends a nonempty `decls` to `rules` before that return, as the algorithm's other branches do.
  Cases 7, 8, 9, 11, and 44 depend on this choice.
  Reporting the defect upstream is a publication that needs owner authorization, so this task does not report it.
- The laboratory keeps reporting the `style` stage as `unsupported`.
  The laboratory has no `tree` stage, so it cannot build a DOM to style, and a style path that no case can reach would be untested dead code.
  Task `FP-0068` owns the laboratory style wiring.
- Each frozen value grammar accepts a subset of the property's standard grammar.
  Every standard form outside that subset produces the diagnostic `unsupported_value`, and the declaration is dropped as a user agent without the feature drops it.
  That includes the `display` values that need flex, grid, or ruby containment, and the CSS Nesting rules, which are dropped with diagnostics.
- No WPT test runs in this task, for the reasons in "WPT applicability".
- The user-agent constants are a `medium` font size of 16px, a `larger` and `smaller` ratio of 1.2, the light system-color palette below, and specificity components that saturate at 65535, as Selectors section 15 permits.
- CSS Variables 1 (work status "Testing") defines `var()` as an arbitrary substitution function with the argument grammar of Values 5, so this task implements that algorithm, `{}`-wrapped free-form arguments, and `var()` names that substitution produces.
  Values 5 is an exploration-phase draft, and only Values 5 defines the spread syntax, so this task does not implement the spread syntax.
  A property whose value uses the spread syntax in an arbitrary substitution function becomes invalid at computed-value time with the reason `unsupported_value`.
  Task `FP-0071` owns the spread syntax.
- The container relative length units `cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, and `cqmax` of CSS Conditional Rules Level 5 produce `unsupported_value`, like the other standard units outside the frozen set.
- The 148 named colors may be transcribed by hand.
  The integrator checks every row against the named-color table of the pinned Color 4 source and records the result.

## Sources

- CSS Syntax Module Level 3, editor's draft of 1 October 2026: <https://drafts.csswg.org/css-syntax-3/>, source <https://github.com/w3c/csswg-drafts/blob/58354dac99cc8783a9b7b28957ece56bb48579eb/css-syntax-3/Overview.bs>.
  Sections 3.3, 4, 4.2, 4.3.1 to 4.3.15, 5.2, 5.3, 5.4.1 to 5.4.10, 5.5.1 to 5.5.11, 7.1, 7.2, 8, 8.1, 8.2, and 8.3.
  The latest TR publication is <https://www.w3.org/TR/2026/CRD-css-syntax-3-20261001/>.
- Selectors Level 4, editor's draft of 18 September 2026: <https://drafts.csswg.org/selectors-4/>.
  Sections 3.1, 3.7, 3.8, 3.9, 5.1, 5.2, 5.3, 6.1, 6.2, 6.3, 6.4, 6.6, 6.7, 14.1 to 14.4, 15, and 16.
- CSS Cascading and Inheritance Level 5, editor's draft of 13 April 2026: <https://drafts.csswg.org/css-cascade-5/>.
  Sections 1.1, 4 to 4.4, 5, 6.1, 6.2, 6.3, 7.1, 7.2, and 7.3.1 to 7.3.6.
- CSS Values and Units Level 4, editor's draft of 20 August 2026: <https://drafts.csswg.org/css-values-4/>.
  Sections 4.1, 4.1.1, 4.3, 5, 5.4, 5.5, 6.1.1, 6.1.2, and 6.2.
- CSS Values and Units Level 5, editor's draft of 4 September 2026: <https://drafts.csswg.org/css-values-5/>.
  Section 3.1.1 and Appendix A: "Substitution", "Argument Grammars and Spread Syntax", "Resolving in Properties", "Invalid Substitution", and "Safely Handling Overly-Long Substitution".
- CSS Custom Properties for Cascading Variables Level 1, editor's draft of 9 October 2026: <https://drafts.csswg.org/css-variables-1/>.
  Sections 2, 2.1, 2.2, and 3.
- CSS Color Level 4, editor's draft of 8 October 2026: <https://drafts.csswg.org/css-color-4/>.
  Sections 3.2, 4.1, 4.1.1, 4.1.2, 4.2, 4.4, 5.1, 5.2, 6.1, 6.2, 6.3, 6.4, 15.1, 15.5, and Appendix A, "Deprecated CSS System Colors".
- CSS Fonts Level 4, editor's draft of 13 September 2026: <https://drafts.csswg.org/css-fonts-4/>.
  Sections 2.5 and 2.5.1.
- CSS Box Model Level 4, editor's draft of 6 August 2026: <https://drafts.csswg.org/css-box-4/>.
  Section 3.1.
- CSS Display Level 4, editor's draft of 5 June 2026: <https://drafts.csswg.org/css-display-4/>.
  Sections 2, 2.3, 2.7, and 2.8.
- CSS Conditional Rules Level 5, working draft source at the pinned commit: <https://github.com/w3c/csswg-drafts/blob/58354dac99cc8783a9b7b28957ece56bb48579eb/css-conditional-5/Overview.bs>.
  Section "Container Relative Lengths" (`#container-lengths`).
- DOM Standard, Living Standard of 5 October 2026: <https://dom.spec.whatwg.org/>.
  Section 1.2 ("Ordered sets"), section 4.5 (document type and mode defaults), and section 4.9 (attribute list, "get an attribute by namespace and local name", "set an attribute value", "remove an attribute by namespace and local name", the ID attribute change steps, and the classes of `classList`).
- Infra Standard, "ASCII whitespace" and "ASCII case-insensitive": <https://infra.spec.whatwg.org/>.
- WPT at the pinned commit `b60c4b349d9d167bf354a40bc0d4cbed15174606`: directory `css/css-syntax/` and the files named under "WPT applicability".
- Repository: `AGENTS.md`, `src/AGENTS.md`, `tests/AGENTS.md`, `docs/RENDERING_AND_TEXT.md`, `docs/ARCHITECTURE.md`, and the FP-0007 and FP-0009 contracts.

## Behavior

### Modules

`src/css/css.zig` is the public module, exported from `src/root.zig` as `css`.
Its parts are `tokenizer.zig`, `parser.zig`, `stylesheet.zig`, `selectors.zig`, `registry.zig`, `properties.zon`, `named_colors.zon`, `values.zig`, `cascade.zig`, `substitution.zig`, `compute.zig`, `style.zig`, and `dump.zig`, all under `src/css/`.
The library test block in `src/root.zig` references `css`.
No file outside `src/css/`, `src/dom.zig`, and `src/root.zig` changes, except evidence files.

Every allocating function takes the caller's allocator, and every owned result has a `deinit`.
An allocation failure returns `error.OutOfMemory`, leaks nothing, and leaves every caller-visible object unchanged.
No runtime function under `src/css/` recurses.
Explicit stacks hold every traversal of nested component values, selectors, elements, and substitutions, so nesting depth is bounded only by memory.

### Input

The CSS entry points take a string as a `View` of UTF-16 code units from `src/web_string.zig`.
"Filter code points" (Syntax 3.3) converts that string into a `[]const u21` sequence.
A high surrogate followed by a low surrogate becomes one supplementary code point.
Every other surrogate code unit, and every U+0000, becomes U+FFFD.
CR LF, CR, and FF each become one LF.
Every later position, source range, and original text refers to this filtered sequence as a half-open range of code-point indexes.
Byte decoding of stylesheets (Syntax 3.2) is outside this task.

### Tokenizer

`tokenizer.zig` implements "consume a token" (4.3.1) and every algorithm that it calls (4.3.2 to 4.3.15), with the definitions of 4.2.
The non-ASCII ident code points are exactly the ranges of 4.2.
`Tokenizer.init(input: []const u21, options: Options)` takes `Options{ .unicode_ranges_allowed: bool = false }`.
`next` returns one token per call and returns null at EOF.

`TokenKind` has exactly these 25 members: `ident`, `function`, `at_keyword`, `hash`, `string`, `bad_string`, `url`, `bad_url`, `delim`, `number`, `percentage`, `dimension`, `unicode_range`, `whitespace`, `cdo`, `cdc`, `colon`, `semicolon`, `comma`, `open_square`, `close_square`, `open_paren`, `close_paren`, `open_curly`, and `close_curly`.
Each token records its kind, its source range, and the fields of section 4.
Those fields are a value for ident, function, at-keyword, hash, string, and url tokens; a hash type flag of `id` or `unrestricted`; a delim code point; a numeric value, a type flag of `integer` or `number`, and a sign of `+`, `-`, or none; a dimension unit; and a unicode range's start and end.
String values are UTF-16 code units that encode the token's code points.

A numeric value is the `f64` nearest to the exact decimal value of the consumed number text, as Values 4 section 5 requires for limited precision.
A value whose magnitude exceeds the largest finite `f64` becomes `std.math.floatMax(f64)` with the value's sign.

### Dump format

`dump.zig` writes deterministic text that cases compare byte for byte.
Tokens are separated by one space.

| Token | Dump |
| --- | --- |
| ident | `ident(V)` |
| function | `function(V)` |
| at-keyword | `at(V)` |
| hash | `hash(V,id)` or `hash(V,unrestricted)` |
| string | `string(V)` |
| bad-string | `bad-string` |
| url | `url(V)` |
| bad-url | `bad-url` |
| delim | `delim(C)` |
| number | `number(N,T,S)` |
| percentage | `percentage(N,S)` |
| dimension | `dimension(N,T,S,U)` |
| unicode-range | `unicode-range(A,B)` |
| whitespace | `ws` |
| CDO and CDC | `<!--` and `-->` |
| colon, semicolon, and comma | `:`, `;`, and `,` |
| brackets | `[`, `]`, `(`, `)`, `{`, and `}` |

`V`, `C`, and `U` are UTF-8.
`N` is the Zig `{d}` formatting of the `f64`.
`T` is `integer` or `number`, and `S` is `+`, `-`, or `none`.
`A` and `B` are uppercase hexadecimal without leading zeros.
A component value dump writes a preserved token as above, a function as `function(NAME)[ITEMS]`, and a simple block as `block({)[ITEMS]`, `block([)[ITEMS]`, or `block(()[ITEMS]`, with items separated by one space.

In this contract, `⟨LF⟩`, `⟨CR⟩`, `⟨FF⟩`, `⟨NUL⟩`, and `⟨XXXX⟩` denote the code unit or code point with that name or hexadecimal value.

### Syntax parser

`parser.zig` implements the token stream of 5.3 and the parser algorithms of 5.5.1 to 5.5.11, with the block-contents decision above.
It implements every entry point of 5.4.

| Entry point | Function | Result |
| --- | --- | --- |
| Parse something according to a CSS grammar (5.4.1) | `parseGrammar` | Used by `stylesheet.zig` and `values.zig` |
| Parse a comma-separated list according to a CSS grammar (5.4.2) | `parseGrammarList` | Used by `values.zig` |
| Parse a stylesheet (5.4.3) | `parseStylesheet` | A list of rules |
| Parse a stylesheet's contents (5.4.4) | `parseStylesheetContents` | A list of rules |
| Parse a block's contents (5.4.5) | `parseBlockContents` | A list of rules and declaration lists |
| Parse a rule (5.4.6) | `parseRule` | A rule or `error.SyntaxError` |
| Parse a declaration (5.4.7) | `parseDeclaration` | A declaration or `error.SyntaxError` |
| Parse a component value (5.4.8) | `parseComponentValue` | A component value or `error.SyntaxError` |
| Parse a list of component values (5.4.9) | `parseComponentValueList` | A list of component values |
| Parse a comma-separated list of component values (5.4.10) | `parseCommaSeparatedComponentValues` | A list of component value lists |

The stylesheet location of 5.4.3 and every other CSSOM attribute are outside this task.
The parser asks a `Validator` whether a rule or declaration is "valid in the current context".
Its context is `top_level`, `at_rule_block`, or `qualified_rule_block`.
`SyntaxOnly` accepts every rule and declaration in every context, so cases 7 to 14 observe the bare syntax.
A declaration whose name is a custom property name records its original text (5.5.6 step 8).
A `unicode-range` declaration retokenizes its original text with unicode ranges allowed (5.5.6 step 8 and 5.5.11).
Each result owns an arena and frees it in `deinit`.

The cases write parser results in this notation:
- A declaration is `NAME = [ITEMS]`, followed by ` !important` when its important flag is set.
- A qualified rule is `qualified [PRELUDE] decls{D; D} rules{R; R}`.
- An at-rule is `@NAME [PRELUDE] no-block` or `@NAME [PRELUDE] block{ITEM; ITEM}`.
- A declaration list inside a block is `decls{D; D}`, and a nested declarations rule is `nested-decls{D; D}`.

### Stylesheets

`stylesheet.zig` implements Syntax section 8 with a validator for the frozen subset.
`Stylesheet.parse(gpa, source: View, origin: Origin) !Stylesheet` runs "parse a stylesheet" and keeps the valid top-level style rules in source order.
`Origin` is `user_agent`, `user`, or `author` (Cascade 6.2).

- A top-level qualified rule is a style rule.
  Its prelude parses as a selector list under "Selectors" below, and a failure drops the rule with `invalid_selector` or `unsupported_selector`.
- Every at-rule, at any level, is dropped with `ignored_at_rule` and its name, because this task implements no at-rule.
  That includes `@charset`, which Syntax 8.3 defines as no rule.
- A qualified rule inside a style rule's block is dropped with `nested_rule_ignored`, because CSS Nesting is outside this task.
- A nested declarations rule (Syntax 5.5.3) is dropped with `nested_declarations_ignored`.
- A declaration whose name is neither a registered property name, compared ASCII case-insensitively, nor a custom property name is dropped with `unknown_property`.
  The name `--` is not a custom property name (Variables 2).
- A value that is one CSS-wide keyword (`initial`, `inherit`, `unset`, `revert`, `revert-layer`, or `revert-rule`, ASCII case-insensitive) with optional whitespace is kept.
- A value that contains a `var()` function is kept when every `var()` matches its argument grammar, and it is otherwise dropped with `invalid_value` (Values 5, "Resolving in Properties").
- A custom property value must also match `<declaration-value>?` (Syntax 7.2, Variables 2.1), and otherwise it is dropped with `invalid_value`.
- Any other value parses with its property's grammar.
  A value that uses a form listed below as unsupported produces `unsupported_value`, and any other mismatch produces `invalid_value`.
  Either diagnostic drops the declaration.

A `Diagnostic` has a kind, a source range, and a name for `ignored_at_rule`, `unknown_property`, `invalid_value`, and `unsupported_value`.
Diagnostics appear in the order that the parser encounters them.

### DOM attributes

`src/dom.zig` gains attribute lists on elements, as far as selectors need them, following DOM section 4.9.
An attribute has a namespace (null or a string), a local name, and a value, each stored as a lossless `WebString`.
Attribute namespace prefixes are outside this task.

| Function | Algorithm |
| --- | --- |
| `setAttribute(element, namespace: ?View, local_name: View, value: View)` | "Set an attribute value"; an existing attribute keeps its list position |
| `attribute(element, namespace: ?View, local_name: View) ?View` | "Get an attribute by namespace and local name" |
| `removeAttribute(element, namespace: ?View, local_name: View) bool` | "Remove an attribute by namespace and local name"; returns whether it removed one |
| `attributes(element)` | Iterates the attribute list in order |
| `elementId(element) ?View` | The element's ID under the ID attribute change steps |
| `classes(element)` | The ordered set parser over the `class` attribute in no namespace |

An empty namespace means null in every function that takes a namespace, as "get an attribute by namespace and local name" step 1 and "validate and extract" step 1 require.
A non-element node returns `error.NotAnElement`, and the existing handle errors still apply.
`setAttribute` copies its strings and reserves list capacity before it changes the store, so a failure changes nothing.
`sweep` and `deinit` free attributes.
Every store document is an XML document in no-quirks mode, because DOM 4.5 makes `xml` and `no-quirks` the defaults and the store creates no other kind.

### Selectors

`selectors.zig` parses `<selector-list>` (Selectors 16) for the frozen subset and matches it against the DOM store.

| Construct | Frozen behavior |
| --- | --- |
| Type selectors `E`, `*\|E`, and `\|E` | `E` and `*\|E` match the local name in any namespace, because no default namespace is declared (5.3); `\|E` matches only elements in no namespace |
| Universal selectors `*`, `*\|*`, and `\|*` | `\|*` matches only elements in no namespace |
| Class selector `.c` | Matches a token of the element's classes (6.6) |
| ID selector `#i` | An `id`-type hash token that matches the element's ID (6.7) |
| Attribute selectors `[a]`, `[*\|a]`, and `[\|a]` | `[a]` and `[\|a]` match attributes in no namespace, and `[*\|a]` matches any namespace (6.4) |
| Matchers `=`, `~=`, `\|=`, `^=`, `$=`, and `*=` | Sections 6.1 and 6.2, including the empty-value and whitespace rules |
| Modifiers `i` and `s` | Section 6.3; the keywords are ASCII case-insensitive |
| Combinators: descendant, `>`, `+`, and `~` | Section 14; sibling combinators consider element siblings only |
| Selector list | A list with any invalid selector is invalid (3.9) |

Element names, IDs, classes, attribute names, and attribute values compare by identical code units, because every store document is an XML document (3.7).
The `i` modifier compares attribute values ASCII case-insensitively.

The parser reports the first problem in token order.
It reports `unsupported_selector` for a colon followed by an ident or function token, for two colons followed by an ident or function token, for an ident followed by a `|` delim and then an ident or `*` as a type or attribute name, and for the `&` delim.
Pseudo-classes, pseudo-elements, declared namespace prefixes (`@namespace`), and CSS Nesting are standard constructs outside this task.
Every other grammar failure reports `invalid_selector`.

`Specificity` has three `u16` components that saturate at 65535 (15).
A style rule's declarations take the specificity of the most specific selector in its list that matches the element (15).

`matchRules(store, element, sheets)` returns the element's `ApplicableDeclaration` list.
Each entry records the property key, the declared value, the origin, the important flag, the specificity, the order of appearance (sheet index, rule index, and declaration index), and the rule identity.
It computes no value.

### Property registry

`src/css/properties.zon` holds one record per standard property, and `registry.zig` builds `PropertyId` and the registry table from it at compile time.
A record has exactly the fields `name`, `spec`, `initial`, `inherited`, `computed`, and `invalidation`.
`registry.validate` rejects duplicate names with `error.DuplicateProperty`, names that are not lowercase ASCII with `error.NonCanonicalName`, and a record without an invalidation effect with `error.MissingInvalidation`.
The compile-time build calls `validate`.
`registry.zig` defines the custom property family with the same fields.

| Property | Initial | Inherited | Computed representation | Invalidation | Source |
| --- | --- | --- | --- | --- | --- |
| `display` | `inline` | no | `Display` | `box_tree`, `layout`, `paint` | Display 4 section 2 |
| `color` | `CanvasText` | yes | `Color` | `paint`, `element_dependents` | Color 4 section 3.2 |
| `font-size` | `medium` | yes | `f64` pixels | `layout`, `paint`, `element_dependents`, `root_dependents` | Fonts 4 section 2.5 |
| `margin-top`, `margin-right`, `margin-bottom`, `margin-left` | `0` | no | `LengthPercentageAuto` | `layout`, `paint` | Box 4 section 3.1 |
| Custom properties `--*` | guaranteed-invalid | yes | `CustomValue` | `element_dependents` | Variables 1 section 2 |

The invalidation effects mean the following:
- `box_tree`: a change can alter box generation.
- `layout`: a change can alter geometry.
- `paint`: a change can alter painted output.
- `element_dependents`: other values on the same element can depend on this value, such as `em` units on `font-size`, `currentcolor` on `color`, and `var()` on a custom property.
- `root_dependents`: on the root element, `rem` units on every element depend on this value.

`registry.lookup(name: View)` matches standard names ASCII case-insensitively, and it returns a custom key with the exact code units of a custom property name.
`ComputedStyle.diff(a, b)` returns the union of the invalidation effects of every property whose computed values differ, plus `descendants` when an inherited property differs.

### Value grammars

`values.zig` parses declared values and computes values.
Keywords and unit identifiers compare ASCII case-insensitively (Values 4 sections 4.1 and 5.4).

`display` accepts exactly these values (Display 4 sections 2 and 2.3), with multi-keyword values in any order:
- `none` and `contents`.
- An outer type of `block`, `inline`, or `run-in` and an inner type of `flow`, `flow-root`, or `table`; one or both appear, an omitted inner type is `flow`, and an omitted outer type is `block`.
- `list-item` with an optional outer type and an optional `flow` or `flow-root`, with the defaults `block` and `flow`.
- `inline-block`, which is inline flow-root, and `inline-table`, which is inline table.
- `table-row-group`, `table-header-group`, `table-footer-group`, `table-row`, `table-cell`, `table-column-group`, `table-column`, and `table-caption`.

A value that contains `flex`, `grid`, `ruby`, `inline-flex`, `inline-grid`, `ruby-base`, `ruby-text`, `ruby-base-container`, or `ruby-text-container` produces `unsupported_value`, because its computed value needs flex, grid, or ruby containment (Display 2.7).
`Display` is `none`, `contents`, `{ outer, inner, list_item: bool }`, or one of the eight internal keywords.
The root element's value is blockified (2.7 and 2.8).
Its outer type becomes `block`; `inline flow-root` and `run-in flow-root` become `block flow`; an internal value becomes `block flow`; `contents` becomes `block flow`; `none` stays `none`; and the list-item flag stays.

`color` accepts these forms (Color 4 sections 4.1, 5.1, 5.2, 6.1 to 6.4, and Appendix A):
- A `<hex-color>`: a hash token of either type with 3, 4, 6, or 8 hexadecimal digits.
- The 148 named colors of section 6.1, stored in `src/css/named_colors.zon`, and `transparent`.
- The 19 system colors of 6.2 and the 23 deprecated system colors of Appendix A, which resolve through the palette below.
- `currentcolor`.
- `rgb()` and `rgba()` in the legacy syntax (4.1.2) and in the modern syntax (4.1.1), with `none` allowed only in the modern syntax.
  Color components clamp to [0, 255] and alpha clamps to [0, 1] at parse time (5.1 and 4.2), and 100% maps to 255 for a color component and to 1 for alpha.

`Color` is `current_color` or `srgb{ red, green, blue, alpha }`, where each component is an `f64` or missing.
A named, hex, `rgb()`, `transparent`, or system color computes to its sRGB color (15.1 and 15.5).
`currentcolor` computes to itself (15.5).
These produce `unsupported_value`: the functions `hsl`, `hsla`, `hwb`, `lab`, `lch`, `oklab`, `oklch`, `color`, `color-mix`, `light-dark`, `contrast-color`, and `device-cmyk`; any function inside `rgb()` or `rgba()`; and an `rgb()` or `rgba()` whose first component is the ident `from`.

| System color | sRGB |
| --- | --- |
| `AccentColor` | 0 96 223 |
| `AccentColorText` | 255 255 255 |
| `ActiveText` | 238 0 0 |
| `ButtonBorder` | 118 118 118 |
| `ButtonFace` | 239 239 239 |
| `ButtonText` | 0 0 0 |
| `Canvas` | 255 255 255 |
| `CanvasText` | 0 0 0 |
| `Field` | 255 255 255 |
| `FieldText` | 0 0 0 |
| `GrayText` | 109 109 109 |
| `Highlight` | 0 96 223 |
| `HighlightText` | 255 255 255 |
| `LinkText` | 0 0 238 |
| `Mark` | 255 255 0 |
| `MarkText` | 0 0 0 |
| `SelectedItem` | 0 96 223 |
| `SelectedItemText` | 255 255 255 |
| `VisitedText` | 85 26 139 |

Every palette color is opaque.
Each pair that Color 4 section 6.2 lists as legible has a WCAG contrast ratio of at least 4.5 to 1.

`font-size` accepts these forms (Fonts 4 section 2.5):
- `xx-small`, `x-small`, `small`, `medium`, `large`, `x-large`, `xx-large`, and `xxx-large`, computed as `16 * numerator / denominator` with the factors 3/5, 3/4, 8/9, 1/1, 6/5, 3/2, 2/1, and 3/1 (2.5.1).
- `larger` and `smaller`, computed as the parent's computed size multiplied or divided by 1.2.
- A nonnegative `<length>` or `<percentage>`.
  A percentage and `em` use the parent's computed size, and `rem` uses the root element's computed size.
  On the root element, `em`, `rem`, and percentages use 16px (Values 4 6.1.1).
- `math` produces `unsupported_value`.

`margin-top`, `margin-right`, `margin-bottom`, and `margin-left` accept `<length-percentage> | auto` (Box 4 3.1).
`em` uses the element's own computed `font-size`, and `rem` uses the root element's.
`LengthPercentageAuto` is `auto`, a length in pixels, or a percentage.

The `<length>` units are `px`; `cm` as `v * 96 / 2.54`; `mm` as `v * 96 / 25.4`; `q` as `v * 96 / 101.6`; `in` as `v * 96`; `pt` as `v * 96 / 72`; `pc` as `v * 96 / 6`; `em`; and `rem` (Values 4 6.1.1 and 6.2).
Each expression is evaluated in `f64` from left to right.
A unitless `0` is a length of 0px.
The units `ex`, `rex`, `cap`, `rcap`, `ch`, `rch`, `ic`, `ric`, `lh`, and `rlh`, and every viewport unit of Values 4 6.1.2 (`vw`, `vh`, `vi`, `vb`, `vmin`, `vmax`, and their `s`, `l`, and `d` variants), produce `unsupported_value`.
The container relative length units `cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, and `cqmax` (Conditional 5, "Container Relative Lengths") also produce `unsupported_value`.
Any other unit is invalid.
Any function other than `var()`, `rgb()`, and `rgba()` in a standard property value produces `unsupported_value`, because Values 4 math functions and the other excluded functions are standard forms.

### Cascade

`cascade.zig` implements Cascade 6.1 for the origins of 6.2 and the importance of 6.3.
`cascade(gpa, declarations: []const ApplicableDeclaration) !CascadeResult` sorts each property's declarations in descending precedence: origin and importance, then specificity, then order of appearance.
The origin and importance order is important user agent, important user, important author, normal author, normal user, and then normal user agent.
Sheets are ordered as the caller passes them.
Encapsulation contexts, element-attached styles, cascade layers, and animation and transition origins have no input in this task.
The result keeps each property's sorted list, so explicit defaulting can roll back.

Explicit defaulting follows Cascade 7.3:
- `initial` gives the initial value.
- `inherit` gives the parent's computed value, or the initial value on the root element.
- `unset` acts as `inherit` for an inherited property and as `initial` otherwise.
- `revert` from an author declaration discards every author declaration, `revert` from a user declaration discards every author and user declaration, and `revert` from a user-agent declaration acts as `unset`.
- `revert-layer` acts as `revert`, because every declaration of an origin sits in the implicit final layer.
- `revert-rule` discards every declaration of the same style rule.

After a rollback, the next declaration in the list becomes the cascaded value, and a list with no remaining declaration gives no cascaded value.

### Custom properties and substitution

A custom property's declared value is its token list and its original text (Syntax 5.5.6, Variables 2.1).
Names compare by identical code units, and values keep their tokens and case (Variables 2 and 2.1).
A CSS-wide keyword as the whole value is explicit defaulting, not a token value (Variables 2).

`substitution.zig` implements "substitute arbitrary substitution functions", "substitute early-invoked functions", guarded substitution contexts, and cyclic substitution contexts (Values 5 Appendix A), and "replace a var() function" (Variables 3).
The `var()` argument grammar is `var( <declaration-value> , <declaration-value>? )`.
Its first argument is a strict free-form production, and its fallback is a non-strict free-form production (Values 5 3.1.1).
A substitution context is `«"property", name»`.
Guarding a context that is already on the guard stack marks every context from that entry to the top as cyclic.
A cyclic custom property computes to the guaranteed-invalid value.
"Replace substitution functions in a property" makes a property invalid at computed-value time when its value contains the guaranteed-invalid value or fails its grammar after substitution (Values 5, "Invalid Substitution").
Such a property computes to the guaranteed-invalid value if it is a custom property, and to its `unset` value otherwise.
A value that is one CSS-wide keyword after substitution acts as that keyword, including `revert` and `revert-rule`.
One `var()` expansion is limited to 65536 component values, where a function or simple block counts as one plus its contents.
A longer expansion gives the guaranteed-invalid value ("Safely Handling Overly-Long Substitution").
The spread syntax is three adjacent `<delim-token>`s with the value `.` immediately followed by an arbitrary substitution function (Values 5, "Argument Grammars and Spread Syntax").
A property whose value uses the spread syntax inside an arbitrary substitution function becomes invalid at computed-value time with the reason `unsupported_value`, so it computes to the guaranteed-invalid value if it is a custom property and to its `unset` value otherwise.

### Style resolution

`style.zig` resolves every element of one document.
`resolve(gpa, store: *dom.Store, document: NodeHandle, sheets: []const *const Stylesheet) !StyleMap` walks the document element and its descendant elements in tree order with an explicit stack.
For each element, it runs `selectors.matchRules`, then `cascade.cascade`, and then `compute.computeStyle`.
`computeStyle` receives the cascade result, the parent's computed style or null, the root element's computed style or null, and whether the element is the root, and nothing from the DOM or the selectors.
It computes custom properties first, then `font-size`, and then the remaining properties.

`StyleMap.get(element)` returns the element's `ComputedStyle`.
`StyleMap.textStyle(text)` returns a text node's style by defaulting from its parent element (Cascade 1.1).
Any node outside the document's tree returns `error.NotStyled`, because elements that are not connected have no values (Cascade 4).
`StyleMap.diagnostics` lists each property that became invalid at computed-value time, with the element, the property, and a reason of `guaranteed_invalid`, `grammar_mismatch`, or `unsupported_value`.

### Laboratory

`src/lab.zig` does not change.
Its `style` stage keeps the status `unsupported`, and a `style` expectation keeps the outcome `unsupported` with exit status 2.
The laboratory has no `tree` stage, so no case can give the style engine a DOM.
The task that completes `tree` makes the stage reachable, and that task or a later one wires `css.resolve` into the laboratory.
FP-0007 cases 2 and 4 stay unchanged and pass.

### WPT applicability

No WPT test runs in this task, and `specs/applicability/wpt.json` keeps `selected: 0`.
Every WPT test is an HTML, XHTML, or SVG document.
The laboratory's `decode`, `tokenize`, and `tree` stages report `unsupported` until `FP-0008` and `FP-0010` land, so no WPT document can produce a DOM to style.
Each testharness test also needs script and the CSSOM, which belong to `FP-0012` and `FP-0019`.
At the pin, `css/css-syntax/escaped-eof.html`, `css/css-syntax/unclosed-constructs.html`, `css/css-syntax/trailing-braces.html`, `css/css-syntax/var-with-blocks.html`, and `css/css-variables/variable-cycles.html` each load `/resources/testharness.js`.
Each reftest also needs layout, paint, and image comparison, which belong to `FP-0016`.
At the pin, `css/css-syntax/missing-semicolon.html` is a reftest that names `missing-semicolon-ref.html` as its match.
Cases 3, 8, 9, 10, and 42 cover the behavior that those files test.

### Remaining obligations

`src/css/css.zig` lists these obligations in its module documentation, and the evidence README repeats them.

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

### Stop rules

If a cited source contradicts an expected value in this contract, stop and report the observed value to the integrator.
Never edit an expectation to pass a case.

## Exact test cases

Each case is a Zig test named `FP-0014 case N: ...` under `src/css/` or in `src/dom.zig`, and it runs through `zig build test`.
A case that lists several inputs checks every input.
Every case uses `std.testing.allocator`, so a leak fails the case.

### Tokenizer

1. Filtering and tokenizing `a⟨CR⟩⟨LF⟩b⟨CR⟩c⟨FF⟩d⟨NUL⟩e⟨D800⟩f⟨D83D⟩⟨DE00⟩` dumps `ident(a) ws ident(b) ws ident(c) ws ident(d⟨FFFD⟩e⟨FFFD⟩f⟨1F600⟩)`.
2. `a f( @k #i #1 "s" 'q' url(u) 1 2% 3px , : ; [ ] ( ) { } <!-- --> ~ U+1` dumps `ident(a) ws function(f) ws at(k) ws hash(i,id) ws hash(1,unrestricted) ws string(s) ws string(q) ws url(u) ws number(1,integer,none) ws percentage(2,none) ws dimension(3,integer,none,px) ws , ws : ws ; ws [ ws ] ws ( ws ) ws { ws } ws <!-- ws --> ws delim(~) ws ident(U) number(1,integer,+)`.
3. Bad tokens, URLs, and escapes dump as follows:

| Input | Dump |
| --- | --- |
| `"a⟨LF⟩b` | `bad-string ws ident(b)` |
| `"abc` | `string(abc)` |
| `"a\⟨LF⟩b"` | `string(ab)` |
| `"a\` | `string(a)` |
| `url(a b) x` | `bad-url ws ident(x)` |
| `url(a"b) x` | `bad-url ws ident(x)` |
| `url(\⟨LF⟩)` | `bad-url` |
| `url( "q" )` | `function(url) ws string(q) ws )` |
| `url(  x  )` | `url(x)` |
| `url(x` | `url(x)` |
| `URL(x)` | `url(x)` |
| `u\72l(x)` | `url(x)` |
| `\41 x` | `ident(Ax)` |
| `a\` | `ident(a⟨FFFD⟩)` |
| `\0 \D800 \110000 \10FFFF` | `ident(⟨FFFD⟩⟨FFFD⟩⟨FFFD⟩⟨10FFFF⟩)` |
| `\⟨LF⟩` | `delim(\) ws` |

4. Numbers tokenize as follows:

| Input | Dump or value |
| --- | --- |
| `+.5` | `number(0.5,number,+)` |
| `1e3` | `number(1000,number,none)` |
| `1.5E-2` | `number(0.015,number,none)` |
| `1e` | `dimension(1,integer,none,e)` |
| `1e+` | `dimension(1,integer,none,e) delim(+)` |
| `.5.5` | `number(0.5,number,none) number(0.5,number,none)` |
| `12.` | `number(12,integer,none) delim(.)` |
| `-1px` | `dimension(-1,integer,-,px)` |
| `1--x` | `dimension(1,integer,none,--x)` |
| `5%%` | `percentage(5,none) delim(%)` |
| `1e999` | One number token whose value is `std.math.floatMax(f64)` |
| `-1e999` | One number token whose value is `-std.math.floatMax(f64)` |

5. Identifiers, hashes, at-keywords, delims, and comments tokenize as follows:

| Input | Dump |
| --- | --- |
| `-a` | `ident(-a)` |
| `--` | `ident(--)` |
| `-` | `delim(-)` |
| `-\31` | `ident(-1)` |
| `@-` | `delim(@) delim(-)` |
| `@--x` | `at(--x)` |
| `#` | `delim(#)` |
| `#-` | `hash(-,unrestricted)` |
| `#-a` | `hash(-a,id)` |
| `⟨00B7⟩a` | `ident(⟨00B7⟩a)` |
| `⟨00D7⟩` | `delim(⟨00D7⟩)` |
| `⟨200C⟩x` | `ident(⟨200C⟩x)` |
| `/* a */b/* unterminated` | `ident(b)` |
| `a/**/b` | `ident(a) ident(b)` |

6. With `unicode_ranges_allowed`, `U+26`, `u+0-7F`, `U+4??`, `U+??????`, `u+a`, `U+1234567`, `U+5-`, and `U+` dump `unicode-range(26,26)`, `unicode-range(0,7F)`, `unicode-range(400,4FF)`, `unicode-range(0,FFFFFF)`, `unicode-range(A,A)`, `unicode-range(123456,123456) number(7,integer,none)`, `unicode-range(5,5) delim(-)`, and `ident(U) delim(+)`.
   Without it, `U+26` dumps `ident(U) number(26,integer,+)`.

### Syntax parser with `SyntaxOnly`

7. `parseStylesheet` of `@import "a"; a { b: c } @media x { d { e: f } } <!-- g{} -->` gives four rules: `@import [ws string(a)] no-block`; `qualified [ident(a) ws] decls{b = [ident(c)]} rules{}`; `@media [ws ident(x) ws] block{qualified [ident(d) ws] decls{e = [ident(f)]} rules{}}`; and `qualified [ident(g)] decls{} rules{}`.
8. `a { ; b: c; d e; f: g !important; : h; i: j k ; l: m }` gives `decls{b = [ident(c)]; f = [ident(g)] !important; i = [ident(j) ws ident(k)]; l = [ident(m)]} rules{}`.
9. `a { b: c(d [e` gives one rule with `decls{b = [function(c)[ident(d) ws block([)[ident(e)]]]}`.
   `a { b: "x` gives `decls{b = [string(x)]}`.
10. `--foo:hover { color: red } b { }` gives only `qualified [ident(b) ws] decls{} rules{}`.
    `a { --x:y {z}; w: v }` gives `decls{--x = [ident(y) ws block({)[ident(z)]]; w = [ident(v)]}`, and the original text of `--x` is `y {z}`.
    `a { b:c {d}; e: f }` gives `decls{}` and `rules{qualified [ident(b) : ident(c) ws] decls{} rules{}; nested-decls{e = [ident(f)]}}`.
11. The entry points give these results:

| Entry point | Input | Result |
| --- | --- | --- |
| `parseRule` | `  a{}  ` | `qualified [ident(a)] decls{} rules{}` |
| `parseRule` | `a{} b{}` | `error.SyntaxError` |
| `parseRule` | Empty | `error.SyntaxError` |
| `parseRule` | `@x;` | `@x [] no-block` |
| `parseRule` | ` --a:b{} ` | `error.SyntaxError` |
| `parseDeclaration` | `a:b` | `a = [ident(b)]` |
| `parseDeclaration` | `  a : b !IMPORTANT ` | `a = [ident(b)] !important` |
| `parseDeclaration` | `a b` | `error.SyntaxError` |
| `parseDeclaration` | `--x:{y}` | `--x = [block({)[ident(y)]]` |
| `parseComponentValue` | ` x ` | `ident(x)` |
| `parseComponentValue` | ` f(a) ` | `function(f)[ident(a)]` |
| `parseComponentValue` | `x y` | `error.SyntaxError` |
| `parseComponentValue` | Empty | `error.SyntaxError` |
| `parseComponentValueList` | `a, b` | `ident(a) , ws ident(b)` |
| `parseCommaSeparatedComponentValues` | `a, b c,,d` | Four groups: `ident(a)`; `ws ident(b) ws ident(c)`; empty; `ident(d)` |
| `parseStylesheetContents` | `<!--a{}` | `qualified [ident(a)] decls{} rules{}` |
| `parseBlockContents` | `a:b; @c; d{} e:f` | `decls{a = [ident(b)]}`; `@c [] no-block`; `qualified [ident(d)] decls{} rules{}`; `decls{e = [ident(f)]}` |

12. `a{b:c!important}`, `a{b:c ! important}`, and `a{b:c !ImPoRtAnT}` give `b = [ident(c)] !important`.
    `a{b: !important}` gives `b = [] !important`.
    `a{b:c !important d}` gives `b = [ident(c) ws delim(!) ident(important) ws ident(d)]`.
13. `@font-face{unicode-range: U+0-7F, u+4??}` gives `@font-face [] block{decls{unicode-range = [unicode-range(0,7F) , ws unicode-range(400,4FF)]}}`.
14. `a{--x:  a  /* c */ B !important ;}` gives `--x = [ident(a) ws ws ident(B)] !important` with the original text `a  /* c */ B`.
    `a{--y:;}` gives `--y = []` with an empty original text.

### Stylesheets

15. `a:hover { color: red } b { color: blue }` keeps the rule for `b` and reports `unsupported_selector` for the first rule.
    `@charset "x"; @import url(a); @media all { b {} } c {}` keeps the rule for `c` and reports `ignored_at_rule` for `charset`, `import`, and `media`, in that order.
16. `p { colour: red; color: 12px; color: hsl(0 0% 0%); COLOR: Blue; font-size: math; --X: 1; --: 2 }` keeps `color` as the named color `blue` and `--X` as `[number(1,integer,none)]`.
    Its diagnostics are `unknown_property` for `colour`, `invalid_value` for `color`, `unsupported_value` for `color`, `unsupported_value` for `font-size`, and `unknown_property` for `--`, in that order.
17. `p { color: red; b { color: blue } margin-top: 1px; @media x { } }` keeps only `color: red` for `p`.
    Its diagnostics are `nested_rule_ignored`, `ignored_at_rule` for `media`, and `nested_declarations_ignored`, in that order.

### DOM attributes

18. On an element, `setAttribute` of (null, `b`, `1`), (null, `a`, `2`), and (`urn:x`, `b`, `3`) gives that list order.
    Setting (null, `b`, `4`) keeps `b` first.
    `attribute(null, "b")` and `attribute("", "b")` return `4`, `attribute("urn:x", "b")` returns `3`, and `attribute(null, "B")` returns null.
    `setAttribute("", "c", "5")` stores `c` in no namespace.
    The first `removeAttribute(null, "a")` returns true, the second returns false, and the list becomes (null, `b`), (`urn:x`, `b`), and (null, `c`).
    A value of `x⟨D800⟩` round-trips with its lone surrogate.
19. An empty `id` gives a null ID, `id="x y"` gives the ID `x y`, and an `id` attribute in `urn:x` gives no ID.
    `class=" a⟨0009⟩b⟨LF⟩a  c⟨FF⟩"` gives the classes `a`, `b`, and `c`.
    `class="a⟨00A0⟩b"` gives the one class `a⟨00A0⟩b`.
    A `class` attribute in `urn:x` gives no classes.
20. `setAttribute` on a text node returns `error.NotAnElement`, a swept element's handle returns `error.StaleHandle`, and a handle from another store returns `error.WrongOwner`.
    `std.testing.checkAllAllocationFailures` runs element creation, three attribute insertions, a replacement, and a removal.
    Each induced failure returns `error.OutOfMemory`, changes nothing, and leaks nothing.
    `sweep` of a detached element with attributes, and store teardown, leak nothing.

### Selectors

21. Each selector parses with this specificity:

| Selector | (A, B, C) |
| --- | --- |
| `*`, `*\|*`, `\|*` | (0, 0, 0) |
| `div`, `*\|div`, `\|div` | (0, 0, 1) |
| `.a`, `[x]`, `[*\|x]`, `[\|x]`, `[x=y]`, `[x~=y]`, `[x\|=y]`, `[x^=y]`, `[x$=y]`, `[x*=y]`, `[x="y" i]`, `[ x = 'y' S ]` | (0, 1, 0) |
| `#a`, `#x34y` | (1, 0, 0) |
| `div.a#b[x]` | (1, 2, 1) |
| `ul ol + li` | (0, 0, 3) |
| `ul > li ~ li.red` | (0, 1, 3) |
| `H1 + *[REL=up]` | (0, 1, 1) |
| `LI.red.level` | (0, 2, 1) |

    `a , #b` parses as two selectors with (0, 0, 1) and (1, 0, 0).
    A compound of 65536 `.a` class selectors has (0, 65535, 0).
22. These report `invalid_selector`: the empty prelude, `a,`, `,a`, `a,,b`, `> a`, `a >`, `a > > b`, `a .`, `. a`, `#1a`, `[]`, `[x=]`, `[x==y]`, `[x = y z]`, `[x=y j]`, `[x=1]`, `[1]`, `a:`, `a||b`, `a!b`, `a ~`, `*|`, and `|`.
    These report `unsupported_selector`: `a:hover`, `:root`, `a::before`, `a:not(b)`, `a|b`, `[ns|x]`, `&`, and `& a`.
    `a:hover, ,b` reports `unsupported_selector`, because the first problem decides.
23. The fixture document holds `root` in no namespace.
    Its children are `div`, with `id="main"` and `class=" box  big "`, and then `section`.
    The children of `div` are `p` (P1) with `class="a"`, `lang="en-US"`, and `data-x="hello world"`; a text node `t`; a comment `c`; `p` (P2) with `class="b"` and `title="Hello"`; and `span` (S) in namespace `urn:x`, with the attribute (`urn:y`, `lang`, `fr`).
    The child of `section` is `p` (P3) with `id="last"`.
    Each selector matches exactly these elements, in tree order:

| Selector | Matches |
| --- | --- |
| `p` | P1, P2, P3 |
| `*` | root, div, P1, P2, S, section, P3 |
| `span`, `*\|span` | S |
| `\|span` | None |
| `\|p` | P1, P2, P3 |
| `.box`, `.big.box`, `#main`, `[class~=big]` | div |
| `.Box`, `#MAIN`, `[class=box]` | None |
| `#last`, `section > #last`, `section p` | P3 |
| `[lang]`, `[\|lang]`, `[lang=en-US]`, `[lang\|=en]` | P1 |
| `[*\|lang]` | P1, S |
| `[lang\|=en-U]` | None |
| `[data-x~=world]`, `[data-x^=hel]`, `[data-x$=rld]`, `[data-x*="o w"]` | P1 |
| `[data-x~="hello world"]`, `[data-x~=""]`, `[data-x^=""]`, `[data-x*=""]` | None |
| `[title=hello i]`, `[title=Hello s]`, `[title=HELLO I]` | P2 |
| `[title=hello]`, `[title=hello s]` | None |
| `div > p`, `root div p` | P1, P2 |
| `root > p`, `div ~ p` | None |
| `root p` | P1, P2, P3 |
| `p + p`, `root > * > p.b`, `#nothing, .b` | P2 |
| `p ~ span`, `div p ~ span` | S |
| `p.a ~ *` | P2, S |
| `div + section` | section |
| `.a, .b` | P1, P2 |

24. A detached `p` matches `p` and does not match `root p`.

### Registry

25. The registry holds exactly `display`, `color`, `font-size`, `margin-top`, `margin-right`, `margin-bottom`, and `margin-left`, with the initial text, inheritance, computed representation, and invalidation effects of the registry table.
    `lookup` returns `color` for `COLOR`, the custom key `--X` for `--X`, distinct keys for `--x` and `--X`, and null for `--`, `colour`, and `margin`.
26. `registry.validate` returns `error.DuplicateProperty`, `error.NonCanonicalName`, and `error.MissingInvalidation` for three malformed in-test tables, and it accepts the committed table.
27. Each initial text parses with its property's grammar.
    A child of a root, where neither has declarations, computes `display` to inline flow, `color` to sRGB 0 0 0 with alpha 1, `font-size` to 16, every margin to 0px, and every custom property to the guaranteed-invalid value.
28. `diff` gives `box_tree`, `layout`, and `paint` for `inline` to `block`.
    It gives `paint`, `element_dependents`, and `descendants` for a `color` change.
    It gives `layout`, `paint`, `element_dependents`, `root_dependents`, and `descendants` for a `font-size` change.
    It gives `layout` and `paint` for a `margin-top` change.
    It gives `element_dependents` and `descendants` for a `--x` change, and nothing for equal styles.

### Computed values

29. On a non-root element, `display` values compute as follows: `block` to block flow; `inline` to inline flow; `run-in` to run-in flow; `flow` to block flow; `flow-root` to block flow-root; `table` to block table; `inline table` and `table inline` to inline table; `block flow-root` to block flow-root; `list-item` to block flow list-item; `inline list-item` to inline flow list-item; `list-item flow-root inline` to inline flow-root list-item; `inline-block` to inline flow-root; `inline-table` to inline table; `table-cell` to table-cell; `none` to none; and `contents` to contents.
    `block block`, `list-item list-item`, `table list-item`, `inline-block list-item`, `foo`, and `block,inline` report `invalid_value`.
    `flex`, `inline-grid`, `block ruby`, and `ruby-text` report `unsupported_value`.
    On the root element, `inline`, `inline-block`, `run-in flow-root`, `table-cell`, and `contents` compute to block flow; `inline list-item` computes to block flow list-item; `inline table` computes to block table; and `none` computes to none.
30. `color` values compute as follows: `#FFF` to 255 255 255 with alpha 1; `#0000ffcc` to 0 0 255 with alpha `204.0 / 255.0`; `#1234` to 17 34 51 with alpha `68.0 / 255.0`; `#AbCdEf` to 171 205 239; `RebeccaPurple` to 102 51 153; `transparent` to 0 0 0 with alpha 0; `CanvasText` to 0 0 0; `canvas` to 255 255 255; `InfoText` to 0 0 0; `ButtonHighlight` to 239 239 239; and `currentColor` to `current_color`.
    `named_colors.zon` has 148 rows in ascending name order, and `aliceblue`, `darkgray`, `grey`, `rebeccapurple`, and `yellowgreen` give 240 248 255, 169 169 169, 128 128 128, 102 51 153, and 154 205 50.
    `#12345`, `#ggg`, `#1234567`, `blurple`, `red blue`, `rgb`, and `currentcolor red` report `invalid_value`.
31. `rgb(255, 0, 0)` gives 255 0 0 with alpha 1; `rgba(255,0,0,0.5)` gives alpha 0.5; `rgb(255 0 0 / 50%)` gives alpha 0.5; `rgb(100% 50% 0%)` gives 255 127.5 0; `rgb(10% 20 30)` gives 25.5 20 30; `rgb(300 -5 0)` gives 255 0 0; `rgb(0 0 0 / 2)` gives alpha 1; `rgb(none 0 0)` gives a missing red component; `rgb(0 0 0 / none)` gives a missing alpha; `rgba(1 2 3)` gives 1 2 3 with alpha 1; `RGB(1,2,3)` gives 1 2 3; and `rgb(1.5, 2, 3)` gives 1.5 2 3.
    `rgb(1, 2)`, `rgb(1 2)`, `rgb(1, 2, none)`, `rgb(10%, 20, 30)`, `rgb(1, 2, 3,)`, `rgb(1 2 3 4)`, `rgb(1 2 3 /)`, and `rgb(1px 2 3)` report `invalid_value`.
    `hsl(0 0% 0%)`, `rgb(calc(1) 2 3)`, `lab(50% 0 0)`, `color-mix(in srgb, red, blue)`, and `rgb(from red r g b)` report `unsupported_value`.
32. Under a root with no declarations and a parent with `font-size: 20px`, a child computes `2em` to 40, `50%` to 10, `larger` to `20.0 * 1.2`, `smaller` to `20.0 / 1.2`, `1rem` to 16, `xx-small` to `16.0 * 3.0 / 5.0`, `x-small` to 12, `small` to `16.0 * 8.0 / 9.0`, `medium` to 16, `large` to `16.0 * 6.0 / 5.0`, `x-large` to 24, `xx-large` to 32, `xxx-large` to 48, `12pt` to `12.0 * 96.0 / 72.0`, `1in` to 96, `2.54cm` to `2.54 * 96.0 / 2.54`, `10mm` to `10.0 * 96.0 / 25.4`, `40Q` to `40.0 * 96.0 / 101.6`, `1pc` to `96.0 / 6.0`, `0` to 0, and `0.5PX` to 0.5.
    `-1px`, `5`, `-10%`, `1foo`, and `auto` report `invalid_value`, and `math`, `1ex`, `1vw`, `1dvmin`, `1cqw`, and `calc(1px)` report `unsupported_value`; each of these children computes to 20.
    On the root element, `2em` and `2rem` compute to 32, and `50%` computes to 8.
33. Under a root with `font-size: 10px`, an element with `font-size: 20px` computes `margin-top: 10px` to 10px, `margin-right: 5%` to 5%, `margin-bottom: auto` to `auto`, and `margin-left: -2em` to -40px.
    `margin-top: 1rem` computes to 10px, and `margin-top: 0` computes to 0px.
    `margin-top: 1` and `margin-top: 10px 5px` report `invalid_value`, `margin-top: 1ch` and `margin-top: calc(1px)` report `unsupported_value`, and each of these computes to 0px.
    `margin-top: 3px; margin-top: 1` computes to 3px.
34. A root declares `color: rgb(1 2 3); font-size: 20px; margin-top: 5px; display: block; --k: v`, and its child `div` and grandchild `p` have no declarations.
    `div` and `p` compute `color` to 1 2 3, `font-size` to 20, `margin-top` to 0px, `display` to inline flow, and `--k` to `[ident(v)]`.
    A text node under `div` gets the same values from `textStyle`.
    A root under no stylesheet computes `display` to block flow.
    An element in a detached subtree, in a document fragment, or in another document returns `error.NotStyled`.

### Cascade

35. Levels 1 to 6 are normal user agent, normal user, normal author, important author, important user, and important user agent.
    Level L declares `color: rgb(L 0 0)` for `<p id="p">`; levels 1 to 3 use the selector `#p`, and levels 4 to 6 use `p`.
    The sheets are passed in the order author, user, and user agent.
    For each K from 1 to 6, a resolution with levels 1 to K gives `rgb(K 0 0)`.
36. On `<p id="a" class="b">`, `#a { color: rgb(1 0 0) } p.b { color: rgb(2 0 0) } p { color: rgb(3 0 0) }` gives 1 0 0.
    `.b { color: rgb(1 0 0) } .b { color: rgb(2 0 0) }` gives 2 0 0.
    Two author sheets with `.b { color: rgb(1 0 0) }` and `.b { color: rgb(2 0 0) }` give the later sheet's color in both orders.
    `.b { color: rgb(1 0 0); color: rgb(2 0 0) }` gives 2 0 0.
    `#x, p { color: rgb(1 0 0) } .b { color: rgb(2 0 0) }` gives 2 0 0 on `<p class="b">` and 1 0 0 on `<p id="x" class="b">`.
    `.b { color: rgb(1 0 0) } .b { color: nonsense }` and `.b { color: rgb(1 0 0); color: hsl(0 0% 0%) }` give 1 0 0.
37. Under a root with `color: rgb(10 0 0); margin-top: 5px`, a `div` with `color: initial; margin-top: inherit` computes 0 0 0 and 5px.
    Its child `p`, with `color: unset; margin-top: unset`, computes 0 0 0 and 0px.
38. Rollback gives these colors on `<p class="b" id="i">` under a root with `color: rgb(1 2 3)`:

| Declarations | `color` |
| --- | --- |
| User `p{color:rgb(0 0 20)}`; author `p{color:revert}` | 0 0 20 |
| User agent `p{color:rgb(0 20 0)}`; user `p{color:revert}` | 0 20 0 |
| User agent `p{color:revert}` | 1 2 3 |
| User `p{color:rgb(0 0 20)}`; author `p{color:revert-layer}` | 0 0 20 |
| Author `p{color:rgb(1 0 0)} .b{color:revert-rule}` | 1 0 0 |
| User `p{color:rgb(0 0 20)}`; author `.b{color:revert-rule}` | 0 0 20 |
| Author `p{color:rgb(1 0 0)} .b{color:revert-rule} #i{color:revert-rule}` | 1 0 0 |
| User `p{color:rgb(0 0 20)}`; author `p{color:revert !important}` | 0 0 20 |
| Author `p{color:rgb(1 0 0); color:revert-rule}` | 1 2 3 |

    A user-agent `p{margin-top:revert}` computes `margin-top` to 0px.

### Custom properties

39. A root declares `--Brand: Foo  /*c*/ bar(1, {x}) [y] ; --brand: other; --e:; --sp:   ; --case: FoO`.
    `--Brand` computes to `[ident(Foo) ws ws function(bar)[number(1,integer,none) , ws block({)[ident(x)]] ws block([)[ident(y)]]]`, and its declaration has the original text `Foo  /*c*/ bar(1, {x}) [y]`.
    `--brand` computes to `[ident(other)]`.
    `--e` and `--sp` compute to empty token lists that are not the guaranteed-invalid value, and `--case` computes to `[ident(FoO)]`.
40. A root declares `--c: rgb(0 0 255); --m: 7px; --n: 20; --other: 10px; --myvar: --other; --x: 5px; --args: --x, 9px; --args2: --none, 9px`.
    In separate resolutions, a child `p` with one declaration computes as follows:

| `p` declaration | Computed value |
| --- | --- |
| `color: var(--c)` | 0 0 255 |
| `color: var(--missing, {rgb(1 2 3)})` | 1 2 3 |
| `margin-top: var(--m)` | 7px |
| `margin-top: var(var(--myvar))` | 10px |
| `margin-right: var(--missing, 3px)` | 3px |
| `font-size: var(--zz, var(--f, 30px))` | 30 |
| `margin-bottom: var(...var(--args))` | 0px, with `unsupported_value` |
| `--s: var(...var(--args))` | The guaranteed-invalid value, with `unsupported_value` |
| `margin-left: var(--n)px` | 0px, with `grammar_mismatch` |
| `margin-left: var(--missing,)` | 0px, with `grammar_mismatch` |
| `margin-left: var(var(--args))` | 0px, with `guaranteed_invalid` |

41. A parent with `color: rgb(1 2 3); --not-a-color: 20px; --nc2: blue` has a child with `color: red; color: var(--not-a-color); margin-top: 9px; margin-top: var(--nc2)`.
    The child computes `color` to 1 2 3 and `margin-top` to 0px, with two `grammar_mismatch` diagnostics.
42. A root declares `--one: calc(var(--two) + 20px); --two: calc(var(--one) - 20px); --self: var(--self); --p: var(--q); --q: var(--r, baz); --r: var(--p); --outside: var(--p, ok); --d0: x; --d1: var(--d0) var(--d0); color: var(--one, rgb(0 128 0))`.
    `--one`, `--two`, `--self`, `--p`, `--q`, and `--r` compute to the guaranteed-invalid value, `--outside` to `[ident(ok)]`, `--d1` to `[ident(x) ws ident(x)]`, and `color` to 0 128 0.
    Reversing the declaration order gives the same values.
43. A parent with `--x: P; --b: 1; --a: var(--b); color: rgb(1 2 3)` has four children.
    The first, with `--b: 2; --c: var(--a)`, computes `--a` and `--c` to `[number(1,integer,none)]`.
    The second, with `--x: initial; color: var(--x, inherit)`, computes `--x` to the guaranteed-invalid value and `color` to 1 2 3.
    The third and fourth, with `--x: inherit` and `--x: unset`, compute `--x` to `[ident(P)]`.
    In a separate resolution with a user sheet `.r { color: rgb(0 0 20) }` and an author sheet `.r { color: var(--missing, revert) }`, an element of class `r` computes `color` to 0 0 20.
44. A root declares `--a: one; --a: ); --b: one; --b: var(b); --c: one; --c: x ! y; --e: one; --e: url(a b); --f: one; --f: var(); --k: a {b} c; --m: 2; margin-top: calc(var(--m) * 1px); color: var(1)`.
    `--a`, `--c`, `--e`, and `--f` compute to `[ident(one)]`, `--b` computes to the guaranteed-invalid value, and `--k` computes to `[ident(a) ws block({)[ident(b)] ws ident(c)]`.
    The stylesheet reports `invalid_value` for the second `--a`, `--c`, `--e`, and `--f` declarations.
    `margin-top` computes to 0px with `unsupported_value`, and `color` computes to 0 0 0 with `guaranteed_invalid`.
    For a root element `r`, the stylesheet `r{--d:one}r{--d:"x⟨LF⟩}` computes `--d` to `[ident(one)]`.
    For a root element `r`, the stylesheet `r{--g:var(--missing,` computes `--g` to an empty token list that is not the guaranteed-invalid value.
45. A root declares `--p1: lol`, then `--pN: var(--pM) var(--pM)` with M = N - 1 for each N from 2 to 30, then `margin-top: var(--p18, 4px)`.
    `--p16` computes to 65535 component values, and `--p17` computes to 131071 component values.
    `--p18` to `--p30` compute to the guaranteed-invalid value, and `margin-top` computes to 4px.
46. A stylesheet of `p{--x:` followed by 100000 `(` parses, and a root `p` computes `--x` to a 100000-deep nesting of `block(()`.
    A chain of 100000 nested `e` elements under `root`, with `root { color: rgb(1 2 3) } e { margin-top: 1px } root > e { margin-top: 2px }`, resolves.
    The first `e` computes `margin-top` to 2px, and the deepest `e` computes `margin-top` to 1px and `color` to 1 2 3.
    A root that declares `--v100000: var(--v99999)`, then each `--vN: var(--vM)` with M = N - 1 in descending order down to `--v1: var(--v0)`, and then `--v0: z`, computes `--v100000` to `[ident(z)]`.
    Each part frees everything in `deinit`.

### Stage separation and allocation failures

47. Compile-time checks find no `dom.Store`, `*dom.Store`, `dom.NodeHandle`, `selectors.SelectorList`, or `Stylesheet` among the parameter types of `cascade.cascade` and `compute.computeStyle`, and no computed-value type among the fields of `ApplicableDeclaration`.
    `cascade.cascade` over hand-built declarations, without a DOM, returns the winner of case 35's six levels.
    `compute.computeStyle` over a hand-built cascade result and a hand-built parent style returns the inherited `color` and the initial margins.
48. `std.testing.checkAllAllocationFailures` runs `Stylesheet.parse` of a sheet that produces every diagnostic kind, then `resolve` over case 23's fixture with case 42's custom properties.
    Each induced failure returns `error.OutOfMemory`, leaves the store unchanged, and leaks nothing.

## Criterion mapping

| Plan criterion | Cases |
| --- | --- |
| Parse a frozen property and selector set with standard recovery | 1 to 17, 21 to 24, 29 to 33, and 36 |
| Keep selectors, cascade, and computed values separate | 23, 24, 35 to 38, and 47 |
| Describe inheritance and invalidation in the property registry | 25 to 28, 34, 37, and 41 |
| Exercise custom-property token preservation and malformed syntax | 1 to 6, 10, 14, 22, 31, and 39 to 46 |

## Evidence

Record each command with `node tools/fairpane.mjs record` under `engineering/evidence/FP-0014/raw/`.
Run every Zig command with `--env ZIG_GLOBAL_CACHE_DIR=C:\src\fairpane\.zig-cache\global`, so the record shows the cache override.

1. Record `tests-before.log` with `zig build test --summary all --cache-dir out/fp0014-cache-before` at the base.
2. Record an uncached `tests-after.log` with `zig build test --summary all --cache-dir out/fp0014-cache-after`.
3. Record `controller-tests-after.log` with `node tools/fairpane.mjs test`.
4. Write `engineering/evidence/FP-0014/README.md` with the remaining obligations, the mutation result, and every stop-rule observation.

The mutation control swaps the precedence of important user declarations and important author declarations in `cascade.zig`.
Store its exact diff in `mutation-cascade-origin.diff` beside its log.
The control must fail case 35.
The integrator records `HEAD` and a status that includes ignored files for every source root before and after it runs `repo-check`, `controller-test`, `zig-fmt`, and `zig-test` with `--evidence-dir engineering/evidence/FP-0014/gates`.
The integrator also compares every row of `src/css/named_colors.zon` with the named-color table of `css-color-4/Overview.bs` at the pinned commit and records the comparison.

## Authority

Writable paths: `src`, `tests`, `tools`, and `build.zig`, plus `engineering/evidence/FP-0014/`.
This contract needs no change under `tests`, `tools`, or `build.zig`.
Protected paths stay unchanged: `AGENTS.md`, `docs/CHARTER.md`, `engineering/qualification.json`, `engineering/policy.json`, `engineering/gates.json`, `toolchains/zig.lock.json`, and `specs/corpora.json`.
No network access occurs.
Required reviewer: `fairpane-review`.

## Non-goals

- No stylesheet byte decoding, CSSOM, serialization, or `getComputedStyle` exists in this task.
- No at-rule, pseudo-class, pseudo-element, nesting, namespace prefix declaration, cascade layer, or style attribute exists in this task.
- No property outside the registry, and no shorthand, exists in this task.
- No used value, box, layout, or paint exists in this task.
- No HTML document type, quirks mode, or user-agent stylesheet exists in this task.
- The laboratory, the C ABI, `include`, and `api` stay unchanged.
- No acceptance threshold, gate, corpus pin, or applicability record changes in this task.
