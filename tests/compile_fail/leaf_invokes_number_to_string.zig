//! FP-0011 case 4: a context with no effects cannot invoke Number::toString.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{})) void {
    _ = ctx.invoke(.number_to_string, .{@as(f64, 1)}) catch unreachable;
}

comptime {
    _ = &probe;
}
