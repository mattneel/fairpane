//! FP-0011 case 4: a context with no effects invokes every leaf operation.

const fairpane = @import("fairpane");
const js = fairpane.js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{}), object: js.CellRef, key: js.CellRef) void {
    _ = ctx.invoke(.number_add, .{ @as(f64, 1), @as(f64, 2) });
    _ = ctx.invoke(.number_same_value, .{ @as(f64, 1), @as(f64, 2) });
    _ = ctx.invoke(.same_value, .{ Rt.undefined_value, Rt.null_value });
    _ = ctx.invoke(.is_callable, .{Rt.undefined_value});
    _ = ctx.invoke(.string_to_number, .{fairpane.web_string.View{ .units = &.{'1'} }});
    _ = ctx.invoke(.ordinary_get_own_property, .{ object, key });
    _ = ctx.invoke(.ordinary_get_prototype_of, .{object});
}

comptime {
    _ = &probe;
}
