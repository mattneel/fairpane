//! The OpenType layout Coverage, ClassDef, Device, and VariationIndex tables, which `layout.zig` re-exports.
//! Source: the OpenType 1.9.1 `chapter2` sections "Coverage table", "Class definition table", and "Device and VariationIndex tables".
//! Opening a table checks every record, in time linear in its length. A query reads the bytes again and checks every index
//! at its point of use, so it never reads outside the bytes even when they change after the check.

const Reader = @import("reader.zig").Reader;
const tables = @import("tables.zig");
const TableStatus = tables.TableStatus;

/// A Coverage table that `parseCoverage` checked.
pub const Coverage = struct {
    /// 1 or 2.
    format: u16,
    table: Reader,
    /// The table's position inside `table`.
    offset: u64,
    /// The checked glyphCount of format 1 or rangeCount of format 2.
    count: u16,
    /// The number of covered glyphs, at most 65536.
    glyph_count: u32,

    pub fn glyphCount(self: Coverage) u32 {
        return self.glyph_count;
    }

    /// The Coverage Index of `glyph`, or null when the table does not cover it. A binary search, in O(log n).
    /// A result is always below `glyphCount`; when the bytes changed after the check, a result that is not is null.
    pub fn index(self: Coverage, glyph: u16) ?u16 {
        var low: u32 = 0;
        var high: u32 = self.count;
        if (self.format == 1) {
            while (low < high) {
                const middle = low + (high - low) / 2;
                const g = self.table.u16At(self.offset + 4 + 2 * @as(u64, middle)) orelse return null;
                if (g == glyph) return @intCast(middle);
                if (g < glyph) low = middle + 1 else high = middle;
            }
            return null;
        }
        while (low < high) {
            const middle = low + (high - low) / 2;
            const record = self.table.fixed(6, self.offset + 4 + 6 * @as(u64, middle)) orelse return null;
            const start = record.int(u16, 0);
            if (glyph < start) {
                high = middle;
            } else if (glyph > record.int(u16, 2)) {
                low = middle + 1;
            } else {
                const i = @as(u32, record.int(u16, 4)) + (glyph - start);
                return if (i < self.glyph_count) @intCast(i) else null;
            }
        }
        return null;
    }

    /// The covered glyphs in Coverage Index order.
    pub fn iterator(self: Coverage) CoverageIterator {
        return .{ .coverage = self };
    }
};

/// Gives at most `glyphCount` glyphs, in Coverage Index order.
pub const CoverageIterator = struct {
    coverage: Coverage,
    emitted: u32 = 0,
    /// Format 2: the current range record.
    record: u32 = 0,
    /// Format 2: the next glyph of the current range, valid when `in_range`.
    next_glyph: u32 = 0,
    in_range: bool = false,

    pub fn next(self: *CoverageIterator) ?u16 {
        const c = self.coverage;
        if (self.emitted >= c.glyph_count) return null;
        if (c.format == 1) {
            const glyph = c.table.u16At(c.offset + 4 + 2 * @as(u64, self.emitted)) orelse return null;
            self.emitted += 1;
            return glyph;
        }
        while (self.record < c.count) {
            const record = c.table.fixed(6, c.offset + 4 + 6 * @as(u64, self.record)) orelse return null;
            if (!self.in_range) {
                self.next_glyph = record.int(u16, 0);
                self.in_range = true;
            }
            if (self.next_glyph <= record.int(u16, 2)) {
                const glyph: u16 = @intCast(self.next_glyph);
                self.next_glyph += 1;
                self.emitted += 1;
                return glyph;
            }
            self.record += 1;
            self.in_range = false;
        }
        return null;
    }
};

