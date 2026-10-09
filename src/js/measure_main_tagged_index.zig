//! The measurement executable of the `tagged_index` representation.

const std = @import("std");
const measure = @import("measure.zig");

pub fn main(init: std.process.Init) !void {
    return measure.main(init, .tagged_index);
}
