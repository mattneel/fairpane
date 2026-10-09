//! The OpenType `GDEF` table: the header, the glyph class and mark attachment class definitions, the mark glyph sets,
//! and the ligature caret list, which `layout.zig` re-exports. AttachList is not parsed. Source: the OpenType 1.9.1 `gdef` chapter.
//! Each method opens its structure again and checks it in time linear in that structure's length.
//! Device and VariationIndex data and the item variation store are reported, never applied.

const Reader = @import("reader.zig").Reader;
const tables = @import("tables.zig");
const TableStatus = tables.TableStatus;
const common = @import("layout_common.zig");
const Coverage = common.Coverage;
const ClassDef = common.ClassDef;
const DeviceStatus = common.DeviceStatus;

pub const Gdef = struct {
    table: Reader,
    /// Major version in the high 16 bits and minor version in the low 16 bits.
    version: u32,
    glyph_class_def: u16,
    attach_list: u16,
    lig_caret_list: u16,
    mark_attach_class_def: u16,
    /// Version 1.2 and later.
    mark_glyph_sets_def: ?u16,
    /// Version 1.3. A nonzero value names an item variation store, which is not applied.
    item_var_store: ?u32,

    /// The GlyphClassDef table, or `.absent` for a NULL offset.
    pub fn glyphClasses(self: Gdef) TableStatus(ClassDef) {
        if (self.glyph_class_def == 0) return .absent;
        return common.parseClassDef(self.table, self.glyph_class_def);
    }

    /// The MarkAttachClassDef table, or `.absent` for a NULL offset.
    pub fn markAttachClasses(self: Gdef) TableStatus(ClassDef) {
        if (self.mark_attach_class_def == 0) return .absent;
        return common.parseClassDef(self.table, self.mark_attach_class_def);
    }

    /// The MarkGlyphSets table, or `.absent` for version 1.0 or a NULL offset. Format 1 needs its Offset32 coverage offsets.
    pub fn markGlyphSets(self: Gdef) TableStatus(MarkGlyphSets) {
        const at: u64 = self.mark_glyph_sets_def orelse return .absent;
        if (at == 0) return .absent;
        const header = self.table.fixed(4, at) orelse return .{ .rejected = .too_short };
        const format = header.int(u16, 0);
        if (format != 1) return .{ .unsupported_version = format };
        const count = header.int(u16, 2);
        if (!self.table.fits(at + 4, 4 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
        return .{ .valid = .{ .count = count, .table = self.table, .offset = at } };
    }

    /// The LigCaretList table, or `.absent` for a NULL offset. It needs its header, its LigGlyph offsets, a valid Coverage,
    /// and every LigGlyph offset nonnull and inside the table.
    pub fn ligatureCaretList(self: Gdef) TableStatus(LigCaretList) {
        if (self.lig_caret_list == 0) return .absent;
        const t = self.table;
        const at: u64 = self.lig_caret_list;
        const header = t.fixed(4, at) orelse return .{ .rejected = .too_short };
        const coverage_offset = header.int(u16, 0);
        const count = header.int(u16, 2);
        if (!t.fits(at + 4, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
        if (coverage_offset == 0) return .{ .rejected = .null_offset };
        const coverage = switch (common.parseCoverage(t, at + coverage_offset)) {
            .valid => |c| c,
            .rejected => |defect| return .{ .rejected = defect },
            .unsupported_version => |format| return .{ .unsupported_version = format },
            .absent => unreachable, // parseCoverage never reports an absent table.
        };
        var k: u64 = 0;
        while (k < count) : (k += 1) {
            const offset = t.u16At(at + 4 + 2 * k) orelse return .{ .rejected = .count_out_of_bounds };
            if (offset == 0) return .{ .rejected = .null_offset };
            if (at + offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
        }
        return .{ .valid = .{ .table = t, .offset = at, .coverage = coverage, .lig_glyph_count = count } };
    }
};

/// Versions 1.0 (12 bytes), 1.2 (14), and 1.3 (18), with every nonnull offset inside the table.
pub fn parseGdef(t: Reader) TableStatus(Gdef) {
    const major = t.u16At(0) orelse return .{ .rejected = .too_short };
    const minor = t.u16At(2) orelse return .{ .rejected = .too_short };
    const version = (@as(u32, major) << 16) | minor;
    const header: u64 = switch (version) {
        0x00010000 => 12,
        0x00010002 => 14,
        0x00010003 => 18,
        else => return .{ .unsupported_version = version },
    };
    if (t.len() < header) return .{ .rejected = .too_short };
    const h = t.fixed(12, 0) orelse return .{ .rejected = .too_short };
    const gdef: Gdef = .{
        .table = t,
        .version = version,
        .glyph_class_def = h.int(u16, 4),
        .attach_list = h.int(u16, 6),
        .lig_caret_list = h.int(u16, 8),
        .mark_attach_class_def = h.int(u16, 10),
        .mark_glyph_sets_def = if (header >= 14) t.u16At(12) orelse return .{ .rejected = .too_short } else null,
        .item_var_store = if (header >= 18) t.u32At(14) orelse return .{ .rejected = .too_short } else null,
    };
    for ([_]u64{ gdef.glyph_class_def, gdef.attach_list, gdef.lig_caret_list, gdef.mark_attach_class_def, gdef.mark_glyph_sets_def orelse 0, gdef.item_var_store orelse 0 }) |offset| {
        if (offset != 0 and offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    return .{ .valid = gdef };
}

/// A MarkGlyphSets table whose header and coverage offsets `Gdef.markGlyphSets` checked.
pub const MarkGlyphSets = struct {
    count: u16,
    table: Reader,
    offset: u64,

    /// Mark glyph set `i`, or null when `i` is at or past `count`. A NULL coverage offset is `null_offset`.
    pub fn set(self: MarkGlyphSets, i: u16) ?TableStatus(Coverage) {
        if (i >= self.count) return null;
        const offset = self.table.u32At(self.offset + 4 + 4 * @as(u64, i)) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        return common.parseCoverage(self.table, self.offset + offset);
    }
};

/// A LigCaretList table that `Gdef.ligatureCaretList` checked.
pub const LigCaretList = struct {
    table: Reader,
    offset: u64,
    coverage: Coverage,
    lig_glyph_count: u16,

    /// The carets of ligature `glyph`. A glyph whose Coverage Index is at or past ligGlyphCount is `index_out_of_range`.
    pub fn carets(self: LigCaretList, glyph: u16) CaretsStatus {
        const t = self.table;
        const index = self.coverage.index(glyph) orelse return .not_covered;
        if (index >= self.lig_glyph_count) return .{ .rejected = .index_out_of_range };
        const offset = t.u16At(self.offset + 4 + 2 * @as(u64, index)) orelse return .{ .rejected = .count_out_of_bounds };
        if (offset == 0) return .{ .rejected = .null_offset };
        const at = self.offset + offset;
        if (at >= t.len()) return .{ .rejected = .offset_out_of_bounds };
        const count = t.u16At(at) orelse return .{ .rejected = .too_short };
        if (!t.fits(at + 2, 2 * @as(u64, count))) return .{ .rejected = .count_out_of_bounds };
        return .{ .valid = .{ .caret_count = count, .table = t, .offset = at } };
    }
};

pub const CaretsStatus = union(enum) { not_covered, rejected: tables.Defect, valid: LigGlyph };

/// A LigGlyph table whose caret offsets `LigCaretList.carets` checked.
pub const LigGlyph = struct {
    caret_count: u16,
    table: Reader,
    offset: u64,

    /// CaretValue `k`, or null when `k` is at or past `caret_count`.
    pub fn caret(self: LigGlyph, k: u16) ?CaretStatus {
        if (k >= self.caret_count) return null;
        const t = self.table;
        const offset = t.u16At(self.offset + 2 + 2 * @as(u64, k)) orelse return .{ .rejected = .too_short };
        if (offset == 0) return .{ .rejected = .null_offset };
        const at = self.offset + offset;
        const format = t.u16At(at) orelse return .{ .rejected = .too_short };
        return switch (format) {
            1 => .{ .valid = .{ .coordinate = t.i16At(at + 2) orelse return .{ .rejected = .too_short } } },
            2 => .{ .valid = .{ .point = t.u16At(at + 2) orelse return .{ .rejected = .too_short } } },
            3 => {
                const value = t.fixed(6, at) orelse return .{ .rejected = .too_short };
                const device = value.int(u16, 4);
                return .{ .valid = .{ .coordinate_device = .{
                    .coordinate = value.int(i16, 2),
                    .device = if (device == 0) null else common.parseDevice(t, at + device),
                } } };
            },
            else => .{ .unsupported_format = format },
        };
    }
};

pub const CaretStatus = union(enum) { rejected: tables.Defect, unsupported_format: u16, valid: CaretValue };

pub const CaretValue = union(enum) {
    /// Format 1, in design units.
    coordinate: i16,
    /// Format 2, a contour point index.
    point: u16,
    /// Format 3. `device` is null for a NULL offset; a Device or VariationIndex table is reported, never applied.
    coordinate_device: struct { coordinate: i16, device: ?DeviceStatus },
};
