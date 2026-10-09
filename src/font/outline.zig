//! The bounded outline model shared by the outline decoders.
//! Coordinates are f64 values in font units, with y pointing up. No hinting or device transform is applied.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Point = struct { x: f64, y: f64 };

pub const Verb = enum(u8) { move, line, quad, cubic, close };

/// A sequence of closed subpaths. `move` and `line` take 1 point, `quad` takes 2 (control, end), `cubic` takes 3,
/// and `close` takes 0. A `close` is a line back to the subpath's start whenever the current point differs from it.
pub const Path = struct {
    verbs: []Verb,
    points: []Point,

    pub fn deinit(path: *Path, gpa: Allocator) void {
        gpa.free(path.verbs);
        gpa.free(path.points);
        path.* = undefined;
    }
};

/// Budgets for one decode. `max_points` bounds the flattened points, and `max_components` bounds the component
/// records processed at every level of a composite.
pub const Limits = struct { max_points: u32 = 65536, max_components: u32 = 65536 };

/// The deepest composite nesting that a decode accepts. A composite of simple glyphs has depth 1, as `maxp` defines it.
pub const max_composite_depth = 8;

pub const OutlineError = error{
    OutOfMemory,
    GlyphOutOfRange,
    NotTrueType,
    InvalidGlyph,
    CompositeCycle,
    CompositeTooDeep,
    OutlineTooLarge,
    UnsupportedPhantomPoint,
};
