//! FP-0011 case 5: bindKernels rejects a Number::add kernel that takes an allocation context.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

const Kernels = struct {
    pub fn number_add(ctx: *Rt.Context(.{ .allocation = true }), x: f64, y: f64) f64 {
        _ = ctx;
        return x + y;
    }
};

comptime {
    _ = Rt.bindKernels(js.operations.catalog[0..1], Kernels);
}