/// Format 1 needs its glyphs in strictly ascending order. Format 2 needs each range's start at or before its end, each
/// start after the previous end, and each startCoverageIndex equal to the number of glyphs in the earlier ranges.
/// Any other format is `unsupported_version` with that format. `offset` is relative to `t`.
pub fn parseCoverage(t: Reader, offset: u64) TableStatus(Coverage) {
    if (offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(4, offset) orelse return .{ .rejected = .too_short };
    const format = header.int(u16, 0);
    const count = header.int(u16, 2);
    switch (format) {
        1 => {
            if (!t.fits(offset + 4, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
            var previous: u16 = 0;
            var i: u64 = 0;
            while (i < count) : (i += 1) {
                const glyph = t.u16At(offset + 4 + 2 * i) orelse return .{ .rejected = .count_out_of_bounds };
                if (i > 0 and glyph <= previous) return .{ .rejected = .unsorted_records };
                previous = glyph;
            }
            return .{ .valid = .{ .format = 1, .table = t, .offset = offset, .count = count, .glyph_count = count } };
        },
        2 => {
            if (!t.fits(offset + 4, 6 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
            var total: u32 = 0;
            var previous_end: u16 = 0;
            var i: u64 = 0;
            while (i < count) : (i += 1) {
                const record = t.fixed(6, offset + 4 + 6 * i) orelse return .{ .rejected = .count_out_of_bounds };
                const start = record.int(u16, 0);
                const end = record.int(u16, 2);
                if (start > end) return .{ .rejected = .invalid_range };
                if (i > 0 and start <= previous_end) return .{ .rejected = .unsorted_records };
                if (record.int(u16, 4) != total) return .{ .rejected = .inconsistent_coverage_index };
                total += @as(u32, end - start) + 1;
                previous_end = end;
            }
            return .{ .valid = .{ .format = 2, .table = t, .offset = offset, .count = count, .glyph_count = total } };
        },
        else => return .{ .unsupported_version = format },
    }
}

/// A ClassDef table that `parseClassDef` checked.
pub const ClassDef = struct {
    /// 1 or 2.
    format: u16,
    table: Reader,
    offset: u64,
    /// Format 1: startGlyphID.
    start: u16,
    /// The checked glyphCount of format 1 or classRangeCount of format 2.
    count: u16,

    /// The class of `glyph`, 0 when the table does not assign one: O(1) for format 1 and a binary search for format 2.
    pub fn class(self: ClassDef, glyph: u16) u16 {
        if (self.format == 1) {
            if (glyph < self.start) return 0;
            const k = glyph - self.start;
            if (k >= self.count) return 0;
            return self.table.u16At(self.offset + 6 + 2 * @as(u64, k)) orelse 0;
        }
        var low: u32 = 0;
        var high: u32 = self.count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const record = self.table.fixed(6, self.offset + 4 + 6 * @as(u64, middle)) orelse return 0;
            if (glyph < record.int(u16, 0)) {
                high = middle;
            } else if (glyph > record.int(u16, 2)) {
                low = middle + 1;
            } else return record.int(u16, 4);
        }
        return 0;
    }
};

/// Format 1 needs its class values and startGlyphID + glyphCount <= 65536. Format 2 needs each range's start at or before
/// its end and each start after the previous end. Any other format is `unsupported_version`. `offset` is relative to `t`.
pub fn parseClassDef(t: Reader, offset: u64) TableStatus(ClassDef) {
    if (offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const format = t.u16At(offset) orelse return .{ .rejected = .too_short };
    switch (format) {
        1 => {
            const header = t.fixed(6, offset) orelse return .{ .rejected = .too_short };
            const start = header.int(u16, 2);
            const count = header.int(u16, 4);
            if (!t.fits(offset + 6, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
            if (@as(u32, start) + count > 65536) return .{ .rejected = .count_out_of_bounds };
            return .{ .valid = .{ .format = 1, .table = t, .offset = offset, .start = start, .count = count } };
        },
        2 => {
            const header = t.fixed(4, offset) orelse return .{ .rejected = .too_short };
            const count = header.int(u16, 2);
            if (!t.fits(offset + 4, 6 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
            var previous_end: u16 = 0;
            var i: u64 = 0;
            while (i < count) : (i += 1) {
                const record = t.fixed(6, offset + 4 + 6 * i) orelse return .{ .rejected = .count_out_of_bounds };
                const start = record.int(u16, 0);
                const end = record.int(u16, 2);
                if (start > end) return .{ .rejected = .invalid_range };
                if (i > 0 and start <= previous_end) return .{ .rejected = .unsorted_records };
                previous_end = end;
            }
            return .{ .valid = .{ .format = 2, .table = t, .offset = offset, .start = 0, .count = count } };
        },
        else => return .{ .unsupported_version = format },
    }
}

/// A Device or VariationIndex table. Neither is ever applied, so a well-formed table is reported as unsupported.
pub const DeviceStatus = union(enum) {
    rejected: tables.Defect,
    /// A Device table with deltaFormat 1, 2, or 3.
    unsupported_device: struct { start_size: u16, end_size: u16, delta_format: u16 },
    /// A VariationIndex table, deltaFormat 0x8000.
    unsupported_variation_index: struct { outer: u16, inner: u16 },
    /// Any other deltaFormat.
    unsupported_format: u16,
};

/// Reads the Device or VariationIndex table at `offset`, relative to `t`. A Device table needs `startSize <= endSize`
/// and its packed delta words: 2, 4, or 8 bits for each size from startSize to endSize.
pub fn parseDevice(t: Reader, offset: u64) DeviceStatus {
    if (offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    const header = t.fixed(6, offset) orelse return .{ .rejected = .too_short };
    const start = header.int(u16, 0);
    const end = header.int(u16, 2);
    const format = header.int(u16, 4);
    if (format == 0x8000) return .{ .unsupported_variation_index = .{ .outer = start, .inner = end } };
    const bits: u64 = switch (format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return .{ .unsupported_format = format },
    };
    if (start > end) return .{ .rejected = .invalid_range };
    const words = ((@as(u64, end) - start + 1) * bits + 15) / 16;
    if (!t.fits(offset + 6, 2 * words)) return .{ .rejected = .count_out_of_bounds };
    return .{ .unsupported_device = .{ .start_size = start, .end_size = end, .delta_format = format } };
}
