//! The OpenType `cmap` table: validation of every encoding record, full validation of every format 4 and format 12 subtable,
//! Unicode subtable selection, and code point lookup. Formats 0, 2, 6, 8, 10, 13, and 14 get only a header and length check.

const std = @import("std");
const Reader = @import("reader.zig").Reader;

pub const Subtable = struct {
    platform_id: u16,
    encoding_id: u16,
    format: u16,
    /// Null for format 14, which has no language field.
    language: ?u32,
};

pub const Selection = struct { platform_id: u16, encoding_id: u16, format: u16 };

/// Selection order: (3, 10) format 12, (0, 4) format 12, (3, 1) format 4, then (0, 3) format 4.
const candidates = [_]Selection{
    .{ .platform_id = 3, .encoding_id = 10, .format = 12 },
    .{ .platform_id = 0, .encoding_id = 4, .format = 12 },
    .{ .platform_id = 3, .encoding_id = 1, .format = 4 },
    .{ .platform_id = 0, .encoding_id = 3, .format = 4 },
};

pub const Error = error{ InvalidCmap, NoUnicodeCmap };

pub const Cmap = struct {
    table: Reader,
    record_count: u16,
    selection: Selection,
    /// The selected subtable, bounded by its length field.
    selected: Reader,

    pub fn subtableCount(self: Cmap) u16 {
        return self.record_count;
    }

    pub fn subtable(self: Cmap, i: u16) Subtable {
        std.debug.assert(i < self.record_count);
        const at = 4 + 8 * @as(u64, i);
        const offset = self.table.u32At(at + 4).?;
        const header = subtableHeader(self.table, offset) catch unreachable;
        return .{
            .platform_id = self.table.u16At(at).?,
            .encoding_id = self.table.u16At(at + 2).?,
            .format = header.format,
            .language = header.language,
        };
    }

    /// The glyph for `code_point`, or 0 when the selected subtable does not map it.
    pub fn glyphIndex(self: Cmap, code_point: u21) u16 {
        return switch (self.selection.format) {
            4 => format4Lookup(self.selected, code_point),
            12 => format12Lookup(self.selected, code_point),
            else => unreachable,
        };
    }
};

const Header = struct { format: u16, length: u64, language: ?u32 };

/// Reads a subtable's format, length, and language, and checks that its length field lies inside the table.
fn subtableHeader(table: Reader, offset: u64) error{InvalidCmap}!Header {
    const format = table.u16At(offset) orelse return error.InvalidCmap;
    const header: Header = switch (format) {
        0, 2, 4, 6 => .{
            .format = format,
            .length = table.u16At(offset + 2) orelse return error.InvalidCmap,
            .language = table.u16At(offset + 4) orelse return error.InvalidCmap,
        },
        8, 10, 12, 13 => .{
            .format = format,
            .length = table.u32At(offset + 4) orelse return error.InvalidCmap,
            .language = table.u32At(offset + 8) orelse return error.InvalidCmap,
        },
        14 => .{ .format = format, .length = table.u32At(offset + 2) orelse return error.InvalidCmap, .language = null },
        else => return error.InvalidCmap,
    };
    const minimum: u64 = switch (format) {
        0, 2, 4, 6 => 6,
        14 => 10,
        else => 12,
    };
    if (header.length < minimum or !table.fits(offset, header.length)) return error.InvalidCmap;
    return header;
}

/// Remembers the offsets of fully validated subtables, so encoding records that share a subtable validate it once.
/// The set holds at most 512 offsets in 1024 slots, which bounds every probe; after that, each record validates its subtable again.
const ValidatedOffsets = struct {
    const slots = 1024;
    const capacity = slots / 2;
    const empty = std.math.maxInt(u32);
    offsets: [slots]u32 = @splat(empty),
    count: usize = 0,

    fn slot(offset: u32) usize {
        return @intCast((@as(u64, offset) *% 0x9E3779B97F4A7C15) >> 54);
    }

    fn contains(self: *const ValidatedOffsets, offset: u32) bool {
        var at = slot(offset);
        while (self.offsets[at] != empty) : (at = (at + 1) % slots) {
            if (self.offsets[at] == offset) return true;
        }
        return false;
    }

    fn insert(self: *ValidatedOffsets, offset: u32) void {
        if (self.count == capacity) return;
        var at = slot(offset);
        while (self.offsets[at] != empty) : (at = (at + 1) % slots) {
            if (self.offsets[at] == offset) return;
        }
        self.offsets[at] = offset;
        self.count += 1;
    }
};

/// Validates the encoding records and every subtable, then selects the Unicode subtable.
pub fn parse(table: Reader, num_glyphs: u16) Error!Cmap {
    const version = table.u16At(0) orelse return error.InvalidCmap;
    if (version != 0) return error.InvalidCmap;
    const count = table.u16At(2) orelse return error.InvalidCmap;
    if (!table.fits(4, 8 * @as(u64, count))) return error.InvalidCmap;
    var best: ?usize = null;
    var selected: Reader = undefined;
    var previous: [3]u32 = undefined;
    var validated: ValidatedOffsets = .{};
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const at = 4 + 8 * i;
        const platform = table.u16At(at).?;
        const encoding = table.u16At(at + 2).?;
        const offset = table.u32At(at + 4).?;
        const header = try subtableHeader(table, offset);
        const key = [3]u32{ platform, encoding, header.language orelse 0 };
        if (i > 0 and std.mem.order(u32, &previous, &key) != .lt) return error.InvalidCmap;
        previous = key;
        const sub = table.sub(offset, header.length).?;
        if (!validated.contains(offset)) {
            switch (header.format) {
                4 => try validateFormat4(sub, num_glyphs),
                12 => try validateFormat12(sub, num_glyphs),
                else => {},
            }
            validated.insert(offset);
        }
        for (candidates, 0..) |c, rank| {
            if (c.platform_id == platform and c.encoding_id == encoding and c.format == header.format and (best == null or rank < best.?)) {
                best = rank;
                selected = sub;
            }
        }
    }
    const rank = best orelse return error.NoUnicodeCmap;
    return .{ .table = table, .record_count = count, .selection = candidates[rank], .selected = selected };
}

