//! A first-party, deterministic, in-memory sfnt writer for FP-0013 malformed-font tests.
//! It writes the table directory, computes every table checksum and `checksumAdjustment`,
//! places tables in directory order padded with zeros to four bytes, and then applies named overrides.
//! `ttTables` and `cffTables` hold the frozen fonts `B_TT` and `B_CFF` of the FP-0013 contract.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tag = [4]u8;

pub const sfnt_truetype: u32 = 0x00010000;
pub const sfnt_cff: u32 = 0x4F54544F; // "OTTO"

/// A directory record that no table data backs.
pub const Extra = struct {
    tag: Tag,
    /// `after` inserts the record right after the record with that tag; null appends it at the end.
    after: ?Tag = null,
    offset: Where,
    length: u32,
};

pub const Where = union(enum) {
    /// The offset of a placed table plus `delta`.
    table: struct { tag: Tag, delta: u32 = 0 },
    /// The end of the font, which every table precedes.
    past_end,
    absolute: u32,
};

pub const RecordField = enum { checksum, offset, length };

/// Changes applied after the font is laid out and checksummed. Nothing is recomputed after an override.
pub const Override = union(enum) {
    sfnt_version: u32,
    num_tables: u16,
    record: struct { tag: Tag, field: RecordField, value: u32 },
    /// Adds `delta` to a record's offset.
    move_record: struct { tag: Tag, delta: u32 },
    /// Sets the offset of record `tag` to the offset of record `from`.
    copy_offset: struct { tag: Tag, from: Tag },
    swap_records: [2]Tag,
    checksum_adjustment: u32,
    /// Flips every bit of the byte at `offset` inside table `tag`.
    flip_byte: struct { tag: Tag, offset: u32 },
};

pub const Table = struct { tag: Tag, data: []u8 };

/// An ordered, owned table list. `build` writes it in list order.
pub const TableSet = struct {
    gpa: Allocator,
    sfnt_version: u32,
    tables: std.ArrayList(Table) = .empty,

    pub fn deinit(self: *TableSet) void {
        for (self.tables.items) |t| self.gpa.free(t.data);
        self.tables.deinit(self.gpa);
        self.* = undefined;
    }

    fn indexOf(self: *const TableSet, tag: Tag) ?usize {
        for (self.tables.items, 0..) |t, i| if (std.mem.eql(u8, &t.tag, &tag)) return i;
        return null;
    }

    /// The mutable data of table `tag`.
    pub fn get(self: *TableSet, tag: Tag) []u8 {
        return self.tables.items[self.indexOf(tag).?].data;
    }

    /// Replaces table `tag` with a copy of `data`, or inserts it in tag order.
    pub fn put(self: *TableSet, tag: Tag, data: []const u8) Allocator.Error!void {
        const copy = try self.gpa.dupe(u8, data);
        errdefer self.gpa.free(copy);
        if (self.indexOf(tag)) |i| {
            self.gpa.free(self.tables.items[i].data);
            self.tables.items[i].data = copy;
            return;
        }
        var at: usize = 0;
        while (at < self.tables.items.len and std.mem.order(u8, &self.tables.items[at].tag, &tag) == .lt) at += 1;
        try self.tables.insert(self.gpa, at, .{ .tag = tag, .data = copy });
    }

    /// Replaces table `tag` with `data`, taking ownership.
    pub fn putOwned(self: *TableSet, tag: Tag, data: []u8) Allocator.Error!void {
        defer self.gpa.free(data);
        try self.put(tag, data);
    }

    pub fn remove(self: *TableSet, tag: Tag) void {
        const t = self.tables.orderedRemove(self.indexOf(tag).?);
        self.gpa.free(t.data);
    }

    /// Shortens table `tag` to `len` bytes.
    pub fn truncate(self: *TableSet, tag: Tag, len: usize) void {
        const i = self.indexOf(tag).?;
        const t = &self.tables.items[i];
        t.data = self.gpa.realloc(t.data, len) catch unreachable;
    }

    pub fn build(self: *const TableSet, extras: []const Extra, overrides: []const Override) Allocator.Error![]u8 {
        return buildFont(self.gpa, self.sfnt_version, self.tables.items, extras, overrides);
    }
};

const Record = struct { tag: Tag, checksum: u32, offset: u32, length: u32, extra: ?Extra };

