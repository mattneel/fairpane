//! FP-0011 case 8: checkLayout rejects a payload field that the layout omits.

const heap_catalog = @import("fairpane").js.heap_catalog;

const Probe = struct {
    kept: u32,
    extra: u32,
};

comptime {
    heap_catalog.checkLayout("Probe", Probe, &.{.{ .name = "kept", .descriptor = .plain }});
}
