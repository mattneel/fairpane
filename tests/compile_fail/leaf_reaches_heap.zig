//! FP-0011 case 34: a context with no effects cannot allocate a string through its stored heap.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{})) void {
    _ = ctx.heap.allocateString(&.{'x'}) catch unreachable;
}

comptime {
    _ = &probe;
}
