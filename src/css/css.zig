//! Initial CSS syntax and cascade.
//!
//! The CSS baseline is the set of CSSWG editor's drafts at `w3c/csswg-drafts` commit
//! `58354dac99cc8783a9b7b28957ece56bb48579eb`: CSS Syntax 3, Selectors 4, Cascade 5, Values 4 and 5,
//! Variables 1, Color 4, Fonts 4, Box 4, Display 4, and Conditional 5. The DOM baseline is the DOM Standard of 5 October 2026.
//!
//! The stages are separate modules:
//! - `tokenizer` filters code points and tokenizes (Syntax 3.3 and 4).
//! - `parser` implements the token stream, the parser entry points, and the parser algorithms (Syntax 5).
//! - `stylesheet` keeps the valid style rules of a stylesheet and reports diagnostics (Syntax 8).
//! - `selectors` parses and matches the frozen selector subset (Selectors 4).
//! - `registry` describes each property's initial value, inheritance, computed representation, and invalidation effects.
//! - `values` parses declared values and computes values for the registered properties.
//! - `cascade` sorts applicable declarations and rolls back explicit defaulting (Cascade 5).
//! - `substitution` implements `var()` and arbitrary substitution (Values 5 Appendix A, Variables 1).
//! - `compute` computes one element's style from a cascade result, with no DOM or selector input.
//! - `style` resolves every element of one document.
//! - `dump` writes the deterministic text that the contract's cases compare.
//!
//! Every allocating function takes the caller's allocator, and every owned result has a `deinit`.
//! No runtime function recurses: explicit stacks hold every nested traversal.
//!
//! Remaining obligations:
//!
//! | Obligation | Current engine behavior | Owner task |
//! | --- | --- | --- |
//! | Stylesheet byte decoding and `@charset` sniffing | No API; the entry points take decoded strings | `FP-0069` |
//! | HTML documents, quirks mode, and HTML case rules for selectors | Every store document is an XML document in no-quirks mode | `FP-0070` |
//! | Pseudo-classes, pseudo-elements, `:is()`, `:not()`, `:where()`, `:has()`, nesting, and `@namespace` | `unsupported_selector`, `nested_rule_ignored`, `nested_declarations_ignored`, or `ignored_at_rule` | `FP-0070` |
//! | Every at-rule | `ignored_at_rule` | `FP-0069` |
//! | Every property outside the registry, including shorthands and logical properties | `unknown_property` | `FP-0071` |
//! | Excluded `color`, `display`, `font-size`, and unit forms | `unsupported_value` | `FP-0071` |
//! | Math functions | `unsupported_value` | `FP-0071` |
//! | The Values 5 spread syntax | Invalid at computed-value time with `unsupported_value` | `FP-0071` |
//! | Cascade layers, encapsulation contexts, style attributes, presentational hints, and animation and transition origins | No input | `FP-0072` |
//! | A user-agent stylesheet for HTML | None | `FP-0072` |
//! | CSSOM, serialization, and `getComputedStyle` | No API | `FP-0073` |
//! | Incremental invalidation | `diff` reports effects, and resolution always recomputes every element | `FP-0074` |
//! | Laboratory style wiring | `style` reports `unsupported` | `FP-0068` |

pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const stylesheet = @import("stylesheet.zig");
pub const selectors = @import("selectors.zig");
pub const registry = @import("registry.zig");
pub const values = @import("values.zig");
pub const cascade = @import("cascade.zig");
pub const substitution = @import("substitution.zig");
pub const compute = @import("compute.zig");
pub const style = @import("style.zig");
pub const dump = @import("dump.zig");

pub const Stylesheet = stylesheet.Stylesheet;
pub const Origin = stylesheet.Origin;
pub const ComputedStyle = compute.ComputedStyle;
pub const StyleMap = style.StyleMap;
pub const resolve = style.resolve;

test {
    _ = tokenizer;
    _ = parser;
    _ = stylesheet;
    _ = selectors;
    _ = registry;
    _ = values;
    _ = cascade;
    _ = substitution;
    _ = compute;
    _ = style;
    _ = dump;
    _ = @import("tests.zig");
}
