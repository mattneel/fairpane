//! FP-0011 case 8: checkLayout rejects a layout field that the payload lacks.

const heap_catalog = @import("fairpane").js.heap_catalog;

const Probe = struct {
    kept: u32,
};

comptime {
    heap_catalog.checkLayout("Probe", Probe, &.{
        .{ .name = "kept", .descriptor = .plain },
        .{ .name = "ghost", .descriptor = .plain },
    });
}
