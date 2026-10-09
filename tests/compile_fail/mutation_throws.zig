//! FP-0011 case 4: a context with only the heap-mutation effect cannot throw a TypeError.

const js = @import("fairpane").js;
const Rt = js.Runtime(.reference);

fn probe(ctx: *Rt.Context(.{ .heap_mutation = true })) error{ OutOfMemory, Throw }!void {
    return ctx.throwTypeError("probe");
}

comptime {
    _ = &probe;
}
