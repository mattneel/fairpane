//! FP-0011 case 5: validate rejects the exception effect without allocation.

const operations = @import("fairpane").js.operations;

comptime {
    operations.validate(&.{.{
        .id = .number_add,
        .name = "BadException",
        .anchor = "sec-numeric-types-number-add",
        .operands = &.{},
        .result = .number,
        .effects = .{ .exception = true },
    }});
}
