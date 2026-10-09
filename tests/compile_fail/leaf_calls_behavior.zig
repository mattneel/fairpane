//! FP-0011 case 4: a context with no effects cannot form the context argument of a built-in behavior.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{}), behavior: Rt.Behavior) void {
    const no_arguments: []const Rt.Value = &.{};
    _ = behavior(ctx, Rt.undefined_value, no_arguments) catch unreachable;
}

comptime {
    _ = &probe;
}