/// The wrapping uint32 sum of `data`, zero-padded to a multiple of four.
pub fn checksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 4) {
        var word: [4]u8 = .{ 0, 0, 0, 0 };
        const n = @min(4, data.len - i);
        @memcpy(word[0..n], data[i..][0..n]);
        sum +%= std.mem.readInt(u32, &word, .big);
    }
    return sum;
}

fn pad4(n: usize) usize {
    return (n + 3) & ~@as(usize, 3);
}

pub fn buildFont(gpa: Allocator, sfnt_version: u32, tables: []const Table, extras: []const Extra, overrides: []const Override) Allocator.Error![]u8 {
    var records: std.ArrayList(Record) = .empty;
    defer records.deinit(gpa);
    for (tables) |t| try records.append(gpa, .{ .tag = t.tag, .checksum = 0, .offset = 0, .length = @intCast(t.data.len), .extra = null });
    for (extras) |e| {
        const record: Record = .{ .tag = e.tag, .checksum = 0, .offset = 0, .length = e.length, .extra = e };
        if (e.after) |after| {
            var at: usize = 0;
            while (!std.mem.eql(u8, &records.items[at].tag, &after)) at += 1;
            try records.insert(gpa, at + 1, record);
        } else try records.append(gpa, record);
    }

    const directory_len = 12 + 16 * records.items.len;
    var total = directory_len;
    for (tables) |t| total += pad4(t.data.len);
    const bytes = try gpa.alloc(u8, total);
    @memset(bytes, 0);

    // Table data in directory order.
    var cursor = directory_len;
    var table_offsets: std.ArrayList(u32) = .empty;
    defer table_offsets.deinit(gpa);
    for (tables) |t| {
        @memcpy(bytes[cursor..][0..t.data.len], t.data);
        try table_offsets.append(gpa, @intCast(cursor));
        cursor += pad4(t.data.len);
    }
    for (records.items) |*r| {
        if (r.extra) |e| {
            r.offset = switch (e.offset) {
                .table => |at| table_offsets.items[tableIndex(tables, at.tag)] + at.delta,
                .past_end => @intCast(total),
                .absolute => |offset| offset,
            };
            const end = @as(u64, r.offset) + r.length;
            r.checksum = if (end <= total) checksum(bytes[r.offset..@intCast(end)]) else 0;
        } else {
            const i = tableIndex(tables, r.tag);
            r.offset = table_offsets.items[i];
            r.checksum = checksum(tables[i].data);
        }
    }

    // The head checksum treats checksumAdjustment as zero; the table data already holds zero there.
    writeU32(bytes[0..4], sfnt_version);
    const num_tables: u16 = @intCast(records.items.len);
    writeU16(bytes[4..6], num_tables);
    var power: u16 = 1;
    var log2: u16 = 0;
    while (power * 2 <= num_tables) : (log2 += 1) power *= 2;
    writeU16(bytes[6..8], power * 16);
    writeU16(bytes[8..10], log2);
    writeU16(bytes[10..12], num_tables * 16 - power * 16);
    for (records.items, 0..) |r, i| writeRecord(bytes, i, r);

    const head_offset: ?u32 = for (tables, 0..) |t, i| {
        if (std.mem.eql(u8, &t.tag, "head") and t.data.len >= 12) break table_offsets.items[i];
    } else null;
    if (head_offset) |offset| writeU32(bytes[offset + 8 ..][0..4], 0xB1B0AFBA -% checksum(bytes));

    for (overrides) |o| applyOverride(bytes, records.items, tables, table_offsets.items, head_offset, o);
    return bytes;
}

fn tableIndex(tables: []const Table, tag: Tag) usize {
    for (tables, 0..) |t, i| if (std.mem.eql(u8, &t.tag, &tag)) return i;
    unreachable;
}

fn recordIndex(records: []const Record, tag: Tag) usize {
    for (records, 0..) |r, i| if (std.mem.eql(u8, &r.tag, &tag)) return i;
    unreachable;
}

fn writeRecord(bytes: []u8, index: usize, r: Record) void {
    const at = 12 + 16 * index;
    @memcpy(bytes[at..][0..4], &r.tag);
    writeU32(bytes[at + 4 ..][0..4], r.checksum);
    writeU32(bytes[at + 8 ..][0..4], r.offset);
    writeU32(bytes[at + 12 ..][0..4], r.length);
}

