//! FP-0011 case 4: a context with only the allocation effect cannot invoke Call.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{ .allocation = true })) void {
    const no_arguments: []const Rt.Value = &.{};
    _ = ctx.invoke(.call, .{ Rt.undefined_value, Rt.undefined_value, no_arguments }) catch unreachable;
}

comptime {
    _ = &probe;
}
