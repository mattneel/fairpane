//! FP-0011 case 5: bindKernels rejects a Number::sameValue kernel that can return error.Throw.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

const Kernels = struct {
    pub fn number_same_value(ctx: *Rt.Context(.{}), x: f64, y: f64) error{Throw}!bool {
        _ = ctx;
        return x == y;
    }
};

comptime {
    _ = Rt.bindKernels(js.operations.catalog[1..2], Kernels);
}
