//! FP-0011 case 5: validate rejects two entries with the same id.

const operations = @import("fairpane").js.operations;

comptime {
    operations.validate(&.{
        .{
            .id = .number_add,
            .name = "FirstAdd",
            .anchor = "sec-numeric-types-number-add",
            .operands = &.{},
            .result = .number,
            .effects = .{},
        },
        .{
            .id = .number_add,
            .name = "SecondAdd",
            .anchor = "sec-numeric-types-number-add",
            .operands = &.{},
            .result = .number,
            .effects = .{},
        },
    });
}
