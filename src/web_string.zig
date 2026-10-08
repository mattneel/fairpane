const std = @import("std");

/// A borrowed view of JavaScript code units, not Unicode scalar values.
/// The caller owns the storage and keeps it alive for this view.
pub const View = struct {
    units: []const u16,

    pub fn length(self: View) usize {
        return self.units.len;
    }

    pub fn codeUnitAt(self: View, index: usize) ?u16 {
        if (index >= self.units.len) return null;
        return self.units[index];
    }

    pub fn eql(self: View, other: View) bool {
        return std.mem.eql(u16, self.units, other.units);
    }
};

test "a view preserves isolated surrogate code units" {
    const units = [_]u16{ 0x0041, 0xD800, 0x0062, 0xDC00 };
    const view: View = .{ .units = &units };
    try std.testing.expectEqual(@as(usize, 4), view.length());
    try std.testing.expectEqual(@as(?u16, 0xD800), view.codeUnitAt(1));
    try std.testing.expectEqual(@as(?u16, 0xDC00), view.codeUnitAt(3));
    try std.testing.expectEqual(@as(?u16, null), view.codeUnitAt(4));
}

test "surrogate pairs occupy two indexed code units" {
    const pair = [_]u16{ 0xD83D, 0xDE00 };
    const view: View = .{ .units = &pair };
    try std.testing.expectEqual(@as(usize, 2), view.length());
    try std.testing.expectEqual(@as(?u16, 0xDE00), view.codeUnitAt(1));
}

test "equality does not normalize text" {
    const composed = [_]u16{0x00E9};
    const decomposed = [_]u16{ 0x0065, 0x0301 };
    const a: View = .{ .units = &composed };
    const b: View = .{ .units = &decomposed };
    try std.testing.expect(!a.eql(b));
    try std.testing.expect(a.eql(a));
}

test "an empty view rejects every index" {
    const empty: View = .{ .units = &.{} };
    try std.testing.expectEqual(@as(usize, 0), empty.length());
    try std.testing.expectEqual(@as(?u16, null), empty.codeUnitAt(0));
    try std.testing.expectEqual(@as(?u16, null), empty.codeUnitAt(std.math.maxInt(usize)));
}