fn applyOverride(bytes: []u8, records: []Record, tables: []const Table, offsets: []const u32, head_offset: ?u32, o: Override) void {
    switch (o) {
        .sfnt_version => |v| writeU32(bytes[0..4], v),
        .num_tables => |v| writeU16(bytes[4..6], v),
        .record => |r| {
            const i = recordIndex(records, r.tag);
            switch (r.field) {
                .checksum => records[i].checksum = r.value,
                .offset => records[i].offset = r.value,
                .length => records[i].length = r.value,
            }
            writeRecord(bytes, i, records[i]);
        },
        .move_record => |m| {
            const i = recordIndex(records, m.tag);
            records[i].offset +%= m.delta;
            writeRecord(bytes, i, records[i]);
        },
        .copy_offset => |c| {
            const i = recordIndex(records, c.tag);
            records[i].offset = records[recordIndex(records, c.from)].offset;
            writeRecord(bytes, i, records[i]);
        },
        .swap_records => |pair| {
            const a = recordIndex(records, pair[0]);
            const b = recordIndex(records, pair[1]);
            std.mem.swap(Record, &records[a], &records[b]);
            writeRecord(bytes, a, records[a]);
            writeRecord(bytes, b, records[b]);
        },
        .checksum_adjustment => |v| writeU32(bytes[head_offset.? + 8 ..][0..4], v),
        .flip_byte => |f| bytes[offsets[tableIndex(tables, f.tag)] + f.offset] ^= 0xFF,
    }
}

/// The directory byte position of the first record with `tag` in a built font.
pub fn recordPosition(bytes: []const u8, tag: Tag) usize {
    const count = readU16(bytes, 4);
    for (0..count) |i| {
        const at = 12 + 16 * i;
        if (std.mem.eql(u8, bytes[at..][0..4], &tag)) return at;
    }
    unreachable;
}

/// The offset field of record `tag` in a built font.
pub fn recordOffset(bytes: []const u8, tag: Tag) u32 {
    return readU32(bytes, recordPosition(bytes, tag) + 8);
}

/// Sets one field of record `tag` in a built font, without recomputing anything.
pub fn setRecord(bytes: []u8, tag: Tag, field: RecordField, value: u32) void {
    const at = recordPosition(bytes, tag) + @as(usize, switch (field) {
        .checksum => 4,
        .offset => 8,
        .length => 12,
    });
    writeU32(bytes[at..][0..4], value);
}

pub fn writeU16(dest: *[2]u8, value: u16) void {
    std.mem.writeInt(u16, dest, value, .big);
}

pub fn writeU32(dest: *[4]u8, value: u32) void {
    std.mem.writeInt(u32, dest, value, .big);
}

pub fn readU16(src: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, src[at..][0..2], .big);
}

pub fn readU32(src: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, src[at..][0..4], .big);
}

/// A big-endian byte writer for table construction.
pub const Writer = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    pub fn u8_(self: *Writer, v: u8) !void {
        try self.bytes.append(self.gpa, v);
    }
    pub fn u16_(self: *Writer, v: u16) !void {
        var b: [2]u8 = undefined;
        writeU16(&b, v);
        try self.bytes.appendSlice(self.gpa, &b);
    }
    pub fn i16_(self: *Writer, v: i16) !void {
        try self.u16_(@bitCast(v));
    }
    pub fn u32_(self: *Writer, v: u32) !void {
        var b: [4]u8 = undefined;
        writeU32(&b, v);
        try self.bytes.appendSlice(self.gpa, &b);
    }
    pub fn raw(self: *Writer, v: []const u8) !void {
        try self.bytes.appendSlice(self.gpa, v);
    }
    pub fn len(self: *const Writer) usize {
        return self.bytes.items.len;
    }
    pub fn patchU16(self: *Writer, at: usize, v: u16) void {
        writeU16(self.bytes.items[at..][0..2], v);
    }
    pub fn patchU32(self: *Writer, at: usize, v: u32) void {
        writeU32(self.bytes.items[at..][0..4], v);
    }
    pub fn finish(self: *Writer) ![]u8 {
        return self.bytes.toOwnedSlice(self.gpa);
    }
};

