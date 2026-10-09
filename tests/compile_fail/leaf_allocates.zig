//! FP-0011 case 4: a context with no effects cannot allocate a string.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{})) void {
    _ = ctx.allocateString(&.{'x'}) catch unreachable;
}

comptime {
    _ = &probe;
}
