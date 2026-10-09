//! HTML parsing: the tokenizer of HTML Standard §13.2.5 and its canonical dump, and tree construction (§13.2.6) for
//! documents outside tables, templates, framesets, and foreign content, with its tree dump.
//!
//! Nothing in the engine's document load calls the parser yet.
//! The laboratory's `tokenize` stage drives the tokenizer directly.

const tokenizer = @import("tokenizer.zig");
const tree = @import("tree.zig");
const web_string = @import("../web_string.zig");

pub const states = @import("states.zig");
pub const errors = @import("errors.zig");
pub const entities = @import("entities.zig");
pub const dump = @import("dump.zig");
pub const modes = @import("modes.zig");
pub const tree_dump = @import("tree_dump.zig");

pub const Tokenizer = tokenizer.Tokenizer;
pub const Error = tokenizer.Error;
pub const ContentState = tokenizer.ContentState;
pub const SwitchError = tokenizer.SwitchError;
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

pub const Parser = tree.Parser;
pub const ParserOptions = tree.Options;
pub const ParserError = tree.Error;
pub const ScriptingMode = tree.ScriptingMode;
pub const Outcome = tree.Outcome;
pub const Unsupported = tree.Unsupported;
pub const TreeParseError = tree.TreeParseError;
pub const ScriptState = tree.ScriptState;
pub const unsupportedOwner = tree.owner;

test {
    _ = @import("tokenizer_test.zig");
    _ = @import("partition_test.zig");
    _ = @import("entities_test.zig");
    _ = @import("tree_test.zig");
    _ = @import("tree_partition_test.zig");
}