// The frozen values of B_TT and B_CFF.
pub const units_per_em: u16 = 1000;
pub const tt_bbox = [4]i16{ 10, 0, 590, 700 };
pub const ascender: i16 = 800;
pub const descender: i16 = -200;
pub const line_gap: i16 = 0;
pub const advance_width_max: u16 = 600;
pub const tt_metrics = [_][2]i16{ .{ 500, 50 }, .{ 250, 0 }, .{ 600, 10 } };
pub const tt_trailing_lsb: i16 = 10;
pub const os2_version: u16 = 4;
pub const os2_weight: u16 = 400;
pub const os2_typo = [3]i16{ 800, -200, 0 };
pub const os2_win = [2]u16{ 800, 200 };
pub const post_underline_position: i16 = -100;
pub const post_underline_thickness: i16 = 50;
pub const name_family = "FP Min";
pub const name_subfamily = "Regular";
pub const cff_font_name = "FPMinCFF";
pub const glyph_boxes = [_][4]i16{ .{ 50, 0, 450, 700 }, .{ 0, 0, 0, 0 }, .{ 10, 0, 590, 700 }, .{ 10, 0, 590, 700 } };

fn utf16be(gpa: Allocator, ascii: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, ascii.len * 2);
    for (ascii, 0..) |c, i| {
        out[2 * i] = 0;
        out[2 * i + 1] = c;
    }
    return out;
}

/// `name` format 0 with (3, 1, 0x409, 1) "FP Min" and (3, 1, 0x409, 2) "Regular".
pub fn nameTable(gpa: Allocator) ![]u8 {
    const family = try utf16be(gpa, name_family);
    defer gpa.free(family);
    const subfamily = try utf16be(gpa, name_subfamily);
    defer gpa.free(subfamily);
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(0);
    try w.u16_(2);
    try w.u16_(6 + 2 * 12);
    for ([_]struct { id: u16, len: usize, off: usize }{
        .{ .id = 1, .len = family.len, .off = 0 },
        .{ .id = 2, .len = subfamily.len, .off = family.len },
    }) |r| {
        try w.u16_(3);
        try w.u16_(1);
        try w.u16_(0x409);
        try w.u16_(r.id);
        try w.u16_(@intCast(r.len));
        try w.u16_(@intCast(r.off));
    }
    try w.raw(family);
    try w.raw(subfamily);
    return w.finish();
}

/// `OS/2` version 4, 96 bytes.
pub fn os2Table(gpa: Allocator) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(os2_version);
    try w.i16_(450); // xAvgCharWidth
    try w.u16_(os2_weight);
    try w.u16_(5); // usWidthClass
    try w.u16_(0); // fsType
    for ([_]i16{ 650, 600, 0, 75, 650, 600, 0, 350, 50, 250 }) |v| try w.i16_(v); // subscript, superscript, strikeout
    try w.i16_(0); // sFamilyClass
    try w.raw(&.{ 2, 11, 5, 2, 4, 5, 4, 2, 2, 4 }); // panose
    for ([_]u32{ 1, 0, 0, 0 }) |v| try w.u32_(v); // ulUnicodeRange1-4
    try w.raw("NONE");
    try w.u16_(0x40); // fsSelection
    try w.u16_(0x20); // usFirstCharIndex
    try w.u16_(0xFFFF); // usLastCharIndex
    for (os2_typo) |v| try w.i16_(v);
    for (os2_win) |v| try w.u16_(v);
    try w.u32_(1); // ulCodePageRange1
    try w.u32_(0); // ulCodePageRange2
    try w.i16_(500); // sxHeight
    try w.i16_(700); // sCapHeight
    try w.u16_(0); // usDefaultChar
    try w.u16_(0x20); // usBreakChar
    try w.u16_(1); // usMaxContext
    std.debug.assert(w.len() == 96);
    return w.finish();
}

/// `post` version 3.0, 32 bytes.
pub fn postTable(gpa: Allocator) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u32_(0x00030000);
    try w.u32_(0); // italicAngle
    try w.i16_(post_underline_position);
    try w.i16_(post_underline_thickness);
    for (0..5) |_| try w.u32_(0); // isFixedPitch and memory fields
    std.debug.assert(w.len() == 32);
    return w.finish();
}

