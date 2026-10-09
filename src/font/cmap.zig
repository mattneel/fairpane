//! The OpenType `cmap` table: validation of every encoding record, full validation of every format 4 and format 12 subtable,
//! Unicode subtable selection, and code point lookup. Formats 0, 2, 6, 8, 10, 13, and 14 get only a header and length check.

const std = @import("std");
const builtin = @import("builtin");
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

/// The number of subtables that `parse` validated, one for each distinct offset. The counter exists only in test builds.
pub const Validations = if (builtin.is_test) u32 else void;

pub const Cmap = struct {
    table: Reader,
    record_count: u16,
    selection: Selection,
    /// The selected subtable, bounded by its length field.
    selected: Reader,
    num_glyphs: u16,
    validations: Validations,

    pub fn subtableCount(self: Cmap) u16 {
        return self.record_count;
    }

    /// Encoding record `i` with its subtable's format and language. Null when `i` is at or past the record count,
    /// or when the record no longer names a subtable whose header fits, because the font bytes changed after `parse`.
    pub fn subtable(self: Cmap, i: u16) ?Subtable {
        if (i >= self.record_count) return null;
        const record = self.table.fixed(8, 4 + 8 * @as(u64, i)) orelse return null;
        const header = subtableHeader(self.table, record.int(u32, 4)) catch return null;
        return .{
            .platform_id = record.int(u16, 0),
            .encoding_id = record.int(u16, 2),
            .format = header.format,
            .language = header.language,
        };
    }

    /// The glyph for `code_point`, or 0 when the selected subtable does not map it. The result is always below numGlyphs:
    /// when the font bytes changed after `parse`, a read outside the subtable or a glyph at or past numGlyphs gives glyph 0.
    pub fn glyphIndex(self: Cmap, code_point: u21) u16 {
        const glyph = switch (self.selection.format) {
            4 => format4Lookup(self.selected, code_point),
            12 => format12Lookup(self.selected, code_point),
            else => null,
        } orelse return 0;
        if (glyph >= self.num_glyphs) return 0;
        return @intCast(glyph);
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

/// The offsets of validated subtables, so encoding records that share a subtable validate it once.
/// The set holds at most 512 offsets in 1024 slots, which bounds every probe. A new offset after that fails the cmap,
/// so no subtable is ever validated twice.
const ValidatedOffsets = struct {
    const slots = 1024;
    const capacity = slots / 2;
    const empty = std.math.maxInt(u32);
    offsets: [slots]u32 = @splat(empty),
    count: usize = 0,

    fn slot(offset: u32) usize {
        // The top 10 bits of a 64-bit product, which index the 1024 slots.
        return @intCast((@as(u64, offset) *% 0x9E3779B97F4A7C15) >> 54);
    }

    fn contains(self: *const ValidatedOffsets, offset: u32) bool {
        var at = slot(offset);
        while (self.offsets[at] != empty) : (at = (at + 1) % slots) {
            if (self.offsets[at] == offset) return true;
        }
        return false;
    }

    /// Adds an offset that the set does not contain. A full set returns `InvalidCmap` instead.
    fn insert(self: *ValidatedOffsets, offset: u32) error{InvalidCmap}!void {
        if (self.count == capacity) return error.InvalidCmap;
        var at = slot(offset);
        while (self.offsets[at] != empty) at = (at + 1) % slots;
        self.offsets[at] = offset;
        self.count += 1;
    }
};

/// Validates the encoding records and every subtable, then selects the Unicode subtable.
/// Each distinct subtable offset is validated at most once, and a cmap with more than 512 distinct offsets returns `InvalidCmap`.
pub fn parse(table: Reader, num_glyphs: u16) Error!Cmap {
    const version = table.u16At(0) orelse return error.InvalidCmap;
    if (version != 0) return error.InvalidCmap;
    const count = table.u16At(2) orelse return error.InvalidCmap;
    if (!table.fits(4, 8 * @as(u64, count))) return error.InvalidCmap;
    var best: ?usize = null;
    var selected: Reader = undefined;
    var previous: [3]u32 = undefined;
    var validated: ValidatedOffsets = .{};
    var validations: Validations = if (builtin.is_test) 0 else {};
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const record = table.fixed(8, 4 + 8 * i) orelse return error.InvalidCmap;
        const platform = record.int(u16, 0);
        const encoding = record.int(u16, 2);
        const offset = record.int(u32, 4);
        const header = try subtableHeader(table, offset);
        const key = [3]u32{ platform, encoding, header.language orelse 0 };
        if (i > 0 and std.mem.order(u32, &previous, &key) != .lt) return error.InvalidCmap;
        previous = key;
        const sub = table.sub(offset, header.length) orelse return error.InvalidCmap;
        if (!validated.contains(offset)) {
            try validated.insert(offset);
            if (builtin.is_test) validations += 1;
            switch (header.format) {
                4 => try validateFormat4(sub, num_glyphs),
                12 => try validateFormat12(sub, num_glyphs),
                else => {},
            }
        }
        for (candidates, 0..) |c, rank| {
            const better = if (best) |b| rank < b else true;
            if (c.platform_id == platform and c.encoding_id == encoding and c.format == header.format and better) {
                best = rank;
                selected = sub;
            }
        }
    }
    const rank = best orelse return error.NoUnicodeCmap;
    return .{
        .table = table,
        .record_count = count,
        .selection = candidates[rank],
        .selected = selected,
        .num_glyphs = num_glyphs,
        .validations = validations,
    };
}

/// Format 4 arrays: endCode at 14, reservedPad, startCode, idDelta, and idRangeOffset, each segCount entries long.
/// Each read returns null outside the subtable.
const Format4 = struct {
    sub: Reader,
    seg_count: u64,

    fn end(self: Format4, i: u64) ?u16 {
        return self.sub.u16At(14 + 2 * i);
    }
    fn start(self: Format4, i: u64) ?u16 {
        return self.sub.u16At(16 + 2 * self.seg_count + 2 * i);
    }
    fn delta(self: Format4, i: u64) ?u16 {
        return self.sub.u16At(16 + 4 * self.seg_count + 2 * i);
    }
    fn rangeOffsetAt(self: Format4, i: u64) u64 {
        return 16 + 6 * self.seg_count + 2 * i;
    }
    fn rangeOffset(self: Format4, i: u64) ?u16 {
        return self.sub.u16At(self.rangeOffsetAt(i));
    }
    /// The glyphIdArray entry for `code_point` in segment `i`, which starts at `segment_start` and has a nonzero idRangeOffset.
    fn glyphId(self: Format4, i: u64, range_offset: u16, segment_start: u16, code_point: u64) ?u16 {
        return self.sub.u16At(self.rangeOffsetAt(i) + range_offset + 2 * (code_point - segment_start));
    }
};

/// Reads at most one glyphIdArray entry per code point of each segment, so one validation reads at most 65536 entries.
fn validateFormat4(sub: Reader, num_glyphs: u16) error{InvalidCmap}!void {
    const seg_count_x2 = sub.u16At(6) orelse return error.InvalidCmap;
    if (seg_count_x2 == 0 or seg_count_x2 % 2 != 0) return error.InvalidCmap;
    const f: Format4 = .{ .sub = sub, .seg_count = seg_count_x2 / 2 };
    if (!sub.fits(0, 16 + 8 * f.seg_count)) return error.InvalidCmap;
    var previous_end: u16 = 0;
    var i: u64 = 0;
    while (i < f.seg_count) : (i += 1) {
        const s = f.start(i) orelse return error.InvalidCmap;
        const e = f.end(i) orelse return error.InvalidCmap;
        if (s > e) return error.InvalidCmap;
        if (i > 0 and (e <= previous_end or s <= previous_end)) return error.InvalidCmap;
        previous_end = e;
        const d = f.delta(i) orelse return error.InvalidCmap;
        const range_offset = f.rangeOffset(i) orelse return error.InvalidCmap;
        if (range_offset == 0) {
            // Glyphs (c + idDelta) mod 65536 for c in [s, e] form one interval unless they wrap past 0xFFFF,
            // and a wrapped interval contains 0xFFFF, which is never below numGlyphs.
            const low = (@as(u64, s) + d) & 0xFFFF;
            if (low + (e - s) > 0xFFFF or low + (e - s) >= num_glyphs) return error.InvalidCmap;
        } else {
            var c: u64 = s;
            while (c <= e) : (c += 1) {
                const glyph = f.glyphId(i, range_offset, s, c) orelse return error.InvalidCmap;
                if (glyph != 0 and ((@as(u64, glyph) + d) & 0xFFFF) >= num_glyphs) return error.InvalidCmap;
            }
        }
    }
    if (previous_end != 0xFFFF) return error.InvalidCmap;
}

/// The mapped glyph, 0 when the subtable does not map `code_point`, or null when a read leaves the subtable.
fn format4Lookup(sub: Reader, code_point: u21) ?u64 {
    if (code_point > 0xFFFF) return 0;
    const seg_count_x2 = sub.u16At(6) orelse return null;
    const f: Format4 = .{ .sub = sub, .seg_count = seg_count_x2 / 2 };
    var low: u64 = 0;
    var high: u64 = f.seg_count;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if ((f.end(middle) orelse return null) < code_point) low = middle + 1 else high = middle;
    }
    if (low == f.seg_count) return 0;
    const s = f.start(low) orelse return null;
    if (s > code_point) return 0;
    const d = f.delta(low) orelse return null;
    const range_offset = f.rangeOffset(low) orelse return null;
    if (range_offset == 0) return (@as(u64, code_point) + d) & 0xFFFF;
    const glyph = f.glyphId(low, range_offset, s, code_point) orelse return null;
    if (glyph == 0) return 0;
    return (@as(u64, glyph) + d) & 0xFFFF;
}

