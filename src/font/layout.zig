//! The OpenType `GSUB`, `GPOS`, and `GDEF` table headers and the common ScriptList, FeatureList, and LookupList formats.
//! No lookup is interpreted. Source: the OpenType `chapter2` (layout common table formats), `gsub`, `gpos`, and `gdef` chapters.

const std = @import("std");
const Reader = @import("reader.zig").Reader;
const tables = @import("tables.zig");
const TableStatus = tables.TableStatus;

pub const Layout = struct {
    table: Reader,
    /// Major version in the high 16 bits and minor version in the low 16 bits.
    version: u32,
    script_list: u16,
    feature_list: u16,
    lookup_list: u16,

    fn listCount(self: Layout, list: u16) u16 {
        return if (list == 0) 0 else self.table.u16At(list).?;
    }

    pub fn scriptCount(self: Layout) u16 {
        return self.listCount(self.script_list);
    }

    pub fn scriptTag(self: Layout, i: u16) [4]u8 {
        std.debug.assert(i < self.scriptCount());
        return self.table.tagAt(@as(u64, self.script_list) + 2 + 6 * @as(u64, i)).?;
    }

    /// The number of features, in FeatureList order.
    pub fn featureCount(self: Layout) u16 {
        return self.listCount(self.feature_list);
    }

    pub fn featureTag(self: Layout, i: u16) [4]u8 {
        std.debug.assert(i < self.featureCount());
        return self.table.tagAt(@as(u64, self.feature_list) + 2 + 6 * @as(u64, i)).?;
    }

    pub fn lookupCount(self: Layout) u16 {
        return self.listCount(self.lookup_list);
    }
};

/// Checks a list of `count` records of `record_size` bytes that starts at `list`, and that each record's 16-bit offset,
/// at `offset_at` inside the record and relative to the list, falls inside the table.
fn checkList(t: Reader, list: u16, record_size: u64, offset_at: u64, comptime sorted_tags: bool) ?tables.Defect {
    if (list == 0) return null;
    const count = t.u16At(list).?;
    if (!t.fits(@as(u64, list) + 2, record_size * count)) return .count_out_of_bounds;
    var previous: [4]u8 = undefined;
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const record = @as(u64, list) + 2 + record_size * i;
        if (sorted_tags) {
            const tag = t.tagAt(record).?;
            if (i > 0 and std.mem.order(u8, &previous, &tag) != .lt) return .unsorted_records;
            previous = tag;
        }
        if (@as(u64, list) + t.u16At(record + offset_at).? >= t.len()) return .offset_out_of_bounds;
    }
    return null;
}

/// Versions 1.0 and 1.1 with every list offset, record array, and Script, Feature, and Lookup offset inside the table.
pub fn parseLayout(t: Reader) TableStatus(Layout) {
    const major = t.u16At(0) orelse return .{ .rejected = .too_short };
    const minor = t.u16At(2) orelse return .{ .rejected = .too_short };
    const version = (@as(u32, major) << 16) | minor;
    if (major != 1 or minor > 1) return .{ .unsupported_version = version };
    if (t.len() < @as(u64, if (minor == 1) 14 else 10)) return .{ .rejected = .too_short };
    const layout: Layout = .{ .table = t, .version = version, .script_list = t.u16At(4).?, .feature_list = t.u16At(6).?, .lookup_list = t.u16At(8).? };
    // A nonnull list offset must leave room for the list's count.
    for ([_]u16{ layout.script_list, layout.feature_list, layout.lookup_list }) |list| {
        if (list != 0 and !t.fits(list, 2)) return .{ .rejected = .offset_out_of_bounds };
    }
    if (minor == 1) {
        const variations = t.u32At(10).?;
        if (variations != 0 and variations >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    if (checkList(t, layout.script_list, 6, 4, true)) |defect| return .{ .rejected = defect };
    if (checkList(t, layout.feature_list, 6, 4, false)) |defect| return .{ .rejected = defect };
    if (checkList(t, layout.lookup_list, 2, 0, false)) |defect| return .{ .rejected = defect };
    return .{ .valid = layout };
}

pub const Gdef = struct {
    /// Major version in the high 16 bits and minor version in the low 16 bits.
    version: u32,
    glyph_class_def: u16,
    attach_list: u16,
    lig_caret_list: u16,
    mark_attach_class_def: u16,
    /// Version 1.2 and later.
    mark_glyph_sets_def: ?u16,
    /// Version 1.3.
    item_var_store: ?u32,
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
    const gdef: Gdef = .{
        .version = version,
        .glyph_class_def = t.u16At(4).?,
        .attach_list = t.u16At(6).?,
        .lig_caret_list = t.u16At(8).?,
        .mark_attach_class_def = t.u16At(10).?,
        .mark_glyph_sets_def = if (header >= 14) t.u16At(12).? else null,
        .item_var_store = if (header >= 18) t.u32At(14).? else null,
    };
    for ([_]u64{ gdef.glyph_class_def, gdef.attach_list, gdef.lig_caret_list, gdef.mark_attach_class_def, gdef.mark_glyph_sets_def orelse 0, gdef.item_var_store orelse 0 }) |offset| {
        if (offset != 0 and offset >= t.len()) return .{ .rejected = .offset_out_of_bounds };
    }
    return .{ .valid = gdef };
}