/// `head`, 54 bytes, with checksumAdjustment zero.
pub fn headTable(gpa: Allocator, bbox: [4]i16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(1);
    try w.u16_(0);
    try w.u32_(0x00010000); // fontRevision
    try w.u32_(0); // checksumAdjustment
    try w.u32_(0x5F0F3CF5);
    try w.u16_(0x000B); // flags
    try w.u16_(units_per_em);
    try w.u32_(0); // created
    try w.u32_(0);
    try w.u32_(0); // modified
    try w.u32_(0);
    for (bbox) |v| try w.i16_(v);
    try w.u16_(0); // macStyle
    try w.u16_(8); // lowestRecPPEM
    try w.i16_(2); // fontDirectionHint
    try w.i16_(0); // indexToLocFormat: short
    try w.i16_(0); // glyphDataFormat
    std.debug.assert(w.len() == 54);
    return w.finish();
}

/// `hhea`, 36 bytes.
pub fn hheaTable(gpa: Allocator, number_of_h_metrics: u16, x_max_extent: i16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(1);
    try w.u16_(0);
    try w.i16_(ascender);
    try w.i16_(descender);
    try w.i16_(line_gap);
    try w.u16_(advance_width_max);
    try w.i16_(0); // minLeftSideBearing
    try w.i16_(0); // minRightSideBearing
    try w.i16_(x_max_extent);
    try w.i16_(1); // caretSlopeRise
    try w.i16_(0); // caretSlopeRun
    try w.i16_(0); // caretOffset
    for (0..4) |_| try w.i16_(0);
    try w.i16_(0); // metricDataFormat
    try w.u16_(number_of_h_metrics);
    std.debug.assert(w.len() == 36);
    return w.finish();
}

pub const Segment = struct { start: u16, end: u16, delta: u16, range_offset: u16 = 0 };

/// A cmap format 4 subtable from explicit segments; `glyph_ids` follows idRangeOffset.
pub fn format4(gpa: Allocator, segments: []const Segment, glyph_ids: []const u16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    const seg_count: u16 = @intCast(segments.len);
    var power: u16 = 1;
    var log2: u16 = 0;
    while (power * 2 <= seg_count) : (log2 += 1) power *= 2;
    try w.u16_(4);
    try w.u16_(@intCast(16 + 8 * segments.len + 2 * glyph_ids.len));
    try w.u16_(0); // language
    try w.u16_(seg_count * 2);
    try w.u16_(power * 2);
    try w.u16_(log2);
    try w.u16_(seg_count * 2 - power * 2);
    for (segments) |s| try w.u16_(s.end);
    try w.u16_(0); // reservedPad
    for (segments) |s| try w.u16_(s.start);
    for (segments) |s| try w.u16_(s.delta);
    for (segments) |s| try w.u16_(s.range_offset);
    for (glyph_ids) |g| try w.u16_(g);
    return w.finish();
}

pub const Group = struct { start: u32, end: u32, glyph: u32 };

pub fn format12(gpa: Allocator, groups: []const Group) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(12);
    try w.u16_(0);
    try w.u32_(@intCast(16 + 12 * groups.len));
    try w.u32_(0); // language
    try w.u32_(@intCast(groups.len));
    for (groups) |g| {
        try w.u32_(g.start);
        try w.u32_(g.end);
        try w.u32_(g.glyph);
    }
    return w.finish();
}

pub const EncodingRecord = struct { platform: u16, encoding: u16, subtable: usize };

/// A cmap table; each record points at one of `subtables`, laid out in order after the records.
pub fn cmapTable(gpa: Allocator, records: []const EncodingRecord, subtables: []const []const u8) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u16_(0);
    try w.u16_(@intCast(records.len));
    var offsets: [8]u32 = undefined;
    var at: u32 = @intCast(4 + 8 * records.len);
    for (subtables, 0..) |s, i| {
        offsets[i] = at;
        at += @intCast(s.len);
    }
    for (records) |r| {
        try w.u16_(r.platform);
        try w.u16_(r.encoding);
        try w.u32_(offsets[r.subtable]);
    }
    for (subtables) |s| try w.raw(s);
    return w.finish();
}

/// The B_TT format 4 subtable: U+0020 to glyph 1 and U+0041 to glyph 2.
pub fn ttFormat4(gpa: Allocator) ![]u8 {
    return format4(gpa, &.{
        .{ .start = 0x20, .end = 0x20, .delta = 1 -% @as(u16, 0x20) },
        .{ .start = 0x41, .end = 0x41, .delta = 2 -% @as(u16, 0x41) },
        .{ .start = 0xFFFF, .end = 0xFFFF, .delta = 1 },
    }, &.{});
}

