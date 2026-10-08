const std = @import("std");

pub const abi_revision: u32 = 0;
pub const Status = enum(u32) {
    ok = 0,
    invalid_argument = 1,
};

pub const Capabilities = extern struct {
    struct_size: u32,
    abi_revision: u32,
    feature_bits: u64,
};

export fn fp_abi_revision() callconv(.c) u32 {
    return abi_revision;
}

export fn fp_query_capabilities(out: ?*Capabilities, out_size: usize) callconv(.c) u32 {
    const result = out orelse return @intFromEnum(Status.invalid_argument);
    if (out_size < @sizeOf(Capabilities)) return @intFromEnum(Status.invalid_argument);
    result.* = .{
        .struct_size = @sizeOf(Capabilities),
        .abi_revision = abi_revision,
        .feature_bits = 0,
    };
    return @intFromEnum(Status.ok);
}

test "the bootstrap reports no browser features" {
    var result: Capabilities = undefined;
    try std.testing.expectEqual(@as(u32, 0), fp_query_capabilities(&result, @sizeOf(Capabilities)));
    try std.testing.expectEqual(@as(u64, 0), result.feature_bits);
    try std.testing.expectEqual(abi_revision, result.abi_revision);
}

test "invalid output leaves caller storage unchanged" {
    var result: Capabilities = .{ .struct_size = 19, .abi_revision = 23, .feature_bits = 42 };
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(null, @sizeOf(Capabilities)));
    try std.testing.expectEqual(@as(u32, 1), fp_query_capabilities(&result, @sizeOf(Capabilities) - 1));
    try std.testing.expectEqual(@as(u32, 19), result.struct_size);
    try std.testing.expectEqual(@as(u32, 23), result.abi_revision);
    try std.testing.expectEqual(@as(u64, 42), result.feature_bits);
}