/// Reads each of `numGroups` groups once.
fn validateFormat12(sub: Reader, num_glyphs: u16) error{InvalidCmap}!void {
    const groups = sub.u32At(12) orelse return error.InvalidCmap;
    if (sub.len() < 16 + 12 * @as(u64, groups)) return error.InvalidCmap;
    var previous_end: u64 = 0;
    var i: u64 = 0;
    while (i < groups) : (i += 1) {
        const group = sub.fixed(12, 16 + 12 * i) orelse return error.InvalidCmap;
        const start = group.int(u32, 0);
        const end = group.int(u32, 4);
        const glyph = group.int(u32, 8);
        if (start > end or end > 0x10FFFF) return error.InvalidCmap;
        if (i > 0 and start <= previous_end) return error.InvalidCmap;
        if (@as(u64, glyph) + (end - start) >= num_glyphs) return error.InvalidCmap;
        previous_end = end;
    }
}

/// The mapped glyph, 0 when the subtable does not map `code_point`, or null when a read leaves the subtable.
fn format12Lookup(sub: Reader, code_point: u21) ?u64 {
    const groups: u64 = sub.u32At(12) orelse return null;
    var low: u64 = 0;
    var high: u64 = groups;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if ((sub.u32At(16 + 12 * middle + 4) orelse return null) < code_point) low = middle + 1 else high = middle;
    }
    if (low == groups) return 0;
    const group = sub.fixed(12, 16 + 12 * low) orelse return null;
    const start = group.int(u32, 0);
    if (start > code_point) return 0;
    return @as(u64, group.int(u32, 8)) + (code_point - start);
}
