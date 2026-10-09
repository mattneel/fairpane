//! FP-0011 case 8: checkLayout rejects a heap reference declared plain.

const js = @import("fairpane").js;

const Probe = struct {
    hidden: ?js.CellRef,
};

comptime {
    js.heap_catalog.checkLayout("Probe", Probe, &.{.{ .name = "hidden", .descriptor = .plain }});
}