pub fn ttFormat12(gpa: Allocator) ![]u8 {
    return format12(gpa, &.{
        .{ .start = 0x20, .end = 0x20, .glyph = 1 },
        .{ .start = 0x41, .end = 0x41, .glyph = 2 },
        .{ .start = 0x1F600, .end = 0x1F600, .glyph = 3 },
    });
}

/// The B_TT cmap: (0, 3) and (3, 1) share the format 4 subtable at offset 28; (3, 10) format 12 follows at 68.
pub fn ttCmap(gpa: Allocator, f4: []const u8, f12: []const u8) ![]u8 {
    return cmapTable(gpa, &.{
        .{ .platform = 0, .encoding = 3, .subtable = 0 },
        .{ .platform = 3, .encoding = 1, .subtable = 0 },
        .{ .platform = 3, .encoding = 10, .subtable = 1 },
    }, &.{ f4, f12 });
}

pub const tt_cmap_format4_offset = 28;
pub const tt_cmap_format12_offset = 68;

/// One simple glyph whose points all lie on the curve, with 16-bit coordinate deltas.
fn simpleGlyph(w: *Writer, bbox: [4]i16, points: []const [2]i16) !void {
    try w.i16_(1);
    for (bbox) |v| try w.i16_(v);
    try w.u16_(@intCast(points.len - 1)); // endPtsOfContours[0]
    try w.u16_(0); // instructionLength
    for (points) |_| try w.u8_(0x01);
    var previous: i16 = 0;
    for (points) |p| {
        try w.i16_(p[0] - previous);
        previous = p[0];
    }
    previous = 0;
    for (points) |p| {
        try w.i16_(p[1] - previous);
        previous = p[1];
    }
}

/// Glyph offsets inside the B_TT `glyf` table.
pub const tt_glyph_offsets = [_]u16{ 0, 34, 34, 64, 80 };

/// `glyf`: a box, an empty glyph, a triangle, and a composite of glyph 2.
pub fn glyfTable(gpa: Allocator) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try simpleGlyph(&w, glyph_boxes[0], &.{ .{ 50, 0 }, .{ 50, 700 }, .{ 450, 700 }, .{ 450, 0 } });
    std.debug.assert(w.len() == tt_glyph_offsets[1]);
    try simpleGlyph(&w, glyph_boxes[2], &.{ .{ 10, 0 }, .{ 300, 700 }, .{ 590, 0 } });
    try w.u8_(0); // pad to an even length for the short loca format
    std.debug.assert(w.len() == tt_glyph_offsets[3]);
    try w.i16_(-1);
    for (glyph_boxes[3]) |v| try w.i16_(v);
    try w.u16_(0x0002); // ARGS_ARE_XY_VALUES with byte arguments
    try w.u16_(2);
    try w.u8_(0);
    try w.u8_(0);
    std.debug.assert(w.len() == tt_glyph_offsets[4]);
    return w.finish();
}

pub fn locaTable(gpa: Allocator) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    for (tt_glyph_offsets) |o| try w.u16_(o / 2);
    return w.finish();
}

pub fn hmtxTable(gpa: Allocator, metrics: []const [2]i16, trailing: []const i16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    for (metrics) |m| {
        try w.u16_(@intCast(m[0]));
        try w.i16_(m[1]);
    }
    for (trailing) |lsb| try w.i16_(lsb);
    return w.finish();
}

pub fn maxpV1(gpa: Allocator, num_glyphs: u16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u32_(0x00010000);
    try w.u16_(num_glyphs);
    for ([_]u16{ 4, 1, 3, 1, 2, 0, 0, 0, 0, 0, 0, 1, 1 }) |v| try w.u16_(v);
    std.debug.assert(w.len() == 32);
    return w.finish();
}

pub fn maxpV05(gpa: Allocator, num_glyphs: u16) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.u32_(0x00005000);
    try w.u16_(num_glyphs);
    return w.finish();
}

pub const LayoutSpec = struct {
    minor: u16 = 0,
    scripts: []const Tag,
    features: []const Tag = &.{},
    lookups: u16 = 0,
    /// For version 1.1: the FeatureVariations offset, written as given.
    feature_variations: u32 = 0,
};

/// Field offsets of a table that `layoutTable` wrote.
pub const LayoutOffsets = struct { script_list: u16, feature_list: u16, lookup_list: u16 };

