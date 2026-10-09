//! Text segmentation over UTF-16 code units, with the Unicode 18.0.0 data of `unicode/properties.zig`.
//!
//! `GraphemeBoundaries` yields the extended grapheme cluster boundaries of UAX #29 revision 49, rules GB1 to GB999,
//! as code-unit indexes of a `web_string.View`. It needs no allocation, and its work is linear in the code-unit length.
//! It offers no legacy grapheme clusters, no tailoring, and no random-access boundary query.
//!
//! Remaining obligations:
//! - Preceding and following boundary queries from any code-unit index, for caret movement: FP-0118.
//! - Word and sentence boundary data: FP-0055. Word movement in editing: FP-0030, which depends on FP-0055.
//! - `ID_Start`, `ID_Continue`, and the other properties of `DerivedCoreProperties.txt`, and the emoji binary properties of
//!   `emoji-data.txt`: FP-0055.
//! - CLDR and script-boundary tailoring: FP-0026's frontier decomposition.

pub const GraphemeBoundaries = @import("grapheme.zig").GraphemeBoundaries;
