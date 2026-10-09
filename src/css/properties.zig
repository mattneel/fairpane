//! One record per standard property, as data only. `registry.zig` builds `PropertyId` and the registry table
//! from these records at compile time and validates every record.
//! Sources: the CSSWG editor's drafts at w3c/csswg-drafts commit 58354dac99cc8783a9b7b28957ece56bb48579eb.

const Record = @import("registry.zig").Record;

pub const records = [_]Record{
    .{
        .name = "display",
        .spec = "CSS Display Level 4, section 2",
        .initial = "inline",
        .inherited = false,
        .computed = .display,
        .invalidation = &.{ .box_tree, .layout, .paint },
    },
    .{
        .name = "color",
        .spec = "CSS Color Level 4, section 3.2",
        .initial = "CanvasText",
        .inherited = true,
        .computed = .color,
        .invalidation = &.{ .paint, .element_dependents },
    },
    .{
        .name = "font-size",
        .spec = "CSS Fonts Level 4, section 2.5",
        .initial = "medium",
        .inherited = true,
        .computed = .pixels,
        .invalidation = &.{ .layout, .paint, .element_dependents, .root_dependents },
    },
    .{
        .name = "margin-top",
        .spec = "CSS Box Model Level 4, section 3.1",
        .initial = "0",
        .inherited = false,
        .computed = .length_percentage_auto,
        .invalidation = &.{ .layout, .paint },
    },
    .{
        .name = "margin-right",
        .spec = "CSS Box Model Level 4, section 3.1",
        .initial = "0",
        .inherited = false,
        .computed = .length_percentage_auto,
        .invalidation = &.{ .layout, .paint },
    },
    .{
        .name = "margin-bottom",
        .spec = "CSS Box Model Level 4, section 3.1",
        .initial = "0",
        .inherited = false,
        .computed = .length_percentage_auto,
        .invalidation = &.{ .layout, .paint },
    },
    .{
        .name = "margin-left",
        .spec = "CSS Box Model Level 4, section 3.1",
        .initial = "0",
        .inherited = false,
        .computed = .length_percentage_auto,
        .invalidation = &.{ .layout, .paint },
    },
};