pub fn layoutOffsets(table: []const u8) LayoutOffsets {
    return .{ .script_list = readU16(table, 4), .feature_list = readU16(table, 6), .lookup_list = readU16(table, 8) };
}

/// A GSUB or GPOS table. Each script has a default LangSys with no features.
/// Each feature lists no lookup, and each lookup is type 1 with no subtable.
pub fn layoutTable(gpa: Allocator, spec: LayoutSpec) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    const header_len: u16 = if (spec.minor == 1) 14 else 10;
    try w.u16_(1);
    try w.u16_(spec.minor);
    try w.u16_(0);
    try w.u16_(0);
    try w.u16_(0);
    if (spec.minor == 1) try w.u32_(spec.feature_variations);
    std.debug.assert(w.len() == header_len);

    // ScriptList, then each Script table with its default LangSys.
    const script_list = w.len();
    w.patchU16(4, @intCast(script_list));
    try w.u16_(@intCast(spec.scripts.len));
    const script_records = w.len();
    for (spec.scripts) |tag| {
        try w.raw(&tag);
        try w.u16_(0);
    }
    for (0..spec.scripts.len) |i| {
        w.patchU16(script_records + 6 * i + 4, @intCast(w.len() - script_list));
        try w.u16_(4); // defaultLangSysOffset
        try w.u16_(0); // langSysCount
        try w.u16_(0); // lookupOrderOffset
        try w.u16_(0xFFFF); // requiredFeatureIndex
        try w.u16_(0); // featureIndexCount
    }

    const feature_list = w.len();
    w.patchU16(6, @intCast(feature_list));
    try w.u16_(@intCast(spec.features.len));
    const feature_records = w.len();
    for (spec.features) |tag| {
        try w.raw(&tag);
        try w.u16_(0);
    }
    for (0..spec.features.len) |i| {
        w.patchU16(feature_records + 6 * i + 4, @intCast(w.len() - feature_list));
        try w.u16_(0); // featureParamsOffset
        try w.u16_(0); // lookupIndexCount
    }

    const lookup_list = w.len();
    w.patchU16(8, @intCast(lookup_list));
    try w.u16_(spec.lookups);
    const lookup_records = w.len();
    for (0..spec.lookups) |_| try w.u16_(0);
    for (0..spec.lookups) |i| {
        w.patchU16(lookup_records + 2 * i, @intCast(w.len() - lookup_list));
        try w.u16_(1); // lookupType
        try w.u16_(0); // lookupFlag
        try w.u16_(0); // subTableCount
    }
    return w.finish();
}

/// A GDEF header of `len` bytes (12, 14, or 18) with every offset null.
pub fn gdefTable(gpa: Allocator, minor: u16, len: usize) ![]u8 {
    const out = try gpa.alloc(u8, len);
    @memset(out, 0);
    writeU16(out[0..2], 1);
    writeU16(out[2..4], minor);
    return out;
}

pub const CffSpec = struct {
    /// Top DICT bytes before the CharStrings entry.
    prefix: []const u8 = &.{},
    /// Top DICT bytes after the CharStrings entry.
    suffix: []const u8 = &.{},
    charstrings: u16 = 2,
};

/// Offsets inside a CFF table that `cffTable` wrote with an empty prefix and suffix.
pub const cff_name_index = 4;
pub const cff_top_dict_index = 17;
pub const cff_charstrings_operand = cff_top_dict_index + 5 + 1;

/// `CFF `: header `01 00 04 01`, Name INDEX [FPMinCFF], a Top DICT whose CharStrings operand is a 5-byte integer,
/// empty String and Global Subr INDEXes, and a CharStrings INDEX of `0E` charstrings.
pub fn cffTable(gpa: Allocator, spec: CffSpec) ![]u8 {
    var w: Writer = .{ .gpa = gpa };
    errdefer w.bytes.deinit(gpa);
    try w.raw(&.{ 1, 0, 4, 1 });
    // Name INDEX.
    try w.u16_(1);
    try w.u8_(1);
    try w.u8_(1);
    try w.u8_(1 + cff_font_name.len);
    try w.raw(cff_font_name);
    std.debug.assert(w.len() == cff_top_dict_index);
    // Top DICT INDEX.
    const dict_len = spec.prefix.len + 6 + spec.suffix.len;
    try w.u16_(1);
    try w.u8_(1);
    try w.u8_(1);
    try w.u8_(@intCast(1 + dict_len));
    try w.raw(spec.prefix);
    try w.u8_(29);
    const operand = w.len();
    try w.u32_(0);
    try w.u8_(17);
    try w.raw(spec.suffix);
    // String and Global Subr INDEXes.
    try w.u16_(0);
    try w.u16_(0);
    // CharStrings INDEX.
    w.patchU32(operand, @intCast(w.len()));
    try w.u16_(spec.charstrings);
    try w.u8_(1);
    for (0..spec.charstrings + 1) |i| try w.u8_(@intCast(1 + i));
    for (0..spec.charstrings) |_| try w.u8_(0x0E);
    return w.finish();
}

