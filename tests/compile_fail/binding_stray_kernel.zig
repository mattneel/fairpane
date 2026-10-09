//! FP-0011 case 36: bindKernels rejects a kernel that belongs to no catalog entry.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

const Kernels = struct {
    pub fn number_add(ctx: *Rt.Context(.{}), x: f64, y: f64) f64 {
        _ = ctx;
        return x + y;
    }

    pub fn stub_kernel(ctx: *Rt.Context(.{})) void {
        _ = ctx;
    }
};

comptime {
    _ = Rt.bindKernels(js.operations.catalog[0..1], Kernels);
}