/// Format 4 arrays: endCode at 14, reservedPad, startCode, idDelta, and idRangeOffset, each segCount entries long.
const Format4 = struct {
    sub: Reader,
    seg_count: u64,

    fn end(self: Format4, i: u64) u16 {
        return self.sub.u16At(14 + 2 * i).?;
    }
    fn start(self: Format4, i: u64) u16 {
        return self.sub.u16At(16 + 2 * self.seg_count + 2 * i).?;
    }
    fn delta(self: Format4, i: u64) u16 {
        return self.sub.u16At(16 + 4 * self.seg_count + 2 * i).?;
    }
    fn rangeOffsetAt(self: Format4, i: u64) u64 {
        return 16 + 6 * self.seg_count + 2 * i;
    }
    fn rangeOffset(self: Format4, i: u64) u16 {
        return self.sub.u16At(self.rangeOffsetAt(i)).?;
    }
    /// The glyphIdArray position for `code_point` in segment `i`, which has a nonzero idRangeOffset.
    fn glyphAt(self: Format4, i: u64, code_point: u64) u64 {
        return self.rangeOffsetAt(i) + self.rangeOffset(i) + 2 * (code_point - self.start(i));
    }
};

fn validateFormat4(sub: Reader, num_glyphs: u16) error{InvalidCmap}!void {
    const seg_count_x2 = sub.u16At(6) orelse return error.InvalidCmap;
    if (seg_count_x2 == 0 or seg_count_x2 % 2 != 0) return error.InvalidCmap;
    const f: Format4 = .{ .sub = sub, .seg_count = seg_count_x2 / 2 };
    if (!sub.fits(0, 16 + 8 * f.seg_count)) return error.InvalidCmap;
    var i: u64 = 0;
    while (i < f.seg_count) : (i += 1) {
        const s = f.start(i);
        const e = f.end(i);
        if (s > e) return error.InvalidCmap;
        if (i > 0 and (e <= f.end(i - 1) or s <= f.end(i - 1))) return error.InvalidCmap;
        const d = f.delta(i);
        if (f.rangeOffset(i) == 0) {
            // Glyphs (c + idDelta) mod 65536 for c in [s, e] form one interval unless they wrap past 0xFFFF,
            // and a wrapped interval contains 0xFFFF, which is never below numGlyphs.
            const low = (@as(u64, s) + d) & 0xFFFF;
            if (low + (e - s) > 0xFFFF or low + (e - s) >= num_glyphs) return error.InvalidCmap;
        } else {
            var c: u64 = s;
            while (c <= e) : (c += 1) {
                const glyph = sub.u16At(f.glyphAt(i, c)) orelse return error.InvalidCmap;
                if (glyph != 0 and ((@as(u64, glyph) + d) & 0xFFFF) >= num_glyphs) return error.InvalidCmap;
            }
        }
    }
    if (f.end(f.seg_count - 1) != 0xFFFF) return error.InvalidCmap;
}

fn format4Lookup(sub: Reader, code_point: u21) u16 {
    if (code_point > 0xFFFF) return 0;
    const f: Format4 = .{ .sub = sub, .seg_count = sub.u16At(6).? / 2 };
    var low: u64 = 0;
    var high: u64 = f.seg_count;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (f.end(middle) < code_point) low = middle + 1 else high = middle;
    }
    if (low == f.seg_count or f.start(low) > code_point) return 0;
    const d = f.delta(low);
    if (f.rangeOffset(low) == 0) return @intCast((@as(u64, code_point) + d) & 0xFFFF);
    const glyph = sub.u16At(f.glyphAt(low, code_point)).?;
    if (glyph == 0) return 0;
    return @intCast((@as(u64, glyph) + d) & 0xFFFF);
}

fn validateFormat12(sub: Reader, num_glyphs: u16) error{InvalidCmap}!void {
    const groups = sub.u32At(12) orelse return error.InvalidCmap;
    if (sub.len() < 16 + 12 * @as(u64, groups)) return error.InvalidCmap;
    var previous_end: u64 = 0;
    var i: u64 = 0;
    while (i < groups) : (i += 1) {
        const at = 16 + 12 * i;
        const start = sub.u32At(at).?;
        const end = sub.u32At(at + 4).?;
        const glyph = sub.u32At(at + 8).?;
        if (start > end or end > 0x10FFFF) return error.InvalidCmap;
        if (i > 0 and start <= previous_end) return error.InvalidCmap;
        if (@as(u64, glyph) + (end - start) >= num_glyphs) return error.InvalidCmap;
        previous_end = end;
    }
}

fn format12Lookup(sub: Reader, code_point: u21) u16 {
    const groups: u64 = sub.u32At(12).?;
    var low: u64 = 0;
    var high: u64 = groups;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (sub.u32At(16 + 12 * middle + 4).? < code_point) low = middle + 1 else high = middle;
    }
    if (low == groups) return 0;
    const at = 16 + 12 * low;
    const start = sub.u32At(at).?;
    if (start > code_point) return 0;
    return @intCast(sub.u32At(at + 8).? + (code_point - start));
}