/// B_TT: TrueType with 4 glyphs and the tables GDEF, GPOS, GSUB, OS/2, cmap, glyf, head, hhea, hmtx, loca, maxp, name, and post.
pub fn ttTables(gpa: Allocator) !TableSet {
    var set: TableSet = .{ .gpa = gpa, .sfnt_version = sfnt_truetype };
    errdefer set.deinit();
    try set.putOwned("GDEF".*, try gdefTable(gpa, 0, 12));
    try set.putOwned("GPOS".*, try layoutTable(gpa, .{ .scripts = &.{"latn".*} }));
    try set.putOwned("GSUB".*, try layoutTable(gpa, .{ .scripts = &.{ "DFLT".*, "latn".* } }));
    try set.putOwned("OS/2".*, try os2Table(gpa));
    const f4 = try ttFormat4(gpa);
    defer gpa.free(f4);
    const f12 = try ttFormat12(gpa);
    defer gpa.free(f12);
    try set.putOwned("cmap".*, try ttCmap(gpa, f4, f12));
    try set.putOwned("glyf".*, try glyfTable(gpa));
    try set.putOwned("head".*, try headTable(gpa, tt_bbox));
    try set.putOwned("hhea".*, try hheaTable(gpa, 3, 590));
    try set.putOwned("hmtx".*, try hmtxTable(gpa, &tt_metrics, &.{tt_trailing_lsb}));
    try set.putOwned("loca".*, try locaTable(gpa));
    try set.putOwned("maxp".*, try maxpV1(gpa, 4));
    try set.putOwned("name".*, try nameTable(gpa));
    try set.putOwned("post".*, try postTable(gpa));
    return set;
}

/// B_CFF: OTTO with 2 glyphs and the tables CFF, OS/2, cmap, head, hhea, hmtx, maxp 0.5, name, and post 3.0.
pub fn cffTables(gpa: Allocator) !TableSet {
    var set: TableSet = .{ .gpa = gpa, .sfnt_version = sfnt_cff };
    errdefer set.deinit();
    try set.putOwned("CFF ".*, try cffTable(gpa, .{}));
    try set.putOwned("OS/2".*, try os2Table(gpa));
    const f4 = try format4(gpa, &.{
        .{ .start = 0x41, .end = 0x41, .delta = 1 -% @as(u16, 0x41) },
        .{ .start = 0xFFFF, .end = 0xFFFF, .delta = 1 },
    }, &.{});
    defer gpa.free(f4);
    try set.putOwned("cmap".*, try cmapTable(gpa, &.{.{ .platform = 3, .encoding = 1, .subtable = 0 }}, &.{f4}));
    try set.putOwned("head".*, try headTable(gpa, .{ 0, 0, 600, 700 }));
    try set.putOwned("hhea".*, try hheaTable(gpa, 2, 600));
    try set.putOwned("hmtx".*, try hmtxTable(gpa, &.{ .{ 500, 0 }, .{ 600, 0 } }, &.{}));
    try set.putOwned("maxp".*, try maxpV05(gpa, 2));
    try set.putOwned("name".*, try nameTable(gpa));
    try set.putOwned("post".*, try postTable(gpa));
    return set;
}

/// Builds B_TT with no change.
pub fn bTt(gpa: Allocator) ![]u8 {
    var set = try ttTables(gpa);
    defer set.deinit();
    return set.build(&.{}, &.{});
}

/// Builds B_CFF with no change.
pub fn bCff(gpa: Allocator) ![]u8 {
    var set = try cffTables(gpa);
    defer set.deinit();
    return set.build(&.{}, &.{});
}
