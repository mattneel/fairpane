//! FP-0011 case 35: a context with no effects cannot obtain a root context from what it exposes.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

/// Passes the context's stored heap where `rootContext` expects the owning runtime.
fn throughRootContext(ctx: *Rt.Context(.{})) Rt.Context(.all) {
    return Rt.rootContext(ctx.heap);
}

/// Initializes a context with every effect from the context's stored heap.
fn throughInitialization(ctx: *Rt.Context(.{})) Rt.Context(.all) {
    return .{ .heap = ctx.heap };
}

comptime {
    _ = &throughRootContext;
    _ = &throughInitialization;
}
