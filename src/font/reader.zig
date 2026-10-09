//! A checked big-endian reader over borrowed font bytes.
//! Every read takes a 64-bit offset and returns null instead of reading past the end, so offset sums cannot wrap.

const std = @import("std");

pub const Tag = [4]u8;

pub const Reader = struct {
    bytes: []const u8,

    pub fn init(bytes: []const u8) Reader {
        return .{ .bytes = bytes };
    }

    pub fn len(self: Reader) u64 {
        return self.bytes.len;
    }

    /// Whether `count` bytes starting at `offset` lie inside the bytes.
    pub fn fits(self: Reader, offset: u64, count: u64) bool {
        return offset <= self.bytes.len and count <= self.bytes.len - offset;
    }

    pub fn slice(self: Reader, offset: u64, count: u64) ?[]const u8 {
        if (!self.fits(offset, count)) return null;
        const start: usize = @intCast(offset);
        return self.bytes[start..][0..@intCast(count)];
    }

    pub fn sub(self: Reader, offset: u64, count: u64) ?Reader {
        return .{ .bytes = self.slice(offset, count) orelse return null };
    }

    /// The bytes from `offset` to the end.
    pub fn rest(self: Reader, offset: u64) ?Reader {
        if (offset > self.bytes.len) return null;
        return .{ .bytes = self.bytes[@intCast(offset)..] };
    }

    fn int(self: Reader, comptime T: type, offset: u64) ?T {
        const n = @sizeOf(T);
        const bytes = self.slice(offset, n) orelse return null;
        return std.mem.readInt(T, bytes[0..n], .big);
    }

    pub fn u8At(self: Reader, offset: u64) ?u8 {
        return self.int(u8, offset);
    }
    pub fn u16At(self: Reader, offset: u64) ?u16 {
        return self.int(u16, offset);
    }
    pub fn i16At(self: Reader, offset: u64) ?i16 {
        return self.int(i16, offset);
    }
    pub fn u32At(self: Reader, offset: u64) ?u32 {
        return self.int(u32, offset);
    }
    pub fn i32At(self: Reader, offset: u64) ?i32 {
        return self.int(i32, offset);
    }
    pub fn i64At(self: Reader, offset: u64) ?i64 {
        return self.int(i64, offset);
    }
    pub fn tagAt(self: Reader, offset: u64) ?Tag {
        const bytes = self.slice(offset, 4) orelse return null;
        return bytes[0..4].*;
    }
    pub fn arrayAt(self: Reader, comptime n: usize, offset: u64) ?[n]u8 {
        const bytes = self.slice(offset, n) orelse return null;
        return bytes[0..n].*;
    }
};

test "reads stop at the end and offset sums do not wrap" {
    const r = Reader.init(&.{ 0x12, 0x34, 0x56, 0x78 });
    try std.testing.expectEqual(@as(?u32, 0x12345678), r.u32At(0));
    try std.testing.expectEqual(@as(?u16, null), r.u16At(3));
    try std.testing.expectEqual(@as(?u8, null), r.u8At(std.math.maxInt(u64)));
    try std.testing.expect(!r.fits(2, std.math.maxInt(u64)));
    try std.testing.expect(r.fits(4, 0));
}
