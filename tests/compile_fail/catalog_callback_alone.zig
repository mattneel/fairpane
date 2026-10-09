//! FP-0011 case 5: validate rejects the callback effect without the other three.

const operations = @import("fairpane").js.operations;

comptime {
    operations.validate(&.{.{
        .id = .number_add,
        .name = "BadCallback",
        .anchor = "sec-numeric-types-number-add",
        .operands = &.{},
        .result = .number,
        .effects = .{ .callback = true },
    }});
}
