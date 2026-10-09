//! FP-0011 case 4: a context with no effects cannot invoke ToNumber.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{})) void {
    _ = ctx.invoke(.to_number, .{Rt.undefined_value}) catch unreachable;
}

comptime {
    _ = &probe;
}
