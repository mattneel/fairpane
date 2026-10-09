//! FP-0011 case 36: bindKernels rejects a catalog entry without a kernel.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

const Kernels = struct {};

comptime {
    _ = Rt.bindKernels(&.{.{
        .id = .number_add,
        .name = "StubOperation",
        .anchor = "sec-numeric-types-number-add",
        .operands = &.{},
        .result = .number,
        .effects = .{},
    }}, Kernels);
}
