//! The measurement executable of the `nan_box` representation.

const std = @import("std");
const measure = @import("measure.zig");

pub fn main(init: std.process.Init) !void {
    return measure.main(init, .nan_box);
}
