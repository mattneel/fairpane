//! HTML parsing: the tokenizer of HTML Standard §13.2.5 and its canonical dump.
//!
//! Tree construction does not exist yet, so nothing in the engine's document load calls the tokenizer.
//! The laboratory's `tokenize` stage drives it directly.

const tokenizer = @import("tokenizer.zig");
const web_string = @import("../web_string.zig");

pub const states = @import("states.zig");
pub const errors = @import("errors.zig");
pub const entities = @import("entities.zig");
pub const dump = @import("dump.zig");

pub const Tokenizer = tokenizer.Tokenizer;
pub const Error = tokenizer.Error;
pub const Step = tokenizer.Step;
pub const Token = tokenizer.Token;
pub const Kind = tokenizer.Kind;
pub const Doctype = tokenizer.Doctype;
pub const Tag = tokenizer.Tag;
pub const Attribute = tokenizer.Attribute;
pub const ProcessingInstruction = tokenizer.ProcessingInstruction;
pub const ParseError = tokenizer.ParseError;
pub const Position = tokenizer.Position;
pub const Span = tokenizer.Span;
pub const State = states.State;
pub const ErrorCode = errors.ErrorCode;
pub const View = web_string.View;
pub const CodeUnitIndex = web_string.CodeUnitIndex;

test {
    _ = @import("tokenizer_test.zig");
    _ = @import("partition_test.zig");
    _ = @import("entities_test.zig");
}
